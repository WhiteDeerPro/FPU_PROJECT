//============================================================================
// Floating-point add/subtract unit.
//
// Flow:
//   req_i
//     -> unpack/classify lhs and rhs
//     -> apply SUB sign inversion to rhs
//     -> choose big/small operand by exponent and significand
//     -> align the small significand and jam discarded bits into sticky
//     -> add same-sign operands or subtract opposite-sign operands
//     -> leading-one detect and normalize the finite result
//     -> select GRS/LSB, compute round increment, and pack
//     -> special-case result mux for NaN/Inf/zero/finite outputs
//
// The main arithmetic path is 53 bits wide. S operands are already unpacked into
// the high 24 bits of that path and are rounded from the lower bits at the end.
// Bits shifted out during alignment are kept only as GRS/sticky sideband state;
// they are not appended to the main add/sub operands as extra precision.
//============================================================================

module fpu_add_unit_pipe
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
  } fp_add_operand_t;

  typedef struct packed {
    fpu_data_t    result;
    fpu_fflags_t  fflags;
  } fp_add_pack_t;

  // --------------------------------------------------------------------------
  // Global datapath and control signals
  // --------------------------------------------------------------------------

  fpu_resp_t resp_d;

  fp_add_operand_t lhs;
  fp_add_operand_t rhs_raw;
  fp_add_operand_t rhs;
  fp_add_operand_t big_op;
  fp_add_operand_t small_op;

  logic        op_is_sub;
  logic        operands_same_sign;
  logic [10:0] exp_diff;
  logic        use_single_path;

  logic [52:0] small_shifted_s;
  logic [53:0] add_sum_s;
  logic [52:0] sub_diff_s;
  logic [5:0]  sub_lop_pos_s;
  logic        sub_is_zero_s;
  logic [52:0] small_shifted_d;
  logic [53:0] add_sum_d;
  logic [52:0] sub_diff_d;
  logic [5:0]  sub_lop_pos_d;
  logic        sub_is_zero_d;

  logic        sub_is_zero;

  logic        finite_sign;
  logic [10:0] finite_exp;
  logic [63:0] finite_sig;
  logic        finite_zero;

  fpu_grs_t    result_grs;
  fpu_grs_t    result_s_grs;
  fpu_grs_t    result_d_grs;
  logic [39:0] result_s_grs_bits;
  logic [10:0] result_d_grs_bits;
  logic        result_lsb;
  logic        result_inexact;
  logic        result_round_inc;
  fp_add_pack_t packed_result;



  // Stage 0: unpack, order, align, and jam.
  logic             s0_op_is_sub;
  logic             s0_operands_same_sign;
  logic             s0_use_single_path;
  logic             s0_valid_op;
  logic [10:0]      s0_exp_diff;
  fp_add_operand_t  s0_lhs;
  fp_add_operand_t  s0_rhs_raw;
  fp_add_operand_t  s0_rhs;
  fp_add_operand_t  s0_big_op;
  fp_add_operand_t  s0_small_op;
  logic [52:0]      s0_big_ext;
  logic [52:0]      s0_small_ext;
  logic [5:0]       s0_align_shamt;
  logic [52:0]      s0_small_shifted_raw;
  logic [52:0]      s0_small_lost;
  logic [52:0]      s0_small_shifted;
  fpu_grs_t         s0_align_grs;

  // Stage 1 register: aligned operands and sideband control.
  logic             s1_valid;
  logic             s1_valid_op;
  fpu_req_t         s1_req;
  fp_add_operand_t  s1_lhs;
  fp_add_operand_t  s1_rhs;
  fp_add_operand_t  s1_big_op;
  logic             s1_operands_same_sign;
  logic             s1_use_single_path;
  logic [10:0]      s1_exp_diff;
  logic [52:0]      s1_big_ext;
  logic [52:0]      s1_small_ext;
  logic [52:0]      s1_small_shifted;
  fpu_grs_t         s1_align_grs;
  logic [52:0]      s1_small_shifted_s;
  logic [52:0]      s1_small_shifted_d;

  // Stage 1: add/subtract and leading-one detect.
  logic [53:0]      s1_add_sum;
  logic [52:0]      s1_sub_diff_main;
  logic [52:0]      s1_sub_diff_corr;
  logic [53:0]      s1_close_diff;
  logic [53:0]      s1_add_sum_s;
  logic [52:0]      s1_sub_diff_s;
  logic [5:0]       s1_sub_lop_pos_s;
  logic             s1_sub_is_zero_s;
  logic [53:0]      s1_add_sum_d;
  logic [52:0]      s1_sub_diff_d;
  logic [5:0]       s1_sub_lop_pos_d;
  logic             s1_sub_is_zero_d;
  logic [5:0]       s1_close_lop_pos;
  logic             s1_close_is_zero;
  logic             s1_sub_is_zero;
  fpu_grs_t         s1_add_grs_s;
  fpu_grs_t         s1_add_grs_d;
  fpu_grs_t         s1_far_sub_grs_s;
  fpu_grs_t         s1_far_sub_grs_d;
  logic             s1_far_sub_shift_bit;

  // Stage 2 register: arithmetic result and sideband control.
  logic             s2_valid;
  logic             s2_valid_op;
  fpu_req_t         s2_req;
  fp_add_operand_t  s2_lhs;
  fp_add_operand_t  s2_rhs;
  fp_add_operand_t  s2_big_op;
  logic             s2_operands_same_sign;
  logic             s2_use_single_path;
  logic [10:0]      s2_exp_diff;
  logic [53:0]      s2_add_sum;
  logic [52:0]      s2_sub_diff_corr;
  logic [53:0]      s2_close_diff;
  logic [5:0]       s2_close_lop_pos;
  logic             s2_close_is_zero;
  logic             s2_sub_is_zero;
  fpu_grs_t         s2_add_grs_s;
  fpu_grs_t         s2_add_grs_d;
  fpu_grs_t         s2_far_sub_grs_s;
  fpu_grs_t         s2_far_sub_grs_d;
  logic             s2_far_sub_shift_bit;

  // Stage 2: normalize, GRS selection, rounding, finite pack, and special-case mux.
  logic             s2_finite_sign;
  logic [10:0]      s2_finite_exp;
  logic [63:0]      s2_finite_sig;
  logic             s2_finite_zero;
  logic [5:0]       s2_norm_shamt;
  logic [5:0]       s2_subnorm_shamt;
  logic [57:0]      s2_close_norm_ext;
  logic [52:0]      s2_finite_main;
  fpu_grs_t         s2_finite_grs;

  fpu_resp_t        s2_resp_d;
  fpu_grs_t         s2_result_grs;
  logic             s2_result_lsb;
  logic             s2_result_inexact;
  logic             s2_result_round_inc;
  fp_add_pack_t     s2_packed_result;

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

  function automatic fp_add_operand_t unpack_operand(
    input fpu_data_t data,
    input fpu_fmt_e  fmt
  );
    fp_add_operand_t op;
    logic            s_is_boxed;

    op = '0;
    s_is_boxed = &data[63:32];

    unique case (fmt)
      FPU_FMT_S: begin
        if (!s_is_boxed) begin
          op.is_nan = 1'b1;
          op.exp    = 11'h0ff;
          op.sig    = {1'b1, 23'h40_0000, 29'd0};
        end else begin
          op.sign    = data[31];
          op.exp     = {3'd0, data[30:23]};
          op.is_zero = (data[30:0] == 31'd0);
          op.is_inf  = (data[30:23] == 8'hff) && (data[22:0] == 23'd0);
          op.is_nan  = (data[30:23] == 8'hff) && (data[22:0] != 23'd0);
          op.sig     = (data[30:23] == 8'd0) ?
                       {1'b0, data[22:0], 29'd0} :
                       {1'b1, data[22:0], 29'd0};

          if (!op.is_zero && op.exp == 11'd0) begin
            op.exp = 11'd1;
          end
        end
      end

      FPU_FMT_D: begin
        op.sign    = data[63];
        op.exp     = data[62:52];
        op.is_zero = (data[62:0] == 63'd0);
        op.is_inf  = (data[62:52] == 11'h7ff) && (data[51:0] == 52'd0);
        op.is_nan  = (data[62:52] == 11'h7ff) && (data[51:0] != 52'd0);
        op.sig     = (data[62:52] == 11'd0) ?
                     {1'b0, data[51:0]} :
                     {1'b1, data[51:0]};

        if (!op.is_zero && op.exp == 11'd0) begin
          op.exp = 11'd1;
        end
      end

      default: begin end
    endcase

    return op;
  endfunction

  function automatic fpu_grs_t align_grs_bits(
    input logic [52:0] sig,
    input logic [10:0] shamt
  );
    fpu_grs_t grs;

    grs = '0;
    for (int unsigned i = 0; i < 53; i++) begin
      if (shamt == (i + 1)) begin
        grs.guard = sig[i];
      end
      if (shamt == (i + 2)) begin
        grs.round = sig[i];
      end
      if (shamt > (i + 2)) begin
        grs.sticky |= sig[i];
      end
    end

    return grs;
  endfunction

  function automatic fpu_grs_t complement_grs_bits(input fpu_grs_t grs);
    logic [2:0] raw_bits;
    logic [3:0] comp_bits;
    fpu_grs_t   comp_grs;

    raw_bits = {grs.guard, grs.round, grs.sticky};
    comp_grs = '0;

    if (raw_bits == 3'd0) begin
      return comp_grs;
    end

    comp_bits = 4'd8 - {1'b0, raw_bits};
    comp_grs.guard  = comp_bits[2];
    comp_grs.round  = comp_bits[1];
    comp_grs.sticky = comp_bits[0];
    return comp_grs;
  endfunction

  function automatic fpu_grs_t shift_right_one_grs(
    input logic     shifted_lsb,
    input fpu_grs_t old_grs
  );
    fpu_grs_t grs;

    grs.guard  = shifted_lsb;
    grs.round  = old_grs.guard;
    grs.sticky = old_grs.round | old_grs.sticky;
    return grs;
  endfunction

  function automatic fpu_grs_t shift_left_one_grs(input fpu_grs_t old_grs);
    fpu_grs_t grs;

    grs.guard  = old_grs.round;
    grs.round  = 1'b0;
    grs.sticky = old_grs.sticky;
    return grs;
  endfunction

  function automatic fpu_grs_t precision_grs(
    input fpu_fmt_e     fmt,
    input logic [52:0]  main,
    input fpu_grs_t     tail_grs
  );
    fpu_grs_t grs;

    grs = tail_grs;
    if (fmt == FPU_FMT_S) begin
      grs.guard  = main[28];
      grs.round  = main[27];
      grs.sticky = |main[26:0] | tail_grs.guard |
                   tail_grs.round | tail_grs.sticky;
    end

    return grs;
  endfunction

  function automatic fp_add_pack_t pack_result(
    input fpu_fmt_e     fmt,
    input logic         sign,
    input logic [10:0]  exp,
    input logic [63:0]  sig,
    input logic         round_inc,
    input logic         inexact,
    input fpu_rm_e      rm
  );
    fp_add_pack_t pack;
    logic [7:0]   exp_s;
    logic [10:0]  exp_d;
    logic [22:0]  mant_s;
    logic [51:0]  mant_d;
    logic [23:0]  mant_s_round;
    logic [52:0]  mant_d_round;
    logic         overflow;

    pack = '0;
    exp_s = exp[7:0];
    exp_d = exp;
    mant_s = 23'd0;
    mant_d = 52'd0;
    overflow = 1'b0;

    if (sig == 64'd0) begin
      pack.result = (fmt == FPU_FMT_S) ? nanbox_s({sign, 31'd0}) :
                                         {sign, 63'd0};
      return pack;
    end

    if (fmt == FPU_FMT_S) begin
      mant_s_round = {1'b0, sig[62:40]} + {23'd0, round_inc};

      if (exp == 11'd0) begin
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

      overflow = (exp > 11'd254) || (exp_s == 8'hff);
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

      if (exp == 11'd0) begin
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

      overflow = (exp > 11'd2046) || (exp_d == 11'h7ff);
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
  // Stage 0: unpack, operation decode, operand ordering, and alignment
  // --------------------------------------------------------------------------

  assign s0_op_is_sub = (req_i.op == FPU_OP_SUB);
  assign s0_lhs       = unpack_operand(req_i.src_a, req_i.rs_fmt);
  assign s0_rhs_raw   = unpack_operand(req_i.src_b, req_i.rs_fmt);
  assign s0_rhs.sign  = s0_rhs_raw.sign ^ s0_op_is_sub;
  assign s0_rhs.exp   = s0_rhs_raw.exp;
  assign s0_rhs.sig   = s0_rhs_raw.sig;
  assign s0_rhs.is_zero = s0_rhs_raw.is_zero;
  assign s0_rhs.is_inf  = s0_rhs_raw.is_inf;
  assign s0_rhs.is_nan  = s0_rhs_raw.is_nan;

  assign s0_valid_op = ((req_i.op == FPU_OP_ADD) || (req_i.op == FPU_OP_SUB)) &&
                       ((req_i.rs_fmt == FPU_FMT_S) || (req_i.rs_fmt == FPU_FMT_D)) &&
                       rm_is_supported(req_i.rm);

  always_comb begin
    if ((s0_lhs.exp > s0_rhs.exp) ||
        ((s0_lhs.exp == s0_rhs.exp) && (s0_lhs.sig >= s0_rhs.sig))) begin
      s0_big_op   = s0_lhs;
      s0_small_op = s0_rhs;
    end else begin
      s0_big_op   = s0_rhs;
      s0_small_op = s0_lhs;
    end
  end

  assign s0_operands_same_sign = (s0_lhs.sign == s0_rhs.sign);
  assign s0_exp_diff           = s0_big_op.exp - s0_small_op.exp;
  assign s0_use_single_path    = (req_i.rs_fmt == FPU_FMT_S);

  assign s0_big_ext     = s0_big_op.sig;
  assign s0_small_ext   = s0_small_op.sig;
  assign s0_align_shamt = (s0_exp_diff > 11'd53) ? 6'd53 : s0_exp_diff[5:0];

  fpu_barrel_shifter #(
    .WIDTH        (53),
    .SUPPORT_LEFT (1'b0),
    .SUPPORT_RIGHT(1'b1)
  ) u_s0_align_shifter (
    .data_i      (s0_small_ext),
    .shamt_i     (s0_align_shamt),
    .left_data_o (),
    .right_data_o(s0_small_shifted_raw),
    .right_lost_o(s0_small_lost)
  );

  assign s0_small_shifted = (s0_exp_diff > 11'd53) ? 53'd0 : s0_small_shifted_raw;
  assign s0_align_grs     = s0_small_op.is_zero ? '0 :
                                                  align_grs_bits(s0_small_ext, s0_exp_diff);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s1_valid               <= 1'b0;
      s1_valid_op            <= 1'b0;
      s1_req                 <= '0;
      s1_lhs                 <= '0;
      s1_rhs                 <= '0;
      s1_big_op              <= '0;
      s1_operands_same_sign  <= 1'b0;
      s1_use_single_path     <= 1'b0;
      s1_exp_diff            <= 11'd0;
      s1_big_ext             <= '0;
      s1_small_ext           <= '0;
      s1_small_shifted       <= '0;
      s1_align_grs           <= '0;
    end else begin
      s1_valid               <= valid_i;
      s1_valid_op            <= s0_valid_op;
      s1_req                 <= req_i;
      s1_lhs                 <= s0_lhs;
      s1_rhs                 <= s0_rhs;
      s1_big_op              <= s0_big_op;
      s1_operands_same_sign  <= s0_operands_same_sign;
      s1_use_single_path     <= s0_use_single_path;
      s1_exp_diff            <= s0_exp_diff;
      s1_big_ext             <= s0_big_ext;
      s1_small_ext           <= s0_small_ext;
      s1_small_shifted       <= s0_small_shifted;
      s1_align_grs           <= s0_align_grs;
    end
  end

  // --------------------------------------------------------------------------
  // Stage 1: add/subtract and leading-one detect
  // --------------------------------------------------------------------------

  assign s1_add_sum       = {1'b0, s1_big_ext} + {1'b0, s1_small_shifted};
  assign s1_sub_diff_main = s1_big_ext - s1_small_shifted;
  assign s1_sub_diff_corr = s1_sub_diff_main -
                             {52'd0, s1_align_grs.guard |
                                     s1_align_grs.round |
                                     s1_align_grs.sticky};
  assign s1_close_diff    = (s1_exp_diff == 11'd0) ?
                            ({s1_big_ext, 1'b0} - {s1_small_ext, 1'b0}) :
                            ({s1_big_ext, 1'b0} - {1'b0, s1_small_ext});
  assign s1_small_shifted_s = s1_small_shifted;
  assign s1_small_shifted_d = s1_small_shifted;

  fpu_lop #(
    .DATA_W(54)
  ) u_s1_close_lop (
    .data_i(s1_close_diff),
    .pos_o (s1_close_lop_pos),
    .zero_o(s1_close_is_zero)
  );

  assign s1_add_sum_s     = s1_add_sum;
  assign s1_sub_diff_s    = (s1_exp_diff <= 11'd1) ? s1_close_diff[53:1] :
                                                        s1_sub_diff_corr;
  assign s1_sub_lop_pos_s = s1_close_lop_pos;
  assign s1_sub_is_zero_s = s1_close_is_zero;
  assign s1_add_sum_d     = s1_add_sum;
  assign s1_sub_diff_d    = (s1_exp_diff <= 11'd1) ? s1_close_diff[53:1] :
                                                        s1_sub_diff_corr;
  assign s1_sub_lop_pos_d = s1_close_lop_pos;
  assign s1_sub_is_zero_d = s1_close_is_zero;
  assign s1_sub_is_zero   = (s1_exp_diff <= 11'd1) ? s1_close_is_zero :
                                                        (s1_sub_diff_corr == 53'd0);

  always_comb begin
    fpu_grs_t add_grs;
    fpu_grs_t far_sub_grs;
    logic [52:0] far_sub_main;

    if (s1_add_sum[53]) begin
      add_grs = shift_right_one_grs(s1_add_sum[0], s1_align_grs);
      s1_add_grs_s = precision_grs(FPU_FMT_S, s1_add_sum[53:1], add_grs);
      s1_add_grs_d = add_grs;
    end else begin
      add_grs = s1_align_grs;
      s1_add_grs_s = precision_grs(FPU_FMT_S, s1_add_sum[52:0], add_grs);
      s1_add_grs_d = add_grs;
    end

    far_sub_grs  = complement_grs_bits(s1_align_grs);
    far_sub_main = s1_sub_diff_corr;
    s1_far_sub_shift_bit = far_sub_grs.guard;

    if (!s1_sub_diff_corr[52] && (s1_big_op.exp > 11'd1)) begin
      far_sub_main = {s1_sub_diff_corr[51:0], far_sub_grs.guard};
      far_sub_grs  = shift_left_one_grs(far_sub_grs);
    end

    s1_far_sub_grs_s = precision_grs(FPU_FMT_S, far_sub_main, far_sub_grs);
    s1_far_sub_grs_d = far_sub_grs;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s2_valid               <= 1'b0;
      s2_valid_op            <= 1'b0;
      s2_req                 <= '0;
      s2_lhs                 <= '0;
      s2_rhs                 <= '0;
      s2_big_op              <= '0;
      s2_operands_same_sign  <= 1'b0;
      s2_use_single_path     <= 1'b0;
      s2_exp_diff            <= 11'd0;
      s2_add_sum             <= 54'd0;
      s2_sub_diff_corr       <= 53'd0;
      s2_close_diff          <= 54'd0;
      s2_close_lop_pos       <= 6'd0;
      s2_close_is_zero       <= 1'b0;
      s2_sub_is_zero         <= 1'b0;
      s2_add_grs_s          <= '0;
      s2_add_grs_d          <= '0;
      s2_far_sub_grs_s      <= '0;
      s2_far_sub_grs_d      <= '0;
      s2_far_sub_shift_bit  <= 1'b0;
    end else begin
      s2_valid               <= s1_valid;
      s2_valid_op            <= s1_valid_op;
      s2_req                 <= s1_req;
      s2_lhs                 <= s1_lhs;
      s2_rhs                 <= s1_rhs;
      s2_big_op              <= s1_big_op;
      s2_operands_same_sign  <= s1_operands_same_sign;
      s2_use_single_path     <= s1_use_single_path;
      s2_exp_diff            <= s1_exp_diff;
      s2_add_sum             <= s1_add_sum;
      s2_sub_diff_corr       <= s1_sub_diff_corr;
      s2_close_diff          <= s1_close_diff;
      s2_close_lop_pos       <= s1_close_lop_pos;
      s2_close_is_zero       <= s1_close_is_zero;
      s2_sub_is_zero         <= s1_sub_is_zero;
      s2_add_grs_s          <= s1_add_grs_s;
      s2_add_grs_d          <= s1_add_grs_d;
      s2_far_sub_grs_s      <= s1_far_sub_grs_s;
      s2_far_sub_grs_d      <= s1_far_sub_grs_d;
      s2_far_sub_shift_bit  <= s1_far_sub_shift_bit;
    end
  end

  // --------------------------------------------------------------------------
  // Stage 2: normalize, GRS selection, rounding, finite pack, and special-case mux
  // --------------------------------------------------------------------------

  always_comb begin
    s2_finite_sign       = s2_big_op.sign;
    s2_finite_exp        = s2_big_op.exp;
    s2_finite_sig        = 64'd0;
    s2_finite_zero       = 1'b0;
    s2_norm_shamt        = 6'd0;
    s2_subnorm_shamt     = 6'd0;
    s2_close_norm_ext    = 58'd0;
    s2_finite_main       = 53'd0;
    s2_finite_grs        = '0;

    if (s2_operands_same_sign) begin
      s2_finite_sign = s2_lhs.sign;

      if (s2_add_sum[53]) begin
        s2_finite_main = s2_add_sum[53:1];
        s2_finite_exp  = s2_big_op.exp + 11'd1;
      end else begin
        s2_finite_main = s2_add_sum[52:0];
        s2_finite_exp  = (s2_add_sum[52] || (s2_big_op.exp != 11'd1)) ?
                         s2_big_op.exp : 11'd0;
      end

      s2_finite_grs = s2_use_single_path ? s2_add_grs_s : s2_add_grs_d;
    end else if (s2_sub_is_zero) begin
      s2_finite_sign = zero_result_sign(s2_lhs.sign, s2_rhs.sign, s2_req.rm);
      s2_finite_exp  = 11'd0;
      s2_finite_sig  = 64'd0;
      s2_finite_zero = 1'b1;
    end else begin
      s2_finite_sign = s2_big_op.sign;

      if (s2_exp_diff <= 11'd1) begin
        s2_norm_shamt = 6'd53 - s2_close_lop_pos;

        if ({5'd0, s2_norm_shamt} < s2_big_op.exp) begin
          s2_close_norm_ext = {s2_close_diff, 4'd0} << s2_norm_shamt;
          s2_finite_exp     = s2_big_op.exp - {5'd0, s2_norm_shamt};
        end else begin
          s2_subnorm_shamt  = (s2_big_op.exp == 11'd0) ? 6'd0 :
                              s2_big_op.exp[5:0] - 6'd1;
          s2_close_norm_ext = {s2_close_diff, 4'd0} << s2_subnorm_shamt;
          s2_finite_exp     = 11'd0;
        end

        s2_finite_main = s2_close_norm_ext[57:5];
        s2_finite_grs.guard  = s2_close_norm_ext[4];
        s2_finite_grs.round  = s2_close_norm_ext[3];
        s2_finite_grs.sticky = |s2_close_norm_ext[2:0];
        s2_finite_grs = precision_grs(s2_req.rs_fmt, s2_finite_main, s2_finite_grs);
      end else begin
        s2_finite_main = s2_sub_diff_corr;

        if (!s2_sub_diff_corr[52] && (s2_big_op.exp > 11'd1)) begin
          s2_finite_main = {s2_sub_diff_corr[51:0],
                            s2_far_sub_shift_bit};
          s2_finite_exp  = s2_big_op.exp - 11'd1;
        end else if (!s2_sub_diff_corr[52]) begin
          s2_finite_exp = 11'd0;
        end else begin
          s2_finite_exp = s2_big_op.exp;
        end

        s2_finite_grs = s2_use_single_path ? s2_far_sub_grs_s :
                                             s2_far_sub_grs_d;
      end
    end

    if (s2_use_single_path) begin
      s2_finite_sig        = 64'd0;
      s2_finite_sig[63:40] = s2_finite_main[52:29];
      s2_finite_sig[39]    = s2_finite_grs.guard;
      s2_finite_sig[38]    = s2_finite_grs.round;
      s2_finite_sig[37]    = s2_finite_grs.sticky;
    end else begin
      s2_finite_sig        = 64'd0;
      s2_finite_sig[63:11] = s2_finite_main;
      s2_finite_sig[10]    = s2_finite_grs.guard;
      s2_finite_sig[9]     = s2_finite_grs.round;
      s2_finite_sig[8]     = s2_finite_grs.sticky;
    end
  end

  always_comb begin
    s2_result_grs = s2_finite_grs;
    s2_result_lsb = 1'b0;
    unique case (s2_req.rs_fmt)
      FPU_FMT_S: begin
        s2_result_lsb = s2_finite_sig[40];
      end

      FPU_FMT_D: begin
        s2_result_lsb = s2_finite_sig[11];
      end

      default: begin end
    endcase
  end

  fpu_round_inc u_s2_round (
    .rm_i     (s2_req.rm),
    .sign_i   (s2_finite_sign),
    .lsb_i    (s2_result_lsb),
    .grs_i    (s2_result_grs),
    .inexact_o(s2_result_inexact),
    .inc_o    (s2_result_round_inc)
  );

  assign s2_packed_result = pack_result(
    s2_req.rs_fmt,
    s2_finite_sign,
    s2_finite_exp,
    s2_finite_sig,
    s2_result_round_inc,
    s2_result_inexact,
    s2_req.rm
  );

  always_comb begin
    s2_resp_d     = '0;
    s2_resp_d.tag = s2_req.tag;
    s2_resp_d.rd  = s2_req.rd;

    if (!s2_valid_op) begin
      s2_resp_d = '0;
      s2_resp_d.tag = s2_req.tag;
      s2_resp_d.rd  = s2_req.rd;
    end else if (s2_lhs.is_nan || s2_rhs.is_nan ||
                 (s2_lhs.is_inf && s2_rhs.is_inf && (s2_lhs.sign != s2_rhs.sign))) begin
      s2_resp_d.result = canonical_nan(s2_req.rs_fmt);
      s2_resp_d.fflags[FPU_FFLAG_NV] = s2_lhs.is_inf && s2_rhs.is_inf &&
                                       (s2_lhs.sign != s2_rhs.sign);
    end else if (s2_lhs.is_inf) begin
      s2_resp_d.result = pack_inf(s2_req.rs_fmt, s2_lhs.sign);
    end else if (s2_rhs.is_inf) begin
      s2_resp_d.result = pack_inf(s2_req.rs_fmt, s2_rhs.sign);
    end else if (s2_lhs.is_zero && s2_rhs.is_zero) begin
      s2_resp_d.result = (s2_req.rs_fmt == FPU_FMT_S) ?
                         nanbox_s({zero_result_sign(s2_lhs.sign, s2_rhs.sign, s2_req.rm), 31'd0}) :
                         {zero_result_sign(s2_lhs.sign, s2_rhs.sign, s2_req.rm), 63'd0};
    end else if (s2_finite_zero) begin
      s2_resp_d.result = (s2_req.rs_fmt == FPU_FMT_S) ?
                         nanbox_s({s2_finite_sign, 31'd0}) :
                         {s2_finite_sign, 63'd0};
    end else begin
      s2_resp_d.result = s2_packed_result.result;
      s2_resp_d.fflags = s2_packed_result.fflags;
    end
  end

  assign valid_o    = s2_valid;
  assign valid_op_o = s2_valid ? s2_valid_op : 1'b0;
  assign resp_o     = s2_resp_d;

endmodule : fpu_add_unit_pipe
