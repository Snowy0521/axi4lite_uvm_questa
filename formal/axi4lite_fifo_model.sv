// ============================================================================
// axi4lite_fifo_model.sv
//
// In-order queue for the blackbox checkers' request bookkeeping: push an
// entry at a request handshake (AW / W / AR), pop the oldest at its
// response handshake (B / R) -- AXI4-Lite answers in order. Not part of
// the DUT; only observes.
//
// Within one edge: pop (ignored when empty), then clr_flag (clears bit 0
// of every entry still stored -- blackbox_data's "stop checking in-flight
// reads"), then push. `head` is only meaningful while `count != 0`.
// ============================================================================
module axi4lite_fifo_model #(
  parameter int W     = 1,
  parameter int DEPTH = 2
)(
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         push,
  input  logic [W-1:0]                 din,
  input  logic                         pop,
  input  logic                         clr_flag,
  output logic [W-1:0]                 head,
  output logic [$clog2(DEPTH+1)-1:0]   count
);

  localparam int CNT_W = $clog2(DEPTH + 1);

  logic [W-1:0]     mem_q [DEPTH];
  logic [W-1:0]     mem_n [DEPTH];
  logic [CNT_W-1:0] cnt_q, cnt_n;

  always_comb begin
    mem_n = mem_q;
    cnt_n = cnt_q;
    if (pop && cnt_q != 0) begin
      for (int i = 0; i < DEPTH - 1; i++)
        mem_n[i] = mem_n[i+1];
      cnt_n = cnt_n - 1'b1;
    end
    if (clr_flag)
      for (int i = 0; i < DEPTH; i++)
        mem_n[i][0] = 1'b0;
    if (push && cnt_n < DEPTH) begin
      mem_n[cnt_n] = din;
      cnt_n        = cnt_n + 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_q <= '{default: '0};
      cnt_q <= '0;
    end else begin
      mem_q <= mem_n;
      cnt_q <= cnt_n;
    end
  end

  assign head  = mem_q[0];
  assign count = cnt_q;

  // The DUT never has more than DEPTH requests outstanding; if a DUT
  // does, raise DEPTH (the checkers' MAX_OUTSTANDING) instead of letting
  // the model silently drop entries.
  a_no_overflow: assert property (
    @(posedge clk) disable iff (!rst_n) push |-> cnt_q < DEPTH || pop
  ) else $error("%m: more than DEPTH=%0d requests outstanding", DEPTH);

endmodule
