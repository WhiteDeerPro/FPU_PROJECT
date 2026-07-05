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

module fpu_add_unit
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

  logic [52:0] big_ext;
  logic [52:0] small_ext;
  logic [5:0]  align_shamt;
  logic [52:0] small_shifted_raw;
  logic [52:0] small_lost;
  logic [52:0] small_shifted;
  logic [3:0]  small_tail;
  logic [53:0] add_sum;
  logic [52:0] sub_diff_main;
  logic [52:0] sub_diff_corr;
  logic [53:0] close_diff;
  logic [5:0]  close_lop_pos;
  logic        close_is_zero;
  logic [5:0]  norm_shamt;
  logic [5:0]  subnorm_shamt;
  logic [57:0] close_norm_ext;
  logic [52:0] finite_main;
  logic [3:0]  finite_tail;

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

  function automatic logic [3:0] align_tail_bits(
    input logic [52:0] sig,
    input logic [10:0] shamt
  );
    logic [3:0] tail;

    tail = 4'd0;
    for (int unsigned i = 0; i < 53; i++) begin
      if (shamt == (i + 1)) begin
        tail[3] = sig[i];
      end
      if (shamt == (i + 2)) begin
        tail[2] = sig[i];
      end
      if (shamt == (i + 3)) begin
        tail[1] = sig[i];
      end
      if (shamt > (i + 3)) begin
        tail[0] |= sig[i];
      end
    end

    return tail;
  endfunction

  function automatic logic [3:0] complement_tail_bits(input logic [3:0] tail);
    logic [3:0] comp_prefix;

    if (tail == 4'd0) begin
      return 4'd0;
    end

    comp_prefix = 4'd8 - {1'b0, tail[3:1]} - {3'd0, tail[0]};
    return {comp_prefix[2:0], tail[0]};
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
  // Unpack, operation decode, and operand ordering
  // --------------------------------------------------------------------------

  assign op_is_sub = (req_i.op == FPU_OP_SUB);
  assign lhs       = unpack_operand(req_i.src_a, req_i.rs_fmt);
  assign rhs_raw   = unpack_operand(req_i.src_b, req_i.rs_fmt);
  assign rhs.sign  = rhs_raw.sign ^ op_is_sub;
  assign rhs.exp   = rhs_raw.exp;
  assign rhs.sig   = rhs_raw.sig;
  assign rhs.is_zero = rhs_raw.is_zero;
  assign rhs.is_inf  = rhs_raw.is_inf;
  assign rhs.is_nan  = rhs_raw.is_nan;

  always_comb begin
    if ((lhs.exp > rhs.exp) || ((lhs.exp == rhs.exp) && (lhs.sig >= rhs.sig))) begin
      big_op   = lhs;
      small_op = rhs;
    end else begin
      big_op   = rhs;
      small_op = lhs;
    end
  end

  assign operands_same_sign = (lhs.sign == rhs.sign);
  assign exp_diff           = big_op.exp - small_op.exp;
  assign use_single_path    = (req_i.rs_fmt == FPU_FMT_S);

  // --------------------------------------------------------------------------
  // Shared 53-bit align/add/sub datapath
  // --------------------------------------------------------------------------

  assign big_ext     = big_op.sig;
  assign small_ext   = small_op.sig;
  assign align_shamt = (exp_diff > 11'd53) ? 6'd53 : exp_diff[5:0];

  fpu_barrel_shifter #(
    .WIDTH        (53),
    .SUPPORT_LEFT (1'b0),
    .SUPPORT_RIGHT(1'b1)
  ) u_align_shifter (
    .data_i      (small_ext),
    .shamt_i     (align_shamt),
    .left_data_o (),
    .right_data_o(small_shifted_raw),
    .right_lost_o(small_lost)
  );

  assign small_shifted = (exp_diff > 11'd53) ? 53'd0 : small_shifted_raw;
  assign small_tail    = small_op.is_zero ? 4'd0 : align_tail_bits(small_ext, exp_diff);

  assign add_sum       = {1'b0, big_ext} + {1'b0, small_shifted};
  assign sub_diff_main = big_ext - small_shifted;
  assign sub_diff_corr = sub_diff_main - {52'd0, |small_tail};
  assign close_diff    = (exp_diff == 11'd0) ? ({big_ext, 1'b0} - {small_ext, 1'b0}) :
                                               ({big_ext, 1'b0} - {1'b0, small_ext});

  fpu_lop #(
    .DATA_W(54)
  ) u_close_lop (
    .data_i(close_diff),
    .pos_o (close_lop_pos),
    .zero_o(close_is_zero)
  );

  assign small_shifted_s = small_shifted;
  assign add_sum_s       = add_sum;
  assign sub_diff_s      = (exp_diff <= 11'd1) ? close_diff[53:1] : sub_diff_corr;
  assign sub_lop_pos_s   = close_lop_pos;
  assign sub_is_zero_s   = close_is_zero;
  assign small_shifted_d = small_shifted;
  assign add_sum_d       = add_sum;
  assign sub_diff_d      = (exp_diff <= 11'd1) ? close_diff[53:1] : sub_diff_corr;
  assign sub_lop_pos_d   = close_lop_pos;
  assign sub_is_zero_d   = close_is_zero;
  assign sub_is_zero     = (exp_diff <= 11'd1) ? close_is_zero :
                                                 (sub_diff_corr == 53'd0);

  // --------------------------------------------------------------------------
  // Normalize finite add/sub result
  // --------------------------------------------------------------------------

  always_comb begin
    finite_sign       = big_op.sign;
    finite_exp        = big_op.exp;
    finite_sig        = 64'd0;
    finite_zero       = 1'b0;
    norm_shamt       = 6'd0;
    subnorm_shamt    = 6'd0;
    close_norm_ext   = 58'd0;
    finite_main      = 53'd0;
    finite_tail      = 4'd0;

    if (operands_same_sign) begin
      finite_sign = lhs.sign;

      if (add_sum[53]) begin
        finite_main = add_sum[53:1];
        finite_tail = {add_sum[0], small_tail[3], small_tail[2],
                       small_tail[1] | small_tail[0]};
        finite_exp  = big_op.exp + 11'd1;
      end else begin
        finite_main = add_sum[52:0];
        finite_tail = small_tail;
        finite_exp  = (add_sum[52] || (big_op.exp != 11'd1)) ?
                      big_op.exp : 11'd0;
      end
    end else if (sub_is_zero) begin
      finite_sign = zero_result_sign(lhs.sign, rhs.sign, req_i.rm);
      finite_exp  = 11'd0;
      finite_sig  = 64'd0;
      finite_zero = 1'b1;
    end else begin
      finite_sign = big_op.sign;

      if (exp_diff <= 11'd1) begin
        norm_shamt = 6'd53 - close_lop_pos;

        if ({5'd0, norm_shamt} < big_op.exp) begin
          close_norm_ext = {close_diff, 4'd0} << norm_shamt;
          finite_exp     = big_op.exp - {5'd0, norm_shamt};
        end else begin
          subnorm_shamt  = (big_op.exp == 11'd0) ? 6'd0 :
                           big_op.exp[5:0] - 6'd1;
          close_norm_ext = {close_diff, 4'd0} << subnorm_shamt;
          finite_exp     = 11'd0;
        end

        finite_main = close_norm_ext[57:5];
        finite_tail = {close_norm_ext[4], close_norm_ext[3], close_norm_ext[2],
                       |close_norm_ext[1:0]};
      end else begin
        finite_main = sub_diff_corr;
        finite_tail = complement_tail_bits(small_tail);

        if (!sub_diff_corr[52] && (big_op.exp > 11'd1)) begin
          finite_main = {sub_diff_corr[51:0], finite_tail[3]};
          finite_tail = {finite_tail[2], finite_tail[1], 1'b0, finite_tail[0]};
          finite_exp  = big_op.exp - 11'd1;
        end else if (!sub_diff_corr[52]) begin
          finite_exp = 11'd0;
        end else begin
          finite_exp = big_op.exp;
        end
      end
    end

    if (use_single_path) begin
      finite_sig        = 64'd0;
      finite_sig[63:40] = finite_main[52:29];
      finite_sig[39]    = finite_main[28];
      finite_sig[38]    = finite_main[27];
      finite_sig[37]    = |finite_main[26:0] | |finite_tail;
    end else begin
      finite_sig        = 64'd0;
      finite_sig[63:11] = finite_main;
      finite_sig[10]    = finite_tail[3];
      finite_sig[9]     = finite_tail[2];
      finite_sig[8]     = finite_tail[1] | finite_tail[0];
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
    valid_op_o = ((req_i.op == FPU_OP_ADD) || (req_i.op == FPU_OP_SUB)) &&
                 ((req_i.rs_fmt == FPU_FMT_S) || (req_i.rs_fmt == FPU_FMT_D)) &&
                 rm_is_supported(req_i.rm);

    if (!valid_op_o) begin
      resp_d = '0;
      resp_d.tag = req_i.tag;
      resp_d.rd  = req_i.rd;
    end else if (lhs.is_nan || rhs.is_nan ||
                 (lhs.is_inf && rhs.is_inf && (lhs.sign != rhs.sign))) begin
      resp_d.result = canonical_nan(req_i.rs_fmt);
      resp_d.fflags[FPU_FFLAG_NV] = lhs.is_inf && rhs.is_inf && (lhs.sign != rhs.sign);
    end else if (lhs.is_inf) begin
      resp_d.result = pack_inf(req_i.rs_fmt, lhs.sign);
    end else if (rhs.is_inf) begin
      resp_d.result = pack_inf(req_i.rs_fmt, rhs.sign);
    end else if (lhs.is_zero && rhs.is_zero) begin
      resp_d.result = (req_i.rs_fmt == FPU_FMT_S) ?
                      nanbox_s({zero_result_sign(lhs.sign, rhs.sign, req_i.rm), 31'd0}) :
                      {zero_result_sign(lhs.sign, rhs.sign, req_i.rm), 63'd0};
    end else if (finite_zero) begin
      resp_d.result = (req_i.rs_fmt == FPU_FMT_S) ?
                      nanbox_s({finite_sign, 31'd0}) :
                      {finite_sign, 63'd0};
    end else begin
      resp_d.result = packed_result.result;
      resp_d.fflags = packed_result.fflags;
    end
  end

  assign resp_o = resp_d;

endmodule : fpu_add_unit
