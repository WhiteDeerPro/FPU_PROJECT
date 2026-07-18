`timescale 1ns/1ps

// Burst-oriented CV-X-IF diagnostic endpoint for the FMUL pipeline.
// It deliberately supports only coupled, committed FMUL.S/D transactions and
// assumes result_ready=1. This keeps the test focused on sustaining one request
// per cycle through fpu_mult_unit_pipe and its internal fpu_mult_pipe.
module fpu_cvxif_mult_burst_endpoint (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  output fpu_pkg::fpu_fflags_t result_fflags_o,
  core_v_xif                   xif
);
  import fpu_pkg::*;

  fpu_req_t  req;
  fpu_resp_t resp;
  logic      fire;
  logic      valid_o;
  logic      valid_op_o;
  logic      decode_valid;
  logic      channels_match;

  always_comb begin
    decode_valid = (xif.issue_req.instr[6:0] == 7'b1010011) &&
                   ((xif.issue_req.instr[31:25] == 7'b0001000) ||
                    (xif.issue_req.instr[31:25] == 7'b0001001)) &&
                   (xif.issue_req.instr[14:12] <= FPU_RM_RMM);
    channels_match = xif.register_valid && xif.commit_valid &&
                     (xif.register.id == xif.issue_req.id) &&
                     (xif.commit.id == xif.issue_req.id) &&
                     (xif.register.hartid == xif.issue_req.hartid) &&
                     (xif.commit.hartid == xif.issue_req.hartid) &&
                     ((xif.register.rs_valid[1:0] & 2'b11) == 2'b11) &&
                     !xif.commit.commit_kill;

    xif.issue_resp               = '0;
    xif.issue_resp.accept        = decode_valid;
    xif.issue_resp.writeback[0]  = decode_valid;
    xif.issue_resp.register_read = '0;
    xif.issue_resp.register_read[1:0] = decode_valid ? 2'b11 : 2'b00;
    xif.issue_ready              = !decode_valid || channels_match;
    xif.register_ready           = xif.issue_ready;

    req         = '0;
    req.op      = FPU_OP_MUL;
    req.rs_fmt  = xif.issue_req.instr[25] ? FPU_FMT_D : FPU_FMT_S;
    req.dst_fmt = req.rs_fmt;
    req.rm      = fpu_rm_e'(xif.issue_req.instr[14:12]);
    req.src_a   = xif.register.rs[0];
    req.src_b   = xif.register.rs[1];
    req.tag     = fpu_tag_t'(xif.issue_req.id);
    req.rd      = xif.issue_req.instr[11:7];

    xif.result         = '0;
    xif.result.id      = resp.tag;
    xif.result.hartid  = '0;
    xif.result.data    = resp.result;
    xif.result.rd      = resp.rd;
    xif.result.we[0]   = valid_op_o;
    xif.result_valid   = valid_o;
    result_fflags_o    = resp.fflags;

    xif.compressed_ready = 1'b1;
    xif.compressed_resp  = '0;
    xif.mem_valid         = 1'b0;
    xif.mem_req           = '0;
  end

  assign fire = xif.issue_valid && xif.issue_ready && decode_valid;

  fpu_mult_unit_pipe u_mult (
    .clk_i,
    .rst_ni,
    .valid_i   (fire),
    .req_i     (req),
    .valid_o,
    .resp_o    (resp),
    .valid_op_o(valid_op_o)
  );

endmodule : fpu_cvxif_mult_burst_endpoint


module tb_fpu_cvxif_mult_burst;
  import fpu_pkg::*;

  localparam int unsigned SAMPLES_PER_PERIOD = 256;
  localparam int unsigned PERIODS            = 4;
  localparam int unsigned TOTAL_SAMPLES      = SAMPLES_PER_PERIOD * PERIODS;
  localparam real         TWO_PI             = 6.28318530717958647692;

  logic clk_i;
  logic rst_ni;
  fpu_fflags_t result_fflags;

  // Dedicated source-side replicas for Verdi/analog viewing.
  int unsigned input_sample_index;
  real         input_theta_real;
  real         input_cos_real;
  real         input_lhs_real;
  real         input_rhs_real;
  logic [63:0] input_lhs_bits;
  logic [63:0] input_rhs_bits;
  logic        burst_active;
  int unsigned burst_accepted_count;

  // Dedicated result-side replicas for Verdi/analog viewing.
  int unsigned output_sample_index;
  real         output_theta_real;
  real         output_lhs_real;
  real         output_rhs_real;
  real         output_result_real;
  real         output_expected_real;
  real         output_error_real;
  logic [63:0] output_result_bits;
  logic [63:0] output_expected_bits;
  fpu_fflags_t output_fflags;
  int unsigned burst_result_count;
  int unsigned inexact_result_count;

  logic [63:0] expected_bits_by_id [0:255];
  real         theta_by_id         [0:255];
  real         lhs_by_id           [0:255];
  int unsigned sample_by_id        [0:255];

  int unsigned pass_cnt;
  int unsigned fail_cnt;
  int unsigned timeout_cnt;
  int          csv_fd;

  core_v_xif #(
    .X_NUM_RS               (3),
    .X_ID_WIDTH             (8),
    .X_RFR_WIDTH            (64),
    .X_RFW_WIDTH            (64),
    .X_HARTID_WIDTH         (1),
    .X_ISSUE_REGISTER_SPLIT (0)
  ) xif();

  fpu_cvxif_mult_burst_endpoint u_dut (
    .clk_i,
    .rst_ni,
    .result_fflags_o(result_fflags),
    .xif
  );

  always #5ns clk_i = ~clk_i;

`ifdef DUMP_FSDB
  initial begin
    $fsdbDumpfile("tb_fpu_cvxif_mult_burst.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_cvxif_mult_burst);
  end
`endif

  function automatic logic [31:0] fmul_d_instr(input logic [4:0] rd);
    return {7'b0001001, 5'd2, 5'd1, 3'b000, rd, 7'b1010011};
  endfunction

  task automatic drive_idle;
    xif.compressed_valid = 1'b0;
    xif.compressed_req   = '0;
    xif.issue_valid      = 1'b0;
    xif.issue_req        = '0;
    xif.register_valid   = 1'b0;
    xif.register         = '0;
    xif.commit_valid     = 1'b0;
    xif.commit           = '0;
    xif.mem_ready        = 1'b1;
    xif.mem_resp         = '0;
    xif.mem_result_valid = 1'b0;
    xif.mem_result       = '0;
    xif.result_ready     = 1'b1;
  endtask

  // Check every returned tag. IDs may wrap, but the multiply latency is much
  // shorter than 256 cycles, so each table entry is consumed before reuse.
  always @(posedge clk_i) begin
    #1ns;
    if (rst_ni && xif.result_valid) begin
      output_sample_index  = sample_by_id[xif.result.id];
      output_theta_real    = theta_by_id[xif.result.id];
      output_lhs_real      = lhs_by_id[xif.result.id];
      output_rhs_real      = lhs_by_id[xif.result.id];
      output_result_bits   = xif.result.data;
      output_expected_bits = expected_bits_by_id[xif.result.id];
      output_fflags       = result_fflags;
      output_result_real   = $bitstoreal(xif.result.data);
      output_expected_real = $bitstoreal(expected_bits_by_id[xif.result.id]);
      output_error_real    = output_result_real - output_expected_real;
      burst_result_count++;

      if ((xif.result.data !== expected_bits_by_id[xif.result.id]) ||
          ((result_fflags & ~(5'b00001)) != 5'd0)) begin
        fail_cnt++;
        $display("[FAIL] sample=%0d id=%0d theta=%0.8f cos=%0.12f got=%h expected=%h flags=%h",
                 output_sample_index, xif.result.id, output_theta_real,
                 output_lhs_real, xif.result.data,
                 expected_bits_by_id[xif.result.id], result_fflags);
      end else begin
        pass_cnt++;
        if (result_fflags[FPU_FFLAG_NX]) begin
          inexact_result_count++;
        end
      end

      if (csv_fd != 0) begin
        $fdisplay(csv_fd, "%0d,%0d,%0.12f,%0.16f,%0.16f,%0.16f,%0.20f",
                  output_sample_index, xif.result.id, output_theta_real,
                  output_lhs_real, output_result_real,
                  output_expected_real, output_error_real);
      end
    end
  end

  initial begin
    real theta;
    real cos_value;
    real expected_value;
    logic [7:0] id;

    clk_i = 1'b0;
    rst_ni = 1'b0;
    pass_cnt = 0;
    fail_cnt = 0;
    timeout_cnt = 0;
    burst_accepted_count = 0;
    burst_result_count = 0;
    inexact_result_count = 0;
    burst_active = 1'b0;
    input_sample_index = 0;
    input_theta_real = 0.0;
    input_cos_real = 0.0;
    input_lhs_real = 0.0;
    input_rhs_real = 0.0;
    input_lhs_bits = '0;
    input_rhs_bits = '0;
    output_sample_index = 0;
    output_theta_real = 0.0;
    output_lhs_real = 0.0;
    output_rhs_real = 0.0;
    output_result_real = 0.0;
    output_expected_real = 0.0;
    output_error_real = 0.0;
    output_result_bits = '0;
    output_expected_bits = '0;
    output_fflags = '0;
    drive_idle();

    csv_fd = $fopen("tb_fpu_cvxif_mult_burst.csv", "w");
    if (csv_fd != 0) begin
      $fdisplay(csv_fd, "sample,id,theta,cos_x,cos2_result,cos2_expected,error");
    end

    repeat (4) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;
    burst_active = 1'b1;

    // No bubbles: one coupled issue/register/commit transaction every cycle.
    for (int unsigned sample_idx = 0;
         sample_idx < TOTAL_SAMPLES; sample_idx++) begin
      theta          = (TWO_PI * real'(sample_idx)) /
                       real'(SAMPLES_PER_PERIOD);
      cos_value      = $cos(theta);
      expected_value = cos_value * cos_value;
      id             = sample_idx[7:0];

      input_sample_index = sample_idx;
      input_theta_real    = theta;
      input_cos_real      = cos_value;
      input_lhs_real      = cos_value;
      input_rhs_real      = cos_value;
      input_lhs_bits      = $realtobits(cos_value);
      input_rhs_bits      = $realtobits(cos_value);

      expected_bits_by_id[id] = $realtobits(expected_value);
      theta_by_id[id]         = theta;
      lhs_by_id[id]           = cos_value;
      sample_by_id[id]        = sample_idx;

      xif.issue_req.instr  = fmul_d_instr(5'd5);
      xif.issue_req.id     = id;
      xif.issue_req.hartid = '0;
      xif.issue_req.mode   = '0;
      xif.issue_valid      = 1'b1;

      xif.register.id       = id;
      xif.register.hartid   = '0;
      xif.register.rs[0]    = input_lhs_bits;
      xif.register.rs[1]    = input_rhs_bits;
      xif.register.rs[2]    = '0;
      xif.register.rs_valid = 3'b011;
      xif.register_valid    = 1'b1;

      xif.commit.id          = id;
      xif.commit.hartid      = '0;
      xif.commit.commit_kill = 1'b0;
      xif.commit_valid       = 1'b1;

      @(posedge clk_i);
      if (!xif.issue_ready || !xif.issue_resp.accept) begin
        $fatal(1, "burst stalled at sample %0d", sample_idx);
      end
      burst_accepted_count++;
      @(negedge clk_i);
    end

    xif.issue_valid    = 1'b0;
    xif.register_valid = 1'b0;
    xif.commit_valid   = 1'b0;
    burst_active       = 1'b0;

    while ((burst_result_count < TOTAL_SAMPLES) &&
           (timeout_cnt < 32)) begin
      @(posedge clk_i);
      timeout_cnt++;
    end

    if (csv_fd != 0) begin
      $fclose(csv_fd);
    end

    $display("tb_fpu_cvxif_mult_burst: accepted=%0d results=%0d pass=%0d fail=%0d nx=%0d",
             burst_accepted_count, burst_result_count, pass_cnt, fail_cnt,
             inexact_result_count);
    if ((burst_result_count != TOTAL_SAMPLES) || (fail_cnt != 0)) begin
      $fatal(1, "CV-X-IF FMUL.D burst test failed");
    end
    $display("PASS: CV-X-IF sustained one FMUL.D/cycle; internal fpu_mult_pipe filled");
    $finish;
  end

endmodule : tb_fpu_cvxif_mult_burst
