`timescale 1ns/1ps

module tb_fpu_rsqrt_seed_lut;

  localparam real REL_ERR_LIMIT = 1.0 / 8192.0;

  logic [11:0]        sig_hi_i;
  logic               exp_odd_i;
  logic [15:0]        mant_seed_o;
  logic signed [15:0] norm_exp_seed_o;
  logic [15:0]        norm_mant_seed_o;

  int unsigned errors;
  int unsigned max_abs_err [2];
  real         max_rel_err [2];

  fpu_rsqrt_seed_lut dut (
    .sig_hi_i        (sig_hi_i),
    .exp_odd_i       (exp_odd_i),
    .mant_seed_o     (mant_seed_o),
    .norm_exp_seed_o (norm_exp_seed_o),
    .norm_mant_seed_o(norm_mant_seed_o)
  );

  function automatic real abs_real(input real value);
    return (value < 0.0) ? -value : value;
  endfunction

  function automatic int unsigned expected_seed(input int unsigned addr, input bit exp_odd);
    real center;
    real domain;
    real scaled;
    center        = (real'(addr) + 0.5) / 2048.0;
    domain        = exp_odd ? (2.0 * center) : center;
    scaled        = (1.0 / $sqrt(domain)) * 32768.0;
    expected_seed = int'($floor(scaled + 0.5));
  endfunction

  task automatic check_addr(input int unsigned addr, input bit exp_odd);
    int unsigned exp_seed;
    int unsigned abs_err;
    real         exact;
    real         seed;
    real         rel_err;

    sig_hi_i  = addr[11:0];
    exp_odd_i = exp_odd;
    #1;

    exp_seed = expected_seed(addr, exp_odd);
    abs_err  = (mant_seed_o > exp_seed) ? (mant_seed_o - exp_seed) :
                                          (exp_seed - mant_seed_o);

    if (abs_err > max_abs_err[exp_odd]) begin
      max_abs_err[exp_odd] = abs_err;
    end

    exact   = real'(exp_seed) / 32768.0;
    seed    = real'(mant_seed_o) / 32768.0;
    rel_err = abs_real(seed - exact) / exact;
    if (rel_err > max_rel_err[exp_odd]) begin
      max_rel_err[exp_odd] = rel_err;
    end

    if (rel_err >= REL_ERR_LIMIT) begin
      $display("[FAIL] exp_odd=%0b addr=0x%03h rel_err=%.12f limit=%.12f ideal=%0d got=%0d",
               exp_odd, addr, rel_err, REL_ERR_LIMIT, exp_seed, mant_seed_o);
      errors++;
    end

    if (mant_seed_o[15]) begin
      if (norm_mant_seed_o !== mant_seed_o || norm_exp_seed_o !== 16'sd0) begin
        $display("[FAIL] normalized pass-through exp_odd=%0b addr=0x%03h",
                 exp_odd, addr);
        errors++;
      end
    end else begin
      if (norm_mant_seed_o !== {mant_seed_o[14:0], 1'b0} ||
          norm_exp_seed_o !== -16'sd1) begin
        $display("[FAIL] normalized shift exp_odd=%0b addr=0x%03h",
                 exp_odd, addr);
        errors++;
      end
    end
  endtask

  initial begin
`ifdef DUMP_FSDB
    $fsdbDumpfile("tb_fpu_rsqrt_seed_lut.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_rsqrt_seed_lut);
`endif

    errors = 0;
    max_abs_err[0] = 0;
    max_abs_err[1] = 0;
    max_rel_err[0] = 0.0;
    max_rel_err[1] = 0.0;

    for (int unsigned addr = 12'h800; addr <= 12'hfff; addr++) begin
      check_addr(addr, 1'b0);
      check_addr(addr, 1'b1);
    end

    sig_hi_i  = 12'h001;
    exp_odd_i = 1'b0;
    #1;
    if (mant_seed_o !== 16'h8000 ||
        norm_mant_seed_o !== 16'h8000 ||
        norm_exp_seed_o !== 16'sd0) begin
      $display("[FAIL] default invalid-address behavior exp_odd=0");
      errors++;
    end

    exp_odd_i = 1'b1;
    #1;
    if (mant_seed_o !== 16'h8000 ||
        norm_mant_seed_o !== 16'h8000 ||
        norm_exp_seed_o !== 16'sd0) begin
      $display("[FAIL] default invalid-address behavior exp_odd=1");
      errors++;
    end

    if (errors == 0) begin
      $display("[PASS] rsqrt seed LUT checked, exp_odd=0 max_abs_err=%0d max_rel_err=%.12f",
               max_abs_err[0], max_rel_err[0]);
      $display("[PASS] rsqrt seed LUT checked, exp_odd=1 max_abs_err=%0d max_rel_err=%.12f",
               max_abs_err[1], max_rel_err[1]);
    end else begin
      $display("[FAIL] rsqrt seed LUT errors=%0d", errors);
      $fatal(1, "tb_fpu_rsqrt_seed_lut failed");
    end

    $finish;
  end

endmodule : tb_fpu_rsqrt_seed_lut
