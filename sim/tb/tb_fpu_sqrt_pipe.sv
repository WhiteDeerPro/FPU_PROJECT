`timescale 1ns/1ps

module tb_fpu_sqrt_pipe;
  import fpu_pkg::*;

  localparam int unsigned TIMEOUT_CYCLES = 500;
  localparam int unsigned COS_SWEEP_POINTS = 720;
  localparam real         PI = 3.1415926535897932384626433832795;

  logic      clk_i;
  logic      rst_ni;
  logic      valid_i;
  fpu_req_t  req_i;
  logic      ready_o;
  logic      valid_o;
  fpu_resp_t resp_o;
  logic      valid_op_o;

  int unsigned pass_cnt;
  int unsigned fail_cnt;
  int unsigned cos_pass_cnt;
  int unsigned cos_fail_cnt;
  int unsigned cos_print_cnt;

  fpu_sqrt_unit_pipe u_dut (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (valid_i),
    .req_i     (req_i),
    .ready_o   (ready_o),
    .valid_o   (valid_o),
    .resp_o    (resp_o),
    .valid_op_o(valid_op_o)
  );

  function automatic fpu_data_t nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
  endfunction

  function automatic fpu_req_t make_req(
    input fpu_fmt_e  fmt,
    input fpu_rm_e   rm,
    input fpu_data_t a,
    input int unsigned idx
  );
    fpu_req_t req;
    req         = '0;
    req.op      = FPU_OP_SQRT;
    req.rs_fmt  = fmt;
    req.dst_fmt = fmt;
    req.rm      = rm;
    req.src_a   = a;
    req.tag     = idx[7:0];
    req.rd      = idx[4:0];
    return req;
  endfunction

  task automatic check_sqrt(
    input string       name,
    input fpu_fmt_e    fmt,
    input fpu_rm_e     rm,
    input fpu_data_t   src,
    input fpu_data_t   exp_result,
    input fpu_fflags_t exp_fflags,
    input logic        exp_valid_op
  );
    int unsigned waited;
    fpu_req_t    req;

    req = make_req(fmt, rm, src, pass_cnt + fail_cnt);
    waited = 0;

    @(posedge clk_i);
    while (!ready_o) begin
      @(posedge clk_i);
    end

    req_i   <= req;
    valid_i <= 1'b1;
    @(posedge clk_i);
    valid_i <= 1'b0;
    req_i   <= '0;

    while (!valid_o && waited < TIMEOUT_CYCLES) begin
      waited++;
      @(posedge clk_i);
    end

    if (!valid_o) begin
      fail_cnt++;
      $display("[FAIL] %-24s timeout", name);
    end else if ((valid_op_o !== exp_valid_op) ||
                 (resp_o.result !== exp_result) ||
                 (resp_o.fflags !== exp_fflags)) begin
      fail_cnt++;
      $display("[FAIL] %-24s got=0x%016h flags=0x%02h valid_op=%0b exp=0x%016h flags=0x%02h valid_op=%0b",
               name, resp_o.result, resp_o.fflags, valid_op_o,
               exp_result, exp_fflags, exp_valid_op);
    end else begin
      pass_cnt++;
      $display("[PASS] %-24s result=0x%016h flags=0x%02h",
               name, resp_o.result, resp_o.fflags);
    end
  endtask

  function automatic real abs_real(input real value);
    return (value < 0.0) ? -value : value;
  endfunction

  function automatic int unsigned abs_int(input int value);
    return (value < 0) ? int'(-value) : int'(value);
  endfunction

  task automatic check_cos_identity_point(input int unsigned idx);
    real          x_real;
    real          y_real;
    real          y_s_real;
    real          ref_half_real;
    real          ref_sqrt_real;
    real          got_real;
    real          abs_err_identity;
    int unsigned  y_s_bits;
    int unsigned  exp_bits;
    int unsigned  got_bits;
    int unsigned  ulp_err;
    int unsigned  waited;
    fpu_req_t     req;

    x_real       = (20.0 * PI * real'(idx)) / real'(COS_SWEEP_POINTS - 1);
    y_real       = ($cos(x_real) + 1.0) * 0.5;
    y_s_bits     = $shortrealtobits(shortreal'(y_real));
    y_s_real     = real'($bitstoshortreal(y_s_bits));
    ref_half_real = abs_real($cos(x_real * 0.5));
    ref_sqrt_real = $sqrt(y_s_real);
    exp_bits     = $shortrealtobits(shortreal'(ref_sqrt_real));

    req = make_req(FPU_FMT_S, FPU_RM_RNE, nanbox_s(y_s_bits[31:0]), idx);
    waited = 0;

    @(posedge clk_i);
    while (!ready_o) begin
      @(posedge clk_i);
    end

    req_i   <= req;
    valid_i <= 1'b1;
    @(posedge clk_i);
    valid_i <= 1'b0;
    req_i   <= '0;

    while (!valid_o && waited < TIMEOUT_CYCLES) begin
      waited++;
      @(posedge clk_i);
    end

    got_bits = resp_o.result[31:0];
    got_real = real'($bitstoshortreal(got_bits[31:0]));
    abs_err_identity = abs_real(got_real - ref_half_real);
    ulp_err = abs_int(int'(got_bits) - int'(exp_bits));

    if (!valid_o) begin
      cos_fail_cnt++;
      $display("[FAIL] cos_sweep[%0d] timeout", idx);
    end else if (!valid_op_o || (ulp_err > 1)) begin
      cos_fail_cnt++;
      if (cos_print_cnt < 24) begin
        $display("[FAIL] cos_sweep[%0d] x=%0.9f y_real=%0.9f y_s=0x%08h y_s_real=%0.9f got=0x%08h/%0.9f exp=0x%08h/%0.9f abs_cos_half=%0.9f ulp=%0d flags=0x%02h",
                 idx, x_real, y_real, y_s_bits[31:0], y_s_real,
                 got_bits[31:0], got_real, exp_bits[31:0], ref_sqrt_real,
                 ref_half_real, ulp_err, resp_o.fflags);
        cos_print_cnt++;
      end
    end else begin
      cos_pass_cnt++;
      if (cos_print_cnt < 12) begin
        $display("[COS] idx=%0d x=%0.9f y=(cos+1)/2 real=%0.9f s=0x%08h sqrt_s=0x%08h/%0.9f abs_cos_half=%0.9f err=%0.9e ulp=%0d",
                 idx, x_real, y_real, y_s_bits[31:0],
                 got_bits[31:0], got_real, ref_half_real,
                 abs_err_identity, ulp_err);
        cos_print_cnt++;
      end
    end
  endtask

  task automatic run_cos_identity_sweep;
    cos_pass_cnt = 0;
    cos_fail_cnt = 0;
    cos_print_cnt = 0;

    for (int unsigned idx = 0; idx < COS_SWEEP_POINTS; idx++) begin
      check_cos_identity_point(idx);
    end

    $display("tb_fpu_sqrt_pipe cos identity S summary: total=%0d pass=%0d fail=%0d",
             COS_SWEEP_POINTS, cos_pass_cnt, cos_fail_cnt);
    if (cos_fail_cnt != 0) begin
      fail_cnt += cos_fail_cnt;
    end else begin
      pass_cnt += 1;
    end
  endtask

  always #5 clk_i = ~clk_i;

  initial begin
`ifdef DUMP_FSDB
    $fsdbDumpfile("tb_fpu_sqrt_pipe.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_sqrt_pipe);
`endif

    clk_i = 1'b0;
    rst_ni = 1'b0;
    valid_i = 1'b0;
    req_i = '0;
    pass_cnt = 0;
    fail_cnt = 0;
    cos_pass_cnt = 0;
    cos_fail_cnt = 0;
    cos_print_cnt = 0;

    repeat (5) @(posedge clk_i);
    rst_ni = 1'b1;
    repeat (2) @(posedge clk_i);

    check_sqrt("d_sqrt_1_exact", FPU_FMT_D, FPU_RM_RNE,
               64'h3ff0_0000_0000_0000,
               64'h3ff0_0000_0000_0000, '0, 1'b1);
    check_sqrt("d_sqrt_4_exact", FPU_FMT_D, FPU_RM_RNE,
               64'h4010_0000_0000_0000,
               64'h4000_0000_0000_0000, '0, 1'b1);
    check_sqrt("d_sqrt_2_rne", FPU_FMT_D, FPU_RM_RNE,
               64'h4000_0000_0000_0000,
               64'h3ff6_a09e_667f_3bcd, 5'b0_0001, 1'b1);
    check_sqrt("d_sqrt_neg_nv", FPU_FMT_D, FPU_RM_RNE,
               64'hbff0_0000_0000_0000,
               64'h7ff8_0000_0000_0000, 5'b1_0000, 1'b1);
    check_sqrt("d_sqrt_neg_zero", FPU_FMT_D, FPU_RM_RNE,
               64'h8000_0000_0000_0000,
               64'h8000_0000_0000_0000, '0, 1'b1);
    check_sqrt("d_sqrt_inf", FPU_FMT_D, FPU_RM_RNE,
               64'h7ff0_0000_0000_0000,
               64'h7ff0_0000_0000_0000, '0, 1'b1);
    check_sqrt("s_sqrt_4_exact", FPU_FMT_S, FPU_RM_RNE,
               nanbox_s(32'h4080_0000),
               nanbox_s(32'h4000_0000), '0, 1'b1);
    check_sqrt("s_sqrt_2_rne", FPU_FMT_S, FPU_RM_RNE,
               nanbox_s(32'h4000_0000),
               nanbox_s(32'h3fb5_04f3), 5'b0_0001, 1'b1);

    run_cos_identity_sweep();

    $display("tb_fpu_sqrt_pipe summary: pass=%0d fail=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_sqrt_pipe failed");
    end

    $finish;
  end

endmodule : tb_fpu_sqrt_pipe
