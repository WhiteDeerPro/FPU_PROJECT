//============================================================================
// Basic integrated FPU top.
//
// This wrapper accepts already-decoded fpu_req_t operations, dispatches them to
// the current leaf units, and returns one response per cycle. It is intentionally
// a thin integration shell: a production RV32F/D wrapper still needs instruction
// decode, CSR frm/fflags plumbing, issue scoreboard, and a response queue for
// same-cycle completions from independent pipes.
//============================================================================

module fpu_top
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

  logic op_addsub;
  logic op_mul;
  logic op_fma;
  logic op_div;
  logic op_sqrt;
  logic op_convert;
  logic op_compare;
  logic op_sgnj;
  logic op_move;
  logic issue_valid;

  fpu_resp_t add_resp;
  fpu_resp_t mult_resp;
  fpu_resp_t fma_resp;
  fpu_resp_t div_resp;
  fpu_resp_t sqrt_resp;
  fpu_resp_t convert_resp;
  fpu_resp_t compare_resp;
  fpu_resp_t sgnj_resp_w;
  fpu_resp_t move_resp_w;
  fpu_resp_t sgnj_resp_q;
  fpu_resp_t move_resp_q;
  fpu_resp_t resp_d;
  fpu_resp_t resp_q;

  logic add_valid;
  logic mult_valid;
  logic fma_valid;
  logic div_valid;
  logic sqrt_valid;
  logic convert_valid;
  logic compare_valid;
  logic sgnj_valid_q;
  logic move_valid_q;

  logic add_valid_op;
  logic mult_valid_op;
  logic fma_valid_op;
  logic div_valid_op;
  logic sqrt_valid_op;
  logic convert_valid_op;
  logic compare_valid_op;
  logic sgnj_valid_op_w;
  logic sgnj_valid_op_q;
  logic move_valid_op_w;
  logic move_valid_op_q;
  logic valid_d;
  logic valid_op_d;
  logic valid_q;

  logic div_ready;
  logic sqrt_ready;

  assign op_addsub  = (req_i.op == FPU_OP_ADD) || (req_i.op == FPU_OP_SUB);
  assign op_mul     = (req_i.op == FPU_OP_MUL);
  assign op_fma     = (req_i.op == FPU_OP_FMADD)  ||
                      (req_i.op == FPU_OP_FMSUB)  ||
                      (req_i.op == FPU_OP_FNMSUB) ||
                      (req_i.op == FPU_OP_FNMADD);
  assign op_div     = (req_i.op == FPU_OP_DIV);
  assign op_sqrt    = (req_i.op == FPU_OP_SQRT);
  assign op_convert = (req_i.op == FPU_OP_CVT_FP)  ||
                      (req_i.op == FPU_OP_CVT_F2I) ||
                      (req_i.op == FPU_OP_CVT_I2F);
  assign op_compare = (req_i.op == FPU_OP_EQ)    ||
                      (req_i.op == FPU_OP_LT)    ||
                      (req_i.op == FPU_OP_LE)    ||
                      (req_i.op == FPU_OP_MIN)   ||
                      (req_i.op == FPU_OP_MAX)   ||
                      (req_i.op == FPU_OP_CLASS);
  assign op_sgnj    = (req_i.op == FPU_OP_SGNJ)  ||
                      (req_i.op == FPU_OP_SGNJN) ||
                      (req_i.op == FPU_OP_SGNJX);
  assign op_move    = (req_i.op == FPU_OP_MV_X_FP) ||
                      (req_i.op == FPU_OP_MV_FP_X);

  assign ready_o     = op_div  ? div_ready  :
                       op_sqrt ? sqrt_ready : 1'b1;
  assign issue_valid = valid_i && ready_o;

  fpu_add_unit_pipe u_add (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (issue_valid && op_addsub),
    .req_i     (req_i),
    .valid_o   (add_valid),
    .resp_o    (add_resp),
    .valid_op_o(add_valid_op)
  );

  fpu_mult_unit_pipe u_mult (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (issue_valid && op_mul),
    .req_i     (req_i),
    .valid_o   (mult_valid),
    .resp_o    (mult_resp),
    .valid_op_o(mult_valid_op)
  );

  fpu_fma_unit_pipe u_fma (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (issue_valid && op_fma),
    .req_i     (req_i),
    .valid_o   (fma_valid),
    .resp_o    (fma_resp),
    .valid_op_o(fma_valid_op)
  );

  fpu_div_unit_pipe u_div (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (issue_valid && op_div),
    .req_i     (req_i),
    .ready_o   (div_ready),
    .valid_o   (div_valid),
    .resp_o    (div_resp),
    .valid_op_o(div_valid_op)
  );

  fpu_sqrt_unit_pipe u_sqrt (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (issue_valid && op_sqrt),
    .req_i     (req_i),
    .ready_o   (sqrt_ready),
    .valid_o   (sqrt_valid),
    .resp_o    (sqrt_resp),
    .valid_op_o(sqrt_valid_op)
  );

  fpu_convert_unit_pipe u_convert (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (issue_valid && op_convert),
    .req_i     (req_i),
    .valid_o   (convert_valid),
    .resp_o    (convert_resp),
    .valid_op_o(convert_valid_op)
  );

  fpu_compare_unit_pipe u_compare (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (issue_valid && op_compare),
    .req_i     (req_i),
    .valid_o   (compare_valid),
    .resp_o    (compare_resp),
    .valid_op_o(compare_valid_op)
  );

  fpu_sgnj_unit u_sgnj (
    .req_i     (req_i),
    .resp_o    (sgnj_resp_w),
    .valid_op_o(sgnj_valid_op_w)
  );

  function automatic fpu_data_t nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
  endfunction

  always_comb begin
    move_resp_w      = '0;
    move_resp_w.tag  = req_i.tag;
    move_resp_w.rd   = req_i.rd;
    move_valid_op_w  = op_move &&
                       ((req_i.rs_fmt == FPU_FMT_S) ||
                        (req_i.rs_fmt == FPU_FMT_D));

    if (move_valid_op_w) begin
      unique case (req_i.op)
        FPU_OP_MV_X_FP: begin
          move_resp_w.result = (req_i.rs_fmt == FPU_FMT_S) ?
                               {{32{req_i.src_a[31]}}, req_i.src_a[31:0]} :
                               req_i.src_a;
        end

        FPU_OP_MV_FP_X: begin
          move_resp_w.result = (req_i.dst_fmt == FPU_FMT_S) ?
                               nanbox_s(req_i.src_a[31:0]) :
                               req_i.src_a;
        end

        default: begin
          move_valid_op_w = 1'b0;
        end
      endcase
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sgnj_valid_q    <= 1'b0;
      sgnj_valid_op_q <= 1'b0;
      sgnj_resp_q     <= '0;
      move_valid_q    <= 1'b0;
      move_valid_op_q <= 1'b0;
      move_resp_q     <= '0;
      valid_q         <= 1'b0;
      resp_q          <= '0;
      valid_op_o      <= 1'b0;
    end else begin
      sgnj_valid_q    <= issue_valid && op_sgnj;
      sgnj_valid_op_q <= sgnj_valid_op_w;
      sgnj_resp_q     <= sgnj_resp_w;
      move_valid_q    <= issue_valid && op_move;
      move_valid_op_q <= move_valid_op_w;
      move_resp_q     <= move_resp_w;
      valid_q         <= valid_d;
      resp_q          <= resp_d;
      valid_op_o      <= valid_op_d;
    end
  end

  always_comb begin
    valid_d    = 1'b0;
    valid_op_d = 1'b0;
    resp_d     = '0;

    // TODO: replace fixed priority with a small response FIFO before allowing
    // unrelated pipes to complete in the same cycle under sustained issue.
    if (div_valid) begin
      valid_d    = 1'b1;
      valid_op_d = div_valid_op;
      resp_d     = div_resp;
    end else if (sqrt_valid) begin
      valid_d    = 1'b1;
      valid_op_d = sqrt_valid_op;
      resp_d     = sqrt_resp;
    end else if (fma_valid) begin
      valid_d    = 1'b1;
      valid_op_d = fma_valid_op;
      resp_d     = fma_resp;
    end else if (mult_valid) begin
      valid_d    = 1'b1;
      valid_op_d = mult_valid_op;
      resp_d     = mult_resp;
    end else if (add_valid) begin
      valid_d    = 1'b1;
      valid_op_d = add_valid_op;
      resp_d     = add_resp;
    end else if (convert_valid) begin
      valid_d    = 1'b1;
      valid_op_d = convert_valid_op;
      resp_d     = convert_resp;
    end else if (compare_valid) begin
      valid_d    = 1'b1;
      valid_op_d = compare_valid_op;
      resp_d     = compare_resp;
    end else if (sgnj_valid_q) begin
      valid_d    = 1'b1;
      valid_op_d = sgnj_valid_op_q;
      resp_d     = sgnj_resp_q;
    end else if (move_valid_q) begin
      valid_d    = 1'b1;
      valid_op_d = move_valid_op_q;
      resp_d     = move_resp_q;
    end
  end

  assign valid_o = valid_q;
  assign resp_o  = resp_q;

endmodule : fpu_top
