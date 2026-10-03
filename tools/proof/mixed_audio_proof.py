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
track) exports, over the WHOLE file: since B59 (#87) the WAV's composition
track holds its own first segment's gain from time 0 rather than carrying the
plan track's ramps up to it, so the 25 ms step at 3.000–3.026 s is gone. And
`mixed-muted` — the same pair with the WAV MUTED — is silent from the WAV's
first sample. And `missing-first` (#217, B61) — a copy of the AAC whose file
is then deleted, followed with no gap by the WAV MUTED, on ONE track — is
silent from the WAV's first sample too: the hold ends at the track's first
SOUNDING segment, so the missing lead's empty time is held over rather than
ending the hold at 0 and slewing the plan's 1 → 0 step at the cut (on the
build before the fix that row failed; the numbers are in the README's B61
record). And `pending-first` (#218, B70) — the AAC itself, held PENDING by its
reverse, followed with no gap by the WAV MUTED, on ONE track — is silent from
the WAV's first sample as well. The hold: an EMPTY REGULAR FILE at the
session's `cache/reversed` before `set_reversed`, so no reversed file is found
(`ReverseCache.existing`) and the render's `createDirectory` throws, which
`ReverseRenderer.run` answers as a failure that is never retried; the source
is untouched, so a forward read would be the loud tone (`mixed`'s row) and a
finished reverse the same tone backwards. Its CONTROLs: no missing media,
`cache/reversed` still a file after the export, and the lead's own span
silent. The render's failure sheet stays up on that session's window.

Fixtures are `mixed_audio_probe.py`'s, written fresh by importing it (the
`silence2` pattern). Needs `ffmpeg`. Run against an instance:

    python3 tools/proof/mixed_audio_proof.py <dir>/agent.sock
    python3 tools/proof/mixed_audio_proof.py --mutant old-onset

`--mutant old-onset` builds a tree copy (`tree_copy.make_copy`, under
`work/mixed-audio-mutant`) with the pre-B61 onset (`git show 16d4934`: the
track's first segment of positive duration, sounding or not) in
`CompositionBuilder+AudioTracks.swift`, the anchor asserted once, by the
copy's own `make app`; launches it on a scratch socket of its own
(`mcp.launch`), logging beside that socket; and runs every row against it.
Exit 0 means caught: both `missing-first` and
`pending-first`'s first-25 ms rows FAIL while both sections' CONTROL rows
pass; 1 means it survived; 2 means the control could not be performed (the
copy was not built or not launched, its log has a `Reelcut: ` parity line, or
a CONTROL row failed). Only that child is ever terminated, by its PID.
"""

import argparse
import math
import os
import re
import shutil
import subprocess
import sys
import time
from array import array

import mixed_audio_probe as probe
import mcp as mcp_client
from mcp import MCP, target

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402
import tree_copy  # noqa: E402

SEC = 600_000

MUTANTS = {"old-onset": ("CompositionBuilder+AudioTracks.swift",
                         "onset: family.sounding.map(\\.lowerBound).min(),",
                         "onset: family.segments.filter { $0.duration > 0 }.map(\\.start).min(),")}

failures = []
checks = 0
results = []


def check(ok, what):
    global checks
    checks += 1
    results.append((ok, what))
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


def run(mcp):
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
    ok, w = same(mixed, split, 1)
    differ = f"; the files differ from {w[1]} s to {w[2]} s" if w and w[1] is not None else ""
    check(ok, "mixed exports sample-for-sample as split does over the whole file "
              f"(max |Δ| {w[0] if w else None} ≤ 1{differ})")

    print("\nmixed-muted — the AAC clip then the WAV, MUTED, on ONE track")
    u = Session(mcp, "mixed-audio-muted")
    aac, wav = u.media("aac.m4a"), u.media("pcm.wav")
    track = u.track_ids()[0]
    first = u.place(track, aac, 0)
    at = {c["id"]: c for c in u.project()["clips"]}[first]["duration"]
    second = u.place(track, wav, at)
    u.op("set_audio", clips=[second], patch={"muted": True})
    muted = pcm(u.export_wav())
    w = at / SEC
    edge, rest = db(muted, w, w + 0.025), db(muted, w + 0.025, w + 1.975)
    check(edge <= -60, f"mixed-muted: the WAV's first 25 ms from {w:.3f} s are silent "
                       f"({edge:.1f} dBFS ≤ −60)")
    check(rest <= -60, f"mixed-muted: silent from {w + 0.025:.3f} s to {w + 1.975:.3f} s "
                       f"({rest:.1f} dBFS ≤ −60)")

    print("\nmissing-first — a missing copy of the AAC, then the WAV MUTED, on ONE track")
    for stale in os.listdir(probe.WORK):
        if re.fullmatch(r"gone-\d+\.m4a", stale):
            os.remove(os.path.join(probe.WORK, stale))
    gone = f"gone-{os.getpid()}.m4a"
    shutil.copyfile(os.path.join(probe.WORK, "aac.m4a"), os.path.join(probe.WORK, gone))
    g = Session(mcp, "mixed-audio-missing")
    copy, wav = g.media(gone), g.media("pcm.wav")
    track = g.track_ids()[0]
    first = g.place(track, copy, 0)
    # No gap: the core's envelope is 0 in a gap, which would hide the slew.
    at = {c["id"]: c for c in g.project()["clips"]}[first]["duration"]
    second = g.place(track, wav, at)
    g.op("set_audio", clips=[second], patch={"muted": True})
    os.remove(os.path.join(probe.WORK, gone))
    missing = g.op("get_project").get("missing_media")
    check(missing == [copy], f"CONTROL missing-first: get_project's missing_media is the "
                             f"copy's id ({missing} == {[copy]})")
    lead = pcm(g.export_wav())
    w = at / SEC
    edge, rest = db(lead, w, w + 0.025), db(lead, w + 0.025, w + 1.975)
    check(edge <= -60, f"missing-first: the WAV's first 25 ms from {w:.3f} s are silent "
                       f"({edge:.1f} dBFS ≤ −60)")
    check(rest <= -60, f"missing-first: silent from {w + 0.025:.3f} s to {w + 1.975:.3f} s "
                       f"({rest:.1f} dBFS ≤ −60)")

    print("\npending-first — the AAC held PENDING by its reverse, then the WAV MUTED, on ONE track")
    h = Session(mcp, "mixed-audio-pending")
    aac, wav = h.media("aac.m4a"), h.media("pcm.wav")
    track = h.track_ids()[0]
    first = h.place(track, aac, 0)
    # No gap, as missing-first: the core's envelope is 0 in a gap.
    at = {c["id"]: c for c in h.project()["clips"]}[first]["duration"]
    second = h.place(track, wav, at)
    h.op("set_audio", clips=[second], patch={"muted": True})
    # The hold: a FILE where the reverse's directory would go, so no reversed
    # file is ever found and the render's createDirectory throws.
    cache = os.path.join(h.path, "cache")
    os.makedirs(cache, exist_ok=True)
    hold = os.path.join(cache, "reversed")
    open(hold, "wb").close()
    h.op("set_reversed", clip=first, reversed=True)
    missing = h.op("get_project").get("missing_media")
    check(not missing, f"CONTROL pending-first: get_project has no missing_media ({missing})")
    pending = pcm(h.export_wav())
    held = os.path.isfile(hold) and not os.path.islink(hold)
    check(held, f"CONTROL pending-first: after the export, cache/reversed is still a regular file "
                f"({'file' if held else 'directory' if os.path.isdir(hold) else 'absent'})")
    w = at / SEC
    quiet = db(pending, 0.25, w - 0.25)
    check(quiet <= -60, f"CONTROL pending-first: the pending lead is silent from 0.25 s to "
                        f"{w - 0.25:.3f} s ({quiet:.1f} dBFS ≤ −60; a forward or finished "
                        f"reverse read would be loud)")
    edge, rest = db(pending, w, w + 0.025), db(pending, w + 0.025, w + 1.975)
    check(edge <= -60, f"pending-first: the WAV's first 25 ms from {w:.3f} s are silent "
                       f"({edge:.1f} dBFS ≤ −60)")
    check(rest <= -60, f"pending-first: silent from {w + 0.025:.3f} s to {w + 1.975:.3f} s "
                       f"({rest:.1f} dBFS ≤ −60)")

    print("\nCONTROL same — two AAC clips of one format on one track")
    q = Session(mcp, "mixed-audio-same")
    one, two = q.media("aac.m4a"), q.media("aac2.m4a")
    track = q.track_ids()[0]
    q.place(track, one, 0)
    q.place(track, two, 3 * SEC)
    windows("same", pcm(q.export_wav()), [0, 3])


def fixtures():
    os.makedirs(WORK, exist_ok=True)
    why = probe.make_media()
    if why:
        check(False, f"the fixtures were written: {why}")
    return why


def build_mutant(name):
    """`graphics_proof.build_mutant`'s shape: a tree copy, the anchor asserted
    once in `app/Sources/<file>` and replaced, the copy's own `make app`.
    The binary, or None and why."""
    file, anchor, replacement = MUTANTS[name]
    made, reason = tree_copy.make_copy(os.path.join(WORK, "mixed-audio-mutant"))
    if made is None:
        return None, reason
    target = os.path.join(made, "app", "Sources", file)
    with open(target) as handle:
        text = handle.read()
    if text.count(anchor) != 1:
        return None, f"the anchor occurs {text.count(anchor)} times in {file}"
    with open(target, "w") as handle:
        handle.write(text.replace(anchor, replacement))
    built = bounded.run(["make", "app"], 1500, cwd=made)
    binary = os.path.join(made, "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut")
    if built["rc"] != 0 or not os.path.exists(binary):
        errors = [line for line in (built["stdout"] + built["stderr"]).splitlines()
                  if "error:" in line]
        return None, (f"make app rc {built['rc']} (expired {built['expired']}): "
                      + ("\n      ".join(errors[:6]) or built["stdout"][-600:]))
    return binary, ""


def parity_lines(log_path):
    """The startup parity check's complaints in the child's log."""
    try:
        with open(log_path, errors="replace") as handle:
            return [line for line in handle.read().splitlines() if "Reelcut: " in line]
    except OSError:
        return []


def mutant(name):
    print(f"mixed audio — the {name} MUTANT (both first-25 ms rows must FAIL)", flush=True)

    def uncontrolled(why):
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2

    binary, why = build_mutant(name)
    if binary is None:
        print(f"  FAIL the mutant builds — {why}")
        return uncontrolled(f"the copy was not built: {why}")
    # One owned child on a scratch socket of its own (spec §11 MC-6), its
    # log beside the socket; only this child is ever terminated.
    instance = mcp_client.launch(binary, env=bounded.child_env(), timeout=300)
    try:
        if instance.client is None:
            print("  FAIL the mutant launches")
            return uncontrolled("the copy did not launch")
        print(f"  instance PID {instance.child.pid} at {instance.socket_path}", flush=True)
        parity = parity_lines(instance.log_path)
        if parity:
            return uncontrolled(f"its log has a parity line: {parity[0]}")
        try:
            run(instance.client)
        except Exception as error:  # a run that cannot finish is not a verdict
            return uncontrolled(f"the run raised {type(error).__name__}: {error}")
        parity = parity_lines(instance.log_path)
    finally:
        instance.stop()
        mcp_client.remove_scratch(instance.socket_path)
    print(f"\n{checks - len(failures)}/{checks} checks passed")
    if parity:
        return uncontrolled(f"its log has a parity line: {parity[0]}")
    controls = [(ok, what) for ok, what in results
                if what.startswith(("CONTROL missing-first:", "CONTROL pending-first:"))]
    if len(controls) != 4 or not all(ok for ok, _ in controls):
        bad = [what for ok, what in controls if not ok]
        return uncontrolled(f"{len(controls)} CONTROL rows, failed: {bad}")
    targets = {prefix: [ok for ok, what in results if what.startswith(prefix)]
               for prefix in ("missing-first: the WAV's first 25 ms",
                              "pending-first: the WAV's first 25 ms")}
    caught = all(len(oks) == 1 and not oks[0] for oks in targets.values())
    print(f"mutant {name}: " + ("caught — both first-25 ms rows FAIL, every CONTROL passes"
                                if caught else f"survived — {targets}"))
    return 0 if caught else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("socket", nargs="?",
                        help="the running instance's RC_AGENT_SOCKET (else $RC_AGENT_SOCKET)")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if fixtures():
        print(f"\n{checks - len(failures)}/{checks} checks passed")
        sys.exit(2 if args.mutant else 1)
    if args.mutant:
        sys.exit(mutant(args.mutant))
    run(MCP(target([sys.argv[0], args.socket or ""])))
    passed = checks - len(failures)
    print(f"\n{passed}/{checks} checks passed")
    sys.exit(0 if not failures else 1)


if __name__ == "__main__":
    main()
