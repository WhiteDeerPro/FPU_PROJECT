`timescale 1ns/1ps

module tb_fpu_mult_pipe;
  import fpu_pkg::*;

  localparam int unsigned NUM_CASES    = 10000;
  localparam int unsigned DRAIN_CYCLES = 4;

  typedef logic [201:0] mult_vec_t;

  logic      clk_i;
  logic      rst_ni;
  logic      valid_i;
  fpu_req_t  req_i;
  fpu_resp_t pipe_resp_o;
  logic      pipe_valid_o;
  logic      pipe_valid_op_o;
  fpu_resp_t ref_resp_o;
  logic      ref_valid_op_o;

  logic      exp_valid_0;
  logic      exp_valid_1;
  logic      exp_valid_2;
  logic      exp_valid_op_0;
  logic      exp_valid_op_1;
  logic      exp_valid_op_2;
  fpu_resp_t exp_resp_0;
  fpu_resp_t exp_resp_1;
  fpu_resp_t exp_resp_2;
  fpu_resp_t issue_exp_resp;
  logic      issue_exp_valid_op;

  int unsigned pass_cnt;
  int unsigned fail_cnt;
  int unsigned cycle_cnt;

  mult_vec_t random_vec [NUM_CASES];

  fpu_mult_unit u_ref (
    .req_i     (req_i),
    .resp_o    (ref_resp_o),
    .valid_op_o(ref_valid_op_o)
  );

  fpu_mult_unit_pipe u_dut (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (valid_i),
    .req_i     (req_i),
    .valid_o   (pipe_valid_o),
    .resp_o    (pipe_resp_o),
    .valid_op_o(pipe_valid_op_o)
  );

  function automatic fpu_data_t nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
  endfunction

  function automatic logic [63:0] mix64(input int unsigned idx, input logic [63:0] salt);
    logic [63:0] value;

    value = (64'h9e37_79b9_7f4a_7c15 * (idx + 64'd1)) ^ salt;
    value ^= value >> 12;
    value ^= value << 25;
    value ^= value >> 27;
    return value * 64'h2545_f491_4f6c_dd1d;
  endfunction

  function automatic fpu_req_t make_req(input int unsigned idx);
    fpu_req_t     req;
    logic [63:0]  bits_a;
    logic [63:0]  bits_b;
    logic [31:0]  bits_s_a;
    logic [31:0]  bits_s_b;

    req      = '0;
    bits_a   = mix64(idx, 64'h0123_4567_89ab_cdef);
    bits_b   = mix64(idx, 64'hfedc_ba98_7654_3210);
    bits_s_a = bits_a[31:0];
    bits_s_b = bits_b[31:0];

    req.op      = FPU_OP_MUL;
    req.rs_fmt  = idx[0] ? FPU_FMT_D : FPU_FMT_S;
    req.dst_fmt = req.rs_fmt;
    req.rm      = FPU_RM_RNE;
    req.tag     = idx[7:0];
    req.rd      = idx[4:0];

    unique case (idx)
      0: begin
        req.rs_fmt  = FPU_FMT_S;
        req.dst_fmt = FPU_FMT_S;
        req.src_a   = nanbox_s(32'h3fc0_0000);
        req.src_b   = nanbox_s(32'h4000_0000);
      end

      1: begin
        req.rs_fmt  = FPU_FMT_S;
        req.dst_fmt = FPU_FMT_S;
        req.src_a   = nanbox_s(32'h7f80_0000);
        req.src_b   = nanbox_s(32'h0000_0000);
      end

      2: begin
        req.rs_fmt  = FPU_FMT_D;
        req.dst_fmt = FPU_FMT_D;
        req.src_a   = 64'h3ff8_0000_0000_0000;
        req.src_b   = 64'h4000_0000_0000_0000;
      end

      3: begin
        req.rs_fmt  = FPU_FMT_D;
        req.dst_fmt = FPU_FMT_D;
        req.src_a   = 64'h7ff0_0000_0000_0000;
        req.src_b   = 64'h0000_0000_0000_0000;
      end

      4: begin
        req.rs_fmt  = FPU_FMT_S;
        req.dst_fmt = FPU_FMT_S;
        req.src_a   = {32'h0000_0000, 32'h3f80_0000};
        req.src_b   = nanbox_s(32'h4000_0000);
      end

      5: begin
        req.op      = FPU_OP_ADD;
        req.rs_fmt  = FPU_FMT_S;
        req.dst_fmt = FPU_FMT_S;
        req.src_a   = nanbox_s(32'h3f80_0000);
        req.src_b   = nanbox_s(32'h3f80_0000);
      end

      default: begin
        if (req.rs_fmt == FPU_FMT_S) begin
          req.src_a = nanbox_s(bits_s_a);
          req.src_b = nanbox_s(bits_s_b);
        end else begin
          req.src_a = bits_a;
          req.src_b = bits_b;
        end

        unique case (idx[5:3])
          3'd0: req.rm = FPU_RM_RNE;
          3'd1: req.rm = FPU_RM_RTZ;
          3'd2: req.rm = FPU_RM_RDN;
          3'd3: req.rm = FPU_RM_RUP;
          3'd4: req.rm = FPU_RM_RMM;
          3'd5: req.rm = FPU_RM_DYN;
          default: req.rm = fpu_rm_e'(3'b101);
        endcase
      end
    endcase

    return req;
  endfunction

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

`ifdef DUMP_FSDB
  initial begin
    $fsdbDumpfile("tb_fpu_mult_pipe.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_mult_pipe);
  end
`endif

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      exp_valid_0    <= 1'b0;
      exp_valid_1    <= 1'b0;
      exp_valid_2    <= 1'b0;
      exp_valid_op_0 <= 1'b0;
      exp_valid_op_1 <= 1'b0;
      exp_valid_op_2 <= 1'b0;
      exp_resp_0     <= '0;
      exp_resp_1     <= '0;
      exp_resp_2     <= '0;
    end else begin
      exp_valid_0    <= valid_i;
      exp_valid_1    <= exp_valid_0;
      exp_valid_2    <= exp_valid_1;
      exp_valid_op_0 <= issue_exp_valid_op;
      exp_valid_op_1 <= exp_valid_op_0;
      exp_valid_op_2 <= exp_valid_op_1;
      exp_resp_0     <= issue_exp_resp;
      exp_resp_1     <= exp_resp_0;
      exp_resp_2     <= exp_resp_1;
    end
  end

  always @(posedge clk_i) begin
    #2;
    if (rst_ni) begin
      cycle_cnt++;
      if (pipe_valid_o !== exp_valid_2) begin
        $display("FAIL cycle=%0d valid_o=%0b expected=%0b",
                 cycle_cnt, pipe_valid_o, exp_valid_2);
        fail_cnt++;
      end else if (pipe_valid_o) begin
        if ((pipe_valid_op_o === exp_valid_op_2) &&
            (pipe_resp_o.result === exp_resp_2.result) &&
            (pipe_resp_o.fflags === exp_resp_2.fflags) &&
            (pipe_resp_o.tag === exp_resp_2.tag) &&
            (pipe_resp_o.rd === exp_resp_2.rd)) begin
          pass_cnt++;
        end else begin
          $display("FAIL cycle=%0d valid_op exp=%0b got=%0b result exp=0x%016h got=0x%016h fflags exp=0x%02h got=0x%02h tag exp=0x%02h got=0x%02h rd exp=%0d got=%0d",
                   cycle_cnt, exp_valid_op_2, pipe_valid_op_o,
                   exp_resp_2.result, pipe_resp_o.result,
                   exp_resp_2.fflags, pipe_resp_o.fflags,
                   exp_resp_2.tag, pipe_resp_o.tag,
                   exp_resp_2.rd, pipe_resp_o.rd);
          fail_cnt++;
        end
      end
    end
  end

  initial begin
    rst_ni    = 1'b0;
    valid_i   = 1'b0;
    req_i     = '0;
    issue_exp_resp = '0;
    issue_exp_valid_op = 1'b0;
    pass_cnt  = 0;
    fail_cnt  = 0;
    cycle_cnt = 0;

    repeat (3) @(posedge clk_i);
    #1;
    rst_ni = 1'b1;

    $readmemh("../tb/fpu_mult_random_cases.mem", random_vec);

    for (int unsigned case_idx = 0; case_idx < NUM_CASES; case_idx++) begin
      logic        fmt_bit;
      logic [2:0]  rm_bits;
      fpu_data_t   src_a;
      fpu_data_t   src_b;
      fpu_data_t   exp_result;
      fpu_fflags_t exp_fflags;
      logic        exp_valid_op;

      {fmt_bit, rm_bits, src_a, src_b, exp_result, exp_fflags, exp_valid_op} = random_vec[case_idx];

      @(posedge clk_i);
      #1;
      valid_i = 1'b1;
      req_i   = '0;
      req_i.op      = FPU_OP_MUL;
      req_i.rs_fmt  = fmt_bit ? FPU_FMT_D : FPU_FMT_S;
      req_i.dst_fmt = req_i.rs_fmt;
      unique case (rm_bits)
        3'd0: req_i.rm = FPU_RM_RNE;
        3'd1: req_i.rm = FPU_RM_RTZ;
        3'd2: req_i.rm = FPU_RM_RDN;
        3'd3: req_i.rm = FPU_RM_RUP;
        3'd4: req_i.rm = FPU_RM_RMM;
        default: req_i.rm = FPU_RM_RNE;
      endcase
      req_i.src_a = src_a;
      req_i.src_b = src_b;
      req_i.tag   = case_idx[7:0];
      req_i.rd    = case_idx[4:0];

      issue_exp_valid_op = exp_valid_op;
      issue_exp_resp = '0;
      issue_exp_resp.result = exp_result;
      issue_exp_resp.fflags = exp_fflags;
      issue_exp_resp.tag    = case_idx[7:0];
      issue_exp_resp.rd     = case_idx[4:0];
    end

    @(posedge clk_i);
    #1;
    valid_i = 1'b0;
    req_i   = '0;
    issue_exp_valid_op = 1'b0;
    issue_exp_resp = '0;

    repeat (DRAIN_CYCLES) @(posedge clk_i);

    $display("tb_fpu_mult_pipe summary: pass=%0d fail=%0d",
             pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_mult_pipe failed");
    end

    $finish;
  end

endmodule : tb_fpu_mult_pipe
