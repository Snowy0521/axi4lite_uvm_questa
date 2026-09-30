# AXI4-Lite UVM + Formal Verification Environment (QuestaSim / Questa Formal)

---
## Introduction

A verification environment for a simplified AXI4-Lite slave, combining a constrained-random UVM testbench with a SystemVerilog Assertions (SVA) formal environment. AXI4-Lite is AMBA's lightweight memory-mapped register interface defined in the *AMBA AXI and ACE Protocol Specification* (ARM IHI 0022E), available from ARM. The DUT's concrete behavior is documented in [`spec/axi4lite_slave_spec.md`](spec/axi4lite_slave_spec.md).


---

## Directory structure

```
axi4lite_uvm/
├── rtl/
│   ├── axi4lite_types_pkg.sv       -- shared AXI protocol types (axi_resp_e), imported everywhere
│   └── axi4lite_slave.sv           -- DUT: simple AXI4-Lite slave, NUM_REGS x 32/64-bit reg file
├── tb/
│   ├── axi4lite_if.sv              -- interface with driver/monitor clocking blocks + modports
│   ├── axi4lite_txn.sv             -- transaction (uvm_sequence_item)
│   ├── axi4lite_sequencer.sv       -- uvm_sequencer typedef
│   ├── axi4lite_sequences.sv       -- directed write/read seqs + randomized traffic seq
│   ├── axi4lite_driver.sv          -- drives transactions onto the bus (AW/W concurrent, timeout-protected)
│   ├── axi4lite_monitor.sv         -- passively reconstructs transactions, broadcasts via analysis port
│   ├── axi4lite_agent.sv           -- driver + sequencer + monitor container (active/passive capable)
│   ├── axi4lite_scoreboard.sv      -- shadow-register-model checker
│   ├── axi4lite_coverage_collector.sv -- functional coverage (op x address-region, wstrb, resp)
│   ├── axi4lite_env.sv             -- top-level environment (agent + scoreboard + coverage)
│   ├── axi4lite_tests.sv           -- base_test, smoke_test, random_test
│   ├── axi4lite_pkg.sv             -- package bundling all `include`d class files
│   ├── tb_top.sv                   -- clock/reset gen, DUT+interface instantiation, run_test()
│   └── tb_simple.sv                -- plain (non-UVM) direct-drive sanity check
├── formal/
│   ├── axi4lite_assumptions.sv     -- `assume property`: constrains the environment to legal masters (no proof depends on them)
│   ├── axi4lite_assertions.sv      -- `assert property`: the DUT's own obligations (incl. whitebox WSTRB + read-data checks)
│   ├── axi4lite_covers.sv          -- `cover property`: handshake/response/strobe, multi-transaction and mid-transaction-reset reachability
│   ├── axi4lite_formal_driver.sv   -- legal-master constrained-random driver for simulation-based checking
│   └── formal_tb.sv                -- top-level formal environment, wires the above + the DUT together
├── spec/
│   └── axi4lite_slave_spec.md      -- this DUT's concrete behavior, traced back to ARM IHI 0022E rules
├── sim/
│   ├── Makefile                    -- QuestaSim + Questa Formal run targets for both tb/ (UVM) and formal/
│   ├── formal_questa.do            -- qverify batch script for the real formal-proof flow (see below)
│   ├── wave.do                     -- interactive-only GUI script: curated waves for tb_simple, then run
│   └── wave_uvm.do                 -- interactive-only GUI script: curated waves for the UVM env (tb_top / intf / dut), then run
└── README.md
```

## Tool support: simulation vs. formal proof

Two different things live in `formal/`, and it's easy to conflate them:

- **Simulation** (`tb/`'s UVM testbench, and `formal/`'s bounded/randomly-driven
  smoke check -- "flow #2" in [`formal_tb.sv`](formal/formal_tb.sv)'s header
  comment): runs on **QuestaSim** (`vlib`/`vlog`/`vopt`/`vsim`). It doesn't
  exhaustively prove anything -- it just simulates, with `formal/`'s
  `assume`/`assert`/`cover` properties checked cycle-by-cycle against
  whatever the randomized driver happens to generate.
- **Formal proof** ("flow #1"): exhaustive, non-simulation property checking
  over every reachable state, bounded only by proof depth. **Questa Formal
  Verification**, driven through the `qverify` command-line front-end
  (sometimes referred to as "Questa Verify"), is a separate Siemens EDA
  product from QuestaSim for this. `make formal-verify` below is what
  exercises it.

## How to run

All targets live in [`sim/Makefile`](sim/Makefile). Requires the relevant
tool on `PATH`:
- `uvm`/`uvm-sweep`/`simple` (any UVM or plain-simulation target): `$UVM_HOME`
  pointed at a UVM class library -- defaults to QuestaSim 2024.3's own
  bundled UVM 1.2 kit. **Note:** this is UVM 1.2 (Accellera), not the IEEE
  1800.2-2020 kit `tb/` was originally written against -- close but
  not identical APIs; if `uvm-build` fails to compile, that mismatch is the
  likely cause (the `formal`-family targets need no UVM at all).
- All simulation targets: `vlib`/`vlog`/`vopt`/`vsim` (source Questa's setup
  script, e.g. `source <questasim_install>/settings.sh`, or add its `bin/`
  to `PATH`) and a valid license (`LM_LICENSE_FILE`).
- `formal-verify`: `qverify` (Questa Formal 2024.3), plus the same license
  setup. Driven by [`sim/formal_questa.do`](sim/formal_questa.do), compiled
  into its own `sim/formal_work` library; the summary lands in
  `sim/formal_report.txt` (`formal_report_64.txt` for the 64-bit run).

`DATA_WIDTH` (32 by default, or 64) works on every target. It is compiled
in as `+define+AXI4LITE_DATA_WIDTH`, and `tb/axi4lite_pkg.sv`,
`tb/tb_simple.sv` and `formal/formal_tb.sv` each pass it to the DUT, so
switching width never means editing a source file.

```bash
cd sim
make simple                                    # plain (non-UVM) direct-drive sanity check via tb_simple.sv

make uvm TEST=axi4lite_smoke_test              # directed write/read-back smoke test
make uvm TEST=axi4lite_random_test SEED=42     # constrained-random regression, reproducible via seed
make uvm-sweep TEST=axi4lite_random_test N=20  # build once, run seeds 1..N, report which (if any) failed
make uvm TEST=axi4lite_random_test DATA_WIDTH=64  # any target: DATA_WIDTH=32 (default) or 64

make formal SEED=7                             # assume/assert/cover env, bounded randomly-driven sim
make formal-sweep N=50                         # same idea: build once, sweep seeds, report failures

make formal-verify                             # real Questa Formal proof (flow #1), not simulation, 32-bit
make formal-verify DATA_WIDTH=64               # same, 64-bit configuration
make formal-verify-all                         # both widths back to back
make formal-verify-noassume                    # proof without assumptions: shows which proofs depend on them

make clean
```

## Formal results

Questa Formal 2024.3, `make formal-verify-all`:

| Configuration | Asserts            | Covers            |
|---------------|--------------------|-------------------|
| 32-bit        | 50 / 50 proven     | 39 / 39 covered   |
| 64-bit        | 58 / 58 proven     | 39 / 39 covered   |

- Full proofs (not bounded), none vacuous.
- `rst_n` is left free after init (`formal verify -auto_constraint_off`),
  so reset asserted mid-transaction is part of every proof, and covers
  show the slave recovering from it.
- Read data is checked end to end: `a_read_data_matches_regfile` proves
  RDATA equals the addressed register, and `cp_write_then_read_back`
  shows a written value actually coming back.
- Frame condition: `g_regfile_frame[i]` proves register `i` changes only
  on an in-range write to index `i`, so an out-of-range write, or a write
  that also clobbers another register, is caught. Checked by mutation:
  aliasing out-of-range writes onto `regfile[word_idx[3:0]]` (while still
  returning SLVERR) fires it.
- `make formal-verify-noassume` proves every assert with the assumptions
  compiled out: the DUT is correct against any master, legal or not.
- Known, benign: roughly 27-31 covers are reported "Covered with
  Warning" (the count and the set vary from run to run). Cause: at the
  first tick after init, `$rose()`/`$stable()` have no previous sample
  (the LRM gives it the type's default, X), and qverify models that
  history value as a free "modeling" control point. A witness that
  assigns one gets flagged. Confirmed in the GUI's Control Point Values
  window: `u_covers.$rose(arvalid)` for `cp_ar_ready_preasserted`, and
  `u_assumptions.$stable(wdata)`/`$stable(wstrb)` for
  `cp_w_before_aw_master` (assumptions sit in every cover's cone of
  influence). Impact:
  - Asserts: none. A free history bit only adds behaviors, so it can
    cause a spurious failure, never a false proof.
  - Covers: a witness could in principle rely on a history value that
    can't occur. The flagged covers all have ordinary legal traces.
    Rewriting `$rose(x) && ...` as `!x ##1 (x && ...)` was shown to clear
    the flag on the `cp_*_ready_preasserted` covers; replacing the
    assumptions' `$stable` with reset registers should clear the rest
    but was not run to completion. The standard SVA forms are kept for
    readability.



## Next steps / extension points

1. **UVM RAL**
2. **Outstanding-transaction handling**
3. **Error injection via factory override**
4. **Implemente AWPROT/ARPROT**
5. **Cover-point closure reporting for `formal/`**
6. **Wire both sweeps and `formal-verify-all` into CI, for both `DATA_WIDTH`s**
7. **Explain/resolve "Covered with Warning" in the qverify GUI**

