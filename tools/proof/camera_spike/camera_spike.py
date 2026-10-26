#!/usr/bin/env python3
"""The camera-recording spike — road map "camera-recording", CR0 (spec §11 CAM-2).

MEASURES camera capture alone and beside a running screen recording before any camera code
is built: the device and format lists (with and without the Continuity Camera key), the
camera grant (the responsible process, the hardened runtime with and without
`com.apple.security.device.camera`), `AVCaptureMovieFileOutput` against `AVAssetWriter`, the
microphone as a second file and its offset, the camera beside an `SCStream` recording and
the screen file's start estimators against a display-link counter, pause as a file sequence,
the live preview's cost, the virtual cameras, and what a proof can measure without a person.
It judges by CAM-2 (fixed before the run; `results.json` pins the §11 file's SHA-256).
The answers are in `designs/camera-recording.md`'s CR0 record, not here.

    python3 tools/proof/camera_spike/camera_spike.py [--groups devices,grant,write,mic,screen,pause,preview,virtual,aimed]
        [--camera SUBSTR] [--mic SUBSTR] [--runs N] [--ask] [--aimed]
    python3 tools/proof/camera_spike/camera_spike.py --selftest [--mutant NAME]

Exit 0: every requested row answered or skipped by name (whatever the VERDICT). Exit 1: an
instrument check failed — B0, a probe crash or expiry, an `analyze` read that failed, the
counter unreadable, a selftest row (so a mutant caught under `--mutant` exits 1). Exit 2: not
performed (no `core/target/release/libframejob_core.a`). A skipped row is never a failure.
Everything written is under `tools/proof/work/camera-spike/` (gitignored). No app instance, no
socket, no MCP, no network; every child runs in its own process group under
`graphics_spike/bounded.py`, and only those groups are ever killed.
"""

import argparse
import hashlib
import json
import os
import platform
import shutil
import statistics
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = ROOT / "tools/proof"
SPIKE = HERE / "camera_spike"
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402

WORK = HERE / "work/camera-spike"
BUILD = WORK / "build"
RECORDINGS = WORK / "recordings"
ANSWERS = WORK / "answers"
RESULTS = WORK / "results.json"
PROBE_SWIFT = SPIKE / "camera_spike_probe.swift"
LIBRARY = ROOT / "core/target/release/libframejob_core.a"
RULE_FILE = ROOT / "designs/spec/11-decisions/camera-recording.md"

GROUPS = ["devices", "grant", "write", "mic", "screen", "pause", "preview", "virtual", "aimed"]
CAMERA_GROUPS = {"grant", "write", "mic", "screen", "pause", "preview", "aimed"}
BUILD_WALL, CAPTURE_WALL, ANALYZE_WALL = 900, 120, 60
FRAMES_PASS = 0.98          # CAM-2 Writer: frames written ≥ 98 % of span × rate
SCREEN_TOL_MS = 16.7        # CAM-2 Screen start
BLACK_LUMA = 24             # CAM-2 Black frame: mean luma (8-bit) < 24
WHITE_MIN, BLACK_MAX = 160, 96   # the counter's block reading: ≥ 160 white, ≤ 96 black, else unreadable
WRITE_SECONDS = 5
SCREEN_RUNS_PER_ORDER = 2
MUTANTS = ["writer-frames-off", "estimator-wide", "decode-swap", "skip-as-fail", "continuity-inverted"]
MUTANT = None

PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>{name}</string>
<key>NSCameraUsageDescription</key><string>The Frame Job camera spike measures camera capture before the recorder is built.</string>
<key>NSMicrophoneUsageDescription</key><string>The Frame Job camera spike measures the microphone beside a camera.</string>
{extra}</dict></plist>
"""
CONTINUITY_KEY = "<key>NSCameraUseContinuityCameraDeviceType</key><true/>\n"
ENTITLEMENTS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.device.camera</key><true/>
</dict></plist>
"""

# What each row needs, for Q0 ("what a proof can measure without a person").
NEEDS = {
    "H0": "nothing", "B0": "nothing (the staticlib)",
    "D1": "nothing (a camera present to list one)", "D2": "nothing (a camera present to list one)",
    "D3": "a camera present",
    "T1": "nothing", "T2": "camera grant + a camera present", "T3": "camera grant + a camera present",
    "W1": "camera grant + a camera present", "W2": "camera grant + a camera present",
    "W3": "camera grant + a camera present",
    "M1": "camera + microphone grants, a camera and the microphone present",
    "M2": "camera + microphone grants, a camera and the microphone present",
    "S1": "camera grant + Screen Recording + a camera present",
    "S2": "camera grant + Screen Recording + a camera present",
    "P1": "camera grant + a camera present (microphone grant for its mic offsets)",
    "P2": "camera grant + a camera present (microphone grant for its mic offsets)",
    "V1": "camera grant + a camera present (a window server session)",
    "X1": "nothing to list; camera grant + a virtual camera to measure delivery",
    "A1": "a person (pointing the camera at the screen) + every grant",
}

ROWS = {}
FAILURES = []


# ---- pure: CAM-2's deciders, the counter, the scoring ----------------------------------------

def spread(values):
    vals = [v for v in values if isinstance(v, (int, float)) and not isinstance(v, bool)]
    if not vals:
        return None
    return {"median": round(statistics.median(vals), 3), "min": round(min(vals), 3),
            "max": round(max(vals), 3), "n": len(vals)}


def best_format(formats):
    """CAM-2 Best format: the largest width × height whose maximum rate is ≥ 30; ties to the
    higher maximum rate, then to the format listed first. The format's index, or None."""
    best, best_key = None, None
    for f in formats:
        if f["maxRate"] < 30:
            continue
        key = (f["width"] * f["height"], f["maxRate"])
        if best_key is None or key > best_key:
            best, best_key = f, key
    return None if best is None else best["index"]


def default_camera(devices, want=None):
    if want:
        for d in devices:
            if d["uniqueID"] == want or want.lower() in d["localizedName"].lower():
                return d
        return None
    for d in devices:
        if (d["deviceType"] == "AVCaptureDeviceTypeBuiltInWideAngleCamera"
                and not d["isContinuityCamera"] and "FaceTime" in d["localizedName"]):
            return d
    return devices[0] if devices else None


def decide_writer(w2, w3, p1_resume_ms, p2_resume_ms, frame_ms):
    """CAM-2 Writer over W2's runs (`ratio`, `start_ok`, `codec_ok`), W3's runs (`ratio`) and
    P1's and P2's median resume start latencies. Answers (verdict, reasons)."""
    if not w2:
        return "NOT MEASURED", ["no W2 run"]
    movie_reaches = all(r["ratio"] is not None and r["ratio"] >= FRAMES_PASS for r in w2)
    writer_reaches = bool(w3) and all(r["ratio"] is not None and r["ratio"] >= FRAMES_PASS for r in w3)
    if not movie_reaches and not writer_reaches:
        return "STOP", ["neither path reaches 98 % of span × rate in every run"]
    reasons = []
    if MUTANT != "writer-frames-off":
        if any(r["ratio"] is None or r["ratio"] < FRAMES_PASS for r in w2) and writer_reaches:
            reasons.append("(a) a W2 run wrote < 98 % of span × rate while W3's runs are ≥ 98 %")
    if any(not r["start_ok"] for r in w2):
        reasons.append("(b) a W2 run had no startPTS callback or no host conversion")
    if any(not r["codec_ok"] for r in w2):
        reasons.append("(c) a W2 run wrote neither HEVC nor H.264")
    if p1_resume_ms is not None and p2_resume_ms is not None and frame_ms:
        if p1_resume_ms - p2_resume_ms > frame_ms:
            reasons.append(f"(d) P1's median resume start latency {p1_resume_ms:.1f} ms exceeds "
                           f"P2's {p2_resume_ms:.1f} ms by more than one frame ({frame_ms:.1f} ms)")
    return ("asset-writer" if reasons else "movie-output"), reasons


def decide_screen(runs):
    """CAM-2 Screen start over the S runs' errors against the counter truth (`e1_ms`, `e2_ms`).
    'unmeasured' when there is no run."""
    tolerance = 50.0 if MUTANT == "estimator-wide" else SCREEN_TOL_MS
    if not runs:
        return "unmeasured"
    for name in ("E1", "E2"):
        errors = [r.get(name.lower() + "_ms") for r in runs]
        if all(e is not None and abs(e) <= tolerance for e in errors):
            return name
    return "STOP"


def encode(code):
    """The counter's 16 blocks for a code: 8 bits MSB first, then their complement (1 = white)."""
    bits = [(code >> (7 - i)) & 1 for i in range(8)]
    return bits + [1 - b for b in bits]


def lumas_of(bits, white=255.0, black=0.0):
    return [white if b else black for b in bits]


def decode(lumas):
    """A frame's 16 block lumas → its code, or None ("unreadable"): a block neither clearly
    white nor clearly black, or a data bit equal to its complement block (a torn frame)."""
    if len(lumas) != 16 or any(not isinstance(v, (int, float)) for v in lumas):
        return None
    bits = []
    for v in lumas:
        if v >= WHITE_MIN:
            bits.append(1)
        elif v <= BLACK_MAX:
            bits.append(0)
        else:
            return None
    data, check = bits[:8], bits[8:]
    if any(d == c for d, c in zip(data, check)):
        return None
    if MUTANT == "decode-swap":
        return sum(b << i for i, b in enumerate(data))
    return sum(b << (7 - i) for i, b in enumerate(data))


def torn(a, b, rows):
    """Blocks of code a in the top `rows` rows and of code b below."""
    return lumas_of(encode(a))[:4 * rows] + lumas_of(encode(b))[4 * rows:]


def decide_continuity(d1_devices, d2_devices):
    """CAM-2 Continuity key: D1 (with the key) against D2 (no key, no .continuityCamera)."""
    continuity = {d["uniqueID"] for d in d1_devices if d.get("isContinuityCamera")}
    if not continuity:
        return "unmeasured"
    listed = {d["uniqueID"] for d in d2_devices}
    needed = not (continuity & listed)
    if MUTANT == "continuity-inverted":
        needed = not needed
    return "needed" if needed else "not-needed"


def decide_entitlement(t2, t3):
    """CAM-2 Camera entitlement over T2 (hardened, no entitlement) and T3 (with it), each
    {frames, black} or None when skipped."""
    def nothing(t):
        return t is None or t["frames"] == 0 or t["black"] >= t["frames"]
    if nothing(t3) or t2 is None:
        return "unmeasured"
    return "needed" if nothing(t2) else "not-needed"


def score(rows):
    """The exit code over the rows: 1 when any row failed, else 0. A skipped row is not a failure."""
    for row in rows.values():
        if row.get("outcome") == "failed":
            return 1
        if MUTANT == "skip-as-fail" and row.get("outcome") == "skipped":
            return 1
    return 0


def screen_truth(blocks, log, e1):
    """The screen file's first-frame truth from its first readable counter frame: the logged
    `targetTimestamp` of that code nearest E1, less the frame's offset from the first frame.
    Answers (truth or None, frame index, code)."""
    if not blocks:
        return None, None, None
    pts0 = blocks[0]["pts"]
    for k, frame in enumerate(blocks):
        code = decode(frame["lumas"])
        if code is None:
            continue
        entries = [e for e in log if int(e[0]) == code]
        if not entries:
            return None, k, code
        target = min(entries, key=lambda e: abs(e[1] - e1))[1] if e1 is not None else entries[0][1]
        return target - (frame["pts"] - pts0), k, code
    return None, None, None


# ---- the selftest ---------------------------------------------------------------------------

def selftest():
    results = []

    def check(name, ok, text):
        results.append((name, ok))
        print(f"  {'ok  ' if ok else 'FAIL'} {name}: {text}")

    good = {"ratio": 0.995, "start_ok": True, "codec_ok": True}
    w3 = [{"ratio": 0.995}] * 3
    base = decide_writer([good] * 3, w3, 40.0, 35.0, 33.3)[0]
    a = decide_writer([good, dict(good, ratio=0.95), good], w3, 40.0, 35.0, 33.3)[0]
    b = decide_writer([good, dict(good, start_ok=False), good], w3, 40.0, 35.0, 33.3)[0]
    c = decide_writer([good, dict(good, codec_ok=False), good], w3, 40.0, 35.0, 33.3)[0]
    d = decide_writer([good] * 3, w3, 80.0, 35.0, 33.3)[0]
    d_under = decide_writer([good] * 3, w3, 60.0, 35.0, 33.3)[0]
    stop = decide_writer([dict(good, ratio=0.95)] * 3, [{"ratio": 0.90}] * 3, 40.0, 35.0, 33.3)[0]
    check("S1", (base, a, b, c, d, d_under, stop) == ("movie-output", "asset-writer", "asset-writer",
                                                     "asset-writer", "asset-writer", "movie-output", "STOP"),
          f"base {base}, (a) {a}, (b) {b}, (c) {c}, (d) {d}, (d) under a frame {d_under}, neither {stop}")

    e1 = decide_screen([{"e1_ms": 16.6, "e2_ms": 3.0}, {"e1_ms": -16.6, "e2_ms": 1.0}])
    e2 = decide_screen([{"e1_ms": 16.8, "e2_ms": 3.0}, {"e1_ms": 2.0, "e2_ms": -16.6}])
    neither = decide_screen([{"e1_ms": 16.8, "e2_ms": 16.8}, {"e1_ms": 1.0, "e2_ms": 1.0}])
    none = decide_screen([])
    check("S2", (e1, e2, neither, none) == ("E1", "E2", "STOP", "unmeasured"),
          f"16.6 ms {e1}, E1 at 16.8 ms {e2}, both 16.8 ms {neither}, no run {none}")

    round_trip = all(decode(lumas_of(encode(n))) == n for n in range(256))
    round_trip_video = all(decode(lumas_of(encode(n), 235.0, 16.0)) == n for n in range(256))
    the_tear = decode(torn(0x0F, 0x10, 2))
    honest = True
    for n in range(256):
        for rows in (1, 2, 3):
            frame = torn(n, (n + 1) % 256, rows)
            got = decode(frame)
            if got is not None and lumas_of(encode(got)) != frame:
                honest = False
    grey = decode([128.0] + lumas_of(encode(0x5A))[1:])
    check("S3", round_trip and round_trip_video and the_tear is None and honest and grey is None,
          f"256 codes round-trip {round_trip} (video range {round_trip_video}); 0x0F/0x10 torn at "
          f"row 2 reads {the_tear}; every n/n+1 tear reads unreadable or the code its pixels are "
          f"{honest}; a grey block reads {grey}")

    skipped = {"H0": {"outcome": "ok"}, "W1": {"outcome": "skipped", "reason": "no grant"}}
    failed = {"H0": {"outcome": "ok"}, "W1": {"outcome": "failed"}}
    check("S4", score(skipped) == 0 and score(failed) == 1,
          f"a skipped row scores {score(skipped)}, a failed row {score(failed)}")

    d1_none = [{"uniqueID": "a", "isContinuityCamera": False}]
    d1_cont = [{"uniqueID": "a", "isContinuityCamera": False}, {"uniqueID": "c", "isContinuityCamera": True}]
    unmeasured = decide_continuity(d1_none, [{"uniqueID": "a"}])
    needed = decide_continuity(d1_cont, [{"uniqueID": "a"}])
    not_needed = decide_continuity(d1_cont, [{"uniqueID": "a"}, {"uniqueID": "c"}])
    lit = {"frames": 60, "black": 2}
    dark = {"frames": 60, "black": 60}
    ent = (decide_entitlement(lit, {"frames": 0, "black": 0}), decide_entitlement(dark, dark),
           decide_entitlement({"frames": 0, "black": 0}, lit), decide_entitlement(dark, lit),
           decide_entitlement(lit, lit))
    check("S5", (unmeasured, needed, not_needed) == ("unmeasured", "needed", "not-needed")
          and ent == ("unmeasured", "unmeasured", "needed", "needed", "not-needed"),
          f"continuity: none marked {unmeasured}, missing without the key {needed}, listed "
          f"{not_needed}; entitlement: T3 no frame {ent[0]}, both black {ent[1]}, T2 no frame "
          f"{ent[2]}, T2 black {ent[3]}, both lit {ent[4]}")

    ok = all(r for _, r in results)
    print(f"selftest: {sum(r for _, r in results)}/{len(results)} passed")
    return ok


# ---- the host, the build, the probe ---------------------------------------------------------

def out(argv, seconds=30):
    ran = bounded.run(argv, seconds)
    return (ran["stdout"] or "").strip()


def host(label):
    power = out(["pmset", "-g", "batt"]).splitlines()
    return {
        "label": label, "at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": out(["sysctl", "-n", "hw.model"]),
        "macos": out(["sw_vers", "-productVersion"]) + " (" + out(["sw_vers", "-buildVersion"]) + ")",
        "load": [round(x, 2) for x in os.getloadavg()],
        "power": power[0] if power else "?",
        "framejob_pids": [int(p) for p in out(["pgrep", "-f", "MacOS/Frame Job"]).split() if p.isdigit()],
    }


def snapshot(label):
    ROWS.setdefault("H0", {"outcome": "ok", "snapshots": []})["snapshots"].append(host(label))


def commit():
    head = out(["git", "-C", str(ROOT), "rev-parse", "HEAD"])
    dirty = out(["git", "-C", str(ROOT), "status", "--porcelain"])
    return head + ("+dirty" if dirty else "")


def fail(row, reason):
    FAILURES.append(f"{row}: {reason}")
    return {"outcome": "failed", "reason": reason}


def write_if_changed(path, text):
    if not path.exists() or path.read_text() != text:
        path.write_text(text)


def build():
    """B0: both probes and the two hardened copies. Answers ({name: path}, row)."""
    import swift_build
    BUILD.mkdir(parents=True, exist_ok=True)
    entry = BUILD / "main.swift"
    write_if_changed(entry, PROBE_SWIFT.read_text())
    paths, row = {}, {"outcome": "ok", "builds": {}}
    for name, extra in (("camera-spike-probe", CONTINUITY_KEY), ("camera-spike-probe-nokey", "")):
        plist = BUILD / f"{name}.plist"
        write_if_changed(plist, PLIST.format(name=name, extra=extra))
        try:
            built = swift_build.build(
                sources=[entry], output=BUILD / name,
                link_args=["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker",
                           "__info_plist", "-Xlinker", str(plist)],
                link_inputs=[plist], timeout=BUILD_WALL)
        except swift_build.SwiftBuildFailed as error:
            return None, fail("B0", f"{name} did not build: " + " | ".join(error.diagnostics[:6] or [str(error)]))
        paths[name] = BUILD / name
        row["builds"][name] = "reused" if built.reused else f"built in {built.seconds:.1f} s"
    entitlements = BUILD / "camera.entitlements"
    write_if_changed(entitlements, ENTITLEMENTS)
    for sub, ents in (("hardened-noent", None), ("hardened-ent", entitlements)):
        folder = BUILD / sub
        folder.mkdir(exist_ok=True)
        target = folder / "camera-spike-probe"
        shutil.copy2(paths["camera-spike-probe"], target)
        argv = ["codesign", "--force", "--sign", "-", "-o", "runtime"]
        argv += ["--entitlements", str(ents)] if ents else []
        ran = bounded.run(argv + [str(target)], 60)
        if ran["rc"] != 0:
            return None, fail("B0", f"codesign {sub} exited {ran['rc']}: {ran['stderr'].strip()[-200:]}")
        shown = bounded.run(["codesign", "-dv", "--entitlements", "-", str(target)], 30)
        flags = [line for line in (shown["stderr"] + shown["stdout"]).splitlines()
                 if "flags=" in line or "device.camera" in line]
        row["builds"][sub] = flags
        paths[sub] = target
    return paths, row


def probe(binary, mode, job, tag, wall=CAPTURE_WALL):
    """(answer, None) or (None, why) on a crash, an expiry or no JSON line."""
    ANSWERS.mkdir(parents=True, exist_ok=True)
    job_file = ANSWERS / f"{tag}.job.json"
    job_file.write_text(json.dumps(job, indent=1))
    ran = bounded.run([str(binary), mode, str(WORK), str(job_file)], wall, cwd=str(WORK))
    (ANSWERS / f"{tag}.stderr.txt").write_text(ran["stderr"] or "")
    if ran["expired"]:
        return None, f"{mode} ({tag}) ran past {wall} s and was killed"
    if ran["rc"] != 0:
        tail = (ran["stderr"] or "").strip()[-300:]
        return None, f"{mode} ({tag}) exited {ran['rc']}: {tail}"
    for line in reversed((ran["stdout"] or "").splitlines()):
        if line.startswith("{"):
            try:
                answer = json.loads(line)
            except ValueError:
                break
            (ANSWERS / f"{tag}.json").write_text(json.dumps(answer, indent=1))
            return answer, None
    return None, f"{mode} ({tag}) printed no JSON line"


def analyze(binary, movie, tag, **extra):
    answer, why = probe(binary, "analyze", dict(movie=str(movie), **extra), f"{tag}.analyze", ANALYZE_WALL)
    if why is None and answer.get("outcome") != "ok":
        why = f"analyze {movie}: {answer.get('reason')}"
    return answer, why


# ---- the groups -----------------------------------------------------------------------------

class Ctx:
    camera = None       # D1's chosen device
    d3 = None           # its best format index
    mic = None          # the chosen microphone's name
    w2_runs, w3_runs = [], []
    p_resume = {}
    frame_ms = None
    screen_runs = []
    t2 = t3 = None
    d1 = d2 = None


def camera_skip(row):
    ROWS[row] = {"outcome": "skipped", "reason": "no camera present (D1 lists none)"
                 if Ctx.d1 is not None else "no camera chosen"}


def group_devices(paths, args):
    d1, why = probe(paths["camera-spike-probe"], "devices", {"continuity": True}, "D1")
    if why:
        ROWS["D1"] = fail("D1", why)
        return
    Ctx.d1 = d1["devices"]
    ROWS["D1"] = {"outcome": "ok", "plistContinuityKey": d1["plistContinuityKey"],
                  "systemPreferredCamera": d1["systemPreferredCamera"],
                  "microphones": d1["microphones"], "devices": d1["devices"]}
    d2 = {"outcome": "ok"}
    with_type, why = probe(paths["camera-spike-probe-nokey"], "devices", {"continuity": True}, "D2-with-type")
    # Asking for .continuityCamera without the key is itself a measurement: a refusal by the
    # framework is an answer here, not an instrument failure.
    d2["withContinuityType"] = ({"devices": [summary_device(x) for x in with_type["devices"]],
                                 "plistContinuityKey": with_type["plistContinuityKey"]}
                                if with_type else {"refused": why})
    without, why = probe(paths["camera-spike-probe-nokey"], "devices", {"continuity": False}, "D2-without-type")
    if why:
        ROWS["D2"] = fail("D2", why)
    else:
        Ctx.d2 = without["devices"]
        d2["withoutContinuityType"] = {"devices": [summary_device(x) for x in without["devices"]],
                                       "plistContinuityKey": without["plistContinuityKey"]}
        ROWS["D2"] = d2
    picks = {}
    for device in Ctx.d1:
        index = best_format(device["formats"])
        f = device["formats"][index] if index is not None else None
        picks[device["localizedName"]] = {
            "uniqueID": device["uniqueID"], "index": index,
            "format": None if f is None else f"{f['width']}x{f['height']}@{f['maxRate']:g} {f['subtype']}",
            "activeFormat": device["activeFormat"],
            "default": None if device["activeFormat"] is None else (
                lambda g: f"{g['width']}x{g['height']}@{g['maxRate']:g} {g['subtype']}")(
                device["formats"][device["activeFormat"]])}
    ROWS["D3"] = {"outcome": "ok" if Ctx.d1 else "skipped", "picks": picks}
    if not Ctx.d1:
        ROWS["D3"]["reason"] = "no camera present"
    Ctx.camera = default_camera(Ctx.d1, args.camera)
    if Ctx.camera:
        Ctx.d3 = best_format(Ctx.camera["formats"])
        f = Ctx.camera["formats"][Ctx.d3] if Ctx.d3 is not None else None
        Ctx.frame_ms = 1000.0 / f["maxRate"] if f else None
    mics = [m for m in d1["microphones"]
            if args.mic.lower() in m["localizedName"].lower() or m["uniqueID"] == args.mic]
    Ctx.mic = mics[0]["uniqueID"] if mics else None
    ROWS["D1"]["chosen"] = {"camera": Ctx.camera and Ctx.camera["localizedName"],
                            "cameraID": Ctx.camera and Ctx.camera["uniqueID"], "d3": Ctx.d3,
                            "microphone": mics[0]["localizedName"] if mics else None}


def summary_device(d):
    return {"uniqueID": d["uniqueID"], "localizedName": d["localizedName"], "deviceType": d["deviceType"],
            "isContinuityCamera": d["isContinuityCamera"], "transportType": d["transportType"]}


def session_row(answer):
    if answer.get("outcome") == "skipped":
        return {"outcome": "skipped", "reason": answer["reason"]}, None
    t = {"frames": answer.get("frames", 0), "black": answer.get("black", 0)}
    row = {"outcome": "ok", **{k: answer.get(k) for k in ("running", "frames", "black", "meanLuma",
                                                           "minLuma", "maxLuma", "firstFrameAfterStartMs", "error")}}
    return row, t


def group_grant(paths, args):
    t1, why = probe(paths["camera-spike-probe"], "grant", {"ask": bool(args.ask)}, "T1", wall=150)
    ROWS["T1"] = fail("T1", why) if why else dict(t1, outcome="ok")
    if not Ctx.camera:
        camera_skip("T2")
        camera_skip("T3")
        return
    for row, key in (("T2", "hardened-noent"), ("T3", "hardened-ent")):
        answer, why = probe(paths[key], "session", {"camera": Ctx.camera["uniqueID"], "seconds": 2}, row)
        if why:
            ROWS[row] = fail(row, why)
            continue
        ROWS[row], t = session_row(answer)
        ROWS[row]["binary"] = key
        if row == "T2":
            Ctx.t2 = t
        else:
            Ctx.t3 = t


def write_metrics(answer, analysis):
    rate = answer.get("targetRate") or 0
    frames = analysis.get("frames") or 0
    first, last = analysis.get("firstPTS"), analysis.get("lastPTS")
    span = (last - first + 1.0 / rate) if (first is not None and last is not None and rate) else None
    expected = span * rate if span else None
    rb = answer.get("readBackRecording") or {}
    return {
        "didStartMs": answer.get("didStartMs"),
        "startPTS_ok": bool(answer.get("didStart")) and bool(answer.get("hostConversion")),
        "syncClockIsHost": answer.get("syncClockIsHost"),
        "startPTSHostMinusCallbackMs": answer.get("startPTSHostMinusCallbackMs"),
        "frames": frames, "expected": round(expected, 2) if expected else None,
        "ratio": round(frames / expected, 4) if expected else None,
        "targetRate": rate, "nominalRate": analysis.get("nominalFrameRate"),
        "averageRate": round((frames - 1) / (last - first), 3) if frames > 1 and last and last > first else None,
        "gapsOver1_5": analysis.get("gapsOver1_5"), "maxIntervalMs": (analysis.get("maxInterval") or 0) * 1000,
        "droppedCallbacks": answer.get("droppedCallbacks"), "notReady": answer.get("notReady"),
        "bytesPerSecond": round(analysis["bytes"] / span) if span else None,
        "codec": analysis.get("codec"), "codecAsked": answer.get("codecAsked") or (answer.get("codec") or {}).get("codecAsked"),
        "hevcWritable": answer.get("hevcWritable", (answer.get("codec") or {}).get("hevcWritable")),
        "h264Writable": answer.get("h264Writable", (answer.get("codec") or {}).get("h264Writable")),
        "colour": [analysis.get("primaries"), analysis.get("transfer"), analysis.get("matrix")],
        "transform": analysis.get("transform"), "dims": [analysis.get("width"), analysis.get("height")],
        "cpuSeconds": round(answer.get("cpuSeconds", 0), 3),
        "readBackMinFrameDuration": rb.get("minFrameDuration"), "readBackMaxFrameDuration": rb.get("maxFrameDuration"),
        "readBackFormat": rb.get("activeFormat"), "formatHeld": answer.get("formatHeld"),
        "closeMs": answer.get("closeMs"),
    }


NUMERIC = ("didStartMs", "startPTSHostMinusCallbackMs", "frames", "expected", "ratio", "nominalRate",
           "averageRate", "gapsOver1_5", "maxIntervalMs", "droppedCallbacks", "notReady", "bytesPerSecond",
           "cpuSeconds", "readBackMinFrameDuration", "readBackMaxFrameDuration", "closeMs")


def off_format(requested, read_backs):
    """True when a run asked for a format and any read-back while recording is another one (or
    missing): such a run is not CAM-2 evidence "at D3's format"."""
    return requested is not None and any(rb != requested for rb in read_backs)


def summarise(runs, keys=NUMERIC):
    return {k: spread([r.get(k) for r in runs]) for k in keys if spread([r.get(k) for r in runs])}


def group_write(paths, args):
    if not Ctx.camera:
        for row in ("W1", "W2", "W3"):
            camera_skip(row)
        return
    binary = paths["camera-spike-probe"]
    shapes = (("W1", "movie", None, False), ("W2", "movie", Ctx.d3, True), ("W3", "writer", Ctx.d3, True))
    for row, writer, fmt, lock in shapes:
        runs, skipped = [], None
        for i in range(args.runs):
            movie = RECORDINGS / f"{row}-{i}.mov"
            job = {"camera": Ctx.camera["uniqueID"], "writer": writer, "format": fmt, "lock": lock,
                   "seconds": WRITE_SECONDS, "out": str(movie)}
            answer, why = probe(binary, "write", job, f"{row}-{i}")
            if why:
                ROWS[row] = fail(row, why)
                break
            if answer["outcome"] == "skipped":
                skipped = answer["reason"]
                break
            if answer["outcome"] != "ok":
                ROWS[row] = fail(row, answer.get("reason"))
                break
            analysis, why = analyze(binary, movie, f"{row}-{i}")
            if why:
                ROWS[row] = fail(row, why)
                break
            m = write_metrics(answer, analysis)
            m["codec_ok"] = m["codec"] in ("hvc1", "avc1")
            m["offFormat"] = off_format(fmt, [m["readBackFormat"]])
            runs.append(m)
        else:
            ROWS[row] = {"outcome": "ok", "format": fmt, "locked": lock, "path": writer,
                         "runs": runs, "summary": summarise(runs),
                         "offFormatRuns": sum(1 for r in runs if r["offFormat"])}
        if skipped:
            ROWS[row] = {"outcome": "skipped", "reason": skipped}
        if row == "W2" and ROWS[row]["outcome"] == "ok":
            # CAM-2 judges W2 "at D3's format": a run that recorded at another format is reported,
            # never evidence.
            Ctx.w2_runs = [{"ratio": r["ratio"], "start_ok": r["startPTS_ok"], "codec_ok": r["codec_ok"]}
                           for r in runs if not r["offFormat"]]
        if row == "W3" and ROWS[row]["outcome"] == "ok":
            Ctx.w3_runs = [{"ratio": r["ratio"]} for r in runs]


def group_mic(paths, args):
    if not Ctx.camera:
        camera_skip("M1")
        camera_skip("M2")
        return
    if not Ctx.mic:
        for row in ("M1", "M2"):
            ROWS[row] = {"outcome": "skipped", "reason": f"no microphone matches {args.mic!r} "
                         f"(present: {[m['localizedName'] for m in ROWS['D1']['microphones']]})"}
        return
    binary = paths["camera-spike-probe"]
    for row in ("M1", "M2"):
        runs, skipped, failed = [], None, False
        for i in range(args.runs):
            video, audio = RECORDINGS / f"{row}-{i}.mov", RECORDINGS / f"{row}-{i}.m4a"
            job = {"camera": Ctx.camera["uniqueID"], "mic": Ctx.mic, "shape": row, "seconds": 3,
                   "outVideo": str(video), "outAudio": str(audio)}
            answer, why = probe(binary, "mic", job, f"{row}-{i}")
            if why or answer["outcome"] == "failed":
                ROWS[row] = fail(row, why or answer.get("reason"))
                failed = True
                break
            if answer["outcome"] == "skipped":
                skipped = answer["reason"]
                break
            r = {k: answer.get(k) for k in ("canAddAudioFileOutput", "offsetPTSMs", "offsetCallbackMs",
                                            "cameraDidStartMs", "micDidStartMs", "micSyncClockIsHost",
                                            "cameraFinish", "micFinish", "micFinishError", "note")}
            if answer.get("canAddAudioFileOutput") is False:
                runs.append(r)
                break
            va, why = analyze(binary, video, f"{row}-{i}-video")
            aa, why2 = (analyze(binary, audio, f"{row}-{i}-audio") if not why else (None, None))
            if why or why2:
                ROWS[row] = fail(row, why or why2)
                failed = True
                break
            r["videoFrames"] = va.get("frames")
            r["videoDuration"] = va.get("duration")
            r["audioDuration"] = aa.get("duration")
            r["audioFormat"] = (aa.get("audio") or {}).get("format")
            r["callbackMinusPTSMs"] = (None if r["offsetPTSMs"] is None or r["offsetCallbackMs"] is None
                                      else round(r["offsetCallbackMs"] - r["offsetPTSMs"], 3))
            runs.append(r)
        if skipped:
            ROWS[row] = {"outcome": "skipped", "reason": skipped}
        elif not failed:
            ROWS[row] = {"outcome": "ok", "runs": runs,
                         "summary": summarise(runs, ("offsetPTSMs", "offsetCallbackMs", "callbackMinusPTSMs",
                                                     "cameraDidStartMs", "micDidStartMs", "videoDuration",
                                                     "audioDuration"))}


def counter_blocks(answer, analysis):
    """The counter's 16 block rects (inner half of each) in the screen file's pixels."""
    x, y, w, h = answer["counterRect"]
    scale = (analysis.get("width") or answer["displayPoints"][0]) / answer["displayPoints"][0]
    cell = w / 4.0
    rects = []
    for i in range(16):
        row, col = divmod(i, 4)
        rects.append([(x + col * cell + cell * 0.25) * scale, (y + row * cell + cell * 0.25) * scale,
                      cell * 0.5 * scale, cell * 0.5 * scale])
    return rects


def group_screen(paths, args):
    if not Ctx.camera:
        camera_skip("S1")
        camera_skip("S2")
        return
    binary = paths["camera-spike-probe"]
    for row, order in (("S1", "camera-first"), ("S2", "stream-first")):
        runs, skipped, failed = [], None, False
        for path in ("movie", "writer"):
            for i in range(SCREEN_RUNS_PER_ORDER):
                tag = f"{row}-{path}-{i}"
                screen_file, camera_file = RECORDINGS / f"{tag}-screen.mov", RECORDINGS / f"{tag}-camera.mov"
                job = {"camera": Ctx.camera["uniqueID"], "order": order, "path": path, "seconds": 4,
                       "fps": 60, "format": Ctx.d3 if path == "writer" else None, "lock": path == "writer",
                       "outScreen": str(screen_file), "outCamera": str(camera_file)}
                answer, why = probe(binary, "screen", job, tag)
                if why or answer["outcome"] == "failed":
                    ROWS[row] = fail(row, why or answer.get("reason"))
                    failed = True
                    break
                if answer["outcome"] == "skipped":
                    skipped = answer["reason"]
                    break
                first, why = analyze(binary, screen_file, f"{tag}-screen")
                if not why:
                    blocks, why = analyze(binary, screen_file, f"{tag}-screen-blocks",
                                          blocks=counter_blocks(answer, first), lumaFrames=12)
                if not why:
                    cam, why = analyze(binary, camera_file, f"{tag}-camera")
                if why:
                    ROWS[row] = fail(row, why)
                    failed = True
                    break
                r = screen_run(answer, first, blocks, cam)
                r["path"] = answer["path"]
                if r["truth"] is None:
                    ROWS[row] = fail(row, f"{tag}: the counter was unreadable in the screen file's first 12 frames")
                    failed = True
                    break
                runs.append(r)
            if failed or skipped:
                break
        if skipped:
            ROWS[row] = {"outcome": "skipped", "reason": skipped}
        elif not failed:
            ROWS[row] = {"outcome": "ok", "order": order, "runs": runs,
                         "summary": summarise(runs, ("e1_ms", "e2_ms", "e2_arrival_ms", "cameraMinusTruthMs",
                                                     "cameraMinusE1Ms", "cameraMinusE2Ms",
                                                     "cameraCallbackMinusE1Ms", "screenFrames", "screenRate",
                                                     "cameraFrames", "cameraRate", "cpuSeconds"))}
            Ctx.screen_runs += runs


def screen_run(answer, first, blocks, cam):
    e1 = answer.get("E1")
    frames = answer.get("framesHead") or []
    complete = [f for f in frames if f[2] == 1]
    e2 = next((f[0] for f in complete if e1 is not None and f[0] >= e1), None)
    e2_arrival = next((f[0] for f in complete if e1 is not None and f[1] >= e1), None)
    truth, k, code = screen_truth(blocks.get("blockFrames") or [], answer.get("counterLog") or [], e1)
    cam_host = answer.get("cameraStartPTSHost")

    def ms(a, b):
        return None if a is None or b is None else round((a - b) * 1000, 3)

    def rate(an):
        f, a, b = an.get("frames") or 0, an.get("firstPTS"), an.get("lastPTS")
        return round((f - 1) / (b - a), 3) if f > 1 and a is not None and b and b > a else None
    return {
        "truth": truth, "truthFrame": k, "truthCode": code,
        "e1_ms": ms(e1, truth), "e2_ms": ms(e2, truth), "e2_arrival_ms": ms(e2_arrival, truth),
        "cameraMinusTruthMs": ms(cam_host, truth), "cameraMinusE1Ms": ms(cam_host, e1),
        "cameraMinusE2Ms": ms(cam_host, e2),
        "cameraCallbackMinusE1Ms": ms(answer.get("cameraCallbackAt"), e1),
        "screenFrames": first.get("frames"), "screenRate": rate(first),
        "cameraFrames": cam.get("frames"), "cameraRate": rate(cam),
        "cpuSeconds": round(answer.get("cpuSeconds", 0), 3), "clockCheckMs": answer.get("clockCheckMs"),
        "streamFailure": answer.get("failure"), "startError": answer.get("startError"),
    }


def group_pause(paths, args):
    if not Ctx.camera:
        camera_skip("P1")
        camera_skip("P2")
        return
    binary = paths["camera-spike-probe"]
    for row in ("P1", "P2"):
        runs, skipped, failed = [], None, False
        for i in range(args.runs):
            folder = RECORDINGS / f"{row}-{i}"
            job = {"camera": Ctx.camera["uniqueID"], "mic": Ctx.mic, "shape": row, "segments": 3,
                   "segSeconds": 2, "pauseSeconds": 1.5, "outDir": str(folder), "format": Ctx.d3, "lock": True}
            answer, why = probe(binary, "pause", job, f"{row}-{i}")
            if why or answer["outcome"] == "failed":
                ROWS[row] = fail(row, why or answer.get("reason"))
                failed = True
                break
            if answer["outcome"] == "skipped":
                skipped = answer["reason"]
                break
            for seg in answer["segments"]:
                an, why = analyze(binary, seg["file"], f"{row}-{i}-seg{seg['index']}")
                if why:
                    ROWS[row] = fail(row, why)
                    failed = True
                    break
                rate = answer.get("targetRate") or 0
                span = (an["lastPTS"] - an["firstPTS"] + 1.0 / rate) if an.get("frames") and rate else None
                seg["fileSpan"] = round(span, 4) if span else None
                seg["fileMinusSegmentMs"] = (round((span - seg["segmentSeconds"]) * 1000, 3)
                                             if span and seg.get("segmentSeconds") else None)
                seg["frames"] = an.get("frames")
                if seg.get("micFile"):
                    ma, why = analyze(binary, seg["micFile"], f"{row}-{i}-seg{seg['index']}-mic")
                    if why:
                        ROWS[row] = fail(row, why)
                        failed = True
                        break
                    seg["micDuration"] = ma.get("duration")
            if failed:
                break
            runs.append({"segments": answer["segments"], "pauses": answer["pauses"],
                         "dataOutputRateOverall": answer.get("dataOutputRateOverall"),
                         "microphone": answer.get("microphone"), "formatHeld": answer.get("formatHeld"),
                         "targetRate": answer.get("targetRate"),
                         "offFormat": off_format(Ctx.d3, [s.get("readBackFormat") for s in answer["segments"]])})
        if skipped:
            ROWS[row] = {"outcome": "skipped", "reason": skipped}
        elif not failed:
            segs = [s for r in runs for s in r["segments"]]
            # Clause (d) judges P1 at D3's format: an off-format P1 run is reported, never evidence.
            judged = [s for r in runs if row != "P1" or not r["offFormat"] for s in r["segments"]]
            resumes = [s.get("startMs") for s in judged if s["index"] >= 1]
            ROWS[row] = {"outcome": "ok", "runs": runs,
                         "offFormatRuns": sum(1 for r in runs if r["offFormat"]), "summary": {
                "startMs": spread([s.get("startMs") for s in segs]),
                "resumeStartMs": spread(resumes),
                "closeMs": spread([s.get("closeMs") for s in segs]),
                "fileMinusSegmentMs": spread([s.get("fileMinusSegmentMs") for s in segs]),
                "micOffsetMs": spread([s.get("micOffsetMs") for s in segs]),
                "micOffsetCallbackMs": spread([s.get("micOffsetCallbackMs") for s in segs]),
                "pauseDataOutputRate": spread([p.get("dataOutputRate") for r in runs for p in r["pauses"]]),
            }}
            med = ROWS[row]["summary"]["resumeStartMs"]
            Ctx.p_resume[row] = med["median"] if med else None


def group_preview(paths, args):
    if not Ctx.camera:
        camera_skip("V1")
        return
    binary = paths["camera-spike-probe"]
    results = {}
    for label, fmt, lock in (("default", None, False), ("d3", Ctx.d3, True)):
        job = {"camera": Ctx.camera["uniqueID"], "format": fmt, "lock": lock, "seconds": 10,
               "out": str(RECORDINGS / f"V1-{label}.mov")}
        answer, why = probe(binary, "preview", job, f"V1-{label}")
        if why or answer["outcome"] == "failed":
            ROWS["V1"] = fail("V1", why or answer.get("reason"))
            return
        if answer["outcome"] == "skipped":
            ROWS["V1"] = {"outcome": "skipped", "reason": answer["reason"]}
            return
        results[label] = {k: answer.get(k) for k in ("baseline", "sessionOnly", "withPreview",
                                                     "withPreviewAndRecording", "readBack", "formatHeld")}
    ROWS["V1"] = {"outcome": "ok", "formats": results}


def group_virtual(paths, args):
    answer, why = probe(paths["camera-spike-probe"], "virtual", {"seconds": 3}, "X1")
    ROWS["X1"] = fail("X1", why) if why else dict(answer, outcome="ok")


def group_aimed(paths, args):
    if not args.aimed:
        ROWS["A1"] = {"outcome": "skipped", "reason": "needs a person pointing the camera at the screen (--aimed)"}
        return
    if not Ctx.camera or not Ctx.mic:
        ROWS["A1"] = {"outcome": "skipped", "reason": "no camera or no microphone present"}
        return
    binary = paths["camera-spike-probe"]
    files = {k: RECORDINGS / f"A1-{k}" for k in ("screen.mov", "camera.mov", "mic.m4a", "tone.wav")}
    job = {"camera": Ctx.camera["uniqueID"], "mic": Ctx.mic, "outScreen": str(files["screen.mov"]),
           "outCamera": str(files["camera.mov"]), "outMic": str(files["mic.m4a"]), "tone": str(files["tone.wav"])}
    answer, why = probe(binary, "aimed", job, "A1")
    if why or answer["outcome"] == "failed":
        ROWS["A1"] = fail("A1", why or answer.get("reason"))
        return
    if answer["outcome"] == "skipped":
        ROWS["A1"] = {"outcome": "skipped", "reason": answer["reason"]}
        return
    cam, w1 = analyze(binary, files["camera.mov"], "A1-camera", allLuma=True)
    scr, w2 = analyze(binary, files["screen.mov"], "A1-screen", allLuma=True)
    mic, w3 = analyze(binary, files["mic.m4a"], "A1-mic", audioOnset=True)
    if w1 or w2 or w3:
        ROWS["A1"] = fail("A1", w1 or w2 or w3)
        return

    def crossing(an):
        lum = an.get("allLuma") or []
        if not lum:
            return None
        lo, hi = min(v for _, v in lum), max(v for _, v in lum)
        mid = (lo + hi) / 2
        t = next((t for t, v in lum if v > mid), None)
        return None if t is None else t - lum[0][0]
    e1 = answer.get("E1")
    complete = [f for f in answer.get("framesHead") or [] if f[2] == 1]
    e2 = next((f[0] for f in complete if e1 is not None and f[0] >= e1), None)
    cam_t, scr_t = crossing(cam), crossing(scr)
    onset = (mic.get("audio") or {}).get("onset")
    mic_first = (mic.get("audio") or {}).get("firstPTS") or 0
    cam_flash = None if cam_t is None or answer.get("cameraStartPTSHost") is None else answer["cameraStartPTSHost"] + cam_t
    scr_flash = None if scr_t is None or e2 is None else e2 + scr_t
    mic_onset = None if onset is None or answer.get("micStartPTSHost") is None else answer["micStartPTSHost"] + onset - mic_first
    ROWS["A1"] = {"outcome": "ok",
                  "cameraMinusScreenMs": None if cam_flash is None or scr_flash is None else round((cam_flash - scr_flash) * 1000, 3),
                  "cameraMinusMicMs": None if cam_flash is None or mic_onset is None else round((cam_flash - mic_onset) * 1000, 3),
                  "flashAt": answer.get("flashAt")}


GROUP_FUNCS = {"devices": group_devices, "grant": group_grant, "write": group_write, "mic": group_mic,
               "screen": group_screen, "pause": group_pause, "preview": group_preview,
               "virtual": group_virtual, "aimed": group_aimed}


# ---- the verdict ----------------------------------------------------------------------------

def verdict():
    write_rows = [ROWS.get(r, {}) for r in ("W1", "W2", "W3")]
    if all(r.get("outcome") == "skipped" for r in write_rows):
        reason = next((r.get("reason") for r in write_rows if r.get("reason")), "every write row skipped")
        return f"VERDICT NOT MEASURED: {reason}", {"writer": "NOT MEASURED"}
    writer, reasons = decide_writer(Ctx.w2_runs, Ctx.w3_runs, Ctx.p_resume.get("P1"),
                                    Ctx.p_resume.get("P2"), Ctx.frame_ms)
    screen = decide_screen(Ctx.screen_runs)
    continuity = decide_continuity(Ctx.d1 or [], Ctx.d2 or []) if Ctx.d2 is not None else "unmeasured"
    entitlement = decide_entitlement(Ctx.t2, Ctx.t3)
    picks = (ROWS.get("D3") or {}).get("picks") or {}
    best = "; ".join(f"{name}={p['format'] or 'none'}" for name, p in picks.items()) or "none"
    line = (f"VERDICT writer={writer} screen_start={screen} continuity_key={continuity} "
            f"camera_entitlement={entitlement} best_format={best}")
    return line, {"writer": writer, "writer_reasons": reasons, "screen_start": screen,
                  "continuity_key": continuity, "camera_entitlement": entitlement, "best_format": picks}


def q0():
    return {row: {"needs": need, "this_run": (ROWS.get(row) or {}).get("outcome", "not requested")}
            for row, need in NEEDS.items()}


def print_table():
    print("\nrow  outcome   what")
    for row in ("H0", "B0", "D1", "D2", "D3", "T1", "T2", "T3", "W1", "W2", "W3", "M1", "M2", "S1", "S2",
                "P1", "P2", "V1", "X1", "A1"):
        r = ROWS.get(row)
        if r is None:
            continue
        what = r.get("reason") or ""
        if not what and "summary" in r:
            what = "; ".join(f"{k} {v['median']} [{v['min']}, {v['max']}] n={v['n']}"
                             for k, v in r["summary"].items() if v)
        elif not what and row == "D3":
            what = "; ".join(f"{n}: {p['format']}" for n, p in r["picks"].items())
        elif not what and row in ("T2", "T3"):
            what = f"frames {r.get('frames')}, black {r.get('black')}, mean luma {r.get('meanLuma')}"
        elif not what and row == "T1":
            what = (f"responsible {r['responsible'].get('responsibleName')}; video {r['video']}, audio "
                    f"{r['audio']}, screen preflight {r['screenPreflight']}")
        print(f"{row:4} {r.get('outcome', '?'):9} {what[:400]}")


def main():
    global MUTANT
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--groups", default=",".join(g for g in GROUPS if g != "aimed"))
    parser.add_argument("--camera", default=None)
    parser.add_argument("--mic", default="MacBook")
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--ask", action="store_true")
    parser.add_argument("--aimed", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--mutant", choices=MUTANTS)
    args = parser.parse_args()

    if args.selftest:
        MUTANT = args.mutant
        ok = selftest()
        if MUTANT:
            print(f"mutant {MUTANT}: {'survived' if ok else 'caught'}")
        return 0 if ok else 1
    if args.mutant:
        parser.error("--mutant needs --selftest")

    groups = [g.strip() for g in args.groups.split(",") if g.strip()]
    unknown = [g for g in groups if g not in GROUPS]
    if unknown:
        parser.error(f"unknown group(s): {', '.join(unknown)}")
    if args.aimed and "aimed" not in groups:
        groups.append("aimed")
    if CAMERA_GROUPS & set(groups) and "devices" not in groups:
        groups.insert(0, "devices")  # the camera and D3 come from D1
    if args.ask and "grant" not in groups:
        groups.insert(1, "grant")
    if not LIBRARY.exists():
        print(f"NOT PERFORMED: {LIBRARY} is missing — run `make rust` first", file=sys.stderr)
        return 2

    started = time.time()
    for folder in (WORK, RECORDINGS, ANSWERS):
        folder.mkdir(parents=True, exist_ok=True)
    rule_sha = hashlib.sha256(RULE_FILE.read_bytes()).hexdigest()
    snapshot("start")
    paths, row = build()
    ROWS["B0"] = row
    if paths is None:
        print(f"B0 FAILED: {row['reason']}", file=sys.stderr)
        RESULTS.write_text(json.dumps({"rows": ROWS, "failures": FAILURES}, indent=1))
        return 1
    for group in [g for g in GROUPS if g in groups]:
        print(f"-- {group}", flush=True)
        GROUP_FUNCS[group](paths, args)
        snapshot(f"after {group}")
    line, decided = verdict()
    ROWS["Q0"] = {"outcome": "ok", "table": q0()}
    results = {
        "command": "python3 tools/proof/camera_spike/camera_spike.py " + " ".join(sys.argv[1:]),
        "date": time.strftime("%Y-%m-%d %H:%M:%S"), "head": commit(), "rule_sha256": rule_sha,
        "python": platform.python_version(), "groups": groups, "runs": args.runs,
        "camera": Ctx.camera and Ctx.camera["localizedName"], "d3": Ctx.d3, "microphone": Ctx.mic,
        "rows": ROWS, "verdict": line, "decided": decided, "failures": FAILURES,
        "seconds": round(time.time() - started, 1),
    }
    RESULTS.write_text(json.dumps(results, indent=1))
    print_table()
    print(f"\nrule_sha256 {rule_sha}; head {results['head']}; {results['seconds']} s; results {RESULTS}")
    for failure in FAILURES:
        print(f"INSTRUMENT FAILURE: {failure}", file=sys.stderr)
    code = score(ROWS)
    print(line, file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
