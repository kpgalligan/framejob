// tools/proof/volume_line_probe.swift — the in-process instrument behind
// `volume_line_proof.py --probe` (road map "audio" AP8a, spec §11
// AU-80…AU-84). Compiled AS `main.swift` with every file in `app/Sources` but
// the app's own `main.swift` through `swift_build.py`'s line, with the app's
// `Compositor.metal` built into a `default.metallib` beside the binary.
//
//     volume_line_probe <work-dir>
//
// One line per row, `ok <ID> — <detail>` or `FAIL <ID> — <detail>`; no app is
// launched. The fixture is built by ops: a 10 s audio file written here, its
// media on three tracks — track A at volume 0.5 holding the MAIN clip (volume
// 0.5, a 0.5 s fade in, a linear volume action [1 s, 2 s) to 2.0, a pan-only
// action [3 s, 4 s)); track B a clip at 6 s ducking by extent; track C, muted,
// a second clip at 0. `eased` is the same with the volume action ease in-out.
//
//  V1  the drawn polyline's vertices equal the plan's ramps for the main clip
//      through the scale (≤ 0.01 pt), on a rect computed here (the audio
//      region below the action lane, inset 1 pt); one point, at the volume
//      action's end, none at the pan action's; the muted clip's line on the
//      floor.
//  V2  `VolumeScale`: y(32) top, y(1) 30.103/90.103 down, y(0) bottom, and
//      `decibels` its inverse within 1e-9 dB.
//  V3  targets at 0.5, 1.5, 2.5, 3.5 and 4.5 s: base, then the volume action.
//  V4  the drag's arithmetic through `VolumeLineSession`.
//  V5  ⌥ at 5 s: `add_action` from 4 s (the pan action's end), the end on
//      `next_id`; applied, the gain unchanged everywhere; ⌥ at 2 s and 4 s nil.
//  V6  ⌥ at 1.25 s splits the volume action and keeps the evaluated volume;
//      ⌥ at 1 s and 3.5 s nil; an eased split keeps the curve on both halves
//      and the values at t and 2 s; ⌥ inside an action a trim left past the
//      clip's end nil.
//  V7  an offscreen `EditorViewController`: a drag on the line is one undo
//      step "Set Volume", a ⌥ click one step "Add Volume Point".
//  V8  the hit order and `resolvingVolumeLine`, and a ⇧-press on a line.
//  V9  the clip painted with and without the line differs on it and not 4 pt
//      off it.
import AVFoundation
import AppKit

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
UserDefaults.standard.setVolatileDomain(
    [EditorViewController.inspectorWidthKey: 304.0, EditorViewController.timelineHeightKey: 300.0,
     EditorViewController.inspectorCollapsedKey: false],
    forName: UserDefaults.argumentDomain)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

let SEC: Ticks = 600_000

func row(_ id: String, _ ok: Bool, _ detail: String) {
    print("\(ok ? "ok" : "FAIL") \(id) — \(detail)")
    fflush(stdout)
}

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

func f(_ x: Double) -> String { String(format: "%.6f", x) }
func f(_ x: CGFloat) -> String { String(format: "%.3f", Double(x)) }

guard CommandLine.arguments.count == 2 else {
    row("V1", false, "usage: volume_line_probe <work-dir>")
    exit(0)
}
let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

// MARK: - The fixture

/// 10 s of a quiet 440 Hz sine, mono 48 kHz, so the media is real.
func writeTone() -> URL? {
    let url = work.appendingPathComponent("tone.caf")
    try? FileManager.default.removeItem(at: url)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1),
          let file = try? AVAudioFile(forWriting: url, settings: format.settings),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480_000)
    else { return nil }
    buffer.frameLength = 480_000
    let data = buffer.floatChannelData![0]
    for i in 0..<480_000 { data[i] = 0.1 * Float(sin(2 * Double.pi * 440 * Double(i) / 48_000)) }
    do { try file.write(from: buffer) } catch { return nil }
    return url
}

struct Fixture {
    let ops: [ReelOp]
    let project: ReelProject
    let main: UInt32
    let ducker: UInt32
    let muted: UInt32
    let volumeAction: UInt32
    let panAction: UInt32
}

func apply(_ project: ReelProject, _ ops: [ReelOp]) -> ReelProject? {
    var current = project
    for op in ops {
        guard case .applied(let next)? = try? current.applying(op) else { return nil }
        current = next
    }
    return current
}

/// The fixture's ops from a blank project, applied one at a time so each new
/// id is read off `next_id` before the op that makes it.
func fixture(tone: URL, eased: Bool) -> Fixture? {
    guard var p = ReelProject.new(width: 1920, height: 1080, fps: .thirty) else { return nil }
    var ops: [ReelOp] = []
    func run(_ op: ReelOp) -> Bool {
        guard let next = apply(p, [op]) else {
            let answer = (try? p.applying(op)).map { "\($0)" } ?? "an invalid op"
            FileHandle.standardError.write(Data("fixture: \(op.json) → \(answer)\n".utf8))
            return false
        }
        ops.append(op)
        p = next
        return true
    }
    guard run(.addTrack(index: 1)), run(.addTrack(index: 2)) else { return nil }
    let tracks = p.snapshot.tracks.map(\.id)
    guard tracks.count == 3 else { return nil }
    let media = p.snapshot.nextId
    guard run(.addMedia(descriptor: MediaDescriptor(
        path: tone.path, kind: .audio, duration: 10 * SEC, hasAudio: true)))
    else { return nil }
    let main = p.snapshot.nextId
    guard run(.addClip(track: tracks[0], media: media, at: 0)) else { return nil }
    let ducker = p.snapshot.nextId
    guard run(.addClip(track: tracks[1], media: media, at: 6 * SEC)) else { return nil }
    let muted = p.snapshot.nextId
    guard run(.addClip(track: tracks[2], media: media, at: 0)),
          run(.setTrack(track: tracks[2], muted: true)),
          run(.setTrack(track: tracks[0], volume: 0.5)),
          run(.setAudio(clips: [main], patch: AudioPatch(volume: 0.5, fadeIn: SEC / 2))),
          run(.setAudio(clips: [ducker], patch: AudioPatch(duck: .some(DuckProps()))))
    else { return nil }
    let volumeAction = p.snapshot.nextId
    // The core's default curve is linear, so only the eased fixture sets one.
    guard run(.addAction(clip: main, at: SEC, duration: SEC)),
          !eased || run(.setAction(clip: main, action: volumeAction, curve: .easeInOut)),
          run(.setActionEnd(
              clip: main, action: volumeAction,
              patch: ActionPatch(audio: AudioPatch(volume: 2.0))))
    else { return nil }
    let panAction = p.snapshot.nextId
    guard run(.addAction(clip: main, at: 3 * SEC, duration: SEC)),
          run(.setActionEnd(
              clip: main, action: panAction, patch: ActionPatch(audio: AudioPatch(pan: -0.5))))
    else { return nil }
    return Fixture(
        ops: ops, project: p, main: main, ducker: ducker, muted: muted,
        volumeAction: volumeAction, panAction: panAction)
}

guard let tone = writeTone(), let fx = fixture(tone: tone, eased: false),
      let eased = fixture(tone: tone, eased: true),
      let mainClip = fx.project.snapshot.clip(fx.main),
      let mutedClip = fx.project.snapshot.clip(fx.muted)
else {
    for id in ["V1", "V2", "V3", "V4", "V5", "V6", "V7", "V8", "V9"] {
        row(id, false, "the fixture did not build")
    }
    exit(0)
}

/// The plan's ramps for `clip`, cut to its audio segment — read here, from
/// the plan's JSON shape, not through `VolumeLines`.
func planRamps(_ project: ReelProject, _ clip: UInt32) -> [(Ticks, Ticks, Double, Double)] {
    for track in project.plan?.audioTracks ?? [] {
        let segments = track.segments.filter { $0.clip == clip }
        guard let first = segments.first else { continue }
        let from = segments.map(\.start).min() ?? first.start
        let to = segments.map { $0.start + $0.duration }.max() ?? first.start
        var out: [(Ticks, Ticks, Double, Double)] = []
        for r in track.ramps ?? [] {
            let s = max(r.start, from)
            let e = min(r.start + r.duration, to)
            guard e > s else { continue }
            func v(_ t: Ticks) -> Double {
                r.duration > 0 ? r.from + (r.to - r.from) * Double(t - r.start) / Double(r.duration)
                    : r.to
            }
            out.append((s, e, v(s), v(e)))
        }
        return out
    }
    return []
}

/// The gain of `ramps` at `t`.
func gain(_ ramps: [(Ticks, Ticks, Double, Double)], _ t: Ticks) -> Double? {
    for r in ramps where r.0 <= t && t < r.1 {
        return r.2 + (r.3 - r.2) * Double(t - r.0) / Double(r.1 - r.0)
    }
    return nil
}

func evaluated(_ project: ReelProject, _ clip: UInt32, _ t: Ticks) -> Double? {
    (project.clipState(clip, at: t)?["audio"] as? [String: Any])?["volume"] as? Double
}

/// The y of `gain` on `rect` (the scale's own rect), computed here.
func expectedY(_ gain: Double, _ rect: CGRect) -> CGFloat {
    let top = 20 * log10(32.0)
    let floor = -60.0
    let db = gain > 0.001 ? min(max(20 * log10(gain), floor), top) : floor
    return rect.minY + CGFloat((top - db) / (top - floor)) * rect.height
}

// MARK: - The editor

let document = ProjectDocument()
document.performGroupedEdit("Fixture", fx.ops)
document.undoManager?.removeAllActions()
let controller = EditorViewController(document: document)
controller.trackHeight = 2
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1600, height: 1000),
    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
window.contentViewController = controller
window.setContentSize(NSSize(width: 1600, height: 1000))
controller.viewWillAppear()
controller.viewDidAppear()
controller.refreshFromDocument(isLive: false)
spin(0.6)
guard let timeline = controller.timeline else {
    for id in ["V1", "V7", "V8", "V9"] { row(id, false, "no timeline") }
    exit(0)
}
timeline.setZoom(100, anchoredAt: TimelineLayout.headerWidth)
spin(0.3)
let content = timeline.content

func clipRect(_ id: UInt32) -> CGRect {
    let snapshot = document.editedProject.snapshot
    guard let clip = snapshot.clip(id),
          let index = snapshot.tracks.firstIndex(where: { $0.id == clip.track })
    else { return .zero }
    return timeline.layout.clipRect(clip, row: timeline.layout.row(forTrackIndex: index))
}

/// The line's rect computed here: the audio region of an audio-only clip
/// (its whole content rect) with its top at the action lane's bottom.
func expectedRect(_ id: UInt32) -> CGRect {
    let contentRect = TimelineContentView.contentRect(clipRect(id))
    let lane = TimelineContentView.actionLane(
        content: contentRect, sizeIndex: timeline.trackHeightIndex)
    return CGRect(
        x: contentRect.minX, y: lane.maxY, width: contentRect.width,
        height: contentRect.maxY - lane.maxY)
}

// MARK: - V1 the drawn line

do {
    let snapshot = document.editedProject.snapshot
    let rect = expectedRect(fx.main)
    let scaleRect = rect.insetBy(dx: 0, dy: 1)
    let ramps = planRamps(document.editedProject, fx.main)
    var want: [CGPoint] = []
    for r in ramps {
        want.append(CGPoint(x: timeline.layout.x(for: r.0), y: expectedY(r.2, scaleRect)))
        want.append(CGPoint(x: timeline.layout.x(for: r.1), y: expectedY(r.3, scaleRect)))
    }
    let main = snapshot.clip(fx.main)
    let got = main.flatMap { content.volumeLineGeometry($0, rect: clipRect(fx.main), owner: timeline) }
    let vertices = got?.vertices ?? []
    let worst = zip(vertices, want).map { max(abs($0.x - $1.x), abs($0.y - $1.y)) }.max() ?? .infinity
    let distinct = Set(ramps.map { $0.2 } + ramps.map { $0.3 }).count
    let endX = timeline.layout.x(for: mainClip.start + 2 * SEC)
    let points = got?.points ?? []
    let pointOK = points.count == 1 && abs(points[0].x - endX) <= 0.01
        && abs(points[0].y - expectedY(gain(ramps, 2 * SEC) ?? -1, scaleRect)) <= 0.01
    let mutedGeometry = snapshot.clip(fx.muted).flatMap {
        content.volumeLineGeometry($0, rect: clipRect(fx.muted), owner: timeline)
    }
    let floorY = expectedRect(fx.muted).insetBy(dx: 0, dy: 1).maxY
    let mutedOK = !(mutedGeometry?.vertices.isEmpty ?? true)
        && mutedGeometry!.vertices.allSatisfy { abs($0.y - floorY) <= 0.01 }
    let rectOK = got.map { abs($0.rect.minY - rect.minY) <= 0.01 && abs($0.rect.maxY - rect.maxY) <= 0.01 } ?? false
    row("V1", vertices.count == want.count && !want.isEmpty && worst <= 0.01 && distinct >= 4
            && pointOK && mutedOK && rectOK,
        "\(vertices.count) vertices against \(want.count) from \(ramps.count) plan ramps "
            + "(\(distinct) distinct gains), worst \(f(worst)) pt; rect top \(got.map { f($0.rect.minY) } ?? "nil") "
            + "(want \(f(rect.minY)), the lane's bottom); points \(points.map { "(\(f($0.x)), \(f($0.y)))" }) "
            + "(want one at x \(f(endX))); muted clip's \(mutedGeometry?.vertices.count ?? 0) vertices "
            + "on the floor y \(f(floorY)): \(mutedOK)")
}

// MARK: - V2 the scale

do {
    let rect = CGRect(x: 0, y: 10, width: 100, height: 90)
    let scale = VolumeScale(rect: rect)
    let top = 20 * log10(32.0)
    let y1Want = 10 + 90 * top / (top + 60)
    let gains = [0.002, 0.01, 0.5, 1, 3, 20, 32]
    var worst = 0.0
    for a in gains {
        for b in gains {
            let d = scale.decibels(deltaY: scale.y(gain: a) - scale.y(gain: b))
            worst = max(worst, abs(d - (20 * log10(b) - 20 * log10(a))))
        }
    }
    let ok = abs(scale.y(gain: 32) - 10) <= 1e-9 && abs(Double(scale.y(gain: 1)) - y1Want) <= 1e-9
        && abs(scale.y(gain: 0) - 100) <= 1e-9 && worst <= 1e-9
        && abs(VolumeScale.topDB - top) <= 1e-12 && VolumeScale.floorDB == -60
    row("V2", ok,
        "y(32) \(f(scale.y(gain: 32))) (want 10), y(1) \(f(scale.y(gain: 1))) (want \(f(y1Want))), "
            + "y(0) \(f(scale.y(gain: 0))) (want 100); decibels' worst inverse error \(worst) dB")
}

// MARK: - V3 targets

do {
    let a = fx.volumeAction
    let cases: [(Double, VolumeLineTarget)] = [
        (0.5, .base(volume: 0.5)), (1.5, .end(action: a, volume: 2)),
        (2.5, .end(action: a, volume: 2)), (3.5, .end(action: a, volume: 2)),
        (4.5, .end(action: a, volume: 2)),
    ]
    var wrong: [String] = []
    for (seconds, want) in cases {
        let got = VolumeLine.target(of: mainClip, at: Ticks(seconds * Double(SEC)))
        if got != want { wrong.append("\(seconds) s → \(got) (want \(want))") }
    }
    row("V3", wrong.isEmpty,
        wrong.isEmpty ? "0.5 s base; 1.5, 2.5, 3.5 (inside the pan-only action) and 4.5 s "
            + "(after it) the volume action \(a)" : wrong.joined(separator: "; "))
}

// MARK: - V4 the drag's arithmetic

func patchVolume(_ op: ReelOp?) -> Double? {
    (op?.args["patch"] as? [String: Any]).flatMap { patch in
        (patch["volume"] as? Double) ?? ((patch["audio"] as? [String: Any])?["volume"] as? Double)
    }
}

do {
    let scale = VolumeScale(rect: CGRect(x: 0, y: 0, width: 200, height: 180))
    let six = 20 * log10(2.0)
    func session(_ target: VolumeLineTarget, pressY: CGFloat) -> VolumeLineSession {
        VolumeLineSession(
            clip: fx.main, target: target, prefix: [], pressY: pressY, scale: scale,
            volume: target.volume, point: CGPoint(x: 0, y: pressY))
    }
    var s = session(.base(volume: 0.5), pressY: 90)
    s.update(y: 90 - CGFloat(six / (VolumeScale.topDB - VolumeScale.floorDB)) * 180)
    let doubled = s.volume
    let op = s.ops.last
    let opOK = op?.name == "set_audio" && abs((patchVolume(op) ?? -1) - 1) <= 1e-9
        && s.undoName == "Set Volume"
    s.update(y: -1000)
    let clamped = s.volume
    s.update(y: scale.rect.maxY)
    let bottom = s.volume
    var z = session(.base(volume: 0), pressY: 90)
    z.update(y: 60)
    let fromZero = z.volume
    let zeroWant = 0.001 * pow(10, Double(30) / 180 * (VolumeScale.topDB - VolumeScale.floorDB) / 20)
    let mutedTarget = VolumeLine.target(of: mutedClip, at: 5 * SEC)
    let floorY = scale.y(gain: 0)
    var m = session(mutedTarget, pressY: floorY)
    m.update(y: floorY)
    let still = m.volume
    m.update(y: floorY - 1)
    let raised = m.volume
    let ok = abs(doubled - 1) <= 1e-9 && opOK && clamped == 32 && bottom == 0
        && abs(fromZero - zeroWant) <= 1e-12 && mutedTarget == .base(volume: 1)
        && still == 1 && raised > 1
    row("V4", ok,
        "+6.0206 dB from 0.5 → \(f(doubled)) (op \(op?.name ?? "nil") \(patchVolume(op).map(f) ?? "nil")); "
            + "far up → \(clamped); to the bottom → \(bottom); from 0 by 30 pt → \(fromZero) "
            + "(want \(zeroWant)); the muted clip's floor line (target \(mutedTarget)): a 0 pt move "
            + "\(still), 1 pt up \(f(raised))")
}

// MARK: - V5 a point after the last action

let frameFps = fx.project.snapshot.canvas.fps
do {
    let next = fx.project.snapshot.nextId
    let made = VolumeLine.point(
        on: mainClip, at: 5 * SEC, project: fx.project, nextId: next, fps: frameFps)
    let want = ReelOp.addAction(clip: fx.main, at: 4 * SEC, duration: SEC)
    let prefixOK = made.map { $0.prefix.count == 1 && $0.prefix[0].json == want.json } ?? false
    let held = evaluated(fx.project, fx.main, 5 * SEC)
    var unchanged = false
    var worst = Double.infinity
    if let made {
        let session = VolumeLineSession(
            clip: fx.main, target: .end(action: made.action, volume: made.volume),
            prefix: made.prefix, pressY: 0, scale: VolumeScale(rect: .zero), volume: made.volume,
            point: .zero)
        if let after = apply(fx.project, session.ops) {
            let before = planRamps(fx.project, fx.main)
            let now = planRamps(after, fx.main)
            worst = 0
            for frame in 0..<300 {
                let t = Ticks(frame) * SEC / 30
                guard let a = gain(before, t), let b = gain(now, t) else {
                    worst = .infinity
                    break
                }
                worst = max(worst, abs(a - b))
            }
            unchanged = worst <= 1e-9 && session.undoName == "Add Volume Point"
                && after.snapshot.clip(fx.main)?.actions.count == 3
        }
    }
    let atEnd = VolumeLine.point(on: mainClip, at: 2 * SEC, project: fx.project, nextId: next, fps: frameFps)
    let atPan = VolumeLine.point(on: mainClip, at: 4 * SEC, project: fx.project, nextId: next, fps: frameFps)
    row("V5", prefixOK && made?.action == next && made?.volume == held && unchanged
            && atEnd == nil && atPan == nil,
        "⌥ at 5 s: \(made.map { $0.prefix.map(\.json).joined(separator: ", ") } ?? "nil") "
            + "(want \(want.json)), action \(made.map { "\($0.action)" } ?? "nil") (want \(next)), "
            + "from \(made.map { f($0.volume) } ?? "nil") (held \(held.map(f) ?? "nil")); applied, "
            + "the gain's worst change over 300 frames \(worst); ⌥ at 2 s \(atEnd == nil ? "nil" : "a point"), "
            + "at 4 s \(atPan == nil ? "nil" : "a point")")
}

// MARK: - V6 splitting a volume action

func split(_ fixture: Fixture, at t: Ticks) -> (ReelProject, (prefix: [ReelOp], action: UInt32, volume: Double))? {
    guard let clip = fixture.project.snapshot.clip(fixture.main),
          let made = VolumeLine.point(
              on: clip, at: t, project: fixture.project, nextId: fixture.project.snapshot.nextId,
              fps: frameFps)
    else { return nil }
    let session = VolumeLineSession(
        clip: fixture.main, target: .end(action: made.action, volume: made.volume),
        prefix: made.prefix, pressY: 0, scale: VolumeScale(rect: .zero), volume: made.volume,
        point: .zero)
    return apply(fixture.project, session.ops).map { ($0, made) }
}

do {
    let at = Ticks(1.25 * Double(SEC))
    var linearOK = false
    var worst = Double.infinity
    var detail = "no split"
    if let (after, made) = split(fx, at: at) {
        worst = 0
        for i in 0..<20 {
            let t = SEC + Ticks(i) * SEC / 20
            let a = evaluated(fx.project, fx.main, t) ?? .nan
            let b = evaluated(after, fx.main, t) ?? .nan
            worst = max(worst, abs(a - b).isNaN ? .infinity : abs(a - b))
        }
        let actions = after.snapshot.clip(fx.main)?.actions.count ?? 0
        linearOK = worst <= 1e-9 && made.action == fx.volumeAction && actions == 3
        detail = "linear split: \(actions) actions, the evaluated volume's worst change at 20 "
            + "times in [1 s, 2 s) \(worst)"
    }
    let atStart = VolumeLine.point(
        on: mainClip, at: SEC, project: fx.project, nextId: fx.project.snapshot.nextId, fps: frameFps)
    let inPan = VolumeLine.point(
        on: mainClip, at: Ticks(3.5 * Double(SEC)), project: fx.project,
        nextId: fx.project.snapshot.nextId, fps: frameFps)
    var easedOK = false
    var easedDetail = "no eased split"
    if let (after, _) = split(eased, at: at), let clip = after.snapshot.clip(eased.main) {
        let t = ReelTime.snapToFrame(at, fps: frameFps)
        let halves = clip.actions.filter { $0.end.audio?.volume != nil }
        let curves = halves.map(\.curve)
        let atT = (evaluated(eased.project, eased.main, t), evaluated(after, eased.main, t))
        let atEnd = (evaluated(eased.project, eased.main, 2 * SEC), evaluated(after, eased.main, 2 * SEC))
        easedOK = halves.count == 2 && curves.allSatisfy { $0 == .easeInOut }
            && abs((atT.0 ?? .nan) - (atT.1 ?? -1)) <= 1e-9
            && abs((atEnd.0 ?? .nan) - (atEnd.1 ?? -1)) <= 1e-9
        easedDetail = "eased split: halves \(curves.map(\.rawValue)), at t \(atT.0.map(f) ?? "nil") → "
            + "\(atT.1.map(f) ?? "nil"), at 2 s \(atEnd.0.map(f) ?? "nil") → \(atEnd.1.map(f) ?? "nil")"
    }
    // The clip trimmed to 1.5 s keeps the volume action [1 s, 2 s) running
    // past its end (SR-22); `add_action` would refuse the split's second
    // half, so the press must beep (nil).
    var overrunOK = false
    var overrunDetail = "no trimmed fixture"
    if let trimmed = apply(fx.project, [.trimEnd(clip: fx.main, to: Ticks(1.5 * Double(SEC)))]),
       let clip = trimmed.snapshot.clip(fx.main),
       let action = clip.actions.first(where: { $0.id == fx.volumeAction }) {
        let made = VolumeLine.point(
            on: clip, at: Ticks(1.25 * Double(SEC)), project: trimmed,
            nextId: trimmed.snapshot.nextId, fps: frameFps)
        let overruns = action.endTime > clip.duration
        overrunOK = overruns && made == nil
        overrunDetail = "trimmed to 1.5 s, the action ends \(f(Double(action.endTime) / Double(SEC))) s "
            + "past the clip's \(f(Double(clip.duration) / Double(SEC))) s: \(overruns); ⌥ at 1.25 s "
            + "\(made == nil ? "nil" : "a point")"
    }
    row("V6", linearOK && atStart == nil && inPan == nil && easedOK && overrunOK,
        "\(detail); ⌥ at 1 s \(atStart == nil ? "nil" : "a point"), at 3.5 s "
            + "\(inPan == nil ? "nil" : "a point"); \(easedDetail); \(overrunDetail)")
}

// MARK: - V7 one undo step each, through the editor

/// A point on the main clip's line at `seconds`, `dy` below it.
func onLine(_ id: UInt32, seconds: Double, dy: CGFloat = 0) -> CGPoint? {
    let snapshot = document.editedProject.snapshot
    guard let clip = snapshot.clip(id),
          let geometry = content.volumeLineGeometry(clip, rect: clipRect(id), owner: timeline),
          let g = VolumeLines.gain(at: clip.start + Ticks(seconds * Double(SEC)), in: geometry.ramps)
    else { return nil }
    let x = timeline.layout.x(for: clip.start + Ticks(seconds * Double(SEC)))
    return CGPoint(x: x, y: geometry.scale.y(gain: g) + dy)
}

func press(_ point: CGPoint, flags: NSEvent.ModifierFlags = [], to end: CGPoint? = nil) {
    timeline.beginGesture(hit: content.hit(at: point), at: point, flags: flags, clicks: 1)
    if let end { timeline.continueGesture(at: end, flags: flags) }
    timeline.endGesture(at: end ?? point, flags: flags)
    spin(0.2)
}

do {
    let original = document.project.json
    var detail = "no point on the line"
    var ok = false
    if let p = onLine(fx.main, seconds: 5) {
        press(p, to: CGPoint(x: p.x, y: p.y - 20))
        let name = document.undoManager?.undoActionName ?? ""
        let moved = document.project.json != original
        document.undoManager?.undo()
        spin(0.2)
        let restored = document.project.json == original
        let first = name == "Set Volume" && moved && restored
        detail = "drag: \"\(name)\", changed \(moved), one undo restores \(restored)"
        if let q = onLine(fx.main, seconds: 5) {
            press(q, flags: [.option])
            let added = document.project.snapshot.clip(fx.main)?.actions.count ?? 0
            let name2 = document.undoManager?.undoActionName ?? ""
            document.undoManager?.undo()
            spin(0.2)
            let restored2 = document.project.json == original
            ok = first && name2 == "Add Volume Point" && added == 3 && restored2
            detail += "; ⌥ click: \"\(name2)\", \(added) actions, one undo restores \(restored2)"
        }
    }
    row("V7", ok, detail)
}

// MARK: - V8 the hit order and the modifiers

do {
    var notes: [String] = []
    var ok = true
    let rect = clipRect(fx.main)
    let audio = TimelineContentView.regions(
        in: TimelineContentView.contentRect(rect), hasVideo: false, hasAudio: true).audio
    let fade = TimelineContentView.fadeRect(mainClip, edge: .start, audio: audio, layout: timeline.layout)
    let fadePoint = CGPoint(x: fade.midX, y: fade.midY)
    let fadeHit = content.hit(at: fadePoint)
    ok = ok && fadeHit == .fade(fx.main, .start)
    notes.append("fade handle → \(fadeHit)")
    let lane = TimelineContentView.actionLane(
        content: TimelineContentView.contentRect(rect), sizeIndex: timeline.trackHeightIndex)
    let bandPoint = CGPoint(x: timeline.layout.x(for: mainClip.start + Ticks(1.5 * Double(SEC))), y: lane.midY)
    let bandHit = content.hit(at: bandPoint)
    ok = ok && bandHit == .action(clip: fx.main, action: fx.volumeAction)
    notes.append("band → \(bandHit)")
    if let grab = onLine(fx.main, seconds: 0.005) {
        let edgeHit = content.hit(at: grab)
        let lineThere = content.volumeLineHit(mainClip, rect: rect, at: grab) != nil
        ok = ok && edgeHit == .clipEdge(fx.main, .start) && lineThere
        notes.append("edge grab on the line → \(edgeHit) (the line alone takes it: \(lineThere))")
    } else {
        ok = false
    }
    if let near = onLine(fx.main, seconds: 5, dy: 2.999), let far = onLine(fx.main, seconds: 5, dy: 6) {
        let a = content.hit(at: near)
        let b = content.hit(at: far)
        var nearOK = false
        if case .volumeLine(let id, _) = a { nearOK = id == fx.main }
        ok = ok && nearOK && b == .clip(fx.main)
        notes.append("3 pt off → \(a); 6 pt off → \(b)")
    } else {
        ok = false
    }
    let line = TimelineHit.volumeLine(fx.main, 5 * SEC)
    let resolved: [(String, TimelineHit, TimelineHit)] = [
        ("⇧", line.resolvingVolumeLine(flags: [.shift], clicks: 1), .clip(fx.main)),
        ("⌥⇧", line.resolvingVolumeLine(flags: [.option, .shift], clicks: 1), .clip(fx.main)),
        ("double", line.resolvingVolumeLine(flags: [], clicks: 2), .clip(fx.main)),
        ("plain", line.resolvingVolumeLine(flags: [], clicks: 1), line),
        ("⌥", line.resolvingVolumeLine(flags: [.option], clicks: 1), line),
    ]
    let badResolve = resolved.filter { $0.1 != $0.2 }.map(\.0)
    ok = ok && badResolve.isEmpty
    notes.append("resolving: " + (badResolve.isEmpty ? "all five" : "wrong for " + badResolve.joined(separator: ", ")))
    // A ⇧-press on the muted clip's line with the main clip alone selected.
    document.selection = [fx.main]
    controller.refreshFromDocument(isLive: false)
    spin(0.2)
    if let p = onLine(fx.muted, seconds: 5) {
        let hit = content.hit(at: p)
        timeline.beginGesture(hit: hit, at: p, flags: [.shift], clicks: 1)
        let session = timeline.volumeDrag != nil
        timeline.endGesture(at: p, flags: [.shift])
        spin(0.2)
        let selection = document.selection
        var onLineHit = false
        if case .volumeLine = hit { onLineHit = true }
        ok = ok && onLineHit && !session && selection == [fx.main, fx.muted]
        notes.append("⇧-press on the muted clip's line (\(hit)): volume session \(session), "
            + "selection \(selection.sorted())")
    } else {
        ok = false
        notes.append("no muted line")
    }
    document.selection = []
    controller.refreshFromDocument(isLive: false)
    spin(0.2)
    row("V8", ok, notes.joined(separator: "; "))
}

// MARK: - V9 the paint

do {
    let rect = clipRect(fx.main).insetBy(dx: 0, dy: 0)
    func paint() -> NSBitmapImageRep? {
        content.needsDisplay = true
        guard let rep = content.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        content.cacheDisplay(in: rect, to: rep)
        return rep
    }
    func pixel(_ rep: NSBitmapImageRep, _ p: CGPoint) -> [CGFloat] {
        let sx = CGFloat(rep.pixelsWide) / rect.width
        let sy = CGFloat(rep.pixelsHigh) / rect.height
        let x = Int(((p.x - rect.minX) * sx).rounded(.down))
        let y = Int(((p.y - rect.minY) * sy).rounded(.down))
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return [] }
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
    }
    let lines = timeline.volumeLines
    let with = paint()
    timeline.volumeLines = nil
    let without = paint()
    timeline.volumeLines = lines
    content.needsDisplay = true
    let samples = [2.6, 5.0, 8.5].compactMap { onLine(fx.main, seconds: $0) }
    var differs = 0
    var same = 0
    if let with, let without, samples.count == 3 {
        for p in samples {
            if pixel(with, p) != pixel(without, p) { differs += 1 }
            let off = CGPoint(x: p.x, y: p.y - 4)
            if pixel(with, off) == pixel(without, off), !pixel(with, off).isEmpty { same += 1 }
        }
    }
    row("V9", differs == 3 && same == 3,
        "at 2.6, 5 and 8.5 s: \(differs)/3 pixels on the line differ with the line drawn, "
            + "\(same)/3 pixels 4 pt above it are the same")
}

exit(0)
