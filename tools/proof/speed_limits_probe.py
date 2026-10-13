#!/usr/bin/env python3
"""Issue batch B52b — the ×1000 speed build (#190 part 2 of 2).

Proves, through the app's own code (`speed_limits_probe.swift`, compiled over
`app/Sources`), that every number about speed comes from the core, that an
h264 export FINISHES with a clip's audio at exactly ×12 in both pitch modes
and every shape, and that above ×12 it finishes with that clip's audio left
out (spec §11 #190: the owner's ceiling, a margin below the export's
loudness pass, which never finishes for a keep-pitch clip that starts its
audio track from ×15, nor in either mode from about ×20). No app instance is launched and no MCP call is made. Every
child runs under `graphics_spike/bounded.py` (rule H): its own process group,
a hard wall-clock bound, and an expiry is the row's answer.

B0  the core lib built: HEAD's `cargo build --release` in `core/`; for a
    mutant, a scratch tree in work/speed-limits/tree/ whose `diff -ru` against
    `core/src` is exactly the mutant's lines (bound 1800 s).
K1  `cargo test --release --test speed_x1000` passes, in `core/` or in the
    mutant's tree (bound 1800 s).
B1  the probe built (`speed_spike.py`'s `build_probe` line; bound 1800 s).
F0  work/speed-limits/tone_180.mov is 180 ±0.1 s, 320x180, with audio.
F1  work/speed-limits/tone_600.mov is 600 ±0.1 s, 320x180, with audio.
U1  limits (0.1, 1000, 12); the sheet's range 0.1…1000; its presets
    [0.25, 0.5, 1, 1.5, 2, 4, 10, 100].
U2  the Speed section's note: ×1 k nil (CONTROL), ×12 k nil, ×12 v nil,
    ×12.5 k and ×12.5 v "Audio is silent above ×12".
E1–E17  h264 exports of `R:S:k|v` timelines (deadline 120 s, runner bound
    180 s), every one required to FINISH. "Sound" is an RMS ≥ −40 dB over the
    span; "nothing" is an audio stream that ends by 2.05 s, or a peak ≤ −80 dB
    over [2.05 s, end); a missing span answer counts as nothing; "no audio"
    is a file with ≥ 1 video frame and no audio stream.

    python3 tools/proof/speed_limits_probe.py [--mutant ceiling-16|no-audio-limit|no-pitch-split]

Run it (about 3 minutes, small generated sources) when a change touches the
speed range or the audio ceiling (`edit_clip_timing.rs`), how `evaluate.rs`
assigns or places audio, `CompositionBuilder`'s audio parameters, or the
export's loudness pass — not on unrelated changes. It never needs
`speed_spike.py`'s hour-long movies.

A plain run exits 0 iff every row passed. A mutant (rule R) exits 1 when
every named row failed (caught), 0 when one passed (survived), 2 when it
could not be performed (an anchor not found exactly once, a build failure,
an instrument row). `no-pitch-split` is scored by K1 alone: no export hangs
on the split since the ceiling is ×12, so no export row can see it.
"""

import argparse
import json
import shutil
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof/speed_spike"))
import bounded  # noqa: E402
from speed_spike import astats, ffprobe_json, has_audio, probe, run, sync_tree  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/speed-limits"
TREE = WORK / "tree"
FIXTURES = {"180": WORK / "tone_180.mov", "600": WORK / "tone_600.mov"}
OUT = WORK / "out"
PROBE_SOURCE = ROOT / "tools/proof/speed_limits_probe.swift"
DEADLINE = 120
CEILING = "pub(crate) const AUDIO_SPEED_MAX: f64 = 12.0;"
MUTANTS = {
    "ceiling-16": ([("edit_clip_timing.rs", CEILING, CEILING.replace("12.0", "16.0"))],
                   ["U1", "U2", "E8", "E9", "E10", "E16"]),
    "no-audio-limit": ([("edit_clip_timing.rs", CEILING, CEILING.replace("12.0", "1000.0"))],
                       # Not E11/E12: above ×32 the export drops the audio by
                       # itself (B52a), so ×100 and ×1000 cannot see the ceiling.
                       ["U1", "U2", "E8", "E9", "E10", "E14", "E16"]),
    "no-pitch-split": ([("evaluate.rs", "!match_pitch ||", "true ||")], ["K1"]),
}
# (row, fixture, clips, [0,2), after 2.05 s, the whole file)
EXPORTS = [
    ("E1", "180", "1:2:k", "sound", None, None),
    ("E2", "180", "12:0:k", None, None, "sound"),
    ("E3", "180", "12:0:v", None, None, "sound"),
    ("E4", "180", "1:2:k,12:0:k", "sound", "sound", None),
    ("E5", "180", "1:2:v,12:0:v", "sound", "sound", None),
    ("E6", "600", "12:0:k", None, None, "sound"),
    ("E7", "600", "12:0:v", None, None, "sound"),
    ("E8", "180", "1:2:k,13:0:k", "sound", "nothing", None),
    ("E9", "180", "1:2:v,13:0:v", "sound", "nothing", None),
    ("E10", "180", "13:0:k", None, None, "no audio"),
    ("E11", "180", "1:2:k,100:0:k", "sound", "nothing", None),
    ("E12", "180", "1000:0:v", None, None, "no audio"),
    ("E13", "180", "1:2:k,12:0:v", "sound", "sound", None),
    ("E14", "180", "20:0:v", None, None, "no audio"),
    ("E15", "180", "12:2:k", None, None, "sound"),
    ("E16", "180", "16:0:k", None, None, "no audio"),
    ("E17", "180", "12:2:v", None, None, "sound"),
]

rows = {}
instrument = []


def emit(name, ok, detail, is_instrument=False):
    rows[name] = {"ok": ok, "detail": detail}
    if not ok and is_instrument:
        instrument.append(name)
    print(f"  {'pass' if ok else 'FAIL':<5} {name}  {detail}", flush=True)


# ---- B0: the core -------------------------------------------------------------

def head_core():
    env = bounded.child_env()
    env.pop("CARGO_TARGET_DIR", None)
    built = run(["cargo", "build", "--release"], 1800, cwd=ROOT / "core", env=env)
    lib = ROOT / "core/target/release/libframejob_core.a"
    ok = built["rc"] == 0 and lib.exists()
    emit("B0", ok, f"HEAD: cargo build --release rc {built['rc']} in {built['seconds']:.0f} s"
         + (" EXPIRED" if built["expired"] else "")
         + ("" if ok else f" · {built['stderr'][-400:]}"), is_instrument=True)
    return lib.parent if ok else None


def mutant_core(name):
    """A scratch tree with the mutant's exact-text edits, `None` and B0 failed
    when an anchor is not found exactly once or the diff or build is off."""
    edits, expected = {}, []
    for rel, old, new in MUTANTS[name][0]:
        text = edits.get(rel, (ROOT / "core/src" / rel).read_bytes()).decode()
        if text.count(old) != 1:
            emit("B0", False, f"{name}: `{old}` occurs {text.count(old)} times in {rel}, not once",
                 is_instrument=True)
            return None
        line = next(l for l in text.splitlines() if old in l)
        expected += ["-" + line, "+" + line.replace(old, new)]
        edits[rel] = text.replace(old, new).encode()
    for crate in ("core", "graphic"):
        (TREE / crate).mkdir(parents=True, exist_ok=True)
        for file in ("Cargo.toml", "Cargo.lock"):
            data = (ROOT / crate / file).read_bytes()
            dest = TREE / crate / file
            if not dest.exists() or dest.read_bytes() != data:
                dest.write_bytes(data)
    sync_tree(ROOT / "core/src", TREE / "core/src", edits)
    sync_tree(ROOT / "core/include", TREE / "core/include")
    sync_tree(ROOT / "core/tests", TREE / "core/tests")
    sync_tree(ROOT / "graphic/src", TREE / "graphic/src")
    diff = run(["diff", "-ru", ROOT / "core/src", TREE / "core/src"], 60)
    changed = [line for line in diff["stdout"].splitlines()
               if line[:1] in "+-" and not line.startswith(("+++", "---"))]
    exact = sorted(changed) == sorted(expected)
    env = bounded.child_env()
    env.pop("CARGO_TARGET_DIR", None)
    built = run(["cargo", "build", "--release", "--offline"], 1800, cwd=TREE / "core", env=env)
    lib = TREE / "core/target/release/libframejob_core.a"
    ok = exact and built["rc"] == 0 and lib.exists()
    emit("B0", ok, f"{name}: diff is exactly its {len(expected)} lines: {exact} · cargo rc "
         f"{built['rc']} in {built['seconds']:.0f} s" + (" EXPIRED" if built["expired"] else "")
         + ("" if built["rc"] == 0 else f" · {built['stderr'][-400:]}"), is_instrument=True)
    return lib.parent if ok else None


# ---- B1: the probe ------------------------------------------------------------

def build_probe(lib_dir, probe_dir):
    """`speed_spike.py`'s `build_probe` with this probe's source and folder:
    the app's `Fonts`, `Blank.mp4` and a `default.metallib` beside the binary,
    every `app/Sources` file but `main.swift`, the probe as `main.swift`,
    `-O -whole-module-optimization`, `-L <lib_dir>`, through
    `swift_build.build` (reused when every input is byte-identical to a
    cached build's)."""
    probe_dir.mkdir(parents=True, exist_ok=True)
    binary = probe_dir / "speed_limits_probe"
    entry = probe_dir / "main.swift"
    if not entry.exists() or entry.read_text() != PROBE_SOURCE.read_text():
        entry.write_text(PROBE_SOURCE.read_text())
    resources = ROOT / "app/Resources"
    fonts = probe_dir / "Fonts"
    if not fonts.is_dir() or (resources / "Fonts").stat().st_mtime > fonts.stat().st_mtime:
        shutil.rmtree(fonts, ignore_errors=True)
        shutil.copytree(resources / "Fonts", fonts)
    if not (probe_dir / "Blank.mp4").exists():
        shutil.copy2(resources / "Blank.mp4", probe_dir / "Blank.mp4")
    started = time.monotonic()
    shader = resources / "Shaders/Compositor.metal"
    metallib, air = probe_dir / "default.metallib", probe_dir / "Compositor.air"
    if not metallib.exists() or shader.stat().st_mtime > metallib.stat().st_mtime:
        step = run(["xcrun", "-sdk", "macosx", "metal", "-c", shader, "-o", air], 300)
        if step["rc"] == 0:
            step = run(["xcrun", "-sdk", "macosx", "metallib", air, "-o", metallib], 300)
        if step["rc"] != 0 or not metallib.exists():
            emit("B1", False, f"the shader did not build: {step['stderr'][-400:]}", True)
            return None
    try:
        built = swift_build.build(sources=swift_build.app_sources() + [entry], output=binary,
                                  defines=["FRAMEJOB_DEV_TOOLS"], optimize=True, wmo=True,
                                  library=lib_dir / "libframejob_core.a", timeout=1800)
    except swift_build.SwiftBuildFailed as error:
        emit("B1", False, f"swiftc rc {error.rc if error.rc is not None else 'before running'} "
             f"expired {error.expired}: "
             f"{(error.diagnostics or ['(no output)'])[:6]}", True)
        return None
    if built.reused:
        emit("B1", True, f"probe up to date — {binary} (linked to {lib_dir})")
        return binary
    emit("B1", True, f"metallib + probe built in {time.monotonic() - started:.0f} s "
         f"(-O -wmo, linked to {lib_dir}) — {binary}")
    return binary


# ---- K1: the core's own tests -----------------------------------------------

def core_tests(crate_dir, offline):
    env = bounded.child_env()
    env.pop("CARGO_TARGET_DIR", None)
    got = run(["cargo", "test", "--release"] + (["--offline"] if offline else [])
              + ["--test", "speed_x1000"], 1800, cwd=crate_dir, env=env)
    failed = [line.split()[1] for line in got["stdout"].splitlines()
              if line.startswith("test ") and line.endswith("FAILED")]
    summary = [line for line in got["stdout"].splitlines() if line.startswith("test result")]
    emit("K1", got["rc"] == 0, f"{crate_dir}: cargo test --test speed_x1000 rc {got['rc']} "
         f"in {got['seconds']:.0f} s · {summary[-1] if summary else 'no result line'}"
         + (f" · FAILED {failed}" if failed else "") + (" EXPIRED" if got["expired"] else ""))


# ---- F0, F1: the fixtures -----------------------------------------------------

def fixture(row, key):
    path, seconds = FIXTURES[key], int(key)
    WORK.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        run(["ffmpeg", "-nostdin", "-y", "-v", "error", "-f", "lavfi",
             "-i", "testsrc2=size=320x180:rate=30", "-f", "lavfi",
             "-i", "sine=frequency=200:sample_rate=48000", "-t", str(seconds),
             "-c:v", "h264_videotoolbox", "-b:v", "1M", "-c:a", "aac", "-ac", "2",
             "-b:a", "128k", path], 600)
    info = ffprobe_json(path, "format=duration:stream=codec_type,width,height")
    try:
        duration = float(info.get("format", {}).get("duration"))
    except (TypeError, ValueError):
        duration = None
    video = [s for s in info.get("streams", []) if s.get("codec_type") == "video"]
    size = (video[0].get("width"), video[0].get("height")) if video else None
    audio = path.exists() and has_audio(path)
    ok = (duration is not None and abs(duration - seconds) <= 0.1 and size == (320, 180)
          and audio)
    emit(row, ok, f"{path.name}: {duration} s, {size}, audio {audio}", True)
    return ok


# ---- U rows -------------------------------------------------------------------

def u_rows(binary):
    got, answer = probe(binary, ["ui", "--media", FIXTURES["180"]], 300)
    if not answer or answer.get("error"):
        detail = (answer or {}).get("error") or f"no ANSWER: rc {got['rc']} {got['stderr'][-300:]!r}"
        emit("U1", False, detail, True)
        emit("U2", False, detail, True)
        return
    limits = answer.get("limits", {})
    got_limits = (limits.get("min"), limits.get("max"), limits.get("audio_max"))
    sheet = answer.get("sheet_range")
    presets = answer.get("sheet_presets")
    ok = (got_limits == (0.1, 1000.0, 12.0) and sheet == [0.1, 1000.0]
          and presets == [0.25, 0.5, 1, 1.5, 2, 4, 10, 100])
    emit("U1", ok, f"limits {got_limits}; sheet range {sheet}; presets {presets}")
    wanted = {(1.0, True): None, (12.0, True): None, (12.0, False): None,
              (12.5, True): "Audio is silent above ×12",
              (12.5, False): "Audio is silent above ×12"}
    notes = {(n.get("rate"), n.get("keep_pitch")): n.get("note") for n in answer.get("notes", [])}
    ok = notes == wanted
    emit("U2", ok, "; ".join(f"×{r:g} {'k' if k else 'v'}: {notes.get((r, k))!r}"
                             for r, k in wanted))


# ---- E rows -------------------------------------------------------------------

def span_level(path, key, start, length=None):
    """`key` of astats' Overall over [start, start + length) — None when the
    span has no answer."""
    extra = ["-ss", f"{start}"] + (["-t", f"{length}"] if length is not None else [])
    value = astats(path, extra)["overall"].get(key)
    return value if isinstance(value, float) else None


def audio_end(path):
    streams = ffprobe_json(path, "stream=codec_type,duration").get("streams", [])
    for stream in streams:
        if stream.get("codec_type") == "audio":
            try:
                return float(stream.get("duration"))
            except (TypeError, ValueError):
                return None
    return None


def sound(path, start, length=None):
    rms = span_level(path, "RMS level dB", start, length)
    return rms is not None and rms >= -40, rms


def nothing_after(path):
    end = audio_end(path)
    if end is None or end <= 2.05:
        return True, f"audio ends at {end}"
    peak = span_level(path, "Peak level dB", 2.05)
    return peak is None or peak <= -80, f"peak after 2.05 s {peak}"


def e_rows(binary):
    OUT.mkdir(parents=True, exist_ok=True)
    for name, key, clips, first, after, whole in EXPORTS:
        file = OUT / f"{name}.mp4"
        got, answer = probe(binary, ["export", "--media", FIXTURES[key], "--clips", clips,
                                     "--file", file, "--deadline", DEADLINE], DEADLINE + 60)
        label = f"{clips} on {key} s"
        if not answer:
            emit(name, False, f"{label}: no ANSWER, rc {got['rc']}, expired {got['expired']} "
                 f"after {got['seconds']:.0f} s")
            continue
        outcome = answer.get("outcome")
        parts = [f"{label}: {outcome} in {answer.get('wall_s', 0):.1f} s"]
        ok = outcome == "success" and file.exists()
        if not ok and answer.get("error"):
            parts.append(f"error {answer['error']!r}")
        if ok and whole == "no audio":
            frames = ffprobe_json(file, "stream=codec_type,nb_frames").get("streams", [])
            video = [int(s.get("nb_frames") or 0) for s in frames if s.get("codec_type") == "video"]
            audio = has_audio(file)
            ok = bool(video) and video[0] >= 1 and not audio
            parts.append(f"video frames {video}, audio stream {audio}")
        if ok and whole == "sound":
            heard, rms = sound(file, 0)
            ok = heard and has_audio(file)
            parts.append(f"audio to {audio_end(file)} s, RMS {rms}")
        if ok and first == "sound":
            heard, rms = sound(file, 0, 2)
            ok = heard
            parts.append(f"RMS [0,2) {rms}")
        if ok and after == "sound":
            heard, rms = sound(file, 2.05)
            ok = heard
            parts.append(f"audio to {audio_end(file)} s, RMS after 2.05 s {rms}")
        if ok and after == "nothing":
            quiet, why = nothing_after(file)
            ok = quiet
            parts.append(why)
        emit(name, ok, " · ".join(parts))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    started = time.monotonic()
    named = MUTANTS[args.mutant][1] if args.mutant else None
    if args.mutant:
        lib_dir = mutant_core(args.mutant)
        probe_dir = WORK / f"probe-{args.mutant}"
        crate_dir = TREE / "core"
    else:
        lib_dir = head_core()
        probe_dir = WORK / "probe"
        crate_dir = ROOT / "core"
    if lib_dir:
        core_tests(crate_dir, offline=bool(args.mutant))
    # A mutant scored by K1 alone builds no probe and runs no export.
    exports = named is None or any(not n.startswith("K") for n in named)
    binary = build_probe(lib_dir, probe_dir) if lib_dir and exports else None
    have_fixtures = exports and fixture("F0", "180") and fixture("F1", "600")
    if binary and have_fixtures:
        u_rows(binary)
        e_rows(binary)
    elapsed = time.monotonic() - started
    (WORK / f"results{'-' + args.mutant if args.mutant else ''}.json").write_text(
        json.dumps(rows, indent=1, sort_keys=True))
    if args.mutant:
        if instrument or not lib_dir or any(n not in rows for n in named):
            print(f"mutant {args.mutant}: not performed — instrument rows {instrument} "
                  f"in {elapsed:.0f} s")
            return 2
        caught = all(not rows[n]["ok"] for n in named)
        print(f"mutant {args.mutant}: {'CAUGHT' if caught else 'SURVIVED'} — named rows "
              f"{ {n: rows[n]['ok'] for n in named} } in {elapsed:.0f} s")
        return 1 if caught else 0
    failed = [n for n, r in rows.items() if not r["ok"]]
    print(f"speed_limits_probe: {len(rows)} rows, failed {failed} in {elapsed:.0f} s")
    return 0 if not failed and binary and have_fixtures else 1


if __name__ == "__main__":
    sys.exit(main())
