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
#   make uvm-sweep TEST=axi4lite_random_test N=50
#
# `formal` runs the ../formal/ assume/assert/cover environment (flow #2 in
# formal_tb.sv's header comment) under vsim -- bounded, randomly-driven
# simulation, not exhaustive formal proof. SEED controls
# axi4lite_formal_driver.sv's randomization for reproducibility:
#   make formal SEED=123
# `formal-sweep` builds once and sweeps seeds 1..N, same idea as uvm-sweep:
#   make formal-sweep N=50
#
# `formal-verify` drives Questa's real formal-proof engine (`qverify`) over 
# the same formal/ SVA files via formal/formal_questa.do, exhaustive property proof, 
# not simulation.
#   make formal-verify
# ============================================================================

TEST      ?= axi4lite_smoke_test
SEED      ?= 42
N         ?= 20
RTL_DIR   := ../rtl
TB_DIR    := ../tb
FORMAL_DIR := ../formal

# If $MODELSIM is set in your shell (some site installs export it globally,
# pointing at the install tree's own modelsim.ini), every vlib/vlog/vmap/vsim
# call ignores this directory's local modelsim.ini and tries to read/write
# that global one instead 
export MODELSIM := $(CURDIR)/modelsim.ini

UVM_HOME ?= /eda/Siemens/2024-25/RHELx86/QUESTA-CORE-PRIME_2024.3/questasim/verilog_src/uvm-1.2/src

RTL_FILES := $(RTL_DIR)/axi4lite_slave.sv

# axi4lite_pkg.sv must come before axi4lite_if.sv: the interface's default
# parameter values reference axi4lite_pkg::ADDR_WIDTH/DATA_WIDTH
TB_FILES  := $(TB_DIR)/axi4lite_pkg.sv \
             $(TB_DIR)/axi4lite_if.sv \
             $(TB_DIR)/tb_top.sv
FORMAL_FILES := $(FORMAL_DIR)/axi4lite_assumptions.sv \
                $(FORMAL_DIR)/axi4lite_assertions.sv \
                $(FORMAL_DIR)/axi4lite_covers.sv \
                $(FORMAL_DIR)/axi4lite_formal_driver.sv \
                $(FORMAL_DIR)/formal_tb.sv

VLIB    ?= vlib
VLOG    ?= vlog
VOPT    ?= vopt
VSIM    ?= vsim
QVERIFY ?= qverify

QUESTA_WORK   := questa_work
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
	$(VLOG) -sv -timescale 1ns/1ps \
	     +incdir+$(TB_DIR) +incdir+$(RTL_DIR) \
	     $(SIMPLE_FILES)
	$(VOPT) +acc tb_simple -o tb_simple_opt

simple: simple-build
	$(VSIM) -c -onfinish exit tb_simple_opt -do "run -all; quit -f"


# ============================================================================
# UVM testbench (tb/) via QuestaSim
# ============================================================================
uvm-build: lib
	$(VLOG) -sv -timescale 1ns/1ps \
	     +incdir+$(UVM_HOME) +define+UVM_NO_DPI \
	     +incdir+$(TB_DIR) +incdir+$(RTL_DIR) \
	     $(UVM_HOME)/uvm_pkg.sv $(RTL_FILES) $(TB_FILES)
	$(VOPT) +acc tb_top -o tb_top_opt

uvm: uvm-build
	$(VSIM) -c tb_top_opt +UVM_TESTNAME=$(TEST) +ntb_random_seed=$(SEED) \
	     +UVM_VERBOSITY=$(UVM_VERBOSITY) -onfinish exit -do "run -all; quit -f"

uvm-sweep: uvm-build
	@fail=0; \
	for s in $$(seq 1 $(N)); do \
	  out=$$($(VSIM) -c tb_top_opt +UVM_TESTNAME=$(TEST) +ntb_random_seed=$$s \
	         +UVM_VERBOSITY=$(UVM_VERBOSITY) -onfinish exit -do "run -all; quit -f" 2>&1); \
	  errs=$$(echo "$$out" | sed -n 's/^#\{0,1\} *UVM_ERROR :[ \t]*\([0-9][0-9]*\).*/\1/p' | tail -1); \
	  fatals=$$(echo "$$out" | sed -n 's/^#\{0,1\} *UVM_FATAL :[ \t]*\([0-9][0-9]*\).*/\1/p' | tail -1); \
	  if [ -z "$$errs" ] || [ -z "$$fatals" ]; then \
	    echo "seed $$s: FAILED (no UVM report summary found -- crashed or hung?)"; \
	    echo "$$out" | tail -30 | sed 's/^/    /'; \
	    fail=1; \
	  elif [ "$$errs" -gt 0 ] || [ "$$fatals" -gt 0 ]; then \
	    echo "seed $$s: FAILED (UVM_ERROR=$$errs UVM_FATAL=$$fatals)"; \
	    fail=1; \
	  else \
	    echo "seed $$s: OK"; \
	  fi; \
	done; \
	if [ "$$fail" -eq 0 ]; then \
	  echo "ALL $(N) SEEDS PASSED (TEST=$(TEST))"; \
	else \
	  echo "SOME SEEDS FAILED (TEST=$(TEST))"; \
	  exit 1; \
	fi

# ============================================================================
# Formal assume/assert/cover environment (flow #2: bounded, randomly-driven
# simulation, not exhaustive proof -- see formal_tb.sv's header comment)
# ============================================================================
formal-build: lib
	$(VLOG) -sv -timescale 1ns/1ps \
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
	$(VLOG) -sv -timescale 1ns/1ps \
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
# `qverify`, driven by formal/formal_questa.do.
# ============================================================================
formal-verify:
	$(QVERIFY) -c -do $(FORMAL_DIR)/formal_questa.do

.PHONY: lib simple-build simple uvm-build uvm uvm-sweep \
        formal-build formal formal-sweep formal-build-cov formal-coverage \
        formal-verify clean

# Everything below is tool-generated and regenerable -- nothing here is a
# source file, so the globs are safe: sim/ only ever holds Makefile,
# wave.do and wave_uvm.do under version control.
clean:
# vlib/vmap/vopt output
	rm -rf $(QUESTA_WORK) work tb_top_opt tb_simple_opt formal_tb_opt formal_tb_cov_opt
	rm -rf modelsim.ini
# vsim: console log, waveform databases, UVM transaction-recording log
	rm -rf transcript *.wlf *.vcd *.fst tr_db.log vsim.dbg vish_stacktrace.vstf
# vcover / coverage
	rm -rf $(FORMAL_COV_DIR) *.ucdb
# qverify (formal-verify): work dirs, reports, replayed command log
	rm -rf .qverify propcheck.db
	rm -rf formal_design.rpt formal_property.rpt formal_settings.rpt \
	       formal_verify.rpt formal_report.txt
	rm -rf formal_compile.log formal_verify.log qverify.log qverify_cmds.tcl
# qverify/visualizer GUI leftovers: saved debug sessions (*.ses), the
# Visualizer wave database, its per-user config dir and logs, and the
# empty `etch<pid>` scratch files Questa drops on startup
	rm -rf *.ses *.qwdb qwave.db .visualizer visualizer.log \
	       qverify_ui.log qverify_ui_cmds.tcl sysinfo.log etch[0-9]*
# catch-all for any remaining tool log
	rm -rf *.log
