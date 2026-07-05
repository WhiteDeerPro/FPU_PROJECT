//============================================================================
// Interleaved divide unit built from a reciprocal seed and one private FMA pipe.
//
// The unit keeps six in-flight divide contexts, enough to keep the current
// five-cycle FMA pipe busy with one micro-op per cycle after warm-up. `ready_o`
// is high when a context slot is free; requests asserted while `ready_o` is low
// are ignored by this unit and must be held by the caller.
//
// Finite path is computed in mantissa space to avoid constructing a full
// IEEE-754 1/b intermediate:
//   ma = normalized significand(a) in [1, 2)
//   mb = normalized significand(b) in [1, 2)
//   x0 = recip_seed(mb)
//   e  = 1.0 - mb*x
//   x' = x + x*e
//   S-format uses 2 NR rounds; D-format uses 3 NR rounds.
//   q0 = signed(ma)*signed(x)
//   r  = signed(ma) - signed(mb)*q0
//   q  = q0 + r*signed(x)
//   result_exp = exponent(a) - exponent(b) + exponent(q)
//============================================================================

module fpu_div_unit_pipe
  import fpu_pkg::*;
(
  input  logic      clk_i,
  input  logic      rst_ni,
  input  logic      valid_i,
  input  fpu_req_t  req_i,
  output logic      ready_o,
  output logic      valid_o,
  output fpu_resp_t resp_o,
  output logic      valid_op_o
);

  localparam int unsigned NUM_CTX     = 6;
  localparam int unsigned FMA_LATENCY = 5;
  localparam int signed   S_EXP_BIAS  = 127;
  localparam int signed   D_EXP_BIAS  = 1023;

  typedef enum logic [2:0] {
    MICRO_E,
    MICRO_X,
    MICRO_Q,
    MICRO_R,
    MICRO_FINAL
  } micro_op_e;

  typedef struct packed {
    logic               sign;
    logic               is_zero;
    logic               is_inf;
    logic               is_nan;
    logic               is_snan;
    logic [11:0]        sig_hi;
    logic [52:0]        sig_norm;
    logic signed [15:0] unbiased_exp;
  } fp_div_operand_t;

  logic [NUM_CTX-1:0] ctx_active;
  logic [NUM_CTX-1:0] ctx_ready;
  logic [NUM_CTX-1:0] ctx_done;
  logic [NUM_CTX-1:0] ctx_valid_op;

  micro_op_e          ctx_step       [NUM_CTX];
  fpu_req_t           ctx_req        [NUM_CTX];
  fpu_data_t          ctx_a_mant     [NUM_CTX];
  fpu_data_t          ctx_b_mant_abs [NUM_CTX];
  fpu_data_t          ctx_b_mant     [NUM_CTX];
  fpu_data_t          ctx_x          [NUM_CTX];
  fpu_data_t          ctx_e          [NUM_CTX];
  fpu_data_t          ctx_q          [NUM_CTX];
  fpu_data_t          ctx_r          [NUM_CTX];
  fpu_resp_t          ctx_resp       [NUM_CTX];
  logic signed [15:0] ctx_exp_delta  [NUM_CTX];
  logic [2:0]         ctx_iter       [NUM_CTX];
  logic [2:0]         ctx_iter_limit [NUM_CTX];

  fpu_req_t  fma_req_q;
  logic      fma_valid_q;
  logic [2:0] fma_ctx_q;
  micro_op_e fma_kind_q;
  logic      fma_valid_o;
  fpu_resp_t fma_resp_o;
  logic      fma_valid_op_o;

  logic      ret_valid_pipe [FMA_LATENCY];
  logic [2:0] ret_ctx_pipe  [FMA_LATENCY];
  micro_op_e ret_kind_pipe  [FMA_LATENCY];

  fpu_resp_t resp_q;
  logic      valid_q;
  logic      valid_op_q;

  fp_div_operand_t lhs;
  fp_div_operand_t rhs;
  logic            op_is_div;
  logic            fmt_is_valid;
  logic            rm_is_valid_w;
  logic            normal_finite_div;
  logic            special_valid_op;
  fpu_resp_t       special_resp;

  logic [11:0]        lut_sig_hi;
  logic [15:0]        seed_mant;
  logic signed [15:0] seed_exp;
  logic [15:0]        seed_norm_mant;
  logic signed [15:0] seed_norm_exp;
  fpu_data_t          seed_data;

  logic       free_valid;
  logic [2:0] free_idx;
  logic       issue_valid;
  logic [2:0] issue_ctx;
  fpu_req_t   issue_req;
  micro_op_e  issue_kind;
  logic       done_valid;
  logic [2:0] done_ctx;
  logic       accept_req;

  assign valid_o    = valid_q;
  assign resp_o     = resp_q;
  assign valid_op_o = valid_op_q;
  assign ready_o    = free_valid;
  assign accept_req = valid_i && free_valid;

  fpu_fma_unit_pipe u_fma_pipe (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (fma_valid_q),
    .req_i     (fma_req_q),
    .valid_o   (fma_valid_o),
    .resp_o    (fma_resp_o),
    .valid_op_o(fma_valid_op_o)
  );

  fpu_recip_seed_lut u_seed_lut (
    .sig_hi_i        (lut_sig_hi),
    .exp_i           (16'sd0),
    .mant_seed_o     (seed_mant),
    .exp_seed_o      (seed_exp),
    .norm_mant_seed_o(seed_norm_mant),
    .norm_exp_seed_o (seed_norm_exp)
  );

  function automatic fpu_data_t nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
  endfunction

  function automatic fpu_rm_e effective_rm(input fpu_rm_e rm);
    return (rm == FPU_RM_DYN) ? FPU_RM_RNE : rm;
  endfunction

  function automatic logic rm_is_supported(input fpu_rm_e rm);
    unique case (rm)
      FPU_RM_RNE,
      FPU_RM_RTZ,
      FPU_RM_RDN,
      FPU_RM_RUP,
      FPU_RM_RMM,
      FPU_RM_DYN: return 1'b1;
      default:    return 1'b0;
    endcase
  endfunction

  function automatic logic fmt_supported(input fpu_fmt_e fmt);
    return (fmt == FPU_FMT_S) || (fmt == FPU_FMT_D);
  endfunction

  function automatic logic [5:0] leading_one_53(input logic [52:0] value);
    logic [5:0] pos;

    pos = 6'd0;
    for (int idx = 0; idx < 53; idx++) begin
      if (value[idx]) begin
        pos = idx[5:0];
      end
    end

    return pos;
  endfunction

  function automatic fp_div_operand_t unpack_operand(
    input fpu_data_t data,
    input fpu_fmt_e  fmt
  );
    fp_div_operand_t op;
    logic [31:0]     bits_s;
    logic [63:0]     bits_d;
    logic [52:0]     sig_raw;
    logic [52:0]     sig_norm;
    logic [5:0]      lop_pos;
    logic [5:0]      lshift;

    op       = '0;
    bits_s   = data[31:0];
    bits_d   = data;
    sig_raw  = '0;
    sig_norm = '0;
    lop_pos  = 6'd0;
    lshift   = 6'd0;

    if (fmt == FPU_FMT_S) begin
      op.sign    = bits_s[31];
      op.is_zero = (bits_s[30:0] == 31'd0);
      op.is_inf  = (bits_s[30:23] == 8'hff) && (bits_s[22:0] == 23'd0);
      op.is_nan  = (bits_s[30:23] == 8'hff) && (bits_s[22:0] != 23'd0);
      op.is_snan = op.is_nan && !bits_s[22];

      if ((bits_s[30:23] != 8'd0) && !op.is_inf && !op.is_nan) begin
        sig_norm        = {1'b1, bits_s[22:0], 29'd0};
        op.unbiased_exp = $signed({8'd0, bits_s[30:23]}) - S_EXP_BIAS;
      end else if (!op.is_zero && !op.is_inf && !op.is_nan) begin
        sig_raw         = {1'b0, bits_s[22:0], 29'd0};
        lop_pos         = leading_one_53(sig_raw);
        lshift          = 6'd52 - lop_pos;
        sig_norm        = sig_raw << lshift;
        op.unbiased_exp = -16'sd126 - $signed({10'd0, lshift});
      end
    end else begin
      op.sign    = bits_d[63];
      op.is_zero = (bits_d[62:0] == 63'd0);
      op.is_inf  = (bits_d[62:52] == 11'h7ff) && (bits_d[51:0] == 52'd0);
      op.is_nan  = (bits_d[62:52] == 11'h7ff) && (bits_d[51:0] != 52'd0);
      op.is_snan = op.is_nan && !bits_d[51];

      if ((bits_d[62:52] != 11'd0) && !op.is_inf && !op.is_nan) begin
        sig_norm        = {1'b1, bits_d[51:0]};
        op.unbiased_exp = $signed({5'd0, bits_d[62:52]}) - D_EXP_BIAS;
      end else if (!op.is_zero && !op.is_inf && !op.is_nan) begin
        sig_raw         = {1'b0, bits_d[51:0]};
        lop_pos         = leading_one_53(sig_raw);
        lshift          = 6'd52 - lop_pos;
        sig_norm        = sig_raw << lshift;
        op.unbiased_exp = -16'sd1022 - $signed({10'd0, lshift});
      end
    end

    op.sig_norm = sig_norm;
    op.sig_hi   = sig_norm[52:41];
    return op;
  endfunction

  function automatic fpu_data_t canonical_nan(input fpu_fmt_e fmt);
    if (fmt == FPU_FMT_S) begin
      return nanbox_s(32'h7fc0_0000);
    end

    return 64'h7ff8_0000_0000_0000;
  endfunction

  function automatic fpu_data_t pack_inf(input fpu_fmt_e fmt, input logic sign);
    if (fmt == FPU_FMT_S) begin
      return nanbox_s({sign, 8'hff, 23'd0});
    end

    return {sign, 11'h7ff, 52'd0};
  endfunction

  function automatic fpu_data_t pack_zero(input fpu_fmt_e fmt, input logic sign);
    if (fmt == FPU_FMT_S) begin
      return nanbox_s({sign, 31'd0});
    end

    return {sign, 63'd0};
  endfunction

  function automatic fpu_data_t pack_max_finite(
    input fpu_fmt_e fmt,
    input logic     sign
  );
    if (fmt == FPU_FMT_S) begin
      return nanbox_s({sign, 8'hfe, 23'h7f_ffff});
    end

    return {sign, 11'h7fe, 52'hf_ffff_ffff_ffff};
  endfunction

  function automatic fpu_data_t pack_overflow_result(
    input fpu_fmt_e fmt,
    input logic     sign,
    input fpu_rm_e  rm
  );
    fpu_rm_e rm_eff;
    logic    to_inf;

    rm_eff = effective_rm(rm);
    to_inf = (rm_eff == FPU_RM_RNE) ||
             (rm_eff == FPU_RM_RMM) ||
             ((rm_eff == FPU_RM_RUP) && !sign) ||
             ((rm_eff == FPU_RM_RDN) && sign);
    return to_inf ? pack_inf(fmt, sign) : pack_max_finite(fmt, sign);
  endfunction

  function automatic fpu_data_t pack_one(input fpu_fmt_e fmt);
    if (fmt == FPU_FMT_S) begin
      return nanbox_s(32'h3f80_0000);
    end

    return 64'h3ff0_0000_0000_0000;
  endfunction

  function automatic fpu_data_t mantissa_data(
    input fpu_fmt_e      fmt,
    input logic [52:0]   sig_norm,
    input logic          sign
  );
    if (fmt == FPU_FMT_S) begin
      return nanbox_s({sign, 8'h7f, sig_norm[51:29]});
    end

    return {sign, 11'h3ff, sig_norm[51:0]};
  endfunction

  function automatic fpu_data_t set_sign(
    input fpu_data_t data,
    input fpu_fmt_e  fmt,
    input logic      sign
  );
    fpu_data_t out;

    out = data;
    if (fmt == FPU_FMT_S) begin
      out[31] = sign;
    end else begin
      out[63] = sign;
    end

    return out;
  endfunction

  function automatic fpu_data_t pack_seed_mant(
    input fpu_fmt_e           fmt,
    input logic [15:0]        norm_mant,
    input logic signed [15:0] norm_exp
  );
    logic signed [15:0] biased_exp;

    biased_exp = (fmt == FPU_FMT_S) ? (norm_exp + 16'sd127) :
                                      (norm_exp + 16'sd1023);
    if (fmt == FPU_FMT_S) begin
      return nanbox_s({1'b0, biased_exp[7:0], norm_mant[14:0], 8'd0});
    end

    return {1'b0, biased_exp[10:0], norm_mant[14:0], 37'd0};
  endfunction

  function automatic logic round_inc(
    input fpu_rm_e rm,
    input logic    sign,
    input logic    lsb,
    input logic    guard,
    input logic    round_bit,
    input logic    sticky
  );
    logic any_tail;

    any_tail = guard || round_bit || sticky;
    unique case (effective_rm(rm))
      FPU_RM_RNE: return guard && (round_bit || sticky || lsb);
      FPU_RM_RTZ: return 1'b0;
      FPU_RM_RDN: return sign && any_tail;
      FPU_RM_RUP: return !sign && any_tail;
      FPU_RM_RMM: return guard;
      default:    return guard && (round_bit || sticky || lsb);
    endcase
  endfunction

  function automatic fpu_resp_t scale_s_result(
    input fpu_resp_t          mant_resp,
    input logic signed [15:0] exp_delta,
    input fpu_rm_e            rm
  );
    fpu_resp_t          out;
    logic [31:0]        bits;
    logic               sign;
    logic signed [15:0] final_exp;
    logic [23:0]        sig;
    logic [63:0]        ext;
    logic [63:0]        shifted;
    logic               lost;
    logic [23:0]        main_sig;
    logic [24:0]        rounded;
    logic               inexact;

    out       = mant_resp;
    bits      = mant_resp.result[31:0];
    sign      = bits[31];
    final_exp = $signed({8'd0, bits[30:23]}) + exp_delta;
    sig       = {1'b1, bits[22:0]};
    ext       = {37'd0, sig, 3'd0};
    shifted   = 64'd0;
    lost      = mant_resp.fflags[FPU_FFLAG_NX];
    main_sig  = 24'd0;
    rounded   = 25'd0;
    inexact   = 1'b0;

    if (bits[30:23] == 8'hff) begin
      return mant_resp;
    end

    if (final_exp >= 16'sd255) begin
      out.result = pack_overflow_result(FPU_FMT_S, sign, rm);
      out.fflags[FPU_FFLAG_OF] = 1'b1;
      out.fflags[FPU_FFLAG_NX] = 1'b1;
    end else if (final_exp > 16'sd0) begin
      out.result = nanbox_s({sign, final_exp[7:0], bits[22:0]});
    end else begin
      if ((16'sd1 - final_exp) >= 16'sd32) begin
        lost = lost || (sig != 24'd0);
      end else begin
        shifted = ext >> (16'sd1 - final_exp);
        for (int bit_idx = 0; bit_idx < 64; bit_idx++) begin
          if (bit_idx < (16'sd1 - final_exp)) begin
            lost = lost || ext[bit_idx];
          end
        end
        main_sig = shifted[26:3];
      end

      inexact = shifted[2] || shifted[1] || shifted[0] || lost;
      rounded = {1'b0, main_sig} +
                {24'd0, round_inc(rm, sign, main_sig[0],
                                   shifted[2], shifted[1],
                                   shifted[0] || lost)};
      if (rounded[24]) begin
        out.result = nanbox_s({sign, 8'd1, 23'd0});
      end else begin
        out.result = nanbox_s({sign, 8'd0, rounded[22:0]});
      end
      out.fflags[FPU_FFLAG_NX] = out.fflags[FPU_FFLAG_NX] || inexact;
      out.fflags[FPU_FFLAG_UF] = out.fflags[FPU_FFLAG_UF] || inexact;
    end

    return out;
  endfunction

  function automatic fpu_resp_t scale_d_result(
    input fpu_resp_t          mant_resp,
    input logic signed [15:0] exp_delta,
    input fpu_rm_e            rm
  );
    fpu_resp_t          out;
    logic [63:0]        bits;
    logic               sign;
    logic signed [15:0] final_exp;
    logic [52:0]        sig;
    logic [127:0]       ext;
    logic [127:0]       shifted;
    logic               lost;
    logic [52:0]        main_sig;
    logic [53:0]        rounded;
    logic               inexact;

    out       = mant_resp;
    bits      = mant_resp.result;
    sign      = bits[63];
    final_exp = $signed({5'd0, bits[62:52]}) + exp_delta;
    sig       = {1'b1, bits[51:0]};
    ext       = {72'd0, sig, 3'd0};
    shifted   = 128'd0;
    lost      = mant_resp.fflags[FPU_FFLAG_NX];
    main_sig  = 53'd0;
    rounded   = 54'd0;
    inexact   = 1'b0;

    if (bits[62:52] == 11'h7ff) begin
      return mant_resp;
    end

    if (final_exp >= 16'sd2047) begin
      out.result = pack_overflow_result(FPU_FMT_D, sign, rm);
      out.fflags[FPU_FFLAG_OF] = 1'b1;
      out.fflags[FPU_FFLAG_NX] = 1'b1;
    end else if (final_exp > 16'sd0) begin
      out.result = {sign, final_exp[10:0], bits[51:0]};
    end else begin
      if ((16'sd1 - final_exp) >= 16'sd61) begin
        lost = lost || (sig != 53'd0);
      end else begin
        shifted = ext >> (16'sd1 - final_exp);
        for (int bit_idx = 0; bit_idx < 128; bit_idx++) begin
          if (bit_idx < (16'sd1 - final_exp)) begin
            lost = lost || ext[bit_idx];
          end
        end
        main_sig = shifted[55:3];
      end

      inexact = shifted[2] || shifted[1] || shifted[0] || lost;
      rounded = {1'b0, main_sig} +
                {53'd0, round_inc(rm, sign, main_sig[0],
                                   shifted[2], shifted[1],
                                   shifted[0] || lost)};
      if (rounded[53]) begin
        out.result = {sign, 11'd1, 52'd0};
      end else begin
        out.result = {sign, 11'd0, rounded[51:0]};
      end
      out.fflags[FPU_FFLAG_NX] = out.fflags[FPU_FFLAG_NX] || inexact;
      out.fflags[FPU_FFLAG_UF] = out.fflags[FPU_FFLAG_UF] || inexact;
    end

    return out;
  endfunction

  function automatic fpu_resp_t scale_result(
    input fpu_resp_t          mant_resp,
    input fpu_fmt_e           fmt,
    input logic signed [15:0] exp_delta,
    input fpu_rm_e            rm
  );
    if (fmt == FPU_FMT_S) begin
      return scale_s_result(mant_resp, exp_delta, rm);
    end

    return scale_d_result(mant_resp, exp_delta, rm);
  endfunction

  function automatic fpu_req_t make_fma_req(
    input fpu_req_t   base_req,
    input fpu_op_e    op,
    input fpu_data_t  src_a,
    input fpu_data_t  src_b,
    input fpu_data_t  src_c,
    input fpu_rm_e    rm
  );
    fpu_req_t req;

    req         = base_req;
    req.op      = op;
    req.rm      = rm;
    req.src_a   = src_a;
    req.src_b   = src_b;
    req.src_c   = src_c;
    req.dst_fmt = base_req.rs_fmt;
    return req;
  endfunction

  assign lhs           = unpack_operand(req_i.src_a, req_i.rs_fmt);
  assign rhs           = unpack_operand(req_i.src_b, req_i.rs_fmt);
  assign op_is_div     = (req_i.op == FPU_OP_DIV);
  assign fmt_is_valid  = fmt_supported(req_i.rs_fmt) &&
                         (req_i.rs_fmt == req_i.dst_fmt);
  assign rm_is_valid_w = rm_is_supported(req_i.rm);
  assign lut_sig_hi    = rhs.sig_hi;
  assign seed_data     = pack_seed_mant(req_i.rs_fmt,
                                        seed_norm_mant,
                                        seed_norm_exp);

  always_comb begin
    special_resp          = '0;
    special_resp.tag      = req_i.tag;
    special_resp.rd       = req_i.rd;
    special_valid_op      = op_is_div && fmt_is_valid && rm_is_valid_w;
    normal_finite_div     = 1'b0;

    if (!special_valid_op) begin
      special_resp.result = '0;
    end else if (lhs.is_nan || rhs.is_nan) begin
      special_resp.result = canonical_nan(req_i.rs_fmt);
      special_resp.fflags[FPU_FFLAG_NV] = lhs.is_snan || rhs.is_snan;
    end else if ((lhs.is_zero && rhs.is_zero) || (lhs.is_inf && rhs.is_inf)) begin
      special_resp.result = canonical_nan(req_i.rs_fmt);
      special_resp.fflags[FPU_FFLAG_NV] = 1'b1;
    end else if (rhs.is_zero) begin
      special_resp.result = pack_inf(req_i.rs_fmt, lhs.sign ^ rhs.sign);
      special_resp.fflags[FPU_FFLAG_DZ] = 1'b1;
    end else if (lhs.is_inf) begin
      special_resp.result = pack_inf(req_i.rs_fmt, lhs.sign ^ rhs.sign);
    end else if (rhs.is_inf) begin
      special_resp.result = pack_zero(req_i.rs_fmt, lhs.sign ^ rhs.sign);
    end else if (lhs.is_zero) begin
      special_resp.result = pack_zero(req_i.rs_fmt, lhs.sign ^ rhs.sign);
    end else begin
      normal_finite_div = 1'b1;
    end
  end

  always_comb begin
    free_valid = 1'b0;
    free_idx   = 3'd0;
    for (int ctx_idx = 0; ctx_idx < NUM_CTX; ctx_idx++) begin
      if (!free_valid && !ctx_active[ctx_idx]) begin
        free_valid = 1'b1;
        free_idx   = ctx_idx[2:0];
      end
    end
  end

  always_comb begin
    done_valid = 1'b0;
    done_ctx   = 3'd0;
    for (int ctx_idx = 0; ctx_idx < NUM_CTX; ctx_idx++) begin
      if (!done_valid && ctx_active[ctx_idx] && ctx_done[ctx_idx]) begin
        done_valid = 1'b1;
        done_ctx   = ctx_idx[2:0];
      end
    end
  end

  always_comb begin
    issue_valid = 1'b0;
    issue_ctx   = 3'd0;
    issue_kind  = MICRO_E;
    issue_req   = '0;

    for (int ctx_idx = 0; ctx_idx < NUM_CTX; ctx_idx++) begin
      if (!issue_valid &&
          ctx_active[ctx_idx] &&
          ctx_ready[ctx_idx] &&
          !ctx_done[ctx_idx]) begin
        issue_valid = 1'b1;
        issue_ctx   = ctx_idx[2:0];
        issue_kind  = ctx_step[ctx_idx];

        unique case (ctx_step[ctx_idx])
          MICRO_E: begin
            issue_req = make_fma_req(ctx_req[ctx_idx],
                                     FPU_OP_FNMSUB,
                                     ctx_b_mant_abs[ctx_idx],
                                     ctx_x[ctx_idx],
                                     pack_one(ctx_req[ctx_idx].rs_fmt),
                                     FPU_RM_RNE);
          end

          MICRO_X: begin
            issue_req = make_fma_req(ctx_req[ctx_idx],
                                     FPU_OP_FMADD,
                                     ctx_x[ctx_idx],
                                     ctx_e[ctx_idx],
                                     ctx_x[ctx_idx],
                                     FPU_RM_RNE);
          end

          MICRO_Q: begin
            issue_req = make_fma_req(ctx_req[ctx_idx],
                                     FPU_OP_FMADD,
                                     ctx_a_mant[ctx_idx],
                                     set_sign(ctx_x[ctx_idx],
                                              ctx_req[ctx_idx].rs_fmt,
                                              ctx_req[ctx_idx].src_b[63]),
                                     pack_zero(ctx_req[ctx_idx].rs_fmt, 1'b0),
                                     FPU_RM_RNE);
            if (ctx_req[ctx_idx].rs_fmt == FPU_FMT_S) begin
              issue_req.src_b = set_sign(ctx_x[ctx_idx],
                                         ctx_req[ctx_idx].rs_fmt,
                                         ctx_req[ctx_idx].src_b[31]);
            end
          end

          MICRO_R: begin
            issue_req = make_fma_req(ctx_req[ctx_idx],
                                     FPU_OP_FNMSUB,
                                     ctx_b_mant[ctx_idx],
                                     ctx_q[ctx_idx],
                                     ctx_a_mant[ctx_idx],
                                     FPU_RM_RNE);
          end

          default: begin
            issue_req = make_fma_req(ctx_req[ctx_idx],
                                     FPU_OP_FMADD,
                                     ctx_r[ctx_idx],
                                     set_sign(ctx_x[ctx_idx],
                                              ctx_req[ctx_idx].rs_fmt,
                                              ctx_req[ctx_idx].src_b[63]),
                                     ctx_q[ctx_idx],
                                     effective_rm(ctx_req[ctx_idx].rm));
            if (ctx_req[ctx_idx].rs_fmt == FPU_FMT_S) begin
              issue_req.src_b = set_sign(ctx_x[ctx_idx],
                                         ctx_req[ctx_idx].rs_fmt,
                                         ctx_req[ctx_idx].src_b[31]);
            end
          end
        endcase
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ctx_active   <= '0;
      ctx_ready    <= '0;
      ctx_done     <= '0;
      ctx_valid_op <= '0;
      fma_req_q    <= '0;
      fma_valid_q  <= 1'b0;
      fma_ctx_q    <= 3'd0;
      fma_kind_q   <= MICRO_E;
      resp_q       <= '0;
      valid_q      <= 1'b0;
      valid_op_q   <= 1'b0;

      for (int ctx_idx = 0; ctx_idx < NUM_CTX; ctx_idx++) begin
        ctx_step[ctx_idx]       <= MICRO_E;
        ctx_req[ctx_idx]        <= '0;
        ctx_a_mant[ctx_idx]     <= '0;
        ctx_b_mant_abs[ctx_idx] <= '0;
        ctx_b_mant[ctx_idx]     <= '0;
        ctx_x[ctx_idx]          <= '0;
        ctx_e[ctx_idx]          <= '0;
        ctx_q[ctx_idx]          <= '0;
        ctx_r[ctx_idx]          <= '0;
        ctx_resp[ctx_idx]       <= '0;
        ctx_exp_delta[ctx_idx]  <= 16'sd0;
        ctx_iter[ctx_idx]       <= 3'd0;
        ctx_iter_limit[ctx_idx] <= 3'd0;
      end

      for (int pipe_idx = 0; pipe_idx < FMA_LATENCY; pipe_idx++) begin
        ret_valid_pipe[pipe_idx] <= 1'b0;
        ret_ctx_pipe[pipe_idx]   <= 3'd0;
        ret_kind_pipe[pipe_idx]  <= MICRO_E;
      end
    end else begin
      valid_q    <= 1'b0;
      valid_op_q <= 1'b0;

      ret_valid_pipe[0] <= fma_valid_q;
      ret_ctx_pipe[0]   <= fma_ctx_q;
      ret_kind_pipe[0]  <= fma_kind_q;
      for (int pipe_idx = 1; pipe_idx < FMA_LATENCY; pipe_idx++) begin
        ret_valid_pipe[pipe_idx] <= ret_valid_pipe[pipe_idx-1];
        ret_ctx_pipe[pipe_idx]   <= ret_ctx_pipe[pipe_idx-1];
        ret_kind_pipe[pipe_idx]  <= ret_kind_pipe[pipe_idx-1];
      end

      fma_valid_q <= issue_valid;
      fma_req_q   <= issue_req;
      fma_ctx_q   <= issue_ctx;
      fma_kind_q  <= issue_kind;
      if (issue_valid) begin
        ctx_ready[issue_ctx] <= 1'b0;
      end

      if (fma_valid_o && ret_valid_pipe[FMA_LATENCY-1]) begin
        unique case (ret_kind_pipe[FMA_LATENCY-1])
          MICRO_E: begin
            ctx_e[ret_ctx_pipe[FMA_LATENCY-1]]     <= fma_resp_o.result;
            ctx_step[ret_ctx_pipe[FMA_LATENCY-1]]  <= MICRO_X;
            ctx_ready[ret_ctx_pipe[FMA_LATENCY-1]] <= fma_valid_op_o;
          end

          MICRO_X: begin
            ctx_x[ret_ctx_pipe[FMA_LATENCY-1]] <= fma_resp_o.result;
            if ((ctx_iter[ret_ctx_pipe[FMA_LATENCY-1]] + 3'd1) >=
                ctx_iter_limit[ret_ctx_pipe[FMA_LATENCY-1]]) begin
              ctx_step[ret_ctx_pipe[FMA_LATENCY-1]] <= MICRO_Q;
            end else begin
              ctx_iter[ret_ctx_pipe[FMA_LATENCY-1]] <=
                ctx_iter[ret_ctx_pipe[FMA_LATENCY-1]] + 3'd1;
              ctx_step[ret_ctx_pipe[FMA_LATENCY-1]] <= MICRO_E;
            end
            ctx_ready[ret_ctx_pipe[FMA_LATENCY-1]] <= fma_valid_op_o;
          end

          MICRO_Q: begin
            ctx_q[ret_ctx_pipe[FMA_LATENCY-1]]     <= fma_resp_o.result;
            ctx_step[ret_ctx_pipe[FMA_LATENCY-1]]  <= MICRO_R;
            ctx_ready[ret_ctx_pipe[FMA_LATENCY-1]] <= fma_valid_op_o;
          end

          MICRO_R: begin
            ctx_r[ret_ctx_pipe[FMA_LATENCY-1]]     <= fma_resp_o.result;
            ctx_step[ret_ctx_pipe[FMA_LATENCY-1]]  <= MICRO_FINAL;
            ctx_ready[ret_ctx_pipe[FMA_LATENCY-1]] <= fma_valid_op_o;
          end

          default: begin
            ctx_resp[ret_ctx_pipe[FMA_LATENCY-1]] <=
              scale_result(fma_resp_o,
                           ctx_req[ret_ctx_pipe[FMA_LATENCY-1]].rs_fmt,
                           ctx_exp_delta[ret_ctx_pipe[FMA_LATENCY-1]],
                           ctx_req[ret_ctx_pipe[FMA_LATENCY-1]].rm);
            ctx_done[ret_ctx_pipe[FMA_LATENCY-1]]   <= fma_valid_op_o;
            ctx_ready[ret_ctx_pipe[FMA_LATENCY-1]]  <= 1'b0;
          end
        endcase
      end

      if (done_valid) begin
        resp_q               <= ctx_resp[done_ctx];
        valid_q              <= 1'b1;
        valid_op_q           <= ctx_valid_op[done_ctx];
        ctx_active[done_ctx] <= 1'b0;
        ctx_ready[done_ctx]  <= 1'b0;
        ctx_done[done_ctx]   <= 1'b0;
        ctx_valid_op[done_ctx] <= 1'b0;
      end

      if (accept_req) begin
        ctx_active[free_idx] <= 1'b1;
        ctx_req[free_idx]    <= req_i;
        ctx_resp[free_idx]   <= special_resp;
        ctx_done[free_idx]   <= !normal_finite_div;
        ctx_valid_op[free_idx] <= special_valid_op;
        ctx_ready[free_idx]  <= normal_finite_div;
        ctx_step[free_idx]   <= MICRO_E;

        if (normal_finite_div) begin
          ctx_a_mant[free_idx]     <= mantissa_data(req_i.rs_fmt,
                                                     lhs.sig_norm,
                                                     lhs.sign);
          ctx_b_mant_abs[free_idx] <= mantissa_data(req_i.rs_fmt,
                                                     rhs.sig_norm,
                                                     1'b0);
          ctx_b_mant[free_idx]     <= mantissa_data(req_i.rs_fmt,
                                                     rhs.sig_norm,
                                                     rhs.sign);
          ctx_x[free_idx]          <= seed_data;
          ctx_e[free_idx]          <= '0;
          ctx_q[free_idx]          <= '0;
          ctx_r[free_idx]          <= '0;
          ctx_exp_delta[free_idx]  <= lhs.unbiased_exp - rhs.unbiased_exp;
          ctx_iter[free_idx]       <= 3'd0;
          ctx_iter_limit[free_idx] <= (req_i.rs_fmt == FPU_FMT_S) ? 3'd2 :
                                                                     3'd3;
          ctx_valid_op[free_idx]   <= 1'b1;
        end
      end
    end
  end

endmodule : fpu_div_unit_pipe
