`timescale 1ns/1ps

module tb_fpu_div_pipe;
  import fpu_pkg::*;

  localparam int unsigned NUM_CASES = 18;
  localparam int unsigned TIMEOUT_CYCLES = 160;

  logic      clk_i;
  logic      rst_ni;
  logic      valid_i;
  fpu_req_t  req_i;
  logic      valid_o;
  fpu_resp_t resp_o;
  logic      valid_op_o;

  int unsigned pass_cnt;
  int unsigned fail_cnt;
  int unsigned cycle_cnt;

  fpu_div_unit_pipe u_dut (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (valid_i),
    .req_i     (req_i),
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
      default: return make_req(FPU_FMT_D, FPU_RM_RNE,
                               64'h4024_0000_0000_0000,  // 10.0
                               64'h4008_0000_0000_0000,  // 3.0
                               idx);
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
      default: return 64'h400a_aaaa_aaaa_aaab;    // 10.0 / 3.0
    endcase
  endfunction

  function automatic fpu_fflags_t expected_fflags(input int unsigned idx);
    fpu_fflags_t flags;

    flags = '0;
    unique case (idx)
      7, 14: flags[FPU_FFLAG_DZ] = 1'b1;
      8, 9, 13: flags[FPU_FFLAG_NV] = 1'b1;
      17:       flags[FPU_FFLAG_NX] = 1'b1;
      default: begin end
    endcase

    return flags;
  endfunction

  function automatic logic expected_valid_op(input int unsigned idx);
    return (idx != 16);
  endfunction

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

  initial begin
    rst_ni    = 1'b0;
    valid_i   = 1'b0;
    req_i     = '0;
    pass_cnt  = 0;
    fail_cnt  = 0;
    cycle_cnt = 0;

    repeat (3) @(posedge clk_i);
    #1;
    rst_ni = 1'b1;

    for (int unsigned idx = 0; idx < NUM_CASES; idx++) begin
      run_case(idx);
    end

    repeat (4) @(posedge clk_i);

    $display("tb_fpu_div_pipe summary: pass=%0d fail=%0d cycles=%0d",
             pass_cnt, fail_cnt, cycle_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_div_pipe failed");
    end

    $finish;
  end

endmodule : tb_fpu_div_pipe
