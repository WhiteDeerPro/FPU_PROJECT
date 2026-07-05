//============================================================================
// Pipelined unsigned fixed-point/integer multiplier.
//
// Flow:
//   lhs_i/rhs_i
//     -> radix-4 Booth partial products
//     -> compressor reduction segment 0
//     -> stage 1 register
//     -> compressor reduction segment 1
//     -> stage 2 register
//     -> compressor reduction segment 2 and final carry-propagate add
//
// The default cut points are chosen for the 53-bit FP significand multiplier:
// 27 Booth rows reduce through six compressor levels, split as 2/3/1 levels.
// The last segment also includes the final wide add, so keeping only one
// compressor level there is usually a better balance than a strict 2/2/2 split.
//============================================================================

module fpu_mult_reduce_segment #(
  parameter int unsigned WIDTH       = 64,
  parameter int unsigned GROUPS      = (WIDTH + 2) / 2,
  parameter int unsigned PP_W        = (2 * WIDTH) + 2,
  parameter int unsigned START_STAGE = 0,
  parameter int unsigned NUM_STAGES  = 0
) (
  input  logic [GROUPS-1:0][PP_W-1:0] rows_i,
  output logic [GROUPS-1:0][PP_W-1:0] rows_o
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

  logic [NUM_STAGES:0][GROUPS-1:0][PP_W-1:0] stage_rows;

  assign stage_rows[0] = rows_i;

  generate
    for (genvar stage_idx = 0; stage_idx < NUM_STAGES; stage_idx++) begin : gen_reduce_stage
      localparam int unsigned GLOBAL_STAGE = START_STAGE + stage_idx;
      localparam int unsigned IN_ROWS      = reduce_rows_at(GLOBAL_STAGE);
      localparam int unsigned QUINTS       = IN_ROWS / 5;
      localparam int unsigned REM_ROWS     = IN_ROWS % 5;
      localparam int unsigned REM_BASE     = 3 * QUINTS;
      localparam int unsigned OUT_ROWS     = reduce_next_rows(IN_ROWS);

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

  assign rows_o = stage_rows[NUM_STAGES];

endmodule : fpu_mult_reduce_segment


module fpu_mult_pipe #(
  parameter int unsigned WIDTH  = 64,
  parameter int unsigned GROUPS = (WIDTH + 2) / 2,
  parameter int unsigned PP_W   = (2 * WIDTH) + 2,
  parameter int unsigned CUT0   = 2,
  parameter int unsigned CUT1   = 5
) (
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    valid_i,
  input  logic [WIDTH-1:0]        lhs_i,
  input  logic [WIDTH-1:0]        rhs_i,
  output logic                    valid_o,
  output logic [(2*WIDTH)-1:0]    product_o,
  output logic [PP_W-1:0]         final_sum_o,
  output logic [PP_W-1:0]         final_carry_o
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

  localparam int unsigned STAGES        = reduce_stage_count();
  localparam int unsigned CUT0_CLAMPED  = (CUT0 > STAGES) ? STAGES : CUT0;
  localparam int unsigned CUT1_CLAMPED  = (CUT1 > STAGES) ? STAGES : CUT1;
  localparam int unsigned CUT1_ORDERED  = (CUT1_CLAMPED < CUT0_CLAMPED) ?
                                          CUT0_CLAMPED : CUT1_CLAMPED;
  localparam int unsigned SEG0_STAGES   = CUT0_CLAMPED;
  localparam int unsigned SEG1_STAGES   = CUT1_ORDERED - CUT0_CLAMPED;
  localparam int unsigned SEG2_STAGES   = STAGES - CUT1_ORDERED;
  localparam int unsigned FINAL_ROWS    = reduce_rows_at(STAGES);

  logic [GROUPS-1:0][2:0]      booth_code;
  logic [GROUPS-1:0][PP_W-1:0] pp_rows;
  logic [GROUPS-1:0][PP_W-1:0] s0_rows_d;
  logic [GROUPS-1:0][PP_W-1:0] s1_rows_q;
  logic [GROUPS-1:0][PP_W-1:0] s1_rows_d;
  logic [GROUPS-1:0][PP_W-1:0] s2_rows_q;
  logic [GROUPS-1:0][PP_W-1:0] s2_rows_d;
  logic                        s1_valid;
  logic                        s2_valid;
  logic signed [PP_W-1:0]      final_product_ext;

  fpu_booth_radix4_compressor #(
    .WIDTH (WIDTH),
    .GROUPS(GROUPS),
    .PP_W  (PP_W)
  ) u_pp_gen (
    .lhs_i       (lhs_i),
    .rhs_i       (rhs_i),
    .booth_code_o(booth_code),
    .pp_o        (pp_rows)
  );

  fpu_mult_reduce_segment #(
    .WIDTH      (WIDTH),
    .GROUPS     (GROUPS),
    .PP_W       (PP_W),
    .START_STAGE(0),
    .NUM_STAGES (SEG0_STAGES)
  ) u_reduce_s0 (
    .rows_i(pp_rows),
    .rows_o(s0_rows_d)
  );

  fpu_mult_reduce_segment #(
    .WIDTH      (WIDTH),
    .GROUPS     (GROUPS),
    .PP_W       (PP_W),
    .START_STAGE(CUT0_CLAMPED),
    .NUM_STAGES (SEG1_STAGES)
  ) u_reduce_s1 (
    .rows_i(s1_rows_q),
    .rows_o(s1_rows_d)
  );

  fpu_mult_reduce_segment #(
    .WIDTH      (WIDTH),
    .GROUPS     (GROUPS),
    .PP_W       (PP_W),
    .START_STAGE(CUT1_ORDERED),
    .NUM_STAGES (SEG2_STAGES)
  ) u_reduce_s2 (
    .rows_i(s2_rows_q),
    .rows_o(s2_rows_d)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s1_valid  <= 1'b0;
      s2_valid  <= 1'b0;
      s1_rows_q <= '0;
      s2_rows_q <= '0;
    end else begin
      s1_valid  <= valid_i;
      s2_valid  <= s1_valid;
      s1_rows_q <= s0_rows_d;
      s2_rows_q <= s1_rows_d;
    end
  end

  assign final_sum_o = s2_rows_d[0];

  generate
    if (FINAL_ROWS == 2) begin : gen_final_two_rows
      assign final_carry_o = s2_rows_d[1];
    end else begin : gen_final_one_row
      assign final_carry_o = '0;
    end
  endgenerate

  assign final_product_ext = $signed(final_sum_o) + $signed(final_carry_o);
  assign product_o         = final_product_ext[(2*WIDTH)-1:0];
  assign valid_o           = s2_valid;

endmodule : fpu_mult_pipe
