#!/usr/bin/env python3
"""Issue #555 — how many documents one instance holds open at once, measured
against the built binary over MCP.

Every document here carries a clip with picture and sound (`media/AV.mov` on
a 640×360 canvas), so each has its player and its caches. The run first makes
and closes the packages `open_project` will need, then opens documents one
after another without closing any, `open_project` and `new_project` in turn,
until `--bound` are open at once. Every ten documents it prints the open
count, the process's threads (`ps -M`), its resident memory (`ps -o rss=`),
the slowest call since the last line and the host's one-minute load.

Rows:

  V0  the verdict rule over made-up readings, no app: a call answered while
      its readings were taken is "slow"; an unanswered one above 0 % CPU is
      "slow"; an unanswered one at 0 % with `_performFileAccess` on the main
      thread is "deadlock"; an unanswered one at 0 % on any other stack, or
      with no sample, is "hung".
  D0  the instance listens; `Frame Job: ` never appears in its log (re-read
      at the end).
  O1  `--bound` documents open at once, every call answered; the table and
      the calls that ran past `--call-seconds` are printed.
  O2  with the bound open, `get_project` answers on the first, the middle and
      the last document, and `set_canvas` on the last applies (read back).
  O3  every document closes (`close_project {discard: true}`): each call
      answers, and `snapshot_ui {}` then lists no editor window.
  O4  the thread count falls back under its count before the first document
      plus 64 (`close_project_proof.py` C3's margin), read 5, 15, 30 and 60 s
      after the last close; the first reading under it passes the row. It
      failed until #568: a closed document whose preview had been built kept
      its player, and with it five CoreMedia threads, until another window
      opened (`tools/proof/README.md`, "Issue #568").
  V1  O5's rule over made-up readings, no app (`memory_fell`).
  O5  resident memory comes back after the closes: the lowest reading after
      the last close is at most the reading before the first document plus
      three quarters of what the bound added (read 10 s after the bound). The
      readings go on through 5, 15, 30 and 60 s until both O4's and O5's rules
      hold, or the last wait is over, and each is printed with the one-minute
      load. It failed until #592: AppKit keeps a closed window until another
      window opens, and the window kept its editor's whole view tree. Three
      quarters is measured, not chosen: before #592 a run kept 98–104 % of
      what the bound added, after it 45–49 %, the rest freed malloc pages the
      allocator had not yet given back (`tools/proof/README.md`, "Issue #592").
  O6  with `--heap` only (Debug: a Release build is hardened and `heap` cannot
      attach): after the readings, `heap <pid>` counts no
      `EditorViewController` and no `Playback`; the `EditorWindow` count, the
      bare windows AppKit still keeps, is printed and not scored. A `heap`
      that cannot read the instance fails the row.

**A hang is never read off a timeout.** A call that runs past
`--call-seconds` (default 120) gets three `ps -o %cpu=` readings a second
apart. If it answered meanwhile, or any reading is 0.5 % or more, it is
"slow": the run waits for it (up to 600 s) and goes on. Only an unanswered
call with every reading under 0.5 % is sampled (`sample <pid> 5`, kept at
`work/open-documents/sample.txt`): "deadlock" when the main thread's stack
holds `_performFileAccess` (the stack `tools/proof/README.md`'s "Relaunch the
instance between proof sessions" describes), else "hung". Either fails O1
with the count it happened at, and the run makes no further call.

    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/open_documents_proof.py [--bound N] [--only-kind new|open] [--call-seconds S] [--app PATH] [--heap] [--mutant timeout-only|any-fall]

It launches one instance of its own (`mcp.launch` on `proof_app.binary()`),
logging to `work/open-documents/framejob.log`, and stops it by its PID. It is
slow and memory-heavy (a window per document) and in no make target: run it
when the document machinery changes. `--mutant timeout-only` makes the
verdict "deadlock" for any overrun, which V0 must fail; `--mutant any-fall`
makes O5's rule pass on any reading under the bound's, which V1 must fail.
Exit 0 when every row passes, else 1.
"""

import argparse
import os
import re
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/open-documents"
AV_MOV = ROOT / "tools/proof/media/AV.mov"
SAMPLE = WORK / "sample.txt"
OLD_FRAME = "_performFileAccess"
THREAD_HEAD = re.compile(r"^\s+\d+ Thread_")   # a thread's first line in `sample`'s call graph
IDLE_BELOW = 0.5          # a %cpu reading under this rounds to 0 %
HARD = 600                # the longest any one call is waited for
THREAD_SLACK = 64
STEP = 10
FALL = (5, 15, 30, 60)    # seconds after the last close at which threads and memory are read
SETTLE = 10              # seconds the bound is held before its last reading
HEAP_SECONDS = 300       # the longest `heap <pid>` is waited for (--heap)
HEAP_CLASSES = ("EditorViewController", "Playback", "EditorWindow")
# The mutants, as `mutant_anchors.py` reads them: switches on MUTANT in `verdict` and
# `memory_fell`, no tree text.
MUTANTS = ("timeout-only", "any-fall")
MUTANT = None

rows = {}


def check(row, good, detail=""):
    rows[row] = bool(good)
    print(f"{row} {'pass' if good else 'fail'} — {detail}", flush=True)


class Wedged(Exception):
    """A call that never answered: the verdict and what was read."""


# ---- the verdict ----------------------------------------------------------------

def verdict(answered, readings, main_stack):
    """"slow", "hung" or "deadlock" for a call past its bound. `answered`: it
    answered while the readings were taken. `readings`: the %cpu values.
    `main_stack`: the sample's main-thread text, or None when there is none."""
    if MUTANT == "timeout-only":
        return "deadlock"
    if answered or any(r is None or r >= IDLE_BELOW for r in readings):
        return "slow"
    if main_stack is not None and OLD_FRAME in main_stack:
        return "deadlock"
    return "hung"


def memory_line(before, bound):
    """O5's line, in MB: the resident memory before the first document plus three quarters of
    what the bound added (#592). None when either reading is missing."""
    if before is None or bound is None:
        return None
    return before + (bound - before) * 3 / 4


def memory_fell(before, bound, readings):
    """O5's rule: the lowest resident reading after the last close is at most `memory_line`.
    `readings`: the MB read after the closes, None where `ps` answered nothing."""
    read = [r for r in readings if r is not None]
    line_mb = memory_line(before, bound)
    if line_mb is None or not read:
        return False
    if MUTANT == "any-fall":
        return min(read) < bound
    return min(read) <= line_mb


def v1():
    cases = [("#568 at 40: 250 before, 985 at the bound, 913 after", (250, 985, [913]), False),
             ("back to where it began", (250, 985, [260]), True),
             ("exactly on the line", (250, 950, [775]), True),
             ("one MB above the line", (250, 950, [776]), False),
             ("the lowest of several", (250, 950, [900, 800, 400]), True),
             ("a reading unread", (250, 950, [None, 400]), True),
             ("nothing read after", (250, 950, [None, None]), False),
             ("no reading before", (None, 950, [300]), False)]
    got = [(name, memory_fell(*given), want) for name, given, want in cases]
    bad = [f"{name}: {said} ≠ {want}" for name, said, want in got if said != want]
    check("V1", not bad, f"{len(got) - len(bad)}/{len(got)} rulings"
                         + (f"; wrong: {bad}" if bad else ""))


def heap_counts(pid):
    """`heap <pid>`'s instance counts of HEAP_CLASSES, matched on the class name's last
    component; (counts, the lines counted, None) or (None, None, why)."""
    ran = bounded.run(["heap", "-q", str(pid)], HEAP_SECONDS)
    if ran["expired"] or ran["rc"] != 0:
        return None, None, (f"heap exited {ran['rc']}" + (" (expired)" if ran["expired"] else "")
                            + f": {ran['stderr'].strip()[-300:]}")
    counts, lines = {name: 0 for name in HEAP_CLASSES}, []
    for text in ran["stdout"].splitlines():
        fields = text.split()
        if len(fields) < 4 or not fields[0].isdigit():
            continue
        last = fields[3].rsplit(".", 1)[-1]
        if last in counts:
            counts[last] += int(fields[0])
            lines.append(" ".join(fields[:5]))
    return counts, lines, None


def v0():
    cases = [("answered while read", (True, [0.0, 0.0, 0.0], None), "slow"),
             ("unanswered, busy", (False, [0.0, 12.5, 0.0], None), "slow"),
             ("unanswered, a reading unread", (False, [0.0, None, 0.0], None), "slow"),
             ("unanswered, 0 %, the old stack",
              (False, [0.0, 0.1, 0.0], f"-[NSDocument {OLD_FRAME}:]\n semaphore_wait_trap"),
              "deadlock"),
             ("unanswered, 0 %, another stack",
              (False, [0.0, 0.0, 0.0], "mach_msg2_trap\n __CFRunLoopRun"), "hung"),
             ("unanswered, 0 %, no sample", (False, [0.0, 0.0, 0.0], None), "hung")]
    got = [(name, verdict(*given), want) for name, given, want in cases]
    bad = [f"{name}: {said} ≠ {want}" for name, said, want in got if said != want]
    check("V0", not bad, f"{len(got) - len(bad)}/{len(got)} verdicts"
                         + (f"; wrong: {bad}" if bad else ""))


# ---- reading the process --------------------------------------------------------

def ps(pid, *flags):
    try:
        return subprocess.run(["ps", *flags, "-p", str(pid)], capture_output=True, text=True,
                              timeout=20).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def thread_count(pid):
    """`close_project_proof.thread_count`: `ps -M`'s lines less its heading."""
    lines = [line for line in ps(pid, "-M").splitlines() if line.strip()]
    return len(lines) - 1 if lines else None


def resident_mb(pid):
    text = ps(pid, "-o", "rss=").strip()
    return round(int(text) / 1024) if text.isdigit() else None


def cpu(pid):
    try:
        return float(ps(pid, "-o", "%cpu=").strip())
    except ValueError:
        return None


def main_stack(pid):
    """`sample <pid> 5` written to SAMPLE; the main thread's block of it, or
    None when no sample could be taken or it names no main thread."""
    SAMPLE.unlink(missing_ok=True)
    ran = bounded.run(["sample", str(pid), "5", "-file", str(SAMPLE)], 120)
    try:
        text = SAMPLE.read_text(errors="replace")
    except OSError:
        print(f"  no sample: rc {ran['rc']} {ran['stderr'].strip()[-200:]}", flush=True)
        return None
    block, inside = [], False
    for line in text.splitlines():
        if THREAD_HEAD.match(line):
            if inside:
                break
            inside = "com.apple.main-thread" in line
        if inside:
            block.append(line)
    return "\n".join(block) if block else None


# ---- one instance ---------------------------------------------------------------

class App:
    """The client with the bound: `call` waits `seconds` for an answer, then
    asks `verdict` what the wait is."""

    def __init__(self, client, pid, seconds):
        self.client, self.pid, self.seconds = client, pid, seconds
        self.overruns = []      # (tool, seconds it took)
        self.slowest = 0.0      # since the last table line
        self.wedged = None

    def call(self, tool, arguments):
        if self.wedged:
            raise Wedged(self.wedged)
        box = {}

        def work():
            try:
                box["reply"] = self.client.call_with(tool, arguments)
            except Exception as error:  # handed to the caller's thread
                box["error"] = error

        thread = threading.Thread(target=work, daemon=True)
        began = time.monotonic()
        thread.start()
        thread.join(self.seconds)
        if thread.is_alive():
            self.overrun(tool, thread, began)
        took = time.monotonic() - began
        self.slowest = max(self.slowest, took)
        if took > self.seconds:
            self.overruns.append((tool, round(took, 1)))
        if "error" in box:
            raise box["error"]
        return box["reply"]

    def overrun(self, tool, thread, began):
        readings = []
        for _ in range(3):
            readings.append(cpu(self.pid))
            thread.join(1)
        answered = not thread.is_alive()
        idle = not any(r is None or r >= IDLE_BELOW for r in readings)
        stack = main_stack(self.pid) if idle and not answered else None
        said = verdict(answered, readings, stack)
        if said == "slow":
            thread.join(HARD)
            if not thread.is_alive():
                return
            said = f"unanswered after {HARD} s at {cpu(self.pid)} % CPU (busy, not a hang)"
        self.wedged = (f"{said}: {tool} unanswered {time.monotonic() - began:.0f} s; "
                       f"%cpu {readings}; threads {thread_count(self.pid)}, "
                       f"{resident_mb(self.pid)} MB resident"
                       + (f"; sample at {SAMPLE}" if stack is not None else ""))
        raise Wedged(self.wedged)


def package(name):
    return str(WORK / f"{name}.framejob")


def fill(app, path):
    """A new project at `path`: 640×360, `AV.mov` placed at 0."""
    app.call("new_project", {"path": path})
    app.call("set_canvas", {"project": path, "width": 640, "height": 360})
    media = app.call("import_media", {"project": path, "path": str(AV_MOV)})["media"]
    track = app.call("get_project", {"project": path})["project"]["tracks"][0]["id"]
    app.call("add_clip", {"project": path, "track": track, "media": media, "at": 0})


def kinds(bound, only):
    """The door each held document comes through, in order."""
    return [only or ("open" if n % 2 == 0 else "new") for n in range(bound)]


def line(app, count):
    print(f"  | {count} | {thread_count(app.pid)} | {resident_mb(app.pid)} | "
          f"{app.slowest:.1f} | {os.getloadavg()[0]:.1f} |", flush=True)
    app.slowest = 0.0


def run_rows(app, bound, only, heap=False):
    order = kinds(bound, only)
    saved = [package(f"saved-{n:03d}") for n, kind in enumerate(order) if kind == "open"]
    began = time.monotonic()
    for path in saved:
        fill(app, path)
        app.call("save_project", {"project": path})
        app.call("close_project", {"project": path})
    print(f"  {len(saved)} packages made, saved and closed in {time.monotonic() - began:.0f} s "
          f"(slowest call {app.slowest:.1f} s)", flush=True)
    app.slowest = 0.0
    before, before_mb = thread_count(app.pid), resident_mb(app.pid)
    print(f"  before the first document: {before} threads, {before_mb} MB resident\n"
          f"  | open | threads | resident MB | slowest call s | load (1 min) |\n"
          f"  |---|---|---|---|---|", flush=True)
    held, waiting = [], iter(saved)
    began = time.monotonic()
    try:
        for n, kind in enumerate(order):
            if kind == "open":
                path = next(waiting)
                app.call("open_project", {"path": path})
            else:
                path = package(f"new-{n:03d}")
                fill(app, path)
            held.append(path)
            app.call("get_project", {"project": path})
            if len(held) % STEP == 0 or len(held) == bound:
                line(app, len(held))
    except Wedged as wedge:
        check("O1", False, f"{len(held)} open when the next call ({order[len(held)]}) "
                           f"stopped answering — {wedge}")
        raise
    time.sleep(SETTLE)
    print(f"  after {SETTLE} s more:", flush=True)
    bound_mb = resident_mb(app.pid)
    line(app, len(held))
    doors = {kind: order.count(kind) for kind in sorted(set(order))}
    check("O1", len(held) == bound,
          f"{len(held)} documents open at once ({doors}) in {time.monotonic() - began:.0f} s: "
          f"{thread_count(app.pid)} threads, {resident_mb(app.pid)} MB resident; "
          f"{len(app.overruns)} call(s) past {app.seconds} s {app.overruns[:6]}")

    probes = [held[0], held[len(held) // 2], held[-1]]
    answered = [bool(app.call("get_project", {"project": p}).get("project")) for p in probes]
    app.call("set_canvas", {"project": held[-1], "width": 720, "height": 480})
    canvas = app.call("get_project", {"project": held[-1]})["project"]["canvas"]
    size = (canvas.get("width"), canvas.get("height"))
    check("O2", all(answered) and size == (720, 480),
          f"get_project on the first, middle and last: {answered}; set_canvas on the last "
          f"reads back {size}")

    began, bad = time.monotonic(), []
    for path in held:
        try:
            app.call("close_project", {"project": path, "discard": True})
        except mcp.ToolError as error:
            bad.append(f"{Path(path).name}: {error}")
    took, closed, seen, after = time.monotonic() - began, time.monotonic(), [], None
    editors = [w for w in app.call("snapshot_ui", {}).get("windows", [])
               if w.get("kind") == "editor"]
    resident, line_mb = [], memory_line(before_mb, bound_mb)
    for wait in FALL:   # read until the threads AND the memory have fallen, or the last wait
        time.sleep(max(0.0, closed + wait - time.monotonic()))
        after, mb = thread_count(app.pid), resident_mb(app.pid)
        resident.append(mb)
        seen.append(f"{wait} s: {after} threads, {mb} MB (load {os.getloadavg()[0]:.1f})")
        fallen = before is not None and after is not None and after < before + THREAD_SLACK
        if fallen and memory_fell(before_mb, bound_mb, resident):
            break
    print("  after the last close: " + "; ".join(seen), flush=True)
    check("O3", not bad and not editors,
          f"{len(held) - len(bad)}/{len(held)} closed in {took:.0f} s; {len(editors)} editor "
          f"window(s) left" + (f"; refused {bad[:3]}" if bad else ""))
    ok = before is not None and after is not None and after < before + THREAD_SLACK
    check("O4", ok, f"threads {before} before the first document, and after the last close "
                    f"{'; '.join(seen)} (wanted < {before} + {THREAD_SLACK})")
    low = min((r for r in resident if r is not None), default=None)
    check("O5", memory_fell(before_mb, bound_mb, resident),
          f"resident {before_mb} MB before the first document, {bound_mb} MB at the bound, "
          f"lowest {low} MB after the last close (wanted ≤ "
          f"{'?' if line_mb is None else f'{line_mb:.0f}'} MB, three quarters of what the "
          f"bound added); load {os.getloadavg()[0]:.1f}")
    if heap:
        counts, lines, why = heap_counts(app.pid)
        if counts is None:
            check("O6", False, f"heap could not read the instance: {why}")
        else:
            check("O6", counts["EditorViewController"] == 0 and counts["Playback"] == 0,
                  f"after {len(held)} closes heap counts {counts} (wanted no "
                  f"EditorViewController and no Playback; the EditorWindow count is printed, "
                  f"not scored); counted {lines}")


def complaints(log):
    try:
        with open(log, errors="replace") as handle:
            return [text.rstrip() for text in handle if "Frame Job: " in text]
    except OSError as error:
        return [f"the log could not be read: {error}"]


def main():
    global MUTANT
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--app", type=Path, default=None)
    parser.add_argument("--bound", type=int, default=150)
    parser.add_argument("--only-kind", choices=("new", "open"), default=None)
    parser.add_argument("--call-seconds", type=float, default=120)
    parser.add_argument("--mutant", choices=MUTANTS, default=None)
    parser.add_argument("--heap", action="store_true",
                        help="score O6 with `heap <pid>` after the closes (Debug only)")
    args = parser.parse_args()
    MUTANT = args.mutant
    binary = args.app or proof_app.binary()
    tree_copy.remove_tree(str(WORK))
    WORK.mkdir(parents=True)
    started = time.monotonic()
    print(f"#555 — {args.bound} documents open at once — {binary} — load "
          f"{os.getloadavg()[0]:.1f}" + (f" — MUTANT {MUTANT}" if MUTANT else ""), flush=True)
    v0()
    v1()
    scored = ["V0", "V1", "D0", "O1", "O2", "O3", "O4", "O5"] + (["O6"] if args.heap else [])
    log = WORK / "framejob.log"
    up = False
    if not AV_MOV.exists():
        why = f"the fixture is missing: {AV_MOV}"
    elif not Path(binary).exists():
        why = f"the app is not built: {binary}"
    else:
        launched = mcp.launch(str(binary), env=bounded.child_env(), log_path=str(log),
                              timeout=HARD + 60)
        up = launched.client is not None
        why = f"the app did not listen at {launched.socket_path}"
        try:
            if up:
                pid = launched.child.pid
                print(f"  instance PID {pid} at {launched.socket_path}", flush=True)
                try:
                    run_rows(App(launched.client, pid, args.call_seconds), args.bound,
                             args.only_kind, heap=args.heap)
                except Wedged as wedge:
                    why = f"the instance stopped answering: {wedge}"
                except Exception as error:  # a broken instrument is a FAIL, not an exit
                    why = f"the row could not run: {type(error).__name__}: {error}"
        finally:
            launched.stop()
            mcp.remove_scratch(launched.socket_path)
    for name in [row for row in scored if row.startswith("O")]:
        if name not in rows:
            check(name, False, why)
    found = complaints(log)
    check("D0", up and found == [], f"listening {up}; complaints {found[:5]}")
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)} in {time.monotonic() - started:.0f} s; load "
          f"{os.getloadavg()[0]:.1f}")
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
