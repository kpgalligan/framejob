#!/usr/bin/env python3
"""The cursor spikes — road map "creator-jobs" CU0b (CU-S1…CU-S4).

MEASURES what the cursor recorder is built on before any of it is: the capture APIs, grants,
clocks and the cursor's image (CU-S1), the mapping from global points to movie pixels and the
time anchor (CU-S2), whether dirty rects locate typing (CU-S3), and the cursor file's size and
speed (CU-S4). It judges by the rules in `designs/creator-jobs.md`'s "Every spike, with its
rule", pinned by CJ-7: R0 hashes each entry and refuses to run on a changed one. The answers
are in the road map's CU0b record, not here.

    python3 tools/proof/cursor_spike/cursor_spike.py [--only s1,s2,s3,s4] [--person] [--build-only]
    python3 tools/proof/cursor_spike/cursor_spike.py --selftest [--mutant NAME]

Exit 0: every requested row answered or skipped by name, whatever the verdict. Exit 1: an
instrument failure — B0, a probe crash or expiry, a still frame under the red floor, a
selftest row (so a mutant caught under `--mutant` exits 1), or `RULE CHANGED <id>` from R0, in
which case nothing is written. Exit 2: not performed (the staticlib or the codecs missing). A
skipped row is never a failure. Runs warp the pointer and show full-screen windows. Nothing
asks for a grant but `--person`'s A8/A11, and `tccutil` runs only there, only on the scratch
bundle's id. Everything written is under `tools/proof/work/cursor_spike/` (gitignored).
"""

import argparse
import json
import math
import os
import shutil
import statistics
import sys
import termios
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = ROOT / "tools/proof"
SPIKE = HERE / "cursor_spike"
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
sys.path.insert(0, str(SPIKE))
import bounded  # noqa: E402
import deciders  # noqa: E402

WORK = HERE / "work/cursor_spike"
BUILD = WORK / "build"
ANSWERS = WORK / "answers"
PROBE = BUILD / "cursor-spike-probe"
BUNDLE = WORK / "bundle/Cursor Spike.app"
BUNDLE_ID = "com.kgalligan.FrameJob.cursorspike"
ROADMAP = ROOT / "designs/creator-jobs.md"
LIBRARY = ROOT / "core/target/release/libframejob_core.a"
CODECS = ROOT / "build/codecs/stamp.json"
READER = SPIKE / "reader"
READER_BIN = READER / "target/release/cursor-spike-reader"
GROUPS = {"s1": "CU-S1", "s2": "CU-S2", "s3": "CU-S3", "s4": "CU-S4"}
MUTANTS = ["rule-unchecked", "clicks-95", "keys-accessibility-ok", "grant-iohid-first",
           "skipped-as-measured", "inherited-grant-counted", "caret-unflipped",
           "odd-window-ignored", "dirty-128", "body-or"]
PERSON = "a person at the machine (--person; JOB-29)"
LOCKED = ("the console is locked (CGSSessionScreenIsLocked): ScreenCaptureKit records the lock screen "
          "and nothing activates; owed to a run at the unlocked machine (JOB-29)")
WALL, BUILD_WALL = 120, 900
FAILURES = []

PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>{ident}</string>
<key>CFBundleName</key><string>{name}</string>
<key>CFBundleExecutable</key><string>{name}</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
</dict></plist>
"""


# ---- small plumbing -------------------------------------------------------------------------

def now():
    return time.strftime("%Y-%m-%d %H:%M:%S")


def out(argv, seconds=30):
    return (bounded.run(argv, seconds)["stdout"] or "").strip()


def fail(row, reason):
    FAILURES.append(f"{row}: {reason}")
    return {"skipped": f"instrument failure: {reason}", "failed": True}


def measured(tier, **fields):
    return dict(tier=tier, at=now(), **fields)


def write_if_changed(path, text):
    if not path.exists() or path.read_text() != text:
        path.write_text(text)


def host_facts():
    power = out(["pmset", "-g", "batt"]).splitlines()
    return {"os_build": out(["sw_vers", "-buildVersion"]), "os_version": out(["sw_vers", "-productVersion"]),
            "chip": out(["sysctl", "-n", "machdep.cpu.brand_string"]), "compute_device": "cpu",
            "power": power[0] if power else "?", "head": out(["git", "-C", str(ROOT), "rev-parse", "HEAD"]),
            "load": [round(x, 2) for x in os.getloadavg()]}


# ---- B0: the probe, the scratch bundle, the reader ---------------------------------------

def build():
    """Answers None, or the reason B0 failed."""
    import swift_build
    BUILD.mkdir(parents=True, exist_ok=True)
    entry = BUILD / "main.swift"
    write_if_changed(entry, (SPIKE / "cursor_spike_probe.swift").read_text())
    plist = BUILD / "cursor-spike-probe.plist"
    write_if_changed(plist, PLIST.format(ident=BUNDLE_ID + ".probe", name="cursor-spike-probe"))
    try:
        swift_build.build(sources=[entry, SPIKE / "cursor_spike_capture.swift"], output=PROBE, optimize=True,
                          link_args=["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker",
                                     "__info_plist", "-Xlinker", str(plist)],
                          link_inputs=[plist], timeout=BUILD_WALL)
    except swift_build.SwiftBuildFailed as error:
        return "the probe did not build: " + " | ".join(error.diagnostics[:6] or [str(error)])
    shutil.rmtree(BUNDLE, ignore_errors=True)
    (BUNDLE / "Contents/MacOS").mkdir(parents=True)
    shutil.copy2(PROBE, BUNDLE / "Contents/MacOS/Cursor Spike")
    (BUNDLE / "Contents/Info.plist").write_text(PLIST.format(ident=BUNDLE_ID, name="Cursor Spike"))
    signed = bounded.run(["codesign", "--force", "--sign", "-", "-o", "runtime", str(BUNDLE)], 60)
    if signed["rc"] != 0:
        return f"codesign exited {signed['rc']}: {signed['stderr'].strip()[-200:]}"
    cargo = bounded.run(["cargo", "build", "--release", "--offline", "--manifest-path",
                         str(READER / "Cargo.toml")], BUILD_WALL)
    if cargo["rc"] != 0 or not READER_BIN.exists():
        return f"the reader did not build: {(cargo['stderr'] or '').strip()[-400:]}"
    return None


def probe(mode, job, tag, wall=WALL):
    """(answer, None) or (None, why): a crash, an expiry or no JSON line."""
    ANSWERS.mkdir(parents=True, exist_ok=True)
    job_file = ANSWERS / f"{tag}.job.json"
    job_file.write_text(json.dumps(job, indent=1))
    ran = bounded.run([str(PROBE), mode, str(WORK), str(job_file)], wall, cwd=str(WORK))
    (ANSWERS / f"{tag}.stderr.txt").write_text(ran["stderr"] or "")
    if ran["expired"]:
        return None, f"{mode} ({tag}) ran past {wall} s and was killed"
    if ran["rc"] != 0:
        return None, f"{mode} ({tag}) exited {ran['rc']}: {(ran['stderr'] or '').strip()[-300:]}"
    for line in reversed((ran["stdout"] or "").splitlines()):
        if line.startswith("{"):
            answer = json.loads(line)
            (ANSWERS / f"{tag}.json").write_text(json.dumps(answer, indent=1))
            return answer, None
    return None, f"{mode} ({tag}) printed no JSON line"


def background(mode, job, tag, wall=WALL):
    ANSWERS.mkdir(parents=True, exist_ok=True)
    job_file = ANSWERS / f"{tag}.job.json"
    job_file.write_text(json.dumps(job, indent=1))
    return bounded.Background([str(PROBE), mode, str(WORK), str(job_file)], wall, cwd=str(WORK))


def finished(bg, tag):
    done = bg.finish()
    for _, line in reversed(done["lines"]):
        if line.startswith("{"):
            answer = json.loads(line)
            (ANSWERS / f"{tag}.json").write_text(json.dumps(answer, indent=1))
            return answer, None
    return None, f"{tag} exited {done['rc']} (expired {done['expired']}): {(done['stderr'] or '').strip()[-300:]}"


def bundle(job, tag, wall=60):
    """Opens the scratch bundle with `open -n -a` and waits, bounded, for its answer file."""
    answer_file, why = open_bundle(job, tag)
    return (None, why) if why else bundle_answer(answer_file, tag, wall)


def open_bundle(job, tag):
    """Opens the scratch bundle and returns at once: (answer file, None) or (None, why)."""
    ANSWERS.mkdir(parents=True, exist_ok=True)
    answer_file = ANSWERS / f"{tag}.bundle.json"
    answer_file.unlink(missing_ok=True)
    job_file = ANSWERS / f"{tag}.job.json"
    job_file.write_text(json.dumps(dict(job, out=str(answer_file)), indent=1))
    opened = bounded.run(["open", "-n", "-a", str(BUNDLE), "--args", str(job_file)], 30)
    if opened["rc"] != 0:
        return None, f"open exited {opened['rc']}: {opened['stderr'].strip()[-200:]}"
    return answer_file, None


def bundle_answer(answer_file, tag, wall=60):
    """Waits, bounded, for an opened bundle's answer file."""
    deadline = time.monotonic() + wall
    while time.monotonic() < deadline:
        if answer_file.exists():
            return json.loads(answer_file.read_text()), None
        time.sleep(0.2)
    return None, f"the scratch bundle ({tag}) wrote no answer within {wall} s"


# ---- CU-S1 ---------------------------------------------------------------------------------

OWN = [900.0, 160.0, 360.0, 260.0]
HELPER = [300.0, 160.0, 360.0, 260.0]
LISTEN_ROWS = [  # row, what the bundle listens with, the grant the row tests, secure input
    ("A1", "tap-mouse", "none", False),
    ("A2.none", "tap-keys", "none", False),
    ("A2.input-monitoring", "tap-keys", "input-monitoring", False),
    ("A2.accessibility", "tap-keys", "accessibility", False),
    ("A3.clicks", "monitor-mouse", "none", False),
    ("A3.keys.none", "monitor-keys", "none", False),
    ("A3.keys.input-monitoring", "monitor-keys", "input-monitoring", False),
    ("A3.keys.accessibility", "monitor-keys", "accessibility", False),
]


def inside(frame, x, y):
    return frame[0] <= x < frame[0] + frame[2] and frame[1] <= y < frame[1] + frame[3]


def plan(keys):
    """100 events into each window: the listener bundle's own first, then the helper's."""
    steps = []
    for half, frame in ((0.0, OWN), (2.5, HELPER)):
        cx, cy = frame[0] + frame[2] / 2, frame[1] + frame[3] / 2
        if keys:
            steps.append({"at": half, "kind": "click", "x": cx, "y": cy})
            for k in range(50):
                for kind in ("keyDown", "keyUp"):
                    steps.append({"at": half + 0.2 + k * 0.04, "kind": kind, "x": cx, "y": cy})
        else:
            for k in range(25):
                for j, kind in enumerate(("down", "drag", "up", "scroll")):
                    steps.append({"at": half + k * 0.09 + j * 0.02, "kind": kind,
                                  "x": cx - 60 + k * 4, "y": cy - 20 + j * 8})
    return steps


def listen_row(what, secure, tier, post):
    """One listener run: the bundle listens, the helper counts, the poster posts (or, in the
    person tier, the owner clicks and types). Answers the row."""
    keys = what.endswith("keys")
    start = time.time() + 5.0
    seconds = 6.0 if post else 20.0
    helper = background("target", {"frame_tl": HELPER, "start_wall": start, "seconds": seconds}, f"{what}-helper", 60)
    job = {"mode": "listen", "what": what, "secure": secure, "own_frame_tl": OWN, "start_wall": start,
           "seconds": seconds}
    # The listener is opened BEFORE anything is posted (the poster blocks until its plan is
    # done), and its answer's `ready_wall` must precede `start_wall`.
    answer_file, why = open_bundle(job, what)
    posted = None
    if why:
        pass
    elif post:
        posted, why = probe("post", {"start_wall": start, "plan": plan(keys)}, f"{what}-post", 60)
    else:
        print(f"  NOW: {'type keys' if keys else 'click, drag and scroll'} into the right-hand window for "
              f"{seconds / 2:.0f} s, then the left-hand one for {seconds / 2:.0f} s (click a window first "
              "to type into it)", file=sys.stderr)
    answer, why1 = bundle_answer(answer_file, what, 60) if answer_file else (None, None)
    helped, why2 = finished(helper, f"{what}-helper")
    if why or why1 or why2:
        return fail(what, why or why1 or why2)
    if posted and posted.get("outcome") == "skipped":
        return {"skipped": posted.get("reason") or "the poster skipped"}
    if (answer.get("ready_wall") or start) >= start:
        return fail(what, f"the listener was not up before start_wall (ready {answer.get('ready_wall')}, "
                          f"start {start:.3f})")
    events = [e for e in answer["events"] if (e[1] in ("keyDown", "keyUp")) == keys]
    own_counts, helper_counts = answer.get("own_counts") or {}, helped.get("counts") or {}
    kinds = ("keyDown", "keyUp") if keys else ("down", "up", "drag", "scroll")
    if keys:
        split = start + (2.5 if post else seconds / 2)
        own_got = sum(1 for e in events if e[0] < split)
        helper_got = len(events) - own_got
    else:
        own_got = sum(1 for e in events if inside(OWN, e[2], e[3]))
        helper_got = sum(1 for e in events if inside(HELPER, e[2], e[3]))
    numer, denom = answer.get("timebase") or [1, 1]
    deltas = {"ns": [], "mach": [], "uptime": []}
    for e in events:
        if e[8] == "tap":
            deltas["ns"].append(round((e[5] - e[4] / 1e9) * 1000, 3))
            deltas["mach"].append(round((e[5] - e[4] * numer / denom / 1e9) * 1000, 3))
        deltas["uptime"].append(round((e[6] - e[7]) * 1000, 3))
    return measured(tier, listener=answer["listener"], what=what, created=answer.get("created"),
                    secure_enabled=answer.get("secure_enabled"),
                    windows={"own": {"sent": sum(own_counts.get(k, 0) for k in kinds), "delivered": own_got},
                             "helper": {"sent": sum(helper_counts.get(k, 0) for k in kinds), "delivered": helper_got}},
                    delivered=len(events), deltas_ms=deltas)


def listener_rows(rows, tier, post, wanted=None):
    held, why = bundle({"mode": "grant", "step": "read"}, f"grant-read-{tier}", 60)
    if why:
        for rid, *_ in LISTEN_ROWS:
            rows[rid] = fail(rid, why)
        return
    grant = held["listener"]["grant"]
    for rid, what, needs, secure in LISTEN_ROWS:
        if wanted and needs not in wanted:
            continue
        rows[rid] = (listen_row(what, secure, tier, post) if grant == needs
                     else {"skipped": f"scratch bundle holds {grant}"})
    a1 = rows.get("A1")
    if a1 and not deciders.is_skipped(a1):
        rows["A6"] = measured(tier, listener=a1["listener"], deltas_ms=a1["deltas_ms"], from_row="A1")
    if not wanted or "input-monitoring" in wanted:  # a key tap sees keys only under Input Monitoring
        rows["A7"] = (listen_row("tap-keys", True, tier, post) if grant in ("input-monitoring", "both")
                      else {"skipped": f"scratch bundle holds {grant}"})


def group_s1(rows, host):
    locked = host["screen_locked"]
    a4, why = probe("a4", {}, "A4")
    if why:
        rows["A4.cost"] = fail("A4", why)
        rows["A4.warps"] = {"skipped": "A4's probe failed"}
    else:
        rows["A4.cost"] = measured("auto", median_us=a4["median_us"], p95_us=a4["p95_us"], max_us=a4["max_us"],
                                   calls=a4["calls"], nil_calls=a4["nil_calls"])
        rows["A4.warps"] = measured("auto", seen=a4["seen"], warps_seen=a4["warps_seen"], warps=a4["warps"],
                                    console_locked=locked)
    rows["A4.real"] = {"skipped": PERSON}
    thread, why = probe("a5thread", {}, "A5-thread", 30)
    rows["A5.thread"] = measured("auto", crashed=True, reason=why) if why else measured(
        "auto", crashed=False, returned=thread["returned"], nils=thread.get("nils"))
    rows["A5"] = {"skipped": PERSON}
    rows["A9.textedit"] = {"skipped": PERSON}
    rows["A8"] = rows["A11"] = {"skipped": PERSON}
    if locked:
        for rid in ["A5.own", "A9.helper", "A10", "A6", "A7"] + [r[0] for r in LISTEN_ROWS]:
            rows[rid] = {"skipped": LOCKED}
        return
    a5, why = probe("a5", {}, "A5-own")
    rows["A5.own"] = (fail("A5.own", why) if why else {"skipped": a5["reason"]} if a5["outcome"] == "skipped"
                      else measured("auto", cursors=a5["cursors"], median_ms=a5["median_ms"]))
    start = time.time() + 4.0
    schedule = {"start_wall": start, "period": 0.5, "phases": 20}
    helper = background("target", dict(schedule, hide_cycle=True, frame_tl=HELPER), "A9-helper", 60)
    seen, why = probe("a9", schedule, "A9-observer", 60)
    helped, why2 = finished(helper, "A9-helper")
    if why or why2:
        rows["A9.helper"] = fail("A9.helper", why or why2)
    elif helped["outcome"] == "skipped":
        rows["A9.helper"] = {"skipped": helped["reason"]}
    else:
        rows["A9.helper"] = measured("auto", trials=seen["trials"], helper=helped)
    a10, why = probe("a10", {}, "A10")
    rows["A10"] = (fail("A10", why) if why else {"skipped": a10["reason"]} if a10["outcome"] == "skipped"
                   else measured("auto", iou=a10["iou"], trials=a10["trials"]))
    if host["post_event"]:
        listener_rows(rows, "posted", post=True)
    else:
        reason = "the terminal cannot post events (CGPreflightPostEventAccess false); owed to the person tier"
        for rid, *_ in LISTEN_ROWS:
            rows[rid] = {"skipped": reason}
        rows["A6"] = rows["A7"] = {"skipped": reason}


def ask(question):
    print(f"\n{question}", file=sys.stderr)
    if sys.stdin.isatty():  # keys typed for a count window never pre-answer this prompt
        termios.tcflush(sys.stdin, termios.TCIFLUSH)
    try:
        return input("> ").strip().lower()
    except EOFError:
        return ""


def person_s1(rows):
    ask("A4: when you press Return, move the mouse in slow circles for 5 s.")
    a4, why = probe("a4", {"real": True, "seconds": 5}, "A4-real", 30)
    rows["A4.real"] = fail("A4.real", why) if why else measured("person", seen=a4["seen"], distinct=a4["distinct"])
    a5 = {}
    for target, where in (("ibeam", "over the text of a TextEdit document"), ("hand", "over a link in Safari"),
                          ("resize", "on a window's resize edge (the record only)")):
        ask(f"A5: hold the pointer still {where}, then press Return (3 s of samples).")
        got, why = probe("a5", {"person": target}, f"A5-{target}", 30)
        if why:
            rows["A5"] = fail("A5", why)
            break
        a5[target] = got
    else:
        rows["A5"] = measured("person", ibeam=a5["ibeam"]["hits"], hand=a5["hand"]["hits"],
                              median_ms=statistics.median(a5["ibeam"]["ms"] + a5["hand"]["ms"]),
                              resize=a5["resize"]["trials"])
    ask("A9: click into a TextEdit document, press Return here, then within 3 s follow the "
        "prompts: TYPE (keep typing) and MOVE (move the mouse), 2 s each.")
    start = time.time() + 3.0
    observer = background("a9", {"start_wall": start, "period": 2.0, "phases": 20}, "A9-textedit", 90)
    for k in range(20):
        time.sleep(max(0.0, start + k * 2.0 - time.time()))
        print("  " + ("TYPE" if k % 2 == 1 else "MOVE"), file=sys.stderr, flush=True)
    seen, why = finished(observer, "A9-textedit")
    rows["A9.textedit"] = fail("A9.textedit", why) if why else measured("person", trials=seen["trials"])
    for grant, how in (("none", "nothing: the runner resets Cursor Spike's Input Monitoring"),
                       ("input-monitoring", "Input Monitoring only (Privacy & Security ▸ Input Monitoring)"),
                       ("accessibility", "Accessibility only (remove Input Monitoring, add Accessibility)")):
        if grant == "none":
            bounded.run(["tccutil", "reset", "ListenEvent", BUNDLE_ID], 30)
        ask(f"A1–A3 with {how}. Grant it to {BUNDLE} if asked, then press Return.")
        listener_rows(rows, "person", post=False, wanted={grant})
    pair = {}
    a8 = None
    for api in ("cg", "iohid"):
        bounded.run(["tccutil", "reset", "ListenEvent", BUNDLE_ID], 30)
        ask(f"A11 ({api}): press Return; Cursor Spike will ask for Input Monitoring. Watch for a prompt.")
        go_file = ANSWERS / f"A11-{api}.go"  # opens both taps' count window (the owner's Return)
        go_file.unlink(missing_ok=True)
        job = {"mode": "grant", "api": api, "wait_grant": 120, "go": str(go_file), "wait_go": 150,
               "type_seconds": 8}
        answer_file = ANSWERS / f"A11-{api}.bundle.json"
        answer_file.unlink(missing_ok=True)
        job_file = ANSWERS / f"A11-{api}.job.json"
        job_file.write_text(json.dumps(dict(job, out=str(answer_file))))
        bounded.run(["open", "-n", "-a", str(BUNDLE), "--args", str(job_file)], 30)
        prompt = ask("Did a prompt appear? (y/n)") == "y"
        bounded.run(["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"], 30)
        listed = ask("Is Cursor Spike listed in Input Monitoring? (y/n)") == "y"
        ask("Turn Cursor Spike on in the pane (add it with + if it is not listed), press Return, then "
            "type steadily into TextEdit, not this terminal, until told to stop (about 10 s).")
        go_file.write_text(now())
        deadline = time.monotonic() + 150
        while time.monotonic() < deadline and not answer_file.exists():
            time.sleep(0.5)
        print("  STOP typing", file=sys.stderr)
        if not answer_file.exists():
            rows["A11"] = fail("A11", f"the scratch bundle wrote no answer for {api}")
            return
        got = json.loads(answer_file.read_text())
        if not got.get("go_seen"):
            rows["A11"] = fail("A11", f"the scratch bundle never saw the go file for {api}")
            return
        pair[api] = dict(got, prompt=prompt, listed=listed)
        a8 = a8 or {"before_tap_delivered": got["before_tap_delivered"], "plist_key_or_entitlement_needed":
                    not got["granted_within_wait"] or not (got["before_tap_delivered"] or got["after_tap_delivered"])}
    rows["A8"] = measured("person", **a8)
    rows["A11"] = measured("person", **pair)


# ---- CU-S2 ---------------------------------------------------------------------------------

def _m(name, p, frame, ppp, fixed):
    """Candidate `name`'s movie pixel for global point p, from one frame's SCStreamFrameInfo."""
    sr, cr = frame.get("screen_rect"), frame.get("content_rect")
    cs, sf = frame.get("content_scale"), frame.get("scale_factor")
    if name == "M3":
        return ((p[0] - fixed[0]) * ppp, (p[1] - fixed[1]) * ppp)
    k = ppp if name == "M1" else sf
    if sr is None or cr is None or cs is None or k is None:
        return None
    return ((p[0] - sr[0]) * cs * k + cr[0] * k, (p[1] - sr[1]) * cs * k + cr[1] * k)


def _m_inverse_x(name, px, frame, ppp, fixed):
    sr, cr = frame.get("screen_rect"), frame.get("content_rect")
    cs, sf = frame.get("content_scale"), frame.get("scale_factor")
    if name == "M3":
        return px / ppp + fixed[0]
    k = ppp if name == "M1" else sf
    if sr is None or cr is None or not cs or not k:
        return None
    return (px - cr[0] * k) / (cs * k) + sr[0]


def red_floor(picture, ppp, content_scale):
    """Half the red pixels the crosshair's 3 × 3 pt centre (or Separate's 24 pt marker) makes."""
    side = 3.0 if picture else 24.0
    return 0.5 * side * side * (ppp * (content_scale or 1.0)) ** 2


def tip_check(frames, picture, ppp):
    """The still frames under the red floor (an instrument failure, never a tip error)."""
    return [f for f in frames if (f.get("red_px") or 0) < red_floor(picture, ppp, f.get("content_scale"))]


def s2_row(answer, rid):
    picture = answer["config"] == "picture"
    ppp, fixed = answer["px_per_pt"], answer["sc_frame"]
    hot = answer.get("crosshair_hot") or [7.5, 7.5]
    off = (7.5 - hot[0], 7.5 - hot[1]) if picture else (0.0, 0.0)
    frames = answer["frames"]
    tip = {m: [] for m in deciders.MAPPINGS}
    for k, hold in enumerate(answer["holds"]):
        still = [f for f in frames if f.get("hold") == k]
        if not still:
            return fail(rid, f"hold {k} saw no complete frame")
        low = tip_check(still, picture, ppp)
        if low:
            return fail(rid, f"hold {k}: {len(low)} still frame(s) under the red floor, red_px "
                             f"{[f.get('red_px') for f in low][:6]} at pts {[round(f['pts'], 3) for f in low][:6]}")
        p = (hold[2] + off[0], hold[3] + off[1])
        for f in still:
            for m in deciders.MAPPINGS:
                got = _m(m, p, f, ppp, fixed)
                tip[m].append(9999.0 if got is None else round(math.hypot(got[0] - f["tip"][0], got[1] - f["tip"][1]), 3))
    best = min(deciders.MAPPINGS, key=lambda m: deciders.p95(tip[m]) or 9999.0)
    move = answer["move"]
    mid = (move["t0"] + move["t1"]) / 2
    info = min(frames, key=lambda f: abs(f["arrival"] - mid)) if frames else {}
    complete = sorted(f["pts"] for f in frames)
    e1 = answer.get("E1")
    anchors = {"E1": e1, "E2": next((t for t in complete if e1 is not None and t >= e1), None),
               "DisplayTime": next((f.get("display_time") for f in frames), None)}
    files = answer["file_frames"]
    first = files[0][0] if files else None
    floor = red_floor(picture, ppp, info.get("content_scale"))
    times = {a: [] for a in deciders.ANCHORS}
    lo, hi = move["x0"] + 30, move["x0"] + move["length"] - 30
    for pts, cx, cy, n in files:
        if n < floor:
            continue
        x = _m_inverse_x(best, cx, info, ppp, fixed)
        if x is None:
            continue
        x -= off[0]
        if not lo <= x <= hi:
            continue
        t_star = move["t0"] + (x - move["x0"]) / move["speed"]
        for a in deciders.ANCHORS:
            if anchors[a] is not None:
                times[a].append(round((anchors[a] + (pts - first) - t_star) * 1000, 3))
    return measured("auto", kind=answer["kind"], odd=answer["odd"], config=answer["config"],
                    configured=answer["configured"], px_per_pt=ppp, tip_err_px=tip,
                    tip_p95_px={m: deciders.p95(v) for m, v in tip.items()}, anchor_mapping=best,
                    time_err_ms=times, time_p95_ms={a: deciders.p95([abs(v) for v in t]) for a, t in times.items()},
                    frame_ms=answer["frame_ms"], frames=len(frames), idle=answer["idle"], file_frames=len(files),
                    frame_info=info)


def group_s2(rows, host, person=False):
    locked = host["screen_locked"]
    for source, (kind, odd, needs_person) in deciders.SOURCES.items():
        for config in deciders.CONFIGS:
            rid = deciders.s2_row(source, config)
            if needs_person != person:
                if needs_person:
                    rows[rid] = {"skipped": PERSON}
                continue
            if locked:
                rows[rid] = {"skipped": LOCKED}
                continue
            if needs_person:
                ask(f"{rid}: pick the instrument's grey window in the picker when it appears; press Return.")
            answer, why = probe("s2", {"source": source, "config": config}, rid.replace(".", "-"))
            if why:
                rows[rid] = fail(rid, why)
            elif answer["outcome"] in ("absent", "skipped"):
                rows[rid] = {answer["outcome"]: answer["reason"]}
            elif answer["outcome"] != "ok":
                rows[rid] = fail(rid, answer.get("reason"))
            else:
                rows[rid] = s2_row(answer, rid)
    if person:
        return
    for k in range(1, 11):
        rid = f"S2.still.{k}"
        if locked:
            rows[rid] = {"skipped": LOCKED}
            continue
        answer, why = probe("still", {"run": k}, f"S2-still-{k}")
        if why or answer["outcome"] == "failed":
            rows[rid] = fail(rid, why or answer.get("reason"))
        elif answer["outcome"] == "skipped":
            rows[rid] = {"skipped": answer["reason"]}
        elif answer.get("file_flip_pts") is None or answer.get("E1") is None:
            rows[rid] = fail(rid, "the flip or E1 was not seen")
        else:
            tf = answer["file_flip_pts"] - answer["file_first_pts"]
            h = answer["flip_after"]

            def err(anchor):
                return None if answer.get(anchor) is None else round((answer[anchor] + tf - h) * 1000, 3)
            rows[rid] = measured("auto", e1_err_ms=err("E1"), e2_err_ms=err("E2"),
                                 display_time_err_ms=err("DisplayTime"), flip_window_ms=round(
                                     (answer["flip_after"] - answer["flip_before"]) * 1000, 3),
                                 file_frames=answer["file_frames"], config=answer["config"])


# ---- CU-S3 and CU-S4 -----------------------------------------------------------------------

def group_s3(rows, host):
    ids = deciders.FIELD_ROWS["CU-S3"]["dirty"]
    if host["screen_locked"]:
        for rid in ids:
            rows[rid] = {"skipped": LOCKED}
        return
    answer, why = probe("s3", {}, "S3", 180)
    if why or answer["outcome"] == "failed":
        reason = why or answer.get("reason")
        FAILURES.append(f"S3: {reason}")
        for rid in ids:
            rows[rid] = {"skipped": f"instrument failure: {reason}", "failed": True}
        return
    if answer["outcome"] == "skipped":
        for rid in ids:
            rows[rid] = {"skipped": answer["reason"]}
        return
    for rid, burst in zip(ids, answer["bursts"]):
        row = dict(burst, px_per_pt=answer["px_per_pt"], display_frame_tl=answer["display_frame_tl"],
                   primary_height_pt=answer["primary_height_pt"])
        distance = deciders.burst_distance(row)
        rows[rid] = measured("auto", **row, distance_pt=None if distance is None else round(distance, 2))


def reader(argv, wall=300):
    ran = bounded.run([str(READER_BIN)] + argv, wall)
    for line in reversed((ran["stdout"] or "").splitlines()):
        if line.startswith("{"):
            answer = json.loads(line)
            if answer.get("outcome") == "ok":
                return answer, None
            return None, answer.get("reason")
    return None, f"the reader exited {ran['rc']} (expired {ran['expired']}): {(ran['stderr'] or '').strip()[-300:]}"


def group_s4(rows):
    folder = WORK / "cu-s4"
    made, why = reader(["generate", "--out", str(folder)])
    if why:
        rows["S4.json"] = rows["S4.binary"] = fail("S4", why)
        return False
    r4a, why = reader(["selftest", "--dir", str(folder)])
    rows["R4a"] = fail("R4a", why) if why else measured("auto", **r4a)
    if r4a and not r4a["r4a"]:
        FAILURES.append(f"R4a: the JSON and binary bodies' states differ ({r4a['mismatches']} of {r4a['compared']})")
    for body, name in (("json", "worst.json"), ("binary", "worst.bin")):
        got, why = reader(["measure", "--body", body, "--file", str(folder / name), "--runs", "5"])
        rows[f"S4.{body}"] = fail(f"S4.{body}", why) if why else measured("auto", **got, generated=made)
    return all(not rows[f"S4.{b}"].get("failed") for b in ("json", "binary"))


# ---- the run ---------------------------------------------------------------------------------

def decide(spike, rows):
    if spike == "CU-S4" and any(rows.get(r, {}).get("failed") or r not in rows for r in ("S4.json", "S4.binary")):
        return None, "VERDICT not measured (CU-S4's rows failed)"
    fields = deciders.DECIDERS[spike](rows)
    return fields, deciders.verdict_line(fields, spike)


def run_spike(spike, args, host, roadmap_text):
    folder = WORK / spike.lower()
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / "results.json"
    rows = {}
    if args.person:
        if not path.exists():
            print(f"{spike}: no results.json to merge the person tier into; run without --person first",
                  file=sys.stderr)
            return
        rows = json.loads(path.read_text())["rows"]
    started = time.time()
    if spike == "CU-S1":
        person_s1(rows) if args.person else group_s1(rows, host)
    elif spike == "CU-S2":
        group_s2(rows, host, person=args.person)
    elif spike == "CU-S3" and not args.person:
        group_s3(rows, host)
    elif spike == "CU-S4" and not args.person:
        group_s4(rows)
    fields, line = decide(spike, rows)
    results = dict(spike=spike, rule_sha256=deciders.rule_sha256(roadmap_text, spike), **host_facts(),
                   command="python3 tools/proof/cursor_spike/cursor_spike.py " + " ".join(sys.argv[1:]),
                   date=now(), seconds=round(time.time() - started, 1), host_grants=host,
                   rows=rows, verdict=line, fields=fields,
                   owed=sorted(k for k, v in (fields or {}).items() if v == deciders.OWED),
                   stops=deciders.stops(spike, fields or {}), failures=list(FAILURES))
    path.write_text(json.dumps(results, indent=1))
    print(f"\n{spike}: rule_sha256 {results['rule_sha256']}; {results['seconds']} s; results {path}")
    for rid, row in sorted(rows.items()):
        if not isinstance(row, dict):
            what = f"{len(row)} runs"
        elif "skipped" in row:
            what = "skipped: " + row["skipped"]
        elif "absent" in row:
            what = "absent: " + row["absent"]
        else:
            what = row.get("tier", "?")
        print(f"  {rid:28} {what}")
    print(line)


# ---- the selftest ----------------------------------------------------------------------------

def _bundle_run(grant, own=(100, 100), helper=(100, 100), launch="bundle"):
    return {"tier": "posted", "listener": {"launch": launch, "grant": grant},
            "windows": {"own": {"sent": own[0], "delivered": own[1]}, "helper": {"sent": helper[0], "delivered": helper[1]}}}


def _trials(signal_tells):
    shown = {"current_system_nil": False, "image_hash": "a"}
    hidden = {"current_system_nil": signal_tells, "image_hash": "a"}
    return [{"shown": shown, "hidden": hidden}] * 10


def _s1_full():
    pair = {"prompt": True, "listed": True, "after_tap_delivered": True}
    return {
        "A4.cost": {"median_us": 3.0}, "A4.warps": {"seen": True}, "A4.real": {"seen": True},
        "A1": _bundle_run("none"), "A3.clicks": _bundle_run("none", (100, 0)),
        "A2.input-monitoring": _bundle_run("input-monitoring"),
        "A3.keys.input-monitoring": _bundle_run("input-monitoring"),
        "A5": {"ibeam": [True] * 10, "hand": [True] * 9 + [False], "median_ms": 0.4},
        "A9.helper": {"trials": _trials(True)}, "A9.textedit": {"trials": _trials(True)},
        "A10": {"iou": [0.95] * 10},
        "A6": {"deltas_ms": {"ns": [-5.0] * 100, "mach": [3.0] * 100, "uptime": [2.0] * 100}},
        "A7": {"delivered": 0}, "A8": {"before_tap_delivered": True}, "A11": {"cg": pair, "iohid": pair},
    }


def _s2_row(kind, odd, m, t=4.0):
    errs = {"M1": [m[0]] * 8, "M2": [m[1]] * 8, "M3": [m[2]] * 8}
    return {"tier": "auto", "kind": kind, "odd": odd, "tip_err_px": errs,
            "time_err_ms": {"E2": [t] * 20, "E1": [t + 30] * 20, "DisplayTime": [t] * 20}, "frame_ms": 16.667}


def _s2_full():
    rows = {}
    for source, (kind, odd, _) in deciders.SOURCES.items():
        for config in deciders.CONFIGS:
            m = (2.5, 0.8, 3.0) if odd else (0.6, 0.7, 3.0)
            rows[deciders.s2_row(source, config)] = _s2_row(kind, odd, m)
    rows[deciders.s2_row("display-second", "picture")] = {"absent": "no second display attached"}
    rows[deciders.s2_row("display-second", "separate")] = {"absent": "no second display attached"}
    for k in range(1, 11):
        rows[f"S2.still.{k}"] = {"tier": "auto", "e1_err_ms": 12.0}
    return rows


def _burst(distance_pt):
    # A 2× display 1512 × 982 pt at (0, 0); caret Cocoa (100, 682, 2, 16) → centre (101, 292).
    return {"dirty_boxes_px": [[196 + 2 * distance_pt, 564, 12, 40]] * 3, "px_per_pt": 2.0,
            "display_frame_tl": [0.0, 0.0], "caret_rect_cocoa": [100.0, 682.0, 2.0, 16.0], "primary_height_pt": 982.0}


def _s4(json_bytes, parse, state, prepare):
    js = {"bytes": json_bytes, "parse_ms": [parse] * 5, "state_us_prepared_median": state, "prepare_ms": [prepare] * 5}
    return {"S4.json": js, "S4.binary": dict(js, bytes=json_bytes // 2)}


def selftest():
    results = []

    def check(name, ok, text):
        results.append((name, ok))
        print(f"  {'ok  ' if ok else 'FAIL'} {name}: {text}")

    text = ROADMAP.read_text()
    changed = text.replace("within 64 pt of the caret", "within 65 pt of the caret", 1)
    check("R0", changed != text and deciders.changed_rules(text) == []
          and deciders.changed_rules(changed) == ["CU-S3"],
          f"HEAD's rules {deciders.changed_rules(text)}; a one-character change {deciders.changed_rules(changed)}")

    full = deciders.verdict_line(deciders.decide_s1(_s1_full()), "CU-S1")
    want = ("VERDICT positions=poll clicks=tap keys=tap cursor_image=current-system hidden=recorded "
            "image_fallback=arrow event_clock=mach secure=withheld relaunch=not-needed grant_api=cg listed=yes")
    check("S1a", full == want, full)
    none = deciders.decide_s1({})
    check("S1b", set(none.values()) == {"owed"}, f"every row skipped: {sorted(set(none.values()))}")
    stops = dict(_s1_full(), **{"A1": _bundle_run("none", (100, 97), (100, 97)),
                                "A3.clicks": _bundle_run("none", (100, 97), (100, 97)),
                                "A2.input-monitoring": _bundle_run("input-monitoring", (100, 0), (100, 0)),
                                "A3.keys.input-monitoring": _bundle_run("input-monitoring", (100, 0), (100, 0)),
                                "A2.accessibility": _bundle_run("accessibility")})
    got = deciders.decide_s1(stops)
    check("S1c", (got["clicks"], got["keys"]) == ("STOP", "STOP"),
          f"97 % delivered: clicks={got['clicks']}; keys only under Accessibility: keys={got['keys']}")
    partial = dict(_s1_full(), **{"A4.real": {"skipped": PERSON}})
    got = deciders.decide_s1(partial)["positions"]
    check("S1d", got == "owed", f"A4's real moves skipped, cost and warps passing: positions={got}")
    terminal = dict(_s1_full(), **{"A1": [{"skipped": "scratch bundle holds input-monitoring"},
                                          _bundle_run("none", (100, 100), (100, 100), launch="terminal")]})
    got = deciders.decide_s1(terminal)["clicks"]
    check("S1e", got == "owed", f"a terminal-run A1 at 200/200 beside a skipped bundle row: clicks={got}")

    got = deciders.decide_s2(_s2_full())
    want2 = {"mapping_display": "M1", "mapping_window": "M2", "separate": "pass", "anchor": "E2", "e1_still_p95_ms": 12.0}
    check("S2a", got == want2, deciders.verdict_line(got, "CU-S2") + " (M1 fails only the 1001 × 701 row)")
    picked = dict(_s2_full(), **{deciders.s2_row("window-picked", "picture"): {"skipped": PERSON}})
    got = deciders.decide_s2(picked)["mapping_window"]
    check("S2b", got == "owed", f"the picked window skipped, M2 passing the rest: mapping_window={got}")
    bad = _s2_full()
    for rid, row in bad.items():
        if rid.startswith("S2.display") and "tip_err_px" in row:
            bad[rid] = dict(_s2_row("display", False, (4.0, 4.0, 4.0), t=40.0))
    got = deciders.decide_s2(bad)
    check("S2c", got["mapping_display"] == "STOP" and got["anchor"] == "none" and got["separate"] == "fail",
          deciders.verdict_line(got, "CU-S2") + " (no candidate passes displays)")
    got = deciders.decide_s2({})
    check("S2d", set(got.values()) == {"owed"}, f"every row skipped: {deciders.verdict_line(got, 'CU-S2')}")

    dirty = deciders.dirty_centre_pt((196, 560, 12, 40), 2.0, (0.0, 0.0))
    caret = deciders.caret_centre_pt((100, 682, 2, 16), 982.0)
    distance = deciders.burst_distance(_burst(0))
    check("S3a", dirty == (101.0, 290.0) and caret == (101.0, 292.0) and distance is not None and distance <= 64,
          f"dirty box px (196, 560, 12, 40) → {dirty}; caret Cocoa (100, 682, 2, 16) → {caret}; {distance} pt apart")
    bursts = {f"S3.burst.{k}": _burst(2 if k <= 8 else 100) for k in range(1, 11)}
    got = deciders.decide_s3(bursts)
    check("S3b", got == {"dirty": "not-stored", "bursts_within": "8/10"}, deciders.verdict_line(got, "CU-S3"))
    got = deciders.decide_s3({})
    check("S3c", got["dirty"] == "owed", deciders.verdict_line(got, "CU-S3") + " (every burst skipped)")

    big = deciders.decide_s4(_s4(30_000_000, 120.0, 3.0, 400.0))
    small = deciders.decide_s4(_s4(10_000_000, 120.0, 3.0, 1500.0))
    check("S4a", (big["body"], small["body"], small["smoothing"]) == ("binary", "json", "per-60s-window"),
          f"30 MB → {big['body']}; 10 MB → {small['body']}, prepare 1.5 s → {small['smoothing']}")

    still = [{"red_px": 40, "content_scale": 1.0}, {"red_px": 3, "content_scale": 1.0}]
    low = tip_check(still, True, 2.0)
    check("T1", len(low) == 1 and low[0]["red_px"] == 3,
          f"floor at 2 px/pt {red_floor(True, 2.0, 1.0)}: frames under it {[f['red_px'] for f in low]}")

    built = bounded.run(["cargo", "build", "--release", "--offline", "--manifest-path", str(READER / "Cargo.toml")], BUILD_WALL)
    if built["rc"] != 0:
        check("R4a", False, f"the reader did not build: {(built['stderr'] or '').strip()[-200:]}")
    else:
        folder = WORK / "selftest"
        made, why = reader(["generate", "--out", str(folder)])
        got, why = (reader(["selftest", "--dir", str(folder)]) if not why else (None, why))
        check("R4a", bool(got and got["r4a"]), f"JSON against binary states at 100 seeded times: {got or why}")

    ok = all(r for _, r in results)
    print(f"selftest: {sum(r for _, r in results)}/{len(results)} passed")
    return ok


# ---- main ------------------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--only", default="s1,s2,s3,s4")
    parser.add_argument("--person", action="store_true")
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--mutant", choices=MUTANTS)
    args = parser.parse_args()
    if args.selftest:
        deciders.MUTANT = args.mutant
        ok = selftest()
        if args.mutant:
            print(f"mutant {args.mutant}: {'survived' if ok else 'caught'}")
        return 0 if ok else 1
    if args.mutant:
        parser.error("--mutant needs --selftest")
    groups = [g.strip() for g in args.only.split(",") if g.strip()]
    unknown = [g for g in groups if g not in GROUPS]
    if unknown:
        parser.error(f"unknown group(s): {', '.join(unknown)}")
    spikes = [GROUPS[g] for g in groups]

    roadmap_text = ROADMAP.read_text()
    changed = deciders.changed_rules(roadmap_text, spikes)
    if changed:
        for spike in changed:
            print(f"RULE CHANGED {spike}: {deciders.rule_sha256(roadmap_text, spike)} is not "
                  f"{deciders.PINNED[spike]}; re-record it in CJ0a's record first", file=sys.stderr)
        return 1
    if not LIBRARY.exists() or not CODECS.exists():
        print(f"NOT PERFORMED: {LIBRARY if not LIBRARY.exists() else CODECS} is missing", file=sys.stderr)
        return 2
    WORK.mkdir(parents=True, exist_ok=True)
    why = build()
    if why:
        print(f"B0 FAILED: {why}", file=sys.stderr)
        return 1
    print(f"B0: {PROBE}, {BUNDLE}, {READER_BIN}")
    if args.build_only:
        return 0
    host, why = probe("host", {}, "host")
    if why:
        print(f"INSTRUMENT FAILURE: host: {why}", file=sys.stderr)
        return 1
    print(f"host: console locked {host['screen_locked']}; screen {host['screen_capture']}, post "
          f"{host['post_event']}, listen {host['listen_event']}, "
          f"accessibility {host['accessibility']}; {len(host['displays'])} display(s); "
          f"{host_facts()['power']}")
    for spike in spikes:
        print(f"-- {spike}", flush=True)
        run_spike(spike, args, host, roadmap_text)
    for failure in FAILURES:
        print(f"INSTRUMENT FAILURE: {failure}", file=sys.stderr)
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
