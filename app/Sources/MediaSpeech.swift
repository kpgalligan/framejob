import Foundation

/// The cached Silero VAD probabilities — `cache/speech/<id>.bin` — and how to
/// ask them about a window, `MediaPeaks`' shape for the voice cache.
///
/// One 32-bit float per 512-sample chunk at 16 kHz (`SileroVAD.chunkSamples`
/// / `SileroVAD.sampleRate`), which is `chunkTicks` ticks of SOURCE time —
/// exactly 19,200, and written as the division rather than as the number for
/// the same reason `MediaPeaks.bucketTicks` is. `MediaPeaks.window` already
/// generalises the project-time → bucket-index arithmetic over the bucket
/// size, so this file adds only the chunk grid and the max-over-window
/// question `SilenceDetector`'s voice test asks.
enum MediaSpeech {

    /// One probability's worth of source time, in ticks. Written as the
    /// division: `SileroVAD.sampleRate` and `SileroVAD.chunkSamples` each
    /// have exactly one home.
    static var chunkTicks: Ticks {
        ReelTime.perSecond * Ticks(SileroVAD.chunkSamples) / Ticks(SileroVAD.sampleRate)
    }

    /// How many probabilities a file of `duration` produces — `writeSpeech`'s
    /// output length, so a caller can size the zero-filled buffer before any
    /// chunk lands.
    static func chunkCount(duration: Ticks) -> Int {
        max(1, Int((Double(duration) / Double(chunkTicks)).rounded(.up)))
    }

    /// One media's cached probabilities read at most once, however many
    /// segments cite it — `MediaPeaks.Loader`'s shape over `loadSpeech`
    /// instead of `loadPeaks`.
    final class Loader {
        private let cacheDirectory: URL?
        private var loaded: [UInt32: [Float]] = [:]
        private(set) var pending: Set<UInt32> = []

        init(cacheDirectory: URL?) {
            self.cacheDirectory = cacheDirectory
        }

        func probabilities(for media: UInt32) -> [Float]? {
            if let cached = loaded[media] { return cached }
            if pending.contains(media) { return nil }
            guard let cacheDirectory = cacheDirectory,
                let read = MediaImporter.loadSpeech(for: media, in: cacheDirectory)
            else {
                pending.insert(media)
                return nil
            }
            loaded[media] = read
            return read
        }
    }

    /// The loudest — here, most confident — probability the project span
    /// `[from, to)` of `segment` covers, or 0 when it falls outside the
    /// window the cache was built from. `MediaPeaks.window` generalised over
    /// the bucket size is the whole of the arithmetic; this only picks the
    /// grid and takes the max.
    static func speechMax(
        _ p: [Float], over segment: PlanSegment, from: Ticks, to: Ticks, reversedPivot: Ticks?
    ) -> Float {
        guard
            let range = MediaPeaks.window(
                of: segment, from: from, to: to, reversedPivot: reversedPivot,
                bucketTicks: chunkTicks, count: p.count)
        else { return 0 }
        var loudest: Float = 0
        for index in range { loudest = max(loudest, p[index]) }
        return loudest
    }
}
