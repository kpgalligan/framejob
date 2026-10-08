#!/usr/bin/env python3
"""Road map 8, W4a — word-caption GENERATION through the built binary.

Launches its own Reelcut on a scratch socket, pointed at its own
`assemblyai_fake.py` (`-RCAssemblyAIEndpoint`, a scratch `-RCSecretFolder` and
the dummy key `proof-key` — nothing here reaches AssemblyAI), drives it over
MCP, and kills both by PID in a `finally`:

* **G1** `apple` + `highlight` over `media/speech.mov` on a 1080×1920 canvas:
  every placed clip has `word_style.mode` highlight, `case` upper,
  `Montserrat-Black`, and one timing per token of its content.
* **G2** Width, off pixels: every page rendered at `start + frame` with the
  captions and without them (`undo`), and every column that differs lies in
  `[0.07 W, 0.93 W]` — the budget's columns.
* **G3** the cloud engine over the fake's words: `subtitles` with
  `place: false` gives `cloud_captions_proof.py`'s pinned cue; `highlight`
  answers from the cache (`uploaded` empty) with `words` in its cues.
* **G4** `highlight`, then an EMPTY "Captions 2" track, then `pill` with
  `replace: true`: `replaced` is the old track alone, one Captions track with
  clips is left, in `Montserrat-ExtraBold`, and the empty track survives; one
  `undo` restores the old track whole and `redo` swaps back.
* **G5** `replace` with `subtitles`, `replace` with `place: false`, and
  `style: "bold"`, each refused by name.
* **G6** `apple` + `one_word` over the `say` pangram: one token a page, at
  least 20 pages, starts non-decreasing.
* **G7** `tools/list`: `style` an enum of the six, `replace` a boolean.
* **G8** two ABUTTING clips — `speech.mov` split at its midpoint — under
  `apple` + `highlight`: no `trimmed`, no `skipped`, every page inside one
  clip, both clips read; then `pill` with `replace: true` replaces that track.
* **L** (issue batch B43, #200 item 4) `cloud_captions_probe.py`'s
  `hold_cloud_lock`, taken first: G3's cloud engine writes
  `reelcut-upload-*` into the one temporary folder the cloud probe and proof
  use, so the three take turns. `--lock-wait` (default 3600 s) bounds the
  wait; an expired wait is a scored FAIL naming the holder, and exit 1 with
  no instance launched.

    python3 tools/proof/word_captions_proof.py [--lock-wait SECONDS]
"""

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time

from mcp import MCP, ToolError, log_beside, remove_scratch, scratch_socket, wait_listening
import proof_app
from cloud_captions_probe import Fake, child_env, hold_cloud_lock
from e1_proof import decode_png
from speech_engine_proof import make_fixtures

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
WORK = os.path.join(HERE, "work", "word_captions")
MEDIA = os.path.join(HERE, "media")
BINARY = str(proof_app.binary())
DUMMY = "proof-key"
SEC = 600_000
STYLES = ["subtitles", "highlight", "pill", "karaoke", "build", "one_word"]
WORDS = [
    {"text": "Hello", "start": 600, "end": 1120, "confidence": 0.98, "speaker": None},
    {"text": "there", "start": 1180, "end": 1600, "confidence": 0.96, "speaker": None},
    {"text": "everyone", "start": 1700, "end": 2400, "confidence": 0.91, "speaker": None},
    {"text": "welcome", "start": 3000, "end": 3600, "confidence": 0.93, "speaker": None},
    {"text": "back", "start": 3700, "end": 4100, "confidence": 0.95, "speaker": None},
]

passed = 0
failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


def fresh(*parts):
    path = os.path.join(WORK, *parts)
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    return path


class Instance:
    """One Reelcut, started here and stopped here by its own PID."""

    def __init__(self, fake):
        self.socket = scratch_socket()
        self.log = log_beside(self.socket)
        if os.path.exists(self.log):
            os.remove(self.log)
        self.handle = open(self.log, "wb")
        env = child_env()
        env["RC_ASSEMBLYAI_KEY"] = DUMMY
        env["RC_AGENT_SOCKET"] = self.socket
        argv = [BINARY, "-ApplePersistenceIgnoreState", "YES",
                "-RCSecretFolder", fresh("secrets"), "-RCAssemblyAIEndpoint", fake.base]
        self.process = subprocess.Popen(argv, stdout=self.handle, stderr=subprocess.STDOUT,
                                        env=env, stdin=subprocess.DEVNULL)
        if not wait_listening(self.log, self.socket, child=self.process, seconds=60):
            raise RuntimeError(f"the instance did not listen at {self.socket} (exit "
                               f"{self.process.poll()}) — {self.log}")
        print(f"  (instance pid {self.process.pid} bound {self.socket}; log {self.log})")
        self.mcp = MCP(self.socket, timeout=300)

    def parity(self):
        with open(self.log, "rb") as stream:
            lines = stream.read().decode("utf-8", "replace").splitlines()
        complaints = [line for line in lines if "Reelcut: " in line]
        check(f"the startup parity check said nothing — `grep \"Reelcut: \"` on {self.log} "
              "is empty", not complaints, "\n       ".join(complaints[:5]))

    def stop(self):
        if self.process.poll() is None:
            self.process.terminate()
            deadline = time.time() + 15
            while time.time() < deadline and self.process.poll() is None:
                time.sleep(0.2)
            if self.process.poll() is None:
                self.process.send_signal(signal.SIGKILL)
                self.process.wait(timeout=10)
        self.handle.close()
        remove_scratch(self.socket)


class Session:
    def __init__(self, instance, name):
        self.mcp = instance.mcp
        self.path = os.path.join(WORK, f"{name}.reelcut")
        shutil.rmtree(self.path, ignore_errors=True)
        self.mcp.call("new_project", path=self.path)

    def op(self, tool, **arguments):
        return self.mcp.call_with(tool, dict(arguments, project=self.path))

    def error(self, tool, **arguments):
        try:
            self.op(tool, **arguments)
            return None
        except ToolError as problem:
            return str(problem)

    def project(self):
        return self.op("get_project")["project"]

    def speech(self):
        media = self.op("import_media", path=os.path.join(MEDIA, "speech.mov"))["media"]
        track = self.project()["tracks"][0]["id"]
        return self.op("add_clip", track=track, media=media, at=0)["new_clips"][0], media

    def captions(self):
        """The Captions tracks, and the clips on each, by track id."""
        project = self.project()
        tracks = [t for t in project["tracks"] if re.fullmatch(r"Captions( \d+)?", t["name"])]
        return {t["id"]: [c for c in project["clips"] if c["track"] == t["id"]] for t in tracks}


def tokens(text):
    return text.split()


def styled(clips, mode, case, font):
    bad = []
    for clip in clips:
        text = clip["text"]
        style = text.get("word_style") or {}
        if (style.get("mode") != mode or text.get("case") != case or text.get("font") != font
                or len(text.get("words", [])) != len(tokens(text["content"]))
                or not text.get("words")):
            bad.append((clip["id"], text.get("content"), style.get("mode"), text.get("case"),
                        text.get("font"), len(text.get("words", []))))
    return bad


# --------------------------------------------------------------------------


def g1_g2(instance):
    print("\nG1, G2 — apple + highlight over speech.mov, on 1080×1920")
    session = Session(instance, "g1")
    session.op("set_canvas", width=1080, height=1920)
    session.speech()
    answer = session.op("transcribe", engine="apple", style="highlight")
    tracks = session.captions()
    clips = [c for group in tracks.values() for c in group]
    check("G1 one Captions track of highlight pages, each with words in every cue of the result",
          len(tracks) == 1 and clips and all("words" in c for c in answer["cues"])
          and "trimmed" not in answer and "skipped" not in answer,
          f"tracks {list(tracks)}, answer keys {sorted(answer)}")
    bad = styled(clips, "highlight", "upper", "Montserrat-Black")
    check(f"G1 every placed page ({len(clips)}) is Montserrat-Black, upper, word_style "
          "highlight, one timing per token", clips and not bad, f"{bad[:4]}")

    canvas = session.project()["canvas"]
    frame = SEC * canvas["fps"][1] // canvas["fps"][0]
    width = canvas["width"]
    times = [c["start"] + frame for c in sorted(clips, key=lambda c: c["start"])]
    after = [render(session, t, f"after-{i}") for i, t in enumerate(times)]
    session.op("undo")
    before = [render(session, t, f"before-{i}") for i, t in enumerate(times)]
    session.op("redo")
    low, high = 0.07 * width, 0.93 * width
    spans = []
    outside = []
    for index, (a, b) in enumerate(zip(after, before)):
        columns = differing_columns(a, b)
        if not columns:
            outside.append((index, "no column differs"))
            continue
        spans.append((min(columns), max(columns)))
        if min(columns) < low or max(columns) > high:
            outside.append((index, min(columns), max(columns)))
    check(f"G2 every page's ink lies within the budget's columns [{low:.0f}, {high:.0f}] of "
          f"{width} — columns that differ with and without the captions, per page {spans}",
          times and not outside, f"{outside}")


def render(session, tick, name):
    path = os.path.join(WORK, f"g2-{name}.png")
    session.op("render_frame", t=tick, path=path)
    return decode_png(path)


def differing_columns(a, b):
    width, height, _, channels, rows_a = a
    _, _, _, _, rows_b = b
    columns = set()
    for y in range(height):
        row_a, row_b = rows_a[y], rows_b[y]
        if row_a == row_b:
            continue
        for x in range(width):
            if row_a[x * channels:(x + 1) * channels] != row_b[x * channels:(x + 1) * channels]:
                columns.add(x)
    return columns


def g3_g4_g5(instance, fake):
    print("\nG3, G4, G5 — the cloud engine over the fake's words, replace, refusals")
    fake.scenario(words=WORDS)
    session = Session(instance, "g3")
    clip, media = session.speech()
    plain = session.op("transcribe", engine="assemblyai", place=False, style="subtitles")
    want = [{"start": 360000, "end": 2460000, "text": "Hello there everyone welcome back"}]
    check("G3 subtitles, place false: the pinned cue, no words", plain["cues"] == want,
          f"got {plain['cues']}")
    styled_run = session.op("transcribe", engine="assemblyai", place=False, style="highlight")
    cues = styled_run["cues"]
    words = [w["text"] for cue in cues for w in cue.get("words", [])]
    check("G3 highlight, place false: answered from the cache (uploaded [], cached has the "
          "media) with words in every cue",
          styled_run.get("uploaded") == [] and media in styled_run.get("cached", [])
          and cues and all(len(c["words"]) == len(tokens(c["text"])) for c in cues)
          and words == [w["text"] for w in WORDS],
          f"uploaded {styled_run.get('uploaded')}, cached {styled_run.get('cached')}, {cues}")

    first = session.op("transcribe", engine="assemblyai", style="highlight")
    old = session.captions()
    old_id = next(iter(old)) if len(old) == 1 else None
    # An EMPTY caption-named track: no clip of it is a caption this run made,
    # so it is not replaced (W4a's review, nit 1).
    session.op("add_track", name="Captions 2")
    empty = [i for i, clips in session.captions().items() if i not in old and not clips]
    empty_id = empty[0] if len(empty) == 1 else None
    swapped = session.op("transcribe", engine="assemblyai", style="pill", replace=True)
    now = session.captions()
    new_clips = [c for group in now.values() for c in group]
    filled = [i for i, clips in now.items() if clips]
    check("G4 pill with replace: replaced is exactly the old track, one Captions track with "
          "clips left",
          old_id is not None and swapped.get("replaced") == [old_id] and len(filled) == 1
          and old_id not in now, f"first {first.get('track_name')}, old {list(old)}, "
          f"replaced {swapped.get('replaced')}, now {list(now)}")
    check("G4 an empty \"Captions 2\" track is not replaced and survives, still empty",
          empty_id is not None and empty_id not in (swapped.get("replaced") or [])
          and now.get(empty_id) == [], f"empty {empty}, now {list(now)}")
    bad = styled(new_clips, "highlight", "upper", "Montserrat-ExtraBold")
    check("G4 the new pages are Montserrat-ExtraBold with the pill's word_style",
          new_clips and not bad and all(c["text"]["word_style"].get("active_pill")
                                        for c in new_clips), f"{bad[:3]}")
    session.op("undo")
    back = session.captions()
    check("G4 one undo restores the old track whole — the same id and the same clips",
          back == {**old, empty_id: []}, f"{list(back)} vs {list(old)}")
    session.op("redo")
    check("G4 and redo swaps back", session.captions() == now)

    refusals = [
        ("replace with subtitles", {"style": "subtitles", "replace": True}, "replace"),
        ("replace with place false", {"style": "highlight", "replace": True, "place": False},
         "when place is true"),
        ("style \"bold\"", {"style": "bold"}, "style must be one of " + ", ".join(STYLES)),
    ]
    for label, arguments, needle in refusals:
        before = session.project()
        text = session.error("transcribe", engine="assemblyai", **arguments)
        check(f"G5 {label} is refused by name and changes nothing",
              text is not None and needle in text and session.project() == before,
              f"got {text!r}")


def g6(instance):
    print("\nG6 — apple + one_word over the say pangram")
    pangram = make_fixtures()[0]
    session = Session(instance, "g6")
    media = session.op("import_media", path=pangram)["media"]
    track = session.project()["tracks"][0]["id"]
    session.op("add_clip", track=track, media=media, at=0)
    answer = session.op("transcribe", engine="apple", style="one_word", place=False)
    cues = answer["cues"]
    starts = [c["start"] for c in cues]
    check(f"G6 one token a page ({len(cues)} pages), at least 20, starts non-decreasing",
          len(cues) >= 20 and all(len(tokens(c["text"])) == 1 and len(c["words"]) == 1
                                  for c in cues)
          and starts == sorted(starts), f"{[c['text'] for c in cues]}")


def g7(instance):
    print("\nG7 — the catalog")
    schema = instance.mcp.schemas()["transcribe"]["inputSchema"]["properties"]
    check("G7 transcribe publishes style as an enum of the six and replace as a boolean",
          schema.get("style", {}).get("enum") == STYLES
          and schema.get("replace", {}).get("type") == "boolean",
          f"style {schema.get('style', {}).get('enum')}, replace {schema.get('replace')}")


def g8(instance):
    print("\nG8 — two abutting clips: speech.mov split at its midpoint")
    session = Session(instance, "g8")
    clip, _ = session.speech()
    canvas = session.project()["canvas"]
    frame = SEC * canvas["fps"][1] // canvas["fps"][0]
    whole = {c["id"]: c for c in session.project()["clips"]}[clip]
    at = whole["start"] + (whole["duration"] // 2 // frame) * frame
    session.op("split", clips=[clip], at=at)
    halves = sorted((c for c in session.project()["clips"] if c["track"] == whole["track"]),
                    key=lambda c: c["start"])
    spans = [(c["start"], c["start"] + c["duration"]) for c in halves]
    answer = session.op("transcribe", engine="apple", style="highlight")
    tracks = session.captions()
    pages = [c for group in tracks.values() for c in group]
    stray = [(p["start"], p["start"] + p["duration"], p["text"]["content"]) for p in pages
             if not any(lo <= p["start"] and p["start"] + p["duration"] <= hi
                        for lo, hi in spans)]
    check(f"G8 no trimmed and no skipped over two abutting clips at {at} "
          f"({len(pages)} pages)", "trimmed" not in answer and "skipped" not in answer
          and len(halves) == 2, f"keys {sorted(answer)}; trimmed {answer.get('trimmed')}, "
          f"skipped {answer.get('skipped')}")
    check("G8 every page lies inside one of the two clips, and both clips were read",
          pages and not stray and sorted(answer["clips_read"]) == sorted(c["id"] for c in halves),
          f"spans {spans}; stray {stray}; read {answer['clips_read']}")
    old = list(tracks)
    swapped = session.op("transcribe", engine="apple", style="pill", replace=True)
    check("G8 pill with replace replaces that track, and one Captions track remains",
          len(old) == 1 and swapped.get("replaced") == old and len(session.captions()) == 1
          and "trimmed" not in swapped,
          f"old {old}, replaced {swapped.get('replaced')}, now {list(session.captions())}")


def main():
    parser = argparse.ArgumentParser(
        description=__doc__.split("\n")[0],
        usage="word_captions_proof.py [--lock-wait SECONDS]")
    parser.add_argument("--lock-wait", type=float, default=3600,
                        help="how long to wait for the cloud instruments' lock, in seconds "
                             "(issue batch B43; rule H)")
    args = parser.parse_args()
    # L (issue batch B43, #200 item 4): held before anything else, and kept
    # open until `main` returns.
    lock, waited, holder = hold_cloud_lock(args.lock_wait)
    print(f"  (waited {waited:.1f} s for the cloud instruments' lock)")
    check("L: the cloud instruments' lock is held \u2014 "
          + (f"by this run, {holder}" if lock else f"still held by {holder} after "
             f"--lock-wait {args.lock_wait:.0f} s"),
          lock is not None, holder)
    if lock is None:
        print(f"\n{passed}/{passed + failed} checks passed in {waited:.0f} s")
        return 1
    started = time.time()
    os.makedirs(WORK, exist_ok=True)
    print("road map 8 W4a — word-caption generation, over MCP\n")
    if not os.path.exists(BINARY):
        check(f"the built binary is there — run `make {proof_app.MAKE_TARGET[proof_app.config()]}` "
              "first", False, BINARY)
        return 1
    with Fake("word-captions") as fake:
        instance = Instance(fake)
        try:
            for row in (g7, g1_g2, g6, g8):
                try:
                    row(instance)
                except Exception as problem:  # noqa: BLE001 — a row's throw is its answer
                    check(f"{row.__name__} ran to its end", False,
                          f"{type(problem).__name__}: {problem}")
            try:
                g3_g4_g5(instance, fake)
            except Exception as problem:  # noqa: BLE001
                check("g3_g4_g5 ran to its end", False, f"{type(problem).__name__}: {problem}")
            instance.parity()
        finally:
            instance.stop()
    print(f"\n{passed}/{passed + failed} checks passed in {time.time() - started:.0f} s")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
