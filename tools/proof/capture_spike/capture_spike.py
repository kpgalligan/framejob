#!/usr/bin/env python3
"""The capture spike — road map 11, V1: the questions V2's `snapshot_ui` and
`perform_menu_item` cannot be designed without, measured.

  q1  the preview well under `cacheDisplay` in a live window, and which way of
      putting a still under the canvas overlay for a capture works;
  q2  sheets: put up by a menu item with the main run loop still free,
      captured, closed — and which menu items reach a modal run loop;
  q3  switching a live window's appearance, capturing and restoring;
  q4  `hasAmbiguousLayout` and "intrinsic width > frame" in an `-O` build.

The probe is `capture_probe.swift` compiled as `main.swift` with every file in
`app/Sources` but `main.swift` and the five `probe_*.swift` beside it, over
`harness/build.sh`'s swiftc line plus Release's `-O -wmo`. Each mode runs as
its own bounded child (Rule H, `graphics_spike/bounded.py`): the build 1200 s,
a mode 180 s, `modal` 60 s. Nothing here launches Reelcut.app or an MCP
server, and nothing is killed but the spike's own children.

    python3 tools/proof/capture_spike/capture_spike.py [--only q1,q2,q3,q4] [--rebuild]

Prints one line per row, `scores:` and `digest:`; writes
`work/capture_spike/answers.json`. Exit 0: every row has a state and no
instrument or control row failed; 1: one did; 2: a row has no state.
Run it with the terminal frontmost and nobody at the machine: the S and A
rows need the probe to become the active app.
"""

import argparse
import datetime
import hashlib
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROOF = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(PROOF, "..", ".."))
sys.path.insert(0, os.path.join(PROOF, "graphics_spike"))
sys.path.insert(0, PROOF)
sys.path.insert(0, HERE)
import bounded  # noqa: E402
import inventory  # noqa: E402
import rows as rowtable  # noqa: E402
from media_less_playback_probe import build_shader, console_locked  # noqa: E402

WORK = os.path.join(PROOF, "work", "capture_spike")
PROBE = os.path.join(WORK, "probe")
FIXTURES = os.path.join(WORK, "fixtures")
PNG = os.path.join(WORK, "png")
ANSWERS = os.path.join(WORK, "answers.json")
SOURCES = os.path.join(ROOT, "app", "Sources")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")
PLACEHOLDER = os.path.join(ROOT, "app", "Resources", "Blank.mp4")
TEMPLATES = os.path.join(ROOT, "graphic", "tests", "graphics")
REFERENCE = os.path.join(ROOT, "docs", "graphics-api.md")
ENTRY = os.path.join(HERE, "capture_probe.swift")
PROBE_FILES = [os.path.join(HERE, f) for f in (
    "probe_support.swift", "probe_well.swift", "probe_sheets.swift", "probe_appearance.swift",
    "probe_layout.swift")]
LIB = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
TICKS = 600_000

# ---------------------------------------------------------------------------
# Host and fixtures.


def host_facts():
    def out(argv):
        return bounded.run(argv, 60)["stdout"].strip()
    return {"macos": out(["sw_vers", "-productVersion"]), "build": out(["sw_vers", "-buildVersion"]),
            "hw_model": out(["sysctl", "-n", "hw.model"]), "console_locked": console_locked(),
            "date": datetime.date.today().isoformat()}


def write_package(name, canvas, clips):
    package = os.path.join(FIXTURES, f"{name}.reelcut")
    shutil.rmtree(package, ignore_errors=True)
    os.makedirs(package)
    project = {"version": 10, "canvas": canvas, "media": [],
               "tracks": [{"id": 1, "name": "Track 1"}], "clips": clips, "markers": [],
               "next_id": 6, "nests": []}
    with open(os.path.join(package, "project.json"), "w") as f:
        json.dump(project, f, indent=1)
    return package


def make_fixtures():
    os.makedirs(FIXTURES, exist_ok=True)
    canvas = {"width": 640, "height": 360, "fps": [30, 1], "background": [1.0, 0.0, 1.0, 1.0],
              "fit_new_clips": True}
    write_package("well", canvas, [{
        "id": 2, "track": 1, "start": 0, "duration": 3 * TICKS, "source": {"kind": "shape"},
        "video": {},
        "shape": {"kind": "rectangle", "width": 320.0, "height": 180.0, "stroke": None,
                  "fill": [1.0, 1.0, 0.0, 1.0], "arrow_start": False, "arrow_end": False,
                  "radius": 0.0, "from": [0.0, 1.0], "to": [1.0, 0.0], "gradient": None}}])
    content = "Every word here is timed"
    tokens = content.split()
    step = 3 * TICKS // len(tokens)
    words = [{"start": i * step, "end": (i + 1) * step - TICKS // 30} for i in range(len(tokens))]
    write_package("note", dict(canvas, background=[0.0, 0.0, 0.0, 1.0]), [{
        "id": 2, "track": 1, "start": 0, "duration": 3 * TICKS, "source": {"kind": "text"},
        "video": {},
        "text": {"content": content, "size": 48.0, "color": [1.0, 1.0, 1.0, 1.0],
                 "words": words, "word_style": {"mode": "highlight"}}}])


# ---------------------------------------------------------------------------
# The build (B0).


def build(force):
    os.makedirs(PROBE, exist_ok=True)
    binary = os.path.join(PROBE, "capture_probe")
    entry = os.path.join(PROBE, "main.swift")
    source = open(ENTRY).read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    fonts = os.path.join(PROBE, "Fonts")
    if not os.path.isdir(fonts) or os.path.getmtime(FONTS) > os.path.getmtime(fonts):
        shutil.rmtree(fonts, ignore_errors=True)
        shutil.copytree(FONTS, fonts)
    if not os.path.exists(os.path.join(PROBE, "Blank.mp4")):
        shutil.copy2(PLACEHOLDER, os.path.join(PROBE, "Blank.mp4"))
    templates = os.path.join(PROBE, "GraphicTemplates")
    shutil.rmtree(templates, ignore_errors=True)
    os.makedirs(templates)
    for name in sorted(os.listdir(TEMPLATES)):
        if name.endswith(".js"):
            shutil.copyfile(os.path.join(TEMPLATES, name), os.path.join(templates, name))
    shutil.copyfile(REFERENCE, os.path.join(PROBE, "GraphicsAPI.md"))
    shader, why = build_shader(PROBE)
    record = {"argv": [], "rc": None, "seconds": 0.0, "expired": False, "cached": False}
    if shader is None:
        return None, "shader: " + why, record
    if not os.path.exists(LIB):
        return None, f"{LIB} is missing — run `cd core && cargo build --release`", record
    swift = sorted(os.path.join(SOURCES, n) for n in os.listdir(SOURCES)
                   if n.endswith(".swift") and n != "main.swift")
    sdk = bounded.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
    argv = (["swiftc", "-O", "-wmo", "-D", "REELCUT_DEV_TOOLS", "-sdk", sdk,
             "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
             "-import-objc-header", os.path.join(ROOT, "app", "Bridging",
                                                  "Reelcut-Bridging-Header.h"),
             "-L", os.path.dirname(LIB), "-lreelcut_core"]
            + swift + PROBE_FILES + [entry, "-o", binary])
    record["argv"] = [a.replace(ROOT + "/", "") for a in argv[:16]] + [
        f"<{len(swift)} app/Sources files>", "<5 probe_*.swift>", "<probe>/main.swift", "-o",
        "<probe>/capture_probe"]
    stamp = os.path.join(PROBE, "sources.txt")
    listing = "\n".join(argv)
    fresh = (not force and os.path.exists(stamp) and open(stamp).read() == listing
             and os.path.exists(binary)
             and all(os.path.getmtime(f) < os.path.getmtime(binary)
                     for f in swift + PROBE_FILES + [entry, LIB]))
    if fresh:
        record.update(rc=0, cached=True)
        print(f"probe: {binary} (up to date)", flush=True)
        return binary, None, record
    if os.path.exists(binary):
        os.remove(binary)
    print("probe: building (-O -wmo, up to 1200 s)…", flush=True)
    built = bounded.run(argv, 1200)
    record.update(rc=built["rc"], seconds=built["seconds"], expired=built["expired"])
    if built["rc"] != 0 or not os.path.exists(binary):
        errors = [line for line in built["stderr"].splitlines() if ": error:" in line]
        tail = [line for line in built["stderr"].strip().splitlines()[-4:] if line.strip()]
        return None, (f"swiftc exited {built['rc']} (expired {built['expired']}): "
                      + " | ".join(errors[:6] or tail or ["(no output)"])), record
    with open(stamp, "w") as f:
        f.write(listing)
    print(f"probe: built in {built['seconds']:.0f} s", flush=True)
    return binary, None, record


def run_mode(binary, mode):
    png = os.path.join(PNG, mode)
    shutil.rmtree(png, ignore_errors=True)
    os.makedirs(png)
    seconds = rowtable.MODE_TIMEOUT.get(mode, 180)
    ran = bounded.run([binary, mode, FIXTURES, png], seconds, cwd=PROBE)
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            try:
                return json.loads(line[len("ANSWER "):]), None, ran["seconds"]
            except json.JSONDecodeError as error:
                return None, f"unreadable ANSWER: {error}", ran["seconds"]
    why = (f"expired after {seconds} s and was killed" if ran["expired"]
           else f"exit {ran['rc']}: {ran['stderr'].strip()[-240:]}")
    return None, why, ran["seconds"]


# ---------------------------------------------------------------------------
# Scoring.


def score(rid, kind, measured, window, host, failure):
    """(state, reason)."""
    if failure:
        return "fail", failure
    skip = rowtable.host_skip(rid, window, host)
    if skip:
        return "skip", skip
    if rid in rowtable.SCALE_DEPENDENT and window and window.get("scale") != 2:
        return "fail", (f"window at scale {window.get('scale')} though the host has "
                        f"{window.get('scale2_screens')} scale-2 screen(s)")
    if measured is None:
        return "fail", "row missing from the probe's answer"
    if "error" in measured:
        return "fail", "probe error: " + str(measured["error"])
    if rid == "L7" and measured.get("on_screen") is not True:
        return "skip", ("not on screen: no visible InspectorNoteLabel reading "
                        f"TextPane.wordStyleNote (found {measured.get('notes_found')})")
    try:
        ok, reason = rowtable.PREDICATES[rid](measured)
    except (KeyError, TypeError, IndexError) as error:
        return "fail", f"predicate: {type(error).__name__}: {error}"
    return ("pass" if ok else "fail"), reason


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="q1,q2,q3,q4")
    parser.add_argument("--rebuild", action="store_true")
    options = parser.parse_args()
    only = [q.strip() for q in options.only.split(",") if q.strip()]
    previous = {}
    if os.path.exists(ANSWERS):
        with open(ANSWERS) as f:
            previous = json.load(f)
    host = host_facts()
    print(f"host: macOS {host['macos']} ({host['build']}), {host['hw_model']}, console locked "
          f"{host['console_locked']}", flush=True)
    make_fixtures()
    binary, why, build_record = build(options.rebuild)
    b0 = ("pass" if binary else "fail",
          (f"built in {build_record['seconds']:.1f} s" if not build_record["cached"]
           else "up to date") + (f"; {why}" if why else "") if binary else why)

    modes = [m for m in rowtable.MODES
             if any(m in rowtable.QUESTION_MODES[q] for q in only)]
    answers, failures, windows, mode_seconds = {}, {}, {}, {}
    for mode in modes:
        if binary is None:
            failures[mode] = "probe did not build"
            continue
        print(f"mode {mode}…", flush=True)
        answer, why, seconds = run_mode(binary, mode)
        mode_seconds[mode] = seconds
        if answer is None:
            failures[mode] = f"probe {mode} gave no answer: {why}"
        else:
            answers[mode] = answer
            windows[mode] = answer.get("window", {})

    results = {}
    for rid, question, kind, mode, _text in rowtable.ROWS:
        if rid == "B0":
            # The build runs whatever `--only` says, so B0 is always scored.
            results[rid] = {"question": question, "kind": kind, "state": b0[0], "reason": b0[1],
                            "measured": build_record}
            continue
        if question not in only:
            if rid in previous.get("rows", {}):
                results[rid] = previous["rows"][rid]
            continue
        if rid in ("I1", "I2", "I3", "I4"):
            continue
        failure = failures.get(mode)
        measured = answers.get(mode, {}).get("rows", {}).get(rid)
        state, reason = score(rid, kind, measured, windows.get(mode), host, failure)
        results[rid] = {"question": question, "kind": kind, "state": state, "reason": reason,
                        "measured": measured if measured is not None else {}}

    table = previous.get("inventory_table", [])
    if "q2" in only:
        leaves = None
        if "menu" in answers:
            leaves = answers["menu"].get("rows", {}).get("I1", {}).get("leaves")
        checked, table = inventory.run(leaves)
        for rid in ("I1", "I2", "I3", "I4"):
            ok, reason, measured = checked[rid]
            if rid == "I1" and leaves is None:
                ok, reason = False, failures.get("menu", "the menu mode gave no leaves")
            results[rid] = {"question": "q2", "kind": "control" if rid == "I4" else "instrument",
                            "state": "pass" if ok else "fail", "reason": reason,
                            "measured": measured}

    print()
    counts = {"pass": 0, "fail": 0, "skip": 0}
    missing = []
    for rid, question, kind, _mode, text in rowtable.ROWS:
        row = results.get(rid)
        if row is None or row.get("state") not in counts:
            missing.append(rid)
            continue
        counts[row["state"]] += 1
        print(f"{rid} {row['state']} {rowtable.LETTER[kind]} — {row['reason']}")
    if "q2" in only:
        inventory.print_table(table)
    total = len(rowtable.ROWS)
    digest = hashlib.sha256("".join(
        f"{rid}={results[rid]['state']}\n" for rid in sorted(results)
        if rid not in missing).encode()).hexdigest()
    print(f"\nscores: {counts['pass']} pass, {counts['fail']} fail, {counts['skip']} skip of {total}")
    print(f"digest: {digest}")
    if mode_seconds:
        print("mode seconds: " + ", ".join(f"{m} {s:.1f}" for m, s in mode_seconds.items()))

    record = {"host": host, "build": {k: build_record[k] for k in ("argv", "rc", "seconds",
                                                                    "expired")},
              "rows": results, "inventory_table": table, "digest": digest,
              "windows": windows, "mode_seconds": mode_seconds}
    os.makedirs(WORK, exist_ok=True)
    with open(ANSWERS, "w") as f:
        json.dump(record, f, indent=1, sort_keys=True, ensure_ascii=False)

    if missing:
        print(f"SPIKE INCOMPLETE: {', '.join(missing)}")
        sys.exit(2)
    broken = [rid for rid, _q, kind, _m, _t in rowtable.ROWS
              if kind in ("instrument", "control") and results[rid]["state"] == "fail"]
    sys.exit(1 if broken else 0)


if __name__ == "__main__":
    main()
