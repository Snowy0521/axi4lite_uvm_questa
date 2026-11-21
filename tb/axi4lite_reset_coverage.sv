// ============================================================================
// axi4lite_reset_coverage.sv
//
// Which phase of a transaction a reset hit, sampled once per aborted
// transaction (a write and a read can be cut off by the same reset), or as
// idle when nothing was in flight. Its own component, built by the env only
// for a test that resets mid-run (config "reset_cov"), so the other tests'
// coverage models don't gain bins they can never close.
// ============================================================================

class axi4lite_reset_coverage extends uvm_subscriber #(axi4lite_reset_evt);
  `uvm_component_utils(axi4lite_reset_coverage)

  typedef enum { RESET_IDLE, RESET_AW_W, RESET_B_WAIT, RESET_AR, RESET_R_WAIT } reset_phase_e;

  covergroup cg_reset with function sample(reset_phase_e phase);
    option.per_instance = 1;
    cp_reset_phase: coverpoint phase {
      bins idle   = {RESET_IDLE};
      bins aw_w   = {RESET_AW_W};
      bins b_wait = {RESET_B_WAIT};
      bins ar     = {RESET_AR};
      bins r_wait = {RESET_R_WAIT};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_reset = new();
  endfunction

  function void write(axi4lite_reset_evt t);
    if (t.aborted.size() == 0)
      cg_reset.sample(RESET_IDLE);
    foreach (t.aborted[i])
      case (t.aborted[i])
        ABORT_AW_W:   cg_reset.sample(RESET_AW_W);
        ABORT_B_WAIT: cg_reset.sample(RESET_B_WAIT);
        ABORT_AR:     cg_reset.sample(RESET_AR);
        ABORT_R_WAIT: cg_reset.sample(RESET_R_WAIT);
      endcase
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("COVERAGE", $sformatf("Reset coverage for %s: %0.2f%% (this seed)",
              get_full_name(), cg_reset.get_inst_coverage()), UVM_LOW)
  endfunction
endclass
