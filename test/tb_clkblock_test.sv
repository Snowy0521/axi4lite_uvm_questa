// tb_clkblock_test.sv —— no UVM, test the clocking block driverability of
// verilator
`timescale 1ns/1ps

interface simple_if(input logic clk);
  logic sig;
  clocking cb @(posedge clk);
    default input #1step output #2;
    output sig;
  endclocking
  modport drv (clocking cb);
endinterface

module tb_clkblock_test;
  logic clk = 0;
  logic rst_n;
  logic test_signal;

  always #5 clk = ~clk;

  simple_if intf(clk);
  initial begin
    $monitor("T=%0t sig=%b", $time, intf.sig);
    repeat(3) @(posedge clk);
    intf.cb.sig <= 1'b1;   
    repeat(5) @(posedge clk);
    $finish;
  end
endmodule
