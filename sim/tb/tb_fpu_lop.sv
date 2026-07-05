`timescale 1ns/1ps

module tb_fpu_lop;

  logic [63:0] data_i;
  logic [5:0]  pos_o;
  logic        zero_o;
  logic [5:0]  pos_v2_o;
  logic        zero_v2_o;

  int unsigned pass_cnt;
  int unsigned fail_cnt;

  fpu_lop #(
    .DATA_W(64)
  ) dut (
    .data_i(data_i),
    .pos_o (pos_o),
    .zero_o(zero_o)
  );

  fpu_lop_v2 #(
    .DATA_W(64)
  ) dut_v2 (
    .data_i(data_i),
    .pos_o (pos_v2_o),
    .zero_o(zero_v2_o)
  );

  function automatic logic [5:0] ref_lop64(input logic [63:0] data);
    logic [5:0] pos;
    pos = 6'd0;

    for (int i = 63; i >= 0; i--) begin
      if (data[i]) begin
        pos = 6'(i);
        break;
      end
    end

    return pos;
  endfunction

  task automatic check(input logic [63:0] data, input string name);
    logic [5:0] exp_pos;
    logic       exp_zero;

    data_i = data;
    #1;

    exp_zero = (data == 64'd0);
    exp_pos  = ref_lop64(data);

    if ((pos_o !== exp_pos) || (zero_o !== exp_zero) ||
        (pos_v2_o !== exp_pos) || (zero_v2_o !== exp_zero)) begin
      fail_cnt++;
      $display("[FAIL] %-24s data=0x%016h exp_pos=%0d pos=%0d zero=%0b pos_v2=%0d zero_v2=%0b exp_zero=%0b",
               name, data, exp_pos, pos_o, zero_o, pos_v2_o, zero_v2_o, exp_zero);
    end else begin
      pass_cnt++;
      $display("[PASS] %-24s data=0x%016h pos=%0d zero=%0b pos_v2=%0d zero_v2=%0b",
               name, data, pos_o, zero_o, pos_v2_o, zero_v2_o);
    end
  endtask

  initial begin
`ifdef DUMP_FSDB
    $fsdbDumpfile("tb_fpu_lop.fsdb");
    $fsdbDumpvars("+all");
    $fsdbDumpvars("+struct");
    $fsdbDumpvars("+mda");
    $fsdbDumpvars(0, tb_fpu_lop);
`endif

    pass_cnt = 0;
    fail_cnt = 0;
    data_i   = '0;

    check(64'h0000_0000_0000_0000, "all_zero_pos0_zero1");
    check(64'h8000_0000_0000_0000, "msb_set");
    check(64'h4000_0000_0000_0000, "bit62_set");
    check(64'h0001_0000_0000_0000, "group2_first_bit");
    check(64'h0000_8000_0000_0000, "group1_first_bit");
    check(64'h0000_0000_0000_0001, "lsb_set");
    check(64'hffff_ffff_ffff_ffff, "all_one");
    check(64'h00ff_0000_0000_0000, "byte_boundary");
    check(64'h0000_0000_00f0_0000, "middle_nibble");

    for (int i = 0; i < 64; i++) begin
      check(64'(1) << i, $sformatf("walking_one_%0d", i));
    end

    for (int i = 0; i < 100; i++) begin
      check({$urandom(), $urandom()}, $sformatf("random_%0d", i));
    end

    $display("tb_fpu_lop summary: pass=%0d fail=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fpu_lop failed");
    end

    $finish;
  end

endmodule : tb_fpu_lop
