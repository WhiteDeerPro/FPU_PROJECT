module tb_fpu_cvxif_wrapper;
  import fpu_pkg::*;

  logic clk_i;
  logic rst_ni;
  fpu_rm_e frm_i;
  logic [2:0] issue_rs_fpr;
  logic issue_rd_fpr;
  fpu_fflags_t result_fflags;
  logic result_rd_fpr;
  fpu_rm_e [0:0] frm_bus;
  logic [0:0][2:0] issue_rs_fpr_bus;
  logic [0:0] issue_rd_fpr_bus;
  fpu_fflags_t [0:0] result_fflags_bus;
  logic [0:0] result_rd_fpr_bus;

  core_v_xif #(
    .X_NUM_RS               (3),
    .X_ID_WIDTH             (8),
    .X_RFR_WIDTH            (64),
    .X_RFW_WIDTH            (64),
    .X_HARTID_WIDTH         (1),
    .X_DUALREAD             (0),
    .X_DUALWRITE            (0),
    .X_ISSUE_REGISTER_SPLIT (1)
  ) xif [0:0]();

  assign frm_bus[0] = frm_i;
  assign issue_rs_fpr = issue_rs_fpr_bus[0];
  assign issue_rd_fpr = issue_rd_fpr_bus[0];
  assign result_fflags = result_fflags_bus[0];
  assign result_rd_fpr = result_rd_fpr_bus[0];

  fpu_cvxif_wrapper #(
    .X_NUM_PORTS           (1),
    .X_ID_WIDTH             (8),
    .X_HARTID_WIDTH         (1),
    .X_ISSUE_REGISTER_SPLIT (1'b1)
  ) u_dut (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .frm_i            (frm_bus),
    .issue_rs_fpr_o   (issue_rs_fpr_bus),
    .issue_rd_fpr_o   (issue_rd_fpr_bus),
    .result_fflags_o  (result_fflags_bus),
    .result_rd_fpr_o  (result_rd_fpr_bus),
    .xif              (xif)
  );

  always #5ns clk_i = ~clk_i;

`ifdef DUMP_FSDB
  initial begin
    $fsdbDumpfile("tb_fpu_cvxif_wrapper.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_cvxif_wrapper);
  end
`endif

  function automatic logic [31:0] op_fp_instr(
    input logic [6:0] funct7,
    input logic [4:0] rs2,
    input logic [4:0] rs1,
    input logic [2:0] funct3,
    input logic [4:0] rd
  );
    return {funct7, rs2, rs1, funct3, rd, 7'b1010011};
  endfunction

  task automatic clear_cpu_drives;
    xif[0].compressed_valid = 1'b0;
    xif[0].compressed_req   = '0;
    xif[0].issue_valid      = 1'b0;
    xif[0].issue_req        = '0;
    xif[0].register_valid   = 1'b0;
    xif[0].register         = '0;
    xif[0].commit_valid     = 1'b0;
    xif[0].commit           = '0;
    xif[0].mem_ready        = 1'b1;
    xif[0].mem_resp         = '0;
    xif[0].mem_result_valid = 1'b0;
    xif[0].mem_result       = '0;
    xif[0].result_ready     = 1'b0;
  endtask

  task automatic issue_instr(
    input logic [31:0] instruction,
    input logic [7:0]  id
  );
    @(negedge clk_i);
    xif[0].issue_req.instr  = instruction;
    xif[0].issue_req.id     = id;
    xif[0].issue_req.hartid = '0;
    xif[0].issue_req.mode   = '0;
    xif[0].issue_valid      = 1'b1;
    do @(posedge clk_i); while (!xif[0].issue_ready);
    @(negedge clk_i);
    xif[0].issue_valid = 1'b0;
  endtask

  task automatic provide_regs_and_commit(
    input logic [7:0]  id,
    input logic [63:0] src_a,
    input logic [63:0] src_b,
    input logic [63:0] src_c,
    input logic        kill
  );
    @(negedge clk_i);
    xif[0].register.id       = id;
    xif[0].register.hartid   = '0;
    xif[0].register.rs[0]    = src_a;
    xif[0].register.rs[1]    = src_b;
    xif[0].register.rs[2]    = src_c;
    xif[0].register.rs_valid = 3'b111;
    xif[0].register_valid    = 1'b1;
    xif[0].commit.id          = id;
    xif[0].commit.hartid      = '0;
    xif[0].commit.commit_kill = kill;
    xif[0].commit_valid       = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    xif[0].register_valid = 1'b0;
    xif[0].commit_valid   = 1'b0;
  endtask

  initial begin
    logic [31:0] fadd_s;
    logic [31:0] fmul_s;
    logic [63:0] held_data;
    int unsigned timeout;

    clk_i = 1'b0;
    rst_ni = 1'b0;
    frm_i = FPU_RM_RNE;
    clear_cpu_drives();

    repeat (4) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;
    @(posedge clk_i);

    fadd_s = op_fp_instr(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3);
    fmul_s = op_fp_instr(7'b0001000, 5'd2, 5'd1, 3'b000, 5'd4);

    // Unsupported instruction is rejected without consuming the transaction slot.
    @(negedge clk_i);
    xif[0].issue_req.instr = 32'h0000_0013;
    xif[0].issue_valid = 1'b1;
    #1ns;
    if (!xif[0].issue_ready || xif[0].issue_resp.accept) begin
      $fatal(1, "unsupported instruction rejection failed");
    end
    @(posedge clk_i);
    @(negedge clk_i);
    xif[0].issue_valid = 1'b0;

    // 1.5f + 2.25f = 3.75f, with NaN-boxed S operands/results.
    xif[0].issue_req.instr = fadd_s;
    #1ns;
    if (!xif[0].issue_resp.accept || issue_rs_fpr != 3'b011 ||
        !issue_rd_fpr) begin
      $fatal(1, "FADD.S decode or register-bank sideband failed");
    end
    issue_instr(fadd_s, 8'h12);
    provide_regs_and_commit(8'h12,
                            64'hffff_ffff_3fc0_0000,
                            64'hffff_ffff_4010_0000,
                            64'd0,
                            1'b0);

    timeout = 0;
    while (!xif[0].result_valid && timeout < 40) begin
      @(posedge clk_i);
      timeout++;
    end
    if (!xif[0].result_valid) begin
      $fatal(1, "timed out waiting for FADD.S result");
    end
    if (xif[0].result.id != 8'h12 || xif[0].result.rd != 5'd3 ||
        xif[0].result.data != 64'hffff_ffff_4070_0000 ||
        result_fflags != 5'd0 || !result_rd_fpr || xif[0].result.exc) begin
      $fatal(1, "bad FADD.S result: id=%h rd=%0d data=%h flags=%h exc=%b",
             xif[0].result.id, xif[0].result.rd, xif[0].result.data,
             result_fflags, xif[0].result.exc);
    end

    // Result payload must remain stable while the CPU applies backpressure.
    held_data = xif[0].result.data;
    repeat (3) begin
      @(posedge clk_i);
      if (!xif[0].result_valid || xif[0].result.data != held_data) begin
        $fatal(1, "result changed under backpressure");
      end
    end
    @(negedge clk_i);
    xif[0].result_ready = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    xif[0].result_ready = 1'b0;
    @(posedge clk_i);

    // A killed transaction never enters fpu_top and never returns a result.
    issue_instr(fmul_s, 8'h23);
    provide_regs_and_commit(8'h23,
                            64'hffff_ffff_3f80_0000,
                            64'hffff_ffff_4000_0000,
                            64'd0,
                            1'b1);
    repeat (12) begin
      @(posedge clk_i);
      if (xif[0].result_valid) begin
        $fatal(1, "killed transaction produced a result");
      end
    end

    $display("PASS: fpu_cvxif_wrapper smoke test");
    $finish;
  end

endmodule : tb_fpu_cvxif_wrapper

// Small coupled issue/register check for X_ISSUE_REGISTER_SPLIT=0.
module tb_fpu_cvxif_wrapper_coupled;
  import fpu_pkg::*;

  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  logic [2:0] issue_rs_fpr;
  logic issue_rd_fpr;
  fpu_fflags_t result_fflags;
  logic result_rd_fpr;
  fpu_rm_e [0:0] frm_bus;
  logic [0:0][2:0] issue_rs_fpr_bus;
  logic [0:0] issue_rd_fpr_bus;
  fpu_fflags_t [0:0] result_fflags_bus;
  logic [0:0] result_rd_fpr_bus;
  int unsigned timeout;

  core_v_xif #(
    .X_NUM_RS               (3),
    .X_ID_WIDTH             (8),
    .X_RFR_WIDTH            (64),
    .X_RFW_WIDTH            (64),
    .X_HARTID_WIDTH         (1),
    .X_ISSUE_REGISTER_SPLIT (0)
  ) xif [0:0]();

  assign frm_bus[0] = FPU_RM_RNE;
  assign issue_rs_fpr = issue_rs_fpr_bus[0];
  assign issue_rd_fpr = issue_rd_fpr_bus[0];
  assign result_fflags = result_fflags_bus[0];
  assign result_rd_fpr = result_rd_fpr_bus[0];

  fpu_cvxif_wrapper #(
    .X_NUM_PORTS           (1),
    .X_ID_WIDTH             (8),
    .X_HARTID_WIDTH         (1),
    .X_ISSUE_REGISTER_SPLIT (1'b0)
  ) u_dut (
    .clk_i, .rst_ni, .frm_i(frm_bus),
    .issue_rs_fpr_o(issue_rs_fpr_bus),
    .issue_rd_fpr_o(issue_rd_fpr_bus),
    .result_fflags_o(result_fflags_bus),
    .result_rd_fpr_o(result_rd_fpr_bus),
    .xif
  );

  always #5ns clk_i = ~clk_i;

`ifdef DUMP_FSDB
  initial begin
    $fsdbDumpfile("tb_fpu_cvxif_wrapper_coupled.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_cvxif_wrapper_coupled);
  end
`endif

  initial begin
    xif[0].compressed_valid = 1'b0;
    xif[0].compressed_req   = '0;
    xif[0].issue_valid      = 1'b0;
    xif[0].issue_req        = '0;
    xif[0].register_valid   = 1'b0;
    xif[0].register         = '0;
    xif[0].commit_valid     = 1'b0;
    xif[0].commit           = '0;
    xif[0].mem_ready        = 1'b1;
    xif[0].mem_resp         = '0;
    xif[0].mem_result_valid = 1'b0;
    xif[0].mem_result       = '0;
    xif[0].result_ready     = 1'b1;

    repeat (4) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    // Coupled FADD.S issue/register handshake. Commit is coincident with the
    // issue handshake, which CV-X-IF explicitly permits.
    @(negedge clk_i);
    xif[0].issue_req.instr  = {7'b0000000, 5'd2, 5'd1, 3'b000,
                            5'd3, 7'b1010011};
    xif[0].issue_req.id     = 8'h31;
    xif[0].issue_req.hartid = '0;
    xif[0].issue_valid      = 1'b1;
    xif[0].register.id       = 8'h31;
    xif[0].register.hartid   = '0;
    xif[0].register.rs[0]    = 64'hffff_ffff_3fc0_0000;
    xif[0].register.rs[1]    = 64'hffff_ffff_4010_0000;
    xif[0].register.rs[2]    = 64'd0;
    xif[0].register.rs_valid = 3'b111;
    xif[0].register_valid    = 1'b1;
    xif[0].commit.id          = 8'h31;
    xif[0].commit.hartid      = '0;
    xif[0].commit.commit_kill = 1'b0;
    xif[0].commit_valid       = 1'b1;

    @(posedge clk_i);
    if (!xif[0].issue_ready || !xif[0].register_ready ||
        !xif[0].issue_resp.accept) begin
      $fatal(1, "coupled issue/register handshake failed");
    end
    @(negedge clk_i);
    xif[0].issue_valid    = 1'b0;
    xif[0].register_valid = 1'b0;
    xif[0].commit_valid   = 1'b0;

    timeout = 0;
    while (!xif[0].result_valid && timeout < 40) begin
      @(posedge clk_i);
      timeout++;
    end
    if (!xif[0].result_valid ||
        xif[0].result.data != 64'hffff_ffff_4070_0000) begin
      $fatal(1, "coupled FADD.S result failed");
    end
    @(posedge clk_i);
    $display("PASS: fpu_cvxif_wrapper coupled smoke test");
    $finish;
  end

endmodule : tb_fpu_cvxif_wrapper_coupled
