// ============================================================================
// axi4lite_formal_driver.sv
//
// Legal-master constrained-random stimulus for formal_tb.sv's flow #2
// (plain-simulator smoke check, e.g. Verilator). `assume property` in
// axi4lite_assumptions.sv only *checks* legal master behavior in a
// simulator -- it doesn't *drive* it, so without this module every input
// just sits at its reset value and none of the assume/assert/cover
// properties ever get exercised.
//
// Each channel is driven so it can never trip the m_* assumptions by
// construction:
//   - VALID forced low during reset.
//   - once VALID is asserted, it (and the payload) only changes on the
//     cycle the matching READY accepts it -- never while waiting.
//   - the decision to raise VALID never looks at READY first.
// BREADY/RREADY carry no such stability rule, so they're free every cycle.
// ============================================================================
module axi4lite_formal_driver #(
  parameter int ADDR_WIDTH = 8,
  parameter int DATA_WIDTH = 32,
  parameter int NUM_REGS   = 16
)(
  input  logic                    clk,
  input  logic                    rst_n,

  output logic [ADDR_WIDTH-1:0]   awaddr,
  output logic                    awvalid,
  input  logic                    awready,

  output logic [DATA_WIDTH-1:0]   wdata,
  output logic [DATA_WIDTH/8-1:0] wstrb,
  output logic                    wvalid,
  input  logic                    wready,

  output logic                    bready,

  output logic [ADDR_WIDTH-1:0]   araddr,
  output logic                    arvalid,
  input  logic                    arready,

  output logic                    rready
);

  localparam int ADDR_LSB = $clog2(DATA_WIDTH / 8);

  // In-range roughly half the time regardless of how NUM_REGS compares to
  // the full ADDR_WIDTH span, so the OKAY and SLVERR paths both get
  // exercised often rather than one being a rare accident of uniform
  // randomization over the whole address bus.
  function automatic logic [ADDR_WIDTH-1:0] rand_addr();
    automatic logic [ADDR_WIDTH-1:0] a;
    a = ADDR_WIDTH'($urandom());
    if ($urandom_range(1))
      a = a % (ADDR_WIDTH'(NUM_REGS) << ADDR_LSB);   // fold into range
    return a;
  endfunction

  // ---- AW ------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      awvalid <= 1'b0;
      awaddr  <= '0;
    end else if (awvalid && awready) begin
      awvalid <= logic'($urandom_range(1));
      awaddr  <= rand_addr();
    end else if (!awvalid && $urandom_range(9) < 6) begin
      awvalid <= 1'b1;
      awaddr  <= rand_addr();
    end
  end

  // ---- W -----------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wvalid <= 1'b0;
      wdata  <= '0;
      wstrb  <= '0;
    end else if (wvalid && wready) begin
      wvalid <= logic'($urandom_range(1));
      wdata  <= DATA_WIDTH'($urandom());
      wstrb  <= (DATA_WIDTH/8)'($urandom_range((1 << (DATA_WIDTH/8)) - 1));
    end else if (!wvalid && $urandom_range(9) < 6) begin
      wvalid <= 1'b1;
      wdata  <= DATA_WIDTH'($urandom());
      wstrb  <= (DATA_WIDTH/8)'($urandom_range((1 << (DATA_WIDTH/8)) - 1));
    end
  end

  // ---- AR ------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      arvalid <= 1'b0;
      araddr  <= '0;
    end else if (arvalid && arready) begin
      arvalid <= logic'($urandom_range(1));
      araddr  <= rand_addr();
    end else if (!arvalid && $urandom_range(9) < 6) begin
      arvalid <= 1'b1;
      araddr  <= rand_addr();
    end
  end

  // ---- BREADY / RREADY ------------------------------------------------------
  // No stability rule on READY -- free every cycle is legal, and lets the
  // covers for "ready before/after valid" get hit either way.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bready <= 1'b0;
      rready <= 1'b0;
    end else begin
      bready <= logic'($urandom_range(1));
      rready <= logic'($urandom_range(1));
    end
  end

endmodule
