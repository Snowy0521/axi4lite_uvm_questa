`timescale 1ns/1ps

interface simple_if(input logic clk);
  logic sig_a, sig_b;
  logic ready_a, ready_b;
  clocking cb @(posedge clk);
    default input #1step output #2;
    output sig_a, sig_b;
    input  ready_a, ready_b;
  endclocking
  modport drv (clocking cb, input clk);
endinterface

module tb_dual_fork_test;
  logic clk = 0;
  always #5 clk = ~clk;

  simple_if intf(clk);
  assign intf.ready_a = intf.sig_a;
  assign intf.ready_b = intf.sig_b;

  virtual simple_if.drv vif;

  initial begin
    vif = intf;
    $monitor("T=%0t sig_a=%b sig_b=%b ready_a=%b ready_b=%b", $time, intf.sig_a, intf.sig_b, intf.ready_a, intf.ready_b);
    repeat(3) @(posedge clk);

    fork
      begin : branch_a
        vif.cb.sig_a <= 1'b1;
        fork
          begin : wait_a
            do @(vif.cb); while (!vif.cb.ready_a);
          end
          begin : timeout_a
            repeat(20) @(vif.cb);
            $display("TIMEOUT A");
          end
        join_any
        disable fork;
      end
      begin : branch_b
        vif.cb.sig_b <= 1'b1;
        fork
          begin : wait_b
            do @(vif.cb); while (!vif.cb.ready_b);
          end
          begin : timeout_b
            repeat(20) @(vif.cb);
            $display("TIMEOUT B");
          end
        join_any
        disable fork;
      end
    join

    $display("BOTH BRANCHES DONE");
    #50;
    $finish;
  end
endmodule
