#!/usr/bin/env python3
"""Docs bugs b1 — Loop at the timeline's end (#466) and ducking after Detach Audio (#468).

    python3 tools/proof/docs_bugs_b1_proof.py [--only L1,D3,…] [--app PATH]

Over MCP on one launch (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`) on a scratch
`CFFIXED_USER_HOME`. Media are made under `tools/proof/work/docs-bugs-b1/` with ffmpeg: `av.mov`, a
5 s test card at 30 fps with a tone; `voice.mov`, the same with a 1000 Hz tone; `music.wav`, 20 s of
a 440 Hz tone, so each one's level reads apart from one export.

Rows marked [B] are red before the fix; the rest are CONTROLS.

**Loop.** Three trials a row, each 24 s with the playhead polled every 0.2 s. A wrap is a fall over
0.5 s. A row passes when every trial has at least 3 wraps and moved in its last 3 s. A row watching
one pass proves nothing: before the fix a loop could go round once more and then stop.
- L1 [B] a lone clip, Clip ▸ Motion ▸ Preview.
- L2 [B] the same with the range cleared by `set_range`: the whole-timeline loop.
- L3 [B] the last clip of two.
- L4 the first clip of two: a loop ending before the timeline does.
- L5 [B] the whole-timeline loop, `play_preview {rate: 2}` for 11, 12 and 13 s: at least one `to`
  is off the loop's start. Before the fix every run ended stopped on it.

**Ducking.** Music on the bottom track, an empty track, the voice on the top one at 5 to 10 s. Gain
is each tone's amplitude over 6 to 9 s of an `audio_wav` export over the same reading with nothing
ducking; voice ± 0.02, music ± 0.01. One document, in this order, so `--only` runs the whole chain
and scores what it names.
- D1 [B] Duck other audio on (`set_audio`, the op the checkbox sends), Clip ▸ Detach Audio: voice
  1.0, music 0.2.
- D2 [B] `get_project`: no `audio.duck` on the picture half, level 0.2 on the sound half.
- D3 [B] `duck: null` on the sound half: voice 1.0, music 1.0.
- D4 undo, Clip ▸ Attach Audio with the duck on: voice 1.0, music 0.2.
- D5 [B] detached again, `set_audio` puts the duck back on the picture half, then save, close and
  reopen: voice 1.0, music 0.2.
- D6 attached, then `set_enabled {audio: false}` on the unlinked clip with its duck: music 0.2.
- Z1 the launch's `grep "Frame Job: "` prints nothing.

What this does not measure: the real Loop button, Home and Space, the real checkbox and ⌥⌘D, and
the sound itself (`docs/manual-checks.md` PB-15, SE-42).
"""

import argparse
import array
import math
import shutil
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

WORK = ROOT / "tools/proof/work/docs-bugs-b1"
HOME = WORK / "home"
MEDIA = WORK / "media"
SEC = 600_000
RATE = 48_000
CALL_BOUND = 600
TRIALS = 3
WATCH = 24
TAIL = 3
MIN_WRAPS = 3
DUCK = {"level": 0.2, "attack": 300000, "release": 600000}
VOICE_TOLERANCE = 0.02
MUSIC_TOLERANCE = 0.01

LOOP_ROWS = ["L1", "L2", "L3", "L4", "L5"]
DUCK_ROWS = ["D1", "D2", "D3", "D4", "D5", "D6"]
ROWS = LOOP_ROWS + DUCK_ROWS + ["Z1"]

selected = set(ROWS)
results = {}


def check(name, ok, detail=""):
    if name not in selected:
        return
    results[name] = bool(ok)
    print(f"  {'ok  ' if ok else 'FAIL'} {name}" + (f"\n       {detail}" if detail else ""),
          flush=True)


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True, timeout=120)


def tone(hertz):
    return f"aevalsrc=0.05*sin(2*PI*{hertz}*t)|0.05*sin(2*PI*{hertz}*t):s=48000:d="


def card(path, hertz):
    ffmpeg("-f", "lavfi", "-i", "testsrc=size=640x360:rate=30:duration=5",
           "-f", "lavfi", "-i", tone(hertz) + "5",
           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "pcm_s16le", "-shortest", str(path))


def make_media():
    MEDIA.mkdir(parents=True, exist_ok=True)
    card(MEDIA / "av.mov", 660)
    card(MEDIA / "voice.mov", 1000)
    ffmpeg("-f", "lavfi", "-i", tone(440) + "20", "-c:a", "pcm_s16le", str(MEDIA / "music.wav"))


def state(client, path):
    return client.call_with("get_project", {"project": path})


def menu(client, path, *items):
    return client.call_with("perform_menu_item", {"project": path, "path": list(items)})


# ---- Loop ----------------------------------------------------------------------------------


def loop_project(client, name, clips):
    path = str(WORK / f"{name}.framejob")
    client.call("new_project", path=path)
    media = client.call("import_media", project=path, path=str(MEDIA / "av.mov"))["media"]
    track = state(client, path)["project"]["tracks"][0]["id"]
    ids, at = [], 0
    for _ in range(clips):
        ids.append(client.call("add_clip", project=path, track=track, media=media,
                               at=at)["new_clips"][0])
        at = state(client, path)["duration"]
    time.sleep(2)
    return path, ids


def trial(client, path, clip, clear_range):
    client.call("set_selection", project=path, clips=[clip])
    menu(client, path, "Clip", "Motion", "Preview")
    if clear_range:
        client.call("set_range", project=path)
    started = time.monotonic()
    polled = []
    while time.monotonic() - started < WATCH:
        polled.append((time.monotonic() - started, state(client, path)["playhead"] / SEC))
        time.sleep(0.2)
    wraps = sum(1 for before, after in zip(polled, polled[1:]) if after[1] < before[1] - 0.5)
    moved = len({p for t, p in polled if t >= WATCH - TAIL}) > 1
    client.call_with("play_preview", {"project": path, "seconds": 0.5})   # ends paused
    return wraps, moved


def loop_row(row, client, path, clip, clear_range=False):
    if row not in selected:
        return
    trials = [trial(client, path, clip, clear_range) for _ in range(TRIALS)]
    check(row, all(wraps >= MIN_WRAPS and moved for wraps, moved in trials),
          f"(wraps, moved in the last {TAIL} s) per {WATCH} s trial: {trials}")


def loop_rows(client):
    path, (clip,) = loop_project(client, "lone", 1)
    loop_row("L1", client, path, clip)
    loop_row("L2", client, path, clip, clear_range=True)
    if "L5" in selected:
        client.call("set_selection", project=path, clips=[clip])
        menu(client, path, "Clip", "Motion", "Preview")
        client.call("set_range", project=path)
        ends = []
        for seconds in (11, 12, 13):
            client.call_with("set_playhead", {"project": path, "t": 0})
            time.sleep(0.5)
            run = client.call_with("play_preview",
                                   {"project": path, "seconds": seconds, "rate": 2})
            ends.append(run["to"] / SEC)
        check("L5", any(end != 0 for end in ends), f"play_preview's to at ×2: {ends}")
    client.call("close_project", project=path, discard=True)
    if {"L3", "L4"} & selected:
        path, (first, last) = loop_project(client, "pair", 2)
        loop_row("L3", client, path, last)
        loop_row("L4", client, path, first)
        client.call("close_project", project=path, discard=True)


# ---- Ducking -------------------------------------------------------------------------------


def decode(file):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", file, "-vn", "-f", "s32le", "-acodec",
                          "pcm_s32le", "-ar", str(RATE), "-ac", "2", "-"],
                         check=True, timeout=120, capture_output=True).stdout
    values = array.array("i")
    values.frombytes(raw)
    return [v / 2147483648.0 for v in values[0::2]]


def amplitude(left, hertz, start_s, end_s):
    first, last = int(start_s * RATE), int(end_s * RATE)
    i = q = 0.0
    for n in range(first, last):
        phase = 2 * math.pi * hertz * n / RATE
        i += left[n] * math.sin(phase)
        q += left[n] * math.cos(phase)
    return 2 * math.hypot(i, q) / (last - first)


class Ducking:
    def __init__(self, client):
        self.client = client
        self.path = str(WORK / "duck.framejob")
        self.reference = None
        client.call("new_project", path=self.path)
        for _ in range(3 - len(self.state()["project"]["tracks"])):
            client.call_with("add_track", {"project": self.path, "index": 0})
        bottom, _, top = [t["id"] for t in self.state()["project"]["tracks"]]
        music = client.call("import_media", project=self.path,
                            path=str(MEDIA / "music.wav"))["media"]
        voice = client.call("import_media", project=self.path,
                            path=str(MEDIA / "voice.mov"))["media"]
        self.music = client.call("add_clip", project=self.path, track=bottom, media=music,
                                 at=0)["new_clips"][0]
        self.voice = client.call("add_clip", project=self.path, track=top, media=voice,
                                 at=5 * SEC)["new_clips"][0]
        time.sleep(2)

    def state(self):
        return state(self.client, self.path)

    def clip(self, ident):
        return next(c for c in self.state()["project"]["clips"] if c["id"] == ident)

    def sound(self):
        return next(c["id"] for c in self.state()["project"]["clips"]
                    if c["id"] not in (self.music, self.voice))

    def set_duck(self, clip, duck):
        self.client.call("set_audio", project=self.path, clips=[clip], patch={"duck": duck})

    def clip_menu(self, item):
        self.client.call("set_selection", project=self.path, clips=[self.voice])
        menu(self.client, self.path, "Clip", item)

    def gains(self, tag):
        """(voice, music), each over the reading with nothing ducking."""
        answer = self.client.export(project=self.path, preset="audio_wav",
                                    path=str(WORK / f"export-{tag}"))
        left = decode(answer["path"])
        voice, music = amplitude(left, 1000, 6, 9), amplitude(left, 440, 6, 9)
        if self.reference is None:
            self.reference = (voice, music)
        return voice / self.reference[0], music / self.reference[1]


def level_row(row, doc, want_voice, want_music):
    voice, music = doc.gains(row)
    voice_ok = want_voice is None or abs(voice - want_voice) <= VOICE_TOLERANCE
    check(row, voice_ok and abs(music - want_music) <= MUSIC_TOLERANCE,
          f"voice {voice:.3f} (want {want_voice}), music {music:.3f} (want {want_music})")


def duck_rows(client):
    doc = Ducking(client)
    doc.gains("reference")
    doc.set_duck(doc.voice, DUCK)

    doc.clip_menu("Detach Audio")
    level_row("D1", doc, 1.0, 0.2)

    sound = doc.sound()
    picture_duck = (doc.clip(doc.voice).get("audio") or {}).get("duck")
    sound_duck = (doc.clip(sound).get("audio") or {}).get("duck") or {}
    check("D2", picture_duck is None and sound_duck.get("level") == 0.2,
          f"picture {picture_duck}, sound {sound_duck}")

    doc.set_duck(sound, None)
    level_row("D3", doc, 1.0, 1.0)
    client.call("undo", project=doc.path)

    doc.clip_menu("Attach Audio")
    level_row("D4", doc, 1.0, 0.2)

    doc.clip_menu("Detach Audio")
    if (doc.clip(doc.voice).get("audio") or {}).get("duck") is None:   # kept, before the fix
        doc.set_duck(doc.voice, DUCK)
    client.call("save_project", project=doc.path)
    client.call("close_project", project=doc.path)
    client.call("open_project", path=doc.path)
    time.sleep(2)
    level_row("D5", doc, 1.0, 0.2)

    doc.clip_menu("Attach Audio")
    client.call("set_enabled", project=doc.path, clip=doc.voice, audio=False)
    level_row("D6", doc, None, 0.2)
    client.call("close_project", project=doc.path, discard=True)


# ---- The launch ----------------------------------------------------------------------------


def with_instance(binary):
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), [],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in selected - {"Z1"}:
                check(row, False, "the app did not listen")
            return
        print(f"  instance PID {launched.child.pid}", flush=True)
        if selected & set(DUCK_ROWS):
            duck_rows(launched.client)
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
    print(f"docs bugs b1 on {binary}", flush=True)
    try:
        with_instance(binary)
    except (mcp.ToolError, OSError, KeyError, subprocess.SubprocessError) as error:
        print(f"  the run stopped: {type(error).__name__}: {error}", flush=True)
    missing = [row for row in sorted(selected) if row not in results]
    for row in missing:
        results[row] = False
        print(f"  FAIL {row}\n       never scored", flush=True)
    passed = sum(1 for ok in results.values() if ok)
    print(f"\n{passed}/{len(results)} rows passed", flush=True)
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
