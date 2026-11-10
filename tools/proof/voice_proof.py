"""Road map "audio" AP14 — voice effects (spec §11 AU-140…AU-149), and
Clip ▸ Voice ▸ (AU-158, #390): the probe over `app/Sources`, its mutants,
each kind's makeup, and exports and the menu from an instance of its own.

    python3 tools/proof/voice_proof.py             # V rows, then I, K and M rows on an own instance
    python3 tools/proof/voice_proof.py --probe     # V1–V14, no instance
    python3 tools/proof/voice_proof.py --measure   # each kind's m_k on the owner's recording
    python3 tools/proof/voice_proof.py --mutants   # the eighteen mutants, each against its row
    python3 tools/proof/voice_proof.py --mutants menu-mixed-as-on,menu-pitch-kept  # the named ones
    python3 tools/proof/voice_proof.py --instance  # I0, K1–K16, I2–I11 and M1–M5 alone
    python3 tools/proof/voice_proof.py --menu      # I0 and M1–M5 alone

The instance is `proof_app`'s app (Debug by default, `RC_PROOF_APP=release`
for the record), launched with `-RCDevRampRenderHold 2` on a scratch socket
and stopped by its own pid. Fixtures are made by ffmpeg (48 kHz mono WAV): a
220 Hz and a 1 kHz tone at −12 dBFS, white noise at −26 dBFS RMS, a click
(one sample at 0.9 at 1 s), and a 50 ms noise burst at −6 dBFS RMS at 0.5 s in
10 s; the owner's recording `samples/Rode-usb-mic.m4a` is I3's and I9's.
Needs `ffmpeg` and numpy. Exports are `audio_wav`, decoded to float by
ffmpeg, left channel; the recording's clips are raised ×4 as AP5's are.

**Probe rows** (`voice_probe.swift`, compiled AS `main.swift` over
`app/Sources` on `swift_build.py`'s line; a build failure is a scored FAIL):
V1 pending plays without the effect, isolation's span when only it is ready;
V2 a synthetic voiced render read at the placement, no isolation on top; V3
which segments get a request, and the isolation gate; V4 the name; V5 the
render against the reference engine for lofi, radio, robot, pitch +7 and
hall; V6 the isolation crossfade into the input; V7 mono as (L+R)/2; V8 the
export's wait and `voiceFailed`; V9 room's and cathedral's tails ≥ 3 s apart;
V10 sync on tone bursts (lag 0 ± 1 ms, each chain's latency printed); V11 a
kind change sends `pitch: null`; V12 Clip ▸ Voice ▸'s items against a literal
list (headers, kinds, tags, the selector, None) and the popup's titles as
"<header>: <item>"; V13 the mark (`VoiceMenu.state`: on, mixed, off; None
likewise); V14 what a choice writes (`VoiceMenu.targets`, `ops`, `kind(tag:)`:
each clip's own amount, no pitch, a text clip no target, None clears).

**Instance rows:**
- I0: the instance's log has no `Frame Job: ` line (the parity check).
- K1–K16, one per kind at amount 1: pitch +7, high and deep move a 220 Hz
  tone to 329.63, 293.66 and 164.81 Hz (±1 cent); robot's 940 and 1060 Hz
  bins each ≥ 10 dB over the 1 kHz bin on a 1 kHz tone; on white noise
  against dry, bass's 63 Hz − 2 kHz ≥ +6 dB, treble's 8 kHz − 250 Hz ≥ +6 dB,
  bright's 3 kHz − 250 Hz ≥ +3 dB (the bell's centre; at 4 kHz AU-141's chain
  lifts about +2.6 dB, reported), telephone's and radio's 125 Hz and 8 kHz
  octaves ≥ 20 / ≥ 15 dB under 1 kHz; lofi's energy outside 900–1100 Hz on a
  1 kHz tone ≥ 20 dB over dry's; distorted's harmonics 2–5 kHz ≥ −30 dB re the
  fundamental; echo's echoes of a click at +250 and +500 ms (±1 ms); room,
  plate, hall and cathedral's time from the burst's end until the 10 ms RMS
  stays under −60 dBFS in 0.05–0.6, 0.05–0.6, 1.0–3.5 and 3.0–8.0 s.
- I2: pitch +12 and −12 on 220 Hz land at 440 and 110 Hz (±1 cent).
- I3: each kind's integrated loudness on the owner's recording within ±1 LU of
  the dry export (ffmpeg's ebur128; the kind pitch at +7).
- I4: `{hall, amount 0}` exports equal to the dry export sample for sample,
  and `cache/voiced/` stays empty.
- I5: an export sent straight after `set_audio` (the render held 2 s) carries
  the echo.
- I6: cathedral on a burst 0.5 s before the clip's end: the export from the
  clip's end to a muted clip 3 s later is exactly 0.
- I7: `trim_start` by one frame on the first of two voiced clips lands a new
  file and prunes the old one; the second clip's file is kept, unchanged.
- I8: a reversed clip with echo: the echo follows the click in playback time.
- I9: isolation 1 and `{pitch, 2}` on the recording: the voiced file lands
  after the isolated one, and the pause floor is ≥ 9 dB under dry (AP5 I2's
  classifier).
- I10: `set_audio` refuses amount 1.5, pitch 13 and kind `robo`, each in the
  core's sentence.
- I11: ×2 with Keep pitch off: no voiced file, and the export equals the
  voice-less export.
- M1–M5, Clip ▸ Voice ▸ through `perform_menu_item` (AU-158), on two tone
  clips A and B and a text clip; "the listing" is `perform_menu_item` with no
  path, whose seventeen `setVoiceEffect:` leaves carry `enabled` and `state`:
  M1 nothing selected, then only the text clip: all seventeen disabled, Radio
  refused as disabled, the project unchanged. M2 A selected: Radio writes
  `{radio, 1}` with no pitch to A alone, the listing reads Radio on and the
  other sixteen off, Radio again changes nothing, and one `undo` clears A and
  checks None. M3 A at `{high, 0.4, 8}` and B, both selected: Deep gives
  `{deep, 0.4}` and `{deep, 1}`, neither with a pitch, and ONE `undo`
  restores both. M4 A radio and B echo: Radio and Echo mixed, None off; B
  cleared: Radio and None mixed, Echo off. M5 None on A and B clears both,
  None reads on, and one `undo` brings both back.

**Mutants** (`--mutants`; each over its own copy of `app/Sources`, killed when
its named row fails): call-size 1024 (V5), preset via `loadFactoryPreset` (V9),
pitch-zero-kept (V3), window-not-keyed (V4), isolation-ignored (V6),
voice-before-isolation (V3), pending-silent (V1), export-no-wait (V8),
tail-kept +48,000 frames (V5), mono-left (V7), latency-kept (V10); and the
menu's seven (AU-158): menu-mixed-as-on, menu-mixed-unmarked and
menu-none-unmarked (V13), menu-amount-from-first, menu-pitch-kept and
menu-targets-all (V14), menu-order-flat (V12). `--mutants a,b` runs the named
ones. latency-kept
surviving with V10's pitch +7 latency at ≤ 48 frames prints `equivalent` and is
left out of the count (spec step 9); exit 0 when every other mutant is killed.

Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff all pass.
"""

import argparse
import math
import re
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

WORK = ROOT / "tools/proof/work/voice"
RODE = ROOT / "samples/Rode-usb-mic.m4a"
SR = 48000
SEC = 600_000
FRAME = 20_000
HOLD_S = 2
CALL_BOUND = 600
VOLUME = 4.0
PROBE_ROWS = ["V1", "V2", "V3", "V4", "V5", "V6", "V7", "V8", "V9", "V10", "V11", "V12", "V13",
              "V14"]
KINDS = ["pitch", "high", "deep", "robot", "bass", "treble", "bright", "telephone", "radio",
         "lofi", "distorted", "echo", "room", "hall", "plate", "cathedral"]

rows = []


def row(row_id, ok, detail):
    rows.append((row_id, bool(ok)))
    print(f"{row_id} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


# ---- the probe -------------------------------------------------------------------

def build_probe(sources, name):
    out = WORK / name
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "voice_probe.swift", entry)
    blank = out / "Blank.mp4"
    if not blank.exists():
        shutil.copyfile(ROOT / "app/Resources/Blank.mp4", blank)
    binary = out / "voice-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [str(entry)], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc: " + " | ".join((errors or list(error.diagnostics) or [str(error)])[:6])
    return binary, ""


def run_probe(sources, name, extra=()):
    """({row: (passed, detail)}, problem, stdout) — None rows when it did not build."""
    binary, problem = build_probe(sources, name)
    if binary is None:
        return None, problem, ""
    scratch = WORK / name / "scratch"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    try:
        result = subprocess.run([str(binary), str(scratch), str(RODE), *extra],
                                capture_output=True, text=True, timeout=900,
                                cwd=str(binary.parent))
    except subprocess.TimeoutExpired:
        return {}, "the probe ran past 900 s and was killed", ""
    found = {}
    for line in result.stdout.splitlines():
        parts = line.split(" ", 2)
        if len(parts) >= 2 and parts[0] in ("ok", "FAIL"):
            detail = parts[2][2:] if len(parts) > 2 and parts[2].startswith("— ") else ""
            found[parts[1]] = (parts[0] == "ok", detail)
    return found, result.stderr.strip()[-600:], result.stdout


def probe_rows(sources=ROOT / "app/Sources"):
    found, problem, _ = run_probe(sources, "probe")
    for name in PROBE_ROWS:
        if found is None:
            row(name, False, "the probe does not build: " + problem)
        elif name not in found:
            row(name, False, "the probe did not answer" + (f": {problem}" if problem else ""))
        else:
            row(name, *found[name])


def measure():
    _, problem, out = run_probe(ROOT / "app/Sources", "measure", extra=["measure"])
    lines = [line for line in out.splitlines() if line.startswith("measure")]
    for line in lines:
        print(line, flush=True)
    if not lines:
        print(f"measure FAIL — no reading: {problem}", flush=True)
    return bool(lines) and not any("FAIL" in line for line in lines)


# ---- mutants ---------------------------------------------------------------------

SILENT_BUILDER_OLD = (
    "                let isolation = isolated.isEmpty && voiced.isEmpty\n"
    "                    ? nil\n"
    "                    : AudioIsolationTrack(\n"
    "                        segments: family.segments, shift: shift, dsp: dsp, renders: isolated,\n"
    "                        voiced: voiced)\n")
SILENT_BUILDER_NEW = (
    "                let isolation = dsp.isolates || dsp.voices\n"
    "                    ? AudioIsolationTrack(\n"
    "                        segments: family.segments, shift: shift, dsp: dsp, renders: isolated,\n"
    "                        voiced: voiced)\n"
    "                    : nil\n")

# name, rows any one of which must fail, [(file, before exactly once, after)].
MUTANTS = [
    ("call-size-1024", ["V5"], [
        ("VoiceRenderer.swift",
         "    static let callFrames: AVAudioFrameCount = 4096\n",
         "    static let callFrames: AVAudioFrameCount = 1024\n")]),
    ("preset-via-loadFactoryPreset", ["V9"], [
        ("VoiceChain.swift",
         "        unit.auAudioUnit.currentPreset = preset\n",
         "        _ = preset\n"
         "        if let reverb = unit as? AVAudioUnitReverb,\n"
         "            let known = AVAudioUnitReverbPreset(rawValue: number)\n"
         "        { reverb.loadFactoryPreset(known) }\n"
         "        if let distortion = unit as? AVAudioUnitDistortion,\n"
         "            let known = AVAudioUnitDistortionPreset(rawValue: number)\n"
         "        { distortion.loadFactoryPreset(known) }\n")]),
    ("pitch-zero-kept", ["V3"], [
        ("VoiceChain.swift",
         "            if cents.rounded() != 0 { stages.append(.timePitch(cents: cents)) }\n",
         "            stages.append(.timePitch(cents: cents))\n")]),
    ("window-not-keyed", ["V4"], [
        ("VoiceCache.swift",
         '            + "|w\\(window.firstFrame):\\(window.endFrame)"\n',
         "")]),
    ("isolation-ignored", ["V6"], [
        ("VoiceRenderer.swift",
         "                            x += i * (wet - x)\n",
         "                            _ = wet\n")]),
    ("voice-before-isolation", ["V3"], [
        ("VoiceCache.swift",
         "                for: s, dsp: dsp, urls: urls, reverse: reverse),\n"
         "                FileManager.default.fileExists(atPath: request.destination.path)\n"
         "            else { return nil }\n",
         "                for: s, dsp: dsp, urls: urls, reverse: reverse)\n"
         "            else { return nil }\n")]),
    # A pending voice plays SILENT: an empty pass still earns a tap, and the
    # tap zeroes a buffer when it has no span (AP5's mutant, on the voice).
    ("pending-silent", ["V1"], [
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
    ("export-no-wait", ["V8"], [
        ("Exporter+RampAudio.swift",
         "                try wait(for: voices, wanting: requests + voices, key: key, cancelled: cancelled)\n",
         "                _ = voices\n")]),
    ("tail-kept", ["V5"], [
        ("VoiceRenderer.swift",
         "            let frames = job.job.window.endFrame - job.job.window.firstFrame\n",
         "            let frames = job.job.window.endFrame - job.job.window.firstFrame + 48_000\n")]),
    ("mono-left", ["V7"], [
        ("VoiceRenderer.swift",
         "                            out[i] = (l + r) * 0.5 * gain\n",
         "                            out[i] = l * gain\n")]),
    ("latency-kept", ["V10"], [
        ("VoiceRenderer.swift",
         "            let discard = Int64(latency)\n",
         "            let discard: Int64 = 0\n")]),
    # Clip ▸ Voice ▸ (spec §11 AU-158), one per decision.
    ("menu-mixed-as-on", ["V13"], [
        ("VoiceMenu.swift",
         "        return carrying == targets.count ? .on : .mixed\n",
         "        return .on\n")]),
    ("menu-mixed-unmarked", ["V13"], [
        ("VoiceMenu.swift",
         "        return carrying == targets.count ? .on : .mixed\n",
         "        return carrying == targets.count ? .on : .off\n")]),
    ("menu-none-unmarked", ["V13"], [
        ("VoiceMenu.swift",
         "        let carrying = targets.filter { $0.audioProps.voice?.kind == kind }.count\n",
         "        guard kind != nil else { return .off }\n"
         "        let carrying = targets.filter { $0.audioProps.voice?.kind == kind }.count\n")]),
    # The popup's rule: every clip gets the first clip's amount.
    ("menu-amount-from-first", ["V14"], [
        ("VoiceMenu.swift",
         "            let voice = VoiceProps.choosing(kind, over: clip.audioProps.voice)\n",
         "            let voice = VoiceProps.choosing(kind, over: targets[0].audioProps.voice)\n")]),
    ("menu-pitch-kept", ["V14"], [
        ("VoiceProps.swift",
         "        return VoiceProps(kind: kind, amount: current?.amount ?? 1, pitch: nil)\n",
         "        return VoiceProps(kind: kind, amount: current?.amount ?? 1, pitch: current?.pitch)\n")]),
    ("menu-targets-all", ["V14"], [
        ("VoiceMenu.swift",
         "        clips.filter { InspectorTab.hasAudio($0, in: snapshot) }\n",
         "        _ = snapshot\n"
         "        return clips\n")]),
    ("menu-order-flat", ["V12"], [
        ("AppDelegate+ClipMenus.swift",
         "        for group in VoiceGroup.allCases {\n"
         "            menu.addItem(.sectionHeader(title: group.title))\n"
         "            for kind in group.kinds {\n"
         "                menu.addItem(tagged(kind.name, action, VoiceMenu.tag(of: kind)))\n"
         "            }\n"
         "        }\n",
         "        for kind in VoiceKind.allCases {\n"
         "            menu.addItem(tagged(kind.name, action, VoiceMenu.tag(of: kind)))\n"
         "        }\n")]),
]


# A mutant that survives only because what it removes measures nothing on this
# host is equivalent, not a survivor (spec step 9): latency-kept when V10 reads
# the pitch +7 chain's latency as at most 48 frames (1 ms).
EQUIVALENT_LATENCY_FRAMES = 48


def equivalence(name, found):
    """The reason a surviving mutant is equivalent, or None."""
    if name != "latency-kept":
        return None
    match = re.search(r"pitch \+7: [^;]*latency (\d+) frames", found.get("V10", (None, ""))[1])
    if match and int(match.group(1)) <= EQUIVALENT_LATENCY_FRAMES:
        return f"latency {match.group(1)} frames"
    return None


def mutants(only=None):
    killed = 0
    equivalent = 0
    sources = ROOT / "app/Sources"
    chosen = [m for m in MUTANTS if only is None or m[0] in only]
    for name in sorted(set(only or []) - {m[0] for m in MUTANTS}):
        row(f"mutant {name}", False, "no mutant has that name")
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
        found, why, _ = run_probe(tree, f"mutant-{name}")
        if found is None:
            row(f"mutant {name}", False, "did not build: " + why)
            continue
        failing = sorted(r for r in PROBE_ROWS if not found.get(r, (False, ""))[0])
        dead = any(found.get(r, (True, ""))[0] is False for r in targets)
        detail = "; ".join(f"{r}: {found.get(r, (None, 'no answer'))[1]}" for r in targets)
        why_equivalent = None if dead else equivalence(name, found)
        if why_equivalent:
            equivalent += 1
            print(f"mutant {name} equivalent ({why_equivalent}) — failing rows: "
                  + (", ".join(failing) or "none") + f" — {detail[:400]}", flush=True)
            continue
        killed += dead
        row(f"mutant {name}", dead, f"killed by {'/'.join(targets)}: {dead}; failing rows: "
            + (", ".join(failing) or "none") + f" — {detail[:400]}")
    scored = len(chosen) - equivalent
    print(f"{killed}/{scored} mutants killed"
          + (f", {equivalent} equivalent" if equivalent else ""), flush=True)
    return killed == scored and all(ok for _, ok in rows)


# ---- fixtures --------------------------------------------------------------------

FIXTURES = {
    "tone220": "sine=frequency=220:sample_rate=48000:duration=4,volume=0.251",
    "tone1k": "sine=frequency=1000:sample_rate=48000:duration=4,volume=0.251",
    "noise": "anoisesrc=color=white:sample_rate=48000:duration=4:amplitude=0.087:seed=7",
}


def make_fixtures():
    folder = WORK / "fixtures"
    folder.mkdir(parents=True, exist_ok=True)
    paths = {}
    for name, graph in FIXTURES.items():
        path = folder / f"{name}.wav"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", graph, "-ac", "1",
                        "-c:a", "pcm_f32le", str(path)], check=True, timeout=60)
        paths[name] = path
    # A click: one sample at 0.9 at 1 s in 4 s; a burst: 50 ms of −6 dBFS RMS
    # noise at 0.5 s in 10 s. Written by numpy, through ffmpeg's WAV muxer.
    rng = np.random.default_rng(5)
    click = np.zeros(4 * SR, dtype="<f4")
    click[SR] = 0.9
    burst = np.zeros(10 * SR, dtype="<f4")
    burst[SR // 2: SR // 2 + SR // 20] = rng.uniform(-0.866, 0.866, SR // 20)
    for name, data in (("click", click), ("burst", burst)):
        path = folder / f"{name}.wav"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1",
                        "-i", "-", "-c:a", "pcm_f32le", str(path)], input=data.tobytes(),
                       check=True, timeout=60)
        paths[name] = path
    return paths


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

    def place(self, path, at=0, source_in=0, track_index=0, media=None, volume=None):
        """`path` as a clip from `source_in` placed at `at`; `media` an id it
        was already imported as."""
        if media is None:
            media = self.must("import_media", path=str(path))["media"]
        tracks = self.project()["tracks"]
        while len(tracks) <= track_index:
            self.must("add_track")
            tracks = self.project()["tracks"]
        track = tracks[track_index]["id"]
        first = 0 if source_in else at
        clip = self.must("add_clip", track=track, media=media, at=first)["new_clips"][0]
        if source_in:
            self.must("trim_start", clip=clip, to=source_in)
        start = self.clip(clip)["start"]
        if start != at:
            self.must("move_clip", clips=[clip], delta=at - start)
        if volume is not None:
            self.must("set_audio", clips=[clip], patch={"volume": volume})
        return clip, media

    def voice(self, clip, voice):
        self.must("set_audio", clips=[clip], patch={"voice": voice})

    def export(self, tag):
        out = WORK / "exports" / f"{tag}.wav"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.unlink(missing_ok=True)
        self.client.export_with({"project": self.path, "preset": "audio_wav",
                                 "path": str(out)}, seconds=CALL_BOUND)
        return out

    def renders(self, folder="voiced"):
        where = Path(self.path) / "cache" / folder
        return sorted(p.name for p in where.iterdir() if p.suffix == ".caf") \
            if where.is_dir() else []

    def close(self):
        attempt(self.client, "close_project", {"project": self.path, "discard": True})


def decode(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-acodec", "pcm_f32le",
         "-ar", str(SR), "-ac", "2", "-"], check=True, timeout=120, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").astype(np.float64)[0::2]


def lufs(path):
    """ffmpeg's ebur128 integrated loudness of `path`."""
    out = subprocess.run(["ffmpeg", "-nostats", "-i", str(path), "-af", "ebur128", "-f", "null",
                          "-"], capture_output=True, text=True, timeout=120).stderr
    found = re.findall(r"I:\s+(-?[\d.]+) LUFS", out)
    return float(found[-1]) if found else math.nan


def db(x, floor=1e-30):
    return 10 * np.log10(np.maximum(x, floor))


def spectrum(x, start=0.5, seconds=2.0):
    seg = x[int(start * SR): int((start + seconds) * SR)]
    win = np.hanning(len(seg))
    nfft = 1 << 20
    mag = np.abs(np.fft.rfft(seg * win, nfft)) ** 2
    return mag, np.fft.rfftfreq(nfft, 1 / SR)


def peak_hz(x, lo=50, hi=2000):
    mag, f = spectrum(x)
    band = (f >= lo) & (f <= hi)
    i = int(np.argmax(np.where(band, mag, 0)))
    a, b, c = np.log(mag[i - 1] + 1e-30), np.log(mag[i] + 1e-30), np.log(mag[i + 1] + 1e-30)
    p = 0.5 * (a - c) / (a - 2 * b + c)
    return (i + p) * (f[1] - f[0])


def bin_power(x, hz, width=5):
    mag, f = spectrum(x)
    return mag[(f >= hz - width) & (f <= hz + width)].sum()


def octave(x, fc):
    mag, f = spectrum(x)
    return mag[(f >= fc / math.sqrt(2)) & (f < fc * math.sqrt(2))].sum()


def cents(got, want):
    return 1200 * math.log2(got / want) if got > 0 else math.inf


def reverb_tail(x, burst_end=1.05):
    """Seconds from the burst's end (the clip at 0.5 s) until the 10 ms RMS
    stays under −60 dBFS."""
    block = SR // 100
    n = len(x) // block
    levels = db(np.mean(x[: n * block].reshape(n, block) ** 2, axis=1))
    above = np.nonzero(levels > -60)[0]
    return (above[-1] + 1) / 100 - burst_end if len(above) else -burst_end


def kind_rows(client, fx):
    """K1–K16 and I2: every kind at amount 1 on its fixture."""
    doc = Doc(client, "kinds")
    results = {}
    try:
        # One after another with a second between, each muted until its turn.
        clips = {}
        at = 0
        for name in ("tone220", "tone1k", "noise", "click", "burst"):
            clips[name], _ = doc.place(fx[name], at=at)
            doc.must("set_audio", clips=[clips[name]], patch={"muted": True})
            placed = doc.clip(clips[name])
            at = placed["start"] + placed["duration"] + SEC
        dry = {}

        def solo(name, voice, tag):
            clip = clips[name]
            doc.must("set_audio", clips=[clip], patch={"muted": False, "voice": voice})
            # Only the one clip sounds; the export is the whole timeline, so
            # read the clip's own span.
            start = doc.clip(clip)["start"]
            out = decode(doc.export(tag))
            doc.must("set_audio", clips=[clip], patch={"muted": True, "voice": None})
            first = int(round(start * SR / SEC))
            length = {"burst": 10, "click": 4}.get(name, 4) * SR
            return out[first: first + length]

        for name in ("tone220", "tone1k", "noise", "click", "burst"):
            dry[name] = solo(name, None, f"dry-{name}")
        for tag, voice, fixture in [
            ("pitch", {"kind": "pitch", "pitch": 7}, "tone220"),
            ("high", {"kind": "high"}, "tone220"), ("deep", {"kind": "deep"}, "tone220"),
            ("pitch+12", {"kind": "pitch", "pitch": 12}, "tone220"),
            ("pitch-12", {"kind": "pitch", "pitch": -12}, "tone220"),
            ("robot", {"kind": "robot"}, "tone1k"), ("bass", {"kind": "bass"}, "noise"),
            ("treble", {"kind": "treble"}, "noise"), ("bright", {"kind": "bright"}, "noise"),
            ("telephone", {"kind": "telephone"}, "noise"), ("radio", {"kind": "radio"}, "noise"),
            ("lofi", {"kind": "lofi"}, "tone1k"), ("distorted", {"kind": "distorted"}, "tone1k"),
            ("echo", {"kind": "echo"}, "click"), ("room", {"kind": "room"}, "burst"),
            ("plate", {"kind": "plate"}, "burst"), ("hall", {"kind": "hall"}, "burst"),
            ("cathedral", {"kind": "cathedral"}, "burst"),
        ]:
            results[tag] = solo(fixture, voice, tag)
    finally:
        doc.close()

    def tone_row(row_id, tag, want):
        got = peak_hz(results[tag])
        off = cents(got, want)
        row(row_id, abs(off) <= 1, f"{tag} on 220 Hz: {got:.3f} Hz (want {want:.2f}), "
            f"{off:+.2f} cents (±1)")

    tone_row("K1", "pitch", 220 * 2 ** (7 / 12))
    tone_row("K2", "high", 220 * 2 ** (5 / 12))
    tone_row("K3", "deep", 220 * 2 ** (-5 / 12))
    r = results["robot"]
    centre, low, high = bin_power(r, 1000), bin_power(r, 940), bin_power(r, 1060)
    row("K4", db(low) - db(centre) >= 10 and db(high) - db(centre) >= 10,
        f"robot on 1 kHz: 940 Hz {db(low) - db(centre):+.1f} dB, 1060 Hz "
        f"{db(high) - db(centre):+.1f} dB re the 1 kHz bin (≥ +10)")
    n = dry["noise"]

    def tilt(x, a, b):
        return (db(octave(x, a)) - db(octave(x, b))) - (db(octave(n, a)) - db(octave(n, b)))

    for row_id, tag, a, b, bound in [("K5", "bass", 63, 2000, 6), ("K6", "treble", 8000, 250, 6),
                                      ("K7", "bright", 3000, 250, 3)]:
        t = tilt(results[tag], a, b)
        also = f"; 4000 Hz − 250 Hz {tilt(results[tag], 4000, 250):+.1f} dB (reported)" \
            if tag == "bright" else ""
        row(row_id, t >= bound, f"{tag} on white noise: {a} Hz − {b} Hz {t:+.1f} dB against "
            f"dry (≥ +{bound}){also}")
    for row_id, tag, bound in [("K8", "telephone", 20), ("K9", "radio", 15)]:
        lo, hi = tilt(results[tag], 125, 1000), tilt(results[tag], 8000, 1000)
        row(row_id, lo <= -bound and hi <= -bound, f"{tag} on white noise: 125 Hz {lo:+.1f} dB, "
            f"8 kHz {hi:+.1f} dB re 1 kHz against dry (≤ −{bound})")

    def outside(x):
        mag, f = spectrum(x)
        return mag[(f < 900) | (f > 1100)].sum()

    lofi = db(outside(results["lofi"])) - db(outside(dry["tone1k"]))
    row("K10", lofi >= 20, f"lofi on 1 kHz: energy outside 900–1100 Hz {lofi:+.1f} dB over "
        "dry's (≥ +20)")
    d = results["distorted"]
    harmonics = sum(bin_power(d, h) for h in (2000, 3000, 4000, 5000))
    rel = db(harmonics) - db(bin_power(d, 1000))
    row("K11", rel >= -30, f"distorted on 1 kHz: harmonics 2–5 kHz {rel:+.1f} dB re the "
        "fundamental (≥ −30)")
    e = np.abs(results["echo"])
    click = int(np.argmax(np.abs(dry["click"])))
    lands = []
    for delay in (0.25, 0.5):
        centre = click + int(delay * SR)
        part = e[centre - 2 * SR // 100: centre + 2 * SR // 100]
        lands.append((int(np.argmax(part)) - 2 * SR // 100) / SR * 1000)
    row("K12", all(abs(x) <= 1 for x in lands),
        f"echo of a click at sample {click}: echoes at +250 ms {lands[0]:+.2f} ms and +500 ms "
        f"{lands[1]:+.2f} ms off (±1)")
    for row_id, tag, lo, hi in [("K13", "room", 0.05, 0.6), ("K14", "plate", 0.05, 0.6),
                                ("K15", "hall", 1.0, 3.5), ("K16", "cathedral", 3.0, 8.0)]:
        t = reverb_tail(results[tag], burst_end=0.55)
        row(row_id, lo <= t <= hi, f"{tag} after a 50 ms burst: {t:.3f} s to stay under "
            f"−60 dBFS ({lo}–{hi})")
    up, down = peak_hz(results["pitch+12"]), peak_hz(results["pitch-12"], lo=50, hi=500)
    row("I2", abs(cents(up, 440)) <= 1 and abs(cents(down, 110)) <= 1,
        f"pitch +12 on 220 Hz: {up:.3f} Hz ({cents(up, 440):+.2f} cents); −12: {down:.3f} Hz "
        f"({cents(down, 110):+.2f} cents) (±1)")


def i3(client, fx):
    doc = Doc(client, "i3")
    try:
        clip, _ = doc.place(RODE, volume=VOLUME)
        dry = lufs(doc.export("i3-dry"))
        parts, ok = [], True
        for kind in KINDS:
            doc.voice(clip, {"kind": kind, "amount": 1, "pitch": 7 if kind == "pitch" else None})
            wet = lufs(doc.export(f"i3-{kind}"))
            ok = ok and abs(wet - dry) <= 1
            parts.append(f"{kind} {wet - dry:+.2f}")
        row("I3", ok, f"dry {dry:.2f} LUFS; each kind against it (±1 LU): " + ", ".join(parts))
    finally:
        doc.close()


def i4_i5(client, fx):
    doc = Doc(client, "i4")
    try:
        clip, _ = doc.place(fx["click"])
        dry = decode(doc.export("i4-dry"))
        doc.voice(clip, {"kind": "hall", "amount": 0})
        zero = decode(doc.export("i4-zero"))
        same = len(dry) == len(zero) and np.array_equal(dry, zero)
        files = doc.renders()
        row("I4", same and not files, f"hall at amount 0: equal to dry sample for sample: {same} "
            f"({len(zero)} vs {len(dry)} frames); cache/voiced/ {files}")
        doc.voice(clip, {"kind": "echo", "amount": 1})
        started = time.monotonic()
        wet = np.abs(decode(doc.export("i5-echo")))
        waited = time.monotonic() - started
        click = int(np.argmax(np.abs(dry)))
        echo = float(np.max(wet[click + SR // 4 - 48: click + SR // 4 + 48]))
        quiet = float(np.max(np.abs(dry)[click + SR // 4 - 48: click + SR // 4 + 48]))
        row("I5", echo > 0.05 and quiet == 0, f"exported straight after set_audio (hold "
            f"{HOLD_S} s): {waited:.1f} s to finish; peak at +250 ms {echo:.3f} (dry {quiet})")
    finally:
        doc.close()


def i6(client, fx):
    doc = Doc(client, "i6")
    try:
        # The burst runs 0.5–0.55 s of the media; the clip from 0.05 s to
        # 1.05 s, so it ends 0.5 s after the burst starts.
        clip, media = doc.place(fx["burst"], source_in=SEC // 20)
        doc.must("trim_end", clip=clip, to=SEC)
        end = doc.clip(clip)
        end = end["start"] + end["duration"]
        later, _ = doc.place(fx["burst"], at=end + 3 * SEC, media=media)
        doc.must("set_audio", clips=[later], patch={"muted": True})
        doc.voice(clip, {"kind": "cathedral"})
        out = decode(doc.export("i6"))
        first = int(round(end * SR / SEC))
        after = out[first: first + 3 * SR]
        before = float(np.max(np.abs(out[first - SR // 10: first])))
        row("I6", len(after) == 3 * SR and not np.any(after),
            f"cathedral, burst 0.5 s before the clip's end: the last 100 ms before the end "
            f"peak {before:.3f}; {int(np.count_nonzero(after))} non-zero samples in the 3 s after")
    finally:
        doc.close()


def i7(client, fx):
    doc = Doc(client, "i7")
    try:
        # Two windows of one media: the second from 0.5 s.
        first, media = doc.place(fx["noise"])
        second, _ = doc.place(fx["noise"], at=5 * SEC, media=media)
        doc.must("trim_start", clip=second, to=5 * SEC + SEC // 2)
        doc.voice(first, {"kind": "telephone"})
        doc.voice(second, {"kind": "telephone"})
        doc.export("i7-before")
        before = doc.renders()
        folder = Path(doc.path) / "cache" / "voiced"
        kept = {}
        for name in before:
            kept[name] = (folder / name).read_bytes()
        doc.must("trim_start", clip=first, to=FRAME)
        doc.export("i7-after")
        deadline = time.monotonic() + 10
        after = doc.renders()
        while (len(after) != 2 or not set(before) - set(after)) and time.monotonic() < deadline:
            time.sleep(0.25)
            after = doc.renders()
        common = set(before) & set(after)
        unchanged = len(common) == 1 and all((folder / n).read_bytes() == kept[n] for n in common)
        ok = len(before) == 2 and len(after) == 2 and unchanged and len(set(after) - set(before)) == 1
        row("I7", ok, f"trim_start by one frame: renders before {before}, after {after}; the "
            f"neighbour's file kept unchanged: {unchanged}")
    finally:
        doc.close()


def wait_reverse(doc, media, bound=300):
    """None once `cache/reversed/<media>-*.mov` exists with no `.partial` and
    the window has no sheet; else why."""
    folder = Path(doc.path) / "cache" / "reversed"
    deadline = time.monotonic() + bound
    while True:
        files = sorted(folder.glob(f"{media}-*.mov")) if folder.is_dir() else []
        partial = folder.is_dir() and any(folder.glob(f"{media}-*.partial"))
        if files and not partial:
            got = doc.call("snapshot_ui", window="sheet", path=str(WORK / "i8-sheet.png"))
            if not got["ok"] and "no sheet attached" in got.get("error", ""):
                return None
        if time.monotonic() > deadline:
            return f"the reverse did not finish within {bound} s"
        time.sleep(0.25)


def i8(client, fx):
    doc = Doc(client, "i8")
    try:
        clip, media = doc.place(fx["click"])
        doc.must("set_reversed", clip=clip, reversed=True)
        late = wait_reverse(doc, media)
        dry = np.abs(decode(doc.export("i8-dry")))
        doc.voice(clip, {"kind": "echo"})
        wet = np.abs(decode(doc.export("i8-echo")))
        click = int(np.argmax(dry))
        after = float(np.max(wet[click + SR // 4 - 48: click + SR // 4 + 48]))
        before = float(np.max(wet[max(0, click - SR // 4 - 48): click - SR // 4 + 48]))
        row("I8", late is None and after > 0.05 and before < 0.01,
            f"reversed ({'ready' if late is None else late}): click at {click / SR:.3f} s; "
            f"peak 250 ms after {after:.3f}, 250 ms before {before:.4f}")
    finally:
        doc.close()


def windows(x, win_s=0.4):
    w = int(win_s * SR)
    n = len(x) // w
    return x[: n * w].reshape(n, w)


def floor_drop(dry, wet):
    """AP5 I2's classifier: pause within 6 dB of the 10th percentile."""
    n = min(len(dry), len(wet))
    lv = db(np.mean(windows(dry[:n]) ** 2, axis=1))
    pause = lv <= np.percentile(lv, 10) + 6
    return db(np.mean(windows(dry[:n])[pause] ** 2)) - db(np.mean(windows(wet[:n])[pause] ** 2))


def i9(client, fx):
    doc = Doc(client, "i9")
    try:
        clip, _ = doc.place(RODE, volume=VOLUME)
        dry = decode(doc.export("i9-dry"))
        doc.must("set_audio", clips=[clip], patch={"isolation": 1,
                                                   "voice": {"kind": "pitch", "pitch": 2}})
        wet = decode(doc.export("i9-wet"))
        root = Path(doc.path) / "cache"
        iso, voiced = doc.renders("isolated"), doc.renders("voiced")
        order = (len(iso) == 1 and len(voiced) == 1
                 and (root / "voiced" / voiced[0]).stat().st_mtime
                 >= (root / "isolated" / iso[0]).stat().st_mtime)
        drop = floor_drop(dry, wet)
        row("I9", order and drop >= 9, f"isolation 1 + pitch 2: isolated {iso}, voiced {voiced}, "
            f"voiced after isolated: {order}; pause floor lowered {drop:.1f} dB (≥ 9)")
    finally:
        doc.close()


def i10(client, fx):
    doc = Doc(client, "i10")
    try:
        clip, _ = doc.place(fx["tone220"])
        doc.voice(clip, {"kind": "pitch"})
        cases = [
            ({"amount": 1.5}, "audio.voice.amount must be between 0 and 1, not 1.5"),
            ({"pitch": 13}, "audio.voice.pitch must be between -12 and 12, not 13"),
            ({"kind": "robo"}, "bad value at \"voice.kind\" in an audio patch: unknown variant "
             "`robo`"),
        ]
        parts, ok = [], True
        for patch, sentence in cases:
            got = doc.call("set_audio", clips=[clip], patch={"voice": patch})
            good = not got["ok"] and sentence in got.get("error", "")
            ok = ok and good
            parts.append(f"{patch}: {got.get('error', got)[:160]}")
        row("I10", ok, "; ".join(parts))
    finally:
        doc.close()


def i11(client, fx):
    doc = Doc(client, "i11")
    try:
        clip, _ = doc.place(fx["noise"])
        doc.must("set_speed", clip=clip, rate=2.0, keep_pitch=False)
        dry = decode(doc.export("i11-dry"))
        doc.voice(clip, {"kind": "telephone"})
        wet = decode(doc.export("i11-voice"))
        files = doc.renders()
        same = len(dry) == len(wet) and np.array_equal(dry, wet)
        row("I11", same and not files, f"×2, Keep pitch off: cache/voiced/ {files}; the export "
            f"equals the voice-less one: {same} ({len(wet)} vs {len(dry)} frames)")
    finally:
        doc.close()


# ---- Clip ▸ Voice ▸ (spec §11 AU-158) --------------------------------------------

VOICE_SELECTOR = "setVoiceEffect:"
VOICE_MENU = ["Clip", "Voice"]
MENU_TITLES = ["Pitch", "High", "Deep", "Robot", "Bass", "Treble", "Bright", "Telephone",
               "Radio", "Lo-Fi", "Distorted", "Echo", "Room", "Hall", "Plate", "Cathedral",
               "None"]


def menu_items(doc):
    """{title: leaf} of the listing's `setVoiceEffect:` leaves under Clip ▸ Voice."""
    listing = doc.must("perform_menu_item")
    return {item["path"][-1]: item for item in listing["items"]
            if item.get("selector") == VOICE_SELECTOR and item["path"][:2] == VOICE_MENU}


def menu_states(doc):
    return {title: item["state"] for title, item in menu_items(doc).items()}


def expect_states(states, **marks):
    """Whether `states` has all seventeen titles, each `off` but the ones named."""
    want = {title: "off" for title in MENU_TITLES}
    want.update(marks)
    return states == want


def marked(states):
    return {title: state for title, state in states.items() if state != "off"} or "none marked"


def choose(doc, title):
    return doc.call("perform_menu_item", path=VOICE_MENU + [title])


def voice_of(doc, clip):
    return (doc.clip(clip).get("audio") or {}).get("voice")


def menu_rows(client, fx):
    doc = Doc(client, "menu")
    try:
        a, _ = doc.place(fx["tone220"])
        b, _ = doc.place(fx["tone1k"], at=5 * SEC)
        before = {c["id"] for c in doc.project()["clips"]}
        doc.must("add_text_clip", track=doc.project()["tracks"][0]["id"], at=10 * SEC,
                 duration=2 * SEC)
        text = next(c["id"] for c in doc.project()["clips"] if c["id"] not in before)

        # M1 — no target.
        parts, ok = [], True
        start = doc.project()
        for label, selection in (("nothing selected", []), ("only the text clip", [text])):
            doc.must("set_selection", clips=selection)
            items = menu_items(doc)
            off = sorted(t for t, item in items.items() if item["enabled"] is False)
            got = choose(doc, "Radio")
            refused = not got["ok"] and "is disabled here" in got.get("error", "")
            ok = ok and sorted(items) == sorted(MENU_TITLES) and len(off) == 17 and refused
            parts.append(f"{label}: {len(items)} setVoiceEffect: leaves, {len(off)} disabled; "
                         f"Radio: {str(got.get('error', got))[:120]}")
        same = doc.project() == start
        row("M1", ok and same, "; ".join(parts) + f"; the project unchanged: {same}")

        # M2 — one clip, the mark, an identity, one undo.
        doc.must("set_selection", clips=[a])
        got = choose(doc, "Radio")
        va, vb = voice_of(doc, a), voice_of(doc, b)
        states = menu_states(doc)
        wrote = got["ok"] and va == {"kind": "radio", "amount": 1} and vb is None
        mark = expect_states(states, Radio="on")
        held = doc.project()
        again = choose(doc, "Radio")
        identity = doc.project() == held
        doc.must("undo")
        after = menu_states(doc)
        undone = voice_of(doc, a) is None and expect_states(after, **{"None": "on"})
        row("M2", wrote and mark and identity and undone,
            f"Radio on A: A {va}, B {vb} (want {{radio, 1}} with no pitch, none); marked "
            f"{marked(states)} (want Radio on alone); Radio again leaves the project "
            f"unchanged: {identity} ({'ran' if again['ok'] else again.get('error', '')[:80]}); "
            f"one undo: A {voice_of(doc, a)}, marked {marked(after)}")

        # M3 — each clip's own amount, no pitch, one undo step.
        doc.voice(a, {"kind": "high", "amount": 0.4, "pitch": 8})
        doc.must("set_selection", clips=[a, b])
        got = choose(doc, "Deep")
        va, vb = voice_of(doc, a), voice_of(doc, b)
        wrote = (got["ok"] and va == {"kind": "deep", "amount": 0.4}
                 and vb == {"kind": "deep", "amount": 1})
        doc.must("undo")
        ua, ub = voice_of(doc, a), voice_of(doc, b)
        undone = ua == {"kind": "high", "amount": 0.4, "pitch": 8} and ub is None
        row("M3", wrote and undone,
            f"Deep on A {{high, 0.4, 8}} and B none: A {va}, B {vb} (want {{deep, 0.4}}, "
            f"{{deep, 1}}, no pitch); one undo: A {ua}, B {ub}")

        # M4 — the dash.
        doc.voice(a, {"kind": "radio", "pitch": None})
        doc.voice(b, {"kind": "echo"})
        doc.must("set_selection", clips=[a, b])
        two = menu_states(doc)
        doc.voice(b, None)
        doc.must("set_selection", clips=[a, b])
        one = menu_states(doc)
        row("M4", expect_states(two, Radio="mixed", Echo="mixed")
            and expect_states(one, Radio="mixed", **{"None": "mixed"}),
            f"A radio, B echo: marked {marked(two)} (want Radio and Echo mixed); B cleared: "
            f"{marked(one)} (want Radio and None mixed)")

        # M5 — None.
        doc.voice(b, {"kind": "echo"})
        doc.must("set_selection", clips=[a, b])
        got = choose(doc, "None")
        va, vb = voice_of(doc, a), voice_of(doc, b)
        states = menu_states(doc)
        cleared = (got["ok"] and va is None and vb is None
                   and expect_states(states, **{"None": "on"}))
        doc.must("undo")
        ua, ub = voice_of(doc, a), voice_of(doc, b)
        back = (ua or {}).get("kind") == "radio" and (ub or {}).get("kind") == "echo"
        row("M5", cleared and back,
            f"None on A radio and B echo: A {va}, B {vb}, marked {marked(states)} (want none, "
            f"none, None on); one undo: A {ua}, B {ub}")
    finally:
        doc.close()


MENU_ROWS = [menu_rows]
APP_ROWS = [kind_rows, i3, i4_i5, i6, i7, i8, i9, i10, i11] + MENU_ROWS
ROW_NAMES = {kind_rows: [f"K{i}" for i in range(1, 17)] + ["I2"], i3: ["I3"],
             i4_i5: ["I4", "I5"], i6: ["I6"], i7: ["I7"], i8: ["I8"], i9: ["I9"],
             i10: ["I10"], i11: ["I11"], menu_rows: ["M1", "M2", "M3", "M4", "M5"]}


def complaints(log):
    try:
        with open(log, errors="replace") as handle:
            return [line.rstrip() for line in handle if "Frame Job: " in line]
    except OSError as error:
        return [f"the log could not be read: {error}"]


def app_rows(runners=None):
    runners = APP_ROWS if runners is None else runners
    try:
        fx = make_fixtures()
    except (OSError, subprocess.SubprocessError) as error:
        for runner in runners:
            for name in ROW_NAMES[runner]:
                row(name, False, f"the fixtures could not be made: {error}")
        row("I0", False, "no fixtures")
        return
    log = WORK / "framejob.log"
    binary = proof_app.binary()
    launched = mcp.launch(str(binary), arguments=["-RCDevRampRenderHold", str(HOLD_S)],
                          env=bounded.child_env(), log_path=str(log), timeout=CALL_BOUND)
    up = launched.client is not None
    try:
        if up:
            print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        for runner in runners:
            if not up:
                for name in ROW_NAMES[runner]:
                    row(name, False, f"the app did not listen at {launched.socket_path}")
                continue
            if runner in (i3, i9) and not RODE.exists():
                for name in ROW_NAMES[runner]:
                    row(name, False, f"{RODE} is missing")
                continue
            done = len(rows)
            try:
                runner(launched.client, fx)
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
    parser.add_argument("--measure", action="store_true")
    parser.add_argument("--mutants", nargs="?", const="", default=None, metavar="NAME[,NAME]",
                        help="every mutant, or the named ones")
    parser.add_argument("--instance", action="store_true", help="the I, K and M rows alone")
    parser.add_argument("--menu", action="store_true", help="I0 and M1–M5 alone")
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    if args.measure:
        return 0 if measure() else 1
    if args.mutants is not None:
        return 0 if mutants([n for n in args.mutants.split(",") if n] or None) else 1
    if not (args.instance or args.menu):
        probe_rows()
    if not args.probe:
        shutil.rmtree(WORK / "projects", ignore_errors=True)
        shutil.rmtree(WORK / "exports", ignore_errors=True)
        (WORK / "framejob.log").unlink(missing_ok=True)
        app_rows(MENU_ROWS if args.menu else None)
    passed = sum(1 for _, ok in rows if ok)
    print(f"{passed}/{len(rows)}", flush=True)
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
