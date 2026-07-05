`timescale 1ns/1ps

module tb_fpu_compare;
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

  logic        dbg_is_compare_unit_op;
  logic        dbg_is_compare;
  logic        dbg_is_minmax;
  logic        dbg_is_class;
  logic        dbg_is_eq;
  logic        dbg_is_lt;
  logic        dbg_is_le;
  logic        dbg_is_min;
  logic        dbg_is_max;
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
  logic        dbg_cmp_result_bit;
  logic [9:0]  dbg_class_bits;
  logic [4:0]  dbg_fflags;

  logic        cmp_s_is;
  logic [31:0] cmp_s_src_a_s;
  logic [31:0] cmp_s_src_b_s;
  logic        cmp_s_result_bool;
  fpu_fflags_t cmp_s_fflags;

  logic        cmp_d_is;
  logic [63:0] cmp_d_src_a_d;
  logic [63:0] cmp_d_src_b_d;
  real         cmp_d_src_a_real;
  real         cmp_d_src_b_real;
  logic        cmp_d_result_bool;
  fpu_fflags_t cmp_d_fflags;

  logic        minmax_s_is;
  logic [31:0] minmax_s_src_a_s;
  logic [31:0] minmax_s_src_b_s;
  logic [31:0] minmax_s_result_s;
  fpu_fflags_t minmax_s_fflags;

  logic        minmax_d_is;
  logic [63:0] minmax_d_src_a_d;
  logic [63:0] minmax_d_src_b_d;
  logic [63:0] minmax_d_result_d;
  real         minmax_d_src_a_real;
  real         minmax_d_src_b_real;
  real         minmax_d_result_real;
  fpu_fflags_t minmax_d_fflags;

  logic        class_s_is;
  logic [31:0] class_s_src_s;
  logic [9:0]  class_s_result;
  fpu_fflags_t class_s_fflags;

  logic        class_d_is;
  logic [63:0] class_d_src_d;
  real         class_d_src_real;
  logic [9:0]  class_d_result;
  fpu_fflags_t class_d_fflags;

  fpu_compare_unit dut (
    .req_i     (req_i),
    .resp_o    (resp_o),
    .valid_op_o(valid_op_o)
  );

  function automatic fpu_data_t nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
  endfunction

  assign dbg_is_compare = (req_i.op == FPU_OP_EQ) ||
                          (req_i.op == FPU_OP_LT) ||
                          (req_i.op == FPU_OP_LE);
  assign dbg_is_minmax  = (req_i.op == FPU_OP_MIN) ||
                          (req_i.op == FPU_OP_MAX);
  assign dbg_is_class   = (req_i.op == FPU_OP_CLASS);
  assign dbg_is_eq      = (req_i.op == FPU_OP_EQ);
  assign dbg_is_lt      = (req_i.op == FPU_OP_LT);
  assign dbg_is_le      = (req_i.op == FPU_OP_LE);
  assign dbg_is_min     = (req_i.op == FPU_OP_MIN);
  assign dbg_is_max     = (req_i.op == FPU_OP_MAX);
  assign dbg_is_compare_unit_op = dbg_is_compare || dbg_is_minmax ||
                                  dbg_is_class;
  assign dbg_is_s       = dbg_is_compare_unit_op && (req_i.rs_fmt == FPU_FMT_S);
  assign dbg_is_d       = dbg_is_compare_unit_op && (req_i.rs_fmt == FPU_FMT_D);
  assign dbg_src_a      = dbg_is_compare_unit_op ? req_i.src_a : 64'd0;
  assign dbg_src_b      = dbg_is_compare_unit_op ? req_i.src_b : 64'd0;
  assign dbg_result     = dbg_is_compare_unit_op ? resp_o.result : 64'd0;
  assign dbg_src_a_hi32  = dbg_is_compare_unit_op ? req_i.src_a[63:32] : 32'd0;
  assign dbg_src_a_lo32  = dbg_is_compare_unit_op ? req_i.src_a[31:0]  : 32'd0;
  assign dbg_src_b_hi32  = dbg_is_compare_unit_op ? req_i.src_b[63:32] : 32'd0;
  assign dbg_src_b_lo32  = dbg_is_compare_unit_op ? req_i.src_b[31:0]  : 32'd0;
  assign dbg_result_hi32 = dbg_is_compare_unit_op ? resp_o.result[63:32] : 32'd0;
  assign dbg_result_lo32 = dbg_is_compare_unit_op ? resp_o.result[31:0]  : 32'd0;
  assign dbg_s_src_a    = dbg_is_s ? req_i.src_a[31:0] : 32'd0;
  assign dbg_s_src_b    = dbg_is_s ? req_i.src_b[31:0] : 32'd0;
  assign dbg_s_result   = dbg_is_s ? resp_o.result[31:0] : 32'd0;
  assign dbg_d_src_a    = dbg_is_d ? req_i.src_a : 64'd0;
  assign dbg_d_src_b    = dbg_is_d ? req_i.src_b : 64'd0;
  assign dbg_d_result   = dbg_is_d ? resp_o.result : 64'd0;
  assign dbg_cmp_result_bit = dbg_is_compare ? resp_o.result[0] : 1'b0;
  assign dbg_class_bits = dbg_is_class ? resp_o.result[9:0] : 10'd0;
  assign dbg_fflags     = dbg_is_compare_unit_op ? resp_o.fflags : 5'd0;

  assign cmp_s_is          = dbg_is_compare && (req_i.rs_fmt == FPU_FMT_S);
  assign cmp_s_src_a_s     = cmp_s_is ? req_i.src_a[31:0] : 32'd0;
  assign cmp_s_src_b_s     = cmp_s_is ? req_i.src_b[31:0] : 32'd0;
  assign cmp_s_result_bool = cmp_s_is ? resp_o.result[0] : 1'b0;
  assign cmp_s_fflags      = cmp_s_is ? resp_o.fflags : '0;

  assign cmp_d_is          = dbg_is_compare && (req_i.rs_fmt == FPU_FMT_D);
  assign cmp_d_src_a_d     = cmp_d_is ? req_i.src_a : 64'd0;
  assign cmp_d_src_b_d     = cmp_d_is ? req_i.src_b : 64'd0;
  assign cmp_d_result_bool = cmp_d_is ? resp_o.result[0] : 1'b0;
  assign cmp_d_fflags      = cmp_d_is ? resp_o.fflags : '0;

  assign minmax_s_is       = dbg_is_minmax && (req_i.rs_fmt == FPU_FMT_S);
  assign minmax_s_src_a_s  = minmax_s_is ? req_i.src_a[31:0] : 32'd0;
  assign minmax_s_src_b_s  = minmax_s_is ? req_i.src_b[31:0] : 32'd0;
  assign minmax_s_result_s = minmax_s_is ? resp_o.result[31:0] : 32'd0;
  assign minmax_s_fflags   = minmax_s_is ? resp_o.fflags : '0;

  assign minmax_d_is       = dbg_is_minmax && (req_i.rs_fmt == FPU_FMT_D);
  assign minmax_d_src_a_d  = minmax_d_is ? req_i.src_a : 64'd0;
  assign minmax_d_src_b_d  = minmax_d_is ? req_i.src_b : 64'd0;
  assign minmax_d_result_d = minmax_d_is ? resp_o.result : 64'd0;
  assign minmax_d_fflags   = minmax_d_is ? resp_o.fflags : '0;

  assign class_s_is        = dbg_is_class && (req_i.rs_fmt == FPU_FMT_S);
  assign class_s_src_s     = class_s_is ? req_i.src_a[31:0] : 32'd0;
  assign class_s_result    = class_s_is ? resp_o.result[9:0] : 10'd0;
  assign class_s_fflags    = class_s_is ? resp_o.fflags : '0;

  assign class_d_is        = dbg_is_class && (req_i.rs_fmt == FPU_FMT_D);
  assign class_d_src_d     = class_d_is ? req_i.src_a : 64'd0;
  assign class_d_result    = class_d_is ? resp_o.result[9:0] : 10'd0;
  assign class_d_fflags    = class_d_is ? resp_o.fflags : '0;

  always @* begin
    dbg_d_src_a_real  = dbg_is_d ? $bitstoreal(req_i.src_a) : 0.0;
    dbg_d_src_b_real  = dbg_is_d ? $bitstoreal(req_i.src_b) : 0.0;
    dbg_d_result_real = (dbg_is_d && dbg_is_minmax) ? $bitstoreal(resp_o.result) : 0.0;

    cmp_d_src_a_real = cmp_d_is ? $bitstoreal(cmp_d_src_a_d) : 0.0;
    cmp_d_src_b_real = cmp_d_is ? $bitstoreal(cmp_d_src_b_d) : 0.0;

    minmax_d_src_a_real  = minmax_d_is ? $bitstoreal(minmax_d_src_a_d) : 0.0;
    minmax_d_src_b_real  = minmax_d_is ? $bitstoreal(minmax_d_src_b_d) : 0.0;
    minmax_d_result_real = minmax_d_is ? $bitstoreal(minmax_d_result_d) : 0.0;

    class_d_src_real = class_d_is ? $bitstoreal(class_d_src_d) : 0.0;
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
    req_i.op      = op;
    req_i.rs_fmt  = fmt;
    req_i.dst_fmt = fmt;
    req_i.src_a   = src_a;
    req_i.src_b   = src_b;
    req_i.tag     = 8'h3c;
    req_i.rd      = 5'd13;
    dbg_case_name = name;
    case_id++;
    #1;
  endtask

  task automatic check_result(
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

  task automatic check_class(
    input string       name,
    input fpu_fmt_e    fmt,
    input fpu_data_t   src_a,
    input logic [9:0]  exp_class
  );
    check_result(name, FPU_OP_CLASS, fmt, src_a, 64'd0,
                 {54'd0, exp_class}, FFLAGS_NONE, 1'b1);
  endtask

  initial begin
`ifdef DUMP_FSDB
    $fsdbDumpfile("tb_fpu_compare.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_compare);
`endif

    pass_cnt = 0;
    fail_cnt = 0;
    case_id  = 0;
    drive_idle();

    check_result("s_eq_pos_zero_neg_zero", FPU_OP_EQ, FPU_FMT_S,
                 nanbox_s(32'h0000_0000), nanbox_s(32'h8000_0000),
                 64'd1, FFLAGS_NONE, 1'b1);
    check_result("s_eq_one_one", FPU_OP_EQ, FPU_FMT_S,
                 nanbox_s(32'h3f80_0000), nanbox_s(32'h3f80_0000),
                 64'd1, FFLAGS_NONE, 1'b1);
    check_result("s_eq_one_two", FPU_OP_EQ, FPU_FMT_S,
                 nanbox_s(32'h3f80_0000), nanbox_s(32'h4000_0000),
                 64'd0, FFLAGS_NONE, 1'b1);
    check_result("s_eq_qnan_no_nv", FPU_OP_EQ, FPU_FMT_S,
                 nanbox_s(32'h7fc0_0001), nanbox_s(32'h3f80_0000),
                 64'd0, FFLAGS_NONE, 1'b1);
    check_result("s_eq_snan_nv", FPU_OP_EQ, FPU_FMT_S,
                 nanbox_s(32'h7fa0_0001), nanbox_s(32'h3f80_0000),
                 64'd0, FFLAGS_NV, 1'b1);
    check_result("s_lt_neg_one_pos_one", FPU_OP_LT, FPU_FMT_S,
                 nanbox_s(32'hbf80_0000), nanbox_s(32'h3f80_0000),
                 64'd1, FFLAGS_NONE, 1'b1);
    check_result("s_lt_pos_one_neg_one", FPU_OP_LT, FPU_FMT_S,
                 nanbox_s(32'h3f80_0000), nanbox_s(32'hbf80_0000),
                 64'd0, FFLAGS_NONE, 1'b1);
    check_result("s_le_equal", FPU_OP_LE, FPU_FMT_S,
                 nanbox_s(32'h3f80_0000), nanbox_s(32'h3f80_0000),
                 64'd1, FFLAGS_NONE, 1'b1);
    check_result("s_lt_qnan_nv", FPU_OP_LT, FPU_FMT_S,
                 nanbox_s(32'h7fc0_0001), nanbox_s(32'h3f80_0000),
                 64'd0, FFLAGS_NV, 1'b1);
    check_result("s_le_qnan_nv", FPU_OP_LE, FPU_FMT_S,
                 nanbox_s(32'h3f80_0000), nanbox_s(32'h7fc0_0001),
                 64'd0, FFLAGS_NV, 1'b1);

    check_result("s_min_neg_zero_pos_zero", FPU_OP_MIN, FPU_FMT_S,
                 nanbox_s(32'h8000_0000), nanbox_s(32'h0000_0000),
                 nanbox_s(32'h8000_0000), FFLAGS_NONE, 1'b1);
    check_result("s_max_neg_zero_pos_zero", FPU_OP_MAX, FPU_FMT_S,
                 nanbox_s(32'h8000_0000), nanbox_s(32'h0000_0000),
                 nanbox_s(32'h0000_0000), FFLAGS_NONE, 1'b1);
    check_result("s_min_qnan_number", FPU_OP_MIN, FPU_FMT_S,
                 nanbox_s(32'h7fc0_0001), nanbox_s(32'h4000_0000),
                 nanbox_s(32'h4000_0000), FFLAGS_NONE, 1'b1);
    check_result("s_max_number_snan", FPU_OP_MAX, FPU_FMT_S,
                 nanbox_s(32'h4000_0000), nanbox_s(32'h7fa0_0001),
                 nanbox_s(32'h4000_0000), FFLAGS_NV, 1'b1);
    check_result("s_min_both_qnan", FPU_OP_MIN, FPU_FMT_S,
                 nanbox_s(32'h7fc0_0001), nanbox_s(32'h7fc0_0002),
                 nanbox_s(32'h7fc0_0000), FFLAGS_NONE, 1'b1);
    check_result("s_max_bad_box_number", FPU_OP_MAX, FPU_FMT_S,
                 64'h0000_0000_3f80_0000, nanbox_s(32'h4000_0000),
                 nanbox_s(32'h4000_0000), FFLAGS_NONE, 1'b1);

    check_result("d_lt_neg_two_neg_one", FPU_OP_LT, FPU_FMT_D,
                 64'hc000_0000_0000_0000, 64'hbff0_0000_0000_0000,
                 64'd1, FFLAGS_NONE, 1'b1);
    check_result("d_le_pos_inf_pos_inf", FPU_OP_LE, FPU_FMT_D,
                 64'h7ff0_0000_0000_0000, 64'h7ff0_0000_0000_0000,
                 64'd1, FFLAGS_NONE, 1'b1);
    check_result("d_min_neg_three_pos_two", FPU_OP_MIN, FPU_FMT_D,
                 64'hc008_0000_0000_0000, 64'h4000_0000_0000_0000,
                 64'hc008_0000_0000_0000, FFLAGS_NONE, 1'b1);
    check_result("d_max_inf_finite", FPU_OP_MAX, FPU_FMT_D,
                 64'h7ff0_0000_0000_0000, 64'h3ff0_0000_0000_0000,
                 64'h7ff0_0000_0000_0000, FFLAGS_NONE, 1'b1);
    check_result("d_min_both_snan_nv", FPU_OP_MIN, FPU_FMT_D,
                 64'h7ff0_0000_0000_0001, 64'h7ff0_0000_0000_0002,
                 64'h7ff8_0000_0000_0000, FFLAGS_NV, 1'b1);

    check_class("s_class_neg_inf", FPU_FMT_S,
                nanbox_s(32'hff80_0000), 10'b00_0000_0001);
    check_class("s_class_neg_norm", FPU_FMT_S,
                nanbox_s(32'hbf80_0000), 10'b00_0000_0010);
    check_class("s_class_neg_sub", FPU_FMT_S,
                nanbox_s(32'h8000_0001), 10'b00_0000_0100);
    check_class("s_class_neg_zero", FPU_FMT_S,
                nanbox_s(32'h8000_0000), 10'b00_0000_1000);
    check_class("s_class_pos_zero", FPU_FMT_S,
                nanbox_s(32'h0000_0000), 10'b00_0001_0000);
    check_class("s_class_pos_sub", FPU_FMT_S,
                nanbox_s(32'h0000_0001), 10'b00_0010_0000);
    check_class("s_class_pos_norm", FPU_FMT_S,
                nanbox_s(32'h3f80_0000), 10'b00_0100_0000);
    check_class("s_class_pos_inf", FPU_FMT_S,
                nanbox_s(32'h7f80_0000), 10'b00_1000_0000);
    check_class("s_class_snan", FPU_FMT_S,
                nanbox_s(32'h7fa0_0001), 10'b01_0000_0000);
    check_class("s_class_qnan", FPU_FMT_S,
                nanbox_s(32'h7fc0_0001), 10'b10_0000_0000);
    check_class("s_class_bad_box_qnan", FPU_FMT_S,
                64'h0000_0000_3f80_0000, 10'b10_0000_0000);
    check_class("d_class_qnan", FPU_FMT_D,
                64'h7ff8_0000_0000_0001, 10'b10_0000_0000);

    check_result("compare_bad_op_invalid", FPU_OP_ADD, FPU_FMT_S,
                 nanbox_s(32'h3f80_0000), nanbox_s(32'h3f80_0000),
                 64'd0, FFLAGS_NONE, 1'b0);
    check_result("compare_bad_fmt_invalid", FPU_OP_EQ, fpu_fmt_e'(2'b10),
                 nanbox_s(32'h3f80_0000), nanbox_s(32'h3f80_0000),
                 64'd0, FFLAGS_NONE, 1'b0);

    $display("tb_fpu_compare summary: pass=%0d fail=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_compare failed");
    end

    $finish;
  end

endmodule : tb_fpu_compare
