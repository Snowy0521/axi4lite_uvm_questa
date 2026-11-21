#!/usr/bin/env python3
"""UVM regression: build once, run every test, merge coverage, check the seeds.

  python3 scripts/regress.py                        (or: make regress)
  python3 scripts/regress.py --tests axi4lite_random_test --seeds 20 --width 64

Directed tests run once; random tests run seeds 1..N. A run passes only by the
rules of scripts/questa_log.py: complete UVM report summary, UVM_ERROR =
UVM_FATAL = 0, and no ** Error / ** Fatal (a bound assertion fails that way).
Coverage is merged from passing runs only:
  - per test, gated at the test's goal (100% for the random tests; the smoke test
    only reaches part of the model by design, so its goal is 0);
  - across all tests, printed, not gated, with the DUT's code coverage.
Seed check: for each random test, N passing seeds must print N different monitor
fingerprints. A seed that is not applied makes every run identical, which no
coverage number shows.

Writes build/regress/summary.log (one line per run, with the command that
reproduces it) and merged reports in build/cov/. Exits 1 if any run fails, a
gate is missed or seeds repeat. Python 3.6 compatible.
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import questa_log
from tools import read, remove, sh

# test -> (random?, merged coverage goal in %)
TESTS = {
    "axi4lite_smoke_test":     (False, 0),
    "axi4lite_random_test":    (True, 100),
    "axi4lite_unaligned_test": (True, 100),
}
OUT = "build/regress"
RUNS = "build/cov/runs"
BUILD_TIMEOUT = 900
RUN_TIMEOUT = 600

FINGERPRINT = re.compile(r"FINGERPRINT ([0-9a-f]{8})")
SEED_COVERAGE = re.compile(r"Overall coverage for [^:]*: *([0-9.]+)%")
TOTAL_CVG = re.compile(r"TOTAL COVERGROUP COVERAGE: *([0-9.]+)%")
CODE_ROW = re.compile(r"^ +(Statements|Branches|Conditions|Expressions|FSM)\b.*$")


def fingerprint(log_text):
    m = FINGERPRINT.search(log_text)
    return m.group(1) if m else None


def repeated(fingerprints):
    """Fingerprints that occur more than once (None counts: a missing one is suspect)."""
    seen, dups = set(), set()
    for fp in fingerprints:
        (dups if fp in seen or fp is None else seen).add(fp)
    return sorted(str(d) for d in dups)


def covergroup_total(report_text):
    m = TOTAL_CVG.findall(report_text)
    return float(m[-1]) if m else None


def dut_code_coverage(report_text):
    """The summary rows of /tb_top/dut itself, not its children (the bound checkers)."""
    rows, inside = [], False
    for line in report_text.splitlines():
        if line.startswith("=== Instance: "):
            inside = line.split()[2] == "/tb_top/dut"
        elif inside and CODE_ROW.match(line):
            rows.append(line.strip())
    return rows


def merge(name, ucdbs):
    """Merge ucdbs into build/cov/<name>.ucdb; (covergroup %, code coverage rows)."""
    merged = "build/cov/%s.ucdb" % name
    sh(["vcover", "merge", merged] + ucdbs, ".", "build/cov/%s_merge.log" % name, RUN_TIMEOUT)
    cvg = "build/cov/%s_cvg.txt" % name
    sh(["vcover", "report", "-cvg", "-details", merged], ".", cvg, RUN_TIMEOUT)
    code = "build/cov/%s_code.txt" % name
    sh(["vcover", "report", "-details", merged], ".", code, RUN_TIMEOUT)
    return covergroup_total(read(cvg)), dut_code_coverage(read(code))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--tests", default=",".join(TESTS), help="comma-separated test names")
    ap.add_argument("--seeds", type=int, default=20, help="seeds per random test")
    ap.add_argument("--width", type=int, default=32, choices=(32, 64))
    ap.add_argument("--checkers", default="yes", choices=("yes", "no"),
                    help="formal checkers bound into the UVM DUT")
    args = ap.parse_args()
    os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    tests = args.tests.split(",")
    unknown = [t for t in tests if t not in TESTS]
    if unknown:
        sys.exit("regress: unknown test(s): %s (known: %s)" % (", ".join(unknown), ", ".join(TESTS)))
    make_vars = ["DATA_WIDTH=%d" % args.width, "UVM_CHECKERS=%s" % args.checkers]

    os.makedirs(OUT, exist_ok=True)
    os.makedirs(RUNS, exist_ok=True)
    for f in os.listdir(RUNS):
        os.remove(os.path.join(RUNS, f))
    code, _ = sh(["make", "uvm-build"] + make_vars, ".", os.path.join(OUT, "uvm_build.log"), BUILD_TIMEOUT)
    if code != 0:
        sys.exit("regress: build failed, see %s/uvm_build.log" % OUT)

    failed, summary, passing = False, [], {}
    for test in tests:
        seeds = range(1, args.seeds + 1) if TESTS[test][0] else [1]
        passing[test] = []
        for seed in seeds:
            log = "build/sim/%s_%d.log" % (test, seed)
            remove(log)
            remove("%s/%s_%d.ucdb" % (RUNS, test, seed))
            code, _ = sh(["make", "uvm-run", "TEST=%s" % test, "SEED=%d" % seed] + make_vars, ".",
                         os.path.join(OUT, "uvm_run.log"), RUN_TIMEOUT)
            text = read(log)
            status, detail = questa_log.classify(text)
            if code == 124:
                status, detail = "crash", "timed out after %d s" % RUN_TIMEOUT
            fp = fingerprint(text)
            cov = SEED_COVERAGE.findall(text)
            line = "%-5s %s seed %d: %s" % (
                status.upper(), test, seed,
                detail if status != "pass" else "coverage this seed %s%%, fingerprint %s" % (
                    cov[-1] if cov else "?", fp))
            print(line, flush=True)
            summary.append("%s  | make uvm TEST=%s SEED=%d %s" % (line, test, seed, " ".join(make_vars)))
            if status == "pass":
                passing[test].append((seed, fp))
            else:
                failed = True

    print()
    for test in tests:
        random_test, goal = TESTS[test]
        ucdbs = ["%s/%s_%d.ucdb" % (RUNS, test, seed) for seed, _ in passing[test]
                 if os.path.exists("%s/%s_%d.ucdb" % (RUNS, test, seed))]
        if not ucdbs:
            line = "COVERAGE %s: no passing run to merge" % test
            failed = True
        else:
            cvg, _ = merge(test, ucdbs)
            ok = cvg is not None and cvg >= goal
            failed |= not ok
            line = "COVERAGE %s: %s%% merged over %d run(s), goal %d%%%s" % (
                test, "?" if cvg is None else "%.2f" % cvg, len(ucdbs), goal, "" if ok else "  ** BELOW GOAL **")
        print(line)
        summary.append(line)
        if random_test and len(passing[test]) >= 2:
            dups = repeated([fp for _, fp in passing[test]])
            line = "SEEDS %s: %s" % (test, "%d distinct fingerprints" % len(passing[test]) if not dups
                                      else "** repeated or missing fingerprint(s): %s **" % ", ".join(dups))
            failed |= bool(dups)
            print(line)
            summary.append(line)

    all_ucdbs = sorted(os.path.join(RUNS, f) for f in os.listdir(RUNS) if f.endswith(".ucdb"))
    passing_ucdbs = [u for u in all_ucdbs
                     if any(u.endswith("/%s_%d.ucdb" % (t, s)) for t in tests for s, _ in passing[t])]
    if passing_ucdbs:
        cvg, code_rows = merge("all", passing_ucdbs)
        line = "COVERAGE all tests: %s%% merged over %d run(s) (not gated)" % (
            "?" if cvg is None else "%.2f" % cvg, len(passing_ucdbs))
        print(line)
        summary.append(line)
        print("DUT CODE COVERAGE (merged, not gated; details in build/cov/all_code.txt):")
        for row in code_rows:
            print("  " + row)
        summary += ["  " + r for r in code_rows]

    verdict = "REGRESSION %s (%s, %d-bit, checkers %s)" % (
        "FAILED" if failed else "PASSED", ", ".join(tests), args.width, args.checkers)
    print(verdict)
    summary.append(verdict)
    with open(os.path.join(OUT, "summary.log"), "w") as f:
        f.write("\n".join(summary) + "\n")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
