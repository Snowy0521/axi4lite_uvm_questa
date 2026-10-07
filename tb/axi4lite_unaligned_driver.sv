// ============================================================================
// axi4lite_unaligned_driver.sv
//
// Drives unaligned addresses -- random byte-select bits under the word
// address, on half the writes and reads -- swapped in for axi4lite_driver
// by a factory override (axi4lite_unaligned_test); the env and agent are
// unchanged. axi4lite_txn's c_addr_align rules these addresses out, so no
// sequence produces them, but the spec defines them: the DUT ignores the
// byte-select bits and accesses the whole word. Without this driver nothing
// would notice if that changed (e.g. unaligned answered SLVERR).
//
// Legal for this DUT, so the scoreboard, coverage and the monitor's
// outstanding check must still pass. The unaligned address is only on the
// bus (the monitor and scoreboard see it there); the item gets its aligned
// address back afterwards, since the random sequence reads back wr.addr
// under c_addr_align and would fail to randomize otherwise.
// ============================================================================

class axi4lite_unaligned_driver extends axi4lite_driver;
  `uvm_component_utils(axi4lite_unaligned_driver)

  // Checked in check_phase so the test can't pass without having injected.
  protected int unsigned n_unaligned;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task drive_write(axi4lite_txn tr);
    bit [ADDR_WIDTH-1:0] addr = tr.addr;
    misalign(tr);
    super.drive_write(tr);
    tr.addr = addr;
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
    super.check_phase(phase);
    if (n_unaligned == 0)
      `uvm_error("UNALIGNED_DRV", "no unaligned address was ever driven")
    else
      `uvm_info("UNALIGNED_DRV", $sformatf("drove %0d unaligned addresses", n_unaligned), UVM_LOW)
  endfunction

endclass
