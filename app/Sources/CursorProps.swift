import Foundation

// MARK: - The cursor in the model and the recipe

// The read-only mirror of `core/src/model_cursor.rs` (format 38, spec §11
// CU-30, CU-39) and of the recipe layer's `cursor` key (CU-32). Nothing here
// draws: the compositor's use of `RecipeCursor` is road map creator-jobs
// CU3a2's. Every decode is lenient, the core's defaults standing in for a key
// that does not read, as the other snapshot types do.

/// Which pointer a clip draws: the images the file recorded, or Frame Job's
/// arrow (`video.cursor.style`).
enum CursorStyle: String, Codable, CaseIterable {
    case recorded, arrow
}

/// What a click draws (`video.cursor.clicks`). The core spells "no ripple"
/// `none`, which is `off` here: a case named `none` beside `Optional.none`
/// is a compiler warning.
enum CursorClicks: String, Codable, CaseIterable {
    case off = "none"
    case ripple
}

/// A clip's `video.cursor` (CU-30). `scale` and `clickSize` animate in an
/// action; `show`, `style`, `clicks` and `clickColor` switch at its end;
/// `smoothing` and `hideIdle` are read from the clip's base props only.
struct CursorProps: Codable, Equatable {
    var show: Bool
    /// 0.25…8.
    var scale: Double
    var style: CursorStyle
    /// 0…1 (spec §11 CU-21).
    var smoothing: Double
    /// Seconds, 0.5…30, or nil: never hidden.
    var hideIdle: Double?
    var clicks: CursorClicks
    /// A CSS colour (spec §11 G-12), as stored.
    var clickColor: String
    /// 0.25…4.
    var clickSize: Double

    static let defaultClickColor = "#ffffffcc"

    init(
        show: Bool = true, scale: Double = 1, style: CursorStyle = .recorded,
        smoothing: Double = 0, hideIdle: Double? = nil, clicks: CursorClicks = .off,
        clickColor: String = CursorProps.defaultClickColor, clickSize: Double = 1
    ) {
        self.show = show
        self.scale = scale
        self.style = style
        self.smoothing = smoothing
        self.hideIdle = hideIdle
        self.clicks = clicks
        self.clickColor = clickColor
        self.clickSize = clickSize
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        show = c.lenient(.show, true)
        scale = c.lenient(.scale, 1)
        style = c.lenient(.style, CursorStyle.recorded)
        smoothing = c.lenient(.smoothing, 0)
        hideIdle = c.lenient(.hideIdle)
        clicks = c.lenient(.clicks, CursorClicks.off)
        clickColor = c.lenient(.clickColor, CursorProps.defaultClickColor)
        clickSize = c.lenient(.clickSize, 1)
    }

    /// All eight keys under the model's names, `NSNull` for a nil
    /// `hideIdle`, so a written cursor says every key (`set_video` merges).
    var dictionary: [String: Any] {
        [
            "show": show, "scale": scale, "style": style.rawValue, "smoothing": smoothing,
            "hide_idle": hideIdle.map { $0 as Any } ?? NSNull(), "clicks": clicks.rawValue,
            "click_color": clickColor, "click_size": clickSize,
        ]
    }
}

/// A sparse cursor (road map creator-jobs CU3b, spec §11 CU-38 (b)): only the keys set are
/// written, so the Cursor section's Show cursor writes `{cursor: {show}}` alone — on the base a
/// merge, inside an action an end naming `show`, which switches at the end (CU-30). CU4 adds the
/// section's other keys.
struct CursorPatch: Codable, Equatable {
    var show: Bool?

    init(show: Bool? = nil) {
        self.show = show
    }

    /// The set keys under the model's names.
    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let show { d["show"] = show }
        return d
    }

    var isEmpty: Bool { show == nil }
}

/// A media's `media.cursor` (CU-39): its cursor file, the app's bookmark for
/// it, and whether the movie's own picture already shows the pointer.
struct MediaCursor: Codable, Equatable {
    var path: String
    var bookmark: String?
    var inPicture: Bool

    init(path: String, bookmark: String? = nil, inPicture: Bool) {
        self.path = path
        self.bookmark = bookmark
        self.inPicture = inPicture
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = c.lenient(.path, "")
        bookmark = c.lenient(.bookmark)
        inPicture = c.lenient(.inPicture, false)
    }

    /// Under the model's key names; `bookmark` only when there is one.
    var dictionary: [String: Any] {
        var d: [String: Any] = ["path": path, "in_picture": inPicture]
        if let bookmark = bookmark { d["bookmark"] = bookmark }
        return d
    }
}

/// A recipe layer's `cursor` (CU-32): the media whose cursor file it is, the
/// source tick to read it at (in the stream the clip plays, so a reversed
/// one is mirrored by `ReverseMirror`), the base `smoothing` and `hideIdle`,
/// and the evaluated props. `media` and `at` are required; the rest lenient.
struct RecipeCursor: Codable, Equatable {
    let media: UInt32
    let at: Ticks
    let reversed: Bool
    let smoothing: Double
    let hideIdle: Double?
    let props: CursorProps

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        media = try c.decode(UInt32.self, forKey: .media)
        at = try c.decode(Ticks.self, forKey: .at)
        reversed = c.lenient(.reversed, false)
        smoothing = c.lenient(.smoothing, 0)
        hideIdle = c.lenient(.hideIdle)
        props = c.lenient(.props, CursorProps())
    }
}
