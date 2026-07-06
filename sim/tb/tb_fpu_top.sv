`timescale 1ns/1ps

module tb_fpu_top;
  import fpu_pkg::*;

  localparam int unsigned NUM_CASES     = 192;
  localparam int unsigned DRAIN_CYCLES  = 520;
  localparam int unsigned TIMEOUT_CYCLES = 4000;

  logic      clk_i;
  logic      rst_ni;
  logic      valid_i;
  fpu_req_t  req_i;
  logic      ready_o;
  logic      valid_o;
  fpu_resp_t resp_o;
  logic      valid_op_o;

  fpu_resp_t add_resp;
  fpu_resp_t mult_resp;
  fpu_resp_t fma_resp;
  fpu_resp_t div_resp;
  fpu_resp_t sqrt_resp;
  fpu_resp_t convert_resp;
  fpu_resp_t compare_resp;
  fpu_resp_t sgnj_resp_w;
  fpu_resp_t sgnj_resp_q;
  fpu_resp_t move_resp_w;
  fpu_resp_t move_resp_q;
  fpu_resp_t exp_resp_d;
  fpu_resp_t exp_resp_q;

  logic add_valid;
  logic mult_valid;
  logic fma_valid;
  logic div_valid;
  logic sqrt_valid;
  logic convert_valid;
  logic compare_valid;
  logic sgnj_valid_q;
  logic move_valid_q;

  logic add_valid_op;
  logic mult_valid_op;
  logic fma_valid_op;
  logic div_valid_op;
  logic sqrt_valid_op;
  logic convert_valid_op;
  logic compare_valid_op;
  logic sgnj_valid_op_w;
  logic sgnj_valid_op_q;
  logic move_valid_op_w;
  logic move_valid_op_q;

  logic exp_valid_d;
  logic exp_valid_q;
  logic exp_valid_op_d;
  logic exp_valid_op_q;

  logic op_addsub;
  logic op_mul;
  logic op_fma;
  logic op_div;
  logic op_sqrt;
  logic op_convert;
  logic op_compare;
  logic op_sgnj;
  logic op_move;
  logic issue_valid;

  logic ref_div_ready;
  logic ref_sqrt_ready;

  int unsigned pass_cnt;
  int unsigned fail_cnt;
  int unsigned cycle_cnt;
  int unsigned issue_cnt;
  int unsigned wait_cnt;
  int unsigned case_idx;
  int unsigned drain_cnt;
  logic        accepted;
  string       dbg_case_name;

  logic        dbg_valid_i;
  logic        dbg_ready_o;
  logic        dbg_issue_valid;
  logic        dbg_valid_o;
  logic        dbg_valid_op_o;
  logic [5:0]  dbg_op;
  logic [1:0]  dbg_rs_fmt;
  logic [1:0]  dbg_dst_fmt;
  logic [1:0]  dbg_int_fmt;
  logic [2:0]  dbg_rm;
  logic [7:0]  dbg_req_tag;
  logic [4:0]  dbg_req_rd;
  logic [63:0] dbg_src_a;
  logic [63:0] dbg_src_b;
  logic [63:0] dbg_src_c;
  logic [63:0] dbg_result;
  logic [4:0]  dbg_fflags;
  logic [7:0]  dbg_resp_tag;
  logic [4:0]  dbg_resp_rd;
  logic [31:0] dbg_s_src_a;
  logic [31:0] dbg_s_src_b;
  logic [31:0] dbg_s_src_c;
  logic [31:0] dbg_s_result;
  logic [63:0] dbg_d_src_a;
  logic [63:0] dbg_d_src_b;
  logic [63:0] dbg_d_src_c;
  logic [63:0] dbg_d_result;
  real         dbg_d_src_a_real;
  real         dbg_d_src_b_real;
  real         dbg_d_src_c_real;
  real         dbg_d_result_real;
  real         dbg_s_src_a_real;
  real         dbg_s_src_b_real;
  real         dbg_s_src_c_real;
  real         dbg_s_result_real;

  logic [8:0]  dbg_unit_valids;
  logic [8:0]  dbg_unit_valid_ops;
  logic [8:0]  dbg_unit_select;
  logic        dbg_top_add_valid;
  logic        dbg_top_mult_valid;
  logic        dbg_top_fma_valid;
  logic        dbg_top_div_valid;
  logic        dbg_top_sqrt_valid;
  logic        dbg_top_convert_valid;
  logic        dbg_top_compare_valid;
  logic        dbg_top_sgnj_valid;
  logic        dbg_top_move_valid;

  fpu_top u_dut (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (valid_i),
    .req_i     (req_i),
    .ready_o   (ready_o),
    .valid_o   (valid_o),
    .resp_o    (resp_o),
    .valid_op_o(valid_op_o)
  );

  assign op_addsub  = (req_i.op == FPU_OP_ADD) || (req_i.op == FPU_OP_SUB);
  assign op_mul     = (req_i.op == FPU_OP_MUL);
  assign op_fma     = (req_i.op == FPU_OP_FMADD)  ||
                      (req_i.op == FPU_OP_FMSUB)  ||
                      (req_i.op == FPU_OP_FNMSUB) ||
                      (req_i.op == FPU_OP_FNMADD);
  assign op_div     = (req_i.op == FPU_OP_DIV);
  assign op_sqrt    = (req_i.op == FPU_OP_SQRT);
  assign op_convert = (req_i.op == FPU_OP_CVT_FP)  ||
                      (req_i.op == FPU_OP_CVT_F2I) ||
                      (req_i.op == FPU_OP_CVT_I2F);
  assign op_compare = (req_i.op == FPU_OP_EQ)    ||
                      (req_i.op == FPU_OP_LT)    ||
                      (req_i.op == FPU_OP_LE)    ||
                      (req_i.op == FPU_OP_MIN)   ||
                      (req_i.op == FPU_OP_MAX)   ||
                      (req_i.op == FPU_OP_CLASS);
  assign op_sgnj    = (req_i.op == FPU_OP_SGNJ)  ||
                      (req_i.op == FPU_OP_SGNJN) ||
                      (req_i.op == FPU_OP_SGNJX);
  assign op_move    = (req_i.op == FPU_OP_MV_X_FP) ||
                      (req_i.op == FPU_OP_MV_FP_X);
  assign issue_valid = valid_i && ready_o;

  fpu_add_unit_pipe u_ref_add (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (issue_valid && op_addsub),
    .req_i     (req_i),
    .valid_o   (add_valid),
    .resp_o    (add_resp),
    .valid_op_o(add_valid_op)
  );

  fpu_mult_unit_pipe u_ref_mult (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (issue_valid && op_mul),
    .req_i     (req_i),
    .valid_o   (mult_valid),
    .resp_o    (mult_resp),
    .valid_op_o(mult_valid_op)
  );

  fpu_fma_unit_pipe u_ref_fma (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (issue_valid && op_fma),
    .req_i     (req_i),
    .valid_o   (fma_valid),
    .resp_o    (fma_resp),
    .valid_op_o(fma_valid_op)
  );

  fpu_div_unit_pipe u_ref_div (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (issue_valid && op_div),
    .req_i     (req_i),
    .ready_o   (ref_div_ready),
    .valid_o   (div_valid),
    .resp_o    (div_resp),
    .valid_op_o(div_valid_op)
  );

  fpu_sqrt_unit_pipe u_ref_sqrt (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (issue_valid && op_sqrt),
    .req_i     (req_i),
    .ready_o   (ref_sqrt_ready),
    .valid_o   (sqrt_valid),
    .resp_o    (sqrt_resp),
    .valid_op_o(sqrt_valid_op)
  );

  fpu_convert_unit_pipe u_ref_convert (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (issue_valid && op_convert),
    .req_i     (req_i),
    .valid_o   (convert_valid),
    .resp_o    (convert_resp),
    .valid_op_o(convert_valid_op)
  );

  fpu_compare_unit_pipe u_ref_compare (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .valid_i   (issue_valid && op_compare),
    .req_i     (req_i),
    .valid_o   (compare_valid),
    .resp_o    (compare_resp),
    .valid_op_o(compare_valid_op)
  );

  fpu_sgnj_unit u_ref_sgnj (
    .req_i     (req_i),
    .resp_o    (sgnj_resp_w),
    .valid_op_o(sgnj_valid_op_w)
  );

  function automatic fpu_data_t nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
  endfunction

  function automatic logic [63:0] mix64(input int unsigned idx, input logic [63:0] salt);
    logic [63:0] value;

    value = (64'h9e37_79b9_7f4a_7c15 * (idx + 64'd17)) ^ salt;
    value ^= value >> 12;
    value ^= value << 25;
    value ^= value >> 27;
    return value;
  endfunction

  function automatic fpu_rm_e rm_from_idx(input int unsigned idx);
    unique case (idx % 5)
      0: return FPU_RM_RNE;
      1: return FPU_RM_RTZ;
      2: return FPU_RM_RDN;
      3: return FPU_RM_RUP;
      default: return FPU_RM_RMM;
    endcase
  endfunction

  function automatic fpu_int_fmt_e int_fmt_from_idx(input int unsigned idx);
    unique case (idx[1:0])
      2'd0: return FPU_INT_W;
      2'd1: return FPU_INT_WU;
      2'd2: return FPU_INT_L;
      default: return FPU_INT_LU;
    endcase
  endfunction

  function automatic fpu_op_e op_from_idx(input int unsigned idx);
    unique case (idx % 20)
      0:  return FPU_OP_ADD;
      1:  return FPU_OP_SUB;
      2:  return FPU_OP_MUL;
      3:  return FPU_OP_FMADD;
      4:  return FPU_OP_FMSUB;
      5:  return FPU_OP_EQ;
      6:  return FPU_OP_LT;
      7:  return FPU_OP_LE;
      8:  return FPU_OP_MIN;
      9:  return FPU_OP_MAX;
      10: return FPU_OP_CLASS;
      11: return FPU_OP_SGNJ;
      12: return FPU_OP_SGNJN;
      13: return FPU_OP_SGNJX;
      14: return FPU_OP_CVT_FP;
      15: return FPU_OP_CVT_F2I;
      16: return FPU_OP_CVT_I2F;
      17: return FPU_OP_MV_X_FP;
      18: return FPU_OP_MV_FP_X;
      default: return idx[2] ? FPU_OP_SQRT : FPU_OP_DIV;
    endcase
  endfunction

  function automatic fpu_req_t make_req(input int unsigned idx);
    fpu_req_t    req;
    logic [63:0] bits_a;
    logic [63:0] bits_b;
    logic [63:0] bits_c;

    req      = '0;
    bits_a   = mix64(idx, 64'h0123_4567_89ab_cdef);
    bits_b   = mix64(idx, 64'hfedc_ba98_7654_3210);
    bits_c   = mix64(idx, 64'h55aa_aa55_00ff_ff00);

    req.op      = op_from_idx(idx);
    req.rs_fmt  = idx[0] ? FPU_FMT_D : FPU_FMT_S;
    req.dst_fmt = req.rs_fmt;
    req.int_fmt = int_fmt_from_idx(idx);
    req.rm      = rm_from_idx(idx);
    req.tag     = idx[7:0];
    req.rd      = idx[4:0];

    if (req.rs_fmt == FPU_FMT_S) begin
      req.src_a = nanbox_s(bits_a[31:0]);
      req.src_b = nanbox_s(bits_b[31:0]);
      req.src_c = nanbox_s(bits_c[31:0]);
    end else begin
      req.src_a = bits_a;
      req.src_b = bits_b;
      req.src_c = bits_c;
    end

    unique case (idx)
      0: begin
        req.op      = FPU_OP_ADD;
        req.rs_fmt  = FPU_FMT_S;
        req.dst_fmt = FPU_FMT_S;
        req.rm      = FPU_RM_RNE;
        req.src_a   = nanbox_s(32'h3f80_0000);
        req.src_b   = nanbox_s(32'h4000_0000);
      end

      1: begin
        req.op      = FPU_OP_SUB;
        req.rs_fmt  = FPU_FMT_D;
        req.dst_fmt = FPU_FMT_D;
        req.rm      = FPU_RM_RNE;
        req.src_a   = 64'h4008_0000_0000_0000;
        req.src_b   = 64'h3ff0_0000_0000_0000;
      end

      2: begin
        req.op      = FPU_OP_MUL;
        req.rs_fmt  = FPU_FMT_S;
        req.dst_fmt = FPU_FMT_S;
        req.rm      = FPU_RM_RNE;
        req.src_a   = nanbox_s(32'h3fc0_0000);
        req.src_b   = nanbox_s(32'h4000_0000);
      end

      3: begin
        req.op      = FPU_OP_FMADD;
        req.rs_fmt  = FPU_FMT_D;
        req.dst_fmt = FPU_FMT_D;
        req.rm      = FPU_RM_RNE;
        req.src_a   = 64'h3ff0_0000_0000_0000;
        req.src_b   = 64'h4000_0000_0000_0000;
        req.src_c   = 64'h3ff0_0000_0000_0000;
      end

      4: begin
        req.op      = FPU_OP_DIV;
        req.rs_fmt  = FPU_FMT_S;
        req.dst_fmt = FPU_FMT_S;
        req.rm      = FPU_RM_RNE;
        req.src_a   = nanbox_s(32'h40c0_0000);
        req.src_b   = nanbox_s(32'h4000_0000);
      end

      5: begin
        req.op      = FPU_OP_SQRT;
        req.rs_fmt  = FPU_FMT_D;
        req.dst_fmt = FPU_FMT_D;
        req.rm      = FPU_RM_RNE;
        req.src_a   = 64'h4010_0000_0000_0000;
      end

      6: begin
        req.op      = FPU_OP_CVT_F2I;
        req.rs_fmt  = FPU_FMT_S;
        req.dst_fmt = FPU_FMT_S;
        req.int_fmt = FPU_INT_W;
        req.rm      = FPU_RM_RTZ;
        req.src_a   = nanbox_s(32'h4120_0000);
      end

      7: begin
        req.op      = FPU_OP_CVT_I2F;
        req.rs_fmt  = FPU_FMT_D;
        req.dst_fmt = FPU_FMT_D;
        req.int_fmt = FPU_INT_L;
        req.rm      = FPU_RM_RNE;
        req.src_a   = 64'h0000_0000_0000_002a;
      end

      8: begin
        req.op      = FPU_OP_EQ;
        req.rs_fmt  = FPU_FMT_S;
        req.dst_fmt = FPU_FMT_S;
        req.src_a   = nanbox_s(32'h3f80_0000);
        req.src_b   = nanbox_s(32'h3f80_0000);
      end

      9: begin
        req.op      = FPU_OP_CLASS;
        req.rs_fmt  = FPU_FMT_D;
        req.dst_fmt = FPU_FMT_D;
        req.src_a   = 64'h7ff8_0000_0000_0001;
      end

      10: begin
        req.op      = FPU_OP_MV_FP_X;
        req.rs_fmt  = FPU_FMT_S;
        req.dst_fmt = FPU_FMT_S;
        req.src_a   = 64'h0000_0000_3f80_0000;
      end

      11: begin
        req.op      = FPU_OP_SGNJX;
        req.rs_fmt  = FPU_FMT_D;
        req.dst_fmt = FPU_FMT_D;
        req.src_a   = 64'hbff0_0000_0000_0000;
        req.src_b   = 64'h4000_0000_0000_0000;
      end

      default: begin
      end
    endcase

    return req;
  endfunction

  function automatic fpu_data_t move_result(input fpu_req_t req);
    if (req.op == FPU_OP_MV_X_FP) begin
      return (req.rs_fmt == FPU_FMT_S) ?
             {{32{req.src_a[31]}}, req.src_a[31:0]} :
             req.src_a;
    end

    if (req.op == FPU_OP_MV_FP_X) begin
      return (req.dst_fmt == FPU_FMT_S) ?
             nanbox_s(req.src_a[31:0]) :
             req.src_a;
    end

    return '0;
  endfunction

  function automatic logic move_valid_op(input fpu_req_t req);
    return ((req.op == FPU_OP_MV_X_FP) || (req.op == FPU_OP_MV_FP_X)) &&
           ((req.rs_fmt == FPU_FMT_S) || (req.rs_fmt == FPU_FMT_D));
  endfunction

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

`ifdef DUMP_FSDB
  initial begin
    $fsdbDumpfile("tb_fpu_top.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_top);
  end
`endif

  always_comb begin
    move_resp_w      = '0;
    move_resp_w.tag  = req_i.tag;
    move_resp_w.rd   = req_i.rd;
    move_valid_op_w  = move_valid_op(req_i);
    move_resp_w.result = move_result(req_i);
  end

  always_comb begin
    exp_valid_d    = 1'b0;
    exp_valid_op_d = 1'b0;
    exp_resp_d     = '0;
    dbg_unit_select = 9'd0;

    if (div_valid) begin
      exp_valid_d    = 1'b1;
      exp_valid_op_d = div_valid_op;
      exp_resp_d     = div_resp;
      dbg_unit_select[3] = 1'b1;
    end else if (sqrt_valid) begin
      exp_valid_d    = 1'b1;
      exp_valid_op_d = sqrt_valid_op;
      exp_resp_d     = sqrt_resp;
      dbg_unit_select[4] = 1'b1;
    end else if (fma_valid) begin
      exp_valid_d    = 1'b1;
      exp_valid_op_d = fma_valid_op;
      exp_resp_d     = fma_resp;
      dbg_unit_select[2] = 1'b1;
    end else if (mult_valid) begin
      exp_valid_d    = 1'b1;
      exp_valid_op_d = mult_valid_op;
      exp_resp_d     = mult_resp;
      dbg_unit_select[1] = 1'b1;
    end else if (add_valid) begin
      exp_valid_d    = 1'b1;
      exp_valid_op_d = add_valid_op;
      exp_resp_d     = add_resp;
      dbg_unit_select[0] = 1'b1;
    end else if (convert_valid) begin
      exp_valid_d    = 1'b1;
      exp_valid_op_d = convert_valid_op;
      exp_resp_d     = convert_resp;
      dbg_unit_select[5] = 1'b1;
    end else if (compare_valid) begin
      exp_valid_d    = 1'b1;
      exp_valid_op_d = compare_valid_op;
      exp_resp_d     = compare_resp;
      dbg_unit_select[6] = 1'b1;
    end else if (sgnj_valid_q) begin
      exp_valid_d    = 1'b1;
      exp_valid_op_d = sgnj_valid_op_q;
      exp_resp_d     = sgnj_resp_q;
      dbg_unit_select[7] = 1'b1;
    end else if (move_valid_q) begin
      exp_valid_d    = 1'b1;
      exp_valid_op_d = move_valid_op_q;
      exp_resp_d     = move_resp_q;
      dbg_unit_select[8] = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sgnj_valid_q    <= 1'b0;
      sgnj_valid_op_q <= 1'b0;
      sgnj_resp_q     <= '0;
      move_valid_q    <= 1'b0;
      move_valid_op_q <= 1'b0;
      move_resp_q     <= '0;
      exp_valid_q     <= 1'b0;
      exp_valid_op_q  <= 1'b0;
      exp_resp_q      <= '0;
    end else begin
      sgnj_valid_q    <= issue_valid && op_sgnj;
      sgnj_valid_op_q <= sgnj_valid_op_w;
      sgnj_resp_q     <= sgnj_resp_w;
      move_valid_q    <= issue_valid && op_move;
      move_valid_op_q <= move_valid_op_w;
      move_resp_q     <= move_resp_w;
      exp_valid_q     <= exp_valid_d;
      exp_valid_op_q  <= exp_valid_op_d;
      exp_resp_q      <= exp_resp_d;
    end
  end

  assign dbg_valid_i      = valid_i;
  assign dbg_ready_o      = ready_o;
  assign dbg_issue_valid  = issue_valid;
  assign dbg_valid_o      = valid_o;
  assign dbg_valid_op_o   = valid_op_o;
  assign dbg_op           = req_i.op;
  assign dbg_rs_fmt       = req_i.rs_fmt;
  assign dbg_dst_fmt      = req_i.dst_fmt;
  assign dbg_int_fmt      = req_i.int_fmt;
  assign dbg_rm           = req_i.rm;
  assign dbg_req_tag      = req_i.tag;
  assign dbg_req_rd       = req_i.rd;
  assign dbg_src_a        = req_i.src_a;
  assign dbg_src_b        = req_i.src_b;
  assign dbg_src_c        = req_i.src_c;
  assign dbg_result       = resp_o.result;
  assign dbg_fflags       = resp_o.fflags;
  assign dbg_resp_tag     = resp_o.tag;
  assign dbg_resp_rd      = resp_o.rd;
  assign dbg_s_src_a      = req_i.src_a[31:0];
  assign dbg_s_src_b      = req_i.src_b[31:0];
  assign dbg_s_src_c      = req_i.src_c[31:0];
  assign dbg_s_result     = resp_o.result[31:0];
  assign dbg_d_src_a      = req_i.src_a;
  assign dbg_d_src_b      = req_i.src_b;
  assign dbg_d_src_c      = req_i.src_c;
  assign dbg_d_result     = resp_o.result;
  assign dbg_unit_valids  = {move_valid_q, sgnj_valid_q, compare_valid,
                             convert_valid, sqrt_valid, div_valid,
                             fma_valid, mult_valid, add_valid};
  assign dbg_unit_valid_ops = {move_valid_op_q, sgnj_valid_op_q, compare_valid_op,
                               convert_valid_op, sqrt_valid_op, div_valid_op,
                               fma_valid_op, mult_valid_op, add_valid_op};
  assign dbg_top_add_valid     = u_dut.add_valid;
  assign dbg_top_mult_valid    = u_dut.mult_valid;
  assign dbg_top_fma_valid     = u_dut.fma_valid;
  assign dbg_top_div_valid     = u_dut.div_valid;
  assign dbg_top_sqrt_valid    = u_dut.sqrt_valid;
  assign dbg_top_convert_valid = u_dut.convert_valid;
  assign dbg_top_compare_valid = u_dut.compare_valid;
  assign dbg_top_sgnj_valid    = u_dut.sgnj_valid_q;
  assign dbg_top_move_valid    = u_dut.move_valid_q;

  always @* begin
    dbg_d_src_a_real  = $bitstoreal(req_i.src_a);
    dbg_d_src_b_real  = $bitstoreal(req_i.src_b);
    dbg_d_src_c_real  = $bitstoreal(req_i.src_c);
    dbg_d_result_real = $bitstoreal(resp_o.result);
    dbg_s_src_a_real  = $bitstoshortreal(req_i.src_a[31:0]);
    dbg_s_src_b_real  = $bitstoshortreal(req_i.src_b[31:0]);
    dbg_s_src_c_real  = $bitstoshortreal(req_i.src_c[31:0]);
    dbg_s_result_real = $bitstoshortreal(resp_o.result[31:0]);
  end

  always @(posedge clk_i) begin
    #2;
    if (rst_ni) begin
      cycle_cnt++;

      if (valid_o !== exp_valid_q) begin
        fail_cnt++;
        $display("[FAIL] cycle=%0d valid exp=%0b got=%0b",
                 cycle_cnt, exp_valid_q, valid_o);
      end else if (valid_o) begin
        if ((valid_op_o === exp_valid_op_q) &&
            (resp_o.result === exp_resp_q.result) &&
            (resp_o.fflags === exp_resp_q.fflags) &&
            (resp_o.tag === exp_resp_q.tag) &&
            (resp_o.rd === exp_resp_q.rd)) begin
          pass_cnt++;
          $display("[PASS] cycle=%0d tag=0x%02h rd=%0d result=0x%016h fflags=0x%02h",
                   cycle_cnt, resp_o.tag, resp_o.rd, resp_o.result, resp_o.fflags);
        end else begin
          fail_cnt++;
          $display("[FAIL] cycle=%0d valid_op exp=%0b got=%0b result exp=0x%016h got=0x%016h fflags exp=0x%02h got=0x%02h tag exp=0x%02h got=0x%02h rd exp=%0d got=%0d",
                   cycle_cnt, exp_valid_op_q, valid_op_o,
                   exp_resp_q.result, resp_o.result,
                   exp_resp_q.fflags, resp_o.fflags,
                   exp_resp_q.tag, resp_o.tag,
                   exp_resp_q.rd, resp_o.rd);
        end
      end

      if (cycle_cnt > TIMEOUT_CYCLES) begin
        $fatal(1, "tb_fpu_top timeout");
      end
    end
  end

  initial begin
    rst_ni        = 1'b0;
    valid_i       = 1'b0;
    req_i         = '0;
    pass_cnt      = 0;
    fail_cnt      = 0;
    cycle_cnt     = 0;
    issue_cnt     = 0;
    wait_cnt      = 0;
    case_idx      = 0;
    drain_cnt     = 0;
    accepted      = 1'b0;
    dbg_case_name = "reset";

    repeat (4) @(posedge clk_i);
    #1;
    rst_ni = 1'b1;

    for (case_idx = 0; case_idx < NUM_CASES; case_idx++) begin
      if ((case_idx[3:0] == 4'd9) || (case_idx[4:0] == 5'd17)) begin
        @(posedge clk_i);
        #1;
        valid_i = 1'b0;
        req_i   = '0;
        dbg_case_name = "random_gap";
      end

      req_i   = make_req(case_idx);
      valid_i = 1'b1;
      accepted = 1'b0;
      dbg_case_name = "issue";

      while (!accepted) begin
        @(posedge clk_i);
        #1;
        if (ready_o) begin
          issue_cnt++;
          valid_i = 1'b0;
          req_i   = '0;
          accepted = 1'b1;
          dbg_case_name = "accepted";
        end else begin
          wait_cnt++;
          dbg_case_name = "wait_ready";
        end
      end
    end

    @(posedge clk_i);
    #1;
    valid_i = 1'b0;
    req_i   = '0;
    dbg_case_name = "drain";

    repeat (DRAIN_CYCLES) begin
      @(posedge clk_i);
      drain_cnt++;
    end

    $display("tb_fpu_top summary: pass=%0d fail=%0d issued=%0d waits=%0d",
             pass_cnt, fail_cnt, issue_cnt, wait_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_top failed");
    end

    $finish;
  end

endmodule : tb_fpu_top
