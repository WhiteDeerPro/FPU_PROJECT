`timescale 1ns/1ps

module tb_fpu_fma_pipe;
  import fpu_pkg::*;

  localparam int unsigned LATENCY      = 5;
  localparam int unsigned NUM_CASES    = 192;
  localparam int unsigned DRAIN_CYCLES = LATENCY + 3;

  logic      clk_i;
  logic      rst_ni;
  logic      valid_i;
  fpu_req_t  req_i;
  fpu_resp_t pipe_resp_o;
  logic      pipe_valid_o;
  logic      pipe_valid_op_o;
  fpu_resp_t ref_resp_o;
  logic      ref_valid_op_o;

  logic      exp_valid    [LATENCY];
  logic      exp_valid_op [LATENCY];
  fpu_resp_t exp_resp     [LATENCY];

  int unsigned pass_cnt;
  int unsigned fail_cnt;
  int unsigned cycle_cnt;

  fpu_fma_unit u_ref (
    .req_i     (req_i),
    .resp_o    (ref_resp_o),
    .valid_op_o(ref_valid_op_o)
  );

  fpu_fma_unit_pipe u_dut (
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

    value = (64'hd1b5_4a32_d192_ed03 * (idx + 64'd11)) ^ salt;
    value ^= value >> 17;
    value ^= value << 31;
    value ^= value >> 29;
    return value;
  endfunction

  function automatic fpu_rm_e rm_sel(input int unsigned idx);
    unique case (idx[6:4])
      3'd0: return FPU_RM_RNE;
      3'd1: return FPU_RM_RTZ;
      3'd2: return FPU_RM_RDN;
      3'd3: return FPU_RM_RUP;
      3'd4: return FPU_RM_RMM;
      3'd5: return FPU_RM_DYN;
      default: return fpu_rm_e'(3'b101);
    endcase
  endfunction

  function automatic fpu_op_e fma_op_sel(input int unsigned idx);
    unique case (idx[3:2])
      2'd0: return FPU_OP_FMADD;
      2'd1: return FPU_OP_FMSUB;
      2'd2: return FPU_OP_FNMSUB;
      default: return FPU_OP_FNMADD;
    endcase
  endfunction

  function automatic fpu_req_t make_req(input int unsigned idx);
    fpu_req_t    req;
    logic [63:0] bits_a;
    logic [63:0] bits_b;
    logic [63:0] bits_c;

    req    = '0;
    bits_a = mix64(idx, 64'h0123_4567_89ab_cdef);
    bits_b = mix64(idx, 64'hfedc_ba98_7654_3210);
    bits_c = mix64(idx, 64'h55aa_5aa5_c33c_3cc3);

    req.op      = fma_op_sel(idx);
    req.rs_fmt  = idx[0] ? FPU_FMT_D : FPU_FMT_S;
    req.dst_fmt = req.rs_fmt;
    req.rm      = rm_sel(idx);
    req.src_a   = bits_a;
    req.src_b   = bits_b;
    req.src_c   = bits_c;
    req.tag     = idx[7:0];
    req.rd      = idx[4:0];

    if (req.rs_fmt == FPU_FMT_S) begin
      req.src_a = nanbox_s(bits_a[31:0]);
      req.src_b = nanbox_s(bits_b[31:0]);
      req.src_c = nanbox_s(bits_c[31:0]);
    end

    unique case (idx)
      0: begin
        req.op      = FPU_OP_FMADD;
        req.rs_fmt  = FPU_FMT_S;
        req.dst_fmt = FPU_FMT_S;
        req.rm      = FPU_RM_RNE;
        req.src_a   = nanbox_s(32'h3fc0_0000);
        req.src_b   = nanbox_s(32'h4000_0000);
        req.src_c   = nanbox_s(32'h3f00_0000);
      end

      1: begin
        req.op      = FPU_OP_FMSUB;
        req.rs_fmt  = FPU_FMT_D;
        req.dst_fmt = FPU_FMT_D;
        req.rm      = FPU_RM_RNE;
        req.src_a   = 64'h3ff8_0000_0000_0000;
        req.src_b   = 64'h4000_0000_0000_0000;
        req.src_c   = 64'h3fe0_0000_0000_0000;
      end

      2: begin
        req.op      = FPU_OP_FNMSUB;
        req.rs_fmt  = FPU_FMT_D;
        req.dst_fmt = FPU_FMT_D;
        req.rm      = FPU_RM_RNE;
        req.src_a   = 64'h3ff8_0000_0000_0000;
        req.src_b   = 64'h4000_0000_0000_0000;
        req.src_c   = 64'h3fe0_0000_0000_0000;
      end

      3: begin
        req.op      = FPU_OP_FNMADD;
        req.rs_fmt  = FPU_FMT_D;
        req.dst_fmt = FPU_FMT_D;
        req.rm      = FPU_RM_RNE;
        req.src_a   = 64'h3ff8_0000_0000_0000;
        req.src_b   = 64'h4000_0000_0000_0000;
        req.src_c   = 64'h3fe0_0000_0000_0000;
      end

      4: begin
        req.op      = FPU_OP_FMADD;
        req.rs_fmt  = FPU_FMT_D;
        req.dst_fmt = FPU_FMT_D;
        req.rm      = FPU_RM_RNE;
        req.src_a   = 64'h7ff0_0000_0000_0000;
        req.src_b   = 64'h0000_0000_0000_0000;
        req.src_c   = 64'h3ff0_0000_0000_0000;
      end

      5: begin
        req.op      = FPU_OP_MUL;
        req.rs_fmt  = FPU_FMT_D;
        req.dst_fmt = FPU_FMT_D;
        req.rm      = FPU_RM_RNE;
        req.src_a   = 64'h3ff0_0000_0000_0000;
        req.src_b   = 64'h3ff0_0000_0000_0000;
        req.src_c   = 64'h3ff0_0000_0000_0000;
      end

      default: begin end
    endcase

    return req;
  endfunction

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

`ifdef DUMP_FSDB
  initial begin
    $fsdbDumpfile("tb_fpu_fma_pipe.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_fma_pipe);
  end
`endif

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int unsigned pipe_idx = 0; pipe_idx < LATENCY; pipe_idx++) begin
        exp_valid[pipe_idx]    <= 1'b0;
        exp_valid_op[pipe_idx] <= 1'b0;
        exp_resp[pipe_idx]     <= '0;
      end
    end else begin
      exp_valid[0]    <= valid_i;
      exp_valid_op[0] <= ref_valid_op_o;
      exp_resp[0]     <= ref_resp_o;

      for (int unsigned pipe_idx = 1; pipe_idx < LATENCY; pipe_idx++) begin
        exp_valid[pipe_idx]    <= exp_valid[pipe_idx-1];
        exp_valid_op[pipe_idx] <= exp_valid_op[pipe_idx-1];
        exp_resp[pipe_idx]     <= exp_resp[pipe_idx-1];
      end
    end
  end

  always @(posedge clk_i) begin
    #2;
    if (rst_ni) begin
      cycle_cnt++;
      if (pipe_valid_o !== exp_valid[LATENCY-1]) begin
        $display("FAIL cycle=%0d valid_o=%0b expected=%0b",
                 cycle_cnt, pipe_valid_o, exp_valid[LATENCY-1]);
        fail_cnt++;
      end else if (pipe_valid_o) begin
        if ((pipe_valid_op_o === exp_valid_op[LATENCY-1]) &&
            (pipe_resp_o.result === exp_resp[LATENCY-1].result) &&
            (pipe_resp_o.fflags === exp_resp[LATENCY-1].fflags) &&
            (pipe_resp_o.tag === exp_resp[LATENCY-1].tag) &&
            (pipe_resp_o.rd === exp_resp[LATENCY-1].rd)) begin
          pass_cnt++;
        end else begin
          $display("FAIL cycle=%0d valid_op exp=%0b got=%0b result exp=0x%016h got=0x%016h fflags exp=0x%02h got=0x%02h tag exp=0x%02h got=0x%02h rd exp=%0d got=%0d",
                   cycle_cnt, exp_valid_op[LATENCY-1], pipe_valid_op_o,
                   exp_resp[LATENCY-1].result, pipe_resp_o.result,
                   exp_resp[LATENCY-1].fflags, pipe_resp_o.fflags,
                   exp_resp[LATENCY-1].tag, pipe_resp_o.tag,
                   exp_resp[LATENCY-1].rd, pipe_resp_o.rd);
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
      valid_i = (case_idx[4:0] != 5'd17);
      req_i   = make_req(case_idx);
    end

    @(posedge clk_i);
    #1;
    valid_i = 1'b0;
    req_i   = '0;

    repeat (DRAIN_CYCLES) @(posedge clk_i);

    $display("tb_fpu_fma_pipe summary: pass=%0d fail=%0d",
             pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_fma_pipe failed");
    end

    $finish;
  end

endmodule : tb_fpu_fma_pipe
