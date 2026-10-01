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
// Timing-agnostic: AW, W and AR/R are queued at their handshakes
// (MAX_OUTSTANDING deep, the most the current DUT accepts; the
// a_e2e_*_no_overflow asserts fire if a DUT ever exceeds it). A read is
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
  // (data/strobe), popped together by each B handshake -- AXI4-Lite
  // answers writes in order.
  // ------------------------------------------------------------------
  logic [MAX_OUTSTANDING-1:0] aw_hit_q, aw_hit_n;
  logic [CNT_W-1:0]           aw_cnt,   aw_cnt_n;
  logic [DATA_WIDTH-1:0]      w_data_q [MAX_OUTSTANDING];
  logic [DATA_WIDTH-1:0]      w_data_n [MAX_OUTSTANDING];
  logic [STRB_W-1:0]          w_strb_q [MAX_OUTSTANDING];
  logic [STRB_W-1:0]          w_strb_n [MAX_OUTSTANDING];
  logic [CNT_W-1:0]           w_cnt,    w_cnt_n;

  always_comb begin
    aw_hit_n = aw_hit_q;
    aw_cnt_n = aw_cnt;
    if (b_hs && aw_cnt != 0) begin
      aw_hit_n = aw_hit_n >> 1;
      aw_cnt_n = aw_cnt_n - 1'b1;
    end
    if (aw_hs && aw_cnt_n < MAX_OUTSTANDING) begin
      aw_hit_n[aw_cnt_n] = aw_hit;
      aw_cnt_n           = aw_cnt_n + 1'b1;
    end

    w_data_n = w_data_q;
    w_strb_n = w_strb_q;
    w_cnt_n  = w_cnt;
    if (b_hs && w_cnt != 0) begin
      for (int i = 0; i < MAX_OUTSTANDING - 1; i++) begin
        w_data_n[i] = w_data_n[i+1];
        w_strb_n[i] = w_strb_n[i+1];
      end
      w_cnt_n = w_cnt_n - 1'b1;
    end
    if (w_hs && w_cnt_n < MAX_OUTSTANDING) begin
      w_data_n[w_cnt_n] = wdata;
      w_strb_n[w_cnt_n] = wstrb;
      w_cnt_n           = w_cnt_n + 1'b1;
    end
  end

  // ------------------------------------------------------------------
  // Reference value of register sym_idx. A write to it takes effect at
  // its B handshake (OKAY only); exp_now includes a commit on this edge.
  // ------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] exp_q, exp_now;
  wire commit = b_hs && aw_cnt != 0 && w_cnt != 0 && aw_hit_q[0]
                && bresp == AXI_RESP_OKAY;

  always_comb begin
    exp_now = exp_q;
    if (commit)
      for (int b = 0; b < STRB_W; b++)
        if (w_strb_q[0][b]) exp_now[b*8 +: 8] = w_data_q[0][b*8 +: 8];
  end

  // A write to sym_idx is outstanding after this edge: accepted on AW
  // (now or earlier) and not answered on B (the head popped now is done).
  logic sym_wr_pending;
  always_comb begin
    sym_wr_pending = aw_hs && aw_hit;
    for (int i = 0; i < MAX_OUTSTANDING; i++)
      if (i < aw_cnt && !(i == 0 && b_hs) && aw_hit_q[i])
        sym_wr_pending = 1'b1;
  end

  // ------------------------------------------------------------------
  // Read side: per accepted AR, whether to check it and what to expect;
  // popped by each R handshake (in order).
  // ------------------------------------------------------------------
  logic [MAX_OUTSTANDING-1:0] rd_chk_q, rd_chk_n;
  logic [DATA_WIDTH-1:0]      rd_exp_q [MAX_OUTSTANDING];
  logic [DATA_WIDTH-1:0]      rd_exp_n [MAX_OUTSTANDING];
  logic [CNT_W-1:0]           rd_cnt,   rd_cnt_n;

  always_comb begin
    rd_chk_n = rd_chk_q;
    rd_exp_n = rd_exp_q;
    rd_cnt_n = rd_cnt;
    if (r_hs && rd_cnt != 0) begin
      rd_chk_n = rd_chk_n >> 1;
      for (int i = 0; i < MAX_OUTSTANDING - 1; i++)
        rd_exp_n[i] = rd_exp_n[i+1];
      rd_cnt_n = rd_cnt_n - 1'b1;
    end
    // A write to sym_idx accepted while reads are in flight: they may
    // legally return either value, so stop checking them.
    if (aw_hs && aw_hit)
      rd_chk_n = '0;
    if (ar_hs && rd_cnt_n < MAX_OUTSTANDING) begin
      rd_chk_n[rd_cnt_n] = ar_hit && !sym_wr_pending;
      rd_exp_n[rd_cnt_n] = exp_now;
      rd_cnt_n           = rd_cnt_n + 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_hit_q <= '0;
      aw_cnt   <= '0;
      w_data_q <= '{default: '0};
      w_strb_q <= '{default: '0};
      w_cnt    <= '0;
      exp_q    <= '0;
      rd_chk_q <= '0;
      rd_exp_q <= '{default: '0};
      rd_cnt   <= '0;
    end else begin
      aw_hit_q <= aw_hit_n;
      aw_cnt   <= aw_cnt_n;
      w_data_q <= w_data_n;
      w_strb_q <= w_strb_n;
      w_cnt    <= w_cnt_n;
      exp_q    <= exp_now;
      rd_chk_q <= rd_chk_n;
      rd_exp_q <= rd_exp_n;
      rd_cnt   <= rd_cnt_n;
    end
  end

  // ------------------------------------------------------------------
  // The end-to-end check
  // ------------------------------------------------------------------
  a_e2e_read_data: assert property (
    r_hs && rd_cnt != 0 && rd_chk_q[0] && rresp == AXI_RESP_OKAY
    |-> rdata == rd_exp_q[0]
  ) else $error("Read of word %0d returned 0x%0h, expected 0x%0h from completed writes",
                sym_idx, rdata, rd_exp_q[0]);

  // ------------------------------------------------------------------
  // Model sanity: every response matches an accepted request, and the
  // queues are deep enough for this DUT.
  // ------------------------------------------------------------------
  a_e2e_b_has_write: assert property (b_hs |-> aw_cnt != 0 && w_cnt != 0)
    else $error("B handshake without an accepted AW and W");
  a_e2e_r_has_read: assert property (r_hs |-> rd_cnt != 0)
    else $error("R handshake without an accepted AR");

  a_e2e_aw_no_overflow: assert property (aw_hs |-> aw_cnt < MAX_OUTSTANDING || b_hs)
    else $error("More than MAX_OUTSTANDING=%0d AWs outstanding", MAX_OUTSTANDING);
  a_e2e_w_no_overflow:  assert property (w_hs  |-> w_cnt  < MAX_OUTSTANDING || b_hs)
    else $error("More than MAX_OUTSTANDING=%0d Ws outstanding", MAX_OUTSTANDING);
  a_e2e_ar_no_overflow: assert property (ar_hs |-> rd_cnt < MAX_OUTSTANDING || r_hs)
    else $error("More than MAX_OUTSTANDING=%0d ARs outstanding", MAX_OUTSTANDING);

  // ------------------------------------------------------------------
  // Non-vacuity: the check fires on real, merged data, and sym_idx is
  // actually free (would be uncoverable if the tool fixed it at 0).
  // ------------------------------------------------------------------
  cp_e2e_read_checked_nonzero: cover property (
    r_hs && rd_cnt != 0 && rd_chk_q[0] && rresp == AXI_RESP_OKAY && rd_exp_q[0] != '0
  );
  cp_e2e_partial_strobe_merge: cover property (
    commit && exp_q != '0 && w_strb_q[0] != '0 && w_strb_q[0] != '1
  );
  cp_e2e_sym_last_reg: cover property (
    sym_idx == IDX_W'(NUM_REGS - 1) && r_hs && rd_cnt != 0 && rd_chk_q[0]
  );

endmodule
