import Foundation

// The clip's audio property group — `DuckProps`, `CompressorProps`, `AudioProps`: a pure move
// out of `ProjectSnapshot.swift` (road map "audio" AP11's toll), which keeps the rest of the
// project's read-only mirror and its decoding rules.

/// What a duck follows (format 29, spec §11 AU-110): the ducking clip's
/// whole extent, or the speech spans saved on its media (`media.speech`).
enum DuckMode: String, Codable, CaseIterable {
    case extent, speech
}

/// A fade's or a crossfade's curve (format 29, spec §11 AU-114, AU-115). The
/// core samples it; this side only names it.
enum FadeShape: String, Codable, CaseIterable {
    case linear
    case sCurve = "s_curve"
    case plus3Db = "plus_3db"
    case minus3Db = "minus_3db"

    /// The popups' words.
    var title: String {
        switch self {
        case .linear: return "Linear"
        case .sCurve: return "S-Curve"
        case .plus3Db: return "+3 dB"
        case .minus3Db: return "−3 dB"
        }
    }
}

/// Ducking: "lower other audio to `level` while this clip plays" (§4.3).
/// By clip extent, or — `mode` speech (format 29, spec §11 AU-110) — over
/// its media's speech spans widened by `preRoll` and `hold`; the core folds
/// it into every other track's envelope either way.
struct DuckProps: Codable, Equatable {
    var level: Double
    var attack: Ticks
    var release: Ticks
    var mode: DuckMode
    var preRoll: Ticks
    var hold: Ticks

    /// `pre_roll`'s and `hold`'s default, 0.5 s — the core's `DUCK_SPEECH_PAD`.
    static let speechPad: Ticks = 300_000

    init(
        level: Double = 0.2, attack: Ticks = 300_000, release: Ticks = 600_000,
        mode: DuckMode = .extent, preRoll: Ticks = speechPad, hold: Ticks = speechPad
    ) {
        self.level = level
        self.attack = attack
        self.release = release
        self.mode = mode
        self.preRoll = preRoll
        self.hold = hold
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = c.lenient(.level, 0.2)
        attack = c.lenient(.attack, 300_000)
        release = c.lenient(.release, 600_000)
        mode = c.lenient(.mode, DuckMode.extent)
        preRoll = c.lenient(.preRoll, Self.speechPad)
        hold = c.lenient(.hold, Self.speechPad)
    }
}

/// "Smooth volume levels" (§4.3): a downward compressor over the clip's own
/// samples. Unlike ducking, which the core resolves into ramps on other
/// clips' envelopes, this one depends on the samples — so the model carries
/// the parameters and the DSP happens on this side.
struct CompressorProps: Codable, Equatable {
    /// dBFS above which gain reduction starts.
    var thresholdDb: Double
    /// N:1 — 1 is no compression, 20 is effectively a limiter.
    var ratio: Double
    var attack: Ticks
    var release: Ticks
    /// dB applied after compression, to win back what it took.
    var makeupDb: Double

    init(
        thresholdDb: Double = -18, ratio: Double = 3, attack: Ticks = 6000,
        release: Ticks = 120_000, makeupDb: Double = 0
    ) {
        self.thresholdDb = thresholdDb
        self.ratio = ratio
        self.attack = attack
        self.release = release
        self.makeupDb = makeupDb
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        thresholdDb = c.lenient(.thresholdDb, -18)
        ratio = c.lenient(.ratio, 3)
        attack = c.lenient(.attack, 6000)
        release = c.lenient(.release, 120_000)
        makeupDb = c.lenient(.makeupDb, 0)
    }
}

/// The clip's true-peak limiter (format 30, spec §11 AU-20, AU-21): a
/// ceiling in dBTP that holds after the clip's fader at its base volume
/// (AU-22), and the time its gain takes to recover. Base-only, like the
/// compressor.
struct LimiterProps: Codable, Equatable {
    /// dBTP, post-fader: −24…0.
    var ceilingDb: Double = -1
    /// Ticks: 600…600 000 (1 ms…1 s).
    var release: Ticks = 60_000

    init(ceilingDb: Double = -1, release: Ticks = 60_000) {
        self.ceilingDb = ceilingDb
        self.release = release
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ceilingDb = c.lenient(.ceilingDb, -1)
        release = c.lenient(.release, 60_000)
    }

    /// The patch's body (`AudioPatch.dictionary`).
    var dictionary: [String: Any] { ["ceiling_db": ceilingDb, "release": release] }
}

/// The sample half of a clip. `volume` may exceed 1, up to 32 (§5.2, §11 AU-1).
struct AudioProps: Codable, Equatable {
    let volume: Double
    let muted: Bool
    let fadeIn: Ticks
    let fadeOut: Ticks
    let duck: DuckProps?
    let mono: Bool
    /// Preserve pitch through a speed change (`scaleTimeRange` + a
    /// time-pitch algorithm; the plan carries it per segment).
    let keepPitch: Bool
    /// -1 hard left, 0 centred, +1 hard right (M3).
    let pan: Double
    let compressor: CompressorProps?
    /// How much background noise to remove: 0 is off (M3).
    let noiseReduction: Double
    /// The fades' curves (format 29, spec §11 AU-114).
    let fadeInShape: FadeShape
    let fadeOutShape: FadeShape
    /// The true-peak limiter, nil when off (AU-21).
    let limiter: LimiterProps?
    /// How much of the isolated voice replaces the clip's sound, 0 off … 1
    /// (format 31, spec §11 AU-50); rendered offline (`IsolationCache`).
    let isolation: Double
    /// The EQ and the hum notch, nil when off, and the channel pick
    /// (format 32, AU-31, AU-33, AU-34; `AudioEQProps.swift`).
    let eq: EqProps?
    let hum: HumProps?
    let channels: AudioChannelChoice
    /// The gate and the de-esser, nil when off (format 33, AU-43, AU-45;
    /// `AudioDynamicsProps.swift`).
    let gate: GateProps?
    let deEsser: DeEsserProps?
    /// The voice effect, nil when off (format 34, spec §11 AU-140;
    /// `VoiceProps.swift`); rendered offline (`VoiceCache`).
    let voice: VoiceProps?

    init(
        volume: Double = 1, muted: Bool = false, fadeIn: Ticks = 0, fadeOut: Ticks = 0,
        duck: DuckProps? = nil, mono: Bool = false, keepPitch: Bool = true,
        pan: Double = 0, compressor: CompressorProps? = nil, noiseReduction: Double = 0,
        fadeInShape: FadeShape = .linear, fadeOutShape: FadeShape = .linear,
        limiter: LimiterProps? = nil, isolation: Double = 0, eq: EqProps? = nil,
        hum: HumProps? = nil, channels: AudioChannelChoice = .both, gate: GateProps? = nil,
        deEsser: DeEsserProps? = nil, voice: VoiceProps? = nil
    ) {
        self.volume = volume
        self.muted = muted
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.duck = duck
        self.mono = mono
        self.keepPitch = keepPitch
        self.pan = pan
        self.compressor = compressor
        self.noiseReduction = noiseReduction
        self.fadeInShape = fadeInShape
        self.fadeOutShape = fadeOutShape
        self.limiter = limiter
        self.isolation = isolation
        self.eq = eq
        self.hum = hum
        self.channels = channels
        self.gate = gate
        self.deEsser = deEsser
        self.voice = voice
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volume = c.lenient(.volume, 1)
        muted = c.lenient(.muted, false)
        fadeIn = c.lenient(.fadeIn, 0)
        fadeOut = c.lenient(.fadeOut, 0)
        duck = c.lenient(.duck)
        mono = c.lenient(.mono, false)
        keepPitch = c.lenient(.keepPitch, true)
        pan = c.lenient(.pan, 0)
        compressor = c.lenient(.compressor)
        noiseReduction = c.lenient(.noiseReduction, 0)
        fadeInShape = c.lenient(.fadeInShape, FadeShape.linear)
        fadeOutShape = c.lenient(.fadeOutShape, FadeShape.linear)
        limiter = c.lenient(.limiter)
        isolation = c.lenient(.isolation, 0)
        eq = c.lenient(.eq)
        hum = c.lenient(.hum)
        channels = c.lenient(.channels, AudioChannelChoice.both)
        gate = c.lenient(.gate)
        deEsser = c.lenient(.deEsser)
        voice = c.lenient(.voice)
    }

    /// Volume in dB for the Audio tab's read-out; -inf shows as silence.
    var decibels: Double { volume <= 0 ? -.infinity : 20 * log10(volume) }
}
