ENV_SETUP = . ./env.sh &&
RC_MAKE   = $(ENV_SETUP) $(MAKE) -C rocket-chip
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

clean:
	@$(RC_MAKE) clean
	@$(GSIM_MAKE) clean
