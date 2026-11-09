"""Road map "audio" AP8b — every other audio parameter animates as action ends
(spec §11 AU-85..AU-89), measured on exports over MCP, and the probe behind it.

    python3 tools/proof/audio_ap8b_proof.py <dir>/agent.sock
    python3 tools/proof/audio_ap8b_proof.py --probe
    python3 tools/proof/audio_ap8b_proof.py --mutants

The caller owns the instance at that socket; nothing is launched or killed.
Needs `ffmpeg` and numpy. `--probe` runs A1–A8 alone, with no instance;
`--mutants` runs M1–M14: M4–M12 and M14 each over its own copy of `app/Sources`,
killed when its named probe row fails, and M1–M3 and M13 each in one copy of
`core/` (`graphic/` beside it as a symlink, the target folder
`work/audio_ap8b-core-target/`, seeded from `core/target` and kept), killed
when its named test in `core/tests/` fails.

**Fixtures**, made on the first run into `tools/proof/media/` (kept), 6 s of
48 kHz stereo 24-bit sine, both channels alike: `ap8b_440.wav` (−12 dBFS),
`ap8b_1k.wav` (1 kHz, −20 dBFS), `ap8b_4k.wav` (4 kHz, −12 dBFS, its peaks on
the sample grid), `ap8b_200.wav` (200 Hz, −12 dBFS) and `ap8b_hot.wav` (440 Hz,
−3 dBFS); E5 reads the owner's `samples/Rode-usb-mic.m4a`. Each project is a
new one with one clip at 0 and one action over [1 s, 3 s) of it, closed with
`close_project` (discarded). Exports are 24-bit `audio_wav`, under the master
limiter's −1 dBTP, decoded to float by ffmpeg.

Levels are read by quadrature at the tone's frequency over windows of exactly
1,200 samples (25 ms, a whole number of cycles), per channel, against the
same fixture's plain export read the same way, each window judged at its
centre time.

Rows:
- **E1**: pan −0.5 → +0.5, linear: every window from 0.5 s to 3.5 s within
  ±0.05 dB of `AudioPanLaw` per channel.
- **E2**: band 2 at 1 kHz, Q 1, gain 0 → +12 dB, linear, on the 1 kHz tone:
  within ±0.1 dB of the gain, 0.5 s to 3.5 s.
- **E3**: the compressor (ratio 4, attack and release 0) threshold −40 → 0 dB,
  linear, on the 4 kHz tone: within ±0.25 dB of the static curve
  `−max(0, (−12 − T)·0.75)`, 0.5 s to 3.5 s.
- **E4**: a limiter (−6 dBTP) switched on at the action's end over the hot
  tone: within 1 LSB of the plain export, sample for sample, over [158
  samples, 3 s − 158 samples) — the limiter's 158 samples (AU-20) are the
  head its lead cannot place before 0 (AU-23's head cost) and its lookahead,
  which turns the gain down that far before the first limited sample; from
  3.1 s its 4× true peak at most −5.9 dBTP.
- **E5**: isolation 0 → 1, linear, from a base of 0, on the recording trimmed
  to 4 s: within 2 LSB of `dry + a(t)·(wet − dry)` from its isolation-0 and
  isolation-1 exports, `a` per frame.
- **E6**: a 1 kHz high-pass (24 dB/oct) on the 200 Hz tone keyed off by
  `set_action_end` `off: ["audio.eq.high_pass"]`: every window to 2.9 s at
  least 20 dB down, every window from 3.1 s within ±0.1 dB of the plain tone;
  the stored end is `{"audio": {"eq": {"high_pass": null}}}`.
- **V1**: the live meter (`loudness_meter`, `play_preview` 5 s at ×1 from 0,
  as AP10's V1) on E2's project within 0.01 LU of its export's integrated
  loudness over the same frames.
- **U1**: one `set_action_end {audio: {pan}}` is one undo step, and the
  instance's log holds no `Frame Job: ` line.
- **A1–A8** (the probe `audio_ap8b_probe.swift`, compiled AS `main.swift` over
  `app/Sources` on `swift_build.py`'s line; a probe that will not build is a
  scored failure): its head lists them.

Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff all pass.
"""

import math
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
OUT = HERE / "work" / "audio_ap8b"
EXPORTS = OUT / "mcp"  # the MCP rows' projects and exports, cleared per run alone
CORE_TARGET = HERE / "work" / "audio_ap8b-core-target"
RODE = ROOT / "samples/Rode-usb-mic.m4a"
RATE = 48000
SEC = 600_000
WINDOW = 1200
LSB = 1 / 2 ** 23
LIMITER_FRAMES = 158  # the clip limiter's delay and lookahead at 48 kHz (AU-20)
PROBE_ROWS = ["A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8"]

# (name, row, file, anchor, replacement): each anchor exactly once.
MUTANTS = [
    ("M4", "A2", "AudioAutomation.swift",
     "            grid, Self.frame(ofTick: points[i].at, rate: rate),",
     "            frame, Self.frame(ofTick: points[i].at, rate: rate),"),
    ("M5", "A1", "AudioAutomation.swift",
     "            mono: mono, keepPitch: keepPitch,",
     "            mono: next.mono, keepPitch: keepPitch,"),
    ("M6", "A4", "AudioAutomation.swift",
     "    var usesLimiter: Bool { points.contains { $0.audio.limiter != nil } }",
     "    var usesLimiter: Bool { points.isEmpty }"),
    ("M7", "A3", "AudioDSP.swift",
     "        if let panRamp, count >= 2 {",
     "        if let panRamp, count >= 200 {"),
    ("M8", "A5", "AudioIsolation.swift",
     "            let amounts = voice == nil ? Self.amounts(of: s, base: amount, shift: shift, "
     "dsp: dsp) : []",
     "            let amounts: [AudioIsolationAmount] = []"),
    ("M9", "A6", "AudioAutomation.swift",
     "            fadeInShape: fadeInShape, fadeOutShape: fadeOutShape, voice: voice)",
     "            fadeInShape: fadeInShape, fadeOutShape: fadeOutShape, eq: eq, voice: voice)"),
    ("M10", "A7", "AudioDynamicsLevels.swift",
     "|| ended($0))",
     "|| false)"),
    ("M11", "A1", "AudioAutomation.swift",
     "slope: $0.slope) }",
     "slope: Int((Double($0.slope) + Double($1.slope - $0.slope) * f).rounded())) }"),
    ("M12", "A8", "ReelOps.swift",
     "            if group == \"audio\", var eq = fields[\"eq\"] as? [String: Any] {",
     "            if group == \"nothing\", var eq = fields[\"eq\"] as? [String: Any] {"),
    ("M14", "A7", "AudioTapSchedule.swift",
     "|| (!voiced\n                        && clip.actions.contains",
     "|| (clip.actions.contains"),
]

# (name, test file, test name, file under core/src, anchor, replacement).
CORE_MUTANTS = [
    ("M1", "audio_automation", "a_linear_pan_action_gives_exactly_four_points",
     "audio_automation.rs",
     "            ticks.push(start);\n            ticks.push(end);\n", ""),
    ("M2", "audio_automation", "isolation_is_present_at_zero_and_ramps_from_it",
     "actions_audio.rs",
     "        if !fields.contains_key(\"isolation\") {",
     "        if false && !fields.contains_key(\"isolation\") {"),
    ("M3", "audio_automation", "an_eq_slope_holds_until_the_actions_end",
     "actions.rs",
     "            hold_audio_steps(&state, &mut lerped);\n", ""),
    ("M13", "action_off", "off_keys_one_eq_slot_off_at_the_end",
     "edit_action_end.rs",
     "        Some(slot) => (object_at(fields, path.key), slot),",
     "        Some(_) => (Some(fields), path.key),"),
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
    shutil.copyfile(HERE / "audio_ap8b_probe.swift", entry)
    binary = out / "audio-ap8b-probe"
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


def app_mutants():
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
    return killed


def core_mutants():
    """M1–M3 and M13 in one copy of `core/`, each file restored after its run."""
    killed = 0
    base = OUT / "core-mutants"
    copy = base / "core"
    shutil.rmtree(base, ignore_errors=True)
    base.mkdir(parents=True)
    shutil.copytree(ROOT / "core", copy, ignore=shutil.ignore_patterns("target"))
    (base / "graphic").symlink_to(ROOT / "graphic")
    if not CORE_TARGET.exists() and (ROOT / "core/target").exists():
        subprocess.run(["cp", "-cR", str(ROOT / "core/target"), str(CORE_TARGET)], check=False)
    env = dict(os.environ, CARGO_TARGET_DIR=str(CORE_TARGET))
    for name, test, case, file, old, new in CORE_MUTANTS:
        path = copy / "src" / file
        original = (ROOT / "core/src" / file).read_text()
        if original.count(old) != 1:
            print(f"{name} FAIL — anchor not found once in core/src/{file}", flush=True)
            continue
        path.write_text(original.replace(old, new))
        try:
            result = subprocess.run(
                ["cargo", "test", "--release", "--test", test], cwd=str(copy), env=env,
                capture_output=True, text=True, timeout=1800)
            log = result.stdout + result.stderr
        except subprocess.TimeoutExpired:
            log = ""
            result = None
        finally:
            path.write_text(original)
        dead = result is not None and result.returncode != 0 \
            and f"test {case} ... FAILED" in log
        built = result is not None and "error[" not in log
        killed += dead
        print(f"{name} {'killed' if dead else 'SURVIVED'} by core/tests/{test}.rs {case} — "
              f"exit {result.returncode if result else 'timeout'}, built {built}", flush=True)
    return killed


def mutants():
    killed = app_mutants() + core_mutants()
    total = len(MUTANTS) + len(CORE_MUTANTS)
    print(f"{killed}/{total} mutants killed", flush=True)
    return killed == total


# ---- fixtures and reading an export ------------------------------------------------

def run(command):
    subprocess.run(command, check=True, timeout=120, capture_output=True)


def tone(name, frequency, dbfs):
    path = MEDIA / name
    if not path.exists():
        a = 10 ** (dbfs / 20)
        run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
             f"aevalsrc='{a}*sin(2*PI*{frequency}*t)|{a}*sin(2*PI*{frequency}*t)':s={RATE}:d=6",
             "-c:a", "pcm_s24le", str(path)])
    return str(path)


def fixtures():
    MEDIA.mkdir(parents=True, exist_ok=True)
    return {
        "440": tone("ap8b_440.wav", 440, -12), "1k": tone("ap8b_1k.wav", 1000, -20),
        "4k": tone("ap8b_4k.wav", 4000, -12), "200": tone("ap8b_200.wav", 200, -12),
        "hot": tone("ap8b_hot.wav", 440, -3),
    }


def decode(path):
    """The export's two channels as float64 arrays."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-vn", "-f", "f32le", "-acodec", "pcm_f32le",
         "-ar", str(RATE), "-ac", "2", "-"], check=True, timeout=120, capture_output=True).stdout
    values = np.frombuffer(raw, dtype="<f4").astype(np.float64)
    return [values[0::2], values[1::2]]


def amplitude(channel, start, frequency):
    n = np.arange(start, start + WINDOW)
    phase = 2 * np.pi * frequency * n / RATE
    x = channel[start:start + WINDOW]
    return 2 * math.hypot(float(np.dot(x, np.sin(phase))), float(np.dot(x, np.cos(phase)))) / WINDOW


def windows(start_s, end_s):
    """Window starts covering [start_s, end_s)."""
    return range(int(start_s * RATE), int(end_s * RATE) - WINDOW + 1, WINDOW)


def centre(start):
    return (start + WINDOW / 2) / RATE


def db(value, reference):
    return 20 * math.log10(max(value, 1e-15) / max(reference, 1e-15))


def law(pan):
    """`AudioPanLaw.gains`: constant power, unity at the centre."""
    theta = (min(max(pan, -1), 1) + 1) * math.pi / 4
    return math.cos(theta) * math.sqrt(2), math.sin(theta) * math.sqrt(2)


def ramp(t):
    """A linear action over [1 s, 3 s): its progress at `t` seconds."""
    return min(max((t - 1) / 2, 0), 1)


def true_peak(x):
    """4× oversampled peak of `x` (FFT zero-padding), in dBFS."""
    n = len(x)
    spectrum = np.fft.rfft(x)
    up = np.fft.irfft(spectrum, 4 * n) * 4
    return 20 * math.log10(max(float(np.max(np.abs(up))), 1e-15))


# ---- one project -------------------------------------------------------------------

class Project:
    def __init__(self, mcp, name, media_path, end=None):
        self.mcp = mcp
        self.path = str(EXPORTS / f"{name}-{os.getpid()}.framejob")
        mcp.call("new_project", path=self.path)
        self.track = self.get()["tracks"][0]["id"]
        media = self.call("import_media", path=media_path)["media"]
        self.clip = self.call("add_clip", track=self.track, media=media, at=0)["new_clips"][0]
        if end is not None:
            self.call("trim_end", clip=self.clip, to=end)

    def call(self, tool, **kwargs):
        return self.mcp.call(tool, project=self.path, **kwargs)

    def get(self):
        return self.call("get_project")["project"]

    def audio(self, **patch):
        self.call("set_audio", clips=[self.clip], patch=patch)

    def clip_json(self):
        return [c for c in self.get()["clips"] if c["id"] == self.clip][0]

    def action(self, patch, off=None, curve=None):
        """One action over [1 s, 3 s) ending at `patch` (and `off`): its id."""
        self.call("add_action", clip=self.clip, at=SEC, duration=2 * SEC)
        action = [a for a in self.clip_json()["actions"] if a["start"] == SEC][0]["id"]
        if curve:
            self.call("set_action", clip=self.clip, action=action, curve=curve)
        arguments = {"clip": self.clip, "action": action, "patch": patch}
        if off:
            arguments["off"] = off
        self.call("set_action_end", **arguments)
        return action

    def export(self, label):
        result = self.mcp.export(project=self.path, preset="audio_wav", audio_bits=24,
                                 path=str(EXPORTS / f"{label}-{os.getpid()}"))
        return decode(result["path"])

    def close(self):
        self.mcp.call("close_project", project=self.path, discard=True)


def exported(mcp, label, media, setup=None, end=None):
    project = Project(mcp, label, media, end=end)
    try:
        extra = setup(project) if setup else None
        return project.export(label), extra
    finally:
        project.close()


# ---- the rows ----------------------------------------------------------------------

def e1(mcp, media):
    plain, _ = exported(mcp, "e1-plain", media["440"])

    def setup(p):
        p.audio(pan=-0.5)
        p.action({"audio": {"pan": 0.5}})
    got, _ = exported(mcp, "e1", media["440"], setup)
    worst = 0.0
    count = 0
    for start in windows(0.5, 3.5):
        want = law(-0.5 + ramp(centre(start)))
        for c in (0, 1):
            measured = db(amplitude(got[c], start, 440), amplitude(plain[c], start, 440))
            worst = max(worst, abs(measured - 20 * math.log10(want[c])))
        count += 1
    row("E1", worst <= 0.05,
        f"pan −0.5 → +0.5 over [1, 3) s: {count} windows × 2 channels, worst |Δ| "
        f"{worst:.4f} dB against the law (want ≤ 0.05)")


def e2(mcp, media):
    plain, _ = exported(mcp, "e2-plain", media["1k"])

    def setup(p):
        p.audio(eq={"band_2": {"frequency": 1000, "gain_db": 0, "q": 1}})
        p.action({"audio": {"eq": {"band_2": {"gain_db": 12}}}})
    got, _ = exported(mcp, "e2", media["1k"], setup)
    worst = 0.0
    for start in windows(0.5, 3.5):
        want = 12 * ramp(centre(start))
        for c in (0, 1):
            measured = db(amplitude(got[c], start, 1000), amplitude(plain[c], start, 1000))
            worst = max(worst, abs(measured - want))
    row("E2", worst <= 0.1,
        f"band 2 gain 0 → +12 dB at 1 kHz: worst |Δ| {worst:.4f} dB against 12·u(t) "
        f"(want ≤ 0.1)")


def e3(mcp, media):
    plain, _ = exported(mcp, "e3-plain", media["4k"])

    def setup(p):
        p.audio(compressor={"threshold_db": -40, "ratio": 4, "attack": 0, "release": 0,
                            "makeup_db": 0})
        p.action({"audio": {"compressor": {"threshold_db": 0}}})
    got, _ = exported(mcp, "e3", media["4k"], setup)
    worst = 0.0
    for start in windows(0.5, 3.5):
        threshold = -40 + 40 * ramp(centre(start))
        want = -max(0.0, (-12 - threshold) * 0.75)
        for c in (0, 1):
            measured = db(amplitude(got[c], start, 4000), amplitude(plain[c], start, 4000))
            worst = max(worst, abs(measured - want))
    row("E3", worst <= 0.25,
        f"compressor 4:1 threshold −40 → 0 dB on a −12 dBFS tone: worst |Δ| {worst:.4f} dB "
        f"against the static curve (want ≤ 0.25)")


def e4(mcp, media):
    plain, _ = exported(mcp, "e4-plain", media["hot"])
    got, _ = exported(mcp, "e4", media["hot"],
                      lambda p: p.action({"audio": {"limiter": {"ceiling_db": -6}}}))
    switch = 3 * RATE
    # The limiter's 158 samples (AU-20): the head the track's lead cannot place
    # before 0 (AU-23's head cost) and the lookahead, which turns the gain down
    # that far ahead of the first limited sample.
    lead = LIMITER_FRAMES
    before = max(float(np.max(np.abs(got[c][lead:switch - lead] - plain[c][lead:switch - lead])))
                 for c in (0, 1))
    after = max(true_peak(got[c][int(3.1 * RATE):int(5.9 * RATE)]) for c in (0, 1))
    row("E4", before <= LSB and after <= -5.9,
        f"over [{lead}, 3 s − {lead}) samples max |Δ| against the plain export "
        f"{before / LSB:.2f} LSB (want ≤ 1); from 3.1 s true peak {after:+.3f} dBTP "
        f"(want ≤ −5.9)")


def e5(mcp):
    if not RODE.exists():
        row("E5", False, f"{RODE} is missing")
        return
    rode = str(RODE)
    end = 4 * SEC
    dry, _ = exported(mcp, "e5-dry", rode, end=end)
    wet, _ = exported(mcp, "e5-wet", rode, lambda p: p.audio(isolation=1), end=end)

    def setup(p):
        p.action({"audio": {"isolation": 1}})
        return "isolation" in p.clip_json().get("audio", {})
    got, keyed = exported(mcp, "e5", rode, setup, end=end)
    n = min(len(got[0]), len(dry[0]), len(wet[0]))
    a = np.clip((np.arange(n) * SEC / RATE - SEC) / (2 * SEC), 0, 1)
    worst = max(float(np.max(np.abs(got[c][:n] - (dry[c][:n] + a * (wet[c][:n] - dry[c][:n])))))
                for c in (0, 1))
    moved = float(np.max(np.abs(wet[0][:n] - dry[0][:n])))
    row("E5", worst <= 2 * LSB and not keyed and moved > 100 * LSB,
        f"Amount 0 → 1 from base 0 (a base key {keyed}): worst |out − (dry + a·(wet − dry))| "
        f"{worst / LSB:.2f} LSB over {n} frames (want ≤ 2); wet − dry up to {moved:.4f}")


def e6(mcp, media):
    plain, _ = exported(mcp, "e6-plain", media["200"])

    def setup(p):
        p.audio(eq={"high_pass": {"frequency": 1000, "slope": 24}})
        action = p.action({}, off=["audio.eq.high_pass"])
        return [a for a in p.clip_json()["actions"] if a["id"] == action][0]["end"]
    got, end = exported(mcp, "e6", media["200"], setup)
    cut = max(db(amplitude(got[c], s, 200), amplitude(plain[c], s, 200))
              for s in windows(0.1, 2.9) for c in (0, 1))
    after = max(abs(db(amplitude(got[c], s, 200), amplitude(plain[c], s, 200)))
                for s in windows(3.1, 5.9) for c in (0, 1))
    stored = end == {"audio": {"eq": {"high_pass": None}}}
    row("E6", cut <= -20 and after <= 0.1 and stored,
        f"stored end {end}; before the end at most {cut:+.2f} dB (want ≤ −20); after it "
        f"worst |Δ| {after:.4f} dB of the dry tone (want ≤ 0.1)")


def meter_row(mcp, media, socket):
    sys.argv[1:] = [socket]  # phase5_proof reads its socket at import
    import phase5_proof as p5
    import audio_ap7_proof as ap7
    from mcp import ToolError

    project = Project(mcp, "v1", media["1k"])
    try:
        project.audio(eq={"band_2": {"frequency": 1000, "gain_db": 0, "q": 1}})
        project.action({"audio": {"eq": {"band_2": {"gain_db": 12}}}})
        project.call("set_playhead", t=0)
        project.call("loudness_meter", reset=True)
        deadline = time.monotonic() + 60
        while True:
            try:
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
        want = ap7.measure([list(stereo[0][start:end]), list(stereo[1][start:end])], p5)
        live = got["integrated_lufs"]
        diff = abs(live - want["I"]) if isinstance(live, (int, float)) and want["I"] is not None \
            else math.inf
        row("V1", end - start >= 4 * RATE and end <= len(stereo[0]) and diff <= 0.01,
            f"meter [{got['from_frame']}, {got['to_frame']}) at {got['sample_rate']} Hz: I "
            f"{live}; export over the same frames I {ap7.fmt(want['I'])}; |dI| {diff:.4f} LU "
            f"(want ≤ 0.01)")
    finally:
        project.close()


def undo_row(mcp, media, socket):
    project = Project(mcp, "u1", media["440"])
    try:
        project.call("add_action", clip=project.clip, at=SEC, duration=2 * SEC)
        action = project.clip_json()["actions"][0]["id"]
        fresh = project.clip_json()["actions"][0]["end"]
        project.call("set_action_end", clip=project.clip, action=action,
                     patch={"audio": {"pan": 0.5}})
        edited = project.clip_json()["actions"][0]["end"]
        project.call("undo")
        undone = project.clip_json()["actions"][0]["end"]
        log = Path(socket).parent / "framejob.log"
        complaints = [line for line in log.read_text(errors="replace").splitlines()
                      if "Frame Job: " in line] if log.exists() else ["no log"]
        row("U1", edited == {"audio": {"pan": 0.5}} and undone == fresh and not complaints,
            f"end {fresh}; after set_action_end {edited}; after one undo {undone}; log "
            f"{len(complaints)} complaint line(s) {complaints[:2]}")
    finally:
        project.close()


def main():
    if sys.argv[1:] == ["--probe"]:
        shutil.rmtree(OUT / "probe", ignore_errors=True)
        probe_rows()
    elif sys.argv[1:] == ["--mutants"]:
        return 0 if mutants() else 1
    elif len(sys.argv) == 2 and not sys.argv[1].startswith("-"):
        from mcp import MCP
        socket = sys.argv[1]
        shutil.rmtree(EXPORTS, ignore_errors=True)
        EXPORTS.mkdir(parents=True)
        probe_rows()
        media = fixtures()
        mcp = MCP(socket)
        for name, runner in [("E1", lambda: e1(mcp, media)), ("E2", lambda: e2(mcp, media)),
                             ("E3", lambda: e3(mcp, media)), ("E4", lambda: e4(mcp, media)),
                             ("E5", lambda: e5(mcp)), ("E6", lambda: e6(mcp, media)),
                             ("V1", lambda: meter_row(mcp, media, socket)),
                             ("U1", lambda: undo_row(mcp, media, socket))]:
            try:
                runner()
            except Exception as error:  # a broken instrument is a FAIL, not an exit
                row(name, False, f"the row could not run: {type(error).__name__}: {error}")
    else:
        print(__doc__.split("\n\n")[1])
        return 2
    passed = sum(1 for _, ok in rows if ok)
    print(f"{passed}/{len(rows)}", flush=True)
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
