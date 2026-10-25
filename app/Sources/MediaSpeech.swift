import Foundation

/// The cached Silero VAD probabilities — `cache/speech/<id>.bin` — and how to
/// ask them about a window, `MediaPeaks`' shape for the voice cache.
///
/// One 32-bit float per 512-sample chunk at 16 kHz (`SileroVAD.chunkSamples`
/// / `SileroVAD.sampleRate`), which is `chunkTicks` ticks of SOURCE time —
/// exactly 19,200, and written as the division rather than as the number for
/// the same reason `MediaPeaks.bucketTicks` is. `MediaPeaks.window` already
/// generalises the project-time → bucket-index arithmetic over the bucket
/// size, and `MediaPeaks.peak` takes the max over it on any grid, so this
/// file adds only the chunk grid, its loader and the question
/// `SilenceDetector`'s voice test asks.
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
    /// segments cite it — a `MediaCacheLoader` over `loadSpeech` instead of
    /// `loadPeaks`.
    static func loader(cacheDirectory: URL?) -> MediaCacheLoader<[Float]> {
        MediaCacheLoader(cacheDirectory: cacheDirectory) {
            MediaImporter.loadSpeech(for: $0, in: $1)
        }
    }

    /// The loudest — here, most confident — probability the project span
    /// `[from, to)` of `segment` covers, or 0 when it falls outside the
    /// window the cache was built from: `MediaPeaks.peak` asked on the chunk
    /// grid.
    static func speechMax(
        _ p: [Float], over segment: PlanSegment, from: Ticks, to: Ticks, reversedPivot: Ticks?
    ) -> Float {
        MediaPeaks.peak(
            p, over: segment, from: from, to: to, reversedPivot: reversedPivot,
            bucketTicks: chunkTicks)
    }
}
