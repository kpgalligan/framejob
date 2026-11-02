import Foundation

/// A movie's cursor file at import and relink (road map creator-jobs CU3b, spec §11 CU-34,
/// CU-38): the header read, the attach check, the look beside a probed movie, and the relink
/// rule. A file is attached only when it opens through `ReelCursor` (the open is the check,
/// CU-15) and its `movie_size` equals the probe's `width` × `height`. Await-free and names no
/// `rc_*` (CJ-8 (l)).
extension MediaImporter {
    /// The three header keys the attach reads; the rest of the body is the core's to check.
    struct CursorFileHeader: Decodable, Equatable {
        let inPicture: Bool
        let movieSize: [Int]
        let cursorImage: String

        enum CodingKeys: String, CodingKey {
            case inPicture = "in_picture"
            case movieSize = "movie_size"
            case cursorImage = "cursor_image"
        }
    }

    /// What an attached file gives its media and its recording segment: `media.cursor`
    /// (CU-34 (b)) and the header's `cursor_image`.
    struct CursorAttachment: Equatable {
        let cursor: MediaCursor
        let image: CursorImageMode?
    }

    /// Opens `file` through `ReelCursor(data:)` (the check), then decodes its header, and
    /// attaches it to `descriptor` only when that is a video with pictures whose `width` ×
    /// `height` equal `movie_size` (CU-34). The failure is a sentence naming the file.
    static func cursorAttachment(at file: URL, to descriptor: MediaDescriptor)
        -> Result<CursorAttachment, CursorFileProblem>
    {
        let name = file.lastPathComponent
        let body: Data
        do {
            body = try Data(contentsOf: file)
        } catch {
            return .failure(
                CursorFileProblem(
                    message: "The cursor file \(name) could not be read: "
                        + "\(error.localizedDescription)."))
        }
        do {
            _ = try ReelCursor(data: body)
        } catch {
            let reason = (error as? ReelCoreError)?.message ?? error.localizedDescription
            return .failure(
                CursorFileProblem(message: "The cursor file \(name) was not attached: \(reason)"))
        }
        let header: CursorFileHeader
        do {
            header = try JSONDecoder().decode(CursorFileHeader.self, from: body)
        } catch {
            return .failure(
                CursorFileProblem(
                    message: "The cursor file \(name) could not be read: "
                        + "\(error.localizedDescription)."))
        }
        guard descriptor.kind == .video, descriptor.hasVideo else {
            let movie = URL(fileURLWithPath: descriptor.path).lastPathComponent
            return .failure(
                CursorFileProblem(
                    message: "The cursor file \(name) was not attached: \(movie) has no picture."))
        }
        guard header.movieSize == [descriptor.width, descriptor.height] else {
            let stored = header.movieSize.map(String.init).joined(separator: " × ")
            return .failure(
                CursorFileProblem(
                    message: "The cursor file \(name) was not attached: its movie_size is "
                        + "\(stored) and the movie is \(descriptor.width) × "
                        + "\(descriptor.height)."))
        }
        let cursor = MediaCursor(
            path: file.path, bookmark: bookmarkString(for: file), inPicture: header.inPicture)
        return .success(
            CursorAttachment(cursor: cursor, image: CursorImageMode(rawValue: header.cursorImage)))
    }

    /// `descriptor` with `cursor` from `<stem>.fjcursor` beside `movie` when that file exists
    /// and attaches (CU-34 (a)); otherwise `descriptor` unchanged, and nothing said.
    static func withCursorBeside(_ descriptor: MediaDescriptor, movie: URL) -> MediaDescriptor {
        let file = CursorFileWriter.url(forMovie: movie)
        guard FileManager.default.fileExists(atPath: file.path),
            case .success(let attachment) = cursorAttachment(at: file, to: descriptor)
        else { return descriptor }
        var attached = descriptor
        attached.cursor = attachment.cursor
        return attached
    }

    /// A probed relink's descriptor (CU-38 (a)): `probed` when it carries a cursor (the file
    /// beside the new movie); else, for a video probe with pictures whose `width` × `height`
    /// equal `current`'s, `probed` with `current.cursor` verbatim when `cursorURL(for:)` names a
    /// file that exists; else `probed`, whose missing cursor clears the stored one (CU-39). No
    /// parse — sizes and a file-exists check — so it may run on main.
    static func relinkProbe(_ probed: MediaDescriptor, current: MediaSnapshot?) -> MediaDescriptor
    {
        guard probed.cursor == nil, let current, let kept = current.cursor,
            probed.kind == .video, probed.hasVideo,
            probed.width == current.width, probed.height == current.height,
            let file = cursorURL(for: current),
            FileManager.default.fileExists(atPath: file.path)
        else { return probed }
        var keeping = probed
        keeping.cursor = kept
        return keeping
    }
}
