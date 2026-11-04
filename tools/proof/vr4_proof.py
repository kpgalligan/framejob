#!/usr/bin/env python3
"""Road map "creator-jobs" VR4a — word caption pages re-paged from their own words (spec §11
VR-40), text presets by the short side (VR-41), File ▸ Re-lay Captions for This Canvas and
`relay_captions` (VR-45); the proof is VR-46.

    python3 tools/proof/vr4_proof.py [--only R2,R8] [--app PATH] [--mutant NAME]

**The probe** (`vr4_probe.swift`, built with `swift_build.py`'s line over `app/Sources` with
`FRAMEJOB_DEV_TOOLS`, no app) answers R1, R6 and R10, lays R4's five styles' pages on
1920 × 1080 (`pages`: `CaptionPages.build` + `CaptionLayout.place`, sent here as op tools), and
measures a project's pages for R8 (`measure`).

**The fixture** (`src.framejob`, 1920 × 1080 at 30 fps, saved): the probe's pages on eight
caption tracks, back to front — "Captions" Highlight + Fill, with one page cut by `split`
mid-page, one trimmed by `trim_start` past its first word and one word corrected by `set_text`;
"Captions 2" Pill + Slide; "Captions 3" Karaoke, hidden and locked; "Captions 4" Build;
"Captions 5" One Word; "Captions 6" Highlight pages set in Anton (a style Frame Job does not
make); "Captions 7" Pill + Slide with one page edited untimed (its content's word count changed,
`words: []`); and "Captions 8" Subtitles from `import_captions`. Copies of the saved package are
opened for each row group.

Rows:
  R1  (probe) every line of every re-paged page, measured as `CaptionPages` measures it, is
      within 0.86 × 1080, a lone word carrying `width` excepted.
  R2  on copy A after `set_canvas 1080 × 1920` and the menu, "Captions" is re-laid (none of its
      old clip ids left) and the multiset of (timeline start, token) over its pages equals the
      source's over the words starting inside each source page — the split's two halves and the
      trimmed page included, so each word lands once, in the half its start lies in — and every
      new page lies inside one source page's window.
  R3  the corrected word is there at its start.
  R4  "Captions" … "Captions 5" are re-laid each in its own font and `word_style`, looks
      included, as the source pages; "Captions 6" is kept, its clip ids and font unchanged.
  R5  "Captions 7" (untimed page) and "Captions 8" (Subtitles) keep their clip ids and are kept
      with "it holds a page with no word timings"; in Make Vertical (copy C) every clip of them is
      `kept` and its scale rescaled by `keep` (× 0.5625).
  R6  (probe) Caption's size, wrap and y on 1080 × 1920 at the three sites (38, 864, 480), the
      old formula byte for byte on 1920 × 1080 and 1080 × 1080, and `overTwoLines` counted.
  R7  `make_vertical_version {shape: 9:16, copy: false}` (copy C) answers `captions.relaid` the
      five and `captions.kept` the three as one undo step "Make Vertical"; with `captions: false`
      (copy D) the answer has no `captions` key and every caption clip is `kept`.
  R8  copy A: `set_canvas`, then File ▸ Re-lay Captions for This Canvas (`perform_menu_item`):
      one undo step "Re-lay Captions" (undo gives the `set_canvas` project back), R1's measure
      holds over the re-laid tracks' pages, the notice (`snapshot_ui`, whose layout dump keeps
      a label's first 200 characters) names "Captions 6" and the untimed "Captions 7" with its
      reason; `relay_captions` on copy B gives the same `get_project`; on a project with
      no caption track the item is disabled.
  R9  every re-laid track keeps its index and name, and "Captions 3" its hidden and locked flags.
  R10 (probe) Make Vertical with a recognised track whose re-page throws `tooMany`: the track in
      `captions.kept` with `tooMany`'s description, each of its clips with a `reframe_clip` keep
      op and a `kept` entry, the plan applied.
  Z0  `grep "Frame Job: "` in the instance's log prints nothing.

Mutants (spec §11 VR-46), `--mutant NAME`: a probe mutant edits a copy of `app/Sources` and
builds the probe from it; an app mutant edits the tree's `app/Sources`, runs `make app-debug`,
runs its rows against that Debug app, then puts the file back and runs `make app-debug` again.
A mutant run exits 1 when every named row failed (caught), 0 when one passed (survived), 2 when
the control could not be performed (an edit's `before` text not found exactly once, a build
failure, or a named row not scored). A plain run exits 0 iff every row passed.
"""

import argparse
import json
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
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/vr4-proof"
HOME = WORK / "home"
CALL_BOUND = 400
SEC = 600_000
MENU = ["File", "Re-lay Captions for This Canvas"]
PROBE_ROWS = ["R1", "R6", "R10"]
APP_ROWS = ["R2", "R3", "R4", "R5", "R7", "R8", "R9", "Z0"]
ROWS = ["R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9", "R10", "Z0"]
RELAID = ["Captions", "Captions 2", "Captions 3", "Captions 4", "Captions 5"]
KEPT = ["Captions 6", "Captions 7", "Captions 8"]
UNTIMED = "it holds a page with no word timings"

# name: (rows, "probe" | "app", [(file, before, after), ...]) — spec §11 VR-46.
MUTANTS = {
    "old-width": (["R1"], "probe", [
        ("CaptionRelayout.swift",
         "            let canvas = CGSize(width: before.canvas.width, height: before.canvas.height)\n",
         "            let canvas = CGSize(\n"
         "                width: max(before.canvas.width, before.canvas.height),\n"
         "                height: min(before.canvas.width, before.canvas.height))\n")]),
    "clip-time": (["R2"], "app", [
        ("CaptionRelayout.swift",
         "            let start = clip.start + word.start\n",
         "            let start = word.start\n")]),
    "lead-applied": (["R2"], "app", [
        ("CaptionPages.swift",
         "            normalize(words, lead: 0, span: span, frame: frame), span: span, request: request,\n",
         "            normalize(words, lead: lead(for: .apple), span: span, frame: frame), span: span,\n"
         "            request: request,\n")]),
    "subtitles-fallback": (["R4"], "app", [
        ("CaptionRelayout.swift",
         "        return nil\n    }\n\n    /// VR-40 (c)",
         "        return (.subtitles, .none)\n    }\n\n    /// VR-40 (c)")]),
    "apply-height": (["R6"], "probe", [
        ("TextPane.swift",
         "                font: font, size: size(on: canvas), align: align, valign: \"middle\",\n",
         "                font: font, size: (sizeFraction * Double(canvas.height)).rounded(),\n"
         "                align: align, valign: \"middle\",\n")]),
    "replace-unrecognised": (["R5", "R8"], "app", [
        ("CaptionRelayout.swift",
         "            if timed.contains(where: { $0 == nil }) {\n",
         "            if timed.allSatisfy({ $0 == nil }) {\n"),
        ("CaptionRelayout.swift",
         "            if timed.contains(where: { $0?.isEmpty ?? true }) {\n",
         "            if timed.contains(where: { $0?.isEmpty ?? false }) {\n")]),
    "front-track": (["R9"], "app", [
        ("CaptionRelayout.swift",
         "            var follow: [ReelOp] = [.moveTrack(track: made.id, index: index)]\n",
         "            var follow: [ReelOp] = []\n")]),
    "all-words": (["R2"], "app", [
        ("CaptionRelayout.swift",
         "            guard inside.contains(start) else { return nil }\n",
         "")]),
    "failed-unkept": (["R10"], "probe", [
        ("VerticalVersion+Plan.swift",
         "            for (id, _) in roles {\n"
         "                guard let clip = old.clip(id), unlaid.contains(clip.track) else { continue }\n",
         "            for (id, _) in roles where id == 0 {\n"
         "                guard let clip = old.clip(id), unlaid.contains(clip.track) else { continue }\n")]),
}

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def attempt_rows(body, rows):
    """A throw fails every named row that has not answered yet."""
    try:
        return body()
    except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
        for row in rows:
            if row in selected and row not in results:
                check(row, False, f"{type(error).__name__}: {error}")
        return None


# ---- the probe --------------------------------------------------------------------

def build_probe(sources, here):
    entry = here / "main.swift"
    here.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(HERE / "vr4_probe.swift", entry)
    binary = here / "vr4-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [str(entry)], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + ("; ".join(error.diagnostics[:8]) or str(error))
    return binary, None


def run_probe(binary, here, *arguments, wall=600):
    result = subprocess.run([str(binary), str(here / "files"), *arguments],
                            capture_output=True, text=True, timeout=wall)
    (here / f"stderr-{arguments[0]}.txt").write_text(result.stderr)
    if result.returncode != 0:
        raise RuntimeError(f"probe {arguments[0]} exit {result.returncode}: "
                           f"{result.stderr[-300:]}")
    return json.loads(result.stdout)


def probe_rows(binary, here):
    if not selected & set(PROBE_ROWS):
        return
    answer = run_probe(binary, here, "main")
    for entry in answer["rows"]:
        check(entry["id"], entry["pass"], entry["detail"])


# ---- the documents ----------------------------------------------------------------

class Doc:
    def __init__(self, client, path):
        self.client = client
        self.path = Path(path)

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def undo_top(self):
        try:
            name = self.call("undo").get("undone")
        except mcp.ToolError:
            return None
        self.call("redo")
        return name

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def tracks_named(state):
    return {t["name"]: (i, t) for i, t in enumerate(state["tracks"])}


def clips_on(state, name):
    found = tracks_named(state).get(name)
    if not found:
        return []
    track = found[1]["id"]
    return sorted((c for c in state["clips"] if c["track"] == track), key=lambda c: c["start"])


def words_inside(clip):
    """(timeline start, token) per word starting inside the clip (VR-40 (c))."""
    text = clip.get("text") or {}
    tokens = (text.get("content") or "").split()
    words = text.get("words") or []
    if len(tokens) != len(words):
        return []
    lo, hi = clip["start"], clip["start"] + clip["duration"]
    return [(clip["start"] + w["start"], t) for t, w in zip(tokens, words)
            if lo <= clip["start"] + w["start"] < hi]


def make_fixture(client, pages):
    path = WORK / "src.framejob"
    if path.exists():
        shutil.rmtree(path)
    client.call("new_project", path=str(path))
    doc = Doc(client, path)
    canvas = doc.state()["canvas"]
    if (canvas["width"], canvas["height"]) != (1920, 1080):
        doc.call("set_canvas", width=1920, height=1080, fps=[30, 1])
    by_style = {p["style"]: p for p in pages}
    plan = [("Captions", "highlight"), ("Captions 2", "pill"), ("Captions 3", "karaoke"),
            ("Captions 4", "build"), ("Captions 5", "one_word"), ("Captions 6", "highlight"),
            ("Captions 7", "pill")]
    for name, style in plan:
        index = len(doc.state()["tracks"])
        doc.call("add_track", index=index, name=name)
        track = doc.state()["tracks"][index]["id"]
        made = []
        for clip in by_style[style]["clips"]:
            made += doc.call("add_text_clip", track=track, at=clip["at"],
                             duration=clip["duration"], text=clip["text"])["new_clips"]
        doc.call("set_video", clips=made, patch=by_style[style]["video"])
    # "Captions": a page cut mid-page, a page trimmed past its first word, a word corrected.
    pages_1 = [c for c in clips_on(doc.state(), "Captions") if len(c["text"]["words"]) >= 4]
    cut, trimmed, corrected = pages_1[0], pages_1[1], pages_1[2]
    frame = 20_000
    w = cut["text"]["words"]
    at = cut["start"] + ((w[1]["start"] + w[2]["start"]) // 2 // frame) * frame
    doc.call("split", clips=[cut["id"]], at=at)
    w = trimmed["text"]["words"]
    to = trimmed["start"] + ((w[0]["start"] + w[1]["start"]) // 2 // frame + 1) * frame
    doc.call("trim_start", clip=trimmed["id"], to=to)
    tokens = corrected["text"]["content"].split(" ")
    tokens[1] = "CORRECTED"
    fixed = " ".join(tokens)
    doc.call("set_text", clips=[corrected["id"]], patch={"content": fixed})
    corrected_start = corrected["start"] + corrected["text"]["words"][1]["start"]
    # "Captions 6": Highlight pages in a face no style uses.
    six = [c["id"] for c in clips_on(doc.state(), "Captions 6")]
    doc.call("set_text", clips=six, patch={"font": "Anton-Regular"})
    # "Captions 7": one page left untimed by a content edit that changed its word count.
    seven = clips_on(doc.state(), "Captions 7")[0]
    doc.call("set_text", clips=[seven["id"]],
             patch={"content": seven["text"]["content"] + " again", "words": []})
    # "Captions 3" hidden and locked, after its pages are on it.
    three = tracks_named(doc.state())["Captions 3"][1]["id"]
    doc.call("set_track", track=three, hidden=True, locked=True)
    srt = WORK / "subs.srt"
    srt.write_text("1\n00:00:01,000 --> 00:00:03,000\nA Subtitles line\n\n"
                   "2\n00:00:04,000 --> 00:00:06,000\nAnd another one\n")
    doc.call("import_captions", path=str(srt))
    doc.call("save_project")
    state = doc.state()
    if "Captions 8" not in tracks_named(state):
        raise RuntimeError(f"import_captions made tracks {list(tracks_named(state))}")
    return doc, state, {"cut": cut["id"], "trimmed": trimmed["id"], "corrected": corrected_start,
                        "token": "CORRECTED"}


def copy_of(client, src, name):
    path = WORK / f"{name}.framejob"
    if path.exists():
        shutil.rmtree(path)
    shutil.copytree(src, path)
    client.call("open_project", path=str(path))
    return Doc(client, path)


def measured(binary, here, state, names):
    """The probe's measure of the pages on the tracks `names`."""
    project = WORK / "measure.json"
    project.write_text(json.dumps(state))
    return run_probe(binary, here, "measure", str(project), ",".join(names))


def sheet_texts(doc, tag):
    (WORK / "sheets").mkdir(parents=True, exist_ok=True)
    try:
        got = doc.call("snapshot_ui", window="sheet", path=str(WORK / "sheets" / f"{tag}.png"))
    except mcp.ToolError:
        return None
    path = got.get("layout_path") if isinstance(got, dict) else None
    if not path:
        return None
    return [v.get("text") or "" for v in json.loads(Path(path).read_text()).get("views") or []]


# ---- the rows ---------------------------------------------------------------------

def app_rows(client, binary, here, pages):
    src, s0, marks = make_fixture(client, pages)
    a = copy_of(client, src.path, "a")
    a.call("set_canvas", width=1080, height=1920)
    s1 = a.state()
    a.call("perform_menu_item", path=MENU)
    s2 = a.state()
    texts = None
    for _ in range(20):
        texts = sheet_texts(a, "notice")
        if texts:
            break
        time.sleep(0.25)
    if texts is not None:
        try:
            a.call("cancel_sheet")
        except mcp.ToolError:
            pass
    undone = a.call("undo").get("undone")
    back = a.state() == s1
    a.call("redo")
    again = a.state() == s2
    b = copy_of(client, src.path, "b")
    b.call("set_canvas", width=1080, height=1920)
    answer_b = b.call("relay_captions")
    same = b.state() == s2
    relaid_b = {r["name"]: r for r in answer_b.get("relaid", [])}
    kept_b = {k["name"]: k for k in answer_b.get("kept", [])}

    # R2 and R3
    old_words = sorted(w for c in clips_on(s0, "Captions") for w in words_inside(c))
    new_clips = clips_on(s2, "Captions")
    new_words = sorted((c["start"] + w["start"], t) for c in new_clips
                       for t, w in zip(c["text"]["content"].split(), c["text"]["words"]))
    old_ids = {c["id"] for c in clips_on(s0, "Captions")}
    windows = [(c["start"], c["start"] + c["duration"]) for c in clips_on(s0, "Captions")]
    outside = [c["id"] for c in new_clips
               if not any(lo <= c["start"] and c["start"] + c["duration"] <= hi
                          for lo, hi in windows)]
    loose = [c["id"] for c in new_clips
             for w in c["text"]["words"] if not 0 <= w["start"] < c["duration"]]
    replaced = bool(new_clips) and not ({c["id"] for c in new_clips} & old_ids)
    check("R2", replaced and new_words == old_words and len(set(new_words)) == len(new_words)
          and not outside and not loose,
          f"re-laid {replaced}: {len(new_words)} words over {len(new_clips)} pages against "
          f"{len(old_words)} in the source (equal {new_words == old_words}, distinct "
          f"{len(set(new_words)) == len(new_words)}); pages outside a source page {outside}, "
          f"words outside their page {loose[:5]}")
    check("R3", (marks["corrected"], marks["token"]) in new_words,
          f"{marks['token']} at {marks['corrected']} present "
          f"{(marks['corrected'], marks['token']) in new_words}")

    # R4
    problems = []
    for name in RELAID:
        source = clips_on(s0, name)
        made = clips_on(s2, name)
        want = (source[0]["text"]["font"], source[0]["text"].get("word_style")) if source else None
        bad = [c["id"] for c in made
               if (c["text"]["font"], c["text"].get("word_style")) != want]
        if not made or bad or {c["id"] for c in made} & {c["id"] for c in source}:
            problems.append(f"{name}: {len(made)} pages, off-style {bad[:4]}")
    six_old, six_new = clips_on(s0, "Captions 6"), clips_on(s2, "Captions 6")
    six_kept = ([c["id"] for c in six_old] == [c["id"] for c in six_new]
                and all(c["text"]["font"] == "Anton-Regular" for c in six_new)
                and "Captions 6" in kept_b)
    check("R4", not problems and six_kept,
          f"{len(RELAID)} styles re-laid in their own font and word_style "
          f"{'; '.join(problems) or 'all'}; Captions 6 kept as it was {six_kept} "
          f"({(kept_b.get('Captions 6') or {}).get('reason')!r})")

    # R9
    before, after = tracks_named(s0), tracks_named(s2)
    moved = [n for n in RELAID if n not in after or after[n][0] != before[n][0]]
    flags = after.get("Captions 3", (0, {}))[1]
    check("R9", not moved and flags.get("hidden") is True and flags.get("locked") is True,
          f"indices kept except {moved}; Captions 3 hidden {flags.get('hidden')} locked "
          f"{flags.get('locked')} at {after.get('Captions 3', (None,))[0]} (was "
          f"{before['Captions 3'][0]})")

    # R8
    got = measured(binary, here, s2, RELAID)
    # The layout dump keeps a label's first 200 characters, which name the first two kept
    # tracks: "Captions 6" and the untimed "Captions 7".
    named = texts is not None and any(
        '"Captions 7" is kept as placed: ' + UNTIMED in t and '"Captions 6"' in t
        for t in texts)
    fresh = WORK / "empty.framejob"
    if fresh.exists():
        shutil.rmtree(fresh)
    client.call("new_project", path=str(fresh))
    empty = Doc(client, fresh)
    try:
        empty.call("perform_menu_item", path=MENU)
        disabled, why = False, "performed"
    except mcp.ToolError as error:
        why = str(error)
        disabled = "is disabled here" in why
    empty.close()
    check("R8", undone == "Re-lay Captions" and back and again and same and not got["over"]
          and got["pages"] > 0 and named and disabled,
          f"undo {undone!r}, the set_canvas project back {back}, redo {again}; relay_captions "
          f"on copy B the same project {same}; {got['pages']} pages, widest line "
          f"{got['worst']:.0f} px of {got['budget']:.1f}, over {got['over'][:3]}; the notice "
          f"names Captions 6 and the untimed Captions 7 {named}; with no caption track: "
          f"{why[:80]!r}")

    # R5
    untouched = all([c["id"] for c in clips_on(s0, n)] == [c["id"] for c in clips_on(s2, n)]
                    for n in ("Captions 7", "Captions 8"))
    reasons = {n: (kept_b.get(n) or {}).get("reason") for n in ("Captions 7", "Captions 8")}
    c = copy_of(client, src.path, "c")
    answer_c = c.call("make_vertical_version", shape="9:16", copy=False)
    s_c = c.state()
    treatment = {e["clip"]: e["treatment"] for e in answer_c.get("clips", [])}
    rescaled = []
    for n in ("Captions 7", "Captions 8"):
        for old in clips_on(s0, n):
            new = next((x for x in s_c["clips"] if x["id"] == old["id"]), None)
            scale = ((old.get("video") or {}).get("scale", 1.0)) * 0.5625
            if (new is None or treatment.get(old["id"]) != "kept"
                    or abs((new.get("video") or {}).get("scale", 1.0) - scale) > 1e-6):
                rescaled.append(old["id"])
    check("R5", untouched and all(r == UNTIMED for r in reasons.values()) and not rescaled,
          f"clip ids kept {untouched}; reasons {reasons}; in Make Vertical not kept or not "
          f"rescaled {rescaled}")

    # R7
    captions = answer_c.get("captions") or {}
    relaid_c = sorted(r["name"] for r in captions.get("relaid", []))
    kept_c = sorted(k["name"] for k in captions.get("kept", []))
    undo_c = c.call("undo").get("undone")
    back_c = c.state() == s0
    d = copy_of(client, src.path, "d")
    answer_d = d.call("make_vertical_version", shape="9:16", copy=False, captions=False)
    caption_ids = [x["id"] for n in RELAID + KEPT for x in clips_on(s0, n)]
    treat_d = {e["clip"]: e["treatment"] for e in answer_d.get("clips", [])}
    not_kept = [i for i in caption_ids if treat_d.get(i) != "kept"]
    check("R7", relaid_c == sorted(RELAID) and kept_c == sorted(KEPT) and undo_c == "Make Vertical"
          and back_c and "captions" not in answer_d and not not_kept,
          f"relaid {relaid_c}, kept {kept_c}; undo {undo_c!r} gives the source back {back_c}; "
          f"captions false: a captions key {'captions' in answer_d}, caption clips not kept "
          f"{not_kept[:5]}")
    for doc in (a, b, c, d, src):
        doc.close()


# ---- launches ---------------------------------------------------------------------

def parity(log):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z0", not lines, f"grep 'Frame Job: ' in {log.name} printed {lines[:3] or 'nothing'}")


def run_app(app, binary, here, pages):
    log = WORK / "instance.log"
    launched = mcp.launch(str(app), [], env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in APP_ROWS:
                check(row, False, "the app did not listen")
        else:
            print(f"  instance PID {launched.child.pid}", flush=True)
            attempt_rows(lambda: app_rows(launched.client, binary, here, pages),
                         [row for row in APP_ROWS if row != "Z0"])
    finally:
        launched.stop()
    parity(log)


def mutate(sources, edits):
    """Applies `edits` under `sources`; the originals, or None and why."""
    originals = {}
    edited = {}
    for file, before, after in edits:
        path = Path(sources) / file
        originals.setdefault(path, path.read_text())
        current = edited.get(path, originals[path])
        if current.count(before) != 1:
            return None, f"{file}: `{before.strip()[:60]}` found {current.count(before)} times"
        edited[path] = current.replace(before, after)
    for path, text in edited.items():
        path.write_text(text)
    return originals, None


def make_debug(tag):
    log = WORK / f"make-app-debug-{tag}.log"
    with open(log, "w") as out:
        code = subprocess.run(["make", "app-debug"], cwd=ROOT, stdout=out,
                              stderr=subprocess.STDOUT).returncode
    return code == 0, log


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--app")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    named, kind, edits = MUTANTS[args.mutant] if args.mutant else ([], None, [])
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
    elif args.mutant:
        selected = set(named)
    unknown = selected - set(ROWS)
    if unknown:
        print(f"unknown rows: {sorted(unknown)}")
        return 2
    if selected & set(APP_ROWS):
        selected |= {"Z0"}
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    HOME.mkdir(parents=True)
    here = WORK / "probe"
    sources = ROOT / "app/Sources"
    originals = None
    if args.mutant and kind == "probe":
        shutil.copytree(sources, WORK / "Sources")
        sources = WORK / "Sources"
        originals, why = mutate(sources, edits)
    elif args.mutant:
        originals, why = mutate(sources, edits)
    if args.mutant and originals is None:
        print(f"mutant {args.mutant}: the control could not be performed — {why}")
        return 2
    try:
        print(f"VR4a — captions re-paged, presets by the short side, Re-lay Captions"
              f"{f' (mutant {args.mutant})' if args.mutant else ''}", flush=True)
        binary, why = build_probe(sources, here)
        if binary is None:
            for row in sorted(selected):
                check(row, False, f"the probe did not build: {why}")
            if args.mutant:
                print(f"mutant {args.mutant}: the control could not be performed — {why}")
                return 2
        else:
            attempt_rows(lambda: probe_rows(binary, here), PROBE_ROWS)
            if selected & set(APP_ROWS):
                if args.mutant and kind == "app":
                    built, log = make_debug(args.mutant)
                    if not built:
                        print(f"mutant {args.mutant}: the control could not be performed — "
                              f"make app-debug failed ({log})")
                        return 2
                pages = run_probe(binary, here, "pages", str(WORK / "pages.json"))
                pages = json.loads((WORK / "pages.json").read_text()) if pages else []
                app = Path(args.app) if args.app else proof_app.binary()
                if app.suffix == ".app":
                    app = proof_app.executable(app)
                print(f"  app: {app} ({proof_app.config()} build)", flush=True)
                run_app(app, binary, here, pages)
    finally:
        if args.mutant and kind == "app" and originals:
            for path, text in originals.items():
                path.write_text(text)
            built, log = make_debug("restored")
            print(f"  tree restored; make app-debug {'ok' if built else 'FAILED'} ({log.name})")
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    if not args.mutant:
        return 0 if not failed and passed else 1
    lost = [row for row in named if row not in results]
    if lost:
        print(f"mutant {args.mutant}: the control could not be performed — row(s) not scored: "
              f"{', '.join(lost)}")
        return 2
    survived = [row for row in named if row not in failed]
    if survived:
        print(f"mutant {args.mutant}: SURVIVED — {', '.join(survived)} passed")
        return 0
    print(f"mutant {args.mutant}: caught — {', '.join(named)} failed")
    return 1


if __name__ == "__main__":
    sys.exit(main())
