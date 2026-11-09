#!/usr/bin/env python3
"""Tests for regress.py's parsing, run by make check (no Questa needed)."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import regress


class Fingerprints(unittest.TestCase):
    def test_read_from_the_monitor_line(self):
        log = "# UVM_INFO tb/m.sv(80) @ 5000: uvm_test_top.env.agent.mon [FINGERPRINT] FINGERPRINT 1a2b3c4d (212 transactions)\n"
        self.assertEqual(regress.fingerprint(log), "1a2b3c4d")
        self.assertIsNone(regress.fingerprint("# nothing here\n"))

    def test_repeats_and_missing_ones_are_reported(self):
        self.assertEqual(regress.repeated(["a", "b", "c"]), [])
        self.assertEqual(regress.repeated(["a", "b", "a"]), ["a"])
        self.assertEqual(regress.repeated(["a", None]), ["None"])


class Coverage(unittest.TestCase):
    def test_covergroup_total_takes_the_last_one(self):
        text = "TOTAL COVERGROUP COVERAGE: 50.00%  COVERGROUP TYPES: 1\n...\nTOTAL COVERGROUP COVERAGE: 100.00%  COVERGROUP TYPES: 1\n"
        self.assertEqual(regress.covergroup_total(text), 100.0)
        self.assertIsNone(regress.covergroup_total(""))

    def test_code_coverage_of_the_dut_only(self):
        text = "\n".join([
            "=== Instance: /tb_top/dut",
            "    Statements                      35        35         0   100.00",
            "    Conditions                      15        11         4    73.33",
            "=== Instance: /tb_top/dut/u_bb_protocol",
            "    Statements                      99         1        98     1.01",
            "=== Instance: /tb_top",
            "    Branches                         1         1         0   100.00",
        ])
        rows = regress.dut_code_coverage(text)
        self.assertEqual(len(rows), 2)
        self.assertTrue(rows[0].startswith("Statements") and rows[1].startswith("Conditions"))


if __name__ == "__main__":
    unittest.main()
