// ============================================================================
// formal_tb.sv
//
// Top-level formal environment for axi4lite_slave. Instantiates the DUT
// once, and wires it to axi4lite_assumptions.sv (constrains the environment
// to legal AXI4-Lite master behavior), axi4lite_assertions.sv (checks the
// DUT's own obligations, including the whitebox write-strobe checks against
// the DUT's internal `regfile`), and axi4lite_covers.sv (reachability
// coverage for the two spec rules that have no assert/assume of their own).
//
// Written to work two ways, selected by compiling with (or without)
// +define+QUESTA_FORMAL:
//   1. True formal tool (Questa Formal via `qverify`): compile with
//      +define+QUESTA_FORMAL. This compiles out the `always #5 clk = ~clk;`
//      generator, the `initial` reset block, the simulation time-limit
//      block, AND the axi4lite_formal_driver instantiation below -- the
//      tool supplies clock/reset itself via its own `clock`/`reset`
//      commands, and every AXI signal left undriven becomes a free
//      variable constrained only by axi4lite_assumptions.sv's `assume
//      property` checks. (The randomized driver must also be excluded
//      here, not just clk/reset -- its $urandom-based next-state logic
//      isn't proof-friendly and would artificially restrict the state
//      space a real formal engine should explore exhaustively.) See
//      formal/formal_questa.do for the qverify script that sets this
//      define.
//   2. Bounded/simulation-based assertion checking (QuestaSim, or any
//      simulator run as a smoke check before a real formal tool is
//      available): compile without the define (the default), and this
//      becomes a self-contained, randomly-driven testbench that still
//      exercises every assume/assert pair -- see sim/Makefile's `formal`
//      target.
// ============================================================================

`timescale 1ns/1ps

module formal_tb;

  localparam int ADDR_WIDTH = 8;
  localparam int DATA_WIDTH = 32;   // change to 64 to formally verify the 64-bit configuration
  localparam int NUM_REGS   = 16;

  // ------------------------------------------------------------------
  // DUT signals
  // ------------------------------------------------------------------
  logic                    clk;
  logic                    rst_n;

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

  // ------------------------------------------------------------------
  // Clock / reset -- flow #2 only (see header comment). Compiled out
  // under +define+QUESTA_FORMAL: a true formal tool drives these itself
  // via its own `clock`/`reset` commands.
  // ------------------------------------------------------------------
`ifndef QUESTA_FORMAL
  initial clk = 0;
  always #5 clk = ~clk;   // 10ns period -> 100MHz

  initial begin
    rst_n = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;
  end

  // ------------------------------------------------------------------
  // Simulation-only run length. A true formal tool never reaches an
  // `initial` block like this one during property solving; it only
  // matters for flow #2.
  // ------------------------------------------------------------------
  initial begin
    #100000;   // ~10,000 clock cycles at the 10ns period above
    $display("[formal_tb] Reached simulation time limit, stopping.");
    $finish;
  end
`endif

  // ------------------------------------------------------------------
  // DUT instantiation
  // ------------------------------------------------------------------
  axi4lite_slave #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .NUM_REGS   (NUM_REGS)
  ) dut (.*);

  // ------------------------------------------------------------------
  // Legal-master stimulus (flow #2 only) -- see
  // axi4lite_formal_driver.sv's header for why this is needed at all.
  // Compiled out under +define+QUESTA_FORMAL: a true formal tool leaves
  // every AXI signal undriven (hence free) and constrains it purely via
  // the `assume property` checks in axi4lite_assumptions.sv instead.
  // ------------------------------------------------------------------
`ifndef QUESTA_FORMAL
  axi4lite_formal_driver #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .NUM_REGS   (NUM_REGS)
  ) u_driver (.*);
`endif

  // ------------------------------------------------------------------
  // Environment constraints 
  // ------------------------------------------------------------------
  axi4lite_assumptions #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
  ) u_assumptions (
    .clk     (clk),
    .rst_n   (rst_n),
    .awaddr  (awaddr),
    .awvalid (awvalid),
    .awready (awready),
    .wdata   (wdata),
    .wstrb   (wstrb),
    .wvalid  (wvalid),
    .wready  (wready),
    .bready  (bready),
    .araddr  (araddr),
    .arvalid (arvalid),
    .arready (arready),
    .rready  (rready)
  );

  // ------------------------------------------------------------------
  // DUT obligations (whitebox: regfile wired directly to dut.regfile)
  // ------------------------------------------------------------------
  axi4lite_assertions #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .NUM_REGS   (NUM_REGS)
  ) u_assertions (
    .clk     (clk),
    .rst_n   (rst_n),
    .awaddr  (awaddr),
    .awvalid (awvalid),
    .awready (awready),
    .wdata   (wdata),
    .wstrb   (wstrb),
    .wvalid  (wvalid),
    .wready  (wready),
    .bresp   (bresp),
    .bvalid  (bvalid),
    .bready  (bready),
    .araddr  (araddr),
    .arvalid (arvalid),
    .arready (arready),
    .rdata   (rdata),
    .rresp   (rresp),
    .rvalid  (rvalid),
    .rready  (rready),
    .regfile (dut.regfile)
  );

  // ------------------------------------------------------------------
  // Reachability coverage for spec rules, which have no
  // assert/assume of their own, confirming the proof actually reaches these
  // scenarios rather than vacuously passing.
  // ------------------------------------------------------------------
  axi4lite_covers #(
    .DATA_WIDTH (DATA_WIDTH)
  ) u_covers (
    .clk     (clk),
    .rst_n   (rst_n),
    .awvalid (awvalid),
    .awready (awready),
    .wstrb   (wstrb),
    .wvalid  (wvalid),
    .wready  (wready),
    .bresp   (bresp),
    .bvalid  (bvalid),
    .bready  (bready),
    .arvalid (arvalid),
    .arready (arready),
    .rresp   (rresp),
    .rvalid  (rvalid),
    .rready  (rready)
  );

endmodule
