# Shared-Unit Multi-Issue FPU

`rtl/core/fpu_top.sv` is the only native FPU backend. It is a parameterized
1-to-4 issue and 1-to-4 writeback design. Protocol adapters instantiate this
module and select widths appropriate to their external interface. The widths
are elaboration parameters because they change the number of physical ports:

```systemverilog
ISSUE_WIDTH     = 1..4
WRITEBACK_WIDTH = 1..4
RESP_FIFO_DEPTH = 32
```

The native input is a decoded-operation interface: callers must issue only
operations supported by `fpu_top`. For legacy compatibility, `DECODE_NONE`
observes `ready_o=1` but is discarded without reserving or returning a
response. Protocol wrappers such as CV-X-IF reject unsupported instructions
before they reach this boundary.

## Resource Model

There is still exactly one instance of each arithmetic resource:

- one ADD/SUB pipe;
- one MUL pipe;
- one FMA pipe;
- one DIV unit;
- one SQRT unit;
- one conversion pipe;
- one compare pipe;
- one SGNJ path;
- one move path.

Different target units can accept requests from different issue lanes in the
same cycle. Requests targeting the same unit conflict. Arbitration is fixed
priority, with lane 0 highest and increasing lane indices progressively lower
priority. An invalid low-index lane does not reserve a resource.

Examples for four valid lanes:

```text
ADD + MUL + FMA + CMP  -> all four accepted
ADD + ADD + MUL + FMA  -> lane-0 ADD, MUL, and FMA accepted
MUL + MUL + MUL + MUL  -> only the lowest valid lane accepted
```

This policy improves utilization of heterogeneous pipelines without
replicating expensive arithmetic units.

## Response Capacity

Every accepted request reserves one of `RESP_FIFO_DEPTH` total response
positions until a CPU writeback handshake consumes it. Up to nine shared units
may complete together and push results into the central response FIFO.

An active-tag table prevents two live requests from using the same tag. A tag
remains busy through arithmetic execution, the response FIFO, and writeback
holding registers, including while a killed operation physically drains.

## Speculative Kill

The native backend consumes an exact `fpu_kill_t` produced by the CPU
integration layer. `kill_i.all` clears every active transaction; otherwise
`kill_i.tag_mask[tag]` selects individual FPU tags. The backend does not infer
ROB age from the numerical tag value.

Issue is stopped for the flush cycle. Arithmetic already inside a pipe may
continue to toggle and drain, but killed completions are discarded before the
response FIFO. Killed writeback entries are suppressed and released without
waiting for their CPU `ready_i`. Killed entries already in the central FIFO are
suppressed when they reach a writeback lane; FIFO order means an earlier
surviving result held under backpressure can delay that reclamation. No killed
result becomes externally visible.

The CPU owns branch recovery and circular ROB age. It must translate that state
to the exact FPU kill mask before driving `kill_i`. The current implementation
uses DRAIN kill; leaf arithmetic continues physically and only its result is
discarded.

## Multi-Writeback

Each writeback lane has an independent one-entry holding register:

```systemverilog
valid_o[lane]
ready_i[lane]
resp_o[lane]
valid_op_o[lane]
```

The central FIFO refills any empty or simultaneously consumed holding lane.
Therefore lane 0 may remain blocked while lanes 1 through 3 continue consuming
and refilling. A result remains stable in its holding lane until that lane's
`valid_o && ready_i` handshake.

With four ready writeback lanes, up to four results can be consumed in one
cycle. If the CPU exposes fewer writeback ports, set `WRITEBACK_WIDTH` to the
actual physical bandwidth; the central FIFO absorbs short completion bursts
and eventually backpressures issue through response reservations.

## CV-X-IF Mapping

The CV-X-IF specification expects superscalar implementations to duplicate the
interface according to issue width. The recommended integration is multiple
CV-X-IF protocol frontends feeding one `fpu_top` backend, not multiple
copies of the FPU backend.

Each accepted request must carry or map these fields through the shared
backend:

```text
source_xif_port
hartid
xif_id
rd / register-bank metadata
fflags metadata
```

The wrapper uses the replicated port index as its internal FPU token and keeps
the original `hartid/id` in the corresponding protocol slot. Therefore equal
external IDs on different ports do not collide.

`fpu_top` implements the protocol-neutral shared dispatch and writeback
backend. `fpu_cvxif_wrapper` instantiates `X_NUM_PORTS=1..4` protocol slots and
configures both native issue and writeback width to that port count. The
current implementation has one outstanding transaction per port; a deeper
per-port ID table remains a separate throughput extension.

## Verification

```sh
make top_multi
make virtual_core
make cvxif_multi
make top_multi_verdi
make top_multi_verdi_sch
make virtual_core_verdi
```

The test covers an older long-latency divide being overtaken by younger short
operations, sustained multi-outstanding traffic through a non-power-of-two
response FIFO with read/write pointer wrap, four heterogeneous requests
accepted together, same-cycle duplicate-tag rejection, four same-unit requests
resolved by low-index priority, a high-index lane issuing when lower lanes are
idle, and four independent writeback backpressure patterns. The virtual-core
test adds RAW scoreboard/ROB forwarding, active-tag exclusion, ordered FPR/FCSR
commit, and suppression of a flushed exception result.
