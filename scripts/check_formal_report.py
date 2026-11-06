#!/usr/bin/env python3
"""Formal self-check: fail unless a qverify report shows a complete, clean proof.

Usage (make formal-verify runs it after every proof):
    python3 scripts/check_formal_report.py build/formal/formal_report.txt

The expected numbers come from formal/expected_counts.txt, looked up by the
report's file name. Exit status 0 only if the report passes.

What is read, and fails closed: only two kinds of failure have been seen in a
real report (formal/reference/failing_*.txt), so these parts must look exactly
as in a clean report, and anything else in them is an error. The counts alone
are not enough: Questa counts a vacuous assert under Proven, with a Vacuous row
below it.
  - the Property Summary block: only the clean rows, each once, with the
    expected counts;
  - the Targets <x> (n) section headings: only Proven, Covered and Covered
    with Warning may have n > 0, and their n must agree with the summary;
  - the proof radius section and the bounded / unsatisfiable assumption
    sections: their "nothing here" sentences must be present.

Everything else in the report is ignored, including the names of the targets,
Assumptions Used in Proofs (non-empty whenever assumptions are on), and the
engine and process statistics.
"""
import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXPECTED_FILE = os.path.join(REPO_ROOT, "formal", "expected_counts.txt")

SUMMARY_HEADING = re.compile(r"^Property Summary\s+Count\s*$", re.M)
RULE = re.compile(r"^(=+|-+)$")
ROW = re.compile(r"^(Assumes|Asserts|Proven|Covers|Covered)\s+(\d+)$")
WARNED_ROW = re.compile(r"^\s+Covered with Warning\s+\((\d+)\)$")
SECTION = re.compile(r"^Targets (.+) \((\d+)\)\s*$", re.M)
CLEAN_SECTIONS = ("Proven", "Covered", "Covered with Warning")
ALL_RESOLVED = "<all targets either proven or fired>"
# Sign-off is on full proofs: a non-empty section here means some result rests
# on a bounded proof or on an unsatisfiable sanity check.
CLEAN_SENTINELS = ("<no assumptions used in bounded proofs>",
                   "<no assumptions used in unsatisfiable sanity checks>",
                   "<no assumptions used in bounded unsatisfiable sanity checks>")


def parse_summary(text):
    """Return (rows, errors). rows maps each summary row to its count; a report
    without warnings has no Covered-with-Warning row, so `warned` defaults to 0."""
    headings = SUMMARY_HEADING.findall(text)
    if len(headings) != 1:
        return {}, ["expected one Property Summary block, found %d" % len(headings)]
    rows, errors = {"warned": 0}, []
    block = text[SUMMARY_HEADING.search(text).end():]
    for line in block.splitlines():
        stripped = line.rstrip()
        if not stripped.strip() or RULE.match(stripped):
            continue
        row, warned = ROW.match(stripped), WARNED_ROW.match(stripped)
        if row and row.group(1) not in rows:
            rows[row.group(1)] = int(row.group(2))
        elif warned:
            rows["warned"] = int(warned.group(1))
        else:
            errors.append("unexpected summary row: %r" % stripped.strip())
    for name in ("Assumes", "Asserts", "Proven", "Covers", "Covered"):
        if name not in rows:
            errors.append("summary row missing: %s" % name)
    return rows, errors


def check_report(text, expected):
    """Return (errors, notes) for a report's text against one expected-counts
    entry {asserts, covers, assumes, warned}."""
    rows, errors = parse_summary(text)
    notes = []
    if errors:
        return errors, notes

    def want(name, value, what):
        if rows[name] != value:
            errors.append("%s: %s is %d, expected %d" % (what, name, rows[name], value))

    want("Asserts", expected["asserts"], "assert count")
    want("Proven", expected["asserts"], "not every assert proven")
    want("Covers", expected["covers"], "cover count")
    want("Covered", expected["covers"], "not every cover reached")
    want("Assumes", expected["assumes"], "assume count")

    sections = {}
    for name, count in SECTION.findall(text):
        sections[name] = int(count)
        if name not in CLEAN_SECTIONS and int(count) != 0:
            errors.append("section Targets %s has %s target(s)" % (name, count))
    if sections.get("Proven", 0) != rows["Proven"]:
        errors.append("section Targets Proven (%d) disagrees with the summary (%d)"
                      % (sections.get("Proven", 0), rows["Proven"]))
    covered = sections.get("Covered", 0) + sections.get("Covered with Warning", 0)
    if covered != rows["Covered"]:
        errors.append("Targets Covered sections add up to %d, the summary says %d"
                      % (covered, rows["Covered"]))
    if rows["warned"] != sections.get("Covered with Warning", 0):
        errors.append("section Targets Covered with Warning (%d) disagrees with the summary (%d)"
                      % (sections.get("Covered with Warning", 0), rows["warned"]))
    if ALL_RESOLVED not in text:
        errors.append("some targets are neither proven nor fired (proof radius section)")
    for sentinel in CLEAN_SENTINELS:
        if sentinel not in text:
            errors.append("expected %s" % sentinel)

    if rows["warned"] != expected["warned"]:
        notes.append("covered with warning is %d, was %d: worth a look (not a failure)"
                     % (rows["warned"], expected["warned"]))
    return errors, notes


def load_expected(path=EXPECTED_FILE):
    """{report file name: {asserts, covers, assumes, warned}}"""
    table = {}
    with open(path) as f:
        for line in f:
            fields = line.split("#")[0].split()
            if fields:
                name, asserts, covers, assumes, warned = fields
                table[name] = {"asserts": int(asserts), "covers": int(covers),
                               "assumes": int(assumes), "warned": int(warned)}
    return table


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    path = argv[1]
    name = os.path.basename(path)
    table = load_expected()
    if name not in table:
        print("FORMAL SELF-CHECK FAILED: %s is not in %s" % (name, EXPECTED_FILE))
        return 1
    if not os.path.exists(path):
        print("FORMAL SELF-CHECK FAILED: %s not found (did qverify finish?)" % path)
        return 1
    with open(path) as f:
        text = f.read()
    errors, notes = check_report(text, table[name])
    for note in notes:
        print("NOTE: %s" % note)
    if errors:
        print("FORMAL SELF-CHECK FAILED: %s" % path)
        for error in errors:
            print("  %s" % error)
        return 1
    want = table[name]
    print("FORMAL SELF-CHECK PASSED: %s: %d/%d proven, %d/%d covered, %d assumes"
          % (name, want["asserts"], want["asserts"], want["covers"], want["covers"],
             want["assumes"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
