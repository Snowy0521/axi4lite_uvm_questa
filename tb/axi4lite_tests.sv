// ============================================================================
// axi4lite_test.sv
//
// base_test sets up the environment and common configuration. 
// ============================================================================

class axi4lite_base_test extends uvm_test;
  `uvm_component_utils(axi4lite_base_test)

  axi4lite_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Backstop for any hang the per-handshake timeouts miss: a clear
    // UVM_FATAL instead of running until the regression's wall-clock limit.
    // The random test finishes in ~5 us.
    uvm_top.set_timeout(1ms);
    uvm_config_db#(int unsigned)::set(this, "env.sb", "num_regs", NUM_REGS);
    env = axi4lite_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_resource_types::rsrc_q_t unused;
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology(); // print the component hierarchy to the transcript

    // Every config_db set must have been read by now (all gets are in
    // build_phase). One that wasn't is almost always a mistyped path or
    // field name. check_config_usage only prints them as UVM_INFO, so
    // also raise an error the regression counts.
    unused = uvm_resource_pool::get().find_unused_resources();
    if (unused.size() != 0) begin
      check_config_usage();
      `uvm_error("CFG_UNUSED", $sformatf(
        "%0d config_db setting(s) never read -- mistyped path or field name? (listed above)",
        unused.size()))
    end
  endfunction

  task run_phase(uvm_phase phase);
    axi4lite_base_seq seq;

    phase.raise_objection(this);
    
    seq = axi4lite_base_seq::type_id::create("seq");
    seq.start(env.agent.sqr);

    // Don't end with requests in flight: their responses would never be
    // checked. The monitor's check_phase then confirms nothing is outstanding.
    env.agent.mon.wait_for_idle(TIMEOUT_CYCLES);

    phase.drop_objection(this);
  endtask

endclass

// --------------------------------------------------------------------------
// Smoke test: a handful of directed writes followed by read-back checks.
// Good first test to bring the environment up with.
// --------------------------------------------------------------------------
class axi4lite_smoke_test extends axi4lite_base_test;
  `uvm_component_utils(axi4lite_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    set_type_override_by_type(axi4lite_base_seq::get_type(), axi4lite_smoke_seq::get_type());
    super.build_phase(phase);
  endfunction

endclass 

// --------------------------------------------------------------------------
// Randomized regression test: constrained-random traffic including
// occasional out-of-range accesses to exercise SLVERR handling.
// --------------------------------------------------------------------------
class axi4lite_random_test extends axi4lite_base_test;
  `uvm_component_utils(axi4lite_random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    set_type_override_by_type(axi4lite_base_seq::get_type(), axi4lite_random_seq::get_type());
    super.build_phase(phase);
  endfunction
  
endclass

// --------------------------------------------------------------------------
// Corner-case test: the random test's traffic, driven by
// axi4lite_corner_driver (AW/W skew, unaligned addresses -- legal stimulus
// the base driver and sequences can't produce, so a pass is the expected
// result: the DUT handles it per spec). The factory
// override is the only change -- env and agent still call
// axi4lite_driver::type_id::create. It goes before super.build_phase by
// habit; the driver itself is only created later, in the agent's
// build_phase (build runs top-down). print_topology in
// end_of_elaboration_phase shows axi4lite_corner_driver as env.agent.drv.
// --------------------------------------------------------------------------
class axi4lite_corner_test extends axi4lite_random_test;
  `uvm_component_utils(axi4lite_corner_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    set_type_override_by_type(axi4lite_driver::get_type(), axi4lite_corner_driver::get_type());
    super.build_phase(phase);
  endfunction

endclass
