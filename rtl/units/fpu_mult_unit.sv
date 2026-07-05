//============================================================================
// Floating-point multiply unit.
//
// Flow:
//   req_i
//     -> unpack/classify lhs and rhs
//     -> compute result sign
//     -> multiply 53-bit significands
//     -> leading-one detect and normalize product
//     -> compute exponent and handle subnormal right-shift/jam
//     -> select GRS/LSB, compute round increment, and pack
//     -> special-case result mux for NaN/Inf/zero/finite outputs
//============================================================================

module fpu_mult_unit
  import fpu_pkg::*;
(
  input  fpu_req_t  req_i,
  output fpu_resp_t resp_o,
  output logic      valid_op_o
);

  // --------------------------------------------------------------------------
  // Global types
  // --------------------------------------------------------------------------

  typedef struct packed {
    logic        sign;
    logic [10:0] exp;
    logic [52:0] sig;
    logic        is_zero;
    logic        is_inf;
    logic        is_nan;
    logic        is_snan;
  } fp_mult_operand_t;

  typedef struct packed {
    fpu_data_t    result;
    fpu_fflags_t  fflags;
  } fp_mult_pack_t;

  // --------------------------------------------------------------------------
  // Global datapath and control signals
  // --------------------------------------------------------------------------

  fpu_resp_t resp_d;

  fp_mult_operand_t lhs;
  fp_mult_operand_t rhs;

  logic [105:0] product;

  logic [5:0]  product_hi_lop_pos;
  logic [5:0]  product_lo_lop_pos;
  logic        product_hi_zero;
  logic        product_lo_zero;
  logic        product_zero;
  logic [6:0]  product_lop_pos;

  logic        finite_sign;
  logic signed [13:0] raw_exp;
  logic signed [13:0] finite_exp;
  logic [63:0] norm_sig;
  logic [63:0] finite_sig;
  logic [6:0]  subnorm_shamt;
  logic [63:0] subnorm_sig_shifted_raw;
  logic [63:0] subnorm_sig_lost;
  logic [63:0] subnorm_sig_jam;

  fpu_grs_t result_grs;
  fpu_grs_t result_s_grs;
  fpu_grs_t result_d_grs;
  logic [39:0] result_s_grs_bits;
  logic [10:0] result_d_grs_bits;
  logic     result_lsb;
  logic     result_inexact;
  logic     result_round_inc;

  fp_mult_pack_t packed_result;

  // --------------------------------------------------------------------------
  // Shared helper functions
  // --------------------------------------------------------------------------

  function automatic logic [63:0] nanbox_s(input logic [31:0] data_s);
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

  function automatic logic [63:0] canonical_nan(input fpu_fmt_e fmt);
    if (fmt == FPU_FMT_S) begin
      return nanbox_s(32'h7fc0_0000);
    end

    return 64'h7ff8_0000_0000_0000;
  endfunction

  function automatic logic [63:0] pack_inf(
    input fpu_fmt_e fmt,
    input logic     sign
  );
    if (fmt == FPU_FMT_S) begin
      return nanbox_s({sign, 8'hff, 23'd0});
    end

    return {sign, 11'h7ff, 52'd0};
  endfunction

  function automatic logic [63:0] pack_zero(
    input fpu_fmt_e fmt,
    input logic     sign
  );
    if (fmt == FPU_FMT_S) begin
      return nanbox_s({sign, 31'd0});
    end

    return {sign, 63'd0};
  endfunction

  function automatic logic [63:0] pack_max_finite(
    input fpu_fmt_e fmt,
    input logic     sign
  );
    if (fmt == FPU_FMT_S) begin
      return nanbox_s({sign, 8'hfe, 23'h7f_ffff});
    end

    return {sign, 11'h7fe, 52'hf_ffff_ffff_ffff};
  endfunction

  function automatic logic [63:0] pack_overflow_result(
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

  function automatic fp_mult_operand_t unpack_operand(
    input fpu_data_t data,
    input fpu_fmt_e  fmt
  );
    fp_mult_operand_t op;
    logic [31:0]      bits_s;
    logic [63:0]      bits_d;
    logic             s_is_boxed;

    op         = '0;
    bits_s     = 32'h7fc0_0000;
    bits_d     = data;
    s_is_boxed = &data[63:32];

    unique case (fmt)
      FPU_FMT_S: begin
        bits_s = s_is_boxed ? data[31:0] : 32'h7fc0_0000;

        op.sign    = bits_s[31];
        op.exp     = {3'd0, bits_s[30:23]};
        op.is_zero = (bits_s[30:0] == 31'd0);
        op.is_inf  = (bits_s[30:23] == 8'hff) && (bits_s[22:0] == 23'd0);
        op.is_nan  = (bits_s[30:23] == 8'hff) && (bits_s[22:0] != 23'd0);
        op.is_snan = op.is_nan && !bits_s[22];
        op.sig     = (bits_s[30:23] == 8'd0) ?
                     {1'b0, bits_s[22:0], 29'd0} :
                     {1'b1, bits_s[22:0], 29'd0};

        if (!op.is_zero && op.exp == 11'd0) begin
          op.exp = 11'd1;
        end
      end

      FPU_FMT_D: begin
        bits_d = data;

        op.sign    = bits_d[63];
        op.exp     = bits_d[62:52];
        op.is_zero = (bits_d[62:0] == 63'd0);
        op.is_inf  = (bits_d[62:52] == 11'h7ff) && (bits_d[51:0] == 52'd0);
        op.is_nan  = (bits_d[62:52] == 11'h7ff) && (bits_d[51:0] != 52'd0);
        op.is_snan = op.is_nan && !bits_d[51];
        op.sig     = (bits_d[62:52] == 11'd0) ?
                     {1'b0, bits_d[51:0]} :
                     {1'b1, bits_d[51:0]};

        if (!op.is_zero && op.exp == 11'd0) begin
          op.exp = 11'd1;
        end
      end

      default: begin end
    endcase

    return op;
  endfunction

  function automatic logic [63:0] normalize_product_sig(
    input logic [105:0] prod,
    input logic [6:0]   lop_pos
  );
    logic [63:0] sig;
    logic [6:0]  rshift;

    sig    = 64'd0;
    rshift = 7'd0;

    if (lop_pos >= 7'd63) begin
      rshift = lop_pos - 7'd63;
      sig    = prod >> rshift;

      for (int bit_idx = 0; bit_idx < 106; bit_idx++) begin
        if (bit_idx < rshift) begin
          sig[0] |= prod[bit_idx];
        end
      end
    end else begin
      sig = prod[63:0] << (7'd63 - lop_pos);
    end

    return sig;
  endfunction

  function automatic fp_mult_pack_t pack_result(
    input fpu_fmt_e             fmt,
    input logic                 sign,
    input logic signed [13:0]   exp,
    input logic [63:0]          sig,
    input logic                 round_inc,
    input logic                 inexact,
    input fpu_rm_e              rm
  );
    fp_mult_pack_t pack;
    logic [7:0]    exp_s;
    logic [10:0]   exp_d;
    logic [22:0]   mant_s;
    logic [51:0]   mant_d;
    logic [23:0]   mant_s_round;
    logic [52:0]   mant_d_round;
    logic          overflow;

    pack         = '0;
    exp_s        = exp[7:0];
    exp_d        = exp[10:0];
    mant_s       = 23'd0;
    mant_d       = 52'd0;
    overflow     = 1'b0;

    if (fmt == FPU_FMT_S) begin
      mant_s_round = {1'b0, sig[62:40]} + {23'd0, round_inc};

      if (exp == 14'sd0) begin
        if (mant_s_round[23]) begin
          exp_s  = 8'd1;
          mant_s = 23'd0;
        end else begin
          exp_s  = 8'd0;
          mant_s = mant_s_round[22:0];
        end
      end else begin
        if (mant_s_round[23]) begin
          exp_s  = exp_s + 8'd1;
          mant_s = 23'd0;
        end else begin
          mant_s = mant_s_round[22:0];
        end
      end

      overflow = (exp > 14'sd254) || (exp_s == 8'hff);
      if (overflow) begin
        pack.result = pack_overflow_result(FPU_FMT_S, sign, rm);
        pack.fflags[FPU_FFLAG_OF] = 1'b1;
        pack.fflags[FPU_FFLAG_NX] = 1'b1;
      end else begin
        pack.result = nanbox_s({sign, exp_s, mant_s});
        pack.fflags[FPU_FFLAG_NX] = inexact;
        pack.fflags[FPU_FFLAG_UF] = (exp_s == 8'd0) && inexact;
      end
    end else begin
      mant_d_round = {1'b0, sig[62:11]} + {52'd0, round_inc};

      if (exp == 14'sd0) begin
        if (mant_d_round[52]) begin
          exp_d  = 11'd1;
          mant_d = 52'd0;
        end else begin
          exp_d  = 11'd0;
          mant_d = mant_d_round[51:0];
        end
      end else begin
        if (mant_d_round[52]) begin
          exp_d  = exp_d + 11'd1;
          mant_d = 52'd0;
        end else begin
          mant_d = mant_d_round[51:0];
        end
      end

      overflow = (exp > 14'sd2046) || (exp_d == 11'h7ff);
      if (overflow) begin
        pack.result = pack_overflow_result(FPU_FMT_D, sign, rm);
        pack.fflags[FPU_FFLAG_OF] = 1'b1;
        pack.fflags[FPU_FFLAG_NX] = 1'b1;
      end else begin
        pack.result = {sign, exp_d, mant_d};
        pack.fflags[FPU_FFLAG_NX] = inexact;
        pack.fflags[FPU_FFLAG_UF] = (exp_d == 11'd0) && inexact;
      end
    end

    return pack;
  endfunction

  // --------------------------------------------------------------------------
  // Unpack, operation decode, and product setup
  // --------------------------------------------------------------------------

  assign lhs         = unpack_operand(req_i.src_a, req_i.rs_fmt);
  assign rhs         = unpack_operand(req_i.src_b, req_i.rs_fmt);
  assign finite_sign = lhs.sign ^ rhs.sign;

  // --------------------------------------------------------------------------
  // Significand multiply
  // --------------------------------------------------------------------------

  fpu_mult #(
    .WIDTH(53)
  ) u_sig_mult (
    .lhs_i        (lhs.sig),
    .rhs_i        (rhs.sig),
    .product_o    (product),
    .booth_code_o (),
    .pp_o         (),
    .final_sum_o  (),
    .final_carry_o()
  );

  // --------------------------------------------------------------------------
  // Product leading-one detect and normalization
  // --------------------------------------------------------------------------

  fpu_lop #(
    .DATA_W(42)
  ) u_product_hi_lop (
    .data_i(product[105:64]),
    .pos_o (product_hi_lop_pos),
    .zero_o(product_hi_zero)
  );

  fpu_lop #(
    .DATA_W(64)
  ) u_product_lo_lop (
    .data_i(product[63:0]),
    .pos_o (product_lo_lop_pos),
    .zero_o(product_lo_zero)
  );

  assign product_zero    = product_hi_zero && product_lo_zero;
  assign product_lop_pos = product_hi_zero ? {1'b0, product_lo_lop_pos} :
                                             {1'b1, product_hi_lop_pos};
  assign norm_sig        = product_zero ? 64'd0 :
                                          normalize_product_sig(product, product_lop_pos);

  // --------------------------------------------------------------------------
  // Exponent calculation and subnormal adjustment
  // --------------------------------------------------------------------------

  fpu_barrel_shifter #(
    .WIDTH        (64),
    .SUPPORT_LEFT (1'b0),
    .SUPPORT_RIGHT(1'b1)
  ) u_subnorm_shifter (
    .data_i      (norm_sig),
    .shamt_i     (subnorm_shamt),
    .left_data_o (),
    .right_data_o(subnorm_sig_shifted_raw),
    .right_lost_o(subnorm_sig_lost)
  );

  always_comb begin
    subnorm_sig_jam = subnorm_sig_shifted_raw;
    subnorm_sig_jam[0] |= |subnorm_sig_lost;
  end

  always_comb begin
    logic signed [13:0] subnorm_shamt_calc;

    raw_exp       = 14'sd0;
    finite_exp    = 14'sd0;
    finite_sig    = norm_sig;
    subnorm_shamt = 7'd0;
    subnorm_shamt_calc = 14'sd0;

    if (!product_zero) begin
      raw_exp = $signed({3'd0, lhs.exp}) + $signed({3'd0, rhs.exp}) -
                ((req_i.rs_fmt == FPU_FMT_S) ? 14'sd127 : 14'sd1023) +
                $signed({7'd0, product_lop_pos}) - 14'sd104;

      if (raw_exp <= 14'sd0) begin
        finite_exp = 14'sd0;

        if (raw_exp <= -14'sd63) begin
          subnorm_shamt = 7'd64;
        end else begin
          subnorm_shamt_calc = 14'sd1 - raw_exp;
          subnorm_shamt      = subnorm_shamt_calc[6:0];
        end

        finite_sig = subnorm_sig_jam;
      end else begin
        finite_exp = raw_exp;
        finite_sig = norm_sig;
      end
    end
  end

  assign result_s_grs_bits = finite_sig[39:0];
  assign result_d_grs_bits = finite_sig[10:0];

  // --------------------------------------------------------------------------
  // GRS selection and round increment
  // --------------------------------------------------------------------------

  fpu_grs #(
    .WIDTH(40)
  ) u_result_s_grs (
    .data_i(result_s_grs_bits),
    .grs_o (result_s_grs)
  );

  fpu_grs #(
    .WIDTH(11)
  ) u_result_d_grs (
    .data_i(result_d_grs_bits),
    .grs_o (result_d_grs)
  );

  always_comb begin
    result_grs = '0;
    result_lsb = 1'b0;
    unique case (req_i.rs_fmt)
      FPU_FMT_S: begin
        result_grs = result_s_grs;
        result_lsb = finite_sig[40];
      end

      FPU_FMT_D: begin
        result_grs = result_d_grs;
        result_lsb = finite_sig[11];
      end

      default: begin end
    endcase
  end

  fpu_round_inc u_round (
    .rm_i     (req_i.rm),
    .sign_i   (finite_sign),
    .lsb_i    (result_lsb),
    .grs_i    (result_grs),
    .inexact_o(result_inexact),
    .inc_o    (result_round_inc)
  );

  // --------------------------------------------------------------------------
  // Finite pack and final special-case result mux
  // --------------------------------------------------------------------------

  assign packed_result = pack_result(
    req_i.rs_fmt,
    finite_sign,
    finite_exp,
    finite_sig,
    result_round_inc,
    result_inexact,
    req_i.rm
  );

  always_comb begin
    resp_d     = '0;
    resp_d.tag = req_i.tag;
    resp_d.rd  = req_i.rd;
    valid_op_o = (req_i.op == FPU_OP_MUL) &&
                 ((req_i.rs_fmt == FPU_FMT_S) || (req_i.rs_fmt == FPU_FMT_D)) &&
                 rm_is_supported(req_i.rm);

    if (!valid_op_o) begin
      resp_d = '0;
      resp_d.tag = req_i.tag;
      resp_d.rd  = req_i.rd;
    end else if (lhs.is_nan || rhs.is_nan) begin
      resp_d.result = canonical_nan(req_i.rs_fmt);
      resp_d.fflags[FPU_FFLAG_NV] = lhs.is_snan || rhs.is_snan;
    end else if ((lhs.is_inf && rhs.is_zero) || (lhs.is_zero && rhs.is_inf)) begin
      resp_d.result = canonical_nan(req_i.rs_fmt);
      resp_d.fflags[FPU_FFLAG_NV] = 1'b1;
    end else if (lhs.is_inf || rhs.is_inf) begin
      resp_d.result = pack_inf(req_i.rs_fmt, finite_sign);
    end else if (lhs.is_zero || rhs.is_zero) begin
      resp_d.result = pack_zero(req_i.rs_fmt, finite_sign);
    end else begin
      resp_d.result = packed_result.result;
      resp_d.fflags = packed_result.fflags;
    end
  end

  assign resp_o = resp_d;

endmodule : fpu_mult_unit
