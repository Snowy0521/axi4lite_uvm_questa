// UVM testbench file list (repo-root-relative, see rtl/rtl.f). The UVM library
// itself is compiled separately from $(UVM_HOME). axi4lite_pkg.sv `includes the
// class files (hence +incdir+tb) and must come before axi4lite_if.sv: the
// interface's default parameter values reference axi4lite_pkg::ADDR_WIDTH /
// DATA_WIDTH.
+incdir+tb
tb/axi4lite_pkg.sv
tb/axi4lite_if.sv
tb/tb_top.sv
