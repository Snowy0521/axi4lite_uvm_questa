// ============================================================================
// axi4lite_scoreboard.sv
//
// A shadow-register-model scoreboard: rather than comparing against a
// separately-generated "expected" transaction stream, this scoreboard
// maintains its own internal model of the DUT's register file, updated on
// every observed write, and checks every observed read against it.
// ============================================================================

class axi4lite_scoreboard extends uvm_component;
  `uvm_component_utils(axi4lite_scoreboard)

  uvm_analysis_imp #(axi4lite_txn, axi4lite_scoreboard) imp; // terminator, write in scoreboard.write()

  // shadow model of the DUT's register file -- word-addressed
  // chose associative array for large address spaces if NUM_REGS gets big
  protected bit [axi4lite_pkg::DATA_WIDTH-1:0] shadow_regs [int unsigned]; // associative array indexed by word address
  protected int unsigned num_regs, num_writes, num_reads, num_errors;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    imp = new("imp", this);
  endfunction 

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(int unsigned)::get(this, "", "num_regs", num_regs))
      num_regs = 16;   // default, matches the DUT's default NUM_REGS = 16
  endfunction

  // called automatically by the monitor's analysis port on every completed txn
  function void write(axi4lite_txn tr);

    int unsigned word_idx = tr.addr >> axi4lite_pkg::ADDR_LSB;
    bit          in_range = (word_idx < num_regs);

    `uvm_info("SB", "write() entered", UVM_HIGH)
    
    if (tr.op == AXI_WRITE) begin
      num_writes++;
      handle_write(tr, word_idx, in_range);
    end else begin
      num_reads++;
      handle_read(tr, word_idx, in_range);
    end
  endfunction

  // write: update the shadow model and check for out-of-range writes
  protected function void handle_write(axi4lite_txn tr, int unsigned word_idx, bit in_range);
    if (in_range) begin
      bit resp_ok = check_resp_ok(tr, "write");
      if (resp_ok)
        // in-range + OKAY -> correct, update the shadow model
        update_shadow_model(word_idx, tr);
    end else begin
      // out-of-range -> expect SLVERR, report an error if not
      check_resp_slverr(tr, "write");
    end
  endfunction

  // read: check response and compare against the shadow model
  protected function void handle_read(axi4lite_txn tr, int unsigned word_idx, bit in_range);
    if (in_range) begin
      bit resp_ok = check_resp_ok(tr, "read");
      if (resp_ok) 
        // in-range + OKAY -> correct, check the read data against the shadow model 
        check_read_data(word_idx, tr);
    end else begin
      // out-of-range -> expect SLVERR, report an error if not
      check_resp_slverr(tr, "read");
    end
  endfunction

  // update the shadow model with the write data, respecting the write strobes
  protected function void update_shadow_model(int unsigned word_idx, axi4lite_txn tr);
    bit [axi4lite_pkg::DATA_WIDTH-1:0] cur = shadow_regs.exists(word_idx) ? shadow_regs[word_idx] : '0;
    for (int b = 0; b < axi4lite_pkg::STRB_WIDTH; b++)
      if (tr.wstrb[b]) cur[b*8 +: 8] = tr.wdata[b*8 +: 8];
    shadow_regs[word_idx] = cur;
  endfunction

  // compare the read data against the shadow model, report an error if it doesn't match
  protected function void check_read_data(int unsigned word_idx, axi4lite_txn tr);
    bit [axi4lite_pkg::DATA_WIDTH-1:0] expected = shadow_regs.exists(word_idx) ? shadow_regs[word_idx] : '0;
    if (tr.rdata !== expected) begin
      num_errors++;
      `uvm_error("SB", $sformatf(
        "READ MISMATCH addr=0x%0h expected=0x%0h actual=0x%0h",
        tr.addr, expected, tr.rdata));
    end
  endfunction

  // check that the response is OKAY (2'b00), report an error if not
  protected function bit check_resp_ok(axi4lite_txn tr, string ctx);
    if (tr.resp != 2'b00) begin
      num_errors++;
      `uvm_error("SB", $sformatf(
        "in-range %s to addr=0x%0h expected OKAY but got resp=%b", ctx, tr.addr, tr.resp));
      return 0;
    end
    return 1;
  endfunction

  // check that the response is SLVERR (2'b10), report an error if not
  protected function void check_resp_slverr(axi4lite_txn tr, string ctx);
    if (tr.resp != 2'b10) begin
      num_errors++;
      `uvm_error("SB", $sformatf(
        "out-of-range %s to addr=0x%0h expected SLVERR but got resp=%b", ctx, tr.addr, tr.resp));
    end
  endfunction


  // report_phase: print a summary of the scoreboard's activity and any errors
  function void report_phase(uvm_phase phase);
    `uvm_info("SB", $sformatf(
      "SCOREBOARD SUMMARY: writes=%0d reads=%0d errors=%0d",
      num_writes, num_reads, num_errors), UVM_LOW)
    if ((num_errors == 0) && (num_writes + num_reads != 0))
      `uvm_info("SB", "*** SCOREBOARD: ALL CHECKS PASSED ***", UVM_LOW)
    else
      `uvm_error("SB", $sformatf("*** SCOREBOARD: %0d CHECK(S) FAILED ***", num_errors))
  endfunction

endclass
