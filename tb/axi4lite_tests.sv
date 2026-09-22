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
    uvm_config_db#(int unsigned)::set(this, "env.sb", "num_regs", NUM_REGS);
    env = axi4lite_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology(); // print the component hierarchy to the transcript
  endfunction

  task run_phase(uvm_phase phase);
    axi4lite_base_seq seq;

    phase.raise_objection(this);
    
    seq = axi4lite_base_seq::type_id::create("seq");
    seq.start(env.agent.sqr);

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
