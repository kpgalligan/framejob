// tools/proof/speed_spike/speed_probe.swift — the in-process instrument behind
// `speed_spike.py` (issue batch B52a, #190 part 1: the ×1000 speed spike).
// Compiled as `main.swift` over every other file in `app/Sources` on
// `export_cancel_proof.build_probe`'s swiftc line (plus `-O
// -whole-module-optimization`), with the app's `Fonts`, `Blank.mp4` and a
// `default.metallib` of `Compositor.metal` beside the binary, linked against
// a SCRATCH core whose `SPEED_MAX` is 1000 (or HEAD's, for the mutant).
//
//     speed_probe timeline --media P[,P…] --rate R --passes N --trim-seconds S [--keep-pitch true|false]
//     speed_probe preview  <timeline args> --deadline SECONDS
//     speed_probe export   <timeline args> --preset h264|audio_m4a --file OUT --deadline SECONDS
//     speed_probe audio    --fixture F --algorithm spectral|time_domain|off --rate R --wav OUT
//
// It CALLS the app's code — `ReelProject.applying`, `MediaImporter.waitForProbe`,
// `CompositionBuilder`, `Playback.previewComposition`, `LevelMeterTrack.mix`,
// `ReelExport.settings`, `Exporter` — and mirrors only what is private
// (`Playback`'s player and item lines) or reader-side (`ExporterLoudness`'s
// mix output), each with a comment citing its line. One export per process.
//
// One line `ANSWER {json}` on stdout and exit 0; a crash is the caller's.
import AVFoundation
import AppKit
import CoreVideo

var answer: [String: Any] = ["error": NSNull()]

func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]))
        ?? Data("{\"error\":\"the answer would not serialise\"}".utf8)
    print("ANSWER " + String(decoding: data, as: UTF8.self))
    fflush(stdout)
    exit(0)
}

func fail(_ message: String) -> Never {
    answer["error"] = message
    finish()
}

/// A Double for JSON: NaN and ±inf are not JSON, so they answer null.
func finite(_ value: Double) -> Any { value.isFinite ? value : NSNull() }

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    answer["mode"] = NSNull()
    fail("usage: speed_probe timeline|preview|export|audio --key value …")
}
let mode = arguments[1]
answer["mode"] = mode
var options: [String: String] = [:]
var index = 2
while index < arguments.count {
    let key = arguments[index]
    guard key.hasPrefix("--"), index + 1 < arguments.count else { fail("bad argument \(key)") }
    options[String(key.dropFirst(2))] = arguments[index + 1]
    index += 2
}

func string(_ name: String) -> String {
    guard let value = options[name] else { fail("--\(name) is required for \(mode)") }
    return value
}

func number(_ name: String) -> Double {
    guard let value = Double(string(name)), value.isFinite else { fail("--\(name) is not a number") }
    return value
}

NSApplication.shared.setActivationPolicy(.prohibited)

let perSecond = Double(ReelTime.perSecond)

func seconds(_ ticks: Ticks) -> Double { Double(ticks) / perSecond }

// MARK: - The timeline

/// One op through the app's own `applying`; any arm but `.applied` stops the
/// probe with `error` set. `set_speed` at the rate the clip already has is the
/// one identity let through (×1 is the control), since the T row reads the
/// speed back anyway.
func apply(_ project: ReelProject, _ op: ReelOp, identityOK: Bool = false) -> ReelProject {
    let edit: ReelEdit
    do {
        edit = try project.applying([op])
    } catch {
        fail("\(op.name) threw: \(error.localizedDescription)")
    }
    switch edit {
    case .applied(let next):
        return next
    case .identity:
        if identityOK { return project }
        fail("\(op.name) answered identity")
    case .refused(let refusal):
        fail("\(op.name) was refused: \(refusal.reason)")
    }
}

func timelineAnswer(_ project: ReelProject) -> [String: Any] {
    let snapshot = project.snapshot
    let clips: [[String: Any]] = snapshot.clips.map { clip in
        ["id": Int(clip.id), "speed": clip.speed, "start_s": seconds(clip.start),
         "duration_s": seconds(clip.duration), "transition_in": clip.transitionIn != nil]
    }
    return [
        "canvas_width": snapshot.canvas.width, "canvas_height": snapshot.canvas.height,
        "canvas_fps": [snapshot.canvas.fps.num, snapshot.canvas.fps.den], "clips": clips,
        "duration_s": seconds(project.duration),
    ]
}

/// The runner's timeline: `set_canvas` to the first media's probed size and
/// rate (skipped with no video), `add_media` per distinct path, then per
/// pass, per media in order, `add_clip` at the cursor, `set_speed`, the clip
/// re-read from the snapshot. A positive `trim-seconds` places media only
/// until the timeline reaches it, then `trim_end`s the last clip there.
func buildTimeline() -> ReelProject {
    let paths = string("media").split(separator: ",").map(String.init)
    let rate = number("rate")
    guard let passes = Int(string("passes")), passes >= 1 else { fail("--passes must be ≥ 1") }
    let trimSeconds = number("trim-seconds")
    let keepPitch: Bool? = options["keep-pitch"].map { $0 == "true" }
    guard !paths.isEmpty else { fail("--media names no file") }

    var distinct: [String] = []
    var descriptors: [String: MediaDescriptor] = [:]
    for path in paths where descriptors[path] == nil {
        do {
            descriptors[path] = try MediaImporter.waitForProbe(URL(fileURLWithPath: path))
        } catch {
            fail("the probe of \(path) failed: \(error.localizedDescription)")
        }
        distinct.append(path)
    }

    var project = ProjectDocument().project
    if let first = descriptors[paths[0]], first.hasVideo {
        project = apply(
            project, .setCanvas(width: first.width, height: first.height, fps: first.fps))
    }
    var mediaIDs: [String: UInt32] = [:]
    for path in distinct {
        guard let descriptor = descriptors[path] else { fail("no descriptor for \(path)") }
        let id = project.snapshot.nextId
        project = apply(project, .addMedia(descriptor: descriptor))
        guard project.snapshot.media.contains(where: { $0.id == id }) else {
            fail("add_media minted no media \(id)")
        }
        mediaIDs[path] = id
    }
    guard let track = project.snapshot.tracks.first?.id else { fail("the project has no track") }

    let limit: Ticks? = trimSeconds > 0 ? Ticks((trimSeconds * perSecond).rounded()) : nil
    var cursor: Ticks = 0
    var lastClip: UInt32?
    placing: for _ in 0..<passes {
        for path in paths {
            if let limit = limit, cursor >= limit { break placing }
            guard let media = mediaIDs[path] else { fail("no media id for \(path)") }
            // Read back by the id the op mints (`nextId` before it), not by
            // `start == cursor`: at an inexact canvas rate (a recorder's VFR
            // average, 28977/1000) `add_clip` snaps `at` onto the frame grid.
            let minted = project.snapshot.nextId
            project = apply(project, .addClip(track: track, media: media, at: cursor))
            guard let placed = project.snapshot.clips.first(where: {
                $0.id == minted && $0.track == track
            }) else { fail("add_clip minted no clip \(minted) at \(cursor)") }
            project = apply(
                project, .setSpeed(clip: placed.id, rate: rate, keepPitch: keepPitch),
                identityOK: placed.speed == rate)
            guard let clip = project.snapshot.clips.first(where: { $0.id == placed.id }) else {
                fail("clip \(placed.id) is gone after set_speed")
            }
            cursor = clip.start + clip.duration
            lastClip = clip.id
        }
    }
    if let limit = limit, let lastClip = lastClip, cursor > limit {
        project = apply(project, .trimEnd(clip: lastClip, to: limit))
    }
    answer["timeline"] = timelineAnswer(project)
    return project
}

func mediaURLs(_ project: ReelProject) -> [UInt32: URL] {
    var urls: [UInt32: URL] = [:]
    for media in project.snapshot.media { urls[media.id] = URL(fileURLWithPath: media.path) }
    return urls
}

// MARK: - Preview

/// All of B, G and R ≤ 16 at every point of a 64 × 36 grid.
func isBlack(_ buffer: CVPixelBuffer) -> Bool {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return false }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let row = CVPixelBufferGetBytesPerRow(buffer)
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    for gy in 0..<36 {
        let y = min(height - 1, (2 * gy + 1) * height / 72)
        for gx in 0..<64 {
            let x = min(width - 1, (2 * gx + 1) * width / 128)
            let pixel = bytes + y * row + x * 4
            if pixel[0] > 16 || pixel[1] > 16 || pixel[2] > 16 { return false }
        }
    }
    return true
}

func runPreview() -> Never {
    let project = buildTimeline()
    let deadlineSeconds = number("deadline")
    let urls = mediaURLs(project)
    // As `Playback.update` publishes before a rebuild (`Playback.swift:229-232`).
    let key = RecipeSource.shared.register()
    RecipeSource.shared.set(project, for: key)
    AudioDSPSource.shared.publish(AudioDSPParameters(snapshot: project.snapshot), for: key)
    guard let plan = project.plan else { fail("the core's plan did not decode") }
    let buildStart = Date()
    let built: BuiltComposition
    do {
        built = try CompositionBuilder.build(
            plan: plan, planJSON: project.planJSON, urls: urls, recipeKey: key, metering: true)
    } catch {
        fail("the build failed: \(error.localizedDescription)")
    }
    answer["build_s"] = Date().timeIntervalSince(buildStart)

    let player = AVPlayer()
    // Mirrors `Playback.swift:138-139` (the player is private there).
    player.actionAtItemEnd = .pause
    player.automaticallyWaitsToMinimizeStalling = false
    // The spike's own line: the speakers stay silent.
    player.volume = 0
    // Mirrors `Playback.swift:432-444`, at Full.
    let item = AVPlayerItem(asset: built.composition)
    item.videoComposition = Playback.previewComposition(built, quality: .full)
    item.audioMix = built.audioMix
    item.preferredMaximumResolution = plan.renderSizeCG
    item.seekingWaitsForVideoCompositionRendering = true
    // The spike's own line: what the screen would have been handed.
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ])
    item.add(output)

    var playedToEnd = false
    var failedToEnd: String?
    let center = NotificationCenter.default
    let endObserver = center.addObserver(
        forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
    ) { _ in playedToEnd = true }
    let failObserver = center.addObserver(
        forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
    ) { note in
        let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
        failedToEnd = error?.localizedDescription ?? "failed to play to end"
    }
    player.replaceCurrentItem(with: item)

    let readyDeadline = Date().addingTimeInterval(30)
    while item.status == .unknown, Date() < readyDeadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
    }
    switch item.status {
    case .readyToPlay: answer["item_status"] = "readyToPlay"
    case .failed: answer["item_status"] = "failed"
    default: answer["item_status"] = "unknown"
    }
    answer["item_error"] = item.error.map { $0.localizedDescription as Any } ?? NSNull()
    let fps = plan.fps.double
    let durationSeconds = seconds(plan.duration)
    answer["expected"] = durationSeconds * fps
    guard item.status == .readyToPlay else {
        answer["error"] = "the item did not become ready"
        answer["delivered"] = 0
        answer["reached_end"] = false
        finish()
    }

    let endTime = built.composition.duration
    let frameSeconds = fps > 0 ? 1 / fps : 1.0 / 30
    var delivered = 0
    var black = 0
    var blackRunStart: Double?
    var longestBlackRun = 0.0
    var firstFrame: Double?
    var longestStall = 0.0
    var waitingEntries = 0
    var lastStatus = player.timeControlStatus
    var meterPeak = -Double.infinity
    var reachedEnd = false
    var wallToEnd: Double?
    var expired = true
    var displayTime = CMTime.invalid

    let playStart = Date()
    let deadline = playStart.addingTimeInterval(deadlineSeconds)
    player.play()
    var lastTime = player.currentTime()
    var lastAdvance = playStart
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
        let now = Date()
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        if output.hasNewPixelBuffer(forItemTime: itemTime),
            let buffer = output.copyPixelBuffer(
                forItemTime: itemTime, itemTimeForDisplay: &displayTime)
        {
            delivered += 1
            if firstFrame == nil { firstFrame = now.timeIntervalSince(playStart) }
            let at = displayTime.isNumeric ? CMTimeGetSeconds(displayTime) : CMTimeGetSeconds(itemTime)
            if isBlack(buffer) {
                black += 1
                let start = blackRunStart ?? at
                blackRunStart = start
                longestBlackRun = max(longestBlackRun, at - start + frameSeconds)
            } else {
                blackRunStart = nil
            }
        }
        let current = player.currentTime()
        if CMTimeCompare(current, lastTime) != 0 {
            lastTime = current
            lastAdvance = now
        } else {
            longestStall = max(longestStall, now.timeIntervalSince(lastAdvance))
        }
        let status = player.timeControlStatus
        if status != lastStatus {
            if status == .waitingToPlayAtSpecifiedRate { waitingEntries += 1 }
            lastStatus = status
        }
        if !built.meters.isEmpty {
            let reading = LevelMeterTrack.mix(built.meters, at: CompositionBuilder.ticks(current))
            let peak = Double(reading.peakDB)
            if peak.isFinite { meterPeak = max(meterPeak, peak) }
        }
        if item.status == .failed {
            answer["error"] = "the item failed while playing: "
                + (item.error?.localizedDescription ?? "no error")
            expired = false
            break
        }
        if let failure = failedToEnd {
            answer["error"] = "failed to play to end: \(failure)"
            expired = false
            break
        }
        if playedToEnd || CMTimeCompare(current, endTime) >= 0 {
            reachedEnd = true
            wallToEnd = now.timeIntervalSince(playStart)
            expired = false
            break
        }
    }
    player.pause()
    center.removeObserver(endObserver)
    center.removeObserver(failObserver)

    answer["first_frame_s"] = firstFrame.map { $0 as Any } ?? NSNull()
    answer["reached_end"] = reachedEnd
    answer["wall_to_end_s"] = wallToEnd.map { $0 as Any } ?? NSNull()
    answer["delivered"] = delivered
    answer["black"] = black
    answer["longest_black_run_s"] = longestBlackRun
    answer["longest_stall_s"] = longestStall
    answer["waiting_entries"] = waitingEntries
    answer["meter_tracks"] = built.meters.count
    answer["meter_peak_db"] = built.meters.isEmpty ? NSNull() : finite(meterPeak)
    answer["expired"] = expired
    answer["final_time_s"] = finite(CMTimeGetSeconds(player.currentTime()))
    finish()
}

// MARK: - Export

/// One export through `Exporter().export`, polled as `export_cancel_probe.swift`
/// polls it: the main run loop in slices of at most 10 ms, under a deadline.
func runExport() -> Never {
    let project = buildTimeline()
    let preset = string("preset")
    let file = URL(fileURLWithPath: string("file"))
    let deadlineSeconds = number("deadline")
    answer["file"] = file.path
    let settings: ExportSettings
    do {
        settings = try ReelExport.settings(project, preset: preset)
    } catch {
        answer["outcome"] = "failure"
        fail("the core would not resolve \(preset): \(error.localizedDescription)")
    }
    try? FileManager.default.removeItem(at: file)

    let exporter = Exporter()
    var outcome: Result<URL, any Error>?
    let start = Date()
    exporter.export(
        project: project, urls: mediaURLs(project), settings: settings, to: file,
        progress: { _ in },
        completion: { result in outcome = result })
    var phases: [[Any]] = []
    var lastPhase: String?
    var first = true
    let deadline = start.addingTimeInterval(deadlineSeconds)
    while outcome == nil, Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        let phase = exporter.phaseDescription
        if first || phase != lastPhase {
            phases.append([phase.map { $0 as Any } ?? NSNull(), Date().timeIntervalSince(start)])
            lastPhase = phase
            first = false
        }
    }
    answer["wall_s"] = Date().timeIntervalSince(start)
    answer["phases"] = phases
    switch outcome {
    case .success?:
        answer["outcome"] = "success"
    case .failure(let error)?:
        answer["outcome"] = "failure"
        answer["error"] = error.localizedDescription
    case nil:
        answer["outcome"] = "deadline"
    }
    finish()
}

// MARK: - Audio

/// 48 kHz stereo interleaved Float32 — `ExporterLoudness.swift:73-81`'s
/// measurement format (private there).
let floatAudioSettings: [String: Any] = [
    AVFormatIDKey: Int(kAudioFormatLinearPCM),
    AVSampleRateKey: 48000,
    AVNumberOfChannelsKey: 2,
    AVLinearPCMBitDepthKey: 32,
    AVLinearPCMIsFloatKey: true,
    AVLinearPCMIsBigEndianKey: false,
    AVLinearPCMIsNonInterleaved: false,
]

func wavData(_ samples: Data) -> Data {
    var data = Data()
    func put(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
    func put32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    put("RIFF")
    put32(UInt32(36 + samples.count))
    put("WAVE")
    put("fmt ")
    put32(16)
    put16(3)  // IEEE float
    put16(2)
    put32(48000)
    put32(48000 * 8)
    put16(8)
    put16(32)
    put("data")
    put32(UInt32(samples.count))
    data.append(samples)
    return data
}

/// One plan segment of `r × 2 s` of source played in 2 s, through the app's
/// `fill` and `audioParameters`, read through an `AVAssetReaderAudioMixOutput`
/// with the mix as `ExporterLoudness.swift:174-184` reads it.
func runAudio() -> Never {
    let fixture = URL(fileURLWithPath: string("fixture"))
    let algorithm = string("algorithm")
    let rate = number("rate")
    let wav = URL(fileURLWithPath: string("wav"))
    answer["expected_frames"] = 96000
    answer["wav"] = wav.path
    let sourceDuration = Ticks((rate * 1_200_000).rounded())
    let json = "{\"clip\":1,\"media\":1,\"source_in\":0,\"source_duration\":\(sourceDuration),"
        + "\"start\":0,\"duration\":1200000,\"pitch\":\"\(algorithm)\"}"
    let segment: PlanSegment
    do {
        segment = try ReelJSON.decoder().decode(PlanSegment.self, from: Data(json.utf8))
    } catch {
        fail("the segment did not decode: \(error.localizedDescription)")
    }
    let start = Date()
    let composition = AVMutableComposition()
    let track: AVMutableCompositionTrack
    do {
        track = try CompositionBuilder.makeTrack(in: composition, mediaType: .audio, id: 1001)
        var assets: [UInt32: AVURLAsset] = [:]
        var reversedAssets: [UInt32: AVURLAsset] = [:]
        try CompositionBuilder.fill(
            track, segments: [segment], mediaType: .audio, urls: [1: fixture],
            reverse: ReverseResolution.none, assets: &assets, reversedAssets: &reversedAssets)
    } catch {
        fail("the composition did not build: \(error.localizedDescription)")
    }
    let parameters = CompositionBuilder.audioParameters(
        for: track, segments: [segment], ramps: nil, dsp: nil, meter: nil)
    let mix = AVMutableAudioMix()
    mix.inputParameters = [parameters]
    answer["composition_s"] = finite(CMTimeGetSeconds(composition.duration))

    let reader: AVAssetReader
    do {
        reader = try AVAssetReader(asset: composition)
    } catch {
        answer["reader_status"] = "unknown"
        fail("the reader would not open: \(error.localizedDescription)")
    }
    // As `ExporterLoudness.swift:174-184`'s `mixOutput` (private there).
    let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: floatAudioSettings)
    output.audioMix = mix
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
        answer["reader_status"] = "unknown"
        fail("the reader refused the float mix output")
    }
    reader.add(output)
    // As `ExporterLoudness.swift:133-135`: the reader reads the export's range,
    // which for a whole-timeline export is the composition's [0, duration).
    reader.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
    var samples = Data()
    var rawFrames = 0
    let endFrame = Int((CMTimeGetSeconds(composition.duration) * 48000).rounded())
    if reader.startReading() {
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let total = CMBlockBufferGetDataLength(block)
            rawFrames += total / 8
            // The mix output hands back whole buffers, so the last one runs
            // past the range's end (98304 frames for 96000 at ×2, measured):
            // only the frames whose presentation time is inside [0, 2 s) count.
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            let first = pts.isNumeric ? Int((CMTimeGetSeconds(pts) * 48000).rounded()) : 0
            let length = max(0, min(total, (endFrame - first) * 8))
            guard length > 0 else { continue }
            var chunk = Data(count: length)
            let status = chunk.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return -1 }
                return CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: length, destination: base)
            }
            if status == kCMBlockBufferNoErr { samples.append(chunk) }
        }
    }
    switch reader.status {
    case .completed: answer["reader_status"] = "completed"
    case .failed: answer["reader_status"] = "failed"
    case .cancelled: answer["reader_status"] = "cancelled"
    case .reading: answer["reader_status"] = "reading"
    default: answer["reader_status"] = "unknown"
    }
    if let error = reader.error { answer["error"] = error.localizedDescription }
    answer["frames"] = samples.count / 8
    answer["frames_read"] = rawFrames
    answer["wall_s"] = Date().timeIntervalSince(start)
    do {
        try wavData(samples).write(to: wav)
    } catch {
        fail("the wav would not write: \(error.localizedDescription)")
    }
    finish()
}

switch mode {
case "timeline":
    _ = buildTimeline()
    finish()
case "preview":
    runPreview()
case "export":
    runExport()
case "audio":
    runAudio()
default:
    fail("unknown mode \(mode)")
}
