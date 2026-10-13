"""Road map 5, E2 — the Motion section, the Clip ▸ Motion menu and the
timeline's wedges, offscreen.

    python3 tools/proof/e2_chrome.py

Two instruments, neither of which is a photograph of a running app:

* **the harness** (`tools/proof/harness/`) compiles every file in
  `app/Sources` with a `main.swift` of its own, opens a `.framejob` package,
  puts an `EditorViewController` in an `NSWindow` and `cacheDisplay`s it into
  a PNG — the same paint path the window uses, no TCC grant.
* **a probe** compiled from `app/Sources` over `harness/build.sh`'s own
  `swiftc` line, for what no photograph can answer: three submenus and their
  tags, a validator's checkmarks, the rows a section builds and which of them
  are live, and what two commands do to a project. A probe that will not
  build is a scored FAILURE and never an exit.

**What the wedges say.** A clip whose motion has an arrival or a departure
draws a triangle along the bottom of its name strip, as long as the preset
lasts at the current zoom: `duration × body.width / clip.duration`, at least
2 pt, 4 pt tall (`TimelineClipDrawing.swift`). At the default zoom of 42 pt/s
a four-second card's body is 168 pt wide from `CLIP_X0` = 132, so a
one-second arrival is a wedge over `[132, 174]` and a half-second departure
one over `[279, 300]`. Those two numbers are the claim, and they are measured
as the pixels that differ from the SAME card with no motion at all.

A `during` draws no wedge: it is continuous and has no length to show. It
draws an 11 pt glyph at the strip's right end instead, and that is the other
diff.

**Nothing `private` is widened.** A section's `id`, a control's `isActive` and
a checkbox's title are all private, so a section is named by where it is, a
control's liveness is read off the `alphaValue` the inspector composites it
at (1, or 0.42 when it is off), and a popup is driven by ObjC selector
dispatch on `itemPicked:` — the message the menu itself sends.
"""

import json
import os
import re
import struct
import subprocess
import sys
import time
import zlib

import swift_build

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work")
CHROME = os.path.join(WORK, "chrome-e2")
BUILD = os.path.join(HERE, "harness", "build.sh")
PROBE = os.path.join(WORK, "e2probe")

# ---------------------------------------------------------------------------
# Geometry, in POINTS, from the app's layout constants — `phase2_chrome.py`'s
# block, with the two numbers the wedges need.

WIDTH, HEIGHT = 1440, 862
# The timeline renders are at 862, the window every earlier chrome script
# photographs. The INSPECTOR renders are taller, and ask for the Clip sub-tab
# (road map 9 §3), where Motion presets now lives: they were first made taller
# when Motion was the tenth section of one long stack, below the fold at 862,
# and the height is kept. Recorded as a deviation.
SECTION_HEIGHT = 1600
TOOLBAR = 44             # DS.toolbarHeight
INSPECTOR_W = 304        # DS.panelWidth
TIMELINE_H = 300         # EditorViewController.defaultTimelineHeight
BAR_H = 36               # DS.timelineBarHeight
RULER_H = 22             # DS.rulerHeight
HEADER_W = 132           # DS.trackHeaderWidth
LANES_INSET = 4          # TimelineLayout.lanesInset
ZOOM = 42                # TimelineLayout.defaultZoom, points per second
BODY_INSET = 3           # TimelineContentView.bodyRect
STRIP_H = 16             # DS.clipHeaderHeight
ROW_PITCH = 29           # DS.controlHeight (22) + InspectorMetrics.rowSpacing (7)

INSPECTOR_X = WIDTH - INSPECTOR_W                        # 1136
TIMELINE_Y = HEIGHT - TIMELINE_H                         # 562
LANES_TOP = TIMELINE_Y + BAR_H + RULER_H + LANES_INSET   # 624
STRIP_Y = LANES_TOP + BODY_INSET                         # 627
CLIP_X0 = HEADER_W                                       # time zero
CLIP_SECONDS = 4
CLIP_X1 = CLIP_X0 + ZOOM * CLIP_SECONDS                  # 300

TICKS = 600_000
BLACK = [0.0, 0.0, 0.0, 1.0]
GLYPH_W = 11             # the during glyph's box

RESULTS = []
WARNINGS = []


def check(name, ok, detail=""):
    RESULTS.append(bool(ok))
    print(f"  {'PASS' if ok else 'FAIL'}: {name}")
    if detail:
        print(detail if detail.startswith("      ") else "      " + detail)


def failure(name, why):
    check(name, False, why)


# ---------------------------------------------------------------------------
# The fixtures, hand-written at version 8.


def video_props(motion=None):
    """`VideoProps` in the core's field order (`model_props.rs`), with
    `motion` LAST — where format version 8 appended it."""
    return {
        "x": 0.0, "y": 0.0, "scale": 1.0, "rotation": 0.0, "opacity": 1.0,
        "crop": {"l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0},
        "corner_radius": 0.0, "shadow": None,
        "color": {"brightness": 0.0, "contrast": 0.0, "saturation": 0.0, "hue": 0.0},
        "chroma": None, "filters": [], "reflection": None, "spotlight": None,
        "obscure": [], "blend": "normal", "motion": motion,
    }


def edge(kind, seconds):
    return {"kind": kind, "duration": int(round(seconds * TICKS))}


def slot(kind, amount=0.5, seconds=1.0):
    return {"kind": kind, "amount": amount, "period": int(round(seconds * TICKS))}


def motion(arrive=None, leave=None, during=None):
    if arrive is None and leave is None and during is None:
        return None
    return {"in": arrive, "out": leave, "during": during}


def shape_props(fill):
    return {
        "kind": "rectangle", "width": 640.0, "height": 360.0, "stroke": None,
        "fill": fill, "arrow_start": False, "arrow_end": False, "radius": 0.0,
        "from": [0.0, 1.0], "to": [1.0, 0.0], "gradient": None,
    }


def clip(cid, start, fill, motion_value=None, actions=None, name=None,
         duration=CLIP_SECONDS * TICKS, label=None):
    return {
        "id": cid, "track": 1, "start": start, "duration": duration,
        "source": {"kind": "shape"},
        "enabled": {"video": True, "audio": True}, "speed": 1.0,
        "video": video_props(motion_value), "audio": None, "text": None,
        "shape": shape_props(fill), "actions": actions or [], "transition_in": None,
        "name": name, "label": label,
    }


def audio_only_clip(cid, start, motion_value=None, name=None,
                    duration=CLIP_SECONDS * TICKS):
    """A clip whose media has NO video — what `InspectorTab.hasPixels` says no
    to, and the only fixture shape that exercises the strip's gate. The file
    need not exist: the timeline paints from the snapshot."""
    return {
        "id": cid, "track": 1, "start": start, "duration": duration,
        "source": {"kind": "media", "media": 90, "in": 0, "reversed": False},
        "enabled": {"video": True, "audio": True}, "speed": 1.0,
        "video": video_props(motion_value), "audio": {}, "text": None,
        "shape": None, "actions": [], "transition_in": None,
        "name": name, "label": None,
    }


AUDIO_MEDIA = [{
    "id": 90, "path": "/fixtures/voice.m4a", "kind": "audio",
    "duration": 60 * TICKS, "width": 0, "height": 0, "fps": [30, 1],
    "has_video": False, "has_audio": True,
}]


def project(clips, media=None):
    return {
        "version": 8,
        "canvas": {
            "width": 1920, "height": 1080, "fps": [30, 1], "background": BLACK,
            "fit_new_clips": True, "timecode_frames": True,
        },
        "media": media or [],
        "tracks": [{"id": 1, "name": "Track 1", "hidden": False, "muted": False,
                    "locked": False, "solo": False}],
        "clips": clips,
        "markers": [],
        # Ids are unique across the WHOLE project — `next_id` is one counter —
        # so an ACTION's id counts too.
        "next_id": max([c["id"] for c in clips]
                       + [a["id"] for c in clips for a in c["actions"]]
                       + [m["id"] for m in media or []] + [1]) + 1,
        "nests": [],
    }


def write_package(name, body):
    path = os.path.join(CHROME, name + ".framejob")
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "project.json"), "w", encoding="utf-8") as handle:
        json.dump(body, handle, indent=2)
        handle.write("\n")
    return path


# A menu tag no builder in this app writes: `motionSlotMenu` writes −1 for
# None and 0…n for the kinds (the E2 reader review's N·1). The EXTREMES of
# the same rule — `Int.min`, `Int.max`, `count`, `count + 1` and `0` — are
# carried in the probe's own source instead of here, because `Int.min` does not
# survive `JSONSerialization` in either direction (block (f)).
STRANGER_TAG = -7

GREY = [0.6, 0.6, 0.6, 1.0]


def packages():
    """Every fixture, by tag. The name is the render tag, so a reader who
    wants to look at one knows which PNG it is."""
    return {
        # The three the wedges are measured from: one card, one track, the
        # SAME in all three but for its motion.
        "wedges": write_package("e2-wedges", project([
            clip(2, 0, GREY, motion(edge("fade", 1.0), edge("fade", 0.5)), name="Card")])),
        "none": write_package("e2-none", project([clip(2, 0, GREY, None, name="Card")])),
        "zero-in": write_package("e2-zero-in", project([
            clip(2, 0, GREY, motion(edge("fade", 0)), name="Card")])),
        "zero-out": write_package("e2-zero-out", project([
            clip(2, 0, GREY, motion(leave=edge("fade", 0)), name="Card")])),
        "zero-both": write_package("e2-zero-both", project([
            clip(2, 0, GREY, motion(edge("fade", 0), edge("fade", 0)), name="Card")])),
        "frame-in": write_package("e2-frame-in", project([
            clip(2, 0, GREY, motion(edge("fade", 1 / 30)), name="Card")])),
        "frame-out": write_package("e2-frame-out", project([
            clip(2, 0, GREY, motion(leave=edge("fade", 1 / 30)), name="Card")])),
        "zero-mixed": write_package("e2-zero-mixed", project([
            clip(2, 0, GREY, motion(edge("fade", 0))),
            clip(3, CLIP_SECONDS * TICKS, GREY, motion(edge("fade", 0.5)))])),
        "zero-different": write_package("e2-zero-different", project([
            clip(2, 0, GREY, motion(edge("fade", 0))),
            clip(3, CLIP_SECONDS * TICKS, GREY, motion(edge("slide_up", 0.5)))])),
        "during": write_package("e2-during", project([
            clip(2, 0, GREY, motion(during=slot("pulse")), name="Card")])),
        # The probe's.
        "one": write_package("e2-one", project([
            clip(2, 0, GREY, motion(edge("slide_up", 0.5)))])),
        "two": write_package("e2-two", project([
            clip(2, 0, GREY, motion(edge("slide_up", 0.5))),
            clip(3, CLIP_SECONDS * TICKS, GREY, motion(edge("fade", 0.5)))])),
        "pulse": write_package("e2-pulse", project([
            clip(2, 0, GREY, motion(edge("fade", 1.0), during=slot("pulse")))])),
        "drift": write_package("e2-drift", project([
            clip(2, 0, GREY, motion(during=slot("drift")))])),
        "action": write_package("e2-action", project([
            clip(2, 0, GREY, None, actions=[{
                "id": 3, "start": 0, "duration": TICKS, "curve": "linear",
                "end": {"video": {"x": 100.0}},
            }])])),
        "zero-action": write_package("e2-zero-action", project([
            clip(2, 0, GREY, motion(edge("fade", 0)), actions=[{
                "id": 3, "start": 0, "duration": TICKS, "curve": "linear",
                "end": {"video": {"x": 100.0}},
            }])])),
        # The glyph against the LABEL dot (the E2 reader review's N·2): the
        # same labelled card with and without a `during`, so the only pixels
        # that differ are the glyph's.
        "labelled": write_package("e2-labelled", project([
            clip(2, 0, GREY, motion(during=slot("pulse")), name="Card",
                 label="blue")])),
        "labelled-none": write_package("e2-labelled-none", project([
            clip(2, 0, GREY, None, name="Card", label="blue")])),
        # The strip's GATE: a clip whose media has no video carries motion in
        # its props (a detached audio twin clones them) and must draw none of
        # it.
        "silent": write_package("e2-silent", project([
            audio_only_clip(2, 0, motion(edge("fade", 1.0), edge("fade", 0.5),
                                         slot("pulse")), name="Voice")],
            media=AUDIO_MEDIA)),
        "silent-none": write_package("e2-silent-none", project([
            audio_only_clip(2, 0, None, name="Voice")], media=AUDIO_MEDIA)),
    }


# ---------------------------------------------------------------------------
# PNG, in pure Python (phase4_chrome.py's, unchanged).


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
        sys.exit(f"{path}: {depth}-bit or interlaced")
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


def changed_pixels(a, b):
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


def describe(boxes, scale, limit=8):
    lines = []
    for x0, y0, x1, y1, n in boxes[:limit]:
        lines.append(
            f"      x {x0 / scale:.1f}–{(x1 + 1) / scale:.1f} y {y0 / scale:.1f}–"
            f"{(y1 + 1) / scale:.1f} pt  ({n} px)")
    if len(boxes) > limit:
        lines.append(f"      … and {len(boxes) - limit} more clusters")
    return "\n".join(lines)


def points(box, scale):
    """A cluster's bounding box in points: (x0, y0, x1, y1), the far edges
    exclusive."""
    return (box[0] / scale, box[1] / scale, (box[2] + 1) / scale, (box[3] + 1) / scale)


# ---------------------------------------------------------------------------
# The harness.


def build_harness():
    start = time.time()
    result = subprocess.run([BUILD], capture_output=True, text=True)
    if result.returncode != 0:
        return None, (result.stdout + result.stderr).strip()[-400:]
    binary = result.stdout.strip().splitlines()[-1]
    built = "built" in result.stderr
    print(f"harness: {binary} "
          f"({'built in %.1f s' % (time.time() - start) if built else 'up to date'})")
    return binary, None


def render(binary, package, out, expand="-", select=-1, height=HEIGHT, sub_tab=None):
    args = [binary, package, out, "light", str(WIDTH), str(height), str(select),
            "0", "1", "clip", "-", expand]
    if sub_tab:
        args += ["-", "-", sub_tab]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stdout + result.stderr).strip()[-400:]
    if result.stderr.strip():
        WARNINGS.append(f"{os.path.basename(out)}: {result.stderr.strip()}")
    return out, None


# ---------------------------------------------------------------------------
# The probe.

PROBE_SOURCE = r'''// Written by tools/proof/e2_chrome.py. See that file's header.
import AppKit

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()

let request = try! JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func dump(_ item: NSMenuItem) -> [String: Any] {
    var row: [String: Any] = [
        "title": item.title, "separator": item.isSeparatorItem, "tag": item.tag,
        "action": item.action.map { NSStringFromSelector($0) } ?? "",
    ]
    if let sub = item.submenu {
        row["submenu"] = ["title": sub.title, "items": sub.items.map(dump)]
    }
    return row
}

func opened(_ path: String) -> ProjectDocument {
    let document = ProjectDocument()
    try! document.read(
        from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
    return document
}

func ordered(_ document: ProjectDocument) -> [ClipSnapshot] {
    document.project.snapshot.clips.sorted { $0.start < $1.start }
}

func select(_ document: ProjectDocument, _ indices: [Int]) {
    let clips = ordered(document)
    document.selection = Set(indices.compactMap {
        clips.indices.contains($0) ? clips[$0].id : nil
    })
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func state(_ value: NSControl.StateValue) -> String {
    value == .on ? "on" : (value == .mixed ? "mixed" : "off")
}

/// The control a row's label belongs to, and the alpha the inspector
/// composites it at — 1 when the row is live, 0.42 when it is not
/// (`OptionControls.swift`). A control's own `isActive` is private;
/// `alphaValue` is the public signal it sets, so nothing is widened.
func controlAfter(_ label: InspectorRowLabel) -> (NSView?, Double) {
    guard let parent = label.superview,
          let index = parent.subviews.firstIndex(of: label) else { return (nil, 1) }
    for view in parent.subviews[(index + 1)...] where view is OptionControl || view is NSControl {
        return (view, Double(view.alphaValue))
    }
    return (nil, 1)
}

/// Every `InspectorSection` in tree order with the rows inside it. A
/// section's `id` has been readable since road map 9's phase 2; a section is
/// still named here by WHERE it is and by what it holds.
func sections(_ root: NSView) -> [[String: Any]] {
    walk(root).compactMap { view -> [String: Any]? in
        guard let section = view as? InspectorSection else { return nil }
        let inside = walk(section)
        let labels = inside.compactMap { $0 as? InspectorRowLabel }
        return [
            "labels": labels.map { $0.stringValue },
            "rows": labels.map { label -> [String: Any] in
                let (control, alpha) = controlAfter(label)
                return [
                    "label": label.stringValue,
                    "control": control.map { String(describing: type(of: $0)) } ?? "",
                    "alpha": alpha,
                ]
            },
            "buttons": inside.compactMap { ($0 as? OptionButtonControl)?.toolTip },
            "expanded": section.isExpanded,
        ]
    }
}

func editor(_ path: String, select indices: [Int], playhead: Ticks? = nil)
    -> (ProjectDocument, EditorViewController)
{
    let document = opened(path)
    select(document, indices)
    if let playhead { document.playhead = playhead }
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.2)
    let controller =
        document.windowControllers.first!.contentViewController as! EditorViewController
    if let playhead { controller.setPlayhead(playhead) }
    // Motion presets is on the Clip sub-tab (road map 9 §3), where the rows
    // below look for it.
    controller.inspector?.selectClipSubTab(.clip)
    spin(0.3)
    return (document, controller)
}

var answer: [String: Any] = [
    "menu": ["title": NSApp.mainMenu?.title ?? "",
             "items": (NSApp.mainMenu?.items ?? []).map(dump)],
    "edges": EdgeMotion.allCases.map(\.displayName),
    "durings": DuringMotion.allCases.map(\.displayName),
]

// ---- validation -----------------------------------------------------------
var validations: [[String: Any]] = []
for probe in request["validate"] as? [[String: Any]] ?? [] {
    let document = opened(probe["package"] as! String)
    select(document, probe["select"] as? [Int] ?? [])
    let controller = EditorViewController(document: document)
    var entries: [[String: Any]] = []
    for spec in probe["selectors"] as? [[String: Any]] ?? [] {
        let item = NSMenuItem(
            title: "", action: NSSelectorFromString(spec["selector"] as! String),
            keyEquivalent: "")
        item.tag = spec["tag"] as! Int
        let enabled = controller.validateUserInterfaceItem(item)
        entries.append([
            "selector": spec["selector"] as! String, "tag": item.tag,
            "enabled": enabled, "state": state(item.state),
        ])
    }
    validations.append(["name": probe["name"] as! String, "entries": entries])
}
answer["validation"] = validations

// ---- the section's rows ---------------------------------------------------
var panes: [String: Any] = [:]
for probe in request["rows"] as? [[String: Any]] ?? [] {
    let (_, controller) = editor(probe["package"] as! String,
                                 select: probe["select"] as? [Int] ?? [])
    panes[probe["name"] as! String] = sections(controller.view)
}
answer["rows"] = panes

// ---- (a) During ▸ None leaves the other two slots alone -------------------
do {
    let (document, controller) = editor(request["clearPackage"] as! String, select: [0])
    let item = NSMenuItem(
        title: "", action: #selector(EditorViewController.setMotionDuring(_:)),
        keyEquivalent: "")
    item.tag = -1
    controller.setMotionDuring(item)
    spin(0.8)
    answer["cleared"] = document.project.json
}

// ---- (b) the section's popup, inside an action ----------------------------
do {
    let spec = request["insideAction"] as! [String: Any]
    let (document, controller) = editor(spec["package"] as! String, select: [0],
                                        playhead: spec["playhead"] as! Ticks)
    // The In popup: the first `OptionPopupControl` after a label spelled "In"
    // in the section that holds the Motion run. Driven the way the menu
    // itself drives it — `itemPicked:` over ObjC dispatch, nothing widened.
    var picked = false
    for view in walk(controller.view) {
        guard let label = view as? InspectorRowLabel, label.stringValue == "In",
              let parent = label.superview,
              let index = parent.subviews.firstIndex(of: label) else { continue }
        guard let control = parent.subviews[(index + 1)...].first(where: { $0 is OptionPopupControl })
        else { continue }
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.tag = spec["tag"] as! Int
        control.perform(NSSelectorFromString("itemPicked:"), with: item)
        picked = true
        break
    }
    spin(0.8)
    answer["insideAction"] = ["picked": picked, "project": document.project.json,
                              "playhead": Int(document.playhead)]
}

// ---- (c) a menu tag no builder writes -------------------------------------
// The E2 reader review's N·1. `motionSlotMenu` writes −1 for None and an
// index for every other item, so −7 came from nowhere this app knows. The
// clip HAS an arrival, which is what makes the write visible: the unfixed
// build read every negative tag as None and cleared it.
do {
    let (document, controller) = editor(request["strangerPackage"] as! String, select: [0])
    let before = document.project.json
    let item = NSMenuItem(
        title: "", action: #selector(EditorViewController.setMotionIn(_:)),
        keyEquivalent: "")
    item.tag = request["strangerTag"] as! Int
    controller.setMotionIn(item)
    spin(0.8)
    answer["stranger"] = ["before": before, "after": document.project.json]
}

// ---- (d) the zoom band's note follows the clip ----------------------------
// The E2 reader review's N·3. Armed on a clip with no `during`, then a
// `during` added and cleared through the ordinary command while the band
// stays up. `armed` says whether the mode could be entered at all — a
// harness window may have no canvas box to aim at, and a claim nothing
// reached is not a claim.
do {
    let (_, controller) = editor(request["notePackage"] as! String, select: [0])
    controller.zoomToRegion(nil)
    spin(0.5)
    var trail: [String] = []
    let armed = controller.canvasRegion != nil
    func noteNow() -> String { controller.canvasRegion?.note ?? "" }
    if armed {
        trail.append(noteNow())
        let on = NSMenuItem(
            title: "", action: #selector(EditorViewController.setMotionDuring(_:)),
            keyEquivalent: "")
        on.tag = 0
        controller.setMotionDuring(on)
        spin(0.8)
        trail.append(noteNow())
        let off = NSMenuItem(
            title: "", action: #selector(EditorViewController.setMotionDuring(_:)),
            keyEquivalent: "")
        off.tag = -1
        controller.setMotionDuring(off)
        spin(0.8)
        trail.append(noteNow())
        controller.endRegionMode()
    }
    answer["note"] = ["armed": armed, "trail": trail,
                      "expected": CanvasRegionView.duringNote]
}

// ---- (e) one op PER CLIP, and one undo step -------------------------------
// The E2 reader review's reader 4. A `motion` patch replaces the whole
// object, so a batch that sent ONE op over every id would give every clip
// the last one's whole motion — the two fixtures disagree about their
// arrival, which is what makes that visible. And the whole batch is one
// undo step: one undo puts `project.json` back byte for byte.
do {
    let (document, controller) = editor(request["perClipPackage"] as! String,
                                        select: [0, 1])
    let before = document.project.json
    let item = NSMenuItem(
        title: "", action: #selector(EditorViewController.setMotionDuring(_:)),
        keyEquivalent: "")
    item.tag = 0
    controller.setMotionDuring(item)
    spin(0.8)
    let after = document.project.json
    document.undoManager?.undo()
    spin(0.8)
    answer["perClip"] = ["before": before, "after": after,
                         "undone": document.project.json,
                         "name": document.undoManager?.redoActionName ?? ""]
}

// ---- (f) N·1's EXTREMES, through the same two doors ----------------------
// The E2 reader review recorded these five tags by INSPECTION and owed a row.
// The tag VALUES live here and never in the request's JSON — `Int.min` is not
// trusted through `JSONSerialization` either way — so the rows are keyed by
// NAME. `0` writes LAST because it is the one tag that is MEANT to write: it
// is the positive control, without which a gate that refused everything would
// pass the four strangers for the wrong reason. The write fixture's In is SET
// (`slide_up`), so a tag read as None would show as a cleared arrival.
do {
    let n = EdgeMotion.allCases.count
    let extremes: [(String, Int)] = [
        ("Int.min", Int.min), ("Int.max", Int.max), ("count", n),
        ("count+1", n + 1), ("0", 0),
    ]
    let spec = request["extremes"] as! [String: Any]
    let (document, controller) = editor(spec["writePackage"] as! String, select: [0])
    var writes: [[String: Any]] = []
    for (name, tag) in extremes {
        let before = document.project.json
        let item = NSMenuItem(
            title: "", action: #selector(EditorViewController.setMotionIn(_:)),
            keyEquivalent: "")
        item.tag = tag
        controller.setMotionIn(item)
        spin(0.8)
        writes.append(["name": name, "before": before, "after": document.project.json])
    }
    // The VALIDATOR half, on the card whose In is EMPTY — the only fixture
    // where "checks nothing" and "reads as None" differ — with None itself as
    // the control. Built exactly as the validate loop above builds its items.
    let empty = opened(spec["validatePackage"] as! String)
    select(empty, [0])
    let inspector = EditorViewController(document: empty)
    var validates: [[String: Any]] = []
    for (name, tag) in extremes + [("-1", -1)] {
        let item = NSMenuItem(
            title: "", action: #selector(EditorViewController.setMotionIn(_:)),
            keyEquivalent: "")
        item.tag = tag
        let enabled = inspector.validateUserInterfaceItem(item)
        validates.append(["name": name, "state": state(item.state), "enabled": enabled])
    }
answer["extremes"] = ["count": n, "writes": writes, "validates": validates]
}

// ---- E2-27: the real menu items and inspector controls -------------------
UserDefaults.standard.set(false, forKey: InspectorSection.collapsedKeyPrefix + "video.motion")
/// Looked up inside the Motion presets section when there is one: on the
/// Clip sub-tab Timing's own "In" row comes first (road map 9 §3).
func rowControl(_ root: NSView, _ name: String) -> NSView? {
    let motion = walk(root).first { ($0 as? InspectorSection)?.id == "video.motion" }
    for view in walk(motion ?? root) {
        guard let label = view as? InspectorRowLabel, label.stringValue == name else { continue }
        return controlAfter(label).0
    }
    return nil
}

func noteState(_ root: NSView) -> [String: Any] {
    guard let note = walk(root).compactMap({ $0 as? MotionInactiveNote }).first else {
        return ["found": false]
    }
    let next = rowControl(root, "In")
    let noteBox = note.convert(note.bounds, to: nil)
    let nextBox = next.map { $0.convert($0.bounds, to: nil) }
    let field = rowControl(root, "In Duration") as? OptionFieldControl
    return [
        "found": true, "text": note.stringValue, "hidden": note.isHidden,
        "height": note.bounds.height, "intrinsic": note.intrinsicContentSize.height,
        "width": note.bounds.width,
        "clearance": nextBox.map { noteBox.minY - $0.maxY } ?? -1000,
        "duration": field?.subviews.compactMap { $0 as? NSTextField }.first?.stringValue ?? "",
        "durationAlpha": field?.alphaValue ?? 0,
    ]
}

func validateEdge(_ controller: EditorViewController, _ item: NSMenuItem) -> [String: Any] {
    let enabled = controller.validateUserInterfaceItem(item)
    return ["title": item.title, "state": state(item.state), "enabled": enabled]
}

do {
    let (document, controller) = editor(request["zeroPackage"] as! String, select: [0])
    let fade = NSMenuItem(title: "Fade", action: #selector(EditorViewController.setMotionIn(_:)),
                          keyEquivalent: "")
    fade.tag = 0
    let none = NSMenuItem(title: "None", action: #selector(EditorViewController.setMotionIn(_:)),
                          keyEquivalent: "")
    none.tag = -1
    let out = NSMenuItem(title: "Fade", action: #selector(EditorViewController.setMotionOut(_:)),
                         keyEquivalent: "")
    out.tag = 0
    var trail: [[String: Any]] = []
    trail.append(["fade": validateEdge(controller, fade), "out": validateEdge(controller, out),
                  "none": validateEdge(controller, none),
                  "note": noteState(controller.view)])
    let before = document.project.json
    if let field = rowControl(controller.view, "In Duration") as? OptionFieldControl {
        let pick = NSMenuItem(title: "0.25 s", action: nil, keyEquivalent: "")
        pick.tag = 0
        field.perform(NSSelectorFromString("quickPicked:"), with: pick)
    }
    spin(0.8)
    trail.append(["fade": validateEdge(controller, fade), "out": validateEdge(controller, out),
                  "none": validateEdge(controller, none),
                  "note": noteState(controller.view), "project": document.project.json])
    document.undoManager?.undo()
    spin(0.8)
    trail.append(["fade": validateEdge(controller, fade), "out": validateEdge(controller, out),
                  "none": validateEdge(controller, none),
                  "note": noteState(controller.view), "project": document.project.json])
    // The actual inspector popup's None command removes the stored edge.
    if let popup = rowControl(controller.view, "In") as? OptionPopupControl {
        let pick = NSMenuItem(title: "None", action: nil, keyEquivalent: "")
        pick.tag = 0
        popup.perform(NSSelectorFromString("itemPicked:"), with: pick)
    }
    spin(0.8)
    trail.append(["fade": validateEdge(controller, fade), "out": validateEdge(controller, out),
                  "none": validateEdge(controller, none),
                  "note": noteState(controller.view), "project": document.project.json])
    select(document, [])
    trail.append(["fade": validateEdge(controller, fade), "none": validateEdge(controller, none)])
    answer["zeroTrail"] = ["before": before, "steps": trail]
}

var selectionStates: [String: Any] = [:]
for name in ["zeroMixed", "zeroDifferent"] {
    let (_, controller) = editor(request[name] as! String, select: [0, 1])
    let item = NSMenuItem(title: "Fade", action: #selector(EditorViewController.setMotionIn(_:)),
                          keyEquivalent: "")
    item.tag = 0
    selectionStates[name] = ["menu": validateEdge(controller, item),
                              "note": noteState(controller.view)]
}
answer["zeroSelections"] = selectionStates

do {
    let (document, controller) = editor(request["zeroAction"] as! String,
                                        select: [0], playhead: Ticks(300_000))
    let notes = walk(controller.view).compactMap { $0 as? InspectorNoteLabel }
        .map { $0.stringValue }.filter { !$0.isEmpty }
    let inactive = noteState(controller.view)
    if let field = rowControl(controller.view, "In Duration") as? OptionFieldControl {
        let pick = NSMenuItem(title: "0.25 s", action: nil, keyEquivalent: "")
        pick.tag = 0
        field.perform(NSSelectorFromString("quickPicked:"), with: pick)
    }
    spin(0.8)
    answer["zeroAction"] = ["notes": notes, "inactive": inactive,
                             "project": document.project.json]
}

do {
    let (document, controller) = editor(request["zeroPackage"] as! String, select: [0])
    let none = NSMenuItem(title: "None", action: #selector(EditorViewController.setMotionOut(_:)),
                          keyEquivalent: "")
    none.tag = -1
    controller.setMotionOut(none)
    spin(0.8)
    let afterMenu = document.project.json
    // Reset is the real header control, reached through the public view tree.
    let section = walk(controller.view).compactMap { $0 as? InspectorSection }.first {
        let names = walk($0).compactMap { ($0 as? InspectorRowLabel)?.stringValue }
        return names.contains("In Duration") && names.contains("Out Duration")
    }
    let reset = section.flatMap { walk($0).compactMap { $0 as? OptionButtonControl }
        .first { $0.toolTip == "Reset this section to its defaults" } }
    if let reset, let event = NSEvent.mouseEvent(
        with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
        reset.mouseDown(with: event)
    }
    spin(0.8)
    answer["zeroRemove"] = ["afterMenu": afterMenu, "afterReset": document.project.json,
                             "resetFound": reset != nil, "note": noteState(controller.view)]
}

try! JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
    .write(to: out)
exit(0)
'''


def build_probe():
    os.makedirs(PROBE, exist_ok=True)
    binary = os.path.join(PROBE, "e2probe")
    entry = os.path.join(PROBE, "main.swift")
    if not os.path.exists(entry) or open(entry).read() != PROBE_SOURCE:
        with open(entry, "w") as f:
            f.write(PROBE_SOURCE)
    sources = sorted(
        os.path.join(ROOT, "app", "Sources", name)
        for name in os.listdir(os.path.join(ROOT, "app", "Sources"))
        if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    try:
        built = swift_build.build(sources=sources + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    if built.reused:
        print(f"probe: {binary} (up to date)")
    else:
        print(f"probe: {binary} (built in {built.seconds:.1f} s)")
    return binary, None


def run_probe(binary, request):
    path = os.path.join(CHROME, "probe-request.json")
    out = os.path.join(CHROME, "probe.json")
    with open(path, "w") as f:
        json.dump(request, f, indent=2)
    result = subprocess.run([binary, path, out], capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stdout + result.stderr).strip()[-400:]
    with open(out) as f:
        return json.load(f), None


def submenu(menu, *titles):
    items = menu["items"]
    for title in titles:
        found = next((i for i in items if i["title"] == title), None)
        if found is None or "submenu" not in found:
            return None
        items = found["submenu"]["items"]
    return items


def motion_section(panes):
    """The section that holds the Motion run — named by what it holds, as it
    always was (`InspectorSection.id` has been readable since road map 9's
    phase 2)."""
    run = ["In", "In Duration", "Out", "Out Duration", "During", "Amount", "Period"]
    for pane in panes:
        if pane["labels"] == run:
            return pane
    return None


# ---------------------------------------------------------------------------


def main():
    os.makedirs(CHROME, exist_ok=True)
    print("E2 chrome — the Motion section, the menu and the timeline's wedges")
    fixtures = packages()

    print("\n1 — the wedges and the glyph, in the timeline")
    binary, error = build_harness()
    if error:
        for name in ["the harness builds", "the wedges are inside the name strip",
                     "the arrival's wedge is as long as the arrival",
                     "the departure's wedge is as long as the departure",
                     "a `during` draws a glyph and no wedge",
                     "the glyph lies left of the label dot",
                     "…and gives way by at least 8 pt",
                     "a clip with no video draws no wedge and no glyph"]:
            failure(name, error)
        binary = None
    renders = {}
    if binary:
        for tag in ("wedges", "none", "during", "labelled", "labelled-none",
                    "silent", "silent-none", "zero-in", "zero-out", "zero-both",
                    "frame-in", "frame-out"):
            out, error = render(binary, fixtures[tag], os.path.join(CHROME, f"{tag}.png"))
            if error:
                failure(f"the {tag} fixture renders", error)
            else:
                renders[tag] = Image(out)

    if {"wedges", "none"} <= set(renders):
        scale = renders["none"].scale
        diff = changed_pixels(renders["none"], renders["wedges"])
        strip = Rect("the name strip", CLIP_X0, STRIP_Y, CLIP_X1 - CLIP_X0, STRIP_H)
        outside = [p for p in diff if not strip.contains(p[0], p[1], scale)]
        check("the two wedges are wholly inside the clip's name strip",
              bool(diff) and not outside,
              f"{len(diff)} changed pixels, {len(outside)} outside {strip}")
        boxes = clusters(diff)
        print(describe(boxes, scale))
        left = [points(b, scale) for b in boxes if b[0] / scale < (CLIP_X0 + CLIP_X1) / 2]
        right = [points(b, scale) for b in boxes if b[0] / scale >= (CLIP_X0 + CLIP_X1) / 2]
        wanted_in = CLIP_X0 + ZOOM * 1.0
        wanted_out = CLIP_X1 - ZOOM * 0.5
        check("the ARRIVAL's wedge runs from the clip's start to where the arrival ends",
              len(left) == 1 and abs(left[0][0] - CLIP_X0) <= 1
              and abs(left[0][2] - wanted_in) <= 1,
              f"{left} (wanted x {CLIP_X0}–{wanted_in:.0f} ± 1: 1 s × 168 pt ÷ 4 s)")
        check("…and the DEPARTURE's from where the departure begins to the clip's end",
              len(right) == 1 and abs(right[0][0] - wanted_out) <= 1
              and abs(right[0][2] - CLIP_X1) <= 1,
              f"{right} (wanted x {wanted_out:.0f}–{CLIP_X1} ± 1: 0.5 s × 168 pt ÷ 4 s)")
    else:
        check("the wedges are measured", False, "a render is missing")

    if {"none", "zero-in", "zero-out", "zero-both", "frame-in", "frame-out"} <= set(renders):
        for tag in ("zero-in", "zero-out", "zero-both"):
            changed = changed_pixels(renders["none"], renders[tag])
            check(f"{tag} draws no timeline wedge against the same plain card",
                  not changed, f"{len(changed)} changed pixels")
        strip = Rect("name strip", CLIP_X0, STRIP_Y, CLIP_X1 - CLIP_X0, STRIP_H)
        midpoint = (CLIP_X0 + CLIP_X1) / 2
        for tag, side in (("frame-in", "left"), ("frame-out", "right")):
            changed = changed_pixels(renders["none"], renders[tag])
            scale = renders[tag].scale
            ok = bool(changed) and all(strip.contains(x, y, scale) for x, y in changed)
            ok = ok and all((x / scale < midpoint) == (side == "left") for x, _ in changed)
            check(f"one-frame positive {side} edge draws its 2 pt minimum wedge",
                  ok, f"{len(changed)} changed pixels")

    if {"during", "none"} <= set(renders):
        scale = renders["none"].scale
        diff = changed_pixels(renders["none"], renders["during"])
        boxes = clusters(diff)
        print(describe(boxes, scale))
        check("a `during` draws ONE mark and not a wedge — it is continuous and has "
              "no length to show",
              len(boxes) == 1, f"{len(boxes)} clusters")
        if boxes:
            x0, y0, x1, y1 = points(boxes[0], scale)
            # The BOX is 11 pt (`TimelineClipDrawing.swift`); what is measured
            # is the SYMBOL drawn in it, whose antialiasing reaches a point and
            # a half past each edge — hence ± 3 rather than ± 1.
            check("…an 11 pt glyph at the strip's right end",
                  abs((x1 - x0) - GLYPH_W) <= 3 and abs(x1 - CLIP_X1) <= 6
                  and STRIP_Y - 1 <= y0 and y1 <= STRIP_Y + STRIP_H + 1,
                  f"x {x0:.1f}–{x1:.1f} ({x1 - x0:.1f} pt wide, the 11 pt box plus the "
                  f"symbol's antialiasing), y {y0:.1f}–{y1:.1f}")
        else:
            check("…an 11 pt glyph at the strip's right end", False, "nothing changed")

    # N·2: the glyph gives way to the LABEL dot, and it does so by carrying
    # what the dot branch decided rather than re-deriving it from `nameEnd`.
    # Measured as the same LABELLED card with and without a `during`, so the
    # dot is in both renders and the only pixels that differ are the glyph's.
    if {"labelled", "labelled-none", "during", "none"} <= set(renders):
        scale = renders["none"].scale
        plain_boxes = clusters(changed_pixels(renders["none"], renders["during"]))
        boxes = clusters(changed_pixels(renders["labelled-none"], renders["labelled"]))
        print(describe(boxes, scale))
        # The dot is 6 pt wide at the strip's right inset
        # (`TimelineClipDrawing.swift`: `strip.maxX - padding - 6`, padding 6).
        dot_left = CLIP_X1 - 12
        if len(boxes) == 1 and len(plain_boxes) == 1:
            _, _, x1, _ = points(boxes[0], scale)
            _, _, plain_x1, _ = points(plain_boxes[0], scale)
            check("on a LABELLED card the `during` glyph lies wholly LEFT of the "
                  "label dot's columns",
                  x1 <= dot_left,
                  f"the glyph's right edge is x {x1:.1f}, the dot's left edge "
                  f"x {dot_left} (the glyph's antialiasing included)")
            check("…and it gives way by at least 8 pt against where it sits with no "
                  "label",
                  plain_x1 - x1 >= 8,
                  f"x {x1:.1f} labelled against x {plain_x1:.1f} unlabelled "
                  f"({plain_x1 - x1:.1f} pt)")
        else:
            check("on a LABELLED card the `during` glyph lies wholly LEFT of the "
                  "label dot's columns", False,
                  f"{len(boxes)} labelled clusters, {len(plain_boxes)} plain")
            check("…and it gives way by at least 8 pt against where it sits with no "
                  "label", False, "no single cluster to measure")

    # The GATE. `hasPixels` is what the section and Clip ▸ Motion gate on, and
    # the strip has to gate on the same thing: a detached audio twin clones the
    # video props, motion included, and must not claim a motion it never shows.
    if {"silent", "silent-none"} <= set(renders):
        diff = changed_pixels(renders["silent-none"], renders["silent"])
        check("a clip whose media has NO video draws no wedge and no glyph, "
              "whatever its props say — the strip gates on `hasPixels`",
              not diff,
              "byte-identical to the same clip with no motion" if not diff
              else f"{len(diff)} changed pixels: "
                   f"{describe(clusters(diff), renders['silent-none'].scale)}")

    print("\n2 — the Motion section, open")
    if binary:
        shut, error = render(binary, fixtures["wedges"], os.path.join(CHROME, "shut.png"),
                             select=0, height=SECTION_HEIGHT, sub_tab="clip")
        opened, error2 = render(binary, fixtures["wedges"],
                                os.path.join(CHROME, "open.png"),
                                expand="video.motion", select=0, height=SECTION_HEIGHT,
                                sub_tab="clip")
        if error or error2:
            failure("the Motion section opens", error or error2)
        else:
            a, b = Image(shut), Image(opened)
            diff = changed_pixels(a, b)
            inspector = Rect(
                "the inspector column", INSPECTOR_X, 0, INSPECTOR_W, SECTION_HEIGHT)
            outside = [p for p in diff if not inspector.contains(p[0], p[1], a.scale)]
            check("opening the section changes only the inspector column",
                  bool(diff) and not outside,
                  f"{len(diff)} changed pixels, {len(outside)} outside {inspector}")
            ys = [y / a.scale for _, y in diff]
            height = max(ys) - min(ys)
            check("…and it opens a body at least seven rows deep, which is what the "
                  "section has",
                  height >= 7 * ROW_PITCH,
                  f"the changed pixels span {height:.1f} pt, from y {min(ys):.1f} "
                  f"(≥ 7 × {ROW_PITCH} = {7 * ROW_PITCH})")
        zero_shut, zero_error = render(
            binary, fixtures["zero-both"], os.path.join(CHROME, "zero-shut.png"),
            select=0, height=SECTION_HEIGHT, sub_tab="clip")
        zero_open, zero_error2 = render(
            binary, fixtures["zero-both"], os.path.join(CHROME, "zero-open.png"),
            expand="video.motion", select=0, height=SECTION_HEIGHT, sub_tab="clip")
        check("zero Motion section captures both collapsed summary and expanded recovery note",
              zero_error is None and zero_error2 is None
              and bool(changed_pixels(Image(zero_shut), Image(zero_open))) if zero_shut and zero_open else False,
              zero_error or zero_error2 or "both inspector renders captured")

    print("\n3 — the menu, the rows and two commands")
    probe_binary, error = build_probe()
    if error:
        for name in ["Clip ▸ Motion has three slots and a Preview",
                     "the In and Out submenus list every edge motion",
                     "the During submenu lists every continuous motion",
                     "a slot is enabled only when something is selected",
                     "the stored kind is the checked one",
                     "…and two clips that disagree check nothing",
                     "…while a slot they both leave empty still checks None",
                     "the section builds seven rows",
                     "Period is live for a pulse and dead for a drift",
                     "In Duration is dead when there is no arrival",
                     "During ▸ None clears the during and keeps the arrival",
                     "the section's popup writes the BASE motion inside an action"]:
            failure(name, error)
        return

    slot_selectors = [
        {"selector": "setMotionIn:", "tag": tag} for tag in (5, -1, STRANGER_TAG)
    ] + [
        {"selector": "setMotionOut:", "tag": -1},
        {"selector": "setMotionDuring:", "tag": -1},
        {"selector": "previewClipMotion:", "tag": 0},
    ]
    request = {
        "validate": [
            {"name": "one card", "package": fixtures["one"], "select": [0],
             "selectors": slot_selectors},
            {"name": "nothing selected", "package": fixtures["one"], "select": [],
             "selectors": slot_selectors},
            {"name": "two that disagree", "package": fixtures["two"], "select": [0, 1],
             "selectors": slot_selectors},
            # A card whose In slot is EMPTY, which is the only fixture where
            # the two readings of a stranger tag differ: None checks `on`
            # here, so a tag read AS None would check `on` too.
            {"name": "no arrival", "package": fixtures["none"], "select": [0],
             "selectors": slot_selectors},
        ],
        "rows": [
            {"name": "pulse", "package": fixtures["pulse"], "select": [0]},
            {"name": "drift", "package": fixtures["drift"], "select": [0]},
            # A clip with an ARRIVAL and no `during` at all: the dead case
            # the Amount row below claims.
            {"name": "one", "package": fixtures["one"], "select": [0]},
        ],
        "clearPackage": fixtures["pulse"],
        "insideAction": {"package": fixtures["action"], "playhead": TICKS // 2, "tag": 2},
        "strangerPackage": fixtures["one"],
        "strangerTag": STRANGER_TAG,
        "notePackage": fixtures["one"],
        "perClipPackage": fixtures["two"],
        # N·1's extremes: the write half on the card whose In is SET, the
        # validator half on the card whose In is EMPTY. The tags themselves
        # are in the probe's source.
        "extremes": {"writePackage": fixtures["one"],
                     "validatePackage": fixtures["none"]},
        "zeroPackage": fixtures["zero-both"],
        "zeroMixed": fixtures["zero-mixed"],
        "zeroDifferent": fixtures["zero-different"],
        "zeroAction": fixtures["zero-action"],
    }
    answer, error = run_probe(probe_binary, request)
    if error:
        failure("the probe runs", error)
        return

    top = submenu(answer["menu"], "Clip", "Motion")
    if top is None:
        failure("Clip ▸ Motion exists", "no such submenu in the menu dump")
        return
    names = [i["title"] for i in top]
    check("Clip ▸ Motion holds the three slots and a Preview",
          names == ["In", "Out", "During", "", "Preview"],
          f"{names}")
    edges = answer["edges"]
    durings = answer["durings"]
    for title, wanted in [("In", edges), ("Out", edges), ("During", durings)]:
        items = submenu(answer["menu"], "Clip", "Motion", title)
        titles = [i["title"] for i in items if not i["separator"]]
        tags = [i["tag"] for i in items if not i["separator"]]
        check(f"Clip ▸ Motion ▸ {title} lists every kind the model has, then None",
              titles == wanted + ["None"] and tags == list(range(len(wanted))) + [-1],
              f"{len(titles)} items {titles}; tags {tags}")

    by_name = {v["name"]: {(e["selector"], e["tag"]): e for e in v["entries"]}
               for v in answer["validation"]}
    one = by_name["one card"]
    empty = by_name["nothing selected"]
    two = by_name["two that disagree"]
    check("every slot is enabled with a drawing clip selected",
          all(e["enabled"] for e in one.values()),
          str({k: v["enabled"] for k, v in one.items()}))
    check("…and every one is dead with nothing selected",
          not any(e["enabled"] for e in empty.values()),
          str({k: v["enabled"] for k, v in empty.items()}))
    check("the stored kind is the checked one, and the empty slots check None",
          one[("setMotionIn:", 5)]["state"] == "on"
          and one[("setMotionIn:", -1)]["state"] == "off"
          and one[("setMotionOut:", -1)]["state"] == "on"
          and one[("setMotionDuring:", -1)]["state"] == "on",
          str({f"{k[0]}{k[1]}": v["state"] for k, v in one.items()}))
    # The two cards disagree about their ARRIVAL and agree about the other
    # two slots, so the rule shows on both sides in one fixture: a slot they
    # disagree on checks nothing at all — not the kind, and not None — while a
    # slot they both leave empty still checks None (`sharedMotionKind`).
    check("…two clips that disagree check NOTHING in that slot, not even None",
          two[("setMotionIn:", 5)]["state"] == "off"
          and two[("setMotionIn:", -1)]["state"] == "off",
          str({f"{k[0]}{k[1]}": v["state"] for k, v in two.items()}))
    check("…while a slot they both leave empty still checks None",
          two[("setMotionOut:", -1)]["state"] == "on"
          and two[("setMotionDuring:", -1)]["state"] == "on",
          str({f"{k[0]}{k[1]}": v["state"] for k, v in two.items()}))
    # N·1, the VALIDATOR half. On a card whose In is EMPTY, None checks
    # `on`; a tag no builder writes must check NOTHING, where the unfixed
    # build read every negative tag as None and checked it `on` too.
    none = by_name["no arrival"]
    check(f"a menu tag no builder writes ({STRANGER_TAG}) checks nothing, where None "
          "checks on — an empty slot is the only fixture where the two differ",
          none[("setMotionIn:", -1)]["state"] == "on"
          and none[("setMotionIn:", STRANGER_TAG)]["state"] == "off",
          str({f"{k[0]}{k[1]}": v["state"] for k, v in none.items()}))

    pulse = motion_section(answer["rows"]["pulse"])
    drift = motion_section(answer["rows"]["drift"])
    plain = motion_section(answer["rows"]["one"])
    check("the section builds In, In Duration, Out, Out Duration, During, Amount "
          "and Period, in that order",
          pulse is not None and drift is not None and plain is not None,
          "found" if pulse and drift and plain
          else f"pulse {bool(pulse)}, drift {bool(drift)}, plain {bool(plain)}")
    if pulse and drift and plain:
        def alpha(pane, label):
            return next(r["alpha"] for r in pane["rows"] if r["label"] == label)
        check("Period is live for a `pulse` and dead for a `drift`, which ignores it",
              alpha(pulse, "Period") == 1 and alpha(drift, "Period") < 1,
              f"pulse {alpha(pulse, 'Period')}, drift {alpha(drift, 'Period')}")
        check("In Duration is dead when there is no arrival to measure",
              alpha(pulse, "In Duration") == 1 and alpha(drift, "In Duration") < 1,
              f"with an arrival {alpha(pulse, 'In Duration')}, without "
              f"{alpha(drift, 'In Duration')}")
        check("…and so is Amount, where there is no `during`",
              alpha(pulse, "Amount") == 1 and alpha(plain, "Amount") < 1,
              f"with a during {alpha(pulse, 'Amount')}, without "
              f"{alpha(plain, 'Amount')}")

    cleared = json.loads(answer["cleared"])["clips"][0]["video"]["motion"]
    check("During ▸ None clears the during and LEAVES the arrival where it was — "
          "a motion patch replaces the whole object, so the command must carry the "
          "other two slots",
          cleared is not None and cleared["during"] is None
          and (cleared["in"] or {}).get("kind") == "fade",
          str(cleared))

    inside = answer["insideAction"]
    project_after = json.loads(inside["project"])["clips"][0]
    check("the section's In popup can be driven at all",
          inside["picked"] is True, str(inside["picked"]))
    check("…and with the playhead inside an ACTION it writes the clip's BASE motion",
          (project_after["video"]["motion"] or {}).get("in", {}).get("kind") == "zoom_in"
          and inside.get("playhead") == TICKS // 2,
          f"playhead {inside.get('playhead')}; {project_after['video']['motion']}")
    check("…leaving the action's own end patch with no motion in it at all",
          all("motion" not in (a["end"].get("video") or {})
              for a in project_after["actions"]),
          str([a["end"] for a in project_after["actions"]]))

    # N·1, the WRITE half. The fixture's In is SET (`slide_up`, 0.5 s): the
    # unfixed build answered nil for tag −7 and CLEARED it. On a clip with no
    # In the same call is nil over nil, which `applying` answers `.identity`
    # for — the bytes would match either way, so that fixture is not the row.
    stranger = answer["stranger"]
    check(f"a menu tag no builder writes ({STRANGER_TAG}) writes NOTHING — the "
          "project is byte-identical, where reading it as None would have cleared "
          "the clip's arrival",
          stranger["before"] == stranger["after"],
          "byte-identical" if stranger["before"] == stranger["after"]
          else f"motion went from "
               f"{json.loads(stranger['before'])['clips'][0]['video']['motion']} to "
               f"{json.loads(stranger['after'])['clips'][0]['video']['motion']}")

    # N·1's EXTREMES, which §12 checked by INSPECTION and recorded as owing a
    # row. `Int.min`, `Int.max`, `count` and `count + 1` are the four tags
    # that break a gate written as "negative means None" or as "≤ count";
    # tag 0 on the same clip is the positive control, without which a gate
    # that refused everything would pass all four.
    extremes = answer["extremes"]
    writes = {w["name"]: w for w in extremes["writes"]}
    strangers = ("Int.min", "Int.max", "count", "count+1")

    def in_kind(blob):
        motion = json.loads(blob)["clips"][0]["video"]["motion"] or {}
        return ((motion.get("in") or {}).get("kind"), motion.get("out"),
                motion.get("during"))

    quiet = [n for n in strangers if writes[n]["before"] == writes[n]["after"]]
    zero = writes["0"]
    before_kind, _, _ = in_kind(zero["before"])
    after_kind, after_out, after_during = in_kind(zero["after"])
    control = (before_kind == "slide_up" and after_kind == "fade"
               and after_out is None and after_during is None)
    check(f"the four extreme tags (count is {extremes['count']}) write NOTHING, and "
          "tag 0 on the same clip writes its kind — the control that says the gate "
          "is not refusing everything",
          len(quiet) == 4 and control,
          "; ".join(
              f"{w['name']}: " + ("no write" if w["before"] == w["after"]
                                  else f"in {in_kind(w['before'])[0]} → "
                                       f"{in_kind(w['after'])[0]}")
              for w in extremes["writes"]))

    # The same five through the VALIDATOR, on the card whose In is empty,
    # with None as the control: a tag no builder writes checks NOTHING, where
    # a gate that read it as None would check it `on` exactly as −1 is.
    validates = {v["name"]: v for v in extremes["validates"]}
    check("…and none of the five checks anything in the menu, where None (−1) "
          "checks on",
          validates["-1"]["state"] == "on"
          and all(validates[n]["state"] == "off" for n in strangers + ("0",)),
          "; ".join(f"{v['name']}: {v['state']}"
                  + ("" if v["enabled"] else " (disabled)")
                  for v in extremes["validates"]))

    trail = answer["zeroTrail"]
    zero, positive, undone, removed, disabled = trail["steps"]
    check("zero In and Out keep checked Fade kinds with explicit inactive menu titles",
          zero["fade"]["title"] == "Fade (inactive)"
          and zero["fade"]["state"] == "on"
          and zero["out"]["title"] == "Fade (inactive)"
          and zero["out"]["state"] == "on"
          and zero["none"]["state"] == "off")
    note = zero["note"]
    check("the selected zero edges show a visible wrapping recovery note and editable 0 s",
          note["found"] and not note["hidden"]
          and "In and Out" in note["text"]
          and "Increase Duration" in note["text"]
          and "None" in note["text"]
          and note["duration"].startswith("0.00")
          and note["durationAlpha"] == 1,
          str(note))
    check("the wrapping inactive note fits its height and clears the In row",
          note["height"] >= note["intrinsic"] - 1
          and note["height"] > 20 and note["width"] <= INSPECTOR_W
          and note["clearance"] >= 0,
          str(note))
    first_motion = json.loads(trail["before"])["clips"][0]["video"]["motion"]
    positive_motion = json.loads(positive["project"])["clips"][0]["video"]["motion"]
    check("the actual quick-duration pick reactivates In and preserves zero Out",
          positive_motion["in"]["kind"] == "fade"
          and positive_motion["in"]["duration"] == 160_000
          and positive_motion["out"] == first_motion["out"]
          and positive["fade"]["title"] == "Fade"
          and positive["out"]["title"] == "Fade (inactive)"
          and positive["note"]["text"].find("Out") >= 0)
    check("one undo restores zero In and its note and menu title",
          json.loads(undone["project"])["clips"][0]["video"]["motion"] == first_motion
          and undone["fade"]["title"] == "Fade (inactive)"
          and not undone["note"]["hidden"])
    removed_motion = json.loads(removed["project"])["clips"][0]["video"]["motion"]
    check("the actual In popup None clears only In; reused menu item loses stale suffix",
          removed_motion["in"] is None and removed_motion["out"] == first_motion["out"]
          and removed["fade"]["title"] == "Fade"
          and removed["none"]["state"] == "on")
    check("no selection disables the reused menu item and keeps its plain title",
          disabled["fade"]["title"] == "Fade" and not disabled["fade"]["enabled"])
    mixed = answer["zeroSelections"]["zeroMixed"]
    different = answer["zeroSelections"]["zeroDifferent"]
    check("same-kind mixed activity checks Fade and says some inactive",
          mixed["menu"]["title"] == "Fade (some inactive)"
          and mixed["menu"]["state"] == "on"
          and "In" in mixed["note"]["text"])
    check("different-kind selection checks nothing but discloses its inactive In",
          different["menu"]["state"] == "off"
          and different["menu"]["title"] == "Fade (inactive)"
          and "In" in different["note"]["text"])
    action = answer["zeroAction"]
    action_clip = json.loads(action["project"])["clips"][0]
    # Road map 9's phase 3a (2026-09-23) replaced Motion presets' own note
    # with the section's ⊘ note, which says the same: edits land on the clip.
    check("zero In inside an action keeps the base-props note and writes base Duration",
          any("Actions don't animate this" in text for text in action["notes"])
          and not action["inactive"]["hidden"]
          and action_clip["video"]["motion"]["in"]["duration"] == 160_000
          and all("motion" not in a["end"].get("video", {}) for a in action_clip["actions"]))
    remove = answer["zeroRemove"]
    menu_motion = json.loads(remove["afterMenu"])["clips"][0]["video"]["motion"]
    reset_motion = json.loads(remove["afterReset"])["clips"][0]["video"]["motion"]
    check("menu None clears only Out; Reset removes the last configured edge",
          menu_motion["out"] is None and menu_motion["in"] == first_motion["in"]
          and remove["resetFound"] and reset_motion is None
          and remove["note"]["hidden"])

    # N·3. The band's second pill is about the CLIP's `during`, not about
    # the moment the mode was armed.
    note = answer["note"]
    if not note["armed"]:
        print("  note: the zoom region mode could not be armed in the harness "
              "(regionTarget needs previewCanvas.box(for:)), so the note's two "
              "claims are UNREACHED here — road map 5 §12, N·3")
    else:
        trail = note["trail"]
        check("the zoom band's note is nil on a clip with no `during`, and APPEARS "
              "when one is added while the band is armed",
              len(trail) >= 2 and trail[0] == "" and trail[1] == note["expected"],
              f"{trail[:2]}")
        check("…and goes again when the `during` is cleared, the band never "
              "having been re-armed",
              len(trail) >= 3 and trail[1] == note["expected"] and trail[2] == "",
              f"{trail}")

    # One op PER CLIP, and one undo step. The two cards disagree about their
    # arrival, so a batch that sent one op over every id would leave them both
    # carrying the LAST clip's whole motion object.
    per = answer["perClip"]
    after = json.loads(per["after"])["clips"]
    arrivals = [(c["video"]["motion"] or {}).get("in", {}).get("kind") for c in after]
    durings = [(c["video"]["motion"] or {}).get("during", {}).get("kind")
               for c in after]
    check("During ▸ * over TWO clips writes one op PER CLIP: each keeps its own "
          "arrival while both gain the during",
          arrivals == ["slide_up", "fade"] and durings == ["pulse", "pulse"],
          f"arrivals {arrivals}, durings {durings}")
    check("…and the whole batch is ONE undo step, which puts `project.json` back "
          "byte for byte",
          per["undone"] == per["before"] and per["after"] != per["before"],
          f"undo name {per['name']!r}; restored "
          f"{per['undone'] == per['before']}, and the write did change it "
          f"{per['after'] != per['before']}")

    if WARNINGS:
        print("\nharness warnings (a render that never settled):")
        for line in WARNINGS:
            print(f"  - {line}")


if __name__ == "__main__":
    try:
        main()
    finally:
        passed = sum(1 for r in RESULTS if r)
        print()
        print(f"{passed}/{len(RESULTS)} checks passed")
        if passed != len(RESULTS):
            sys.exit(1)
