`timescale 1ns/1ps

module tb_fpu_sqrt_pipe;
  import fpu_pkg::*;

  // 复制DUT中的参数，用于数组信号声明
  localparam int unsigned NUM_CTX = 6;
  localparam int unsigned FMA_LATENCY = 5;

  localparam int unsigned TIMEOUT_CYCLES = 500;
  localparam int unsigned SQRT_VEC_COUNT = 10760;
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

  // ---- 端口级调试信号（仿照 add pipe） ----
  logic        dbg_is_s;
  logic        dbg_is_d;
  logic        dbg_rm_rne;
  logic [63:0] dbg_src_a;
  logic [63:0] dbg_result;
  logic [4:0]  dbg_fflags;
  logic [1:0]  dbg_fmt;
  logic [2:0]  dbg_rm;
  logic        dbg_valid;
  logic        dbg_ready;
  logic        dbg_valid_op;

  // 实数转换
  real         dbg_d_src_a_real;
  real         dbg_d_result_real;
  real         dbg_s_src_a_real;
  real         dbg_s_result_real;

  logic [31:0] dbg_s_src_a;
  logic [31:0] dbg_s_result;
  logic [63:0] dbg_d_src_a;
  logic [63:0] dbg_d_result;

  // 无用b信号置零
  logic [31:0] dbg_s_src_b;
  logic [31:0] dbg_s_result_b;
  logic [63:0] dbg_d_src_b;
  logic [63:0] dbg_d_result_b;

  // ---- 新增内部调试信号（从DUT内部抓取） ----
  // 源操作数解析
  logic [52:0] dbg_src_sig_norm;
  logic signed [15:0] dbg_src_unbiased_exp;
  logic        dbg_src_exp_odd;

  // 种子
  logic [63:0] dbg_seed_data;

  // FMA流水线接口
  logic        dbg_fma_valid_i;
  fpu_req_t    dbg_fma_req;
  logic        dbg_fma_valid_o;
  fpu_resp_t   dbg_fma_resp;
  logic        dbg_fma_valid_op_o;

  // 上下文数组（便于波形查看）
  logic [NUM_CTX-1:0] dbg_ctx_active;
  logic [NUM_CTX-1:0] dbg_ctx_ready;
  logic [NUM_CTX-1:0] dbg_ctx_done;
  logic [2:0]         dbg_ctx_step [NUM_CTX];      // micro_op_e
  logic [63:0]        dbg_ctx_x     [NUM_CTX];
  logic [63:0]        dbg_ctx_t     [NUM_CTX];
  logic [63:0]        dbg_ctx_e     [NUM_CTX];
  logic [63:0]        dbg_ctx_q     [NUM_CTX];
  logic [63:0]        dbg_ctx_r     [NUM_CTX];
  logic [63:0]        dbg_ctx_a_mant[NUM_CTX];
  logic signed [15:0] dbg_ctx_exp_delta [NUM_CTX];
  logic [2:0]         dbg_ctx_iter      [NUM_CTX];
  logic [2:0]         dbg_ctx_iter_limit[NUM_CTX];

  int unsigned pass_cnt;
  int unsigned fail_cnt;
  int unsigned cos_pass_cnt;
  int unsigned cos_fail_cnt;
  int unsigned cos_print_cnt;
  int unsigned vec_pass_cnt;
  int unsigned vec_result_fail_cnt;
  int unsigned vec_timeout_cnt;
  int unsigned vec_print_cnt;
  int unsigned vec_result_fail_by_fmt_rm [2][5];
  int unsigned vec_timeout_by_fmt_rm     [2][5];
  int unsigned vec_count_by_fmt_rm       [2][5];

  typedef logic [137:0] sqrt_vec_t;
  sqrt_vec_t sqrt_vec [SQRT_VEC_COUNT];

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

  // ---- 端口信号连接 ----
  assign dbg_is_s    = (req_i.rs_fmt == FPU_FMT_S);
  assign dbg_is_d    = (req_i.rs_fmt == FPU_FMT_D);
  assign dbg_rm_rne  = (req_i.rm == FPU_RM_RNE);
  assign dbg_src_a   = req_i.src_a;
  assign dbg_result  = resp_o.result;
  assign dbg_fflags  = resp_o.fflags;
  assign dbg_fmt     = req_i.rs_fmt;
  assign dbg_rm      = req_i.rm;
  assign dbg_valid   = valid_o;
  assign dbg_ready   = ready_o;
  assign dbg_valid_op = valid_op_o;

  assign dbg_s_src_a = req_i.src_a[31:0];
  assign dbg_s_result = resp_o.result[31:0];
  assign dbg_d_src_a = req_i.src_a;
  assign dbg_d_result = resp_o.result;
  assign dbg_s_src_b = 32'd0;
  assign dbg_s_result_b = 32'd0;
  assign dbg_d_src_b = 64'd0;
  assign dbg_d_result_b = 64'd0;

  always @* begin
    dbg_d_src_a_real  = $bitstoreal(req_i.src_a);
    dbg_d_result_real = $bitstoreal(resp_o.result);
    dbg_s_src_a_real  = $bitstoshortreal(req_i.src_a[31:0]);
    dbg_s_result_real = $bitstoshortreal(resp_o.result[31:0]);
  end

  // ---- 内部信号连接 ----
  // 源操作数解析输出
  assign dbg_src_sig_norm     = u_dut.src.sig_norm;
  assign dbg_src_unbiased_exp = u_dut.src.unbiased_exp;
  assign dbg_src_exp_odd      = u_dut.src.unbiased_exp[0];

  // 种子数据
  assign dbg_seed_data = u_dut.seed_data;

  // FMA接口（注意u_dut内部的FMA实例名）
  assign dbg_fma_valid_i = u_dut.fma_valid_q;
  assign dbg_fma_req     = u_dut.fma_req_q;
  assign dbg_fma_valid_o = u_dut.fma_valid_o;
  assign dbg_fma_resp    = u_dut.fma_resp_o;
  assign dbg_fma_valid_op_o = u_dut.fma_valid_op_o;

  // 上下文数组（使用generate批量连接）
  genvar gi;
  generate
    for (gi = 0; gi < NUM_CTX; gi++) begin : gen_ctx
      assign dbg_ctx_active[gi]      = u_dut.ctx_active[gi];
      assign dbg_ctx_ready[gi]       = u_dut.ctx_ready[gi];
      assign dbg_ctx_done[gi]        = u_dut.ctx_done[gi];
      assign dbg_ctx_step[gi]        = u_dut.ctx_step[gi];
      assign dbg_ctx_x[gi]           = u_dut.ctx_x[gi];
      assign dbg_ctx_t[gi]           = u_dut.ctx_t[gi];
      assign dbg_ctx_e[gi]           = u_dut.ctx_e[gi];
      assign dbg_ctx_q[gi]           = u_dut.ctx_q[gi];
      assign dbg_ctx_r[gi]           = u_dut.ctx_r[gi];
      assign dbg_ctx_a_mant[gi]      = u_dut.ctx_a_mant[gi];
      assign dbg_ctx_exp_delta[gi]   = u_dut.ctx_exp_delta[gi];
      assign dbg_ctx_iter[gi]        = u_dut.ctx_iter[gi];
      assign dbg_ctx_iter_limit[gi]  = u_dut.ctx_iter_limit[gi];
    end
  endgenerate

  // ---- 原有功能函数和任务（保持不变） ----
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

  function automatic fpu_rm_e rm_from_bits(input logic [2:0] rm_bits);
    unique case (rm_bits)
      3'd0: return FPU_RM_RNE;
      3'd1: return FPU_RM_RTZ;
      3'd2: return FPU_RM_RDN;
      3'd3: return FPU_RM_RUP;
      3'd4: return FPU_RM_RMM;
      default: return FPU_RM_RNE;
    endcase
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

  task automatic run_sqrt_vec(input int unsigned idx);
    logic        fmt_bit;
    logic [2:0]  rm_bits;
    fpu_data_t   src;
    fpu_data_t   exp_result;
    fpu_fflags_t exp_fflags;
    logic        exp_valid_op;
    int unsigned waited;
    fpu_req_t    req;

    {fmt_bit, rm_bits, src, exp_result, exp_fflags, exp_valid_op} = sqrt_vec[idx];
    req = make_req(fmt_bit ? FPU_FMT_D : FPU_FMT_S, rm_from_bits(rm_bits), src, idx);
    waited = 0;
    vec_count_by_fmt_rm[fmt_bit][rm_bits]++;

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
      vec_timeout_cnt++;
      vec_timeout_by_fmt_rm[fmt_bit][rm_bits]++;
      if (vec_print_cnt < 24) begin
        $display("[FAIL] sqrt_vec[%0d] timeout fmt=%0d rm=%0d src=0x%016h",
                 idx, fmt_bit, rm_bits, src);
        vec_print_cnt++;
      end
    end else if ((valid_op_o !== exp_valid_op) ||
                 (resp_o.result !== exp_result) ||
                 (resp_o.fflags !== exp_fflags)) begin
      vec_result_fail_cnt++;
      vec_result_fail_by_fmt_rm[fmt_bit][rm_bits]++;
      if (vec_print_cnt < 24) begin
        $display("[FAIL] sqrt_vec[%0d] fmt=%0d rm=%0d src=0x%016h got=0x%016h flags=0x%02h valid_op=%0b exp=0x%016h flags=0x%02h valid_op=%0b",
                 idx, fmt_bit, rm_bits, src, resp_o.result, resp_o.fflags, valid_op_o,
                 exp_result, exp_fflags, exp_valid_op);
        vec_print_cnt++;
      end
    end else begin
      vec_pass_cnt++;
    end
  endtask

  task automatic run_sqrt_vectors;
    $readmemh("../tb/fpu_sqrt_random_cases.mem", sqrt_vec);
    for (int unsigned idx = 0; idx < SQRT_VEC_COUNT; idx++) begin
      run_sqrt_vec(idx);
    end

    $display("tb_fpu_sqrt_pipe vector summary: total=%0d pass=%0d result_fail=%0d timeout=%0d",
             SQRT_VEC_COUNT, vec_pass_cnt, vec_result_fail_cnt, vec_timeout_cnt);
    for (int unsigned fmt_idx = 0; fmt_idx < 2; fmt_idx++) begin
      for (int unsigned rm_idx = 0; rm_idx < 5; rm_idx++) begin
        $display("tb_fpu_sqrt_pipe vector bucket fmt=%0d rm=%0d count=%0d result_fail=%0d timeout=%0d",
                 fmt_idx, rm_idx, vec_count_by_fmt_rm[fmt_idx][rm_idx],
                 vec_result_fail_by_fmt_rm[fmt_idx][rm_idx],
                 vec_timeout_by_fmt_rm[fmt_idx][rm_idx]);
      end
    end
    if ((vec_result_fail_cnt != 0) || (vec_timeout_cnt != 0)) begin
      fail_cnt += vec_result_fail_cnt + vec_timeout_cnt;
    end else begin
      pass_cnt += 1;
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
    vec_pass_cnt = 0;
    vec_result_fail_cnt = 0;
    vec_timeout_cnt = 0;
    vec_print_cnt = 0;
    for (int unsigned fmt_idx = 0; fmt_idx < 2; fmt_idx++) begin
      for (int unsigned rm_idx = 0; rm_idx < 5; rm_idx++) begin
        vec_result_fail_by_fmt_rm[fmt_idx][rm_idx] = 0;
        vec_timeout_by_fmt_rm[fmt_idx][rm_idx] = 0;
        vec_count_by_fmt_rm[fmt_idx][rm_idx] = 0;
      end
    end

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
    vec_pass_cnt = 0;
    vec_result_fail_cnt = 0;
    vec_timeout_cnt = 0;
    vec_print_cnt = 0;
    for (int unsigned fmt_idx = 0; fmt_idx < 2; fmt_idx++) begin
      for (int unsigned rm_idx = 0; rm_idx < 5; rm_idx++) begin
        vec_result_fail_by_fmt_rm[fmt_idx][rm_idx] = 0;
        vec_timeout_by_fmt_rm[fmt_idx][rm_idx] = 0;
        vec_count_by_fmt_rm[fmt_idx][rm_idx] = 0;
      end
    end

    repeat (5) @(posedge clk_i);
    rst_ni = 1'b1;
    repeat (2) @(posedge clk_i);

    // 常规平方根测试
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

    run_sqrt_vectors();

`ifdef ENABLE_SQRT_COS_SWEEP
    run_cos_identity_sweep();
`endif

    $display("tb_fpu_sqrt_pipe summary: pass=%0d fail=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_sqrt_pipe failed");
    end

    $finish;
  end

endmodule : tb_fpu_sqrt_pipe
