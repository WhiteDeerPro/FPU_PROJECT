//============================================================================
// Pipelined floating-point conversion units.
//
// Each conversion leaf is split into two internal combinational stages:
//   stage 0 -> decode/normalize/shift/GRS preparation
//   stage 1 -> rounding, boundary checks, and response packing
//
// The wrapper runs I2F/F2F/F2I leaves in parallel and selects the response from
// the request delayed by the same two-cycle pipe.
//============================================================================

//----------------------------------------------------------------------------
// Integer to floating-point conversion, two-cycle pipe.
//----------------------------------------------------------------------------

module fpu_convert_i2f_unit_pipe
  import fpu_pkg::*;
(
  input  logic     clk_i,
  input  logic     rst_ni,
  input  logic     valid_i,
  input  fpu_req_t req_i,
  output logic     valid_o,
  output fpu_resp_t resp_o,
  output logic     valid_op_o
);

  typedef struct packed {
    logic      sign;
    fpu_data_t mag;
  } int_mag_t;

  logic      rm_is_valid;
  int_mag_t  int_src;
  logic      int_fmt_i32;
  logic [5:0] i2f_lop_pos;
  logic       i2f_is_zero;
  logic [6:0] i2f_shamt;
  fpu_data_t  i2f_sig;

  logic      s1_valid;
  fpu_req_t  s1_req;
  logic      s1_rm_is_valid;
  logic      s1_int_fmt_i32;
  logic      s1_sign;
  logic [5:0] s1_lop_pos;
  logic       s1_is_zero;
  fpu_data_t  s1_sig;

  logic [31:0] i2f_s_bits;
  logic [63:0] i2f_d_bits;
  logic [31:0] i2f_s_rounded_bits;
  logic [63:0] i2f_d_rounded_bits;
  logic [39:0] i2f_s_grs_bits;
  logic [10:0] i2f_d_grs_bits;
  fpu_grs_t    i2f_s_grs;
  fpu_grs_t    i2f_d_grs;
  logic        i2f_s_inexact;
  logic        i2f_d_inexact;
  logic        i2f_s_round_inc;
  logic        i2f_d_round_inc;
  fpu_resp_t   resp_d;
  logic        valid_op_d;

  logic      s2_valid;
  fpu_resp_t s2_resp;
  logic      s2_valid_op;

  function automatic logic [63:0] nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
  endfunction

  function automatic logic int_is_i32(input fpu_int_fmt_e int_fmt);
    return (int_fmt == FPU_INT_W) || (int_fmt == FPU_INT_WU);
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

  function automatic int_mag_t unpack_int(
    input logic [63:0]  data,
    input fpu_int_fmt_e int_fmt
  );
    int_mag_t unpacked;

    unpacked = '0;

    unique case (int_fmt)
      FPU_INT_W: begin
        unpacked.sign = data[31];
        unpacked.mag  = unpacked.sign ? {32'd0, (~data[31:0] + 32'd1)} :
                                         {32'd0, data[31:0]};
      end

      FPU_INT_WU: begin
        unpacked.mag = {32'd0, data[31:0]};
      end

      FPU_INT_L: begin
        unpacked.sign = data[63];
        unpacked.mag  = unpacked.sign ? (~data + 64'd1) : data;
      end

      FPU_INT_LU: begin
        unpacked.mag = data;
      end

      default: begin end
    endcase

    return unpacked;
  endfunction

  assign rm_is_valid = rm_is_supported(req_i.rm);
  assign int_src     = unpack_int(req_i.src_a, req_i.int_fmt);
  assign int_fmt_i32 = int_is_i32(req_i.int_fmt);

  fpu_lop #(
    .DATA_W(64)
  ) u_int_lop (
    .data_i(int_src.mag),
    .pos_o (i2f_lop_pos),
    .zero_o(i2f_is_zero)
  );

  assign i2f_shamt = i2f_is_zero ? 7'd0 : (7'd63 - {1'b0, i2f_lop_pos});

  fpu_barrel_shifter #(
    .WIDTH        (64),
    .SUPPORT_LEFT (1'b1),
    .SUPPORT_RIGHT(1'b0)
  ) u_i2f_align_shifter (
    .data_i      (int_src.mag),
    .shamt_i     (i2f_shamt),
    .left_data_o (i2f_sig),
    .right_data_o(),
    .right_lost_o()
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s1_valid       <= 1'b0;
      s1_req         <= '0;
      s1_rm_is_valid <= 1'b0;
      s1_int_fmt_i32 <= 1'b0;
      s1_sign        <= 1'b0;
      s1_lop_pos     <= 6'd0;
      s1_is_zero     <= 1'b0;
      s1_sig         <= '0;
      s2_valid       <= 1'b0;
      s2_resp        <= '0;
      s2_valid_op    <= 1'b0;
    end else begin
      s1_valid       <= valid_i;
      s1_req         <= req_i;
      s1_rm_is_valid <= rm_is_valid;
      s1_int_fmt_i32 <= int_fmt_i32;
      s1_sign        <= int_src.sign;
      s1_lop_pos     <= i2f_lop_pos;
      s1_is_zero     <= i2f_is_zero;
      s1_sig         <= i2f_sig;
      s2_valid       <= s1_valid;
      s2_resp        <= resp_d;
      s2_valid_op    <= s1_valid && valid_op_d;
    end
  end

  assign i2f_s_bits = s1_is_zero ? 32'd0 :
                                   {s1_sign,
                                    ({2'b00, s1_lop_pos} + 8'd127),
                                    s1_sig[62:40]};
  assign i2f_d_bits = s1_is_zero ? 64'd0 :
                                   {s1_sign,
                                    ({5'b00000, s1_lop_pos} + 11'd1023),
                                    s1_sig[62:11]};

  assign i2f_s_grs_bits = s1_int_fmt_i32 ? {s1_sig[39:32], 32'd0} :
                                            s1_sig[39:0];
  assign i2f_d_grs_bits = s1_int_fmt_i32 ? 11'd0 : s1_sig[10:0];

  fpu_grs #(
    .WIDTH(40)
  ) u_i2f_s_grs (
    .data_i(i2f_s_grs_bits),
    .grs_o (i2f_s_grs)
  );

  fpu_grs #(
    .WIDTH(11)
  ) u_i2f_d_grs (
    .data_i(i2f_d_grs_bits),
    .grs_o (i2f_d_grs)
  );

  fpu_round_inc u_i2f_s_round (
    .rm_i     (s1_req.rm),
    .sign_i   (s1_sign),
    .lsb_i    (i2f_s_bits[0]),
    .grs_i    (i2f_s_grs),
    .inexact_o(i2f_s_inexact),
    .inc_o    (i2f_s_round_inc)
  );

  fpu_round_inc u_i2f_d_round (
    .rm_i     (s1_req.rm),
    .sign_i   (s1_sign),
    .lsb_i    (i2f_d_bits[0]),
    .grs_i    (i2f_d_grs),
    .inexact_o(i2f_d_inexact),
    .inc_o    (i2f_d_round_inc)
  );

  always_comb begin
    logic [7:0]  exp_s;
    logic [10:0] exp_d;
    logic [23:0] mant_s_round;
    logic [52:0] mant_d_round;

    exp_s        = ({2'b00, s1_lop_pos} + 8'd127);
    exp_d        = ({5'b00000, s1_lop_pos} + 11'd1023);
    mant_s_round = {1'b0, s1_sig[62:40]} + {23'd0, i2f_s_round_inc};
    mant_d_round = {1'b0, s1_sig[62:11]} + {52'd0, i2f_d_round_inc};

    if (s1_is_zero) begin
      i2f_s_rounded_bits = 32'd0;
      i2f_d_rounded_bits = 64'd0;
    end else begin
      i2f_s_rounded_bits = {s1_sign,
                            exp_s + {7'd0, mant_s_round[23]},
                            mant_s_round[23] ? 23'd0 : mant_s_round[22:0]};
      i2f_d_rounded_bits = {s1_sign,
                            exp_d + {10'd0, mant_d_round[52]},
                            mant_d_round[52] ? 52'd0 : mant_d_round[51:0]};
    end
  end

  always_comb begin
    resp_d      = '0;
    resp_d.tag  = s1_req.tag;
    resp_d.rd   = s1_req.rd;
    valid_op_d  = (s1_req.op == FPU_OP_CVT_I2F);

    unique case ({s1_req.int_fmt, s1_req.dst_fmt})
      {FPU_INT_W,  FPU_FMT_S},
      {FPU_INT_WU, FPU_FMT_S},
      {FPU_INT_L,  FPU_FMT_S},
      {FPU_INT_LU, FPU_FMT_S}: begin
        if (valid_op_d && s1_rm_is_valid) begin
          resp_d.result = nanbox_s(i2f_s_rounded_bits);
          resp_d.fflags[FPU_FFLAG_NX] = i2f_s_inexact;
        end else begin
          valid_op_d = 1'b0;
        end
      end

      {FPU_INT_W,  FPU_FMT_D},
      {FPU_INT_WU, FPU_FMT_D},
      {FPU_INT_L,  FPU_FMT_D},
      {FPU_INT_LU, FPU_FMT_D}: begin
        if (valid_op_d && s1_rm_is_valid) begin
          resp_d.result = i2f_d_rounded_bits;
          resp_d.fflags[FPU_FFLAG_NX] = i2f_d_inexact;
        end else begin
          valid_op_d = 1'b0;
        end
      end

      default: begin
        valid_op_d = 1'b0;
      end
    endcase
  end

  assign valid_o    = s2_valid;
  assign resp_o     = s2_resp;
  assign valid_op_o = s2_valid_op;

endmodule : fpu_convert_i2f_unit_pipe

//----------------------------------------------------------------------------
// Floating-point to floating-point conversion, two-cycle pipe.
//----------------------------------------------------------------------------

module fpu_convert_f2f_unit_pipe
  import fpu_pkg::*;
(
  input  logic     clk_i,
  input  logic     rst_ni,
  input  logic     valid_i,
  input  fpu_req_t req_i,
  output logic     valid_o,
  output fpu_resp_t resp_o,
  output logic     valid_op_o
);

  float64_t fp64_src;

  logic       rm_is_valid;
  logic [63:0] f2f_s2d_bits;
  logic [52:0] f2f_d2s_sig53;
  logic [77:0] f2f_d2s_sub_ext;
  logic [77:0] f2f_d2s_sub_shifted;
  logic [77:0] f2f_d2s_sub_lost;
  logic [9:0]  f2f_d2s_sub_shamt;
  logic [6:0]  f2f_d2s_sub_shamt_limited;
  logic        f2f_d2s_sub_far;
  logic [22:0] f2f_d2s_sub_mant;
  fpu_grs_t    f2f_d2s_norm_grs;
  fpu_grs_t    f2f_d2s_sub_raw_grs;
  fpu_grs_t    f2f_d2s_sub_grs;
  fpu_grs_t    f2f_d2s_grs;
  logic        f2f_d2s_lsb;

  logic       s1_valid;
  fpu_req_t   s1_req;
  logic       s1_rm_is_valid;
  float64_t   s1_fp64_src;
  logic [63:0] s1_s2d_bits;
  logic [22:0] s1_d2s_sub_mant;
  fpu_grs_t    s1_d2s_grs;
  logic        s1_d2s_lsb;

  logic [31:0] f2f_d2s_bits;
  fpu_fflags_t f2f_d2s_fflags;
  logic        f2f_d2s_inexact;
  logic        f2f_d2s_round_inc;
  fpu_resp_t   resp_d;
  logic        valid_op_d;

  logic      s2_valid;
  fpu_resp_t s2_resp;
  logic      s2_valid_op;

  function automatic logic [63:0] nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
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

  function automatic logic [63:0] f2f_s_to_d(input logic [31:0] data_s);
    logic        sign;
    logic [7:0]  exp_s;
    logic [22:0] frac_s;
    logic [10:0] exp_d;
    logic [51:0] frac_d;
    logic [63:0] rem_ext;
    int          msb_pos;

    sign    = data_s[31];
    exp_s   = data_s[30:23];
    frac_s  = data_s[22:0];
    exp_d   = 11'd0;
    frac_d  = 52'd0;
    rem_ext = 64'd0;
    msb_pos = 0;

    if (exp_s == 8'hff) begin
      exp_d  = 11'h7ff;
      frac_d = {frac_s, 29'd0};
      if (frac_s != 23'd0 && frac_d == 52'd0) begin
        frac_d[51] = 1'b1;
      end
    end else if (exp_s == 8'd0) begin
      if (frac_s != 23'd0) begin
        for (int bit_idx = 0; bit_idx < 23; bit_idx++) begin
          if (frac_s[bit_idx]) begin
            msb_pos = bit_idx;
          end
        end

        exp_d   = msb_pos + 11'd874;
        rem_ext = {41'd0, frac_s & ((23'd1 << msb_pos) - 23'd1)};
        frac_d  = rem_ext[51:0] << (52 - msb_pos);
      end
    end else begin
      exp_d  = {3'd0, exp_s} + 11'd896;
      frac_d = {frac_s, 29'd0};
    end

    return {sign, exp_d, frac_d};
  endfunction

  function automatic logic [31:0] f2f_d2s_overflow_result(
    input logic    sign,
    input fpu_rm_e rm
  );
    fpu_rm_e rm_eff;
    logic    to_inf;

    rm_eff = (rm == FPU_RM_DYN) ? FPU_RM_RNE : rm;
    to_inf = (rm_eff == FPU_RM_RNE) ||
             (rm_eff == FPU_RM_RMM) ||
             ((rm_eff == FPU_RM_RUP) && !sign) ||
             ((rm_eff == FPU_RM_RDN) && sign);

    return to_inf ? {sign, 8'hff, 23'd0} : {sign, 8'hfe, 23'h7f_ffff};
  endfunction

  assign rm_is_valid      = rm_is_supported(req_i.rm);
  assign fp64_src.bits    = req_i.src_a;
  assign f2f_s2d_bits     = f2f_s_to_d(req_i.src_a[31:0]);
  assign f2f_d2s_sig53    = (fp64_src.fields.exponent == 11'd0) ?
                            {1'b0, fp64_src.fields.mantissa} :
                            {1'b1, fp64_src.fields.mantissa};
  assign f2f_d2s_sub_ext  = {24'd0, 1'b0, f2f_d2s_sig53};
  assign f2f_d2s_sub_shamt = (fp64_src.fields.exponent < 11'd897) ?
                             (10'd926 - {1'b0, fp64_src.fields.exponent}) :
                             10'd0;
  assign f2f_d2s_sub_far = (f2f_d2s_sub_shamt > 10'd54);
  assign f2f_d2s_sub_shamt_limited = f2f_d2s_sub_far ? 7'd0 :
                                                          f2f_d2s_sub_shamt[6:0];

  fpu_grs #(
    .WIDTH(29)
  ) u_f2f_d2s_norm_grs (
    .data_i(fp64_src.fields.mantissa[28:0]),
    .grs_o (f2f_d2s_norm_grs)
  );

  fpu_barrel_shifter #(
    .WIDTH        (78),
    .SUPPORT_LEFT (1'b0),
    .SUPPORT_RIGHT(1'b1)
  ) u_f2f_d2s_sub_shifter (
    .data_i      (f2f_d2s_sub_ext),
    .shamt_i     (f2f_d2s_sub_shamt_limited),
    .left_data_o (),
    .right_data_o(f2f_d2s_sub_shifted),
    .right_lost_o(f2f_d2s_sub_lost)
  );

  fpu_grs #(
    .WIDTH(78)
  ) u_f2f_d2s_sub_grs (
    .data_i(f2f_d2s_sub_lost),
    .grs_o (f2f_d2s_sub_raw_grs)
  );

  always_comb begin
    f2f_d2s_sub_mant  = 23'd0;
    f2f_d2s_sub_grs   = '0;
    f2f_d2s_grs       = f2f_d2s_norm_grs;
    f2f_d2s_lsb       = fp64_src.fields.mantissa[29];

    if (fp64_src.fields.exponent == 11'd0) begin
      f2f_d2s_grs        = '0;
      f2f_d2s_grs.sticky = |fp64_src.fields.mantissa;
      f2f_d2s_lsb        = 1'b0;
    end else if (fp64_src.fields.exponent < 11'd897) begin
      if (!f2f_d2s_sub_far) begin
        f2f_d2s_sub_mant = f2f_d2s_sub_shifted[22:0];
        f2f_d2s_sub_grs  = f2f_d2s_sub_raw_grs;
      end else begin
        f2f_d2s_sub_grs.sticky = |f2f_d2s_sig53;
      end

      f2f_d2s_grs = f2f_d2s_sub_grs;
      f2f_d2s_lsb = f2f_d2s_sub_mant[0];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s1_valid          <= 1'b0;
      s1_req            <= '0;
      s1_rm_is_valid    <= 1'b0;
      s1_fp64_src       <= '0;
      s1_s2d_bits       <= 64'd0;
      s1_d2s_sub_mant   <= 23'd0;
      s1_d2s_grs        <= '0;
      s1_d2s_lsb        <= 1'b0;
      s2_valid          <= 1'b0;
      s2_resp           <= '0;
      s2_valid_op       <= 1'b0;
    end else begin
      s1_valid          <= valid_i;
      s1_req            <= req_i;
      s1_rm_is_valid    <= rm_is_valid;
      s1_fp64_src       <= fp64_src;
      s1_s2d_bits       <= f2f_s2d_bits;
      s1_d2s_sub_mant   <= f2f_d2s_sub_mant;
      s1_d2s_grs        <= f2f_d2s_grs;
      s1_d2s_lsb        <= f2f_d2s_lsb;
      s2_valid          <= s1_valid;
      s2_resp           <= resp_d;
      s2_valid_op       <= s1_valid && valid_op_d;
    end
  end

  fpu_round_inc u_f2f_d2s_round (
    .rm_i     (s1_req.rm),
    .sign_i   (s1_fp64_src.fields.sign),
    .lsb_i    (s1_d2s_lsb),
    .grs_i    (s1_d2s_grs),
    .inexact_o(f2f_d2s_inexact),
    .inc_o    (f2f_d2s_round_inc)
  );

  always_comb begin
    logic [7:0]  exp_s;
    logic [22:0] mant_s;
    logic [23:0] mant_round;
    logic        overflow;

    f2f_d2s_bits   = 32'd0;
    f2f_d2s_fflags = '0;
    exp_s          = 8'd0;
    mant_s         = 23'd0;
    mant_round     = 24'd0;
    overflow       = 1'b0;

    if (s1_fp64_src.fields.exponent == 11'h7ff) begin
      f2f_d2s_bits = {s1_fp64_src.fields.sign,
                      8'hff,
                      s1_fp64_src.fields.mantissa[51:29]};
      if (s1_fp64_src.fields.mantissa != 52'd0 &&
          s1_fp64_src.fields.mantissa[51:29] == 23'd0) begin
        f2f_d2s_bits[22] = 1'b1;
      end
    end else if (s1_fp64_src.fields.exponent == 11'd0) begin
      if (s1_fp64_src.fields.mantissa != 52'd0) begin
        mant_round = {1'b0, 23'd0} + {23'd0, f2f_d2s_round_inc};
        f2f_d2s_bits = {s1_fp64_src.fields.sign, 8'd0, mant_round[22:0]};
        f2f_d2s_fflags[FPU_FFLAG_NX] = f2f_d2s_inexact;
        f2f_d2s_fflags[FPU_FFLAG_UF] = f2f_d2s_inexact;
      end
    end else if (s1_fp64_src.fields.exponent < 11'd897) begin
      mant_round = {1'b0, s1_d2s_sub_mant} + {23'd0, f2f_d2s_round_inc};
      if (mant_round[23]) begin
        f2f_d2s_bits = {s1_fp64_src.fields.sign, 8'd1, 23'd0};
      end else begin
        f2f_d2s_bits = {s1_fp64_src.fields.sign, 8'd0, mant_round[22:0]};
        f2f_d2s_fflags[FPU_FFLAG_UF] = f2f_d2s_inexact;
      end
      f2f_d2s_fflags[FPU_FFLAG_NX] = f2f_d2s_inexact;
    end else begin
      exp_s = s1_fp64_src.fields.exponent - 11'd896;
      mant_round = {1'b0, s1_fp64_src.fields.mantissa[51:29]} +
                   {23'd0, f2f_d2s_round_inc};

      if (mant_round[23]) begin
        exp_s  = exp_s + 8'd1;
        mant_s = 23'd0;
      end else begin
        mant_s = mant_round[22:0];
      end

      overflow = (s1_fp64_src.fields.exponent > 11'd1150) ||
                 (exp_s == 8'hff);

      if (overflow) begin
        f2f_d2s_bits = f2f_d2s_overflow_result(s1_fp64_src.fields.sign,
                                               s1_req.rm);
        f2f_d2s_fflags[FPU_FFLAG_OF] = 1'b1;
        f2f_d2s_fflags[FPU_FFLAG_NX] = 1'b1;
      end else begin
        f2f_d2s_bits = {s1_fp64_src.fields.sign, exp_s, mant_s};
        f2f_d2s_fflags[FPU_FFLAG_NX] = f2f_d2s_inexact;
      end
    end
  end

  always_comb begin
    resp_d      = '0;
    resp_d.tag  = s1_req.tag;
    resp_d.rd   = s1_req.rd;
    valid_op_d  = (s1_req.op == FPU_OP_CVT_FP);

    unique case ({s1_req.rs_fmt, s1_req.dst_fmt})
      {FPU_FMT_S, FPU_FMT_S}: begin
        if (valid_op_d) begin
          resp_d.result = nanbox_s(s1_req.src_a[31:0]);
        end
      end

      {FPU_FMT_D, FPU_FMT_D}: begin
        if (valid_op_d) begin
          resp_d.result = s1_req.src_a;
        end
      end

      {FPU_FMT_S, FPU_FMT_D}: begin
        if (valid_op_d) begin
          resp_d.result = s1_s2d_bits;
        end
      end

      {FPU_FMT_D, FPU_FMT_S}: begin
        if (valid_op_d && s1_rm_is_valid) begin
          resp_d.result = nanbox_s(f2f_d2s_bits);
          resp_d.fflags = f2f_d2s_fflags;
        end else begin
          valid_op_d = 1'b0;
        end
      end

      default: begin
        valid_op_d = 1'b0;
      end
    endcase
  end

  assign valid_o    = s2_valid;
  assign resp_o     = s2_resp;
  assign valid_op_o = s2_valid_op;

endmodule : fpu_convert_f2f_unit_pipe

//----------------------------------------------------------------------------
// Floating-point to integer conversion, two-cycle pipe.
//----------------------------------------------------------------------------

module fpu_convert_f2i_unit_pipe
  import fpu_pkg::*;
(
  input  logic     clk_i,
  input  logic     rst_ni,
  input  logic     valid_i,
  input  fpu_req_t req_i,
  output logic     valid_o,
  output fpu_resp_t resp_o,
  output logic     valid_op_o
);

  float32_t fp32_src;
  float64_t fp64_src;

  logic        rm_is_valid;
  logic        f2i_sign;
  logic [10:0] f2i_exp;
  logic        f2i_frac_nz;
  fpu_data_t   f2i_sig;
  logic [10:0] f2i_bias_m1;
  logic [10:0] f2i_bias_p63;
  logic [10:0] f2i_boundary_exp;
  logic        f2i_dst_i32;
  logic        f2i_dst_signed;
  logic [11:0] f2i_full_shamt;
  logic [6:0]  f2i_shamt;
  logic        f2i_shift_far;
  fpu_data_t   f2i_mag;
  fpu_data_t   f2i_lost;
  fpu_grs_t    f2i_grs;
  fpu_grs_t    f2i_eff_grs;
  logic        f2i_src_is_nonzero;

  logic        s1_valid;
  fpu_req_t    s1_req;
  logic        s1_rm_is_valid;
  logic        s1_sign;
  logic [10:0] s1_exp;
  logic        s1_frac_nz;
  logic [10:0] s1_bias_m1;
  logic [10:0] s1_boundary_exp;
  logic        s1_dst_i32;
  logic        s1_dst_signed;
  fpu_data_t   s1_mag;
  fpu_grs_t    s1_eff_grs;

  logic        f2i_inexact;
  logic        f2i_round_inc;
  fpu_data_t   f2i_rounded_mag;
  logic        f2i_rounded_invalid;
  logic        f2i_invalid_negative;
  fpu_data_t   f2i_result;
  fpu_fflags_t f2i_fflags;
  fpu_resp_t   resp_d;
  logic        valid_op_d;

  logic      s2_valid;
  fpu_resp_t s2_resp;
  logic      s2_valid_op;

  function automatic logic int_is_i32(input fpu_int_fmt_e int_fmt);
    return (int_fmt == FPU_INT_W) || (int_fmt == FPU_INT_WU);
  endfunction

  function automatic logic int_is_signed(input fpu_int_fmt_e int_fmt);
    return (int_fmt == FPU_INT_W) || (int_fmt == FPU_INT_L);
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

  function automatic logic [10:0] fp_max_exp(input fpu_fmt_e fmt);
    return (fmt == FPU_FMT_D) ? 11'h7ff : 11'h0ff;
  endfunction

  function automatic logic [63:0] apply_int_sign(
    input logic [63:0] mag,
    input logic        sign,
    input logic        dst_i32,
    input logic        dst_signed
  );
    logic [31:0] value32;
    logic [63:0] value64;

    if (dst_i32) begin
      value32 = sign ? (~mag[31:0] + 32'd1) : mag[31:0];
      return dst_signed ? {{32{value32[31]}}, value32} :
                          {32'd0, value32};
    end

    value64 = sign ? (~mag + 64'd1) : mag;
    return value64;
  endfunction

  function automatic logic [63:0] f2i_invalid_result(
    input logic dst_i32,
    input logic dst_signed,
    input logic invalid_negative
  );
    if (!dst_signed) begin
      if (dst_i32) begin
        return invalid_negative ? 64'd0 : 64'h0000_0000_ffff_ffff;
      end

      return invalid_negative ? 64'd0 : 64'hffff_ffff_ffff_ffff;
    end

    if (dst_i32) begin
      return invalid_negative ? 64'hffff_ffff_8000_0000 :
                                64'h0000_0000_7fff_ffff;
    end

    return invalid_negative ? 64'h8000_0000_0000_0000 :
                              64'h7fff_ffff_ffff_ffff;
  endfunction

  function automatic logic [63:0] f2i_signed_min(input logic dst_i32);
    return dst_i32 ? 64'hffff_ffff_8000_0000 : 64'h8000_0000_0000_0000;
  endfunction

  function automatic logic f2i_mag_overflows(
    input logic [63:0] mag,
    input logic        sign,
    input logic        dst_i32,
    input logic        dst_signed
  );
    if (dst_i32) begin
      if (dst_signed) begin
        return sign ? (mag > 64'h0000_0000_8000_0000) :
                      (mag > 64'h0000_0000_7fff_ffff);
      end
      return sign ? (mag != 64'd0) : (mag > 64'h0000_0000_ffff_ffff);
    end

    if (dst_signed) begin
      return sign ? (mag > 64'h8000_0000_0000_0000) :
                    (mag > 64'h7fff_ffff_ffff_ffff);
    end

    return sign && (mag != 64'd0);
  endfunction

  assign rm_is_valid    = rm_is_supported(req_i.rm);
  assign fp32_src.bits  = req_i.src_a[31:0];
  assign fp64_src.bits  = req_i.src_a;
  assign f2i_dst_i32    = int_is_i32(req_i.int_fmt);
  assign f2i_dst_signed = int_is_signed(req_i.int_fmt);

  always_comb begin
    f2i_sign     = 1'b0;
    f2i_exp      = 11'd0;
    f2i_frac_nz  = 1'b0;
    f2i_sig      = 64'd0;
    f2i_bias_m1  = 11'd126;
    f2i_bias_p63 = 11'd190;

    unique case (req_i.rs_fmt)
      FPU_FMT_S: begin
        f2i_sign     = fp32_src.fields.sign;
        f2i_exp      = {3'd0, fp32_src.fields.exponent};
        f2i_frac_nz  = |fp32_src.fields.mantissa;
        f2i_sig      = (fp32_src.fields.exponent == 8'd0) ?
                       {1'b0, fp32_src.fields.mantissa, 40'd0} :
                       {1'b1, fp32_src.fields.mantissa, 40'd0};
        f2i_bias_m1  = 11'd126;
        f2i_bias_p63 = 11'd190;
      end

      FPU_FMT_D: begin
        f2i_sign     = fp64_src.fields.sign;
        f2i_exp      = fp64_src.fields.exponent;
        f2i_frac_nz  = |fp64_src.fields.mantissa;
        f2i_sig      = (fp64_src.fields.exponent == 11'd0) ?
                       {1'b0, fp64_src.fields.mantissa, 11'd0} :
                       {1'b1, fp64_src.fields.mantissa, 11'd0};
        f2i_bias_m1  = 11'd1022;
        f2i_bias_p63 = 11'd1086;
      end

      default: begin end
    endcase
  end

  always_comb begin
    if (f2i_dst_i32) begin
      if (f2i_dst_signed) begin
        f2i_boundary_exp = (req_i.rs_fmt == FPU_FMT_D) ? 11'd1054 : 11'd158;
      end else begin
        f2i_boundary_exp = (req_i.rs_fmt == FPU_FMT_D) ? 11'd1055 : 11'd159;
      end
    end else begin
      f2i_boundary_exp = f2i_dst_signed ? f2i_bias_p63 :
                                           (f2i_bias_p63 + 11'd1);
    end
  end

  always_comb begin
    f2i_full_shamt = 12'd0;

    if (f2i_exp > f2i_bias_p63) begin
      f2i_full_shamt = 12'd0;
    end else begin
      f2i_full_shamt = {1'b0, f2i_bias_p63} - {1'b0, f2i_exp};
    end

    f2i_shift_far = (f2i_full_shamt > 12'd64);
    f2i_shamt     = f2i_shift_far ? 7'd64 : f2i_full_shamt[6:0];
  end

  fpu_barrel_shifter #(
    .WIDTH        (64),
    .SUPPORT_LEFT (1'b0),
    .SUPPORT_RIGHT(1'b1)
  ) u_f2i_shifter (
    .data_i      (f2i_sig),
    .shamt_i     (f2i_shamt),
    .left_data_o (),
    .right_data_o(f2i_mag),
    .right_lost_o(f2i_lost)
  );

  fpu_grs #(
    .WIDTH(64)
  ) u_f2i_grs (
    .data_i(f2i_lost),
    .grs_o (f2i_grs)
  );

  assign f2i_src_is_nonzero = (f2i_exp != 11'd0) || f2i_frac_nz;

  always_comb begin
    f2i_eff_grs = f2i_grs;

    if (f2i_shift_far) begin
      f2i_eff_grs.guard  = 1'b0;
      f2i_eff_grs.round  = 1'b0;
      f2i_eff_grs.sticky = f2i_src_is_nonzero;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s1_valid        <= 1'b0;
      s1_req          <= '0;
      s1_rm_is_valid  <= 1'b0;
      s1_sign         <= 1'b0;
      s1_exp          <= 11'd0;
      s1_frac_nz      <= 1'b0;
      s1_bias_m1      <= 11'd0;
      s1_boundary_exp <= 11'd0;
      s1_dst_i32      <= 1'b0;
      s1_dst_signed   <= 1'b0;
      s1_mag          <= 64'd0;
      s1_eff_grs      <= '0;
      s2_valid        <= 1'b0;
      s2_resp         <= '0;
      s2_valid_op     <= 1'b0;
    end else begin
      s1_valid        <= valid_i;
      s1_req          <= req_i;
      s1_rm_is_valid  <= rm_is_valid;
      s1_sign         <= f2i_sign;
      s1_exp          <= f2i_exp;
      s1_frac_nz      <= f2i_frac_nz;
      s1_bias_m1      <= f2i_bias_m1;
      s1_boundary_exp <= f2i_boundary_exp;
      s1_dst_i32      <= f2i_dst_i32;
      s1_dst_signed   <= f2i_dst_signed;
      s1_mag          <= f2i_mag;
      s1_eff_grs      <= f2i_eff_grs;
      s2_valid        <= s1_valid;
      s2_resp         <= resp_d;
      s2_valid_op     <= s1_valid && valid_op_d;
    end
  end

  fpu_round_inc u_f2i_round (
    .rm_i     (s1_req.rm),
    .sign_i   (s1_sign),
    .lsb_i    (s1_mag[0]),
    .grs_i    (s1_eff_grs),
    .inexact_o(f2i_inexact),
    .inc_o    (f2i_round_inc)
  );

  always_comb begin
    f2i_result = 64'd0;
    f2i_fflags = '0;
    f2i_rounded_mag = s1_mag + {63'd0, f2i_round_inc};
    f2i_invalid_negative = s1_sign &&
                           !((s1_exp == fp_max_exp(s1_req.rs_fmt)) &&
                             s1_frac_nz);
    f2i_rounded_invalid = f2i_mag_overflows(
      f2i_rounded_mag,
      s1_sign,
      s1_dst_i32,
      s1_dst_signed
    );

    if ((s1_exp == fp_max_exp(s1_req.rs_fmt)) ||
        (s1_exp > s1_boundary_exp)) begin
      f2i_fflags[FPU_FFLAG_NV] = 1'b1;
      f2i_result = f2i_invalid_result(
        s1_dst_i32,
        s1_dst_signed,
        f2i_invalid_negative
      );
    end else if (s1_exp < (s1_bias_m1 + 11'd1)) begin
      f2i_fflags[FPU_FFLAG_NX] = f2i_inexact;
      f2i_result = apply_int_sign(
        f2i_rounded_mag,
        s1_sign,
        s1_dst_i32,
        s1_dst_signed
      );
    end else if (s1_exp == s1_boundary_exp) begin
      if (s1_dst_signed && s1_sign && !s1_frac_nz) begin
        f2i_result = f2i_signed_min(s1_dst_i32);
      end else begin
        f2i_fflags[FPU_FFLAG_NV] = 1'b1;
        f2i_result = f2i_invalid_result(
          s1_dst_i32,
          s1_dst_signed,
          f2i_invalid_negative
        );
      end
    end else begin
      f2i_fflags[FPU_FFLAG_NX] = f2i_inexact;
      if (f2i_rounded_invalid) begin
        f2i_fflags = '0;
        f2i_fflags[FPU_FFLAG_NV] = 1'b1;
        f2i_result = f2i_invalid_result(
          s1_dst_i32,
          s1_dst_signed,
          f2i_invalid_negative
        );
      end else begin
        f2i_result = apply_int_sign(
          f2i_rounded_mag,
          s1_sign,
          s1_dst_i32,
          s1_dst_signed
        );
      end
    end
  end

  always_comb begin
    resp_d      = '0;
    resp_d.tag  = s1_req.tag;
    resp_d.rd   = s1_req.rd;
    valid_op_d  = (s1_req.op == FPU_OP_CVT_F2I);

    unique case ({s1_req.rs_fmt, s1_req.int_fmt})
      {FPU_FMT_S, FPU_INT_W},
      {FPU_FMT_S, FPU_INT_WU},
      {FPU_FMT_D, FPU_INT_W},
      {FPU_FMT_D, FPU_INT_WU},
      {FPU_FMT_S, FPU_INT_L},
      {FPU_FMT_S, FPU_INT_LU},
      {FPU_FMT_D, FPU_INT_L},
      {FPU_FMT_D, FPU_INT_LU}: begin
        if (valid_op_d && s1_rm_is_valid) begin
          resp_d.result = f2i_result;
          resp_d.fflags = f2i_fflags;
        end else begin
          valid_op_d = 1'b0;
        end
      end

      default: begin
        valid_op_d = 1'b0;
      end
    endcase
  end

  assign valid_o    = s2_valid;
  assign resp_o     = s2_resp;
  assign valid_op_o = s2_valid_op;

endmodule : fpu_convert_f2i_unit_pipe

//----------------------------------------------------------------------------
// Conversion wrapper.
//----------------------------------------------------------------------------

module fpu_convert_unit_pipe
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

  logic      s1_valid;
  fpu_req_t  s1_req;
  logic      s2_valid;
  fpu_req_t  s2_req;

  fpu_resp_t i2f_resp;
  fpu_resp_t f2f_resp;
  fpu_resp_t f2i_resp;
  logic      i2f_valid_op;
  logic      f2f_valid_op;
  logic      f2i_valid_op;
  fpu_resp_t resp_d;
  logic      valid_op_d;

  fpu_convert_i2f_unit_pipe u_i2f (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (valid_i),
    .req_i     (req_i),
    .valid_o   (),
    .resp_o    (i2f_resp),
    .valid_op_o(i2f_valid_op)
  );

  fpu_convert_f2f_unit_pipe u_f2f (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (valid_i),
    .req_i     (req_i),
    .valid_o   (),
    .resp_o    (f2f_resp),
    .valid_op_o(f2f_valid_op)
  );

  fpu_convert_f2i_unit_pipe u_f2i (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (valid_i),
    .req_i     (req_i),
    .valid_o   (),
    .resp_o    (f2i_resp),
    .valid_op_o(f2i_valid_op)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s1_valid <= 1'b0;
      s1_req   <= '0;
      s2_valid <= 1'b0;
      s2_req   <= '0;
    end else begin
      s1_valid <= valid_i;
      s1_req   <= req_i;
      s2_valid <= s1_valid;
      s2_req   <= s1_req;
    end
  end

  always_comb begin
    resp_d      = '0;
    resp_d.tag  = s2_req.tag;
    resp_d.rd   = s2_req.rd;
    valid_op_d  = 1'b0;

    unique case (s2_req.op)
      FPU_OP_CVT_I2F: begin
        resp_d     = i2f_resp;
        valid_op_d = i2f_valid_op;
      end

      FPU_OP_CVT_FP: begin
        resp_d     = f2f_resp;
        valid_op_d = f2f_valid_op;
      end

      FPU_OP_CVT_F2I: begin
        resp_d     = f2i_resp;
        valid_op_d = f2i_valid_op;
      end

      default: begin end
    endcase
  end

  assign valid_o    = s2_valid;
  assign resp_o     = resp_d;
  assign valid_op_o = valid_op_d;

endmodule : fpu_convert_unit_pipe
