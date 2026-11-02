import Foundation

/// Where an on-device word's sound begins (road map "creator-jobs" TX1b, spec
/// §11 TX-15…TX-18). This Mac's recogniser puts a word's start early, by 110
/// to 1,186 ms (TX-S3), so the word after a pause starts inside the silence.
/// Every reader of a stored run (`TimelineTranscript.deviceWords`,
/// `get_transcript`) moves each start, when it reads, to where the voice
/// cache's speech begins, refined on the 10 ms peaks cache. The stored run is
/// never changed (TX-16). Pure but for `caches`, which reads two files.
///
/// **The rule (TX-15)**, per stored run, in media source ticks, its words in
/// source order. A word has start `s`, end `e = max(s, end)` and `limit =
/// min(e, the next word's stored start)` (`e` for the last word); a voice cell
/// k is `[k·chunk, (k+1)·chunk)` and is speech at `p ≥ defaultVoiceConfidence`.
/// - (a) `b` is the first speech cell after `s`'s cell, `b < count` and
///   `b·chunk < limit`, whose preceding non-speech run `[a, b)` holds `s`'s
///   cell or is at least `TranscriptCut.minimumRunCells` long; none, unmoved.
/// - (b) `T = max(level, floorRatio × median)`, the median the element at
///   `(n − 1)/2` of the sorted peaks of the buckets whose start lies in
///   `[a·chunk, b·chunk)` (0 with none): the run's own noise floor.
/// - (c) the onset is the start of the first bucket with `peak ≥ T`, from the
///   bucket holding `max(s, a·chunk, (b − leadCells)·chunk)` up to, not
///   including, the first bucket starting at or after `(b + 1)·chunk`, then at
///   least `s`; with no such bucket or no peaks, `b·chunk`.
/// - (d) an onset at or past `limit` is `b·chunk`.
enum WordOnsets {
    /// −40 dBFS, linear: the quietest bucket an onset can be.
    static let level: Float = 0.01
    /// +12 dB over the median bucket of the word's non-speech run `[a, b)`,
    /// the noise floor before the onset — never a speech level.
    static let floorRatio: Float = 4
    /// How far before the first speech cell the refinement looks: 3 cells,
    /// 96 ms, so a click earlier in the silence is not an onset.
    static let leadCells = 3

    /// One moved start per word of `words`, in order; nil when `speech` is
    /// nil (no voice cache: TX-18).
    static func moved(
        _ words: [DeviceTranscriptCache.Word], speech: [Float]?, peaks: [Float]?
    ) -> [Ticks]? {
        guard let speech else { return nil }
        var out: [Ticks] = []
        out.reserveCapacity(words.count)
        for (index, word) in words.enumerated() {
            let end = max(word.start, word.end)
            let limit = index + 1 < words.count ? min(end, words[index + 1].start) : end
            out.append(onset(word.start, limit: limit, speech: speech, peaks: peaks))
        }
        return out
    }

    /// A media's voice cache and peaks cache, as the open's cache pass left
    /// them. Off main: two small files.
    static func caches(media: UInt32, in cacheDir: URL) -> (speech: [Float]?, peaks: [Float]?) {
        (MediaImporter.loadSpeech(for: media, in: cacheDir),
         MediaImporter.loadPeaks(for: media, in: cacheDir))
    }

    /// TX-15 for one word starting at `s`.
    static func onset(_ s: Ticks, limit: Ticks, speech: [Float], peaks: [Float]?) -> Ticks {
        guard s >= 0, let (a, b) = firstSpeech(after: s, limit: limit, speech: speech) else {
            return s
        }
        let chunk = MediaSpeech.chunkTicks
        let fallback = Ticks(b) * chunk
        guard let peaks else { return fallback }
        let bucket = MediaPeaks.bucketTicks
        let threshold = max(level, floorRatio * median(peaks, from: Ticks(a) * chunk, to: fallback))
        let from = max(s, Ticks(a) * chunk, Ticks(b - leadCells) * chunk)
        let first = Int(from / bucket)
        let past = min(Int((Ticks(b + 1) * chunk + bucket - 1) / bucket), peaks.count)
        guard first < past, let hit = (first..<past).first(where: { peaks[$0] >= threshold }) else {
            return fallback
        }
        let onset = max(Ticks(hit) * bucket, s)
        return onset >= limit ? fallback : onset
    }

    /// (a): the first speech cell `b` and the start `a` of its non-speech run.
    private static func firstSpeech(
        after s: Ticks, limit: Ticks, speech: [Float]
    ) -> (a: Int, b: Int)? {
        let chunk = MediaSpeech.chunkTicks
        let confidence = Float(SilenceDetector.Settings.defaultVoiceConfidence)
        let own = Int(s / chunk)
        var runStart: Int?
        if own < speech.count, speech[own] < confidence {
            var k = own
            while k > 0, speech[k - 1] < confidence { k -= 1 }
            runStart = k
        }
        var b = own + 1
        while b < speech.count, Ticks(b) * chunk < limit {
            if speech[b] >= confidence {
                if let a = runStart, a <= own || b - a >= TranscriptCut.minimumRunCells {
                    return (a, b)
                }
                runStart = nil
            } else if runStart == nil {
                runStart = b
            }
            b += 1
        }
        return nil
    }

    /// (b): the median peak of the buckets whose start lies in `[from, to)`.
    private static func median(_ peaks: [Float], from: Ticks, to: Ticks) -> Float {
        let bucket = MediaPeaks.bucketTicks
        let first = Int((from + bucket - 1) / bucket)
        let past = min(Int((to + bucket - 1) / bucket), peaks.count)
        guard first < past else { return 0 }
        let sorted = peaks[first..<past].sorted()
        return sorted[(sorted.count - 1) / 2]
    }
}
