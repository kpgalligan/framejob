#!/usr/bin/env python3
"""Road map creator-jobs CU6 — record shortcuts: `record_screen`'s `keys` over MCP (Y5), and
the granted tier on a real recording in-process (Y3, Y4) (spec §11 CU-60, CU-62, CU-63).

    RC_PROOF_APP=release python3 tools/proof/cursor_keys_proof.py [--only Y5,Y3,…] [--app PATH]

Rows:
  Y5  over MCP on the app (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`), each call refused
      before anything records:
      Y5a `{seconds: 1, keys: "shortcuts", project: <a path naming nothing>}` refused starting
          with CU-3's sentence ("Input Monitoring is not granted to Frame Job. Turn it on in
          System Settings ▸ Privacy & Security ▸ Input Monitoring."), the grant read before
          `project`; when the project's sentence answers instead (the app's process holds the
          grant), printed as a note naming why, and Y5 stays scored on Y5b–Y5e.
      Y5b `{seconds: 1, source: "voice_over", keys: "shortcuts"}` refused naming `keys`
          ("With source voice_over, keys cannot be given — …").
      Y5c `{seconds: 1, source: "camera", keys: "off"}` refused naming `keys` ("With source
          camera, keys cannot be given — …").
      Y5d `{seconds: 1, keys: "all"}` refused with the vocabulary ("keys must be one of off,
          shortcuts (got \\"all\\").").
      Y5e `tools/list`: `record_screen`'s `keys` is a string with the enum ["off",
          "shortcuts"].
  Y3  `cursor_keys_proof.swift` records the main display in-process with `keys` `shortcuts`,
      its own window key and in front, and posts ⌘⇧F19 and five letters: the segment's cursor
      file holds exactly one shortcut in that span, `cmd+shift+f19` with code 80, and five
      typed marks there.
  Y4  … then five letters under `EnableSecureEventInput()` and two after it: no mark in the
      secure span, two after it.
      Y3 and Y4 are SKIPPED by name without Screen Recording, Input Monitoring or post access
      for this process, on a locked console, or when the probe cannot be the active
      application.
  Z1  the launch's log holds no `Frame Job: ` line.

Prints each check and `scores: P/N` over the rows scored, with each skip and its reason; exits
0 iff every scored row passed (skips are not failures), 1 otherwise.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/cursor-keys-proof"
ROWS = ["Y5", "Y3", "Y4", "Z1"]
WALL = 300
CU3 = ("Input Monitoring is not granted to Frame Job. Turn it on in System Settings ▸ "
       "Privacy & Security ▸ Input Monitoring.")

results = {}
skips = {}
selected = set(ROWS)


def check(row, ok, detail):
    if row not in selected:
        return
    results.setdefault(row, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {row} {detail}", flush=True)


def skip(row, why):
    if row in selected:
        skips[row] = why
        print(f"  skip {row} — {why}", flush=True)


def refusal(client, arguments):
    """The tool's refusal text, or None when it answered."""
    try:
        client.call_with("record_screen", arguments)
    except mcp.ToolError as error:
        return str(error).removeprefix("record_screen: ")
    return None


def y5(binary):
    started = mcp.launch(binary, [], seconds=60, timeout=300)
    try:
        if started.client is None:
            for row in ("Y5", "Z1"):
                check(row, False, f"the app did not bind its socket — {started.log_path}")
            return
        client = started.client
        if "Y5" in selected:
            nowhere = str(WORK / "no-such-project.framejob")
            text = refusal(client, {"seconds": 1, "keys": "shortcuts", "project": nowhere})
            if text is not None and text.startswith(CU3):
                check("Y5", True, f"Y5a refused with CU-3's sentence: {text!r}")
            elif text is not None and "Input Monitoring" not in text and "project" in text.lower():
                # A note, not a skip: Y5 stays scored on Y5b–Y5e (the review's nit).
                print(f"  note Y5 — Y5a not checked: the project's sentence answered — the app "
                      f"holds Input Monitoring: {text!r}", flush=True)
            else:
                check("Y5", False, f"Y5a: {text!r}")
            text = refusal(client, {"seconds": 1, "source": "voice_over", "keys": "shortcuts"})
            check("Y5", text == "With source voice_over, keys cannot be given — a voice-over "
                  "records the microphone alone.", f"Y5b: {text!r}")
            text = refusal(client, {"seconds": 1, "source": "camera", "keys": "off"})
            check("Y5", text == "With source camera, keys cannot be given — a camera recording "
                  "records the camera alone, at the camera's own format.", f"Y5c: {text!r}")
            text = refusal(client, {"seconds": 1, "keys": "all"})
            check("Y5", text == 'keys must be one of off, shortcuts (got "all").', f"Y5d: {text!r}")
            schema = client.schemas()["record_screen"]["inputSchema"]["properties"].get("keys", {})
            check("Y5", schema.get("type") == "string"
                  and schema.get("enum") == ["off", "shortcuts"],
                  f"Y5e: record_screen.keys {json.dumps({k: schema.get(k) for k in ('type', 'enum')})}")
    finally:
        started.stop()
        log = Path(started.log_path).read_text(errors="replace") if started.log_path else ""
        lines = [line for line in log.splitlines() if "Frame Job: " in line]
        check("Z1", not lines, f"{len(lines)} `Frame Job: ` line(s) in {started.log_path}")


def build():
    entry = WORK / "main.swift"
    shutil.copyfile(HERE / "cursor_keys_proof.swift", entry)
    binary = WORK / "cursor-keys-proof"
    sources = sorted(str(p) for p in (ROOT / "app/Sources").glob("*.swift")
                     if p.name != "main.swift")
    try:
        swift_build.build(sources=sources + [str(entry)], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + ("; ".join(error.diagnostics[:8]) or str(error))
    return binary, None


def probe(binary, *argv):
    try:
        done = subprocess.run([str(binary), *argv], capture_output=True, text=True, timeout=WALL)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {WALL} s"
    (WORK / f"stderr-{argv[0]}.txt").write_text(done.stderr)
    try:
        return json.loads(done.stdout), None
    except ValueError:
        return None, f"no answer (exit {done.returncode}): {done.stderr[-300:]}"


def within(times, span):
    return [t for t in times if span[0] <= t <= span[1]]


def granted(answer):
    """Y3 and Y4 over the recording's cursor file."""
    segments = answer.get("segments") or []
    path = (segments[0] if segments else {}).get("cursor_path")
    for row in ("Y3", "Y4"):
        check(row, answer.get("records_keys") is True and len(segments) == 1 and path
              and Path(path).exists(),
              f"recordsKeys {answer.get('records_keys')}, {len(segments)} segment(s), cursor file "
              f"{path!r} {answer.get('start_error') or answer.get('finish_error') or ''}".rstrip())
    if not path or not Path(path).exists():
        return
    body = json.loads(Path(path).read_text())
    keys = body.get("keys", {})
    shortcut = keys.get("shortcut", {})
    typed = keys.get("typed", {}).get("t", [])
    spans = answer.get("spans", {})
    y3 = spans.get("y3", [0, -1])
    hits = [(k, c) for t, k, c in zip(shortcut.get("t", []), shortcut.get("keys", []),
                                      shortcut.get("code", [])) if y3[0] <= t <= y3[1]]
    check("Y3", hits == [("cmd+shift+f19", 80)] and len(shortcut.get("t", [])) == 1,
          f"shortcuts in the span {hits}, in the file {shortcut.get('keys')}")
    check("Y3", len(within(typed, y3)) == 5 and sorted(keys.get("typed", {})) == ["t"],
          f"{len(within(typed, y3))} typed marks in the span {y3}, typed keys "
          f"{sorted(keys.get('typed', {}))}")
    secure, after = spans.get("secure", [0, -1]), spans.get("after", [0, -1])
    check("Y4", answer.get("secure_on") is True and answer.get("secure_off") is True,
          f"secure input on {answer.get('secure_on')}, off after {answer.get('secure_off')}")
    check("Y4", within(typed, secure) == [] and len(within(typed, after)) == 2,
          f"{len(within(typed, secure))} marks in the secure span {secure}, "
          f"{len(within(typed, after))} after it {after}")
    check("Y4", answer.get("front_while_posting") is True,
          f"the probe was the active application whenever it posted: "
          f"{answer.get('front_while_posting')}")


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)
    print(f"CU6 — record shortcuts ({proof_app.config()} build for Y5)", flush=True)
    if selected & {"Y5", "Z1"}:
        app = Path(args.app) if args.app else proof_app.binary()
        if app.suffix == ".app":
            app = proof_app.executable(app)
        y5(app)
    in_process = [r for r in ("Y3", "Y4") if r in selected]
    if in_process:
        binary, why = build()
        if binary is None:
            for row in in_process:
                check(row, False, f"the probe did not build — {why}")
        else:
            host, why = probe(binary, "host")
            if host is None:
                for row in in_process:
                    check(row, False, f"host — {why}")
            else:
                print(f"  host: {host}", flush=True)
                blocked = ("the console is locked" if host.get("locked") else
                           "CGPreflightScreenCaptureAccess() is false under this process's grant"
                           if not host.get("preflight") else
                           "CGPreflightListenEventAccess() is false: no Input Monitoring for this "
                           "process" if not host.get("listen") else
                           "CGPreflightPostEventAccess() is false: this process cannot post input"
                           if not host.get("post") else None)
                if blocked:
                    for row in in_process:
                        skip(row, blocked)
                else:
                    answer, why = probe(binary, "run", str(WORK))
                    if answer is None:
                        for row in in_process:
                            check(row, False, f"the recording did not run: {why}")
                    elif "skipped" in answer:
                        for row in in_process:
                            skip(row, answer["skipped"])
                    else:
                        (WORK / "answer.json").write_text(json.dumps(answer, indent=1))
                        granted(answer)
    failed = [row for row, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [row for row in results if row not in failed]
    print(f"\nscores: {len(passed)}/{len(results)}"
          + (f"; failed {failed}" if failed else "")
          + (f"; skipped {sorted(skips)}" if skips else ""))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
