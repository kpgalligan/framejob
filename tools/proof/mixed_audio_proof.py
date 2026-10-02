#!/usr/bin/env python3
"""Mixed audio formats on one track (kpgalligan/reelcut#34) — the EXPORT
path's regression guard, driven against the built binary over MCP.

This is NOT the proof of the fix. The defect was the PREVIEW's: a tapped
`AVPlayerItem` over one composition track that changes format part-way
stalled, while the export's reader always played such a track — so every row
here passed on the baseline app too. The proof of the fix is
`mixed_audio_probe.py` section 4, the editor's own `Playback`, which no tool
reaches. What this script claims is that the fix — one composition track per
source format — leaves the EXPORT's sound unchanged: an AAC clip then a WAV
on ONE track exports loud in both and silent between, the WAV at its own
level, and sample-for-sample as the user's workaround (the WAV on a second
track) exports, outside the 25 ms where AVFoundation's mix smooths the plan's
envelope step at the WAV's start — that step sits on `mixed`'s WAV track
(the plan track's ramps, gap included) and not on `split`'s, on the baseline
and the fix alike.

Fixtures are `mixed_audio_probe.py`'s, written fresh by importing it (the
`silence2` pattern). Needs `ffmpeg`. Run against an instance:

    python3 tools/proof/mixed_audio_proof.py <dir>/agent.sock
"""

import math
import os
import re
import shutil
import subprocess
import sys
from array import array

import mixed_audio_probe as probe
from mcp import MCP, target

SOCKET = target(sys.argv)
HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
SEC = 600_000

failures = []
checks = 0


def check(ok, what):
    global checks
    checks += 1
    if ok:
        print(f"  ok   {what}")
    else:
        print(f"  FAIL {what}")
        failures.append(what)


class Session:
    """One project (`phase2_proof.py`'s `Session`, cut to what this needs)."""

    def __init__(self, mcp, name):
        self.mcp = mcp
        self.name = name
        for stale in os.listdir(WORK):
            if re.fullmatch(rf"{re.escape(name)}-\d+\.reelcut", stale):
                shutil.rmtree(os.path.join(WORK, stale))
        self.path = os.path.join(WORK, f"{name}-{os.getpid()}.reelcut")
        mcp.call("new_project", path=self.path)
        self.op("set_canvas", width=640, height=360)

    def op(self, name, **kwargs):
        return self.mcp.call(name, project=self.path, **kwargs)

    def project(self):
        return self.op("get_project")["project"]

    def track_ids(self):
        return [t["id"] for t in self.project()["tracks"]]

    def media(self, file):
        return self.op("import_media", path=os.path.join(probe.WORK, file))["media"]

    def place(self, track, media, at):
        return self.op("add_clip", track=track, media=media, at=int(at))["new_clips"][0]

    def export_wav(self):
        target = os.path.join(WORK, f"{self.name}-{os.getpid()}.wav")
        if os.path.exists(target):
            os.remove(target)
        return self.op("export", preset="audio_wav", path=target)["path"]


def pcm(path):
    """`path` decoded to raw signed 16-bit LE stereo 48 kHz, as bytes — e1's line."""
    out = os.path.splitext(path)[0] + ".pcm"
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", path, "-vn", "-f", "s16le",
         "-acodec", "pcm_s16le", "-ar", "48000", "-ac", "2", out],
        check=True)
    with open(out, "rb") as handle:
        return handle.read()


def samples(data):
    values = array("h")
    values.frombytes(data)
    return values


def wobble(a, b, outside=None):
    """(max |Δ| outside `outside` seconds, first and last differing second),
    or None when the two dumps differ in length."""
    if len(a) != len(b):
        return None
    worst, first, last = 0, None, None
    for i, (p, q) in enumerate(zip(samples(a), samples(b))):
        if p == q:
            continue
        t = i / 2 / 48000
        first = t if first is None else first
        last = t
        if outside is None or not outside[0] <= t < outside[1]:
            worst = max(worst, abs(p - q))
    return worst, first, last


def same(a, b, tolerance, outside=None):
    w = wobble(a, b, outside)
    return w is not None and w[0] <= tolerance, w


def db(data, start, end):
    """RMS in dBFS over [start, end) s of a stereo 48 kHz dump."""
    values = samples(data)[int(start * 48000) * 2:int(end * 48000) * 2]
    if not values:
        return -200.0
    rms = math.sqrt(sum(v * v for v in values) / len(values)) / 32768
    return 20 * math.log10(rms) if rms > 0 else -200.0


def windows(label, data, clips):
    """Loud inside every 2 s clip at `clips` seconds, silent in the gaps."""
    for c in clips:
        level = db(data, c + 0.25, c + 1.75)
        check(level >= -30, f"{label}: loud from {c + 0.25} s to {c + 1.75} s "
                            f"({level:.1f} dBFS ≥ −30)")
    for c, following in zip(clips, clips[1:]):
        level = db(data, c + 2.1, following - 0.1)
        check(level <= -60, f"{label}: silent from {c + 2.1:.1f} s to {following - 0.1:.1f} s "
                            f"({level:.1f} dBFS ≤ −60)")


def main():
    os.makedirs(WORK, exist_ok=True)
    why = probe.make_media()
    if why:
        check(False, f"the fixtures were written: {why}")
        print(f"\n{checks - len(failures)}/{checks} checks passed")
        sys.exit(1)
    mcp = MCP(SOCKET)

    print("mixed — an AAC clip then a WAV on ONE track")
    m = Session(mcp, "mixed-audio")
    aac, wav = m.media("aac.m4a"), m.media("pcm.wav")
    track = m.track_ids()[0]
    first = m.place(track, aac, 0)
    second = m.place(track, wav, 3 * SEC)
    clips = {c["id"]: c for c in m.project()["clips"]}
    check(clips[first]["track"] == track and clips[second]["track"] == track
          and clips[second]["start"] == 3 * SEC,
          f"both clips on track {track}, the WAV at 3 s "
          f"({[(c['id'], c['track'], c['start']) for c in clips.values()]})")
    mixed = pcm(m.export_wav())
    windows("mixed", mixed, [0, 3])
    source = pcm(os.path.join(probe.WORK, "pcm.wav"))
    own, exported = db(source, 0.25, 1.75), db(mixed, 3.25, 4.75)
    check(abs(own - exported) <= 1,
          f"mixed: the WAV exports at its own level ({exported:.2f} dBFS vs the file's "
          f"{own:.2f} dBFS, within 1 dB)")

    print("\nCONTROL split — the WAV on a second track (the workaround)")
    s = Session(mcp, "mixed-audio-split")
    aac, wav = s.media("aac.m4a"), s.media("pcm.wav")
    s.op("add_track", index=1)
    back, front = s.track_ids()[0], s.track_ids()[1]
    s.place(back, aac, 0)
    s.place(front, wav, 3 * SEC)
    split = pcm(s.export_wav())
    windows("split", split, [0, 3])
    ok, w = same(mixed, split, 1, outside=(3.0, 3.026))
    check(ok, "mixed exports sample-for-sample as split does outside the envelope step at "
              f"3.000–3.026 s (max |Δ| {w[0] if w else None} ≤ 1; the files differ from "
              f"{w[1] if w else None} s to {w[2] if w else None} s)")
    check(w is not None and (w[1] is None or (w[1] >= 3.0 and w[2] < 3.026)),
          "…and nowhere outside 3.000–3.026 s")

    print("\nCONTROL same — two AAC clips of one format on one track")
    q = Session(mcp, "mixed-audio-same")
    one, two = q.media("aac.m4a"), q.media("aac2.m4a")
    track = q.track_ids()[0]
    q.place(track, one, 0)
    q.place(track, two, 3 * SEC)
    windows("same", pcm(q.export_wav()), [0, 3])

    passed = checks - len(failures)
    print(f"\n{passed}/{checks} checks passed")
    sys.exit(0 if not failures else 1)


if __name__ == "__main__":
    main()
