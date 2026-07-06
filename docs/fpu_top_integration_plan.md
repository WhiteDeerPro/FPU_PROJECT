# FPU Top Integration Plan

This note is a design plan only. It records the next `fpu_top` integration
steps around architectural state, buffering, flush, and future wider issue.
No RTL behavior is changed by this document.

## Current Top Boundary

`rtl/core/fpu_top.sv` is currently a decoded-request execution wrapper:

- The CPU/core provides source operands, formats, rounding mode, `rd`, and
  `tag` in `fpu_req_t`.
- The FPU dispatches to existing scalar pipe units and returns `fpu_resp_t`.
- FDIV/FSQRT can deassert `ready_o` when their internal context slots are full.
- Other units are treated as one-request-per-cycle pipes.
- Response selection is fixed priority and has no response FIFO yet.

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

## FIFO And Dataflow Waiting

The first real top-level dataflow problem is response collision. Independent
units can complete in the same cycle, but the current `fpu_top` output mux
selects one fixed-priority response and drops the others. Before sustained
mixed issue is enabled, add a small response collector.

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
  +--> sqrt pipe ---+
  +--> convert -----+
  +--> compare -----+
  +--> sgnj/move ---+
```

Implementation choices:

- Minimal path: collect all same-cycle completions into a small multi-push
  response FIFO. If the FIFO cannot accept the worst-case number of completions,
  throttle issue early enough to prevent overflow.
- Conservative path: add one-entry skid registers per unit plus a single
  response FIFO push port. This is simpler to time, but needs per-unit
  backpressure or "do not issue when skid may overflow" bookkeeping.
- Scoreboard-aware path: let the CPU scoreboard track destination readiness and
  let the FPU response queue preserve enough `tag`/`rd` metadata for writeback.

`ready_o` should eventually mean "the top can accept this request without
losing a future response", not only "the selected FDIV/FSQRT context is free".

## Flush Requirements

`fpu_pkg` already defines:

```systemverilog
typedef struct packed {
  logic     valid;
  fpu_tag_t min_tag;
} fpu_flush_t;
```

The missing contract is tag age ordering. Before coding, define one of these
policies explicitly:

- Flush all in-flight requests with `tag >= min_tag`.
- Keep all requests with `tag < min_tag`.
- Use a wrapping age comparison if tags are allocated from a circular ROB.

Recommended behavior after the policy is fixed:

- Add `flush_i` to `fpu_top` and to every pipe/context unit that can hold
  in-flight work.
- Carry `tag`, `rd`, and sideband metadata through every pipeline stage.
- On flush, clear matching valid bits in fixed-latency pipes.
- In FDIV/FSQRT, invalidate matching context slots and suppress late FMA
  sub-results for killed contexts.
- Flush response FIFO entries whose tags are killed.
- Do not OR killed instruction flags into architectural `fcsr.fflags`.

The flush path should kill visibility, not necessarily zero every datapath
register. Valid-bit masking is enough as long as stale responses cannot escape.

## Vector And Multi-Issue Direction

The current scalar arithmetic units are still useful for wider designs. The
scaling work belongs around dispatch, metadata, and response collection.

For scalar superscalar:

- Add multiple decoded request lanes in front of `fpu_top`.
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

1. Add `tb_fpu_top` smoke/regression coverage with Verdi-friendly `dbg_*`
   signals around dispatch, ready, response priority, and result payloads.
2. Define the flush tag ordering contract in package comments or a short spec.
3. Add response collector/FIFO planning assertions before changing issue rate.
4. Add top-level `frm_i` only if the CPU does not already resolve dynamic
   rounding.
5. Add flush valid-bit masking to fixed-latency pipes, then to FDIV/FSQRT
   contexts.
6. Revisit 32 x 64-bit register-file ownership when the core/FPU integration
   boundary is clearer.
