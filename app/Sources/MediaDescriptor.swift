import Foundation

// MARK: - Media descriptors

/// The file a playable copy was made from (spec §11 #228-O): a WebM or
/// Matroska file the built-in copy turned into a `.mov`. The media's own
/// `path` and `bookmark` stay the copy's; these are the original's, which
/// the Media tab names, Reveal in Finder opens and the open-time re-copy
/// copies again.
struct MediaOriginal: Codable, Equatable {
    var path: String
    var bookmark: String?

    init(path: String, bookmark: String? = nil) {
        self.path = path
        self.bookmark = bookmark
    }

    /// The original as `source` is now: its path and a bookmark of it.
    init(of source: URL) {
        self.init(path: source.path, bookmark: bookmarkString(for: source))
    }

    /// Under the model's key names; `bookmark` only when there is one.
    var dictionary: [String: Any] {
        var d: [String: Any] = ["path": path]
        if let bookmark = bookmark { d["bookmark"] = bookmark }
        return d
    }
}

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
    var original: MediaOriginal?

    init(
        path: String, bookmark: String? = nil, kind: MediaKind = .video, duration: Ticks = 0,
        width: Int = 0, height: Int = 0, fps: Fps = .thirty, hasVideo: Bool = false,
        hasAudio: Bool = false, hasAlpha: Bool = false, original: MediaOriginal? = nil
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
        self.original = original
    }

    /// Re-describes an existing entry, for Relink… and for the agent's
    /// echo of what it imported.
    init(_ media: MediaSnapshot) {
        self.init(
            path: media.path, bookmark: media.bookmark, kind: media.kind,
            duration: media.duration, width: media.width, height: media.height, fps: media.fps,
            hasVideo: media.hasVideo, hasAudio: media.hasAudio, hasAlpha: media.hasAlpha,
            original: media.original)
    }

    /// The descriptor under the model's own key names. `bookmark` and
    /// `original` are omitted rather than null when absent, so the core's
    /// serde default applies.
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
        if let original = original { d["original"] = original.dictionary }
        return d
    }

    /// The descriptor as `relink_media`'s `probe`: `dictionary` minus
    /// `path` and `bookmark`, which are the op's own arguments (§11, #63).
    /// It keeps `original`, so a relink records the new file's (#228-O).
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

/// The original a copy was made from, resolved as `mediaURL(for:)` resolves
/// the copy: its bookmark first, its path second. nil when the media has no
/// original or it is gone (spec §11 #228-O).
func originalURL(for media: MediaSnapshot) -> URL? {
    guard let original = media.original else { return nil }
    if let bookmark = original.bookmark, let data = Data(base64Encoded: bookmark) {
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil,
            bookmarkDataIsStale: &stale),
            FileManager.default.fileExists(atPath: url.path) {
            return url
        }
    }
    guard !original.path.isEmpty, FileManager.default.fileExists(atPath: original.path) else {
        return nil
    }
    return URL(fileURLWithPath: original.path)
}

/// What Reveal in Finder shows: the original, or the copy when the original
/// is gone (spec §11 #228-O, O11).
func revealURL(for media: MediaSnapshot) -> URL? {
    originalURL(for: media) ?? mediaURL(for: media)
}

/// Whether `url` lies inside `folder` — strictly: `folder` itself is not
/// inside itself. Pure path arithmetic on the standardized paths.
func isInside(_ url: URL, folder: URL) -> Bool {
    let base = folder.standardizedFileURL.path
    return url.standardizedFileURL.path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
}

/// Whether `url` sits in the Trash of its own volume, where Finder's delete
/// moves a file and its bookmark follows it. The folder is asked of
/// FileManager for `url`'s volume, else for the home volume; false when
/// neither answers. It never lists or writes the Trash.
func isTrashed(_ url: URL) -> Bool {
    let files = FileManager.default
    let trash =
        (try? files.url(
            for: .trashDirectory, in: .userDomainMask, appropriateFor: url, create: false))
        ?? (try? files.url(
            for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
    guard let trash = trash else { return false }
    return isInside(url, folder: trash)
}
