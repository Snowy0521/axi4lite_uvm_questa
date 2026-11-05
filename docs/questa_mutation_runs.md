# Step 3: two mutation runs on Questa (A and B)

**Purpose:** get two real failing reports and confirm that the formal self-check really fails them. Both runs
**should fail**; failing is the correct result.

| Copy | What changes | Question it answers |
|---|---|---|
| A (`/tmp/m04`) | Out-of-range accesses answer OKAY instead of SLVERR (M04 in `docs/plan.md`) | How does Questa print a failing assert and an unreached cover? |
| B (`/tmp/vac`) | The condition of `a_bresp_legal_value` can never hold, so the assert is vacuous | Does Questa count a vacuous assert as `Proven`? |

Each run takes about 2 minutes. All edits happen in the `/tmp` copies, so the project directory is not touched.

---

## 0. Setup

The project on the server must be at `step3-lint-check`, `3308dd9` or later. If it isn't, update it first.

```bash
# Replace with the project path on the server
PROJ=<project-dir>
RESULTS=~/step3_results
mkdir -p $RESULTS

cd $PROJ
ls scripts/check_formal_report.py formal/expected_counts.txt   # both files must exist
python3 --version                                              # the self-check needs python3
which qverify                                                  # Questa Formal must be on PATH
```

If `ls` reports an error, the code is out of date. Update it before going on.

---

## 1. Run A: out-of-range answers OKAY

```bash
rm -rf /tmp/m04 && cp -r $PROJ /tmp/m04 && cd /tmp/m04 && rm -rf build

sed -i 's/resp <= AXI_RESP_SLVERR;/resp <= AXI_RESP_OKAY;/' rtl/axi4lite_slave.sv
grep -c 'resp <= AXI_RESP_SLVERR;' rtl/axi4lite_slave.sv       # must print 0

make formal-verify 2>&1 | tee $RESULTS/m04.log
echo "make exit code: ${PIPESTATUS[0]}" | tee -a $RESULTS/m04.log

cp build/formal/formal_report.txt $RESULTS/failing_m04.txt
```

---

## 2. Run B: vacuous assert

```bash
rm -rf /tmp/vac && cp -r $PROJ /tmp/vac && cd /tmp/vac && rm -rf build

sed -i "s/a_bresp_legal_value: assert property (bvalid |->/a_bresp_legal_value: assert property (1'b0 |->/" formal/axi4lite_blackbox_protocol.sv
grep -c "a_bresp_legal_value: assert property (1'b0 |->" formal/axi4lite_blackbox_protocol.sv   # must print 1

make formal-verify 2>&1 | tee $RESULTS/vac.log
echo "make exit code: ${PIPESTATUS[0]}" | tee -a $RESULTS/vac.log

cp build/formal/formal_report.txt $RESULTS/failing_vacuous.txt
```

If a `cp` can't find `formal_report.txt`, qverify didn't write a report. That is a useful result too: keep the `.log`.

---

## 3. Reading the results

Look at the last lines of each `.log`:

| What you see | Meaning | Next |
|---|---|---|
| `FORMAL SELF-CHECK FAILED` with reasons, non-zero `make exit code` | As expected | Keep the results |
| `make` stopped at the qverify line, no self-check output | A failure, but not the expected one | Keep the results and note it |
| A shows `FORMAL SELF-CHECK PASSED` | Unexpected: the mutant was not caught | Keep the results and investigate |
| **B shows `FORMAL SELF-CHECK PASSED`** | **The self-check has a vacuity hole, and step 3 can't finish** | Keep the results; **do not merge** |

---

## 4. Files to keep

The four files in `~/step3_results/`:

- `m04.log`
- `failing_m04.txt`
- `vac.log`
- `failing_vacuous.txt`

The reports name the host they ran on. Before adding one to the repo, strip it with the `sed` in `docs/plan.md`
§2.8, and check that the host name is gone.

To clean up afterwards: `rm -rf /tmp/m04 /tmp/vac`.

---

## 5. The rest of the step 3 checklist

Run these in the project directory, in the same session:

```bash
cd $PROJ
make check                                                  # CHECK PASSED (needs verilator and slang; skip if the server has neither)
make simple                                                 # *** TEST PASSED ***
make uvm-sweep TEST=axi4lite_random_test N=3                # 3 x OK
make uvm-sweep TEST=axi4lite_random_test N=3 DATA_WIDTH=64  # 3 x OK
make formal-verify-all                                      # two FORMAL SELF-CHECK PASSED lines: 57/57, 65/65 proven, 43/43 covered
make formal-verify-noassume                                 # FORMAL SELF-CHECK PASSED, 0 assumes
make formal-verify-noassume DATA_WIDTH=64                   # FORMAL SELF-CHECK PASSED, 0 assumes
git status --short --ignored                                # only build/ (skip if the project is not a git clone)
```

The four proofs take about 14 minutes in total. Note which items pass and which fail.
