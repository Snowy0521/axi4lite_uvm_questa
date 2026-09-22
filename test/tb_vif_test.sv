`timescale 1ns/1ps

interface simple_if(input logic clk);
  logic sig;
  logic ready;
  clocking cb @(posedge clk);
    default input #1step output #2;
    output sig;
    input  ready;
  endclocking
  modport drv (clocking cb, input clk);
endinterface

class driver_like;
  virtual simple_if.drv vif;   // 关键：virtual interface 句柄，跟你的 driver 一样

  task drive();
    fork
      begin : do_drive
        vif.cb.sig <= 1'b1;
        do @(vif.cb); while (!vif.cb.ready);
      end
      begin : timeout
        repeat(20) @(vif.cb);
        $display("TIMEOUT waiting for ready");
      end
    join_any
    disable fork;
  endtask
endclass

module tb_vif_test;
  logic clk = 0;
  always #5 clk = ~clk;

  simple_if intf(clk);
  assign intf.ready = intf.sig;   // 简单反馈：sig 变 1 之后 ready 也跟着变 1，方便观察

  driver_like drv;

  initial begin
    $monitor("T=%0t sig=%b ready=%b", $time, intf.sig, intf.ready);
    drv = new();
    drv.vif = intf;   // 句柄赋值，模拟 uvm_config_db::get 的效果
    repeat(3) @(posedge clk);
    drv.drive();
    #100;
    $finish;
  end
endmodule
