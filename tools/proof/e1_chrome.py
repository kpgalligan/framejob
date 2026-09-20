"""Road map 5, E1 — the Transition section and the Clip ▸ Transition menu,
offscreen.

    python3 tools/proof/e1_chrome.py [--reference DIR]

Two instruments, neither of which is a photograph of a running app:

* **the harness** (`tools/proof/harness/`) compiles every file in
  `app/Sources` with a `main.swift` of its own, opens a `.reelcut` package,
  puts an `EditorViewController` in an `NSWindow` and `cacheDisplay`s it into
  a PNG — the same paint path the window uses, no TCC grant. It is run on
  THIS tree and on the REFERENCE tree (`1c3e92e`, the commit before E1's
  first toll, extracted and built under `tools/proof/work/e1-reference`), so
  what the section GAINED is a difference between two photographs rather than
  a number read off a layout constant.
* **a probe** compiled from `app/Sources` over `harness/build.sh`'s own
  `swiftc` line, for the things no photograph can answer: a menu's items and
  tags, a validator's answers, a checkmark, the row labels a section builds,
  and what a menu command does to a selection of two clips. A probe that will
  not build is a scored FAILURE and never an exit, so a rotted instrument
  cannot take the score down with it.

**The fixture is a version-6 package both trees can open.** The reference
build's format version is SIX and the core refuses a file from the future, so
the render fixture is hand-written: two cards with a two-second overlap and a
bare `{"kind": "wipe"}` on the later one, which is exactly what a project
saved by last month's build holds.

**What the section gained, and how it is measured.** E1 put a Curve popup and
a Crossfade Audio checkbox into the Transition section, so its open body is
two rows taller: 2 × 29 pt, `DS.controlHeight` + `InspectorMetrics.rowSpacing`
(`app/Sources/Theme.swift`, `InspectorPane.swift`). The measurement is the
vertical EXTENT of the pixels that differ between the shut render and the
open one, on each tree, and the claim is the DIFFERENCE of the two extents.
The difference is what makes it a measurement: the extent includes the
header's own disclosure triangle and the body's top and bottom insets, and
every one of those is the same in both trees, so they cancel. (The
`shift_match` a phase-6-shaped measurement would use does not apply here: the
Transition section is the LAST one in a shape clip's stack — the audio group
below it is empty — so opening it moves nothing, and there is no shift to
find. Recorded as a deviation.)
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
CHROME = os.path.join(WORK, "chrome-e1")
BUILD = os.path.join(HERE, "harness", "build.sh")
PROBE = os.path.join(WORK, "e1probe")
REFERENCE = os.path.join(WORK, "e1-reference")

WIDTH = 1440
# Tall enough that the Transition section's open body — the last section in a
# shape clip's stack — is wholly inside the pane on BOTH trees, and that the
# reference tree's shorter stack (it has no Motion section) still puts the
# section in the same scroll position rather than relaying the panel out.
HEIGHT = 1600

TICKS = 600_000
ROW_PITCH = 29           # DS.controlHeight (22) + InspectorMetrics.rowSpacing (7)
GAINED_ROWS = 2          # Curve, Crossfade Audio
EXTENT_SLOP = 4

BLACK = [0.0, 0.0, 0.0, 1.0]

RESULTS = []
WARNINGS = []


def check(name, ok, detail=""):
    RESULTS.append(bool(ok))
    print(f"  {'PASS' if ok else 'FAIL'}: {name}")
    if detail:
        print(detail if detail.startswith("      ") else "      " + detail)


def failure(name, why):
    """An instrument that would not build or run — scored, never an exit."""
    check(name, False, why)


# ---------------------------------------------------------------------------
# The fixtures, hand-written.


def video_props():
    """`VideoProps` in the core's field order (`model_props.rs`). `motion` is
    omitted deliberately: the struct carries `#[serde(default)]`, so a file
    without the key reads `null` at either version, and a version-6 file may
    not carry it at all."""
    return {
        "x": 0.0, "y": 0.0, "scale": 1.0, "rotation": 0.0, "opacity": 1.0,
        "crop": {"l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0},
        "corner_radius": 0.0, "shadow": None,
        "color": {"brightness": 0.0, "contrast": 0.0, "saturation": 0.0, "hue": 0.0},
        "chroma": None, "filters": [], "reflection": None, "spotlight": None,
        "obscure": [], "blend": "normal",
    }


def shape_props(fill):
    return {
        "kind": "rectangle", "width": 640.0, "height": 360.0, "stroke": None,
        "fill": fill, "arrow_start": False, "arrow_end": False, "radius": 0.0,
        "from": [0.0, 1.0], "to": [1.0, 0.0], "gradient": None,
    }


def clip(cid, track, start, duration, fill, transition=None):
    return {
        "id": cid, "track": track, "start": start, "duration": duration,
        "source": {"kind": "shape"},
        "enabled": {"video": True, "audio": True}, "speed": 1.0,
        "video": video_props(), "audio": None, "text": None,
        "shape": shape_props(fill), "actions": [], "transition_in": transition,
        "name": None, "label": None,
    }


def project(version, clips):
    return {
        "version": version,
        "canvas": {
            "width": 1920, "height": 1080, "fps": [30, 1], "background": BLACK,
            "fit_new_clips": True, "timecode_frames": True,
        },
        "media": [],
        "tracks": [{"id": 1, "name": "Track 1", "hidden": False, "muted": False,
                    "locked": False, "solo": False}],
        "clips": clips,
        "markers": [],
        "next_id": max(c["id"] for c in clips) + 1,
        "nests": [],
    }


def write_package(name, body):
    path = os.path.join(CHROME, name + ".reelcut")
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "project.json"), "w", encoding="utf-8") as handle:
        json.dump(body, handle, indent=2)
        handle.write("\n")
    return path


def pair_package():
    """The render fixture: A `[0, 5)` and B `[3, 8)` on one track, a two-second
    overlap, and the version-6 spelling of a transition — a bare kind, with no
    `curve` and no `audio` because neither key existed."""
    return write_package("v6-pair", project(6, [
        clip(2, 1, 0, 5 * TICKS, [0.75, 0.75, 0.75, 1.0]),
        clip(3, 1, 3 * TICKS, 5 * TICKS, [0.25, 0.25, 0.25, 1.0], {"kind": "wipe"}),
    ]))


def menu_package():
    """The probe fixture, one clip of each PLACEMENT: A first on its track, B
    at a hard cut after it, C after a gap, and D overlapping C with a stored
    `push_left`."""
    return write_package("e1-menu", project(8, [
        clip(2, 1, 0, 2 * TICKS, [0.8, 0.8, 0.8, 1.0]),
        clip(3, 1, 2 * TICKS, 2 * TICKS, [0.6, 0.6, 0.6, 1.0]),
        clip(4, 1, 5 * TICKS, 2 * TICKS, [0.4, 0.4, 0.4, 1.0]),
        clip(5, 1, 6 * TICKS, 2 * TICKS, [0.2, 0.2, 0.2, 1.0],
             {"kind": "push_left", "curve": "linear", "audio": False}),
    ]))


# ---------------------------------------------------------------------------
# PNG, in pure Python (phase4_chrome.py's, unchanged — every chrome script
# carries its own copy so one can be run without the others).


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
    """Bounding boxes of changed pixels grouped within `cell` px of each
    other."""
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


def extent(pixels, scale):
    """(top, bottom) of a changed set in POINTS, or (None, None) when empty.

    Never a `guard` at a call site: a check that quietly disappears when its
    diff comes back empty is a check that cannot fail."""
    if not pixels:
        return None, None
    ys = [y for _, y in pixels]
    return min(ys) / scale, (max(ys) + 1) / scale


# ---------------------------------------------------------------------------
# The two harnesses.


def build_harness(build_script, label):
    start = time.time()
    result = subprocess.run([build_script], capture_output=True, text=True)
    if result.returncode != 0:
        return None, (result.stdout + result.stderr).strip()[-400:]
    binary = result.stdout.strip().splitlines()[-1]
    built = "built" in result.stderr
    print(f"harness ({label}): {binary} "
          f"({'built in %.1f s' % (time.time() - start) if built else 'up to date'})")
    return binary, None


def render(binary, package, out, expand="-", select=1):
    """One render, with the harness's arguments in the order every earlier
    chrome script depends on — and the order the REFERENCE harness takes too
    (`expandSections` is `arguments[11]` in both)."""
    args = [binary, package, out, "light", str(WIDTH), str(HEIGHT), str(select),
            "0", "1", "clip", "-", expand]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stdout + result.stderr).strip()[-400:]
    if result.stderr.strip():
        WARNINGS.append(f"{os.path.basename(out)}: {result.stderr.strip()}")
    return out, None


def body_extent(binary, package, tag):
    """How far the pixels that OPENING the section changes reach, in points.

    The extent and not a shift: the section is the last one in the stack, so
    nothing below it moves (see the module doc). It is only ever read as a
    difference between two trees, where the header's triangle and the body's
    insets cancel."""
    shut, error = render(binary, package, os.path.join(CHROME, f"{tag}-shut.png"))
    if error:
        return None, error, None
    opened, error = render(binary, package, os.path.join(CHROME, f"{tag}-open.png"),
                           expand="video.transition")
    if error:
        return None, error, None
    a, b = Image(shut), Image(opened)
    diff = changed_pixels(a, b)
    top, bottom = extent(diff, a.scale)
    if top is None:
        return None, "opening the section changed no pixel at all", None
    return bottom - top, None, (diff, a.scale)


# ---------------------------------------------------------------------------
# The probe.

PROBE_SOURCE = r'''// Written by tools/proof/e1_chrome.py. See that file's header.
import AppKit

/// `ProjectDocument.read(from:ofType:)` needs a document controller to exist
/// before a window controller is made — `transition_sheet_probe.py`'s shape.
final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()

let request = try! JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
// The one call that builds the menu: `buildMainMenu()` is private and its
// only caller is the launch notification, which the harness never sends.
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

/// The control a row's label belongs to: the first `OptionControl` or
/// `NSControl` sibling AFTER the label in the row's stack, with the alpha the
/// inspector composites it at — 1 when the row is live, 0.42 when it is not
/// (`OptionControls.swift`). Nothing `private` is widened for this: a
/// control's own `isActive` is private and `alphaValue` is the public
/// signal it sets.
func controlAfter(_ label: InspectorRowLabel) -> [String: Any] {
    guard let parent = label.superview,
          let index = parent.subviews.firstIndex(of: label) else { return [:] }
    for view in parent.subviews[(index + 1)...] {
        if view is OptionControl || view is NSControl {
            return ["control": String(describing: type(of: view)),
                    "alpha": Double(view.alphaValue)]
        }
    }
    return [:]
}

/// Every `InspectorSection` in tree order, with the rows inside it. The
/// section's own id is `private`, so a section is named by WHERE it is and
/// by what it holds — which is all any of these rows needs.
func sections(_ root: NSView) -> [[String: Any]] {
    walk(root).compactMap { view -> [String: Any]? in
        guard let section = view as? InspectorSection else { return nil }
        let inside = walk(section)
        let labels = inside.compactMap { $0 as? InspectorRowLabel }
        return [
            "labels": labels.map { $0.stringValue },
            "rows": labels.map { label -> [String: Any] in
                var row = controlAfter(label)
                row["label"] = label.stringValue
                return row
            },
            "checkboxes": inside.filter { $0 is OptionCheckboxControl }.count,
            "popups": inside.filter { $0 is OptionPopupControl }.count,
            "expanded": section.isExpanded,
        ]
    }
}

func placement(_ document: ProjectDocument) -> [[String: Any]] {
    ordered(document).map {
        ["id": Int($0.id), "start": $0.start, "end": $0.end,
         "kind": $0.transitionIn?.kind.rawValue ?? NSNull()]
    }
}

func state(_ value: NSControl.StateValue) -> String {
    value == .on ? "on" : (value == .mixed ? "mixed" : "off")
}

var answer: [String: Any] = [
    "menu": ["title": NSApp.mainMenu?.title ?? "",
             "items": (NSApp.mainMenu?.items ?? []).map(dump)],
    "kinds": TransitionKind.allCases.map(\.displayName),
]

// ---- validation: a selector, a TAG, and the state the validator set -------
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

// ---- the section's rows, read off a real editor in a real window ----------
if let rows = request["rows"] as? [String: Any] {
    let document = opened(rows["package"] as! String)
    select(document, rows["select"] as? [Int] ?? [])
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.2)
    let controller =
        document.windowControllers.first!.contentViewController as! EditorViewController
    answer["rows"] = walk(controller.view).compactMap {
        ($0 as? InspectorRowLabel)?.stringValue
    }
    answer["sections"] = sections(controller.view)
}

// ---- the menu command over a selection of two ----------------------------
if let batch = request["batch"] as? [String: Any] {
    let document = opened(batch["package"] as! String)
    select(document, batch["select"] as? [Int] ?? [])
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.2)
    let controller =
        document.windowControllers.first!.contentViewController as! EditorViewController
    let before = placement(document)
    let item = NSMenuItem(
        title: "", action: #selector(EditorViewController.setTransitionKind(_:)),
        keyEquivalent: "")
    item.tag = batch["tag"] as! Int
    controller.setTransitionKind(item)
    spin(0.8)
    answer["batch"] = [
        "before": before, "after": placement(document),
        "sheet": controller.view.window?.attachedSheet != nil,
        "undoName": document.undoManager?.undoActionName ?? "",
    ]
}

try! JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
    .write(to: out)
exit(0)
'''


def build_probe():
    """Compile the probe if it is stale, exactly as `harness/build.sh` does —
    the same swiftc line, the same staleness rule. Returns `(binary, None)` or
    `(None, reason)`; the reason is SCORED and never exits."""
    os.makedirs(PROBE, exist_ok=True)
    binary = os.path.join(PROBE, "e1probe")
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
    """The submenu reached by walking `titles` from the main menu."""
    items = menu["items"]
    for title in titles:
        found = next((i for i in items if i["title"] == title), None)
        if found is None or "submenu" not in found:
            return None
        items = found["submenu"]["items"]
    return items


# ---------------------------------------------------------------------------


def main():
    reference_tree = REFERENCE
    if "--reference" in sys.argv:
        reference_tree = sys.argv[sys.argv.index("--reference") + 1]
    os.makedirs(CHROME, exist_ok=True)
    print("E1 chrome — the Transition section, against the build before E1")

    pair = pair_package()
    menu_fixture = menu_package()

    # ---- 1. the section's body, on two trees ----
    print("\n1 — the Curve and Crossfade Audio rows, as pixels")
    now_binary, error = build_harness(BUILD, "this tree")
    if error:
        failure("this tree's harness builds", error)
        now_extent = None
    else:
        now_extent, error, diff = body_extent(now_binary, pair, "now")
        if error:
            failure("this tree's Transition section opens", error)
        else:
            image_scale = diff[1]
            inspector = Rect("inspector", WIDTH - 304, 0, 304, HEIGHT)
            outside = [p for p in diff[0] if not inspector.contains(p[0], p[1], image_scale)]
            check("opening the section changes only the inspector column",
                  not outside,
                  f"{len(outside)} pixels outside {inspector}" if outside else str(inspector))
            print(f"      B_now = {now_extent:.1f} pt")
            print(describe(clusters(diff[0]), image_scale))

    reference_build = os.path.join(reference_tree, "tools", "proof", "harness", "build.sh")
    if not os.path.exists(reference_build):
        check(f"the reference tree is built at {reference_tree}", False,
              "no harness build script there — "
              "`git archive 1c3e92e | tar -x -C tools/proof/work/e1-reference` "
              "then `make app` in it")
        ref_extent = None
    else:
        ref_binary, error = build_harness(reference_build, "reference")
        if error:
            # A FAILURE and not a skip. CLAUDE.md's one exemption is for a
            # script that builds an OLD `app/Sources` against the CURRENT
            # core, which a header that has moved can make impossible; this
            # builds a whole tree against its OWN header and its own
            # staticlib, so nothing about it is out of reach and a build
            # that will not go is a real one.
            failure("the reference harness builds", error)
            ref_extent = None
        else:
            ref_extent, error, diff = body_extent(ref_binary, pair, "ref")
            if error:
                failure("the reference tree's Transition section opens", error)
            else:
                print(f"      B_ref = {ref_extent:.1f} pt")

    if now_extent is not None and ref_extent is not None:
        gained = now_extent - ref_extent
        check(f"the section's body is exactly {GAINED_ROWS} rows taller than it was",
              abs(gained - GAINED_ROWS * ROW_PITCH) <= EXTENT_SLOP,
              f"B_now − B_ref = {now_extent:.1f} − {ref_extent:.1f} = {gained:.1f} pt "
              f"(wanted {GAINED_ROWS} × {ROW_PITCH} = {GAINED_ROWS * ROW_PITCH} "
              f"± {EXTENT_SLOP}; the triangle and the insets cancel)")
    else:
        check("the two trees' section bodies are compared", False,
              "one of the two renders is missing")

    # ---- 2 and 3. the menu, the validator and the batch ----
    print("\n2 — the menu, the validator, the rows and the batch")
    binary, error = build_probe()
    if error:
        for name in ["Clip ▸ Transition lists every kind", "…with the three wipes last",
                     "…and None on its own, below a separator",
                     "a kind is enabled where there is somewhere to put one",
                     "…and disabled where there is not",
                     "None is enabled for every selection",
                     "the stored kind is the checked one",
                     "the section builds the four rows",
                     "the batch transitions the clip at the cut",
                     "…and skips the one at a gap"]:
            failure(name, error)
        return

    selectors = [{"selector": "setTransitionKind:", "tag": tag} for tag in (0, 3, -1)]
    request = {
        "validate": [
            {"name": name, "package": menu_fixture, "select": [index],
             "selectors": selectors}
            for name, index in [("A (first on its track)", 0), ("B (a hard cut)", 1),
                                ("C (after a gap)", 2), ("D (an overlap)", 3)]
        ],
        "rows": {"package": menu_fixture, "select": [3]},
        "batch": {"package": menu_fixture, "select": [1, 2], "tag": 0},
    }
    answer, error = run_probe(binary, request)
    if error:
        failure("the probe runs", error)
        return

    items = submenu(answer["menu"], "Clip", "Transition")
    if items is None:
        failure("Clip ▸ Transition exists", "no such submenu in the menu dump")
        return
    kinds = answer["kinds"]
    titles = [i["title"] for i in items if not i["separator"]]
    tags = [i["tag"] for i in items if not i["separator"]]
    check("Clip ▸ Transition lists every kind the model has, in order",
          titles == kinds + ["None"] and tags == list(range(len(kinds))) + [-1],
          f"{len(titles)} items: {titles[:3]} … {titles[-4:]}; tags {tags[:3]} … {tags[-4:]}")
    check("…with the three wipe directions last, at tags 10, 11 and 12",
          titles[10:13] == ["Wipe Left", "Wipe Up", "Wipe Down"]
          and tags[10:13] == [10, 11, 12],
          f"{titles[10:13]} at {tags[10:13]}")
    separators = [index for index, i in enumerate(items) if i["separator"]]
    check("…and None sits alone under a separator",
          separators == [len(items) - 2] and items[-1]["title"] == "None",
          f"separators at {separators} of {len(items)} items")

    by_name = {v["name"]: {(e["selector"], e["tag"]): e for e in v["entries"]}
               for v in answer["validation"]}
    enabled = {name: entries[("setTransitionKind:", 0)]["enabled"]
               for name, entries in by_name.items()}
    check("a KIND is enabled where there is somewhere to put one",
          enabled["B (a hard cut)"] and enabled["D (an overlap)"],
          f"B {enabled['B (a hard cut)']}, D {enabled['D (an overlap)']}")
    check("…and disabled where there is not",
          not enabled["A (first on its track)"] and not enabled["C (after a gap)"],
          f"A {enabled['A (first on its track)']}, C {enabled['C (after a gap)']}")
    none_enabled = {name: entries[("setTransitionKind:", -1)]["enabled"]
                    for name, entries in by_name.items()}
    check("None stays enabled for EVERY selection — a stored transition must "
          "always be clearable",
          all(none_enabled.values()), str(none_enabled))
    states = {name: entries[("setTransitionKind:", 3)]["state"]
              for name, entries in by_name.items()}
    check("the stored kind is the checked one, and only on the clip that stores it",
          states["D (an overlap)"] == "on"
          and all(v == "off" for k, v in states.items() if k != "D (an overlap)"),
          f"push_left (tag 3): {states}")

    # The Transition section is the LAST one a shape clip with an overlap
    # gets (the audio group below it is empty), so it is named by its place
    # and by what it holds — `InspectorSection.id` is private.
    #
    # **Crossfade Audio is a CHECKBOX row and carries no `InspectorRowLabel`
    # at all**: `inspectorCheckRow` passes `nil` for the label and the title
    # lives inside `OptionCheckboxControl`, which is private. So the row is
    # counted rather than read by name, and no private member is widened.
    # Recorded as a deviation.
    panes = answer.get("sections", [])
    last = panes[-1] if panes else {}
    check("the Transition section builds Kind, Curve and Duration, in that order",
          last.get("labels") == ["Kind", "Curve", "Duration"],
          f"the last of {len(panes)} sections holds {last.get('labels')}")
    check("…and one Crossfade Audio CHECKBOX between Curve and Duration, which "
          "carries its own title and so no row label",
          last.get("checkboxes") == 1 and last.get("popups") == 2,
          f"{last.get('checkboxes')} checkboxes, {last.get('popups')} popups")

    batch = answer.get("batch", {})
    before = {row["id"]: row for row in batch.get("before", [])}
    after = {row["id"]: row for row in batch.get("after", [])}
    check("the batch made the overlap at the hard cut",
          bool(after) and after[3]["start"] < before[3]["start"]
          and after[2]["end"] > before[2]["end"]
          and after[3]["kind"] == "cross_dissolve",
          f"B {before.get(3)} → {after.get(3)}")
    check("…and left the clip at a GAP exactly where it was, rather than aborting "
          "the whole selection",
          bool(after) and after[4] == before[4],
          f"C {before.get(4)} → {after.get(4)}")
    check("…with no sheet: a shape clip has material on both sides of the cut",
          batch.get("sheet") is False, f"sheet: {batch.get('sheet')}")

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
        if passed != len(RESULTS):
            print(f"{passed}/{len(RESULTS)} checks passed")
            sys.exit(1)
        print(f"{passed}/{len(RESULTS)} checks passed")
