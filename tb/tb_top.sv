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
  logic rst_n;

  // ------------------------------------------------------------------
  // Clock generation: 100 MHz (10ns period)
  // ------------------------------------------------------------------
  initial clk = 0;
  always #5 clk = ~clk;

  // ------------------------------------------------------------------
  // Reset generation: held low for a few cycles at the start
  // ------------------------------------------------------------------
  initial begin
    rst_n = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;

    @(posedge clk);
  end

  // ------------------------------------------------------------------
  // Interface + DUT
  // ------------------------------------------------------------------
  axi4lite_if #(.ADDR_WIDTH(axi4lite_pkg::ADDR_WIDTH), .DATA_WIDTH(axi4lite_pkg::DATA_WIDTH)) intf (
    .clk    (clk),
    .rst_n (rst_n)
  );

  axi4lite_slave #(
    .ADDR_WIDTH (axi4lite_pkg::ADDR_WIDTH),
    .DATA_WIDTH (axi4lite_pkg::DATA_WIDTH),
    .NUM_REGS   (axi4lite_pkg::NUM_REGS)
  ) dut (
    .clk    (clk),
    .rst_n (rst_n),
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
  // UVM setup + test launch
  // ------------------------------------------------------------------
  initial begin
    uvm_config_db#(
    virtual axi4lite_if #(
      .ADDR_WIDTH(axi4lite_pkg::ADDR_WIDTH),
      .DATA_WIDTH(axi4lite_pkg::DATA_WIDTH)
      ).driver
    )::set(null, "*", "vif", intf);

  uvm_config_db#(
    virtual axi4lite_if #(
      .ADDR_WIDTH(axi4lite_pkg::ADDR_WIDTH),
      .DATA_WIDTH(axi4lite_pkg::DATA_WIDTH)
      ).monitor
    )::set(null, "*", "vif", intf);
    // +UVM_TESTNAME on the vsim command line overrides this default test name
    run_test("axi4lite_smoke_test");
  end

  // optional: dump waves if the simulator supports it
  initial begin
    $dumpfile("tb_top.vcd");
    $dumpvars(0, tb_top);
  end

endmodule
