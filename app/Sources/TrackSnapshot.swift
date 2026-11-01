import AppKit

// One timeline track, `TrackSnapshot`: a pure move out of
// `ProjectSnapshot.swift` (road map creator-jobs CJ0d, T13).

// MARK: - Tracks

/// One timeline track. Higher index = further front (§2); the ORDER of
/// `ProjectSnapshot.tracks` is that stacking order, index 0 = back.
struct TrackSnapshot: Codable, Equatable, Identifiable {
    let id: UInt32
    let name: String
    /// Contributes no video layers when true (audio still plays).
    let hidden: Bool
    let muted: Bool
    /// Locked tracks are not hit-tested and ripple/insert-time skip them.
    let locked: Bool
    /// While any track in its container is soloed, every track that is not
    /// is silent — audio only, and mute still wins on the same track. The
    /// core's envelopes apply it (`audio.rs`); the header only shows it.
    let solo: Bool
    /// The track's matte (format version 14, `TrackMatte.swift`); `.none`
    /// for an ordinary track and for a file that names no mode.
    let matte: TrackMatte
    /// The track's fader, linear 0…4, and its pan, −1…1 (format 35, spec
    /// §11 AU-102); the core's envelope and plan apply both.
    let volume: Double
    let pan: Double
    /// The track's compressor and limiter (format 36, spec §11 AU-150), nil
    /// when off; post-fader on the track's sub-mix (AU-151).
    let compressor: CompressorProps?
    let limiter: LimiterProps?

    init(
        id: UInt32, name: String = "Track", hidden: Bool = false, muted: Bool = false,
        locked: Bool = false, solo: Bool = false, matte: TrackMatte = .none,
        volume: Double = 1, pan: Double = 0, compressor: CompressorProps? = nil,
        limiter: LimiterProps? = nil
    ) {
        self.id = id
        self.name = name
        self.hidden = hidden
        self.muted = muted
        self.locked = locked
        self.solo = solo
        self.matte = matte
        self.volume = volume
        self.pan = pan
        self.compressor = compressor
        self.limiter = limiter
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UInt32.self, forKey: .id)
        name = c.lenient(.name, "Track")
        hidden = c.lenient(.hidden, false)
        muted = c.lenient(.muted, false)
        locked = c.lenient(.locked, false)
        solo = c.lenient(.solo, false)
        matte = c.lenient(.matte, TrackMatte.none)
        volume = c.lenient(.volume, 1.0)
        pan = c.lenient(.pan, 0.0)
        compressor = c.lenient(.compressor)
        limiter = c.lenient(.limiter)
    }
}
