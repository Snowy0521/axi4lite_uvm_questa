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
  input logic clk
);

  // ---------------------------------------------------------------------
  // Reset. The interface owns rst_n, so the power-on reset (tb_top) and a
  // test's mid-run reset (reset_ctrl modport) go through the same code.
  // It starts at 1 and power_on_reset drops it at 1 ns: a real 1 -> 0 edge
  // after every process has started and before the first posedge. An
  // initialiser of 0 gives the DUT's `negedge rst_n` no edge at all, and
  // `rst_n = 0` in an initial at time 0 races it. Every other change is at a
  // negedge, at least the drv_cb output skew (2 ns) after a posedge, so no
  // clocking-block drive is pending when rst_n falls and the driver's direct
  // clear (clear_master_valids) can't be undone by one. Anything that waits
  // for reset waits for rst_n to fall and then rise: it starts at 1.
  // ---------------------------------------------------------------------
  logic rst_n = 1'b1;

  // Power-on: low for `cycles` posedges, released at a negedge.
  task automatic power_on_reset(int unsigned cycles);
    #1 rst_n = 1'b0;
    repeat (cycles) @(posedge clk);
    @(negedge clk) rst_n = 1'b1;
  endtask

  // Mid-run: from a negedge, low for `cycles` (at least 1) clock cycles,
  // released at a negedge.
  task automatic apply_reset(int unsigned cycles);
    @(negedge clk) rst_n = 1'b0;
    repeat ((cycles == 0) ? 1 : cycles) @(negedge clk);
    rst_n = 1'b1;
  endtask

  // The master-side VALIDs and READYs start at the driver's idle values
  // (reset_signals()): the driver only drives them after reset is released,
  // so without these they would be X at every power-on edge, where the bound
  // m_*valid_low_in_reset / m_no_x_* assumptions check them. Addresses and
  // data may stay X: every check on them is conditional on VALID.
  logic [ADDR_WIDTH-1:0]   awaddr;
  logic                    awvalid = 1'b0;
  logic                    awready;

  logic [DATA_WIDTH-1:0]   wdata;
  logic [DATA_WIDTH/8-1:0] wstrb;
  logic                    wvalid = 1'b0;
  logic                    wready;

  logic [1:0]              bresp;
  logic                    bvalid;
  logic                    bready = 1'b1;

  logic [ADDR_WIDTH-1:0]   araddr;
  logic                    arvalid = 1'b0;
  logic                    arready;
  
  logic [DATA_WIDTH-1:0]   rdata;
  logic [1:0]              rresp;
  logic                    rvalid;
  logic                    rready = 1'b1;
  
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

  // The one bypass of drv_cb, for the driver's reset handling only: the
  // master VALIDs go low in the same time step as rst_n falls, as a real
  // master's flops with an asynchronous reset would (spec 4.1.1, checked by
  // the bound m_*valid_low_in_reset). Through drv_cb they would only change
  // at the next posedge + 2 ns, after that posedge had sampled them high.
  // Not an `output awvalid` in the modport: that would let any driver code
  // bypass the clocking block.
  function automatic void clear_master_valids();
    awvalid = 1'b0;
    wvalid  = 1'b0;
    arvalid = 1'b0;
  endfunction

  // The master VALIDs as they were just before rst_n fell (#1step: sampled in
  // the Preponed region of the fall's time step), for the monitor to report
  // what a reset cut off. Neither mon_cb nor the raw pins can tell it: mon_cb
  // holds the last posedge sample, from before the driver raised a VALID
  // (drv_cb drives 2 ns after a posedge, the fall comes at the next negedge),
  // and the pins race the driver's clear_master_valids() in the same time
  // step. A clocking block updates its samples before it triggers, so they are
  // current once @(rst_cb) returns.
  clocking rst_cb @(negedge rst_n);
    default input #1step;
    input awvalid, wvalid, arvalid;
  endclocking

  // rst_n is asynchronous and deliberately kept outside both clocking
  // blocks: the driver and monitor wait for rst_n to fall and then rise
  // (it starts at 1), and need to see each change immediately, not delayed
  // by a clocking block's #1step sample.
  modport driver     (clocking drv_cb, input clk, rst_n, import clear_master_valids);
  modport monitor    (clocking mon_cb, clocking rst_cb, input clk, rst_n);
  // For a test that resets the DUT mid-run (axi4lite_reset_test).
  modport reset_ctrl (input clk, rst_n, import apply_reset);

endinterface
