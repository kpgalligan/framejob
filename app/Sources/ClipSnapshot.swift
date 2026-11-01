import AppKit

// A clip, what it plays and its transition — `ClipSource`, `ClipSnapshot`,
// `TransitionSnapshot`: a pure move out of `ProjectSnapshot.swift` (road map
// creator-jobs CJ0d, T12).

// MARK: - Clips

/// What a clip plays. Internally tagged by `kind`, and one of its keys is
/// the Swift keyword `in` — so it codes by hand rather than through the
/// snake_case strategy.
enum ClipSource: Codable, Equatable {
    /// A video or audio file. `in` is the source time of the first frame —
    /// in the REVERSED stream when `reversed` is set, which has the same
    /// duration, so no time math anywhere changes with the flag.
    case media(id: UInt32, in: Ticks, reversed: Bool)
    /// A freeze frame: one source frame held. `at` is the source time.
    case still(id: UInt32, at: Ticks)
    /// A still picture file (PNG/JPEG/HEIC).
    case image(id: UInt32)
    case text
    case shape
    /// Drawn by a module in the package's `graphics/` (format version 10).
    /// The description is the clip's `graphic` key, decoded as
    /// `ClipSnapshot.graphic` (`ProjectSnapshot+Graphic.swift`).
    case graphic
    /// A group of tracks and clips shown as one clip, by nest id
    /// (`ProjectSnapshot.nests`).
    ///
    /// A NUMBER since format version 2. It was a path in version 1 while
    /// this side already decoded a `UInt32` — `lenient` swallowed the
    /// mismatch to 0, so a nest clip silently lost its identity crossing
    /// the FFI. The two sides now agree.
    case nest(project: UInt32)
    case adjustment  // no picture: grades what is behind it (spec §11 GR-6)

    private enum CodingKeys: String, CodingKey {
        case kind, media, at, project, reversed
        case sourceIn = "in"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = c.lenient(.kind, "media")
        switch kind {
        case "media":
            self = .media(
                id: c.lenient(.media, 0), in: c.lenient(.sourceIn, 0),
                reversed: c.lenient(.reversed, false))
        case "still":
            self = .still(id: c.lenient(.media, 0), at: c.lenient(.at, 0))
        case "image":
            self = .image(id: c.lenient(.media, 0))
        case "text": self = .text
        case "shape": self = .shape
        case "graphic": self = .graphic
        case "adjustment": self = .adjustment
        case "nest":
            self = .nest(project: c.lenient(.project, 0))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c, debugDescription: "unknown clip source kind '\(kind)'")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kindName, forKey: .kind)
        switch self {
        case .media(let id, let sourceIn, let reversed):
            try c.encode(id, forKey: .media)
            try c.encode(sourceIn, forKey: .sourceIn)
            try c.encode(reversed, forKey: .reversed)
        case .still(let id, let at):
            try c.encode(id, forKey: .media)
            try c.encode(at, forKey: .at)
        case .image(let id):
            try c.encode(id, forKey: .media)
        case .text, .shape, .graphic, .adjustment: break
        case .nest(let project):
            try c.encode(project, forKey: .project)
        }
    }

    /// The media this clip references, or nil for the generated kinds.
    var mediaID: UInt32? {
        switch self {
        case .media(let id, _, _), .still(let id, _), .image(let id): return id
        case .text, .shape, .graphic, .nest, .adjustment: return nil
        }
    }

    /// The nest this clip shows, or nil for every other kind.
    var nestID: UInt32? {
        if case .nest(let project) = self { return project }
        return nil
    }

    /// True when the clip plays its media backwards, which is what
    /// `CompositionBuilder` substitutes a pre-rendered reversed asset for.
    var isReversed: Bool {
        if case .media(_, _, let reversed) = self { return reversed }
        return false
    }

    /// The model's tag, for op JSON, timeline tinting and agent replies.
    var kindName: String {
        switch self {
        case .media: return "media"
        case .still: return "still"
        case .image: return "image"
        case .text: return "text"
        case .shape: return "shape"
        case .graphic: return "graphic"
        case .nest: return "nest"
        case .adjustment: return "adjustment"
        }
    }

    /// Source time of the clip's first frame; 0 for kinds with no source
    /// bound (§5.2 — `still`, `image`, `text`, `shape` may take any length).
    var sourceIn: Ticks {
        switch self {
        case .media(_, let sourceIn, _): return sourceIn
        case .still(_, let at): return at
        case .image, .text, .shape, .graphic, .nest, .adjustment: return 0
        }
    }

    /// Only `media` clips are limited by their source's length, and only
    /// they accept `set_speed` / `rate_stretch` (§6).
    var hasSourceBound: Bool {
        if case .media = self { return true }
        return false
    }
}

/// One clip on one track. The bar the timeline draws and the layer the
/// compositor composites.
struct ClipSnapshot: Codable, Equatable, Identifiable {
    let id: UInt32
    let track: UInt32
    /// Project time of the clip's first frame.
    let start: Ticks
    let duration: Ticks
    let source: ClipSource
    let enabled: EnabledFlags
    /// Playback rate; `media` sources only (§6 `set_speed`).
    let speed: Double
    let video: VideoProps?
    let audio: AudioProps?
    let text: TextProps?
    let shape: ShapeProps?
    let graphic: GraphicSnapshot?
    let actions: [ActionSnapshot]
    /// The transition into this clip. Its DURATION is the overlap with the
    /// previous clip on the track; with no overlap it is ignored.
    let transitionIn: TransitionSnapshot?
    /// The clip's OWN name (format version 3); nil means "call it what it
    /// shows", and `ProjectSnapshot.name(of:)` holds that fallback.
    let name: String?
    /// A colour name from `ClipLabel`'s vocabulary, or nil for no label.
    /// Stored unvalidated on both sides, so draw it through
    /// `ClipLabel.color(named:)`, which absorbs a name this build lacks.
    let label: String?
    /// The clip this one is linked to (format 28, spec §11 AU-90): Detach
    /// Audio's picture and sound, which every placement edit keeps in step.
    let linked: UInt32?

    init(
        id: UInt32, track: UInt32, start: Ticks = 0, duration: Ticks = 0,
        source: ClipSource = .text, enabled: EnabledFlags = EnabledFlags(),
        speed: Double = 1, video: VideoProps? = nil, audio: AudioProps? = nil,
        text: TextProps? = nil, shape: ShapeProps? = nil,
        graphic: GraphicSnapshot? = nil,
        actions: [ActionSnapshot] = [], transitionIn: TransitionSnapshot? = nil,
        name: String? = nil, label: String? = nil, linked: UInt32? = nil
    ) {
        self.id = id
        self.track = track
        self.start = start
        self.duration = duration
        self.source = source
        self.enabled = enabled
        self.speed = speed
        self.video = video
        self.audio = audio
        self.text = text
        self.shape = shape
        self.graphic = graphic
        self.actions = actions
        self.transitionIn = transitionIn
        self.name = name
        self.label = label
        self.linked = linked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UInt32.self, forKey: .id)
        track = try c.decode(UInt32.self, forKey: .track)
        start = c.lenient(.start, 0)
        duration = c.lenient(.duration, 0)
        source = try c.decode(ClipSource.self, forKey: .source)
        enabled = c.lenient(.enabled, EnabledFlags())
        speed = c.lenient(.speed, 1)
        video = c.lenient(.video)
        audio = c.lenient(.audio)
        text = c.lenient(.text)
        shape = c.lenient(.shape)
        graphic = c.lenient(.graphic)
        actions = c.lenient(.actions, [])
        transitionIn = c.lenient(.transitionIn)
        name = c.lenient(.name)
        label = c.lenient(.label)
        linked = c.lenient(.linked)
    }

    /// Project time one tick past the clip's last frame.
    var end: Ticks { start + duration }
    /// The clip's span in project time.
    var range: Range<Ticks> { start..<max(start, end) }
    /// Whether project time `t` falls inside the clip.
    func contains(_ t: Ticks) -> Bool { t >= start && t < end }
    /// Project time `t` as clip time; negative or past `duration` outside.
    func clipTime(_ t: Ticks) -> Ticks { t - start }

    /// The pixel properties with the model's defaults filled in — what every
    /// view should draw from, so a clip that has never been transformed is
    /// not a special case.
    var videoProps: VideoProps { video ?? .identity }
    /// The sample properties with defaults filled in.
    var audioProps: AudioProps { audio ?? AudioProps() }

    /// The clip's label in the timeline when there is no media name to use:
    /// the text itself for a text clip, else the kind.
    var fallbackName: String {
        switch source {
        case .text:
            let content = text?.content ?? ""
            return content.isEmpty ? "Text" : content
        case .shape: return shape?.kind.displayName ?? "Shape"
        case .graphic: return "Graphic"
        case .still: return "Freeze Frame"
        case .nest: return "Nest"
        case .adjustment: return "Adjustment"
        case .media, .image: return "Clip"
        }
    }
}

/// The transition into a clip (§5.2 `transition_in`).
///
/// `curve` and `audio` are format version 7's. Their defaults here are the
/// FILE defaults — linear and silent — and not what the core MINTS (spec
/// §11, R5-2), because this type decodes files: a version-6 project carries
/// neither key and must read as what it always rendered. `audioShape` is
/// format 29's (spec §11 AU-115), `plus_3db` — R5-2's constant power — when
/// absent.
struct TransitionSnapshot: Codable, Equatable {
    let kind: TransitionKind
    let curve: Curve
    let audio: Bool
    let audioShape: FadeShape

    init(
        kind: TransitionKind = .crossDissolve, curve: Curve = .linear, audio: Bool = false,
        audioShape: FadeShape = .plus3Db
    ) {
        self.kind = kind
        self.curve = curve
        self.audio = audio
        self.audioShape = audioShape
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(.kind, TransitionKind.crossDissolve)
        curve = c.lenient(.curve, Curve.linear)
        audio = c.lenient(.audio, false)
        audioShape = c.lenient(.audioShape, FadeShape.plus3Db)
    }
}
