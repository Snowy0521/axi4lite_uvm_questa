// Formal environment file list (repo-root-relative, see rtl/rtl.f): the checker
// modules and the formal_tb harness, exactly what qverify compiles. The
// simulation flow (make formal) adds formal/axi4lite_formal_driver.sv, the
// random legal master that QUESTA_FORMAL compiles out.
formal/axi4lite_assumptions.sv
formal/axi4lite_fifo_model.sv
formal/axi4lite_blackbox_protocol.sv
formal/axi4lite_blackbox_data.sv
formal/axi4lite_whitebox_regfile.sv
formal/axi4lite_covers.sv
formal/formal_tb.sv
