# AXI4-Lite UVM + Formal Verification Environment (QuestaSim / Questa Formal)

---

> **QuestaSim flow.** The `rtl/`/`tb/`/`formal/` sources are built and run with
> Siemens EDA's QuestaSim (`vlib`/`vlog`/`vopt`/`vsim`) and Questa Formal
> Verification (`qverify`). The same environment also has a Verilator-based
> flow, kept in a separate tree; only `sim/Makefile`,
> `formal/formal_questa.do`, and this README differ between the two.

## Introduction

A verification environment for a simplified AXI4-Lite slave, combining a constrained-random UVM testbench with a SystemVerilog Assertions (SVA) formal environment. AXI4-Lite is AMBA's lightweight memory-mapped register interface defined in the *AMBA AXI and ACE Protocol Specification* (ARM IHI 0022E), available from ARM. The DUT's concrete behavior is documented in [`spec/axi4lite_slave_spec.md`](spec/axi4lite_slave_spec.md).


---

## Directory structure

```
axi4lite_uvm/
├── rtl/
│   └── axi4lite_slave.sv           -- DUT: simple AXI4-Lite slave, NUM_REGS x 32-bit reg file
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
│   ├── axi4lite_assumptions.sv     -- `assume property`: constrains the environment to legal masters
│   ├── axi4lite_assertions.sv      -- `assert property`: the DUT's own obligations (incl. whitebox WSTRB checks)
│   ├── axi4lite_covers.sv          -- `cover property`: reachability for spec rules with no assert/assume
│   ├── axi4lite_formal_driver.sv   -- legal-master constrained-random driver for simulation-based checking
│   ├── formal_tb.sv                -- top-level formal environment, wires the above + the DUT together
│   └── formal_questa.do            -- qverify batch script for the real formal-proof flow (see below)
├── spec/
│   └── axi4lite_slave_spec.md      -- this DUT's concrete behavior, traced back to ARM IHI 0022E rules
├── sim/
│   └── Makefile                    -- QuestaSim + Questa Formal run targets for both tb/ (UVM) and formal/
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
- `formal-verify`: `qverify`, plus the same license setup. Its driving
  script, [`formal/formal_questa.do`](formal/formal_questa.do), is a
  template -- see its header comment before trusting the results; it
  hasn't been run against a real Questa install, since this repo was
  developed without one available.

```bash
cd sim
make uvm TEST=axi4lite_smoke_test              # directed write/read-back smoke test
make uvm TEST=axi4lite_random_test SEED=42     # constrained-random regression, reproducible via seed
make uvm-sweep TEST=axi4lite_random_test N=50  # build once, run seeds 1..N, report which (if any) failed

make formal SEED=7                             # assume/assert/cover env, bounded randomly-driven sim
make formal-sweep N=50                         # same idea: build once, sweep seeds, report failures

make formal-verify                             # real Questa Formal proof (flow #1), not simulation

make simple                                    # plain (non-UVM) direct-drive sanity check via tb_simple.sv
make clean
```



## Next steps / extension points

1. **UVM RAL**
2. **Outstanding-transaction handling**
3. **Error injection via factory override**
4. **Implemente AWPROT/ARPROT**
5. **Cover-point closure reporting for `formal/`**
6. ~~**Real formal proof for `formal/`**~~ -- `make formal-verify` (this
   branch), pending validation against a real Questa install
7. **Wire both sweeps into CI**
8. ~~**`formal-coverage` equivalent under Questa**~~ -- `make formal-coverage`
   (this branch), via `vcover merge`/`report`; validated against a real
   run, all 27 `cp_*` points covered across a 20-seed sweep
9. ~~**Confirm `tb/` compiles unmodified against Questa's bundled UVM 1.2**~~
   -- it didn't, unmodified: two real bugs found and fixed (a file
   compile-order issue in `sim/Makefile`, and an argument-name mismatch in
   `axi4lite_coverage_collector.sv`'s `write()` override -- see git log).
   `tb/` now runs clean on both UVM 1.2 (this branch) and dev's IEEE
   1800.2-2020 kit
