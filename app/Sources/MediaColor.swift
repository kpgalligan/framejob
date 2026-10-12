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

/// A video media's Camera Log: a built-in curve and its gamut, or a `lut`
/// media converting the file instead; `detected` when import read it from
/// the file's label. Also a recipe layer's and a plan segment's `input`,
/// which carry no `detected` — so the decoder is written out: a synthesized
/// one would throw on the absent key, and `lenient` would read that as no
/// setting at all.
struct MediaColor: Codable, Equatable {
    var log: LogCurve?
    var gamut: CameraGamut?
    var lut: UInt32?
    var detected: Bool

    init(log: LogCurve? = nil, gamut: CameraGamut? = nil, lut: UInt32? = nil,
         detected: Bool = false) {
        self.log = log
        self.gamut = gamut
        self.lut = lut
        self.detected = detected
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        log = c.lenient(.log)
        gamut = c.lenient(.gamut)
        lut = c.lenient(.lut)
        detected = c.lenient(.detected, false)
    }

    /// The gamut step 0 converts from: the stored one, else the curve's
    /// first (the core stores it so; a hand-written file may not).
    var effectiveGamut: CameraGamut? {
        gamut ?? log?.gamuts.first
    }

    /// `set_media_color`'s `color`: `log`, `gamut` and `lut`, never
    /// `detected`, which only import writes.
    var opDictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let log = log { d["log"] = log.rawValue }
        if let gamut = gamut { d["gamut"] = gamut.rawValue }
        if let lut = lut { d["lut"] = lut }
        return d
    }

    /// An `add_media` descriptor's `color`: `opDictionary` plus `detected`
    /// when true.
    var descriptorDictionary: [String: Any] {
        var d = opDictionary
        if detected { d["detected"] = true }
        return d
    }
}
