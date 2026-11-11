"""Road map "audio" AP5 — voice isolation (spec §11 AU-50…AU-57), and
isolation on a retimed clip (#387, AU-55 as amended): the probe over
`app/Sources`, its mutants, and exports from an instance of its own.

    python3 tools/proof/audio_ap5_proof.py             # P rows, then I rows on an own instance
    python3 tools/proof/audio_ap5_proof.py --probe     # P1–P18, P2b and P8b, no instance
    python3 tools/proof/audio_ap5_proof.py --mutants   # the twenty-four mutants, each against its row
    python3 tools/proof/audio_ap5_proof.py --mutants a,b  # the named ones
    python3 tools/proof/audio_ap5_proof.py --instance  # I0–I11, I1b and I7a–I7e alone
    python3 tools/proof/audio_ap5_proof.py --instance --only I7a --only I11  # those rows' runners

The instance is `proof_app`'s app (Debug by default, `RC_PROOF_APP=release`
for the record), launched with `-RCDevRampRenderHold 2` on a scratch socket
and stopped by its own pid. The owner's recording `samples/Rode-usb-mic.m4a`
(30.3 s, mono 48 kHz) is every row's media; missing, every row that needs it
FAILs. Needs `ffmpeg` and numpy. Exports are `audio_wav`, decoded to float by
ffmpeg, left channel. Every project raises the clip's volume ×4 (+12 dB) so a
16-bit export's quantisation sits ≥ 60 dB under the recording; the fader is
after the tap, so it changes no comparison between two exports.

**Probe rows** (`audio_ap5_probe.swift`, compiled AS `main.swift` over
`app/Sources` on `swift_build.py`'s line, under `FRAMEJOB_DEV_TOOLS` for P11's
render hold; a build failure is a scored FAIL):
P1 pending is dry with no tap; P2 a synthetic render read sample for sample at
the placement, alone and with the noise reducer's lead; P2b the wet offset off
the 48 kHz grid; P3 Amount 0.5 and 0.25 as a crossfade; P4 a ×1 segment gets
a tapped request, a retimed one a chain (two stages live, three rendered),
each stage formable once the file before it is there; P5 the render's lag 0
on the recording; P6 a window against the whole file's render ≤ −40 dB; P7 the
name; P8 the export waits; P9 a failure reaches the owner once, on main; P10
a round whose lanes answer different frame counts fails the render naming both
(#409); P11 Voice Isolation's Status in the app's own Clip pane reads
"Rendering…" while a held render is pending, "Ready" once it lands and "Not
rendered: …" once one fails, which only the pane's drop of its memo on
`.reversedMediaDidChange` can move (#408); P12 the same landing for Voice
Effect's Status. The retimed rows (#387; the probe's header has each):
P13 the processed render equals the dry render when the mix is the dry sound
(the shift by the window's first frame is exact; the pad holds what Apple's
unit reads); P8b the export's wait builds with every stage on disk; P18 the
preview's build reads what the export's reads; P14 the mix and its Amount
through a map; P15 what the composition reads for a live and a rendered
segment; P16 what each file is named by; P17 the Status and the dry render
wanted beside the chain.

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
- I7a–I7d, a retimed clip is isolated (AU-55 as amended, #387). The oracle
  is "isolating then retiming equals retiming the isolated file": I2's ×1
  isolated export, its left channel as a mono file, imported and given the
  same speed. I7a ×2 with Keep pitch off, isolation 1: the pause floor at
  least 6 dB under its dry export and within 1 dB of what the oracle
  lowers it (400 ms windows of a ×2 clip span twice the media, so a pause
  window is shallower than I2's), speech within ±0.5 dB; against the oracle a
  residual ≤ −40 dB and |lag| ≤ 0.5 sample; two files in `cache/isolated/`
  (the isolation and the mix) and two in `cache/ramp-audio/` (dry and
  processed). I7b ×2 with Keep pitch on (AVFoundation's time-pitch, not
  deterministic): the floor by the same rule, speech ±1 dB, |lag| against
  the oracle ≤ 5 ms; no ramp file. I7c a ×1→×2 Speed action over 12 s:
  Keep pitch off by I7a's rule; on (Apple's unit, rendered) by I7b's with
  the floor within 2 dB, its dry export's lag and residual against the dry
  file retimed reported beside it. I7d ×2 Keep pitch off at Amount 0.5
  against 0.5·(I7a's dry + isolated): residual ≤ −60 dB.
- I7e: ×2 → ×1.5 with Keep pitch on keeps both files in `cache/isolated/`
  and their dates (one window, rounded out to whole seconds); Amount 1 → 0.5
  keeps the isolation and writes a new mix, the old one pruned; a trim to
  10 s renders both again.
- I11: a `freeze_frame` still has no audio properties: `paste_attributes`
  and `set_audio` with `isolation` are refused in the core's sentence, no
  file is rendered and the export is unchanged.
- I8: `paste_attributes` carries `isolation` onto another clip.
- I9: `set_audio {isolation: 1.5}` is refused with the core's sentence.
- I10: `set_audio {isolation: 0}` on an isolated clip: `get_project` holds no
  `isolation` key and the export equals I2's dry, sample for sample.

**Mutants** (`--mutants`; each over its own copy of `app/Sources`, killed when
its named row fails): latency-kept (P5), no-preroll (P6), amount-swapped
(P3), no-track-lead (P2), pending-silent (P1), scaled-isolated (P4),
export-no-wait (P8), window-not-keyed (P7), split-rounding (P2b),
failure-silent (P9), lanes-cut-to-shorter (P10), memo-not-dropped (P11),
voice-memo-not-dropped (P12), isolation-failure-retimed (P11: an unreadable
forward source fails in the ramp renderer's words); and #387's ten, one per
decision: retimed-dry (P4: no chain, the old behaviour), map-unshifted (P13),
pad-zero (P13), mix-swapped (P14), automation-unmapped (P14),
live-not-substituted (P15), family-not-told (P15), amount-not-keyed (P16),
dry-not-wanted (P17), export-one-pass (P8b). split-rounding is also I1b's;
the instance rows are not re-run per mutant.

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
PROBE_ROWS = ["P1", "P2", "P2b", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P10", "P11",
              "P12", "P13", "P8b", "P18", "P14", "P15", "P16", "P17"]
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
        # FRAMEJOB_DEV_TOOLS: P11 and P12 hold a render (`RampAudioRenders.hold`).
        swift_build.build(sources=swift + [str(entry)], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc: " + " | ".join((errors or list(error.diagnostics) or [str(error)])[:6])
    return binary, ""


def run_probe(sources, name, only=None):
    """({row: (passed, detail)}, problem) — None rows when it did not build.
    `only`: the rows whose sections run (`AP5_ROWS`); every one when None."""
    binary, problem = build_probe(sources, name)
    if binary is None:
        return None, problem
    scratch = WORK / name / "scratch"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    try:
        env = dict(os.environ)
        env.pop("AP5_ROWS", None)
        if only:
            env["AP5_ROWS"] = ",".join(only)
        result = subprocess.run([str(binary), str(scratch), str(RODE)], capture_output=True,
                                text=True, timeout=900, cwd=str(binary.parent), env=env)
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

# The builder's text since AP14 (a voiced render rides the same pass).
SILENT_BUILDER_OLD = (
    "                let isolation = isolated.isEmpty && voiced.isEmpty\n"
    "                    ? nil\n"
    "                    : AudioIsolationTrack(\n"
    "                        segments: family.segments, shift: shift, dsp: dsp, renders: isolated,\n"
    "                        voiced: voiced)\n")
SILENT_BUILDER_NEW = (
    "                let isolation = dsp.isolates\n"
    "                    ? AudioIsolationTrack(\n"
    "                        segments: family.segments, shift: shift, dsp: dsp, renders: isolated,\n"
    "                        voiced: voiced)\n"
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
    # A time-scaled segment taken for a ×1 one: a tapped request for it.
    ("scaled-isolated", ["P4"], [
        ("IsolationCache.swift",
         "        RetimedSound.kind(of: s) == .tapped\n",
         "        RetimedSound.kind(of: s) != .rendered\n")]),
    ("export-no-wait", ["P8"], [
        ("RetimedSound.swift",
         "        add(IsolationCache.requests(plan: plan, dsp: dsp, urls: urls, reverse: reverse))\n",
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
    ("lanes-cut-to-shorter", ["P10"], [
        ("IsolationRenderer.swift",
         "        guard let first = counts.first else { return 0 }\n",
         "        guard let first = counts.min() else { return 0 }\n"
         "        if first >= 0 { return first }\n")]),
    # #408: a render landing or failing no longer drops the Status memo.
    ("memo-not-dropped", ["P11"], [
        ("AudioPane.swift", "        isolationMemo.invalidate()\n", "")]),
    ("voice-memo-not-dropped", ["P12"], [
        ("AudioPane.swift", "        voiceMemo.invalidate()\n", "")]),
    ("isolation-failure-retimed", ["P11"], [
        ("RampAudioRenders.swift",
         "                    throw IsolationRenderer.RenderError.unreadable(why)\n"
         "                }\n"
         "                let job = IsolationRenderer.Job(\n",
         "                    throw RampAudioRenderer.RenderError.unreadable(why)\n"
         "                }\n"
         "                let job = IsolationRenderer.Job(\n")]),
    # AU-55 as amended (#387), one per decision.
    # The old behaviour: a retimed segment has no chain and plays dry.
    ("retimed-dry", ["P4"], [
        ("RetimedSound.swift",
         "        guard voice != nil || wants, let kind = kind(of: s), kind != .tapped,\n",
         "        guard voice != nil || wants, let kind = kind(of: s), kind == .tapped,\n")]),
    ("map-unshifted", ["P13"], [
        ("RampAudioRenders.swift",
         "                    map: RampAudioCache.map(of: ramp, lessFrames: request.sourceFirstFrame),\n",
         "                    map: RampAudioCache.map(of: ramp),\n")]),
    ("pad-zero", ["P13"], [
        ("RetimedSound.swift",
         "    static let padFrames: Int64 = 8192\n",
         "    static let padFrames: Int64 = 0\n")]),
    ("mix-swapped", ["P14"], [
        ("IsolationMix.swift",
         "                            x += a * (iso.samples(channel: min(c, iso.channels - 1))[w] - x)\n",
         "                            let wet = iso.samples(channel: min(c, iso.channels - 1))[w]\n"
         "                            x = wet + a * (x - wet)\n")]),
    # The Amount's points read in source time, not through the map.
    ("automation-unmapped", ["P14"], [
        ("IsolationMix.swift",
         "            let t = clip[leg] + u * (clip[leg + 1] - clip[leg])\n",
         "            let t = x - source[0] + 0 * u\n")]),
    ("live-not-substituted", ["P15"], [
        ("CompositionBuilder+AudioTracks.swift",
         "        if mediaType == .audio, !processed.isEmpty,\n",
         "        if mediaType == .video, !processed.isEmpty,\n")]),
    # The families are split by the media's format while `fill` inserts the
    # processed window: a float CAF on an AAC track (#34).
    ("family-not-told", ["P15"], [
        ("CompositionBuilder+AudioTracks.swift",
         "                    assets: &assets, reversedAssets: &reversedAssets, ramps: ramps,\n"
         "                    processed: processed)\n"
         "                : nil\n",
         "                    assets: &assets, reversedAssets: &reversedAssets, ramps: ramps,\n"
         "                    processed: [:])\n"
         "                : nil\n")]),
    ("amount-not-keyed", ["P16"], [
        ("IsolationMix.swift",
         '|\\(job.isolated.lastPathComponent)|a\\(job.amount)"',
         '|\\(job.isolated.lastPathComponent)"')]),
    ("dry-not-wanted", ["P17"], [
        ("ProjectDocument+RampAudio.swift",
         "            if ramped { add(RampAudioCache.requests(plan: plan, urls: urls, reverse: reverse)) }\n",
         "")]),
    ("export-one-pass", ["P8b"], [
        ("Exporter+RampAudio.swift",
         "        for _ in 0..<offlineAudioPasses {\n",
         "        for _ in 0..<1 {\n")]),
]


def mutants(only=None):
    killed = 0
    sources = ROOT / "app/Sources"
    chosen = [m for m in MUTANTS if not only or m[0] in only]
    for name, targets, edits in chosen:
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
        # Only the sections its rows are in run: a mutant is scored on those.
        found, why = run_probe(tree, f"mutant-{name}", only=targets)
        if found is None:
            row(f"mutant {name}", False, "did not build: " + why)
            continue
        failing = sorted(r for r in found if not found[r][0])
        dead = any(found.get(r, (True, ""))[0] is False for r in targets)
        killed += dead
        row(f"mutant {name}", dead, f"killed by {'/'.join(targets)}: {dead}; of the rows run "
            f"({', '.join(sorted(found))}), failing: " + (", ".join(failing) or "none"))
    print(f"{killed}/{len(chosen)} mutants killed", flush=True)
    return bool(chosen) and killed == len(chosen)


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


def folder_files(doc, name):
    folder = Path(doc.path) / "cache" / name
    return sorted(p.name for p in folder.iterdir() if p.suffix == ".caf") \
        if folder.is_dir() else []


def retime(doc, clip, kind, keep):
    """`kind` "x2": ×2; "ramp": a ×1→×2 Speed action over the whole clip."""
    if kind == "x2":
        doc.must("set_speed", clip=clip, rate=2.0, keep_pitch=keep)
    else:
        # 12 s of clip, so the ramp's 18 s of media fit the recording.
        doc.must("trim_end", clip=clip, to=12 * SEC)
        if not keep:  # on is the default, and saying so again is no change
            doc.must("set_speed", clip=clip, rate=1.0, keep_pitch=False)
        doc.must("add_speed_ramp", clip=clip, shape="ramp_up", rate=2, curve="linear")


def residual_db(a, b):
    n = min(len(a), len(b))
    return db(np.mean((a[:n] - b[:n]) ** 2)) - db(np.mean(b[:n] ** 2))


def speech_shift(dry, wet):
    _, speech = classify(dry)
    n = min(len(dry), len(wet))
    return class_db(wet[:n], speech[: len(windows(wet[:n]))]) \
        - class_db(dry[:n], speech[: len(windows(dry[:n]))])


def oracle(client, source, kind, keep, tag):
    """The ×1 isolated export `source` (a WAV) imported as media and retimed
    the same way, at volume 1: retiming the isolated file. Its left channel
    alone, as a mono file: the recording is mono, and Apple's time-pitch
    unit does not time a stereo source as it does a mono one."""
    mono = source.with_name(source.stem + "-mono.wav")
    if not mono.exists():
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(source), "-af",
                        "pan=mono|c0=c0", "-c:a", "pcm_s16le", str(mono)], check=True,
                       timeout=120)
    doc = Doc(client, tag)
    try:
        media = doc.must("import_media", path=str(mono))["media"]
        track = doc.project()["tracks"][0]["id"]
        clip = doc.must("add_clip", track=track, media=media, at=0)["new_clips"][0]
        retime(doc, clip, kind, keep)
        return doc.export(tag)
    finally:
        doc.close()


def i7(client, state):
    """AU-55 as amended (#387): a retimed clip is isolated through its
    processed window. The oracle is "isolating then retiming equals retiming
    the isolated file": I2's ×1 isolated export imported as media and given
    the same speed. A rendered segment (Keep pitch off, or a ramp) is
    deterministic, so it is compared sample against sample; a live one
    (constant speed, Keep pitch on) is AVFoundation's time-pitch, which is not
    deterministic between two reads, so it is held to its pause floor and a
    lag."""
    iso_wav = WORK / "exports" / "i2-wet.wav"
    dry_wav = WORK / "exports" / "i2-dry.wav"
    cases = [("I7a", "x2", False), ("I7b", "x2", True), ("I7c", "ramp", False),
             ("I7c", "ramp", True)]
    parts_c, ok_c = [], True
    for name, kind, keep in cases:
        tag = f"i7-{kind}-{'on' if keep else 'off'}"
        doc = Doc(client, tag)
        try:
            clip, _ = doc.rode()
            retime(doc, clip, kind, keep)
            dry = doc.export(f"{tag}-dry")
            doc.isolate(clip, 1)
            wet = doc.export(f"{tag}-wet")
            files = (folder_files(doc, "isolated"), folder_files(doc, "ramp-audio"))
            drop, _, _ = floor_drop(dry, wet)
            speech = speech_shift(dry, wet)
            want = oracle(client, iso_wav, kind, keep, f"{tag}-oracle") \
                if iso_wav.exists() else np.zeros(0)
            n = min(len(wet), len(want))
            lag = xcorr_lag(want[:n], wet[:n]) if n > SR else math.nan
            rendered = kind == "ramp" or not keep
            dry_want = oracle(client, dry_wav, kind, keep, f"{tag}-dry-oracle") \
                if dry_wav.exists() else np.zeros(0)
            floor_gap = floor_drop(dry_want, want)[0] if len(dry_want) > SR else math.nan
            # The floor: 400 ms windows of a retimed clip span more media than
            # I2's, so a pause window is rarer and less deep; the bound is 6 dB
            # and what retiming the isolated file gives, within 1 dB.
            # Keep pitch on is Apple's time-pitch, live or rendered: its ramp
            # render of the DRY recording already differs from the render of
            # the same sound read from a WAV (reported), so it is held to the
            # floor (within 2 dB on a ramp) and a lag, not a residual.
            within = 2.0 if keep and kind == "ramp" else 1.0
            floor = (f"floor lowered {drop:.1f} dB (≥ 6; retiming the isolated file lowers it "
                     f"{floor_gap:.1f}, within {within:g})")
            good = drop >= 6 and abs(drop - floor_gap) <= within
            if not keep:
                res = residual_db(wet, want) if n > SR else math.nan
                good = good and abs(speech) <= 0.5 and res <= -40 and abs(lag) <= 0.5
                detail = (f"{floor}, speech {speech:+.2f} dB (±0.5); against retiming the "
                          f"isolated file: residual {res:.1f} dB (≤ −40), lag {lag:+.3f} "
                          f"(≤ 0.5)")
            else:
                m = min(len(dry), len(dry_want))
                base_lag = xcorr_lag(dry_want[:m], dry[:m]) if m > SR else math.nan
                base_res = residual_db(dry, dry_want) if m > SR else math.nan
                good = good and abs(speech) <= 1.0 and abs(lag) <= 0.005 * SR
                detail = (f"{floor}, speech {speech:+.2f} dB (±1); lag {lag:+.1f} samples "
                          f"(≤ {0.005 * SR:.0f}); its dry export against the dry file retimed: "
                          f"lag {base_lag:+.1f}, residual {base_res:.1f} dB (reported)")
            counts = (len(files[0]), len(files[1]))
            good = good and counts == ((2, 2) if rendered else (2, 0))
            detail = (f"{'×2' if kind == 'x2' else '×1→×2 ramp'}, Keep pitch "
                      f"{'on' if keep else 'off'}: {detail}; files isolated {counts[0]} "
                      f"(want 2), ramp-audio {counts[1]} (want {2 if rendered else 0})")
            if name == "I7c":
                parts_c.append(detail)
                ok_c = ok_c and good
            else:
                row(name, good, detail)
            if name == "I7a":
                # I7d: the Amount on a retimed clip is the mix's.
                doc.isolate(clip, 0.5)
                half = doc.export("i7d-half")
                m = min(len(half), len(dry), len(wet))
                mid = 0.5 * (dry[:m] + wet[:m])
                res = db(np.mean((half[:m] - mid) ** 2)) - db(np.mean(mid ** 2))
                row("I7d", res <= -60, f"×2 Keep pitch off, Amount 0.5 against 0.5·(dry + "
                    f"isolated): residual {res:.1f} dB (bound −60)")
        finally:
            doc.close()
    row("I7c", ok_c, "; ".join(parts_c))


def settle(doc, folder, want, bound=20):
    """`folder`'s `.caf` names once `want(names)` holds, or after `bound` s."""
    deadline = time.monotonic() + bound
    names = folder_files(doc, folder)
    while not want(names) and time.monotonic() < deadline:
        time.sleep(0.25)
        names = folder_files(doc, folder)
    return names


def stamps(doc, folder):
    base = Path(doc.path) / "cache" / folder
    return {n: (base / n).stat().st_mtime_ns for n in folder_files(doc, folder)}


def i7e(client, state):
    """What a render is named by. The whole recording at ×2 and at ×1.5 reads
    the same seconds of media, so its window — rounded out to whole seconds —
    is the same, and so are the isolated file and (the Amount unchanged) the
    mix. A new Amount writes a new mix beside the same isolation; a trim that
    moves the window by seconds renders the isolation again."""
    doc = Doc(client, "i7e")
    try:
        clip, _ = doc.rode()
        doc.must("set_speed", clip=clip, rate=2.0, keep_pitch=True)
        doc.isolate(clip, 1)
        doc.export("i7e-a")
        first = stamps(doc, "isolated")
        doc.must("set_speed", clip=clip, rate=1.5, keep_pitch=True)
        doc.export("i7e-b")
        second = stamps(doc, "isolated")
        doc.isolate(clip, 0.5)
        doc.export("i7e-c")
        third = settle(doc, "isolated", lambda names: len(names) == 2)
        doc.must("trim_end", clip=clip, to=10 * SEC)
        doc.export("i7e-d")
        fourth = settle(doc, "isolated",
                        lambda names: len(names) == 2 and not set(names) & set(first))
        kept = set(third) & set(first)
        ok = len(first) == 2 and first == second and len(third) == 2 and len(kept) == 1 \
            and len(fourth) == 2 and not set(fourth) & set(first)
        row("I7e", ok,
            f"×2 → ×1.5, Keep pitch on: isolated files and their dates unchanged: "
            f"{first == second} ({sorted(first)}); Amount 1 → 0.5: {third}, {len(kept)} kept "
            f"(the isolation; want 1) and a new mix; trimmed to 10 s: {fourth}, none of the "
            f"first two: {not set(fourth) & set(first)}")
    finally:
        doc.close()


def i11(client, state):
    """A freeze frame has no sound of its own: the still `freeze_frame`
    makes has no audio properties, so the core refuses isolation on it by
    either door, nothing is rendered and no sample changes."""
    doc = Doc(client, "i11")
    try:
        other, _ = doc.rode(at=60 * SEC)
        picture = doc.must("import_media", path=str(ROOT / "tools/proof/media/AV.mov"))["media"]
        track = doc.project()["tracks"][0]["id"]
        clip = doc.must("add_clip", track=track, media=picture, at=0)["new_clips"][0]
        before = {c["id"] for c in doc.project()["clips"]}
        doc.must("freeze_frame", clip=clip, at=3 * SEC, duration=2 * SEC)
        stills = [c for c in doc.project()["clips"]
                  if c["id"] not in before and c["source"].get("kind") == "still"]
        plain = doc.export("i11-plain")
        doc.isolate(other, 0.6)
        source = doc.clip(other)
        doc.isolate(other, 0)
        got = doc.call("paste_attributes", clips=[s["id"] for s in stills],
                       payload={"clips": [source], "media": []}, groups=["audio"])
        direct = doc.call("set_audio", clips=[s["id"] for s in stills], patch={"isolation": 1})
        sentence = "has no audio properties"
        refused = [not g["ok"] and sentence in g.get("error", "") for g in (got, direct)]
        again = doc.export("i11-isolated")
        time.sleep(HOLD_S + 1)
        files = folder_files(doc, "isolated")
        same = len(plain) == len(again) and np.array_equal(plain, again)
        row("I11", len(stills) == 1 and all(refused) and same and not files,
            f"isolation on a freeze_frame still: paste_attributes: {got.get('error', got)}; "
            f"set_audio: {direct.get('error', direct)}; isolated files {files}; export equals "
            f"the one before: {same} ({len(again)} frames)")
    finally:
        doc.close()


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


APP_ROWS = [i1, i1b, i2_i3_i10_i5, i4, i6, i7, i7e, i11, i8_i9]
ROW_NAMES = {i1: ["I1"], i1b: ["I1b"], i2_i3_i10_i5: ["I2", "I3", "I10", "I5"], i4: ["I4"],
             i6: ["I6"], i7: ["I7a", "I7d", "I7b", "I7c"], i7e: ["I7e"], i11: ["I11"],
             i8_i9: ["I8", "I9"]}


def complaints(log):
    try:
        with open(log, errors="replace") as handle:
            return [line.rstrip() for line in handle if "Frame Job: " in line]
    except OSError as error:
        return [f"the log could not be read: {error}"]


def app_rows(only=None):
    if only:
        chosen = [r for r in APP_ROWS if set(ROW_NAMES[r]) & set(only)]
        # I7's oracle is I2's exports.
        if i7 in chosen and i2_i3_i10_i5 not in chosen:
            chosen.insert(0, i2_i3_i10_i5)
        APP_ROWS[:] = chosen
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
    parser.add_argument("--mutants", nargs="?", const="", default=None, metavar="a,b",
                        help="every mutant, or the named ones")
    parser.add_argument("--instance", action="store_true", help="the I rows alone")
    parser.add_argument("--only", action="append", default=[],
                        help="an instance row to run (repeatable); with --instance")
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    if args.mutants is not None:
        return 0 if mutants([n for n in args.mutants.split(",") if n]) else 1
    if not args.instance:
        probe_rows()
    if not args.probe:
        shutil.rmtree(WORK / "projects", ignore_errors=True)
        shutil.rmtree(WORK / "exports", ignore_errors=True)
        (WORK / "framejob.log").unlink(missing_ok=True)
        app_rows(args.only)
    passed = sum(1 for _, ok in rows if ok)
    print(f"{passed}/{len(rows)}", flush=True)
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
