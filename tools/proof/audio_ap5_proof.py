"""Road map "audio" AP5 — voice isolation (spec §11 AU-50…AU-57): the probe
over `app/Sources`, its mutants, and exports from an instance of its own.

    python3 tools/proof/audio_ap5_proof.py             # P rows, then I rows on an own instance
    python3 tools/proof/audio_ap5_proof.py --probe     # P1–P9 and P2b, no instance
    python3 tools/proof/audio_ap5_proof.py --mutants   # the ten mutants, each against its row
    python3 tools/proof/audio_ap5_proof.py --instance  # I0–I10 and I1b alone

The instance is `proof_app`'s app (Debug by default, `RC_PROOF_APP=release`
for the record), launched with `-RCDevRampRenderHold 2` on a scratch socket
and stopped by its own pid. The owner's recording `samples/Rode-usb-mic.m4a`
(30.3 s, mono 48 kHz) is every row's media; missing, every row that needs it
FAILs. Needs `ffmpeg` and numpy. Exports are `audio_wav`, decoded to float by
ffmpeg, left channel. Every project raises the clip's volume ×4 (+12 dB) so a
16-bit export's quantisation sits ≥ 60 dB under the recording; the fader is
after the tap, so it changes no comparison between two exports.

**Probe rows** (`audio_ap5_probe.swift`, compiled AS `main.swift` over
`app/Sources` on `swift_build.py`'s line; a build failure is a scored FAIL):
P1 pending is dry with no tap; P2 a synthetic render read sample for sample at
the placement, alone and with the noise reducer's lead; P2b the wet offset off
the 48 kHz grid; P3 Amount 0.5 and 0.25 as a crossfade; P4 no request for a
time-scaled, ramped, freeze or pending-reverse segment; P5 the render's lag 0
on the recording; P6 a window against the whole file's render ≤ −40 dB; P7 the
name; P8 the export waits; P9 a failure reaches the owner once, on main.

**Instance rows:**
- I0: the instance's log has no `Frame Job: ` line (the parity check).
- I1: a clip from 8 s placed at 2 s, isolation 1 against 0: |lag| ≤ 0.5
  sample (cross-correlation, parabolic peak).
- I1b: the same on a 29.97 fps project (`set_canvas {fps: [30000, 1001]}`),
  the clip at frame 61 (1,221,220 ticks) from frame 240 (4,804,800 ticks):
  an offset of 286,686.4 samples, off the grid.
- I2: the whole recording: the pause floor (S2's 400 ms classifier on the
  dry: pause within 6 dB of the 10th percentile, speech 20 dB over it) at
  least 9 dB lower; speech per octave 63 Hz–8 kHz and broadband within
  ±0.5 dB.
- I3: Amount 0.5 against 0.5·(I2's dry + I2's isolated): residual ≤ −60 dB.
- I4: an export sent straight after a fresh window's `set_audio` (the render
  held 2 s) holds the isolated floor (≥ 9 dB under its dry).
- I5: `trim_start` 1 s: a new `.caf` lands in `cache/isolated/`, the old one
  is pruned, and the new export's lag against its dry is 0 (≤ 0.5).
- I6: a reversed clip (the reverse waited for): lag ≤ 0.5; its floor drop is
  reported.
- I7: ×2 with Keep pitch on and off: no `.caf` in `cache/isolated/`; Keep
  pitch off's export equals isolation 0's over the common length, sample for
  sample; Keep pitch on's (AVFoundation's spectral time-pitch, which is not
  deterministic between two exports) keeps isolation 0's pause floor within
  ±1 dB, a second dry export's difference reported.
- I8: `paste_attributes` carries `isolation` onto another clip.
- I9: `set_audio {isolation: 1.5}` is refused with the core's sentence.
- I10: `set_audio {isolation: 0}` on an isolated clip: `get_project` holds no
  `isolation` key and the export equals I2's dry, sample for sample.

**Mutants** (`--mutants`; each over its own copy of `app/Sources`, killed when
its named row fails): latency-kept (P5), no-preroll (P6), amount-swapped
(P3), no-track-lead (P2), pending-silent (P1), scaled-isolated (P4),
export-no-wait (P8), window-not-keyed (P7), split-rounding (P2b),
failure-silent (P9). split-rounding is also I1b's; the instance rows are not
re-run per mutant.

Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff all pass.
"""

import argparse
import math
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE / "graphics_spike"))
sys.path.insert(0, str(HERE))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/audio_ap5"
RODE = ROOT / "samples/Rode-usb-mic.m4a"
SR = 48000
SEC = 600_000
HOLD_S = 2
CALL_BOUND = 600
VOLUME = 4.0
PROBE_ROWS = ["P1", "P2", "P2b", "P3", "P4", "P5", "P6", "P7", "P8", "P9"]
OCTAVES = [63, 125, 250, 500, 1000, 2000, 4000, 8000]

rows = []


def row(row_id, ok, detail):
    rows.append((row_id, bool(ok)))
    print(f"{row_id} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


# ---- the probe -------------------------------------------------------------------

def build_probe(sources, name):
    out = WORK / name
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "audio_ap5_probe.swift", entry)
    blank = out / "Blank.mp4"
    if not blank.exists():
        shutil.copyfile(ROOT / "app/Resources/Blank.mp4", blank)
    binary = out / "audio-ap5-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [str(entry)], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc: " + " | ".join((errors or list(error.diagnostics) or [str(error)])[:6])
    return binary, ""


def run_probe(sources, name):
    """({row: (passed, detail)}, problem) — None rows when it did not build."""
    binary, problem = build_probe(sources, name)
    if binary is None:
        return None, problem
    scratch = WORK / name / "scratch"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    try:
        result = subprocess.run([str(binary), str(scratch), str(RODE)], capture_output=True,
                                text=True, timeout=900, cwd=str(binary.parent))
    except subprocess.TimeoutExpired:
        return {}, "the probe ran past 900 s and was killed"
    found = {}
    for line in result.stdout.splitlines():
        parts = line.split(" ", 2)
        if len(parts) >= 2 and parts[0] in ("ok", "FAIL"):
            detail = parts[2][2:] if len(parts) > 2 and parts[2].startswith("— ") else ""
            found[parts[1]] = (parts[0] == "ok", detail)
    return found, result.stderr.strip()[-600:]


def probe_rows(sources=ROOT / "app/Sources"):
    found, problem = run_probe(sources, "probe")
    for name in PROBE_ROWS:
        if found is None:
            row(name, False, "the probe does not build: " + problem)
        elif name not in found:
            row(name, False, "the probe did not answer" + (f": {problem}" if problem else ""))
        else:
            row(name, *found[name])


# ---- mutants ---------------------------------------------------------------------

SILENT_BUILDER_OLD = (
    "                let isolation = isolated.isEmpty\n"
    "                    ? nil\n"
    "                    : AudioIsolationTrack(\n"
    "                        segments: family.segments, shift: shift, dsp: dsp, renders: isolated)\n")
SILENT_BUILDER_NEW = (
    "                let isolation = dsp.isolates\n"
    "                    ? AudioIsolationTrack(\n"
    "                        segments: family.segments, shift: shift, dsp: dsp, renders: isolated)\n"
    "                    : nil\n")

# name, rows any one of which must fail, [(file, before exactly once, after)].
MUTANTS = [
    ("latency-kept", ["P5"], [
        ("IsolationRenderer.swift",
         "            let discard = preroll + Int64(latencyFrames)\n",
         "            let discard = preroll\n")]),
    ("no-preroll", ["P6"], [
        ("IsolationRenderer.swift",
         "        let preroll = min(prerollFrames, window.firstFrame)\n",
         "        let preroll: Int64 = 0\n")]),
    ("amount-swapped", ["P3"], [
        ("AudioIsolation.swift",
         "                        for i in 0..<n { out[i] += a * (wet[i] - out[i]) }\n",
         "                        for i in 0..<n { out[i] = wet[i] + a * (out[i] - wet[i]) }\n")]),
    ("no-track-lead", ["P2"], [
        ("AudioIsolation.swift",
         "CompositionBuilder.placement(of: s, shift: shift)",
         "CompositionBuilder.placement(of: s, shift: .none)")]),
    # A pending render plays SILENT: an empty isolation pass still earns a
    # tap, and the tap zeroes a buffer when it has no span.
    ("pending-silent", ["P1"], [
        ("CompositionBuilder+AudioTracks.swift", SILENT_BUILDER_OLD, SILENT_BUILDER_NEW),
        ("AudioTap.swift",
         "        guard track.isActive || !(isolation?.isEmpty ?? true) || meter != nil else { return nil }\n",
         "        guard track.isActive || isolation != nil || meter != nil else { return nil }\n"),
        ("AudioTap.swift",
         "        if isolates, let isolation = isolation {\n",
         "        if isolation?.isEmpty ?? false {\n"
         "            for index in 0..<count {\n"
         "                if let data = list[index].mData {\n"
         "                    memset(data, 0, Int(list[index].mDataByteSize))\n"
         "                }\n"
         "            }\n"
         "        }\n"
         "        if isolates, let isolation = isolation {\n")]),
    ("scaled-isolated", ["P4"], [
        ("IsolationCache.swift",
         "        s.duration > 0 && s.ramp == nil && !s.isTimeScaled\n",
         "        s.duration > 0 && s.ramp == nil\n")]),
    ("export-no-wait", ["P8"], [
        ("Exporter+RampAudio.swift",
         "            + IsolationCache.requests(plan: plan, dsp: dsp, urls: urls, reverse: reverse)\n",
         "")]),
    ("window-not-keyed", ["P7"], [
        ("IsolationCache.swift",
         '"|p\\(IsolationRenderer.prerollFrames)|w\\(window.firstFrame):\\(window.endFrame)"',
         '"|p\\(IsolationRenderer.prerollFrames)"')]),
    ("split-rounding", ["P2b"], [
        ("IsolationCache.swift",
         "        frame(ofTicks: sourceIn - at) - window.firstFrame\n",
         "        frame(ofTicks: sourceIn) - frame(ofTicks: at) - window.firstFrame\n")]),
    ("failure-silent", ["P9"], [
        ("RampAudioRenders.swift",
         "                failures[request.destination.path] = message\n"
         "                called = settledOwnersLocked(request.destination)\n",
         "                failures[request.destination.path] = message\n")]),
]


def mutants():
    killed = 0
    sources = ROOT / "app/Sources"
    for name, targets, edits in MUTANTS:
        tree = WORK / f"mutant-{name}" / "Sources"
        shutil.rmtree(tree, ignore_errors=True)
        shutil.copytree(sources, tree)
        problem = None
        for file, before, after in edits:
            path = tree / file
            text = path.read_text()
            if text.count(before) != 1:
                problem = f"an anchor is not found exactly once in {file}"
                break
            path.write_text(text.replace(before, after))
        if problem:
            row(f"mutant {name}", False, problem)
            continue
        found, why = run_probe(tree, f"mutant-{name}")
        if found is None:
            row(f"mutant {name}", False, "did not build: " + why)
            continue
        failing = sorted(r for r in PROBE_ROWS if not found.get(r, (False, ""))[0])
        dead = any(found.get(r, (True, ""))[0] is False for r in targets)
        killed += dead
        row(f"mutant {name}", dead, f"killed by {'/'.join(targets)}: {dead}; failing rows: "
            + (", ".join(failing) or "none"))
    print(f"{killed}/{len(MUTANTS)} mutants killed", flush=True)
    return killed == len(MUTANTS)


# ---- the instance ----------------------------------------------------------------

def attempt(client, tool, arguments):
    try:
        return {"ok": True, "reply": client.call_with(tool, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}


class Doc:
    """One project file; every call addressed to it."""

    def __init__(self, client, name):
        self.client = client
        (WORK / "projects").mkdir(parents=True, exist_ok=True)
        self.path = str(WORK / "projects" / f"{name}.framejob")
        got = attempt(client, "new_project", {"path": self.path})
        if not got["ok"]:
            raise RuntimeError(f"new_project {self.path}: {got['error']}")

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=self.path))

    def must(self, tool, **arguments):
        got = self.call(tool, **arguments)
        if not got["ok"]:
            raise RuntimeError(f"{tool} {arguments}: {got['error']}")
        return got["reply"]

    def project(self):
        return self.must("get_project")["project"]

    def clip(self, clip):
        return next(c for c in self.project()["clips"] if c["id"] == clip)

    def rode(self, at=0, source_in=0, track_index=0, media=None):
        """The recording as a clip from `source_in` placed at `at`, volume ×4;
        `media` an id it was already imported as."""
        if media is None:
            media = self.must("import_media", path=str(RODE))["media"]
        track = self.project()["tracks"][track_index]["id"]
        # From 0 when it is trimmed (the trim moves its start), else at `at`.
        first = 0 if source_in else at
        clip = self.must("add_clip", track=track, media=media, at=first)["new_clips"][0]
        if source_in:
            self.must("trim_start", clip=clip, to=source_in)
        start = self.clip(clip)["start"]
        if start != at:
            self.must("move_clip", clips=[clip], delta=at - start)
        self.must("set_audio", clips=[clip], patch={"volume": VOLUME})
        return clip, media

    def isolate(self, clip, amount):
        self.must("set_audio", clips=[clip], patch={"isolation": amount})

    def export(self, tag):
        out = WORK / "exports" / f"{tag}.wav"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.unlink(missing_ok=True)
        self.client.export_with({"project": self.path, "preset": "audio_wav",
                                 "path": str(out)}, seconds=CALL_BOUND)
        return decode(out)

    def renders(self):
        folder = Path(self.path) / "cache" / "isolated"
        return sorted(p.name for p in folder.iterdir() if p.suffix == ".caf") \
            if folder.is_dir() else []

    def close(self):
        attempt(self.client, "close_project", {"project": self.path, "discard": True})


def decode(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-acodec", "pcm_f32le",
         "-ar", str(SR), "-ac", "2", "-"], check=True, timeout=120, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").astype(np.float64)[0::2]


def db(x, floor=1e-20):
    return 10 * np.log10(np.maximum(x, floor))


def xcorr_lag(ref, sig, maxlag=SR // 10):
    """S2's: the lag L with sig[n] ≈ ref[n − L], parabolic to a fraction."""
    n = len(ref) + len(sig)
    nfft = 1 << (n - 1).bit_length()
    c = np.fft.irfft(np.fft.rfft(sig, nfft) * np.conj(np.fft.rfft(ref, nfft)), nfft)
    lags = np.concatenate([np.arange(0, maxlag + 1), np.arange(-maxlag, 0)])
    vals = np.concatenate([c[: maxlag + 1], c[-maxlag:]])
    i = int(np.argmax(vals))
    whole = int(lags[i])
    y0, y1, y2 = c[(whole - 1) % nfft], c[whole % nfft], c[(whole + 1) % nfft]
    den = y0 - 2 * y1 + y2
    return whole + (0.5 * (y0 - y2) / den if den != 0 else 0.0)


def windows(x, win_s=0.4):
    w = int(win_s * SR)
    n = len(x) // w
    return x[: n * w].reshape(n, w)


def classify(dry):
    lv = db(np.mean(windows(dry) ** 2, axis=1))
    p10 = np.percentile(lv, 10)
    return lv <= p10 + 6, lv >= p10 + 20


def class_db(x, mask):
    return db(np.mean(windows(x)[mask] ** 2))


def octaves(x, mask):
    W = windows(x)[mask]
    win = np.hanning(W.shape[1])
    P = (np.abs(np.fft.rfft(W * win, axis=1)) ** 2).mean(axis=0) / np.sum(win ** 2)
    f = np.fft.rfftfreq(W.shape[1], 1 / SR)
    return np.array([P[(f >= fc / np.sqrt(2)) & (f < fc * np.sqrt(2))].sum() for fc in OCTAVES])


def floor_drop(dry, wet):
    pause, speech = classify(dry)
    n = min(len(dry), len(wet))
    dry, wet = dry[:n], wet[:n]
    return class_db(dry, pause) - class_db(wet, pause), pause, speech


def lag_of(dry, wet):
    n = min(len(dry), len(wet))
    return xcorr_lag(dry[:n], wet[:n])


def i1(client, state):
    doc = Doc(client, "i1")
    try:
        clip, _ = doc.rode(at=2 * SEC, source_in=8 * SEC)
        dry = doc.export("i1-dry")
        doc.isolate(clip, 1)
        wet = doc.export("i1-wet")
        lag = lag_of(dry, wet)
        row("I1", abs(lag) <= 0.5, f"clip from 8 s at 2 s: lag {lag:+.3f} samples (bound 0.5)")
    finally:
        doc.close()


def i1b(client, state):
    doc = Doc(client, "i1b")
    try:
        doc.must("set_canvas", fps=[30000, 1001])
        clip, _ = doc.rode(at=1_221_220, source_in=4_804_800)
        placed = doc.clip(clip)
        dry = doc.export("i1b-dry")
        doc.isolate(clip, 1)
        wet = doc.export("i1b-wet")
        lag = lag_of(dry, wet)
        where = (placed["start"], placed["source"].get("in"))
        row("I1b", where == (1_221_220, 4_804_800) and abs(lag) <= 0.5,
            f"29.97 fps, clip at {where[0]} from {where[1]} (offset "
            f"{(where[1] - where[0]) * 2 / 25:.1f} samples): lag {lag:+.3f} (bound 0.5)")
    finally:
        doc.close()


def i2_i3_i10_i5(client, state):
    doc = Doc(client, "whole")
    try:
        clip, _ = doc.rode()
        dry = doc.export("i2-dry")
        doc.isolate(clip, 1)
        wet = doc.export("i2-wet")
        drop, pause, speech = floor_drop(dry, wet)
        n = min(len(dry), len(wet))
        bands = db(octaves(wet[:n], speech)) - db(octaves(dry[:n], speech))
        broad = class_db(wet[:n], speech) - class_db(dry[:n], speech)
        ok = drop >= 9 and np.all(np.abs(bands) <= 0.5) and abs(broad) <= 0.5
        row("I2", ok,
            f"{int(pause.sum())} pause and {int(speech.sum())} speech windows of 400 ms: floor "
            f"lowered {drop:.1f} dB (≥ 9); speech broadband {broad:+.2f} dB, octaves "
            + " ".join(f"{fc}:{b:+.2f}" for fc, b in zip(OCTAVES, bands)) + " (±0.5)")
        state["whole_dry"] = dry

        doc.isolate(clip, 0.5)
        half = doc.export("i3-half")
        m = min(n, len(half))
        want = 0.5 * (dry[:m] + wet[:m])
        residual = db(np.mean((half[:m] - want) ** 2)) - db(np.mean(want ** 2))
        row("I3", residual <= -60, f"Amount 0.5 against 0.5·(dry + isolated): residual "
            f"{residual:.1f} dB (bound −60)")

        doc.isolate(clip, 0)
        stored = doc.clip(clip)["audio"]
        again = doc.export("i10-dry")
        same = len(again) == len(dry) and np.array_equal(again, dry)
        row("I10", "isolation" not in stored and same,
            f"isolation 0: key in get_project {'isolation' in stored}; export equals I2's dry "
            f"sample for sample: {same} ({len(again)} vs {len(dry)} frames)")

        doc.isolate(clip, 1)
        doc.export("i5-before")
        before = doc.renders()
        doc.must("trim_start", clip=clip, to=SEC)
        wet5 = doc.export("i5-wet")
        deadline = time.monotonic() + 10
        after = doc.renders()
        while (set(after) & set(before) or len(after) != 1) and time.monotonic() < deadline:
            time.sleep(0.25)
            after = doc.renders()
        doc.isolate(clip, 0)
        dry5 = doc.export("i5-dry")
        lag = lag_of(dry5, wet5)
        ok = len(before) == 1 and len(after) == 1 and before != after and abs(lag) <= 0.5
        row("I5", ok, f"trim_start 1 s: renders before {before}, after {after}; lag "
            f"{lag:+.3f} (bound 0.5)")
    finally:
        doc.close()


def i4(client, state):
    doc = Doc(client, "i4")
    try:
        clip, _ = doc.rode(source_in=3 * SEC)
        doc.isolate(clip, 1)
        started = time.monotonic()
        wet = doc.export("i4-wet")
        waited = time.monotonic() - started
        doc.isolate(clip, 0)
        dry = doc.export("i4-dry")
        drop, _, _ = floor_drop(dry, wet)
        row("I4", drop >= 9, f"exported straight after set_audio (hold {HOLD_S} s): "
            f"{waited:.1f} s to finish, floor lowered {drop:.1f} dB (≥ 9)")
    finally:
        doc.close()


def wait_reverse(doc, media, bound=300):
    """None once `cache/reversed/<media>-*.mov` exists with no `.partial` and
    the window has no sheet (the render's progress sheet gone); else why."""
    folder = Path(doc.path) / "cache" / "reversed"
    deadline = time.monotonic() + bound
    while True:
        files = sorted(folder.glob(f"{media}-*.mov")) if folder.is_dir() else []
        partial = folder.is_dir() and any(folder.glob(f"{media}-*.partial"))
        if files and not partial:
            got = doc.call("snapshot_ui", window="sheet", path=str(WORK / "i6-sheet.png"))
            if not got["ok"] and "no sheet attached" in got.get("error", ""):
                return None
        if time.monotonic() > deadline:
            return f"the reverse did not finish within {bound} s"
        time.sleep(0.25)


def i6(client, state):
    doc = Doc(client, "i6")
    try:
        clip, media = doc.rode()
        doc.must("set_reversed", clip=clip, reversed=True)
        late = wait_reverse(doc, media)
        dry = doc.export("i6-dry")
        doc.isolate(clip, 1)
        wet = doc.export("i6-wet")
        lag = lag_of(dry, wet)
        drop, _, _ = floor_drop(dry, wet)
        row("I6", late is None and abs(lag) <= 0.5,
            f"reversed ({'ready' if late is None else late}): lag {lag:+.3f} (bound 0.5); floor "
            f"lowered {drop:.1f} dB (reported)")
    finally:
        doc.close()


def i7(client, state):
    """Keep pitch off renders through the ramp queue's varispeed, which is
    deterministic, so its export equals isolation 0's sample for sample. Keep
    pitch on is AVFoundation's spectral time-pitch, which is not: two exports
    of one ×2 clip at isolation 0 measured max |Δ| 0.095, 331,924 of 726,400
    samples apart — so it is held to its dry export's pause floor (±1 dB, where
    isolation lowers it ≥ 9 dB), with a second dry export's difference
    reported beside it."""
    parts, ok = [], True
    for keep in (True, False):
        doc = Doc(client, f"i7-{'on' if keep else 'off'}")
        try:
            clip, _ = doc.rode()
            doc.must("set_speed", clip=clip, rate=2.0, keep_pitch=keep)
            dry = doc.export(f"i7-{keep}-dry")
            doc.isolate(clip, 1)
            wet = doc.export(f"i7-{keep}-wet")
            n = min(len(dry), len(wet))
            files = doc.renders()
            if keep:
                doc.isolate(clip, 0)
                again = doc.export(f"i7-{keep}-dry2")
                m = min(n, len(again))
                drift = float(np.max(np.abs(dry[:m] - again[:m]))) if m else math.nan
                drop, _, _ = floor_drop(dry, wet)
                good = n > SR and abs(drop) <= 1.0
                parts.append(f"keep pitch on: renders {files}, pause floor moved {drop:+.2f} dB "
                             f"(±1), a second dry export max |Δ| {drift:.4f} from the first")
            else:
                good = n > SR and np.array_equal(dry[:n], wet[:n])
                parts.append(f"keep pitch off: renders {files}, equal over {n} frames: {good}")
            ok = ok and good and not files
        finally:
            doc.close()
    row("I7", ok, "; ".join(parts))


def i8_i9(client, state):
    doc = Doc(client, "i8")
    try:
        first, media = doc.rode()
        second, _ = doc.rode(at=40 * SEC, media=media)
        doc.isolate(first, 0.6)
        source = doc.clip(first)
        doc.must("paste_attributes", clips=[second], payload={"clips": [source], "media": []},
                 groups=["audio"])
        carried = doc.clip(second)["audio"].get("isolation")
        row("I8", carried == 0.6, f"paste_attributes onto clip {second}: isolation {carried}")
        got = doc.call("set_audio", clips=[first], patch={"isolation": 1.5})
        sentence = "audio.isolation must be between 0 and 1, not 1.5"
        row("I9", not got["ok"] and got.get("error", "").endswith(sentence),
            f"set_audio {{isolation: 1.5}}: {got.get('error', got)}")
    finally:
        doc.close()


APP_ROWS = [i1, i1b, i2_i3_i10_i5, i4, i6, i7, i8_i9]
ROW_NAMES = {i1: ["I1"], i1b: ["I1b"], i2_i3_i10_i5: ["I2", "I3", "I10", "I5"], i4: ["I4"],
             i6: ["I6"], i7: ["I7"], i8_i9: ["I8", "I9"]}


def complaints(log):
    try:
        with open(log, errors="replace") as handle:
            return [line.rstrip() for line in handle if "Frame Job: " in line]
    except OSError as error:
        return [f"the log could not be read: {error}"]


def app_rows():
    if not RODE.exists():
        for runner in APP_ROWS:
            for name in ROW_NAMES[runner]:
                row(name, False, f"{RODE} is missing")
        return
    log = WORK / "framejob.log"
    binary = proof_app.binary()
    launched = mcp.launch(str(binary), arguments=["-RCDevRampRenderHold", str(HOLD_S)],
                          env=bounded.child_env(), log_path=str(log), timeout=CALL_BOUND)
    up = launched.client is not None
    try:
        if up:
            print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        state = {}
        for runner in APP_ROWS:
            if not up:
                for name in ROW_NAMES[runner]:
                    row(name, False, f"the app did not listen at {launched.socket_path}")
                continue
            done = len(rows)
            try:
                runner(launched.client, state)
            except Exception as error:  # a broken instrument is a FAIL, not an exit
                answered = {r for r, _ in rows[done:]}
                for name in ROW_NAMES[runner]:
                    if name not in answered:
                        row(name, False, f"the row could not run: {type(error).__name__}: {error}")
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    found = complaints(log)
    row("I0", up and not found, f"listening {up}; complaints {found[:5]}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--probe", action="store_true")
    parser.add_argument("--mutants", action="store_true")
    parser.add_argument("--instance", action="store_true", help="the I rows alone")
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    if args.mutants:
        return 0 if mutants() else 1
    if not args.instance:
        probe_rows()
    if not args.probe:
        shutil.rmtree(WORK / "projects", ignore_errors=True)
        shutil.rmtree(WORK / "exports", ignore_errors=True)
        (WORK / "framejob.log").unlink(missing_ok=True)
        app_rows()
    passed = sum(1 for _, ok in rows if ok)
    print(f"{passed}/{len(rows)}", flush=True)
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
