// ============================================================================
// formal_tb.sv
//
// Top-level formal environment for axi4lite_slave. Instantiates the DUT
// once, and wires it to:
//   - axi4lite_assumptions.sv       -- constrains the environment to legal
//                                      AXI4-Lite master behavior
//   - axi4lite_blackbox_protocol.sv -- handshake/response/X checks, AXI
//                                      ports only
//   - axi4lite_blackbox_data.sv     -- end-to-end data check, AXI ports only
//   - axi4lite_whitebox_regfile.sv  -- data checks against the DUT's
//                                      internal `regfile`
//   - axi4lite_covers.sv            -- reachability coverage
//
// Written to work two ways, selected by compiling with (or without)
// +define+QUESTA_FORMAL:
//   1. True formal tool (Questa Formal via `qverify`): compile with
//      +define+QUESTA_FORMAL. This compiles out the `always #5 clk = ~clk;`
//      generator, the `initial` reset block, the simulation time-limit
//      block, AND the axi4lite_formal_driver instantiation below -- the
//      tool supplies clock/reset itself via its own `clock`/`reset`
//      commands, and every master-driven AXI signal becomes a top-level
//      input port -- a free variable constrained only by
//      axi4lite_assumptions.sv's `assume
//      property` checks. (The randomized driver must also be excluded
//      here, not just clk/reset -- its $urandom-based next-state logic
//      isn't proof-friendly and would artificially restrict the state
//      space a real formal engine should explore exhaustively.) See
//      sim/formal_questa.do for the qverify script that sets this
//      define.
//   2. Bounded/simulation-based assertion checking (QuestaSim, or any
//      simulator run as a smoke check before a real formal tool is
//      available): compile without the define (the default), and this
//      becomes a self-contained, randomly-driven testbench that still
//      exercises every assume/assert pair -- see sim/Makefile's `formal`
//      target.
// ============================================================================

`timescale 1ns/1ps

// Under +define+QUESTA_FORMAL, clk/rst_n and every master-driven AXI
// signal are top-level input ports -- the formal tool's primary inputs --
// rather than undriven internal nets (qverify flags those as
// DECLARATION_UNDRIVEN). In flow #2 they stay internal, driven by the
// clock/reset blocks and axi4lite_formal_driver below.
module formal_tb
`ifdef QUESTA_FORMAL
  (clk, rst_n, awaddr, awvalid, wdata, wstrb, wvalid, bready, araddr, arvalid, rready)
`endif
;

`ifdef QUESTA_FORMAL
  `define FTB_FREE input logic
`else
  `define FTB_FREE logic
`endif

  localparam int ADDR_WIDTH = 8;
  // 32 or 64 -- set via +define+AXI4LITE_DATA_WIDTH=<n> (sim/Makefile's
  // DATA_WIDTH variable); 32 if not given.
`ifndef AXI4LITE_DATA_WIDTH
  `define AXI4LITE_DATA_WIDTH 32
`endif
  localparam int DATA_WIDTH = `AXI4LITE_DATA_WIDTH;
  localparam int NUM_REGS   = 16;

  // ------------------------------------------------------------------
  // DUT signals (`FTB_FREE: master side / clock / reset, see above)
  // ------------------------------------------------------------------
  `FTB_FREE                    clk;
  `FTB_FREE                    rst_n;

  `FTB_FREE [ADDR_WIDTH-1:0]   awaddr;
  `FTB_FREE                    awvalid;
  logic                        awready;

  `FTB_FREE [DATA_WIDTH-1:0]   wdata;
  `FTB_FREE [DATA_WIDTH/8-1:0] wstrb;
  `FTB_FREE                    wvalid;
  logic                        wready;

  logic [1:0]                  bresp;
  logic                        bvalid;
  `FTB_FREE                    bready;

  `FTB_FREE [ADDR_WIDTH-1:0]   araddr;
  `FTB_FREE                    arvalid;
  logic                        arready;

  logic [DATA_WIDTH-1:0]       rdata;
  logic [1:0]                  rresp;
  logic                        rvalid;
  `FTB_FREE                    rready;

`undef FTB_FREE

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
  // Compiled out under +define+QUESTA_FORMAL: there every master-driven
  // AXI signal is a top-level input (hence free), constrained purely via
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
  // Environment constraints. FORMAL_NO_ASSUMPTIONS compiles them out
  // (sim/Makefile's formal-verify-noassume) to check which proofs
  // actually depend on them.
  // ------------------------------------------------------------------
`ifndef FORMAL_NO_ASSUMPTIONS
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
`endif

  // ------------------------------------------------------------------
  // Blackbox protocol checks (AXI ports only)
  // ------------------------------------------------------------------
  axi4lite_blackbox_protocol #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .NUM_REGS   (NUM_REGS)
  ) u_bb_protocol (
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
    .rready  (rready)
  );

  // ------------------------------------------------------------------
  // Blackbox end-to-end data check (AXI ports only)
  // ------------------------------------------------------------------
  axi4lite_blackbox_data #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .NUM_REGS   (NUM_REGS)
  ) u_bb_data (
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
    .rready  (rready)
  );

  // ------------------------------------------------------------------
  // Whitebox data checks (regfile wired directly to dut.regfile)
  // ------------------------------------------------------------------
  axi4lite_whitebox_regfile #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .NUM_REGS   (NUM_REGS)
  ) u_wb_regfile (
    .clk     (clk),
    .rst_n   (rst_n),
    .awaddr  (awaddr),
    .awvalid (awvalid),
    .awready (awready),
    .wdata   (wdata),
    .wstrb   (wstrb),
    .wvalid  (wvalid),
    .wready  (wready),
    .bvalid  (bvalid),
    .araddr  (araddr),
    .arvalid (arvalid),
    .arready (arready),
    .rdata   (rdata),
    .regfile (dut.regfile)
  );

  // ------------------------------------------------------------------
  // Reachability coverage for spec rules, which have no
  // assert/assume of their own, confirming the proof actually reaches these
  // scenarios rather than vacuously passing.
  // ------------------------------------------------------------------
  axi4lite_covers #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
  ) u_covers (
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
    .rready  (rready)
  );

endmodule
