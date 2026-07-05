`timescale 1ns/1ps

module tb_fpu_mult;
  import fpu_pkg::*;

  localparam fpu_fflags_t FFLAGS_NONE = 5'b0_0000;
  localparam fpu_fflags_t FFLAGS_NX   = 5'b0_0001;
  localparam fpu_fflags_t FFLAGS_UFNX = 5'b0_0011;
  localparam fpu_fflags_t FFLAGS_OFNX = 5'b0_0101;
  localparam fpu_fflags_t FFLAGS_NV   = 5'b1_0000;
  localparam int unsigned SIN_SAMPLES_PER_PERIOD = 256;
  localparam int unsigned SIN_PERIODS            = 10;
  localparam int unsigned SIN_TOTAL_SAMPLES      = SIN_SAMPLES_PER_PERIOD * SIN_PERIODS;
  localparam real         TWO_PI                 = 6.28318530717958647692;

  fpu_req_t  req_i;
  fpu_resp_t resp_o;
  logic      valid_op_o;

  int unsigned pass_cnt;
  int unsigned fail_cnt;
  int unsigned case_id;
  int unsigned sin_s_pass_cnt;
  int unsigned sin_s_fail_cnt;
  int unsigned sin_d_pass_cnt;
  int unsigned sin_d_fail_cnt;
  string       dbg_case_name;

  logic        dbg_is_mul;
  logic        dbg_is_s;
  logic        dbg_is_d;
  logic [63:0] dbg_src_a;
  logic [63:0] dbg_src_b;
  logic [63:0] dbg_result;
  logic [31:0] dbg_s_src_a;
  logic [31:0] dbg_s_src_b;
  logic [31:0] dbg_s_result;
  logic [63:0] dbg_d_src_a;
  logic [63:0] dbg_d_src_b;
  logic [63:0] dbg_d_result;
  real         dbg_s_src_a_real;
  real         dbg_s_src_b_real;
  real         dbg_s_result_real;
  real         dbg_d_src_a_real;
  real         dbg_d_src_b_real;
  real         dbg_d_result_real;
  logic [1:0]  dbg_sin_phase;
  int unsigned dbg_sin_sample_idx;
  real         dbg_sin_theta;
  real         dbg_sin_s_value_real;
  real         dbg_sin_s_product_real;
  real         dbg_sin_d_value_real;
  real         dbg_sin_d_product_real;
  logic [31:0] dbg_sin_s_value_bits;
  logic [31:0] dbg_sin_s_product_bits;
  logic [63:0] dbg_sin_d_value_bits;
  logic [63:0] dbg_sin_d_product_bits;
  logic [4:0]  dbg_fflags;
  logic [1:0]  dbg_fmt;
  logic [2:0]  dbg_rm;

  logic        dbg_lhs_sign;
  logic        dbg_rhs_sign;
  logic [10:0] dbg_lhs_exp;
  logic [10:0] dbg_rhs_exp;
  logic [63:0] dbg_lhs_sig;
  logic [63:0] dbg_rhs_sig;
  logic [127:0] dbg_product;
  logic [6:0]  dbg_product_lop_pos;
  logic signed [13:0] dbg_raw_exp;
  logic signed [13:0] dbg_finite_exp;
  logic [63:0] dbg_norm_sig;
  logic [63:0] dbg_finite_sig;
  logic        dbg_guard;
  logic        dbg_round;
  logic        dbg_sticky;
  logic        dbg_lsb;
  logic        dbg_inc;
  logic        dbg_inexact;

  fpu_mult_unit dut (
    .req_i     (req_i),
    .resp_o    (resp_o),
    .valid_op_o(valid_op_o)
  );

  function automatic fpu_data_t nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
  endfunction

  function automatic real pow2_real(input int exponent);
    real value;

    value = 1.0;
    if (exponent >= 0) begin
      for (int idx = 0; idx < exponent; idx++) begin
        value = value * 2.0;
      end
    end else begin
      for (int idx = 0; idx < -exponent; idx++) begin
        value = value / 2.0;
      end
    end

    return value;
  endfunction

  function automatic logic [31:0] real_to_float32_bits(input real value);
    logic        sign;
    real         abs_value;
    real         norm_value;
    int          exponent;
    int          exp_field;
    real         mant_scaled;
    int          mant_floor;
    logic [31:0] mant_floor_u;
    logic [22:0] mant_floor_bits;
    real         mant_rem;
    logic [23:0] mant_round;

    sign      = (value < 0.0);
    abs_value = sign ? -value : value;

    if (abs_value == 0.0) begin
      return {sign, 31'd0};
    end

    norm_value = abs_value;
    exponent   = 0;

    while (norm_value >= 2.0) begin
      norm_value = norm_value / 2.0;
      exponent++;
    end

    while (norm_value < 1.0) begin
      norm_value = norm_value * 2.0;
      exponent--;
    end

    exp_field    = exponent + 127;
    mant_scaled  = (norm_value - 1.0) * 8388608.0;
    mant_floor   = $rtoi(mant_scaled);
    mant_floor_u = mant_floor;
    mant_floor_bits = mant_floor_u[22:0];
    mant_rem     = mant_scaled - real'(mant_floor);
    mant_round   = {1'b0, mant_floor_bits};

    if ((mant_rem > 0.5) ||
        ((mant_rem == 0.5) && mant_round[0])) begin
      mant_round = mant_round + 24'd1;
    end

    if (mant_round[23]) begin
      mant_round = 24'd0;
      exp_field++;
    end

    return {sign, exp_field[7:0], mant_round[22:0]};
  endfunction

  function automatic real float32_bits_to_real(input logic [31:0] bits);
    real magnitude;
    real fraction;
    int  exponent;

    if (bits[30:0] == 31'd0) begin
      return bits[31] ? -0.0 : 0.0;
    end

    if (bits[30:23] == 8'd0) begin
      fraction  = real'(bits[22:0]) / 8388608.0;
      magnitude = fraction * pow2_real(-126);
    end else begin
      exponent  = int'(bits[30:23]) - 127;
      fraction  = 1.0 + (real'(bits[22:0]) / 8388608.0);
      magnitude = fraction * pow2_real(exponent);
    end

    return bits[31] ? -magnitude : magnitude;
  endfunction

  assign dbg_is_mul = (req_i.op == FPU_OP_MUL);
  assign dbg_is_s   = dbg_is_mul && (req_i.rs_fmt == FPU_FMT_S);
  assign dbg_is_d   = dbg_is_mul && (req_i.rs_fmt == FPU_FMT_D);
  assign dbg_src_a  = dbg_is_mul ? req_i.src_a : 64'd0;
  assign dbg_src_b  = dbg_is_mul ? req_i.src_b : 64'd0;
  assign dbg_result = dbg_is_mul ? resp_o.result : 64'd0;
  assign dbg_s_src_a  = dbg_is_s ? req_i.src_a[31:0] : 32'd0;
  assign dbg_s_src_b  = dbg_is_s ? req_i.src_b[31:0] : 32'd0;
  assign dbg_s_result = dbg_is_s ? resp_o.result[31:0] : 32'd0;
  assign dbg_d_src_a  = dbg_is_d ? req_i.src_a : 64'd0;
  assign dbg_d_src_b  = dbg_is_d ? req_i.src_b : 64'd0;
  assign dbg_d_result = dbg_is_d ? resp_o.result : 64'd0;
  assign dbg_fflags   = dbg_is_mul ? resp_o.fflags : 5'd0;
  assign dbg_fmt      = dbg_is_mul ? req_i.rs_fmt : 2'd0;
  assign dbg_rm       = dbg_is_mul ? req_i.rm : 3'd0;

  assign dbg_lhs_sign        = dbg_is_mul ? dut.lhs.sign : 1'b0;
  assign dbg_rhs_sign        = dbg_is_mul ? dut.rhs.sign : 1'b0;
  assign dbg_lhs_exp         = dbg_is_mul ? dut.lhs.exp : 11'd0;
  assign dbg_rhs_exp         = dbg_is_mul ? dut.rhs.exp : 11'd0;
  assign dbg_lhs_sig         = dbg_is_mul ? dut.lhs.sig : 64'd0;
  assign dbg_rhs_sig         = dbg_is_mul ? dut.rhs.sig : 64'd0;
  assign dbg_product         = dbg_is_mul ? dut.product : 128'd0;
  assign dbg_product_lop_pos = dbg_is_mul ? dut.product_lop_pos : 7'd0;
  assign dbg_raw_exp         = dbg_is_mul ? dut.raw_exp : 14'sd0;
  assign dbg_finite_exp      = dbg_is_mul ? dut.finite_exp : 14'sd0;
  assign dbg_norm_sig        = dbg_is_mul ? dut.norm_sig : 64'd0;
  assign dbg_finite_sig      = dbg_is_mul ? dut.finite_sig : 64'd0;
  assign dbg_guard           = dbg_is_mul ? dut.result_grs.guard : 1'b0;
  assign dbg_round           = dbg_is_mul ? dut.result_grs.round : 1'b0;
  assign dbg_sticky          = dbg_is_mul ? dut.result_grs.sticky : 1'b0;
  assign dbg_lsb             = dbg_is_mul ? dut.result_lsb : 1'b0;
  assign dbg_inc             = dbg_is_mul ? dut.result_round_inc : 1'b0;
  assign dbg_inexact         = dbg_is_mul ? dut.result_inexact : 1'b0;

  always @* begin
    dbg_s_src_a_real  = dbg_is_s ? float32_bits_to_real(req_i.src_a[31:0]) : 0.0;
    dbg_s_src_b_real  = dbg_is_s ? float32_bits_to_real(req_i.src_b[31:0]) : 0.0;
    dbg_s_result_real = dbg_is_s ? float32_bits_to_real(resp_o.result[31:0]) : 0.0;
    dbg_d_src_a_real  = dbg_is_d ? $bitstoreal(req_i.src_a) : 0.0;
    dbg_d_src_b_real  = dbg_is_d ? $bitstoreal(req_i.src_b) : 0.0;
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
    input fpu_data_t src_b
  );
    req_i = '0;
    req_i.op      = op;
    req_i.rs_fmt  = fmt;
    req_i.dst_fmt = fmt;
    req_i.rm      = rm;
    req_i.src_a   = src_a;
    req_i.src_b   = src_b;
    req_i.tag     = 8'ha5;
    req_i.rd      = 5'd9;
    dbg_case_name = name;
    case_id++;
    #1;
  endtask

  task automatic check_mul(
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

  task automatic check_sin_sample_s(input int unsigned sample_idx);
    real       theta;
    real       sin_value;
    real       sin_value_s;
    real       product_real;
    logic [31:0] sin_bits;
    logic [31:0] product_bits;

    theta        = (TWO_PI * real'(sample_idx)) / real'(SIN_SAMPLES_PER_PERIOD);
    sin_value    = $sin(theta);
    sin_bits     = real_to_float32_bits(sin_value);
    sin_value_s  = float32_bits_to_real(sin_bits);
    product_real = sin_value_s * sin_value_s;
    product_bits = real_to_float32_bits(product_real);

    apply_req("s_mul_sin_t_sin_t", FPU_OP_MUL, FPU_FMT_S, FPU_RM_RNE,
              nanbox_s(sin_bits), nanbox_s(sin_bits));

    dbg_sin_phase       = 2'd1;
    dbg_sin_sample_idx  = sample_idx;
    dbg_sin_theta        = theta;
    dbg_sin_s_value_real = sin_value_s;
    dbg_sin_s_product_real = float32_bits_to_real(resp_o.result[31:0]);
    dbg_sin_s_value_bits = sin_bits;
    dbg_sin_s_product_bits = resp_o.result[31:0];

    if ((valid_op_o !== 1'b1) ||
        (resp_o.result !== nanbox_s(product_bits)) ||
        (resp_o.fflags[FPU_FFLAG_NV] !== 1'b0) ||
        (resp_o.fflags[FPU_FFLAG_DZ] !== 1'b0) ||
        (resp_o.fflags[FPU_FFLAG_OF] !== 1'b0) ||
        (resp_o.fflags[FPU_FFLAG_UF] !== 1'b0)) begin
      sin_s_fail_cnt++;
      fail_cnt++;
      $display("[FAIL] s_mul_sin_t_sin_t sample=%0d theta=%0.12f sin=%0.12f result exp=0x%08h got=0x%08h fflags=0x%02h",
               sample_idx, theta, sin_value_s, product_bits, resp_o.result[31:0],
               resp_o.fflags);
    end else begin
      sin_s_pass_cnt++;
      pass_cnt++;
    end

  endtask

  task automatic check_sin_sample_d(input int unsigned sample_idx);
    real       theta;
    real       sin_value;
    real       product_real;
    fpu_data_t sin_bits;
    fpu_data_t product_bits;

    theta        = (TWO_PI * real'(sample_idx)) / real'(SIN_SAMPLES_PER_PERIOD);
    sin_value    = $sin(theta);
    product_real = sin_value * sin_value;
    sin_bits     = $realtobits(sin_value);
    product_bits = $realtobits(product_real);

    apply_req("d_mul_sin_t_sin_t", FPU_OP_MUL, FPU_FMT_D, FPU_RM_RNE,
              sin_bits, sin_bits);

    dbg_sin_phase          = 2'd2;
    dbg_sin_sample_idx     = sample_idx;
    dbg_sin_theta          = theta;
    dbg_sin_d_value_real   = sin_value;
    dbg_sin_d_product_real = $bitstoreal(resp_o.result);
    dbg_sin_d_value_bits   = sin_bits;
    dbg_sin_d_product_bits = resp_o.result;

    if ((valid_op_o !== 1'b1) ||
        (resp_o.result !== product_bits) ||
        (resp_o.fflags[FPU_FFLAG_NV] !== 1'b0) ||
        (resp_o.fflags[FPU_FFLAG_DZ] !== 1'b0) ||
        (resp_o.fflags[FPU_FFLAG_OF] !== 1'b0) ||
        (resp_o.fflags[FPU_FFLAG_UF] !== 1'b0)) begin
      sin_d_fail_cnt++;
      fail_cnt++;
      $display("[FAIL] d_mul_sin_t_sin_t sample=%0d theta=%0.12f sin=%0.12f result exp=0x%016h got=0x%016h fflags=0x%02h",
               sample_idx, theta, sin_value, product_bits, resp_o.result,
               resp_o.fflags);
    end else begin
      sin_d_pass_cnt++;
      pass_cnt++;
    end

  endtask

  initial begin
`ifdef DUMP_FSDB
    $fsdbDumpfile("tb_fpu_mult.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_mult);
`endif

    pass_cnt = 0;
    fail_cnt = 0;
    case_id  = 0;
    sin_s_pass_cnt = 0;
    sin_s_fail_cnt = 0;
    sin_d_pass_cnt = 0;
    sin_d_fail_cnt = 0;
    dbg_sin_phase          = 2'd0;
    dbg_sin_sample_idx     = 0;
    dbg_sin_theta          = 0.0;
    dbg_sin_s_value_real   = 0.0;
    dbg_sin_s_product_real = 0.0;
    dbg_sin_d_value_real   = 0.0;
    dbg_sin_d_product_real = 0.0;
    dbg_sin_s_value_bits   = 32'd0;
    dbg_sin_s_product_bits = 32'd0;
    dbg_sin_d_value_bits   = 64'd0;
    dbg_sin_d_product_bits = 64'd0;
    drive_idle();

    check_mul("s_mul_1p5_2p0", FPU_OP_MUL, FPU_FMT_S, FPU_RM_RNE,
              nanbox_s(32'h3fc0_0000), nanbox_s(32'h4000_0000),
              nanbox_s(32'h4040_0000), FFLAGS_NONE, 1'b1);
    check_mul("s_mul_neg_zero_pos", FPU_OP_MUL, FPU_FMT_S, FPU_RM_RNE,
              nanbox_s(32'h8000_0000), nanbox_s(32'h4040_0000),
              nanbox_s(32'h8000_0000), FFLAGS_NONE, 1'b1);
    check_mul("s_mul_inf_zero_invalid", FPU_OP_MUL, FPU_FMT_S, FPU_RM_RNE,
              nanbox_s(32'h7f80_0000), nanbox_s(32'h0000_0000),
              nanbox_s(32'h7fc0_0000), FFLAGS_NV, 1'b1);
    check_mul("s_mul_max_2p0_overflow", FPU_OP_MUL, FPU_FMT_S, FPU_RM_RNE,
              nanbox_s(32'h7f7f_ffff), nanbox_s(32'h4000_0000),
              nanbox_s(32'h7f80_0000), FFLAGS_OFNX, 1'b1);
    check_mul("s_mul_min_norm_half", FPU_OP_MUL, FPU_FMT_S, FPU_RM_RNE,
              nanbox_s(32'h0080_0000), nanbox_s(32'h3f00_0000),
              nanbox_s(32'h0040_0000), FFLAGS_NONE, 1'b1);
    check_mul("s_mul_tiny_underflow", FPU_OP_MUL, FPU_FMT_S, FPU_RM_RNE,
              nanbox_s(32'h0080_0000), nanbox_s(32'h0080_0000),
              nanbox_s(32'h0000_0000), FFLAGS_UFNX, 1'b1);
    check_mul("s_mul_bad_nanbox", FPU_OP_MUL, FPU_FMT_S, FPU_RM_RNE,
              {32'h0000_0000, 32'h3f80_0000}, nanbox_s(32'h4000_0000),
              nanbox_s(32'h7fc0_0000), FFLAGS_NONE, 1'b1);

    check_mul("d_mul_1p5_2p0", FPU_OP_MUL, FPU_FMT_D, FPU_RM_RNE,
              64'h3ff8_0000_0000_0000, 64'h4000_0000_0000_0000,
              64'h4008_0000_0000_0000, FFLAGS_NONE, 1'b1);
    check_mul("d_mul_neg2_half", FPU_OP_MUL, FPU_FMT_D, FPU_RM_RNE,
              64'hc000_0000_0000_0000, 64'h3fe0_0000_0000_0000,
              64'hbff0_0000_0000_0000, FFLAGS_NONE, 1'b1);
    check_mul("d_mul_inf_zero_invalid", FPU_OP_MUL, FPU_FMT_D, FPU_RM_RNE,
              64'h7ff0_0000_0000_0000, 64'h0000_0000_0000_0000,
              64'h7ff8_0000_0000_0000, FFLAGS_NV, 1'b1);
    check_mul("d_mul_max_2p0_overflow", FPU_OP_MUL, FPU_FMT_D, FPU_RM_RNE,
              64'h7fef_ffff_ffff_ffff, 64'h4000_0000_0000_0000,
              64'h7ff0_0000_0000_0000, FFLAGS_OFNX, 1'b1);
    check_mul("d_mul_min_norm_half", FPU_OP_MUL, FPU_FMT_D, FPU_RM_RNE,
              64'h0010_0000_0000_0000, 64'h3fe0_0000_0000_0000,
              64'h0008_0000_0000_0000, FFLAGS_NONE, 1'b1);
    check_mul("d_mul_tiny_underflow", FPU_OP_MUL, FPU_FMT_D, FPU_RM_RNE,
              64'h0010_0000_0000_0000, 64'h0010_0000_0000_0000,
              64'h0000_0000_0000_0000, FFLAGS_UFNX, 1'b1);

    check_mul("invalid_op", FPU_OP_ADD, FPU_FMT_S, FPU_RM_RNE,
              nanbox_s(32'h3f80_0000), nanbox_s(32'h3f80_0000),
              64'd0, FFLAGS_NONE, 1'b0);

    for (int unsigned sample_idx = 0; sample_idx < SIN_TOTAL_SAMPLES; sample_idx++) begin
      check_sin_sample_s(sample_idx);
    end

    drive_idle();

    for (int unsigned sample_idx = 0; sample_idx < SIN_TOTAL_SAMPLES; sample_idx++) begin
      check_sin_sample_d(sample_idx);
    end

    drive_idle();

    $display("tb_fpu_mult summary: pass=%0d fail=%0d cases=%0d",
             pass_cnt, fail_cnt, case_id);
    $display("sin(t)*sin(t) S: periods=%0d samples_per_period=%0d total_samples=%0d pass=%0d fail=%0d range=[-1,1]",
             SIN_PERIODS, SIN_SAMPLES_PER_PERIOD, SIN_TOTAL_SAMPLES,
             sin_s_pass_cnt, sin_s_fail_cnt);
    $display("sin(t)*sin(t) D: periods=%0d samples_per_period=%0d total_samples=%0d pass=%0d fail=%0d range=[-1,1]",
             SIN_PERIODS, SIN_SAMPLES_PER_PERIOD, SIN_TOTAL_SAMPLES,
             sin_d_pass_cnt, sin_d_fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_mult failed");
    end

    $finish;
  end

endmodule : tb_fpu_mult
