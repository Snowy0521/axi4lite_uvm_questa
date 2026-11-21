#!/usr/bin/env python3
"""Small helpers shared by run_mutations.py and regress.py."""
import os
import signal
import subprocess

# Variables a parent make passes down: a `make mutate DATA_WIDTH=64` would
# otherwise reach every make these scripts start, whatever they pass.
MAKE_ENV = ("MAKEFLAGS", "MFLAGS", "MAKELEVEL", "MAKEOVERRIDES")


def sh(cmd, cwd, log, timeout):
    """Run a command in cwd, write its output to log; (exit code, output). A missing
    tool is 127 and a timeout is 124, not a crash of the caller.

    The command gets its own process group, and a timeout kills the whole group:
    the command is make, and the tool it started would otherwise keep running,
    holding its license and writing into the run directory."""
    env = {k: v for k, v in os.environ.items() if k not in MAKE_ENV}
    try:
        p = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             universal_newlines=True, start_new_session=True, env=env)
    except OSError as e:
        code, out = 127, "cannot run %s: %s\n" % (cmd[0], e)
    else:
        try:
            out, _ = p.communicate(timeout=timeout)
            code = p.returncode
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)
            try:
                out, _ = p.communicate(timeout=10)
            except subprocess.TimeoutExpired:      # something left the group and holds the pipe
                out = ""
            code = 124
            out += "timed out after %d s: %s\n" % (timeout, " ".join(cmd))
    with open(log, "w") as f:
        f.write(out)
    return code, out


def read(path):
    if not os.path.exists(path):
        return ""
    with open(path, errors="replace") as f:
        return f.read()


def remove(path):
    """Before a run that writes path: a run that dies must not leave an earlier
    result to be read as its own."""
    if os.path.exists(path):
        os.remove(path)
