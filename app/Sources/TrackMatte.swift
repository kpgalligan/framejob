import Foundation

/// A track's matte (format version 14, spec §11 MT-1), mirroring
/// `core/src/model_matte.rs`'s `TrackMatte`: what the track's clips do to
/// the track directly behind it — nothing (`none`, an ordinary track), or
/// cut it by their alpha, inverted alpha, Rec. 709 luma or inverted luma.
///
/// **The case ORDER is a shader discriminant** (MT-3): `shaderCode` is the
/// case index, `Compositor.metal`'s `kMatteNone`…`kMatteLumaInverted`
/// compare against the same integers, and the core declares the variants in
/// the same order. Append, never reorder — `BlendMode`'s rule.
enum TrackMatte: String, Codable, CaseIterable {
    case none
    case alpha
    case alphaInverted = "alpha_inverted"
    case luma
    case lumaInverted = "luma_inverted"

    /// The word a person reads for the mode: the menu row (MT-7) and the
    /// header's tag.
    var displayName: String {
        switch self {
        case .none: return "Off"
        case .alpha: return "Alpha"
        case .alphaInverted: return "Inverted Alpha"
        case .luma: return "Luma"
        case .lumaInverted: return "Inverted Luma"
        }
    }

    /// The code the matte resolve pass's uniform carries: the case index,
    /// `none` 0 to `lumaInverted` 4.
    var shaderCode: Float { Float(TrackMatte.allCases.firstIndex(of: self) ?? 0) }

    /// The track `track` cuts (MT-2), the core's `matte_target` for the
    /// CHROME only — the header's tag, the lane's bracket and the Clip tab's
    /// note; what is drawn is the recipe's. The track directly behind it in
    /// `tracks` (one container, back first), when that track is not itself a
    /// matte track; nil for an ordinary track, a back-most matte track, a
    /// matte in front of a matte and an id `tracks` does not hold.
    static func target(of track: UInt32, in tracks: [TrackSnapshot]) -> UInt32? {
        guard let index = tracks.firstIndex(where: { $0.id == track }),
              tracks[index].matte != .none, index > 0
        else { return nil }
        let behind = tracks[index - 1]
        return behind.matte == .none ? behind.id : nil
    }
}
