"""Road map "audio" AP10 part 2a — an audio export's stems (spec §11 AU-107..AU-109),
measured on exports over MCP, and the probe behind it.

    python3 tools/proof/audio_ap10b_proof.py <dir>/agent.sock [--only S1,S6,...]
    python3 tools/proof/audio_ap10b_proof.py --probe

The caller owns the instance at that socket; nothing is launched or killed.
Needs `ffmpeg`, `ffprobe` and numpy. `--probe` runs B1–B2 alone, with no
instance. Every project is a new one, closed with `close_project` (discarded).
Output is under `tools/proof/work/audio_ap10b/`.

**Fixtures**, made on the first run into `tools/proof/media/` (kept):
`ap10b_tone.wav` — 6 s of a 440 Hz sine at −12.5 dBFS, 48 kHz stereo (×4 is
−0.46 dBFS: over −1 dBTP, under full scale); `ap10b_music.wav` — 6 s, 48 kHz
stereo, three sines (220, 330, 523.25 Hz) plus pink noise, near −20 dBFS RMS,
24-bit; `ap10b_long.m4a` — 600 s of a 440 Hz sine at −20 dBFS, AAC.

Audio is decoded to PCM integers at the file's own depth. Rows:
- **S1** `tracks`, 24-bit WAV, no target: "Tone" holds the tone at 0 and
  "Music" the music at 5 s (overlapping 1 s): two stems at AU-108's names
  (`Mix - Tone.wav`, `Mix - Music.wav`) and nothing else beside the mix; Σ stems
  − mix ≤ 2 LSB on every sample; the result's `stems` names, tracks and paths
  are those files.
- **S2** `names`: tracks "Music", "music" and "" → two stems ("Music" holding
  the first two, "Track 3"), Σ = mix as S1.
- **S3** S1's project with `loudness_lufs -16`: every stem's samples identical
  to S1's; the mix's differ.
- **S4** a muted track, then (unmuted) a soloed one: no stem, and no file, for
  a silenced track.
- **S5** `samples/Rode-usb-mic.m4a` on one track beside the music: each stem's
  samples identical to the 24-bit export of the project with only that track
  soloed (skipped by name when the sample is absent).
- **S6** the tone at clip volume ×4: its stem's true peak above −1 dBTP by
  `limiter_probe.py`'s two meters; the mix's ≤ −1 + 0.001 by both.
- **S7** refusals by name: `stems` on `h264`, `stems: "both"`, every track muted.
- **S8** source collision: track "Dialogue" holds media at `<out>/Mix -
  Dialogue.wav` (a copy of the music); exporting `<out>/Mix.wav` with `stems:
  "tracks"` fails with SourceCollision's sentence naming it, the media file is
  byte-identical, and no `Mix.wav` or other stem file exists.
- **C1** the long tone on three tracks, three stems: `cancel_export` only once
  `export_status`'s progress is past the start of the LAST stem (the write's
  share is the second half of the bar, so past 0.5 + 0.5 × 3/4), having first
  seen stems 1 and 2 on disk; then `cancelled`, and no mix or stem file
  remains. Fails, never skips, when the job finishes first or the first poll in
  that window finds stems 1–2 absent.
- **B1–B2** (the probe `audio_ap10b_probe.swift`, compiled AS `main.swift`
  over `app/Sources` on `swift_build.py`'s line; a probe that will not build is
  a scored failure): `ExportAudioMaster(limits: false)` writes `round(input)`
  frame for frame with no tail; `url(for:mix:)`, `summary` and `collision`
  (exact, case-only, a symlink, none).

The queue row's success line is not read here: `export_status`'s `done` answer
carries no line and `snapshot_ui` cannot capture the Export Queue window. Its
wording is `summary`'s (B2), appended at both success lines.

Rows print `<ID> ok|FAIL|skip — <detail>`, then `n/m`; exit 0 iff every row
asked passed (a skip is not a failure).
"""

import argparse
import hashlib
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
OUT = HERE / "work" / "audio_ap10b"
RODE = ROOT / "samples" / "Rode-usb-mic.m4a"
RATE = 48000
SEC = 600_000
PROBE_ROWS = ["B1", "B2"]
MCP_ROWS = ["S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "C1"]

rows = []


def row(row_id, ok, detail, skip=False):
    word = "skip" if skip else ("ok" if ok else "FAIL")
    rows.append((row_id, bool(ok) or skip))
    print(f"{row_id} {word} — {detail}", flush=True)


# ---- the probe -------------------------------------------------------------------

def probe_rows(sources=ROOT / "app/Sources"):
    out = OUT / "probe"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "audio_ap10b_probe.swift", entry)
    binary = out / "audio-ap10b-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    found, problem = {}, ""
    try:
        if len(swift) < 100:
            raise swift_build.SwiftBuildFailed("app source set incomplete", [])
        swift_build.build(sources=swift + [str(entry)], output=binary)
        scratch = out / "scratch"
        shutil.rmtree(scratch, ignore_errors=True)
        scratch.mkdir(parents=True)
        result = subprocess.run([str(binary), str(scratch)], capture_output=True, text=True,
                                timeout=600, cwd=str(out))
        problem = result.stderr.strip()[-600:]
        for line in result.stdout.splitlines():
            parts = line.split(" ", 2)
            if len(parts) >= 2 and parts[0] in ("ok", "FAIL"):
                detail = parts[2][2:] if len(parts) > 2 and parts[2].startswith("— ") else ""
                found[parts[1]] = (parts[0] == "ok", detail)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        found = None
        problem = "swiftc: " + " | ".join((errors or list(error.diagnostics) or [str(error)])[:6])
    except subprocess.TimeoutExpired:
        problem = "the probe ran past 600 s and was killed"
    for name in PROBE_ROWS:
        if found is None:
            row(name, False, "the probe does not build: " + problem)
        elif name not in found:
            row(name, False, "the probe did not answer: " + problem)
        else:
            row(name, found[name][0], found[name][1])


# ---- fixtures and reading an export ------------------------------------------------

def run(command, timeout=300):
    subprocess.run(command, check=True, timeout=timeout, capture_output=True)


def fixtures():
    MEDIA.mkdir(parents=True, exist_ok=True)
    tone = MEDIA / "ap10b_tone.wav"
    if not tone.exists():
        a = 10 ** (-12.5 / 20)
        run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
             f"aevalsrc='{a}*sin(2*PI*440*t)|{a}*sin(2*PI*440*t)':s={RATE}:d=6",
             "-c:a", "pcm_s24le", str(tone)])
    music = MEDIA / "ap10b_music.wav"
    if not music.exists():
        sines = "0.08*sin(2*PI*220*t)+0.08*sin(2*PI*330*t)+0.08*sin(2*PI*523.25*t)"
        shifted = ("0.08*sin(2*PI*220*t+1)+0.08*sin(2*PI*330*t+2)"
                   "+0.08*sin(2*PI*523.25*t+3)")
        run(["ffmpeg", "-v", "error", "-y", "-filter_complex",
             f"aevalsrc='{sines}|{shifted}':s={RATE}:d=6[a];"
             f"anoisesrc=color=pink:amplitude=0.06:seed=7:d=6:r={RATE},"
             "aformat=channel_layouts=stereo[b];[a][b]amix=inputs=2:normalize=0",
             "-c:a", "pcm_s24le", str(music)])
    long = MEDIA / "ap10b_long.m4a"
    if not long.exists():
        a = 10 ** (-20 / 20)
        run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
             f"aevalsrc='{a}*sin(2*PI*440*t)|{a}*sin(2*PI*440*t)':s={RATE}:d=600",
             "-c:a", "aac", "-b:a", "192k", str(long)])
    return str(tone), str(music), str(long)


def pcm(path):
    """The file's samples as int64 (frames × 2), at its own depth: 24-bit files
    as their 24-bit integers, every other as 16-bit."""
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


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


# ---- one project -------------------------------------------------------------------

class Project:
    """A new project with `names` tracks (back to front) and `clips` — (track
    index, media path, start in seconds, clip volume or None)."""

    def __init__(self, mcp, label, names, clips):
        self.mcp = mcp
        self.label = label
        self.path = str(OUT / f"{label}-{os.getpid()}.framejob")
        mcp.call("new_project", path=self.path)
        while len(self.get()["tracks"]) < len(names):
            self.call("add_track")
        self.tracks = [t["id"] for t in self.get()["tracks"]][:len(names)]
        for track, name in zip(self.tracks, names):
            self.mcp.call_with("set_track", {"project": self.path, "track": track, "name": name})
        media = {}
        self.clips = []
        for index, path, start, volume in clips:
            if path not in media:
                media[path] = self.call("import_media", path=path)["media"]
            clip = self.call("add_clip", track=self.tracks[index], media=media[path],
                             at=round(start * SEC))["new_clips"][0]
            if volume is not None:
                self.call("set_audio", clips=[clip], patch={"volume": volume})
            self.clips.append(clip)

    def call(self, tool, **kwargs):
        return self.mcp.call(tool, project=self.path, **kwargs)

    def get(self):
        return self.call("get_project")["project"]

    def folder(self, name):
        folder = OUT / f"{self.label}-{name}"
        shutil.rmtree(folder, ignore_errors=True)
        folder.mkdir(parents=True)
        return folder

    def export(self, folder, preset="audio_wav", **extra):
        arguments = {"project": self.path, "preset": preset, "path": str(folder / "Mix.wav")}
        arguments.update(extra)
        return self.mcp.export_with(arguments)

    def close(self):
        self.mcp.call("close_project", project=self.path, discard=True)


def stems_of(result):
    return [(s["name"], s["tracks"], s["path"]) for s in result.get("stems", [])]


def files_in(folder):
    return sorted(p.name for p in Path(folder).iterdir())


def sum_check(result):
    """(worst |Σ stems − mix| in LSB, same lengths) for a finished export."""
    mix = pcm(result["path"])
    total = np.zeros_like(mix)
    same = True
    for _, _, path in stems_of(result):
        stem = pcm(path)
        same = same and stem.shape == mix.shape
        if stem.shape == mix.shape:
            total += stem
    worst = int(np.max(np.abs(total - mix))) if same and len(mix) else None
    return worst, same


# ---- the rows ----------------------------------------------------------------------

def s1_s3(mcp, tone, music, only):
    project = Project(mcp, "s1", ["Tone", "Music"], [(0, tone, 0, None), (1, music, 5, None)])
    try:
        folder = project.folder("plain")
        result = project.export(folder, audio_bits=24, stems="tracks")
        want = [("Tone", [project.tracks[0]], str(folder / "Mix - Tone.wav")),
                ("Music", [project.tracks[1]], str(folder / "Mix - Music.wav"))]
        got = stems_of(result)
        worst, same = sum_check(result)
        files = files_in(folder)
        if "S1" in only:
            row("S1", got == want and files == ["Mix - Music.wav", "Mix - Tone.wav", "Mix.wav"]
                and same and worst is not None and worst <= 2,
                f"result stems {got} (want {want}); files {files}; Σ stems − mix worst "
                f"{worst} LSB at 24 bits (want ≤ 2), lengths equal {same}")
        if "S3" not in only:
            return
        loud_folder = project.folder("loud")
        loud = project.export(loud_folder, audio_bits=24, stems="tracks", loudness_lufs=-16)
        pairs = list(zip(stems_of(result), stems_of(loud)))
        identical = [np.array_equal(pcm(a[2]), pcm(b[2])) for a, b in pairs]
        mix_differs = not np.array_equal(pcm(result["path"]), pcm(loud["path"]))
        gain = loud.get("loudness", {}).get("gain_db")
        row("S3", len(pairs) == 2 and all(identical) and mix_differs,
            f"loudness −16 (gain {gain} dB): stems identical to S1's {identical}; the mix "
            f"differs {mix_differs}")
    finally:
        project.close()


def s2(mcp, tone, music):
    project = Project(mcp, "s2", ["Music", "music", ""],
                      [(0, music, 0, None), (1, tone, 3, None), (2, music, 6, None)])
    try:
        folder = project.folder("names")
        result = project.export(folder, audio_bits=24, stems="names")
        t = project.tracks
        want = [("Music", [t[0], t[1]], str(folder / "Mix - Music.wav")),
                ("Track 3", [t[2]], str(folder / "Mix - Track 3.wav"))]
        got = stems_of(result)
        worst, same = sum_check(result)
        row("S2", got == want and same and worst is not None and worst <= 2
            and files_in(folder) == ["Mix - Music.wav", "Mix - Track 3.wav", "Mix.wav"],
            f"result stems {got} (want {want}); files {files_in(folder)}; Σ − mix worst "
            f"{worst} LSB (want ≤ 2)")
    finally:
        project.close()


def s4(mcp, tone, music):
    project = Project(mcp, "s4", ["A", "B", "C"],
                      [(0, tone, 0, None), (1, music, 0, None), (2, tone, 0, None)])
    try:
        t = project.tracks
        project.call("set_track", track=t[1], muted=True)
        muted = project.folder("muted")
        got_muted = [s[0] for s in stems_of(project.export(muted, stems="tracks"))]
        project.call("set_track", track=t[1], muted=False)
        project.call("set_track", track=t[2], solo=True)
        soloed = project.folder("soloed")
        got_solo = [s[0] for s in stems_of(project.export(soloed, stems="tracks"))]
        row("S4", got_muted == ["A", "C"] and files_in(muted) == ["Mix - A.wav", "Mix - C.wav",
                                                                  "Mix.wav"]
            and got_solo == ["C"] and files_in(soloed) == ["Mix - C.wav", "Mix.wav"],
            f"B muted: stems {got_muted}, files {files_in(muted)} (want A, C); C soloed: stems "
            f"{got_solo}, files {files_in(soloed)} (want C)")
    finally:
        project.close()


def s5(mcp, music):
    if not RODE.exists():
        row("S5", True, f"{RODE} is absent", skip=True)
        return
    project = Project(mcp, "s5", ["Voice", "Music"], [(0, str(RODE), 0, None),
                                                      (1, music, 2, None)])
    try:
        folder = project.folder("stems")
        result = project.export(folder, audio_bits=24, stems="tracks")
        details, good = [], len(stems_of(result)) == 2
        for index, (name, _, path) in enumerate(stems_of(result)):
            project.call("set_track", track=project.tracks[index], solo=True)
            alone = project.folder(f"solo{index}")
            solo = project.export(alone, audio_bits=24)
            project.call("set_track", track=project.tracks[index], solo=False)
            a, b = pcm(path), pcm(solo["path"])
            same = a.shape == b.shape and np.array_equal(a, b)
            worst = int(np.max(np.abs(a - b))) if a.shape == b.shape else None
            details.append(f"{name}: identical {same} (worst {worst} LSB, frames "
                           f"{len(a)}/{len(b)}, the solo's limited_db "
                           f"{solo.get('loudness', {}).get('limited_db')})")
            good = good and same
        row("S5", good, "; ".join(details))
    finally:
        project.close()


def s6(mcp, tone):
    sys.path.insert(0, str(HERE))
    from limiter_probe import true_peaks
    project = Project(mcp, "s6", ["Hot"], [(0, tone, 0, 4)])
    try:
        folder = project.folder("hot")
        result = project.export(folder, audio_bits=24, stems="tracks")
        stems = stems_of(result)
        stem_peaks = true_peaks(stems[0][2]) if stems else (None, None)
        mix_peaks = true_peaks(result["path"])
        row("S6", len(stems) == 1 and min(stem_peaks) > -1 and max(mix_peaks) <= -1 + 0.001,
            f"stem true peak (Kaiser, Annex 2) {stem_peaks} dBTP (want > −1); mix "
            f"{mix_peaks} dBTP (want ≤ −0.999)")
    finally:
        project.close()


def s7(mcp, tone):
    from mcp import ToolError
    project = Project(mcp, "s7", ["A"], [(0, tone, 0, None)])
    folder = project.folder("refused")
    found = []

    def refusal(**extra):
        try:
            project.export(folder, **extra)
            return None
        except ToolError as error:
            return str(error)
    try:
        cases = [
            (dict(preset="h264", stems="tracks"),
             "h264 has no stems; stems applies to audio_m4a, audio_wav and audio_aiff"),
            (dict(stems="both"), 'export stems must be "tracks" or "names", not "both"'),
        ]
        for extra, sentence in cases:
            said = refusal(**extra)
            found.append((said is not None and sentence in said, said))
        project.call("set_track", track=project.tracks[0], muted=True)
        said = refusal(stems="tracks")
        found.append((said is not None
                      and "stems: no track is heard, so there is no stem to write" in said, said))
        row("S7", all(ok for ok, _ in found) and files_in(folder) == [],
            f"{[said for _, said in found]}; files {files_in(folder)}")
    finally:
        project.close()


def s8(mcp, music):
    from mcp import ToolError
    folder = OUT / "s8-out"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    media = folder / "Mix - Dialogue.wav"
    shutil.copyfile(music, media)
    before = digest(media)
    project = Project(mcp, "s8", ["Dialogue"], [(0, str(media), 0, None)])
    try:
        try:
            project.export(folder, stems="tracks")
            reason = None
        except ToolError as error:
            reason = str(error)
        sentence = ("The stem “Mix - Dialogue.wav” would replace media this project uses; "
                    "export under another name.")
        files = files_in(folder)
        row("S8", reason is not None and sentence in reason and digest(media) == before
            and files == ["Mix - Dialogue.wav"],
            f"failure {reason!r}; the media unchanged {digest(media) == before}; files {files} "
            f"(want the media alone)")
    finally:
        project.close()


def c1(mcp, long):
    project = Project(mcp, "c1", ["One", "Two", "Three"],
                      [(0, long, 0, None), (1, long, 0, None), (2, long, 0, None)])
    try:
        folder = project.folder("cancel")
        answer = mcp.call("export", project=project.path, preset="audio_wav",
                          path=str(folder / "Mix.wav"), stems="tracks")
        job = answer["export_id"]
        stems = [folder / f"Mix - {n}.wav" for n in ("One", "Two", "Three")]
        threshold = 0.5 + 0.5 * 3 / 4
        seen, status, progress = None, None, 0.0
        deadline = time.monotonic() + 900
        while time.monotonic() < deadline:
            state = mcp.call("export_status", export_id=job)
            status = state["status"]
            if status != "running" and status not in ("queued",):
                break
            progress = state.get("progress", 0.0) or 0.0
            if status == "running" and progress > threshold:
                seen = [s.exists() for s in stems[:2]]
                break
            time.sleep(0.02)
        if seen is None:
            mcp.call("cancel_export", export_id=job)
            row("C1", False, f"never inside the last stem: status {status}, progress "
                f"{progress} (want > {threshold} while running)")
            return
        mcp.call("cancel_export", export_id=job)
        while time.monotonic() < deadline:
            status = mcp.call("export_status", export_id=job)["status"]
            if status in ("done", "failed", "cancelled"):
                break
            time.sleep(0.05)
        left = files_in(folder)
        row("C1", seen == [True, True] and status == "cancelled" and left == [],
            f"at progress {progress:.4f} (> {threshold}) stems 1–2 on disk {seen}; then "
            f"{status}; files left {left} (want none)")
    finally:
        project.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("socket", nargs="?")
    parser.add_argument("--probe", action="store_true")
    parser.add_argument("--only", help="comma-separated rows, e.g. S1,S6,B2")
    args = parser.parse_args()
    if args.probe:
        shutil.rmtree(OUT / "probe", ignore_errors=True)
        probe_rows()
    elif args.socket:
        only = set(args.only.split(",")) if args.only else set(PROBE_ROWS + MCP_ROWS)
        OUT.mkdir(parents=True, exist_ok=True)
        if only & set(PROBE_ROWS):
            probe_rows()
        from mcp import MCP
        tone, music, long = fixtures()
        mcp = MCP(args.socket)
        if only & {"S1", "S3"}:
            s1_s3(mcp, tone, music, only)
        steps = [("S2", lambda: s2(mcp, tone, music)), ("S4", lambda: s4(mcp, tone, music)),
                 ("S5", lambda: s5(mcp, music)), ("S6", lambda: s6(mcp, tone)),
                 ("S7", lambda: s7(mcp, tone)), ("S8", lambda: s8(mcp, music)),
                 ("C1", lambda: c1(mcp, long))]
        for name, step in steps:
            if name in only:
                step()
    else:
        print(__doc__.split("\n\n")[1])
        return 2
    passed = sum(1 for _, ok in rows if ok)
    print(f"{passed}/{len(rows)}", flush=True)
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
