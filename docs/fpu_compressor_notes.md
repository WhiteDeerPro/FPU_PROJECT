# FPU Compressor Notes

This note records the bit-compressor blocks used by multiplier reduction trees
and by small lookup-table interpolation datapaths. Booth recoding is deliberately
left out here; this page only describes the compression cells.

Current RTL:

- `rtl/common/fpu_compressors.sv`
- `fpu_compressor_3_2`
- `fpu_compressor_4_2`

## 3-2 Compressor

A 3-2 compressor is the one-column full-adder form used across a vector of bit
columns:

```text
a + b + c = sum + 2*carry
```

`sum` remains in the same bit column. `carry` has weight two and is therefore
shifted left by one when it is consumed by the next reduction level or by a
final carry-propagate adder.

```mermaid
flowchart LR
  classDef data fill:#fff,stroke:#111,stroke-width:1.5px,color:#111;
  classDef ctrl fill:#f8f8f8,stroke:#333,stroke-width:1.2px,stroke-dasharray:5 4,color:#111;
  classDef group fill:#fff,stroke:#111,stroke-width:1.6px,color:#111;

  A["a[i]"]:::data
  B["b[i]"]:::data
  C["c[i]"]:::data

  subgraph FA["3-2 compressor / full adder"]
    direction TB
    XOR["sum = a xor b xor c"]:::data
    MAJ["carry = majority(a,b,c)"]:::data
  end
  class FA group

  A --> XOR
  B --> XOR
  C --> XOR
  A --> MAJ
  B --> MAJ
  C --> MAJ

  XOR --> SUM["sum[i]<br/>weight 1"]:::data
  MAJ --> CARRY["carry[i]<br/>weight 2"]:::data
```

Reduction-tree view:

```mermaid
flowchart LR
  classDef data fill:#fff,stroke:#111,stroke-width:1.5px,color:#111;
  classDef ctrl fill:#f8f8f8,stroke:#333,stroke-width:1.2px,stroke-dasharray:5 4,color:#111;
  classDef group fill:#fff,stroke:#111,stroke-width:1.6px,color:#111;

  ROWS["Three aligned rows<br/>A · B · C"]:::data
  COMP["3-2 compressor vector"]:::data
  SUM["sum row"]:::data
  CAR["carry row<br/>shift left by one"]:::data
  NEXT["Next compressor level<br/>or final CPA"]:::data

  ROWS --> COMP
  COMP --> SUM --> NEXT
  COMP --> CAR --> NEXT
```

## From 5-3 To 4-2

The implemented `fpu_compressor_4_2` is best understood as a five-input
compressor with two carry outputs:

```text
a + b + c + d + cin = sum + 2*carry + 2*cout
```

In an array, the `cout` produced by one column is naturally routed as the
neighbor column's `cin`. For that reason this five-input structure is commonly
called a 4-2 compressor: it reduces four local rows plus a carry-in sideband
into one local sum row, one local carry row, and one carry-out sideband.

```mermaid
flowchart LR
  classDef data fill:#fff,stroke:#111,stroke-width:1.5px,color:#111;
  classDef ctrl fill:#f8f8f8,stroke:#333,stroke-width:1.2px,stroke-dasharray:5 4,color:#111;
  classDef group fill:#fff,stroke:#111,stroke-width:1.6px,color:#111;

  A["a[i]"]:::data
  B["b[i]"]:::data
  C["c[i]"]:::data
  D["d[i]"]:::data
  CIN["cin[i]<br/>from previous column"]:::ctrl

  subgraph COMP["5-input compressor<br/>used as 4-2"]
    direction TB
    FIRST["First 3-input combine<br/>a,b,c -> mid_sum, cout"]:::data
    SECOND["Second 3-input combine<br/>mid_sum,d,cin -> sum, carry"]:::data
  end
  class COMP group

  A --> FIRST
  B --> FIRST
  C --> FIRST
  FIRST --> SECOND
  D --> SECOND
  CIN -.-> SECOND

  SECOND --> SUM["sum[i]<br/>weight 1"]:::data
  SECOND --> CARRY["carry[i]<br/>weight 2"]:::data
  FIRST --> COUT["cout[i]<br/>to next column cin"]:::ctrl
```

Array-level view:

```mermaid
flowchart LR
  classDef data fill:#fff,stroke:#111,stroke-width:1.5px,color:#111;
  classDef ctrl fill:#f8f8f8,stroke:#333,stroke-width:1.2px,stroke-dasharray:5 4,color:#111;
  classDef group fill:#fff,stroke:#111,stroke-width:1.6px,color:#111;

  ROWS["Four partial-product rows<br/>A · B · C · D"]:::data
  CIN["cin sideband"]:::ctrl
  COMP["4-2 compressor vector"]:::data
  SUM["sum row"]:::data
  CAR["carry row<br/>shift left by one"]:::data
  COUT["cout sideband<br/>feeds next column"]:::ctrl
  NEXT["Next compressor level<br/>or final CPA"]:::data

  ROWS --> COMP
  CIN -.-> COMP
  COMP --> SUM --> NEXT
  COMP --> CAR --> NEXT
  COMP -.-> COUT
  COUT -.-> CIN
```

## 4-2 Compression Tree View

At the reduction-tree level, a 4-2 compressor is useful because every level
roughly halves the number of rows while preserving the weighted sum. For a
16-row example:

```text
A1 + A2 + ... + A16 = X1 + X2

16 rows -> 8 rows -> 4 rows -> 2 rows
          level 0    level 1    level 2
```

The final two rows `X1` and `X2` are then added by a normal carry-propagate
adder. This is the main picture to keep in mind for multiplier partial-product
reduction: compressors do not finish the addition; they reshape many aligned
rows into two aligned rows with the same numeric value.

```mermaid
flowchart LR
  classDef data fill:#fff,stroke:#111,stroke-width:1.5px,color:#111;
  classDef ctrl fill:#f8f8f8,stroke:#333,stroke-width:1.2px,stroke-dasharray:5 4,color:#111;
  classDef group fill:#fff,stroke:#111,stroke-width:1.6px,color:#111;

  subgraph IN["Input partial-product rows"]
    direction TB
    A1["A1"]:::data
    A2["A2"]:::data
    A3["A3"]:::data
    A4["A4"]:::data
    A5["A5"]:::data
    A6["A6"]:::data
    A7["A7"]:::data
    A8["A8"]:::data
    A9["A9"]:::data
    A10["A10"]:::data
    A11["A11"]:::data
    A12["A12"]:::data
    A13["A13"]:::data
    A14["A14"]:::data
    A15["A15"]:::data
    A16["A16"]:::data
  end
  class IN group

  L0["4-2 compressor level 0<br/>16 rows -> 8 rows"]:::data
  L1["4-2 compressor level 1<br/>8 rows -> 4 rows"]:::data
  L2["4-2 compressor level 2<br/>4 rows -> 2 rows"]:::data

  subgraph OUT["Reduced rows"]
    direction TB
    X1["X1"]:::data
    X2["X2"]:::data
  end
  class OUT group

  CPA["Final carry-propagate add<br/>X1 + X2"]:::data
  EQ["X1 + X2 = A1 + A2 + ... + A16"]:::ctrl

  IN --> L0 --> L1 --> L2 --> OUT --> CPA
  OUT -. weighted-sum preserved .-> EQ
```

Compact view:

```mermaid
flowchart LR
  classDef data fill:#fff,stroke:#111,stroke-width:1.5px,color:#111;
  classDef ctrl fill:#f8f8f8,stroke:#333,stroke-width:1.2px,stroke-dasharray:5 4,color:#111;

  A["A1, A2, A3, ... , A16<br/>16 aligned rows"]:::data
  L0["4-2<br/>level 0"]:::data
  B["8 rows"]:::data
  L1["4-2<br/>level 1"]:::data
  C["4 rows"]:::data
  L2["4-2<br/>level 2"]:::data
  X["X1, X2<br/>2 rows"]:::data
  CPA["CPA"]:::data
  R["final sum"]:::data
  EQ["X1 + X2 = sum(A1..A16)"]:::ctrl

  A --> L0 --> B --> L1 --> C --> L2 --> X --> CPA --> R
  X -.-> EQ
```

The code in `fpu_compressor_4_2` writes this directly as Boolean compressor
logic rather than instantiating two `fpu_compressor_3_2` submodules. The shape
is still the same conceptual evolution: 3-2 full-adder compression, then a
five-input form that becomes a practical 4-2 compressor when `cout` is chained
between columns.
