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
A0 + A1 + ... + A15 = B1 + B2

16 rows -> 8 rows -> 4 rows -> 2 rows
          level 0    level 1    level 2
```

The final two rows `B1` and `B2` are then added by a normal carry-propagate
adder. This is the main picture to keep in mind for multiplier partial-product
reduction: compressors do not finish the addition; they reshape many aligned
rows into two aligned rows with the same numeric value.

```mermaid
flowchart LR
  classDef in fill:#fff,stroke:#111,stroke-width:1.2px,color:#111;
  classDef comp fill:#f8f8f8,stroke:#111,stroke-width:1.6px,color:#111;
  classDef out fill:#fff,stroke:#111,stroke-width:1.6px,color:#111;
  classDef note fill:#f8f8f8,stroke:#333,stroke-width:1.2px,stroke-dasharray:5 4,color:#111;

  subgraph IN["16 input rows / partial products"]
    direction TB
    A0["A0"]:::in
    A1["A1"]:::in
    A2["A2"]:::in
    A3["A3"]:::in
    A4["A4"]:::in
    A5["A5"]:::in
    A6["A6"]:::in
    A7["A7"]:::in
    A8["A8"]:::in
    A9["A9"]:::in
    A10["A10"]:::in
    A11["A11"]:::in
    A12["A12"]:::in
    A13["A13"]:::in
    A14["A14"]:::in
    A15["A15"]:::in
  end

  subgraph L1["Level 1: 16 rows -> 8 rows"]
    direction TB
    C0["4-2 compressor<br/>C0: A0..A3"]:::comp
    C1["4-2 compressor<br/>C1: A4..A7"]:::comp
    C2["4-2 compressor<br/>C2: A8..A11"]:::comp
    C3["4-2 compressor<br/>C3: A12..A15"]:::comp
  end

  subgraph L2["Level 2: 8 rows -> 4 rows"]
    direction TB
    C4["4-2 compressor<br/>C4"]:::comp
    C5["4-2 compressor<br/>C5"]:::comp
  end

  subgraph L3["Level 3: 4 rows -> 2 rows"]
    direction TB
    C6["4-2 compressor<br/>C6"]:::comp
  end

  B1["B1: final sum row"]:::out
  B2["B2: final carry row << 1"]:::out
  EQ["Σ A0..A15 = B1 + B2"]:::note

  A0 --> C0
  A1 --> C0
  A2 --> C0
  A3 --> C0

  A4 --> C1
  A5 --> C1
  A6 --> C1
  A7 --> C1

  A8 --> C2
  A9 --> C2
  A10 --> C2
  A11 --> C2

  A12 --> C3
  A13 --> C3
  A14 --> C3
  A15 --> C3

  C0 -->|"sum0"| C4
  C0 -->|"carry0"| C4
  C1 -->|"sum1"| C4
  C1 -->|"carry1"| C4

  C2 -->|"sum2"| C5
  C2 -->|"carry2"| C5
  C3 -->|"sum3"| C5
  C3 -->|"carry3"| C5

  C4 -->|"sum4"| C6
  C4 -->|"carry4"| C6
  C5 -->|"sum5"| C6
  C5 -->|"carry5"| C6

  C6 --> B1
  C6 --> B2
  B1 -.-> EQ
  B2 -.-> EQ
```

Here `B1` is the final sum row and `B2` is the final carry row after its
one-bit weight shift. A final carry-propagate adder can later compute
`B1 + B2`, but the compressor tree itself is only responsible for preserving
`sum(A0..A15)` while reducing sixteen rows to two rows.

The code in `fpu_compressor_4_2` writes this directly as Boolean compressor
logic rather than instantiating two `fpu_compressor_3_2` submodules. The shape
is still the same conceptual evolution: 3-2 full-adder compression, then a
five-input form that becomes a practical 4-2 compressor when `cout` is chained
between columns.
