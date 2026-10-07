// ============================================================================
// axi4lite_monitor.sv
//
// Passively observes the bus and reconstructs completed write/read
// transactions, broadcasting each one on an analysis port for the
// scoreboard and coverage collector to consume.
//
// Write and read channels are monitored concurrently since AXI4-Lite allows
// independent, overlapping read/write traffic.
// ============================================================================

class axi4lite_monitor extends uvm_monitor;
  `uvm_component_utils(axi4lite_monitor)

  virtual axi4lite_if #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ).monitor vif;

  uvm_analysis_port #(axi4lite_txn) ap;

  // Raw handshake counts per channel, kept apart from transaction
  // reconstruction: a B or R the DUT sends unasked never gets paired by
  // monitor_write/monitor_read, but still shows up here. Plus the
  // transactions actually published on ap.
  int unsigned n_aw, n_w, n_b, n_ar, n_r;
  int unsigned n_wr_pub, n_rd_pub;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this); // TLM port, can not be registered in config_db, just new it
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi4lite_if#(
   	 .ADDR_WIDTH(ADDR_WIDTH),
    	 .DATA_WIDTH(DATA_WIDTH)
       ).monitor)::get(this, "", "vif", vif))
       	`uvm_fatal("NOVIF", "virtual interface (monitor modport) not found in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    // Waiting for reset and one extra clocking-event pushes the first 
    // sample to the next edge, by which point the driver's first 
    // transaction's driven values.
    wait (vif.rst_n === 1'b1);
    @(vif.mon_cb);
    fork
      monitor_write();
      monitor_read();
      count_handshakes();
    join
  endtask

  // Samples the same edges as monitor_write/monitor_read.
  task count_handshakes();
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.awvalid && vif.mon_cb.awready) n_aw++;
      if (vif.mon_cb.wvalid  && vif.mon_cb.wready)  n_w++;
      if (vif.mon_cb.bvalid  && vif.mon_cb.bready)  n_b++;
      if (vif.mon_cb.arvalid && vif.mon_cb.arready) n_ar++;
      if (vif.mon_cb.rvalid  && vif.mon_cb.rready)  n_r++;
    end
  endtask

  // Every accepted request answered exactly once, nothing answered unasked,
  // and every answer published as a transaction.
  function bit all_answered();
    return n_aw == n_b && n_w == n_b && n_ar == n_r
        && n_wr_pub == n_b && n_rd_pub == n_r;
  endfunction

  // Called by the test before it drops its objection, so the last
  // responses are still observed and checked rather than cut off.
  task wait_for_idle(int unsigned max_cycles);
    repeat (max_cycles) begin
      if (all_answered()) return;
      @(vif.mon_cb);
    end
    if (!all_answered())
      `uvm_error("MON_NOT_IDLE", $sformatf(
        "bus not idle %0d cycles after the sequence finished", max_cycles))
  endtask

  // Sign-off: no transaction outstanding (or unsolicited) at end of test.
  function void check_phase(uvm_phase phase);
    string counts = $sformatf(
      "AW=%0d W=%0d B=%0d AR=%0d R=%0d, published writes=%0d reads=%0d",
      n_aw, n_w, n_b, n_ar, n_r, n_wr_pub, n_rd_pub);
    super.check_phase(phase);
    if (all_answered())
      `uvm_info("MON", {"no outstanding transactions: ", counts}, UVM_LOW)
    else
      `uvm_error("MON_OUTSTANDING", {"unanswered or unsolicited transactions at end of test: ", counts})
  endfunction

  // ------------------------------------------------------------------
  // Reconstruct a write transaction: wait for AW and W handshakes
  // (independently, since they can complete in either order), then wait
  // for the B response, then publish the completed transaction.
  // ------------------------------------------------------------------
  task monitor_write();
    forever begin
      axi4lite_txn tr = axi4lite_txn::type_id::create("tr");
      time         aw_t, w_t;   // when each half was accepted, for aw_w_order
      tr.op = AXI_WRITE;

      fork
        begin : do_aw
          fork
            begin : wait_aw
              do @(vif.mon_cb); while (!(vif.mon_cb.awvalid && vif.mon_cb.awready));
            end
            begin : aw_stall_watch
              forever begin
                repeat (TIMEOUT_CYCLES) @(vif.mon_cb);
                `uvm_warning("MON_STALL", "monitor_write: still waiting for AW handshake")
              end
            end
          join_any
          disable fork;
          tr.addr = vif.mon_cb.awaddr;
          aw_t    = $time;
        end
        begin : do_w
          fork
            begin : wait_w
              do @(vif.mon_cb); while (!(vif.mon_cb.wvalid && vif.mon_cb.wready));
            end
            begin : w_stall_watch
              forever begin
                repeat (TIMEOUT_CYCLES) @(vif.mon_cb);
                `uvm_warning("MON_STALL", "monitor_write: still waiting for W handshake")
              end
            end
          join_any
          disable fork;
          tr.wdata = vif.mon_cb.wdata;
          tr.wstrb = vif.mon_cb.wstrb;
          w_t      = $time;
        end
      join
      tr.aw_w_order = (aw_t < w_t) ? AW_FIRST :
                      (w_t < aw_t) ? W_FIRST  : AW_W_SAME_CYCLE;

      fork
        begin : wait_b
          do begin
            @(vif.mon_cb);
            if (vif.mon_cb.bvalid && !vif.mon_cb.bready) tr.resp_stall++;   // backpressure
          end while (!(vif.mon_cb.bvalid && vif.mon_cb.bready));
        end
        begin : b_stall_watch
          forever begin
            repeat (TIMEOUT_CYCLES) @(vif.mon_cb);
            `uvm_warning("MON_STALL", "monitor_write: still waiting for BVALID")
          end
        end
      join_any
      disable fork;
      tr.resp = vif.mon_cb.bresp;

      `uvm_info("MON", $sformatf("observed %s", tr.convert2string()), UVM_HIGH)
      n_wr_pub++;
      ap.write(tr);
    end
  endtask

  // ------------------------------------------------------------------
  // Reconstruct a read transaction: wait for the AR handshake, then wait
  // for RVALID, then publish. Same stall-watchdog reasoning as above.
  // ------------------------------------------------------------------
  task monitor_read();
    forever begin
      axi4lite_txn tr = axi4lite_txn::type_id::create("tr");
      tr.op = AXI_READ;

      fork
        begin : wait_ar
          do @(vif.mon_cb); while (!(vif.mon_cb.arvalid && vif.mon_cb.arready));
        end
        begin : ar_stall_watch
          forever begin
            repeat (TIMEOUT_CYCLES) @(vif.mon_cb);
            `uvm_warning("MON_STALL", "monitor_read: still waiting for AR handshake")
          end
        end
      join_any
      disable fork;
      tr.addr = vif.mon_cb.araddr;

      fork
        begin : wait_r
          do begin
            @(vif.mon_cb);
            if (vif.mon_cb.rvalid && !vif.mon_cb.rready) tr.resp_stall++;   // backpressure
          end while (!(vif.mon_cb.rvalid && vif.mon_cb.rready));
        end
        begin : r_stall_watch
          forever begin
            repeat (TIMEOUT_CYCLES) @(vif.mon_cb);
            `uvm_warning("MON_STALL", "monitor_read: still waiting for RVALID")
          end
        end
      join_any
      disable fork;
      tr.rdata = vif.mon_cb.rdata;
      tr.resp  = vif.mon_cb.rresp;

      `uvm_info("MON", $sformatf("observed %s", tr.convert2string()), UVM_HIGH)
      n_rd_pub++;
      ap.write(tr);
    end
  endtask

endclass
