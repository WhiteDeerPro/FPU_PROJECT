`timescale 1ns/1ps

module tb_fpu_fma;
  import fpu_pkg::*;

  localparam fpu_fflags_t FFLAGS_NONE = 5'b0_0000;
  localparam fpu_fflags_t FFLAGS_NV   = 5'b1_0000;

  fpu_req_t  req_i;
  fpu_resp_t resp_o;
  logic      valid_op_o;

  int unsigned pass_cnt;
  int unsigned fail_cnt;
  int unsigned case_id;
  string       dbg_case_name;

  logic        dbg_is_fma;
  logic        dbg_is_s;
  logic        dbg_is_d;
  logic [31:0] dbg_s_src_a;
  logic [31:0] dbg_s_src_b;
  logic [31:0] dbg_s_src_c;
  logic [31:0] dbg_s_result;
  logic [63:0] dbg_d_src_a;
  logic [63:0] dbg_d_src_b;
  logic [63:0] dbg_d_src_c;
  logic [63:0] dbg_d_result;
  real         dbg_d_src_a_real;
  real         dbg_d_src_b_real;
  real         dbg_d_src_c_real;
  real         dbg_d_result_real;

  fpu_fma_unit dut (
    .req_i     (req_i),
    .resp_o    (resp_o),
    .valid_op_o(valid_op_o)
  );

  function automatic fpu_data_t nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
  endfunction

  assign dbg_is_fma = (req_i.op == FPU_OP_FMADD)  ||
                      (req_i.op == FPU_OP_FMSUB)  ||
                      (req_i.op == FPU_OP_FNMSUB) ||
                      (req_i.op == FPU_OP_FNMADD);
  assign dbg_is_s = dbg_is_fma && (req_i.rs_fmt == FPU_FMT_S);
  assign dbg_is_d = dbg_is_fma && (req_i.rs_fmt == FPU_FMT_D);

  assign dbg_s_src_a = dbg_is_s ? req_i.src_a[31:0] : 32'd0;
  assign dbg_s_src_b = dbg_is_s ? req_i.src_b[31:0] : 32'd0;
  assign dbg_s_src_c = dbg_is_s ? req_i.src_c[31:0] : 32'd0;
  assign dbg_s_result = dbg_is_s ? resp_o.result[31:0] : 32'd0;
  assign dbg_d_src_a = dbg_is_d ? req_i.src_a : 64'd0;
  assign dbg_d_src_b = dbg_is_d ? req_i.src_b : 64'd0;
  assign dbg_d_src_c = dbg_is_d ? req_i.src_c : 64'd0;
  assign dbg_d_result = dbg_is_d ? resp_o.result : 64'd0;

  always @* begin
    dbg_d_src_a_real  = dbg_is_d ? $bitstoreal(req_i.src_a) : 0.0;
    dbg_d_src_b_real  = dbg_is_d ? $bitstoreal(req_i.src_b) : 0.0;
    dbg_d_src_c_real  = dbg_is_d ? $bitstoreal(req_i.src_c) : 0.0;
    dbg_d_result_real = dbg_is_d ? $bitstoreal(resp_o.result) : 0.0;
  end

  task automatic drive_idle;
    req_i = '0;
    dbg_case_name = "idle";
    #1;
  endtask

  task automatic apply_req(
    input string     name,
    input fpu_op_e   op,
    input fpu_fmt_e  fmt,
    input fpu_rm_e   rm,
    input fpu_data_t src_a,
    input fpu_data_t src_b,
    input fpu_data_t src_c
  );
    req_i = '0;
    req_i.op      = op;
    req_i.rs_fmt  = fmt;
    req_i.dst_fmt = fmt;
    req_i.rm      = rm;
    req_i.src_a   = src_a;
    req_i.src_b   = src_b;
    req_i.src_c   = src_c;
    req_i.tag     = 8'h5a;
    req_i.rd      = 5'd17;
    dbg_case_name = name;
    case_id++;
    #1;
  endtask

  task automatic check_fma(
    input string       name,
    input fpu_op_e     op,
    input fpu_fmt_e    fmt,
    input fpu_rm_e     rm,
    input fpu_data_t   src_a,
    input fpu_data_t   src_b,
    input fpu_data_t   src_c,
    input fpu_data_t   exp_result,
    input fpu_fflags_t exp_fflags,
    input logic        exp_valid
  );
    apply_req(name, op, fmt, rm, src_a, src_b, src_c);

    if ((valid_op_o !== exp_valid) ||
        (resp_o.result !== exp_result) ||
        (resp_o.fflags !== exp_fflags) ||
        (resp_o.tag !== req_i.tag) ||
        (resp_o.rd !== req_i.rd)) begin
      fail_cnt++;
      $display("[FAIL] %-32s valid exp=%0b got=%0b result exp=0x%016h got=0x%016h fflags exp=0x%02h got=0x%02h",
               name, exp_valid, valid_op_o, exp_result, resp_o.result,
               exp_fflags, resp_o.fflags);
    end else begin
      pass_cnt++;
      $display("[PASS] %-32s result=0x%016h fflags=0x%02h",
               name, resp_o.result, resp_o.fflags);
    end

    drive_idle();
  endtask

  initial begin
`ifdef DUMP_FSDB
    $fsdbDumpfile("tb_fpu_fma.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_fma);
`endif

    pass_cnt = 0;
    fail_cnt = 0;
    case_id  = 0;
    drive_idle();

    check_fma("s_fmadd_1p5_2p0_0p5", FPU_OP_FMADD, FPU_FMT_S, FPU_RM_RNE,
              nanbox_s(32'h3fc0_0000), nanbox_s(32'h4000_0000),
              nanbox_s(32'h3f00_0000),
              nanbox_s(32'h4060_0000), FFLAGS_NONE, 1'b1);

    check_fma("s_fmsub_fused_cancel", FPU_OP_FMSUB, FPU_FMT_S, FPU_RM_RNE,
              nanbox_s(32'h3f80_0001), nanbox_s(32'h3f7f_fffe),
              nanbox_s(32'h3f80_0000),
              nanbox_s(32'ha880_0000), FFLAGS_NONE, 1'b1);

    check_fma("d_fmadd_1p5_2p0_0p5", FPU_OP_FMADD, FPU_FMT_D, FPU_RM_RNE,
              64'h3ff8_0000_0000_0000, 64'h4000_0000_0000_0000,
              64'h3fe0_0000_0000_0000,
              64'h400c_0000_0000_0000, FFLAGS_NONE, 1'b1);

    check_fma("d_fmsub_1p5_2p0_0p5", FPU_OP_FMSUB, FPU_FMT_D, FPU_RM_RNE,
              64'h3ff8_0000_0000_0000, 64'h4000_0000_0000_0000,
              64'h3fe0_0000_0000_0000,
              64'h4004_0000_0000_0000, FFLAGS_NONE, 1'b1);

    check_fma("d_fnmsub_1p5_2p0_0p5", FPU_OP_FNMSUB, FPU_FMT_D, FPU_RM_RNE,
              64'h3ff8_0000_0000_0000, 64'h4000_0000_0000_0000,
              64'h3fe0_0000_0000_0000,
              64'hc004_0000_0000_0000, FFLAGS_NONE, 1'b1);

    check_fma("d_fnmadd_1p5_2p0_0p5", FPU_OP_FNMADD, FPU_FMT_D, FPU_RM_RNE,
              64'h3ff8_0000_0000_0000, 64'h4000_0000_0000_0000,
              64'h3fe0_0000_0000_0000,
              64'hc00c_0000_0000_0000, FFLAGS_NONE, 1'b1);

    check_fma("d_fmsub_fused_cancel", FPU_OP_FMSUB, FPU_FMT_D, FPU_RM_RNE,
              64'h3ff0_0000_0000_0001, 64'h3fef_ffff_ffff_fffe,
              64'h3ff0_0000_0000_0000,
              64'hb970_0000_0000_0000, FFLAGS_NONE, 1'b1);

    check_fma("d_fmadd_inf_zero_invalid", FPU_OP_FMADD, FPU_FMT_D, FPU_RM_RNE,
              64'h7ff0_0000_0000_0000, 64'h0000_0000_0000_0000,
              64'h3ff0_0000_0000_0000,
              64'h7ff8_0000_0000_0000, FFLAGS_NV, 1'b1);

    check_fma("d_fmadd_inf_sub_inf_invalid", FPU_OP_FMADD, FPU_FMT_D, FPU_RM_RNE,
              64'h7ff0_0000_0000_0000, 64'h3ff0_0000_0000_0000,
              64'hfff0_0000_0000_0000,
              64'h7ff8_0000_0000_0000, FFLAGS_NV, 1'b1);

    check_fma("invalid_op", FPU_OP_MUL, FPU_FMT_D, FPU_RM_RNE,
              64'h3ff0_0000_0000_0000, 64'h3ff0_0000_0000_0000,
              64'h3ff0_0000_0000_0000,
              64'd0, FFLAGS_NONE, 1'b0);

    $display("tb_fpu_fma summary: pass=%0d fail=%0d cases=%0d",
             pass_cnt, fail_cnt, case_id);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_fma failed");
    end

    $finish;
  end

endmodule : tb_fpu_fma
