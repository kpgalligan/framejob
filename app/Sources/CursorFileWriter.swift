import AppKit

/// Puts one segment's cursor file beside its movie (spec §11 CU-15): `<stem>.fjcursor`, written
/// as `<stem>.fjcursor.partial`, read back through the core (`ReelCursor`, the open that is
/// the check), and only then renamed into place with `rename(2)`, replacing any file there. A
/// failure leaves neither path and throws a `CursorFileProblem` carrying the core's sentence,
/// which is that segment's `cursorProblem` and never the recording's failure (CU-14). Names
/// no `rc_*` (CJ-8 (l)).
enum CursorFileWriter {
    static let fileExtension = "fjcursor"

    /// `<stem>.fjcursor` beside `movie`.
    static func url(forMovie movie: URL) -> URL {
        movie.deletingPathExtension().appendingPathExtension(fileExtension)
    }

    /// Writes, reads back and renames `body`; answers the file's URL.
    static func write(_ body: Data, forMovie movie: URL) throws -> URL {
        let target = url(forMovie: movie)
        let partial = target.appendingPathExtension("partial")
        let name = target.lastPathComponent
        do {
            try body.write(to: partial)
        } catch {
            discard(partial, target)
            throw CursorFileProblem(
                message: "The cursor file \(name) could not be written: "
                    + error.localizedDescription)
        }
        do {
            _ = try ReelCursor(data: Data(contentsOf: partial))
        } catch {
            discard(partial, target)
            let reason = (error as? ReelCoreError)?.message ?? error.localizedDescription
            throw CursorFileProblem(message: "The cursor file \(name) was not kept: \(reason)")
        }
        guard rename(partial.path, target.path) == 0 else {
            let reason = String(cString: strerror(errno))
            discard(partial, target)
            throw CursorFileProblem(
                message: "The cursor file \(name) could not be put in place: \(reason)")
        }
        return target
    }

    /// Removes both paths, so a failure leaves no file a later import could take for this
    /// movie's.
    private static func discard(_ partial: URL, _ target: URL) {
        try? FileManager.default.removeItem(at: partial)
        try? FileManager.default.removeItem(at: target)
    }
}
