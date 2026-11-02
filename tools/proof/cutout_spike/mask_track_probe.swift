// Road map "creator-jobs" CO0, spike CO-S2 — how the mask reaches the
// compositor. Compiled AS `main.swift` over every file in `app/Sources` but
// the app's own `main.swift`, with `mask_track_writer.swift`, against
// `libframejob_core.a`, through `swift_build.build` (optimized), with
// `Blank.mp4` and `default.metallib` beside the binary (`cutout_spike.py`).
//
//   mask_track_probe fixtures <media> [barcode|barcode_rev|long_60m]
//   mask_track_probe registration <work> <media> <encoding> <L>
//   mask_track_probe colour <work> <media> <encoding>
//   mask_track_probe codec <work> <dump> <movie> <encoding> <L>
//   mask_track_probe playback <work> <media> <encoding> <L> <rate>
//   mask_track_probe build <work> <media> <encoding> <L> <rate>
//   mask_track_probe fixed <work> <encoding>
//   mask_track_probe pack <work> <media> <part>   (part: registration|colour|playback|build)
//
// Each mode's last stdout line is `ANSWER <json>`; it decides nothing (the
// runner's `deciders.py` does).
//
// A case is a project built through `ReelProject`/`ReelOps` (1920×1080 at
// 30 fps, the `export_offset_probe.swift` way), planned by the core and built
// by `CompositionBuilder.build` with a `RecipeSource` key and an empty
// `ReverseResolution` published (the reversed clip's file in `ready`, as
// `audio_ap10c_probe.swift` publishes). Then, on the built composition: one
// mask track per picture plan track that shows a cut-out media, id `2001 + i`
// (i the plan track's index), made by `CompositionBuilder.makeTrack` and
// filled by `CompositionBuilder.fill` with an empty resolution; its segments
// copy the picture segments, cut at chunk boundaries in source ticks
// (reversed: in reversed-stream ticks at T − kL), each part's start and
// duration by the segment's linear map in ticks (nearest tick, the last part
// the remainder), each part's `media` a synthetic id per chunk file, decoded
// through `PlanSegment`'s own decoder. The video composition is the built
// configuration with `customVideoCompositorClass` the probe class (the
// subclass of the class the build chose) and every `RecipeInstruction`'s
// required ids plus the mask ids.
import AVFoundation
import AppKit
import CoreMedia

NSApplication.shared.setActivationPolicy(.prohibited)

let mediaSecond: Ticks = 600_000
let timescale600: Int64 = 600
let ticksPerUnit: Int64 = 1000   // ticks per 1/600 s
let firstMaskID = 2001
let arguments = CommandLine.arguments

func mediaDir(_ i: Int) -> URL { URL(fileURLWithPath: arguments[i], isDirectory: true) }

func answer(_ object: Any) {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    print("ANSWER " + String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("mask_track_probe: \(message)\n".utf8))
    answer(["ok": false, "error": message])
    exit(1)
}

// MARK: - The recorder and the probe compositors

/// What the probe compositor saw. One lock; every request appends.
final class ProbeRecorder: @unchecked Sendable {
    static let shared = ProbeRecorder()
    enum Mode { case count, registration, colour, pack }
    private let lock = NSLock()
    var mode = Mode.count
    /// (picture track id, mask track id) pairs to read.
    var pairs: [(Int32, Int32)] = []
    private(set) var requests = 0
    private(set) var records: [[Int]] = []      // [ticks, picture track, picture, mask]
    private(set) var colour: [Int: [Float]] = [:] // mask index → R × 255, row-packed
    /// Pack mode: composition ticks → the mask index the pack shows there.
    var packLookup: ((Ticks, Int32) -> (index: Int, bytes: [UInt8])?)?

    func reset(_ mode: Mode, pairs: [(Int32, Int32)]) {
        lock.lock()
        self.mode = mode
        self.pairs = pairs
        requests = 0
        records = []
        colour = [:]
        lock.unlock()
    }

    func observe(_ request: AVAsynchronousVideoCompositionRequest) {
        lock.lock()
        requests += 1
        let mode = self.mode, pairs = self.pairs, lookup = packLookup
        lock.unlock()
        guard mode != .count else { return }
        let ticks = CompositionBuilder.ticks(request.compositionTime)
        for (picture, mask) in pairs {
            guard let pictureBuffer = request.sourceFrame(byTrackID: picture) else { continue }
            let pictureIndex = readCode(pictureBuffer, bandY: 0.5)
            var maskIndex = -1
            if mode == .pack {
                if let found = lookup?(ticks, picture) {
                    maskIndex = found.index
                    _ = found.bytes.count
                }
            } else if let maskBuffer = request.sourceFrame(byTrackID: mask) {
                maskIndex = readCode(maskBuffer, bandY: maskBandY)
                if mode == .colour {
                    lock.lock()
                    let seen = colour[maskIndex] != nil
                    lock.unlock()
                    if !seen {
                        let values = redPlane(maskBuffer)
                        lock.lock()
                        colour[maskIndex] = values
                        lock.unlock()
                    }
                }
            }
            lock.lock()
            records.append([Int(ticks), Int(picture), pictureIndex, maskIndex])
            lock.unlock()
        }
    }
}

class ProbeCompositor: Compositor {
    override func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        ProbeRecorder.shared.observe(asyncVideoCompositionRequest)
        super.startRequest(asyncVideoCompositionRequest)
    }
}

/// `ConvertingCompositor` is `final`; this is its whole body.
final class ProbeConvertingCompositor: ProbeCompositor {
    override var canConformColorOfSourceFrames: Bool { true }
    override var supportsHDRSourceFrames: Bool { true }
}

/// A 64RGBAHalf buffer's R at (x, y), or a bi-planar buffer's luma / 255.
func withLevels<T>(_ buffer: CVPixelBuffer, _ body: (Int, Int, (Int, Int) -> Float) -> T) -> T {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    switch CVPixelBufferGetPixelFormatType(buffer) {
    case kCVPixelFormatType_64RGBAHalf:
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        return body(width, height) { x, y in
            Float((base + y * stride).assumingMemoryBound(to: Float16.self)[4 * x])
        }
    default:
        let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        return body(width, height) { x, y in Float(base[y * stride + x]) / 255 }
    }
}

func readCode(_ buffer: CVPixelBuffer, bandY: Double) -> Int {
    withLevels(buffer) { w, h, level in BarCode.read(width: w, height: h, bandY: bandY, level: level) }
}

func redPlane(_ buffer: CVPixelBuffer) -> [Float] {
    withLevels(buffer) { w, h, level in
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { out[y * w + x] = level(x, y) * 255 } }
        return out
    }
}

// MARK: - Sources, analysed frames and chunks

/// Every sample's presentation time of a movie's video track, in 1/600 s.
func sourceFrames(_ url: URL) throws -> [Int64] {
    let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .video) else {
        throw SpikeError("\(url.lastPathComponent): no video")
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(output)
    guard reader.startReading() else { throw SpikeError("frames: \(String(describing: reader.error))") }
    var out: [Int64] = []
    while let sample = output.copyNextSampleBuffer() {
        guard CMSampleBufferGetNumSamples(sample) > 0 else { continue }
        out.append(CMTimeConvertScale(CMSampleBufferGetPresentationTimeStamp(sample),
                                      timescale: 600, method: .roundHalfAwayFromZero).value)
    }
    return out.sorted()
}

/// CJ-23's sample rule in 1/600 s: every frame, or the first frame at or
/// after each k / rate s.
func analysedFrames(_ frames: [Int64], rate: String) -> [Int64] {
    guard rate != "every", let r = Int64(rate) else { return frames }
    var picked: [Int64] = [], k: Int64 = 0, at = 0
    while true {
        while at < frames.count, frames[at] * r < k * 600 { at += 1 }
        if at >= frames.count { break }
        if picked.last != frames[at] { picked.append(frames[at]) }
        k += 1
    }
    return picked
}

/// One source's frames (1/600 s) and its model duration.
struct Source {
    let name: String
    let url: URL
    let frames: [Int64]
    let duration: Ticks

    init(_ name: String, media: URL) throws {
        self.name = name
        url = media.appendingPathComponent("\(name).mov")
        frames = try sourceFrames(url)
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        duration = CompositionBuilder.ticks(asset.duration)
    }

    /// The pivot T in 1/600 s.
    var pivotUnits: Int64 { duration / ticksPerUnit }

    /// Each frame's end: the next frame's time; the track's end for the last.
    func end(of frame: Int64) -> Int64 {
        var lo = 0, hi = frames.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if frames[mid] <= frame { lo = mid + 1 } else { hi = mid }
        }
        return lo < frames.count ? frames[lo] : pivotUnits
    }
}

/// A source's chunk files at one (encoding, L, rate): forward `<k>.mov` and
/// mirrored `r<k>.mov`, written on demand.
final class Chunks {
    let source: Source
    let encoding: MaskEncoding
    let length: Int64          // L in 1/600 s
    let rate: String
    let folder: URL
    let analysed: [Int64]
    private var mirroredAnalysed: [Int64] = []
    private var mirroredIndex: [Int64: Int64] = [:]
    private(set) var written = 0

    init(_ source: Source, encoding: MaskEncoding, seconds: Int, rate: String, work: URL) {
        self.source = source
        self.encoding = encoding
        length = Int64(seconds) * 600
        self.rate = rate
        folder = work.appendingPathComponent(
            "chunks/\(encoding.rawValue)/\(seconds)/\(rate)/\(source.name)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        analysed = analysedFrames(source.frames, rate: rate)
        // The mirrored analysed times, `reversed_time(pts, end, T) = T − end`.
        for a in analysed {
            let m = source.pivotUnits - source.end(of: a)
            mirroredAnalysed.append(m)
            mirroredIndex[m] = a
        }
        mirroredAnalysed.sort()
    }

    var lengthTicks: Ticks { length * ticksPerUnit }

    func forward(_ k: Int64) throws -> URL {
        let url = folder.appendingPathComponent("\(k).mov")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let window = (k * length)..<((k + 1) * length)
        let samples = chunkSamples(frames: source.frames, analysed: analysed, window: window)
        try writeChunk(url, encoding: encoding, width: maskWidth, height: maskHeight,
                       timescale: 600, length: length,
                       samples: samples.map { s in (s.time, { barcodeMask(Int(s.analysed / 20)) }) })
        written += 1
        return url
    }

    /// Chunk k's window in the reversed stream, [T − (k+1)L, T − kL): each
    /// reversed frame shows its nearest over the mirrored analysed times.
    func mirrored(_ k: Int64) throws -> URL {
        let url = folder.appendingPathComponent("r\(k).mov")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let pivot = source.pivotUnits
        let window = (pivot - (k + 1) * length)..<(pivot - k * length)
        // The reversed stream's frames: each forward frame at T − end.
        let reversedFrames = source.frames.map { pivot - source.end(of: $0) }.sorted()
        let samples = chunkSamples(frames: reversedFrames, analysed: mirroredAnalysed, window: window)
        try writeChunk(url, encoding: encoding, width: maskWidth, height: maskHeight,
                       timescale: 600, length: length,
                       samples: samples.map { s in
                           (s.time, { barcodeMask(Int(self.mirroredIndex[s.analysed]! / 20)) })
                       })
        written += 1
        return url
    }
}

// MARK: - Projects

struct Placed {
    var project: ReelProject
    var reversed: [UInt32: URL] = [:]
}

func apply(_ project: ReelProject, _ op: ReelOp) throws -> ReelProject {
    switch try project.applying([op]) {
    case .applied(let next): return next
    case .identity: return project
    case .refused(let refusal): throw SpikeError("\(op.name) was refused: \(refusal.reason)")
    }
}

func descriptor(_ url: URL) throws -> MediaDescriptor {
    let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    guard let video = CompositionBuilder.firstTrack(of: asset, mediaType: .video) else {
        throw SpikeError("\(url.lastPathComponent) has no video")
    }
    let size = video.naturalSize
    return MediaDescriptor(
        path: url.path, kind: .video, duration: CompositionBuilder.ticks(asset.duration),
        width: Int(size.width), height: Int(size.height), fps: Fps(num: 30, den: 1),
        hasVideo: true, hasAudio: false)
}

/// A project of `canvas` at 30 fps with `sources` added as media; answers it
/// and each source's media id.
func project(_ sources: [Source], width: Int = 1920, height: Int = 1080, hlg: Bool = false)
    throws -> (ReelProject, [String: UInt32])
{
    var project = try apply(ProjectDocument().project,
                            .setCanvas(width: width, height: height, fps: Fps(num: 30, den: 1)))
    if hlg { project = try apply(project, .setCanvas(output: .hlg)) }
    var ids: [String: UInt32] = [:]
    for source in sources {
        ids[source.name] = project.snapshot.nextId
        project = try apply(project, .addMedia(descriptor: try descriptor(source.url)))
    }
    return (project, ids)
}

/// Adds a clip of `media` at `at` and trims it to the played window
/// [from, to) (seconds of the stream it plays), left at `at`.
func addWindow(_ project: inout ReelProject, track: UInt32, media: UInt32, at: Ticks,
               from: Double, to: Double, reversed: Bool = false) throws -> UInt32 {
    let clip = project.snapshot.nextId
    project = try apply(project, .addClip(track: track, media: media, at: at))
    guard project.snapshot.clip(clip) != nil else { throw SpikeError("add_clip minted no clip") }
    if reversed { project = try apply(project, .setReversed(clip: clip, reversed: true)) }
    let a = Ticks((from * Double(mediaSecond)).rounded()), b = Ticks((to * Double(mediaSecond)).rounded())
    project = try apply(project, .trimEnd(clip: clip, to: at + b))
    project = try apply(project, .trimStart(clip: clip, to: at + a))
    project = try apply(project, .moveClip(clips: [clip], delta: -a))
    return clip
}

struct Case {
    let name: String
    let source: String
    let reversed: Bool
    let make: (inout Placed, [String: UInt32], UInt32, Source) throws -> Void
}

let cases: [Case] = [
    Case(name: "trim", source: "barcode", reversed: false) { p, ids, track, _ in
        _ = try addWindow(&p.project, track: track, media: ids["barcode"]!, at: 0, from: 28, to: 32)
    },
    Case(name: "x0.5", source: "barcode", reversed: false) { p, ids, track, _ in
        let clip = try addWindow(&p.project, track: track, media: ids["barcode"]!, at: 0, from: 29, to: 31)
        p.project = try apply(p.project, .setSpeed(clip: clip, rate: 0.5))
    },
    Case(name: "x2", source: "barcode", reversed: false) { p, ids, track, _ in
        let clip = try addWindow(&p.project, track: track, media: ids["barcode"]!, at: 0, from: 26, to: 34)
        p.project = try apply(p.project, .setSpeed(clip: clip, rate: 2))
    },
    Case(name: "x1.37", source: "barcode", reversed: false) { p, ids, track, _ in
        let clip = try addWindow(&p.project, track: track, media: ids["barcode"]!, at: 0, from: 28, to: 33.5)
        p.project = try apply(p.project, .setSpeed(clip: clip, rate: 1.37))
    },
    Case(name: "ramp", source: "barcode", reversed: false) { p, ids, track, _ in
        let clip = try addWindow(&p.project, track: track, media: ids["barcode"]!, at: 0, from: 28, to: 34)
        p.project = try apply(p.project, .addSpeedRamp(clip: clip, shape: .rampUp, rate: 2))
    },
    Case(name: "freeze", source: "barcode", reversed: false) { p, ids, track, _ in
        let clip = try addWindow(&p.project, track: track, media: ids["barcode"]!, at: 0, from: 28, to: 32)
        // Timeline 59 frames shows source frame 899, chunk 0's last at every L.
        p.project = try apply(p.project, .freezeFrame(clip: clip, at: 59 * 20_000))
    },
    Case(name: "reverse", source: "barcode", reversed: true) { p, ids, track, source in
        let clip = try addWindow(&p.project, track: track, media: ids["barcode"]!, at: 0, from: 128,
                                 to: 132, reversed: true)
        p.reversed[clip] = source.url.deletingLastPathComponent()
            .appendingPathComponent("barcode_rev.mov")
    },
    Case(name: "split", source: "barcode", reversed: false) { p, ids, track, _ in
        _ = try addWindow(&p.project, track: track, media: ids["barcode"]!, at: 0, from: 28, to: 32)
        p.project = try apply(p.project, .split(clips: nil, at: mediaSecond))
    },
    Case(name: "nest", source: "barcode", reversed: false) { p, ids, track, _ in
        let clip = try addWindow(&p.project, track: track, media: ids["barcode"]!, at: 0, from: 28, to: 32)
        p.project = try apply(p.project, .nest(clips: [clip]))
    },
    Case(name: "cross-dissolve", source: "barcode", reversed: false) { p, ids, track, _ in
        _ = try addWindow(&p.project, track: track, media: ids["barcode"]!, at: 0, from: 27, to: 31)
        let b = try addWindow(&p.project, track: track, media: ids["barcode"]!, at: 4 * mediaSecond,
                              from: 29, to: 33)
        p.project = try apply(p.project, .addTransition(clip: b, kind: .crossDissolve,
                                                        duration: mediaSecond, align: .center))
    },
    Case(name: "hlg-vfr", source: "hlg_vfr", reversed: false) { p, ids, track, _ in
        _ = try addWindow(&p.project, track: track, media: ids["hlg_vfr"]!, at: 0, from: 28, to: 32)
    },
]

// MARK: - Builds with mask tracks

/// The key, the plan and the build, with the resolution published.
struct Build {
    let key: Int
    let plan: CompositionPlan
    let built: BuiltComposition
}

func build(_ placed: Placed) throws -> Build {
    let key = RecipeSource.shared.register()
    RecipeSource.shared.set(placed.project, for: key)
    RecipeSource.shared.setOptions(.none, for: key)
    AudioDSPSource.shared.publish(AudioDSPParameters(snapshot: placed.project.snapshot), for: key)
    ReverseSource.shared.publish(
        ReverseResolution(ready: placed.reversed, pending: []), project: placed.project, for: key)
    guard let plan = placed.project.plan else { throw SpikeError("no plan") }
    let mediaURLs = Dictionary(uniqueKeysWithValues: placed.project.snapshot.media.map {
        ($0.id, URL(fileURLWithPath: $0.path))
    })
    let built = try CompositionBuilder.build(
        plan: plan, planJSON: placed.project.planJSON, urls: mediaURLs, recipeKey: key)
    return Build(key: key, plan: plan, built: built)
}

func release(_ build: Build) {
    ReverseSource.shared.unpublish(build.key)
    RecipeSource.shared.unregister(build.key)
}

func scaled(_ value: Int64, _ num: Int64, _ den: Int64) -> Int64 {
    let (product, overflow) = value.multipliedReportingOverflow(by: num)
    if overflow { return Int64((Double(value) * Double(num) / Double(den)).rounded()) }
    // Nearest tick, halves away from zero.
    let q = product / den, r = product % den
    return 2 * abs(r) >= den ? q + (product >= 0 ? 1 : -1) : q
}

/// The mask segments for one picture plan track, and their chunk files.
func maskSegments(
    _ segments: [PlanSegment], chunks: [UInt32: Chunks], reversedClips: Set<UInt32>,
    urls: inout [UInt32: URL], ids: inout [URL: UInt32]
) throws -> [PlanSegment] {
    var json: [[String: Any]] = []
    for s in segments where s.duration > 0 && s.sourceDuration > 0 {
        guard let set = chunks[s.media] else { continue }
        let L = set.lengthTicks
        let T = set.source.duration
        let reversed = reversedClips.contains(s.clip)
        let a = s.sourceIn, b = s.sourceIn + s.sourceDuration
        var cuts: [Ticks] = [a]
        if reversed {
            // Boundaries T − kL strictly inside (a, b): kL in (T − b, T − a).
            var k = max(0, (T - b) / L + 1)
            while k * L < T - a {
                if T - k * L < b, T - k * L > a { cuts.append(T - k * L) }
                k += 1
            }
            cuts.sort()
        } else {
            var c = (a / L + 1) * L
            while c < b { cuts.append(c); c += L }
        }
        cuts.append(b)
        var starts: [Ticks] = []
        for c in cuts.dropLast() { starts.append(s.start + scaled(c - a, s.duration, s.sourceDuration)) }
        for i in 0..<(cuts.count - 1) {
            let p0 = cuts[i], p1 = cuts[i + 1]
            let start = starts[i]
            let end = i + 1 < starts.count ? starts[i + 1] : s.start + s.duration
            let k: Int64, chunkStart: Ticks, url: URL
            if reversed {
                k = (T - p0 - 1) / L
                chunkStart = T - (k + 1) * L
                url = try set.mirrored(k)
            } else {
                k = p0 / L
                chunkStart = k * L
                url = try set.forward(k)
            }
            let id: UInt32
            if let known = ids[url] { id = known } else {
                id = UInt32(100_000 + ids.count)
                ids[url] = id
                urls[id] = url
            }
            json.append(["clip": s.clip, "media": id, "source_in": p0 - chunkStart,
                         "source_duration": p1 - p0, "start": start, "duration": end - start])
        }
    }
    let data = try JSONSerialization.data(withJSONObject: json)
    return try ReelJSON.decoder().decode([PlanSegment].self, from: data)
}

/// Adds the mask tracks; answers the probe's configuration and the pairs.
func addMasks(
    _ b: Build, chunks: [UInt32: Chunks], reversedClips: Set<UInt32>,
    probeClass: (any AVVideoCompositing.Type)? = nil
) throws -> (AVVideoComposition.Configuration, [(Int32, Int32)], Int) {
    guard let composition = b.built.composition as? AVMutableComposition else {
        throw SpikeError("the built composition is not mutable")
    }
    var urls: [UInt32: URL] = [:], ids: [URL: UInt32] = [:]
    var pairs: [(Int32, Int32)] = []
    var assets: [UInt32: AVURLAsset] = [:], reversedAssets: [UInt32: AVURLAsset] = [:]
    for (i, planTrack) in b.plan.videoTracks.enumerated() {
        guard planTrack.segments.contains(where: { chunks[$0.media] != nil }) else { continue }
        let segments = try maskSegments(planTrack.segments, chunks: chunks,
                                         reversedClips: reversedClips, urls: &urls, ids: &ids)
        let id = firstMaskID + i
        let track = try CompositionBuilder.makeTrack(in: composition, mediaType: .video, id: id)
        try CompositionBuilder.fill(
            track, segments: segments, mediaType: .video, urls: urls,
            reverse: ReverseResolution(ready: [:], pending: []), assets: &assets,
            reversedAssets: &reversedAssets)
        pairs.append((Int32(planTrack.id), Int32(id)))
    }
    var configuration = b.built.videoConfiguration
    let maskIDs = pairs.map { Int($0.1) }
    configuration.instructions = configuration.instructions.map { item in
        guard let r = item as? RecipeInstruction else { return item }
        let required = (r.requiredSourceTrackIDs ?? []).compactMap { ($0 as? NSNumber)?.intValue }
        return RecipeInstruction(
            timeRange: r.timeRange, requiredTrackIDs: required + maskIDs, recipeKey: r.recipeKey,
            mediaURLs: r.mediaURLs, sourceOrientations: r.sourceOrientations,
            missingClips: r.missingClips, fullRangeTracks: r.fullRangeTracks)
    }
    configuration.customVideoCompositorClass = probeClass ?? probe(for: b.built)
    return (configuration, pairs, ids.count)
}

func probe(for built: BuiltComposition) -> any AVVideoCompositing.Type {
    built.videoConfiguration.customVideoCompositorClass == ConvertingCompositor.self
        ? ProbeConvertingCompositor.self : ProbeCompositor.self
}

/// Every frame of the composition through `AVAssetReaderVideoCompositionOutput`.
func readAll(_ composition: AVComposition, _ configuration: AVVideoComposition.Configuration)
    throws -> Int
{
    let reader = try AVAssetReader(asset: composition)
    let output = AVAssetReaderVideoCompositionOutput(
        videoTracks: composition.tracks(withMediaType: .video),
        videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(Compositor.outputPixelFormat),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
    output.videoComposition = AVVideoComposition(configuration: configuration)
    reader.add(output)
    guard reader.startReading() else { throw SpikeError("read: \(String(describing: reader.error))") }
    var frames = 0
    while let sample = output.copyNextSampleBuffer() {
        if CMSampleBufferGetImageBuffer(sample) != nil { frames += 1 }
    }
    guard reader.status == .completed else {
        throw SpikeError("read ended \(reader.status.rawValue): \(String(describing: reader.error))")
    }
    return frames
}

// MARK: - (5) playback and (6) build

/// The playback project: `screen_4k` on the first track under five 4 s
/// `barcode` clips at sources kL − 2 s … kL + 2 s (k = 1…5) on a second,
/// 3840×2160 at 30 fps.
func playbackProject(_ screen: Source, _ barcode: Source, seconds: Int)
    throws -> (Placed, [String: UInt32])
{
    let (base, ids) = try project([screen, barcode], width: 3840, height: 2160)
    var placed = Placed(project: try apply(base, .addTrack(index: 1)))
    let tracks = placed.project.snapshot.tracks.map(\.id)
    _ = try addWindow(&placed.project, track: tracks[0], media: ids["screen_4k"]!, at: 0,
                      from: 0, to: 20)
    for k in 1...5 {
        let centre = Double(k * seconds)
        _ = try addWindow(&placed.project, track: tracks[1], media: ids["barcode"]!,
                          at: Ticks(k - 1) * 4 * mediaSecond, from: centre - 2, to: centre + 2)
    }
    return (placed, ids)
}

/// Plays `composition` for 20 s through an `AVPlayer` whose
/// `AVPlayerItemVideoOutput` a 60 Hz main-run-loop timer pulls; answers the
/// compositor requests counted.
func play(_ composition: AVComposition, _ configuration: AVVideoComposition.Configuration,
          mode: ProbeRecorder.Mode, pairs: [(Int32, Int32)]) throws -> Int {
    let item = AVPlayerItem(asset: composition)
    item.videoComposition = AVVideoComposition(configuration: configuration)
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(Compositor.outputPixelFormat),
    ])
    item.add(output)
    let player = AVPlayer(playerItem: item)
    player.isMuted = true
    let deadline = Date().addingTimeInterval(20)
    while item.status != .readyToPlay {
        if item.status == .failed { throw SpikeError("item: \(String(describing: item.error))") }
        if Date() > deadline { throw SpikeError("the item never became ready") }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    ProbeRecorder.shared.reset(mode, pairs: pairs)
    player.play()
    let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        if output.hasNewPixelBuffer(forItemTime: time) {
            _ = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
        }
    }
    RunLoop.main.add(timer, forMode: .common)
    RunLoop.main.run(until: Date().addingTimeInterval(20))
    timer.invalidate()
    player.pause()
    let count = ProbeRecorder.shared.requests
    ProbeRecorder.shared.reset(.count, pairs: [])
    return count
}

func median(_ values: [Double]) -> Double {
    let s = values.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

/// `long_60m` as 120 clips of 30 s (one clip split every 30 s).
func longProject(_ long: Source) throws -> (Placed, [String: UInt32]) {
    let (base, ids) = try project([long])
    var placed = Placed(project: base)
    let track = placed.project.snapshot.tracks.first!.id
    placed.project = try apply(placed.project, .addClip(track: track, media: ids["long_60m"]!, at: 0))
    for i in 1..<120 {
        placed.project = try apply(placed.project, .split(clips: nil, at: Ticks(i) * 30 * mediaSecond))
    }
    return (placed, ids)
}

// MARK: - The per-media mask pack (`--pack`, or when the track fails)

/// One file per media: a header, the frame table (every source frame's time
/// in 1/600 s and its nearest analysed mask's slot), the offset table (each
/// distinct analysed mask's time, offset and length) and each distinct
/// analysed mask once, 512×288 8-bit, `NSData.compressed(using: .lzfse)`.
/// `tablesOnly` writes no masks (lengths 0): `long_60m`'s pack for (6),
/// whose build reads the tables and nothing else.
func writePack(_ url: URL, source: Source, rate: String, tablesOnly: Bool = false) throws {
    let analysed = analysedFrames(source.frames, rate: rate)
    var slot: [Int64: UInt32] = [:]
    for (i, a) in analysed.enumerated() { slot[a] = UInt32(i) }
    let shown = chunkSamples(frames: source.frames, analysed: analysed,
                             window: 0..<(source.pivotUnits + 1))
    // The frame table from the nearest-hold rule, frame by frame.
    var table = Data(), offsets = Data(), blobs = Data()
    var cursor = 0, next = 0
    var lastAnalysed = shown.first?.analysed ?? 0
    for frame in source.frames {
        while next < shown.count, shown[next].time <= frame {
            lastAnalysed = shown[next].analysed
            next += 1
        }
        var t = frame, s = slot[lastAnalysed]!
        table.append(Data(bytes: &t, count: 8))
        table.append(Data(bytes: &s, count: 4))
    }
    for a in analysed {
        var blob = Data()
        if !tablesOnly {
            blob = try (Data(barcodeMask(Int(a / 20))) as NSData).compressed(using: .lzfse) as Data
        }
        var time = a, offset = UInt64(cursor), length = UInt32(blob.count)
        offsets.append(Data(bytes: &time, count: 8))
        offsets.append(Data(bytes: &offset, count: 8))
        offsets.append(Data(bytes: &length, count: 4))
        blobs.append(blob)
        cursor += blob.count
    }
    var header = Data("FJMP".utf8)
    let counts = [UInt32(source.frames.count), UInt32(analysed.count), UInt32(maskWidth),
                  UInt32(maskHeight)]
    header.append(counts.withUnsafeBytes { Data($0) })
    header.append(table)
    header.append(offsets)
    header.append(blobs)
    try header.write(to: url)
}

/// A pack read back: the tables always, the masks on demand.
final class Pack {
    let frames: [Int64]
    let slots: [UInt32]
    let analysed: [Int64]
    let offsets: [(UInt64, UInt32)]
    let data: Data
    let base: Int

    init(_ url: URL) throws {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        self.data = data
        guard data.count >= 20, data.prefix(4) == Data("FJMP".utf8) else {
            throw SpikeError("\(url.lastPathComponent) is not a pack")
        }
        func u32(_ at: Int) -> UInt32 { data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt32.self) } }
        func i64(_ at: Int) -> Int64 { data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: Int64.self) } }
        func u64(_ at: Int) -> UInt64 { data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt64.self) } }
        let frameCount = Int(u32(4)), maskCount = Int(u32(8))
        var at = 20
        var frames: [Int64] = [], slots: [UInt32] = []
        frames.reserveCapacity(frameCount)
        for _ in 0..<frameCount { frames.append(i64(at)); slots.append(u32(at + 8)); at += 12 }
        var analysed: [Int64] = [], offsets: [(UInt64, UInt32)] = []
        for _ in 0..<maskCount {
            analysed.append(i64(at))
            offsets.append((u64(at + 8), u32(at + 16)))
            at += 20
        }
        self.frames = frames
        self.slots = slots
        self.analysed = analysed
        self.offsets = offsets
        base = at
    }

    func mask(_ slot: Int) throws -> [UInt8] {
        let (offset, length) = offsets[slot]
        let start = base + Int(offset)
        let blob = data.subdata(in: start..<(start + Int(length)))
        return [UInt8](try (blob as NSData).decompressed(using: .lzfse) as Data)
    }

    /// The last frame at or before `t` (1/600 s), as an index into `frames`.
    func shown(at t: Int64) -> Int? {
        var lo = 0, hi = frames.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if frames[mid] <= t { lo = mid + 1 } else { hi = mid }
        }
        return lo > 0 ? lo - 1 : nil
    }
}

/// The pack lookup the probe compositor runs per request: composition ticks
/// → the covering picture segment → the shown source frame (reversed through
/// the pivot) → its mask, decompressed.
func packLookup(plan: CompositionPlan, packs: [UInt32: (Pack, Source)],
                reversedClips: Set<UInt32>) -> (Ticks, Int32) -> (index: Int, bytes: [UInt8])? {
    var byTrack: [Int32: [PlanSegment]] = [:]
    for track in plan.videoTracks { byTrack[Int32(track.id)] = track.segments }
    // The reversed stream per media: each forward frame's reversed time
    // (sorted, with its frame) and the mirrored analysed times (sorted, with
    // their slots), `reversed_time = T − end`.
    var reversedFrames: [UInt32: [(Int64, Int64)]] = [:]
    var mirroredAnalysed: [UInt32: [(Int64, Int)]] = [:]
    for (media, (pack, source)) in packs where !reversedClips.isEmpty {
        let pivot = source.pivotUnits
        reversedFrames[media] = pack.frames.map { (pivot - source.end(of: $0), $0) }
            .sorted { $0.0 < $1.0 }
        mirroredAnalysed[media] = pack.analysed.enumerated()
            .map { (pivot - source.end(of: $0.element), $0.offset) }.sorted { $0.0 < $1.0 }
    }
    return { ticks, picture in
        guard let segment = byTrack[picture]?.first(where: {
            $0.duration > 0 && $0.start <= ticks && ticks < $0.start + $0.duration
        }), let (pack, source) = packs[segment.media] else { return nil }
        let s = segment.sourceIn + scaled(ticks - segment.start, segment.sourceDuration,
                                          segment.duration)
        let units = s / ticksPerUnit
        let slot: Int
        if reversedClips.contains(segment.clip) {
            // The reversed stream's frame shown at `units`, mapped back to the
            // forward frame, then the nearest analysed frame in the reversed
            // stream (ties to the earlier there).
            guard let reversed = reversedFrames[segment.media],
                  let mirrored = mirroredAnalysed[segment.media],
                  let shownFrame = reversed.last(where: { $0.0 <= units }) else { return nil }
            let r = shownFrame.0
            var best = mirrored[0]
            for m in mirrored {
                if abs(m.0 - r) < abs(best.0 - r) || (abs(m.0 - r) == abs(best.0 - r) && m.0 < best.0) {
                    best = m
                }
            }
            slot = best.1
        } else {
            guard let i = pack.shown(at: units) else { return nil }
            slot = Int(pack.slots[i])
        }
        guard let bytes = try? pack.mask(slot) else { return nil }
        return (Int(pack.analysed[slot] / 20), bytes)
    }
}

func runTimed(_ mode: String) throws {
    let work = mediaDir(2), media = mediaDir(3)
    if mode == "playback" || mode == "build" {
        guard let encoding = MaskEncoding(rawValue: arguments[4]), let seconds = Int(arguments[5])
        else { fail("\(mode) <work> <media> <encoding> <L> <rate>") }
        let rate = arguments[6]
        if mode == "playback" {
            let screen = try Source("screen_4k", media: media)
            let barcode = try Source("barcode", media: media)
            let set = Chunks(barcode, encoding: encoding, seconds: seconds, rate: rate, work: work)
            let (placed, ids) = try playbackProject(screen, barcode, seconds: seconds)
            let plain = try build(placed)
            defer { release(plain) }
            var without = plain.built.videoConfiguration
            without.customVideoCompositorClass = probe(for: plain.built)
            let masked = try build(placed)
            defer { release(masked) }
            let (with, pairs, files) = try addMasks(masked, chunks: [ids["barcode"]!: set],
                                                    reversedClips: [])
            var withRuns: [Double] = [], withoutRuns: [Double] = []
            for _ in 0..<3 {
                withoutRuns.append(Double(try play(plain.built.composition, without, mode: .count,
                                                   pairs: [])))
                withRuns.append(Double(try play(masked.built.composition, with, mode: .count,
                                                pairs: pairs)))
            }
            let a = median(withRuns), b = median(withoutRuns)
            answer(["ok": true, "with": withRuns, "without": withoutRuns, "with_median": a,
                    "without_median": b, "ratio": b > 0 ? a / b : 0, "chunk_files": files,
                    "class": String(describing: with.customVideoCompositorClass!)])
        } else {
            let long = try Source("long_60m", media: media)
            let set = Chunks(long, encoding: encoding, seconds: seconds, rate: rate, work: work)
            // Chunk 0 written for real; every other chunk an APFS clone of it
            // (the build opens each file and reads its track; it decodes nothing).
            let first = try set.forward(0)
            let count = Int64((long.pivotUnits + set.length - 1) / set.length)
            for k in 1..<count {
                let url = set.folder.appendingPathComponent("\(k).mov")
                if !FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.copyItem(at: first, to: url)
                }
            }
            let (placed, ids) = try longProject(long)
            // Each build in its own autorelease pool, so one build's assets
            // and tracks are gone before the next is timed.
            func timed(_ masks: Bool) throws -> Double {
                try autoreleasepool {
                    let started = CFAbsoluteTimeGetCurrent()
                    let b = try build(placed)
                    if masks {
                        _ = try addMasks(b, chunks: [ids["long_60m"]!: set], reversedClips: [])
                    }
                    let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
                    release(b)
                    return ms
                }
            }
            _ = try timed(false)
            _ = try timed(true)
            var with: [Double] = [], without: [Double] = []
            for _ in 0..<10 {
                without.append(try timed(false))
                with.append(try timed(true))
            }
            answer(["ok": true, "with_ms": with, "without_ms": without,
                    "delta_ms": median(with) - median(without), "chunks": count,
                    "clips": placed.project.snapshot.clips.count])
        }
        return
    }
    // pack <work> <media> <part>
    let part = arguments[4]
    let folder = work.appendingPathComponent("pack", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    func pack(_ source: Source, _ rate: String, tablesOnly: Bool = false) throws -> Pack {
        let url = folder.appendingPathComponent("\(source.name)-\(rate).pack")
        if !FileManager.default.fileExists(atPath: url.path) {
            try writePack(url, source: source, rate: rate, tablesOnly: tablesOnly)
        }
        return try Pack(url)
    }
    switch part {
    case "registration":
        let sources = ["barcode": try Source("barcode", media: media),
                       "hlg_vfr": try Source("hlg_vfr", media: media)]
        var rows: [[String: Any]] = []
        for rate in ["every", "15"] {
            for item in cases {
                let source = sources[item.source]!
                var row: [String: Any] = ["case": item.name, "rate": rate, "source": item.source,
                                          "reversed": item.reversed]
                do {
                    let (base, ids) = try project([source])
                    var placed = Placed(project: base)
                    let track = placed.project.snapshot.tracks.first!.id
                    try item.make(&placed, ids, track, source)
                    let b = try build(placed)
                    defer { release(b) }
                    let p = try pack(source, rate)
                    ProbeRecorder.shared.packLookup = packLookup(
                        plan: b.plan, packs: [ids[item.source]!: (p, source)],
                        reversedClips: Set(placed.reversed.keys))
                    var configuration = b.built.videoConfiguration
                    configuration.customVideoCompositorClass = probe(for: b.built)
                    let pairs = b.plan.videoTracks.map { (Int32($0.id), Int32(0)) }
                    ProbeRecorder.shared.reset(.pack, pairs: pairs)
                    row["frames"] = try readAll(b.built.composition, configuration)
                    row["expected_frames"] = Int(b.plan.duration / 20_000)
                    row["records"] = ProbeRecorder.shared.records
                    row["ok"] = true
                } catch {
                    row["ok"] = false
                    row["error"] = "\(error)"
                }
                rows.append(row)
            }
        }
        let out = work.appendingPathComponent("registration-pack.json")
        try JSONSerialization.data(withJSONObject: ["rows": rows]).write(to: out)
        answer(["ok": true, "path": out.path, "rows": rows.count])
    case "colour":
        let source = try Source("barcode", media: media)
        let p = try pack(source, "every")
        var worst = 0, compared = 0
        for (slot, a) in p.analysed.enumerated() where a >= 28 * 600 && a < 32 * 600 {
            let back = try p.mask(slot), original = barcodeMask(Int(a / 20))
            for i in 0..<back.count { worst = max(worst, abs(Int(back[i]) - Int(original[i]))) }
            compared += 1
        }
        answer(["ok": true, "colour_max": worst, "compared": compared])
    case "playback":
        let rate = arguments.count > 5 ? arguments[5] : "every"
        let screen = try Source("screen_4k", media: media)
        let barcode = try Source("barcode", media: media)
        let (placed, ids) = try playbackProject(screen, barcode, seconds: 10)
        let b = try build(placed)
        defer { release(b) }
        let p = try pack(barcode, rate)
        ProbeRecorder.shared.packLookup = packLookup(
            plan: b.plan, packs: [ids["barcode"]!: (p, barcode)], reversedClips: [])
        var configuration = b.built.videoConfiguration
        configuration.customVideoCompositorClass = probe(for: b.built)
        let pairs = b.plan.videoTracks.filter { $0.segments.contains { $0.media == ids["barcode"]! } }
            .map { (Int32($0.id), Int32(0)) }
        var with: [Double] = [], without: [Double] = []
        for _ in 0..<3 {
            without.append(Double(try play(b.built.composition, configuration, mode: .count, pairs: [])))
            with.append(Double(try play(b.built.composition, configuration, mode: .pack, pairs: pairs)))
        }
        let a = median(with), c = median(without)
        answer(["ok": true, "with": with, "without": without, "ratio": c > 0 ? a / c : 0])
    case "build":
        let long = try Source("long_60m", media: media)
        _ = try pack(long, "every", tablesOnly: true)
        let url = folder.appendingPathComponent("long_60m-every.pack")
        let (placed, _) = try longProject(long)
        func timed(_ tables: Bool) throws -> Double {
            try autoreleasepool {
                let started = CFAbsoluteTimeGetCurrent()
                let b = try build(placed)
                if tables { _ = try Pack(url) }
                let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
                release(b)
                return ms
            }
        }
        _ = try timed(false)
        _ = try timed(true)
        var with: [Double] = [], without: [Double] = []
        for _ in 0..<10 {
            without.append(try timed(false))
            with.append(try timed(true))
        }
        answer(["ok": true, "with_ms": with, "without_ms": without,
                "delta_ms": median(with) - median(without),
                "pack_bytes": (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) ?? 0])
    case "size":
        // No rule reads it: the pack's bytes over CO-S1's dumped Vision masks
        // (every distinct analysed mask once, LZFSE), scaled to a minute,
        // beside (4)'s track sizes. `pack <work> <media> size <dump>`.
        let dump = try Dump(URL(fileURLWithPath: arguments[5], isDirectory: true))
        var bytes = 20 + dump.allPts.count * 12 + dump.pts.count * 20
        for i in 0..<dump.pts.count {
            bytes += try (Data(dump.mask(i)) as NSData).compressed(using: .lzfse).length
        }
        answer(["ok": true, "bytes": bytes, "masks": dump.pts.count,
                "mask": "\(dump.width)x\(dump.height)", "seconds": dump.duration,
                "mb_per_min": Double(bytes) / 1e6 * 60 / dump.duration])
    default:
        fail("pack part \(part)")
    }
}

// MARK: - Modes

guard arguments.count >= 3 else { fail("usage: mask_track_probe <mode> …") }
let mode = arguments[1]

do {
    switch mode {
    case "fixtures":
        let media = mediaDir(2)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let only = arguments.count > 3 ? arguments[3] : nil
        var made: [String: Double] = [:]
        for (name, frames, reverse) in [("barcode", 4800, false), ("barcode_rev", 4800, true),
                                        ("long_60m", 108_000, false)] where only == nil || only == name {
            let started = CFAbsoluteTimeGetCurrent()
            try writeBarcode(media.appendingPathComponent("\(name).mov"), frames: frames) {
                reverse ? frames - 1 - $0 : $0
            }
            made[name] = CFAbsoluteTimeGetCurrent() - started
        }
        answer(["ok": true, "seconds": made])

    case "registration":
        let work = mediaDir(2), media = mediaDir(3)
        guard let encoding = MaskEncoding(rawValue: arguments[4]), let seconds = Int(arguments[5])
        else { fail("registration <work> <media> <encoding> <L>") }
        let sources = ["barcode": try Source("barcode", media: media),
                       "hlg_vfr": try Source("hlg_vfr", media: media)]
        var rows: [[String: Any]] = []
        for rate in ["every", "15"] {
            let sets = sources.mapValues { Chunks($0, encoding: encoding, seconds: seconds, rate: rate,
                                                  work: work) }
            for item in cases {
                let source = sources[item.source]!
                var row: [String: Any] = ["case": item.name, "rate": rate, "source": item.source,
                                          "reversed": item.reversed]
                do {
                    let (base, ids) = try project([source])
                    var placed = Placed(project: base)
                    guard let track = placed.project.snapshot.tracks.first?.id else {
                        throw SpikeError("no track")
                    }
                    try item.make(&placed, ids, track, source)
                    let b = try build(placed)
                    defer { release(b) }
                    let chunks = [ids[item.source]!: sets[item.source]!]
                    let (configuration, pairs, files) = try addMasks(
                        b, chunks: chunks, reversedClips: Set(placed.reversed.keys))
                    ProbeRecorder.shared.reset(.registration, pairs: pairs)
                    let frames = try readAll(b.built.composition, configuration)
                    row["frames"] = frames
                    row["expected_frames"] = Int(b.plan.duration / 20_000)
                    row["records"] = ProbeRecorder.shared.records
                    row["requests"] = ProbeRecorder.shared.requests
                    row["pairs"] = pairs.map { [Int($0.0), Int($0.1)] }
                    row["chunk_files"] = files
                    row["class"] = String(describing: configuration.customVideoCompositorClass!)
                    row["ok"] = true
                } catch {
                    row["ok"] = false
                    row["error"] = "\(error)"
                }
                rows.append(row)
                let note = "registration \(encoding.rawValue)/\(seconds) \(rate) \(item.name): "
                    + "\(row["ok"] as? Bool ?? false) \(row["error"] as? String ?? "")\n"
                FileHandle.standardError.write(Data(note.utf8))
            }
        }
        let out = work.appendingPathComponent("registration-\(encoding.rawValue)-\(seconds).json")
        try JSONSerialization.data(withJSONObject: ["rows": rows]).write(to: out)
        answer(["ok": true, "path": out.path, "rows": rows.count])

    case "colour":
        let work = mediaDir(2), media = mediaDir(3)
        guard let encoding = MaskEncoding(rawValue: arguments[4]) else { fail("colour <encoding>") }
        let source = try Source("barcode", media: media)
        let set = Chunks(source, encoding: encoding, seconds: 10, rate: "every", work: work)
        // Each chunk's own decode, by the index its bottom half carries.
        var decoded: [Int: [UInt8]] = [:]
        for k in [Int64(2), 3] {
            for sample in try decodeY(try set.forward(k), encoding: encoding) {
                let index = BarCode.read(width: sample.w, height: sample.h, bandY: maskBandY) {
                    Float(sample.y[$1 * sample.w + $0]) / 255
                }
                decoded[index] = sample.y
            }
        }
        var out: [String: Any] = ["ok": true, "encoding": encoding.rawValue]
        let classes: [(String, Bool, (any AVVideoCompositing.Type)?)] = [
            ("plain_sdr", false, ProbeCompositor.self),
            ("converting_sdr", false, ProbeConvertingCompositor.self),
            ("converting_hlg", true, nil)]
        for (label, hlg, forced) in classes {
            let (base, ids) = try project([source], hlg: hlg)
            var placed = Placed(project: base)
            let track = placed.project.snapshot.tracks.first!.id
            try cases[0].make(&placed, ids, track, source)
            let b = try build(placed)
            defer { release(b) }
            let (configuration, pairs, _) = try addMasks(
                b, chunks: [ids["barcode"]!: set], reversedClips: [], probeClass: forced)
            ProbeRecorder.shared.reset(.colour, pairs: pairs)
            _ = try readAll(b.built.composition, configuration)
            var worst: Float = 0, compared = 0, missing = 0
            for (index, values) in ProbeRecorder.shared.colour {
                guard let y = decoded[index], y.count == values.count else { missing += 1; continue }
                for i in 0..<y.count { worst = max(worst, abs(values[i] - Float(y[i]))) }
                compared += 1
            }
            out[label] = compared > 0 ? Double(worst) : NSNull()
            out["\(label)_compared"] = compared
            out["\(label)_missing"] = missing
            out["\(label)_class"] = String(describing: configuration.customVideoCompositorClass!)
        }
        answer(out)

    case "codec":
        let work = mediaDir(2)
        let dump = try Dump(mediaDir(3))
        guard arguments.count == 7, let encoding = MaskEncoding(rawValue: arguments[5]),
              let seconds = Int(arguments[6])
        else { fail("codec <work> <dump> <movie> <encoding> <L>") }
        // The movie's frames as the dump decoded them (its `all_pts`, in the
        // dump's timescale): compressed sample times miss an edit list.
        var row = try codecRow(
            dump: dump, sourceFrames: dump.allPts, encoding: encoding, chunkSeconds: seconds,
            folder: work.appendingPathComponent("codec/\(encoding.rawValue)/\(seconds)"))
        row["ok"] = true
        row["settings"] = MaskEncoding.pinned[encoding.rawValue]
        answer(row)

    case "fixed":
        let work = mediaDir(2)
        guard let encoding = MaskEncoding(rawValue: arguments[3]) else { fail("fixed <encoding>") }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        _ = try fixedCost(encoding, folder: work)  // a warm-up, not counted
        var runs: [Double] = []
        for _ in 0..<10 { runs.append(try fixedCost(encoding, folder: work)) }
        answer(["ok": true, "runs": runs, "fixed_s": runs.sorted()[runs.count / 2],
                "settings": MaskEncoding.pinned[encoding.rawValue] ?? ""])

    case "playback", "build", "pack":
        try runTimed(mode)

    default:
        fail("unknown mode \(mode)")
    }
} catch {
    fail("\(error)")
}
exit(0)
