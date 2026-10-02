#!/usr/bin/env python3
"""Road map 2, phase 5 (Sound) — the CHROME half of the proof, and the meter's
reading.

Phase 5 is five features and four of them are audio, which a still frame
cannot hold an opinion about. Mono, Normalise, loudness and the two LPCM
rows are `tools/proof/phase5_proof.py`'s, over MCP against a running app and
sample-for-sample against decoded exports. What is left for an offscreen
renderer is the ONE thing phase 5 draws:

    5b  the output level meter in the timeline bar (`LevelMeterView`,
        `TimelineBar.build`) — that its resting appearance is drawn at all,
        that it is drawn where the layout constants say and at the size they
        say, that it took nothing from anything that shipped, and that at the
        900 pt minimum window it VANISHES rather than pushing a control
        sideways or breaking a constraint.

**Section 8 is not a picture**, and it is the half with arithmetic behind it:
what the meter READS. The contract's claim is that on a −20 dBFS tone the
published model reads −20 dBFS within ±0.5 dB, and it says to assert the
MODEL rather than pixels — which is right twice over. The harness has no
player, so every chrome render photographs a meter at rest and a lit one
could not be photographed at all; and the ballistics that would light it
(peak hold, the fall, the clip dwell) belong to the view, while the number
belongs to the model. So section 8 hands the model buffers of samples this
script authored and reads back what it published. One check there hands it
four magnitudes instead of a buffer, and says why where it stands: the
invariant `LevelMeterReading.init` restores is one no buffer can violate, so
a check over a measured tone would be green against the build with the clamp
deleted. Nothing there is a picture and nothing there is claimed to be one.

**Section 9 is not a picture either**, and it is here for section 8's reason
one step further on. The export gain is decided in one pure function over
three doubles (`ExportLoudness.resolve`, `app/Sources/Loudness.swift`), and
the only way `phase5_proof.py` can reach it is to export a whole file and
read the report back — which asks about ONE measured true peak, whichever
that Mac's decode happened to give. The gain is quantised to a 0.01 dB grid,
so whether a ceiling-capped export lands over its ceiling depends on where
the measured peak falls in that grid: one fixture answers that by coin toss
and a sweep of 200 peaks answers it. `Loudness.swift` has no AVFoundation, no
AppKit and no project in it, so unlike the meter it needs neither the harness
nor a stand-in — this script writes a `main.swift`, compiles the two together
in under a second, and hands the probe its cases as JSON.

Every claim in sections 1–7 is a BYTE comparison of two PNGs the offscreen
harness wrote (`tools/proof/harness/`, CLAUDE.md's "Seeing the chrome"), then
a measurement of WHERE the changed pixels landed against rectangles derived
from the app's own layout constants. `phase4_chrome.py` is the model and this
file follows it.

**The second PNG is the build BEFORE the meter existed**, and that is this
script's one new instrument. Phases 2–4 compared two renders of one binary
that differed in the document or in a pinned default; a meter is neither —
it is always drawn, identically, whatever the package says — so the only
comparison that can say "this is what the phase added, and this is all of
it" is against the chrome as it was. `reference_commit()` finds that tree
without a checkout: the parent of the commit that ADDED
`app/Sources/LevelMeterView.swift`, or HEAD while the phase is still
uncommitted, extracted with `git archive` into `work/chrome5/before/` and
compiled with its matching Rust core and bridging header, and the SAME
current `harness/main.swift` under `HARNESS_REFERENCE_BUILD`. This preserves
the historical source/FFI contract while using one paint instrument. The answer is
worth the 35 s it costs: at 1440 in both appearances, and at 1080 and 1600,
the TIMELINE BAR differs in exactly one 120 × 12 rectangle — 4 704 pixels of
it, and not one anywhere else in the row — and at the 900 pt minimum it does
not differ at all.

**The bar and not the whole window, and that is the one thing this script
promises about a future it cannot see.** A cross-build comparison holds the
current tree to a tree that ages: phase 6 adds inspector sections, phase 7
touches the export chrome, and the first of them would make a whole-window
comparison fail with the meter itself untouched — a proof that breaks on
being right, in a repository whose rule is that every earlier phase's script
re-runs unchanged. So sections 3, 5 and 6 score only what happened inside
`bar_rect`, the row the meter went into and whose slack it took, and print
what changed elsewhere without scoring it. Nothing is lost by it: all five
chrome mutations below are bar-local, because every way a level meter can be
wrong is a way the timeline bar looks wrong. **Section 3b is the check that
the scoping works** — the same reference render against a current one whose
PLAYHEAD has moved, which changes the toolbar's timecode and the ruler's
line and nothing the bar draws. It is the shape of every later phase's chrome
change, staged: the window differs in four places and the bar still differs
in exactly the meter's 4 704 pixels. (Measured, with that scoping reverted:
the same pair fails, 80/81.) What a change to the BAR itself would do is not
covered and is not meant to be — a phase that redraws this row is a phase
that has to re-baseline this comparison, and section 3's rectangle
measurements are what will tell it so.

The instrument itself is guarded the same way. The reference is compiled with
the CURRENT `harness/main.swift` under `-D HARNESS_REFERENCE_BUILD` — one
general flag, not a per-phase one, so a later phase's mode goes behind the
same `#if`. A reference build
that cannot be made at all is a scored FAILURE and not a `sys.exit`: it is
the only thing here that reaches backwards in the history, so it is the only
thing that can rot on its own, and it must not take the model checks — which
need no reference at all — down with it. A failed current harness build also
leaves the independent gain checks running; meter requests and renders cannot.

**One harness change, and the phase's plan said there would not be one.**
Wave 2B measured the meter's rect and reported the model reachable without
touching `harness/main.swift`, by compiling `app/Sources/LevelMeter.swift`
alone against a stand-in for the two types it borrows — and that was true
when they wrote it. Wave 6 then moved `LevelMeterEnvelope`'s search into
`MediaPeaks.envelope`, so the app would have ONE spelling of the plan's mix
rule rather than the two phase 5 shipped with; `MediaPeaks` needs
`ProjectSnapshot`, `ReelTime` and `MediaImporter`, and standing those in
would make this script measure its own arithmetic instead of the app's. So
the harness grew a third mode, `harness meter <request.json> <out.json>`, in
phase 4's `cues` shape: it renders nothing, changes no render argument, is
answered before AppKit wakes, and exists because the code it calls has no
other caller a script can reach. The signal is a file THIS script writes, so
the tone is the caller's and not the instrument's. The mode's one later
addition is `store`, four magnitudes going straight into `LevelMeterSink`
in place of a measured file, for the one reading a buffer cannot carry.

The package is written BY HAND (a `.reelcut` is a directory holding
`project.json`, spec §5.2) around one text clip, so nothing loads
asynchronously and every render is deterministic — no media at all. One
package is enough: the meter reads `LevelMeter.shared` and not the document,
so no project can change what it draws, which is itself half of what
section 3 measures.

THE WINDOW IS 1440 x 862 — phase 2's, and the size wave 2B measured the
meter's rect at. A text clip's sixteen inspector sections overflow their
scroll view at that height, which is what makes the whole-window byte
comparison safe: a section stack with slack hands it to whichever section
will stretch and which one wins is decided per PROCESS (app/CLAUDE.md's
fourth inspector pitfall, and `phase4_chrome.py`'s `SHAPE_HEIGHT` note).
Three more widths are rendered — 900 (the minimum), 1080 and 1600 — because
what the meter must do at each of them is different. And the 900 pt window is
rendered TWICE, the second time with `OS_ACTIVITY_DT_MODE` set: AppKit's
"Conflicting constraints detected" goes to the unified log and never to a
pipe without it, so a row the solver had to break to lay out is the one
failure a byte comparison cannot see. It is a separate render because that
switch also mirrors every unrelated framework `os_log` line, which would
drown the harness's own one-line settle warning.

Every check here was MUTATION-TESTED against deliberately broken builds of
the same sources, each compiled outside the repository so the tree was never
touched. A check nothing can break is not a check, and each number below
names the ones that broke. The two halves come apart cleanly, which is
itself worth knowing: no chrome mutation moved a model check and no model
mutation moved a chrome one.

Sections 1–7, the CHROME's forty-five, against five mutations of
`TimelineBar.swift` and `LevelMeterView.swift`: dropping `LevelMeterView()`
from the row (16/45), moving it to the END of the row, after S/M/L (19/45),
dropping the `minimumWidth` guard so a starved meter draws a two-point scale
instead of nothing (44/45 — ONLY the 900 pt window's bar identity, which is
the whole argument for rendering the minimum window at all), widening the
clip cell from 3 pt to 6 (43/45 — only the two column measurements, which is
what a geometry solved out of pixels is for), and giving the meter a
REQUIRED 2000 pt width so the row cannot be laid out at all (19/45,
including section 7's — the same render then logs 252 lines of "Conflicting
constraints detected", which is what says that check can fail; a required
400 pt width does NOT break one, because the stack view can compress the
selection block and the buttons to make room, so it fails on the pixels
alone). Every one of the five is bar-local — which is the measurement behind
the paragraph above, and the reason scoping the comparison to the row cost
this section nothing: the five were run against the forty-two checks phase 5
shipped and again against the forty-five here, and each broke the same
checks.

Section 8, the MODEL's twenty-three, against four mutations of
`LevelMeter.swift` and one of `MediaPeaks.swift`: measuring RMS where peak is
asked for (10/23), writing `decibels` as `10 * log10` (9/23 — right at
0 dBFS and wrong at every other level, which is why the sweep is a sweep),
dropping the `scaled(by:)` multiply so the meter reports pre-fader (19/23 —
the three envelope legs and the mute, which is the D-0 decision this phase
turns on), `MediaPeaks.envelope` answering a ramp's `from` instead of
interpolating (20/23), and deleting `LevelMeterReading.init`'s
`min(sanitised(rms), peak)` clamp (22/23 — the torn-read check alone, which
is the whole reason that check hands the sink a pair rather than a buffer:
the phase shipped asserting `rms ≤ peak` of a MEASURED tone, and no buffer
can break that, so the check was green against a build with the clamp gone).

Section 9, the GAIN's thirteen, against three copies of `Loudness.swift`
each carrying the code one check was written for: the ceiling quantised to
the NEAREST step rather than downward (11/13 — both sweeps), a non-finite
true peak read as INFINITE headroom rather than none (11/13 — the boost it
must not apply, and the "Silent" it must not print), and a summary that says
nothing about a mix past full scale (12/13). The first and the third were
also built into a whole app, in a copy of the tree so this one was never
touched, and driven over MCP: they fail `phase5_proof.py`'s five-ceiling
sweep and its clipped-summary check and nothing else.

The ten fell either side of the line and none of them crossed it: every
chrome mutation left all twenty-three model checks passing, the clamp
mutation left all forty-five chrome checks passing, and the four model
mutations before it left all forty-two of the chrome checks there were then.

Run it from anywhere; it builds both harnesses if they are stale:

    python3 tools/proof/phase5_chrome.py

The last line is `<n>/<n> checks passed` and the exit status is non-zero if
any failed. The PNGs stay in `tools/proof/work/chrome5/` (with a crop of the
meter out of the 1440 pt pair, both appearances, for an eye check — the
reference crop is the empty bar the meter went into — and section 8's signal
files and answers beside them), and the changed-pixel clusters of every
comparison are printed as bounding boxes so a reader can see where a diff
landed without opening anything.
"""

import json
import math
import os
import re
import struct
import subprocess
import sys
import time
import zlib

from reference_build import build_reference as build_matching_reference

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work")
CHROME = os.path.join(WORK, "chrome5")
BEFORE = os.path.join(CHROME, "before")
SIGNALS = os.path.join(CHROME, "signals")
BUILD = os.path.join(HERE, "harness", "build.sh")
HARNESS_MAIN = os.path.join(HERE, "harness", "main.swift")
STATICLIB = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
BRIDGING = os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")
# The file whose arrival IS the meter. The reference build is the tree one
# commit before it, and the check in section 2 is that the extracted tree
# does not contain it.
METER_VIEW = "app/Sources/LevelMeterView.swift"

# ---------------------------------------------------------------------------
# Geometry, in POINTS, from the app's layout constants. Each number names the
# Swift constant it mirrors; the PNG's width / WIDTH is the backing scale
# (2 on a Retina Mac).

WIDTH = 1440
HEIGHT = 862
# The three other widths, and what each is for. 900 is the minimum window
# `TimelineBar.build`'s own arithmetic is written against — where the row's
# fixed content leaves about 20 pt of slack and the meter must give ITS width
# up rather than take one from a control. 1080 and 1600 are a narrow and a
# wide ordinary window: the meter must sit at its intrinsic width at both,
# never stretching toward its cap, and never moving relative to the right
# edge it is anchored against.
MINIMUM_WIDTH = 900
OTHER_WIDTHS = [1080, 1600]

TOOLBAR = 44             # DS.toolbarHeight
TIMELINE_H = 300         # EditorViewController.defaultTimelineHeight
BAR_H = 36               # DS.timelineBarHeight — the bar over the lanes

# `LevelMeterView`'s own metrics.
METER_W = 120            # LevelMeterView.intrinsicWidth
METER_H = 12             # LevelMeterView.intrinsicHeight
METER_MAX_W = 160        # LevelMeterView.maximumWidth — the cap on the slack
METER_MIN_W = 40         # LevelMeterView.minimumWidth — under it, draw nothing
CHANNEL_GAP = 2          # LevelMeterView.channelGap
CLIP_CELL = 3            # LevelMeterView.clipCell
CLIP_GAP = 2             # LevelMeterView.clipGap
CHANNELS = 2             # `bars` is two, always (LevelMeterReading is 2 ch)

# What the resting view draws, solved the way `LevelMeterView.draw` solves it.
SCALE_W = METER_W - CLIP_CELL - CLIP_GAP                       # 115
ROW_H = int((METER_H - CHANNEL_GAP * (CHANNELS - 1)) / CHANNELS)  # 5
ROW_PITCH = ROW_H + CHANNEL_GAP                                # 7
ROW_TOP = round((METER_H - (ROW_H * CHANNELS + CHANNEL_GAP * (CHANNELS - 1))) / 2)  # 0

# `TimelineBar.build`'s row, from the RIGHT edge in. Everything after the
# meter is fixed width, so the meter's right edge is a constant inset from the
# window's — which is the whole reason the meter went in the flexible gap
# rather than at the end of the row, and what section 5 measures at three
# window widths.
PADDING = 12             # TimelineBar.padding — the edge inset AND row spacing
ACTION_W = 28            # TimelineBar.actionSize.width
DIVIDER_W = 1            # DividerView.intrinsicContentSize.width
SIZE_W = 3 * 26          # OptionSegmentedControl: 3 segments × cellWidth 26
ZOOM_SPACING = 8         # TimelineBar.zoomCluster's stack spacing
ZOOM_SLIDER_W = 110      # …and its slider's width constraint
ZOOM_W = 3 * ACTION_W + ZOOM_SLIDER_W + 3 * ZOOM_SPACING       # 218
# meter │ 12 │ zoom │ 12 │ divider │ 12 │ size │ 12 │ window edge
METER_RIGHT_INSET = (
    PADDING + SIZE_W + PADDING + DIVIDER_W + PADDING + ZOOM_W + PADDING)  # 345

# The bar sits at the top of the timeline container, which is the bottom
# arranged subview of the main split; the row is centred in it.
BAR_TOP = HEIGHT - TIMELINE_H                                  # 562
METER_Y = BAR_TOP + (BAR_H - METER_H) / 2                      # 574


class Rect:
    def __init__(self, name, x, y, w, h):
        self.name, self.x0, self.y0, self.x1, self.y1 = name, x, y, x + w, y + h

    def contains(self, x, y, scale, slop=0):
        return (self.x0 - slop) * scale <= x < (self.x1 + slop) * scale \
            and (self.y0 - slop) * scale <= y < (self.y1 + slop) * scale

    def __str__(self):
        return (f"{self.name} x {self.x0:g}–{self.x1:g} y {self.y0:g}–{self.y1:g} pt "
                f"({self.x1 - self.x0:g} × {self.y1 - self.y0:g})")


def meter_rect(width=WIDTH, height=HEIGHT):
    """Where `LevelMeterView` must be, from the constants alone — never from
    the pixels. Section 4 solves the same rectangle out of a diff and the two
    have to agree."""
    top = (height - TIMELINE_H) + (BAR_H - METER_H) / 2
    return Rect("the meter", width - METER_RIGHT_INSET - METER_W, top, METER_W, METER_H)


def bar_rect(width=WIDTH, height=HEIGHT):
    return Rect("the timeline bar", 0, height - TIMELINE_H, width, BAR_H)


# The sharp chrome pass (2026-09-23, `designs/design_handoff_reelcut_sharp/`)
# changed four controls in this row BY DESIGN against the pre-meter tree: the
# selection block's kind chip and the Snap box lost their radius, the zoom
# slider became a `BlockSlider`, and S/M/L's end cells went square. Their
# columns, full bar height, from the constants above so they hold at every
# width, are masked where each bar-scoped set is MADE (sections 3, 3b, 5, 6)
# and the masked count is printed, not scored. Nothing else may differ.
SNAP_X0 = PADDING + 176 + PADDING + DIVIDER_W + PADDING + 238 + PADDING + DIVIDER_W + PADDING
SNAP_BOX = 13            # OptionCheckboxControl.boxSize


def sharp_columns(width=WIDTH, height=HEIGHT):
    top, slider_x0 = height - TIMELINE_H, meter_rect(width).x1 + PADDING + ACTION_W + ZOOM_SPACING
    return [Rect("the kind chip", PADDING, top, 8, BAR_H),
            Rect("the Snap box", SNAP_X0, top, SNAP_BOX, BAR_H),
            Rect("the zoom slider", slider_x0, top, ZOOM_SLIDER_W, BAR_H),
            Rect("S/M/L", width - PADDING - SIZE_W, top, SIZE_W, BAR_H)]


def sharp(pixels, width, scale):
    """A bar-scoped set without the four sharp-pass columns."""
    kept = outside(pixels, sharp_columns(width), scale)
    print(f"      the sharp pass's four columns: {len(pixels) - len(kept)} px masked, "
          "NOT scored")
    return kept


# ---------------------------------------------------------------------------
# The package, by hand (spec §5.2). One text clip, 0–5 s, on one track.
#
# It has no media in it, which is the point: a media clip loads its thumbnails
# and its waveform through a notification and would make the render a race.
# The meter draws the same thing either way — it reads `LevelMeter.shared`,
# which no document can reach — so the package's only job is to give the bar's
# selection block something to say.

TICKS_PER_SECOND = 600_000


def project_json():
    return {
        "version": 5,
        "canvas": {
            "width": 1920, "height": 1080, "fps": [30, 1],
            "background": [0.0, 0.0, 0.0, 1.0], "fit_new_clips": True,
            "timecode_frames": True,
        },
        "media": [],
        "tracks": [{
            "id": 1, "name": "Track 1", "hidden": False, "muted": False,
            "locked": False, "solo": False,
        }],
        "clips": [{
            "id": 2, "track": 1, "start": 0, "duration": 5 * TICKS_PER_SECOND,
            "source": {"kind": "text"},
            "enabled": {"video": True, "audio": True},
            "speed": 1.0,
            "video": {
                "x": 0.0, "y": 0.0, "scale": 1.0, "rotation": 0.0, "opacity": 1.0,
                "crop": {"l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0},
                "corner_radius": 0.0, "shadow": None,
                "color": {"brightness": 0.0, "contrast": 0.0, "saturation": 0.0, "hue": 0.0},
                "chroma": None, "filters": [], "reflection": None, "spotlight": None,
                "obscure": [],
            },
            "audio": None,
            "text": {
                "content": "Hello", "font": "SourceSans3-SemiBold", "size": 72.0,
                "color": [1.0, 1.0, 1.0, 1.0], "align": "center", "valign": "middle",
                "line_spacing": 1.0, "tracking": 0.0, "outline": None, "backdrop": None,
                "width": None, "animation": None,
            },
            "shape": None,
            "actions": [], "transition_in": None,
            "name": None, "label": None,
        }],
        "markers": [],
        "next_id": 3,
        "nests": [],
    }


def write_package():
    path = os.path.join(CHROME, "bar.reelcut")
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "project.json"), "w") as f:
        json.dump(project_json(), f, indent=2)
        f.write("\n")
    return path


# ---------------------------------------------------------------------------
# The two harnesses.

WARNINGS = []
STDERR = {}


def git(*args):
    result = subprocess.run(
        ["git", "-C", ROOT] + list(args), capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit("git " + " ".join(args) + " failed:\n" + result.stderr)
    return result.stdout


def reference_commit():
    """The tree immediately BEFORE the level meter existed.

    Found from the history rather than named, so this proof keeps working
    after phase 5 is committed and after every phase that follows it: the
    commit that ADDED `LevelMeterView.swift`, minus one. While the phase is
    still uncommitted the file is untracked, `git log` names no commit, and
    HEAD is already that tree — which is the case this was written under and
    the reason both branches are exercised rather than one being theory.
    """
    added = git("log", "--diff-filter=A", "--format=%H", "--", METER_VIEW).split()
    return (added[-1] + "^") if added else "HEAD"


def build_reference(commit):
    """Build archived Swift with its matching archived core and header."""
    return build_matching_reference(root=ROOT, before=BEFORE, commit=commit,
                                    harness_main=HARNESS_MAIN, fonts=FONTS,
                                    proof_script=__file__)


def build_harness():
    """Return the current binary and a diagnostic for the scored build row."""
    start = time.time()
    try:
        result = subprocess.run([BUILD], capture_output=True, text=True)
    except OSError as error:
        return None, str(error)
    if result.returncode != 0:
        return None, (result.stdout + result.stderr).strip()
    lines = result.stdout.strip().splitlines()
    if not lines or not os.path.isfile(lines[-1]):
        return None, "build.sh succeeded without a harness binary"
    binary = lines[-1]
    built = "built" in result.stderr
    print(f"harness: {binary} ({'built in %.0f s' % (time.time() - start) if built else 'up to date'})")
    return binary, None


def render(binary, package, out, width=WIDTH, height=HEIGHT, appearance="dark",
           select=0, playhead=0, constraints=False):
    """One offscreen render. `out` is returned; its stderr is kept in
    `STDERR` under the file's own name, and section 7 is what reads it.

    `playhead` is the harness's seventh argument, in SECONDS. Every render
    here takes it at 0 but one: section 3b moves it, because the playhead is
    the cheapest thing in this program that changes the window OUTSIDE the
    timeline bar and nothing at all inside it.

    `constraints` turns AppKit's layout diagnostics on for this render —
    `OS_ACTIVITY_DT_MODE`, which is what Xcode sets, and without which
    "Conflicting constraints detected" goes to the unified log and never to
    this pipe. It is off by default because it ALSO mirrors every unrelated
    `os_log` line the frameworks emit (~40 KB of `linkd` and `cfprefsd`
    chatter per launch), which would drown the harness's own one-line warning
    and make "nothing else was written to stderr" meaningless. So the ordinary
    renders stay quiet and one extra render is made noisy on purpose.
    """
    args = [
        binary, package, out, appearance, str(width), str(height), str(select),
        str(playhead), "1", "clip", "-", "-",
    ]
    environment = dict(os.environ)
    if constraints:
        environment["OS_ACTIVITY_DT_MODE"] = "enable"
    result = subprocess.run(args, capture_output=True, text=True, env=environment)
    if result.returncode != 0 or not os.path.exists(out):
        sys.stderr.write(result.stdout + result.stderr)
        sys.exit(f"render failed for {os.path.basename(out)}")
    STDERR[os.path.basename(out)] = result.stderr
    # `Harness.png` writes one line when two consecutive captures never came
    # back equal — the layout was still moving when it gave up, so every byte
    # comparison would be measuring a race rather than the feature.
    if not constraints and result.stderr.strip():
        WARNINGS.append((os.path.basename(out), result.stderr.strip()))
    return out


# ---------------------------------------------------------------------------
# PNG, in pure Python: chunks, zlib, the five filters. (`phase4_chrome.py`'s,
# unchanged — these scripts are standalone on purpose.)

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


class Image:
    def __init__(self, path, points=WIDTH):
        self.path = path
        self.width, self.height, self.channels, self.rows = decode_png(path)
        self.scale = self.width / points

    def pixel(self, x, y):
        row = self.rows[y]
        return tuple(row[x * self.channels:(x + 1) * self.channels])

    def point(self, x, y):
        """The pixel at a POINT, at the middle of the point's own square."""
        s = self.scale
        return self.pixel(int(x * s + s / 2), int(y * s + s / 2))

    def crop(self, rect, out):
        s = self.scale
        x0, x1 = max(int(rect.x0 * s), 0), min(int(rect.x1 * s), self.width)
        y0, y1 = max(int(rect.y0 * s), 0), min(int(rect.y1 * s), self.height)
        rows = [row[x0 * self.channels:x1 * self.channels] for row in self.rows[y0:y1]]
        with open(out, "wb") as f:
            f.write(encode_png(x1 - x0, y1 - y0, self.channels, rows))


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


def outside(pixels, rects, scale, slop=0):
    return [p for p in pixels if not any(r.contains(p[0], p[1], scale, slop) for r in rects)]


def inside(pixels, rects, scale, slop=0):
    return [p for p in pixels if any(r.contains(p[0], p[1], scale, slop) for r in rects)]


def extent(pixels, scale):
    """The bounding box of a changed set, in POINTS — the rectangle a diff
    claims, to be compared with the one the constants predict. None when
    nothing changed, which every caller reports as a failure rather than
    letting an empty set agree with anything."""
    if not pixels:
        return None
    xs = [x for x, _ in pixels]
    ys = [y for _, y in pixels]
    return (min(xs) / scale, min(ys) / scale, (max(xs) + 1) / scale, (max(ys) + 1) / scale)


def runs(values):
    """Contiguous runs of a sorted list of integers, as (first, last) pairs."""
    if not values:
        return []
    out, start, previous = [], values[0], values[0]
    for value in values[1:]:
        if value != previous + 1:
            out.append((start, previous))
            start = value
        previous = value
    out.append((start, previous))
    return out


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


def identical(name, a, b, points=WIDTH, detail=""):
    """Two renders that must be byte-identical, reported like phase 4's."""
    if same_file(a, b):
        check(name, True, detail)
        return
    ia, ib = Image(a, points), Image(b, points)
    diff = changed_pixels(ia, ib)
    check(name, not diff,
          ("the PNG bytes differ but every pixel is the same" if not diff else
           f"{len(diff)} pixels differ:\n" + describe(clusters(diff), ia.scale)))


# ---------------------------------------------------------------------------
# Section 8's signals — authored HERE, so the tone the model is asked about is
# this script's and not the instrument's.
#
# 48 kHz and 1000 Hz make a period of exactly 48 samples, and 48 is divisible
# by 4, so sample 12 lands exactly on the crest: the fixture's peak IS its
# amplitude, to the last bit of a float. 4032 frames is exactly 84 whole
# periods, so its RMS is exactly amplitude/√2 as well. Both matter: a ±0.5 dB
# tolerance means nothing if the fixture itself is only accurate to a few
# tenths, and neither number below is a rounding of anything.

RATE = 48000.0
HZ = 1000.0
FRAMES = 4032
ROOT_TWO_DB = 20 * math.log10(math.sqrt(2))          # 3.0103, a sine's peak−RMS


def dbfs(magnitude):
    return 20 * math.log10(magnitude)


def amplitude(db):
    return 10 ** (db / 20)


def sine(db):
    a = amplitude(db)
    return [a * math.sin(2 * math.pi * HZ * i / RATE) for i in range(FRAMES)]


def square(db):
    """|sample| is constant, so RMS == peak — which is what tells a real RMS
    from a peak with a constant subtracted off it."""
    a = amplitude(db)
    return [a if (int(i * HZ * 2 / RATE) % 2 == 0) else -a for i in range(FRAMES)]


def impulse():
    """One sample at full scale. Peak 0 dBFS, RMS 10·log10(FRAMES) under it —
    the widest a buffer's peak and RMS can be apart."""
    return [1.0 if i == FRAMES // 2 else 0.0 for i in range(FRAMES)]


def poison():
    """A NaN and an infinity in an otherwise ordinary buffer. One of either
    poisons a running maximum for ever, so the model answers silence."""
    data = sine(-12)
    data[7] = float("nan")
    data[9] = float("inf")
    return data


def write_signal(name, channels):
    """Planar little-endian float32 — the shape `AudioTap` hands the sink."""
    os.makedirs(SIGNALS, exist_ok=True)
    path = os.path.join(SIGNALS, name + ".f32")
    with open(path, "wb") as f:
        for data in channels:
            f.write(struct.pack("<%df" % len(data), *data))
    return path


def measure(binary, name, tracks, at=0, then_stop=None):
    """One run of `harness meter`. `tracks` is a list of
    (signal path, channel count, ramps-or-None), each optionally with a fourth
    element: four magnitudes written straight into the sink INSTEAD of a file
    being measured into it, which is the only way to hand the model a reading
    no buffer can produce (see the torn-read check below)."""
    rows = []
    for index, spec in enumerate(tracks):
        path, count, ramps = spec[:3]
        stored = spec[3] if len(spec) > 3 else None
        row = {"id": index + 1, "ramps": ramps}
        if stored is None:
            row.update({"samples": path, "channels": count, "frames": FRAMES})
        else:
            row["store"] = stored
        rows.append(row)
    request = {"at": at, "tracks": rows}
    if then_stop:
        request["then_stop"] = then_stop
    source = os.path.join(SIGNALS, f"request-{name}.json")
    out = os.path.join(SIGNALS, f"reading-{name}.json")
    with open(source, "w") as f:
        json.dump(request, f, indent=2)
    result = subprocess.run([binary, "meter", source, out], capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        sys.stderr.write(result.stdout + result.stderr)
        sys.exit(f"the meter model failed for {name}")
    with open(out) as f:
        return json.load(f)


def ramp(start, duration, begin, end):
    return {"start": start, "duration": duration, "from": begin, "to": end}


def close(value, want, tolerance):
    return value is not None and abs(value - want) <= tolerance


# ---------------------------------------------------------------------------

def geometry_checks(diff, scale, rect, what):
    """Solve `LevelMeterView.draw`'s resting geometry out of a diff.

    Everything the view draws at rest is the trough: two channel rows, each a
    scale and a clip cell with a gap between them. Nothing else is drawn at
    all, because `width(forDB:)` returns 0 at the floor — so the changed
    pixels ARE the resting appearance, and its metrics can be read straight
    off them and compared with the constants. It is done from a diff rather
    than by hunting for ink because the diff is already known to be the
    meter's and nothing else's (section 3).
    """
    xs = sorted({x for x, _ in diff})
    ys = sorted({y for _, y in diff})
    rows = [(a / scale, (b + 1) / scale) for a, b in runs(ys)]
    columns = [(a / scale, (b + 1) / scale) for a, b in runs(xs)]
    print(f"      {what}: rows {[(f'{a:g}', f'{b:g}') for a, b in rows]}")
    print(f"      {what}: columns {[(f'{a:g}', f'{b:g}') for a, b in columns]}")

    check(f"{what}: the ink is exactly {CHANNELS} channel rows "
          f"(LevelMeterReading is two channels, always)",
          len(rows) == CHANNELS, f"{len(rows)} row band(s): {rows}")
    check(f"{what}: each row is {ROW_H} pt tall — "
          f"floor(({METER_H} − {CHANNEL_GAP}) / {CHANNELS}) of intrinsicHeight",
          rows and all(abs((b - a) - ROW_H) < 0.01 for a, b in rows),
          f"heights {[round(b - a, 2) for a, b in rows]}")
    check(f"{what}: they are {ROW_PITCH} pt apart — one row plus "
          f"channelGap {CHANNEL_GAP}",
          len(rows) == CHANNELS and abs((rows[1][0] - rows[0][0]) - ROW_PITCH) < 0.01,
          f"pitch {rows[1][0] - rows[0][0] if len(rows) > 1 else '—'}")
    check(f"{what}: the first row starts {ROW_TOP} pt below the view's own top, "
          "so the pair is centred in intrinsicHeight",
          rows and abs(rows[0][0] - (rect.y0 + ROW_TOP)) < 0.01,
          f"first row at y {rows[0][0] if rows else '—'} pt, "
          f"the meter's top is {rect.y0:g} pt")

    check(f"{what}: the ink is a scale and a SEPARATE clip cell — two column "
          "bands, not one pill", len(columns) == 2,
          f"{len(columns)} column band(s): {columns}")
    if len(columns) == 2:
        scale_w = columns[0][1] - columns[0][0]
        gap = columns[1][0] - columns[0][1]
        cell = columns[1][1] - columns[1][0]
        check(f"{what}: the scale is {SCALE_W} pt — intrinsicWidth {METER_W} less "
              f"clipCell {CLIP_CELL} and clipGap {CLIP_GAP}",
              abs(scale_w - SCALE_W) < 0.01, f"{scale_w:g} pt")
        check(f"{what}: the gap before the cell is clipGap {CLIP_GAP} pt",
              abs(gap - CLIP_GAP) < 0.01, f"{gap:g} pt")
        check(f"{what}: the cell is clipCell {CLIP_CELL} pt and sits at the view's "
              "right edge", abs(cell - CLIP_CELL) < 0.01
              and abs(columns[1][1] - rect.x1) < 0.01,
              f"{cell:g} pt, right edge at {columns[1][1]:g} pt vs {rect.x1:g} pt")
    else:
        for name in ("the scale is intrinsicWidth less the cell and the gap",
                     "the gap before the cell is clipGap",
                     "the cell is clipCell and sits at the view's right edge"):
            check(f"{what}: {name}", False, "there are not two column bands to measure")


def ink_checks(image, diff, rect, what):
    """What the resting meter is painted IN — one ink, and a grey one.

    `DS.meterTrough` is `.quaternaryLabelColor`, which is grey in both
    appearances; `DS.meterFill` is `clipAudio` (#2C7A58) and `DS.meterClip` is
    `coral` (#F4653F), and neither is anywhere near it. So "every changed
    pixel is achromatic" is the statement that at rest there is no fill bar,
    no peak wash and no lit clip cell — the resting appearance the harness
    depends on (`LevelMeterView`'s "one resting appearance, always drawn", and
    the reason no timer ever starts offscreen).
    """
    colours = {}
    for x, y in diff:
        colours[image.pixel(x, y)] = colours.get(image.pixel(x, y), 0) + 1
    ranked = sorted(colours.items(), key=lambda kv: -kv[1])
    print(f"      {what}: {len(ranked)} colour(s); "
          + ", ".join(f"{c[:3]}×{n}" for c, n in ranked[:4]))
    if not ranked:
        # Nothing was drawn, so there is no ink to have an opinion about — and
        # every check below would pass VACUOUSLY over an empty set (`all` of
        # nothing is true, "no chromatic pixel" is trivially so). `extent`'s
        # rule in `phase4_chrome.py`: report the empty case as a FAIL and keep
        # the score the same length rather than shortening it into a pass.
        for name in ("every pixel of the resting meter is GREY",
                     "one ink covers the meter",
                     "it is not the bar's own background",
                     "the clip cell is drawn at rest, in the trough's ink"):
            check(f"{what}: {name}", False, "the meter drew nothing at all")
        return
    chromatic = [(c, n) for c, n in ranked if len(set(c[:3])) != 1]
    check(f"{what}: every pixel of the resting meter is GREY — no meterFill "
          "(#2C7A58) and no meterClip (#F4653F) anywhere in it", not chromatic,
          f"{sum(n for _, n in chromatic)} px in {len(chromatic)} colour(s): "
          f"{[c for c, _ in chromatic[:3]]}")
    ink, count = ranked[0]
    check(f"{what}: one ink covers the meter — DS.meterTrough, over "
          f"{count * 100 // len(diff)} % of it", count >= 0.9 * len(diff),
          f"{ink[:3]} over {count} of {len(diff)} px")
    background = image.point(rect.x0 - 6, rect.y0 + METER_H / 2)
    check(f"{what}: and it is not the bar's own background, which is what makes "
          "it visible at all", ink[:3] != background[:3],
          f"trough {ink[:3]} vs bar {background[:3]}")
    # The cell is drawn in the trough ink at rest and in coral only on an over,
    # so at rest the two must be the same colour — a cell that were merely
    # absent would leave the bar background showing through instead.
    cell = image.point(rect.x1 - CLIP_CELL / 2, rect.y0 + ROW_TOP + ROW_H / 2)
    check(f"{what}: the clip cell is DRAWN at rest, in the same ink as the "
          "trough — it is lit on an over, not conjured by one",
          cell[:3] == ink[:3], f"cell {cell[:3]} vs trough {ink[:3]}")


def reading_checks(binary):
    """Section 8 — what the meter READS, over the harness's meter mode."""
    print("\n8. the meter's reading — the model, over buffers this script wrote")
    print(f"      {FRAMES} frames at {RATE:g} Hz: {FRAMES * HZ / RATE:g} whole periods of "
          f"a {HZ:g} Hz sine, so the fixture's peak and RMS are both exact")

    tone20 = write_signal("tone-20", [sine(-20), sine(-20)])
    out = measure(binary, "tone-20", [(tone20, 2, None)])
    published = out["published"]
    print(f"      published: peak L {published['peak_left_db']:.4f} dBFS, "
          f"R {published['peak_right_db']:.4f}, RMS L {published['rms_left_db']:.4f} dBFS")
    # THE claim the contract states, in its own words and its own tolerance.
    for side in ("left", "right"):
        check(f"a −20 dBFS tone reads −20 dBFS on the {side} bar, within ±0.5 dB — "
              "measured through LevelMeterSink and read back off LevelMeter.shared "
              "after the publish, not off a local total",
              close(published[f"peak_{side}_db"], -20, 0.5),
              f"{published[f'peak_{side}_db']:.4f} dBFS "
              f"(error {published[f'peak_{side}_db'] + 20:+.4f} dB)")
    check("its RMS is exactly a sine's √2 under its peak (3.0103 dB, ±0.05) — so the "
          "second number is a real RMS and not the peak wearing a discount",
          close(published["peak_left_db"] - published["rms_left_db"], ROOT_TWO_DB, 0.05),
          f"{published['peak_left_db'] - published['rms_left_db']:.4f} dB")
    # The clamp, exercised where a MEASURED buffer cannot reach it. `rms ≤ peak`
    # is arithmetic over any real buffer, so asserting it of a tone is a check
    # that stays green with `LevelMeterReading.init`'s
    # `min(sanitised(rmsLeft), peakLeft)` deleted — which is the only line it
    # would be claiming to test. The skew the clamp exists for comes from the
    # crossing instead: peak and RMS are two relaxed words, stored and loaded
    # separately, so a reader can catch this buffer's RMS beside the previous,
    # quieter buffer's peak. `store` hands the model exactly that pair.
    torn = measure(binary, "torn-read", [(None, 2, None, {
        "peak_left": 0.1, "peak_right": 0.1, "rms_left": 0.5, "rms_right": 0.5})])
    pulled = torn["published"]
    check("a TORN read — this buffer's RMS beside the previous, quieter buffer's peak, "
          "0.5 against 0.1 — comes back with the RMS pulled down to the peak, the "
          "invariant LevelMeterReading.init restores across the two atomic words",
          close(pulled["rms_left"], pulled["peak_left"], 1e-6)
          and close(pulled["rms_right"], pulled["peak_right"], 1e-6)
          and close(pulled["peak_left"], 0.1, 1e-6),
          f"stored peak 0.1 / RMS 0.5 → raw peak {torn['tracks'][0]['raw']['peak_left']:.4f} "
          f"/ RMS {torn['tracks'][0]['raw']['rms_left']:.4f}, published peak "
          f"{pulled['peak_left']:.4f} / RMS {pulled['rms_left']:.4f}")

    # The whole scale, not one point on it. A build with a wrong dB constant
    # is right at 0 dBFS and wrong everywhere else, which is why the sweep
    # matters more than the single number above.
    levels = [0, -6, -20, -40, -60]
    errors = []
    for db in levels:
        path = write_signal(f"tone{db}", [sine(db), sine(db)])
        got = measure(binary, f"tone{db}", [(path, 2, None)])["published"]["peak_db"]
        errors.append((db, got, got - db))
    print("      the sweep, dBFS in → dBFS out: "
          + "  ".join(f"{db:>3} → {got:+.4f}" for db, got, _ in errors))
    worst = max(errors, key=lambda row: abs(row[2]))
    check(f"the whole scale reads true, {levels[0]} to {levels[-1]} dBFS, within ±0.5 dB — "
          "a build whose dB constant were 10·log10 rather than 20·log10 is exact at "
          "0 dBFS and wrong at every other level",
          all(abs(error) <= 0.5 for _, _, error in errors),
          f"worst {worst[0]} dBFS → {worst[1]:.4f} ({worst[2]:+.4f} dB)")

    lr = write_signal("tone-lr", [sine(-6), sine(-30)])
    out = measure(binary, "tone-lr", [(lr, 2, None)])["published"]
    check("two channels at different levels stay apart — −6 dBFS left, −30 right, "
          "neither summed into the other nor copied across",
          close(out["peak_left_db"], -6, 0.5) and close(out["peak_right_db"], -30, 0.5),
          f"L {out['peak_left_db']:.4f}, R {out['peak_right_db']:.4f} dBFS")

    mono = write_signal("mono-20", [sine(-20)])
    out = measure(binary, "mono-20", [(mono, 1, None)])["published"]
    check("a ONE-channel track lights both bars alike — a mono composition track is "
          "widened downstream of the tap, so its one channel is what both are showing",
          out["peak_left"] == out["peak_right"] and close(out["peak_left_db"], -20, 0.5),
          f"L {out['peak_left_db']:.4f}, R {out['peak_right_db']:.4f} dBFS")

    sq = write_signal("square-20", [square(-20), square(-20)])
    out = measure(binary, "square-20", [(sq, 2, None)])["published"]
    check("a SQUARE wave's RMS equals its peak (±0.05 dB), where the sine's was 3 dB "
          "under — the two numbers are measured, not derived from each other",
          close(out["rms_left_db"] - out["peak_left_db"], 0, 0.05),
          f"peak {out['peak_left_db']:.4f}, RMS {out['rms_left_db']:.4f} dBFS")

    spike = write_signal("impulse", [impulse(), impulse()])
    out = measure(binary, "impulse", [(spike, 2, None)])["published"]
    want = -10 * math.log10(FRAMES)
    check(f"one full-scale SAMPLE in {FRAMES} reads 0 dBFS peak and {want:.2f} dBFS RMS "
          "— peak is a maximum and RMS is an average, and a meter that averaged both "
          "would miss the transient a peak meter exists for",
          close(out["peak_db"], 0, 0.01) and close(out["rms_left_db"], want, 0.05),
          f"peak {out['peak_db']:.4f}, RMS {out['rms_left_db']:.4f} dBFS")

    quiet = write_signal("silence", [[0.0] * FRAMES, [0.0] * FRAMES])
    out = measure(binary, "silence", [(quiet, 2, None)])
    check("digital silence reads as the FLOOR and not as −∞ — a −∞ reaching a layout "
          "constraint lays out as NaN, which AppKit reports as a broken constraint "
          "rather than as a quiet meter",
          out["published"]["is_silent"]
          and out["published"]["peak_db"] == out["floor_db"],
          f"peak {out['published']['peak_db']} dBFS, floor {out['floor_db']}")

    bad = write_signal("poison", [poison(), poison()])
    out = measure(binary, "poison", [(bad, 2, None)])["published"]
    check("a NaN and an infinity in the buffer read as silence — one of either poisons "
          "a running maximum for ever, and the bar would vanish and stay vanished",
          out["is_silent"], f"peak {out['peak_db']} dBFS, silent {out['is_silent']}")

    # ── the envelope: D-0, the decision the whole meter rests on ────────────
    print("      the envelope — a PreEffects tap times the plan's ramps (contract D-0)")
    fade = [ramp(0, 600_000, 0.0, 1.0)]
    out = measure(binary, "fade-mid", [(tone20, 2, fade)], at=300_000)
    track = out["tracks"][0]
    check("halfway up a one-second fade the envelope is 0.5 and the meter reads 6.02 dB "
          "under the tap — the tap is PreEffects and sees the samples BEFORE the "
          "volume, so the multiply is what makes the number post-fader",
          close(track["gain"], 0.5, 1e-6)
          and close(out["published"]["peak_db"], -20 - 20 * math.log10(2), 0.05),
          f"gain {track['gain']:.6f}, raw {track['raw']['peak_db']:.4f} → "
          f"published {out['published']['peak_db']:.4f} dBFS")
    check("…and the RAW reading is still −20 dBFS, so it is the fold that scaled it and "
          "not the measurement", close(track["raw"]["peak_db"], -20, 0.5),
          f"raw {track['raw']['peak_db']:.4f} dBFS")

    # The same ramp downhill. A build that answered a ramp's `from` instead of
    # interpolating reads 6 dB too LOW going up and 6 dB too HIGH coming down,
    # so the pair pins the direction as well as the arithmetic.
    out = measure(binary, "fadeout-mid", [(tone20, 2, [ramp(0, 600_000, 1.0, 0.0)])],
                  at=300_000)
    check("and halfway DOWN a fade-out it is 0.5 too — the envelope is interpolated "
          "between a ramp's ends, in the direction the ramp runs",
          close(out["tracks"][0]["gain"], 0.5, 1e-6)
          and close(out["published"]["peak_db"], -20 - 20 * math.log10(2), 0.05),
          f"gain {out['tracks'][0]['gain']:.6f}, "
          f"published {out['published']['peak_db']:.4f} dBFS")

    # Three legs, read inside the LAST one: the search has to find the ramp
    # covering the tick, not the first ramp or the nearest edge.
    legs = [ramp(0, 600_000, 0.0, 1.0),
            ramp(600_000, 0, 1.0, 1.0),
            ramp(1_200_000, 600_000, 1.0, 0.25)]
    out = measure(binary, "three-legs", [(tone20, 2, legs)], at=1_500_000)
    check("with three legs, the one covering the playhead is the one used — halfway "
          "through a 1 → 0.25 leg the envelope is 0.625, which neither of the other "
          "two could produce",
          close(out["tracks"][0]["gain"], 0.625, 1e-6)
          and close(out["published"]["peak_db"], -20 + dbfs(0.625), 0.05),
          f"gain {out['tracks'][0]['gain']:.6f}, "
          f"published {out['published']['peak_db']:.4f} dBFS")

    out = measure(binary, "fade-none", [(tone20, 2, None)])
    check("a track the plan gave NO ramps is unity — audio.rs's meaning of an "
          "unmodified track, and the one case where a missing envelope must not read "
          "as silence", out["tracks"][0]["gain"] == 1,
          f"gain {out['tracks'][0]['gain']}")

    muted = [ramp(0, 10 * TICKS_PER_SECOND, 0.0, 0.0)]
    out = measure(binary, "muted", [(tone20, 2, muted)], at=TICKS_PER_SECOND)
    check("a MUTED or unsoloed track reads silent however loud its samples are — "
          "audio.rs expresses both as a zero envelope, so the meter gets them for free "
          "and cannot disagree with the mix",
          out["published"]["is_silent"] and out["tracks"][0]["gain"] == 0,
          f"gain {out['tracks'][0]['gain']}, raw {out['tracks'][0]['raw']['peak_db']:.2f} "
          f"→ published {out['published']['peak_db']} dBFS")

    out = measure(binary, "past-end", [(tone20, 2, fade)], at=5 * TICKS_PER_SECOND)
    check("past the last ramp the envelope HOLDS its end value rather than falling off "
          "— the fade ended at unity, so the meter reads the tap",
          close(out["tracks"][0]["gain"], 1, 1e-6)
          and close(out["published"]["peak_db"], -20, 0.5),
          f"gain {out['tracks'][0]['gain']:.6f} at 5 s, "
          f"published {out['published']['peak_db']:.4f} dBFS")

    # ── the fold across tracks ──────────────────────────────────────────────
    out = measure(binary, "two-tracks", [(tone20, 2, None), (tone20, 2, None)])["published"]
    check("two tracks at −20 dBFS sum to −13.98 — peaks add LINEARLY, which is the "
          "arithmetic upper bound on what the mix can reach and the honest thing for a "
          "meter whose job is to warn",
          close(out["peak_db"], -20 + 20 * math.log10(2), 0.05),
          f"{out['peak_db']:.4f} dBFS")
    check("…while their RMS adds in POWER, +3.01 dB and not +6 — two uncorrelated "
          "sources do not sum to twice the level",
          close(out["rms_left_db"], -20 - ROOT_TWO_DB + 10 * math.log10(2), 0.05),
          f"{out['rms_left_db']:.4f} dBFS")
    out = measure(binary, "one-and-silence", [(tone20, 2, None), (quiet, 2, None)])
    check("a silent track adds nothing — the sum is the lone track's own reading",
          out["published"]["peak_db"] == out["tracks"][0]["scaled"]["peak_db"],
          f"published {out['published']['peak_db']:.4f} vs track 1 "
          f"{out['tracks'][0]['scaled']['peak_db']:.4f} dBFS")

    # ── the publish rule ────────────────────────────────────────────────────
    out = measure(binary, "stop-other", [(tone20, 2, None)], then_stop="other")
    check("another transport's STOP cannot blank a live meter — with two documents open "
          "they share one output device, and window B's stop must not put out window "
          "A's levels", not out["published_after_stop"]["is_silent"],
          f"after another transport's silence: "
          f"{out['published_after_stop']['peak_db']:.4f} dBFS")
    out = measure(binary, "stop-same", [(tone20, 2, None)], then_stop="same")
    check("…and its OWN stop does blank it, which is the final zero Playback publishes "
          "when the rate drops and again from deinit",
          out["published_after_stop"]["is_silent"],
          f"after its own silence: {out['published_after_stop']['peak_db']} dBFS")


def report():
    passed = sum(RESULTS)
    print(f"\n{passed}/{len(RESULTS)} checks passed")
    sys.exit(0 if passed == len(RESULTS) else 1)


# ---------------------------------------------------------------------------
# Section 9 — the export GAIN's arithmetic, over a probe compiled out of
# `app/Sources/Loudness.swift` alone.
#
# It belongs beside section 8 and for the same reason one step further on:
# the numbers `ExportLoudness.resolve` answers are decided in one pure
# function over three doubles, and the only way `phase5_proof.py` can reach
# it is by exporting a whole file and reading the report back — which
# measures ONE measured true peak, whichever the decode happened to give.
# The defect this section was written for lives in the 0.01 dB grid the gain
# is quantised to, so it shows on some measured peaks and not on others: a
# check that exports one fixture is a coin toss, and a sweep over 200 peaks
# is not. `Loudness.swift` has no AVFoundation, no AppKit and no project in
# it (its own header says why), so unlike the meter it needs neither the
# harness nor a stand-in — it compiles with a `main.swift` this script
# writes and nothing else, in under a second.

LOUDNESS = os.path.join(CHROME, "loudness")
LOUDNESS_SOURCE = os.path.join(ROOT, "app", "Sources", "Loudness.swift")

# The probe. A case in, a resolved report out, JSON both ways — with the
# non-finite levels spelled "inf" / "-inf", because JSON has no infinity and
# a non-finite true peak is one of the cases under test.
PROBE = """import Foundation

// Written by tools/proof/phase5_chrome.py. `ExportLoudness.resolve` over the
// cases in argument 1, its answers into argument 2.

func level(_ value: Any?) -> Double {
    if let number = value as? Double { return number }
    if let text = value as? String {
        return text.hasPrefix("-") ? -Double.infinity : Double.infinity
    }
    return 0
}

func json(_ value: Double) -> Any {
    value.isFinite ? value : (value < 0 ? "-inf" : "inf")
}

let arguments = CommandLine.arguments
guard arguments.count == 3,
    let data = FileManager.default.contents(atPath: arguments[1]),
    let cases = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
else { exit(2) }

var answers: [[String: Any]] = []
for one in cases {
    let report = LoudnessReport(
        integratedLUFS: one["integrated"] as? Double,
        truePeakDBTP: level(one["true_peak"]),
        samplePeakDBFS: level(one["sample_peak"]))
    let resolved = ExportLoudness.resolve(
        measured: report, target: one["target"] as? Double,
        ceiling: one["ceiling"] as? Double)
    answers.append([
        "gain_db": resolved.gainDB,
        "true_peak_dbtp": json(resolved.truePeakDBTP),
        "capped_by_peak": resolved.cappedByPeak,
        "mix_clipped": resolved.mixClipped,
        "summary": resolved.summary,
        "step_db": ExportLoudness.gainStepDB,
    ])
}
try JSONSerialization.data(withJSONObject: answers)
    .write(to: URL(fileURLWithPath: arguments[2]))
"""

STEP = 0.01              # ExportLoudness.gainStepDB


def build_probe():
    """`app/Sources/Loudness.swift` and the probe above, compiled together.

    The same swiftc line the two harnesses use, less the staticlib and the
    bridging header: this file links nothing of the core's. Rebuilt every run
    — it costs under a second, and a stale probe is a probe that can lie."""
    os.makedirs(LOUDNESS, exist_ok=True)
    main = os.path.join(LOUDNESS, "main.swift")
    with open(main, "w") as f:
        f.write(PROBE)
    binary = os.path.join(LOUDNESS, "probe")
    sdk = subprocess.run(
        ["xcrun", "--show-sdk-path", "--sdk", "macosx"],
        capture_output=True, text=True, check=True).stdout.strip()
    result = subprocess.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0",
         LOUDNESS_SOURCE, main, "-o", binary],
        capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(binary):
        sys.stderr.write(result.stdout + result.stderr)
        sys.exit("the loudness probe did not build")
    return binary


def resolve(binary, cases, name):
    """`ExportLoudness.resolve` over a list of cases, as a list of answers."""
    source = os.path.join(LOUDNESS, f"cases-{name}.json")
    out = os.path.join(LOUDNESS, f"answers-{name}.json")
    with open(source, "w") as f:
        json.dump(cases, f, indent=2)
    result = subprocess.run([binary, source, out], capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        sys.stderr.write(result.stdout + result.stderr)
        sys.exit(f"the loudness probe failed for {name}")
    with open(out) as f:
        return json.load(f)


def case(integrated, true_peak, target, ceiling=None, sample_peak=None):
    """One measured programme and what was asked of it. The sample peak
    defaults to the true peak, which is the relationship every real
    measurement has (`LoudnessMeter.finish` takes the max of the two)."""
    one = {
        "integrated": integrated,
        "true_peak": true_peak,
        "sample_peak": true_peak if sample_peak is None else sample_peak,
        "target": target,
    }
    if ceiling is not None:
        one["ceiling"] = ceiling
    return one


def gain_checks():
    """Section 9 — the gain, swept."""
    print("\n9. the export gain — `ExportLoudness.resolve`, over a probe of its own")
    binary = build_probe()

    # (a) The ceiling, swept across the 0.01 dB grid. A ceiling-limited gain
    # is a CONSTRAINT and not a target: quantising it to the NEAREST step
    # hands back up to half a step of the attenuation the ceiling asked for,
    # and the export then reports — and writes — a true peak ABOVE the
    # ceiling it names. 200 measured peaks 0.001 dB apart cover every phase
    # of that grid twenty times over, so this cannot pass by luck the way one
    # exported fixture can.
    for ceiling, named in ((-1.0, "−1 dBTP"), (None, "the default 0 dBTP")):
        peaks = [-0.3 - 0.001 * i for i in range(200)]
        answers = resolve(
            binary, [case(-20.0, p, -14.0, ceiling) for p in peaks],
            f"sweep{'' if ceiling is None else int(-ceiling * 10)}")
        limit = 0.0 if ceiling is None else ceiling
        over = [
            (p, a["true_peak_dbtp"]) for p, a in zip(peaks, answers)
            if a["true_peak_dbtp"] > limit + 1e-9
        ]
        # What a round-to-nearest quantisation would have done to the same
        # sweep, computed here rather than assumed: it is the size of the
        # hole this check covers.
        would = sum(
            1 for p in peaks
            if round((limit - p) / STEP) * STEP > (limit - p) + 1e-12)
        check(f"no gain capped at {named} lands OVER it — 200 measured true peaks "
              f"0.001 dB apart, and the shifted peak is at or under the ceiling for "
              f"every one of them",
              not over,
              f"{len(over)} of 200 over ({', '.join('%.4f→%.4f' % o for o in over[:3])}"
              f"{', …' if len(over) > 3 else ''})" if over else
              f"a round-to-NEAREST quantisation would put {would} of 200 over it")
        short = [
            (p, a["true_peak_dbtp"]) for p, a in zip(peaks, answers)
            if a["true_peak_dbtp"] < limit - STEP - 1e-9
        ]
        check(f"…and none of them gives away more than the {STEP} dB grid to get there, "
              f"so the cap is rounded DOWN and not simply lowered",
              not short,
              f"{len(short)} of 200 more than one step under" if short else
              f"the worst sits {min(limit - a['true_peak_dbtp'] for a in answers):.4f} dB "
              f"under the ceiling")
        check(f"…and every one of them says so: capped_by_peak, since −14 LUFS over a "
              f"−20 LUFS programme wants +6 dB and the ceiling has under a decibel",
              all(a["capped_by_peak"] for a in answers))

    # (b) The other half of the same decision: a TARGET-limited gain still
    # rounds to nearest. Flooring both would be a second bug wearing the
    # first one's clothes — a quiet export, every time, by up to a hundredth
    # of a decibel.
    answers = resolve(
        binary,
        [case(-20.004, -30.0, -14.0, -1.0), case(-20.006, -30.0, -14.0, -1.0)],
        "target")
    check("a gain the TARGET decided still rounds to nearest — +5.996 dB asks for 6.00 "
          "and +6.006 dB asks for 6.01, which is what says the rounding above was "
          "chosen and not applied everywhere",
          [round(a["gain_db"], 6) for a in answers] == [6.0, 6.01]
          and not any(a["capped_by_peak"] for a in answers),
          f"{[round(a['gain_db'], 6) for a in answers]}")

    # (c) A non-finite true peak. It reaches `resolve` from float source
    # media carrying an infinity — −∞ cannot, because a programme with no
    # integrated loudness has already returned — and "the peak cannot be
    # measured" has to mean NO headroom. Infinite headroom is the inversion:
    # the whole requested boost, ceiling ignored.
    answers = resolve(
        binary,
        [case(-40.0, "inf", -14.0, -1.0), case(-6.0, "inf", -23.0, -1.0),
         case(None, "-inf", -14.0, -1.0)],
        "nonfinite")
    check("a non-finite true peak is NO headroom, not infinite headroom — a −40 LUFS "
          "programme carrying an infinity is not boosted 26 dB toward −14",
          answers[0]["gain_db"] == 0 and answers[0]["capped_by_peak"],
          f"gain {answers[0]['gain_db']} dB, capped {answers[0]['capped_by_peak']}")
    check("…while an ATTENUATION it asks for still happens — no headroom bounds the "
          "gain above, never below",
          round(answers[1]["gain_db"], 6) == -17.0,
          f"gain {answers[1]['gain_db']} dB")
    check("…and it does not read as SILENCE, which is what a bare isFinite guard makes "
          "of it — the one programme that is anything but",
          "Silent" not in answers[0]["summary"],
          f"summary “{answers[0]['summary']}”")
    check("while digital silence — no integrated loudness, a −∞ peak — still does",
          answers[2]["summary"] == "Silent" and answers[2]["gain_db"] == 0,
          f"summary “{answers[2]['summary']}”")

    # (d) The mix the writer would clip. Since #86 a NORMALISED export reads
    # the same float mix the measurement read and quantises once after the
    # gain, so a hot mix with a gain is not clipped and is not reported so.
    # Only a hot mix written with NO gain goes through the 16-bit decode,
    # which saturates; that one must say so. `phase5_proof.py` measures both
    # end to end on written files.
    answers = resolve(
        binary,
        [case(2.4, 6.02, -14.0, -1.0), case(-6.7, -0.02, -14.0, -1.0),
         case(2.4, 6.02, None)],
        "clipped")
    check("a mix measured PAST full scale and normalised is NOT reported as clipped — "
          "the gain is applied to the float mix before it is quantised",
          not answers[0]["mix_clipped"] and "clipped" not in answers[0]["summary"],
          f"summary “{answers[0]['summary']}”")
    check("…and one that merely came close is not, so the sentence means something",
          not answers[1]["mix_clipped"] and "clipped" not in answers[1]["summary"],
          f"summary “{answers[1]['summary']}”")
    check("…while the same hot mix written with NO gain is reported as clipped — the "
          "16-bit decode saturates, so these figures are the mix's and the file's are "
          "worse",
          answers[2]["mix_clipped"] and "clipped" in answers[2]["summary"],
          f"summary “{answers[2]['summary']}”")


def main():
    os.makedirs(CHROME, exist_ok=True)
    binary, build_note = build_harness()
    if binary is None:
        check("the current harness builds, so meter renders and readings can run", False,
              build_note or "unknown build failure")
        gain_checks()
        report()
    reference, sha, note = build_reference(reference_commit())
    package = write_package()
    print(f"package: {os.path.relpath(package, ROOT)}")
    rect = meter_rect()
    bar = bar_rect()
    print(f"   {rect}")
    print(f"   {bar}")
    print(f"   its right edge is {METER_RIGHT_INSET} pt in from the window's: "
          f"{PADDING} + S/M/L {SIZE_W} + {PADDING} + divider {DIVIDER_W} + {PADDING}"
          f" + zoom {ZOOM_W} + {PADDING}")

    def png(tag):
        return os.path.join(CHROME, tag + ".png")

    if reference is None:
        print("\n2. the reference build — the tree one commit before the meter existed")
        check("the reference tree built, so there is a 'before' to compare the chrome against",
              False, "      " + note.replace("\n", "\n      "))
        print("   sections 3–7 are cross-build comparisons and cannot run without it.")
        reading_checks(binary)
        gain_checks()
        report()

    start = time.time()
    renders = {}
    # The current build, twice at 1440 dark (determinism), once light, and
    # once at each of the other three widths.
    # Every render, as (tag, width, appearance, which binary). "now-a" and
    # "now-b" are the determinism pair; every "was-" is the reference build at
    # a setting its "now-" twin was rendered at, so each comparison below is
    # one package, one size, one appearance, two builds.
    plan = [("now-a", WIDTH, "dark", binary), ("now-b", WIDTH, "dark", binary),
            ("now-light", WIDTH, "light", binary),
            ("was-a", WIDTH, "dark", reference), ("was-light", WIDTH, "light", reference)]
    for width in [MINIMUM_WIDTH] + OTHER_WIDTHS:
        plan.append((f"now-{width}", width, "dark", binary))
        plan.append((f"was-{width}", width, "dark", reference))
    for tag, width, appearance, which in plan:
        renders[tag] = render(which, package, png(tag), width=width, appearance=appearance)
    # One more at the minimum window with AppKit's constraint diagnostics on
    # (see `render`). It is a twelfth render and not a flag on the eleventh
    # because the diagnostics come with 40 KB of unrelated framework chatter,
    # and section 7 wants both answers: a quiet stream it can hold to
    # "nothing but the harness may write here", and a noisy one it can search.
    renders["now-loud"] = render(
        binary, package, png("now-loud"), width=MINIMUM_WIDTH, constraints=True)
    print(f"rendered {len(renders)} PNGs in {time.time() - start:.1f} s")

    # The four full-width renders are decoded once here; the other widths are
    # decoded in section 5, where the width they are measured against is the
    # window's own rather than WIDTH.
    images = {tag: Image(renders[tag], WIDTH) for tag in
              ("now-a", "now-b", "now-light", "was-a", "was-light")}
    scale = images["now-a"].scale
    print(f"   {images['now-a'].width}x{images['now-a'].height} "
          f"{images['now-a'].channels}-channel, scale {scale:g}")

    # 1. Determinism. Everything below is a comparison of two renders, so this
    # is asserted FIRST and the rest of the score means nothing without it.
    # Two PROCESSES, not two captures inside one: the failure this guards
    # against (an ambiguous constraint the solver breaks differently per run)
    # is invisible within a process.
    print("\n1. determinism — one package rendered twice, in two processes")
    identical("the chrome, twice → byte-identical PNGs", renders["now-a"], renders["now-b"])

    # 2. What the reference build IS. A comparison against "the build before
    # the meter" is only worth something if that is what it is.
    print("\n2. the reference build — the tree one commit before the meter existed")
    tree = os.path.join(BEFORE, "tree", "app", "Sources")
    present = os.path.exists(os.path.join(tree, os.path.basename(METER_VIEW)))
    print(f"      {sha[:12]}, {len(os.listdir(tree))} sources in "
          f"{os.path.relpath(tree, ROOT)}")
    print(f"      compiled with {note}")
    check("the reference tree built, so there is a 'before' to compare the chrome "
          "against — see build_reference for the two instruments it tries", True)
    check("it does not contain LevelMeterView.swift at all — so every pixel section 3 "
          "attributes to the meter is a pixel that could not have been drawn without it",
          not present,
          f"{os.path.basename(METER_VIEW)} is {'PRESENT' if present else 'absent'}")
    check("and it is a different build from the current one, so the comparison is not "
          "a file against itself",
          not same_file(renders["now-a"], renders["was-a"]))

    # 3. The meter is drawn, and inside the TIMELINE BAR it is all that changed.
    #
    # The bar and not the window, and the reason is in the header: the
    # reference tree ages. Every phase after this one changes chrome somewhere
    # — 6 adds inspector sections, 7 touches the export sheet — and a
    # whole-window comparison against a tree that predates them would fail with
    # the meter itself untouched, which is a proof that breaks on being right.
    # The bar is the row the meter went into and the row whose slack it took,
    # so it is what this phase can honestly hold a later one to; what changed
    # elsewhere is PRINTED, and section 3b is the check that the scoping works.
    print("\n3. the meter is drawn — and inside the timeline bar it is all that "
          "changed, in either appearance")
    bands = {}
    for tag, was, appearance in (
        ("now-a", "was-a", "dark"), ("now-light", "was-light", "light"),
    ):
        diff = changed_pixels(images[was], images[tag])
        in_bar = sharp(inside(diff, [bar], scale), WIDTH, scale)
        elsewhere = outside(diff, [bar], scale)
        boxes = clusters(in_bar)
        print(f"\n   {appearance}: {len(in_bar)} changed pixels in the bar, "
              f"in {len(boxes)} cluster(s)")
        print(describe(boxes, scale))
        check(f"{appearance}: the meter draws SOMETHING at rest — a view that drew "
              "nothing offscreen would be a view no chrome proof could ever see",
              bool(in_bar), f"{len(in_bar)} px")
        stray = outside(in_bar, [rect], scale)
        check(f"{appearance}: inside {bar}, every changed pixel is inside {rect} — the "
              "zoom cluster, S/M/L, the snap box, the eight actions and the selection "
              "block are all exactly where they were before the meter existed (the four "
              "columns the sharp pass redrew — kind chip, Snap box, zoom slider, S/M/L — "
              "masked, 2026-09-23)", not stray,
              "" if not stray else f"{len(stray)} px elsewhere in the bar:\n"
              + describe(clusters(stray), scale))
        box = extent(in_bar, scale)
        check(f"{appearance}: the changed set FILLS the rectangle the constants "
              "predict, corner to corner",
              box == (rect.x0, rect.y0, rect.x1, rect.y1),
              f"{box}" if box else "no changed pixels at all")
        print(f"      outside the bar: {len(elsewhere)} px in "
              f"{len(clusters(elsewhere))} cluster(s), NOT scored — see the comment "
              "above and section 3b")
        if elsewhere:
            print(describe(clusters(elsewhere), scale, limit=4))
        bands[appearance] = in_bar
    check("and the two appearances changed the SAME pixels — the meter's shape is its "
          "metrics, not its palette",
          bands["dark"] and set(bands["dark"]) == set(bands["light"]),
          f"dark {len(bands['dark'])} px, light {len(bands['light'])} px")

    # 3b. The scoping, staged. A claim scoped to the bar is only worth
    # something if a change outside the bar really does leave it alone, so the
    # next phase's chrome change is acted out here with the cheapest thing in
    # this program that touches the window and not the row: the PLAYHEAD, which
    # moves the toolbar's timecode and the ruler's line and reaches nothing the
    # bar draws. The reference render is section 3's own — one build against
    # the other, exactly as above — and the pair is what a whole-window
    # comparison could not survive.
    print("\n3b. the scoping, staged — a change OUTSIDE the bar, which is the shape "
          "every later phase's will have")
    shifted = Image(
        render(binary, package, png("now-shifted"), playhead=2), WIDTH)
    diff = changed_pixels(images["was-a"], shifted)
    in_bar = sharp(inside(diff, [bar], scale), WIDTH, scale)
    elsewhere = outside(diff, [bar], scale)
    print(f"      {len(diff)} changed pixels, {len(elsewhere)} of them outside the bar "
          f"in {len(clusters(elsewhere))} cluster(s)")
    print(describe(clusters(elsewhere), scale, limit=4))
    moved = outside(changed_pixels(images["now-a"], shifted), [bar], scale)
    check("moving the playhead really did change the window outside the bar — without "
          "that this section agrees with anything",
          bool(moved), f"{len(moved)} px outside the bar against now-a")
    check("…and inside the bar the two builds still differ by exactly the meter's "
          "pixels, the same set section 3 measured — which is what makes sections 3, 5 "
          "and 6 survive a phase that redraws the inspector or the export sheet",
          bool(in_bar) and set(in_bar) == set(bands["dark"]),
          f"{len(in_bar)} px in the bar vs section 3's {len(bands['dark'])}; "
          f"{len(set(in_bar) ^ set(bands['dark']))} px differ between the two sets")

    # 4. The resting appearance, solved out of those pixels.
    print("\n4. the resting appearance — LevelMeterView.draw's metrics, from the pixels")
    print(f"      the constants: scale {SCALE_W} + gap {CLIP_GAP} + cell {CLIP_CELL} "
          f"= {METER_W} pt across; {CHANNELS} rows of {ROW_H} pt at pitch {ROW_PITCH}")
    geometry_checks(bands["dark"], scale, rect, "dark")
    for appearance in ("dark", "light"):
        ink_checks(images["now-" + ("a" if appearance == "dark" else "light")],
                   bands[appearance], rect, appearance)

    # 5. The slack. The meter sits in the flexible gap and must absorb what is
    # going spare WITHOUT growing into it and without moving anything.
    print("\n5. three window widths — the meter takes the slack and gives none back")
    sizes = {}
    for width in [OTHER_WIDTHS[0], WIDTH, OTHER_WIDTHS[1]]:
        if width == WIDTH:
            a, b = images["was-a"], images["now-a"]
        else:
            a = Image(renders[f"was-{width}"], width)
            b = Image(renders[f"now-{width}"], width)
        check(f"{width} pt: the window really is {width} pt wide — a minimum the "
              "harness could not honour would make every measurement below a "
              "measurement of another window", a.width == int(width * scale),
              f"{a.width} px at scale {scale:g}")
        # Scoped to the bar, for section 3's reason.
        diff = sharp(inside(changed_pixels(a, b), [bar_rect(width)], scale), width, scale)
        boxes = clusters(diff)
        want = meter_rect(width)
        stray = outside(diff, [want], scale)
        got = ((boxes[0][0] / scale, (boxes[0][2] + 1) / scale) if boxes else None)
        sizes[width] = len(diff)
        check(f"{width} pt: the only thing that changed in the bar is the meter, at "
              f"x {want.x0:g}–{want.x1:g} pt — {METER_RIGHT_INSET} pt in from the right "
              "edge, the same inset at every width, so the zoom cluster and S/M/L never "
              "move (the kind chip, Snap box, zoom slider and S/M/L columns masked for "
              "the sharp pass, 2026-09-23)", not stray and got == (want.x0, want.x1),
              f"{len(boxes)} cluster(s), x {got} pt"
              + ("" if not stray else f"; {len(stray)} px outside the meter"))
        check(f"{width} pt: it is {METER_W} pt wide — its intrinsic size, never stretched "
              f"toward the {METER_MAX_W} pt cap, because the row's spacer wins the slack",
              got is not None and abs((got[1] - got[0]) - METER_W) < 0.01,
              f"{got[1] - got[0] if got else '—'} pt")
    check("and the same NUMBER of pixels changed at all three widths, which is the "
          "same meter drawn three times rather than three meters",
          len(set(sizes.values())) == 1, f"{sizes}")

    # 6. The minimum window. This is the one the contract's D-B4 is written
    # about, and the claim is the strongest kind available: not "the meter got
    # small" but "the window is what it was".
    print(f"\n6. the {MINIMUM_WIDTH} pt minimum — the meter vanishes rather than pushing")
    print(f"      the row's fixed content measures about 880 pt against {MINIMUM_WIDTH}, "
          f"so what is left over is far under minimumWidth {METER_MIN_W} pt")
    narrow_was = Image(renders[f"was-{MINIMUM_WIDTH}"], MINIMUM_WIDTH)
    narrow = Image(renders[f"now-{MINIMUM_WIDTH}"], MINIMUM_WIDTH)
    narrow_diff = changed_pixels(narrow_was, narrow)
    narrow_bar = sharp(
        inside(narrow_diff, [bar_rect(MINIMUM_WIDTH)], scale), MINIMUM_WIDTH, scale)
    check(
        f"at {MINIMUM_WIDTH} pt the timeline bar is byte-identical to the build before "
        "the meter existed — the meter drew nothing, and nothing else in the row moved "
        "to make space for it (outside the sharp pass's four masked columns, 2026-09-23)",
        not narrow_bar,
        "" if not narrow_bar else f"{len(narrow_bar)} px differ:\n"
        + describe(clusters(narrow_bar), scale))
    # Whole-window, as INFORMATION. It is zero today and this script would like
    # it said out loud, but it is not scored: see section 3's comment — the
    # reference tree ages and the rest of the window is not this phase's to
    # promise. Whether the two files are byte-identical is the cheapest way to
    # say it, since a PNG whose pixels all agree can still differ in its bytes.
    print(f"      outside the bar: {len(narrow_diff) - len(narrow_bar)} px, NOT scored; "
          f"the two PNGs are "
          f"{'byte-identical' if same_file(renders[f'was-{MINIMUM_WIDTH}'], renders[f'now-{MINIMUM_WIDTH}']) else 'different files'}")
    check(f"…and it is a {MINIMUM_WIDTH} pt window that says so",
          narrow.width == int(MINIMUM_WIDTH * scale),
          f"{narrow.width} px at scale {scale:g}")

    # 7. The instrument's own honesty, and the one thing a byte comparison
    # cannot see: a constraint the solver had to break to lay the row out.
    print("\n7. the renders themselves")
    unsettled = [(tag, text) for tag, text in WARNINGS if "never settled" in text]
    other = [(tag, text) for tag, text in WARNINGS if (tag, text) not in unsettled]
    check("no render reported an unsettled layout", not unsettled,
          "" if not unsettled else "\n".join(f"      {t}: {x}" for t, x in unsettled))
    check("and the eleven quiet renders wrote nothing else to stderr either",
          not other, "" if not other else "\n".join(f"      {t}: {x}" for t, x in other))
    # The noisy twelfth. `OS_ACTIVITY_DT_MODE` is what makes AppKit's
    # "Conflicting constraints detected" reach a pipe at all; measured against
    # a build whose meter carried a REQUIRED 2000 pt width, the same render
    # comes back with 252 lines of it, so this is a check that can fail.
    log = STDERR[os.path.basename(renders["now-loud"])].splitlines()
    conflicts = [line for line in log if "constraint" in line.lower()]
    print(f"      {len(log)} lines of AppKit diagnostics from the {MINIMUM_WIDTH} pt "
          f"render, {len(conflicts)} of them about constraints")
    check(f"at {MINIMUM_WIDTH} pt the row lays out with NO conflicting constraint — the "
          "meter compresses to nothing and stops drawing, which is why it carries no "
          "divider (TimelineBar.build's own arithmetic: one more stack gap fits, a "
          "divider's gap and hairline would not)", not conflicts,
          "" if not conflicts else "\n".join("      " + line[:150] for line in conflicts[:4]))
    identical(
        "…and turning the diagnostics on changed nothing about the picture, so the "
        "quiet render section 6 compared is the one that was inspected here",
        renders[f"now-{MINIMUM_WIDTH}"], renders["now-loud"], points=MINIMUM_WIDTH)

    # 8. The reading, which is not a picture — see the file's header.
    reading_checks(binary)

    # 9. The export gain, which is not a picture either.
    gain_checks()

    # Crops for the eye check: the meter and a little of the bar around it.
    crop = Rect("meter", rect.x0 - 20, rect.y0 - 12, METER_W + 40, METER_H + 24)
    for tag in ("now-a", "was-a", "now-light", "was-light"):
        images[tag].crop(crop, os.path.join(CHROME, f"crop-{tag}.png"))
    print(f"\nPNGs, crops and the model's signal files and answers are in "
          f"{os.path.relpath(CHROME, ROOT)}/")
    print("A LIT meter is not claimed here and cannot be: the harness has no player, so "
          "every\nrender photographs the resting state, and the ballistics that would "
          "light it are the\nview's while the number is the model's — which is what "
          "section 8 measures instead.")

    report()


if __name__ == "__main__":
    main()
