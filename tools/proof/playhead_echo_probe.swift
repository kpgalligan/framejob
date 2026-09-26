// tools/proof/playhead_echo_probe.swift — the in-process instrument behind
// `playhead_echo_probe.py`. Compiled with every file in `app/Sources` but
// `main.swift` over `harness/build.sh`'s swiftc line, copied in as
// `main.swift`, with the app's `Fonts`, `Blank.mp4` and a `default.metallib`
// of the app's own shader beside it.
//
//     playhead_echo_probe <echo.reelcut>
//
// The package is opened in a real editor window, as the app opens one, and the
// editor's own `playback.onTimeChanged` is WRAPPED: every tick it carries is
// appended to a log and then forwarded, so the editor behaves exactly as it
// would. The log is cleared before each action and read after a 1.5 s settle,
// with the document's playhead, the timeline's, the player's own tick and
// its rate. No row reads a picture. The answer is one line, `ANSWER <json>`.
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

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

let args = CommandLine.arguments
guard args.count == 2 else {
    print("usage: playhead_echo_probe <echo.reelcut>")
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
spin(3)

/// Every tick `onTimeChanged` carries, in order, since the last `clear()`.
var reports: [Ticks] = []
let forward = editor.playback.onTimeChanged
editor.playback.onTimeChanged = { t in
    reports.append(t)
    forward?(t)
}

let timeline = editor.timeline!
let scroll = (timeline.subviews.first { $0 is NSScrollView }
    ?? walk(timeline).first { $0 is NSScrollView }) as! NSScrollView

/// `revealPlayhead`'s band, in content x.
func band() -> (left: CGFloat, right: CGFloat) {
    let clip = scroll.contentView
    return (clip.bounds.minX + TimelineLayout.headerWidth + 24, clip.bounds.maxX - 24)
}

func inBand(_ t: Ticks) -> Bool {
    let x = timeline.layout.x(for: t)
    let b = band()
    return x >= b.left && x <= b.right
}

/// Where everything rests, and the log since the last clear.
func state() -> [String: Any] {
    [
        "log": reports,
        "playhead": document.playhead,
        "timeline": timeline.playhead,
        "playerTicks": CompositionBuilder.ticks(player.currentTime()),
        "rate": player.rate,
    ]
}

func start(at t: Ticks) {
    editor.setPlayhead(t)
    spin(settle)
    reports = []
}

func moveClip(_ id: UInt32, frames k: Int) -> ReelOp {
    .moveClip(clips: [id], delta: Ticks(k) * frame)
}

func liveDrag(_ id: UInt32, sampleScroll: Bool = false) -> [CGFloat] {
    var minX: [CGFloat] = []
    document.beginLiveEdit()
    for k in 1...5 {
        document.updateLiveEdit(moveClip(id, frames: k))
        spin(0.25)
        if sampleScroll { minX.append(scroll.contentView.bounds.minX) }
    }
    document.endLiveEdit("Probe Drag")
    spin(settle)
    if sampleScroll { minX.append(scroll.contentView.bounds.minX) }
    return minX
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

// refresh — a property-only edit at 1 s.
start(at: second)
let planBefore = editor.playback.builtPlanJSON
document.applyEdit("Probe", .setVideo(clips: [3], patch: VideoPatch(opacity: 0.5)))
spin(settle)
var refresh = state()
refresh["samePlan"] = planBefore != nil && planBefore == editor.playback.builtPlanJSON
answer["refresh"] = refresh

// step — the right arrow at 1 s.
start(at: second)
rightArrow()
spin(settle)
answer["step"] = state()

// seek — setPlayhead(2 s).
start(at: second)
editor.setPlayhead(2 * second)
spin(settle)
answer["seek"] = state()

// rebuild — a live drag, then a non-live move, at 1 s.
start(at: second)
let rebuildBefore = editor.playback.builtPlanJSON
_ = liveDrag(3)
var rebuild = state()
rebuild["changedPlan"] = rebuildBefore != editor.playback.builtPlanJSON
answer["rebuild"] = rebuild
reports = []
document.applyEdit("Probe", moveClip(3, frames: 1))
spin(settle)
answer["rebuild4"] = state()

// action — a span that holds 1 s and not 0, deselected, then a structural edit.
start(at: second)
document.selection = [3]
document.applyEdit("Probe", .addAction(clip: 3, at: second / 2, duration: second))
spin(settle)
editor.setPlayhead(second)
spin(settle)
let actionID = document.editedProject.snapshot.clip(3)?.actions.first?.id
document.selectAction(nil)
reports = []
document.applyEdit("Probe", moveClip(4, frames: 1))
spin(settle)
var action = state()
action["actionID"] = actionID.map { $0 as Any } ?? NSNull()
action["selectedAction"] = document.selectedAction.map { $0 as Any } ?? NSNull()
action["underPlayhead"] = document.actionUnderPlayhead.map { $0.id as Any } ?? NSNull()
answer["action"] = action
document.selection = []
spin(0.5)

// reveal — zoomed in and scrolled away from the 1 s playhead.
start(at: second)
timeline.setZoom(TimelineLayout.maxZoom, anchoredAt: scroll.contentView.bounds.midX)
spin(0.3)
timeline.scroll(toX: timeline.layout.x(for: 4 * second))
spin(0.5)
var reveal = state()
reveal["outside"] = !inBand(document.playhead)
let minX0 = scroll.contentView.bounds.minX
reveal["minX0"] = minX0
reports = []
reveal["minX"] = liveDrag(3, sampleScroll: true)
reveal["dragLog"] = reports
reveal["dragPlayhead"] = document.playhead
reports = []
rightArrow()
spin(settle)
reveal["arrow"] = state()
reveal["arrowInside"] = inBand(document.playhead)
reveal["arrowMinX"] = scroll.contentView.bounds.minX
answer["reveal"] = reveal
timeline.fit()
spin(0.5)

// play — 1.2 s from 0.5 s.
start(at: second / 2)
editor.playback.play()
spin(1.2)
var play = state()
play["from"] = second / 2
answer["play"] = play
editor.playback.pause()
spin(0.5)

// play·2 — a structural edit 0.6 s into play.
start(at: second / 2)
editor.playback.play()
spin(0.6)
let earlier = reports.count
document.applyEdit("Probe", moveClip(4, frames: 1))
spin(0.8)
var play2 = state()
play2["earlier"] = earlier
answer["play2"] = play2
editor.playback.pause()
spin(0.5)

// loop — in 0.5 s, out 2.0 s, loop on, 1.2 s from 1.5 s.
editor.setPlayhead(second / 2)
spin(0.5)
editor.setInPoint(nil)
editor.setPlayhead(2 * second)
spin(0.5)
editor.setOutPoint(nil)
editor.toggleLoop(nil)
start(at: 3 * second / 2)
editor.playback.play()
spin(1.2)
var loop = state()
loop["range"] = editor.playback.loopRange.map { [$0.start, $0.duration] } ?? []
answer["loop"] = loop
editor.playback.pause()
editor.clearInOutRange(nil)
editor.toggleLoop(nil)
spin(0.5)

// end — parked at the end, a property-only edit; then played into the end.
let duration = document.editedProject.duration
start(at: duration)
document.applyEdit("Probe", .setVideo(clips: [4], patch: VideoPatch(opacity: 0.75)))
spin(settle)
var end1 = state()
end1["duration"] = duration
answer["end1"] = end1
start(at: document.editedProject.duration - 12 * frame)
editor.playback.play()
spin(1.5)
var end2 = state()
end2["duration"] = document.editedProject.duration
answer["end2"] = end2

// short — the timeline shortened under the playhead.
start(at: 5 * second)
document.applyEdit("Probe", .delete(clips: [4]))
spin(settle)
var short = state()
short["duration"] = document.editedProject.duration
answer["short"] = short

document.close()
spin(0.5)
let data = try! JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
FileHandle.standardOutput.write("ANSWER ".data(using: .utf8)! + data + "\n".data(using: .utf8)!)
exit(0)
