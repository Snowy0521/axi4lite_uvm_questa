// ============================================================================
// tb_simple.sv
//
// The simplest possible testbench for axi4lite_slave
//
// What it does:
//   1. Generate clock + reset
//   2. Write a 32/64 pattern to register 0 
//   3. Write a 32/64 pattern to register 1
//   4. Read back register 0, check it matches
//   5. Read back register 1, check it matches
//   6. Attempt a write to an out-of-range address, check SLVERR comes back
//   7. Print PASS/FAIL summary
// ============================================================================

`timescale 1ns/1ps

module tb_simple;

  localparam int ADDR_WIDTH = 8;
  localparam int DATA_WIDTH = 32;
  //localparam int DATA_WIDTH = 64;
  localparam int NUM_REGS   = 16; 
  localparam int ADDR_LSB = $clog2(DATA_WIDTH / 8);
  localparam int REG_STRIDE = DATA_WIDTH / 8; 

  // ------------------------------------------------------------------
  // DUT signals 
  // ------------------------------------------------------------------
  logic                    clk = 0;
  logic                    rst_n;

  logic [ADDR_WIDTH-1:0]   awaddr;
  logic                    awvalid;
  logic                    awready;

  logic [DATA_WIDTH-1:0]   wdata;
  logic [DATA_WIDTH/8-1:0] wstrb;
  logic                    wvalid;
  logic                    wready;

  logic [1:0]              bresp;
  logic                    bvalid;
  logic                    bready;

  logic [ADDR_WIDTH-1:0]   araddr;
  logic                    arvalid;
  logic                    arready;

  logic [DATA_WIDTH-1:0]   rdata;
  logic [1:0]              rresp;
  logic                    rvalid;
  logic                    rready;

  int num_checks = 0;
  int num_errors = 0;

  // ------------------------------------------------------------------
  // DUT instantiation
  // ------------------------------------------------------------------
  axi4lite_slave #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .NUM_REGS   (NUM_REGS)
  ) dut (.*);

  // ------------------------------------------------------------------
  // Clock + resetgeneration
  // ------------------------------------------------------------------
  always #5 clk = ~clk;   // 10ns period -> 100MHz

  initial begin
    rst_n = 0;

    // aw inputs
    awvalid = 0; awaddr  = '0;

    // w inputs
    wdata = '0; wstrb = '0; wvalid = 0; 

    // b input
    bready = 1;

    // ar inputs
    arvalid = 0; araddr = '0;

    // r input
    rready = 1; 

    repeat (3) @(posedge clk);
    rst_n = 1;
  end

  // ------------------------------------------------------------------
  // Driving tasks 
  // ------------------------------------------------------------------
  task do_write(bit [ADDR_WIDTH-1:0] addr, bit [DATA_WIDTH-1:0] data);
    // drive AW and W together (both can be driven from the same beat here
    // since this simple testbench doesn't need to model independent timing)
    awaddr  <= addr;
    awvalid <= 1'b1;
    wdata   <= data;
    wstrb   <= '1;
    wvalid  <= 1'b1;

    // wait for both AWREADY and WREADY (they may arrive on different cycles)
    fork
      begin
        do @(posedge clk); while (!awready);
      end
      begin
        do @(posedge clk); while (!wready);
      end
    join
    awvalid <= 1'b0;
    wvalid  <= 1'b0;

    // wait for the write response
    do @(posedge clk); while (!bvalid);
    $display("[%0t] WRITE addr=0x%0h data=0x%0h -> bresp=%0b", $time, addr, data, bresp);
  endtask

  task do_read(bit [ADDR_WIDTH-1:0] addr, output bit [DATA_WIDTH-1:0] data, output bit [1:0] resp);
    araddr  <= addr;
    arvalid <= 1'b1;
    do @(posedge clk); while (!arready);
    arvalid <= 1'b0;

    do @(posedge clk); while (!rvalid);
    data = rdata;
    resp = rresp;
    $display("[%0t] READ  addr=0x%0h -> data=0x%0h resp=%0b", $time, addr, data, resp);
  endtask

  task check(string what, bit [DATA_WIDTH-1:0] actual, bit [DATA_WIDTH-1:0] expected);
    num_checks++;
    if (actual !== expected) begin
      num_errors++;
      $error("%s MISMATCH: expected=0x%0h actual=0x%0h", what, expected, actual);
    end else begin
      $display("%s OK (0x%0h)", what, actual);
    end
  endtask

  task check_resp(string what, bit [1:0] actual, bit [1:0] expected);
    num_checks++;
    if (actual !== expected) begin
      num_errors++;
      $error("%s RESP MISMATCH: expected=%0b actual=%0b", what, expected, actual);
    end else begin
      $display("%s resp OK (%0b)", what, actual);
    end
  endtask

  // ------------------------------------------------------------------
  // Test sequence
  // ------------------------------------------------------------------
  bit [DATA_WIDTH-1:0] rd_data;
  bit [1:0]            rd_resp;

  initial begin
    bit [DATA_WIDTH-1:0] reg0_data, reg1_data, oor_data;

    wait (rst_n === 1'b1);
    @(posedge clk);
    
    case (DATA_WIDTH)
	32: begin 
 	   reg0_data = 32'hCAFE_BABE;
    	   reg1_data = 32'h1234_5678;
	   oor_data  = 32'hDEAD_DEAD;
	end 
	64: begin 
	   reg0_data = 64'hCAFE_BABE_12345678;
	   reg1_data = 64'hDEADBEEF_98765432;
	   oor_data = 64'hDEAD_DEAD_DEAD_DEAD;
	end 
	default: begin
	   $fatal(1, "tb_simple: DATA_WIDTH=%0d invalid, only 32/64 supported", DATA_WIDTH);
	end 
   endcase

   // 1) write reg0 and reg1
   do_write(8'h00, 	reg0_data);
   do_write(8'(REG_STRIDE), reg1_data);


    // 2) read back and check
    do_read(8'h00, rd_data, rd_resp);
    check("reg0 read-back", rd_data, reg0_data);
    check_resp("reg0 read", rd_resp, 2'b00);

    do_read(8'(REG_STRIDE), rd_data, rd_resp);
    check("reg1 read-back", rd_data, reg1_data);
    check_resp("reg1 read", rd_resp, 2'b00);

    // 3) out-of-range write -> expect SLVERR
    do_write(8'hFC, oor_data);   // word_idx = 0xFC>>2 = 63, way beyond NUM_REGS=16
    check_resp("out-of-range write", bresp, 2'b10);

    // 4) out-of-range read -> expect SLVERR, rdata == 0
    do_read(8'hFC, rd_data, rd_resp);
    check_resp("out-of-range read", rd_resp, 2'b10);
    check("out-of-range read data", rd_data, '0);

    // ------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------
    $display("\n==============================");
    $display("TOTAL CHECKS: %0d   ERRORS: %0d", num_checks, num_errors);
    if (num_errors == 0) $display("*** TEST PASSED ***");
    else                 $display("*** TEST FAILED ***");
    $display("==============================\n");

    $finish;
  end

  // safety timeout in case something hangs
  initial begin
    #10000;
    $error("TIMEOUT: simulation did not finish in time!");
    $finish;
  end

endmodule
