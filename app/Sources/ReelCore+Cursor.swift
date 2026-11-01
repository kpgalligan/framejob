import AppKit

// The cursor file's wrapper (spec §11 CU-9, CJ-8 (l)): `ReelCursor` over `rc_cursor_open` and
// `rc_cursor_free`. Its typed values are `CursorValues.swift`'s, which names no `rc_*`.

// MARK: - Cursor files

/// A cursor file the core parsed and checked (`RcCursor`, format v1, spec §11 CU-10). An open
/// IS the check: `CursorFileWriter` reads each file back through it before the rename that
/// puts it in place (CU-15). Immutable, so it may be read from any thread.
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
}
