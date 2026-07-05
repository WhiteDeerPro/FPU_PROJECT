`timescale 1ns/1ps

module tb_fpu_mult_trig;

  localparam int unsigned WIDTH              = 64;
  localparam int unsigned GROUPS             = (WIDTH + 2) / 2;
  localparam int unsigned PP_W               = (2 * WIDTH) + 2;
  localparam int unsigned SAMPLES_PER_PERIOD = 256;
  localparam int unsigned PERIODS            = 10;
  localparam int unsigned TOTAL_SAMPLES      = SAMPLES_PER_PERIOD * PERIODS;
  localparam real         TWO_PI             = 6.28318530717958647692;
  localparam real         SINE_AMPLITUDE     = 500.0;
  localparam real         SINE_OFFSET        = 500.0;

  real                  transformed_product;
  real                  transformed_product_ideal;
  logic signed [31:0]   transformed_product_i;

  real                  theta_wave;
  logic [WIDTH-1:0]     factor_wave;
  logic [31:0]          product_wave;

  logic [WIDTH-1:0]          lhs;
  logic [WIDTH-1:0]          rhs;
  logic [(2*WIDTH)-1:0]      product;
  logic [GROUPS-1:0][2:0]    booth_code;
  logic [GROUPS-1:0][PP_W-1:0] pp;
  logic [PP_W-1:0]           final_sum;
  logic [PP_W-1:0]           final_carry;

  int unsigned pass_cnt;
  int unsigned fail_cnt;
  int          csv_fd;

  fpu_mult #(
    .WIDTH (WIDTH),
    .GROUPS(GROUPS),
    .PP_W  (PP_W)
  ) dut (
    .lhs_i        (lhs),
    .rhs_i        (rhs),
    .product_o    (product),
    .booth_code_o (booth_code),
    .pp_o         (pp),
    .final_sum_o  (final_sum),
    .final_carry_o(final_carry)
  );

  function automatic logic [WIDTH-1:0] trig_factor(input int unsigned sample_idx);
    real raw_value;
    real rounded_value;
    int  int_value;

    raw_value     = (SINE_AMPLITUDE * $sin((TWO_PI * real'(sample_idx)) /
                                           real'(SAMPLES_PER_PERIOD))) + SINE_OFFSET;
    rounded_value = raw_value + 0.5;
    int_value     = $rtoi(rounded_value);

    if (int_value < 0) begin
      int_value = 0;
    end

    return WIDTH'(int_value);
  endfunction

  task automatic check_sample(input int unsigned sample_idx);
    logic [WIDTH-1:0]     factor;
    logic [(2*WIDTH)-1:0] expected;
    real                  theta;
    real                  dc_term;
    real                  fundamental_term;
    real                  neg_cos2_term;
    real                  ideal_square;
    real                  cos2_pos_term;
    real                  cos2_pos_ideal;

    factor = trig_factor(sample_idx);
    lhs    = factor;
    rhs    = factor;
    #1;

    expected = {{WIDTH{1'b0}}, factor} * {{WIDTH{1'b0}}, factor};

    theta           = (TWO_PI * real'(sample_idx)) / real'(SAMPLES_PER_PERIOD);
    dc_term         = (SINE_OFFSET * SINE_OFFSET) +
                      ((SINE_AMPLITUDE * SINE_AMPLITUDE) / 2.0);
    fundamental_term = (2.0 * SINE_OFFSET * SINE_AMPLITUDE) * $sin(theta);
    neg_cos2_term   = -((SINE_AMPLITUDE * SINE_AMPLITUDE) / 2.0) * $cos(2.0 * theta);
    ideal_square    = dc_term + fundamental_term + neg_cos2_term;

    cos2_pos_term  = dc_term + fundamental_term - real'(product[31:0]);
    cos2_pos_ideal = -neg_cos2_term;

    transformed_product       = cos2_pos_term;
    transformed_product_ideal = cos2_pos_ideal;
    transformed_product_i     = $rtoi(cos2_pos_term);
    theta_wave                = theta;
    factor_wave               = factor;
    product_wave              = product[31:0];

    if (product !== expected) begin
      fail_cnt++;
      $display("[FAIL] sample=%0d factor=%0d expected=0x%032h product=0x%032h",
               sample_idx, factor, expected, product);
    end else begin
      pass_cnt++;
    end

    if (csv_fd != 0) begin
      $fdisplay(csv_fd, "%0d,%0d,%0.12f,%0.6f,%0.6f,%0d,%0d,%0d,%0.6f,%0.6f,%0.6f,%0.6f",
                sample_idx,
                sample_idx / SAMPLES_PER_PERIOD,
                theta,
                transformed_product,
                transformed_product_ideal,
                transformed_product_i,
                factor,
                product[31:0],
                dc_term,
                fundamental_term,
                neg_cos2_term,
                ideal_square);
    end
  endtask

  initial begin
`ifdef DUMP_FSDB
    $fsdbDumpfile("tb_fpu_mult_trig.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_mult_trig);
`endif

    pass_cnt = 0;
    fail_cnt = 0;
    lhs      = '0;
    rhs      = '0;
    transformed_product       = 0.0;
    transformed_product_ideal = 0.0;
    transformed_product_i     = '0;
    theta_wave                = 0.0;
    factor_wave               = '0;
    product_wave              = '0;

    csv_fd = $fopen("tb_fpu_mult_trig.csv", "w");
    if (csv_fd == 0) begin
      $display("[WARN] could not open tb_fpu_mult_trig.csv");
    end else begin
      $fdisplay(csv_fd, "sample,period,theta,transformed_product,transformed_product_ideal,transformed_product_i,factor,product,dc_term,fundamental_term,neg_cos2_term,ideal_square");
    end

    for (int unsigned sample_idx = 0; sample_idx < TOTAL_SAMPLES; sample_idx++) begin
      check_sample(sample_idx);
    end

    if (csv_fd != 0) begin
      $fclose(csv_fd);
    end

    $display("tb_fpu_mult_trig summary: pass=%0d fail=%0d samples=%0d periods=%0d csv=tb_fpu_mult_trig.csv",
             pass_cnt, fail_cnt, TOTAL_SAMPLES, PERIODS);
    $display("identity: (500*sin(t)+500)^2 = 375000 + 500000*sin(t) - 125000*cos(2*t)");
    $display("positive cos2 extraction: 375000 + 500000*sin(t) - product = 125000*cos(2*t)");

    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_mult_trig failed");
    end

    $finish;
  end

endmodule : tb_fpu_mult_trig
