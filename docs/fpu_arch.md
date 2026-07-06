# FPU Architecture Notes

## Current Baseline

- The FPU is an execution unit attached to an RV CPU core.
- The FPU has no architectural floating-point register file.
- The CPU owns decode, register reads, dependency tracking, issue, writeback, commit, flush, and CSR updates.
- The FPU receives decoded request payloads with source operand values.
- The FPU returns result payloads with `fflags`, `tag`, and `rd`.
- Top-level request/response flow should use `valid/ready` backpressure.
- The top data bus is 64-bit.
- Double-precision operands use the full 64-bit encoding.
- Single-precision operands use the low 32 bits and follow RISC-V NaN-boxing in the high 32 bits.
- The current `rtl/core/fpu_top.sv` is a decoded-request wrapper, not a full
  RISC-V coprocessor shell.

## Type Model

The FPU `op` field describes the operation family after CPU decode. Concrete operand/result types are selected by request fields:

- `op`: decoded FPU operation family, such as add, multiply, convert, or move.
- `rs_fmt`: source floating-point format.
- `dst_fmt`: destination floating-point format.
- `int_fmt`: integer width and signedness.
- `rm`: rounding mode.

This keeps the top-level bus compact while still distinguishing single/double floating-point and signed/unsigned integer conversions.

## Directory Layout

- `rtl/pkg`: shared packages and top-level bus payload types.
- `rtl/core`: future FPU top-level shell, request routing, response arbitration.
- `rtl/common`: reusable combinational building blocks, such as barrel shifters,
  leading-one position encoders, classify, unpack, normalize, round, and pack
  helpers.
- `rtl/units`: operation-level units, such as add/sub, multiply, compare,
  convert, move, and future div/sqrt units.
- `sim/tb`: future testbenches.
- `docs`: architecture notes and design decisions.

## Related Notes

- `docs/fpu_pipeline_notes.md`: rounding model, convert/add-sub critical paths,
  and suggested pipeline cut points.
- `docs/fpu_unit_flow.md`: datapath flow diagrams for the main units.

## Top Wrapper Status

`fpu_top` can be instantiated by a core that already performs decode and owns
the architectural state. The usable interface today is:

- `valid_i/ready_o` request handshake.
- `fpu_req_t` decoded operation payload, including source data, formats,
  rounding mode, destination register, and tag.
- `valid_o`, `fpu_resp_t`, and `valid_op_o` response payload.
- Backpressure is only driven by FDIV/FSQRT context availability; other pipe
  units accept one request per cycle.

The wrapper still needs these integration pieces before it should be treated as
a complete core-facing FPU subsystem:

- A response FIFO or scoreboard-aware return path. The current response mux has
  fixed priority and can drop same-cycle completions from unrelated pipes under
  sustained mixed issue.
- A flush input. `fpu_pkg` already defines `fpu_flush_t {valid, min_tag}`, but
  `fpu_top` does not consume it yet.
- CSR plumbing. `frm`/dynamic rounding, accrued `fflags`/`fcsr`, and any
  privileged CSR reflection are expected to live in the CPU/CSR block today.
- ISA configuration. `CSR_MISA` is not implemented inside this FPU; the core
  should advertise F/D support there according to the configured system.

## CSR Boundary

The FPU units return per-instruction `fflags`. They do not hold architectural
`fcsr`. A core wrapper should:

1. Resolve `rm == FPU_RM_DYN` from `fcsr.frm` before issuing into the FPU, or
   provide a top-level `frm_i` and resolve it in `fpu_top`.
2. OR retiring instruction flags into `fcsr.fflags` at commit.
3. Keep speculative flags out of `fcsr` until the instruction is known to
   retire.

`CSR_STATUS`/`mstatus` FS state and `CSR_MISA` are also core-level concerns.
This FPU can provide capability parameters, but it should not own privileged
CSR storage unless it is wrapped into a larger coprocessor block.

## Flush Direction

There is no need for active out-of-order execution inside the FPU for the
current design. The core should remain responsible for issue order,
dependencies, and commit. What the FPU does need is kill/flush support for
speculative pipe contents.

Recommended shape:

- Add `flush_i: fpu_flush_t` to `fpu_top` and every pipe unit that can hold
  multiple in-flight requests.
- Carry `tag` through every pipeline stage and div/sqrt context.
- On `flush_i.valid`, clear stage/context valid bits whose tag is younger than
  or equal to the chosen policy around `flush_i.min_tag`.
- Do not update architectural `fcsr` directly from flushed responses; the core
  only accrues flags at commit.

The existing `min_tag` name suggests an age-threshold policy. Before coding,
the core tag ordering should be made explicit: either "flush tag >= min_tag" or
"keep tag < min_tag". Once that convention is fixed, the hardware is mostly
valid-bit masking plus div/sqrt context invalidation.

## Superscalar And Vector-Like Scaling

There is a real need to consider this, but it should be treated as a wrapper
and scheduling problem first, not a different arithmetic datapath.

Useful near-term support:

- One decoded scalar request per cycle into `fpu_top`.
- Independent unit pipelines for add/mul/fma/compare/convert plus interleaved
  div/sqrt contexts.
- A response FIFO that can accept multiple same-cycle unit completions or
  otherwise applies backpressure before collisions happen.

For superscalar scalar cores, the clean extension is multiple issue lanes into a
front-end dispatcher with scoreboarding and per-unit queues. Arithmetic units
can stay scalar internally.

For vector workloads, the likely design is lane replication around the existing
scalar units:

- A vector wrapper slices element operands into scalar lane requests.
- Each lane carries element index, vector destination metadata, mask/tail state,
  and exception flags.
- Per-element `fflags` reduce into the architectural vector/scalar accrued
  flags at commit.
- FDIV/FSQRT can remain lower-throughput shared resources unless target
  workloads justify lane replication.

So yes, vector-like demand is worth planning for. The current scalar unit
boundary is compatible with it, but `fpu_top` needs a stronger dispatcher,
response buffering, flush tagging, and metadata sideband before superscalar or
vector wrappers are pleasant to build.

## Convert Operations

`rtl/pkg/fpu_pkg.sv` already separates conversion operation families:

- `FPU_OP_CVT_F2I`: floating-point to integer.
- `FPU_OP_CVT_I2F`: integer to floating-point.
- `FPU_OP_CVT_FP`: floating-point format conversion.

The concrete signedness and integer width are carried by `int_fmt`; source and
destination FP precision are carried by `rs_fmt` and `dst_fmt`.
