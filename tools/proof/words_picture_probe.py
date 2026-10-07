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
P2  no ink outside that box at any of them, the pill's rows and columns in —
    and, since issue batch B86, with every config also drawn half FILLED and
    every pill config also GLIDING at `glide` 0 and 0.5 (word ≥ 2);
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
    0.95 × 1.5 × its width at pop 0 (the clip scaled with the token);
P10 (issue batch B86, spec §11 W-14) what the three looks COST: the median of
    20 `text(_:hash:reveal:)` calls on a cache miss — a raster and an upload,
    after one untimed warm-up — of the P1 text as the HIGHLIGHT preset's own
    page (Montserrat-Black at 0.075 × min(w, h), upper case, outlined), at
    1080×1920 and 3840×2160, for four reveals at word 3: `pop` 0.5 (the
    shipped comparator, never scored), `fill` 0.5, `fill` 0.5 with `dim` 0.5
    at `pause_dim` 0.5, and `glide` 0.5 (with the default pill) — and, since
    the dim's layer costs by the box and One Word's type is the largest a
    preset ships (0.12 × min(w, h)), the fill with the dim on the page ONE
    WORD generates, one word (`oneword-page fill+dim`, scored), and (issue
    batch B86 phase 2, where the sheet's Dim first reaches every word style)
    on the page KARAOKE's pager makes of a run of words with no pause — the
    one preset page of TWO lines, at its own wrap width, its last word half
    filled (`karaoke-2line fill+dim`, scored; the row also requires that the
    page really was laid on two lines). **P10 scores three pages in the
    presets' own styles**: Highlight's line, One Word's one-word page and
    Karaoke's two-line page. Beside them it prints, never scored (as `pop` is), a
    HAND-MADE page of large type: the same six words on one line at One
    Word's size (`oneword-line fill+dim (hand-made)`), which no preset makes
    and `set_text` can write. On a dim's ramp frames that page read 9.529 ms
    at 3840×2160 against the 8 ms budget (2026-10-05, High Power, on
    battery, thermal state nominal) — a known limit, in
    `designs/adr/roadmap-08-word-captions.md`, not a scored row; the dim
    costs this because it is one transparency layer over the whole box (spec
    §11 W-14). Every page but Karaoke's is one line (`width` nil). The probe measures it
    FIRST, before the P1/P2 sweep. It FAILS when a scored median is over
    4 ms at 1080×1920 — half of spec §7.5's 8 ms frame, because a fill pays
    it on every frame of a word — or over 8 ms at 3840×2160. The fourteen
    medians are printed either way. A median over budget is reported; the
    budget is not raised.
    **P10 is JUDGED only on an unthrottled host.** The probe reads
    `ProcessInfo`'s Low Power Mode flag and thermal state before the first
    raster and after the last; when Low Power Mode is on, or the thermal
    state is above nominal, at either reading — or the probe did not say —
    the row is `P10 not judged: <why>`, a CONTROL FAILURE with the medians
    and the power state printed: never a pass, never a skip. Re-run it with
    Low Power Mode off and the Mac cool.
P11–P16 (issue batch B86, spec §11 W-14) the looks' geometry, each value the
    recipe would carry set exactly and the picture read off `textBitmap`:
P11 between two LINES the gliding plate's four edges are at
    `from + easeOut(½) × (to − from)` ± 2 px at `word_glide` ½ — x, y and
    width all travel — and on `from`'s at 0;
P12 the plate pops about its OWN centre: at `word_pop` 1 and `active_scale`
    1.5 its centre is where it is unpopped and its width and height 1.5×;
P13 a token that WRAPS over two lines takes the settled pill: the plate does
    not slide onto it or off it (`word_glide` ½ is `word_glide` 1, byte for
    byte), where between two one-piece tokens the same two instants differ;
P14 a wrapped token fills each of its two pieces by the same fraction;
P15 a FULL word is drawn whole: on an outlined build page `word_fill` 1 is
    the unfilled page byte for byte, though the stroke reaches past the edge
    `word_fill` 0.999 is cut at;
P16 a look's value outside 0…1 draws as the nearest value inside it
    (`word_fill`, `word_glide`, `word_dim` and `pause_dim`, each side), the
    two ends of each range being two pictures; and a full dim at `pause_dim`
    1 draws nothing;
P17 (issue batch B86 phase 2) the plate's HEIGHT travels too: between two
    lines of DIFFERENT metrics — the second holds glyphs Montserrat does not
    have, so a fallback face's ascent and descent make that line — the two
    settled pills differ in height by more than 8 px (else the row is a
    CONTROL FAILURE: this host's fallback face gave the line the same
    metrics) and half-way through the travel (`word_glide` 0.2063, which
    eases to ½) all four edges are at `from + ½ × (to − from)` ± 2 px.

    python3 tools/proof/words_picture_probe.py [--raster-budget-ms N] [--only ROWS]
    python3 tools/proof/words_picture_probe.py --mutant NAME
    python3 tools/proof/words_picture_probe.py --power-selftest

`--power-selftest` builds and times nothing: it feeds P10's scorer made-up
answers — Low Power Mode on, a thermal state above nominal before or after
the rasters, no power state at all, and an unthrottled host under and over
budget — and scores that each is the row it should be (T1–T8).

`--only ROWS` (comma-separated, of P10–P17: the rows measured before the
sweep) runs the probe with `--quick`, which stops before the sweep, and
scores those rows alone — `--only P10` is P10 by itself, a build and about
half a minute. `--raster-budget-ms N` replaces both of P10's budgets with
N; a run at 0 is its made-to-fail control (P10 alone must fail, on an
unthrottled host for the budget's own reason — a throttled one answers
`P10 not judged` whatever the budget). A `--mutant` run does not score P10.

A mutant is built from a COPY of `app/Sources` with one anchor (three, for
`looks-unclamped`), each asserted to occur exactly once, replaced; exit 0
means at least one row FAILED in the copy, which is the pass, and 1 that
every row held (it survived). A mutant of the looks' geometry names its row
and runs `--only` that row. Exit 2
(rule R, issue batch B13) means the control could not be performed — the
copy could not be made, the anchor was not found exactly once, the copy did
not build, the probe did not answer one JSON object, or the run passed its
deadline — printed as `mutant <name>: the control could not be performed —
<why>`.
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
# P10's budgets in milliseconds, by canvas; `--raster-budget-ms` replaces both.
RASTER_BUDGET = {"1080x1920": 4.0, "3840x2160": 8.0}
# A mutant run does not score P10: a timing is no picture, and a median over
# budget must not be what "catches" a mutant of the drawing.
SCORE_RASTER = True
# The rows the probe measures before the sweep, which `--only` can run alone.
QUICK = ("P10", "P11", "P12", "P13", "P14", "P15", "P16", "P17")
# None for every row, else the rows `--only` named.
ONLY = None
THERMAL_NOMINAL = 0

rows = []
control_failures = []


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


def wanted(name):
    return ONLY is None or name in ONLY


def throttled(answer):
    """Why P10's medians cannot be judged on this host, and the power state
    as the probe read it; the reason is "" on an unthrottled host."""
    power = answer.get("power")
    readings = [power.get(key) for key in ("before", "after")] if isinstance(power, dict) else []
    if len(readings) != 2 or not all(
            isinstance(r, dict) and isinstance(r.get("low_power"), bool)
            and isinstance(r.get("thermal_state"), int) for r in readings):
        return "the probe did not report the host's power state", f"power: {power!r}"
    state = "; ".join(
        f"{key}: Low Power Mode {'on' if r['low_power'] else 'off'}, thermal state "
        f"{r.get('thermal', r['thermal_state'])}"
        for key, r in zip(("before the rasters", "after"), readings))
    why = []
    if any(r["low_power"] for r in readings):
        why.append("Low Power Mode")
    hot = max(readings, key=lambda r: r["thermal_state"])
    if hot["thermal_state"] > THERMAL_NOMINAL:
        why.append(f"thermal state {hot.get('thermal', hot['thermal_state'])}")
    return " and ".join(why), state


def judge_raster(answer):
    """P10 as `(row, good, detail)`: the medians against the budgets — judged
    only when the host was not throttled while they were taken."""
    p10 = answer.get("p10") or []
    medians = "; ".join(
        f"{m['canvas']} {m['case']} {m['median_ms']:.3f} ms"
        + (f" [{m.get('lines')} lines, {m.get('tokens')} words, box {m.get('box')}]"
           if m["case"].startswith("karaoke-2line") else "")
        + ("" if m.get("scored") else " (not scored)") for m in p10)
    budgets = ", ".join(f"{canvas} {limit:g} ms" for canvas, limit in RASTER_BUDGET.items())
    why, power = throttled(answer)
    if why:
        return (f"P10 not judged: {why} — a CONTROL FAILURE, never a pass or a skip: the "
                f"medians below were taken on a throttled host and are held to no budget "
                f"({budgets}); re-run with Low Power Mode off and the Mac cool",
                False, f"medians: {medians}; power: {power}")
    over = [(m["canvas"], m["case"], round(m["median_ms"], 3)) for m in p10
            if m.get("scored") and not m["median_ms"] <= RASTER_BUDGET[m["canvas"]]]
    scored = [m for m in p10 if m.get("scored")]
    # The Karaoke case is only what it says when the pager's page took two lines.
    two_lines = [m.get("lines") for m in p10 if m["case"].startswith("karaoke-2line")]
    return (f"P10 a fill, a fill with a dim, a glide, One Word's one-word page and Karaoke's "
            f"two-line page with a fill and a dim each rasterize and upload within budget "
            f"({budgets}; median of 20 on a cache miss)",
            len(p10) == 14 and len(scored) == 10 and all(m["drew"] for m in p10)
            and two_lines == [2, 2] and not over,
            f"medians: {medians}; Karaoke's page lines per canvas: {two_lines}; over budget: "
            f"{over}; power: {power}")


def score_raster(answer):
    check(*judge_raster(answer))


def power_selftest():
    """`--power-selftest`: P10's scorer fed made-up answers — no probe is
    built and nothing is timed. The fourteen medians are 1 ms each."""
    def answer(low=False, thermal=0, after=None, power=True):
        names = ["nominal", "fair", "serious", "critical"]
        def reading(state):
            return {"low_power": low, "thermal_state": state, "thermal": names[state]}
        cases = [("pop", False), ("fill", True), ("fill+dim", True), ("glide", True),
                 ("oneword-page fill+dim", True),
                 ("oneword-line fill+dim (hand-made)", False),
                 ("karaoke-2line fill+dim", True)]
        made = {"p10": [{"canvas": canvas, "case": case, "scored": scored, "drew": True,
                         "median_ms": 1.0, "lines": 2 if case.startswith("karaoke") else 1}
                        for canvas in RASTER_BUDGET for case, scored in cases]}
        if power:
            made["power"] = {"before": reading(thermal),
                             "after": reading(thermal if after is None else after)}
        return made

    print("P10's scorer on made-up answers (nothing is built or timed)")
    saved = dict(RASTER_BUDGET)
    name, good, _ = judge_raster(answer(low=True))
    check("T1 Low Power Mode on: the row is `P10 not judged: Low Power Mode …` and it fails",
          name.startswith("P10 not judged: Low Power Mode —") and good is False, name)
    name, good, _ = judge_raster(answer(thermal=1))
    check("T2 thermal state fair: `P10 not judged: thermal state fair …`, failed",
          name.startswith("P10 not judged: thermal state fair —") and good is False, name)
    name, good, _ = judge_raster(answer(after=2))
    check("T3 nominal before the rasters and serious after: not judged, failed",
          name.startswith("P10 not judged: thermal state serious —") and good is False, name)
    name, good, _ = judge_raster(answer(low=True, thermal=3))
    check("T4 both: the row names both, failed",
          name.startswith("P10 not judged: Low Power Mode and thermal state critical —")
          and good is False, name)
    name, good, _ = judge_raster(answer(power=False))
    check("T5 a probe that reports no power state: not judged, failed",
          name.startswith("P10 not judged: the probe did not report") and good is False, name)
    name, good, _ = judge_raster(answer())
    check("T6 unthrottled, every median under budget: judged, and it passes",
          name.startswith("P10 a fill") and good is True, name)
    for canvas in RASTER_BUDGET:
        RASTER_BUDGET[canvas] = 0.0
    name, good, detail = judge_raster(answer())
    check("T7 unthrottled at budget 0: judged, and it fails on the ten scored medians",
          name.startswith("P10 a fill") and good is False and detail.count("1.0)") == 10,
          detail[detail.find("over budget"):detail.find("; power")])
    name, good, _ = judge_raster(answer(low=True))
    check("T8 throttled at budget 0: still `not judged` — the budget is not what fails it",
          name.startswith("P10 not judged: Low Power Mode —") and good is False, name)
    RASTER_BUDGET.update(saved)
    print(f"{rows.count(True)}/{len(rows)}")
    return 0 if all(rows) else 1


def rect(value):
    return value if isinstance(value, list) and len(value) == 4 else None


def score_looks(answer):
    """P11–P16: the looks' geometry."""
    ease = 1 - (1 - 0.5) ** 3
    if wanted("P11"):
        p11 = answer.get("p11") or {}
        a, b, start, half = (rect(p11.get(key)) for key in ("from", "to", "start", "half"))
        good = None not in (a, b, start, half) and p11.get("lines") == 2
        expect = [a[i] + ease * (b[i] - a[i]) for i in range(4)] if good else None
        # Not vacuous: the two pills differ in x, in y and in width.
        apart = good and abs(b[0] - a[0]) > 10 and abs(b[1] - a[1]) > 10 \
            and abs((b[2] - b[0]) - (a[2] - a[0])) > 10
        check("P11 between two lines the gliding plate's four edges are at from + easeOut(½) × "
              "(to − from) ± 2 px at word_glide ½, and on from's at 0",
              good and apart and all(abs(half[i] - expect[i]) <= 2 for i in range(4))
              and all(abs(start[i] - a[i]) <= 1 for i in range(4)),
              f"[minX, minY, maxX, maxY] from {a}, to {b}, at 0 {start}, at ½ {half}, "
              f"expected {expect}; lines {p11.get('lines')}")
    if wanted("P12"):
        p12 = answer.get("p12") or {}
        flat, popped = rect(p12.get("flat")), rect(p12.get("popped"))
        scale = p12.get("scale")
        good = None not in (flat, popped) and scale == 1.5
        if good:
            centre = [abs((popped[i] + popped[i + 2]) - (flat[i] + flat[i + 2])) / 2
                      for i in (0, 1)]
            grown = [(popped[i + 2] - popped[i]) / (flat[i + 2] - flat[i]) for i in (0, 1)]
            sizes = [abs((popped[i + 2] - popped[i]) - scale * (flat[i + 2] - flat[i]))
                     for i in (0, 1)]
        check("P12 the gliding plate pops about its own centre: at word_pop 1 its centre is "
              "the unpopped plate's ± 1.5 px and its width and height are active_scale (1.5) "
              "times it ± 3 px",
              good and max(centre) <= 1.5 and max(sizes) <= 3,
              f"unpopped {flat}, popped {popped}"
              + (f"; centre moved {centre}, grew ×{grown[0]:.3f} by ×{grown[1]:.3f}"
                 if good else ""))
    if wanted("P13"):
        p13 = answer.get("p13") or {}
        plate = rect(p13.get("plate_on_wrapped"))
        tall = plate is not None and (plate[3] - plate[1]) > 1.5 * (p13.get("line_height") or 1e9)
        check("P13 a token that wraps over two lines takes the settled pill: word_glide ½ is "
              "word_glide 1 byte for byte, sliding onto it and off it, with the plate on both "
              "its lines; between two one-piece tokens the same two instants differ",
              p13.get("token_lines") == 2 and p13.get("onto_wrapped_same") is True
              and p13.get("off_wrapped_same") is True and tall
              and p13.get("one_piece_same") is False, f"{p13}")
    if wanted("P14"):
        p14 = answer.get("p14") or {}
        pieces = p14.get("pieces") or []
        lines, good = [], p14.get("token_lines") == 2 and len(pieces) == 2
        for piece in pieces:
            full, red, blue = (rect(piece.get(key)) for key in
                               ("full_red", "half_red", "half_blue"))
            if None in (full, red, blue):
                good = False
                lines.append(f"line {piece.get('line')}: {piece}")
                continue
            expect = full[0] + 0.5 * (full[2] - full[0])
            # The red run ends within 6 px of half the piece, and blue takes over there.
            fine = abs(red[2] - expect) <= 6 and -1 <= blue[0] - red[2] <= 12
            good = good and fine
            lines.append(f"line {piece['line']}: the piece {full[0]:g}…{full[2]:g}, red to "
                         f"{red[2]:g} (half is {expect:g}), blue from {blue[0]:g}")
        check("P14 a token on two lines fills each piece by the same fraction: at word_fill ½ "
              "each line's active ink ends within 6 px of half that piece, and the upcoming "
              "ink starts there", good, "; ".join(lines) or f"{p14}")
    if wanted("P15"):
        p15 = answer.get("p15") or {}
        full, nearly = rect(p15.get("ink_full")), rect(p15.get("ink_nearly"))
        past = full[2] - nearly[2] if None not in (full, nearly) else None
        check("P15 a full word is drawn whole: on an outlined build page word_fill 1 is the "
              "unfilled page byte for byte (½ is not), and its stroke reaches at least 2 px "
              "past where word_fill 0.999 is cut",
              p15.get("full_same_as_unfilled") is True
              and p15.get("half_same_as_unfilled") is False and past is not None and past >= 2,
              f"{p15}; the stroke's reach past the edge {past}")
    if wanted("P16"):
        p16 = answer.get("p16") or {}
        same, control = p16.get("same") or {}, p16.get("control_same") or {}
        moved = sorted(key for key, value in same.items() if value is not True)
        flat = sorted(key for key, value in control.items() if value is not False)
        check("P16 a look's value outside 0…1 draws as the nearest one inside (word_fill, "
              "word_glide, word_dim and pause_dim, each side), the ends of each range are two "
              "pictures, and a full dim at pause_dim 1 draws nothing",
              len(same) == 8 and not moved and len(control) == 4 and not flat
              and rect(p16.get("lit_ink")) is not None and p16.get("invisible_ink") is None,
              f"not drawn as the clamped value: {moved}; ends that drew alike: {flat}; ink at "
              f"pause_dim 1 × word_dim 1: {p16.get('invisible_ink')!r}; compared: "
              f"{sorted(same)}")
    if wanted("P17"):
        p17 = answer.get("p17") or {}
        a, b, half = (rect(p17.get(key)) for key in ("from", "to", "half"))
        glide = p17.get("glide")
        good = None not in (a, b, half) and isinstance(glide, float)
        travel = 1 - (1 - glide) ** 3 if good else None
        tall = [(r[3] - r[1]) for r in (a, b, half)] if good else []
        if good and abs(tall[1] - tall[0]) <= 8:
            control_failures.append("P17")
            check("P17 CONTROL FAILURE: the two lines' pills are the same height on this host "
                  "(the fallback face gave the second line the first one's metrics), so the "
                  "row cannot see the height travel", False,
                  f"heights {tall}; lines' ascent + descent {p17.get('lines')}")
        else:
            expect = [a[i] + travel * (b[i] - a[i]) for i in range(4)] if good else None
            check("P17 between two lines of different metrics the gliding plate's four edges "
                  "are half-way between the two pills' ± 2 px half-way through the travel: its "
                  "HEIGHT travels with it",
                  good and abs(travel - 0.5) < 0.01
                  and all(abs(half[i] - expect[i]) <= 2 for i in range(4)),
                  f"[minX, minY, maxX, maxY] from {a}, to {b}, half-way {half}, expected "
                  f"{expect}; heights {tall}; lines' ascent + descent {p17.get('lines')}; "
                  f"travel {travel}")


def score(answer):
    if ONLY is None:
        score_sweep(answer)
    if SCORE_RASTER and wanted("P10"):
        score_raster(answer)
    score_looks(answer)


def score_sweep(answer):
    """P1–P9: road map 8's rows, the sweep among them."""
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
    quick = ["--quick"] if ONLY is not None else []
    result = subprocess.run([str(binary), str(FONTS), *quick], capture_output=True, text=True,
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
    # The looks' geometry (issue batch B86): each names the row it must fail,
    # and runs `--only` that row.
    "plate-y-jumps": ("LayerRenderersWords.swift",
                      "                    y: a.minY + (b.minY - a.minY) * travel,\n",
                      "                    y: b.minY,\n", "P11"),
    "plate-width-jumps": ("LayerRenderersWords.swift",
                          "                    width: a.width + (b.width - a.width) * travel,\n",
                          "                    width: b.width,\n", "P11"),
    "plate-height-jumps": ("LayerRenderersWords.swift",
                           "                    height: a.height + (b.height - a.height) * travel)\n",
                           "                    height: b.height)\n", "P17"),
    "plate-pop-ignored": ("LayerRenderersWords.swift",
                          "            fillPlate(plate, in: rect, size: size, scale: scale, "
                          "in: context)\n",
                          "            fillPlate(plate, in: rect, size: size, scale: 1, "
                          "in: context)\n", "P12"),
    "one-piece-ignored": ("LayerRenderersWords.swift",
                          "        if travel < 1, to.count == 1, from.count == 1 {\n",
                          "        if travel < 1, !to.isEmpty, !from.isEmpty {\n", "P13"),
    "fill-first-piece-only": ("LayerRenderersWords.swift",
                              "        for piece in activePieces {\n",
                              "        for piece in activePieces.prefix(1) {\n", "P14"),
    "full-word-at-glyph-edge": ("LayerRenderersWords.swift",
                                "                let edge = filled >= 1\n",
                                "                let edge = filled >= 2\n", "P15"),
    "looks-unclamped": ("LayerRenderersWords.swift", [
        ("        let filled: Double? = fill.map { min(max($0, 0), 1) }\n",
         "        let filled: Double? = fill\n"),
        ("        let travel = CGFloat(easeOut(min(max(glide ?? 1, 0), 1)))\n",
         "        let travel = CGFloat(easeOut(glide ?? 1))\n"),
        ("        let dimmed = min(max(dim ?? 0, 0), 1) * min(max(style.pauseDim, 0), 1)\n",
         "        let dimmed = (dim ?? 0) * style.pauseDim\n"),
    ], None, "P16"),
}


def mutant(name):
    global SCORE_RASTER, ONLY
    SCORE_RASTER = False
    file, before, after, *row = MUTANTS[name]
    edits = before if isinstance(before, list) else [(before, after)]
    if row:
        ONLY = [row[0]]
    began = time.time()
    with tempfile.TemporaryDirectory(prefix=f"reelcut-words-picture-{name}-") as temp:
        sources = Path(temp) / "Sources"
        try:
            shutil.copytree(ROOT / "app/Sources", sources)
            for one, other in edits:
                replace_once(sources / file, one, other)
        except (OSError, RuntimeError) as error:
            print(f"mutant {name}: the control could not be performed — {error}")
            return 2
        print(f"MUTANT {name}: {file}, {len(edits)} anchor(s) each replaced once, in {sources}"
              + (f"; --only {row[0]}" if row else ""))
        try:
            run(sources, Path(temp) / "out")
        except subprocess.TimeoutExpired:
            print(f"MUTANT FAILURE: {name} did not finish within {DEADLINE} s")
            print(f"mutant {name}: the control could not be performed — the run passed "
                  f"{DEADLINE} s")
            return 2
    elapsed = time.time() - began
    if not (len(rows) >= 2 and rows[0] and rows[1]):
        why = ("the probe did not build" if not (rows and rows[0])
               else "the probe did not answer one JSON object")
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    if elapsed > DEADLINE:
        print(f"mutant {name}: the control could not be performed — the run passed "
              f"{DEADLINE} s ({elapsed:.0f} s)")
        return 2
    if control_failures:
        print(f"mutant {name}: the control could not be performed — "
              f"{', '.join(control_failures)} failed as a control on this host")
        return 2
    caught = not all(rows[2:])
    if caught:
        print(f"MUTANT PASS: {name} — {rows.count(False)} row(s) FAILED in the copy, "
              f"{elapsed:.0f} s")
        return 0
    print(f"MUTANT FAILURE: {name} — caught {caught}, {elapsed:.0f} s")
    return 1


def main():
    global ONLY
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant" and sys.argv[2] in MUTANTS:
        return mutant(sys.argv[2])
    if sys.argv[1:] == ["--power-selftest"]:
        return power_selftest()
    arguments = sys.argv[1:]
    if len(arguments) % 2:
        sys.exit(__doc__)
    for flag, value in zip(arguments[::2], arguments[1::2]):
        if flag == "--raster-budget-ms":
            try:
                budget = float(value)
            except ValueError:
                sys.exit(__doc__)
            for canvas in RASTER_BUDGET:
                RASTER_BUDGET[canvas] = budget
        elif flag == "--only":
            ONLY = [name.strip() for name in value.split(",") if name.strip()]
            if not ONLY or any(name not in QUICK for name in ONLY):
                sys.exit(f"--only takes rows of {', '.join(QUICK)} (the rows measured before "
                         f"the sweep), not {value!r}")
        else:
            sys.exit(__doc__)
    print("W3 — word captions, the picture's arithmetic (probe)"
          + (f" — only {', '.join(ONLY)}" if ONLY else ""))
    try:
        run(ROOT / "app/Sources", WORK)
    except subprocess.TimeoutExpired:
        check(f"the probe finishes within {DEADLINE} s", False)
    print(f"{rows.count(True)}/{len(rows)}")
    return 0 if rows and all(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
