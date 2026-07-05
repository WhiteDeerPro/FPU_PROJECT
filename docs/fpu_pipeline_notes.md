# FPU Pipeline And Timing Notes

## Rounding Model

The shared rounding interface is:

- retained significand LSB
- sign
- rounding mode
- GRS bits

`fpu_round_inc` turns those inputs into one increment bit plus `inexact`.
RTZ is therefore the same datapath as every other mode with `round_inc = 0`.
RNE uses `guard & (round | sticky | lsb)`, so exact half-way cases round to
the even retained LSB. `FPU_RM_DYN` currently maps to RNE inside the unit until
a top-level CSR rounding-mode input is added.

## Convert Unit Critical Paths

### I2F

Path:

1. Integer sign/magnitude extraction.
2. 64-bit leading-one position encoder.
3. Left barrel shift for normalization.
4. GRS window extraction.
5. Rounding increment decision.
6. Mantissa increment, carry into exponent, pack.

Likely long logic:

- absolute-value generation for signed 64-bit inputs
- LOP tree
- 64-bit left shifter
- S-format sticky OR over up to 38 low bits, D-format sticky OR over 9 low bits
- final mantissa increment and exponent carry

Pipe candidates:

- after sign/magnitude extraction and LOP
- after the normalization shifter
- after rounding/pack if the target clock is tight

### F2I

Path:

1. FP unpack/classify and bias selection.
2. Exponent boundary comparisons.
3. Right barrel shift into integer magnitude.
4. Lost-bit window to GRS.
5. Rounding increment decision.
6. Magnitude increment.
7. overflow/saturation comparison.
8. sign application and pack.

Likely long logic:

- exponent compare fanout
- 64-bit right shifter plus lost-bit generation
- 64-bit magnitude increment
- rounded overflow comparison
- final two's-complement sign application

Pipe candidates:

- after unpack/classify and exponent decode
- after right shift/lost-bit generation
- after rounding increment and rounded overflow compare

### F2F

S-to-D is mostly unpack, exponent rebias, and mantissa extension. It can remain
in a short path unless NaN-box validation is later added.

D-to-S is longer:

1. D unpack/classify.
2. normal/subnormal path select.
3. GRS extraction from either the low normal mantissa bits or the subnormal
   right-shift window.
4. rounding increment decision.
5. mantissa increment and exponent carry.
6. overflow/underflow flag selection and NaN-boxed S pack.

Pipe candidates:

- after D unpack/classify and exponent range compare
- after subnormal shift/GRS selection
- after round/pack if D-to-S must meet the same clock as add/sub

## Add/Sub Unit Critical Path

Path:

1. Unpack/classify both operands.
2. Apply FSUB sign inversion to operand B.
3. Compare exponents and significands to choose big/small operands.
4. Right-shift-and-jam the smaller significand.
5. 65-bit add or 64-bit subtract.
6. For subtraction, leading-one position encode and left normalize.
7. Extract GRS from the normalized result.
8. Rounding increment decision.
9. Mantissa increment, exponent carry, overflow/underflow flag selection, pack.

Likely long logic:

- exponent/significand compare into operand swap muxes
- 64-bit right shifter with sticky generation
- 65-bit adder/subtractor
- subtraction LOP plus normalization left shifter
- final mantissa increment and pack muxing

Useful pipe cuts:

- stage A: unpack/classify, exponent difference, operand ordering
- stage B: alignment shifter and sticky generation
- stage C: add/sub result
- stage D: LOP/normalization and GRS extraction
- stage E: rounding increment, pack, and flags

Practical options:

- 2 stages: cut after alignment. This is simple but leaves add/sub,
  normalize, and round in one stage.
- 3 stages: cut after alignment and after add/sub. This is a good default for
  a moderate target frequency.
- 4 stages: add a cut after LOP/normalization. This is the safer shape for
  higher clocks because the subtract-cancel path is otherwise very long.
- 5 stages: additionally separate round/pack. This is only worth it if the
  final mantissa increment plus flag muxing becomes visible in synthesis.

## Notes For Later Integration

- Non-pipe add/sub and convert units remain combinational reference datapaths.
  A top-level scheduler can use the `units_pipe` variants when it needs fixed
  latency and higher frequency without changing the request/response payload
  shape.
- Keep `fflags`, `tag`, and `rd` registered with the same stage as the data.
- If cancellation-heavy subtraction is timing-critical, consider replacing the
  current align-subtract-normalize chain with a near-path/far-path split.
- The GRS block is intentionally small and reusable. It can hang off the low
  bits of a left-normalized I2F significand, the lost bits of an F2I right
  shifter, or the low tail of an add/sub normalized significand.

## Implemented Pipeline Variants

Current pipe RTL lives under `rtl/units_pipe/`.

- `fpu_add_unit_pipe`: 3 combinational stages with two internal registers.
  Stage 0 unpacks/orders/aligns and builds initial GRS sideband; stage 1 does
  add/sub/close-cancel LOP and one-bit GRS correction; stage 2 normalizes,
  rounds, packs, and handles special cases.
- `fpu_mult_pipe`: common 53-bit significand multiplier pipeline with two
  internal registers. For WIDTH=53, the 27 Booth rows reduce through six
  compressor levels split as 2/3/1 levels; the last segment also includes the
  final carry-propagate add.
- `fpu_mult_unit_pipe`: 4 combinational stages with three cycle latency. It
  uses `fpu_mult_pipe`, registers the product and delayed sideband once more,
  then performs product LOP, normalization, exponent correction, rounding,
  packing, and special-case muxing in the final stage. The base exponent
  `lhs.exp + rhs.exp - bias - 104` is computed in stage 0 and carried as
  sideband; the final stage only adds `product_lop_pos`.
- `fpu_compare_unit_pipe`: 2 stages. Stage 0 unpacks/classifies and computes
  compare predicates; stage 1 selects compare/min/max/class result and flags.
- `fpu_convert_unit_pipe`: 2-cycle conversion pipe with I2F, F2F, and F2I
  leaf-internal cuts. Each leaf runs stage 0 decode/normalize/shift/GRS
  preparation, registers its intermediate payload, then runs stage 1 rounding,
  boundary checks, and response packing before the output register. The wrapper
  delays the request by the same two cycles and selects the matching leaf
  response.
