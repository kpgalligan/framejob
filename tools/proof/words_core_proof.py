#!/usr/bin/env python3
"""Word captions, the core's half: road map 8's W1b (§10.5), over MCP.

Format version 9 adds `text.case`, `text.words` and `text.word_style`, with
the core as the one counter, rebaser, snapper and recipe of them (spec §11
W-1 to W-6). This script is the core's half, so every claim here is a
placement read back through `get_project`, a refusal's own sentence, a
saved file's text, or a BYTE comparison of two PNGs — and that last one,
a CONTROL until W3 (two frames a word apart drew the same picture while no
renderer read `word`), is inverted since W3: the same two frames DIFFER.

The recipe's `word` / `word_pop` keys are NOT reachable over MCP (no tool
returns a recipe), so the recipe rows are `core/tests/words.rs`'s, through
the FFI, and this script does not restate them.

    python3 tools/proof/words_core_proof.py <dir>/agent.sock
    python3 tools/proof/words_core_proof.py --mutant hash-arm|trim-rebase|count-check

The first form launches nothing and kills nothing: the caller owns the
instance at the socket, relaunched fresh. The second copies `core/` to a
temporary tree (op_contract_proof.py's pattern), breaks one thing there with
an anchor that must occur exactly once, and runs the one test that should
catch it with a bounded wall clock; exit 0 means that test FAILED in the
copy, which is the pass.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp import MCP, ToolError, target  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
WORK = os.path.join(HERE, "work")
SEC = 600_000
FRAME = 20_000
PAGE = "so here's the thing"
TIMINGS = [
    {"start": 0, "end": 108000},
    {"start": 120000, "end": 276000},
    {"start": 288000, "end": 348000},
    {"start": 360000, "end": 618000},
]
STYLE = {"mode": "highlight", "active_color": [1.0, 0.85, 0.0, 1.0], "active_scale": 1.2}
HEADER = os.path.join(ROOT, "core", "include", "reelcut_core.h")


def format_version():
    """`RC_FORMAT_VERSION` off the tree's own header, not a copy: a copy goes stale at every bump."""
    with open(HEADER) as f:
        text = f.read()
    match = re.search(r"#define RC_FORMAT_VERSION (\d+)", text)
    if match is None:
        raise RuntimeError(f"{HEADER} has no `#define RC_FORMAT_VERSION <n>` line")
    return int(match.group(1))


CURRENT_VERSION = format_version()
NEWER_VERSION = CURRENT_VERSION + 1
WRITTEN = re.compile(r"Written to (\S+\.png)\.")

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


def nearest(value, frame):
    """The nearest frame boundary, half away from zero — `time::snap_to_frame`
    written again as the oracle, never imported."""
    whole, rest = divmod(abs(value), frame)
    index = whole + (1 if 2 * rest >= frame else 0)
    return index * frame if value >= 0 else -index * frame


def snapped(words, frame=FRAME):
    return [{"start": nearest(w["start"], frame), "end": nearest(w["end"], frame)}
            for w in words]


def shifted(words, by):
    return [{"start": w["start"] + by, "end": w["end"] + by} for w in words]


class Session:
    """One saved project in `work/`, named per pid (an earlier run's package
    under a fixed name would be matched instead — phase 2's finding)."""

    def __init__(self, mcp, name):
        self.mcp = mcp
        for stale in os.listdir(WORK):
            if re.fullmatch(rf"{re.escape(name)}-\d+\.reelcut", stale):
                shutil.rmtree(os.path.join(WORK, stale))
        self.path = os.path.join(WORK, f"{name}-{os.getpid()}.reelcut")
        mcp.call("new_project", path=self.path)
        self.op("set_canvas", width=640, height=360, fps=[30, 1])

    def op(self, tool, **arguments):
        return self.mcp.call_with(tool, dict(arguments, project=self.path))

    def error(self, tool, **arguments):
        try:
            self.op(tool, **arguments)
            return None
        except ToolError as error:
            return str(error)

    def project(self):
        return self.op("get_project")["project"]

    def clip(self, clip):
        return {c["id"]: c for c in self.project()["clips"]}[clip]

    def words(self, clip):
        return self.clip(clip)["text"]["words"]

    def track(self, name):
        before = {t["id"] for t in self.project()["tracks"]}
        self.op("add_track", name=name)
        return next(t["id"] for t in self.project()["tracks"] if t["id"] not in before)

    def page(self, track, at=0, duration=6 * SEC, content=PAGE, words=TIMINGS, style=STYLE):
        text = {"content": content, "words": words}
        if style is not None:
            text["word_style"] = style
        return self.op("add_text_clip", track=track, at=at, duration=duration,
                       text=text)["new_clips"][0]

    def clip_starting(self, track, start):
        return next(c["id"] for c in self.project()["clips"]
                    if c["track"] == track and c["start"] == start)


def render(session, tick):
    answer = str(session.op("render_frame", t=tick))
    found = WRITTEN.search(answer)
    if not found:
        raise RuntimeError(f"render_frame said something else: {answer}")
    with open(found.group(1), "rb") as stream:
        return found.group(1), stream.read()


# ---- the rows ------------------------------------------------------------


def version_gate(mcp):
    path = os.path.join(WORK, f"words-v{NEWER_VERSION}-{os.getpid()}.reelcut")
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    with open(os.path.join(path, "project.json"), "w", encoding="utf-8") as stream:
        json.dump({"version": NEWER_VERSION, "canvas": {"width": 640, "height": 360, "fps": [30, 1]},
                   "tracks": [{"id": 2, "name": "T"}], "clips": [], "next_id": 3}, stream)
    try:
        mcp.call("open_project", path=path)
        message = None
    except ToolError as error:
        message = str(error)
    check(f"a version-{NEWER_VERSION} package is refused, naming version {CURRENT_VERSION} as "
          f"this build's",
          message is not None and f"version {NEWER_VERSION} is newer" in message
          and f"(version {CURRENT_VERSION})" in message,
          repr(message))


def door(s, track):
    clip = s.page(track)
    check("add_text_clip stores the page's words snapped to the 30 fps grid",
          s.words(clip) == snapped(TIMINGS), f"{s.words(clip)}")
    s.op("add_action", clip=clip, at=0)
    action = s.clip(clip)["actions"][0]["id"]

    # The undo marker: one applied edit, then seven calls the door must turn
    # away without a step, then ONE undo — which must take the marker back.
    before = json.dumps(s.project(), sort_keys=True)
    s.op("set_text", clips=[clip], patch={"color": [1.0, 0.0, 0.0, 1.0]})
    three = [{"start": 0, "end": 20000}, {"start": 20000, "end": 40000},
             {"start": 40000, "end": 60000}]
    missing = [dict(w) for w in TIMINGS]
    del missing[0]["end"]
    reversed_word = [dict(w) for w in snapped(TIMINGS)]
    reversed_word[1] = {"start": 200000, "end": 100000}
    rows = [
        ("3 timings for 4 words (W-2's sentence)", "set_text",
         {"clips": [clip], "patch": {"words": three}},
         "this text is timed word by word: 3 timings for 4 words"),
        ("words[0].end missing", "set_text",
         {"clips": [clip], "patch": {"words": missing}},
         'missing key "words[0].end" in a text patch'),
        ("active_scale 2", "set_text",
         {"clips": [clip], "patch": {"word_style": {"active_scale": 2}}},
         "text.word_style.active_scale must be between 1 and 1.5, not 2"),
        ("a reversed word", "set_text",
         {"clips": [clip], "patch": {"words": reversed_word}},
         "text.words[1].end must be at least its start 200000, not 100000"),
        ("set_action_end naming text.words", "set_action_end",
         {"clip": clip, "action": action, "patch": {"text": {"words": []}}},
         "text.words is not an animation target"),
        ("case \"shouting\"", "set_text",
         {"clips": [clip], "patch": {"case": "shouting"}},
         'bad value at "case" in a text patch'),
    ]
    for name, tool, arguments, sentence in rows:
        message = s.error(tool, **arguments)
        check(f"refused: {name}", message is not None and sentence in message, repr(message))
    undone = s.op("undo")
    after = json.dumps(s.project(), sort_keys=True)
    check("ONE undo restores the marker: the refusals made no step",
          after == before, f"undo answered {undone}")

    # A content edit: the same count keeps the words; another count must
    # send `words: []` in the same patch.
    s.op("set_text", clips=[clip], patch={"content": "so here it is"})
    check("a content edit with the same count keeps the words",
          s.words(clip) == snapped(TIMINGS))
    message = s.error("set_text", clips=[clip], patch={"content": "a b c"})
    check("a content edit with another count alone is an error",
          message is not None and "4 timings for 3 words" in message, repr(message))
    s.op("set_text", clips=[clip], patch={"content": "a b c", "words": []})
    check("…and with `words: []` beside it lands untimed", s.words(clip) == [])
    s.op("set_text", clips=[clip], patch={"content": PAGE, "words": TIMINGS})
    return clip


def split_mid_page(s, clip):
    cut = 10 * FRAME
    s.op("split", clips=[clip], at=cut)
    second = s.clip_starting(s.clip(clip)["track"], cut)
    check("split: the first half's words are untouched", s.words(clip) == snapped(TIMINGS))
    check("split: the second half's are rebased by the cut, a negative start legal",
          s.words(second) == shifted(snapped(TIMINGS), -cut)
          and s.words(second)[0]["start"] == -cut, f"{s.words(second)}")
    return second


def split_after_action(s, track):
    clip = s.page(track)
    s.op("add_action", clip=clip, at=0)
    action = s.clip(clip)["actions"][0]["id"]
    s.op("set_action_end", clip=clip, action=action, patch={"text": {"content": "a b c"}})
    s.op("split", clips=[clip], at=2 * SEC)
    second = s.clip_starting(track, 2 * SEC)
    half = s.clip(second)["text"]
    check("split after a content action: the second half reads `words: []`",
          half["content"] == "a b c" and half["words"] == [], f"{half['content']!r} {half['words']}")
    message = s.error("set_text", clips=[second], patch={"color": [1.0, 0.0, 0.0, 1.0]})
    check("…and set_text {color} on it is applied",
          message is None and s.clip(second)["text"]["color"] == [1.0, 0.0, 0.0, 1.0],
          repr(message))
    check("…while the first half keeps its four", s.words(clip) == snapped(TIMINGS))


def trims(s, track):
    clip = s.page(track)
    s.op("trim_start", clip=clip, to=2 * FRAME)
    check("trim_start +2 frames rebases every word by -2 frames",
          s.words(clip) == shifted(snapped(TIMINGS), -2 * FRAME), f"{s.words(clip)}")
    s.op("trim_end", clip=clip, to=5 * SEC)
    check("trim_end leaves the words where they were",
          s.words(clip) == shifted(snapped(TIMINGS), -2 * FRAME), f"{s.words(clip)}")
    return clip


def edges(s, track):
    s.op("add_text_clip", track=track, at=0, duration=3 * SEC, text={"content": "before"})
    clip = s.page(track, at=3 * SEC, duration=3 * SEC)
    s.op("roll", clip=clip, to=3 * SEC + FRAME)
    check("roll +1 frame rebases the later clip's words by -1 frame",
          s.words(clip) == shifted(snapped(TIMINGS), -FRAME), f"{s.words(clip)}")
    start = s.clip(clip)["start"]
    s.op("add_transition", clip=clip, duration=10 * FRAME, align="before")
    head = start - s.clip(clip)["start"]
    check("add_transition {align: before} moves the words with the new head (+head)",
          head == 10 * FRAME and s.words(clip) == shifted(snapped(TIMINGS), head - FRAME),
          f"head {head}, {s.words(clip)}")


def paste_attributes(s, track, source):
    target_words = [{"start": 0, "end": 20000}, {"start": 20000, "end": 40000}]
    target = s.page(track, content="a b", words=target_words, style=None)
    payload = {"clips": [s.clip(source)]}
    s.op("paste_attributes", clips=[target], payload=payload, groups=["text"])
    text = s.clip(target)["text"]
    check("paste_attributes copies word_style, keeps content and words",
          text["word_style"] == s.clip(source)["text"]["word_style"]
          and text["content"] == "a b" and text["words"] == target_words, f"{text}")


def control(s, second):
    # The split's second half starts at 10 frames with starts rebased to
    # [-200000, -80000, 80000, 160000]: at t = 15 frames it is on word 3, at
    # 19 frames on word 4. Everything else on the canvas is static there.
    a_path, a = render(s, 15 * FRAME)
    b_path, b = render(s, 19 * FRAME)
    check("two frames a word apart DIFFER (W3 draws the active word)",
          a != b and len(a) > 0 and len(b) > 0, f"{a_path} vs {b_path}")


def resnap(s, clip):
    was = s.words(clip)
    s.op("set_canvas", fps=[24, 1])
    check("set_canvas fps [24, 1] re-snaps every word to the 24 fps grid (D7-3)",
          s.words(clip) == snapped(was, 25_000), f"{was} → {s.words(clip)}")


def save_and_reopen(s):
    s.op("save_project")
    with open(os.path.join(s.path, "project.json"), encoding="utf-8") as stream:
        text = stream.read()
    root = json.loads(text)
    check(f"save_project writes \"version\": {CURRENT_VERSION}",
          f'"version": {CURRENT_VERSION}' in text and root["version"] == CURRENT_VERSION,
          f"version {root.get('version')}")
    texts = [c["text"] for c in root["clips"] if c.get("text")]
    check("…with word_style closing every text object, after animation, case, words",
          texts and all(list(t.keys())[-4:] == ["animation", "case", "words", "word_style"]
                        for t in texts), f"{[list(t.keys())[-4:] for t in texts][:2]}")
    copy = os.path.join(WORK, f"words-reopen-{os.getpid()}.reelcut")
    shutil.rmtree(copy, ignore_errors=True)
    shutil.copytree(s.path, copy)
    s.mcp.call("open_project", path=copy)
    reopened = s.mcp.call_with("get_project", {"project": copy})["project"]
    check("…and re-opens equal", reopened["clips"] == s.project()["clips"])


def run(socket_path):
    os.makedirs(WORK, exist_ok=True)
    mcp = MCP(socket_path)
    print("W1b — word captions, the core (format version 9)")
    version_gate(mcp)
    s = Session(mcp, "words-core")
    first = s.project()["tracks"][0]["id"]
    page = door(s, first)
    second = split_mid_page(s, page)
    split_after_action(s, s.track("After action"))
    trimmed = trims(s, s.track("Trims"))
    edges(s, s.track("Edges"))
    paste_attributes(s, s.track("Paste"), second)
    control(s, second)
    resnap(s, trimmed)
    save_and_reopen(s)
    print(f"{passed}/{passed + failed}")
    return 1 if failed else 0


# ---- the mutants ---------------------------------------------------------


def replace_once(path, before, after):
    with open(path, encoding="utf-8") as stream:
        text = stream.read()
    count = text.count(before)
    if count != 1:
        raise RuntimeError(f"mutation anchor {os.path.basename(path)}: expected once, "
                           f"found {count}: {before!r}")
    with open(path, "w", encoding="utf-8") as stream:
        stream.write(text.replace(before, after))


MUTANTS = {
    "hash-arm": (
        "recipe_text.rs",
        '    if let Some(words) = words {\n'
        '        keyed.insert("word".to_string(), Value::from(words.word));\n'
        '        keyed.insert(\n'
        '            "word_pop".to_string(),\n'
        '            words.pop.map_or(Value::Null, number),\n'
        '        );\n'
        '    }\n',
        '    let _ = words;\n',
        "words", "a_styled_page_hashes_a_word_apart_differently",
    ),
    "trim-rebase": (
        "edit_clip_timing.rs",
        "        if let Some(text) = moved.text.as_mut() {\n"
        "            rebase_words(text, delta);\n"
        "        }\n",
        "",
        "words", "trim_start_rebases_the_words_by_its_delta",
    ),
    "count-check": (
        "props_check.rs",
        "        if props.words.len() != tokens {\n",
        "        if false && props.words.len() != tokens {\n",
        "schema_v9", "a_count_mismatch_is_an_error_in_the_rules_own_words",
    ),
}


def mutant(name):
    file, before, after, suite, test = MUTANTS[name]
    with tempfile.TemporaryDirectory(prefix=f"reelcut-words-{name}-") as temp:
        core = os.path.join(temp, "core")
        shutil.copytree(os.path.join(ROOT, "core"), core,
                        ignore=shutil.ignore_patterns("target", ".git", ".DS_Store"))
        replace_once(os.path.join(core, "src", file), before, after)
        environment = dict(os.environ, CARGO_TARGET_DIR=os.path.join(temp, "target"))
        command = ["cargo", "test", "--release", "--test", suite, test]
        print("RUN", " ".join(command), "in", core, flush=True)
        try:
            result = subprocess.run(command, cwd=core, env=environment, text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    timeout=900, start_new_session=True)
        except subprocess.TimeoutExpired:
            print(f"MUTANT FAILURE: {name}: cargo did not finish in 900 s")
            return 2
        output = result.stdout
        compiled = "Finished `release` profile" in output
        caught = f"test {test} ... FAILED" in output
        print("\n".join(line for line in output.splitlines()
                        if line.startswith(("test ", "test result", "error"))
                        or "panicked" in line))
        if compiled and caught and result.returncode != 0:
            print(f"MUTANT PASS: {name} — {suite}::{test} FAILED in the copy")
            return 0
        print(f"MUTANT FAILURE: {name} — compiled {compiled}, caught {caught}, "
              f"rc {result.returncode}")
        return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant" and sys.argv[2] in MUTANTS:
        return mutant(sys.argv[2])
    if len(sys.argv) == 2 and not sys.argv[1].startswith("--"):
        return run(target(sys.argv))
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main())
