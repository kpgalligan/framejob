#!/usr/bin/env python3
"""Word captions, the picture's arithmetic: road map 8's W3 (§10.7).

Builds `words_picture_probe.swift` over `app/Sources` with
`tools/proof/harness/build.sh`'s swiftc line (a probe that will not build is a
scored FAILURE, never an exit), runs it, and scores what it measured:

P1  the bitmap is `measuredSize` at every word 0…n and pop {0, .3, .58, 1}, for
    four faces × 1080×1920 and 1920×1080, one line and wrapped, valign middle,
    top and bottom, at (active_scale 1.15, default pill), (1.5, default pill)
    and (1.5, no pill) — plus, since W4a, each of §5h's five word styles in its
    own face, case, outline, scale and pill (`CaptionStyle`);
P2  no ink outside that box at any of them, the pill's rows and columns in;
P3  word 1 ≠ word 2; a build page at word 0 has no ink (and at word 1 has);
P4  `laidContent` applies `case`, and on the upper page "straße ist" with a red
    active word: at word 1 the red ink ends left of the LAID midpoint and is
    at least 0.9 × the probe's own "STRASSE" wide; at word 2 it starts right
    of that midpoint;
P5  each bundled face resolves to itself, not the fallback, and the file at
    kCTFontURLAttribute has the pinned sha256;
P6  `contentEdit`'s three cases and `contentOps` (a), (b), (c);
P7  `wordHeadroom` is zero for a colour-only style, ≥ the floors for a pop,
    and at 1.5 / default pill equals the formula and exceeds both floors;
P8  `measuredSize` is equal with and without `words`;
P9  no pill, active_scale 1.5, a ≥ 3-em word: the red ink at pop 1 is at least
    0.95 × 1.5 × its width at pop 0 (the clip scaled with the token).

    python3 tools/proof/words_picture_probe.py
    python3 tools/proof/words_picture_probe.py --mutant NAME

A mutant is built from a COPY of `app/Sources` with one anchor, asserted to
occur exactly once, replaced; exit 0 means at least one row FAILED in the
copy, which is the pass. A mutant copy that does not build is a FAILURE.
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/words-picture-probe"
FONTS = ROOT / "app/Resources/Fonts"
PINNED = {"Montserrat-ExtraBold": "d3ac6a843d3ba6d5", "Montserrat-Black": "ea67b37f8776eebe",
          "Anton-Regular": "a4ba3a92350ebb03", "BebasNeue-Regular": "08e4623805102d81"}
DEADLINE = 1500

rows = []


def check(name, good, detail=""):
    rows.append(bool(good))
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""))


def build(sources, out):
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/words_picture_probe.swift", entry)
    binary = out / "words-picture-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    sdk = subprocess.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"],
                         capture_output=True, text=True).stdout.strip()
    lib = ROOT / "core/target/release/libreelcut_core.a"
    result = subprocess.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
         "-import-objc-header", str(ROOT / "app/Bridging/Reelcut-Bridging-Header.h"),
         "-L", str(lib.parent), "-lreelcut_core", *swift, str(entry), "-o", str(binary)],
        capture_output=True, text=True, timeout=DEADLINE, start_new_session=True)
    if result.returncode:
        errors = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "; ".join(errors[:8]) or result.stderr[-600:]
    return binary, ""


def sha(path):
    with open(path, "rb") as stream:
        return hashlib.sha256(stream.read()).hexdigest()[:16]


def score(answer):
    boxes = answer["boxes"]
    uneven = [b for b in boxes if b["bitmap_sizes"] != [b["measured"]]]
    check(f"P1 the bitmap is measuredSize at every word and pop ({len(boxes)} pages)",
          boxes and not uneven, f"{uneven[:3]}")
    spill = [(b["canvas"], b["face"], b["config"], b["scale"], b["wrapped"], b["valign"],
              b["overflow_px"])
             for b in boxes if max(b["overflow_px"].values()) > 0]
    worst = max((max(b["overflow_px"].values()) for b in boxes), default=None)
    check(f"P2 no ink outside the box at any word or pop, pill included (worst {worst} px)",
          boxes and not spill, f"{spill[:4]}")

    p3 = answer["p3"]
    check("P3 word 1 ≠ word 2, and a build page has no ink at word 0 (and ink at word 1)",
          p3["word1_ne_word2"] and p3["build_word0_ink"] is None
          and isinstance(p3["build_word1_ink"], list), f"{p3}")

    p4 = answer["p4"]
    one, two = p4.get("red_word1"), p4.get("red_word2")
    mid, strasse = p4.get("midpoint"), p4.get("strasse_width")
    good = (p4["laid_upper"] == "STRASSE IST" and p4["laid_as_written"] == "straße ist"
            and isinstance(one, list) and isinstance(two, list) and mid is not None
            and one[2] <= mid and (one[2] - one[0]) >= 0.9 * strasse and two[0] > mid)
    check("P4 laidContent applies case; the red word keeps to its side of the LAID midpoint, "
          "and word 1 is as wide as STRASSE", good,
          f"laid {p4['laid_upper']!r}/{p4['laid_as_written']!r}, midpoint {mid}, "
          f"STRASSE {strasse}, red@1 {one}, red@2 {two}")

    faces = answer["p5"]
    bad = []
    for face in faces:
        name = face["face"]
        pinned = PINNED[name]
        found = sha(face["file"]) if face["file"] and os.path.exists(face["file"]) else None
        if face["postscript"] != name or face["postscript"] == face["fallback"] \
                or found != pinned:
            bad.append((name, face["postscript"], face["file"], found, pinned))
    check("P5 each bundled face resolves to itself, not the fallback, from the pinned file",
          len(faces) == 4 and not bad, f"{bad}")

    p6 = answer["p6"]
    a, b, c = p6["a"], p6["b"], p6["c"]
    good = (p6["untimed_keeps"] and p6["agree_keeps"] and p6["mismatch_clears"]
            and len(a) == 2 and all(o["name"] == "set_text" for o in a)
            and '"clips":[2]' in a[0]["json"] and '"words":[]' in a[0]["json"]
            and '"clips":[1]' in a[1]["json"] and '"words"' not in a[1]["json"]
            and len(b) == 1 and b[0]["name"] == "set_action_end" and '"words"' not in b[0]["json"]
            and len(c) == 2 and c[0]["name"] == "set_text" and '"words":[]' in c[0]["json"]
            and c[1]["name"] == "set_action_end" and '"words"' not in c[1]["json"])
    check("P6 contentEdit's three cases, and contentOps (a) (b) (c) per clip, never words "
          "in an action end", good, json.dumps(p6)[:900])

    p7 = answer["p7"]
    em = p7["em"]
    w, h = p7["pop150"]
    fw, fh = p7["formula150"]
    good = (p7["colour_only"] == [0, 0]
            and p7["pop115"][0] >= 0.45 * em - 1e-9 and p7["pop115"][1] >= 0.30 * em - 1e-9
            and abs(w - fw) < 1e-6 and abs(h - fh) < 1e-6
            and w > 0.45 * em and h > 0.30 * em)
    check("P7 headroom: zero colour-only, floors for a pop, the formula past both floors at 1.5",
          good, f"{p7}")

    p8 = answer["p8"]
    check("P8 measuredSize is equal with and without words", p8["with"] == p8["without"],
          f"{p8}")

    p9 = answer["p9"]
    zero, full = p9.get("red_pop0"), p9.get("red_pop1")
    good = (isinstance(zero, list) and isinstance(full, list) and p9["word_em"] >= 3
            and (full[2] - full[0]) >= 0.95 * 1.5 * (zero[2] - zero[0]))
    check("P9 the popped word's ink scales with it: pop 1 ≥ 0.95 × 1.5 × pop 0", good,
          f"{p9}")


def run(sources, out):
    began = time.time()
    binary, problem = build(sources, out)
    check("the probe builds over app/Sources", binary is not None, problem)
    if binary is None:
        return
    result = subprocess.run([str(binary), str(FONTS)], capture_output=True, text=True,
                            timeout=max(DEADLINE - (time.time() - began), 60),
                            start_new_session=True)
    try:
        answer = json.loads(result.stdout)
    except json.JSONDecodeError:
        check("the probe answers one JSON object", False,
              (result.stdout[-400:] + result.stderr[-400:]).strip())
        return
    check("the probe answers one JSON object", answer.get("ok") is True
          and answer.get("registered", 0) >= 4, f"registered {answer.get('registered')}")
    (out / "answer.json").write_text(json.dumps(answer, indent=1, sort_keys=True))
    score(answer)


def replace_once(path, before, after):
    text = path.read_text(encoding="utf-8")
    count = text.count(before)
    if count != 1:
        raise RuntimeError(f"mutation anchor {path.name}: expected once, found {count}: "
                           f"{before!r}")
    path.write_text(text.replace(before, after), encoding="utf-8")


MUTANTS = {
    "ignore-word": ("LayerRenderersText.swift",
                    "        if let word = reveal.word, let style = props.wordStyle {\n",
                    "        if false, let word = reveal.word, let style = props.wordStyle {\n"),
    "drop-headroom": ("LayerRenderersText.swift",
                      "        return (x: base + headroom.width, y: base + headroom.height)\n",
                      "        _ = headroom\n        return (x: base, y: base)\n"),
    "skip-case": ("WordProps.swift",
                  "    var laidContent: String { textCase == .upper ? content.uppercased() "
                  ": content }\n",
                  "    var laidContent: String { content }\n"),
    "keep-words": ("WordProps.swift",
                   "        return TextPatch(content: content, words: [])\n",
                   "        return TextPatch(content: content)\n"),
    "clip-then-scale": ("LayerRenderersWords.swift",
                        "            // (a) the pop, about the pill's centre.\n",
                        "            context.clip(to: CGRect(\n"
                        "                x: bounds.left, y: 0, width: max(bounds.right - "
                        "bounds.left, 0),\n                height: height))\n"
                        "            // (a) the pop, about the pill's centre.\n"),
    "flat-vertical": ("LayerRenderersWords.swift",
                      "        let height = max(\n"
                      "            CGFloat(wordHeadroomVerticalFloorEm) * size,\n"
                      "            peak * pad + (peak - 1) * (metrics.ascent + metrics.descent) "
                      "/ 2 - outline\n                + wordHeadroomVerticalEdgePx)\n",
                      "        let height = CGFloat(wordHeadroomVerticalFloorEm) * size\n"),
}


def mutant(name):
    file, before, after = MUTANTS[name]
    began = time.time()
    with tempfile.TemporaryDirectory(prefix=f"reelcut-words-picture-{name}-") as temp:
        sources = Path(temp) / "Sources"
        shutil.copytree(ROOT / "app/Sources", sources)
        replace_once(sources / file, before, after)
        print(f"MUTANT {name}: {file}, anchor replaced once, in {sources}")
        try:
            run(sources, Path(temp) / "out")
        except subprocess.TimeoutExpired:
            print(f"MUTANT FAILURE: {name} did not finish within {DEADLINE} s")
            return 2
    elapsed = time.time() - began
    built = bool(rows) and rows[0]
    caught = built and not all(rows[1:])
    if caught and elapsed <= DEADLINE:
        print(f"MUTANT PASS: {name} — {rows.count(False)} row(s) FAILED in the copy, "
              f"{elapsed:.0f} s")
        return 0
    print(f"MUTANT FAILURE: {name} — built {built}, caught {caught}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant" and sys.argv[2] in MUTANTS:
        return mutant(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("W3 — word captions, the picture's arithmetic (probe)")
    try:
        run(ROOT / "app/Sources", WORK)
    except subprocess.TimeoutExpired:
        check(f"the probe finishes within {DEADLINE} s", False)
    print(f"{rows.count(True)}/{len(rows)}")
    return 0 if rows and all(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
