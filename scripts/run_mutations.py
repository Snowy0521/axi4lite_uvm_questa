#!/usr/bin/env python3
"""Mutation testing: inject each bug in mutations/ and record which flow catches it.

Each mutant runs in a throwaway copy, build/mutation/<id>/, never in the repo, so
an interrupted run cannot leave a bug in the real RTL. For each mutant and width:
  1. behaviour: the patch applies, and the signature of a random formal_tb run is
     compared with the clean design's. Equal signatures: "no difference seen".
  2. simulation: the UVM tests on the mutant, black-box (UVM_CHECKERS=no: the formal
     checkers are not bound in). Stops at the first failure.
     What counts as a failure is decided by scripts/questa_log.py.
  3. formal: make formal-verify, scored from the report (check_formal_report.py).
     make's exit status is not used: the self-check fails on any mutant, and
     qverify itself exits 0 with fired asserts.
The clean design must pass all three first, or nothing is scored.

Each patch states the result expected before the run (# baseline <width>: <sim>
<formal>, K killed / S survives / E equivalent). The summary marks every mutant
that differs: a survivor nobody expected is a finding.

Writes build/mutation/summary.md; exits 1 on any difference or error.

  python3 scripts/run_mutations.py                 (or: make mutate)
  python3 scripts/run_mutations.py --only M05,M18 --seeds 2

Python 3.6 compatible.
"""
import argparse
import atexit
import datetime
import glob
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_formal_report
import questa_log
from tools import read, remove, sh

OUT = "build/mutation"
COPY = ["rtl", "tb", "formal", "scripts", "Makefile"]
DIRECTED_TESTS = ["axi4lite_smoke_test"]
RANDOM_TESTS = ["axi4lite_random_test", "axi4lite_unaligned_test"]
RUN_TIMEOUT = 600        # one simulation, seconds
FORMAL_TIMEOUT = 3600    # one proof, seconds


def parse_patch(path):
    """(id, description, {width: (sim, formal)}) from a patch's header lines."""
    text = read(path)
    m = re.match(r"# (M\w+): (.+)\n", text)
    if not m:
        raise ValueError("%s: first line must be '# Mnn: description'" % path)
    baseline = {int(w): (s, f) for w, s, f in
                re.findall(r"^# baseline (\d+): ([KSE]) ([KSE])$", text, re.M)}
    if not baseline:
        raise ValueError("%s: no '# baseline <width>: <sim> <formal>' line" % path)
    return m.group(1), m.group(2), baseline


def prepare(mid, patch):
    """Fresh copy of the sources in build/mutation/<mid>/, with the patch applied.
    Returns (directory, applied)."""
    d = os.path.join(OUT, mid)
    if os.path.isdir(d):
        # Moved aside first: on NFS a file a dead tool still holds open stays as
        # .nfs*, and its directory can't be removed until that process exits
        old = os.path.join(OUT, "old", "%s.%d" % (mid, os.getpid()))
        os.makedirs(os.path.dirname(old), exist_ok=True)
        os.rename(d, old)
        shutil.rmtree(old, ignore_errors=True)
    os.makedirs(d)
    for item in COPY:
        if os.path.isdir(item):
            shutil.copytree(item, os.path.join(d, item))
        else:
            shutil.copy(item, d)
    if patch is None:
        return d, True
    # patch, not git apply: inside this work tree git apply skips paths outside the
    # current directory and still exits 0. So the result is checked too.
    code, _ = sh(["patch", "-p1", "--batch", "--forward", "--input", os.path.abspath(patch)],
                 d, os.path.join(d, "apply.log"), RUN_TIMEOUT)
    changed = any(read(os.path.join(d, f)) != read(f)
                  for f in re.findall(r"^\+\+\+ b/(\S+)", read(patch), re.M))
    return d, code == 0 and changed


def signature(d, width):
    """The behaviour signature, or None if the run did not produce one."""
    log = os.path.join(d, "build/sim/signature.log")
    remove(log)
    sh(["make", "formal-signature", "DATA_WIDTH=%d" % width], d,
       os.path.join(d, "signature_%d.log" % width), RUN_TIMEOUT)
    m = re.search(r"FORMAL SIM SIGNATURE: ([0-9a-f]+)", read(log))
    return m.group(1) if m else None


def score_sim(d, width, seeds):
    """(caught, detail): True at the first failing run, False if every run passes,
    None if a run did not finish or the build failed."""
    code, _ = sh(["make", "uvm-build", "DATA_WIDTH=%d" % width, "UVM_CHECKERS=no"], d,
                 os.path.join(d, "uvm_build_%d.log" % width), RUN_TIMEOUT)
    if code != 0:
        return None, "UVM build failed (see uvm_build_%d.log)" % width
    runs = [(t, 1) for t in DIRECTED_TESTS] + [(t, s) for t in RANDOM_TESTS for s in range(1, seeds + 1)]
    for test, seed in runs:
        log = os.path.join(d, "build/sim/%s_%d.log" % (test, seed))
        remove(log)
        code, _ = sh(["make", "uvm-run", "TEST=%s" % test, "SEED=%d" % seed, "DATA_WIDTH=%d" % width],
                     d, os.path.join(d, "uvm_run.log"), RUN_TIMEOUT)
        status, detail = questa_log.classify(read(log))
        if code == 124:
            return None, "%s seed %d timed out" % (test, seed)
        if status == "fail":
            return True, "%s seed %d: %s" % (test, seed, detail)
        if status == "crash":
            return None, "%s seed %d: %s" % (test, seed, detail)
    return False, ""


def score_formal(d, width, expected):
    """(caught, detail), from the report only."""
    name = "formal_report.txt" if width == 32 else "formal_report_%d.txt" % width
    code, _ = sh(["make", "formal-verify", "DATA_WIDTH=%d" % width], d,
                 os.path.join(d, "formal_%d.log" % width), FORMAL_TIMEOUT)
    if code == 124:
        return None, "qverify timed out"
    text = read(os.path.join(d, "build/formal", name))
    if not text:
        return None, "no report (see formal_%d.log)" % width
    return check_formal_report.formal_verdict(text, expected[name])


def result(sim, frm, same_signature):
    """'<sim> / <formal>'. Equivalent needs all three: the signature is one seed, so
    a flow that caught the mutant has shown it is not equivalent."""
    equivalent = same_signature and sim is False and frm is False

    def letter(caught):
        return "?" if caught is None else "K" if caught else "E" if equivalent else "S"
    return "%s / %s" % (letter(sim), letter(frm))


def lock():
    """One run per work tree: a second one would delete the first one's copies."""
    path = os.path.join(OUT, "run.pid")
    if os.path.exists(path):
        try:
            pid = int(read(path).strip())
            os.kill(pid, 0)
        except (ValueError, OSError):
            pid = None
        if pid:
            sys.exit("run_mutations: another run is active here (PID %d)" % pid)
    with open(path, "w") as f:
        f.write("%d\n" % os.getpid())
    atexit.register(lambda: os.path.exists(path) and os.remove(path))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--only", help="comma-separated mutant IDs, e.g. M05,M18")
    ap.add_argument("--seeds", type=int, default=5, help="seeds per random test")
    args = ap.parse_args()
    # Every path is repo-root-relative: work from there, wherever we were started
    os.chdir(check_formal_report.REPO_ROOT)

    patches = [(p,) + parse_patch(p) for p in sorted(glob.glob("mutations/M*.patch"))]
    if args.only:
        wanted = set(args.only.split(","))
        patches = [p for p in patches if p[1] in wanted]
        if {p[1] for p in patches} != wanted:
            sys.exit("run_mutations: no patch for %s" % ", ".join(wanted - {p[1] for p in patches}))
    os.makedirs(OUT, exist_ok=True)
    lock()
    expected = check_formal_report.load_expected()

    # The measuring tools are validated on the clean design before they measure
    d, _ = prepare("clean", None)
    clean_sig = {}
    for width in sorted({w for p in patches for w in p[3]}):
        print("clean design, %d-bit ..." % width, flush=True)
        clean_sig[width] = signature(d, width)
        sim, sim_detail = score_sim(d, width, args.seeds)
        frm, frm_detail = score_formal(d, width, expected)
        if clean_sig[width] is None or sim is not False or frm is not False:
            sys.exit("run_mutations: the clean design does not pass at %d bits (signature %s; simulation %s %s; "
                     "formal %s %s); see %s/clean/" % (width, clean_sig[width], sim, sim_detail, frm, frm_detail, OUT))

    rows, n_differs, n_error = [], 0, 0
    for patch, mid, description, baseline in patches:
        d, applied = prepare(mid, patch)
        for width in sorted(baseline):
            print("%s, %d-bit ..." % (mid, width), flush=True)
            want = "%s / %s" % baseline[width]
            if not applied:
                rows.append((mid, width, description, "patch does not apply", "", "", "?", want, "**error**"))
                n_error += 1
                continue
            sig = signature(d, width)
            same = sig == clean_sig[width]
            sim, sim_detail = score_sim(d, width, args.seeds)
            frm, frm_detail = score_formal(d, width, expected)
            got = result(sim, frm, same)
            error = sig is None or sim is None or frm is None
            n_error += error
            n_differs += not error and got != want
            rows.append((mid, width, description,
                         "no signature" if sig is None else "no difference seen" if same else "changed",
                         sim_detail or "passed", frm_detail or "proven", got, want,
                         "**error**" if error else "as expected" if got == want else "**differs**"))

    md = ["# Mutation summary", "",
          "%s; simulation: black-box UVM, %s, %d seeds of %s" % (
              datetime.date.today().isoformat(), ", ".join(DIRECTED_TESTS), args.seeds, ", ".join(RANDOM_TESTS)), "",
          "| ID | Width | Mutation | Behaviour | Simulation | Formal | Sim / formal | Expected | Result |",
          "|---|---|---|---|---|---|---|---|---|"]
    md += ["| %s | %d | %s | %s | %s | %s | %s | %s | %s |" % r for r in rows]
    md += ["", "**%d runs:** %d differ from the expected baseline, %d errors." % (len(rows), n_differs, n_error)]
    summary = os.path.join(OUT, "summary.md")
    with open(summary, "w") as f:
        f.write("\n".join(md) + "\n")
    print("\n".join(md))
    print("\nwritten: %s (one directory per mutant in %s/)" % (summary, OUT))
    sys.exit(0 if n_differs == 0 and n_error == 0 else 1)


if __name__ == "__main__":
    main()
