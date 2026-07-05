`timescale 1ns/1ps

module tb_fpu_recip_seed_lut;

  logic [9:0]          sig_hi_i;
  logic signed [15:0] exp_i;
  logic [10:0]        mant_seed_o;
  logic signed [15:0] exp_seed_o;
  logic [10:0]        norm_mant_seed_o;
  logic signed [15:0] norm_exp_seed_o;

  int unsigned errors;
  real         max_center_rel_err;

  fpu_recip_seed_lut dut (
    .sig_hi_i        (sig_hi_i),
    .exp_i           (exp_i),
    .mant_seed_o     (mant_seed_o),
    .exp_seed_o      (exp_seed_o),
    .norm_mant_seed_o(norm_mant_seed_o),
    .norm_exp_seed_o (norm_exp_seed_o)
  );

  function automatic int unsigned expected_seed(input int unsigned addr);
    longint unsigned denom;
    longint unsigned numerator;

    denom        = (2 * addr) + 1;
    numerator    = 1 << 20;
    expected_seed = ((2 * numerator) + denom) / (2 * denom);
  endfunction

  function automatic real abs_real(input real value);
    return (value < 0.0) ? -value : value;
  endfunction

  task automatic check_addr(input int unsigned addr);
    int unsigned exp_seed;
    real         center;
    real         exact;
    real         seed;
    real         rel_err;

    sig_hi_i = addr[9:0];
    #1;

    exp_seed = expected_seed(addr);
    if (mant_seed_o !== exp_seed[10:0]) begin
      $display("[FAIL] addr=0x%03h seed exp=%0d got=%0d", addr, exp_seed, mant_seed_o);
      errors++;
    end

    center  = (real'(addr) + 0.5) / 512.0;
    exact   = 1.0 / center;
    seed    = real'(mant_seed_o) / 1024.0;
    rel_err = abs_real(seed - exact) / exact;
    if (rel_err > max_center_rel_err) begin
      max_center_rel_err = rel_err;
    end

    if (mant_seed_o[10]) begin
      if (norm_mant_seed_o !== mant_seed_o || norm_exp_seed_o !== exp_seed_o) begin
        $display("[FAIL] normalized pass-through addr=0x%03h", addr);
        errors++;
      end
    end else begin
      if (norm_mant_seed_o !== {mant_seed_o[9:0], 1'b0} || norm_exp_seed_o !== (exp_seed_o - 16'sd1)) begin
        $display("[FAIL] normalized shift addr=0x%03h", addr);
        errors++;
      end
    end
  endtask

  initial begin
`ifdef DUMP_FSDB
    $fsdbDumpfile("tb_fpu_recip_seed_lut.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_recip_seed_lut);
`endif

    errors = 0;
    max_center_rel_err = 0.0;
    exp_i = 16'sd17;

    for (int unsigned addr = 10'h200; addr <= 10'h3ff; addr++) begin
      check_addr(addr);
    end

    if (exp_seed_o !== -16'sd17) begin
      $display("[FAIL] exp_seed exp=%0d got=%0d", -16'sd17, exp_seed_o);
      errors++;
    end

    sig_hi_i = 10'h001;
    #1;
    if (mant_seed_o !== 11'd1024 || norm_mant_seed_o !== 11'd1024 || norm_exp_seed_o !== exp_seed_o) begin
      $display("[FAIL] default invalid-address behavior");
      errors++;
    end

    if (max_center_rel_err > (1.0 / 1024.0)) begin
      $display("[FAIL] max center relative error too high: %.12f", max_center_rel_err);
      errors++;
    end

    if (errors == 0) begin
      $display("[PASS] reciprocal seed LUT checked, max center rel err=%.12f", max_center_rel_err);
    end else begin
      $display("[FAIL] reciprocal seed LUT errors=%0d", errors);
    end

    $finish;
  end

endmodule : tb_fpu_recip_seed_lut
