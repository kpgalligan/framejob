#!/usr/bin/env python3
"""Road map "mattes", phase MT4 (#240; spec §11 MT-7) — the matte track's
chrome, measured in the app's own code.

    python3 tools/proof/matte_chrome_probe.py
    python3 tools/proof/matte_chrome_probe.py --mutant NAME

No MCP call reaches a menu's check state, a context menu, the header's tag,
the lane's paint, the Clip tab's note or the canvas's hit, so this is
`CLAUDE.md`'s instrument for app STRUCTURE with no caller a script can reach:
`matte_chrome_probe.swift` built as `main.swift` over every other file in
`app/Sources` through `swift_build.build` (reused when every input is
byte-identical), in `tools/proof/work/matte_chrome_probe/`. **A build failure
is a scored FAILURE (B0), never an exit.** No app is launched; the probe puts
a real `EditorViewController` in an offscreen `NSWindow` (aqua) over a
six-track fixture — back to front B (ordinary), M (alpha, cuts B), O
(ordinary), M2 (alpha, cuts O), L (luma, a matte behind it: cuts nothing) and
F (ordinary, empty, the front-most) — and writes one JSON answer.

Rows:
  M1  Track ▸ Matte and the track context menu's Matte both come right after
      Solo and list Off, Alpha, Inverted Alpha, Luma, Inverted Luma, tagged
      0…4; every context row names the clicked track.
  M2  the check states: the validator checks the CURRENT track's mode (M:
      Alpha, L: Luma, F: Off) and enables the rows; the context menu checks
      the CLICKED track's (M, L, O).
  M3  the context menu's Luma on O (not the current track) makes O a luma
      matte and changes no other track, undo "Track Matte"; again is an
      identity (no change, no step: one undo restores the project); Track ▸
      Matte ▸ Inverted Alpha with a clip on B selected does the same for B.
  T1  `TimelineMatteTag.text`: "Matte · Alpha" / "· Inverted Alpha" / "·
      Luma" / "· Inverted Luma" undimmed over an ordinary track; "Matte ·
      nothing behind" DIMMED for a back-most matte and a matte in front of a
      matte; nil for an ordinary track; the matte behind still has its words.
  T2  the tag on a Small name line (MT-7 as amended in MT4's fix pass): for
      each of the five tag texts on the Small text and audio rows, at
      `TimelineLayout.headerWidth`, the name keeps >= 40 pt, the tag
      `drawMatteTag` draws reads "Matte" exactly for the three long texts
      ("· Inverted Alpha", "· Inverted Luma", "· nothing behind") and its
      own words for the two short ones, and `matteTagWidth` (the width the
      header clips the name by) is the drawn tag's width plus the gap.
  T3  the tag's contrast: `TimelineMatteTag.textColor` over its box
      (`fillColor`) over the header row's fill (`DS.chromeBackground`), each
      resolved under aqua and darkAqua, composited in sRGB: the dimmed tag's
      WCAG contrast ratio is >= 3.0 in both looks, over the host's accent
      AND over every sRGB cube corner standing in for the accent at the
      dimmed box's own alpha (MT5); the undimmed tag's (its
      words in the primary label colour over the accent-tinted box) is
      >= 4.5 in both looks, over the host's accent AND over every accent the
      box could take (its RGB swapped for each corner of the sRGB cube at the
      box's own alpha), so the score does not depend on the owner's accent.
      CONTROLS, both host-independent: the measure can fail (the header
      row's own colour as text over the dimmed box is < 1.5:1, each look),
      and the two looks resolved apart (the light row's luminance > 0.5, the
      dark row's < 0.1).
  LN  the timeline content view `cacheDisplay`ed as the window paints it: a
      pixel inside M's clip (a matte lane) is the lane's colour and the
      clip's own fill (read off B's identical clip) mixed at 0.5, ±3 a
      channel, in the capture's own encoding (where the composite happens;
      a mix of two colours converted to sRGB is not their sRGB mix); CONTROL: O's identical clip reads B's fill exactly (±1), and
      the lane and the fill differ by > 20 in some channel, so the mix is
      measurable.
  NT  `ClipPane.matteNote` for single (M), shared-mode (M + M2), mixed-mode
      (M + L), mixed with an ordinary clip (M + B), no-target (L), ordinary
      and empty selections, exactly MT-7's words or nil; and the note the
      inspector's pinned block SHOWS, on the first sub-tab and on Clip, for
      M, B and L.
  HT  a 1600×900 card under a 200×200 alpha window, both centred: the
      canvas's hit (`CanvasLayerBox.boxes(recipe:snapshot:)` and
      `PreviewCanvasView.hit(at:)`'s rule) answers the window at the centre
      and the card 500 px right of it; CONTROL: the window's recipe layer has non-null
      `matte.into` (it is a matte layer, not drawn).
Not scored: where the tag goes per lane height (printed).

`--mutant NAME` applies one anchored replacement (asserted to occur exactly
once) to a copy of `app/Sources` in `work/matte_chrome_probe/mutant/NAME/`,
builds the probe over that copy and runs every row: the named rows must FAIL.
Rule R: exit 0 = caught, 1 = survived, 2 = the control could not be
performed (B0 failed, or the probe did not answer).
"""

import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/matte_chrome_probe"
PROBE_SOURCE = ROOT / "tools/proof/matte_chrome_probe.swift"
SOURCES = ROOT / "app/Sources"
MODES = ["Off", "Alpha", "Inverted Alpha", "Luma", "Inverted Luma"]
CONTEXT_TITLES = ["Hide Video", "Mute Audio", "Lock Track", "Solo", "Matte", "-",
                  "Remove Track"]
NOTE = ("Matte for the track below (Alpha). Not drawn: its blend mode, drop shadow and "
        "reflection have no effect.")
NOTHING = "Nothing is behind this matte track, so it cuts nothing."

# name: (file under app/Sources, anchor, replacement, rows that must fail)
MUTANTS = {
    "menu-current-track": (
        "TimelineView+TrackMenu.swift",
        "        guard let track = menuTrack(sender), let tag = (sender as? NSMenuItem)?.tag,\n",
        "        guard let track = snapshot.tracks.last, let tag = (sender as? NSMenuItem)?.tag,\n",
        ["M3"]),
    "validator-always-off": (
        "EditorViewController+Identity.swift",
        "                    modes.indices.contains(menuItem.tag) && track?.matte == modes[menuItem.tag]\n"
        "                    ? .on : .off\n",
        "                    .off\n",
        ["M2"]),
    "tag-never-dim": (
        "TimelineView+Matte.swift",
        '            return ("Matte · nothing behind", true)\n',
        '            return ("Matte · nothing behind", false)\n',
        ["T1"]),
    "lane-full-opacity": (
        "TimelineView+Matte.swift",
        "    static let laneOpacity: CGFloat = 0.5\n",
        "    static let laneOpacity: CGFloat = 1\n",
        ["LN"]),
    "note-every-clip": (
        "ClipPane+Matte.swift",
        "            guard let track = tracks.first(where: { $0.id == clip.track }),\n"
        "                  track.matte != .none\n",
        "            guard let track = tracks.first(where: { $0.id == clip.track })\n",
        ["NT"]),
    "hit-skips-matte": (
        "CanvasSessions.swift",
        "        recipe.layers.compactMap { layer in\n",
        "        recipe.layers.filter { $0.matte?.into == nil }.compactMap { layer in\n",
        ["HT"]),
    "tag-never-short": (
        "TimelineView+Matte.swift",
        '        rowWidth - 14 - width(of: text) - gap < minimumNameWidth ? "Matte" : text\n',
        "        text\n",
        ["T2"]),
    "tag-dim-accent": (
        "TimelineView+Matte.swift",
        "    static func textColor(dimmed: Bool) -> NSColor { dimmed ? DS.textMuted : DS.textStrong }\n",
        "    static func textColor(dimmed: Bool) -> NSColor {\n"
        "        dimmed ? DS.accent.withAlphaComponent(0.45) : DS.textStrong\n"
        "    }\n",
        ["T3"]),
    "tag-accent-text": (
        "TimelineView+Matte.swift",
        "    static func textColor(dimmed: Bool) -> NSColor { dimmed ? DS.textMuted : DS.textStrong }\n",
        "    static func textColor(dimmed: Bool) -> NSColor { dimmed ? DS.textMuted : DS.accent }\n",
        ["T3"]),
    "undo-name": (
        "EditorViewController+Matte.swift",
        '            "Track Matte", .setTrack(track: track.id, matte: TrackMatte.allCases[tag]))\n',
        '            "Matte Track", .setTrack(track: track.id, matte: TrackMatte.allCases[tag]))\n',
        ["M3"]),
}

rows = {}


def check(name, good, detail=""):
    key = name.split()[0]
    rows[key] = rows.get(key, True) and bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def sources_for(mutant):
    """`app/Sources`, or a copy of its Swift files with the mutant applied.
    (folder, "") or (None, why)."""
    if not mutant:
        return SOURCES, ""
    name, anchor, replacement, _ = MUTANTS[mutant]
    copy = WORK / "mutant" / mutant / "Sources"
    if copy.exists():
        shutil.rmtree(copy)
    copy.mkdir(parents=True)
    for path in SOURCES.iterdir():
        if path.suffix == ".swift":
            shutil.copy2(path, copy / path.name)
    target = copy / name
    text = target.read_text()
    if text.count(anchor) != 1:
        return None, f"the mutant's anchor occurs {text.count(anchor)} times in {name}"
    target.write_text(text.replace(anchor, replacement))
    return copy, ""


def build(mutant):
    """(binary, "") or (None, why)."""
    folder, why = sources_for(mutant)
    if folder is None:
        return None, why
    built_dir = WORK / ("mutant/" + mutant if mutant else "probe")
    built_dir.mkdir(parents=True, exist_ok=True)
    entry = built_dir / "main.swift"
    if not entry.exists() or entry.read_text() != PROBE_SOURCE.read_text():
        entry.write_text(PROBE_SOURCE.read_text())
    binary = built_dir / "matte_chrome_probe"
    try:
        made = swift_build.build(sources=swift_build.app_sources(folder) + [entry],
                                 output=binary, timeout=900)
    except swift_build.SwiftBuildFailed as error:
        return None, (f"swiftc rc {error.rc if error.rc is not None else 'before running'}: "
                      f"{(error.diagnostics or ['(no output)'])[:6]}")
    print(f"  probe: {'up to date' if made.reused else f'built in {made.seconds:.0f} s'} — "
          f"{binary}", flush=True)
    return binary, ""


def run(binary):
    out = binary.parent / "answer.json"
    if out.exists():
        out.unlink()
    ran = bounded.run([str(binary), str(out)], 180)
    if not out.exists():
        return None, (f"rc {ran['rc']} expired {ran['expired']} "
                      f"{(ran['stdout'] + ran['stderr'])[-400:]}")
    return json.loads(out.read_text()), ""


def titles(menu):
    return [item["title"] for item in menu or []]


def matte_submenu(menu):
    for item in menu or []:
        if item["title"] == "Matte":
            return item["submenu"] or []
    return None


def checked(submenu):
    return [item["title"] for item in submenu or [] if item["on"]]


LONG_TAGS = ["Matte · Inverted Alpha", "Matte · Inverted Luma", "Matte · nothing behind"]
SHORT_TAGS = ["Matte · Alpha", "Matte · Luma"]


def over(top, bottom):
    """`top` (RGBA, 0…1) composited over an opaque `bottom` (RGB)."""
    a = top[3]
    return [top[i] * a + bottom[i] * (1 - a) for i in range(3)]


def luminance(rgb):
    def linear(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (linear(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(text, fill, row):
    """WCAG 2 contrast of `text` over `fill` over the opaque `row`, or None."""
    if not (len(text) == len(fill) == len(row) == 4):
        return None
    box = over(fill, row[:3])
    ink = over(text, box)
    hi, lo = sorted((luminance(box), luminance(ink)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def near(a, b, slop):
    return len(a) == len(b) == 3 and all(abs(x - y) <= slop for x, y in zip(a, b))


def score(answer):
    ids = answer["ids"]
    B, M, O, L, F = ids["B"], ids["M"], ids["O"], ids["L"], ids["F"]

    print("\nM1 — the rows")
    main = answer["trackMenu"]
    main_titles = titles(main)
    sub = matte_submenu(main)
    check("M1 Track ▸ Matte follows Solo and lists the five modes in order, tagged 0…4",
          "Solo" in main_titles and "Matte" in main_titles
          and main_titles.index("Matte") == main_titles.index("Solo") + 1
          and titles(sub) == MODES and [i["tag"] for i in sub] == list(range(5)),
          f"Track: {main_titles}; Matte: {titles(sub) if sub is not None else None}")
    context = answer["contextMenu"]
    csub = matte_submenu(context)
    check("M1 the track context menu: Hide Video, Mute Audio, Lock Track, Solo, Matte, -, "
          "Remove Track; its Matte lists the five modes tagged 0…4, each naming the clicked "
          "track (O)",
          titles(context) == CONTEXT_TITLES and titles(csub) == MODES
          and [i["tag"] for i in csub] == list(range(5))
          and all(i["track"] == O for i in csub)
          and all(i["track"] == O for i in context if i["title"] != "-"),
          json.dumps(context))

    print("\nM2 — the check states")
    states = answer["states"]
    for key, track, mode in (("currentM", M, "Alpha"), ("currentL", L, "Luma"),
                             ("currentF", F, "Off")):
        state = states[key]
        on = [i["title"] for i in state["items"] if i["on"]]
        check(f"M2 Track ▸ Matte with the current track {key[7:]}: only {mode} checked, every "
              "row enabled",
              state["current"] == track and on == [mode]
              and all(i["enabled"] for i in state["items"]), json.dumps(state))
    for key, mode in (("contextM", "Alpha"), ("contextL", "Luma"), ("contextO", "Off")):
        got = checked(matte_submenu(states[key]))
        check(f"M2 the context menu on {key[7:]}: only {mode} checked", got == [mode],
              f"checked {got}")

    print("\nM3 — the edits")
    edits = answer["edits"]
    c = edits["context"]
    want = dict(c["before"], **{str(O): "luma"})
    check("M3 the context menu's Luma on O (the current track is F) makes O a luma matte and "
          "nothing else, undo \"Track Matte\"",
          edits["currentBefore"] == F and c["performed"] and c["after"] == want
          and c["undoName"] == "Track Matte", json.dumps(c))
    a = edits["contextAgain"]
    check("M3 choosing Luma again is an identity, and one undo restores the project",
          a["performed"] and a["unchanged"] and edits["contextUndone"],
          json.dumps({"again": a, "undone": edits["contextUndone"]}))
    m = edits["menu"]
    want = dict(m["before"], **{str(B): "alpha_inverted"})
    check("M3 Track ▸ Matte ▸ Inverted Alpha on the current track (B) makes B an inverted "
          "alpha matte and nothing else, undo \"Track Matte\"",
          edits["menuCurrent"] == B and m["performed"] and m["after"] == want
          and m["undoName"] == "Track Matte", json.dumps(m))
    check("M3 choosing it again is an identity, and one undo restores the project",
          edits["menuAgain"]["unchanged"] and edits["menuUndone"],
          json.dumps({"again": edits["menuAgain"], "undone": edits["menuUndone"]}))

    print("\nT1 — the header tag's words")
    tags = answer["tags"]
    words = {"alpha": "Alpha", "alpha_inverted": "Inverted Alpha", "luma": "Luma",
             "luma_inverted": "Inverted Luma"}
    good = all(tags.get(mode) == {"text": f"Matte · {word}", "dimmed": False}
               for mode, word in words.items())
    check("T1 the four modes over an ordinary track: \"Matte · <mode>\", not dimmed", good,
          json.dumps({k: tags.get(k) for k in words}))
    nothing = {"text": "Matte · nothing behind", "dimmed": True}
    check("T1 a back-most matte and a matte in front of a matte: \"Matte · nothing behind\", "
          "dimmed",
          tags["backMost"] == nothing and tags["matteBehindMatte"] == nothing,
          json.dumps({"backMost": tags["backMost"], "matteBehindMatte": tags["matteBehindMatte"]}))
    check("T1 an ordinary track has no tag; the lower of two mattes keeps its words",
          tags["ordinary"] is None
          and tags["lowerOfTwo"] == {"text": "Matte · Luma", "dimmed": False},
          json.dumps({"ordinary": tags["ordinary"], "lowerOfTwo": tags["lowerOfTwo"]}))
    print(f"  (placement, not scored: {json.dumps(answer['placement'])})")

    print("\nT2 — the tag on a Small name line")
    lines = answer["nameLines"]
    width, gap, minimum = lines["headerWidth"], lines["gap"], lines["minimum"]
    for line in lines["rows"]:
        full = line.get("full")
        shortened = full in LONG_TAGS
        for kind in ("text", "audio"):
            row = line.get(kind) or {}
            room = width - 14 - row.get("clip", width)
            drawn_width = row.get("drawnWidth")
            reads = '"Matte"' if shortened else "its own words"
            check(f"T2 \"{full}\" on a Small {kind} row: on the name's line, the name keeps "
                  f">= {minimum:.0f} pt, the tag reads {reads}, and the clip is the drawn "
                  "width plus the gap",
                  full in LONG_TAGS + SHORT_TAGS and row.get("ownLine") is False
                  and room >= minimum
                  and row.get("drawnText") == ("Matte" if shortened else full)
                  and drawn_width is not None and abs(row["clip"] - (drawn_width + gap)) < 0.01,
                  f"room {room:.1f} pt, {json.dumps(row)}")
    check("T2 every one of the five tag texts was measured",
          sorted(line.get("full") or "" for line in lines["rows"])
          == sorted(LONG_TAGS + SHORT_TAGS), json.dumps([l.get("full") for l in lines["rows"]]))

    print("\nT3 — the tag's contrast")
    corners = [[r, g, b] for r in (0.0, 1.0) for g in (0.0, 1.0) for b in (0.0, 1.0)]
    for look, colors in answer["contrast"].items():
        row = colors["row"]
        dimmed = contrast(colors["dimmedText"], colors["dimmedFill"], row)
        plain = contrast(colors["text"], colors["fill"], row)
        check(f"T3 {look}: the dimmed tag's text over its box over the header row has a "
              f"contrast ratio >= 3.0", dimmed is not None and dimmed >= 3.0,
              f"{dimmed and round(dimmed, 2)}:1, {json.dumps(colors)}")
        check(f"T3 {look}: the undimmed tag's text over its box (the host's accent) over "
              f"the header row has a contrast ratio >= 4.5", plain is not None and plain >= 4.5,
              f"{plain and round(plain, 2)}:1")
        fill = colors["fill"]
        worst = (min(((contrast(colors["text"], c + fill[3:], row), c) for c in corners),
                     key=lambda pair: pair[0])
                 if len(fill) == 4 and plain is not None else (None, None))
        check(f"T3 {look}: the undimmed tag's ratio is >= 4.5 over every accent the box "
              f"could take (each sRGB cube corner at the box's alpha {fill[3:]})",
              worst[0] is not None and worst[0] >= 4.5,
              f"worst {worst[0] and round(worst[0], 2)}:1 at accent {worst[1]}")
        dim_fill = colors["dimmedFill"]
        dim_worst = (min(((contrast(colors["dimmedText"], c + dim_fill[3:], row), c)
                          for c in corners), key=lambda pair: pair[0])
                     if len(dim_fill) == 4 and dimmed is not None else (None, None))
        check(f"T3 {look}: the dimmed tag's ratio is >= 3.0 over every accent its box could "
              f"take (each sRGB cube corner at the dimmed box's alpha {dim_fill[3:]})",
              dim_worst[0] is not None and dim_worst[0] >= 3.0,
              f"worst {dim_worst[0] and round(dim_worst[0], 2)}:1 at accent {dim_worst[1]}")
        control = contrast(row, colors["dimmedFill"], row)
        check(f"T3 CONTROL {look}: the measure can fail — the header row's own colour as "
              f"text over the dimmed box is < 1.5:1",
              control is not None and control < 1.5, f"{control and round(control, 2)}:1")
    looks = answer["contrast"]
    rows_apart = ("light" in looks and "dark" in looks
                  and len(looks["light"]["row"]) == 4 and len(looks["dark"]["row"]) == 4)
    check("T3 CONTROL: the two looks resolved apart — the light row's luminance > 0.5 and the "
          "dark row's < 0.1",
          rows_apart and luminance(looks["light"]["row"][:3]) > 0.5
          and luminance(looks["dark"]["row"][:3]) < 0.1,
          json.dumps({k: v["row"] for k, v in looks.items()}))

    print("\nLN — a matte lane's clip")
    lane = answer["lane"]
    fill, back, clip, control = lane["ownFill"], lane["matteLane"], lane["matteClip"], \
        lane["ordinaryControl"]
    measurable = (len(fill) == len(back) == 3
                  and max(abs(x - y) for x, y in zip(fill, back)) > 20)
    check("LN CONTROL: an ordinary lane's identical clip reads the same fill (±1), and the "
          "fill and the lane differ by > 20 in some channel",
          near(control, fill, 1) and measurable,
          f"fill {fill} control {control} lane {back}")
    mixed = [round((x + y) / 2, 1) for x, y in zip(fill, back)] if measurable else []
    check("LN the matte lane's clip pixel is the lane and the fill mixed at 0.5 (±3)",
          measurable and near(clip, mixed, 3),
          f"clip {clip} wanted {mixed} (fill {fill}, lane {back}) at {lane['points']} "
          f"scale {lane['scale']}, {lane['space']}")

    print("\nNT — the Clip tab's note")
    notes = answer["notes"]
    want_notes = {"singleM": NOTE, "sharedM_M2": NOTE, "mixedModeM_L": None,
                  "mixedOrdinaryM_B": None, "noTargetL": NOTHING, "ordinaryB": None,
                  "ordinaryB_O": None, "empty": None}
    wrong = {k: notes.get(k) for k, v in want_notes.items() if notes.get(k) != v}
    check("NT matteNote: MT-7's words for single and shared-mode selections, \"Nothing is "
          "behind…\" with no target, nil for mixed, ordinary and empty", not wrong,
          json.dumps(wrong))
    shown = answer["shownNotes"]
    check("NT the inspector's pinned block shows it on the first sub-tab and on Clip for M, "
          "\"Nothing is behind…\" for L, and nothing for B",
          shown == {"mFirstTab": NOTE, "mClipTab": NOTE, "b": None, "l": NOTHING},
          json.dumps(shown))

    print("\nHT — the canvas hit")
    hit = answer["hit"]
    check("HT CONTROL: the window's recipe layer is a matte layer (non-null `matte.into`)",
          hit["windowInto"] is not None, json.dumps(hit))
    check("HT the canvas hits the matte clip inside its box and the matted card outside it",
          hit["canvasInside"] == hit["window"] and hit["canvasOutside"] == hit["card"],
          json.dumps(hit))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    named = MUTANTS[args.mutant][3] if args.mutant else []
    print("mattes MT4 — the chrome probe"
          + (f", the {args.mutant} MUTANT ({' '.join(named)} must FAIL)" if args.mutant else ""),
          flush=True)
    WORK.mkdir(parents=True, exist_ok=True)
    binary, why = build(args.mutant)
    check("B0 the probe builds over app/Sources", binary is not None, why or str(binary))
    answer = None
    if binary is not None:
        answer, why = run(binary)
        check("B0 the probe answers and drove an editor",
              answer is not None and "error" not in answer,
              why or (answer or {}).get("error", ""))
    if answer is not None and "error" not in answer:
        score(answer)
    scored = ["B0", "M1", "M2", "M3", "T1", "T2", "T3", "LN", "NT", "HT"]
    passed = sum(1 for name in scored if rows.get(name))
    print(f"\n{passed}/{len(scored)}")
    if args.mutant:
        if not rows.get("B0"):
            print(f"mutant {args.mutant}: the control could not be performed")
            return 2
        survived = [name for name in named if rows.get(name)]
        print(f"{'MUTANT PASS' if not survived else 'MUTANT FAILURE'}: {args.mutant} — "
              f"{' '.join(named)} {'all FAILED' if not survived else 'did not all fail'}")
        return 0 if not survived else 1
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
