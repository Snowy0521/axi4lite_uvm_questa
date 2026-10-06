// ============================================================================
// axi4lite_coverage_collector.sv
//
// Coverage collector for AXI4-Lite interface transactions, sampled on every
// completed transaction (after its response) from the monitor. The model is
// closed on the coverage merged across a uvm-sweep, not per seed: one seed
// of NUM_TXNS writes can't be expected to hit every register x op and every
// data/strobe pattern.
// ============================================================================


class axi4lite_coverage_collector extends uvm_subscriber #(axi4lite_txn);
    `uvm_component_utils(axi4lite_coverage_collector)


    covergroup cg_axi4lite with function sample(
	   axi4lite_op_e				op,
	   logic [ADDR_WIDTH-1:0] 	addr,
	   logic [DATA_WIDTH-1:0]		wdata,
	   logic [STRB_WIDTH-1:0]		wstrb,
	   logic [1:0]					resp); 

        option.per_instance = 1; // Each instance of the coverage collector will have its own coverage group

        cp_op: coverpoint op {
            bins write = {AXI_WRITE};
            bins read = {AXI_READ};
        }

        // Address region, for the response cross: in range (must be OKAY)
        // or not (must be SLVERR). Byte addresses, so unaligned ones in the
        // last word (axi4lite_corner_driver drives those) count as in range.
        cp_addr: coverpoint addr {
            bins in_range     = {[0 : NUM_REGS*STRB_WIDTH - 1]};
            bins out_of_range = {[NUM_REGS*STRB_WIDTH : MAX_ADDR]};
        }

        // Word index: every register on its own (one in_range bin is closed
        // by touching register 0 once), the first word past the range,
        // where an off-by-one in the range check shows, and the rest.
        cp_word: coverpoint addr[ADDR_WIDTH-1:ADDR_LSB] {
            bins regs[]    = {[0 : NUM_REGS - 1]};
            bins first_oor = {NUM_REGS};
            bins rest_oor  = {[NUM_REGS + 1 : MAX_WORD]};
        }

        // Bit patterns, not value ranges: together they drive every data
        // bit both ways, which is what finds a stuck or swapped register bit.
        cp_wdata: coverpoint wdata iff (op == AXI_WRITE) {
            bins zeros = {0};
            bins ones  = {DATA_ONES};
            bins alt_a = {DATA_ALT_A};
            bins alt_5 = {DATA_ALT_5};
        }

        // Each byte lane on its own and each half word, where a lane
        // mix-up in the strobe merge shows; plus nothing and everything.
        cp_wstrb: coverpoint wstrb iff (op == AXI_WRITE) {
            bins none    = {0};
            bins full    = {STRB_FULL};
            bins lane[]  = {[1 : STRB_FULL]} with ($countones(item) == 1);
            bins lo_half = {STRB_LO_HALF};
            bins hi_half = {STRB_HI_HALF};
        }

        // This DUT only answers OKAY or SLVERR; anything else is an error
        // here, not a silently ignored value.
        cp_resp: coverpoint resp {
            bins ok     = {AXI_RESP_OKAY};
            bins slverr = {AXI_RESP_SLVERR};
            illegal_bins exokay = {AXI_RESP_EXOKAY};
            illegal_bins decerr = {AXI_RESP_DECERR};
        }

        // Every register both written and read, and out-of-range writes as
        // well as reads. Without it, reads alone can close cp_word: an
        // out-of-range write aliased onto a register could then go untested.
        cx_op_word: cross cp_op, cp_word;

        // Each region seen with its response. An in-range access must never
        // get SLVERR, an out-of-range one never OKAY -- illegal_bins flag it.
        cx_addr_resp: cross cp_addr, cp_resp {
            illegal_bins invalid_out_of_range_ok = binsof(cp_addr.out_of_range) && binsof(cp_resp.ok);
            illegal_bins invalid_in_range_err    = binsof(cp_addr.in_range) && binsof(cp_resp.slverr);
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_axi4lite = new(); 
    endfunction

    // Argument must be named `t` to match uvm_subscriber#(T)'s pure virtual write(T t) exactly
    function void write(axi4lite_txn t);
        cg_axi4lite.sample(t.op, t.addr, t.wdata, t.wstrb, t.resp);
    endfunction

    function void report_phase(uvm_phase phase);
    	super.report_phase(phase);
    	`uvm_info("COVERAGE",
        	$sformatf("Overall coverage for %s: %0.2f%% (this seed; sign-off is on the merged sweep)",
        	          get_full_name(), cg_axi4lite.get_inst_coverage()),
        	UVM_LOW)
    endfunction    
endclass




