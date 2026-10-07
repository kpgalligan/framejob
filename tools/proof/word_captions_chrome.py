#!/usr/bin/env python3
"""Word captions, the Generate Captions sheet: road map 8's W4b (§10.10).

Two halves.

PHOTOGRAPHS, through `tools/proof/harness/`'s `transcribe` mode (the root
CLAUDE.md's "Seeing the chrome"): the card hosted as a window's content, over
three v9 packages written under `work/chrome-words-sheet/` — one audio media
over `tools/proof/media/speech.aiff` (it must exist: `mediaURL(for:)` drops a
missing file) and one clip on it —

  tall    1080×1920
  wide    1920×1080
  track   1080×1920 with a "Captions" track holding one text clip over the clip

CONTROL  tall, Subtitles, light, rendered twice, is byte-identical;
then the six styles are six distinct PNGs per appearance, each style differs
light vs dark, Highlight differs 9:16 vs 16:9, and `track` with Replace
checked differs from `tall` with Replace asked for (which stays off). Issue
batch B86 phase 2 (spec §11 W-15): `tall`, light, with one look box ticked
(the mode's `looks` argument) — Pill with Slide, Karaoke with Fill, Highlight
with Dim — each differs from the same style with none.

STRUCTURE, through `word_captions_sheet_probe.swift` compiled over
`app/Sources` with `harness/build.sh`'s swiftc line (a probe that will not
build is a scored FAILURE), with `word_captions_sheet_support.swift` beside
it: rows S1–S16 (S10–S16 are the three look boxes: their titles and live
table, the row's layout and the note, the remembered keys, the greyed box
that keeps its tick, what a commit writes, the preview's two frames).

    python3 tools/proof/word_captions_chrome.py
    python3 tools/proof/word_captions_chrome.py --mutant NAME

A mutant is built from a COPY of `app/Sources` with each anchor asserted to
occur exactly once, and only the probe runs; exit 0 means its NAMED row
FAILED in the copy, which is the pass. Run it AFTER anything that builds
`tools/proof/harness`, never beside it.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools/proof"
WORK = HERE / "work/chrome-words-sheet"
BUILD = HERE / "harness/build.sh"
FONTS = ROOT / "app/Resources/Fonts"
SPEECH = HERE / "media/speech.aiff"
STYLES = ["subtitles", "highlight", "pill", "karaoke", "build", "one_word"]
SEC = 600_000
DEADLINE = 900

rows = []


def check(name, good, detail=""):
    rows.append((name, bool(good)))
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""))


# ---- the fixtures ---------------------------------------------------------


def package(name, width, height, captions=False):
    path = WORK / f"{name}.reelcut"
    shutil.rmtree(path, ignore_errors=True)
    path.mkdir(parents=True)
    tracks = [{"id": 1, "name": "Track 1"}]
    clips = [{"id": 10, "track": 1, "start": 0, "duration": 6 * SEC,
              "source": {"kind": "media", "media": 90, "in": 0, "reversed": False},
              "enabled": {"video": True, "audio": True}, "speed": 1.0,
              "video": {}, "audio": {}}]
    if captions:
        tracks.append({"id": 2, "name": "Captions"})
        clips.append({"id": 11, "track": 2, "start": 0, "duration": 2 * SEC,
                      "source": {"kind": "text"}, "video": {},
                      "text": {"content": "Old words"}})
    document = {
        "version": 9,
        "canvas": {"width": width, "height": height, "fps": [30, 1]},
        "media": [{"id": 90, "path": str(SPEECH), "kind": "audio", "duration": 6 * SEC,
                   "width": 0, "height": 0, "fps": [30, 1],
                   "has_video": False, "has_audio": True}],
        "tracks": tracks, "clips": clips, "markers": [], "nests": [], "next_id": 100,
    }
    (path / "project.json").write_text(json.dumps(document), encoding="utf-8")
    return path


def build_harness():
    began = time.time()
    result = subprocess.run([str(BUILD)], capture_output=True, text=True, timeout=DEADLINE)
    if result.returncode != 0:
        return None, (result.stdout + result.stderr).strip()[-400:]
    binary = result.stdout.strip().splitlines()[-1]
    print(f"harness: {binary} ({time.time() - began:.1f} s)")
    return binary, None


def render(binary, package_path, name, appearance, style, replace=0, looks=""):
    out = WORK / f"{name}.png"
    result = subprocess.run(
        [binary, "transcribe", str(package_path), str(out), appearance, style, str(replace),
         looks],
        capture_output=True, text=True, timeout=300)
    if result.returncode != 0 or not out.exists():
        return None, (result.stdout + result.stderr).strip()[-400:]
    return out.read_bytes(), None


def photographs():
    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    tall = package("tall", 1080, 1920)
    wide = package("wide", 1920, 1080)
    track = package("track", 1080, 1920, captions=True)
    binary, error = build_harness()
    check("the harness builds over app/Sources", binary is not None, error or "")
    if not binary:
        return
    shots = {}
    problems = []

    def shoot(key, *args):
        data, problem = render(binary, *args)
        if problem:
            problems.append(f"{key}: {problem}")
        else:
            shots[key] = data

    shoot("control-1", tall, "control-1", "light", "subtitles")
    shoot("control-2", tall, "control-2", "light", "subtitles")
    for appearance in ("light", "dark"):
        for style in STYLES:
            shoot((appearance, style), tall, f"tall-{appearance}-{style}", appearance, style)
    shoot("wide-highlight", wide, "wide-light-highlight", "light", "highlight")
    shoot("track-replace", track, "track-light-highlight-replace", "light", "highlight", 1)
    shoot("tall-replace", tall, "tall-light-highlight-replace", "light", "highlight", 1)
    looked = [("pill", "s", "slide"), ("karaoke", "f", "fill"), ("highlight", "d", "dim")]
    for style, letter, look in looked:
        shoot(("look", style), tall, f"tall-light-{style}-{look}", "light", style, 0, letter)
    check("every render wrote a PNG", not problems, "; ".join(problems[:3]))

    a, b = shots.get("control-1"), shots.get("control-2")
    check("CONTROL: Subtitles, light, rendered twice is byte-identical",
          a is not None and a == b, f"{len(a or b'')} / {len(b or b'')} bytes")
    for appearance in ("light", "dark"):
        got = [shots.get((appearance, s)) for s in STYLES]
        distinct = len({g for g in got if g is not None})
        check(f"the six styles are six distinct PNGs ({appearance})",
              None not in got and distinct == 6, f"{distinct} distinct of {len(got)}")
    same = [s for s in STYLES
            if shots.get(("light", s)) is None or shots.get(("light", s)) == shots.get(("dark", s))]
    check("each style differs light vs dark", not same, f"alike or missing: {same}")
    wide_shot, tall_shot = shots.get("wide-highlight"), shots.get(("light", "highlight"))
    check("Highlight differs 9:16 vs 16:9", wide_shot is not None and tall_shot is not None
          and wide_shot != tall_shot)
    with_track, without = shots.get("track-replace"), shots.get("tall-replace")
    check("a Captions track with Replace checked differs from no track with Replace asked for",
          with_track is not None and without is not None and with_track != without)
    for style, _, look in looked:
        ticked, plain = shots.get(("look", style)), shots.get(("light", style))
        check(f"{style} with {look} ticked differs from {style} with no look (light)",
              ticked is not None and plain is not None and ticked != plain,
              f"{len(ticked or b'')} / {len(plain or b'')} bytes")


# ---- the probe ------------------------------------------------------------


def build_probe(sources, out):
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "word_captions_sheet_probe.swift", entry)
    support = out / "word_captions_sheet_support.swift"
    shutil.copyfile(HERE / "word_captions_sheet_support.swift", support)
    binary = out / "word-captions-sheet-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    sdk = subprocess.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"],
                         capture_output=True, text=True).stdout.strip()
    lib = ROOT / "core/target/release/libreelcut_core.a"
    result = subprocess.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
         "-import-objc-header", str(ROOT / "app/Bridging/Reelcut-Bridging-Header.h"),
         "-L", str(lib.parent), "-lreelcut_core", *swift, str(support), str(entry),
         "-o", str(binary)],
        capture_output=True, text=True, timeout=DEADLINE, start_new_session=True)
    if result.returncode:
        errors = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "; ".join(errors[:8]) or result.stderr[-600:]
    return binary, ""


def probe(sources, out):
    binary, problem = build_probe(sources, out)
    check("the sheet probe builds over app/Sources", binary is not None, problem)
    if binary is None:
        return
    result = subprocess.run([str(binary), str(FONTS), str(SPEECH)], capture_output=True,
                            text=True, timeout=DEADLINE, start_new_session=True)
    try:
        answer = json.loads(result.stdout)
    except json.JSONDecodeError:
        check("the sheet probe answers one JSON object", False,
              (result.stdout[-400:] + result.stderr[-400:]).strip())
        return
    check("the sheet probe answers one JSON object",
          answer.get("ok") is True and answer.get("registered", 0) >= 4,
          f"registered {answer.get('registered')} fonts")
    for row in answer["rows"]:
        check(row["name"], row["ok"], row["detail"])


# ---- mutants --------------------------------------------------------------


def replace_once(path, before, after):
    text = path.read_text(encoding="utf-8")
    count = text.count(before)
    if count != 1:
        raise RuntimeError(f"mutation anchor {path.name}: expected once, found {count}: "
                           f"{before!r}")
    path.write_text(text.replace(before, after), encoding="utf-8")


STYLE = "TranscribeSheetController+Style.swift"
LOOKS = "TranscribeSheetController+Looks.swift"
# name: ([(file, before, after)], the row-name prefix that must FAIL)
MUTANTS = {
    "preview-ignores-style": ([(STYLE,
                                "        let props = previewProps(for: cue, canvas: canvas)\n",
                                "        let props = CaptionStyle.highlight.textProps(\n"
                                "            content: Self.sampleText, size: 80, width: nil)\n")],
                              "S2 "),
    "replace-without-track": ([(STYLE,
                                "        let live = style.isWordStyle && !replaceable.isEmpty\n",
                                "        let live = style.isWordStyle\n")],
                              "S3 no caption track"),
    "style-not-remembered": ([(STYLE,
                               "        defaults.set(style.rawValue, forKey: "
                               "CaptionStyle.defaultsKey)\n", "")], "S4 "),
    "replace-empty-track": ([("CaptionLayout.swift",
                              "            guard snapshot.clips.contains(where: "
                              "{ $0.track == track.id }) else { return nil }\n", "")],
                            "S3 an empty"),
    # W4b residue: the commit's outline wider than the pager measured it with.
    "commit-wider-outline": ([("CaptionStyle.swift",
                               "outline: props.outline.map { .some($0) },",
                               "outline: props.outline.map { .some(OutlineProps(width: "
                               "$0.width * 1.25, color: $0.color)) },")],
                             "S8 a shrunk"),
    # …and the preview measured at the style's size, not the page's.
    "preview-base-size": ([(STYLE,
                            "content: cue.text, size: cue.size ?? style.size(for: canvas), "
                            "width: cue.width,\n",
                            "content: cue.text, size: style.size(for: canvas), "
                            "width: cue.width,\n")],
                          "S8 a shrunk"),
    "preview-redraws": ([(STYLE, "        if key != previewKey {\n",
                          "        if true || key != previewKey {\n")], "S9 "),
    # Issue batch B86 phase 2 (spec §11 W-15): the three look boxes.
    "fill-live-everywhere": ([("CaptionLooks.swift",
                               "                return word.mode == .build || active != upcoming\n",
                               "                return true || word.mode == .build "
                               "|| active != upcoming\n")],
                             "S10 "),
    "note-unbounded": ([(LOOKS,
                         "        dimNoteLabel.preferredMaxLayoutWidth = Self.previewSize.width\n",
                         "")],
                       "S11 before any layout"),
    "note-any-engine": ([(LOOKS,
                          "        dimNoteLabel.isHidden = !(engine == .apple && "
                          "dimCheckbox.isEnabled)\n",
                          "        dimNoteLabel.isHidden = !dimCheckbox.isEnabled\n")],
                        "S12 "),
    "looks-not-remembered": ([(LOOKS,
                               "            defaults.set(checkbox(for: look).state == .on, "
                               "forKey: look.defaultsKey)\n",
                               "            _ = look\n")],
                             "S13 "),
    "greyed-box-counts": ([(LOOKS,
                            "            out[look] = box.isEnabled && box.state == .on\n",
                            "            out[look] = box.state == .on\n")],
                          "S14 "),
    "commit-drops-looks": ([("TranscribeSheetController+Commit.swift",
                             "                style: style, looks: looks, replacing: replacing)\n",
                             "                style: style, replacing: replacing)\n")],
                           "S15 (ii) "),
    # `wordStyle(_:)`'s rebuild forgets one field of the preset: Karaoke's
    # upcoming colour is the one preset value that is not the default there.
    "rebuild-drops-preset": ([("CaptionLooks.swift",
                               "            upcomingColor: preset.upcomingColor,\n", "")],
                             "S15 (ii) karaoke"),
    "preview-ignores-looks": ([(STYLE,
                                "            ? Self.previewReveals(tokens: props.tokenCount, "
                                "looks: looks)\n",
                                "            ? Self.previewReveals(tokens: props.tokenCount, "
                                "looks: .none)\n")],
                              "S16 "),
}


def mutant(name):
    edits, row = MUTANTS[name]
    began = time.time()
    with tempfile.TemporaryDirectory(prefix=f"reelcut-wordsheet-{name}-") as temp:
        sources = Path(temp) / "Sources"
        shutil.copytree(ROOT / "app/Sources", sources)
        for file, before, after in edits:
            replace_once(sources / file, before, after)
        print(f"MUTANT {name}: {len(edits)} anchor(s) replaced once, in {sources}")
        try:
            probe(sources, Path(temp) / "out")
        except subprocess.TimeoutExpired:
            print(f"MUTANT FAILURE: {name} did not finish within {DEADLINE} s")
            return 2
    elapsed = time.time() - began
    built = bool(rows) and rows[0][1]
    failed = [n for n, ok in rows if not ok]
    caught = built and any(n.startswith(row) for n in failed)
    if caught:
        print(f"MUTANT PASS: {name} — {len(failed)} row(s) FAILED in the copy, the named "
              f"{row.strip()!r} among them: {[n[:40] for n in failed]}, {elapsed:.0f} s")
        return 0
    print(f"MUTANT FAILURE: {name} — built {built}, {row.strip()!r} failed: {caught}, failed "
          f"{[n[:40] for n in failed]}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant" and sys.argv[2] in MUTANTS:
        return mutant(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("W4b — the Generate Captions sheet's Style row (chrome + probe)")
    began = time.time()
    try:
        photographs()
        probe(ROOT / "app/Sources", WORK / "probe")
    except subprocess.TimeoutExpired:
        check(f"the run finishes within {DEADLINE} s", False)
    good = sum(1 for _, ok in rows if ok)
    print(f"{good}/{len(rows)} ({time.time() - began:.0f} s)")
    return 0 if rows and all(ok for _, ok in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
