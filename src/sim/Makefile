SHELL=/bin/bash -o pipefail
.SHELLFLAGS += -e

HDL_SRCS ?= $(firstword $(HDL_SRCS))

DESIGN_TOP = $(firstword $(DESIGN_TOP))

TIMEOUT   ?= 10000000
VER_FLAGS= -Wall --timescale 1ps/1ps  -Mdir build -O3 -CFLAGS "-Ofast -march=native" --cc verilator_warn.vlt


# verilator/build/Vtop_tb: $(VER_SRCS) $(HDRS) $(VER_EX)
# 	mkdir -p verilator
# 	python3 check_sus.py
# 	../bin/rvfi_reference.py
# 	cd verilator ;\
# 	verilator -trace-fst +define+ECE411_VER_DUMP +define+ECE411_FST_DUMP $(VER_FLAGS) $(VER_SRCS) --top-module top_tb --exe $(VER_EX)
# 	cd verilator/build ;\
# 	$(MAKE) --jobs=$(shell echo $(shell nproc)-2 | bc) -f Vtop_tb.mk

# .PHONY: run_verilator_top_tb
# run_verilator_top_tb: verilator/build/Vtop_tb $(PROG)
# 	mkdir -p spike
# 	find ./verilator -maxdepth 1 -type f -delete
# 	../bin/generate_memory_file.py -32 $(PROG)
# 	python3 $(PWD)/../bin/get_options.py clock
# 	python3 $(PWD)/../bin/get_options.py bmem_x
# 	cd verilator && ./build/Vtop_tb \
# 		+TIMEOUT_ECE411=$(TIMEOUT) \
# 		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock) \
# 		+BRAM_0_ON_X_ECE411=$(shell python3 $(PWD)/../bin/get_options.py bmem_x) \
# 		+MEMLST_ECE411="$(PWD)/bin/memory_32.lst"

.PHONY: lint
lint: $(HDL_SRCS) $(HDRS)
	mkdir -p verilator
	# python3 check_sus.py
	# ../bin/rvfi_reference.py
	cd verilator ;\
	verilator --lint-only +define+ECE411_VER_DUMP +define+ECE411_FST_DUMP $(VER_FLAGS) $(HDL_SRCS) --top-module $(DESIGN_TOP)
	# svlint $(HDL_SRCS)


.PHONY: clean
clean:
	rm -rf bin vcs verdi verilator spike
