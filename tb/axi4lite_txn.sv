// ============================================================================
// axi4lite_txn.sv
//
// The transaction class driven by the sequencer/driver and reconstructed by
// the monitor. Represents ONE AXI4-Lite operation: a single-beat read or
// write.
// ============================================================================

typedef enum bit { AXI_WRITE, AXI_READ } axi4lite_op_e;

class axi4lite_txn extends uvm_sequence_item;

  rand axi4lite_op_e                               op;
  rand bit [axi4lite_pkg::ADDR_WIDTH-1:0]          addr;     // matches ADDR_WIDTH on the DUT/interface
  rand bit [axi4lite_pkg::DATA_WIDTH-1:0]          wdata;    // valid only for op == AXI_WRITE
  rand bit [axi4lite_pkg::STRB_WIDTH-1:0]          wstrb;    // valid only for op == AXI_WRITE
       bit [axi4lite_pkg::DATA_WIDTH-1:0]          rdata;    // filled in by the monitor/driver on a read
       bit [1:0]                                   resp;     // BRESP/RRESP as observed

  // --------------------------------------------------------------------
  // Constraints
  // --------------------------------------------------------------------
  constraint c_addr_align {
    addr % axi4lite_pkg::STRB_WIDTH == 0;               
  }

  constraint c_wstrb_default {
    soft wstrb == '1;        // default to a full-word write unless overridden
  }

  // --------------------------------------------------------------------
  // Factory registration and field automation  
  // --------------------------------------------------------------------
  `uvm_object_utils_begin(axi4lite_txn)
    `uvm_field_enum(axi4lite_op_e, op,    UVM_ALL_ON) 
    `uvm_field_int  (addr,                UVM_ALL_ON) 
    `uvm_field_int  (wdata,               UVM_ALL_ON)
    `uvm_field_int  (wstrb,               UVM_ALL_ON)
    `uvm_field_int  (rdata,               UVM_ALL_ON)
    `uvm_field_int  (resp,                UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "axi4lite_txn");
    super.new(name);
  endfunction

  function string convert2string();
    if (op == AXI_WRITE)
      return $sformatf("WRITE addr=0x%0h wdata=0x%0h wstrb=0b%b", addr, wdata, wstrb);
    else
      return $sformatf("READ  addr=0x%0h rdata=0x%0h resp=0b%b", addr, rdata, resp);
  endfunction

endclass
