import AppKit

/// The typed, READ-ONLY mirror of the project JSON (spec §5.2) that
/// `rc_project_to_json` hands back. Every Swift view draws from a value in
/// this file; nothing here mutates, and nothing here builds an edit — edits
/// are `ReelOp` values in `ReelCore.swift`, which owns the other half of this
/// contract (the op table lives in the module doc of `core/src/edit.rs`).
///
/// Decoding rules, in one place because they are easy to get wrong:
///
///  - `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` (see
///    `ReelJSON`), so a property spelled `cornerRadius` matches the model's
///    `corner_radius` with no `CodingKeys` at all.
///  - **Pitfall:** that conversion is not symmetric for acronyms —
///    `required_track_ids` converts to `requiredTrackIds`, NOT
///    `requiredTrackIDs`. Any property whose Swift name capitalises an
///    acronym needs an explicit `CodingKeys` raw value spelled the way the
///    converter spells it. `PlanInstruction` is the one such case.
///  - The three keys that cannot round-trip through the converter get custom
///    coding: `source` (internally tagged by `kind`, and one of its keys is
///    the Swift keyword `in`), `fps` (a two-element array, not an object),
///    and the recipe's tagged `source`.
///  - Every field the model gives a serde default decodes that same default
///    when absent, null, or the wrong shape (`lenient` below), so a
///    hand-written project JSON still loads. Only identity fields (`id`,
///    `track`, `path`, a clip's `source`) are required.

// MARK: - Scalars

/// Project time. Integer ticks at `ReelTime.perSecond` (600 000/s, spec
/// §5.1) — a timescale that divides every common frame duration exactly, so
/// no edit ever lands off the grid through rounding.
typealias Ticks = Int64

/// A frame rate as the exact rational the model stores. Serialized as the
/// two-element array `[num, den]`, which is why it codes by hand.
struct Fps: Codable, Equatable {
    let num: Int
    let den: Int

    init(num: Int, den: Int) {
        self.num = num
        self.den = den
    }

    /// The rate as a Double, for display and for arithmetic that does not
    /// have to be exact. 0 for a degenerate rate, never a division by zero.
    var double: Double { den == 0 ? 0 : Double(num) / Double(den) }

    /// One frame in ticks, exact for every rate in `Fps.common` — the step
    /// the arrow keys and frame-accurate seeks use. 0 for a degenerate rate.
    var frameDuration: Ticks {
        guard num > 0, den > 0 else { return 0 }
        return Ticks(ReelTime.perSecond) * Ticks(den) / Ticks(num)
    }

    /// "30", "29.97", "23.976" — the Document tab's spelling.
    var displayName: String {
        if den == 1 { return String(num) }
        let value = double
        return String(format: value < 100 ? "%.3f" : "%.2f", value)
            .replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }

    /// The rates the Document tab offers, in the order it lists them.
    static let common: [Fps] = [
        Fps(num: 24, den: 1), Fps(num: 24000, den: 1001), Fps(num: 25, den: 1),
        Fps(num: 30, den: 1), Fps(num: 30000, den: 1001), Fps(num: 50, den: 1),
        Fps(num: 60, den: 1),
    ]

    static let thirty = Fps(num: 30, den: 1)

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        num = try c.decode(Int.self)
        den = try c.decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(num)
        try c.encode(den)
    }
}

/// A colour as the model stores it: four components 0…1, straight alpha.
/// Kept as an array rather than a struct so it round-trips byte-for-byte
/// through the core, which never inspects it.
typealias RGBA = [Double]

extension Array where Element == Double {
    /// The array read as an RGBA colour in sRGB. Missing components read as
    /// 0 except alpha, which reads as 1 — so a three-element `chroma.key`
    /// converts without a special case.
    var nsColor: NSColor {
        func component(_ i: Int) -> CGFloat {
            i < count ? CGFloat(Swift.min(Swift.max(self[i], 0), 1)) : (i == 3 ? 1 : 0)
        }
        return NSColor(
            srgbRed: component(0), green: component(1), blue: component(2),
            alpha: component(3))
    }
}

extension NSColor {
    /// The colour as the model's `[r, g, b, a]`. Converts to sRGB first;
    /// nil-safe (a colour with no RGB representation reads as opaque black),
    /// because a colour well can hand back a pattern or a catalog colour.
    var rgbaComponents: RGBA {
        guard let c = usingColorSpace(.sRGB) else { return [0, 0, 0, 1] }
        return [
            Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent),
            Double(c.alphaComponent),
        ]
    }
}

// MARK: - Decoding helpers

extension KeyedDecodingContainer {
    /// Decodes `key`, falling back to the model's documented default when it
    /// is absent, null, or the wrong shape. Deliberately non-throwing: a
    /// hand-written project with a missing optional field must still open.
    func lenient<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }

    /// Decodes an optional-by-design field (`shadow`, `duck`, `outline`, …);
    /// nil when absent, null or malformed.
    func lenient<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// Decodes a field where "absent" and "explicitly null" mean different
    /// things — the patch convention (§6 `set_action_end`: a key set to null
    /// REMOVES it, an absent key leaves it alone). Outer nil = absent.
    func nullable<T: Decodable>(_ key: Key) -> T?? {
        guard contains(key) else { return nil }
        return .some((try? decodeIfPresent(T.self, forKey: key)) ?? nil)
    }
}

/// The one configured decoder for everything the core emits — the project,
/// the plan, the recipe, export presets and settings. A fresh instance per
/// call on purpose: `JSONDecoder` is not documented as thread-safe and the
/// compositor decodes recipes on its own queue while the main thread decodes
/// snapshots.
enum ReelJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Encoder for the rare Swift → core direction. NOT the persistence
    /// path: `.reelcut` stores `rc_project_to_json`'s own bytes, never a
    /// re-encoded snapshot, so the core stays the single writer of the file
    /// format.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? decoder().decode(type, from: data)
    }
}

// MARK: - Enumerations

/// What a media file is. `image` is a still picture (ImageIO decodes it);
/// `audio` has no video track.
enum MediaKind: String, Codable, CaseIterable {
    case video, audio, image

    var displayName: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        case .image: return "Image"
        }
    }
}

/// The shape kinds the Shape tab offers. A "rounded rectangle" is a
/// `rectangle` with a non-zero `radius`, not a kind of its own.
enum ShapeKind: String, Codable, CaseIterable {
    case rectangle, ellipse, line, arrow

    var displayName: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        case .arrow: return "Arrow"
        }
    }

    /// Line and arrow are the two kinds whose geometry is the `from`/`to`
    /// endpoints rather than the box, so they get endpoint handles.
    var isLinear: Bool { self == .line || self == .arrow }
}

/// An action's easing. Raw values are the model's spelling; the key decoding
/// strategy never touches VALUES, so these stay snake_case.
enum Curve: String, Codable, CaseIterable {
    case linear
    case easeIn = "ease_in"
    case easeOut = "ease_out"
    case easeInOut = "ease_in_out"

    var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .easeInOut: return "Ease In Out"
        }
    }
}

/// The ten transitions of spec §5.2. A transition's DURATION is the overlap
/// with the previous clip on the track, so it lives in the timeline, not
/// here; this is only which one it is.
enum TransitionKind: String, Codable, CaseIterable {
    case crossDissolve = "cross_dissolve"
    case fadeBlack = "fade_black"
    case fadeWhite = "fade_white"
    case pushLeft = "push_left"
    case pushRight = "push_right"
    case pushUp = "push_up"
    case pushDown = "push_down"
    case wipe
    case slide
    case zoom

    var displayName: String {
        switch self {
        case .crossDissolve: return "Cross Dissolve"
        case .fadeBlack: return "Fade Through Black"
        case .fadeWhite: return "Fade Through White"
        case .pushLeft: return "Push Left"
        case .pushRight: return "Push Right"
        case .pushUp: return "Push Up"
        case .pushDown: return "Push Down"
        case .wipe: return "Wipe"
        case .slide: return "Slide"
        case .zoom: return "Zoom"
        }
    }
}

// MARK: - Canvas

/// The document's fixed canvas (spec §5.2 `canvas`).
struct CanvasSnapshot: Codable, Equatable {
    let width: Int
    let height: Int
    let fps: Fps
    let background: RGBA
    /// Fit a dropped clip that exceeds the canvas (§6 `add_clip`).
    let fitNewClips: Bool
    /// Timecode shows `HH:MM:SS:FF` when true, `HH:MM:SS.mmm` when false.
    let timecodeFrames: Bool

    init(
        width: Int = 1920, height: Int = 1080, fps: Fps = .thirty,
        background: RGBA = [0, 0, 0, 1], fitNewClips: Bool = true,
        timecodeFrames: Bool = true
    ) {
        self.width = width
        self.height = height
        self.fps = fps
        self.background = background
        self.fitNewClips = fitNewClips
        self.timecodeFrames = timecodeFrames
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = c.lenient(.width, 1920)
        height = c.lenient(.height, 1080)
        fps = c.lenient(.fps, Fps.thirty)
        background = c.lenient(.background, [0, 0, 0, 1])
        fitNewClips = c.lenient(.fitNewClips, true)
        timecodeFrames = c.lenient(.timecodeFrames, true)
    }

    var size: CGSize { CGSize(width: width, height: height) }
    /// The canvas centre, the origin of every clip's `(x, y)` (§5.3).
    var center: CGPoint { CGPoint(x: Double(width) / 2, y: Double(height) / 2) }
    var aspect: Double { height == 0 ? 1 : Double(width) / Double(height) }
}

// MARK: - Media

/// One imported file. Referenced, never copied: `path` plus a base64
/// `URL.bookmarkData()` that survives a move. `mediaURL(for:)` in
/// `ReelCore.swift` resolves the pair.
struct MediaSnapshot: Codable, Equatable, Identifiable {
    let id: UInt32
    let path: String
    let bookmark: String?
    let kind: MediaKind
    let duration: Ticks
    let width: Int
    let height: Int
    let fps: Fps
    let hasVideo: Bool
    let hasAudio: Bool
    let hasAlpha: Bool

    init(
        id: UInt32, path: String, bookmark: String? = nil, kind: MediaKind = .video,
        duration: Ticks = 0, width: Int = 0, height: Int = 0, fps: Fps = .thirty,
        hasVideo: Bool = true, hasAudio: Bool = false, hasAlpha: Bool = false
    ) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
        self.kind = kind
        self.duration = duration
        self.width = width
        self.height = height
        self.fps = fps
        self.hasVideo = hasVideo
        self.hasAudio = hasAudio
        self.hasAlpha = hasAlpha
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UInt32.self, forKey: .id)
        path = c.lenient(.path, "")
        bookmark = c.lenient(.bookmark)
        kind = c.lenient(.kind, MediaKind.video)
        duration = c.lenient(.duration, 0)
        width = c.lenient(.width, 0)
        height = c.lenient(.height, 0)
        fps = c.lenient(.fps, Fps.thirty)
        hasVideo = c.lenient(.hasVideo, false)
        hasAudio = c.lenient(.hasAudio, false)
        hasAlpha = c.lenient(.hasAlpha, false)
    }

    /// The file's display name, for the Media tab and clip labels.
    var name: String { (path as NSString).lastPathComponent }
    /// Pixel size; `.zero` for audio, which has none.
    var pixelSize: CGSize { CGSize(width: width, height: height) }
}

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

    init(
        id: UInt32, name: String = "Track", hidden: Bool = false, muted: Bool = false,
        locked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.hidden = hidden
        self.muted = muted
        self.locked = locked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UInt32.self, forKey: .id)
        name = c.lenient(.name, "Track")
        hidden = c.lenient(.hidden, false)
        muted = c.lenient(.muted, false)
        locked = c.lenient(.locked, false)
    }
}

// MARK: - Clip property groups

/// Which halves of a clip are live. Detach Audio (§6) flips these across two
/// clips rather than moving samples.
struct EnabledFlags: Codable, Equatable {
    let video: Bool
    let audio: Bool

    init(video: Bool = true, audio: Bool = true) {
        self.video = video
        self.audio = audio
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        video = c.lenient(.video, true)
        audio = c.lenient(.audio, true)
    }
}

/// Crop insets in SOURCE pixels, one per edge. Cropping never shifts
/// content (§5.3) — see `canvasRect(of:in:sourceSize:video:)`.
struct CropInsets: Codable, Equatable {
    let l: Double
    let t: Double
    let r: Double
    let b: Double

    init(l: Double = 0, t: Double = 0, r: Double = 0, b: Double = 0) {
        self.l = l
        self.t = t
        self.r = r
        self.b = b
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        l = c.lenient(.l, 0)
        t = c.lenient(.t, 0)
        r = c.lenient(.r, 0)
        b = c.lenient(.b, 0)
    }

    static let zero = CropInsets()
    var isZero: Bool { l == 0 && t == 0 && r == 0 && b == 0 }
}

/// A drop shadow. `angle` is degrees clockwise from straight up; `distance`
/// and `blur` are canvas pixels.
struct ShadowProps: Codable, Equatable {
    let color: RGBA
    let opacity: Double
    let blur: Double
    let angle: Double
    let distance: Double

    init(
        color: RGBA = [0, 0, 0, 1], opacity: Double = 0.5, blur: Double = 12,
        angle: Double = 315, distance: Double = 8
    ) {
        self.color = color
        self.opacity = opacity
        self.blur = blur
        self.angle = angle
        self.distance = distance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = c.lenient(.color, [0, 0, 0, 1])
        opacity = c.lenient(.opacity, 0.5)
        blur = c.lenient(.blur, 12)
        angle = c.lenient(.angle, 315)
        distance = c.lenient(.distance, 8)
    }
}

/// Per-clip colour controls, all centred on 0 = no change.
struct ColorAdjust: Codable, Equatable {
    let brightness: Double
    let contrast: Double
    let saturation: Double
    /// Hue rotation in degrees.
    let hue: Double

    init(brightness: Double = 0, contrast: Double = 0, saturation: Double = 0, hue: Double = 0) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.hue = hue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = c.lenient(.brightness, 0)
        contrast = c.lenient(.contrast, 0)
        saturation = c.lenient(.saturation, 0)
        hue = c.lenient(.hue, 0)
    }

    static let identity = ColorAdjust()
    var isIdentity: Bool { self == .identity }
}

/// Chroma key (M3). `key` is a THREE-component colour — no alpha.
struct ChromaProps: Codable, Equatable {
    let key: [Double]
    let tolerance: Double
    let softness: Double
    let spill: Double

    init(
        key: [Double] = [0, 1, 0], tolerance: Double = 0.2, softness: Double = 0.1,
        spill: Double = 0.5
    ) {
        self.key = key
        self.tolerance = tolerance
        self.softness = softness
        self.spill = spill
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.lenient(.key, [0, 1, 0])
        tolerance = c.lenient(.tolerance, 0.2)
        softness = c.lenient(.softness, 0.1)
        spill = c.lenient(.spill, 0.5)
    }
}

/// The pixel half of a clip. `x`/`y` are canvas pixels from the canvas
/// CENTRE, y down; `scale` 1 = native pixels; `rotation` degrees clockwise.
struct VideoProps: Codable, Equatable {
    let x: Double
    let y: Double
    let scale: Double
    let rotation: Double
    let opacity: Double
    let crop: CropInsets
    /// Rounds the CROPPED rectangle, in source pixels, before rotation.
    let cornerRadius: Double
    let shadow: ShadowProps?
    let color: ColorAdjust
    let chroma: ChromaProps?

    init(
        x: Double = 0, y: Double = 0, scale: Double = 1, rotation: Double = 0,
        opacity: Double = 1, crop: CropInsets = .zero, cornerRadius: Double = 0,
        shadow: ShadowProps? = nil, color: ColorAdjust = .identity,
        chroma: ChromaProps? = nil
    ) {
        self.x = x
        self.y = y
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
        self.crop = crop
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.color = color
        self.chroma = chroma
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = c.lenient(.x, 0)
        y = c.lenient(.y, 0)
        scale = c.lenient(.scale, 1)
        rotation = c.lenient(.rotation, 0)
        opacity = c.lenient(.opacity, 1)
        crop = c.lenient(.crop, CropInsets.zero)
        cornerRadius = c.lenient(.cornerRadius, 0)
        shadow = c.lenient(.shadow)
        color = c.lenient(.color, ColorAdjust.identity)
        chroma = c.lenient(.chroma)
    }

    static let identity = VideoProps()
    /// The clip's offset from the canvas centre, as a point.
    var offset: CGPoint { CGPoint(x: x, y: y) }
}

/// Ducking: "lower other audio to `level` while this clip plays" (§4.3).
/// By clip extent, never by voice activity — the core folds it into every
/// other track's envelope.
struct DuckProps: Codable, Equatable {
    let level: Double
    let attack: Ticks
    let release: Ticks

    init(level: Double = 0.2, attack: Ticks = 300_000, release: Ticks = 600_000) {
        self.level = level
        self.attack = attack
        self.release = release
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = c.lenient(.level, 0.2)
        attack = c.lenient(.attack, 300_000)
        release = c.lenient(.release, 600_000)
    }
}

/// The sample half of a clip. `volume` may exceed 1, up to 4 (§5.2).
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

    init(
        volume: Double = 1, muted: Bool = false, fadeIn: Ticks = 0, fadeOut: Ticks = 0,
        duck: DuckProps? = nil, mono: Bool = false, keepPitch: Bool = true
    ) {
        self.volume = volume
        self.muted = muted
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.duck = duck
        self.mono = mono
        self.keepPitch = keepPitch
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
    }

    /// Volume in dB for the Audio tab's read-out; -inf shows as silence.
    var decibels: Double { volume <= 0 ? -.infinity : 20 * log10(volume) }
}

/// A text outline (stroke), in canvas pixels.
struct OutlineProps: Codable, Equatable {
    let width: Double
    let color: RGBA

    init(width: Double = 2, color: RGBA = [0, 0, 0, 1]) {
        self.width = width
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = c.lenient(.width, 2)
        color = c.lenient(.color, [0, 0, 0, 1])
    }
}

/// The plate drawn behind text.
struct BackdropProps: Codable, Equatable {
    let color: RGBA
    let padding: Double
    let radius: Double

    init(color: RGBA = [0, 0, 0, 0.6], padding: Double = 12, radius: Double = 8) {
        self.color = color
        self.padding = padding
        self.radius = radius
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = c.lenient(.color, [0, 0, 0, 0.6])
        padding = c.lenient(.padding, 12)
        radius = c.lenient(.radius, 8)
    }
}

/// A text clip's description. The model NEVER stores the measured layout
/// size — only `LayerRenderers` knows it, and it reports it to the canvas
/// overlay through a hash-keyed cache (§5.3, §11).
struct TextProps: Codable, Equatable {
    let content: String
    let font: String
    let size: Double
    let color: RGBA
    /// "left" | "center" | "right".
    let align: String
    /// "top" | "middle" | "bottom", within the box.
    let valign: String
    let lineSpacing: Double
    /// Letter spacing, in points.
    let tracking: Double
    let outline: OutlineProps?
    let backdrop: BackdropProps?
    /// Fixed box width in canvas pixels; nil auto-sizes to the content.
    let width: Double?

    init(
        content: String = "", font: String = "SourceSans3-SemiBold", size: Double = 72,
        color: RGBA = [1, 1, 1, 1], align: String = "center", valign: String = "middle",
        lineSpacing: Double = 1, tracking: Double = 0, outline: OutlineProps? = nil,
        backdrop: BackdropProps? = nil, width: Double? = nil
    ) {
        self.content = content
        self.font = font
        self.size = size
        self.color = color
        self.align = align
        self.valign = valign
        self.lineSpacing = lineSpacing
        self.tracking = tracking
        self.outline = outline
        self.backdrop = backdrop
        self.width = width
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = c.lenient(.content, "")
        font = c.lenient(.font, "SourceSans3-SemiBold")
        size = c.lenient(.size, 72)
        color = c.lenient(.color, [1, 1, 1, 1])
        align = c.lenient(.align, "center")
        valign = c.lenient(.valign, "middle")
        lineSpacing = c.lenient(.lineSpacing, 1)
        tracking = c.lenient(.tracking, 0)
        outline = c.lenient(.outline)
        backdrop = c.lenient(.backdrop)
        width = c.lenient(.width)
    }
}

/// A shape's stroke.
struct StrokeProps: Codable, Equatable {
    let width: Double
    let color: RGBA

    init(width: Double = 6, color: RGBA = [1, 1, 1, 1]) {
        self.width = width
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = c.lenient(.width, 6)
        color = c.lenient(.color, [1, 1, 1, 1])
    }
}

/// A shape clip's description. `width`/`height` are the box in source
/// pixels — the shape's "source size" for §5.3 placement.
struct ShapeProps: Codable, Equatable {
    let kind: ShapeKind
    let width: Double
    let height: Double
    let stroke: StrokeProps?
    let fill: RGBA?
    let arrowStart: Bool
    let arrowEnd: Bool
    /// Corner radius for `rectangle`, in source pixels.
    let radius: Double
    /// UNIT coordinates in the box, `line` and `arrow` only.
    let from: [Double]
    let to: [Double]

    init(
        kind: ShapeKind = .rectangle, width: Double = 320, height: Double = 120,
        stroke: StrokeProps? = nil, fill: RGBA? = nil, arrowStart: Bool = false,
        arrowEnd: Bool = false, radius: Double = 0,
        from: [Double] = [0, 0.5], to: [Double] = [1, 0.5]
    ) {
        self.kind = kind
        self.width = width
        self.height = height
        self.stroke = stroke
        self.fill = fill
        self.arrowStart = arrowStart
        self.arrowEnd = arrowEnd
        self.radius = radius
        self.from = from
        self.to = to
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(.kind, ShapeKind.rectangle)
        width = c.lenient(.width, 320)
        height = c.lenient(.height, 120)
        stroke = c.lenient(.stroke)
        fill = c.lenient(.fill)
        arrowStart = c.lenient(.arrowStart, false)
        arrowEnd = c.lenient(.arrowEnd, false)
        radius = c.lenient(.radius, 0)
        from = c.lenient(.from, [0, 0.5])
        to = c.lenient(.to, [1, 0.5])
    }

    var boxSize: CGSize { CGSize(width: width, height: height) }
    /// `from` in unit space; (0, 0.5) when the array is malformed.
    var fromPoint: CGPoint { ShapeProps.point(from, fallback: CGPoint(x: 0, y: 0.5)) }
    var toPoint: CGPoint { ShapeProps.point(to, fallback: CGPoint(x: 1, y: 0.5)) }

    private static func point(_ values: [Double], fallback: CGPoint) -> CGPoint {
        guard values.count >= 2 else { return fallback }
        return CGPoint(x: values[0], y: values[1])
    }
}

// MARK: - Actions

/// An action's END state: a SPARSE patch of `video`, `audio` and `text`
/// keys. Sparse is the whole point — an absent key means "whatever is in
/// effect at the action's start" (§5.4), which is why the patch types are
/// structs of optionals rather than full property groups. The patch types
/// themselves live in `ReelCore.swift` beside the op builders that send
/// them, so there is exactly one shape per patch.
struct ActionPatch: Codable, Equatable {
    var video: VideoPatch?
    var audio: AudioPatch?
    var text: TextPatch?

    init(video: VideoPatch? = nil, audio: AudioPatch? = nil, text: TextPatch? = nil) {
        self.video = video
        self.audio = audio
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        video = c.lenient(.video)
        audio = c.lenient(.audio)
        text = c.lenient(.text)
    }

    var isEmpty: Bool { video == nil && audio == nil && text == nil }
}

/// A span on a clip with an easing curve, whose END values you edit (§2.3).
/// `start` is CLIP time, not project time.
struct ActionSnapshot: Codable, Equatable, Identifiable {
    let id: UInt32
    let start: Ticks
    let duration: Ticks
    let curve: Curve
    let end: ActionPatch

    init(
        id: UInt32, start: Ticks = 0, duration: Ticks = 600_000, curve: Curve = .easeInOut,
        end: ActionPatch = ActionPatch()
    ) {
        self.id = id
        self.start = start
        self.duration = duration
        self.curve = curve
        self.end = end
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UInt32.self, forKey: .id)
        start = c.lenient(.start, 0)
        duration = c.lenient(.duration, 600_000)
        curve = c.lenient(.curve, Curve.easeInOut)
        end = c.lenient(.end, ActionPatch())
    }

    /// End of the span, in clip time.
    var endTime: Ticks { start + duration }
}

// MARK: - Clips

/// What a clip plays. Internally tagged by `kind`, and one of its keys is
/// the Swift keyword `in` — so it codes by hand rather than through the
/// snake_case strategy.
enum ClipSource: Codable, Equatable {
    /// A video or audio file. `in` is the source time of the first frame.
    case media(id: UInt32, in: Ticks)
    /// A freeze frame: one source frame held. `at` is the source time.
    case still(id: UInt32, at: Ticks)
    /// A still picture file (PNG/JPEG/HEIC).
    case image(id: UInt32)
    case text
    case shape
    /// A nested project (M3).
    case nest(project: UInt32)

    private enum CodingKeys: String, CodingKey {
        case kind, media, at, project
        case sourceIn = "in"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = c.lenient(.kind, "media")
        switch kind {
        case "media":
            self = .media(id: c.lenient(.media, 0), in: c.lenient(.sourceIn, 0))
        case "still":
            self = .still(id: c.lenient(.media, 0), at: c.lenient(.at, 0))
        case "image":
            self = .image(id: c.lenient(.media, 0))
        case "text":
            self = .text
        case "shape":
            self = .shape
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
        case .media(let id, let sourceIn):
            try c.encode(id, forKey: .media)
            try c.encode(sourceIn, forKey: .sourceIn)
        case .still(let id, let at):
            try c.encode(id, forKey: .media)
            try c.encode(at, forKey: .at)
        case .image(let id):
            try c.encode(id, forKey: .media)
        case .text, .shape:
            break
        case .nest(let project):
            try c.encode(project, forKey: .project)
        }
    }

    /// The media this clip references, or nil for the generated kinds.
    var mediaID: UInt32? {
        switch self {
        case .media(let id, _), .still(let id, _), .image(let id): return id
        case .text, .shape, .nest: return nil
        }
    }

    /// The model's tag, for op JSON, timeline tinting and agent replies.
    var kindName: String {
        switch self {
        case .media: return "media"
        case .still: return "still"
        case .image: return "image"
        case .text: return "text"
        case .shape: return "shape"
        case .nest: return "nest"
        }
    }

    /// Source time of the clip's first frame; 0 for kinds with no source
    /// bound (§5.2 — `still`, `image`, `text`, `shape` may take any length).
    var sourceIn: Ticks {
        switch self {
        case .media(_, let sourceIn): return sourceIn
        case .still(_, let at): return at
        case .image, .text, .shape, .nest: return 0
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
    let actions: [ActionSnapshot]
    /// The transition into this clip. Its DURATION is the overlap with the
    /// previous clip on the track; with no overlap it is ignored.
    let transitionIn: TransitionSnapshot?

    init(
        id: UInt32, track: UInt32, start: Ticks = 0, duration: Ticks = 0,
        source: ClipSource = .text, enabled: EnabledFlags = EnabledFlags(),
        speed: Double = 1, video: VideoProps? = nil, audio: AudioProps? = nil,
        text: TextProps? = nil, shape: ShapeProps? = nil,
        actions: [ActionSnapshot] = [], transitionIn: TransitionSnapshot? = nil
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
        self.actions = actions
        self.transitionIn = transitionIn
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
        actions = c.lenient(.actions, [])
        transitionIn = c.lenient(.transitionIn)
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
        case .still: return "Freeze Frame"
        case .nest: return "Nest"
        case .media, .image: return "Clip"
        }
    }
}

/// The transition into a clip (§5.2 `transition_in`).
struct TransitionSnapshot: Codable, Equatable {
    let kind: TransitionKind

    init(kind: TransitionKind = .crossDissolve) {
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(.kind, TransitionKind.crossDissolve)
    }
}

// MARK: - Markers

/// A named point on the ruler; `chapter` markers become a chapter track on
/// export (M2).
struct MarkerSnapshot: Codable, Equatable, Identifiable {
    let id: UInt32
    let time: Ticks
    let name: String
    let color: String
    let chapter: Bool

    init(
        id: UInt32, time: Ticks = 0, name: String = "", color: String = "red",
        chapter: Bool = false
    ) {
        self.id = id
        self.time = time
        self.name = name
        self.color = color
        self.chapter = chapter
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UInt32.self, forKey: .id)
        time = c.lenient(.time, 0)
        name = c.lenient(.name, "")
        color = c.lenient(.color, "red")
        chapter = c.lenient(.chapter, false)
    }
}

// MARK: - The project

/// The whole document, decoded once per `ReelProject` handle
/// (`ReelProject.snapshot`). Selection, playhead, zoom and panel sizes are
/// deliberately NOT here — that is view state and lives in Swift (§5.2).
struct ProjectSnapshot: Codable, Equatable {
    let version: Int
    let canvas: CanvasSnapshot
    let media: [MediaSnapshot]
    /// Back to front: index 0 is the rearmost track.
    let tracks: [TrackSnapshot]
    let clips: [ClipSnapshot]
    let markers: [MarkerSnapshot]
    let nextId: UInt32

    init(
        version: Int = 1, canvas: CanvasSnapshot = CanvasSnapshot(),
        media: [MediaSnapshot] = [], tracks: [TrackSnapshot] = [],
        clips: [ClipSnapshot] = [], markers: [MarkerSnapshot] = [], nextId: UInt32 = 1
    ) {
        self.version = version
        self.canvas = canvas
        self.media = media
        self.tracks = tracks
        self.clips = clips
        self.markers = markers
        self.nextId = nextId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.lenient(.version, 1)
        canvas = c.lenient(.canvas, CanvasSnapshot())
        media = c.lenient(.media, [])
        tracks = c.lenient(.tracks, [])
        clips = c.lenient(.clips, [])
        markers = c.lenient(.markers, [])
        nextId = c.lenient(.nextId, 1)
    }

    /// The value a failed decode falls back to, so `ReelProject.snapshot`
    /// can stay non-optional and no view needs an "unloaded" state.
    static let empty = ProjectSnapshot()

    // MARK: Lookups

    func clip(_ id: UInt32) -> ClipSnapshot? { clips.first { $0.id == id } }
    func track(_ id: UInt32) -> TrackSnapshot? { tracks.first { $0.id == id } }
    func media(_ id: UInt32) -> MediaSnapshot? { media.first { $0.id == id } }
    func marker(_ id: UInt32) -> MarkerSnapshot? { markers.first { $0.id == id } }

    /// One track's clips in timeline order — the order the overlap rule and
    /// every transition lookup assume.
    func clips(onTrack id: UInt32) -> [ClipSnapshot] {
        clips.filter { $0.track == id }.sorted { $0.start < $1.start }
    }

    /// End of the last clip; 0 for an empty project. Mirrors
    /// `rc_project_duration` so views can answer without an FFI call.
    var duration: Ticks { clips.map(\.end).max() ?? 0 }

    /// Stacking index of a track: 0 = back, `tracks.count - 1` = front.
    func trackIndex(of id: UInt32) -> Int? { tracks.firstIndex { $0.id == id } }

    /// The media backing a clip, when it has one.
    func media(for clip: ClipSnapshot) -> MediaSnapshot? {
        clip.source.mediaID.flatMap { media($0) }
    }

    /// The timeline's label for a clip: the media file name where there is
    /// one, else the kind.
    func name(of clip: ClipSnapshot) -> String {
        media(for: clip)?.name ?? clip.fallbackName
    }

    /// The clip's UNCROPPED source rectangle size in source pixels — the
    /// input to `canvasRect`. nil for text (only `LayerRenderers` can
    /// measure a text layout, §5.3) and for nests (M3).
    func sourceSize(of clip: ClipSnapshot) -> CGSize? {
        switch clip.source {
        case .media(let id, _), .still(let id, _), .image(let id):
            guard let m = media(id), m.width > 0, m.height > 0 else { return nil }
            return m.pixelSize
        case .shape:
            guard let s = clip.shape, s.width > 0, s.height > 0 else { return nil }
            return s.boxSize
        case .text, .nest:
            return nil
        }
    }

    /// Clips that contribute PIXELS at project time `t`, back to front — the
    /// order the compositor draws in and the canvas hit-tests in reverse.
    /// Hidden tracks, disabled video and audio-only media drop out here so
    /// no caller repeats the test. Not a substitute for the frame recipe:
    /// this is the clip list, not the evaluated one.
    func layers(at t: Ticks) -> [ClipSnapshot] {
        let order = Dictionary(
            uniqueKeysWithValues: tracks.enumerated().map { ($0.element.id, $0.offset) })
        return clips
            .filter { clip in
                guard clip.contains(t), clip.enabled.video else { return false }
                guard track(clip.track)?.hidden != true else { return false }
                if let m = media(for: clip) { return m.hasVideo || m.kind == .image }
                return true
            }
            .sorted {
                let (a, b) = (order[$0.track] ?? 0, order[$1.track] ?? 0)
                return a == b ? $0.start < $1.start : a < b
            }
    }
}

// MARK: - Placement (spec §5.3)

/// The ONE placement rule. Every view that hit-tests, draws a handle or
/// snaps calls this — never re-derives it, because the pitfall is subtle:
/// cropping removes edges IN PLACE, so a cropped clip's rectangle is a
/// sub-rectangle of where the uncropped one sat, and the content under it
/// does not move (a screencast editor's behaviour, §5.3).
///
/// Returns the CROPPED rectangle in CANVAS pixel space with the origin at
/// the canvas's top-left and **y increasing downward** — the model's
/// convention, matching CoreVideo. A view in AppKit's flipped-or-not space
/// converts on the way out.
///
/// Rotation is deliberately NOT applied: it belongs to the caller, which
/// must rotate about `canvasAnchor(of:in:)` — the centre of the UNCROPPED
/// rectangle, not the centre of the returned one.
func canvasRect(
    of clip: ClipSnapshot, in canvas: CanvasSnapshot, sourceSize: CGSize, video: VideoProps
) -> CGRect {
    let scale = video.scale
    let full = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    let anchor = canvasAnchor(of: clip, in: canvas, video: video)
    let originX = anchor.x - full.width / 2
    let originY = anchor.y - full.height / 2
    // Crop insets are SOURCE pixels, so they scale with the layer.
    let l = video.crop.l * scale
    let t = video.crop.t * scale
    let r = video.crop.r * scale
    let b = video.crop.b * scale
    return CGRect(
        x: originX + l, y: originY + t,
        width: max(0, full.width - l - r), height: max(0, full.height - t - b))
}

/// The point a layer is placed on and rotated about: the canvas centre plus
/// the clip's `(x, y)`, in the same y-down canvas space as `canvasRect`.
/// Cropping never moves it — that is exactly why it is separate.
func canvasAnchor(of clip: ClipSnapshot, in canvas: CanvasSnapshot, video: VideoProps) -> CGPoint {
    CGPoint(x: canvas.center.x + video.x, y: canvas.center.y + video.y)
}

// MARK: - Frame recipe (spec §7.3)

/// The canvas facts a recipe carries, so the compositor never needs the
/// project to clear a frame.
struct RecipeCanvas: Codable, Equatable {
    let width: Int
    let height: Int
    let background: RGBA

    init(width: Int = 1920, height: Int = 1080, background: RGBA = [0, 0, 0, 1]) {
        self.width = width
        self.height = height
        self.background = background
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = c.lenient(.width, 1920)
        height = c.lenient(.height, 1080)
        background = c.lenient(.background, [0, 0, 0, 1])
    }

    var size: CGSize { CGSize(width: width, height: height) }
}

/// Where a recipe layer's pixels come from. Internally tagged by `kind`.
enum RecipeSourceRef: Codable, Equatable {
    /// A composition video track, named by the same id `CompositionBuilder`
    /// passed as `preferredTrackID` (§7.2).
    case track(Int)
    /// A still image file; Swift decodes with ImageIO and caches the texture.
    case image(UInt32)
    /// Resolved text plus a stable content hash to cache the texture by.
    case text(hash: String, props: TextProps)
    case shape(hash: String, props: ShapeProps)
    /// The media could not be resolved — draw a slate.
    case missing

    private enum CodingKeys: String, CodingKey {
        case kind, media, hash, text, shape
        // `track_id` converts to `trackId`, not `trackID`; spell it the way
        // the converter does or this key silently never matches.
        case trackID = "trackId"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = c.lenient(.kind, "missing")
        switch kind {
        case "track":
            self = .track(c.lenient(.trackID, 0))
        case "image":
            self = .image(c.lenient(.media, 0))
        case "text":
            self = .text(hash: c.lenient(.hash, ""), props: c.lenient(.text, TextProps()))
        case "shape":
            self = .shape(hash: c.lenient(.hash, ""), props: c.lenient(.shape, ShapeProps()))
        default:
            self = .missing
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .track(let id):
            try c.encode("track", forKey: .kind)
            try c.encode(id, forKey: .trackID)
        case .image(let id):
            try c.encode("image", forKey: .kind)
            try c.encode(id, forKey: .media)
        case .text(let hash, let props):
            try c.encode("text", forKey: .kind)
            try c.encode(hash, forKey: .hash)
            try c.encode(props, forKey: .text)
        case .shape(let hash, let props):
            try c.encode("shape", forKey: .kind)
            try c.encode(hash, forKey: .hash)
            try c.encode(props, forKey: .shape)
        case .missing:
            try c.encode("missing", forKey: .kind)
        }
    }

    /// The texture-cache key for the kinds `LayerRenderers` rasterizes;
    /// nil for track sources, which come from the decoder.
    var cacheHash: String? {
        switch self {
        case .text(let hash, _), .shape(let hash, _): return hash
        case .track, .image, .missing: return nil
        }
    }

    /// The composition track this layer samples, when it samples one.
    var trackID: Int? {
        if case .track(let id) = self { return id }
        return nil
    }
}

/// A transition the compositor draws as ONE pass over a pair of adjacent
/// layers: both carry the same `kind` and `progress`, one with role "out",
/// one with role "in" (§7.3).
struct RecipeTransition: Codable, Equatable {
    let kind: TransitionKind
    /// 0…1 across the overlap.
    let progress: Double
    /// "in" or "out".
    let role: String
    /// The other clip of the pair.
    let partner: UInt32

    init(kind: TransitionKind, progress: Double, role: String, partner: UInt32) {
        self.kind = kind
        self.progress = progress
        self.role = role
        self.partner = partner
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(.kind, TransitionKind.crossDissolve)
        progress = c.lenient(.progress, 0)
        role = c.lenient(.role, "in")
        partner = c.lenient(.partner, 0)
    }

    var isIncoming: Bool { role == "in" }
}

/// One layer of a composed frame, every property already evaluated through
/// the clip's actions.
struct RecipeLayer: Codable, Equatable {
    let clip: UInt32
    let source: RecipeSourceRef
    /// Media pixel size, the shape box, or nil for text (the renderer
    /// measures it).
    let sourceSize: [Double]?
    let crop: CropInsets
    let x: Double
    let y: Double
    let scale: Double
    let rotation: Double
    let opacity: Double
    let cornerRadius: Double
    let shadow: ShadowProps?
    let color: ColorAdjust
    let chroma: ChromaProps?
    let transition: RecipeTransition?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clip = c.lenient(.clip, 0)
        source = c.lenient(.source, RecipeSourceRef.missing)
        sourceSize = c.lenient(.sourceSize)
        crop = c.lenient(.crop, CropInsets.zero)
        x = c.lenient(.x, 0)
        y = c.lenient(.y, 0)
        scale = c.lenient(.scale, 1)
        rotation = c.lenient(.rotation, 0)
        opacity = c.lenient(.opacity, 1)
        cornerRadius = c.lenient(.cornerRadius, 0)
        shadow = c.lenient(.shadow)
        color = c.lenient(.color, ColorAdjust.identity)
        chroma = c.lenient(.chroma)
        transition = c.lenient(.transition)
    }

    /// `sourceSize` as a size; nil for text, whose size only the renderer
    /// knows.
    var sourceSizeCG: CGSize? {
        guard let s = sourceSize, s.count >= 2, s[0] > 0, s[1] > 0 else { return nil }
        return CGSize(width: s[0], height: s[1])
    }

    /// The layer's properties as a `VideoProps`, so the overlay can reuse
    /// `canvasRect` on an evaluated layer instead of the base clip.
    var videoProps: VideoProps {
        VideoProps(
            x: x, y: y, scale: scale, rotation: rotation, opacity: opacity, crop: crop,
            cornerRadius: cornerRadius, shadow: shadow, color: color, chroma: chroma)
    }
}

/// The composed frame at one time: back-to-front layers with everything
/// resolved. Asked once per composed frame and by the canvas overlay for
/// hit-testing and handles.
struct FrameRecipe: Codable, Equatable {
    let t: Ticks
    let canvas: RecipeCanvas
    /// Back to front.
    let layers: [RecipeLayer]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = c.lenient(.t, 0)
        canvas = c.lenient(.canvas, RecipeCanvas())
        layers = c.lenient(.layers, [])
    }

    /// The topmost layer whose canvas rect contains `point` (canvas space,
    /// y down), or nil. Rotation is applied about the layer's anchor, so a
    /// rotated clip hit-tests correctly.
    func layer(at point: CGPoint, measuring textSize: (RecipeLayer) -> CGSize?) -> RecipeLayer? {
        for layer in layers.reversed() {
            guard let size = layer.sourceSizeCG ?? textSize(layer) else { continue }
            let anchor = CGPoint(
                x: Double(canvas.width) / 2 + layer.x, y: Double(canvas.height) / 2 + layer.y)
            let scale = layer.scale
            let full = CGSize(width: size.width * scale, height: size.height * scale)
            let rect = CGRect(
                x: anchor.x - full.width / 2 + layer.crop.l * scale,
                y: anchor.y - full.height / 2 + layer.crop.t * scale,
                width: max(0, full.width - (layer.crop.l + layer.crop.r) * scale),
                height: max(0, full.height - (layer.crop.t + layer.crop.b) * scale))
            let radians = -layer.rotation * .pi / 180
            let dx = point.x - anchor.x
            let dy = point.y - anchor.y
            let local = CGPoint(
                x: anchor.x + dx * cos(radians) - dy * sin(radians),
                y: anchor.y + dx * sin(radians) + dy * cos(radians))
            if rect.contains(local) { return layer }
        }
        return nil
    }
}

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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clip = c.lenient(.clip, 0)
        media = c.lenient(.media, 0)
        sourceIn = c.lenient(.sourceIn, 0)
        sourceDuration = c.lenient(.sourceDuration, 0)
        start = c.lenient(.start, 0)
        duration = c.lenient(.duration, 0)
        pitch = c.lenient(.pitch)
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

/// One composition track: video ids start at 1, audio at 101, and
/// `CompositionBuilder` passes the id as `preferredTrackID` so the recipe
/// can name a track by the same number.
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
    }

    /// `renderSize` as a size; the canvas default when malformed.
    var renderSizeCG: CGSize {
        guard renderSize.count >= 2 else { return CGSize(width: 1920, height: 1080) }
        return CGSize(width: renderSize[0], height: renderSize[1])
    }
}
