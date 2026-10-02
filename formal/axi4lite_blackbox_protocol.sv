// ============================================================================
// axi4lite_blackbox_protocol.sv
//
// Blackbox protocol checks for axi4lite_slave: handshake rules, response
// codes and X checks, from the AXI ports alone. Data correctness lives in
// axi4lite_blackbox_data.sv (end to end) and axi4lite_whitebox_regfile.sv
// (against the DUT's internal register file).
//
// ============================================================================
module axi4lite_blackbox_protocol #(
  parameter int ADDR_WIDTH = 8,
  parameter int DATA_WIDTH = 32,
  parameter int NUM_REGS   = 16,
  // Most accepted-but-unanswered requests per channel the bookkeeping
  // below tracks (each axi4lite_fifo_model's a_no_overflow fires if a DUT
  // exceeds it).
  parameter int MAX_OUTSTANDING = 2,
  // "Must not wait for READY" is checked as: a pending response appears
  // within RESP_TIMEOUT cycles even if READY stays low. A deadlock bound,
  // not the DUT's latency (1-2 cycles today).
  parameter int RESP_TIMEOUT    = 8,
  // An idle slave raises AWREADY / WREADY / ARREADY within READY_TIMEOUT
  // cycles of the matching VALID (section 4.4). Also a deadlock bound.
  parameter int READY_TIMEOUT   = 8
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

  import axi4lite_types_pkg::*;

  
  localparam int ADDR_LSB = $clog2(DATA_WIDTH / 8);
  
  function automatic bit in_range(logic [ADDR_WIDTH-1:0] addr);
    return (addr[ADDR_WIDTH-1:ADDR_LSB] < NUM_REGS);
  endfunction

  
  // One-shot check at elaboration time, not a formal property.
  initial begin
    assert (DATA_WIDTH == 32 || DATA_WIDTH == 64) // AXI4-Lite data bus width must be 32 or 64 bits.
      else $fatal(1, "axi4lite_blackbox_protocol: DATA_WIDTH=%0d is not legal, (32 or 64 are desired)", DATA_WIDTH);
  end

  // Module-level default clocking and reset for all properties below. 
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // No X on the slave's outputs: control always, payload while VALID.
  // (RDATA is covered by a_rvalid_requires_rdata, rule 4.3.3 below.)
  a_no_x_awready:  assert property (!$isunknown(awready));

  a_no_x_wready:   assert property (!$isunknown(wready));

  a_no_x_bvalid:   assert property (!$isunknown(bvalid));
  a_no_x_bresp:    assert property (bvalid |-> !$isunknown(bresp));

  a_no_x_arready:  assert property (!$isunknown(arready));

  a_no_x_rvalid:   assert property (!$isunknown(rvalid));
  a_no_x_rresp:    assert property (rvalid |-> !$isunknown(rresp));

  // ****************************************************************************
  // ***** 4.1 General rules (slave-driven channels: B, R) **********************
  // ****************************************************************************

  // 1. BVALID and RVALID must be LOW during reset.
  // 
  // Explicitly disable the `disable iff` for this one, 
  // since that would mask exactly the cycle under test.
  a_bvalid_low_in_reset: assert property (disable iff (1'b0) !rst_n |-> !bvalid) 
    else $error("BVALID not held low during reset");

  a_rvalid_low_in_reset: assert property (disable iff (1'b0) !rst_n |-> !rvalid)
    else $error("RVALID not held low during reset");


  // 2. Once VALID is asserted, it must remain asserted, and the
  //    accompanying payload (address/data/control) must remain stable,
  //    until the rising clock edge after READY is seen HIGH.
  a_bvalid_stable: assert property (bvalid && !bready |=> bvalid && $stable(bresp))
    else $error("BVALID/BRESP deasserted or changed before BREADY");

  a_rvalid_stable: assert property (rvalid && !rready |=> rvalid && $stable(rdata) && $stable(rresp))
    else $error("RVALID/RDATA/RRESP deasserted or changed before RREADY");

  // ****************************************************************************
  // *********** 4.2 Specific rules for AW / W / B -- slave side **************** 
  // ****************************************************************************
  // Request bookkeeping, timing-independent: each AW / W / AR handshake
  // is queued and each B / R handshake retires the oldest one (AXI4-Lite
  // answers in order). The AW and AR queues hold one bit per request:
  // was its address in range. Counts are of requests accepted on an
  // earlier edge and not yet answered.
  localparam int CNT_W = $clog2(MAX_OUTSTANDING + 1);

  wire aw_hs = awvalid && awready;
  wire w_hs  = wvalid  && wready;
  wire b_hs  = bvalid  && bready;
  wire ar_hs = arvalid && arready;
  wire r_hs  = rvalid  && rready;

  logic             aw_inr_head, ar_inr_head;   // oldest request in range?
  logic             w_unused;
  logic [CNT_W-1:0] aw_cnt, w_cnt, ar_cnt;

  axi4lite_fifo_model #(.W(1), .DEPTH(MAX_OUTSTANDING)) u_aw_q (
    .clk, .rst_n, .push(aw_hs), .din(in_range(awaddr)), .pop(b_hs),
    .clr_flag(1'b0), .head(aw_inr_head), .count(aw_cnt));
  axi4lite_fifo_model #(.W(1), .DEPTH(MAX_OUTSTANDING)) u_w_q (
    .clk, .rst_n, .push(w_hs), .din(1'b0), .pop(b_hs),
    .clr_flag(1'b0), .head(w_unused), .count(w_cnt));
  axi4lite_fifo_model #(.W(1), .DEPTH(MAX_OUTSTANDING)) u_ar_q (
    .clk, .rst_n, .push(ar_hs), .din(in_range(araddr)), .pop(r_hs),
    .clr_flag(1'b0), .head(ar_inr_head), .count(ar_cnt));

  // 1. The slave must wait for AWVALID, AWREADY, WVALID, and
  //    WREADY to all have been asserted (AW and W handshakes both
  //    complete) before asserting BVALID.
  a_bvalid_requires_aw_and_w: assert property (bvalid |-> aw_cnt != 0 && w_cnt != 0)
    else $error("BVALID asserted without an earlier, unanswered AW and W handshake");

  // 2. The slave must not wait for BREADY before asserting BVALID.
  a_bvalid_not_wait_bready: assert property (
    aw_cnt != 0 && w_cnt != 0 |-> ##[0:RESP_TIMEOUT] bvalid
  ) else $error("No BVALID within RESP_TIMEOUT=%0d cycles of a complete AW+W -- possible BREADY dependency", RESP_TIMEOUT);


  // 3. DUT design rule, stricter than the spec: BRESP is OKAY or SLVERR.
  //    AXI4-Lite also allows DECERR (only EXOKAY is excluded); this slave
  //    never produces it, so a DECERR here is a DUT bug, not a protocol one.
  a_bresp_legal_value: assert property (bvalid |-> (bresp == AXI_RESP_OKAY || bresp == AXI_RESP_SLVERR))
    else $error("BRESP is neither OKAY nor SLVERR while BVALID is asserted");

  // Response code for the write being answered (oldest outstanding),
  // against the DUT's address range.
  a_write_okay_in_range: assert property (
    bvalid && aw_cnt != 0 && aw_inr_head |-> bresp == AXI_RESP_OKAY
  ) else $error("In-range write did not return OKAY");

  a_write_slverr_out_of_range: assert property (
    bvalid && aw_cnt != 0 && !aw_inr_head |-> bresp == AXI_RESP_SLVERR
  ) else $error("Out-of-range write did not return SLVERR");

  // ****************************************************************************
  // ************ 4.3 Specific rules for AR / R -- slave side ******************* 
  // ****************************************************************************

  // 1. The slave must wait for both ARVALID and ARREADY to be
  //    asserted before asserting RVALID.
  a_rvalid_requires_ar: assert property (rvalid |-> ar_cnt != 0)
    else $error("RVALID asserted without an earlier, unanswered AR handshake");

  // 2. The slave must not wait for RREADY before asserting
  //    RVALID.
  a_ar_leads_to_rvalid: assert property (ar_cnt != 0 |-> ##[0:RESP_TIMEOUT] rvalid)
    else $error("No RVALID within RESP_TIMEOUT=%0d cycles of an AR handshake -- possible RREADY dependency", RESP_TIMEOUT);

  // 3. The slave asserts RVALID only when it drives valid RDATA.
  a_rvalid_requires_rdata: assert property (rvalid |-> !$isunknown(rdata))
    else $error("RVALID asserted while RDATA is unknown");

  // Response code for the read being answered. rdata == 0 on SLVERR is a
  // DUT design rule; AXI leaves RDATA unspecified on an error response.
  a_read_okay_in_range: assert property (
    rvalid && ar_cnt != 0 && ar_inr_head |-> rresp == AXI_RESP_OKAY
  ) else $error("In-range read did not return OKAY");

  a_read_slverr_out_of_range: assert property (
    rvalid && ar_cnt != 0 && !ar_inr_head |-> (rresp == AXI_RESP_SLVERR && rdata == '0)
  ) else $error("Out-of-range read did not return SLVERR with rdata==0");

  // DUT design rule, read side (parallel to a_bresp_legal_value): RRESP is
  // OKAY or SLVERR, never DECERR, although AXI4-Lite would allow it.
  a_rresp_legal_value: assert property (rvalid |-> (rresp == AXI_RESP_OKAY || rresp == AXI_RESP_SLVERR))
    else $error("RRESP is neither OKAY nor SLVERR while RVALID is asserted");

  // ****************************************************************************
  // ************ 4.4 Request acceptance -- DUT design rules ********************
  // ****************************************************************************
  // AXI lets a slave hold READY low for as long as it likes, so a slave
  // that never accepts anything breaks no rule above: with no handshake,
  // nothing is ever checked. These close that gap for this DUT: with no
  // request of the same kind outstanding, a VALID is accepted within
  // READY_TIMEOUT cycles. Only when idle -- once a request is accepted,
  // the slave may legally stall on the master (a W that never comes, a
  // BREADY / RREADY held low). AW and W are independent here (this slave
  // never makes AWREADY wait for WVALID or the reverse, which AXI allows).
  a_awready_when_idle: assert property (
    awvalid && aw_cnt == 0 |-> ##[0:READY_TIMEOUT] awready
  ) else $error("Idle slave did not raise AWREADY within READY_TIMEOUT=%0d cycles", READY_TIMEOUT);

  a_wready_when_idle: assert property (
    wvalid && w_cnt == 0 |-> ##[0:READY_TIMEOUT] wready
  ) else $error("Idle slave did not raise WREADY within READY_TIMEOUT=%0d cycles", READY_TIMEOUT);

  a_arready_when_idle: assert property (
    arvalid && ar_cnt == 0 |-> ##[0:READY_TIMEOUT] arready
  ) else $error("Idle slave did not raise ARREADY within READY_TIMEOUT=%0d cycles", READY_TIMEOUT);



endmodule
