import Foundation

/// A media whose cursor file could not be drawn (spec §11 CU-37 (c)): its id, the file's path
/// and the reason — the core's sentence, or `CursorTracks`' "the cursor file P could not be
/// read". The clip draws without a cursor and nothing fails; `export_status` answers it as a
/// `cursor_warnings` entry and `render_frame` as a sentence.
struct ExportCursorWarning: Equatable {
    let media: UInt32
    let path: String
    let message: String
}

/// An export's and an offline frame's wait for the cursor tracks they draw (road map
/// creator-jobs CU3a2, spec §11 CU-37 (b)), in `withRampAudio`'s shape: published and wanted
/// on the caller's own `RecipeSource` key before the build, so no frame is composed while a
/// track it needs is still loading.
extension Exporter {
    /// Publishes `project`'s cursor files on `key`, then waits (`CursorTracks.wait` under
    /// owner `key`) for the requests: `at` nil every clip's, top level and every nest
    /// (`CursorFiles.requests`); `at` t only those the recipe at t (with `options`) names through
    /// its layers' `cursor` — the media's file at the layer's base `smoothing`. A
    /// `.failed(path, message)` records one warning per media on that path and waits again
    /// without it; `.cancelled` throws `ExportError.cancelled`. Never main: it blocks. The pin
    /// lasts until `key` is unregistered (`RecipeSource.unregister` releases it, CU-37 (e)).
    static func waitForCursors(
        project: ReelProject, key: Int, at: Ticks?, options: RecipeOptions,
        cancelled: @escaping () -> Bool
    ) throws -> [ExportCursorWarning] {
        let snapshot = project.snapshot
        let files = CursorFiles.files(of: snapshot)
        guard !files.isEmpty else { return [] }
        RecipeSource.shared.setCursorFiles(files, for: key)
        var requests: [CursorTrackRequest]
        if let t = at {
            var wanted = Set<CursorTrackRequest>()
            for layer in project.recipe(at: t, options: options)?.layers ?? [] {
                guard let cursor = layer.cursor, let file = files[cursor.media] else { continue }
                wanted.insert(CursorTrackRequest(url: file.url, smoothing: cursor.smoothing))
            }
            requests = wanted.sorted {
                $0.url.path != $1.url.path
                    ? $0.url.path < $1.url.path : $0.smoothing < $1.smoothing
            }
        } else {
            requests = CursorFiles.requests(of: snapshot, files: files)
        }
        var warnings: [ExportCursorWarning] = []
        while !requests.isEmpty {
            do {
                try CursorTracks.shared.wait(for: requests, owner: key, cancelled: cancelled)
                break
            } catch CursorTracks.WaitError.cancelled {
                throw ExportError.cancelled
            } catch CursorTracks.WaitError.failed(let path, let message) {
                for (media, file) in files.sorted(by: { $0.key < $1.key })
                where file.url.path == path {
                    warnings.append(ExportCursorWarning(media: media, path: path, message: message))
                }
                requests.removeAll { $0.url.path == path }
            }
        }
        return warnings
    }

    /// `render_frame`'s sentence for each warning (CU-37 (c)), in order.
    static func cursorSentences(_ warnings: [ExportCursorWarning]) -> [String] {
        warnings.map { "The cursor of media \($0.media) is not drawn: \($0.message)." }
    }
}
