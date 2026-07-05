//============================================================================
// Reciprocal initial seed LUT with linear 3-term slope correction.
//
// sig_hi_i is the leading 12 bits of a normalized significand:
//   {hidden_one, fraction[MSB -: 11]}
// valid addresses are 12'h800 through 12'hfff, representing [1, 2).
//
// The table stores 256 segment bases plus a sparse signed-digit slope. The
// low 3 address bits are multiplied by that slope using at most three
// shifted partial products; those products and the base are compressed with
// a 4:2 compressor and one final carry-propagate add.
//
// mant_seed_o is Q1.15 for a raw 1/m estimate. exp_seed_o is -exp_i.
// norm_* shifts Q1.15 values below 1.0 into a normalized significand seed.
// Table search bound: max_abs_err=1 LSB, max_rel_err=0.000051192939.
//============================================================================

module fpu_recip_seed_lut #(
  parameter int unsigned EXP_W = 16
) (
  input  logic [11:0]               sig_hi_i,
  input  logic signed [EXP_W-1:0]   exp_i,
  output logic [15:0]               mant_seed_o,
  output logic signed [EXP_W-1:0]   exp_seed_o,
  output logic [15:0]               norm_mant_seed_o,
  output logic signed [EXP_W-1:0]   norm_exp_seed_o
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

  assign addr_valid = sig_hi_i[11];
  assign seg_idx    = sig_hi_i[10:3];
  assign seg_n      = sig_hi_i[2:0];
  assign exp_seed_o = -exp_i;

  always_comb begin
    base_seed     = 16'h8000;
    term_neg      = 3'b000;
    term_shift[0] = 4'd15;
    term_shift[1] = 4'd15;
    term_shift[2] = 4'd15;

    if (addr_valid) begin
      unique case (seg_idx)
        8'h00: begin base_seed = 16'd32760; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd4; end
        8'h01: begin base_seed = 16'd32632; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'h02: begin base_seed = 16'd32506; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'h03: begin base_seed = 16'd32380; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h04: begin base_seed = 16'd32256; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h05: begin base_seed = 16'd32132; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h06: begin base_seed = 16'd32010; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h07: begin base_seed = 16'd31888; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h08: begin base_seed = 16'd31767; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h09: begin base_seed = 16'd31648; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h0a: begin base_seed = 16'd31529; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h0b: begin base_seed = 16'd31410; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h0c: begin base_seed = 16'd31293; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h0d: begin base_seed = 16'd31177; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h0e: begin base_seed = 16'd31062; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h0f: begin base_seed = 16'd30947; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h10: begin base_seed = 16'd30833; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        8'h11: begin base_seed = 16'd30720; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        8'h12: begin base_seed = 16'd30608; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h13: begin base_seed = 16'd30497; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h14: begin base_seed = 16'd30387; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h15: begin base_seed = 16'd30277; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h16: begin base_seed = 16'd30168; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h17: begin base_seed = 16'd30060; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h18: begin base_seed = 16'd29953; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h19: begin base_seed = 16'd29845; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h1a: begin base_seed = 16'd29740; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h1b: begin base_seed = 16'd29635; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h1c: begin base_seed = 16'd29531; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h1d: begin base_seed = 16'd29428; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h1e: begin base_seed = 16'd29325; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h1f: begin base_seed = 16'd29221; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h20: begin base_seed = 16'd29120; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h21: begin base_seed = 16'd29020; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h22: begin base_seed = 16'd28920; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h23: begin base_seed = 16'd28821; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h24: begin base_seed = 16'd28722; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h25: begin base_seed = 16'd28624; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h26: begin base_seed = 16'd28526; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h27: begin base_seed = 16'd28430; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h28: begin base_seed = 16'd28334; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h29: begin base_seed = 16'd28239; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        8'h2a: begin base_seed = 16'd28144; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h2b: begin base_seed = 16'd28050; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'h2c: begin base_seed = 16'd27956; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h2d: begin base_seed = 16'd27863; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h2e: begin base_seed = 16'd27771; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h2f: begin base_seed = 16'd27680; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h30: begin base_seed = 16'd27589; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'h31: begin base_seed = 16'd27497; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h32: begin base_seed = 16'd27408; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h33: begin base_seed = 16'd27319; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h34: begin base_seed = 16'd27230; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h35: begin base_seed = 16'd27142; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h36: begin base_seed = 16'd27055; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h37: begin base_seed = 16'd26968; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h38: begin base_seed = 16'd26882; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'h39: begin base_seed = 16'd26794; term_neg = 3'b111; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h3a: begin base_seed = 16'd26709; term_neg = 3'b111; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h3b: begin base_seed = 16'd26625; term_neg = 3'b111; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h3c: begin base_seed = 16'd26541; term_neg = 3'b111; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h3d: begin base_seed = 16'd26457; term_neg = 3'b111; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h3e: begin base_seed = 16'd26374; term_neg = 3'b111; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h3f: begin base_seed = 16'd26291; term_neg = 3'b111; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h40: begin base_seed = 16'd26209; term_neg = 3'b111; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h41: begin base_seed = 16'd26127; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h42: begin base_seed = 16'd26046; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h43: begin base_seed = 16'd25966; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h44: begin base_seed = 16'd25886; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h45: begin base_seed = 16'd25806; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h46: begin base_seed = 16'd25727; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h47: begin base_seed = 16'd25649; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h48: begin base_seed = 16'd25571; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h49: begin base_seed = 16'd25492; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h4a: begin base_seed = 16'd25415; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h4b: begin base_seed = 16'd25338; term_neg = 3'b111; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h4c: begin base_seed = 16'd25262; term_neg = 3'b111; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h4d: begin base_seed = 16'd25186; term_neg = 3'b111; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h4e: begin base_seed = 16'd25111; term_neg = 3'b111; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h4f: begin base_seed = 16'd25035; term_neg = 3'b111; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h50: begin base_seed = 16'd24961; term_neg = 3'b111; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h51: begin base_seed = 16'd24887; term_neg = 3'b111; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h52: begin base_seed = 16'd24814; term_neg = 3'b111; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h53: begin base_seed = 16'd24740; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h54: begin base_seed = 16'd24668; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h55: begin base_seed = 16'd24596; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h56: begin base_seed = 16'd24524; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h57: begin base_seed = 16'd24452; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h58: begin base_seed = 16'd24381; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h59: begin base_seed = 16'd24311; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h5a: begin base_seed = 16'd24241; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h5b: begin base_seed = 16'd24171; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h5c: begin base_seed = 16'd24100; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h5d: begin base_seed = 16'd24032; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h5e: begin base_seed = 16'd23963; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h5f: begin base_seed = 16'd23895; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h60: begin base_seed = 16'd23827; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h61: begin base_seed = 16'd23759; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'h62: begin base_seed = 16'd23692; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'h63: begin base_seed = 16'd23625; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd10; end
        8'h64: begin base_seed = 16'd23559; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd10; end
        8'h65: begin base_seed = 16'd23493; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd10; end
        8'h66: begin base_seed = 16'd23428; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd10; end
        8'h67: begin base_seed = 16'd23362; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd5; end
        8'h68: begin base_seed = 16'd23298; term_neg = 3'b101; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd10; end
        8'h69: begin base_seed = 16'd23233; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd5; end
        8'h6a: begin base_seed = 16'd23169; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd5; end
        8'h6b: begin base_seed = 16'd23105; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd5; end
        8'h6c: begin base_seed = 16'd23042; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd5; end
        8'h6d: begin base_seed = 16'd22979; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd5; end
        8'h6e: begin base_seed = 16'd22916; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd10; end
        8'h6f: begin base_seed = 16'd22853; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'h70: begin base_seed = 16'd22791; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'h71: begin base_seed = 16'd22730; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd10; end
        8'h72: begin base_seed = 16'd22668; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h73: begin base_seed = 16'd22607; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h74: begin base_seed = 16'd22546; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h75: begin base_seed = 16'd22486; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h76: begin base_seed = 16'd22426; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h77: begin base_seed = 16'd22366; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h78: begin base_seed = 16'd22307; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h79: begin base_seed = 16'd22248; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd9; end
        8'h7a: begin base_seed = 16'd22188; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h7b: begin base_seed = 16'd22129; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h7c: begin base_seed = 16'd22071; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h7d: begin base_seed = 16'd22013; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h7e: begin base_seed = 16'd21956; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h7f: begin base_seed = 16'd21899; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h80: begin base_seed = 16'd21842; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h81: begin base_seed = 16'd21785; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h82: begin base_seed = 16'd21729; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h83: begin base_seed = 16'd21673; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h84: begin base_seed = 16'd21617; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h85: begin base_seed = 16'd21561; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h86: begin base_seed = 16'd21506; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd8; end
        8'h87: begin base_seed = 16'd21451; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h88: begin base_seed = 16'd21396; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h89: begin base_seed = 16'd21342; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h8a: begin base_seed = 16'd21288; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h8b: begin base_seed = 16'd21234; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h8c: begin base_seed = 16'd21181; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'h8d: begin base_seed = 16'd21126; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h8e: begin base_seed = 16'd21073; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h8f: begin base_seed = 16'd21021; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h90: begin base_seed = 16'd20968; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h91: begin base_seed = 16'd20916; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h92: begin base_seed = 16'd20864; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h93: begin base_seed = 16'd20812; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h94: begin base_seed = 16'd20761; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h95: begin base_seed = 16'd20710; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'h96: begin base_seed = 16'd20659; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'h97: begin base_seed = 16'd20607; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h98: begin base_seed = 16'd20557; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h99: begin base_seed = 16'd20507; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h9a: begin base_seed = 16'd20457; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h9b: begin base_seed = 16'd20407; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'h9c: begin base_seed = 16'd20357; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h9d: begin base_seed = 16'd20308; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h9e: begin base_seed = 16'd20259; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'h9f: begin base_seed = 16'd20210; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'ha0: begin base_seed = 16'd20162; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'ha1: begin base_seed = 16'd20114; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'ha2: begin base_seed = 16'd20065; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'ha3: begin base_seed = 16'd20018; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'ha4: begin base_seed = 16'd19970; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'ha5: begin base_seed = 16'd19923; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'ha6: begin base_seed = 16'd19875; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'ha7: begin base_seed = 16'd19829; term_neg = 3'b100; term_shift[0] = 4'd4; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        8'ha8: begin base_seed = 16'd19782; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'ha9: begin base_seed = 16'd19735; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'haa: begin base_seed = 16'd19689; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'hab: begin base_seed = 16'd19643; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'hac: begin base_seed = 16'd19597; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'had: begin base_seed = 16'd19552; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        8'hae: begin base_seed = 16'd19505; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'haf: begin base_seed = 16'd19460; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'hb0: begin base_seed = 16'd19415; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'hb1: begin base_seed = 16'd19370; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hb2: begin base_seed = 16'd19326; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'hb3: begin base_seed = 16'd19281; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hb4: begin base_seed = 16'd19237; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hb5: begin base_seed = 16'd19193; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hb6: begin base_seed = 16'd19149; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hb7: begin base_seed = 16'd19106; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hb8: begin base_seed = 16'd19063; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'hb9: begin base_seed = 16'd19019; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hba: begin base_seed = 16'd18976; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hbb: begin base_seed = 16'd18934; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        8'hbc: begin base_seed = 16'd18890; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hbd: begin base_seed = 16'd18848; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hbe: begin base_seed = 16'd18805; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hbf: begin base_seed = 16'd18763; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hc0: begin base_seed = 16'd18722; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hc1: begin base_seed = 16'd18680; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hc2: begin base_seed = 16'd18639; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hc3: begin base_seed = 16'd18597; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hc4: begin base_seed = 16'd18556; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hc5: begin base_seed = 16'd18515; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hc6: begin base_seed = 16'd18474; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hc7: begin base_seed = 16'd18434; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hc8: begin base_seed = 16'd18393; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hc9: begin base_seed = 16'd18353; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hca: begin base_seed = 16'd18313; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hcb: begin base_seed = 16'd18273; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hcc: begin base_seed = 16'd18234; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hcd: begin base_seed = 16'd18194; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hce: begin base_seed = 16'd18155; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hcf: begin base_seed = 16'd18116; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd0: begin base_seed = 16'd18077; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd1: begin base_seed = 16'd18038; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd2: begin base_seed = 16'd17999; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd3: begin base_seed = 16'd17961; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        8'hd4: begin base_seed = 16'd17922; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd5: begin base_seed = 16'd17884; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd6: begin base_seed = 16'd17846; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd7: begin base_seed = 16'd17808; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd8: begin base_seed = 16'd17771; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hd9: begin base_seed = 16'd17733; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        8'hda: begin base_seed = 16'd17695; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hdb: begin base_seed = 16'd17657; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hdc: begin base_seed = 16'd17620; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hdd: begin base_seed = 16'd17584; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hde: begin base_seed = 16'd17547; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'hdf: begin base_seed = 16'd17510; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'he0: begin base_seed = 16'd17474; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'he1: begin base_seed = 16'd17438; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'he2: begin base_seed = 16'd17401; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'he3: begin base_seed = 16'd17366; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'he4: begin base_seed = 16'd17330; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        8'he5: begin base_seed = 16'd17294; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'he6: begin base_seed = 16'd17258; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'he7: begin base_seed = 16'd17223; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'he8: begin base_seed = 16'd17187; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'he9: begin base_seed = 16'd17152; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hea: begin base_seed = 16'd17117; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'heb: begin base_seed = 16'd17083; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        8'hec: begin base_seed = 16'd17048; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hed: begin base_seed = 16'd17013; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hee: begin base_seed = 16'd16979; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hef: begin base_seed = 16'd16944; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'hf0: begin base_seed = 16'd16910; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'hf1: begin base_seed = 16'd16876; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'hf2: begin base_seed = 16'd16842; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'hf3: begin base_seed = 16'd16809; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hf4: begin base_seed = 16'd16775; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'hf5: begin base_seed = 16'd16742; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        8'hf6: begin base_seed = 16'd16708; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'hf7: begin base_seed = 16'd16675; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'hf8: begin base_seed = 16'd16642; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'hf9: begin base_seed = 16'd16609; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        8'hfa: begin base_seed = 16'd16576; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'hfb: begin base_seed = 16'd16543; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'hfc: begin base_seed = 16'd16511; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'hfd: begin base_seed = 16'd16478; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'hfe: begin base_seed = 16'd16446; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
        8'hff: begin base_seed = 16'd16414; term_neg = 3'b011; term_shift[0] = 4'd4; term_shift[1] = 4'd4; term_shift[2] = 4'd6; end
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

  assign mant_seed_o = addr_valid ? seed_sum_mod[15:0] : 16'h8000;

  always_comb begin
    if (mant_seed_o[15]) begin
      norm_mant_seed_o = mant_seed_o;
      norm_exp_seed_o  = exp_seed_o;
    end else begin
      norm_mant_seed_o = {mant_seed_o[14:0], 1'b0};
      norm_exp_seed_o  = exp_seed_o - $signed({{(EXP_W-1){1'b0}}, 1'b1});
    end
  end

endmodule : fpu_recip_seed_lut
