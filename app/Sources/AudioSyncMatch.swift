import Accelerate
import Foundation

/// Synchronize Audio's signal arithmetic (road maps "audio-sync" and
/// "audio-sync-2"; spec §11 SY-12..SY-14, SY-17, SY-18, SY-21): two files'
/// cached features (and, when both hold speech, their speech masks) in,
/// candidate lags and their confidence out.
///
/// It is pure — no AppKit, no document, no disk. `AudioSync.read` hands it
/// each file's `cache/sync/<media id>.bin` frames (`SyncFeatures`: 26 MFCCs
/// per 16 ms of SOURCE time), and `AudioSync.find` and `plan` turn what it
/// answers into ops or a refusal.
///
/// **The coarse match is on FEATURES** (SY-12). Each stretch compared is
/// standardised per coefficient — gain, microphone and room move a
/// coefficient's level and spread, which standardising takes off — and the
/// correlation is the SUM over coefficients of their full cross-correlations,
/// `c(L) = Σ_k Σ_m x_k[m + L]·y_k[m]`, one zero-padded FFT per coefficient and
/// one inverse of the summed cross-spectrum. A lag's confidence is its
/// z-score against every lag (BBC's `audio-offset-finder`, as `mfccsync.py`
/// measured it on the owner's files). `search` answers the candidates and the
/// best peak near where the mover already sits; `AudioSync+Search.swift`
/// chooses between them (SY-14, SY-18).
///
/// **Speech only** (SY-17): when both stretches hold `minimumSpeechFrames`
/// frames the cached Silero VAD calls speech, each is standardised over its
/// own speech frames and every other frame is 0, so only frames that are
/// speech in both correlate; otherwise every frame counts, as above.
///
/// **Drift** runs on the same features (SY-21): each of its windows is one
/// `search` with a narrower `radius`, the line through them fitted in
/// `AudioSyncDrift.swift`, and each window refined on the samples by
/// `AudioSyncPHAT.swift` (SY-20), which shares `refine` from here.
enum AudioSyncMatch {

    // MARK: - The numbers (SY-12..SY-14)

    /// 2 s of frames: a played window under it is not searched, and a file
    /// under it is too short to match.
    static let minimumStretchFrames = 125
    /// A lag overlapping fewer frames (or the shorter stretch, when that is
    /// shorter) may not be a candidate; it still counts in z's mean and sd.
    static let minimumOverlapFrames = 125
    /// 0.96 s: how far apart two candidates must be — a peak's own shoulders
    /// are not a second candidate.
    static let exclusionFrames = 60
    /// The most candidates a search answers.
    static let candidateCount = 4
    /// The z a best candidate needs to be chosen on its own — the CONFIDENT
    /// tier, which applies without asking (SY-18; BBC's `audio-offset-finder`
    /// reads "> 10 trustworthy"), and applied only when GCC-PHAT confirms it
    /// (SY-29).
    static let confidentZ = 10.0
    /// How far, in z, it must stand above the second candidate.
    static let confidentMargin = 1.5
    /// The z the peak near the mover's placement needs to be chosen — the
    /// WEAK tier, which is asked about, never applied silently (SY-18), and
    /// offered only when GCC-PHAT confirms it (SY-29).
    static let plausibleZ = 4.0
    /// 3.008 s: how near the mover's current placement that peak must lie.
    static let placementRadiusFrames = 188
    /// The VAD probability at or above which a frame is speech (SY-17):
    /// Silero's default, and `detect_silence`'s default `voice_confidence`.
    static let speechProbability: Float = 0.5
    /// The speech frames each stretch needs for a speech-only search (2 s).
    static let minimumSpeechFrames = 125

    /// A feature frame's centre after its start: half of `fftSize` at
    /// `sampleRate` — exactly 19,200 ticks, written as the division for
    /// `SyncFeatures.frameTicks`' reason.
    static var frameCentreTicks: Ticks {
        ReelTime.perSecond * Ticks(SyncFeatures.fftSize / 2) / Ticks(SyncFeatures.sampleRate)
    }

    /// What a search correlated (SY-17).
    enum MatchedOn: String {
        case speech, sound
    }

    // MARK: - The feature search (SY-12, SY-14)

    /// One candidate lag: the anchor's frame minus the mover's frame of the
    /// same sound, file-relative on the timeline grid and refined, with its
    /// z-score.
    struct Candidate: Equatable {
        let lag: Double
        let z: Double
    }

    /// What one search found: its candidates, highest first, and the highest
    /// peak near where the mover already sits (nil when there is none).
    struct SearchResult: Equatable {
        let candidates: [Candidate]
        let nearPlacement: Candidate?
        var matchedOn: MatchedOn = .sound
    }

    // MARK: - Speech masks (SY-17)

    /// Which of a file's `frames` feature frames are speech: frame f is when
    /// the probability of the chunk holding its centre, chunk
    /// `(f·frameTicks + frameCentreTicks) / chunkTicks` (the last when past
    /// the end), is at least `speechProbability`. All false with no
    /// probabilities.
    static func speechMask(_ probabilities: [Float], frames: Int) -> [Bool] {
        guard !probabilities.isEmpty else { return [Bool](repeating: false, count: frames) }
        let chunk = MediaSpeech.chunkTicks
        return (0..<frames).map { f in
            let index = min(
                Int((Ticks(f) * SyncFeatures.frameTicks + frameCentreTicks) / chunk),
                probabilities.count - 1)
            return probabilities[index] >= speechProbability
        }
    }

    /// `mask` on the timeline grid of a clip playing at `speed`, as
    /// `resampledFrames` takes its frames: frame k is source frame
    /// `round(k·speed)` (the last when past it). The mask itself at ×1.
    static func resampledMask(_ mask: [Bool], speed: Double) -> [Bool] {
        let count = mask.count
        guard speed != 1, speed.isFinite, speed > 0, count > 1 else { return mask }
        let last = count - 1
        let resampledCount = Int((Double(last) / speed).rounded(.down)) + 1
        return (0..<resampledCount).map { mask[min(Int((Double($0) * speed).rounded()), last)] }
    }

    /// `frames` standardised per coefficient: mean 0, sd 1 (the population
    /// sd), over the whole stretch, or with `speech` over its true frames
    /// only, every false frame then 0 (SY-17). A coefficient whose sd is
    /// under 1e-6 is 0.
    static func standardised(_ frames: [Float], speech: [Bool]? = nil) -> [Float] {
        let width = SyncFeatures.coefficients
        let count = frames.count / width
        var result = [Float](repeating: 0, count: count * width)
        guard count > 0 else { return result }
        let counted = speech.map { mask in (0..<count).filter { $0 < mask.count && mask[$0] } }
            ?? Array(0..<count)
        guard !counted.isEmpty else { return result }
        for k in 0..<width {
            var sum = 0.0
            for f in counted { sum += Double(frames[f * width + k]) }
            let mean = sum / Double(counted.count)
            var squares = 0.0
            for f in counted {
                let d = Double(frames[f * width + k]) - mean
                squares += d * d
            }
            let sd = (squares / Double(counted.count)).squareRoot()
            guard sd >= 1e-6 else { continue }
            for f in counted {
                result[f * width + k] = Float((Double(frames[f * width + k]) - mean) / sd)
            }
        }
        return result
    }

    /// Whether `frames` hold no sound to line up by: every coefficient is 0
    /// once standardised (each is constant over the stretch).
    static func isSilent(_ frames: [Float]) -> Bool {
        standardised(frames).allSatisfy { $0 == 0 }
    }

    /// `c[L] = Σ_k Σ_m x_k[m+L]·y_k[m]` over the `SyncFeatures.coefficients`
    /// of two frame-major arrays, for L from −(ny−1) to nx−1 at index
    /// L + ny − 1: each coefficient's zero-padded `vDSP_fft_zrip`, the
    /// cross-spectra summed, and ONE inverse transform.
    static func summedCorrelation(_ x: [Float], _ y: [Float]) -> [Double] {
        let width = SyncFeatures.coefficients
        let nx = x.count / width
        let ny = y.count / width
        guard nx > 0, ny > 0 else { return [] }
        let lags = nx + ny - 1
        var log2n = 1
        while (1 << log2n) < lags { log2n += 1 }
        let n = 1 << log2n
        let half = n / 2
        guard let setup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2)) else {
            var result = [Double](repeating: 0, count: lags)
            for k in 0..<width {
                let column = direct(
                    (0..<nx).map { x[$0 * width + k] }, (0..<ny).map { y[$0 * width + k] })
                for index in 0..<lags { result[index] += column[index] }
            }
            return result
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var padded = [Float](repeating: 0, count: n)
        func spectrum(_ values: [Float], count: Int, column: Int) -> ([Float], [Float]) {
            for index in 0..<n { padded[index] = index < count ? values[index * width + column] : 0 }
            var real = [Float](repeating: 0, count: half)
            var imaginary = [Float](repeating: 0, count: half)
            real.withUnsafeMutableBufferPointer { re in
                imaginary.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                    padded.withUnsafeBufferPointer { source in
                        source.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(
                        setup, &split, 1, vDSP_Length(log2n), FFTDirection(kFFTDirection_Forward))
                }
            }
            return (real, imaginary)
        }

        // Σ_k X_k · conj(Y_k). DC and Nyquist are real and multiply on their own.
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        for k in 0..<width {
            let (xr, xi) = spectrum(x, count: nx, column: k)
            let (yr, yi) = spectrum(y, count: ny, column: k)
            real[0] += xr[0] * yr[0]
            imaginary[0] += xi[0] * yi[0]
            for bin in 1..<half {
                real[bin] += xr[bin] * yr[bin] + xi[bin] * yi[bin]
                imaginary[bin] += xi[bin] * yr[bin] - xr[bin] * yi[bin]
            }
        }
        var circular = [Float](repeating: 0, count: n)
        real.withUnsafeMutableBufferPointer { re in
            imaginary.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                vDSP_fft_zrip(
                    setup, &split, 1, vDSP_Length(log2n), FFTDirection(kFFTDirection_Inverse))
                circular.withUnsafeMutableBufferPointer { out in
                    out.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ztoc(&split, 1, $0, 2, vDSP_Length(half))
                    }
                }
            }
        }
        // Each forward spectrum is scaled by 2 and the inverse by n.
        let scale = 1 / (4 * Double(n))
        var result = [Double](repeating: 0, count: lags)
        for index in 0..<lags {
            let lag = index - (ny - 1)
            result[index] = Double(circular[lag >= 0 ? lag : n + lag]) * scale
        }
        return result
    }

    /// One search (SY-12, SY-14, SY-17): the anchor's and the mover's
    /// stretches, frame-major on the timeline grid, with their speech masks
    /// (nil without the model); `offset` the anchor stretch's first frame
    /// minus the mover's, which makes a stretch lag file-relative;
    /// `placementLag` the file-relative lag at which the mover already sits,
    /// and `radius` how near it the near placement must lie (drift's windows
    /// search a narrower one, SY-21). Speech only when both masks hold
    /// `minimumSpeechFrames` true frames.
    /// nil when either stretch is silent or no lag overlaps enough to score.
    static func search(
        anchor: [Float], mover: [Float], anchorSpeech: [Bool]?, moverSpeech: [Bool]?,
        offset: Int, placementLag: Double, radius: Int = placementRadiusFrames
    ) -> SearchResult? {
        let width = SyncFeatures.coefficients
        func spoken(_ mask: [Bool]?) -> Bool {
            (mask?.lazy.filter { $0 }.count ?? 0) >= minimumSpeechFrames
        }
        let onSpeech = spoken(anchorSpeech) && spoken(moverSpeech)
        let (x, y) = onSpeech
            ? (standardised(anchor, speech: anchorSpeech), standardised(mover, speech: moverSpeech))
            : (standardised(anchor), standardised(mover))
        guard x.contains(where: { $0 != 0 }), y.contains(where: { $0 != 0 }) else { return nil }
        let na = x.count / width
        let nb = y.count / width
        let c = summedCorrelation(x, y)
        let lags = c.count

        // z over EVERY lag, as `mfccsync.py` takes it.
        let mean = c.reduce(0, +) / Double(lags)
        let sd = (c.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(lags)).squareRoot()
        func z(_ index: Int) -> Double { sd > 0 ? (c[index] - mean) / sd : 0 }

        let needed = min(minimumOverlapFrames, min(na, nb))
        let scored = (0..<lags).map { index -> Bool in
            let lag = index - (nb - 1)
            return min(nb, na - lag) - max(0, -lag) >= needed
        }
        guard scored.contains(true) else { return nil }
        func candidate(_ index: Int) -> Candidate {
            let shift = refine(
                left: index > 0 ? c[index - 1] : nil, centre: c[index],
                right: index + 1 < lags ? c[index + 1] : nil)
            return Candidate(lag: Double(index - (nb - 1) + offset) + shift, z: z(index))
        }

        // Local maxima among the scored lags; a neighbour not scored is no
        // rival. Kept highest first, each more than `exclusionFrames` from
        // every one kept before it.
        var peaks: [Int] = []
        for index in 0..<lags where scored[index] {
            let left = index > 0 && scored[index - 1] ? c[index - 1] : -.infinity
            let right = index + 1 < lags && scored[index + 1] ? c[index + 1] : -.infinity
            if c[index] > left && c[index] >= right { peaks.append(index) }
        }
        peaks.sort { c[$0] > c[$1] }
        var kept: [Int] = []
        for index in peaks where kept.allSatisfy({ abs($0 - index) > exclusionFrames }) {
            kept.append(index)
            if kept.count == candidateCount { break }
        }

        // The highest true peak within the radius: both neighbours scored and
        // strictly lower, so a flank of a peak outside it is never one.
        var near: Int?
        for index in stride(from: 1, to: lags - 1, by: 1)
        where scored[index] && scored[index - 1] && scored[index + 1]
            && c[index] > c[index - 1] && c[index] > c[index + 1] {
            let lag = Double(index - (nb - 1) + offset)
            guard abs(lag - placementLag) <= Double(radius) else { continue }
            if near.map({ c[index] > c[$0] }) ?? true { near = index }
        }
        return SearchResult(
            candidates: kept.map(candidate), nearPlacement: near.map(candidate),
            matchedOn: onSpeech ? .speech : .sound)
    }

    /// `frames` on the timeline grid of a clip playing at `speed`:
    /// frame k is source frame k·speed, each coefficient interpolated
    /// linearly between its two neighbours. The frames themselves at ×1.
    static func resampledFrames(_ frames: [Float], speed: Double) -> [Float] {
        let width = SyncFeatures.coefficients
        let count = frames.count / width
        guard speed != 1, speed.isFinite, speed > 0, count > 1 else { return frames }
        let last = count - 1
        let resampledCount = Int((Double(last) / speed).rounded(.down)) + 1
        var result = [Float](repeating: 0, count: resampledCount * width)
        for frame in 0..<resampledCount {
            let position = Double(frame) * speed
            let index = min(Int(position), last)
            let fraction = index < last ? position - Double(index) : 0
            let next = min(index + 1, last)
            for k in 0..<width {
                result[frame * width + k] = Float(
                    Double(frames[index * width + k]) * (1 - fraction)
                        + Double(frames[next * width + k]) * fraction)
            }
        }
        return result
    }

    // MARK: - Arithmetic

    /// The vertex of the parabola through three neighbouring scores, as an
    /// offset from the centre, clamped to ±0.5; 0 without both neighbours or
    /// when the three do not bend down.
    static func refine(left: Double?, centre: Double, right: Double?) -> Double {
        guard let left = left, let right = right else { return 0 }
        let bend = left - 2 * centre + right
        guard bend < 0 else { return 0 }
        let offset = 0.5 * (left - right) / bend
        return min(0.5, max(-0.5, offset))
    }

    /// `c[L] = Σ x[m+L]·y[m]`, one by one: `summedCorrelation`'s fallback, a
    /// coefficient at a time, when no FFT setup can be made.
    private static func direct(_ x: [Float], _ y: [Float]) -> [Double] {
        let ny = y.count
        var result = [Double](repeating: 0, count: x.count + ny - 1)
        for index in result.indices {
            let lag = index - (ny - 1)
            var sum = 0.0
            for m in max(0, -lag)..<min(ny, x.count - lag) {
                sum += Double(x[m + lag]) * Double(y[m])
            }
            result[index] = sum
        }
        return result
    }
}
