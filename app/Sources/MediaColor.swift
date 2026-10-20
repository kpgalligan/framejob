import Foundation

// MARK: - Camera log (spec §11 GR-16)

/// A maker's published log curve, as `media.color.log` spells it. Apple
/// Log 2 is Apple Log's curve with Apple Wide Gamut (GR-16's append).
enum LogCurve: String, Codable, CaseIterable {
    case appleLog = "apple_log", slog3, vlog, appleLog2 = "apple_log2"

    /// The gamuts the curve pairs with, its default first — the core's
    /// `LogCurve::gamuts`, which refuses any other.
    var gamuts: [CameraGamut] {
        switch self {
        case .appleLog: return [.bt2020]
        case .appleLog2: return [.appleWideGamut]
        case .slog3: return [.sGamut3Cine, .sGamut3]
        case .vlog: return [.vGamut]
        }
    }

    var displayName: String {
        switch self {
        case .appleLog: return "Apple Log"
        case .appleLog2: return "Apple Log 2"
        case .slog3: return "S-Log3"
        case .vlog: return "V-Log"
        }
    }
}

/// The camera gamut a log curve's signal is in, as `media.color.gamut`
/// spells it.
enum CameraGamut: String, Codable, CaseIterable {
    case bt2020, sGamut3Cine = "s_gamut3_cine", sGamut3 = "s_gamut3", vGamut = "v_gamut"
    case appleWideGamut = "apple_wide_gamut"

    var displayName: String {
        switch self {
        case .bt2020: return "BT.2020"
        case .sGamut3Cine: return "S-Gamut3.Cine"
        case .sGamut3: return "S-Gamut3"
        case .vGamut: return "V-Gamut"
        case .appleWideGamut: return "Apple Wide Gamut"
        }
    }
}

// MARK: - The PQ peak (spec §11 HD-12)

/// Which HDR10 field gave a PQ file's peak, as `media.color.pq.from` spells
/// it: CTA-861.3's MaxCLL, or SMPTE ST 2086's mastering maximum.
enum PeakSource: String, Codable, CaseIterable {
    case maxCLL = "max_cll", masteringDisplay = "mastering_display"
}

/// A PQ file's HDR10 peak, `media.color.pq`: `file`, what import read in
/// whole cd/m², with `from` naming its field; `peak`, the person's override.
/// The core wrote it, so it decodes leniently (`init(from:)` below).
struct PQColor: Codable, Equatable {
    var file: UInt32?
    var from: PeakSource?
    var peak: UInt32?

    /// The peak step 0 uses: the override, else the file's; nil means
    /// `InputConversions.pqWhite`.
    var effectivePeak: UInt32? { peak ?? file }

    /// The stored shape, each key only when set.
    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let file = file { d["file"] = file }
        if let from = from { d["from"] = from.rawValue }
        if let peak = peak { d["peak"] = peak }
        return d
    }
}

extension PQColor {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(file: c.lenient(.file), from: c.lenient(.from), peak: c.lenient(.peak))
    }
}

// MARK: - The media's colour

/// A video media's Camera Log: a built-in curve and its gamut, or a `lut`
/// media converting the file instead; `detected` when import read it from
/// the file's label; `pq` a PQ file's peak (spec §11 HD-12). Also a recipe
/// layer's and a plan segment's `input`, which carry no `detected` and no
/// `pq` but a flat `peak` (the effective one) — so the decoder is written
/// out: a synthesized one would throw on the absent key, and `lenient` would
/// read that as no setting at all.
struct MediaColor: Codable, Equatable {
    var log: LogCurve?
    var gamut: CameraGamut?
    var lut: UInt32?
    var detected: Bool
    /// The stored peak record; nil on every media that is not a PQ file.
    var pq: PQColor?
    /// An `input`'s effective PQ peak; never stored.
    var peak: UInt32?

    init(log: LogCurve? = nil, gamut: CameraGamut? = nil, lut: UInt32? = nil,
         detected: Bool = false, pq: PQColor? = nil, peak: UInt32? = nil) {
        self.log = log
        self.gamut = gamut
        self.lut = lut
        self.detected = detected
        self.pq = pq
        self.peak = peak
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        log = c.lenient(.log)
        gamut = c.lenient(.gamut)
        lut = c.lenient(.lut)
        detected = c.lenient(.detected, false)
        pq = c.lenient(.pq)
        peak = c.lenient(.peak)
    }

    /// The gamut step 0 converts from: the stored one, else the curve's
    /// first (the core stores it so; a hand-written file may not).
    var effectiveGamut: CameraGamut? {
        gamut ?? log?.gamuts.first
    }

    /// `set_media_color`'s `color`: `log`, `gamut`, `lut` and the override
    /// `pq.peak` as `peak` (spec §11 HD-12), never `detected` or the file's
    /// reading, which only import writes.
    var opDictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let log = log { d["log"] = log.rawValue }
        if let gamut = gamut { d["gamut"] = gamut.rawValue }
        if let lut = lut { d["lut"] = lut }
        if let peak = pq?.peak { d["peak"] = peak }
        return d
    }

    /// An `add_media` descriptor's `color`: `log`, `gamut`, `lut`,
    /// `detected` when true and `pq` whole — never a flat `peak`.
    var descriptorDictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let log = log { d["log"] = log.rawValue }
        if let gamut = gamut { d["gamut"] = gamut.rawValue }
        if let lut = lut { d["lut"] = lut }
        if detected { d["detected"] = true }
        if let pq = pq { d["pq"] = pq.dictionary }
        return d
    }
}
