// ============================================================================
// axi4lite_slave.sv
//
// A simple AXI4-Lite slave with a small memory-mapped register
// file (NUM_REGS x DATA_WIDTH-bit registers).
//
// Supported behavior:
//   - Single-beat, DATA_WIDTH-bit-wide read/write transactions only
//   - DATA_WIDTH must be fixed at either 32-bit or 64-bit 
//   - WVALID/WDATA and AWVALID/AWADDR are accepted independently and matched
//   - Out-of-range address on write returns SLVERR and does NOT write
//   - Out-of-range address on read returns SLVERR (2'b10) with 0 data
// ===========================================================================

typedef enum logic [1:0] {
  AXI_RESP_OKAY = 2'b00,
  AXI_RESP_EXOKAY = 2'b01,
  AXI_RESP_SLVERR = 2'b10,
  AXI_RESP_DECERR = 2'b11
} axi_resp_e;

module axi4lite_slave #(
  parameter int ADDR_WIDTH = 8,     
  parameter int DATA_WIDTH = 32,
  //parameter int DATA_WIDTH = 64,
  parameter int NUM_REGS   = 16     
)(
  input  logic                    clk,
  input  logic                    rst_n,

  // Write address channel
  input  logic [ADDR_WIDTH-1:0]   awaddr,
  input  logic                    awvalid,
  output logic                    awready,

  // Write data channel
  input  logic [DATA_WIDTH-1:0]   wdata,
  input  logic [DATA_WIDTH/8-1:0] wstrb,
  input  logic                    wvalid,
  output logic                    wready,

  // Write response channel
  output logic [1:0]              bresp,
  output logic                    bvalid,
  input  logic                    bready,

  // Read address channel
  input  logic [ADDR_WIDTH-1:0]   araddr,
  input  logic                    arvalid,
  output logic                    arready,

  // Read data channel
  output logic [DATA_WIDTH-1:0]   rdata,
  output logic [1:0]              rresp,
  output logic                    rvalid,
  input  logic                    rready
);
  
  initial begin 
	  assert (DATA_WIDTH == 32 || DATA_WIDTH == 64)
	  else $fatal(1, "axi4lite_slave: DATA_WIDTH=%0d is not legal, must be 32 or 64", DATA_WIDTH);
  end   

  localparam int ADDR_LSB = $clog2(DATA_WIDTH / 8);
  // -----------------------------------------------------------------------
  // Register file
  // -----------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] regfile [NUM_REGS];

  // -----------------------------------------------------------------------
  // Write channel handshake state
  // AXI4-Lite allows AWVALID and WVALID to arrive independently; latch
  // whichever one shows up first, and fire the actual write once BOTH are
  // present.
  // -----------------------------------------------------------------------
  logic aw_hs_done, w_hs_done;
  logic [ADDR_WIDTH-1:0]   awaddr_latched;
  logic [DATA_WIDTH-1:0]   wdata_latched;
  logic [DATA_WIDTH/8-1:0] wstrb_latched;

  assign awready = !aw_hs_done;
  assign wready  = !w_hs_done;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // internal signals 
      aw_hs_done     <= 1'b0;
      w_hs_done      <= 1'b0;
      awaddr_latched <= '0;
      wdata_latched  <= '0;
      wstrb_latched  <= '0;

      // part of the output signals
      bvalid         <= 1'b0;
      bresp          <= 2'b00;

      // Register file: explicit reset removes reliance on
      // simulator-specific uninitialized-memory behavior (2-state tools
      // read 0, 4-state tools read X) -- deterministic, portable value
      // for a read of any never-written register, on every simulator.
      regfile        <= '{default: '0};
    end else begin
      // latch AW
      if (awvalid && awready) begin // cycle N
        awaddr_latched <= awaddr;
        aw_hs_done     <= 1'b1;
      end
      // latch W
      if (wvalid && wready) begin // cycle N
        wdata_latched <= wdata;
        wstrb_latched <= wstrb;
        w_hs_done     <= 1'b1;
      end

      // fire the actual write once both halves have arrived
      if (aw_hs_done && w_hs_done && !bvalid) begin // cycle N+1
        automatic int unsigned word_idx = awaddr_latched[ADDR_WIDTH-1: ADDR_LSB];
        if (word_idx < NUM_REGS) begin
          for (int b = 0; b < DATA_WIDTH/8; b++) begin
            if (wstrb_latched[b])
              regfile[word_idx][b*8 +: 8] <= wdata_latched[b*8 +: 8];
          end
          bresp <= AXI_RESP_OKAY; 
        end else begin
          bresp <= AXI_RESP_SLVERR; 
        end
        bvalid     <= 1'b1;
        aw_hs_done <= 1'b0;
        w_hs_done  <= 1'b0;
      end

      // clear bvalid once the master accepts the response
      if (bvalid && bready) // cycle N+2 
        bvalid <= 1'b0;
    end
  end

  // -----------------------------------------------------------------------
  // Read channel
  // -----------------------------------------------------------------------
  assign arready = !rvalid;   // accept a new read address once RVALID has cleared

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rvalid <= 1'b0;
      rdata  <= '0;
      rresp  <= 2'b00;
    end else begin
      if (arvalid && arready) begin
        automatic int unsigned word_idx = araddr[ADDR_WIDTH-1 : ADDR_LSB];
        if (word_idx < NUM_REGS) begin
          rdata <= regfile[word_idx];
          rresp <= AXI_RESP_OKAY;
        end else begin
          rdata <= '0;
          rresp <= AXI_RESP_SLVERR;
        end
        rvalid <= 1'b1;
      end else if (rvalid && rready) begin
        rvalid <= 1'b0;
      end
    end
  end

endmodule
