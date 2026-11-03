// RTL file list. Paths are relative to the repo root: vlog -f, verilator -f and
// slang -f resolve them against the current directory, and every flow runs from
// the root. File names and +incdir only, no tool flags.
// axi4lite_types_pkg.sv first: the RTL, the UVM package, tb_simple and the
// formal files all import it.
+incdir+rtl
rtl/axi4lite_types_pkg.sv
rtl/axi4lite_slave.sv
