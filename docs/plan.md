# Verification plan

How the design in [axi4lite_slave_spec.md](axi4lite_slave_spec.md) is verified. Overview, how to run and
results: [README.md](../README.md).

Status markers: **(done)** exists in the repo today; **(planned)** decided, not implemented yet. Every planned item
names the step in §6 that delivers it.

---

## 1. Sampling conventions

**Clock and reset.** One clock `clk`, rising edge only. `rst_n` is asynchronous active-low (spec §5.3): the DUT's
flops clear as soon as it falls, without waiting for an edge.

**What a `@(posedge clk)` assertion sees.** SVA samples in the preponed region: the values just *before* the edge.
So on the edge where `arvalid && arready` is sampled high, `regfile` is still the value from before that edge.
A write that fires on that same edge is not visible yet. That is why `a_read_data_matches_regfile` compares
`rdata` against `$past(regfile[...])`.

**Testbench sampling.** Both clocking blocks in `tb/axi4lite_if.sv` sample with `input #1step`, so they see the same
pre-edge values as the assertions. `drv_cb` drives with `output #2`: a value driven at clocking event E reaches
the pins at E + 2 ns, and the DUT first samples it at the next edge. `rst_n` is outside both clocking blocks, so
the driver and monitor see it change immediately.

**Sample index.** The monitor counts `mon_cb` events from time 0 in `cyc` (planned, step 5c). It does not restart
at reset, so stamps stay monotonic across resets. A *sample* is one `mon_cb` event, and "sample n" is the
value of `cyc` there. All UVM ordering rules (§3.4) are written in sample indices, not in edges.

---

## 2. Formal verification

Sign-off: **every assertion a full proof (not bounded), every cover reached, in both data widths, and every assertion
also proven with the assumptions compiled out.** `rst_n` stays free after qverify's init sequence
(`-auto_constraint_off`), so a reset mid-transaction is part of every proof.

### 2.1 Checker conventions (done)

- Each checker module declares `default clocking @(posedge clk)` and `default disable iff (!rst_n)` itself.
  The reset properties (`a_bvalid_low_in_reset`, `a_rvalid_low_in_reset`, `m_*valid_low_in_reset`, the
  `cp_reset_*` covers) opt out with `disable iff (1'b0)`.
- There is no shared defaults header, and no X-safe `rst_n !== 1'b1` form. In the UVM bench `rst_n` is declared
  `= 1'b1` and dropped at `#1`, and the first `posedge clk` is at 5 ns. So no edge samples `rst_n = X`, and the DUT's
  asynchronous reset sees a real negedge before the first posedge (§3.3; in `tb_top` from step 5a, in the interface
  from step 5b). Revisit only if binding the checkers into UVM (§3.2) shows a
  failure before the first reset. Any later change of this kind must leave the `disable iff (1'b0)` properties
  alone.
- Checker state (fifo models, latched references) has `rst_n` as its asynchronous reset. The one deliberate
  exception is `sym_idx` (§2.3): it has no reset, so formal is free to choose it.

### 2.2 Blackbox protocol (done)

`formal/axi4lite_blackbox_protocol.sv`, AXI ports only, no knowledge of the RTL's internals.

- **X checks:** `a_no_x_awready`, `a_no_x_wready`, `a_no_x_bvalid`, `a_no_x_bresp`, `a_no_x_arready`, `a_no_x_rvalid`,
  `a_no_x_rresp`, `a_rvalid_requires_rdata`.
- **Reset (spec §4.1.1):** `a_bvalid_low_in_reset`, `a_rvalid_low_in_reset`.
- **Stability (spec §4.1.2):** `a_bvalid_stable` (with `bresp`), `a_rvalid_stable` (with `rdata`, `rresp`).
- **Write response (spec §4.2):** `a_bvalid_requires_aw_and_w`, `a_bvalid_not_wait_bready`, `a_bresp_legal_value`,
  `a_write_okay_in_range`, `a_write_slverr_out_of_range`.
- **Read response (spec §4.3):** `a_rvalid_requires_ar`, `a_ar_leads_to_rvalid`, `a_read_okay_in_range`,
  `a_read_slverr_out_of_range`, `a_rresp_legal_value`.
- **Liveness, bounded:** `a_awready_when_idle`, `a_wready_when_idle`, `a_arready_when_idle` (within
  `READY_TIMEOUT = 8`); responses within `RESP_TIMEOUT = 8`.
- Requests are paired with responses by in-order queues (`axi4lite_fifo_model.sv`, `MAX_OUTSTANDING = 2`), each
  with its own `a_no_overflow`.

### 2.3 Blackbox end-to-end data (done)

`formal/axi4lite_blackbox_data.sv`. `a_e2e_read_data` checks every read of a **symbolic register index**
`sym_idx` against the completed writes to it, merging byte lanes by WSTRB.

- Under `QUESTA_FORMAL`, `sym_idx` is a register with no reset that holds its value, so formal picks any initial
  value and one proof covers every register.
- In simulation (`make formal`, and in UVM once the checkers are bound in), `sym_idx` is `$urandom_range` at time 0.
  So **each seed checks one register end to end**; the sweep covers the rest.
- A read is only checked when no write to `sym_idx` is outstanding at its AR handshake.
- Covers: `cp_e2e_read_checked_nonzero`, `cp_e2e_partial_strobe_merge`, `cp_e2e_sym_last_reg`.

### 2.4 Whitebox regfile (done)

`formal/axi4lite_whitebox_regfile.sv`, bound to `dut.regfile`.

- `g_strobe_byte_check[b].a_write_enabled_byte_updated` / `.a_write_disabled_byte_preserved`, one pair per byte
  lane.
- `g_regfile_frame[r].a_regfile_changes_only_on_own_write`, one per register: the frame condition.
- `a_read_data_matches_regfile`: `rdata` equals the register value at the AR handshake edge (`$past`, §1).

### 2.5 Assumptions (done)

`formal/axi4lite_assumptions.sv`, 15 `assume property`: no X on master signals, master VALIDs low in reset, VALID
held and payload stable until READY. **No proof depends on them** (`make formal-verify-noassume`).
In UVM they are bound unchanged and act as a legal-master check on the UVM driver (§3.2).

### 2.6 Covers (done)

`formal/axi4lite_covers.sv` (40) plus the 3 e2e covers above: every handshake, READY before and after VALID on every
channel, every response code, AW/W in either order and in the same cycle, WSTRB none / partial / full,
back-to-back writes and reads, read after write, write and read in the same cycle, B and R pending together,
a write arriving while B is pending, write-then-read-back, and reset in the middle of a write, a B, or an R.

**Planned (step 5c, with G1):** two covers for the read/write ordering boundary (§3.4), on the same register:
`cp_rw_fire_before_ar` (BVALID first seen high at the AR handshake sample, `m == k`) and `cp_rw_fire_on_ar_edge`
(BVALID first seen high one sample after it, `m == k + 1`). They raise the expected cover count to 45.

### 2.7 Expected counts

These are the numbers the formal self-check (§2.8) compares against. Derivation for `assert` (32-bit / 64-bit):
protocol 25, e2e 1, whitebox 2 × lanes + `NUM_REGS` + 1 = 25 / 33, and `a_no_overflow` in each of the 6
fifo-model instances (3 in protocol, 3 in data) = 6. That gives 57 / 65. Covers: 40 + 3 = 43. The source line counts
(`grep "assert property"` = 31) are **not** the report counts, because of the generate loops and the fifo
instances.

| Configuration | Asserts proven | Covers reached | Assumes | Source |
|---|---|---|---|---|
| 32-bit | 57 | 43 | 15 | README, Questa Formal 2024.3 |
| 64-bit | 65 | 43 | 15 | README, Questa Formal 2024.3 |
| 32-bit, no assumptions | 57 | 43 (to confirm) | 0 | asserts: README; covers: first self-check run |
| 64-bit, no assumptions | 65 | 43 (to confirm) | 0 | as above |

"Covered with Warning" counts as covered, but its number is printed (33 at 32-bit per the README). Reason: at the
first tick `$rose` / `$stable` have no previous sample, qverify models it as a free control point and flags
witnesses that assign it. That cannot cause a false proof. A change in the number is worth a look.
Any change to this table is a deliberate edit in the same commit as the property change.

### 2.8 Questa Formal flow

`qverify -c -do` on the DUT plus `formal/` with `+define+QUESTA_FORMAL`, then `formal compile -d formal_tb`, then
`formal verify -auto_constraint_off`. Knobs: `DATA_WIDTH=32|64`, `NO_ASSUME=1` (compiles out the assumptions
instance). Script: `formal/run_formal.tcl` (done), started by `make formal-verify` as
`qverify -c -od build/formal -do formal/run_formal.tcl` from the repo root. It compiles `-f rtl/rtl.f -f formal/formal.f`
into its own `build/formal_work` library; every qverify output and `formal_report*.txt` land in `build/formal/`.

**Self-check (planned, step 3):** after each run, parse the report. Pass only if falsified = 0, inconclusive = 0,
uncovered = 0, and proven and covered equal the row of §2.7 for that configuration (kept machine-readable in
`formal/expected_counts.txt`). Mutation scoring (§4) needs this check on the clean design as its reference.

### 2.9 Formal in simulation (done)

`make formal` / `formal-sweep`: `formal_tb` without `QUESTA_FORMAL`, with `axi4lite_formal_driver.sv` as a random
legal master under vsim. This is not a proof.

**Mid-run reset (planned, step 4):** today reset happens only at time 0 (`formal_tb.sv:106-110`), with the same
time-0 race as `tb_top` (`rst_n = 0` in an `initial`, §3.3). In the same edit the power-on part becomes
`rst_n = 1'b1; #1 rst_n = 1'b0; repeat (3) @(posedge clk); @(negedge clk) rst_n = 1'b1;` inside the
simulation-only `initial`. The release moves to a negedge as well: today `repeat (3) @(posedge clk); rst_n = 1;`
releases on the posedge itself, so whether the DUT takes its reset branch at that edge, and whether that edge's
`default disable iff (!rst_n)` attempts are disabled, depends on process order. The power-on reset stays 3
posedges long, and no clock edge sees `rst_n` change. A declaration initialiser is not possible
there: `rst_n` is declared through `` `FTB_FREE`` (`formal_tb.sv:71`), which is an `input` under `QUESTA_FORMAL`.
The X → 1 at time 0 is not a negedge, and the 1 → 0 at 1 ns is a real one, after every process has started. A rare random
mid-run reset is added to that simulation-only reset block (inside the existing non-`QUESTA_FORMAL` code), **not**
to the driver. The driver already clears its VALIDs asynchronously (`axi4lite_formal_driver.sv:60-62` and the
same for W / AR), so it obeys `m_*valid_low_in_reset` without change. This gives two things: `make formal` /
`formal-sweep` exercise the reset properties in simulation, not only in qverify; and M09b becomes visible to the
mutation behaviour-difference check (§4).

A Verilator
version (props-sim) is **deferred**: Verilator rejects `$stable` / `$past` on the unpacked `regfile` in the whitebox
checker, and the checker is not rewritten for a weaker simulator.

---

## 3. UVM environment

Questa-only (UVM 1.2 shipped with Questa, `+define+UVM_NO_DPI`). There is no Verilator UVM flow.

### 3.1 Transactions (done)

One class, `axi4lite_txn`: the sequence fills `op`, `addr`, `wdata`, `wstrb`; the monitor fills `rdata`, `resp`,
`aw_w_order`, `resp_stall`. There is no separate monitor class: it would guard against no known bug (the monitor already rebuilds every field from the pins) and would double the subscriber interfaces. The guard is structural
instead: **the monitor creates a fresh object for every transaction it publishes, and the scoreboard and coverage
collector subscribe only to the monitor's port**, so nothing the driver touches reaches a checker.

Planned field (step 5c): `stamp`, the sample index of the event that orders the transaction (§3.4).

### 3.2 Components

- **Driver (done):** `axi4lite_driver`, one item at a time. AW and W are driven concurrently with a random skew in
  either order (`pick_skew`); BREADY / RREADY are stalled at random (`pick_ready_stall`); every wait has a
  timeout watchdog, and a timeout is fatal. `axi4lite_unaligned_driver` (factory override) adds random byte
  offsets to the address.
- **Monitor (done):** rebuilds every transaction from the pins through `mon_cb`. It counts raw handshakes per
  channel, and `check_phase` requires every request answered exactly once and every answer published.
- **Monitor X check (planned, step 5a):** today the UVM bench cannot see an X on a DUT output.
  `axi4lite_txn.rdata` / `.resp` are 2-state `bit`, so the monitor's copy from `mon_cb` turns X into 0, and an X
  response even reads as OKAY. The bound `a_no_x_*` checks see it, but mutation scoring builds without them
  (`UVM_CHECKERS=no`). So the monitor itself raises `MON_X` (`uvm_error`) on `$isunknown`, with **exactly the
  conditions of the bound checks**, `MON_X` ≡ `a_no_x_*` + `a_rvalid_requires_rdata`
  (`axi4lite_blackbox_protocol.sv:74-84, 183`). Then a `UVM_CHECKERS=no` build loses no X coverage:
  - `awready`, `wready`, `arready`, `bvalid`, `rvalid`: every sample with `rst_n === 1'b1`;
  - `bresp`: every sample with `bvalid` high, not only at the B handshake (an X during a backpressure wait already
    violates `a_no_x_bresp`, even if it settles by the handshake);
  - `rresp`, `rdata`: every sample with `rvalid` high, for the same reason.

  If either side changes, the other changes in the same commit. It checks before copying into the transaction. This is a black-box check, part of the UVM bench in
  every build.
- **Scoreboard (done):** shadow register model, WSTRB merge, OKAY in range / SLVERR out of range, read data
  against the shadow. `num_regs` comes from config_db, and a missing value is fatal.
- **Coverage collector (done):** §3.6.
- **Formal checkers bound into the DUT (planned, step 5a):** an **instance** bind, written inside `tb_top`, not a
  module-type bind:
  ```systemverilog
  `ifndef NO_UVM_CHECKERS
    bind dut axi4lite_assumptions       #(...) u_assumptions (...);
    bind dut axi4lite_blackbox_protocol #(...) u_bb_protocol (...);
    bind dut axi4lite_blackbox_data     #(...) u_bb_data     (...);
    bind dut axi4lite_whitebox_regfile  #(...) u_wb_regfile  (..., .regfile(regfile));
  `endif
  ```
  Reason: `make simple`, `make uvm` and `make formal` share one library (`build/questa_work`), and `formal_tb` already
  instantiates the same checkers explicitly. A module-type bind on `axi4lite_slave` would also reach the DUT of
  `formal_tb` / `tb_simple`, doubling the checkers there and changing their counts. Binding the instance `dut`
  scopes the checkers to `tb_top.dut`, and the port names (including `regfile`) still resolve in the DUT scope.
  The instance names are the same as in `formal_tb` (`u_assumptions`, `u_bb_protocol`, `u_bb_data`,
  `u_wb_regfile`), and they become children of `/tb_top/dut`. Two things are unaffected. `wave_uvm.do` only
  references `tb_top`, `intf` and `dut` signals. The code-coverage summary awk (`Makefile:213`) matches the
  exact instance `/tb_top/dut`, not its children, and the checkers are not compiled with `+cover` anyway.
  `axi4lite_covers` is not bound: cover results are formal sign-off, not a UVM goal. `axi4lite_blackbox_data`
  does carry the 3 e2e covers (`cp_e2e_*`), so they land in the UVM UCDBs as cover directives. They are
  **informational in UVM**: not part of any gate (the covergroup gate reads `TOTAL COVERGROUP COVERAGE`, and the
  code-coverage awk reads `/tb_top/dut` only). One can sit at 0 in a seed whose `sym_idx` never got a non-zero
  read; do not "fix" that.
  A failing property is a `** Error`, not a `UVM_ERROR`, and the regression counts it (§3.7). `UVM_CHECKERS=no`
  (which sets `+define+NO_UVM_CHECKERS`) builds without them; mutation scoring uses it to measure the UVM bench
  alone (§4).
- **VCD dump (done):** only with `+vcd` (`make uvm PLUSARGS=+vcd`), into `build/sim/tb_top.vcd`.

### 3.3 Reset in the middle of a test (planned, step 5b)

**Who drives `rst_n`.** The interface owns `rst_n`. It stops being an `axi4lite_if` port and becomes an interface
variable; `tb_top` connects `dut.rst_n` to `intf.rst_n`. It is declared **`logic rst_n = 1'b1;`**, and the power-on
part of `apply_reset` drops it at `#1`. Why not `= 1'b0`: a declaration initialiser sets the starting value
**without an event**, so `always_ff @(posedge clk or negedge rst_n)` never sees a negedge at time 0. The DUT's flops
would stay X until the first posedge, and the assertions at that edge would sample `bvalid` / `rvalid` = X with
`rst_n = 0`. Today's `logic rst_n; initial rst_n = 1'b0;` is a time-0 race: whether the `always_ff` already waits
on its event control when the `initial` runs depends on process start order, which the LRM leaves undefined. In
iverilog the flop stays X at 4 ns; Questa evidently orders it favourably. `= 1'b1` then `#1` gives a real `1 → 0`
edge at 1 ns, before any clock edge, so `rst_n` is never X at an edge and the DUT is reset when the 5 ns edge
samples it (checked in iverilog 4-state: X / X / 0 for the three forms). §2.1 depends on this. The interface exposes
`task apply_reset(int unsigned cycles)` through a `reset_ctrl` modport. A test gets the `reset_ctrl` vif from
config_db.

**Power-on reset:** `rst_n` is 1 at time 0 and dropped at `#1`, before the first posedge, then released at a
`negedge clk` after N cycles. The `#1` drop is the one exception to the negedge rule below. It is safe because
nothing has been driven yet, so no clocking-block drive can be pending.

**Master signals at power-on (step 5a):** the interface gives the master-side signals declaration initialisers that
match `reset_signals()`: `awvalid = 1'b0`, `wvalid = 1'b0`, `arvalid = 1'b0`, `bready = 1'b1`, `rready = 1'b1`. Today
they have none (`axi4lite_if.sv:21-41`), and the driver drives its idle values only after reset release, through
`drv_cb` (`axi4lite_driver.sv:37-38`). So they are X at every power-on edge and at the first edge after release.
The DUT tolerates it (`if (awvalid && awready)` with X takes the else path), but the bound
`m_*valid_low_in_reset` and `m_no_x_*` would fire on the clean design. An initialiser is a legal starting value
for a variable the clocking block drives later; nothing waits on these signals at time 0, so no event is needed.
Addresses and data stay uninitialised: every assume on them is conditional on VALID.

**Timing constraint on mid-test resets:** `apply_reset` drops `rst_n` only at a `negedge clk`, which is at least
the output skew (2 ns) after the previous posedge. Reason: a `drv_cb` drive issued at posedge E is applied at
E + 2 ns. If `rst_n` fell inside (E, E + 2], the driver's direct clear below would run first, and the pending
`awvalid <= 1` would set VALID again during reset. The bound `m_*valid_low_in_reset` enforces this constraint in
simulation: a reset task that is later randomized freely makes the assume fire. `rst_n` is also released at a
`negedge clk`.

**Driver:**
- The interface has one bypass of the clocking block, used only here:
  ```systemverilog
  function automatic void clear_master_valids();  // async reset only
    awvalid = 1'b0; wvalid = 1'b0; arvalid = 1'b0;
  endfunction
  modport driver (clocking drv_cb, input clk, rst_n, import clear_master_valids);
  ```
  The modport does **not** get `output awvalid, ...`. That would let any driver code bypass the clocking block.
- Each item runs inside `fork begin <drive item> end begin @(negedge vif.rst_n); end join_any; disable fork;`.
  `disable fork` also kills the AW / W / B / R timeout watchdogs. A surviving watchdog would fire `DRV_TIMEOUT`
  later and turn a passing reset test into a fatal.
- On reset: `vif.clear_master_valids()` in the same time step as the `rst_n` fall, plus `drv_cb.*valid <= 0`, so the
  clockvars hold 0 at the next edge whatever was pending. Then `item_done()` for the aborted item (otherwise the
  sequence hangs in `finish_item`). Then `wait (vif.rst_n === 1'b1)` and `reset_signals()`.
- That last part is one task, `wait_reset_release()`, called both at the start of `run_phase` and after an abort.
- **Reset while idle:** if `rst_n` falls while the driver is blocked in `get_next_item` (between items), nothing is
  in flight to kill, and the VALIDs are already low. But the next item would arrive during reset and be driven at
  once: `m_*valid_low_in_reset` would fire, and the DUT would ignore a transfer the scoreboard expects. So after
  every `get_next_item`, before driving: `if (vif.rst_n !== 1'b1) wait_reset_release();`. In SPLIT mode (§3.4),
  both threads do this.

**Monitor:**
- On `negedge rst_n` it kills its reconstruction threads, publishes each in-flight transaction with `aborted = 1`
  and `abort_phase` ∈ {AW_W, B_WAIT, AR, R_WAIT}, and resets its raw handshake counters to 0. The DUT has dropped
  all of them, so the end-of-test outstanding check starts over.
- It publishes a reset event (cycle stamp) on a second analysis port `reset_ap`, even when nothing is in flight.

**Scoreboard:**
- On a reset event it calls one function, `clear_on_reset()`, which clears **all** model state together: the shadow
  model to 0 and, from step 5c, the per-register write history (§3.4). This is deterministic: the regfile has an
  asynchronous reset (spec §5.3), so a write in flight is lost whether or not it had been latched. A history entry
  from before the reset must never be visible to a read after it.
- Aborted transactions are not checked; it only counts them.

**Coverage:** `cp_reset_phase` = {idle, AW_W, B_WAIT, AR, R_WAIT}, sampled once per aborted transaction, and as
`idle` from `reset_ap` when nothing was in flight. In SPLIT mode (§3.4), one reset can abort a write and a read
together. The monitor then publishes both aborted transactions and one reset event. `cp_reset_phase` is sampled
once for each aborted transaction, so this case needs no extra bin.

### 3.4 Read/write concurrency (planned, step 5c)

**Why.** The driver handles one item at a time, so the read and write channels are never active together. The DUT's
read and write paths are independent, and "a read of the register being written this cycle" is a classic slave
bug (M19).

**Structure.** The existing sequences rely on `finish_item` blocking until the whole transfer is done:
`axi4lite_random_seq` writes a register, then reads it back. That must not change.
- A config_db setting `drv_mode` ∈ {COMBINED, SPLIT} (default COMBINED) is read by **both the agent and the
  driver** in build_phase. A test uses one mode, never both.
- The **same** driver class gets a second pull port, `rd_item_port`, next to the inherited `seq_item_port`.
  `drive_write` / `drive_read` stay in one class, so the `axi4lite_unaligned_driver` override keeps working.
- Which sequencers are built and how they are wired, per mode (agent `build_phase` / `connect_phase`):

  | Mode | Sequencers built | `seq_item_port` connects to | `rd_item_port` connects to | Driver threads |
  |---|---|---|---|---|
  | COMBINED | `sqr` | `sqr` | unconnected, never used | one, in order (today's loop) |
  | SPLIT | `wr_sqr`, `rd_sqr` | `wr_sqr` | `rd_sqr` | a write thread on `seq_item_port`, a read thread on `rd_item_port` |

  In COMBINED mode the topology (and `print_topology`) is exactly today's, so the existing tests and their
  sign-off numbers do not change. In SPLIT mode `sqr` is not built at all. If some code still starts a sequence on
  it, `axi4lite_base_test::run_phase` (`axi4lite_tests.sv:49-50`, `seq.start(env.agent.sqr)`) fails at once on a
  null handle, instead of hanging until the 1 ms global timeout. In SPLIT mode the write thread fatals on a read
  item and the read thread on a write item.
- **Reset with two threads in flight:** each thread keeps its current item in a member (`cur_wr`, `cur_rd`). The
  supervisor runs both threads inside the reset fork of §3.3. On reset it does `disable fork`, then calls
  `item_done()` on each port that has a current item, then calls `wait_reset_release()` once.
- The concurrency test sets `drv_mode = SPLIT`, overrides `run_phase`, and runs a virtual sequence over `wr_sqr`
  and `rd_sqr`.
- **Stimulus knob for the boundary:** `axi4lite_txn` gets `rand int unsigned start_delay` (cycles to wait before
  driving), honoured in SPLIT mode only (constrained to 0 in COMBINED, so existing traffic does not change).
  With today's driver, a write's `m` is about 2 samples after its last AW/W handshake: it fires on the next edge,
  and BVALID is seen one sample later. Where the read's `k` falls depends on when the read thread starts. So the
  virtual sequence gives the write and the read the same register and a small `start_delay` range (0..4) on
  the read, and `m == k` and `m == k + 1` are hit by construction, not by luck. The formal covers (§2.6) show
  the boundary is reachable independently of this stimulus.

**Ordering rule (DUT rule, spec §5.5).** With two threads, a read can complete before an earlier write's B
handshake, so the order of arrival on the analysis port no longer tells the scoreboard which value a read must
see. The rule, in sample indices (§1):

- `k` = the sample at which `arvalid && arready` is seen;
- `m` = the first sample at which this write's `bvalid` is seen high. The DUT writes the regfile on the same edge
  that raises BVALID (spec §5.1), so the write fired on the edge just before sample `m`.
- The read returns the new value **iff `m <= k`**. When `m == k`, the regfile was updated on the edge before the AR
  handshake edge, so the read sees it. When `m == k + 1`, the regfile was updated on the AR edge itself, so the read
  does not see it yet (`$past` in `a_read_data_matches_regfile`).

BVALID is low for at least one sample between two writes: a fire needs `!bvalid`, and the edge that clears
`bvalid` still sees it as 1. So every BVALID rise identifies exactly one write.

**Monitor and scoreboard:**
- The monitor stamps a write with `m` and a read with `k`. It publishes a write a second time, at sample `m`, on
  `commit_ap` (addr, wdata, wstrb, resp, stamp: all of them are known at `m`). Since `m <= k <` the read's R
  handshake, every write with `m <= k` reaches the scoreboard before the read.
- **One write path, in all modes:** the scoreboard applies writes, and checks write responses, **only** from
  `commit_ap`, in COMBINED and SPLIT alike. Completed transactions on `ap` go to coverage and to the read checks;
  the scoreboard ignores completed writes on `ap`. This changes the scoreboard for the existing tests too, so the
  existing random / unaligned sweeps (20 / 20 seeds, 100% merged, both widths) are the regression for that change
  (§6, step 5c).
- The scoreboard keeps, per register, the **full** history of (`m`, value) for the test: one entry appended at each
  write commit, cleared only by `clear_on_reset()` (§3.3). A read with stamp `k` is checked against the newest entry
  with `m <= k`, or the reset value 0 if there is none. **No pruning.** Reason: pruning only bounds memory, and the
  bound is tiny here (`NUM_TXNS = 100` per test, and the history is cleared on reset, so a few hundred entries at
  most). Pruning would need an AR event on `commit_ap` and a queue of outstanding read stamps, and that queue can
  get stuck on a read aborted by reset. The full history needs neither, and makes no assumption about how many
  reads are outstanding, so M15 (two unanswered ARs) cannot mislead it. `commit_ap` carries write commits only. If
  a long soak test is ever added, add pruning then: keep a queue of outstanding read stamps (pushed by an AR event
  on `commit_ap`, cleared on reset), and prune entries older than the newest entry with `m <= min(outstanding k)`.
- The rule lives in one function, `visible(write_stamp, read_stamp)`. A DUT with a different commit point changes
  that one line. There is no "loose mode" (accepting either the old or the new value): it would let M19 pass by
  construction.

**Coverage:** `cp_rw_overlap` on the same register, with bins `m == k` and `m == k + 1`, plus "other register" and
"no overlap". Both boundary bins are required, with a matching formal cover each (§2.6). These bins are gated
**per test**, by the concurrency test only, not merged into the random test's goal. `start_delay` above is what
makes them reachable on purpose.

**Not closed by this:** the four code-coverage condition terms in §3.8 need a *second request on the same channel*
while the first is pending (two writes, or two reads). One write thread plus one read thread does not produce
that. They stay formal-only until a pipelined driver (§5).

### 3.5 Tests

| Test | Status | What it checks |
|---|---|---|
| `axi4lite_smoke_test` | done | `NUM_SMOKE_TXNS` = 4 full-strobe writes, then read-back. Directed; not held to a coverage goal |
| `axi4lite_random_test` | done | `NUM_TXNS` = 100 random writes, each read back, plus a read of another register 30% of the time; data, strobe and address biased toward the coverage bins (incl. the last register and the first out-of-range word) |
| `axi4lite_unaligned_test` | done | the random traffic with `axi4lite_unaligned_driver`: unaligned byte addresses, legal stimulus the sequences cannot produce |
| `axi4lite_reset_test` | planned (5b) | random traffic with `apply_reset` at random negedges; every `cp_reset_phase` bin; the shadow cleared after each reset |
| `axi4lite_oor_sweep_test` | planned (5c) | write every out-of-range word with a unique pattern, then read every register: the frame condition in simulation, and the minimal reproducer for M01 / M05 |
| `axi4lite_rw_concurrency_test` | planned (5c) | SPLIT mode (`drv_mode` via config_db); overrides `run_phase` (no `sqr` in SPLIT mode) and runs a virtual sequence over `wr_sqr` / `rd_sqr`, same register, read `start_delay` 0..4, targeting the `m == k` / `m == k + 1` boundary |

**Further directed tests are added only when a mutant survives simulation but is killed by formal** (§4). Strobes,
backpressure and AW/W order are already shown exercised by random stimulus and 100% merged coverage, so a
directed copy of them adds maintenance, not evidence.

### 3.6 Functional coverage (done)

`cg_axi4lite` in `tb/axi4lite_coverage_collector.sv`, sampled on every completed transaction from the monitor.
Bin counts below are derived from the source (32-bit / 64-bit); confirm them against the `vcover` report at the
first `regress.py` run.

| Item | Bins | Why |
|---|---|---|
| `cp_op` | 2 | write, read |
| `cp_addr` | 2 | in range / out of range, by byte address (unaligned addresses in the last word count as in range) |
| `cp_word` | 18 | each of the 16 registers, the first word past the range (off-by-one), the rest |
| `cp_wdata` | 4 | all-zeros, all-ones, `0xAA..`, `0x55..`: every data bit driven both ways |
| `cp_wstrb` | 8 / 12 | none, full, each single lane (4 / 8), low half, high half |
| `cp_aw_w_order` | 3 | same cycle, AW first, W first (separate latch paths) |
| `cp_resp_wait` | 2 | response accepted at once / waited for READY |
| `cx_op_resp_wait` | 4 | backpressure on B and on R |
| `cp_resp` | 2 | OKAY, SLVERR; EXOKAY and DECERR are `illegal_bins` (checks, not goals) |
| `cx_op_word` | 36 | every register written and read; out-of-range writes as well as reads |
| `cx_wstrb_region` | 8 / 12 | every strobe shape on an in-range register (out of range ignored: it never reaches the merge) |
| `cx_addr_resp` | 2 | in range × OKAY, out of range × SLVERR; the other two are `illegal_bins` |

Total: 91 / 99 bins. Sign-off is on the **merged** sweep. One seed of 100 transactions is not expected to close
the model alone.

### 3.7 Regression

**Today (done):** `make uvm-sweep TEST=<t> N=20` builds once, runs seeds 1..N with `-sv_seed`, merges the passing
seeds' UCDBs and gates merged covergroup coverage at `COV_GOAL` (100 for random and unaligned, 0 for smoke).
It prints DUT code coverage but does not gate it.

**Planned (step 5a), `scripts/regress.py`:**
- One build. Every directed test once, then N seeds of each random test.
- A run passes only if the UVM report summary is present (a missing summary means a crash or hang),
  `UVM_ERROR = UVM_FATAL = 0`, and there is no `** Error` / `** Fatal` (bound assertions, `$fatal`). These rules
  live in **one** shared module, `scripts/questa_log.py`, written in step 4 for mutation scoring and reused here.
  Two copies of "what counts as a failure" would drift, as the file lists did.
- Merge passing runs only. Keep the per-test gates (`COV_GOAL` per test, the concurrency bins per test), and also
  print one figure merged across all tests.
- Write each run's result and its full reproduce command line to `build/sim/summary.log`.
- **Seed check:** the monitor keeps a running FNV-1a hash over every transaction it publishes (all fields, including
  `aw_w_order` and `resp_stall`, so the driver's randomness counts too), and prints `FINGERPRINT <hex>` in
  `report_phase`. For each test in `RANDOM_TESTS`, N seeds must give N distinct fingerprints. Directed tests
  (smoke, oor-sweep) are exempt by design: do **not** "fix" a constant smoke fingerprint by adding randomness.
  `$get_initial_random_seed()` is printed for information only; it is a Questa extension, not IEEE 1800.
  This check would have caught the `+ntb_random_seed` bug, since every seed then produced identical traffic.

### 3.8 Code coverage

The RTL alone is compiled with `+cover=bcesf` into the same UCDBs. Merged today (README): statements 35 / 35,
branches 21 / 21, conditions 11 / 15. The four missing condition terms need a second request on the same channel
while the slave is still busy with the first, which the one-at-a-time driver cannot produce. Each is reached by a
formal cover instead:

| RTL condition term never hit in UVM | Formal cover |
|---|---|
| `awvalid && awready` with AWREADY low | `cp_aw_ready_after_valid` |
| `wvalid && wready` with WREADY low | `cp_w_ready_after_valid` |
| `arvalid && arready` with ARREADY low | `cp_ar_ready_after_valid` |
| write fire held off by a pending BVALID | `cp_write_arrives_while_b_pending` |

These are the only exclusions. Any new hole needs a reason before it is waived: missing stimulus, a scenario
missing from this plan, or code proven unreachable.

---

## 4. Mutation testing (planned, step 4)

One patch per bug in `mutations/Mnn_*.patch`, first line = description. `scripts/run_mutations.py` /
`make mutate [ONLY=M02,M05]`:

- Apply each patch with `patch -p1` to a throwaway copy in `build/mutation/<id>/`, never to the repo, and check
  that a file really changed.
- **Behaviour-difference check first:** an output signature over VALID-qualified outputs only (`bresp` only while
  `bvalid`, `rdata` / `rresp` only while `rvalid`, plus the VALIDs and READYs). It uses the `formal_tb` random driver
  under vsim, which reaches concurrency and backpressure, not UVM. A signature equal to the clean one is
  reported as "no difference seen", then confirmed with formal and by reading the patch.
- **Simulation** is scored black-box (`UVM_CHECKERS=no`). **Formal** is scored with qverify, using the §2.8
  self-check on the clean design as the reference. The results go in separate columns. "Killed by formal,
  survived simulation" is the column that decides which directed test or stimulus change to add (§3.5).
- Default width 32. Width-sensitive mutants (M18) also run at 64.
- Each cell of `build/mutation/summary.md` names the first failing check. The table goes into the README.
- "Did this run pass" uses `scripts/questa_log.py`, the one shared log classifier (summary present,
  `UVM_ERROR = UVM_FATAL = 0`, no `** Error` / `** Fatal`), which `regress.py` reuses in step 5a (§3.7).
- The behaviour-difference check and `formal-sweep` both use `formal_tb` with the rare mid-run reset of §2.9, so
  M09b shows a difference there. The formal column stays authoritative for M09a / M09b / M20. M20 must still show no
  difference with the reset added; that is what it is for.

**Expected at baseline** (step 4: the current testbench, no reset test, no concurrency, checkers not bound) is
recorded *before* the run. A survivor not marked here is a finding. A marked survivor that gets killed is a
surprise worth a look. K = killed, S = survives, E = equivalent (no observable difference).

| # | Mutation | Expected to be caught by | Baseline sim / formal |
|---|---|---|---|
| M01 | Out-of-range write aliased onto `regfile[idx[3:0]]`, still SLVERR | `a_e2e_read_data`, frame condition; scoreboard (read of another register), oor-sweep test | K / K |
| M02 | One WSTRB lane ignored (always written) | `a_write_disabled_byte_preserved`; scoreboard | K / K |
| M03 | WSTRB lanes reversed | whitebox strobe checks, e2e; scoreboard | K / K |
| M04 | Out-of-range access answers OKAY | `a_write_slverr_out_of_range` / `a_read_slverr_out_of_range`; scoreboard, `cx_addr_resp` illegal bins | K / K |
| M05 | Range check off by one (last register out of range, or first out-of-range word accepted) | e2e, response checks; `cp_word` (last register, `first_oor`) stimulus | K / K |
| M06 | BVALID dropped before BREADY | `a_bvalid_stable`; driver `DRV_TIMEOUT` (with a B stall it waits for BVALID again after raising BREADY) | K / K |
| M07 | RDATA / RRESP (or BRESP) changes while VALID && !READY | `a_rvalid_stable` / `a_bvalid_stable`; scoreboard if the value at the handshake is wrong | K / K |
| M08 | W before AW loses the data (or AW before W loses the address) | e2e; `cp_aw_w_order` stimulus | K / K |
| M09a | Reset branch does not clear the regfile at all | reset asserts, e2e; monitor X check | **S** / K, see note |
| M09b | Regfile cleared at the first reset only (a `reset_seen` flop in the mutant skips the clear afterwards) | e2e (qverify's free `rst_n` resets mid-run); `axi4lite_reset_test` | **S** / K, see note |
| M10 | Address decode uses the low address bits (unaligned alias) | e2e; unaligned test | K / K |
| M11 | One data bit stuck at 0 in one register | e2e (symbolic `sym_idx`); `cp_wdata` patterns | K / K |
| M12 | Response EXOKAY or DECERR instead of OKAY / SLVERR | `a_bresp_legal_value` / `a_rresp_legal_value`; scoreboard, `cp_resp` illegal bins | K / K |
| M13 | AWREADY / WREADY not released after the B handshake | `a_awready_when_idle` / `a_wready_when_idle`; `DRV_TIMEOUT` | K / K |
| M14 | `!bvalid` dropped from the write-fire condition | `a_bvalid_stable`, fifo pairing. Needs a 2nd write while B is pending | **S** / K (until a pipelined driver) |
| M15 | `arready = 1'b1`: a new AR overwrites a pending R | `a_rvalid_stable`, `a_e2e_read_data`. Needs a 2nd AR while R is pending | **S** / K (same) |
| M16 | Write fires on `aw_hs_done` alone (stale `wdata_latched`) | `a_bvalid_requires_aw_and_w`, e2e; UVM via the W-late skew | K / K |
| M17 | BVALID raised only when BREADY is high | `a_bvalid_not_wait_bready`; UVM deadlock → `DRV_TIMEOUT` (with a B stall, the driver waits for BVALID before raising BREADY, `axi4lite_driver.sv:138-158`) | K / K |
| M18 | `ADDR_LSB` hardcoded to 2 | e2e, `a_read_data_matches_regfile`. **Only visible at `DATA_WIDTH = 64`** | 32-bit: E / E; 64-bit: K / K |
| M19 | A read bypasses a write firing on the same edge (returns the new value) | `a_read_data_matches_regfile`; UVM only with the concurrency test (§3.4) | **S** / K (until 5c) |
| M20 | Reset does not clear `rdata` / `bresp` | nothing: not observable at the ports while VALID is low. The test case for the behaviour-difference check | E / E |

**Note on M09a / M09b.** M09 is split so that each row has one committed expectation, and so that 5b is measured
by a row of its own.
- **M09a**, baseline **S** in simulation. Without the reset, the regfile starts as X in 4-state vsim, and the random
  sequence's 30% "read another register" can hit a register never written in that seed. But `axi4lite_txn.rdata`
  and `.resp` are 2-state `bit` (`axi4lite_txn.sv:20-21`), so the monitor's `tr.rdata = vif.mon_cb.rdata`
  (`axi4lite_monitor.sv:209`) silently turns X into 0. That matches the scoreboard's expected 0, so the
  `!==` compare (`axi4lite_scoreboard.sv:89`) passes. After the monitor X check (§3.2, step 5a) it becomes **K** in
  simulation, killed by `MON_X` at power-on. Formal: **K**. An unreset regfile gets free initial values, and
  `a_e2e_read_data` (reference reset to 0) catches it.
- **M09b**, baseline **S / K**. The first reset clears the regfile, so power-on hides nothing, and only a reset after
  a write shows the bug. The baseline UVM bench has no mid-test reset. qverify's free `rst_n` gives formal one, and
  the §2.9 `formal_tb` mid-run reset gives the behaviour-difference check one. After 5b: **K / K**, killed by
  `axi4lite_reset_test` on a register that held a written value. This is the row that measures 5b.
- The behaviour-difference signature is computed over 4-state values (an X bit hashes differently from 0), so M09a
  is not reported "no difference" for the same X-to-0 reason.

---

## 5. Stretch goals

1. **UVM RAL.** Note: the UVM library is compiled with `+define+UVM_NO_DPI` (`Makefile:150`). RAL backdoor
   access needs the DPI HDL functions, so it means dropping `UVM_NO_DPI` or using Questa's precompiled UVM.
2. **Pipelined driver / monitor**, more than one request in flight per channel. This would close the four condition
   terms of §3.8 in simulation and turn M14 / M15 into UVM catches.
3. **AWPROT / ARPROT** (spec §2 marks them not implemented).
4. **CI** for both widths: lint, check, regression, formal.
5. **"Covered with Warning"**: confirm each flagged cover's control points in the qverify GUI, including the ones
   that use neither `$rose` nor `$stable` (`cp_e2e_partial_strobe_merge`, `cp_write_arrives_while_b_pending`).

---

## 6. Order of work and exit criteria

Each step (and each of 5a / 5b / 5c) is one commit, with its own Questa checklist like step 2, so a failure on
Questa can be traced to one change.

| Step | Work | Done when |
|---|---|---|
| 1 | This plan; spec §1 / §5.5 | Plan and spec consistent with the code (counts, line references, rules) |
| 2 | Structure: root `Makefile`, `rtl.f` / `tb.f` / `formal.f`, outputs in `build/`, `formal/run_formal.tcl`, VCD behind `+vcd`, `QUESTA_UVM_HOME` from the `vsim` on PATH (not `UVM_HOME`), `.gitignore`, README layout (implemented; Questa checklist pending) | Questa checklist passes unchanged, after `git clean -fdx sim/` removes the old flow's outputs: `simple`; `uvm` smoke with a UVM-1.2 banner, and with `PLUSARGS=+vcd`; `uvm-sweep TEST=axi4lite_random_test N=3` at 32 and 64 bits; `formal-sweep N=3`; `formal-coverage N=3`; `formal-verify-all` 57/57, 65/65 proven, 43/43 covered; `formal-verify-noassume` all proven at 32 and 64 bits; the four `build/formal/formal_report*.txt` copied outside the repo (the reference for the step 3 self-check); outputs only under `build/` (`git status --short --ignored`); nothing left after `make clean` |
| 3 | `make lint` (Verilator `-Wall` on the RTL with the two `WIDTHEXPAND` fixed and the two `UNUSEDSIGNAL` waived by comment; slang over RTL + `formal/`, both defines, both widths, `--timescale 1ns/1ps`), `make check` (lint + Verilator smoke on `*** TEST PASSED ***`), formal self-check | `make check` passes locally; self-check passes on all four configurations |
| 4 | `scripts/questa_log.py` (shared run classifier); `formal_tb`'s simulation reset in the `#1` drop / negedge release form, plus a rare mid-run reset; mutations M01–M20 (21 patches: M09a / M09b) on the current testbench | Baseline table: every mutant scored per flow and compared with the "expected at baseline" column (§4); clean design passes every flow first; `formal-sweep` still passes with the mid-run reset |
| 5a | `scripts/regress.py` (reusing `questa_log.py`), monitor `FINGERPRINT`, monitor X check (`MON_X`), master-signal initialisers in the interface, `tb_top` power-on reset as `rst_n = 1'b1` / `#1` drop / release at a negedge after 3 posedges, formal checkers bound into `tb_top.dut` (instance bind, `NO_UVM_CHECKERS` switch). No new tests | Existing tests pass on 20 seeds in both widths with the bound checkers silent, **including no assume firing at power-on**; no `MON_X`; coverage numbers unchanged; distinct fingerprints for the random tests |
| 5b | Reset: `rst_n` moved into the interface (`= 1'b1`, power-on drop at `#1`), `apply_reset` / `reset_ctrl`, `clear_master_valids`, driver kill path and `wait_reset_release`, monitor abort + `reset_ap`, scoreboard clear, `cp_reset_phase`, `axi4lite_reset_test` | Reset test and existing tests pass on 20 seeds in both widths; every `cp_reset_phase` bin hit, `idle` including resets that land while the driver is blocked in `get_next_item`; no `m_*valid_low_in_reset` firing; M09b killed by `axi4lite_reset_test` |
| 5c | Concurrency: `drv_mode`, `wr_sqr` / `rd_sqr` / `rd_item_port`, `start_delay`, monitor `cyc` / `stamp` / `commit_ap` (write commits), scoreboard `visible()` + full per-register history (the only write path, all modes; cleared by `clear_on_reset()`), `cp_rw_overlap`, formal covers `cp_rw_fire_before_ar` / `cp_rw_fire_on_ar_edge` (`expected_counts.txt` 43 → 45), `axi4lite_rw_concurrency_test`, `axi4lite_oor_sweep_test`; then the directed tests the step 4 survivors call for | Concurrency test closes both boundary bins; **the existing random / unaligned sweeps still give 20 / 20 seeds and 100% merged coverage in both widths** (the regression for the new scoreboard write path); formal self-check 45 covers |
| 6 | Re-run mutations, README results | Table updated; every survivor explained (expected survivor, or equivalent); M09a, M09b and M19 now killed in simulation |
