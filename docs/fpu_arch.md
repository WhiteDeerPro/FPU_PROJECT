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
