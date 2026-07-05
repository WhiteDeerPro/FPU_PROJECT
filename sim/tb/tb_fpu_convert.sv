`timescale 1ns/1ps

module tb_fpu_convert;
  import fpu_pkg::*;

  localparam fpu_fflags_t FFLAGS_NONE = 5'b0_0000;
  localparam fpu_fflags_t FFLAGS_NX   = 5'b0_0001;
  localparam fpu_fflags_t FFLAGS_UFNX = 5'b0_0011;
  localparam fpu_fflags_t FFLAGS_OFNX = 5'b0_0101;
  localparam fpu_fflags_t FFLAGS_NV   = 5'b1_0000;

  fpu_req_t  req_i;
  fpu_resp_t resp_o;
  logic      valid_op_o;

  int unsigned pass_cnt;
  int unsigned fail_cnt;
  int unsigned case_id;
  string       dbg_case_name;

  logic        dbg_is_i2f;
  logic        dbg_is_f2i;
  logic        dbg_is_f2f;
  logic        dbg_is_f2f_s2d;
  logic        dbg_is_f2f_d2s;

  logic [63:0] dbg_i2f_src;
  logic [63:0] dbg_i2f_result;
  logic [31:0] dbg_i2f_src_hi32;
  logic [31:0] dbg_i2f_src_lo32;
  logic [31:0] dbg_i2f_result_hi32;
  logic [31:0] dbg_i2f_result_lo32;
  real         dbg_i2f_result_d_real;
  logic [2:0]  dbg_i2f_rm;
  logic        dbg_i2f_rm_rne;
  logic [63:0] dbg_i2f_mag;
  logic [63:0] dbg_i2f_norm_sig;
  logic [5:0]  dbg_i2f_lop_pos;
  logic [6:0]  dbg_i2f_shamt;
  logic        dbg_i2f_guard;
  logic        dbg_i2f_round;
  logic        dbg_i2f_sticky;
  logic        dbg_i2f_inc;
  logic        dbg_i2f_inexact;

  logic [63:0] dbg_f2i_src;
  logic [63:0] dbg_f2i_result;
  logic [31:0] dbg_f2i_src_hi32;
  logic [31:0] dbg_f2i_src_lo32;
  logic [31:0] dbg_f2i_result_hi32;
  logic [31:0] dbg_f2i_result_lo32;
  real         dbg_f2i_src_d_real;
  logic [2:0]  dbg_f2i_rm;
  logic        dbg_f2i_rm_rne;
  logic [63:0] dbg_f2i_mag;
  logic [63:0] dbg_f2i_lost;
  logic [6:0]  dbg_f2i_shamt;
  logic        dbg_f2i_guard;
  logic        dbg_f2i_round;
  logic        dbg_f2i_sticky;
  logic        dbg_f2i_inc;
  logic        dbg_f2i_inexact;

  logic [63:0] dbg_f2f_src;
  logic [63:0] dbg_f2f_result;
  logic [31:0] dbg_f2f_src_hi32;
  logic [31:0] dbg_f2f_src_lo32;
  logic [31:0] dbg_f2f_result_hi32;
  logic [31:0] dbg_f2f_result_lo32;
  real         dbg_f2f_src_d_real;
  real         dbg_f2f_result_d_real;
  logic [2:0]  dbg_f2f_rm;
  logic        dbg_f2f_rm_rne;
  logic        dbg_f2f_guard;
  logic        dbg_f2f_round;
  logic        dbg_f2f_sticky;
  logic        dbg_f2f_inc;
  logic        dbg_f2f_inexact;

  // Waveform groups: one conversion instruction per prefix.
  logic        f2f_s_s_is;
  logic [31:0] f2f_s_s_src_s;
  logic [31:0] f2f_s_s_result_s;
  logic [2:0]  f2f_s_s_rm;
  fpu_fflags_t f2f_s_s_fflags;

  logic        f2f_s_d_is;
  logic [31:0] f2f_s_d_src_s;
  logic [63:0] f2f_s_d_result_d;
  real         f2f_s_d_result_d_real;
  logic [2:0]  f2f_s_d_rm;
  fpu_fflags_t f2f_s_d_fflags;

  logic        f2f_d_s_is;
  logic [63:0] f2f_d_s_src_d;
  real         f2f_d_s_src_d_real;
  logic [31:0] f2f_d_s_result_s;
  logic [2:0]  f2f_d_s_rm;
  fpu_fflags_t f2f_d_s_fflags;

  logic        f2f_d_d_is;
  logic [63:0] f2f_d_d_src_d;
  logic [63:0] f2f_d_d_result_d;
  real         f2f_d_d_src_d_real;
  real         f2f_d_d_result_d_real;
  logic [2:0]  f2f_d_d_rm;
  fpu_fflags_t f2f_d_d_fflags;

  logic        i2f_w_s_is;
  logic [31:0] i2f_w_s_src_w;
  logic [31:0] i2f_w_s_result_s;
  logic [2:0]  i2f_w_s_rm;
  fpu_fflags_t i2f_w_s_fflags;

  logic        i2f_wu_s_is;
  logic [31:0] i2f_wu_s_src_wu;
  logic [31:0] i2f_wu_s_result_s;
  logic [2:0]  i2f_wu_s_rm;
  fpu_fflags_t i2f_wu_s_fflags;

  logic        i2f_l_s_is;
  logic [63:0] i2f_l_s_src_l;
  logic [31:0] i2f_l_s_result_s;
  logic [2:0]  i2f_l_s_rm;
  fpu_fflags_t i2f_l_s_fflags;

  logic        i2f_lu_s_is;
  logic [63:0] i2f_lu_s_src_lu;
  logic [31:0] i2f_lu_s_result_s;
  logic [2:0]  i2f_lu_s_rm;
  fpu_fflags_t i2f_lu_s_fflags;

  logic        i2f_w_d_is;
  logic [31:0] i2f_w_d_src_w;
  logic [63:0] i2f_w_d_result_d;
  real         i2f_w_d_result_d_real;
  logic [2:0]  i2f_w_d_rm;
  fpu_fflags_t i2f_w_d_fflags;

  logic        i2f_wu_d_is;
  logic [31:0] i2f_wu_d_src_wu;
  logic [63:0] i2f_wu_d_result_d;
  real         i2f_wu_d_result_d_real;
  logic [2:0]  i2f_wu_d_rm;
  fpu_fflags_t i2f_wu_d_fflags;

  logic        i2f_l_d_is;
  logic [63:0] i2f_l_d_src_l;
  logic [63:0] i2f_l_d_result_d;
  real         i2f_l_d_result_d_real;
  logic [2:0]  i2f_l_d_rm;
  fpu_fflags_t i2f_l_d_fflags;

  logic        i2f_lu_d_is;
  logic [63:0] i2f_lu_d_src_lu;
  logic [63:0] i2f_lu_d_result_d;
  real         i2f_lu_d_result_d_real;
  logic [2:0]  i2f_lu_d_rm;
  fpu_fflags_t i2f_lu_d_fflags;

  logic        f2i_s_w_is;
  logic [31:0] f2i_s_w_src_s;
  logic [31:0] f2i_s_w_result_w;
  logic [2:0]  f2i_s_w_rm;
  fpu_fflags_t f2i_s_w_fflags;

  logic        f2i_s_wu_is;
  logic [31:0] f2i_s_wu_src_s;
  logic [31:0] f2i_s_wu_result_wu;
  logic [2:0]  f2i_s_wu_rm;
  fpu_fflags_t f2i_s_wu_fflags;

  logic        f2i_s_l_is;
  logic [31:0] f2i_s_l_src_s;
  logic [63:0] f2i_s_l_result_l;
  logic [2:0]  f2i_s_l_rm;
  fpu_fflags_t f2i_s_l_fflags;

  logic        f2i_s_lu_is;
  logic [31:0] f2i_s_lu_src_s;
  logic [63:0] f2i_s_lu_result_lu;
  logic [2:0]  f2i_s_lu_rm;
  fpu_fflags_t f2i_s_lu_fflags;

  logic        f2i_d_w_is;
  logic [63:0] f2i_d_w_src_d;
  real         f2i_d_w_src_d_real;
  logic [31:0] f2i_d_w_result_w;
  logic [2:0]  f2i_d_w_rm;
  fpu_fflags_t f2i_d_w_fflags;

  logic        f2i_d_wu_is;
  logic [63:0] f2i_d_wu_src_d;
  real         f2i_d_wu_src_d_real;
  logic [31:0] f2i_d_wu_result_wu;
  logic [2:0]  f2i_d_wu_rm;
  fpu_fflags_t f2i_d_wu_fflags;

  logic        f2i_d_l_is;
  logic [63:0] f2i_d_l_src_d;
  real         f2i_d_l_src_d_real;
  logic [63:0] f2i_d_l_result_l;
  logic [2:0]  f2i_d_l_rm;
  fpu_fflags_t f2i_d_l_fflags;

  logic        f2i_d_lu_is;
  logic [63:0] f2i_d_lu_src_d;
  real         f2i_d_lu_src_d_real;
  logic [63:0] f2i_d_lu_result_lu;
  logic [2:0]  f2i_d_lu_rm;
  fpu_fflags_t f2i_d_lu_fflags;

  fpu_convert_unit dut (
    .req_i     (req_i),
    .resp_o    (resp_o),
    .valid_op_o(valid_op_o)
  );

  function automatic fpu_data_t nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
  endfunction

  assign dbg_is_i2f     = (req_i.op == FPU_OP_CVT_I2F);
  assign dbg_is_f2i     = (req_i.op == FPU_OP_CVT_F2I);
  assign dbg_is_f2f     = (req_i.op == FPU_OP_CVT_FP);
  assign dbg_is_f2f_s2d = dbg_is_f2f && (req_i.rs_fmt == FPU_FMT_S) &&
                          (req_i.dst_fmt == FPU_FMT_D);
  assign dbg_is_f2f_d2s = dbg_is_f2f && (req_i.rs_fmt == FPU_FMT_D) &&
                          (req_i.dst_fmt == FPU_FMT_S);

  assign f2f_s_s_is       = dbg_is_f2f && (req_i.rs_fmt == FPU_FMT_S) &&
                            (req_i.dst_fmt == FPU_FMT_S);
  assign f2f_s_s_src_s    = f2f_s_s_is ? req_i.src_a[31:0] : 32'd0;
  assign f2f_s_s_result_s = f2f_s_s_is ? resp_o.result[31:0] : 32'd0;
  assign f2f_s_s_rm       = f2f_s_s_is ? req_i.rm : 3'd0;
  assign f2f_s_s_fflags   = f2f_s_s_is ? resp_o.fflags : '0;

  assign f2f_s_d_is       = dbg_is_f2f && (req_i.rs_fmt == FPU_FMT_S) &&
                            (req_i.dst_fmt == FPU_FMT_D);
  assign f2f_s_d_src_s    = f2f_s_d_is ? req_i.src_a[31:0] : 32'd0;
  assign f2f_s_d_result_d = f2f_s_d_is ? resp_o.result : 64'd0;
  assign f2f_s_d_rm       = f2f_s_d_is ? req_i.rm : 3'd0;
  assign f2f_s_d_fflags   = f2f_s_d_is ? resp_o.fflags : '0;

  assign f2f_d_s_is       = dbg_is_f2f && (req_i.rs_fmt == FPU_FMT_D) &&
                            (req_i.dst_fmt == FPU_FMT_S);
  assign f2f_d_s_src_d    = f2f_d_s_is ? req_i.src_a : 64'd0;
  assign f2f_d_s_result_s = f2f_d_s_is ? resp_o.result[31:0] : 32'd0;
  assign f2f_d_s_rm       = f2f_d_s_is ? req_i.rm : 3'd0;
  assign f2f_d_s_fflags   = f2f_d_s_is ? resp_o.fflags : '0;

  assign f2f_d_d_is       = dbg_is_f2f && (req_i.rs_fmt == FPU_FMT_D) &&
                            (req_i.dst_fmt == FPU_FMT_D);
  assign f2f_d_d_src_d    = f2f_d_d_is ? req_i.src_a : 64'd0;
  assign f2f_d_d_result_d = f2f_d_d_is ? resp_o.result : 64'd0;
  assign f2f_d_d_rm       = f2f_d_d_is ? req_i.rm : 3'd0;
  assign f2f_d_d_fflags   = f2f_d_d_is ? resp_o.fflags : '0;

  assign i2f_w_s_is      = dbg_is_i2f && (req_i.int_fmt == FPU_INT_W) &&
                           (req_i.dst_fmt == FPU_FMT_S);
  assign i2f_w_s_src_w    = i2f_w_s_is ? req_i.src_a[31:0] : 32'd0;
  assign i2f_w_s_result_s = i2f_w_s_is ? resp_o.result[31:0] : 32'd0;
  assign i2f_w_s_rm       = i2f_w_s_is ? req_i.rm : 3'd0;
  assign i2f_w_s_fflags   = i2f_w_s_is ? resp_o.fflags : '0;

  assign i2f_wu_s_is       = dbg_is_i2f && (req_i.int_fmt == FPU_INT_WU) &&
                             (req_i.dst_fmt == FPU_FMT_S);
  assign i2f_wu_s_src_wu   = i2f_wu_s_is ? req_i.src_a[31:0] : 32'd0;
  assign i2f_wu_s_result_s = i2f_wu_s_is ? resp_o.result[31:0] : 32'd0;
  assign i2f_wu_s_rm       = i2f_wu_s_is ? req_i.rm : 3'd0;
  assign i2f_wu_s_fflags   = i2f_wu_s_is ? resp_o.fflags : '0;

  assign i2f_l_s_is      = dbg_is_i2f && (req_i.int_fmt == FPU_INT_L) &&
                           (req_i.dst_fmt == FPU_FMT_S);
  assign i2f_l_s_src_l    = i2f_l_s_is ? req_i.src_a : 64'd0;
  assign i2f_l_s_result_s = i2f_l_s_is ? resp_o.result[31:0] : 32'd0;
  assign i2f_l_s_rm       = i2f_l_s_is ? req_i.rm : 3'd0;
  assign i2f_l_s_fflags   = i2f_l_s_is ? resp_o.fflags : '0;

  assign i2f_lu_s_is       = dbg_is_i2f && (req_i.int_fmt == FPU_INT_LU) &&
                             (req_i.dst_fmt == FPU_FMT_S);
  assign i2f_lu_s_src_lu   = i2f_lu_s_is ? req_i.src_a : 64'd0;
  assign i2f_lu_s_result_s = i2f_lu_s_is ? resp_o.result[31:0] : 32'd0;
  assign i2f_lu_s_rm       = i2f_lu_s_is ? req_i.rm : 3'd0;
  assign i2f_lu_s_fflags   = i2f_lu_s_is ? resp_o.fflags : '0;

  assign i2f_w_d_is      = dbg_is_i2f && (req_i.int_fmt == FPU_INT_W) &&
                           (req_i.dst_fmt == FPU_FMT_D);
  assign i2f_w_d_src_w    = i2f_w_d_is ? req_i.src_a[31:0] : 32'd0;
  assign i2f_w_d_result_d = i2f_w_d_is ? resp_o.result : 64'd0;
  assign i2f_w_d_rm       = i2f_w_d_is ? req_i.rm : 3'd0;
  assign i2f_w_d_fflags   = i2f_w_d_is ? resp_o.fflags : '0;

  assign i2f_wu_d_is       = dbg_is_i2f && (req_i.int_fmt == FPU_INT_WU) &&
                             (req_i.dst_fmt == FPU_FMT_D);
  assign i2f_wu_d_src_wu   = i2f_wu_d_is ? req_i.src_a[31:0] : 32'd0;
  assign i2f_wu_d_result_d = i2f_wu_d_is ? resp_o.result : 64'd0;
  assign i2f_wu_d_rm       = i2f_wu_d_is ? req_i.rm : 3'd0;
  assign i2f_wu_d_fflags   = i2f_wu_d_is ? resp_o.fflags : '0;

  assign i2f_l_d_is      = dbg_is_i2f && (req_i.int_fmt == FPU_INT_L) &&
                           (req_i.dst_fmt == FPU_FMT_D);
  assign i2f_l_d_src_l    = i2f_l_d_is ? req_i.src_a : 64'd0;
  assign i2f_l_d_result_d = i2f_l_d_is ? resp_o.result : 64'd0;
  assign i2f_l_d_rm       = i2f_l_d_is ? req_i.rm : 3'd0;
  assign i2f_l_d_fflags   = i2f_l_d_is ? resp_o.fflags : '0;

  assign i2f_lu_d_is       = dbg_is_i2f && (req_i.int_fmt == FPU_INT_LU) &&
                             (req_i.dst_fmt == FPU_FMT_D);
  assign i2f_lu_d_src_lu   = i2f_lu_d_is ? req_i.src_a : 64'd0;
  assign i2f_lu_d_result_d = i2f_lu_d_is ? resp_o.result : 64'd0;
  assign i2f_lu_d_rm       = i2f_lu_d_is ? req_i.rm : 3'd0;
  assign i2f_lu_d_fflags   = i2f_lu_d_is ? resp_o.fflags : '0;

  assign f2i_s_w_is       = dbg_is_f2i && (req_i.rs_fmt == FPU_FMT_S) &&
                            (req_i.int_fmt == FPU_INT_W);
  assign f2i_s_w_src_s    = f2i_s_w_is ? req_i.src_a[31:0] : 32'd0;
  assign f2i_s_w_result_w = f2i_s_w_is ? resp_o.result[31:0] : 32'd0;
  assign f2i_s_w_rm       = f2i_s_w_is ? req_i.rm : 3'd0;
  assign f2i_s_w_fflags   = f2i_s_w_is ? resp_o.fflags : '0;

  assign f2i_s_wu_is        = dbg_is_f2i && (req_i.rs_fmt == FPU_FMT_S) &&
                              (req_i.int_fmt == FPU_INT_WU);
  assign f2i_s_wu_src_s     = f2i_s_wu_is ? req_i.src_a[31:0] : 32'd0;
  assign f2i_s_wu_result_wu = f2i_s_wu_is ? resp_o.result[31:0] : 32'd0;
  assign f2i_s_wu_rm        = f2i_s_wu_is ? req_i.rm : 3'd0;
  assign f2i_s_wu_fflags    = f2i_s_wu_is ? resp_o.fflags : '0;

  assign f2i_s_l_is       = dbg_is_f2i && (req_i.rs_fmt == FPU_FMT_S) &&
                            (req_i.int_fmt == FPU_INT_L);
  assign f2i_s_l_src_s    = f2i_s_l_is ? req_i.src_a[31:0] : 32'd0;
  assign f2i_s_l_result_l = f2i_s_l_is ? resp_o.result : 64'd0;
  assign f2i_s_l_rm       = f2i_s_l_is ? req_i.rm : 3'd0;
  assign f2i_s_l_fflags   = f2i_s_l_is ? resp_o.fflags : '0;

  assign f2i_s_lu_is        = dbg_is_f2i && (req_i.rs_fmt == FPU_FMT_S) &&
                              (req_i.int_fmt == FPU_INT_LU);
  assign f2i_s_lu_src_s     = f2i_s_lu_is ? req_i.src_a[31:0] : 32'd0;
  assign f2i_s_lu_result_lu = f2i_s_lu_is ? resp_o.result : 64'd0;
  assign f2i_s_lu_rm        = f2i_s_lu_is ? req_i.rm : 3'd0;
  assign f2i_s_lu_fflags    = f2i_s_lu_is ? resp_o.fflags : '0;

  assign f2i_d_w_is       = dbg_is_f2i && (req_i.rs_fmt == FPU_FMT_D) &&
                            (req_i.int_fmt == FPU_INT_W);
  assign f2i_d_w_src_d    = f2i_d_w_is ? req_i.src_a : 64'd0;
  assign f2i_d_w_result_w = f2i_d_w_is ? resp_o.result[31:0] : 32'd0;
  assign f2i_d_w_rm       = f2i_d_w_is ? req_i.rm : 3'd0;
  assign f2i_d_w_fflags   = f2i_d_w_is ? resp_o.fflags : '0;

  assign f2i_d_wu_is        = dbg_is_f2i && (req_i.rs_fmt == FPU_FMT_D) &&
                              (req_i.int_fmt == FPU_INT_WU);
  assign f2i_d_wu_src_d     = f2i_d_wu_is ? req_i.src_a : 64'd0;
  assign f2i_d_wu_result_wu = f2i_d_wu_is ? resp_o.result[31:0] : 32'd0;
  assign f2i_d_wu_rm        = f2i_d_wu_is ? req_i.rm : 3'd0;
  assign f2i_d_wu_fflags    = f2i_d_wu_is ? resp_o.fflags : '0;

  assign f2i_d_l_is       = dbg_is_f2i && (req_i.rs_fmt == FPU_FMT_D) &&
                            (req_i.int_fmt == FPU_INT_L);
  assign f2i_d_l_src_d    = f2i_d_l_is ? req_i.src_a : 64'd0;
  assign f2i_d_l_result_l = f2i_d_l_is ? resp_o.result : 64'd0;
  assign f2i_d_l_rm       = f2i_d_l_is ? req_i.rm : 3'd0;
  assign f2i_d_l_fflags   = f2i_d_l_is ? resp_o.fflags : '0;

  assign f2i_d_lu_is        = dbg_is_f2i && (req_i.rs_fmt == FPU_FMT_D) &&
                              (req_i.int_fmt == FPU_INT_LU);
  assign f2i_d_lu_src_d     = f2i_d_lu_is ? req_i.src_a : 64'd0;
  assign f2i_d_lu_result_lu = f2i_d_lu_is ? resp_o.result : 64'd0;
  assign f2i_d_lu_rm        = f2i_d_lu_is ? req_i.rm : 3'd0;
  assign f2i_d_lu_fflags    = f2i_d_lu_is ? resp_o.fflags : '0;

  assign dbg_i2f_src      = dbg_is_i2f ? req_i.src_a : 64'd0;
  assign dbg_i2f_result   = dbg_is_i2f ? resp_o.result : 64'd0;
  assign dbg_i2f_src_hi32    = dbg_is_i2f ? req_i.src_a[63:32] : 32'd0;
  assign dbg_i2f_src_lo32    = dbg_is_i2f ? req_i.src_a[31:0]  : 32'd0;
  assign dbg_i2f_result_hi32 = dbg_is_i2f ? resp_o.result[63:32] : 32'd0;
  assign dbg_i2f_result_lo32 = dbg_is_i2f ? resp_o.result[31:0]  : 32'd0;
  assign dbg_i2f_rm       = dbg_is_i2f ? req_i.rm : 3'd0;
  assign dbg_i2f_rm_rne   = dbg_is_i2f && (req_i.rm == FPU_RM_RNE);
  assign dbg_i2f_mag      = dbg_is_i2f ? dut.u_i2f.int_src.mag : 64'd0;
  assign dbg_i2f_norm_sig = dbg_is_i2f ? dut.u_i2f.i2f_sig : 64'd0;
  assign dbg_i2f_lop_pos  = dbg_is_i2f ? dut.u_i2f.i2f_lop_pos : 6'd0;
  assign dbg_i2f_shamt    = dbg_is_i2f ? dut.u_i2f.i2f_shamt : 7'd0;

  assign dbg_f2i_src      = dbg_is_f2i ? req_i.src_a : 64'd0;
  assign dbg_f2i_result   = dbg_is_f2i ? resp_o.result : 64'd0;
  assign dbg_f2i_src_hi32    = dbg_is_f2i ? req_i.src_a[63:32] : 32'd0;
  assign dbg_f2i_src_lo32    = dbg_is_f2i ? req_i.src_a[31:0]  : 32'd0;
  assign dbg_f2i_result_hi32 = dbg_is_f2i ? resp_o.result[63:32] : 32'd0;
  assign dbg_f2i_result_lo32 = dbg_is_f2i ? resp_o.result[31:0]  : 32'd0;
  assign dbg_f2i_rm       = dbg_is_f2i ? req_i.rm : 3'd0;
  assign dbg_f2i_rm_rne   = dbg_is_f2i && (req_i.rm == FPU_RM_RNE);
  assign dbg_f2i_mag      = dbg_is_f2i ? dut.u_f2i.f2i_mag : 64'd0;
  assign dbg_f2i_lost     = dbg_is_f2i ? dut.u_f2i.f2i_lost : 64'd0;
  assign dbg_f2i_shamt    = dbg_is_f2i ? dut.u_f2i.f2i_shamt : 7'd0;
  assign dbg_f2i_guard    = dbg_is_f2i ? dut.u_f2i.f2i_eff_grs.guard : 1'b0;
  assign dbg_f2i_round    = dbg_is_f2i ? dut.u_f2i.f2i_eff_grs.round : 1'b0;
  assign dbg_f2i_sticky   = dbg_is_f2i ? dut.u_f2i.f2i_eff_grs.sticky : 1'b0;
  assign dbg_f2i_inc      = dbg_is_f2i ? dut.u_f2i.f2i_round_inc : 1'b0;
  assign dbg_f2i_inexact  = dbg_is_f2i ? dut.u_f2i.f2i_inexact : 1'b0;

  assign dbg_f2f_src      = dbg_is_f2f ? req_i.src_a : 64'd0;
  assign dbg_f2f_result   = dbg_is_f2f ? resp_o.result : 64'd0;
  assign dbg_f2f_src_hi32    = dbg_is_f2f ? req_i.src_a[63:32] : 32'd0;
  assign dbg_f2f_src_lo32    = dbg_is_f2f ? req_i.src_a[31:0]  : 32'd0;
  assign dbg_f2f_result_hi32 = dbg_is_f2f ? resp_o.result[63:32] : 32'd0;
  assign dbg_f2f_result_lo32 = dbg_is_f2f ? resp_o.result[31:0]  : 32'd0;
  assign dbg_f2f_rm       = dbg_is_f2f ? req_i.rm : 3'd0;
  assign dbg_f2f_rm_rne   = dbg_is_f2f && (req_i.rm == FPU_RM_RNE);
  assign dbg_f2f_guard    = dbg_is_f2f_d2s ? dut.u_f2f.f2f_d2s_grs.guard : 1'b0;
  assign dbg_f2f_round    = dbg_is_f2f_d2s ? dut.u_f2f.f2f_d2s_grs.round : 1'b0;
  assign dbg_f2f_sticky   = dbg_is_f2f_d2s ? dut.u_f2f.f2f_d2s_grs.sticky : 1'b0;
  assign dbg_f2f_inc      = dbg_is_f2f_d2s ? dut.u_f2f.f2f_d2s_round_inc : 1'b0;
  assign dbg_f2f_inexact  = dbg_is_f2f_d2s ? dut.u_f2f.f2f_d2s_inexact : 1'b0;

  always_comb begin
    dbg_i2f_guard   = 1'b0;
    dbg_i2f_round   = 1'b0;
    dbg_i2f_sticky  = 1'b0;
    dbg_i2f_inc     = 1'b0;
    dbg_i2f_inexact = 1'b0;

    if (dbg_is_i2f && (req_i.dst_fmt == FPU_FMT_S)) begin
      dbg_i2f_guard   = dut.u_i2f.i2f_s_grs.guard;
      dbg_i2f_round   = dut.u_i2f.i2f_s_grs.round;
      dbg_i2f_sticky  = dut.u_i2f.i2f_s_grs.sticky;
      dbg_i2f_inc     = dut.u_i2f.i2f_s_round_inc;
      dbg_i2f_inexact = dut.u_i2f.i2f_s_inexact;
    end else if (dbg_is_i2f && (req_i.dst_fmt == FPU_FMT_D)) begin
      dbg_i2f_guard   = dut.u_i2f.i2f_d_grs.guard;
      dbg_i2f_round   = dut.u_i2f.i2f_d_grs.round;
      dbg_i2f_sticky  = dut.u_i2f.i2f_d_grs.sticky;
      dbg_i2f_inc     = dut.u_i2f.i2f_d_round_inc;
      dbg_i2f_inexact = dut.u_i2f.i2f_d_inexact;
    end
  end

  always @* begin
    dbg_i2f_result_d_real = (dbg_is_i2f && (req_i.dst_fmt == FPU_FMT_D)) ?
                            $bitstoreal(resp_o.result) : 0.0;
    dbg_f2i_src_d_real    = (dbg_is_f2i && (req_i.rs_fmt == FPU_FMT_D)) ?
                            $bitstoreal(req_i.src_a) : 0.0;
    dbg_f2f_src_d_real    = (dbg_is_f2f && (req_i.rs_fmt == FPU_FMT_D)) ?
                            $bitstoreal(req_i.src_a) : 0.0;
    dbg_f2f_result_d_real = (dbg_is_f2f && (req_i.dst_fmt == FPU_FMT_D)) ?
                            $bitstoreal(resp_o.result) : 0.0;

    f2f_s_d_result_d_real = f2f_s_d_is ? $bitstoreal(f2f_s_d_result_d) : 0.0;
    f2f_d_s_src_d_real    = f2f_d_s_is ? $bitstoreal(f2f_d_s_src_d) : 0.0;
    f2f_d_d_src_d_real    = f2f_d_d_is ? $bitstoreal(f2f_d_d_src_d) : 0.0;
    f2f_d_d_result_d_real = f2f_d_d_is ? $bitstoreal(f2f_d_d_result_d) : 0.0;

    i2f_w_d_result_d_real  = i2f_w_d_is ? $bitstoreal(i2f_w_d_result_d) : 0.0;
    i2f_wu_d_result_d_real = i2f_wu_d_is ? $bitstoreal(i2f_wu_d_result_d) : 0.0;
    i2f_l_d_result_d_real  = i2f_l_d_is ? $bitstoreal(i2f_l_d_result_d) : 0.0;
    i2f_lu_d_result_d_real = i2f_lu_d_is ? $bitstoreal(i2f_lu_d_result_d) : 0.0;

    f2i_d_w_src_d_real  = f2i_d_w_is ? $bitstoreal(f2i_d_w_src_d) : 0.0;
    f2i_d_wu_src_d_real = f2i_d_wu_is ? $bitstoreal(f2i_d_wu_src_d) : 0.0;
    f2i_d_l_src_d_real  = f2i_d_l_is ? $bitstoreal(f2i_d_l_src_d) : 0.0;
    f2i_d_lu_src_d_real = f2i_d_lu_is ? $bitstoreal(f2i_d_lu_src_d) : 0.0;
  end

  task automatic drive_idle;
    req_i = '0;
    dbg_case_name = "idle";
    #1;
  endtask

  task automatic apply_req(
    input string        name,
    input fpu_op_e      op,
    input fpu_fmt_e     rs_fmt,
    input fpu_fmt_e     dst_fmt,
    input fpu_int_fmt_e int_fmt,
    input fpu_rm_e      rm,
    input fpu_data_t    src_a
  );
    req_i = '0;
    req_i.op      = op;
    req_i.rs_fmt  = rs_fmt;
    req_i.dst_fmt = dst_fmt;
    req_i.int_fmt = int_fmt;
    req_i.rm      = rm;
    req_i.src_a   = src_a;
    req_i.tag     = 8'h5a;
    req_i.rd      = 5'd17;
    dbg_case_name = name;
    case_id++;
    #1;
  endtask

  task automatic check_result(
    input string        name,
    input fpu_op_e      op,
    input fpu_fmt_e     rs_fmt,
    input fpu_fmt_e     dst_fmt,
    input fpu_int_fmt_e int_fmt,
    input fpu_rm_e      rm,
    input fpu_data_t    src_a,
    input fpu_data_t    exp_result,
    input fpu_fflags_t  exp_fflags,
    input logic         exp_valid
  );
    apply_req(name, op, rs_fmt, dst_fmt, int_fmt, rm, src_a);

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

  task automatic check_i2f(
    input string        name,
    input fpu_int_fmt_e int_fmt,
    input fpu_fmt_e     dst_fmt,
    input fpu_rm_e      rm,
    input fpu_data_t    src_a,
    input fpu_data_t    exp_result,
    input fpu_fflags_t  exp_fflags
  );
    check_result(name, FPU_OP_CVT_I2F, FPU_FMT_D, dst_fmt, int_fmt, rm,
                 src_a, exp_result, exp_fflags, 1'b1);
  endtask

  task automatic check_f2i(
    input string        name,
    input fpu_fmt_e     rs_fmt,
    input fpu_int_fmt_e int_fmt,
    input fpu_rm_e      rm,
    input fpu_data_t    src_a,
    input fpu_data_t    exp_result,
    input fpu_fflags_t  exp_fflags
  );
    check_result(name, FPU_OP_CVT_F2I, rs_fmt, FPU_FMT_D, int_fmt, rm,
                 src_a, exp_result, exp_fflags, 1'b1);
  endtask

  task automatic check_f2f(
    input string       name,
    input fpu_fmt_e    rs_fmt,
    input fpu_fmt_e    dst_fmt,
    input fpu_rm_e     rm,
    input fpu_data_t   src_a,
    input fpu_data_t   exp_result,
    input fpu_fflags_t exp_fflags
  );
    check_result(name, FPU_OP_CVT_FP, rs_fmt, dst_fmt, FPU_INT_W, rm,
                 src_a, exp_result, exp_fflags, 1'b1);
  endtask

  initial begin
`ifdef DUMP_FSDB
    $fsdbDumpfile("tb_fpu_convert.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_convert);
`endif

    pass_cnt = 0;
    fail_cnt = 0;
    case_id  = 0;
    drive_idle();

    check_f2f("f2f_s_s_one", FPU_FMT_S, FPU_FMT_S, FPU_RM_RNE,
              nanbox_s(32'h3f80_0000), nanbox_s(32'h3f80_0000), FFLAGS_NONE);
    check_f2f("f2f_d_d_one", FPU_FMT_D, FPU_FMT_D, FPU_RM_RNE,
              64'h3ff0_0000_0000_0000, 64'h3ff0_0000_0000_0000, FFLAGS_NONE);
    check_f2f("f2f_s_d_one", FPU_FMT_S, FPU_FMT_D, FPU_RM_RNE,
              nanbox_s(32'h3f80_0000), 64'h3ff0_0000_0000_0000, FFLAGS_NONE);
    check_f2f("f2f_s_d_min_sub", FPU_FMT_S, FPU_FMT_D, FPU_RM_RNE,
              nanbox_s(32'h0000_0001), 64'h36a0_0000_0000_0000, FFLAGS_NONE);
    check_f2f("f2f_s_d_qnan", FPU_FMT_S, FPU_FMT_D, FPU_RM_RNE,
              nanbox_s(32'h7fc0_0000), 64'h7ff8_0000_0000_0000, FFLAGS_NONE);
    check_f2f("f2f_d_s_one", FPU_FMT_D, FPU_FMT_S, FPU_RM_RNE,
              64'h3ff0_0000_0000_0000, nanbox_s(32'h3f80_0000), FFLAGS_NONE);
    check_f2f("f2f_d_s_min_sub_exact", FPU_FMT_D, FPU_FMT_S, FPU_RM_RNE,
              64'h36a0_0000_0000_0000, nanbox_s(32'h0000_0001), FFLAGS_NONE);
    check_f2f("f2f_d_s_half_min_sub", FPU_FMT_D, FPU_FMT_S, FPU_RM_RNE,
              64'h3690_0000_0000_0000, nanbox_s(32'h0000_0000), FFLAGS_UFNX);
    check_f2f("f2f_d_s_min_norm", FPU_FMT_D, FPU_FMT_S, FPU_RM_RNE,
              64'h3810_0000_0000_0000, nanbox_s(32'h0080_0000), FFLAGS_NONE);
    check_f2f("f2f_d_s_smax_exact", FPU_FMT_D, FPU_FMT_S, FPU_RM_RNE,
              64'h47ef_ffff_e000_0000, nanbox_s(32'h7f7f_ffff), FFLAGS_NONE);
    check_f2f("f2f_d_s_smax_tail_down", FPU_FMT_D, FPU_FMT_S, FPU_RM_RNE,
              64'h47ef_ffff_e000_0001, nanbox_s(32'h7f7f_ffff), FFLAGS_NX);
    check_f2f("f2f_d_s_smax_tail_up", FPU_FMT_D, FPU_FMT_S, FPU_RM_RNE,
              64'h47ef_ffff_ffff_ffff, nanbox_s(32'h7f80_0000), FFLAGS_OFNX);
    check_f2f("f2f_d_s_smax_tail_rdn", FPU_FMT_D, FPU_FMT_S, FPU_RM_RDN,
              64'h47ef_ffff_ffff_ffff, nanbox_s(32'h7f7f_ffff), FFLAGS_NX);

    check_i2f("i2f_w_s_zero", FPU_INT_W, FPU_FMT_S, FPU_RM_RNE,
              64'd0, nanbox_s(32'h0000_0000), FFLAGS_NONE);
    check_i2f("i2f_w_s_neg1", FPU_INT_W, FPU_FMT_S, FPU_RM_RNE,
              64'hffff_ffff_ffff_ffff, nanbox_s(32'hbf80_0000), FFLAGS_NONE);
    check_i2f("i2f_w_s_i32_max_rne", FPU_INT_W, FPU_FMT_S, FPU_RM_RNE,
              64'h0000_0000_7fff_ffff, nanbox_s(32'h4f00_0000), FFLAGS_NX);
    check_i2f("i2f_w_s_i32_min", FPU_INT_W, FPU_FMT_S, FPU_RM_RNE,
              64'h0000_0000_8000_0000, nanbox_s(32'hcf00_0000), FFLAGS_NONE);
    check_i2f("i2f_wu_s_u32_max_rne", FPU_INT_WU, FPU_FMT_S, FPU_RM_RNE,
              64'h0000_0000_ffff_ffff, nanbox_s(32'h4f80_0000), FFLAGS_NX);
    check_i2f("i2f_l_s_i64_max_rne", FPU_INT_L, FPU_FMT_S, FPU_RM_RNE,
              64'h7fff_ffff_ffff_ffff, nanbox_s(32'h5f00_0000), FFLAGS_NX);
    check_i2f("i2f_l_s_i64_min", FPU_INT_L, FPU_FMT_S, FPU_RM_RNE,
              64'h8000_0000_0000_0000, nanbox_s(32'hdf00_0000), FFLAGS_NONE);
    check_i2f("i2f_lu_s_u64_max_rne", FPU_INT_LU, FPU_FMT_S, FPU_RM_RNE,
              64'hffff_ffff_ffff_ffff, nanbox_s(32'h5f80_0000), FFLAGS_NX);
    check_i2f("i2f_w_d_i32_max", FPU_INT_W, FPU_FMT_D, FPU_RM_RNE,
              64'h0000_0000_7fff_ffff, 64'h41df_ffff_ffc0_0000, FFLAGS_NONE);
    check_i2f("i2f_wu_d_u32_max", FPU_INT_WU, FPU_FMT_D, FPU_RM_RNE,
              64'h0000_0000_ffff_ffff, 64'h41ef_ffff_ffe0_0000, FFLAGS_NONE);
    check_i2f("i2f_l_d_2p53p1_rne", FPU_INT_L, FPU_FMT_D, FPU_RM_RNE,
              64'h0020_0000_0000_0001, 64'h4340_0000_0000_0000, FFLAGS_NX);
    check_i2f("i2f_l_d_i64_max_rne", FPU_INT_L, FPU_FMT_D, FPU_RM_RNE,
              64'h7fff_ffff_ffff_ffff, 64'h43e0_0000_0000_0000, FFLAGS_NX);
    check_i2f("i2f_l_d_i64_min", FPU_INT_L, FPU_FMT_D, FPU_RM_RNE,
              64'h8000_0000_0000_0000, 64'hc3e0_0000_0000_0000, FFLAGS_NONE);
    check_i2f("i2f_lu_d_u64_max_rne", FPU_INT_LU, FPU_FMT_D, FPU_RM_RNE,
              64'hffff_ffff_ffff_ffff, 64'h43f0_0000_0000_0000, FFLAGS_NX);

    check_f2i("f2i_s_w_0p25_rne", FPU_FMT_S, FPU_INT_W, FPU_RM_RNE,
              nanbox_s(32'h3e80_0000), 64'h0000_0000_0000_0000, FFLAGS_NX);
    check_f2i("f2i_s_w_0p5_tie_even", FPU_FMT_S, FPU_INT_W, FPU_RM_RNE,
              nanbox_s(32'h3f00_0000), 64'h0000_0000_0000_0000, FFLAGS_NX);
    check_f2i("f2i_s_w_0p75_rne", FPU_FMT_S, FPU_INT_W, FPU_RM_RNE,
              nanbox_s(32'h3f40_0000), 64'h0000_0000_0000_0001, FFLAGS_NX);
    check_f2i("f2i_s_w_1p5_tie_odd", FPU_FMT_S, FPU_INT_W, FPU_RM_RNE,
              nanbox_s(32'h3fc0_0000), 64'h0000_0000_0000_0002, FFLAGS_NX);
    check_f2i("f2i_s_w_2p5_tie_even", FPU_FMT_S, FPU_INT_W, FPU_RM_RNE,
              nanbox_s(32'h4020_0000), 64'h0000_0000_0000_0002, FFLAGS_NX);
    check_f2i("f2i_s_w_3p5_tie_odd", FPU_FMT_S, FPU_INT_W, FPU_RM_RNE,
              nanbox_s(32'h4060_0000), 64'h0000_0000_0000_0004, FFLAGS_NX);
    check_f2i("f2i_s_w_n1p5_tie_odd", FPU_FMT_S, FPU_INT_W, FPU_RM_RNE,
              nanbox_s(32'hbfc0_0000), 64'hffff_ffff_ffff_fffe, FFLAGS_NX);
    check_f2i("f2i_s_w_n2p5_tie_even", FPU_FMT_S, FPU_INT_W, FPU_RM_RNE,
              nanbox_s(32'hc020_0000), 64'hffff_ffff_ffff_fffe, FFLAGS_NX);
    check_f2i("f2i_s_w_0p25_rup", FPU_FMT_S, FPU_INT_W, FPU_RM_RUP,
              nanbox_s(32'h3e80_0000), 64'h0000_0000_0000_0001, FFLAGS_NX);
    check_f2i("f2i_s_w_n0p25_rdn", FPU_FMT_S, FPU_INT_W, FPU_RM_RDN,
              nanbox_s(32'hbe80_0000), 64'hffff_ffff_ffff_ffff, FFLAGS_NX);
    check_f2i("f2i_s_w_pos_2p31_nv", FPU_FMT_S, FPU_INT_W, FPU_RM_RNE,
              nanbox_s(32'h4f00_0000), 64'h0000_0000_7fff_ffff, FFLAGS_NV);
    check_f2i("f2i_s_w_neg_2p31", FPU_FMT_S, FPU_INT_W, FPU_RM_RNE,
              nanbox_s(32'hcf00_0000), 64'hffff_ffff_8000_0000, FFLAGS_NONE);
    check_f2i("f2i_s_w_below_min_nv", FPU_FMT_S, FPU_INT_W, FPU_RM_RNE,
              nanbox_s(32'hcf00_0001), 64'hffff_ffff_8000_0000, FFLAGS_NV);
    check_f2i("f2i_s_w_inf_nv", FPU_FMT_S, FPU_INT_W, FPU_RM_RNE,
              nanbox_s(32'h7f80_0000), 64'h0000_0000_7fff_ffff, FFLAGS_NV);
    check_f2i("f2i_s_w_nan_nv", FPU_FMT_S, FPU_INT_W, FPU_RM_RNE,
              nanbox_s(32'h7fc0_0000), 64'h0000_0000_7fff_ffff, FFLAGS_NV);
    check_f2i("f2i_d_w_0p5_tie_even", FPU_FMT_D, FPU_INT_W, FPU_RM_RNE,
              64'h3fe0_0000_0000_0000, 64'h0000_0000_0000_0000, FFLAGS_NX);
    check_f2i("f2i_d_w_0p75_rne", FPU_FMT_D, FPU_INT_W, FPU_RM_RNE,
              64'h3fe8_0000_0000_0000, 64'h0000_0000_0000_0001, FFLAGS_NX);
    check_f2i("f2i_d_w_2p5_tie_even", FPU_FMT_D, FPU_INT_W, FPU_RM_RNE,
              64'h4004_0000_0000_0000, 64'h0000_0000_0000_0002, FFLAGS_NX);
    check_f2i("f2i_d_l_pos_2p63_nv", FPU_FMT_D, FPU_INT_L, FPU_RM_RNE,
              64'h43e0_0000_0000_0000, 64'h7fff_ffff_ffff_ffff, FFLAGS_NV);
    check_f2i("f2i_d_l_neg_2p63", FPU_FMT_D, FPU_INT_L, FPU_RM_RNE,
              64'hc3e0_0000_0000_0000, 64'h8000_0000_0000_0000, FFLAGS_NONE);

    check_f2i("f2i_s_wu_one", FPU_FMT_S, FPU_INT_WU, FPU_RM_RNE,
              nanbox_s(32'h3f80_0000), 64'h0000_0000_0000_0001, FFLAGS_NONE);
    check_f2i("f2i_d_wu_one", FPU_FMT_D, FPU_INT_WU, FPU_RM_RNE,
              64'h3ff0_0000_0000_0000, 64'h0000_0000_0000_0001, FFLAGS_NONE);
    check_f2i("f2i_s_lu_one", FPU_FMT_S, FPU_INT_LU, FPU_RM_RNE,
              nanbox_s(32'h3f80_0000), 64'h0000_0000_0000_0001, FFLAGS_NONE);
    check_f2i("f2i_d_lu_one", FPU_FMT_D, FPU_INT_LU, FPU_RM_RNE,
              64'h3ff0_0000_0000_0000, 64'h0000_0000_0000_0001, FFLAGS_NONE);
    check_f2i("f2i_s_wu_neg_nv", FPU_FMT_S, FPU_INT_WU, FPU_RM_RNE,
              nanbox_s(32'hbf80_0000), 64'h0000_0000_0000_0000, FFLAGS_NV);
    check_f2i("f2i_s_wu_max_below_2p32", FPU_FMT_S, FPU_INT_WU, FPU_RM_RNE,
              nanbox_s(32'h4f7f_ffff), 64'h0000_0000_ffff_ff00, FFLAGS_NONE);
    check_f2i("f2i_d_wu_2p32_minus_1", FPU_FMT_D, FPU_INT_WU, FPU_RM_RNE,
              64'h41ef_ffff_ffe0_0000, 64'h0000_0000_ffff_ffff, FFLAGS_NONE);
    check_f2i("f2i_d_wu_round_to_2p32_nv", FPU_FMT_D, FPU_INT_WU, FPU_RM_RNE,
              64'h41ef_ffff_fff0_0000, 64'h0000_0000_ffff_ffff, FFLAGS_NV);
    check_f2i("f2i_s_wu_2p32_nv", FPU_FMT_S, FPU_INT_WU, FPU_RM_RNE,
              nanbox_s(32'h4f80_0000), 64'h0000_0000_ffff_ffff, FFLAGS_NV);
    check_f2i("f2i_d_wu_2p32_nv", FPU_FMT_D, FPU_INT_WU, FPU_RM_RNE,
              64'h41f0_0000_0000_0000, 64'h0000_0000_ffff_ffff, FFLAGS_NV);

    $display("tb_fpu_convert summary: pass=%0d fail=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_convert failed");
    end

    $finish;
  end

endmodule : tb_fpu_convert
