// Speed ramps SR4 (spec §11 SR-20): the F rows' readings for `ramp_proof.py`,
// compiled as `main.swift` over `app/Sources` through `swift_build.build()`.
// Prints one JSON object on stdout: what the readers answer for a ramped clip,
// its ×1.5 constant twin and its reversed twin, F4's ×1.5 Keep pitch off
// constant twin (spec §11 SR-28: its plan segment carries a constant `ramp`
// and no `source`), and F5's timings. The proof
// scores every reading against its own closed form; this file decides nothing.
// No network, no app, no defaults, no disk.
//
// Each project is in-process (`ReelProject.new`), with a 10 s A/V media that
// has no file (`addMedia(descriptor:)`, as `container_rewrap_probe.swift`
// adds one): a clip at 0, `trimStart` to 0.5 s (so it starts at 0.5 s from
// `in` 0.5 s), `trimEnd` to 5.5 s (D = 5 s), and on the ramped twins an
// action at clip time 0 for 2 s, `setAction` linear, `setActionEndRaw
// {speed: 2}`: S(t) = t + t²/4 s on [0, 2 s), then 3 s + 2(t − 2 s), so it
// reads S(5 s) = 9 s of the 10 s file.

import Foundation

let second: Ticks = 600_000
let frame: Ticks = 20_000
let start: Ticks = 300_000
let length: Ticks = 5 * second
let null = URL(fileURLWithPath: "/dev/null")
var out: [String: Any] = [:]
var problems: [String] = []

func flag(_ map: SourceMap?) -> Any { map.map { $0.ramped as Any } ?? NSNull() }

func pairs(_ map: SourceMap?) -> Any {
    map.map { m in m.points.map { [Int($0[0]), Int($0[1])] } } ?? NSNull()
}

/// One clip's project: `ramp` adds the speed action, `rate` a constant
/// speed (with `keepPitch`, nil the core's default), `reversed` plays it
/// backwards.
func make(
    ramp: Bool, rate: Double? = nil, reversed: Bool = false, keepPitch: Bool? = nil
) -> ReelProject? {
    guard var project = ReelProject.new(width: 320, height: 180, fps: .thirty) else { return nil }
    /// Applied or an identity; a refusal or an error is a problem.
    func step(_ op: ReelOp) -> Bool {
        switch try? project.applying(op) {
        case .applied(let next)?: project = next
        case .identity?: break
        case .refused(let why)?:
            problems.append("\(op.name) refused: \(why.reason)")
            return false
        case nil:
            problems.append("\(op.name) was invalid")
            return false
        }
        return true
    }
    let descriptor = MediaDescriptor(
        path: "/fixtures/ramp-mapper.mov", kind: .video, duration: 10 * second, width: 320,
        height: 180, fps: .thirty, hasVideo: true, hasAudio: true)
    guard step(.addMedia(descriptor: descriptor)),
          let media = project.snapshot.media.first?.id,
          let track = project.snapshot.tracks.first?.id,
          step(.addClip(track: track, media: media, at: 0)),
          let clip = project.snapshot.clips.last?.id,
          step(.trimStart(clip: clip, to: start)),
          step(.trimEnd(clip: clip, to: start + length))
    else { return nil }
    if ramp {
        guard step(.addAction(clip: clip, at: 0, duration: 2 * second)),
              let action = project.snapshot.clips.last?.actions.first?.id,
              step(.setAction(clip: clip, action: action, curve: .linear)),
              step(.setActionEndRaw(clip: clip, action: action, patch: ["speed": 2]))
        else { return nil }
    }
    if let rate, !step(.setSpeed(clip: clip, rate: rate, keepPitch: keepPitch)) { return nil }
    if reversed, !step(.setReversed(clip: clip, reversed: true)) { return nil }
    return project
}

func describe(_ project: ReelProject) -> [String: Any] {
    let snapshot = project.snapshot
    guard let clip = snapshot.clips.last, let media = snapshot.media(for: clip) else { return [:] }
    return ["clip": Int(clip.id), "start": Int(clip.start), "duration": Int(clip.duration),
            "in": Int(clip.source.sourceIn), "speed": clip.speed, "file": Int(media.duration)]
}

/// The plan's one audio segment of the project's clip.
func audioSegment(_ project: ReelProject) -> PlanSegment? {
    guard let id = project.snapshot.clips.last?.id else { return nil }
    return project.plan?.audioTracks.flatMap(\.segments).first { $0.clip == id }
}

guard let ramped = make(ramp: true), let constant = make(ramp: false, rate: 1.5),
      let reversed = make(ramp: true, reversed: true),
      let rampClip = ramped.snapshot.clips.last, let constClip = constant.snapshot.clips.last,
      let revClip = reversed.snapshot.clips.last,
      let rampMedia = ramped.snapshot.media(for: rampClip),
      let constMedia = constant.snapshot.media(for: constClip),
      let revMedia = reversed.snapshot.media(for: revClip)
else {
    let answer = ["error": "the fixtures were not made: " + problems.joined(separator: "; ")]
    print(String(data: try! JSONSerialization.data(withJSONObject: answer), encoding: .utf8)!)
    exit(0)
}
let rampMap = ramped.sourceMap(rampClip.id)
let constMap = constant.sourceMap(constClip.id)
let revMap = reversed.sourceMap(revClip.id)
out["clips"] = ["ramped": describe(ramped), "constant": describe(constant),
                "reversed": describe(reversed)]

// MARK: - F1: the map

let planRamp = audioSegment(ramped)?.ramp
out["F1"] = [
    "ramped": ["ramped": flag(rampMap), "map": pairs(rampMap)],
    "constant": ["ramped": flag(constMap), "map": pairs(constMap)],
    "reversed": ["ramped": flag(revMap), "map": pairs(revMap)],
    "plan_map_equal": planRamp.map { $0.map == (rampMap?.points ?? []) } ?? false,
    "text_clip_nil": ramped.sourceMap(9999) == nil,
]

// MARK: - F2: the filmstrip's and the waveform's source time

func frames(_ clip: ClipSnapshot) -> [Ticks] {
    stride(from: clip.start, to: clip.end, by: Int(frame)).map { $0 }
}
var constantSame = true
var nilSame = true
for t in frames(constClip) {
    let three = TimelineView.sourceTime(of: constClip, in: constMedia, at: t)
    if TimelineView.sourceTime(of: constClip, in: constMedia, at: t, map: constMap) != three {
        constantSame = false
    }
    if TimelineView.sourceTime(of: constClip, in: constMedia, at: t, map: nil) != three {
        nilSame = false
    }
}
var rampNilSame = true
for t in frames(rampClip)
where TimelineView.sourceTime(of: rampClip, in: rampMedia, at: t, map: nil)
    != TimelineView.sourceTime(of: rampClip, in: rampMedia, at: t) {
    rampNilSame = false
}
out["F2"] = [
    "ramped": frames(rampClip).map {
        [Int($0), Int(TimelineView.sourceTime(of: rampClip, in: rampMedia, at: $0, map: rampMap))]
    },
    "reversed": frames(revClip).map {
        [Int($0), Int(TimelineView.sourceTime(of: revClip, in: revMedia, at: $0, map: revMap))]
    },
    "constant_equal": constantSame, "nil_equal": nilSame, "ramp_nil_equal": rampNilSame,
]

// MARK: - F3: the transcript readers

func jobText(_ job: Transcriber.Job?) -> Any {
    guard let job else { return NSNull() }
    return ["start": Int(job.start), "duration": Int(job.duration), "in": Int(job.sourceIn),
            "length": Int(job.sourceLength), "speed": job.speed, "ramp": job.ramp != nil,
            "clip_start": job.ramp.map { Int($0.clipStart) } ?? NSNull()]
}
let rampURLs = [rampClip.source.mediaID ?? 0: null]
let fourArg = Transcriber.jobs(
    for: [rampClip], in: ramped.snapshot, urls: rampURLs, maps: ramped.sourceMap)
let threeArg = Transcriber.jobs(for: [rampClip], in: ramped.snapshot, urls: rampURLs)
let constURLs = [constClip.source.mediaID ?? 0: null]
let constFour = Transcriber.jobs(
    for: [constClip], in: constant.snapshot, urls: constURLs, maps: constant.sourceMap)
let constThree = Transcriber.jobs(for: [constClip], in: constant.snapshot, urls: constURLs)
var f3: [String: Any] = [
    "job": jobText(fourArg.jobs.first),
    "three_jobs": threeArg.jobs.count,
    "three_problems": threeArg.problems.map { "\($0.tag): \($0.reason)" },
    "constant_equal": constFour.jobs == constThree.jobs && constFour.jobs.count == 1
        && constFour.jobs.first?.ramp == nil,
]
if let job = fourArg.jobs.first {
    let sources: [Ticks] = stride(from: 0, through: 10 * second, by: 50_000).map { $0 }
    f3["project"] = sources.map { [Int($0), Int(MediaTranscript.project($0, in: job))] }
    let seconds: [Double] = stride(from: 0.0, through: 9.0, by: 0.125).map { $0 }
    f3["transcriber"] = seconds.map { [$0, Double(Transcriber.project($0, in: job))] }
    let windows: [(Ticks, Ticks)] = [
        (2 * second, 3 * second), (0, second), (4 * second, 5 * second), (0, 5 * second)]
    f3["windows"] = windows.map { from, to -> [String: Any] in
        let window = TranscriptReader.Window(from: job.start + from, to: job.start + to)
        let sub = TranscriptReader.recognitionJob(job, for: window)
        // 1 s into the sub-run, as the clip's own job places it.
        let inSub = Transcriber.project(1, in: sub)
        let offset = Double(sub.sourceIn - job.sourceIn) / Double(second) + 1
        return ["from": Int(window.from), "to": Int(window.to), "job": jobText(sub),
                "same": sub == job, "map_kept": sub.ramp == job.ramp,
                "one_second": Int(inSub),
                "one_second_whole": Int(Transcriber.project(offset, in: job))]
    }
}
out["F3"] = f3

// MARK: - F4: the silence walk's source tick

let constantOff = make(ramp: false, rate: 1.5, keepPitch: false)
if let segment = audioSegment(ramped), let constSegment = audioSegment(constant),
   let offSegment = constantOff.flatMap(audioSegment)
{
    let ticks = stride(from: segment.start, to: segment.start + segment.duration, by: Int(frame))
    out["F4"] = [
        "segment": ["start": Int(segment.start), "duration": Int(segment.duration),
                    "in": Int(segment.sourceIn), "source_duration": Int(segment.sourceDuration),
                    "has_map": segment.ramp?.source != nil],
        "ramped": ticks.map { [Int($0), Int(MediaPeaks.sourceTick(segment, at: $0))] },
        "constant_segment": [
            "start": Int(constSegment.start), "duration": Int(constSegment.duration),
            "in": Int(constSegment.sourceIn),
            "source_duration": Int(constSegment.sourceDuration),
            "ramp": constSegment.ramp != nil],
        "constant": stride(
            from: constSegment.start, to: constSegment.start + constSegment.duration,
            by: Int(frame)
        ).map { [Int($0), Int(MediaPeaks.sourceTick(constSegment, at: $0))] },
        "constant_off_segment": [
            "start": Int(offSegment.start), "duration": Int(offSegment.duration),
            "in": Int(offSegment.sourceIn),
            "source_duration": Int(offSegment.sourceDuration),
            "ramp": offSegment.ramp != nil, "constant": offSegment.ramp?.constant ?? false,
            "has_map": offSegment.ramp?.source != nil],
        "constant_off": stride(
            from: offSegment.start, to: offSegment.start + offSegment.duration,
            by: Int(frame)
        ).map { [Int($0), Int(MediaPeaks.sourceTick(offSegment, at: $0))] },
    ]
} else {
    out["F4"] = ["error": "no audio segment in a plan"]
}

// MARK: - F5: a 100 000-point map, read by binary search

let count = 100_000
var dense: [[Ticks]] = []
dense.reserveCapacity(count)
for k in 0..<count {
    let k64 = Ticks(k)
    dense.append([600 * k64, 600 * k64 + 3 * k64 * (k64 + 1)])
}
var f5: [String: Any] = ["points": count]
var lcg: UInt64 = 0x9E37_79B9_7F4A_7C15
func next(_ bound: UInt64) -> UInt64 {
    lcg = lcg &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return (lcg >> 17) % bound
}
func wall() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }
let checked = wall()
let denseMap = SourceMap(ramped: true, points: dense)
f5["check_seconds"] = wall() - checked
f5["made"] = denseMap != nil
if let denseMap {
    let lastClip = UInt64(dense[count - 1][0])
    let lastSource = UInt64(dense[count - 1][1])
    var hits = 0
    var wrong = 0
    var t0 = wall()
    var sink = 0.0
    for _ in 0..<count {
        // Every tenth reading lands on a breakpoint, where the answer is exact.
        let onPoint = next(10) == 0
        let k = Int(next(UInt64(count)))
        let t = onPoint ? Double(dense[k][0]) : Double(next(lastClip + 1))
        let s = denseMap.source(atClip: t)
        sink += s
        if onPoint {
            hits += 1
            if s != Double(dense[k][1]) { wrong += 1 }
        }
    }
    f5["source_seconds"] = wall() - t0
    t0 = wall()
    for _ in 0..<count {
        let onPoint = next(10) == 0
        let k = Int(next(UInt64(count)))
        let s = onPoint ? Double(dense[k][1]) : Double(next(lastSource + 1))
        let c = denseMap.clip(atSource: s)
        sink += c
        if onPoint {
            hits += 1
            if c != Double(dense[k][0]) { wrong += 1 }
        }
    }
    f5["clip_seconds"] = wall() - t0
    f5["breakpoints"] = hits
    f5["breakpoints_wrong"] = wrong
    // A plan segment decoded from JSON carrying the map, as the plan decodes one.
    let rows = dense.map { "[\($0[0]),\($0[1])]" }.joined(separator: ",")
    let json = #"{"clip":1,"media":1,"source_in":0,"source_duration":\#(lastSource),"start":0,"#
        + #""duration":\#(lastClip),"pitch":"off","ramp":{"keep_pitch":false,"map":[\#(rows)]}}"#
    if let segment = ReelJSON.decode(PlanSegment.self, from: json), segment.ramp?.source != nil {
        var tickWrong = 0
        t0 = wall()
        for _ in 0..<10_000 {
            let k = Int(next(UInt64(count)))
            if MediaPeaks.sourceTick(segment, at: dense[k][0]) != dense[k][1] { tickWrong += 1 }
        }
        f5["tick_seconds"] = wall() - t0
        f5["tick_wrong"] = tickWrong
    } else {
        f5["tick_error"] = "the segment did not decode with its map"
    }
    f5["sink"] = sink.isFinite
}
out["F5"] = f5
out["problems"] = problems

let answer = (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data()
print(String(data: answer, encoding: .utf8) ?? "{}")
