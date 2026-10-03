#!/usr/bin/env python3
"""Word captions, the picture: road map 8's W3 (§10.7), over MCP.

The app now decodes format version 9's `case` / `words` / `word_style` and the
recipe's `word` / `word_pop`, and draws a timed page. Every row here is a BYTE
comparison of two `render_frame` PNGs of a hand-written version-9 package, or
a sentence read back off `tools/list`; the arithmetic no script can reach (the
box, the headroom, the ink) is `words_picture_probe.py`'s.

    python3 tools/proof/words_picture_proof.py <dir>/agent.sock

R1  two frames inside one word's hold, +0.20 s and +0.30 s after its start
    (WORD_POP is 0.12 s), are byte-identical;
R2  the frame a frame before a word start differs from the frame at it;
R3  a build page a frame before its first word equals a frame before the clip;
R4  `case: upper` differs from `as_written` and equals the capitals typed;
R5  the four bundled faces and NoSuchFont-Black: five pairwise-distinct PNGs;
R6  set_text's patch description names case, words and word_style;
R7  an UNTIMED page with a colour-only word_style equals its unstyled twin.

It launches nothing and kills nothing: the caller owns the instance at the
socket, relaunched fresh, and has checked `grep "Reelcut: " <dir>/reelcut.log`
prints nothing.
"""

import hashlib
import json
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp import MCP, target  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work", "words-picture")
SEC = 600_000
FRAME = 20_000
WRITTEN = re.compile(r"Written to (\S+\.png)\.")

# Four words on the 30 fps grid: 0.2 s, 0.6 s, 1.0 s, 1.4 s into the clip.
PAGE = "the quick brown fox"
TIMINGS = [{"start": 120_000, "end": 300_000}, {"start": 360_000, "end": 540_000},
           {"start": 600_000, "end": 780_000}, {"start": 840_000, "end": 1_020_000}]
HIGHLIGHT = {"mode": "highlight", "active_color": [1.0, 0.85, 0.0, 1.0], "active_scale": 1.2,
             "active_pill": {"color": [0.55, 0.27, 0.93, 1.0], "padding": 0.2, "radius": 0.25},
             "spoken_color": [0.8, 0.8, 0.8, 1.0], "upcoming_color": [1.0, 1.0, 1.0, 0.5]}
FACES = ["Montserrat-ExtraBold", "Montserrat-Black", "Anton-Regular", "BebasNeue-Regular",
         "NoSuchFont-Black"]

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


def text_clip(clip, start, duration, text):
    return {"id": clip, "track": 1, "start": start, "duration": duration,
            "source": {"kind": "text"}, "video": {}, "text": text}


def package(name, clips):
    """A fresh version-9 package in `work/words-picture/`, one track."""
    path = os.path.join(WORK, f"{name}.reelcut")
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    document = {
        "version": 9,
        "canvas": {"width": 640, "height": 360, "fps": [30, 1],
                   "background": [0.2, 0.25, 0.3, 1.0]},
        "media": [], "tracks": [{"id": 1, "name": "Words"}], "clips": clips,
        "markers": [], "nests": [], "next_id": 100,
    }
    with open(os.path.join(path, "project.json"), "w", encoding="utf-8") as stream:
        json.dump(document, stream)
    return path


class Frames:
    def __init__(self, mcp, path):
        self.mcp = mcp
        self.path = path
        mcp.call("open_project", path=path)

    def at(self, tick):
        answer = str(self.mcp.call("render_frame", project=self.path, t=tick))
        found = WRITTEN.search(answer)
        if not found:
            raise RuntimeError(f"render_frame said something else: {answer}")
        with open(found.group(1), "rb") as stream:
            data = stream.read()
        # A copy under a stable name, so a failing row leaves its pictures.
        kept = os.path.join(WORK, f"{os.path.basename(self.path)[:-8]}-t{tick}.png")
        with open(kept, "wb") as stream:
            stream.write(data)
        return kept, data


def sha(data):
    return hashlib.sha256(data).hexdigest()[:16]


def highlight_rows(mcp):
    frames = Frames(mcp, package("highlight", [
        text_clip(10, 0, 3 * SEC, {"content": PAGE, "size": 56, "words": TIMINGS,
                                   "word_style": HIGHLIGHT})]))
    start = TIMINGS[1]["start"]
    a_path, a = frames.at(start + 6 * FRAME)
    b_path, b = frames.at(start + 9 * FRAME)
    check("R1 +0.20 s and +0.30 s after a word start (its pop settled) are byte-identical",
          a == b and len(a) > 0, f"{a_path} {sha(a)} vs {b_path} {sha(b)}")
    c_path, c = frames.at(start - FRAME)
    d_path, d = frames.at(start)
    check("R2 the frame a frame before a word start differs from the frame at it",
          c != d and len(c) > 0 and len(d) > 0, f"{c_path} {sha(c)} vs {d_path} {sha(d)}")


def build_row(mcp):
    style = dict(HIGHLIGHT, mode="build")
    frames = Frames(mcp, package("build", [
        text_clip(10, SEC, 3 * SEC, {"content": PAGE, "size": 56, "words": TIMINGS,
                                     "word_style": style})]))
    before_clip_path, before_clip = frames.at(SEC // 2)
    before_word_path, before_word = frames.at(SEC + TIMINGS[0]["start"] - FRAME)
    on_path, on = frames.at(SEC + TIMINGS[0]["start"])
    check("R3 a build page a frame before its first word equals a frame before the clip",
          before_clip == before_word and len(before_clip) > 0,
          f"{before_clip_path} {sha(before_clip)} vs {before_word_path} {sha(before_word)}")
    # Not a row of its own: without ink AT the first word, R3 could pass on a
    # page that never draws at all.
    if on == before_word:
        check("R3's page draws its first word at the word's start", False,
              f"{on_path} equals {before_word_path}")


def case_row(mcp):
    content = "straße ist"
    frames = Frames(mcp, package("case", [
        text_clip(10, 0, SEC, {"content": content, "size": 56}),
        text_clip(11, SEC, SEC, {"content": content, "size": 56, "case": "upper"}),
        text_clip(12, 2 * SEC, SEC, {"content": "STRASSE IST", "size": 56}),
    ]))
    _, written = frames.at(SEC // 2)
    upper_path, upper = frames.at(SEC + SEC // 2)
    typed_path, typed = frames.at(2 * SEC + SEC // 2)
    check("R4 case upper differs from as_written, and equals the capitals typed",
          written != upper and upper == typed,
          f"as_written {sha(written)}, upper {sha(upper)} ({upper_path}), "
          f"typed {sha(typed)} ({typed_path})")


def faces_row(mcp):
    clips = [text_clip(10 + index, index * SEC, SEC,
                       {"content": "WORD CAPTIONS", "size": 56, "font": face})
             for index, face in enumerate(FACES)]
    frames = Frames(mcp, package("faces", clips))
    pictures = [frames.at(index * SEC + SEC // 2)[1] for index in range(len(FACES))]
    distinct = len({sha(p) for p in pictures})
    check("R5 the four bundled faces and NoSuchFont-Black render five distinct PNGs",
          distinct == len(FACES),
          ", ".join(f"{face} {sha(p)}" for face, p in zip(FACES, pictures)))


def description_row(mcp):
    schema = mcp.schemas()["set_text"]["inputSchema"]["properties"]["patch"]
    prose = schema.get("description", "")
    wanted = ["case (as_written|upper", "words (one {start, end}",
              "word_style (null or {mode: highlight|build"]
    missing = [w for w in wanted if w not in prose]
    check("R6 set_text's patch description names case, words and word_style",
          not missing, f"missing {missing}")


def colour_only_row(mcp):
    style = {"mode": "highlight", "active_color": [1.0, 0.0, 0.0, 1.0]}
    frames = Frames(mcp, package("colour-only", [
        text_clip(10, 0, SEC, {"content": PAGE, "size": 56, "words": [], "word_style": style}),
        text_clip(11, SEC, SEC, {"content": PAGE, "size": 56}),
    ]))
    styled_path, styled = frames.at(SEC // 2)
    twin_path, twin = frames.at(SEC + SEC // 2)
    check("R7 an untimed page with a colour-only word_style equals its unstyled twin",
          styled == twin and len(styled) > 0,
          f"{styled_path} {sha(styled)} vs {twin_path} {sha(twin)}")


def main():
    if len(sys.argv) != 2 or sys.argv[1].startswith("--"):
        sys.exit(__doc__)
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)
    mcp = MCP(target(sys.argv))
    print("W3 — word captions, the picture")
    highlight_rows(mcp)
    build_row(mcp)
    case_row(mcp)
    faces_row(mcp)
    description_row(mcp)
    colour_only_row(mcp)
    print(f"{passed}/{passed + failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
