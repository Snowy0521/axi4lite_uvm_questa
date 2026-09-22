// ============================================================================
// axi4lite_driver.sv
//
// Pulls axi4lite_txn items from the sequencer and drives them onto the
// AXI4-Lite bus via the interface's driver clocking block.
//
// ============================================================================

class axi4lite_driver extends uvm_driver #(axi4lite_txn);
  `uvm_component_utils(axi4lite_driver)

  virtual axi4lite_if #(
    .ADDR_WIDTH(axi4lite_pkg::ADDR_WIDTH),
    .DATA_WIDTH(axi4lite_pkg::DATA_WIDTH)
  ).driver vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi4lite_if #(
  	  .ADDR_WIDTH(axi4lite_pkg::ADDR_WIDTH),
    	  .DATA_WIDTH(axi4lite_pkg::DATA_WIDTH)
        ).driver)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface (driver modport) not found in config_db")
  endfunction

  task run_phase(uvm_phase phase);

    // super.run_phase(phase); --- IGNORE --- // its a virtual task, so it does nothing anyway
    wait (vif.rst_n === 1'b1); // “===” return only true and false, not x or z
    reset_signals();

    forever begin
      axi4lite_txn tr;
      seq_item_port.get_next_item(tr);
      `uvm_info("DRV", $sformatf("Got transaction: op=%0d addr=0x%0h data=0x%0h", tr.op, tr.addr, tr.wdata), UVM_LOW)
      if (tr.op == AXI_WRITE) drive_write(tr);
      else                    drive_read(tr);
      seq_item_port.item_done();
    end
  endtask

  task reset_signals();
    // drive clockvars through drv_cb -- output skew (#2, see axi4lite_if.sv)
    vif.drv_cb.awvalid <= 1'b0;
    vif.drv_cb.wvalid  <= 1'b0;
    vif.drv_cb.bready  <= 1'b1;   // always ready to accept a write response in this simple driver
    vif.drv_cb.arvalid <= 1'b0;
    vif.drv_cb.rready  <= 1'b1;   // always ready to accept read data in this simple driver

    @(vif.drv_cb);
  endtask

  // ------------------------------------------------------------------
  // Write: drive AW and W concurrently, each with its own timeout watchdog.
  // ------------------------------------------------------------------
  task drive_write(axi4lite_txn tr);
    fork
      begin : do_aw
        vif.drv_cb.awaddr  <= tr.addr;
        vif.drv_cb.awvalid <= 1'b1;
        fork
          begin : wait_awready
            do @(vif.drv_cb); while (!vif.drv_cb.awready);
          end
          begin : awready_timeout
            repeat (axi4lite_pkg::TIMEOUT_CYCLES) @(vif.drv_cb);
            `uvm_error("DRV_TIMEOUT", "timed out waiting for AWREADY")
          end
        join_any
        disable fork;
        vif.drv_cb.awvalid <= 1'b0;
      end
      begin : do_w
        vif.drv_cb.wdata  <= tr.wdata;
        vif.drv_cb.wstrb  <= tr.wstrb;
        vif.drv_cb.wvalid <= 1'b1;
        fork
          begin : wait_wready
            do @(vif.drv_cb); while (!vif.drv_cb.wready);
          end
          begin : wready_timeout
            repeat (axi4lite_pkg::TIMEOUT_CYCLES) @(vif.drv_cb);
            `uvm_error("DRV_TIMEOUT", "timed out waiting for WREADY")
          end
        join_any
        disable fork;
        vif.drv_cb.wvalid <= 1'b0;
      end
    join

    // wait for the write response
    fork
      begin : wait_bvalid
        do @(vif.drv_cb); while (!vif.drv_cb.bvalid);
        tr.resp = vif.drv_cb.bresp; // update transaction object using "="
      end
      begin : bresp_timeout
        repeat (axi4lite_pkg::TIMEOUT_CYCLES) @(vif.drv_cb);
        `uvm_error("DRV_TIMEOUT", "timed out waiting for BVALID")
      end
    join_any
    disable fork;
  endtask

  // ------------------------------------------------------------------
  // Read
  // ------------------------------------------------------------------
  task drive_read(axi4lite_txn tr);
    vif.drv_cb.araddr  <= tr.addr;
    vif.drv_cb.arvalid <= 1'b1;
    fork
      begin : wait_arready
        do @(vif.drv_cb); while (!vif.drv_cb.arready);
      end
      begin : arready_timeout
        repeat (axi4lite_pkg::TIMEOUT_CYCLES) @(vif.drv_cb);
        `uvm_error("DRV_TIMEOUT", "timed out waiting for ARREADY")
      end
    join_any
    disable fork;
    vif.drv_cb.arvalid <= 1'b0;

    fork
      begin : wait_rvalid
        do @(vif.drv_cb); while (!vif.drv_cb.rvalid);
        tr.rdata = vif.drv_cb.rdata;
        tr.resp  = vif.drv_cb.rresp;
      end
      begin : rvalid_timeout
        repeat (axi4lite_pkg::TIMEOUT_CYCLES) @(vif.drv_cb);
        `uvm_error("DRV_TIMEOUT", "timed out waiting for RVALID")
      end
    join_any
    disable fork;
  endtask

endclass
