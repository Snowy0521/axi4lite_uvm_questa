#!/usr/bin/env python3
"""What counts as a passing UVM run: the one place that decides it.

classify(text) reads a vsim log and returns (status, detail):
  "pass"   UVM report summary present, UVM_ERROR = UVM_FATAL = 0, no ** Error / ** Fatal
  "fail"   the run finished and something failed; detail is the first failure
  "crash"  no complete UVM report summary: the run did not finish

A bound assertion or an illegal coverage bin reports ** Error, not UVM_ERROR, so
both are checked. Anything not recognised as a pass is not a pass.
"""
import re

SUMMARY = "--- UVM Report Summary ---"
COUNT = r"^#?\s*%s\s*:\s*(\d+)"
PROBLEM = re.compile(r"^#?\s*((?:UVM_(?:ERROR|FATAL)\b(?!\s*:)|\*\* (?:Error|Fatal)\b).*)$", re.M)
TAGGED = re.compile(r"\[(\w+)\]\s*(.*)$")


def first_problem(text):
    """The first UVM_ERROR / UVM_FATAL / ** Error / ** Fatal line, shortened to
    '[TAG] message' when it has a UVM tag, or ''."""
    m = PROBLEM.search(text)
    if not m:
        return ""
    tagged = TAGGED.search(m.group(1))
    return "[%s] %s" % tagged.groups() if tagged else m.group(1)


def classify(text):
    errors = re.findall(COUNT % "UVM_ERROR", text, re.M)
    fatals = re.findall(COUNT % "UVM_FATAL", text, re.M)
    if SUMMARY not in text or not errors or not fatals:
        return "crash", first_problem(text) or "no complete UVM report summary"
    problem = first_problem(text)
    if int(errors[-1]) or int(fatals[-1]) or problem:
        return "fail", problem or "UVM_ERROR = %s, UVM_FATAL = %s" % (errors[-1], fatals[-1])
    return "pass", ""
