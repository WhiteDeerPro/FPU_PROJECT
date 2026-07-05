//============================================================================
// Rounding increment decision.
//
// Given the current rounding mode, result sign, retained LSB, and GRS bits,
// produce the one-bit increment used by the caller's datapath.
//============================================================================

module fpu_round_inc
  import fpu_pkg::*;
(
  input  fpu_rm_e  rm_i,
  input  logic     sign_i,
  input  logic     lsb_i,
  input  fpu_grs_t grs_i,
  output logic     inexact_o,
  output logic     inc_o
);

  fpu_rm_e rm_eff;

  assign rm_eff    = (rm_i == FPU_RM_DYN) ? FPU_RM_RNE : rm_i;
  assign inexact_o = grs_i.guard | grs_i.round | grs_i.sticky;

  always_comb begin
    unique case (rm_eff)
      FPU_RM_RNE: inc_o = grs_i.guard & (grs_i.round | grs_i.sticky | lsb_i);
      FPU_RM_RTZ: inc_o = 1'b0;
      FPU_RM_RDN: inc_o = sign_i & inexact_o;
      FPU_RM_RUP: inc_o = ~sign_i & inexact_o;
      FPU_RM_RMM: inc_o = grs_i.guard;
      default:    inc_o = 1'b0;
    endcase
  end

endmodule : fpu_round_inc
