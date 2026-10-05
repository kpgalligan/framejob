// app/Sources/GraphicStore+Files.swift — the store's own writes into
// `graphics/`: the free-name rule and the module write (road map 10 §5f).
//
// **A name is taken when the scan holds it OR its file is on disk**, so a
// module written from the shell a moment before is never overwritten by a
// stale scan (#75). **A file lands through `land(at:writing:)`**: a
// `.partial` beside it, then moved into place, and on any failure the
// `.partial` is removed. `removeScratchRoot()` removes the untitled root
// (spec §11 G-19 (d)).
//
// **`removeModule` and `moveModule` are the app's delete and rename** (spec
// §11 G-27, G-28), each inside `onQueue` so no pass runs between their
// steps: the first keeps the file's bytes and then removes it, the second
// moves the file, journals the pair and moves its history, and a throw
// part-way leaves the file, the history and the journal where they were.
// Neither rescans.

import CryptoKit
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
        try write(name: name, bytes: Data(source.utf8))
    }

    /// `write(name:source:)` for bytes as they are — a kept revision put
    /// back byte for byte.
    func write(name: String, bytes: Data) throws {
        guard Self.isModuleName(name) else { throw ReelCoreError(message: Self.nameSentence(name)) }
        try ensureFolder()
        writeManual()
        _ = try Self.land(at: folderURL.appendingPathComponent(name + ".js")) {
            try bytes.write(to: $0)
        }
    }

    /// Main. Keeps `<name>.js`'s bytes as its newest kept text, then
    /// removes the file; the kept revision. The caller rescans. A file whose
    /// text could not be kept is not removed (G-27 (c)).
    func removeModule(named name: String) throws -> String {
        try onQueue {
            let url = folderURL.appendingPathComponent(name + ".js")
            let bytes = try Data(contentsOf: url)
            let revision = Self.hex(SHA256.hash(data: bytes))
            Self.keep(bytes, named: name, in: folderURL)
            guard kept(named: name).first?.revision == revision else {
                throw ReelCoreError(
                    message: "its text could not be kept in graphics/"
                        + "\(Self.historyFolderName)/\(name)/")
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                Self.dropKept(revision: revision, named: name, in: folderURL)
                throw error
            }
            return revision
        }
    }

    /// Main. Moves `<from>.js` to `<to>.js`, journals the pair, and moves
    /// its history with it; a throw leaves the file, the history and the
    /// journal where they were. **A rename that could not be journalled is
    /// refused** (G-28 (d)): the pair is written, and read back, before the
    /// history is folded — a fold cannot be undone — so no rename succeeds
    /// that Undo could not repair. When the history then fails to move, the
    /// journal is put back as it was read (its bytes, or no file): a
    /// refused rename journals no pair, and an earlier pair of the same two
    /// names is still there for Undo. A crash between the three steps is
    /// G-28 (f)'s limit. The caller checks the names and rescans.
    func moveModule(from: String, to: String) throws {
        try onQueue {
            let files = FileManager.default
            let source = folderURL.appendingPathComponent(from + ".js")
            let target = folderURL.appendingPathComponent(to + ".js")
            let journalled = Self.renameJournalBytes(in: folderURL)
            try files.moveItem(at: source, to: target)
            Self.recordRename(from, to, in: folderURL)
            guard let newest = renamePairs().first, newest == (from, to) else {
                try? files.moveItem(at: target, to: source)
                throw ReelCoreError(
                    message: "its rename could not be journalled in graphics/"
                        + "\(Self.historyFolderName)/\(Self.renameJournalName)")
            }
            do {
                try Self.moveHistory(from: from, to: to, in: folderURL)
            } catch {
                try? files.moveItem(at: target, to: source)
                Self.putBackRenameJournal(journalled, in: folderURL)
                throw error
            }
        }
    }

    /// The sentence for a module the folder does not hold, naming what it does.
    func noModuleSentence(_ name: String) -> String {
        let held = scan.modules.keys.sorted()
        let listed = held.isEmpty ? "nothing" : held.joined(separator: ", ")
        return "No module named \"\(name)\" in graphics/ — the folder holds: \(listed)"
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
