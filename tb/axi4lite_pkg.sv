// ============================================================================
// axi4lite_pkg.sv
//
// Bundles all class-based testbench code into one package. `include order
// matters here -- each file only depends on files listed before it.
// ============================================================================

package axi4lite_pkg;

  parameter int unsigned ADDR_WIDTH     = 8;
  parameter int unsigned DATA_WIDTH     = 32;
  //parameter int unsigned DATA_WIDTH     = 64;
  parameter int unsigned NUM_REGS       = 16;
  parameter int unsigned STRB_WIDTH     = DATA_WIDTH/8;
  parameter int unsigned ADDR_LSB       = $clog2(STRB_WIDTH);
  parameter int unsigned NUM_TXNS       = 100;   // number of transactions in the random traffic generator
  parameter int unsigned MAX_ADDR       = 2**ADDR_WIDTH-1;
  parameter int unsigned TIMEOUT_CYCLES = 20;
  parameter int unsigned NUM_SMOKE_TXNS  = 4;    // number of transactions in the smoke test


  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "axi4lite_txn.sv"
  `include "axi4lite_sequencer.sv"
  `include "axi4lite_sequences.sv"
  `include "axi4lite_driver.sv"
  `include "axi4lite_monitor.sv"
  `include "axi4lite_agent.sv"
  `include "axi4lite_scoreboard.sv"
  `include "axi4lite_coverage_collector.sv"
  `include "axi4lite_env.sv"
  `include "axi4lite_tests.sv"


endpackage
