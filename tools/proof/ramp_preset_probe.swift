// Speed ramp presets (#340, spec §11 SR-24): the A rows' readings for
// `ramp_preset_proof.py`, compiled as `main.swift` over `app/Sources` through
// `swift_build.build()`. Prints one JSON object on stdout: what
// `SpeedRampSheetController`'s span, op and readout and `SpeedAudioDrop`'s
// crossing answer on in-process projects. The proof scores every reading;
// this file decides nothing. No network, no app, no defaults written.
//
// The project is made in-process (`ReelProject.new`, 30 fps):
//   X   a 5 s A/V media with no file, a clip at 0 from in 0, `trim_end` to
//       2 s — the MCP rows' AV.mov fixture, 3 s of media past its out point
//   Y   the same media at 3 s, `trim_end` to 2 s: A1's clip off the origin
//   G   a copy of the project with an opacity action on X at clip time
//       0.9 s for 0.2 s, inside a whole-clip dip's hold gap

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let second: Ticks = 600_000
let frame: Ticks = 20_000
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
    if let number = value as? Double { return number }
    if let number = value as? Int { return number }
    if let number = value as? UInt32 { return Int(number) }
    if let number = value as? Int64 { return Int(number) }
    if let flag = value as? Bool { return flag }
    if let text = value as? String { return text }
    return String(describing: value)
}

guard var project = ReelProject.new(width: 320, height: 180, fps: .thirty) else {
    out["error"] = "ReelProject.new answered nil"
    emit()
}
/// Applied or an identity; a refusal or an error is a problem.
func step(_ op: ReelOp) {
    switch try? project.applying(op) {
    case .applied(let next)?: project = next
    case .identity?: break
    case .refused(let why)?: problems.append("\(op.name) refused: \(why.reason)")
    case nil: problems.append("\(op.name) was invalid: \(op.args)")
    }
}
func lastClip() -> UInt32 { project.snapshot.clips.max { $0.id < $1.id }?.id ?? 0 }

let descriptor = MediaDescriptor(
    path: "/fixtures/ramp-preset.mov", kind: .video, duration: 5 * second, width: 320,
    height: 180, fps: .thirty, hasVideo: true, hasAudio: true)
step(.addMedia(descriptor: descriptor))
let media = project.snapshot.media.last?.id ?? 0
guard let track = project.snapshot.tracks.first?.id else {
    out["error"] = "no track"
    emit()
}
step(.addClip(track: track, media: media, at: 0))
let clipX = lastClip()
step(.trimEnd(clip: clipX, to: 2 * second))
step(.addClip(track: track, media: media, at: 3 * second))
let clipY = lastClip()
step(.trimEnd(clip: clipY, to: 5 * second))
let plainProject = project
step(.addAction(clip: clipX, at: 27 * frame, duration: 6 * frame))
let gapAction = project.snapshot.clip(clipX)?.actions.last?.id ?? 0
step(.setActionEndRaw(clip: clipX, action: gapAction, patch: ["video": ["opacity": 0.5]]))
let gapProject = project
project = plainProject

guard problems.isEmpty, let x = project.snapshot.clip(clipX), let y = project.snapshot.clip(clipY)
else {
    out["error"] = "the fixtures were not made"
    emit()
}
func facts(_ clip: ClipSnapshot) -> [String: Any] {
    ["id": Int(clip.id), "start": Int(clip.start), "duration": Int(clip.duration)]
}
out["clips"] = ["X": facts(x), "Y": facts(y)]
out["gap_action"] = Int(gapAction)
out["media_duration"] = Int(project.snapshot.media.last?.duration ?? 0)

// MARK: - A1 the span

func spanAnswer(_ range: (start: Ticks, end: Ticks)?) -> Any {
    guard let span = SpeedRampSheetController.span(of: y, range: range) else { return NSNull() }
    return [Int(span.from), Int(span.to)]
}
out["A1"] = [
    "inside": spanAnswer((3 * second + second / 2, 4 * second + second / 2)),
    "past_end": spanAnswer((4 * second + second / 2, 5 * second + second / 2)),
    "before_start": spanAnswer((2 * second + second / 2, 3 * second + second / 2)),
    "empty": spanAnswer((4 * second, 4 * second)),
    "absent": spanAnswer(nil),
    "exact": spanAnswer((3 * second, 5 * second)),
]

// MARK: - A2 the op

func opArgs(_ op: ReelOp) -> [String: Any] {
    ["name": op.name, "args": plain(op.args)]
}
let rangeX: (from: Ticks, to: Ticks) = (second / 2, 3 * second / 2)
out["A2"] = [
    "dip": opArgs(SpeedRampSheetController.op(
        clip: clipX, shape: .speedDip, rate: 0.5, curve: .easeInOut, hold: 0.25, span: nil)),
    "burst": opArgs(SpeedRampSheetController.op(
        clip: clipX, shape: .speedBurst, rate: 2, curve: .easeInOut, hold: 0, span: rangeX)),
    "up": opArgs(SpeedRampSheetController.op(
        clip: clipX, shape: .rampUp, rate: 2, curve: .linear, hold: 0.25, span: rangeX)),
    "down": opArgs(SpeedRampSheetController.op(
        clip: clipX, shape: .rampDown, rate: 0.5, curve: .easeInOut, hold: 0.75, span: nil)),
    "defaults": SpeedRampShape.allCases.map {
        [$0.rawValue, SpeedRampSheetController.defaultRate(for: $0)] as [Any]
    },
    "holds": SpeedRampSheetController.holds,
    "names": SpeedRampShape.allCases.map(\.displayName),
]

// MARK: - A3 / A4 the readout

func readout(
    _ shape: SpeedRampShape, rate: Double, curve: Curve = .easeInOut, hold: Double = 0.5,
    span: (from: Ticks, to: Ticks)?, in project: ReelProject
) -> [String: Any] {
    let op = SpeedRampSheetController.op(
        clip: clipX, shape: shape, rate: rate, curve: curve, hold: hold, span: span)
    let read = SpeedRampSheetController.readout(
        of: op, clip: clipX, shape: shape, span: span, in: project)
    return ["lines": read.lines, "can_apply": read.canApply]
}
let fps = project.snapshot.canvas.fps
out["tc"] = Dictionary(
    uniqueKeysWithValues: [0, second / 2, 3 * second / 2, 2 * second].map {
        (String($0), ReelTime.format($0, fps: fps, frames: true))
    })
out["A3"] = [
    "dip": readout(.speedDip, rate: 0.5, span: nil, in: project),
    "up": readout(.rampUp, rate: 2, curve: .linear, span: rangeX, in: project),
]
out["A4"] = [
    "overrun": readout(.rampUp, rate: 10, curve: .linear, span: nil, in: project),
    "overlap": readout(.speedDip, rate: 0.5, span: nil, in: gapProject),
    "direction": readout(.rampUp, rate: 0.5, span: nil, in: project),
]

// MARK: - A5 the ×12 question

let lastSix: (from: Ticks, to: Ticks) = (2 * second - 6 * frame, 2 * second)
func crossing(_ rate: Double) -> [Int] {
    let op = SpeedRampSheetController.op(
        clip: clipX, shape: .rampUp, rate: rate, curve: .easeInOut, hold: 0.5, span: lastSix)
    return SpeedAudioDrop.crossing(applying: [op], to: project).map { Int($0.id) }
}
out["A5"] = [
    "x14": crossing(14),
    "x12": crossing(12),
    "may_cross": SpeedAudioDrop.mayCross([
        SpeedRampSheetController.op(
            clip: clipX, shape: .speedDip, rate: 0.5, curve: .easeInOut, hold: 0.5, span: nil)
    ]),
]

emit()
