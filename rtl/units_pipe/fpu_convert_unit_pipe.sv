//============================================================================
// Pipelined floating-point conversion wrapper.
//
// Flow:
//   req_i
//     -> stage 1 register for request/control payload
//     -> existing conversion leaf datapaths in parallel
//     -> stage 2 register for selected response and valid_op
//
// This is a coarse 3-combinational-stage wrapper: input register, conversion
// core, output register.  It preserves the existing conversion behavior while
// giving the top-level scheduler a fixed-latency, one-request-per-cycle pipe.
// Fine-grain cuts inside I2F/F2F/F2I can be added later if the middle stage is
// still timing-critical.
//============================================================================

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

  fpu_req_t  s1_req;
  logic      s1_valid;
  fpu_resp_t s1_resp;
  logic      s1_valid_op;

  fpu_resp_t s2_resp;
  logic      s2_valid;
  logic      s2_valid_op;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s1_req   <= '0;
      s1_valid <= 1'b0;
    end else begin
      s1_req   <= req_i;
      s1_valid <= valid_i;
    end
  end

  fpu_convert_unit u_core (
    .req_i     (s1_req),
    .resp_o    (s1_resp),
    .valid_op_o(s1_valid_op)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s2_resp     <= '0;
      s2_valid    <= 1'b0;
      s2_valid_op <= 1'b0;
    end else begin
      s2_resp     <= s1_resp;
      s2_valid    <= s1_valid;
      s2_valid_op <= s1_valid && s1_valid_op;
    end
  end

  assign valid_o    = s2_valid;
  assign resp_o     = s2_resp;
  assign valid_op_o = s2_valid_op;

endmodule : fpu_convert_unit_pipe
