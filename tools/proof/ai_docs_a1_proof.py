#!/usr/bin/env python3
"""ai-docs a1 — the playhead past the last media clip (#523) and the Loop's wrap hold (#520).

    python3 tools/proof/ai_docs_a1_proof.py [--only P1,W1,…] [--app PATH]

Over MCP on one launch (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`) on a scratch
`CFFIXED_USER_HOME` under `tools/proof/work/ai-docs-a1/`. Media: `tools/proof/media/A.mov` (10 s,
picture only), `AV.mov` (5 s, picture and sound) and `vonly.mov`, a 5 s `testsrc` at 30 fps with no
audio stream, made with ffmpeg under the work folder. It prints the default output device's name and
transport first, since the #520 rows time the player and a Bluetooth output delays the sound.

Rows marked [B] are red before the fix; C rows are CONTROLS; MEASURE rows are printed, never scored.
A playhead is read back through `get_project` after a 1 s wait.

**#523.** Fixture S: A.mov at 0 on V1, a shape 10–17 s and a text 17–20 s on V1. Fixture U: the
same two clips on a second track.
- P1 [B] S and U, 3 rounds each: from 2 s, `set_playhead` 16 s reads 16.0.
- P2 [B] S: from 2 s, each of 11, 14 and 20 s reads itself; 22.9 s reads 20.0.
- P3 [B] S, 3 rounds: held at 16 s (asked twice from 2 s, so the base holds it too), `set_video
  {x}` on the shape, then `undo`: 16.0 after each.
- P4 [B] S: from 2 s, `play_preview {seconds: 2, seek_to: 16 s}` (the ruler's seek): `to` > 16.2 s.
- P5 [B] S: `set_playhead` 9 s, `play_preview {seconds: 3}`: `to` > 10.5 s.
- X1 S: an `h264` export; ffprobe's video stream duration is 20 s ± one frame.
- P6 [B] S: from 2 s, `set_playhead` 20 s, `insert_graphic {name: "lower-third", from:
  "template"}`: the new clip's `start` is 20 s.
- P7 [B] vonly.mov at 0 on V1 and a shape 5–8 s (no audio track, so the placeholder's id must not
  take V1's): `set_playhead` 6.5 s reads 6.5, and `play_preview {seconds: 1}` from 6 s answers with
  `to` > 6.3 s.
- C1 control: A.mov alone, `set_playhead` 12 s reads 10.0.
- C2 control: a shape 0–3 s alone, `play_preview {seconds: 2}` from 0: `to` ≥ 1.0 s.

**#520** (measured, not fixed: the issue stays open). `play_preview` runs on the server thread,
times its own wall clock and answers the player's own `to`, so a hold is wall time the player's
clock did not advance. lone is one AV.mov, pair is AV.mov twice with the loop on the first clip
(it ends before the timeline does); Loop is Clip ▸ Motion ▸ Preview. 3 trials a measurement;
D is the start deficit, wall − (to − from) of a 4 s play from 0 that does not wrap.
- W1 MEASURE lone, Loop on: per-wrap hold of a 13 s play (two wraps) = (wall − (to − from) −
  2·5 s − D) / 2.
- W2 MEASURE pair, Loop on: as W1.
- W3 MEASURE lone and pair: a 16 s poll of `get_project` as fast as the socket answers; each
  wrap's run of readings at the loop start, in seconds.
- W4 control: pair, Loop off, a 4 s play from 0: `to` ≥ 3.0 s; prints D.
- W5 MEASURE pair, Loop off: `play_preview {seconds: 6, seek_to: 0}` from 0; seek hold = wall −
  (seek_from − from) − to − D.
- W6 MEASURE: W5 and W1 on lone with the clip's sound off (`set_enabled {audio: false}`).
- W7 MEASURE: W4, W5 and W1 on one vonly.mov (no audio stream).
- Z1 the launch's `grep "Frame Job: "` prints nothing.

What this does not measure: a real mouse click on the ruler, the picture or the sound at a wrap
(`docs/manual-checks.md` PB-15, PB-18).
"""

import argparse
import json
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402

WORK = ROOT / "tools/proof/work/ai-docs-a1"
HOME = WORK / "home"
MEDIA = WORK / "media"
A_MOV = ROOT / "tools/proof/media/A.mov"
AV_MOV = ROOT / "tools/proof/media/AV.mov"
VONLY = MEDIA / "vonly.mov"
SEC = 600_000
CALL_BOUND = 600
TRIALS = 3
LOOP = 5.0
POLL_WATCH = 16.0
EPS = 0.0005

PLAYHEAD_ROWS = ["P1", "P2", "P3", "P4", "P5", "X1", "P6", "P7", "C1", "C2"]
LOOP_ROWS = ["W1", "W2", "W3", "W4", "W5", "W6", "W7"]
MEASURE_ROWS = {"W1", "W2", "W3", "W5", "W6", "W7"}
ROWS = PLAYHEAD_ROWS + LOOP_ROWS + ["Z1"]

selected = set(ROWS)
results = {}


def check(name, ok, detail=""):
    if name not in selected:
        return
    results[name] = bool(ok)
    print(f"  {'ok  ' if ok else 'FAIL'} {name}" + (f"\n       {detail}" if detail else ""),
          flush=True)


def measure(name, detail):
    if name not in selected:
        return
    print(f"  MEASURE {name}\n       {detail}", flush=True)


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True, timeout=120)


def make_media():
    MEDIA.mkdir(parents=True, exist_ok=True)
    ffmpeg("-f", "lavfi", "-i", "testsrc=size=640x360:rate=30:duration=5",
           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-an", str(VONLY))


def output_device():
    """The default output device's name and transport, from system_profiler."""
    try:
        text = subprocess.run(["system_profiler", "SPAudioDataType"], capture_output=True,
                              text=True, timeout=60).stdout
    except (OSError, subprocess.SubprocessError) as error:
        return f"unknown ({error})"
    name, transports, default = None, {}, None
    for line in text.splitlines():
        stripped = line.strip()
        indent = len(line) - len(line.lstrip())
        if stripped.endswith(":") and indent == 8:
            name = stripped[:-1]
        elif stripped.startswith("Transport:") and name:
            transports[name] = stripped.split(":", 1)[1].strip()
        elif stripped == "Default Output Device: Yes":
            default = name
    return f"{default} ({transports.get(default, 'transport unknown')})" if default else "not found"


# ---- the document --------------------------------------------------------------------------


class Doc:
    def __init__(self, client, name):
        self.client = client
        self.path = str(WORK / f"{name}.framejob")
        self.a = {"project": self.path}
        client.call("new_project", path=self.path)
        self.v1 = self.state()["project"]["tracks"][0]["id"]

    def state(self):
        return self.client.call_with("get_project", self.a)

    def playhead(self):
        return self.state()["playhead"] / SEC

    def seek(self, t, wait=1.0):
        self.client.call_with("set_playhead", {**self.a, "t": int(round(t * SEC))})
        time.sleep(wait)
        return self.playhead()

    def media(self, file):
        return self.client.call_with("import_media", {**self.a, "path": str(file)})["media"]

    def clip(self, media, at, track=None):
        return self.client.call_with("add_clip", {**self.a, "track": track or self.v1,
                                                  "media": media, "at": at})["new_clips"][0]

    def shape(self, track, at, duration):
        return self.client.call_with("add_shape_clip", {**self.a, "track": track,
                                                        "at": int(at * SEC),
                                                        "duration": int(duration * SEC)})[
            "new_clips"][0]

    def text(self, track, at, duration):
        return self.client.call_with("add_text_clip", {**self.a, "track": track,
                                                       "at": int(at * SEC),
                                                       "duration": int(duration * SEC),
                                                       "text": "Past"})["new_clips"][0]

    def play(self, seconds, seek_to=None, start=0.0):
        self.client.call_with("set_playhead", {**self.a, "t": int(round(start * SEC))})
        time.sleep(0.6)
        args = {**self.a, "seconds": seconds}
        if seek_to is not None:
            args["seek_to"] = int(round(seek_to * SEC))
        run = self.client.call_with("play_preview", args)
        return run["from"] / SEC, run["to"] / SEC, run["wall_seconds"], run

    def close(self):
        self.client.call("close_project", project=self.path, discard=True)


# ---- #523 ----------------------------------------------------------------------------------


def titles_doc(client, name, same_track):
    doc = Doc(client, name)
    doc.clip(doc.media(A_MOV), 0)
    track = doc.v1 if same_track else client.call_with("add_track", doc.a)["new_tracks"][0]
    shape = doc.shape(track, 10, 7)
    doc.text(track, 17, 3)
    time.sleep(2)
    print(f"  [{name}] duration {doc.state()['duration'] / SEC:.3f} s", flush=True)
    return doc, shape


def p1_rounds(doc):
    rounds = []
    for _ in range(3):
        doc.seek(2)
        rounds.append(round(doc.seek(16), 6))
    return rounds


def playhead_rows(client):
    s, shape = titles_doc(client, "S", True)
    if "P1" in selected:
        u, _ = titles_doc(client, "U", False)
        on_u = p1_rounds(u)
        u.close()
        on_s = p1_rounds(s)
        check("P1", all(abs(v - 16) < EPS for v in on_s + on_u),
              f"from 2 s, asking 16 s read: S {on_s}, U {on_u}")
    if "P2" in selected:
        got = {}
        for target in (11, 14, 20, 22.9):
            s.seek(2)
            got[target] = round(s.seek(target), 6)
        want = {11: 11, 14: 14, 20: 20, 22.9: 20}
        check("P2", all(abs(got[t] - want[t]) < EPS for t in want),
              f"from 2 s, asked → read: {got}")
    if "P3" in selected:
        reads = []
        for rnd in range(1, 4):
            s.seek(2)
            s.seek(16)
            held = s.seek(16)
            client.call_with("set_video", {**s.a, "clips": [shape], "patch": {"x": 40 * rnd}})
            time.sleep(1.0)
            after = s.playhead()
            client.call_with("undo", s.a)
            time.sleep(1.0)
            reads.append((round(held, 6), round(after, 6), round(s.playhead(), 6)))
        check("P3", all(abs(v - 16) < EPS for r in reads for v in r),
              f"(held, after set_video x, after undo) per round: {reads}")
    if "P4" in selected:
        f, t, w, run = s.play(2, seek_to=16, start=2)
        check("P4", t > 16.2, f"from {f:.3f}, seek_from {run.get('seek_from', 0) / SEC:.3f}, "
                              f"seek_to 16 s, to {t:.6f}, wall {w:.3f}")
    if "P5" in selected:
        f, t, w, _ = s.play(3, start=9)
        check("P5", t > 10.5, f"from {f:.3f}, played 3 s: to {t:.6f}, wall {w:.3f}")
    if "X1" in selected:
        out = WORK / "x1"
        answer = client.export(project=s.path, preset="h264", path=str(out))
        probe = json.loads(subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
             "stream=duration,r_frame_rate", "-of", "json", answer["path"]],
            capture_output=True, text=True, timeout=60, check=True).stdout)["streams"][0]
        num, den = (int(x) for x in probe["r_frame_rate"].split("/"))
        frame = den / num
        duration = float(probe["duration"])
        check("X1", abs(duration - 20) <= frame + 1e-6,
              f"video stream duration {duration:.6f} s (one frame {frame:.6f} s)")
    if "P6" in selected:
        s.seek(2)
        s.seek(20)
        graphic = client.call_with("insert_graphic", {**s.a, "name": "lower-third",
                                                      "from": "template"})["new_clips"][0]
        time.sleep(1)
        clips = {cl["id"]: cl for cl in s.state()["project"]["clips"]}
        start = clips[graphic]["start"] / SEC
        check("P6", abs(start - 20) < EPS, f"the graphic's start {start:.6f} s")
    s.close()

    if "P7" in selected:
        doc = Doc(client, "vonly-shape")
        doc.clip(doc.media(VONLY), 0)
        doc.shape(doc.v1, 5, 3)
        time.sleep(2)
        doc.seek(2)
        read = doc.seek(6.5)
        try:
            f, t, w, _ = doc.play(1, start=6)
            played = f"from {f:.3f}, to {t:.6f}, wall {w:.3f}"
            ok = t > 6.3
        except mcp.ToolError as error:
            played, ok = f"refused: {error}", False
        check("P7", abs(read - 6.5) < EPS and ok, f"asked 6.5 s read {read:.6f}; play {played}")
        doc.close()
    if "C1" in selected:
        doc = Doc(client, "a-alone")
        doc.clip(doc.media(A_MOV), 0)
        time.sleep(2)
        doc.seek(2)
        read = doc.seek(12)
        check("C1", abs(read - 10) < EPS, f"asked 12 s on a 10 s timeline read {read:.6f}")
        doc.close()
    if "C2" in selected:
        doc = Doc(client, "shape-alone")
        doc.shape(doc.v1, 0, 3)
        time.sleep(2)
        f, t, w, _ = doc.play(2)
        check("C2", t >= 1.0, f"from {f:.3f}, to {t:.6f}, wall {w:.3f}")
        doc.close()


# ---- #520 ----------------------------------------------------------------------------------


def loop_doc(client, name, file, clips):
    doc = Doc(client, name)
    media = doc.media(file)
    ids, at = [], 0
    for _ in range(clips):
        ids.append(doc.clip(media, at))
        at = doc.state()["duration"]
    time.sleep(2)
    return doc, ids


def loop_on(doc, clip):
    doc.client.call_with("set_selection", {**doc.a, "clips": [clip]})
    doc.client.call_with("perform_menu_item", {**doc.a, "path": ["Clip", "Motion", "Preview"]})


def loop_on_paused(doc, clip):
    loop_on(doc, clip)
    time.sleep(1)
    doc.client.call_with("play_preview", {**doc.a, "seconds": 0.5})   # ends paused


def deficits(doc):
    """D per trial: wall − (to − from) of a 4 s play from 0, and the `to`s."""
    runs = [doc.play(4) for _ in range(TRIALS)]
    return [w - (t - f) for f, t, w, _ in runs], [t for _, t, _, _ in runs]


def wrap_holds(doc, base):
    holds = []
    for _ in range(TRIALS):
        f, t, w, _ = doc.play(13)
        holds.append((w - (t - f) - 2 * LOOP - base) / 2)
    return holds


def seek_holds(doc, base):
    holds = []
    for _ in range(TRIALS):
        f, t, w, run = doc.play(6, seek_to=0)
        holds.append(w - (run["seek_from"] / SEC - f) - t - base)
    return holds


def poll_holds(doc, clip):
    """Each wrap's run of readings at the loop start, in seconds, over a 16 s poll."""
    loop_on(doc, clip)
    t0 = time.monotonic()
    samples = []
    while time.monotonic() - t0 < POLL_WATCH:
        before = time.monotonic()
        value = doc.playhead()
        samples.append(((before + time.monotonic()) / 2 - t0, value))
    doc.client.call_with("play_preview", {**doc.a, "seconds": 0.5})   # ends paused
    holds = []
    for i in range(1, len(samples)):
        if samples[i][1] < samples[i - 1][1] - 0.5:
            j = i
            while j < len(samples) and samples[j][1] <= EPS:
                j += 1
            if j == len(samples):
                break
            holds.append(samples[j][0] - samples[i][0])
    return holds, len(samples)


def fmt(values):
    return "[" + ", ".join(f"{v:.3f}" for v in values) + "]"


def loop_rows(client):
    if {"W2", "W3", "W4", "W5"} & selected:
        doc, (first, _) = loop_doc(client, "pair", AV_MOV, 2)
        off, tos = deficits(doc)
        d_off = statistics.median(off)
        check("W4", all(t >= 3.0 for t in tos), f"Loop off, 4 s from 0: to {fmt(tos)}; D "
                                                f"{fmt(off)}, median {d_off:.3f} s")
        if "W5" in selected:
            holds = seek_holds(doc, d_off)
            measure("W5", f"seek holds {fmt(holds)}, median {statistics.median(holds):.3f} s")
        loop_on_paused(doc, first)
        if "W2" in selected:
            on, _ = deficits(doc)
            holds = wrap_holds(doc, statistics.median(on))
            measure("W2", f"D {fmt(on)}; per-wrap holds {fmt(holds)}, median "
                          f"{statistics.median(holds):.3f} s")
        pair_poll = poll_holds(doc, first) if "W3" in selected else None
        doc.close()
    if {"W1", "W3"} & selected:
        doc, (lone,) = loop_doc(client, "lone", AV_MOV, 1)
        loop_on_paused(doc, lone)
        if "W1" in selected:
            on, _ = deficits(doc)
            holds = wrap_holds(doc, statistics.median(on))
            measure("W1", f"D {fmt(on)}; per-wrap holds {fmt(holds)}, median "
                          f"{statistics.median(holds):.3f} s")
        if "W3" in selected:
            lone_poll = poll_holds(doc, lone)
            measure("W3", f"runs at the loop start: pair {fmt(pair_poll[0])} "
                          f"({pair_poll[1]} readings), lone {fmt(lone_poll[0])} "
                          f"({lone_poll[1]} readings)")
        doc.close()
    for row, name, file, mute in (("W6", "lone-muted", AV_MOV, True),
                                  ("W7", "vonly", VONLY, False)):
        if row not in selected:
            continue
        doc, (clip,) = loop_doc(client, name, file, 1)
        if mute:
            client.call_with("set_enabled", {**doc.a, "clip": clip, "audio": False})
            time.sleep(1)
        off, tos = deficits(doc)
        seeks = seek_holds(doc, statistics.median(off))
        loop_on_paused(doc, clip)
        on, _ = deficits(doc)
        wraps = wrap_holds(doc, statistics.median(on))
        measure(row, f"Loop off: D {fmt(off)} (to {fmt(tos)}), seek holds {fmt(seeks)} median "
                     f"{statistics.median(seeks):.3f} s; Loop on: D {fmt(on)}, per-wrap holds "
                     f"{fmt(wraps)} median {statistics.median(wraps):.3f} s")
        doc.close()


# ---- The launch ----------------------------------------------------------------------------


def with_instance(binary):
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), [],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in selected - {"Z1"} - MEASURE_ROWS:
                check(row, False, "the app did not listen")
            return
        print(f"  instance PID {launched.child.pid}", flush=True)
        if selected & set(PLAYHEAD_ROWS):
            playhead_rows(launched.client)
        if selected & set(LOOP_ROWS):
            loop_rows(launched.client)
    finally:
        launched.stop()
    lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    check("Z1", not lines, f"grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("Z1")
    shutil.rmtree(WORK, ignore_errors=True)
    HOME.mkdir(parents=True)
    make_media()

    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    print(f"ai-docs a1 on {binary}", flush=True)
    print(f"  default output: {output_device()}", flush=True)
    try:
        with_instance(binary)
    except (mcp.ToolError, OSError, KeyError, subprocess.SubprocessError) as error:
        print(f"  the run stopped: {type(error).__name__}: {error}", flush=True)
    missing = [row for row in sorted(selected - MEASURE_ROWS) if row not in results]
    for row in missing:
        results[row] = False
        print(f"  FAIL {row}\n       never scored", flush=True)
    passed = sum(1 for ok in results.values() if ok)
    print(f"\n{passed}/{len(results)} rows passed", flush=True)
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
