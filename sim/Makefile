# ============================================================================
# Makefile -- run targets for QuestaSim / Questa Formal Verification
# (Siemens EDA). Builds the rtl/tb/formal sources with vlib/vlog/vopt/vsim
# and adds a real formal-proof flow via `qverify'.
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
# `formal` runs the ../formal/ assume/assert/cover environment (flow #2 in
# formal_tb.sv's header comment) under vsim -- bounded, randomly-driven
# simulation, not exhaustive formal proof. SEED controls
# axi4lite_formal_driver.sv's randomization for reproducibility:
#   make formal SEED=123
# `formal-sweep` builds once and sweeps seeds 1..N, same idea as uvm-sweep:
#   make formal-sweep N=20
#
# `formal-verify` drives Questa's real formal-proof engine (`qverify`) over 
# the same formal/ SVA files via sim/formal_questa.do, exhaustive property proof, 
# not simulation.
#   make formal-verify                        # 32-bit (DATA_WIDTH default)
#   make formal-verify DATA_WIDTH=64          # 64-bit
#   make formal-verify-all                    # both
#
# DATA_WIDTH (32 or 64, default 32) applies to every target -- UVM,
# simple and formal alike:
#   make uvm TEST=axi4lite_random_test DATA_WIDTH=64
# ============================================================================

TEST      ?= axi4lite_smoke_test
SEED      ?= 42
N         ?= 20
# uvm-sweep fails if the functional coverage merged over its passing seeds
# is below COV_GOAL (%). 100 for the random and unaligned-address tests
# (sign-off); the smoke test only reaches part of the model by design, so
# it isn't held to it. One seed isn't expected to close the model alone.
COV_GOAL  ?= $(if $(filter axi4lite_random_test axi4lite_unaligned_test,$(TEST)),100,0)
RTL_DIR   := ../rtl
TB_DIR    := ../tb
FORMAL_DIR := ../formal

# If $MODELSIM is set in your shell (some site installs export it globally,
# pointing at the install tree's own modelsim.ini), every vlib/vlog/vmap/vsim
# call ignores this directory's local modelsim.ini and tries to read/write
# that global one instead 
export MODELSIM := $(CURDIR)/modelsim.ini

UVM_HOME ?= /eda/Siemens/2024-25/RHELx86/QUESTA-CORE-PRIME_2024.3/questasim/verilog_src/uvm-1.2/src

# axi4lite_types_pkg.sv must come first: the RTL, UVM package, tb_simple
# and formal files all import it
RTL_FILES := $(RTL_DIR)/axi4lite_types_pkg.sv \
             $(RTL_DIR)/axi4lite_slave.sv

# axi4lite_pkg.sv must come before axi4lite_if.sv: the interface's default
# parameter values reference axi4lite_pkg::ADDR_WIDTH/DATA_WIDTH
TB_FILES  := $(TB_DIR)/axi4lite_pkg.sv \
             $(TB_DIR)/axi4lite_if.sv \
             $(TB_DIR)/tb_top.sv
FORMAL_FILES := $(FORMAL_DIR)/axi4lite_assumptions.sv \
                $(FORMAL_DIR)/axi4lite_fifo_model.sv \
                $(FORMAL_DIR)/axi4lite_blackbox_protocol.sv \
                $(FORMAL_DIR)/axi4lite_blackbox_data.sv \
                $(FORMAL_DIR)/axi4lite_whitebox_regfile.sv \
                $(FORMAL_DIR)/axi4lite_covers.sv \
                $(FORMAL_DIR)/axi4lite_formal_driver.sv \
                $(FORMAL_DIR)/formal_tb.sv

VLIB    ?= vlib
VLOG    ?= vlog
VOPT    ?= vopt
VSIM    ?= vsim
QVERIFY ?= qverify

QUESTA_WORK   := questa_work

# AXI data width, 32 or 64, for every flow: compiled in as
# +define+AXI4LITE_DATA_WIDTH, read by tb/axi4lite_pkg.sv (UVM),
# tb/tb_simple.sv and formal/formal_tb.sv, each of which passes it to the
# DUT. uvm/simple/formal share questa_work, and every *-build target
# recompiles, so switching width needs no clean.
DATA_WIDTH ?= 32
WIDTH_DEFINE := +define+AXI4LITE_DATA_WIDTH=$(DATA_WIDTH)
UVM_VERBOSITY ?= UVM_LOW

# ============================================================================
# Shared library setup -- just vlib+vmap, nothing UVM/test-specific about it.
# ============================================================================
lib:
	$(VLIB) $(QUESTA_WORK)
	vmap work $(QUESTA_WORK)

# ============================================================================
# Plain (non-UVM) simple test -- tb_simple.sv drives axi4lite_slave
# directly, no UVM agent/package involved.
# ============================================================================
SIMPLE_FILES := $(RTL_FILES) $(TB_DIR)/tb_simple.sv

simple-build: lib
	$(VLOG) -sv -timescale 1ns/1ps $(WIDTH_DEFINE) \
	     +incdir+$(TB_DIR) +incdir+$(RTL_DIR) \
	     $(SIMPLE_FILES)
	$(VOPT) +acc tb_simple -o tb_simple_opt

simple: simple-build
	$(VSIM) -c -onfinish exit tb_simple_opt -do "run -all; quit -f"


# ============================================================================
# UVM testbench (tb/) via QuestaSim
# ============================================================================
# Code coverage on the RTL only (statement, branch, condition, expression,
# FSM), not on the UVM library or the testbench: the RTL is compiled in its
# own vlog call with +cover, and vsim -coverage collects it into the same
# UCDB as the covergroups.
CODE_COV ?= bcesf

uvm-build: lib
	$(VLOG) -sv -timescale 1ns/1ps $(WIDTH_DEFINE) \
	     +incdir+$(UVM_HOME) +define+UVM_NO_DPI \
	     $(UVM_HOME)/uvm_pkg.sv
	$(VLOG) -sv -timescale 1ns/1ps $(WIDTH_DEFINE) +cover=$(CODE_COV) \
	     +incdir+$(RTL_DIR) \
	     $(RTL_FILES)
	$(VLOG) -sv -timescale 1ns/1ps $(WIDTH_DEFINE) \
	     +incdir+$(UVM_HOME) +define+UVM_NO_DPI \
	     +incdir+$(TB_DIR) +incdir+$(RTL_DIR) \
	     $(TB_FILES)
	$(VOPT) +acc tb_top -o tb_top_opt

uvm: uvm-build
	$(VSIM) -c -coverage tb_top_opt +UVM_TESTNAME=$(TEST) -sv_seed $(SEED) \
	     +UVM_VERBOSITY=$(UVM_VERBOSITY) -onfinish exit -do "run -all; quit -f"

# Each seed saves its coverage to $(UVM_COV_DIR)/seed_<n>.ucdb (same
# -onfinish stop / coverage save pattern as formal-coverage); the passing
# seeds are merged with vcover and the merged covergroup coverage is held to
# COV_GOAL. merged_cvg.txt is kept for finding the bins still at zero.
# Code coverage of the DUT is reported too (merged_code.txt, summary
# printed) but not gated: a code hole needs a reason -- missing stimulus,
# missing plan item, or unreachable code -- before it can be waived.
UVM_COV_DIR := uvm_cov_ucdb

uvm-sweep: uvm-build
	@rm -rf $(UVM_COV_DIR); mkdir -p $(UVM_COV_DIR); \
	fail=0; \
	for s in $$(seq 1 $(N)); do \
	  out=$$($(VSIM) -c -coverage tb_top_opt +UVM_TESTNAME=$(TEST) -sv_seed $$s \
	         +UVM_VERBOSITY=$(UVM_VERBOSITY) -onfinish stop \
	         -do "run -all; coverage save $(UVM_COV_DIR)/seed_$$s.ucdb; quit -f" 2>&1); \
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
	     +incdir+$(RTL_DIR) \
	     $(RTL_FILES) $(FORMAL_FILES)
	$(VOPT) +acc formal_tb -o formal_tb_opt

formal: formal-build
	$(VSIM) -c -onfinish exit formal_tb_opt -sv_seed $(SEED) -do "run -all; quit -f"

formal-sweep: formal-build
	@fail=0; \
	for s in $$(seq 1 $(N)); do \
	  out=$$($(VSIM) -c -onfinish exit formal_tb_opt -sv_seed $$s -do "run -all; quit -f" 2>&1); \
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
VCOVER ?= vcover
FORMAL_COV_DIR := formal_cov_ucdb

formal-build-cov: lib
	$(VLOG) -sv -timescale 1ns/1ps $(WIDTH_DEFINE) \
	     +incdir+$(RTL_DIR) \
	     $(RTL_FILES) $(FORMAL_FILES)
	$(VOPT) +acc formal_tb -o formal_tb_cov_opt

formal-coverage: formal-build-cov
	@rm -rf $(FORMAL_COV_DIR); mkdir -p $(FORMAL_COV_DIR)
	@for s in $$(seq 1 $(N)); do \
	  $(VSIM) -c -onfinish stop formal_tb_cov_opt -sv_seed $$s \
	       -do "run -all; coverage save $(FORMAL_COV_DIR)/seed_$$s.ucdb; quit -f" \
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
# `qverify`, driven by sim/formal_questa.do.
# ============================================================================
# Report: formal_report.txt (32-bit) or formal_report_64.txt.
formal-verify:
	DATA_WIDTH=$(DATA_WIDTH) $(QVERIFY) -c -do formal_questa.do

# Prove both supported data widths back to back.
formal-verify-all:
	$(MAKE) formal-verify DATA_WIDTH=32
	$(MAKE) formal-verify DATA_WIDTH=64

# Same proof with formal_tb's assumptions compiled out -- any assert that
# no longer proves here depends on the assumptions. Writes
# formal_report[_64]_noassume.txt; the normal report is untouched.
formal-verify-noassume:
	DATA_WIDTH=$(DATA_WIDTH) NO_ASSUME=1 $(QVERIFY) -c -do formal_questa.do

.PHONY: lib simple-build simple uvm-build uvm uvm-sweep \
        formal-build formal formal-sweep formal-build-cov formal-coverage \
        formal-verify formal-verify-all formal-verify-noassume clean

# Everything below is tool-generated and regenerable -- nothing here is a
# source file, so the globs are safe: sim/ only ever holds Makefile,
# formal_questa.do, wave.do and wave_uvm.do under version control.
clean:
# vlib/vmap/vopt output
	rm -rf $(QUESTA_WORK) formal_work work tb_top_opt tb_simple_opt formal_tb_opt formal_tb_cov_opt
	rm -rf modelsim.ini
# vsim: console log, waveform databases, UVM transaction-recording log
	rm -rf transcript *.wlf *.vcd *.fst tr_db.log vsim.dbg vish_stacktrace.vstf
# vcover / coverage
	rm -rf $(FORMAL_COV_DIR) $(UVM_COV_DIR) *.ucdb
# qverify (formal-verify): work dirs, reports, replayed command log
	rm -rf .qverify propcheck.db
	rm -rf formal_design.rpt formal_property.rpt formal_settings.rpt \
	       formal_verify.rpt formal_report*.txt
	rm -rf formal_compile.log formal_verify.log qverify.log qverify_cmds.tcl
# qverify/visualizer GUI leftovers: saved debug sessions (*.ses), the
# Visualizer wave database, its per-user config dir and logs, and the
# empty `etch<pid>` scratch files Questa drops on startup
	rm -rf *.ses *.qwdb qwave.db .visualizer visualizer.log \
	       qverify_ui.log qverify_ui_cmds.tcl sysinfo.log etch[0-9]*
# catch-all for any remaining tool log
	rm -rf *.log
