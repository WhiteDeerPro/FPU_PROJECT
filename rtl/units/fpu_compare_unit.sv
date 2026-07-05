//============================================================================
// Floating-point compare, min/max, and classify unit.
//
// Flow:
//   req_i
//     -> unpack/classify lhs and rhs
//     -> decode compare/minmax/class operation
//     -> compute NaN/sNaN controls
//     -> compute compare, min/max, or class result
//     -> pack integer result and flags
//============================================================================

module fpu_compare_unit
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
    logic [51:0] frac;
    logic [62:0] mag;
    logic        is_zero;
    logic        is_subnormal;
    logic        is_normal;
    logic        is_inf;
    logic        is_nan;
    logic        is_snan;
    fpu_data_t   boxed_data;
  } fp_cmp_operand_t;

  // --------------------------------------------------------------------------
  // Global datapath and control signals
  // --------------------------------------------------------------------------

  fpu_resp_t       resp_d;
  fp_cmp_operand_t lhs;
  fp_cmp_operand_t rhs;

  logic fmt_is_valid;
  logic op_is_compare;
  logic op_is_minmax;
  logic op_is_class;
  logic cmp_eq;
  logic cmp_lt;
  logic cmp_le;
  logic any_nan;
  logic any_snan;

  // --------------------------------------------------------------------------
  // Shared helper functions
  // --------------------------------------------------------------------------

  function automatic logic [63:0] nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
  endfunction

  function automatic fpu_data_t canonical_nan(input fpu_fmt_e fmt);
    if (fmt == FPU_FMT_S) begin
      return nanbox_s(32'h7fc0_0000);
    end

    return 64'h7ff8_0000_0000_0000;
  endfunction

  function automatic fp_cmp_operand_t unpack_operand(
    input fpu_data_t data,
    input fpu_fmt_e  fmt
  );
    fp_cmp_operand_t op;
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

        op.sign         = bits_s[31];
        op.exp          = {3'd0, bits_s[30:23]};
        op.frac         = {bits_s[22:0], 29'd0};
        op.boxed_data   = nanbox_s(bits_s);
        op.is_zero      = (bits_s[30:0] == 31'd0);
        op.is_subnormal = (bits_s[30:23] == 8'd0) &&
                          (bits_s[22:0] != 23'd0);
        op.is_normal    = (bits_s[30:23] != 8'd0) &&
                          (bits_s[30:23] != 8'hff);
        op.is_inf       = (bits_s[30:23] == 8'hff) &&
                          (bits_s[22:0] == 23'd0);
        op.is_nan       = (bits_s[30:23] == 8'hff) &&
                          (bits_s[22:0] != 23'd0);
        op.is_snan      = op.is_nan && !bits_s[22];
      end

      FPU_FMT_D: begin
        bits_d = data;

        op.sign         = bits_d[63];
        op.exp          = bits_d[62:52];
        op.frac         = bits_d[51:0];
        op.boxed_data   = bits_d;
        op.is_zero      = (bits_d[62:0] == 63'd0);
        op.is_subnormal = (bits_d[62:52] == 11'd0) &&
                          (bits_d[51:0] != 52'd0);
        op.is_normal    = (bits_d[62:52] != 11'd0) &&
                          (bits_d[62:52] != 11'h7ff);
        op.is_inf       = (bits_d[62:52] == 11'h7ff) &&
                          (bits_d[51:0] == 52'd0);
        op.is_nan       = (bits_d[62:52] == 11'h7ff) &&
                          (bits_d[51:0] != 52'd0);
        op.is_snan      = op.is_nan && !bits_d[51];
      end

      default: begin end
    endcase

    op.mag = {op.exp, op.frac};
    return op;
  endfunction

  function automatic logic fp_equal(
    input fp_cmp_operand_t a,
    input fp_cmp_operand_t b
  );
    if (a.is_zero && b.is_zero) begin
      return 1'b1;
    end

    return (a.sign == b.sign) && (a.mag == b.mag);
  endfunction

  function automatic logic fp_less_than(
    input fp_cmp_operand_t a,
    input fp_cmp_operand_t b
  );
    if (a.is_zero && b.is_zero) begin
      return 1'b0;
    end

    if (a.sign != b.sign) begin
      return a.sign;
    end

    if (!a.sign) begin
      return a.mag < b.mag;
    end

    return a.mag > b.mag;
  endfunction

  function automatic fpu_data_t minmax_result(
    input fp_cmp_operand_t a,
    input fp_cmp_operand_t b,
    input fpu_fmt_e        fmt,
    input logic            is_max
  );
    logic a_lt_b;

    if (a.is_nan && b.is_nan) begin
      return canonical_nan(fmt);
    end

    if (a.is_nan) begin
      return b.boxed_data;
    end

    if (b.is_nan) begin
      return a.boxed_data;
    end

    if (a.is_zero && b.is_zero && (a.sign != b.sign)) begin
      if (is_max) begin
        return a.sign ? b.boxed_data : a.boxed_data;
      end

      return a.sign ? a.boxed_data : b.boxed_data;
    end

    a_lt_b = fp_less_than(a, b);

    if (is_max) begin
      return a_lt_b ? b.boxed_data : a.boxed_data;
    end

    return a_lt_b ? a.boxed_data : b.boxed_data;
  endfunction

  function automatic logic [9:0] class_bits(input fp_cmp_operand_t op);
    logic [9:0] bits;

    bits = 10'd0;

    if (op.is_nan) begin
      bits[8] = op.is_snan;
      bits[9] = !op.is_snan;
    end else if (op.is_inf) begin
      if (op.sign) begin
        bits[0] = 1'b1;
      end else begin
        bits[7] = 1'b1;
      end
    end else if (op.is_zero) begin
      if (op.sign) begin
        bits[3] = 1'b1;
      end else begin
        bits[4] = 1'b1;
      end
    end else if (op.is_subnormal) begin
      if (op.sign) begin
        bits[2] = 1'b1;
      end else begin
        bits[5] = 1'b1;
      end
    end else if (op.is_normal) begin
      if (op.sign) begin
        bits[1] = 1'b1;
      end else begin
        bits[6] = 1'b1;
      end
    end

    return bits;
  endfunction

  // --------------------------------------------------------------------------
  // Unpack, decode, and compare/control calculation
  // --------------------------------------------------------------------------

  assign lhs = unpack_operand(req_i.src_a, req_i.rs_fmt);
  assign rhs = unpack_operand(req_i.src_b, req_i.rs_fmt);

  assign fmt_is_valid  = (req_i.rs_fmt == FPU_FMT_S) ||
                         (req_i.rs_fmt == FPU_FMT_D);
  assign op_is_compare = (req_i.op == FPU_OP_EQ) ||
                         (req_i.op == FPU_OP_LT) ||
                         (req_i.op == FPU_OP_LE);
  assign op_is_minmax  = (req_i.op == FPU_OP_MIN) ||
                         (req_i.op == FPU_OP_MAX);
  assign op_is_class   = (req_i.op == FPU_OP_CLASS);
  assign any_nan       = lhs.is_nan || rhs.is_nan;
  assign any_snan      = lhs.is_snan || rhs.is_snan;
  assign cmp_eq        = !any_nan && fp_equal(lhs, rhs);
  assign cmp_lt        = !any_nan && fp_less_than(lhs, rhs);
  assign cmp_le        = cmp_lt || cmp_eq;

  // --------------------------------------------------------------------------
  // Final operation result mux
  // --------------------------------------------------------------------------

  always_comb begin
    resp_d      = '0;
    resp_d.tag  = req_i.tag;
    resp_d.rd   = req_i.rd;
    valid_op_o  = fmt_is_valid && (op_is_compare || op_is_minmax || op_is_class);

    if (valid_op_o) begin
      unique case (req_i.op)
        FPU_OP_EQ: begin
          resp_d.result = {63'd0, cmp_eq};
          resp_d.fflags[FPU_FFLAG_NV] = any_snan;
        end

        FPU_OP_LT: begin
          resp_d.result = {63'd0, cmp_lt};
          resp_d.fflags[FPU_FFLAG_NV] = any_nan;
        end

        FPU_OP_LE: begin
          resp_d.result = {63'd0, cmp_le};
          resp_d.fflags[FPU_FFLAG_NV] = any_nan;
        end

        FPU_OP_MIN: begin
          resp_d.result = minmax_result(lhs, rhs, req_i.rs_fmt, 1'b0);
          resp_d.fflags[FPU_FFLAG_NV] = any_snan;
        end

        FPU_OP_MAX: begin
          resp_d.result = minmax_result(lhs, rhs, req_i.rs_fmt, 1'b1);
          resp_d.fflags[FPU_FFLAG_NV] = any_snan;
        end

        FPU_OP_CLASS: begin
          resp_d.result = {54'd0, class_bits(lhs)};
        end

        default: begin end
      endcase
    end
  end

  assign resp_o = resp_d;

endmodule : fpu_compare_unit
