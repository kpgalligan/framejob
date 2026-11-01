import Accelerate
import Foundation

// The noise-reduction stage `AudioDSPChain` runs: a pure move out of `AudioDSP.swift` (road
// map "audio" AP0's toll T1), whose head says why the stages have no AVFoundation in them
// and what real-time discipline they keep.

// MARK: - Noise reduction

/// Broadband noise reduction, one instance per channel: a short-time spectral
/// attenuator over a noise floor the signal itself is measured for.
///
/// **What it actually does**, spelled out so that neither this comment nor the
/// pane's label can overstate it. The signal is cut into 512-sample frames
/// every 128 samples and each is windowed and transformed. A per-bin estimate
/// of the background noise floor is tracked continuously. Each bin is then
/// multiplied by a Wiener gain — `SNR / (SNR + k)` — over a decision-directed
/// estimate of that bin's signal-to-noise ratio, with `k` the over-subtraction
/// factor the user's amount sets and a floor under the result so a suppressed
/// bin fades rather than vanishes. The frames are windowed again and
/// overlap-added back.
///
/// **It is not a gate, and the difference is the point.** Nothing here
/// compares a level with a threshold and decides between "signal" and
/// "silence": every bin of every frame keeps the fraction of itself that its
/// own SNR says is signal, so a quiet passage keeps its content and a steady
/// hiss is attenuated *underneath* speech rather than only between words. What
/// it cannot do is remove a noise that is not stationary — a door slam, a
/// cough — because nothing distinguishes those from the material.
///
/// **The noise estimate is continuous minimum tracking** (Doblinger's
/// recursive-minimum variant of Martin's minimum statistics): the smoothed
/// power in each bin is followed by a value that falls to it instantly and
/// rises back only slowly, so it settles on the floor the bin returns to
/// between sounds. That needs no noise print from the user and no silence at
/// the head of the clip. Its known cost is that a bin which is never quiet —
/// a long held note — is eventually read as noise; `minimumRise` is set for
/// that case and the decision-directed SNR carries the rest.
///
/// **Latency.** An STFT cannot see a sample's neighbours before they arrive,
/// so the output lags the input by one analysis window: 512 samples, 10.7 ms
/// at 48 kHz. Measured, not assumed: a tap's process callback cannot read
/// ahead — a second `MTAudioProcessingTapGetSourceAudio` inside one callback
/// returns the SAME audio again rather than the next block, so priming a
/// look-ahead is impossible. 10.7 ms is far inside every A/V sync tolerance
/// and applies only to a track some clip of which asks for noise reduction;
/// `AudioTap` keeps the stage running for the whole track once any clip on it
/// does, so the delay never changes at a cut.
final class AudioNoiseReductionStage {
    /// Analysis window, a power of two for `vDSP`'s radix-2 FFT.
    static let window = 512
    /// Hop: 75 % overlap, which is what a √Hann pair needs to add back up to
    /// a constant and is fine enough that a modified bin does not smear.
    static let hop = 128

    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let half: Int

    /// √Hann, used for BOTH analysis and synthesis (Griffin–Lim): windowing
    /// twice is what keeps a per-bin gain change from clicking at the frame
    /// edges.
    private let windowCurve: UnsafeMutablePointer<Float>
    /// Everything below is allocated once and reused every frame.
    private let history: UnsafeMutablePointer<Float>      // last `window` inputs
    private let staging: UnsafeMutablePointer<Float>      // this hop's inputs
    private let frame: UnsafeMutablePointer<Float>
    private let real: UnsafeMutablePointer<Float>
    private let imaginary: UnsafeMutablePointer<Float>
    private let power: UnsafeMutablePointer<Float>        // half + 1
    private let smoothed: UnsafeMutablePointer<Float>     // half + 1
    private let minimum: UnsafeMutablePointer<Float>      // half + 1
    private let binGain: UnsafeMutablePointer<Float>      // half + 1
    /// Last frame's estimate of the CLEAN power per bin, which is what makes
    /// the a priori SNR below a decision-directed one rather than a raw
    /// per-frame ratio.
    private let cleaned: UnsafeMutablePointer<Float>      // half + 1
    private let overlap: UnsafeMutablePointer<Float>      // window
    /// The finished samples waiting to be handed back, as a plain FIFO with a
    /// read and a write index. It never holds more than two hops, and it is
    /// compacted on a push rather than shifted on a pop — a `memmove` per
    /// SAMPLE is what a naive queue costs here, and this runs on the audio
    /// thread.
    private let output: UnsafeMutablePointer<Float>       // window + hop
    private var outputHead = 0
    private var outputTail = 0
    private var stagedCount = 0
    /// False until the first frame has been analysed. The tracker starts at
    /// that frame's own power rather than at zero: from zero it would take
    /// its whole rise constant to charge up to the noise floor, and until it
    /// did every bin would look like signal and nothing would be removed.
    private var primed = false
    /// The forward/inverse round trip's scale, times the overlap-add
    /// normalisation. Both are constants of the window and the hop, so they
    /// are folded into one multiply.
    private let scale: Float

    /// Smoothing of the per-bin power before the minimum tracker sees it.
    private let powerSmoothing: Float = 0.7
    /// How fast the tracked minimum may rise back — the one number that
    /// decides whether a held note is mistaken for the room.
    ///
    /// The tracker FALLS instantly and rises at this rate, so an
    /// overestimate corrects itself within a few frames of quiet while an
    /// underestimate persists. That asymmetry says to be slow: 0.9999 per hop
    /// is about 27 s at 48 kHz. Measured on a one-second 700 Hz tone buried
    /// in white noise, 0.998 (1.4 s) took 12 dB off the tone and 0.9995 (5 s)
    /// took 10 dB, because the tracker climbed to the tone and the filter
    /// then read it as the floor; at 0.9999 the tone comes through within
    /// half a dB and the noise-only stretches still lose 13.
    private let minimumRise: Float = 0.9999
    private let minimumBias: Float = 0.96
    /// The tracked minimum reads low, because it is a minimum; the usual
    /// compensation for the bias of that estimator.
    private let noiseBias: Float = 1.5
    /// How much of the a priori SNR is carried from the previous frame's
    /// clean estimate. 0.98 is Ephraim and Malah's own figure, and it is what
    /// stops the gain from chattering bin by bin — the chatter IS musical
    /// noise.
    private let decisionDirected: Float = 0.98

    init?() {
        var n = 1
        var bits: vDSP_Length = 0
        while n < Self.window {
            n <<= 1
            bits += 1
        }
        guard n == Self.window, let setup = vDSP_create_fftsetup(bits, FFTRadix(kFFTRadix2))
        else { return nil }
        self.setup = setup
        log2n = bits
        half = Self.window / 2

        windowCurve = .allocate(capacity: Self.window)
        history = .allocate(capacity: Self.window)
        staging = .allocate(capacity: Self.hop)
        frame = .allocate(capacity: Self.window)
        real = .allocate(capacity: half)
        imaginary = .allocate(capacity: half)
        power = .allocate(capacity: half + 1)
        smoothed = .allocate(capacity: half + 1)
        minimum = .allocate(capacity: half + 1)
        binGain = .allocate(capacity: half + 1)
        cleaned = .allocate(capacity: half + 1)
        overlap = .allocate(capacity: Self.window)
        output = .allocate(capacity: Self.window + Self.hop)

        history.initialize(repeating: 0, count: Self.window)
        staging.initialize(repeating: 0, count: Self.hop)
        frame.initialize(repeating: 0, count: Self.window)
        real.initialize(repeating: 0, count: half)
        imaginary.initialize(repeating: 0, count: half)
        power.initialize(repeating: 0, count: half + 1)
        smoothed.initialize(repeating: 0, count: half + 1)
        minimum.initialize(repeating: 0, count: half + 1)
        binGain.initialize(repeating: 1, count: half + 1)
        cleaned.initialize(repeating: 0, count: half + 1)
        overlap.initialize(repeating: 0, count: Self.window)
        output.initialize(repeating: 0, count: Self.window + Self.hop)

        // Periodic Hann, square-rooted: `hann` itself is what the analysis and
        // synthesis windows multiply to, and 75 % overlap makes those sum to a
        // constant. The constant is computed rather than quoted, so the round
        // trip is unity whatever the window and hop become.
        var overlapSum: Float = 0
        for index in 0..<Self.window {
            let hann = 0.5 - 0.5 * cos(2 * Float.pi * Float(index) / Float(Self.window))
            windowCurve[index] = sqrt(max(hann, 0))
        }
        for step in stride(from: 0, to: Self.window, by: Self.hop) {
            let sample = windowCurve[step]
            overlapSum += sample * sample
        }
        // `vDSP_fft_zrip` returns a spectrum scaled by 2, and the inverse does
        // not undo the transform's own length, so a round trip needs 1/(2·N).
        scale = 1 / (2 * Float(Self.window) * max(overlapSum, .leastNormalMagnitude))
        resetState()
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("AudioNoiseReductionStage does not support NSCoder")
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        windowCurve.deallocate()
        history.deallocate()
        staging.deallocate()
        frame.deallocate()
        real.deallocate()
        imaginary.deallocate()
        power.deallocate()
        smoothed.deallocate()
        minimum.deallocate()
        binGain.deallocate()
        cleaned.deallocate()
        overlap.deallocate()
        output.deallocate()
    }

    /// Empties the pipeline and re-primes the delay line.
    ///
    /// The queue starts holding ONE HOP of silence, not one window. Frame `k`
    /// finishes the hop of output that begins at input `(k + 1)·hop − window`,
    /// so the overlap-add itself already delays by `window − hop`; priming the
    /// queue with one more hop makes the total exactly `window` and — checked
    /// against every arrival pattern, not just the tidy one — leaves the queue
    /// unable to run dry between hops.
    func reset() { resetState() }

    private func resetState() {
        history.update(repeating: 0, count: Self.window)
        staging.update(repeating: 0, count: Self.hop)
        overlap.update(repeating: 0, count: Self.window)
        output.update(repeating: 0, count: Self.window + Self.hop)
        smoothed.update(repeating: 0, count: half + 1)
        minimum.update(repeating: 0, count: half + 1)
        cleaned.update(repeating: 0, count: half + 1)
        primed = false
        outputHead = 0
        outputTail = Self.hop
        stagedCount = 0
    }

    /// Filters `frames` samples in place.
    ///
    /// `amount` is the clip's `noise_reduction`, read fresh on every call
    /// because the clip under the playhead changes at every cut. At 0 the
    /// gain floor is 1, every bin's gain is 1, and the stage is an exact
    /// (float-precision) delay rather than a filter — which is what keeps a
    /// track that mixes reduced and unreduced clips from changing its latency
    /// halfway through.
    func process(_ data: UnsafeMutablePointer<Float>, frames: Int, amount: Double) {
        guard frames > 0 else { return }
        let clamped = Float(min(max(amount.isFinite ? amount : 0, 0), 1))
        // Over-subtraction: 1 removes exactly the estimate, 4 removes four
        // times it. The floor is what is left of a bin the subtraction would
        // otherwise empty; at amount 0 it is 1, which makes every gain 1.
        let overSubtraction = 1 + 3 * clamped
        let floorGain = 1 - clamped

        for index in 0..<frames {
            // Samples are staged a hop at a time and the history is shifted
            // once per hop, not once per sample: the window is a plain
            // in-order buffer (which is what `vDSP_vmul` wants) and the price
            // of that is 384 floats moved per 128 samples rather than 511 per
            // one. A ring buffer would need no move at all and would cost an
            // unwrap on every read of every frame instead — the wrong trade at
            // 75 % overlap.
            staging[stagedCount] = data[index]
            stagedCount += 1
            if stagedCount == Self.hop {
                stagedCount = 0
                memmove(
                    history, history + Self.hop,
                    (Self.window - Self.hop) * MemoryLayout<Float>.size)
                (history + Self.window - Self.hop).update(from: staging, count: Self.hop)
                processFrame(overSubtraction: overSubtraction, floorGain: floorGain)
            }
            data[index] = popOutput()
        }
    }

    /// One analysis/synthesis frame over the newest `window` samples.
    private func processFrame(overSubtraction: Float, floorGain: Float) {
        vDSP_vmul(history, 1, windowCurve, 1, frame, 1, vDSP_Length(Self.window))

        var split = DSPSplitComplex(realp: real, imagp: imaginary)
        frame.withMemoryRebound(to: DSPComplex.self, capacity: half) { pointer in
            vDSP_ctoz(pointer, 2, &split, 1, vDSP_Length(half))
        }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))

        // `vDSP_fft_zrip` packs DC in real[0] and Nyquist in imaginary[0];
        // both are real, so they get their own slots at either end of the
        // power array rather than being treated as a complex pair.
        power[0] = real[0] * real[0]
        power[half] = imaginary[0] * imaginary[0]
        for bin in 1..<half {
            power[bin] = real[bin] * real[bin] + imaginary[bin] * imaginary[bin]
        }

        for bin in 0...half {
            let current = power[bin]
            let smooth =
                primed ? powerSmoothing * smoothed[bin] + (1 - powerSmoothing) * current : current
            if !primed {
                minimum[bin] = smooth
            } else if minimum[bin] < smooth {
                // Rise slowly, and only as fast as the smoothed power itself
                // is rising — Doblinger's recursion, which is what stops a
                // long vowel from dragging the floor up with it.
                minimum[bin] =
                    minimumRise * minimum[bin]
                    + ((1 - minimumRise) / (1 - minimumBias))
                    * (smooth - minimumBias * smoothed[bin])
            } else {
                minimum[bin] = smooth
            }
            smoothed[bin] = smooth

            // The gain is a Wiener filter over the a priori SNR, and the a
            // priori SNR is the decision-directed estimate: mostly what last
            // frame's clean output says this bin holds, corrected by what
            // this frame's power says. Subtracting the noise estimate from
            // the power directly (the textbook subtractor) makes the gain
            // jump with the periodogram's own variance, which is heard as
            // bins winking in and out; this does not.
            let noise = max(max(minimum[bin], 0) * noiseBias, .leastNormalMagnitude)
            let posterior = current / noise
            let prior = max(
                decisionDirected * cleaned[bin] / noise
                    + (1 - decisionDirected) * max(posterior - 1, 0),
                1e-6)
            // `overSubtraction` in the denominator generalises the filter: 1
            // is the plain Wiener gain, 4 removes four times as much for the
            // same SNR. The floor is what a bin keeps when the filter would
            // otherwise empty it — at amount 0 the floor is 1 and the whole
            // rule collapses to a no-op.
            let gain = max(floorGain, prior / (prior + overSubtraction))
            binGain[bin] = gain
            cleaned[bin] = gain * gain * current
        }
        primed = true

        real[0] *= binGain[0]
        imaginary[0] *= binGain[half]
        for bin in 1..<half {
            real[bin] *= binGain[bin]
            imaginary[bin] *= binGain[bin]
        }

        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Inverse))
        frame.withMemoryRebound(to: DSPComplex.self, capacity: half) { pointer in
            vDSP_ztoc(&split, 1, pointer, 2, vDSP_Length(half))
        }
        var factor = scale
        vDSP_vsmul(frame, 1, &factor, frame, 1, vDSP_Length(Self.window))
        vDSP_vmul(frame, 1, windowCurve, 1, frame, 1, vDSP_Length(Self.window))
        vDSP_vadd(overlap, 1, frame, 1, overlap, 1, vDSP_Length(Self.window))

        // The first `hop` samples of the accumulator have now been summed by
        // every frame that covers them, so they are finished: they go to the
        // output queue and the accumulator slides.
        pushOutput(overlap, count: Self.hop)
        memmove(overlap, overlap + Self.hop, (Self.window - Self.hop) * MemoryLayout<Float>.size)
        (overlap + Self.window - Self.hop).update(repeating: 0, count: Self.hop)
    }

    /// Appends finished samples, compacting the queue first when the tail has
    /// run out of room. The queue holds at most two hops, so the capacity of
    /// `window + hop` can never actually be exceeded; the `take` clamp is
    /// there so that a future window/hop pair which broke that invariant would
    /// drop samples rather than write off the end.
    private func pushOutput(_ source: UnsafeMutablePointer<Float>, count: Int) {
        let capacity = Self.window + Self.hop
        if outputTail + count > capacity {
            let held = outputTail - outputHead
            if held > 0 { memmove(output, output + outputHead, held * MemoryLayout<Float>.size) }
            outputHead = 0
            outputTail = held
        }
        let take = min(count, capacity - outputTail)
        guard take > 0 else { return }
        (output + outputTail).update(from: source, count: take)
        outputTail += take
    }

    private func popOutput() -> Float {
        guard outputHead < outputTail else { return 0 }
        let value = output[outputHead]
        outputHead += 1
        return value
    }
}
