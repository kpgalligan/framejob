import Foundation

// MARK: - Media

/// One imported file. Referenced, never copied: `path` plus a base64
/// `URL.bookmarkData()` that survives a move. `mediaURL(for:)` in
/// `ReelCore.swift` resolves the pair. `original` is the WebM or Matroska
/// file a playable copy was made from (spec §11 #228-O), nil for any other
/// media.
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
    let original: MediaOriginal?

    init(
        id: UInt32, path: String, bookmark: String? = nil, kind: MediaKind = .video,
        duration: Ticks = 0, width: Int = 0, height: Int = 0, fps: Fps = .thirty,
        hasVideo: Bool = true, hasAudio: Bool = false, hasAlpha: Bool = false,
        original: MediaOriginal? = nil
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
        self.original = original
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
        original = c.lenient(.original)
    }

    /// The file's display name, for the Media tab, clip labels, the relink
    /// sheets, Consolidate's messages and the search: the ONE spelling of
    /// it. A copy is named after its original (spec §11 #228-O).
    var name: String { ((original?.path ?? path) as NSString).lastPathComponent }
    /// Pixel size; `.zero` for audio, which has none.
    var pixelSize: CGSize { CGSize(width: width, height: height) }
}
