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
/// that knows whether it is about to write — `FFmpegRewrap.convert` does it
/// with `withIntermediateDirectories: true`, and so does
/// `ExportPresetsStore.write`. Building a path must not have the side effect of
/// littering the user's Library with empty folders for features they never
/// used.
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
}
