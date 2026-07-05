package fpu_pkg;

  parameter int unsigned FPU_DATA_W = 64;
  parameter int unsigned FPU_TAG_W  = 8;
  parameter int unsigned FPU_RD_W   = 5;

  localparam int unsigned FPU_FFLAGS_W = 5;

  typedef logic [FPU_DATA_W-1:0]   fpu_data_t;
  typedef logic [FPU_TAG_W-1:0]    fpu_tag_t;
  typedef logic [FPU_RD_W-1:0]     fpu_rd_t;
  typedef logic [FPU_FFLAGS_W-1:0] fpu_fflags_t;

  typedef union packed {
    logic [31:0] bits;
    struct packed {
      logic        sign;
      logic [7:0]  exponent;
      logic [22:0] mantissa;
    } fields;
  } float32_t;

  typedef union packed {
    logic [63:0] bits;
    struct packed {
      logic        sign;
      logic [10:0] exponent;
      logic [51:0] mantissa;
    } fields;
  } float64_t;

  typedef struct packed {
    logic guard;
    logic round;
    logic sticky;
  } fpu_grs_t;

  // RISC-V fflags bit positions.
  localparam int unsigned FPU_FFLAG_NX = 0;
  localparam int unsigned FPU_FFLAG_UF = 1;
  localparam int unsigned FPU_FFLAG_OF = 2;
  localparam int unsigned FPU_FFLAG_DZ = 3;
  localparam int unsigned FPU_FFLAG_NV = 4;

  // Floating-point format carried on the 64-bit FPU data bus.
  // S-format operands use bits [31:0] and are NaN-boxed in bits [63:32].
  // D-format operands use the full 64-bit IEEE-754 encoding.
  typedef enum logic [1:0] {
    FPU_FMT_S = 2'b00,
    FPU_FMT_D = 2'b01
  } fpu_fmt_e;

  typedef enum logic [1:0] {
    FPU_INT_W  = 2'b00,
    FPU_INT_WU = 2'b01,
    FPU_INT_L  = 2'b10,
    FPU_INT_LU = 2'b11
  } fpu_int_fmt_e;

  typedef enum logic [2:0] {
    FPU_RM_RNE = 3'b000,
    FPU_RM_RTZ = 3'b001,
    FPU_RM_RDN = 3'b010,
    FPU_RM_RUP = 3'b011,
    FPU_RM_RMM = 3'b100,
    FPU_RM_DYN = 3'b111
  } fpu_rm_e;

  // CPU decode selects an operation family. Concrete source/destination
  // formats are described by fpu_req_t fields.
  typedef enum logic [5:0] {
    FPU_OP_NONE     = 6'b00_0000,

    // Arithmetic, op[5:4] = 2'b00.
    FPU_OP_ADD      = 6'b00_0001,  // FADD.S/D
    FPU_OP_SUB      = 6'b00_0010,  // FSUB.S/D
    FPU_OP_MUL      = 6'b00_0011,  // FMUL.S/D
    FPU_OP_DIV      = 6'b00_0100,  // FDIV.S/D
    FPU_OP_SQRT     = 6'b00_0101,  // FSQRT.S/D
    FPU_OP_FMADD    = 6'b00_0110,  // FMADD.S/D
    FPU_OP_FMSUB    = 6'b00_0111,  // FMSUB.S/D
    FPU_OP_FNMSUB   = 6'b00_1000,  // FNMSUB.S/D
    FPU_OP_FNMADD   = 6'b00_1001,  // FNMADD.S/D

    // Compare/classify/sign-injection, op[5:4] = 2'b01.
    FPU_OP_EQ       = 6'b01_0001,  // FEQ.S/D
    FPU_OP_LT       = 6'b01_0010,  // FLT.S/D
    FPU_OP_LE       = 6'b01_0011,  // FLE.S/D
    FPU_OP_MIN      = 6'b01_0100,  // FMIN.S/D
    FPU_OP_MAX      = 6'b01_0101,  // FMAX.S/D
    FPU_OP_CLASS    = 6'b01_0110,  // FCLASS.S/D
    FPU_OP_SGNJ     = 6'b01_0111,  // FSGNJ.S/D
    FPU_OP_SGNJN    = 6'b01_1000,  // FSGNJN.S/D
    FPU_OP_SGNJX    = 6'b01_1001,  // FSGNJX.S/D

    // Convert, op[5:4] = 2'b10.
    FPU_OP_CVT_FP   = 6'b10_0001,  // FP <-> FP
    FPU_OP_CVT_F2I  = 6'b10_0010,  // FP -> integer
    FPU_OP_CVT_I2F  = 6'b10_0011,  // Integer -> FP

    // Move, op[5:4] = 2'b11.
    FPU_OP_MV_X_FP  = 6'b11_0001,  // FMV.X.W/D
    FPU_OP_MV_FP_X  = 6'b11_0010   // FMV.W/D.X
  } fpu_op_e;

  // CPU -> FPU payload. The valid/ready handshake belongs at the fpu_top port
  // level, not inside the payload.
  typedef struct packed {
    fpu_op_e      op;
    fpu_fmt_e     rs_fmt;
    fpu_fmt_e     dst_fmt;
    fpu_int_fmt_e int_fmt;
    fpu_rm_e      rm;

    fpu_data_t    src_a;
    fpu_data_t    src_b;
    fpu_data_t    src_c;

    fpu_tag_t     tag;
    fpu_rd_t      rd;
  } fpu_req_t;

  typedef struct packed {
    fpu_data_t    result;
    fpu_fflags_t  fflags;
    fpu_tag_t     tag;
    fpu_rd_t      rd;
  } fpu_resp_t;

  typedef struct packed {
    logic     valid;
    fpu_tag_t min_tag;
  } fpu_flush_t;

endpackage : fpu_pkg
