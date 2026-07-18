`timescale 1ns/1ps

// Minimal core-side model around the configurable fpu_top. It is deliberately
// not an ISA
// simulator: the model contains only the architectural pieces that define the
// FPU boundary -- FPR ownership, a producer scoreboard, a result/fflags ROB,
// ordered commit, and speculative flush.
module tb_fpu_virtual_core;
  import fpu_pkg::*;

  localparam int unsigned ISSUE_WIDTH = 2;
  localparam int unsigned WB_WIDTH    = 2;
  localparam int unsigned TAG_COUNT   = (1 << FPU_TAG_W);

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

  // Architectural state owned by the virtual CPU, not by the FPU.
  fpu_data_t   fpr [0:31];
  fpu_fflags_t fcsr_fflags;

  // CPU dependency and precise-retirement state.
  logic [31:0] fpr_busy;
  fpu_tag_t    fpr_producer [0:31];
  logic        rob_valid  [0:TAG_COUNT-1];
  logic        rob_done   [0:TAG_COUNT-1];
  logic        rob_killed [0:TAG_COUNT-1];
  fpu_data_t   rob_result [0:TAG_COUNT-1];
  fpu_fflags_t rob_fflags [0:TAG_COUNT-1];
  fpu_rd_t     rob_rd     [0:TAG_COUNT-1];

  int unsigned raw_stall_cycles;
  int unsigned wb_count;
  logic        killed_response_seen;

  fpu_top #(
    .ISSUE_WIDTH     (ISSUE_WIDTH),
    .WRITEBACK_WIDTH (WB_WIDTH),
    .RESP_FIFO_DEPTH (16)
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
    $fsdbDumpfile("tb_fpu_virtual_core.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_virtual_core);
  end
`endif

  function automatic fpu_req_t make_d_req(
    input fpu_op_e op,
    input fpu_tag_t tag,
    input fpu_rd_t rd,
    input real a,
    input real b
  );
    fpu_req_t request;
    request         = '0;
    request.op      = op;
    request.rs_fmt  = FPU_FMT_D;
    request.dst_fmt = FPU_FMT_D;
    request.rm      = FPU_RM_RNE;
    request.src_a   = $realtobits(a);
    request.src_b   = $realtobits(b);
    request.tag     = tag;
    request.rd      = rd;
    return request;
  endfunction

  task automatic allocate_rob(input fpu_req_t request);
    rob_valid[request.tag]  = 1'b1;
    rob_done[request.tag]   = 1'b0;
    rob_killed[request.tag] = 1'b0;
    rob_result[request.tag] = '0;
    rob_fflags[request.tag] = '0;
    rob_rd[request.tag]     = request.rd;
    fpr_busy[request.rd]    = 1'b1;
    fpr_producer[request.rd] = request.tag;
  endtask

  task automatic issue_one(input fpu_req_t request);
    logic accepted;
    allocate_rob(request);
    accepted = 1'b0;
    while (!accepted) begin
      @(negedge clk_i);
      valid_i = 2'b01;
      req_i[0] = request;
      req_i[1] = '0;
      #1ns;
      accepted = ready_o[0];
      @(posedge clk_i);
    end
    @(negedge clk_i);
    valid_i = '0;
    req_i   = '0;
  endtask

  task automatic issue_two(input fpu_req_t request0,
                           input fpu_req_t request1);
    logic [1:0] pending;
    logic [1:0] accepted;
    allocate_rob(request0);
    allocate_rob(request1);
    pending = 2'b11;
    while (pending != 0) begin
      @(negedge clk_i);
      valid_i = pending;
      req_i[0] = request0;
      req_i[1] = request1;
      #1ns;
      accepted = pending & ready_o;
      @(posedge clk_i);
      pending = pending & ~accepted;
    end
    @(negedge clk_i);
    valid_i = '0;
    req_i   = '0;
  endtask

  task automatic pulse_flush(input fpu_tag_t min_tag);
    // Called on the negedge immediately following issue, so no extra request
    // can enter between the branch recovery decision and the FPU flush.
    kill_i          = '0;
    kill_i.valid    = 1'b1;
    for (int unsigned tag_idx = 0; tag_idx < FPU_TAG_COUNT; tag_idx++) begin
      kill_i.tag_mask[tag_idx] = (tag_idx >= min_tag);
    end
    for (int unsigned tag = 0; tag < TAG_COUNT; tag++) begin
      if (rob_valid[tag] && (tag >= min_tag)) begin
        rob_killed[tag] = 1'b1;
      end
    end
    #1ns;
    if (ready_o != '0) begin
      $fatal(1, "FPU accepted issue during flush boundary");
    end
    @(posedge clk_i);
    @(negedge clk_i);
    kill_i = '0;
  endtask

  task automatic commit_tag(input fpu_tag_t tag);
    int unsigned timeout;
    if (!rob_valid[tag]) begin
      $fatal(1, "commit of invalid ROB tag %0d", tag);
    end

    if (rob_killed[tag]) begin
      rob_valid[tag] = 1'b0;
      if (fpr_busy[rob_rd[tag]] &&
          (fpr_producer[rob_rd[tag]] == tag)) begin
        fpr_busy[rob_rd[tag]] = 1'b0;
      end
    end else begin
      timeout = 0;
      while (!rob_done[tag] && (timeout < 600)) begin
        @(negedge clk_i);
        #1ns;
        timeout++;
      end
      if (!rob_done[tag]) begin
        $fatal(1, "timeout waiting for ROB tag %0d", tag);
      end

      // Architectural FPR and accrued exception flags change only here.
      fpr[rob_rd[tag]] = rob_result[tag];
      fcsr_fflags      = fcsr_fflags | rob_fflags[tag];
      rob_valid[tag]   = 1'b0;
      if (fpr_busy[rob_rd[tag]] &&
          (fpr_producer[rob_rd[tag]] == tag)) begin
        fpr_busy[rob_rd[tag]] = 1'b0;
      end
    end
  endtask

  // The writeback ports complete speculative ROB entries. They intentionally
  // do not update FPRs or FCSR; commit_tag performs the architectural update.
  always @(negedge clk_i) begin
    if (rst_ni) begin
      for (int unsigned lane = 0; lane < WB_WIDTH; lane++) begin
        if (valid_o[lane] && ready_i[lane]) begin
          wb_count++;
          if (!valid_op_o[lane]) begin
            $fatal(1, "invalid decoded operation reached writeback");
          end
          if ((resp_o[lane].tag == 8'd11) ||
              ((resp_o[lane].tag >= 8'd20) &&
               (resp_o[lane].tag <= 8'd23))) begin
            killed_response_seen = 1'b1;
          end
          if (!rob_valid[resp_o[lane].tag] ||
              rob_killed[resp_o[lane].tag]) begin
            $fatal(1, "writeback for invalid/killed tag %0d",
                   resp_o[lane].tag);
          end
          rob_done[resp_o[lane].tag]   = 1'b1;
          rob_result[resp_o[lane].tag] = resp_o[lane].result;
          rob_fflags[resp_o[lane].tag] = resp_o[lane].fflags;
        end
      end
    end
  end

  initial begin
    fpu_req_t producer_req;
    fpu_req_t consumer_req;
    fpu_req_t older_div_req;
    fpu_req_t younger_sqrt_req;
    fpu_req_t buffered_req0;
    fpu_req_t buffered_req1;
    fpu_req_t buffered_req2;
    fpu_req_t buffered_req3;
    fpu_data_t forwarded_value;
    int unsigned timeout;

    clk_i = 1'b0;
    rst_ni = 1'b0;
    kill_i = '0;
    valid_i = '0;
    req_i = '0;
    ready_i = '1;
    fcsr_fflags = '0;
    fpr_busy = '0;
    raw_stall_cycles = 0;
    wb_count = 0;
    killed_response_seen = 1'b0;
    for (int unsigned idx = 0; idx < 32; idx++) begin
      fpr[idx] = '0;
      fpr_producer[idx] = '0;
    end
    for (int unsigned tag = 0; tag < TAG_COUNT; tag++) begin
      rob_valid[tag] = 1'b0;
      rob_done[tag] = 1'b0;
      rob_killed[tag] = 1'b0;
      rob_result[tag] = '0;
      rob_fflags[tag] = '0;
      rob_rd[tag] = '0;
    end

    repeat (4) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    // RAW: f1 = 2*3, then f2 = f1+1. The core scoreboard stalls the
    // consumer until the producer's ROB result is available, then forwards it.
    producer_req = make_d_req(FPU_OP_MUL, 8'd1, 5'd1, 2.0, 3.0);
    issue_one(producer_req);
    valid_i[0] = 1'b1;
    req_i[0] = make_d_req(FPU_OP_ADD, 8'd1, 5'd5, 4.0, 5.0);
    #1ns;
    if (ready_o[0]) begin
      $fatal(1, "active tag was accepted a second time");
    end
    @(posedge clk_i);
    @(negedge clk_i);
    valid_i = '0;
    req_i   = '0;
    while (!rob_done[8'd1]) begin
      raw_stall_cycles++;
      @(negedge clk_i);
      #1ns;
    end
    if (!fpr_busy[1] || (fpr_producer[1] != 8'd1)) begin
      $fatal(1, "producer scoreboard state was lost before commit");
    end
    forwarded_value = rob_result[8'd1];
    consumer_req = make_d_req(FPU_OP_ADD, 8'd2, 5'd2, 0.0, 1.0);
    consumer_req.src_a = forwarded_value;
    issue_one(consumer_req);
    commit_tag(8'd1);
    commit_tag(8'd2);
    if ((fpr[1] !== $realtobits(6.0)) ||
        (fpr[2] !== $realtobits(7.0)) ||
        (raw_stall_cycles == 0)) begin
      $fatal(1, "RAW/forwarding test failed: f1=%h f2=%h stalls=%0d",
             fpr[1], fpr[2], raw_stall_cycles);
    end

    // Precise flags: older FDIV produces DZ; younger negative FSQRT produces
    // NV but is flushed. Neither result may affect FCSR before ordered commit.
    fcsr_fflags = '0;
    older_div_req = make_d_req(FPU_OP_DIV, 8'd10, 5'd3, 1.0, 0.0);
    younger_sqrt_req = make_d_req(FPU_OP_SQRT, 8'd11, 5'd4, -1.0, 0.0);
    issue_two(older_div_req, younger_sqrt_req);
    pulse_flush(8'd11);

    timeout = 0;
    while (!rob_done[8'd10] && (timeout < 600)) begin
      @(negedge clk_i);
      #1ns;
      timeout++;
    end
    if (!rob_done[8'd10]) begin
      $fatal(1, "older divide did not survive younger flush");
    end
    if (fcsr_fflags != '0) begin
      $fatal(1, "speculative writeback changed FCSR before commit");
    end
    if (!rob_fflags[8'd10][FPU_FFLAG_DZ]) begin
      $fatal(1, "divide-by-zero did not return DZ to the ROB");
    end

    commit_tag(8'd10);
    commit_tag(8'd11);
    if (fcsr_fflags !== (5'b00001 << FPU_FFLAG_DZ)) begin
      $fatal(1, "precise FCSR failed: got=%b expected DZ only",
             fcsr_fflags);
    end
    if (fpr_busy[4]) begin
      $fatal(1, "flushed destination remained busy");
    end

    // Wait for the physically executing killed SQRT to drain and release its
    // reservation. It must never become architecturally visible.
    timeout = 0;
    while ((u_dut.outstanding_q != 0) && (timeout < 600)) begin
      @(negedge clk_i);
      #1ns;
      timeout++;
    end
    if ((u_dut.outstanding_q != 0) || killed_response_seen) begin
      $fatal(1, "flush drain failed: outstanding=%0d killed_seen=%b",
             u_dut.outstanding_q, killed_response_seen);
    end

    // Flush both response-storage levels while the CPU is applying complete
    // writeback backpressure: two results in WB holds and at least one still
    // in the central FIFO. Killed entries must release internally.
    ready_i = '0;
    buffered_req0 = make_d_req(FPU_OP_ADD,   8'd20, 5'd20, 1.0, 2.0);
    buffered_req1 = make_d_req(FPU_OP_MUL,   8'd21, 5'd21, 2.0, 3.0);
    buffered_req2 = make_d_req(FPU_OP_FMADD, 8'd22, 5'd22, 2.0, 3.0);
    buffered_req2.src_c = $realtobits(1.0);
    buffered_req3 = make_d_req(FPU_OP_EQ,    8'd23, 5'd23, 4.0, 4.0);
    issue_two(buffered_req0, buffered_req1);
    issue_two(buffered_req2, buffered_req3);

    timeout = 0;
    while (!((u_dut.wb_valid_q == 2'b11) &&
             (u_dut.resp_count_q != 0)) && (timeout < 100)) begin
      @(negedge clk_i);
      #1ns;
      timeout++;
    end
    if ((u_dut.wb_valid_q != 2'b11) || (u_dut.resp_count_q == 0)) begin
      $fatal(1, "failed to stage responses in both WB and FIFO");
    end
    pulse_flush(8'd20);
    commit_tag(8'd20);
    commit_tag(8'd21);
    commit_tag(8'd22);
    commit_tag(8'd23);

    timeout = 0;
    while ((u_dut.outstanding_q != 0) && (timeout < 100)) begin
      @(negedge clk_i);
      #1ns;
      timeout++;
    end
    if ((u_dut.outstanding_q != 0) || (valid_o != 0) ||
        killed_response_seen) begin
      $fatal(1, "buffered flush failed: outstanding=%0d valid=%b seen=%b",
             u_dut.outstanding_q, valid_o, killed_response_seen);
    end
    ready_i = '1;

    $display("PASS: RAW stalls=%0d, f2=7.0, precise FCSR=%b, completion/WB/FIFO flush suppression, writebacks=%0d",
             raw_stall_cycles, fcsr_fflags, wb_count);
    #20ns;
    $finish;
  end

endmodule : tb_fpu_virtual_core
