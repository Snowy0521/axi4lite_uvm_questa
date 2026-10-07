// ============================================================================
// axi4lite_driver.sv
//
// Pulls axi4lite_txn items from the sequencer and drives them onto the
// AXI4-Lite bus via the interface's driver clocking block.
//
// A timeout is fatal: the transfer is left unfinished, so carrying on would
// either drop VALID before its handshake (illegal) or run the next item
// into the stale one, burying the real cause under follow-on errors.
// Ending here keeps the first error in the log the real one.
// ============================================================================

class axi4lite_driver extends uvm_driver #(axi4lite_txn);
  `uvm_component_utils(axi4lite_driver)

  virtual axi4lite_if #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ).driver vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi4lite_if #(
  	  .ADDR_WIDTH(ADDR_WIDTH),
    	  .DATA_WIDTH(DATA_WIDTH)
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
      `uvm_info("DRV", $sformatf("Got transaction: op=%0d addr=0x%0h data=0x%0h", tr.op, tr.addr, tr.wdata), UVM_HIGH)
      if (tr.op == AXI_WRITE) drive_write(tr);
      else                    drive_read(tr);
      seq_item_port.item_done();
    end
  endtask

  task reset_signals();
    // drive clockvars through drv_cb -- output skew (#2, see axi4lite_if.sv)
    vif.drv_cb.awvalid <= 1'b0;
    vif.drv_cb.wvalid  <= 1'b0;
    vif.drv_cb.bready  <= 1'b1;   // per-response backpressure is set in wait_b / drive_read
    vif.drv_cb.arvalid <= 1'b0;
    vif.drv_cb.rready  <= 1'b1;

    @(vif.drv_cb);
  endtask

  // ------------------------------------------------------------------
  // Write: drive AW and W concurrently, each with its own timeout watchdog,
  // then wait for B. drive_write / drive_aw / drive_w / drive_read are
  // virtual so a factory override (axi4lite_unaligned_driver) can change one
  // step; a non-virtual task would still be called from run_phase, and the
  // override would be built but silently never used.
  // ------------------------------------------------------------------
  virtual task drive_write(axi4lite_txn tr);
    pick_skew();
    fork
      drive_aw(tr);
      drive_w(tr);
    join
    wait_b(tr);
  endtask

  // Cycles each half of the write in progress waits before starting; at
  // most one is nonzero. Without a skew AW and W always start together and
  // the DUT's AW-first / W-first paths (spec: either order is legal) never
  // run. Here: half the writes together, a quarter each with one channel
  // 1-2 cycles late. Once one cycle apart, the DUT's latch paths are the
  // same however long the gap, so a wider skew wouldn't reach anything new.
  protected int unsigned aw_delay, w_delay;

  virtual function void pick_skew();
    aw_delay = 0;
    w_delay  = 0;
    case ($urandom_range(3, 0))
      0:       w_delay  = $urandom_range(2, 1);   // AW first
      1:       aw_delay = $urandom_range(2, 1);   // W first
      default: ;                                  // same cycle
    endcase
  endfunction

  virtual task drive_aw(axi4lite_txn tr);
    repeat (aw_delay) @(vif.drv_cb);
    vif.drv_cb.awaddr  <= tr.addr;
    vif.drv_cb.awvalid <= 1'b1;
    fork
      begin : wait_awready
        do @(vif.drv_cb); while (!vif.drv_cb.awready);
      end
      begin : awready_timeout
        repeat (TIMEOUT_CYCLES) @(vif.drv_cb);
        `uvm_fatal("DRV_TIMEOUT", {"timed out waiting for AWREADY: ", tr.convert2string()})
      end
    join_any
    disable fork;
    vif.drv_cb.awvalid <= 1'b0;
  endtask

  virtual task drive_w(axi4lite_txn tr);
    repeat (w_delay) @(vif.drv_cb);
    vif.drv_cb.wdata  <= tr.wdata;
    vif.drv_cb.wstrb  <= tr.wstrb;
    vif.drv_cb.wvalid <= 1'b1;
    fork
      begin : wait_wready
        do @(vif.drv_cb); while (!vif.drv_cb.wready);
      end
      begin : wready_timeout
        repeat (TIMEOUT_CYCLES) @(vif.drv_cb);
        `uvm_fatal("DRV_TIMEOUT", {"timed out waiting for WREADY: ", tr.convert2string()})
      end
    join_any
    disable fork;
    vif.drv_cb.wvalid <= 1'b0;
  endtask

  // Backpressure on B and R: cycles a response's VALID waits for READY.
  // Half the time READY is already high, otherwise it goes high 1-3 cycles
  // after VALID. Without it no VALID ever waits on a low READY, and the
  // DUT's hold-until-accepted paths never run (code coverage showed it).
  virtual function int unsigned pick_ready_stall();
    return $urandom_range(1, 0) ? 0 : $urandom_range(3, 1);
  endfunction

  task wait_b(axi4lite_txn tr);
    int unsigned stall = pick_ready_stall();
    vif.drv_cb.bready <= (stall == 0);
    fork
      begin : wait_bvalid
        do @(vif.drv_cb); while (!vif.drv_cb.bvalid);
        if (stall != 0) begin
          // BVALID is up with BREADY low at this edge; keep it low for
          // `stall` edges in all, then accept.
          repeat (stall - 1) @(vif.drv_cb);
          vif.drv_cb.bready <= 1'b1;
          do @(vif.drv_cb); while (!vif.drv_cb.bvalid);
        end
        tr.resp = vif.drv_cb.bresp; // update transaction object using "="
      end
      begin : bresp_timeout
        repeat (TIMEOUT_CYCLES) @(vif.drv_cb);
        `uvm_fatal("DRV_TIMEOUT", {"timed out waiting for BVALID: ", tr.convert2string()})
      end
    join_any
    disable fork;
  endtask

  // ------------------------------------------------------------------
  // Read
  // ------------------------------------------------------------------
  virtual task drive_read(axi4lite_txn tr);
    int unsigned stall;
    vif.drv_cb.araddr  <= tr.addr;
    vif.drv_cb.arvalid <= 1'b1;
    fork
      begin : wait_arready
        do @(vif.drv_cb); while (!vif.drv_cb.arready);
      end
      begin : arready_timeout
        repeat (TIMEOUT_CYCLES) @(vif.drv_cb);
        `uvm_fatal("DRV_TIMEOUT", {"timed out waiting for ARREADY: ", tr.convert2string()})
      end
    join_any
    disable fork;
    vif.drv_cb.arvalid <= 1'b0;

    stall = pick_ready_stall();
    vif.drv_cb.rready <= (stall == 0);
    fork
      begin : wait_rvalid
        do @(vif.drv_cb); while (!vif.drv_cb.rvalid);
        if (stall != 0) begin
          // as in wait_b
          repeat (stall - 1) @(vif.drv_cb);
          vif.drv_cb.rready <= 1'b1;
          do @(vif.drv_cb); while (!vif.drv_cb.rvalid);
        end
        tr.rdata = vif.drv_cb.rdata;
        tr.resp  = vif.drv_cb.rresp;
      end
      begin : rvalid_timeout
        repeat (TIMEOUT_CYCLES) @(vif.drv_cb);
        `uvm_fatal("DRV_TIMEOUT", {"timed out waiting for RVALID: ", tr.convert2string()})
      end
    join_any
    disable fork;
  endtask

endclass
