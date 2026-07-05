//============================================================================
// Pipelined divide unit built from a reciprocal seed and a private FMA pipe.
//
// This first divide pipe is a fixed micro-sequence, not a throughput-1 pipe:
// it accepts a new finite FDIV only while idle. The surrounding scheduler must
// not assert another valid FDIV while this unit is busy.
//
// Finite path:
//   x0 = recip_seed(abs(b))
//   e  = 1.0 - abs(b) * x
//   x' = x + x * e
//   S-format: two Newton-Raphson rounds, then a * signed(x)
//   D-format: four Newton-Raphson rounds, then a * signed(x)
//   q0 = a * signed(x)
//   r  = a - b * q0
//   q  = q0 + r * signed(x)
//============================================================================

module fpu_div_unit_pipe
  import fpu_pkg::*;
(
  input  logic      clk_i,
  input  logic      rst_ni,
  input  logic      valid_i,
  input  fpu_req_t  req_i,
  output logic      valid_o,
  output fpu_resp_t resp_o,
  output logic      valid_op_o
);

  localparam int signed S_EXP_BIAS = 127;
  localparam int signed D_EXP_BIAS = 1023;

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_WAIT_E,
    ST_WAIT_X,
    ST_WAIT_Q,
    ST_WAIT_R,
    ST_WAIT_FINAL
  } state_e;

  typedef struct packed {
    logic             sign;
    logic             is_zero;
    logic             is_inf;
    logic             is_nan;
    logic             is_snan;
    logic [11:0]      sig_hi;
    logic signed [15:0] unbiased_exp;
  } fp_div_operand_t;

  state_e     state_q;
  fpu_req_t   req_q;
  fpu_data_t  b_abs_q;
  fpu_data_t  x_q;
  fpu_data_t  q_q;
  logic       b_sign_q;
  logic [2:0] iter_q;
  logic [2:0] iter_limit_q;

  fpu_req_t  fma_req_q;
  logic      fma_valid_q;
  logic      fma_valid_o;
  fpu_resp_t fma_resp_o;
  logic      fma_valid_op_o;

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

  logic [11:0]             lut_sig_hi;
  logic signed [15:0]      lut_exp;
  logic [15:0]             seed_mant;
  logic signed [15:0]      seed_exp;
  logic [15:0]             seed_norm_mant;
  logic signed [15:0]      seed_norm_exp;
  fpu_data_t               seed_data;

  assign valid_o    = valid_q;
  assign resp_o     = resp_q;
  assign valid_op_o = valid_op_q;

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
    .exp_i           (lut_exp),
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

    op.sig_hi = sig_norm[52:41];
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

  function automatic fpu_data_t pack_one(input fpu_fmt_e fmt);
    if (fmt == FPU_FMT_S) begin
      return nanbox_s(32'h3f80_0000);
    end

    return 64'h3ff0_0000_0000_0000;
  endfunction

  function automatic fpu_data_t abs_data(
    input fpu_data_t data,
    input fpu_fmt_e  fmt
  );
    fpu_data_t out;

    out = data;
    if (fmt == FPU_FMT_S) begin
      out[31] = 1'b0;
    end else begin
      out[63] = 1'b0;
    end

    return out;
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

  function automatic fpu_data_t pack_seed(
    input fpu_fmt_e             fmt,
    input logic [15:0]          norm_mant,
    input logic signed [15:0]   norm_exp
  );
    logic signed [15:0] biased_exp;
    logic [31:0]       bits_s;
    logic [63:0]       bits_d;

    biased_exp = (fmt == FPU_FMT_S) ? (norm_exp + 16'sd127) :
                                      (norm_exp + 16'sd1023);
    bits_s     = 32'd0;
    bits_d     = 64'd0;

    if (fmt == FPU_FMT_S) begin
      if (biased_exp >= 16'sd255) begin
        bits_s = {1'b0, 8'hff, 23'd0};
      end else if (biased_exp <= 16'sd0) begin
        bits_s = 32'd0;
      end else begin
        bits_s = {1'b0, biased_exp[7:0], norm_mant[14:0], 8'd0};
      end

      return nanbox_s(bits_s);
    end

    if (biased_exp >= 16'sd2047) begin
      bits_d = {1'b0, 11'h7ff, 52'd0};
    end else if (biased_exp <= 16'sd0) begin
      bits_d = 64'd0;
    end else begin
      bits_d = {1'b0, biased_exp[10:0], norm_mant[14:0], 37'd0};
    end

    return bits_d;
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

  assign lut_sig_hi = rhs.sig_hi;
  assign lut_exp    = rhs.unbiased_exp;
  assign seed_data  = pack_seed(req_i.rs_fmt, seed_norm_mant, seed_norm_exp);

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

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q      <= ST_IDLE;
      req_q        <= '0;
      b_abs_q      <= '0;
      x_q          <= '0;
      q_q          <= '0;
      b_sign_q     <= 1'b0;
      iter_q       <= 3'd0;
      iter_limit_q <= 3'd0;
      fma_req_q    <= '0;
      fma_valid_q  <= 1'b0;
      resp_q       <= '0;
      valid_q      <= 1'b0;
      valid_op_q   <= 1'b0;
    end else begin
      valid_q     <= 1'b0;
      valid_op_q  <= 1'b0;
      fma_valid_q <= 1'b0;

      unique case (state_q)
        ST_IDLE: begin
          if (valid_i) begin
            if (!normal_finite_div) begin
              resp_q      <= special_resp;
              valid_q     <= 1'b1;
              valid_op_q  <= special_valid_op;
            end else begin
              req_q        <= req_i;
              b_abs_q      <= abs_data(req_i.src_b, req_i.rs_fmt);
              x_q          <= seed_data;
              b_sign_q     <= rhs.sign;
              iter_q       <= 3'd0;
              iter_limit_q <= (req_i.rs_fmt == FPU_FMT_S) ? 3'd2 : 3'd4;
              fma_req_q    <= make_fma_req(req_i,
                                            FPU_OP_FNMSUB,
                                            abs_data(req_i.src_b, req_i.rs_fmt),
                                            seed_data,
                                            pack_one(req_i.rs_fmt),
                                            FPU_RM_RNE);
              fma_valid_q  <= 1'b1;
              state_q      <= ST_WAIT_E;
            end
          end
        end

        ST_WAIT_E: begin
          if (fma_valid_o) begin
            fma_req_q   <= make_fma_req(req_q,
                                        FPU_OP_FMADD,
                                        x_q,
                                        fma_resp_o.result,
                                        x_q,
                                        FPU_RM_RNE);
            fma_valid_q <= 1'b1;
            state_q     <= ST_WAIT_X;
          end
        end

        ST_WAIT_X: begin
          if (fma_valid_o) begin
            x_q <= fma_resp_o.result;
            if ((iter_q + 3'd1) >= iter_limit_q) begin
              fma_req_q   <= make_fma_req(req_q,
                                          FPU_OP_FMADD,
                                          req_q.src_a,
                                          set_sign(fma_resp_o.result,
                                                   req_q.rs_fmt,
                                                   b_sign_q),
                                          pack_zero(req_q.rs_fmt, 1'b0),
                                          FPU_RM_RNE);
              fma_valid_q <= 1'b1;
              state_q     <= ST_WAIT_Q;
            end else begin
              iter_q      <= iter_q + 3'd1;
              fma_req_q   <= make_fma_req(req_q,
                                          FPU_OP_FNMSUB,
                                          b_abs_q,
                                          fma_resp_o.result,
                                          pack_one(req_q.rs_fmt),
                                          FPU_RM_RNE);
              fma_valid_q <= 1'b1;
              state_q     <= ST_WAIT_E;
            end
          end
        end

        ST_WAIT_Q: begin
          if (fma_valid_o) begin
            q_q         <= fma_resp_o.result;
            fma_req_q   <= make_fma_req(req_q,
                                        FPU_OP_FNMSUB,
                                        req_q.src_b,
                                        fma_resp_o.result,
                                        req_q.src_a,
                                        FPU_RM_RNE);
            fma_valid_q <= 1'b1;
            state_q     <= ST_WAIT_R;
          end
        end

        ST_WAIT_R: begin
          if (fma_valid_o) begin
            fma_req_q   <= make_fma_req(req_q,
                                        FPU_OP_FMADD,
                                        fma_resp_o.result,
                                        set_sign(x_q, req_q.rs_fmt, b_sign_q),
                                        q_q,
                                        effective_rm(req_q.rm));
            fma_valid_q <= 1'b1;
            state_q     <= ST_WAIT_FINAL;
          end
        end

        ST_WAIT_FINAL: begin
          if (fma_valid_o) begin
            resp_q      <= fma_resp_o;
            valid_q     <= 1'b1;
            valid_op_q  <= fma_valid_op_o;
            state_q     <= ST_IDLE;
          end
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end

endmodule : fpu_div_unit_pipe
