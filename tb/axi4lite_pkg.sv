// ============================================================================
// axi4lite_pkg.sv
//
// Bundles all class-based testbench code into one package. `include order
// matters here -- each file only depends on files listed before it.
// ============================================================================

package axi4lite_pkg;

  // 32 or 64 -- set via +define+AXI4LITE_DATA_WIDTH=<n> (sim/Makefile's
  // DATA_WIDTH variable); 32 if not given.
`ifndef AXI4LITE_DATA_WIDTH
  `define AXI4LITE_DATA_WIDTH 32
`endif
  parameter int unsigned ADDR_WIDTH     = 8;
  parameter int unsigned DATA_WIDTH     = `AXI4LITE_DATA_WIDTH;
  parameter int unsigned NUM_REGS       = 16;
  parameter int unsigned STRB_WIDTH     = DATA_WIDTH/8;
  parameter int unsigned ADDR_LSB       = $clog2(STRB_WIDTH);
  parameter int unsigned NUM_TXNS       = 100;   // number of transactions in the random traffic generator
  parameter int unsigned MAX_ADDR       = 2**ADDR_WIDTH-1;
  parameter int unsigned TIMEOUT_CYCLES = 20;
  parameter int unsigned NUM_SMOKE_TXNS  = 4;    // number of transactions in the smoke test
  parameter int unsigned MAX_WORD       = MAX_ADDR >> ADDR_LSB;   // last word index in the address space

  // Bit patterns the coverage model asks for and the random sequence biases
  // toward: every data bit both 0 and 1 (all-zero/all-one and the two
  // alternating patterns), and the strobe shapes a byte-lane bug shows in.
  // Sized constants rather than '1 in bins / constraints: an unsized '1 in
  // a self-determined spot can mean a 1-bit 1, i.e. value 1, not all ones.
  parameter bit [DATA_WIDTH-1:0] DATA_ONES    = '1;
  parameter bit [DATA_WIDTH-1:0] DATA_ALT_A   = {DATA_WIDTH/2{2'b10}};   // 0xAAAA...
  parameter bit [DATA_WIDTH-1:0] DATA_ALT_5   = {DATA_WIDTH/2{2'b01}};   // 0x5555...
  parameter bit [STRB_WIDTH-1:0] STRB_FULL    = '1;
  parameter bit [STRB_WIDTH-1:0] STRB_LO_HALF = STRB_FULL >> (STRB_WIDTH/2);
  parameter bit [STRB_WIDTH-1:0] STRB_HI_HALF = STRB_FULL ^ STRB_LO_HALF;


  import axi4lite_types_pkg::*;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "axi4lite_txn.sv"
  `include "axi4lite_sequencer.sv"
  `include "axi4lite_sequences.sv"
  `include "axi4lite_driver.sv"
  `include "axi4lite_unaligned_driver.sv"
  `include "axi4lite_monitor.sv"
  `include "axi4lite_agent.sv"
  `include "axi4lite_scoreboard.sv"
  `include "axi4lite_coverage_collector.sv"
  `include "axi4lite_env.sv"
  `include "axi4lite_tests.sv"


endpackage
