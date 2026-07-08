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
// the same 8-bit table and apply a small fixed shift-add scale by 1/sqrt(2).
//
// mant_seed_o is Q1.15. Center-point exhaustive bound after the odd-exponent
// scale: max_abs_err=5 LSB for exp_odd=0, 3 LSB for exp_odd=1.
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
  logic [17:0] odd_scale_sum;

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
        8'h00: begin base_seed = 16'd32768; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd5; end
        8'h01: begin base_seed = 16'd32704; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd5; end
        8'h02: begin base_seed = 16'd32641; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd5; end
        8'h03: begin base_seed = 16'd32578; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd5; end
        8'h04: begin base_seed = 16'd32515; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd10; term_shift[2] = 4'd11; end
        8'h05: begin base_seed = 16'd32453; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd10; term_shift[2] = 4'd11; end
        8'h06: begin base_seed = 16'd32391; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd10; term_shift[2] = 4'd11; end
        8'h07: begin base_seed = 16'd32329; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'h08: begin base_seed = 16'd32267; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h09: begin base_seed = 16'd32206; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h0a: begin base_seed = 16'd32146; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h0b: begin base_seed = 16'd32086; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd9; term_shift[2] = 4'd11; end
        8'h0c: begin base_seed = 16'd32026; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h0d: begin base_seed = 16'd31967; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd9; term_shift[2] = 4'd11; end
        8'h0e: begin base_seed = 16'd31907; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h0f: begin base_seed = 16'd31849; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h10: begin base_seed = 16'd31789; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h11: begin base_seed = 16'd31731; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h12: begin base_seed = 16'd31673; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h13: begin base_seed = 16'd31615; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        8'h14: begin base_seed = 16'd31558; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        8'h15: begin base_seed = 16'd31501; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        8'h16: begin base_seed = 16'd31445; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h17: begin base_seed = 16'd31388; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        8'h18: begin base_seed = 16'd31332; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        8'h19: begin base_seed = 16'd31276; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h1a: begin base_seed = 16'd31221; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        8'h1b: begin base_seed = 16'd31166; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        8'h1c: begin base_seed = 16'd31111; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h1d: begin base_seed = 16'd31057; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        8'h1e: begin base_seed = 16'd31002; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h1f: begin base_seed = 16'd30948; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h20: begin base_seed = 16'd30895; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        8'h21: begin base_seed = 16'd30840; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h22: begin base_seed = 16'd30787; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h23: begin base_seed = 16'd30734; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h24: begin base_seed = 16'd30681; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h25: begin base_seed = 16'd30629; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h26: begin base_seed = 16'd30577; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h27: begin base_seed = 16'd30525; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h28: begin base_seed = 16'd30474; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h29: begin base_seed = 16'd30422; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h2a: begin base_seed = 16'd30371; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h2b: begin base_seed = 16'd30321; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h2c: begin base_seed = 16'd30269; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h2d: begin base_seed = 16'd30219; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h2e: begin base_seed = 16'd30169; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h2f: begin base_seed = 16'd30119; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        8'h30: begin base_seed = 16'd30070; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h31: begin base_seed = 16'd30020; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        8'h32: begin base_seed = 16'd29971; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        8'h33: begin base_seed = 16'd29923; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h34: begin base_seed = 16'd29874; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        8'h35: begin base_seed = 16'd29826; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        8'h36: begin base_seed = 16'd29778; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        8'h37: begin base_seed = 16'd29730; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        8'h38: begin base_seed = 16'd29682; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        8'h39: begin base_seed = 16'd29635; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        8'h3a: begin base_seed = 16'd29588; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        8'h3b: begin base_seed = 16'd29541; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        8'h3c: begin base_seed = 16'd29494; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        8'h3d: begin base_seed = 16'd29447; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h3e: begin base_seed = 16'd29401; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h3f: begin base_seed = 16'd29355; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h40: begin base_seed = 16'd29309; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h41: begin base_seed = 16'd29264; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        8'h42: begin base_seed = 16'd29217; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h43: begin base_seed = 16'd29172; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h44: begin base_seed = 16'd29127; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h45: begin base_seed = 16'd29082; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h46: begin base_seed = 16'd29037; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h47: begin base_seed = 16'd28993; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h48: begin base_seed = 16'd28949; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h49: begin base_seed = 16'd28905; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h4a: begin base_seed = 16'd28861; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h4b: begin base_seed = 16'd28818; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h4c: begin base_seed = 16'd28774; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h4d: begin base_seed = 16'd28731; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h4e: begin base_seed = 16'd28688; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h4f: begin base_seed = 16'd28646; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h50: begin base_seed = 16'd28603; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h51: begin base_seed = 16'd28559; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h52: begin base_seed = 16'd28517; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h53: begin base_seed = 16'd28475; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h54: begin base_seed = 16'd28433; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h55: begin base_seed = 16'd28391; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h56: begin base_seed = 16'd28350; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h57: begin base_seed = 16'd28309; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h58: begin base_seed = 16'd28267; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h59: begin base_seed = 16'd28226; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h5a: begin base_seed = 16'd28186; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h5b: begin base_seed = 16'd28145; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h5c: begin base_seed = 16'd28105; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h5d: begin base_seed = 16'd28064; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h5e: begin base_seed = 16'd28024; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h5f: begin base_seed = 16'd27984; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h60: begin base_seed = 16'd27945; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h61: begin base_seed = 16'd27905; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h62: begin base_seed = 16'd27866; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h63: begin base_seed = 16'd27827; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h64: begin base_seed = 16'd27787; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h65: begin base_seed = 16'd27749; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h66: begin base_seed = 16'd27710; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h67: begin base_seed = 16'd27671; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h68: begin base_seed = 16'd27633; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h69: begin base_seed = 16'd27595; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h6a: begin base_seed = 16'd27556; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h6b: begin base_seed = 16'd27519; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h6c: begin base_seed = 16'd27479; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h6d: begin base_seed = 16'd27442; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h6e: begin base_seed = 16'd27404; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h6f: begin base_seed = 16'd27367; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h70: begin base_seed = 16'd27330; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h71: begin base_seed = 16'd27293; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h72: begin base_seed = 16'd27256; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h73: begin base_seed = 16'd27219; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h74: begin base_seed = 16'd27183; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h75: begin base_seed = 16'd27146; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h76: begin base_seed = 16'd27110; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h77: begin base_seed = 16'd27074; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h78: begin base_seed = 16'd27038; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h79: begin base_seed = 16'd27002; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h7a: begin base_seed = 16'd26967; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h7b: begin base_seed = 16'd26931; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h7c: begin base_seed = 16'd26896; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h7d: begin base_seed = 16'd26860; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h7e: begin base_seed = 16'd26825; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h7f: begin base_seed = 16'd26790; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h80: begin base_seed = 16'd26755; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'h81: begin base_seed = 16'd26720; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'h82: begin base_seed = 16'd26686; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h83: begin base_seed = 16'd26651; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'h84: begin base_seed = 16'd26616; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h85: begin base_seed = 16'd26582; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h86: begin base_seed = 16'd26548; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h87: begin base_seed = 16'd26514; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h88: begin base_seed = 16'd26480; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h89: begin base_seed = 16'd26447; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'h8a: begin base_seed = 16'd26413; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h8b: begin base_seed = 16'd26379; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h8c: begin base_seed = 16'd26346; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h8d: begin base_seed = 16'd26313; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h8e: begin base_seed = 16'd26280; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h8f: begin base_seed = 16'd26247; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h90: begin base_seed = 16'd26214; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h91: begin base_seed = 16'd26182; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h92: begin base_seed = 16'd26149; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h93: begin base_seed = 16'd26117; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h94: begin base_seed = 16'd26084; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h95: begin base_seed = 16'd26052; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h96: begin base_seed = 16'd26020; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h97: begin base_seed = 16'd25988; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h98: begin base_seed = 16'd25956; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h99: begin base_seed = 16'd25924; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h9a: begin base_seed = 16'd25893; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h9b: begin base_seed = 16'd25861; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h9c: begin base_seed = 16'd25830; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h9d: begin base_seed = 16'd25799; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h9e: begin base_seed = 16'd25768; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h9f: begin base_seed = 16'd25737; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'ha0: begin base_seed = 16'd25706; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'ha1: begin base_seed = 16'd25675; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'ha2: begin base_seed = 16'd25644; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'ha3: begin base_seed = 16'd25614; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'ha4: begin base_seed = 16'd25583; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'ha5: begin base_seed = 16'd25552; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'ha6: begin base_seed = 16'd25522; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'ha7: begin base_seed = 16'd25492; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'ha8: begin base_seed = 16'd25462; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'ha9: begin base_seed = 16'd25432; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'haa: begin base_seed = 16'd25402; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hab: begin base_seed = 16'd25372; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hac: begin base_seed = 16'd25342; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'had: begin base_seed = 16'd25313; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hae: begin base_seed = 16'd25283; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'haf: begin base_seed = 16'd25254; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hb0: begin base_seed = 16'd25225; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hb1: begin base_seed = 16'd25195; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hb2: begin base_seed = 16'd25166; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hb3: begin base_seed = 16'd25137; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hb4: begin base_seed = 16'd25109; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb5: begin base_seed = 16'd25080; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb6: begin base_seed = 16'd25051; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hb7: begin base_seed = 16'd25023; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb8: begin base_seed = 16'd24994; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hb9: begin base_seed = 16'd24966; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hba: begin base_seed = 16'd24938; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hbb: begin base_seed = 16'd24910; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hbc: begin base_seed = 16'd24882; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hbd: begin base_seed = 16'd24854; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hbe: begin base_seed = 16'd24826; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hbf: begin base_seed = 16'd24798; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hc0: begin base_seed = 16'd24770; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hc1: begin base_seed = 16'd24743; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hc2: begin base_seed = 16'd24715; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hc3: begin base_seed = 16'd24688; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hc4: begin base_seed = 16'd24661; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hc5: begin base_seed = 16'd24634; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hc6: begin base_seed = 16'd24607; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hc7: begin base_seed = 16'd24580; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hc8: begin base_seed = 16'd24553; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hc9: begin base_seed = 16'd24526; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hca: begin base_seed = 16'd24499; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hcb: begin base_seed = 16'd24472; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hcc: begin base_seed = 16'd24446; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hcd: begin base_seed = 16'd24419; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hce: begin base_seed = 16'd24391; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hcf: begin base_seed = 16'd24365; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd0: begin base_seed = 16'd24339; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd1: begin base_seed = 16'd24313; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd2: begin base_seed = 16'd24287; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd3: begin base_seed = 16'd24261; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd4: begin base_seed = 16'd24235; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd5: begin base_seed = 16'd24209; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd6: begin base_seed = 16'd24183; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd7: begin base_seed = 16'd24158; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd8: begin base_seed = 16'd24132; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd9: begin base_seed = 16'd24106; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hda: begin base_seed = 16'd24081; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hdb: begin base_seed = 16'd24056; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hdc: begin base_seed = 16'd24030; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hdd: begin base_seed = 16'd24005; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hde: begin base_seed = 16'd23980; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hdf: begin base_seed = 16'd23955; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he0: begin base_seed = 16'd23930; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he1: begin base_seed = 16'd23905; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he2: begin base_seed = 16'd23880; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he3: begin base_seed = 16'd23856; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he4: begin base_seed = 16'd23831; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he5: begin base_seed = 16'd23807; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'he6: begin base_seed = 16'd23782; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he7: begin base_seed = 16'd23758; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he8: begin base_seed = 16'd23733; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he9: begin base_seed = 16'd23709; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hea: begin base_seed = 16'd23685; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'heb: begin base_seed = 16'd23661; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hec: begin base_seed = 16'd23637; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hed: begin base_seed = 16'd23613; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hee: begin base_seed = 16'd23589; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hef: begin base_seed = 16'd23565; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf0: begin base_seed = 16'd23541; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf1: begin base_seed = 16'd23518; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf2: begin base_seed = 16'd23494; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf3: begin base_seed = 16'd23470; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hf4: begin base_seed = 16'd23447; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf5: begin base_seed = 16'd23424; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf6: begin base_seed = 16'd23400; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hf7: begin base_seed = 16'd23377; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf8: begin base_seed = 16'd23354; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf9: begin base_seed = 16'd23331; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hfa: begin base_seed = 16'd23308; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hfb: begin base_seed = 16'd23285; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hfc: begin base_seed = 16'd23262; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hfd: begin base_seed = 16'd23239; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hfe: begin base_seed = 16'd23216; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hff: begin base_seed = 16'd23193; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
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

  assign odd_scale_sum = {2'd0, (mant_seed_even >> 1)} +
                         {2'd0, (mant_seed_even >> 2)} -
                         {2'd0, (mant_seed_even >> 4)} +
                         {2'd0, (mant_seed_even >> 6)} +
                         {2'd0, (mant_seed_even >> 8)} +
                         {2'd0, (mant_seed_even >> 14)} +
                         18'd1;

  assign mant_seed_o = addr_valid ?
                       (exp_odd_i ? odd_scale_sum[15:0] : mant_seed_even) :
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
