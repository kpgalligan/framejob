#!/usr/bin/env python3
"""Road map 2, phase 6 (Looks) — the CHROME half of the proof.

**Nothing about a PICTURE is claimed here, and nothing can be.** Phase 6's
two features are a blend mode and a gradient, and both of them are pixels:
the blend is `Compositor.metal`'s `blendPremultiplied`, which
`tools/proof/harness/build.sh` never compiles at all (it is a swiftc line
over `app/Sources`, and the shader is a Metal source file the app builds),
and the gradient is `LayerRenderers.renderShape`'s `CGGradient`, which lands
in a texture the preview well would draw — and the preview well renders
BLACK offscreen, because a Metal layer has no drawable. So the eight blend
formulas, the 64/192/255 arithmetic, the linear and radial ramps and the two
background commands' plates all belong to `tools/proof/phase6_proof.py`,
which drives a running app over MCP and compares `render_frame` PNGs. This
script photographs the CHROME around them, which is the half no MCP call can
see: the Video pane's Blend row, the Shape pane's Gradient section, and the
Clip menu.

That split is phase 3's and phase 4's, read again — those scripts say the
same sentence about the candidate wash and the caption reveal — and it is
worth restating because the temptation here is larger. A gradient IS a
picture, and the section that edits it is not.

What is claimed, section by section:

    2  the **Blend popup** exists in the Transform section, is bound to
       `video.blend`, and is the row directly below Opacity — measured as
       row arithmetic against `DS.controlHeight` and
       `InspectorMetrics.rowSpacing`, and as eight distinct drawings, one
       per mode.
    3  the **note** `VideoPane.blendNote` computes: it appears for a
       non-normal mode over a black canvas with nothing behind, and each of
       the two things that should suppress it does (a non-black canvas, a
       visible clip on a track behind), while the two that should NOT —
       a HIDDEN track behind, a clip behind with its video switched off —
       leave it standing.
    4  the **Gradient section** exists under its own id, below Fill, closed
       by the design, and is exactly as many rows tall as it has stops —
       measured as how far it pushes the sections under it down, against a
       header located by three shut renders whose summaries disagree.
    5  its rows are **DISABLED for `line` and `arrow`** — solved out of the
       pixels as the 0.42 alpha `InspectorPane` writes, never assumed — and
       the row LABELS are not, which is the difference between a disabled
       control and a disabled row.
    6  the **Angle row is disabled for `radial`** with its number unchanged,
       which one alpha over one aligned pair says in a single measurement.
    7  the **two Clip-menu items** exist, Add Background is a SUBMENU of
       two, neither takes a key equivalent, and the validator arm added to
       `EditorViewController` answers correctly for four selections.

**No rectangle in the gradient half is written down.** The section's header
is located by diffing three SHUT renders whose summaries differ — a shut
section draws nothing but its header, so the pixels that move are inside one
and the intersection of the three pins it. Its rows are located by a second
fixture that moves the Angle and nothing else, and the two answers are then
checked AGAINST each other: the Angle row must sit exactly one header, one
content inset and two row pitches below the header the summaries found. What
is left is an interval narrower than a row, and every rectangle below is
built as an INNER band from its two ends, so it lies inside the row it names
wherever in that interval the row really begins. Every body height is solved
from how far the sections under it moved, and section 4 scores the MARGIN of
that solve as a check of its own — because a shift that wins by two
mismatched rows out of four hundred is not a measurement, and at the window
height this script was first written at, every one of them was exactly that.
The only geometry asserted rather than derived is six rows of
`InspectorSection`'s own arithmetic.

**Colours are SOLVED, never hard-coded.** A harness PNG carries the
display's ICC profile (Display P3 primaries with an sRGB transfer on this
Mac), so a check that asserted a DS token's literal RGB would pass here and
fail on another machine — and `DS.accent`, which the note is drawn in, is
`NSColor.controlAccentColor`, which the person at the machine chooses in
System Settings. So section 5 and section 6 measure the background and the
enabled ink in the very renders they are comparing and solve

    disabled = background + alpha x (enabled - background)

for `alpha`, per component, over every pixel the two renders disagree
about. `phase3_chrome.py` solves for the candidate wash's 0.24 the same way,
against two different backgrounds in one render; here the two renders are of
two packages — one shape kind each — read against each other at a vertical
offset this file MEASURED (a `line`'s section carries a note row a
rectangle's does not, so its rows sit exactly that far lower, and the proof
that the offset is right is that the label column comes back byte-identical
under it). The answer is 0.42, `InspectorPane`'s own constant, solved twice
from two different pairs, and nothing in this file spells a colour.

**Section 7 needs an instrument this file builds**, and it is declared here
rather than buried: a menu lives in `NSApp.mainMenu` and is never drawn into
a window, so the harness — which renders a window — cannot photograph one at
any size. `AppDelegate.buildMainMenu()` is private and reachable only
through `applicationWillFinishLaunching`, and the app is the only other
caller. So this script writes a `main.swift` of fifty lines, compiles it
against `app/Sources` with `harness/build.sh`'s own swiftc line, and reads
the menu the delegate actually builds — plus the answers
`EditorViewController.validateUserInterfaceItem` gives for the three new
selectors over four selections. `phase5_chrome.py` established the shape (it
compiles a probe out of `app/Sources/Loudness.swift` alone, for the same
reason: no other caller a script can reach); this one differs in compiling
the whole module, because a menu item names a selector on the editor and the
delegate names every other class in the app. It is CACHED on modification
times like the harness is, and a build it cannot make is a scored FAILURE
rather than an exit, so a rotted instrument cannot take the rest of the
score down with it.

What is NOT claimed, and why:

  - **the popup's LIST.** A closed `NSPopUpButton` draws the selected item's
    title and nothing else, and a menu cannot be opened offscreen. So the
    eight rows are proved here only as eight distinct drawings of one row —
    that the popup is built over `BlendMode.allCases` in the enum's order,
    and that the order is the shader's discriminant, is
    `phase6_proof.py`'s and the core's.
  - **which verb the note uses.** `blendNote` says "reads black here" for
    the three modes that collapse against black and "changes nothing here"
    for the four that are the identity there. Reading that off a PNG needs
    OCR; what is measured instead is that the seven notes are seven
    different drawings, so the sentence names the mode rather than standing
    still.
  - **anything a gradient or a blend looks like.** See the first paragraph.

Run it from anywhere; it builds the harness and the probe if they are stale:

    python3 tools/proof/phase6_chrome.py

The last line is `<n>/<n> checks passed` and the exit status is non-zero if
any failed. The PNGs stay in `tools/proof/work/chrome6/`, with a crop of the
Transform and Gradient sections out of the interesting renders for an eye
check, and every comparison's changed pixels are printed as bounding boxes
so a reader can see where a diff landed without opening anything.
"""

import json
import os
import re
import struct
import subprocess
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work")
CHROME = os.path.join(WORK, "chrome6")
BUILD = os.path.join(HERE, "harness", "build.sh")
PROBE = os.path.join(WORK, "menuprobe")

# ---------------------------------------------------------------------------
# Geometry, in POINTS, from the app's layout constants. Each number names the
# Swift constant it mirrors; the PNG's width / WIDTH is the backing scale
# (2 on a Retina Mac).

WIDTH = 1440
# The blend fixtures' window. A shape clip's section stack OVERFLOWS the
# inspector's scroll view at this height, which is the property phase 4 paid
# for the hard way (its `SHAPE_HEIGHT` note): a stack with slack hands it to
# whichever section will stretch, and a render that is stable within a
# process and different across processes is an Auto Layout ambiguity. Both
# blend sections read the Transform group, which is the first section under
# the header, so nothing here needs a taller window.
HEIGHT = 862
# The gradient fixtures' window, and the number in this file that was most
# expensive to get right. Gradient's header sits at y 567 pt and its open
# body is up to 235 pt, so the panel has to hold the body AND leave a band
# below it: every body height here is solved from HOW FAR DOWN the sections
# under it moved, and a shift cannot be measured against content that was
# pushed off the bottom of the pane. Three heights were rendered and
# measured before this one was picked:
#
#   1100  the open body reaches y 795 and the panel ends at 800, so five
#         points of band are left and the winning shift beats the runner-up
#         by two mismatched rows out of 390. It answered 177 pt for two
#         stops (right) and 61 pt for a stop (wrong: it is 29). A margin
#         that thin is not a measurement.
#   1300  the SHUT stack fits the pane and the OPEN one does not, so opening
#         the section relays out the whole panel: measured, the diff reaches
#         the section headers ABOVE Gradient (y 82 pt, four sections up) and
#         no shift matches anywhere.
#   1400  both states have slack, nothing above the section moves, and every
#         fixture's winning shift is exact — 2 mismatched rows out of 490,
#         against a runner-up 120 rows worse. Section 4 SCORES that margin
#         rather than trusting it.
#
# It is 1600 since road map 5's E2 put a shut Motion header after Obscure: at
# 1400 the four-stop fixture's OPEN stack no longer fitted the pane and relaid
# out the panel (grad-4 495/495, 68/70). This used to add that "1600 measures
# identically to 1400, which is what says the number is a threshold and not a
# resonance"; E2 made that false, and the E2 reader review (road map 5 §12,
# N·4) took the sentence out rather than leave a claim no run backs. What
# would earn it back is a render of one fixture at TALL + 200 whose solved
# body height equals TALL's, scored as a row of its own.
TALL = 1600
# The band under the section starts this far below its header. It must clear
# the tallest body any fixture here has (235 pt, four stops) or the
# measurement would be reading the section against itself — section 4 scores
# that too, rather than leaving it as a comment.
BODY_MAX = 250
# What "an exact shift" means, in IMAGE rows of the band. The winner may
# leave a few rows unexplained — the band's own top edge straddles a row of
# antialiasing at every offset — and the runner-up must be far worse, which
# is the half that says a number was MEASURED and not merely preferred.
SHIFT_SLOP = 4
SHIFT_MARGIN = 40

TOOLBAR = 44             # DS.toolbarHeight
TAB = 32                 # DS.tabHeight — the inspector's tab strip
INSPECTOR_W = 304        # DS.panelWidth = EditorViewController.defaultInspectorWidth
TIMELINE_H = 300         # EditorViewController.defaultTimelineHeight
SCROLLER_W = 16          # AppKit's legacy scroller, pinned by the harness

SECTION_HEADER_H = 28    # InspectorMetrics.headerHeight
CONTROL_H = 22           # DS.controlHeight — one row
ROW_SPACING = 7          # InspectorMetrics.rowSpacing
CONTENT_TOP = 2          # InspectorSection's content edgeInsets.top
CONTENT_BOTTOM = 8       # …and .bottom
INSET = 10               # InspectorMetrics.inset — the content stack's sides
LABEL_W = 76             # InspectorMetrics.labelWidth
ROW_PITCH = CONTROL_H + ROW_SPACING          # 29

# The alpha every disabled control in the inspector is drawn at. It is
# written `alphaValue = enabled() ? 1 : 0.42` three times in
# `InspectorPane.swift` and eight in `OptionControls.swift` (a ninth spends
# it as a segment's tint), and sections 5 and 6 SOLVE for it out of the
# pixels rather than reading a colour off a token.
DISABLED_ALPHA = 0.42

INSPECTOR_X = WIDTH - INSPECTOR_W                        # 1136
# The label column and the control columns of a row, from the content
# stack's insets. A disabled ROW would dim both; a disabled control dims only
# the second, which is what section 5 measures.
LABEL_X0 = INSPECTOR_X + INSET                           # 1146
LABEL_X1 = LABEL_X0 + LABEL_W                            # 1222
CONTROL_X1 = INSPECTOR_X + INSPECTOR_W - INSET - SCROLLER_W

# The section ids, as their Swift files spell them. That both sides spell the
# same string is half of what sections 4 and 6 prove: a section under any
# other id would not open when the harness pins this one.
GRADIENT_ID = "shape.gradient"            # ShapePane.gradientSection
FILL_ID = "shape.fill"                    # ShapePane.fillSection
ABSENT_ID = GRADIENT_ID + ".nope"         # an id no section has

# The Transform section's rows, in `VideoPane.transformSection`'s order. The
# Blend popup is the LAST value row, immediately below Opacity, and the two
# Fit/Fill buttons follow it.
TRANSFORM_ROWS = ["Scale", "Position X", "Position Y", "Rotation", "Opacity", "Blend"]
OPACITY_ROW = TRANSFORM_ROWS.index("Opacity")
BLEND_ROW = TRANSFORM_ROWS.index("Blend")

# `BlendMode` in declaration order (`ProjectSnapshot.swift`, and
# `model_props.rs` beside it). The ORDER is the shader's discriminant and is
# a core claim; here the list is only what the eight fixtures are named for.
BLEND_MODES = [
    "normal", "multiply", "screen", "add", "overlay", "darken", "lighten", "difference",
]
# The three that collapse to black over the default canvas, and so take
# `blendNote`'s other verb. Not readable off a PNG (see the header); listed
# because the fixtures are named for it and a reader will look for it.
COLLAPSING = {"multiply", "darken", "overlay"}

# The Gradient section's rows with a gradient ON, in `gradientSection`'s
# order: the switch, the kind, the angle, one row per stop, and the Add Stop
# button row. A note, when the section has one, is the row ABOVE all of them
# (`InspectorSection.init` adds it first).
GRADIENT_FIXED_ROWS = 3          # Gradient, Kind, Angle
GRADIENT_TRAILING_ROWS = 1       # Add Stop

# ---------------------------------------------------------------------------
# Packages, by hand (spec §5.2). A `.reelcut` is a directory holding a
# `project.json`, so nothing here loads asynchronously and every render is
# deterministic — and the fixtures are SHAPE clips with no media at all,
# which is `phase6_proof.py`'s choice too and for the same reason: a shape
# clip gets the Transform section (so the Blend row) AND the shape sections
# (so the Gradient one), and there is nothing to decode.

TICKS_PER_SECOND = 600_000
CLIP_SECONDS = 5

BLACK = [0.0, 0.0, 0.0, 1.0]
WHITE = [1.0, 1.0, 1.0, 1.0]


def video_props(blend="normal", opacity=1.0):
    """`VideoProps` in the core's field order (`model_props.rs`), with
    `blend` LAST — where format version 6 appended it."""
    return {
        "x": 0.0, "y": 0.0, "scale": 1.0, "rotation": 0.0, "opacity": opacity,
        "crop": {"l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0},
        "corner_radius": 0.0, "shadow": None,
        "color": {"brightness": 0.0, "contrast": 0.0, "saturation": 0.0, "hue": 0.0},
        "chroma": None, "filters": [], "reflection": None, "spotlight": None,
        "obscure": [], "blend": blend,
    }


def ramp(stops):
    """`stops` evenly spaced from black to white — the shape of
    `Gradient::default()`, extended. The COLOURS are not a claim anywhere
    below; what matters is that there are `stops` of them."""
    return [
        {"at": i / (stops - 1), "color": [i / (stops - 1)] * 3 + [1.0]}
        for i in range(stops)
    ]


def gradient(stops=2, kind="linear", angle=0.0):
    return {"kind": kind, "stops": ramp(stops), "angle": angle}


def shape_props(kind="rectangle", grad=None, fill=None):
    """`ShapeProps` in the core's field order, with `gradient` LAST."""
    return {
        "kind": kind, "width": 320.0, "height": 120.0,
        "stroke": {"width": 6.0, "color": [1.0, 1.0, 1.0, 1.0]}, "fill": fill,
        "arrow_start": False, "arrow_end": False, "radius": 0.0,
        "from": [0.0, 1.0], "to": [1.0, 0.0], "gradient": grad,
    }


def text_props():
    return {
        "content": "Hello", "font": "SourceSans3-SemiBold", "size": 72.0,
        "color": [1.0, 1.0, 1.0, 1.0], "align": "center", "valign": "middle",
        "line_spacing": 1.0, "tracking": 0.0, "outline": None, "backdrop": None,
        "width": None, "animation": None,
    }


def clip(cid, track, start, source="shape", **props):
    body = {
        "id": cid, "track": track, "start": start,
        "duration": CLIP_SECONDS * TICKS_PER_SECOND,
        "source": {"kind": source},
        "enabled": {"video": props.pop("video_on", True), "audio": True},
        "speed": 1.0,
        "video": video_props(props.pop("blend", "normal"), props.pop("opacity", 1.0)),
        "audio": None,
        "text": text_props() if source == "text" else None,
        "shape": None if source == "text" else shape_props(
            props.pop("kind", "rectangle"), props.pop("grad", None), props.pop("fill", None)),
        "actions": [], "transition_in": None,
        "name": None, "label": None,
    }
    assert not props, f"unread package keys: {sorted(props)}"
    return body


def project_json(
    version=6, background=None, behind=None, hidden=False, behind_video=True, **clip_kw
):
    """One shape (or text) clip on one track, plus an optional clip on a
    track BEHIND it — the fixture `VideoPane.hasVisibleLayerBehind` is asked
    about. The front clip starts a second in so that START ORDER, which is
    how the harness's `selectIndex` picks, is unambiguous: Swift's sort is
    not documented stable and two clips at 0 would have no defined order."""
    # Ids are unique across the WHOLE project — `next_id` is one counter — so
    # the tracks take the low numbers and the clips follow them.
    tracks = [
        {"id": 1, "name": "Track 1", "hidden": False, "muted": False, "locked": False,
         "solo": False}
    ]
    clips = []
    front_track, front_start = 1, 0
    if behind:
        tracks[0]["hidden"] = hidden
        tracks.append({"id": 2, "name": "Track 2", "hidden": False, "muted": False,
                       "locked": False, "solo": False})
        clips.append(clip(3, 1, 0, video_on=behind_video))
        front_track, front_start = 2, TICKS_PER_SECOND
    clips.append(clip(len(tracks) + len(clips) + 1, front_track, front_start, **clip_kw))
    if version < 6:
        # A version-5 file has neither key: `blend` and `gradient` are what
        # version 6 appended, and both default, so this must open and read
        # `normal` and `null` with no migrate step.
        for one in clips:
            one["video"].pop("blend", None)
            if one["shape"] is not None:
                one["shape"].pop("gradient", None)
    return {
        "version": version,
        "canvas": {
            "width": 1920, "height": 1080, "fps": [30, 1],
            "background": background or BLACK, "fit_new_clips": True,
            "timecode_frames": True,
        },
        "media": [],
        "tracks": tracks,
        "clips": sorted(clips, key=lambda c: c["start"]),
        "markers": [],
        "next_id": len(tracks) + len(clips) + 1,
        "nests": [],
    }


# Every package this script renders, and what it is for. The name is the
# render tag, so a reader who wants to look at one knows which PNG it is.
PACKAGES = {
    # 2 — the Blend row. A WHITE canvas, so `blendNote` never fires and the
    # only thing a mode can change is the row itself.
    **{f"blend-{mode}": dict(background=WHITE, blend=mode) for mode in BLEND_MODES},
    "blend-opacity": dict(background=WHITE, opacity=0.9),
    "blend-v5": dict(background=WHITE, version=5),
    # 3 — the note. A BLACK canvas, which is the default and the trap.
    **{f"note-{mode}": dict(background=BLACK, blend=mode) for mode in BLEND_MODES},
    "note-behind-normal": dict(background=BLACK, behind=True),
    "note-behind-multiply": dict(background=BLACK, behind=True, blend="multiply"),
    # A HIDDEN track behind draws nothing, so the note must come back…
    "note-hidden-multiply": dict(
        background=BLACK, behind=True, hidden=True, blend="multiply"),
    # …and so must a clip behind whose video is switched off.
    "note-off-multiply": dict(
        background=BLACK, behind=True, behind_video=False, blend="multiply"),
    # 4, 5, 6 — the Gradient section.
    "grad-2": dict(grad=gradient(2)),
    "grad-3": dict(grad=gradient(3)),
    "grad-4": dict(grad=gradient(4)),
    "grad-off": dict(grad=None),
    "grad-fill": dict(grad=gradient(2), fill=[0.2, 0.4, 0.8, 1.0]),
    "grad-radial": dict(grad=gradient(2, kind="radial")),
    "grad-ellipse": dict(kind="ellipse", grad=gradient(2)),
    "grad-line": dict(kind="line", grad=gradient(2)),
    "grad-arrow": dict(kind="arrow", grad=gradient(2)),
    "grad-line-fill": dict(kind="line", grad=gradient(2), fill=[0.2, 0.4, 0.8, 1.0]),
    # The row-grid locator. It differs from `grad-2` in the Angle alone, so
    # the pixels it changes ARE the Angle row and nothing else — which is
    # what lets section 6 solve an alpha over a row it has measured rather
    # than over one it has computed. Rendered OPEN only.
    "grad-angle": dict(grad=gradient(2, angle=45.0)),
    # Three stops, so every Remove button is LIVE: with two the floor rule
    # (`list().count > 2`) disables Remove on both sides of the pair and its
    # pixels would solve for an alpha of 1 inside a region claiming 0.42.
    "grad-3-line": dict(kind="line", grad=gradient(3)),
    # A TEXT clip gets no shape sections at all, so it must not get this one.
    "text-clip": dict(source="text"),
}

# Fixtures that exist only to be diffed against another OPEN render, so the
# shut half would be a render and a decode spent on nothing.
OPEN_ONLY = {"grad-angle"}


def write_package(name, spec):
    path = os.path.join(WORK, "p6-" + name + ".reelcut")
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "project.json"), "w") as f:
        json.dump(project_json(**spec), f, indent=2)
        f.write("\n")
    return path


# ---------------------------------------------------------------------------
# The harness.

WARNINGS = []


def build_harness():
    start = time.time()
    result = subprocess.run([BUILD], capture_output=True, text=True)
    elapsed = time.time() - start
    if result.returncode != 0:
        sys.stderr.write(result.stdout + result.stderr)
        sys.exit("harness build failed")
    binary = result.stdout.strip().splitlines()[-1]
    built = "built" in result.stderr
    print(f"harness: {binary} ({'built in %.1f s' % elapsed if built else 'up to date'})")
    return binary


def render(binary, package, out, expand="-", height=HEIGHT, select=0):
    """One render, with the harness's arguments in the order every earlier
    chrome script depends on. `expandSections` is phase 3's argument and is
    used here for what it was built for — a section written
    `defaultExpanded: false` draws nothing but its header — so this script
    adds no instrument to the renderer at all."""
    args = [
        binary, package, out, "light", str(WIDTH), str(height), str(select), "0", "1",
        "clip", "-", expand,
    ]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        sys.stderr.write(result.stdout + result.stderr)
        sys.exit(f"render failed for {package}")
    # `Harness.png` writes one line to stderr when two consecutive captures
    # never came back equal — the layout was still moving when it gave up,
    # and every byte comparison below would then be measuring a race instead
    # of the feature. Collected rather than ignored, and reported as its own
    # check at the end.
    if result.stderr.strip():
        WARNINGS.append(f"{os.path.basename(out)}: {result.stderr.strip()}")
    return out


# ---------------------------------------------------------------------------
# The menu probe — the instrument this script builds, declared in the header.
#
# `AppDelegate.buildMainMenu()` is private and its one caller is
# `applicationWillFinishLaunching`, which the app runs at launch and the
# harness never does (it renders a window; a menu is not in one). So the probe
# is that call, plus a walk of `NSApp.mainMenu`, plus
# `EditorViewController.validateUserInterfaceItem` over a package opened from
# disk — which needs no window at all, since validation reads the document and
# the selection.

PROBE_SOURCE = r'''// Written by tools/proof/phase6_chrome.py. See that file's header.
import AppKit

let request = try! JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
// The one call that builds the menu: `buildMainMenu()` is private.
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

func dump(_ item: NSMenuItem) -> [String: Any] {
    var row: [String: Any] = [
        "title": item.title, "separator": item.isSeparatorItem,
        "action": item.action.map { NSStringFromSelector($0) } ?? "",
        "key": item.keyEquivalent, "modifiers": item.keyEquivalentModifierMask.rawValue,
    ]
    if let sub = item.submenu {
        row["submenu"] = ["title": sub.title, "items": sub.items.map(dump)]
    }
    return row
}
var answer: [String: Any] = [
    "menu": ["title": NSApp.mainMenu?.title ?? "",
             "items": (NSApp.mainMenu?.items ?? []).map(dump)]
]
var validations: [[String: Any]] = []
for probe in request["validate"] as? [[String: Any]] ?? [] {
    let document = ProjectDocument()
    try! document.read(
        from: URL(fileURLWithPath: probe["package"] as! String),
        ofType: "com.kgalligan.reelcut-project")
    let clips = document.project.snapshot.clips.sorted { $0.start < $1.start }
    document.selection = Set((probe["select"] as? [Int] ?? []).compactMap {
        clips.indices.contains($0) ? clips[$0].id : nil })
    let controller = EditorViewController(document: document)
    var enabled: [String: Bool] = [:]
    for name in probe["selectors"] as? [String] ?? [] {
        let item = NSMenuItem(title: name, action: NSSelectorFromString(name), keyEquivalent: "")
        enabled[name] = controller.validateUserInterfaceItem(item)
    }
    validations.append(["name": probe["name"] as! String, "enabled": enabled])
}
answer["validation"] = validations
try! JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
    .write(to: out)
exit(0)
'''


def build_probe():
    """Compile the probe if it is stale, exactly as `harness/build.sh` does —
    the same swiftc line, the same staleness rule (the binary must be newer
    than every source, the probe's own main and the staticlib). Returns the
    binary's path, or None with the reason, which section 7 scores as a
    FAILURE rather than exiting: an instrument that will not build must not
    take the rest of the score with it."""
    os.makedirs(PROBE, exist_ok=True)
    binary = os.path.join(PROBE, "menuprobe")
    entry = os.path.join(PROBE, "main.swift")
    # Written only when it CHANGED, or the staleness check below would
    # rebuild on every run.
    if not os.path.exists(entry) or open(entry).read() != PROBE_SOURCE:
        with open(entry, "w") as f:
            f.write(PROBE_SOURCE)
    sources = sorted(
        os.path.join(ROOT, "app", "Sources", name)
        for name in os.listdir(os.path.join(ROOT, "app", "Sources"))
        if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    if os.path.exists(binary) and all(
        os.path.getmtime(f) < os.path.getmtime(binary) for f in sources + [entry, lib]
    ):
        print(f"menu probe: {binary} (up to date)")
        return binary, None
    sdk = subprocess.run(
        ["xcrun", "--show-sdk-path", "--sdk", "macosx"], capture_output=True, text=True
    ).stdout.strip()
    start = time.time()
    result = subprocess.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos15.0", "-module-name", "Reelcut",
         "-import-objc-header", os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
         "-L", os.path.dirname(lib), "-lreelcut_core"] + sources + [entry, "-o", binary],
        capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(binary):
        errors = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    print(f"menu probe: {binary} (built in {time.time() - start:.1f} s)")
    return binary, None


def run_probe(binary, cases):
    request = os.path.join(CHROME, "menu-request.json")
    out = os.path.join(CHROME, "menu.json")
    with open(request, "w") as f:
        json.dump({"validate": cases}, f, indent=2)
    result = subprocess.run([binary, request, out], capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stdout + result.stderr).strip()[:400]
    with open(out) as f:
        return json.load(f), None


# ---------------------------------------------------------------------------
# PNG, in pure Python: chunks, zlib, the five filters. (phase4_chrome.py's,
# unchanged — every chrome script carries its own copy so one can be run
# without the others.)

def decode_png(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"{path} is not a PNG")
    pos, idat, header = 8, [], None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    width, height, depth, colour, _, _, interlace = header
    if depth != 8 or interlace != 0:
        sys.exit(f"{path}: only 8-bit non-interlaced PNGs are decoded here")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[colour]
    raw = zlib.decompress(b"".join(idat))
    stride = width * channels
    bpp = channels
    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(height):
        kind = raw[pos]
        cur = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if kind == 1:
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i - bpp]) & 255
        elif kind == 2:
            for i in range(stride):
                cur[i] = (cur[i] + prev[i]) & 255
        elif kind == 3:
            for i in range(bpp):
                cur[i] = (cur[i] + (prev[i] >> 1)) & 255
            for i in range(bpp, stride):
                cur[i] = (cur[i] + ((cur[i - bpp] + prev[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(bpp):
                cur[i] = (cur[i] + prev[i]) & 255
            for i in range(bpp, stride):
                a, b, c = cur[i - bpp], prev[i], prev[i - bpp]
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                if pa <= pb and pa <= pc:
                    pred = a
                elif pb <= pc:
                    pred = b
                else:
                    pred = c
                cur[i] = (cur[i] + pred) & 255
        elif kind != 0:
            sys.exit(f"{path}: unknown filter {kind}")
        rows.append(bytes(cur))
        prev = cur
    return width, height, channels, rows


def encode_png(width, height, channels, rows):
    """Filter-0 rows, for the crops written beside the renders."""
    colour = {1: 0, 2: 4, 3: 2, 4: 6}[channels]
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(
            ">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, colour, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


class Rect:
    def __init__(self, name, x, y, w, h):
        self.name, self.x0, self.y0, self.x1, self.y1 = name, x, y, x + w, y + h

    def contains(self, x, y, scale, slop=0):
        return (self.x0 - slop) * scale <= x < (self.x1 + slop) * scale \
            and (self.y0 - slop) * scale <= y < (self.y1 + slop) * scale

    def __str__(self):
        return f"{self.name} x {self.x0:g}–{self.x1:g} y {self.y0:g}–{self.y1:g} pt"


class Image:
    def __init__(self, path):
        self.path = path
        self.width, self.height, self.channels, self.rows = decode_png(path)
        self.scale = self.width / WIDTH

    def pixel(self, x, y):
        row = self.rows[y]
        return tuple(row[x * self.channels:(x + 1) * self.channels])

    def crop(self, rect, out):
        s = self.scale
        x0, x1 = int(rect.x0 * s), int(rect.x1 * s)
        y0, y1 = max(int(rect.y0 * s), 0), min(int(rect.y1 * s), self.height)
        rows = [row[x0 * self.channels:x1 * self.channels] for row in self.rows[y0:y1]]
        with open(out, "wb") as f:
            f.write(encode_png(x1 - x0, y1 - y0, self.channels, rows))


class LazyImages:
    """`tag -> Image`, decoded on first use and kept."""

    def __init__(self, renders):
        self.renders = renders
        self.cache = {}

    def __getitem__(self, tag):
        if tag not in self.cache:
            self.cache[tag] = Image(self.renders[tag])
        return self.cache[tag]

    def __len__(self):
        return len(self.renders)


def changed_pixels(a, b):
    """Every (x, y) whose bytes differ, found by XOR-ing whole rows."""
    if (a.width, a.height, a.channels) != (b.width, b.height, b.channels):
        sys.exit(f"{a.path} and {b.path} differ in shape")
    out = []
    ch = a.channels
    for y, (ra, rb) in enumerate(zip(a.rows, b.rows)):
        if ra == rb:
            continue
        x = int.from_bytes(ra, "big") ^ int.from_bytes(rb, "big")
        xb = x.to_bytes(len(ra), "big")
        for m in re.finditer(rb"[^\x00]+", xb):
            for px in range(m.start() // ch, (m.end() - 1) // ch + 1):
                out.append((px, y))
    return out


def clusters(pixels, cell=12):
    """Bounding boxes of changed pixels grouped within `cell` px of each other."""
    buckets = {}
    for x, y in pixels:
        buckets.setdefault((x // cell, y // cell), []).append((x, y))
    parent = {k: k for k in buckets}

    def find(k):
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    for cx, cy in buckets:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                n = (cx + dx, cy + dy)
                if n in buckets:
                    parent[find(n)] = find((cx, cy))
    groups = {}
    for k, pts in buckets.items():
        groups.setdefault(find(k), []).extend(pts)
    boxes = []
    for pts in groups.values():
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        boxes.append((min(xs), min(ys), max(xs), max(ys), len(pts)))
    return sorted(boxes, key=lambda b: (b[1], b[0]))


def describe(boxes, scale, limit=12):
    lines = []
    for x0, y0, x1, y1, n in boxes[:limit]:
        lines.append(
            f"      x {x0}–{x1} y {y0}–{y1} px  = x {x0 / scale:.1f}–{(x1 + 1) / scale:.1f}"
            f" y {y0 / scale:.1f}–{(y1 + 1) / scale:.1f} pt  ({n} px)")
    if len(boxes) > limit:
        lines.append(f"      … and {len(boxes) - limit} more clusters")
    return "\n".join(lines)


def inside(pixels, rect, scale, slop=0):
    return [p for p in pixels if rect.contains(p[0], p[1], scale, slop)]


def outside(pixels, rects, scale, slop=0):
    return [p for p in pixels if not any(r.contains(p[0], p[1], scale, slop) for r in rects)]


def extent(pixels, scale):
    """(top, bottom) of a changed set in points, or (None, None) when empty.

    Never a `guard` at a call site: a check that quietly disappears when its
    diff comes back empty is a check that cannot fail, so every caller here
    reports the empty case as a FAIL and the score stays the same length.
    """
    if not pixels:
        return None, None
    ys = [y for _, y in pixels]
    return min(ys) / scale, (max(ys) + 1) / scale


def shift_match(top, bottom, band, limit=260):
    """How far DOWN `bottom` is `top`, measured over `band`.

    With the section stack overflowing its scroll view there is no spare
    height to redistribute, so opening a section can only push what is under
    it down. This walks every whole-point shift and counts the rows of `band`
    that do not match; the winner is the growth, in points. (phase4_chrome's,
    with a wider limit — a gradient of four stops is a taller body than an
    animation's three rows.)
    """
    scale = bottom.scale
    ch = bottom.channels
    x0, x1 = int(band.x0 * scale) * ch, int(band.x1 * scale) * ch
    y0, y1 = int(band.y0 * scale), int(band.y1 * scale)
    scores = []
    for points in range(limit):
        offset = int(points * scale)
        if y0 - offset < 0:
            break
        mismatch = sum(
            1 for y in range(y0, y1)
            if bottom.rows[y][x0:x1] != top.rows[y - offset][x0:x1])
        scores.append((mismatch, points))
    scores.sort()
    return scores


# ---------------------------------------------------------------------------
# Solving for the disabled alpha.
#
# A control the inspector has switched off is the SAME drawing composited at
# `alphaValue`, so for every pixel of it
#
#     disabled = background + alpha x (enabled - background)
#
# holds per component, exactly, up to the 8-bit rounding at each end. The
# background is measured in the very renders being compared (the modal pixel
# of the band — the inspector's pane fill), and the enabled ink is measured
# too, so no colour is written down anywhere: what comes out is a NUMBER, and
# the number is `InspectorPane`'s 0.42.
#
# The two halves are `paired_pixels` (which reads one render against another,
# with the measured note-row offset between them) and `solve_alpha`, above.

def modal_pixel(image, rect):
    """The most common pixel in `rect` — the pane fill, whatever this
    machine's profile encodes it as."""
    counts = {}
    s, ch = image.scale, image.channels
    for y in range(int(rect.y0 * s), min(int(rect.y1 * s), image.height)):
        row = image.rows[y]
        for x in range(int(rect.x0 * s), int(rect.x1 * s)):
            px = row[x * ch:(x + 1) * ch]
            counts[px] = counts.get(px, 0) + 1
    if not counts:
        return None
    return tuple(max(counts.items(), key=lambda kv: kv[1])[0])


def paired_pixels(a, b, rect, dy=0):
    """Every `((x, y), pixel of a, pixel of b)` over `rect` in `a`'s frame,
    reading `b` `dy` POINTS further down.

    The offset is what lets a disabled section be compared against an enabled
    one that is not at the same y: a `line`'s Gradient section carries a note
    row a rectangle's does not, so its rows sit exactly that far lower. The
    offset is MEASURED (section 5 solves it out of the two body heights)
    rather than assumed, and section 5 scores the fact that with it applied
    the label column comes back byte-identical — which a wrong offset could
    not do."""
    s, ch = a.scale, a.channels
    off = int(round(dy * s))
    out = []
    for y in range(max(int(rect.y0 * s), 0), min(int(rect.y1 * s), a.height)):
        if not 0 <= y + off < b.height:
            continue
        ra, rb = a.rows[y], b.rows[y + off]
        for x in range(int(rect.x0 * s), int(rect.x1 * s)):
            out.append(((x, y), ra[x * ch:(x + 1) * ch], rb[x * ch:(x + 1) * ch]))
    return out


def differing(pairs):
    """The (x, y) of every pair whose two pixels are not the same bytes."""
    return [xy for xy, pa, pb in pairs if pa != pb]


def solve_alpha(pairs, background, floor=60):
    """Every alpha sample over `pairs`: `(b - bg) / (a - bg)` per component.

    Only components at least `floor` away from the background are sampled. An
    antialiased glyph edge a byte or two off the background solves for the
    same alpha in exact arithmetic but carries a rounding error of
    0.5/|a − bg|, which at |a − bg| = 4 is ±0.12 — noise that would swamp the
    answer."""
    samples = []
    for _, pa, pb in pairs:
        for c in range(min(3, len(pa))):
            span = pa[c] - background[c]
            if abs(span) < floor:
                continue
            samples.append((pb[c] - background[c]) / span)
    return samples


def summarise(samples):
    """(median, 1st percentile, 99th percentile, n) of an alpha solve."""
    if not samples:
        return None
    ordered = sorted(samples)
    n = len(ordered)
    return (ordered[n // 2], ordered[max(0, n // 100)], ordered[min(n - 1, n - n // 100)], n)


# ---------------------------------------------------------------------------
# The checks.

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append(bool(ok))
    print(f"  {'PASS' if ok else 'FAIL'}: {name}")
    if detail:
        print(detail if detail.startswith("      ") else "      " + detail)


def same_file(a, b):
    with open(a, "rb") as fa, open(b, "rb") as fb:
        return fa.read() == fb.read()


def identical(name, renders, images, a, b, scale):
    """Two renders that must be byte-identical, reported like phase 3's."""
    if same_file(renders[a], renders[b]):
        check(name, True)
        return
    diff = changed_pixels(images[a], images[b])
    check(name, not diff,
          ("the PNG bytes differ but every pixel is the same" if not diff else
           f"{len(diff)} pixels differ:\n" + describe(clusters(diff), scale)))


def report(images, a, b, what, scale, limit=10):
    """The changed pixels of one comparison, printed as clusters."""
    diff = changed_pixels(images[a], images[b])
    boxes = clusters(diff)
    print(f"\n   {what}: {len(diff)} changed pixels in {len(boxes)} clusters:")
    print(describe(boxes, scale, limit=limit))
    return diff, boxes


def origin_interval(band, offsets):
    """The values of a row's top edge R for which `band` (top, bottom) fits
    inside [R + lo, R + hi] — an interval, or None when the band is empty."""
    top, bottom = band
    if top is None:
        return None
    lo, hi = offsets
    return bottom - hi, top - lo


def intersect(intervals):
    lows = [i[0] for i in intervals if i]
    highs = [i[1] for i in intervals if i]
    if len(lows) != len(intervals) or not lows:
        return None
    return max(lows), min(highs)


def body_height(images, tag, band):
    """How much taller the pane is with a section OPEN, solved out of the
    pixels below it — which is the section's whole body, header excluded.

    Returns `(mismatched rows, points)` for the winner and the runner-up, so
    a caller can score the MARGIN. A shift that wins by two rows out of four
    hundred is not a measurement, and at the window height this script used
    to render at, that is exactly what every one of these was."""
    scores = shift_match(images[f"{tag}-shut"], images[f"{tag}-open"], band)
    return scores[0], scores[1]


# ---------------------------------------------------------------------------


def main():
    os.makedirs(CHROME, exist_ok=True)
    binary = build_harness()
    probe_binary, probe_error = build_probe()
    packages = {name: write_package(name, spec) for name, spec in PACKAGES.items()}
    print(f"packages: {len(packages)} written under {os.path.relpath(WORK, ROOT)}/")

    def png(tag):
        return os.path.join(CHROME, tag + ".png")

    start = time.time()
    renders = {}
    # The blend fixtures: one render each at the short window, where a shape
    # clip's section stack overflows.
    for name in list(PACKAGES):
        if name.startswith(("blend-", "note-")):
            select = 1 if PACKAGES[name].get("behind") else 0
            renders[name] = render(binary, packages[name], png(name), select=select)
    # …and one repeat, for section 1.
    renders["blend-normal-again"] = render(
        binary, packages["blend-normal"], png("blend-normal-again"))
    # The gradient fixtures: shut and open, at the tall window.
    for name in list(PACKAGES):
        if name.startswith("grad-") or name == "text-clip":
            if name not in OPEN_ONLY:
                renders[f"{name}-shut"] = render(
                    binary, packages[name], png(f"{name}-shut"), height=TALL)
            renders[f"{name}-open"] = render(
                binary, packages[name], png(f"{name}-open"), expand=GRADIENT_ID, height=TALL)
    renders["grad-2-open-again"] = render(
        binary, packages["grad-2"], png("grad-2-open-again"), expand=GRADIENT_ID, height=TALL)
    # The Fill section pinned instead, so section 4 can say WHERE Gradient
    # sits relative to it, and an id no section has, so it can say that the
    # pin is about THIS id.
    renders["grad-2-fillpin"] = render(
        binary, packages["grad-2"], png("grad-2-fillpin"), expand=FILL_ID, height=TALL)
    renders["grad-2-absent"] = render(
        binary, packages["grad-2"], png("grad-2-absent"), expand=ABSENT_ID, height=TALL)
    print(f"rendered {len(renders)} PNGs in {time.time() - start:.1f} s")

    start = time.time()
    # Decoded on first use, not up front: a 1440 x 1600 render is a
    # 2880 x 3200 PNG and this file's decoder is pure Python, so the renders
    # that are only ever compared BYTE for byte (`identical`, which reaches
    # for pixels only when the bytes already differ) are never decoded at all.
    images = LazyImages(renders)
    scale = images["blend-normal"].scale
    print(f"first decode in {time.time() - start:.1f} s; "
          f"{images['blend-normal'].width}x{images['blend-normal'].height} "
          f"{images['blend-normal'].channels}-channel, scale {scale:g}")

    inspector = Rect("inspector", INSPECTOR_X, TOOLBAR + TAB, INSPECTOR_W,
                     (HEIGHT - TIMELINE_H) - (TOOLBAR + TAB))
    tall_inspector = Rect("inspector", INSPECTOR_X, TOOLBAR + TAB, INSPECTOR_W,
                          (TALL - TIMELINE_H) - (TOOLBAR + TAB))
    print(f"   {inspector} (blend fixtures) · {tall_inspector} (gradient fixtures)")

    # 1. Determinism. Everything below is a comparison of two renders, so
    # this is asserted FIRST and the rest of the score means nothing without
    # it — at BOTH window heights, since a section stack with slack hands it
    # to whichever section will stretch and phase 4 lost a gate to exactly
    # that. A render that is stable within a process and different across
    # processes is an Auto Layout AMBIGUITY, never a race, and this pair is
    # what would say so: each of the two is a second process rendering the
    # package the checks below lean on hardest.
    print("\n1. determinism — one package rendered twice, in two processes")
    identical("the Transform fixture, twice → byte-identical PNGs", renders, images,
              "blend-normal", "blend-normal-again", scale)
    identical(f"the Gradient fixture with `{GRADIENT_ID}` pinned open, twice → byte-identical",
              renders, images, "grad-2-open", "grad-2-open-again", scale)

    # 2. The Blend row. The canvas is WHITE in every fixture here, so
    # `blendNote` never fires (section 3 is where that is proved) and the
    # only thing a mode can move is its own row.
    print("\n2. the Blend popup — Transform's last value row, under Opacity")
    opacity_diff, _ = report(
        images, "blend-normal", "blend-opacity", "Opacity 100% vs 90%", scale)
    blend_diff, _ = report(
        images, "blend-normal", "blend-multiply", "Blend normal vs multiply", scale)
    check("dialling Opacity moves pixels", bool(opacity_diff))
    check("choosing a blend mode moves pixels", bool(blend_diff))
    for name, diff in (("Opacity", opacity_diff), ("Blend", blend_diff)):
        stray = outside(diff, [inspector], scale)
        check(f"every pixel the {name} row changed is inside the inspector",
              bool(diff) and not stray,
              "" if not stray else f"{len(stray)} px elsewhere:\n"
              + describe(clusters(stray), scale))
    opacity_band = extent(opacity_diff, scale)
    blend_band = extent(blend_diff, scale)
    print(f"      Opacity ink y {opacity_band[0]}–{opacity_band[1]} pt · "
          f"Blend ink y {blend_band[0]}–{blend_band[1]} pt")
    for name, band in (("Opacity", opacity_band), ("Blend", blend_band)):
        check(f"the {name} row's ink fits inside one row (DS.controlHeight {CONTROL_H} pt)",
              band[0] is not None and band[1] - band[0] <= CONTROL_H,
              f"{band[1] - band[0]:g} pt tall" if band[0] is not None else "no ink at all")
    # One row origin has to explain BOTH bands, one pitch apart. Solved as an
    # interval rather than compared as a top edge, because the two inks are
    # different shapes: a slider knob and a line of digits against a popup's
    # title, each sitting differently inside the same 22 pt row.
    row = intersect([
        origin_interval(opacity_band, (0, CONTROL_H)),
        (lambda i: i and (i[0] - ROW_PITCH, i[1] - ROW_PITCH))(
            origin_interval(blend_band, (0, CONTROL_H))),
    ])
    same_row = intersect([
        origin_interval(opacity_band, (0, CONTROL_H)),
        origin_interval(blend_band, (0, CONTROL_H)),
    ])
    check(f"Blend is exactly one row pitch below Opacity — {CONTROL_H} pt of "
          f"DS.controlHeight plus {ROW_SPACING} pt of InspectorMetrics.rowSpacing = "
          f"{ROW_PITCH} pt", row is not None and row[0] <= row[1],
          f"one Opacity row top R ∈ {row} puts both inks where InspectorSection.init would"
          if row and row[0] <= row[1] else f"no such R: {row}")
    check("…and they are NOT the same row, which is what makes that a measurement",
          same_row is None or same_row[0] > same_row[1],
          f"R ∈ {same_row} would put both in one row" if same_row and same_row[0] <= same_row[1]
          else "no single row holds both inks")

    digests = {}
    for mode in BLEND_MODES:
        with open(renders[f"blend-{mode}"], "rb") as f:
            digests[mode] = f.read()
    distinct = len({v for v in digests.values()})
    check(f"the {len(BLEND_MODES)} modes draw {len(BLEND_MODES)} DIFFERENT rows — the popup "
          "shows the clip's own mode and not a fixed title", distinct == len(BLEND_MODES),
          f"{distinct} distinct renders of {len(BLEND_MODES)}: "
          + ", ".join(sorted(BLEND_MODES)))
    blend_row = Rect("the Blend row", INSPECTOR_X, blend_band[0] or 0, INSPECTOR_W,
                     (blend_band[1] or 0) - (blend_band[0] or 0))
    strays, moved = {}, {}
    for mode in BLEND_MODES[1:]:
        diff = changed_pixels(images["blend-normal"], images[f"blend-{mode}"])
        moved[mode] = bool(inside(diff, blend_row, scale, slop=1))
        out = outside(diff, [blend_row], scale, slop=1)
        if out:
            strays[mode] = out
    check("and each of the seven changes that one row and NOTHING else — no summary, no "
          "note, no other section", all(moved.values()) and not strays,
          f"{blend_row}" if not strays else "; ".join(
              f"{m}: {len(p)} px" for m, p in strays.items()))
    identical("a version-5 file, which has no `blend` key at all, renders byte-identically "
              "to an explicit `\"normal\"` — the schema default, with no migrate step",
              renders, images, "blend-normal", "blend-v5", scale)

    # 3. The note. `VideoPane.blendNote` is computed, not standing: it fires
    # only when the trap is live, and four fixtures ask it the four questions
    # its guards answer.
    print("\n3. the note — `blendNote`, which fires only when the trap is live")
    note_band = Rect("above the rows", INSPECTOR_X, TOOLBAR + TAB, INSPECTOR_W,
                     (opacity_band[0] or 0) - (TOOLBAR + TAB))
    note_diff, _ = report(
        images, "note-normal", "note-multiply",
        "black canvas, nothing behind: normal vs multiply", scale)
    check("a non-normal mode over the default canvas with nothing behind draws something "
          "ABOVE the value rows that `normal` does not", bool(inside(note_diff, note_band, scale)),
          f"{len(inside(note_diff, note_band, scale))} px above y {opacity_band[0]} pt")
    # The note is the FIRST row of the section's content
    # (`InspectorSection.init` adds it before the rows), so everything under
    # it moves down by the note's own height plus one row spacing. Solved,
    # not assumed — and the same number for all seven modes is the claim.
    shifts = {}
    for mode in BLEND_MODES[1:]:
        band = Rect("below Transform", INSPECTOR_X, (opacity_band[0] or 0) + CONTROL_H,
                    INSPECTOR_W - SCROLLER_W,
                    (HEIGHT - TIMELINE_H) - ((opacity_band[0] or 0) + CONTROL_H))
        scores = shift_match(images["note-normal"], images[f"note-{mode}"], band)
        shifts[mode] = scores[0]
    note_shift = shifts["multiply"][1]
    print("      shift below Transform, per mode (points, mismatched rows): "
          + ", ".join(f"{m} {s[1]}@{s[0]}" for m, s in shifts.items()))
    check("every one of the seven pushes the rows below it down by the SAME amount — one "
          "note row, which is what a section with a note is taller by",
          len({s[1] for s in shifts.values()}) == 1 and note_shift > 0,
          f"{sorted({s[1] for s in shifts.values()})} pt; a row of text plus "
          f"InspectorMetrics.rowSpacing {ROW_SPACING} pt")
    notes = {mode: open(renders[f"note-{mode}"], "rb").read() for mode in BLEND_MODES}
    check("and the seven notes are seven DIFFERENT drawings — the sentence names the mode "
          "rather than standing still (WHICH words it uses is not readable off a PNG; see "
          "the header)", len({v for k, v in notes.items() if k != "normal"}) == 7,
          f"{len({v for k, v in notes.items() if k != 'normal'})} distinct of 7")
    # The three suppressions, each its own fixture. In all three the note
    # must be gone, so the only thing that may differ from the same project
    # at `normal` is the Blend row itself.
    for tag, what in (
        ("blend", "a canvas that is not black — there IS something to blend against"),
        ("note-behind", "a visible clip on a track BEHIND it"),
    ):
        a, b = (("blend-normal", "blend-multiply") if tag == "blend"
                else ("note-behind-normal", "note-behind-multiply"))
        diff = changed_pixels(images[a], images[b])
        stray = outside(diff, [blend_row], scale, slop=1)
        check(f"{what} suppresses the note: the only thing that changes is the Blend row",
              bool(diff) and not stray,
              f"{len(diff)} px, all in {blend_row}" if not stray
              else f"{len(stray)} px elsewhere:\n" + describe(clusters(stray), scale))
    # …and the two things that must NOT suppress it. A hidden track draws
    # nothing and a clip with its video switched off draws nothing, so the
    # note is still true and must still be there.
    for tag, what in (
        ("note-hidden-multiply", "a HIDDEN track behind"),
        ("note-off-multiply", "a clip behind with its video switched off"),
    ):
        band = Rect("below Transform", INSPECTOR_X, (opacity_band[0] or 0) + CONTROL_H,
                    INSPECTOR_W - SCROLLER_W,
                    (HEIGHT - TIMELINE_H) - ((opacity_band[0] or 0) + CONTROL_H))
        scores = shift_match(images["note-behind-normal"], images[tag], band)
        check(f"{what} draws nothing, so the note stays: the rows below Transform sit one "
              "note row lower than they do with a visible one",
              scores[0][1] == note_shift,
              f"{scores[0][1]} pt at {scores[0][0]} mismatched rows; the note is "
              f"{note_shift} pt")

    # 4. The Gradient section.
    print(f"\n4. the Gradient section — `{GRADIENT_ID}`, under Fill, shut by the design")
    grad_diff, _ = report(images, "grad-2-shut", "grad-2-open",
                          "the section shut vs pinned open", scale)
    check(f"pinning `{GRADIENT_ID}` open changes pixels — a section built "
          "`defaultExpanded: false` draws nothing but its header until it is",
          bool(grad_diff))
    stray = outside(grad_diff, [tall_inspector], scale)
    check("every changed pixel is inside the inspector", bool(grad_diff) and not stray,
          "" if not stray else f"{len(stray)} px elsewhere:\n" + describe(clusters(stray), scale))
    identical(f"pinning `{ABSENT_ID}`, which no section has, renders byte-identically",
              renders, images, "grad-2-shut", "grad-2-absent", scale)
    identical("a TEXT clip has no Gradient section at all: the same pin renders "
              "byte-identically", renders, images, "text-clip-shut", "text-clip-open", scale)

    # WHERE its header is, MEASURED. A shut section draws nothing but its
    # header, so two packages differing only in what the summary says differ
    # only inside one — which locates the header to a few points AND is the
    # claim that a closed section still tells the truth about the value under
    # it (`phase3_chrome.py` makes the same one about Obscure).
    print("\n   the header, located from three shut renders:")
    summary = {}
    for tag in ("grad-3", "grad-radial", "grad-off"):
        diff = changed_pixels(images["grad-2-shut"], images[f"{tag}-shut"])
        summary[tag] = extent(diff, scale)
        print(f"      vs {tag:<12} {len(diff):>5} px, y {summary[tag][0]}–{summary[tag][1]} pt")
    for tag, what in (("grad-3", "the stop COUNT"), ("grad-radial", "the KIND"),
                      ("grad-off", "whether there is a gradient at all")):
        band = summary[tag]
        check(f"a SHUT section's summary tracks {what}, and every pixel it moves fits "
              f"inside one header (InspectorMetrics.headerHeight {SECTION_HEADER_H} pt) — "
              "which is all a shut section draws",
              band[0] is not None and band[1] - band[0] <= SECTION_HEADER_H,
              f"y {band[0]}–{band[1]} pt" if band[0] is not None
              else "the two shut renders are identical: the summary says nothing")
    header = intersect([origin_interval(summary[t], (0, SECTION_HEADER_H))
                        for t in ("grad-3", "grad-radial", "grad-off")])
    header_ok = header is not None and header[0] <= header[1]
    check("…and one header holds all three, which is what LOCATES it — every rectangle "
          "below is measured from this and none is written down",
          header_ok, f"the header's top y ∈ {header} pt" if header_ok else f"no such y: {header}")
    header = header if header_ok else (0.0, 0.0)
    grad_top = extent(grad_diff, scale)[0]
    check("the disclosure triangle the pin turned sits in that same header — the thing "
          "the pin moved and the thing the summary is drawn in are one section",
          header_ok and grad_top is not None
          and header[0] <= grad_top <= header[1] + SECTION_HEADER_H,
          f"the triangle's first row y {grad_top} pt")
    # WHERE it is in the stack: Fill is built immediately before it
    # (`ClipPane.makeSections`), and `gradientSection`'s note — "the gradient
    # covers the Fill colour above" — is written from that order.
    fill_diff = changed_pixels(images["grad-2-shut"], images["grad-2-fillpin"])
    fill_top = extent(fill_diff, scale)[0]
    check("the Gradient section sits BELOW Fill: pinning Fill open changes the panel "
          "higher up than pinning Gradient does",
          None not in (fill_top, grad_top) and fill_top < grad_top,
          f"Fill's first changed row y {fill_top} pt, Gradient's y {grad_top} pt")

    # How TALL it is, per fixture, solved out of what it pushed down.
    band_top = header[0] + SECTION_HEADER_H + BODY_MAX
    band = Rect("shift band", INSPECTOR_X, band_top, INSPECTOR_W - SCROLLER_W,
                (TALL - TIMELINE_H) - band_top)
    print(f"\n   the section's body height, solved from what it pushes down, over {band}:")
    bodies, margins = {}, {}
    for tag in ("grad-2", "grad-3", "grad-4", "grad-off", "grad-fill", "grad-ellipse",
                "grad-line", "grad-arrow", "grad-line-fill", "grad-radial", "grad-3-line"):
        best, second = body_height(images, tag, band)
        bodies[tag], margins[tag] = best[1], (best[0], second[0], second[1])
        print(f"      {tag:<14} {best[1]:>4} pt at {best[0]} mismatched rows  "
              f"(next best {second[1]} pt at {second[0]})")

    def solved(*tags):
        """Every named body was actually measured. Never a `guard`: a check
        that quietly disappears when its section is missing is a check that
        cannot fail, so this is ANDed into each comparison below instead."""
        return all(bodies.get(t, 0) > 0 for t in tags)

    rows = int((band.y1 - band.y0) * scale)
    check(f"every one of those is an EXACT match and not a best guess: the winning shift "
          f"leaves at most {SHIFT_SLOP} of the band's {rows} rows unexplained, and the "
          f"runner-up leaves at least {SHIFT_MARGIN} more",
          all(m[0] <= SHIFT_SLOP and m[1] - m[0] >= SHIFT_MARGIN for m in margins.values()),
          "; ".join(f"{t} {m[0]}/{m[1]}" for t, m in margins.items()
                    if not (m[0] <= SHIFT_SLOP and m[1] - m[0] >= SHIFT_MARGIN)) or "all clean")
    check(f"…and no body reached the band, so none was measured against itself — the "
          f"tallest is {max(bodies.values(), default=0)} pt against {BODY_MAX} pt of "
          "clearance under the header",
          bodies and 0 < max(bodies.values()) < BODY_MAX,
          f"{sorted(bodies.values())[-3:]} pt")

    rows2 = GRADIENT_FIXED_ROWS + 2 + GRADIENT_TRAILING_ROWS
    predicted = (CONTENT_TOP + rows2 * CONTROL_H + (rows2 - 1) * ROW_SPACING + CONTENT_BOTTOM)
    check(f"with two stops the body is exactly {rows2} rows tall — {CONTENT_TOP} + "
          f"{rows2} × (DS.controlHeight {CONTROL_H}) + {rows2 - 1} × "
          f"(InspectorMetrics.rowSpacing {ROW_SPACING}) + {CONTENT_BOTTOM} = {predicted} pt: "
          "the switch, the Kind popup, the Angle, one row per stop and the Add Stop button",
          solved("grad-2") and bodies["grad-2"] == predicted, f"measured {bodies['grad-2']} pt")
    check(f"a third stop adds exactly one row ({ROW_PITCH} pt)",
          solved("grad-2", "grad-3") and bodies["grad-3"] - bodies["grad-2"] == ROW_PITCH,
          f"{bodies['grad-3']} − {bodies['grad-2']} = "
          f"{bodies['grad-3'] - bodies['grad-2']} pt")
    check(f"and a fourth adds another ({2 * ROW_PITCH} pt over two stops)",
          solved("grad-2", "grad-4") and bodies["grad-4"] - bodies["grad-2"] == 2 * ROW_PITCH,
          f"{bodies['grad-4']} − {bodies['grad-2']} = "
          f"{bodies['grad-4'] - bodies['grad-2']} pt")

    # The note the section carries, and the cross-check that says the number
    # is a note row rather than whatever this measurement happened to answer.
    note_row = bodies.get("grad-fill", 0) - bodies.get("grad-2", 0)
    check("a gradient over a FILL adds one note row — `The gradient covers the Fill colour "
          "above`, which is the section saying where the colour went rather than the panel "
          "hiding it", solved("grad-2", "grad-fill") and note_row > 0,
          f"{bodies.get('grad-fill')} − {bodies.get('grad-2')} = {note_row} pt")
    check("…and that row is exactly as tall as the note section 3 measured in TRANSFORM — "
          "a different section, a different sentence, a different fixture and a different "
          "window height, so one line of `InspectorNoteLabel` plus "
          f"InspectorMetrics.rowSpacing {ROW_SPACING} pt is what both of them are",
          note_row > 0 and note_row == note_shift,
          f"{note_row} pt here against {note_shift} pt there")
    check("switching the gradient OFF drops the two stop rows and puts one `No gradient.` "
          f"line where they were: {predicted} − 2 × {ROW_PITCH} + {note_row} = "
          f"{predicted - 2 * ROW_PITCH + note_row} pt",
          solved("grad-off") and note_row > 0
          and bodies["grad-off"] == predicted - 2 * ROW_PITCH + note_row,
          f"off {bodies.get('grad-off')} pt vs on {bodies.get('grad-2')} pt")

    # 5. Line and arrow: the rows are DISABLED, not hidden.
    print("\n5. `line` and `arrow` — the rows are there, and dead")
    check("an ellipse's section is exactly a rectangle's — both have an area to fill",
          solved("grad-ellipse", "grad-2") and bodies["grad-ellipse"] == bodies["grad-2"],
          f"ellipse {bodies.get('grad-ellipse')} pt vs rectangle {bodies.get('grad-2')} pt")
    for kind in ("line", "arrow"):
        check(f"a {kind}'s section is one note row TALLER than a rectangle's — the rows are "
              "all still there (a hidden row would make it shorter, not longer), plus the "
              "sentence that says why they are dead",
              solved(f"grad-{kind}", "grad-2") and note_row > 0
              and bodies[f"grad-{kind}"] - bodies["grad-2"] == note_row,
              f"{kind} {bodies.get(f'grad-{kind}')} pt − rectangle {bodies.get('grad-2')} pt "
              f"= {bodies.get(f'grad-{kind}', 0) - bodies.get('grad-2', 0)} pt, one note row "
              f"is {note_row} pt")
    check("a FILL under a line adds NOTHING on top of that: the `line or arrow` note wins, "
          "so the panel says why the rows are dead rather than where the fill went",
          solved("grad-line", "grad-line-fill")
          and bodies["grad-line-fill"] == bodies["grad-line"],
          f"line+fill {bodies.get('grad-line-fill')} pt vs line {bodies.get('grad-line')} pt")

    # The row GRID, located from a fixture that moves ONE row and nothing
    # else: `grad-angle` differs from `grad-2` in the angle alone, so the
    # pixels between them ARE the Angle row. Everything measured below is
    # measured against this, so no row rectangle in this file is computed
    # from a constant alone.
    angle_diff = changed_pixels(images["grad-2-open"], images["grad-angle-open"])
    angle_ink = extent(angle_diff, scale)
    print(f"\n   the row grid, from the Angle fixture: {len(angle_diff)} changed px, "
          f"y {angle_ink[0]}–{angle_ink[1]} pt")
    check("dialling the Angle moves pixels, and every one of them fits inside a single row "
          f"(DS.controlHeight {CONTROL_H} pt)",
          angle_ink[0] is not None and angle_ink[1] - angle_ink[0] <= CONTROL_H,
          f"{angle_ink[1] - angle_ink[0]:g} pt tall" if angle_ink[0] is not None
          else "no ink at all")
    offset = SECTION_HEADER_H + CONTENT_TOP + 2 * ROW_PITCH
    grid = intersect([origin_interval(angle_ink, (0, CONTROL_H)),
                      (header[0] + offset, header[1] + offset)])
    grid_ok = grid is not None and grid[0] <= grid[1] and header_ok
    check("that row is the THIRD of the body — the Gradient switch, the Kind popup, then "
          f"the Angle — which is where InspectorSection's own arithmetic puts it: the "
          f"header's {SECTION_HEADER_H} pt, {CONTENT_TOP} pt of content inset and "
          f"2 × {ROW_PITCH} pt of row pitch, {offset} pt below the header this section "
          "was located by", grid_ok,
          f"the Angle row's top y ∈ {grid} pt" if grid_ok else f"no such y: {grid}")
    check("…and that interval is narrower than a row, which is what lets every rectangle "
          "below be an INNER band — built from the interval's far end at the top and its "
          "near end at the bottom, so it lies strictly inside the row it names wherever "
          "in the interval the row really starts, rather than a midpoint and a hope",
          grid_ok and grid[1] - grid[0] < CONTROL_H,
          f"{grid[1] - grid[0]:g} pt of play against a {CONTROL_H} pt row" if grid else "")
    angle_lo, angle_hi = grid if grid_ok else (0.0, 0.0)

    # The alpha solve. The pair is three stops on a RECTANGLE against three on
    # a LINE: three, not two, because with two the `list().count > 2` floor
    # disables Remove on BOTH sides and those pixels would solve for 1 inside
    # a region claiming 0.42.
    dy = bodies.get("grad-3-line", 0) - bodies.get("grad-3", 0)
    check("the pair the alpha is solved over is OFFSET by exactly one note row — the "
          "line's body is taller by the note and its rows sit that much lower, which is a "
          "measured shift rather than an assumed alignment",
          solved("grad-3", "grad-3-line") and note_row > 0 and dy == note_row,
          f"line {bodies.get('grad-3-line')} pt − rectangle {bodies.get('grad-3')} pt = "
          f"{dy} pt, one note row is {note_row} pt")
    rows_top = angle_hi - ROW_PITCH                          # inside the Kind row
    rows_bottom = angle_lo + 3 * ROW_PITCH + CONTROL_H       # inside the third stop row
    controls = Rect("Kind through Stop 3, control columns", LABEL_X1, rows_top,
                    CONTROL_X1 - LABEL_X1, rows_bottom - rows_top)
    labels = Rect("the same five rows, label column", LABEL_X0, rows_top, LABEL_W,
                  rows_bottom - rows_top)
    print(f"      {controls}\n      {labels}")
    background = modal_pixel(images["grad-3-open"], controls)
    print(f"      the pane fill, measured in the render itself: {background}")
    pairs = paired_pixels(images["grad-3-open"], images["grad-3-line-open"], controls, dy)
    control_diff = differing(pairs)
    stats = summarise(solve_alpha(pairs, background or (0,) * 4))
    check("the line's controls are the rectangle's controls drawn at ONE alpha — every "
          "component of every pixel solves for the same number",
          bool(control_diff) and stats is not None and stats[2] - stats[1] < 0.02,
          f"{len(control_diff)} px differ; median {stats[0]:.4f}, 1st–99th percentile "
          f"{stats[1]:.4f}–{stats[2]:.4f} over {stats[3]} components" if stats
          else "no pixel differed enough to solve")
    check(f"and that number is {DISABLED_ALPHA} — `InspectorPane`'s own "
          "`alphaValue = enabled() ? 1 : 0.42`, solved out of the pixels rather than read "
          "off a token (no colour is written down anywhere in this file)",
          stats is not None and abs(stats[0] - DISABLED_ALPHA) < 0.005,
          f"solved {stats[0]:.4f}" if stats else "nothing to solve")
    label_diff = differing(
        paired_pixels(images["grad-3-open"], images["grad-3-line-open"], labels, dy))
    check("the row LABELS are byte-identical across the same shift while those controls "
          "changed — it is the CONTROLS that go dead, which is the difference between a "
          "disabled control and a disabled row", bool(control_diff) and not label_diff,
          f"{labels}" if not label_diff else f"{len(label_diff)} px changed in the label "
          "column")

    # 6. Radial: the Angle row alone goes dead.
    print("\n6. `radial` — the Angle row alone, and its number unchanged")
    check("a radial gradient's section is exactly as tall as a linear one's: the Angle row "
          "is disabled, not removed",
          solved("grad-radial", "grad-2") and bodies["grad-radial"] == bodies["grad-2"],
          f"radial {bodies.get('grad-radial')} pt vs linear {bodies.get('grad-2')} pt")
    radial_diff, _ = report(
        images, "grad-2-open", "grad-radial-open", "linear vs radial", scale, limit=8)
    section = Rect("the Gradient section", INSPECTOR_X, header[0], INSPECTOR_W,
                   (header[1] - header[0]) + SECTION_HEADER_H + bodies.get("grad-2", 0))
    stray = outside(radial_diff, [section], scale)
    check("everything the kind changes is inside the Gradient section — its header's "
          "summary and its own rows, and nothing anywhere else in the panel",
          bool(radial_diff) and not stray,
          f"{section}" if not stray else f"{len(stray)} px elsewhere:\n"
          + describe(clusters(stray), scale))
    # Inner band at the top, outer at the bottom: whatever the true row origin
    # is inside the interval, `angle_row` is inside the Angle row and `below`
    # is below all of it.
    angle_row = Rect("the Angle row", INSPECTOR_X, angle_hi, INSPECTOR_W,
                     max((angle_lo + CONTROL_H) - angle_hi, 0))
    below = Rect("the stop rows and Add Stop", INSPECTOR_X, angle_hi + CONTROL_H, INSPECTOR_W,
                 max(section.y1 - (angle_hi + CONTROL_H), 0))
    check("the Angle row changed and the stop rows and the Add Stop button under it did "
          "NOT — a radial gradient still has stops to edit",
          bool(inside(radial_diff, angle_row, scale)) and not inside(radial_diff, below, scale),
          f"{below}" if not inside(radial_diff, below, scale)
          else f"{len(inside(radial_diff, below, scale))} px changed below the Angle row")
    angle_controls = Rect("the Angle row's controls", LABEL_X1, angle_row.y0,
                          CONTROL_X1 - LABEL_X1, angle_row.y1 - angle_row.y0)
    background = modal_pixel(images["grad-2-open"], angle_controls)
    pairs = paired_pixels(images["grad-2-open"], images["grad-radial-open"], angle_controls)
    stats = summarise(solve_alpha(pairs, background or (0,) * 4))
    check("the Angle row's every changed component is the SAME drawing at one alpha — so "
          "the row went dead without its number changing, which is what "
          "`enabled: { … kind == .linear }` does and what a row that reset its value would "
          "fail", bool(differing(pairs)) and stats is not None and stats[2] - stats[1] < 0.02,
          f"median {stats[0]:.4f}, 1st–99th percentile {stats[1]:.4f}–{stats[2]:.4f} over "
          f"{stats[3]} components" if stats else "no pixel differed enough to solve")
    check(f"and that alpha is {DISABLED_ALPHA} again — the same constant, solved a second "
          "time from a different pair", stats is not None
          and abs(stats[0] - DISABLED_ALPHA) < 0.005,
          f"solved {stats[0]:.4f}" if stats else "nothing to solve")

    # 7. The Clip menu, over the probe.
    print("\n7. Clip ▸ Add Background ▸ … and Clip ▸ Add Blurred Background")
    check("the menu probe builds — an instrument that will not compile is a FAILURE here, "
          "never an exit: it must not take the rest of the score with it",
          probe_binary is not None, probe_error or f"{os.path.relpath(PROBE, ROOT)}/menuprobe")
    cases = [
        {"name": "one shape clip", "package": packages["grad-2"], "select": [0],
         "selectors": ["addSolidColorBackground:", "addImageBackground:",
                       "addBlurredBackground:"]},
        {"name": "nothing selected", "package": packages["grad-2"], "select": [],
         "selectors": ["addSolidColorBackground:", "addImageBackground:",
                       "addBlurredBackground:"]},
        {"name": "a text clip", "package": packages["text-clip"], "select": [0],
         "selectors": ["addSolidColorBackground:", "addImageBackground:",
                       "addBlurredBackground:"]},
        {"name": "two clips", "package": packages["note-behind-normal"], "select": [0, 1],
         "selectors": ["addSolidColorBackground:", "addImageBackground:",
                       "addBlurredBackground:"]},
    ]
    answer, error = run_probe(probe_binary, cases) if probe_binary else (None, probe_error)
    if answer is None:
        # Every check below is about what the probe answered, so each one
        # fails by name rather than the list getting shorter.
        print(f"      the probe did not answer: {error}")
        answer = {"menu": {"items": []}, "validation": []}
    clip_menu = next(
        (i["submenu"]["items"] for i in answer["menu"]["items"]
         if i["title"] == "Clip" and i.get("submenu")), [])
    titles = [i["title"] for i in clip_menu]
    print("      Clip ▸ " + " · ".join(t or "—" for t in titles))
    background_item = next((i for i in clip_menu if i["title"] == "Add Background"), None)
    blurred_item = next((i for i in clip_menu if i["title"] == "Add Blurred Background"), None)
    check("Clip ▸ Add Background is a SUBMENU, not one item with a dialog behind it — two "
          "commands rather than two settings of one",
          background_item is not None and background_item.get("submenu") is not None,
          "" if background_item else "there is no Add Background item at all")
    sub = (background_item or {}).get("submenu", {"items": []})
    sub_titles = [i["title"] for i in sub["items"]]
    check("…and it holds exactly two rows, `Solid Color` then `Image…` — the colour needs "
          "no dialog and so takes no ellipsis; the picture needs an open panel and so "
          "takes one", sub_titles == ["Solid Color", "Image…"], f"{sub_titles}")
    check("the two rows carry `EditorViewController`'s own selectors",
          [i["action"] for i in sub["items"]]
          == ["addSolidColorBackground:", "addImageBackground:"],
          f"{[i['action'] for i in sub['items']]}")
    check("Clip ▸ Add Blurred Background is a plain item over `addBlurredBackground:`",
          blurred_item is not None and blurred_item.get("submenu") is None
          and blurred_item["action"] == "addBlurredBackground:",
          "" if blurred_item else "there is no Add Blurred Background item")
    keyed = [i["title"] for i in ([background_item, blurred_item] if blurred_item else [])
             + sub["items"] if i and i["key"]]
    check("neither takes a key equivalent, and neither does either submenu row — spec §9's "
          "table claims no row for phase 6 and a bare letter belongs to the editor's own "
          "`keyDown`", not keyed, f"{keyed}" if keyed else "no key equivalent on any of the four")
    if background_item is not None and blurred_item is not None:
        i, j = titles.index("Add Background"), titles.index("Add Blurred Background")
        grouped = (j == i + 1 and i > 0 and clip_menu[i - 1]["separator"]
                   and j + 1 < len(clip_menu) and clip_menu[j + 1]["separator"])
    else:
        grouped = False
    check("the two sit together in a group of their own, between separators — neither "
          "edits the selection, and both put a clip on a new back-most track", grouped,
          " · ".join(t or "—" for t in titles[max(0, titles.index("Add Background") - 1):])
          if background_item else "")

    validation = {v["name"]: v["enabled"] for v in answer["validation"]}
    print("      validateUserInterfaceItem: " + json.dumps(validation, sort_keys=True))
    for name in ("one shape clip", "nothing selected", "a text clip", "two clips"):
        answers = validation.get(name, {})
        check(f"with {name}, both plate commands are offered — a backdrop needs a canvas "
              "and nothing else",
              answers.get("addSolidColorBackground:") is True
              and answers.get("addImageBackground:") is True, f"{answers}")
    check("Add Blurred Background is offered for ONE clip whose source has a pixel size",
          validation.get("one shape clip", {}).get("addBlurredBackground:") is True,
          f"{validation.get('one shape clip')}")
    for name, why in (
        ("nothing selected", "there is no clip to copy"),
        ("two clips", "the op takes one clip and the validator says so"),
        ("a text clip", "a text source has no pixel size to scale to the canvas — the op's "
                        "own refusal, asked before the menu is drawn"),
    ):
        check(f"…and refused with {name}: {why}",
              validation.get(name, {}).get("addBlurredBackground:") is False,
              f"{validation.get(name)}")

    # 8. The instrument's own honesty.
    print("\n8. the renders themselves")
    check("no render reported an unsettled layout", not WARNINGS,
          "" if not WARNINGS else "\n".join("      " + w for w in WARNINGS))

    # Crops for the eye check.
    transform = Rect("transform", INSPECTOR_X, TOOLBAR + TAB, INSPECTOR_W, 300)
    for tag in ("blend-normal", "blend-multiply", "note-multiply", "note-behind-multiply"):
        images[tag].crop(transform, os.path.join(CHROME, f"crop-{tag}-transform.png"))
    gradient_crop = Rect(
        "gradient", INSPECTOR_X, header[0] - 4, INSPECTOR_W,
        SECTION_HEADER_H + max(bodies.values(), default=0) + 16)
    for tag in ("grad-2", "grad-3", "grad-3-line", "grad-off", "grad-fill", "grad-line",
                "grad-line-fill", "grad-radial", "grad-arrow"):
        images[f"{tag}-open"].crop(
            gradient_crop, os.path.join(CHROME, f"crop-{tag}-gradient.png"))
    print(f"\nPNGs, crops and the menu the probe read are in {os.path.relpath(CHROME, ROOT)}/")
    print("No blend and no gradient is PHOTOGRAPHED here — the preview well renders black "
          "offscreen and\nthe harness never compiles Compositor.metal. That is "
          "phase6_proof.py's, over MCP against a running app.")

    passed = sum(RESULTS)
    print(f"\n{passed}/{len(RESULTS)} checks passed")
    sys.exit(0 if passed == len(RESULTS) else 1)


if __name__ == "__main__":
    main()
