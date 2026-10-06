// ============================================================================
// axi4lite_coverage_collector.sv
//
// Coverage collector for AXI4-Lite interface transactions. 
// Collects coverage on the address, data, and response fields of both read and write transactions. 
// ============================================================================


class axi4lite_coverage_collector extends uvm_subscriber #(axi4lite_txn);
    `uvm_component_utils(axi4lite_coverage_collector)


    covergroup cg_axi4lite with function sample(
	   axi4lite_op_e				op,
	   logic [axi4lite_pkg::ADDR_WIDTH-1:0] 	addr,
	   logic [axi4lite_pkg::DATA_WIDTH-1:0]		wdata,
	   logic [axi4lite_pkg::STRB_WIDTH-1:0]		wstrb,
	   logic [1:0]					resp); 

        option.per_instance = 1; // Each instance of the coverage collector will have its own coverage group

        cp_op: coverpoint op {
            bins write = {AXI_WRITE};
            bins read = {AXI_READ};
        }

        cp_addr: coverpoint addr {
            // every byte address of the register file, including unaligned ones
            // in the last word (axi4lite_corner_driver drives those)
            bins in_range = {[0 : axi4lite_pkg::NUM_REGS*axi4lite_pkg::STRB_WIDTH - 1]};
            bins out_of_range = {[axi4lite_pkg::NUM_REGS*axi4lite_pkg::STRB_WIDTH : axi4lite_pkg::MAX_ADDR]};
        }

        // Binned on the top two bits: same ranges as [0, 2^(W-2)),
        // [2^(W-2), 2^(W-1)), [2^(W-1), 2^W), but 2**(W-1) overflows a
        // 32-bit int (W=32: bin 'high' was silently dropped; W=64: all
        // three bins covered every value).
        cp_wdata: coverpoint wdata[axi4lite_pkg::DATA_WIDTH-1 -: 2] iff (op == AXI_WRITE) {
            bins low  = {2'b00};
            bins mid  = {2'b01};
            bins high = {[2'b10 : 2'b11]};
        }

        cp_wstrb: coverpoint wstrb iff (op == AXI_WRITE) {
            bins all_zero = {'0};
            bins all_one =  {'1};
            bins others = default;
        }

        cp_resp: coverpoint resp {
            bins ok = {AXI_RESP_OKAY};
            bins slverr = {AXI_RESP_SLVERR};
        }

        // cross coverage between coverpoints
        cx_op_addr: 	cross cp_op, cp_addr;

        // An in-range access must never get SLVERR, an out-of-range access
        // must never get OKAY -- illegal_bins inside a cross flags. 
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
        	$sformatf("Overall coverage for %s: %0.2f%%", get_full_name(), cg_axi4lite.get_inst_coverage()),
        	UVM_LOW)
    endfunction    
endclass




