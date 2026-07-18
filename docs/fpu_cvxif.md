# FPU CV-X-IF Wrapper

`rtl/wrappers/fpu_cvxif_wrapper.sv` replicates one to four CV-X-IF protocol
ports around a single shared `fpu_top`. It uses the OpenHW Group interface
definition in `rtl/interfaces/core_v_xif.sv` and supports both coupled and
split issue/register operation.

## Initial Integration Contract

- `X_NUM_RS = 3`
- `X_RFR_WIDTH = 64`
- `X_RFW_WIDTH = 64`
- `X_DUALREAD = 0`
- `X_DUALWRITE = 0`
- `X_NUM_PORTS = 1..4`
- One accepted instruction may be in flight per replicated port.
- Up to `X_NUM_PORTS` instructions can enter distinct FPU units together.
- Equal external IDs on different ports are supported.
- The CPU emits an explicit commit transaction for each accepted FPU ID.
- Compatibility limit: commit/kill is matched to that exact `{hartid,id}`.
  CV-X-IF v1.0 batched age-range commit/kill semantics are not implemented by
  this one-slot-per-port wrapper, so the integrating CPU must not batch them.
- F/D load and store instructions are not handled by this wrapper.
- Compressed and CV-X-IF memory channels are inactive.

The official CV-X-IF register and result channels do not identify an FPR
register bank. This project therefore adds the following CPU-integration
sidebands:

- `issue_rs_fpr_o[port][2:0]`: source register-bank selection per port.
- `issue_rd_fpr_o[port]`: destination bank selected during issue decode.
- `result_rd_fpr_o[port]`: destination bank accompanying each result.
- `result_fflags_o[port]`: per-instruction flags accompanying each result.

These sidebands are not part of standard CV-X-IF. A CPU with a native FPR must
use them, or implement equivalent instruction-ID metadata, to route register
reads and writeback correctly.

## Commit And Kill Policy

Every port independently waits for operands and a matching non-kill commit
before asserting its corresponding `fpu_top.valid_i[port]`. A matching kill
before execution drops only that port's transaction.

This is a deliberately narrower integration contract than the standard
CV-X-IF commit channel, where a non-kill ID can commit older instructions and a
kill ID can cancel newer instructions in a batch. Supporting that contract
requires age tracking across all replicated ports; the current wrapper instead
requires one exact-ID commit/kill notification per accepted transaction.

CV-X-IF permits commit to arrive while an issue transaction is waiting for
`issue_ready`. Each port retains one early matching commit for its pending
request.

The wrapper uses the port index as an internal FPU token. `fpu_top` responses
are routed by that token to the port slot, which restores the original XIF
`hartid` and `id`. One stalled result port backpressures only its assigned FPU
writeback lane.

This implementation has one protocol slot per port, rather than an arbitrary
outstanding-ID table per port. Thus it supports N-way simultaneous issue and N
concurrent transactions. Sustaining N new issues every cycle regardless of
latency would require a deeper `{port,id}` transaction table as a later step.

## `fcsr` Boundary

`fcsr` remains in the CPU. The CPU supplies `frm_i`; dynamic instruction
rounding (`rm=111`) is resolved by the wrapper before entering the FPU. The CPU
must accumulate `result_fflags_o` into `fcsr.fflags` at architectural commit.

## Supported Decode

The wrapper decodes scalar RISC-V F/D arithmetic, FMA, compare, min/max,
classify, sign injection, FP/integer moves, and FP/integer/format conversions.
It rejects unsupported opcodes and reserved rounding modes with
`issue_resp.accept = 0`.

## Smoke Tests

From the repository root:

```sh
make -C sim/tb cvxif
make -C sim/tb cvxif_verdi
make -C sim/tb cvxif_verdi_sch
make -C sim/tb cvxif_multi
make -C sim/tb cvxif_multi_verdi
make -C sim/tb cvxif_multi_verdi_sch
make -C sim/tb cvxif_coupled
make -C sim/tb cvxif_coupled_verdi
make -C sim/tb cvxif_coupled_verdi_sch
make -C sim/tb cvxif_mult_burst
make -C sim/tb cvxif_mult_burst_verdi
make -C sim/tb cvxif_mult_burst_verdi_sch
```

The tests cover unsupported-instruction rejection, split/coupled register
delivery, coincident commit, kill-before-execute, four heterogeneous ports
issuing together, four same-unit requests serialized by the shared-unit
arbiter, equal external IDs on different ports, response routing, and
independent result backpressure.

`cvxif_mult_burst` is a throughput-oriented diagnostic endpoint. It sends 1024
coupled and already-committed `FMUL.D` transactions without bubbles, using
`cos(x)` for both operands. This fills `fpu_mult_unit_pipe` and its internal
`fpu_mult_pipe`. Dedicated input/output `real` replicas and a CSV file make the
`cos(x)` and `cos(x)^2` waveforms easy to inspect in Verdi.

## Source References

- CV-X-IF specification: https://docs.openhwgroup.org/projects/openhw-group-core-v-xif/en/latest/
- Canonical SystemVerilog interface: https://github.com/openhwgroup/core-v-xif/blob/main/src/core_v_xif.sv

The local interface changes the canonical unpacked `rs` array into an
equivalent packed array so that the repository's VCS 2018 toolchain accepts the
type.
