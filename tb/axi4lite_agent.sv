// ============================================================================
// axi4lite_agent.sv
//
// Standard driver + sequencer + monitor container, with active/passive mode
// switching. The monitor is always built; driver/sequencer only
// exist when the agent is active.
// ============================================================================

class axi4lite_agent extends uvm_agent;
  `uvm_component_utils(axi4lite_agent)

  axi4lite_driver    drv;
  axi4lite_sequencer sqr;
  axi4lite_monitor   mon;

  uvm_analysis_port #(axi4lite_txn) ap;   // pass-through of the monitor's ap for env-level connect

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this); 
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = axi4lite_monitor::type_id::create("mon", this);

    if (get_is_active() == UVM_ACTIVE) begin
      drv = axi4lite_driver::type_id::create("drv", this);
      sqr = axi4lite_sequencer::type_id::create("sqr", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
    mon.ap.connect(ap);
    `uvm_info("AGT", "connect_phase done", UVM_LOW)
  endfunction

endclass
