//============================================================================
// Guard/round/sticky extractor.
//
// data_i is the discarded bit window. The highest bit becomes guard, the next
// lower bit becomes round, and all remaining lower bits reduce into sticky.
//============================================================================

module fpu_grs
  import fpu_pkg::*;
#(
  parameter int unsigned WIDTH = 64
) (
  input  logic [WIDTH-1:0] data_i,
  output fpu_grs_t         grs_o
);

  assign grs_o.guard = data_i[WIDTH-1];

  generate
    if (WIDTH == 1) begin : gen_no_round_sticky
      assign grs_o.round  = 1'b0;
      assign grs_o.sticky = 1'b0;
    end else if (WIDTH == 2) begin : gen_no_sticky
      assign grs_o.round  = data_i[0];
      assign grs_o.sticky = 1'b0;
    end else begin : gen_full_grs
      assign grs_o.round  = data_i[WIDTH-2];
      assign grs_o.sticky = |data_i[WIDTH-3:0];
    end
  endgenerate

endmodule : fpu_grs
