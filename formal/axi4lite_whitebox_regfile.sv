// ============================================================================
// axi4lite_whitebox_regfile.sv
//
// Whitebox data checks for axi4lite_slave, against the DUT's internal
// register file (connect .regfile(dut.regfile) in formal_tb.sv): WSTRB
// byte lanes, read data, and the regfile frame condition. These depend on
// the DUT's storage and timing and need rewiring whenever the RTL is
// restructured; axi4lite_blackbox_data.sv checks the same data end to end
// from the AXI ports alone.
// ============================================================================
module axi4lite_whitebox_regfile #(
  parameter int ADDR_WIDTH = 8,
  parameter int DATA_WIDTH = 32,
  parameter int NUM_REGS   = 16
)(
  input logic                    clk,
  input logic                    rst_n,

  input logic [ADDR_WIDTH-1:0]   awaddr,
  input logic                    awvalid,
  input logic                    awready,

  input logic [DATA_WIDTH-1:0]   wdata,
  input logic [DATA_WIDTH/8-1:0] wstrb,
  input logic                    wvalid,
  input logic                    wready,

  input logic                    bvalid,

  input logic [ADDR_WIDTH-1:0]   araddr,
  input logic                    arvalid,
  input logic                    arready,

  input logic [DATA_WIDTH-1:0]   rdata,

  input logic [DATA_WIDTH-1:0]   regfile [NUM_REGS]
);

  localparam int ADDR_LSB = $clog2(DATA_WIDTH / 8);

  function automatic bit in_range(logic [ADDR_WIDTH-1:0] addr);
    return (addr[ADDR_WIDTH-1:ADDR_LSB] < NUM_REGS);
  endfunction

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // Address of the write in progress (same latch as in
  // axi4lite_blackbox_protocol.sv).
  logic [ADDR_WIDTH-1:0] awaddr_latched_ref;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                  awaddr_latched_ref <= '0;
    else if (awvalid && awready) awaddr_latched_ref <= awaddr;
  end

  // Write-strobe byte-lane correctness, whitebox check against the
  // connected `regfile` array.
  logic [DATA_WIDTH-1:0]   wdata_latched_ref;
  logic [DATA_WIDTH/8-1:0] wstrb_latched_ref;
  logic [DATA_WIDTH-1:0]   regfile_before_write [NUM_REGS];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wdata_latched_ref    <= '0;
      wstrb_latched_ref    <= '0;
      regfile_before_write <= '{default: '0};
    end else begin
      if (wvalid && wready) begin
        wdata_latched_ref <= wdata;
        wstrb_latched_ref <= wstrb;
      end
      if (awvalid && awready) regfile_before_write <= regfile;
    end
  end

  genvar gb;
  generate
    for (gb = 0; gb < DATA_WIDTH/8; gb++) begin : g_strobe_byte_check
      a_write_enabled_byte_updated: assert property (
        $rose(bvalid) && in_range(awaddr_latched_ref) && wstrb_latched_ref[gb]
        |-> regfile[awaddr_latched_ref[ADDR_WIDTH-1:ADDR_LSB]][gb*8+:8] == wdata_latched_ref[gb*8+:8]
      ) else $error("Byte lane %0d enabled by WSTRB was not written with WDATA", gb);

      a_write_disabled_byte_preserved: assert property (
        $rose(bvalid) && in_range(awaddr_latched_ref) && !wstrb_latched_ref[gb]
        |-> regfile[awaddr_latched_ref[ADDR_WIDTH-1:ADDR_LSB]][gb*8+:8]
              == regfile_before_write[awaddr_latched_ref[ADDR_WIDTH-1:ADDR_LSB]][gb*8+:8]
      ) else $error("Byte lane %0d masked by WSTRB was modified anyway", gb);
    end
  endgenerate

  // Frame condition: a register may change only on the cycle an in-range
  // write to its own index fires (the regfile update lands on the same
  // edge BVALID rises). Catches what the byte-lane checks above cannot:
  // an out-of-range write touching any register, or a write also
  // clobbering a register other than the addressed one.
  genvar gr;
  generate
    for (gr = 0; gr < NUM_REGS; gr++) begin : g_regfile_frame
      a_regfile_changes_only_on_own_write: assert property (
        !$stable(regfile[gr])
        |-> $rose(bvalid) && in_range(awaddr_latched_ref)
            && awaddr_latched_ref[ADDR_WIDTH-1:ADDR_LSB] == gr
      ) else $error("regfile[%0d] changed without an in-range write to it", gr);
    end
  endgenerate

  // Read-data correctness, whitebox against `regfile`. RDATA is the
  // register's value at the AR handshake edge -- a write firing on that
  // same edge is not yet visible -- hence $past, which also samples
  // araddr at the handshake rather than one cycle later.
  a_read_data_matches_regfile: assert property (
    (arvalid && arready && in_range(araddr))
    |=> rdata == $past(regfile[araddr[ADDR_WIDTH-1:ADDR_LSB]])
  ) else $error("In-range read returned data different from the addressed register");

endmodule
