#!/usr/bin/env python3
"""Tests for check_formal_report.py, run by make check (no Questa needed).

Each reference report must pass. Each damaged copy of one must fail: only clean
reports exist, so these damaged copies stand in for the failing runs the parser
has never seen.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_formal_report as cfr

REFERENCE = os.path.join(cfr.REPO_ROOT, "formal", "reference")


def read(name="formal_report.txt"):
    with open(os.path.join(REFERENCE, name)) as f:
        return f.read()


def replace(text, old, new):
    assert old in text, old
    return text.replace(old, new, 1)


class ReferenceReports(unittest.TestCase):
    def test_every_configuration_has_a_passing_reference(self):
        table = cfr.load_expected()
        self.assertEqual(len(table), 4)
        for name, expected in table.items():
            errors, notes = cfr.check_report(read(name), expected)
            self.assertEqual((errors, notes), ([], []), name)


class DamagedReports(unittest.TestCase):
    def setUp(self):
        self.text = read()
        self.expected = cfr.load_expected()["formal_report.txt"]

    def assertFails(self, text, expected=None):
        errors, _ = cfr.check_report(text, expected or self.expected)
        self.assertNotEqual(errors, [])

    def summary_row_after(self, row, new_row):
        """Add a row to the summary block, right after an existing one."""
        start = cfr.SUMMARY_HEADING.search(self.text).end()
        head, block = self.text[:start], self.text[start:]
        lines = block.splitlines()
        index = next(i for i, l in enumerate(lines) if l.startswith(row))
        lines.insert(index + 1, new_row)
        return head + "\n".join(lines) + "\n"

    def test_one_assert_not_proven(self):
        self.assertFails(replace(self.text, "Proven                                57",
                                 "Proven                                56"))

    def test_one_cover_not_reached(self):
        self.assertFails(replace(self.text, "Covered                               43",
                                 "Covered                               42"))

    def test_assert_lost_from_the_design(self):
        text = replace(self.text, "Asserts                               57",
                       "Asserts                               56")
        self.assertFails(replace(text, "Proven                                57",
                                 "Proven                                56"))

    def test_assume_dropped(self):
        self.assertFails(replace(self.text, "Assumes                               15",
                                 "Assumes                               14"))

    def test_expected_count_moved(self):
        self.assertFails(self.text, dict(self.expected, asserts=58))
        self.assertFails(self.text, dict(self.expected, covers=45))

    def test_unknown_summary_rows(self):
        for row in ("Fired                                  1",
                    "Inconclusive                           1",
                    "Uncovered                              1",
                    "  Proven with Warning  (1)",
                    "  Vacuous  (1)",
                    "something new"):
            self.assertFails(self.summary_row_after("Proven", row))

    def test_repeated_row(self):
        self.assertFails(self.summary_row_after("Proven", "Proven      57"))

    def test_failing_section_with_a_clean_summary(self):
        self.assertFails(replace(self.text, "Targets Proven (57)",
                                 "Targets Fired (1)\n---\nu_x.a_y\n---\nTargets Proven (57)"))

    def test_section_disagrees_with_summary(self):
        self.assertFails(replace(self.text, "Targets Proven (57)", "Targets Proven (56)"))
        self.assertFails(replace(self.text, "Targets Covered (10)", "Targets Covered (9)"))

    def test_unresolved_targets(self):
        self.assertFails(replace(self.text, cfr.ALL_RESOLVED, "u_x.a_y  12"))

    def test_bounded_or_unsatisfiable_sections_not_empty(self):
        for sentinel in ("<no assumptions used in bounded proofs>",
                         "<no assumptions used in unsatisfiable sanity checks>",
                         "<no assumptions used in bounded unsatisfiable sanity checks>"):
            self.assertFails(replace(self.text, sentinel, "u_assumptions.m_no_x_awvalid"))

    def test_report_cut_off_before_the_warning_row(self):
        self.assertFails(self.text[:self.text.index("  Covered with Warning")])

    def test_warning_row_disagrees_with_its_section(self):
        self.assertFails(replace(self.text, "Targets Covered with Warning (33)",
                                 "Targets Covered with Warning (32)"))

    def test_no_summary(self):
        self.assertFails(self.text[:cfr.SUMMARY_HEADING.search(self.text).start()])
        self.assertFails("")

    def test_two_summaries(self):
        self.assertFails(self.text + self.text)

    def test_warning_count_change_is_only_a_note(self):
        text = replace(self.text, "Covered with Warning  (33)", "Covered with Warning  (32)")
        text = replace(text, "Targets Covered with Warning (33)", "Targets Covered with Warning (32)")
        text = replace(text, "Targets Covered (10)", "Targets Covered (11)")
        errors, notes = cfr.check_report(text, self.expected)
        self.assertEqual(errors, [])
        self.assertEqual(len(notes), 1)


class CommandLine(unittest.TestCase):
    def test_report_passes(self):
        self.assertEqual(cfr.main(["x", os.path.join(REFERENCE, "formal_report_64.txt")]), 0)

    def test_missing_report_fails(self):
        self.assertEqual(cfr.main(["x", "build/formal/nothing/formal_report.txt"]), 1)

    def test_unknown_report_name_fails(self):
        self.assertEqual(cfr.main(["x", "build/formal/formal_report_128.txt"]), 1)


if __name__ == "__main__":
    unittest.main()
