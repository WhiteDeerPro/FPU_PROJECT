`timescale 1ns/1ps

module tb_fpu_mult_pipe_common;

  localparam int unsigned WIDTH       = 53;
  localparam int unsigned PRODUCT_W   = 2 * WIDTH;
  localparam int unsigned NUM_CASES   = 256;
  localparam int unsigned DRAIN_CYCLES = 4;

  logic                   clk_i;
  logic                   rst_ni;
  logic                   valid_i;
  logic [WIDTH-1:0]       lhs_i;
  logic [WIDTH-1:0]       rhs_i;
  logic                   valid_o;
  logic [PRODUCT_W-1:0]   product_o;
  logic [PRODUCT_W-1:0]   ref_product;
  logic                   exp_valid_0;
  logic                   exp_valid_1;
  logic [PRODUCT_W-1:0]   exp_product_0;
  logic [PRODUCT_W-1:0]   exp_product_1;

  int unsigned pass_cnt;
  int unsigned fail_cnt;
  int unsigned cycle_cnt;

  fpu_mult #(
    .WIDTH(WIDTH)
  ) u_ref_mult (
    .lhs_i        (lhs_i),
    .rhs_i        (rhs_i),
    .product_o    (ref_product),
    .booth_code_o (),
    .pp_o         (),
    .final_sum_o  (),
    .final_carry_o()
  );

  fpu_mult_pipe #(
    .WIDTH(WIDTH)
  ) u_dut (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .valid_i      (valid_i),
    .lhs_i        (lhs_i),
    .rhs_i        (rhs_i),
    .valid_o      (valid_o),
    .product_o    (product_o),
    .final_sum_o  (),
    .final_carry_o()
  );

  function automatic logic [WIDTH-1:0] operand_a(input int unsigned idx);
    logic [63:0] mixed;

    unique case (idx)
      0: return '0;
      1: return {{(WIDTH-1){1'b0}}, 1'b1};
      2: return {1'b1, {(WIDTH-1){1'b0}}};
      3: return '1;
      4: return {1'b1, {(WIDTH-2){1'b0}}, 1'b1};
      default: begin
        mixed = (64'h9e37_79b9_7f4a_7c15 * (idx + 64'd1)) ^
                (64'hd1b5_4a32_d192_ed03 >> (idx[5:0]));
        return mixed[WIDTH-1:0];
      end
    endcase
  endfunction

  function automatic logic [WIDTH-1:0] operand_b(input int unsigned idx);
    logic [63:0] mixed;

    unique case (idx)
      0: return '0;
      1: return '1;
      2: return {{(WIDTH-1){1'b0}}, 1'b1};
      3: return {1'b1, {(WIDTH-1){1'b0}}};
      4: return {2'b11, {(WIDTH-2){1'b0}}};
      default: begin
        mixed = (64'hc2b2_ae3d_27d4_eb4f * (idx + 64'd17)) ^
                (64'h1656_67b1_9e37_79f9 << (idx[4:0]));
        return mixed[WIDTH-1:0];
      end
    endcase
  endfunction

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

`ifdef DUMP_FSDB
  initial begin
    $fsdbDumpfile("tb_fpu_mult_pipe_common.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_mult_pipe_common);
  end
`endif

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      exp_valid_0   <= 1'b0;
      exp_valid_1   <= 1'b0;
      exp_product_0 <= '0;
      exp_product_1 <= '0;
    end else begin
      exp_valid_0   <= valid_i;
      exp_product_0 <= ref_product;
      exp_valid_1   <= exp_valid_0;
      exp_product_1 <= exp_product_0;
    end
  end

  always @(posedge clk_i) begin
    #2;
    if (rst_ni) begin
      cycle_cnt++;
      if (valid_o !== exp_valid_1) begin
        $display("FAIL cycle=%0d valid_o=%0b expected=%0b",
                 cycle_cnt, valid_o, exp_valid_1);
        fail_cnt++;
      end else if (valid_o) begin
        if (product_o === exp_product_1) begin
          pass_cnt++;
        end else begin
          $display("FAIL cycle=%0d lhs=%h rhs=%h got=%h expected=%h",
                   cycle_cnt, lhs_i, rhs_i, product_o, exp_product_1);
          fail_cnt++;
        end
      end
    end
  end

  initial begin
    rst_ni    = 1'b0;
    valid_i   = 1'b0;
    lhs_i     = '0;
    rhs_i     = '0;
    pass_cnt  = 0;
    fail_cnt  = 0;
    cycle_cnt = 0;

    repeat (3) @(posedge clk_i);
    #1;
    rst_ni = 1'b1;

    for (int unsigned case_idx = 0; case_idx < NUM_CASES; case_idx++) begin
      @(posedge clk_i);
      #1;
      valid_i = (case_idx[2:0] != 3'd3);
      lhs_i   = operand_a(case_idx);
      rhs_i   = operand_b(case_idx);
    end

    @(posedge clk_i);
    #1;
    valid_i = 1'b0;
    lhs_i   = '0;
    rhs_i   = '0;

    repeat (DRAIN_CYCLES) @(posedge clk_i);

    $display("tb_fpu_mult_pipe_common summary: pass=%0d fail=%0d",
             pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_mult_pipe_common failed");
    end

    $finish;
  end

endmodule : tb_fpu_mult_pipe_common
