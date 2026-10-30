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

    init(
        volume: Double = 1, muted: Bool = false, fadeIn: Ticks = 0, fadeOut: Ticks = 0,
        duck: DuckProps? = nil, mono: Bool = false, keepPitch: Bool = true,
        pan: Double = 0, compressor: CompressorProps? = nil, noiseReduction: Double = 0,
        fadeInShape: FadeShape = .linear, fadeOutShape: FadeShape = .linear
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
    }

    /// Volume in dB for the Audio tab's read-out; -inf shows as silence.
    var decibels: Double { volume <= 0 ? -.infinity : 20 * log10(volume) }
}
