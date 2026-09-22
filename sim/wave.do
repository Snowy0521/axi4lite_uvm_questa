# ============================================================================
# wave.do -- interactive-only: add curated waves for tb_simple, then run.
#
# NOT for batch/CI use -- deliberately doesn't `quit` at the end, so you're
# left sitting in the GUI looking at the result. See sim/Makefile's
# `-do "run -all; quit -f"` for the automated (headless, pass/fail) run.
#
# Usage:
#   cd sim && make simple-build          # compile + vopt tb_simple_opt first
#   vsim -do wave.do tb_simple_opt        # load design, add waves, run, done
# or, from inside an already-loaded GUI session's Transcript:
#   do wave.do
#
# Run the `vsim` line by hand in a shell with a working $DISPLAY, not via a
# make target.
# ============================================================================

add wave -divider "AW (write addr)"
add wave -radix hexadecimal   /tb_simple/awaddr
add wave                      /tb_simple/awvalid
add wave                      /tb_simple/awready

add wave -divider "W (write data)"
add wave -radix hexadecimal   /tb_simple/wdata
add wave -radix binary        /tb_simple/wstrb
add wave                      /tb_simple/wvalid
add wave                      /tb_simple/wready

add wave -divider "B (write resp)"
add wave -radix hexadecimal   /tb_simple/bresp
add wave                      /tb_simple/bvalid
add wave                      /tb_simple/bready

add wave -divider "AR (read addr)"
add wave -radix hexadecimal   /tb_simple/araddr
add wave                      /tb_simple/arvalid
add wave                      /tb_simple/arready

add wave -divider "R (read data)"
add wave -radix hexadecimal   /tb_simple/rdata
add wave -radix hexadecimal   /tb_simple/rresp
add wave                      /tb_simple/rvalid
add wave                      /tb_simple/rready

add wave -divider "DUT internal"
add wave                      /tb_simple/dut/aw_hs_done
add wave                      /tb_simple/dut/w_hs_done
add wave -radix hexadecimal   /tb_simple/dut/regfile

configure wave -namecolwidth 220

run -all

wave zoom full
