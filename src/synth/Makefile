SHELL=/bin/bash -o pipefail
.SHELLFLAGS += -e

export PKG_SRCS =
# export HDL_SRCS = $(shell find $(PWD)/../hdl -name '*.sv')
HDL_SRCS ?= $(firstword $(HDL_SRCS))
export SRAM_LIB =
DESIGN_TOP = $(firstword $(DESIGN_TOP))
VER_FLAGS= -Wall --timescale 1ps/1ps  -Mdir build -O3 -CFLAGS "-Ofast -march=native" --cc verilator_warn.vlt

#choose between the following options for the standard cell library

# export STD_CELL_LIB=/usr/local/share/qflow/tech/osu018/osu018.lib
# export STD_CELL_LIB=/usr/local/share/qflow/tech/gscl45nm/gscl45nm.lib
# export STD_CELL_LIB=/usr/local/share/qflow/tech/osu018/osu018_stdcells.lib
export STD_CELL_LIB=/usr/local/share/qflow/tech/osu035_redm4/osu035_stdcells.lib
# export STD_CELL_LIB=/usr/local/share/qflow/tech/osu050/osu05_stdcells.lib
# export STD_CELL_ALIB=/usr/local/share/qflow/tech/gscl45nm/alib

.PHONY: synth
synth: clean
	$(MAKE) outputs/synth.ddc

outputs/synth.ddc:
	mkdir -p reports outputs
	export ECE411_MIN_POWER=0 ;\
	export ECE411_COMPILE_CMD=compile ;\
	export ECE411_DC_CORES=4 ;\
	(verilator --lint-only -Wno-fatal -Wwarn-style -Wwarn-lint +define+ECE411_VER_DUMP +define+ECE411_FST_DUMP $(VER_FLAGS) $(HDL_SRCS) --top-module $(DESIGN_TOP) || true ) |& tee reports/lint.log 
	echo "read_verilog -sv $(HDL_SRCS)" > synth.ys
	echo -e "read_liberty -lib -ignore_miss_dir -setattr blackbox $(STD_CELL_LIB)\nsetattr -unset keep\nproc; check -assert -force-detailed-loop-check -initdrv -noinit" >> synth.ys
	echo -e "synth -top $(DESIGN_TOP) \ndfflibmap -liberty $(STD_CELL_LIB) \nopt\nabc -exe /usr/local/share/qflow/bin/yosys-abc -liberty $(STD_CELL_LIB) -script +strash;scorr;ifraig;retime,{D};strash;dch,-f;map,-M,1,{D} \nflatten\nsetundef -zero \nclean -purge \niopadmap -outpad BUFX2 A:Y -bits \nopt \nclean \nrename -enumerate \nwrite_verilog  mapped.v \nstat -liberty $(STD_CELL_LIB)" >> synth.ys
	# echo "synth -top $(DESIGN_TOP)" >> synth.ys
	yosys -s synth.ys |& tee reports/synthesis.log
	echo -e "read_liberty $(STD_CELL_LIB)\nread_verilog mapped.v\nlink_design $(DESIGN_TOP)\ncreate_clock -name clk -period 10 [get_ports clk]\nset_input_delay 1 -clock clk [all_inputs]\nset_output_delay 1 -clock clk [all_outputs]\nset_load 0.1 [all_outputs]\nset_max_fanout 1 [all_inputs]\nset_power_activity -input -activity 0.1\nset_power_activity -input_port reset -activity 0\nreport_power\nreport_checks -path_delay min_max -digits 3 -fields {slew arrival slack} -group_path_count 10 > reports/timing.rpt" > sta.tcl
	sta -exit sta.tcl |& tee reports/sta.log
	rm -f  *.log
	rm -f  default.svf
	rm -rf work
	rm -rf mapped.v
	rm -rf synth.ys
	rm -rf sta.tcl
	# bash check_synth_error.sh

.PHONY: dv
dv:
	timeout $(ECE411_GUI_TIMEOUT) design_vision -f dv.tcl

.PHONY: clean
clean:
	rm -f  *.log
	rm -f  default.svf
	rm -rf work
	rm -rf reports
	rm -rf outputs
	rm -rf mapped.v
	rm -rf synth.ys
	rm -rf sta.tcl

