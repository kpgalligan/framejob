#!/usr/bin/env python3
"""The shared maker of the proofs' BT.709-tagged ffmpeg fixtures (issue #292):
precision_proof's `tagged`/`read_back` rule (issue batch B98, #290),
parametrised by path, for hdr_proof, curves_proof, grading_verdict and
grading_spike.

    python3 tools/proof/bt709_fixture.py --selftest
    python3 tools/proof/bt709_fixture.py --selftest --mutant guard-dropped|tags-unchecked|readback-unchecked|no-remake

`make(out, graph, codec, want, pix_fmt)` refuses a graph that does not carry
`SETPARAMS` on its input: given to the output alone, the tags left ProRes's
primaries and transfer `unknown` (B98), and an output-only tag can convert the
codes (B95). Otherwise it makes `out` when missing, from `[*graph, *codec,
*TAG]` through a `partial-` file renamed into place, and keeps `out` — a
cached file too — only when ffprobe reads every pair of `want` and
`TAG_WANT` and `read_back` holds: the first frame of `graph` rendered raw to
`pix_fmt` with no encode, against `out`'s first frame decoded to `pix_fmt`,
mean |Δ| of each of Y, Cb and Cr ≤ `READBACK_MEAN` 8-bit levels (10-bit
codes ÷ 4). A refused file is removed and made once more; a second refusal is
`(None, reason)`. It prints one line per kept or refused file, and returns it.

The selftest (S1–S4 scored, S5 a RECORD) works in `tools/proof/work/
bt709_fixture/`, removed at the start and at exit, on a 64×64 1 s `testsrc2`
through `prores_ks` profile 3 `yuv422p10le`. Each mutant edits `make` and
must fail its cases: `guard-dropped` S1, `tags-unchecked` S3,
`readback-unchecked` S4, `no-remake` S3 and S4. Every ffmpeg and ffprobe is
bounded. README: `tools/proof/README.md`, "Issue #292".
"""

import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402

SETPARAMS = "setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709"
TAG = ["-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709"]
TAG_WANT = {"color_primaries": "bt709", "color_transfer": "bt709", "color_space": "bt709"}
READBACK_MEAN = 2.0
# The planar layouts `read_back` reads: bytes a sample, chroma subsampling.
PLANAR = {"yuv420p": (1, 2, 2), "yuv420p10le": (2, 2, 2), "yuv422p10le": (2, 2, 1),
          "yuv444p10le": (2, 1, 1)}
MUTANTS = ("guard-dropped", "tags-unchecked", "readback-unchecked", "no-remake")
MUTANT = None
EXPECTED = {"guard-dropped": {"S1"}, "tags-unchecked": {"S3"},
            "readback-unchecked": {"S4"}, "no-remake": {"S3", "S4"}}
WORK = HERE / "work" / "bt709_fixture"
FAILED = set()   # the scored cases the last selftest failed


def stream(path):
    """ffprobe's first video stream: codec, profile, pix_fmt, size and the
    three colour tags; {} when it reads nothing."""
    ran = bounded.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                       "stream=codec_name,profile,pix_fmt,width,height,color_space,"
                       "color_transfer,color_primaries", "-of", "json", str(path)], 60)
    try:
        return (json.loads(ran["stdout"]).get("streams") or [{}])[0]
    except (ValueError, IndexError, AttributeError):
        return {}


def tags(probe):
    return (f"{probe.get('color_transfer')}/{probe.get('color_primaries')}/"
            f"{probe.get('color_space')}")


def decode(path, pix_fmt):
    """The raw `pix_fmt` bytes of `path`'s first frame, or None — bounded."""
    try:
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-frames:v", "1",
                              "-f", "rawvideo", "-pix_fmt", pix_fmt, "-"],
                             capture_output=True, timeout=300, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    return raw or None


def planes(raw, pix_fmt, width, height):
    """`raw` (one frame) as its Y, Cb and Cr sample lists, chroma sized by
    ceil, or None when it is short."""
    size, sub_x, sub_y = PLANAR[pix_fmt]
    cw, ch = -(-width // sub_x), -(-height // sub_y)
    counts = (width * height, cw * ch, cw * ch)
    if not raw or len(raw) < size * sum(counts):
        return None
    values = struct.unpack(f"<{sum(counts)}{'H' if size == 2 else 'B'}",
                           raw[:size * sum(counts)])
    return [values[:counts[0]], values[counts[0]:counts[0] + counts[1]],
            values[counts[0] + counts[1]:]]


def read_back(out, graph, pix_fmt):
    """(held, detail): `out`'s first frame decoded to `pix_fmt` against the
    first frame of `graph` (the fixture's own input argv) rendered raw to
    `pix_fmt` with no encode, by mean |Δ| per plane in 8-bit levels (10-bit
    codes ÷ 4); held when each of Y, Cb and Cr is ≤ READBACK_MEAN."""
    probe = stream(out)
    width, height = probe.get("width"), probe.get("height")
    if not width or not height:
        return False, f"ffprobe read no size from {Path(out).name}"
    try:
        raw = subprocess.run(["ffmpeg", "-v", "error", *graph, "-frames:v", "1", "-f",
                              "rawvideo", "-pix_fmt", pix_fmt, "-"], capture_output=True,
                             timeout=300, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        raw = None
    written, stored = (planes(raw, pix_fmt, width, height),
                       planes(decode(out, pix_fmt), pix_fmt, width, height))
    if written is None or stored is None:
        return False, (f"read back {pix_fmt}: the graph's frame {'ok' if written else 'short'}, "
                       f"{Path(out).name}'s {'ok' if stored else 'short'}")
    scale = 4 if PLANAR[pix_fmt][0] == 2 else 1
    means = [sum(abs(a - b) for a, b in zip(w, s)) / len(w) / scale
             for w, s in zip(written, stored)]
    return (all(m <= READBACK_MEAN for m in means),
            "read-back mean |Δ| Y, Cb, Cr " + ", ".join(f"{m:.3f}" for m in means)
            + " 8-bit levels")


def make(out, graph, codec, want, pix_fmt, seconds=600):
    """(`out`, the kept line) when `out` — made from `[*graph, *codec, *TAG]`
    when missing — reads `want` and TAG_WANT and `read_back` holds; else
    (None, the reason). A graph without SETPARAMS is refused before ffmpeg
    runs; a refused file, a stale cached one included, is removed and made
    once more."""
    out = Path(out)
    if MUTANT != "guard-dropped" and not any(SETPARAMS in str(part) for part in graph):
        why = (f"{out.name} refused: its graph carries no `{SETPARAMS}` on the input (the "
               f"output's tags alone can leave primaries and transfer unknown, or convert)")
        print(f"       {why}", flush=True)
        return None, why
    need = {**want, **TAG_WANT}
    why = f"ffmpeg did not make {out.name}"
    for attempt in (1, 2):
        if not out.exists():
            out.parent.mkdir(parents=True, exist_ok=True)
            partial = out.parent / f"partial-{out.name}"
            made = bounded.run(["ffmpeg", "-nostdin", "-v", "error", "-y", *graph, *codec,
                                *TAG, str(partial)], seconds)
            if made["rc"] != 0 or made["expired"] or not partial.exists():
                why = (f"ffmpeg did not make {out.name} (attempt {attempt}): "
                       f"{'expired' if made['expired'] else made['stderr'][-300:].strip()}")
                print(f"       {why}", flush=True)
                partial.unlink(missing_ok=True)
                continue
            partial.rename(out)
        probe = stream(out)
        wrong = {} if MUTANT == "tags-unchecked" else {
            k: probe.get(k, "unknown") for k, v in need.items() if probe.get(k) != v}
        if wrong:
            held, detail = False, "not read"
        elif MUTANT == "readback-unchecked":
            held, detail = True, "read-back skipped (mutant readback-unchecked)"
        else:
            held, detail = read_back(out, graph, pix_fmt)
        if held:
            line = f"{out.name} kept: {tags(probe)}; {detail}"
            print(f"       {line}", flush=True)
            return out, line
        why = (f"{out.name} refused (attempt {attempt}): ffprobe read {wrong or 'as wanted'}, "
               f"want {need}; {detail}")
        print(f"       {why}", flush=True)
        out.unlink(missing_ok=True)
        if MUTANT == "no-remake":
            return None, why
    return None, why


# ---- the selftest ---------------------------------------------------------------

SOURCE = "testsrc2=size=64x64:rate=30:duration=1"
GRAPH = ["-f", "lavfi", "-i", f"{SOURCE},{SETPARAMS}"]
CODEC = ["-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le"]
WANT = {"codec_name": "prores", "pix_fmt": "yuv422p10le", "width": 64, "height": 64}
SMPTE170M = ("setparams=color_primaries=smpte170m:color_trc=smpte170m:colorspace=smpte170m")
FLAGS_170M = ["-colorspace", "smpte170m", "-color_primaries", "smpte170m",
              "-color_trc", "smpte170m"]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest() if Path(path).exists() else None


def prewrite(out, argv):
    """`out` written by ffmpeg from `argv` directly (a stale fixture), or False."""
    out.parent.mkdir(parents=True, exist_ok=True)
    made = bounded.run(["ffmpeg", "-nostdin", "-v", "error", "-y", *argv, str(out)], 120)
    return made["rc"] == 0 and not made["expired"] and out.exists()


def selftest():
    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    results = {}

    def score(case, ok, detail):
        results[case] = ok
        print(f"{case} {'ok' if ok else 'FAIL'} — {detail}", flush=True)

    try:
        out = WORK / "s1.mov"
        made, why = make(out, ["-f", "lavfi", "-i", SOURCE], CODEC, WANT, "yuv422p10le", 120)
        left = [p.name for p in WORK.iterdir()]
        score("S1", made is None and SETPARAMS in why and not left,
              f"no SETPARAMS: returned {made}, reason names SETPARAMS "
              f"{SETPARAMS in why}, files left {left or 'none'}")

        out = WORK / "s2.mov"
        made, line = make(out, GRAPH, CODEC, WANT, "yuv422p10le", 120)
        probe = stream(out) if made else {}
        score("S2", made == out and all(probe.get(k) == v for k, v in TAG_WANT.items()),
              f"proper graph: {line}")

        out = WORK / "s3.mov"
        pre = prewrite(out, ["-f", "lavfi", "-i", f"{SOURCE},{SMPTE170M}", *CODEC, *FLAGS_170M])
        before = tags(stream(out)) if pre else "not written"
        made, line = make(out, GRAPH, CODEC, WANT, "yuv422p10le", 120)
        probe = stream(out) if made else {}
        score("S3", pre and made == out
              and all(probe.get(k) == v for k, v in TAG_WANT.items()),
              f"pre-written {before}; then {line}; kept file reads "
              f"{tags(probe) if made else 'none'}")

        out = WORK / "s4.mov"
        pre = prewrite(out, ["-f", "lavfi", "-i", f"color=c=gray:size=64x64:rate=30:duration=1,"
                                                  f"{SETPARAMS}", *CODEC, *TAG])
        stale = sha(out) if pre else None
        before = tags(stream(out)) if pre else "not written"
        made, line = make(out, GRAPH, CODEC, WANT, "yuv422p10le", 120)
        kept = sha(out) if made else None
        score("S4", pre and made == out and kept is not None and kept != stale,
              f"pre-written gray {before} sha256 {str(stale)[:16]}; then {line}; kept sha256 "
              f"{str(kept)[:16]}")

        out = WORK / "s5.mov"
        written = prewrite(out, ["-f", "lavfi", "-i", SOURCE, *CODEC, *TAG])
        print(f"S5 RECORD — TAG on the output only: ffprobe reads "
              f"{tags(stream(out)) if written else 'not written'} (transfer/primaries/space)",
              flush=True)
    finally:
        shutil.rmtree(WORK, ignore_errors=True)
    failed = sorted(case for case, ok in results.items() if not ok)
    print(f"selftest{f' (mutant {MUTANT})' if MUTANT else ''}: "
          f"{len(results) - len(failed)}/{len(results)} ok"
          f"{'; failed ' + ', '.join(failed) if failed else ''}", flush=True)
    FAILED.clear()
    FAILED.update(failed)
    return 1 if failed else 0


def main():
    global MUTANT
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--mutant", choices=MUTANTS)
    args = parser.parse_args()
    if not args.selftest:
        parser.error("only --selftest [--mutant NAME] is a command")
    MUTANT = args.mutant
    status = selftest()
    if MUTANT is None:
        return status
    failed = FAILED
    caught = EXPECTED[MUTANT] <= failed
    print(f"mutant {MUTANT}: {'caught' if caught else 'SURVIVED'} (must fail "
          f"{', '.join(sorted(EXPECTED[MUTANT]))}; failed {', '.join(sorted(failed)) or 'none'})",
          flush=True)
    return 0 if caught else 1


if __name__ == "__main__":
    sys.exit(main())
