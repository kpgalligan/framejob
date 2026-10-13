#!/usr/bin/env python3
"""The sharp chrome pass (`designs/design_handoff_sharp/`), offscreen.

    python3 tools/proof/sharp_chrome.py

The pass squares every chrome corner (the radius tokens in `Theme.swift` go
to 0), keeps a clip bar at 2 pt, and replaces the zoom slider's system knob
with `Controls.swift`'s `BlockSlider` — a 3 pt track and a 7 × 11 pt block.
Two instruments, `e2_chrome.py`'s:

* **a probe** compiled from `app/Sources` over `harness/build.sh`'s own
  `swiftc` line (a build failure is a scored FAILURE, never an exit): the six
  tokens, the timeline's slider class, and a standalone `BlockSlider` in the
  bar's own configuration (`controlSize = .small`, 110 wide, its intrinsic
  height) — its knob rect at three values, and a bitmap through
  `recording_probe.py`'s `renderBase64` path (`cacheDisplay`, read back with
  `NSBitmapImageRep`), whose four corner pixels must equal its centre (a
  rectangle; an oval leaves them background). An `AccentButton`'s corner
  pixel against its edge.
* **the harness**, the editor at 1440 × 862 in both appearances, twice each.
  Every row is written in POINTS and converted with the render's own
  `Image.scale`: the PNG is at the display's backing scale, 1 on a sleeping
  display (`recording_probe.py`'s 6c comment). The harness's playhead is at
  2 s, so its line (x 216) is clear of the clip corner at x 132 — at 0 s the
  coral line covers the very pixels the corner row reads.

Made to fail on purpose (2026-09-23): `DS.clipRadius` back to 4 takes the
two token rows and the `D_(s-1)` row per appearance (25/29);
`BlockSliderCell.drawKnob` drawing an oval takes the probe's corner row and
all four slider rows per appearance — the oval's centre row is 12 px of knob
ink at scale 2, not 14, so the knob run is not found at all (20/29);
`DS.buttonRadius` back to 4 takes the token row, the probe's AccentButton row
and the Export row per appearance (25/29).
"""

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2_chrome as e2  # noqa: E402  (the helpers: Image, clip, project, packages)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work")
CHROME = os.path.join(WORK, "chrome-sharp")
PROBE = os.path.join(WORK, "sharp-probe")

WIDTH, HEIGHT = e2.WIDTH, e2.HEIGHT          # 1440 × 862
CLIP_X0, STRIP_Y = e2.CLIP_X0, e2.STRIP_Y    # 132, 627 — the card's top-left
PLAYHEAD_SEC = 2                             # x 132 + 2 × 42 = 216, clear of the corner

# The toolbar's Export (`AccentButton`, 26 tall in a 44 pt bar, 12 pt from
# the right edge) and the timeline bar's S/M/L (3 × 26 wide, 22 tall, 12 pt
# in), in points.
EXPORT_RIGHT, EXPORT_TOP, EXPORT_MID = WIDTH - 12, 9, 22
SML_LEFT, SML_TOP = WIDTH - 12 - 78, 569
# The zoom slider: `phase5_chrome.py`'s `meter_rect().x1 + 12 + 28 + 8`,
# 110 wide, on the bar's centreline (bar 562–598).
SLIDER_X0 = WIDTH - 297
SLIDER_X1 = SLIDER_X0 + 110
BAR_MID = 580

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append(bool(ok))
    print(f"  {'PASS' if ok else 'FAIL'}: {name}")
    if detail:
        print("      " + detail)


# ---------------------------------------------------------------------------
# The probe.

PROBE_SOURCE = r'''// Written by tools/proof/sharp_chrome.py. See that file's header.
import AppKit

_ = NSApplication.shared
let out = URL(fileURLWithPath: CommandLine.arguments[1])
var answer: [String: Any] = [:]

answer["tokens"] = [
    "controlRadius": Double(DS.controlRadius), "buttonRadius": Double(DS.buttonRadius),
    "listRowRadius": Double(DS.listRowRadius), "fieldRadius": Double(DS.fieldRadius),
    "railSlotRadius": Double(DS.railSlotRadius), "clipRadius": Double(DS.clipRadius),
]
answer["layoutClipRadius"] = Double(TimelineLayout.clipRadius)

let timeline = TimelineView()
let zoom: NSSlider = timeline.zoomSlider
answer["zoomIsBlock"] = zoom is BlockSlider
answer["zoomCellIsBlock"] = zoom.cell is BlockSliderCell

func rect(_ r: NSRect) -> [Double] {
    [Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)]
}

/// `recording_probe.py`'s `renderBase64` path, kept as the rep.
func bitmap(_ view: NSView) -> NSBitmapImageRep? {
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}

/// The pixel containing the POINT (x, y), top-left origin, as raw samples.
func pixel(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat, scale: CGFloat) -> [Int] {
    var samples = [Int](repeating: 0, count: max(rep.samplesPerPixel, 4))
    rep.getPixel(&samples, atX: Int((x * scale).rounded(.down)), y: Int((y * scale).rounded(.down)))
    return Array(samples.prefix(rep.samplesPerPixel))
}

// The slider in the bar's own configuration (`TimelineBar.zoomCluster`).
let slider = BlockSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
slider.controlSize = .small
let height = slider.intrinsicContentSize.height
slider.frame = NSRect(x: 0, y: 0, width: 110, height: height)
var sliderAnswer: [String: Any] = [
    "height": Double(height), "flipped": slider.isFlipped, "bounds": rect(slider.bounds),
]
if let cell = slider.cell as? BlockSliderCell {
    var knobs: [[String: Any]] = []
    for value in [0.0, 0.5, 1.0] {
        slider.doubleValue = value
        let knob = cell.knobRect(flipped: true)
        let bar = cell.barRect(flipped: true)
        knobs.append([
            "value": value, "knob": rect(knob), "barMidY": Double(bar.midY),
            "inside": slider.bounds.contains(knob),
        ])
    }
    sliderAnswer["knobs"] = knobs
    slider.doubleValue = 0.5
    if let rep = bitmap(slider) {
        let scale = CGFloat(rep.pixelsWide) / slider.bounds.width
        // The knob in the bitmap's top-left space.
        var knob = cell.knobRect(flipped: slider.isFlipped)
        if !slider.isFlipped { knob.origin.y = slider.bounds.height - knob.maxY }
        let mid = knob.midY
        sliderAnswer["bitmap"] = [
            "scale": Double(scale), "knob": rect(knob),
            "centre": pixel(rep, knob.midX, mid, scale: scale),
            "corners": [
                pixel(rep, knob.minX + 1, knob.minY + 1, scale: scale),
                pixel(rep, knob.maxX - 1, knob.minY + 1, scale: scale),
                pixel(rep, knob.minX + 1, knob.maxY - 1, scale: scale),
                pixel(rep, knob.maxX - 1, knob.maxY - 1, scale: scale),
            ],
            "track10": pixel(rep, 10, mid, scale: scale),
            "track100": pixel(rep, 100, mid, scale: scale),
            "above30": pixel(rep, 30, mid - 4, scale: scale),
        ]
    }
}
answer["slider"] = sliderAnswer

let button = AccentButton(
    title: "Export", symbol: nil, fallback: "", tooltip: "Export", action: nil)
button.frame = NSRect(x: 0, y: 0, width: 100, height: 26)
if let rep = bitmap(button) {
    let scale = CGFloat(rep.pixelsWide) / button.bounds.width
    answer["button"] = [
        "corner": pixel(rep, 0, 0, scale: scale), "edge": pixel(rep, 2, 13, scale: scale),
    ]
}

try! JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
    .write(to: out)
exit(0)
'''


def build_probe():
    """`e2_chrome.py`'s builder, pointed at this probe: the same swiftc line as
    `harness/build.sh`, the same staleness rule, a reason instead of an exit.
    (The binary keeps e2's name, `e2probe`, in this script's own directory.)"""
    e2.PROBE, e2.PROBE_SOURCE = PROBE, PROBE_SOURCE
    return e2.build_probe()


PROBE_ROWS = [
    "the six radius tokens are square (0) and a clip keeps 2",
    "TimelineLayout.clipRadius is 2",
    "the timeline's zoom slider is a BlockSlider, its cell a BlockSliderCell",
    "the small slider's knob is 7 × 11 at 0, 0.5 and 1",
    "its midX strictly increases with the value",
    "its midY is the bar's midY",
    "the knob lies inside the slider's bounds at its small intrinsic height",
    "the knob's four corner pixels are the knob's centre ink (a rectangle, not an oval)",
    "the track at x 10 (accent) and x 100 (border) differ",
    "the pixel 4 pt above the track is background (a 3 pt track)",
    "an AccentButton's corner pixel is its fill (a square corner)",
]


def probe_checks():
    print("\n1 — the probe: tokens, the slider class, a standalone BlockSlider")
    binary, error = build_probe()
    if error:
        for name in PROBE_ROWS:
            check(name, False, error)
        return
    out = os.path.join(PROBE, "answer.json")
    result = subprocess.run([binary, out], capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        for name in PROBE_ROWS:
            check(name, False, (result.stdout + result.stderr).strip()[-300:])
        return
    with open(out) as f:
        a = json.load(f)
    want = {"controlRadius": 0, "buttonRadius": 0, "listRowRadius": 0, "fieldRadius": 0,
            "railSlotRadius": 0, "clipRadius": 2}
    check(PROBE_ROWS[0], a["tokens"] == want, f"{a['tokens']}")
    check(PROBE_ROWS[1], a["layoutClipRadius"] == 2, f"{a['layoutClipRadius']}")
    check(PROBE_ROWS[2], a["zoomIsBlock"] and a["zoomCellIsBlock"],
          f"slider {a['zoomIsBlock']}, cell {a['zoomCellIsBlock']}")
    s = a["slider"]
    knobs = s.get("knobs", [])
    print(f"      the small slider: height {s['height']:g} pt (intrinsic), flipped "
          f"{s['flipped']}, bounds {s['bounds']}")
    for k in knobs:
        print(f"      value {k['value']:g}: knob {k['knob']}, bar midY {k['barMidY']:g}")
    check(PROBE_ROWS[3], len(knobs) == 3 and all(
        k["knob"][2] == 7 and k["knob"][3] == 11 for k in knobs))
    mids = [k["knob"][0] + k["knob"][2] / 2 for k in knobs]
    check(PROBE_ROWS[4], len(mids) == 3 and mids[0] < mids[1] < mids[2], f"{mids}")
    check(PROBE_ROWS[5], len(knobs) == 3 and all(
        abs(k["knob"][1] + k["knob"][3] / 2 - k["barMidY"]) < 1e-9 for k in knobs))
    check(PROBE_ROWS[6], len(knobs) == 3 and all(k["inside"] for k in knobs))
    b = s.get("bitmap")
    if not b:
        for name in PROBE_ROWS[7:10]:
            check(name, False, "no bitmap")
    else:
        print(f"      bitmap at scale {b['scale']:g}: knob {b['knob']}, centre {b['centre']}")
        check(PROBE_ROWS[7], all(c == b["centre"] for c in b["corners"]),
              f"corners {b['corners']}")
        check(PROBE_ROWS[8], b["track10"] != b["track100"],
              f"x 10 {b['track10']}, x 100 {b['track100']}")
        check(PROBE_ROWS[9], b["above30"] not in (b["track10"], b["track100"], b["centre"])
              and b["above30"][-1] == 0, f"{b['above30']}")
    btn = a.get("button")
    check(PROBE_ROWS[10], btn is not None and btn["corner"] == btn["edge"],
          f"{btn}")


# ---------------------------------------------------------------------------
# The harness.


def render(binary, package, out, appearance):
    args = [binary, package, out, appearance, str(WIDTH), str(HEIGHT), "-1",
            str(PLAYHEAD_SEC), "1", "clip", "-", "-"]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stdout + result.stderr).strip()[-400:]
    return out, None


HARNESS_ROWS = [
    "two renders are byte-identical",
    "Export: the top-right corner pixel is the button's fill, not the toolbar",
    "S/M/L: the top-left corner pixel is the cell's top edge, not the bar",
    "clip corner: D_0 is not the border ink (not square)",
    "clip corner: D_(s-1) is not the lane (not 4 pt)",
    "zoom slider: a 7 pt knob run on the centreline, accent left, a different colour right",
    "zoom slider: the knob is 11 pt tall at its midX",
    "zoom slider: the knob's four corner pixels are the knob ink (a block, not an oval)",
    "zoom slider: 1 px above the knob, 4 pt left of it, is neither accent nor knob (3 pt track)",
]


def pixel(image, x, y):
    row = image.rows[y]
    c = image.channels
    return tuple(row[x * c:(x + 1) * c])


def px(image, x, y):
    s = image.scale
    return pixel(image, int(round(x * s)), int(round(y * s)))


def slider_rows(image, appearance):
    s = image.scale
    k = int(round(s))
    row = int(round(BAR_MID * s))
    runs = []
    for x in range(int(round(SLIDER_X0 * s)), int(round(SLIDER_X1 * s))):
        p = pixel(image, x, row)
        if runs and runs[-1][0] == p:
            runs[-1][2] += 1
        else:
            runs.append([p, x, 1])

    def vertical(x, colour):
        top = bottom = row
        while top > 0 and pixel(image, x, top - 1) == colour:
            top -= 1
        while bottom + 1 < image.height and pixel(image, x, bottom + 1) == colour:
            bottom += 1
        return top, bottom

    lengths = {7 * k} if k == 2 else {7 * k - 1, 7 * k}
    heights = {11 * k} if k == 2 else {10, 11}
    found = None
    for i, (colour, x0, n) in enumerate(runs):
        if 0 < i < len(runs) - 1 and n in lengths:
            top, bottom = vertical(x0 + n // 2, colour)
            if bottom - top + 1 >= 9 * s:
                found = (i, colour, x0, n, top, bottom)
                break
    name = f"{appearance}: "
    if not found:
        check(name + HARNESS_ROWS[5], False,
              f"runs on y {BAR_MID} pt: {[(r[0][:3], r[1], r[2]) for r in runs]}")
        for row_name in HARNESS_ROWS[6:9]:
            check(name + row_name, False, "no knob found")
        return
    i, colour, x0, n, top, bottom = found
    x1 = x0 + n
    left, right = runs[i - 1][0], runs[i + 1][0]
    print(f"      {appearance}: knob {colour[:3]} x {x0}–{x1} px, y {top}–{bottom} px; "
          f"left {left[:3]}, right {right[:3]}")
    check(name + HARNESS_ROWS[5], left != right and colour not in (left, right),
          f"run {n} px; left {left[:3]}, right {right[:3]}")
    check(name + HARNESS_ROWS[6], bottom - top + 1 in heights,
          f"{bottom - top + 1} px at scale {s:g}")
    corners = [pixel(image, x0, top + 1), pixel(image, x1 - 1, top + 1),
               pixel(image, x0, bottom - 1), pixel(image, x1 - 1, bottom - 1)]
    check(name + HARNESS_ROWS[7], all(c == colour for c in corners),
          f"{[c[:3] for c in corners]}")
    accent = pixel(image, x0 - 4 * k, row)
    probe = pixel(image, x0 - 4 * k, top - 1)
    check(name + HARNESS_ROWS[8], probe not in (accent, colour),
          f"{probe[:3]} vs accent {accent[:3]}, knob {colour[:3]}")


def harness_checks():
    print("\n2 — the harness: the editor, 1440 × 862, dark and light, twice each")
    os.makedirs(CHROME, exist_ok=True)
    e2.CHROME = CHROME
    package = e2.write_package(
        "sharp", e2.project([e2.clip(2, 0, e2.GREY, None, name="Card")]))
    binary, error = e2.build_harness()
    if error:
        for appearance in ("dark", "light"):
            for row_name in HARNESS_ROWS:
                check(f"{appearance}: {row_name}", False, error)
        return
    for appearance in ("dark", "light"):
        paths = []
        for tag in ("a", "b"):
            out, error = render(binary, package, os.path.join(CHROME, f"{appearance}-{tag}.png"),
                                appearance)
            paths.append(out)
            if error:
                print(f"      {appearance}-{tag}: {error}")
        name = f"{appearance}: "
        if None in paths:
            for row_name in HARNESS_ROWS:
                check(name + row_name, False, "a render failed")
            continue
        with open(paths[0], "rb") as fa, open(paths[1], "rb") as fb:
            check(name + HARNESS_ROWS[0], fa.read() == fb.read())
        image = e2.Image(paths[0])
        s = image.scale
        print(f"      {appearance}: {image.width}×{image.height} px, scale {s:g}")
        corner = px(image, EXPORT_RIGHT - 1 / s, EXPORT_TOP)
        edge = px(image, EXPORT_RIGHT - 1 / s, EXPORT_MID)
        toolbar = px(image, EXPORT_RIGHT + 5, EXPORT_TOP)
        check(name + HARNESS_ROWS[1], corner == edge and corner != toolbar,
              f"corner {corner[:3]}, edge {edge[:3]}, toolbar {toolbar[:3]}")
        corner = px(image, SML_LEFT, SML_TOP)
        top_edge = px(image, SML_LEFT + 13, SML_TOP)
        bar = px(image, SML_LEFT - 2, SML_TOP)
        check(name + HARNESS_ROWS[2], corner == top_edge and corner != bar,
              f"corner {corner[:3]}, top edge {top_edge[:3]}, bar {bar[:3]}")
        k = int(round(s))
        diagonal = [pixel(image, int(CLIP_X0 * s) + i, int(STRIP_Y * s) + i) for i in range(4)]
        border = px(image, CLIP_X0 + 8, STRIP_Y)
        lane = px(image, CLIP_X0 + 8, STRIP_Y - 1)
        print(f"      clip corner D_0…D_3 {[d[:3] for d in diagonal]}, "
              f"E {border[:3]}, L {lane[:3]}")
        check(name + HARNESS_ROWS[3], diagonal[0] != border)
        check(name + HARNESS_ROWS[4], diagonal[k - 1] != lane)
        slider_rows(image, appearance)


def main():
    print("Sharp chrome — square corners, a 2 pt clip, the block slider knob")
    probe_checks()
    harness_checks()


if __name__ == "__main__":
    try:
        main()
    finally:
        passed = sum(1 for r in RESULTS if r)
        print()
        print(f"{passed}/{len(RESULTS)} checks passed")
        if passed != len(RESULTS):
            sys.exit(1)
