// ============================================================================
// axi4lite_sequencer.sv
//
// Nothing to customize for a basic environment -- uvm_sequencer parameterized
// on our transaction type is sufficient. Kept as its own typedef/class for
// clarity and to leave room for a p_sequencer-style virtual sequencer later.
// ============================================================================

typedef uvm_sequencer #(axi4lite_txn) axi4lite_sequencer;
