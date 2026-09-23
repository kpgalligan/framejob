#!/usr/bin/env python3
"""Road map 2, phase 7 (Output) — the OFFSCREEN half of the proof.

**Almost nothing in phase 7 can be photographed, and that is a fact about the
features rather than about the harness.** Save Frame is a save panel; the
export sheet is a sheet; the export queue is a window of its own. The harness
renders an `EditorViewController`'s content view into a PNG — a panel is not in
it, a sheet is not in it, a second window is not in it, and no sheet can be put
up offscreen at all (which is why phase 3's Remove Silences candidates arrive as
a harness ARGUMENT rather than as a photograph of its sheet). So this script is
mostly PROBES, which is the route `phase6_chrome.py` took for the Clip menu and
`phase5_chrome.py` took for `Loudness`: a `main.swift` of its own compiled
against the WHOLE of `app/Sources` with `harness/build.sh`'s own swiftc line,
cached on modification times, and scored as a FAILURE rather than an exit when
it will not build, so a rotted instrument cannot take the rest of the run down.

What is claimed, section by section:

    1  **the menu and the validator.** File ▸ Save Frame… exists, carries
       `saveFrame:`, and takes ⌥⌘E — the letter Export… already has, under
       two modifiers rather than one, measured as flags read off `NSEvent`
       rather than as a number written here. Window ▸ Export Queue exists,
       carries `showExportQueue:` and takes no key equivalent at all. Then
       `validateSaveFrameAction`: **false on a zero-duration project and true
       on one with a clip**, and `nil` for a selector that is not its own —
       the arm is load-bearing, and a build whose arm answered `true`
       unconditionally would offer a command that can only open a panel and
       then apologise.
    2  **`FrameWriter`, called directly.** Three formats and their whole
       vocabulary; `format(for:requested:)` over every spelling that matters,
       including that `heif` is NOT one of them; three files written from one
       `CGImage` and read back; PNG and HEIC keep the alpha, JPEG does not —
       and **the JPEG flatten really is onto BLACK**, read out of the written
       file at three sample points.
    3  **the remembered choice and the named presets**, in TWO PROCESSES: one
       writes through `ExportChoice.remember()` and `ExportPresetsStore.write()`
       and exits, a second reads them back. **This proves the MECHANISM under
       the PROBE BINARY's own `UserDefaults` domain, not under Reelcut.app's** —
       no proof script in this tree has ever launched or terminated the app, so
       "the sheet reopens on last time's choice after a relaunch" is not a
       thing any of them can say. What is bought here is that the record
       survives a process boundary intact — all NINE fields, and one whole
       preset compared field for field rather than by name, because
       `custom_size` was the one `ExportChoice` field nothing read back until
       the review and a decoder that dropped it scored a clean run — that the
       name is dropped from the remembered one, that the uniqueness rule is
       trimmed and case-insensitive, and that a CORRUPT presets file degrades
       to "no presets" instead of throwing.
    4  **the export queue**, driven through `ExportQueueController` with no
       window ever ordered front — which is what that type's AppKit-free
       design was for. Two queued jobs write files **byte-identical** to two
       single exports through `Exporter` itself; they run ONE at a time and IN
       ORDER; **an edit made to the document between the enqueue and the run
       does not reach either file**; a cancelled job's half-written file is
       deleted and the queue carries on; `remove` refuses a job that has not
       finished and takes ONE that has; and `clearFinished` then drops the row
       it left behind. **That last pair is one probe run and the order inside
       it is the check** — it removed BOTH finished rows before the clear
       until the review, so the clear ran over an empty list and answered 0
       whatever its body did.
    5  **the Document tab's transparency note** — the one thing in this phase
       that IS in the editor's own content view, and so the one real
       photograph here.

**The byte claims of section 4 are made over `apng`, and the reason is
measured.** A QuickTime movie carries a creation and a modification time at
one-second resolution: two ProRes 4444 exports of one unchanged project came
back 207,679 bytes each and differed in exactly SIX bytes, all inside the movie
header's time fields, when they landed in different seconds — and were
byte-identical when they landed in the same one. So a byte comparison of two
`.mov` files is a comparison of two clocks. `apng` has no such field, goes
through `ExporterImageSequence.swift` rather than `ExportWriter`, and came back
byte-identical across processes every time. H.264 is not deterministic at all
(measured: three exports of one project, 2,638 / 2,625 / 2,638 bytes), which is
VideoToolbox's rate control and not a defect — it is the reason the cancel
scenario, which makes no byte claim, is the only place this script uses it. The
ProRes 4444 row's own claims are `tools/proof/phase7_proof.py`'s, over MCP,
where `ffprobe` can read the pixel format.

**Two instruments this script builds, both declared here rather than buried.**
The first is the probe. The second is a `default.metallib`: a bare swiftc
binary has no compiled shader, `MetalRenderer.init` therefore returns nil and
every export in the probe fails with "Metal is not available on this system." —
so `build_probe` compiles the app's OWN `app/Resources/Shaders/Compositor.metal`
with `xcrun metal` and puts the library beside the binary, where
`Bundle.main` finds it. That is the same shader source the app builds, so the
frames the queue writes here are the app's frames. Beside it go the app's
`Fonts` (as `harness/build.sh` does) and `Blank.mp4` — and the answer to
"is `Bundle.main` reachable from a bare swiftc binary" is YES, measured:
`Bundle.main.resourceURL` is the directory the executable is in, so
`CompositionBuilder.addPlaceholderIfNeeded` finds the placeholder there and a
timeline of nothing but shapes exports. That is what lets every fixture here be
a shape card with no media at all.

**Two of these checks were killed by mutants nobody meant to run, and it is
worth saying so.** While this file was being written another agent was
mutation-testing the same working tree, and three of this script's runs
compiled probes against builds carrying its breakages. A `recipe_text.rs` whose
burn-in `y` was a hard-coded 158.4 instead of `canvas.height x
BURN_IN_Y_FRACTION` drew the timecode correctly on the 360 fixture and at 0.646
of the frame on the taller one — which is the whole argument for measuring the
placement at two heights, arrived at by accident. An
`ExporterImageSequence.append` handed the default `RecipeOptions` drew nothing
at all, at either height. Both are fixed in the tree these checks were finally
run against; the paragraph is here because a proof that has actually caught the
bug it was written for is worth more than one that has only been reasoned about.

**One check here is weaker than it reads, and the mutation run is how that was
learned.** "A cancelled job's half-written file is deleted" was written as a
guard on `ExportQueueController.finished`'s `removeItem`, and a build with that
line taken out scores a clean run: `AVAssetWriter.cancelWriting()` already removes
its own part-file and `ImageSequenceWriter` already removes its own, so on both
pipelines the queue's line is defence in depth. The check is therefore worded
as the OUTCOME a person cares about — nothing is left behind — and it is joined
by the precondition that says the outcome means something (the file WAS on disk
when the cancel was asked for). Do not read it as proof of that line, and do
not delete the line: it costs nothing and it says what the queue intends.

**One hazard found while writing this, recorded rather than proved by
crashing.** `Exporter.startWriting` calls `progressHandler` once between
installing its `ExportWriter` and starting it, so a cancel sent SYNCHRONOUSLY
from inside a progress callback reaches `AVAssetReader.cancelReading()` before
`startReading()` has ever been called, and the `startReading()` three lines
later raises an uncaught `NSInternalInconsistencyException` that takes the
process down. Nothing a person can do reaches it — the queue window's Cancel
button is its own event — so the probe defers its cancel by one run-loop turn,
which is what a button click is, and the hazard is written down here and handed
to the orchestrator.

What is NOT claimed here, and why:

  - **anything Save Frame's panel or the export sheet LOOKS like.** Neither is
    in the view the harness captures and neither can be put up offscreen.
    `FrameWriter` is reachable because phase 7a put the write in a value type
    with no AppKit in it; the panel around it is not.
  - **that the app itself reopens its sheet on the remembered choice.** See
    section 3's paragraph: the domain a probe writes is the probe's.
  - **anything about ProRes 4444's pixels, its alpha or `ffprobe`'s reading of
    it.** That is `phase7_proof.py`'s, and it needs a decoder this script
    deliberately does not carry.
  - **`clearFinished` asked while a job is still RUNNING.** The queue is
    settled before the remove and the clear alike, so what section 4 measures
    is that a finished row goes and an empty, idle list is left; that a clear
    leaves a running job where it is comes from `removeAll { $0.state.isFinished }`
    and is not separable from an idle list here.
  - **`AgentServer.replaceableExtensions`.** It is `private static`, so no
    probe can read it; whether `render_frame {path: "shot.jpg"}` writes
    `shot.jpg` or `shot.jpg.png` is a behaviour and belongs to the MCP script.

Run it from anywhere; it builds the harness, the shader library and the probe
if they are stale:

    python3 tools/proof/phase7_chrome.py

The last line is `<n>/<n> checks passed` and the exit status is non-zero if any
failed. The renders, the written stills, the exported files and every probe
answer stay under `tools/proof/work/chrome7/`.

**It touches two things outside the tree and puts both back.** The probe's
`UserDefaults` domain is its own (`~/Library/Preferences/phase7probe.plist`,
keyed on the executable name — measured: two runs of one binary share a domain
and two different binaries do not), and its one key is removed at the end.
`ExportPresetsStore` writes the REAL
`~/Library/Application Support/Reelcut/ExportPresets.json`, because its path is
`AppSupport.directory`'s and `NSHomeDirectory()` ignores `$HOME` on macOS
(measured), so there is no sandbox to put it in — this script therefore copies
that file aside before section 3 and restores it afterwards in a `finally`,
scoring the restoration as a check of its own.
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
CHROME = os.path.join(WORK, "chrome7")
EXPORTS = os.path.join(CHROME, "exports")
BUILD = os.path.join(HERE, "harness", "build.sh")
PROBE = os.path.join(WORK, "phase7probe")
SHADER = os.path.join(ROOT, "app", "Resources", "Shaders", "Compositor.metal")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")
PLACEHOLDER = os.path.join(ROOT, "app", "Resources", "Blank.mp4")

# ---------------------------------------------------------------------------
# Geometry, in POINTS, from the app's layout constants. Section 5 is the only
# one that photographs anything, so this list is short.

WIDTH = 1440
# The Document tab's window. It has to be tall enough that the Appearance
# section's open body AND the Markers section under it are both inside the
# inspector's scroll view in BOTH renders — at the default 862 the note pushes
# the Background row off the bottom, so nothing below it moves and the shift
# this section measures would come back zero for the wrong reason. Measured at
# 862 (the Background row is clipped) and at 1200 (everything fits, and the
# solve is exact).
HEIGHT = 1200

TOOLBAR = 44             # DS.toolbarHeight
INSPECTOR_W = 304        # DS.panelWidth
SCROLLER_W = 16          # AppKit's legacy scroller, pinned by the harness
INSET = 10               # InspectorMetrics.inset
CONTROL_H = 22           # DS.controlHeight — one row
ROW_SPACING = 7          # InspectorMetrics.rowSpacing
SECTION_HEADER_H = 28    # InspectorMetrics.headerHeight

INSPECTOR_X = WIDTH - INSPECTOR_W                        # 1136
LABEL_X0 = INSPECTOR_X + INSET                           # 1146
CONTROL_X1 = INSPECTOR_X + INSPECTOR_W - INSET - SCROLLER_W

# The band the shift is solved over: the Markers section, which is the only
# thing BELOW Appearance in the Document tab (`DocumentPane.sections` is
# Summary, Canvas, Frame Rate, Appearance, Markers). It starts below the
# Appearance section's open body in both renders and ends well above the
# timeline, so a shift cannot be measured against content that was pushed out
# of the pane.
BELOW_Y0 = 615
BELOW_H = 135
# What "an exact shift" means: the winner must leave NO row of the band
# unexplained, and the runner-up must be far worse — the half that says a
# number was measured and not merely preferred. (`phase6_chrome.py`'s rule,
# and its numbers.)
SHIFT_MARGIN = 40
# Where the Document summary line is, the one thing above the Appearance
# section that a background change legitimately redraws ("Black" against
# "Black · 50%").
SUMMARY_Y0, SUMMARY_H = 222, 22
# Everything above this belongs to the sections ABOVE Appearance, which a note
# inside Appearance must not move.
ABOVE_Y1 = 500
# A patch of the toolbar's Export button, which is an `AccentButton` filled
# with `DS.accent` — the same ink `InspectorNoteLabel` draws its text in. No
# colour is written down anywhere in this file: the note's ink is compared
# against this rectangle's, measured in the very render being read, so the
# check holds whatever the person at the machine chose in System Settings.
#
# It sits in the flat run between the button's leading edge (x 1334 pt,
# measured) and its share glyph, NOT across the middle — a rectangle spanning
# the button's whole width is 30 % icon and label, and a modal over that is a
# modal over the fill only by luck. Section 5 scores the "is this inside a flat
# fill" question rather than assuming it.
ACCENT_X0, ACCENT_Y0, ACCENT_W, ACCENT_H = 1336, 15, 10, 14

# ---------------------------------------------------------------------------
# Packages, by hand (spec §5.2). A `.reelcut` is a directory holding a
# `project.json`, so nothing here loads asynchronously and every render is
# deterministic. Every fixture is a SHAPE card with no media at all: a shape
# clip needs no decode, gives the Document tab everything it draws, and
# exports through `CompositionBuilder`'s placeholder track — which is what
# makes this script need no `media/` fixture and no ffmpeg.

TICKS_PER_SECOND = 600_000

BLACK = [0.0, 0.0, 0.0, 1.0]
WHITE = [1.0, 1.0, 1.0, 1.0]


def video_props():
    """`VideoProps` in the core's field order (`model_props.rs`), with
    `blend` LAST — where format version 6 appended it."""
    return {
        "x": 0.0, "y": 0.0, "scale": 1.0, "rotation": 0.0, "opacity": 1.0,
        "crop": {"l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0},
        "corner_radius": 0.0, "shadow": None,
        "color": {"brightness": 0.0, "contrast": 0.0, "saturation": 0.0, "hue": 0.0},
        "chroma": None, "filters": [], "reflection": None, "spotlight": None,
        "obscure": [], "blend": "normal",
    }


def shape_props():
    """`ShapeProps` in the core's field order, with `gradient` LAST."""
    return {
        "kind": "rectangle", "width": 320.0, "height": 120.0,
        "stroke": {"width": 6.0, "color": [1.0, 1.0, 1.0, 1.0]},
        "fill": [0.2, 0.6, 0.9, 1.0], "arrow_start": False, "arrow_end": False,
        "radius": 0.0, "from": [0.0, 1.0], "to": [1.0, 0.0], "gradient": None,
    }


def clip(cid, track, start, duration):
    return {
        "id": cid, "track": track, "start": start, "duration": duration,
        "source": {"kind": "shape"},
        "enabled": {"video": True, "audio": True}, "speed": 1.0,
        "video": video_props(), "audio": None, "text": None, "shape": shape_props(),
        "actions": [], "transition_in": None, "name": None, "label": None,
    }


def project_json(width, height, seconds, background=None):
    clips = (
        [clip(2, 1, 0, int(seconds * TICKS_PER_SECOND))] if seconds > 0 else []
    )
    return {
        "version": 6,
        "canvas": {
            "width": width, "height": height, "fps": [30, 1],
            "background": background or BLACK, "fit_new_clips": True,
            "timecode_frames": True,
        },
        "media": [],
        "tracks": [{"id": 1, "name": "Track 1", "hidden": False, "muted": False,
                    "locked": False, "solo": False}],
        "clips": clips, "markers": [], "next_id": 2 + len(clips), "nests": [],
    }


PACKAGES = {
    # 1 — the validator's two answers. A zero-duration project is the one
    # `Exporter.renderFrame` refuses at any time, which is the arm's own test.
    #
    # The size is small so an export is a second's work, and it is a real
    # canvas rather than a token one: the burn-in draws at every height
    # measured (180, 240, 360, 540 and 720 all land their box between 0.931 and
    # 0.938 of the frame), so nothing here depends on picking a large one.
    "card": dict(width=640, height=360, seconds=1),
    "empty": dict(width=640, height=360, seconds=0),
    # …and a SECOND canvas height, because the placement is a FRACTION of it:
    # one height can only ever say where the box landed, and two say whether it
    # SCALES. 360 is exactly the height at which `BURN_IN_Y_FRACTION` x height
    # and a hard-coded 158.4 coincide, so a proof written against 360 alone
    # would pass against a constant — which is not a hypothetical: this script
    # was accidentally run against a build carrying that very constant (see the
    # header), where the 360 fixture drew a burn-in in the right place and the
    # taller one put it at 0.646 of the frame.
    "tall": dict(width=1280, height=720, seconds=1),
    # 4 — the queue. `card` is the fast one (a 320x180 second of shape) and
    # `long` is the only slow one in the file: the cancel scenario needs an
    # export still running when the cancel is asked for.
    "long": dict(width=1920, height=1080, seconds=25),
    # 5 — the Document tab. Two OPAQUE backgrounds, so that "a background
    # changed" and "the canvas went translucent" can be told apart; one
    # translucent; and the two sides of the 0.995 threshold.
    "doc-black": dict(width=1920, height=1080, seconds=5, background=BLACK),
    "doc-white": dict(width=1920, height=1080, seconds=5, background=WHITE),
    "doc-half": dict(width=1920, height=1080, seconds=5, background=[0.0, 0.0, 0.0, 0.5]),
    "doc-a99": dict(width=1920, height=1080, seconds=5, background=[0.0, 0.0, 0.0, 0.99]),
    "doc-a999": dict(width=1920, height=1080, seconds=5, background=[0.0, 0.0, 0.0, 0.999]),
}


def write_package(name, spec):
    path = os.path.join(WORK, "p7-" + name + ".reelcut")
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


def render(binary, package, out, height=HEIGHT):
    """One render of the DOCUMENT tab, with the harness's arguments in the
    order every earlier chrome script depends on. This script adds no argument
    to the renderer at all — `doc.appearance` is built `defaultExpanded: true`,
    so phase 3's `expandSections` is not needed either."""
    args = [
        binary, package, out, "light", str(WIDTH), str(height), "0", "0", "1",
        "document", "-", "-",
    ]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        sys.stderr.write(result.stdout + result.stderr)
        sys.exit(f"render failed for {package}")
    # `Harness.png` writes one line to stderr when two consecutive captures
    # never came back equal — the layout was still moving when it gave up, and
    # every byte comparison would then be measuring a race instead of the
    # feature. Collected rather than ignored, and scored at the end.
    if result.stderr.strip():
        WARNINGS.append(f"{os.path.basename(out)}: {result.stderr.strip()}")
    return out


# ---------------------------------------------------------------------------
# The probe — the instrument this script builds, declared in the header.
#
# ONE binary with several MODES, because compiling the whole of `app/Sources`
# costs a minute and phase 7's features are spread over four corners of the app
# that no photograph reaches. Every mode writes one JSON object and exits 0, so
# a mode that answers nothing is a scored failure rather than a crash.

PROBE_SOURCE = r'''// Written by tools/proof/phase7_chrome.py. See that file's header.
//
// One binary, several MODES: the mode is `request["mode"]`, the request is
// argv[1] and the answer is argv[2].
import AVFoundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let requestURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])
let request =
    (try? JSONSerialization.jsonObject(with: Data(contentsOf: requestURL)) as? [String: Any])
    ?? [:]
let app = NSApplication.shared
// No Dock tile, no menu bar, no activation: this is a command-line program
// that happens to link AppKit. `phase6_chrome.py`'s probe does the same, and
// nothing here ever orders a window front.
app.setActivationPolicy(.prohibited)

/// The fonts beside the binary, the way `harness/build.sh` puts them beside the
/// harness. `Bundle.main.resourceURL` of a bare swiftc binary is the directory
/// the binary is in — measured — which is also how `Blank.mp4` and
/// `default.metallib` are found.
let binaryDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().standardizedFileURL
func registerFonts() {
    let fonts = binaryDirectory.appendingPathComponent("Fonts")
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: fonts.path) else {
        return
    }
    for name in names where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
        CTFontManagerRegisterFontsForURL(
            fonts.appendingPathComponent(name) as CFURL, .process, nil)
    }
}

var answer: [String: Any] = [:]

func finish() -> Never {
    let data = (try? JSONSerialization.data(
        withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    try? data.write(to: outURL)
    exit(0)
}

/// Spins the MAIN run loop until `done()` or the deadline. Every mode that
/// runs an `Exporter` needs this and nothing else: `Exporter` schedules a
/// run-loop `Timer` for progress and calls its completion on the main thread,
/// so a program with no `NSApp.run()` still drives one to the end by servicing
/// the run loop itself.
func spin(until done: () -> Bool, timeout: Double) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !done(), Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return done()
}

func openDocument(_ path: String) -> ProjectDocument? {
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
    } catch {
        return nil
    }
    return document
}

// ---------------------------------------------------------------------------
// menu — the main menu the delegate builds, and the editor's validator.
//
// `AppDelegate.buildMainMenu()` is private and its one caller is
// `applicationWillFinishLaunching`, which the app runs at launch and the
// harness never does (it renders a window; a menu is not in one).

func runMenu() {
    let delegate = AppDelegate()
    delegate.applicationWillFinishLaunching(
        Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

    func dump(_ item: NSMenuItem) -> [String: Any] {
        var row: [String: Any] = [
            "title": item.title, "separator": item.isSeparatorItem,
            "action": item.action.map { NSStringFromSelector($0) } ?? "",
            "key": item.keyEquivalent,
            "modifiers": Int(item.keyEquivalentModifierMask.rawValue),
        ]
        if let sub = item.submenu {
            row["submenu"] = ["title": sub.title, "items": sub.items.map(dump)]
        }
        return row
    }
    answer["menu"] = [
        "title": NSApp.mainMenu?.title ?? "",
        "items": (NSApp.mainMenu?.items ?? []).map(dump),
    ]
    // The modifier flags, read off AppKit rather than spelled as numbers in
    // the script: "⌥⌘E" is a claim about which two bits are set and about the
    // two that are not.
    answer["modifierBits"] = [
        "command": Int(NSEvent.ModifierFlags.command.rawValue),
        "option": Int(NSEvent.ModifierFlags.option.rawValue),
        "shift": Int(NSEvent.ModifierFlags.shift.rawValue),
        "control": Int(NSEvent.ModifierFlags.control.rawValue),
    ]
    var validations: [[String: Any]] = []
    for probe in request["validate"] as? [[String: Any]] ?? [] {
        var row: [String: Any] = ["name": probe["name"] as? String ?? "?"]
        guard let document = openDocument(probe["package"] as? String ?? "") else {
            row["error"] = "the package would not open"
            validations.append(row)
            continue
        }
        let clips = document.project.snapshot.clips.sorted { $0.start < $1.start }
        document.selection = Set(
            (probe["select"] as? [Int] ?? []).compactMap {
                clips.indices.contains($0) ? clips[$0].id : nil
            })
        let controller = EditorViewController(document: document)
        var enabled: [String: Bool] = [:]
        for name in probe["selectors"] as? [String] ?? [] {
            let item = NSMenuItem(
                title: name, action: NSSelectorFromString(name), keyEquivalent: "")
            enabled[name] = controller.validateUserInterfaceItem(item)
        }
        row["enabled"] = enabled
        row["duration"] = document.project.duration
        // The arm itself, asked directly. `validateUserInterfaceItem` is the
        // chain; this is the one link phase 7a added, and an arm that answered
        // for selectors other than its own would be answering for every
        // command in the chain.
        row["saveFrameArm"] =
            controller.validateSaveFrameAction(
                #selector(EditorViewController.saveFrame(_:))) as Any
        row["armForAnotherSelector"] =
            controller.validateSaveFrameAction(
                #selector(EditorViewController.exportProject(_:))) as Any
        validations.append(row)
    }
    answer["validation"] = validations
}

// ---------------------------------------------------------------------------
// framewriter — `FrameWriter`, called directly.

/// A 64x64 test card in STRAIGHT (non-premultiplied) alpha: a transparent
/// white band, a half-transparent white band, an opaque white band.
///
/// Straight rather than premultiplied on purpose, and the reason is the whole
/// of what makes section 2's flatten check a check. Over PREMULTIPLIED pixels
/// a flatten onto black is numerically the IDENTITY — a transparent pixel is
/// already (0,0,0) and `src + dst(1 - a)` with dst = 0 is `src` — so a fixture
/// in that encoding cannot tell a build that flattens from a build that merely
/// drops the alpha channel, and the check would pass against both. Straight
/// alpha separates them: unflattened, the white survives at full value.
func testCard(width: Int = 64, height: Int = 64) -> CGImage? {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            let alpha: UInt8 = x < width / 3 ? 0 : (x < 2 * width / 3 ? 128 : 255)
            bytes[i] = 255
            bytes[i + 1] = 255
            bytes[i + 2] = 255
            bytes[i + 3] = alpha
        }
    }
    guard let data = CFDataCreate(nil, bytes, bytes.count),
        let provider = CGDataProvider(data: data)
    else { return nil }
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}

/// Reads a written file back and samples it. Answers nil when the file is not
/// an image ImageIO can read at all, which is a failure the script scores
/// rather than a crash.
func sample(_ url: URL, at points: [[Int]]) -> [String: Any]? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let uti = CGImageSourceGetType(source) as String? ?? ""
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    var samples: [[Int]] = []
    var drew = false
    bytes.withUnsafeMutableBytes { raw in
        // PREMULTIPLIED, because `CGContext` does not accept straight alpha at
        // all — `kCGImageAlphaLast` is not a supported CONTEXT format, a
        // context asked for it comes back nil, and every sample would then
        // read zero, which is a silent pass for exactly the claims below (it
        // is how this function was wrong the first time). So a pixel is
        // reported premultiplied: the ALPHA is the honest half for PNG and
        // HEIC, and the RGB is the honest half for JPEG, which has no alpha
        // left to premultiply by.
        guard let context = CGContext(
            data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        drew = true
    }
    if !drew { return nil }
    for point in points {
        let x = min(max(point[0], 0), width - 1)
        let y = min(max(point[1], 0), height - 1)
        let i = (y * width + x) * 4
        samples.append([Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3])])
    }
    return [
        "uti": uti, "width": width, "height": height,
        "alphaInfo": Int(image.alphaInfo.rawValue), "samples": samples,
    ]
}

func runFrameWriter() {
    let directory = URL(fileURLWithPath: request["dir"] as! String)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let points = request["points"] as? [[Int]] ?? [[8, 32], [32, 32], [56, 32]]

    // The vocabulary, read off the type rather than spelled here.
    answer["cases"] = FrameWriter.Format.allCases.map { format in
        [
            "raw": format.rawValue, "ext": format.fileExtension,
            "display": format.displayName, "alpha": format.carriesAlpha,
            "note": format.alphaNote, "uti": format.contentType.identifier,
            "hasProperties": format.destinationProperties != nil,
        ]
    }
    answer["flattenNote"] = FrameWriter.flattenNote
    answer["quality"] = FrameWriter.quality

    // `format(for:requested:)` over every spelling that matters.
    var reads: [[String: Any]] = []
    for probe in request["formats"] as? [[String: Any]] ?? [] {
        let name = probe["name"] as? String ?? ""
        let requested = (probe["requested"] as? String)
            .flatMap { FrameWriter.Format(rawValue: $0) }
        let url = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
        reads.append([
            "name": name, "requested": probe["requested"] as? String ?? "",
            "answer": FrameWriter.format(for: url, requested: requested).rawValue,
        ])
    }
    answer["formatFor"] = reads

    // Written for real, one file per format, from ONE image.
    guard let image = testCard() else {
        answer["error"] = "the test card could not be built"
        return
    }
    var written: [[String: Any]] = []
    for format in FrameWriter.Format.allCases {
        let url = directory.appendingPathComponent("card.\(format.fileExtension)")
        try? FileManager.default.removeItem(at: url)
        var row: [String: Any] = ["format": format.rawValue, "path": url.path]
        do {
            row["answered"] = try FrameWriter.write(image, as: format, to: url).path
            row["bytes"] =
                ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size])
                    as? Int) ?? 0
            if let read = sample(url, at: points) {
                row["read"] = read
            } else {
                row["error"] = "the file written is not an image ImageIO can read back"
            }
        } catch {
            row["error"] = error.localizedDescription
        }
        written.append(row)
    }
    answer["written"] = written

    // A path that cannot be written, so the throw is MEASURED: `FrameWriter`
    // names the path, and a caller handed a bare `false` would have nothing to
    // put in an alert.
    do {
        _ = try FrameWriter.write(
            image, as: .png, to: URL(fileURLWithPath: "/System/nowhere/card.png"))
        answer["refusal"] = ""
    } catch {
        answer["refusal"] = error.localizedDescription
    }
}

// ---------------------------------------------------------------------------
// defaults — the remembered choice and the named presets, in two processes.

func choice(from raw: [String: Any]) -> ExportChoice {
    ExportChoice(
        name: raw["name"] as? String ?? "",
        presetID: raw["preset_id"] as? String ?? "",
        sizeRow: raw["size_row"] as? String,
        customSize: raw["custom_size"] as? [Int],
        fps: raw["fps"] as? [Int],
        qualityTier: raw["quality_tier"] as? String,
        loudness: raw["loudness"] as? Double,
        inOutRange: raw["in_out_range"] as? Bool ?? false,
        burnInTimecode: raw["burn_in_timecode"] as? Bool ?? false)
}

func describe(_ c: ExportChoice) -> [String: Any] {
    [
        "name": c.name, "preset_id": c.presetID, "size_row": c.sizeRow as Any,
        "custom_size": c.customSize as Any, "fps": c.fps as Any,
        "quality_tier": c.qualityTier as Any, "loudness": c.loudness as Any,
        "in_out_range": c.inOutRange, "burn_in_timecode": c.burnInTimecode,
    ]
}

func runDefaultsWrite() {
    answer["presetsURL"] = ExportPresetsStore.url?.path ?? ""
    answer["defaultsKey"] = ExportChoice.rememberedKey
    UserDefaults.standard.removeObject(forKey: ExportChoice.rememberedKey)
    if let raw = request["remember"] as? [String: Any] {
        let c = choice(from: raw)
        c.remember()
        answer["asked"] = describe(c)
    }
    var store = ExportPresetsStore()
    for raw in request["presets"] as? [[String: Any]] ?? [] {
        store = store.saving(choice(from: raw))
    }
    answer["saved"] = store.presets.map(describe)
    var trimmed = store
    for name in request["remove"] as? [String] ?? [] {
        trimmed = trimmed.removing(named: name)
    }
    answer["afterRemove"] = trimmed.presets.map(describe)
    // The PRE-removal store is what lands on disk, so the reading process has
    // something with more than one record in it to read.
    answer["wrote"] = store.write()
    // The raw defaults value, so the script can see that ONE key holds the
    // whole record as JSON rather than nine keys.
    answer["rawDefaults"] = UserDefaults.standard.string(forKey: ExportChoice.rememberedKey) ?? ""
    UserDefaults.standard.synchronize()
}

func runDefaultsRead() {
    answer["defaultsKey"] = ExportChoice.rememberedKey
    answer["presetsURL"] = ExportPresetsStore.url?.path ?? ""
    answer["remembered"] = ExportChoice.remembered.map(describe) as Any
    let store = ExportPresetsStore.load()
    answer["presets"] = store.presets.map(describe)
    answer["lookup"] = (request["lookup"] as? [String] ?? []).map { name -> [String: Any] in
        ["ask": name, "found": store.preset(named: name).map(describe) as Any]
    }
    // "" is what the harness pins the key to and what `string(forKey:)` of an
    // absent key reads as: both must mean "nothing remembered".
    UserDefaults.standard.set("", forKey: ExportChoice.rememberedKey)
    answer["rememberedWhenEmpty"] = ExportChoice.remembered.map(describe) as Any
    // The degradation, measured on this process's own read: a file of nonsense
    // answers an empty store rather than throwing.
    if let corrupt = request["corrupt"] as? String, let url = ExportPresetsStore.url {
        try? Data(corrupt.utf8).write(to: url)
        answer["corruptCount"] = ExportPresetsStore.load().presets.count
        answer["corruptSurvived"] = true
    }
}

/// Puts back what the two modes above touched: the one defaults key, and the
/// presets file (which the SCRIPT restores from its own copy — this only
/// removes what the probe wrote when there was nothing there before).
func runDefaultsClean() {
    UserDefaults.standard.removeObject(forKey: ExportChoice.rememberedKey)
    UserDefaults.standard.synchronize()
    answer["remembered"] = ExportChoice.remembered.map(describe) as Any
    if request["deletePresets"] as? Bool ?? false, let url = ExportPresetsStore.url {
        try? FileManager.default.removeItem(at: url)
    }
    answer["presetsExists"] = ExportPresetsStore.url.map {
        FileManager.default.fileExists(atPath: $0.path)
    } ?? false
}

// ---------------------------------------------------------------------------
// export — one export straight through `Exporter`, the sheet's own path, so
// the queue's files have something to be compared against.

func runExportSingle() {
    guard let document = openDocument(request["package"] as! String) else {
        answer["error"] = "the package would not open"
        return
    }
    if let raw = request["edit"] as? [Double] {
        document.applyEdit("Edit", .setCanvas(background: raw))
    }
    let preset = request["preset"] as? String ?? "apng"
    guard let resolved = try? ReelExport.settings(document.project, preset: preset) else {
        answer["error"] = "the core would not resolve \(preset)"
        return
    }
    let url = URL(fileURLWithPath: request["out"] as! String)
    try? FileManager.default.removeItem(at: url)
    var options = RecipeOptions.none
    options.burnInTimecode = request["burn_in"] as? Bool ?? false
    let exporter = Exporter()
    var outcome: String?
    var message = ""
    exporter.export(
        project: document.project, urls: document.mediaURLs(), settings: resolved, to: url,
        options: options,
        progress: { _ in },
        completion: { result in
            switch result {
            case .success(let written):
                outcome = "completed"
                message = written.lastPathComponent
            case .failure(let error):
                outcome = "failed"
                message = error.localizedDescription
            }
        })
    answer["settled"] = spin(
        until: { outcome != nil }, timeout: request["timeout"] as? Double ?? 300)
    answer["state"] = outcome ?? "timed out"
    answer["message"] = message
    answer["exists"] = FileManager.default.fileExists(atPath: url.path)
}

// ---------------------------------------------------------------------------
// queue — `ExportQueueController`, driven with NO window ever ordered front.

final class QueueWatcher {
    let queue: ExportQueueController
    /// Every state a job has been seen in, in the order they were first seen:
    /// "1:running", "1:completed", "2:running"… This is what says the jobs ran
    /// ONE AT A TIME and IN ORDER, and it is read off the controller's own
    /// notification rather than polled, so a transition between two spins of
    /// the run loop cannot be missed.
    var transitions: [String] = []
    var maxRunning = 0
    var observations = 0
    /// Set by the cancel rule, so the script can assert the PRECONDITION — the
    /// file was on disk when the cancel was asked for — before it asserts that
    /// the file is gone. A check whose precondition never held would pass
    /// against a build that deletes nothing.
    var cancelledID: UInt64?
    var existedAtCancel: Bool?
    var progressAtCancel: Double?
    var cancelWhenProgress: Double?
    private var armed = false
    private var seen = Set<String>()
    private var token: NSObjectProtocol?

    init(_ queue: ExportQueueController) {
        self.queue = queue
        token = NotificationCenter.default.addObserver(
            forName: ExportQueueController.didChangeNotification, object: queue, queue: nil
        ) { [weak self] _ in self?.observe() }
    }

    deinit {
        if let token = token { NotificationCenter.default.removeObserver(token) }
    }

    func observe() {
        observations += 1
        var running = 0
        for job in queue.jobs {
            if job.state == .running { running += 1 }
            let key = "\(job.id):\(job.state.rawValue)"
            if seen.insert(key).inserted { transitions.append(key) }
        }
        maxRunning = max(maxRunning, running)
        if let threshold = cancelWhenProgress, !armed,
            let job = queue.runningJob, job.progress >= threshold
        {
            armed = true
            // **The cancel is deferred one run-loop turn on purpose, and it is
            // not politeness.** This notification is posted from inside
            // `Exporter`'s progress callback, and `Exporter.startWriting` makes
            // exactly one of those calls between installing its `ExportWriter`
            // and starting it — so a cancel sent synchronously from here
            // reaches `AVAssetReader.cancelReading()` before `startReading()`
            // has ever been called, and the `startReading()` three lines later
            // raises an uncaught `NSInternalInconsistencyException` that takes
            // the process down (measured). Nothing a person can do reaches it:
            // the queue window's Cancel button is its own event. So the probe
            // models the button, and the hazard is written down in the
            // script's header rather than proved by crashing.
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.cancelledID == nil,
                    let job = self.queue.runningJob
                else { return }
                self.cancelledID = job.id
                self.progressAtCancel = job.progress
                self.existedAtCancel = FileManager.default.fileExists(
                    atPath: job.destination.path)
                self.queue.cancel(job.id)
            }
        }
    }
}

func runQueue() {
    guard let document = openDocument(request["package"] as! String) else {
        answer["error"] = "the package would not open"
        return
    }
    let preset = request["preset"] as? String ?? "apng"
    guard let resolved = try? ReelExport.settings(document.project, preset: preset) else {
        answer["error"] = "the core would not resolve \(preset)"
        return
    }
    // A queue of this probe's OWN, never `ExportQueueController.shared`: the
    // notification carries the controller as its object, so a probe's watcher
    // cannot be woken by anything else and nothing here can disturb an app.
    let queue = ExportQueueController()
    let watcher = QueueWatcher(queue)
    watcher.cancelWhenProgress = request["cancel_when_progress"] as? Double

    answer["idleBefore"] = queue.isIdle
    var ids: [UInt64] = []
    for raw in request["jobs"] as? [[String: Any]] ?? [] {
        let url = URL(fileURLWithPath: raw["out"] as! String)
        try? FileManager.default.removeItem(at: url)
        var options = RecipeOptions.none
        options.burnInTimecode = raw["burn_in"] as? Bool ?? false
        ids.append(
            queue.enqueue(
                project: document.project, urls: document.mediaURLs(), settings: resolved,
                to: url, options: options))
    }
    answer["ids"] = ids.map { Int($0) }
    answer["waitingAfterEnqueue"] = queue.waitingCount
    answer["runningAfterEnqueue"] = queue.runningJob.map { Int($0.id) } as Any

    // **The immutability test.** The edit lands after both jobs are queued and
    // before the run loop has been spun once, so it precedes the first frame
    // either job composes — and both files must still hold the timeline as it
    // was when they were enqueued.
    if let raw = request["edit_after_enqueue"] as? [Double] {
        document.applyEdit("Edit", .setCanvas(background: raw))
        answer["editedTo"] = raw
        answer["documentBackgroundNow"] = document.project.snapshot.canvas.background
    }

    // `remove` on a job that has not finished, asked while one runs and one
    // waits.
    if request["remove_unfinished"] as? Bool ?? false {
        let before = queue.jobs.count
        for id in ids { queue.remove(id) }
        answer["removeUnfinished"] = ["before": before, "after": queue.jobs.count]
    }

    answer["settled"] = spin(
        until: { queue.isIdle }, timeout: request["timeout"] as? Double ?? 600)
    answer["idleAfter"] = queue.isIdle
    answer["transitions"] = watcher.transitions
    answer["maxRunning"] = watcher.maxRunning
    answer["observations"] = watcher.observations
    answer["cancelledID"] = watcher.cancelledID.map { Int($0) } as Any
    answer["existedAtCancel"] = watcher.existedAtCancel as Any
    answer["progressAtCancel"] = watcher.progressAtCancel as Any
    answer["jobs"] = queue.jobs.map { job -> [String: Any] in
        [
            "id": Int(job.id), "state": job.state.rawValue, "finished": job.state.isFinished,
            "progress": job.progress, "message": job.message ?? "",
            "name": job.name, "path": job.destination.path,
            "exists": FileManager.default.fileExists(atPath: job.destination.path),
            "burn_in": job.options.burnInTimecode,
        ]
    }

    // Removing a FINISHED job is what the queue does allow, asked after the
    // refusal above so the pair is one measurement. It takes the FIRST id and
    // no more, and that is the review's correction rather than a preference:
    // this block used to remove BOTH, which left `clearFinished` below running
    // over an already-empty list, so `afterClear` was 0 whatever that method's
    // body did and the check on it could not fail. A clear has to be asked of
    // a queue that still holds a finished row.
    if request["remove_finished"] as? Bool ?? false, let first = ids.first {
        let before = queue.jobs.count
        queue.remove(first)
        answer["removeFinished"] = [
            "before": before, "after": queue.jobs.count, "removed": Int(first),
        ]
    }
    if request["clear_finished"] as? Bool ?? false {
        let before = queue.jobs.count
        queue.clearFinished()
        answer["beforeClear"] = before
        answer["afterClear"] = queue.jobs.count
        // Read AFTER the clear, so the "and the queue is still running" half is
        // a fact about the list the clear left rather than about the settle two
        // blocks up (which is where `idleAfter` is read, and which no clear can
        // affect).
        answer["idleAfterClear"] = queue.isIdle
    }
}

// ---------------------------------------------------------------------------

registerFonts()
answer["mode"] = request["mode"] as? String ?? ""
answer["resourceURL"] = Bundle.main.resourceURL?.path ?? ""
answer["placeholder"] = Bundle.main.url(forResource: "Blank", withExtension: "mp4")?.path ?? ""
switch request["mode"] as? String ?? "" {
case "menu": runMenu()
case "framewriter": runFrameWriter()
case "defaults-write": runDefaultsWrite()
case "defaults-read": runDefaultsRead()
case "defaults-clean": runDefaultsClean()
case "export-single": runExportSingle()
case "queue": runQueue()
default: answer["error"] = "unknown mode"
}
finish()
'''


def build_shader():
    """Compiles the app's own `Compositor.metal` into a `default.metallib`
    beside the probe binary.

    A bare swiftc binary has no shader library, so `MetalRenderer.init` returns
    nil and EVERY export the probe runs fails with "Metal is not available on
    this system." — which reads exactly like a queue defect and is not one.
    Cached on modification times like everything else here. Answers None with a
    reason, which section 4 scores rather than exiting on."""
    os.makedirs(PROBE, exist_ok=True)
    lib = os.path.join(PROBE, "default.metallib")
    air = os.path.join(PROBE, "Compositor.air")
    if os.path.exists(lib) and os.path.getmtime(SHADER) < os.path.getmtime(lib):
        return lib, None
    compile_step = subprocess.run(
        ["xcrun", "-sdk", "macosx", "metal", "-c", SHADER, "-o", air],
        capture_output=True, text=True)
    if compile_step.returncode != 0:
        return None, "xcrun metal failed:\n      " + compile_step.stderr.strip()[:400]
    link_step = subprocess.run(
        ["xcrun", "-sdk", "macosx", "metallib", air, "-o", lib],
        capture_output=True, text=True)
    if link_step.returncode != 0 or not os.path.exists(lib):
        return None, "xcrun metallib failed:\n      " + link_step.stderr.strip()[:400]
    return lib, None


def build_probe():
    """Compiles the probe if it is stale, exactly as `harness/build.sh` does —
    the same swiftc line, the same staleness rule (the binary must be newer
    than every source, the probe's own main and the staticlib) — and copies the
    app's `Fonts` and `Blank.mp4` beside it, which is what makes
    `Bundle.main` answer for a bare executable.

    Returns the binary's path, or None with the reason, which every section
    scores as a FAILURE rather than exiting: an instrument that will not build
    must not take the rest of the score with it."""
    os.makedirs(PROBE, exist_ok=True)
    binary = os.path.join(PROBE, "phase7probe")
    entry = os.path.join(PROBE, "main.swift")
    # Written only when it CHANGED, or the staleness check below would rebuild
    # on every run.
    if not os.path.exists(entry) or open(entry).read() != PROBE_SOURCE:
        with open(entry, "w") as f:
            f.write(PROBE_SOURCE)
    fonts = os.path.join(PROBE, "Fonts")
    if not os.path.isdir(fonts) or os.path.getmtime(FONTS) > os.path.getmtime(fonts):
        shutil.rmtree(fonts, ignore_errors=True)
        shutil.copytree(FONTS, fonts)
    placeholder = os.path.join(PROBE, "Blank.mp4")
    if not os.path.exists(placeholder):
        shutil.copy2(PLACEHOLDER, placeholder)
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
        print(f"probe: {binary} (up to date)")
        return binary, None
    sdk = subprocess.run(
        ["xcrun", "--show-sdk-path", "--sdk", "macosx"], capture_output=True, text=True
    ).stdout.strip()
    start = time.time()
    result = subprocess.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
         "-import-objc-header", os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
         "-L", os.path.dirname(lib), "-lreelcut_core"] + sources + [entry, "-o", binary],
        capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(binary):
        errors = [line for line in result.stderr.splitlines() if ": error:" in line]
        # The tail as well as the error lines: a swiftc that is KILLED (a
        # signal, memory pressure behind another whole-module build) exits
        # non-zero with no `: error:` line at all, and "(no error lines)" on
        # its own is a message nobody can act on.
        tail = [line for line in result.stderr.strip().splitlines()[-4:] if line.strip()]
        return None, (f"swiftc exited {result.returncode}:\n      "
                      + "\n      ".join(errors[:6] or tail or ["(no output)"]))
    print(f"probe: {binary} (built in {time.time() - start:.1f} s)")
    return binary, None


PROBE_RUNS = []


def run_probe(binary, tag, request, timeout=600):
    """One probe invocation. Answers (answer, error); a probe that crashed or
    wrote nothing answers (None, its output), which every caller turns into
    failures BY NAME rather than into a shorter list."""
    if binary is None:
        return None, "the probe did not build"
    request_path = os.path.join(CHROME, f"request-{tag}.json")
    out = os.path.join(CHROME, f"answer-{tag}.json")
    if os.path.exists(out):
        os.remove(out)
    with open(request_path, "w") as f:
        json.dump(request, f, indent=2)
    start = time.time()
    try:
        result = subprocess.run(
            [binary, request_path, out], capture_output=True, text=True, timeout=timeout)
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
# PNG, in pure Python: chunks, zlib, the five filters. (phase6_chrome.py's,
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


def shift_match(top, bottom, band, limit=60):
    """How far DOWN `bottom` is `top`, measured over `band`.

    Walks every whole-point shift and counts the rows of `band` that do not
    match; the winner is the growth, in points, and the runner-up is what says
    the winner was measured rather than preferred. (`phase6_chrome.py`'s, with
    a shorter limit — the only thing that can move here is one label row.)"""
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


def changed_row_band(a_path, b_path):
    """The rows two same-sized PNGs disagree about, as
    `(top, bottom, height, x0, x1, width)` in PIXELS, or None when they agree.

    Used on the FIRST FRAME of two APNG exports — an animated PNG's default
    image is an ordinary PNG, so `decode_png` reads it with no new instrument —
    to find where the timecode burn-in landed. It is a row band rather than a
    rectangle because that is the whole of the claim: the burn-in's placement is
    a fraction of the canvas HEIGHT.
    """
    wa, ha, ch, rows_a = decode_png(a_path)
    wb, hb, _, rows_b = decode_png(b_path)
    if (wa, ha) != (wb, hb):
        return None
    rows = [y for y in range(ha) if rows_a[y] != rows_b[y]]
    if not rows:
        return None
    xs = set()
    for y in rows:
        ra, rb = rows_a[y], rows_b[y]
        x = int.from_bytes(ra, "big") ^ int.from_bytes(rb, "big")
        xb = x.to_bytes(len(ra), "big")
        for m in re.finditer(rb"[^\x00]+", xb):
            xs.add(m.start() // ch)
            xs.add((m.end() - 1) // ch)
    return min(rows), max(rows), ha, min(xs), max(xs), wa


def modal_pixel(image, rect, exclude=()):
    """The most common pixel of a rectangle, skipping any in `exclude`. Used
    twice in section 5 and NEVER against a written-down colour: both the
    accent and the note's ink are measured in the render being read."""
    counts = {}
    s = image.scale
    for y in range(int(rect.y0 * s), min(int(rect.y1 * s), image.height)):
        for x in range(int(rect.x0 * s), min(int(rect.x1 * s), image.width)):
            px = image.pixel(x, y)
            if px in exclude:
                continue
            counts[px] = counts.get(px, 0) + 1
    if not counts:
        return None, 0, 0
    total = sum(counts.values())
    best = max(counts.items(), key=lambda kv: kv[1])
    return best[0], best[1], total


# ---------------------------------------------------------------------------
# The checks.

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append(bool(ok))
    print(f"  {'PASS' if ok else 'FAIL'}: {name}")
    if detail:
        print(detail if detail.startswith("      ") else "      " + detail)


def same_file(a, b):
    if not (os.path.exists(a) and os.path.exists(b)):
        return False
    with open(a, "rb") as fa, open(b, "rb") as fb:
        return fa.read() == fb.read()


def size_of(path):
    return os.path.getsize(path) if os.path.exists(path) else -1


def find_item(items, title):
    return next((i for i in items if i["title"] == title), None)


def submenu_items(menu, title):
    item = find_item(menu.get("items", []), title)
    return (item or {}).get("submenu", {}).get("items", [])


# ---------------------------------------------------------------------------


def main():
    os.makedirs(CHROME, exist_ok=True)
    os.makedirs(EXPORTS, exist_ok=True)
    harness = build_harness()
    shader, shader_error = build_shader()
    probe, probe_error = build_probe()
    packages = {name: write_package(name, spec) for name, spec in PACKAGES.items()}
    print(f"packages: {len(packages)} written under {os.path.relpath(WORK, ROOT)}/")

    def png(tag):
        return os.path.join(CHROME, tag + ".png")

    def out(name):
        return os.path.join(EXPORTS, name)

    print("\n0. the instruments")
    check("the probe builds — an instrument that will not compile is a FAILURE here, never "
          "an exit: it must not take the rest of the score with it",
          probe is not None, probe_error or os.path.relpath(PROBE, ROOT) + "/phase7probe")
    check("the shader library builds — a bare swiftc binary has none, `MetalRenderer.init` "
          "then returns nil, and EVERY export below would fail with \"Metal is not "
          "available on this system.\" — which reads exactly like a queue defect and is not "
          "one", shader is not None,
          shader_error or os.path.relpath(shader or "", ROOT))

    # ------------------------------------------------------------------
    # 1. The menu and the validator.
    print("\n1. File ▸ Save Frame… ⌥⌘E, Window ▸ Export Queue, and the validator arm")
    menu_answer, menu_error = run_probe(probe, "menu", {
        "mode": "menu",
        "validate": [
            {"name": "a clip on the timeline", "package": packages["card"], "select": [0],
             "selectors": ["saveFrame:", "exportProject:"]},
            {"name": "an empty timeline", "package": packages["empty"], "select": [],
             "selectors": ["saveFrame:", "exportProject:"]},
        ],
    })
    if menu_answer is None:
        print(f"      the probe did not answer: {menu_error}")
        menu_answer = {"menu": {"items": []}, "validation": [], "modifierBits": {}}
    file_items = submenu_items(menu_answer["menu"], "File")
    window_items = submenu_items(menu_answer["menu"], "Window")
    print("      File ▸ " + " · ".join(i["title"] or "—" for i in file_items))
    print("      Window ▸ " + " · ".join(i["title"] or "—" for i in window_items))
    bits = menu_answer.get("modifierBits", {})
    save_frame = find_item(file_items, "Save Frame…")
    export_item = find_item(file_items, "Export…")
    check("File ▸ Save Frame… exists", save_frame is not None,
          "" if save_frame else "there is no Save Frame… item at all")
    check("…over `EditorViewController.saveFrame:` — the selector the extension declares, "
          "not a new one on the delegate",
          (save_frame or {}).get("action") == "saveFrame:", f"{(save_frame or {}).get('action')}")
    check("its key equivalent is the LETTER Export… already has, so the two commands read "
          "as a pair", (save_frame or {}).get("key") == "e"
          and (export_item or {}).get("key") == "e",
          f"Save Frame {(save_frame or {}).get('key')!r}, Export {(export_item or {}).get('key')!r}")
    want = bits.get("command", 0) | bits.get("option", 0)
    check("…and its modifiers are exactly ⌥⌘ — command and option SET, shift and control "
          "CLEAR, read as flags off `NSEvent` rather than as a number written in this file",
          save_frame is not None and bits and save_frame["modifiers"] == want,
          f"{(save_frame or {}).get('modifiers')} against ⌥⌘ = {want} "
          f"(⌘ {bits.get('command')}, ⌥ {bits.get('option')}, ⇧ {bits.get('shift')}, "
          f"⌃ {bits.get('control')})")
    check("Export… still takes PLAIN ⌘E — one letter, two commands, and the modifier is the "
          "whole of what separates them; a Save Frame that had taken the bare key would "
          "have shadowed the movie export",
          export_item is not None and bits and export_item["modifiers"] == bits.get("command"),
          f"{(export_item or {}).get('modifiers')} against ⌘ = {bits.get('command')}")
    titles = [i["title"] for i in file_items]
    check("Save Frame… sits directly under Export… with no separator between them — the "
          "still-image sibling of the movie, in the movie's own group",
          "Export…" in titles and "Save Frame…" in titles
          and titles.index("Save Frame…") == titles.index("Export…") + 1,
          " · ".join(t or "—" for t in titles[-3:]))
    queue_item = find_item(window_items, "Export Queue")
    check("Window ▸ Export Queue exists, over `AppDelegate.showExportQueue:` — the queue "
          "outlives its window, so the item shows the one there is rather than making one",
          queue_item is not None and queue_item["action"] == "showExportQueue:",
          f"{(queue_item or {}).get('action')}" if queue_item else "there is no item")
    check("…and takes NO key equivalent: spec §9's table claims no row for phase 7e, and a "
          "modifier-less menu key is resolved ahead of the first responder",
          queue_item is not None and queue_item["key"] == "",
          f"{(queue_item or {}).get('key')!r}")

    validation = {v["name"]: v for v in menu_answer.get("validation", [])}
    print("      validateUserInterfaceItem: " + json.dumps(
        {k: v.get("enabled") for k, v in validation.items()}, sort_keys=True))
    with_clip = validation.get("a clip on the timeline", {})
    empty = validation.get("an empty timeline", {})
    check("the two fixtures are what they claim to be — one project has a duration and the "
          "other is zero, which is the ONLY thing the arm asks about (a check whose "
          "precondition never held would pass against a build that answers `true` "
          "unconditionally)",
          with_clip.get("duration", 0) > 0 and empty.get("duration", -1) == 0,
          f"{with_clip.get('duration')} ticks against {empty.get('duration')}")
    check("Save Frame… is OFFERED on a timeline with a clip on it",
          with_clip.get("enabled", {}).get("saveFrame:") is True, f"{with_clip.get('enabled')}")
    check("…and REFUSED on a zero-duration project, which is exactly what "
          "`Exporter.renderFrame` answers nil for: without the arm the command falls "
          "through to `validateUserInterfaceItem`'s closing `return true` and is live where "
          "it can only open a panel and then apologise",
          empty.get("enabled", {}).get("saveFrame:") is False, f"{empty.get('enabled')}")
    check("the arm itself answers the same two things — `true` and `false`, never nil, so "
          "the chain's answer above is this arm's and not the fallthrough's",
          with_clip.get("saveFrameArm") is True and empty.get("saveFrameArm") is False,
          f"{with_clip.get('saveFrameArm')} and {empty.get('saveFrameArm')}")
    check("…and `nil` for a selector that is not its own, on BOTH fixtures: an arm that "
          "answered `false` for everything would grey out every other command in the chain "
          "on an empty timeline",
          "armForAnotherSelector" in with_clip and "armForAnotherSelector" in empty
          and with_clip["armForAnotherSelector"] is None
          and empty["armForAnotherSelector"] is None,
          f"{with_clip.get('armForAnotherSelector')} and {empty.get('armForAnotherSelector')}")

    # ------------------------------------------------------------------
    # 2. FrameWriter.
    print("\n2. `FrameWriter` — three containers, one image, and the JPEG flatten")
    spellings = [
        {"name": "shot.png"}, {"name": "shot.jpg"}, {"name": "shot.jpeg"},
        {"name": "shot.JPG"}, {"name": "shot.heic"}, {"name": "shot.HEIC"},
        {"name": "shot.heif"}, {"name": "shot.mov"}, {"name": "shot"},
        {"name": "shot.png", "requested": "jpeg"}, {"name": "shot.jpg", "requested": "png"},
        {"name": "shot.mov", "requested": "heic"},
    ]
    fw, fw_error = run_probe(probe, "framewriter", {
        "mode": "framewriter", "dir": os.path.join(CHROME, "stills"),
        "formats": spellings,
        # A column well inside each band, so no check is reading a JPEG's
        # chroma-subsampled edge.
        "points": [[8, 32], [32, 32], [56, 32]],
    })
    if fw is None:
        print(f"      the probe did not answer: {fw_error}")
        fw = {"cases": [], "formatFor": [], "written": []}
    cases = {c["raw"]: c for c in fw.get("cases", [])}
    order = [c["raw"] for c in fw.get("cases", [])]
    check("`FrameWriter.Format` is exactly three cases, png then jpeg then heic — the "
          "rawValue is the agent's vocabulary and is deliberately NOT the extension",
          order == ["png", "jpeg", "heic"], f"{order}")
    check("each names ONE extension — png / jpg / heic — so the panel, `destinationURL` "
          "and `format(for:)` cannot disagree about what a file of it is called",
          [cases.get(k, {}).get("ext") for k in order] == ["png", "jpg", "heic"],
          f"{[cases.get(k, {}).get('ext') for k in order]}")
    check("…and one display name, PNG / JPEG / HEIC",
          [cases.get(k, {}).get("display") for k in order] == ["PNG", "JPEG", "HEIC"],
          f"{[cases.get(k, {}).get('display') for k in order]}")
    check("the HEIC row is `UTType.heic` and not `public.heif`: only the former is in "
          "`CGImageDestinationCopyTypeIdentifiers()` on this macOS, and a destination made "
          "for the latter is nil with nothing to say",
          [cases.get(k, {}).get("uti") for k in order]
          == ["public.png", "public.jpeg", "public.heic"],
          f"{[cases.get(k, {}).get('uti') for k in order]}")
    check("`carriesAlpha` is true for PNG and HEIC and false for JPEG — which IS the "
          "flatten rule: the one container that cannot hold alpha is the one that gets a "
          "black backdrop",
          [cases.get(k, {}).get("alpha") for k in order] == [True, False, True],
          f"{[cases.get(k, {}).get('alpha') for k in order]}")
    check("PNG's `destinationProperties` is NIL and the two lossy rows' are not. Every "
          "phase from 1 to 6 compares PNG bytes against frames written with nil, so "
          "anything that ADDS metadata changes those files — and this is a STRUCTURAL read "
          "of `!= nil`, which is what makes it the only assertion in either script that "
          "catches `[:]`: an empty dictionary and no dictionary write byte-identical PNGs "
          "on macOS 26.5.1 (measured — same sha256, same 5330 bytes, same chunk list, "
          "across two processes), so no byte comparison could tell them apart. The rule "
          "stays nil as a guard rather than as an observation; the next ImageIO owes us "
          "nothing",
          [cases.get(k, {}).get("hasProperties") for k in order] == [False, True, True],
          f"{[cases.get(k, {}).get('hasProperties') for k in order]}")
    check("the lossy quality is 0.9, a delivery still — not `MediaImporter.writeJPEG`'s "
          "0.7, which is a 54 pt filmstrip thumbnail",
          abs(fw.get("quality", 0) - 0.9) < 1e-9, f"{fw.get('quality')}")
    jpeg_note = cases.get("jpeg", {}).get("note", "")
    check("JPEG's `alphaNote` IS `FrameWriter.flattenNote` and says BLACK out loud — the "
          "sentence the save panel shows is the same string as the behaviour's, so the two "
          "cannot drift",
          jpeg_note and jpeg_note == fw.get("flattenNote") and "black" in jpeg_note.lower(),
          f"{jpeg_note!r}")
    check("…and the other two rows carry a note of their own naming their format and its "
          "alpha, so the line never appears or disappears as the popup is used",
          all("alpha" in cases.get(k, {}).get("note", "").lower()
              and cases[k]["display"] in cases[k]["note"] for k in ("png", "heic")),
          " / ".join(repr(cases.get(k, {}).get("note")) for k in ("png", "heic")))

    reads = {(r["name"], r["requested"]): r["answer"] for r in fw.get("formatFor", [])}
    check("`format(for:)` reads `.png` as PNG and all three spellings of JPEG — `.jpg`, "
          "`.jpeg` and an UPPERCASE `.JPG` — as one case",
          [reads.get(("shot.png", "")), reads.get(("shot.jpg", "")),
           reads.get(("shot.jpeg", "")), reads.get(("shot.JPG", ""))]
          == ["png", "jpeg", "jpeg", "jpeg"],
          f"{[reads.get(('shot.png', '')), reads.get(('shot.jpg', '')), reads.get(('shot.jpeg', '')), reads.get(('shot.JPG', ''))]}")
    check("…and `.heic` in either case",
          [reads.get(("shot.heic", "")), reads.get(("shot.HEIC", ""))] == ["heic", "heic"],
          f"{[reads.get(('shot.heic', '')), reads.get(('shot.HEIC', ''))]}")
    check("…and does NOT recognise `heif`, which is the point: a spelling this app never "
          "writes is part of the NAME, so recognising one the extension-replacement set "
          "does not replace would turn `shot.heif` into `shot.heif.heic`",
          reads.get(("shot.heif", "")) == "png", f"{reads.get(('shot.heif', ''))}")
    check("anything else falls back to PNG — the row that loses nothing — including a name "
          "with a foreign extension and a name with none at all",
          [reads.get(("shot.mov", "")), reads.get(("shot", ""))] == ["png", "png"],
          f"{[reads.get(('shot.mov', '')), reads.get(('shot', ''))]}")
    check("an explicit `requested` wins over the extension in BOTH directions, which is "
          "what the panel's popup and the agent's argument both need",
          [reads.get(("shot.png", "jpeg")), reads.get(("shot.jpg", "png")),
           reads.get(("shot.mov", "heic"))] == ["jpeg", "png", "heic"],
          f"{[reads.get(('shot.png', 'jpeg')), reads.get(('shot.jpg', 'png')), reads.get(('shot.mov', 'heic'))]}")

    written = {w["format"]: w for w in fw.get("written", [])}
    check("all three formats wrote a file from ONE `CGImage`, and each came back readable "
          "as its own type at the source's own size",
          all(written.get(k, {}).get("read", {}).get("uti") == cases.get(k, {}).get("uti")
              and written.get(k, {}).get("read", {}).get("width") == 64
              and written.get(k, {}).get("read", {}).get("height") == 64
              for k in ("png", "jpeg", "heic")),
          " / ".join(
              f"{k}: {written.get(k, {}).get('read', {}).get('uti')} "
              f"{written.get(k, {}).get('bytes')} B "
              f"{written.get(k, {}).get('error', '')}" for k in ("png", "jpeg", "heic")))
    for kind in ("png", "heic"):
        alphas = [s[3] for s in written.get(kind, {}).get("read", {}).get("samples", [])]
        check(f"{cases.get(kind, {}).get('display', kind)} KEPT the alpha channel — the "
              "transparent band reads 0, the half-transparent one reads its own value and "
              "the opaque one reads 255, so nothing was flattened into a format chosen for "
              "carrying it",
              alphas[:1] == [0] and len(alphas) == 3 and 100 <= alphas[1] <= 156
              and alphas[2] == 255, f"alphas {alphas}")
    jpeg_samples = written.get("jpeg", {}).get("read", {}).get("samples", [])
    check("JPEG came back OPAQUE at every sample — it has no alpha channel to carry, which "
          "is why it is the one row that flattens",
          len(jpeg_samples) == 3 and all(s[3] == 255 for s in jpeg_samples),
          f"{jpeg_samples}")
    check("**the JPEG flatten really is onto BLACK.** The source's transparent band is "
          "WHITE at alpha 0 in STRAIGHT alpha, so a build that merely dropped the channel "
          "would write white there and a build that composites over black writes black — "
          "and this is the sample that tells them apart",
          len(jpeg_samples) == 3 and max(jpeg_samples[0][:3]) <= 12,
          f"transparent band reads {jpeg_samples[0][:3] if jpeg_samples else '—'} "
          f"(black is 0, unflattened white would be 255)")
    check("…and the picture DID arrive: the opaque band is white and the half-transparent "
          "one lands between them, so the flatten is a real composite over black and not a "
          "fill that threw the frame away",
          len(jpeg_samples) == 3 and min(jpeg_samples[2][:3]) >= 243
          and 100 <= jpeg_samples[1][0] <= 156,
          f"half {jpeg_samples[1][:3] if jpeg_samples else '—'}, "
          f"opaque {jpeg_samples[2][:3] if jpeg_samples else '—'}")
    refusal = fw.get("refusal", "")
    check("a write that cannot land THROWS and names the PATH — a frame grab answering a "
          "bare `false` would leave a person guessing between a folder they cannot write, "
          "a format this Mac does not know and an encoder that gave up",
          bool(refusal) and "/System/nowhere/card.png" in refusal, f"{refusal!r}")

    # ------------------------------------------------------------------
    # 3. The remembered choice and the named presets, in two processes.
    print("\n3. the remembered choice and the named presets, across a process boundary")
    print("      (the probe binary's OWN defaults domain, never Reelcut.app's — see the "
          "header)")
    presets_path = os.path.expanduser(
        "~/Library/Application Support/Reelcut/ExportPresets.json")
    backup = os.path.join(CHROME, "ExportPresets.backup.json")
    had_presets = os.path.exists(presets_path)
    if had_presets:
        shutil.copy2(presets_path, backup)
    restored = False
    try:
        remembered_ask = {
            "name": "dropped on the way in", "preset_id": "prores_4444",
            "size_row": "1080p", "fps": [24, 1], "quality_tier": "High",
            "loudness": -16.0, "in_out_range": True, "burn_in_timecode": True,
        }
        write_answer, write_error = run_probe(probe, "defaults-write", {
            "mode": "defaults-write",
            "remember": remembered_ask,
            "presets": [
                {"name": "  Review copy  ", "preset_id": "h264", "size_row": "720p",
                 "quality_tier": "Low"},
                {"name": "Master", "preset_id": "prores_4444", "custom_size": [3840, 2160]},
                # The SAME name in another case: the uniqueness rule says this
                # replaces the first record in place rather than appending.
                {"name": "review COPY", "preset_id": "hevc", "size_row": "1080p"},
                # A name that is nothing but spaces cannot be listed or
                # deleted, so `saving` must refuse it.
                {"name": "   ", "preset_id": "gif"},
            ],
            "remove": ["  MASTER "],
        })
        read_answer, read_error = run_probe(probe, "defaults-read", {
            "mode": "defaults-read",
            "lookup": ["Review copy", "review copy", "  review copy  ", "Master", "nope"],
            "corrupt": "{ this is not JSON at all ]]",
        })
        if write_answer is None:
            print(f"      the writing process did not answer: {write_error}")
            write_answer = {}
        if read_answer is None:
            print(f"      the reading process did not answer: {read_error}")
            read_answer = {}
        check("the writing process wrote the presets file, under "
              "`AppSupport.directory` — one spelling of "
              "`~/Library/Application Support/Reelcut/`, which is what `AppSupport.swift` "
              "exists for",
              write_answer.get("wrote") is True
              and write_answer.get("presetsURL", "").endswith(
                  "/Library/Application Support/Reelcut/ExportPresets.json"),
              f"{write_answer.get('presetsURL')}")
        raw = write_answer.get("rawDefaults", "")
        check("the remembered choice is ONE `UserDefaults` key holding the whole record as "
              "JSON, not nine keys — half a remembered choice is a sheet that lies about "
              "what it will export",
              write_answer.get("defaultsKey") == "ReelcutExportChoice"
              and raw.startswith("{") and raw.endswith("}") and "preset_id" in raw,
              f"{write_answer.get('defaultsKey')} = {raw[:96]}…")
        check("…and `remember()` DROPS the name: the remembered choice is nobody's preset, "
              "so the record that goes into defaults carries an empty one however it was "
              "asked", '"name":""' in raw.replace(" ", ""), f"{raw}")
        got = read_answer.get("remembered") or {}
        # All NINE coded fields, `custom_size` included — and it is included as
        # the None it must be rather than as a number, which is the honest
        # shape here: this record was asked with `size_row`, and `ExportChoice`
        # calls a record carrying BOTH a hand-edited file's state, so pinning
        # the two together would pin something the sheet cannot produce. The
        # positive direction is the "Master" preset's, two checks below. Until
        # the review this dict had eight keys while the sentence said nine, so
        # a decoder that INVENTED a custom size here was invisible.
        want_back = dict(remembered_ask, name="", custom_size=None)
        differing = sorted(k for k, v in want_back.items() if got.get(k) != v)
        check("a SECOND PROCESS reads the whole record back — every one of the nine fields, "
              "with the name cleared and nothing else changed",
              got and not differing,
              "" if got and not differing else f"differs in {differing}: {json.dumps(got)}")
        check("an EMPTY string reads as \"nothing remembered\", which is what "
              "`string(forKey:)` of an absent key answers and what "
              "`tools/proof/harness/main.swift`'s `pinDefaults` pins the key to — so every "
              "chrome render is of a first-run card whatever the developer last exported",
              read_answer.get("rememberedWhenEmpty", "unset") is None,
              f"{read_answer.get('rememberedWhenEmpty')}")
        names = [p["name"] for p in read_answer.get("presets", [])]
        check("the named presets survive the process boundary in the order they were first "
              "saved — a person's own order is information, so the list is not sorted",
              names == ["review COPY", "Master"], f"{names}")
        # **The FILE, field for field, and not just the names.** Every other
        # assertion about the presets list projects `["name"]`, so until the
        # review `custom_size` was the one `ExportChoice` field nothing in
        # either script ever read back: `customSize = nil` in the decoder
        # would have scored a clean run — nobody ran it, which is the point:
        # fifteen mutants are a sample of the edits somebody might make, not a
        # search for the checks that cannot fail. A person reapplying a preset
        # saved off Custom 3840 × 2160 would get the document's own size with
        # the popup claiming the preset had been applied — `applySize` returns
        # on a nil custom size and says nothing.
        # Both directions are pinned here — the record that HAS one and the
        # record beside it that must not have grown one.
        stored = {p.get("name"): p for p in read_answer.get("presets", [])}
        want_master = {
            "name": "Master", "preset_id": "prores_4444", "size_row": None,
            "custom_size": [3840, 2160], "fps": None, "quality_tier": None,
            "loudness": None, "in_out_range": False, "burn_in_timecode": False,
        }
        master = stored.get("Master") or {}
        master_differs = sorted(k for k, v in want_master.items() if master.get(k) != v)
        check("…and a preset's WHOLE record survives it, field for field — the nine of them, "
              "`custom_size` included. A named preset is a row of controls and a size typed "
              "into Custom… is one of them: restored as nil it falls through `applySize` "
              "with the popup still showing the document's own size and nothing said",
              bool(master) and not master_differs
              and stored.get("review COPY", {}).get("custom_size") is None,
              f"Master differs in {master_differs}: {json.dumps(master, sort_keys=True)}; "
              f"review COPY's custom_size is "
              f"{stored.get('review COPY', {}).get('custom_size')!r}")
        saved = [p["name"] for p in write_answer.get("saved", [])]
        check("a re-save under a name that differs only in CASE and whitespace REPLACES the "
              "record in place — the same name is the same preset, so the popup does not "
              "reshuffle under the pointer and Delete never has to guess which of two rows "
              "was meant", saved == ["review COPY", "Master"], f"{saved}")
        check("…and a name that is nothing but whitespace is refused: a record with no name "
              "cannot be listed by a popup keyed on titles and cannot be deleted, so it is "
              "never made", len(saved) == 2, f"{len(saved)} records from four saves")
        after = [p["name"] for p in write_answer.get("afterRemove", [])]
        check("`removing(named:)` matches on the same trimmed, case-insensitive rule as "
              "saving — \"  MASTER \" removes \"Master\" and leaves the other alone",
              after == ["review COPY"], f"{after}")
        lookup = {l["ask"]: (l["found"] or {}).get("name") for l in read_answer.get("lookup", [])}
        check("`preset(named:)` answers the stored record for every spelling of its name "
              "and nil for a name nobody saved",
              lookup.get("Review copy") == "review COPY"
              and lookup.get("review copy") == "review COPY"
              and lookup.get("  review copy  ") == "review COPY"
              and lookup.get("Master") == "Master" and lookup.get("nope") is None,
              json.dumps(lookup, sort_keys=True))
        check("a CORRUPT presets file degrades to \"no presets\" and does not throw: the "
              "list is a convenience over a dialog that works perfectly without it, so the "
              "worst a broken preferences file may cause is an empty popup — never a lost "
              "export and never a modal about a file in the middle of somebody's work",
              read_answer.get("corruptSurvived") is True
              and read_answer.get("corruptCount") == 0,
              f"{read_answer.get('corruptCount')} presets read back from nonsense")
    finally:
        clean, clean_error = run_probe(probe, "defaults-clean", {
            "mode": "defaults-clean", "deletePresets": not had_presets,
        })
        if had_presets:
            shutil.copy2(backup, presets_path)
        restored = (
            (had_presets and same_file(backup, presets_path))
            or (not had_presets and not os.path.exists(presets_path)))
    check("this script put back what it touched outside the tree — the probe's one defaults "
          "key is gone and the user's own `ExportPresets.json` is byte for byte what it was "
          "(or is absent again, if there was none)",
          restored and (clean or {}).get("remembered", "unset") is None,
          f"presets file {'restored' if restored else 'NOT restored'}; "
          f"remembered now {(clean or {}).get('remembered')}"
          + (f"; clean probe: {clean_error}" if clean is None else ""))

    # ------------------------------------------------------------------
    # 4. The export queue.
    print("\n4. `ExportQueueController` — two jobs, one at a time, and nothing a later edit "
          "can reach")
    print("      (byte claims over `apng`; a QuickTime movie carries a clock — see the "
          "header)")
    singles = {}
    for tag, package, kw in (
        ("plain", "card", {}),
        ("burnt", "card", {"burn_in": True}),
        ("edited", "card", {"edit": [1.0, 0.0, 0.0, 1.0]}),
        # The same pair on a taller canvas, for the placement check below.
        ("tall-plain", "tall", {}),
        ("tall-burnt", "tall", {"burn_in": True}),
    ):
        answer, error = run_probe(probe, f"single-{tag}", dict({
            "mode": "export-single", "package": packages[package], "preset": "apng",
            "out": out(f"single-{tag}.png"), "timeout": 180,
        }, **kw))
        singles[tag] = (answer or {}, error)
    check("five single exports through `Exporter` itself — the export sheet's own path — "
          "all completed, so the queue has something to be compared against",
          all(a.get("state") == "completed" for a, _ in singles.values()),
          " / ".join(f"{k}: {a.get('state')} {a.get('message', '')} {e or ''}"
                     for k, (a, e) in singles.items()))
    check("the three differ from each other: the burn-in changes the picture and so does "
          "the edit, which is the PRECONDITION every claim below leans on — two files that "
          "were going to be identical anyway prove nothing about what wrote them",
          not same_file(out("single-plain.png"), out("single-burnt.png"))
          and not same_file(out("single-plain.png"), out("single-edited.png")),
          f"plain {size_of(out('single-plain.png'))} B, "
          f"burnt {size_of(out('single-burnt.png'))} B, "
          f"edited {size_of(out('single-edited.png'))} B")

    # The burn-in, measured on the exported frames themselves. An APNG never
    # goes through `ExportWriter` at all — `ImageSequenceWriter` calls
    # `Exporter.renderFrame` per frame through a `RecipeSource` key of its own —
    # so "the option reached an image-sequence export" is a claim the contract
    # (D7) names as the one that would be silently missed.
    bands = {
        "360": changed_row_band(out("single-plain.png"), out("single-burnt.png")),
        "720": changed_row_band(out("single-tall-plain.png"), out("single-tall-burnt.png")),
    }
    check("the timecode burn-in reaches an APNG export, at both canvas heights — an image "
          "sequence never goes through `ExportWriter`, so an option plumbed only through "
          "the export's own recipe key would leave every GIF and APNG silently un-burnt",
          all(bands.values()),
          " / ".join(f"{k}: " + ("no pixel changed" if v is None else
                                 f"rows {v[0]}–{v[1]} of {v[2]}, x {v[3]}–{v[4]} of {v[5]}")
                     for k, v in bands.items()))
    check("…and it is a NARROW band across the middle of the frame's width, which is what "
          "one line of centred monospace with a backdrop looks like — not a whole-frame "
          "difference, which is what a burn-in that had changed the picture some other way "
          "would give",
          all(v is not None and (v[1] - v[0] + 1) < 0.1 * v[2]
              and v[3] > 0 and v[4] < v[5] - 1
              and (v[4] - v[3] + 1) < 0.6 * v[5]
              for v in bands.values()),
          " / ".join(f"{k}: {v[1] - v[0] + 1} rows of {v[2]}, "
                     f"{v[4] - v[3] + 1} columns of {v[5]}" if v else f"{k}: —"
                     for k, v in bands.items()))
    # `BURN_IN_Y_FRACTION` is 0.44 of the canvas height BELOW the centre, which
    # `recipe_text.rs` spells out as "94 % of the way down the frame" — a
    # fraction, so it is the same number whatever size the row resolves to and
    # whatever height the canvas is.
    fractions = {
        k: (None if v is None else ((v[0] + v[1]) / 2) / v[2]) for k, v in bands.items()
    }
    check("**the burn-in sits 94 % of the way down the frame — `BURN_IN_Y_FRACTION` (0.44) "
          "of the canvas height below its centre — at BOTH heights.** It is a fraction, so "
          "one measurement cannot say it: 360 is exactly the height at which 0.44 x height "
          "and the literal 158.4 agree, and a proof written at that height alone would pass "
          "against a placement that is a constant",
          all(f is not None and abs(f - 0.94) < 0.04 for f in fractions.values()),
          " / ".join(f"{k}: box centre at {f:.3f} of the frame height"
                     if f is not None else f"{k}: nothing drawn"
                     for k, f in fractions.items())
          + "   (0.940 is the documented placement)")

    queue_answer, queue_error = run_probe(probe, "queue-run", {
        "mode": "queue", "package": packages["card"], "preset": "apng",
        "jobs": [
            {"out": out("queued-plain.png"), "burn_in": False},
            {"out": out("queued-burnt.png"), "burn_in": True},
        ],
        # The edit lands after BOTH enqueues and before the run loop has been
        # spun once, so it precedes the first frame either job composes.
        "edit_after_enqueue": [1.0, 0.0, 0.0, 1.0],
        # Proportionate rather than generous: these two jobs take well under a
        # second each, so three minutes is two orders of magnitude of headroom
        # and a DEADLOCKED queue — which is what two concurrent `Exporter`s
        # give, measured — fails by name in three minutes instead of ten.
        "timeout": 180,
    })
    if queue_answer is None:
        print(f"      the probe did not answer: {queue_error}")
        queue_answer = {}
    print(f"      transitions: {queue_answer.get('transitions')}")
    jobs = {j["id"]: j for j in queue_answer.get("jobs", [])}
    check("`enqueue` starts the queue itself: after two jobs are added, ONE is running and "
          "ONE is waiting — nothing had to press start",
          queue_answer.get("idleBefore") is True
          and queue_answer.get("runningAfterEnqueue") == 1
          and queue_answer.get("waitingAfterEnqueue") == 1,
          f"idle before {queue_answer.get('idleBefore')}, running "
          f"{queue_answer.get('runningAfterEnqueue')}, waiting "
          f"{queue_answer.get('waitingAfterEnqueue')}")
    check("both jobs completed and the queue went idle, driven with NO window ever ordered "
          "front — which is what `ExportQueueController`'s AppKit-free design was for",
          queue_answer.get("settled") is True and queue_answer.get("idleAfter") is True
          and [j.get("state") for j in queue_answer.get("jobs", [])]
          == ["completed", "completed"],
          " / ".join(f"{j['id']}: {j['state']} {j['message']}"
                     for j in queue_answer.get("jobs", [])))
    check("ONE AT A TIME: at no observation of the queue's own change notification were two "
          "jobs running — a `DispatchQueue` of exporters would be the wrong shape whatever "
          "the core count, because `Exporter.export` is main-thread-only and schedules a "
          "run-loop timer",
          queue_answer.get("maxRunning") == 1,
          f"{queue_answer.get('maxRunning')} at once over "
          f"{queue_answer.get('observations')} observations")
    check("…and IN ORDER: job 1 finished before job 2 started, read off the notification "
          "rather than polled, so a transition between two spins cannot be missed",
          queue_answer.get("transitions")
          == ["1:waiting", "1:running", "2:waiting", "1:completed", "2:running",
              "2:completed"],
          f"{queue_answer.get('transitions')}")
    check("**the queued file is BYTE-IDENTICAL to a single export of the same project, "
          "settings and options** — the queue is a list of calls that were going to be "
          "made, not a second way of making them",
          same_file(out("queued-plain.png"), out("single-plain.png")),
          f"{size_of(out('queued-plain.png'))} B against "
          f"{size_of(out('single-plain.png'))} B")
    check("…and so is the second, whose `RecipeOptions` asked for the burn-in: the option "
          "is carried PER JOB, because two jobs from one document may legitimately differ "
          "in it", same_file(out("queued-burnt.png"), out("single-burnt.png")),
          f"{size_of(out('queued-burnt.png'))} B against "
          f"{size_of(out('single-burnt.png'))} B")
    check("the two queued files DIFFER from each other, so the per-job option reached the "
          "write rather than both jobs writing the queue's first answer twice",
          not same_file(out("queued-plain.png"), out("queued-burnt.png")),
          f"{jobs.get(1, {}).get('burn_in')} against {jobs.get(2, {}).get('burn_in')}")
    check("**an edit made to the document AFTER the enqueue and BEFORE the run does not "
          "reach either file.** The handle is immutable and the media URLs were resolved at "
          "enqueue, so a queued write cannot be reached by an edit, an undo or a Relink… "
          "made while it waits",
          queue_answer.get("documentBackgroundNow") == [1.0, 0.0, 0.0, 1.0]
          and same_file(out("queued-plain.png"), out("single-plain.png"))
          and not same_file(out("queued-plain.png"), out("single-edited.png")),
          f"the document's canvas is {queue_answer.get('documentBackgroundNow')} now; the "
          f"file matches the PRE-edit export and not the post-edit one "
          f"({size_of(out('single-edited.png'))} B)")

    cancel_answer, cancel_error = run_probe(probe, "queue-cancel", {
        "mode": "queue", "package": packages["long"], "preset": "h264",
        "jobs": [{"out": out("cancelled.mov")}, {"out": out("after-cancel.mov")}],
        # Cancel as soon as the running job reports progress — by which point
        # `ExportWriter` has opened its file. The threshold is small so the
        # cancel lands mid-write rather than after the end.
        "cancel_when_progress": 0.02,
        # Longer than the other two: this one exports 25 s of 1080p H.264.
        "timeout": 300,
    })
    if cancel_answer is None:
        print(f"      the probe did not answer: {cancel_error}")
        cancel_answer = {}
    cancelled_jobs = {j["id"]: j for j in cancel_answer.get("jobs", [])}
    check("the cancel's PRECONDITION held: the job was running and its file was ON DISK at "
          "the moment the cancel was asked for — a \"the file is gone\" check whose file "
          "was never there would pass against a build that deletes nothing",
          cancel_answer.get("cancelledID") == 1
          and cancel_answer.get("existedAtCancel") is True,
          f"job {cancel_answer.get('cancelledID')} at progress "
          f"{cancel_answer.get('progressAtCancel')}, file present "
          f"{cancel_answer.get('existedAtCancel')}")
    check("a cancelled job ends `.cancelled` and leaves NO file behind — a stopped export "
          "that left a truncated movie under the name a person chose for a whole one is "
          "debris they never asked for. **The claim is the OUTCOME and not the queue's own "
          "`removeItem`**, and that is a mutation result rather than a preference: with "
          "that line deleted nothing is left behind anyway, because "
          "`AVAssetWriter.cancelWriting()` removes its own part-file (`ExporterWriter.swift` "
          "says so) and `ImageSequenceWriter` removes its own — so the queue's line is "
          "defence in depth and no check here can separate the three",
          cancelled_jobs.get(1, {}).get("state") == "cancelled"
          and cancelled_jobs.get(1, {}).get("exists") is False,
          f"{cancelled_jobs.get(1, {}).get('state')}, file present "
          f"{cancelled_jobs.get(1, {}).get('exists')}: "
          f"{cancelled_jobs.get(1, {}).get('message')}")
    check("…and the QUEUE carries on: the job behind it ran and landed, so a cancel is one "
          "job being stopped rather than the list being abandoned",
          cancelled_jobs.get(2, {}).get("state") == "completed"
          and cancelled_jobs.get(2, {}).get("exists") is True
          and cancel_answer.get("transitions")
          == ["1:waiting", "1:running", "2:waiting", "1:cancelled", "2:running",
              "2:completed"],
          f"{cancel_answer.get('transitions')}")

    remove_answer, remove_error = run_probe(probe, "queue-remove", {
        "mode": "queue", "package": packages["card"], "preset": "apng",
        "jobs": [{"out": out("remove-1.png")}, {"out": out("remove-2.png")}],
        "remove_unfinished": True, "remove_finished": True, "clear_finished": True,
        "timeout": 180,
    })
    if remove_answer is None:
        print(f"      the probe did not answer: {remove_error}")
        remove_answer = {}
    check("`remove` REFUSES a job that has not finished — asked for both while one was "
          "running and one was waiting, and the list came back the same length: a row is "
          "cancelled first, which is what the window's one button does in its two states",
          remove_answer.get("removeUnfinished") == {"before": 2, "after": 2},
          f"{remove_answer.get('removeUnfinished')}")
    check("…and takes ONE once it HAS finished, which is the other half of the same rule — "
          "the row named is the row that goes, and the one beside it stays, which is what "
          "says `remove` addresses a job by id and does not wipe the list",
          remove_answer.get("removeFinished") == {"before": 2, "after": 1, "removed": 1},
          f"{remove_answer.get('removeFinished')}")
    check("`clearFinished` drops the finished row `remove` left behind, and the queue it "
          "leaves is empty and idle. **The precondition is the check**: this was asked in "
          "the same probe run as `remove_finished` until the review, which removed BOTH "
          "rows first — so the clear ran over an empty list and answered 0 for any body, "
          "gutted or not. It is asked with exactly one finished job in the list now, and a "
          "`clearFinished()` that did nothing would answer 1",
          remove_answer.get("beforeClear") == 1
          and remove_answer.get("afterClear") == 0
          and remove_answer.get("idleAfterClear") is True,
          f"{remove_answer.get('beforeClear')} job in the list before the clear, "
          f"{remove_answer.get('afterClear')} after; idle {remove_answer.get('idleAfterClear')}")

    # ------------------------------------------------------------------
    # 5. The Document tab's transparency note — the one photograph.
    print("\n5. the Document tab's transparency note")
    renders = {
        tag: render(harness, packages[tag], png(tag))
        for tag in ("doc-black", "doc-white", "doc-half", "doc-a99", "doc-a999")
    }
    images = LazyImages(renders)
    black = images["doc-black"]
    scale = black.scale
    inspector = Rect("the inspector", INSPECTOR_X, 0, INSPECTOR_W, HEIGHT)
    summary = Rect("the Document summary line", LABEL_X0, SUMMARY_Y0,
                   CONTROL_X1 - LABEL_X0, SUMMARY_H)
    above = Rect("everything above the Appearance section", INSPECTOR_X, 0, INSPECTOR_W,
                 ABOVE_Y1)
    band = Rect("the Markers section under Appearance", INSPECTOR_X, BELOW_Y0, INSPECTOR_W,
                BELOW_H)

    opaque_diff = inside(changed_pixels(black, images["doc-white"]), inspector, scale)
    print(f"\n   two OPAQUE canvases (black against white): {len(opaque_diff)} changed "
          f"pixels in the inspector, in {len(clusters(opaque_diff))} clusters:")
    print(describe(clusters(opaque_diff), scale))
    opaque_shift = shift_match(black, images["doc-white"], band)
    check("changing an opaque background changes the summary line and the swatch and MOVES "
          "NOTHING — the control this section needs, because without it a shift measured "
          "below could be any background change rather than the note",
          bool(opaque_diff) and opaque_shift[0] == (0, 0)
          and opaque_shift[1][0] >= SHIFT_MARGIN,
          f"the winning shift is {opaque_shift[0][1]} pt with {opaque_shift[0][0]} "
          f"mismatched rows; the runner-up is {opaque_shift[1][1]} pt with "
          f"{opaque_shift[1][0]}")

    note_diff = inside(changed_pixels(black, images["doc-half"]), inspector, scale)
    print(f"\n   opaque against TRANSLUCENT: {len(note_diff)} changed pixels in the "
          f"inspector, in {len(clusters(note_diff))} clusters:")
    print(describe(clusters(note_diff), scale))
    scores = shift_match(black, images["doc-half"], band)
    shift = scores[0][1]
    check("a TRANSLUCENT canvas pushes everything below the Appearance section DOWN by an "
          "exact whole number of points — every row of the band explained, and the "
          "runner-up far worse, which is what says the number was measured and not "
          "preferred",
          scores[0][0] == 0 and scores[0][1] > 0 and scores[1][0] >= SHIFT_MARGIN,
          f"{shift} pt with {scores[0][0]} mismatched rows of "
          f"{int(BELOW_H * scale)}; runner-up {scores[1][1]} pt with {scores[1][0]}")
    check(f"…and what was inserted is ONE LABEL row, not a control row and not a section: "
          f"the growth is more than the stack's own row spacing ({ROW_SPACING} pt) and less "
          f"than a control row and its spacing ({CONTROL_H + ROW_SPACING} pt), which is "
          f"exactly what an `InspectorNoteLabel` at 11 pt costs",
          ROW_SPACING < shift < CONTROL_H + ROW_SPACING,
          f"{shift} pt = {ROW_SPACING} pt of spacing + a {shift - ROW_SPACING} pt label")
    stray = outside(inside(note_diff, above, scale), [summary], scale)
    check("nothing above the Appearance section moved or redrew except the Document "
          "summary, which legitimately reads \"Black · 50%\" instead of \"Black\" — so the "
          "note is INSIDE the section whose value it is about, and the Canvas and Frame "
          "Rate sections above it were not touched",
          bool(inside(note_diff, summary, scale)) and not stray,
          f"{summary}" if not stray else f"{len(stray)} px elsewhere above y {ABOVE_Y1} pt:\n"
          + describe(clusters(stray), scale))

    # The note's own row, located from the pixels rather than written down: the
    # first row below the sections above that the two renders disagree about is
    # where the Appearance section's content begins, and the note is the
    # `shift - ROW_SPACING` points from there.
    below_top = [p for p in note_diff if p[1] >= ABOVE_Y1 * scale]
    content_top = min((p[1] for p in below_top), default=0) / scale
    note_row = Rect("the note row", LABEL_X0, content_top, CONTROL_X1 - LABEL_X0,
                    max(shift - ROW_SPACING, 1))
    accent_patch = Rect("the Export button's fill", ACCENT_X0, ACCENT_Y0, ACCENT_W, ACCENT_H)
    accent, accent_count, accent_total = modal_pixel(images["doc-half"], accent_patch)
    check("the accent probe lands inside a flat fill — the toolbar's Export button is an "
          "`AccentButton` painted in `DS.accent`, and this rectangle has to be INSIDE it "
          "for the comparison below to mean anything",
          accent is not None and accent_count > 0.75 * max(accent_total, 1),
          f"{accent} covers {accent_count}/{accent_total} px of {accent_patch}")
    background, _, _ = modal_pixel(images["doc-half"], note_row)
    ink, ink_count, _ = modal_pixel(images["doc-half"], note_row, exclude={background})
    check("the note is drawn in the ACCENT — its ink is the same pixel as the Export "
          "button's fill, measured in the same render, so this holds whatever colour the "
          "person at the machine chose in System Settings and no colour is written down "
          "here", ink is not None and accent is not None and ink == accent,
          f"{note_row}: ink {ink} ({ink_count} px) against the button's {accent}")
    opaque_ink, _, _ = modal_pixel(
        images["doc-black"], note_row,
        exclude={modal_pixel(images["doc-black"], note_row)[0]})
    check("…and the same band of the OPAQUE render holds a different ink entirely — it is "
          "the Background row's label, which the note pushed down rather than replaced",
          opaque_ink is not None and ink is not None and opaque_ink != ink,
          f"opaque {opaque_ink} against translucent {ink}")

    a99 = shift_match(black, images["doc-a99"], band)
    a999 = shift_match(black, images["doc-a999"], band)
    check("the threshold is `alphaComponent < 0.995` and it is pinned from BOTH sides: an "
          "alpha of 0.99 gets the note and an alpha of 0.999 does not, so a build that had "
          "quietly moved it would fail here rather than at some number nobody rendered",
          a99[0] == (0, shift) and a999[0] == (0, 0)
          and a99[1][0] >= SHIFT_MARGIN and a999[1][0] >= SHIFT_MARGIN,
          f"0.99 → {a99[0][1]} pt ({a99[0][0]} mismatched); "
          f"0.999 → {a999[0][1]} pt ({a999[0][0]} mismatched)")

    # ------------------------------------------------------------------
    # 6. The instruments' own honesty.
    print("\n6. the instruments themselves")
    check("no render reported an unsettled layout", not WARNINGS,
          "" if not WARNINGS else "\n".join("      " + w for w in WARNINGS))
    failed = [tag for tag, ok, _ in PROBE_RUNS if not ok]
    check("every probe invocation answered — a mode that crashed or wrote nothing would "
          "have failed its own section's checks by name above, and this is the line that "
          "says how many ran",
          not failed and len(PROBE_RUNS) >= 8,
          f"{len(PROBE_RUNS)} runs, "
          + ", ".join(f"{tag} {seconds:.1f} s" for tag, ok, seconds in PROBE_RUNS if ok)
          + (f"; FAILED: {failed}" if failed else ""))

    # Crops for the eye check.
    crop = Rect("inspector", INSPECTOR_X, TOOLBAR, INSPECTOR_W, 700)
    for tag in ("doc-black", "doc-half"):
        images[tag].crop(crop, os.path.join(CHROME, f"crop-{tag}.png"))
    print(f"\nRenders, crops, written stills, exported files and every probe answer are in "
          f"{os.path.relpath(CHROME, ROOT)}/")
    print("Nothing about Save Frame's PANEL, the export SHEET or the queue's WINDOW is "
          "photographed here —\nnone of the three is in the view the harness captures. The "
          "ProRes 4444 row is phase7_proof.py's.")

    passed = sum(RESULTS)
    print(f"\n{passed}/{len(RESULTS)} checks passed")
    sys.exit(0 if passed == len(RESULTS) else 1)


if __name__ == "__main__":
    main()
