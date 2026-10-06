// ============================================================================
// axi4lite_sequences.sv
//
// A small library of reusable sequences, from simple directed single-item
// sequences up to a constrained-random traffic generator.
// ============================================================================

// --------------------------------------------------------------------------
// Base sequence class for all axi4lite sequences. Provides a handle to the
// environment and the agent's sequencer, so that derived sequences can access
// the DUT's configuration and start sub-sequences on the agent's sequencer.
// --------------------------------------------------------------------------
class axi4lite_base_seq extends uvm_sequence #(axi4lite_txn);
  `uvm_object_utils(axi4lite_base_seq)

  function new(string name = "axi4lite_base_seq");
    super.new(name);
  endfunction 

  virtual task body();
    `uvm_fatal("SEQ", "axi4lite_base_seq is abstract -- use a derived sequence class")
  endtask
endclass

// --------------------------------------------------------------------------
// Directed single write
// --------------------------------------------------------------------------
class axi4lite_write_seq extends axi4lite_base_seq;
  `uvm_object_utils(axi4lite_write_seq)

  // directed single write transaction parameters
  rand bit [ADDR_WIDTH-1:0] addr;
  rand bit [DATA_WIDTH-1:0] wdata;
  rand bit [STRB_WIDTH-1:0] wstrb;

  function new(string name = "axi4lite_write_seq");
    super.new(name);
  endfunction

  task body();
    axi4lite_txn tr = axi4lite_txn::type_id::create("tr");
    start_item(tr);
    if (!tr.randomize() with {
      op    == AXI_WRITE;
      addr  == local::addr;
      wdata == local::wdata;
      wstrb == local::wstrb;
    }) `uvm_error("SEQ", "randomize failed in axi4lite_write_seq")
    finish_item(tr);
  endtask
endclass

// --------------------------------------------------------------------------
// Directed single read
// --------------------------------------------------------------------------
class axi4lite_read_seq extends axi4lite_base_seq;
  `uvm_object_utils(axi4lite_read_seq)

  rand bit [ADDR_WIDTH-1:0] addr;

  function new(string name = "axi4lite_read_seq");
    super.new(name);
  endfunction

  task body();
    axi4lite_txn tr = axi4lite_txn::type_id::create("tr");
    start_item(tr);
    if (!tr.randomize() with {
      op   == AXI_READ;
      addr == local::addr;
    }) `uvm_error("SEQ", "randomize failed in axi4lite_read_seq")
    finish_item(tr);
  endtask
endclass

// --------------------------------------------------------------------------
// Smoke sequence - wraps the number of NUM_SMOKE_TXNS directed writes and then 
// same times directed reads from axi4lite_smoke_test
// --------------------------------------------------------------------------
class axi4lite_smoke_seq extends axi4lite_base_seq;
  `uvm_object_utils(axi4lite_smoke_seq)

  function new(string name = "axi4lite_smoke_seq");
    super.new(name);
  endfunction

  task body();
    axi4lite_write_seq wr;
    axi4lite_read_seq  rd;

    for (int i = 0; i < NUM_SMOKE_TXNS; i++) begin
      wr = axi4lite_write_seq::type_id::create($sformatf("wr%0d", i));
      wr.addr  = i * STRB_WIDTH;
      wr.wdata = {(DATA_WIDTH/32){32'hA000_0000 + i}};
      wr.wstrb = '1;
      wr.start(m_sequencer, this);
    end

    for (int i = 0; i < NUM_SMOKE_TXNS; i++) begin
      rd = axi4lite_read_seq::type_id::create($sformatf("rd%0d", i));
      rd.addr = i * STRB_WIDTH;
      rd.start(m_sequencer, this);
    end
  endtask
endclass



// --------------------------------------------------------------------------
// Constrained-random traffic: NUM_TXNS writes, each read back, plus a read
// of some other register 30% of the time. Address, data and strobe are
// biased toward what the coverage model asks for (axi4lite_coverage_collector).
// --------------------------------------------------------------------------
class axi4lite_random_seq extends axi4lite_base_seq;
  `uvm_object_utils(axi4lite_random_seq)

  function new(string name = "axi4lite_random_seq");
    super.new(name);
  endfunction

  task body();
    repeat (NUM_TXNS) begin
      axi4lite_txn         wr, rd;
      bit                  fix_data, fix_strb;
      bit [DATA_WIDTH-1:0] data;
      bit [STRB_WIDTH-1:0] strb;

      // Data: 20% one of cp_wdata's bit patterns (5% each), else random.
      fix_data = 1;
      case ($urandom_range(19, 0))
        0:       data = '0;
        1:       data = DATA_ONES;
        2:       data = DATA_ALT_A;
        3:       data = DATA_ALT_5;
        default: fix_data = 0;
      endcase

      // Strobe: 10% none, 20% full, 20% one byte lane, 10% a half word,
      // 40% any other partial pattern. Uniform over all patterns would give
      // each single lane 1/2^STRB_WIDTH (1/256 at 64-bit).
      fix_strb = 1;
      case ($urandom_range(9, 0))
        0:       strb = '0;
        1, 2:    strb = STRB_FULL;
        3, 4:    strb = STRB_WIDTH'(1) << $urandom_range(STRB_WIDTH - 1, 0);
        5:       strb = $urandom_range(1, 0) ? STRB_LO_HALF : STRB_HI_HALF;
        default: fix_strb = 0;
      endcase

      wr = axi4lite_txn::type_id::create("wr");
      wr.c_wstrb_default.constraint_mode(0);
      start_item(wr);
      if (!wr.randomize() with {
        op   == AXI_WRITE;
        // On the word index, not the byte address: c_addr_align would
        // otherwise drop a different fraction of each group and the split
        // would not be what the weights say (it would be badly skewed by
        // an all-aligned boundary group). The two words either side of
        // the range edge get their own weight -- that's where an
        // off-by-one in the range check shows.
        addr[ADDR_WIDTH-1:ADDR_LSB] dist {
          [0 : NUM_REGS-2]        :/ 70,   // registers below the last
          NUM_REGS-1              := 10,   // last register: OKAY
          NUM_REGS                := 10,   // first word past it: SLVERR
          [NUM_REGS+1 : MAX_WORD] :/ 10    // rest of the space: SLVERR
        };
        local::fix_data ->  wdata == local::data;
        local::fix_strb ->  wstrb == local::strb;
        !local::fix_strb -> (wstrb != 0 && wstrb != STRB_FULL);
      }) `uvm_error("SEQ", "randomize failed in axi4lite_random_seq for write transaction")
      finish_item(wr);

      rd = axi4lite_txn::type_id::create("rd");
      start_item(rd);
      if (!rd.randomize() with {
        op   == AXI_READ;
        addr == wr.addr;  // read back the same address we just wrote
      }) `uvm_error("SEQ", "randomize failed in axi4lite_random_seq for read transaction")
      finish_item(rd);

      // Read back alone only ever reads a register right after writing it,
      // so a write that corrupts a *different* register (e.g. an
      // out-of-range write aliased onto one) is overwritten before it is
      // read, unless a partial strobe happens to leave it visible.
      if ($urandom_range(9, 0) < 3) begin
        rd = axi4lite_txn::type_id::create("rd_other");
        start_item(rd);
        if (!rd.randomize() with {
          op == AXI_READ;
          addr[ADDR_WIDTH-1:ADDR_LSB] inside {[0 : NUM_REGS-1]};
          addr != wr.addr;
        }) `uvm_error("SEQ", "randomize failed in axi4lite_random_seq for read of another register")
        finish_item(rd);
      end
    end
  endtask
endclass
