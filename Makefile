# ============================================================================
# FPU_PROJECT - top-level Makefile
# ============================================================================

TB_DIR := sim/tb

.PHONY: all compile run verdi verdi_sch clean rerun lop recip_seed_lut mult_trig mult_trig_verdi mult_trig_rerun convert convert_pipe convert_verdi convert_rerun add add_pipe add_verdi add_rerun mult mult_pipe mult_pipe_common mult_verdi mult_rerun fma fma_pipe fma_verdi fma_rerun sgnj sgnj_verdi sgnj_rerun compare compare_pipe compare_verdi compare_rerun tree

all:
	$(MAKE) -C $(TB_DIR) all

compile:
	$(MAKE) -C $(TB_DIR) compile

run:
	$(MAKE) -C $(TB_DIR) run

verdi:
	$(MAKE) -C $(TB_DIR) verdi

verdi_sch:
	$(MAKE) -C $(TB_DIR) verdi_sch

clean:
	$(MAKE) -C $(TB_DIR) clean

rerun:
	$(MAKE) -C $(TB_DIR) rerun

lop:
	$(MAKE) -C $(TB_DIR) lop

recip_seed_lut:
	$(MAKE) -C $(TB_DIR) recip_seed_lut

mult_trig:
	$(MAKE) -C $(TB_DIR) mult_trig

mult_trig_verdi:
	$(MAKE) -C $(TB_DIR) mult_trig_verdi

mult_trig_rerun:
	$(MAKE) -C $(TB_DIR) mult_trig_rerun

convert:
	$(MAKE) -C $(TB_DIR) convert

convert_pipe:
	$(MAKE) -C $(TB_DIR) convert_pipe

convert_verdi:
	$(MAKE) -C $(TB_DIR) convert_verdi

convert_rerun:
	$(MAKE) -C $(TB_DIR) convert_rerun

add:
	$(MAKE) -C $(TB_DIR) add

add_pipe:
	$(MAKE) -C $(TB_DIR) add_pipe

add_verdi:
	$(MAKE) -C $(TB_DIR) add_verdi

add_rerun:
	$(MAKE) -C $(TB_DIR) add_rerun

mult:
	$(MAKE) -C $(TB_DIR) mult

mult_pipe:
	$(MAKE) -C $(TB_DIR) mult_pipe

mult_pipe_common:
	$(MAKE) -C $(TB_DIR) mult_pipe_common

mult_verdi:
	$(MAKE) -C $(TB_DIR) mult_verdi

mult_rerun:
	$(MAKE) -C $(TB_DIR) mult_rerun

fma:
	$(MAKE) -C $(TB_DIR) fma

fma_pipe:
	$(MAKE) -C $(TB_DIR) fma_pipe

fma_verdi:
	$(MAKE) -C $(TB_DIR) fma_verdi

fma_rerun:
	$(MAKE) -C $(TB_DIR) fma_rerun

sgnj:
	$(MAKE) -C $(TB_DIR) sgnj

sgnj_verdi:
	$(MAKE) -C $(TB_DIR) sgnj_verdi

sgnj_rerun:
	$(MAKE) -C $(TB_DIR) sgnj_rerun

compare:
	$(MAKE) -C $(TB_DIR) compare

compare_pipe:
	$(MAKE) -C $(TB_DIR) compare_pipe

compare_verdi:
	$(MAKE) -C $(TB_DIR) compare_verdi

compare_rerun:
	$(MAKE) -C $(TB_DIR) compare_rerun

tree:
	@find . -path './.git' -prune -o -path './.agents' -prune -o -print
