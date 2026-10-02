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
server, and nothing is killed but the spike's own children and, on a
bundle-route timeout, the processes running the bundle's own executable
(`kill_bundled`).

**How a mode launches (issue batch B70, #132).** After the build, every run
assembles `work/capture_spike/CaptureProbe.app` (`bundle`): the binary as
`Contents/MacOS/capture_probe`, `Fonts/`, `Blank.mp4`, `default.metallib`,
`GraphicTemplates/` and `GraphicsAPI.md` in `Contents/Resources/`, an
`Info.plist`, signed ad hoc; a failed assembly fails B0 as `bundle: <why>`.
The default route, `--route bundle`, launches each mode through LaunchServices
(`open -n -W -F --stdout … --stderr … CaptureProbe.app --args <mode> …`), so
the probe is a real app that can become the active one; on its bound expiry
exactly the PIDs running `CaptureProbe.app/Contents/MacOS/capture_probe` (only
this spike launches that path) are killed. `--route direct` runs the bare
binary as before, which never becomes active on this host, so its S and A
rows skip with `host: probe not active`.

**A bundle-route run takes keyboard focus** and puts the probe's windows in
front for the length of the run (about 3 minutes in full), so run it only when
nobody is typing at the Mac. `--route direct` does not take focus.

    python3 tools/proof/capture_spike/capture_spike.py [--only q1,q2,q3,q4] [--rebuild]
                                                       [--route bundle|direct]
    python3 tools/proof/capture_spike/capture_spike.py --bundle-only [--rebuild]
    python3 tools/proof/capture_spike/capture_spike.py --activation [--rebuild]

Prints one line per row, `scores:` and `digest:`; writes
`work/capture_spike/answers.json`. Exit 0: every row has a state and no
instrument or control row failed; 1: one did; 2: a row has no state.

`--bundle-only` builds, assembles and checks the bundle (`verify_bundle`:
`plutil -lint`, `codesign --verify --strict`, the executable the built binary,
every resource present) and launches nothing: `bundle: ok <app>` or one
`bundle: FAIL <problem>` per problem, exit 0 or 1. `--activation` runs the
probe's `activation` mode once over `direct` (the CONTROL, the route that
never activated) and once over `bundle`, 60 s each, printing `activation
<route>: active <bool> in <ms|None> ms, key <bool>, visible windows <n>`; exit
0 when the bundle route answered active and key with exactly 1 visible window,
1 when it answered otherwise, 2 when a route gave no answer. Neither reads or
writes `answers.json`, and `activation` is not one of `rows.py`'s modes.
"""

import argparse
import datetime
import hashlib
import json
import os
import plistlib
import shutil
import signal
import struct
import sys
import tempfile

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
APP = os.path.join(WORK, "CaptureProbe.app")
BUNDLED = ("Fonts", "Blank.mp4", "default.metallib", "GraphicTemplates", "GraphicsAPI.md")
INFO = {"CFBundleIdentifier": "com.kgalligan.reelcut.captureprobe",
        "CFBundleExecutable": "capture_probe", "CFBundleName": "CaptureProbe",
        "CFBundlePackageType": "APPL", "NSPrincipalClass": "NSApplication",
        "LSMinimumSystemVersion": "26.0", "NSHighResolutionCapable": True}
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


# ---------------------------------------------------------------------------
# The bundle (#132): the probe as a LaunchServices app.


def bundle(binary):
    """`CaptureProbe.app` assembled afresh around `binary` and signed ad hoc.
    The app's path, or None and why."""
    try:
        shutil.rmtree(APP, ignore_errors=True)
        macos = os.path.join(APP, "Contents", "MacOS")
        resources = os.path.join(APP, "Contents", "Resources")
        os.makedirs(macos)
        os.makedirs(resources)
        shutil.copy2(binary, os.path.join(macos, "capture_probe"))
        for name in BUNDLED:
            source = os.path.join(PROBE, name)
            if os.path.isdir(source):
                shutil.copytree(source, os.path.join(resources, name))
            else:
                shutil.copy2(source, os.path.join(resources, name))
        with open(os.path.join(APP, "Contents", "Info.plist"), "wb") as f:
            plistlib.dump(INFO, f)
    except OSError as error:
        return None, f"assembly: {type(error).__name__}: {error}"
    signed = bounded.run(["codesign", "--force", "--sign", "-", APP], 120)
    if signed["rc"] != 0:
        return None, (f"codesign exited {signed['rc']} (expired {signed['expired']}): "
                      + signed["stderr"].strip()[-240:])
    return APP, None


def unsigned(path, folder):
    """The bytes of the Mach-O at `path` with its signature removed (on a
    scratch copy) and `__LINKEDIT`'s vmsize zeroed, or None. The vmsize is the
    one field `--remove-signature` leaves as the signature it removed rounded
    it: the linker's signature and the bundle's differ in size."""
    copy = os.path.join(folder, os.path.basename(os.path.dirname(path)) + "-"
                        + os.path.basename(path))
    shutil.copy2(path, copy)
    removed = bounded.run(["codesign", "--remove-signature", copy], 120)
    if removed["rc"] != 0:
        return None
    with open(copy, "rb") as f:
        data = bytearray(f.read())
    if len(data) < 32 or struct.unpack_from("<I", data, 0)[0] != 0xFEEDFACF:
        return None
    ncmds = struct.unpack_from("<I", data, 16)[0]
    offset = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, offset)
        if cmd == 0x19 and bytes(data[offset + 8:offset + 24]).rstrip(b"\0") == b"__LINKEDIT":
            data[offset + 32:offset + 40] = bytes(8)
        offset += size
    return bytes(data)


def verify_bundle(binary):
    """The bundle's problems, empty when it is sound."""
    problems = []
    plist = os.path.join(APP, "Contents", "Info.plist")
    linted = bounded.run(["plutil", "-lint", plist], 60)
    if linted["rc"] != 0:
        problems.append(f"plutil -lint: {(linted['stdout'] + linted['stderr']).strip()[-240:]}")
    else:
        with open(plist, "rb") as f:
            read = plistlib.load(f)
        if read != INFO:
            problems.append(f"Info.plist reads {read}, not {INFO}")
    verified = bounded.run(["codesign", "--verify", "--strict", APP], 120)
    if verified["rc"] != 0:
        problems.append(f"codesign --verify --strict exited {verified['rc']}: "
                        + verified["stderr"].strip()[-240:])
    inside = os.path.join(APP, "Contents", "MacOS", "capture_probe")
    if not os.path.isfile(inside):
        problems.append("Contents/MacOS/capture_probe is missing")
    else:
        # codesign rewrites the executable's own signature (the linker's ad-hoc
        # one becomes the bundle's), so the bytes compared are both files'
        # with their signatures removed (`unsigned`).
        with tempfile.TemporaryDirectory(dir=WORK) as scratch:
            a, b = unsigned(binary, scratch), unsigned(inside, scratch)
            if a is None or b is None:
                problems.append("codesign --remove-signature failed on a scratch copy, "
                                "or it is not a 64-bit Mach-O")
            elif a != b:
                problems.append("Contents/MacOS/capture_probe is not the built binary "
                                "(unsigned bytes differ)")
    resources = os.path.join(APP, "Contents", "Resources")
    for name in BUNDLED:
        source, copied = os.path.join(PROBE, name), os.path.join(resources, name)
        if not os.path.exists(copied):
            problems.append(f"Contents/Resources/{name} is missing")
        elif os.path.isdir(source):
            want, got = sorted(os.listdir(source)), sorted(os.listdir(copied))
            if want != got:
                problems.append(f"Contents/Resources/{name} holds {len(got)} entries, "
                                f"{PROBE}/{name} {len(want)}")
    return problems


def kill_bundled():
    """SIGKILL exactly the processes running the bundle's executable (only
    this spike launches that path). The PIDs killed."""
    found = bounded.run(["pgrep", "-f", os.path.join(APP, "Contents", "MacOS", "capture_probe")],
                        30)
    pids = [int(p) for p in found["stdout"].split() if p.isdigit()]
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    return pids



def read_text(path):
    """A file's text, or "" when it does not exist."""
    if not os.path.exists(path):
        return ""
    with open(path) as handle:
        return handle.read()

def run_mode(binary, mode, route="bundle", seconds=None):
    png = os.path.join(PNG, mode)
    shutil.rmtree(png, ignore_errors=True)
    os.makedirs(png)
    seconds = seconds or rowtable.MODE_TIMEOUT.get(mode, 180)
    if route == "direct":
        ran = bounded.run([binary, mode, FIXTURES, png], seconds, cwd=PROBE)
        stdout, stderr = ran["stdout"], ran["stderr"]
    else:
        out, err = os.path.join(PNG, f"{mode}.out"), os.path.join(PNG, f"{mode}.err")
        for stale in (out, err):
            if os.path.exists(stale):
                os.remove(stale)
        ran = bounded.run(["open", "-n", "-W", "-F", "--stdout", out, "--stderr", err, APP,
                           "--args", mode, FIXTURES, png], seconds)
        killed = kill_bundled() if ran["expired"] else []
        stdout = read_text(out)
        stderr = read_text(err) + ran["stderr"]
    for line in stdout.splitlines():
        if line.startswith("ANSWER "):
            try:
                return json.loads(line[len("ANSWER "):]), None, ran["seconds"]
            except json.JSONDecodeError as error:
                return None, f"unreadable ANSWER: {error}", ran["seconds"]
    if ran["expired"] and route != "direct":
        why = (f"expired after {seconds} s; `open` was killed and so were the bundle's "
               f"PIDs {killed}")
    else:
        why = (f"expired after {seconds} s and was killed" if ran["expired"]
               else f"exit {ran['rc']}: {stderr.strip()[-240:]}")
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


def bundle_only(rebuild):
    """`--bundle-only`: build, assemble, verify; launches nothing."""
    make_fixtures()
    binary, why, _record = build(rebuild)
    if binary is None:
        print(f"bundle: FAIL the probe did not build: {why}")
        return 1
    app, why = bundle(binary)
    if app is None:
        print(f"bundle: FAIL {why}")
        return 1
    problems = verify_bundle(binary)
    for problem in problems:
        print(f"bundle: FAIL {problem}")
    if not problems:
        print(f"bundle: ok {app}")
    return 0 if not problems else 1


def activation(rebuild):
    """`--activation`: the `activation` mode over `direct` (the CONTROL) and
    over `bundle`, 60 s each. Takes keyboard focus."""
    host = host_facts()
    print(f"host: macOS {host['macos']} ({host['build']}), {host['hw_model']}, console locked "
          f"{host['console_locked']}", flush=True)
    make_fixtures()
    binary, why, _record = build(rebuild)
    if binary is None:
        print(f"activation: the probe did not build: {why}")
        return 2
    app, why = bundle(binary)
    if app is None:
        print(f"activation: bundle: {why}")
        return 2
    answered = {}
    for route in ("direct", "bundle"):
        answer, why, _seconds = run_mode(binary, "activation", route=route, seconds=60)
        x0 = (answer or {}).get("rows", {}).get("X0")
        if x0 is None or "error" in x0:
            print(f"activation {route}: no answer — {why or (x0 or {}).get('error')}")
            continue
        answered[route] = x0
        print(f"activation {route}: active {x0.get('active')} in {x0.get('active_ms')} ms, "
              f"key {x0.get('key_is_editor')}, visible windows {x0.get('visible_windows')}")
    if len(answered) != 2:
        return 2
    b = answered["bundle"]
    return 0 if (b.get("active") is True and b.get("key_is_editor") is True
                 and b.get("visible_windows") == 1) else 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="q1,q2,q3,q4")
    parser.add_argument("--rebuild", action="store_true")
    parser.add_argument("--route", choices=("bundle", "direct"), default="bundle")
    parser.add_argument("--bundle-only", action="store_true")
    parser.add_argument("--activation", action="store_true")
    options = parser.parse_args()
    if options.bundle_only:
        sys.exit(bundle_only(options.rebuild))
    if options.activation:
        sys.exit(activation(options.rebuild))
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
    app, bundled = (bundle(binary) if binary else (None, None))
    if binary and app is None:
        b0 = ("fail", f"bundle: {bundled}")
    else:
        b0 = ("pass" if binary else "fail",
              (f"built in {build_record['seconds']:.1f} s" if not build_record["cached"]
               else "up to date") + (f"; {why}" if why else "")
              + f"; bundle {APP} assembled and signed" if binary else why)
    print(f"route: {options.route}", flush=True)

    modes = [m for m in rowtable.MODES
             if any(m in rowtable.QUESTION_MODES[q] for q in only)]
    answers, failures, windows, mode_seconds = {}, {}, {}, {}
    for mode in modes:
        if binary is None:
            failures[mode] = "probe did not build"
            continue
        if options.route == "bundle" and app is None:
            failures[mode] = f"probe bundle was not assembled: {bundled}"
            continue
        print(f"mode {mode}…", flush=True)
        answer, why, seconds = run_mode(binary, mode, route=options.route)
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
