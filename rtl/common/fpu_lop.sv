//============================================================================
// Leading-one position encoder.
//
// For nonzero input, pos_o is the index of the highest set bit.
// For zero input, zero_o is set and pos_o is 0.
//
// Staged 64 -> 16 -> 4 -> bit selector, easy to read in schematic.
//============================================================================

module fpu_lop #(
  parameter int unsigned DATA_W = 64
) (
  input  logic [DATA_W-1:0] data_i,
  output logic [5:0]        pos_o,
  output logic              zero_o
);

  localparam int unsigned TREE_W = 64;

  logic [TREE_W-1:0] tree_data;

  logic [3:0]        nz16_s;
  logic [1:0]        sel16;
  logic [15:0]       data16;

  logic [3:0]        nz4_s;
  logic [1:0]        sel4;
  logic [3:0]        data4;

  logic [1:0]        sel1;
  logic [5:0]        pos;

  generate
    if (DATA_W == TREE_W) begin : gen_no_pad
      assign tree_data = data_i;
    end else begin : gen_high_zero_pad
      assign tree_data = {{(TREE_W-DATA_W){1'b0}}, data_i};
    end
  endgenerate

  assign nz16_s[3] = |tree_data[63:48];
  assign nz16_s[2] = |tree_data[47:32];
  assign nz16_s[1] = |tree_data[31:16];
  assign nz16_s[0] = |tree_data[15:0];
  assign zero_o    = ~|nz16_s;

  always_comb begin
    unique casez (nz16_s)
      4'b1???: begin
        sel16  = 2'b11;
        data16 = tree_data[63:48];
      end
      4'b01??: begin
        sel16  = 2'b10;
        data16 = tree_data[47:32];
      end
      4'b001?: begin
        sel16  = 2'b01;
        data16 = tree_data[31:16];
      end
      4'b0001: begin
        sel16  = 2'b00;
        data16 = tree_data[15:0];
      end
      default: begin
        sel16  = 2'b00;
        data16 = 16'd0;
      end
    endcase
  end

  assign nz4_s[3] = |data16[15:12];
  assign nz4_s[2] = |data16[11:8];
  assign nz4_s[1] = |data16[7:4];
  assign nz4_s[0] = |data16[3:0];

  always_comb begin
    unique casez (nz4_s)
      4'b1???: begin
        sel4  = 2'b11;
        data4 = data16[15:12];
      end
      4'b01??: begin
        sel4  = 2'b10;
        data4 = data16[11:8];
      end
      4'b001?: begin
        sel4  = 2'b01;
        data4 = data16[7:4];
      end
      4'b0001: begin
        sel4  = 2'b00;
        data4 = data16[3:0];
      end
      default: begin
        sel4  = 2'b00;
        data4 = 4'd0;
      end
    endcase
  end

  always_comb begin
    unique casez (data4)
      4'b1???: sel1 = 2'b11;
      4'b01??: sel1 = 2'b10;
      4'b001?: sel1 = 2'b01;
      4'b0001: sel1 = 2'b00;
      default: sel1 = 2'b00;
    endcase
  end

  assign pos   = {sel16, sel4, sel1};
  assign pos_o = zero_o ? 6'd0 : pos;

endmodule : fpu_lop
