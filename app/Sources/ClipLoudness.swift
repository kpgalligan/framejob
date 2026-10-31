import Foundation

/// A clip's integrated loudness and true peak, read off its media's loudness
/// cache (`MediaLoudness`, spec §11 AU-10) over the window that plays — the
/// Volume section's readout and Loudness mode's measurement.
///
/// **What it counts** (AU-11): the plan's audio segments of the clip, the
/// export's channel layout (a mono record's z doubled: the export plays mono
/// as dual mono, +3.01 LU), and on stereo media the clip's own base `mono`
/// fold then `pan` as one 2×2 matrix. Not noise reduction or the compressor,
/// not the volume, fades, ducks, mute or solo, not an enclosing nest's fold:
/// the material's loudness, pre-fader, as Normalize's peak is.
///
/// **The window** (AU-12): the played time in 10 ms steps, each mapped to
/// source ticks through `MediaPeaks.sourceTick` (speed, a ramp's map) and
/// `ReverseMirror` (reversed), pooled in played order across the segments so
/// the gating grid is anchored at the played start; 400 ms gating blocks at
/// a 100 ms hop, counted from the whole steps; −70 LUFS then −10 LU, once.
/// A speed other than ×1 or a ramp reads within about 0.5 LU (spike S4).
enum ClipLoudness {
    /// One gating block: under it there is no integrated loudness.
    static let minimumPlayedTicks: Ticks = 240_000

    /// A step, and a record: 10 ms, the peaks grid.
    static var stepTicks: Ticks { MediaPeaks.bucketTicks }

    /// What a stereo clip's own channel settings do to the two channels, as
    /// `out = M · in`: the channel pick (AU-35), then the base mono fold
    /// (both channels to their mean), then the pan (`AudioPanLaw.gains`),
    /// `AudioClipDSP`'s order. EQ and hum are not counted.
    struct ChannelMatrix: Equatable {
        let m00, m01, m10, m11: Double

        static let identity = ChannelMatrix(m00: 1, m01: 0, m10: 0, m11: 1)

        init(m00: Double, m01: Double, m10: Double, m11: Double) {
            self.m00 = m00
            self.m01 = m01
            self.m10 = m10
            self.m11 = m11
        }

        init(_ props: AudioProps?) {
            guard let props else {
                self = .identity
                return
            }
            let gains = AudioPanLaw.gains(props.pan)
            let left = Double(gains.left)
            let right = Double(gains.right)
            let mix = props.mono
                ? ChannelMatrix(m00: left / 2, m01: left / 2, m10: right / 2, m11: right / 2)
                : ChannelMatrix(m00: left, m01: 0, m10: 0, m11: right)
            // The channel pick first (AU-34, AU-35): pan · fold · pick.
            let pick: ChannelMatrix
            switch props.channels {
            case .both: pick = .identity
            case .left: pick = ChannelMatrix(m00: 1, m01: 0, m10: 1, m11: 0)
            case .right: pick = ChannelMatrix(m00: 0, m01: 1, m10: 0, m11: 1)
            case .swapped: pick = ChannelMatrix(m00: 0, m01: 1, m10: 1, m11: 0)
            }
            self.init(
                m00: mix.m00 * pick.m00 + mix.m01 * pick.m10,
                m01: mix.m00 * pick.m01 + mix.m01 * pick.m11,
                m10: mix.m10 * pick.m00 + mix.m11 * pick.m10,
                m11: mix.m10 * pick.m01 + mix.m11 * pick.m11)
        }
    }

    struct Reading: Equatable {
        /// LUFS; nil under 0.4 s played, or when every block is under −70.
        let lufs: Double?
        /// Linear, the max over the played window (outward).
        let truePeak: Double
        let playedTicks: Ticks
        /// The 10 ms steps' energies (Σ over the output channels of the mean
        /// square), in played order: what `integrated` gates, and what
        /// `AudioLimiterModel` runs over (spec §11 AU-24).
        let steps: [Double]
        /// Each step's true peak, linear: the max of the records its energy
        /// read, on the louder output channel.
        let stepPeaks: [Double]
    }

    enum Answer: Equatable {
        case reading(Reading)
        /// The cache is not written yet.
        case pending
        /// Nothing to read: not one measurable clip.
        case unavailable
    }

    // MARK: - The reading

    static func reading(
        _ cache: MediaLoudness, segments: [PlanSegment], pivots: [Ticks?], matrix: ChannelMatrix
    ) -> Reading {
        let step = stepTicks
        var steps: [Double] = []
        var stepPeaks: [Double] = []
        var peak = 0.0
        var played: Ticks = 0
        let ordered = segments.indices.sorted { segments[$0].start < segments[$1].start }
        for index in ordered {
            let segment = segments[index]
            let pivot = index < pivots.count ? pivots[index] : nil
            played += segment.duration
            if let range = MediaPeaks.window(
                of: segment, from: segment.start, to: segment.start + segment.duration,
                reversedPivot: pivot, bucketTicks: step, count: cache.count) {
                for record in range { peak = max(peak, truePeak(cache, record, matrix)) }
            }
            guard step > 0 else { continue }
            for k in 0..<(segment.duration / step) {
                let from = segment.start + k * step
                var a = MediaPeaks.sourceTick(segment, at: from)
                var b = MediaPeaks.sourceTick(segment, at: from + step)
                if let pivot {
                    a = ReverseMirror.mirrored(a, about: pivot)
                    b = ReverseMirror.mirrored(b, about: pivot)
                }
                let read = energy(cache, from: min(a, b), to: max(a, b), matrix)
                steps.append(read.energy)
                stepPeaks.append(read.peak)
            }
        }
        return Reading(
            lufs: StepLoudness.integrated(steps), truePeak: peak, playedTicks: played,
            steps: steps, stepPeaks: stepPeaks)
    }

    /// One step's Σ over the output channels of the mean square: the mean of
    /// records `[⌊a/step + ½⌋, ⌊b/step + ½⌋)`, else the one record holding the
    /// midpoint. Outside the file reads as silence. Its peak is the largest
    /// true peak of the records it read.
    private static func energy(
        _ cache: MediaLoudness, from a: Ticks, to b: Ticks, _ matrix: ChannelMatrix
    ) -> (energy: Double, peak: Double) {
        let step = stepTicks
        let first = MediaPeaks.bucketIndex(a + step / 2, bucket: step)
        let end = MediaPeaks.bucketIndex(b + step / 2, bucket: step)
        if end > first {
            let lower = max(0, first)
            let upper = min(cache.count, end)
            guard upper > lower else { return (0, 0) }
            var sum = 0.0
            var peak = 0.0
            for record in lower..<upper {
                sum += energy(cache, record, matrix)
                peak = max(peak, truePeak(cache, record, matrix))
            }
            return (sum / Double(end - first), peak)
        }
        let middle = MediaPeaks.bucketIndex(a + (b - a) / 2, bucket: step)
        guard middle >= 0, middle < cache.count else { return (0, 0) }
        return (energy(cache, middle, matrix), truePeak(cache, middle, matrix))
    }

    private static func energy(_ cache: MediaLoudness, _ record: Int, _ m: ChannelMatrix) -> Double {
        let base = record * cache.width
        let r = cache.records
        guard cache.channels == 2 else { return 2 * Double(r[base]) }  // dual mono
        let zL = Double(r[base]), zR = Double(r[base + 1]), zLR = Double(r[base + 2])
        let left = m.m00 * m.m00 * zL + m.m01 * m.m01 * zR + 2 * m.m00 * m.m01 * zLR
        let right = m.m10 * m.m10 * zL + m.m11 * m.m11 * zR + 2 * m.m10 * m.m11 * zLR
        return max(0, left) + max(0, right)
    }

    /// A record's true peak on the louder output channel, bounded by
    /// Σ|m|·tp where the matrix mixes the two.
    private static func truePeak(_ cache: MediaLoudness, _ record: Int, _ m: ChannelMatrix) -> Double {
        let base = record * cache.width
        let r = cache.records
        guard cache.channels == 2 else { return Double(r[base + 1]) }
        let tpL = Double(r[base + 3]), tpR = Double(r[base + 4])
        return max(abs(m.m00) * tpL + abs(m.m01) * tpR, abs(m.m10) * tpL + abs(m.m11) * tpR)
    }

    // MARK: - Loading

    static func loader(cacheDirectory: URL?) -> MediaCacheLoader<MediaLoudness> {
        MediaCacheLoader(cacheDirectory: cacheDirectory) {
            MediaImporter.loadLoudness(for: $0, in: $1)
        }
    }

    /// The answer for one clip of a document, from scratch: Normalize's
    /// admission, the clip's segments of one media, that media's cache.
    static func answer(
        for clip: UInt32, in document: ProjectDocument, loader: MediaCacheLoader<MediaLoudness>
    ) -> Answer {
        let project = document.editedProject
        guard let plan = project.plan else { return .unavailable }
        return answer(
            for: clip, snapshot: project.snapshot, segments: AudioNormalize.audioSegments(in: plan),
            loader: loader)
    }

    /// The same over a plan already indexed, so a run over many clips decodes
    /// the plan once.
    static func answer(
        for clip: UInt32, snapshot: ProjectSnapshot, segments: [UInt32: [PlanSegment]],
        loader: MediaCacheLoader<MediaLoudness>
    ) -> Answer {
        guard AudioNormalize.admit(clip, in: snapshot, segments: segments) == nil,
            let cited = segments[clip], let first = cited.first
        else { return .unavailable }
        let own = cited.filter { $0.media == first.media }
        guard let cache = loader.value(for: first.media) else { return .pending }
        return .reading(
            reading(
                cache, segments: own,
                pivots: own.map { MediaPeaks.reversedPivot(for: $0, in: snapshot) },
                matrix: ChannelMatrix(snapshot.clip(clip)?.audio)))
    }

    // MARK: - The readout's memo

    /// The Volume section's three holds (spec §11 AU-15): an answer per
    /// project handle and clip; one loader across handles, so each media's
    /// file is read once until `invalidate()` (a `loudness` post) drops it;
    /// and, while the document is live-editing, the held answer for the same
    /// clip of the same document without decoding the plan or walking the
    /// steps — a Volume or Pan drag reads nothing per tick, and the first
    /// non-live answer after the gesture recomputes. At volume is the pane's
    /// arithmetic on the answer and the current volume, never memoised.
    final class Memo {
        private weak var project: ReelProject?
        private weak var document: ProjectDocument?
        private var clip: UInt32?
        private var held: Answer?
        private var loader: MediaCacheLoader<MediaLoudness>?
        private var directory: URL?
        /// The files read and the answers computed since `init`: the probe's
        /// counts (C11).
        private(set) var reads = 0
        private(set) var computations = 0

        func answer(for clip: UInt32, in document: ProjectDocument) -> Answer {
            if let held, self.clip == clip, self.document === document,
                document.isLiveEditing || project === document.editedProject {
                return held
            }
            let directory = document.cacheDirectory
            if loader == nil || directory != self.directory {
                self.directory = directory
                loader = MediaCacheLoader(cacheDirectory: directory) { [weak self] media, url in
                    self?.reads += 1
                    return MediaImporter.loadLoudness(for: media, in: url)
                }
            }
            guard let loader else { return .unavailable }
            computations += 1
            let answer = ClipLoudness.answer(for: clip, in: document, loader: loader)
            self.project = document.editedProject
            self.document = document
            self.clip = clip
            held = answer
            return answer
        }

        func invalidate() {
            held = nil
            project = nil
            loader = nil
        }
    }
}
