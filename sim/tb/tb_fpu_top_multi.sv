`timescale 1ns/1ps

module tb_fpu_top_multi;
  import fpu_pkg::*;

  localparam int unsigned ISSUE_WIDTH = 4;
  localparam int unsigned WB_WIDTH    = 4;
  localparam int unsigned RESP_FIFO_DEPTH = 15;
  localparam int unsigned WRAP_BATCHES = 6;
  localparam int unsigned EXPECTED_ACCEPTED = 12 + (4 * WRAP_BATCHES);

  logic clk_i;
  logic rst_ni;
  fpu_kill_t kill_i;
  logic [ISSUE_WIDTH-1:0] valid_i;
  fpu_req_t [ISSUE_WIDTH-1:0] req_i;
  logic [ISSUE_WIDTH-1:0] ready_o;
  logic [WB_WIDTH-1:0] valid_o;
  logic [WB_WIDTH-1:0] ready_i;
  fpu_resp_t [WB_WIDTH-1:0] resp_o;
  logic [WB_WIDTH-1:0] valid_op_o;

  fpu_resp_t expected_by_tag [0:255];
  logic [255:0] expected_valid;
  int unsigned accepted_count;
  int unsigned consumed_count;
  int unsigned fail_count;
  int unsigned cycle_count;
  int unsigned stalled_wb_count;
  int unsigned max_outstanding_count;
  logic        younger_returned_before_older;
  logic        older_return_observed;
  logic        older_result_visible;
  logic        younger_result_visible;

  fpu_top #(
    .ISSUE_WIDTH     (ISSUE_WIDTH),
    .WRITEBACK_WIDTH (WB_WIDTH),
    .RESP_FIFO_DEPTH (RESP_FIFO_DEPTH)
  ) u_dut (
    .clk_i,
    .rst_ni,
    .kill_i,
    .valid_i,
    .req_i,
    .ready_o,
    .valid_o,
    .ready_i,
    .resp_o,
    .valid_op_o
  );

  always #5ns clk_i = ~clk_i;

`ifdef DUMP_FSDB
  initial begin
    $fsdbDumpfile("tb_fpu_top_multi.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_top_multi);
  end
`endif

  function automatic fpu_req_t make_req(
    input fpu_op_e op,
    input logic [7:0] tag,
    input real a,
    input real b,
    input real c
  );
    fpu_req_t req;
    req         = '0;
    req.op      = op;
    req.rs_fmt  = FPU_FMT_D;
    req.dst_fmt = FPU_FMT_D;
    req.rm      = FPU_RM_RNE;
    req.src_a   = $realtobits(a);
    req.src_b   = $realtobits(b);
    req.src_c   = $realtobits(c);
    req.tag     = tag;
    req.rd      = tag[4:0];
    return req;
  endfunction

  function automatic fpu_resp_t expected_for(input fpu_req_t req);
    fpu_resp_t response;
    real a;
    real b;
    real c;

    response        = '0;
    response.tag    = req.tag;
    response.rd     = req.rd;
    a = $bitstoreal(req.src_a);
    b = $bitstoreal(req.src_b);
    c = $bitstoreal(req.src_c);

    unique case (req.op)
      FPU_OP_ADD:   response.result = $realtobits(a + b);
      FPU_OP_SUB:   response.result = $realtobits(a - b);
      FPU_OP_MUL:   response.result = $realtobits(a * b);
      FPU_OP_FMADD: response.result = $realtobits((a * b) + c);
      FPU_OP_DIV:   response.result = $realtobits(a / b);
      FPU_OP_EQ:    response.result = (a == b) ? 64'd1 : 64'd0;
      FPU_OP_SGNJ:  response.result = {req.src_b[63], req.src_a[62:0]};
      default:      response.result = '0;
    endcase
    return response;
  endfunction

  task automatic issue_once(
    input logic [ISSUE_WIDTH-1:0] lane_valid,
    input fpu_req_t [ISSUE_WIDTH-1:0] lane_req,
    input logic [ISSUE_WIDTH-1:0] expected_ready
  );
    @(negedge clk_i);
    valid_i = lane_valid;
    req_i   = lane_req;
    #1ns;
    if ((ready_o & lane_valid) !== (expected_ready & lane_valid)) begin
      $fatal(1, "issue arbitration mismatch: valid=%b ready=%b expected=%b",
             lane_valid, ready_o, expected_ready);
    end
    @(posedge clk_i);
    for (int unsigned lane = 0; lane < ISSUE_WIDTH; lane++) begin
      if (valid_i[lane] && ready_o[lane]) begin
        expected_by_tag[req_i[lane].tag] = expected_for(req_i[lane]);
        expected_valid[req_i[lane].tag]  = 1'b1;
        accepted_count++;
      end
    end
    @(negedge clk_i);
    valid_i = '0;
    req_i   = '0;
  endtask

  // Independent writeback readiness. Holding lanes see different stall
  // patterns, exercising refill of one lane while another remains blocked.
  always @(negedge clk_i) begin
    if (!rst_ni) begin
      ready_i = '1;
    end else begin
      ready_i[0] = ((cycle_count % 5) != 1);
      ready_i[1] = ((cycle_count % 7) != 2);
      ready_i[2] = ((cycle_count % 4) != 0);
      ready_i[3] = 1'b1;
    end
  end

  // Observe return order at valid_o, independently of consumer readiness.
  // A same-cycle older/younger pair does not count as a younger-before-older
  // inversion.
  always_comb begin
    older_result_visible   = 1'b0;
    younger_result_visible = 1'b0;
    for (int unsigned lane = 0; lane < WB_WIDTH; lane++) begin
      if (valid_o[lane] && (resp_o[lane].tag == 8'd30)) begin
        older_result_visible = 1'b1;
      end
      if (valid_o[lane] && (resp_o[lane].tag >= 8'd1) &&
          (resp_o[lane].tag <= 8'd4)) begin
        younger_result_visible = 1'b1;
      end
    end
  end

  always @(posedge clk_i) begin
    if (rst_ni) begin
      cycle_count++;
      if (u_dut.outstanding_q > max_outstanding_count) begin
        max_outstanding_count = u_dut.outstanding_q;
      end
      if (younger_result_visible && !older_result_visible &&
          !older_return_observed) begin
        younger_returned_before_older = 1'b1;
      end
      if (older_result_visible) begin
        older_return_observed = 1'b1;
      end
      for (int unsigned lane = 0; lane < WB_WIDTH; lane++) begin
        if (valid_o[lane]) begin
          if (!expected_valid[resp_o[lane].tag] ||
              !valid_op_o[lane] ||
              (resp_o[lane] !== expected_by_tag[resp_o[lane].tag])) begin
            fail_count++;
            $display("[FAIL] wb_lane=%0d tag=%0d result=%h expected=%h valid_op=%b",
                     lane, resp_o[lane].tag, resp_o[lane].result,
                     expected_by_tag[resp_o[lane].tag].result,
                     valid_op_o[lane]);
          end
          if (ready_i[lane]) begin
            expected_valid[resp_o[lane].tag] = 1'b0;
            consumed_count++;
          end else begin
            stalled_wb_count++;
          end
        end
      end
    end
  end

  initial begin
    fpu_req_t [ISSUE_WIDTH-1:0] lanes;
    int unsigned timeout;
    int unsigned base_tag;

    clk_i = 1'b0;
    rst_ni = 1'b0;
    kill_i = '0;
    valid_i = '0;
    req_i = '0;
    ready_i = '1;
    expected_valid = '0;
    accepted_count = 0;
    consumed_count = 0;
    fail_count = 0;
    cycle_count = 0;
    stalled_wb_count = 0;
    max_outstanding_count = 0;
    younger_returned_before_older = 1'b0;
    older_return_observed = 1'b0;

    repeat (4) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    // Establish a deterministic age/latency inversion. The older divide stays
    // outstanding while the following short operations complete around it.
    lanes = '0;
    lanes[0] = make_req(FPU_OP_DIV, 8'd30, 144.0, 12.0, 0.0);
    issue_once(4'b0001, lanes, 4'b0001);

    // Four distinct units: all four lanes issue in one cycle.
    lanes[0] = make_req(FPU_OP_ADD,   8'd1, 1.0, 2.0, 0.0);
    lanes[1] = make_req(FPU_OP_MUL,   8'd2, 2.0, 3.0, 0.0);
    lanes[2] = make_req(FPU_OP_FMADD, 8'd3, 2.0, 3.0, 1.0);
    lanes[3] = make_req(FPU_OP_EQ,    8'd4, 4.0, 4.0, 0.0);
    issue_once(4'b1111, lanes, 4'b1111);

    // Distinct units do not make duplicate tags legal: lane 0 claims tag 40
    // and the later lane must be rejected in the same arbitration cycle.
    lanes = '0;
    lanes[0] = make_req(FPU_OP_ADD, 8'd40, 40.0, 2.0, 0.0);
    lanes[1] = make_req(FPU_OP_MUL, 8'd40,  6.0, 7.0, 0.0);
    issue_once(4'b0011, lanes, 4'b0001);

    // Four requests for one ADD pipe: lane 0 wins, high indices lose.
    lanes[0] = make_req(FPU_OP_ADD, 8'd10, 10.0, 1.0, 0.0);
    lanes[1] = make_req(FPU_OP_ADD, 8'd11, 11.0, 1.0, 0.0);
    lanes[2] = make_req(FPU_OP_ADD, 8'd12, 12.0, 1.0, 0.0);
    lanes[3] = make_req(FPU_OP_ADD, 8'd13, 13.0, 1.0, 0.0);
    issue_once(4'b1111, lanes, 4'b0001);

    // A high-index lane can issue naturally when no lower lane conflicts.
    lanes = '0;
    lanes[3] = make_req(FPU_OP_ADD, 8'd13, 13.0, 1.0, 0.0);
    issue_once(4'b1000, lanes, 4'b1000);

    // A second heterogeneous group, including the one-cycle SGNJ path.
    lanes[0] = make_req(FPU_OP_ADD,  8'd20, 5.0, 6.0, 0.0);
    lanes[1] = make_req(FPU_OP_MUL,  8'd21, 4.0, 5.0, 0.0);
    lanes[2] = make_req(FPU_OP_FMADD,8'd22, 3.0, 4.0, 2.0);
    lanes[3] = make_req(FPU_OP_SGNJ, 8'd23,-1.0, 1.0, 0.0);
    issue_once(4'b1111, lanes, 4'b1111);

    // Drive enough additional mixed traffic through a non-power-of-two FIFO
    // to wrap both pointers. The final pointer checks catch truncation before
    // modulo arithmetic as well as lost/duplicated responses.
    for (int unsigned batch = 0; batch < WRAP_BATCHES; batch++) begin
      base_tag = 64 + (4 * batch);
      lanes[0] = make_req(FPU_OP_ADD,   base_tag,     real'(batch + 1), 2.0, 0.0);
      lanes[1] = make_req(FPU_OP_MUL,   base_tag + 1, real'(batch + 2), 3.0, 0.0);
      lanes[2] = make_req(FPU_OP_FMADD, base_tag + 2, real'(batch + 1), 4.0, 1.0);
      lanes[3] = make_req(FPU_OP_EQ,    base_tag + 3, real'(batch),     real'(batch), 0.0);
      issue_once(4'b1111, lanes, 4'b1111);
    end

    timeout = 0;
    while ((consumed_count < accepted_count) && (timeout < 200)) begin
      @(posedge clk_i);
      timeout++;
    end
    #2ns;

    $display("fpu_top 4-lane config: accepted=%0d consumed=%0d fail=%0d wb_stalls=%0d max_outstanding=%0d ooo=%0b fifo_rptr=%0d fifo_wptr=%0d",
             accepted_count, consumed_count, fail_count, stalled_wb_count,
             max_outstanding_count, younger_returned_before_older,
             u_dut.resp_read_ptr_q, u_dut.resp_write_ptr_q);
    if ((accepted_count != EXPECTED_ACCEPTED) ||
        (consumed_count != accepted_count) ||
        (expected_valid != '0) || (fail_count != 0) ||
        (stalled_wb_count == 0) ||
        (max_outstanding_count < (RESP_FIFO_DEPTH - 2)) ||
        !younger_returned_before_older || (u_dut.resp_count_q != 0) ||
        (u_dut.outstanding_q != 0) || (u_dut.wb_valid_q != '0) ||
        (u_dut.resp_read_ptr_q != (accepted_count % RESP_FIFO_DEPTH)) ||
        (u_dut.resp_write_ptr_q != (accepted_count % RESP_FIFO_DEPTH))) begin
      $fatal(1, "fpu_top 4-lane configuration test failed");
    end
    $display("PASS: 4-lane issue, duplicate-tag rejection, OOO return, independent WB stalls, and non-power-of-two FIFO wrap");
    $finish;
  end

endmodule : tb_fpu_top_multi
