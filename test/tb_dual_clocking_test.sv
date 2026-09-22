`timescale 1ns/1ps

interface dual_cb_if(input logic clk);
  logic sig;
  logic ready;

  clocking drv_cb @(posedge clk);
    default input #1step output #2;
    output sig;
    input  ready;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input sig, ready;   // 只读，跟 drv_cb 引用同一批物理信号
  endclocking

  modport drv (clocking drv_cb, input clk);
  modport mon (clocking mon_cb, input clk);
endinterface

module tb_dual_clocking_test;
  logic clk = 0;
  always #5 clk = ~clk;

  dual_cb_if intf(clk);
  assign intf.ready = intf.sig;

  virtual dual_cb_if.drv vif;

  initial begin
    vif = intf;
    $monitor("T=%0t sig=%b ready=%b", $time, intf.sig, intf.ready);
    repeat(3) @(posedge clk);

    vif.drv_cb.sig <= 1'b1;
    fork
      begin : wait_ready
        do @(vif.drv_cb); while (!vif.drv_cb.ready);
      end
      begin : timeout
        repeat(20) @(vif.drv_cb);
        $display("TIMEOUT");
      end
    join_any
    disable fork;

    $display("DONE");
    #50;
    $finish;
  end
endmodule
