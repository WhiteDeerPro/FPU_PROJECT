`timescale 1ns/1ps

module tb_fpu_add_pipe;
  import fpu_pkg::*;

  localparam fpu_fflags_t FFLAGS_NONE = 5'b0_0000;
  localparam fpu_fflags_t FFLAGS_NX   = 5'b0_0001;
  localparam fpu_fflags_t FFLAGS_UFNX = 5'b0_0011;
  localparam fpu_fflags_t FFLAGS_OFNX = 5'b0_0101;
  localparam fpu_fflags_t FFLAGS_NV   = 5'b1_0000;

  logic      clk_i;
  logic      rst_ni;
  logic      valid_i;
  logic      valid_o;
  fpu_req_t  req_i;
  fpu_resp_t resp_o;
  logic      valid_op_o;

  int unsigned pass_cnt;
  int unsigned fail_cnt;
  int unsigned case_id;
  string       dbg_case_name;

  logic        dbg_is_addsub;
  logic        dbg_is_add;
  logic        dbg_is_sub;
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
  logic [4:0]  dbg_fflags;
  logic [1:0]  dbg_fmt;
  logic [2:0]  dbg_rm;
  logic        dbg_rm_rne;

  logic        dbg_lhs_sign;
  logic        dbg_rhs_sign;
  logic [10:0] dbg_big_exp;
  logic [10:0] dbg_small_exp;
  logic [10:0] dbg_exp_diff;
  logic [63:0] dbg_big_sig;
  logic [63:0] dbg_small_sig_shifted;
  logic [64:0] dbg_add_sig_sum;
  logic [63:0] dbg_sub_sig_diff;
  logic [6:0]  dbg_sub_lop_pos;
  logic        dbg_sub_is_zero;
  logic [10:0] dbg_finite_exp;
  logic [63:0] dbg_finite_sig;
  logic        dbg_finite_sign;
  logic        dbg_guard;
  logic        dbg_round;
  logic        dbg_sticky;
  logic        dbg_lsb;
  logic        dbg_inc;
  logic        dbg_inexact;

  fpu_add_unit_pipe dut (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (valid_i),
    .req_i     (req_i),
    .valid_o   (valid_o),
    .resp_o    (resp_o),
    .valid_op_o(valid_op_o)
  );

  always #5 clk_i = ~clk_i;

  function automatic fpu_data_t nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
  endfunction

  assign dbg_is_addsub = (req_i.op == FPU_OP_ADD) || (req_i.op == FPU_OP_SUB);
  assign dbg_is_add    = (req_i.op == FPU_OP_ADD);
  assign dbg_is_sub    = (req_i.op == FPU_OP_SUB);
  assign dbg_is_s      = dbg_is_addsub && (req_i.rs_fmt == FPU_FMT_S);
  assign dbg_is_d      = dbg_is_addsub && (req_i.rs_fmt == FPU_FMT_D);
  assign dbg_src_a     = dbg_is_addsub ? req_i.src_a : 64'd0;
  assign dbg_src_b     = dbg_is_addsub ? req_i.src_b : 64'd0;
  assign dbg_result    = dbg_is_addsub ? resp_o.result : 64'd0;
  assign dbg_src_a_hi32   = dbg_is_addsub ? req_i.src_a[63:32] : 32'd0;
  assign dbg_src_a_lo32   = dbg_is_addsub ? req_i.src_a[31:0]  : 32'd0;
  assign dbg_src_b_hi32   = dbg_is_addsub ? req_i.src_b[63:32] : 32'd0;
  assign dbg_src_b_lo32   = dbg_is_addsub ? req_i.src_b[31:0]  : 32'd0;
  assign dbg_result_hi32  = dbg_is_addsub ? resp_o.result[63:32] : 32'd0;
  assign dbg_result_lo32  = dbg_is_addsub ? resp_o.result[31:0]  : 32'd0;
  assign dbg_s_src_a      = dbg_is_s ? req_i.src_a[31:0] : 32'd0;
  assign dbg_s_src_b      = dbg_is_s ? req_i.src_b[31:0] : 32'd0;
  assign dbg_s_result     = dbg_is_s ? resp_o.result[31:0] : 32'd0;
  assign dbg_d_src_a      = dbg_is_d ? req_i.src_a : 64'd0;
  assign dbg_d_src_b      = dbg_is_d ? req_i.src_b : 64'd0;
  assign dbg_d_result     = dbg_is_d ? resp_o.result : 64'd0;
  assign dbg_fflags    = dbg_is_addsub ? resp_o.fflags : 5'd0;
  assign dbg_fmt       = dbg_is_addsub ? req_i.rs_fmt : 2'd0;
  assign dbg_rm        = dbg_is_addsub ? req_i.rm : 3'd0;
  assign dbg_rm_rne    = dbg_is_addsub && (req_i.rm == FPU_RM_RNE);

  assign dbg_lhs_sign          = 1'b0;
  assign dbg_rhs_sign          = 1'b0;
  assign dbg_big_exp           = 11'd0;
  assign dbg_small_exp         = 11'd0;
  assign dbg_exp_diff          = 11'd0;
  assign dbg_big_sig           = 64'd0;
  assign dbg_small_sig_shifted = dbg_is_d ? {11'd0, dut.s1_small_shifted_d} : 64'd0;
  assign dbg_add_sig_sum       = dbg_is_d ? {11'd0, dut.s1_add_sum_d} : 65'd0;
  assign dbg_sub_sig_diff      = dbg_is_d ? {11'd0, dut.s1_sub_diff_d} : 64'd0;
  assign dbg_sub_lop_pos       = 7'd0;
  assign dbg_sub_is_zero       = 1'b0;
  assign dbg_finite_exp        = 11'd0;
  assign dbg_finite_sig        = 64'd0;
  assign dbg_finite_sign       = 1'b0;
  assign dbg_guard             = 1'b0;
  assign dbg_round             = 1'b0;
  assign dbg_sticky            = 1'b0;
  assign dbg_lsb               = 1'b0;
  assign dbg_inc               = 1'b0;
  assign dbg_inexact           = 1'b0;

  always @* begin
    dbg_d_src_a_real  = dbg_is_d ? $bitstoreal(req_i.src_a) : 0.0;
    dbg_d_src_b_real  = dbg_is_d ? $bitstoreal(req_i.src_b) : 0.0;
    dbg_d_result_real = dbg_is_d ? $bitstoreal(resp_o.result) : 0.0;
  end

  task automatic drive_idle;
    @(posedge clk_i);
    #1;
    req_i = '0;
    valid_i = 1'b0;
    dbg_case_name = "idle";
  endtask

  task automatic apply_req(
    input string     name,
    input fpu_op_e   op,
    input fpu_fmt_e  fmt,
    input fpu_rm_e   rm,
    input fpu_data_t src_a,
    input fpu_data_t src_b
  );
    @(posedge clk_i);
    #1;
    req_i = '0;
    req_i.op      = op;
    req_i.rs_fmt  = fmt;
    req_i.dst_fmt = fmt;
    req_i.rm      = rm;
    req_i.src_a   = src_a;
    req_i.src_b   = src_b;
    req_i.tag     = 8'ha5;
    req_i.rd      = 5'd9;
    valid_i       = 1'b1;
    dbg_case_name = name;
    case_id++;
    @(posedge clk_i);
    #1;
    valid_i = 1'b0;
    req_i = '0;
    @(posedge clk_i);
    #2;
  endtask

  task automatic check_addsub(
    input string       name,
    input fpu_op_e     op,
    input fpu_fmt_e    fmt,
    input fpu_rm_e     rm,
    input fpu_data_t   src_a,
    input fpu_data_t   src_b,
    input fpu_data_t   exp_result,
    input fpu_fflags_t exp_fflags,
    input logic        exp_valid
  );
    apply_req(name, op, fmt, rm, src_a, src_b);

    if ((valid_o !== 1'b1) ||
        (valid_op_o !== exp_valid) ||
        (resp_o.result !== exp_result) ||
        (resp_o.fflags !== exp_fflags) ||
        (resp_o.tag !== 8'ha5) ||
        (resp_o.rd !== 5'd9)) begin
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
    $fsdbDumpfile("tb_fpu_add_pipe.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_add_pipe);
`endif

    clk_i = 1'b0;
    rst_ni = 1'b0;
    valid_i = 1'b0;
    req_i = '0;
    pass_cnt = 0;
    fail_cnt = 0;
    case_id  = 0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;
    drive_idle();

    check_addsub("s_add_1p0_1p0", FPU_OP_ADD, FPU_FMT_S, FPU_RM_RNE,
                 nanbox_s(32'h3f80_0000), nanbox_s(32'h3f80_0000),
                 nanbox_s(32'h4000_0000), FFLAGS_NONE, 1'b1);
    check_addsub("s_sub_1p0_0p5", FPU_OP_SUB, FPU_FMT_S, FPU_RM_RNE,
                 nanbox_s(32'h3f80_0000), nanbox_s(32'h3f00_0000),
                 nanbox_s(32'h3f00_0000), FFLAGS_NONE, 1'b1);
    check_addsub("s_sub_cancel_rne_pos_zero", FPU_OP_SUB, FPU_FMT_S, FPU_RM_RNE,
                 nanbox_s(32'h3f80_0000), nanbox_s(32'h3f80_0000),
                 nanbox_s(32'h0000_0000), FFLAGS_NONE, 1'b1);
    check_addsub("s_sub_cancel_rdn_neg_zero", FPU_OP_SUB, FPU_FMT_S, FPU_RM_RDN,
                 nanbox_s(32'h3f80_0000), nanbox_s(32'h3f80_0000),
                 nanbox_s(32'h8000_0000), FFLAGS_NONE, 1'b1);
    check_addsub("s_add_neg_zero_neg_zero", FPU_OP_ADD, FPU_FMT_S, FPU_RM_RNE,
                 nanbox_s(32'h8000_0000), nanbox_s(32'h8000_0000),
                 nanbox_s(32'h8000_0000), FFLAGS_NONE, 1'b1);
    check_addsub("s_add_pos_zero_neg_zero_rdn", FPU_OP_ADD, FPU_FMT_S, FPU_RM_RDN,
                 nanbox_s(32'h0000_0000), nanbox_s(32'h8000_0000),
                 nanbox_s(32'h8000_0000), FFLAGS_NONE, 1'b1);
    check_addsub("s_add_half_ulp_tie_even", FPU_OP_ADD, FPU_FMT_S, FPU_RM_RNE,
                 nanbox_s(32'h3f80_0000), nanbox_s(32'h3380_0000),
                 nanbox_s(32'h3f80_0000), FFLAGS_NX, 1'b1);
    check_addsub("s_add_1p5_ulp_tie_even", FPU_OP_ADD, FPU_FMT_S, FPU_RM_RNE,
                 nanbox_s(32'h3f80_0000), nanbox_s(32'h3440_0000),
                 nanbox_s(32'h3f80_0002), FFLAGS_NX, 1'b1);
    check_addsub("s_add_one_ulp_exact", FPU_OP_ADD, FPU_FMT_S, FPU_RM_RNE,
                 nanbox_s(32'h3f80_0000), nanbox_s(32'h3400_0000),
                 nanbox_s(32'h3f80_0001), FFLAGS_NONE, 1'b1);
    check_addsub("s_add_smax_smax_rne", FPU_OP_ADD, FPU_FMT_S, FPU_RM_RNE,
                 nanbox_s(32'h7f7f_ffff), nanbox_s(32'h7f7f_ffff),
                 nanbox_s(32'h7f80_0000), FFLAGS_OFNX, 1'b1);
    check_addsub("s_add_smax_smax_rdn", FPU_OP_ADD, FPU_FMT_S, FPU_RM_RDN,
                 nanbox_s(32'h7f7f_ffff), nanbox_s(32'h7f7f_ffff),
                 nanbox_s(32'h7f7f_ffff), FFLAGS_OFNX, 1'b1);
    check_addsub("s_add_neg_smax_neg_smax_rup", FPU_OP_ADD, FPU_FMT_S, FPU_RM_RUP,
                 nanbox_s(32'hff7f_ffff), nanbox_s(32'hff7f_ffff),
                 nanbox_s(32'hff7f_ffff), FFLAGS_OFNX, 1'b1);
    check_addsub("s_add_inf_finite", FPU_OP_ADD, FPU_FMT_S, FPU_RM_RNE,
                 nanbox_s(32'h7f80_0000), nanbox_s(32'h3f80_0000),
                 nanbox_s(32'h7f80_0000), FFLAGS_NONE, 1'b1);
    check_addsub("s_add_inf_neg_inf_nv", FPU_OP_ADD, FPU_FMT_S, FPU_RM_RNE,
                 nanbox_s(32'h7f80_0000), nanbox_s(32'hff80_0000),
                 nanbox_s(32'h7fc0_0000), FFLAGS_NV, 1'b1);
    check_addsub("s_add_qnan", FPU_OP_ADD, FPU_FMT_S, FPU_RM_RNE,
                 nanbox_s(32'h7fc0_1234), nanbox_s(32'h3f80_0000),
                 nanbox_s(32'h7fc0_0000), FFLAGS_NONE, 1'b1);
    check_addsub("s_add_bad_nanbox", FPU_OP_ADD, FPU_FMT_S, FPU_RM_RNE,
                 64'h0000_0000_3f80_0000, nanbox_s(32'h3f80_0000),
                 nanbox_s(32'h7fc0_0000), FFLAGS_NONE, 1'b1);
    check_addsub("s_add_min_norm_minus_max_sub", FPU_OP_ADD, FPU_FMT_S, FPU_RM_RNE,
                 nanbox_s(32'h0080_0000), nanbox_s(32'h807f_ffff),
                 nanbox_s(32'h0000_0001), FFLAGS_NONE, 1'b1);

    check_addsub("d_add_1p0_1p0", FPU_OP_ADD, FPU_FMT_D, FPU_RM_RNE,
                 64'h3ff0_0000_0000_0000, 64'h3ff0_0000_0000_0000,
                 64'h4000_0000_0000_0000, FFLAGS_NONE, 1'b1);
    check_addsub("d_sub_1p0_0p5", FPU_OP_SUB, FPU_FMT_D, FPU_RM_RNE,
                 64'h3ff0_0000_0000_0000, 64'h3fe0_0000_0000_0000,
                 64'h3fe0_0000_0000_0000, FFLAGS_NONE, 1'b1);
    check_addsub("d_add_half_ulp_tie_even", FPU_OP_ADD, FPU_FMT_D, FPU_RM_RNE,
                 64'h3ff0_0000_0000_0000, 64'h3ca0_0000_0000_0000,
                 64'h3ff0_0000_0000_0000, FFLAGS_NX, 1'b1);
    check_addsub("d_add_1p5_ulp_tie_even", FPU_OP_ADD, FPU_FMT_D, FPU_RM_RNE,
                 64'h3ff0_0000_0000_0000, 64'h3cb8_0000_0000_0000,
                 64'h3ff0_0000_0000_0002, FFLAGS_NX, 1'b1);
    check_addsub("d_add_dmax_dmax_rne", FPU_OP_ADD, FPU_FMT_D, FPU_RM_RNE,
                 64'h7fef_ffff_ffff_ffff, 64'h7fef_ffff_ffff_ffff,
                 64'h7ff0_0000_0000_0000, FFLAGS_OFNX, 1'b1);
    check_addsub("d_add_dmax_dmax_rdn", FPU_OP_ADD, FPU_FMT_D, FPU_RM_RDN,
                 64'h7fef_ffff_ffff_ffff, 64'h7fef_ffff_ffff_ffff,
                 64'h7fef_ffff_ffff_ffff, FFLAGS_OFNX, 1'b1);
    check_addsub("d_add_neg_dmax_neg_dmax_rup", FPU_OP_ADD, FPU_FMT_D, FPU_RM_RUP,
                 64'hffef_ffff_ffff_ffff, 64'hffef_ffff_ffff_ffff,
                 64'hffef_ffff_ffff_ffff, FFLAGS_OFNX, 1'b1);
    check_addsub("d_add_inf_neg_inf_nv", FPU_OP_ADD, FPU_FMT_D, FPU_RM_RNE,
                 64'h7ff0_0000_0000_0000, 64'hfff0_0000_0000_0000,
                 64'h7ff8_0000_0000_0000, FFLAGS_NV, 1'b1);
    check_addsub("d_add_min_norm_minus_max_sub", FPU_OP_ADD, FPU_FMT_D, FPU_RM_RNE,
                 64'h0010_0000_0000_0000, 64'h800f_ffff_ffff_ffff,
                 64'h0000_0000_0000_0001, FFLAGS_NONE, 1'b1);
    check_addsub("d_add_neg_zero_neg_zero", FPU_OP_ADD, FPU_FMT_D, FPU_RM_RNE,
                 64'h8000_0000_0000_0000, 64'h8000_0000_0000_0000,
                 64'h8000_0000_0000_0000, FFLAGS_NONE, 1'b1);
    check_addsub("d_add_pos_zero_neg_zero_rdn", FPU_OP_ADD, FPU_FMT_D, FPU_RM_RDN,
                 64'h0000_0000_0000_0000, 64'h8000_0000_0000_0000,
                 64'h8000_0000_0000_0000, FFLAGS_NONE, 1'b1);

    check_addsub("add_bad_rm_invalid", FPU_OP_ADD, FPU_FMT_S, fpu_rm_e'(3'b101),
                 nanbox_s(32'h3f80_0000), nanbox_s(32'h3f80_0000),
                 64'd0, FFLAGS_NONE, 1'b0);

    $display("tb_fpu_add_pipe summary: pass=%0d fail=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_add_pipe failed");
    end

    $finish;
  end

endmodule : tb_fpu_add_pipe
