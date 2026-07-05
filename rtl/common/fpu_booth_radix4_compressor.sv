//============================================================================
// Unsigned radix-4 Booth partial-product generator.
//
// Multiplies two equal-width unsigned operands.  The modified Booth recoder
// treats the multiplier as unsigned by adding a zero sign-extension group at
// the top.  The generated signed partial products are shifted into product
// position and exposed directly; no compressor or carry-propagate adder is
// instantiated here.
//============================================================================

module fpu_booth_radix4_compressor #(
  parameter int unsigned WIDTH  = 64,
  parameter int unsigned GROUPS = (WIDTH + 2) / 2,
  parameter int unsigned PP_W   = (2 * WIDTH) + 2
) (
  input  logic [WIDTH-1:0]          lhs_i,
  input  logic [WIDTH-1:0]          rhs_i,
  output logic [GROUPS-1:0][2:0]    booth_code_o,
  output logic [GROUPS-1:0][PP_W-1:0] pp_o
);

  logic [WIDTH+2:0]          rhs_ext;
  logic signed [PP_W-1:0]    lhs_ext;

  function automatic logic [2:0] booth_sel(input int unsigned group_idx);
    return rhs_ext[(2*group_idx) +: 3];
  endfunction

  function automatic logic signed [PP_W-1:0] booth_pp(input logic [2:0] sel);
    logic signed [PP_W-1:0] pp;

    pp = '0;

    unique case (sel)
      3'b000,
      3'b111: pp = '0;
      3'b001,
      3'b010: pp = lhs_ext;
      3'b011: pp = lhs_ext <<< 1;
      3'b100: pp = -(lhs_ext <<< 1);
      3'b101,
      3'b110: pp = -lhs_ext;
      default: pp = '0;
    endcase

    return pp;
  endfunction

  assign rhs_ext = {2'b00, rhs_i, 1'b0};
  assign lhs_ext = $signed({{(PP_W-WIDTH){1'b0}}, lhs_i});

  always_comb begin
    for (int unsigned group_idx = 0; group_idx < GROUPS; group_idx++) begin
      booth_code_o[group_idx] = booth_sel(group_idx);
      pp_o[group_idx]         = booth_pp(booth_sel(group_idx)) <<< (2 * group_idx);
    end
  end

endmodule : fpu_booth_radix4_compressor



