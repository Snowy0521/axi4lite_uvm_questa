// ============================================================================
// axi4lite_assumptions.sv
//
// All `assume property` constraints for axi4lite_slave's formal environment
// ============================================================================
module axi4lite_assumptions #(
  parameter int ADDR_WIDTH = 8,
  parameter int DATA_WIDTH = 32
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

  input logic                    bready,

  input logic [ADDR_WIDTH-1:0]   araddr,
  input logic                    arvalid,
  input logic                    arready,

  input logic                    rready
);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // Environment constraints to prevent X propagation from the master side.
  m_no_x_awvalid: assume property (!$isunknown(awvalid));
  m_no_x_awaddr:  assume property (awvalid |-> !$isunknown(awaddr));

  m_no_x_wvalid:  assume property (!$isunknown(wvalid));
  m_no_x_wdata:   assume property (wvalid  |-> !$isunknown(wdata));
  m_no_x_wstrb:   assume property (wvalid  |-> !$isunknown(wstrb));

  m_no_x_bready:  assume property (!$isunknown(bready));

  m_no_x_arvalid: assume property (!$isunknown(arvalid));
  m_no_x_araddr:  assume property (arvalid |-> !$isunknown(araddr));

  m_no_x_rready:  assume property (!$isunknown(rready));

  // ****************************************************************************
  // ***** 4.1 General rules (master-driven channels: AW, W, AR) **************** 
  // ****************************************************************************

  // 1. AWVALID, WVALID, and ARVALID signals must be LOW during reset.
  m_awvalid_low_in_reset: assume property (disable iff (1'b0) !rst_n |-> !awvalid);
  m_wvalid_low_in_reset:  assume property (disable iff (1'b0) !rst_n |-> !wvalid);
  m_arvalid_low_in_reset: assume property (disable iff (1'b0) !rst_n |-> !arvalid);


  // 2. Once VALID is asserted, it must remain asserted, and the
  //    accompanying payload (address/data/control) must remain stable,
  //    until the rising clock edge after READY is seen HIGH.
  // 
  // 4. The transmitter must not wait for READY before asserting VALID.
  m_awvalid_stable: assume property (awvalid && !awready |=> awvalid && $stable(awaddr));
  m_wvalid_stable:  assume property (wvalid && !wready |=> wvalid && $stable(wdata) && $stable(wstrb));
  m_arvalid_stable: assume property (arvalid && !arready |=> arvalid && $stable(araddr));

endmodule
