SHELL := /bin/bash

ENV_SETUP = . ./env.sh &&
RC_MAKE   = $(ENV_SETUP) CCACHE_DISABLE=1 $(MAKE) -C rocket-chip
GSIM_MAKE = $(ENV_SETUP) $(MAKE) -C gsim
REF      ?= Spike
TEST_IMAGE ?= $(abspath ./riscv-arch-test/riscv-test-suite/build/I-add-01.bin)
RISCV_TEST_BUILD_DIR ?= $(abspath ./riscv-arch-test/riscv-test-suite/build)
RISCV_TEST_BINS := $(shell find $(RISCV_TEST_BUILD_DIR) -name '*.bin' -type f | sort)

.PHONY: build-verilator-emu build-gsim-emu run-verilator-emu run-gsim-emu run-compare-logs run-batch-compare gsim-build run-xs-gsim clean

gsim-build:
	@$(GSIM_MAKE) build-gsim

build-verilator-emu:
	@$(RC_MAKE) REF=$(REF) GSIM=0 emu

build-gsim-emu:
	@$(RC_MAKE) REF=$(REF) GSIM=1 gsim-emu

run-verilator-emu: gsim-build build-verilator-emu
	@$(ENV_SETUP) ./rocket-chip/build/emu -i $(TEST_IMAGE)

run-gsim-emu: gsim-build build-gsim-emu
	@$(ENV_SETUP) ./rocket-chip/build/gsim-compile/emu -i $(TEST_IMAGE)

run-compare-logs: gsim-build build-gsim-emu build-verilator-emu
	@mkdir -p tmp-out
	@$(ENV_SETUP) ./rocket-chip/build/emu -i $(TEST_IMAGE) > tmp-out/verilator.log 2>&1 || true
	@$(ENV_SETUP) ./rocket-chip/build/gsim-compile/emu -i $(TEST_IMAGE) > tmp-out/gsim.log 2>&1 || true
	@echo "Logs written to tmp-out/verilator.log and tmp-out/gsim.log"

run-batch-compare: gsim-build build-gsim-emu build-verilator-emu
	@mkdir -p tmp-out/batch-compare/verilator tmp-out/batch-compare/gsim
	@set -euo pipefail; \
	BINS="$(RISCV_TEST_BINS)"; \
	if [ -z "$$BINS" ]; then \
		echo "No binaries found in $(RISCV_TEST_BUILD_DIR)"; \
		exit 1; \
	fi; \
	for bin in $$BINS; do \
		base=$$(basename $$bin .bin); \
		echo "Running verilator for $$bin"; \
		$(ENV_SETUP) ./rocket-chip/build/emu -i $$bin > tmp-out/batch-compare/verilator/$${base}.log 2>&1 || true; \
		echo "Running gsim for $$bin"; \
		$(ENV_SETUP) ./rocket-chip/build/gsim-compile/emu -i $$bin > tmp-out/batch-compare/gsim/$${base}.log 2>&1 || true; \
	done; \
	echo "Batch compare logs stored under tmp-out/batch-compare"

run-xs-gsim: gsim-build
	@$(ENV_SETUP) NOOP_HOME=/workspace/gsim-chisel7-playground/XiangShan $(MAKE) -C XiangShan gsim-run GSIM=1 -j 30

clean:
	@$(RC_MAKE) clean
	@$(GSIM_MAKE) clean
