import AVFoundation
import AudioToolbox

/// What a voice render is made of (spec §11 AU-141): the kind, the amount and
/// the semitones it shifts by — 0 for every kind that does not read `pitch`,
/// so a stored pitch on such a kind changes neither the chain nor the cache
/// name.
struct VoiceSettings: Hashable {
    let kind: VoiceKind
    let amount: Double
    let semitones: Double
}

/// The AU-141 table: each voice kind as a FIXED chain of Apple units —
/// TimePitch → EQ → Distortion → Delay → Reverb — scaled by the amount `a`,
/// which scales every gain, wet mix and shift, and moves every band edge
/// geometrically from where it does nothing, `geo(x0, x1) = x0·(x1/x0)^a`.
/// Every number here is Frame Job's own (the Concat rule).
///
/// A chain is described first as `Stage` values (pure, so inertness and the
/// probe read it without building a unit), then built by `units(for:)`:
/// a preset through `auAudioUnit.currentPreset` and only `wetDryMix` over it;
/// every other unit with every parameter set and then clamped to the range
/// its parameter tree publishes (AU-142).
enum VoiceChain {
    /// Part of the cache key (AU-144): bump it whenever this table, the
    /// makeup or `VoiceRenderer`'s contract changes what is written.
    static let version = 1

    /// One EQ band: its filter, its edge or centre in Hz, its width in
    /// octaves (a parametric's) and its gain in dB (a shelf's or a bell's).
    struct Band: Equatable {
        let type: AVAudioUnitEQFilterType
        let frequency: Float
        let bandwidth: Float
        let gain: Float
    }

    enum Distortion: Equatable {
        case preset(AVAudioUnitDistortionPreset)
        /// The ring modulator, set parameter by parameter (no preset makes a
        /// robot, E0).
        case robot
    }

    enum Stage: Equatable {
        case timePitch(cents: Float)
        case eq([Band])
        case distortion(Distortion, wet: Float)
        case delay(seconds: Double, feedback: Float, lowPass: Float, wet: Float)
        case reverb(AVAudioUnitReverbPreset, wet: Float)
    }

    /// The model's voice as the chain reads it: the amount clamped to 0…1
    /// and the semitones to −12…12, 0 unless the kind reads `pitch`.
    static func settings(_ voice: VoiceProps) -> VoiceSettings {
        let amount = voice.amount.isFinite ? min(max(voice.amount, 0), 1) : 1
        let semitones = voice.kind.usesPitch && voice.semitones.isFinite
            ? min(max(voice.semitones, -12), 12) : 0
        return VoiceSettings(kind: voice.kind, amount: amount, semitones: semitones)
    }

    /// `x0·(x1/x0)^a`: x0 at a = 0, x1 at a = 1.
    static func geo(_ x0: Double, _ x1: Double, _ a: Double) -> Float {
        Float(x0 * pow(x1 / x0, a))
    }

    /// The chain, in unit order. Empty for an amount of 0. TimePitch is left
    /// out when its cents round to 0, and no stage is put in at wet 0.
    static func stages(for s: VoiceSettings) -> [Stage] {
        let a = s.amount
        guard a > 0 else { return [] }
        let fa = Float(a)
        func band(_ type: AVAudioUnitEQFilterType, _ hz: Float, gain: Float = 0, octaves: Float = 1)
            -> Band
        {
            Band(type: type, frequency: hz, bandwidth: octaves, gain: gain)
        }
        var stages: [Stage] = []
        if s.kind.usesPitch {
            let cents = Float(100 * s.semitones * a)
            if cents.rounded() != 0 { stages.append(.timePitch(cents: cents)) }
        }
        switch s.kind {
        case .pitch:
            break
        case .high:
            stages.append(.eq([
                band(.highPass, geo(20, 150, a)), band(.highShelf, 4_000, gain: 3 * fa),
            ]))
        case .deep:
            stages.append(.eq([
                band(.lowShelf, 150, gain: 4 * fa), band(.highShelf, 5_000, gain: -3 * fa),
            ]))
        case .robot:
            stages.append(.distortion(.robot, wet: 100 * fa))
            stages.append(.delay(seconds: 0.008, feedback: 50, lowPass: 15_000, wet: 30 * fa))
        case .bass:
            stages.append(.eq([band(.lowShelf, 200, gain: 10 * fa)]))
        case .treble:
            stages.append(.eq([band(.highShelf, 3_000, gain: 10 * fa)]))
        case .bright:
            stages.append(.eq([
                band(.parametric, 3_000, gain: 4 * fa), band(.highShelf, 8_000, gain: 6 * fa),
            ]))
        case .telephone:
            let low = geo(20, 300, a)
            let high = geo(20_000, 3_400, a)
            stages.append(.eq([
                band(.highPass, low), band(.highPass, low), band(.lowPass, high),
                band(.lowPass, high),
            ]))
        case .radio:
            let low = geo(20, 400, a)
            let high = geo(20_000, 4_500, a)
            stages.append(.eq([
                band(.highPass, low), band(.highPass, low), band(.lowPass, high),
                band(.lowPass, high),
            ]))
            stages.append(.distortion(.preset(.speechRadioTower), wet: 40 * fa))
        case .lofi:
            stages.append(.eq([band(.highPass, geo(20, 150, a)), band(.lowPass, geo(20_000, 6_000, a))]))
            stages.append(.distortion(.preset(.multiDecimated2), wet: 100 * fa))
        case .distorted:
            stages.append(.distortion(.preset(.multiDistortedCubed), wet: 100 * fa))
        case .echo:
            stages.append(.delay(seconds: 0.25, feedback: 40, lowPass: 6_000, wet: 50 * fa))
        case .room:
            stages.append(.reverb(.mediumRoom, wet: 35 * fa))
        case .hall:
            stages.append(.reverb(.largeHall, wet: 40 * fa))
        case .plate:
            stages.append(.reverb(.plate, wet: 35 * fa))
        case .cathedral:
            stages.append(.reverb(.cathedral, wet: 45 * fa))
        }
        return stages.filter {
            switch $0 {
            case .distortion(_, let wet), .delay(_, _, _, let wet), .reverb(_, let wet):
                return wet > 0
            case .timePitch, .eq:
                return true
            }
        }
    }

    /// An inert voice renders nothing and plays dry: an amount of 0, or an
    /// empty chain (the kind `pitch` at 0 cents).
    static func isInert(_ s: VoiceSettings) -> Bool {
        s.amount <= 0 || stages(for: s).isEmpty
    }

    /// The kind's makeup at a = 1, in dB (AU-141): the dry recording's gated
    /// loudness less the render's, measured on `samples/Rode-usb-mic.m4a` by
    /// `voice_proof.py --measure` (the kind `pitch` at +7, the others at their
    /// own pitch), both read as an export at ×4 reads them: the gate makes
    /// the loudness of a recording this quiet (−44.7 LUFS) non-linear in its
    /// level. Applied as `10^(m·a/20)`.
    static func makeupDb(_ kind: VoiceKind) -> Double {
        switch kind {
        case .pitch: return 2.01
        case .high: return 1.67
        case .deep: return 1.12
        case .robot: return 8.70
        case .bass: return -3.88
        case .treble: return -1.67
        case .bright: return -0.63
        case .telephone: return 2.64
        case .radio: return -2.95
        case .lofi: return -3.08
        case .distorted: return 8.89
        case .echo: return 0.34
        case .room: return 1.47
        case .hall: return 1.56
        case .plate: return 1.20
        case .cathedral: return 2.89
        }
    }

    /// The linear makeup gain for `s`.
    static func makeup(_ s: VoiceSettings) -> Float {
        Float(pow(10, makeupDb(s.kind) * s.amount / 20))
    }

    enum ChainError: LocalizedError, Equatable {
        case parameter(String)

        var errorDescription: String? {
            switch self {
            case .parameter(let why): return why
            }
        }
    }

    /// Fresh, configured units in chain order, not yet attached.
    static func units(for s: VoiceSettings) throws -> [AVAudioNode] {
        try stages(for: s).map { stage -> AVAudioNode in
            switch stage {
            case .timePitch(let cents):
                let unit = AVAudioUnitTimePitch()
                unit.rate = 1
                unit.pitch = cents
                unit.overlap = 8
                clampTree(unit)
                return unit
            case .eq(let bands):
                let unit = AVAudioUnitEQ(numberOfBands: bands.count)
                unit.globalGain = 0
                for (band, setting) in zip(unit.bands, bands) {
                    band.filterType = setting.type
                    band.frequency = setting.frequency
                    band.bandwidth = setting.bandwidth
                    band.gain = setting.gain
                    band.bypass = false
                }
                clampTree(unit)
                return unit
            case .distortion(.preset(let preset), let wet):
                let unit = AVAudioUnitDistortion()
                try setPreset(unit, number: preset.rawValue)
                unit.wetDryMix = wet
                return unit
            case .distortion(.robot, let wet):
                let unit = AVAudioUnitDistortion()
                try robot(unit, wet: wet)
                return unit
            case .delay(let seconds, let feedback, let lowPass, let wet):
                let unit = AVAudioUnitDelay()
                unit.delayTime = seconds
                unit.feedback = feedback
                unit.lowPassCutoff = lowPass
                unit.wetDryMix = wet
                clampTree(unit)
                return unit
            case .reverb(let preset, let wet):
                let unit = AVAudioUnitReverb()
                try setPreset(unit, number: preset.rawValue)
                unit.wetDryMix = wet
                return unit
            }
        }
    }

    /// A factory preset by `auAudioUnit.currentPreset` — never
    /// `loadFactoryPreset`, which before `start()` is ignored and after it
    /// lands about 43 ms into the render (E0's `fx_presets`).
    private static func setPreset(_ unit: AVAudioUnit, number: Int) throws {
        guard let preset = unit.auAudioUnit.factoryPresets?.first(where: { $0.number == number })
        else {
            throw ChainError.parameter("\(unit.name) has no factory preset \(number)")
        }
        unit.auAudioUnit.currentPreset = preset
    }

    /// Every parameter the unit's tree publishes, clamped to its range.
    private static func clampTree(_ unit: AVAudioUnit) {
        for parameter in unit.auAudioUnit.parameterTree?.allParameters ?? [] {
            let value = min(max(parameter.value, parameter.minValue), parameter.maxValue)
            if value != parameter.value { parameter.value = value }
        }
    }

    /// The robot: AUDistortion's sixteen parameters, every one set by address
    /// and clamped to its published range — a 60 Hz ring modulator on both
    /// oscillators at balance 50 and full mix, the delay, decimation and
    /// polynomial stages mixed out, a linear term of 1, the soft clip at
    /// −6 dB and the final mix at `wet`.
    private static func robot(_ unit: AVAudioUnitDistortion, wet: Float) throws {
        let values: [(AUParameterAddress, Float)] = [
            (AUParameterAddress(kDistortionParam_Delay), 0.1),
            (AUParameterAddress(kDistortionParam_Decay), 1),
            (AUParameterAddress(kDistortionParam_DelayMix), 0),
            (AUParameterAddress(kDistortionParam_Decimation), 0),
            (AUParameterAddress(kDistortionParam_Rounding), 0),
            (AUParameterAddress(kDistortionParam_DecimationMix), 0),
            (AUParameterAddress(kDistortionParam_LinearTerm), 1),
            (AUParameterAddress(kDistortionParam_SquaredTerm), 0),
            (AUParameterAddress(kDistortionParam_CubicTerm), 0),
            (AUParameterAddress(kDistortionParam_PolynomialMix), 0),
            (AUParameterAddress(kDistortionParam_RingModFreq1), 60),
            (AUParameterAddress(kDistortionParam_RingModFreq2), 60),
            (AUParameterAddress(kDistortionParam_RingModBalance), 50),
            (AUParameterAddress(kDistortionParam_RingModMix), 100),
            (AUParameterAddress(kDistortionParam_SoftClipGain), -6),
            (AUParameterAddress(kDistortionParam_FinalMix), wet),
        ]
        guard let tree = unit.auAudioUnit.parameterTree else {
            throw ChainError.parameter("the distortion unit publishes no parameters")
        }
        for (address, value) in values {
            guard let parameter = tree.parameter(withAddress: address) else {
                throw ChainError.parameter("the distortion unit has no parameter \(address)")
            }
            parameter.value = min(max(value, parameter.minValue), parameter.maxValue)
        }
    }
}
