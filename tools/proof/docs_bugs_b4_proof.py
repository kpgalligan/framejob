#!/usr/bin/env python3
"""Docs bugs, batch b4 (#477 #492 #500 #508 #509; spec §11 #477): the Export sheet, its queue row
and quitting during an export.

    python3 tools/proof/docs_bugs_b4_proof.py [--only A1,P1,…] [--app PATH] [--base-sources PATH]
                                              [--expect-red] [--mutant NAME]
    RC_PROOF_APP=<the frozen base app> python3 tools/proof/docs_bugs_b4_proof.py \
        --base-sources <a tree at the base>/app/Sources --expect-red
    RC_PROOF_APP=release python3 tools/proof/docs_bugs_b4_proof.py

The built app (`proof_app`'s choice, or `--app`) on a scratch `CFFIXED_USER_HOME` under
`work/docs-bugs-b4/`, launched with `-RCDevRampRenderHold 8`. `(c)` marks a CONTROL, which passes on
the base too; every other row is red on the frozen base app with `--base-sources` set to the base's
`app/Sources`, and `--expect-red` exits 0 only when that holds. The fixtures are made here, so ffmpeg
(with libx264) and ffprobe are needed at proof time. The app saves the two packages the probe opens:
`long60.framejob` (a 60 s 1080p clip with sound) and `ramp.framejob` (a 2 s clip of a 6 s file
with an action over [0, 1 s) ending at ×2), the ramp's renders removed from the probe's copy.

- App, over MCP: A1 `export h264` of the ramp project at once: every `running` poll with no file at
  the path reads `phase` "Preparing…" or "Measuring loudness…", and one reads "Preparing…". A2 (c)
  a `running` poll with the file there has no phase, and the job is `done`.
- Probe, `docs_bugs_b4_probe.swift` through `swift_build.build()` with `FRAMEJOB_DEV_TOOLS` and a
  `default.metallib` from this tree's shaders, the same source on the base and the fix, off-screen:
  P1 AV1 Speed, P2 WAV Bit depth, P3 WAV Stems, each moved with "Master" selected: the Preset popup
  reads "Custom". P4 (c) Quality and Loudness the same. H1 the sheet's hint says "keeps its true peak
  at or under −1 dBTP". S1 AV1 and H.264 progress sheets on `long60`, Cancel clicked past 3 %
  "Writing": every 10 ms sample until the button is live again reads "Stopping…". R1 one queued
  `h264` job of the ramp under `-RCDevRampRenderHold 6`, sampled straight after `enqueue` and every
  20 ms: every running sample with no file reads "Preparing… · N %" or "Measuring loudness… · N %".
  R2 (c) once the file exists a "Writing · N %" sample, then `completed`. T1 an H.264 sheet past 40 %
  "Writing": `applicationShouldTerminate` answers `.terminateCancel`, the window's frame and
  `NSApp.isActive` unchanged, the export finishes and ffprobe reads the file (exit 0, 60.000 s);
  on `.terminateNow` the probe exits as a quit would. T2 (c) asked after the sheet finished:
  `.terminateNow`. PB (c) the general pasteboard's change count is unchanged in every probe run.
- Z1 (c) `grep "Frame Job: "` on each launch's log prints nothing.

`--mutant NAME`: the named decision broken in a `tree_copy.py` copy of the tree, whose `app/Sources`
the probe is built from; the app under test only saves the packages. CAUGHT exits 1 when every named
row failed, SURVIVED exits 0, and a control that could not be performed (the copy did not build, an
anchor not found once) exits 2. An instrument that cannot run is a scored failure, never an exit.
"""

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/docs-bugs-b4"
HOME = WORK / "home"
FILES = WORK / "files"
LOGS = WORK / "logs"
PACKAGES = WORK / "packages"
OUT = WORK / "probe"
PROBE = HERE / "docs_bugs_b4_probe.swift"
SHADERS = ROOT / "app/Resources/Shaders"
CALL_BOUND = 300
JOB_BOUND = 900
PROBE_BOUND = 1500     # a 60 s 1080p write on a machine shared with other builds
SEC = 600000
PREPARING = "Preparing…"
MEASURING = "Measuring loudness…"
HINT = "keeps its true peak at or under −1 dBTP"

APP_ROWS = ["A1", "A2"]
SHEET_ROWS = ["P1", "P2", "P3", "P4", "H1"]
STOP_ROWS = ["S1"]
QUEUE_ROWS = ["R1", "R2"]
QUIT_ROWS = ["T1", "T2"]
PROBE_ROWS = SHEET_ROWS + STOP_ROWS + QUEUE_ROWS + QUIT_ROWS + ["PB"]
ROWS = APP_ROWS + PROBE_ROWS + ["Z1"]
CONTROLS = {"A2", "P4", "R2", "T2", "PB", "Z1"}

SPEED = "app/Sources/ExportSheetSpeed.swift"
BITS = "app/Sources/ExportSheetAudioBits.swift"
STEMS = "app/Sources/ExportSheetStems.swift"
PROGRESS = "app/Sources/ExportProgressSheetController.swift"
QUEUE = "app/Sources/ExportQueueController.swift"
DELEGATE = "app/Sources/AppDelegate.swift"
# name: (the rows it must turn red, the edits).
MUTANTS = {
    "speed-unmarked": (["P1"], [(
        SPEED, "        encoderSpeedChoice = speed\n        presetEdited()\n",
        "        encoderSpeedChoice = speed\n")]),
    "bits-unmarked": (["P2"], [(
        BITS, "        audioBitsChoice = bits\n        presetEdited()\n",
        "        audioBitsChoice = bits\n")]),
    "stems-unmarked": (["P3"], [(
        STEMS, "representedObject as? String\n        presetEdited()\n",
        "representedObject as? String\n")]),
    "stop-overwritten": (["S1"], [(PROGRESS, "        guard !isStopping else { return }\n", "")]),
    "no-preparing": (["R1"], [(
        QUEUE, "exporter?.phaseDescription ?? (exporter?.isWriting == true ? nil : Self.preparing)",
        "exporter?.phaseDescription")]),
    "preparing-always": (["R2"], [(
        QUEUE, "exporter?.isWriting == true ? nil : Self.preparing",
        "exporter?.isWriting == false ? nil : Self.preparing")]),
    "launch-unprepared": (["R1"], [(
        QUEUE, "        jobs[index].phase = Self.preparing\n", "        jobs[index].phase = nil\n")]),
    "quit-unguarded": (["T1"], [(
        DELEGATE, "        if ExportProgressSheetController.revealWriting() { return .terminateCancel }\n",
        "")]),
    "never-unregistered": (["T2"], [(PROGRESS, "        Self.writing.remove(self)\n", "")]),
}

results = {}
selected = set(ROWS)
logs = []


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'} {name}: {detail}", flush=True)


def attempt(names, body):
    """`body` when any of `names` is selected; an instrument that raises fails them, never exits."""
    if not selected & set(names):
        return
    try:
        body()
    except Exception as error:  # noqa: BLE001
        for name in names:
            check(name, False, f"the row could not run: {error!r}")


# ---- the fixtures -----------------------------------------------------------------------

def fixtures():
    """`repro/make_fixtures.sh`'s 60 s 1080p clip with sound, and a 6 s one for the ramp."""
    for name, seconds in (("long60.mov", 60), ("short6.mov", 6)):
        subprocess.run(
            ["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
             f"testsrc2=size=1920x1080:rate=30:duration={seconds}", "-f", "lavfi", "-i",
             f"sine=frequency=440:duration={seconds}", "-pix_fmt", "yuv420p", "-c:v", "libx264",
             "-preset", "ultrafast", "-c:a", "aac", "-shortest", str(FILES / name)],
            check=True, timeout=300)


def ffprobe(path):
    """(exit code, duration in seconds or None) of `path`."""
    done = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of",
                           "json", str(path)], capture_output=True, text=True, timeout=120)
    try:
        return done.returncode, float(json.loads(done.stdout)["format"]["duration"])
    except (ValueError, KeyError, TypeError):
        return done.returncode, None


# ---- the instance -----------------------------------------------------------------------

def start(binary, label, arguments=()):
    log = LOGS / f"{label}.log"
    logs.append(log)
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    launched = mcp.launch(str(binary), list(arguments), env=env, log_path=str(log),
                          timeout=CALL_BOUND)
    print(f"  {label}: instance PID {launched.child.pid}", flush=True)
    return launched


def parity():
    lines = []
    for log in logs:
        try:
            lines += [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
        except OSError:
            lines.append(f"{log} could not be read")
    check("Z1", bool(logs) and not lines,
          f"grep 'Frame Job: ' over {len(logs)} logs printed {lines[:3] or 'nothing'}")


def clip_project(client, path, media, length=None):
    """A new project at `path` holding `media` at 0 on the first track; its clip id."""
    client.call_with("new_project", {"path": path})
    m = client.call_with("import_media", {"project": path, "path": str(media)})["media"]
    track = client.call_with("get_project", {"project": path})["project"]["tracks"][0]["id"]
    client.call_with("add_clip", {"project": path, "media": m, "track": track, "at": 0})
    clip = client.call_with("get_project", {"project": path})["project"]["clips"][-1]
    if length is not None and clip["duration"] != length:
        client.call_with("trim_end", {"project": path, "clip": clip["id"], "to": length})
    return clip["id"]


def app_rows(client):
    """Saves both packages, the probe's ramp copy without renders, then A1 and A2."""
    long60 = str(PACKAGES / "long60.framejob")
    clip_project(client, long60, FILES / "long60.mov")
    client.call_with("save_project", {"project": long60})
    client.call_with("close_project", {"project": long60})
    ramp = str(WORK / "ramp.framejob")
    clip = clip_project(client, ramp, FILES / "short6.mov", length=2 * SEC)
    action = client.call_with("add_action", {"project": ramp, "clip": clip, "at": 0,
                                             "duration": SEC})["new_actions"][0]
    client.call_with("set_action_end", {"project": ramp, "clip": clip, "action": action,
                                        "patch": {"speed": 2}})
    client.call_with("save_project", {"project": ramp})
    copy = PACKAGES / "ramp.framejob"
    shutil.copytree(ramp, copy)
    shutil.rmtree(copy / "cache/ramp-audio", ignore_errors=True)
    packages = {"long60": long60, "ramp": str(copy)}
    if selected & set(APP_ROWS):
        attempt(APP_ROWS, lambda: export_rows(client, ramp))
    client.call_with("close_project", {"project": ramp, "discard": True})
    return packages


def export_rows(client, ramp):
    out = WORK / "held.mp4"
    answer = client.call_with("export", {"project": ramp, "preset": "h264", "path": str(out)})
    began = time.monotonic()
    polls = []
    while True:
        status = client.call_with("export_status", {"export_id": answer["export_id"]})
        polls.append((status.get("status"), status.get("phase"), out.exists()))
        if status.get("status") in ("done", "failed", "cancelled") or time.monotonic() - began > JOB_BOUND:
            break
        time.sleep(0.1)
    waiting = [phase for word, phase, there in polls if word == "running" and not there]
    writing = [phase for word, phase, there in polls if word == "running" and there]
    shown = sorted({str(phase) for phase in waiting})
    check("A1", waiting and all(p in (PREPARING, MEASURING) for p in waiting) and PREPARING in waiting,
          f"{len(waiting)} running polls with no file, phases {shown}")
    check("A2", any(p is None for p in writing) and polls[-1][0] == "done",
          f"{len(writing)} running polls with the file, phases {sorted({str(p) for p in writing})}; "
          f"last {polls[-1][0]}")


# ---- the probe --------------------------------------------------------------------------

def build_probe(sources):
    """(binary, None) or (None, why): a probe that will not build fails its rows."""
    OUT.mkdir(parents=True, exist_ok=True)
    airs = []
    for shader in sorted(SHADERS.glob("*.metal")):
        air = OUT / (shader.stem + ".air")
        step = subprocess.run(["xcrun", "-sdk", "macosx", "metal", "-c", str(shader), "-o", str(air)],
                              capture_output=True, text=True, timeout=300)
        if step.returncode:
            return None, f"metal {shader.name}: {step.stderr[:300]}"
        airs.append(str(air))
    step = subprocess.run(["xcrun", "-sdk", "macosx", "metallib", *airs, "-o",
                           str(OUT / "default.metallib")], capture_output=True, text=True, timeout=300)
    if step.returncode:
        return None, f"metallib: {step.stderr[:300]}"
    entry = OUT / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = OUT / "docs-bugs-b4-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8]))
    return binary, None


def probe(binary, mode, package, *extra):
    """The rows one probe run printed, by row name (a list each), and PB scored."""
    run = WORK / f"run-{mode}-{'-'.join(extra) or 'x'}"
    run.mkdir(parents=True, exist_ok=True)
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    done = subprocess.run([str(binary), mode, package, str(run), *extra], capture_output=True,
                          text=True, env=env, timeout=PROBE_BOUND, cwd=OUT, stdin=subprocess.DEVNULL)
    rows = {}
    for line in done.stdout.splitlines():
        if line.startswith("{"):
            answer = json.loads(line)
            rows.setdefault(answer["row"], []).append(answer)
    if done.returncode != 0 or "PB" not in rows:
        raise RuntimeError(f"{mode}: exit {done.returncode}, rows {sorted(rows)}: "
                           f"{(done.stdout + done.stderr)[-400:]}")
    pb = rows["PB"][0]
    check("PB", pb["unchanged"], f"{mode} {' '.join(extra)}: unchanged {pb['unchanged']}, changes "
                                 f"(probe seconds, count) {pb.get('changes')}")
    return rows


def sheet_rows(binary, packages):
    rows = probe(binary, "sheet", packages["long60"])
    for name in ("P1", "P2", "P3", "P4"):
        for answer in rows.get(name, []):
            ok = (answer["armed"] == "Master" and answer["from"] != answer["to"]
                  and answer["enabled"] and answer["preset_popup"] == "Custom")
            check(name, ok, f"{answer['format']} {answer['moved']} {answer['from']} → {answer['to']} "
                            f"with {answer['armed']!r}: Preset reads {answer['preset_popup']!r}")
        if name not in results:
            check(name, False, "the probe printed no row")
    hint = rows.get("H1", [{}])[0]
    check("H1", HINT in hint.get("text", ""), f"hint {hint.get('text', '')!r}")


def stop_rows(binary, packages):
    for preset in ("av1", "h264"):
        answer = probe(binary, "stop", packages["long60"], preset)["S1"][0]
        before = answer.get("before", {}).get("status", "")
        ok = (before.startswith("Writing") and answer.get("stopped") and answer.get("samples", 0) > 1
              and not answer.get("others"))
        check("S1", ok, f"{preset}: cancelled at {before!r} {answer.get('before', {}).get('percent')}, "
                        f"{answer.get('samples')} samples over {answer.get('stopping_ms')} ms, other "
                        f"lines {answer.get('others') or answer.get('error')}")


def queue_rows(binary, packages):
    answer = probe(binary, "queue", packages["ramp"], "-RCDevRampRenderHold", "6")["R"][0]
    samples = answer["samples"]
    waiting = [s["row_status"] for s in samples if s["state"] == "running" and not s["file_on_disk"]]
    writing = [s["row_status"] for s in samples if s["state"] == "running" and s["file_on_disk"]]
    starts = samples[0]["row_status"] if samples else None
    check("R1", waiting and all(r.startswith((PREPARING + " · ", MEASURING + " · ")) for r in waiting),
          f"first {starts!r}; with no file {waiting[:6]}")
    check("R2", any(r.startswith("Writing · ") for r in writing) and answer["final"] == "completed",
          f"with the file {writing[:4]}; final {answer['final']}")


def quit_rows(binary, packages):
    rows = probe(binary, "quit", packages["long60"])
    first = rows.get("T1", [{}])[0]
    if "error" in first or "reply" not in first:
        check("T1", False, f"the sheet never reached 40 %: {first}")
    else:
        finish = rows.get("T1-finish", [{}])[0]
        code, seconds = ffprobe(first["destination"])
        ok = (first["reply"] == "terminateCancel" and not first["exited"] and first["frame_same"]
              and first["active_same"] and not first["hidden"] and not first["miniaturized"]
              and finish.get("finished") and finish.get("reading", {}).get("status", "").startswith("Exported")
              and code == 0 and seconds is not None and abs(seconds - 60) < 0.05)
        check("T1", ok, f"{first['reply']} at {first['reading']['percent']} (exited {first['exited']}, "
                        f"frame same {first['frame_same']}, active same {first['active_same']}); "
                        f"finished {finish.get('finished')}; ffprobe exit {code}, {seconds} s")
    if "T2" in selected:
        asked = rows.get("T2") or probe(binary, "quitdone", packages["long60"]).get("T2", [])
        for answer in asked:
            check("T2", answer.get("reply") == "terminateNow",
                  f"after the finish: {answer.get('reply') or answer.get('error')}, "
                  f"{answer.get('reading', {}).get('status', '')[:50]!r}")
        if "T2" not in results:
            check("T2", False, "the probe printed no T2")


# ---- the run ----------------------------------------------------------------------------

def run(binary, sources):
    probe_binary, why = (None, None)
    if selected & set(PROBE_ROWS):
        probe_binary, why = build_probe(sources)
        if why:
            for row in sorted(selected & set(PROBE_ROWS)):
                check(row, False, f"the probe did not build: {why}")
    packages = None
    launched = start(binary, "main", ["-RCDevRampRenderHold", "8"])
    try:
        if launched.client is None:
            for row in sorted(selected - {"Z1"}):
                check(row, False, "the app did not listen")
            return

        def keep():
            nonlocal packages
            packages = app_rows(launched.client)

        attempt(sorted(selected - {"Z1"}), keep)
    finally:
        launched.stop()
    if probe_binary is None or packages is None:
        return
    if selected & set(SHEET_ROWS) or selected == {"PB", "Z1"}:
        attempt(SHEET_ROWS + ["PB"], lambda: sheet_rows(probe_binary, packages))
    attempt(STOP_ROWS, lambda: stop_rows(probe_binary, packages))
    attempt(QUEUE_ROWS, lambda: queue_rows(probe_binary, packages))
    attempt(QUIT_ROWS, lambda: quit_rows(probe_binary, packages))


def unperformed(row):
    """True when a failed row's instrument never ran: a red row must be red by behaviour."""
    return any(not ok and ("could not run" in detail or "did not build" in detail
                           or "did not listen" in detail or "were not made" in detail)
               for ok, detail in results.get(row, []))


def mutate(name):
    """(the copy, None) or (None, why): the tree copy with the mutant's edits."""
    made_copy, reason = tree_copy.make_copy(str(WORK / "mutant"), agent=False)
    if made_copy is None:
        return None, reason
    for path, anchor, replacement in MUTANTS[name][1]:
        target = Path(made_copy) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor[:60]!r}"
        target.write_text(text.replace(anchor, replacement))
    return Path(made_copy), None


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--app")
    parser.add_argument("--base-sources")
    parser.add_argument("--expect-red", action="store_true")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.mutant:
        selected = set(MUTANTS[args.mutant][0]) | {"Z1"}
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("Z1")
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    for folder in (FILES, HOME, LOGS, PACKAGES):
        folder.mkdir(parents=True)

    binary = Path(args.app) if args.app else None
    sources = Path(args.base_sources) if args.base_sources else ROOT / "app/Sources"
    if args.mutant:
        named = " ".join(MUTANTS[args.mutant][0])
        print(f"docs bugs b4 — the {args.mutant} MUTANT ({named} must FAIL)", flush=True)
        copy, why = mutate(args.mutant)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
        sources = copy / "app/Sources"
    if binary is None:
        binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    print(f"docs bugs b4 — the Export sheet, its queue row and quitting ({binary.name}; probe from "
          f"{sources})", flush=True)

    try:
        fixtures()
    except (OSError, subprocess.SubprocessError) as error:
        for row in sorted(selected):
            check(row, False, f"the fixtures were not made: {error!r}")
    else:
        run(binary, sources)
        parity()

    failed = [name for name in ROWS if name in results and not all(ok for ok, _ in results[name])]
    passed = [name for name in ROWS if name in results and name not in failed]
    print(f"\n{len(passed)}/{len(passed) + len(failed)} rows passed"
          + (f"; failed {failed}" if failed else ""), flush=True)
    if args.mutant:
        rows = MUTANTS[args.mutant][0]
        missing = [row for row in rows if row not in results]
        if missing:
            print(f"mutant {args.mutant}: the control could not be performed — {missing} never "
                  f"scored")
            return 2
        if any(unperformed(row) for row in rows):
            print(f"mutant {args.mutant}: the control could not be performed — the probe did not "
                  f"build")
            return 2
        caught = all(row in failed for row in rows)
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: "
              + ", ".join(f"{row} {'failed' if row in failed else 'passed'}" for row in rows),
              flush=True)
        return 1 if caught else 0
    if args.expect_red:
        never = [r for r in ROWS if r in selected and r not in results]
        wrong = ([r for r in failed if r in CONTROLS or unperformed(r)]
                 + [r for r in passed if r not in CONTROLS] + never)
        print("expected red, every row not marked (c) failing and every (c) passing: "
              + ("held" if not wrong else f"NOT held for {wrong}"), flush=True)
        return 1 if wrong else 0
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
