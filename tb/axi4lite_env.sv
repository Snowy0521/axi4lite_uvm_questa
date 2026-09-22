// ============================================================================
// axi4lite_env.sv
//
// Top-level environment: one active agent + the scoreboard, wired together
// via the agent's pass-through analysis port.
// ============================================================================

class axi4lite_env extends uvm_env;
  `uvm_component_utils(axi4lite_env)

  axi4lite_agent      agent;
  axi4lite_scoreboard sb;
  axi4lite_coverage_collector cov_col;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "agent", "is_active", UVM_ACTIVE);
    agent = axi4lite_agent::type_id::create("agent", this);
    sb    = axi4lite_scoreboard::type_id::create("sb", this);
    cov_col = axi4lite_coverage_collector::type_id::create("cov_col", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.ap.connect(sb.imp);
    agent.ap.connect(cov_col.analysis_export); // coverage collector is a subscriber, defined default analysis_export. 
    `uvm_info("ENV", "connect_phase done", UVM_LOW)  
  endfunction

endclass
