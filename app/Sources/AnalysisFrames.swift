import AVFoundation

/// The analysis frame reader (spec §11 CJ-23; road map "creator-jobs" CJ2a):
/// a media's grid on source time, and its pictures, upright, at a kind's
/// long side, in presentation order.
///
/// **Two readers.** The direct reader is an `AVAssetReaderTrackOutput` over
/// the first video track, 32BGRA scaled to the long side and turned upright
/// from the track's `preferredTransform`. The converted reader is an
/// `AVAssetReaderVideoCompositionOutput` over `MediaImporter.oneClip`'s
/// one-clip composition, its `renderSize` the kind's size as Preview Quality
/// sets one, read in the compositor's one format (64RGBAHalf) and rounded to
/// 8-bit BGRA here, so analysis sees what the person sees through step 0. A
/// media is read converted whenever `ThumbnailInput(media:urls:)` or
/// `ThumbnailInput(track:)` exists (CJ-S3 (c)); the request carries which.
///
/// **The pre-roll is decoded frames, not indices.** A range's read starts two
/// frame durations before its first index and, while fewer than two kept
/// frames precede that index, restarts from twice as far back, until two do
/// or the media's start is reached — so a value that depends on the two
/// frames before a grid point is the same wherever a job began, a variable
/// frame rate's gap included (P7).
///
/// Await-free (spec §11 W-8): every read blocks the analysis lane's thread,
/// where blocking is the point, as `ReverseRenderer`'s do.

/// A media's analysis grid: index k is round(pts × fps), the first frame on
/// an index winning, over 0…`lastIndex`.
struct AnalysisGrid: Equatable {
    let num: Double
    let den: Double
    let duration: Ticks

    init(media: MediaSnapshot) {
        let valid = media.fps.num > 0 && media.fps.den > 0
        num = Double(valid ? media.fps.num : 30)
        den = Double(valid ? media.fps.den : 1)
        duration = max(0, media.duration)
    }

    /// A sample grid of `samplesPerSecond` (spec §11 CJ-33: `faces`).
    init(samplesPerSecond: Double, duration: Ticks) {
        num = samplesPerSecond
        den = 1
        self.duration = max(0, duration)
    }

    /// The hop grid of `hopTicks` (spec §11 FC-31: `sound_events`), index k
    /// at k × `hopTicks`.
    init(hopTicks: Ticks, duration: Ticks) {
        num = 600_000
        den = Double(max(1, hopTicks))
        self.duration = max(0, duration)
    }

    /// Grid indices per tick.
    var rate: Double { num / (600_000 * den) }

    /// How many indices the media spans, at least one.
    var count: Int { max(1, Int((Double(duration) * rate - 1e-6).rounded(.up))) }

    var lastIndex: Int { count - 1 }

    /// One frame's length in ticks.
    var frameTicks: Double { 1 / rate }

    /// The index a frame at `ticks` lands on, clamped to the grid.
    func index(of ticks: Int64) -> Int {
        min(lastIndex, max(0, Int((Double(ticks) * rate).rounded())))
    }

    /// The tick of index `k`.
    func ticks(of k: Int) -> Ticks {
        Ticks((Double(k) / rate).rounded())
    }

    /// The indices whose ticks lie in [from, to); nil when none does.
    func indices(from: Ticks, to: Ticks) -> ClosedRange<Int>? {
        let low = max(0, Int((Double(from) * rate - 1e-9).rounded(.up)))
        let high = min(lastIndex, Int((Double(to) * rate - 1e-9).rounded(.up)) - 1)
        return low <= high ? low...high : nil
    }

    /// `window` and `margin` indices each side, clamped to the grid.
    func need(_ window: ClosedRange<Int>, margin: Int) -> ClosedRange<Int> {
        max(0, window.lowerBound - margin)...min(lastIndex, window.upperBound + margin)
    }
}

/// One upright picture, 8-bit BGRA, valid only inside the reader's callback.
struct AnalysisPicture {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let bytes: UnsafePointer<UInt8>
}

enum AnalysisFrames {

    enum ReadError: LocalizedError {
        case noPicture
        case unconvertible
        case reader(String)

        var errorDescription: String? {
            switch self {
            case .noPicture: return "the file has no video track"
            case .unconvertible: return "its picture could not be converted through step 0"
            case .reader(let why): return "the file could not be read: \(why)"
            }
        }
    }

    /// What a job reads: the media, its file, the converted reader's input
    /// (nil: the direct reader) and, for an input, which converted reader
    /// (`.inputPass`: CO-7's third arm, `AnalysisFrames+InputPass.swift`).
    struct Source {
        let media: MediaSnapshot
        let url: URL
        let input: ThumbnailInput?
        var arm: Arm = .standard
    }

    enum Arm { case standard, inputPass }

    /// The display size at `longSide`, each side at least 2.
    static func size(of media: MediaSnapshot, longSide: Int) -> (width: Int, height: Int) {
        let w = Double(max(1, media.width))
        let h = Double(max(1, media.height))
        let scale = Double(longSide) / max(w, h)
        return (max(2, Int((w * scale).rounded())), max(2, Int((h * scale).rounded())))
    }

    /// Reads every kept frame of `range` (index, pts in ticks, picture),
    /// preceded by the pre-roll's frames (indices below the range), in
    /// presentation order. False when `cancelled()` stopped it. The picture
    /// is made only when the callback asks for it (#437).
    static func read(
        range: ClosedRange<Int>, grid: AnalysisGrid, source: Source, longSide: Int,
        cancelled: () -> Bool, frame: (Int, Int64, LazyAnalysisPicture) throws -> Void
    ) throws -> Bool {
        let first = range.lowerBound
        let firstTick = grid.ticks(of: first)
        var back = 2.0
        var start: Ticks = 0
        while first > 0 {
            start = max(0, firstTick - Ticks((back * grid.frameTicks).rounded()))
            guard start > 0 else { break }
            var kept = Set<Int>()
            let counted = try decode(
                source, longSide: longSide, from: start, to: firstTick, cancelled: cancelled
            ) { pts, _ in
                let k = grid.index(of: pts)
                if k < first { kept.insert(k) }
                return true
            }
            guard counted else { return false }
            guard kept.count < 2 else { break }
            back *= 2
        }
        var lastKept: Int?
        return try decode(
            source, longSide: longSide, from: start, to: grid.ticks(of: range.upperBound + 1),
            cancelled: cancelled
        ) { pts, picture in
            let k = grid.index(of: pts)
            if k > range.upperBound { return false }
            if let lastKept, k <= lastKept { return true }  // the first frame on an index wins
            lastKept = k
            try frame(k, pts, picture)
            return true
        }
    }

    // MARK: - The two readers

    /// Every picture from `from` to `to` (ticks) to `each`, which answers
    /// whether to go on. False when `cancelled()` stopped it.
    private static func decode(
        _ source: Source, longSide: Int, from: Ticks, to: Ticks, cancelled: () -> Bool,
        each: (Int64, LazyAnalysisPicture) throws -> Bool
    ) throws -> Bool {
        let range = CMTimeRange(
            start: CMTime(value: from, timescale: 600_000),
            end: CMTime(value: max(from + 1, to), timescale: 600_000))
        if let input = source.input, source.arm == .inputPass {
            return try decodeThroughInputPass(
                source, input: input, longSide: longSide, range: range, cancelled: cancelled,
                each: each)
        }
        if let input = source.input {
            return try decodeConverted(
                source, input: input, longSide: longSide, range: range, cancelled: cancelled,
                each: each)
        }
        return try decodeDirect(
            source, longSide: longSide, range: range, cancelled: cancelled, each: each)
    }

    private static func decodeDirect(
        _ source: Source, longSide: Int, range: CMTimeRange, cancelled: () -> Bool,
        each: (Int64, LazyAnalysisPicture) throws -> Bool
    ) throws -> Bool {
        let asset = AVURLAsset(
            url: source.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .video) else {
            throw ReadError.noPicture
        }
        let transform = preferredTransform(of: track)
        let turned = CompositionBuilder.orientationCode(transform) & 1 == 1
        let display = size(of: source.media, longSide: longSide)
        let natural = turned ? (display.height, display.width) : (display.width, display.height)
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch {
            throw ReadError.reader(error.localizedDescription)
        }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: natural.0,
                kCVPixelBufferHeightKey as String: natural.1,
            ])
        output.alwaysCopiesSampleData = false
        reader.timeRange = range
        reader.add(output)
        var upright = Upright(transform: transform)
        return try pump(reader, output, cancelled: cancelled) { pts, buffer in
            try each(
                pts,
                LazyAnalysisPicture { body in
                    _ = try upright.picture(of: buffer) {
                        try body($0)
                        return true
                    }
                })
        }
    }

    private static func decodeConverted(
        _ source: Source, input: ThumbnailInput, longSide: Int, range: CMTimeRange,
        cancelled: () -> Bool, each: (Int64, LazyAnalysisPicture) throws -> Bool
    ) throws -> Bool {
        let key = RecipeSource.shared.register()
        defer { RecipeSource.shared.unregister(key) }
        guard
            let built = MediaImporter.oneClip(
                source.media, url: source.url, input: input, key: key)
        else { throw ReadError.unconvertible }
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: built.composition) } catch {
            throw ReadError.reader(error.localizedDescription)
        }
        let display = size(of: source.media, longSide: longSide)
        var configuration = built.videoConfiguration
        configuration.renderSize = CGSize(width: display.width, height: display.height)
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: built.composition.tracks(withMediaType: .video),
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(Compositor.outputPixelFormat),
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ])
        output.videoComposition = AVVideoComposition(configuration: configuration)
        output.alwaysCopiesSampleData = false
        // Held inside the composition: a range past its end is an invalid
        // composition to the reader (-11841).
        reader.timeRange = CMTimeRangeGetIntersection(
            range, otherRange: CMTimeRange(start: .zero, duration: built.composition.duration))
        reader.add(output)
        var scratch: [UInt8] = []
        return try pump(reader, output, cancelled: cancelled) { pts, buffer in
            try each(
                pts,
                LazyAnalysisPicture { body in
                    _ = try halfToBGRA(buffer, into: &scratch) {
                        try body($0)
                        return true
                    }
                })
        }
    }

    /// The sample loop both readers share: `cancelReading` on this thread,
    /// after `copyNextSampleBuffer` returned (G-17).
    static func pump(
        _ reader: AVAssetReader, _ output: AVAssetReaderOutput, cancelled: () -> Bool,
        each: (Int64, CVPixelBuffer) throws -> Bool
    ) throws -> Bool {
        guard reader.startReading() else {
            throw ReadError.reader(reader.error?.localizedDescription ?? "it would not start")
        }
        var finished = true
        do {
            while let sample = output.copyNextSampleBuffer() {
                if cancelled() {
                    finished = false
                    break
                }
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                let pts = CMTimeConvertScale(
                    CMSampleBufferGetPresentationTimeStamp(sample), timescale: 600_000,
                    method: .roundHalfAwayFromZero
                ).value
                guard try each(pts, buffer) else { break }
            }
        } catch {
            reader.cancelReading()
            throw error
        }
        if reader.status == .reading { reader.cancelReading() }
        if reader.status == .failed {
            throw ReadError.reader(reader.error?.localizedDescription ?? "it failed")
        }
        return finished
    }

    /// The track's `preferredTransform`, read by key (the property is
    /// deprecated for its async load; `CompositionBuilder.keyed`'s posture).
    static func preferredTransform(of track: AVAssetTrack) -> CGAffineTransform {
        guard let value = CompositionBuilder.keyed(track, "preferredTransform") as? NSValue else {
            return .identity
        }
        var transform = CGAffineTransform.identity
        value.getValue(&transform, size: MemoryLayout<CGAffineTransform>.size)
        return transform
    }
}
