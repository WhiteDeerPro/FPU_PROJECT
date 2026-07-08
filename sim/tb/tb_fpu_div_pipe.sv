`timescale 1ns/1ps

module tb_fpu_div_pipe;
  import fpu_pkg::*;

  localparam int unsigned NUM_CASES = 55;
  localparam int unsigned TIMEOUT_CYCLES = 260;
  localparam int unsigned RANDOM_VEC_COUNT = 12560;
  localparam int unsigned SUBNORMAL_VEC_COUNT = 10000;
  localparam int unsigned RANDOM_PRINT_LIMIT = 20;

  typedef logic [201:0] div_random_vec_t;

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
  int unsigned cycle_cnt;
  int unsigned random_pass_cnt;
  int unsigned random_result_fail_cnt;
  int unsigned random_nx_fail_cnt;
  int unsigned random_timeout_cnt;
  int unsigned random_print_cnt;
  int unsigned random_result_fail_by_fmt_rm [2][5];
  int unsigned random_nx_fail_by_fmt_rm     [2][5];
  int unsigned random_count_by_fmt_rm       [2][5];
  int unsigned subnormal_pass_cnt;
  int unsigned subnormal_result_fail_cnt;
  int unsigned subnormal_nx_fail_cnt;
  int unsigned subnormal_timeout_cnt;
  int unsigned subnormal_print_cnt;
  int unsigned subnormal_result_fail_by_fmt_rm [2][5];
  int unsigned subnormal_nx_fail_by_fmt_rm     [2][5];
  int unsigned subnormal_count_by_fmt_rm       [2][5];

  div_random_vec_t random_vec [RANDOM_VEC_COUNT];
  div_random_vec_t subnormal_vec [SUBNORMAL_VEC_COUNT];

  logic [7:0]  trace_accept_tag;
  logic [7:0]  trace_result_tag;
  logic [31:0] trace_accept_s_src_a;
  logic [31:0] trace_accept_s_src_b;
  logic [31:0] trace_result_s;
  logic [63:0] trace_accept_d_src_a;
  logic [63:0] trace_accept_d_src_b;
  logic [63:0] trace_result_d;

  fpu_data_t   trace_src_a_by_tag  [256];
  fpu_data_t   trace_src_b_by_tag  [256];
  fpu_data_t   trace_result_by_tag [256];
  fpu_fmt_e    trace_fmt_by_tag    [256];
  fpu_fflags_t trace_fflags_by_tag [256];

  fpu_div_unit_pipe u_dut (
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
    input fpu_fmt_e    fmt,
    input fpu_rm_e     rm,
    input fpu_data_t   a,
    input fpu_data_t   b,
    input int unsigned idx
  );
    fpu_req_t req;

    req         = '0;
    req.op      = FPU_OP_DIV;
    req.rs_fmt  = fmt;
    req.dst_fmt = fmt;
    req.rm      = rm;
    req.src_a   = a;
    req.src_b   = b;
    req.tag     = idx[7:0];
    req.rd      = idx[4:0];
    return req;
  endfunction

  function automatic fpu_req_t case_req(input int unsigned idx);
    unique case (idx)
      0: return make_req(FPU_FMT_D, FPU_RM_RNE,
                         64'h4018_0000_0000_0000,  // 6.0
                         64'h4000_0000_0000_0000,  // 2.0
                         idx);
      1: return make_req(FPU_FMT_D, FPU_RM_RNE,
                         64'h3ff0_0000_0000_0000,  // 1.0
                         64'h4000_0000_0000_0000,  // 2.0
                         idx);
      2: return make_req(FPU_FMT_D, FPU_RM_RNE,
                         64'hc014_0000_0000_0000,  // -5.0
                         64'h4004_0000_0000_0000,  // 2.5
                         idx);
      3: return make_req(FPU_FMT_D, FPU_RM_RNE,
                         64'h3ff0_0000_0000_0000,  // 1.0
                         64'h3ff0_0000_0000_0000,  // 1.0
                         idx);
      4: return make_req(FPU_FMT_S, FPU_RM_RNE,
                         nanbox_s(32'h40c0_0000),  // 6.0f
                         nanbox_s(32'h4000_0000),  // 2.0f
                         idx);
      5: return make_req(FPU_FMT_S, FPU_RM_RNE,
                         nanbox_s(32'h3f80_0000),  // 1.0f
                         nanbox_s(32'h4080_0000),  // 4.0f
                         idx);
      6: return make_req(FPU_FMT_S, FPU_RM_RNE,
                         nanbox_s(32'hc0a0_0000),  // -5.0f
                         nanbox_s(32'h4020_0000),  // 2.5f
                         idx);
      7: return make_req(FPU_FMT_D, FPU_RM_RNE,
                         64'h3ff0_0000_0000_0000,
                         64'h0000_0000_0000_0000,
                         idx);
      8: return make_req(FPU_FMT_D, FPU_RM_RNE,
                         64'h0000_0000_0000_0000,
                         64'h0000_0000_0000_0000,
                         idx);
      9: return make_req(FPU_FMT_D, FPU_RM_RNE,
                         64'h7ff0_0000_0000_0000,
                         64'h7ff0_0000_0000_0000,
                         idx);
      10: return make_req(FPU_FMT_D, FPU_RM_RNE,
                          64'h7ff0_0000_0000_0000,
                          64'h4000_0000_0000_0000,
                          idx);
      11: return make_req(FPU_FMT_D, FPU_RM_RNE,
                          64'h3ff0_0000_0000_0000,
                          64'h7ff0_0000_0000_0000,
                          idx);
      12: return make_req(FPU_FMT_D, FPU_RM_RNE,
                          64'h7ff8_0000_0000_0001,
                          64'h4000_0000_0000_0000,
                          idx);
      13: return make_req(FPU_FMT_D, FPU_RM_RNE,
                          64'h7ff0_0000_0000_0001,
                          64'h4000_0000_0000_0000,
                          idx);
      14: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000),
                          nanbox_s(32'h0000_0000),
                          idx);
      15: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h0000_0000),
                          nanbox_s(32'h4000_0000),
                          idx);
      16: begin
        fpu_req_t req;
        req = make_req(FPU_FMT_D, FPU_RM_RNE,
                       64'h3ff0_0000_0000_0000,
                       64'h3ff0_0000_0000_0000,
                       idx);
        req.op = FPU_OP_ADD;
        return req;
      end
      22: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h3dcccccd), idx);
      23: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h3f19999a), idx);
      24: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h3f8ccccd), idx);
      25: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h3fcccccd), idx);
      26: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h40066666), idx);
      27: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h40266666), idx);
      28: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h40466666), idx);
      29: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h40666666), idx);
      30: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h40833333), idx);
      31: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h40933333), idx);
      32: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h40a33333), idx);
      33: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h40b33333), idx);
      34: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h40c33333), idx);
      35: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h40d33333), idx);
      36: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h40e33333), idx);
      37: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h40f33333), idx);
      38: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h4101999a), idx);
      39: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h4109999a), idx);
      40: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h4111999a), idx);
      41: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h4119999a), idx);
      42: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h3f80_0000), nanbox_s(32'h41200000), idx);
      43: return make_req(FPU_FMT_D, FPU_RM_RNE,
                          64'h4008_0000_0000_0000, 64'h4008_0000_0000_0000, idx);
      44: return make_req(FPU_FMT_D, FPU_RM_RTZ,
                          64'h4008_0000_0000_0000, 64'h4008_0000_0000_0000, idx);
      45: return make_req(FPU_FMT_D, FPU_RM_RDN,
                          64'h4008_0000_0000_0000, 64'h4008_0000_0000_0000, idx);
      46: return make_req(FPU_FMT_D, FPU_RM_RUP,
                          64'h4008_0000_0000_0000, 64'h4008_0000_0000_0000, idx);
      47: return make_req(FPU_FMT_D, FPU_RM_RMM,
                          64'h4008_0000_0000_0000, 64'h4008_0000_0000_0000, idx);
      48: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h4040_0000), nanbox_s(32'h4040_0000), idx);
      49: return make_req(FPU_FMT_S, FPU_RM_RTZ,
                          nanbox_s(32'h4040_0000), nanbox_s(32'h4040_0000), idx);
      50: return make_req(FPU_FMT_S, FPU_RM_RDN,
                          nanbox_s(32'h4040_0000), nanbox_s(32'h4040_0000), idx);
      51: return make_req(FPU_FMT_S, FPU_RM_RUP,
                          nanbox_s(32'h4040_0000), nanbox_s(32'h4040_0000), idx);
      52: return make_req(FPU_FMT_S, FPU_RM_RMM,
                          nanbox_s(32'h4040_0000), nanbox_s(32'h4040_0000), idx);
      53: return make_req(FPU_FMT_D, FPU_RM_RNE,
                          64'hc008_0000_0000_0000, 64'h4008_0000_0000_0000, idx);
      54: return make_req(FPU_FMT_S, FPU_RM_RNE,
                          nanbox_s(32'h4040_0000), nanbox_s(32'hc040_0000), idx);
      default: return make_req(FPU_FMT_D, FPU_RM_RNE,
                               case_data_a(idx),
                               case_data_b(idx),
                               idx);
    endcase
  endfunction

  function automatic fpu_data_t case_data_a(input int unsigned idx);
    unique case (idx)
      17: return 64'h4024_0000_0000_0000; // 10.0
      18: return 64'h7fef_ffff_ffff_ffff; // max finite
      19: return 64'h0010_0000_0000_0000; // min normal
      20: return 64'h3ff0_0000_0000_0000; // 1.0
      default: return 64'h7fef_ffff_ffff_ffff; // max finite
    endcase
  endfunction

  function automatic fpu_data_t case_data_b(input int unsigned idx);
    unique case (idx)
      17: return 64'h4008_0000_0000_0000; // 3.0
      18: return 64'h3ff0_0000_0000_0000; // 1.0
      19: return 64'h4000_0000_0000_0000; // 2.0
      20: return 64'h0010_0000_0000_0000; // min normal
      default: return 64'h0010_0000_0000_0000; // min normal
    endcase
  endfunction

  function automatic fpu_data_t expected_result(input int unsigned idx);
    unique case (idx)
      0: return 64'h4008_0000_0000_0000;          // 3.0
      1: return 64'h3fe0_0000_0000_0000;          // 0.5
      2: return 64'hc000_0000_0000_0000;          // -2.0
      3: return 64'h3ff0_0000_0000_0000;          // 1.0
      4: return nanbox_s(32'h4040_0000);          // 3.0f
      5: return nanbox_s(32'h3e80_0000);          // 0.25f
      6: return nanbox_s(32'hc000_0000);          // -2.0f
      7: return 64'h7ff0_0000_0000_0000;          // +inf, DZ
      8: return 64'h7ff8_0000_0000_0000;          // canonical NaN
      9: return 64'h7ff8_0000_0000_0000;          // canonical NaN
      10: return 64'h7ff0_0000_0000_0000;         // +inf
      11: return 64'h0000_0000_0000_0000;         // +0
      12: return 64'h7ff8_0000_0000_0000;         // canonical NaN
      13: return 64'h7ff8_0000_0000_0000;         // canonical NaN
      14: return nanbox_s(32'h7f80_0000);         // +inf, DZ
      15: return nanbox_s(32'h0000_0000);         // +0
      16: return 64'd0;                           // invalid op
      17: return 64'h400a_aaaa_aaaa_aaab;         // 10.0 / 3.0
      18: return 64'h7fef_ffff_ffff_ffff;         // max finite / 1.0
      19: return 64'h0008_0000_0000_0000;         // min normal / 2.0
      20: return 64'h7fd0_0000_0000_0000;         // 1.0 / min normal
      22: return nanbox_s(32'h4120_0000);         // 1.0f / 0.1f
      23: return nanbox_s(32'h3fd5_5555);         // 1.0f / 0.6f
      24: return nanbox_s(32'h3f68_ba2e);         // 1.0f / 1.1f
      25: return nanbox_s(32'h3f20_0000);         // 1.0f / 1.6f
      26: return nanbox_s(32'h3ef3_cf3e);         // 1.0f / 2.1f
      27: return nanbox_s(32'h3ec4_ec4f);         // 1.0f / 2.6f
      28: return nanbox_s(32'h3ea5_294b);         // 1.0f / 3.1f
      29: return nanbox_s(32'h3e8e_38e4);         // 1.0f / 3.6f
      30: return nanbox_s(32'h3e79_c190);         // 1.0f / 4.1f
      31: return nanbox_s(32'h3e5e_9bd4);         // 1.0f / 4.6f
      32: return nanbox_s(32'h3e48_c8c9);         // 1.0f / 5.1f
      33: return nanbox_s(32'h3e36_db6e);         // 1.0f / 5.6f
      34: return nanbox_s(32'h3e27_de6d);         // 1.0f / 6.1f
      35: return nanbox_s(32'h3e1b_26ca);         // 1.0f / 6.6f
      36: return nanbox_s(32'h3e10_39b1);         // 1.0f / 7.1f
      37: return nanbox_s(32'h3e06_bca2);         // 1.0f / 7.6f
      38: return nanbox_s(32'h3dfc_d6e9);         // 1.0f / 8.1f
      39: return nanbox_s(32'h3dee_23b8);         // 1.0f / 8.6f
      40: return nanbox_s(32'h3de1_0e10);         // 1.0f / 9.1f
      41: return nanbox_s(32'h3dd5_5555);         // 1.0f / 9.6f
      42: return nanbox_s(32'h3dcc_cccd);         // 1.0f / 10.0f
      43, 44, 45, 46, 47: return 64'h3ff0_0000_0000_0000; // 3.0 / 3.0
      48, 49, 50, 51, 52: return nanbox_s(32'h3f80_0000); // 3.0f / 3.0f
      53: return 64'hbff0_0000_0000_0000;         // -3.0 / 3.0
      54: return nanbox_s(32'hbf80_0000);         // 3.0f / -3.0f
      default: return 64'h7ff0_0000_0000_0000;    // overflow
    endcase
  endfunction

  function automatic fpu_fflags_t expected_fflags(input int unsigned idx);
    fpu_fflags_t flags;

    flags = '0;
    unique case (idx)
      7, 14: flags[FPU_FFLAG_DZ] = 1'b1;
      8, 9, 13: flags[FPU_FFLAG_NV] = 1'b1;
      17:       flags[FPU_FFLAG_NX] = 1'b1;
      21: begin
        flags[FPU_FFLAG_OF] = 1'b1;
        flags[FPU_FFLAG_NX] = 1'b1;
      end
      22, 23, 24, 25, 26, 27, 28,
      29, 30, 31, 32, 33, 34, 35,
      36, 37, 38, 39, 40, 41, 42: begin
        flags[FPU_FFLAG_NX] = 1'b1;
      end
      default: begin end
    endcase

    return flags;
  endfunction

  function automatic logic expected_valid_op(input int unsigned idx);
    return (idx != 16);
  endfunction

  function automatic fpu_fmt_e vec_fmt(input logic fmt_bit);
    return fmt_bit ? FPU_FMT_D : FPU_FMT_S;
  endfunction

  function automatic fpu_rm_e vec_rm(input logic [2:0] rm_bits);
    unique case (rm_bits)
      3'd0: return FPU_RM_RNE;
      3'd1: return FPU_RM_RTZ;
      3'd2: return FPU_RM_RDN;
      3'd3: return FPU_RM_RUP;
      3'd4: return FPU_RM_RMM;
      default: return FPU_RM_RNE;
    endcase
  endfunction

  task automatic run_random_vec(input int unsigned idx);
    logic          fmt_bit;
    logic [2:0]    rm_bits;
    fpu_data_t     src_a;
    fpu_data_t     src_b;
    fpu_data_t     exp_result;
    fpu_fflags_t   exp_fflags;
    logic          exp_valid_op;
    fpu_req_t      req;
    int unsigned   waited;
    logic          result_match;
    logic          flags_match;

    {fmt_bit, rm_bits, src_a, src_b, exp_result, exp_fflags, exp_valid_op} = random_vec[idx];
    req          = make_req(vec_fmt(fmt_bit), vec_rm(rm_bits),
                            src_a, src_b, 8'hc0 + idx[7:0]);
    waited       = 0;
    result_match = 1'b0;
    flags_match  = 1'b0;

    random_count_by_fmt_rm[fmt_bit][rm_bits]++;

    while (!ready_o) begin
      @(posedge clk_i);
      #1;
    end

    @(posedge clk_i);
    #1;
    req_i   = req;
    valid_i = 1'b1;
    @(posedge clk_i);
    #1;
    valid_i = 1'b0;
    req_i   = '0;

    while (!valid_o && waited < TIMEOUT_CYCLES) begin
      @(posedge clk_i);
      #1;
      waited++;
    end

    if (!valid_o) begin
      random_timeout_cnt++;
      fail_cnt++;
      if (random_print_cnt < RANDOM_PRINT_LIMIT) begin
        $display("[RAND_TIMEOUT] idx=%0d fmt=%0d rm=%0d a=0x%016h b=0x%016h",
                 idx, fmt_bit, rm_bits, src_a, src_b);
        random_print_cnt++;
      end
    end else begin
      result_match = (resp_o.result === exp_result);
      flags_match  = (resp_o.fflags === exp_fflags);

      if (result_match && flags_match) begin
        random_pass_cnt++;
      end
      if (!result_match) begin
        random_result_fail_cnt++;
        random_result_fail_by_fmt_rm[fmt_bit][rm_bits]++;
      end
      if (!flags_match) begin
        random_nx_fail_cnt++;
        random_nx_fail_by_fmt_rm[fmt_bit][rm_bits]++;
      end
      if (!result_match || !flags_match) begin
        fail_cnt++;
        if (random_print_cnt < RANDOM_PRINT_LIMIT) begin
          $display("[RAND_FAIL] idx=%0d fmt=%0d rm=%0d a=0x%016h b=0x%016h result exp=0x%016h got=0x%016h flags exp=0x%02h got=0x%02h",
                   idx, fmt_bit, rm_bits, src_a, src_b,
                   exp_result, resp_o.result, exp_fflags, resp_o.fflags);
          random_print_cnt++;
        end
      end
    end
  endtask

  task automatic run_random_vectors;
    $readmemh("../tb/fpu_div_random_cases.mem", random_vec);
    for (int unsigned idx = 0; idx < RANDOM_VEC_COUNT; idx++) begin
      run_random_vec(idx);
    end

    $display("tb_fpu_div_pipe random summary: total=%0d pass=%0d result_fail=%0d nx_fail=%0d timeout=%0d",
             RANDOM_VEC_COUNT, random_pass_cnt, random_result_fail_cnt,
             random_nx_fail_cnt, random_timeout_cnt);
    for (int unsigned fmt_idx = 0; fmt_idx < 2; fmt_idx++) begin
      for (int unsigned rm_idx = 0; rm_idx < 5; rm_idx++) begin
        $display("tb_fpu_div_pipe random bucket fmt=%0d rm=%0d count=%0d result_fail=%0d nx_fail=%0d",
                 fmt_idx, rm_idx, random_count_by_fmt_rm[fmt_idx][rm_idx],
                 random_result_fail_by_fmt_rm[fmt_idx][rm_idx],
                 random_nx_fail_by_fmt_rm[fmt_idx][rm_idx]);
      end
    end
  endtask

  task automatic run_case(input int unsigned idx);
    fpu_req_t      req;
    int unsigned   waited;
    fpu_data_t     exp_result;
    fpu_fflags_t   exp_fflags;
    logic          exp_valid_op;

    req          = case_req(idx);
    exp_result   = expected_result(idx);
    exp_fflags   = expected_fflags(idx);
    exp_valid_op = expected_valid_op(idx);
    waited       = 0;

    while (!ready_o) begin
      @(posedge clk_i);
      #1;
    end

    @(posedge clk_i);
    #1;
    req_i   = req;
    valid_i = 1'b1;
    @(posedge clk_i);
    #1;
    valid_i = 1'b0;
    req_i   = '0;

    while (!valid_o && waited < TIMEOUT_CYCLES) begin
      @(posedge clk_i);
      #1;
      waited++;
    end

    if (!valid_o) begin
      $display("[FAIL] case=%0d timeout", idx);
      fail_cnt++;
    end else if ((valid_op_o === exp_valid_op) &&
                 (!exp_valid_op ||
                  ((resp_o.result === exp_result) &&
                   (resp_o.fflags === exp_fflags) &&
                   (resp_o.tag === req.tag) &&
                   (resp_o.rd === req.rd)))) begin
      pass_cnt++;
    end else begin
      $display("[FAIL] case=%0d valid_op exp=%0b got=%0b result exp=0x%016h got=0x%016h fflags exp=0x%02h got=0x%02h tag exp=0x%02h got=0x%02h rd exp=%0d got=%0d",
               idx, exp_valid_op, valid_op_o,
               exp_result, resp_o.result,
               exp_fflags, resp_o.fflags,
               req.tag, resp_o.tag,
               req.rd, resp_o.rd);
      fail_cnt++;
    end
  endtask

  task automatic check_burst_output(
    inout logic [5:0] seen,
    inout int unsigned got
  );
    int unsigned idx;
    fpu_data_t   exp_result;
    fpu_fflags_t exp_fflags;

    if (valid_o) begin
      if (resp_o.tag < 8'h80 || resp_o.tag >= 8'h86) begin
        $display("[FAIL] burst unexpected tag=0x%02h", resp_o.tag);
        fail_cnt++;
      end else begin
        idx = resp_o.tag - 8'h80;
        if (seen[idx]) begin
          $display("[FAIL] burst duplicate tag=0x%02h", resp_o.tag);
          fail_cnt++;
        end else begin
          exp_result = expected_result(idx);
          exp_fflags = expected_fflags(idx);
          if ((valid_op_o === 1'b1) &&
              (resp_o.result === exp_result) &&
              (resp_o.fflags === exp_fflags) &&
              (resp_o.rd === idx[4:0])) begin
            seen[idx] = 1'b1;
            got++;
            pass_cnt++;
          end else begin
            $display("[FAIL] burst idx=%0d valid_op=%0b result exp=0x%016h got=0x%016h fflags exp=0x%02h got=0x%02h rd exp=%0d got=%0d",
                     idx, valid_op_o, exp_result, resp_o.result,
                     exp_fflags, resp_o.fflags, idx[4:0], resp_o.rd);
            fail_cnt++;
          end
        end
      end
    end
  endtask

  task automatic run_burst6;
    fpu_req_t    reqs [6];
    logic [5:0]  seen;
    int unsigned sent;
    int unsigned got;
    int unsigned waited;

    seen   = 6'd0;
    sent   = 0;
    got    = 0;
    waited = 0;

    for (int unsigned idx = 0; idx < 6; idx++) begin
      reqs[idx]     = case_req(idx);
      reqs[idx].tag = 8'h80 + idx[7:0];
      reqs[idx].rd  = idx[4:0];
    end

    while (sent < 6) begin
      @(posedge clk_i);
      #1;
      check_burst_output(seen, got);
      if (ready_o) begin
        valid_i = 1'b1;
        req_i   = reqs[sent];
        sent++;
      end else begin
        valid_i = 1'b0;
        req_i   = '0;
      end
    end

    @(posedge clk_i);
    #1;
    valid_i = 1'b0;
    req_i   = '0;

    while (got < 6 && waited < TIMEOUT_CYCLES) begin
      check_burst_output(seen, got);
      @(posedge clk_i);
      #1;
      waited++;
    end

    if (got != 6) begin
      $display("[FAIL] burst got=%0d expected=6 seen=0x%02h", got, seen);
      fail_cnt++;
    end
  endtask

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

`ifdef DUMP_FSDB
  initial begin
    $fsdbDumpfile("tb_fpu_div_pipe.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_div_pipe);
  end
`endif

  always @(posedge clk_i) begin
    if (rst_ni) begin
      cycle_cnt++;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      trace_accept_tag     <= 8'd0;
      trace_result_tag     <= 8'd0;
      trace_accept_s_src_a <= 32'd0;
      trace_accept_s_src_b <= 32'd0;
      trace_result_s       <= 32'd0;
      trace_accept_d_src_a <= 64'd0;
      trace_accept_d_src_b <= 64'd0;
      trace_result_d       <= 64'd0;

      for (int tag_idx = 0; tag_idx < 256; tag_idx++) begin
        trace_src_a_by_tag[tag_idx]  <= '0;
        trace_src_b_by_tag[tag_idx]  <= '0;
        trace_result_by_tag[tag_idx] <= '0;
        trace_fmt_by_tag[tag_idx]    <= FPU_FMT_S;
        trace_fflags_by_tag[tag_idx] <= '0;
      end
    end else begin
      if (valid_i && ready_o) begin
        trace_accept_tag     <= req_i.tag;
        trace_accept_s_src_a <= req_i.src_a[31:0];
        trace_accept_s_src_b <= req_i.src_b[31:0];
        trace_accept_d_src_a <= req_i.src_a;
        trace_accept_d_src_b <= req_i.src_b;

        trace_src_a_by_tag[req_i.tag] <= req_i.src_a;
        trace_src_b_by_tag[req_i.tag] <= req_i.src_b;
        trace_fmt_by_tag[req_i.tag]   <= req_i.rs_fmt;
      end

      if (valid_o) begin
        trace_result_tag                <= resp_o.tag;
        trace_result_s                  <= resp_o.result[31:0];
        trace_result_d                  <= resp_o.result;
        trace_result_by_tag[resp_o.tag] <= resp_o.result;
        trace_fflags_by_tag[resp_o.tag] <= resp_o.fflags;
      end
    end
  end

  initial begin
    rst_ni    = 1'b0;
    valid_i   = 1'b0;
    req_i     = '0;
    pass_cnt  = 0;
    fail_cnt  = 0;
    cycle_cnt = 0;
    random_pass_cnt = 0;
    random_result_fail_cnt = 0;
    random_nx_fail_cnt = 0;
    random_timeout_cnt = 0;
    random_print_cnt = 0;
    subnormal_pass_cnt = 0;
    subnormal_result_fail_cnt = 0;
    subnormal_nx_fail_cnt = 0;
    subnormal_timeout_cnt = 0;
    subnormal_print_cnt = 0;

    for (int unsigned fmt_idx = 0; fmt_idx < 2; fmt_idx++) begin
      for (int unsigned rm_idx = 0; rm_idx < 5; rm_idx++) begin
        random_result_fail_by_fmt_rm[fmt_idx][rm_idx] = 0;
        random_nx_fail_by_fmt_rm[fmt_idx][rm_idx] = 0;
        random_count_by_fmt_rm[fmt_idx][rm_idx] = 0;
        subnormal_result_fail_by_fmt_rm[fmt_idx][rm_idx] = 0;
        subnormal_nx_fail_by_fmt_rm[fmt_idx][rm_idx] = 0;
        subnormal_count_by_fmt_rm[fmt_idx][rm_idx] = 0;
      end
    end

    repeat (3) @(posedge clk_i);
    #1;
    rst_ni = 1'b1;

    for (int unsigned idx = 0; idx < NUM_CASES; idx++) begin
      run_case(idx);
    end

    run_burst6();
    run_random_vectors();

    repeat (4) @(posedge clk_i);

    $display("tb_fpu_div_pipe summary: pass=%0d fail=%0d cycles=%0d",
             pass_cnt, fail_cnt, cycle_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_div_pipe failed");
    end

    $finish;
  end

endmodule : tb_fpu_div_pipe
