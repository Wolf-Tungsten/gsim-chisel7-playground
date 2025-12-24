ENV_SETUP = . ./env.sh &&
RC_MAKE   = $(ENV_SETUP) CCACHE_DISABLE=1 $(MAKE) -C rocket-chip
GSIM_MAKE = $(ENV_SETUP) $(MAKE) -C gsim
REF      ?= Spike
TEST_IMAGE ?= $(abspath ./riscv-arch-test/riscv-test-suite/build/I-add-01.bin)

.PHONY: build-verilator-emu build-gsim-emu run-verilator-emu run-gsim-emu gsim-build clean

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

clean:
	@$(RC_MAKE) clean
	@$(GSIM_MAKE) clean
