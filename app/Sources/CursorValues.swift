import AppKit

// The cursor file's typed values (spec §11 CU-10, CU-16, CU-17): the header a segment opens
// with, the body `CursorCaptureBuffer` encodes, the anchor and the writer's problem. Names no
// `rc_*` (CJ-8 (l)); the format's specification is `core/src/cursor_file.rs`'s module doc.

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
enum CursorKind: String, Encodable, CaseIterable {
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
