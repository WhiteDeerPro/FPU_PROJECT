//============================================================================
// Bit compressors for multiplier reduction trees.
//============================================================================

module fpu_compressor_3_2 #(
  parameter int unsigned WIDTH = 64
) (
  input  logic [WIDTH-1:0] a_i,
  input  logic [WIDTH-1:0] b_i,
  input  logic [WIDTH-1:0] c_i,
  output logic [WIDTH-1:0] sum_o,
  output logic [WIDTH-1:0] carry_o
);

  // a + b + c = sum + 2*carry
  assign sum_o   = a_i ^ b_i ^ c_i;
  assign carry_o = (a_i & b_i) | (a_i & c_i) | (b_i & c_i);

endmodule : fpu_compressor_3_2


module fpu_compressor_4_2 #(
  parameter int unsigned WIDTH = 64
) (
  input  logic [WIDTH-1:0] a_i,
  input  logic [WIDTH-1:0] b_i,
  input  logic [WIDTH-1:0] c_i,
  input  logic [WIDTH-1:0] d_i,
  input  logic [WIDTH-1:0] cin_i,
  output logic [WIDTH-1:0] sum_o,
  output logic [WIDTH-1:0] carry_o,
  output logic [WIDTH-1:0] cout_o
);

  logic [WIDTH-1:0] mid_sum;

  // This is the 5-input compressor commonly used as a 4-2 compressor:
  // a + b + c + d + cin = sum + 2*carry + 2*cout.
  // In a compressor array, low-column cout usually becomes the next column's
  // cin; the Boolean structure here is direct compressor logic, not
  // submodule calls.
  assign mid_sum = a_i ^ b_i ^ c_i;
  assign cout_o  = (a_i & b_i) | (a_i & c_i) | (b_i & c_i);

  assign sum_o   = mid_sum ^ d_i ^ cin_i;
  assign carry_o = (mid_sum & d_i) | (mid_sum & cin_i) | (d_i & cin_i);

endmodule : fpu_compressor_4_2
