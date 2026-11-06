// ============================================================================
// axi4lite_signature.sv
//
// Behaviour signature for mutation testing (flow #2 only, instantiated by
// formal_tb.sv): a running hash of what the DUT shows at its ports, printed at
// the end of the run. Two runs on the same seed with the same signature showed
// no difference in behaviour, so a mutant that matches the clean design is
// reported as "no difference seen", not as missed.
//
// Only what a master can observe goes in: VALID and READY every cycle out of
// reset, BRESP only while BVALID, RDATA / RRESP only while RVALID. Hashed bit by
// bit over 4-state values, so an X never looks like a 0.
// ============================================================================
`timescale 1ns/1ps

module axi4lite_signature #(
  parameter int DATA_WIDTH = 32
)(
  input logic                  clk,
  input logic                  rst_n,
  input logic                  awready,
  input logic                  wready,
  input logic                  arready,
  input logic                  bvalid,
  input logic [1:0]            bresp,
  input logic                  rvalid,
  input logic [DATA_WIDTH-1:0] rdata,
  input logic [1:0]            rresp
);

  // FNV-1a step per bit; 0, 1 and anything else are three different inputs
  function automatic logic [31:0] fnv(input logic [31:0] h, input logic b);
    logic [7:0] code;
    code = (b === 1'b0) ? 8'd0 : (b === 1'b1) ? 8'd1 : 8'd2;
    return (h ^ 32'(code)) * 32'h0100_0193;
  endfunction

  logic [31:0] hash = 32'h811c_9dc5;

  always @(posedge clk) begin
    if (rst_n === 1'b1) begin
      automatic logic [31:0] h = hash;
      h = fnv(h, awready);
      h = fnv(h, wready);
      h = fnv(h, arready);
      h = fnv(h, bvalid);
      h = fnv(h, rvalid);
      if (bvalid !== 1'b0)
        for (int i = 0; i < 2; i++) h = fnv(h, bresp[i]);
      if (rvalid !== 1'b0) begin
        for (int i = 0; i < 2; i++) h = fnv(h, rresp[i]);
        for (int i = 0; i < DATA_WIDTH; i++) h = fnv(h, rdata[i]);
      end
      hash = h;
    end
  end

  final $display("FORMAL SIM SIGNATURE: %08h", hash);

endmodule
