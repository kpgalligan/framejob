"""Road map 5, E2 — the Motion section, the Clip ▸ Motion menu and the
timeline's wedges, offscreen.

    python3 tools/proof/e2_chrome.py

Two instruments, neither of which is a photograph of a running app:

* **the harness** (`tools/proof/harness/`) compiles every file in
  `app/Sources` with a `main.swift` of its own, opens a `.reelcut` package,
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
# photographs. The INSPECTOR renders are taller: Motion is the tenth section
# in a shape clip's stack and its header is below the fold at 862, so opening
# it would change no visible pixel at all (measured). Recorded as a deviation.
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
         duration=CLIP_SECONDS * TICKS):
    return {
        "id": cid, "track": 1, "start": start, "duration": duration,
        "source": {"kind": "shape"},
        "enabled": {"video": True, "audio": True}, "speed": 1.0,
        "video": video_props(motion_value), "audio": None, "text": None,
        "shape": shape_props(fill), "actions": actions or [], "transition_in": None,
        "name": name, "label": None,
    }


def project(clips):
    return {
        "version": 8,
        "canvas": {
            "width": 1920, "height": 1080, "fps": [30, 1], "background": BLACK,
            "fit_new_clips": True, "timecode_frames": True,
        },
        "media": [],
        "tracks": [{"id": 1, "name": "Track 1", "hidden": False, "muted": False,
                    "locked": False, "solo": False}],
        "clips": clips,
        "markers": [],
        # Ids are unique across the WHOLE project — `next_id` is one counter —
        # so an ACTION's id counts too.
        "next_id": max([c["id"] for c in clips]
                       + [a["id"] for c in clips for a in c["actions"]] + [1]) + 1,
        "nests": [],
    }


def write_package(name, body):
    path = os.path.join(CHROME, name + ".reelcut")
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "project.json"), "w", encoding="utf-8") as handle:
        json.dump(body, handle, indent=2)
        handle.write("\n")
    return path


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


def render(binary, package, out, expand="-", select=-1, height=HEIGHT):
    args = [binary, package, out, "light", str(WIDTH), str(height), str(select),
            "0", "1", "clip", "-", expand]
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
        from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
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
/// section's `id` is private, so a section is named by WHERE it is and by
/// what it holds.
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
    return (document,
            document.windowControllers.first!.contentViewController as! EditorViewController)
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
    answer["insideAction"] = ["picked": picked, "project": document.project.json]
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
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    print(f"probe: {binary} (built in {time.time() - start:.1f} s)")
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
    """The section that holds the Motion run — named by what it holds, since
    `InspectorSection.id` is private."""
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
                     "a `during` draws a glyph and no wedge"]:
            failure(name, error)
        binary = None
    renders = {}
    if binary:
        for tag in ("wedges", "none", "during"):
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

    print("\n2 — the Motion section, open")
    if binary:
        shut, error = render(binary, fixtures["wedges"], os.path.join(CHROME, "shut.png"),
                             select=0, height=SECTION_HEIGHT)
        opened, error2 = render(binary, fixtures["wedges"],
                                os.path.join(CHROME, "open.png"),
                                expand="video.motion", select=0, height=SECTION_HEIGHT)
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
        {"selector": "setMotionIn:", "tag": tag} for tag in (5, -1)
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
          (project_after["video"]["motion"] or {}).get("in", {}).get("kind") == "zoom_in",
          str(project_after["video"]["motion"]))
    check("…leaving the action's own end patch with no motion in it at all",
          all("motion" not in (a["end"].get("video") or {})
              for a in project_after["actions"]),
          str([a["end"] for a in project_after["actions"]]))

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
