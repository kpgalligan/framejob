"""Issue batch B60 — a normalised export gains the float mix and quantises
once (#86 part 1), proved per audio preset ACROSS two builds.

    python3 tools/proof/export_gain_proof.py <dir>/agent.sock --record <dir>
    python3 tools/proof/export_gain_proof.py <dir>/agent.sock --against <dir>

Over MCP (the caller owns the instance at that socket, its `RC_AGENT_SOCKET`;
nothing is launched or killed — and a build from before road map 14 listens
on TCP alone, so a `--record` against one is no longer reachable: the
record B60 took stands, and a new one is taken on a build that has the
socket). `--record` runs on the build BEFORE the change and writes
`manifest.json` and every export's decoded PCM into <dir>; `--against` runs
on the build AFTER it and compares with <dir>. Both modes score the
within-build rows.

**Fixtures**, rewritten every run into `work/fixtures/` with ffmpeg
`aevalsrc`, 2 s, 48 kHz stereo s16: `gain_tone.wav` (L 0.5·sin 440 Hz, R
0.5·sin 660 Hz) and `gain_quiet.wav` (the same at 0.02).

**Exports**, for each of the seven presets with sound (`h264`, `hevc`,
`prores_422`, `prores_4444`, `audio_m4a`, `audio_wav`, `audio_aiff`; the
video rows at `size` 640 × 360): the `tone` project un-normalised twice
(`plain`, `plain2`); the `toneoff` project, the tone at `volume` 0.9,
normalised DOWN to −23 LUFS / −1 dBTP (`down`); the `quiet` project, its
clip at `volume` 0.9, normalised UP to −14 / −1 (`up`);
the `hot` project (the tone at `volume` 4, a +6 dBFS mix) normalised to
−14 / −1 (`hot`), plus one un-normalised `audio_wav` of it (`hotplain`).
Each is decoded to s16le 48 kHz stereo by ffmpeg. Every project is closed
with `close_project`.

Within-build rows:
- **G0** (CONTROL), per preset: `plain` and `plain2` decode identically.
- **G4**, per preset, the `hot` export: no decoded sample at −32768 or
  32767; this script's BS.1770-4 integrated loudness of the decode within
  ±0.5 LU of the report's; no "clipped" in the summary.
- **G5**: `hotplain` says "clipped" and holds full-scale samples.

Cross-build rows (`--against`):
- **G1**, per preset: `plain` decodes byte-identical to the reference's.
  Where G0 failed for that preset (in this run or the reference's), G1 is an
  instrument failure.
- **G2** (`down`) and **G3** (`up`) on the LPCM rows (`prores_422`,
  `prores_4444`, `audio_wav`, `audio_aiff`): equal length, and
  max |new − ref| ≤ 1 LSB (down) or ≤ ceil(g/2) + 1 LSB (up, g the reported
  linear gain); G3 also needs at least one differing sample.
- **G2** and **G3** on the AAC rows (`h264`, `hevc`, `audio_m4a`):
  |ΔLUFS| ≤ 0.01 and the difference's RMS ≤ −55 dBFS. (The spec's −70 is
  under AAC's own coding error, −58.4 dBFS on the `up` export, so any
  change to the encoder's input reads about −61 dBFS; README, B60.)

A bound changes only with the measured figure written in the README's B60
section. Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff all
pass.
"""

import array
import json
import math
import os
import re
import shutil
import subprocess
import sys

from mcp import MCP
# The BS.1770-4 pass `phase5_proof.py` wrote from the standard's text, so the
# loudness here is measured with the same arithmetic as phase 5's ±0.5 LU.
from phase5_proof import integrated

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
FIXTURES = os.path.join(WORK, "fixtures")
OUT = os.path.join(WORK, "export_gain")
RATE = 48000

PRESETS = ["h264", "hevc", "prores_422", "prores_4444", "audio_m4a", "audio_wav", "audio_aiff"]
VIDEO = {"h264", "hevc", "prores_422", "prores_4444"}
LPCM = {"prores_422", "prores_4444", "audio_wav", "audio_aiff"}

FIXTURE_EXPRESSIONS = {
    "gain_tone.wav": ("0.5*sin(2*PI*440*t)", "0.5*sin(2*PI*660*t)"),
    "gain_quiet.wav": ("0.02*sin(2*PI*440*t)", "0.02*sin(2*PI*660*t)"),
}

# (project, fixture, volume, [(label, presets, export arguments)])
PLAN = [
    ("tone", "gain_tone.wav", None, [
        ("plain", PRESETS, {}),
        ("plain2", PRESETS, {}),
    ]),
    # At volume 0.9, so the float mix is OFF the 16-bit grid. At 1.0 a 16-bit
    # source's float read is k/32768 exactly, both builds round k·g the same
    # way, and G2 and G3 measured 0 differing samples on every LPCM row (B60).
    ("toneoff", "gain_tone.wav", 0.9, [
        ("down", PRESETS, {"loudness_lufs": -23, "peak_dbtp": -1}),
    ]),
    ("quiet", "gain_quiet.wav", 0.9, [
        ("up", PRESETS, {"loudness_lufs": -14, "peak_dbtp": -1}),
    ]),
    ("hot", "gain_tone.wav", 4, [
        ("hot", PRESETS, {"loudness_lufs": -14, "peak_dbtp": -1}),
        ("hotplain", ["audio_wav"], {}),
    ]),
]

rows = []


def row(row_id, ok, detail):
    rows.append((row_id, ok))
    print(f"{row_id} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


def write_fixtures():
    os.makedirs(FIXTURES, exist_ok=True)
    for name, (left, right) in FIXTURE_EXPRESSIONS.items():
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-f", "lavfi",
             "-i", f"aevalsrc='{left}|{right}':s={RATE}:d=2",
             "-c:a", "pcm_s16le", os.path.join(FIXTURES, name)],
            check=True, timeout=60)


def decode(path, out):
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", path, "-vn", "-f", "s16le",
         "-acodec", "pcm_s16le", "-ar", str(RATE), "-ac", "2", out],
        check=True, timeout=120)
    with open(out, "rb") as handle:
        return handle.read()


def samples(data):
    values = array.array("h")
    values.frombytes(data)
    return values


def lufs(data):
    values = samples(data)
    return integrated([[s / 32768.0 for s in values[0::2]],
                       [s / 32768.0 for s in values[1::2]]])


def full_scale(data):
    return sum(1 for s in samples(data) if s == -32768 or s == 32767)


def run_exports(mcp):
    """Every export of PLAN: {preset: {label: (pcm path, bytes, loudness)}}."""
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT)
    got = {}
    for name, fixture, volume, exports in PLAN:
        path = os.path.join(OUT, f"{name}-{os.getpid()}.reelcut")
        mcp.call("new_project", path=path)
        try:
            media = mcp.call("import_media", project=path,
                             path=os.path.join(FIXTURES, fixture))["media"]
            track = mcp.call("get_project", project=path)["project"]["tracks"][0]["id"]
            clip = mcp.call("add_clip", project=path, track=track, media=media,
                            at=0)["new_clips"][0]
            if volume is not None:
                mcp.call("set_audio", project=path, clips=[clip], patch={"volume": volume})
            for label, presets, extra in exports:
                for preset in presets:
                    args = dict(extra)
                    if preset in VIDEO:
                        args["size"] = [640, 360]
                    target = os.path.join(OUT, f"{name}-{label}-{preset}")
                    result = mcp.call("export", project=path, preset=preset, path=target,
                                      **args)
                    pcm = os.path.join(OUT, f"{label}-{preset}.pcm")
                    data = decode(result["path"], pcm)
                    got.setdefault(preset, {})[label] = (pcm, data, result.get("loudness"))
        finally:
            mcp.call("close_project", project=path, discard=True)
    return got


def within(got):
    """G0, G4, G5: the rows one build answers alone. Returns {preset: G0 ok}."""
    g0 = {}
    for preset in PRESETS:
        a, b = got[preset]["plain"][1], got[preset]["plain2"][1]
        g0[preset] = a == b
        row(f"G0 {preset}", a == b,
            f"CONTROL: two un-normalised exports decode identically "
            f"({len(a)} vs {len(b)} bytes{'' if a == b else ', differ'})")
    for preset in PRESETS:
        _, data, report = got[preset]["hot"]
        clipped = full_scale(data)
        mine = lufs(data)
        reported = (report or {}).get("integrated_lufs")
        summary = (report or {}).get("summary", "")
        near = mine is not None and reported is not None and abs(mine - reported) <= 0.5
        ok = clipped == 0 and near and "clipped" not in summary
        row(f"G4 {preset}", ok,
            f"hot −14/−1: {clipped} full-scale samples, {mine if mine is None else f'{mine:.3f}'}"
            f" LUFS decoded vs {reported} reported, summary “{summary}”")
    _, data, report = got["audio_wav"]["hotplain"]
    clipped = full_scale(data)
    summary = (report or {}).get("summary", "")
    row("G5", "clipped" in summary and clipped > 0,
        f"hot un-normalised WAV: {clipped} full-scale samples, summary “{summary}”")
    return g0


def against(got, g0, where):
    with open(os.path.join(where, "manifest.json")) as handle:
        manifest = json.load(handle)

    def reference(preset, label):
        entry = manifest["presets"][preset]["labels"][label]
        with open(os.path.join(where, entry["pcm"]), "rb") as handle:
            return handle.read(), entry["loudness"]

    for preset in PRESETS:
        ref, _ = reference(preset, "plain")
        new = got[preset]["plain"][1]
        if not (g0[preset] and manifest["presets"][preset]["g0"]):
            row(f"G1 {preset}", False,
                f"instrument: G0 failed for {preset} (this run {g0[preset]}, "
                f"reference {manifest['presets'][preset]['g0']})")
            continue
        row(f"G1 {preset}", new == ref,
            f"un-normalised decode against the reference: "
            f"{'byte-identical' if new == ref else 'DIFFERS'} ({len(new)} vs {len(ref)} bytes)")

    for row_id, label in (("G2", "down"), ("G3", "up")):
        for preset in PRESETS:
            ref, ref_report = reference(preset, label)
            _, new, report = got[preset][label]
            gain_db = (report or {}).get("gain_db")
            gains = f"gain {gain_db} dB (reference {(ref_report or {}).get('gain_db')})"
            if preset in LPCM:
                if len(new) != len(ref):
                    row(f"{row_id} {preset}", False,
                        f"lengths differ ({len(new)} vs {len(ref)} bytes); {gains}")
                    continue
                diffs = [abs(p - q) for p, q in zip(samples(new), samples(ref)) if p != q]
                worst = max(diffs) if diffs else 0
                g = 10 ** (gain_db / 20) if gain_db is not None else math.inf
                bound = 1 if label == "down" else math.ceil(g / 2) + 1
                ok = worst <= bound and (label == "down" or len(diffs) > 0)
                row(f"{row_id} {preset}", ok,
                    f"{len(diffs)} of {len(new) // 2} samples differ, max |Δ| {worst} LSB "
                    f"(bound {bound}); {gains}")
            else:
                a, b = lufs(new), lufs(ref)
                n = min(len(new), len(ref)) // 2
                x, y = samples(new), samples(ref)
                power = sum((x[i] - y[i]) ** 2 for i in range(n)) / max(n, 1)
                rms = 20 * math.log10(math.sqrt(power) / 32768) if power > 0 else -math.inf
                delta = abs(a - b) if a is not None and b is not None else math.inf
                ok = len(new) == len(ref) and delta <= 0.01 and rms <= -55
                row(f"{row_id} {preset}", ok,
                    f"|ΔLUFS| {delta:.4f} ({a} vs {b}), difference RMS {rms:.1f} dBFS "
                    f"(bound −55), lengths {len(new)} vs {len(ref)} bytes; {gains}")


def record(got, g0, where):
    os.makedirs(where, exist_ok=True)
    manifest = {"presets": {}}
    for preset, labels in got.items():
        entry = {"g0": g0.get(preset, False), "labels": {}}
        for label, (pcm, _, report) in labels.items():
            name = os.path.basename(pcm)
            shutil.copy2(pcm, os.path.join(where, name))
            entry["labels"][label] = {"pcm": name, "loudness": report}
        manifest["presets"][preset] = entry
    with open(os.path.join(where, "manifest.json"), "w") as handle:
        json.dump(manifest, handle, indent=1, sort_keys=True)
    print(f"recorded {sum(len(v) for v in got.values())} decodes into {where}", flush=True)


def main():
    args = sys.argv[1:]
    if len(args) != 3 or args[1] not in ("--record", "--against"):
        print(__doc__.split("\n\n")[1])
        return 2
    socket_path, mode, where = args[0], args[1], os.path.abspath(args[2])
    if mode == "--against" and not os.path.exists(os.path.join(where, "manifest.json")):
        print(f"no reference at {where}: run --record on the earlier build first")
        return 2
    write_fixtures()
    got = run_exports(MCP(socket_path))
    g0 = within(got)
    if mode == "--record":
        record(got, g0, where)
    else:
        against(got, g0, where)
    passed = sum(1 for _, ok in rows if ok)
    print(f"{passed}/{len(rows)}", flush=True)
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
