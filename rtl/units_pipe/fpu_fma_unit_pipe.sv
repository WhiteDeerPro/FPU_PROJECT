//============================================================================
// Pipelined floating-point fused multiply-add unit.
//
// Flow:
// Flow:
//   S0: decode FMADD/FMSUB/FNMSUB/FNMADD, unpack/classify, start multiplier
//   S1: multiplier reduction segment 1
//   S2: multiplier reduction segment 2 and final product add
//   S3: product/addend leading-one detect and accumulator exponent setup
//   S4: align product/addend into the accumulator domain and add/subtract
//   S5: result leading-one detect, normalize, round, pack, and special mux
//============================================================================

module fpu_fma_unit_pipe
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
  } fp_fma_operand_t;

  typedef struct packed {
    fpu_data_t    result;
    fpu_fflags_t  fflags;
  } fp_fma_pack_t;

  // --------------------------------------------------------------------------
  // Global datapath and control signals
  // --------------------------------------------------------------------------

  fpu_resp_t resp_d;

  fp_fma_operand_t lhs;
  fp_fma_operand_t rhs;
  fp_fma_operand_t addend;

  logic            op_is_fma;
  logic            negate_product;
  logic            negate_addend;
  logic            product_sign;
  logic            addend_sign;

  logic [105:0] product;

  logic [5:0] product_hi_lop_pos;
  logic [5:0] product_lo_lop_pos;
  logic       product_hi_zero;
  logic       product_lo_zero;
  logic       product_zero;
  logic [6:0] product_lop_pos;

  logic [5:0] addend_lop_pos;
  logic       addend_sig_zero;

  logic signed [15:0] prod_bit_base_exp;
  logic signed [15:0] add_bit_base_exp;
  logic signed [15:0] prod_top_exp;
  logic signed [15:0] add_top_exp;
  logic signed [15:0] align_top_exp;
  logic signed [15:0] acc_lsb_exp;

  logic [159:0] product_acc_mag;
  logic [159:0] addend_acc_mag;
  logic [159:0] finite_mag;
  logic [160:0] acc_sum_ext;

  logic             finite_sign;
  logic             finite_zero;
  logic signed [15:0] raw_exp;
  logic signed [15:0] finite_exp;
  logic [63:0]      norm_sig;
  logic [63:0]      finite_sig;
  logic [6:0]       subnorm_shamt;
  logic [63:0]      subnorm_sig_shifted_raw;
  logic [63:0]      subnorm_sig_lost;
  logic [63:0]      subnorm_sig_jam;

  logic [5:0] finite_hi_lop_pos;
  logic [5:0] finite_mid_lop_pos;
  logic [5:0] finite_lo_lop_pos;
  logic       finite_hi_zero;
  logic       finite_mid_zero;
  logic       finite_lo_zero;
  logic [7:0] finite_lop_pos;
  logic signed [15:0] finite_top_exp;

  fpu_grs_t result_grs;
  fpu_grs_t result_s_grs;
  fpu_grs_t result_d_grs;
  logic [39:0] result_s_grs_bits;
  logic [10:0] result_d_grs_bits;
  logic     result_lsb;
  logic     result_inexact;
  logic     result_round_inc;

  fp_fma_pack_t packed_result;

  logic       mult_valid;
  logic [105:0] product_w;

  logic            s1_valid;
  logic            s1_valid_op;
  fpu_req_t        s1_req;
  fp_fma_operand_t s1_lhs;
  fp_fma_operand_t s1_rhs;
  fp_fma_operand_t s1_addend;
  logic            s1_product_sign;
  logic            s1_addend_sign;

  logic            s2_valid;
  logic            s2_valid_op;
  fpu_req_t        s2_req;
  fp_fma_operand_t s2_lhs;
  fp_fma_operand_t s2_rhs;
  fp_fma_operand_t s2_addend;
  logic            s2_product_sign;
  logic            s2_addend_sign;

  logic            s3_valid;
  logic            s3_valid_op;
  fpu_req_t        s3_req;
  fp_fma_operand_t s3_lhs;
  fp_fma_operand_t s3_rhs;
  fp_fma_operand_t s3_addend;
  logic            s3_product_sign;
  logic            s3_addend_sign;
  logic [105:0]    s3_product;

  logic                 s4_valid;
  logic                 s4_valid_op;
  fpu_req_t             s4_req;
  fp_fma_operand_t      s4_lhs;
  fp_fma_operand_t      s4_rhs;
  fp_fma_operand_t      s4_addend;
  logic                 s4_product_sign;
  logic                 s4_addend_sign;
  logic [105:0]         s4_product;
  logic                 s4_product_zero;
  logic                 s4_addend_sig_zero;
  logic signed [15:0]   s4_prod_bit_base_exp;
  logic signed [15:0]   s4_add_bit_base_exp;
  logic signed [15:0]   s4_acc_lsb_exp;

  logic                 s5_valid;
  logic                 s5_valid_op;
  fpu_req_t             s5_req;
  fp_fma_operand_t      s5_lhs;
  fp_fma_operand_t      s5_rhs;
  fp_fma_operand_t      s5_addend;
  logic                 s5_product_sign;
  logic                 s5_addend_sign;
  logic [159:0]         s5_finite_mag;
  logic                 s5_finite_sign;
  logic signed [15:0]   s5_acc_lsb_exp;

  // --------------------------------------------------------------------------
  // Shared helper functions
  // --------------------------------------------------------------------------

  function automatic logic [63:0] nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
  endfunction

  function automatic logic [15:0] exp_bias(input fpu_fmt_e fmt);
    if (fmt == FPU_FMT_S) begin
      return 16'd127;
    end

    return 16'd1023;
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

  function automatic logic zero_result_sign(
    input logic    lhs_sign,
    input logic    rhs_sign,
    input fpu_rm_e rm
  );
    if (lhs_sign == rhs_sign) begin
      return lhs_sign;
    end

    return (effective_rm(rm) == FPU_RM_RDN);
  endfunction

  function automatic fp_fma_operand_t unpack_operand(
    input fpu_data_t data,
    input fpu_fmt_e  fmt
  );
    fp_fma_operand_t op;
    logic [31:0]     bits_s;
    logic [63:0]     bits_d;
    logic            s_is_boxed;

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

  function automatic logic [159:0] align_u106_to_acc(
    input logic [105:0]       data,
    input logic signed [15:0] bit_base_exp,
    input logic signed [15:0] acc_lsb_exp_i
  );
    logic [159:0] aligned;
    int signed        target_idx;

    aligned = '0;

    for (int bit_idx = 0; bit_idx < 106; bit_idx++) begin
      if (data[bit_idx]) begin
        target_idx = bit_base_exp + bit_idx - acc_lsb_exp_i;
        if (target_idx <= 0) begin
          aligned[0] = 1'b1;
        end else if (target_idx < 160) begin
          aligned[target_idx] = 1'b1;
        end
      end
    end

    return aligned;
  endfunction

  function automatic logic [159:0] align_u53_to_acc(
    input logic [52:0]        data,
    input logic signed [15:0] bit_base_exp,
    input logic signed [15:0] acc_lsb_exp_i
  );
    logic [159:0] aligned;
    int signed        target_idx;

    aligned = '0;

    for (int bit_idx = 0; bit_idx < 53; bit_idx++) begin
      if (data[bit_idx]) begin
        target_idx = bit_base_exp + bit_idx - acc_lsb_exp_i;
        if (target_idx <= 0) begin
          aligned[0] = 1'b1;
        end else if (target_idx < 160) begin
          aligned[target_idx] = 1'b1;
        end
      end
    end

    return aligned;
  endfunction

  function automatic logic [63:0] normalize_acc_sig(
    input logic [159:0] data,
    input logic [7:0]       lop_pos
  );
    logic [63:0] sig;
    int unsigned rshift;

    sig    = 64'd0;
    rshift = 0;

    if (lop_pos >= 8'd63) begin
      rshift = lop_pos - 8'd63;
      sig    = data >> rshift;

      for (int bit_idx = 0; bit_idx < 160; bit_idx++) begin
        if (bit_idx < rshift) begin
          sig[0] |= data[bit_idx];
        end
      end
    end else begin
      sig = data[63:0] << (8'd63 - lop_pos);
    end

    return sig;
  endfunction

  function automatic fp_fma_pack_t pack_result(
    input fpu_fmt_e             fmt,
    input logic                 sign,
    input logic signed [15:0]   exp,
    input logic [63:0]          sig,
    input logic                 round_inc,
    input logic                 inexact,
    input fpu_rm_e              rm
  );
    fp_fma_pack_t pack;
    logic [7:0]   exp_s;
    logic [10:0]  exp_d;
    logic [22:0]  mant_s;
    logic [51:0]  mant_d;
    logic [23:0]  mant_s_round;
    logic [52:0]  mant_d_round;
    logic         overflow;

    pack         = '0;
    exp_s        = exp[7:0];
    exp_d        = exp[10:0];
    mant_s       = 23'd0;
    mant_d       = 52'd0;
    overflow     = 1'b0;

    if (fmt == FPU_FMT_S) begin
      mant_s_round = {1'b0, sig[62:40]} + {23'd0, round_inc};

      if (exp == 16'sd0) begin
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

      overflow = (exp > 16'sd254) || (exp_s == 8'hff);
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

      if (exp == 16'sd0) begin
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

      overflow = (exp > 16'sd2046) || (exp_d == 11'h7ff);
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
  // S0: operation decode, unpack, sign control, and multiplier launch
  // --------------------------------------------------------------------------

  assign op_is_fma = (req_i.op == FPU_OP_FMADD)  ||
                     (req_i.op == FPU_OP_FMSUB)  ||
                     (req_i.op == FPU_OP_FNMSUB) ||
                     (req_i.op == FPU_OP_FNMADD);

  assign negate_product = (req_i.op == FPU_OP_FNMSUB) ||
                          (req_i.op == FPU_OP_FNMADD);
  assign negate_addend  = (req_i.op == FPU_OP_FMSUB) ||
                          (req_i.op == FPU_OP_FNMADD);

  assign lhs     = unpack_operand(req_i.src_a, req_i.rs_fmt);
  assign rhs     = unpack_operand(req_i.src_b, req_i.rs_fmt);
  assign addend  = unpack_operand(req_i.src_c, req_i.rs_fmt);

  assign product_sign = lhs.sign ^ rhs.sign ^ negate_product;
  assign addend_sign  = addend.sign ^ negate_addend;

  fpu_mult_pipe #(
    .WIDTH(53)
  ) u_sig_mult (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .valid_i      (valid_i),
    .lhs_i        (lhs.sig),
    .rhs_i        (rhs.sig),
    .valid_o      (mult_valid),
    .product_o    (product_w),
    .final_sum_o  (),
    .final_carry_o()
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s1_valid        <= 1'b0;
      s1_valid_op     <= 1'b0;
      s1_req          <= '0;
      s1_lhs          <= '0;
      s1_rhs          <= '0;
      s1_addend       <= '0;
      s1_product_sign <= 1'b0;
      s1_addend_sign  <= 1'b0;
      s2_valid        <= 1'b0;
      s2_valid_op     <= 1'b0;
      s2_req          <= '0;
      s2_lhs          <= '0;
      s2_rhs          <= '0;
      s2_addend       <= '0;
      s2_product_sign <= 1'b0;
      s2_addend_sign  <= 1'b0;
      s3_valid        <= 1'b0;
      s3_valid_op     <= 1'b0;
      s3_req          <= '0;
      s3_lhs          <= '0;
      s3_rhs          <= '0;
      s3_addend       <= '0;
      s3_product_sign <= 1'b0;
      s3_addend_sign  <= 1'b0;
      s3_product      <= '0;
    end else begin
      s1_valid        <= valid_i;
      s1_valid_op     <= op_is_fma &&
                         ((req_i.rs_fmt == FPU_FMT_S) ||
                          (req_i.rs_fmt == FPU_FMT_D)) &&
                         rm_is_supported(req_i.rm);
      s1_req          <= req_i;
      s1_lhs          <= lhs;
      s1_rhs          <= rhs;
      s1_addend       <= addend;
      s1_product_sign <= product_sign;
      s1_addend_sign  <= addend_sign;
      s2_valid        <= s1_valid;
      s2_valid_op     <= s1_valid_op;
      s2_req          <= s1_req;
      s2_lhs          <= s1_lhs;
      s2_rhs          <= s1_rhs;
      s2_addend       <= s1_addend;
      s2_product_sign <= s1_product_sign;
      s2_addend_sign  <= s1_addend_sign;
      s3_valid        <= mult_valid;
      s3_valid_op     <= s2_valid_op;
      s3_req          <= s2_req;
      s3_lhs          <= s2_lhs;
      s3_rhs          <= s2_rhs;
      s3_addend       <= s2_addend;
      s3_product_sign <= s2_product_sign;
      s3_addend_sign  <= s2_addend_sign;
      s3_product      <= product_w;
    end
  end

  // --------------------------------------------------------------------------
  // S3: product/addend leading-one detect and accumulator exponent setup
  // --------------------------------------------------------------------------

  fpu_lop #(
    .DATA_W(42)
  ) u_product_hi_lop (
    .data_i(s3_product[105:64]),
    .pos_o (product_hi_lop_pos),
    .zero_o(product_hi_zero)
  );

  fpu_lop #(
    .DATA_W(64)
  ) u_product_lo_lop (
    .data_i(s3_product[63:0]),
    .pos_o (product_lo_lop_pos),
    .zero_o(product_lo_zero)
  );

  fpu_lop #(
    .DATA_W(53)
  ) u_addend_lop (
    .data_i(s3_addend.sig),
    .pos_o (addend_lop_pos),
    .zero_o(addend_sig_zero)
  );

  assign product_zero    = product_hi_zero && product_lo_zero;
  assign product_lop_pos = product_hi_zero ? {1'b0, product_lo_lop_pos} :
                                             {1'b1, product_hi_lop_pos};

  always_comb begin
    prod_bit_base_exp = 16'sd0;
    add_bit_base_exp  = 16'sd0;
    prod_top_exp      = 16'sd0;
    add_top_exp       = 16'sd0;
    align_top_exp     = 16'sd0;
    acc_lsb_exp       = -16'sd158;

    if (!product_zero) begin
      prod_bit_base_exp = $signed({5'd0, s3_lhs.exp}) +
                          $signed({5'd0, s3_rhs.exp}) -
                          $signed(exp_bias(s3_req.rs_fmt)) -
                          $signed(exp_bias(s3_req.rs_fmt)) -
                          16'sd104;
      prod_top_exp = prod_bit_base_exp + $signed({9'd0, product_lop_pos});
    end

    if (!addend_sig_zero) begin
      add_bit_base_exp = $signed({5'd0, s3_addend.exp}) -
                         $signed(exp_bias(s3_req.rs_fmt)) -
                         16'sd52;
      add_top_exp = add_bit_base_exp + $signed({10'd0, addend_lop_pos});
    end

    if (!product_zero && !addend_sig_zero) begin
      align_top_exp = (prod_top_exp >= add_top_exp) ? prod_top_exp :
                                                      add_top_exp;
    end else if (!product_zero) begin
      align_top_exp = prod_top_exp;
    end else if (!addend_sig_zero) begin
      align_top_exp = add_top_exp;
    end

    acc_lsb_exp = align_top_exp - 16'sd158;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s4_valid             <= 1'b0;
      s4_valid_op          <= 1'b0;
      s4_req               <= '0;
      s4_lhs               <= '0;
      s4_rhs               <= '0;
      s4_addend            <= '0;
      s4_product_sign      <= 1'b0;
      s4_addend_sign       <= 1'b0;
      s4_product           <= '0;
      s4_product_zero      <= 1'b0;
      s4_addend_sig_zero   <= 1'b0;
      s4_prod_bit_base_exp <= 16'sd0;
      s4_add_bit_base_exp  <= 16'sd0;
      s4_acc_lsb_exp       <= 16'sd0;
    end else begin
      s4_valid             <= s3_valid;
      s4_valid_op          <= s3_valid_op;
      s4_req               <= s3_req;
      s4_lhs               <= s3_lhs;
      s4_rhs               <= s3_rhs;
      s4_addend            <= s3_addend;
      s4_product_sign      <= s3_product_sign;
      s4_addend_sign       <= s3_addend_sign;
      s4_product           <= s3_product;
      s4_product_zero      <= product_zero;
      s4_addend_sig_zero   <= addend_sig_zero;
      s4_prod_bit_base_exp <= prod_bit_base_exp;
      s4_add_bit_base_exp  <= add_bit_base_exp;
      s4_acc_lsb_exp       <= acc_lsb_exp;
    end
  end

  // --------------------------------------------------------------------------
  // S4: align product/addend into accumulator domain and add/subtract
  // --------------------------------------------------------------------------

  always_comb begin
    product_acc_mag = s4_product_zero ? '0 :
                      align_u106_to_acc(s4_product,
                                        s4_prod_bit_base_exp,
                                        s4_acc_lsb_exp);
    addend_acc_mag  = s4_addend_sig_zero ? '0 :
                      align_u53_to_acc(s4_addend.sig,
                                       s4_add_bit_base_exp,
                                       s4_acc_lsb_exp);
  end

  always_comb begin
    acc_sum_ext = '0;
    finite_mag  = '0;
    finite_sign = s4_product_sign;

    if (s4_product_sign == s4_addend_sign) begin
      acc_sum_ext = {1'b0, product_acc_mag} + {1'b0, addend_acc_mag};
      finite_mag  = acc_sum_ext[159:0];
      finite_sign = s4_product_sign;
    end else if (product_acc_mag > addend_acc_mag) begin
      finite_mag  = product_acc_mag - addend_acc_mag;
      finite_sign = s4_product_sign;
    end else if (addend_acc_mag > product_acc_mag) begin
      finite_mag  = addend_acc_mag - product_acc_mag;
      finite_sign = s4_addend_sign;
    end else begin
      finite_mag  = '0;
      finite_sign = zero_result_sign(s4_product_sign, s4_addend_sign, s4_req.rm);
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s5_valid        <= 1'b0;
      s5_valid_op     <= 1'b0;
      s5_req          <= '0;
      s5_lhs          <= '0;
      s5_rhs          <= '0;
      s5_addend       <= '0;
      s5_product_sign <= 1'b0;
      s5_addend_sign  <= 1'b0;
      s5_finite_mag   <= '0;
      s5_finite_sign  <= 1'b0;
      s5_acc_lsb_exp  <= 16'sd0;
    end else begin
      s5_valid        <= s4_valid;
      s5_valid_op     <= s4_valid_op;
      s5_req          <= s4_req;
      s5_lhs          <= s4_lhs;
      s5_rhs          <= s4_rhs;
      s5_addend       <= s4_addend;
      s5_product_sign <= s4_product_sign;
      s5_addend_sign  <= s4_addend_sign;
      s5_finite_mag   <= finite_mag;
      s5_finite_sign  <= finite_sign;
      s5_acc_lsb_exp  <= s4_acc_lsb_exp;
    end
  end

  // --------------------------------------------------------------------------
  // S5: result leading-one detect, normalize, round, pack, and special mux
  // --------------------------------------------------------------------------

  fpu_lop #(
    .DATA_W(64)
  ) u_finite_hi_lop (
    .data_i(s5_finite_mag[159:96]),
    .pos_o (finite_hi_lop_pos),
    .zero_o(finite_hi_zero)
  );

  fpu_lop #(
    .DATA_W(64)
  ) u_finite_mid_lop (
    .data_i(s5_finite_mag[95:32]),
    .pos_o (finite_mid_lop_pos),
    .zero_o(finite_mid_zero)
  );

  fpu_lop #(
    .DATA_W(32)
  ) u_finite_lo_lop (
    .data_i(s5_finite_mag[31:0]),
    .pos_o (finite_lo_lop_pos),
    .zero_o(finite_lo_zero)
  );

  always_comb begin
    if (!finite_hi_zero) begin
      finite_lop_pos = 8'd96 + {2'd0, finite_hi_lop_pos};
    end else if (!finite_mid_zero) begin
      finite_lop_pos = 8'd32 + {2'd0, finite_mid_lop_pos};
    end else begin
      finite_lop_pos = {2'd0, finite_lo_lop_pos};
    end
  end

  assign finite_zero    = finite_hi_zero && finite_mid_zero && finite_lo_zero;
  assign finite_top_exp = s5_acc_lsb_exp + $signed({8'd0, finite_lop_pos});
  assign norm_sig       = finite_zero ? 64'd0 :
                                        normalize_acc_sig(s5_finite_mag,
                                                          finite_lop_pos);

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
    logic signed [15:0] subnorm_shamt_calc;

    raw_exp       = 16'sd0;
    finite_exp    = 16'sd0;
    finite_sig    = norm_sig;
    subnorm_shamt = 7'd0;
    subnorm_shamt_calc = 16'sd0;

    if (!finite_zero) begin
      raw_exp = finite_top_exp + $signed(exp_bias(s5_req.rs_fmt));

      if (raw_exp <= 16'sd0) begin
        finite_exp = 16'sd0;

        if (raw_exp <= -16'sd63) begin
          subnorm_shamt = 7'd64;
        end else begin
          subnorm_shamt_calc = 16'sd1 - raw_exp;
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
    unique case (s5_req.rs_fmt)
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
    .rm_i     (s5_req.rm),
    .sign_i   (s5_finite_sign),
    .lsb_i    (result_lsb),
    .grs_i    (result_grs),
    .inexact_o(result_inexact),
    .inc_o    (result_round_inc)
  );

  // --------------------------------------------------------------------------
  // Finite pack and final special-case result mux
  // --------------------------------------------------------------------------

  assign packed_result = pack_result(
    s5_req.rs_fmt,
    s5_finite_sign,
    finite_exp,
    finite_sig,
    result_round_inc,
    result_inexact,
    s5_req.rm
  );

  always_comb begin
    logic invalid_mul;
    logic product_is_inf;
    logic invalid_inf_add;

    invalid_mul     = (s5_lhs.is_inf && s5_rhs.is_zero) ||
                      (s5_lhs.is_zero && s5_rhs.is_inf);
    product_is_inf  = s5_lhs.is_inf || s5_rhs.is_inf;
    invalid_inf_add = product_is_inf && s5_addend.is_inf &&
                      (s5_product_sign != s5_addend_sign);

    resp_d     = '0;
    resp_d.tag = s5_req.tag;
    resp_d.rd  = s5_req.rd;
    valid_op_o = s5_valid && s5_valid_op;

    if (!valid_op_o) begin
      resp_d = '0;
      resp_d.tag = s5_req.tag;
      resp_d.rd  = s5_req.rd;
    end else if (s5_lhs.is_nan || s5_rhs.is_nan || s5_addend.is_nan ||
                 invalid_mul || invalid_inf_add) begin
      resp_d.result = canonical_nan(s5_req.rs_fmt);
      resp_d.fflags[FPU_FFLAG_NV] = s5_lhs.is_snan || s5_rhs.is_snan ||
                                    s5_addend.is_snan || invalid_mul ||
                                    invalid_inf_add;
    end else if (product_is_inf) begin
      resp_d.result = pack_inf(s5_req.rs_fmt, s5_product_sign);
    end else if (s5_addend.is_inf) begin
      resp_d.result = pack_inf(s5_req.rs_fmt, s5_addend_sign);
    end else if (finite_zero) begin
      resp_d.result = pack_zero(s5_req.rs_fmt, s5_finite_sign);
    end else begin
      resp_d.result = packed_result.result;
      resp_d.fflags = packed_result.fflags;
    end
  end

  assign valid_o = s5_valid;
  assign resp_o = resp_d;

endmodule : fpu_fma_unit_pipe
