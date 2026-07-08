# FPU_PROJECT

This repository is the local source tree for the FPU RTL experiments.

## Directory layout

```text
FPU_PROJECT/
  rtl/
    pkg/        shared SystemVerilog packages
    common/     reusable RTL blocks, such as fpu_lop
    units/      FPU functional units
    filelist.f  RTL compile-order filelist
  sim/
    tb/         testbenches, VCS filelists, and simulation Makefile
  docs/         design notes
  Makefile      top-level shortcut Makefile
```

## Local workflow

From the project root:

```bash
make compile
make run
make verdi
make verdi_sch
make rerun
make lop
make convert
make convert_verdi
make add
make add_verdi
make sgnj
make sgnj_verdi
make compare
make compare_verdi
make clean
```

The top-level Makefile delegates to `sim/tb/Makefile`.
Simulation outputs are written under `sim/01`, keeping `sim/tb` source-only.

## Design notes

- `docs/fpu_arch.md` records the top-level integration boundary, CSR/flush
  expectations, and throughput-scaling notes.
- `docs/fpu_top_integration_plan.md` records the planned top-level CSR,
  response FIFO, flush, and vector/multi-issue integration work.
- `docs/fpu_unit_flow.md` records unit datapath flow diagrams for code reading.

FDIV/FSQRT now use constrained exactness vectors (`N*K/K` and `sqrt(k^2)`) to
cover residual-correction edges. The iterative datapaths run enough Newton
rounds for candidate precision, then use an integer-domain residual exactness
check to clear false `NX/UF` and repair exact one-ulp-neighbor candidates.

## Authors

- WhiteDeerPro <1207707136@qq.com>
- 10kyfu <2194438514@qq.com>
- strive2021 <xiligongda@outlook.com>

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).

## VM workspace workflow

Keep the VM project on a normal writable disk path, for example:

```bash
~/workspace/FPU_PROJECT
```

Avoid running VCS or Verdi directly inside an FTP-mounted directory. VCS and Verdi create files such as `simv`, `csrc/`, `*.log`, `*.fsdb`, `novas.*`, and `verdiLog/`; FTP servers often reject those writes with `550`.

Recommended VM commands:

```bash
cd ~/workspace/FPU_PROJECT
make rerun
make verdi_sch
```
