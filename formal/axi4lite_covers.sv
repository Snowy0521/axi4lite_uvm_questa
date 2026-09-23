// ============================================================================
// axi4lite_covers.sv
//
// All `cover property` points for axi4lite_slave's formal environment.
// ============================================================================
module axi4lite_covers #(
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

  input logic [1:0]              bresp,
  input logic                    bvalid,
  input logic                    bready,

  input logic [ADDR_WIDTH-1:0]   araddr,
  input logic                    arvalid,
  input logic                    arready,

  input logic [DATA_WIDTH-1:0]   rdata,
  input logic [1:0]              rresp,
  input logic                    rvalid,
  input logic                    rready
);

  localparam logic [1:0] OKAY   = 2'b00;
  localparam logic [1:0] SLVERR = 2'b10;

  localparam int ADDR_LSB = $clog2(DATA_WIDTH / 8);

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
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                wstrb_latched_ref <= '0;
    else if (wvalid && wready) wstrb_latched_ref <= wstrb;
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

  // A read returns non-reset data (regfile resets to 0), i.e. a written
  // value made it back out -- keeps a_read_data_matches_regfile from
  // only ever being exercised against all-zero registers.
  cp_read_written_data: cover property ($rose(rvalid) && rresp == OKAY && rdata != '0);


  // ****************************************************************************
  // ***** Multi-transaction scenarios ******************************************
  // ****************************************************************************
  // Everything above is reachable with a single transaction; these need
  // two or more in sequence, or both channels busy at once.

  // Back-to-back: the next response follows the previous one's accept as
  // soon as the DUT allows.
  cp_back_to_back_writes: cover property ((bvalid && bready) ##[1:2] $rose(bvalid));
  cp_back_to_back_reads:  cover property ((rvalid && rready) ##1 (arvalid && arready));

  // A read issued right after a write completes.
  cp_read_after_write: cover property ((bvalid && bready) ##1 (arvalid && arready));

  // Read and write in flight together.
  cp_write_read_same_cycle: cover property (
    awvalid && awready && wvalid && wready && arvalid && arready
  );
  cp_b_and_r_pending: cover property (bvalid && rvalid);

  // Write-then-read-back: a full-strobe OKAY write, then a read of the
  // same register returning that (non-reset) data. Tracks the last such
  // write; the AW/W latches mirror the DUT's own.
  logic [ADDR_WIDTH-1:0] awaddr_q;
  logic [DATA_WIDTH-1:0] wdata_q, last_wr_data;
  logic [ADDR_WIDTH-1:0] last_wr_addr;
  logic                  last_wr_valid;
  logic                  bvalid_d;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      awaddr_q      <= '0;
      wdata_q       <= '0;
      last_wr_addr  <= '0;
      last_wr_data  <= '0;
      last_wr_valid <= 1'b0;
      bvalid_d      <= 1'b0;
    end else begin
      bvalid_d <= bvalid;
      if (awvalid && awready) awaddr_q <= awaddr;
      if (wvalid  && wready)  wdata_q  <= wdata;
      if (bvalid && !bvalid_d && bresp == OKAY && wstrb_latched_ref == '1) begin
        last_wr_addr  <= awaddr_q;
        last_wr_data  <= wdata_q;
        last_wr_valid <= 1'b1;
      end
    end
  end

  cp_write_then_read_back: cover property (
    (arvalid && arready && last_wr_valid && last_wr_data != '0 &&
     araddr[ADDR_WIDTH-1:ADDR_LSB] == last_wr_addr[ADDR_WIDTH-1:ADDR_LSB])
    ##1 (rvalid && rresp == OKAY && rdata == last_wr_data)
  );


  // ****************************************************************************
  // ***** Reset asserted mid-transaction ***************************************
  // ****************************************************************************
  // Requires rst_n to be free after init (formal verify -auto_constraint_off
  // in sim/formal_questa.do). `disable iff (1'b0)` for the same reason as
  // a_bvalid_low_in_reset: the default disable would mask the reset cycle.

  // Reset lands between the AW and W handshakes of a write.
  cp_reset_after_aw_before_w: cover property (disable iff (1'b0)
    (awvalid && awready && !(wvalid && wready)) ##1 !rst_n
  );
  // Reset lands while a response is waiting on the master.
  cp_reset_while_bvalid: cover property (disable iff (1'b0) (bvalid && !bready) ##1 !rst_n);
  cp_reset_while_rvalid: cover property (disable iff (1'b0) (rvalid && !rready) ##1 !rst_n);

  // The slave recovers: a full transaction completes after such a reset.
  cp_write_after_reset: cover property (disable iff (1'b0)
    (bvalid && !bready) ##1 !rst_n ##[1:$] $rose(bvalid)
  );
  cp_read_after_reset: cover property (disable iff (1'b0)
    (rvalid && !rready) ##1 !rst_n ##[1:$] $rose(rvalid)
  );

endmodule
