#!/usr/bin/env python3
"""The reversed mirror, spelled once — road map 7 §10 phase C.

§10.6's fourth decision keeps the reversed mirror on the APP side: `in` is
measured in the stream a clip PLAYS, and `core/src/edit_clip.rs`'s
`set_reversed` argues why a second convention must not enter the crate. What
the app had instead was the mirror spelled TWICE by convention —
`MediaPeaks.window` (`lo = pivot − last`, `hi = pivot − first`) and
`ReverseRenderer.walkBackwards` (`total − following`) — with nothing shared
and nothing asserting the two agreed, and a third reader,
`TimelineView.sourceTime`, that applied NO mirror at all, so a reversed clip's
filmstrip and waveform indexed the forward caches unmirrored and drew the
wrong end of the file. `ReverseMirror.swift` is now the one home; spec §11's
**D4-6** is the decision.

None of this is reachable over MCP — a drawn waveform is not an op, a
renderer's presentation stamps are not a placement, and a sheet's readout is
not project state — so this is `CLAUDE.md`'s instrument for app ARITHMETIC and
app STRUCTURE with no caller a script can reach: a probe compiled out of
`app/Sources` over `harness/build.sh`'s own swiftc line, cached on
modification times, a build failure scored as a FAILURE rather than an exit.

What it measures:

  * **§1 one spelling.** The tick and the window mirrors against numbers
    computed by hand; `MediaPeaks.window` for a reversed segment against the
    bucket range it answered BEFORE this phase (400…500 — the claim that
    routing it through `ReverseMirror` moved nothing, which
    `silence2_proof.py`'s claim 9 depends on); and the `CMTime` overload
    agreeing with the tick one under `CompositionBuilder.time`.
  * **§2 the drawn timeline.** A forward and a reversed whole-file clip of one
    audio media whose hand-written peaks cache is LOUD over its first half and
    silent over its second, drawn by a bare `TimelineView` into a bitmap: the
    forward clip's waveform is loud on the LEFT and the reversed one's on the
    RIGHT. Run against the unchanged tree on 2026-09-20 both were loud on the
    left — the same 18028/760 lit-pixel split, pixel for pixel — which is the
    defect §10.3 asked for a probe of. Plus the arithmetic under the picture,
    at ×1 and ×2.
  * **§3 the renderer.** A real reverse of `media/AV.mov`, its output video
    stamps read back with `AVAssetReader` and compared with the walk
    `[T − following]` from the end of the source: first stamp exactly 0,
    strictly ascending, the same frame count, and each stamp within one unit
    of the output track's own timescale (nothing in `ReverseRenderer` pins
    `mediaTimeScale`, so the writer is free to requantise).
  * **§4 the five Swift mirrors of core arithmetic**, each against the PLAN of
    the same project after phase B changed what `set_speed` writes:
    `Transcriber.contentLength` and the plan agree at 6 200 000 on §10.8's
    vector (a); the round, not floor, of a 1.00003 clip; `TimelineView` and
    `MediaPeaks` agreeing tick for tick at every frame boundary of a ×2 clip
    and staying inside the file at its last tick; and `Transcriber.project`,
    the inverse.
  * **§5 the Speed sheet's readout**, which is now the CORE's answer:
    `SpeedSheetController.lengths` against the durations read back after
    really applying its own ops — held to the file at a tail, APPLIED into a
    neighbour with a minted cross dissolve, REFUSED in the overlap rule's own
    sentence, and a MIXED selection that sums both.

Made to fail on purpose, five ways, each patched into a tree COPY with the
patch asserting its text occurs exactly once (`tools/proof/README.md` has the
table and what each took).

    python3 tools/proof/source_mirror_probe.py
"""

import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROBE = os.path.join(ROOT, "tools", "proof", "work", "source-mirror-probe")

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


def skip(name, why):
    global skipped
    skipped += 1
    print(f"  SKIP {name}\n       {why}")


PROBE_SOURCE = r'''
import AVFoundation
import AppKit
import Foundation

_ = NSApplication.shared

let SEC: Ticks = 600_000
let FRAME: Ticks = 20_000       // one frame at 30 fps
let MIRROR_T: Ticks = 6 * SEC   // §2's media duration
let BUCKETS = 600               // 100 peaks buckets per source second
let LONG: Ticks = 6_233_613     // §10.8's vector (a)

var answer: [String: Any] = [:]
func write(_ object: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
func fail(_ why: String) -> Never {
    answer["error"] = why
    write(answer)
    exit(0)
}

// ---- fixtures, built from ops alone: no file is needed anywhere ----------

func addMedia(
    _ document: ProjectDocument, _ path: String, _ duration: Ticks, kind: MediaKind = .video,
    hasVideo: Bool = true, hasAudio: Bool = true
) -> MediaSnapshot {
    document.performGroupedEdit(
        "Media",
        [
            .addMedia(
                descriptor: MediaDescriptor(
                    path: path, kind: kind, duration: duration, width: 1920, height: 1080,
                    fps: .thirty, hasVideo: hasVideo, hasAudio: hasAudio))
        ])
    guard let media = document.project.snapshot.media.first(where: { $0.path == path }) else {
        fail("add_media \(path) added nothing")
    }
    return media
}

func clipID(_ document: ProjectDocument, track: UInt32, at start: Ticks) -> UInt32 {
    guard let clip = document.project.snapshot.clips.first(where: {
        $0.track == track && $0.start == start
    }) else { fail("no clip on track \(track) at \(start)") }
    return clip.id
}

/// The plan's segment for a clip — the core's own answer about the window,
/// which is where phase B's defects showed.
func segment(of clip: UInt32, in project: ReelProject) -> PlanSegment? {
    guard let plan = project.plan else { return nil }
    for track in plan.videoTracks + plan.audioTracks {
        if let found = track.segments.first(where: { $0.clip == clip }) { return found }
    }
    return nil
}

// =========================================================================
// §2's fixture, which §1 also asks its `MediaPeaks` question of.
// One AUDIO media, 6 s, loud over its first half; a forward whole-file clip
// on the back track and a reversed one on the front.

let document = ProjectDocument()
guard let back = document.project.snapshot.tracks.first?.id else {
    fail("the blank project has no track")
}
document.performGroupedEdit("Track", [.addTrack(index: 1)])
guard let front = document.project.snapshot.tracks.last?.id, front != back else {
    fail("add_track did not add a front track")
}
let tone = addMedia(
    document, "/nowhere/tone.wav", MIRROR_T, kind: .audio, hasVideo: false, hasAudio: true)
document.performGroupedEdit("Clips", [
    .addClip(track: back, media: tone.id, at: 0),
    .addClip(track: front, media: tone.id, at: 0),
])
let forwardID = clipID(document, track: back, at: 0)
let reversedID = clipID(document, track: front, at: 0)
document.performGroupedEdit("Reverse", [.setReversed(clip: reversedID, reversed: true)])
let snapshot = document.project.snapshot
guard let forward = snapshot.clip(forwardID), let reversed = snapshot.clip(reversedID),
      reversed.source.isReversed, !forward.source.isReversed
else { fail("the fixture's two clips are not one forward and one reversed") }
answer["fixture"] = [
    "mediaDuration": tone.duration,
    "forwardDuration": forward.duration, "forwardIn": forward.source.sourceIn,
    "reversedDuration": reversed.duration, "reversedIn": reversed.source.sourceIn,
    "fps": [snapshot.canvas.fps.num, snapshot.canvas.fps.den],
]

// =========================================================================
// §1 — one spelling

var one: [String: Any] = [:]
one["tick"] = ReverseMirror.mirrored(Ticks(250_000), about: Ticks(1_000_000))
one["tickPastTheStart"] = ReverseMirror.mirrored(Ticks(1_200_000), about: Ticks(1_000_000))
let mirroredWindow = ReverseMirror.mirrored(
    Ticks(100_000)...Ticks(400_000), about: Ticks(1_000_000))
one["window"] = [mirroredWindow.lowerBound, mirroredWindow.upperBound]
one["pivotForward"] = ReverseMirror.pivot(for: forward, in: snapshot) ?? -1
one["pivotReversed"] = ReverseMirror.pivot(for: reversed, in: snapshot) ?? -1

// `MediaPeaks.window` over the reversed clip's own plan segment: the bucket
// range is hand-computed in the Python beside this, and it is the range this
// answered before the mirror moved into `ReverseMirror`.
guard let reversedSegment = segment(of: reversedID, in: document.project) else {
    fail("the plan has no segment for the reversed clip")
}
let pivot = MediaPeaks.reversedPivot(for: reversedSegment, in: snapshot)
let bucketWindow = MediaPeaks.window(
    of: reversedSegment, from: 1 * SEC, to: 2 * SEC, reversedPivot: pivot,
    bucketTicks: MediaPeaks.bucketTicks, count: BUCKETS)
one["segment"] = [
    "sourceIn": reversedSegment.sourceIn, "sourceDuration": reversedSegment.sourceDuration,
    "start": reversedSegment.start, "duration": reversedSegment.duration,
]
one["reversedPivot"] = pivot ?? -1
one["bucketTicks"] = MediaPeaks.bucketTicks
one["bucketWindow"] = bucketWindow.map { [$0.lowerBound, $0.upperBound] } ?? [-1, -1]
let forwardWindow = MediaPeaks.window(
    of: reversedSegment, from: 1 * SEC, to: 2 * SEC, reversedPivot: nil,
    bucketTicks: MediaPeaks.bucketTicks, count: BUCKETS)
one["forwardBucketWindow"] = forwardWindow.map { [$0.lowerBound, $0.upperBound] } ?? [-1, -1]

// The CMTime overload and the tick one are the same subtraction.
var agreements: [[String: Any]] = []
for p: Ticks in [0, 1, 6_000, 599_999, 1_234_567, MIRROR_T] {
    let viaTicks = CompositionBuilder.time(ReverseMirror.mirrored(p, about: MIRROR_T))
    let viaTime = ReverseMirror.mirrored(
        CompositionBuilder.time(p), about: CompositionBuilder.time(MIRROR_T))
    agreements.append([
        "p": p, "agrees": viaTicks == viaTime,
        "value": viaTime.value, "timescale": Int(viaTime.timescale),
    ])
}
one["cmTimeAgreement"] = agreements
answer["one"] = one

// =========================================================================
// §2 — the drawn timeline

guard let cache = document.cacheDirectory else { fail("the document has no cache directory") }
var peaks = [Float](repeating: 0, count: BUCKETS)
for i in 0..<(BUCKETS / 2) { peaks[i] = 1 }
let peaksURL = cache.appendingPathComponent("peaks", isDirectory: true)
    .appendingPathComponent("\(tone.id).bin")
try? FileManager.default.createDirectory(
    at: peaksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
peaks.withUnsafeBufferPointer { raw in try? Data(buffer: raw).write(to: peaksURL) }
let source = MediaImporter.CacheStamp(
    size: 0, modified: 0, duration: tone.duration, width: tone.width,
    height: tone.height, hasVideo: tone.hasVideo, hasAudio: tone.hasAudio,
    thumbnailHeight: MediaImporter.thumbnailHeight,
    maxThumbnails: MediaImporter.maxThumbnails,
    peakBucketsPerSecond: MediaImporter.peakBucketsPerSecond)
_ = MediaImporter.writeStamp(
    MediaImporter.PeaksStamp(source),
    to: MediaImporter.peaksMarkerURL(for: tone.id, in: cache))
guard MediaImporter.loadPeaks(for: tone.id, in: cache)?.count == BUCKETS else {
    fail("the hand-written peaks file did not read back")
}

let timeline = TimelineView()
timeline.frame = NSRect(x: 0, y: 0, width: 1000, height: 320)
timeline.layoutSubtreeIfNeeded()
timeline.update(
    snapshot: snapshot, selection: [], playhead: 0, inOutRange: nil, cacheDirectory: cache)
timeline.layoutSubtreeIfNeeded()

let content = timeline.content
let viewBounds = content.bounds
guard let rep = content.bitmapImageRepForCachingDisplay(in: viewBounds) else {
    fail("no bitmap for the content view")
}
content.cacheDisplay(in: viewBounds, to: rep)
let scaleX = CGFloat(rep.pixelsWide) / viewBounds.width
let scaleY = CGFloat(rep.pixelsHigh) / viewBounds.height

/// The waveform region of one clip, in the content view's own coordinates.
func waveformRect(_ clip: ClipSnapshot) -> CGRect {
    let index = snapshot.trackIndex(of: clip.track) ?? 0
    let rect = timeline.layout.clipRect(clip, row: timeline.layout.row(forTrackIndex: index))
    let inner = TimelineContentView.contentRect(rect)
    return TimelineContentView.regions(in: inner, hasVideo: false, hasAudio: true).audio
}

/// Lit pixels per half of a region, thresholded on the region's OWN range so
/// no clip tint has to be known here: the waveform is white at 44 % over the
/// tint, so the bright half of [min, max] is the ink.
func halves(_ rect: CGRect) -> [String: Any] {
    let x0 = max(0, Int((rect.minX * scaleX).rounded()))
    let x1 = min(rep.pixelsWide, Int((rect.maxX * scaleX).rounded()))
    let y0 = max(0, Int((rect.minY * scaleY).rounded()))
    let y1 = min(rep.pixelsHigh, Int((rect.maxY * scaleY).rounded()))
    var luma: [[Double]] = []
    var lowest = 1.0
    var highest = 0.0
    for y in y0..<max(y0, y1) {
        var row: [Double] = []
        for x in x0..<max(x0, x1) {
            let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
            let value =
                0.2126 * Double(color?.redComponent ?? 0)
                + 0.7152 * Double(color?.greenComponent ?? 0)
                + 0.0722 * Double(color?.blueComponent ?? 0)
            row.append(value)
            lowest = min(lowest, value)
            highest = max(highest, value)
        }
        luma.append(row)
    }
    let threshold = (lowest + highest) / 2
    let width = luma.first?.count ?? 0
    var left = 0
    var right = 0
    var ink = [Int](repeating: 0, count: width)
    for row in luma {
        for (x, value) in row.enumerated() where value > threshold {
            if x < width / 2 { left += 1 } else { right += 1 }
            ink[x] += 1
        }
    }
    // A LOUD column fills all but a point of the region; a silent one is the
    // one-pixel baseline. Half the height separates them by a mile.
    let tall = ink.indices.filter { ink[$0] > luma.count / 2 }
    return [
        "left": left, "right": right, "min": lowest, "max": highest,
        "threshold": threshold, "width": width, "height": luma.count, "tall": tall,
    ]
}

answer["scale"] = [Double(scaleX), Double(scaleY)]
answer["forwardWaveform"] = halves(waveformRect(forward))
answer["reversedWaveform"] = halves(waveformRect(reversed))

/// `sourceTime` against `pivot − (in + (t − start) × speed)`, spelled here.
func mirrorRows(_ clip: ClipSnapshot, _ media: MediaSnapshot) -> [String: Any] {
    var rows: [[Ticks]] = []
    for fraction in [0.0, 0.25, 0.5, 0.75, 0.99] {
        let t = clip.start + Ticks(Double(clip.duration) * fraction)
        let got = TimelineView.sourceTime(of: clip, in: media, at: t)
        let played = clip.source.sourceIn + Ticks((Double(t - clip.start) * clip.speed).rounded())
        let want = clip.source.isReversed ? media.duration - played : played
        rows.append([t, got, want])
    }
    return ["speed": clip.speed, "duration": clip.duration, "rows": rows]
}
var drawn: [String: Any] = ["forward": mirrorRows(forward, tone), "reversed×1": mirrorRows(reversed, tone)]

// The same clip at ×2, in the same document — after the picture was taken.
document.performGroupedEdit("Speed", [.setSpeed(clip: reversedID, rate: 2)])
guard let doubled = document.project.snapshot.clip(reversedID), doubled.speed == 2 else {
    fail("set_speed ×2 did not take on the reversed clip")
}
drawn["reversed×2"] = mirrorRows(doubled, tone)
answer["sourceTime"] = drawn

// =========================================================================
// §3 — the renderer

let fixture = URL(fileURLWithPath: CommandLine.arguments[2])
if !FileManager.default.fileExists(atPath: fixture.path) {
    answer["renderer"] = ["skipped": "\(fixture.path) is not there"]
} else if let probed = try? MediaImporter.probeBlocking(url: fixture) {
    let work = FileManager.default.temporaryDirectory
        .appendingPathComponent("reelcut-source-mirror-\(ProcessInfo.processInfo.processIdentifier)")
    try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    let destination = work.appendingPathComponent("reversed.mov")
    let job = ReverseRenderer.Job(
        media: 1, name: "AV.mov", source: fixture, destination: destination,
        duration: probed.duration, fps: probed.fps, hasAudio: probed.hasAudio)
    let outcome = ReverseRenderer(job: job).run()
    switch outcome {
    case .failure(let error):
        answer["renderer"] = ["error": "\(error)"]
    case .success(let url):
        /// Every video presentation stamp of one file, in order.
        func stamps(_ asset: AVURLAsset) -> [CMTime] {
            guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .video),
                  let reader = try? AVAssetReader(asset: asset)
            else { return [] }
            // DECODED, not sample references: a compressed read of these two
            // files answered 149 stamps for a 150-frame source and 152 for its
            // reversal, which is the container's business and not the walk's.
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ])
            guard reader.canAdd(output) else { return [] }
            reader.add(output)
            guard reader.startReading() else { return [] }
            var times: [CMTime] = []
            while let sample = output.copyNextSampleBuffer() {
                let time = CMSampleBufferGetPresentationTimeStamp(sample)
                if time.isNumeric { times.append(time) }
            }
            return times.sorted { $0 < $1 }
        }
        let total = CompositionBuilder.time(probed.duration)
        let source = stamps(AVURLAsset(url: fixture)).filter { $0 < total }
        let written = stamps(AVURLAsset(url: url))
        let outputScale =
            CompositionBuilder.firstTrack(of: AVURLAsset(url: url), mediaType: .video)?
            .naturalTimeScale ?? CMTimeScale(ReelTime.perSecond)
        // `following` starts at T, so the source's LAST frame is written at
        // zero and every frame back is written at T − the stamp of the frame
        // that followed it.
        var expected: [CMTime] = [ReverseMirror.mirrored(total, about: total)]
        for index in stride(from: source.count - 1, to: 0, by: -1) {
            expected.append(ReverseMirror.mirrored(source[index], about: total))
        }
        var rows: [[String: Any]] = []
        var worst: Int64 = 0
        for (index, want) in expected.enumerated() where index < written.count {
            let wanted = CMTimeConvertScale(
                want, timescale: outputScale, method: .roundHalfAwayFromZero)
            let drift = abs(written[index].value - wanted.value)
            worst = max(worst, drift)
            if index < 3 || index >= expected.count - 2 {
                rows.append([
                    "index": index, "want": wanted.value, "got": written[index].value,
                    "drift": drift,
                ])
            }
        }
        var ascending = true
        for index in 1..<max(written.count, 1) where written[index] <= written[index - 1] {
            ascending = false
        }
        answer["renderer"] = [
            "sourceFrames": source.count, "writtenFrames": written.count,
            "duration": probed.duration, "outputScale": Int(outputScale),
            "firstIsZero": written.first == .zero, "ascending": ascending,
            "worstDrift": worst, "rows": rows,
        ]
    }
} else {
    answer["renderer"] = ["error": "the fixture could not be probed"]
}

// =========================================================================
// §4 — the five Swift mirrors, each against the PLAN of the same project

let speedDoc = ProjectDocument()
guard let lane = speedDoc.project.snapshot.tracks.first?.id else { fail("no track") }
speedDoc.performGroupedEdit("Track", [.addTrack(index: 1)])
guard let lane2 = speedDoc.project.snapshot.tracks.last?.id else { fail("no second track") }
let long = addMedia(speedDoc, "/nowhere/long.mov", LONG)
let tiny = addMedia(speedDoc, "/nowhere/tiny.mov", FRAME)
speedDoc.performGroupedEdit("Clips", [
    .addClip(track: lane, media: long.id, at: 0),
    .addClip(track: lane2, media: tiny.id, at: 0),
])
let longID = clipID(speedDoc, track: lane, at: 0)
let tinyID = clipID(speedDoc, track: lane2, at: 0)
let wholeFile = speedDoc.project.snapshot.clip(longID)?.duration ?? -1
speedDoc.performGroupedEdit("Speed", [
    .setSpeed(clip: longID, rate: 2), .setSpeed(clip: tinyID, rate: 1.00003),
])
let sped = speedDoc.project.snapshot
guard let longClip = sped.clip(longID), let tinyClip = sped.clip(tinyID) else {
    fail("the sped clips are gone")
}
let urls = [long.id: URL(fileURLWithPath: long.path), tiny.id: URL(fileURLWithPath: tiny.path)]
let made = Transcriber.jobs(for: [longClip, tinyClip], in: sped, urls: urls)
guard let longJob = made.jobs.first(where: { $0.clip == longID }),
      let tinyJob = made.jobs.first(where: { $0.clip == tinyID })
else { fail("Transcriber.jobs made none: \(made.problems.map(\.reason))") }
guard let longSegment = segment(of: longID, in: speedDoc.project) else {
    fail("the plan has no segment for the ×2 clip")
}

// `TimelineView.sourceTime` against `MediaPeaks.sourceTick`, at every frame
// boundary of the ×2 clip, and inside the file at its last tick.
var disagreements: [[Ticks]] = []
var boundary = longClip.start
while boundary < longClip.start + longClip.duration {
    let view = TimelineView.sourceTime(of: longClip, in: long, at: boundary)
    let peak = MediaPeaks.sourceTick(longSegment, at: boundary)
    if view != peak { disagreements.append([boundary, view, peak]) }
    boundary += FRAME
}
let lastTick = longClip.start + longClip.duration - 1

// `Transcriber.project`, the inverse: `start + ticks(t) / speed`, clamped.
var inverse: [[Ticks]] = []
for seconds in [0.0, 0.5, 1.0, 2.5, 10.0, 1_000.0] {
    let got = Transcriber.project(seconds, in: longJob)
    let want = min(
        longJob.start + ReelTime.ticks(seconds: seconds / longJob.speed),
        longJob.start + longJob.duration)
    inverse.append([Ticks(seconds * 1000), got, want])
}

answer["four"] = [
    "wholeFileDuration": wholeFile,
    "spedDuration": longClip.duration,
    "jobSourceLength": longJob.sourceLength,
    "segmentSourceDuration": longSegment.sourceDuration,
    "segmentSourceIn": longSegment.sourceIn,
    "tinyDuration": tinyClip.duration, "tinySpeed": tinyClip.speed,
    "tinySourceLength": tinyJob.sourceLength,
    "frameDisagreements": disagreements,
    "frameBoundaries": Int(longClip.duration / FRAME),
    "lastTick": lastTick,
    "lastSource": TimelineView.sourceTime(of: longClip, in: long, at: lastTick),
    "mediaDuration": long.duration,
    "inverse": inverse,
]

// =========================================================================
// §5 — the readout, which is the core's own answer

/// `lengths`, beside the durations read back after REALLY applying its ops.
func readout(
    _ clips: [UInt32], rate: Double, in project: ReelProject, keepPitch: Bool = true
) -> [String: Any] {
    let measured = SpeedSheetController.lengths(
        of: clips, rate: rate, keepPitch: keepPitch, in: project)
    let ops = SpeedSheetController.ops(for: clips, rate: rate, keepPitch: keepPitch)
    let edit = try? project.applying(ops)
    let applied = edit.project ?? project
    let after = clips.reduce(Ticks(0)) { $0 + (applied.snapshot.clip($1)?.duration ?? 0) }
    var arm = "identity"
    var reason = ""
    switch edit {
    case .some(.applied): arm = "applied"
    case .some(.refused(let why)):
        arm = "refused"
        reason = why.reason
    default: break
    }
    return [
        "before": measured.before, "after": measured.after, "readBack": after,
        "arm": arm, "reason": reason,
    ]
}

// (a) held to the FILE: the whole-file clip of the 6 233 613-tick media at ×2.
let tailDoc = ProjectDocument()
guard let tailLane = tailDoc.project.snapshot.tracks.first?.id else { fail("no track") }
let tailMedia = addMedia(tailDoc, "/nowhere/long.mov", LONG)
tailDoc.performGroupedEdit("Clip", [.addClip(track: tailLane, media: tailMedia.id, at: 0)])
let tailID = clipID(tailDoc, track: tailLane, at: 0)

// The neighbours: ONE 30 fps project, track 1 = A, B and track 2 = C, D.
let neighbourDoc = ProjectDocument()
guard let trackOne = neighbourDoc.project.snapshot.tracks.first?.id else { fail("no track") }
neighbourDoc.performGroupedEdit("Track", [.addTrack(index: 1)])
guard let trackTwo = neighbourDoc.project.snapshot.tracks.last?.id else { fail("no track 2") }
let mediaX = addMedia(neighbourDoc, "/nowhere/X.mov", 1_000_000)
let mediaY = addMedia(neighbourDoc, "/nowhere/Y.mov", 2_000_000)
let mediaZ = addMedia(neighbourDoc, "/nowhere/Z.mov", 1_200_000)
neighbourDoc.performGroupedEdit("Clips", [
    .addClip(track: trackOne, media: mediaX.id, at: 0),
    .addClip(track: trackOne, media: mediaY.id, at: 1_600_000),
    .addClip(track: trackTwo, media: mediaX.id, at: 0),
    .addClip(track: trackTwo, media: mediaZ.id, at: 1_000_000),
])
let clipA = clipID(neighbourDoc, track: trackOne, at: 0)
let clipB = clipID(neighbourDoc, track: trackOne, at: 1_600_000)
let clipC = clipID(neighbourDoc, track: trackTwo, at: 0)
let clipD = clipID(neighbourDoc, track: trackTwo, at: 1_000_000)
let neighbourProject = neighbourDoc.project
let opsA = SpeedSheetController.ops(for: [clipA], rate: 0.5, keepPitch: true)
let appliedA = (try? neighbourProject.applying(opsA)).project ?? neighbourProject

answer["five"] = [
    "heldToTheFile": readout([tailID], rate: 2, in: tailDoc.project),
    "appliedIntoTheNeighbour": readout([clipA], rate: 0.5, in: neighbourProject),
    "refused": readout([clipC], rate: 0.5, in: neighbourProject),
    "mixed": readout([clipA, clipC], rate: 0.5, in: neighbourProject),
    "clips": [
        "A": clipA, "B": clipB, "C": clipC, "D": clipD,
        "aDuration": neighbourProject.snapshot.clip(clipA)?.duration ?? -1,
        "bStart": neighbourProject.snapshot.clip(clipB)?.start ?? -1,
        "dDuration": neighbourProject.snapshot.clip(clipD)?.duration ?? -1,
    ],
    "bTransitionBefore": neighbourProject.snapshot.clip(clipB)?.transitionIn != nil,
    "bTransitionAfter": appliedA.snapshot.clip(clipB)?.transitionIn != nil,
]

write(answer)
'''


def build_probe():
    """`marquee_probe.py`'s builder: `harness/build.sh`'s own swiftc line, the
    same staleness rule, and a reason instead of an exit when it will not
    build."""
    os.makedirs(PROBE, exist_ok=True)
    binary = os.path.join(PROBE, "sourcemirrorprobe")
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
        print(f"source mirror probe: {binary} (up to date)")
        return binary, None
    sdk = subprocess.run(
        ["xcrun", "--show-sdk-path", "--sdk", "macosx"], capture_output=True, text=True
    ).stdout.strip()
    start = time.time()
    result = subprocess.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
         "-import-objc-header", os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
         "-L", os.path.dirname(lib), "-lreelcut_core"] + sources + [entry, "-o", binary],
        capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(binary):
        errors = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    print(f"source mirror probe: {binary} (built in {time.time() - start:.1f} s)")
    return binary, None


def run_probe(binary):
    out = os.path.join(PROBE, "answer.json")
    fixture = os.path.join(ROOT, "tools", "proof", "media", "AV.mov")
    if os.path.exists(out):
        os.remove(out)
    try:
        result = subprocess.run(
            [binary, out, fixture], capture_output=True, text=True, timeout=900)
    except subprocess.TimeoutExpired:
        return None, "the probe never returned"
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stderr.strip().splitlines() or ["(no output)"])[-1]
    with open(out) as f:
        return json.load(f), None


def main():
    print("the reversed mirror, spelled once — road map 7 §10 phase C\n")
    binary, error = build_probe()
    check("the probe builds — an instrument that will not compile is a FAILURE here, "
          "not an exit", binary is not None, error or "")
    if binary is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1
    answer, error = run_probe(binary)
    check("the probe answers", answer is not None, error or "")
    if answer is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1
    check("…and it got as far as drawing a timeline", "error" not in answer,
          answer.get("error", ""))
    if "error" in answer:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1

    fixture = answer["fixture"]
    check("the fixture is a 6 s media at 30 fps with two whole-file clips, one reversed",
          fixture == {
              "mediaDuration": 3600000, "forwardDuration": 3600000, "forwardIn": 0,
              "reversedDuration": 3600000, "reversedIn": 0, "fps": [30, 1]},
          json.dumps(fixture))

    print("\n1 — one spelling of the mirror")
    one = answer["one"]
    check("a tick mirrors as pivot − tick", one["tick"] == 750_000, json.dumps(one["tick"]))
    check("…and may go negative when the window runs past the file's start",
          one["tickPastTheStart"] == -200_000, json.dumps(one["tickPastTheStart"]))
    check("a window mirrors END for END: (pivot − upper)…(pivot − lower)",
          one["window"] == [600_000, 900_000], json.dumps(one["window"]))
    check("the pivot is the media's model duration for the reversed clip and nil for the "
          "forward one",
          one["pivotReversed"] == 3_600_000 and one["pivotForward"] == -1,
          json.dumps([one["pivotForward"], one["pivotReversed"]]))
    check("the plan carries no reversal — the segment is the forward window",
          one["segment"] == {
              "sourceIn": 0, "sourceDuration": 3600000, "start": 0, "duration": 3600000},
          json.dumps(one["segment"]))
    check("MediaPeaks.reversedPivot answers that same pivot through ReverseMirror",
          one["reversedPivot"] == 3_600_000, json.dumps(one["reversedPivot"]))
    # By hand, at 6000 ticks a bucket: first = 600 000, last = 1 199 999,
    # lo = 3 600 000 − 1 199 999 = 2 400 001, hi = 3 600 000 − 600 000 = 3 000 000,
    # floor(2 400 001 / 6000) = 400 and floor(3 000 000 / 6000) = 500.
    check("MediaPeaks.window over 1–2 s of the reversed clip is buckets 400…500, the "
          "range it answered before the mirror moved (silence2_proof claim 9's numbers)",
          one["bucketTicks"] == 6000 and one["bucketWindow"] == [400, 500],
          json.dumps([one["bucketTicks"], one["bucketWindow"]]))
    check("…and 100…199 unmirrored, which is the half the mirror exists to avoid reading",
          one["forwardBucketWindow"] == [100, 199], json.dumps(one["forwardBucketWindow"]))
    check("the CMTime overload is the tick one under CompositionBuilder.time, at every "
          "tick tried",
          all(row["agrees"] for row in one["cmTimeAgreement"]),
          json.dumps(one["cmTimeAgreement"]))

    print("\n2 — the drawn timeline")
    f = answer["forwardWaveform"]
    r = answer["reversedWaveform"]
    check("both waveform regions were drawn at the same size",
          f["width"] == r["width"] and f["height"] == r["height"] and f["width"] > 100,
          json.dumps([f, r]))
    check("the forward clip's waveform is loud on the LEFT", f["left"] > 8 * max(f["right"], 1),
          json.dumps(f))
    check("the reversed clip's waveform is loud on the RIGHT — the defect this phase fixed; "
          "on the unchanged tree it read 18028 left and 760 right, the forward clip's own "
          "split pixel for pixel",
          r["right"] > 8 * max(r["left"], 1), json.dumps(r))
    mirrored = {f["width"] - 1 - x for x in f["tall"]}
    check("the reversed clip's LOUD columns are the forward clip's, mirrored — bar the "
          "blank column at its head, which is the one tick the shared spelling is high by",
          len(f["tall"]) > 200 and len(mirrored ^ set(r["tall"])) <= 4,
          json.dumps({"forward": f["tall"][:3] + f["tall"][-3:],
                      "reversed": r["tall"][:3] + r["tall"][-3:],
                      "differ": sorted(mirrored ^ set(r["tall"]))}))
    drawn = answer["sourceTime"]
    for name, rows in sorted(drawn.items()):
        check(f"sourceTime of the {name} clip is in + (t − start) × speed"
              + (", mirrored about the media's duration" if "reversed" in name else ""),
              all(row[1] == row[2] for row in rows["rows"]), json.dumps(rows))

    print("\n3 — the renderer")
    renderer = answer.get("renderer", {})
    if "skipped" in renderer:
        skip("ReverseRenderer against media/AV.mov", renderer["skipped"]
             + " — tools/proof/README.md has the recipe")
    elif "error" in renderer:
        check("the reverse renders", False, renderer["error"])
    else:
        check("the reversal has the same frame count as its source",
              renderer["writtenFrames"] == renderer["sourceFrames"] and renderer["sourceFrames"] > 20,
              json.dumps(renderer))
        check("the source's LAST frame is written at exactly zero",
              renderer["firstIsZero"], json.dumps(renderer))
        check("every stamp is later than the one before it — a walk that did not mirror "
              "would make the writer refuse the append",
              renderer["ascending"], json.dumps(renderer))
        check("every stamp is T − the following frame's, within one unit of the output "
              "track's own timescale (nothing pins mediaTimeScale)",
              renderer["worstDrift"] <= 1, json.dumps(renderer))

    print("\n4 — the five Swift mirrors, against the core's plan")
    four = answer["four"]
    check("a whole-file clip of a 6 233 613-tick media is 6 220 000 at 30 fps, and ×2 "
          "makes it 3 100 000 — held to the file at the new rate (D4-3)",
          four["wholeFileDuration"] == 6_220_000 and four["spedDuration"] == 3_100_000,
          json.dumps(four))
    check("Transcriber's source length and the PLAN's segment agree at 6 200 000",
          four["jobSourceLength"] == 6_200_000 and four["segmentSourceDuration"] == 6_200_000,
          json.dumps(four))
    check("a one-frame clip at ×1.00003 reads 20 001 source ticks — ROUND, not floor",
          four["tinyDuration"] == 20_000 and four["tinySpeed"] == 1.00003
          and four["tinySourceLength"] == 20_001, json.dumps(four))
    check("TimelineView.sourceTime and MediaPeaks.sourceTick agree at every frame boundary "
          "of the ×2 clip",
          four["frameDisagreements"] == [] and four["frameBoundaries"] == 155,
          json.dumps(four))
    check("…and the clip's last tick is still inside its file",
          four["lastSource"] == 6_199_998 and four["lastSource"] <= four["mediaDuration"],
          json.dumps(four))
    check("Transcriber.project is start + ticks(t) / speed, clamped into the clip",
          all(row[1] == row[2] for row in four["inverse"]), json.dumps(four["inverse"]))

    print("\n5 — the Speed sheet's readout is the core's answer")
    five = answer["five"]
    tail = five["heldToTheFile"]
    check("HELD TO THE FILE: 6 220 000 → 3 100 000 at ×2, not the 3 110 000 the quotient "
          "would print",
          (tail["before"], tail["after"]) == (6_220_000, 3_100_000), json.dumps(tail))
    for name in ["heldToTheFile", "appliedIntoTheNeighbour", "refused", "mixed"]:
        row = five[name]
        check(f"…{name}: the readout equals the durations read back after really applying "
              "its own ops", row["after"] == row["readBack"], json.dumps(row))
    applied = five["appliedIntoTheNeighbour"]
    check("APPLIED INTO THE NEIGHBOUR: A at ×0.5 reads 1 000 000 → 2 000 000, an overlap of "
          "400 000 against a limit of 1 000 000",
          (applied["before"], applied["after"]) == (1_000_000, 2_000_000)
          and applied["arm"] == "applied", json.dumps(applied))
    check("…and B gains a cross dissolve it did not have, which the readout now names "
          "(speed_sheet_probe.py)",
          five["bTransitionBefore"] is False and five["bTransitionAfter"] is True,
          json.dumps([five["bTransitionBefore"], five["bTransitionAfter"]]))
    refused = five["refused"]
    check("REFUSED: C at ×0.5 reaches 1 000 000 into D, past half of the shorter clip, so "
          "it reads 1 000 000 → 1 000 000",
          (refused["before"], refused["after"]) == (1_000_000, 1_000_000)
          and refused["arm"] == "refused", json.dumps(refused))
    check("…in the overlap rule's own sentence",
          refused["reason"] == "clips {} and {} would overlap by 1000000 ticks, more than "
          "half of the shorter clip (600000 ticks)".format(five["clips"]["C"], five["clips"]["D"]),
          json.dumps(refused["reason"]))
    mixed = five["mixed"]
    check("MIXED: [A, C] at ×0.5 reads 2 000 000 → 3 000 000 — the applied clip's new "
          "length beside the refused clip's old one, which is what Apply writes",
          (mixed["before"], mixed["after"]) == (2_000_000, 3_000_000), json.dumps(mixed))

    total = passed + failed
    print(f"\n{passed}/{total} checks passed" + (f", {skipped} skipped by name" if skipped else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
