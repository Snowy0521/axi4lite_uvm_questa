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

# Own library, separate from the simulation flows' questa_work: the two
# compile the same files with different defines (QUESTA_FORMAL etc.),
# which in one shared library overwrites each other's units (vlog-13233).
# sim/Makefile's `lib` target re-maps work to questa_work for simulation.
vlib formal_work
vmap work formal_work

# Environment knobs (set by sim/Makefile):
#   DATA_WIDTH=32|64        -- formal_tb's data width (default 32)
#   NO_ASSUME=1             -- compile out formal_tb's assumptions instance
#                              (make formal-verify-noassume), to check which
#                              proofs need it
# Each non-default knob adds a suffix to the report name, so runs don't
# clobber each other: formal_report.txt, formal_report_64.txt,
# formal_report_noassume.txt, formal_report_64_noassume.txt.
set DATA_WIDTH 32
if {[info exists ::env(DATA_WIDTH)] && $::env(DATA_WIDTH) ne ""} {
    set DATA_WIDTH $::env(DATA_WIDTH)
}
set EXTRA_DEFINES [list +define+AXI4LITE_DATA_WIDTH=$DATA_WIDTH]
set REPORT_SUFFIX ""
if {$DATA_WIDTH != 32} {
    append REPORT_SUFFIX "_$DATA_WIDTH"
}
if {[info exists ::env(NO_ASSUME)] && $::env(NO_ASSUME)} {
    lappend EXTRA_DEFINES +define+FORMAL_NO_ASSUMPTIONS
    append REPORT_SUFFIX "_noassume"
}
set REPORT "formal_report$REPORT_SUFFIX.txt"

vlog -sv -timescale 1ns/1ps +define+QUESTA_FORMAL {*}$EXTRA_DEFINES \
     +incdir+$RTL_DIR \
     $RTL_DIR/axi4lite_types_pkg.sv \
     $RTL_DIR/axi4lite_slave.sv \
     $FORMAL_DIR/axi4lite_assumptions.sv \
     $FORMAL_DIR/axi4lite_fifo_model.sv \
     $FORMAL_DIR/axi4lite_blackbox_protocol.sv \
     $FORMAL_DIR/axi4lite_blackbox_data.sv \
     $FORMAL_DIR/axi4lite_whitebox_regfile.sv \
     $FORMAL_DIR/axi4lite_covers.sv \
     $FORMAL_DIR/formal_tb.sv

# Elaborate the design for formal analysis.
formal compile -d formal_tb

# Run every compiled assert/cover property to exhaustion.
#
# -auto_constraint_off: by default qverify pins rst_n to 1 after its
# init sequence, which makes every `!rst_n |-> ...` property vacuous
# (a_bvalid/rvalid_low_in_reset, m_*valid_low_in_reset) and never
# explores reset asserted mid-transaction. With it off, rst_n is a free
# input after init, so reset can hit at any cycle.
formal verify -auto_constraint_off

# Dump a human-readable summary (proven / falsified / inconclusive / covered per property)
formal generate report $REPORT

exit
