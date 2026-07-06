//============================================================================
// Leading-one position encoder.
//
// For nonzero input, pos_o is the index of the highest set bit.
// For zero input, zero_o is set and pos_o is 0.
//
// USE_TREE_IMPL=0 selects the compact staged 64 -> 16 -> 4 -> bit selector.
// USE_TREE_IMPL=1 selects a parallel 4-way recursive tree. It has more parallel
// structure and is often faster, but generally costs more area.
//============================================================================

module fpu_lop_tree_rec #(
  parameter int unsigned WIDTH = 64
) (
  input  logic [WIDTH-1:0]         data_i,
  output logic [$clog2(WIDTH)-1:0] pos_o,
  output logic                     zero_o
);

  generate
    if (WIDTH == 4) begin : gen_leaf
      assign zero_o = ~|data_i;

      always_comb begin
        unique casez (data_i)
          4'b1???: pos_o = 2'd3;
          4'b01??: pos_o = 2'd2;
          4'b001?: pos_o = 2'd1;
          4'b0001: pos_o = 2'd0;
          default: pos_o = 2'd0;
        endcase
      end
    end else begin : gen_tree
      localparam int unsigned CHILD_W  = WIDTH / 4;
      localparam int unsigned CHILD_CW = $clog2(CHILD_W);

      logic [CHILD_W-1:0]  data3, data2, data1, data0;
      logic [3:0]          nonzero_s;
      logic [CHILD_CW-1:0] pos3, pos2, pos1, pos0;

      assign data3 = data_i[WIDTH-1           -: CHILD_W];
      assign data2 = data_i[WIDTH-CHILD_W-1   -: CHILD_W];
      assign data1 = data_i[WIDTH-2*CHILD_W-1 -: CHILD_W];
      assign data0 = data_i[WIDTH-3*CHILD_W-1 -: CHILD_W];

      assign nonzero_s = {|data3, |data2, |data1, |data0};
      assign zero_o    = ~|nonzero_s;

      fpu_lop_tree_rec #(.WIDTH(CHILD_W)) u_lop3 (
        .data_i(data3),
        .pos_o (pos3),
        .zero_o()
      );

      fpu_lop_tree_rec #(.WIDTH(CHILD_W)) u_lop2 (
        .data_i(data2),
        .pos_o (pos2),
        .zero_o()
      );

      fpu_lop_tree_rec #(.WIDTH(CHILD_W)) u_lop1 (
        .data_i(data1),
        .pos_o (pos1),
        .zero_o()
      );

      fpu_lop_tree_rec #(.WIDTH(CHILD_W)) u_lop0 (
        .data_i(data0),
        .pos_o (pos0),
        .zero_o()
      );

      always_comb begin
        unique casez (nonzero_s)
          4'b1???: pos_o = {2'b11, pos3};
          4'b01??: pos_o = {2'b10, pos2};
          4'b001?: pos_o = {2'b01, pos1};
          4'b0001: pos_o = {2'b00, pos0};
          default: pos_o = '0;
        endcase
      end
    end
  endgenerate

endmodule : fpu_lop_tree_rec


module fpu_lop #(
  parameter int unsigned DATA_W        = 64,
  parameter bit          USE_TREE_IMPL = 1'b0
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
  logic [5:0]        tree_pos;
  logic              tree_zero;

  generate
    if (DATA_W == TREE_W) begin : gen_no_pad
      assign tree_data = data_i;
    end else begin : gen_high_zero_pad
      assign tree_data = {{(TREE_W-DATA_W){1'b0}}, data_i};
    end
  endgenerate

  generate
    if (USE_TREE_IMPL) begin : gen_tree_impl
      fpu_lop_tree_rec #(
        .WIDTH(TREE_W)
      ) u_tree (
        .data_i(tree_data),
        .pos_o (tree_pos),
        .zero_o(tree_zero)
      );

      assign zero_o = tree_zero;
      assign pos_o  = tree_zero ? 6'd0 : tree_pos;
    end else begin : gen_staged_impl
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
    end
  endgenerate

endmodule : fpu_lop
