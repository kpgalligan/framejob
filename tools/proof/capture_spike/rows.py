"""The capture spike's rows (road map 11, V1): the table, and one pure
predicate per row over the probe's measured JSON.

A row is (ID, question, kind, mode, what it asks). `kind` is `instrument`
(I), `control` (C) or `answer` (A). A predicate takes the row's `measured`
dict (and, for the I rows, the inventory checker's result) and answers
`(ok, reason)`; the reason carries the numbers. An answer row's `fail` is a
measured "no"; an instrument's or a control's is the spike failing.

`host_skip` is the only place a row is skipped, and only by name: a locked
console, no display, an occluded window, a probe that did not activate, a
host with no backing-scale-2 screen (W4a–c only: their answer depends on the
scale, and the probe puts its windows on a scale-2 screen when one exists),
and L7's label not on screen.
"""

ROWS = [
    ("B0", "q1", "instrument", None, "shader and probe built (-O -wmo, REELCUT_DEV_TOOLS)"),
    ("W0", "q1", "instrument", "well", "window visible, not occluded; the layer shows a frame"),
    ("W1", "q1", "answer", "well", "cacheDisplay of the live well is not the picture"),
    ("W2", "q1", "control", "well", "M (selected vs unselected) has a non-empty core"),
    ("W3", "q1", "control", "well", "quadrant classifier: still 4/4, unmodified well ≤ 3/4"),
    ("W4a", "q1", "answer", "well", "NSImageView above playerHost: (i)–(iv)"),
    ("W4b", "q1", "answer", "well", "CALayer contents above the AVPlayerLayer: (i)–(iv)"),
    ("W4c", "q1", "answer", "well", "three passes (capture, still, overlay cacheDisplay): (i)–(iv)"),
    ("W5", "q1", "control", "well", "NSImageView above the OVERLAY: (ii) fails"),
    ("W6", "q1", "control", "well", "NSImageView not removed: (iv) fails"),
    ("S0", "q2", "instrument", "sheets", "the app's menu bar set, the three items found"),
    ("S1a", "q2", "answer", "sheets", "File ▸ Export… puts a sheet up and returns, main free"),
    ("S1b", "q2", "answer", "sheets", "Track ▸ Remove Track puts a sheet up and returns, main free"),
    ("S1c", "q2", "answer", "sheets", "File ▸ Add Media… puts a sheet up and returns, main free"),
    ("S2a", "q2", "answer", "sheets", "Export sheet captured (size, ≥ 16 colours) and closed"),
    ("S2b", "q2", "answer", "sheets", "Remove Track alert captured and closed"),
    ("S2c", "q2", "answer", "sheets", "Add Media open panel captured and closed"),
    ("S3", "q2", "control", "sheets", "the parent's capture does not hold the sheet (< 50 %)"),
    ("S4", "q2", "control", "modal", "a runModal item: the call blocks ≥ 1 s, the marker runs inside"),
    ("I1", "q2", "instrument", "menu", "every menu leaf's selector is in the inventory, and back"),
    ("I2", "q2", "instrument", None, "grep sites ↔ inventory sites, one-to-one, tokens hold"),
    ("I3", "q2", "instrument", None, "verdicts cite lines that hold their tokens; references resolve"),
    ("I4", "q2", "control", None, "the checker catches one removed selector and one removed site"),
    ("A0", "q3", "instrument", "appearance", "the editor on screen; appearance, activation"),
    ("A1", "q3", "control", "appearance", "fresh aqua vs fresh darkAqua differ > 10 %"),
    ("A2", "q3", "control", "appearance", "two fresh windows, same appearance: byte-identical"),
    ("A3", "q3", "answer", "appearance", "window.appearance → opposite = fresh opposite"),
    ("A4", "q3", "answer", "appearance", "window.appearance → nil = before"),
    ("A5", "q3", "answer", "appearance", "contentView.appearance → opposite = fresh opposite"),
    ("A6", "q3", "answer", "appearance", "contentView.appearance → nil = before"),
    ("A7", "q3", "control", "appearance", "window.appearance = the one in effect = nil capture"),
    ("L1", "q4", "control", "layout", "a view missing its height: hasAmbiguousLayout true"),
    ("L2", "q4", "control", "layout", "the same with height pinned: false"),
    ("L3", "q4", "answer", "layout", "the editor's tree: no view answers ambiguous"),
    ("L4", "q4", "control", "layout", "truncating label: intrinsic width > frame"),
    ("L5", "q4", "control", "layout", "label that fits: not"),
    ("L6", "q4", "answer", "layout", "wrapping label: the heuristic says not truncated"),
    ("L7", "q4", "answer", "layout", "#70: the word-style note's intrinsic width > frame"),
]

LETTER = {"instrument": "I", "control": "C", "answer": "A"}
MODE_TIMEOUT = {"modal": 60}
MODES = ["layout", "well", "sheets", "modal", "menu", "appearance"]
QUESTION_MODES = {"q1": ["well"], "q2": ["sheets", "modal", "menu"], "q3": ["appearance"],
                  "q4": ["layout"]}
ACTIVATED = {"S1a", "S1b", "S1c", "S2a", "S2b", "S2c", "S3",
             "A1", "A2", "A3", "A4", "A5", "A6", "A7"}
# At scale 1 the M-core is ~300 px and every pixel keeps (pass 3's run 2);
# the recorded answer is scale 2's.
SCALE_DEPENDENT = {"W4a", "W4b", "W4c"}


def host_skip(rid, window, host):
    """A named host condition, or None."""
    if rid[0] not in "WSA" or window is None:
        return None
    if host.get("console_locked"):
        return "host: console locked"
    if window.get("screens", 1) == 0:
        return "host: no display"
    if window.get("occluded") is True:
        return "host: window occluded"
    if rid in ACTIVATED and not (window.get("active") and window.get("key_is_editor")):
        return "host: probe not active"
    if rid in SCALE_DEPENDENT and window.get("scale2_screens") == 0:
        return "host: no scale-2 screen"
    return None


def _yes(v):
    return v is True


def W0(m):
    ok = _yes(m.get("visible")) and m.get("occluded") is False and _yes(m.get("displayed_buffer"))
    return ok, (f"visible {m.get('visible')}, occluded {m.get('occluded')}, scale "
                f"{m.get('scale')}, displayedPixelBuffer {m.get('displayed_buffer')} after "
                f"{m.get('displayed_ms')} ms")


def W1(m):
    h = m.get("harness_case", {})
    return m.get("verdict") != "picture", (
        f"live well = {m.get('verdict')} (mean {m.get('mean')}, counts {m.get('counts')}, "
        f"shape rect yellow {m.get('shape_yellow_fraction')}); never-shown window = "
        f"{h.get('verdict')} (mean {h.get('mean')})")


def W2(m):
    return (m.get("m_core", 0) > 0 and _yes(m.get("reselected_identical")),
            f"M {m.get('m')} px, M-core {m.get('m_core')}, M+2 {m.get('m_dilated')}, bounds "
            f"{m.get('m_bounds')}, well {m.get('well_px')}, scale {m.get('scale')}, reselected "
            f"identical {m.get('reselected_identical')}")


def W3(m):
    own = m.get("own_bitmap", {}).get("correct", -1)
    raw = m.get("unmodified", {}).get("correct", -1)
    return own == 4 and 0 <= raw <= 3, (
        f"still {own}/4 {m.get('own_bitmap', {}).get('classes')}; unmodified well {raw}/4 "
        f"{m.get('unmodified', {}).get('classes')}")


def _four(m):
    return (f"(i) {m.get('quadrants', {}).get('correct')}/4 "
            f"{m.get('quadrants', {}).get('classes')}; (ii) M-core {m.get('core_within_3')}/"
            f"{m.get('core_total')} = {m.get('core_fraction')}; (iii) outside changed "
            f"{m.get('outside_changed')}; (iv) tree restored {m.get('tree_restored')}, next "
            f"identical {m.get('next_identical')} ({m.get('next_changed')} px)")


def W4(m):
    ok = all(_yes(m.get(k)) for k in
             ("i_quadrants_4of4", "ii_overlay_on_top", "iii_nothing_outside", "iv_restored"))
    reason = _four(m)
    a = m.get("overlay_alpha")
    if a:
        k, o = a.get("kept", {}), a.get("not_kept", {})
        reason += (f"; overlay alpha at the M-core (selected/unselected against w4a/w5): kept "
                   f"n {k.get('n')} {k.get('min')}–{k.get('max')} median {k.get('median')}, "
                   f"not kept n {o.get('n')} {o.get('min')}–{o.get('max')} median "
                   f"{o.get('median')}, no contrast {a.get('no_contrast')}")
    return ok, reason


def W5(m):
    return m.get("ii_overlay_on_top") is False, "control: " + _four(m)


def W6(m):
    return m.get("iv_restored") is False, "control: " + _four(m)


def S0(m):
    return (_yes(m.get("menu_set")) and _yes(m.get("all_found")),
            f"menus {len(m.get('menus', []))}, items found {m.get('all_found')}, targets "
            f"{m.get('targets')}, active {m.get('is_active')} in {m.get('active_ms')} ms, key "
            f"{m.get('key_is_editor')}, main {m.get('main_is_editor')}, first responder "
            f"{m.get('first_responder')}")


def S1(m):
    ok = _yes(m.get("sheet")) and _yes(m.get("marker_unrun_at_return")) and _yes(
        m.get("modal_window_nil"))
    return ok, (f"route {m.get('route')}: returned in {m.get('returned_ms')} ms, marker unrun "
                f"{m.get('marker_unrun_at_return')}, modalWindow nil {m.get('modal_window_nil')},"
                f" sheet {m.get('sheet_class')} after {m.get('sheet_ms')} ms")


def S2(m):
    ok = _yes(m.get("size_ok")) and m.get("distinct_colours", 0) >= 16 and _yes(m.get("closed"))
    return ok, (f"{m.get('sheet_class')}: {m.get('px')} px (want {m.get('want_px')}), "
                f"{m.get('distinct_colours')} colours, closed by {m.get('close_by')} "
                f"{m.get('closed')} in {m.get('close_ms')} ms")


def S3(m):
    sheets = m.get("sheets", [])
    ok = bool(sheets) and all(s["fraction"] < 0.5 for s in sheets)
    return ok, "; ".join(f"{s['case']}: {s['matching']}/{s['compared']} = {s['fraction']}"
                         for s in sheets) or "no sheet was up"


def S4(m):
    ok = m.get("elapsed_s", 0) >= 1.0 and _yes(m.get("marker_inside"))
    return ok, (f"call returned after {m.get('elapsed_s')} s; marker ran {m.get('marker_ran')}, "
                f"inside {m.get('marker_inside')}; background main.sync completed "
                f"{m.get('sync_completed')} at {m.get('sync_ms')} ms, inside the call "
                f"{m.get('sync_inside')}")


def A0(m):
    act = m.get("activation", {})
    return _yes(m.get("on_screen")) and m.get("occluded") is False, (
        f"on screen {m.get('on_screen')}, system {m.get('system')}, effective "
        f"{m.get('effective')}, active {act.get('active')} in {act.get('active_ms')} ms, key "
        f"{act.get('key_is_editor')}")


def _diff(m):
    top = ", ".join(f"{c['view']} {c['box_px']} ({c['pixels']} px)"
                    for c in m.get("clusters", [])[:4])
    return (f"identical {m.get('identical')}, {m.get('differing')} px differ "
            f"({m.get('fraction')}); effective {m.get('effective', '-')}"
            + (f"; clusters: {top}" if top else ""))


def A1(m):
    return m.get("fraction", 0) > 0.10, _diff(m)


def identical(m):
    return _yes(m.get("identical")), _diff(m)


def L_ambiguous(want):
    def predicate(m):
        return m.get("ambiguous") is want, f"hasAmbiguousLayout {m.get('ambiguous')}, frame {m.get('frame')}"
    return predicate


def L3(m):
    views = m.get("ambiguous", [])
    return len(views) == 0, (f"{len(views)} of {m.get('views')} views ambiguous: "
                             + ", ".join(f"{v['class']} {v['frame']}" for v in views[:6]))


def L_truncated(want):
    def predicate(m):
        return m.get("truncated") is want, (f"intrinsic {m.get('intrinsic_w')} vs frame "
                                            f"{m.get('frame_w')}")
    return predicate


def L7(m):
    wide = m.get("wider_than_frame", [])
    return _yes(m.get("truncated")), (
        f"note intrinsic {m.get('intrinsic_w')} vs frame {m.get('frame_w')}; "
        f"{len(wide)} visible field(s) wider than their frame: "
        + ", ".join(f"{w['class']} “{w['text'][:28]}” {w['intrinsic_w']}>{w['frame_w']}"
                    for w in wide[:5]))


PREDICATES = {
    "W0": W0, "W1": W1, "W2": W2, "W3": W3, "W4a": W4, "W4b": W4, "W4c": W4, "W5": W5,
    "W6": W6, "S0": S0, "S1a": S1, "S1b": S1, "S1c": S1, "S2a": S2, "S2b": S2, "S2c": S2,
    "S3": S3, "S4": S4, "A0": A0, "A1": A1, "A2": identical, "A3": identical, "A4": identical,
    "A5": identical, "A6": identical, "A7": identical, "L1": L_ambiguous(True),
    "L2": L_ambiguous(False), "L3": L3, "L4": L_truncated(True), "L5": L_truncated(False),
    "L6": L_truncated(False), "L7": L7,
}
