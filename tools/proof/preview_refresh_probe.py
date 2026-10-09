#!/usr/bin/env python3
"""The paused preview that did not follow a property edit —
`Playback.refreshPausedFrame`, measured (2026-09-17).

What happened. With the transport paused, changing a clip's attributes —
opacity, scale, a colour, anything the compositor reads from `RecipeSource`
without a rebuild (spec §7.6's property-only branch) — left the preview
showing the OLD picture until the playhead moved or the transport ran.
`Playback.update` did what §7.6 said: publish the project, compare the plan
JSON, and since it was equal, "re-seek to the current time with zero
tolerance to force one composed frame (the standard trick for redisplaying a
paused AVPlayer)". On macOS 26.5.1 that trick is a no-op, measured here: the
seek's completion fires with `finished`, no composition request is issued,
and `AVPlayerLayer` keeps the buffer it had. Re-assigning the item's
`videoComposition` and `AVPlayerItem.seek` to the same time are the same
no-op. A seek to a DIFFERENT time composes. So the refresh now steps one tick
off the playhead and queues the return behind it — two real seeks, the
picture between them the same frame — and lands back on the playhead's own
tick with the new recipe drawn; and a refresh asked for while a seek is in
flight is remembered and run when it lands rather than dropped, which is
what used to lose the last tick of a live drag.

Why a probe and not an MCP script. `render_frame` composes offline through
`AVAssetImageGenerator`, which asks the compositor fresh every time, so every
MCP frame comparison passed against the broken build — the defect is in what
the editor's OWN player displays, which no tool reads. This is
`preview_validity_probe.py`'s instrument again: a `main.swift` compiled
against the whole of `app/Sources` with `swift_build.py`'s line, the
app's `Compositor.metal` beside it, cached by content, a build
failure scored as a FAILURE rather than an exit. It opens a one-clip package
in a real editor window, applies edits through `ProjectDocument.applyEdit` —
the path the inspector takes — and reads `AVPlayerLayer.displayedPixelBuffer()`
off the editor's player after each one. Needs an unlocked console: host
state is read and a locked one is a named skip, never a pass.

Sections:
  1. the fixture opens with a picture, and every edit below is
     PROPERTY-ONLY — the plan the item was built from is unchanged, so
     each one is §7.6's refresh branch and not a rebuild;
  2. the paused preview follows the edit: opacity 0 goes black, opacity 1
     comes back, a 5 % scale shrinks the picture, at 0 s and again after a
     move to 1 s;
  3. after every refresh the player rests on the playhead's OWN tick — the
     round trip, not a one-way step that would leave the transport a tick
     off the grid;
  4. a refresh asked for while a seek is in flight is not lost: an edit in
     the same run-loop turn as a playhead move, two edits in one turn each
     way, and — the window `refreshWanted` exists for — an edit after the
     move's seek has COMPOSED its frame but before its completion has run
     on main (the main thread held 300 ms), all show the LAST value;
  5. the last frame, where the step has to go backwards because the next
     tick is not a time, and the composition's END — seeked to, where the
     layer holds nothing (the end tick composes the empty canvas), and
     reached by PLAYING, where it holds whichever frame the pipeline
     composed last, the last frame or that empty canvas (measured both
     ways, so the row claims neither) — where the transport comes to rest
     on the last frame's final tick and that frame is drawn with the new
     recipe, rather than blanked by a return to the end or left stale;
  6. View ▸ Preview Quality on a paused player shows without a playhead
     move — the displayed buffer halves and comes back — since that setter
     relies on the same refresh.

**58/58** at the landing, console unlocked. Mutation-tested on the working
tree with the probe rebuilt: `refreshPausedFrame` restored to the same-time
seek scores **48/58** — every row where the picture has to CHANGE (the
"goes black" rows, the shrink, the burst to the picture, the held-thread
row and all four end rows; a row where the picture merely has to be there
is satisfied by the stale one, which is the defect); `refreshWanted` never
set — a refresh while seeking dropped, the old guard — scores **57/58**,
and the one row is the held-thread one, which is why that row exists: the
two same-turn rows pass against it because the seek already in flight
composes AFTER the recipe is published; the end branch removed — a round
trip back to the end tick — scores **54/58**, the four end rows (the
transport lands on the end tick and the layer shows black).

  7. (the precision road map's PR1, spec §11 PR-1) PF: at Full the displayed
     buffer is the compositor's 64RGBAHalf, and its 40 × 40 grid mean is
     within ±1 of `Exporter.renderFrame`'s at the same tick. Every buffer the
     probe reads is read by its format — 32BGRA bytes, or 64RGBAHalf halves
     × 255 — and any other format leaves no mean, which fails the rows that
     read it.

Needs `ffmpeg`, `swiftc`, `xcrun metal` and `core/target/release/libreelcut_core.a`.
No port. Run from anywhere:

    python3 tools/proof/preview_refresh_probe.py
    python3 tools/proof/preview_refresh_probe.py --sources DIR   # a copy's app/Sources
"""

import json
import os
import shutil
import subprocess
import sys

import swift_build

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "preview-refresh")
PROBE = os.path.join(WORK, "probe")
SOURCES = os.path.join(ROOT, "app", "Sources")
SHADER = os.path.join(ROOT, "app", "Resources", "Shaders", "Compositor.metal")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")
PLACEHOLDER = os.path.join(ROOT, "app", "Resources", "Blank.mp4")

TICKS = 600_000
CLIP_SECONDS = 3
END = CLIP_SECONDS * TICKS
# The layer's mean over a 40 × 40 grid: the test card reads well over this
# with the picture on and well under it with the picture off.
PICTURE = 16
BLACK = 8

passed = 0
failed = 0
skipped = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


def skip(name, reason):
    global skipped
    skipped += 1
    print(f"  skip {name} — {reason}")


def section(title):
    print(f"\n{title}")


# ---------------------------------------------------------------------------
# The fixture: one test card, one clip, a 30 fps canvas at the card's size.


def make_fixture():
    os.makedirs(WORK, exist_ok=True)
    movie = os.path.join(WORK, "card.mov")
    if not os.path.exists(movie):
        result = subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-t", "4",
             "-f", "lavfi", "-i", "testsrc2=size=432x280:rate=30",
             "-c:v", "h264", "-pix_fmt", "yuv420p", movie],
            capture_output=True, text=True)
        if result.returncode != 0:
            return None, f"ffmpeg failed: {result.stderr.strip()[:300]}"
    package = os.path.join(WORK, "refresh.reelcut")
    os.makedirs(package, exist_ok=True)
    project = {
        "version": 8,
        "canvas": {"width": 432, "height": 280, "fps": [30, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": True, "timecode_frames": True},
        "media": [{"id": 2, "path": movie, "kind": "video", "duration": 4 * TICKS,
                   "width": 432, "height": 280, "fps": [30, 1],
                   "has_video": True, "has_audio": False}],
        "tracks": [{"id": 1, "name": "Track 1"}],
        "clips": [{"id": 3, "track": 1, "start": 0, "duration": CLIP_SECONDS * TICKS,
                   "source": {"kind": "media", "media": 2, "in": 0}, "video": {}, "audio": {}}],
        "markers": [], "next_id": 4, "nests": [],
    }
    with open(os.path.join(package, "project.json"), "w") as f:
        json.dump(project, f, indent=1)
    return package, None


# ---------------------------------------------------------------------------
# The probe.

PROBE_SOURCE = r'''
import AppKit
import AVFoundation

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
NSApplication.shared.setActivationPolicy(.accessory)
// The player reads View ▸ Preview Quality from the defaults at birth: pin it
// to Full in the argument domain, so a previous run's section 6 cannot leak
// into this one's picture.
UserDefaults.standard.setVolatileDomain(
    ["ReelcutPreviewQuality": 0], forName: UserDefaults.argumentDomain)

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
}

let args = CommandLine.arguments
var answer: [String: Any] = [:]

/// The displayed buffer's 40 × 40 grid: the mean of (r + g + b) / 3 a pixel
/// in integers, each channel 0…255 — a 32BGRA buffer's bytes, or a
/// 64RGBAHalf buffer's halves × 255, rounded (the precision road map's PR1:
/// the compositor's output is 64RGBAHalf) — and the same mean unrounded, with
/// the buffer's fourcc. The means are nil for any other format, which every
/// row reading them scores as a failure.
func gridMean(_ buffer: CVPixelBuffer) -> (format: String, mean: Int?, exact: Double?) {
    let type = CVPixelBufferGetPixelFormatType(buffer)
    let format = String(bytes: [24, 16, 8, 0].map { UInt8((type >> UInt32($0)) & 0xFF) },
                        encoding: .ascii) ?? "\(type)"
    guard type == kCVPixelFormatType_32BGRA || type == kCVPixelFormatType_64RGBAHalf,
        CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess
    else { return (format, nil, nil) }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
    let row = CVPixelBufferGetBytesPerRow(buffer)
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return (format, nil, nil) }
    var sum = 0, exact = 0.0, n = 0
    for y in stride(from: 0, to: h, by: max(h / 40, 1)) {
        for x in stride(from: 0, to: w, by: max(w / 40, 1)) {
            var channels = [0, 0, 0]
            if type == kCVPixelFormatType_32BGRA {
                let p = (base + y * row).assumingMemoryBound(to: UInt8.self) + x * 4
                channels = [Int(p[0]), Int(p[1]), Int(p[2])]
            } else {
                let p = (base + y * row).assumingMemoryBound(to: Float16.self) + x * 4
                channels = (0..<3).map { Int((Float(p[$0]) * 255).rounded()) }
            }
            sum += (channels[0] + channels[1] + channels[2]) / 3
            exact += Double(channels[0] + channels[1] + channels[2]) / 3
            n += 1
        }
    }
    return (format, sum / max(n, 1), exact / Double(max(n, 1)))
}

let document = ProjectDocument()
try! document.read(from: URL(fileURLWithPath: args[1]), ofType: ProjectDocument.projectTypeIdentifier)
NSDocumentController.shared.addDocument(document)
document.makeWindowControllers()
document.showWindows()
let editor = document.windowControllers.first!.contentViewController as! EditorViewController
let layer = editor.playback.playerLayer
let player = layer.player!
spin(3)
let clip = document.editedProject.snapshot.clips[0].id
let frame = document.editedProject.snapshot.canvas.fps.frameDuration
let duration = document.editedProject.duration

/// What the layer displays and where the transport rests. Captured on
/// SETTLE, the harness's rule: the layer is polled for a displayed buffer
/// for up to three seconds. A sample taken at one fixed instant 1.5 s after
/// a Preview Quality change read `displayedPixelBuffer()` as nil about one
/// run in three, with the transport at rest on the right tick and every
/// poll since answering at once (`waitMs` is 0 in every run recorded) —
/// an instant with no buffer, not a layer left with none.
func sample() -> [String: Any] {
    let started = Date()
    var buffer = layer.displayedPixelBuffer()
    while buffer == nil, Date().timeIntervalSince(started) < 3 {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        buffer = layer.displayedPixelBuffer()
    }
    var s: [String: Any] = [
        "playhead": document.playhead,
        "playerTicks": CompositionBuilder.ticks(player.currentTime()),
        "rate": player.rate,
        "ready": layer.isReadyForDisplay,
        "waitMs": Int(Date().timeIntervalSince(started) * 1000),
    ]
    if let buffer = buffer {
        let grid = gridMean(buffer)
        s["format"] = grid.format
        if let mean = grid.mean {
            s["size"] = [CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer)]
            s["mean"] = mean
            s["meanExact"] = grid.exact
        }
    }
    return s
}

/// One edit through the inspector's own path, then the settle. `samePlan`
/// is whether the item the player holds was built from the plan it still
/// has — the §7.6 branch the edit took.
func edit(_ ops: [ReelOp], wait: Double = 1.5) -> [String: Any] {
    let before = editor.playback.builtPlanJSON
    document.applyEdit("Probe", ops)
    spin(wait)
    var s = sample()
    s["samePlan"] = before == editor.playback.builtPlanJSON
    return s
}
func opacity(_ value: Double) -> ReelOp { .setVideo(clips: [clip], patch: VideoPatch(opacity: value)) }
func scale(_ value: Double) -> ReelOp { .setVideo(clips: [clip], patch: VideoPatch(scale: value)) }
func move(_ ticks: Ticks) { editor.setPlayhead(ticks); spin(1.5) }

answer["opened"] = sample()
answer["opacity0"] = edit([opacity(0)])
answer["opacity1"] = edit([opacity(1)])
answer["scaleSmall"] = edit([scale(0.05)])
answer["scaleBack"] = edit([scale(1)])

move(ReelTime.ticks(seconds: 1))
answer["at1s"] = sample()
answer["opacity0at1s"] = edit([opacity(0)])
answer["opacity1at1s"] = edit([opacity(1)])

// The edit lands in the SAME run-loop turn as the move, so its refresh is
// asked for while the move's seek is in flight.
editor.setPlayhead(ReelTime.ticks(seconds: 2))
answer["midSeek"] = edit([opacity(0)])
// Two edits in one turn: the second's refresh arrives while the first's
// round trip is in flight. The last value is the one that must show.
document.applyEdit("Probe", [opacity(1)])
answer["burstToBlack"] = edit([opacity(0)])
document.applyEdit("Probe", [opacity(0)])
answer["burstToPicture"] = edit([opacity(1)])
// The window `refreshWanted` exists for: the move's seek has COMPOSED its
// frame (the compositor and AVFoundation run on their own threads) but its
// completion has not yet run on main, so the frame on the layer predates the
// recipe the edit publishes. Holding the main thread is how that window is
// hit on purpose: the completion is queued behind the sleep.
editor.setPlayhead(ReelTime.ticks(seconds: 2.5))
Thread.sleep(forTimeInterval: 0.3)
answer["composedBeforeEdit"] = edit([opacity(0)])
_ = edit([opacity(1)])

// The last frame, where the next tick is still inside the composition, and
// the end itself, where it is not: seeked to, and then reached by PLAYING,
// which is how a transport usually comes to rest there.
move(duration - frame)
answer["atLastFrame"] = sample()
answer["opacity0atLastFrame"] = edit([opacity(0)])
answer["opacity1atLastFrame"] = edit([opacity(1)])
move(duration)
answer["atEnd"] = sample()
answer["opacity0atEnd"] = edit([opacity(0)])
answer["opacity1atEnd"] = edit([opacity(1)])
move(duration - 12 * frame)
editor.playback.play()
spin(4)
answer["playedToEnd"] = sample()
answer["halfAfterPlay"] = edit([opacity(0.5)])
answer["opacity1afterPlay"] = edit([opacity(1)])

// Preview Quality while paused: the setter re-assigns the item's composition
// and asks for the same refresh.
move(ReelTime.ticks(seconds: 1))
answer["beforeQuality"] = sample()
// PF (the precision road map's PR1): the frame `Exporter.renderFrame` draws at
// the same tick, on the same grid — redrawn into 8-bit RGBA in its own space.
if let image = Exporter.renderFrame(
    project: document.project, urls: document.mediaURLs(), at: document.playhead, maxWidth: nil),
    let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
{
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
        guard let context = CGContext(
            data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    var exact = 0.0, n = 0
    for y in stride(from: 0, to: h, by: max(h / 40, 1)) where drawn {
        for x in stride(from: 0, to: w, by: max(w / 40, 1)) {
            let p = (y * w + x) * 4
            exact += Double(Int(bytes[p]) + Int(bytes[p + 1]) + Int(bytes[p + 2])) / 3
            n += 1
        }
    }
    answer["renderAtFull"] = ["size": [w, h], "bits": image.bitsPerComponent,
                              "mean": drawn ? exact / Double(max(n, 1)) : -1]
}
editor.playback.setPreviewQuality(.half)
spin(1.5)
answer["half"] = sample()
editor.playback.setPreviewQuality(.full)
spin(1.5)
answer["fullAgain"] = sample()

let data = try! JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
FileHandle.standardOutput.write("ANSWER ".data(using: .utf8)! + data + "\n".data(using: .utf8)!)
exit(0)
'''


def build_shader():
    """The app's own `Compositor.metal` as a `default.metallib` beside the
    binary — without it `MetalRenderer.init` returns nil and the player draws
    nothing at all. `phase7_chrome.py`'s `build_shader`, cached the same way."""
    lib = os.path.join(PROBE, "default.metallib")
    air = os.path.join(PROBE, "Compositor.air")
    if os.path.exists(lib) and os.path.getmtime(SHADER) < os.path.getmtime(lib):
        return lib, None
    step = subprocess.run(["xcrun", "-sdk", "macosx", "metal", "-c", SHADER, "-o", air],
                          capture_output=True, text=True)
    if step.returncode != 0:
        return None, "xcrun metal failed: " + step.stderr.strip()[:300]
    step = subprocess.run(["xcrun", "-sdk", "macosx", "metallib", air, "-o", lib],
                          capture_output=True, text=True)
    if step.returncode != 0 or not os.path.exists(lib):
        return None, "xcrun metallib failed: " + step.stderr.strip()[:300]
    return lib, None


def build_probe():
    """`preview_validity_probe.py`'s `build_probe`: `swift_build.build`,
    `Fonts` and `Blank.mp4` beside the binary. Answers (binary, None) or (None,
    reason)."""
    os.makedirs(PROBE, exist_ok=True)
    binary = os.path.join(PROBE, "refreshprobe")
    entry = os.path.join(PROBE, "main.swift")
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
    shader, why = build_shader()
    if shader is None:
        return None, why
    sources = sorted(os.path.join(SOURCES, name) for name in os.listdir(SOURCES)
                     if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    try:
        built = swift_build.build(sources=sources + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        tail = error.diagnostics[-4:]
        return None, (f"swiftc exited {error.rc if error.rc is not None else 'before running'}: "
                      + " | ".join(errors[:6] or tail or ["(no output)"]))
    if built.reused:
        print(f"probe: {binary} (up to date)")
    else:
        print(f"probe: {binary} (built in {built.seconds:.1f} s)")
    return binary, None


def run_probe(binary, *arguments):
    """One invocation; (answer, None) or (None, why)."""
    if binary is None:
        return None, "the probe did not build"
    try:
        result = subprocess.run([binary, *arguments], capture_output=True, text=True,
                                timeout=240, cwd=PROBE)
    except subprocess.TimeoutExpired:
        return None, "the probe timed out"
    for line in result.stdout.splitlines():
        if line.startswith("ANSWER "):
            return json.loads(line[len("ANSWER "):]), None
    return None, f"no answer (exit {result.returncode}): {result.stderr.strip()[-300:]}"


def console_locked():
    """Host state is a proof input (`recording_proof.py`): a locked console
    displays nothing in any layer, so every row is skipped BY NAME."""
    out = subprocess.run(["ioreg", "-n", "Root", "-d1", "-a"], capture_output=True, text=True).stdout
    marker = out.find("<key>IOConsoleLocked</key>")
    return marker >= 0 and out[marker:marker + 60].find("<true/>") >= 0


EDITS = ["opacity0", "opacity1", "scaleSmall", "scaleBack", "opacity0at1s", "opacity1at1s",
         "midSeek", "burstToBlack", "burstToPicture", "composedBeforeEdit", "opacity0atLastFrame",
         "opacity1atLastFrame", "opacity0atEnd", "opacity1atEnd", "halfAfterPlay",
         "opacity1afterPlay"]


def rows():
    """Every row, as (section, name, predicate over the answer, detail key)."""
    def mean(a, key):
        return a[key].get("mean", -1)

    def picture(key):
        return lambda a: mean(a, key) > PICTURE and a[key].get("ready") is True

    def black(key):
        return lambda a: 0 <= mean(a, key) < BLACK

    def rests(key):
        return lambda a: a[key]["playerTicks"] == a[key]["playhead"] and a[key]["rate"] == 0

    yield ("1 — the fixture opens with a picture, and every edit is property-only", [
        ("the editor's player displays the test card at 0 s", picture("opened"), "opened"),
    ] + [
        (f"{key}: the plan the item was built from is unchanged (the refresh branch)",
         (lambda k: lambda a: a[k]["samePlan"] is True)(key), key)
        for key in EDITS
    ])
    yield ("2 — the paused preview follows a property edit", [
        ("opacity 0 at 0 s: the layer goes black", black("opacity0"), "opacity0"),
        ("opacity 1 at 0 s: the picture comes back", picture("opacity1"), "opacity1"),
        ("scale 0.05 at 0 s: the picture shrinks to a fraction of the mean",
         lambda a: 0 <= mean(a, "scaleSmall") < mean(a, "opacity1") / 3, "scaleSmall"),
        ("scale 1 at 0 s: the picture is whole again", picture("scaleBack"), "scaleBack"),
        ("after a move to 1 s the layer shows the card (precondition)", picture("at1s"), "at1s"),
        ("opacity 0 at 1 s: the layer goes black", black("opacity0at1s"), "opacity0at1s"),
        ("opacity 1 at 1 s: the picture comes back", picture("opacity1at1s"), "opacity1at1s"),
    ])
    yield ("3 — after every refresh the player rests on the playhead's own tick", [
        (f"{key}: the player's time is the playhead's, paused", rests(key), key) for key in EDITS
    ] + [
        ("the move to 1 s put the playhead at 1 s exactly",
         lambda a: a["at1s"]["playhead"] == TICKS, "at1s"),
    ])
    yield ("4 — a refresh asked for while a seek is in flight is not lost", [
        ("an edit in the same turn as a move to 2 s: black at 2 s",
         lambda a: black("midSeek")(a) and a["midSeek"]["playhead"] == 2 * TICKS, "midSeek"),
        ("opacity 1 then 0 in one turn: black", black("burstToBlack"), "burstToBlack"),
        ("opacity 0 then 1 in one turn: the picture", picture("burstToPicture"), "burstToPicture"),
        ("an edit after the move's seek composed but before its completion reached main "
         "(the main thread held 300 ms): black at 2.5 s, on that tick",
         lambda a: black("composedBeforeEdit")(a)
         and a["composedBeforeEdit"]["playhead"] == 2 * TICKS + TICKS // 2
         and rests("composedBeforeEdit")(a), "composedBeforeEdit"),
    ])
    yield ("5 — the last frame, and the composition's end", [
        ("at the last frame the layer shows the card (precondition)",
         picture("atLastFrame"), "atLastFrame"),
        ("opacity 0 at the last frame: black", black("opacity0atLastFrame"), "opacity0atLastFrame"),
        ("opacity 1 at the last frame: the picture", picture("opacity1atLastFrame"),
         "opacity1atLastFrame"),
        ("seeked to the end, the playhead is there and the layer holds NO frame — the end tick "
         "composes nothing (AVFoundation's; the precondition)",
         lambda a: a["atEnd"]["playhead"] == END and a["atEnd"].get("mean") == 0, "atEnd"),
        ("opacity 0 at the end: the transport rests on the last frame's final tick, black",
         lambda a: black("opacity0atEnd")(a) and a["opacity0atEnd"]["playerTicks"] == END - 1,
         "opacity0atEnd"),
        ("opacity 1 at the end: still on that tick, and the picture is back",
         lambda a: picture("opacity1atEnd")(a) and a["opacity1atEnd"]["playerTicks"] == END - 1,
         "opacity1atEnd"),
        ("played to the end, the transport is paused at the end tick (precondition; what the "
         "layer holds there is whichever frame the pipeline composed last, and is not claimed)",
         lambda a: a["playedToEnd"]["playerTicks"] == END and a["playedToEnd"]["rate"] == 0,
         "playedToEnd"),
        ("opacity 0.5 there: the last frame is drawn at half on its final tick — not blanked, "
         "not stale",
         lambda a: PICTURE < mean(a, "halfAfterPlay") < mean(a, "opacity1afterPlay") - PICTURE
         and a["halfAfterPlay"]["playerTicks"] == END - 1, "halfAfterPlay"),
        ("opacity 1 there: the last frame is whole again, on that tick",
         lambda a: picture("opacity1afterPlay")(a)
         and a["opacity1afterPlay"]["playerTicks"] == END - 1, "opacity1afterPlay"),
    ])
    yield ("6 — Preview Quality on a paused player shows without a move", [
        ("at Full the displayed buffer is the canvas size",
         lambda a: a["beforeQuality"].get("size") == [432, 280], "beforeQuality"),
        ("Half: the displayed buffer halves, with the picture in it",
         lambda a: a["half"].get("size") == [216, 140] and picture("half")(a), "half"),
        ("Full again: the displayed buffer is the canvas size again, with the picture in it",
         lambda a: a["fullAgain"].get("size") == [432, 280] and picture("fullAgain")(a),
         "fullAgain"),
        ("neither quality change moved the playhead",
         lambda a: a["half"]["playhead"] == TICKS and a["fullAgain"]["playhead"] == TICKS
         and rests("half")(a) and rests("fullAgain")(a), "fullAgain"),
    ])


def pf_row():
    """PF (the precision road map's PR1, spec §11 PR-1): at Full the displayed
    buffer is 64RGBAHalf, and its grid mean is within ±1 of
    `Exporter.renderFrame`'s at the same tick."""
    def good(a):
        shown, drawn = a["beforeQuality"], a["renderAtFull"]
        return (shown.get("format") == "RGhA" and drawn.get("mean", -1) >= 0
                and abs(shown["meanExact"] - drawn["mean"]) <= 1)
    return ("7 — the displayed buffer is the compositor's 16-bit float (PR1)", [
        ("PF at Full the displayed buffer is 64RGBAHalf and its 40 × 40 grid mean is within ±1 "
         "of Exporter.renderFrame's at the same tick", good, "PF"),
    ])


def main():
    global SOURCES, SHADER, PROBE
    if "--sources" in sys.argv:
        # A mutant's copy (`precision_proof.py --mutant output-8bit`): its
        # sources and its shader, built in a folder of their own.
        SOURCES = os.path.abspath(sys.argv[sys.argv.index("--sources") + 1])
        SHADER = os.path.join(os.path.dirname(SOURCES), "Resources", "Shaders", "Compositor.metal")
        PROBE = os.path.join(WORK, "probe-sources")
        print(f"sources: {SOURCES}")
    package, why = make_fixture()
    binary, build_error = build_probe()
    locked = console_locked()
    answer, error = (None, None)
    if not locked and package is not None and binary is not None:
        answer, error = run_probe(binary, package)
    for title, checks in list(rows()) + [pf_row()]:
        section(title)
        for name, predicate, key in checks:
            if locked:
                skip(name, "the console is locked, and a locked console displays nothing in any layer")
            elif answer is None:
                check(name, False, why or build_error or error)
            else:
                try:
                    ok = predicate(answer)
                except (KeyError, TypeError) as e:
                    ok = False
                detail = ({"shown": answer.get("beforeQuality"), "drawn": answer.get("renderAtFull")}
                          if key == "PF" else answer.get(key))
                check(name, ok, json.dumps(detail))
                if ok and key == "PF":
                    print(f"       {json.dumps(detail)}")
    total = passed + failed
    print(f"\n{passed}/{total} checks passed" + (f", {skipped} skipped by name" if skipped else ""))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
