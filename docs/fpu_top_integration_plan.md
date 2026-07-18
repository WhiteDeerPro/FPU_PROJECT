# FPU Top Integration Plan

This note records the core/FPU integration direction around architectural
state, buffering, flush, and wider issue. The shared multi-issue backend,
response buffering, and native DRAIN-kill policy are implemented.

## Current Top Boundary

`rtl/core/fpu_top.sv` is the decoded-request execution backend:

- The CPU/core provides source operands, formats, rounding mode, `rd`, and
  `tag` in `fpu_req_t`.
- The FPU dispatches to existing scalar pipe units and returns `fpu_resp_t`.
- FDIV/FSQRT can deassert `ready_o` when their internal context slots are full.
- Other units are treated as one-request-per-cycle pipes.
- Same-cycle unit completions are compacted into a multi-push response FIFO.
- One to four independent `valid_o/ready_i` lanes provide response backpressure.
- Accepted requests reserve response capacity until their result handshake.
- `kill_i` consumes an exact CPU-produced tag mask, suppresses killed responses,
  and reclaims reservations on drain.
- An active-tag table prevents a live tag from being reused.

Protocol-specific modules are wrappers around this native boundary. For
example, `fpu_cvxif_wrapper` configures one to four issue lanes and the same
number of writeback lanes from `X_NUM_PORTS`; a future AXI4 wrapper can choose
its own queueing and configured width.

That boundary is good for unit integration, but not yet enough for a complete
core-facing FPU subsystem.

## Top-Level Register And CSR Plan

Near-term architectural/control state should be split by ownership:

```text
CPU/commit side:
  mstatus.FS / sstatus.FS dirty tracking
  fcsr.fflags accrued exception flags
  fcsr.frm dynamic rounding mode
  misa.F / misa.D advertised ISA capability

FPU top side:
  optional capability parameters
  decoded request metadata
  in-flight tags and response buffering
  optional frm_i input if dynamic rounding is resolved inside fpu_top
```

Recommended four top-visible control items:

- `status`: do not store full privileged status inside this FPU. The core
  should own `mstatus`/`sstatus`; the FPU may provide a small sideband such as
  "accepted FP op" or "retired FP op" so the core can set FS dirty.
- `fcsr`: keep architectural `fflags` accrual at commit. The FPU should return
  per-instruction `fflags` and let the core OR them into `fcsr.fflags` only for
  non-flushed retiring instructions.
- `frm`: either resolve `FPU_RM_DYN` before issue, or add `frm_i` to `fpu_top`
  and rewrite dynamic requests to the concrete rounding mode at accept time.
- `fmr`: treat this as a configuration/status register name until the external
  contract is fixed. Good candidates are implemented formats, latency/profile
  bits, and enable masks for F/D/vector wrappers.

The 32 x 64-bit floating-point register file is intentionally left out for now.
It belongs either in the CPU register-file subsystem or in a larger coprocessor
wrapper that also owns decode, dependencies, commit, and precise exceptions.

## Implemented Response FIFO

Independent units can complete in the same cycle. `fpu_top` compacts all
valid completions in deterministic unit order and writes them into a
parameterized response FIFO (`RESP_FIFO_DEPTH`, default 32).

Recommended shape:

```text
decoded issue
  |
  v
unit dispatch valid bits
  |
  +--> add pipe ----+
  +--> mul pipe ----+
  +--> fma pipe ----+
  +--> div pipe ----+--> response collector --> response FIFO --> valid_o/resp_o
  +--> sqrt pipe ---+                         +--> WB lane 0
  +--> convert -----+
  +--> compare -----+
  +--> sgnj/move ---+                         +--> WB lane N
```

Implemented policy:

- Every accepted supported request increments an outstanding reservation count.
- A `valid_o[lane] && ready_i[lane]` handshake releases one reservation.
- New requests stop when all FIFO capacity has been reserved, even if some
  reserved operations are still executing in leaf pipelines.
- Every same-cycle completion is pushed; up to `WRITEBACK_WIDTH` FIFO results
  may be moved to writeback holding lanes per cycle.
- `resp_o`, `valid_op_o`, and `valid_o` remain stable while `ready_i` is low.

`ready_o` now means "the top can accept this request without losing its future
response" as well as "the selected FDIV/FSQRT context is available".

## Implemented Kill Contract

`fpu_pkg` already defines:

```systemverilog
typedef struct packed {
  logic                     valid;
  logic                     all;
  logic [FPU_TAG_COUNT-1:0] tag_mask;
} fpu_kill_t;
```

The CPU/integration layer owns branch and ROB age, including circular-pointer
wrap, and supplies the exact FPU tags to kill. `fpu_top` is a pure consumer and
does not compare tag values to infer program order.

During a kill cycle issue is stopped. Matching arithmetic operations may
physically finish, but the backend filters them at completion, in buffered
responses, and in writeback holding lanes. A killed result never asserts the
external `valid_o`; its response reservation and active tag are released when
it drains. A killed item already in the ordered central FIFO can be delayed by
an earlier surviving writeback item held under backpressure. There is no
requirement to zero inactive datapath registers.

The CPU continues to own precise state: it records per-instruction flags in
the ROB and ORs them into architectural `fcsr.fflags` only at ordered commit.

The CV-X-IF wrapper uses a different integration policy: a killed commit is
dropped in its protocol slot, and only a non-kill committed instruction enters
`fpu_top`. It therefore ties the native `kill_i` input low.

## Vector And Multi-Issue Direction

The current scalar arithmetic units are still useful for wider designs. The
scaling work belongs around dispatch, metadata, and response collection.

For scalar superscalar (implemented backend portion):

- Connect one to four decoded request lanes to `fpu_top`.
- Use a dispatcher to route lanes to per-unit queues.
- Keep one scoreboard/ROB tag per issued request.
- Preserve precise retirement in the core, not inside arithmetic pipes.
- Size the response collector for multiple same-cycle completions.

For vector:

- Build a vector wrapper that slices vector operands into scalar element
  requests.
- Carry element index, mask/tail policy, vector destination metadata, and ROB
  tag with each lane request.
- Reduce per-element `fflags` into the retiring vector instruction's flags.
- Share FDIV/FSQRT at first; replicate only if workload measurements require
  more throughput.

This avoids rewriting the scalar add/mul/fma/convert/compare datapaths. The
hard parts become queue sizing, tag/element metadata, replay/flush, and precise
flag accrual.

## Suggested Milestones

1. `tb_fpu_top` smoke/regression coverage with Verdi-friendly `dbg_*` signals
   around dispatch, ready, completion collisions, and result payloads:
   implemented.
2. Define the kill ownership contract: implemented as an exact CPU-produced
   tag mask consumed by the backend; the FPU does not infer program age.
3. Response collector/FIFO and capacity reservation: implemented.
4. Add top-level `frm_i` only if the CPU does not already resolve dynamic
   rounding.
5. Add architecturally visible kill masking and drain accounting: implemented
   centrally in `fpu_top`; leaf-pipe power cancellation remains optional.
6. Revisit 32 x 64-bit register-file ownership when the core/FPU integration
   boundary is clearer.
