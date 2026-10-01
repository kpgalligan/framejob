#!/usr/bin/env python3
"""Issue batch B52a — the ×1000 speed spike (#190 part 1 of 2).

Measures preview, export and audio at ×120 and ×1000 on an hour looped from
the recorder's own output, through the app's own `CompositionBuilder` /
`Exporter` code (`speed_probe.swift`, compiled over `app/Sources`) linked
against a SCRATCH core whose `SPEED_MAX` is 1000. Nothing records the
owner's screen; no app instance is launched and no MCP call is made. Every
child runs under `graphics_spike/bounded.py` (rule H): its own process group,
a hard wall-clock bound, and an expiry is the row's answer.

H0      host: model and CPU, macOS, load, other `MacOS/Reelcut` PIDs (load is
        repeated on every timed row).
B0      scratch core: `core/` and `graphic/` copied to work/speed_spike/tree/,
        HEAD's one `SPEED_MAX` line (matched by pattern, whatever its value)
        replaced by `= 1000.0;`, `diff -ru` printed (exactly that line, or no
        line at all when HEAD already says 1000.0, as it has since B52b),
        `cargo build --release --offline` (bound 1800 s).
B1      metallib + probe build (`-O -whole-module-optimization`, bound 1800 s).
S.<src> ffprobe facts: `loop` (the longest real recording looped to 3600 s
        with `-c copy`, with its own microphone file) and `loopv` (its video
        stream alone, made only when `loop` has audio).
T<r>.<src>  the timeline at ×r: every clip's speed reads back r (±1e-9).
P<r>.<src>  the preview: the app's player and item over the metering build,
        played at ×1 wall time, polled every ≤ 5 ms (bound timeline + 120 s).
E<r>.<src>  an h264 export (bound 900 s for r ≤ 10, 7200 s above), then
        ffprobe, blackdetect and astats on the file.
        `loop` runs r ∈ {1, 10, 120, 1000} (1 and 10 CONTROLS), `loopv`
        r ∈ {120, 1000}.
A.<fixture>.<algo>.<r>  2 s of output from r × 2 s of source through the
        app's `fill` and `audioParameters`, read by a float mix output;
        astats, zero-crossing frequency, spectral flatness.
L.<fixture>.<algo>  the largest swept r with every swept r' ≤ r working.
X.<k|v>.<r>  the product path: speech at ×r, keep pitch (k) or not (v),
        trimmed to 2 s, exported `audio_m4a`.
V       the verdicts at ×120 and ×1000, judged on `loopv` when it exists.
C0      `git status --porcelain` of the product directories, before = after.

    python3 tools/proof/speed_spike/speed_spike.py --remeasure
        [--rows H,B,S,T,P,E,A,X,V,C] [--loop-source PATH] [--stock-core]

**A historical measurement, not a check.** It builds two hour-long movies
(~18 GB) and a full run takes about 95 minutes. Run it only to RE-MEASURE the
speed or audio ceilings: work on #212 (the loudness-pass stall) or a change
to `SPEED_MAX` / `AUDIO_SPEED_MAX`. A change to speed code in general is
`speed_limits_probe.py`'s to check, not this. Without `--remeasure` it runs
nothing and exits 2 (not performed).

`--rows` names the families SCORED; their prerequisites are made regardless.
Exit 0 every row answered, 1 an instrument failed. `--stock-core` is the
mutant (rule R): no scratch tree, the probe linked to `core/target/release`
(HEAD) in its own folder, its rows in `results-stock-core.json`; exit 1
caught (T120/T1000 read back HEAD's `SPEED_MAX`), 0 survived, 2 not
performed. When HEAD's `SPEED_MAX` is already ≥ 1000 (since B52b, #190) the
stock core is no mutant: the mode says so and exits 2 before building
anything.
"""

import argparse
import json
import math
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
import bounded  # noqa: E402

WORK = ROOT / "tools/proof/work/speed_spike"
TREE = WORK / "tree"
FIXTURES = WORK / "fixtures"
OUT = WORK / "out"
PROBE_SOURCE = ROOT / "tools/proof/speed_spike/speed_probe.swift"
RECORDINGS = Path.home() / "Movies/Reelcut Recordings"
SPEECH_AIFF = ROOT / "tools/proof/media/speech.aiff"
HOUR = 3600
SPEED_PATTERN = re.compile(r"^pub\(crate\) const SPEED_MAX: f64 = ([0-9.]+);$", re.MULTILINE)
SPEED_SCRATCH = "pub(crate) const SPEED_MAX: f64 = 1000.0;"
LOOP_RATES = [1, 10, 120, 1000]
LOOPV_RATES = [120, 1000]
SWEEP = [1, 2, 4, 8, 16, 24, 31, 32, 33, 40, 48, 64, 120, 1000]
ALGOS = ["spectral", "time_domain", "off"]
X_RATES = [1, 32, 33, 120, 1000]
C0_PATHS = ["app", "core", "graphic", "agent", "designs", "docs", "Makefile", "project.yml"]
FAMILIES = "HBSTPEAXVC"

results = {"rows": {}, "started": time.strftime("%Y-%m-%d %H:%M:%S")}
instrument_failures = []


def save():
    WORK.mkdir(parents=True, exist_ok=True)
    name = "results-stock-core.json" if results.get("stock_core") else "results.json"
    (WORK / name).write_text(json.dumps(results, indent=1, sort_keys=True, default=str))


def emit(name, status, detail="", data=None, instrument=False):
    """One row: printed, kept in results.json. `instrument` marks a failure
    of the instrument rather than an answer."""
    results["rows"][name] = {"status": status, "detail": detail, "data": data}
    if instrument:
        instrument_failures.append(name)
    print(f"  {status:<7} {name}" + (f"  {detail}" if detail else ""), flush=True)
    save()


def run(argv, seconds, cwd=None, env=None):
    return bounded.run([str(a) for a in argv], seconds, cwd=cwd, env=env)


def load():
    return run(["sysctl", "-n", "vm.loadavg"], 30)["stdout"].strip()


def fmt(value, digits=3):
    if value is None:
        return "null"
    if isinstance(value, float):
        return f"{value:.{digits}f}"
    return str(value)


# ---- C0 / H0 ------------------------------------------------------------------

def git_status():
    got = run(["git", "status", "--porcelain", "--"] + C0_PATHS, 60, cwd=ROOT)
    return got["stdout"]


def host_row(score):
    model = run(["sysctl", "-n", "hw.model", "machdep.cpu.brand_string"], 30)["stdout"].split("\n")
    macos = run(["sw_vers", "-productVersion"], 30)["stdout"].strip()
    pids = run(["pgrep", "-f", "MacOS/Reelcut"], 30)["stdout"].split()
    data = {"model": model[0].strip() if model else "", "cpu": model[1].strip() if len(model) > 1 else "",
            "macos": macos, "load": load(), "other_reelcut_pids": len(pids)}
    results["host"] = data
    if score:
        emit("H0", "ok", f"{data['model']} · {data['cpu']} · macOS {macos} · load {data['load']} · "
             f"other MacOS/Reelcut PIDs {len(pids)}", data)


# ---- sources ------------------------------------------------------------------

def ffprobe_json(path, entries, seconds=120):
    got = run(["ffprobe", "-v", "error", "-show_entries", entries, "-of", "json", path], seconds)
    try:
        return json.loads(got["stdout"])
    except ValueError:
        return {}


def duration_of(path):
    fmt_ = ffprobe_json(path, "format=duration").get("format", {})
    try:
        return float(fmt_.get("duration"))
    except (TypeError, ValueError):
        return None


def has_audio(path):
    streams = ffprobe_json(path, "stream=codec_type").get("streams", [])
    return any(s.get("codec_type") == "audio" for s in streams)


def stamp(path):
    st = Path(path).stat()
    return {"path": str(path), "size": st.st_size, "mtime": int(st.st_mtime)}


def made_before(out, sidecar, recipe):
    """True when `out` exists and `sidecar` records this exact recipe."""
    if not out.exists() or not sidecar.exists():
        return False
    try:
        return json.loads(sidecar.read_text()) == recipe
    except ValueError:
        return False


def pick_recording(override):
    if override:
        path = Path(override).expanduser()
        return (path, duration_of(path)) if path.exists() else (None, None)
    best = (None, None)
    for path in sorted(RECORDINGS.glob("*.mov")) if RECORDINGS.is_dir() else []:
        seconds = duration_of(path)
        if seconds is not None and (best[1] is None or seconds > best[1]):
            best = (path, seconds)
    return best


def make_sources(override):
    """`loop` (and `loopv` when `loop` has audio): {name: {path, made_from, …}},
    or None with the instrument failure emitted."""
    WORK.mkdir(parents=True, exist_ok=True)
    mov, seconds = pick_recording(override)
    loop = WORK / "loop_hour.mov"
    sidecar = WORK / "loop_hour.json"
    sources = {}
    if mov is not None and seconds:
        mic = mov.with_name(f"{mov.stem} (Microphone).m4a")
        mic = mic if mic.exists() else None
        k = math.ceil(HOUR / seconds) - 1
        recipe = {"kind": "loop", "movie": stamp(mov), "mic": stamp(mic) if mic else None, "k": k}
        argv = ["ffmpeg", "-nostdin", "-y", "-v", "error", "-stream_loop", k, "-i", mov]
        if mic:
            argv += ["-stream_loop", k, "-i", mic]
        argv += ["-map", "0:v:0"] + (["-map", "1:a:0"] if mic else ["-map", "0:a:0?"])
        argv += ["-c", "copy", "-t", HOUR, loop]
        made_from = (f"{mov.name} ({seconds:.3f} s) looped K={k} with -c copy"
                     + (f", muxed with {mic.name}" if mic else ", its own audio if any"))
    else:
        recipe = {"kind": "synthetic"}
        argv = ["ffmpeg", "-nostdin", "-y", "-v", "error",
                "-f", "lavfi", "-i", f"testsrc2=size=2560x1440:rate=60:duration={HOUR}",
                "-f", "lavfi", "-i", f"sine=frequency=440:duration={HOUR}",
                "-c:v", "hevc_videotoolbox", "-tag:v", "hvc1", "-g", "120",
                "-c:a", "aac", "-ac", "2", loop]
        made_from = "SYNTHETIC: no recording on disk — testsrc2 2560x1440 60 fps + sine 440 Hz"
    if made_before(loop, sidecar, recipe):
        print(f"  source loop: up to date — {loop}", flush=True)
    else:
        started = time.monotonic()
        got = run(argv, 1800)
        if got["rc"] != 0 or got["expired"] or not loop.exists():
            emit("S.loop", "FAIL", f"ffmpeg rc {got['rc']} expired {got['expired']}: "
                 f"{got['stderr'][-400:]}", instrument=True)
            return None
        sidecar.write_text(json.dumps(recipe))
        print(f"  source loop: made in {time.monotonic() - started:.0f} s — {loop}", flush=True)
    sources["loop"] = {"path": loop, "made_from": made_from}
    if has_audio(loop):
        loopv = WORK / "loop_hour_v.mov"
        vsidecar = WORK / "loop_hour_v.json"
        vrecipe = {"from": stamp(loop)}
        if made_before(loopv, vsidecar, vrecipe):
            print(f"  source loopv: up to date — {loopv}", flush=True)
        else:
            got = run(["ffmpeg", "-nostdin", "-y", "-v", "error", "-i", loop, "-map", "0:v:0",
                       "-c", "copy", loopv], 1800)
            if got["rc"] != 0 or got["expired"] or not loopv.exists():
                emit("S.loopv", "FAIL", f"ffmpeg rc {got['rc']}: {got['stderr'][-400:]}",
                     instrument=True)
                return None
            vsidecar.write_text(json.dumps(vrecipe))
        sources["loopv"] = {"path": loopv, "made_from": "loop_hour.mov's video stream, -map 0:v:0 -c copy"}
    return sources


def source_row(name, source, score):
    path = source["path"]
    info = ffprobe_json(path, "format=duration,size:stream=index,codec_type,codec_name,"
                        "codec_tag_string,width,height,r_frame_rate,avg_frame_rate,nb_frames,"
                        "duration,sample_rate,channels", 300)
    packets = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                   "packet=flags", "-of", "csv=p=0", path], 900)
    lines = [line for line in packets["stdout"].splitlines() if line.strip()]
    keyframes = sum(1 for line in lines if "K" in line)
    fmt_ = info.get("format", {})
    streams = info.get("streams", [])
    video = next((s for s in streams if s.get("codec_type") == "video"), {})
    audio = next((s for s in streams if s.get("codec_type") == "audio"), None)
    data = {"path": str(path), "made_from": source["made_from"],
            "duration": float(fmt_.get("duration", "nan")), "bytes": int(fmt_.get("size", 0)),
            "codec": video.get("codec_name"), "tag": video.get("codec_tag_string"),
            "size": f"{video.get('width')}x{video.get('height')}",
            "r_frame_rate": video.get("r_frame_rate"), "avg_frame_rate": video.get("avg_frame_rate"),
            "packets": len(lines), "keyframes": keyframes,
            "audio": ({"codec": audio.get("codec_name"), "rate": audio.get("sample_rate"),
                       "channels": audio.get("channels"), "duration": audio.get("duration")}
                      if audio else None)}
    source["duration"] = data["duration"]
    source["facts"] = data
    ok = bool(lines) and math.isfinite(data["duration"]) and not packets["expired"]
    if score:
        audio_text = (f"audio {audio.get('codec_name')} {audio.get('sample_rate')} Hz "
                      f"{audio.get('channels')} ch {audio.get('duration')} s" if audio else "audio none")
        emit(f"S.{name}", "ok" if ok else "FAIL",
             f"{data['duration']:.3f} s · {data['codec']}/{data['tag']} {data['size']} · "
             f"r {data['r_frame_rate']} avg {data['avg_frame_rate']} · {data['packets']} packets, "
             f"{keyframes} keyframes · {data['bytes']} bytes · {audio_text} · made from: "
             f"{source['made_from']}", data, instrument=not ok)
    return ok


# ---- fixtures -----------------------------------------------------------------

def make_fixtures():
    FIXTURES.mkdir(parents=True, exist_ok=True)
    speech = SPEECH_AIFF
    if not speech.exists():
        said = run(["say", "-o", speech, "The quick brown fox jumps over the lazy dog. "
                    "Pack my box with five dozen liquor jugs."], 120)
        if said["rc"] != 0:
            emit("F.speech", "FAIL", f"say rc {said['rc']}", instrument=True)
            return None
    made = {
        "sine": (FIXTURES / "sine_2100.m4a",
                 ["-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000:duration=2100"]),
        "speech": (FIXTURES / "speech_2100.m4a",
                   ["-stream_loop", "400", "-i", speech, "-t", "2100", "-ar", "48000"]),
        "noise": (FIXTURES / "noise_10.m4a",
                  ["-f", "lavfi", "-i",
                   "anoisesrc=color=white:sample_rate=48000:duration=10:amplitude=0.25"]),
    }
    paths = {}
    for name, (path, inputs) in made.items():
        if not path.exists():
            got = run(["ffmpeg", "-nostdin", "-y", "-v", "error"] + inputs
                      + ["-ac", "2", "-c:a", "aac", "-b:a", "128k", path], 600)
            if got["rc"] != 0 or not path.exists():
                emit(f"F.{name}", "FAIL", f"ffmpeg rc {got['rc']}: {got['stderr'][-300:]}",
                     instrument=True)
                return None
        paths[name] = path
        print(f"  fixture {name}: {path.name} {duration_of(path):.3f} s", flush=True)
    return paths


# ---- the scratch core and the probe --------------------------------------------

def sync_tree(source, target, edits=None):
    """`target` made a copy of `source`, writing only files whose bytes differ
    (so cargo's fingerprints survive a rerun). `edits` maps a relative path to
    replacement bytes."""
    edits = edits or {}
    wanted = {}
    for path in source.rglob("*"):
        if path.is_file():
            rel = path.relative_to(source)
            wanted[rel] = edits.get(str(rel), path.read_bytes())
    if target.exists():
        for path in sorted(target.rglob("*"), reverse=True):
            rel = path.relative_to(target)
            if path.is_file() and rel not in wanted:
                path.unlink()
    for rel, data in wanted.items():
        dest = target / rel
        if dest.exists() and dest.read_bytes() == data:
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)


def head_speed_lines():
    """HEAD's `edit_clip_timing.rs` and every match of its `SPEED_MAX` line."""
    text = (ROOT / "core/src/edit_clip_timing.rs").read_text()
    return text, list(SPEED_PATTERN.finditer(text))


def scratch_core(score):
    for crate in ("core", "graphic"):
        (TREE / crate).mkdir(parents=True, exist_ok=True)
        for name in ("Cargo.toml", "Cargo.lock"):
            data = (ROOT / crate / name).read_bytes()
            dest = TREE / crate / name
            if not dest.exists() or dest.read_bytes() != data:
                dest.write_bytes(data)
    text, found = head_speed_lines()
    if len(found) != 1:
        emit("B0", "FAIL", f"`{SPEED_PATTERN.pattern}` matches {len(found)} times in HEAD's "
             "edit_clip_timing.rs, not once", instrument=True)
        return None
    head_line = found[0].group(0)
    edits = {"edit_clip_timing.rs": SPEED_PATTERN.sub(SPEED_SCRATCH, text, count=1).encode()}
    sync_tree(ROOT / "core/src", TREE / "core/src", edits)
    sync_tree(ROOT / "core/include", TREE / "core/include")
    sync_tree(ROOT / "graphic/src", TREE / "graphic/src")
    diff = run(["diff", "-ru", ROOT / "core/src", TREE / "core/src"], 60)
    print(diff["stdout"].rstrip(), flush=True)
    changed = [line for line in diff["stdout"].splitlines()
               if line[:1] in "+-" and not line.startswith(("+++", "---"))]
    unchanged = head_line == SPEED_SCRATCH
    one_line = changed == ([] if unchanged else ["-" + head_line, "+" + SPEED_SCRATCH])
    env = bounded.child_env()
    env.pop("CARGO_TARGET_DIR", None)
    built = run(["cargo", "build", "--release", "--offline"], 1800, cwd=TREE / "core", env=env)
    lib = TREE / "core/target/release/libreelcut_core.a"
    ok = one_line and built["rc"] == 0 and lib.exists()
    which = ("none expected, HEAD already says 1000.0" if unchanged
             else f"exactly `{head_line}` → 1000.0")
    detail = (f"diff: {len(changed)} changed lines, {which}: {one_line} · "
              f"cargo rc {built['rc']} in {built['seconds']:.0f} s"
              + (" EXPIRED" if built["expired"] else ""))
    if not ok and built["rc"] != 0:
        detail += f" · {built['stderr'][-400:]}"
    emit("B0", "ok" if ok else "FAIL", detail,
         {"diff": diff["stdout"], "cargo_rc": built["rc"], "cargo_s": built["seconds"]},
         instrument=not ok)
    return lib.parent if ok else None


def build_probe(lib_dir, probe_dir, score):
    """`export_cancel_proof.build_probe`'s build (`export_cancel_proof.py:217-270`):
    the app's `Fonts`, `Blank.mp4` and a `default.metallib` of `Compositor.metal`
    beside the binary, every `app/Sources` file but `main.swift`, the probe as
    `main.swift` — plus `-O -whole-module-optimization` (Release optimises) and
    `-L <lib_dir>`. Rebuilt only when stale."""
    probe_dir.mkdir(parents=True, exist_ok=True)
    binary = probe_dir / "speed_probe"
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
            emit("B1", "FAIL", f"the shader did not build: {step['stderr'][-400:]}", instrument=True)
            return None
    swift = sorted(p for p in (ROOT / "app/Sources").glob("*.swift") if p.name != "main.swift")
    lib = lib_dir / "libreelcut_core.a"
    headers = [ROOT / "app/Bridging/Reelcut-Bridging-Header.h", ROOT / "core/include/reelcut_core.h"]
    if binary.exists() and all(p.stat().st_mtime < binary.stat().st_mtime
                               for p in swift + [entry, lib] + headers):
        emit("B1", "ok", f"probe up to date — {binary} (linked to {lib_dir})")
        return binary
    sdk = run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
    built = run(["swiftc", "-D", "REELCUT_DEV_TOOLS", "-O", "-whole-module-optimization",
                 "-sdk", sdk, "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
                 "-import-objc-header", ROOT / "app/Bridging/Reelcut-Bridging-Header.h",
                 "-L", lib_dir, "-lreelcut_core"] + swift + [entry, "-o", binary], 1800)
    if built["rc"] != 0 or not binary.exists():
        errors = [line for line in built["stderr"].splitlines() if ": error:" in line]
        emit("B1", "FAIL", f"swiftc rc {built['rc']} expired {built['expired']}: "
             f"{(errors or built['stderr'].splitlines()[-4:] or ['(no output)'])[:6]}",
             instrument=True)
        return None
    emit("B1", "ok", f"metallib + probe built in {time.monotonic() - started:.0f} s "
         f"(-O -wmo, linked to {lib_dir}) — {binary}", {"seconds": time.monotonic() - started})
    return binary


def probe(binary, args, seconds):
    """(the bounded run, the ANSWER object or None)."""
    got = run([binary] + args, seconds)
    answer = None
    for line in got["stdout"].splitlines():
        if line.startswith("ANSWER "):
            try:
                answer = json.loads(line[len("ANSWER "):])
            except ValueError:
                answer = None
    return got, answer


def no_answer(got):
    return (f"no ANSWER: rc {got['rc']} after {got['seconds']:.1f} s; "
            f"stderr {got['stderr'][-300:]!r}")


# ---- analysis -----------------------------------------------------------------

def astats(path, extra=None):
    """{'overall': {...}, 'channels': {1: {...}}} from ffmpeg's astats."""
    got = run(["ffmpeg", "-nostdin", "-v", "info", "-i", path] + (extra or [])
              + ["-af", "astats", "-f", "null", "-"], 600)
    sections = {"overall": {}, "channels": {}}
    current = None
    for line in got["stderr"].splitlines():
        if "Parsed_astats" not in line:
            continue
        body = line.split("] ", 1)[-1].strip()
        if body.startswith("Channel:"):
            current = sections["channels"].setdefault(int(body.split(":")[1]), {})
            continue
        if body == "Overall":
            current = sections["overall"]
            continue
        if current is not None and ":" in body:
            key, value = body.split(":", 1)
            try:
                current[key.strip()] = float(value.strip())
            except ValueError:
                current[key.strip()] = value.strip()
    return sections


def flatness(path):
    got = run(["ffmpeg", "-nostdin", "-v", "info", "-i", path, "-af",
               "aspectralstats=measure=flatness,ametadata=mode=print", "-f", "null", "-"], 600)
    values = []
    for match in re.finditer(r"lavfi\.aspectralstats\.1\.flatness=(\S+)", got["stderr"]):
        try:
            value = float(match.group(1))
        except ValueError:
            continue
        if math.isfinite(value):
            values.append(value)
    return sum(values) / len(values) if values else None


def audio_numbers(path):
    stats = astats(path)
    overall = stats["overall"]
    channel = stats["channels"].get(1, {})
    zcr = channel.get("Zero crossings rate")
    return {"rms_db": overall.get("RMS level dB"), "peak_db": overall.get("Peak level dB"),
            "freq_hz": zcr * 48000 / 2 if isinstance(zcr, float) else None,
            "flatness": flatness(path)}


def finite_number(value):
    return isinstance(value, (int, float)) and math.isfinite(value)


# ---- T / P / E ------------------------------------------------------------------

def timeline_args(path, rate, passes, trim, keep_pitch=None):
    args = ["--media", path, "--rate", str(rate), "--passes", str(passes),
            "--trim-seconds", str(trim)]
    if keep_pitch is not None:
        args += ["--keep-pitch", "true" if keep_pitch else "false"]
    return args


def shape(rate, source_duration):
    if rate <= 10:
        return 1, 30
    return math.ceil(30 * rate / source_duration), 0


def t_row(binary, name, src, source, rate, score):
    passes, trim = shape(rate, source["duration"])
    got, answer = probe(binary, ["timeline"] + timeline_args(source["path"], rate, passes, trim), 300)
    row = f"T{rate}.{name}"
    if answer is None:
        emit(row, "FAIL", no_answer(got), instrument=True)
        return None
    timeline = answer.get("timeline") or {}
    clips = timeline.get("clips", [])
    speeds = sorted({c["speed"] for c in clips})
    ok = (answer.get("error") is None and bool(clips)
          and all(abs(c["speed"] - rate) <= 1e-9 for c in clips))
    if score:
        emit(row, "ok" if ok else "FAIL",
             f"{len(clips)} clips ({passes} passes, trim {trim} s), speeds read back {speeds}, "
             f"duration {fmt(timeline.get('duration_s'))} s, canvas {timeline.get('canvas_width')}x"
             f"{timeline.get('canvas_height')} @ {timeline.get('canvas_fps')}, error "
             f"{answer.get('error')}", answer)
    return answer if ok else None


def p_row(binary, name, source, rate, timeline):
    passes, trim = shape(rate, source["duration"])
    duration = timeline["timeline"]["duration_s"]
    deadline = duration + 60
    before = load()
    got, answer = probe(binary, ["preview"] + timeline_args(source["path"], rate, passes, trim)
                        + ["--deadline", f"{deadline:.3f}"], duration + 120)
    row = f"P{rate}.{name}"
    if answer is None and got["expired"]:
        answer = {"expired": True, "reached_end": False, "error": "bound expired",
                  "delivered": 0, "item_status": "unknown"}
    if answer is None:
        emit(row, "FAIL", no_answer(got), instrument=True)
        return None
    delivered = answer.get("delivered") or 0
    ratio = (answer.get("black", 0) / delivered) if delivered else None
    answer["black_ratio"] = ratio
    answer["load_before"] = before
    answer["probe_s"] = got["seconds"]
    emit(row, "answer",
         f"build {fmt(answer.get('build_s'))} s · {answer.get('item_status')} · first frame "
         f"{fmt(answer.get('first_frame_s'))} s · reached_end {answer.get('reached_end')} · wall to end "
         f"{fmt(answer.get('wall_to_end_s'))} s (timeline {duration:.3f} s) · delivered {delivered} of "
         f"expected {fmt(answer.get('expected'), 1)} · black {answer.get('black')} (ratio "
         f"{fmt(ratio)}) · longest black run {fmt(answer.get('longest_black_run_s'))} s · longest stall "
         f"{fmt(answer.get('longest_stall_s'))} s · waiting entries {answer.get('waiting_entries')} · "
         f"meter peak {fmt(answer.get('meter_peak_db'), 1)} dB over {answer.get('meter_tracks')} "
         f"tracks · expired {answer.get('expired')} · error {answer.get('error')} · item_error "
         f"{answer.get('item_error')} · load {before}", answer)
    return answer


def e_row(binary, name, source, rate, timeline):
    passes, trim = shape(rate, source["duration"])
    bound = 900 if rate <= 10 else 7200
    OUT.mkdir(parents=True, exist_ok=True)
    out = OUT / f"E{rate}.{name}.mp4"
    before = load()
    got, answer = probe(binary, ["export"] + timeline_args(source["path"], rate, passes, trim)
                        + ["--preset", "h264", "--file", out, "--deadline", str(bound - 60)], bound)
    row = f"E{rate}.{name}"
    if answer is None and got["expired"]:
        answer = {"outcome": "deadline", "expired": True, "wall_s": got["seconds"],
                  "error": "bound expired"}
    if answer is None:
        emit(row, "FAIL", no_answer(got), instrument=True)
        return None
    answer["load_before"] = before
    file_facts = {}
    if answer.get("outcome") == "success" and out.exists():
        info = ffprobe_json(out, "format=duration:stream=codec_type,duration,nb_frames", 120)
        video = next((s for s in info.get("streams", []) if s.get("codec_type") == "video"), {})
        audio = next((s for s in info.get("streams", []) if s.get("codec_type") == "audio"), None)
        black = run(["ffmpeg", "-nostdin", "-i", out, "-vf", "blackdetect=d=0.1:pix_th=0.02",
                     "-an", "-f", "null", "-"], 900)
        spans = [float(v) for v in re.findall(r"black_duration:([0-9.]+)", black["stderr"])]
        file_facts = {"format_duration": float(info.get("format", {}).get("duration", "nan")),
                      "video_duration": float(video.get("duration", "nan")),
                      "video_frames": video.get("nb_frames"),
                      "audio_duration": float(audio["duration"]) if audio and audio.get("duration") else None,
                      "black_s": sum(spans), "black_spans": len(spans)}
        if audio:
            stats = astats(out, ["-vn"])["overall"]
            file_facts["audio_rms_db"] = stats.get("RMS level dB")
            file_facts["audio_peak_db"] = stats.get("Peak level dB")
    answer["file_facts"] = file_facts
    phases = "; ".join(f"{p[0]} @ {p[1]:.1f} s" for p in answer.get("phases") or [])
    emit(row, "answer",
         f"{answer.get('outcome')} in {fmt(answer.get('wall_s'), 1)} s (timeline "
         f"{timeline['timeline']['duration_s']:.3f} s) · phases [{phases}] · file {file_facts} · "
         f"error {answer.get('error')} · load {before}", answer)
    return answer


# ---- A / L / X --------------------------------------------------------------------

def a_rows(binary, fixtures):
    OUT.mkdir(parents=True, exist_ok=True)
    table = {}
    plan = [(f, a, r) for f in ("sine", "speech") for a in ALGOS for r in SWEEP]
    plan.append(("noise", "spectral", 1))
    for fixture, algo, rate in plan:
        wav = OUT / f"A.{fixture}.{algo}.{rate}.wav"
        before = load()
        got, answer = probe(binary, ["audio", "--fixture", fixtures[fixture], "--algorithm", algo,
                                     "--rate", str(rate), "--wav", wav], 300)
        row = f"A.{fixture}.{algo}.{rate}"
        if answer is None and got["expired"]:
            answer = {"reader_status": "expired", "frames": 0, "error": "bound expired"}
        if answer is None:
            emit(row, "FAIL", no_answer(got), instrument=True)
            continue
        numbers = audio_numbers(wav) if wav.exists() and answer.get("frames") else {}
        answer.update(numbers)
        answer["load_before"] = before
        table[(fixture, algo, rate)] = answer
        label = "CONTROL " if fixture == "noise" else ""
        emit(row, "answer",
             f"{label}reader {answer.get('reader_status')} · frames {answer.get('frames')} of "
             f"{answer.get('expected_frames')} (read {answer.get('frames_read')}) · wall {fmt(answer.get('wall_s'))} s · RMS "
             f"{fmt(answer.get('rms_db'), 2)} dB · peak {fmt(answer.get('peak_db'), 2)} dB · freq "
             f"{fmt(answer.get('freq_hz'), 1)} Hz · flatness {fmt(answer.get('flatness'), 4)} · error "
             f"{answer.get('error')} · load {before}", answer)
    return table


def works(table, fixture, algo, rate):
    row = table.get((fixture, algo, rate))
    ref = table.get((fixture, algo, 1))
    if row is None or ref is None:
        return False, "not measured"
    if row.get("reader_status") != "completed":
        return False, f"reader {row.get('reader_status')}"
    if abs((row.get("frames") or 0) - 96000) > 960:
        return False, f"frames {row.get('frames')}"
    if not (finite_number(row.get("rms_db")) and finite_number(ref.get("rms_db"))):
        return False, f"RMS {row.get('rms_db')} vs r=1 {ref.get('rms_db')}"
    if abs(row["rms_db"] - ref["rms_db"]) > 6:
        return False, f"RMS {row['rms_db']:.2f} vs r=1 {ref['rms_db']:.2f}"
    if fixture == "sine" and algo in ("spectral", "time_domain"):
        if not (finite_number(row.get("freq_hz")) and finite_number(ref.get("freq_hz"))):
            return False, "no frequency"
        if abs(row["freq_hz"] - ref["freq_hz"]) > 0.05 * ref["freq_hz"]:
            return False, f"freq {row['freq_hz']:.1f} vs r=1 {ref['freq_hz']:.1f} Hz"
    return True, "works"


def l_rows(table):
    limits = {}
    for fixture in ("sine", "speech"):
        for algo in ALGOS:
            limit, why = None, ""
            for rate in SWEEP:
                good, reason = works(table, fixture, algo, rate)
                if not good:
                    why = f"first failure ×{rate}: {reason}"
                    break
                limit = rate
            limits[(fixture, algo)] = limit
            label = ("CONTROL (Nyquist: varispeed puts the 1 kHz tone at 1000·r Hz, 24 kHz at ×24) "
                     if (fixture, algo) == ("sine", "off") else "")
            emit(f"L.{fixture}.{algo}", "answer",
                 f"{label}L = {limit if limit is not None else 'none'}"
                 + (f" ({why})" if why else " (every swept rate works)"),
                 {"limit": limit, "why": why})
    sdk = run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
    header = (Path(sdk) / "System/Library/Frameworks/AVFoundation.framework/Versions/A/Headers"
              / "AVAudioProcessingSettings.h")
    grep = run(["grep", "-n", "1/32", header], 30)
    print(f"  grep -n \"1/32\" {header}\n" + grep["stdout"].rstrip(), flush=True)
    results["sdk_header_grep"] = {"header": str(header), "lines": grep["stdout"]}
    save()
    return limits


def x_rows(binary, fixtures):
    OUT.mkdir(parents=True, exist_ok=True)
    table = {}
    for keep in (True, False):
        for rate in X_RATES:
            tag = "k" if keep else "v"
            out = OUT / f"X.{tag}.{rate}.m4a"
            before = load()
            got, answer = probe(binary, ["export"] + timeline_args(fixtures["speech"], rate, 1, 2, keep)
                                + ["--preset", "audio_m4a", "--file", out, "--deadline", "540"], 600)
            row = f"X.{tag}.{rate}"
            if answer is None and got["expired"]:
                answer = {"outcome": "deadline", "error": "bound expired"}
            if answer is None:
                emit(row, "FAIL", no_answer(got), instrument=True)
                continue
            if answer.get("outcome") == "success" and out.exists():
                answer["file_duration"] = duration_of(out)
                answer.update(audio_numbers(out))
            answer["load_before"] = before
            table[(tag, rate)] = answer
            label = "CONTROL " if rate == 1 else ""
            emit(row, "answer",
                 f"{label}{answer.get('outcome')} in {fmt(answer.get('wall_s'), 1)} s · file "
                 f"{fmt(answer.get('file_duration'))} s · RMS {fmt(answer.get('rms_db'), 2)} dB · peak "
                 f"{fmt(answer.get('peak_db'), 2)} dB · flatness {fmt(answer.get('flatness'), 4)} · "
                 f"clip speed {[c['speed'] for c in (answer.get('timeline') or {}).get('clips', [])]} · "
                 f"error {answer.get('error')} · load {before}", answer)
    return table


# ---- V ------------------------------------------------------------------------

def preview_verdict(row, black_measurable):
    if row is None:
        return ["not measured"]
    why = []
    if row.get("item_status") == "failed" or row.get("error"):
        why.append(f"item failed or error: {row.get('item_status')} / {row.get('error')}")
    if not row.get("reached_end"):
        why.append(f"hang: reached_end false (expired {row.get('expired')})")
    if (row.get("longest_stall_s") or 0) >= 5:
        why.append(f"longest stall {row['longest_stall_s']:.2f} s ≥ 5")
    if not row.get("delivered"):
        why.append("delivered 0")
    if black_measurable:
        ratio = row.get("black_ratio")
        if (ratio is not None and ratio >= 0.10) or (row.get("longest_black_run_s") or 0) >= 0.5:
            why.append(f"black {row.get('black')}/{row.get('delivered')} (ratio {fmt(ratio)}), "
                       f"longest run {fmt(row.get('longest_black_run_s'))} s")
    return why


def export_verdict(row, timeline, black_measurable):
    if row is None:
        return ["not measured"]
    why = []
    if row.get("outcome") != "success" or row.get("expired"):
        why.append(f"outcome {row.get('outcome')} ({row.get('error')})")
        return why
    facts = row.get("file_facts") or {}
    fps = timeline["timeline"]["canvas_fps"]
    frame = fps[1] / fps[0] if fps and fps[0] else 1 / 30
    video = facts.get("video_duration")
    wanted = timeline["timeline"]["duration_s"]
    if not finite_number(video) or abs(video - wanted) > 2 * frame:
        why.append(f"video stream {fmt(video)} s vs timeline {wanted:.3f} s (2 frames = {2 * frame:.3f} s)")
    if black_measurable and (facts.get("black_s") or 0) >= 0.5:
        why.append(f"black {facts.get('black_s'):.2f} s")
    return why


def v_rows(sources, timelines, previews, exports):
    judged = "loopv" if "loopv" in sources else "loop"
    p1 = previews.get(("loop", 1))
    e1 = exports.get(("loop", 1))
    p_black = p1 is not None and p1.get("black") == 0
    e_black = e1 is not None and (e1.get("file_facts") or {}).get("black_s") == 0
    if not p_black:
        print("  preview black not measurable on this source (loop's P1 black ≠ 0 or unmeasured)")
    if not e_black:
        print("  export black not measurable on this source (loop's E1 black ≠ 0 or unmeasured)")
    stop = []
    verdicts = {}
    for rate in (120, 1000):
        for kind in ("preview", "export"):
            def judge(src):
                if kind == "preview":
                    return preview_verdict(previews.get((src, rate)), p_black)
                timeline = timelines.get((src, rate))
                if timeline is None:
                    return ["not measured (T failed)"]
                return export_verdict(exports.get((src, rate)), timeline, e_black)
            why = judge(judged)
            text = "copes" if not why else f"cannot cope ({'; '.join(why)})"
            if why:
                stop.append(f"×{rate} {kind} on {judged}: {'; '.join(why)}")
            detail = f"{kind}: {text}"
            if judged == "loopv":
                audio_why = judge("loop")
                detail += ("\n           with audio (loop): "
                           + ("copes" if not audio_why else f"cannot cope ({'; '.join(audio_why)})"))
            verdicts[f"{rate}.{kind}"] = {"judged_on": judged, "why": why}
            emit(f"V{rate}.{kind}", "answer", detail, verdicts[f"{rate}.{kind}"])
            print(f"V {rate} {detail}", flush=True)
    results["verdict"] = {"stop": stop, "judged_on": judged}
    print(("  VERDICT: STOP — " + " | ".join(stop)) if stop else
          "  VERDICT: preview and export cope at ×120 and ×1000", flush=True)
    save()


# ---- main ---------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rows", default=",".join(FAMILIES))
    parser.add_argument("--loop-source")
    parser.add_argument("--stock-core", action="store_true")
    parser.add_argument("--remeasure", action="store_true")
    args = parser.parse_args()
    if not args.remeasure:
        print("speed spike: not performed — a historical measurement (B52a, #190) that builds "
              "two hour-long movies (~18 GB) and runs up to ~95 minutes. Run it only to "
              "re-measure the speed or audio ceilings (#212, or a change to SPEED_MAX / "
              "AUDIO_SPEED_MAX), with --remeasure. Speed code in general is "
              "tools/proof/speed_limits_probe.py's to check.")
        return 2
    rows = {part.strip()[:1].upper() for part in args.rows.split(",") if part.strip()}
    unknown = rows - set(FAMILIES)
    if unknown:
        print(f"unknown row families {sorted(unknown)}")
        return 1
    head_max = None
    if args.stock_core:
        found = head_speed_lines()[1]
        if len(found) != 1:
            print(f"mutant stock-core: not performed — HEAD's SPEED_MAX line matches "
                  f"{len(found)} times, not once")
            return 2
        head_max = float(found[0].group(1))
        if head_max >= 1000:
            print(f"mutant stock-core: not performed — HEAD's SPEED_MAX is already {head_max:g}, "
                  "so the stock core is no mutant")
            return 2
    started = time.monotonic()
    results["argv"] = sys.argv[1:]
    results["stock_core"] = args.stock_core
    status_before = git_status()
    host_row("H" in rows)

    needs_probe = bool(rows & set("TPEAXV"))
    needs_timelines = bool(rows & set("TPEV"))
    needs_fixtures = bool(rows & set("AX"))

    sources = None
    if rows & set("STPEV"):
        sources = make_sources(args.loop_source)
        if sources:
            for name, source in sources.items():
                if not source_row(name, source, "S" in rows):
                    sources = None
                    break

    binary = None
    if needs_probe:
        if args.stock_core:
            lib_dir = ROOT / "core/target/release"
            if not (lib_dir / "libreelcut_core.a").exists():
                emit("B1", "FAIL", f"{lib_dir}/libreelcut_core.a is missing — cd core && cargo "
                     "build --release", instrument=True)
                lib_dir = None
            probe_dir = WORK / "probe-stock"
        else:
            lib_dir = scratch_core("B" in rows)
            probe_dir = WORK / "probe"
        if lib_dir is not None:
            binary = build_probe(lib_dir, probe_dir, "B" in rows)

    fixtures = make_fixtures() if needs_fixtures else None

    timelines, previews, exports = {}, {}, {}
    plan = []
    if sources:
        plan = [("loop", r) for r in LOOP_RATES]
        if "loopv" in sources:
            plan += [("loopv", r) for r in LOOPV_RATES]
    if binary and sources and needs_timelines:
        for name, rate in plan:
            answer = t_row(binary, name, name, sources[name], rate, "T" in rows)
            if answer is not None:
                timelines[(name, rate)] = answer
            elif "T" not in rows:
                emit(f"T{rate}.{name}", "FAIL", "the timeline did not read back its rate")
    if binary and sources and rows & set("PV"):
        for name, rate in plan:
            if (name, rate) in timelines:
                previews[(name, rate)] = p_row(binary, name, sources[name], rate, timelines[(name, rate)])
            else:
                emit(f"P{rate}.{name}", "FAIL", "not run: its T row failed", instrument=True)
    a_table = {}
    if binary and fixtures and "A" in rows:
        a_table = a_rows(binary, fixtures)
        results["limits"] = {f"{f}.{a}": v for (f, a), v in l_rows(a_table).items()}
        save()
    if binary and fixtures and "X" in rows:
        x_rows(binary, fixtures)
    if binary and sources and rows & set("EV"):
        for name, rate in sorted(plan, key=lambda item: (item[1], item[0])):
            if (name, rate) in timelines:
                exports[(name, rate)] = e_row(binary, name, sources[name], rate, timelines[(name, rate)])
            else:
                emit(f"E{rate}.{name}", "FAIL", "not run: its T row failed", instrument=True)
    if "V" in rows and sources:
        v_rows(sources, timelines, previews, exports)

    status_after = git_status()
    if "C" in rows:
        emit("C0", "ok" if status_before == status_after else "FAIL",
             f"git status --porcelain -- {' '.join(C0_PATHS)} equal before and after: "
             f"{status_before == status_after} ({len(status_before.splitlines())} lines)",
             {"before": status_before, "after": status_after})
    elapsed = time.monotonic() - started
    results["wall_s"] = elapsed

    if args.stock_core:
        if instrument_failures:
            print(f"mutant stock-core: the control could not be performed — instrument rows "
                  f"{instrument_failures} in {elapsed:.0f} s", flush=True)
            save()
            return 2
        high = [results["rows"].get(f"T{r}.{n}") for n, r in plan if r >= 120]
        if "T" not in rows or not high or any(h is None for h in high):
            print("mutant stock-core: the control could not be performed — T120/T1000 never scored")
            save()
            return 2
        def speeds(h):
            return sorted({c["speed"] for c in ((h.get("data") or {}).get("timeline") or {})
                           .get("clips", [])})
        caught = all(h["status"] == "FAIL" and speeds(h) == [head_max] for h in high)
        print(f"mutant stock-core: {'CAUGHT' if caught else 'SURVIVED'} — T120/T1000 read back "
              f"{[speeds(h) for h in high]} in {elapsed:.0f} s", flush=True)
        save()
        return 1 if caught else 0
    print(f"speed_spike: {len(results['rows'])} rows, instrument failures {instrument_failures} "
          f"in {elapsed:.0f} s", flush=True)
    save()
    return 1 if instrument_failures else 0


if __name__ == "__main__":
    sys.exit(main())
