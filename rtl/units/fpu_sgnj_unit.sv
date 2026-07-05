//============================================================================
// Floating-point sign-injection unit.
//
// Flow:
//   req_i
//     -> decode format and SGNJ/SGNJN/SGNJX operation
//     -> extract source signs
//     -> compute injected sign
//     -> preserve src_a payload and replace only the sign bit
//     -> pack response
//============================================================================

module fpu_sgnj_unit
  import fpu_pkg::*;
(
  input  fpu_req_t  req_i,
  output fpu_resp_t resp_o,
  output logic      valid_op_o
);

  // Global datapath and control signals.

  fpu_resp_t resp_d;

  logic src_a_sign;
  logic src_b_sign;
  logic result_sign;
  logic fmt_is_valid;
  logic op_is_valid;

  // Shared helper functions.

  function automatic logic [63:0] nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
  endfunction

  function automatic logic fp_sign_bit(
    input fpu_data_t data,
    input fpu_fmt_e  fmt
  );
    return (fmt == FPU_FMT_D) ? data[63] : data[31];
  endfunction

  function automatic fpu_data_t inject_sign(
    input fpu_data_t data,
    input fpu_fmt_e  fmt,
    input logic      sign
  );
    if (fmt == FPU_FMT_S) begin
      return nanbox_s({sign, data[30:0]});
    end

    return {sign, data[62:0]};
  endfunction

  assign fmt_is_valid = (req_i.rs_fmt == FPU_FMT_S) ||
                        (req_i.rs_fmt == FPU_FMT_D);
  assign op_is_valid  = (req_i.op == FPU_OP_SGNJ)  ||
                        (req_i.op == FPU_OP_SGNJN) ||
                        (req_i.op == FPU_OP_SGNJX);

  assign src_a_sign = fp_sign_bit(req_i.src_a, req_i.rs_fmt);
  assign src_b_sign = fp_sign_bit(req_i.src_b, req_i.rs_fmt);

  // Operation decode and final response mux.

  always_comb begin
    unique case (req_i.op)
      FPU_OP_SGNJ:  result_sign = src_b_sign;
      FPU_OP_SGNJN: result_sign = ~src_b_sign;
      FPU_OP_SGNJX: result_sign = src_a_sign ^ src_b_sign;
      default:      result_sign = 1'b0;
    endcase
  end

  always_comb begin
    resp_d      = '0;
    resp_d.tag  = req_i.tag;
    resp_d.rd   = req_i.rd;
    valid_op_o  = op_is_valid && fmt_is_valid;

    if (valid_op_o) begin
      resp_d.result = inject_sign(req_i.src_a, req_i.rs_fmt, result_sign);
    end
  end

  assign resp_o = resp_d;

endmodule : fpu_sgnj_unit
