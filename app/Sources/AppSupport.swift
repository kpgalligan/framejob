import Foundation

/// `~/Library/Application Support/Reelcut/` — the ONE place the app spells its
/// own support directory.
///
/// Two things live under it and they arrived a phase apart:
/// `Rewrapped/`, the ffmpeg conversions `FFmpegRewrap` writes (spec §11, and
/// that file's `rewrapDirectory` doc argues at length why they are not in the
/// document package), and `ExportPresets.json`, the named export presets road
/// map 2's phase 7 added. Neither is document state — a `.reelcut` package
/// holds `project.json` and `cache` and drops anything else on the next save —
/// and neither is regenerable from the project, which is the pair of facts
/// that puts both here rather than in the package or in `NSTemporaryDirectory`.
/// A third, `Agent/`, holds the agent server's socket (road map 14, spec §11
/// MC-1, MC-2): a `0700` folder of its own, because its mode is the socket's
/// whole access control and this folder's own mode is left alone (#108).
///
/// **Why it is a type and not two literals.** The path was spelled once, as
/// `FFmpegRewrap.rewrapDirectory`, and privately: a second feature needing the
/// same folder had no way to ask for it and would have written the two
/// components out again. Two spellings of one directory is the drift this
/// project warns about everywhere else — the same reason `MediaPeaks.swift`
/// exists and the same reason `ClipLabel.swift` is the one home of the marker
/// colours. A third caller adds a line here; it does not add a third literal.
///
/// Every accessor answers a PATH and creates nothing but the Application
/// Support root itself, which `FileManager` creates as a side effect of being
/// asked for it. The caller creates the leaf, because the caller is the one
/// that knows whether it is about to write — and it does so through
/// `ensureDirectory`, the ONE creator of this folder and of any folder under
/// it: `0700` at each level it makes, an existing folder left alone (#108).
/// `FFmpegRewrap.convert`, `ExportPresetsStore.write`, `FileStore.write`,
/// `AssistantSpend.record` and `AgentServer.bindSocket` all call it. Building a path must not have the side
/// effect of littering the user's Library with empty folders for features
/// they never used.
enum AppSupport {
    /// The app's folder name inside Application Support. The one literal.
    static let folderName = "Reelcut"

    /// `~/Library/Application Support/Reelcut/`, or nil on the sandboxed or
    /// broken installs where `FileManager` cannot answer. Nil is a refusal
    /// every caller already has to handle: a conversion that cannot be filed
    /// is not attempted, and export presets degrade to none.
    static var directory: URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true)
        else { return nil }
        return support.appendingPathComponent(folderName, isDirectory: true)
    }

    /// A named subdirectory of it — the path only.
    static func subdirectory(_ name: String) -> URL? {
        directory?.appendingPathComponent(name, isDirectory: true)
    }

    /// A file directly inside it — the path only.
    static func file(_ name: String) -> URL? {
        directory?.appendingPathComponent(name, isDirectory: false)
    }

    /// Why `ensureDirectory` could not make a folder, as the sentence itself:
    /// "<path> is not a folder", or `strerror`'s text.
    struct FolderError: LocalizedError, Equatable {
        let reason: String
        var errorDescription: String? { reason }
    }

    /// Makes `url` a folder (#108). It walks up to the nearest existing
    /// ancestor, which must be a folder, then `mkdir(2)`s each missing level
    /// top down at `0700` — never `chmod`ed after, and an existing folder's
    /// mode is left alone, so a person who chose their own keeps it. `EEXIST`
    /// counts as made when the path is now a folder (another writer won the
    /// race); any other errno throws its `strerror` sentence.
    static func ensureDirectory(_ url: URL) throws {
        let manager = FileManager.default
        var missing: [URL] = []
        var level = url.standardizedFileURL
        while true {
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: level.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else {
                    throw FolderError(reason: "\(level.path) is not a folder")
                }
                break
            }
            missing.append(level)
            let parent = level.deletingLastPathComponent().standardizedFileURL
            if parent.path == level.path { break }
            level = parent
        }
        for level in missing.reversed() {
            let made = level.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else {
                    errno = EINVAL
                    return -1
                }
                return mkdir(path, 0o700)
            }
            if made == 0 { continue }
            let code = errno
            var isDirectory: ObjCBool = false
            if code == EEXIST,
                manager.fileExists(atPath: level.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            {
                continue
            }
            throw FolderError(reason: String(cString: strerror(code)))
        }
    }
}
