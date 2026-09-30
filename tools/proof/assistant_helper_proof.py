#!/usr/bin/env python3
"""The helper and its build — road map 12 A1, part 2 (spec §11 AI-1, AI-7;
road map 12 §2).

  P0   the wiring, read from the source: project.yml has exactly one
       "Build Agent Helper" item, after "Copy Graphic Templates" and before
       `schemes:`, with `basedOnDependencyAnalysis: false` and
       `agent/build.sh" helper`; the Makefile's `typecheck` runs
       `/bin/sh agent/build.sh typecheck`, and `unexport ANTHROPIC_API_KEY`
       occurs once
  P1   never skips: `build.sh helper` and `build.sh typecheck` with a fresh
       empty HOME and PATH=/usr/bin:/bin each exit non-zero with a first
       stderr line `error: bun is not installed…` and leave no helper
       (skips only when bun sits at /opt/homebrew/bin or /usr/local/bin)
  P2r  the Release helper: present, `flags=0x10002(adhoc,runtime)`,
       entitlements exactly {allow-jit: true}, `codesign --verify --strict`
  P2d  the same for the Distribution helper, when --dist is given
  P3   the Release helper, with exactly HOME, TMPDIR and PATH, answers a
       `configure` (api_base at anthropic_fake.py) with `ready` and exits 0
       once stdin closes; the stand-in sees no POST and logs no failures
  P4   the §2 fields reach the API: core_tools, search_guide and
       compaction_instructions, read back from the stand-in's POSTs
  P5   the control: a scratch agent/ with a type error in main.ts fails
       `build.sh typecheck`, naming main.ts

    python3 tools/proof/assistant_helper_proof.py [--dist APP]
    python3 tools/proof/assistant_helper_proof.py --mutant skip-without-bun  # P1 alone: FAILS
    python3 tools/proof/assistant_helper_proof.py --mutant no-fields         # P4 alone: FAILS

Each mutant runs only its row, which must fail (exit 1; 0 when it
survives); a mutant whose row skipped on this host (bun at a fixed path P1
cannot hide) exits 2, the control not performed — and so, by rule R (issue
batch B13), does one whose scratch build.sh could not be made or whose row
was scored by a caught exception, printing `mutant <name>: the control could
not be performed — <why>`. An instrument that
cannot run is a scored FAIL, never an exit. No app is launched. No key is
read: every child's environment has `RC_ASSEMBLYAI_KEY` and
`ANTHROPIC_API_KEY` popped, the helper only ever gets `proof-key`, and every
`configure` sets `api_base` to the stand-in, so no row reaches
api.anthropic.com. Each child runs under a wall in its own process group,
and only that group is killed (rule H).
"""

import argparse
import json
import os
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402

WORK = os.path.join(HERE, "work", "assistant_helper")
AGENT = os.path.join(ROOT, "agent")
BUILD_SH = os.path.join(AGENT, "build.sh")
FAKE = os.path.join(HERE, "anthropic_fake.py")
HELPER = os.path.join("Contents", "Helpers", "reelcut-agent")
RELEASE_APP = os.path.join(ROOT, "build", "Build", "Products", "Release", "Reelcut.app")
MODEL = "claude-opus-5-5"
BUN_ERROR = "error: bun is not installed"
GUARD_EXIT = "  exit 1\n"
WALL_P1, WALL_READY, WALL_TURN, WALL_EXIT, WALL_P5 = 30, 20, 60, 5, 180


def child_env(extra=None):
    """`bounded.child_env` with `ANTHROPIC_API_KEY` popped as well; `pop`
    never binds the value to a name."""
    env = bounded.child_env(extra)
    env.pop("ANTHROPIC_API_KEY", None)
    return env


def run(argv, seconds, cwd=None, env=None):
    return bounded.run(argv, seconds, cwd=cwd, env=env or child_env())


def kill_group(child, grace=2.0):
    if child is None or child.poll() is not None:
        return
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(child.pid, sig)
        except ProcessLookupError:
            return
        try:
            child.wait(timeout=grace)
            return
        except subprocess.TimeoutExpired:
            continue


# ---------------------------------------------------------------------------
# P0: the wiring.


def p0():
    problems = []
    yml = open(os.path.join(ROOT, "project.yml")).read()
    items = [m.start() for m in re.finditer(r"^\s*- name: Build Agent Helper\s*$", yml, re.M)]
    templates = yml.find("- name: Copy Graphic Templates")
    schemes = yml.find("\nschemes:")
    if len(items) != 1:
        problems.append(f"{len(items)} 'Build Agent Helper' items, not 1")
    else:
        at = items[0]
        if not (0 <= templates < at):
            problems.append("the item is not after 'Copy Graphic Templates'")
        if not (0 <= at < schemes):
            problems.append("the item is not before `schemes:`")
        block = yml[at:schemes]
        if "basedOnDependencyAnalysis: false" not in block:
            problems.append("no `basedOnDependencyAnalysis: false`")
        if 'agent/build.sh" helper' not in block:
            problems.append("no `agent/build.sh\" helper`")
    makefile = open(os.path.join(ROOT, "Makefile")).read()
    recipe = re.search(r"^typecheck:\n((?:\t.*\n)+)", makefile, re.M)
    if not recipe or "\t/bin/sh agent/build.sh typecheck\n" not in recipe.group(1):
        problems.append("the Makefile's typecheck does not run `/bin/sh agent/build.sh typecheck`")
    unexports = len(re.findall(r"^unexport ANTHROPIC_API_KEY$", makefile, re.M))
    if unexports != 1:
        problems.append(f"`unexport ANTHROPIC_API_KEY` occurs {unexports} times, not once")
    if problems:
        return False, "; ".join(problems)
    return True, ("one 'Build Agent Helper' item between 'Copy Graphic Templates' and "
                  "`schemes:`, not dependency-analysed, running build.sh helper; the "
                  "Makefile's typecheck ends with build.sh typecheck; one unexport")


# ---------------------------------------------------------------------------
# P1: never skips.


def mutant_build_sh():
    """A scratch build.sh whose guard `exit 1` became `exit 0`. Answers
    (path, None) or (None, reason)."""
    text = open(BUILD_SH).read()
    count = text.count(GUARD_EXIT)
    if count != 1:
        return None, f"the guard's `exit 1` occurs {count} times in build.sh, not once"
    folder = os.path.join(WORK, "p1-mutant")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    path = os.path.join(folder, "build.sh")
    with open(path, "w") as f:
        f.write(text.replace(GUARD_EXIT, "  exit 0\n"))
    return path, None


def p1(script):
    for fixed in ("/opt/homebrew/bin/bun", "/usr/local/bin/bun"):
        if os.path.exists(fixed):
            return None, f"host: bun at a fixed path ({fixed})"
    details = []
    ok = True
    for mode in ("helper", "typecheck"):
        base = os.path.join(WORK, "p1", mode)
        shutil.rmtree(base, ignore_errors=True)
        home, target = os.path.join(base, "home"), os.path.join(base, "target")
        os.makedirs(home)
        os.makedirs(target)
        env = {"HOME": home, "PATH": "/usr/bin:/bin", "TARGET_BUILD_DIR": target,
               "CONTENTS_FOLDER_PATH": "Reelcut.app/Contents"}
        ran = run(["/bin/sh", script, mode], WALL_P1, env=env)
        first = (ran["stderr"].splitlines() or [""])[0]
        placed = os.path.exists(os.path.join(target, "Reelcut.app", HELPER))
        good = (not ran["expired"] and ran["rc"] not in (0, None)
                and first.startswith(BUN_ERROR) and not placed)
        ok = ok and good
        details.append(f"{mode}: exit {ran['rc']}{' (expired)' if ran['expired'] else ''}, "
                       f"first stderr {first[:40]!r}, helper placed {placed}")
    return ok, "; ".join(details)


# ---------------------------------------------------------------------------
# P2: the signed helper.


def p2(app):
    helper = os.path.join(app, HELPER)
    if not os.path.isfile(helper):
        return False, f"no helper at {helper}"
    shown = run(["codesign", "-dv", "--verbose=4", helper], 30)
    flags = re.search(r"flags=(\S+)", shown["stderr"])
    flags = flags.group(1) if flags else None
    ents = run(["codesign", "-d", "--entitlements", "-", "--xml", helper], 30)
    try:
        parsed = plistlib.loads(ents["stdout"].encode()) if ents["stdout"].strip() else None
    except Exception as error:  # noqa: BLE001 — an unreadable answer is the row's failure
        parsed = f"unparsable: {error}"
    verified = run(["codesign", "--verify", "--strict", helper], 30)
    ok = (flags == "0x10002(adhoc,runtime)"
          and parsed == {"com.apple.security.cs.allow-jit": True}
          and verified["rc"] == 0)
    return ok, (f"flags={flags}, entitlements {parsed}, verify --strict exit {verified['rc']}")


# ---------------------------------------------------------------------------
# The stand-in and the helper.


def start_fake(folder):
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    err = open(os.path.join(folder, "fake.stderr"), "w")
    child = subprocess.Popen([sys.executable, FAKE, "--dir", folder], env=child_env(),
                             stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=err,
                             text=True, start_new_session=True)
    err.close()
    line = child.stdout.readline().strip()
    if not line.startswith("port "):
        kill_group(child)
        raise RuntimeError(f"the stand-in printed {line!r}, not a port")
    return child, f"http://127.0.0.1:{int(line.split()[1])}"


def http(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method,
                                     headers={"content-type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, json.loads(response.read() or b"null")
    except urllib.error.HTTPError as error:
        return error.code, None


class Helper:
    """The helper under its walls, in its own session, with exactly HOME,
    TMPDIR and PATH=/usr/bin:/bin."""

    def __init__(self, path):
        env = {"HOME": os.environ.get("HOME", ""),
               "TMPDIR": os.environ.get("TMPDIR", "/tmp/"), "PATH": "/usr/bin:/bin"}
        self.events, self.errors = [], []
        self.child = subprocess.Popen([path], env=env, stdin=subprocess.PIPE,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                      start_new_session=True)
        self.readers = [threading.Thread(target=self._read, args=(self.child.stdout, True),
                                         daemon=True),
                        threading.Thread(target=self._read, args=(self.child.stderr, False),
                                         daemon=True)]
        for reader in self.readers:
            reader.start()

    def _read(self, stream, events):
        for raw in stream:
            line = raw.decode("utf-8", "replace").rstrip("\n")
            if not events:
                self.errors.append(line)
                continue
            try:
                self.events.append(json.loads(line))
            except ValueError:
                self.errors.append(f"(not JSON) {line}")

    def send(self, message):
        self.child.stdin.write((json.dumps(message) + "\n").encode())
        self.child.stdin.flush()

    def find(self, kind):
        return next((at for at, e in enumerate(self.events) if e.get("type") == kind), None)

    def wait_for(self, kind, seconds, after=0):
        """The index of the first `kind` event at or past `after`, or None."""
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            for at in range(after, len(self.events)):
                if self.events[at].get("type") == kind:
                    return at
            if self.child.poll() is not None:
                time.sleep(0.2)
                for at in range(after, len(self.events)):
                    if self.events[at].get("type") == kind:
                        return at
                return None
            time.sleep(0.05)
        return None

    def close(self):
        """Closes stdin and answers the exit status within the wall, or None."""
        try:
            self.child.stdin.close()
        except OSError:
            pass
        try:
            return self.child.wait(timeout=WALL_EXIT)
        except subprocess.TimeoutExpired:
            return None

    def kill(self):
        kill_group(self.child)
        for reader in self.readers:
            reader.join(timeout=2)


def configure(base, **fields):
    message = {"type": "configure", "api_key": "proof-key", "model": MODEL,
               "system": "Reelcut A1 part 2 proof.", "tools": [], "api_base": base,
               "settings": {"auto_compact_tokens": None, "clear_tool_results": False}}
    message.update(fields)
    return message


def posts(log):
    return [r for r in log.get("requests", [])
            if r.get("method") == "POST" and r.get("path", "").startswith("/v1/messages")]


def p3(app, fake, base):
    helper_path = os.path.join(app, HELPER)
    if not os.path.isfile(helper_path):
        return False, f"no helper at {helper_path}"
    http("POST", base + "/__control/scenario", {"replies": []})
    helper = Helper(helper_path)
    try:
        helper.send(configure(base, core_tools=[], search_guide="", compaction_instructions=""))
        ready = helper.wait_for("ready", WALL_READY)
        # The Models API lookup configure starts: wait for its answer so the
        # stand-in has seen it before the log is read.
        usage = helper.wait_for("context_usage", WALL_READY) if ready is not None else None
        status = helper.close()
    finally:
        helper.kill()
    _, log = http("GET", base + "/__control/log")
    log = log or {}
    gets = [r["path"] for r in log.get("requests", []) if r.get("method") == "GET"]
    ok = (ready is not None and status == 0 and not posts(log)
          and not log.get("failures") and bool(log))
    return ok, (f"ready {ready is not None}, context_usage {usage is not None}, exit {status}; "
                f"stand-in: {len(posts(log))} POSTs, GETs {gets}, failures "
                f"{log.get('failures')}; helper stderr {helper.errors[:2]}")


# ---------------------------------------------------------------------------
# P4: the §2 fields reach the API.


def system_text(body):
    system = body.get("system")
    if isinstance(system, str):
        return system
    if isinstance(system, list):
        return "".join(b.get("text", "") for b in system if b.get("type") == "text")
    return None


def p4(app, fake, base, no_fields):
    helper_path = os.path.join(app, HELPER)
    if not os.path.isfile(helper_path):
        return False, f"no helper at {helper_path}"
    reply = {"content": [{"type": "text", "text": "P4 stand-in reply."}],
             "stop_reason": "end_turn"}
    http("POST", base + "/__control/scenario", {"replies": [reply, reply]})
    schema = {"type": "object", "properties": {}}
    fields = {"system": "P4-SYSTEM",
              "tools": [{"name": "get_project", "description": "P4 get_project",
                         "inputSchema": schema},
                        {"name": "add_marker", "description": "P4 add_marker",
                         "inputSchema": schema}],
              "settings": {"auto_compact_tokens": 1, "clear_tool_results": False}}
    if not no_fields:
        fields.update(core_tools=["get_project"], search_guide="P4-GUIDE",
                      compaction_instructions="P4-COMPACTION")
    helper = Helper(helper_path)
    notes = []
    try:
        helper.send(configure(base, **fields))
        if helper.wait_for("ready", WALL_READY) is None:
            return False, f"no ready within {WALL_READY} s; stderr {helper.errors[:2]}"
        helper.send({"type": "send", "text": "P4 turn one."})
        finished = helper.wait_for("turn_finished", WALL_TURN)
        started = helper.find("compaction_started")
        notes.append(f"turn 1 finished {finished is not None}, "
                     f"compaction_started {started is not None}")
        _, log = http("GET", base + "/__control/log")
        if finished is not None and started is not None and len(posts(log or {})) < 2:
            # The SDK sends the summary request only on the next turn.
            helper.send({"type": "send", "text": "P4 turn two."})
            again = helper.wait_for("turn_finished", WALL_TURN, after=finished + 1)
            notes.append(f"a second send was needed; turn 2 finished {again is not None}")
        status = helper.close()
        notes.append(f"exit {status}")
    finally:
        helper.kill()
    _, log = http("GET", base + "/__control/log")
    log = log or {}
    sent = posts(log)
    problems = []
    if not sent:
        return False, "no POST reached the stand-in; " + "; ".join(notes)
    first = sent[0].get("body") or {}
    system = system_text(first)
    if system != "P4-SYSTEM\n\nP4-GUIDE":
        problems.append(f"first POST's system is {system!r}")
    tools = {t.get("name"): t for t in first.get("tools", [])}
    if sorted(tools) != ["add_marker", "get_project", "tool_search_tool_bm25"]:
        problems.append(f"first POST's tools are {sorted(tools)}")
    else:
        if "defer_loading" in tools["get_project"]:
            problems.append(f"get_project carries defer_loading "
                            f"{tools['get_project']['defer_loading']!r}")
        if tools["add_marker"].get("defer_loading") is not True:
            problems.append(f"add_marker's defer_loading is "
                            f"{tools['add_marker'].get('defer_loading')!r}")
    if len(sent) < 2:
        problems.append(f"only {len(sent)} POST(s): none after compaction_started")
    elif "P4-COMPACTION" not in json.dumps(sent[1].get("body")):
        problems.append("the POST after compaction_started does not carry P4-COMPACTION")
    if log.get("failures"):
        problems.append(f"stand-in failures {log['failures']}")
    detail = "; ".join(notes) + f"; {len(sent)} POSTs"
    if problems:
        return False, detail + " — " + "; ".join(problems)
    return True, (detail + " — system 'P4-SYSTEM\\n\\nP4-GUIDE', get_project up front, "
                  "add_marker deferred, the summary POST carries P4-COMPACTION, no failures")


# ---------------------------------------------------------------------------
# P5: the control.


def p5():
    scratch = os.path.join(WORK, "p5", "agent")
    shutil.rmtree(os.path.dirname(scratch), ignore_errors=True)
    shutil.copytree(AGENT, scratch, ignore=shutil.ignore_patterns("node_modules"))
    with open(os.path.join(scratch, "src", "main.ts"), "a") as f:
        f.write('const p5: number = "p5";\n')
    ran = run(["/bin/sh", os.path.join(scratch, "build.sh"), "typecheck"], WALL_P5)
    output = ran["stdout"] + ran["stderr"]
    named = [l for l in output.splitlines() if "main.ts" in l]
    ok = not ran["expired"] and ran["rc"] not in (0, None) and bool(named)
    return ok, (f"exit {ran['rc']}{' (expired)' if ran['expired'] else ''} in "
                f"{ran['seconds']} s; {named[0].strip()[:120] if named else 'main.ts not named'}")


# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--dist", help="a Distribution Reelcut.app, for P2d")
    parser.add_argument("--mutant", choices=["skip-without-bun", "no-fields"],
                        help="run one row against its made-to-fail variant; it must FAIL")
    args = parser.parse_args()
    os.makedirs(WORK, exist_ok=True)
    results = []  # (id, state, reason, instrument); state is "ok", "FAIL" or "skip"

    def score(row_id, ok, reason, *, instrument=False):
        state = "skip" if ok is None else ("ok" if ok else "FAIL")
        results.append((row_id, state, reason, instrument))
        print(f"{row_id} {state} — {reason}", flush=True)

    def guarded(row_id, function, *arguments):
        try:
            score(row_id, *function(*arguments))
        except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
            score(row_id, False, f"the instrument could not run: {type(error).__name__}: "
                                 f"{error}", instrument=True)

    def with_fake(row_id, function, *arguments):
        fake = None
        try:
            fake, base = start_fake(os.path.join(WORK, "fake-" + row_id.lower()))
            score(row_id, *function(*arguments, fake, base))
        except Exception as error:  # noqa: BLE001
            score(row_id, False, f"the instrument could not run: {type(error).__name__}: "
                                 f"{error}", instrument=True)
        finally:
            kill_group(fake)

    if args.mutant == "skip-without-bun":
        script, why = mutant_build_sh()
        if script is None:
            score("P1", False, why, instrument=True)
        else:
            guarded("P1", lambda: (lambda ok, r: (ok, "(scratch build.sh, guard exits 0) " + r))
                    (*p1(script)))
    elif args.mutant == "no-fields":
        with_fake("P4", lambda fake, base: (lambda ok, r: (ok, "(the three fields omitted) " + r))
                  (*p4(RELEASE_APP, fake, base, True)))
    else:
        guarded("P0", p0)
        guarded("P1", p1, BUILD_SH)
        guarded("P2r", p2, RELEASE_APP)
        if args.dist:
            guarded("P2d", p2, os.path.abspath(args.dist))
        else:
            score("P2d", None, "no --dist given")
        with_fake("P3", p3, RELEASE_APP)
        with_fake("P4", lambda fake, base: p4(RELEASE_APP, fake, base, False))
        guarded("P5", p5)

    scored = [r for r in results if r[1] != "skip"]
    passed = sum(1 for r in scored if r[1] == "ok")
    print(f"{passed}/{len(scored)}", flush=True)
    if args.mutant and not scored:
        # A mutant whose row skipped proved nothing either way: exit 2, never
        # the 0 of a clean run or the 1 of a caught mutant.
        print(f"mutant {args.mutant}: the control could not be performed — its row did not "
              "run on this host", flush=True)
        return 2
    broken = [r[0] for r in scored if r[3]]
    if args.mutant and broken:
        # Rule R (issue batch B13): a row scored where its own comparison did
        # not run is an instrument failure, never a caught mutant.
        print(f"mutant {args.mutant}: the control could not be performed — scored as "
              f"instrument failures: {', '.join(broken)}", flush=True)
        return 2
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
