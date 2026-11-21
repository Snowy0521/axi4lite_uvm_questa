// ============================================================================
// tb_top.sv
//
// Top-level testbench: generates clock/reset, instantiates the DUT and the
// AXI4-Lite interface, registers the virtual interface with uvm_config_db
// for the UVM environment to pick up, and launches the UVM test.
// ============================================================================

`timescale 1ns/1ps

import uvm_pkg::*;
import axi4lite_pkg::*;

module tb_top;

  logic clk;

  // ------------------------------------------------------------------
  // Clock generation: 100 MHz (10ns period)
  // ------------------------------------------------------------------
  initial clk = 0;
  always #5 clk = ~clk;

  // ------------------------------------------------------------------
  // Interface + DUT. The interface owns rst_n (see axi4lite_if.sv).
  // ------------------------------------------------------------------
  axi4lite_if #(.ADDR_WIDTH(axi4lite_pkg::ADDR_WIDTH), .DATA_WIDTH(axi4lite_pkg::DATA_WIDTH)) intf (
    .clk    (clk)
  );

  // Power-on reset: low from 1 ns for 3 posedges, released at a negedge
  initial intf.power_on_reset(3);

  axi4lite_slave #(
    .ADDR_WIDTH (axi4lite_pkg::ADDR_WIDTH),
    .DATA_WIDTH (axi4lite_pkg::DATA_WIDTH),
    .NUM_REGS   (axi4lite_pkg::NUM_REGS)
  ) dut (
    .clk    (clk),
    .rst_n   (intf.rst_n),
    .awaddr  (intf.awaddr),
    .awvalid (intf.awvalid),
    .awready (intf.awready),
    .wdata   (intf.wdata),
    .wstrb   (intf.wstrb),
    .wvalid  (intf.wvalid),
    .wready  (intf.wready),
    .bresp   (intf.bresp),
    .bvalid  (intf.bvalid),
    .bready  (intf.bready),
    .araddr  (intf.araddr),
    .arvalid (intf.arvalid),
    .arready (intf.arready),
    .rdata   (intf.rdata),
    .rresp   (intf.rresp),
    .rvalid  (intf.rvalid),
    .rready  (intf.rready)
  );

  // ------------------------------------------------------------------
  // The formal checkers, bound into this DUT instance, so every UVM test also
  // runs every assertion; a failing one is a "** Error", which the regression
  // counts. An instance bind, not a module-type bind: formal_tb instantiates
  // the same checkers, and a module-type bind would reach its DUT too, since
  // both are compiled into one library. The connections and parameters resolve
  // in the DUT's scope (its ports, its regfile, its parameters).
  // axi4lite_assumptions checks that the UVM driver is a legal master.
  // axi4lite_covers is not bound: covers are formal sign-off, not a UVM goal.
  // NO_UVM_CHECKERS (make UVM_CHECKERS=no) builds without them: mutation
  // testing scores the UVM bench on its own that way.
  // ------------------------------------------------------------------
`ifndef NO_UVM_CHECKERS
  bind dut axi4lite_assumptions #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))
    u_assumptions (.*);
  bind dut axi4lite_blackbox_protocol #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .NUM_REGS(NUM_REGS))
    u_bb_protocol (.*);
  bind dut axi4lite_blackbox_data #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .NUM_REGS(NUM_REGS))
    u_bb_data (.*);
  bind dut axi4lite_whitebox_regfile #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .NUM_REGS(NUM_REGS))
    u_wb_regfile (.*);
`endif

  // ------------------------------------------------------------------
  // UVM setup + test launch
  // ------------------------------------------------------------------
  initial begin
    // One set per modport: config_db keys on the full type, so the
    // .driver and .monitor handles are separate entries. Scoped to the
    // agent rather than "*", so only its driver and monitor can see the
    // interface; a mistyped path then leaves a set nobody reads, which
    // the getters' NOVIF fatal and the base test's unused-config check catch.
    uvm_config_db#(
      virtual axi4lite_if #(
        .ADDR_WIDTH(axi4lite_pkg::ADDR_WIDTH),
        .DATA_WIDTH(axi4lite_pkg::DATA_WIDTH)
      ).driver
    )::set(null, "uvm_test_top.env.agent.*", "vif", intf);

    uvm_config_db#(
      virtual axi4lite_if #(
        .ADDR_WIDTH(axi4lite_pkg::ADDR_WIDTH),
        .DATA_WIDTH(axi4lite_pkg::DATA_WIDTH)
      ).monitor
    )::set(null, "uvm_test_top.env.agent.*", "vif", intf);

    // For a test that resets the DUT mid-run; the base test reads it
    uvm_config_db#(
      virtual axi4lite_if #(
        .ADDR_WIDTH(axi4lite_pkg::ADDR_WIDTH),
        .DATA_WIDTH(axi4lite_pkg::DATA_WIDTH)
      ).reset_ctrl
    )::set(null, "uvm_test_top", "reset_vif", intf);
    // +UVM_TESTNAME on the vsim command line overrides this default test name
    run_test("axi4lite_smoke_test");
  end

  // Waves only on request (+vcd, e.g. make uvm PLUSARGS=+vcd): a full-hierarchy
  // VCD on every run costs time on every regression seed.
  initial begin
    if ($test$plusargs("vcd")) begin
      $dumpfile("tb_top.vcd");
      $dumpvars(0, tb_top);
    end
  end

endmodule
