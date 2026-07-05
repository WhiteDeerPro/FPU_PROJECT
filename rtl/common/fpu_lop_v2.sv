//============================================================================
// Leading-one position encoder, v2.
//
// Parallel 4-way tree implementation. For nonzero input, pos_o is the index of
// the highest set bit. For zero input, zero_o is set and pos_o is 0.
//============================================================================

module fpu_lop_v2_rec #(
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

      fpu_lop_v2_rec #(.WIDTH(CHILD_W)) u_lop3 (
        .data_i(data3),
        .pos_o (pos3),
        .zero_o()
      );

      fpu_lop_v2_rec #(.WIDTH(CHILD_W)) u_lop2 (
        .data_i(data2),
        .pos_o (pos2),
        .zero_o()
      );

      fpu_lop_v2_rec #(.WIDTH(CHILD_W)) u_lop1 (
        .data_i(data1),
        .pos_o (pos1),
        .zero_o()
      );

      fpu_lop_v2_rec #(.WIDTH(CHILD_W)) u_lop0 (
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

endmodule : fpu_lop_v2_rec


module fpu_lop_v2 #(
  parameter int unsigned DATA_W = 64
) (
  input  logic [DATA_W-1:0] data_i,
  output logic [5:0]        pos_o,
  output logic              zero_o
);

  localparam int unsigned TREE_W = 64;

  logic [TREE_W-1:0] tree_data;
  logic [5:0]        tree_pos;
  logic              tree_zero;

  generate
    if (DATA_W == TREE_W) begin : gen_no_pad
      assign tree_data = data_i;
    end else begin : gen_high_zero_pad
      assign tree_data = {{(TREE_W-DATA_W){1'b0}}, data_i};
    end
  endgenerate

  fpu_lop_v2_rec #(
    .WIDTH(TREE_W)
  ) u_tree (
    .data_i(tree_data),
    .pos_o (tree_pos),
    .zero_o(tree_zero)
  );

  assign zero_o = tree_zero;
  assign pos_o  = tree_zero ? 6'd0 : tree_pos;

endmodule : fpu_lop_v2
