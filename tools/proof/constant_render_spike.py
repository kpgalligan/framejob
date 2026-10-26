#!/usr/bin/env python3
"""#334's cost spike — what rendering every constant ×0.25/×0.5/×2/×4 Keep pitch
off clip offline through SR-6's `RampAudioRenderer` (option (a)) would cost:
render wall time and cache bytes per output minute, the silent-until-rendered
window from the edit to an audible preview, whether the render is free of
#334's steps and placed on the timeline, with an existing ramp for scale. No
product file is changed; #334 stays open.

    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/constant_render_spike.py [--selftest]
        [--mutant per-second|ideal-phase|order-off]
        [--groups app,render,quality,window] [--runs N] [--app PATH]

Groups run in the order app, render, quality, window. The work folder is
`tools/proof/work/constant-render/` (untracked): `fixtures/` (kept), `packages/`
(the W packages, pristine), `docs/` (the A and E documents), `window/` (per-run
copies), `renders/`, `exports/`, `probe-<group>/`, `framejob.log`, `state.json`
(what the app group made, read by quality and window) and `results.json` (rows
merged across invocations). The `app` group empties everything but `fixtures/`.

The fixtures: `long-sine.wav` (mono s16 48 kHz, 0.5·sin(2π·220·n/48000), 250 s,
`ramp_spike.write_wav`) and `long-speech.wav` (`media/speech.mov`'s audio
looped and cut to 250 s, stereo pcm_s16le 48 kHz), and `ramp_spike`'s 20 s sine
and clicks movies. A constant clip is ×N Keep pitch off from source in 1 s; the
ramp is RV1's shape, ×1 then [1 s, 3 s) linear to ×2.

app      one owned instance (`mcp.launch`, `bounded.child_env()`, stopped by its
         PID). W packages: per media × (×N, ramp) × 10 s and 60 s, the clip
         and an action with no end, saved and closed. A-<media>-x<N>: a fresh
         60 s document, `set_action_end {speed: N}` on an action over the whole
         clip, the seconds until a `.caf` lands (bound 300 s) and its bytes.
         E-x<N>: on the 20 s sine and clicks, "flat" (that action, end speed N)
         and "plain" (`set_speed` only), each exported `audio_wav`. D0. Every
         import waits for its cache pass (`settle`) before the next op.
render   (probe) R-<media>-x<N> / R-<media>-ramp: 60 s of output rendered from
         the long fixture over a 1 ms map, per run and median wall s and bytes
         per output minute, peak RSS; each long-sine render's step events.
quality  (probe) RC-off-x<N> and RC-off-x1 rendered on the 20 s fixtures. I1:
         RC-off-x1 on sine equals the fixture (`render_spike.identity`). Q-x<N>:
         steps on sine, max |render − ideal_sine| over [0.05 s, D − 0.05 s]
         (blind to a whole number of 1/220 s of source-in error; the clicks
         placement is the timing reading), the clicks placement and
         `varispeed_pass`, frames against `frames_target`, R's 60 s step
         counts, and E-x<N>'s flat and plain exports read the same way
         (channel 0, `ramp_spike.read_channel0`: ffmpeg's mono downmix scales
         two equal channels by √2).
window   (probe) W-<media>-x<N>-<L> / W-<media>-ramp-<L>: a fresh copy of each
         W package per run, the probe's `window` read (bound 300 s): landed_s,
         audible_s, caf_bytes, plan_bytes; every line held to `window_ok`.

H0 `host_snapshot()` at the start and after each group. B0 the probe build
(`-O`, whole-module). F0 the long fixtures (48 kHz, ≥ 241 s, speech 2 channels
and sine 1, sine sample 1000 within 1e-4 of its formula) and `ramp_spike.z0()`.
`--selftest` (no build, no app): S1 `per_minute`, S2 `ideal_sine` at a
source-in of 0.0025 s, S3 `window_ok`; each mutant must make it exit 1.

Exit 0 when every scored row passes (the rest are reported); 1 when an
instrument check fails (B0, F0, I1, D0, a `window_ok`, a probe crash or expiry,
a row the app could not answer); 2 when not performed (no ffmpeg/ffprobe, no
built app for `app`, no `state.json` for `window`).
"""

import argparse
import json
import math
import re
import shutil
import statistics
import sys
import time
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof"))
import ramp_proof as rp  # noqa: E402  (puts graphics_spike and ramp_spike on the path)
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import ramp_spike as rs  # noqa: E402
import render_spike as rsp  # noqa: E402
import retimed_audio_proof  # noqa: E402
import tree_copy  # noqa: E402
from export_offset_proof import read_ffmpeg  # noqa: E402

WORK = ROOT / "tools/proof/work/constant-render"
FIXTURES = WORK / "fixtures"
PACKAGES = WORK / "packages"
DOCS = WORK / "docs"
WINDOW = WORK / "window"
RENDERS = WORK / "renders"
EXPORTS = WORK / "exports"
LOG = WORK / "framejob.log"
STATE = WORK / "state.json"
RESULTS = WORK / "results.json"
SPEECH = ROOT / "tools/proof/media/speech.mov"
LONG = {"sine": FIXTURES / "long-sine.wav", "speech": FIXTURES / "long-speech.wav"}
MEDIA = ("sine", "speech")

SEC = 600_000
HZ = 48_000
RATES = (0.25, 0.5, 2.0, 4.0)
LONG_S = 250
OUTPUT_S = 60
WINDOW_S = (10, 60)
RUNS = 3
SOURCE_IN = rs.SOURCE_IN
BOUND_S = 300
CACHE_BOUND_S = 120
CALL_BOUND = 600
EDGE_S = 0.05
GROUPS = ["app", "render", "quality", "window"]
WALLS = {"app": 1500, "render": 1800, "quality": 900, "window": 2400}
MUTANTS = ["per-second", "ideal-phase", "order-off"]
MUTANT = None


def RAMP(length_s):
    return (False, 1.0, 2.0, "linear", 1.0, 3.0, length_s)


def label(rate):
    return f"x{rate:g}"


# ---- pure ------------------------------------------------------------------------


def per_minute(wall_s, bytes, frames):
    """(wall s, bytes) per output minute; output seconds = frames / 48 000."""
    seconds = frames / HZ
    per = seconds if MUTANT == "per-second" else seconds / 60
    return wall_s / per, bytes / per


def ideal_sine(rate, n, source_in_s=1.0):
    """The ideal ×rate render of the 220 Hz sine at output frame n."""
    if MUTANT == "ideal-phase":
        source_in_s = 0.0
    return 0.5 * math.sin(2 * math.pi * 220 * (source_in_s + rate * n / HZ))


def window_ok(line):
    """(ok, why): ok, no render in the item before the edit, and
    0 ≤ landed_s ≤ audible_s ≤ the job's bound_s."""
    if not line.get("ok"):
        return False, f"not ok: {line.get('error')}"
    if line.get("pre_edit_caf"):
        return False, "the item carried a render before the edit"
    landed, audible = line.get("landed_s"), line.get("audible_s")
    bound = line.get("bound_s", BOUND_S)
    if landed is None or audible is None:
        return False, f"landed {landed}, audible {audible} within {bound} s"
    if landed < 0 or audible > bound:
        return False, f"landed {landed} s, audible {audible} s outside [0, {bound}]"
    if MUTANT != "order-off" and audible < landed:
        return False, f"audible {audible} s before landed {landed} s"
    return True, "ok"


def spread(values):
    values = [v for v in values if v is not None]
    if not values:
        return None
    return {"median": statistics.median(values), "min": min(values), "max": max(values),
            "n": len(values)}


def host_snapshot():
    snap = dict(rs.host())
    ps = bounded.run(["ps", "-Ao", "pcpu,comm", "-r"], 30)
    lines = [line.strip() for line in (ps["stdout"] or "").splitlines()[1:] if line.strip()]
    snap["top_cpu"] = lines[:5]
    snap["builds"] = sum(1 for line in lines
                         if re.search(r"swift-frontend|xcodebuild|cargo|rustc", line))
    power = bounded.run(["pmset", "-g", "ps"], 30)
    snap["power"] = ((power["stdout"] or "").splitlines() or [""])[0].strip()
    return snap


# ---- the selftest ----------------------------------------------------------------


def selftest():
    results = []
    got = per_minute(1.5, 23_040_000, 2_880_000)
    results.append(("S1", got == (1.5, 23_040_000), f"per_minute → {got}"))
    at = 0.0025
    synthetic = [0.5 * math.sin(2 * math.pi * 220 * (at + 4.0 * n / HZ)) for n in range(4801)]
    exact = max(abs(synthetic[n] - ideal_sine(4.0, n, at)) for n in range(4800))
    shifted = max(abs(synthetic[n + 1] - ideal_sine(4.0, n, at)) for n in range(4800))
    results.append(("S2", exact <= 1e-9 and shifted > 0.01,
                    f"exact max |diff| {exact:.2e}, one sample late {shifted:.4f}"))
    good = {"ok": True, "pre_edit_caf": False, "landed_s": 1.0, "audible_s": 1.2,
            "bound_s": 300}
    bad = {"audible before landed": dict(good, audible_s=0.9),
           "pre-edit render": dict(good, pre_edit_caf=True),
           "past the bound": dict(good, audible_s=301.0),
           "not ok": dict(good, ok=False, error="x")}
    rejected = {name: not window_ok(line)[0] for name, line in bad.items()}
    results.append(("S3", window_ok(good)[0] and all(rejected.values()),
                    f"good accepted {window_ok(good)[0]}; rejected {rejected}"))
    for row, ok, detail in results:
        print(f"{row} {'pass' if ok else 'fail'} — {detail}", flush=True)
    passed = sum(1 for _, ok, _ in results if ok)
    print(f"{passed}/{len(results)}" + (f" — mutant {MUTANT}" if MUTANT else ""))
    return 0 if passed == len(results) else 1


# ---- bookkeeping -----------------------------------------------------------------


class Run:
    def __init__(self):
        self.rows = {}           # this invocation's rows: name → {status, detail, …}
        self.instrument = []     # failed instrument checks
        self.not_performed = []

    def row(self, name, status, detail, **data):
        self.rows[name] = dict(data, status=status, detail=detail)
        print(f"{name} {status} — {detail}", flush=True)
        if status == "FAIL":
            self.instrument.append(name)


def load(path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def save_results(run, hosts, args):
    results = load(RESULTS, {"rows": {}, "host": []})
    results["rows"].update(run.rows)
    results["host"] += hosts
    results.setdefault("invocations", []).append({
        "groups": args.groups, "runs": args.runs, "commit": rs.commit(),
        "app": str(args.app or ""), "probe": f"{rs.PROBE_DIR}/constant-render-probe",
        "at": time.strftime("%Y-%m-%d %H:%M:%S")})
    RESULTS.write_text(json.dumps(results, indent=1, default=str))


def tools_there():
    return all(shutil.which(t) for t in ("ffmpeg", "ffprobe"))


# ---- the fixtures ----------------------------------------------------------------


def make_long():
    FIXTURES.mkdir(parents=True, exist_ok=True)
    if not LONG["sine"].exists():
        partial = LONG["sine"].with_suffix(".partial.wav")
        rs.write_wav(partial, (0.5 * math.sin(2 * math.pi * 220 * n / HZ)
                               for n in range(LONG_S * HZ)))
        partial.rename(LONG["sine"])
    if not LONG["speech"].exists():
        partial = LONG["speech"].with_suffix(".partial.wav")
        rs.run(["ffmpeg", "-v", "error", "-y", "-stream_loop", "-1", "-i", SPEECH, "-map",
                "0:a:0", "-t", str(LONG_S), "-c:a", "pcm_s16le", "-ar", str(HZ), "-ac", "2",
                partial], 300)
        partial.rename(LONG["speech"])


def probe_stream(path):
    ran = rs.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
                  "stream=sample_rate,channels,duration", "-of", "json", path], 60)
    stream = json.loads(ran["stdout"])["streams"][0]
    return int(stream["sample_rate"]), int(stream["channels"]), float(stream["duration"])


def f0(run):
    problems, parts = [], []
    try:
        make_long()
        for media, want_channels in (("sine", 1), ("speech", 2)):
            rate, channels, duration = probe_stream(LONG[media])
            parts.append(f"{media} {rate} Hz {channels} ch {duration:.3f} s")
            if rate != HZ or channels != want_channels or duration < 241:
                problems.append(f"{media}: {rate} Hz, {channels} ch, {duration} s")
        with wave.open(str(LONG["sine"]), "rb") as w:
            w.setpos(1000)
            value = int.from_bytes(w.readframes(1), "little", signed=True) / 32767
        want = 0.5 * math.sin(2 * math.pi * 220 * 1000 / HZ)
        parts.append(f"sine[1000] {value:.6f} (formula {want:.6f})")
        if abs(value - want) > 1e-4:
            problems.append(f"sine sample 1000 {value} ≠ {want}")
        rs.make_fixtures(False)
        ok, detail = rs.z0()
        parts.append(f"z0: {detail}")
        if not ok:
            problems.append(f"z0: {detail}")
    except Exception as error:  # a broken instrument is a FAIL
        problems.append(f"{type(error).__name__}: {error}")
    run.row("F0", "FAIL" if problems else "ok", "; ".join(problems or parts))
    return not problems


# ---- the app group ---------------------------------------------------------------


def settle(doc, media):
    """Waits (bound `CACHE_BOUND_S`) for the import's cache pass — the
    `peaks`, `sync` and `speech` markers in the package — so passes never
    pile up: twenty unsettled imports of the 250 s fixtures, saved and closed
    back to back, left every `AVAssetReader` in the instance blocked, the
    ramp render's with them (Debug and Release, 2026-10-25)."""
    cache = Path(doc.path) / "cache"
    started = time.monotonic()
    while time.monotonic() - started < CACHE_BOUND_S:
        if all((cache / kind / f"{media}.complete.json").exists()
               for kind in ("peaks", "sync", "speech")):
            return
        time.sleep(0.05)
    raise RuntimeError(f"media {media}'s cache pass did not finish within {CACHE_BOUND_S} s")


def long_clip(doc, path, length, rate):
    """`ramp_proof.Doc.fixture_clip`'s op sequence over `path`: at 0 from
    source in 1 s, ×rate Keep pitch off, cut to `length`; (clip, media)."""
    media = doc.must("import_media", path=str(path))["media"]
    settle(doc, media)
    track = doc.project()["tracks"][0]["id"]
    clip = doc.must("add_clip", track=track, media=media, at=0)["new_clips"][0]
    doc.must("trim_start", clip=clip, to=SOURCE_IN)
    doc.must("move_clip", clips=[clip], delta=-SOURCE_IN)
    doc.must("set_speed", clip=clip, rate=rate, keep_pitch=False)
    doc.must("trim_end", clip=clip, to=length)
    placed = doc.clip(clip)
    if (placed["start"], placed["duration"], placed["source"].get("in")) != (0, length, SOURCE_IN):
        raise RuntimeError(f"the clip landed as {placed}")
    return clip, media


def new_doc(client, folder, name):
    rp.WORK = folder
    folder.mkdir(parents=True, exist_ok=True)
    doc = rp.Doc(client, name)
    doc.canvas()
    return doc


def w_package(client, media, rate, length_s):
    """A pristine W package (saved, closed): its {package, clip, action, speed}."""
    name = f"W-{media}-{'ramp' if rate is None else label(rate)}-{length_s}"
    doc = new_doc(client, PACKAGES, name)
    try:
        clip, _ = long_clip(doc, LONG[media], length_s * SEC, 1.0 if rate is None else rate)
        if rate is None:
            action = doc.action(clip, SEC, 2 * SEC)
            made = next(a for a in doc.clip(clip)["actions"] if a["id"] == action)
            if made.get("curve", "linear") != "linear":
                doc.must("set_action", clip=clip, action=action, curve="linear")
        else:
            action = doc.action(clip, 0, length_s * SEC)
        doc.must("save_project")
        return name, {"package": doc.path, "clip": clip, "action": action,
                      "speed": 2.0 if rate is None else rate, "media": media,
                      "length_s": length_s}
    finally:
        doc.close()


def a_run(client, media, rate, k):
    """(seconds, bytes) from `set_action_end` until one `.caf` lands."""
    doc = new_doc(client, DOCS, f"A-{media}-{label(rate)}-{k}")
    try:
        clip, _ = long_clip(doc, LONG[media], OUTPUT_S * SEC, rate)
        action = doc.action(clip, 0, OUTPUT_S * SEC)
        started = time.monotonic()
        rp.ramp_end(doc, clip, action, speed=rate)
        landed = []
        while time.monotonic() - started < BOUND_S:
            landed = [n for n in doc.renders() if n.endswith(".caf")]
            if landed:
                break
            time.sleep(0.01)
        seconds = time.monotonic() - started
        if not landed:
            raise RuntimeError(f"no .caf within {BOUND_S} s ({doc.renders()})")
        size = (Path(doc.path) / "cache" / "ramp-audio" / landed[0]).stat().st_size
        return seconds, size
    finally:
        doc.close()


def e_export(client, rate, fixture, kind):
    """E's export: (path, timeline ticks)."""
    length = round(rs.CONTROLS[f"C-off-{label(rate)}"][2] * SEC)
    doc = new_doc(client, DOCS, f"E-{label(rate)}-{kind}-{fixture}")
    try:
        clip, media = doc.fixture_clip(fixture, length, rate, False)
        settle(doc, media)
        if kind == "flat":
            action = doc.action(clip, 0, length)
            rp.ramp_end(doc, clip, action, speed=rate)
        return str(doc.export("audio_wav", f"E-{label(rate)}-{kind}-{fixture}")), length
    finally:
        doc.close()


def app_group(run, binary, runs):
    started = time.monotonic()
    state = {"packages": {}, "e": {}}
    errors = []
    launched = mcp.launch(str(binary), env=bounded.child_env(), log_path=str(LOG),
                          timeout=CALL_BOUND)
    up = launched.client is not None
    a_rows = {}

    def in_time():
        if time.monotonic() - started <= WALLS["app"]:
            return True
        expired = f"the app group ran past {WALLS['app']} s"
        if expired not in errors:
            errors.append(expired)
        return False

    try:
        if not up:
            errors.append(f"the app did not listen at {launched.socket_path}")
        else:
            client = launched.client
            print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
            rp.EXPORTS = EXPORTS
            for media in MEDIA:
                for rate in list(RATES) + [None]:
                    for length_s in WINDOW_S:
                        if not in_time():
                            break
                        try:
                            name, made = w_package(client, media, rate, length_s)
                            state["packages"][name] = made
                        except Exception as error:  # an instrument that breaks is a FAIL
                            errors.append(f"W {media} {rate} {length_s}: {error}")
            print(f"  {len(state['packages'])} W packages", flush=True)
            for k in range(1, runs + 1):
                for media in MEDIA:
                    for rate in RATES:
                        if not in_time():
                            break
                        name = f"A-{media}-{label(rate)}"
                        try:
                            seconds, size = a_run(client, media, rate, k)
                            a_rows.setdefault(name, []).append((seconds, size))
                            print(f"  {name} run {k}: {seconds:.3f} s, {size} bytes", flush=True)
                        except Exception as error:  # an instrument that breaks is a FAIL
                            errors.append(f"{name} run {k}: {error}")
            for rate in RATES:
                for fixture in ("sine", "clicks"):
                    for kind in ("flat", "plain"):
                        if not in_time():
                            break
                        tag = f"E-{label(rate)}-{kind}-{fixture}"
                        try:
                            path, length = e_export(client, rate, fixture, kind)
                            state["e"][tag] = {"path": path, "length": length}
                            print(f"  {tag}: {length} ticks", flush=True)
                        except Exception as error:  # an instrument that breaks is a FAIL
                            errors.append(f"{tag}: {error}")
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    STATE.write_text(json.dumps(state, indent=1))
    found = rp.complaints(LOG)
    run.row("D0", "ok" if up and not found else "FAIL",
            f"listening {up}; complaints {found[:5]}")
    for name, got in a_rows.items():
        per = [per_minute(s, b, OUTPUT_S * HZ) for s, b in got]
        run.row(name, "reported",
                f"edit → landed {[round(s, 3) for s, _ in got]} s, {[b for _, b in got]} bytes "
                f"over {len(got)} runs; median {statistics.median(s for s, _ in got):.3f} s",
                seconds=[s for s, _ in got], bytes=[b for _, b in got],
                wall_per_min=spread([p[0] for p in per]),
                bytes_per_min=spread([p[1] for p in per]))
    if errors:
        run.row("APP", "FAIL", "; ".join(errors[:12]))
    print(f"  app group {time.monotonic() - started:.0f} s", flush=True)


# ---- the probe -------------------------------------------------------------------


def probe(run):
    shader, why = rp.build_shader(str(rs.PROBE_DIR))
    binary = None
    if shader is not None:
        binary, why = rs.build_probe(optimize=True, name="constant-render-probe", wmo=True)
    run.row("B0", "ok" if binary else "FAIL", why or "built")
    return binary


def probe_run(run, binary, group, probe_group, jobs):
    work = WORK / f"probe-{group}"
    work.mkdir(parents=True, exist_ok=True)
    lines, why = rs.run_group(binary, probe_group, jobs, work=work,
                              walls={probe_group: WALLS[group]})
    if why:
        run.row(f"P-{group}", "FAIL", why)
    return lines


def render_job(name, source, ramp, length):
    clip, source_ticks = rsp.rendered_map(ramp, length)
    destination = RENDERS / f"{name}.caf"
    destination.unlink(missing_ok=True)
    return {"name": name, "source": str(source), "clip_ticks": clip, "source_ticks": source_ticks,
            "keep_pitch": False, "destination": str(destination)}


def sine_events(x, length_s):
    return rsp.click_events(rsp.dense_scan(x, HZ, length_s), 0)


def render_group(run, binary, runs):
    RENDERS.mkdir(parents=True, exist_ok=True)
    jobs, rows = [], {}
    for k in range(1, runs + 1):
        for media in MEDIA:
            for rate in list(RATES) + [None]:
                row = f"R-{media}-{'ramp' if rate is None else label(rate)}"
                ramp = RAMP(OUTPUT_S) if rate is None else rsp.control_ramp(False, rate, OUTPUT_S)
                jobs.append(render_job(f"{row}-{k}", LONG[media], ramp, OUTPUT_S * SEC))
                rows.setdefault(row, []).append(f"{row}-{k}")
    lines = probe_run(run, binary, "render", "render", jobs)
    for row, names in rows.items():
        got = [lines.get((n, "render")) for n in names]
        bad = [n for n, line in zip(names, got) if not line or not line.get("ok")]
        if bad:
            run.row(row, "FAIL", f"no render for {bad}: "
                    + str([(line or {}).get("error") for line in got][:2]))
            continue
        per = [per_minute(line["wall_s"], line["bytes"], line["frames"]) for line in got]
        events = None
        if row.startswith("R-sine"):
            events = []
            for line in got:
                x, _ = read_ffmpeg(Path(line["path"]))
                events.append(len(sine_events(x, float(OUTPUT_S))))
        walls, sizes = [p[0] for p in per], [p[1] for p in per]
        run.row(row, "reported",
                f"wall s/min {[round(w, 3) for w in walls]} (median "
                f"{statistics.median(walls):.3f}); bytes/min {[round(b) for b in sizes]}; "
                f"frames {[line['frames'] for line in got]}; channels "
                f"{got[0]['channels']}; peak RSS {[line['peak_rss_bytes'] for line in got]}"
                + ("" if events is None else f"; step events {events}"),
                wall_s=[line["wall_s"] for line in got], bytes=[line["bytes"] for line in got],
                frames=[line["frames"] for line in got], channels=got[0]["channels"],
                wall_per_min=spread(walls), bytes_per_min=spread(sizes),
                peak_rss=[line["peak_rss_bytes"] for line in got], events=events)


def readings(x, rate, length_ticks, fixture):
    """Q's readings of one signal: steps and max |diff| on sine, placement on
    clicks; frames against the target."""
    out = {"frames": len(x), "target": retimed_audio_proof.frames_target(length_ticks)}
    length_s = length_ticks / SEC
    if fixture == "sine":
        out["steps"] = len(sine_events(x, length_s))
        lo, hi = int(EDGE_S * HZ), min(len(x), int((length_s - EDGE_S) * HZ))
        out["max_diff"] = max((abs(x[n] - ideal_sine(rate, n)) for n in range(lo, hi)),
                              default=None)
    else:
        s = rsp.place_ideal(x, HZ, rsp.variants()[f"RC-off-{label(rate)}"])
        out["placement"] = rp.place_text(s)
        out["varispeed_pass"] = rs.varispeed_pass(s)
    return out


def text(r):
    parts = [f"frames {r['frames']} of {r['target']}"]
    if "steps" in r:
        parts.append(f"steps {r['steps']}, max |diff| "
                     + ("—" if r["max_diff"] is None else f"{r['max_diff']:.6f}"))
    if "placement" in r:
        parts.append(f"{r['placement']} (varispeed_pass {r['varispeed_pass']})")
    return ", ".join(parts)


def quality_group(run, binary):
    RENDERS.mkdir(parents=True, exist_ok=True)
    everything = rsp.variants()
    jobs = []
    for rate in list(RATES) + [1.0]:
        v = everything[f"RC-off-{label(rate)}"]
        for fixture in ("sine", "clicks"):
            destination = RENDERS / f"Q-{label(rate)}@{fixture}.caf"
            destination.unlink(missing_ok=True)
            jobs.append({"name": f"Q-{label(rate)}@{fixture}",
                         "source": str(rs.FIXTURES / rs.FIXTURE_FILES[fixture]),
                         "clip_ticks": v["map"][0], "source_ticks": v["map"][1],
                         "keep_pitch": False, "destination": str(destination)})
    lines = probe_run(run, binary, "quality", "render", jobs)
    fixture_sine = read_ffmpeg(rs.FIXTURES / rs.FIXTURE_FILES["sine"])[0]
    one = lines.get(("Q-x1@sine", "render"))
    if one and one.get("ok"):
        v = everything["RC-off-x1"]
        n = round(v["length"] / rsp.TICKS_PER_FRAME)
        offset = round(SOURCE_IN / rsp.TICKS_PER_FRAME)
        ok, worst = rsp.identity(read_ffmpeg(Path(one["path"]))[0], fixture_sine, offset, n)
        run.row("I1", "ok" if ok else "FAIL",
                f"RC-off-x1's render against the sine fixture over {n} frames: max |diff| "
                + ("—" if worst is None else f"{worst:.2e}"))
    else:
        run.row("I1", "FAIL", f"no RC-off-x1 render: {(one or {}).get('error')}")
    state = load(STATE, {})
    earlier = dict(load(RESULTS, {"rows": {}})["rows"], **run.rows)
    for rate in RATES:
        v = everything[f"RC-off-{label(rate)}"]
        parts, data = [], {}
        for fixture in ("sine", "clicks"):
            line = lines.get((f"Q-{label(rate)}@{fixture}", "render"))
            if not line or not line.get("ok"):
                run.row(f"Q-{label(rate)}", "FAIL",
                        f"no {fixture} render: {(line or {}).get('error')}")
                break
            x, _ = read_ffmpeg(Path(line["path"]))
            r = readings(x, rate, v["length"], fixture)
            r["frames"] = line["frames"]
            data[f"render-{fixture}"] = r
            parts.append(f"render {fixture}: {text(r)}")
        else:
            long_steps = {f"R-sine-{label(rate)}": earlier.get(f"R-sine-{label(rate)}", {})
                          .get("events")}
            data["long_steps"] = long_steps
            parts.append(f"60 s long-sine steps {long_steps}")
            for kind in ("flat", "plain"):
                for fixture in ("sine", "clicks"):
                    got = state.get("e", {}).get(f"E-{label(rate)}-{kind}-{fixture}")
                    if not got:
                        parts.append(f"E {kind} {fixture}: not made (run the app group)")
                        continue
                    x, _ = rs.read_channel0(Path(got["path"]))
                    r = readings(x, rate, got["length"], fixture)
                    data[f"E-{kind}-{fixture}"] = r
                    parts.append(f"E {kind} {fixture}: {text(r)}")
            run.row(f"Q-{label(rate)}", "reported", "; ".join(parts), **data)


def window_group(run, binary, runs, state):
    WINDOW.mkdir(parents=True, exist_ok=True)
    jobs, rows = [], {}
    for k in range(1, runs + 1):
        for name, made in state["packages"].items():
            copy = WINDOW / f"{name}-{k}.framejob"
            shutil.rmtree(copy, ignore_errors=True)
            shutil.copytree(made["package"], copy)
            shutil.rmtree(copy / "cache" / "ramp-audio", ignore_errors=True)
            jobs.append({"name": f"{name}-{k}", "project": str(copy), "clip": made["clip"],
                         "action": made["action"], "speed": made["speed"],
                         "bound_s": BOUND_S})
            rows.setdefault(name, []).append(f"{name}-{k}")
    lines = probe_run(run, binary, "window", "window", jobs)
    bad = []
    for row, names in rows.items():
        got = []
        for n in names:
            line = lines.get((n, "window"))
            if line is None:
                bad.append(f"{n}: no line")
                continue
            line = dict(line, bound_s=BOUND_S)
            ok, why = window_ok(line)
            if not ok:
                bad.append(f"{n}: {why}")
            got.append(line)
        fields = {f: [line.get(f) for line in got]
                  for f in ("landed_s", "audible_s", "caf_bytes", "plan_bytes")}
        med = {f: spread(v) for f, v in fields.items()}
        audible = (med["audible_s"] or {}).get("median")
        run.row(row, "reported",
                f"landed {[None if v is None else round(v, 3) for v in fields['landed_s']]} s, "
                f"audible {[None if v is None else round(v, 3) for v in fields['audible_s']]} s "
                f"(median {'—' if audible is None else f'{audible:.3f}'}), caf "
                f"{fields['caf_bytes']} bytes, plan {fields['plan_bytes']} bytes "
                f"over {len(got)} runs", median=med, **fields)
    run.row("WOK", "FAIL" if bad else "ok",
            "; ".join(bad[:10]) if bad else f"window_ok holds for all {len(jobs)} lines")


# ---- main ------------------------------------------------------------------------


def main():
    global MUTANT
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--mutant", choices=MUTANTS, default=None)
    parser.add_argument("--groups", default=",".join(GROUPS))
    parser.add_argument("--runs", type=int, default=RUNS)
    parser.add_argument("--app", type=Path, default=None)
    args = parser.parse_args()
    MUTANT = args.mutant
    if args.selftest:
        return selftest()
    chosen = [g for g in GROUPS if g in args.groups.split(",")]
    if not tools_there():
        print("not performed: ffmpeg and ffprobe are needed")
        return 2
    binary = None
    if "app" in chosen:
        binary = args.app or proof_app.binary()
        if not Path(binary).exists():
            print(f"not performed: the app is not built: {binary}")
            return 2
    if "window" in chosen and "app" not in chosen and not STATE.exists():
        print(f"not performed: no {STATE} (run the app group first)")
        return 2
    if "app" in chosen:
        for child in WORK.iterdir() if WORK.exists() else []:
            if child.name != "fixtures":
                if child.is_dir():
                    tree_copy.remove_tree(str(child))
                else:
                    child.unlink()
    WORK.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    run = Run()
    hosts = [dict(host_snapshot(), when="start")]
    print(f"#334 constant render cost — groups {chosen}, {args.runs} runs", flush=True)
    print(f"  H0 start: load {hosts[0]['load']}, builds {hosts[0]['builds']}, "
          f"power {hosts[0]['power']!r}, top {hosts[0]['top_cpu'][:3]}", flush=True)
    if f0(run):
        probe_binary = None
        for group in chosen:
            group_started = time.monotonic()
            print(f"-- {group}", flush=True)
            try:
                if group == "app":
                    try:
                        app_group(run, binary, args.runs)
                    except proof_app.StaleApp as error:
                        print(f"not performed: {error}")
                        run.not_performed.append(f"app: {error}")
                else:
                    if probe_binary is None:
                        probe_binary = probe(run)
                        if probe_binary is None:
                            break
                    if group == "render":
                        render_group(run, probe_binary, args.runs)
                    elif group == "quality":
                        quality_group(run, probe_binary)
                    else:
                        state = load(STATE, {})
                        if not state.get("packages"):
                            run.not_performed.append("window: no W packages in state.json")
                        else:
                            window_group(run, probe_binary, args.runs, state)
            except Exception as error:  # a broken instrument is a FAIL, not an exit
                run.row(f"G-{group}", "FAIL", f"{type(error).__name__}: {error}")
            snap = dict(host_snapshot(), when=f"after {group}")
            hosts.append(snap)
            print(f"  H0 after {group} ({time.monotonic() - group_started:.0f} s): load "
                  f"{snap['load']}, builds {snap['builds']}, top {snap['top_cpu'][:3]}",
                  flush=True)
    save_results(run, hosts, args)
    print("\n| row | status |")
    print("|---|---|")
    for name, row in run.rows.items():
        print(f"| {name} | {row['status']} |")
    print(f"{len(run.rows)} rows in {time.monotonic() - started:.0f} s; instrument failures "
          f"{run.instrument}; not performed {run.not_performed}")
    if run.instrument:
        return 1
    return 2 if run.not_performed else 0


if __name__ == "__main__":
    sys.exit(main())
