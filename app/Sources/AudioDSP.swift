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

/// The clip limiter's settings in the units the stage works in (spec §11
/// AU-22): its ceiling BEFORE the fader, since the fader is downstream of
/// the tap.
struct AudioLimiterSettings: Equatable {
    /// Linear, pre-fader: `10^(ceilingDb/20) / volume` for the clip's base
    /// volume; +∞ at volume 0, where nothing reaches the ceiling.
    let ceiling: Float
    /// Seconds for the gain to recover.
    let releaseSeconds: Double

    init(ceiling: Float, releaseSeconds: Double) {
        self.ceiling = ceiling.isNaN ? .infinity : ceiling
        self.releaseSeconds = releaseSeconds.isFinite ? Swift.max(releaseSeconds, 0) : 0.1
    }

    /// The settings a clip's limiter and base volume ask for. A hand-edited
    /// value outside the model's ranges is held to them (`clamp_audio`'s).
    init(ceilingDb: Double, volume: Double, releaseSeconds: Double) {
        let db = ceilingDb.isFinite ? Swift.min(Swift.max(ceilingDb, -24), 0) : -1
        let linear = pow(10, db / 20)
        let ceiling = volume.isFinite && volume > 0 ? Float(linear / volume) : Float.infinity
        self.init(ceiling: ceiling, releaseSeconds: releaseSeconds)
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
    /// The clip's limiter, last in the chain (AU-20); nil when it has none.
    var limiter: AudioLimiterSettings?

    init(
        pan: Double = 0, compressor: AudioCompressorSettings? = nil, noiseReduction: Double = 0,
        mono: Bool = false, enclosingMono: Bool = false, limiter: AudioLimiterSettings? = nil
    ) {
        self.pan = pan.isFinite ? Swift.min(Swift.max(pan, -1), 1) : 0
        self.compressor = compressor
        self.noiseReduction =
            noiseReduction.isFinite ? Swift.min(Swift.max(noiseReduction, 0), 1) : 0
        // No clamping: a bool has no range.
        self.mono = mono
        self.enclosingMono = enclosingMono
        self.limiter = limiter
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
            && limiter == nil
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

// MARK: - The chain

/// One composition audio track's effect chain: noise reduction, then the
/// compressor, then the Mix stage — the mono fold, then the pan, then the
/// fold an enclosing NEST clip asked for — then the limiter (spec §11 AU-3,
/// AU-20).
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
/// fold → limiter → volume/fades/ducking, which puts the compressor before the
/// fader exactly as an insert should be. The limiter is told the fader's base
/// gain instead (`AudioLimiterSettings`, AU-22).
final class AudioDSPChain {
    let channelCount: Int
    private let compressor: AudioCompressorStage
    /// One per channel, or nil when no clip on this track asks for noise
    /// reduction — in which case the track has no added latency at all.
    private let reducers: [AudioNoiseReductionStage]?
    /// Nil when no clip on this track has a limiter — no added latency.
    private let limiter: AudioLimiterStage?

    /// `usesNoiseReduction` and `usesLimiter` are decided for the WHOLE track
    /// when the composition is built, not per buffer: each stage adds a fixed
    /// delay, and switching one in and out at a cut would make the track jump
    /// backwards and forwards (SY-25, AU-23).
    init(
        channelCount: Int, sampleRate: Double, maxFrames: Int, usesNoiseReduction: Bool,
        usesLimiter: Bool = false
    ) {
        self.channelCount = max(0, channelCount)
        compressor = AudioCompressorStage(sampleRate: sampleRate, maxFrames: maxFrames)
        limiter = usesLimiter && self.channelCount > 0
            ? AudioLimiterStage(
                channelCount: self.channelCount, sampleRate: sampleRate, maxFrames: maxFrames)
            : nil
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
        limiter?.reset()
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

        // Last, for the whole track once any clip on it asks (AU-23): a
        // clip without a limiter passes through it as a delay.
        limiter?.process(channels, count: count, frames: frames, settings: params.limiter)
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
