//============================================================================
// Per-port CV-X-IF transaction frontend used by fpu_cvxif_wrapper.
//
// Integration contract:
// - X_NUM_RS=3, X_RFR_WIDTH=64, X_RFW_WIDTH=64, no dual read/write.
// - register.rs carries values read by the CPU from either its FPR or GPR.
//   issue_rs_fpr_o tells the CPU which architectural register bank is needed.
// - result_rd_fpr_o tells the CPU whether result.rd targets the FPR or GPR.
// - result_fflags_o is a required non-standard sideband for commit-time fcsr
//   accumulation in the CPU.
// - One accepted instruction may be in flight per port. Execution starts after
//   non-kill commit, so the arithmetic pipes do not need speculative flush in
//   this conservative first implementation.
// - Commit/kill uses an integration-specific exact {hartid,id} notification per
//   accepted instruction. Standard CV-X-IF batched age-range commit/kill is not
//   implemented by this one-slot-per-port frontend.
//============================================================================

module fpu_cvxif_port #(
  parameter int unsigned X_ID_WIDTH             = 8,
  parameter int unsigned X_HARTID_WIDTH         = 1,
  parameter bit          X_ISSUE_REGISTER_SPLIT = 1'b1
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  fpu_pkg::fpu_rm_e     frm_i,
  output logic [2:0]           issue_rs_fpr_o,
  output logic                 issue_rd_fpr_o,
  output fpu_pkg::fpu_fflags_t result_fflags_o,
  output logic                 result_rd_fpr_o,
  output logic                 native_valid_o,
  output fpu_pkg::fpu_req_t    native_req_o,
  input  logic                 native_ready_i,
  input  logic                 native_result_valid_i,
  output logic                 native_result_ready_o,
  input  fpu_pkg::fpu_resp_t   native_resp_i,
  input  logic                 native_valid_op_i,
  core_v_xif                   xif
);
  import fpu_pkg::*;

  typedef enum logic [1:0] {
    TX_IDLE,
    TX_WAIT,
    TX_EXEC,
    TX_RESULT
  } tx_state_e;

  tx_state_e tx_state_q;

  fpu_req_t  dec_req;
  fpu_req_t  req_q;
  fpu_resp_t result_resp_q;

  logic dec_valid;
  logic dec_rm_valid;
  logic dec_rd_fpr;
  logic [2:0] dec_rs_fpr;
  logic [2:0] dec_rs_read;

  logic [X_ID_WIDTH-1:0]     id_q;
  logic [X_HARTID_WIDTH-1:0] hartid_q;
  logic                      rd_fpr_q;
  logic [2:0]                rs_read_q;
  logic                      operands_ready_q;
  logic                      committed_q;
  logic                      result_exc_q;
  logic                      early_commit_valid_q;
  logic [X_ID_WIDTH-1:0]     early_commit_id_q;
  logic [X_HARTID_WIDTH-1:0] early_commit_hartid_q;
  logic                      early_commit_kill_q;

  logic      issue_fire;
  logic      accepted_issue_fire;
  logic      register_match;
  logic      register_operands_valid;
  logic      commit_issue_match;
  logic      commit_current_match;
  logic      early_commit_issue_match;
  logic      kill_current;

  logic [31:0] instr;
  logic [6:0]  opcode;
  logic [6:0]  funct7;
  logic [2:0]  funct3;
  logic [2:0]  instr_rm;

  assign instr    = xif.issue_req.instr;
  assign opcode   = instr[6:0];
  assign funct3   = instr[14:12];
  assign instr_rm = instr[14:12];
  assign funct7   = instr[31:25];

  function automatic logic concrete_rm_valid(input logic [2:0] rm);
    return rm <= FPU_RM_RMM;
  endfunction

  function automatic fpu_rm_e resolve_rm(
    input logic [2:0] raw_rm,
    input fpu_rm_e    dynamic_rm
  );
    return (raw_rm == FPU_RM_DYN) ? dynamic_rm : fpu_rm_e'(raw_rm);
  endfunction

  function automatic fpu_int_fmt_e int_fmt_from_rs2(input logic [4:0] rs2);
    unique case (rs2)
      5'd0: return FPU_INT_W;
      5'd1: return FPU_INT_WU;
      5'd2: return FPU_INT_L;
      default: return FPU_INT_LU;
    endcase
  endfunction

  // RISC-V F/D decoder. Memory operations are intentionally not accepted.
  always_comb begin
    dec_req       = '0;
    dec_req.op    = FPU_OP_NONE;
    dec_req.rm    = FPU_RM_RNE;
    dec_req.rd    = instr[11:7];
    dec_req.tag   = fpu_tag_t'(xif.issue_req.id);
    dec_req.rs_fmt  = FPU_FMT_S;
    dec_req.dst_fmt = FPU_FMT_S;
    dec_req.int_fmt = FPU_INT_W;

    dec_valid     = 1'b0;
    dec_rm_valid  = concrete_rm_valid(resolve_rm(instr_rm, frm_i));
    dec_rs_read   = 3'b000;
    dec_rs_fpr    = 3'b000;
    dec_rd_fpr    = 1'b0;

    unique case (opcode)
      // FMADD/FMSUB/FNMSUB/FNMADD, including rs3.
      7'b1000011,
      7'b1000111,
      7'b1001011,
      7'b1001111: begin
        if ((instr[26:25] == 2'b00) || (instr[26:25] == 2'b01)) begin
          unique case (opcode)
            7'b1000011: dec_req.op = FPU_OP_FMADD;
            7'b1000111: dec_req.op = FPU_OP_FMSUB;
            7'b1001011: dec_req.op = FPU_OP_FNMSUB;
            default:    dec_req.op = FPU_OP_FNMADD;
          endcase
          dec_req.rs_fmt  = (instr[26:25] == 2'b00) ? FPU_FMT_S : FPU_FMT_D;
          dec_req.dst_fmt = dec_req.rs_fmt;
          dec_req.rm      = resolve_rm(instr_rm, frm_i);
          dec_valid       = dec_rm_valid;
          dec_rs_read     = 3'b111;
          dec_rs_fpr      = 3'b111;
          dec_rd_fpr      = 1'b1;
        end
      end

      // Remaining scalar floating-point operations.
      7'b1010011: begin
        unique case (funct7)
          7'b0000000, 7'b0000001: begin // FADD.S/D
            dec_req.op      = FPU_OP_ADD;
            dec_req.rs_fmt  = funct7[0] ? FPU_FMT_D : FPU_FMT_S;
            dec_req.dst_fmt = dec_req.rs_fmt;
            dec_req.rm      = resolve_rm(instr_rm, frm_i);
            dec_valid       = dec_rm_valid;
            dec_rs_read     = 3'b011;
            dec_rs_fpr      = 3'b011;
            dec_rd_fpr      = 1'b1;
          end

          7'b0000100, 7'b0000101: begin // FSUB.S/D
            dec_req.op      = FPU_OP_SUB;
            dec_req.rs_fmt  = funct7[0] ? FPU_FMT_D : FPU_FMT_S;
            dec_req.dst_fmt = dec_req.rs_fmt;
            dec_req.rm      = resolve_rm(instr_rm, frm_i);
            dec_valid       = dec_rm_valid;
            dec_rs_read     = 3'b011;
            dec_rs_fpr      = 3'b011;
            dec_rd_fpr      = 1'b1;
          end

          7'b0001000, 7'b0001001: begin // FMUL.S/D
            dec_req.op      = FPU_OP_MUL;
            dec_req.rs_fmt  = funct7[0] ? FPU_FMT_D : FPU_FMT_S;
            dec_req.dst_fmt = dec_req.rs_fmt;
            dec_req.rm      = resolve_rm(instr_rm, frm_i);
            dec_valid       = dec_rm_valid;
            dec_rs_read     = 3'b011;
            dec_rs_fpr      = 3'b011;
            dec_rd_fpr      = 1'b1;
          end

          7'b0001100, 7'b0001101: begin // FDIV.S/D
            dec_req.op      = FPU_OP_DIV;
            dec_req.rs_fmt  = funct7[0] ? FPU_FMT_D : FPU_FMT_S;
            dec_req.dst_fmt = dec_req.rs_fmt;
            dec_req.rm      = resolve_rm(instr_rm, frm_i);
            dec_valid       = dec_rm_valid;
            dec_rs_read     = 3'b011;
            dec_rs_fpr      = 3'b011;
            dec_rd_fpr      = 1'b1;
          end

          7'b0101100, 7'b0101101: begin // FSQRT.S/D
            dec_req.op      = FPU_OP_SQRT;
            dec_req.rs_fmt  = funct7[0] ? FPU_FMT_D : FPU_FMT_S;
            dec_req.dst_fmt = dec_req.rs_fmt;
            dec_req.rm      = resolve_rm(instr_rm, frm_i);
            dec_valid       = (instr[24:20] == 5'd0) && dec_rm_valid;
            dec_rs_read     = 3'b001;
            dec_rs_fpr      = 3'b001;
            dec_rd_fpr      = 1'b1;
          end

          7'b0010000, 7'b0010001: begin // FSGNJ[N/X].S/D
            unique case (funct3)
              3'b000: dec_req.op = FPU_OP_SGNJ;
              3'b001: dec_req.op = FPU_OP_SGNJN;
              3'b010: dec_req.op = FPU_OP_SGNJX;
              default: dec_req.op = FPU_OP_NONE;
            endcase
            dec_req.rs_fmt  = funct7[0] ? FPU_FMT_D : FPU_FMT_S;
            dec_req.dst_fmt = dec_req.rs_fmt;
            dec_valid       = (dec_req.op != FPU_OP_NONE);
            dec_rs_read     = 3'b011;
            dec_rs_fpr      = 3'b011;
            dec_rd_fpr      = 1'b1;
          end

          7'b0010100, 7'b0010101: begin // FMIN/FMAX.S/D
            if (funct3 == 3'b000) begin
              dec_req.op = FPU_OP_MIN;
            end else if (funct3 == 3'b001) begin
              dec_req.op = FPU_OP_MAX;
            end
            dec_req.rs_fmt  = funct7[0] ? FPU_FMT_D : FPU_FMT_S;
            dec_req.dst_fmt = dec_req.rs_fmt;
            dec_valid       = (funct3 == 3'b000) || (funct3 == 3'b001);
            dec_rs_read     = 3'b011;
            dec_rs_fpr      = 3'b011;
            dec_rd_fpr      = 1'b1;
          end

          7'b1010000, 7'b1010001: begin // FLE/FLT/FEQ.S/D
            unique case (funct3)
              3'b000: dec_req.op = FPU_OP_LE;
              3'b001: dec_req.op = FPU_OP_LT;
              3'b010: dec_req.op = FPU_OP_EQ;
              default: dec_req.op = FPU_OP_NONE;
            endcase
            dec_req.rs_fmt = funct7[0] ? FPU_FMT_D : FPU_FMT_S;
            dec_valid      = (dec_req.op != FPU_OP_NONE);
            dec_rs_read    = 3'b011;
            dec_rs_fpr     = 3'b011;
            dec_rd_fpr     = 1'b0;
          end

          7'b1100000, 7'b1100001: begin // FCVT.[W/WU/L/LU].S/D
            dec_req.op      = FPU_OP_CVT_F2I;
            dec_req.rs_fmt  = funct7[0] ? FPU_FMT_D : FPU_FMT_S;
            dec_req.int_fmt = int_fmt_from_rs2(instr[24:20]);
            dec_req.rm      = resolve_rm(instr_rm, frm_i);
            dec_valid       = (instr[24:20] <= 5'd3) && dec_rm_valid;
            dec_rs_read     = 3'b001;
            dec_rs_fpr      = 3'b001;
            dec_rd_fpr      = 1'b0;
          end

          7'b1101000, 7'b1101001: begin // FCVT.S/D.[W/WU/L/LU]
            dec_req.op      = FPU_OP_CVT_I2F;
            dec_req.dst_fmt = funct7[0] ? FPU_FMT_D : FPU_FMT_S;
            dec_req.int_fmt = int_fmt_from_rs2(instr[24:20]);
            dec_req.rm      = resolve_rm(instr_rm, frm_i);
            dec_valid       = (instr[24:20] <= 5'd3) && dec_rm_valid;
            dec_rs_read     = 3'b001;
            dec_rs_fpr      = 3'b000;
            dec_rd_fpr      = 1'b1;
          end

          7'b0100000: begin // FCVT.S.D
            dec_req.op      = FPU_OP_CVT_FP;
            dec_req.rs_fmt  = FPU_FMT_D;
            dec_req.dst_fmt = FPU_FMT_S;
            dec_req.rm      = resolve_rm(instr_rm, frm_i);
            dec_valid       = (instr[24:20] == 5'd1) && dec_rm_valid;
            dec_rs_read     = 3'b001;
            dec_rs_fpr      = 3'b001;
            dec_rd_fpr      = 1'b1;
          end

          7'b0100001: begin // FCVT.D.S
            dec_req.op      = FPU_OP_CVT_FP;
            dec_req.rs_fmt  = FPU_FMT_S;
            dec_req.dst_fmt = FPU_FMT_D;
            dec_req.rm      = resolve_rm(instr_rm, frm_i);
            dec_valid       = (instr[24:20] == 5'd0) && dec_rm_valid;
            dec_rs_read     = 3'b001;
            dec_rs_fpr      = 3'b001;
            dec_rd_fpr      = 1'b1;
          end

          7'b1110000, 7'b1110001: begin // FMV.X.W/D or FCLASS.S/D
            dec_req.rs_fmt = funct7[0] ? FPU_FMT_D : FPU_FMT_S;
            if ((instr[24:20] == 5'd0) && (funct3 == 3'b000)) begin
              dec_req.op = FPU_OP_MV_X_FP;
              dec_valid  = 1'b1;
            end else if ((instr[24:20] == 5'd0) && (funct3 == 3'b001)) begin
              dec_req.op = FPU_OP_CLASS;
              dec_valid  = 1'b1;
            end
            dec_rs_read = 3'b001;
            dec_rs_fpr  = 3'b001;
            dec_rd_fpr  = 1'b0;
          end

          7'b1111000, 7'b1111001: begin // FMV.W/D.X
            dec_req.op      = FPU_OP_MV_FP_X;
            dec_req.dst_fmt = funct7[0] ? FPU_FMT_D : FPU_FMT_S;
            dec_valid       = (instr[24:20] == 5'd0) && (funct3 == 3'b000);
            dec_rs_read     = 3'b001;
            dec_rs_fpr      = 3'b000;
            dec_rd_fpr      = 1'b1;
          end

          default: begin
          end
        endcase
      end

      default: begin
      end
    endcase
  end

  assign issue_rs_fpr_o = dec_valid ? dec_rs_fpr : 3'b000;
  assign issue_rd_fpr_o = dec_valid && dec_rd_fpr;

  always_comb begin
    xif.issue_resp               = '0;
    xif.issue_resp.accept        = dec_valid;
    xif.issue_resp.writeback[0]  = dec_valid;
    xif.issue_resp.register_read = '0;
    xif.issue_resp.register_read[2:0] = dec_valid ? dec_rs_read : 3'b000;
    xif.issue_resp.loadstore     = 1'b0;

    register_match = (xif.register.id == xif.issue_req.id) &&
                     (xif.register.hartid == xif.issue_req.hartid);
    register_operands_valid =
      ((xif.register.rs_valid[2:0] & dec_rs_read) == dec_rs_read);

    if (!dec_valid) begin
      // Unsupported instructions can always be rejected without consuming the
      // single transaction slot.
      xif.issue_ready = 1'b1;
    end else if (X_ISSUE_REGISTER_SPLIT) begin
      xif.issue_ready = (tx_state_q == TX_IDLE);
    end else begin
      xif.issue_ready = (tx_state_q == TX_IDLE) && xif.register_valid &&
                        register_match && register_operands_valid;
    end

    xif.register_ready = X_ISSUE_REGISTER_SPLIT ? 1'b1 : xif.issue_ready;
  end

  assign issue_fire          = xif.issue_valid && xif.issue_ready;
  assign accepted_issue_fire = issue_fire && dec_valid;
  assign commit_issue_match  = xif.commit_valid &&
                               (xif.commit.id == xif.issue_req.id) &&
                               (xif.commit.hartid == xif.issue_req.hartid);
  assign commit_current_match = xif.commit_valid &&
                                (xif.commit.id == id_q) &&
                                (xif.commit.hartid == hartid_q);
  assign early_commit_issue_match = early_commit_valid_q &&
                                    (early_commit_id_q == xif.issue_req.id) &&
                                    (early_commit_hartid_q ==
                                     xif.issue_req.hartid);
  assign kill_current = commit_current_match && xif.commit.commit_kill;

  assign native_valid_o = (tx_state_q == TX_WAIT) && operands_ready_q &&
                          committed_q && !kill_current;
  assign native_req_o = req_q;
  assign native_result_ready_o = (tx_state_q == TX_EXEC);

  always_comb begin
    xif.result         = '0;
    xif.result.hartid  = hartid_q;
    xif.result.id      = id_q;
    xif.result.data    = result_resp_q.result;
    xif.result.rd      = result_resp_q.rd;
    xif.result.we[0]   = 1'b1;
    xif.result.exc     = result_exc_q;
    xif.result.exccode = result_exc_q ? 6'd2 : 6'd0;
    xif.result_valid   = (tx_state_q == TX_RESULT);

    result_fflags_o = result_resp_q.fflags;
    result_rd_fpr_o = rd_fpr_q;

    // This FPU wrapper implements no compressed or memory operations.
    xif.compressed_ready       = 1'b1;
    xif.compressed_resp        = '0;
    xif.mem_valid              = 1'b0;
    xif.mem_req                = '0;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tx_state_q       <= TX_IDLE;
      req_q            <= '0;
      result_resp_q    <= '0;
      id_q             <= '0;
      hartid_q         <= '0;
      rd_fpr_q         <= 1'b0;
      rs_read_q        <= '0;
      operands_ready_q <= 1'b0;
      committed_q      <= 1'b0;
      result_exc_q     <= 1'b0;
      early_commit_valid_q  <= 1'b0;
      early_commit_id_q     <= '0;
      early_commit_hartid_q <= '0;
      early_commit_kill_q   <= 1'b0;
    end else begin
      // Commit is allowed as soon as an issue transaction is initiated, even
      // while issue_ready is low. Retain one early commit for the one pending
      // issue request that this conservative wrapper can observe.
      if (early_commit_valid_q &&
          (!xif.issue_valid ||
           (early_commit_id_q != xif.issue_req.id) ||
           (early_commit_hartid_q != xif.issue_req.hartid))) begin
        early_commit_valid_q <= 1'b0;
      end
      if (xif.commit_valid && xif.issue_valid && dec_valid &&
          (xif.commit.id == xif.issue_req.id) &&
          (xif.commit.hartid == xif.issue_req.hartid) &&
          !accepted_issue_fire) begin
        early_commit_valid_q  <= 1'b1;
        early_commit_id_q     <= xif.commit.id;
        early_commit_hartid_q <= xif.commit.hartid;
        early_commit_kill_q   <= xif.commit.commit_kill;
      end

      unique case (tx_state_q)
        TX_IDLE: begin
          operands_ready_q <= 1'b0;
          committed_q      <= 1'b0;
          result_exc_q     <= 1'b0;

          if (accepted_issue_fire) begin
            req_q      <= dec_req;
            id_q       <= xif.issue_req.id;
            hartid_q   <= xif.issue_req.hartid;
            rd_fpr_q   <= dec_rd_fpr;
            rs_read_q  <= dec_rs_read;
            tx_state_q <= TX_WAIT;
            if (early_commit_issue_match) begin
              early_commit_valid_q <= 1'b0;
            end

            if (!X_ISSUE_REGISTER_SPLIT) begin
              req_q.src_a       <= xif.register.rs[0];
              req_q.src_b       <= xif.register.rs[1];
              req_q.src_c       <= xif.register.rs[2];
              operands_ready_q  <= 1'b1;
            end

            if (commit_issue_match || early_commit_issue_match) begin
              if ((commit_issue_match && xif.commit.commit_kill) ||
                  (!commit_issue_match && early_commit_kill_q)) begin
                tx_state_q <= TX_IDLE;
              end else begin
                committed_q <= 1'b1;
              end
            end
          end
        end

        TX_WAIT: begin
          if (X_ISSUE_REGISTER_SPLIT && xif.register_valid &&
              (xif.register.id == id_q) &&
              (xif.register.hartid == hartid_q) &&
              ((xif.register.rs_valid[2:0] & rs_read_q) == rs_read_q)) begin
            req_q.src_a      <= xif.register.rs[0];
            req_q.src_b      <= xif.register.rs[1];
            req_q.src_c      <= xif.register.rs[2];
            operands_ready_q <= 1'b1;
          end

          if (commit_current_match) begin
            if (xif.commit.commit_kill) begin
              tx_state_q <= TX_IDLE;
            end else begin
              committed_q <= 1'b1;
            end
          end

          if (native_valid_o && native_ready_i) begin
            tx_state_q <= TX_EXEC;
          end
        end

        TX_EXEC: begin
          if (native_result_valid_i && native_result_ready_o) begin
            result_resp_q <= native_resp_i;
            result_exc_q  <= !native_valid_op_i;
            tx_state_q    <= TX_RESULT;
          end
        end

        TX_RESULT: begin
          if (xif.result_valid && xif.result_ready) begin
            tx_state_q <= TX_IDLE;
          end
        end

        default: tx_state_q <= TX_IDLE;
      endcase
    end
  end

  initial begin
    if ($bits(xif.register.rs[0]) != FPU_DATA_W ||
        $bits(xif.result.data) != FPU_DATA_W) begin
      $fatal(1, "fpu_cvxif_port requires 64-bit XIF read/write data");
    end
    if ($bits(xif.register.rs) / $bits(xif.register.rs[0]) != 3) begin
      $fatal(1, "fpu_cvxif_port requires X_NUM_RS=3");
    end
  end

endmodule : fpu_cvxif_port

//============================================================================
// Replicated CV-X-IF frontend around one shared, configurable fpu_top.
//
// CV-X-IF superscalar integration is expressed as replicated protocol ports.
// Each port owns one independent protocol transaction slot. The port index is
// used as the internal FPU token, so equal external IDs on different ports do
// not alias. fpu_top performs shared-unit arbitration and response buffering.
//============================================================================
module fpu_cvxif_wrapper #(
  parameter int unsigned X_NUM_PORTS           = 2,
  parameter int unsigned X_ID_WIDTH             = 8,
  parameter int unsigned X_HARTID_WIDTH         = 1,
  parameter bit          X_ISSUE_REGISTER_SPLIT = 1'b1,
  parameter int unsigned FPU_RESP_FIFO_DEPTH    = 32
) (
  input  logic                                      clk_i,
  input  logic                                      rst_ni,
  input  fpu_pkg::fpu_rm_e [X_NUM_PORTS-1:0]       frm_i,
  output logic [X_NUM_PORTS-1:0][2:0]              issue_rs_fpr_o,
  output logic [X_NUM_PORTS-1:0]                   issue_rd_fpr_o,
  output fpu_pkg::fpu_fflags_t [X_NUM_PORTS-1:0]   result_fflags_o,
  output logic [X_NUM_PORTS-1:0]                   result_rd_fpr_o,
  core_v_xif                                        xif [X_NUM_PORTS-1:0]
);
  import fpu_pkg::*;

  logic [X_NUM_PORTS-1:0] port_native_valid;
  fpu_req_t [X_NUM_PORTS-1:0] port_native_req;
  logic [X_NUM_PORTS-1:0] port_native_ready;
  logic [X_NUM_PORTS-1:0] port_result_valid;
  logic [X_NUM_PORTS-1:0] port_result_ready;
  fpu_resp_t [X_NUM_PORTS-1:0] port_result_resp;
  logic [X_NUM_PORTS-1:0] port_result_valid_op;

  logic [X_NUM_PORTS-1:0] fpu_issue_valid;
  fpu_req_t [X_NUM_PORTS-1:0] fpu_issue_req;
  logic [X_NUM_PORTS-1:0] fpu_issue_ready;
  logic [X_NUM_PORTS-1:0] fpu_wb_valid;
  logic [X_NUM_PORTS-1:0] fpu_wb_ready;
  fpu_resp_t [X_NUM_PORTS-1:0] fpu_wb_resp;
  logic [X_NUM_PORTS-1:0] fpu_wb_valid_op;

  for (genvar port_idx = 0; port_idx < X_NUM_PORTS; port_idx++) begin : g_port
    fpu_cvxif_port #(
      .X_ID_WIDTH             (X_ID_WIDTH),
      .X_HARTID_WIDTH         (X_HARTID_WIDTH),
      .X_ISSUE_REGISTER_SPLIT (X_ISSUE_REGISTER_SPLIT)
    ) u_port (
      .clk_i,
      .rst_ni,
      .frm_i                 (frm_i[port_idx]),
      .issue_rs_fpr_o        (issue_rs_fpr_o[port_idx]),
      .issue_rd_fpr_o        (issue_rd_fpr_o[port_idx]),
      .result_fflags_o       (result_fflags_o[port_idx]),
      .result_rd_fpr_o       (result_rd_fpr_o[port_idx]),
      .native_valid_o        (port_native_valid[port_idx]),
      .native_req_o          (port_native_req[port_idx]),
      .native_ready_i        (port_native_ready[port_idx]),
      .native_result_valid_i (port_result_valid[port_idx]),
      .native_result_ready_o (port_result_ready[port_idx]),
      .native_resp_i         (port_result_resp[port_idx]),
      .native_valid_op_i     (port_result_valid_op[port_idx]),
      .xif                    (xif[port_idx])
    );
  end

  assign fpu_issue_valid  = port_native_valid;
  assign port_native_ready = fpu_issue_ready;

  // Attach a unique internal token to each protocol port. External XIF IDs are
  // retained inside the corresponding port slot and restored on result.
  always_comb begin
    fpu_issue_req = port_native_req;
    for (int unsigned port_idx = 0; port_idx < X_NUM_PORTS; port_idx++) begin
      fpu_issue_req[port_idx].tag = fpu_tag_t'(port_idx);
    end
  end

  // Route every backend writeback lane to the protocol slot named by its tag.
  // A stalled result port backpressures only the WB lane currently holding it;
  // other backend WB lanes and other CV-X-IF ports remain independent.
  always_comb begin : p_result_route
    logic [X_NUM_PORTS-1:0] port_claimed;
    int unsigned target_port;

    fpu_wb_ready        = '0;
    port_result_valid   = '0;
    port_result_resp    = '0;
    port_result_valid_op = '0;
    port_claimed        = '0;

    for (int unsigned lane = 0; lane < X_NUM_PORTS; lane++) begin
      target_port = fpu_wb_resp[lane].tag;
      if (fpu_wb_valid[lane] && (target_port < X_NUM_PORTS) &&
          !port_claimed[target_port]) begin
        port_result_valid[target_port]    = 1'b1;
        port_result_resp[target_port]     = fpu_wb_resp[lane];
        port_result_valid_op[target_port] = fpu_wb_valid_op[lane];
        fpu_wb_ready[lane] = port_result_ready[target_port];
        port_claimed[target_port] = 1'b1;
      end
    end
  end

  fpu_top #(
    .ISSUE_WIDTH     (X_NUM_PORTS),
    .WRITEBACK_WIDTH (X_NUM_PORTS),
    .RESP_FIFO_DEPTH (FPU_RESP_FIFO_DEPTH)
  ) u_fpu_top (
    .clk_i,
    .rst_ni,
    .kill_i     ('0),
    .valid_i    (fpu_issue_valid),
    .req_i      (fpu_issue_req),
    .ready_o    (fpu_issue_ready),
    .valid_o    (fpu_wb_valid),
    .ready_i    (fpu_wb_ready),
    .resp_o     (fpu_wb_resp),
    .valid_op_o (fpu_wb_valid_op)
  );

  initial begin
    if ((X_NUM_PORTS < 1) || (X_NUM_PORTS > 4)) begin
      $fatal(1, "fpu_cvxif_wrapper X_NUM_PORTS must be in 1..4");
    end
    if (X_NUM_PORTS > (1 << FPU_TAG_W)) begin
      $fatal(1, "fpu_cvxif_wrapper has insufficient internal tag width");
    end
  end

endmodule : fpu_cvxif_wrapper
