# Mutation baseline (step 4)

First full `make mutate` on Questa 2024.3 (QuestaSim + Questa Formal), 2026-11-09, branch `step4-mutations` at
`7140dcd`. Simulation: black-box UVM, `axi4lite_smoke_test`, then 5 seeds each of `axi4lite_random_test` and
`axi4lite_unaligned_test`, stopping at the first failure. Formal: `make formal-verify`, scored by
`scripts/check_formal_report.py`. The clean design passed all three checks at 32 and 64 bits first.

Condensed from `build/mutation/summary.md` (not committed: it lists every fired target in full). Simulation names the
first failing run and its first problem; formal gives the number of fired targets, grouped by property.

**22 runs: 0 differ from the expected baseline, 0 errors.**

**Re-run after step 5a (2026-11-10, `step5a-regress`):** 22 runs, 0 differ, 0 errors. The only change is M09a,
now K / K: `axi4lite_random_test seed 1: [MON_X] X/Z on DUT output(s): rdata` (its patch baseline was moved to
K K in the same step). Every other row is as below.

| ID | Width | Mutation | Behaviour | Simulation | Formal | Sim / formal | Result |
|---|---|---|---|---|---|---|---|
| M01 | 32 | Out-of-range write aliased onto regfile[idx[3:0]], still SLVERR | changed | random seed 1: `[SB]` | 17 fired: `a_e2e_read_data`, `a_regfile_changes_only_on_own_write` ×16 | K / K | as expected |
| M02 | 32 | WSTRB lane 0 ignored: that byte is always written | changed | random seed 1: `[SB]` | 2 fired: `a_e2e_read_data`, `a_write_disabled_byte_preserved` | K / K | as expected |
| M03 | 32 | WSTRB lanes reversed | changed | random seed 1: `[SB]` | 9 fired: `a_e2e_read_data`, `a_write_disabled_byte_preserved` ×4, `a_write_enabled_byte_updated` ×4 | K / K | as expected |
| M04 | 32 | Out-of-range access answers OKAY | changed | random seed 1: illegal bin `invalid_out_of_range_ok` | 3 fired: `a_e2e_read_data`, `a_read_slverr_out_of_range`, `a_write_slverr_out_of_range` | K / K | as expected |
| M05 | 32 | Range check off by one: the first out-of-range word is accepted | changed | random seed 1: illegal bin `invalid_out_of_range_ok` | 3 fired: `a_e2e_read_data`, `a_read_slverr_out_of_range`, `a_write_slverr_out_of_range` | K / K | as expected |
| M06 | 32 | BVALID dropped after one cycle, without waiting for BREADY | changed | smoke seed 1: `[DRV_TIMEOUT]` | 9 fired: `a_e2e_read_data`, `a_no_overflow` ×4, `a_bvalid_not_wait_bready`, `a_bvalid_stable`, `a_write_okay_in_range`, `a_write_slverr_out_of_range` | K / K | as expected |
| M07 | 32 | RDATA changes while RVALID && !RREADY | changed | smoke seed 1: `[SB]` | 3 fired: `a_e2e_read_data`, `a_read_slverr_out_of_range`, `a_rvalid_stable` | K / K | as expected |
| M08 | 32 | W before AW loses the data: the late AW clears the latched write data | changed | smoke seed 1: `[SB]` | 5 fired: `a_e2e_read_data`, `a_write_enabled_byte_updated` ×4 | K / K | as expected |
| M09a | 32 | Reset branch does not clear the regfile at all | changed | passed | 17 fired: `a_e2e_read_data`, `a_regfile_changes_only_on_own_write` ×16 | S / K | as expected |
| M09b | 32 | Regfile cleared at the first reset only | changed | passed | 17 fired: `a_e2e_read_data`, `a_regfile_changes_only_on_own_write` ×16 | S / K | as expected |
| M10 | 32 | Read decode rounds an unaligned address up to the next word | changed | unaligned seed 1: `[SB]` | 4 fired: `a_e2e_read_data`, `a_read_okay_in_range`, `a_read_slverr_out_of_range`, `a_read_data_matches_regfile` | K / K | as expected |
| M11 | 32 | Bit 12 of register 5 stuck at 0 | changed | random seed 2: `[SB]` | 2 fired: `a_e2e_read_data`, `a_write_enabled_byte_updated` | K / K | as expected |
| M12 | 32 | Out-of-range access answers DECERR instead of SLVERR | changed | random seed 1: illegal bin `decerr` | 4 fired: `a_bresp_legal_value`, `a_read_slverr_out_of_range`, `a_rresp_legal_value`, `a_write_slverr_out_of_range` | K / K | as expected |
| M13 | 32 | AWREADY not released after a write | changed | smoke seed 1: `[DRV_TIMEOUT]` | 7 fired: `a_e2e_read_data`, `a_awready_when_idle`, `a_bvalid_requires_aw_and_w`, `a_write_disabled_byte_preserved` ×4 | K / K | as expected |
| M14 | 32 | !bvalid dropped from the write-fire condition | changed | passed | 25 fired: `a_e2e_read_data`, `a_no_overflow` ×4, `a_bvalid_not_wait_bready`, `a_bvalid_stable`, `a_write_okay_in_range`, `a_write_slverr_out_of_range`, `a_regfile_changes_only_on_own_write` ×16 | S / K | as expected |
| M15 | 32 | ARREADY always high: a new AR overwrites a pending R | changed | passed | 7 fired: `a_e2e_read_data`, `a_no_overflow` ×2, `a_ar_leads_to_rvalid`, `a_read_okay_in_range`, `a_read_slverr_out_of_range`, `a_rvalid_stable` | S / K | as expected |
| M16 | 32 | Write fires on aw_hs_done alone, with stale write data | changed | random seed 1: `[DRV_TIMEOUT]` | 11 fired: `a_e2e_read_data`, `a_bvalid_requires_aw_and_w`, `a_wready_when_idle`, `a_write_disabled_byte_preserved` ×4, `a_write_enabled_byte_updated` ×4 | K / K | as expected |
| M17 | 32 | BVALID raised only when BREADY is high | changed | smoke seed 1: `[DRV_TIMEOUT]` | 1 fired: `a_bvalid_not_wait_bready` | K / K | as expected |
| M18 | 32 | ADDR_LSB hardcoded to 2 | no difference seen | passed | proven | E / E | as expected |
| M18 | 64 | ADDR_LSB hardcoded to 2 | changed | random seed 1: illegal bin `invalid_in_range_err` | 27 fired: `a_e2e_read_data`, `a_read_okay_in_range`, `a_write_okay_in_range`, `a_read_data_matches_regfile`, `a_regfile_changes_only_on_own_write` ×15, `a_write_enabled_byte_updated` ×8 | K / K | as expected |
| M19 | 32 | A read bypasses a write firing on the same edge and returns the new value | changed | passed | 1 fired: `a_read_data_matches_regfile` | S / K | as expected |
| M20 | 32 | Reset does not clear rdata / bresp | no difference seen | passed | proven | E / E | as expected |

## Survivors in simulation (expected)

| ID | Why the UVM bench misses it | Closed by (plan §6) |
|---|---|---|
| M09a (closed in 5a) | Without the reset the regfile starts as X, but the monitor copies `rdata` into a 2-state `bit`, so an unwritten register reads back as 0, which is what the scoreboard expects (plan §4, note on M09) | 5a: monitor X check (`MON_X`) |
| M09b | The regfile is cleared at power-on; no test resets mid-run, so the skipped later clears are never seen | 5b: `axi4lite_reset_test` |
| M14, M15 | Needs a second write while B is pending / a second AR while R is pending; the driver keeps one request in flight per channel | Stretch goal: pipelined driver |
| M19 | Needs a read and a write to the same register firing on the same edge | 5c: `axi4lite_rw_concurrency_test` |

M18 at 32 bits (`ADDR_LSB` is 2 there anyway) and M20 (`rdata` / `bresp` are not observable at the ports while VALID
is low) are equivalent: the behaviour check sees no difference, and neither flow can catch them.

Note: for M04, M05, M12 and M18 (64-bit) the simulation column shows a covergroup illegal bin, because
`questa_log.first_problem` reports the first problem line, and the coverage collector prints before the scoreboard.
The scoreboard flags the same transactions in all four runs (`[SB]` errors in the same log: M04 49, M05 29, M12 49, M18 85).
