#!/usr/bin/env python3
"""Issue batch B83 (#238) — `mcp.py`'s defaults guard, proved on a clone of the
built app, and the real build's own session measured.

    python3 tools/proof/defaults_proof.py [--app <Reelcut.app>] [--only ROWS]
    python3 tools/proof/defaults_proof.py --mutant no-compare|no-exit

No environment moves `UserDefaults`, so an instance a proof launches shares
`com.kgalligan.Reelcut` with the owner. `mcp.py` snapshots that domain by key
name when a socket is made, launched on or handed over, compares when the
session ends, and ENDS the script with status 3 and `mcp: DEFAULTS MOVED …`
last on stderr when a key outside AppKit's `NS*`/`Apple*` families moved and
no other Reelcut shares the domain (with one, it only prints). This proof
makes that happen on purpose, and never on the owner's domain.

**The clone.** `--app` (the Release build by default) is cloned to
`tools/proof/work/defaults-proof/Reelcut.app` (`cp -c -R`, else a copy) and
its `CFBundleIdentifier` replaced with `com.kgalligan.reelcut.defaults-proof`,
so its instances write that domain and none of the owner's. The one route to
an owner-visible write is `perform_menu_item`: `["View", "Snapping"]` writes
`ReelcutSnappingEnabled`. The real `com.kgalligan.Reelcut` domain is only
ever read (`defaults export`), and no value or digest is printed.

Each G row runs this script again as a `--child` that scores nothing and
ends `sys.exit(0)`; the parent scores its status, stdout and stderr.

- **C0** the clone is made, its domain removed, its bundle identifier reads
  back, and it comes up on a scratch socket with `perform_menu_item` in its
  catalog, no parity complaint and no owner-visible key moved.
- **G1** child `write` (`mcp.launch(clone)`, `new_project`, View ▸ Snapping,
  `defaults_moved` printed as JSON, stop, `remove_scratch`): the JSON holds
  `ReelcutSnappingEnabled`; status 3; stderr's last line is `DEFAULTS MOVED`
  naming the key and `none`.
- **G2** CONTROL, child `quiet` (`new_project`, `close_project`): status 0
  and no such line.
- **G3** child `write-no-remove`, which never calls `remove_scratch`:
  status 3, by the `atexit` handler finishing the record still held.
- **G5** child `write` while S2 is alive, a second instance of the clone the
  parent started itself by `Popen` on its own folder (no `mcp` record):
  status 0, and the line names S2's pid. Another Reelcut shares the domain,
  so the guard prints and does not fail.
- **G4** child `write-handed`, which only builds `MCP(S2's socket)`: status
  3, and the key is among `defaults_moved` at the first reading after the
  call. A script handed its socket is guarded by the record `MCP()` makes,
  and its exit is the one compare with no `stop()` in front of it.
- **R1** the REAL build, in this process: `mcp.launch`, `new_project`,
  `close_project`, stop, `remove_scratch`. No owner-visible key of
  `com.kgalligan.Reelcut` moved. If one did and another Reelcut shares the
  domain, one retry; then FAIL naming the keys and the pids.
- **R2** the real domain across C0 and the G rows: no owner-visible key
  moved (no retry).

**A write is a toggle, and only the first one may count.** View ▸ Snapping
writes the opposite of what the instance read when the project's window was
made; a toggle onto the value already stored would move nothing. So each
child toggles up to `TOGGLES` times, waiting up to `WAIT` seconds each, and
prints its record's domain, its owned pids, how many keys its first snapshot
held, whether `ReelcutSnappingEnabled` was among them, how long the session
took to open, and for each toggle whether and when the key showed. A key
that shows only at a later toggle FAILS its row (one that shows at none is
said to have shown at none), and G4 also fails when the first reading after
the call lacks the key, which is what a handed script exiting at once would
be compared on. The later toggles are an instrument,
never a retry: they say which cause it was. `owns pids []` or a domain that
is not the clone's is the record: `lsof` named no pid, or (a pid owned, the
app's domain) `ps` did not name that pid's executable; `mcp.py` says either
on stderr; `no snapshot` is the snapshot; the key `present`, toggle 1
not shown and toggle 2 shown at once is a toggle onto the stored value;
`absent` with toggle 1 not shown is a write that did not land; `first
reading late` with toggle 1 shown after some tenths is the guard reading
before the write was visible, and then the defect is the guard's. An
`opened in` over 30 s is an `lsof`, a `ps` or a `defaults export` that
expired.
Each row starts `[N s]`, the time since the row before it, and each G row
ends `session S s, stop T s, compare U s; child V s, the parent's lsof and
stop W s`: the child's `TIMES` line (to its last read of `defaults_moved`,
its `stop()`, its `remove_scratch`), then the child's wall and the parent's
work after it. G3's and G4's compare runs in the exit handler, inside the
child's wall. No row scores a time. The
proof README's B83 section has the three handed sessions that showed no
moved key and the runs since in which none did.

`--mutant` reaches the children by argv and must fail exactly its rows (then
MUTANT PASS, exit 0): `no-compare` (`proof_defaults.moved` answers `[]`) G1,
G3, G4, G5; `no-exit` (`mcp._exit_failed` is a no-op) G1, G3, G4.

At the end S2 is stopped, the work folder removed through
`tree_copy.remove_tree` (which unregisters the clone, #223) and the clone's
domain removed by `proof_defaults.remove_domain`. Only pids this script
started are stopped. Not a line of `make test`: it launches the app.
"""

import argparse
import json
import os
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402

sys.path.insert(0, HERE)
import mcp  # noqa: E402
import proof_defaults  # noqa: E402
import tree_copy  # noqa: E402

APP = os.path.join(ROOT, "build", "Build", "Products", "Release", "Reelcut.app")
WORK = os.path.join(HERE, "work", "defaults-proof")
CLONE = os.path.join(WORK, "Reelcut.app")
CLONE_DOMAIN = "com.kgalligan.reelcut.defaults-proof"
KEY = "ReelcutSnappingEnabled"
MARK = "mcp: DEFAULTS MOVED in "
ROWS = ["C0", "G1", "G2", "G3", "G5", "G4", "R1", "R2"]
EXPECTED = {"no-compare": {"G1", "G3", "G4", "G5"}, "no-exit": {"G1", "G3", "G4"}}
WALL_CHILD, WALL_COPY = 240, 300
TOGGLES, WAIT = 3, 3.0


def binary_of(app):
    return os.path.join(app, "Contents", "MacOS", "Reelcut")


def child_env():
    env = bounded.child_env()
    env.pop("ANTHROPIC_API_KEY", None)
    return env


# ---- the child -------------------------------------------------------------------

def child(kind, target, mutant):
    """Scores nothing and ends `sys.exit(0)`: the guard decides the status."""
    if mutant == "no-compare":
        proof_defaults.moved = lambda before, after: []
    if mutant == "no-exit":
        mcp._exit_failed = lambda lines: None
    started = None
    began = time.monotonic()
    if kind == "write-handed":
        socket_path = target
        client = mcp.MCP(socket_path, timeout=60)
    else:
        started = mcp.launch(target, env=child_env(), timeout=60)
        socket_path, client = started.socket_path, started.client
        print("SOCKET " + socket_path, flush=True)
    record = mcp._GUARDED.get(socket_path) or {}
    held = record.get("before")
    print(f"DOMAIN {record.get('domain')} ({'no snapshot' if held is None else len(held)} "
          f"keys before; {KEY} {'present' if KEY in (held or {}) else 'absent'}; owns pids "
          f"{sorted(record.get('own') or [])}; opened in {time.monotonic() - began:.1f} s)",
          flush=True)
    if client is None:
        print("NOT UP", flush=True)
    else:
        project = os.path.join(WORK, f"{kind}-{os.getpid()}.reelcut")
        client.call("new_project", path=project)
        if kind == "quiet":
            client.call("close_project", project=project, discard=True)
        else:
            first = False
            for toggle in range(1, TOGGLES + 1):
                client.call_with("perform_menu_item", {"path": ["View", "Snapping"],
                                                       "project": project})
                called = time.monotonic()
                shown = KEY in mcp.defaults_moved(socket_path)   # what an exit now would compare
                if toggle == 1:
                    first = shown
                while not shown and time.monotonic() < called + WAIT:
                    time.sleep(0.1)
                    shown = KEY in mcp.defaults_moved(socket_path)
                print(f"TOGGLE {toggle} " + (f"shown after {time.monotonic() - called:.1f} s"
                                             if shown else f"not shown in {WAIT:.0f} s"),
                      flush=True)
                if shown:
                    break
            print(f"FIRST {'at once' if first else 'late'}", flush=True)
            print(f"TOGGLES {toggle}", flush=True)
        print("MOVED " + json.dumps(mcp.defaults_moved(socket_path)), flush=True)
    asked = time.monotonic()
    if started is not None:
        started.stop()
    stopped = time.monotonic()
    if kind in ("write", "quiet"):
        mcp.remove_scratch(socket_path)
    print(f"TIMES session {asked - began:.1f} s, stop {stopped - asked:.1f} s, compare "
          f"{time.monotonic() - stopped:.1f} s", flush=True)
    print("DONE", flush=True)
    sys.exit(0)


# ---- the parent ------------------------------------------------------------------

def stop_pid(pid):
    """Terminates a pid this script's own child started, then kills it."""
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except OSError:
            return
        time.sleep(0.2)
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass


def run_child(kind, target, mutant):
    """{rc, expired, moved (list or None), done, stderr lines, marks}."""
    argv = [sys.executable, os.path.abspath(__file__), "--child", kind, target]
    if mutant:
        argv += ["--mutant", mutant]
    began = time.monotonic()
    ran = bounded.run(argv, WALL_CHILD, env=child_env())
    ended = time.monotonic()
    moved, done, socket_path, toggles, domain = None, False, None, None, None
    first, trail, times = None, [], None
    for line in ran["stdout"].splitlines():
        if line.startswith("MOVED "):
            try:
                moved = json.loads(line[len("MOVED "):])
            except json.JSONDecodeError:
                moved = None
        elif line.startswith("SOCKET "):
            socket_path = line[len("SOCKET "):]
        elif line.startswith("DOMAIN "):
            domain = line[len("DOMAIN "):]
        elif line.startswith("TOGGLES "):
            toggles = line[len("TOGGLES "):]
        elif line.startswith("FIRST "):
            first = line[len("FIRST "):]
        elif line.startswith("TIMES "):
            times = line[len("TIMES "):]
        elif line.startswith("TOGGLE "):
            trail.append("toggle " + line[len("TOGGLE "):])
        elif line == "DONE":
            done = True
    if socket_path:
        # The child's instance is in its own session: a child that expired or
        # never removed its scratch folder leaves both to its parent.
        holder = mcp.socket_pid(socket_path)
        if holder is not None:
            stop_pid(holder)
        mcp.remove_scratch(socket_path)
    lines = [line for line in ran["stderr"].splitlines() if line.strip()]
    return {"rc": ran["rc"], "expired": ran["expired"], "moved": moved, "done": done,
            "toggles": toggles, "domain": domain, "first": first, "trail": trail,
            "times": f"{times or 'no TIMES line'}; child {ended - began:.1f} s, the parent's "
                     f"lsof and stop {time.monotonic() - ended:.1f} s",
            "lines": lines, "marks": [line for line in lines if line.startswith(MARK)]}


def shape(answer):
    """A row's detail: the status, the moved names and the guard's lines."""
    last = answer["lines"][-1] if answer["lines"] else "(no stderr)"
    return (f"status {answer['rc']}" + (" (expired)" if answer["expired"] else "")
            + f"; guarded {answer['domain']}"
            + (f"; {', '.join(answer['trail'])}; first reading {answer['first']}"
               if answer["trail"] else "")
            + f"; defaults_moved {answer['moved']}; stderr's last line {last!r}"
            + f"; {answer['times']}")


def make_clone(app):
    """None, or why the clone could not be made."""
    tree_copy.remove_tree(WORK)
    os.makedirs(WORK)
    copied = bounded.run(["cp", "-c", "-R", app, CLONE], WALL_COPY)
    if copied["rc"] != 0 or copied["expired"] or not os.path.isdir(CLONE):
        tree_copy.remove_tree(CLONE)
        try:
            shutil.copytree(app, CLONE, symlinks=True)
        except OSError as error:
            return f"{app} could not be copied: {error}"
    info = os.path.join(CLONE, "Contents", "Info.plist")
    try:
        with open(info, "rb") as handle:
            raw = handle.read()
        loaded = plistlib.loads(raw)
        loaded["CFBundleIdentifier"] = CLONE_DOMAIN
        binary = raw.startswith(b"bplist")
        with open(info, "wb") as handle:
            plistlib.dump(loaded, handle,
                          fmt=plistlib.FMT_BINARY if binary else plistlib.FMT_XML)
    except Exception as error:
        return f"{info} could not be rewritten: {error}"
    return None


def start_s2():
    """(child, socket, log, None) or (None, None, None, reason): a second
    instance of the clone on this script's own folder, with no `mcp` record."""
    folder = tempfile.mkdtemp(prefix="rc-dp-")
    os.chmod(folder, 0o700)
    socket_path = os.path.join(folder, "agent.sock")
    if len(socket_path.encode()) > mcp.MAX_SOCKET_PATH:
        shutil.rmtree(folder, ignore_errors=True)
        return None, None, None, f"{socket_path} is over {mcp.MAX_SOCKET_PATH} bytes"
    log_path = os.path.join(folder, "reelcut.log")
    env = child_env()
    env["RC_AGENT_SOCKET"] = socket_path
    with open(log_path, "ab") as out:
        s2 = subprocess.Popen([binary_of(CLONE), "-ApplePersistenceIgnoreState", "YES"],
                              stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT,
                              start_new_session=True, env=env)
    if not mcp.wait_listening(log_path, socket_path, child=s2, seconds=60):
        return s2, socket_path, log_path, "S2 did not come up within 60 s"
    return s2, socket_path, log_path, None


def stop_s2(s2, socket_path):
    if s2 is not None and s2.poll() is None:
        s2.terminate()
        try:
            s2.wait(timeout=30)
        except subprocess.TimeoutExpired:
            s2.kill()
            s2.wait()
    if socket_path:
        folder = os.path.dirname(socket_path)
        if os.path.realpath(folder).startswith(os.path.realpath(tempfile.gettempdir()) + os.sep):
            shutil.rmtree(folder, ignore_errors=True)


def parity(log_path):
    try:
        with open(log_path, errors="replace") as handle:
            return [line.strip() for line in handle if "Reelcut: " in line]
    except OSError as error:
        return [f"the log could not be read: {error}"]


def real_session(app, index):
    """(the moved key names, None) or (None, reason): one session of the
    REAL build, in this process."""
    started = mcp.launch(binary_of(app), env=child_env(), timeout=60)
    reason = None
    try:
        if started.client is None:
            reason = "the real build did not come up within 60 s"
        else:
            project = os.path.join(WORK, f"r1-{index}.reelcut")
            started.client.call("new_project", path=project)
            started.client.call("close_project", project=project, discard=True)
    except Exception as error:
        reason = f"{type(error).__name__}: {error}"
    finally:
        started.stop()
    names = mcp.defaults_moved(started.socket_path)
    mcp.remove_scratch(started.socket_path)
    return (None, reason) if reason else (names, None)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--app", default=APP, help="the built Reelcut.app (Release)")
    parser.add_argument("--only", help="rows to run, comma-separated (C0 runs for any G row)")
    parser.add_argument("--mutant", choices=sorted(EXPECTED))
    parser.add_argument("--child", nargs=2, metavar=("KIND", "TARGET"), help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.child:
        child(args.child[0], args.child[1], args.mutant)
        return 0

    wanted = set(ROWS)
    if args.only and not args.mutant:
        wanted = {one.strip() for one in args.only.split(",") if one.strip()}
        unknown = sorted(wanted - set(ROWS))
        if unknown:
            print(f"--only names {unknown}; the rows are {ROWS}")
            return 2
    results = []
    clock = [time.monotonic()]

    def row(row_id, ok, detail):
        now = time.monotonic()
        results.append((row_id, bool(ok)))
        print(("  ok   " if ok else "  FAIL ")
              + f"{row_id} [{now - clock[0]:.0f} s] {detail}", flush=True)
        clock[0] = now

    app = os.path.abspath(args.app)
    if not os.path.isfile(binary_of(app)):
        print(f"instrument failure: {binary_of(app)} is missing — run `make app`")
        return 2

    s2, s2_socket = None, None
    try:
        before = proof_defaults.snapshot()
        needs_clone = bool(wanted - {"R1"})
        clone_up = False
        if needs_clone:
            # C0
            problems = []
            stale = proof_defaults.sharing_pids(CLONE_DOMAIN)
            if stale:
                problems.append(f"a Reelcut that may share {CLONE_DOMAIN} is running: {stale}")
            reason = make_clone(app) if not stale else "not made"
            if reason:
                problems.append(reason)
            else:
                left = proof_defaults.remove_domain(CLONE_DOMAIN)
                if left:
                    problems.append(f"the clone's domain was not removed: {left}")
                identifier = proof_defaults.bundle_domain(binary_of(CLONE))
                if identifier != CLONE_DOMAIN:
                    problems.append(f"the clone's bundle identifier reads {identifier!r}")
            detail = ""
            if not problems:
                started = mcp.launch(binary_of(CLONE), env=child_env(), timeout=60)
                try:
                    if started.client is None:
                        problems.append("the clone did not come up within 60 s")
                    else:
                        if "perform_menu_item" not in started.client.tools():
                            problems.append("the clone's catalog has no perform_menu_item")
                        complaints = parity(started.log_path)
                        if complaints:
                            problems.append(f"the parity check complained: {complaints[:2]}")
                finally:
                    started.stop()
                names = mcp.defaults_moved(started.socket_path)
                mcp.remove_scratch(started.socket_path)
                if proof_defaults.owner_visible(names):
                    problems.append("a bare launch moved "
                                    f"{proof_defaults.owner_visible(names)}")
                detail = (f"the clone at {os.path.relpath(CLONE, ROOT)} reads {CLONE_DOMAIN}, "
                          "its domain was removed, and it came up with perform_menu_item and "
                          f"no parity complaint; a bare launch moved {names}")
            clone_up = not problems
            row("C0", clone_up, "; ".join(problems) if problems else detail)

        def guard_row(row_id, kind, target, check):
            if row_id not in wanted:
                return
            if not clone_up:
                row(row_id, False, "not run: C0 failed")
                return
            answer = run_child(kind, target, args.mutant)
            problems = check(answer)
            row(row_id, not problems, shape(answer) + ("" if not problems
                                                      else " — " + "; ".join(problems)))

        def wrote(answer):
            problems = [] if answer["moved"] and KEY in answer["moved"] else [
                f"the JSON does not hold {KEY}"]
            trail = answer["trail"]
            if trail and " not shown " in trail[-1]:
                problems.append(f"{KEY} showed at none of the {len(trail)} toggles")
            elif answer["toggles"] not in (None, "1"):
                problems.append(f"{KEY} showed only at toggle {answer['toggles']}: the first "
                                "write was not seen")
            return problems

        def at_once(answer):
            return [] if answer["first"] == "at once" else [
                f"{KEY} was not among defaults_moved when perform_menu_item answered: a handed "
                "script that exits at once would not be failed"]

        def failed_last(answer):
            problems = []
            if answer["rc"] != mcp.DEFAULTS_EXIT:
                problems.append(f"status is not {mcp.DEFAULTS_EXIT}")
            last = answer["lines"][-1] if answer["lines"] else ""
            if not (last.startswith(MARK + CLONE_DOMAIN + ":") and KEY in last
                    and last.endswith("(other Reelcut pids: none)")):
                problems.append(f"stderr's last line is not DEFAULTS MOVED naming {KEY} and none")
            return problems

        guard_row("G1", "write", binary_of(CLONE), lambda a: wrote(a) + failed_last(a))

        def quiet(answer):
            problems = []
            if answer["rc"] != 0:
                problems.append("status is not 0")
            if answer["marks"]:
                problems.append("a DEFAULTS MOVED line was printed")
            if not answer["done"] or answer["moved"] is None:
                problems.append("the child did not finish its session")
            return problems

        guard_row("G2", "quiet", binary_of(CLONE), quiet)
        guard_row("G3", "write-no-remove", binary_of(CLONE),
                  lambda a: wrote(a) + failed_last(a))

        if clone_up and wanted & {"G5", "G4"}:
            s2, s2_socket, _log, reason = start_s2()
            if reason:
                for row_id in ("G5", "G4"):
                    if row_id in wanted:
                        row(row_id, False, f"not run: {reason}")
                wanted -= {"G5", "G4"}

        def shared(answer):
            problems = wrote(answer)
            if answer["rc"] != 0:
                problems.append("status is not 0")
            pid = str(s2.pid)
            named = [line for line in answer["marks"]
                     if KEY in line and pid in line.rsplit("(other Reelcut pids: ", 1)[-1]
                     .rstrip(")").split(", ")]
            if not named:
                problems.append(f"no DEFAULTS MOVED line names {KEY} and S2's pid {pid}")
            return problems

        guard_row("G5", "write", binary_of(CLONE), shared)
        guard_row("G4", "write-handed", s2_socket or "",
                  lambda a: wrote(a) + at_once(a) + failed_last(a))
        stop_s2(s2, s2_socket)
        s2, s2_socket = None, None
        after = proof_defaults.snapshot()

        if "R1" in wanted:
            os.makedirs(WORK, exist_ok=True)
            names, reason = real_session(app, 1)
            visible = proof_defaults.owner_visible(names or [])
            retried = False
            if reason is None and visible and proof_defaults.sharing_pids(proof_defaults.APP_DOMAIN):
                retried = True
                names, reason = real_session(app, 2)
                visible = proof_defaults.owner_visible(names or [])
            if reason:
                row("R1", False, f"the real build's session: {reason}")
            else:
                pids = proof_defaults.sharing_pids(proof_defaults.APP_DOMAIN)
                row("R1", not visible,
                    f"the real build, new_project and close_project: moved {names}; "
                    f"owner-visible {visible}" + ("; after one retry" if retried else "")
                    + f"; other Reelcut pids sharing {proof_defaults.APP_DOMAIN} now: "
                    f"{pids or 'none'}")

        if "R2" in wanted:
            if before is None or after is None:
                row("R2", False, f"`defaults export {proof_defaults.APP_DOMAIN} -` did not answer")
            else:
                names = proof_defaults.moved(before, after)
                visible = proof_defaults.owner_visible(names)
                row("R2", not visible,
                    f"{proof_defaults.APP_DOMAIN} ({len(after)} keys) across C0 and the G rows: moved "
                    f"{names}; owner-visible {visible}; other Reelcut pids sharing it now: "
                    f"{proof_defaults.sharing_pids(proof_defaults.APP_DOMAIN) or 'none'}")
    finally:
        stop_s2(s2, s2_socket)
        tree_copy.remove_tree(WORK)
        left = proof_defaults.remove_domain(CLONE_DOMAIN)
        print("cleanup: the work folder is " + ("STILL THERE" if os.path.lexists(WORK)
                                                else "gone")
              + f"; the clone's domain: {left or 'removed'}", flush=True)

    failed = {row_id for row_id, ok in results if not ok}
    print(f"passed {len(results) - len(failed)}/{len(results)}")
    if not args.mutant:
        return 1 if failed or left or os.path.lexists(WORK) else 0
    expected = EXPECTED[args.mutant]
    verdict = "MUTANT PASS" if failed == expected else "MUTANT FAIL"
    print(f"{verdict}: {args.mutant} failed {sorted(failed)}, expected {sorted(expected)}")
    return 0 if failed == expected else 1


if __name__ == "__main__":
    sys.exit(main())
