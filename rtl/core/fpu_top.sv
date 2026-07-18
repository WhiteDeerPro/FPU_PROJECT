//============================================================================
// Canonical configurable 1..4 issue / 1..4 writeback FPU backend.
//
// One instance of each arithmetic unit is shared by all issue lanes. Requests
// targeting different units may issue together. Requests targeting the same
// unit are resolved with fixed priority: lane 0 is highest, larger lane indices
// have lower priority. No arithmetic unit is replicated by this module.
//============================================================================

module fpu_top
  import fpu_pkg::*;
#(
  parameter int unsigned ISSUE_WIDTH      = 2,
  parameter int unsigned WRITEBACK_WIDTH  = 2,
  parameter int unsigned RESP_FIFO_DEPTH  = 32
)
(
  input  logic                               clk_i,
  input  logic                               rst_ni,
  input  fpu_kill_t                          kill_i,
  input  logic [ISSUE_WIDTH-1:0]             valid_i,
  input  fpu_req_t [ISSUE_WIDTH-1:0]         req_i,
  output logic [ISSUE_WIDTH-1:0]             ready_o,
  output logic [WRITEBACK_WIDTH-1:0]         valid_o,
  input  logic [WRITEBACK_WIDTH-1:0]         ready_i,
  output fpu_resp_t [WRITEBACK_WIDTH-1:0]    resp_o,
  output logic [WRITEBACK_WIDTH-1:0]         valid_op_o
);

  localparam int unsigned NUM_UNITS = 9;
  localparam int unsigned UNIT_ADD  = 0;
  localparam int unsigned UNIT_MUL  = 1;
  localparam int unsigned UNIT_FMA  = 2;
  localparam int unsigned UNIT_DIV  = 3;
  localparam int unsigned UNIT_SQRT = 4;
  localparam int unsigned UNIT_CVT  = 5;
  localparam int unsigned UNIT_CMP  = 6;
  localparam int unsigned UNIT_SGNJ = 7;
  localparam int unsigned UNIT_MOVE = 8;

  localparam int unsigned RESP_PTR_W = (RESP_FIFO_DEPTH > 1) ?
                                      $clog2(RESP_FIFO_DEPTH) : 1;
  localparam int unsigned RESP_COUNT_W = $clog2(RESP_FIFO_DEPTH + 1);
  localparam int unsigned PUSH_COUNT_W = $clog2(NUM_UNITS + 1);
  localparam int unsigned ISSUE_COUNT_W = $clog2(ISSUE_WIDTH + 1);
  localparam int unsigned WB_COUNT_W = $clog2(WRITEBACK_WIDTH + 1);
  localparam int unsigned TAG_COUNT = FPU_TAG_COUNT;

  typedef enum logic [3:0] {
    DECODE_NONE,
    DECODE_ADD,
    DECODE_MUL,
    DECODE_FMA,
    DECODE_DIV,
    DECODE_SQRT,
    DECODE_CVT,
    DECODE_CMP,
    DECODE_SGNJ,
    DECODE_MOVE
  } decoded_unit_e;

  function automatic decoded_unit_e decode_unit(input fpu_op_e op);
    unique case (op)
      FPU_OP_ADD,
      FPU_OP_SUB: return DECODE_ADD;
      FPU_OP_MUL: return DECODE_MUL;
      FPU_OP_FMADD,
      FPU_OP_FMSUB,
      FPU_OP_FNMSUB,
      FPU_OP_FNMADD: return DECODE_FMA;
      FPU_OP_DIV:  return DECODE_DIV;
      FPU_OP_SQRT: return DECODE_SQRT;
      FPU_OP_CVT_FP,
      FPU_OP_CVT_F2I,
      FPU_OP_CVT_I2F: return DECODE_CVT;
      FPU_OP_EQ,
      FPU_OP_LT,
      FPU_OP_LE,
      FPU_OP_MIN,
      FPU_OP_MAX,
      FPU_OP_CLASS: return DECODE_CMP;
      FPU_OP_SGNJ,
      FPU_OP_SGNJN,
      FPU_OP_SGNJX: return DECODE_SGNJ;
      FPU_OP_MV_X_FP,
      FPU_OP_MV_FP_X: return DECODE_MOVE;
      default: return DECODE_NONE;
    endcase
  endfunction

  function automatic int unsigned unit_index(input decoded_unit_e unit_sel);
    unique case (unit_sel)
      DECODE_ADD:  return UNIT_ADD;
      DECODE_MUL:  return UNIT_MUL;
      DECODE_FMA:  return UNIT_FMA;
      DECODE_DIV:  return UNIT_DIV;
      DECODE_SQRT: return UNIT_SQRT;
      DECODE_CVT:  return UNIT_CVT;
      DECODE_CMP:  return UNIT_CMP;
      DECODE_SGNJ: return UNIT_SGNJ;
      default:     return UNIT_MOVE;
    endcase
  endfunction

  function automatic fpu_data_t nanbox_s(input logic [31:0] data_s);
    return {32'hffff_ffff, data_s};
  endfunction

  // Local consumer policy for the protocol-level kill bundle.  Keep this
  // implementation helper out of fpu_pkg: the package defines the wire
  // contract, while each block decides how and when it consumes that contract.
  function automatic logic kill_matches(
    input fpu_kill_t kill,
    input fpu_tag_t  tag
  );
    return kill.valid && (kill.all || kill.tag_mask[tag]);
  endfunction

  fpu_req_t unit_req [0:NUM_UNITS-1];
  logic [NUM_UNITS-1:0] unit_issue_valid;
  logic [NUM_UNITS-1:0] unit_taken;
  logic [ISSUE_COUNT_W-1:0] accepted_count;
  integer reservation_available;

  logic div_ready;
  logic sqrt_ready;

  fpu_resp_t add_resp;
  fpu_resp_t mult_resp;
  fpu_resp_t fma_resp;
  fpu_resp_t div_resp;
  fpu_resp_t sqrt_resp;
  fpu_resp_t convert_resp;
  fpu_resp_t compare_resp;
  fpu_resp_t sgnj_resp_w;
  fpu_resp_t move_resp_w;
  fpu_resp_t sgnj_resp_q;
  fpu_resp_t move_resp_q;

  logic add_valid;
  logic mult_valid;
  logic fma_valid;
  logic div_valid;
  logic sqrt_valid;
  logic convert_valid;
  logic compare_valid;
  logic sgnj_valid_q;
  logic move_valid_q;

  logic add_valid_op;
  logic mult_valid_op;
  logic fma_valid_op;
  logic div_valid_op;
  logic sqrt_valid_op;
  logic convert_valid_op;
  logic compare_valid_op;
  logic sgnj_valid_op_w;
  logic move_valid_op_w;
  logic sgnj_valid_op_q;
  logic move_valid_op_q;

  fpu_resp_t resp_fifo_q [0:RESP_FIFO_DEPTH-1];
  logic      resp_fifo_valid_op_q [0:RESP_FIFO_DEPTH-1];
  logic [RESP_PTR_W-1:0]   resp_read_ptr_q;
  logic [RESP_PTR_W-1:0]   resp_write_ptr_q;
  logic [RESP_COUNT_W-1:0] resp_count_q;
  logic [RESP_COUNT_W-1:0] outstanding_q;

  fpu_resp_t push_resp [0:NUM_UNITS-1];
  logic      push_valid_op [0:NUM_UNITS-1];
  logic [PUSH_COUNT_W-1:0] push_count;
  fpu_resp_t completion_resp [0:NUM_UNITS-1];
  logic [NUM_UNITS-1:0] completion_valid;
  logic [NUM_UNITS-1:0] completion_valid_op;
  fpu_tag_t completion_drop_tag [0:NUM_UNITS-1];
  logic [PUSH_COUNT_W-1:0] completion_drop_count;
  logic [TAG_COUNT-1:0] killed_q;
  logic [TAG_COUNT-1:0] active_q;
  logic [TAG_COUNT-1:0] issue_tag_taken;

  logic [WRITEBACK_WIDTH-1:0] wb_valid_q;
  fpu_resp_t [WRITEBACK_WIDTH-1:0] wb_resp_q;
  logic [WRITEBACK_WIDTH-1:0] wb_valid_op_q;
  logic [WRITEBACK_WIDTH-1:0] wb_pop;
  logic [WRITEBACK_WIDTH-1:0] wb_killed;
  logic [WRITEBACK_WIDTH-1:0] wb_release;
  logic [WRITEBACK_WIDTH-1:0] wb_load;
  fpu_resp_t [WRITEBACK_WIDTH-1:0] wb_load_resp;
  logic [WRITEBACK_WIDTH-1:0] wb_load_valid_op;
  logic [WB_COUNT_W-1:0] wb_release_count;
  logic [WB_COUNT_W-1:0] fifo_to_wb_count;

  // Fixed-priority lane arbitration. Only a valid higher-priority lane claims
  // a unit, so an idle low lane does not block a higher-numbered lane.
  always_comb begin : p_dispatch
    decoded_unit_e decoded_unit;
    int unsigned   decoded_index;
    logic          target_ready;

    ready_o         = '0;
    unit_issue_valid = '0;
    unit_taken       = '0;
    issue_tag_taken  = '0;
    accepted_count   = '0;
    for (int unsigned unit_idx = 0; unit_idx < NUM_UNITS; unit_idx++) begin
      unit_req[unit_idx] = '0;
    end

    reservation_available = RESP_FIFO_DEPTH - outstanding_q +
                            wb_release_count + completion_drop_count;

    // A flush cycle is a control boundary: do not accept a request while the
    // killed-tag state is being established.
    if (!kill_i.valid) begin
      for (int unsigned lane = 0; lane < ISSUE_WIDTH; lane++) begin
        decoded_unit = decode_unit(req_i[lane].op);
        if (decoded_unit == DECODE_NONE) begin
          // Preserve the scalar top behavior for unsupported decoded requests.
          ready_o[lane] = 1'b1;
        end else begin
          decoded_index = unit_index(decoded_unit);
          target_ready = ((decoded_unit != DECODE_DIV) || div_ready) &&
                         ((decoded_unit != DECODE_SQRT) || sqrt_ready);
          ready_o[lane] = !unit_taken[decoded_index] && target_ready &&
                          !active_q[req_i[lane].tag] &&
                          !issue_tag_taken[req_i[lane].tag] &&
                          (accepted_count < reservation_available);

          if (valid_i[lane] && ready_o[lane]) begin
            unit_taken[decoded_index]       = 1'b1;
            issue_tag_taken[req_i[lane].tag] = 1'b1;
            unit_issue_valid[decoded_index] = 1'b1;
            unit_req[decoded_index]         = req_i[lane];
            accepted_count++;
          end
        end
      end
    end
  end

  fpu_add_unit_pipe u_add (
    .clk_i, .rst_ni,
    .valid_i   (unit_issue_valid[UNIT_ADD]),
    .req_i     (unit_req[UNIT_ADD]),
    .valid_o   (add_valid),
    .resp_o    (add_resp),
    .valid_op_o(add_valid_op)
  );

  fpu_mult_unit_pipe u_mult (
    .clk_i, .rst_ni,
    .valid_i   (unit_issue_valid[UNIT_MUL]),
    .req_i     (unit_req[UNIT_MUL]),
    .valid_o   (mult_valid),
    .resp_o    (mult_resp),
    .valid_op_o(mult_valid_op)
  );

  fpu_fma_unit_pipe u_fma (
    .clk_i, .rst_ni,
    .valid_i   (unit_issue_valid[UNIT_FMA]),
    .req_i     (unit_req[UNIT_FMA]),
    .valid_o   (fma_valid),
    .resp_o    (fma_resp),
    .valid_op_o(fma_valid_op)
  );

  fpu_div_unit_pipe u_div (
    .clk_i, .rst_ni,
    .valid_i   (unit_issue_valid[UNIT_DIV]),
    .req_i     (unit_req[UNIT_DIV]),
    .ready_o   (div_ready),
    .valid_o   (div_valid),
    .resp_o    (div_resp),
    .valid_op_o(div_valid_op)
  );

  fpu_sqrt_unit_pipe u_sqrt (
    .clk_i, .rst_ni,
    .valid_i   (unit_issue_valid[UNIT_SQRT]),
    .req_i     (unit_req[UNIT_SQRT]),
    .ready_o   (sqrt_ready),
    .valid_o   (sqrt_valid),
    .resp_o    (sqrt_resp),
    .valid_op_o(sqrt_valid_op)
  );

  fpu_convert_unit_pipe u_convert (
    .clk_i, .rst_ni,
    .valid_i   (unit_issue_valid[UNIT_CVT]),
    .req_i     (unit_req[UNIT_CVT]),
    .valid_o   (convert_valid),
    .resp_o    (convert_resp),
    .valid_op_o(convert_valid_op)
  );

  fpu_compare_unit_pipe u_compare (
    .clk_i, .rst_ni,
    .valid_i   (unit_issue_valid[UNIT_CMP]),
    .req_i     (unit_req[UNIT_CMP]),
    .valid_o   (compare_valid),
    .resp_o    (compare_resp),
    .valid_op_o(compare_valid_op)
  );

  fpu_sgnj_unit u_sgnj (
    .req_i     (unit_req[UNIT_SGNJ]),
    .resp_o    (sgnj_resp_w),
    .valid_op_o(sgnj_valid_op_w)
  );

  always_comb begin
    move_resp_w      = '0;
    move_resp_w.tag  = unit_req[UNIT_MOVE].tag;
    move_resp_w.rd   = unit_req[UNIT_MOVE].rd;
    move_valid_op_w  = ((unit_req[UNIT_MOVE].op == FPU_OP_MV_X_FP) ||
                        (unit_req[UNIT_MOVE].op == FPU_OP_MV_FP_X)) &&
                       ((unit_req[UNIT_MOVE].rs_fmt == FPU_FMT_S) ||
                        (unit_req[UNIT_MOVE].rs_fmt == FPU_FMT_D));

    if (move_valid_op_w) begin
      unique case (unit_req[UNIT_MOVE].op)
        FPU_OP_MV_X_FP: begin
          move_resp_w.result = (unit_req[UNIT_MOVE].rs_fmt == FPU_FMT_S) ?
            {{32{unit_req[UNIT_MOVE].src_a[31]}},
             unit_req[UNIT_MOVE].src_a[31:0]} : unit_req[UNIT_MOVE].src_a;
        end
        FPU_OP_MV_FP_X: begin
          move_resp_w.result = (unit_req[UNIT_MOVE].dst_fmt == FPU_FMT_S) ?
            nanbox_s(unit_req[UNIT_MOVE].src_a[31:0]) :
            unit_req[UNIT_MOVE].src_a;
        end
        default: move_valid_op_w = 1'b0;
      endcase
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sgnj_valid_q    <= 1'b0;
      sgnj_valid_op_q <= 1'b0;
      sgnj_resp_q     <= '0;
      move_valid_q    <= 1'b0;
      move_valid_op_q <= 1'b0;
      move_resp_q     <= '0;
    end else begin
      sgnj_valid_q    <= unit_issue_valid[UNIT_SGNJ];
      sgnj_valid_op_q <= sgnj_valid_op_w;
      sgnj_resp_q     <= sgnj_resp_w;
      move_valid_q    <= unit_issue_valid[UNIT_MOVE];
      move_valid_op_q <= move_valid_op_w;
      move_resp_q     <= move_resp_w;
    end
  end

  // Completion collector: up to one completion from each shared unit. Killed
  // operations physically drain their pipe but never enter the response FIFO.
  always_comb begin
    // Retain the historical same-cycle completion order across all configured
    // widths so changing ISSUE_WIDTH does not silently change response order.
    completion_valid     = {move_valid_q, sgnj_valid_q, compare_valid,
                            convert_valid, add_valid, mult_valid, fma_valid,
                            sqrt_valid, div_valid};
    completion_valid_op  = {move_valid_op_q, sgnj_valid_op_q,
                            compare_valid_op, convert_valid_op, add_valid_op,
                            mult_valid_op, fma_valid_op, sqrt_valid_op,
                            div_valid_op};
    completion_resp[0] = div_resp;
    completion_resp[1] = sqrt_resp;
    completion_resp[2] = fma_resp;
    completion_resp[3] = mult_resp;
    completion_resp[4] = add_resp;
    completion_resp[5] = convert_resp;
    completion_resp[6] = compare_resp;
    completion_resp[7] = sgnj_resp_q;
    completion_resp[8] = move_resp_q;

    push_count = '0;
    completion_drop_count = '0;
    for (int unsigned idx = 0; idx < NUM_UNITS; idx++) begin
      push_resp[idx]     = '0;
      push_valid_op[idx] = 1'b0;
      completion_drop_tag[idx] = '0;
    end

    for (int unsigned idx = 0; idx < NUM_UNITS; idx++) begin
      if (completion_valid[idx]) begin
        if (killed_q[completion_resp[idx].tag] ||
            kill_matches(kill_i, completion_resp[idx].tag)) begin
          completion_drop_tag[completion_drop_count] =
            completion_resp[idx].tag;
          completion_drop_count++;
        end else begin
          push_resp[push_count]     = completion_resp[idx];
          push_valid_op[push_count] = completion_valid_op[idx];
          push_count++;
        end
      end
    end
  end

  always_comb begin : p_wb_status
    wb_killed = '0;
    for (int unsigned lane = 0; lane < WRITEBACK_WIDTH; lane++) begin
      wb_killed[lane] = wb_valid_q[lane] &&
                        (killed_q[wb_resp_q[lane].tag] ||
                         kill_matches(kill_i, wb_resp_q[lane].tag));
    end
  end

  assign valid_o    = wb_valid_q & ~wb_killed;
  assign resp_o     = wb_resp_q;
  assign valid_op_o = wb_valid_op_q & ~wb_killed;
  assign wb_pop     = valid_o & ready_i;
  assign wb_release = wb_pop | wb_killed;

  always_comb begin : p_wb_allocate
    int unsigned read_index;

    wb_release_count   = '0;
    fifo_to_wb_count   = '0;
    wb_load            = '0;
    wb_load_resp       = '0;
    wb_load_valid_op   = '0;

    for (int unsigned lane = 0; lane < WRITEBACK_WIDTH; lane++) begin
      if (wb_release[lane]) begin
        wb_release_count++;
      end
      if ((!wb_valid_q[lane] || wb_release[lane]) &&
          (fifo_to_wb_count < resp_count_q)) begin
        read_index = (resp_read_ptr_q + fifo_to_wb_count) % RESP_FIFO_DEPTH;
        wb_load[lane]          = 1'b1;
        wb_load_resp[lane]     = resp_fifo_q[read_index];
        wb_load_valid_op[lane] = resp_fifo_valid_op_q[read_index];
        fifo_to_wb_count++;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : p_response_storage
    int unsigned write_index;

    if (!rst_ni) begin
      resp_read_ptr_q  <= '0;
      resp_write_ptr_q <= '0;
      resp_count_q     <= '0;
      outstanding_q    <= '0;
      killed_q         <= '0;
      active_q         <= '0;
      wb_valid_q       <= '0;
      wb_resp_q        <= '0;
      wb_valid_op_q    <= '0;
      for (int unsigned idx = 0; idx < RESP_FIFO_DEPTH; idx++) begin
        resp_fifo_q[idx]          <= '0;
        resp_fifo_valid_op_q[idx] <= 1'b0;
      end
    end else begin
      for (int unsigned idx = 0; idx < NUM_UNITS; idx++) begin
        if (idx < push_count) begin
          write_index = (resp_write_ptr_q + idx) % RESP_FIFO_DEPTH;
          resp_fifo_q[write_index]          <= push_resp[idx];
          resp_fifo_valid_op_q[write_index] <= push_valid_op[idx];
        end
      end

      if (push_count != 0) begin
        resp_write_ptr_q <= (resp_write_ptr_q + push_count) % RESP_FIFO_DEPTH;
      end
      if (fifo_to_wb_count != 0) begin
        resp_read_ptr_q <= (resp_read_ptr_q + fifo_to_wb_count) %
                           RESP_FIFO_DEPTH;
      end
      resp_count_q <= resp_count_q + push_count - fifo_to_wb_count;
      outstanding_q <= outstanding_q + accepted_count - wb_release_count -
                       completion_drop_count;

      // Establish the killed range first. Later assignments retire tags whose
      // physical operation or buffered result drains on this same edge.
      if (kill_i.valid) begin
        for (int unsigned tag_idx = 0; tag_idx < TAG_COUNT; tag_idx++) begin
          if ((kill_i.all || kill_i.tag_mask[tag_idx]) &&
              active_q[tag_idx]) begin
            killed_q[tag_idx] <= 1'b1;
          end
        end
      end
      // active_q makes tags unique across pipelines and all response buffers.
      // A killed tag naturally remains not-ready until its old operation has
      // physically drained and one of the release paths below clears it.
      for (int unsigned unit_idx = 0; unit_idx < NUM_UNITS; unit_idx++) begin
        if (unit_issue_valid[unit_idx]) begin
          active_q[unit_req[unit_idx].tag] <= 1'b1;
          killed_q[unit_req[unit_idx].tag] <= 1'b0;
        end
      end
      for (int unsigned idx = 0; idx < NUM_UNITS; idx++) begin
        if (idx < completion_drop_count) begin
          active_q[completion_drop_tag[idx]] <= 1'b0;
          killed_q[completion_drop_tag[idx]] <= 1'b0;
        end
      end
      for (int unsigned lane = 0; lane < WRITEBACK_WIDTH; lane++) begin
        if (wb_killed[lane]) begin
          active_q[wb_resp_q[lane].tag] <= 1'b0;
          killed_q[wb_resp_q[lane].tag] <= 1'b0;
        end else if (wb_pop[lane]) begin
          active_q[wb_resp_q[lane].tag] <= 1'b0;
        end
      end

      for (int unsigned lane = 0; lane < WRITEBACK_WIDTH; lane++) begin
        if (wb_load[lane]) begin
          wb_valid_q[lane]    <= 1'b1;
          wb_resp_q[lane]     <= wb_load_resp[lane];
          wb_valid_op_q[lane] <= wb_load_valid_op[lane];
        end else if (wb_release[lane]) begin
          wb_valid_q[lane]    <= 1'b0;
          wb_resp_q[lane]     <= '0;
          wb_valid_op_q[lane] <= 1'b0;
        end
      end

      if ((resp_count_q + push_count) >
          (RESP_FIFO_DEPTH + fifo_to_wb_count)) begin
        $fatal(1, "fpu_top response FIFO overflow");
      end
    end
  end

  initial begin
    if ((ISSUE_WIDTH < 1) || (ISSUE_WIDTH > 4)) begin
      $fatal(1, "fpu_top ISSUE_WIDTH must be in 1..4");
    end
    if ((WRITEBACK_WIDTH < 1) || (WRITEBACK_WIDTH > 4)) begin
      $fatal(1, "fpu_top WRITEBACK_WIDTH must be in 1..4");
    end
    if (RESP_FIFO_DEPTH < (ISSUE_WIDTH + WRITEBACK_WIDTH)) begin
      $fatal(1, "fpu_top RESP_FIFO_DEPTH is too small");
    end
  end

endmodule : fpu_top
