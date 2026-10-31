import Foundation

// The read-only mirror of a clip's EQ, hum notch and channel pick (format 32, spec §11 AU-31,
// AU-33, AU-34): `EqProps` and its slots, `HumProps`, `AudioChannelChoice`, and the inspector's
// three presets (`EqPreset`, AU-32). The core's `model_audio.rs` is the vocabulary; snake keys
// arrive through `.convertFromSnakeCase` (`band_1` is `band1`). The DSP is
// `AudioBiquad.swift`'s and `AudioEQStage.swift`'s.

/// Which channels of a stereo source play (AU-34). A one-channel track
/// ignores it, as it ignores pan.
enum AudioChannelChoice: String, Codable, CaseIterable {
    case both, left, right, swapped

    /// The Channels popup's words.
    var title: String {
        switch self {
        case .both: return "Both"
        case .left: return "Left Only"
        case .right: return "Right Only"
        case .swapped: return "Swap Left and Right"
        }
    }
}

/// A Butterworth pass: its corner in Hz and its slope, 12 or 24 dB/octave.
struct EqPassProps: Codable, Equatable {
    var frequency: Double
    var slope: Int

    init(frequency: Double, slope: Int = 12) {
        self.frequency = frequency
        self.slope = slope
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frequency = c.lenient(.frequency, 1000)
        slope = c.lenient(.slope, 12)
    }

    static let highPass = EqPassProps(frequency: 80)
    static let lowPass = EqPassProps(frequency: 12_000)

    var dictionary: [String: Any] { ["frequency": frequency, "slope": slope] }
}

/// An RBJ shelf (S = 1): its corner in Hz and its gain in dB.
struct EqShelfProps: Codable, Equatable {
    var frequency: Double
    var gainDb: Double

    init(frequency: Double, gainDb: Double = 0) {
        self.frequency = frequency
        self.gainDb = gainDb
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frequency = c.lenient(.frequency, 1000)
        gainDb = c.lenient(.gainDb, 0)
    }

    static let lowShelf = EqShelfProps(frequency: 100)
    static let highShelf = EqShelfProps(frequency: 8000)

    var dictionary: [String: Any] { ["frequency": frequency, "gain_db": gainDb] }
}

/// An RBJ peaking bell: its centre in Hz, its gain in dB and its Q.
struct EqBandProps: Codable, Equatable {
    var frequency: Double
    var gainDb: Double
    var q: Double

    init(frequency: Double = 1000, gainDb: Double = 0, q: Double = 1) {
        self.frequency = frequency
        self.gainDb = gainDb
        self.q = q
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frequency = c.lenient(.frequency, 1000)
        gainDb = c.lenient(.gainDb, 0)
        q = c.lenient(.q, 1)
    }

    var dictionary: [String: Any] { ["frequency": frequency, "gain_db": gainDb, "q": q] }
}

/// The clip's EQ (AU-31): seven named slots in signal order, nil when off,
/// and `bypass`, which keeps the settings and silences them.
struct EqProps: Codable, Equatable {
    var highPass: EqPassProps?
    var lowShelf: EqShelfProps?
    var band1: EqBandProps?
    var band2: EqBandProps?
    var band3: EqBandProps?
    var highShelf: EqShelfProps?
    var lowPass: EqPassProps?
    var bypass: Bool

    init(
        highPass: EqPassProps? = nil, lowShelf: EqShelfProps? = nil, band1: EqBandProps? = nil,
        band2: EqBandProps? = nil, band3: EqBandProps? = nil, highShelf: EqShelfProps? = nil,
        lowPass: EqPassProps? = nil, bypass: Bool = false
    ) {
        self.highPass = highPass
        self.lowShelf = lowShelf
        self.band1 = band1
        self.band2 = band2
        self.band3 = band3
        self.highShelf = highShelf
        self.lowPass = lowPass
        self.bypass = bypass
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        highPass = c.lenient(.highPass)
        lowShelf = c.lenient(.lowShelf)
        band1 = c.lenient(.band1)
        band2 = c.lenient(.band2)
        band3 = c.lenient(.band3)
        highShelf = c.lenient(.highShelf)
        lowPass = c.lenient(.lowPass)
        bypass = c.lenient(.bypass, false)
    }

    /// How many slots are on.
    var activeCount: Int {
        [highPass != nil, lowShelf != nil, band1 != nil, band2 != nil, band3 != nil,
         highShelf != nil, lowPass != nil].filter { $0 }.count
    }

    /// The patch's body. EVERY slot key is written, `NSNull` for an off slot,
    /// because a patch merges per key (`patch.rs`): a slot left out would
    /// keep its stored value rather than turn off.
    var dictionary: [String: Any] {
        func slot(_ value: [String: Any]?) -> Any { value ?? NSNull() }
        return [
            "high_pass": slot(highPass?.dictionary), "low_shelf": slot(lowShelf?.dictionary),
            "band_1": slot(band1?.dictionary), "band_2": slot(band2?.dictionary),
            "band_3": slot(band3?.dictionary), "high_shelf": slot(highShelf?.dictionary),
            "low_pass": slot(lowPass?.dictionary), "bypass": bypass,
        ]
    }
}

/// The hum notch comb (AU-33): mains 50 or 60 Hz, each notch's depth in
/// dB, and how many harmonics it takes.
struct HumProps: Codable, Equatable {
    var frequency: Int
    var depthDb: Double
    var harmonics: Int

    init(frequency: Int = 60, depthDb: Double = 30, harmonics: Int = 4) {
        self.frequency = frequency
        self.depthDb = depthDb
        self.harmonics = harmonics
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frequency = c.lenient(.frequency, 60)
        depthDb = c.lenient(.depthDb, 30)
        harmonics = c.lenient(.harmonics, 4)
    }

    var dictionary: [String: Any] {
        ["frequency": frequency, "depth_db": depthDb, "harmonics": harmonics]
    }
}

/// The EQ section's three voice presets (AU-32). Each writes only its own
/// slot and `bypass: false`, so they combine.
enum EqPreset: CaseIterable {
    case rumbleCut, deMud, presence

    var title: String {
        switch self {
        case .rumbleCut: return "Rumble Cut"
        case .deMud: return "De-mud"
        case .presence: return "Presence"
        }
    }

    func applied(to eq: EqProps) -> EqProps {
        var next = eq
        next.bypass = false
        switch self {
        case .rumbleCut: next.highPass = EqPassProps(frequency: 80, slope: 24)
        case .deMud: next.band1 = EqBandProps(frequency: 300, gainDb: -3, q: 1)
        case .presence: next.band3 = EqBandProps(frequency: 4000, gainDb: 3, q: 1)
        }
        return next
    }
}
