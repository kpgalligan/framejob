#!/usr/bin/env python3
"""Road map 2, phase 8 (Viewing and finding) — the OFFSCREEN half of the proof.

**Phase 8 is three features and the harness can photograph one of them**, which
is why this script is mostly PROBES. Preview Quality scales the PLAYER's video
composition — the preview well renders black offscreen because a Metal layer
has no drawable there, so no render at any size can show the difference.
Preview Window is a SECOND window, and the harness captures the editor's
content view. The Media tab's find band is the one thing that is drawn inside
that view, and section 7 photographs it.

**Section 9 is the exception, and it is the phase's own defect made
measurable.** The harness cannot photograph a preview, but a PROBE can render
one: `AVAssetImageGenerator` over a composition built exactly as `Playback`
builds it, with `renderSize` scaled exactly as `previewComposition` scales it,
answers a CGImage at 1920 x 1080, 960 x 540 and 480 x 270 with no window and no
drawable anywhere. That is how the reduced sizes came to be looked at at all —
and what it showed was that `[[position]]` is in DESTINATION pixels while three
fragment stages took it for canvas pixels, which was true only while
`renderSize` was always the canvas. Section 9 is that reading, kept.

So the instrument is `phase6_chrome.py`'s and `phase7_chrome.py`'s: a
`main.swift` of this script's own, compiled against the WHOLE of `app/Sources`
with `harness/build.sh`'s own swiftc line, cached on modification times, run
with a JSON request and answering with a JSON object. **A probe that will not
build is a scored FAILURE and never a `sys.exit`** — a rotted instrument must
not take the rest of the score down with it.

**The probe lives in an `.app` bundle, and exactly one of its six modes needs
that.** `NSApp.target(forAction:to:from:)` — the whole reason phase 8b's window
is an `NSPanel` — searches the KEY window's responder chain and then the MAIN
window's, and a process that cannot ACTIVATE has neither: measured, a bare
swiftc binary under `.prohibited`, `.accessory` or `.regular` reports
`keyWindow` nil and `mainWindow` nil after `makeKeyAndOrderFront`, and
`target(forAction:)` answers NONE for every mode, so the panel and the plain
window would look identical and the check would pass against both. Activation
needs a bundle and an `NSApplication.run()`, so `build_probe` wraps the binary
in one. **The `dispatch` mode therefore takes the keyboard focus for about a
second and puts two windows on screen while it runs.** Every other mode sets
`.prohibited` and orders nothing in, which is phase 7's posture.

What is claimed, section by section:

    1  **the aspect rule** (`PreviewQuality.renderSize(for:)`), which is the
       subtlest thing in the phase. Over eleven canvases, each at all three
       rows: the answer's aspect equals the canvas's EXACTLY, by integer
       cross-multiply and never a float tolerance; no answer is FINER than the
       row asked for; a coprime canvas (1001 x 667) comes back Full at every
       row; and the answer is always `m . (w/g, h/g)` for a whole `m`.
       **1920 x 1080 alone cannot fail any of this**, which is the whole
       reason 999 x 666, 1001 x 667, 100 x 100 and the portrait pair are in
       the list: a naive `(w/2, h/2)` is exactly right on 1920 x 1080 and
       wrong on three of the others. Then `PreviewQuality.stored()` with the
       key absent, at 0, 1 and 2, at 5 and -1 (outside the enum, which must
       read Full rather than trap) and at a STRING, plus the `store()` round
       trip.
    2  **the View menu**, in the same probe, because a menu lives in
       `NSApp.mainMenu` and is never drawn into a window (`phase6_chrome.py`'s
       reason). The menu ends with a separator, a `Preview Quality` submenu
       whose rows are `PreviewQuality.allCases`' titles carrying their raw
       values as TAGS, and `Preview Window` at "p" with command|shift —
       modifier bits read off `NSEvent` rather than written down here. Then
       `validatePreviewQualityAction`: true, `.on` for exactly the stored row
       and `.off` for the other two, and `nil` for a selector that is not its
       own.
    3  **the panel contract** — `NSPanel`, `canBecomeMain` false,
       `hidesOnDeactivate` false, excluded from the Windows menu, not released
       when closed, `.fullScreenPrimary`, the fixed autosave name — and the
       toggle's own behaviour (a second ⇧⌘P hides and keeps the controller, a
       third shows it again, the editor window closing closes it).
    4  **the dispatch guarantee those properties exist for**: with the panel
       KEY, `NSApp.target(forAction:)` for ⌘E, ⌘T and ⌘0 still resolves to the
       editor's controller and the menu items validate ENABLED. The build lane
       measured that a titled `NSWindow` instead makes all three resolve to
       NONE. The precondition — the app activated and the panel really is
       key — is asserted before the answer is read, so a machine that refused
       to activate fails by name instead of passing vacuously.
    5  **one player, two layers.** The layer in the panel is the same
       `AVPlayer` as `Playback.playerLayer`'s, by identity; the panel holds
       exactly one `AVPlayerLayer`; and `PreviewWindowController.swift`
       constructs no `AVPlayer` at all, read structurally out of the source.
       **Nothing here claims either layer is DISPLAYING anything**: the phase's
       own spike measured that `isReadyForDisplay` and `videoRect` read true
       and plausible for a layer with no superlayer, and `displayedPixelBuffer`
       — the only property that discriminates — is nil for both in a process
       with no window on screen. Both readings are recorded so that nobody
       reaches for the useless two later.
    6  **8c's arithmetic and its no-rebuild design.** `usesMedia` /
       `clipsUsing` / `timelineClipsUsing` over a fixture with a top-level
       user, a NEST-ONLY user, a both-ways user and an unused entry;
       `MediaListFilter.admits` and `.ordered` at their boundaries (a
       diacritic, a case fold, a literal space that is NOT trimmed, all four
       orders and their tie rule); the popup's row titles and indices; and
       then the pane itself, driven through the search field the way AppKit
       drives it — the rows re-order and hide with **no rebuild**, the search
       field is the SAME OBJECT afterwards, `structureSignature` does not
       move, and a sibling field keeps first responder and its caret offset.
       Beside it, the AppKit premise the design rests on, asserted against
       plain `NSStackView`s: hiding an arranged subview collapses it out of
       the layout, `insertArrangedSubview(_:at:)` MOVES rather than
       duplicates (all 24 permutations of four rows), and removing a field's
       ancestor loses both the responder and the caret.
    7  **the find band, photographed.** The band's height against the two
       hairlines that bound it, the search field's line, the 116 pt popup, the
       13 pt checkbox at the trailing edge, the tally, and the three NARROWED
       states.
    9  **what a reduced render size does to the three fragment stages that
       measure a fragment in CANVAS pixels** — the nest clip rectangle, the
       shadow draw and the outgoing dissolve's weight correction (8d). Four
       fixtures of SHAPE clips, each rendered at all three qualities through
       the app's own path, and every claim a FRACTION of the frame: the same
       picture at a different resolution, never a pixel count. This is the
       one section that renders a pixel, and it needed the second bundle
       `build_metal_probe` makes.

**The narrowed states needed a twelfth harness argument, and that is a
decision this script has to justify rather than slip past.** The band's state
is view state no package carries, and the only thing that writes it in the app
is a person typing into a field and clicking two controls — so without an
argument the harness can photograph the RESTING band and nothing else, and the
resting band is the part of phase 8c that a build with the whole filter deleted
would still draw. `candidateSpans` is the precedent exactly (phase 3's
Remove Silences wash, view state set by a sheet that cannot be put up
offscreen), and `mediaFilter` is APPENDED after `expandSections` in the shape
that phase set, so every earlier chrome script's argument positions still hold
and their scores are re-run here to say so. It drives the app's OWN controls —
`controlTextDidChange(_:)` on the field, `itemPicked:` on the popup,
`mouseDown(with:)` on the checkbox — and touches `MediaPane.filter`, which is
private, not at all.

**The window is 1440 x 1100 and the height is measured, not picked.** At
phase 2's 862 the inspector's visible height is about 480 pt, the six-row list
overflows it and the pane grows a 16 pt legacy scroller — and the NARROWED
renders, whose lists fit, do not. Every trailing-aligned thing in the panel
then sits 16 pt further right in one render than in another, and a comparison
of two states would be measuring a scroller. At 1100 no state overflows, the
trailing edge is 1429.5 pt in all five renders (measured), and the diff is the
feature.

**ONE CHECK IN SECTION 3 FAILED AGAINST THE BUILD THIS WAS WRITTEN FOR, and
it was a real defect rather than a broken instrument — fixed in the review, so
the whole file now scores 150/150.** What it found: the preview panel's
`frameAutosaveName` read back EMPTY, because `PreviewWindowController.init`
called `setFrameAutosaveName` BEFORE `super.init(window:)`, and
`NSWindowController.init(window:)` assigns its own `windowFrameAutosaveName` —
"" unless somebody set one — to the window it is handed, wiping the name. So
nothing ever wrote `NSWindow Frame ReelcutPreviewWindow`, the
`setFrameUsingName` restore beside it could never find anything, and the panel
opened centred every time — which is the one thing the type doc says it must
not do, since a preview window exists to be put on a SECOND DISPLAY. The
mechanism is measured on a BARE `NSPanel` and a BARE `NSWindowController` in
the same probe (`autosaveMechanism`), so the reading is about AppKit and not
about Reelcut, and the probe reports what `setFrameAutosaveName` answers when
it is re-asked AFTER the controller has taken the window (true, and the name
sticks) — which was both the proof and the fix. The call is after
`super.init` now and nothing else in this file moved for it. **Keep the
`autosaveMechanism` readings** even though the check they explain has gone
green: they are what stops the call being "tidied" back above `super.init`,
where AppKit reports nothing at all.

**Section 4 asks about the KEY WINDOW, so anything else that can be key
spoils it, and two things can.** With no key window at all
`NSApp.target(forAction:)` answers NONE — which is exactly what a plain
`NSWindow` in place of the panel would answer, so a spoiled run and the defect
this section exists to catch are indistinguishable. Both causes were measured
in this tree rather than guessed:

  · **A SHEET.** `viewDidAppear` calls `offerRelinkIfNeeded`, and every media
    entry in the six-file fixture points at a path that does not exist (so no
    thumbnail decode ever runs) — so the Relink sheet went up, took the key
    window, and all six checks fell together. The cure is the FIXTURE: the
    dispatch mode opens a package of one SHAPE clip and no media at all, which
    has a duration for Export… to validate against and nothing to relink, and
    the probe reports `attachedSheet` so a sheet that comes back is named
    rather than inferred.
  · **Another PROCESS activating.** An app launching during the two seconds
    this mode runs takes the focus outright (measured — an unrelated build
    launched mid-run). So the probe re-demands the focus immediately before
    each of its two readings rather than once at launch, and the script
    retries on the PRECONDITION alone (the app active, the editor key AND
    main). Once that holds the first answer is scored and no second attempt is
    made, so nothing here re-rolls a failing GUARANTEE.
  · **A LOCKED CONSOLE.** A process on a locked console cannot ACTIVATE at
    all, so there is no key window to demand and the retry above can never
    succeed. That is HOST STATE and not this tree's, so the six readings that
    need the focus are SKIPPED BY NAME — `console_locked()`, the same reading
    `preview_refresh_probe.py` and `preview_validity_probe.py` take — while
    the seventh, the sheet, is the same reading either way and is still
    scored. Measured on ONE build, both ways: **150/150** with the console
    unlocked, **144/144 with 6 skipped** with it locked. Before this the
    locked run read 144/150, and six failures about a window being key look
    exactly like a regression in the thing section 4 exists to catch.

Run it with no port and no media:

    python3 tools/proof/phase8_chrome.py

Renders, crops, the probe's requests and answers land in
`tools/proof/work/chrome8/`.
"""

import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work")
CHROME = os.path.join(WORK, "chrome8")
BUILD = os.path.join(HERE, "harness", "build.sh")
PROBE = os.path.join(WORK, "phase8probe")
BUNDLE = os.path.join(PROBE, "Phase8Probe.app")
# Section 9's own bundle — the same binary with a compiled shader beside it.
# `build_metal_probe` says why it is not the bundle above.
METAL_BUNDLE = os.path.join(PROBE, "Phase8Metal.app")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")
PLACEHOLDER = os.path.join(ROOT, "app", "Resources", "Blank.mp4")
SOURCES = os.path.join(ROOT, "app", "Sources")
SHADER = os.path.join(ROOT, "app", "Resources", "Shaders", "Compositor.metal")

# ---------------------------------------------------------------------------
# Geometry, in POINTS, from the app's layout constants. Section 7 is the only
# one that photographs anything.

WIDTH = 1440
# See the header: 1100 rather than 862 so no state of the pane overflows its
# scroll view and the trailing edge is the same in every render.
HEIGHT = 1100

INSPECTOR_W = 304        # DS.panelWidth
INSET = 10               # InspectorMetrics.inset
ROW_SPACING = 7          # InspectorMetrics.rowSpacing
CONTROL_H = 22           # DS.controlHeight
POPUP_W = 116            # InspectorMetrics.popupWidth
CHECKBOX_BOX = 13        # OptionCheckboxControl.boxSize
FIELD_H = 24             # MediaSearchField's DSField.style height
ROW_H = 52               # MediaRowView.height
LIST_SPACING = 3         # MediaPane.listView's stack spacing
BAND_H = 60              # MediaPane.findRow's `bar(height: 60, …)`
ACTION_BAND_H = 38       # MediaPane.actionRow's

INSPECTOR_X = WIDTH - INSPECTOR_W                 # 1136
CONTENT_X0 = INSPECTOR_X + INSET                  # 1146
CONTENT_X1 = INSPECTOR_X + INSPECTOR_W - INSET    # 1430 — no scroller at 1100

# The two hairlines that bound the find band, MEASURED off a render and then
# checked against each other: `BarView(border: .bottom)` draws one at the foot
# of the action row and one at the foot of the find band, and what section 7
# asserts is their SEPARATION — `BAND_H + ROW_SPACING` — which is a statement
# about the constants and not about where the section happens to start.
ACTION_RULE_Y = 143.0
FIND_RULE_Y = 210.0
# The band's own top, derived: the rule is drawn at its foot.
BAND_Y0 = FIND_RULE_Y - BAND_H                    # 150
# The column stack inside it: 24 pt field, 6 pt gap, 22 pt controls = 52,
# centred in 60, so line 1 starts 4 pt down.
LINE_GAP = 6
LINE1_Y0 = BAND_Y0 + (BAND_H - (FIELD_H + LINE_GAP + CONTROL_H)) / 2   # 154
LINE2_Y0 = LINE1_Y0 + FIELD_H + LINE_GAP                              # 184
# The action row's tally, right-aligned at the content's trailing edge.
TALLY_Y0, TALLY_H = 114.0, 22.0
# The list's first row, one row spacing below the band's rule.
LIST_Y0 = FIND_RULE_Y + ROW_SPACING                                   # 217

# ---------------------------------------------------------------------------
# Packages, by hand (spec §5.2). A `.reelcut` is a directory holding a
# `project.json`, so nothing here loads asynchronously and every render is
# deterministic.
#
# Every media entry points at a path that does NOT exist, which is deliberate
# and not laziness: `MediaRowView.loadThumbnailIfNeeded` reads the package's
# thumbnail cache and, failing that, decodes an IMAGE file — so a video whose
# file is absent never starts an asynchronous decode and never changes the
# picture halfway through a settle. The rows draw a "missing" badge, which is
# below the band this script measures.

TICKS_PER_SECOND = 600_000


def media(mid, name, kind="video", seconds=1.0):
    return {
        "id": mid, "path": "/reelcut-phase8-no-such-directory/" + name,
        "bookmark": None, "kind": kind,
        "duration": int(seconds * TICKS_PER_SECOND),
        "width": 640 if kind != "audio" else 0,
        "height": 360 if kind != "audio" else 0,
        "fps": [30, 1], "has_video": kind != "audio", "has_audio": True,
        "has_alpha": False,
    }


def video_props(**over):
    """`VideoProps` in the core's field order (`model_props.rs`), `blend`
    last — where format version 6 appended it. The keyword arguments are
    section 9's, which needs an offset nest clip and a shadow; with none given
    this is the same dictionary every earlier section has always written."""
    props = {
        "x": 0.0, "y": 0.0, "scale": 1.0, "rotation": 0.0, "opacity": 1.0,
        "crop": {"l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0},
        "corner_radius": 0.0, "shadow": None,
        "color": {"brightness": 0.0, "contrast": 0.0, "saturation": 0.0, "hue": 0.0},
        "chroma": None, "filters": [], "reflection": None, "spotlight": None,
        "obscure": [], "blend": "normal",
    }
    props.update(over)
    return props


def shape_props(width, height, fill):
    """`ShapeProps` in the core's field order, `gradient` last. A filled
    rectangle with NO stroke, because `LayerRenderers.renderShape` draws the
    box exactly — so the layer's texture is `width` x `height` of one solid
    colour and every measurement in section 9 is a statement about placement
    rather than about drawing."""
    return {
        "kind": "rectangle", "width": float(width), "height": float(height),
        "stroke": None, "fill": fill, "arrow_start": False, "arrow_end": False,
        "radius": 0.0, "from": [0.0, 1.0], "to": [1.0, 0.0], "gradient": None,
    }


def clip(cid, track, start, duration, source, video=None, shape=None, transition=None):
    return {
        "id": cid, "track": track, "start": start, "duration": duration,
        "source": source,
        "enabled": {"video": True, "audio": True}, "speed": 1.0,
        "video": video or video_props(), "audio": None, "text": None, "shape": shape,
        "actions": [], "transition_in": transition, "name": None, "label": None,
    }


def media_source(mid):
    return {"kind": "media", "media": mid, "in": 0, "reversed": False}


def track(tid, name="Track 1"):
    return {"id": tid, "name": name, "hidden": False, "muted": False,
            "locked": False, "solo": False}


def project_json(media_list=(), clips=(), nests=(), next_id=100):
    return {
        "version": 6,
        "canvas": {
            "width": 1920, "height": 1080, "fps": [30, 1],
            "background": [0.0, 0.0, 0.0, 1.0], "fit_new_clips": True,
            "timecode_frames": True,
        },
        "media": list(media_list),
        "tracks": [track(10)],
        "clips": list(clips),
        "markers": [], "next_id": next_id, "nests": list(nests),
    }


# Six files, no clips: every one of them is UNUSED, which is what makes
# section 7's "Unused only" check a claim about the CHECKBOX and not about the
# list — the switch must change the box and nothing else. The names are chosen
# so that Import Order (Alpha, Beta, Gamma, Delta, Epsilon, Zeta) and Name
# order (Alpha, Beta, Delta, Epsilon, Gamma, Zeta) differ in exactly three
# places, so the sort's diff is three row-shaped clusters and not six.
SIX = [media(i + 1, name) for i, name in enumerate(
    ["Alpha.mov", "Beta.mov", "Gamma.mov", "Delta.mov", "Epsilon.mov", "Zeta.mov"])]

# The usage fixture (section 6): media 1 used by two TOP-LEVEL clips, media 2
# used ONLY inside a nest, media 3 used nowhere, media 4 used both ways.
USAGE_MEDIA = [media(1, "Top.mov"), media(2, "Nested.mov"), media(3, "Orphan.mov"),
               media(4, "Both.mov")]
USAGE_NEST = {
    "id": 50, "name": "Group", "width": 1920, "height": 1080,
    "tracks": [track(51, "Nest Track")],
    "clips": [clip(52, 51, 0, TICKS_PER_SECOND, media_source(2)),
              clip(53, 51, TICKS_PER_SECOND, TICKS_PER_SECOND, media_source(4))],
}
USAGE_CLIPS = [
    clip(20, 10, 0, TICKS_PER_SECOND, media_source(1)),
    clip(21, 10, 2 * TICKS_PER_SECOND, TICKS_PER_SECOND, media_source(1)),
    clip(22, 10, 4 * TICKS_PER_SECOND, TICKS_PER_SECOND, media_source(4)),
    clip(23, 10, 6 * TICKS_PER_SECOND, TICKS_PER_SECOND, {"kind": "nest", "project": 50}),
]

# The `dispatch` fixture: one SHAPE clip, NO media. It needs a duration (File ▸
# Export… validates on `project.duration > 0`) and it must not have a missing
# file in it, because `viewDidAppear` puts up the Relink sheet for one and a
# sheet takes the key window the whole of section 4 is about — see
# `makeEditor`'s doc in the probe.
SHAPE_CLIP = {
    "id": 30, "track": 10, "start": 0, "duration": 5 * TICKS_PER_SECOND,
    "source": {"kind": "shape"},
    "enabled": {"video": True, "audio": True}, "speed": 1.0,
    "video": video_props(), "audio": None, "text": None,
    "shape": {
        "kind": "rectangle", "width": 320.0, "height": 120.0,
        "stroke": {"width": 6.0, "color": [1.0, 1.0, 1.0, 1.0]},
        "fill": [0.2, 0.6, 0.9, 1.0], "arrow_start": False, "arrow_end": False,
        "radius": 0.0, "from": [0.0, 1.0], "to": [1.0, 0.0], "gradient": None,
    },
    "actions": [], "transition_in": None, "name": None, "label": None,
}

# ---------------------------------------------------------------------------
# Section 9's four fixtures — the three fragment stages that measure a
# fragment in CANVAS pixels, each given a picture whose right answer is
# arithmetic off the canvas and not a rendering to be eyeballed.
#
# All four are made of SHAPE clips and no media at all, which is what makes
# them exact: `LayerRenderers.renderShape` draws a filled, unstroked rectangle
# as `width` x `height` of one solid colour, so a lit pixel is a placement
# fact. Every measurement below is a FRACTION of the frame, because the whole
# question is whether the same picture comes back at three destination sizes.

# §5.2 Colors, not pixels — hence the names: `WHITE` is already the PNG
# reader's white further down this file, and a fixture constant that shadows
# an image constant is a trap whichever way the two are ordered.
FILL_WHITE = [1.0, 1.0, 1.0, 1.0]
FILL_BLUE = [0.0, 0.0, 1.0, 1.0]
FILL_RED = [1.0, 0.0, 0.0, 1.0]
CANVAS_W, CANVAS_H = 1920, 1080

# A. The nest clip rectangle. The nest's canvas is 960 x 540 and the shape
# inside it is 1920 x 1080 — TWICE the nest — so the rectangle is the only
# thing that cuts the picture, and a build that dropped the test entirely
# would fill the frame. The nest clip is off centre (-240, -135) so that
# neither axis can come out right by symmetry: `nest.rs::enter` writes the
# rect's centre as `canvas/2 + x`, giving (720, 405), 960 x 540 — canvas
# 240…1200 x 135…675.
NEST_FIXTURE = {
    "id": 60, "name": "Group", "width": 960, "height": 540,
    "tracks": [track(61, "Nest Track")],
    "clips": [clip(62, 61, 0, 4 * TICKS_PER_SECOND, {"kind": "shape"},
                   shape=shape_props(CANVAS_W, CANVAS_H, FILL_WHITE))],
}
NEST_RECT = (240 / CANVAS_W, 135 / CANVAS_H, 1200 / CANVAS_W, 675 / CANVAS_H)
NEST_COVERAGE = (960 * 540) / (CANVAS_W * CANVAS_H)

# B and C. A 400 x 300 white card with a pure RED shadow — a colour nothing
# else in the frame can make, so "is the shadow where it should be" is a
# question about one class of pixel.
#
# `blur: 0` deliberately: below `MetalRenderer.minShadowSigma` the draw
# samples the unblurred mask, so the silhouette has hard edges and its box is
# arithmetic rather than a threshold on a Gaussian tail. `distance: 0` puts
# the shadow exactly behind the card, where it must be invisible at EVERY
# quality; `distance: 300` at the default 315° puts it 300·cos45 = 212.13 px
# down and right, where it must be visible at every quality and in the same
# place.
#
# **The card sits at the canvas's upper-left QUARTER-point and not at its
# centre, and that is the difference between a check and a check that only
# looks like one.** A destination-space sample reaches uv 1/divisor, so at
# Quarter it reads the top-left SIXTEENTH of the canvas-sized mask: a card in
# the middle of the canvas is not in that sixteenth, the broken build draws no
# shadow at all, and "the shadow is invisible" passes for the wrong reason
# (measured — the centred fixture scored 24/25 against the defect rather than
# 22/25, and the one it missed was the Quarter row of the site the phase was
# about). At (480, 270) the card IS inside it, so a broken build puts a slab
# in open canvas at Half and at Quarter alike. It is off centre on both axes
# for the reason the nest fixture is.
CARD_W, CARD_H = 400, 300
CARD_CENTRE = (CANVAS_W / 4, CANVAS_H / 4)
CARD_BOX = (CARD_CENTRE[0] - CARD_W / 2, CARD_CENTRE[1] - CARD_H / 2,
            CARD_CENTRE[0] + CARD_W / 2, CARD_CENTRE[1] + CARD_H / 2)
CARD_RECT = (CARD_BOX[0] / CANVAS_W, CARD_BOX[1] / CANVAS_H,
             CARD_BOX[2] / CANVAS_W, CARD_BOX[3] / CANVAS_H)
CARD_COVERAGE = (CARD_W * CARD_H) / (CANVAS_W * CANVAS_H)
SHADOW_DISTANCE = 300.0
SHADOW_OFFSET = SHADOW_DISTANCE * (0.5 ** 0.5)          # 315°, down and right
SHADOW_RECT = ((CARD_BOX[0] + SHADOW_OFFSET) / CANVAS_W,
               (CARD_BOX[1] + SHADOW_OFFSET) / CANVAS_H,
               (CARD_BOX[2] + SHADOW_OFFSET) / CANVAS_W,
               (CARD_BOX[3] + SHADOW_OFFSET) / CANVAS_H)


def shadow_props(distance):
    return {"color": FILL_RED, "opacity": 1.0, "blur": 0.0, "angle": 315.0,
            "distance": distance}


def shadow_clips(distance):
    """The card, placed by §5.3's rule — `x`/`y` are an offset from the CANVAS
    CENTRE, so the quarter-point above is a negative quarter-canvas here."""
    return [clip(20, 10, 0, 4 * TICKS_PER_SECOND, {"kind": "shape"},
                 video=video_props(shadow=shadow_props(distance),
                                   x=CARD_CENTRE[0] - CANVAS_W / 2,
                                   y=CARD_CENTRE[1] - CANVAS_H / 2),
                 shape=shape_props(CARD_W, CARD_H, FILL_WHITE))]


# D. A cross dissolve whose incoming half covers the bottom-right QUADRANT
# and nothing else — the case the correction exists for and the only one that
# can see it fail. Two full-frame clips hide the defect entirely, because a
# partner covering the whole canvas has no edge inside the frame.
#
# At the midpoint the arithmetic is exact and the two answers are far apart:
# outside the partner the outgoing white lands at alpha 0.5 over black, which
# is 128 grey at every quality. INSIDE it the outgoing is divided by the
# attenuation the incoming is about to apply — (1 - p)/(1 - p·1) = 1 — so the
# white is whole and the blue at 0.5 over it reads (128, 128, 255). Skip the
# correction and the white lands at 0.5, the blue at 0.5 over THAT, and the
# same pixel reads (64, 64, 191). One class of pixel per answer, and the
# frame holds exactly one of them.
DISSOLVE_CLIPS = [
    clip(20, 10, 0, 4 * TICKS_PER_SECOND, {"kind": "shape"},
         shape=shape_props(CANVAS_W, CANVAS_H, FILL_WHITE)),
    clip(21, 10, 3 * TICKS_PER_SECOND, 4 * TICKS_PER_SECOND, {"kind": "shape"},
         video=video_props(x=CANVAS_W / 4, y=CANVAS_H / 4),
         shape=shape_props(CANVAS_W / 2, CANVAS_H / 2, FILL_BLUE),
         transition={"kind": "cross_dissolve"}),
]
DISSOLVE_TICK = 7 * TICKS_PER_SECOND // 2       # the overlap's exact midpoint
QUADRANT = (0.5, 0.5, 1.0, 1.0)

# The colour classes the probe counts. Boxes rather than exact values, wide
# enough for the resample and DISJOINT — the corrected and uncorrected
# dissolve pixels are 64 apart on two channels, and neither can be read as the
# plain grey outside the partner, so a frame holds exactly one of the three
# answers and never a blend of two.
CARD_CLASSES = [
    {"name": "card", "low": [200, 200, 200], "high": [255, 255, 255]},
    {"name": "shadow", "low": [100, 0, 0], "high": [255, 90, 90]},
]
DISSOLVE_CLASSES = [
    {"name": "corrected", "low": [100, 100, 230], "high": [160, 160, 255]},
    {"name": "uncorrected", "low": [40, 40, 160], "high": [95, 95, 225]},
    {"name": "plain", "low": [100, 100, 100], "high": [160, 160, 160]},
]

PACKAGES = {
    "six": dict(media_list=SIX),
    "dispatch": dict(clips=[SHAPE_CLIP]),
    # The band must not exist at all with nothing to find (`makeSections`'s
    # own guard), which is section 7's first differential.
    "none": dict(media_list=[]),
    "usage": dict(media_list=USAGE_MEDIA, clips=USAGE_CLIPS, nests=[USAGE_NEST]),
    "nest": dict(clips=[clip(20, 10, 0, 4 * TICKS_PER_SECOND,
                             {"kind": "nest", "project": 60},
                             video=video_props(x=-240.0, y=-135.0))],
                 nests=[NEST_FIXTURE]),
    "shadow0": dict(clips=shadow_clips(0.0)),
    "shadow300": dict(clips=shadow_clips(SHADOW_DISTANCE)),
    "dissolve": dict(clips=DISSOLVE_CLIPS),
}


def write_package(name, spec):
    path = os.path.join(WORK, "p8-" + name + ".reelcut")
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


def render(binary, package, out, media_filter="-"):
    """One render of the MEDIA tab. Twelve arguments — the twelfth is this
    phase's own and everything before it is exactly what phase 3 left."""
    args = [
        binary, package, out, "light", str(WIDTH), str(HEIGHT), "-1", "0", "1",
        "media", "-", "-", media_filter,
    ]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        sys.stderr.write(result.stdout + result.stderr)
        sys.exit(f"render failed for {package}")
    # `Harness.png` writes to stderr when the layout never settled, and
    # `applyMediaFilter` writes there when it could not find a control — both
    # would make every byte comparison below measure something other than the
    # feature, so they are collected and scored at the end.
    if result.stderr.strip():
        WARNINGS.append(f"{os.path.basename(out)}: {result.stderr.strip()}")
    return out


# ---------------------------------------------------------------------------
# The probe.

PROBE_SOURCE = r'''// Written by tools/proof/phase8_chrome.py. See that file's header.
//
// One binary, several MODES: the mode is `request["mode"]`, the request is
// argv[1] and the answer is argv[2]. Every mode writes one JSON object and
// exits, so a mode that answers nothing is a scored failure and not a crash.
import AVFoundation
import AppKit

// The two JSON paths, picked out by extension rather than by position: the
// `dispatch` mode is launched through `open -W -n`, which is the only
// launcher that reliably ACTIVATES the process (measured — a direct exec
// succeeds about one time in three), and `open` is entitled to put arguments
// of its own in front of ours.
let jsonArguments = CommandLine.arguments.dropFirst().filter { $0.hasSuffix(".json") }
let requestURL = URL(fileURLWithPath: jsonArguments.first ?? "")
let outURL = URL(fileURLWithPath: jsonArguments.count > 1 ? jsonArguments[1] : "")
let request =
    (try? JSONSerialization.jsonObject(with: Data(contentsOf: requestURL)) as? [String: Any])
    ?? [:]
let mode = request["mode"] as? String ?? ""
let app = NSApplication.shared

var answer: [String: Any] = [:]

func finish() {
    // WHICH binary answered. `open -n <path>` is asked for a bundle by PATH,
    // but LaunchServices resolves bundle IDENTIFIERS, and a mutation run holds
    // two copies of this bundle under one id — so a mutant that was never
    // actually consulted would read exactly like a surviving one. The script
    // scores this against the bundle it built.
    answer["bundlePath"] = Bundle.main.bundlePath
    let data = (try? JSONSerialization.data(
        withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    try? data.write(to: outURL)
}

/// The fonts beside the binary. In a bundle `Bundle.main.resourceURL` is
/// `Contents/Resources`, which is where `build_probe` puts them.
func registerFonts() {
    guard let resources = Bundle.main.resourceURL else { return }
    let fonts = resources.appendingPathComponent("Fonts")
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: fonts.path) else {
        return
    }
    for name in names where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
        CTFontManagerRegisterFontsForURL(
            fonts.appendingPathComponent(name) as CFURL, .process, nil)
    }
}

/// Every key the chrome and the two phase-8 features read, pinned in the
/// VOLATILE argument domain — which is searched first, so nothing this process
/// writes and nothing the machine already holds can change an answer. It is
/// the harness's `pinDefaults` rule applied to a probe: a preview quality left
/// behind by a person using the app would otherwise decide section 2's
/// checkmark.
func pinDefaults(_ extra: [String: Any] = [:]) {
    var pinned: [String: Any] = [
        PreviewQuality.defaultsKey: 0,
        "NSWindow Frame " + PreviewWindowController.frameAutosaveName: "",
        "AgentServerEnabled": false,
        "AppleShowScrollBars": "Always",
        // The launch flag CLAUDE.md's own instructions pass to the app
        // (`-ApplePersistenceIgnoreState YES`), as a default rather than an
        // argument: without it AppKit restores windows from an earlier run of
        // this bundle id, and a restored window that becomes KEY decides
        // section 4's answer.
        "ApplePersistenceIgnoreState": true,
        "NSQuitAlwaysKeepsWindows": false,
    ]
    for (key, value) in extra { pinned[key] = value }
    UserDefaults.standard.setVolatileDomain(pinned, forName: UserDefaults.argumentDomain)
}

func openDocument(_ path: String) -> ProjectDocument? {
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
        document.fileURL = URL(fileURLWithPath: path)
    } catch {
        return nil
    }
    return document
}

func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
    var found: [T] = []
    for subview in view.subviews {
        if let hit = subview as? T { found.append(hit) }
        found.append(contentsOf: descendants(type, in: subview))
    }
    return found
}

/// The responder chain from a window's first responder up, by class name —
/// what `NSApp.target(forAction:)` actually walks.
func chainOf(_ window: NSWindow?) -> [String] {
    guard let window = window else { return [] }
    var names: [String] = []
    var responder: NSResponder? = window.firstResponder
    var guardCount = 0
    while let current = responder, guardCount < 24 {
        names.append(String(describing: type(of: current)))
        responder = current.nextResponder
        guardCount += 1
    }
    return names
}

func playerLayers(in layer: CALayer?) -> [AVPlayerLayer] {
    guard let layer = layer else { return [] }
    var found: [AVPlayerLayer] = []
    if let player = layer as? AVPlayerLayer { found.append(player) }
    for sub in layer.sublayers ?? [] { found.append(contentsOf: playerLayers(in: sub)) }
    return found
}

/// The app's own document window, opened the way the app opens one.
///
/// **Through `makeWindowControllers()` and `EditorWindowController`, not a
/// hand-built `NSWindow`**, and section 4 is why: the dispatch guarantee is a
/// claim about how AppKit resolves an action through the MAIN window's
/// responder chain, and a window assembled differently from the app's would
/// be a claim about this file. Everything that needs a real view tree goes
/// through this, so one description of "the app, running" serves four modes.
///
/// **`viewDidAppear` can put up a SHEET, and the `dispatch` mode is the one
/// that cares.** `offerRelinkIfNeeded` presents the Relink sheet once per
/// document whose media is missing — and every media entry in this script's
/// six-file fixture points at a path that does not exist, deliberately, so no
/// thumbnail decode ever runs. A sheet is a window and it takes KEY, so the
/// dispatch mode's editor never became key and all six of its checks fell
/// together (measured: `key "Untitled"`, `main "p8-six.reelcut"`). The cure is
/// the FIXTURE and not a dismissal: `dispatch` opens a package of one SHAPE
/// clip and no media at all, which has a duration for Export… to validate
/// against and nothing to relink. `attachedSheet` is reported either way, so a
/// sheet that appears again is named rather than inferred.
func makeEditor(_ path: String, tab: String? = nil) -> (ProjectDocument, EditorViewController,
    NSWindow)?
{
    let before = NSApp.windows.count
    guard let document = openDocument(path) else { return nil }
    let afterRead = NSApp.windows.count
    document.makeWindowControllers()
    answer["windowCensus"] = [
        "beforeOpen": before, "afterRead": afterRead,
        "afterMakeWindowControllers": NSApp.windows.count,
        "windowControllers": document.windowControllers.count,
        "titles": NSApp.windows.map { $0.title },
    ]
    guard let window = document.windowControllers.first?.window,
        let controller = window.contentViewController as? EditorViewController
    else { return nil }
    window.setContentSize(NSSize(width: 1440, height: 1100))
    controller.viewWillAppear()
    controller.viewDidAppear()
    // The sheet `viewDidAppear` may have put up, named rather than dismissed:
    // section 4's whole subject is which window is KEY, and a sheet is a
    // window. See `makeEditor`'s doc.
    answer["attachedSheet"] = window.attachedSheet != nil
    controller.refreshFromDocument(isLive: false)
    for _ in 0..<12 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        controller.view.layoutSubtreeIfNeeded()
    }
    if tab == "media" { controller.inspector?.select(.media) }
    for _ in 0..<6 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        controller.view.layoutSubtreeIfNeeded()
    }
    return (document, controller, window)
}

// ---------------------------------------------------------------------------
// quality — `PreviewQuality`'s arithmetic and its stored value. No window, no
// document, no AppKit state at all: this is a value type answering questions.

func runQuality() {
    answer["cases"] = PreviewQuality.allCases.map {
        ["raw": $0.rawValue, "title": $0.title, "divisor": $0.divisor]
    }
    var sizes: [[String: Any]] = []
    for pair in request["canvases"] as? [[Int]] ?? [] {
        let canvas = CGSize(width: pair[0], height: pair[1])
        sizes.append([
            "w": pair[0], "h": pair[1],
            "answers": PreviewQuality.allCases.map { quality -> [String: Any] in
                let size = quality.renderSize(for: canvas)
                return [
                    "raw": quality.rawValue, "divisor": quality.divisor,
                    // Integers, so the script's cross-multiply is exact: the
                    // function answers a CGSize and a float that has passed
                    // through JSON would make an aspect check a tolerance.
                    "w": Int(size.width), "h": Int(size.height),
                    "wIsWhole": size.width == size.width.rounded(),
                    "hIsWhole": size.height == size.height.rounded(),
                ]
            },
        ])
    }
    answer["sizes"] = sizes

    // `stored()`: the argument domain decides, so nothing on this machine can.
    var stored: [[String: Any]] = []
    for given in request["stored"] as? [Any] ?? [] {
        if let number = given as? Int {
            UserDefaults.standard.setVolatileDomain(
                [PreviewQuality.defaultsKey: number], forName: UserDefaults.argumentDomain)
        } else if let text = given as? String, text != "absent" {
            UserDefaults.standard.setVolatileDomain(
                [PreviewQuality.defaultsKey: text], forName: UserDefaults.argumentDomain)
        } else {
            UserDefaults.standard.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
            UserDefaults.standard.removeObject(forKey: PreviewQuality.defaultsKey)
        }
        stored.append(["given": given, "raw": PreviewQuality.stored().rawValue])
    }
    answer["stored"] = stored

    // `store()` and back, with the argument domain empty so the value this
    // writes is the one that is read.
    UserDefaults.standard.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
    answer["roundTrip"] = PreviewQuality.allCases.map { quality -> [String: Any] in
        quality.store()
        return ["stored": quality.rawValue, "read": PreviewQuality.stored().rawValue]
    }
    UserDefaults.standard.removeObject(forKey: PreviewQuality.defaultsKey)
    answer["afterRemoval"] = PreviewQuality.stored().rawValue
    answer["defaultsKey"] = PreviewQuality.defaultsKey
}

// ---------------------------------------------------------------------------
// menu — the main menu the delegate builds, and the quality validator.
//
// `AppDelegate.buildMainMenu()` is private and its one caller is
// `applicationWillFinishLaunching`, which the app runs at launch and neither
// the harness nor any render ever does.

func dump(_ item: NSMenuItem) -> [String: Any] {
    var row: [String: Any] = [
        "title": item.title, "separator": item.isSeparatorItem,
        "action": item.action.map { NSStringFromSelector($0) } ?? "",
        "key": item.keyEquivalent, "tag": item.tag,
        "modifiers": Int(item.keyEquivalentModifierMask.rawValue),
    ]
    if let sub = item.submenu {
        row["submenu"] = ["title": sub.title, "items": sub.items.map(dump)]
    }
    return row
}

func runMenu() {
    pinDefaults()
    let delegate = AppDelegate()
    delegate.applicationWillFinishLaunching(
        Notification(name: NSApplication.willFinishLaunchingNotification, object: app))
    answer["menu"] = [
        "title": NSApp.mainMenu?.title ?? "",
        "items": (NSApp.mainMenu?.items ?? []).map(dump),
    ]
    answer["modifierBits"] = [
        "command": Int(NSEvent.ModifierFlags.command.rawValue),
        "option": Int(NSEvent.ModifierFlags.option.rawValue),
        "shift": Int(NSEvent.ModifierFlags.shift.rawValue),
        "control": Int(NSEvent.ModifierFlags.control.rawValue),
    ]
    answer["titles"] = PreviewQuality.allCases.map { $0.title }

    guard let (_, controller, _) = makeEditor(request["package"] as? String ?? "") else {
        answer["error"] = "the package would not open"
        return
    }
    // The validator, over every quality the setting can be in and every tag a
    // menu row can carry. A build whose validator answered for a tag it does
    // not own would light two checkmarks at once.
    var validations: [[String: Any]] = []
    for chosen in PreviewQuality.allCases {
        controller.playback.setPreviewQuality(chosen)
        var states: [[String: Any]] = []
        for tag in [0, 1, 2] {
            let item = NSMenuItem(
                title: "row \(tag)",
                action: #selector(EditorViewController.setPreviewQuality(_:)), keyEquivalent: "")
            item.tag = tag
            let enabled = controller.validatePreviewQualityAction(
                #selector(EditorViewController.setPreviewQuality(_:)), item: item)
            states.append([
                "tag": tag, "enabled": enabled as Any, "on": item.state == .on,
            ])
        }
        validations.append([
            "quality": chosen.rawValue, "current": controller.playback.previewQuality.rawValue,
            "states": states,
        ])
    }
    answer["validation"] = validations
    // The arm answers nil for a selector that is not its own — the arm is
    // load-bearing, and one that answered `true` unconditionally would enable
    // every command in the chain.
    let foreign = NSMenuItem(
        title: "x", action: #selector(EditorViewController.exportProject(_:)), keyEquivalent: "")
    answer["armForAnotherSelector"] = controller.validatePreviewQualityAction(
        #selector(EditorViewController.exportProject(_:)), item: foreign) as Any
    // …and the action itself refuses a tag outside the enum (it beeps; the one
    // sound this script makes) and leaves the setting where it was.
    controller.playback.setPreviewQuality(.half)
    let bad = NSMenuItem(
        title: "bad", action: #selector(EditorViewController.setPreviewQuality(_:)),
        keyEquivalent: "")
    bad.tag = 7
    controller.setPreviewQuality(bad)
    answer["afterBadTag"] = controller.playback.previewQuality.rawValue
    controller.setPreviewQuality(nil)
    answer["afterNilSender"] = controller.playback.previewQuality.rawValue
}

// ---------------------------------------------------------------------------
// panel — the window `PreviewWindowController` builds, and the one player.
// No activation and nothing ordered on screen: every reading here is a
// property of the object.

func describeWindow(_ window: NSWindow) -> [String: Any] {
    [
        "class": String(describing: type(of: window)),
        "isPanel": window is NSPanel,
        "canBecomeMain": window.canBecomeMain,
        "canBecomeKey": window.canBecomeKey,
        "hidesOnDeactivate": window.hidesOnDeactivate,
        "isExcludedFromWindowsMenu": window.isExcludedFromWindowsMenu,
        "isReleasedWhenClosed": window.isReleasedWhenClosed,
        "collectionBehavior": Int(window.collectionBehavior.rawValue),
        "fullScreenPrimary": window.collectionBehavior.contains(.fullScreenPrimary),
        "frameAutosaveName": window.frameAutosaveName,
        "title": window.title,
        "minWidth": window.minSize.width, "minHeight": window.minSize.height,
        "styleMaskTitled": window.styleMask.contains(.titled),
        "styleMaskClosable": window.styleMask.contains(.closable),
        "styleMaskResizable": window.styleMask.contains(.resizable),
    ]
}

func runPanel() {
    pinDefaults()
    guard let (document, controller, window) = makeEditor(request["package"] as? String ?? "")
    else {
        answer["error"] = "the package would not open"
        return
    }
    answer["autosaveConstant"] = PreviewWindowController.frameAutosaveName
    answer["beforeToggle"] = ["exists": controller.previewWindow != nil]
    controller.togglePreviewWindow(nil)
    guard let wc = controller.previewWindow, let panel = wc.window else {
        answer["error"] = "no preview window was made"
        return
    }
    answer["panel"] = describeWindow(panel)
    // `setFrameAutosaveName` answers false when another window already holds
    // the name, and the name it did take is what `frameAutosaveName` reads
    // back. Both are reported so a failure here is legible rather than a bare
    // empty string.
    answer["autosaveRetake"] = panel.setFrameAutosaveName(
        PreviewWindowController.frameAutosaveName)
    answer["autosaveAfterRetake"] = panel.frameAutosaveName
    answer["editorWindow"] = describeWindow(window)
    // WHY it reads back the way it does, measured on a bare pair rather than
    // reasoned about: `NSWindowController.init(window:)` assigns its own
    // `windowFrameAutosaveName` — "" unless somebody set one — to the window
    // it is given, so a name set on the window BEFORE `super.init(window:)`
    // does not survive.
    let bare = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
        styleMask: [.titled], backing: .buffered, defer: false)
    _ = bare.setFrameAutosaveName("Phase8ProbeBareWindow")
    let nameBeforeController = bare.frameAutosaveName
    let bareController = NSWindowController(window: bare)
    answer["autosaveMechanism"] = [
        "beforeController": nameBeforeController,
        "afterController": bare.frameAutosaveName,
        "controllerName": bareController.windowFrameAutosaveName,
    ]
    answer["isShowing"] = wc.isShowing
    answer["documentName"] = document.displayName

    // One player, two layers. The panel's content view is a plain NSView
    // hosting the layer, so this walks the LAYER tree rather than the view
    // tree: `PreviewSurfaceView` is private and its `playerLayer` is too.
    let layers = playerLayers(in: panel.contentView?.layer)
    answer["previewLayers"] = layers.count
    answer["samePlayer"] = layers.first.map { $0.player === controller.playback.playerLayer.player }
        ?? false
    answer["editorLayerHasPlayer"] = controller.playback.playerLayer.player != nil
    answer["previewGravity"] = layers.first?.videoGravity.rawValue ?? ""
    answer["differentLayers"] = layers.first.map { $0 !== controller.playback.playerLayer } ?? false
    // The three properties the phase's spike measured, recorded so the useless
    // two are on the record as useless. `displayedPixelBuffer` is the only one
    // that discriminates, and in a process with nothing on screen it is nil
    // for both — which is why this script claims nothing about what either
    // layer shows.
    func display(_ layer: AVPlayerLayer?) -> [String: Any] {
        guard let layer = layer else { return [:] }
        return [
            "isReadyForDisplay": layer.isReadyForDisplay,
            "videoRectWidth": layer.videoRect.width,
            "videoRectHeight": layer.videoRect.height,
            "hasDisplayedBuffer": layer.displayedPixelBuffer() != nil,
        ]
    }
    answer["previewDisplay"] = display(layers.first)
    answer["editorDisplay"] = display(controller.playback.playerLayer)

    // The toggle: hide, show, and the controller kept across both.
    controller.togglePreviewWindow(nil)
    answer["afterSecond"] = [
        "isShowing": wc.isShowing, "sameController": controller.previewWindow === wc,
    ]
    controller.togglePreviewWindow(nil)
    answer["afterThird"] = [
        "isShowing": wc.isShowing, "sameController": controller.previewWindow === wc,
    ]
    // The validator's checkmark follows the panel, not the controller.
    func validated() -> [String: Any] {
        let item = NSMenuItem(
            title: "Preview Window",
            action: #selector(EditorViewController.togglePreviewWindow(_:)), keyEquivalent: "")
        let enabled = controller.validatePreviewWindowAction(
            #selector(EditorViewController.togglePreviewWindow(_:)), item: item)
        return ["enabled": enabled as Any, "on": item.state == .on]
    }
    answer["validateShowing"] = validated()
    controller.togglePreviewWindow(nil)
    answer["validateHidden"] = validated()
    let foreign = NSMenuItem(
        title: "x", action: #selector(EditorViewController.exportProject(_:)), keyEquivalent: "")
    answer["armForAnotherSelector"] = controller.validatePreviewWindowAction(
        #selector(EditorViewController.exportProject(_:)), item: foreign) as Any

    // The editor's window closing is the deterministic door.
    controller.togglePreviewWindow(nil)
    answer["beforeEditorClose"] = wc.isShowing
    window.close()
    for _ in 0..<4 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    answer["afterEditorClose"] = wc.isShowing
}

// ---------------------------------------------------------------------------
// dispatch — the one mode that needs an ACTIVE app, and the whole reason the
// probe is inside an `.app` bundle. See the script's header.

final class DispatchDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var controller: EditorViewController?
    var second: NSWindow?
    /// **Held, and it has to be**: `EditorViewController.document` is `weak`,
    /// and a document opened this way is not registered with
    /// `NSDocumentController` (`documents` reads 0), so nothing else in the
    /// process retains it. Dropped, it deallocates, `controller.document`
    /// goes nil and `validateExportAction`'s first guard refuses — so File ▸
    /// Export… validated DISABLED with the editor key and the target
    /// resolving perfectly, which reads exactly like the defect this section
    /// is looking for. Measured, in this file.
    var document: ProjectDocument?

    /// The app's own answer, and it is load-bearing here: without it AppKit
    /// asks the shared document controller for an untitled document at launch
    /// and the window it makes becomes KEY, so every target below resolves
    /// through a document this probe never opened. Measured — the first run
    /// of this mode reported `keyWindow "Untitled"`.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ note: Notification) {
        pinDefaults()
        // The REAL menu, so the items whose targets are measured are the app's.
        AppDelegate().applicationWillFinishLaunching(
            Notification(name: NSApplication.willFinishLaunchingNotification, object: app))
        guard let (document, controller, window) = makeEditor(request["package"] as? String ?? "")
        else {
            answer["error"] = "the package would not open"
            finish()
            exit(0)
        }
        self.document = document
        self.controller = controller
        self.window = window
        answer["windowsAtStart"] = NSApp.windows.map {
            [$0.title, String(describing: type(of: $0)), $0.isVisible] as [Any]
        }
        answer["activationAttempts"] = demandFocus(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.stageTwo() }
    }

    /// Asks for the keyboard focus until this process HAS it and `wanted` is
    /// its key window, or a deadline passes; answers how many tries it took.
    ///
    /// Activation is the one thing in this file another PROCESS can take
    /// away, and it does: a run of this script was measured losing the focus
    /// mid-mode to an unrelated app launching, and every target below then
    /// read NONE — for a panel and for a plain window alike, which is a
    /// PASSING lie in the other direction. So the focus is demanded again
    /// immediately before each reading rather than once at launch, and
    /// section 4's precondition check is what turns "it never got it" into a
    /// named failure.
    @discardableResult
    func demandFocus(_ wanted: NSWindow?, tries: Int = 40) -> Int {
        var attempts = 0
        while attempts < tries {
            if app.isActive, wanted?.isKeyWindow ?? true { return attempts }
            app.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            wanted?.makeKeyAndOrderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            attempts += 1
        }
        return attempts
    }

    /// The three selectors whose actions live on `EditorViewController`, asked
    /// of the app the way a menu asks: nil target, resolved down the chain.
    func targets(_ label: String) -> [String: Any] {
        var found: [String: Any] = [:]
        for name in ["exportProject:", "splitAtPlayhead:", "zoomToFit:"] {
            let selector = NSSelectorFromString(name)
            let item = NSMenuItem(title: name, action: selector, keyEquivalent: "")
            let target = app.target(forAction: selector, to: nil, from: item)
            found[name] = target.map { String(describing: type(of: $0)) } ?? "NONE"
        }
        return [
            "stage": label,
            "targets": found,
            "appActive": app.isActive,
            "keyWindow": app.keyWindow?.title ?? "nil",
            "mainWindow": app.mainWindow?.title ?? "nil",
            "editorIsKey": window?.isKeyWindow ?? false,
            "editorIsMain": window?.isMainWindow ?? false,
            "secondIsKey": second?.isKeyWindow ?? false,
            "secondIsMain": second?.isMainWindow ?? false,
            "secondClass": second.map { String(describing: type(of: $0)) } ?? "none",
            // Every window in the process, because the first run of this mode
            // found a window nobody meant to make holding the key status.
            "documents": NSDocumentController.shared.documents.count,
            "chain": chainOf(window),
            "windows": NSApp.windows.map { window -> [String: Any] in
                [
                    "class": String(describing: type(of: window)), "title": window.title,
                    "visible": window.isVisible, "key": window.isKeyWindow,
                    "main": window.isMainWindow,
                ]
            },
            // The item's own enablement, which is what a person sees: the
            // whole menu is updated first, so this is AppKit's answer and not
            // a second reading of `target(forAction:)`.
            "exportEnabled": self.exportEnabled(),
            // The two things `validateExportAction` reads before it answers,
            // so a `false` above is attributable rather than mysterious.
            "controllerHasDocument": self.controller?.document != nil,
            "duration": Int(self.controller?.document?.project.duration ?? 0),
        ]
    }

    func exportEnabled() -> Bool {
        guard let menu = NSApp.mainMenu else { return false }
        for item in menu.items {
            guard let sub = item.submenu else { continue }
            sub.update()
            for row in sub.items
            where row.action == #selector(EditorViewController.exportProject(_:)) {
                return row.isEnabled
            }
        }
        return false
    }

    func stageTwo() {
        var stages: [[String: Any]] = []
        answer["refocusEditor"] = demandFocus(window)
        stages.append(targets("editor alone"))
        controller?.togglePreviewWindow(nil)
        second = controller?.previewWindow?.window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            answer["refocusPreview"] = self.demandFocus(self.second)
            stages.append(self.targets("preview key"))
            answer["stages"] = stages
            answer["panelIsPanel"] = self.second is NSPanel
            finish()
            exit(0)
        }
    }
}

// ---------------------------------------------------------------------------
// media — phase 8c's arithmetic, the pane that applies it, and the AppKit
// premise the pane's no-rebuild design rests on.

func snapshotEntries(_ rows: [[String: Any]]) -> [MediaSnapshot] {
    rows.map { row in
        MediaSnapshot(
            id: UInt32(row["id"] as? Int ?? 0),
            path: (row["dir"] as? String ?? "/x/") + (row["name"] as? String ?? ""),
            kind: MediaKind(rawValue: row["kind"] as? String ?? "video") ?? .video,
            duration: Ticks(row["duration"] as? Int ?? 0))
    }
}

func runMedia() {
    pinDefaults()
    // --- usage, over the real fixture through the real core.
    if let document = openDocument(request["usagePackage"] as? String ?? "") {
        let snapshot = document.project.snapshot
        var usage: [[String: Any]] = []
        for entry in snapshot.media {
            usage.append([
                "id": Int(entry.id), "name": entry.name,
                "usesMedia": snapshot.usesMedia(entry.id),
                "clipsUsing": snapshot.clipsUsing(entry.id).map { Int($0.id) },
                "timelineClipsUsing": snapshot.timelineClipsUsing(entry.id).map { Int($0.id) },
            ])
        }
        answer["usage"] = usage
        answer["nestCount"] = snapshot.nests.count
        answer["topLevelClips"] = snapshot.clips.count
    } else {
        answer["usageError"] = "the usage package would not open"
    }

    // --- the filter, as a value. Nothing is used in this snapshot, so
    // `unusedOnly` admits everything and the search is the only term.
    let entries = snapshotEntries(request["entries"] as? [[String: Any]] ?? [])
    let synthetic = ProjectSnapshot(media: entries)
    var searches: [[String: Any]] = []
    for text in request["searches"] as? [String] ?? [] {
        var filter = MediaListFilter()
        filter.search = text
        searches.append([
            "search": text,
            "admits": entries.filter { filter.admits($0, in: synthetic) }.map { Int($0.id) },
            "isNarrowing": filter.isNarrowing,
        ])
    }
    answer["searches"] = searches
    answer["orders"] = MediaListFilter.Order.allCases.map { order -> [String: Any] in
        var filter = MediaListFilter()
        filter.order = order
        return [
            "raw": order.rawValue, "title": order.title,
            "ids": filter.ordered(entries).map { Int($0) },
        ]
    }
    // The switch, against the fixture where something IS used.
    if let document = openDocument(request["usagePackage"] as? String ?? "") {
        let snapshot = document.project.snapshot
        var filter = MediaListFilter()
        filter.unusedOnly = true
        answer["unusedOnly"] = [
            "admits": snapshot.media.filter { filter.admits($0, in: snapshot) }.map { Int($0.id) },
            "isNarrowing": filter.isNarrowing,
        ]
        // …and the two together, which is an AND and not an OR. "top" names
        // a file that IS used, so the switch must take it away — where an OR
        // would keep it and add the unused one.
        for text in ["top", "rphan"] {
            var both = MediaListFilter()
            both.unusedOnly = true
            both.search = text
            var searchOnly = MediaListFilter()
            searchOnly.search = text
            answer["and-" + text] = [
                "searchOnly": snapshot.media.filter { searchOnly.admits($0, in: snapshot) }
                    .map { Int($0.id) },
                "both": snapshot.media.filter { both.admits($0, in: snapshot) }
                    .map { Int($0.id) },
            ]
        }
    }
    answer["defaultFilter"] = [
        "search": MediaListFilter().search,
        "order": MediaListFilter().order.rawValue,
        "unusedOnly": MediaListFilter().unusedOnly,
        "isNarrowing": MediaListFilter().isNarrowing,
    ]

    // --- the pane, driven the way AppKit drives it.
    guard let (document, controller, window) = makeEditor(
        request["package"] as? String ?? "", tab: "media"),
        let pane = descendants(MediaPane.self, in: controller.view).first
    else {
        answer["paneError"] = "no MediaPane"
        runAppKitPremise()
        return
    }
    guard let field = descendants(MediaSearchField.self, in: pane).first,
        let stack = pane.rows.first?.view.superview as? NSStackView
    else {
        answer["paneError"] = "no search field or list stack"
        runAppKitPremise()
        return
    }

    func paneState() -> [String: Any] {
        [
            "signature": pane.structureSignature,
            "modelOrder": pane.rows.map { Int($0.media) },
            "arranged": stack.arrangedSubviews.compactMap { view in
                pane.rows.first(where: { $0.view === view }).map { Int($0.media) }
            },
            "hidden": pane.rows.map { $0.view.isHidden },
            "visible": pane.rows.filter { !$0.view.isHidden }.map { Int($0.media) },
            // The arranged order restricted to what is showing — what a
            // person actually reads down the list, where `visible` above is
            // the MODEL's order and says nothing about the sort.
            "visibleArranged": stack.arrangedSubviews.compactMap { view in
                pane.rows.first(where: { $0.view === view && !$0.view.isHidden })
                    .map { Int($0.media) }
            },
            "labels": descendants(InspectorRowLabel.self, in: pane).map { $0.stringValue },
            "fieldIsSame": descendants(MediaSearchField.self, in: pane).first === field,
            "fieldText": field.stringValue,
            "rowCount": pane.rows.count,
            "subviewCount": stack.subviews.count,
        ]
    }

    func settle() {
        for _ in 0..<4 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            controller.view.layoutSubtreeIfNeeded()
        }
    }

    func type(_ text: String) {
        field.stringValue = text
        field.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: field))
        settle()
    }

    var pane_states: [[String: Any]] = []
    pane_states.append(["stage": "rest"].merging(paneState()) { a, _ in a })

    // First responder and the caret, before the filter moves anything.
    window.makeFirstResponder(field)
    let editor = field.currentEditor()
    editor?.selectedRange = NSRange(location: 0, length: 0)
    let responderBefore = window.firstResponder
    answer["responderBefore"] = [
        "isFieldEditor": responderBefore === editor,
        "hasEditor": editor != nil,
        "range": [editor?.selectedRange.location ?? -1],
    ]

    type("eta")
    if let editor = field.currentEditor() { editor.selectedRange = NSRange(location: 1, length: 0) }
    let caretBefore = field.currentEditor()?.selectedRange.location ?? -1
    pane_states.append(["stage": "search eta"].merging(paneState()) { a, _ in a })

    // The sort, through the popup's own action.
    if let popup = descendants(OptionPopupControl.self, in: pane).first {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.tag = MediaListFilter.Order.name.rawValue
        let picked = NSSelectorFromString("itemPicked:")
        answer["popupRespondsToItemPicked"] = popup.responds(to: picked)
        if popup.responds(to: picked) { popup.perform(picked, with: item) }
        settle()
    }
    pane_states.append(["stage": "sorted by name"].merging(paneState()) { a, _ in a })

    // What the whole permutation cost the person typing: nothing.
    answer["responderAfter"] = [
        "isFieldEditor": window.firstResponder === field.currentEditor(),
        "hasEditor": field.currentEditor() != nil,
        "caret": field.currentEditor()?.selectedRange.location ?? -1,
        "caretBefore": caretBefore,
        "fieldIsSame": descendants(MediaSearchField.self, in: pane).first === field,
    ]

    type("")
    pane_states.append(["stage": "cleared"].merging(paneState()) { a, _ in a })
    answer["paneStates"] = pane_states

    // --- Reveal in Timeline, on the usage fixture.
    if let (usageDocument, usageController, _) = makeEditor(
        request["usagePackage"] as? String ?? "", tab: "media"),
        let usagePane = descendants(MediaPane.self, in: usageController.view).first
    {
        var reveal: [[String: Any]] = []
        for entry in usageDocument.project.snapshot.media {
            reveal.append([
                "id": Int(entry.id), "name": entry.name,
                "canReveal": usagePane.canRevealInTimeline(entry.id),
            ])
        }
        answer["canReveal"] = reveal
        var sent: [String] = []
        usageController.inspector?.onCommand = { selector in
            sent.append(NSStringFromSelector(selector))
        }
        usagePane.revealInTimeline(1)
        answer["revealedTopLevel"] = [
            "selection": usageDocument.selection.map { Int($0) }.sorted(),
            "selectedMedia": Int(usageDocument.selectedMedia ?? 0),
            "sent": sent,
        ]
        sent.removeAll()
        usageDocument.selection = []
        usagePane.revealInTimeline(2)
        answer["revealedNestOnly"] = [
            "selection": usageDocument.selection.map { Int($0) }.sorted(),
            "sent": sent,
        ]
    } else {
        answer["revealError"] = "no usage pane"
    }

    runAppKitPremise()
}

// ---------------------------------------------------------------------------
// The AppKit premise. Not a claim about Reelcut at all — three claims about
// `NSStackView` and the field editor that the Media pane's whole no-rebuild
// design rests on. If AppKit ever changes here, the pane silently eats
// keystrokes and nothing else in this suite would say so.

func runAppKitPremise() {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
        styleMask: [.titled], backing: .buffered, defer: false)
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    window.contentView = root

    let container = NSView(frame: NSRect(x: 0, y: 200, width: 400, height: 100))
    root.addSubview(container)
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    field.stringValue = "abcdefgh"
    container.addSubview(field)

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 3
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)
    var rows: [NSView] = []
    for index in 0..<4 {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 20).isActive = true
        row.widthAnchor.constraint(equalToConstant: 200).isActive = true
        row.identifier = NSUserInterfaceItemIdentifier("row\(index)")
        stack.addArrangedSubview(row)
        rows.append(row)
    }
    root.layoutSubtreeIfNeeded()
    let allShown = stack.fittingSize.height
    rows[1].isHidden = true
    root.layoutSubtreeIfNeeded()
    let oneHidden = stack.fittingSize.height
    rows[1].isHidden = false
    root.layoutSubtreeIfNeeded()
    answer["stackHeights"] = [
        "allShown": allShown, "oneHidden": oneHidden,
        "shownAgain": stack.fittingSize.height,
        "arrangedCount": stack.arrangedSubviews.count,
        "subviewCount": stack.subviews.count,
    ]

    // Every permutation of four rows, applied the way `MediaPane.arrange`
    // applies one: `insertArrangedSubview(_:at:)` walking the wanted order.
    func permutations(_ items: [Int]) -> [[Int]] {
        guard items.count > 1 else { return [items] }
        var out: [[Int]] = []
        for (index, item) in items.enumerated() {
            var rest = items
            rest.remove(at: index)
            for tail in permutations(rest) { out.append([item] + tail) }
        }
        return out
    }
    var permutationRows: [[String: Any]] = []
    for wanted in permutations([0, 1, 2, 3]) {
        for (slot, index) in wanted.enumerated() {
            stack.insertArrangedSubview(rows[index], at: slot)
        }
        root.layoutSubtreeIfNeeded()
        let arranged = stack.arrangedSubviews.map { view in
            rows.firstIndex(where: { $0 === view }) ?? -1
        }
        // The LAID-OUT order as well as the arranged order: a stack that
        // recorded the permutation and drew the old one would pass on the
        // first alone.
        let laidOut = rows.indices.sorted { rows[$0].frame.minY > rows[$1].frame.minY }
        permutationRows.append([
            "wanted": wanted, "arranged": arranged, "laidOut": laidOut,
            "subviewCount": stack.subviews.count,
            "arrangedCount": stack.arrangedSubviews.count,
        ])
    }
    answer["permutations"] = permutationRows

    // The field beside them keeps first responder and its caret across one.
    window.makeFirstResponder(field)
    field.currentEditor()?.selectedRange = NSRange(location: 3, length: 0)
    let before: [String: Any] = [
        "isEditor": window.firstResponder === field.currentEditor(),
        "caret": field.currentEditor()?.selectedRange.location ?? -1,
    ]
    for (slot, index) in [3, 2, 1, 0].enumerated() {
        stack.insertArrangedSubview(rows[index], at: slot)
    }
    root.layoutSubtreeIfNeeded()
    answer["responderAcrossPermutation"] = [
        "before": before,
        "after": [
            "isEditor": window.firstResponder === field.currentEditor(),
            "caret": field.currentEditor()?.selectedRange.location ?? -1,
        ],
    ]
    // …and loses both when its ANCESTOR goes, which is what a rebuild does.
    container.removeFromSuperview()
    root.layoutSubtreeIfNeeded()
    answer["responderAfterAncestorRemoved"] = [
        "hasEditor": field.currentEditor() != nil,
        "isWindow": window.firstResponder === window,
        "isField": window.firstResponder === field,
    ]
}

// ---------------------------------------------------------------------------
// Mode 6: the three fragment stages that measure a fragment in CANVAS pixels,
// rendered at three DESTINATION sizes through the app's own path (phase 8d).
//
// This is the only mode that renders a pixel, and it is the only one whose
// bundle carries a `default.metallib` — `build_metal_probe` says why the two
// bundles are separate. Everything below `render` is the app's: the document,
// `CompositionBuilder.build`, `Playback.previewComposition`'s copy-and-set,
// `Compositor`, `MetalRenderer` and the project's own shader. Nothing here
// fills a uniform by hand, which is the point: a probe that wrote
// `canvasPerDest*` itself would pass against a build where Swift never wrote
// them at all.

/// One frame, as straight 8-bit RGBA in sRGB. `AVAssetImageGenerator` hands
/// back a CGImage in whatever space the composition used, so it is redrawn
/// into a known one rather than read raw — the measurements below are colour
/// CLASSES and a shifted blue would put every pixel in none of them.
func framePixels(_ image: CGImage) -> ([UInt8], Int, Int)? {
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let drawn: Bool = bytes.withUnsafeMutableBytes { raw -> Bool in
        guard let context = CGContext(
            data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return drawn ? (bytes, width, height) : nil
}

/// A named box in RGB. A frame is measured as the COVERAGE and the BOUNDING
/// BOX of each class, both as fractions of the destination, because the whole
/// question is whether one picture survives three destination sizes.
struct ColorClass {
    let name: String
    let low: [Int]
    let high: [Int]
}

func measureFrame(_ image: CGImage, _ classes: [ColorClass]) -> [String: Any] {
    guard let (pixels, width, height) = framePixels(image) else {
        return ["error": "the frame could not be read back"]
    }
    var count = [Int](repeating: 0, count: classes.count)
    var minX = [Int](repeating: width, count: classes.count)
    var maxX = [Int](repeating: -1, count: classes.count)
    var minY = [Int](repeating: height, count: classes.count)
    var maxY = [Int](repeating: -1, count: classes.count)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            for (n, klass) in classes.enumerated() {
                guard r >= klass.low[0], r <= klass.high[0], g >= klass.low[1],
                    g <= klass.high[1], b >= klass.low[2], b <= klass.high[2]
                else { continue }
                count[n] += 1
                minX[n] = min(minX[n], x); maxX[n] = max(maxX[n], x)
                minY[n] = min(minY[n], y); maxY[n] = max(maxY[n], y)
            }
        }
    }
    var measured: [String: Any] = [:]
    for (n, klass) in classes.enumerated() {
        var entry: [String: Any] = [
            "count": count[n], "coverage": Double(count[n]) / Double(width * height),
        ]
        if count[n] > 0 {
            entry["x0"] = Double(minX[n]) / Double(width)
            entry["x1"] = Double(maxX[n] + 1) / Double(width)
            entry["y0"] = Double(minY[n]) / Double(height)
            entry["y1"] = Double(maxY[n] + 1) / Double(height)
        }
        measured[klass.name] = entry
    }
    return ["width": width, "height": height, "classes": measured]
}

/// One frame of one document at one quality, through the app's own path.
/// The three lines that scale it are `Playback.previewComposition`'s, copied
/// rather than called because that method is private to a `Playback` this
/// probe has no player for — and copied EXACTLY, including the guard that
/// returns the builder's own object when the size does not move.
func renderPreviewFrame(
    _ document: ProjectDocument, quality: PreviewQuality, at tick: Ticks
) -> (CGImage?, CGSize, CGSize, String?) {
    let project = document.project
    guard let plan = project.plan, plan.duration > 0 else {
        return (nil, .zero, .zero, "the project has no plan")
    }
    let key = RecipeSource.shared.register()
    defer { RecipeSource.shared.unregister(key) }
    RecipeSource.shared.set(project, for: key)
    RecipeSource.shared.setOptions(.none, for: key)
    let built: BuiltComposition
    do {
        built = try CompositionBuilder.build(
            plan: plan, planJSON: project.planJSON, urls: document.mediaURLs(), recipeKey: key)
    } catch {
        return (nil, .zero, .zero, "the composition would not build: \(error)")
    }
    let base: AVVideoComposition = built.videoComposition
    var composition = base
    let wanted = quality.renderSize(for: base.renderSize)
    if wanted != base.renderSize, let copy = base.mutableCopy() as? AVMutableVideoComposition {
        copy.renderSize = wanted
        composition = copy
    }
    let generator = AVAssetImageGenerator(asset: built.composition)
    generator.videoComposition = composition
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.appliesPreferredTrackTransform = false
    do {
        let image = try generator.copyCGImage(
            at: CompositionBuilder.time(max(0, tick)), actualTime: nil)
        return (image, base.renderSize, composition.renderSize, nil)
    } catch {
        return (nil, base.renderSize, composition.renderSize, "no frame: \(error)")
    }
}

func runCompositor() {
    pinDefaults()
    // The layout contract `Compositor.swift` and `Compositor.metal` share,
    // from the side that can be asked. Nothing checks the Metal half but
    // reading it — and the renders below, which come out as garbage if the
    // two ever disagree.
    answer["layerUniformsSize"] = MemoryLayout<LayerUniforms>.size
    answer["layerUniformsStride"] = MemoryLayout<LayerUniforms>.stride
    answer["shadowUniformsSize"] = MemoryLayout<ShadowUniforms>.size
    answer["shadowUniformsStride"] = MemoryLayout<ShadowUniforms>.stride
    var rendered: [[String: Any]] = []
    for spec in request["renders"] as? [[String: Any]] ?? [] {
        let tag = spec["tag"] as? String ?? "?"
        let classes = (spec["classes"] as? [[String: Any]] ?? []).map {
            ColorClass(
                name: $0["name"] as? String ?? "?",
                low: $0["low"] as? [Int] ?? [0, 0, 0],
                high: $0["high"] as? [Int] ?? [255, 255, 255])
        }
        guard let document = openDocument(spec["package"] as? String ?? "") else {
            rendered.append(["tag": tag, "error": "the package would not open"])
            continue
        }
        let tick = Ticks(spec["tick"] as? Int ?? 0)
        for quality in PreviewQuality.allCases {
            let (image, canvas, destination, error) = renderPreviewFrame(
                document, quality: quality, at: tick)
            var row: [String: Any] = [
                "tag": tag, "quality": quality.rawValue,
                "canvas": [Int(canvas.width), Int(canvas.height)],
                "destination": [Int(destination.width), Int(destination.height)],
            ]
            if let image = image {
                for (key, value) in measureFrame(image, classes) { row[key] = value }
            } else {
                row["error"] = error ?? "no frame and no reason"
            }
            rendered.append(row)
        }
    }
    answer["renders"] = rendered
}

// ---------------------------------------------------------------------------

registerFonts()
switch mode {
case "dispatch":
    // The one mode that needs a key window. See the script's header: without
    // an ACTIVE app there is no key window and no main window, and
    // `target(forAction:)` answers NONE for a panel and a plain window alike.
    app.setActivationPolicy(.accessory)
    let delegate = DispatchDelegate()
    app.delegate = delegate
    app.run()
default:
    app.setActivationPolicy(.prohibited)
    switch mode {
    case "quality": runQuality()
    case "menu": runMenu()
    case "panel": runPanel()
    case "media": runMedia()
    case "appkit": runAppKitPremise()
    case "compositor": runCompositor()
    default: answer["error"] = "unknown mode \(mode)"
    }
    finish()
    exit(0)
}
'''

INFO_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>phase8probe</string>
<key>CFBundleIdentifier</key><string>com.kgalligan.reelcut.phase8probe</string>
<key>CFBundleName</key><string>Phase8Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
"""


def build_probe():
    """Compiles the probe if it is stale, exactly as `harness/build.sh` does —
    the same swiftc line, the same staleness rule — into an `.app` bundle,
    which one mode needs and the rest merely tolerate (the script's header
    says why).

    Returns the binary's path, or None with the reason, which every section
    scores as a FAILURE rather than exiting."""
    macos = os.path.join(BUNDLE, "Contents", "MacOS")
    resources = os.path.join(BUNDLE, "Contents", "Resources")
    os.makedirs(macos, exist_ok=True)
    os.makedirs(resources, exist_ok=True)
    with open(os.path.join(BUNDLE, "Contents", "Info.plist"), "w") as f:
        f.write(INFO_PLIST)
    binary = os.path.join(macos, "phase8probe")
    entry = os.path.join(PROBE, "main.swift")
    # Written only when it CHANGED, or the staleness check below rebuilds on
    # every run.
    if not os.path.exists(entry) or open(entry).read() != PROBE_SOURCE:
        with open(entry, "w") as f:
            f.write(PROBE_SOURCE)
    fonts = os.path.join(resources, "Fonts")
    if not os.path.isdir(fonts) or os.path.getmtime(FONTS) > os.path.getmtime(fonts):
        shutil.rmtree(fonts, ignore_errors=True)
        shutil.copytree(FONTS, fonts)
    placeholder = os.path.join(resources, "Blank.mp4")
    if not os.path.exists(placeholder):
        shutil.copy2(PLACEHOLDER, placeholder)
    sources = sorted(
        os.path.join(SOURCES, name) for name in os.listdir(SOURCES)
        if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    if os.path.exists(binary) and all(
        os.path.getmtime(f) < os.path.getmtime(binary) for f in sources + [entry, lib]
    ):
        print(f"probe: {binary} (up to date)")
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
        tail = [line for line in result.stderr.strip().splitlines()[-4:] if line.strip()]
        return None, (f"swiftc exited {result.returncode}:\n      "
                      + "\n      ".join(errors[:6] or tail or ["(no output)"]))
    print(f"probe: {binary} (built in {time.time() - start:.1f} s)")
    return binary, None


def build_metal_probe(binary):
    """Section 9's bundle: the SAME binary again, beside a `default.metallib`
    compiled from the project's own `Compositor.metal`.

    **A second bundle rather than a metallib in the first one**, and the
    reason is section 5. `MetalRenderer.init?()` asks
    `makeDefaultLibrary(bundle:)` for the shader, so without a metallib every
    Metal render in this process fails and the compositor draws nothing —
    which is the state sections 3, 4 and 5 were measured in, and section 5
    records `displayedPixelBuffer` nil for both player layers as an honest
    limit of exactly that state. Putting a working shader into the bundle
    those modes run from would change what they are reading about, for a
    feature they say nothing about. Two bundles cost one `cp` and one
    `xcrun metal`, and the binary is compiled once either way.

    Returns (binary, None) or (None, the reason), which section 9 scores as a
    FAILURE rather than exiting."""
    if binary is None:
        return None, "the probe did not build"
    macos = os.path.join(METAL_BUNDLE, "Contents", "MacOS")
    resources = os.path.join(METAL_BUNDLE, "Contents", "Resources")
    os.makedirs(macos, exist_ok=True)
    os.makedirs(resources, exist_ok=True)
    with open(os.path.join(METAL_BUNDLE, "Contents", "Info.plist"), "w") as f:
        f.write(INFO_PLIST.replace("phase8probe", "phase8metal")
                .replace("Phase8Probe", "Phase8Metal"))
    copy = os.path.join(macos, "phase8metal")
    if not os.path.exists(copy) or os.path.getmtime(copy) < os.path.getmtime(binary):
        shutil.copy2(binary, copy)
    # `CompositionBuilder.addPlaceholderIfNeeded` gives a timeline of nothing
    # but shapes a video track to tick against, and it reads this out of the
    # bundle. Without it every fixture below renders no frame at all.
    placeholder = os.path.join(resources, "Blank.mp4")
    if not os.path.exists(placeholder):
        shutil.copy2(PLACEHOLDER, placeholder)
    library = os.path.join(resources, "default.metallib")
    if not os.path.exists(library) or os.path.getmtime(library) < os.path.getmtime(SHADER):
        result = subprocess.run(
            ["xcrun", "-sdk", "macosx", "metal", "-o", library, SHADER],
            capture_output=True, text=True)
        if result.returncode != 0 or not os.path.exists(library):
            tail = [line for line in result.stderr.strip().splitlines() if ": error:" in line]
            return None, ("`xcrun metal` exited %d:\n      " % result.returncode
                          + "\n      ".join(tail[:6] or ["(no output)"]))
        print(f"probe: {os.path.relpath(library, ROOT)} (compiled)")
    return copy, None


PROBE_RUNS = []


def run_probe(binary, tag, request, timeout=180, activate=False):
    """One probe invocation. Answers (answer, error); a probe that crashed or
    wrote nothing answers (None, its output), which every caller turns into
    failures BY NAME rather than into a shorter list.

    `activate=True` launches the bundle through `open -W -n` instead of
    exec'ing the binary, and that is the difference between a measurement and
    a coin toss: a bare exec of an `.app`'s executable is handed the keyboard
    focus by the window server about one time in three (measured, 30 retries
    over three seconds and never once), while every `open` of the same bundle
    activated. It is used by the `dispatch` mode alone, which is the only one
    that needs a key window at all."""
    if binary is None:
        return None, "the probe did not build"
    request_path = os.path.join(CHROME, f"request-{tag}.json")
    out = os.path.join(CHROME, f"answer-{tag}.json")
    if os.path.exists(out):
        os.remove(out)
    with open(request_path, "w") as f:
        json.dump(request, f, indent=2)
    command = (["open", "-W", "-n", BUNDLE, "--args", request_path, out] if activate
               else [binary, request_path, out])
    start = time.time()
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        PROBE_RUNS.append((tag, False, timeout))
        return None, f"the probe did not return within {timeout} s"
    elapsed = time.time() - start
    if not os.path.exists(out):
        PROBE_RUNS.append((tag, False, elapsed))
        return None, (result.stdout + result.stderr).strip()[:600] or "no answer was written"
    with open(out) as f:
        answer = json.load(f)
    PROBE_RUNS.append((tag, True, elapsed))
    print(f"  probe {tag}: {elapsed:.1f} s")
    return answer, None


# ---------------------------------------------------------------------------
# PNG, in pure Python: chunks, zlib, the five filters. (phase7_chrome.py's,
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


WHITE = (255, 255, 255, 255)


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

    def ink_box(self, x0, x1, y0, y1):
        """The bounding box, in POINTS, of everything that is not the panel's
        white ground inside a rectangle — the instrument section 7 measures a
        control's drawn extent with."""
        s = self.scale
        xs, ys, count = [], [], 0
        for y in range(int(y0 * s), min(int(y1 * s), self.height)):
            for x in range(int(x0 * s), min(int(x1 * s), self.width)):
                if self.pixel(x, y) != WHITE:
                    xs.append(x)
                    ys.append(y)
                    count += 1
        if not xs:
            return None
        return (min(xs) / s, (max(xs) + 1) / s, min(ys) / s, (max(ys) + 1) / s, count)

    def ink_columns(self, y0, y1, x0, x1):
        """Runs of columns holding ink, in points — how the three controls of
        the band's second line are told apart without a colour being written
        down anywhere."""
        s = self.scale
        runs, start = [], None
        for xpx in range(int(x0 * s), int(x1 * s)):
            ink = any(self.pixel(xpx, y) != WHITE
                      for y in range(int(y0 * s), min(int(y1 * s), self.height)))
            if ink and start is None:
                start = xpx
            if not ink and start is not None:
                runs.append((start / s, xpx / s))
                start = None
        if start is not None:
            runs.append((start / s, x1))
        return runs

    def full_width_rules(self, y0, y1, x0=CONTENT_X0, x1=CONTENT_X1, fraction=0.999):
        """Every scanline between `y0` and `y1` that is inked right across the
        panel's content — the hairlines `BarView` draws at a band's foot. In
        points, and de-duplicated into RUNS, since a 1 pt rule is two rows at
        the backing scale.

        The threshold is EVERY pixel and not most of them, which is what tells
        a rule from a control: the search field spans the same width, but its
        bezel is rounded, so its top scanline misses the corner pixels (564 of
        568, measured) where a bar's hairline runs edge to edge (568)."""
        s = self.scale
        total = int(x1 * s) - int(x0 * s)
        hits = []
        for ypx in range(int(y0 * s), min(int(y1 * s), self.height)):
            inked = sum(1 for x in range(int(x0 * s), int(x1 * s))
                        if self.pixel(x, ypx) != WHITE)
            if inked > fraction * total:
                hits.append(ypx)
        runs = []
        for ypx in hits:
            if runs and ypx == runs[-1][1] + 1:
                runs[-1][1] = ypx
            else:
                runs.append([ypx, ypx])
        return [(a / s, (b + 1) / s) for a, b in runs]


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
            f"      x {x0 / scale:.1f}–{(x1 + 1) / scale:.1f}"
            f" y {y0 / scale:.1f}–{(y1 + 1) / scale:.1f} pt  ({n} px)")
    if len(boxes) > limit:
        lines.append(f"      … and {len(boxes) - limit} more clusters")
    return "\n".join(lines)


def inside(pixels, rect, scale, slop=0):
    return [p for p in pixels if rect.contains(p[0], p[1], scale, slop)]


def outside(pixels, rects, scale, slop=0):
    return [p for p in pixels if not any(r.contains(p[0], p[1], scale, slop) for r in rects)]


def rows_equal(a, b, y0, y1, x0, x1):
    """Whether two renders are byte-identical over a rectangle — the byte
    comparison a "nothing else moved" claim is made of."""
    s = a.scale
    ch = a.channels
    for y in range(int(y0 * s), min(int(y1 * s), a.height)):
        if a.rows[y][int(x0 * s) * ch:int(x1 * s) * ch] \
                != b.rows[y][int(x0 * s) * ch:int(x1 * s) * ch]:
            return False
    return True


# ---------------------------------------------------------------------------
# The checks.

RESULTS = []
SKIPS = []


def check(name, ok, detail=""):
    RESULTS.append(bool(ok))
    print(f"  {'PASS' if ok else 'FAIL'}: {name}")
    if detail:
        print(detail if detail.startswith("      ") else "      " + detail)


def skip(name, reason):
    """A row host state has put out of reach. It is NAMED and counted and it
    is not a pass: it never reaches `RESULTS`, so the score below is over the
    rows that were actually measured (`recording_proof.py`'s rule, and
    `preview_refresh_probe.py`'s)."""
    SKIPS.append(name)
    print(f"  SKIP: {name}")
    print(f"      {reason}")


def console_locked():
    """Is the console locked? Host state is a proof INPUT, read and never
    assumed (`recording_proof.py`). A process on a locked console cannot
    activate, so it has neither a key window nor a main one, and section 4 —
    the only section that needs either — skips those six readings by name.
    The reading is `preview_refresh_probe.py`'s and
    `preview_validity_probe.py`'s, copied like every other helper here so one
    script can be run without the others."""
    out = subprocess.run(["ioreg", "-n", "Root", "-d1", "-a"],
                         capture_output=True, text=True).stdout
    marker = out.find("<key>IOConsoleLocked</key>")
    return marker >= 0 and out[marker:marker + 60].find("<true/>") >= 0


def same_file(a, b):
    if not (os.path.exists(a) and os.path.exists(b)):
        return False
    with open(a, "rb") as fa, open(b, "rb") as fb:
        return fa.read() == fb.read()


def gcd(a, b):
    while b:
        a, b = b, a % b
    return a


def find_item(items, title):
    return next((i for i in items if i["title"] == title), None)


def submenu_items(menu, title):
    item = find_item(menu.get("items", []), title)
    return (item or {}).get("submenu", {}).get("items", [])


# ---------------------------------------------------------------------------
# Section 9's readings. A colour class's coverage and bounding box arrive as
# FRACTIONS of the destination, so "the same picture at a different
# resolution" is a comparison of numbers and never of pixel counts — 480 x 270
# holds a sixteenth of 1920 x 1080's pixels and the same picture.
#
# Two tolerances, both because a reduced render resamples an edge and neither
# large enough to hide a defect this section is about. A BOX may move by one
# and a half DESTINATION pixels: an edge that lands on a pixel centre at Full
# lands between two at Quarter, and the biggest such move measured in this
# fixture set is half a pixel. COVERAGE may move by 0.4 % of the frame, where
# the same edges cost at most 0.1 %. The defects, for scale: a nest clip
# rectangle at Half came back with its box moved by an eighth of the frame and
# its coverage 56 % out; a shadow moved by a third of the frame; and a
# dissolve's correction went from a quarter of the frame to none of it.
BOX_SLOP = 1.5
COVERAGE_SLOP = 0.004


def measurement(answer, tag, quality, klass):
    """One colour class of one render, or None."""
    for row in (answer or {}).get("renders", []):
        if row.get("tag") == tag and row.get("quality") == quality:
            box = (row.get("classes") or {}).get(klass)
            if box is None:
                return None
            return dict(box, width=row.get("width", 1), height=row.get("height", 1))
    return None


def placed(answer, tag, quality, klass, rect, coverage=None):
    """(ok, detail) — whether a class of pixel sits where the fixture's own
    arithmetic says it must, as a fraction of the frame."""
    box = measurement(answer, tag, quality, klass)
    if box is None:
        return False, f"{tag} at quality {quality}: no {klass} measurement"
    if not box["count"]:
        return False, f"{tag} at quality {quality}: {klass} is EMPTY"
    got = (box["x0"], box["y0"], box["x1"], box["y1"])
    tol = (BOX_SLOP / box["width"], BOX_SLOP / box["height"]) * 2
    ok = all(abs(a - b) <= t for a, b, t in zip(got, rect, tol))
    if coverage is not None:
        ok = ok and abs(box["coverage"] - coverage) <= COVERAGE_SLOP
    detail = (f"{tag} q{quality} {box['width']}x{box['height']}: {klass} "
              f"x {got[0]:.4f}…{got[2]:.4f} y {got[1]:.4f}…{got[3]:.4f} "
              f"coverage {box['coverage']:.4f}  wanted x {rect[0]:.4f}…{rect[2]:.4f} "
              f"y {rect[1]:.4f}…{rect[3]:.4f}"
              + (f" coverage {coverage:.4f}" if coverage is not None else ""))
    return ok, detail


def unlit(answer, tag, quality, klass):
    """(ok, detail) — whether a class of pixel is absent altogether."""
    box = measurement(answer, tag, quality, klass)
    if box is None:
        return False, f"{tag} at quality {quality}: no {klass} measurement"
    return not box["count"], f"{tag} q{quality}: {box['count']} {klass} px"


def hidden(answer, tag, quality, klass, rect):
    """(ok, detail) — whether a class of pixel is either absent or confined to
    within a destination pixel of `rect`'s edge.

    The card's own edges land on pixel BOUNDARIES at all three sizes, so what
    this actually measures is zero shadow pixels — but the slack is kept and
    is not a fudge. A card whose edge falls on a pixel CENTRE instead loses
    that row to the top-left fill rule while the mask, sampled half a texel
    away, answers 0.5: measured, with this fixture centred on the canvas, one
    row of 100 px at Quarter, 0.08 % of the frame. That is the whole cost of a
    resampled edge, against the 22 % slab a destination-space sample puts in
    open canvas."""
    box = measurement(answer, tag, quality, klass)
    if box is None:
        return False, f"{tag} at quality {quality}: no {klass} measurement"
    if not box["count"]:
        return True, f"{tag} q{quality}: no {klass} px at all"
    sx, sy = BOX_SLOP / box["width"], BOX_SLOP / box["height"]
    ok = (box["x0"] >= rect[0] - sx and box["x1"] <= rect[2] + sx
          and box["y0"] >= rect[1] - sy and box["y1"] <= rect[3] + sy
          and box["coverage"] < 0.002)
    return ok, (f"{tag} q{quality} {box['width']}x{box['height']}: {klass} "
                f"x {box['x0']:.4f}…{box['x1']:.4f} y {box['y0']:.4f}…{box['y1']:.4f} "
                f"coverage {box['coverage']:.4f}, against the card's "
                f"x {rect[0]:.4f}…{rect[2]:.4f} y {rect[1]:.4f}…{rect[3]:.4f}")


# ---------------------------------------------------------------------------


def main():
    os.makedirs(CHROME, exist_ok=True)
    os.makedirs(PROBE, exist_ok=True)
    harness = build_harness()
    probe, probe_error = build_probe()
    packages = {name: write_package(name, spec) for name, spec in PACKAGES.items()}
    print(f"packages: {len(packages)} written under {os.path.relpath(WORK, ROOT)}/")

    def png(tag):
        return os.path.join(CHROME, tag + ".png")

    print("\n0. the instruments")
    check("the probe builds — an instrument that will not compile is a FAILURE here, never "
          "an exit: it must not take the rest of the score with it",
          probe is not None, probe_error or os.path.relpath(BUNDLE, ROOT))
    check("…and the app bundle around it — `NSApp.target(forAction:)` searches the KEY "
          "window's chain, a process that cannot ACTIVATE has no key window, and activation "
          "needs a bundle (measured: a bare swiftc binary under `.prohibited`, `.accessory` "
          "and `.regular` alike reports both `keyWindow` and `mainWindow` nil)",
          probe is not None and os.path.isdir(BUNDLE)
          and os.path.exists(os.path.join(BUNDLE, "Contents", "Info.plist")),
          os.path.relpath(BUNDLE, ROOT))

    # ------------------------------------------------------------------
    # 1. The aspect rule.
    print("\n1. PreviewQuality's aspect rule (8a)")
    canvases = [
        [1920, 1080], [1280, 720], [3840, 2160], [1080, 1920], [999, 666],
        [1001, 667], [100, 100], [640, 360], [1366, 768], [720, 1280], [4096, 2160],
    ]
    quality, error = run_probe(probe, "quality", {
        "mode": "quality", "canvases": canvases,
        "stored": ["absent", 0, 1, 2, 5, -1, "half"],
    })
    if quality is None:
        check("the quality probe answered", False, error or "")
        quality = {}
    rows = {(r["w"], r["h"]): r["answers"] for r in quality.get("sizes", [])}

    check("the three rows are Full / Half / Quarter at raw values 0, 1, 2 with divisors "
          "1, 2, 4 — the raw value IS the menu tag, so this is the contract the submenu and "
          "the validator both read",
          [(c["raw"], c["title"], c["divisor"]) for c in quality.get("cases", [])]
          == [(0, "Full", 1), (1, "Half", 2), (2, "Quarter", 4)],
          str(quality.get("cases")))

    exact = []
    for (w, h), answers in rows.items():
        for a in answers:
            # INTEGER cross-multiply. A float tolerance would pass against
            # 501 x 333 on a 640 x 360 canvas, which is the exact size the
            # phase measured moving every drag handle in the frame.
            if a["w"] * h != a["h"] * w:
                exact.append(f"{w}x{h} row {a['raw']} → {a['w']}x{a['h']}")
    check("every answer carries the canvas's aspect EXACTLY, by integer cross-multiply over "
          f"{len(rows)} canvases x 3 rows — never a float tolerance, which is what would let "
          "a 640x360 canvas come back 501x333 and move every drag handle "
          "(`PreviewCanvasView` maps them through `videoRect`, which is the BUFFER's aspect)",
          rows and not exact, "; ".join(exact) or f"{len(rows) * 3} answers, all exact")

    finer = []
    for (w, h), answers in rows.items():
        for a in answers:
            if a["w"] * a["divisor"] < w or a["h"] * a["divisor"] < h:
                finer.append(f"{w}x{h} row {a['raw']} → {a['w']}x{a['h']}")
    check("no answer is FINER than its row asked for — `ceil` rounds toward a coarser "
          "preview, so the picture is never worse than the menu promised",
          rows and not finer, "; ".join(finer) or "every answer ≥ canvas/divisor")

    bigger = [f"{w}x{h} row {a['raw']} → {a['w']}x{a['h']}"
              for (w, h), answers in rows.items() for a in answers
              if a["w"] > w or a["h"] > h]
    check("…and none is BIGGER than the canvas: `m` is clamped at `g`, so Full is the "
          "ceiling and a coarser row can only come down",
          rows and not bigger, "; ".join(bigger) or "every answer ≤ the canvas")

    steps = []
    for (w, h), answers in rows.items():
        g = gcd(w, h)
        for a in answers:
            m = max(1, -(-g // a["divisor"]))
            if (a["w"], a["h"]) != (w // g * m, h // g * m):
                steps.append(f"{w}x{h} row {a['raw']} → {a['w']}x{a['h']}, wanted "
                             f"{w // g * m}x{h // g * m}")
    check("every answer is exactly `m · (w/g, h/g)` for `g = gcd(w, h)` and "
          "`m = ceil(g / divisor)` — the rule re-derived here rather than read off the "
          "answers, so this compares two independent statements of it",
          rows and not steps, "; ".join(steps) or f"{len(rows) * 3} answers")

    coprime = rows.get((1001, 667), [])
    check("1001 x 667 is COPRIME, so every row comes back at FULL size — the conservative "
          "fallback: a preview that is merely no faster is a disappointment, where handles "
          "that moved would be a defect",
          len(coprime) == 3 and all((a["w"], a["h"]) == (1001, 667) for a in coprime),
          str([(a["w"], a["h"]) for a in coprime]))

    check("1920 x 1080 halves and quarters EXACTLY (960x540, 480x270), because 2 and 4 both "
          "divide its gcd of 120 — the case a naive `(w/2, h/2)` also gets right, which is "
          "why it cannot be the only canvas in the list",
          [(a["w"], a["h"]) for a in rows.get((1920, 1080), [])]
          == [(1920, 1080), (960, 540), (480, 270)],
          str([(a["w"], a["h"]) for a in rows.get((1920, 1080), [])]))

    odd = rows.get((999, 666), [])
    check("999 x 666 (gcd 333) gives 501 x 334 at Half — 0.15 % ABOVE half and exactly 3:2 — "
          "which is the whole point: the answer is odd, it is not the naive half, and it is "
          "the canvas's aspect to the integer",
          len(odd) == 3 and (odd[1]["w"], odd[1]["h"]) == (501, 334)
          and odd[1]["w"] * 666 == odd[1]["h"] * 999,
          str([(a["w"], a["h"]) for a in odd]))

    naive_wrong = [f"{w}x{h}" for (w, h), answers in rows.items()
                   if any((a["w"], a["h"]) != (w // a["divisor"], h // a["divisor"])
                          for a in answers)]
    check("…and the list CONTAINS canvases a naive `(w/divisor, h/divisor)` gets wrong — "
          "named here so the mutation pass has something to kill, and so nobody trims the "
          "list back to a single 16:9 fixture that every wrong rule also gets right",
          len(naive_wrong) >= 3, "the naive fraction differs on: " + ", ".join(naive_wrong))

    check("100 x 100 (gcd 100) gives 50x50 and 25x25, and a square canvas stays square",
          [(a["w"], a["h"]) for a in rows.get((100, 100), [])]
          == [(100, 100), (50, 50), (25, 25)],
          str([(a["w"], a["h"]) for a in rows.get((100, 100), [])]))

    portrait = rows.get((1080, 1920), [])
    check("a PORTRAIT canvas is not a special case: 1080 x 1920 gives 540x960 and 270x480, "
          "the transpose of the landscape answers",
          [(a["w"], a["h"]) for a in portrait] == [(1080, 1920), (540, 960), (270, 480)],
          str([(a["w"], a["h"]) for a in portrait]))

    whole = all(a["wIsWhole"] and a["hIsWhole"]
                for answers in rows.values() for a in answers)
    check("every answer is a WHOLE number of pixels — the arithmetic is integer and the "
          "CGSize carries no fraction, which is what lets the cross-multiply above be exact",
          rows and whole)

    stored = {str(r["given"]): r["raw"] for r in quality.get("stored", [])}
    check("`stored()` reads Full when the key is ABSENT — the only value that cannot "
          "surprise somebody who does not know the setting exists",
          stored.get("absent") == 0, str(stored))
    check("…and reads back 0, 1 and 2 as Full, Half and Quarter",
          (stored.get("0"), stored.get("1"), stored.get("2")) == (0, 1, 2), str(stored))
    check("…and a number OUTSIDE the enum reads Full rather than trapping — 5 is what a "
          "downgrade after a future fourth row would leave behind, and -1 is what a "
          "corrupted plist can hold",
          stored.get("5") == 0 and stored.get("-1") == 0, str(stored))
    check("…and so does a STRING under the key, which `integer(forKey:)` reads as 0 and "
          "which `object(forKey:) != nil` alone would have let through",
          stored.get("half") == 0, str(stored))
    check("`store()` and `stored()` round-trip all three rows",
          [(r["stored"], r["read"]) for r in quality.get("roundTrip", [])]
          == [(0, 0), (1, 1), (2, 2)], str(quality.get("roundTrip")))
    check("…and removing the key puts it back to Full, so the round trip left nothing "
          "behind on this machine",
          quality.get("afterRemoval") == 0
          and quality.get("defaultsKey") == "ReelcutPreviewQuality",
          f"{quality.get('afterRemoval')}, key {quality.get('defaultsKey')}")

    # ------------------------------------------------------------------
    # 2. The View menu and the validator.
    print("\n2. the View menu (8a)")
    menu, error = run_probe(probe, "menu", {"mode": "menu", "package": packages["six"]})
    if menu is None:
        check("the menu probe answered", False, error or "")
        menu = {}
    view = submenu_items(menu.get("menu", {}), "View")
    bits = menu.get("modifierBits", {})
    check("the View menu exists and is not empty", len(view) > 3, f"{len(view)} rows")
    check("it ENDS with a separator, the Preview Quality submenu and Preview Window — a "
          "group of their own, because both are about the PREVIEW rather than about the "
          "editor's own panes",
          len(view) >= 3 and view[-3]["separator"]
          and view[-2].get("submenu", {}).get("title") == "Preview Quality"
          and view[-1]["title"] == "Preview Window",
          " | ".join(r["title"] or "(separator)" for r in view[-4:]))

    quality_rows = view[-2].get("submenu", {}).get("items", []) if len(view) >= 2 else []
    check("the submenu's rows ARE `PreviewQuality.allCases`' titles, in order — the enum "
          "is the single source, so the menu cannot list a quality it has not got or spell "
          "one differently from the checkmark that validates it",
          [r["title"] for r in quality_rows] == menu.get("titles"),
          f"{[r['title'] for r in quality_rows]} against {menu.get('titles')}")
    check("…each carrying its RAW VALUE as its tag and `setPreviewQuality:` as its action",
          [(r["tag"], r["action"]) for r in quality_rows]
          == [(0, "setPreviewQuality:"), (1, "setPreviewQuality:"), (2, "setPreviewQuality:")],
          str([(r["tag"], r["action"]) for r in quality_rows]))
    check("…and NO key equivalents: every bare letter belongs to the editor's own `keyDown`",
          all(r["key"] == "" for r in quality_rows),
          str([r["key"] for r in quality_rows]))

    window_row = view[-1] if view else {}
    check("Preview Window takes ⇧⌘P — the letter and BOTH modifier bits read off `NSEvent` "
          "rather than written down here, and the two that must not be set checked too",
          window_row.get("key") == "p"
          and window_row.get("modifiers") == bits.get("command", 0) + bits.get("shift", 0),
          f"key {window_row.get('key')!r} modifiers {window_row.get('modifiers')} against "
          f"command|shift = {bits.get('command', 0) + bits.get('shift', 0)}")
    check("…and its action is `togglePreviewWindow:`, a TOGGLE rather than an opener",
          window_row.get("action") == "togglePreviewWindow:", str(window_row.get("action")))

    validation = menu.get("validation", [])
    check("the validator ENABLES the item at every quality — a quality is a property of the "
          "preview and not of the timeline, so there is nothing to refuse on an empty "
          "project",
          len(validation) == 3
          and all(s["enabled"] is True for row in validation for s in row["states"]),
          str([[s["enabled"] for s in row["states"]] for row in validation]))
    marks = [[s["on"] for s in row["states"]] for row in validation]
    check("…and puts the checkmark on EXACTLY the stored row, at each of the three — a "
          "validator that answered for a tag it does not own would light two at once",
          marks == [[True, False, False], [False, True, False], [False, False, True]],
          str(marks))
    check("the arm answers nil for a selector that is not its own — the arm is load-bearing "
          "in `validateUserInterfaceItem`'s chain, and one that answered `true` "
          "unconditionally would enable every command below it",
          menu.get("armForAnotherSelector") is None,
          repr(menu.get("armForAnotherSelector")))
    check("`setPreviewQuality:` refuses a tag outside the enum and a nil sender, leaving "
          "the setting where it was (it beeps — the one sound this script makes)",
          menu.get("afterBadTag") == 1 and menu.get("afterNilSender") == 1,
          f"after tag 7: {menu.get('afterBadTag')}, after nil: {menu.get('afterNilSender')}")

    # ------------------------------------------------------------------
    # 3. The panel contract.
    print("\n3. the preview window's panel contract (8b)")
    panel_answer, error = run_probe(probe, "panel", {
        "mode": "panel", "package": packages["six"]})
    if panel_answer is None:
        check("the panel probe answered", False, error or "")
        panel_answer = {}
    p = panel_answer.get("panel", {})
    check("⇧⌘P makes a window where there was none",
          panel_answer.get("beforeToggle", {}).get("exists") is False
          and bool(p) and panel_answer.get("isShowing") is True,
          f"class {p.get('class')}, showing {panel_answer.get('isShowing')}")
    check("it is an `NSPanel`, and `canBecomeMain` is FALSE — which is the whole of section "
          "4 below: AppKit resolves a nil-target action through the MAIN window's chain, so "
          "a window that cannot become main leaves the editor's commands alive",
          p.get("isPanel") is True and p.get("canBecomeMain") is False,
          f"{p.get('class')}, canBecomeMain {p.get('canBecomeMain')}, "
          f"canBecomeKey {p.get('canBecomeKey')}")
    check("…and `canBecomeKey` is TRUE, so it still takes ⌘W and the bare transport keys",
          p.get("canBecomeKey") is True, str(p.get("canBecomeKey")))
    check("`hidesOnDeactivate` is FALSE — the panel default is TRUE (measured), which would "
          "make a preview on a second display vanish the moment the person switched apps",
          p.get("hidesOnDeactivate") is False, str(p.get("hidesOnDeactivate")))
    check("it is excluded from the Windows menu — `NSApp.windowsMenu` is set, so without "
          "this the menu would list the preview as well as View's own item",
          p.get("isExcludedFromWindowsMenu") is True,
          str(p.get("isExcludedFromWindowsMenu")))
    check("`isReleasedWhenClosed` is FALSE — the controller outlives the window's closing, "
          "since ⇧⌘P shows it again",
          p.get("isReleasedWhenClosed") is False, str(p.get("isReleasedWhenClosed")))
    check("its collection behaviour contains `.fullScreenPrimary`, so it can fill a second "
          "display outright although it cannot become main",
          p.get("fullScreenPrimary") is True, str(p.get("collectionBehavior")))
    check("its frame autosave name is the FIXED one, never per-document — a per-document "
          "name would mint a defaults key per project",
          p.get("frameAutosaveName") == panel_answer.get("autosaveConstant")
          == "ReelcutPreviewWindow",
          f"{p.get('frameAutosaveName')!r} against "
          f"{panel_answer.get('autosaveConstant')!r}; re-set answered "
          f"{panel_answer.get('autosaveRetake')} and read back "
          f"{panel_answer.get('autosaveAfterRetake')!r}")
    check("…which is the name the offscreen harness pins, spelled `\"NSWindow Frame \" + "
          "name` — so this constant and `pinDefaults`' key cannot drift apart",
          "NSWindow Frame " + str(panel_answer.get("autosaveConstant"))
          == "NSWindow Frame ReelcutPreviewWindow")
    check("the title carries the document's name, so two open projects' previews are told "
          "apart", p.get("title") == f"{panel_answer.get('documentName')} — Preview",
          f"{p.get('title')!r}")
    check("it is titled, closable and resizable, and its minimum size is 320 x 200",
          p.get("styleMaskTitled") and p.get("styleMaskClosable") and p.get("styleMaskResizable")
          and (p.get("minWidth"), p.get("minHeight")) == (320, 200),
          f"min {p.get('minWidth')}x{p.get('minHeight')}")
    check("the EDITOR's window is not a panel and CAN become main — the contrast this whole "
          "section is about, measured in the same process",
          panel_answer.get("editorWindow", {}).get("isPanel") is False
          and panel_answer.get("editorWindow", {}).get("canBecomeMain") is True,
          str(panel_answer.get("editorWindow", {}).get("class")))

    check("a second ⇧⌘P HIDES the panel and keeps the controller; a third shows it again — "
          "the toggle Snapping and Safe Areas set the shape for",
          panel_answer.get("afterSecond") == {"isShowing": False, "sameController": True}
          and panel_answer.get("afterThird") == {"isShowing": True, "sameController": True},
          f"{panel_answer.get('afterSecond')} then {panel_answer.get('afterThird')}")
    check("the menu item's checkmark follows the PANEL and not the controller: on while "
          "showing, off while hidden, enabled both times",
          panel_answer.get("validateShowing") == {"enabled": True, "on": True}
          and panel_answer.get("validateHidden") == {"enabled": True, "on": False},
          f"{panel_answer.get('validateShowing')} then {panel_answer.get('validateHidden')}")
    check("…and that arm too answers nil for a selector that is not its own",
          panel_answer.get("armForAnotherSelector") is None,
          repr(panel_answer.get("armForAnotherSelector")))
    check("the EDITOR window closing closes the panel — the deterministic door, rather than "
          "waiting for this object to be deallocated: a window whose controller has gone "
          "while it is still on screen is nobody's",
          panel_answer.get("beforeEditorClose") is True
          and panel_answer.get("afterEditorClose") is False,
          f"showing {panel_answer.get('beforeEditorClose')} → "
          f"{panel_answer.get('afterEditorClose')}")

    # ------------------------------------------------------------------
    # 4. The dispatch guarantee.
    print("\n4. the dispatch guarantee the panel exists for (8b)")
    print("      (this mode ACTIVATES the probe and shows two windows for about a second — "
          "it is\n       the only way there is a key window to measure at all)")
    # **This mode is the one instrument here another PROCESS can spoil**, and
    # it is asked up to three times for that reason and no other. A second app
    # activating during the two seconds it runs takes the keyboard focus, and
    # with no key window `target(forAction:)` answers NONE — for a panel and
    # for a plain window alike, so a build with the panel swapped for a plain
    # window would read exactly the same. Measured: a run of this script had
    # its dispatch mode deactivated by an unrelated app launching. The retry
    # is on the PRECONDITION alone (the app active, the editor key and main);
    # once that holds, the first answer is the one scored and a second
    # attempt is never made, so nothing here re-rolls a failing GUARANTEE.
    # The third spoiler is the one not worth retrying: a process that cannot
    # activate can never satisfy the precondition, so a locked console is
    # asked ONCE and the six readings that need the focus are skipped below.
    locked = console_locked()
    if locked:
        print("      (the console is LOCKED, so the probe is asked once and the six readings "
              "that\n       need the keyboard focus are skipped by name)")
    dispatch, error, attempts, preconditions = None, None, 0, []
    for attempts in range(1, 2 if locked else 4):
        dispatch, error = run_probe(probe, "dispatch", {
            "mode": "dispatch", "package": packages["dispatch"]}, timeout=120, activate=True)
        first = next((s for s in (dispatch or {}).get("stages", [])
                      if s["stage"] == "editor alone"), {})
        preconditions.append(
            f"attempt {attempts}: active {first.get('appActive')}, "
            f"key {first.get('keyWindow')!r}, main {first.get('mainWindow')!r}")
        if (first.get("appActive") is True and first.get("editorIsKey") is True
                and first.get("editorIsMain") is True):
            break
    if dispatch is None:
        check("the dispatch probe answered", False, error or "")
        dispatch = {}
    stages = {s["stage"]: s for s in dispatch.get("stages", [])}
    alone, preview = stages.get("editor alone", {}), stages.get("preview key", {})
    # Rule 3 of the mutation rules, applied to an instrument: assert the
    # precondition, then act on it. Without an ACTIVE app there is no key
    # window at all and every target below is NONE — for a panel and for a
    # plain window alike — so the answer would be a passing lie.
    ready = (alone.get("appActive") is True and alone.get("editorIsKey") is True
             and alone.get("editorIsMain") is True)

    def focused(name, ok, detail=""):
        """One of the six rows whose precondition is a key window. On a locked
        console it is not askable, and a row that is not askable is skipped by
        name rather than scored against an answer nothing could have given."""
        if locked:
            skip(name, "the console is locked, and a process that cannot activate has "
                       "neither a key window nor a main one")
        else:
            check(name, ok, detail)

    focused("PRECONDITION: the probe activated and the editor is both key and main before the "
            "panel is opened — without this every reading below is NONE for a panel and a "
            "plain window alike, and the section would pass against both",
            ready,
            "; ".join(preconditions)
            + "; re-asked for the focus "
            + f"{alone.get('refocusEditor', dispatch.get('refocusEditor'))}"
            + f"/{dispatch.get('refocusPreview')} times before the two readings")
    check("PRECONDITION: nothing put a SHEET up over the editor — a sheet is a window and "
          "takes KEY, which is what the six-file fixture's deliberately absent files did "
          "through `offerRelinkIfNeeded` before this mode was given a shape-clip package "
          "of its own",
          dispatch.get("attachedSheet") is False, f"attachedSheet {dispatch.get('attachedSheet')}")
    focused("with the editor alone, ⌘E / ⌘T / ⌘0 all resolve to the editor's view controller",
            ready and set(alone.get("targets", {}).values()) == {"EditorViewController"},
            str(alone.get("targets")))
    focused("PRECONDITION: opening the preview makes the PANEL key",
            ready and preview.get("secondIsKey") is True and dispatch.get("panelIsPanel") is True,
            f"key {preview.get('keyWindow')!r}, class {preview.get('secondClass')}")
    focused("…and leaves the EDITOR main, which a titled `NSWindow` would not: measured by the "
            "build lane, a plain window becomes key AND main and every target below goes NONE",
            ready and preview.get("secondIsMain") is False
            and preview.get("editorIsMain") is True,
            f"panel isMain {preview.get('secondIsMain')}, editor isMain "
            f"{preview.get('editorIsMain')}, main window {preview.get('mainWindow')!r}")
    focused("THE GUARANTEE: with the panel key, ⌘E Export…, ⌘T Split and ⌘0 Zoom to Fit STILL "
            "resolve to the editor's controller — nothing forwards them, the panel simply "
            "never became main",
            ready and set(preview.get("targets", {}).values()) == {"EditorViewController"},
            str(preview.get("targets")))
    focused("…and the File menu's Export… item validates ENABLED with the preview focused, "
            "which is the thing a person would actually notice going dead. Its own two "
            "preconditions are reported beside it — the controller still has its document "
            "(it is a WEAK reference) and the project has a duration — because a `false` from "
            "either of those reads exactly like the defect this section hunts",
            ready and preview.get("exportEnabled") is True and alone.get("exportEnabled") is True,
            f"alone {alone.get('exportEnabled')}, preview key {preview.get('exportEnabled')}; "
            f"document held {preview.get('controllerHasDocument')}, duration "
            f"{preview.get('duration')} ticks")

    # ------------------------------------------------------------------
    # 5. One player, two layers.
    print("\n5. one player, two layers (8b)")
    check("the panel holds exactly ONE `AVPlayerLayer`, and it is not the editor's",
          panel_answer.get("previewLayers") == 1
          and panel_answer.get("differentLayers") is True,
          f"{panel_answer.get('previewLayers')} layers")
    check("its player is IDENTICAL to `Playback.playerLayer`'s — one player, two layers, so "
          "the two pictures cannot drift apart by construction: there is no second item, no "
          "second composition and nothing to keep in step",
          panel_answer.get("samePlayer") is True
          and panel_answer.get("editorLayerHasPlayer") is True,
          f"same player {panel_answer.get('samePlayer')}")
    check("…at `.resizeAspect`, the gravity the canvas pane uses, so the second window "
          "letterboxes the same frame rather than cropping it",
          panel_answer.get("previewGravity") == "AVLayerVideoGravityResizeAspect",
          str(panel_answer.get("previewGravity")))
    source = open(os.path.join(SOURCES, "PreviewWindowController.swift")).read()
    check("`PreviewWindowController.swift` constructs no `AVPlayer` and no "
          "`AVPlayerLayer(player:)` of its own — `Playback.makePreviewLayer()` is the one "
          "door, which is what lets `Playback.player` stay private. Read out of the source, "
          "because an identity check alone cannot see a SECOND player that happens not to "
          "be installed",
          "AVPlayer(" not in source and "AVPlayerLayer(" not in source,
          "no `AVPlayer(` or `AVPlayerLayer(` in the file")
    playback = open(os.path.join(SOURCES, "Playback.swift")).read()
    check("…and `Playback.swift` is the only place either is constructed, once each",
          playback.count("AVPlayer()") == 1 and playback.count("AVPlayerLayer(player:") == 2,
          f"{playback.count('AVPlayer()')} players, "
          f"{playback.count('AVPlayerLayer(player:')} layers "
          "(the canvas's and `makePreviewLayer`'s)")
    preview_display = panel_answer.get("previewDisplay", {})
    editor_display = panel_answer.get("editorDisplay", {})
    check("HONEST LIMIT, recorded as a reading rather than assumed: NEITHER layer is "
          "displaying anything in this process — `displayedPixelBuffer` is nil for both — "
          "so nothing here claims the two windows show the same frame. That claim needs a "
          "person at the machine; no instrument in this tree can make it",
          preview_display.get("hasDisplayedBuffer") is False
          and editor_display.get("hasDisplayedBuffer") is False,
          f"preview {preview_display.get('hasDisplayedBuffer')}, "
          f"editor {editor_display.get('hasDisplayedBuffer')}")
    check("…and the two properties a reader would reach for first say the SAME thing about "
          "both layers, which is all they can ever say: they are two views of one player, "
          "so `isReadyForDisplay` and `videoRect` cannot tell a layer that is showing the "
          "frame from one that is not. The phase's spike measured them reading TRUE and "
          "plausible for a layer with no superlayer at all; here, with no item loaded, they "
          "read false and zero for both. Either way they discriminate nothing — recorded so "
          "the next reader does not reach for them",
          preview_display.get("isReadyForDisplay")
          == editor_display.get("isReadyForDisplay")
          and preview_display.get("videoRectWidth") == editor_display.get("videoRectWidth"),
          f"preview isReadyForDisplay {preview_display.get('isReadyForDisplay')} videoRect "
          f"{preview_display.get('videoRectWidth')}x{preview_display.get('videoRectHeight')}; "
          f"editor {editor_display.get('isReadyForDisplay')} "
          f"{editor_display.get('videoRectWidth')}x{editor_display.get('videoRectHeight')}")

    # ------------------------------------------------------------------
    # 6. The Media tab's arithmetic, its pane, and the AppKit premise.
    print("\n6. the find band's arithmetic and the pane that applies it (8c)")
    entries = [
        {"id": 1, "name": "Résumé Take.mov", "duration": 3 * TICKS_PER_SECOND},
        {"id": 2, "name": "keynote.mov", "duration": 1 * TICKS_PER_SECOND},
        {"id": 3, "name": "Beta Reel.mov", "duration": 2 * TICKS_PER_SECOND},
        {"id": 4, "name": "alpha.wav", "kind": "audio", "duration": 2 * TICKS_PER_SECOND},
        {"id": 5, "name": "Cover.png", "kind": "image", "duration": 2 * TICKS_PER_SECOND},
    ]
    media_answer, error = run_probe(probe, "media", {
        "mode": "media", "package": packages["six"], "usagePackage": packages["usage"],
        "entries": entries,
        "searches": ["resume", "RESUME", "Résumé", "résumé", "KEYNOTE", "Beta Reel",
                     "Beta  Reel", "keynote ", " keynote", "", "zzz", ".mov", "wav"],
    })
    if media_answer is None:
        check("the media probe answered", False, error or "")
        media_answer = {}

    usage = {r["name"]: r for r in media_answer.get("usage", [])}
    check("the usage fixture opened through the CORE with its nest intact",
          media_answer.get("nestCount") == 1 and media_answer.get("topLevelClips") == 4
          and len(usage) == 4,
          f"{media_answer.get('nestCount')} nests, "
          f"{media_answer.get('topLevelClips')} top-level clips")
    check("`clipsUsing` counts the timeline's clips AND the nest's — the set the core "
          "refuses `remove_media` against (`every_clip()`), which is what a plain "
          "`snapshot.clips` filter got wrong in two places",
          usage.get("Top.mov", {}).get("clipsUsing") == [20, 21]
          and usage.get("Nested.mov", {}).get("clipsUsing") == [52]
          and usage.get("Both.mov", {}).get("clipsUsing") == [22, 53]
          and usage.get("Orphan.mov", {}).get("clipsUsing") == [],
          "; ".join(f"{n}: {r['clipsUsing']}" for n, r in usage.items()))
    check("`usesMedia` agrees with it, TRUE for a file whose only user is inside a nest — "
          "the live cost of getting this wrong was a Remove that showed no alert, went to "
          "the core as a plain `remove_media` and came back as a bare beep",
          usage.get("Top.mov", {}).get("usesMedia") is True
          and usage.get("Nested.mov", {}).get("usesMedia") is True
          and usage.get("Both.mov", {}).get("usesMedia") is True
          and usage.get("Orphan.mov", {}).get("usesMedia") is False,
          "; ".join(f"{n}: {r['usesMedia']}" for n, r in usage.items()))
    check("`timelineClipsUsing` is the NARROWER question a selection can hold — empty for "
          "the nest-only file, where `clipsUsing` is not. The difference between the two is "
          "exactly what lets Reveal in Timeline validate FALSE rather than select nothing",
          usage.get("Top.mov", {}).get("timelineClipsUsing") == [20, 21]
          and usage.get("Nested.mov", {}).get("timelineClipsUsing") == []
          and usage.get("Both.mov", {}).get("timelineClipsUsing") == [22]
          and usage.get("Orphan.mov", {}).get("timelineClipsUsing") == [],
          "; ".join(f"{n}: {r['timelineClipsUsing']}" for n, r in usage.items()))

    searches = {r["search"]: r for r in media_answer.get("searches", [])}
    check("the search is DIACRITIC-insensitive at the boundary: \"resume\" finds "
          "\"Résumé Take.mov\" — `localizedStandardContains`, the comparison Finder searches "
          "with, and the one thing a hand-rolled `lowercased().contains` would fail",
          searches.get("resume", {}).get("admits") == [1], str(searches.get("resume")))
    check("…and CASE-insensitive both ways: \"RESUME\" finds it too, and \"KEYNOTE\" finds "
          "\"keynote.mov\"",
          searches.get("RESUME", {}).get("admits") == [1]
          and searches.get("KEYNOTE", {}).get("admits") == [2],
          f"{searches.get('RESUME', {}).get('admits')} / "
          f"{searches.get('KEYNOTE', {}).get('admits')}")
    check("…and the accented spelling finds it in both cases as well",
          searches.get("Résumé", {}).get("admits") == [1]
          and searches.get("résumé", {}).get("admits") == [1])
    check("a literal SPACE is not trimmed — \"keynote \" and \" keynote\" match NOTHING "
          "where \"keynote\" matches, while \"Beta Reel\" (a space the name really has) "
          "does: the field is on screen beside the list, and a filter that quietly trimmed "
          "what somebody typed would disagree with what they can see",
          searches.get("Beta Reel", {}).get("admits") == [3]
          and searches.get("KEYNOTE", {}).get("admits") == [2]
          and searches.get("keynote ", {}).get("admits") == []
          and searches.get(" keynote", {}).get("admits") == [],
          f"'Beta Reel' {searches.get('Beta Reel', {}).get('admits')}, "
          f"'keynote ' {searches.get('keynote ', {}).get('admits')}, "
          f"' keynote' {searches.get(' keynote', {}).get('admits')}")
    check("…and two spaces where the name has one match nothing, so the comparison is not "
          "collapsing whitespace either",
          searches.get("Beta  Reel", {}).get("admits") == [],
          str(searches.get("Beta  Reel", {}).get("admits")))
    check("an EMPTY search is the only value that means \"no search\": every entry survives "
          "and `isNarrowing` is false",
          searches.get("", {}).get("admits") == [1, 2, 3, 4, 5]
          and searches.get("", {}).get("isNarrowing") is False,
          str(searches.get("", {})))
    check("…and any non-empty search narrows, even one that matches everything",
          searches.get(".mov", {}).get("admits") == [1, 2, 3]
          and searches.get(".mov", {}).get("isNarrowing") is True
          and searches.get("zzz", {}).get("admits") == [],
          f"'.mov' {searches.get('.mov', {}).get('admits')}, "
          f"'zzz' {searches.get('zzz', {}).get('admits')}")

    orders = {r["title"]: r for r in media_answer.get("orders", [])}
    check("the sort popup's rows are Import Order, Name, Duration, Kind at indices 0-3 — the "
          "raw value IS the row index, so the order is API for the popup that reads it",
          [(r["raw"], r["title"]) for r in media_answer.get("orders", [])]
          == [(0, "Import Order"), (1, "Name"), (2, "Duration"), (3, "Kind")],
          str([(r["raw"], r["title"]) for r in media_answer.get("orders", [])]))
    check("Import Order is the media array's own order, untouched — the app knows an ORDER "
          "and does not know a TIME, which is why the row is not called \"Added\"",
          orders.get("Import Order", {}).get("ids") == [1, 2, 3, 4, 5],
          str(orders.get("Import Order", {}).get("ids")))
    check("Name is `localizedStandardCompare` ascending, so \"alpha.wav\" sorts before "
          "\"Beta Reel.mov\" — a case-sensitive `<` would have put every capital first",
          orders.get("Name", {}).get("ids") == [4, 3, 5, 2, 1],
          f"{orders.get('Name', {}).get('ids')} — "
          "alpha.wav, Beta Reel.mov, Cover.png, keynote.mov, Résumé Take.mov")
    check("Duration is ascending, and the TIE between the three 2 s entries falls back to "
          "import order — `Array.sort` is not documented stable, so without the tiebreak "
          "two files of one length could swap places between two runs of the same sort",
          orders.get("Duration", {}).get("ids") == [2, 3, 4, 5, 1],
          str(orders.get("Duration", {}).get("ids")))
    check("Kind is by DISPLAY NAME ascending — Audio, Image, Video — with the same tie "
          "rule, so the three videos keep their import order inside their group",
          orders.get("Kind", {}).get("ids") == [4, 5, 1, 2, 3],
          str(orders.get("Kind", {}).get("ids")))

    check("\"Unused only\" hides every file a clip uses, INCLUDING one used only inside a "
          "nest — which is exactly what `remove_media` will say if it is asked",
          media_answer.get("unusedOnly", {}).get("admits") == [3]
          and media_answer.get("unusedOnly", {}).get("isNarrowing") is True,
          str(media_answer.get("unusedOnly")))
    check("…and the switch and the search are an AND, not an OR — the sharp case: \"top\" "
          "alone admits the file it names, and \"top\" with the switch on admits NOTHING, "
          "because that file is used. An OR would have kept it and added the unused one",
          media_answer.get("and-top", {}) == {"searchOnly": [1], "both": []}
          and media_answer.get("and-rphan", {}) == {"searchOnly": [3], "both": [3]},
          f"top {media_answer.get('and-top')}, rphan {media_answer.get('and-rphan')}")
    check("a default `MediaListFilter` is empty search, Import Order, switch off, not "
          "narrowing — which is what the pane shows before anybody touches it",
          media_answer.get("defaultFilter")
          == {"search": "", "order": 0, "unusedOnly": False, "isNarrowing": False},
          str(media_answer.get("defaultFilter")))

    states = {s["stage"]: s for s in media_answer.get("paneStates", [])}
    rest, typed = states.get("rest", {}), states.get("search eta", {})
    sorted_state, cleared = states.get("sorted by name", {}), states.get("cleared", {})
    check("the pane holds one row per file, arranged in the model's order, none hidden",
          rest.get("rowCount") == 6 and rest.get("arranged") == [1, 2, 3, 4, 5, 6]
          and rest.get("visible") == [1, 2, 3, 4, 5, 6],
          str(rest.get("arranged")))
    check("typing into the search field HIDES the rows that do not match and leaves the "
          "rest — through `controlTextDidChange`, the callback AppKit itself calls. "
          "\"eta\" is in Beta.mov and Zeta.mov and in none of the other four",
          typed.get("visible") == [2, 6],
          f"visible {typed.get('visible')} of {typed.get('modelOrder')}")
    check("…and the tally says so out loud: \"2 of 6 items\", which is the one line that "
          "stops a narrowed list reading as a lost library",
          "2 of 6 items" in typed.get("labels", []),
          str([l for l in typed.get("labels", []) if "item" in l]))
    check("**no rebuild**: the search field is the SAME OBJECT after the list has narrowed, "
          "and `structureSignature` has not moved — a signature carrying the filtered set "
          "would destroy the field under the caret on the first keystroke",
          typed.get("fieldIsSame") is True
          and typed.get("signature") == rest.get("signature")
          and typed.get("rowCount") == 6,
          f"same field {typed.get('fieldIsSame')}, signature unchanged "
          f"{typed.get('signature') == rest.get('signature')}, rows still "
          f"{typed.get('rowCount')}")
    check("sorting re-ORDERS the stack's arranged subviews while `MediaPane.rows` keeps the "
          "MODEL's order — hiding a row and moving one are different jobs, done separately",
          sorted_state.get("arranged") == [1, 2, 4, 5, 3, 6]
          and sorted_state.get("modelOrder") == [1, 2, 3, 4, 5, 6],
          f"arranged {sorted_state.get('arranged')}, model {sorted_state.get('modelOrder')}")
    check("…and moves no view in or out: the stack still has six subviews and six arranged, "
          "so `insertArrangedSubview(_:at:)` MOVED rather than duplicated",
          sorted_state.get("subviewCount") == 6 and len(sorted_state.get("arranged", [])) == 6,
          f"{sorted_state.get('subviewCount')} subviews")
    check("clearing the search shows every row again, in the SORT's order — a hidden row "
          "kept its place in the arrangement and came back where it belongs, which is why "
          "hiding and ordering are two passes and not one",
          cleared.get("visibleArranged") == [1, 2, 4, 5, 3, 6]
          and cleared.get("visible") == [1, 2, 3, 4, 5, 6]
          and "6 items" in cleared.get("labels", []),
          f"arranged and showing {cleared.get('visibleArranged')}, model order "
          f"{cleared.get('visible')}, tally "
          f"{[l for l in cleared.get('labels', []) if 'item' in l]}")
    check("the popup still answers `itemPicked:` — the selector its own menu items carry, "
          "and the one door the harness's `mediaFilter` argument drives the sort through",
          media_answer.get("popupRespondsToItemPicked") is True)
    responder = media_answer.get("responderAfter", {})
    check("THE POINT OF ALL OF IT: after a search AND a re-sort, the search field still "
          "holds first responder and the caret is still where it was — this is the thing "
          "the no-rebuild design buys, and nothing else in this suite would notice it going",
          responder.get("isFieldEditor") is True and responder.get("hasEditor") is True
          and responder.get("caret") == responder.get("caretBefore") == 1
          and responder.get("fieldIsSame") is True,
          f"editor {responder.get('isFieldEditor')}, caret "
          f"{responder.get('caretBefore')} → {responder.get('caret')}")

    reveal = {r["name"]: r["canReveal"] for r in media_answer.get("canReveal", [])}
    check("Reveal in Timeline is enabled for a file with top-level users and DISABLED for "
          "one whose only user is inside a nest — a nested clip has no id a selection can "
          "hold, so the item would select nothing and scroll nowhere",
          reveal == {"Top.mov": True, "Nested.mov": False, "Orphan.mov": False,
                     "Both.mov": True},
          str(reveal))
    check("…and running it selects exactly the top-level clips that show the file, sets it "
          "as the selected media, and sends ONE selector to the editor — view state, no op, "
          "no undo step",
          media_answer.get("revealedTopLevel", {}).get("selection") == [20, 21]
          and media_answer.get("revealedTopLevel", {}).get("selectedMedia") == 1
          and media_answer.get("revealedTopLevel", {}).get("sent")
          == ["revealSelectionInTimeline:"],
          str(media_answer.get("revealedTopLevel")))
    check("…and on the nest-only file it changes no selection and sends nothing (it beeps)",
          media_answer.get("revealedNestOnly", {}).get("selection") == []
          and media_answer.get("revealedNestOnly", {}).get("sent") == [],
          str(media_answer.get("revealedNestOnly")))

    print("\n6b. the AppKit premise the no-rebuild design rests on")
    heights = media_answer.get("stackHeights", {})
    check("hiding an arranged subview takes it OUT of an `NSStackView`'s layout entirely: "
          "four 20 pt rows at 3 pt spacing measure 89 pt, three of them 66 — not 89 with a "
          "gap. This is an AppKit claim, not a Reelcut one, and if it ever changes the "
          "Media pane silently grows a hole",
          heights.get("allShown") == 89 and heights.get("oneHidden") == 66
          and heights.get("shownAgain") == 89,
          f"{heights.get('allShown')} / {heights.get('oneHidden')} / "
          f"{heights.get('shownAgain')} pt")
    check("…and a hidden arranged subview is still ARRANGED and still a subview — it is "
          "collapsed, not removed, which is what lets it come back in place",
          heights.get("arrangedCount") == 4 and heights.get("subviewCount") == 4,
          f"{heights.get('arrangedCount')} arranged, {heights.get('subviewCount')} subviews")
    permutations = media_answer.get("permutations", [])
    wrong = [p for p in permutations if p["arranged"] != p["wanted"]]
    check("`insertArrangedSubview(_:at:)` MOVES a view that is already arranged, over all "
          "24 permutations of four rows: the arranged order is the one asked for every time",
          len(permutations) == 24 and not wrong,
          f"{len(permutations)} permutations, {len(wrong)} wrong")
    laid_out_wrong = [p for p in permutations if p["laidOut"] != p["wanted"]]
    check("…and the LAID-OUT order follows it — a stack that recorded the permutation and "
          "drew the old one would pass on `arrangedSubviews` alone",
          len(permutations) == 24 and not laid_out_wrong,
          f"{len(laid_out_wrong)} laid out wrong")
    duplicated = [p for p in permutations
                  if p["subviewCount"] != 4 or p["arrangedCount"] != 4]
    check("…and NOTHING is duplicated: four subviews and four arranged after every one of "
          "the 24, which is the half of the claim a re-insert could break silently",
          len(permutations) == 24 and not duplicated,
          f"{len(duplicated)} permutations left a different count")
    across = media_answer.get("responderAcrossPermutation", {})
    check("a sibling text field keeps first responder AND its caret offset across such a "
          "permutation — the claim the whole design rests on, since the pane re-orders rows "
          "under a field somebody is typing into",
          across.get("before", {}).get("isEditor") is True
          and across.get("after", {}).get("isEditor") is True
          and across.get("before", {}).get("caret") == across.get("after", {}).get("caret") == 3,
          f"{across.get('before')} → {across.get('after')}")
    removed = media_answer.get("responderAfterAncestorRemoved", {})
    check("…and removing that field's ANCESTOR loses both — the field editor is gone and "
          "the WINDOW is first responder, which is exactly what a `rebuild()` would do to "
          "the search field and why the filter is not in `structureSignature`",
          removed.get("hasEditor") is False and removed.get("isWindow") is True
          and removed.get("isField") is False, str(removed))

    # ------------------------------------------------------------------
    # 7. The find band, photographed.
    print("\n7. the find band, offscreen (8c)")
    renders = {
        "six": render(harness, packages["six"], png("six")),
        "six-again": render(harness, packages["six"], png("six-again")),
        "none": render(harness, packages["none"], png("none")),
        "search": render(harness, packages["six"], png("search"), "beta||"),
        "nomatch": render(harness, packages["six"], png("nomatch"), "zzzz||"),
        "sorted": render(harness, packages["six"], png("sorted"), "|1|"),
        "unused": render(harness, packages["six"], png("unused"), "||1"),
    }
    images = {tag: Image(path) for tag, path in renders.items()}
    six = images["six"]
    scale = six.scale

    check("two renders of one package are byte-identical — the first thing every chrome "
          "script checks, because a proof that scores differently on identical input is an "
          "ambiguity to find and not a race to out-wait",
          same_file(renders["six"], renders["six-again"]),
          f"{os.path.basename(renders['six'])} vs "
          f"{os.path.basename(renders['six-again'])}")

    rules = six.full_width_rules(105, 215)
    check("the pane draws exactly TWO full-width hairlines between the section header and "
          "the list — the action row's and the find band's, both `BarView(border: .bottom)`",
          len(rules) == 2, f"rules at {[f'{a:g}–{b:g}' for a, b in rules]} pt")
    check("…and they are `BAND_H + rowSpacing` apart: the find band is 60 pt tall and the "
          "section's rows sit 7 apart, so a rule 67 pt below the action row's is the band's "
          "height measured on the picture rather than read off the source",
          len(rules) == 2 and abs((rules[1][0] - rules[0][0]) - (BAND_H + ROW_SPACING)) <= 0.5,
          f"{rules[1][0] - rules[0][0]:g} pt against {BAND_H} + {ROW_SPACING}"
          if len(rules) == 2 else "")

    field_box = six.ink_box(CONTENT_X0 - 4, CONTENT_X1 + 4, LINE1_Y0 - 4, LINE1_Y0 + FIELD_H + 4)
    check("line 1 is the search field alone, spanning the whole content width — 24 pt tall "
          "(`DSField.style`'s height) and 1146 → 1430 pt, which is the panel less the "
          "section inset on both sides",
          field_box is not None
          and abs((field_box[3] - field_box[2]) - FIELD_H) <= 1
          and abs(field_box[0] - CONTENT_X0) <= 1 and abs(field_box[1] - CONTENT_X1) <= 1,
          f"x {field_box[0]:g}–{field_box[1]:g} y {field_box[2]:g}–{field_box[3]:g} pt"
          if field_box else "no ink")
    check("…and it sits 4 pt below the band's top: 24 + 6 + 22 = 52 pt of controls centred "
          "in a 60 pt band, which is the two-LINE arrangement the pane had to grow because "
          "three controls measure 319 pt against the 284 the panel leaves",
          field_box is not None and abs(field_box[2] - LINE1_Y0) <= 1.5,
          f"top {field_box[2]:g} pt against {LINE1_Y0:g}" if field_box else "")

    runs = six.ink_columns(LINE2_Y0, LINE2_Y0 + CONTROL_H, CONTENT_X0 - 4, CONTENT_X1 + 4)
    popup = [r for r in runs if abs((r[1] - r[0]) - POPUP_W) < 0.6]
    check("line 2 holds a popup exactly `InspectorMetrics.popupWidth` (116 pt) wide — the "
          "width that holds \"Import Order\" in `DS.mono(11)` with its chevron",
          len(popup) == 1, f"{len(popup)} run(s) of 116 pt among "
          + ", ".join(f"{b - a:g}" for a, b in runs))
    caption = [r for r in runs if r[1] <= popup[0][0]] if popup else []
    check("…with the \"Sort\" caption to its left, starting at the content's leading edge, "
          "and an 8 pt gap between the two (the band's own stack spacing)",
          bool(caption) and abs(caption[0][0] - CONTENT_X0) <= 0.5
          and abs(popup[0][0] - caption[-1][1] - 8) <= 1.5,
          f"caption {caption[0][0]:g}–{caption[-1][1]:g}, popup starts {popup[0][0]:g}"
          if caption and popup else "")
    box = [r for r in runs if abs((r[1] - r[0]) - CHECKBOX_BOX) < 0.6
           and popup and r[0] > popup[0][1]]
    check("…and a 13 pt checkbox box (`OptionCheckboxControl.boxSize`) right of it, with its "
          "label running to the trailing edge — the spacer between them is what pushes the "
          "switch to the same edge the tally uses",
          len(box) == 1 and runs and abs(runs[-1][1] - CONTENT_X1) <= 1,
          f"box {box[0][0]:g}–{box[0][1]:g}, last ink ends {runs[-1][1]:g} against "
          f"{CONTENT_X1}" if box and runs else str(runs))

    tally = six.ink_box(CONTENT_X1 - 120, CONTENT_X1 + 4, TALLY_Y0, TALLY_Y0 + TALLY_H)
    check("the item tally is drawn at the trailing edge of the action row, above the band",
          tally is not None and abs(tally[1] - CONTENT_X1) <= 1,
          f"x {tally[0]:g}–{tally[1]:g} y {tally[2]:g}–{tally[3]:g} pt" if tally else "no ink")

    empty_rules = images["none"].full_width_rules(105, 215)
    empty_runs = images["none"].ink_columns(
        LINE2_Y0, LINE2_Y0 + CONTROL_H, CONTENT_X0 - 4, CONTENT_X1 + 4)
    empty_popup = [r for r in empty_runs if abs((r[1] - r[0]) - POPUP_W) < 0.6]
    empty_gap = (empty_rules[1][0] - empty_rules[0][0]) if len(empty_rules) >= 2 else 0
    check("with NOTHING imported the band is not drawn at all — no 116 pt popup anywhere on "
          "the line it would occupy, and the two rules that ARE there (the action row's and "
          "the footer's) are not 67 pt apart. Three dead controls over a line saying the "
          "list is empty would be worse than nothing, and the pane is rebuilt the moment "
          "the first file lands",
          not empty_popup and abs(empty_gap - (BAND_H + ROW_SPACING)) > 2,
          f"{len(empty_rules)} rule(s) {empty_gap:g} pt apart; {len(empty_popup)} popup-wide "
          f"runs on line 2")

    print("\n7b. the three narrowed states")
    unused_changed = changed_pixels(six, images["unused"])
    unused_boxes = clusters(unused_changed)
    checkbox_rect = Rect("the checkbox's box", box[0][0] if box else 0, LINE2_Y0 - 1,
                         CHECKBOX_BOX, CONTROL_H + 2)
    check("turning \"Unused only\" ON changes ONE cluster in the whole window, and it is the "
          "13 x 13 checkbox box — every file in this fixture is unused, so the list must not "
          "move, and a build whose switch was not wired would change nothing at all",
          len(unused_boxes) == 1 and not outside(unused_changed, [checkbox_rect], scale, 1),
          f"{len(unused_changed)} px in {len(unused_boxes)} cluster(s)\n"
          + describe(unused_boxes, scale))

    sorted_changed = changed_pixels(six, images["sorted"])
    sorted_boxes = clusters(sorted_changed)
    popup_rect = Rect("the popup", popup[0][0] if popup else 0, LINE2_Y0 - 2,
                      POPUP_W, CONTROL_H + 4)
    # Import order is Alpha, Beta, Gamma, Delta, Epsilon, Zeta; name order is
    # Alpha, Beta, Delta, Epsilon, Gamma, Zeta — so rows 3, 4 and 5 change and
    # rows 1, 2 and 6 must not. The pitch is one row plus the list's spacing.
    pitch = ROW_H + LIST_SPACING
    moved = [Rect(f"row {n}", CONTENT_X0 - 2, LIST_Y0 + (n - 1) * pitch,
                  CONTENT_X1 - CONTENT_X0 + 4, ROW_H + 2) for n in (3, 4, 5)]
    check("choosing Name from the sort popup changes the popup's own label and EXACTLY the "
          "three rows that move — rows 1, 2 and 6 are byte-identical, which is what says "
          "the list was re-ordered rather than redrawn",
          sorted_changed and not outside(sorted_changed, [popup_rect] + moved, scale, 2),
          f"{len(sorted_changed)} px in {len(sorted_boxes)} cluster(s)\n"
          + describe(sorted_boxes, scale))
    for n in (1, 2, 6):
        check(f"…row {n} really is byte-identical, compared directly rather than inferred "
              "from a cluster list",
              rows_equal(six, images["sorted"], LIST_Y0 + (n - 1) * pitch,
                         LIST_Y0 + (n - 1) * pitch + ROW_H, CONTENT_X0 - 2, CONTENT_X1 + 2))

    search_changed = changed_pixels(six, images["search"])
    above = [p for p in search_changed if p[1] < ACTION_RULE_Y * scale
             and p[0] >= INSPECTOR_X * scale]
    tally_rect = Rect("the tally", CONTENT_X1 - 120, TALLY_Y0, 124, TALLY_H)
    check("typing \"beta\" changes nothing in the panel ABOVE the action row's rule except "
          "the tally — the band does not move, the tabs do not move, and the section header "
          "does not move",
          not outside(above, [tally_rect], scale, 1),
          f"{len(above)} changed px above the rule, "
          f"{len(outside(above, [tally_rect], scale, 1))} of them outside the tally")
    check("…the tally itself grows LEFTWARD from the same right edge, because the label is "
          "trailing-aligned: \"6 items\" becomes \"1 of 6 items\"",
          bool(inside(search_changed, tally_rect, scale, 1)),
          f"{len(inside(search_changed, tally_rect, scale, 1))} px in {tally_rect}")
    typed_box = images["search"].ink_box(
        CONTENT_X0 + 3, CONTENT_X1 - 3, LINE1_Y0 + 3, LINE1_Y0 + FIELD_H - 3)
    rest_box = six.ink_box(
        CONTENT_X0 + 3, CONTENT_X1 - 3, LINE1_Y0 + 3, LINE1_Y0 + FIELD_H - 3)
    check("…and the field's INSIDE — the bezel excluded — holds the four letters where the "
          "resting render holds a fourteen-character placeholder: same left inset, less ink, "
          "a shorter run",
          typed_box is not None and rest_box is not None
          and typed_box[4] < rest_box[4] and typed_box[1] < rest_box[1] - 20
          and abs(typed_box[0] - rest_box[0]) <= 0.5,
          f"typed {typed_box[4]} px to x {typed_box[1]:g}, placeholder {rest_box[4]} px to x "
          f"{rest_box[1]:g}" if typed_box and rest_box else "")
    first_row_same = rows_equal(six, images["search"], LIST_Y0, LIST_Y0 + ROW_H,
                                CONTENT_X0 - 2, CONTENT_X1 + 2)
    second_row_gone = not rows_equal(six, images["search"], LIST_Y0 + pitch,
                                     LIST_Y0 + pitch + ROW_H, CONTENT_X0 - 2, CONTENT_X1 + 2)
    check("…and the list collapses to the one match, which lands in the FIRST row's "
          "rectangle: the surviving row moved up rather than staying where it was, so the "
          "hidden rows left the layout (`isHidden` on an arranged subview, section 6b)",
          not first_row_same and second_row_gone,
          f"row 1 changed {not first_row_same}, row 2 changed {second_row_gone}")

    nomatch = images["nomatch"]
    nomatch_rules = nomatch.full_width_rules(105, 215)
    check("a search that matches NOTHING keeps the band exactly where it was — both "
          "hairlines still there, still 67 pt apart",
          len(nomatch_rules) == 2
          and abs((nomatch_rules[1][0] - nomatch_rules[0][0]) - (BAND_H + ROW_SPACING)) <= 0.5,
          f"rules at {[f'{a:g}' for a, b in nomatch_rules]} pt")
    # The window is the first 24 pt below the band, which is where the first
    # row's card begins in the six-file render and where the message sits in
    # this one — a taller window would reach the FOOTER, which has moved up
    # with the list and would be read as the message.
    line_box = nomatch.ink_box(CONTENT_X0 - 2, CONTENT_X1 + 2, LIST_Y0, LIST_Y0 + 24)
    row_box = six.ink_box(CONTENT_X0 - 2, CONTENT_X1 + 2, LIST_Y0, LIST_Y0 + 24)
    check("…and puts a LINE of text where the first row's card was, not a card: nine points "
          "of glyphs stopping 94 pt short of the trailing edge, against a card that is "
          "twenty-three points tall and runs the full width. A list that had silently gone "
          "blank is the worst thing a search can do to a library",
          line_box is not None and row_box is not None
          and (line_box[3] - line_box[2]) < 15 and (row_box[3] - row_box[2]) > 20
          and line_box[1] < CONTENT_X1 - 60 and abs(row_box[1] - CONTENT_X1) <= 1,
          f"line x→{line_box[1]:g} {line_box[3] - line_box[2]:g} pt tall; card x→"
          f"{row_box[1]:g} {row_box[3] - row_box[2]:g} pt tall"
          if line_box and row_box else "")
    check("…and the tally reads it as a narrowed list rather than an empty library",
          bool(inside(changed_pixels(six, nomatch), tally_rect, scale, 1)),
          f"{len(inside(changed_pixels(six, nomatch), tally_rect, scale, 1))} px changed in "
          f"{tally_rect}")

    # ------------------------------------------------------------------
    # 8. The instruments themselves.
    print("\n8. the instruments themselves")
    check("no render reported an unsettled layout or a control the filter argument could "
          "not find — either would make every byte comparison above measure something else",
          not WARNINGS,
          "" if not WARNINGS else "\n".join("      " + w for w in WARNINGS))
    answered = {}
    for tag in ("quality", "menu", "panel", "dispatch", "media"):
        path = os.path.join(CHROME, f"answer-{tag}.json")
        if os.path.exists(path):
            with open(path) as f:
                answered[tag] = json.load(f).get("bundlePath", "")
    check("every answer came from the bundle THIS script built, read out of the answers "
          "themselves — `open -n` is asked for a path but LaunchServices resolves bundle "
          "IDENTIFIERS, and a mutation run holds two copies of this bundle under one id, "
          "where a mutant that was never consulted would read exactly like a surviving one",
          len(answered) == 5
          and all(os.path.realpath(p) == os.path.realpath(BUNDLE) for p in answered.values()),
          "; ".join(f"{tag}: {os.path.relpath(path, ROOT) if path else 'none'}"
                    for tag, path in answered.items()) or "no answers")
    failed = [tag for tag, ok, _ in PROBE_RUNS if not ok]
    check("every probe invocation answered — a mode that crashed or wrote nothing would "
          "have failed its own section's checks by name above, and this is the line that "
          "says how many ran",
          not failed and len(PROBE_RUNS) >= 5,
          f"{len(PROBE_RUNS)} runs, "
          + ", ".join(f"{tag} {seconds:.1f} s" for tag, ok, seconds in PROBE_RUNS if ok)
          + (f"; FAILED: {failed}" if failed else ""))
    harness_source = open(os.path.join(HERE, "harness", "main.swift")).read()
    check("the harness's twelfth argument is APPENDED after `expandSections`, so every "
          "earlier chrome script's positions still hold — read out of the harness's own "
          "argument parsing, not asserted from memory",
          "arguments[11]" in harness_source and "arguments[12]" in harness_source
          and harness_source.index("arguments[11]") < harness_source.index("arguments[12]"),
          "expandSections is argument 11, mediaFilter 12")

    # ------------------------------------------------------------------
    # 9. The three canvas-space fragment stages, at all three qualities.
    print("\n9. what a reduced render size does to the three stages that measure a fragment "
          "in CANVAS pixels")
    metal, metal_error = build_metal_probe(probe)
    check("the compositor probe builds, and the project's OWN `Compositor.metal` compiles "
          "into the bundle beside it — a shader that will not compile is a FAILURE here, "
          "like every other instrument in this script, and never an exit",
          metal is not None, metal_error or os.path.relpath(METAL_BUNDLE, ROOT))
    compositor, compositor_error = run_probe(metal, "compositor", {
        "mode": "compositor",
        "renders": [
            {"tag": "nest", "package": packages["nest"], "tick": TICKS_PER_SECOND // 2,
             "classes": [{"name": "lit", "low": [40, 40, 40], "high": [255, 255, 255]}]},
            {"tag": "shadow0", "package": packages["shadow0"],
             "tick": TICKS_PER_SECOND // 2, "classes": CARD_CLASSES},
            {"tag": "shadow300", "package": packages["shadow300"],
             "tick": TICKS_PER_SECOND // 2, "classes": CARD_CLASSES},
            {"tag": "dissolve", "package": packages["dissolve"], "tick": DISSOLVE_TICK,
             "classes": DISSOLVE_CLASSES},
        ],
    })
    if compositor is None:
        check("the compositor probe answered", False, compositor_error or "")
        compositor = {}
    check("`LayerUniforms` is 416 bytes and `ShadowUniforms` 48 — the layout contract's own "
          "arithmetic (104 floats, 26 x 16; and 12 floats, 3 x 16), read from "
          "`MemoryLayout` rather than counted by eye. Nothing checks the METAL half of that "
          "contract but reading it, and the twelve renders below, which come back as "
          "garbage the moment the two lists disagree",
          compositor.get("layerUniformsSize") == 416
          and compositor.get("layerUniformsStride") == 416
          and compositor.get("shadowUniformsSize") == 48
          and compositor.get("shadowUniformsStride") == 48,
          f"layer {compositor.get('layerUniformsSize')}/"
          f"{compositor.get('layerUniformsStride')} bytes, shadow "
          f"{compositor.get('shadowUniformsSize')}/{compositor.get('shadowUniformsStride')}")
    rows = compositor.get("renders", [])
    failed_renders = [f"{r.get('tag')} q{r.get('quality')}: {r['error']}"
                      for r in rows if "error" in r]
    check("all twelve renders came back with a frame — four fixtures through the app's own "
          "path: `ProjectDocument.read`, `CompositionBuilder.build`, "
          "`Playback.previewComposition`'s copy-and-set, `Compositor`, `MetalRenderer` and "
          "the project's own shader, with no uniform filled by hand anywhere (a probe that "
          "wrote `canvasPerDest*` itself would pass against a build where Swift never "
          "wrote them at all)",
          len(rows) == 12 and not failed_renders,
          f"{len(rows)} renders, out of "
          + os.path.relpath(compositor.get("bundlePath", "nowhere"), ROOT)
          + ("; " + "; ".join(failed_renders) if failed_renders else ""))
    sizes = sorted({tuple(r.get("destination", [])) for r in rows})
    check("…at THREE destination sizes, 480x270, 960x540 and 1920x1080, which is the "
          "check that stops every comparison below being three copies of one render: "
          "`PreviewQuality.renderSize` answers the canvas itself at Full, and a coprime "
          "canvas would answer it at all three",
          sizes == [(480, 270), (960, 540), (1920, 1080)], f"{sizes}")

    # 9a. The nest clip rectangle (`Compositor.metal`'s step 7a).
    for quality, name in ((0, "Full"), (1, "Half"), (2, "Quarter")):
        ok, detail = placed(compositor, "nest", quality, "lit", NEST_RECT, NEST_COVERAGE)
        check(f"THE NEST CLIP RECTANGLE at {name}: a 960 x 540 nest holding a shape twice "
              "its size lands exactly where `nest.rs::enter` put the rectangle — canvas "
              "240…1200 x 135…675, a quarter of the frame, off centre on both axes so that "
              "neither can be right by symmetry"
              if quality == 0 else
              f"…and at {name} it is the SAME picture, within a destination pixel. Tested "
              "against the destination's own position it was a rectangle magnified about "
              "the canvas origin — measured against this fixture, the box moved by an "
              "eighth of the frame at Half and by a quarter at Quarter, and the coverage "
              "went 0.25 to 0.39 and then to 0.14",
              ok, detail)

    # 9b. The shadow draw, which samples a CANVAS-sized mask.
    for quality, name in ((0, "Full"), (1, "Half"), (2, "Quarter")):
        ok, detail = (unlit(compositor, "shadow0", quality, "shadow") if quality == 0
                      else hidden(compositor, "shadow0", quality, "shadow", CARD_RECT))
        check("THE SHADOW at Full, distance 0: a shadow exactly behind its card shows NO "
              "pixel of itself — the control that says this fixture can see a shadow that "
              "has moved, since a build drawing it anywhere else fails here first"
              if quality == 0 else
              f"…and at {name} it is still behind the card: what red there is lies within "
              "a destination pixel of the card's own edge. Sampling a canvas-sized mask "
              "with a destination-space coordinate put a magnified slab of it in open "
              "canvas instead — 22 % of the frame at Half and 23 % at Quarter, nowhere "
              "near the layer that cast it",
              ok, detail)
    for quality, name in ((0, "Full"), (1, "Half"), (2, "Quarter")):
        ok, detail = placed(compositor, "shadow300", quality, "shadow", SHADOW_RECT)
        check("THE SHADOW at Full, distance 300: the red lands 212 px down and right, "
              "which is 300 at the default 315° — the arithmetic `encodeShadow` does, "
              "measured in the frame rather than read back out of the uniform"
              if quality == 0 else
              f"…and at {name} it lands in the same place. Under a destination-space "
              "sample the offset was subtracted in canvas pixels from a coordinate that "
              "was not in them, and the shadow landed a third of the frame away at Half "
              "and left the mask altogether at Quarter, where the fixture rendered no red "
              "at all",
              ok, detail)
    for quality, name in ((0, "Full"), (1, "Half"), (2, "Quarter")):
        ok, detail = placed(compositor, "shadow300", quality, "card", CARD_RECT, CARD_COVERAGE)
        check(f"…and the CARD is in the same place at {name} — the control beside the two "
              "above, and the one that says a moving shadow is the shadow moving and not "
              "the layer",
              ok, detail)

    # 9c. The outgoing dissolve's weight correction.
    for quality, name in ((0, "Full"), (1, "Half"), (2, "Quarter")):
        ok, detail = placed(compositor, "dissolve", quality, "corrected", QUADRANT, 0.25)
        check("THE DISSOLVE at Full: at the overlap's midpoint the outgoing half's weight "
              "is divided by the attenuation the incoming is about to apply, and the "
              "corrected pixel — (128, 128, 255) rather than (64, 64, 191) — covers "
              "EXACTLY the quadrant the partner covers, which is what `partnerBox` "
              "publishes in canvas pixels"
              if quality == 0 else
              f"…and at {name} the correction still lands on the partner's quadrant. "
              "Tested in destination space the box began past the frame's right edge, so "
              "NO pixel was corrected and the whole overlap dipped ~25 % dark — invisible "
              "between two full-frame clips, which is why an ordinary dissolve looks fine "
              "and a PiP does not",
              ok, detail)
    for quality, name in ((0, "Full"), (1, "Half"), (2, "Quarter")):
        ok, detail = unlit(compositor, "dissolve", quality, "uncorrected")
        check(f"…and at {name} the UNCORRECTED colour appears in no pixel at all — the "
              "positive half of the same claim, since a build that corrected everywhere "
              "would also pass the box check above",
              ok, detail)
    for quality, name in ((0, "Full"), (1, "Half"), (2, "Quarter")):
        ok, detail = placed(compositor, "dissolve", quality, "plain", (0.0, 0.0, 1.0, 1.0),
                            0.75)
        check(f"…and at {name} the other three quarters of the frame are the plain 128 "
              "grey a half-faded white is, so the correction is confined to where the "
              "partner is and the rest of the dissolve is untouched by all of this",
              ok, detail)

    # Crops for the eye check.
    crop = Rect("the Media tab", INSPECTOR_X, 44, INSPECTOR_W, 460)
    for tag in ("six", "search", "nomatch", "sorted", "unused", "none"):
        images[tag].crop(crop, os.path.join(CHROME, f"crop-{tag}.png"))
    print(f"\nRenders, crops and every probe answer are in {os.path.relpath(CHROME, ROOT)}/")
    print("Nothing the harness PHOTOGRAPHS says anything about either preview's picture — "
          "the well is\nblack offscreen and `displayedPixelBuffer` is nil for both layers "
          "(section 5). What Preview\nQuality changes is the player's render size: section "
          "1 is the arithmetic that decides it,\nand section 9 renders at all three sizes "
          "through a probe to say what the compositor then\ndoes with them.")

    passed = sum(RESULTS)
    print(f"\n{passed}/{len(RESULTS)} checks passed"
          + (f", {len(SKIPS)} skipped by name" if SKIPS else ""))
    sys.exit(0 if passed == len(RESULTS) else 1)


if __name__ == "__main__":
    main()
