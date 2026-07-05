// RTL compile order.
// Packages must be compiled before modules that import them.

rtl/pkg/fpu_pkg.sv

rtl/common/fpu_barrel_shifter.sv
rtl/common/fpu_grs.sv
rtl/common/fpu_round_inc.sv
rtl/common/fpu_lop.sv
rtl/common/fpu_lop_v2.sv
rtl/common/fpu_booth_radix4_compressor.sv
rtl/common/fpu_compressors.sv
rtl/common/fpu_mult.sv
rtl/common/fpu_mult_pipe.sv
rtl/common/fpu_recip_seed_lut.sv

rtl/units/fpu_convert_unit.sv
rtl/units/fpu_add_unit.sv
rtl/units/fpu_mult_unit.sv
rtl/units/fpu_fma_unit.sv
rtl/units/fpu_sgnj_unit.sv
rtl/units/fpu_compare_unit.sv

rtl/units_pipe/fpu_add_unit_pipe.sv
rtl/units_pipe/fpu_convert_unit_pipe.sv
rtl/units_pipe/fpu_mult_unit_pipe.sv
rtl/units_pipe/fpu_fma_unit_pipe.sv
rtl/units_pipe/fpu_div_unit_pipe.sv
rtl/units_pipe/fpu_compare_unit_pipe.sv

// Future modules:
// rtl/core/fpu_top.sv
