# ============================================================================
# wave_uvm.do -- interactive-only: add curated waves for the UVM env
# (tb_top / intf / dut), then run. Same idea as wave.do, just aimed at the
# UVM testbench instead of tb_simple.
#
# NOT for batch/CI use -- deliberately doesn't `quit` at the end.
#
# Usage:
#   cd sim && make uvm-build
#   vsim -do wave_uvm.do tb_top_opt
#   vsim -do wave_uvm.do tb_top_opt +UVM_TESTNAME=axi4lite_random_test \
#        +ntb_random_seed=42 +UVM_VERBOSITY=UVM_LOW
#
# Run this by hand in a shell with a working $DISPLAY, not via a make
# target.
# ============================================================================

add wave -divider "clk/rst"
add wave /tb_top/clk
add wave /tb_top/rst_n

add wave -divider "AW (write addr)"
add wave -radix hexadecimal   /tb_top/intf/awaddr
add wave                      /tb_top/intf/awvalid
add wave                      /tb_top/intf/awready

add wave -divider "W (write data)"
add wave -radix hexadecimal   /tb_top/intf/wdata
add wave -radix binary        /tb_top/intf/wstrb
add wave                      /tb_top/intf/wvalid
add wave                      /tb_top/intf/wready

add wave -divider "B (write resp)"
add wave -radix hexadecimal   /tb_top/intf/bresp
add wave                      /tb_top/intf/bvalid
add wave                      /tb_top/intf/bready

add wave -divider "AR (read addr)"
add wave -radix hexadecimal   /tb_top/intf/araddr
add wave                      /tb_top/intf/arvalid
add wave                      /tb_top/intf/arready

add wave -divider "R (read data)"
add wave -radix hexadecimal   /tb_top/intf/rdata
add wave -radix hexadecimal   /tb_top/intf/rresp
add wave                      /tb_top/intf/rvalid
add wave                      /tb_top/intf/rready

add wave -divider "DUT internal (ground truth -- what actually got written)"
add wave                      /tb_top/dut/aw_hs_done
add wave                      /tb_top/dut/w_hs_done
add wave -radix hexadecimal   /tb_top/dut/wdata_latched
add wave -radix binary        /tb_top/dut/wstrb_latched
add wave -radix hexadecimal   /tb_top/dut/regfile

configure wave -namecolwidth 220

#run 100ns
run -all
wave zoom full
