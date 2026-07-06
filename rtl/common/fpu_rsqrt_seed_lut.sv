//============================================================================
// Reciprocal-square-root initial seed LUT with linear 3-term slope correction.
//
// sig_hi_i is the leading 12 bits of a normalized significand in [1, 2).
// exp_odd_i selects the sqrt mantissa domain:
//   0: seed approximates 1/sqrt(m)
//   1: seed approximates 1/sqrt(2*m)
//
// The table stores 512 segment bases plus a sparse signed-digit slope. The
// low 3 address bits are multiplied by that slope using at most three
// shifted partial products; those products and the base are compressed with
// a 4:2 compressor and one final carry-propagate add.
//
// mant_seed_o is Q1.15. Table search bound: max_abs_err=1 LSB, max_rel_err=0.000060554681.
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
  logic [8:0]  seg_idx;
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
  assign seg_idx    = {exp_odd_i, sig_hi_i[10:3]};
  assign seg_n      = sig_hi_i[2:0];

  always_comb begin
    base_seed     = 16'h8000;
    term_neg      = 3'b000;
    term_shift[0] = 4'd15;
    term_shift[1] = 4'd15;
    term_shift[2] = 4'd15;

    if (addr_valid) begin
      unique case (seg_idx)
        9'h000: begin base_seed = 16'd32768; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd5; end
        9'h001: begin base_seed = 16'd32704; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd5; end
        9'h002: begin base_seed = 16'd32641; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd5; end
        9'h003: begin base_seed = 16'd32578; term_neg = 3'b110; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd5; end
        9'h004: begin base_seed = 16'd32515; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd10; term_shift[2] = 4'd11; end
        9'h005: begin base_seed = 16'd32453; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd10; term_shift[2] = 4'd11; end
        9'h006: begin base_seed = 16'd32391; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd10; term_shift[2] = 4'd11; end
        9'h007: begin base_seed = 16'd32329; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h008: begin base_seed = 16'd32267; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h009: begin base_seed = 16'd32206; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h00a: begin base_seed = 16'd32146; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h00b: begin base_seed = 16'd32086; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd9; term_shift[2] = 4'd11; end
        9'h00c: begin base_seed = 16'd32026; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h00d: begin base_seed = 16'd31967; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd9; term_shift[2] = 4'd11; end
        9'h00e: begin base_seed = 16'd31907; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h00f: begin base_seed = 16'd31849; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h010: begin base_seed = 16'd31789; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h011: begin base_seed = 16'd31731; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h012: begin base_seed = 16'd31673; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h013: begin base_seed = 16'd31615; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        9'h014: begin base_seed = 16'd31558; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        9'h015: begin base_seed = 16'd31501; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        9'h016: begin base_seed = 16'd31445; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h017: begin base_seed = 16'd31388; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        9'h018: begin base_seed = 16'd31332; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        9'h019: begin base_seed = 16'd31276; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h01a: begin base_seed = 16'd31221; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        9'h01b: begin base_seed = 16'd31166; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        9'h01c: begin base_seed = 16'd31111; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h01d: begin base_seed = 16'd31057; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        9'h01e: begin base_seed = 16'd31002; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h01f: begin base_seed = 16'd30948; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h020: begin base_seed = 16'd30895; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd8; end
        9'h021: begin base_seed = 16'd30840; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h022: begin base_seed = 16'd30787; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h023: begin base_seed = 16'd30734; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h024: begin base_seed = 16'd30681; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h025: begin base_seed = 16'd30629; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h026: begin base_seed = 16'd30577; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h027: begin base_seed = 16'd30525; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h028: begin base_seed = 16'd30474; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h029: begin base_seed = 16'd30422; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h02a: begin base_seed = 16'd30371; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h02b: begin base_seed = 16'd30321; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h02c: begin base_seed = 16'd30269; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h02d: begin base_seed = 16'd30219; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h02e: begin base_seed = 16'd30169; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h02f: begin base_seed = 16'd30119; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        9'h030: begin base_seed = 16'd30070; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h031: begin base_seed = 16'd30020; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        9'h032: begin base_seed = 16'd29971; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        9'h033: begin base_seed = 16'd29923; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h034: begin base_seed = 16'd29874; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        9'h035: begin base_seed = 16'd29826; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        9'h036: begin base_seed = 16'd29778; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        9'h037: begin base_seed = 16'd29730; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        9'h038: begin base_seed = 16'd29682; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        9'h039: begin base_seed = 16'd29635; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        9'h03a: begin base_seed = 16'd29588; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        9'h03b: begin base_seed = 16'd29541; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        9'h03c: begin base_seed = 16'd29494; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        9'h03d: begin base_seed = 16'd29447; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h03e: begin base_seed = 16'd29401; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h03f: begin base_seed = 16'd29355; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h040: begin base_seed = 16'd29309; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h041: begin base_seed = 16'd29264; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd7; end
        9'h042: begin base_seed = 16'd29217; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h043: begin base_seed = 16'd29172; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h044: begin base_seed = 16'd29127; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h045: begin base_seed = 16'd29082; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h046: begin base_seed = 16'd29037; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h047: begin base_seed = 16'd28993; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h048: begin base_seed = 16'd28949; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h049: begin base_seed = 16'd28905; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h04a: begin base_seed = 16'd28861; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h04b: begin base_seed = 16'd28818; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h04c: begin base_seed = 16'd28774; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h04d: begin base_seed = 16'd28731; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h04e: begin base_seed = 16'd28688; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h04f: begin base_seed = 16'd28646; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h050: begin base_seed = 16'd28603; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h051: begin base_seed = 16'd28559; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h052: begin base_seed = 16'd28517; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h053: begin base_seed = 16'd28475; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h054: begin base_seed = 16'd28433; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h055: begin base_seed = 16'd28391; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h056: begin base_seed = 16'd28350; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h057: begin base_seed = 16'd28309; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h058: begin base_seed = 16'd28267; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h059: begin base_seed = 16'd28226; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h05a: begin base_seed = 16'd28186; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h05b: begin base_seed = 16'd28145; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h05c: begin base_seed = 16'd28105; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h05d: begin base_seed = 16'd28064; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h05e: begin base_seed = 16'd28024; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h05f: begin base_seed = 16'd27984; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h060: begin base_seed = 16'd27945; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h061: begin base_seed = 16'd27905; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h062: begin base_seed = 16'd27866; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h063: begin base_seed = 16'd27827; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h064: begin base_seed = 16'd27787; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h065: begin base_seed = 16'd27749; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h066: begin base_seed = 16'd27710; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h067: begin base_seed = 16'd27671; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h068: begin base_seed = 16'd27633; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h069: begin base_seed = 16'd27595; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h06a: begin base_seed = 16'd27556; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h06b: begin base_seed = 16'd27519; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h06c: begin base_seed = 16'd27479; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h06d: begin base_seed = 16'd27442; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h06e: begin base_seed = 16'd27404; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h06f: begin base_seed = 16'd27367; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h070: begin base_seed = 16'd27330; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h071: begin base_seed = 16'd27293; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h072: begin base_seed = 16'd27256; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h073: begin base_seed = 16'd27219; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h074: begin base_seed = 16'd27183; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h075: begin base_seed = 16'd27146; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h076: begin base_seed = 16'd27110; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h077: begin base_seed = 16'd27074; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h078: begin base_seed = 16'd27038; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h079: begin base_seed = 16'd27002; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h07a: begin base_seed = 16'd26967; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h07b: begin base_seed = 16'd26931; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h07c: begin base_seed = 16'd26896; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h07d: begin base_seed = 16'd26860; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h07e: begin base_seed = 16'd26825; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h07f: begin base_seed = 16'd26790; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h080: begin base_seed = 16'd26755; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h081: begin base_seed = 16'd26720; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h082: begin base_seed = 16'd26686; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h083: begin base_seed = 16'd26651; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h084: begin base_seed = 16'd26616; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h085: begin base_seed = 16'd26582; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h086: begin base_seed = 16'd26548; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h087: begin base_seed = 16'd26514; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h088: begin base_seed = 16'd26480; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h089: begin base_seed = 16'd26447; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h08a: begin base_seed = 16'd26413; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h08b: begin base_seed = 16'd26379; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h08c: begin base_seed = 16'd26346; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h08d: begin base_seed = 16'd26313; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h08e: begin base_seed = 16'd26280; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h08f: begin base_seed = 16'd26247; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h090: begin base_seed = 16'd26214; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h091: begin base_seed = 16'd26182; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h092: begin base_seed = 16'd26149; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h093: begin base_seed = 16'd26117; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h094: begin base_seed = 16'd26084; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h095: begin base_seed = 16'd26052; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h096: begin base_seed = 16'd26020; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h097: begin base_seed = 16'd25988; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h098: begin base_seed = 16'd25956; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h099: begin base_seed = 16'd25924; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h09a: begin base_seed = 16'd25893; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h09b: begin base_seed = 16'd25861; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h09c: begin base_seed = 16'd25830; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h09d: begin base_seed = 16'd25799; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h09e: begin base_seed = 16'd25768; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h09f: begin base_seed = 16'd25737; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h0a0: begin base_seed = 16'd25706; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h0a1: begin base_seed = 16'd25675; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h0a2: begin base_seed = 16'd25644; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h0a3: begin base_seed = 16'd25614; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h0a4: begin base_seed = 16'd25583; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h0a5: begin base_seed = 16'd25552; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h0a6: begin base_seed = 16'd25522; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h0a7: begin base_seed = 16'd25492; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h0a8: begin base_seed = 16'd25462; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h0a9: begin base_seed = 16'd25432; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h0aa: begin base_seed = 16'd25402; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h0ab: begin base_seed = 16'd25372; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h0ac: begin base_seed = 16'd25342; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0ad: begin base_seed = 16'd25313; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h0ae: begin base_seed = 16'd25283; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0af: begin base_seed = 16'd25254; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h0b0: begin base_seed = 16'd25225; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h0b1: begin base_seed = 16'd25195; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0b2: begin base_seed = 16'd25166; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0b3: begin base_seed = 16'd25137; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0b4: begin base_seed = 16'd25109; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0b5: begin base_seed = 16'd25080; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0b6: begin base_seed = 16'd25051; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0b7: begin base_seed = 16'd25023; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0b8: begin base_seed = 16'd24994; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0b9: begin base_seed = 16'd24966; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0ba: begin base_seed = 16'd24938; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0bb: begin base_seed = 16'd24910; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0bc: begin base_seed = 16'd24882; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0bd: begin base_seed = 16'd24854; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0be: begin base_seed = 16'd24826; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0bf: begin base_seed = 16'd24798; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0c0: begin base_seed = 16'd24770; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0c1: begin base_seed = 16'd24743; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0c2: begin base_seed = 16'd24715; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0c3: begin base_seed = 16'd24688; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0c4: begin base_seed = 16'd24661; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0c5: begin base_seed = 16'd24634; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0c6: begin base_seed = 16'd24607; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0c7: begin base_seed = 16'd24580; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0c8: begin base_seed = 16'd24553; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0c9: begin base_seed = 16'd24526; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0ca: begin base_seed = 16'd24499; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0cb: begin base_seed = 16'd24472; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0cc: begin base_seed = 16'd24446; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h0cd: begin base_seed = 16'd24419; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h0ce: begin base_seed = 16'd24391; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0cf: begin base_seed = 16'd24365; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0d0: begin base_seed = 16'd24339; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0d1: begin base_seed = 16'd24313; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0d2: begin base_seed = 16'd24287; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0d3: begin base_seed = 16'd24261; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0d4: begin base_seed = 16'd24235; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0d5: begin base_seed = 16'd24209; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0d6: begin base_seed = 16'd24183; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0d7: begin base_seed = 16'd24158; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0d8: begin base_seed = 16'd24132; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0d9: begin base_seed = 16'd24106; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0da: begin base_seed = 16'd24081; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0db: begin base_seed = 16'd24056; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0dc: begin base_seed = 16'd24030; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0dd: begin base_seed = 16'd24005; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0de: begin base_seed = 16'd23980; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0df: begin base_seed = 16'd23955; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0e0: begin base_seed = 16'd23930; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0e1: begin base_seed = 16'd23905; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0e2: begin base_seed = 16'd23880; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0e3: begin base_seed = 16'd23856; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0e4: begin base_seed = 16'd23831; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0e5: begin base_seed = 16'd23807; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0e6: begin base_seed = 16'd23782; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0e7: begin base_seed = 16'd23758; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0e8: begin base_seed = 16'd23733; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0e9: begin base_seed = 16'd23709; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0ea: begin base_seed = 16'd23685; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0eb: begin base_seed = 16'd23661; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0ec: begin base_seed = 16'd23637; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0ed: begin base_seed = 16'd23613; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0ee: begin base_seed = 16'd23589; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0ef: begin base_seed = 16'd23565; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f0: begin base_seed = 16'd23541; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f1: begin base_seed = 16'd23518; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f2: begin base_seed = 16'd23494; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f3: begin base_seed = 16'd23470; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0f4: begin base_seed = 16'd23447; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f5: begin base_seed = 16'd23424; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f6: begin base_seed = 16'd23400; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0f7: begin base_seed = 16'd23377; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f8: begin base_seed = 16'd23354; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0f9: begin base_seed = 16'd23331; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0fa: begin base_seed = 16'd23308; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0fb: begin base_seed = 16'd23285; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0fc: begin base_seed = 16'd23262; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0fd: begin base_seed = 16'd23239; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h0fe: begin base_seed = 16'd23216; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h0ff: begin base_seed = 16'd23193; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h100: begin base_seed = 16'd23170; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h101: begin base_seed = 16'd23125; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h102: begin base_seed = 16'd23080; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h103: begin base_seed = 16'd23036; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h104: begin base_seed = 16'd22992; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h105: begin base_seed = 16'd22948; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h106: begin base_seed = 16'd22904; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h107: begin base_seed = 16'd22860; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h108: begin base_seed = 16'd22817; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h109: begin base_seed = 16'd22774; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h10a: begin base_seed = 16'd22731; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h10b: begin base_seed = 16'd22689; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h10c: begin base_seed = 16'd22647; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h10d: begin base_seed = 16'd22603; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h10e: begin base_seed = 16'd22561; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h10f: begin base_seed = 16'd22520; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h110: begin base_seed = 16'd22478; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h111: begin base_seed = 16'd22437; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h112: begin base_seed = 16'd22396; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h113: begin base_seed = 16'd22356; term_neg = 3'b111; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h114: begin base_seed = 16'd22315; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h115: begin base_seed = 16'd22275; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h116: begin base_seed = 16'd22235; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h117: begin base_seed = 16'd22195; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h118: begin base_seed = 16'd22155; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h119: begin base_seed = 16'd22116; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h11a: begin base_seed = 16'd22077; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h11b: begin base_seed = 16'd22038; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h11c: begin base_seed = 16'd21999; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h11d: begin base_seed = 16'd21960; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h11e: begin base_seed = 16'd21922; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h11f: begin base_seed = 16'd21884; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h120: begin base_seed = 16'd21846; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h121: begin base_seed = 16'd21808; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h122: begin base_seed = 16'd21769; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h123: begin base_seed = 16'd21732; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h124: begin base_seed = 16'd21695; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h125: begin base_seed = 16'd21658; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h126: begin base_seed = 16'd21621; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h127: begin base_seed = 16'd21584; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h128: begin base_seed = 16'd21548; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h129: begin base_seed = 16'd21512; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h12a: begin base_seed = 16'd21476; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h12b: begin base_seed = 16'd21440; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h12c: begin base_seed = 16'd21404; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h12d: begin base_seed = 16'd21369; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h12e: begin base_seed = 16'd21333; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h12f: begin base_seed = 16'd21298; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h130: begin base_seed = 16'd21263; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h131: begin base_seed = 16'd21228; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h132: begin base_seed = 16'd21193; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h133: begin base_seed = 16'd21159; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h134: begin base_seed = 16'd21124; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h135: begin base_seed = 16'd21090; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h136: begin base_seed = 16'd21056; term_neg = 3'b110; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h137: begin base_seed = 16'd21022; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h138: begin base_seed = 16'd20988; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h139: begin base_seed = 16'd20954; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h13a: begin base_seed = 16'd20921; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h13b: begin base_seed = 16'd20888; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h13c: begin base_seed = 16'd20855; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h13d: begin base_seed = 16'd20822; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h13e: begin base_seed = 16'd20789; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h13f: begin base_seed = 16'd20757; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h140: begin base_seed = 16'd20724; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h141: begin base_seed = 16'd20692; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h142: begin base_seed = 16'd20660; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h143: begin base_seed = 16'd20628; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h144: begin base_seed = 16'd20596; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h145: begin base_seed = 16'd20564; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h146: begin base_seed = 16'd20533; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h147: begin base_seed = 16'd20501; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h148: begin base_seed = 16'd20470; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h149: begin base_seed = 16'd20439; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd6; end
        9'h14a: begin base_seed = 16'd20408; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h14b: begin base_seed = 16'd20377; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h14c: begin base_seed = 16'd20346; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h14d: begin base_seed = 16'd20316; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h14e: begin base_seed = 16'd20285; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h14f: begin base_seed = 16'd20255; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h150: begin base_seed = 16'd20225; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h151: begin base_seed = 16'd20195; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h152: begin base_seed = 16'd20165; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h153: begin base_seed = 16'd20135; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h154: begin base_seed = 16'd20106; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd10; end
        9'h155: begin base_seed = 16'd20076; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h156: begin base_seed = 16'd20047; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h157: begin base_seed = 16'd20017; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h158: begin base_seed = 16'd19988; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h159: begin base_seed = 16'd19959; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h15a: begin base_seed = 16'd19930; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h15b: begin base_seed = 16'd19902; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h15c: begin base_seed = 16'd19873; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h15d: begin base_seed = 16'd19844; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h15e: begin base_seed = 16'd19816; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h15f: begin base_seed = 16'd19788; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h160: begin base_seed = 16'd19760; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h161: begin base_seed = 16'd19732; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h162: begin base_seed = 16'd19704; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h163: begin base_seed = 16'd19676; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h164: begin base_seed = 16'd19649; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h165: begin base_seed = 16'd19621; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h166: begin base_seed = 16'd19594; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h167: begin base_seed = 16'd19567; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h168: begin base_seed = 16'd19540; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h169: begin base_seed = 16'd19512; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h16a: begin base_seed = 16'd19486; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h16b: begin base_seed = 16'd19459; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h16c: begin base_seed = 16'd19432; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h16d: begin base_seed = 16'd19404; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h16e: begin base_seed = 16'd19379; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h16f: begin base_seed = 16'd19353; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd9; end
        9'h170: begin base_seed = 16'd19325; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h171: begin base_seed = 16'd19299; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h172: begin base_seed = 16'd19273; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h173: begin base_seed = 16'd19247; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h174: begin base_seed = 16'd19221; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h175: begin base_seed = 16'd19195; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h176: begin base_seed = 16'd19169; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h177: begin base_seed = 16'd19144; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h178: begin base_seed = 16'd19118; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h179: begin base_seed = 16'd19093; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h17a: begin base_seed = 16'd19068; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h17b: begin base_seed = 16'd19043; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h17c: begin base_seed = 16'd19018; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h17d: begin base_seed = 16'd18993; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h17e: begin base_seed = 16'd18968; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h17f: begin base_seed = 16'd18943; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h180: begin base_seed = 16'd18918; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h181: begin base_seed = 16'd18894; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h182: begin base_seed = 16'd18869; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h183: begin base_seed = 16'd18845; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h184: begin base_seed = 16'd18821; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h185: begin base_seed = 16'd18797; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h186: begin base_seed = 16'd18773; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h187: begin base_seed = 16'd18749; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h188: begin base_seed = 16'd18725; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h189: begin base_seed = 16'd18701; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h18a: begin base_seed = 16'd18677; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h18b: begin base_seed = 16'd18653; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h18c: begin base_seed = 16'd18630; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h18d: begin base_seed = 16'd18606; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h18e: begin base_seed = 16'd18583; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h18f: begin base_seed = 16'd18560; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h190: begin base_seed = 16'd18537; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h191: begin base_seed = 16'd18513; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h192: begin base_seed = 16'd18490; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h193: begin base_seed = 16'd18468; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h194: begin base_seed = 16'd18445; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h195: begin base_seed = 16'd18422; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h196: begin base_seed = 16'd18399; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h197: begin base_seed = 16'd18377; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h198: begin base_seed = 16'd18354; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h199: begin base_seed = 16'd18332; term_neg = 3'b100; term_shift[0] = 4'd5; term_shift[1] = 4'd6; term_shift[2] = 4'd8; end
        9'h19a: begin base_seed = 16'd18309; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h19b: begin base_seed = 16'd18287; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h19c: begin base_seed = 16'd18265; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h19d: begin base_seed = 16'd18243; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h19e: begin base_seed = 16'd18221; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h19f: begin base_seed = 16'd18199; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h1a0: begin base_seed = 16'd18177; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h1a1: begin base_seed = 16'd18155; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h1a2: begin base_seed = 16'd18132; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1a3: begin base_seed = 16'd18112; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd10; end
        9'h1a4: begin base_seed = 16'd18089; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1a5: begin base_seed = 16'd18067; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1a6: begin base_seed = 16'd18046; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1a7: begin base_seed = 16'd18025; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1a8: begin base_seed = 16'd18004; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1a9: begin base_seed = 16'd17982; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1aa: begin base_seed = 16'd17961; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1ab: begin base_seed = 16'd17940; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1ac: begin base_seed = 16'd17919; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1ad: begin base_seed = 16'd17898; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1ae: begin base_seed = 16'd17878; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1af: begin base_seed = 16'd17857; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1b0: begin base_seed = 16'd17836; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1b1: begin base_seed = 16'd17816; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1b2: begin base_seed = 16'd17795; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1b3: begin base_seed = 16'd17775; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1b4: begin base_seed = 16'd17754; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1b5: begin base_seed = 16'd17734; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1b6: begin base_seed = 16'd17714; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1b7: begin base_seed = 16'd17694; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1b8: begin base_seed = 16'd17674; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1b9: begin base_seed = 16'd17654; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1ba: begin base_seed = 16'd17634; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1bb: begin base_seed = 16'd17614; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1bc: begin base_seed = 16'd17594; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1bd: begin base_seed = 16'd17574; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1be: begin base_seed = 16'd17555; term_neg = 3'b100; term_shift[0] = 4'd6; term_shift[1] = 4'd8; term_shift[2] = 4'd9; end
        9'h1bf: begin base_seed = 16'd17535; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1c0: begin base_seed = 16'd17515; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1c1: begin base_seed = 16'd17496; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1c2: begin base_seed = 16'd17476; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1c3: begin base_seed = 16'd17457; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1c4: begin base_seed = 16'd17438; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1c5: begin base_seed = 16'd17418; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1c6: begin base_seed = 16'd17399; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1c7: begin base_seed = 16'd17380; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1c8: begin base_seed = 16'd17361; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1c9: begin base_seed = 16'd17342; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1ca: begin base_seed = 16'd17323; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1cb: begin base_seed = 16'd17304; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1cc: begin base_seed = 16'd17285; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1cd: begin base_seed = 16'd17267; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1ce: begin base_seed = 16'd17248; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1cf: begin base_seed = 16'd17229; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1d0: begin base_seed = 16'd17211; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd9; end
        9'h1d1: begin base_seed = 16'd17192; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1d2: begin base_seed = 16'd17173; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1d3: begin base_seed = 16'd17155; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1d4: begin base_seed = 16'd17137; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1d5: begin base_seed = 16'd17118; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1d6: begin base_seed = 16'd17100; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1d7: begin base_seed = 16'd17082; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1d8: begin base_seed = 16'd17064; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1d9: begin base_seed = 16'd17046; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1da: begin base_seed = 16'd17028; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1db: begin base_seed = 16'd17010; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1dc: begin base_seed = 16'd16992; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1dd: begin base_seed = 16'd16974; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1de: begin base_seed = 16'd16957; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1df: begin base_seed = 16'd16939; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1e0: begin base_seed = 16'd16921; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1e1: begin base_seed = 16'd16904; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1e2: begin base_seed = 16'd16886; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1e3: begin base_seed = 16'd16869; term_neg = 3'b110; term_shift[0] = 4'd7; term_shift[1] = 4'd9; term_shift[2] = 4'd10; end
        9'h1e4: begin base_seed = 16'd16851; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1e5: begin base_seed = 16'd16834; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1e6: begin base_seed = 16'd16816; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1e7: begin base_seed = 16'd16799; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1e8: begin base_seed = 16'd16782; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1e9: begin base_seed = 16'd16765; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1ea: begin base_seed = 16'd16747; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1eb: begin base_seed = 16'd16730; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1ec: begin base_seed = 16'd16713; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1ed: begin base_seed = 16'd16696; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1ee: begin base_seed = 16'd16680; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1ef: begin base_seed = 16'd16663; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1f0: begin base_seed = 16'd16646; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1f1: begin base_seed = 16'd16629; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1f2: begin base_seed = 16'd16613; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1f3: begin base_seed = 16'd16596; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1f4: begin base_seed = 16'd16579; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1f5: begin base_seed = 16'd16563; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1f6: begin base_seed = 16'd16546; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1f7: begin base_seed = 16'd16530; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1f8: begin base_seed = 16'd16513; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1f9: begin base_seed = 16'd16497; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1fa: begin base_seed = 16'd16481; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1fb: begin base_seed = 16'd16465; term_neg = 3'b101; term_shift[0] = 4'd6; term_shift[1] = 4'd7; term_shift[2] = 4'd10; end
        9'h1fc: begin base_seed = 16'd16448; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1fd: begin base_seed = 16'd16432; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1fe: begin base_seed = 16'd16416; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
        9'h1ff: begin base_seed = 16'd16400; term_neg = 3'b101; term_shift[0] = 4'd5; term_shift[1] = 4'd5; term_shift[2] = 4'd7; end
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
      norm_exp_seed_o  = '0;
    end else begin
      norm_mant_seed_o = {mant_seed_o[14:0], 1'b0};
      norm_exp_seed_o  = -$signed({{(EXP_W-1){1'b0}}, 1'b1});
    end
  end

endmodule : fpu_rsqrt_seed_lut
