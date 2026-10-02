// ============================================================================
// axi4lite_blackbox_data.sv
//
// Blackbox end-to-end data check for axi4lite_slave: a read of a register
// returns the value built up by the writes to it that have completed
// (B handshake, OKAY), starting from the reset value 0.
//
// Sees only the AXI ports -- nothing inside the DUT -- so it keeps holding
// across RTL restructuring (storage moved out of the slave, extra pipeline
// stages), unlike the checks in axi4lite_whitebox_regfile.sv.
//
// Symbolic address: instead of modelling every register, track one word
// index `sym_idx`. Under +define+QUESTA_FORMAL it is a register with no
// reset that only holds its value, so its initial value is free and the
// proof covers every index at once. In simulation (flow #2) it is picked
// at random per seed.
//
// Timing-agnostic: AW, W and AR/R are queued at their handshakes in
// axi4lite_fifo_model instances (MAX_OUTSTANDING deep, the most the
// current DUT accepts; their a_no_overflow fires if a DUT ever exceeds
// it). That every B / R answers an earlier request is checked in
// axi4lite_blackbox_protocol.sv, not repeated here. A read is
// only checked when no write to sym_idx is outstanding at its AR
// handshake and none is accepted while it is in flight -- AXI4-Lite
// allows either the old or the new value in that window.
// ============================================================================
module axi4lite_blackbox_data
  import axi4lite_types_pkg::*;
#(
  parameter int ADDR_WIDTH      = 8,
  parameter int DATA_WIDTH      = 32,
  parameter int NUM_REGS        = 16,
  parameter int MAX_OUTSTANDING = 2
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

  localparam int ADDR_LSB = $clog2(DATA_WIDTH / 8);
  localparam int IDX_W    = ADDR_WIDTH - ADDR_LSB;
  localparam int STRB_W   = DATA_WIDTH / 8;
  localparam int CNT_W    = $clog2(MAX_OUTSTANDING + 1);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  wire aw_hs = awvalid && awready;
  wire w_hs  = wvalid  && wready;
  wire b_hs  = bvalid  && bready;
  wire ar_hs = arvalid && arready;
  wire r_hs  = rvalid  && rready;

  // ------------------------------------------------------------------
  // Symbolic word index
  // ------------------------------------------------------------------
  logic [IDX_W-1:0] sym_idx;
`ifdef QUESTA_FORMAL
  always_ff @(posedge clk) sym_idx <= sym_idx;
`else
  initial sym_idx = IDX_W'($urandom_range(NUM_REGS - 1, 0));
`endif

  wire aw_hit = (awaddr[ADDR_WIDTH-1:ADDR_LSB] == sym_idx);
  wire ar_hit = (araddr[ADDR_WIDTH-1:ADDR_LSB] == sym_idx);

  // ------------------------------------------------------------------
  // Write side: AW queue (does the address hit sym_idx?) and W queue
  // (data/strobe), popped together by each B handshake.
  // ------------------------------------------------------------------
  logic                  aw_hit_head;
  logic [DATA_WIDTH-1:0] w_data_head;
  logic [STRB_W-1:0]     w_strb_head;
  logic [CNT_W-1:0]      aw_cnt, w_cnt;

  axi4lite_fifo_model #(.W(1), .DEPTH(MAX_OUTSTANDING)) u_aw_q (
    .clk, .rst_n, .push(aw_hs), .din(aw_hit), .pop(b_hs),
    .clr_flag(1'b0), .head(aw_hit_head), .count(aw_cnt));
  axi4lite_fifo_model #(.W(STRB_W + DATA_WIDTH), .DEPTH(MAX_OUTSTANDING)) u_w_q (
    .clk, .rst_n, .push(w_hs), .din({wstrb, wdata}), .pop(b_hs),
    .clr_flag(1'b0), .head({w_strb_head, w_data_head}), .count(w_cnt));

  // ------------------------------------------------------------------
  // Reference value of register sym_idx. A write to it takes effect at
  // its B handshake (OKAY only); exp_now includes a commit on this edge.
  // ------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] exp_q, exp_now;
  wire commit = b_hs && aw_cnt != 0 && w_cnt != 0 && aw_hit_head
                && bresp == AXI_RESP_OKAY;

  always_comb begin
    exp_now = exp_q;
    if (commit)
      for (int b = 0; b < STRB_W; b++)
        if (w_strb_head[b]) exp_now[b*8 +: 8] = w_data_head[b*8 +: 8];
  end

  // Writes to sym_idx accepted on AW and not yet answered on B. After
  // this edge's B (which retires the head) and AW, one is outstanding iff
  // sym_wr_pending.
  logic [CNT_W-1:0] sym_wr_cnt;
  wire  sym_wr_retire  = b_hs && aw_cnt != 0 && aw_hit_head;
  wire  sym_wr_accept  = aw_hs && aw_hit;
  wire  sym_wr_pending = (sym_wr_cnt - sym_wr_retire) != 0 || sym_wr_accept;

  // ------------------------------------------------------------------
  // Read side: per accepted AR, {expected value, check it?}, popped by
  // each R handshake. A write to sym_idx accepted while reads are in
  // flight clears their check bit (bit 0): either value is legal then.
  // ------------------------------------------------------------------
  logic                  rd_chk_head;
  logic [DATA_WIDTH-1:0] rd_exp_head;
  logic [CNT_W-1:0]      rd_cnt;

  axi4lite_fifo_model #(.W(DATA_WIDTH + 1), .DEPTH(MAX_OUTSTANDING)) u_rd_q (
    .clk, .rst_n, .push(ar_hs), .din({exp_now, ar_hit && !sym_wr_pending}),
    .pop(r_hs), .clr_flag(sym_wr_accept),
    .head({rd_exp_head, rd_chk_head}), .count(rd_cnt));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      exp_q      <= '0;
      sym_wr_cnt <= '0;
    end else begin
      exp_q      <= exp_now;
      sym_wr_cnt <= sym_wr_cnt - sym_wr_retire + sym_wr_accept;
    end
  end

  // ------------------------------------------------------------------
  // The end-to-end check
  // ------------------------------------------------------------------
  a_e2e_read_data: assert property (
    r_hs && rd_cnt != 0 && rd_chk_head && rresp == AXI_RESP_OKAY
    |-> rdata == rd_exp_head
  ) else $error("Read of word %0d returned 0x%0h, expected 0x%0h from completed writes",
                sym_idx, rdata, rd_exp_head);

  // ------------------------------------------------------------------
  // Non-vacuity: the check fires on real, merged data, and sym_idx is
  // actually free (would be uncoverable if the tool fixed it at 0).
  // ------------------------------------------------------------------
  cp_e2e_read_checked_nonzero: cover property (
    r_hs && rd_cnt != 0 && rd_chk_head && rresp == AXI_RESP_OKAY && rd_exp_head != '0
  );
  cp_e2e_partial_strobe_merge: cover property (
    commit && exp_q != '0 && w_strb_head != '0 && w_strb_head != '1
  );
  cp_e2e_sym_last_reg: cover property (
    sym_idx == IDX_W'(NUM_REGS - 1) && r_hs && rd_cnt != 0 && rd_chk_head
  );

endmodule
