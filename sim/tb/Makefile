# ============================================================================
# FPU testbench - VCS Makefile
# ============================================================================

# --- Environment -------------------------------------------------------------
ifndef VCS_HOME
VCS_HOME := /opt/synopsys/vcs
endif

# --- Files and arguments -----------------------------------------------------
FLIST      ?= fpu_lop_vcs.f
TOP        ?= tb_fpu_lop
FSDB_FILE  ?= tb_fpu_lop.fsdb
SIMV       ?= simv
WORK_DIR   ?= ../01
MAX_CYCLES ?= 50000

# VCS compile options
VCS_FLAGS := -sverilog \
             -debug_access+all \
             -debug_region+cell+encrypt \
             -lca -kdb \
             -full64 \
             -timescale=1ns/1ps \
             -verdi \
             +define+DUMP_FSDB \
             -LDFLAGS -Wl,--no-as-needed

# Simulation runtime options
SIM_FLAGS := +fsdb+autoflush +fsdb+all +fsdb+struct +fsdb+mda +max_cycles=$(MAX_CYCLES)

# --- Targets ----------------------------------------------------------------
.PHONY: all compile run verdi verdi_sch clean rerun lop recip_seed_lut mult_trig mult_trig_verdi mult_trig_rerun convert convert_pipe convert_verdi convert_rerun add add_pipe add_verdi add_rerun mult mult_cases mult_pipe mult_pipe_common mult_verdi mult_rerun fma fma_cases fma_pipe fma_verdi fma_rerun div_cases div_pipe div_verdi div_rerun sqrt_cases sqrt_pipe sqrt_verdi sqrt_rerun top_compile sgnj sgnj_verdi sgnj_rerun compare compare_pipe compare_verdi compare_rerun

all: clean compile run

compile: $(FLIST)
	mkdir -p $(WORK_DIR)
	cd $(WORK_DIR) && vcs $(VCS_FLAGS) -f ../tb/$(FLIST) -top $(TOP) -l compile.log

run:
	@if [ ! -f $(WORK_DIR)/$(SIMV) ]; then \
		echo "Error: $(WORK_DIR)/$(SIMV) not found. Run 'make compile' first."; \
		exit 1; \
	fi
	cd $(WORK_DIR) && ./$(SIMV) $(SIM_FLAGS) -l sim.log

verdi:
	@if [ ! -f $(WORK_DIR)/$(FSDB_FILE) ]; then \
		echo "Error: $(WORK_DIR)/$(FSDB_FILE) not found. Run 'make run' first."; \
		exit 1; \
	fi
	cd $(WORK_DIR) && verdi -sv -f ../tb/$(FLIST) -top $(TOP) -ssf $(FSDB_FILE) &

verdi_sch:
	mkdir -p $(WORK_DIR)
	cd $(WORK_DIR) && verdi -sv -f ../tb/$(FLIST) -top $(TOP) &

clean:
	rm -rf $(WORK_DIR)/simv* $(WORK_DIR)/csrc* $(WORK_DIR)/*.log \
	       $(WORK_DIR)/*.key $(WORK_DIR)/*.vpd $(WORK_DIR)/*.vdb \
	       $(WORK_DIR)/*.fsdb $(WORK_DIR)/verdiLog $(WORK_DIR)/novas.* \
	       $(WORK_DIR)/ucli.key

rerun: clean compile run verdi

lop:
	$(MAKE) rerun FLIST=fpu_lop_vcs.f TOP=tb_fpu_lop FSDB_FILE=tb_fpu_lop.fsdb

recip_seed_lut:
	$(MAKE) rerun FLIST=fpu_recip_seed_lut_vcs.f TOP=tb_fpu_recip_seed_lut FSDB_FILE=tb_fpu_recip_seed_lut.fsdb

mult_trig:
	$(MAKE) rerun FLIST=fpu_mult_trig_vcs.f TOP=tb_fpu_mult_trig FSDB_FILE=tb_fpu_mult_trig.fsdb

mult_trig_verdi:
	$(MAKE) verdi FLIST=fpu_mult_trig_vcs.f TOP=tb_fpu_mult_trig FSDB_FILE=tb_fpu_mult_trig.fsdb

mult_trig_rerun: mult_trig

convert:
	$(MAKE) rerun FLIST=fpu_convert_vcs.f TOP=tb_fpu_convert FSDB_FILE=tb_fpu_convert.fsdb

convert_pipe:
	$(MAKE) rerun FLIST=fpu_convert_pipe_vcs.f TOP=tb_fpu_convert_pipe FSDB_FILE=tb_fpu_convert_pipe.fsdb

convert_verdi:
	$(MAKE) verdi FLIST=fpu_convert_vcs.f TOP=tb_fpu_convert FSDB_FILE=tb_fpu_convert.fsdb

convert_rerun: convert

add:
	$(MAKE) rerun FLIST=fpu_add_vcs.f TOP=tb_fpu_add FSDB_FILE=tb_fpu_add.fsdb

add_pipe:
	$(MAKE) rerun FLIST=fpu_add_pipe_vcs.f TOP=tb_fpu_add_pipe FSDB_FILE=tb_fpu_add_pipe.fsdb

add_verdi:
	$(MAKE) verdi FLIST=fpu_add_vcs.f TOP=tb_fpu_add FSDB_FILE=tb_fpu_add.fsdb

add_rerun: add

mult:
	$(MAKE) rerun FLIST=fpu_mult_vcs.f TOP=tb_fpu_mult FSDB_FILE=tb_fpu_mult.fsdb

mult_cases:
	python3 gen_fpu_mult_random_cases.py

mult_pipe: mult_cases
	$(MAKE) rerun FLIST=fpu_mult_pipe_vcs.f TOP=tb_fpu_mult_pipe FSDB_FILE=tb_fpu_mult_pipe.fsdb

mult_pipe_common:
	$(MAKE) rerun FLIST=fpu_mult_pipe_common_vcs.f TOP=tb_fpu_mult_pipe_common FSDB_FILE=tb_fpu_mult_pipe_common.fsdb

mult_verdi:
	$(MAKE) verdi FLIST=fpu_mult_vcs.f TOP=tb_fpu_mult FSDB_FILE=tb_fpu_mult.fsdb

mult_rerun: mult

fma:
	$(MAKE) rerun FLIST=fpu_fma_vcs.f TOP=tb_fpu_fma FSDB_FILE=tb_fpu_fma.fsdb

fma_pipe: fma_cases
	$(MAKE) rerun FLIST=fpu_fma_pipe_vcs.f TOP=tb_fpu_fma_pipe FSDB_FILE=tb_fpu_fma_pipe.fsdb

fma_verdi:
	$(MAKE) verdi FLIST=fpu_fma_vcs.f TOP=tb_fpu_fma FSDB_FILE=tb_fpu_fma.fsdb

fma_rerun: fma

fma_cases:
	python3 gen_fpu_fma_random_cases.py

div_pipe: div_cases
	$(MAKE) rerun FLIST=fpu_div_pipe_vcs.f TOP=tb_fpu_div_pipe FSDB_FILE=tb_fpu_div_pipe.fsdb MAX_CYCLES=200000

div_verdi:
	$(MAKE) verdi FLIST=fpu_div_pipe_vcs.f TOP=tb_fpu_div_pipe FSDB_FILE=tb_fpu_div_pipe.fsdb

div_rerun: div_pipe

sqrt_cases:
	python3 gen_fpu_sqrt_random_cases.py

sqrt_pipe: sqrt_cases
	$(MAKE) rerun FLIST=fpu_sqrt_pipe_vcs.f TOP=tb_fpu_sqrt_pipe FSDB_FILE=tb_fpu_sqrt_pipe.fsdb MAX_CYCLES=50000

sqrt_verdi:
	$(MAKE) verdi FLIST=fpu_sqrt_pipe_vcs.f TOP=tb_fpu_sqrt_pipe FSDB_FILE=tb_fpu_sqrt_pipe.fsdb

sqrt_rerun: sqrt_pipe

top_compile:
	$(MAKE) clean compile FLIST=fpu_top_vcs.f TOP=fpu_top

sgnj:
	$(MAKE) rerun FLIST=fpu_sgnj_vcs.f TOP=tb_fpu_sgnj FSDB_FILE=tb_fpu_sgnj.fsdb

sgnj_verdi:
	$(MAKE) verdi FLIST=fpu_sgnj_vcs.f TOP=tb_fpu_sgnj FSDB_FILE=tb_fpu_sgnj.fsdb

sgnj_rerun: sgnj

compare:
	$(MAKE) rerun FLIST=fpu_compare_vcs.f TOP=tb_fpu_compare FSDB_FILE=tb_fpu_compare.fsdb

compare_pipe:
	$(MAKE) rerun FLIST=fpu_compare_pipe_vcs.f TOP=tb_fpu_compare_pipe FSDB_FILE=tb_fpu_compare_pipe.fsdb

compare_verdi:
	$(MAKE) verdi FLIST=fpu_compare_vcs.f TOP=tb_fpu_compare FSDB_FILE=tb_fpu_compare.fsdb

compare_rerun: compare
div_cases:
	python3 gen_fpu_div_random_cases.py
