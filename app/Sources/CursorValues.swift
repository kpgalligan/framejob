import AppKit

// The cursor file's typed values (spec §11 CU-10, CU-16, CU-17): the header a segment opens
// with, the body `CursorCaptureBuffer` encodes, the anchor and the writer's problem; and the
// typed requests and answers of `ReelCursor.query` (CU-25). Names no `rc_*` (CJ-8 (l)); the
// format's specification is `core/src/cursor_file.rs`'s module doc, the vocabulary's
// `core/src/cursor_query.rs`'s.

/// What the recording captured.
enum CursorSourceKind: String, Encodable {
    case display, window, picked
}

/// Whether the file carries the system cursor's images.
enum CursorImageMode: String, Encodable {
    case currentSystem = "current-system"
    case none
}

/// A known system cursor an image equals; the core's closed list, the same raw strings.
enum CursorKind: String, Codable, CaseIterable {
    case arrow, ibeam
    case ibeamVertical = "ibeam_vertical"
    case pointingHand = "pointing_hand"
    case openHand = "open_hand"
    case closedHand = "closed_hand"
    case crosshair
    case operationNotAllowed = "operation_not_allowed"
    case dragCopy = "drag_copy"
    case dragLink = "drag_link"
    case contextualMenu = "contextual_menu"
    case disappearingItem = "disappearing_item"
    case resizeLeft = "resize_left"
    case resizeRight = "resize_right"
    case resizeLeftRight = "resize_left_right"
    case resizeUp = "resize_up"
    case resizeDown = "resize_down"
    case resizeUpDown = "resize_up_down"
}

/// A size in px.
struct CursorPixelSize: Equatable {
    let width: Int
    let height: Int
}

/// The first frame a segment's times count from, named in the header: E2 (the first complete
/// frame) when the frame watch answered, else E1 (the did-start's host time).
struct CursorAnchor: Equatable {
    enum Kind: String, Encodable {
        case e2, e1
    }

    let kind: Kind
    /// Host-clock seconds.
    let host: Double

    /// E2 when given, else E1 (CU-17).
    static func choose(e2: Double?, e1: Double) -> CursorAnchor {
        e2.map { CursorAnchor(kind: .e2, host: $0) } ?? CursorAnchor(kind: .e1, host: e1)
    }
}

/// The stream's geometry: every CU-S2 candidate mapping's inputs.
struct CursorGeometry: Equatable {
    let screenRect: CGRect
    let contentRect: CGRect
    let contentScale: Double
    let scaleFactor: Double
}

/// What a segment's header is made of, known when its movie opens.
struct CursorSegmentStart {
    let inPicture: Bool
    let source: CursorSourceKind
    let displayID: UInt32?
    /// The SCDisplay or SCWindow frame at open, in global points.
    let sourceFrame: CGRect
    let pointSize: CGSize
    let pixelsPerPoint: Double
    let contentSize: CursorPixelSize
    let cursorImage: CursorImageMode
    /// The segment's geometry at open, written at t 0 so every file has an entry.
    let geometry: CursorGeometry
}

/// Format v1's body exactly: snake_case keys, every time integer µs from the movie's first
/// frame, every position and length integer points × 100, sizes in px.
struct CursorFileBody: Encodable {
    struct Moves: Encodable {
        var t: [Int64] = [], x: [Int64] = [], y: [Int64] = []
    }

    struct Image: Encodable {
        let png: String
        let hotX: Int64, hotY: Int64, w: Int64, h: Int64
        let kind: CursorKind?

        enum CodingKeys: String, CodingKey {
            case png, hotX = "hot_x", hotY = "hot_y", w, h, kind
        }
    }

    struct ImageChanges: Encodable {
        var t: [Int64] = [], id: [Int64] = []
    }

    struct Hidden: Encodable {
        var from: [Int64] = [], to: [Int64] = []
    }

    struct Clicks: Encodable {
        var t: [Int64] = [], button: [Int64] = [], down: [Int64] = []
        var x: [Int64] = [], y: [Int64] = [], count: [Int64] = []
    }

    struct Scrolls: Encodable {
        var t: [Int64] = [], x: [Int64] = [], y: [Int64] = [], dx: [Int64] = [], dy: [Int64] = []
    }

    struct Geometry: Encodable {
        let t: Int64
        let screenRect: [Int64], contentRect: [Int64]
        let contentScale: Double, scaleFactor: Double

        enum CodingKeys: String, CodingKey {
            case t, screenRect = "screen_rect", contentRect = "content_rect"
            case contentScale = "content_scale", scaleFactor = "scale_factor"
        }
    }

    struct Dirty: Encodable {
        var t: [Int64] = [], x: [Int64] = [], y: [Int64] = [], w: [Int64] = [], h: [Int64] = []
    }

    struct Shortcuts: Encodable {
        var t: [Int64] = [], keys: [String] = [], code: [Int64] = []
    }

    struct Typed: Encodable {
        var t: [Int64] = []
    }

    struct Keys: Encodable {
        var shortcut = Shortcuts(), typed = Typed()
    }

    let format = "framejob-cursor"
    let version: Int
    let inPicture: Bool
    let source: CursorSourceKind
    let displayID: UInt32?
    let sourceFrame: [Int64]
    let pointSize: [Int64]
    let pixelsPerPoint: Double
    let contentSize: [Int]
    let movieSize: [Int]
    let anchor: CursorAnchor.Kind
    let anchorHostUs: Int64
    let cursorImage: CursorImageMode
    var moves = Moves()
    var images: [Image] = []
    var imageChanges = ImageChanges()
    var hidden = Hidden()
    var clicks = Clicks()
    var scrolls = Scrolls()
    var geometry: [Geometry] = []
    var dirty = Dirty()
    var keys = Keys()

    enum CodingKeys: String, CodingKey {
        case format, version, inPicture = "in_picture", source, displayID = "display_id"
        case sourceFrame = "source_frame", pointSize = "point_size"
        case pixelsPerPoint = "pixels_per_point", contentSize = "content_size"
        case movieSize = "movie_size", anchor, anchorHostUs = "anchor_host_us"
        case cursorImage = "cursor_image", moves, images, imageChanges = "image_changes"
        case hidden, clicks, scrolls, geometry, dirty, keys
    }

    /// The body's bytes. Never throws: a float that is not finite is written as a string, which
    /// the core's read-back refuses by name (CU-14).
    func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return (try? encoder.encode(self)) ?? Data()
    }
}

/// Why a segment's cursor file was not kept: its `cursorProblem` and the landing's note,
/// never the recording's failure (CU-14).
struct CursorFileProblem: Error, Equatable {
    let message: String
}

// MARK: - Queries (CU-25)

/// A `state` request's props: the smoothing (0…1), idle hide in seconds (nil for never), the
/// image's scale, and whether click ripples are answered.
struct CursorStateProps: Encodable, Equatable {
    var smoothing = 0.0
    var hideIdle: Double? = nil
    var scale = 1.0
    var ripples = false

    enum CodingKeys: String, CodingKey {
        case smoothing, hideIdle = "hide_idle", scale, clicks
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(smoothing, forKey: .smoothing)
        try c.encodeIfPresent(hideIdle, forKey: .hideIdle)
        try c.encode(scale, forKey: .scale)
        try c.encode(ripples ? "ripple" : "none", forKey: .clicks)
    }
}

/// The cursor at one source time, in movie pixels.
struct CursorState: Decodable, Equatable {
    struct Image: Decodable, Equatable {
        let id: Int
        let w: Double, h: Double, hotX: Double, hotY: Double
    }

    struct Ripple: Decodable, Equatable {
        let x: Double, y: Double, phase: Double
    }

    let visible: Bool
    let x: Double, y: Double, opacity: Double, pxPerPoint: Double
    let image: Image?
    let ripples: [Ripple]
}

/// One cursor image: its PNG, its size and hot spot in points, the system cursor it equals.
struct CursorImage: Decodable {
    let id: Int
    let png: Data
    let w: Double, h: Double, hotX: Double, hotY: Double
    let kind: CursorKind?
}

/// What an `events` request asks for.
enum CursorEventKind: String, Encodable {
    case clicks, scrolls, shortcuts, typing
}

/// The events in a range; a kind not asked for is nil.
struct CursorEvents: Decodable {
    struct Click: Decodable, Equatable {
        let t: Int64
        let button: Int, down: Int
        let x: Double, y: Double
        let count: Int
    }

    struct Scroll: Decodable, Equatable {
        let t: Int64
        let x: Double, y: Double, dx: Double, dy: Double
    }

    struct Shortcut: Decodable, Equatable {
        let t: Int64
        let keys: String
        let code: Int
    }

    struct Stretch: Decodable, Equatable {
        let from: Int64, to: Int64
        let marks: Int
    }

    let clicks: [Click]?
    let scrolls: [Scroll]?
    let shortcuts: [Shortcut]?
    let typing: [Stretch]?
}

/// A path sampled in source ticks, in movie pixels (VR5's read).
struct CursorPath: Decodable, Equatable {
    let t: [Int64]
    let x: [Double]
    let y: [Double]
}

extension ReelCursor {
    /// Builds and stores the path at `smoothing`; the points it keeps.
    func prepare(smoothing: Double) throws -> Int {
        struct Kept: Decodable { let kept: Int }
        struct Answer: Decodable { let prepared: Kept }
        let answer: Answer = try ask(["prepare": ["smoothing": smoothing]])
        return answer.prepared.kept
    }

    /// Drops the stored path at `smoothing`; whether one was stored.
    func unprepare(smoothing: Double) throws -> Bool {
        let answer: [String: Bool] = try ask(["unprepare": ["smoothing": smoothing]])
        return answer["unprepared"] ?? false
    }

    func state(at: Int64, props: CursorStateProps) throws -> CursorState {
        struct Body: Encodable { let at: Int64, props: CursorStateProps }
        return try ask(["state": Body(at: at, props: props)])
    }

    func image(id: Int) throws -> CursorImage {
        try ask(["image": ["id": id]])
    }

    func events(from: Int64, to: Int64, kinds: [CursorEventKind]) throws -> CursorEvents {
        struct Body: Encodable { let from: Int64, to: Int64, kinds: [CursorEventKind] }
        return try ask(["events": Body(from: from, to: to, kinds: kinds)])
    }

    func path(from: Int64, to: Int64, step: Int64, smoothing: Double) throws -> CursorPath {
        struct Body: Encodable { let from: Int64, to: Int64, step: Int64, smoothing: Double }
        return try ask(["path": Body(from: from, to: to, step: step, smoothing: smoothing)])
    }

    /// One request, encoded and answered through `query`, decoded from snake case.
    private func ask<Body: Encodable, Answer: Decodable>(_ request: [String: Body]) throws
        -> Answer
    {
        let text = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Answer.self, from: Data(try query(text).utf8))
    }
}
