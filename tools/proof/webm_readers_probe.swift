// Road map "codec-export" C3, fix pass 1 (RULING-2) — the measurement made before
// `ExportWebMWriter` took one `AVAssetReader` per output: two readers over the same
// composition (one carrying the video composition output alone, one the audio mix output
// alone) hand back the same frames and the same sound as one reader carrying both.
// `webm_export_proof.py` builds and runs it (row R1).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`
// on `swift_build.py`'s line, beside the tree's `Compositor.metal` and `ExportI010.metal` as
// `default.metallib` and `Blank.mp4`. No window, no app.
//
//   webm_readers_probe <AV.mov> [answer.json]
//
// A1's project (`av1_export_proof.py`'s): a 640 × 360, 30 fps canvas, AV.mov from 0, a
// two-second text clip on a track above. Each configuration gets its own build (its own
// `AVAudioMix` and taps), its reads on two threads at once as the writer runs them, the
// `av1_webm` settings' outputs (`ExportWriter.videoReadOutput` / `audioReadOutput`):
//
//   R1  frames: the same count, every frame's 64RGBAHalf bytes equal, and the I010 the
//       encoder is handed (`ExportI010Converter`, the row's size and picture) byte-equal
//       for the first, middle and last frame; sound: the same 16-bit PCM, sample for sample
import AVFoundation
import Foundation

DecoderSupport.enable()

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1600))])
}

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

func apply(_ project: ReelProject, _ op: ReelOp) throws -> ReelProject {
    switch try project.applying([op]) {
    case .applied(let next): return next
    case .identity: return project
    case .refused(let refusal): throw ProbeError("\(op.name) was refused: \(refusal.reason)")
    }
}

func a1(_ media: URL) throws -> ReelProject {
    var project = try apply(
        ProjectDocument().project, .setCanvas(width: 640, height: 360, fps: Fps(num: 30, den: 1)))
    let asset = AVURLAsset(url: media)
    let video = asset.tracks(withMediaType: .video).first
    let size = video?.naturalSize ?? .zero
    let id = project.snapshot.nextId
    project = try apply(project, .addMedia(descriptor: MediaDescriptor(
        path: media.path, kind: .video, duration: CompositionBuilder.ticks(asset.duration),
        width: Int(size.width), height: Int(size.height), fps: Fps(num: 30, den: 1),
        hasVideo: video != nil, hasAudio: !asset.tracks(withMediaType: .audio).isEmpty)))
    guard let track = project.snapshot.tracks.first?.id else { throw ProbeError("no track") }
    project = try apply(project, .addClip(track: track, media: id, at: 0))
    project = try apply(project, .addTrack(index: project.snapshot.tracks.count, name: "Titles"))
    guard let titles = project.snapshot.tracks.last?.id else { throw ProbeError("no titles") }
    project = try apply(project, .addTextClip(
        track: titles, at: 0, duration: 2 * ReelTime.perSecond, text: TextPatch(content: "AV1")))
    return project
}

struct Read {
    var frames: [Data] = []          // each frame's 64RGBAHalf bytes, row by row
    var i010: [Int: Data] = [:]      // the I010 of the frames asked for
    var audio = Data()
    var errors: [String] = []
}

func pixels(_ buffer: CVPixelBuffer) -> Data {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return Data() }
    let row = CVPixelBufferGetWidth(buffer) * 8
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    var out = Data(capacity: row * CVPixelBufferGetHeight(buffer))
    for y in 0..<CVPixelBufferGetHeight(buffer) {
        out.append(Data(bytes: base + y * stride, count: row))
    }
    return out
}

func planes(_ frame: I010Frame) -> Data {
    let words = frame.buffer.contents().assumingMemoryBound(to: UInt16.self)
    var out = Data()
    for y in 0..<frame.height {
        out.append(Data(bytes: words + y * frame.lumaStride, count: frame.width * 2))
    }
    for offset in [frame.cbOffset, frame.crOffset] {
        for y in 0..<(frame.height + 1) / 2 {
            out.append(Data(
                bytes: words + offset + y * frame.chromaStride, count: (frame.width + 1) / 2 * 2))
        }
    }
    return out
}

/// One configuration: `split` two readers (one output each), else one reader with both.
func read(_ project: ReelProject, urls: [UInt32: URL], split: Bool, keep: Set<Int>) throws -> Read {
    guard let plan = project.plan else { throw ProbeError("no plan") }
    let key = RecipeSource.shared.register()
    defer { RecipeSource.shared.unregister(key) }
    RecipeSource.shared.set(project, for: key)
    RecipeSource.shared.setOptions(.none, for: key)
    let built = try CompositionBuilder.build(
        plan: plan, planJSON: project.planJSON, urls: urls, recipeKey: key)
    let settings = try ReelExport.settings(project, preset: "av1_webm")
    let range = Exporter.timeRange(settings, composition: built.composition)
    let videoOutput = ExportWriter.videoReadOutput(built, settings: settings)
    let audioOutput = ExportWriter.audioReadOutput(built, gained: false)
    let videoReader = try AVAssetReader(asset: built.composition)
    let audioReader = split ? try AVAssetReader(asset: built.composition) : videoReader
    videoReader.timeRange = range
    if split { audioReader.timeRange = range }
    videoReader.add(videoOutput)
    audioReader.add(audioOutput)
    guard videoReader.startReading(), !split || audioReader.startReading() else {
        throw ProbeError("startReading failed: \(videoReader.error ?? audioReader.error as Any)")
    }
    let frame = ExportWriter.encodedSize(settings)
    let canvas = built.videoComposition.renderSize
    let converter = try ExportI010Converter(
        width: frame.width, height: frame.height, canvas: canvas,
        fills: ExportWriter.fillsTheBox(settings, canvas: canvas),
        picture: ExportAV1Picture(color: settings.color), pool: 3)
    var result = Read()
    let lock = NSLock()
    let group = DispatchGroup()
    DispatchQueue.global().async(group: group) {
        var index = 0
        while let sample = videoOutput.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let bytes = pixels(buffer)
            var converted: Data?
            if keep.contains(index), let i010 = converter.convert(buffer) {
                converted = planes(i010)
                converter.recycle(i010)
            }
            lock.lock()
            result.frames.append(bytes)
            if let converted { result.i010[index] = converted }
            lock.unlock()
            index += 1
        }
        if videoReader.status == .failed {
            lock.lock()
            result.errors.append("video: \(videoReader.error as Any)")
            lock.unlock()
        }
    }
    DispatchQueue.global().async(group: group) {
        var sound = Data()
        while let sample = audioOutput.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var bytes = Data(count: length)
            _ = bytes.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
            }
            sound.append(bytes)
        }
        lock.lock()
        result.audio = sound
        if audioReader.status == .failed { result.errors.append("audio: \(audioReader.error as Any)") }
        lock.unlock()
    }
    group.wait()
    return result
}

let arguments = CommandLine.arguments
do {
    guard arguments.count > 1 else { throw ProbeError("usage: webm_readers_probe <AV.mov>") }
    let media = URL(fileURLWithPath: arguments[1])
    let project = try a1(media)
    var urls: [UInt32: URL] = [:]
    for item in project.snapshot.media { urls[item.id] = URL(fileURLWithPath: item.path) }
    let keep: Set<Int> = [0, 75, 149]
    let one = try read(project, urls: urls, split: false, keep: keep)
    let two = try read(project, urls: urls, split: true, keep: keep)
    let unequal = zip(one.frames, two.frames).enumerated().filter { $0.element.0 != $0.element.1 }
        .map(\.offset)
    let i010 = keep.sorted().map { (index: $0, equal: one.i010[$0] != nil && one.i010[$0] == two.i010[$0],
                                    bytes: one.i010[$0]?.count ?? 0) }
    let firstSampleDiff = zip(one.audio, two.audio).enumerated().first { $0.element.0 != $0.element.1 }?
        .offset
    let distinct = Set(one.frames).count
    let ok = distinct > 1 && one.errors.isEmpty && two.errors.isEmpty && one.frames.count == 150
        && one.frames.count == two.frames.count && unequal.isEmpty
        && i010.allSatisfy(\.equal) && one.audio.count == 240_000 * 4 && one.audio == two.audio
    check("R1 two readers (one output each) read A1's project as one reader with both",
          ok, "\(distinct) distinct frames; frames \(one.frames.count) / \(two.frames.count) (want 150), unequal 64RGBAHalf "
            + "frames \(unequal.prefix(8)); I010 \(i010.map { "#\($0.index) \($0.bytes) bytes equal \($0.equal)" }); "
            + "audio \(one.audio.count / 4) / \(two.audio.count / 4) frames (want 240000), equal "
            + "\(one.audio == two.audio), first differing byte \(firstSampleDiff.map(String.init) ?? "none"); "
            + "errors \(one.errors + two.errors)")
} catch {
    check("R1 two readers (one output each) read A1's project as one reader with both", false,
          "\(error)")
}

let answer = try JSONSerialization.data(withJSONObject: ["rows": rows], options: [.prettyPrinted])
if arguments.count > 2 {
    try answer.write(to: URL(fileURLWithPath: arguments[2]))
} else {
    FileHandle.standardOutput.write(answer)
}
exit(0)
