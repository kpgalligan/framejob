// app/Sources/GraphicStore+Files.swift — the store's own writes into
// `graphics/`: the free-name rule and the module write (road map 10 §5f).
//
// **A name is taken when the scan holds it OR its file is on disk**, so a
// module written from the shell a moment before is never overwritten by a
// stale scan (#75). **A file lands through `land(at:writing:)`**: a
// `.partial` beside it, then moved into place, and on any failure the
// `.partial` is removed. `removeScratchRoot()` removes the untitled root
// (spec §11 G-19 (d)).

import Foundation

extension GraphicStore {
    /// `base` when no module of that name is held, else `base-2`,
    /// `base-3`, … — `base` cut to 60 scalars first, so a suffix fits.
    func uniqueModuleName(_ base: String) -> String {
        let root = String(String.UnicodeScalarView(base.unicodeScalars.prefix(60)))
        guard holdsModule(named: root) else { return root }
        var n = 2
        while holdsModule(named: "\(root)-\(n)") { n += 1 }
        return "\(root)-\(n)"
    }

    /// True when the scan holds `name` or `<name>.js` is on disk.
    func holdsModule(named name: String) -> Bool {
        scan.modules[name] != nil
            || FileManager.default.fileExists(
                atPath: folderURL.appendingPathComponent(name + ".js").path)
    }

    /// The app's own write: `<name>.js.partial`, then moved into place, so
    /// a reader never sees half a module.
    func write(name: String, source: String) throws {
        guard Self.isModuleName(name) else { throw ReelCoreError(message: Self.nameSentence(name)) }
        try ensureFolder()
        writeManual()
        _ = try Self.land(at: folderURL.appendingPathComponent(name + ".js")) {
            try Data(source.utf8).write(to: $0)
        }
    }

    /// Writes `<target>.partial` through `write` (any stale one removed
    /// first), then replaces `target` with it, or moves it into place when
    /// there is none. On any throw the partial is removed and the error
    /// rethrown. Whether it replaced.
    static func land(at target: URL, writing write: (URL) throws -> Void) throws -> Bool {
        let files = FileManager.default
        let partial = target.deletingLastPathComponent()
            .appendingPathComponent(target.lastPathComponent + ".partial")
        try? files.removeItem(at: partial)
        do {
            try write(partial)
            if files.fileExists(atPath: target.path) {
                _ = try files.replaceItemAt(target, withItemAt: partial)
                return true
            }
            try files.moveItem(at: partial, to: target)
            return false
        } catch {
            try? files.removeItem(at: partial)
            throw error
        }
    }

    /// Main, after `stop()`: the untitled root is removed; a package's
    /// `graphics/` is never touched (G-14, G-19 (d)).
    func removeScratchRoot() {
        guard package == nil else { return }
        try? FileManager.default.removeItem(at: folderURL)
    }
}
