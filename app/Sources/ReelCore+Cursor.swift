import AppKit

// The cursor file's wrapper (spec §11 CU-9, CJ-8 (l)): `ReelCursor` over `rc_cursor_open`,
// `rc_cursor_free` and `rc_cursor_query`. Its typed values and typed requests are
// `CursorValues.swift`'s, which names no `rc_*`.

// MARK: - Cursor files

/// A cursor file the core parsed and checked (`RcCursor`, format v1, spec §11 CU-10). An open
/// IS the check: `CursorFileWriter` reads each file back through it before the rename that
/// puts it in place (CU-15). The core holds its prepared paths under a lock, so any thread may
/// query it (CU-25).
final class ReelCursor {
    /// The newest cursor file the core reads, and the version `CursorCaptureBuffer` writes.
    static let fileVersion = Int(RC_CURSOR_FILE_VERSION)
    private let handle: OpaquePointer

    /// Parses and checks `data`; throws the core's sentence.
    init(data: Data) throws {
        var err: UnsafeMutablePointer<CChar>? = nil
        let made = withNonNullBytes(data) { rc_cursor_open($0, $1, &err) }
        guard let made else {
            throw ReelCoreError(message: takeErrorMessage(err, fallback: "it could not be read"))
        }
        handle = made
    }

    deinit { rc_cursor_free(handle) }

    /// One JSON request against this track (`core/src/cursor_query.rs`'s vocabulary, CU-25);
    /// the answer's JSON, or throws the core's sentence. `project` is for the planners to come.
    func query(_ requestJSON: String, project: ReelProject? = nil) throws -> String {
        var err: UnsafeMutablePointer<CChar>? = nil
        let tracks: [OpaquePointer?] = [handle]
        let answer = withExtendedLifetime(project) {
            tracks.withUnsafeBufferPointer {
                rc_cursor_query($0.baseAddress, 1, project?.ptr, requestJSON, &err)
            }
        }
        guard let text = takeString(answer) else {
            throw ReelCoreError(message: takeErrorMessage(err, fallback: "it was not answered"))
        }
        return text
    }

    /// One JSON request against `tracks` together, with `project` — `plan_zooms` (spec §11
    /// CU-70), whose `tracks[i]` is the cursor track of its `clips[i]` (a media used twice is
    /// passed twice). The answer's JSON, or throws the core's sentence.
    static func query(_ requestJSON: String, tracks: [ReelCursor], project: ReelProject) throws
        -> String
    {
        var err: UnsafeMutablePointer<CChar>? = nil
        let handles: [OpaquePointer?] = tracks.map { $0.handle }
        let answer = withExtendedLifetime((tracks, project)) {
            handles.withUnsafeBufferPointer {
                rc_cursor_query($0.baseAddress, handles.count, project.ptr, requestJSON, &err)
            }
        }
        guard let text = takeString(answer) else {
            throw ReelCoreError(message: takeErrorMessage(err, fallback: "it was not answered"))
        }
        return text
    }
}
