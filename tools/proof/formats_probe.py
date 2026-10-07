#!/usr/bin/env python3
"""Which import formats AVFoundation and ImageIO open on THIS host (#46).

Makes tiny ffmpeg fixtures (1 s, 128x72), builds formats_probe.swift with
every app/Sources/*.swift except main.swift (peaks_probe.py's pattern) and
asks the product's own `MediaImporter.waitForProbe` about each — no ffmpeg
rewrap, which is spec §11's, not §7.7's. A row is `opens` (probe and first
decode both answer), `probe-only` (probe answers, decode does not),
`refused` (the probe throws), `not made` (the encoder failed on this host)
or `expired` (the probe binary's bound ran out before its row arrived).

Controls: C1 mov_h264_aac.mov opens; C2 junk.mov (4096 seeded random bytes)
is refused; C3 mp4_vp9.mp4 and C4 mp4_vp9_p2.mp4 open (the supplemental VP9
decoder, spec §11 #216); C5 mp4_vp9_p1.mp4 is refused with exactly the
Profile 1 sentence; C6 mp4_av1.mp4 is refused with exactly the M3 sentence
when HOST hw_av1 is false, and opens when it is true; C7 mp4_h264_damaged.mp4
(a decodable codec with its first GOP damaged) is not refused.

Mutants: `junk-good` hands C2 the C1 file, so C2 must FAIL. The source
mutants build from an edited copy of app/Sources: `no-register` drops both
supplemental-decoder registrations (C3, C4 FAIL), `no-decode-check` makes
`decodesFirstFrame` answer true at its head (C5 FAIL, and C6 on an M1/M2),
`refuse-any-failure` refuses on any AVFoundation reader error (C7 FAIL).
Each must exit 1. Every child runs under graphics_spike/bounded.py's `run`.

    python3 tools/proof/formats_probe.py [--mutant NAME]
"""
import argparse
import json
from pathlib import Path
import random
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
import bounded  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/formats-probe"
FIXTURES = WORK / "fixtures"
VIDEO_IN = ["-f", "lavfi", "-i", "testsrc2=size=128x72:rate=30:duration=1"]
AUDIO_IN = ["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=1"]
YUV = ["-pix_fmt", "yuv420p"]
X264 = ["-c:v", "libx264", *YUV]
AAC = ["-c:a", "aac"]
HEVC = ["-c:v", "libx265", *YUV, "-tag:v", "hvc1"]
VORBIS = ["-c:a", "vorbis", "-strict", "-2", "-ac", "2"]

# (id, file, inputs, encoder arguments); inputs: v = picture, a = sound.
FIXTURE_ROWS = [
    ("V1", "mov_h264_aac.mov", "va", X264 + AAC),
    ("V2", "mp4_h264_aac.mp4", "va", X264 + AAC),
    ("V3", "m4v_h264.m4v", "v", X264 + ["-f", "ipod"]),
    ("V4", "mov_hevc.mov", "v", HEVC),
    ("V5", "mp4_hevc.mp4", "v", HEVC),
    ("V6", "mov_prores.mov", "v", ["-c:v", "prores_ks", "-profile:v", "2",
                                   "-pix_fmt", "yuv422p10le"]),
    ("V7", "mov_mjpeg.mov", "v", ["-c:v", "mjpeg", "-pix_fmt", "yuvj420p"]),
    ("V8", "mp4_mpeg4.mp4", "v", ["-c:v", "mpeg4", *YUV]),
    ("V9", "mp4_av1.mp4", "v", ["-c:v", "libsvtav1", *YUV]),
    ("V10", "mp4_vp9.mp4", "v", ["-c:v", "libvpx-vp9", *YUV]),
    ("V11", "mkv_h264.mkv", "v", X264),
    ("V12", "mkv_av1.mkv", "v", ["-c:v", "libsvtav1", *YUV]),
    ("V13", "webm_vp9.webm", "va", ["-c:v", "libvpx-vp9", *YUV, "-c:a", "libopus"]),
    ("V14", "webm_vp8.webm", "va", ["-c:v", "libvpx", *YUV, *VORBIS]),
    ("V15", "avi_mjpeg.avi", "v", ["-c:v", "mjpeg", "-pix_fmt", "yuvj420p"]),
    ("V16", "ts_h264.ts", "v", X264),
    ("V17", "mp4_vp9_p2.mp4", "v", ["-c:v", "libvpx-vp9", "-pix_fmt", "yuv420p10le",
                                    "-profile:v", "2"]),
    ("V18", "mp4_vp9_p1.mp4", "v", ["-c:v", "libvpx-vp9", "-pix_fmt", "yuv444p",
                                    "-profile:v", "1"]),
    ("V19", "mp4_vp8.mp4", "v", ["-c:v", "libvpx", *YUV]),
    ("A1", "m4a_aac.m4a", "a", AAC),
    ("A2", "aac_adts.aac", "a", AAC),
    ("A3", "mp3.mp3", "a", ["-c:a", "libmp3lame"]),
    ("A4", "wav.wav", "a", ["-c:a", "pcm_s16le"]),
    ("A5", "aiff.aiff", "a", ["-c:a", "pcm_s16be"]),
    ("A6", "caf_pcm.caf", "a", ["-c:a", "pcm_s16le"]),
    ("A7", "m4a_alac.m4a", "a", ["-c:a", "alac"]),
    ("A8", "flac.flac", "a", ["-c:a", "flac"]),
    ("A9", "ogg_opus.ogg", "a", ["-c:a", "libopus"]),
    ("A10", "ogg_vorbis.ogg", "a", VORBIS),
    ("P1", "png.png", "v", ["-frames:v", "1"]),
    ("P2", "jpg.jpg", "v", ["-frames:v", "1"]),
    # rgb24: left alone, ffmpeg writes testsrc2's yuv420p as a subsampled
    # YCbCr TIFF, which ImageIO reads no size from (refused on 2026-10-01).
    ("P3", "tiff.tiff", "v", ["-frames:v", "1", "-pix_fmt", "rgb24"]),
    ("P4", "gif.gif", "v", ["-frames:v", "1"]),
    ("P5", "bmp.bmp", "v", ["-frames:v", "1"]),
]

# name: [(file under app/Sources, before, after)]; each `before` must match
# exactly once in the copy (cache_pass_probe.py's `mutate`).
SOURCE_MUTANTS = {
    "no-register": [
        ("DecoderSupport.swift",
         "VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9)", "_ = 0"),
        ("DecoderSupport.swift",
         "VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_AV1)", "_ = 0"),
    ],
    "no-decode-check": [
        ("DecoderSupport.swift",
         "static func decodesFirstFrame(of track: AVAssetTrack, in asset: AVAsset) -> Bool {",
         "static func decodesFirstFrame(of track: AVAssetTrack, in asset: AVAsset) -> Bool {\n"
         "        return true"),
    ],
    "refuse-any-failure": [
        ("DecoderSupport.swift", "Self.refusingErrorCodes.contains(code)", "true"),
    ],
}

P1_SENTENCE = ("mp4_vp9_p1.mp4 is VP9 Profile 1 video, which this Mac cannot decode; "
               "VP9 Profiles 0 and 2 import.")
AV1_SENTENCE = "mp4_av1.mp4 is AV1 video, which needs an M3 or later Mac."


def check(name, good, detail=""):
    print(("  ok   " if good else "  FAIL ") + name + (f": {detail}" if detail else ""))
    return bool(good)


def tail(text, limit=200):
    text = " ".join((text or "").split())
    return text[-limit:] if text else "(no stderr)"


def make_fixtures():
    """[(id, file, path or None, not-made reason)] in table order."""
    if FIXTURES.exists():
        shutil.rmtree(FIXTURES)
    FIXTURES.mkdir(parents=True)
    rows = []
    for row_id, name, inputs, args in FIXTURE_ROWS:
        path = FIXTURES / name
        source = (VIDEO_IN if "v" in inputs else []) + (AUDIO_IN if "a" in inputs else [])
        result = bounded.run(["ffmpeg", "-y", "-v", "error", *source, *args, str(path)], 60)
        made = result["rc"] == 0 and not result["expired"] and path.exists()
        why = "" if made else ("expired after 60 s" if result["expired"]
                               else tail(result["stderr"]))
        rows.append((row_id, name, path if made else None, why))
    heic = FIXTURES / "heic.heic"
    png = FIXTURES / "png.png"
    if png.exists():
        result = bounded.run(["sips", "-s", "format", "heic", str(png), "--out", str(heic)], 60)
        made = result["rc"] == 0 and not result["expired"] and heic.exists()
        why = "" if made else ("expired after 60 s" if result["expired"]
                               else tail(result["stderr"] or result["stdout"]))
    else:
        made, why = False, "png.png was not made"
    rows.append(("P6", "heic.heic", heic if made else None, why))
    junk = FIXTURES / "junk.mov"
    junk.write_bytes(random.Random(58).randbytes(4096))
    rows.append(("X1", "junk.mov", junk, ""))
    rows.append(make_damaged())
    return rows


def make_damaged():
    """X2: an H.264 MP4 whose first GOP is overwritten just past the mdat
    header with 2048 seeded random bytes — a codec this Mac decodes, with
    damaged data (spec §11 #216: not refused)."""
    name = "mp4_h264_damaged.mp4"
    path = FIXTURES / name
    result = bounded.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                          "testsrc2=size=640x360:rate=30:duration=1", *X264,
                          "-movflags", "+faststart", str(path)], 60)
    if result["rc"] or result["expired"] or not path.exists():
        why = "expired after 60 s" if result["expired"] else tail(result["stderr"])
        return ("X2", name, None, why)
    data = bytearray(path.read_bytes())
    at = data.find(b"mdat")
    if at < 0 or at + 4 + 2048 > len(data):
        return ("X2", name, None, "no mdat box with 2048 bytes after its header")
    data[at + 4:at + 4 + 2048] = random.Random(72).randbytes(2048)
    path.write_bytes(bytes(data))
    return ("X2", name, path, "")


def mutate(name, dest):
    """A copy of app/Sources at `dest` with the mutant's edits; the reason
    when a `before` text is not found exactly once, else None."""
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(ROOT / "app/Sources", dest)
    for file, before, after in SOURCE_MUTANTS[name]:
        path = dest / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def build(sources):
    WORK.mkdir(parents=True, exist_ok=True)
    entry = WORK / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/formats_probe.swift", entry)
    binary = WORK / "formats-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary, timeout=600)
    except swift_build.SwiftBuildFailed as error:
        if error.expired:
            return None, "swiftc expired after 600 s"
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    return binary, ""


def verdict(answer):
    if answer["probe"] != "ok":
        return "refused"
    return "opens" if answer["decode"] == "ok" else "probe-only"


def describe(answer):
    if answer["probe"] != "ok":
        what = answer.get("error", "")
    else:
        tracks = "+".join(t for t, key in (("video", "has_video"), ("audio", "has_audio"))
                          if answer.get(key)) or "no tracks"
        what = (f"{answer['kind']} {answer['width']}x{answer['height']}, {tracks}, "
                f"{answer['duration_ticks']} ticks")
    playable = answer.get("playable")
    return (f"{what}; decode {answer['decode_detail']}; playable "
            f"{'n/a' if playable is None else str(playable).lower()}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=["junk-good", *SOURCE_MUTANTS])
    args = parser.parse_args()
    cpu = bounded.run(["sysctl", "-n", "machdep.cpu.brand_string"], 30)["stdout"].strip()
    sources = ROOT / "app/Sources"
    if args.mutant in SOURCE_MUTANTS:
        sources = WORK / f"Sources-{args.mutant}"
        why = mutate(args.mutant, sources)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    rows = make_fixtures()
    binary, problem = build(sources)
    if not check(f"B0 the probe builds from {sources.relative_to(ROOT)}",
                 binary is not None, problem):
        print("controls: 0/7")
        made = sum(1 for row in rows if row[2])
        print(f"rows: {made} made, {len(rows) - made} not made, 0 expired")
        return 1
    files = [str(path) for _, _, path, _ in rows if path]
    result = bounded.run([str(binary), *files], 300)
    host, answers = {}, {}
    for line in result["stdout"].splitlines():
        tag, _, body = line.partition(" ")
        try:
            parsed = json.loads(body) if tag in ("HOST", "ROW") else None
        except json.JSONDecodeError:
            continue  # a line cut off by the kill: score what arrived whole
        if tag == "HOST":
            host = parsed
        elif tag == "ROW":
            answers[parsed["file"]] = parsed
    print(f"host: macOS {host.get('macos', '?')} ({host.get('build', '?')}), {cpu}; "
          f"hw_av1 {host.get('hw_av1')}, hw_vp9 {host.get('hw_vp9')}, "
          f"hw_hevc {host.get('hw_hevc')}")
    if result["expired"]:
        print(f"probe binary expired after 300 s; {len(answers)} rows received")
    elif result["rc"]:
        print(f"probe binary exited {result['rc']}: {tail(result['stderr'], 400)}")
    table, counts = [], {"made": 0, "not made": 0, "expired": 0}
    for row_id, name, path, why in rows:
        if path is None:
            counts["not made"] += 1
            entry = {"id": row_id, "file": name, "verdict": f"not made: {why}"}
            print(f"{row_id} {name} not made: {why}")
        elif name not in answers:
            counts["made"] += 1
            counts["expired"] += 1
            # "expired" is the bound running out; a binary that died first says so.
            lost = "expired" if result["expired"] else f"no answer (binary exited {result['rc']})"
            entry = {"id": row_id, "file": name, "verdict": lost}
            print(f"{row_id} {name} {lost}")
        else:
            counts["made"] += 1
            answer = answers[name]
            entry = {"id": row_id, "file": name, "verdict": verdict(answer), "answer": answer}
            print(f"{row_id} {name} {entry['verdict']} — {describe(answer)}")
        table.append(entry)
    by_file = {entry["file"]: entry["verdict"] for entry in table}

    def message(name):
        return answers.get(name, {}).get("message")

    def refused_with(name, sentence):
        got = by_file.get(name, "missing")
        good = got == "refused" and message(name) == sentence
        return good, f"{got}: {message(name)!r}" if got == "refused" else got

    c2_file = "mov_h264_aac.mov" if args.mutant == "junk-good" else "junk.mov"
    av1_hardware = host.get("hw_av1") is True
    if av1_hardware:
        c6 = (by_file.get("mp4_av1.mp4") == "opens", by_file.get("mp4_av1.mp4", "missing"))
    else:
        c6 = refused_with("mp4_av1.mp4", AV1_SENTENCE)
    controls = [
        check("C1 mov_h264_aac.mov opens", by_file.get("mov_h264_aac.mov") == "opens",
              by_file.get("mov_h264_aac.mov", "missing")),
        check(f"C2 {c2_file} is refused", by_file.get(c2_file) == "refused",
              by_file.get(c2_file, "missing")),
        check("C3 mp4_vp9.mp4 opens", by_file.get("mp4_vp9.mp4") == "opens",
              by_file.get("mp4_vp9.mp4", "missing")),
        check("C4 mp4_vp9_p2.mp4 opens", by_file.get("mp4_vp9_p2.mp4") == "opens",
              by_file.get("mp4_vp9_p2.mp4", "missing")),
        check("C5 mp4_vp9_p1.mp4 is refused with the Profile 1 sentence",
              *refused_with("mp4_vp9_p1.mp4", P1_SENTENCE)),
        check("C6 mp4_av1.mp4 " + ("opens (hw_av1 true)" if av1_hardware
                                   else "is refused with the M3 sentence (hw_av1 false)"), *c6),
        check("C7 mp4_h264_damaged.mp4 is not refused",
              by_file.get("mp4_h264_damaged.mp4") in ("opens", "probe-only"),
              by_file.get("mp4_h264_damaged.mp4", "missing")),
    ]
    (WORK / "answers.json").write_text(json.dumps(
        {"host": host, "cpu": cpu, "mutant": args.mutant, "rows": table,
         "controls": controls}, indent=2) + "\n")
    print(f"controls: {sum(controls)}/{len(controls)}")
    print(f"rows: {counts['made']} made, {counts['not made']} not made, "
          f"{counts['expired']} expired")
    return 0 if all(controls) else 1


if __name__ == "__main__":
    sys.exit(main())
