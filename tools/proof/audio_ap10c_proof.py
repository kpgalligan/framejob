"""Road map "audio" AP10 part 2b — a track's compressor and limiter (spec §11
AU-150..AU-156), measured on exports and the live meter over MCP, and the
probe behind it.

    python3 tools/proof/audio_ap10c_proof.py <dir>/agent.sock [--only T1,P1,...]
    python3 tools/proof/audio_ap10c_proof.py --probe
    python3 tools/proof/audio_ap10c_proof.py --mutants

The caller owns the instance at that socket; nothing is launched or killed.
Needs `ffmpeg`, `ffprobe` and numpy. `--probe` runs B1–B5 alone, with no
instance. `--mutants` runs M1–M4, M6, M7, M10 and M11 (`--only M11` for the
ones named), each over its own copy of
`app/Sources`, killed when its named probe row fails; M5 (killed by T6 on a
mutated Debug build) and M8, M9 (killed by `core/tests/track_dynamics.rs`) are
run by hand, and the script prints their anchors. Every project is a new one,
closed with `close_project` (discarded). Output is under
`tools/proof/work/audio_ap10c/`.

**Fixtures**, made on the first run into `tools/proof/media/` (kept), 48 kHz
stereo 24-bit WAV, 6 s: `ap10c_hot_a.wav` (440 Hz at −1 dBFS),
`ap10c_hot_b.wav` (660 Hz at −1 dBFS), `ap10c_mid_a.wav` and `ap10c_mid_b.wav`
(the same at −6 dBFS), `ap10c_sine10.wav` (440 Hz at −10 dBFS),
`ap10c_music.wav` (three sines and pink noise near −20 dBFS RMS).

Rows:
- **T1** one track: the hot 440 Hz clip at 0 trimmed to 4 s, the hot 660 Hz
  clip at 4 s, a 1 s crossfade (`add_transition`, align after), the track
  limited at −6 dBTP: the `tracks` stem (24-bit, `peak_dbtp` 0) ≤ −6 + 0.01
  dBTP by both of `limiter_probe.py`'s meters; the same project without the
  limiter > −5.5.
- **T2** the −10 dBFS sine, the track compressed (threshold −20, ratio 4,
  makeup 3): its 440 Hz level over 2–4 s is −14.5 ± 0.05 dBFS; at track volume
  0.5 −16.005 ± 0.05 (post-fader).
- **T3** the two −6 dBFS tones on two tracks nested into one nest clip, its
  track limited at −6 dBTP: the stem ≤ −6 + 0.01 dBTP by both meters.
- **T4** the 440 Hz −12 dBFS-ish sine (`ap10c_sine10.wav`) compressed on one
  track and the music limited at −10 dBTP on another, `stems: tracks`,
  `peak_dbtp` 0, 24-bit: Σ stems − mix ≤ 2 LSB on every sample.
- **T5** the music compressed (threshold −30, ratio 4, makeup 6),
  `loudness_lufs` −16: the file's integrated loudness −16 ± 0.1 LUFS and its
  true peak ≤ −1 + 0.001 dBTP by both meters.
- **T6** `vp9_webm` of T2's compressed project within 0.2 LU of its WAV; the
  same project undynamic as `vp9_webm` more than 3 LU from that WAV.
- **P1** T1's limited project played 5 s at ×1 from 2 s (over the crossfade):
  `loudness_meter`'s true peak − the ceiling is recorded (the guide's figure)
  with `tracks_approximate` true; the limiter cleared and played again,
  `tracks_approximate` false.
- **U1** `set_track {compressor}` is one undo step and reads back whole;
  each refusal names itself (not an object, an unknown key, a range, inside a
  scope); `nest` leaves the nest's tracks none and the timeline's track its
  own; the instance's log holds no `Frame Job: ` line.
- **B1–B5** (the probe `audio_ap10c_probe.swift`, compiled AS `main.swift` over
  `app/Sources` on `swift_build.py`'s line; a probe that will not build is a
  scored failure): the stage at any buffer size, `ExportMixRead` single and
  sub-mixed and the measurement's read, a nest bus, the tap's ×E/÷E at 48 and
  44.1 kHz, the leads, the build's record, `mixIsSet` and the footer.

Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff every row asked
passed.
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

import numpy as np

import swift_build  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
MEDIA = HERE / "media"
OUT = HERE / "work" / "audio_ap10c"
RATE = 48000
SEC = 600_000
PROBE_ROWS = ["B1", "B2", "B3", "B4", "B5"]
MCP_ROWS = ["T1", "T2", "T3", "T4", "T5", "T6", "P1", "U1"]

# (name, killing row, [(file, old, new), ...]) — each over its own copy of app/Sources.
MUTANTS = [
    ("M1", "B2", [("ExportMixRead.swift", "        guard !owned.isEmpty else {",
                   "        guard owned.isEmpty, !owned.isEmpty else {")]),
    ("M2", "B3", [("ExportMixRead.swift", "                rest.insert(id)",
                   "                owned[built.trackDynamics.keys.min() ?? 0, default: []]"
                   ".insert(id)")]),
    ("M3", "B3", [("ExportMixRead.swift",
                   "            toDrop = Group.latency(stage, settings)",
                   "            toDrop = 0")]),
    ("M4", "B2", [("ExporterLoudness.swift", "        let subMixed = mixRead.isSubMixed",
                   "        let subMixed = mixRead.isSubMixed && false")]),
    ("M6", "B4", [("AudioTap.swift",
                   "                    vDSP_vmul(data, 1, e, 1, data, 1, vDSP_Length(length))",
                   "                    _ = data"),
                  ("AudioTap.swift",
                   "                        data[i] = e[i] >= Self.envelopeFloor ? data[i] / e[i] : 0",
                   "                        data[i] = data[i]")]),
    ("M7", "B5", [("CompositionBuilder+AudioPlacement.swift",
                   " + (usesTrackLimiter ? limiterLead : 0),", " + 0,"),
                  ("AudioTapSchedule.swift",
                   "        trackLead = dynamics?.settings.limiter == nil ? 0 : "
                   "CompositionBuilder.AudioShift.limiterLead",
                   "        trackLead = 0")]),
    ("M10", "B4", [("AudioTap.swift", "fromFrame: first + latency, rate: sampleRate)",
                    "fromFrame: first + leadFrames(track.trackLead), rate: sampleRate)")]),
    # The last drain handed back as one buffer of whatever is left (#414).
    ("M11", "B2", [("ExportMixRead.swift",
                    "                ? min(groups.map(\\.available).max() ?? 0, Self.blockFrames)",
                    "                ? groups.map(\\.available).max() ?? 0")]),
]

BY_HAND = [
    ("M5", "T6 on a mutated Debug build", "app/Sources/ExportWebMWriter.swift",
     "let read = ExportMixRead(built, origin: range.start)",
     "let read = ExportMixRead({ var b = built; b.trackDynamics = [:]; return b }(), "
     "origin: range.start)"),
    ("M8", "core/tests/track_dynamics.rs (inside_a_scope_…)", "core/src/scope.rs",
     "the guarded `Op::SetTrack { compressor, limiter, .. } if …` arm", "removed"),
    ("M9", "core/tests/track_dynamics.rs (nest_gives_…)", "core/src/edit_nest.rs",
     "compressor: None, limiter: None", "compressor: from.compressor, limiter: from.limiter"),
]

rows = []


def row(row_id, ok, detail):
    rows.append((row_id, bool(ok)))
    print(f"{row_id} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


# ---- the probe -------------------------------------------------------------------

def run_probe(sources, name):
    """({row: (passed, detail)}, problem) — None rows when it did not build."""
    out = OUT / name
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "audio_ap10c_probe.swift", entry)
    blank = out / "Blank.mp4"
    if not blank.exists():
        shutil.copyfile(ROOT / "app/Resources/Blank.mp4", blank)
    binary = out / "audio-ap10c-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [str(entry)], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc: " + " | ".join((errors or list(error.diagnostics) or [str(error)])[:6])
    scratch = out / "scratch"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    try:
        result = subprocess.run([str(binary), str(scratch)], capture_output=True, text=True,
                                timeout=600, cwd=str(out))
    except subprocess.TimeoutExpired:
        return {}, "the probe ran past 600 s and was killed"
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
            row(name, False, "the probe did not answer: " + problem)
        else:
            row(name, found[name][0], found[name][1])


def mutants(only=None):
    """Every probe mutant, or only the ones named (a fix pass's own)."""
    chosen = [m for m in MUTANTS if not only or m[0] in only]
    killed = 0
    sources = ROOT / "app/Sources"
    for name, target, edits in chosen:
        tree = OUT / f"mutant-{name}" / "Sources"
        shutil.rmtree(tree, ignore_errors=True)
        shutil.copytree(sources, tree)
        anchored = True
        for file, old, new in edits:
            path = tree / file
            text = path.read_text()
            if text.count(old) != 1:
                print(f"{name} FAIL — anchor not found once in {file}: {old.strip()[:60]}",
                      flush=True)
                anchored = False
                break
            path.write_text(text.replace(old, new))
        if not anchored:
            continue
        found, problem = run_probe(tree, f"mutant-{name}")
        if found is None:
            print(f"{name} FAIL — did not build: {problem}", flush=True)
            continue
        dead = found.get(target, (True, ""))[0] is False
        killed += dead
        failing = sorted(r for r, (ok, _) in found.items() if not ok)
        print(f"{name} {'killed' if dead else 'SURVIVED'} by {target} — failing rows: "
              f"{', '.join(failing) or 'none'}", flush=True)
    print(f"{killed}/{len(chosen)} probe mutants killed", flush=True)
    for name, killer, file, old, new in BY_HAND:
        print(f"{name} by hand — killed by {killer}: in {file}, {old} → {new}", flush=True)
    return bool(chosen) and killed == len(chosen)


# ---- fixtures and reading an export ------------------------------------------------

def run(command, timeout=300):
    subprocess.run(command, check=True, timeout=timeout, capture_output=True)


def tone(name, db, hz):
    path = MEDIA / name
    if not path.exists():
        a = 10 ** (db / 20)
        run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
             f"aevalsrc='{a}*sin(2*PI*{hz}*t)|{a}*sin(2*PI*{hz}*t)':s={RATE}:d=6",
             "-c:a", "pcm_s24le", str(path)])
    return str(path)


def fixtures():
    MEDIA.mkdir(parents=True, exist_ok=True)
    music = MEDIA / "ap10c_music.wav"
    if not music.exists():
        sines = "0.08*sin(2*PI*220*t)+0.08*sin(2*PI*330*t)+0.08*sin(2*PI*523.25*t)"
        shifted = ("0.08*sin(2*PI*220*t+1)+0.08*sin(2*PI*330*t+2)"
                   "+0.08*sin(2*PI*523.25*t+3)")
        run(["ffmpeg", "-v", "error", "-y", "-filter_complex",
             f"aevalsrc='{sines}|{shifted}':s={RATE}:d=6[a];"
             f"anoisesrc=color=pink:amplitude=0.06:seed=7:d=6:r={RATE},"
             "aformat=channel_layouts=stereo[b];[a][b]amix=inputs=2:normalize=0",
             "-c:a", "pcm_s24le", str(music)])
    return {
        "hot_a": tone("ap10c_hot_a.wav", -1, 440), "hot_b": tone("ap10c_hot_b.wav", -1, 660),
        "mid_a": tone("ap10c_mid_a.wav", -6, 440), "mid_b": tone("ap10c_mid_b.wav", -6, 660),
        "sine10": tone("ap10c_sine10.wav", -10, 440), "music": str(music),
    }


def pcm(path):
    """The file's samples as int64 (frames × 2), at its own depth."""
    codec = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
         "stream=codec_name", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True).stdout.strip()
    wide = "24" in codec
    fmt, acodec, dtype = ("s32le", "pcm_s32le", "<i4") if wide else ("s16le", "pcm_s16le", "<i2")
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-vn", "-f", fmt, "-acodec", acodec,
         "-ac", "2", "-"], check=True, timeout=300, capture_output=True).stdout
    data = np.frombuffer(raw, dtype=dtype).astype(np.int64)
    if wide:
        data = data >> 8
    return data.reshape(-1, 2)


def floats(path):
    """The file decoded to float64 (2 × frames) at 48 kHz."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-vn", "-f", "f32le", "-acodec", "pcm_f32le",
         "-ar", str(RATE), "-ac", "2", "-"], check=True, timeout=300, capture_output=True).stdout
    data = np.frombuffer(raw, dtype="<f4").astype(np.float64)
    return [data[0::2], data[1::2]]


def level_db(channels, hz=440, start=2.0, end=4.0):
    """The mean `hz` amplitude by quadrature over [start, end) s, louder channel, dBFS."""
    window = RATE // 40  # 25 ms: 11 cycles of 440 Hz
    best = 0.0
    for channel in channels:
        amplitudes = []
        for s in range(int(start * RATE), int(end * RATE) - window + 1, window):
            n = np.arange(s, s + window)
            x = channel[s:s + window]
            i = np.sum(x * np.sin(2 * np.pi * hz * n / RATE))
            q = np.sum(x * np.cos(2 * np.pi * hz * n / RATE))
            amplitudes.append(2 * np.hypot(i, q) / window)
        best = max(best, float(np.mean(amplitudes)))
    return 20 * np.log10(best) if best > 0 else -np.inf


def loudness(channels):
    """BS.1770-4 integrated loudness, `phase5_proof`'s implementation."""
    p5 = phase5()
    return p5.integrated([list(c) for c in channels])


def phase5():
    saved = sys.argv[1:]
    sys.argv[1:] = [SOCKET]  # phase5_proof reads its socket at import
    try:
        import phase5_proof
    finally:
        sys.argv[1:] = saved
    return phase5_proof


def true_peaks(path):
    sys.path.insert(0, str(HERE))
    from limiter_probe import true_peaks as peaks
    return peaks(path)


# ---- one project -------------------------------------------------------------------

class Project:
    """A new project with `count` tracks and `clips` — (track index, media path,
    start in seconds)."""

    def __init__(self, mcp, label, count, clips):
        self.mcp = mcp
        self.label = label
        self.path = str(OUT / f"{label}-{os.getpid()}.framejob")
        mcp.call("new_project", path=self.path)
        while len(self.get()["tracks"]) < count:
            self.call("add_track")
        self.tracks = [t["id"] for t in self.get()["tracks"]][:count]
        media = {}
        self.clips = []
        for index, path, start in clips:
            if path not in media:
                media[path] = self.call("import_media", path=path)["media"]
            self.clips.append(self.call("add_clip", track=self.tracks[index], media=media[path],
                                        at=round(start * SEC))["new_clips"][0])

    def call(self, tool, **kwargs):
        return self.mcp.call(tool, project=self.path, **kwargs)

    def get(self):
        return self.call("get_project")["project"]

    def track(self, track_id, nests=False):
        project = self.get()
        found = [t for t in project["tracks"] if t["id"] == track_id]
        if nests:
            found += [t for n in project.get("nests", []) for t in n["tracks"]
                      if t["id"] == track_id]
        return found[0]

    def folder(self, name):
        folder = OUT / f"{self.label}-{name}"
        shutil.rmtree(folder, ignore_errors=True)
        folder.mkdir(parents=True)
        return folder

    def export(self, folder, preset="audio_wav", file="Mix.wav", **extra):
        arguments = {"project": self.path, "preset": preset, "path": str(folder / file)}
        arguments.update(extra)
        return self.mcp.export_with(arguments)

    def close(self):
        self.mcp.call("close_project", project=self.path, discard=True)


LIMIT6 = {"ceiling_db": -6.0}


def crossfaded(mcp, label, media):
    """T1's project: the hot pair crossfading on one track."""
    project = Project(mcp, label, 1, [(0, media["hot_a"], 0)])
    project.call("trim_end", clip=project.clips[0], to=4 * SEC)
    into = project.call("add_clip", track=project.tracks[0],
                        media=project.call("import_media", path=media["hot_b"])["media"],
                        at=4 * SEC)["new_clips"][0]
    project.call("add_transition", clip=into, duration=SEC, align="after")
    return project


# ---- the rows ----------------------------------------------------------------------

def t1(mcp, media):
    project = crossfaded(mcp, "t1", media)
    try:
        project.call("set_track", track=project.tracks[0], limiter=LIMIT6)
        limited = project.export(project.folder("limited"), audio_bits=24, stems="tracks",
                                 peak_dbtp=0)
        project.call("set_track", track=project.tracks[0], limiter=None)
        control = project.export(project.folder("control"), audio_bits=24, stems="tracks",
                                 peak_dbtp=0)
        stem = true_peaks(limited["stems"][0]["path"])
        open_stem = true_peaks(control["stems"][0]["path"])
        row("T1", max(stem) <= -6 + 0.01 and min(open_stem) > -5.5,
            f"limited stem (Kaiser, Annex 2) {fmt(stem)} dBTP (want ≤ −5.99); without the "
            f"limiter {fmt(open_stem)} (want > −5.5)")
    finally:
        project.close()


def t2_project(mcp, label, media, compressed=True, volume=None):
    project = Project(mcp, label, 1, [(0, media["sine10"], 0)])
    if compressed:
        project.call("set_track", track=project.tracks[0],
                     compressor={"threshold_db": -20.0, "ratio": 4.0, "makeup_db": 3.0})
    if volume is not None:
        project.call("set_track", track=project.tracks[0], volume=volume)
    return project


def t2(mcp, media):
    got = []
    for label, volume, want in (("t2", None, -14.5), ("t2v", 0.5, -16.005)):
        project = t2_project(mcp, label, media, volume=volume)
        try:
            result = project.export(project.folder("wav"), audio_bits=24)
            got.append((volume, level_db(floats(result["path"])), want))
        finally:
            project.close()
    ok = all(abs(level - want) <= 0.05 for _, level, want in got)
    row("T2", ok, "; ".join(f"track volume {v or 1}: {level:.4f} dBFS (want {want} ±0.05)"
                            for v, level, want in got))


def t3(mcp, media):
    project = Project(mcp, "t3", 2, [(0, media["mid_a"], 0), (1, media["mid_b"], 0)])
    try:
        project.call("nest", clips=project.clips)
        bus = [c for c in project.get()["clips"] if c["source"].get("kind") == "nest"][0]["track"]
        project.call("set_track", track=bus, limiter=LIMIT6)
        result = project.export(project.folder("stems"), audio_bits=24, stems="tracks",
                                peak_dbtp=0)
        stems = result.get("stems", [])
        peaks = true_peaks(stems[0]["path"]) if len(stems) == 1 else (None, None)
        row("T3", len(stems) == 1 and max(peaks) <= -6 + 0.01,
            f"{len(stems)} stem(s) {[s['tracks'] for s in stems]}; the bus's stem {fmt(peaks)} "
            f"dBTP (want ≤ −5.99)")
    finally:
        project.close()


def t4(mcp, media):
    project = Project(mcp, "t4", 2, [(0, media["sine10"], 0), (1, media["music"], 1)])
    try:
        project.call("set_track", track=project.tracks[0],
                     compressor={"threshold_db": -20.0, "ratio": 4.0})
        project.call("set_track", track=project.tracks[1], limiter={"ceiling_db": -10.0})
        result = project.export(project.folder("stems"), audio_bits=24, stems="tracks",
                                peak_dbtp=0)
        mix = pcm(result["path"])
        total = np.zeros_like(mix)
        same = True
        for stem in result.get("stems", []):
            samples = pcm(stem["path"])
            same = same and samples.shape == mix.shape
            if samples.shape == mix.shape:
                total += samples
        worst = int(np.max(np.abs(total - mix))) if same and len(mix) else None
        row("T4", len(result.get("stems", [])) == 2 and same and worst is not None and worst <= 2,
            f"{len(result.get('stems', []))} stems; Σ stems − mix worst {worst} LSB at 24 bits "
            f"(want ≤ 2), lengths equal {same}")
    finally:
        project.close()


def t5(mcp, media):
    project = Project(mcp, "t5", 1, [(0, media["music"], 0)])
    try:
        project.call("set_track", track=project.tracks[0],
                     compressor={"threshold_db": -30.0, "ratio": 4.0, "makeup_db": 6.0})
        result = project.export(project.folder("loud"), audio_bits=24, loudness_lufs=-16)
        lufs = loudness(floats(result["path"]))
        peaks = true_peaks(result["path"])
        row("T5", lufs is not None and abs(lufs + 16) <= 0.1 and max(peaks) <= -1 + 0.001,
            f"integrated {lufs:.3f} LUFS (want −16 ±0.1); true peak {fmt(peaks)} dBTP (want "
            f"≤ −0.999); the export's own {result.get('loudness')}")
    finally:
        project.close()


def t6(mcp, media):
    loud = {}
    for label, compressed, preset, file in (("t6wav", True, "audio_wav", "Mix.wav"),
                                            ("t6webm", True, "vp9_webm", "Mix.webm"),
                                            ("t6plain", False, "vp9_webm", "Mix.webm")):
        project = t2_project(mcp, label, media, compressed=compressed)
        try:
            result = project.export(project.folder("out"), preset=preset, file=file)
            loud[label] = loudness(floats(result["path"]))
        finally:
            project.close()
    near = abs(loud["t6webm"] - loud["t6wav"])
    far = abs(loud["t6plain"] - loud["t6wav"])
    row("T6", near <= 0.2 and far > 3,
        f"WAV {loud['t6wav']:.3f}, vp9_webm {loud['t6webm']:.3f} LUFS (|Δ| {near:.3f}, want ≤ "
        f"0.2); undynamic vp9_webm {loud['t6plain']:.3f} (|Δ| {far:.3f}, want > 3)")


def play(project):
    from mcp import ToolError
    project.call("set_playhead", t=2 * SEC)
    project.call("loudness_meter", reset=True)
    deadline = time.monotonic() + 60
    while True:
        try:
            project.call("play_preview", seconds=5)
            return project.call("loudness_meter")
        except ToolError as error:
            if "nothing to play" not in str(error) or time.monotonic() > deadline:
                raise
            time.sleep(0.5)


def p1(mcp, media):
    project = crossfaded(mcp, "p1", media)
    try:
        project.call("set_track", track=project.tracks[0], limiter=LIMIT6)
        limited = play(project)
        project.call("set_track", track=project.tracks[0], limiter=None)
        cleared = play(project)
        peak = limited.get("true_peak_dbtp")
        over = peak + 6 if isinstance(peak, (int, float)) else None
        row("P1", over is not None and limited.get("tracks_approximate") is True
            and cleared.get("tracks_approximate") is False,
            f"limited at −6 dBTP: the meter's true peak {peak} dBTP, {over:+.3f} dB over the "
            f"ceiling (recorded), tracks_approximate {limited.get('tracks_approximate')}; "
            f"cleared: tracks_approximate {cleared.get('tracks_approximate')} (want true, then "
            f"false)" if over is not None else f"no true peak: {limited}")
    finally:
        project.close()


def u1(mcp, media, socket):
    from mcp import ToolError
    project = Project(mcp, "u1", 1, [(0, media["sine10"], 0)])
    details, good = [], True
    try:
        track = project.tracks[0]
        fresh = project.track(track)
        project.call("set_track", track=track, compressor={"threshold_db": -20.0, "ratio": 4.0})
        edited = project.track(track).get("compressor")
        project.call("undo")
        undone = project.track(track)
        whole = edited == {"threshold_db": -20.0, "ratio": 4.0, "attack": 6000,
                           "release": 120000, "makeup_db": 0.0}
        good = good and whole and undone == fresh and "compressor" not in fresh
        details.append(f"read back {edited} (whole {whole}); one undo back to fresh "
                       f"{undone == fresh}")

        def refused(arguments, sentence):
            try:
                project.mcp.call_with("set_track", {"project": project.path, **arguments})
                return False
            except ToolError as error:
                return sentence in str(error)
        checks = [
            refused({"track": track, "compressor": 5},
                    "compressor must be a json object or null, not 5"),
            refused({"track": track, "compressor": {"knee": 6}},
                    'unknown key "compressor.knee" in set_track'),
            refused({"track": track, "compressor": {"ratio": 30}},
                    "compressor.ratio must be between 1 and 20, not 30"),
            refused({"track": track, "limiter": {"release": "slow"}},
                    'bad value at "limiter.release" in set_track: '),
        ]
        project.call("set_track", track=track, limiter=LIMIT6)
        project.call("nest", clips=project.clips)
        state = project.get()
        nest = state["nests"][-1]
        inner = nest["tracks"][0]["id"]
        checks.append(refused({"track": inner, "scope": nest["id"], "limiter": None},
                              f"a track's compressor or limiter has no meaning inside nest "
                              f"{nest['id']}"))
        none_inside = all("compressor" not in t and "limiter" not in t for t in nest["tracks"])
        kept = project.track(track).get("limiter") == {"ceiling_db": -6.0, "release": 60000}
        good = good and all(checks) and none_inside and kept
        details.append(f"refusals by name {checks}; nest leaves none inside {none_inside}, "
                       f"the timeline's track keeps its limiter {kept}")
        log = Path(socket).parent / "framejob.log"
        complaints = [line for line in log.read_text(errors="replace").splitlines()
                      if "Frame Job: " in line] if log.exists() else ["no log"]
        good = good and not complaints
        details.append(f"log {len(complaints)} complaint line(s) {complaints[:2]}")
        row("U1", good, "; ".join(details))
    finally:
        project.close()


def fmt(pair):
    return "(" + ", ".join("None" if v is None else f"{v:.4f}" for v in pair) + ")"


SOCKET = ""


def main():
    global SOCKET
    parser = argparse.ArgumentParser()
    parser.add_argument("socket", nargs="?")
    parser.add_argument("--probe", action="store_true")
    parser.add_argument("--mutants", action="store_true")
    parser.add_argument("--only", default="")
    args = parser.parse_args()
    if args.mutants:
        OUT.mkdir(parents=True, exist_ok=True)
        return 0 if mutants(set(args.only.split(",")) if args.only else None) else 1
    if args.probe:
        shutil.rmtree(OUT, ignore_errors=True)
        probe_rows()
    elif args.socket:
        from mcp import MCP
        SOCKET = args.socket
        only = set(args.only.split(",")) if args.only else set(PROBE_ROWS + MCP_ROWS)
        shutil.rmtree(OUT, ignore_errors=True)
        OUT.mkdir(parents=True)
        if only & set(PROBE_ROWS):
            probe_rows()
        media = fixtures()
        mcp = MCP(SOCKET)
        steps = {"T1": lambda: t1(mcp, media), "T2": lambda: t2(mcp, media),
                 "T3": lambda: t3(mcp, media), "T4": lambda: t4(mcp, media),
                 "T5": lambda: t5(mcp, media), "T6": lambda: t6(mcp, media),
                 "P1": lambda: p1(mcp, media), "U1": lambda: u1(mcp, media, SOCKET)}
        for name in MCP_ROWS:
            if name in only:
                try:
                    steps[name]()
                except Exception as error:  # a row that raised is a failed row
                    row(name, False, f"raised {type(error).__name__}: {error}")
    else:
        print(__doc__.split("\n\n")[1])
        return 2
    passed = sum(1 for _, ok in rows if ok)
    print(f"{passed}/{len(rows)}", flush=True)
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
