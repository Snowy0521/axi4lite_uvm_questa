# ============================================================================
# formal_questa.do -- Questa Formal Verification (qverify) batch script.
#
# Run via:  cd sim && make formal-verify
#
# Only supported from sim/ (paths below are relative to that directory,
# matching every other target in sim/Makefile)
#
# Compiles the DUT plus formal/'s SVA files (assumptions/assertions/covers)
# ============================================================================

onerror {exit 1}

set RTL_DIR    "../rtl"
set FORMAL_DIR "../formal"

vlib questa_work
vmap work questa_work

vlog -sv -timescale 1ns/1ps +define+QUESTA_FORMAL \
     +incdir+$RTL_DIR \
     $RTL_DIR/axi4lite_slave.sv \
     $FORMAL_DIR/axi4lite_assumptions.sv \
     $FORMAL_DIR/axi4lite_assertions.sv \
     $FORMAL_DIR/axi4lite_covers.sv \
     $FORMAL_DIR/formal_tb.sv

# Elaborate the design for formal analysis.
formal compile -d formal_tb

# Run every compiled assert/cover property to exhaustion.
formal verify

# Dump a human-readable summary (proven / falsified / inconclusive / covered per property)
formal generate report formal_report.txt

exit
