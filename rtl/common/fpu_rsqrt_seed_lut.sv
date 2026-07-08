//============================================================================
// Reciprocal-square-root initial seed LUT with linear 3-term slope correction.
//
// sig_hi_i is the leading 12 bits of a normalized significand in [1, 2).
// exp_odd_i selects the sqrt mantissa domain:
//   0: seed approximates 1/sqrt(m)
//   1: seed approximates 1/sqrt(2*m)
//
// Default USE_ODD_SCALE=0 uses a 9-bit {exp_odd_i, segment} LUT with
// independent even/odd bases and slopes. USE_ODD_SCALE=1 keeps only the
// even 8-bit LUT, then applies an odd-exponent *sqrt2/2 correction
// (multiplying by 1/sqrt(2) is equivalent).
//
// Each LUT entry stores one segment base plus a sparse signed-digit slope.
// The low 3 address bits are multiplied by that slope using at most three
// shifted partial products; those products and the base are compressed with
// a 4:2 compressor and one final carry-propagate add.
//============================================================================

module fpu_rsqrt_seed_lut #(
  parameter int unsigned EXP_W = 16,
  parameter bit          USE_ODD_SCALE = 1'b0
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
  logic [15:0] mant_seed_lut;
  logic [15:0] mant_seed_raw;

  assign addr_valid = sig_hi_i[11];
  assign seg_idx    = sig_hi_i[10:3];
  assign seg_n      = sig_hi_i[2:0];

  generate
    if (USE_ODD_SCALE) begin : gen_scaled_lut
      always_comb begin
        base_seed     = 16'h8000;
        term_neg      = 3'b000;
        term_shift[0] = 4'd15;
        term_shift[1] = 4'd15;
        term_shift[2] = 4'd15;

        if (addr_valid) begin
          unique case (seg_idx)
        8'h00: begin base_seed = 16'd32764; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd5; end
        8'h01: begin base_seed = 16'd32700; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd10; end
        8'h02: begin base_seed = 16'd32637; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd5; end
        8'h03: begin base_seed = 16'd32574; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd10; end
        8'h04: begin base_seed = 16'd32511; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd10; end
        8'h05: begin base_seed = 16'd32449; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd10; end
        8'h06: begin base_seed = 16'd32387; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'h07: begin base_seed = 16'd32325; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h08: begin base_seed = 16'd32264; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h09: begin base_seed = 16'd32203; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h0a: begin base_seed = 16'd32142; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h0b: begin base_seed = 16'd32082; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h0c: begin base_seed = 16'd32022; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h0d: begin base_seed = 16'd31963; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h0e: begin base_seed = 16'd31904; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h0f: begin base_seed = 16'd31845; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h10: begin base_seed = 16'd31785; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h11: begin base_seed = 16'd31727; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h12: begin base_seed = 16'd31669; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h13: begin base_seed = 16'd31612; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h14: begin base_seed = 16'd31555; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h15: begin base_seed = 16'd31498; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h16: begin base_seed = 16'd31441; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h17: begin base_seed = 16'd31385; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h18: begin base_seed = 16'd31329; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h19: begin base_seed = 16'd31273; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h1a: begin base_seed = 16'd31218; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h1b: begin base_seed = 16'd31162; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h1c: begin base_seed = 16'd31108; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h1d: begin base_seed = 16'd31053; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h1e: begin base_seed = 16'd30999; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h1f: begin base_seed = 16'd30945; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h20: begin base_seed = 16'd30891; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h21: begin base_seed = 16'd30837; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h22: begin base_seed = 16'd30783; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h23: begin base_seed = 16'd30731; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h24: begin base_seed = 16'd30678; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h25: begin base_seed = 16'd30626; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h26: begin base_seed = 16'd30574; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h27: begin base_seed = 16'd30522; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h28: begin base_seed = 16'd30471; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h29: begin base_seed = 16'd30419; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h2a: begin base_seed = 16'd30368; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h2b: begin base_seed = 16'd30318; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h2c: begin base_seed = 16'd30266; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h2d: begin base_seed = 16'd30216; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h2e: begin base_seed = 16'd30166; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h2f: begin base_seed = 16'd30116; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h30: begin base_seed = 16'd30067; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h31: begin base_seed = 16'd30017; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h32: begin base_seed = 16'd29968; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h33: begin base_seed = 16'd29919; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h34: begin base_seed = 16'd29871; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h35: begin base_seed = 16'd29823; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h36: begin base_seed = 16'd29775; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h37: begin base_seed = 16'd29727; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h38: begin base_seed = 16'd29679; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h39: begin base_seed = 16'd29632; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h3a: begin base_seed = 16'd29585; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h3b: begin base_seed = 16'd29538; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h3c: begin base_seed = 16'd29491; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h3d: begin base_seed = 16'd29444; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h3e: begin base_seed = 16'd29398; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h3f: begin base_seed = 16'd29352; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h40: begin base_seed = 16'd29306; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h41: begin base_seed = 16'd29260; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h42: begin base_seed = 16'd29214; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h43: begin base_seed = 16'd29169; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h44: begin base_seed = 16'd29124; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h45: begin base_seed = 16'd29079; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h46: begin base_seed = 16'd29035; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h47: begin base_seed = 16'd28990; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h48: begin base_seed = 16'd28946; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h49: begin base_seed = 16'd28902; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h4a: begin base_seed = 16'd28859; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h4b: begin base_seed = 16'd28815; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h4c: begin base_seed = 16'd28772; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h4d: begin base_seed = 16'd28729; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h4e: begin base_seed = 16'd28686; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h4f: begin base_seed = 16'd28643; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h50: begin base_seed = 16'd28600; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h51: begin base_seed = 16'd28558; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h52: begin base_seed = 16'd28514; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h53: begin base_seed = 16'd28472; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h54: begin base_seed = 16'd28430; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h55: begin base_seed = 16'd28389; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h56: begin base_seed = 16'd28347; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h57: begin base_seed = 16'd28306; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h58: begin base_seed = 16'd28265; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h59: begin base_seed = 16'd28224; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h5a: begin base_seed = 16'd28183; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h5b: begin base_seed = 16'd28143; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h5c: begin base_seed = 16'd28102; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h5d: begin base_seed = 16'd28062; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h5e: begin base_seed = 16'd28022; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h5f: begin base_seed = 16'd27982; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h60: begin base_seed = 16'd27942; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h61: begin base_seed = 16'd27903; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h62: begin base_seed = 16'd27863; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h63: begin base_seed = 16'd27824; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h64: begin base_seed = 16'd27785; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h65: begin base_seed = 16'd27746; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h66: begin base_seed = 16'd27707; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h67: begin base_seed = 16'd27669; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h68: begin base_seed = 16'd27630; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h69: begin base_seed = 16'd27592; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h6a: begin base_seed = 16'd27554; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h6b: begin base_seed = 16'd27516; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h6c: begin base_seed = 16'd27477; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h6d: begin base_seed = 16'd27439; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h6e: begin base_seed = 16'd27402; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h6f: begin base_seed = 16'd27365; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h70: begin base_seed = 16'd27328; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h71: begin base_seed = 16'd27291; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h72: begin base_seed = 16'd27254; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h73: begin base_seed = 16'd27217; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h74: begin base_seed = 16'd27181; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h75: begin base_seed = 16'd27144; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h76: begin base_seed = 16'd27108; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h77: begin base_seed = 16'd27072; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h78: begin base_seed = 16'd27036; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h79: begin base_seed = 16'd27000; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h7a: begin base_seed = 16'd26964; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h7b: begin base_seed = 16'd26929; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h7c: begin base_seed = 16'd26893; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h7d: begin base_seed = 16'd26858; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h7e: begin base_seed = 16'd26823; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h7f: begin base_seed = 16'd26788; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h80: begin base_seed = 16'd26753; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h81: begin base_seed = 16'd26718; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'h82: begin base_seed = 16'd26683; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h83: begin base_seed = 16'd26649; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'h84: begin base_seed = 16'd26614; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h85: begin base_seed = 16'd26580; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h86: begin base_seed = 16'd26546; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h87: begin base_seed = 16'd26512; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h88: begin base_seed = 16'd26478; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h89: begin base_seed = 16'd26445; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'h8a: begin base_seed = 16'd26411; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h8b: begin base_seed = 16'd26377; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h8c: begin base_seed = 16'd26344; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h8d: begin base_seed = 16'd26311; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h8e: begin base_seed = 16'd26278; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h8f: begin base_seed = 16'd26245; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h90: begin base_seed = 16'd26212; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h91: begin base_seed = 16'd26179; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h92: begin base_seed = 16'd26147; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h93: begin base_seed = 16'd26115; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h94: begin base_seed = 16'd26082; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h95: begin base_seed = 16'd26050; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h96: begin base_seed = 16'd26018; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h97: begin base_seed = 16'd25986; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h98: begin base_seed = 16'd25954; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h99: begin base_seed = 16'd25922; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h9a: begin base_seed = 16'd25891; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h9b: begin base_seed = 16'd25859; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h9c: begin base_seed = 16'd25828; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h9d: begin base_seed = 16'd25797; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h9e: begin base_seed = 16'd25766; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'h9f: begin base_seed = 16'd25735; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'ha0: begin base_seed = 16'd25704; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'ha1: begin base_seed = 16'd25673; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'ha2: begin base_seed = 16'd25642; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'ha3: begin base_seed = 16'd25611; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'ha4: begin base_seed = 16'd25581; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'ha5: begin base_seed = 16'd25550; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'ha6: begin base_seed = 16'd25520; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'ha7: begin base_seed = 16'd25490; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'ha8: begin base_seed = 16'd25460; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'ha9: begin base_seed = 16'd25430; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'haa: begin base_seed = 16'd25400; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hab: begin base_seed = 16'd25371; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'hac: begin base_seed = 16'd25341; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'had: begin base_seed = 16'd25311; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hae: begin base_seed = 16'd25282; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'haf: begin base_seed = 16'd25252; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb0: begin base_seed = 16'd25223; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hb1: begin base_seed = 16'd25194; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hb2: begin base_seed = 16'd25165; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hb3: begin base_seed = 16'd25136; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb4: begin base_seed = 16'd25107; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb5: begin base_seed = 16'd25078; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb6: begin base_seed = 16'd25050; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb7: begin base_seed = 16'd25021; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb8: begin base_seed = 16'd24993; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hb9: begin base_seed = 16'd24964; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hba: begin base_seed = 16'd24936; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hbb: begin base_seed = 16'd24908; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hbc: begin base_seed = 16'd24880; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hbd: begin base_seed = 16'd24852; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hbe: begin base_seed = 16'd24824; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hbf: begin base_seed = 16'd24796; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hc0: begin base_seed = 16'd24769; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hc1: begin base_seed = 16'd24741; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hc2: begin base_seed = 16'd24714; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hc3: begin base_seed = 16'd24686; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hc4: begin base_seed = 16'd24659; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hc5: begin base_seed = 16'd24632; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hc6: begin base_seed = 16'd24605; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hc7: begin base_seed = 16'd24578; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hc8: begin base_seed = 16'd24551; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hc9: begin base_seed = 16'd24524; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hca: begin base_seed = 16'd24497; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hcb: begin base_seed = 16'd24471; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hcc: begin base_seed = 16'd24444; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hcd: begin base_seed = 16'd24418; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hce: begin base_seed = 16'd24390; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hcf: begin base_seed = 16'd24365; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hd0: begin base_seed = 16'd24339; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hd1: begin base_seed = 16'd24311; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd2: begin base_seed = 16'd24285; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd3: begin base_seed = 16'd24259; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd4: begin base_seed = 16'd24233; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd5: begin base_seed = 16'd24207; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd6: begin base_seed = 16'd24182; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd7: begin base_seed = 16'd24156; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd8: begin base_seed = 16'd24130; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd9: begin base_seed = 16'd24105; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hda: begin base_seed = 16'd24079; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hdb: begin base_seed = 16'd24054; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hdc: begin base_seed = 16'd24029; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hdd: begin base_seed = 16'd24004; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hde: begin base_seed = 16'd23979; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hdf: begin base_seed = 16'd23954; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'he0: begin base_seed = 16'd23929; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'he1: begin base_seed = 16'd23904; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'he2: begin base_seed = 16'd23879; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he3: begin base_seed = 16'd23854; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he4: begin base_seed = 16'd23830; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'he5: begin base_seed = 16'd23805; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'he6: begin base_seed = 16'd23781; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
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
        8'hf2: begin base_seed = 16'd23493; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf3: begin base_seed = 16'd23469; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf4: begin base_seed = 16'd23446; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf5: begin base_seed = 16'd23422; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf6: begin base_seed = 16'd23399; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf7: begin base_seed = 16'd23376; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hf8: begin base_seed = 16'd23352; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hf9: begin base_seed = 16'd23329; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hfa: begin base_seed = 16'd23306; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hfb: begin base_seed = 16'd23283; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hfc: begin base_seed = 16'd23260; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hfd: begin base_seed = 16'd23238; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hfe: begin base_seed = 16'd23215; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hff: begin base_seed = 16'd23192; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
            default: begin end
          endcase
        end
      end
    end else begin : gen_9bit_lut
      always_comb begin
        base_seed     = 16'h8000;
        term_neg      = 3'b000;
        term_shift[0] = 4'd15;
        term_shift[1] = 4'd15;
        term_shift[2] = 4'd15;

        if (addr_valid) begin
          unique case ({exp_odd_i, seg_idx})
        9'h000: begin base_seed = 16'd32764; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd5; end
        9'h001: begin base_seed = 16'd32700; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd10; end
        9'h002: begin base_seed = 16'd32637; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd5; end
        9'h003: begin base_seed = 16'd32574; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd10; end
        9'h004: begin base_seed = 16'd32511; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd10; end
        9'h005: begin base_seed = 16'd32449; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd10; end
        9'h006: begin base_seed = 16'd32387; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h007: begin base_seed = 16'd32325; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        9'h008: begin base_seed = 16'd32264; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        9'h009: begin base_seed = 16'd32203; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        9'h00a: begin base_seed = 16'd32142; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h00b: begin base_seed = 16'd32082; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h00c: begin base_seed = 16'd32022; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h00d: begin base_seed = 16'd31963; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        9'h00e: begin base_seed = 16'd31904; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        9'h00f: begin base_seed = 16'd31845; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h010: begin base_seed = 16'd31785; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        9'h011: begin base_seed = 16'd31727; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h012: begin base_seed = 16'd31669; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        9'h013: begin base_seed = 16'd31612; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h014: begin base_seed = 16'd31555; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h015: begin base_seed = 16'd31498; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h016: begin base_seed = 16'd31441; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        9'h017: begin base_seed = 16'd31385; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        9'h018: begin base_seed = 16'd31329; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        9'h019: begin base_seed = 16'd31273; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        9'h01a: begin base_seed = 16'd31218; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        9'h01b: begin base_seed = 16'd31162; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h01c: begin base_seed = 16'd31108; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        9'h01d: begin base_seed = 16'd31053; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h01e: begin base_seed = 16'd30999; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h01f: begin base_seed = 16'd30945; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h020: begin base_seed = 16'd30891; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h021: begin base_seed = 16'd30837; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h022: begin base_seed = 16'd30783; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h023: begin base_seed = 16'd30731; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h024: begin base_seed = 16'd30678; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h025: begin base_seed = 16'd30626; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h026: begin base_seed = 16'd30574; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h027: begin base_seed = 16'd30522; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h028: begin base_seed = 16'd30471; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h029: begin base_seed = 16'd30419; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h02a: begin base_seed = 16'd30368; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h02b: begin base_seed = 16'd30318; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h02c: begin base_seed = 16'd30266; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h02d: begin base_seed = 16'd30216; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h02e: begin base_seed = 16'd30166; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h02f: begin base_seed = 16'd30116; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h030: begin base_seed = 16'd30067; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h031: begin base_seed = 16'd30017; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h032: begin base_seed = 16'd29968; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h033: begin base_seed = 16'd29919; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h034: begin base_seed = 16'd29871; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h035: begin base_seed = 16'd29823; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h036: begin base_seed = 16'd29775; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h037: begin base_seed = 16'd29727; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h038: begin base_seed = 16'd29679; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h039: begin base_seed = 16'd29632; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h03a: begin base_seed = 16'd29585; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h03b: begin base_seed = 16'd29538; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h03c: begin base_seed = 16'd29491; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h03d: begin base_seed = 16'd29444; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h03e: begin base_seed = 16'd29398; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h03f: begin base_seed = 16'd29352; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h040: begin base_seed = 16'd29306; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h041: begin base_seed = 16'd29260; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h042: begin base_seed = 16'd29214; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h043: begin base_seed = 16'd29169; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h044: begin base_seed = 16'd29124; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h045: begin base_seed = 16'd29079; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h046: begin base_seed = 16'd29035; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h047: begin base_seed = 16'd28990; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h048: begin base_seed = 16'd28946; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h049: begin base_seed = 16'd28902; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h04a: begin base_seed = 16'd28859; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h04b: begin base_seed = 16'd28815; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h04c: begin base_seed = 16'd28772; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h04d: begin base_seed = 16'd28729; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h04e: begin base_seed = 16'd28686; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h04f: begin base_seed = 16'd28643; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h050: begin base_seed = 16'd28600; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h051: begin base_seed = 16'd28558; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h052: begin base_seed = 16'd28514; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h053: begin base_seed = 16'd28472; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h054: begin base_seed = 16'd28430; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h055: begin base_seed = 16'd28389; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h056: begin base_seed = 16'd28347; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h057: begin base_seed = 16'd28306; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h058: begin base_seed = 16'd28265; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h059: begin base_seed = 16'd28224; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h05a: begin base_seed = 16'd28183; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h05b: begin base_seed = 16'd28143; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h05c: begin base_seed = 16'd28102; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h05d: begin base_seed = 16'd28062; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h05e: begin base_seed = 16'd28022; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h05f: begin base_seed = 16'd27982; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h060: begin base_seed = 16'd27942; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h061: begin base_seed = 16'd27903; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h062: begin base_seed = 16'd27863; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h063: begin base_seed = 16'd27824; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h064: begin base_seed = 16'd27785; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h065: begin base_seed = 16'd27746; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h066: begin base_seed = 16'd27707; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h067: begin base_seed = 16'd27669; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h068: begin base_seed = 16'd27630; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h069: begin base_seed = 16'd27592; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h06a: begin base_seed = 16'd27554; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h06b: begin base_seed = 16'd27516; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h06c: begin base_seed = 16'd27477; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h06d: begin base_seed = 16'd27439; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h06e: begin base_seed = 16'd27402; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h06f: begin base_seed = 16'd27365; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h070: begin base_seed = 16'd27328; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h071: begin base_seed = 16'd27291; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h072: begin base_seed = 16'd27254; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h073: begin base_seed = 16'd27217; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h074: begin base_seed = 16'd27181; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h075: begin base_seed = 16'd27144; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h076: begin base_seed = 16'd27108; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h077: begin base_seed = 16'd27072; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h078: begin base_seed = 16'd27036; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h079: begin base_seed = 16'd27000; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h07a: begin base_seed = 16'd26964; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h07b: begin base_seed = 16'd26929; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h07c: begin base_seed = 16'd26893; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h07d: begin base_seed = 16'd26858; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h07e: begin base_seed = 16'd26823; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h07f: begin base_seed = 16'd26788; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h080: begin base_seed = 16'd26753; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h081: begin base_seed = 16'd26718; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h082: begin base_seed = 16'd26683; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h083: begin base_seed = 16'd26649; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h084: begin base_seed = 16'd26614; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h085: begin base_seed = 16'd26580; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h086: begin base_seed = 16'd26546; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h087: begin base_seed = 16'd26512; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h088: begin base_seed = 16'd26478; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h089: begin base_seed = 16'd26445; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h08a: begin base_seed = 16'd26411; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h08b: begin base_seed = 16'd26377; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h08c: begin base_seed = 16'd26344; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h08d: begin base_seed = 16'd26311; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h08e: begin base_seed = 16'd26278; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h08f: begin base_seed = 16'd26245; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h090: begin base_seed = 16'd26212; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h091: begin base_seed = 16'd26179; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h092: begin base_seed = 16'd26147; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h093: begin base_seed = 16'd26115; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h094: begin base_seed = 16'd26082; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h095: begin base_seed = 16'd26050; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h096: begin base_seed = 16'd26018; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h097: begin base_seed = 16'd25986; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h098: begin base_seed = 16'd25954; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h099: begin base_seed = 16'd25922; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h09a: begin base_seed = 16'd25891; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h09b: begin base_seed = 16'd25859; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h09c: begin base_seed = 16'd25828; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h09d: begin base_seed = 16'd25797; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h09e: begin base_seed = 16'd25766; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h09f: begin base_seed = 16'd25735; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h0a0: begin base_seed = 16'd25704; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h0a1: begin base_seed = 16'd25673; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h0a2: begin base_seed = 16'd25642; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h0a3: begin base_seed = 16'd25611; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h0a4: begin base_seed = 16'd25581; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h0a5: begin base_seed = 16'd25550; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h0a6: begin base_seed = 16'd25520; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h0a7: begin base_seed = 16'd25490; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h0a8: begin base_seed = 16'd25460; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h0a9: begin base_seed = 16'd25430; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h0aa: begin base_seed = 16'd25400; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h0ab: begin base_seed = 16'd25371; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h0ac: begin base_seed = 16'd25341; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h0ad: begin base_seed = 16'd25311; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h0ae: begin base_seed = 16'd25282; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h0af: begin base_seed = 16'd25252; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0b0: begin base_seed = 16'd25223; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h0b1: begin base_seed = 16'd25194; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h0b2: begin base_seed = 16'd25165; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h0b3: begin base_seed = 16'd25136; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0b4: begin base_seed = 16'd25107; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0b5: begin base_seed = 16'd25078; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0b6: begin base_seed = 16'd25050; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0b7: begin base_seed = 16'd25021; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0b8: begin base_seed = 16'd24993; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0b9: begin base_seed = 16'd24964; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0ba: begin base_seed = 16'd24936; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0bb: begin base_seed = 16'd24908; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0bc: begin base_seed = 16'd24880; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0bd: begin base_seed = 16'd24852; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0be: begin base_seed = 16'd24824; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0bf: begin base_seed = 16'd24796; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0c0: begin base_seed = 16'd24769; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0c1: begin base_seed = 16'd24741; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0c2: begin base_seed = 16'd24714; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0c3: begin base_seed = 16'd24686; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0c4: begin base_seed = 16'd24659; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0c5: begin base_seed = 16'd24632; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0c6: begin base_seed = 16'd24605; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0c7: begin base_seed = 16'd24578; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0c8: begin base_seed = 16'd24551; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0c9: begin base_seed = 16'd24524; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0ca: begin base_seed = 16'd24497; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0cb: begin base_seed = 16'd24471; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0cc: begin base_seed = 16'd24444; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0cd: begin base_seed = 16'd24418; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0ce: begin base_seed = 16'd24390; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0cf: begin base_seed = 16'd24365; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0d0: begin base_seed = 16'd24339; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0d1: begin base_seed = 16'd24311; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0d2: begin base_seed = 16'd24285; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0d3: begin base_seed = 16'd24259; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0d4: begin base_seed = 16'd24233; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0d5: begin base_seed = 16'd24207; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0d6: begin base_seed = 16'd24182; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0d7: begin base_seed = 16'd24156; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0d8: begin base_seed = 16'd24130; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0d9: begin base_seed = 16'd24105; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0da: begin base_seed = 16'd24079; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0db: begin base_seed = 16'd24054; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0dc: begin base_seed = 16'd24029; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0dd: begin base_seed = 16'd24004; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0de: begin base_seed = 16'd23979; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0df: begin base_seed = 16'd23954; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0e0: begin base_seed = 16'd23929; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0e1: begin base_seed = 16'd23904; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0e2: begin base_seed = 16'd23879; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0e3: begin base_seed = 16'd23854; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0e4: begin base_seed = 16'd23830; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0e5: begin base_seed = 16'd23805; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0e6: begin base_seed = 16'd23781; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0e7: begin base_seed = 16'd23756; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0e8: begin base_seed = 16'd23732; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0e9: begin base_seed = 16'd23708; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0ea: begin base_seed = 16'd23683; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0eb: begin base_seed = 16'd23659; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0ec: begin base_seed = 16'd23635; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0ed: begin base_seed = 16'd23611; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0ee: begin base_seed = 16'd23587; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0ef: begin base_seed = 16'd23564; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f0: begin base_seed = 16'd23540; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f1: begin base_seed = 16'd23516; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f2: begin base_seed = 16'd23493; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f3: begin base_seed = 16'd23469; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f4: begin base_seed = 16'd23446; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f5: begin base_seed = 16'd23422; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f6: begin base_seed = 16'd23399; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f7: begin base_seed = 16'd23376; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f8: begin base_seed = 16'd23352; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0f9: begin base_seed = 16'd23329; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0fa: begin base_seed = 16'd23306; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0fb: begin base_seed = 16'd23283; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0fc: begin base_seed = 16'd23260; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0fd: begin base_seed = 16'd23238; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0fe: begin base_seed = 16'd23215; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0ff: begin base_seed = 16'd23192; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h100: begin base_seed = 16'd23167; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h101: begin base_seed = 16'd23122; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h102: begin base_seed = 16'd23078; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h103: begin base_seed = 16'd23033; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h104: begin base_seed = 16'd22989; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h105: begin base_seed = 16'd22945; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h106: begin base_seed = 16'd22901; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h107: begin base_seed = 16'd22858; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h108: begin base_seed = 16'd22814; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h109: begin base_seed = 16'd22771; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h10a: begin base_seed = 16'd22729; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h10b: begin base_seed = 16'd22686; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h10c: begin base_seed = 16'd22643; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h10d: begin base_seed = 16'd22601; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h10e: begin base_seed = 16'd22559; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h10f: begin base_seed = 16'd22517; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h110: begin base_seed = 16'd22476; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h111: begin base_seed = 16'd22435; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h112: begin base_seed = 16'd22394; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h113: begin base_seed = 16'd22353; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h114: begin base_seed = 16'd22313; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h115: begin base_seed = 16'd22272; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h116: begin base_seed = 16'd22232; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h117: begin base_seed = 16'd22192; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h118: begin base_seed = 16'd22153; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h119: begin base_seed = 16'd22113; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h11a: begin base_seed = 16'd22074; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h11b: begin base_seed = 16'd22035; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h11c: begin base_seed = 16'd21997; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h11d: begin base_seed = 16'd21958; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h11e: begin base_seed = 16'd21920; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h11f: begin base_seed = 16'd21881; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h120: begin base_seed = 16'd21842; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h121: begin base_seed = 16'd21804; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h122: begin base_seed = 16'd21768; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h123: begin base_seed = 16'd21729; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h124: begin base_seed = 16'd21692; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h125: begin base_seed = 16'd21655; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h126: begin base_seed = 16'd21619; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h127: begin base_seed = 16'd21582; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h128: begin base_seed = 16'd21546; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h129: begin base_seed = 16'd21509; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h12a: begin base_seed = 16'd21473; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h12b: begin base_seed = 16'd21438; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h12c: begin base_seed = 16'd21402; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h12d: begin base_seed = 16'd21366; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h12e: begin base_seed = 16'd21331; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h12f: begin base_seed = 16'd21296; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h130: begin base_seed = 16'd21261; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h131: begin base_seed = 16'd21226; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h132: begin base_seed = 16'd21191; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h133: begin base_seed = 16'd21156; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h134: begin base_seed = 16'd21122; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h135: begin base_seed = 16'd21088; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h136: begin base_seed = 16'd21054; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h137: begin base_seed = 16'd21020; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h138: begin base_seed = 16'd20986; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h139: begin base_seed = 16'd20952; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h13a: begin base_seed = 16'd20919; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h13b: begin base_seed = 16'd20886; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h13c: begin base_seed = 16'd20853; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h13d: begin base_seed = 16'd20820; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h13e: begin base_seed = 16'd20787; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h13f: begin base_seed = 16'd20755; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h140: begin base_seed = 16'd20722; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h141: begin base_seed = 16'd20690; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h142: begin base_seed = 16'd20658; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h143: begin base_seed = 16'd20626; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h144: begin base_seed = 16'd20594; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h145: begin base_seed = 16'd20562; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h146: begin base_seed = 16'd20531; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h147: begin base_seed = 16'd20499; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h148: begin base_seed = 16'd20468; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h149: begin base_seed = 16'd20437; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h14a: begin base_seed = 16'd20406; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h14b: begin base_seed = 16'd20375; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h14c: begin base_seed = 16'd20345; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        9'h14d: begin base_seed = 16'd20314; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h14e: begin base_seed = 16'd20283; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h14f: begin base_seed = 16'd20253; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h150: begin base_seed = 16'd20223; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h151: begin base_seed = 16'd20193; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h152: begin base_seed = 16'd20163; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h153: begin base_seed = 16'd20134; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h154: begin base_seed = 16'd20104; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h155: begin base_seed = 16'd20075; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h156: begin base_seed = 16'd20045; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h157: begin base_seed = 16'd20016; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h158: begin base_seed = 16'd19986; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h159: begin base_seed = 16'd19957; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h15a: begin base_seed = 16'd19928; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h15b: begin base_seed = 16'd19900; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h15c: begin base_seed = 16'd19871; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h15d: begin base_seed = 16'd19843; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h15e: begin base_seed = 16'd19814; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h15f: begin base_seed = 16'd19786; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h160: begin base_seed = 16'd19758; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h161: begin base_seed = 16'd19730; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h162: begin base_seed = 16'd19702; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h163: begin base_seed = 16'd19675; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h164: begin base_seed = 16'd19647; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h165: begin base_seed = 16'd19620; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h166: begin base_seed = 16'd19592; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h167: begin base_seed = 16'd19565; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h168: begin base_seed = 16'd19538; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h169: begin base_seed = 16'd19511; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h16a: begin base_seed = 16'd19484; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h16b: begin base_seed = 16'd19457; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h16c: begin base_seed = 16'd19430; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h16d: begin base_seed = 16'd19402; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h16e: begin base_seed = 16'd19377; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h16f: begin base_seed = 16'd19351; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h170: begin base_seed = 16'd19325; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h171: begin base_seed = 16'd19297; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h172: begin base_seed = 16'd19271; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h173: begin base_seed = 16'd19245; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h174: begin base_seed = 16'd19219; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h175: begin base_seed = 16'd19194; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h176: begin base_seed = 16'd19168; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h177: begin base_seed = 16'd19142; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h178: begin base_seed = 16'd19117; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h179: begin base_seed = 16'd19092; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h17a: begin base_seed = 16'd19066; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h17b: begin base_seed = 16'd19041; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h17c: begin base_seed = 16'd19016; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h17d: begin base_seed = 16'd18991; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h17e: begin base_seed = 16'd18966; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h17f: begin base_seed = 16'd18942; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h180: begin base_seed = 16'd18917; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h181: begin base_seed = 16'd18892; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h182: begin base_seed = 16'd18868; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h183: begin base_seed = 16'd18844; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h184: begin base_seed = 16'd18819; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h185: begin base_seed = 16'd18795; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h186: begin base_seed = 16'd18771; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h187: begin base_seed = 16'd18747; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h188: begin base_seed = 16'd18723; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h189: begin base_seed = 16'd18699; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h18a: begin base_seed = 16'd18676; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h18b: begin base_seed = 16'd18652; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h18c: begin base_seed = 16'd18628; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h18d: begin base_seed = 16'd18605; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h18e: begin base_seed = 16'd18582; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h18f: begin base_seed = 16'd18558; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h190: begin base_seed = 16'd18535; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h191: begin base_seed = 16'd18512; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h192: begin base_seed = 16'd18489; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h193: begin base_seed = 16'd18466; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h194: begin base_seed = 16'd18443; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h195: begin base_seed = 16'd18420; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h196: begin base_seed = 16'd18398; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h197: begin base_seed = 16'd18375; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h198: begin base_seed = 16'd18353; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h199: begin base_seed = 16'd18330; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h19a: begin base_seed = 16'd18308; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h19b: begin base_seed = 16'd18286; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h19c: begin base_seed = 16'd18264; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h19d: begin base_seed = 16'd18241; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h19e: begin base_seed = 16'd18219; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h19f: begin base_seed = 16'd18196; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1a0: begin base_seed = 16'd18176; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h1a1: begin base_seed = 16'd18154; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h1a2: begin base_seed = 16'd18132; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h1a3: begin base_seed = 16'd18109; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1a4: begin base_seed = 16'd18089; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h1a5: begin base_seed = 16'd18066; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1a6: begin base_seed = 16'd18045; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1a7: begin base_seed = 16'd18023; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1a8: begin base_seed = 16'd18002; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1a9: begin base_seed = 16'd17981; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1aa: begin base_seed = 16'd17960; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1ab: begin base_seed = 16'd17939; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1ac: begin base_seed = 16'd17918; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1ad: begin base_seed = 16'd17897; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1ae: begin base_seed = 16'd17876; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1af: begin base_seed = 16'd17856; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1b0: begin base_seed = 16'd17835; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1b1: begin base_seed = 16'd17814; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1b2: begin base_seed = 16'd17794; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1b3: begin base_seed = 16'd17774; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1b4: begin base_seed = 16'd17753; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1b5: begin base_seed = 16'd17733; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1b6: begin base_seed = 16'd17713; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1b7: begin base_seed = 16'd17693; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1b8: begin base_seed = 16'd17672; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1b9: begin base_seed = 16'd17652; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1ba: begin base_seed = 16'd17632; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1bb: begin base_seed = 16'd17613; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1bc: begin base_seed = 16'd17593; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1bd: begin base_seed = 16'd17573; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1be: begin base_seed = 16'd17553; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1bf: begin base_seed = 16'd17534; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1c0: begin base_seed = 16'd17514; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1c1: begin base_seed = 16'd17495; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1c2: begin base_seed = 16'd17475; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1c3: begin base_seed = 16'd17456; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1c4: begin base_seed = 16'd17437; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1c5: begin base_seed = 16'd17417; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1c6: begin base_seed = 16'd17398; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1c7: begin base_seed = 16'd17379; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1c8: begin base_seed = 16'd17360; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1c9: begin base_seed = 16'd17341; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1ca: begin base_seed = 16'd17322; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1cb: begin base_seed = 16'd17303; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1cc: begin base_seed = 16'd17284; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1cd: begin base_seed = 16'd17265; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1ce: begin base_seed = 16'd17247; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1cf: begin base_seed = 16'd17228; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1d0: begin base_seed = 16'd17209; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1d1: begin base_seed = 16'd17191; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1d2: begin base_seed = 16'd17172; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1d3: begin base_seed = 16'd17154; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1d4: begin base_seed = 16'd17135; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1d5: begin base_seed = 16'd17117; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1d6: begin base_seed = 16'd17099; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1d7: begin base_seed = 16'd17081; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1d8: begin base_seed = 16'd17063; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1d9: begin base_seed = 16'd17045; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1da: begin base_seed = 16'd17027; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1db: begin base_seed = 16'd17009; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1dc: begin base_seed = 16'd16991; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1dd: begin base_seed = 16'd16973; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1de: begin base_seed = 16'd16956; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1df: begin base_seed = 16'd16938; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1e0: begin base_seed = 16'd16920; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1e1: begin base_seed = 16'd16903; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1e2: begin base_seed = 16'd16885; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1e3: begin base_seed = 16'd16867; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1e4: begin base_seed = 16'd16850; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1e5: begin base_seed = 16'd16832; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1e6: begin base_seed = 16'd16815; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1e7: begin base_seed = 16'd16798; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1e8: begin base_seed = 16'd16781; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1e9: begin base_seed = 16'd16764; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1ea: begin base_seed = 16'd16746; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1eb: begin base_seed = 16'd16729; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1ec: begin base_seed = 16'd16712; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1ed: begin base_seed = 16'd16695; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1ee: begin base_seed = 16'd16679; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1ef: begin base_seed = 16'd16662; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1f0: begin base_seed = 16'd16645; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1f1: begin base_seed = 16'd16628; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1f2: begin base_seed = 16'd16611; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1f3: begin base_seed = 16'd16595; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1f4: begin base_seed = 16'd16578; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1f5: begin base_seed = 16'd16562; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1f6: begin base_seed = 16'd16545; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1f7: begin base_seed = 16'd16529; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1f8: begin base_seed = 16'd16512; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1f9: begin base_seed = 16'd16496; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1fa: begin base_seed = 16'd16480; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1fb: begin base_seed = 16'd16464; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1fc: begin base_seed = 16'd16447; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1fd: begin base_seed = 16'd16431; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1fe: begin base_seed = 16'd16415; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
        9'h1ff: begin base_seed = 16'd16399; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd7; end
            default: begin end
          endcase
        end
      end
    end
  endgenerate

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

  assign mant_seed_lut = seed_sum_mod[15:0];

  generate
    if (USE_ODD_SCALE) begin : gen_odd_scale
      logic [31:0] odd_scale_product;

      // Odd exponents need x * sqrt2/2; multiplying by 1/sqrt(2) is equivalent.
      // 46340/2^16 is the 6-partial-product CSD-friendly approximation:
      //   46340 = 2^15 + 2^13 + 2^12 + 2^10 + 2^8 + 2^2
      assign odd_scale_product = ({16'd0, mant_seed_lut} << 15) +
                                 ({16'd0, mant_seed_lut} << 13) +
                                 ({16'd0, mant_seed_lut} << 12) +
                                 ({16'd0, mant_seed_lut} << 10) +
                                 ({16'd0, mant_seed_lut} << 8)  +
                                 ({16'd0, mant_seed_lut} << 2);

      assign mant_seed_raw = exp_odd_i ? odd_scale_product[31:16] : mant_seed_lut;
    end else begin : gen_no_odd_scale
      assign mant_seed_raw = mant_seed_lut;
    end
  endgenerate

  assign mant_seed_o = addr_valid ? mant_seed_raw : 16'h8000;

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
