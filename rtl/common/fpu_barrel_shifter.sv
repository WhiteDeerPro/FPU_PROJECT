module fpu_barrel_shifter #(
  parameter int unsigned WIDTH         = 64,
  parameter bit          SUPPORT_LEFT  = 1'b1,
  parameter bit          SUPPORT_RIGHT = 1'b1,
  parameter int unsigned SHAMT_W       = $clog2(WIDTH + 1)
) (
  input  logic [WIDTH-1:0]   data_i,
  input  logic [SHAMT_W-1:0] shamt_i,
  output logic [WIDTH-1:0]   left_data_o,
  output logic [WIDTH-1:0]   right_data_o,
  output logic [WIDTH-1:0]   right_lost_o
);

  logic shift_ge_width;

  assign shift_ge_width = (shamt_i >= SHAMT_W'(WIDTH));

  // The shifter works on unsigned magnitudes/significands only.
  // FP alignment usually consumes right_data_o with the significand placed
  // toward the left of the window. Normalization usually consumes left_data_o
  // with the significand placed toward the right of the window.
  generate
    if (SUPPORT_LEFT) begin : gen_left_shift
      always_comb begin
        if (shift_ge_width) begin
          left_data_o = '0;
        end else begin
          left_data_o = data_i << shamt_i;
        end
      end
    end else begin : gen_no_left_shift
      assign left_data_o = '0;
    end

    if (SUPPORT_RIGHT) begin : gen_right_shift
      always_comb begin
        if (shift_ge_width) begin
          right_data_o = '0;
          right_lost_o = data_i;
        end else if (shamt_i == '0) begin
          right_data_o = data_i;
          right_lost_o = '0;
        end else begin
          right_data_o = data_i >> shamt_i;
          right_lost_o = data_i << (SHAMT_W'(WIDTH) - shamt_i);
        end
      end
    end else begin : gen_no_right_shift
      assign right_data_o = '0;
      assign right_lost_o = '0;
    end
  endgenerate

endmodule : fpu_barrel_shifter
