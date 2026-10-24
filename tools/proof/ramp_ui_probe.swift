// Speed ramps SR5 (spec §11 SR-21): the G rows' readings for `ramp_proof.py`,
// compiled as `main.swift` over `app/Sources` through `swift_build.build()`.
// Prints one JSON object on stdout: what the inspector's Speed section, the
// marks, the bands, the ×12 question and the Speed sheet answer on a ramped
// project. The proof scores every reading; this file decides nothing. No
// network, no app, no defaults written (no section is toggled).
//
// The project is made in-process (`ReelProject.new`) and written to
// `<cwd>/ramp-ui.framejob/project.json`, then opened in a `ProjectDocument`
// with an `InspectorViewController` over it (`clip_inspector_probe.swift`
// S4's pattern):
//   one   a 10 s A/V media with no file, a clip at 0.5 s from in 0.5 s, 5 s
//         long; action A [0, 2 s) linear {speed: 2}, action B [3 s, 4 s)
//         linear {video: {opacity: 0.5}}
//   two   the same media at 6 s, 2 s long, an action [0, 2 s) linear
//         {speed: 3}, then `trim_end` to 1 s: the action runs past the end
//   P     a 60 s A/V media with no file at 10 s, in 0, `trim_end` to 0.5 s at
//         ×1, one action [0, 0.5 s) linear {speed: 2}
//   Q     the same media at 12 s, `set_speed` 13, `trim_end` to 0.5 s (it
//         reads 6.5 s), one action [0, 0.5 s) linear {speed: 13}
//   R     the same media at 14 s, `set_speed` 2, `trim_end` to 0.5 s: a
//         constant ×2 clip with sound

import AppKit

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let second: Ticks = 600_000
var out: [String: Any] = [:]
var problems: [String] = []

func emit() -> Never {
    if !problems.isEmpty { out["problems"] = problems }
    let answer = (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data()
    print(String(data: answer, encoding: .utf8) ?? "{}")
    exit(0)
}

/// A JSON-safe copy of an op's argument value.
func plain(_ value: Any) -> Any {
    if value is NSNull { return NSNull() }
    if let map = value as? [String: Any] { return map.mapValues(plain) }
    if let list = value as? [Any] { return list.map(plain) }
    if let number = value as? Double { return number }
    if let number = value as? Int { return number }
    if let number = value as? UInt32 { return Int(number) }
    if let number = value as? Int64 { return Int(number) }
    if let flag = value as? Bool { return flag }
    if let text = value as? String { return text }
    return String(describing: value)
}

func describe(_ ops: [ReelOp]) -> [[String: Any]] {
    ops.map { ["name": $0.name, "args": plain($0.args)] }
}

func markName(_ mark: RowMark?) -> String {
    guard let mark else { return "no row" }
    switch mark {
    case .none: return "none"
    case .keyed: return "keyed"
    case .keyedAtEnd: return "keyedAtEnd"
    case .other(let number): return "other(\(number))"
    case .follows: return "follows"
    case .notAnimatable: return "notAnimatable"
    }
}

// MARK: - The project

guard var project = ReelProject.new(width: 320, height: 180, fps: .thirty) else {
    out["error"] = "ReelProject.new answered nil"
    emit()
}
/// Applied or an identity; a refusal or an error is a problem.
@discardableResult
func step(_ op: ReelOp) -> Bool {
    switch try? project.applying(op) {
    case .applied(let next)?: project = next
    case .identity?: break
    case .refused(let why)?:
        problems.append("\(op.name) refused: \(why.reason)")
        return false
    case nil:
        problems.append("\(op.name) was invalid: \(op.args)")
        return false
    }
    return true
}
func lastClip() -> UInt32 { project.snapshot.clips.max { $0.id < $1.id }?.id ?? 0 }
func actions(_ clip: UInt32) -> [ActionSnapshot] {
    project.snapshot.clip(clip).map { ActionBands.ordered($0) } ?? []
}
/// A linear action at clip time `at` for `duration` whose end is `patch`.
func action(_ clip: UInt32, at: Ticks, duration: Ticks, _ patch: [String: Any]) -> UInt32 {
    let before = Set(actions(clip).map(\.id))
    step(.addAction(clip: clip, at: at, duration: duration))
    guard let id = actions(clip).map(\.id).first(where: { !before.contains($0) }) else {
        problems.append("no action added on clip \(clip) at \(at)")
        return 0
    }
    step(.setAction(clip: clip, action: id, curve: .linear))
    step(.setActionEndRaw(clip: clip, action: id, patch: patch))
    return id
}
func media(_ path: String, _ seconds: Ticks) -> UInt32 {
    let descriptor = MediaDescriptor(
        path: path, kind: .video, duration: seconds * second, width: 320, height: 180,
        fps: .thirty, hasVideo: true, hasAudio: true)
    step(.addMedia(descriptor: descriptor))
    return project.snapshot.media.last?.id ?? 0
}

let short = media("/fixtures/ramp-ui.mov", 10)
let long = media("/fixtures/ramp-ui-long.mov", 60)
guard let track = project.snapshot.tracks.first?.id else {
    out["error"] = "no track"
    emit()
}
step(.addClip(track: track, media: short, at: 0))
let one = lastClip()
step(.trimStart(clip: one, to: second / 2))
step(.trimEnd(clip: one, to: second / 2 + 5 * second))
let actionA = action(one, at: 0, duration: 2 * second, ["speed": 2])
let actionB = action(one, at: 3 * second, duration: second, ["video": ["opacity": 0.5]])

step(.addClip(track: track, media: short, at: 6 * second))
let two = lastClip()
step(.trimEnd(clip: two, to: 8 * second))
let pastAction = action(two, at: 0, duration: 2 * second, ["speed": 3])
step(.trimEnd(clip: two, to: 7 * second))

step(.addClip(track: track, media: long, at: 10 * second))
let clipP = lastClip()
step(.trimEnd(clip: clipP, to: 10 * second + second / 2))
let actionP = action(clipP, at: 0, duration: second / 2, ["speed": 2])

step(.addClip(track: track, media: long, at: 12 * second))
let clipQ = lastClip()
step(.setSpeed(clip: clipQ, rate: 13))
step(.trimEnd(clip: clipQ, to: 12 * second + second / 2))
let actionQ = action(clipQ, at: 0, duration: second / 2, ["speed": 13])

step(.addClip(track: track, media: long, at: 14 * second))
let clipR = lastClip()
step(.setSpeed(clip: clipR, rate: 2))
step(.trimEnd(clip: clipR, to: 14 * second + second / 2))

if !problems.isEmpty {
    out["error"] = "the fixtures were not made"
    emit()
}
func clipFacts(_ id: UInt32) -> [String: Any] {
    guard let clip = project.snapshot.clip(id) else { return [:] }
    return ["id": Int(id), "start": Int(clip.start), "duration": Int(clip.duration),
            "in": Int(clip.source.sourceIn), "speed": clip.speed,
            "actions": clip.actions.map {
                ["id": Int($0.id), "start": Int($0.start), "duration": Int($0.duration),
                 "speed": $0.end.speed as Any? ?? NSNull()]
            }]
}
out["clips"] = ["one": clipFacts(one), "two": clipFacts(two), "P": clipFacts(clipP),
                "Q": clipFacts(clipQ), "R": clipFacts(clipR)]
out["ids"] = ["A": Int(actionA), "B": Int(actionB), "past": Int(pastAction),
              "P": Int(actionP), "Q": Int(actionQ)]

let package = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("ramp-ui.framejob")
try? FileManager.default.removeItem(at: package)
do {
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try project.json.write(
        to: package.appendingPathComponent("project.json"), atomically: true, encoding: .utf8)
} catch {
    out["error"] = "the package could not be written: \(error)"
    emit()
}
let document = ProjectDocument()
do {
    try document.read(from: package, ofType: ProjectDocument.projectTypeIdentifier)
} catch {
    out["error"] = "the package did not open: \(error)"
    emit()
}
let inspector = InspectorViewController()
inspector.document = document
let binding = inspector.binding

/// The selection `clips`, the playhead at `t`, and `action` selected.
func select(_ clips: Set<UInt32>, playhead t: Ticks, action: UInt32?) {
    document.selection = clips
    document.playhead = t
    document.selectAction(action)
    binding.invalidate()
}
let startOne = project.snapshot.clip(one)?.start ?? 0
let startTwo = project.snapshot.clip(two)?.start ?? 0

/// The Speed section's rows on the Clip sub-tab of a fresh pane.
func speedRows() -> (rate: InspectorRowView?, keep: InspectorRowView?, fit: InspectorRowView?) {
    let pane = ClipPane(inspector: inspector)
    pane.choose(.clip)
    pane.rebuild()
    pane.refresh()
    func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
    guard let section = pane.sections.first(where: { $0.id == "video.speed" }) else {
        return (nil, nil, nil)
    }
    let rows = walk(section).compactMap { $0 as? InspectorRowView }
    func labelled(_ text: String) -> InspectorRowView? {
        rows.first { row in
            row.arrangedSubviews.contains { ($0 as? InspectorRowLabel)?.stringValue == text }
        }
    }
    let keep = rows.first { row in row.arrangedSubviews.contains { $0 is OptionCheckboxControl } }
    return (labelled("Rate"), keep, labelled("Fit to"))
}

// MARK: - G1 Rate's writes, Keep pitch at the base

var g1: [String: Any] = [:]
select([one], playhead: startOne + second, action: actionA)
g1["A"] = describe(VideoPane.rateOps(binding, rate: 3))
let rowsA = speedRows()
g1["keep_pitch"] = [
    "ops": describe(rowsA.keep?.gutter.default?.ops() ?? []),
    "writes": rowsA.keep?.gutter.writes ?? [],
    "mark": markName(rowsA.keep?.gutter.mark),
]
g1["fit"] = ["writes": rowsA.fit?.gutter.writes ?? [], "mark": markName(rowsA.fit?.gutter.mark)]
g1["base_rate"] = VideoPane.baseRate(binding)
select([one], playhead: startOne + 3 * second + second / 2, action: actionB)
g1["B"] = describe(VideoPane.rateOps(binding, rate: 3))
select([one], playhead: startOne + 5 * second / 2, action: nil)
g1["none"] = describe(VideoPane.rateOps(binding, rate: 3))
select([one, two], playhead: startOne + 5 * second / 2, action: nil)
g1["two"] = describe(VideoPane.rateOps(binding, rate: 3))
out["G1"] = g1

// MARK: - G2 Rate's read

var g2: [String: Any] = [:]
select([one], playhead: startOne + 5 * second / 2, action: actionA)
g2["A"] = VideoPane.rateRead(binding)
select([one], playhead: startOne + 5 * second / 2, action: actionB)
g2["B"] = VideoPane.rateRead(binding)
select([one], playhead: startOne + 5 * second / 2, action: nil)
g2["none"] = VideoPane.rateRead(binding)
select([one], playhead: startOne + second, action: nil)
g2["playhead"] = binding.at(.playhead) { VideoPane.rateRead(binding) }
g2["now"] = binding.nowValue { VideoPane.rateRead(binding) } as Any? ?? NSNull()
select([two], playhead: startTwo + second / 2, action: pastAction)
g2["past"] = VideoPane.rateRead(binding)
g2["past_selected"] = document.selectedAction.map { Int($0) } as Any? ?? NSNull()
out["G2"] = g2

// MARK: - G3 the band

var zoomEnd = VideoPatch()
(zoomEnd.scale, zoomEnd.x, zoomEnd.y) = (2, 10, 20)
let zoom = ActionSnapshot(id: 1, end: ActionPatch(video: zoomEnd))
let zoomRate = ActionSnapshot(id: 2, end: ActionPatch(video: zoomEnd, speed: 2))
let ramp = actions(one).first { $0.id == actionA }
out["G3"] = [
    "keys_A": ramp.map { ActionBands.keys(of: $0.end) } ?? [],
    "keys_zoom_rate": ActionBands.keys(of: zoomRate.end),
    "keys_zoom": ActionBands.keys(of: zoom.end),
    "zoom": ActionBands.isZoom(zoom), "zoom_rate": ActionBands.isZoom(zoomRate),
    "A_zoom": ramp.map { ActionBands.isZoom($0) } ?? true,
]

// MARK: - G4 the ×12 question

let speedEnd = ReelOp.setActionEnd(clip: clipP, action: actionP, patch: ActionPatch(speed: 14))
var opacityEnd = VideoPatch()
opacityEnd.opacity = 0.5
out["G4_may"] = [
    "end_speed": SpeedAudioDrop.mayCross([speedEnd]),
    "end_opacity": SpeedAudioDrop.mayCross(
        [.setActionEnd(clip: one, action: actionB, patch: ActionPatch(video: opacityEnd))]),
    "set_action": SpeedAudioDrop.mayCross(
        [.setAction(clip: one, action: actionA, curve: .easeIn)]),
    "set_speed": SpeedAudioDrop.mayCross([.setSpeed(clip: one, rate: 2)]),
]
func arm(_ ops: [ReelOp]) -> (String, ReelProject?) {
    do {
        switch try project.applying(ops) {
        case .applied(let next): return ("applied", next)
        case .identity: return ("identity", nil)
        case .refused(let why): return ("refused: " + why.reason, nil)
        }
    } catch {
        return ("error: \(error)", nil)
    }
}
var trials: [[String: Any]] = []
var noteP: Any = NSNull()
for (name, clip, action, rate) in [
    ("P14", clipP, actionP, 14.0), ("P12", clipP, actionP, 12.0), ("Q14", clipQ, actionQ, 14.0),
] {
    let ops: [ReelOp] = [.setActionEnd(clip: clip, action: action, patch: ActionPatch(speed: rate))]
    let (outcome, after) = arm(ops)
    let crossing = SpeedAudioDrop.crossing(applying: ops, to: project)
    trials.append([
        "name": name, "clip": Int(clip), "arm": outcome, "may": SpeedAudioDrop.mayCross(ops),
        "crossing": crossing.map { ["id": Int($0.id), "speed": $0.speed] },
    ])
    if name == "P14", let after, let applied = after.snapshot.clip(clipP) {
        noteP = VideoPane.silentAudioNote(
            for: [applied], in: after.snapshot, limits: ReelSpeed.limits) as Any? ?? NSNull()
    }
}
let constant = project.snapshot.clip(clipR).map {
    VideoPane.silentAudioNote(for: [$0], in: project.snapshot, limits: ReelSpeed.limits)
}
out["G4"] = [
    "trials": trials, "note_P14": noteP, "note_R": constant.flatMap { $0 } as Any? ?? NSNull(),
    "audio_max": ReelSpeed.limits.audioMax,
]

// MARK: - G5 the `speed` path

var g5: [String: Any] = [:]
select([one], playhead: startOne + second, action: actionA)
g5["set_speed"] = InspectorBinding.paths(of: [.setSpeed(clip: one, rate: 2)])
g5["rate_A"] = InspectorBinding.paths(of: VideoPane.rateOps(binding, rate: 3))
g5["keyed_A"] = Array(binding.keyedPaths()).sorted()
g5["clear"] = describe(binding.clearOps(["speed"]))
g5["count_A"] = ramp.map { ClipSubTab.clip.keyedCount(in: $0.end) } ?? -1
g5["count_B"] = actions(one).first { $0.id == actionB }.map {
    ClipSubTab.clip.keyedCount(in: $0.end)
} ?? -1
g5["rate_mark_A"] = markName(speedRows().rate?.gutter.mark)
select([one], playhead: startOne + 5 * second / 2, action: nil)
g5["rate_mark_none"] = markName(speedRows().rate?.gutter.mark)
out["G5"] = g5

// MARK: - G6 the Speed sheet

let edited = document.editedProject
let rampedLines = SpeedSheetController.readout(
    of: [one], rate: 2, keepPitch: false, in: edited
).components(separatedBy: "\n")
let trial = SpeedSheetController.trial(of: [one], rate: 2, keepPitch: false, in: edited)
let constantLines = SpeedSheetController.readout(
    of: [clipR], rate: 1, keepPitch: false, in: edited
).components(separatedBy: "\n")
out["G6"] = [
    "ramped": rampedLines, "constant": constantLines, "ramp_line": SpeedSheetController.rampLine,
    "trial_A": trial.clip(one)?.actions.first { $0.id == actionA }?.end.speed as Any? ?? NSNull(),
    "trial_speed": trial.clip(one)?.speed ?? 0,
]

emit()
