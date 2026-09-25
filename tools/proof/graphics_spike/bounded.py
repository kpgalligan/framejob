"""Rule H for the graphics spike: every child runs under a hard wall-clock
bound, in its OWN process group, and only that group is ever killed.

`run` drains stdout and stderr while it waits (`communicate(timeout=)`), so
a child whose answer does not fit a 64 KiB pipe cannot deadlock it — the
lesson `tools/proof/README.md`'s words-spike section records. An expiry is
an ANSWER (`expired: True`), never an exception."""

import os
import signal
import subprocess
import threading
import time


def child_env(extra=None):
    """The caller's environment without the AssemblyAI key, which no row
    here needs (the Makefile `unexport`s it for the same reason)."""
    env = dict(os.environ)
    env.pop("RC_ASSEMBLYAI_KEY", None)
    env.update(extra or {})
    return env


def run(argv, seconds, cwd=None, env=None):
    started = time.monotonic()
    try:
        child = subprocess.Popen(argv, cwd=cwd, env=env or child_env(), text=True,
                                 stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, start_new_session=True)
    except OSError as error:
        return {"argv": argv, "rc": None, "stdout": "", "stderr": f"{type(error).__name__}: {error}",
                "seconds": 0.0, "expired": False}
    expired = False
    try:
        out, err = child.communicate(timeout=seconds)
    except subprocess.TimeoutExpired:
        expired = True
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        out, err = child.communicate()
    return {"argv": argv, "rc": child.returncode, "stdout": out, "stderr": err,
            "seconds": round(time.monotonic() - started, 3), "expired": expired}


class Background:
    """A bounded child that runs WHILE the caller acts (q7's watcher): its
    stdout lines are collected on a thread, and `finish` waits for it up to
    the bound and then kills its group."""

    def __init__(self, argv, seconds, cwd=None, env=None):
        self.started = time.monotonic()
        self.seconds = seconds
        self.lines = []
        self.child = subprocess.Popen(argv, cwd=cwd, env=env or child_env(), text=True,
                                      stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, start_new_session=True)
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self):
        for line in self.child.stdout:
            self.lines.append((time.time(), line.rstrip("\n")))

    def finish(self):
        remaining = max(0.0, self.seconds - (time.monotonic() - self.started))
        expired = False
        try:
            self.child.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            expired = True
            try:
                os.killpg(self.child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self.child.wait()
        self.reader.join(timeout=5)
        return {"rc": self.child.returncode, "expired": expired, "lines": self.lines,
                "stderr": self.child.stderr.read() if self.child.stderr else ""}
