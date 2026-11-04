# ============================================================================
# Makefile -- run targets for QuestaSim / Questa Formal Verification
# (Siemens EDA). Builds the rtl/tb/formal sources with vlib/vlog/vopt/vsim
# and adds a real formal-proof flow via `qverify'.
#
# Run every target from the repo root: the file lists (rtl/rtl.f, tb/tb.f,
# formal/formal.f) hold repo-root-relative paths, and every tool output goes
# to build/ (see "Outputs" below). `make clean` removes build/.
#
# Local checks, no Questa needed (verilator and slang on PATH):
#   make check      BEFORE EVERY COMMIT: lint, then the Verilator smoke test
#                   at both data widths. Stops at the first failure.
#   make lint       verilator --lint-only -Wall on the RTL (both widths), and
#                   slang over the RTL + formal/ (both widths, with and
#                   without QUESTA_FORMAL)
#   make smoke      tb_simple.sv under Verilator, DATA_WIDTH=32|64
#
# Requires vlib/vlog/vopt/vsim/qverify on PATH (source Questa's setup
# script first, e.g. add .../questasim/linux_x86_64 and
# .../questa_static_formal/linux_x86_64/bin to PATH) and a valid license
# (LM_LICENSE_FILE).
#
# TEST defaults to the smoke test; override on the command line, e.g.:
#   make uvm TEST=axi4lite_random_test
#
# `uvm-sweep` builds TEST once and runs seeds 1..N (default 20) against it,
# reporting which (if any) failed by parsing each run's UVM report summary
# (UVM_ERROR/UVM_FATAL counts) -- much cheaper than N full rebuilds:
#   make uvm-sweep TEST=axi4lite_random_test N=20
#
# `formal` runs the formal/ assume/assert/cover environment (flow #2 in
# formal_tb.sv's header comment) under vsim -- bounded, randomly-driven
# simulation, not exhaustive formal proof. SEED controls
# axi4lite_formal_driver.sv's randomization for reproducibility:
#   make formal SEED=123
# `formal-sweep` builds once and sweeps seeds 1..N, same idea as uvm-sweep:
#   make formal-sweep N=20
#
# `formal-verify` drives Questa's real formal-proof engine (`qverify`) over
# the same formal/ SVA files via formal/run_formal.tcl, exhaustive property
# proof, not simulation.
#   make formal-verify                        # 32-bit (DATA_WIDTH default)
#   make formal-verify DATA_WIDTH=64          # 64-bit
#   make formal-verify-all                    # both
#
# DATA_WIDTH (32 or 64, default 32) applies to every target -- UVM,
# simple and formal alike:
#   make uvm TEST=axi4lite_random_test DATA_WIDTH=64
#
# Waveforms: the UVM bench dumps tb_top.vcd only with PLUSARGS=+vcd
# (into build/sim/). For curated GUI waves see sim/wave.do / sim/wave_uvm.do.
#
# Outputs, all under build/ (nothing is written to the repo root):
#   build/modelsim.ini, build/questa_work/, build/formal_work/   libraries
#   build/sim/        vsim runs here (transcript, *.wlf, tr_db.log, tb_top.vcd)
#   build/formal/     qverify -od: logs, *.rpt, formal_report*.txt,
#                     propcheck.db/, .qverify/, qverify_cmds.tcl
#   build/cov/uvm/    uvm-sweep: seed_<n>.ucdb, merged.ucdb, merged_cvg.txt,
#                     merged_code.txt, merge.log
#   build/cov/formal/ formal-coverage scratch (removed at the end of the run)
#   build/smoke_<w>/  Verilator smoke build and log, per data width
# ============================================================================

TEST      ?= axi4lite_smoke_test
SEED      ?= 42
N         ?= 20
PLUSARGS  ?=
# uvm-sweep fails if the functional coverage merged over its passing seeds
# is below COV_GOAL (%). 100 for the random and unaligned-address tests
# (sign-off); the smoke test only reaches part of the model by design, so
# it isn't held to it. One seed isn't expected to close the model alone.
COV_GOAL  ?= $(if $(filter axi4lite_random_test axi4lite_unaligned_test,$(TEST)),100,0)

RTL_F      := rtl/rtl.f
TB_F       := tb/tb.f
FORMAL_F   := formal/formal.f
# The random legal master for flow #2 only; QUESTA_FORMAL compiles it out,
# so it is not in formal.f (which is exactly what qverify compiles).
FORMAL_DRV := formal/axi4lite_formal_driver.sv

BUILD          := build
SIM_DIR        := $(BUILD)/sim
FORMAL_OUT     := $(BUILD)/formal
UVM_COV_DIR    := $(BUILD)/cov/uvm
FORMAL_COV_DIR := $(BUILD)/cov/formal

# If $MODELSIM is set in your shell (some site installs export it globally,
# pointing at the install tree's own modelsim.ini), every vlib/vlog/vmap/vsim
# call ignores a local modelsim.ini and tries to read/write that global one
# instead. Pin it to build/ (absolute, so vsim finds it from build/sim/).
export MODELSIM := $(CURDIR)/$(BUILD)/modelsim.ini

# UVM 1.2 shipped with the QuestaSim on PATH; override QUESTA_UVM_HOME (or
# QUESTA_HOME) for another install. Deliberately not UVM_HOME: a shell may
# export that for another simulator's UVM kit (e.g. 1800.2 for Verilator),
# which must not leak into the Questa build. Checked only by uvm-build, so the
# other targets don't need vsim to be on PATH for make to parse this file.
VSIM_ON_PATH    := $(shell command -v vsim 2>/dev/null)
QUESTA_HOME     ?= $(if $(VSIM_ON_PATH),$(abspath $(dir $(VSIM_ON_PATH))/..))
QUESTA_UVM_HOME ?= $(if $(QUESTA_HOME),$(QUESTA_HOME)/verilog_src/uvm-1.2/src)

VERILATOR ?= verilator
SLANG     ?= slang

VLIB    ?= vlib
VMAP    ?= vmap
VLOG    ?= vlog
VOPT    ?= vopt
VSIM    ?= vsim
VCOVER  ?= vcover
QVERIFY ?= qverify

QUESTA_WORK := $(BUILD)/questa_work

# AXI data width, 32 or 64, for every flow: compiled in as
# +define+AXI4LITE_DATA_WIDTH, read by tb/axi4lite_pkg.sv (UVM),
# tb/tb_simple.sv and formal/formal_tb.sv, each of which passes it to the
# DUT. uvm/simple/formal share questa_work, and every *-build target
# recompiles, so switching width needs no clean.
DATA_WIDTH ?= 32
WIDTH_DEFINE := +define+AXI4LITE_DATA_WIDTH=$(DATA_WIDTH)
UVM_VERBOSITY ?= UVM_LOW

# ============================================================================
# Local checks (Verilator / slang, no Questa). check = lint + smoke at both
# widths, in that order, stopping at the first failure.
# ============================================================================
WIDTHS := 32 64

check:
	$(MAKE) --no-print-directory lint
	$(MAKE) --no-print-directory smoke DATA_WIDTH=32
	$(MAKE) --no-print-directory smoke DATA_WIDTH=64
	@echo "CHECK PASSED: lint, smoke (32- and 64-bit)"

lint: lint-verilator lint-slang

# -Wall on the RTL only. The one deliberate exception, the unused byte-select
# address bits (spec §1), is waived bit-precisely in rtl/axi4lite_slave.vlt,
# outside the RTL, so any other warning (including any other unused address
# bit) is new and fails the target.
lint-verilator:
	@for w in $(WIDTHS); do \
	  echo "verilator --lint-only -Wall, DATA_WIDTH=$$w"; \
	  $(VERILATOR) --lint-only -Wall --top-module axi4lite_slave -GDATA_WIDTH=$$w rtl/axi4lite_slave.vlt -f $(RTL_F) || exit 1; \
	done

# slang over the RTL plus the formal environment, both widths, with and
# without QUESTA_FORMAL (the two compile variants qverify and vsim see).
# --timescale: axi4lite_formal_driver.sv has no `timescale of its own and
# relies on vlog's -timescale, as the Questa targets pass it.
lint-slang:
	@for w in $(WIDTHS); do \
	  echo "slang, DATA_WIDTH=$$w"; \
	  $(SLANG) -q --timescale 1ns/1ps -DAXI4LITE_DATA_WIDTH=$$w \
	      -f $(RTL_F) -f $(FORMAL_F) $(FORMAL_DRV) || exit 1; \
	  echo "slang, DATA_WIDTH=$$w, QUESTA_FORMAL"; \
	  $(SLANG) -q --timescale 1ns/1ps -DAXI4LITE_DATA_WIDTH=$$w -DQUESTA_FORMAL \
	      -f $(RTL_F) -f $(FORMAL_F) || exit 1; \
	done

# tb_simple.sv under Verilator (2-state, so this is a quick local check, not a
# substitute for `make simple` on Questa). Pass/fail from tb_simple's own
# summary line.
SMOKE_DIR = $(BUILD)/smoke_$(DATA_WIDTH)

smoke:
	mkdir -p $(SMOKE_DIR)
	$(VERILATOR) --binary --timing -Wno-fatal -Wno-lint -Wno-style \
	    $(WIDTH_DEFINE) --top-module tb_simple -Mdir $(SMOKE_DIR) \
	    +incdir+tb -f $(RTL_F) tb/tb_simple.sv > $(SMOKE_DIR)/build.log 2>&1 \
	    || { tail -30 $(SMOKE_DIR)/build.log; exit 1; }
	$(SMOKE_DIR)/Vtb_simple | tee $(SMOKE_DIR)/smoke.log
	@grep -q '\*\*\* TEST PASSED \*\*\*' $(SMOKE_DIR)/smoke.log \
	    || { echo "SMOKE FAILED (DATA_WIDTH=$(DATA_WIDTH))"; exit 1; }

# ============================================================================
# Shared library setup -- just vlib+vmap, nothing UVM/test-specific about it.
# Mapped with an absolute path, so vsim resolves it from build/sim/. Also
# re-maps work after formal-verify, which maps it to build/formal_work.
# ============================================================================
lib:
	mkdir -p $(SIM_DIR)
	$(VLIB) $(QUESTA_WORK)
	$(VMAP) work $(CURDIR)/$(QUESTA_WORK)

# ============================================================================
# Plain (non-UVM) simple test -- tb_simple.sv drives axi4lite_slave
# directly, no UVM agent/package involved.
# ============================================================================
simple-build: lib
	$(VLOG) -sv -timescale 1ns/1ps $(WIDTH_DEFINE) \
	     +incdir+tb -f $(RTL_F) tb/tb_simple.sv
	$(VOPT) +acc tb_simple -o tb_simple_opt

simple: simple-build
	cd $(SIM_DIR) && $(VSIM) -c -onfinish exit tb_simple_opt -do "run -all; quit -f"


# ============================================================================
# UVM testbench (tb/) via QuestaSim
# ============================================================================
# Code coverage on the RTL only (statement, branch, condition, expression,
# FSM), not on the UVM library or the testbench: the RTL is compiled in its
# own vlog call with +cover, and vsim -coverage collects it into the same
# UCDB as the covergroups.
CODE_COV ?= bcesf

uvm-home-check:
	@test -n "$(QUESTA_UVM_HOME)" || { echo "uvm-build: vsim is not on PATH; set QUESTA_UVM_HOME (or QUESTA_HOME)"; exit 1; }
	@test -f "$(QUESTA_UVM_HOME)/uvm_pkg.sv" || { echo "uvm-build: $(QUESTA_UVM_HOME)/uvm_pkg.sv not found; set QUESTA_UVM_HOME"; exit 1; }

# The library setup runs from the recipe, after uvm-home-check, rather than
# as a second prerequisite: under make -j sibling prerequisites run in any
# order, and the check must come first so a missing vsim gives its message,
# not a vlib error.
uvm-build: uvm-home-check
	@$(MAKE) --no-print-directory lib
	$(VLOG) -sv -timescale 1ns/1ps $(WIDTH_DEFINE) \
	     +incdir+$(QUESTA_UVM_HOME) +define+UVM_NO_DPI \
	     $(QUESTA_UVM_HOME)/uvm_pkg.sv
	$(VLOG) -sv -timescale 1ns/1ps $(WIDTH_DEFINE) +cover=$(CODE_COV) \
	     -f $(RTL_F)
	$(VLOG) -sv -timescale 1ns/1ps $(WIDTH_DEFINE) \
	     +incdir+$(QUESTA_UVM_HOME) +define+UVM_NO_DPI \
	     +incdir+rtl -f $(TB_F)
	$(VOPT) +acc tb_top -o tb_top_opt

uvm: uvm-build
	cd $(SIM_DIR) && $(VSIM) -c -coverage tb_top_opt +UVM_TESTNAME=$(TEST) -sv_seed $(SEED) \
	     +UVM_VERBOSITY=$(UVM_VERBOSITY) $(PLUSARGS) -onfinish exit -do "run -all; quit -f"

# Each seed saves its coverage to $(UVM_COV_DIR)/seed_<n>.ucdb (same
# -onfinish stop / coverage save pattern as formal-coverage); the passing
# seeds are merged with vcover and the merged covergroup coverage is held to
# COV_GOAL. merged_cvg.txt is kept for finding the bins still at zero.
# Code coverage of the DUT is reported too (merged_code.txt, summary
# printed) but not gated: a code hole needs a reason -- missing stimulus,
# missing plan item, or unreachable code -- before it can be waived.
# vsim runs inside build/sim/, so the UCDB path it saves to is absolute.
uvm-sweep: uvm-build
	@rm -rf $(UVM_COV_DIR); mkdir -p $(UVM_COV_DIR); \
	fail=0; \
	for s in $$(seq 1 $(N)); do \
	  out=$$(cd $(SIM_DIR) && $(VSIM) -c -coverage tb_top_opt +UVM_TESTNAME=$(TEST) -sv_seed $$s \
	         +UVM_VERBOSITY=$(UVM_VERBOSITY) $(PLUSARGS) -onfinish stop \
	         -do "run -all; coverage save $(CURDIR)/$(UVM_COV_DIR)/seed_$$s.ucdb; quit -f" 2>&1); \
	  sfail=0; \
	  errs=$$(echo "$$out" | sed -n 's/^#\{0,1\} *UVM_ERROR :[ \t]*\([0-9][0-9]*\).*/\1/p' | tail -1); \
	  fatals=$$(echo "$$out" | sed -n 's/^#\{0,1\} *UVM_FATAL :[ \t]*\([0-9][0-9]*\).*/\1/p' | tail -1); \
	  cov=$$(echo "$$out" | sed -n 's/.*Overall coverage for [^:]*: *\([0-9.]*\)%.*/\1/p' | tail -1); \
	  if [ -z "$$errs" ] || [ -z "$$fatals" ]; then \
	    echo "seed $$s: FAILED (no UVM report summary found -- crashed or hung?)"; \
	    echo "$$out" | tail -30 | sed 's/^/    /'; \
	    sfail=1; \
	  elif [ "$$errs" -gt 0 ] || [ "$$fatals" -gt 0 ]; then \
	    echo "seed $$s: FAILED (UVM_ERROR=$$errs UVM_FATAL=$$fatals)"; \
	    sfail=1; \
	  else \
	    echo "seed $$s: OK (coverage this seed $${cov:-?}%)"; \
	  fi; \
	  if [ "$$sfail" -ne 0 ]; then fail=1; rm -f $(UVM_COV_DIR)/seed_$$s.ucdb; fi; \
	done; \
	if ls $(UVM_COV_DIR)/seed_*.ucdb > /dev/null 2>&1; then \
	  $(VCOVER) merge $(UVM_COV_DIR)/merged.ucdb $(UVM_COV_DIR)/seed_*.ucdb \
	       > $(UVM_COV_DIR)/merge.log 2>&1; \
	  $(VCOVER) report -cvg -details $(UVM_COV_DIR)/merged.ucdb \
	       > $(UVM_COV_DIR)/merged_cvg.txt 2>&1; \
	  mcov=$$(sed -n 's/.*TOTAL COVERGROUP COVERAGE: *\([0-9.]*\)%.*/\1/p' \
	          $(UVM_COV_DIR)/merged_cvg.txt | tail -1); \
	  if [ -z "$$mcov" ]; then \
	    echo "MERGED COVERAGE: not found in $(UVM_COV_DIR)/merged_cvg.txt (see merge.log)"; \
	    fail=1; \
	  elif awk -v c="$$mcov" -v g="$(COV_GOAL)" 'BEGIN { exit !(c + 0 >= g + 0) }'; then \
	    echo "MERGED COVERAGE: $$mcov% (COV_GOAL=$(COV_GOAL)%)"; \
	  else \
	    echo "MERGED COVERAGE: $$mcov% < COV_GOAL=$(COV_GOAL)% -- bins at zero in $(UVM_COV_DIR)/merged_cvg.txt"; \
	    fail=1; \
	  fi; \
	  $(VCOVER) report -details $(UVM_COV_DIR)/merged.ucdb \
	       > $(UVM_COV_DIR)/merged_code.txt 2>&1; \
	  echo "DUT CODE COVERAGE (merged, not gated; details in $(UVM_COV_DIR)/merged_code.txt):"; \
	  awk '/^=== Instance: / { dut = ($$3 == "/tb_top/dut") } \
	       dut && /^ +(Statements|Branches|Conditions|Expressions|FSM)/ { print "  " $$0 }' \
	      $(UVM_COV_DIR)/merged_code.txt; \
	else \
	  echo "MERGED COVERAGE: no passing seed to merge"; \
	  fail=1; \
	fi; \
	if [ "$$fail" -eq 0 ]; then \
	  echo "ALL $(N) SEEDS PASSED (TEST=$(TEST), merged coverage >= $(COV_GOAL)%)"; \
	else \
	  echo "SWEEP FAILED (TEST=$(TEST))"; \
	  exit 1; \
	fi

# ============================================================================
# Formal assume/assert/cover environment (flow #2: bounded, randomly-driven
# simulation, not exhaustive proof -- see formal_tb.sv's header comment)
# ============================================================================
formal-build: lib
	$(VLOG) -sv -timescale 1ns/1ps $(WIDTH_DEFINE) \
	     -f $(RTL_F) -f $(FORMAL_F) $(FORMAL_DRV)
	$(VOPT) +acc formal_tb -o formal_tb_opt

formal: formal-build
	cd $(SIM_DIR) && $(VSIM) -c -onfinish exit formal_tb_opt -sv_seed $(SEED) -do "run -all; quit -f"

formal-sweep: formal-build
	@fail=0; \
	for s in $$(seq 1 $(N)); do \
	  out=$$(cd $(SIM_DIR) && $(VSIM) -c -onfinish exit formal_tb_opt -sv_seed $$s -do "run -all; quit -f" 2>&1); \
	  if echo "$$out" | grep -qiE '\*\* (Error|Fatal)'; then \
	    echo "seed $$s: FAILED"; \
	    echo "$$out" | grep -iE '\*\* (Error|Fatal)' | sed 's/^/    /'; \
	    fail=1; \
	  else \
	    echo "seed $$s: OK"; \
	  fi; \
	done; \
	if [ "$$fail" -eq 0 ]; then \
	  echo "ALL $(N) SEEDS PASSED"; \
	else \
	  echo "SOME SEEDS FAILED"; \
	  exit 1; \
	fi

# ============================================================================
# formal-coverage: cp_* cover-point reachability across N seeds
# ============================================================================
formal-build-cov: lib
	$(VLOG) -sv -timescale 1ns/1ps $(WIDTH_DEFINE) \
	     -f $(RTL_F) -f $(FORMAL_F) $(FORMAL_DRV)
	$(VOPT) +acc formal_tb -o formal_tb_cov_opt

formal-coverage: formal-build-cov
	@rm -rf $(FORMAL_COV_DIR); mkdir -p $(FORMAL_COV_DIR)
	@for s in $$(seq 1 $(N)); do \
	  (cd $(SIM_DIR) && $(VSIM) -c -onfinish stop formal_tb_cov_opt -sv_seed $$s \
	       -do "run -all; coverage save $(CURDIR)/$(FORMAL_COV_DIR)/seed_$$s.ucdb; quit -f") \
	       > $(FORMAL_COV_DIR)/seed_$$s.log 2>&1; \
	done
	@$(VCOVER) merge $(FORMAL_COV_DIR)/merged.ucdb $(FORMAL_COV_DIR)/seed_*.ucdb > /dev/null
	@echo "=== cp_* cover-point hits across $(N) seeds (axi4lite_covers.sv) ==="
	@$(VCOVER) report -details $(FORMAL_COV_DIR)/merged.ucdb \
	     | awk '/\/formal_tb\/u_covers\/cp_/ { \
	              n=$$0; sub(/^.*\/formal_tb\/u_covers\//,"",n); sub(/[ \t].*/,"",n); \
	              pending=n; next \
	            } \
	            pending!="" && /^[ \t]+[0-9]+[ \t]+[A-Za-z]/ { \
	              line=$$0; sub(/^[ \t]+/,"",line); sub(/[ \t]+$$/,"",line); \
	              n2=split(line,f,/[ \t]+/); h=f[n2-1]; s=f[n2]; \
	              if (!(pending in seen)) { seen[pending]=1; print pending": "h" "s } \
	              pending="" \
	            }'
	@rm -rf $(FORMAL_COV_DIR)

# ============================================================================
# Real Questa Formal Verification (exhaustive property proof, flow #1) via
# `qverify`, driven by formal/run_formal.tcl. Report:
# build/formal/formal_report.txt (32-bit) or formal_report_64.txt.
# ============================================================================
formal-verify:
	mkdir -p $(FORMAL_OUT)
	DATA_WIDTH=$(DATA_WIDTH) $(QVERIFY) -c -od $(FORMAL_OUT) -do formal/run_formal.tcl

# Prove both supported data widths back to back.
formal-verify-all:
	$(MAKE) formal-verify DATA_WIDTH=32
	$(MAKE) formal-verify DATA_WIDTH=64

# Same proof with formal_tb's assumptions compiled out -- any assert that
# no longer proves here depends on the assumptions. Writes
# formal_report[_64]_noassume.txt; the normal report is untouched.
formal-verify-noassume:
	mkdir -p $(FORMAL_OUT)
	DATA_WIDTH=$(DATA_WIDTH) NO_ASSUME=1 $(QVERIFY) -c -od $(FORMAL_OUT) -do formal/run_formal.tcl

.PHONY: check lint lint-verilator lint-slang smoke \
        lib simple-build simple uvm-home-check uvm-build uvm uvm-sweep \
        formal-build formal formal-sweep formal-build-cov formal-coverage \
        formal-verify formal-verify-all formal-verify-noassume clean

# Every output is under build/. The .gitignore fallback entries cover a tool
# started by hand from the repo root.
clean:
	rm -rf $(BUILD)
