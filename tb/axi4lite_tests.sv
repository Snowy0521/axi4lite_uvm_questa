// ============================================================================
// axi4lite_test.sv
//
// base_test sets up the environment and common configuration. 
// ============================================================================

class axi4lite_base_test extends uvm_test;
  `uvm_component_utils(axi4lite_base_test)

  axi4lite_env env;
  // For resetting the DUT mid-run (axi4lite_reset_test). Read here, by every
  // test, so the end-of-elaboration check doesn't report tb_top's set as unused.
  virtual axi4lite_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)).reset_ctrl reset_vif;

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
    if (!uvm_config_db#(virtual axi4lite_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)).reset_ctrl)::get(
            this, "", "reset_vif", reset_vif))
      `uvm_fatal("NOVIF", "reset_ctrl virtual interface not found in config_db (set in tb_top)")
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
// Unaligned-address test: the random test's traffic, driven by
// axi4lite_unaligned_driver -- legal stimulus the sequences can't produce,
// so a pass is the expected result: the DUT handles it per spec. The
// factory override is the only change -- env and agent still call
// axi4lite_driver::type_id::create. It goes before super.build_phase by
// habit; the driver itself is only created later, in the agent's
// build_phase (build runs top-down). print_topology in
// end_of_elaboration_phase shows axi4lite_unaligned_driver as env.agent.drv.
// --------------------------------------------------------------------------
class axi4lite_unaligned_test extends axi4lite_random_test;
  `uvm_component_utils(axi4lite_unaligned_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    set_type_override_by_type(axi4lite_driver::get_type(), axi4lite_unaligned_driver::get_type());
    super.build_phase(phase);
  endfunction

endclass

// --------------------------------------------------------------------------
// Reset test: the random traffic, with the DUT reset in the middle of it.
// Checks that a reset at any point of a transaction leaves the bench and the
// DUT consistent: the driver drops the item it was driving and starts again,
// the monitor reports what was cut off and restarts its counts, and the
// scoreboard clears its model, so reads after a reset expect the reset value.
// That is also what catches a DUT that does not clear its register file on a
// later reset (mutant M09b).
// - NUM_RESETS resets at random points of the traffic; the first one is one
//   clock long, the shortest possible, which the driver's abort path must
//   handle without missing the release;
// - then one reset while the driver is idle in get_next_item (the traffic is
//   done), with the second run of the traffic started during that reset: its
//   first item arrives in the reset, and the driver must hold it until the
//   release ("item held until reset release" in the log).
// cp_reset_phase (axi4lite_reset_coverage) records which phase each reset hit.
// --------------------------------------------------------------------------
class axi4lite_reset_test extends axi4lite_random_test;
  `uvm_component_utils(axi4lite_reset_test)

  localparam int unsigned NUM_RESETS = 6;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    uvm_config_db#(bit)::set(this, "env", "reset_cov", 1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    axi4lite_base_seq seq;
    phase.raise_objection(this);

    seq = axi4lite_base_seq::type_id::create("seq");
    fork
      seq.start(env.agent.sqr);
      resets_during_traffic();
    join

    // The traffic is done: the driver waits in get_next_item. Reset it there,
    // and start the next traffic during the reset.
    repeat (5) @(posedge reset_vif.clk);
    seq = axi4lite_base_seq::type_id::create("seq_after_reset");
    fork
      reset_vif.apply_reset(4);
      begin
        wait (reset_vif.rst_n === 1'b0);
        seq.start(env.agent.sqr);
      end
    join

    env.agent.mon.wait_for_idle(TIMEOUT_CYCLES);
    phase.drop_objection(this);
  endtask

  protected task resets_during_traffic();
    for (int i = 0; i < NUM_RESETS; i++) begin
      repeat ($urandom_range(150, 30)) @(posedge reset_vif.clk);
      reset_vif.apply_reset((i == 0) ? 1 : $urandom_range(4, 1));
    end
  endtask

endclass
