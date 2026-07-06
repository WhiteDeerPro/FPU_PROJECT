`timescale 1ns/1ps

module tb_fpu_fma_pipe;
  import fpu_pkg::*;

  localparam int unsigned LATENCY      = 5;
  localparam int unsigned NUM_CASES    = 192;
  localparam int unsigned FMA_SUBNORMAL_VEC_COUNT = 10000;
  localparam int unsigned DRAIN_CYCLES = LATENCY + 3;

  typedef logic [260:0] fma_ext_vec_t;

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
  logic      exp_is_ext   [LATENCY];
  logic      exp_ext_fmt  [LATENCY];
  logic [2:0] exp_ext_rm  [LATENCY];
  fpu_resp_t exp_resp     [LATENCY];

  logic      ext_ref_mode;
  logic      ext_ref_fmt;
  logic [2:0] ext_ref_rm;
  fpu_resp_t ext_ref_resp;
  logic      ext_ref_valid_op;

  int unsigned pass_cnt;
  int unsigned fail_cnt;
  int unsigned cycle_cnt;
  int unsigned fma_subnormal_pass_cnt;
  int unsigned fma_subnormal_result_fail_cnt;
  int unsigned fma_subnormal_nx_fail_cnt;
  int unsigned fma_subnormal_result_fail_by_fmt_rm [2][5];
  int unsigned fma_subnormal_nx_fail_by_fmt_rm     [2][5];
  int unsigned fma_subnormal_count_by_fmt_rm       [2][5];

  fma_ext_vec_t fma_subnormal_vec [FMA_SUBNORMAL_VEC_COUNT];

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

  function automatic fpu_rm_e ext_rm_sel(input logic [2:0] rm_bits);
    unique case (rm_bits)
      3'd0: return FPU_RM_RNE;
      3'd1: return FPU_RM_RTZ;
      3'd2: return FPU_RM_RDN;
      3'd3: return FPU_RM_RUP;
      3'd4: return FPU_RM_RMM;
      default: return FPU_RM_RNE;
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
        exp_is_ext[pipe_idx]   <= 1'b0;
        exp_ext_fmt[pipe_idx]  <= 1'b0;
        exp_ext_rm[pipe_idx]   <= 3'd0;
        exp_resp[pipe_idx]     <= '0;
      end
    end else begin
      exp_valid[0]    <= valid_i;
      exp_valid_op[0] <= ext_ref_mode ? ext_ref_valid_op : ref_valid_op_o;
      exp_is_ext[0]   <= ext_ref_mode && valid_i;
      exp_ext_fmt[0]  <= ext_ref_fmt;
      exp_ext_rm[0]   <= ext_ref_rm;
      exp_resp[0]     <= ext_ref_mode ? ext_ref_resp : ref_resp_o;

      for (int unsigned pipe_idx = 1; pipe_idx < LATENCY; pipe_idx++) begin
        exp_valid[pipe_idx]    <= exp_valid[pipe_idx-1];
        exp_valid_op[pipe_idx] <= exp_valid_op[pipe_idx-1];
        exp_is_ext[pipe_idx]   <= exp_is_ext[pipe_idx-1];
        exp_ext_fmt[pipe_idx]  <= exp_ext_fmt[pipe_idx-1];
        exp_ext_rm[pipe_idx]   <= exp_ext_rm[pipe_idx-1];
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
            ((exp_is_ext[LATENCY-1] &&
              (pipe_resp_o.fflags[FPU_FFLAG_NX] ===
               exp_resp[LATENCY-1].fflags[FPU_FFLAG_NX])) ||
             (!exp_is_ext[LATENCY-1] &&
              (pipe_resp_o.fflags === exp_resp[LATENCY-1].fflags))) &&
            (pipe_resp_o.tag === exp_resp[LATENCY-1].tag) &&
            (pipe_resp_o.rd === exp_resp[LATENCY-1].rd)) begin
          pass_cnt++;
          if (exp_is_ext[LATENCY-1]) begin
            fma_subnormal_pass_cnt++;
          end
        end else begin
          if (exp_is_ext[LATENCY-1]) begin
            if (pipe_resp_o.result !== exp_resp[LATENCY-1].result) begin
              fma_subnormal_result_fail_cnt++;
              fma_subnormal_result_fail_by_fmt_rm[exp_ext_fmt[LATENCY-1]]
                                                  [exp_ext_rm[LATENCY-1]]++;
            end
            if (pipe_resp_o.fflags[FPU_FFLAG_NX] !==
                exp_resp[LATENCY-1].fflags[FPU_FFLAG_NX]) begin
              fma_subnormal_nx_fail_cnt++;
              fma_subnormal_nx_fail_by_fmt_rm[exp_ext_fmt[LATENCY-1]]
                                              [exp_ext_rm[LATENCY-1]]++;
            end
          end
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

  task automatic run_fma_subnormal_vectors;
    logic          fmt_bit;
    logic [2:0]    rm_bits;
    fpu_data_t     src_a;
    fpu_data_t     src_b;
    fpu_data_t     src_c;
    fpu_data_t     exp_result;
    logic          exp_nx;

    $readmemh("../tb/fpu_fma_subnormal_cases.mem", fma_subnormal_vec);
    ext_ref_mode = 1'b1;

    for (int unsigned vec_idx = 0; vec_idx < FMA_SUBNORMAL_VEC_COUNT; vec_idx++) begin
      {fmt_bit, rm_bits, src_a, src_b, src_c, exp_result, exp_nx} =
        fma_subnormal_vec[vec_idx];

      @(posedge clk_i);
      #1;
      valid_i = 1'b1;
      req_i = '0;
      req_i.op      = FPU_OP_FMADD;
      req_i.rs_fmt  = fmt_bit ? FPU_FMT_D : FPU_FMT_S;
      req_i.dst_fmt = req_i.rs_fmt;
      req_i.rm      = ext_rm_sel(rm_bits);
      req_i.src_a   = src_a;
      req_i.src_b   = src_b;
      req_i.src_c   = src_c;
      req_i.tag     = vec_idx[7:0];
      req_i.rd      = vec_idx[4:0];

      ext_ref_valid_op = 1'b1;
      ext_ref_fmt      = fmt_bit;
      ext_ref_rm       = rm_bits;
      ext_ref_resp     = '0;
      ext_ref_resp.result = exp_result;
      ext_ref_resp.fflags[FPU_FFLAG_NX] = exp_nx;
      ext_ref_resp.fflags[FPU_FFLAG_UF] = exp_nx;
      ext_ref_resp.tag = vec_idx[7:0];
      ext_ref_resp.rd  = vec_idx[4:0];

      fma_subnormal_count_by_fmt_rm[fmt_bit][rm_bits]++;
    end

    @(posedge clk_i);
    #1;
    valid_i = 1'b0;
    req_i   = '0;
    ext_ref_mode = 1'b0;
    ext_ref_resp = '0;
    ext_ref_valid_op = 1'b0;

    repeat (DRAIN_CYCLES) @(posedge clk_i);

    $display("tb_fpu_fma_pipe subnormal summary: total=%0d pass=%0d result_fail=%0d nx_fail=%0d",
             FMA_SUBNORMAL_VEC_COUNT, fma_subnormal_pass_cnt,
             fma_subnormal_result_fail_cnt, fma_subnormal_nx_fail_cnt);
    for (int unsigned fmt_idx = 0; fmt_idx < 2; fmt_idx++) begin
      for (int unsigned rm_idx = 0; rm_idx < 5; rm_idx++) begin
        $display("tb_fpu_fma_pipe subnormal bucket fmt=%0d rm=%0d count=%0d result_fail=%0d nx_fail=%0d",
                 fmt_idx, rm_idx, fma_subnormal_count_by_fmt_rm[fmt_idx][rm_idx],
                 fma_subnormal_result_fail_by_fmt_rm[fmt_idx][rm_idx],
                 fma_subnormal_nx_fail_by_fmt_rm[fmt_idx][rm_idx]);
      end
    end
  endtask

  initial begin
    rst_ni    = 1'b0;
    valid_i   = 1'b0;
    req_i     = '0;
    pass_cnt  = 0;
    fail_cnt  = 0;
    cycle_cnt = 0;
    ext_ref_mode = 1'b0;
    ext_ref_fmt = 1'b0;
    ext_ref_rm = 3'd0;
    ext_ref_resp = '0;
    ext_ref_valid_op = 1'b0;
    fma_subnormal_pass_cnt = 0;
    fma_subnormal_result_fail_cnt = 0;
    fma_subnormal_nx_fail_cnt = 0;
    for (int unsigned fmt_idx = 0; fmt_idx < 2; fmt_idx++) begin
      for (int unsigned rm_idx = 0; rm_idx < 5; rm_idx++) begin
        fma_subnormal_result_fail_by_fmt_rm[fmt_idx][rm_idx] = 0;
        fma_subnormal_nx_fail_by_fmt_rm[fmt_idx][rm_idx] = 0;
        fma_subnormal_count_by_fmt_rm[fmt_idx][rm_idx] = 0;
      end
    end

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

    run_fma_subnormal_vectors();

    $display("tb_fpu_fma_pipe summary: pass=%0d fail=%0d",
             pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_fma_pipe failed");
    end

    $finish;
  end

endmodule : tb_fpu_fma_pipe
