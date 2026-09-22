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
    .ADDR_WIDTH(axi4lite_pkg::ADDR_WIDTH),
    .DATA_WIDTH(axi4lite_pkg::DATA_WIDTH)
  ).monitor vif;

  uvm_analysis_port #(axi4lite_txn) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this); // TLM port, can not be registered in config_db, just new it
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi4lite_if#(
   	 .ADDR_WIDTH(axi4lite_pkg::ADDR_WIDTH),
    	 .DATA_WIDTH(axi4lite_pkg::DATA_WIDTH)
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
    join
  endtask

  // ------------------------------------------------------------------
  // Reconstruct a write transaction: wait for AW and W handshakes
  // (independently, since they can complete in either order), then wait
  // for the B response, then publish the completed transaction.
  // ------------------------------------------------------------------
  task monitor_write();
    forever begin
      axi4lite_txn tr = axi4lite_txn::type_id::create("tr");
      tr.op = AXI_WRITE;

      fork
        begin : do_aw
          fork
            begin : wait_aw
              do @(vif.mon_cb); while (!(vif.mon_cb.awvalid && vif.mon_cb.awready));
            end
            begin : aw_stall_watch
              forever begin
                repeat (axi4lite_pkg::TIMEOUT_CYCLES) @(vif.mon_cb);
                `uvm_warning("MON_STALL", "monitor_write: still waiting for AW handshake")
              end
            end
          join_any
          disable fork;
          tr.addr = vif.mon_cb.awaddr;
        end
        begin : do_w
          fork
            begin : wait_w
              do @(vif.mon_cb); while (!(vif.mon_cb.wvalid && vif.mon_cb.wready));
            end
            begin : w_stall_watch
              forever begin
                repeat (axi4lite_pkg::TIMEOUT_CYCLES) @(vif.mon_cb);
                `uvm_warning("MON_STALL", "monitor_write: still waiting for W handshake")
              end
            end
          join_any
          disable fork;
          tr.wdata = vif.mon_cb.wdata;
          tr.wstrb = vif.mon_cb.wstrb;
        end
      join

      fork
        begin : wait_b
          do @(vif.mon_cb); while (!(vif.mon_cb.bvalid && vif.mon_cb.bready));
        end
        begin : b_stall_watch
          forever begin
            repeat (axi4lite_pkg::TIMEOUT_CYCLES) @(vif.mon_cb);
            `uvm_warning("MON_STALL", "monitor_write: still waiting for BVALID")
          end
        end
      join_any
      disable fork;
      tr.resp = vif.mon_cb.bresp;

      `uvm_info("MON", $sformatf("observed %s", tr.convert2string()), UVM_LOW)
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
            repeat (axi4lite_pkg::TIMEOUT_CYCLES) @(vif.mon_cb);
            `uvm_warning("MON_STALL", "monitor_read: still waiting for AR handshake")
          end
        end
      join_any
      disable fork;
      tr.addr = vif.mon_cb.araddr;

      fork
        begin : wait_r
          do @(vif.mon_cb); while (!(vif.mon_cb.rvalid && vif.mon_cb.rready));
        end
        begin : r_stall_watch
          forever begin
            repeat (axi4lite_pkg::TIMEOUT_CYCLES) @(vif.mon_cb);
            `uvm_warning("MON_STALL", "monitor_read: still waiting for RVALID")
          end
        end
      join_any
      disable fork;
      tr.rdata = vif.mon_cb.rdata;
      tr.resp  = vif.mon_cb.rresp;

      `uvm_info("MON", $sformatf("observed %s", tr.convert2string()), UVM_LOW)
      ap.write(tr);
    end
  endtask

endclass
