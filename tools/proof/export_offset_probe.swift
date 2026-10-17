// Issue #298 — where an exported sample lands, stage by stage. The
// in-process instrument behind `export_offset_proof.py`'s L1–L9 (phase 1),
// X1–X8 (phase 2's pins) and clean-up batch 3's L10–L12 and X9–X15 (#307,
// #306: spec §11 SY-35, SY-36, SY-38).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a`, through
// `swift_build.build` (the proof's `build_probe`, `playback_audio_proof.py`'s
// pattern), with `Blank.mp4` beside the binary:
//
//     export_offset_probe <out-dir> <fixtures-dir> [all|L|X]
//
// The third argument picks the row group (default `all`): `L` runs L1–L12,
// `X` runs X1–X15 (what `--mutants` runs).
//
// It decodes each fixture's sound at each stage of the export path and writes
// what it read; it locates nothing — the proof locates every click in what is
// written here, with the same `locate` it runs on the exported files. Each
// read is `<out-dir>/<fixture>-<stage>-<variant>.f32` (mono float32 LE, a
// stereo read averaged, placed by its first buffer's presentation time), but
// the export and extract stages', which are WAVs
// (`<fixture>-export-<variant>.wav`), read by the proof's `read_wav`. Every
// read is a row of `<out-dir>/manifest.json`: `{"row", "fixture", "stage",
// "variant", "rate", "path", "start_ticks", "speed", "first_pts_s", "ok",
// "error"}` and a stage's extras. One line out: `ANSWER {"rows": [{"id", "ok", "detail"}]}`, a row
// ok when every read in it completed.
//
// Projects: an untitled `ProjectDocument`'s project, 640×360 at 30 fps, one
// `add_media` (a `MediaDescriptor` from the file's `AVURLAsset` duration and
// tracks), one `add_clip` and, where a row names one, `set_speed(rate,
// keep_pitch)`, each through the app's own `applying`. Builds go through
// `CompositionBuilder.build(…, metering: false)`, the export through
// `Exporter().export` with `ReelExport.settings(_:preset: "audio_wav")`.
//
// Stages (the variant is `<speed>[-off|-keep][+…]`; the part before `+` is the
// speed the proof chains the stages by):
//   asset48  the media's own audio track, `AVAssetReaderTrackOutput`, LPCM
//            float 48 kHz mono                                          (L1)
//   native   the same at the track's own sample rate                    (L2)
//   comp     the build's composition, `AVAssetReaderAudioMixOutput`, float
//            stereo, `audioMix` nil, the output's `audioTimePitchAlgorithm`
//            set from the segment's plan `pitch` as
//            `CompositionBuilder.audioParameters` maps it ("off" →
//            varispeed, "spectral" → spectral, "time_domain" → timeDomain;
//            none leaves the output's own default, spectral), named in the
//            variant as `+alg-…`                                  (L3, L7, L8)
//   mix      the same output at 48 kHz with the build's `audioMix` and the
//            output's default algorithm, as `ExportWriter.addAudioOutput`
//            reads it                                         (L4, L6, L8, L9)
//   export   the in-process `audio_wav` export                       (L5, L8)
//   avaudiofile  the file through `AVAudioFile`, float at its rate, from
//            frame 0; extras `priming_frames`, `remainder_frames`,
//            `valid_frames` (its packet table, else null)              (L10)
//   trimmed  native, the reader's range from `MP3Gapless.leadingTrim` when
//            not zero, placed from it; extra `trim_frames`              (L10)
//   peaks    `writePeaks`' output settings verbatim, channels averaged (L11)
//   speech   `writeSpeech`'s, 16 kHz mono                              (L11)
//   extract  the product's `Transcriber.extractAudio`, a 16 kHz WAV    (L11)
//   sync     the product's `writeSyncFeatures` into a cache of its own,
//            then `loadSyncSamples` at 8 kHz from 0                    (X12)
//
//   L1–L5  each fixture (all five) at frame 206 (F206 = 206·20 000 ticks), ×1
//   L6     L4 at ×1 with each input's algorithm set to nil (the reader
//          output's default, spectral, applies — not a bypass) / varispeed /
//          spectral / timeDomain, on parameters rebuilt by
//          `CompositionBuilder.audioParameters` (clicks16, clicks48)
//   L7     L3 read at 16 000 / 44 100 / 48 000 Hz (clicks16, clicks48)
//   L8     L3, L4, L5 at ×0.99999 and ×0.5, keep_pitch false and true
//          (clicks16, clicks48)
//   L9     L4 with the clip at 0, F206 and 10 s (clicks16, clicks48, cam-ff16)
//   L10    asset48, native and avaudiofile of clicks44-mp3 and clicks48-mp3;
//          trimmed of those and clicks24-mp3; native of clicks44s-mp3,
//          clicks44-mp3-itunsmpb, clicks44-mp3-noxing and clicks24-mp3
//   L11    peaks, speech and extract of the three MP3s (clicks44-mp3,
//          clicks48-mp3, clicks24-mp3) and their WAV controls clicks44,
//          clicks48; asset48 of clicks44 and clicks24-mp3 (the reverse
//          decode's)
//   L12    `MP3Gapless` checked in-process: each fixture's tag and trim,
//          then synthetic and damaged tags (files under `<out-dir>/l12/`);
//          a mismatch is a row error naming the case
//
//   X1–X8  the in-process `audio_wav` export (the export stage), pinned by the
//          proof (spec §11 SY-27): X1 clicks16 F206 ×1; X2 clicks44 F206 ×1;
//          X3 clicks48 F206 ×0.5 keep false; X4 clicks48 F206 noise reduction
//          0.5 (`set_audio`); X5 clicks48 at 0 noise reduction 0.5; X6
//          clicks16 F206 ×0.99999 keep true; X7 clicks48 F206 ×1; X8
//          clicks44-late F206 ×1 (its audio, 0.5 s into the movie)
//   X9–X15 the same at F206 ×1: X9 clicks16-late5 (its audio 5 s in, SY-35);
//          X10 clicks44-mp3; X11 clicks48-mp3; X12 the sync cache (stage
//          `sync`) of both MP3s, clicks44, clicks48 and clicks44s-mp3; X13
//          clicks44s-mp3 and clicks44-mp3-itunsmpb (packet tables); X14
//          clicks44-mp3-noxing (no tag); X15 clicks24-mp3 (MPEG-2)
import AVFoundation
import AppKit
import AudioToolbox

NSApplication.shared.setActivationPolicy(.prohibited)

let arguments = CommandLine.arguments
let group = arguments.count == 4 ? arguments[3] : "all"
guard arguments.count == 3 || arguments.count == 4, ["all", "L", "X"].contains(group) else {
    FileHandle.standardError.write(
        Data("usage: export_offset_probe <out-dir> <fixtures-dir> [all|L|X]\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: arguments[1], isDirectory: true)
let fixturesDir = URL(fileURLWithPath: arguments[2], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let fixtureFiles: [String: String] = [
    "clicks16": "clicks16-v1.wav", "clicks48": "clicks48-v1.wav",
    "cam-pcm48": "cam-pcm48-v1.mov", "cam-aac48": "cam-aac48-v1.mov",
    "cam-ff16": "cam-ff16-v1.mov",
    "clicks44": "clicks44-v1.wav", "clicks44-late": "clicks44-late-v1.mov",
    "clicks44-mp3": "clicks44-mp3-v1.mp3", "clicks48-mp3": "clicks48-mp3-v1.mp3",
    "clicks16-late5": "clicks16-late5-v1.mov",
    "clicks44s-mp3": "clicks44s-mp3-v1.mp3", "clicks44-mp3-noxing": "clicks44-mp3-noxing-v1.mp3",
    "clicks44-mp3-itunsmpb": "clicks44-mp3-itunsmpb-v1.mp3", "clicks24-mp3": "clicks24-mp3-v1.mp3",
]
let allFixtures = ["clicks16", "clicks48", "cam-pcm48", "cam-aac48", "cam-ff16"]
let wavFixtures = ["clicks16", "clicks48"]
let second: Ticks = 600_000
let f206: Ticks = 206 * 20_000

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

var manifest: [[String: Any]] = []
var rowReads: [String: Int] = [:]
var rowErrors: [String: [String]] = [:]

func writeAnswer() {
    let manifestData = (try? JSONSerialization.data(
        withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])) ?? Data("[]".utf8)
    try? manifestData.write(to: outDir.appendingPathComponent("manifest.json"))
    let lRows = ["L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "L10", "L11", "L12"]
    let xRows = [
        "X1", "X2", "X3", "X4", "X5", "X6", "X7", "X8", "X9", "X10", "X11", "X12", "X13", "X14",
        "X15",
    ]
    let ids = group == "L" ? lRows : group == "X" ? xRows : lRows + xRows
    let rows = ids.map { id -> [String: Any] in
        let reads = rowReads[id] ?? 0
        let errors = rowErrors[id] ?? []
        return [
            "id": id, "ok": reads > 0 && errors.isEmpty,
            "detail": String(("\(reads) read(s), \(errors.count) failed"
                + (errors.isEmpty ? "" : ": " + errors.joined(separator: " | "))).prefix(1500)),
        ]
    }
    let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data("{\"rows\":[]}".utf8)
    print("ANSWER " + String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

// MARK: - Reading

func floatSettings(rate: Int, channels: Int) -> [String: Any] {
    [
        AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: rate,
        AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
}

/// Every sample `output` yields, its channels averaged, placed on the
/// output's own clock: the first buffer's presentation time less `origin`, in
/// samples, is leading silence (or, when negative, samples dropped).
/// (samples, that presentation time).
func drain(
    _ reader: AVAssetReader, _ output: AVAssetReaderOutput, channels: Int, rate: Int,
    origin: Double = 0
) throws -> ([Float], Double) {
    guard reader.canAdd(output) else { throw ProbeError("the reader refused the output") }
    reader.add(output)
    guard reader.startReading() else {
        throw ProbeError("startReading: \(String(describing: reader.error))")
    }
    var samples: [Float] = []
    var first: CMTime?
    while let buffer = output.copyNextSampleBuffer() {
        guard CMSampleBufferGetNumSamples(buffer) > 0,
              let block = CMSampleBufferGetDataBuffer(buffer)
        else { continue }
        if first == nil { first = CMSampleBufferGetPresentationTimeStamp(buffer) }
        let length = CMBlockBufferGetDataLength(block)
        var chunk = [Float](repeating: 0, count: length / 4)
        let status = chunk.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
        }
        guard status == noErr else { throw ProbeError("a block buffer would not copy") }
        if channels == 1 {
            samples.append(contentsOf: chunk)
        } else {
            var index = 0
            while index + channels <= chunk.count {
                var sum: Float = 0
                for c in 0..<channels { sum += chunk[index + c] }
                samples.append(sum / Float(channels))
                index += channels
            }
        }
    }
    guard reader.status == .completed else {
        throw ProbeError("the reader ended \(reader.status.rawValue): "
            + "\(String(describing: reader.error))")
    }
    let pts = first.map { CMTimeGetSeconds($0) } ?? 0
    let shift = Int(((pts - origin) * Double(rate)).rounded())
    if shift > 0 {
        samples = [Float](repeating: 0, count: shift) + samples
    } else if shift < 0 {
        samples.removeFirst(min(-shift, samples.count))
    }
    return (samples, pts)
}

func writeF32(_ samples: [Float], _ url: URL) throws {
    let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
    try data.write(to: url)
}

func fixtureURL(_ fixture: String) -> URL {
    fixturesDir.appendingPathComponent(fixtureFiles[fixture]!)
}

func audioTrack(_ fixture: String) throws -> (AVURLAsset, AVAssetTrack) {
    let asset = AVURLAsset(url: fixtureURL(fixture))
    guard let track = asset.tracks(withMediaType: .audio).first else {
        throw ProbeError("\(fixture) has no audio track")
    }
    return (asset, track)
}

func nativeRate(_ track: AVAssetTrack) throws -> Int {
    guard let description = (track.formatDescriptions as? [CMAudioFormatDescription])?.first,
          let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)
    else { throw ProbeError("no stream description") }
    return Int(asbd.pointee.mSampleRate.rounded())
}

/// One read, recorded in the manifest whether it completed or not; `extra`
/// is merged into its entry.
func record(
    _ row: String, _ fixture: String, _ stage: String, _ variant: String, rate: Int,
    start: Ticks, speed: Double, extra: [String: Any] = [:], _ body: (URL) throws -> Double
) {
    let ext = stage == "export" || stage == "extract" ? "wav" : "f32"
    let url = outDir.appendingPathComponent("\(fixture)-\(stage)-\(variant).\(ext)")
    try? FileManager.default.removeItem(at: url)
    var entry: [String: Any] = [
        "row": row, "fixture": fixture, "stage": stage, "variant": variant, "rate": rate,
        "path": url.path, "start_ticks": Int(start), "speed": speed,
    ]
    entry.merge(extra) { _, new in new }
    rowReads[row, default: 0] += 1
    do {
        entry["first_pts_s"] = try body(url)
        entry["ok"] = true
        entry["error"] = NSNull()
    } catch {
        entry["ok"] = false
        entry["first_pts_s"] = NSNull()
        entry["error"] = "\(error)"
        rowErrors[row, default: []].append("\(fixture) \(stage) \(variant): \(error)")
    }
    manifest.append(entry)
}

// MARK: - Projects

let base = ProjectDocument().project

func apply(_ project: ReelProject, _ op: ReelOp) throws -> ReelProject {
    switch try project.applying([op]) {
    case .applied(let next): return next
    case .identity: return project
    case .refused(let refusal): throw ProbeError("\(op.name) was refused: \(refusal.reason)")
    }
}

func descriptor(_ url: URL) throws -> MediaDescriptor {
    let asset = AVURLAsset(url: url)
    let video = asset.tracks(withMediaType: .video).first
    let hasAudio = !asset.tracks(withMediaType: .audio).isEmpty
    let size = video?.naturalSize ?? .zero
    let duration = CompositionBuilder.ticks(asset.duration)
    guard duration > 0 else { throw ProbeError("\(url.lastPathComponent) has no duration") }
    return MediaDescriptor(
        path: url.path, kind: video == nil ? .audio : .video, duration: duration,
        width: Int(size.width), height: Int(size.height), fps: Fps(num: 30, den: 1),
        hasVideo: video != nil, hasAudio: hasAudio)
}

struct Placed {
    let project: ReelProject
    let clip: UInt32
    let start: Ticks
    let speed: Double
    let urls: [UInt32: URL]
}

func place(
    _ fixture: String, at: Ticks, rate: Double? = nil, keepPitch: Bool = true,
    noiseReduction: Double? = nil
) throws -> Placed {
    var project = try apply(base, .setCanvas(width: 640, height: 360, fps: Fps(num: 30, den: 1)))
    let media = project.snapshot.nextId
    project = try apply(project, .addMedia(descriptor: try descriptor(fixtureURL(fixture))))
    guard let track = project.snapshot.tracks.first?.id else { throw ProbeError("no track") }
    let clip = project.snapshot.nextId
    project = try apply(project, .addClip(track: track, media: media, at: at))
    guard project.snapshot.clip(clip) != nil else { throw ProbeError("add_clip minted no clip") }
    if let rate = rate {
        project = try apply(project, .setSpeed(clip: clip, rate: rate, keepPitch: keepPitch))
    }
    if let noiseReduction = noiseReduction {
        project = try apply(
            project, .setAudio(clips: [clip], patch: AudioPatch(noiseReduction: noiseReduction)))
    }
    guard let placed = project.snapshot.clip(clip) else { throw ProbeError("the clip is gone") }
    var urls: [UInt32: URL] = [:]
    for item in project.snapshot.media { urls[item.id] = URL(fileURLWithPath: item.path) }
    return Placed(project: project, clip: clip, start: placed.start, speed: placed.speed,
                  urls: urls)
}

/// The build, with its recipe key published for its life (`body`'s).
func withBuild<T>(_ placed: Placed, _ body: (BuiltComposition, CompositionPlan) throws -> T)
    throws -> T
{
    guard let plan = placed.project.plan else { throw ProbeError("the project has no plan") }
    let key = RecipeSource.shared.register()
    defer { RecipeSource.shared.unregister(key) }
    RecipeSource.shared.set(placed.project, for: key)
    RecipeSource.shared.setOptions(.none, for: key)
    let built = try CompositionBuilder.build(
        plan: plan, planJSON: placed.project.planJSON, urls: placed.urls, recipeKey: key,
        metering: false)
    return try body(built, plan)
}

/// The algorithm `CompositionBuilder.audioParameters` maps a plan `pitch` to.
func algorithm(forPitch pitch: String?) -> (AVAudioTimePitchAlgorithm?, String) {
    switch pitch {
    case "spectral": return (.spectral, "spectral")
    case "off": return (.varispeed, "varispeed")
    case "time_domain": return (.timeDomain, "timeDomain")
    default: return (nil, "default-spectral")
    }
}

func planPitch(_ plan: CompositionPlan) -> String? {
    plan.audioTracks.flatMap(\.segments).compactMap(\.pitch).first
}

// MARK: - Stages

func readTrack(_ row: String, _ fixture: String, stage: String) {
    var rate = 48_000
    if stage == "native", let (_, track) = try? audioTrack(fixture),
       let native = try? nativeRate(track)
    {
        rate = native
    }
    record(row, fixture, stage, "x1", rate: rate, start: 0, speed: 1) { url in
        let (asset, track) = try audioTrack(fixture)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track, outputSettings: floatSettings(rate: rate, channels: 1))
        let (samples, pts) = try drain(reader, output, channels: 1, rate: rate)
        try writeF32(samples, url)
        return pts
    }
}

func speedTag(_ rate: Double?, keep: Bool) -> String {
    guard let rate = rate else { return "x1" }
    return "x\(rate)" + (keep ? "-keep" : "-off")
}

/// The composition alone: `audioMix` nil, the output's algorithm from the plan.
func readComp(
    _ row: String, _ fixture: String, rate speed: Double? = nil, keep: Bool = true,
    readRate: Int = 48_000, tag: String = ""
) {
    let placed: Placed
    do {
        placed = try place(fixture, at: f206, rate: speed, keepPitch: keep)
    } catch {
        record(row, fixture, "comp", speedTag(speed, keep: keep) + tag, rate: readRate,
               start: f206, speed: speed ?? 1) { _ in throw error }
        return
    }
    let pitch = placed.project.plan.flatMap(planPitch)
    let (algo, name) = algorithm(forPitch: pitch)
    record(row, fixture, "comp", speedTag(speed, keep: keep) + tag + "+alg-\(name)",
           rate: readRate, start: placed.start, speed: placed.speed) { url in
        try withBuild(placed) { built, _ in
            let reader = try AVAssetReader(asset: built.composition)
            let output = AVAssetReaderAudioMixOutput(
                audioTracks: built.composition.tracks(withMediaType: .audio),
                audioSettings: floatSettings(rate: readRate, channels: 2))
            output.audioMix = nil
            if let algo = algo { output.audioTimePitchAlgorithm = algo }
            let (samples, pts) = try drain(reader, output, channels: 2, rate: readRate)
            try writeF32(samples, url)
            return pts
        }
    }
}

/// The export's read: the build's `audioMix`, the output's default algorithm.
/// `override` rebuilds each input's parameters through
/// `CompositionBuilder.audioParameters` and sets the named algorithm on them.
func readMix(
    _ row: String, _ fixture: String, at: Ticks = f206, rate speed: Double? = nil,
    keep: Bool = true, override: (AVAudioTimePitchAlgorithm?, String)? = nil, tag: String = ""
) {
    let variant = speedTag(speed, keep: keep) + tag
        + (override.map { "+alg-\($0.1)" } ?? "")
    let placed: Placed
    do {
        placed = try place(fixture, at: at, rate: speed, keepPitch: keep)
    } catch {
        record(row, fixture, "mix", variant, rate: 48_000, start: at, speed: speed ?? 1) { _ in
            throw error
        }
        return
    }
    record(row, fixture, "mix", variant, rate: 48_000, start: placed.start,
           speed: placed.speed) { url in
        try withBuild(placed) { built, plan in
            let tracks = built.composition.tracks(withMediaType: .audio)
            let reader = try AVAssetReader(asset: built.composition)
            let output = AVAssetReaderAudioMixOutput(
                audioTracks: tracks, audioSettings: floatSettings(rate: 48_000, channels: 2))
            if let (algo, _) = override {
                guard let mutable = built.composition as? AVMutableComposition,
                      plan.audioTracks.count == 1
                else { throw ProbeError("the override needs one plan audio track") }
                let planTrack = plan.audioTracks[0]
                let mix = AVMutableAudioMix()
                mix.inputParameters = mutable.tracks(withMediaType: .audio).map { track in
                    let rebuilt = CompositionBuilder.audioParameters(
                        for: track, segments: planTrack.segments, ramps: planTrack.ramps,
                        onset: planTrack.segments.map(\.start).min(), dsp: nil, meter: nil)
                    let parameters = (rebuilt as? AVMutableAudioMixInputParameters)
                        ?? (rebuilt.mutableCopy() as! AVMutableAudioMixInputParameters)
                    parameters.audioTimePitchAlgorithm = algo
                    return parameters
                }
                output.audioMix = mix
            } else {
                output.audioMix = built.audioMix
            }
            let (samples, pts) = try drain(reader, output, channels: 2, rate: 48_000)
            try writeF32(samples, url)
            return pts
        }
    }
}

/// The in-process `audio_wav` export, the main run loop spun until it ends.
func readExport(
    _ row: String, _ fixture: String, at: Ticks = f206, rate speed: Double? = nil,
    keep: Bool = true, noiseReduction: Double? = nil, tag: String = ""
) {
    let variant = speedTag(speed, keep: keep) + tag
    let placed: Placed
    do {
        placed = try place(
            fixture, at: at, rate: speed, keepPitch: keep, noiseReduction: noiseReduction)
    } catch {
        record(row, fixture, "export", variant, rate: 48_000, start: at,
               speed: speed ?? 1) { _ in throw error }
        return
    }
    record(row, fixture, "export", variant, rate: 48_000, start: placed.start,
           speed: placed.speed) { url in
        let settings = try ReelExport.settings(placed.project, preset: "audio_wav")
        let exporter = Exporter()
        var outcome: Result<URL, any Error>?
        exporter.export(
            project: placed.project, urls: placed.urls, settings: settings, to: url,
            progress: { _ in }, completion: { outcome = $0 })
        let deadline = Date().addingTimeInterval(120)
        while outcome == nil, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        switch outcome {
        case .success?:
            return 0
        case .failure(let error)?:
            throw ProbeError("the export failed: \(error.localizedDescription)")
        case nil:
            exporter.cancel()
            throw ProbeError("the export did not end within 120 s")
        }
    }
}

// MARK: - An MP3's other readers (L10, L11, X12)

/// The file's packet table (`kAudioFilePropertyPacketTableInfo`): its
/// priming, remainder and valid frames, or nil when it has none.
func packetTable(_ url: URL) -> (priming: Int64, remainder: Int64, valid: Int64)? {
    var file: AudioFileID?
    guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else {
        return nil
    }
    defer { AudioFileClose(file) }
    var info = AudioFilePacketTableInfo()
    var size = UInt32(MemoryLayout<AudioFilePacketTableInfo>.size)
    guard AudioFileGetProperty(file, kAudioFilePropertyPacketTableInfo, &size, &info) == noErr
    else { return nil }
    return (Int64(info.mPrimingFrames), Int64(info.mRemainderFrames), info.mNumberValidFrames)
}

/// The file through `AVAudioFile` (float, the file's own rate), its channels
/// averaged, from frame 0: no presentation time to place it by.
func readGapless(_ row: String, _ fixture: String) {
    let url = fixtureURL(fixture)
    var extra: [String: Any] = [
        "priming_frames": NSNull(), "remainder_frames": NSNull(), "valid_frames": NSNull(),
    ]
    if let table = packetTable(url) {
        extra = [
            "priming_frames": Int(table.priming), "remainder_frames": Int(table.remainder),
            "valid_frames": Int(table.valid),
        ]
    }
    let rate = (try? AVAudioFile(forReading: url)).map {
        Int($0.processingFormat.sampleRate.rounded())
    } ?? 0
    record(row, fixture, "avaudiofile", "x1", rate: rate, start: 0, speed: 1, extra: extra) {
        out in
        let file = try AVAudioFile(
            forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let channels = Int(format.channelCount)
        guard channels > 0 else { throw ProbeError("the file has no channels") }
        var samples: [Float] = []
        while file.framePosition < file.length {
            let count = AVAudioFrameCount(min(48_000, file.length - file.framePosition))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else {
                throw ProbeError("the buffer could not be made")
            }
            try file.read(into: buffer, frameCount: count)
            let frames = Int(buffer.frameLength)
            guard frames > 0, let data = buffer.floatChannelData else { break }
            for n in 0..<frames {
                var sum: Float = 0
                for c in 0..<channels { sum += data[c][n] }
                samples.append(sum / Float(channels))
            }
        }
        try writeF32(samples, out)
        return 0
    }
}

/// The track's own rate and channel count.
func nativeFormat(_ fixture: String) -> (rate: Int, channels: Int) {
    guard let (_, track) = try? audioTrack(fixture),
          let description = (track.formatDescriptions as? [CMAudioFormatDescription])?.first,
          let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)
    else { return (48_000, 1) }
    return (Int(asbd.pointee.mSampleRate.rounded()), max(1, Int(asbd.pointee.mChannelsPerFrame)))
}

/// `writePeaks`' decode: its output settings verbatim (no rate, no channel
/// count), the track's channels averaged, placed by its first buffer.
func readPeaksDecode(_ row: String, _ fixture: String) {
    let (rate, channels) = nativeFormat(fixture)
    record(row, fixture, "peaks", "x1", rate: rate, start: 0, speed: 1) { url in
        let (asset, track) = try audioTrack(fixture)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
        output.alwaysCopiesSampleData = false
        let (samples, pts) = try drain(reader, output, channels: channels, rate: rate)
        try writeF32(samples, url)
        return pts
    }
}

/// `writeSpeech`'s decode: its output settings verbatim, 16 kHz mono.
func readSpeechDecode(_ row: String, _ fixture: String) {
    let rate = SileroVAD.sampleRate
    record(row, fixture, "speech", "x1", rate: rate, start: 0, speed: 1) { url in
        let (asset, track) = try audioTrack(fixture)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: Double(SileroVAD.sampleRate),
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
        output.alwaysCopiesSampleData = false
        let (samples, pts) = try drain(reader, output, channels: 1, rate: rate)
        try writeF32(samples, url)
        return pts
    }
}

/// The transcription extract: the product's `Transcriber.extractAudio` over
/// the whole asset, a 16 kHz mono WAV.
func readExtract(_ row: String, _ fixture: String) {
    record(row, fixture, "extract", "x1", rate: 16_000, start: 0, speed: 1) { url in
        _ = try Transcriber.extractAudio(
            url: fixtureURL(fixture), name: fixture, range: Transcriber.wholeAsset, to: url,
            cancel: Transcriber.CancelToken())
        return 0
    }
}

/// The sync cache: the product's `writeSyncFeatures` into a cache of its
/// own, then its `.pcm` by `loadSyncSamples` at 8 kHz from 0.
func readSync(_ row: String, _ fixture: String) {
    record(row, fixture, "sync", "x1+\(row)", rate: SyncFeatures.sampleRate, start: 0,
           speed: 1) { out in
        let url = fixtureURL(fixture)
        let media = MediaSnapshot(
            id: 1, path: url.path, kind: .audio, duration: try descriptor(url).duration,
            hasVideo: false, hasAudio: true)
        guard let stamp = MediaImporter.CacheStamp.stamp(for: media, url: url) else {
            throw ProbeError("no cache stamp")
        }
        let folder = outDir.appendingPathComponent("sync-\(fixture)", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        let cache = folder.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: url)
        guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .audio) else {
            throw ProbeError("\(fixture) has no audio track")
        }
        MediaImporter.writeSyncFeatures(
            for: media, asset: asset, track: track, stamp: stamp, into: cache, pass: nil)
        guard let samples = MediaImporter.loadSyncSamples(for: media.id, in: cache) else {
            throw ProbeError("loadSyncSamples answered nil (no cache was published)")
        }
        try writeF32(samples.map { Float($0) / 32767 }, out)
        return 0
    }
}

let mp3Fixtures = ["clicks44-mp3", "clicks48-mp3"]
let residueFixtures = mp3Fixtures + ["clicks44", "clicks48"]

// MARK: - The MP3's encoder delay (L10's trimmed reads, L12)

/// The track at its own rate, read from `MP3Gapless.leadingTrim` when that is
/// not zero (the copy's and the sync reader's start), placed from the trim:
/// the first frame read is index 0.
func readTrimmed(_ row: String, _ fixture: String) {
    let url = fixtureURL(fixture)
    var rate = 48_000
    var trim = CMTime.zero
    if let (asset, track) = try? audioTrack(fixture) {
        if let native = try? nativeRate(track) { rate = native }
        trim = withExtendedLifetime(asset) { MP3Gapless.leadingTrim(of: url, track: track) }
    }
    record(row, fixture, "trimmed", "x1", rate: rate, start: 0, speed: 1,
           extra: ["trim_frames": Int(trim.value)]) { out in
        let (asset, track) = try audioTrack(fixture)
        let reader = try AVAssetReader(asset: asset)
        if trim > .zero {
            reader.timeRange = CMTimeRange(start: trim, duration: .positiveInfinity)
        }
        let output = AVAssetReaderTrackOutput(
            track: track, outputSettings: floatSettings(rate: rate, channels: 1))
        let (samples, pts) = try drain(
            reader, output, channels: 1, rate: rate, origin: CMTimeGetSeconds(trim))
        try writeF32(samples, out)
        return pts
    }
}

/// `MP3Gapless` against what each file is: (a) `tag(at:)` per fixture, (b)
/// `leadingTrim` per fixture, (c) synthetic and damaged tags. Each mismatch is
/// a row error naming the case, the answer and the expectation.
func checkTags(_ row: String) {
    func check(_ name: String, _ answer: String, _ want: String) {
        rowReads[row, default: 0] += 1
        if answer != want {
            rowErrors[row, default: []].append("\(name): answered \(answer), want \(want)")
        }
    }
    func show(_ tag: MP3Gapless.Tag?) -> String {
        tag.map { "Tag(\($0.encoderDelay), \($0.padding), \($0.sampleRate))" } ?? "nil"
    }
    let tags: [String: MP3Gapless.Tag] = [
        "clicks44-mp3": .init(encoderDelay: 576, padding: 792, sampleRate: 44_100),
        "clicks48-mp3": .init(encoderDelay: 576, padding: 960, sampleRate: 48_000),
        "clicks24-mp3": .init(encoderDelay: 576, padding: 768, sampleRate: 24_000),
        "clicks44s-mp3": .init(encoderDelay: 576, padding: 792, sampleRate: 44_100),
    ]
    let trims: [String: CMTime] = [
        "clicks44-mp3": CMTime(value: 576, timescale: 44_100),
        "clicks48-mp3": CMTime(value: 576, timescale: 48_000),
        "clicks24-mp3": CMTime(value: 576, timescale: 24_000),
    ]
    for fixture in fixtureFiles.keys.sorted() {
        let url = fixtureURL(fixture)
        check("(a) tag(at:) \(fixture)", show(MP3Gapless.tag(at: url)), show(tags[fixture]))
        let asset = AVURLAsset(url: url)
        guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .audio) else {
            check("(b) \(fixture)'s audio track", "none", "a track")
            continue
        }
        let trim = withExtendedLifetime(asset) { MP3Gapless.leadingTrim(of: url, track: track) }
        let want = trims[fixture] ?? .zero
        check("(b) leadingTrim \(fixture)", "\(trim.value)/\(trim.timescale)",
              "\(want.value)/\(want.timescale)")
    }

    // (c) synthetic cases, from clicks44-mp3's bytes.
    guard let file = try? Data(contentsOf: fixtureURL("clicks44-mp3")) else {
        check("(c) clicks44-mp3's bytes", "unreadable", "read")
        return
    }
    let bytes = [UInt8](file)
    let offset = MP3Gapless.firstFrameOffset(head: Data(bytes.prefix(10)))
    check("(c) firstFrameOffset clicks44-mp3", "\(offset.map(String.init) ?? "nil")", "44")
    let frame = Array(bytes.dropFirst(44))
    let tag = tags["clicks44-mp3"]
    var wrong: [Int] = []
    for length in 0...2_048 where show(MP3Gapless.tag(frame: Data(frame.prefix(length))))
        != (length < 177 ? "nil" : show(tag))
    {
        wrong.append(length)
    }
    check("(c) prefixes 0…2048 (nil below 177, the tag from 177)",
          wrong.isEmpty ? "as wanted" : "wrong at lengths \(wrong.prefix(8))", "as wanted")
    var xing = frame
    xing.replaceSubrange(21..<25, with: Array("Xing".utf8))
    check("(c) Info→Xing", show(MP3Gapless.tag(frame: Data(xing))), show(tag))
    var stranger = frame
    stranger.replaceSubrange(141..<145, with: Array("XXXX".utf8))
    check("(c) encoder XXXX", show(MP3Gapless.tag(frame: Data(stranger))), "nil")
    var smeared = frame
    for i in 21..<177 { smeared[i] = 0xA5 }
    check("(c) bytes 21..<177 = 0xA5", show(MP3Gapless.tag(frame: Data(smeared))), "nil")

    let folder = outDir.appendingPathComponent("l12", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var lcg: UInt32 = 0
    var noise: [UInt8] = []
    for _ in 0..<4_096 {
        noise.append(UInt8(truncatingIfNeeded: lcg >> 24))
        lcg = lcg &* 1_664_525 &+ 1_013_904_223
    }
    let id3 = Array("ID3".utf8)
    let files: [(String, [UInt8], String)] = [
        ("first-200", Array(bytes.prefix(200)), "nil"),
        ("first-221", Array(bytes.prefix(221)), show(tag)),
        ("id3-size-7f7f7f7f", id3 + [4, 0, 0, 0x7F, 0x7F, 0x7F, 0x7F], "nil"),
        ("id3-size-byte-80", id3 + [4, 0, 0, 0, 0, 0, 0x80], "nil"),
        ("empty", [], "nil"),
        ("id3-3-bytes", id3, "nil"),
        ("lcg-4096", noise, "nil"),
    ]
    for (name, content, want) in files {
        let url = folder.appendingPathComponent("\(name).mp3")
        guard (try? Data(content).write(to: url)) != nil else {
            check("(c) file \(name)", "not written", "written")
            continue
        }
        check("(c) file \(name)", show(MP3Gapless.tag(at: url)), want)
    }
    check("(c) firstFrameOffset of size 0x7F7F7F7F",
          "\(MP3Gapless.firstFrameOffset(head: Data(id3 + [4, 0, 0, 0x7F, 0x7F, 0x7F, 0x7F])).map(String.init) ?? "nil")",
          "\(10 + 0x0FFF_FFFF)")
}

// MARK: - The rows

func lRows() {
    for fixture in allFixtures {
        readTrack("L1", fixture, stage: "asset48")
        readTrack("L2", fixture, stage: "native")
        readComp("L3", fixture)
        readMix("L4", fixture)
        readExport("L5", fixture)
    }
    for fixture in wavFixtures {
        let overrides: [(AVAudioTimePitchAlgorithm?, String)] = [
            (nil, "nil"), (.varispeed, "varispeed"), (.spectral, "spectral"),
            (.timeDomain, "timeDomain"),
        ]
        for override in overrides { readMix("L6", fixture, override: override) }
        for readRate in [16_000, 44_100, 48_000] {
            readComp("L7", fixture, readRate: readRate, tag: "+rate-\(readRate)")
        }
        for speed in [0.99999, 0.5] {
            for keep in [false, true] {
                readComp("L8", fixture, rate: speed, keep: keep)
                readMix("L8", fixture, rate: speed, keep: keep)
                readExport("L8", fixture, rate: speed, keep: keep)
            }
        }
    }
    for fixture in ["clicks16", "clicks48", "cam-ff16"] {
        for (at, name) in [(Ticks(0), "0"), (f206, "F206"), (10 * second, "10s")] {
            readMix("L9", fixture, at: at, tag: "+at-\(name)")
        }
    }
    for fixture in mp3Fixtures {
        readTrack("L10", fixture, stage: "asset48")
        readTrack("L10", fixture, stage: "native")
        readGapless("L10", fixture)
    }
    for fixture in mp3Fixtures + ["clicks24-mp3"] { readTrimmed("L10", fixture) }
    for fixture in ["clicks44s-mp3", "clicks44-mp3-itunsmpb", "clicks44-mp3-noxing", "clicks24-mp3"] {
        readTrack("L10", fixture, stage: "native")
    }
    for fixture in residueFixtures + ["clicks24-mp3"] {
        readPeaksDecode("L11", fixture)
        readSpeechDecode("L11", fixture)
        readExtract("L11", fixture)
    }
    // The reverse renderer's decode is L1's asset48; L1 has no clicks44 or
    // clicks24-mp3 (whose control is clicks44, the WAV it was made from).
    readTrack("L11", "clicks44", stage: "asset48")
    readTrack("L11", "clicks24-mp3", stage: "asset48")
    checkTags("L12")
}

func xRows() {
    // Each variant names its row, so no X file overwrites an L5 or L8 one.
    readExport("X1", "clicks16", tag: "+X1")
    readExport("X2", "clicks44", tag: "+X2")
    readExport("X3", "clicks48", rate: 0.5, keep: false, tag: "+X3")
    readExport("X4", "clicks48", noiseReduction: 0.5, tag: "+X4-nr-0.5")
    readExport("X5", "clicks48", at: 0, noiseReduction: 0.5, tag: "+X5-nr-0.5-at-0")
    readExport("X6", "clicks16", rate: 0.99999, keep: true, tag: "+X6")
    readExport("X7", "clicks48", tag: "+X7")
    readExport("X8", "clicks44-late", tag: "+X8")
    readExport("X9", "clicks16-late5", tag: "+X9")
    readExport("X10", "clicks44-mp3", tag: "+X10")
    readExport("X11", "clicks48-mp3", tag: "+X11")
    for fixture in residueFixtures + ["clicks44s-mp3"] { readSync("X12", fixture) }
    readExport("X13", "clicks44s-mp3", tag: "+X13")
    readExport("X13", "clicks44-mp3-itunsmpb", tag: "+X13")
    readExport("X14", "clicks44-mp3-noxing", tag: "+X14")
    readExport("X15", "clicks24-mp3", tag: "+X15")
}

if group != "X" { lRows() }
if group != "L" { xRows() }
writeAnswer()
exit(0)
