//============================================================================
// Reciprocal-square-root initial seed LUT with linear 3-term slope correction.
//
// sig_hi_i is the leading 12 bits of a normalized significand in [1, 2).
// exp_odd_i selects the sqrt mantissa domain:
//   0: seed approximates 1/sqrt(m)
//   1: seed approximates 1/sqrt(2*m)
//
// The table stores 256 segment bases for 1/sqrt(m) plus a sparse signed-digit
// slope. The low 3 address bits are multiplied by that slope using at most
// three shifted partial products; those products and the base are compressed
// with a 4:2 compressor and one final carry-propagate add. Odd exponents reuse
// the same 8-bit table and apply a fixed-point shift-add scale by 1/sqrt(2).
//
// mant_seed_o is Q1.15. Center-point exhaustive bound after the odd-exponent
// scale: max_abs_err=1 LSB for exp_odd=0, 1 LSB for exp_odd=1.
//============================================================================

module fpu_rsqrt_seed_lut #(
  parameter int unsigned EXP_W = 16
) (
  input  logic [11:0]               sig_hi_i,
  input  logic                      exp_odd_i,
  output logic [15:0]               mant_seed_o,
  output logic signed [EXP_W-1:0]   norm_exp_seed_o,
  output logic [15:0]               norm_mant_seed_o
);

  logic        addr_valid;
  logic [7:0]  seg_idx;
  logic [2:0]  seg_n;
  logic [15:0] base_seed;
  logic [2:0]  term_neg;
  logic [3:0]  term_shift [3];
  logic [17:0] n_ext;
  logic [17:0] term_mag [3];
  logic [17:0] term_pp  [3];
  logic [17:0] base_pp;
  logic [17:0] comp_sum;
  logic [17:0] comp_carry;
  logic [17:0] comp_cout;
  logic [17:0] seed_sum_mod;
  logic [15:0] mant_seed_even;
  logic [31:0] odd_scale_product;

  assign addr_valid = sig_hi_i[11];
  assign seg_idx    = sig_hi_i[10:3];
  assign seg_n      = sig_hi_i[2:0];

  always_comb begin
    base_seed     = 16'h8000;
    term_neg      = 3'b000;
    term_shift[0] = 4'd15;
    term_shift[1] = 4'd15;
    term_shift[2] = 4'd15;

    if (addr_valid) begin
      unique case (seg_idx)
        8'h00: begin base_seed = 16'd32764; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd5; end
        8'h01: begin base_seed = 16'd32700; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd5; end
        8'h02: begin base_seed = 16'd32637; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd5; end
        8'h03: begin base_seed = 16'd32574; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd5; end
        8'h04: begin base_seed = 16'd32511; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd5; end
        8'h05: begin base_seed = 16'd32449; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd10; end
        8'h06: begin base_seed = 16'd32388; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd5; end
        8'h07: begin base_seed = 16'd32324; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h08: begin base_seed = 16'd32263; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h09: begin base_seed = 16'd32202; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h0a: begin base_seed = 16'd32142; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h0b: begin base_seed = 16'd32082; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h0c: begin base_seed = 16'd32022; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h0d: begin base_seed = 16'd31963; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h0e: begin base_seed = 16'd31902; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h0f: begin base_seed = 16'd31845; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h10: begin base_seed = 16'd31785; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h11: begin base_seed = 16'd31727; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h12: begin base_seed = 16'd31669; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h13: begin base_seed = 16'd31612; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h14: begin base_seed = 16'd31554; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h15: begin base_seed = 16'd31498; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h16: begin base_seed = 16'd31441; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h17: begin base_seed = 16'd31385; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h18: begin base_seed = 16'd31329; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h19: begin base_seed = 16'd31273; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h1a: begin base_seed = 16'd31217; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h1b: begin base_seed = 16'd31162; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h1c: begin base_seed = 16'd31108; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h1d: begin base_seed = 16'd31053; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h1e: begin base_seed = 16'd30999; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h1f: begin base_seed = 16'd30945; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h20: begin base_seed = 16'd30892; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h21: begin base_seed = 16'd30836; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h22: begin base_seed = 16'd30783; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h23: begin base_seed = 16'd30730; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h24: begin base_seed = 16'd30677; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h25: begin base_seed = 16'd30626; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h26: begin base_seed = 16'd30574; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h27: begin base_seed = 16'd30522; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h28: begin base_seed = 16'd30470; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h29: begin base_seed = 16'd30419; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h2a: begin base_seed = 16'd30367; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h2b: begin base_seed = 16'd30316; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h2c: begin base_seed = 16'd30266; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h2d: begin base_seed = 16'd30216; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h2e: begin base_seed = 16'd30166; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h2f: begin base_seed = 16'd30115; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h30: begin base_seed = 16'd30066; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h31: begin base_seed = 16'd30017; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h32: begin base_seed = 16'd29968; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h33: begin base_seed = 16'd29919; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h34: begin base_seed = 16'd29871; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h35: begin base_seed = 16'd29823; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h36: begin base_seed = 16'd29775; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h37: begin base_seed = 16'd29727; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h38: begin base_seed = 16'd29679; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h39: begin base_seed = 16'd29632; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h3a: begin base_seed = 16'd29584; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h3b: begin base_seed = 16'd29537; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h3c: begin base_seed = 16'd29491; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h3d: begin base_seed = 16'd29445; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h3e: begin base_seed = 16'd29398; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h3f: begin base_seed = 16'd29352; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h40: begin base_seed = 16'd29307; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h41: begin base_seed = 16'd29261; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h42: begin base_seed = 16'd29216; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h43: begin base_seed = 16'd29169; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h44: begin base_seed = 16'd29124; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h45: begin base_seed = 16'd29079; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h46: begin base_seed = 16'd29035; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h47: begin base_seed = 16'd28990; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h48: begin base_seed = 16'd28946; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h49: begin base_seed = 16'd28902; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h4a: begin base_seed = 16'd28858; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h4b: begin base_seed = 16'd28815; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h4c: begin base_seed = 16'd28770; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h4d: begin base_seed = 16'd28728; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h4e: begin base_seed = 16'd28684; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h4f: begin base_seed = 16'd28641; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h50: begin base_seed = 16'd28600; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h51: begin base_seed = 16'd28556; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h52: begin base_seed = 16'd28514; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h53: begin base_seed = 16'd28472; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h54: begin base_seed = 16'd28430; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h55: begin base_seed = 16'd28389; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h56: begin base_seed = 16'd28347; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h57: begin base_seed = 16'd28305; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h58: begin base_seed = 16'd28264; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h59: begin base_seed = 16'd28223; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h5a: begin base_seed = 16'd28183; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h5b: begin base_seed = 16'd28143; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h5c: begin base_seed = 16'd28102; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h5d: begin base_seed = 16'd28062; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h5e: begin base_seed = 16'd28022; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h5f: begin base_seed = 16'd27982; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h60: begin base_seed = 16'd27942; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h61: begin base_seed = 16'd27903; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h62: begin base_seed = 16'd27863; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h63: begin base_seed = 16'd27824; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h64: begin base_seed = 16'd27785; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h65: begin base_seed = 16'd27746; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h66: begin base_seed = 16'd27707; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h67: begin base_seed = 16'd27669; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h68: begin base_seed = 16'd27630; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h69: begin base_seed = 16'd27592; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h6a: begin base_seed = 16'd27554; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h6b: begin base_seed = 16'd27517; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h6c: begin base_seed = 16'd27479; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h6d: begin base_seed = 16'd27441; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h6e: begin base_seed = 16'd27404; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h6f: begin base_seed = 16'd27364; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h70: begin base_seed = 16'd27327; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h71: begin base_seed = 16'd27290; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h72: begin base_seed = 16'd27253; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h73: begin base_seed = 16'd27216; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h74: begin base_seed = 16'd27180; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h75: begin base_seed = 16'd27144; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h76: begin base_seed = 16'd27108; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h77: begin base_seed = 16'd27072; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h78: begin base_seed = 16'd27036; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h79: begin base_seed = 16'd26999; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h7a: begin base_seed = 16'd26964; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h7b: begin base_seed = 16'd26928; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h7c: begin base_seed = 16'd26893; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h7d: begin base_seed = 16'd26857; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h7e: begin base_seed = 16'd26822; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h7f: begin base_seed = 16'd26787; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h80: begin base_seed = 16'd26753; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h81: begin base_seed = 16'd26717; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h82: begin base_seed = 16'd26682; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h83: begin base_seed = 16'd26648; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h84: begin base_seed = 16'd26614; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h85: begin base_seed = 16'd26579; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h86: begin base_seed = 16'd26545; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h87: begin base_seed = 16'd26512; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h88: begin base_seed = 16'd26477; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h89: begin base_seed = 16'd26444; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h8a: begin base_seed = 16'd26411; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h8b: begin base_seed = 16'd26377; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h8c: begin base_seed = 16'd26343; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h8d: begin base_seed = 16'd26310; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h8e: begin base_seed = 16'd26277; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h8f: begin base_seed = 16'd26244; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h90: begin base_seed = 16'd26212; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h91: begin base_seed = 16'd26179; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h92: begin base_seed = 16'd26147; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h93: begin base_seed = 16'd26114; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h94: begin base_seed = 16'd26082; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h95: begin base_seed = 16'd26050; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h96: begin base_seed = 16'd26018; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h97: begin base_seed = 16'd25986; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h98: begin base_seed = 16'd25954; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h99: begin base_seed = 16'd25922; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h9a: begin base_seed = 16'd25891; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h9b: begin base_seed = 16'd25859; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h9c: begin base_seed = 16'd25828; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h9d: begin base_seed = 16'd25797; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h9e: begin base_seed = 16'd25765; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h9f: begin base_seed = 16'd25734; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'ha0: begin base_seed = 16'd25703; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'ha1: begin base_seed = 16'd25673; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'ha2: begin base_seed = 16'd25642; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'ha3: begin base_seed = 16'd25612; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'ha4: begin base_seed = 16'd25581; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'ha5: begin base_seed = 16'd25551; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'ha6: begin base_seed = 16'd25521; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'ha7: begin base_seed = 16'd25491; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'ha8: begin base_seed = 16'd25461; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'ha9: begin base_seed = 16'd25431; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'haa: begin base_seed = 16'd25400; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hab: begin base_seed = 16'd25371; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'hac: begin base_seed = 16'd25342; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'had: begin base_seed = 16'd25312; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'hae: begin base_seed = 16'd25283; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'haf: begin base_seed = 16'd25252; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb0: begin base_seed = 16'd25224; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'hb1: begin base_seed = 16'd25195; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'hb2: begin base_seed = 16'd25166; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'hb3: begin base_seed = 16'd25135; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb4: begin base_seed = 16'd25106; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb5: begin base_seed = 16'd25078; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb6: begin base_seed = 16'd25049; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb7: begin base_seed = 16'd25021; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb8: begin base_seed = 16'd24992; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb9: begin base_seed = 16'd24964; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hba: begin base_seed = 16'd24936; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hbb: begin base_seed = 16'd24908; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hbc: begin base_seed = 16'd24880; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hbd: begin base_seed = 16'd24852; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hbe: begin base_seed = 16'd24824; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hbf: begin base_seed = 16'd24796; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hc0: begin base_seed = 16'd24769; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hc1: begin base_seed = 16'd24741; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hc2: begin base_seed = 16'd24713; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hc3: begin base_seed = 16'd24686; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hc4: begin base_seed = 16'd24659; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hc5: begin base_seed = 16'd24630; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hc6: begin base_seed = 16'd24603; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hc7: begin base_seed = 16'd24576; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hc8: begin base_seed = 16'd24549; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hc9: begin base_seed = 16'd24522; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hca: begin base_seed = 16'd24497; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hcb: begin base_seed = 16'd24469; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hcc: begin base_seed = 16'd24442; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hcd: begin base_seed = 16'd24416; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hce: begin base_seed = 16'd24389; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hcf: begin base_seed = 16'd24363; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd0: begin base_seed = 16'd24337; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd1: begin base_seed = 16'd24311; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd2: begin base_seed = 16'd24285; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd3: begin base_seed = 16'd24259; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd4: begin base_seed = 16'd24233; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd5: begin base_seed = 16'd24207; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd6: begin base_seed = 16'd24181; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd7: begin base_seed = 16'd24155; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd8: begin base_seed = 16'd24130; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd9: begin base_seed = 16'd24105; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hda: begin base_seed = 16'd24079; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hdb: begin base_seed = 16'd24053; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hdc: begin base_seed = 16'd24028; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hdd: begin base_seed = 16'd24003; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hde: begin base_seed = 16'd23978; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hdf: begin base_seed = 16'd23953; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he0: begin base_seed = 16'd23928; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he1: begin base_seed = 16'd23903; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he2: begin base_seed = 16'd23878; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he3: begin base_seed = 16'd23854; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he4: begin base_seed = 16'd23830; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'he5: begin base_seed = 16'd23805; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he6: begin base_seed = 16'd23780; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he7: begin base_seed = 16'd23756; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he8: begin base_seed = 16'd23732; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he9: begin base_seed = 16'd23708; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hea: begin base_seed = 16'd23683; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'heb: begin base_seed = 16'd23659; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hec: begin base_seed = 16'd23635; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hed: begin base_seed = 16'd23611; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hee: begin base_seed = 16'd23587; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hef: begin base_seed = 16'd23564; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf0: begin base_seed = 16'd23540; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf1: begin base_seed = 16'd23516; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf2: begin base_seed = 16'd23492; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf3: begin base_seed = 16'd23469; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf4: begin base_seed = 16'd23445; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf5: begin base_seed = 16'd23422; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf6: begin base_seed = 16'd23399; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf7: begin base_seed = 16'd23375; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf8: begin base_seed = 16'd23352; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf9: begin base_seed = 16'd23329; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hfa: begin base_seed = 16'd23306; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hfb: begin base_seed = 16'd23283; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hfc: begin base_seed = 16'd23260; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hfd: begin base_seed = 16'd23237; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hfe: begin base_seed = 16'd23215; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hff: begin base_seed = 16'd23192; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        default: begin end
      endcase
    end
  end

  assign n_ext   = {7'd0, seg_n, 8'd0};
  assign base_pp = {2'd0, base_seed};

  generate
    for (genvar term_idx = 0; term_idx < 3; term_idx++) begin : gen_terms
      assign term_mag[term_idx] = n_ext >> term_shift[term_idx];
      assign term_pp[term_idx]  = term_neg[2-term_idx] ?
                                  (~term_mag[term_idx] + 18'd1) :
                                  term_mag[term_idx];
    end
  endgenerate

  fpu_compressor_4_2 #(
    .WIDTH(18)
  ) u_seed_compress (
    .a_i    (base_pp),
    .b_i    (term_pp[0]),
    .c_i    (term_pp[1]),
    .d_i    (term_pp[2]),
    .cin_i  (18'd0),
    .sum_o  (comp_sum),
    .carry_o(comp_carry),
    .cout_o (comp_cout)
  );

  assign seed_sum_mod = comp_sum +
                        {comp_carry[16:0], 1'b0} +
                        {comp_cout[16:0], 1'b0};

  assign mant_seed_even = seed_sum_mod[15:0];

  assign odd_scale_product = ({16'd0, mant_seed_even} << 15) +
                             ({16'd0, mant_seed_even} << 13) +
                             ({16'd0, mant_seed_even} << 12) +
                             ({16'd0, mant_seed_even} << 10) +
                             ({16'd0, mant_seed_even} << 8)  +
                             ({16'd0, mant_seed_even} << 2)  +
                             ({16'd0, mant_seed_even} << 1);

  assign mant_seed_o = addr_valid ?
                       (exp_odd_i ? odd_scale_product[31:16] : mant_seed_even) :
                       16'h8000;

  always_comb begin
    if (mant_seed_o[15]) begin
      norm_mant_seed_o = mant_seed_o;
      norm_exp_seed_o  = '0;
    end else begin
      norm_mant_seed_o = {mant_seed_o[14:0], 1'b0};
      norm_exp_seed_o  = -$signed({{(EXP_W-1){1'b0}}, 1'b1});
    end
  end

endmodule : fpu_rsqrt_seed_lut
