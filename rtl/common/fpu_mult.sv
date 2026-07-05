//============================================================================
// Unsigned fixed-point/integer multiplier.
//
// This block is intentionally FP-agnostic.  It builds a product from the
// radix-4 Booth partial-product generator and a direct 4-2 compressor
// reduction tree.  The final two rows are added directly; no custom CLA is
// instantiated here.  Booth generation, reduction, and final add are kept
// separate so pipeline cuts can be inserted later without changing the math.
//============================================================================

module fpu_mult #(
  parameter int unsigned WIDTH  = 64,
  parameter int unsigned GROUPS = (WIDTH + 2) / 2,
  parameter int unsigned PP_W   = (2 * WIDTH) + 2
) (
  input  logic [WIDTH-1:0]          lhs_i,
  input  logic [WIDTH-1:0]          rhs_i,
  output logic [(2*WIDTH)-1:0]      product_o,
  output logic [GROUPS-1:0][2:0]    booth_code_o,
  output logic [GROUPS-1:0][PP_W-1:0] pp_o,
  output logic [PP_W-1:0]           final_sum_o,
  output logic [PP_W-1:0]           final_carry_o
);

  function automatic int unsigned reduce_rem_rows(input int unsigned rows);
    unique case (rows)
      0,
      1,
      2: return rows;
      3: return 2;
      4: return 3;
      default: return 0;
    endcase
  endfunction

  function automatic int unsigned reduce_next_rows(input int unsigned rows);
    return ((rows / 5) * 3) + reduce_rem_rows(rows % 5);
  endfunction

  function automatic int unsigned reduce_rows_at(input int unsigned stage);
    int unsigned rows;

    rows = GROUPS;
    for (int unsigned stage_idx = 0; stage_idx < stage; stage_idx++) begin
      if (rows > 2) begin
        rows = reduce_next_rows(rows);
      end
    end

    return rows;
  endfunction

  function automatic int unsigned reduce_stage_count();
    int unsigned rows;
    int unsigned stages;

    rows   = GROUPS;
    stages = 0;
    while (rows > 2) begin
      rows = reduce_next_rows(rows);
      stages++;
    end

    return stages;
  endfunction

  localparam int unsigned STAGES    = reduce_stage_count();
  localparam int unsigned FINAL_ROWS = reduce_rows_at(STAGES);

  logic [STAGES:0][GROUPS-1:0][PP_W-1:0] stage_rows;
  logic signed [PP_W-1:0]                 final_product_ext;

  fpu_booth_radix4_compressor #(
    .WIDTH (WIDTH),
    .GROUPS(GROUPS),
    .PP_W  (PP_W)
  ) u_pp_gen (
    .lhs_i       (lhs_i),
    .rhs_i       (rhs_i),
    .booth_code_o(booth_code_o),
    .pp_o        (pp_o)
  );

  generate
    for (genvar row_idx = 0; row_idx < GROUPS; row_idx++) begin : gen_stage0
      assign stage_rows[0][row_idx] = pp_o[row_idx];
    end

    for (genvar stage_idx = 0; stage_idx < STAGES; stage_idx++) begin : gen_reduce_stage
      localparam int unsigned IN_ROWS  = reduce_rows_at(stage_idx);
      localparam int unsigned QUINTS   = IN_ROWS / 5;
      localparam int unsigned REM_ROWS = IN_ROWS % 5;
      localparam int unsigned REM_BASE = 3 * QUINTS;
      localparam int unsigned OUT_ROWS = reduce_next_rows(IN_ROWS);

      logic [GROUPS-1:0][PP_W-1:0] carry0_bits;
      logic [GROUPS-1:0][PP_W-1:0] carry1_bits;
      logic [PP_W-1:0]             rem_carry0_bits;
      logic [PP_W-1:0]             rem_carry1_bits;

      for (genvar quint_idx = 0; quint_idx < QUINTS; quint_idx++) begin : gen_4_2
        fpu_compressor_4_2 #(
          .WIDTH(PP_W)
        ) u_compress (
          .a_i    (stage_rows[stage_idx][5*quint_idx]),
          .b_i    (stage_rows[stage_idx][5*quint_idx + 1]),
          .c_i    (stage_rows[stage_idx][5*quint_idx + 2]),
          .d_i    (stage_rows[stage_idx][5*quint_idx + 3]),
          .cin_i  (stage_rows[stage_idx][5*quint_idx + 4]),
          .sum_o  (stage_rows[stage_idx+1][3*quint_idx]),
          .carry_o(carry0_bits[quint_idx]),
          .cout_o (carry1_bits[quint_idx])
        );

        assign stage_rows[stage_idx+1][3*quint_idx + 1] =
               {carry0_bits[quint_idx][PP_W-2:0], 1'b0};
        assign stage_rows[stage_idx+1][3*quint_idx + 2] =
               {carry1_bits[quint_idx][PP_W-2:0], 1'b0};
      end

      if (REM_ROWS == 1) begin : gen_rem1
        assign stage_rows[stage_idx+1][REM_BASE] =
               stage_rows[stage_idx][5*QUINTS];
      end

      if (REM_ROWS == 2) begin : gen_rem2
        assign stage_rows[stage_idx+1][REM_BASE] =
               stage_rows[stage_idx][5*QUINTS];
        assign stage_rows[stage_idx+1][REM_BASE + 1] =
               stage_rows[stage_idx][5*QUINTS + 1];
      end

      if (REM_ROWS == 3) begin : gen_rem3
        fpu_compressor_3_2 #(
          .WIDTH(PP_W)
        ) u_rem_compress (
          .a_i    (stage_rows[stage_idx][5*QUINTS]),
          .b_i    (stage_rows[stage_idx][5*QUINTS + 1]),
          .c_i    (stage_rows[stage_idx][5*QUINTS + 2]),
          .sum_o  (stage_rows[stage_idx+1][REM_BASE]),
          .carry_o(rem_carry0_bits)
        );

        assign stage_rows[stage_idx+1][REM_BASE + 1] =
               {rem_carry0_bits[PP_W-2:0], 1'b0};
      end

      if (REM_ROWS == 4) begin : gen_rem4
        fpu_compressor_4_2 #(
          .WIDTH(PP_W)
        ) u_rem_compress (
          .a_i    (stage_rows[stage_idx][5*QUINTS]),
          .b_i    (stage_rows[stage_idx][5*QUINTS + 1]),
          .c_i    (stage_rows[stage_idx][5*QUINTS + 2]),
          .d_i    (stage_rows[stage_idx][5*QUINTS + 3]),
          .cin_i  ('0),
          .sum_o  (stage_rows[stage_idx+1][REM_BASE]),
          .carry_o(rem_carry0_bits),
          .cout_o (rem_carry1_bits)
        );

        assign stage_rows[stage_idx+1][REM_BASE + 1] =
               {rem_carry0_bits[PP_W-2:0], 1'b0};
        assign stage_rows[stage_idx+1][REM_BASE + 2] =
               {rem_carry1_bits[PP_W-2:0], 1'b0};
      end

      for (genvar zero_idx = OUT_ROWS; zero_idx < GROUPS; zero_idx++) begin : gen_zero_tail
        assign stage_rows[stage_idx+1][zero_idx] = '0;
      end
    end
  endgenerate

  assign final_sum_o = stage_rows[STAGES][0];

  generate
    if (FINAL_ROWS == 2) begin : gen_final_two_rows
      assign final_carry_o = stage_rows[STAGES][1];
    end else begin : gen_final_one_row
      assign final_carry_o = '0;
    end
  endgenerate

  assign final_product_ext = $signed(final_sum_o) + $signed(final_carry_o);
  assign product_o = final_product_ext[(2*WIDTH)-1:0];

endmodule : fpu_mult
