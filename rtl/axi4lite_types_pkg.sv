// ============================================================================
// axi4lite_types_pkg.sv
//
// Synthesizable AXI4-Lite protocol definitions, shared by the RTL, the
// UVM/simple testbenches and the formal environment. Must be compiled
// before any file that imports it.
// ============================================================================

package axi4lite_types_pkg;

  // BRESP / RRESP encoding (AXI spec A3.4.4)
  typedef enum logic [1:0] {
    AXI_RESP_OKAY   = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11
  } axi_resp_e;

endpackage
