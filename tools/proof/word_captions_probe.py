#!/usr/bin/env python3
"""Word captions, the pager's arithmetic: road map 8's W4a (§10.9).

Builds `word_captions_probe.swift` (with `word_captions_support.swift`
beside it) over `app/Sources` with
`tools/proof/swift_build.py`'s line (a probe that will not build is a
scored FAILURE, never an exit), runs it over a FIXED word list, and prints the
rows it answered:

P0  every page: one timing per token, starts non-decreasing, end ≥ start,
    inside the span;
P1  every multi-word page measures within 0.86 of the canvas width;
P2  every page closed only by width would pass the budget with its next word
    (or is one balance move from such a page); a page ending `,;:` is exempt
    only where the clause rule's own conditions hold (at least `clauseMinimum`
    of the budget, the width break within `clauseWindow` words), and at least
    one such page exists;
P3  no lone word unless its break was forced, no balance move improves it, or
    it is ≥ half the budget;
P4  a lone over-wide word shrinks to the floor before it wraps;
P5  no two-line page but Karaoke or a wrapped lone word;
P6  abutment where the gap is under breakGap (standard rules and hold 0.1 s);
P7  1080×1920 and 1920×1080 page differently;
P8  the first page starts at raw start + lead, per engine;
P9  cues(.subtitles) == CaptionCues.build;
P10 the pause measurement: SpeechEngine over the `say` pangram
    (`speech_engine_proof.make_fixtures()`), paged by gap + punctuation, and
    again with road map 4's two detector pauses as forced breaks — the row
    asserts the first breaks at both pauses; whether the second changes any
    page is PRINTED (a host without en-US installed is a named SKIP);
P11 two abutting spans, per engine and word style;
P12 a ≥ 0.25 s unpunctuated gap closes a page: no page of any style holds both
    words of the first such pair in the list.

The fixed list is `tools/proof/work/words_spike/fixtures/fixtures.json`'s
`talk_text`, one token every 0.3 s from 1.0 s, each spoken for 0.18 s (a
0.12 s gap, under `breakGap`), with one 40-letter compound after the first
sentence, and every token from the sixth unpunctuated mid-sentence one
("editing | video") on shifted 0.3 s later, so that one gap is 0.42 s.
Every word style × both canvases.

    python3 tools/proof/word_captions_probe.py
    python3 tools/proof/word_captions_probe.py --mutant NAME

A mutant is built from a COPY of `app/Sources` with each anchor asserted to
occur exactly once; exit 0 means its NAMED row FAILED in the copy, which is
the pass. A mutant copy that does not build is a FAILURE.
"""

import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import swift_build

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof"))
WORK = ROOT / "tools/proof/work/word-captions-probe"
FONTS = ROOT / "app/Resources/Fonts"
FIXTURES = ROOT / "tools/proof/work/words_spike/fixtures/fixtures.json"
COMPOUND = "Donaudampfschifffahrtsgesellschaftskapitaen"[:40]
DEADLINE = 900
SEC = 600_000
GAP_SHIFT = 180_000

rows = []


def check(name, good, detail=""):
    rows.append((name, bool(good)))
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""))


def fixed_words():
    talk = json.loads(FIXTURES.read_text())["talk_text"]
    tokens = talk.split()
    first_stop = next(i for i, t in enumerate(tokens) if t.endswith((".", "?", "!")))
    tokens.insert(first_stop + 1, COMPOUND)
    words = [{"text": t, "start": SEC + i * 180_000, "end": SEC + i * 180_000 + 108_000}
             for i, t in enumerate(tokens)]
    # The one gap over `breakGap` (W4a's review, nit 2): the SIXTH token that
    # ends in no mark and follows one that ends in none either, and every
    # token after it, 0.3 s later — a 0.42 s gap, mid-sentence.
    marks = ".?!…,;:"
    unmarked = [i for i in range(1, len(tokens))
                if tokens[i][-1] not in marks and tokens[i - 1][-1] not in marks]
    for word in words[unmarked[5]:]:
        word["start"] += GAP_SHIFT
        word["end"] += GAP_SHIFT
    return words


def build(sources, out):
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/word_captions_probe.swift", entry)
    support = out / "word_captions_support.swift"
    shutil.copyfile(ROOT / "tools/proof/word_captions_support.swift", support)
    binary = out / "word-captions-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    try:
        swift_build.build(sources=[*swift, support, entry], output=binary, timeout=DEADLINE)
    except swift_build.SwiftBuildFailed as error:
        return None, "; ".join(error.diagnostics[:8])
    return binary, ""


def run(sources, out, pangram):
    began = time.time()
    binary, problem = build(sources, out)
    check("the probe builds over app/Sources", binary is not None, problem)
    if binary is None:
        return None
    words = out / "words.json"
    words.write_text(json.dumps(fixed_words()))
    result = subprocess.run([str(binary), str(FONTS), str(words), str(pangram)],
                            capture_output=True, text=True,
                            timeout=max(DEADLINE - (time.time() - began), 60),
                            start_new_session=True)
    try:
        answer = json.loads(result.stdout)
    except json.JSONDecodeError:
        check("the probe answers one JSON object", False,
              (result.stdout[-400:] + result.stderr[-400:]).strip())
        return None
    check("the probe answers one JSON object", answer.get("ok") is True
          and answer.get("registered", 0) >= 4,
          f"registered {answer.get('registered')}, {answer.get('fixed_words')} fixed words")
    (out / "answer.json").write_text(json.dumps(answer, indent=1, sort_keys=True))
    for row in answer["rows"]:
        check(row["name"], row["ok"], row["detail"])
    p10 = answer["p10"]
    if not p10.get("ran"):
        print(f"  SKIP P10 — {p10.get('skip')}")
    else:
        print(f"  P10 measured: {p10['words']} words, largest word gap {p10['largest_gap_s']:.3f} s, "
              f"gaps at the two pauses {p10['gaps_s']} s at {p10['at']}")
        print(f"      gap + punctuation pages: {p10['plain']}")
        print(f"      with the detector's pauses: {p10['detector']}")
        print(f"      the detector's breaks change the pages: {p10['detector_changes_pages']}")
    return answer


def replace_once(path, before, after):
    text = path.read_text(encoding="utf-8")
    count = text.count(before)
    if count != 1:
        raise RuntimeError(f"mutation anchor {path.name}: expected once, found {count}: "
                           f"{before!r}")
    path.write_text(text.replace(before, after), encoding="utf-8")


# name: ([(file, before, after)], the row prefix that must FAIL)
MUTANTS = {
    "width-count": ([("CaptionPages.swift",
                      '        content.split(separator: "\\n").allSatisfy '
                      '{ width(String($0), style, size) <= budget }\n',
                      "        content.split(whereSeparator: \\.isWhitespace).count <= 3\n")],
                    "P2"),
    "drop-balance": ([("CaptionPages.swift", "            pager.balance(&pages)\n", "")], "P3"),
    "drop-no-blink": ([("CaptionPages.swift",
                        "                end = next - last.end < rules.breakGap ? next "
                        ": min(next, last.end + rules.hold)\n",
                        "                end = min(next, last.end + rules.hold)\n")], "P6"),
    "drop-lead": ([("CaptionPages.swift",
                    "        case .apple: return 162_000\n"
                    "        case .assemblyai: return -36_000\n",
                    "        case .apple: return 0\n        case .assemblyai: return 0\n")], "P8"),
    "drop-span": ([("CaptionPages.swift",
                    "            let start = min(max(word.start + lead, lower), lastFrame)\n",
                    "            let start = word.start + lead\n"),
                   ("CaptionPages.swift",
                    "            let end = min(max(word.end + lead, start), upper)\n",
                    "            let end = max(word.end + lead, start)\n"),
                   ("CaptionPages.swift",
                    "                end = min(last.end + rules.hold, span.upperBound)\n",
                    "                end = last.end + rules.hold\n")], "P11"),
    "drop-gap": ([("CaptionPages.swift",
                   "            if word.speaker != previous.speaker || word.start - previous.end "
                   ">= rules.breakGap\n",
                   "            if word.speaker != previous.speaker\n")], "P12"),
    "drop-clause": ([("CaptionPages.swift",
                      "            let lowest = max(0, page.count - 1 - rules.clauseWindow)\n",
                      "            let lowest = page.count\n")], "P2"),
    # The clause preference's two limits loosened at once: any mark, any head.
    "loosen-clause": ([("CaptionPages.swift",
                        "                guard measure(head) >= rules.clauseMinimum * budget,\n",
                        "                guard measure(head) >= 0,\n"),
                       ("CaptionPages.swift",
                        "            let lowest = max(0, page.count - 1 - rules.clauseWindow)\n",
                        "            let lowest = 0\n")], "P2"),
}


def pangram_fixture():
    from speech_engine_proof import make_fixtures
    return make_fixtures()[0]


def mutant(name):
    edits, row = MUTANTS[name]
    began = time.time()
    with tempfile.TemporaryDirectory(prefix=f"reelcut-word-captions-{name}-") as temp:
        sources = Path(temp) / "Sources"
        shutil.copytree(ROOT / "app/Sources", sources)
        for file, before, after in edits:
            replace_once(sources / file, before, after)
        print(f"MUTANT {name}: {len(edits)} anchor(s) replaced once, in {sources}")
        try:
            run(sources, Path(temp) / "out", pangram_fixture())
        except subprocess.TimeoutExpired:
            print(f"MUTANT FAILURE: {name} did not finish within {DEADLINE} s")
            return 2
    elapsed = time.time() - began
    built = bool(rows) and rows[0][1]
    failed = [n for n, ok in rows if not ok]
    caught = built and any(n.startswith(row + " ") for n in failed)
    if caught:
        print(f"MUTANT PASS: {name} — {len(failed)} row(s) FAILED in the copy, the named "
              f"{row} among them: {[n.split(' ')[0] for n in failed]}, {elapsed:.0f} s")
        return 0
    print(f"MUTANT FAILURE: {name} — built {built}, {row} failed: {caught}, failed "
          f"{[n.split(' ')[0] for n in failed]}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant" and sys.argv[2] in MUTANTS:
        return mutant(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("W4a — word captions, the pager's arithmetic (probe)")
    began = time.time()
    try:
        run(ROOT / "app/Sources", WORK, pangram_fixture())
    except subprocess.TimeoutExpired:
        check(f"the probe finishes within {DEADLINE} s", False)
    good = sum(1 for _, ok in rows if ok)
    print(f"{good}/{len(rows)} ({time.time() - began:.0f} s)")
    return 0 if rows and all(ok for _, ok in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
