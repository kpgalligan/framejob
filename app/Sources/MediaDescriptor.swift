import Foundation

// MARK: - Media descriptors

/// A `media[]` element minus its id — what `MediaImporter.probe` produces
/// and `add_media` takes. The host probes the file; the core only stores
/// what came out (§6, §7.7).
struct MediaDescriptor: Equatable {
    var path: String
    var bookmark: String?
    var kind: MediaKind
    var duration: Ticks
    var width: Int
    var height: Int
    var fps: Fps
    var hasVideo: Bool
    var hasAudio: Bool
    var hasAlpha: Bool

    init(
        path: String, bookmark: String? = nil, kind: MediaKind = .video, duration: Ticks = 0,
        width: Int = 0, height: Int = 0, fps: Fps = .thirty, hasVideo: Bool = false,
        hasAudio: Bool = false, hasAlpha: Bool = false
    ) {
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

    /// Re-describes an existing entry, for Relink… and for the agent's
    /// echo of what it imported.
    init(_ media: MediaSnapshot) {
        self.init(
            path: media.path, bookmark: media.bookmark, kind: media.kind,
            duration: media.duration, width: media.width, height: media.height, fps: media.fps,
            hasVideo: media.hasVideo, hasAudio: media.hasAudio, hasAlpha: media.hasAlpha)
    }

    /// The descriptor under the model's own key names. `bookmark` is omitted
    /// rather than null when absent, so the core's serde default applies.
    var dictionary: [String: Any] {
        var d: [String: Any] = [
            "path": path,
            "kind": kind.rawValue,
            "duration": duration,
            "width": width,
            "height": height,
            "fps": [fps.num, fps.den],
            "has_video": hasVideo,
            "has_audio": hasAudio,
            "has_alpha": hasAlpha,
        ]
        if let bookmark = bookmark { d["bookmark"] = bookmark }
        return d
    }

    /// The descriptor as `relink_media`'s `probe`: `dictionary` minus
    /// `path` and `bookmark`, which are the op's own arguments (§11, #63).
    var probeDictionary: [String: Any] {
        var d = dictionary
        d.removeValue(forKey: "path")
        d.removeValue(forKey: "bookmark")
        return d
    }
}

// MARK: - Media files

/// Resolves a media entry to a file URL: the bookmark first (it survives a
/// move or a rename), the stored path as the fallback. NO security scope —
/// the app is not sandboxed (§11), so a resolved URL is usable as is and
/// there is nothing to stop accessing.
///
/// nil means the file is gone: the clip draws a missing slate and Relink…
/// is offered.
func mediaURL(for media: MediaSnapshot) -> URL? {
    if let bookmark = media.bookmark, let data = Data(base64Encoded: bookmark) {
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil,
            bookmarkDataIsStale: &stale),
            FileManager.default.fileExists(atPath: url.path) {
            return url
        }
    }
    guard !media.path.isEmpty, FileManager.default.fileExists(atPath: media.path) else {
        return nil
    }
    return URL(fileURLWithPath: media.path)
}

/// The base64 bookmark the model stores beside a path. nil when the URL
/// cannot be bookmarked (an unreachable volume), which is not an error —
/// the path alone still opens the file today.
func bookmarkString(for url: URL) -> String? {
    let data = try? url.bookmarkData(
        options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    return data?.base64EncodedString()
}
