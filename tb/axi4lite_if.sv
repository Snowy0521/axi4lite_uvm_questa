// ============================================================================
// axi4lite_if.sv
//
// Bundles all AXI4-Lite signals into one interface, with clocking blocks for
// the driver (drives inputs from the master side, samples slave responses)
// and the monitor (purely samples everything, drives nothing).
//
// Using clocking blocks here avoids the classic testbench-vs-RTL sampling
// race: driver outputs are skewed after the clock edge, and driver
// inputs are sampled slightly before it.
// ============================================================================

interface axi4lite_if #(
  parameter int ADDR_WIDTH = axi4lite_pkg::ADDR_WIDTH,
  parameter int DATA_WIDTH = axi4lite_pkg::DATA_WIDTH
)(
  input logic clk,
  input logic rst_n
);

  logic [ADDR_WIDTH-1:0]   awaddr;
  logic                    awvalid;
  logic                    awready;

  logic [DATA_WIDTH-1:0]   wdata;
  logic [DATA_WIDTH/8-1:0] wstrb;
  logic                    wvalid;
  logic                    wready;

  logic [1:0]              bresp;
  logic                    bvalid;
  logic                    bready;

  logic [ADDR_WIDTH-1:0]   araddr;
  logic                    arvalid;
  logic                    arready;
  
  logic [DATA_WIDTH-1:0]   rdata;
  logic [1:0]              rresp;
  logic                    rvalid;
  logic                    rready;
  
  // ---------------------------------------------------------------------
  // Driver clocking block: drives master-side signals, samples slave
  // responses. Output skew keeps driven values from racing the DUT's own
  // posedge-triggered sampling; input skew (#1step) samples the settled
  // pre-edge value.
  // ---------------------------------------------------------------------
  clocking drv_cb @(posedge clk);
    default input #1step output #2;
    output awaddr, awvalid, wdata, wstrb, wvalid, bready, araddr, arvalid, rready;
    input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid;
  endclocking

  // ---------------------------------------------------------------------
  // Monitor clocking block: read-only, race-free view of every signal.
  // ---------------------------------------------------------------------
  clocking mon_cb @(posedge clk);
    default input #1step;
    input awaddr, awvalid, awready;
    input wdata, wstrb, wvalid, wready;
    input bresp, bvalid, bready;
    input araddr, arvalid, arready;
    input rdata, rresp, rvalid, rready;
  endclocking

  // rst_n is asynchronous and deliberately kept outside both clocking
  // blocks: driver/monitor code does `wait (vif.rst_n === 1'b1)` and needs
  // to see reset release immediately, not delayed by a clocking block's
  // #1step sample.
  modport driver  (clocking drv_cb, input clk, rst_n);
  modport monitor (clocking mon_cb, input clk, rst_n);

endinterface
