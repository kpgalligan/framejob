"""Road map "audio" AP10 part 1 — a track's volume and pan (spec §11
AU-102..AU-106), measured on exports over MCP, and the probe behind it.

    python3 tools/proof/audio_ap10_proof.py <dir>/agent.sock
    python3 tools/proof/audio_ap10_proof.py --probe
    python3 tools/proof/audio_ap10_proof.py --mutants

The caller owns the instance at that socket; nothing is launched or killed.
Needs `ffmpeg`. `--probe` runs B1–B4 alone, with no instance; `--mutants` runs
M6 and M7, each over its own copy of `app/Sources`, killed when its named
probe row fails (M1–M5 and M8–M10 are the core's, killed by
`core/tests/track_mix.rs`, run by hand).

**Fixtures**, made on the first run into `tools/proof/media/` (kept):
`ap10_tone.wav` — 6 s of a 440 Hz sine at −12 dBFS, 48 kHz stereo, both
channels alike; `ap10_tone_mono.wav` — the same, mono. Each project is a new
one with one clip of a fixture at 0, closed with `close_project` (discarded).

Levels are read by quadrature at 440 Hz over windows of exactly 1,200 samples
(11 cycles, 25 ms) across 1–3 s, per channel, and stated in dB of the same
fixture's UNITY export, read the same way. `audio_wav` is 16-bit with no
dither, so a channel whose gain is 0 is exactly 0.

Rows:
- **F1**: track volume 0.5 gives −6.02 ± 0.02 dB in each channel.
- **F2**: clip volume 2 × track volume 0.25 gives −6.02 ± 0.02 dB.
- **F3**: the clip nested, its inner track at 0.5 (`set_track` with `scope`)
  and the nest clip's track at 0.5, gives −12.04 ± 0.02 dB.
- **F4**: a muted track at volume 4 is silent (peak ≤ −120 dBFS).
- **F5**: nesting the clip of a track at volume 0.5, pan −0.5 leaves its export
  unchanged (each channel ± 0.02 dB), and the nest's track reads volume 1, pan
  0 (no keys).
- **P1**: track pan −1 gives L +3.01 dB and R silent; pan 0.5 matches the
  law (`AudioPanLaw`: L √2·cos(3π/8), R √2·sin(3π/8)) ± 0.02 dB per channel.
- **P2**: inner −0.5 × outer +0.5 through a nest gives the product of the two
  pairs ± 0.02 dB.
- **P3**: an inner pan −1 inside a nest whose clip is mono leaves L = R
  (± 0.02 dB of each other).
- **P4**: a mono source with track pan −1 is unchanged (± 0.02 dB per channel).
- **P5**: a clip pan −0.5 and a track pan −0.5 multiply (± 0.02 dB).
- **U1**: one `set_track {volume, pan}` is one undo step: `get_project` reads
  them back, one `undo` returns the track to no keys, which a default track
  writes; and the instance's log holds no `Frame Job: ` line.
- **V1**: the live meter (`loudness_meter`, `play_preview` 5 s at ×1 from 0,
  as AP7's L1) reads a project at track volume 0.5, pan −0.5 within 0.01 LU
  of its export's integrated loudness over the same frames, every one of them
  inside the export (a play to the 6 s tone's end counts the flush past it).
- **B1–B4** (the probe `audio_ap10_probe.swift`, compiled AS `main.swift` over
  `app/Sources` on `swift_build.py`'s line; a probe that will not build is a
  scored failure): the balance's product and unity, the chain's order (the
  balance before the limiter), `isInert` with the builder's gate (a project
  whose only processing is a track pan builds a tap — P1 offline), and
  `TrackMixLevel`.

Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff all pass.
"""

import array
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

import swift_build  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
MEDIA = HERE / "media"
OUT = HERE / "work" / "audio_ap10"
RATE = 48000
SEC = 600_000
WINDOW = 1200  # 11 cycles of 440 Hz at 48 kHz
TONE_DB = -12.0
TOL = 0.02
PROBE_ROWS = ["B1", "B2", "B3", "B4"]

MUTANTS = [
    ("M6", "B3", "CompositionBuilder+AudioTracks.swift",
     "let trackDSP = dsp.isEmpty && !pans",
     "let trackDSP = dsp.isEmpty && pans == pans"),
    ("M7", "B2", "AudioDSP.swift",
     "        if params.trackBalance != .unity, count >= 2 {\n"
     "            balance(channels, frames: frames, by: params.trackBalance)\n"
     "        }\n\n"
     "        // Last, for the whole track once any clip on it asks (AU-23): a\n"
     "        // clip without a limiter passes through it as a delay.\n"
     "        limiter?.process(channels, count: count, frames: frames, settings: params.limiter)\n",
     "        // Last, for the whole track once any clip on it asks (AU-23): a\n"
     "        // clip without a limiter passes through it as a delay.\n"
     "        limiter?.process(channels, count: count, frames: frames, settings: params.limiter)\n"
     "        if params.trackBalance != .unity, count >= 2 {\n"
     "            balance(channels, frames: frames, by: params.trackBalance)\n"
     "        }\n"),
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
    shutil.copyfile(HERE / "audio_ap10_probe.swift", entry)
    blank = out / "Blank.mp4"
    if not blank.exists():
        shutil.copyfile(ROOT / "app/Resources/Blank.mp4", blank)
    binary = out / "audio-ap10-probe"
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


def mutants():
    killed = 0
    sources = ROOT / "app/Sources"
    for name, target, file, old, new in MUTANTS:
        tree = OUT / f"mutant-{name}" / "Sources"
        shutil.rmtree(tree, ignore_errors=True)
        shutil.copytree(sources, tree)
        path = tree / file
        text = path.read_text()
        if text.count(old) != 1:
            print(f"{name} FAIL — anchor not found once in {file}", flush=True)
            continue
        path.write_text(text.replace(old, new))
        found, problem = run_probe(tree, f"mutant-{name}")
        if found is None:
            print(f"{name} FAIL — did not build: {problem}", flush=True)
            continue
        dead = found.get(target, (True, ""))[0] is False
        killed += dead
        failing = sorted(r for r, (ok, _) in found.items() if not ok)
        print(f"{name} {'killed' if dead else 'SURVIVED'} by {target} — failing rows: "
              f"{', '.join(failing) or 'none'}", flush=True)
    print(f"{killed}/{len(MUTANTS)} mutants killed", flush=True)
    return killed == len(MUTANTS)


# ---- fixtures and reading an export ------------------------------------------------

def run(command):
    subprocess.run(command, check=True, timeout=120, capture_output=True)


def fixtures():
    MEDIA.mkdir(parents=True, exist_ok=True)
    amplitude = 10 ** (TONE_DB / 20)
    tone = MEDIA / "ap10_tone.wav"
    if not tone.exists():
        run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
             f"aevalsrc='{amplitude}*sin(2*PI*440*t)|{amplitude}*sin(2*PI*440*t)':s={RATE}:d=6",
             "-c:a", "pcm_s16le", str(tone)])
    mono = MEDIA / "ap10_tone_mono.wav"
    if not mono.exists():
        run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
             f"aevalsrc='{amplitude}*sin(2*PI*440*t)':s={RATE}:d=6",
             "-c:a", "pcm_s16le", str(mono)])
    return str(tone), str(mono)


def decode(path):
    """The export's two channels as floats."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-vn", "-f", "s16le", "-acodec", "pcm_s16le",
         "-ar", str(RATE), "-ac", "2", "-"], check=True, timeout=120, capture_output=True).stdout
    values = array.array("h")
    values.frombytes(raw)
    return [[s / 32768.0 for s in values[0::2]], [s / 32768.0 for s in values[1::2]]]


def amplitude(channel, start):
    i = q = 0.0
    for n in range(start, start + WINDOW):
        phase = 2 * math.pi * 440 * n / RATE
        i += channel[n] * math.sin(phase)
        q += channel[n] * math.cos(phase)
    return 2 * math.hypot(i, q) / WINDOW


def level(channel):
    """The mean 440 Hz amplitude over 1–3 s."""
    starts = range(RATE, 3 * RATE - WINDOW + 1, WINDOW)
    return sum(amplitude(channel, s) for s in starts) / len(starts)


def levels(stereo):
    return [level(c) for c in stereo]


def db(value, reference):
    return 20 * math.log10(max(value, 1e-12) / reference)


def law(pan):
    """`AudioPanLaw.gains`: constant power, unity at the centre."""
    theta = (min(max(pan, -1), 1) + 1) * math.pi / 4
    return math.cos(theta) * math.sqrt(2), math.sin(theta) * math.sqrt(2)


# ---- one project -------------------------------------------------------------------

class Project:
    def __init__(self, mcp, name, media_path):
        self.mcp = mcp
        self.path = str(OUT / f"{name}-{os.getpid()}.framejob")
        mcp.call("new_project", path=self.path)
        self.track = self.get()["tracks"][0]["id"]
        media = self.call("import_media", path=media_path)["media"]
        self.clip = self.call("add_clip", track=self.track, media=media, at=0)["new_clips"][0]

    def call(self, tool, **kwargs):
        return self.mcp.call(tool, project=self.path, **kwargs)

    def get(self):
        return self.call("get_project")["project"]

    def nest(self):
        """Nests the clip: (the nest's id, its one track's id)."""
        self.call("nest", clips=[self.clip])
        project = self.get()
        nest = project["nests"][-1]
        self.nest_clip = [c for c in project["clips"] if c["source"].get("kind") == "nest"][0]["id"]
        return nest["id"], nest["tracks"][0]["id"]

    def export(self, label):
        result = self.mcp.export(project=self.path, preset="audio_wav",
                                 path=str(OUT / f"{label}-{os.getpid()}"))
        return decode(result["path"])

    def close(self):
        self.mcp.call("close_project", project=self.path, discard=True)


def measured(mcp, label, media, setup):
    """`setup(project)`, then the export's per-channel levels and samples."""
    project = Project(mcp, label, media)
    try:
        extra = setup(project)
        stereo = project.export(label)
        return levels(stereo), stereo, extra
    finally:
        project.close()


def against(got, reference, want_db):
    """Each channel's dB against `want_db` (a pair), the worst |Δ|."""
    got_db = [db(g, r) for g, r in zip(got, reference)]
    worst = max(abs(g - w) for g, w in zip(got_db, want_db))
    return got_db, worst


def fmt(values):
    return "(" + ", ".join(f"{v:+.3f}" for v in values) + ") dB"


# ---- the rows ----------------------------------------------------------------------

def fader_rows(mcp, tone):
    unity, _, _ = measured(mcp, "unity", tone, lambda p: None)
    six = 20 * math.log10(0.5)

    got, _, _ = measured(mcp, "f1", tone,
                         lambda p: p.call("set_track", track=p.track, volume=0.5))
    got_db, worst = against(got, unity, [six, six])
    row("F1", worst <= TOL, f"track 0.5: {fmt(got_db)} (want {six:+.3f} ±{TOL})")

    def f2(p):
        p.call("set_audio", clips=[p.clip], patch={"volume": 2})
        p.call("set_track", track=p.track, volume=0.25)
    got, _, _ = measured(mcp, "f2", tone, f2)
    got_db, worst = against(got, unity, [six, six])
    row("F2", worst <= TOL, f"clip 2 × track 0.25: {fmt(got_db)} (want {six:+.3f} ±{TOL})")

    def f3(p):
        nest, inner = p.nest()
        p.call("set_track", track=inner, volume=0.5, scope=nest)
        p.call("set_track", track=p.track, volume=0.5)
        inner_track = [n for n in p.get()["nests"] if n["id"] == nest][0]["tracks"][0]
        return inner_track.get("volume")
    got, _, stored = measured(mcp, "f3", tone, f3)
    got_db, worst = against(got, unity, [2 * six, 2 * six])
    row("F3", worst <= TOL and stored == 0.5,
        f"inner 0.5 (scoped, stored {stored}) × outer 0.5: {fmt(got_db)} "
        f"(want {2 * six:+.3f} ±{TOL})")

    def f4(p):
        p.call("set_track", track=p.track, volume=4, muted=True)
    _, stereo, _ = measured(mcp, "f4", tone, f4)
    peak = max(max(abs(s) for s in channel) for channel in stereo)
    peak_db = 20 * math.log10(peak) if peak > 0 else -math.inf
    row("F4", peak_db <= -120, f"muted at ×4: peak {peak_db} dBFS (want ≤ −120)")

    def mixed(p):
        p.call("set_track", track=p.track, volume=0.5, pan=-0.5)
    before, _, _ = measured(mcp, "f5a", tone, mixed)

    def nested(p):
        mixed(p)
        nest, _ = p.nest()
        return [n for n in p.get()["nests"] if n["id"] == nest][0]["tracks"][0]
    after, _, inner = measured(mcp, "f5b", tone, nested)
    delta = [db(a, b) for a, b in zip(after, before)]
    keys = "volume" not in inner and "pan" not in inner
    row("F5", max(abs(d) for d in delta) <= TOL and keys,
        f"nested against un-nested: {fmt(delta)} (want 0 ±{TOL}); the nest's track "
        f"{ {k: inner.get(k) for k in ('volume', 'pan')} } (want no keys)")
    return unity


def pan_rows(mcp, tone, mono, unity):
    got, stereo, _ = measured(mcp, "p1a", tone,
                              lambda p: p.call("set_track", track=p.track, pan=-1))
    left = db(got[0], unity[0])
    right_peak = max(abs(s) for s in stereo[1])
    hard = abs(left - 20 * math.log10(math.sqrt(2))) <= TOL and right_peak == 0
    got, _, _ = measured(mcp, "p1b", tone,
                         lambda p: p.call("set_track", track=p.track, pan=0.5))
    want = [20 * math.log10(g) for g in law(0.5)]
    got_db, worst = against(got, unity, want)
    row("P1", hard and worst <= TOL,
        f"pan −1: L {left:+.3f} dB (want +3.010), R peak {right_peak}; pan 0.5: {fmt(got_db)} "
        f"(want {fmt(want)} ±{TOL})")

    def p2(p):
        nest, inner = p.nest()
        p.call("set_track", track=inner, pan=-0.5, scope=nest)
        p.call("set_track", track=p.track, pan=0.5)
    got, _, _ = measured(mcp, "p2", tone, p2)
    want = [20 * math.log10(a * b) for a, b in zip(law(-0.5), law(0.5))]
    got_db, worst = against(got, unity, want)
    row("P2", worst <= TOL, f"inner −0.5 × outer +0.5: {fmt(got_db)} (want {fmt(want)} ±{TOL})")

    def p3(p):
        nest, inner = p.nest()
        p.call("set_track", track=inner, pan=-1, scope=nest)
        p.call("set_audio", clips=[p.nest_clip], patch={"mono": True})
    got, _, _ = measured(mcp, "p3", tone, p3)
    apart = db(got[0], got[1])
    row("P3", abs(apart) <= TOL and got[0] > 0,
        f"inner pan −1 in a folded nest: L {db(got[0], unity[0]):+.3f}, R "
        f"{db(got[1], unity[1]):+.3f} dB, L − R {apart:+.3f} dB (want 0 ±{TOL})")

    mono_unity, _, _ = measured(mcp, "p4u", mono, lambda p: None)
    got, _, _ = measured(mcp, "p4", mono,
                         lambda p: p.call("set_track", track=p.track, pan=-1))
    got_db, worst = against(got, mono_unity, [0, 0])
    row("P4", worst <= TOL, f"a mono source at track pan −1: {fmt(got_db)} (want 0 ±{TOL})")

    def p5(p):
        p.call("set_audio", clips=[p.clip], patch={"pan": -0.5})
        p.call("set_track", track=p.track, pan=-0.5)
    got, _, _ = measured(mcp, "p5", tone, p5)
    want = [20 * math.log10(g * g) for g in law(-0.5)]
    got_db, worst = against(got, unity, want)
    row("P5", worst <= TOL, f"clip −0.5 × track −0.5: {fmt(got_db)} (want {fmt(want)} ±{TOL})")


def undo_row(mcp, tone, socket):
    project = Project(mcp, "u1", tone)
    try:
        def track():
            return [t for t in project.get()["tracks"] if t["id"] == project.track][0]
        fresh = track()
        project.call("set_track", track=project.track, volume=0.5, pan=0.25)
        edited = track()
        project.call("undo")
        undone = track()
        log = Path(socket).parent / "framejob.log"
        complaints = [line for line in log.read_text(errors="replace").splitlines()
                      if "Frame Job: " in line] if log.exists() else ["no log"]
        no_keys = all("volume" not in t and "pan" not in t for t in (fresh, undone))
        row("U1", no_keys and edited.get("volume") == 0.5 and edited.get("pan") == 0.25
            and undone == fresh and not complaints,
            f"fresh {fresh}; after set_track {edited}; after one undo {undone}; log "
            f"{len(complaints)} complaint line(s) {complaints[:2]}")
    finally:
        project.close()


def meter_row(mcp, tone, socket):
    sys.argv[1:] = [socket]  # phase5_proof reads its socket at import
    import phase5_proof as p5
    import audio_ap7_proof as ap7
    from mcp import ToolError

    project = Project(mcp, "v1", tone)
    try:
        project.call("set_track", track=project.track, volume=0.5, pan=-0.5)
        project.call("set_playhead", t=0)
        project.call("loudness_meter", reset=True)
        deadline = time.monotonic() + 60
        while True:
            try:
                # 5 s of the 6 s tone, so the frames the meter counts are all
                # inside the export (a play to the end counts the flush past it).
                project.call("play_preview", seconds=5)
                break
            except ToolError as error:
                if "nothing to play" not in str(error) or time.monotonic() > deadline:
                    raise
                time.sleep(0.5)
        got = project.call("loudness_meter")
        rate = got["sample_rate"] or RATE
        start = round(got["from_frame"] * RATE / rate) if got["from_frame"] is not None else 0
        end = round(got["to_frame"] * RATE / rate) if got["to_frame"] is not None else 0
        stereo = project.export("v1")
        want = ap7.measure([stereo[0][start:end], stereo[1][start:end]], p5)
        live = got["integrated_lufs"]
        diff = abs(live - want["I"]) if isinstance(live, (int, float)) and want["I"] is not None \
            else math.inf
        row("V1", end - start >= 4 * RATE and end <= len(stereo[0]) and diff <= 0.01,
            f"meter [{got['from_frame']}, {got['to_frame']}) at {got['sample_rate']} Hz: I "
            f"{live}; export over the same frames I {ap7.fmt(want['I'])}; |dI| {diff:.4f} LU "
            f"(want ≤ 0.01)")
    finally:
        project.close()


def main():
    if sys.argv[1:] == ["--probe"]:
        shutil.rmtree(OUT, ignore_errors=True)
        probe_rows()
    elif sys.argv[1:] == ["--mutants"]:
        return 0 if mutants() else 1
    elif len(sys.argv) == 2 and not sys.argv[1].startswith("-"):
        from mcp import MCP
        socket = sys.argv[1]
        shutil.rmtree(OUT, ignore_errors=True)
        OUT.mkdir(parents=True)
        probe_rows()
        tone, mono = fixtures()
        mcp = MCP(socket)
        unity = fader_rows(mcp, tone)
        pan_rows(mcp, tone, mono, unity)
        undo_row(mcp, tone, socket)
        meter_row(mcp, tone, socket)
    else:
        print(__doc__.split("\n\n")[1])
        return 2
    passed = sum(1 for _, ok in rows if ok)
    print(f"{passed}/{len(rows)}", flush=True)
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
