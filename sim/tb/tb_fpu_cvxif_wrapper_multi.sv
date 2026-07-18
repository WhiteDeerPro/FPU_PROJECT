`timescale 1ns/1ps

module tb_fpu_cvxif_wrapper_multi;
  import fpu_pkg::*;

  localparam int unsigned PORTS = 4;

  logic clk_i;
  logic rst_ni;
  fpu_rm_e [PORTS-1:0] frm_i;
  logic [PORTS-1:0][2:0] issue_rs_fpr;
  logic [PORTS-1:0] issue_rd_fpr;
  fpu_fflags_t [PORTS-1:0] result_fflags;
  logic [PORTS-1:0] result_rd_fpr;

  core_v_xif #(
    .X_NUM_RS               (3),
    .X_ID_WIDTH             (8),
    .X_RFR_WIDTH            (64),
    .X_RFW_WIDTH            (64),
    .X_HARTID_WIDTH         (1),
    .X_DUALREAD             (0),
    .X_DUALWRITE            (0),
    .X_ISSUE_REGISTER_SPLIT (1)
  ) xif [PORTS-1:0]();

  logic [PORTS-1:0] issue_valid_d;
  logic [PORTS-1:0][31:0] instr_d;
  logic [PORTS-1:0][7:0] id_d;
  logic [PORTS-1:0] register_valid_d;
  logic [PORTS-1:0][2:0][63:0] rs_d;
  logic [PORTS-1:0][2:0] rs_valid_d;
  logic [PORTS-1:0] commit_valid_d;
  logic [PORTS-1:0] commit_kill_d;
  logic [PORTS-1:0] result_ready_d;

  logic [PORTS-1:0] issue_ready;
  logic [PORTS-1:0] issue_accept;
  logic [PORTS-1:0] register_ready;
  logic [PORTS-1:0] result_valid;
  logic [PORTS-1:0][7:0] result_id;
  logic [PORTS-1:0][4:0] result_rd;
  logic [PORTS-1:0][63:0] result_data;
  logic [PORTS-1:0] result_exc;

  logic [PORTS-1:0] expected_valid;
  logic [PORTS-1:0][7:0] expected_id;
  logic [PORTS-1:0][4:0] expected_rd;
  logic [PORTS-1:0][63:0] expected_data;
  logic [PORTS-1:0] expected_rd_fpr;
  logic [PORTS-1:0] consumed;
  logic track_same_unit;
  int unsigned same_unit_accept_count;
  int unsigned fail_count;

  for (genvar p = 0; p < PORTS; p++) begin : g_cpu_wiring
    assign xif[p].compressed_valid = 1'b0;
    assign xif[p].compressed_req   = '0;
    assign xif[p].issue_valid      = issue_valid_d[p];
    assign xif[p].issue_req.instr  = instr_d[p];
    assign xif[p].issue_req.mode   = '0;
    assign xif[p].issue_req.hartid = '0;
    assign xif[p].issue_req.id     = id_d[p];
    assign xif[p].register_valid   = register_valid_d[p];
    assign xif[p].register.hartid  = '0;
    assign xif[p].register.id      = id_d[p];
    assign xif[p].register.rs      = rs_d[p];
    assign xif[p].register.rs_valid = rs_valid_d[p];
    assign xif[p].commit_valid      = commit_valid_d[p];
    assign xif[p].commit.hartid     = '0;
    assign xif[p].commit.id         = id_d[p];
    assign xif[p].commit.commit_kill = commit_kill_d[p];
    assign xif[p].mem_ready         = 1'b1;
    assign xif[p].mem_resp          = '0;
    assign xif[p].mem_result_valid  = 1'b0;
    assign xif[p].mem_result        = '0;
    assign xif[p].result_ready      = result_ready_d[p];

    assign issue_ready[p]    = xif[p].issue_ready;
    assign issue_accept[p]   = xif[p].issue_resp.accept;
    assign register_ready[p] = xif[p].register_ready;
    assign result_valid[p]   = xif[p].result_valid;
    assign result_id[p]      = xif[p].result.id;
    assign result_rd[p]      = xif[p].result.rd;
    assign result_data[p]    = xif[p].result.data;
    assign result_exc[p]     = xif[p].result.exc;
  end

  fpu_cvxif_wrapper #(
    .X_NUM_PORTS           (PORTS),
    .X_ID_WIDTH             (8),
    .X_HARTID_WIDTH         (1),
    .X_ISSUE_REGISTER_SPLIT (1'b1),
    .FPU_RESP_FIFO_DEPTH    (24)
  ) u_dut (
    .clk_i,
    .rst_ni,
    .frm_i,
    .issue_rs_fpr_o  (issue_rs_fpr),
    .issue_rd_fpr_o  (issue_rd_fpr),
    .result_fflags_o (result_fflags),
    .result_rd_fpr_o (result_rd_fpr),
    .xif
  );

  always #5ns clk_i = ~clk_i;

`ifdef DUMP_FSDB
  initial begin
    $fsdbDumpfile("tb_fpu_cvxif_wrapper_multi.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_cvxif_wrapper_multi);
  end
`endif

  function automatic logic [31:0] op_fp_instr(
    input logic [6:0] funct7,
    input logic [2:0] funct3,
    input logic [4:0] rd
  );
    return {funct7, 5'd2, 5'd1, funct3, rd, 7'b1010011};
  endfunction

  function automatic logic [31:0] fmadd_d_instr(input logic [4:0] rd);
    return {5'd3, 2'b01, 5'd2, 5'd1, 3'b000, rd, 7'b1000011};
  endfunction

  task automatic launch_all;
    @(negedge clk_i);
    issue_valid_d = '1;
    #1ns;
    if ((issue_ready !== '1) || (issue_accept !== '1)) begin
      $fatal(1, "not all CV-X-IF ports accepted issue: ready=%b accept=%b",
             issue_ready, issue_accept);
    end
    @(posedge clk_i);
    @(negedge clk_i);
    issue_valid_d    = '0;
    register_valid_d = '1;
    commit_valid_d   = '1;
    #1ns;
    if (register_ready !== '1) begin
      $fatal(1, "split register channels were not independently ready");
    end
    @(posedge clk_i);
    @(negedge clk_i);
    register_valid_d = '0;
    commit_valid_d   = '0;
  endtask

  always @(posedge clk_i) begin
    if (rst_ni) begin
      for (int unsigned p = 0; p < PORTS; p++) begin
        if (result_valid[p]) begin
          if (!expected_valid[p] || result_exc[p] ||
              (result_id[p] !== expected_id[p]) ||
              (result_rd[p] !== expected_rd[p]) ||
              (result_data[p] !== expected_data[p]) ||
              (result_rd_fpr[p] !== expected_rd_fpr[p]) ||
              (result_fflags[p] !== 5'd0)) begin
            fail_count++;
            $display("[FAIL] port=%0d id=%h rd=%0d data=%h exp=%h exc=%b",
                     p, result_id[p], result_rd[p], result_data[p],
                     expected_data[p], result_exc[p]);
          end
          if (result_ready_d[p]) begin
            consumed[p] = 1'b1;
          end
        end
      end

      if (track_same_unit &&
          (|(u_dut.fpu_issue_valid & u_dut.fpu_issue_ready))) begin
        if ((u_dut.fpu_issue_valid & u_dut.fpu_issue_ready) !==
            (4'b0001 << same_unit_accept_count)) begin
          $fatal(1, "same-unit arbitration order mismatch: count=%0d fire=%b",
                 same_unit_accept_count,
                 u_dut.fpu_issue_valid & u_dut.fpu_issue_ready);
        end
        same_unit_accept_count++;
      end
    end
  end

  initial begin
    logic [63:0] held_port0_data;
    int unsigned timeout;

    clk_i = 1'b0;
    rst_ni = 1'b0;
    frm_i = '{default:FPU_RM_RNE};
    issue_valid_d = '0;
    instr_d = '0;
    id_d = '0;
    register_valid_d = '0;
    rs_d = '0;
    rs_valid_d = '1;
    commit_valid_d = '0;
    commit_kill_d = '0;
    result_ready_d = '0;
    expected_valid = '0;
    expected_id = '0;
    expected_rd = '0;
    expected_data = '0;
    expected_rd_fpr = '0;
    consumed = '0;
    track_same_unit = 1'b0;
    same_unit_accept_count = 0;
    fail_count = 0;

    repeat (4) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    // Four protocol ports use the same external ID, but target four distinct
    // shared units. All four native issue lanes must fire together.
    instr_d[0] = op_fp_instr(7'b0000001, 3'b000, 5'd8); // FADD.D
    instr_d[1] = op_fp_instr(7'b0001001, 3'b000, 5'd9); // FMUL.D
    instr_d[2] = fmadd_d_instr(5'd10);                   // FMADD.D
    instr_d[3] = op_fp_instr(7'b1010001, 3'b010, 5'd11);// FEQ.D
    id_d = '{default:8'h55};
    rs_d[0][0] = $realtobits(1.0); rs_d[0][1] = $realtobits(2.0);
    rs_d[1][0] = $realtobits(3.0); rs_d[1][1] = $realtobits(4.0);
    rs_d[2][0] = $realtobits(2.0); rs_d[2][1] = $realtobits(3.0);
    rs_d[2][2] = $realtobits(1.0);
    rs_d[3][0] = $realtobits(4.0); rs_d[3][1] = $realtobits(4.0);
    expected_valid = '1;
    expected_id = id_d;
    expected_rd[0] = 5'd8; expected_data[0] = $realtobits(3.0);
    expected_rd[1] = 5'd9; expected_data[1] = $realtobits(12.0);
    expected_rd[2] = 5'd10; expected_data[2] = $realtobits(7.0);
    expected_rd[3] = 5'd11; expected_data[3] = 64'd1;
    expected_rd_fpr = 4'b0111;
    result_ready_d = 4'b1110;
    launch_all();

    timeout = 0;
    while (((consumed & 4'b1110) != 4'b1110) && (timeout < 100)) begin
      @(posedge clk_i);
      #1ns;
      timeout++;
    end
    if ((consumed & 4'b1110) != 4'b1110) begin
      $fatal(1, "independent ports did not complete while port0 stalled");
    end
    while (!result_valid[0] && (timeout < 120)) begin
      @(posedge clk_i);
      #1ns;
      timeout++;
    end
    if (!result_valid[0]) begin
      $fatal(1, "port0 result never reached its holding state");
    end
    held_port0_data = result_data[0];
    repeat (3) begin
      @(posedge clk_i);
      if (!result_valid[0] || (result_data[0] != held_port0_data)) begin
        $fatal(1, "port0 result did not remain stable under backpressure");
      end
    end
    @(negedge clk_i);
    result_ready_d[0] = 1'b1;
    timeout = 0;
    while (!consumed[0] && (timeout < 20)) begin
      @(posedge clk_i);
      #1ns;
      timeout++;
    end
    if (!consumed[0]) begin
      $fatal(1, "stalled port0 result was not consumed");
    end

    // Four FADD.D requests are accepted by four CV-X-IF slots together, then
    // serialized by fpu_top's single ADD pipe in port-index priority order.
    @(negedge clk_i);
    consumed = '0;
    same_unit_accept_count = 0;
    track_same_unit = 1'b1;
    result_ready_d = '1;
    for (int unsigned p = 0; p < PORTS; p++) begin
      instr_d[p] = op_fp_instr(7'b0000001, 3'b000, 5'd16 + p);
      id_d[p] = 8'h60 + p;
      rs_d[p][0] = $realtobits(real'(p + 1));
      rs_d[p][1] = $realtobits(10.0);
      rs_d[p][2] = '0;
      expected_id[p] = id_d[p];
      expected_rd[p] = 5'd16 + p;
      expected_data[p] = $realtobits(real'(p + 11));
      expected_rd_fpr[p] = 1'b1;
    end
    launch_all();

    timeout = 0;
    while ((consumed != '1) && (timeout < 100)) begin
      @(posedge clk_i);
      #1ns;
      timeout++;
    end
    track_same_unit = 1'b0;
    if ((consumed != '1) || (same_unit_accept_count != 4) ||
        (fail_count != 0)) begin
      $fatal(1, "multi-port CV-X-IF test failed: consumed=%b accepts=%0d fail=%0d",
             consumed, same_unit_accept_count, fail_count);
    end

    $display("PASS: 4 CV-X-IF ports, heterogeneous 4-way issue, same-unit arbitration, routed IDs, and independent result backpressure");
    #20ns;
    $finish;
  end

endmodule : tb_fpu_cvxif_wrapper_multi
