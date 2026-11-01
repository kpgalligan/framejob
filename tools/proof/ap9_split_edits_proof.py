#!/usr/bin/env python3
"""Road map "audio" AP9 — split edits (J- and L-cuts) that keep sync, and
Attach Audio (spec §11 AU-90…AU-97), driven over MCP and measured in the
exports.

    python3 tools/proof/ap9_split_edits_proof.py <dir>/agent.sock [--only A1,A2,...]

The fixture is made once under `tools/proof/work/ap9/` (`fixture-v1.mov`):
10 s at 30 fps, 640×360, a gray picture with a white flash frame at frames
45, 90, …, 270 and, at those same instants, a click (the raised-cosine
click `export_offset_proof.py` locates), over a continuous 440 Hz tone at
0.1. The picture is ProRes and the sound 48 kHz 16-bit PCM, written by
ffmpeg; the tone and clicks by Python.

Every export is `prores_422` (A6's two are `audio_wav`) and is decoded with
ffmpeg through `export_offset_proof.py`'s `read_ffmpeg` and `flash_times`
(imported, never copied). The tolerance is that file's E-row tolerance,
`TARGET_MS`: an offset is held to it, and every click to its flash.

- A0: no `Frame Job: ` line in the instance's log (the parity check).
- A1: `detach_audio` → `linked` mutual over `get_project`.
- A2: the J-cut (the sound's `trim_start` alone 15 frames early, after a
  one-second carried head trim): tone onset − first picture frame = −0.5 s.
- A3: the L-cut (the picture's `trim_end` with `alone: true` 15 frames
  early): tone offset − last picture frame's end = +0.5 s.
- A4: after `move_clip` on the picture, `ripple_delete` of a silent, hidden
  clip before the pair, `split` + `delete` of the first halves, and `nest`,
  each export keeps the L offset (+0.5 s), the J offset (−0.5 s until the
  split takes the lead away, 0 after), and every click within the tolerance
  of its flash.
- A5: `set_speed` on a half refused in AU-94's sentence; `attach_audio` on
  the J-cut refused in AU-95's.
- A6: `attach_audio` on an in-step pair → one clip, and its `audio_wav`
  export equals a never-detached clip's sample for sample within −90 dBFS.
- A7: `undo` restores the pair, linked.
- A8: two consecutive detached shots, the second's sound moved to a new
  track and J-cut 15 frames: its picture stays on its track, the sound has
  no `transition_in`, and every click in the export is on its flash.
- A9: `delete` of a detached sound alone: the picture stays, `linked`
  absent, its export silent.

Every project is closed with `discard: true`; no menu item is performed.
Prints `<ID> ok|FAIL — <detail>`, then `scores: n/m`; exit 0 iff every row
asked for passed.
"""

import argparse
import array
import math
import os
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools/proof"
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
from export_offset_proof import TARGET_MS, click_value, flash_times, locate, read_ffmpeg  # noqa: E402
from mcp import MCP, ToolError, log_beside  # noqa: E402

WORK = HERE / "work/ap9"
EXPORTS = WORK / "exports"
FIXTURE = WORK / "fixture-v1.mov"
SEC = 600_000
FRAME = SEC // 30
RATE = 48_000
LENGTH_S = 10
FLASH_FRAMES = [45 * k for k in range(1, 7)]
TONE = 0.1
ONSET = 0.02  # |x| over this is the tone (or a click) sounding
PICTURE = 32  # a frame's mean luma over this is the picture, not the black canvas
FLASH = 200  # and over this, a flash
SILENT_DB = -90.0
ROWS = [f"A{n}" for n in range(10)]
TOL = TARGET_MS / 1000

results: dict = {}


def score(row, ok, detail):
    results[row] = (bool(ok), detail)
    print(f"{row} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


def run(argv, seconds=240):
    ran = bounded.run([str(a) for a in argv], seconds)
    if ran["expired"] or ran["rc"] != 0:
        raise RuntimeError(f"{Path(str(argv[0])).name}: {(ran['stderr'] or '').strip()[-300:]}")
    return ran


# ---- the fixture -----------------------------------------------------------


def make_fixture():
    if FIXTURE.exists():
        return FIXTURE
    WORK.mkdir(parents=True, exist_ok=True)
    wav = WORK / "fixture-v1.wav"
    h = RATE / 2000
    clicks = [round(f / 30 * RATE) for f in FLASH_FRAMES]
    samples = array.array("h")
    for n in range(LENGTH_S * RATE):
        x = TONE * math.sin(2 * math.pi * 440 * n / RATE)
        for c in clicks:
            if abs(n - c) < h:
                x += click_value(n - c, h)
        samples.append(int(round(max(-1.0, min(1.0, x)) * 32767)))
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(samples.tobytes())
    flash = "+".join(f"eq(n\\,{f})" for f in FLASH_FRAMES)
    partial = WORK / "fixture-v1.partial.mov"
    run(["ffmpeg", "-v", "error", "-y",
         "-f", "lavfi", "-i", f"color=c=gray:s=640x360:r=30:d={LENGTH_S}",
         "-i", wav,
         "-vf", f"drawbox=x=0:y=0:w=iw:h=ih:color=white:t=fill:enable='{flash}'",
         "-c:v", "prores_ks", "-profile:v", "0", "-pix_fmt", "yuv422p10le",
         "-c:a", "pcm_s16le", "-shortest", partial])
    wav.unlink(missing_ok=True)
    partial.rename(FIXTURE)
    return FIXTURE


# ---- measuring an export ---------------------------------------------------


def has_audio(path):
    ran = run(["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries",
               "stream=index", "-of", "csv=p=0", path])
    return bool(ran["stdout"].strip())


def measure(path):
    """The picture's first frame and last frame's end, the sound's onset and
    offset, and each flash's click offset (s)."""
    frames = flash_times(path, PICTURE)
    flashes = flash_times(path, FLASH)
    samples, rate = read_ffmpeg(path)
    loud = [i for i, x in enumerate(samples) if abs(x) > ONSET]
    found = locate(samples, rate, flashes)
    return {
        "first": frames[0] if frames else None,
        "end": frames[-1] + 1 / 30 if frames else None,
        "onset": loud[0] / rate if loud else None,
        "offset": (loud[-1] + 1) / rate if loud else None,
        "flashes": len(flashes),
        "av": [None if f is None else f - t for (f, _), t in zip(found, flashes)],
    }


def offsets_ok(m, head, tail, flashes_wanted):
    """(ok, sentence): the J offset `head`, the L offset `tail` (None skips
    one), and every flash's click inside the tolerance."""
    parts = []
    ok = m["first"] is not None and m["onset"] is not None
    if head is not None and ok:
        j = m["onset"] - m["first"]
        ok &= abs(j - head) <= TOL
        parts.append(f"onset − first frame {j:+.4f} s (want {head:+.1f})")
    if tail is not None and ok:
        lo = m["offset"] - m["end"]
        ok &= abs(lo - tail) <= TOL
        parts.append(f"offset − picture end {lo:+.4f} s (want {tail:+.1f})")
    av = m["av"]
    clicks_ok = len(av) >= flashes_wanted and all(v is not None and abs(v) <= TOL for v in av)
    ok &= clicks_ok
    worst = max((abs(v) for v in av if v is not None), default=None)
    parts.append(f"{len(av)} flashes, worst |click − flash| "
                 + ("—" if worst is None else f"{worst * 1000:.3f} ms")
                 + f" (≤ {TARGET_MS} ms)")
    return ok, "; ".join(parts)


# ---- the app's projects ----------------------------------------------------


class Session:
    def __init__(self, mcp, name):
        self.mcp = mcp
        self.path = str(WORK / f"{name}-{os.getpid()}.framejob")
        mcp.call("new_project", path=self.path)
        self.op("set_canvas", width=640, height=360, fps=30)
        self.media_id = None

    def op(self, name, **kwargs):
        if name == "export":
            return self.mcp.export(project=self.path, **kwargs)
        return self.mcp.call(name, project=self.path, **kwargs)

    def project(self):
        return self.op("get_project")["project"]

    def clips(self):
        return {c["id"]: c for c in self.project()["clips"]}

    def place(self, at, track=None):
        if self.media_id is None:
            self.media_id = self.op("import_media", path=str(FIXTURE))["media"]
        track = track or self.project()["tracks"][-1]["id"]
        return self.op("add_clip", track=track, media=self.media_id, at=at)["new_clips"][0]

    def detach(self, clip):
        self.op("detach_audio", clip=clip)
        return self.clips()[clip]["linked"]

    def export(self, tag, preset="prores_422"):
        EXPORTS.mkdir(parents=True, exist_ok=True)
        out = EXPORTS / f"{tag}.{'wav' if preset == 'audio_wav' else 'mov'}"
        out.unlink(missing_ok=True)
        self.op("export", preset=preset, path=str(out))
        return out

    def close(self):
        try:
            self.op("close_project", discard=True)
        except ToolError:
            pass


def refused(fn, sentence):
    try:
        fn()
    except ToolError as error:
        return sentence in str(error), str(error)
    return False, "applied"


# ---- the rows --------------------------------------------------------------


def main_pair(mcp):
    """A1–A5 on one project: a silent, hidden filler (0–1 s), then the pair."""
    s = Session(mcp, "ap9-pair")
    try:
        filler = s.place(0)
        s.op("trim_end", clip=filler, to=SEC)
        s.op("set_enabled", clip=filler, video=False, audio=False)
        p = s.place(2 * SEC)
        sound = s.detach(p)
        clips = s.clips()
        score("A1", clips[p].get("linked") == sound and clips[sound].get("linked") == p,
              f"picture {p} linked {clips[p].get('linked')}, sound {sound} linked "
              f"{clips[sound].get('linked')}")
        # A carried head trim (both halves), then the sound's lead.
        s.op("trim_start", clip=p, to=3 * SEC)
        s.op("trim_start", clip=sound, to=3 * SEC - 15 * FRAME, alone=True)
        m = measure(s.export("a2"))
        ok, detail = offsets_ok(m, -0.5, None, 6)
        score("A2", ok, detail)

        end = s.clips()[p]["start"] + s.clips()[p]["duration"]
        s.op("trim_end", clip=p, to=end - 15 * FRAME, alone=True)
        m = measure(s.export("a3"))
        ok, detail = offsets_ok(m, -0.5, 0.5, 5)
        score("A3", ok, detail)

        speed = refused(lambda: s.op("set_speed", clip=p, rate=2.0),
                        f"clip {p} is linked to clip {sound}: Attach Audio before changing "
                        "its speed or direction")
        attach = refused(lambda: s.op("attach_audio", clip=sound),
                         f"clip {p}'s picture and clip {sound}'s sound do not cover the same "
                         "time; trim them to match before Attach Audio")
        score("A5", speed[0] and attach[0], f"set_speed: {speed[1]}; attach_audio: {attach[1]}")

        steps = []
        s.op("move_clip", clips=[p], delta=SEC)
        steps.append(("move", -0.5, measure(s.export("a4-move"))))
        s.op("ripple_delete", clips=[filler])
        steps.append(("ripple", -0.5, measure(s.export("a4-ripple"))))
        cut = s.clips()[p]["start"] + 2 * SEC
        s.op("split", clips=[p], at=cut)
        s.op("delete", clips=[p])
        left = s.clips()
        second = next(c for c in left.values() if c["start"] == cut and c["enabled"]["video"])
        steps.append(("split+delete", 0.0, measure(s.export("a4-split"))))
        s.op("nest", clips=[second["id"]])
        steps.append(("nest", 0.0, measure(s.export("a4-nest"))))
        oks, parts = [], []
        for name, head, m in steps:
            ok, detail = offsets_ok(m, head, 0.5, 3)
            oks.append(ok)
            parts.append(f"{name}: {detail}")
        score("A4", all(oks) and len(oks) == 4, " | ".join(parts))
    finally:
        s.close()


def attach_rows(mcp):
    """A6 and A7."""
    a = Session(mcp, "ap9-attach")
    b = Session(mcp, "ap9-plain")
    try:
        p = a.place(0)
        sound = a.detach(p)
        a.op("attach_audio", clip=sound)
        clips = a.clips()
        one = list(clips) == [p] and "linked" not in clips[p] and clips[p]["enabled"]["audio"]
        attached, _ = read_ffmpeg(a.export("a6-attached", "audio_wav"))
        b.place(0)
        plain, _ = read_ffmpeg(b.export("a6-plain", "audio_wav"))
        n = min(len(attached), len(plain))
        worst = max((abs(x - y) for x, y in zip(attached[:n], plain[:n])), default=1.0)
        db = 20 * math.log10(worst) if worst > 0 else float("-inf")
        same = len(attached) == len(plain) and db <= SILENT_DB
        score("A6", one and same,
              f"one clip {one}; {len(attached)} / {len(plain)} samples, worst difference "
              f"{db:.1f} dBFS (≤ {SILENT_DB})")

        a.op("undo")
        clips = a.clips()
        back = clips.get(p, {}).get("linked") == sound and clips.get(sound, {}).get("linked") == p
        score("A7", back, f"after undo: {sorted(clips)} linked "
                          f"{[clips[c].get('linked') for c in sorted(clips)]}")
    finally:
        a.close()
        b.close()


def consecutive(mcp):
    """A8."""
    s = Session(mcp, "ap9-consecutive")
    try:
        p1 = s.place(0)
        p2 = s.place(10 * SEC)
        s.detach(p1)
        s2 = s.detach(p2)
        s.op("trim_start", clip=p2, to=11 * SEC)
        s.op("move_clip", clips=[p2], delta=-SEC)
        before = {t["id"] for t in s.project()["tracks"]}
        s.op("add_track")
        new_track = next(t["id"] for t in s.project()["tracks"] if t["id"] not in before)
        picture_track = s.clips()[p2]["track"]
        s.op("move_clip", clips=[s2], delta=0, track=new_track)
        s.op("trim_start", clip=s2, to=10 * SEC - 15 * FRAME, alone=True)
        clips = s.clips()
        placed = (clips[p2]["track"] == picture_track and clips[s2]["track"] == new_track
                  and clips[s2].get("transition_in") is None
                  and clips[s2]["start"] == 10 * SEC - 15 * FRAME)
        m = measure(s.export("a8"))
        ok, detail = offsets_ok(m, None, None, 10)
        score("A8", placed and ok,
              f"picture {p2} on track {clips[p2]['track']} (was {picture_track}), sound {s2} on "
              f"{clips[s2]['track']} at {clips[s2]['start']} with transition_in "
              f"{clips[s2].get('transition_in')}; {detail}")
    finally:
        s.close()


def sound_alone(mcp):
    """A9."""
    s = Session(mcp, "ap9-silent")
    try:
        p = s.place(0)
        sound = s.detach(p)
        s.op("delete", clips=[sound])
        clips = s.clips()
        kept = list(clips) == [p] and "linked" not in clips[p]
        out = s.export("a9")
        if has_audio(out):
            samples, _ = read_ffmpeg(out)
            peak = max((abs(x) for x in samples), default=0.0)
        else:
            peak = 0.0
        db = 20 * math.log10(peak) if peak > 0 else float("-inf")
        score("A9", kept and db <= SILENT_DB,
              f"clips {sorted(clips)}, picture linked {clips.get(p, {}).get('linked')}; "
              f"export peak {db:.1f} dBFS (≤ {SILENT_DB})")
    finally:
        s.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("socket")
    parser.add_argument("--only", help="comma-separated row ids")
    args = parser.parse_args()
    wanted = args.only.split(",") if args.only else list(ROWS)
    unknown = [row for row in wanted if row not in ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    WORK.mkdir(parents=True, exist_ok=True)
    try:
        make_fixture()
        mcp = MCP(args.socket)
    except Exception as error:  # an instrument failure is a scored FAIL of every row
        for row in wanted:
            score(row, False, f"not run: {type(error).__name__}: {error}")
        mcp = None
    if mcp is not None:
        groups = [({"A1", "A2", "A3", "A4", "A5"}, lambda: main_pair(mcp)),
                  ({"A6", "A7"}, lambda: attach_rows(mcp)),
                  ({"A8"}, lambda: consecutive(mcp)),
                  ({"A9"}, lambda: sound_alone(mcp))]
        for rows, fn in groups:
            if not rows & set(wanted):
                continue
            try:
                fn()
            except Exception as error:
                for row in sorted(rows):
                    if row not in results:
                        score(row, False, f"{type(error).__name__}: {error}")
    if "A0" in wanted:
        log = Path(log_beside(args.socket))
        lines = [line for line in (log.read_text(errors="replace").splitlines()
                                   if log.exists() else [])
                 if "Frame Job: " in line]
        score("A0", log.exists() and not lines,
              f"{log}: {len(lines)} 'Frame Job: ' lines" + (f", first {lines[0]!r}" if lines else ""))
    passed = sum(1 for row in wanted if results.get(row, (False,))[0])
    print(f"scores: {passed}/{len(wanted)}")
    return 0 if passed == len(wanted) else 1


if __name__ == "__main__":
    sys.exit(main())
