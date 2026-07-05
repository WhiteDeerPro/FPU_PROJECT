#!/usr/bin/env bash
set -euo pipefail

verdi_pli_args=()
dump_define=()
if [[ -n "${VERDI_HOME:-}" ]]; then
  verdi_pli_args=(
    -P "${VERDI_HOME}/share/PLI/VCS/LINUX64/novas.tab"
       "${VERDI_HOME}/share/PLI/VCS/LINUX64/pli.a"
  )
  dump_define=(+define+DUMP_FSDB)
fi

vcs -full64 -sverilog -debug_access+all -kdb -lca \
  "${dump_define[@]}" \
  -timescale=1ns/1ps \
  -f fpu_lop_vcs.f \
  -top tb_fpu_lop \
  "${verdi_pli_args[@]}" \
  -l comp.log

./simv -l run.log
