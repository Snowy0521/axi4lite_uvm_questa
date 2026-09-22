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
  rand bit [axi4lite_pkg::ADDR_WIDTH-1:0] addr;
  rand bit [axi4lite_pkg::DATA_WIDTH-1:0] wdata;
  rand bit [axi4lite_pkg::STRB_WIDTH-1:0] wstrb;

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

  rand bit [axi4lite_pkg::ADDR_WIDTH-1:0] addr;

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

    for (int i = 0; i < axi4lite_pkg::NUM_SMOKE_TXNS; i++) begin
      wr = axi4lite_write_seq::type_id::create($sformatf("wr%0d", i));
      wr.addr  = i * axi4lite_pkg::STRB_WIDTH;
      wr.wdata = {(axi4lite_pkg::DATA_WIDTH/32){32'hA000_0000 + i}};
      wr.wstrb = '1;
      wr.start(m_sequencer, this);
    end

    for (int i = 0; i < axi4lite_pkg::NUM_SMOKE_TXNS; i++) begin
      rd = axi4lite_read_seq::type_id::create($sformatf("rd%0d", i));
      rd.addr = i * axi4lite_pkg::STRB_WIDTH;
      rd.start(m_sequencer, this);
    end
  endtask
endclass



// --------------------------------------------------------------------------
// Constrained-random write-then-read-back traffic generator.
// --------------------------------------------------------------------------
class axi4lite_random_seq extends axi4lite_base_seq;
  `uvm_object_utils(axi4lite_random_seq)

  function new(string name = "axi4lite_random_seq");
    super.new(name);
  endfunction

  task body();
    repeat (axi4lite_pkg::NUM_TXNS) begin
      axi4lite_txn wr, rd;

      wr = axi4lite_txn::type_id::create("wr");
      wr.c_wstrb_default.constraint_mode(0);
      start_item(wr);
      if (!wr.randomize() with {
        op   == AXI_WRITE;
        addr dist {
          [0 : (NUM_REGS-1)*STRB_WIDTH]      :/ 90,   // in-range, word-aligned
          [NUM_REGS*STRB_WIDTH : MAX_ADDR]   :/ 10    // out-of-range -> SLVERR path
        };
	      wstrb dist {['0 : '1]};
      }) `uvm_error("SEQ", "randomize failed in axi4lite_random_seq for write transaction")
      finish_item(wr);

      rd = axi4lite_txn::type_id::create("rd");
      start_item(rd);
      if (!rd.randomize() with {
        op   == AXI_READ;
        addr == wr.addr;  // read back the same address we just wrote
      }) `uvm_error("SEQ", "randomize failed in axi4lite_random_seq for read transaction")
      finish_item(rd);
    end
  endtask
endclass
