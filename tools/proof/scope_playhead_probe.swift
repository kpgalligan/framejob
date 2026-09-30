// tools/proof/scope_playhead_probe.swift — the in-process instrument behind
// `scope_playhead_probe.py` (issue batch B21, #130). Compiled with every file in
// `app/Sources` but `main.swift` over `harness/build.sh`'s swiftc line, copied in
// as `main.swift`, with the app's `Fonts`, `Blank.mp4` and a `default.metallib`
// of the app's own shader beside it — `playhead_echo_probe.swift`'s build.
//
//     scope_playhead_probe <scope.reelcut>
//
// The package is opened in a real editor window and the editor's own
// `playback.onTimeChanged` is WRAPPED, as the echo probe wraps it: every tick it
// carries is logged, then forwarded. The races are FORCED, never waited for:
// `Playback.rebuildHop` (nil in the app) stores the block a rebuild would hand
// `DispatchQueue.main.async`, so a scope change can be held with its rebuild
// in flight for as long as a row needs, and "one turn" is two calls with no
// run-loop spin between them. The answer is one line, `ANSWER <json>`.
import AppKit
import AVFoundation

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
NSApplication.shared.setActivationPolicy(.accessory)
UserDefaults.standard.setVolatileDomain(
    ["ReelcutPreviewQuality": 0], forName: UserDefaults.argumentDomain)

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

let args = CommandLine.arguments
guard args.count == 2 else {
    print("usage: scope_playhead_probe <scope.reelcut>")
    exit(2)
}

let second = ReelTime.ticks(seconds: 1)
let settle = 1.5

let url = URL(fileURLWithPath: args[1])
let document = ProjectDocument()
try! document.read(from: url, ofType: ProjectDocument.projectTypeIdentifier)
document.fileURL = url
NSDocumentController.shared.addDocument(document)
document.makeWindowControllers()
document.showWindows()
let editor = document.windowControllers.first!.contentViewController as! EditorViewController
let player = editor.playback.playerLayer.player!
let frame = document.editedProject.snapshot.canvas.fps.frameDuration
spin(2)

/// Every tick `onTimeChanged` carries, in order, since the last clear.
var reports: [Ticks] = []
let forward = editor.playback.onTimeChanged
editor.playback.onTimeChanged = { t in
    reports.append(t)
    forward?(t)
}
let timeline = editor.timeline!

// The fixture: shape A at 0–1 s, shape B at 2–4 s, B nested into N at 2–4 s.
document.applyEdit(
    "Probe", .addShapeClip(track: 1, at: 0, duration: second, shape: .rectangle))
document.applyEdit(
    "Probe", .addShapeClip(track: 1, at: 2 * second, duration: 2 * second, shape: .ellipse))
spin(0.5)
let shapeB = document.project.snapshot.clips.first { $0.start == 2 * second }!.id
document.applyEdit("Probe", .nest(clips: [shapeB]))
spin(settle)
let shapeA = document.project.snapshot.clips.first { $0.source.nestID == nil }!.id

func nestClip() -> ClipSnapshot {
    document.project.snapshot.clips.first { $0.source.nestID != nil }!
}

// MARK: - The hold

final class Hold {
    let lock = NSLock()
    var block: (() -> Void)?
}
let hold = Hold()

/// Arms the seam: the NEXT rebuild's finishing block is stored, not run.
func arm() {
    hold.lock.lock()
    hold.block = nil
    hold.lock.unlock()
    editor.playback.rebuildHop = { block in
        hold.lock.lock()
        hold.block = block
        hold.lock.unlock()
    }
}

/// Waits (≤ 10 s) for the held block, then for five equal player reads 20 ms
/// apart (≤ 3 s). Answers the block, or nil when none arrived.
func waitHeld() -> (block: (() -> Void)?, settled: Bool) {
    var block: (() -> Void)?
    let deadline = Date().addingTimeInterval(10)
    while block == nil && Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        hold.lock.lock()
        block = hold.block
        hold.lock.unlock()
    }
    guard block != nil else {
        editor.playback.rebuildHop = nil
        return (nil, false)
    }
    var last = player.currentTime()
    var same = 0
    let until = Date().addingTimeInterval(3)
    while same < 5 && Date() < until {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        let now = player.currentTime()
        if now == last { same += 1 } else { same = 0; last = now }
    }
    return (block, same >= 5)
}

func release(_ block: (() -> Void)?) {
    block?()
    editor.playback.rebuildHop = nil
}

// MARK: - Positions

/// Where everything rests, and the log since the row began.
func state() -> [String: Any] {
    [
        "log": reports,
        "playhead": document.playhead,
        "timeline": timeline.playhead,
        "playerTicks": CompositionBuilder.ticks(player.currentTime()),
        "rate": player.rate,
        "scope": document.nestPath.count,
    ]
}

/// The timeline open, the playhead at `t`, settled, the log cleared.
func atTimeline(_ t: Ticks) {
    while !document.nestPath.isEmpty {
        editor.leaveNest()
        spin(settle)
    }
    editor.setPlayhead(t)
    spin(settle)
    reports = []
}

/// N open, the playhead at `t` inside it, settled, the log cleared.
func inside(_ t: Ticks) {
    if document.nestPath.isEmpty {
        editor.enterNest(nestClip())
        spin(settle)
    }
    editor.setPlayhead(t)
    spin(settle)
    reports = []
}

func rightArrow() {
    let arrow = String(UnicodeScalar(UInt32(NSRightArrowFunctionKey))!)
    let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, characters: arrow,
        charactersIgnoringModifiers: arrow, isARepeat: false, keyCode: 124)!
    editor.view.window?.makeFirstResponder(nil)
    _ = editor.handleEditorKey(event)
}

var answer: [String: Any] = ["frame": frame, "second": second]

// S0 — the fixture.
let n0 = nestClip()
answer["S0"] = [
    "duration": document.editedProject.duration, "nStart": n0.start,
    "nDuration": n0.duration, "a": shapeA,
] as [String: Any]

// S1 — inside at 1 s; held; leave.
inside(second)
arm()
editor.leaveNest()
var held = waitHeld()
var s1: [String: Any] = ["held": held.block != nil, "settled": held.settled,
                         "duringHold": document.playhead, "logAtHold": reports]
release(held.block)
spin(settle)
s1.merge(state()) { _, new in new }
answer["S1"] = s1

// S2 — inside at 0; one turn: setPlayhead(1 s), leave.
inside(0)
editor.setPlayhead(second)
editor.leaveNest()
spin(settle)
answer["S2"] = state()

// S3 — timeline 3 s; held; enter N.
atTimeline(3 * second)
arm()
editor.enterNest(nestClip())
held = waitHeld()
var s3: [String: Any] = ["held": held.block != nil, "settled": held.settled,
                         "duringHold": document.playhead]
release(held.block)
spin(settle)
s3.merge(state()) { _, new in new }
answer["S3"] = s3

// S4 — timeline 3 s; one turn: enter N, leave.
atTimeline(3 * second)
editor.enterNest(nestClip())
editor.leaveNest()
spin(settle)
var s4 = state()
s4["planMatches"] = editor.playback.builtPlanJSON == document.editedProject.planJSON
answer["S4"] = s4

// S5 — timeline 0.5 s; one turn: opacity on A, setPlayhead(3 s), enter N.
atTimeline(second / 2)
document.applyEdit("Probe", .setVideo(clips: [shapeA], patch: VideoPatch(opacity: 0.5)))
editor.setPlayhead(3 * second)
editor.enterNest(nestClip())
spin(settle)
answer["S5"] = state()

// S6 — timeline 1 s; one turn: opacity on A, setPlayhead(2 s).
atTimeline(second)
document.applyEdit("Probe", .setVideo(clips: [shapeA], patch: VideoPatch(opacity: 0.6)))
editor.setPlayhead(2 * second)
spin(settle)
answer["S6"] = state()

// S7 — timeline 1 s; held; move A one frame; one turn: the held block, setPlayhead(2 s).
atTimeline(second)
arm()
document.applyEdit("Probe", .moveClip(clips: [shapeA], delta: frame))
held = waitHeld()
var s7: [String: Any] = ["held": held.block != nil, "settled": held.settled]
release(held.block)
editor.setPlayhead(2 * second)
spin(settle)
s7.merge(state()) { _, new in new }
answer["S7"] = s7

// S8 — from 1 s, setPlayhead(0.5 s).
atTimeline(second)
editor.setPlayhead(second / 2)
spin(settle)
answer["S8"] = state()

// S9 — at 0.5 s, the right arrow.
atTimeline(second / 2)
rightArrow()
spin(settle)
answer["S9"] = state()

// S10 — at 1 s, an opacity edit on A.
atTimeline(second)
document.applyEdit("Probe", .setVideo(clips: [shapeA], patch: VideoPatch(opacity: 0.7)))
spin(settle)
answer["S10"] = state()

// S11 — at 1 s, A moved one frame, non-live.
atTimeline(second)
document.applyEdit("Probe", .moveClip(clips: [shapeA], delta: frame))
spin(settle)
answer["S11"] = state()

// S12 — from 0.5 s, play 1.2 s.
atTimeline(second / 2)
editor.playback.play()
spin(1.2)
var s12 = state()
s12["from"] = second / 2
answer["S12"] = s12
editor.playback.pause()
spin(0.5)

document.close()
spin(0.5)
let data = try! JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
FileHandle.standardOutput.write("ANSWER ".data(using: .utf8)! + data + "\n".data(using: .utf8)!)
exit(0)
