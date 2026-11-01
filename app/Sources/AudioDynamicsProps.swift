import Foundation

// The read-only mirror of a clip's gate and de-esser (format 33, spec §11 AU-43, AU-45) and
// leveller (format 37, AU-66): `GateProps`, `DeEsserProps` and `LevellerProps`. The core's `model_audio.rs` is the vocabulary and
// `audio_dynamics.rs` its bounds; snake keys arrive through `.convertFromSnakeCase`
// (`de_esser` is `deEsser`). Both thresholds are dB relative to the clip's measured loudness
// (AU-41), resolved by `AudioDynamicsLevels`, and so is the leveller's target, through its curve;
// the DSP is `AudioGateStage.swift`'s, `AudioDeEsserStage.swift`'s and `AudioLevellerStage.swift`'s.

/// The downward expander/gate (AU-43): below `thresholdDb` re the clip's
/// loudness, `ratio − 1` dB down per dB under, never more than `rangeDb`.
struct GateProps: Codable, Equatable {
    /// dB re the clip's loudness: −40…0.
    var thresholdDb: Double
    /// 1…20.
    var ratio: Double
    /// dB, 1…80.
    var rangeDb: Double
    /// Ticks: 0…60 000 (100 ms).
    var attack: Ticks
    /// Ticks: 0…300 000 (500 ms).
    var hold: Ticks
    /// Ticks: 600…1 200 000 (1 ms…2 s).
    var release: Ticks

    init(
        thresholdDb: Double = -10, ratio: Double = 4, rangeDb: Double = 20, attack: Ticks = 600,
        hold: Ticks = 30_000, release: Ticks = 60_000
    ) {
        self.thresholdDb = thresholdDb
        self.ratio = ratio
        self.rangeDb = rangeDb
        self.attack = attack
        self.hold = hold
        self.release = release
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        thresholdDb = c.lenient(.thresholdDb, -10)
        ratio = c.lenient(.ratio, 4)
        rangeDb = c.lenient(.rangeDb, 20)
        attack = c.lenient(.attack, 600)
        hold = c.lenient(.hold, 30_000)
        release = c.lenient(.release, 60_000)
    }

    /// The patch's body (`AudioPatch.dictionary`).
    var dictionary: [String: Any] {
        [
            "threshold_db": thresholdDb, "ratio": ratio, "range_db": rangeDb, "attack": attack,
            "hold": hold, "release": release,
        ]
    }
}

/// The split-band de-esser (AU-44, AU-45): the band above `frequency`
/// turned down as far as its sidechain passes `thresholdDb` re the clip's
/// loudness, never more than `rangeDb`.
struct DeEsserProps: Codable, Equatable {
    /// Hz, 2 000…12 000.
    var frequency: Double
    /// dB re the clip's loudness: −30…+20.
    var thresholdDb: Double
    /// dB, 1…24.
    var rangeDb: Double

    init(frequency: Double = 6000, thresholdDb: Double = 0, rangeDb: Double = 6) {
        self.frequency = frequency
        self.thresholdDb = thresholdDb
        self.rangeDb = rangeDb
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frequency = c.lenient(.frequency, 6000)
        thresholdDb = c.lenient(.thresholdDb, 0)
        rangeDb = c.lenient(.rangeDb, 6)
    }

    /// The patch's body (`AudioPatch.dictionary`).
    var dictionary: [String: Any] {
        ["frequency": frequency, "threshold_db": thresholdDb, "range_db": rangeDb]
    }
}

/// The leveller (AU-66): a gain curve made ahead of time from the clip's
/// loudness and speech, bringing each phrase toward `targetDb` re the clip's
/// loudness, never more than `maxUpDb` up or `maxDownDb` down, smoothed both
/// ways over `response`; pauses hold.
struct LevellerProps: Codable, Equatable {
    /// dB re the clip's loudness: −20…10.
    var targetDb: Double
    /// dB, 0…24.
    var maxUpDb: Double
    /// dB, 0…24.
    var maxDownDb: Double
    /// Ticks: 300 000…6 000 000 (0.5…10 s). Held at an action's end (AU-66 (f)).
    var response: Ticks

    init(
        targetDb: Double = 0, maxUpDb: Double = 12, maxDownDb: Double = 12,
        response: Ticks = 1_200_000
    ) {
        self.targetDb = targetDb
        self.maxUpDb = maxUpDb
        self.maxDownDb = maxDownDb
        self.response = response
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        targetDb = c.lenient(.targetDb, 0)
        maxUpDb = c.lenient(.maxUpDb, 12)
        maxDownDb = c.lenient(.maxDownDb, 12)
        response = c.lenient(.response, 1_200_000)
    }

    /// The patch's body (`AudioPatch.dictionary`).
    var dictionary: [String: Any] {
        [
            "target_db": targetDb, "max_up_db": maxUpDb, "max_down_db": maxDownDb,
            "response": response,
        ]
    }
}
