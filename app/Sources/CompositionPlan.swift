import AppKit

// MARK: - Composition plan (spec §7.2)

/// One clip's contribution to a composition track. `duration !=
/// sourceDuration` is the signal to `scaleTimeRange` (speed and freeze).
struct PlanSegment: Codable, Equatable {
    let clip: UInt32
    let media: UInt32
    let sourceIn: Ticks
    let sourceDuration: Ticks
    let start: Ticks
    let duration: Ticks
    /// The time-pitch algorithm for a speed change, e.g. "spectral"; nil
    /// leaves AVFoundation's default.
    let pitch: String?
    /// A video segment's media's Camera Log (spec §11 GR-16), present only
    /// when the media converts: it makes the composition a converting one
    /// (`CompositionPlan.convertsMedia`).
    let input: MediaColor?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clip = c.lenient(.clip, 0)
        media = c.lenient(.media, 0)
        sourceIn = c.lenient(.sourceIn, 0)
        sourceDuration = c.lenient(.sourceDuration, 0)
        start = c.lenient(.start, 0)
        duration = c.lenient(.duration, 0)
        pitch = c.lenient(.pitch)
        input = c.lenient(.input)
    }

    /// Whether the segment needs `scaleTimeRange` — speed, or the
    /// one-source-frame freeze idiom.
    var isTimeScaled: Bool { duration != sourceDuration }
}

/// One piecewise-linear leg of an audio envelope.
struct PlanRamp: Codable, Equatable {
    let start: Ticks
    let duration: Ticks
    let from: Double
    let to: Double

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = c.lenient(.start, 0)
        duration = c.lenient(.duration, 0)
        from = c.lenient(.from, 1)
        to = c.lenient(.to, 1)
    }
}

/// One composition track: video ids start at 1, audio at 1001, and
/// `CompositionBuilder` passes the id as `preferredTrackID` so the recipe
/// can name a track by the same number. (Audio moved up from 101 when nests
/// landed — a nest contributes its own tracks, so the old gap of a hundred
/// was reachable. Nothing in Swift reads the number; both halves come from
/// the plan.)
struct PlanTrack: Codable, Equatable, Identifiable {
    let id: Int
    let segments: [PlanSegment]
    /// Audio only: the envelope covering the whole extent, fades, volume
    /// actions and ducking already folded in.
    let ramps: [PlanRamp]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id, 0)
        segments = c.lenient(.segments, [])
        ramps = c.lenient(.ramps)
    }
}

/// One `AVVideoCompositionInstruction` range. Instructions tile
/// `[0, duration]` with no gaps or overlaps — an AVFoundation requirement.
struct PlanInstruction: Codable, Equatable {
    let start: Ticks
    let duration: Ticks
    let requiredTrackIDs: [Int]

    private enum CodingKeys: String, CodingKey {
        case start, duration
        // `required_track_ids` converts to `requiredTrackIds`.
        case requiredTrackIDs = "requiredTrackIds"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = c.lenient(.start, 0)
        duration = c.lenient(.duration, 0)
        requiredTrackIDs = c.lenient(.requiredTrackIDs, [])
    }
}

/// Everything structural about the timeline, and nothing else — which is
/// why comparing two plans as STRINGS is a correct rebuild-vs-refresh test
/// (§7.6, §11).
struct CompositionPlan: Codable, Equatable {
    let timescale: Int
    let duration: Ticks
    let fps: Fps
    let renderSize: [Int]
    let videoTracks: [PlanTrack]
    let audioTracks: [PlanTrack]
    let instructions: [PlanInstruction]
    /// Advisory, e.g. more than 8 video tracks required by one instruction.
    let warnings: [String]
    /// The project's dynamic range (spec §11 HD-2): every composition of an
    /// HLG project converts in BT.2020/HLG (`CompositionBuilder`).
    let output: CanvasOutput

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timescale = c.lenient(.timescale, Int(ReelTime.perSecond))
        duration = c.lenient(.duration, 0)
        fps = c.lenient(.fps, Fps.thirty)
        renderSize = c.lenient(.renderSize, [1920, 1080])
        videoTracks = c.lenient(.videoTracks, [])
        audioTracks = c.lenient(.audioTracks, [])
        instructions = c.lenient(.instructions, [])
        warnings = c.lenient(.warnings, [])
        output = c.lenient(.output, .sdr)
    }

    /// Whether any video segment's media converts at step 0 (spec §11
    /// GR-16): such a composition is built with `ConvertingCompositor` even
    /// when no source's labels ask for one, and a change of setting changes
    /// the plan, so `Playback.update` rebuilds it.
    var convertsMedia: Bool {
        videoTracks.contains { $0.segments.contains { $0.input != nil } }
    }

    /// `renderSize` as a size; the canvas default when malformed.
    var renderSizeCG: CGSize {
        guard renderSize.count >= 2 else { return CGSize(width: 1920, height: 1080) }
        return CGSize(width: renderSize[0], height: renderSize[1])
    }
}
