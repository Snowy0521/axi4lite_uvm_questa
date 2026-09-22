// ============================================================================
// axi4lite_covers.sv
//
// All `cover property` points for axi4lite_slave's formal environment.
// ============================================================================
module axi4lite_covers #(
  parameter int DATA_WIDTH = 32
)(
  input logic                    clk,
  input logic                    rst_n,

  input logic                    awvalid,
  input logic                    awready,

  input logic [DATA_WIDTH/8-1:0] wstrb,
  input logic                    wvalid,
  input logic                    wready,

  input logic [1:0]              bresp,
  input logic                    bvalid,
  input logic                    bready,

  input logic                    arvalid,
  input logic                    arready,

  input logic [1:0]              rresp,
  input logic                    rvalid,
  input logic                    rready
);

  localparam logic [1:0] OKAY   = 2'b00;
  localparam logic [1:0] SLVERR = 2'b10;

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // ****************************************************************************
  // **************************** 4.1 General rules *****************************
  // ****************************************************************************

  // 3. Transfer occurs only on a clock edge where VALID and READY 
  // are both HIGH on that channel.
  cp_aw_handshake_occurs:   cover property (awvalid && awready);
  cp_w_handshake_occurs:    cover property (wvalid && wready);
  cp_b_handshake_occurs:    cover property (bvalid && bready);
  cp_ar_handshake_occurs:   cover property (arvalid && arready);
  cp_r_handshake_occurs:    cover property (rvalid && rready);

  // 5. The receiver may assert READY either before or after VALID.
  cp_aw_ready_preasserted: cover property ($rose(awvalid) && awready);
  cp_aw_ready_after_valid: cover property (awvalid && !awready ##1 (awvalid throughout awready[->1]));

  cp_w_ready_preasserted: cover property ($rose(wvalid) && wready);
  cp_w_ready_after_valid: cover property (wvalid && !wready ##1 (wvalid throughout wready[->1]));

  cp_b_ready_preasserted: cover property ($rose(bvalid) && bready);
  cp_b_ready_after_valid: cover property (bvalid && !bready ##1 (bvalid throughout bready[->1]));

  cp_ar_ready_preasserted: cover property ($rose(arvalid) && arready);
  cp_ar_ready_after_valid: cover property (arvalid && !arready ##1 (arvalid throughout arready[->1]));

  cp_r_ready_preasserted: cover property ($rose(rvalid) && rready);
  cp_r_ready_after_valid: cover property (rvalid && !rready ##1 (rvalid throughout rready[->1]));


  // ****************************************************************************
  // *********** 4.2 Specific rules for AW / W / B ****************************** 
  // ****************************************************************************

  cp_write_okay:   cover property ($rose(bvalid) && bresp == OKAY);
  cp_write_slverr: cover property ($rose(bvalid) && bresp == SLVERR);

  //AWVALID/WVALID may arrive in either order or simultaneously. 
  cp_aw_before_w: cover property (
    (awvalid && awready && !(wvalid && wready)) ##1 (wvalid && wready)[->1]
  );
  cp_w_before_aw: cover property (
    (wvalid && wready && !(awvalid && awready)) ##1 (awvalid && awready)[->1]
  );
  cp_aw_w_same_cycle: cover property (awvalid && awready && wvalid && wready);

  // Write-strobe pattern coverage
  logic [DATA_WIDTH/8-1:0] wstrb_latched_ref;
  always_ff @(posedge clk) begin
    if (wvalid && wready) wstrb_latched_ref <= wstrb;
  end

  cp_wstrb_all_zero: cover property ($rose(bvalid) && wstrb_latched_ref == '0);
  cp_wstrb_partial:  cover property (
    $rose(bvalid) && wstrb_latched_ref != '0 && wstrb_latched_ref != '1
  );
  cp_wstrb_full: cover property ($rose(bvalid) && wstrb_latched_ref == '1);

  cp_aw_before_w_master: cover property ((awvalid && !wvalid) ##1 wvalid[->1]);
  cp_w_before_aw_master: cover property ((wvalid && !awvalid) ##1 awvalid[->1]);


  // ****************************************************************************
  // ***** 4.3 Specific rules for AR / R ****************************************
  // ****************************************************************************

  cp_read_okay:   cover property ($rose(rvalid) && rresp == OKAY);
  cp_read_slverr: cover property ($rose(rvalid) && rresp == SLVERR);

endmodule
