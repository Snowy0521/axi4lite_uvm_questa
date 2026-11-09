#!/usr/bin/env python3
"""Tests for the mutation flow, run by make check (no Questa needed): every patch
applies and compiles at both widths, its baseline matches docs/plan.md section 4,
and scripts/questa_log.py classifies logs as intended.
"""
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_formal_report as cfr
import questa_log
import run_mutations as rm

ROOT = cfr.REPO_ROOT
PATCHES = sorted(glob.glob(os.path.join(ROOT, "mutations", "M*.patch")))

SIM_FILES = ["formal/axi4lite_formal_driver.sv", "formal/axi4lite_signature.sv"]


def slang(cwd, width, defines=()):
    cmd = ["slang", "-q", "--timescale", "1ns/1ps", "-DAXI4LITE_DATA_WIDTH=%d" % width]
    cmd += ["-D" + d for d in defines] + ["-f", "rtl/rtl.f", "-f", "formal/formal.f"]
    cmd += [] if defines else SIM_FILES
    return subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          universal_newlines=True)


class Patches(unittest.TestCase):
    def test_every_plan_row_has_a_patch_with_the_same_baseline(self):
        with open(os.path.join(ROOT, "docs/plan.md")) as f:
            plan = f.read()
        rows = re.findall(r"^\| (M\d+[ab]?) \|.*\| ([^|]*) \|$", plan, re.M)
        self.assertEqual(len(rows), 21)
        in_plan = {mid: re.findall(r"\*{0,2}([KSE])\*{0,2} / ([KSE])", cell) for mid, cell in rows}
        in_patches = {}
        for path in PATCHES:
            mid, _, baseline = rm.parse_patch(path)
            in_patches[mid] = [baseline[w] for w in sorted(baseline)]
        self.assertEqual(in_patches, in_plan)

    def test_every_patch_applies_and_compiles(self):
        for path in PATCHES:
            with self.subTest(os.path.basename(path)):
                d = tempfile.mkdtemp()
                try:
                    for item in ("rtl", "formal"):
                        shutil.copytree(os.path.join(ROOT, item), os.path.join(d, item))
                    p = subprocess.run(["patch", "-p1", "--batch", "--forward", "--input", path], cwd=d,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       universal_newlines=True)
                    self.assertEqual(p.returncode, 0, p.stdout)
                    with open(os.path.join(d, "rtl/axi4lite_slave.sv")) as f, \
                            open(os.path.join(ROOT, "rtl/axi4lite_slave.sv")) as g:
                        self.assertNotEqual(f.read(), g.read())
                    for width in (32, 64):
                        for defines in ((), ("QUESTA_FORMAL",)):
                            r = slang(d, width, defines)
                            self.assertEqual(r.returncode, 0, r.stdout)
                finally:
                    shutil.rmtree(d, ignore_errors=True)


SUMMARY = """# --- UVM Report Summary ---
#
# ** Report counts by severity
# UVM_INFO :    5
# UVM_WARNING :    0
# UVM_ERROR : %d
# UVM_FATAL : %d
"""


class Classify(unittest.TestCase):
    def test_pass(self):
        self.assertEqual(questa_log.classify(SUMMARY % (0, 0)), ("pass", ""))

    def test_uvm_error_gives_the_first_message(self):
        log = ("# UVM_ERROR tb/sb.sv(89) @ 100: uvm_test_top.env.sb [SB] READ MISMATCH addr=0x4\n"
               "# UVM_ERROR tb/sb.sv(89) @ 200: uvm_test_top.env.sb [SB] second\n" + SUMMARY % (2, 0))
        self.assertEqual(questa_log.classify(log), ("fail", "[SB] READ MISMATCH addr=0x4"))

    def test_uvm_fatal(self):
        log = ("# UVM_FATAL tb/d.sv(156) @ 300: uvm_test_top.env.agent.drv [DRV_TIMEOUT] timed out\n"
               + SUMMARY % (0, 1))
        self.assertEqual(questa_log.classify(log), ("fail", "[DRV_TIMEOUT] timed out"))

    def test_simulator_error_with_a_clean_uvm_summary(self):
        status, detail = questa_log.classify("# ** Error: Assertion error.\n" + SUMMARY % (0, 0))
        self.assertEqual(status, "fail")
        self.assertIn("Assertion error", detail)

    def test_counts_without_a_message_still_fail(self):
        self.assertEqual(questa_log.classify(SUMMARY % (1, 0))[0], "fail")

    def test_no_summary_is_never_a_pass(self):
        self.assertEqual(questa_log.classify("")[0], "crash")
        self.assertEqual(questa_log.classify("# some output\n")[0], "crash")
        self.assertEqual(questa_log.classify("# --- UVM Report Summary ---\n")[0], "crash")


class Letters(unittest.TestCase):
    def test_changed_behaviour(self):
        self.assertEqual(rm.result(True, True, False), "K / K")
        self.assertEqual(rm.result(False, True, False), "S / K")
        self.assertEqual(rm.result(False, False, False), "S / S")

    def test_equivalent_only_if_neither_flow_caught_it(self):
        self.assertEqual(rm.result(False, False, True), "E / E")
        self.assertEqual(rm.result(False, True, True), "S / K")   # formal shows it is not equivalent
        self.assertEqual(rm.result(True, False, True), "K / S")   # a formal miss, not "harmless"

    def test_error_is_not_equivalent(self):
        self.assertEqual(rm.result(None, False, True), "? / S")
        self.assertEqual(rm.result(False, None, False), "S / ?")


def process_gone(pid):
    """True once pid has exited (a zombie waiting for its reaper counts as gone)."""
    try:
        with open("/proc/%d/stat" % pid) as f:
            return f.read().rsplit(")", 1)[1].split()[0] == "Z"
    except OSError:
        return True


class Timeout(unittest.TestCase):
    def test_a_timeout_also_kills_what_make_started(self):
        d = tempfile.mkdtemp()
        try:
            pidfile = os.path.join(d, "child.pid")
            script = "sleep 30 & echo $! > %s; wait" % pidfile
            start = time.time()
            code, _ = rm.sh(["sh", "-c", script], d, os.path.join(d, "log"), 1)
            self.assertEqual(code, 124)
            self.assertLess(time.time() - start, 10)
            with open(pidfile) as f:
                child = int(f.read())
            for _ in range(50):
                if process_gone(child):
                    break
                time.sleep(0.1)
            self.assertTrue(process_gone(child))
        finally:
            shutil.rmtree(d, ignore_errors=True)

    def test_a_missing_tool_is_127(self):
        d = tempfile.mkdtemp()
        try:
            self.assertEqual(rm.sh(["no_such_tool_here"], d, os.path.join(d, "log"), 5)[0], 127)
        finally:
            shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
