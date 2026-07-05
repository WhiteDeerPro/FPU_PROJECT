`timescale 1ns/1ps

module tb_fpu_sgnj;
  import fpu_pkg::*;

  localparam fpu_fflags_t FFLAGS_NONE = 5'b0_0000;

  fpu_req_t  req_i;
  fpu_resp_t resp_o;
  logic      valid_op_o;

  int unsigned pass_cnt;
  int unsigned fail_cnt;
  int unsigned case_id;
  string       dbg_case_name;

  logic        dbg_is_sgnj;
  logic        dbg_is_sgnjn;
  logic        dbg_is_sgnjx;
  logic        dbg_is_s;
  logic        dbg_is_d;
  logic [63:0] dbg_src_a;
  logic [63:0] dbg_src_b;
  logic [63:0] dbg_result;
  logic [31:0] dbg_src_a_hi32;
  logic [31:0] dbg_src_a_lo32;
  logic [31:0] dbg_src_b_hi32;
  logic [31:0] dbg_src_b_lo32;
  logic [31:0] dbg_result_hi32;
  logic [31:0] dbg_result_lo32;
  logic [31:0] dbg_s_src_a;
  logic [31:0] dbg_s_src_b;
  logic [31:0] dbg_s_result;
  logic [63:0] dbg_d_src_a;
  logic [63:0] dbg_d_src_b;
  logic [63:0] dbg_d_result;
  real         dbg_d_src_a_real;
  real         dbg_d_src_b_real;
  real         dbg_d_result_real;
  logic        dbg_src_a_sign;
  logic        dbg_src_b_sign;
  logic        dbg_result_sign;

  logic        sgnj_s_is;
  logic [31:0] sgnj_s_src_a_s;
  logic [31:0] sgnj_s_src_b_s;
  logic [31:0] sgnj_s_result_s;
  logic        sgnj_s_src_a_sign;
  logic        sgnj_s_src_b_sign;
  logic        sgnj_s_result_sign;

  logic        sgnj_d_is;
  logic [63:0] sgnj_d_src_a_d;
  logic [63:0] sgnj_d_src_b_d;
  logic [63:0] sgnj_d_result_d;
  real         sgnj_d_src_a_real;
  real         sgnj_d_src_b_real;
  real         sgnj_d_result_real;
  logic        sgnj_d_src_a_sign;
  logic        sgnj_d_src_b_sign;
  logic        sgnj_d_result_sign;

  fpu_sgnj_unit dut (
    .req_i     (req_i),
    .resp_o    (resp_o),
    .valid_op_o(valid_op_o)
  );

  function automatic fpu_data_t nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
  endfunction

  assign dbg_is_sgnj = (req_i.op == FPU_OP_SGNJ)  ||
                       (req_i.op == FPU_OP_SGNJN) ||
                       (req_i.op == FPU_OP_SGNJX);
  assign dbg_is_sgnjn = (req_i.op == FPU_OP_SGNJN);
  assign dbg_is_sgnjx = (req_i.op == FPU_OP_SGNJX);
  assign dbg_is_s      = dbg_is_sgnj && (req_i.rs_fmt == FPU_FMT_S);
  assign dbg_is_d      = dbg_is_sgnj && (req_i.rs_fmt == FPU_FMT_D);
  assign dbg_src_a     = dbg_is_sgnj ? req_i.src_a : 64'd0;
  assign dbg_src_b     = dbg_is_sgnj ? req_i.src_b : 64'd0;
  assign dbg_result    = dbg_is_sgnj ? resp_o.result : 64'd0;
  assign dbg_src_a_hi32  = dbg_is_sgnj ? req_i.src_a[63:32] : 32'd0;
  assign dbg_src_a_lo32  = dbg_is_sgnj ? req_i.src_a[31:0]  : 32'd0;
  assign dbg_src_b_hi32  = dbg_is_sgnj ? req_i.src_b[63:32] : 32'd0;
  assign dbg_src_b_lo32  = dbg_is_sgnj ? req_i.src_b[31:0]  : 32'd0;
  assign dbg_result_hi32 = dbg_is_sgnj ? resp_o.result[63:32] : 32'd0;
  assign dbg_result_lo32 = dbg_is_sgnj ? resp_o.result[31:0]  : 32'd0;
  assign dbg_s_src_a   = dbg_is_s ? req_i.src_a[31:0] : 32'd0;
  assign dbg_s_src_b   = dbg_is_s ? req_i.src_b[31:0] : 32'd0;
  assign dbg_s_result  = dbg_is_s ? resp_o.result[31:0] : 32'd0;
  assign dbg_d_src_a   = dbg_is_d ? req_i.src_a : 64'd0;
  assign dbg_d_src_b   = dbg_is_d ? req_i.src_b : 64'd0;
  assign dbg_d_result  = dbg_is_d ? resp_o.result : 64'd0;
  assign dbg_src_a_sign = dbg_is_s ? req_i.src_a[31] :
                          dbg_is_d ? req_i.src_a[63] : 1'b0;
  assign dbg_src_b_sign = dbg_is_s ? req_i.src_b[31] :
                          dbg_is_d ? req_i.src_b[63] : 1'b0;
  assign dbg_result_sign = dbg_is_s ? resp_o.result[31] :
                           dbg_is_d ? resp_o.result[63] : 1'b0;

  assign sgnj_s_is          = dbg_is_s;
  assign sgnj_s_src_a_s     = sgnj_s_is ? req_i.src_a[31:0] : 32'd0;
  assign sgnj_s_src_b_s     = sgnj_s_is ? req_i.src_b[31:0] : 32'd0;
  assign sgnj_s_result_s    = sgnj_s_is ? resp_o.result[31:0] : 32'd0;
  assign sgnj_s_src_a_sign  = sgnj_s_is ? req_i.src_a[31] : 1'b0;
  assign sgnj_s_src_b_sign  = sgnj_s_is ? req_i.src_b[31] : 1'b0;
  assign sgnj_s_result_sign = sgnj_s_is ? resp_o.result[31] : 1'b0;

  assign sgnj_d_is          = dbg_is_d;
  assign sgnj_d_src_a_d     = sgnj_d_is ? req_i.src_a : 64'd0;
  assign sgnj_d_src_b_d     = sgnj_d_is ? req_i.src_b : 64'd0;
  assign sgnj_d_result_d    = sgnj_d_is ? resp_o.result : 64'd0;
  assign sgnj_d_src_a_sign  = sgnj_d_is ? req_i.src_a[63] : 1'b0;
  assign sgnj_d_src_b_sign  = sgnj_d_is ? req_i.src_b[63] : 1'b0;
  assign sgnj_d_result_sign = sgnj_d_is ? resp_o.result[63] : 1'b0;

  always @* begin
    dbg_d_src_a_real  = dbg_is_d ? $bitstoreal(req_i.src_a) : 0.0;
    dbg_d_src_b_real  = dbg_is_d ? $bitstoreal(req_i.src_b) : 0.0;
    dbg_d_result_real = dbg_is_d ? $bitstoreal(resp_o.result) : 0.0;

    sgnj_d_src_a_real  = sgnj_d_is ? $bitstoreal(sgnj_d_src_a_d) : 0.0;
    sgnj_d_src_b_real  = sgnj_d_is ? $bitstoreal(sgnj_d_src_b_d) : 0.0;
    sgnj_d_result_real = sgnj_d_is ? $bitstoreal(sgnj_d_result_d) : 0.0;
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
    input fpu_data_t src_a,
    input fpu_data_t src_b
  );
    req_i = '0;
    req_i.op     = op;
    req_i.rs_fmt = fmt;
    req_i.src_a  = src_a;
    req_i.src_b  = src_b;
    req_i.tag    = 8'hc3;
    req_i.rd     = 5'd11;
    dbg_case_name = name;
    case_id++;
    #1;
  endtask

  task automatic check_sgnj(
    input string       name,
    input fpu_op_e     op,
    input fpu_fmt_e    fmt,
    input fpu_data_t   src_a,
    input fpu_data_t   src_b,
    input fpu_data_t   exp_result,
    input fpu_fflags_t exp_fflags,
    input logic        exp_valid
  );
    apply_req(name, op, fmt, src_a, src_b);

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
    $fsdbDumpfile("tb_fpu_sgnj.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_sgnj);
`endif

    pass_cnt = 0;
    fail_cnt = 0;
    case_id  = 0;
    drive_idle();

    check_sgnj("s_sgnj_pos_mag_neg_sign", FPU_OP_SGNJ, FPU_FMT_S,
               nanbox_s(32'h3f80_0000), nanbox_s(32'h8000_0000),
               nanbox_s(32'hbf80_0000), FFLAGS_NONE, 1'b1);
    check_sgnj("s_sgnjn_pos_mag_neg_sign", FPU_OP_SGNJN, FPU_FMT_S,
               nanbox_s(32'h3f80_0000), nanbox_s(32'h8000_0000),
               nanbox_s(32'h3f80_0000), FFLAGS_NONE, 1'b1);
    check_sgnj("s_sgnjx_neg_xor_neg", FPU_OP_SGNJX, FPU_FMT_S,
               nanbox_s(32'hbf80_0000), nanbox_s(32'h8000_0000),
               nanbox_s(32'h3f80_0000), FFLAGS_NONE, 1'b1);
    check_sgnj("s_sgnjx_pos_xor_neg", FPU_OP_SGNJX, FPU_FMT_S,
               nanbox_s(32'h3f80_0000), nanbox_s(32'h8000_0000),
               nanbox_s(32'hbf80_0000), FFLAGS_NONE, 1'b1);
    check_sgnj("s_sgnj_preserve_nan_payload", FPU_OP_SGNJ, FPU_FMT_S,
               nanbox_s(32'h7fc1_2345), nanbox_s(32'h8000_0000),
               nanbox_s(32'hffc1_2345), FFLAGS_NONE, 1'b1);
    check_sgnj("s_sgnj_bad_box_still_bitwise", FPU_OP_SGNJ, FPU_FMT_S,
               64'h0000_0000_3f80_0000, nanbox_s(32'h8000_0000),
               nanbox_s(32'hbf80_0000), FFLAGS_NONE, 1'b1);

    check_sgnj("d_sgnj_pos_mag_neg_sign", FPU_OP_SGNJ, FPU_FMT_D,
               64'h3ff0_0000_0000_0000, 64'h8000_0000_0000_0000,
               64'hbff0_0000_0000_0000, FFLAGS_NONE, 1'b1);
    check_sgnj("d_sgnjn_pos_mag_neg_sign", FPU_OP_SGNJN, FPU_FMT_D,
               64'h3ff0_0000_0000_0000, 64'h8000_0000_0000_0000,
               64'h3ff0_0000_0000_0000, FFLAGS_NONE, 1'b1);
    check_sgnj("d_sgnjx_neg_xor_neg", FPU_OP_SGNJX, FPU_FMT_D,
               64'hbff0_0000_0000_0000, 64'h8000_0000_0000_0000,
               64'h3ff0_0000_0000_0000, FFLAGS_NONE, 1'b1);
    check_sgnj("d_sgnj_preserve_nan_payload", FPU_OP_SGNJ, FPU_FMT_D,
               64'h7ff8_1234_5678_9abc, 64'h8000_0000_0000_0000,
               64'hfff8_1234_5678_9abc, FFLAGS_NONE, 1'b1);

    check_sgnj("sgnj_bad_op_invalid", FPU_OP_EQ, FPU_FMT_S,
               nanbox_s(32'h3f80_0000), nanbox_s(32'h8000_0000),
               64'd0, FFLAGS_NONE, 1'b0);
    check_sgnj("sgnj_bad_fmt_invalid", FPU_OP_SGNJ, fpu_fmt_e'(2'b10),
               nanbox_s(32'h3f80_0000), nanbox_s(32'h8000_0000),
               64'd0, FFLAGS_NONE, 1'b0);

    $display("tb_fpu_sgnj summary: pass=%0d fail=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_sgnj failed");
    end

    $finish;
  end

endmodule : tb_fpu_sgnj
