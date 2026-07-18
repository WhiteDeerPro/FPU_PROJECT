# FPU testbenches

This directory contains the current VCS/Verdi test setup.
Generated simulation files are written to `sim/01`.

## Files

```text
tb_fpu_lop.sv       self-checking testbench
tb_fpu_convert.sv   convert unit self-checking testbench
tb_fpu_add.sv       add/sub unit self-checking testbench
tb_fpu_mult.sv      multiply unit self-checking testbench
tb_fpu_fma.sv       fused multiply-add unit self-checking testbench
tb_fpu_fma_pipe.sv  pipelined FMA unit self-checking testbench
tb_fpu_sgnj.sv      sign-injection unit self-checking testbench
tb_fpu_compare.sv   compare/min/max/class unit self-checking testbench
tb_fpu_top.sv       integrated fpu_top mixed-operation smoke testbench
tb_fpu_top_multi.sv 4-lane issue, OOO return, FIFO wrap, and backpressure testbench
tb_fpu_virtual_core.sv ROB/scoreboard, precise commit, and flush testbench
tb_fpu_cvxif_wrapper.sv split/coupled CV-X-IF smoke testbenches
tb_fpu_cvxif_wrapper_multi.sv four-port shared-backend CV-X-IF testbench
tb_fpu_mult_trig.sv multiplier sine-square stimulus testbench
tb_fpu_cvxif_mult_burst.sv CV-X-IF FMUL.D cos(x)*cos(x) no-bubble burst testbench
fpu_lop_vcs.f       VCS/Verdi filelist
fpu_convert_vcs.f   convert unit VCS/Verdi filelist
fpu_add_vcs.f       add/sub unit VCS/Verdi filelist
fpu_mult_vcs.f      multiply unit VCS/Verdi filelist
fpu_fma_vcs.f       fused multiply-add unit VCS/Verdi filelist
fpu_fma_pipe_vcs.f  pipelined FMA unit VCS/Verdi filelist
fpu_sgnj_vcs.f      sign-injection unit VCS/Verdi filelist
fpu_compare_vcs.f   compare/min/max/class unit VCS/Verdi filelist
fpu_top_vcs.f       integrated fpu_top VCS/Verdi filelist
fpu_top_multi_vcs.f multi-issue fpu_top VCS/Verdi filelist
fpu_virtual_core_vcs.f virtual-core VCS/Verdi filelist
fpu_cvxif_wrapper_vcs.f CV-X-IF wrapper VCS/Verdi filelist
fpu_mult_trig_vcs.f multiplier sine-square VCS/Verdi filelist
fpu_cvxif_mult_burst_vcs.f CV-X-IF FMUL.D burst VCS/Verdi filelist
Makefile            compile, run, waveform, and schematic targets
```

## Commands

From this directory:

```bash
make compile
make run
make verdi
make verdi_sch
make rerun
make lop
make mult_trig
make mult_trig_verdi
make cvxif_mult_burst
make cvxif_mult_burst_verdi
make cvxif_mult_burst_verdi_sch
make convert
make convert_verdi
make add
make add_verdi
make mult
make mult_verdi
make fma
make fma_pipe
make fma_verdi
make sgnj
make sgnj_verdi
make compare
make compare_verdi
make top
make top_verdi
make top_multi
make top_multi_verdi
make virtual_core
make cvxif
make cvxif_multi
make cvxif_coupled
make clean
```

From the project root, use the same targets through the top-level Makefile.
