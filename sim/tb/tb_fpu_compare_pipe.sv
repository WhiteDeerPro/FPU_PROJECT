`timescale 1ns/1ps

module tb_fpu_compare_pipe;
  import fpu_pkg::*;

  localparam int unsigned NUM_CASES    = 192;
  localparam int unsigned DRAIN_CYCLES = 3;

  logic      clk_i;
  logic      rst_ni;
  logic      valid_i;
  fpu_req_t  req_i;
  fpu_resp_t pipe_resp_o;
  logic      pipe_valid_o;
  logic      pipe_valid_op_o;
  fpu_resp_t ref_resp_o;
  logic      ref_valid_op_o;

  logic      exp_valid;
  logic      exp_valid_op;
  fpu_resp_t exp_resp;

  int unsigned pass_cnt;
  int unsigned fail_cnt;
  int unsigned cycle_cnt;

  fpu_compare_unit u_ref (
    .req_i     (req_i),
    .resp_o    (ref_resp_o),
    .valid_op_o(ref_valid_op_o)
  );

  fpu_compare_unit_pipe u_dut (
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

    value = (64'hd6e8_feb8_6659_fd93 * (idx + 64'd5)) ^ salt;
    value ^= value >> 11;
    value ^= value << 31;
    value ^= value >> 19;
    return value;
  endfunction

  function automatic fpu_op_e cmp_op(input int unsigned idx);
    unique case (idx % 7)
      0: return FPU_OP_EQ;
      1: return FPU_OP_LT;
      2: return FPU_OP_LE;
      3: return FPU_OP_MIN;
      4: return FPU_OP_MAX;
      5: return FPU_OP_CLASS;
      default: return FPU_OP_ADD;
    endcase
  endfunction

  function automatic fpu_req_t make_req(input int unsigned idx);
    fpu_req_t    req;
    logic [63:0] bits_a;
    logic [63:0] bits_b;

    req      = '0;
    bits_a   = mix64(idx, 64'h0123_4567_89ab_cdef);
    bits_b   = mix64(idx, 64'hfedc_ba98_7654_3210);

    req.op      = cmp_op(idx);
    req.rs_fmt  = idx[0] ? FPU_FMT_D : FPU_FMT_S;
    req.dst_fmt = req.rs_fmt;
    req.rm      = FPU_RM_RNE;
    req.tag     = idx[7:0];
    req.rd      = idx[4:0];

    unique case (idx)
      0: begin
        req.op      = FPU_OP_EQ;
        req.rs_fmt  = FPU_FMT_S;
        req.dst_fmt = FPU_FMT_S;
        req.src_a   = nanbox_s(32'h3f80_0000);
        req.src_b   = nanbox_s(32'h3f80_0000);
      end

      1: begin
        req.op      = FPU_OP_LT;
        req.rs_fmt  = FPU_FMT_S;
        req.dst_fmt = FPU_FMT_S;
        req.src_a   = nanbox_s(32'hbf80_0000);
        req.src_b   = nanbox_s(32'h0000_0000);
      end

      2: begin
        req.op      = FPU_OP_MIN;
        req.rs_fmt  = FPU_FMT_S;
        req.dst_fmt = FPU_FMT_S;
        req.src_a   = nanbox_s(32'h8000_0000);
        req.src_b   = nanbox_s(32'h0000_0000);
      end

      3: begin
        req.op      = FPU_OP_CLASS;
        req.rs_fmt  = FPU_FMT_D;
        req.dst_fmt = FPU_FMT_D;
        req.src_a   = 64'h7ff8_0000_0000_0001;
        req.src_b   = 64'd0;
      end

      4: begin
        req.op      = FPU_OP_LE;
        req.rs_fmt  = FPU_FMT_D;
        req.dst_fmt = FPU_FMT_D;
        req.src_a   = 64'hfff0_0000_0000_0000;
        req.src_b   = 64'h7ff0_0000_0000_0000;
      end

      5: begin
        req.op      = FPU_OP_MAX;
        req.rs_fmt  = FPU_FMT_S;
        req.dst_fmt = FPU_FMT_S;
        req.src_a   = {32'h0000_0000, 32'h3f80_0000};
        req.src_b   = nanbox_s(32'h4000_0000);
      end

      default: begin
        if (req.rs_fmt == FPU_FMT_S) begin
          req.src_a = nanbox_s(bits_a[31:0]);
          req.src_b = nanbox_s(bits_b[31:0]);
        end else begin
          req.src_a = bits_a;
          req.src_b = bits_b;
        end
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
    $fsdbDumpfile("tb_fpu_compare_pipe.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_compare_pipe);
  end
`endif

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      exp_valid    <= 1'b0;
      exp_valid_op <= 1'b0;
      exp_resp     <= '0;
    end else begin
      exp_valid    <= valid_i;
      exp_valid_op <= ref_valid_op_o;
      exp_resp     <= ref_resp_o;
    end
  end

  always @(posedge clk_i) begin
    #2;
    if (rst_ni) begin
      cycle_cnt++;
      if (pipe_valid_o !== exp_valid) begin
        $display("FAIL cycle=%0d valid_o=%0b expected=%0b",
                 cycle_cnt, pipe_valid_o, exp_valid);
        fail_cnt++;
      end else if (pipe_valid_o) begin
        if ((pipe_valid_op_o === exp_valid_op) &&
            (pipe_resp_o.result === exp_resp.result) &&
            (pipe_resp_o.fflags === exp_resp.fflags) &&
            (pipe_resp_o.tag === exp_resp.tag) &&
            (pipe_resp_o.rd === exp_resp.rd)) begin
          pass_cnt++;
        end else begin
          $display("FAIL cycle=%0d valid_op exp=%0b got=%0b result exp=0x%016h got=0x%016h fflags exp=0x%02h got=0x%02h tag exp=0x%02h got=0x%02h rd exp=%0d got=%0d",
                   cycle_cnt, exp_valid_op, pipe_valid_op_o,
                   exp_resp.result, pipe_resp_o.result,
                   exp_resp.fflags, pipe_resp_o.fflags,
                   exp_resp.tag, pipe_resp_o.tag,
                   exp_resp.rd, pipe_resp_o.rd);
          fail_cnt++;
        end
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

    repeat (3) @(posedge clk_i);
    #1;
    rst_ni = 1'b1;

    for (int unsigned case_idx = 0; case_idx < NUM_CASES; case_idx++) begin
      @(posedge clk_i);
      #1;
      valid_i = (case_idx[3:0] != 4'd5);
      req_i   = make_req(case_idx);
    end

    @(posedge clk_i);
    #1;
    valid_i = 1'b0;
    req_i   = '0;

    repeat (DRAIN_CYCLES) @(posedge clk_i);

    $display("tb_fpu_compare_pipe summary: pass=%0d fail=%0d",
             pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_compare_pipe failed");
    end

    $finish;
  end

endmodule : tb_fpu_compare_pipe
