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
- `rtl/core/fpu_top.sv` is the configurable decoded-request backend, not a full
  RISC-V coprocessor shell. Protocol conversion belongs in sibling wrappers.

## Type Model

The FPU `op` field describes the operation family after CPU decode. Concrete operand/result types are selected by request fields:

- `op`: decoded FPU operation family, such as add, multiply, convert, or move.
- `rs_fmt`: source floating-point format.
- `dst_fmt`: destination floating-point format.
- `int_fmt`: integer width and signedness.
- `rm`: rounding mode.

This keeps the top-level bus compact while still distinguishing single/double floating-point and signed/unsigned integer conversions.

## Protocol Wrapper Organization

The native backend does not know whether requests originate from CV-X-IF,
AXI4, a tightly coupled CPU port, or a testbench:

```text
fpu_cvxif_wrapper ----+
fpu_axi4_wrapper  -----+--> fpu_top #(ISSUE_WIDTH, WRITEBACK_WIDTH)
native core port  -----+             |
                                    +--> shared ADD/MUL/FMA/DIV/... units
                                    +--> response FIFO and writeback lanes
```

Each protocol wrapper owns protocol state, request decoding/packing, response
IDs, and any clock-domain or bus buffering. It also chooses the elaborated
native issue/writeback widths. `fpu_top` owns only execution scheduling,
arithmetic resources, native backpressure, result buffering, tags, and flush.

The CV-X-IF wrapper replicates one to four independent protocol slots and
configures `fpu_top` issue/writeback width to the same count. An AXI4 peripheral
wrapper is not implemented yet; it would normally expose command and result
register/FIFO windows and translate them to the same native arrays.

## Directory Layout

- `rtl/pkg`: shared packages and top-level bus payload types.
- `rtl/core`: configurable protocol-neutral FPU top, routing, and buffering.
- `rtl/wrappers`: CV-X-IF and future AXI4/native protocol adapters.
- `rtl/common`: reusable combinational building blocks, such as barrel shifters,
  leading-one position encoders, classify, unpack, normalize, round, and pack
  helpers.
- `rtl/units`: combinational operation-level units, such as add/sub, multiply,
  compare, convert, move, and sign injection.
- `rtl/units_pipe`: pipelined add/multiply/FMA/convert/compare and interleaved
  divide/square-root units.
- `sim/tb`: self-checking unit, integration, protocol, and stress testbenches.
- `docs`: architecture notes and design decisions.

## Related Notes

- `docs/fpu_pipeline_notes.md`: rounding model, convert/add-sub critical paths,
  and suggested pipeline cut points.
- `docs/fpu_unit_flow.md`: datapath flow diagrams for the main units.
- `docs/fpu_compressor_notes.md`: bit-compressor diagrams used by multiplier
  and lookup-table reduction logic.

## Native Top Status

`fpu_top` can be instantiated by a core that already performs decode and
owns the architectural state. The usable interface today is:

- `valid_i/ready_o` request handshake.
- `fpu_req_t` decoded operation payload, including source data, formats,
  rounding mode, destination register, and tag.
- `valid_o/ready_i`, `fpu_resp_t`, and `valid_op_o` response handshake.
- Request backpressure is driven by FDIV/FSQRT context availability and by
  reservation capacity in the response FIFO.
- Same-cycle completions from independent units are compacted into the response
  FIFO without fixed-priority loss.
- `kill_i {valid,all,tag_mask}` consumes the exact FPU-tag set selected by the
  CPU integration layer.
- A live-tag table prevents tag reuse until normal writeback or killed physical
  drain releases the old operation.
- Native callers must provide a supported decoded operation. The legacy
  `DECODE_NONE` path is consumed without producing a response; protocol wrappers
  reject unsupported instructions before the native boundary.

The wrapper still needs these integration pieces before it should be treated as
a complete core-facing FPU subsystem:

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

There is no need for active out-of-order execution inside the FPU. The core
remains responsible for dependencies, ROB order, and commit. The CPU or
protocol adapter translates branch/ROB recovery into the exact
`kill_i.tag_mask`; the FPU never compares numerical tags to infer age. Rather
than adding kill ports to every arithmetic leaf, the backend uses DRAIN kill:
already-issued work physically drains while killed tags are filtered at
completion, FIFO, and writeback. Killed per-instruction `fflags` never reach
writeback; surviving flags enter architectural `fcsr` only at CPU commit.
An earlier surviving response held in a writeback lane can delay reclamation of
a killed entry still behind it in the ordered central FIFO.

## Superscalar And Vector-Like Scaling

There is a real need to consider this, but it should be treated as a wrapper
and scheduling problem first, not a different arithmetic datapath.

Useful near-term support:

- One to four decoded scalar requests per cycle into `fpu_top`.
- Independent unit pipelines for add/mul/fma/compare/convert plus interleaved
  div/sqrt contexts.
- The implemented response FIFO accepts multiple same-cycle unit completions
  and applies request backpressure based on reserved response capacity.

For superscalar scalar cores, the clean extension is multiple issue lanes into a
front-end dispatcher with scoreboarding and per-unit queues. Arithmetic units
can stay scalar internally.

`rtl/core/fpu_top.sv` provides the shared-unit implementation:
1-to-4 issue lanes, fixed low-index arbitration for same-unit conflicts, and
1-to-4 independent writeback holding lanes. It does not replicate arithmetic
units. Multi-CV-X-IF protocol tracking remains a wrapper-level task.

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
boundary and shared dispatcher/response/kill backend are compatible with it;
vector integration still needs element metadata, mask/tail handling, and any
per-unit queues required by the target throughput.

## Convert Operations

`rtl/pkg/fpu_pkg.sv` already separates conversion operation families:

- `FPU_OP_CVT_F2I`: floating-point to integer.
- `FPU_OP_CVT_I2F`: integer to floating-point.
- `FPU_OP_CVT_FP`: floating-point format conversion.

The concrete signedness and integer width are carried by `int_fmt`; source and
destination FP precision are carried by `rs_fmt` and `dst_fmt`.
