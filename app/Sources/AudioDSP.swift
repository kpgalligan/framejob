import Accelerate
import Foundation

/// The four sample-level audio effects the model carries and AVFoundation
/// cannot express: pan, the mono fold, the compressor and broadband noise
/// reduction (spec §4.2, §5.2's `AudioProps`).
///
/// **Why this file has no AVFoundation in it.** Volume, the fades and ducking
/// are a gain CURVE, so `audio.rs` folds them into one envelope per
/// composition track and `AVMutableAudioMixInputParameters` plays it back as
/// volume ramps. These four cannot be a curve: pan and the mono fold need
/// every channel at once to write to, and the compressor and the noise reducer
/// are functions of the samples rather than of the clock. So they are real
/// DSP, they run in Swift,
/// and they live here — plain buffers in, plain buffers out, no player, no
/// reader, no tap. `AudioTap.swift` is the only file that knows where the
/// buffers come from, which is what lets the SAME code serve the preview and
/// the export (§7.2's one-movie-one-description rule).
///
/// **Real-time discipline.** Everything runs inside
/// `MTAudioProcessingTap`'s process callback, on a thread that must not
/// block: every buffer these types touch is allocated once in `init` and
/// never grown, nothing here takes a lock, and no Swift value that could
/// allocate is created per sample. `frames` is never larger than the
/// `maxFrames` the chain was built with.
///
/// **Transparency is a property of the CALLER, not of these types.** With
/// pan 0, mono off, no compressor and noise reduction 0 the chain is still a
/// chain, and
/// running audio through the noise reducer's FFT round trip would change the
/// low bits even though it changes nothing audible. So `CompositionBuilder`
/// installs no tap at all on a track whose every clip is inert
/// (`AudioClipDSP.isInert`), and such a track's samples are the ones today's
/// build produces, byte for byte.
enum AudioDSP {
    /// Below this the compressor's detector is treated as silence rather than
    /// fed to `log10`, which would otherwise return -inf and poison the
    /// envelope. -180 dBFS: far under any 24-bit source's noise floor.
    static let silenceFloor: Float = 1e-9

    /// dB → linear gain, and the constant that turns a dB difference into an
    /// exponent for `expf` (ln 10 / 20). One `expf` per sample is cheaper than
    /// one `powf`.
    static let dbToExponent: Float = 0.115_129_254_649_702_28

    static func gain(fromDecibels db: Float) -> Float { expf(db * dbToExponent) }
}

// MARK: - Parameters

/// The compressor's settings in the units the DSP works in.
///
/// The model spells the two time constants in TICKS, like every other time in
/// the schema (`core/src/model.rs`'s `Compressor`). They become seconds
/// exactly once, in `AudioClipDSP`'s conversion, so nothing below this line
/// ever sees a tick — the rule the slice was written to.
struct AudioCompressorSettings: Equatable {
    /// dBFS above which gain reduction starts, clamped to the model's -60…0.
    var thresholdDB: Double
    /// N:1. 1 is no reduction at all (the makeup still applies), 20 is
    /// effectively a limiter.
    var ratio: Double
    /// Seconds for the reduction to close on a level that just rose.
    var attackSeconds: Double
    /// Seconds for it to open again on a level that just fell.
    var releaseSeconds: Double
    /// dB added after the reduction, to win back what it took.
    var makeupDB: Double

    init(
        thresholdDB: Double, ratio: Double, attackSeconds: Double, releaseSeconds: Double,
        makeupDB: Double
    ) {
        // A hand-edited project can carry anything; the op's own range checks
        // (`props_check.rs`'s `check_audio`) only cover what the app wrote.
        self.thresholdDB = thresholdDB.isFinite ? Swift.min(Swift.max(thresholdDB, -60), 0) : -18
        self.ratio = ratio.isFinite ? Swift.min(Swift.max(ratio, 1), 20) : 1
        self.attackSeconds = attackSeconds.isFinite ? Swift.max(attackSeconds, 0) : 0
        self.releaseSeconds = releaseSeconds.isFinite ? Swift.max(releaseSeconds, 0) : 0
        self.makeupDB = makeupDB.isFinite ? Swift.min(Swift.max(makeupDB, 0), 24) : 0
    }
}

/// One clip's worth of sample-level audio settings — everything the model
/// carries that the composition plan cannot.
///
/// A composition audio track holds many clips one after another (§7.2), so
/// these change at every cut on the track; `AudioTap` looks the right one up
/// by the buffer's own timestamp.
struct AudioClipDSP: Equatable {
    /// -1 hard left … +1 hard right. See `AudioPanLaw`.
    var pan: Double
    var compressor: AudioCompressorSettings?
    /// 0 off … 1 the most subtraction this build will do.
    var noiseReduction: Double
    /// `AudioProps.mono`: average every channel into all of them. It rides
    /// here rather than in the plan because the plan carries nothing a
    /// property edit changes, and because the per-clip sample-level settings
    /// already travel this way, keyed by clip id.
    var mono: Bool
    /// The same fold, asked for by a nest clip this one is INSIDE, and run at
    /// the tail of the chain rather than at the head of the Mix stage.
    ///
    /// **Why it is a second flag rather than the same one.** A nest clip's
    /// `mono` is a statement about the nest's MIX, and the mix is a sum: the
    /// fold is linear, so folding every contributor separately and adding
    /// them gives exactly the same samples as adding them and folding once —
    /// but only if each contributor is folded after everything IT does to its
    /// own channels. Folding at the head instead would put the inner clip's
    /// own pan after the nest's fold, and a hard-left clip inside a folded
    /// nest would come out hard left, which is not mono at all. The plan's
    /// envelope is a scalar per track and applies to every channel equally,
    /// so it commutes with the fold and may stay downstream of the tap.
    var enclosingMono: Bool

    init(
        pan: Double = 0, compressor: AudioCompressorSettings? = nil, noiseReduction: Double = 0,
        mono: Bool = false, enclosingMono: Bool = false
    ) {
        self.pan = pan.isFinite ? Swift.min(Swift.max(pan, -1), 1) : 0
        self.compressor = compressor
        self.noiseReduction =
            noiseReduction.isFinite ? Swift.min(Swift.max(noiseReduction, 0), 1) : 0
        // No clamping: a bool has no range.
        self.mono = mono
        self.enclosingMono = enclosingMono
    }

    /// The settings that change nothing. A composition track on which every
    /// clip is inert gets no tap, which is what makes an untouched project's
    /// audio bit-identical to the build before this file existed.
    static let inert = AudioClipDSP()

    /// True when this clip asks for no sample work whatsoever. `pan == 0` is
    /// exact rather than approximate on purpose: the pan law is unity at the
    /// centre, so 0 and "nearly 0" differ by nothing audible, and treating a
    /// hand-written 1e-18 as active costs one silent multiply rather than a
    /// wrong answer.
    var isInert: Bool {
        pan == 0 && compressor == nil && noiseReduction <= 0 && !mono && !enclosingMono
    }
}

// MARK: - Pan

/// The pan law: constant power, normalised to unity at the centre.
///
/// **Why constant power.** Two uncorrelated channels sum by POWER, so a law
/// that keeps `L² + R²` constant is the one that holds perceived loudness
/// across the sweep; the linear law (`L = 1 - t`, `R = t`) drops 6 dB in the
/// middle and sounds like a dip as the clip crosses the centre.
///
/// **Why normalised to unity rather than to the edges.** The textbook
/// constant-power law puts 0.707 in both channels at the centre — a 3 dB cut
/// applied to every clip whose pan is 0, which is every clip in every project
/// that has ever been opened in this app. Multiplying the pair by √2 moves
/// the unity point to the centre instead, so pan 0 is EXACTLY a no-op
/// (`gains(0) == (1, 1)` is asserted, not hoped for) and the price is paid at
/// the extremes, where a hard-panned clip is 3 dB louder in the channel it
/// went to. That is the right trade for an editor: the common case is
/// transparent and the loud case is one the user chose.
///
/// **On a stereo clip this is a BALANCE.** Applying one gain to L and another
/// to R does not move a stereo image the way panning a mono source into a
/// stereo bus does; it leans it. That is what every editor's clip-level pan
/// does, and folding to mono first to get a "true" pan would throw away the
/// stereo the clip was recorded with.
///
/// **On a clip that asks for `mono` it is a TRUE pan**, and that is the
/// honest description rather than a special case: the fold runs at the head of
/// the Mix stage, immediately before this, so both channels hold the same
/// signal and leaning them moves one source between two speakers. It is also
/// why the fold cannot go after the pan — `(g_L·x + g_R·x)/2 = ((g_L+g_R)/2)·x`
/// is the same signal in both channels at every pan position, so the control
/// would degrade into a gain change and read as broken. A fold an enclosing
/// NEST clip asks for DOES run after this pan, and is not that case: it folds
/// the nest's mix, and flattening whatever panning happens inside the nest is
/// precisely what that means (`AudioDSPChain`).
///
/// **A mono composition track cannot be panned at all** — measured, not
/// assumed: a tap on a track whose source is mono is prepared with one
/// channel, and the upmix to stereo happens downstream of it. There is no
/// second channel to write to, so pan on such a clip is inaudible; see
/// `AudioDSPChain.process`.
enum AudioPanLaw {
    static func gains(_ pan: Double) -> (left: Float, right: Float) {
        guard pan.isFinite, pan != 0 else { return (1, 1) }
        let clamped = min(max(pan, -1), 1)
        // 0 … π/2 as the pan runs left … right.
        let theta = (clamped + 1) * Double.pi / 4
        return (Float(cos(theta) * 2.0.squareRoot()), Float(sin(theta) * 2.0.squareRoot()))
    }
}

// MARK: - Compressor

/// A feed-forward peak compressor with a hard knee, channel-linked.
///
/// **Linked, not per channel.** The detector is the largest absolute sample
/// across the channels and one gain is applied to all of them. Compressing
/// each channel on its own detector makes the stereo image wander whenever
/// one side is louder, which is the classic way a compressor ruins a mix.
///
/// **One compressor per composition TRACK, not per clip.** A composition
/// audio track is a sequence of clips (§7.2) and this sits on it like a
/// channel-strip insert: the settings change at each cut, the envelope
/// carries across it. Restarting the envelope per clip would make every cut
/// audible as a jump in gain reduction.
///
/// The envelope is a one-pole smoother on the gain reduction in dB, which is
/// the standard shape: `attack` is how fast the reduction closes on a level
/// that just rose, `release` how fast it opens again.
final class AudioCompressorStage {
    /// Current gain reduction in dB, always ≥ 0. Persists across buffers.
    private var reductionDB: Float = 0
    /// The peak follower's state — see `processChunk`. Also persists.
    private var detectorState: Float = 0
    private let sampleRate: Double
    /// The linked detector and the per-sample gain, sized once.
    private let detector: UnsafeMutablePointer<Float>
    private let scratch: UnsafeMutablePointer<Float>
    private let gains: UnsafeMutablePointer<Float>
    private let capacity: Int

    init(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 48000
        capacity = max(1, maxFrames)
        detector = .allocate(capacity: capacity)
        scratch = .allocate(capacity: capacity)
        gains = .allocate(capacity: capacity)
        detector.initialize(repeating: 0, count: capacity)
        scratch.initialize(repeating: 0, count: capacity)
        gains.initialize(repeating: 1, count: capacity)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("AudioCompressorStage does not support NSCoder")
    }

    deinit {
        detector.deallocate()
        scratch.deallocate()
        gains.deallocate()
    }

    /// Forgets the envelope and the follower. Called when playback restarts,
    /// so a paused-then-resumed preview does not open with the reduction the
    /// last buffer left.
    func reset() {
        reductionDB = 0
        detectorState = 0
    }

    /// A one-pole coefficient for a time constant in seconds. Zero seconds
    /// means "instantly", which is a legitimate setting (a brick-wall attack)
    /// and must not divide by zero.
    private func coefficient(_ seconds: Double) -> Float {
        guard seconds > 0 else { return 1 }
        return Float(1 - exp(-1 / (seconds * sampleRate)))
    }

    /// Compresses `frames` samples in place across `count` channels.
    ///
    /// `settings` of nil means this clip asks for no compression: the target
    /// reduction is 0 but the envelope still RELEASES toward it, so a cut from
    /// a compressed clip to an uncompressed one opens up over the last
    /// clip's release time instead of stepping.
    func process(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        frames: Int, settings: AudioCompressorSettings?
    ) {
        guard frames > 0, count > 0 else { return }
        // `maxFrames` is what `prepare` promised, not a guarantee: a buffer
        // bigger than the scratch is split rather than dropped, because
        // silently leaving audio unprocessed is the one outcome worth ruling
        // out.
        var offset = 0
        while offset < frames {
            let chunk = min(capacity, frames - offset)
            processChunk(channels, count: count, offset: offset, frames: chunk, settings: settings)
            offset += chunk
        }
    }

    private func processChunk(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        offset: Int, frames: Int, settings: AudioCompressorSettings?
    ) {
        // The linked detector: |x| of the first channel, then the running
        // maximum against every other. Vectorised — this is two passes over
        // the buffer rather than a branch per sample per channel.
        var wrote = false
        for channel in 0..<count {
            guard let data = channels[channel] else { continue }
            if !wrote {
                vDSP_vabs(data + offset, 1, detector, 1, vDSP_Length(frames))
                wrote = true
            } else {
                vDSP_vabs(data + offset, 1, scratch, 1, vDSP_Length(frames))
                vDSP_vmax(detector, 1, scratch, 1, detector, 1, vDSP_Length(frames))
            }
        }
        guard wrote else { return }

        let thresholdDB = Float(settings?.thresholdDB ?? 0)
        let ratio = Float(settings?.ratio ?? 1)
        // How much of every dB above the threshold is given back. Ratio 1
        // (or no compressor at all) makes this 0 and the stage a pure makeup
        // gain, which is exactly what 1:1 means.
        let slope = ratio > 1 ? 1 - 1 / ratio : 0
        let makeupDB = Float(settings?.makeupDB ?? 0)
        let thresholdLinear = AudioDSP.gain(fromDecibels: thresholdDB)
        let attack = coefficient(settings?.attackSeconds ?? 0)
        let release = coefficient(settings?.releaseSeconds ?? 0)
        // The detector is a PEAK FOLLOWER — it jumps to each new peak and
        // falls back at the release rate — rather than the raw |x|. A naive
        // detector reads a waveform's own zero crossings as the level
        // collapsing, so the gain is modulated at twice the signal's
        // frequency: audible as distortion on anything low, and the reason a
        // sine measured through a textbook 3:1 lands a few tenths of a dB
        // shy of where the arithmetic says it should. The floor keeps a
        // zero-release setting from turning the follower back into |x|.
        let fall = Float(exp(-1 / (max(settings?.releaseSeconds ?? 0, 0.010) * sampleRate)))

        for index in 0..<frames {
            detectorState = max(detector[index], detectorState * fall)
            let level = detectorState
            // The log is skipped entirely below the threshold, which is where
            // most samples of most material are.
            var target: Float = 0
            if slope > 0, level > thresholdLinear {
                let levelDB = 20 * log10f(max(level, AudioDSP.silenceFloor))
                target = (levelDB - thresholdDB) * slope
            }
            let coefficient = target > reductionDB ? attack : release
            reductionDB += (target - reductionDB) * coefficient
            gains[index] = AudioDSP.gain(fromDecibels: makeupDB - reductionDB)
        }

        for channel in 0..<count {
            guard let data = channels[channel] else { continue }
            vDSP_vmul(data + offset, 1, gains, 1, data + offset, 1, vDSP_Length(frames))
        }
    }
}

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

// MARK: - The chain

/// One composition audio track's effect chain: noise reduction, then the
/// compressor, then the Mix stage — the mono fold, then the pan, then the
/// fold an enclosing NEST clip asked for.
///
/// **That order is the order a channel strip has**, and each step is there
/// because of the one before it. Cleaning first means the compressor is not
/// asked to make a decision about a level the hiss is holding up — a
/// compressor in front of a noise reducer pumps the noise floor audibly.
/// Panning last means the reduction is computed on the signal as it was
/// recorded, not on a channel the pan has already leaned.
///
/// **The fold is at the head of the Mix stage, after the compressor and
/// before the pan.** After the pan it would undo it (see `AudioPanLaw`);
/// before the noise reducer it would hand both reducers identical input,
/// which invites the false optimisation of running one and copying — and a
/// stage that stopped being fed would click the moment mono came off at a
/// cut, because mono is a per-CLIP setting and the reducers are stateful.
/// Where it is, it also makes `AudioPane`'s Mix section — which holds `mono`
/// and `pan`, in that order — literally the DSP order, which that pane
/// already claims for the other three sections.
///
/// **A NEST clip's fold is the one thing that runs after the pan**, and it is
/// not an exception to the paragraph above: it belongs to a different clip.
/// It stands for a fold of the whole nest's MIX, and a mix is a sum, so
/// folding each contributor at the very end of its own chain sums to exactly
/// the same samples (`AudioClipDSP.enclosingMono` argues it). Running it at
/// the head with the clip's own would fold BEFORE the inner clip's pan and
/// leave a hard-panned clip hard-panned inside a nest the user folded.
///
/// The clip's own volume, its fades and any ducking are NOT here: `audio.rs`
/// folds those into the plan's envelope and `AVMutableAudioMixInputParameters`
/// applies them as volume ramps, which — measured — happen downstream of a
/// tap created with `kMTAudioProcessingTapCreationFlag_PreEffects`. So the
/// full order the samples actually see is
/// noise reduction → compressor → the clip's fold → pan → an enclosing nest's
/// fold → volume/fades/ducking, which puts the compressor before the fader
/// exactly as an insert should be.
final class AudioDSPChain {
    let channelCount: Int
    private let compressor: AudioCompressorStage
    /// One per channel, or nil when no clip on this track asks for noise
    /// reduction — in which case the track has no added latency at all.
    private let reducers: [AudioNoiseReductionStage]?

    /// `usesNoiseReduction` is decided for the WHOLE track when the
    /// composition is built, not per buffer: the stage adds a fixed delay, and
    /// switching it in and out at a cut would make the track jump backwards
    /// and forwards by 10 ms.
    init(channelCount: Int, sampleRate: Double, maxFrames: Int, usesNoiseReduction: Bool) {
        self.channelCount = max(0, channelCount)
        compressor = AudioCompressorStage(sampleRate: sampleRate, maxFrames: maxFrames)
        if usesNoiseReduction, self.channelCount > 0 {
            // All channels or none: a track whose left channel was filtered
            // and whose right was not would be delayed on one side, which is
            // worse than not filtering at all. `vDSP_create_fftsetup` is the
            // only thing that can fail here, and if it does the clip plays
            // and exports with its pan and compressor and without its noise
            // reduction, rather than not playing.
            let stages = (0..<self.channelCount).compactMap { _ in AudioNoiseReductionStage() }
            reducers = stages.count == self.channelCount ? stages : nil
        } else {
            reducers = nil
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("AudioDSPChain does not support NSCoder")
    }

    /// Drops every bit of carried state — the compressor's envelope, the
    /// reducers' delay lines and noise estimates. `AudioTap` calls this when
    /// the stream restarts, so a seek does not play the previous position's
    /// tail.
    func reset() {
        compressor.reset()
        reducers?.forEach { $0.reset() }
    }

    /// Runs the chain in place over one buffer.
    ///
    /// `params` is the clip under this buffer's timestamp. It changes at every
    /// cut on the track; the stages carry their state across the change, which
    /// is what a track insert does.
    func process(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, frames: Int,
        params: AudioClipDSP
    ) {
        let count = min(channels.count, channelCount)
        guard frames > 0, count > 0 else { return }

        if let reducers = reducers {
            for channel in 0..<min(count, reducers.count) {
                guard let data = channels[channel] else { continue }
                reducers[channel].process(data, frames: frames, amount: params.noiseReduction)
            }
        }

        compressor.process(channels, count: count, frames: frames, settings: params.compressor)

        // The head of the Mix stage. The branch is not entered at all for a
        // clip that does not ask for mono — not multiplied by one, not folded
        // with a weight of zero — which is what makes an untouched track's
        // samples bit-identical to the build before this landed, by
        // construction rather than by argument.
        if params.mono, count >= 2 { fold(channels, count: count, frames: frames) }

        pan(channels, count: count, frames: frames, position: params.pan)

        // The tail: the fold a nest clip ABOVE this one asked for, after
        // everything this clip does to its own channels, which is what makes
        // the sum of the folded contributors the fold of the sum.
        if params.enclosingMono, count >= 2 { fold(channels, count: count, frames: frames) }
    }

    /// The pan, in place. Its own method only so the tail fold above it is
    /// reachable: every early return here used to end `process`.
    ///
    /// Pan needs somewhere to pan TO. A mono composition track is prepared
    /// with one channel and is widened to stereo downstream of the tap, so
    /// there is nothing here to lean; the pan is silently inaudible on such a
    /// clip rather than turning into a volume change, which is what applying
    /// half a pan law to a single channel would be.
    private func pan(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        frames: Int, position: Double
    ) {
        guard count >= 2 else { return }
        let gains = AudioPanLaw.gains(position)
        guard gains.left != 1 || gains.right != 1 else { return }
        var left = gains.left
        var right = gains.right
        if let data = channels[0] { vDSP_vsmul(data, 1, &left, data, 1, vDSP_Length(frames)) }
        if let data = channels[1] { vDSP_vsmul(data, 1, &right, data, 1, vDSP_Length(frames)) }
    }

    /// Averages EVERY channel and writes the average to all of them.
    ///
    /// **Every channel, not L and R.** `prepare` is handed the COMPOSITION
    /// track's channel count, so a 5.1 source gives 6; folding only channels 0
    /// and 1 would leave four untouched and produce something that is neither
    /// mono nor the original. At two channels this is exactly (L+R)/2.
    ///
    /// Allocation-free and stateless: `count` linear passes plus `count − 1`
    /// copies over at most `maxFrames` floats, which is two orders of
    /// magnitude under one noise-reduction frame. The accumulator is the first
    /// channel that actually has a buffer, and the divisor counts only the
    /// channels that contributed — a null buffer must not quietly attenuate
    /// the rest.
    private func fold(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        frames: Int
    ) {
        var accumulator: UnsafeMutablePointer<Float>?
        var summed = 0
        for channel in 0..<count {
            guard let data = channels[channel] else { continue }
            summed += 1
            guard let into = accumulator else {
                accumulator = data
                continue
            }
            vDSP_vadd(into, 1, data, 1, into, 1, vDSP_Length(frames))
        }
        guard let into = accumulator, summed >= 2 else { return }
        var scale = 1 / Float(summed)
        vDSP_vsmul(into, 1, &scale, into, 1, vDSP_Length(frames))
        for channel in 0..<count {
            guard let data = channels[channel], data != into else { continue }
            data.update(from: into, count: frames)
        }
    }
}
