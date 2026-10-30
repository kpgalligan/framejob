"""Road map "audio" AP11 — ducking by speech, and fade and crossfade shapes
(spec §11 AU-110..AU-116), measured on exports over MCP.

    python3 tools/proof/audio_ap11_proof.py <dir>/agent.sock
    python3 tools/proof/audio_ap11_proof.py --probe

The caller owns the instance at that socket; nothing is launched or killed.
Needs `say` and `ffmpeg`. `--probe` runs P1 and P2 alone, with no instance.

**Fixtures**, made on the first run into `tools/proof/media/` (kept):
`ap11_voice.wav` — two `say` sentences with 3.5 s of silence between them,
48 kHz mono; `ap11_voice_cut.wav` — its first 1.0 s, which ends inside the
first word; `ap11_bed.wav` — 20 s of a 440 Hz sine at −12 dBFS, 48 kHz
stereo; `ap11_silent.wav` — 5 s of silence. Each project is a new one,
closed with `close_project` (discarded).

Levels are read by quadrature at 440 Hz over windows of exactly 1,200
samples (11 cycles, 25 ms), so a window of constant gain reads its
amplitude exactly; a window over a ramp reads the ramp's mean, which the
expectation averages too. The voice is MUTED in every ducking project — a
muted ducker still ducks — so the export holds the bed alone.

Rows:
- **D1**: Duck by Speech through `set_audio {duck: {mode: speech}}` applies
  (retried while the speech cache is still being written) and
  `get_project`'s `media[].speech` holds sorted spans inside the file.
- **D2**: inside every held part of every widened span (pre-roll 0.3 s,
  hold 0.3 s, attack 0.1 s) the bed is within ±0.2 dB of 20·log10(0.25).
- **D3**: between the spans, after each release (0.2 s), and before the
  first, the bed is within ±0.2 dB of 0.
- **D4**: the same voice with an EXTENT duck holds the bed at the level
  through the 3.5 s pause too, and lets it back after the clip's end.
- **F1..F4**: a fade in and a fade out of 1 s in each shape (linear,
  s_curve, plus_3db, minus_3db) against the formula, ±0.5 dB wherever the
  formula is above −30 dB.
- **X1**: a linear crossfade (`set_transition_style {curve: linear,
  audio_shape: linear}`) from the bed into a silent clip follows 1 − p,
  ±0.5 dB above −30 dB.
- **T1**: Duck by Speech on `ap11_voice_cut.wav`, which ends in speech,
  applies; every span ends at or before its duration and the last within
  one VAD chunk (19,200 ticks) of it.
- **R1** (only with `samples/Rode-usb-mic.m4a` present): its speech spans'
  JSON size, printed — the file-size cost AU-110 accepted.
- **P1, P2** (the probe `audio_ap11_probe.swift`, compiled AS `main.swift`
  over `app/Sources` on `swift_build.py`'s line; a probe that will not build
  is a scored failure): Ducking ▸ Level committed through the row's own field
  on a clip whose Speech duck came by Paste Attributes and whose media has no
  spans. P1, with the media's voice cache written, sends the media's
  `set_media_speech` before the `set_audio` and the two apply, as `set_audio`
  over MCP does (AU-111); P2, with none, sends the `set_audio` and the core
  refuses it in its own sentence.

Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff all pass.
"""

import array
import json
import math
import os
import shutil
import subprocess
import sys
import time

from mcp import MCP, ToolError
import e2_chrome as e2  # noqa: E402  (project, write_package)
import clip_inspector_proof as ci  # noqa: E402  (media_clip)
import clip_inspector2_proof as ci2  # noqa: E402  (movie)
import swift_build  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MEDIA = os.path.join(HERE, "media")
OUT = os.path.join(HERE, "work", "audio_ap11")
RATE = 48000
SEC = 600_000
WINDOW = 1200  # 11 cycles of 440 Hz at 48 kHz
BED_DB = -12.0
LEVEL = 0.25
DUCK = {"level": LEVEL, "attack": SEC // 10, "release": SEC // 5, "pre_roll": 3 * SEC // 10,
        "hold": 3 * SEC // 10}
VOICE_AT = 2 * SEC
CHUNK = 19_200
SHAPES = ["linear", "s_curve", "plus_3db", "minus_3db"]

rows = []


def row(row_id, ok, detail):
    rows.append((row_id, ok))
    print(f"{row_id} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


def run(command):
    subprocess.run(command, check=True, timeout=120, capture_output=True)


def fixtures():
    os.makedirs(MEDIA, exist_ok=True)
    voice = os.path.join(MEDIA, "ap11_voice.wav")
    if not os.path.exists(voice):
        os.makedirs(OUT, exist_ok=True)
        one, two = os.path.join(OUT, "one.aiff"), os.path.join(OUT, "two.aiff")
        run(["say", "-o", one, "This is the first sentence of the voice over."])
        run(["say", "-o", two, "And this is the second one, after a pause."])
        run(["ffmpeg", "-v", "error", "-y", "-i", one, "-f", "lavfi", "-t", "3.5", "-i",
             f"anullsrc=r={RATE}:cl=mono", "-i", two, "-filter_complex",
             f"[0:a]aresample={RATE},aformat=channel_layouts=mono[a];"
             f"[2:a]aresample={RATE},aformat=channel_layouts=mono[c];"
             "[a][1:a][c]concat=n=3:v=0:a=1", "-ar", str(RATE), "-ac", "1",
             "-c:a", "pcm_s16le", voice])
    cut = os.path.join(MEDIA, "ap11_voice_cut.wav")
    if not os.path.exists(cut):
        run(["ffmpeg", "-v", "error", "-y", "-i", voice, "-t", "1.0", "-c:a", "pcm_s16le", cut])
    bed = os.path.join(MEDIA, "ap11_bed.wav")
    if not os.path.exists(bed):
        amplitude = 10 ** (BED_DB / 20)
        run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
             f"aevalsrc='{amplitude}*sin(2*PI*440*t)|{amplitude}*sin(2*PI*440*t)':s={RATE}:d=20",
             "-c:a", "pcm_s16le", bed])
    silent = os.path.join(MEDIA, "ap11_silent.wav")
    if not os.path.exists(silent):
        run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-t", "5", "-i",
             f"anullsrc=r={RATE}:cl=stereo", "-c:a", "pcm_s16le", silent])
    return voice, cut, bed, silent


def decode(path):
    """The export's left channel as floats."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-vn", "-f", "s16le", "-acodec", "pcm_s16le",
         "-ar", str(RATE), "-ac", "2", "-"], check=True, timeout=120, capture_output=True).stdout
    values = array.array("h")
    values.frombytes(raw)
    return [s / 32768.0 for s in values[0::2]]


def amplitude(left, start):
    """The 440 Hz amplitude over the window starting at sample `start`."""
    i = q = 0.0
    for n in range(start, start + WINDOW):
        phase = 2 * math.pi * 440 * n / RATE
        i += left[n] * math.sin(phase)
        q += left[n] * math.cos(phase)
    return 2 * math.hypot(i, q) / WINDOW


def level_db(left, from_tick, to_tick, reference):
    """Mean of the window amplitudes over [from, to], in dB of `reference`."""
    first = int(from_tick * RATE / SEC)
    last = int(to_tick * RATE / SEC) - WINDOW
    starts = list(range(first, last + 1, WINDOW)) or [first]
    mean = sum(amplitude(left, s) for s in starts) / len(starts)
    return 20 * math.log10(max(mean, 1e-12) / reference)


def project(mcp, name, tracks):
    path = os.path.join(OUT, f"{name}-{os.getpid()}.framejob")
    mcp.call("new_project", path=path)
    for _ in range(tracks - len(mcp.call("get_project", project=path)["project"]["tracks"])):
        mcp.call_with("add_track", {"project": path, "index": 0})
    ids = [t["id"] for t in mcp.call("get_project", project=path)["project"]["tracks"]]
    return path, ids


def place(mcp, path, file, track, at):
    media = mcp.call("import_media", project=path, path=file)["media"]
    clip = mcp.call("add_clip", project=path, track=track, media=media, at=at)["new_clips"][0]
    return media, clip


def speech_duck(mcp, path, clip, duck, seconds=180):
    """`set_audio` turning Speech on, retried while the cache is pending."""
    deadline = time.monotonic() + seconds
    while True:
        try:
            return mcp.call("set_audio", project=path, clips=[clip], patch={"duck": duck})
        except ToolError as error:
            if "not been detected yet" not in str(error) or time.monotonic() > deadline:
                raise
            time.sleep(1)


def export(mcp, path, name):
    result = mcp.export(project=path, preset="audio_wav", path=os.path.join(OUT, name))
    return decode(result["path"])


def media_of(mcp, path, media):
    for entry in mcp.call("get_project", project=path)["project"]["media"]:
        if entry["id"] == media:
            return entry
    raise RuntimeError(f"no media {media}")


def ducking(mcp, voice, bed):
    path, (front, back) = project(mcp, "duck", 2)
    try:
        reference = 10 ** (BED_DB / 20)
        place(mcp, path, bed, back, 0)
        media, clip = place(mcp, path, voice, front, VOICE_AT)
        mcp.call("set_audio", project=path, clips=[clip], patch={"muted": True})
        speech_duck(mcp, path, clip, dict(DUCK, mode="speech"))
        entry = media_of(mcp, path, media)
        spans = entry.get("speech") or []
        sorted_ok = all(0 <= a < b <= entry["duration"] for a, b in spans) and all(
            spans[k][1] <= spans[k + 1][0] for k in range(len(spans) - 1))
        row("D1", bool(spans) and sorted_ok,
            f"{len(spans)} spans in {entry['duration']} ticks: {spans}")
        left = export(mcp, path, "speech")
        # Widened and merged in project time, as the core does.
        widened = []
        for a, b in spans:
            s, e = VOICE_AT + a - DUCK["pre_roll"], VOICE_AT + b + DUCK["hold"]
            if widened and s <= widened[-1][1]:
                widened[-1][1] = max(widened[-1][1], e)
            else:
                widened.append([s, e])
        margin = SEC // 40
        held = [(s + DUCK["attack"] + margin, e - margin) for s, e in widened
                if e - s - DUCK["attack"] > 3 * margin + SEC // 20]
        free = []
        edge = 0
        for s, e in widened:
            if s - margin - (edge + margin) > SEC // 10:
                free.append((edge + margin, s - margin))
            edge = e + DUCK["release"]
        want = 20 * math.log10(LEVEL)
        down = [level_db(left, a, b, reference) for a, b in held]
        row("D2", bool(down) and all(abs(d - want) <= 0.2 for d in down),
            f"held parts {[(a, b) for a, b in held]}: "
            + ", ".join(f"{d:+.3f}" for d in down) + f" dB (want {want:+.3f} ±0.2)")
        up = [level_db(left, a, b, reference) for a, b in free]
        row("D3", bool(up) and all(abs(d) <= 0.2 for d in up),
            f"free parts {free}: " + ", ".join(f"{d:+.3f}" for d in up) + " dB (want 0 ±0.2)")
        pause = None
        for (_, e1), (s2, _) in zip(spans, spans[1:]):
            if s2 - e1 > 2 * SEC:
                pause = (VOICE_AT + e1 + SEC // 2, VOICE_AT + s2 - SEC // 2)
        mcp.call("set_audio", project=path, clips=[clip], patch={"duck": {"mode": "extent"}})
        left = export(mcp, path, "extent")
        end = VOICE_AT + entry["duration"]
        through = level_db(left, *pause, reference) if pause else math.nan
        after = level_db(left, end + DUCK["release"] + margin, end + DUCK["release"] + SEC,
                         reference)
        row("D4", pause is not None and abs(through - want) <= 0.2 and abs(after) <= 0.2,
            f"extent duck: pause {pause} at {through:+.3f} dB (want {want:+.3f}), after the "
            f"clip's release {after:+.3f} dB (want 0)")
    finally:
        mcp.call("close_project", project=path, discard=True)


def formula(shape, u):
    u = min(max(u, 0.0), 1.0)
    return {"linear": u, "s_curve": (1 - math.cos(math.pi * u)) / 2,
            "plus_3db": math.sin(u * math.pi / 2),
            "minus_3db": 1 - math.cos(u * math.pi / 2)}[shape]


def against(left, start_tick, end_tick, gain, reference):
    """Every window over [start, end] against the mean of `gain(tick)`;
    the worst |Δ| in dB where the expectation is above −30 dB."""
    worst, counted = 0.0, 0
    first = int(start_tick * RATE / SEC)
    last = int(end_tick * RATE / SEC) - WINDOW
    for s in range(first, last + 1, WINDOW):
        expect = sum(gain(int(n * SEC / RATE)) for n in range(s, s + WINDOW, 40)) / (WINDOW / 40)
        if expect <= 10 ** (-30 / 20):
            continue
        got = amplitude(left, s) / reference
        worst = max(worst, abs(20 * math.log10(max(got, 1e-12) / expect)))
        counted += 1
    return worst, counted


def fades(mcp, bed):
    reference = 10 ** (BED_DB / 20)
    for index, shape in enumerate(SHAPES, start=1):
        path, (track,) = project(mcp, f"fade-{shape}", 1)
        try:
            _, clip = place(mcp, path, bed, track, 0)
            mcp.call("trim_end", project=path, clip=clip, to=4 * SEC)
            mcp.call("set_audio", project=path, clips=[clip],
                     patch={"fade_in": SEC, "fade_out": SEC, "fade_in_shape": shape,
                            "fade_out_shape": shape})
            left = export(mcp, path, f"fade-{shape}")
            fade_in, n_in = against(left, 0, SEC, lambda t: formula(shape, t / SEC), reference)
            fade_out, n_out = against(left, 3 * SEC, 4 * SEC,
                                      lambda t: formula(shape, (4 * SEC - t) / SEC), reference)
            row(f"F{index}", max(fade_in, fade_out) <= 0.5 and n_in > 10 and n_out > 10,
                f"{shape}: fade in worst {fade_in:.3f} dB over {n_in} windows, fade out worst "
                f"{fade_out:.3f} dB over {n_out} (bound 0.5)")
        finally:
            mcp.call("close_project", project=path, discard=True)


def crossfade(mcp, bed, silent):
    reference = 10 ** (BED_DB / 20)
    path, (track,) = project(mcp, "crossfade", 1)
    try:
        _, out = place(mcp, path, bed, track, 0)
        mcp.call("trim_end", project=path, clip=out, to=4 * SEC)
        _, into = place(mcp, path, silent, track, 4 * SEC)
        mcp.call("add_transition", project=path, clip=into, duration=SEC, align="after")
        mcp.call("set_transition_style", project=path, clip=into, curve="linear",
                 audio_shape="linear")
        stored = [c for c in mcp.call("get_project", project=path)["project"]["clips"]
                  if c["id"] == into][0].get("transition_in", {})
        left = export(mcp, path, "crossfade")
        worst, counted = against(left, 4 * SEC, 5 * SEC, lambda t: 1 - (t - 4 * SEC) / SEC,
                                 reference)
        row("X1", stored.get("audio_shape") == "linear" and worst <= 0.5 and counted > 10,
            f"transition {stored}; outgoing bed against 1 − p: worst {worst:.3f} dB over "
            f"{counted} windows (bound 0.5)")
    finally:
        mcp.call("close_project", project=path, discard=True)


def ends_in_speech(mcp, cut):
    path, (track,) = project(mcp, "cut", 1)
    try:
        media, clip = place(mcp, path, cut, track, 0)
        speech_duck(mcp, path, clip, dict(DUCK, mode="speech"))
        entry = media_of(mcp, path, media)
        spans = entry.get("speech") or []
        duration = entry["duration"]
        last = spans[-1][1] if spans else None
        ok = bool(spans) and all(b <= duration for _, b in spans) and duration - last <= CHUNK
        row("T1", ok, f"duration {duration}, spans {spans} (last end {last})")
    finally:
        mcp.call("close_project", project=path, discard=True)


def rode(mcp):
    sample = os.path.join(ROOT, "samples", "Rode-usb-mic.m4a")
    if not os.path.exists(sample):
        print("R1 — samples/Rode-usb-mic.m4a is not here; nothing to measure", flush=True)
        return
    path, (track,) = project(mcp, "rode", 1)
    try:
        media, clip = place(mcp, path, sample, track, 0)
        speech_duck(mcp, path, clip, {"mode": "speech"})
        entry = media_of(mcp, path, media)
        spans = entry.get("speech") or []
        text = json.dumps(spans, separators=(",", ":"))
        pretty = json.dumps({"speech": spans}, indent=2)
        row("R1", bool(spans),
            f"{len(spans)} spans over {entry['duration'] / SEC:.1f} s: {len(text.encode())} bytes "
            f"compact, {len(pretty.encode())} bytes as the project file's pretty JSON writes it")
    finally:
        mcp.call("close_project", project=path, discard=True)


def probe():
    """P1, P2: the probe over this tree's `app/Sources`."""
    work = os.path.join(OUT, "probe")
    os.makedirs(work, exist_ok=True)
    e2.CHROME = work
    six = ci.CLIP_SECONDS * e2.TICKS
    package = e2.write_package("ap11-duck", e2.project(
        [ci.media_clip(2, 91, 0, [], video=True), ci.media_clip(3, 92, six, [], video=True)],
        media=[ci2.movie(91, True), ci2.movie(92, True)]))
    entry = os.path.join(work, "main.swift")
    shutil.copyfile(os.path.join(HERE, "audio_ap11_probe.swift"), entry)
    sources = os.path.join(ROOT, "app", "Sources")
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    binary = os.path.join(work, "audio-ap11-probe")
    try:
        swift_build.build(sources=swift + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        row("P1", False, "the probe does not build: " + " | ".join(errors[:6] or [str(error)]))
        row("P2", False, "the probe does not build")
        return
    request, answer = os.path.join(work, "request.json"), os.path.join(work, "answer.json")
    with open(request, "w") as f:
        json.dump({"duck": package}, f)
    result = subprocess.run([binary, request, answer], capture_output=True, text=True,
                            timeout=300)
    answered = {}
    if result.returncode == 0 and os.path.exists(answer):
        with open(answer) as f:
            answered = {r["name"].split(" ")[0]: r for r in json.load(f)["rows"]}
    for name in ("P1", "P2"):
        got = answered.get(name)
        if got is None:
            row(name, False, "the probe did not answer: "
                + (result.stdout + result.stderr).strip()[-400:])
        else:
            row(name, got["ok"], got["name"] + " — " + got["detail"])


def main():
    if sys.argv[1:] == ["--probe"]:
        shutil.rmtree(OUT, ignore_errors=True)
        probe()
        passed = sum(1 for _, ok in rows if ok)
        print(f"{passed}/{len(rows)}", flush=True)
        return 0 if passed == len(rows) else 1
    if len(sys.argv) != 2:
        print(__doc__.split("\n\n")[1])
        return 2
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT)
    probe()
    voice, cut, bed, silent = fixtures()
    mcp = MCP(sys.argv[1])
    ducking(mcp, voice, bed)
    fades(mcp, bed)
    crossfade(mcp, bed, silent)
    ends_in_speech(mcp, cut)
    rode(mcp)
    passed = sum(1 for _, ok in rows if ok)
    print(f"{passed}/{len(rows)}", flush=True)
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
