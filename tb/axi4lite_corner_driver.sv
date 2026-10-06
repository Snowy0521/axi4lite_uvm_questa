// ============================================================================
// axi4lite_corner_driver.sv
//
// Injects bus-level stimulus the sequences can't express, swapped in for
// axi4lite_driver by a factory override (axi4lite_corner_test) -- the env and
// agent are unchanged:
//
//   - AW/W skew: one of the two channels starts 1..MAX_SKEW cycles after
//     the other, in either order. The base driver always starts both on
//     the same cycle, so the DUT's "AW first" and "W first" latch paths
//     (spec: AWVALID/WVALID may arrive in either order) are never reached.
//   - Unaligned addresses: random byte-select bits under the word address,
//     on writes and reads. axi4lite_txn's c_addr_align rules these out;
//     per the spec the DUT ignores those bits and accesses the whole word.
//
// Both are legal for this DUT, so the scoreboard, coverage and the
// monitor's outstanding check must still pass. The unaligned address is
// only on the bus (the monitor and scoreboard see it there); the item gets
// its aligned address back afterwards, since the random sequence reads
// back wr.addr under c_addr_align and would fail to randomize otherwise.
// ============================================================================

class axi4lite_corner_driver extends axi4lite_driver;
  `uvm_component_utils(axi4lite_corner_driver)

  localparam int unsigned MAX_SKEW = 4;   // cycles; well under TIMEOUT_CYCLES

  // Delay for each channel of the write in progress; at most one is nonzero.
  protected int unsigned aw_delay, w_delay;

  // Injection counts, checked in check_phase so the test can't pass
  // without having injected anything.
  protected int unsigned n_aw_first, n_w_first, n_unaligned;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task drive_write(axi4lite_txn tr);
    bit [ADDR_WIDTH-1:0] addr = tr.addr;
    int unsigned skew = $urandom_range(MAX_SKEW, 0);
    aw_delay = 0;
    w_delay  = 0;
    if (skew != 0) begin
      if ($urandom_range(1, 0)) begin w_delay  = skew; n_aw_first++; end
      else                      begin aw_delay = skew; n_w_first++;  end
    end
    misalign(tr);
    super.drive_write(tr);
    tr.addr = addr;
  endtask

  virtual task drive_aw(axi4lite_txn tr);
    repeat (aw_delay) @(vif.drv_cb);
    super.drive_aw(tr);
  endtask

  virtual task drive_w(axi4lite_txn tr);
    repeat (w_delay) @(vif.drv_cb);
    super.drive_w(tr);
  endtask

  virtual task drive_read(axi4lite_txn tr);
    bit [ADDR_WIDTH-1:0] addr = tr.addr;
    misalign(tr);
    super.drive_read(tr);
    tr.addr = addr;
  endtask

  // Half the time, set the byte-select bits below the word address.
  protected function void misalign(axi4lite_txn tr);
    if ($urandom_range(1, 0)) begin
      tr.addr[ADDR_LSB-1:0] = $urandom_range(STRB_WIDTH - 1, 1);
      n_unaligned++;
    end
  endfunction

  function void check_phase(uvm_phase phase);
    string counts = $sformatf("AW first=%0d, W first=%0d, unaligned=%0d",
                              n_aw_first, n_w_first, n_unaligned);
    super.check_phase(phase);
    if (n_aw_first == 0 || n_w_first == 0 || n_unaligned == 0)
      `uvm_error("CORNER_DRV", {"an injection never happened: ", counts})
    else
      `uvm_info("CORNER_DRV", {"injected ", counts}, UVM_LOW)
  endfunction

endclass
