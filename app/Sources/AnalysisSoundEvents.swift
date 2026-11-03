import AVFoundation
import Foundation
import SoundAnalysis

/// The `sound_events` kind's job (spec §11 FC-30…FC-34; road map
/// "creator-jobs" FC3): Sound Analysis' `.version1` classifier over each
/// missing range of a media's first audio track, kept per window as
/// `windows.bin` (`SoundEvents`). Nothing visible; `get_media_analysis
/// {kind: "sound_events"}` answers the windows.
///
/// **The read.** Each range k0…k1 is decoded through
/// `MediaImporter.speechReader` — 16 kHz mono float, read past an MP3's
/// encoder delay (`MP3Gapless.leadingTrim`), `window` `readWindow(k0…k1)`:
/// the range's span plus one window and one hop — into one
/// `SNAudioStreamAnalyzer` running the job's one `SNClassifySoundRequest` at
/// FC-30's window and overlap, positions counted from the range's first
/// sample. A result whose start is s samples is window k0 + round(s / hop);
/// one past k1 is dropped. Each group's value is the maximum confidence over
/// its labels. Synchronous SoundAnalysis only (spec §11 W-8).
///
/// **Publication**, through `AnalysisStore.publishFile`: every
/// `publishInterval` and at the range's end, mid-range only through the
/// contiguous answered prefix. At the end, once the reader `.completed` at
/// the media's end (its window reaches the media's duration, or the track
/// ran out first), every window of the range with no result that overhangs
/// the decoded sound (k·hop + window past the last decoded sample) is stored
/// NaN and covered; any other unanswered window stays uncovered. A reader
/// that does not complete fails the job, and the range's end publishes
/// nothing (FC-31).
enum AnalysisSoundEvents {
    static let publishInterval: TimeInterval = 30

    enum SoundError: LocalizedError {
        case noSound
        case reader(String)
        case request(String)

        var errorDescription: String? {
            switch self {
            case .noSound: return "the file has no audio track"
            case .reader(let why): return "the file's sound could not be read: \(why)"
            case .request(let why): return "Sound Analysis refused the request: \(why)"
            }
        }
    }

    /// What a range's decode reads, in the forward media's ticks from the
    /// recording's first sample: k0 × hop for (k1 − k0) × hop + window + hop.
    static func readWindow(_ indices: ClosedRange<Int>) -> CMTimeRange {
        let hop = Int64(SoundEvents.hopTicks)
        let start = Int64(indices.lowerBound) * hop
        let length = Int64(indices.upperBound - indices.lowerBound) * hop
            + Int64(SoundEvents.windowTicks) + hop
        return CMTimeRange(
            start: CMTime(value: start, timescale: 600_000),
            duration: CMTime(value: length, timescale: 600_000))
    }

    /// The windows a range covers at its end (FC-31): the contiguous
    /// answered prefix from `from`, then — only when `decodedEnd` is given
    /// (the reader completed at the media's end; ticks past the last decoded
    /// sample) — every window of `range` with no result whose end
    /// k·hop + window lies past `decodedEnd`, as NaN. Pure.
    static func coverage(
        range: ClosedRange<Int>, from: Int, answered: Set<Int>, decodedEnd: Ticks?,
        grid: AnalysisGrid
    ) -> (covered: [ClosedRange<Int>], tail: [Int]) {
        var end = from - 1
        while end < range.upperBound, answered.contains(end + 1) { end += 1 }
        var covered: [ClosedRange<Int>] = end >= from ? [from...end] : []
        var tail: [Int] = []
        if let decodedEnd, from <= range.upperBound {
            for k in stride(from: max(from, end + 1), through: range.upperBound, by: 1)
            where !answered.contains(k) {
                if grid.ticks(of: k) + SoundEvents.windowTicks > decodedEnd { tail.append(k) }
            }
            covered += tail.map { $0...$0 }
        }
        return (AnalysisStore.merged(covered), tail)
    }

    /// Collects one analyzer's results under a lock: per window index, each
    /// group's maximum over its labels.
    private final class Collector: NSObject, SNResultsObserving {
        let k0: Int
        let k1: Int
        private let lock = NSLock()
        private var windows: [Int: SoundEvents.Window] = [:]
        private var failure: String?

        init(range: ClosedRange<Int>) {
            k0 = range.lowerBound
            k1 = range.upperBound
        }

        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let result = result as? SNClassificationResult else { return }
            let start = result.timeRange.start.seconds * Double(SoundEvents.sampleRate)
            let k = k0 + Int((start / Double(SoundEvents.hopSamples)).rounded())
            guard k <= k1 else { return }
            let values = SoundEvents.Group.allCases.map { group -> Float in
                let found = (SoundEvents.labels[group] ?? []).compactMap {
                    result.classification(forIdentifier: $0)?.confidence
                }
                return found.max().map { Float($0) } ?? .nan
            }
            lock.lock()
            windows[k] = SoundEvents.Window(values: values)
            lock.unlock()
        }

        func request(_ request: SNRequest, didFailWithError error: Error) {
            lock.lock()
            failure = error.localizedDescription
            lock.unlock()
        }

        var snapshot: (windows: [Int: SoundEvents.Window], failure: String?) {
            lock.lock()
            defer { lock.unlock() }
            return (windows, failure)
        }
    }

    // MARK: - The job

    /// Runs `request`'s ranges (window indices) in order. False when
    /// `cancelled()` stopped it; `progress` hears the share of samples read.
    static func run(
        _ request: AnalysisRequest, cancelled: () -> Bool, progress: (Double) -> Void,
        publishInterval: TimeInterval = publishInterval
    ) throws -> Bool {
        let grid = request.kind.grid(of: request.media)
        var assets: [UInt32: AVURLAsset] = [:]
        guard
            let track = CompositionBuilder.assetTrack(
                at: request.url, key: request.media.id, mediaType: .audio, assets: &assets),
            let asset = assets[request.media.id]
        else { throw SoundError.noSound }
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Double(SoundEvents.sampleRate),
                channels: 1, interleaved: false)
        else { throw SoundError.reader("no 16 kHz mono format") }
        let classify: SNClassifySoundRequest
        do {
            classify = try SNClassifySoundRequest(classifierIdentifier: .version1)
        } catch {
            throw SoundError.request(error.localizedDescription)
        }
        classify.windowDuration = CMTime(value: SoundEvents.windowTicks, timescale: 600_000)
        classify.overlapFactor = SoundEvents.overlap
        let ticksPerSample = 600_000 / Double(SoundEvents.sampleRate)
        let total = max(1, request.ranges.reduce(0.0) {
            $0 + readWindow($1).duration.seconds * Double(SoundEvents.sampleRate)
        })
        var before = 0.0
        for range in request.ranges {
            let window = readWindow(range)
            guard
                let (reader, output) = MediaImporter.speechReader(
                    asset: asset, track: track, window: window),
                reader.canAdd(output)
            else { throw SoundError.reader("the reader could not be made") }
            reader.add(output)
            guard reader.startReading() else {
                throw SoundError.reader(reader.error?.localizedDescription ?? "it did not start")
            }
            let analyzer = SNAudioStreamAnalyzer(format: format)
            let collector = Collector(range: range)
            do {
                try analyzer.add(classify, withObserver: collector)
            } catch {
                reader.cancelReading()
                throw SoundError.request(error.localizedDescription)
            }
            var job = Job(range: range)
            var position: AVAudioFramePosition = 0
            var lastPublish = Date()
            while let sample = output.copyNextSampleBuffer() {
                if cancelled() {
                    reader.cancelReading()
                    analyzer.removeAllRequests()
                    return false
                }
                guard let floats = MediaImporter.monoFloats(of: sample), !floats.isEmpty,
                    let buffer = AVAudioPCMBuffer(
                        pcmFormat: format, frameCapacity: AVAudioFrameCount(floats.count))
                else { continue }
                buffer.frameLength = AVAudioFrameCount(floats.count)
                floats.withUnsafeBufferPointer { source in
                    buffer.floatChannelData![0].update(from: source.baseAddress!, count: floats.count)
                }
                analyzer.analyze(buffer, atAudioFramePosition: position)
                position += AVAudioFramePosition(floats.count)
                progress(min(1, (before + Double(position)) / total))
                if Date().timeIntervalSince(lastPublish) >= publishInterval {
                    let found = collector.snapshot.windows
                    let (covered, _) = coverage(
                        range: range, from: job.from, answered: Set(found.keys), decodedEnd: nil,
                        grid: grid)
                    if let through = covered.first?.upperBound {
                        try publish(request, &job, through: through, tail: [], found: found,
                                    grid: grid)
                    }
                    lastPublish = Date()
                }
            }
            let status = reader.status
            let why = reader.error?.localizedDescription
            reader.cancelReading()
            guard status == .completed else {
                analyzer.removeAllRequests()
                if cancelled() { return false }
                throw SoundError.reader(why ?? "the decode stopped (status \(status.rawValue))")
            }
            analyzer.completeAnalysis()
            let (found, failure) = collector.snapshot
            if let failure { throw SoundError.request(failure) }
            let decoded = Ticks((Double(position) * ticksPerSample).rounded())
            let reachesEnd = window.start.value + window.duration.value >= request.media.duration
            let ranOut = decoded < Ticks(window.duration.value)
            let decodedEnd: Ticks? =
                reachesEnd || ranOut ? Ticks(window.start.value) + decoded : nil
            let (covered, tail) = coverage(
                range: range, from: job.from, answered: Set(found.keys), decodedEnd: decodedEnd,
                grid: grid)
            if let through = covered.last?.upperBound {
                try publish(request, &job, through: through, tail: tail, found: found, grid: grid,
                            covered: covered)
            }
            before += window.duration.seconds * Double(SoundEvents.sampleRate)
        }
        return true
    }

    /// One range's job state: the first window not yet published.
    private struct Job {
        var from: Int

        init(range: ClosedRange<Int>) { from = range.lowerBound }
    }

    /// Publishes `job.from…through` (`covered` when given, else that one
    /// range): each covered window's result, a tail window as NaN.
    private static func publish(
        _ request: AnalysisRequest, _ job: inout Job, through: Int, tail: [Int],
        found: [Int: SoundEvents.Window], grid: AnalysisGrid, covered: [ClosedRange<Int>]? = nil
    ) throws {
        let ranges = covered ?? [job.from...through]
        var results: [Int: SoundEvents.Window] = [:]
        for range in ranges { for k in range { results[k] = found[k] ?? .empty } }
        for k in tail { results[k] = .empty }
        try AnalysisStore.publishFile(
            kind: .soundEvents, cacheDir: request.cacheDir, mediaID: request.media.id,
            stamp: request.stamp, covered: ranges, files: [SoundEvents.payloadName]
        ) { onDisk, partial in
            try SoundEvents.write(
                onDisk: onDisk, partial: partial, count: grid.count, results: results)
        }
        job.from = through + 1
    }
}
