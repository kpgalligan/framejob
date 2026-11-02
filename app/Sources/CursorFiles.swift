import Foundation

// MARK: - A project's cursor files

/// One media's cursor file as the compositor reads it (spec §11 CU-33, CU-37): where it is,
/// and what a reversed clip's time is mirrored through — `pivot` the media's model duration,
/// `frame` one frame of its rate (CU-33 (f)).
struct CursorFile: Equatable {
    let url: URL
    let pivot: Ticks
    let frame: Ticks
}

/// What a project's cursor files are and which tracks its clips want (CU-37). Pure over a
/// snapshot but for `cursorURL(for:)`'s bookmark resolution; names no `rc_*`.
enum CursorFiles {
    /// Every media with `cursor` and `in_picture == false`, by id, at `cursorURL(for:)`.
    static func files(of snapshot: ProjectSnapshot) -> [UInt32: CursorFile] {
        var files: [UInt32: CursorFile] = [:]
        for media in snapshot.media {
            guard let cursor = media.cursor, !cursor.inPicture,
                  let url = cursorURL(for: media)
            else { continue }
            files[media.id] = CursorFile(
                url: url, pivot: media.duration, frame: max(media.fps.frameDuration, 1))
        }
        return files
    }

    /// One request per (file, base smoothing) of every clip — top level and every nest —
    /// whose media is in `files`; the smoothing is the clip's base `video.cursor.smoothing`,
    /// 0 without one (CU-30). Deduplicated, sorted by path then smoothing.
    static func requests(of snapshot: ProjectSnapshot, files: [UInt32: CursorFile])
        -> [CursorTrackRequest]
    {
        guard !files.isEmpty else { return [] }
        var wanted = Set<CursorTrackRequest>()
        let clips = snapshot.clips + snapshot.nests.flatMap(\.clips)
        for clip in clips {
            guard let id = clip.source.mediaID, let file = files[id] else { continue }
            wanted.insert(
                CursorTrackRequest(url: file.url, smoothing: clip.video?.cursor?.smoothing ?? 0))
        }
        return wanted.sorted {
            $0.url.path != $1.url.path ? $0.url.path < $1.url.path : $0.smoothing < $1.smoothing
        }
    }
}
