// app/Sources/GraphicStore+History.swift — the kept revisions of a
// document's modules and the rename journal (spec §11 G-27, G-28, G-29).
//
// **On disk**, inside `graphics/`:
// `history/<name>/<%06d sequence>-<revision>.js` is one kept text — the next
// sequence is the highest plus one, and any other file there is ignored —
// and `history/renames.json` is a JSON array of `[a, b]` pairs (the app
// moved the file FROM `a` TO `b`; the repair only ever moves it back, G-28
// (e)), oldest first, at most `renameJournalLimit`, a repeated unordered
// pair moved to the end. Both are user content carried by every save (spec
// §5.6), never a cache.
//
// **`history/` is created only inside an existing `graphics/`** (G-14:
// `ensureFolder()` stays the one creator of the folder), with no
// `packageContentsDidChangeOnDisk()` call — `fonts/`'s precedent in
// `GraphicStore+Import.swift`.
//
// **History never holds the current text.** `keepReplaced`, which a pass
// calls on the store's queue before it stores its scan, keeps the bytes a
// module's new text replaced and drops the new text's own revision; a
// text kept twice is listed once, and the lowest sequences past
// `historyLimit` are pruned. Nothing is kept at `start()`, for a removal
// the app did not make, or for a text that came and went inside one pass;
// `start()` DROPS each module's current revision from its history (a text
// put back while the project was closed), which is a drop and not a keep.
//
// **A file-less name with kept revisions is a DELETED module** (G-27 (f);
// a rename killed part-way leaves the same state: G-28 (f)): `moveHistory`
// leaves no `history/<from>/` behind, which is what makes that test sound
// for `ProjectDocument.reconcileGraphicNames()`.

import CryptoKit
import Foundation

/// One kept text of a module: its revision (G-13), its place in the
/// module's history and its file.
struct GraphicKept: Equatable {
    let revision: String, sequence: Int, url: URL
}

extension GraphicStore {
    static let historyFolderName = "history", renameJournalName = "renames.json"
    static let historyLimit = 10, renameJournalLimit = 32

    // MARK: - Reading (main)

    /// The kept texts of `name`, newest first, read from the disk; empty
    /// for a name that is not a module name.
    func kept(named name: String) -> [GraphicKept] {
        Array(Self.keptEntries(named: name, in: folderURL).reversed())
    }

    /// The names holding at least one kept text, sorted — deleted modules
    /// included.
    func keptNames() -> [String] {
        let history = folderURL.appendingPathComponent(Self.historyFolderName, isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: history.path)) ?? []
        return names.filter { !Self.keptEntries(named: $0, in: folderURL).isEmpty }.sorted()
    }

    /// The journalled renames, newest first.
    func renamePairs() -> [(String, String)] {
        Self.journal(in: folderURL).reversed().map { ($0[0], $0[1]) }
    }

    // MARK: - Writing (the store's queue, or main inside `onQueue`)

    /// Keeps `bytes` as the newest text of `name`: an entry already holding
    /// that revision is removed first, then the lowest sequences past
    /// `historyLimit` are pruned. Nothing unless `folder` exists.
    static func keep(_ bytes: Data, named name: String, in folder: URL) {
        let files = FileManager.default
        guard isModuleName(name), files.fileExists(atPath: folder.path) else { return }
        let directory = historyDirectory(of: name, in: folder)
        try? files.createDirectory(at: directory, withIntermediateDirectories: true)
        let revision = hex(SHA256.hash(data: bytes))
        let entries = keptEntries(named: name, in: folder)
        let next = (entries.last?.sequence ?? 0) + 1
        do {
            try bytes.write(
                to: directory.appendingPathComponent(entryName(next, revision)), options: .atomic)
        } catch {
            return
        }
        tidy(name, in: folder)
    }

    /// Removes every kept entry of `name` holding `revision`.
    static func dropKept(revision: String, named name: String, in folder: URL) {
        for entry in keptEntries(named: name, in: folder) where entry.revision == revision {
            try? FileManager.default.removeItem(at: entry.url)
        }
        removeIfEmpty(historyDirectory(of: name, in: folder))
    }

    /// One pass's history work, file work only: for every name in BOTH
    /// scans whose revision differs, the old scan's bytes are kept; for
    /// every name whose revision is new or changed, the current revision is
    /// dropped from its history.
    static func keepReplaced(from last: GraphicScan, to found: GraphicScan, in folder: URL) {
        for (name, module) in found.modules.sorted(by: { $0.key < $1.key }) {
            let old = last.modules[name]
            guard old?.revision != module.revision else { continue }
            if let old = old { keep(old.bytes, named: name, in: folder) }
            dropKept(revision: module.revision, named: name, in: folder)
        }
    }

    /// `from`'s entries appended, in order, after `to`'s highest sequence,
    /// then pruned; `history/<from>/` is gone afterwards. A throw leaves
    /// both histories as they were.
    static func moveHistory(from: String, to: String, in folder: URL) throws {
        let files = FileManager.default
        let source = historyDirectory(of: from, in: folder)
        guard files.fileExists(atPath: source.path) else { return }
        let target = historyDirectory(of: to, in: folder)
        guard files.fileExists(atPath: target.path) else {
            try files.moveItem(at: source, to: target)
            return
        }
        var sequence = keptEntries(named: to, in: folder).last?.sequence ?? 0
        var moved: [(from: URL, to: URL)] = []
        do {
            for entry in keptEntries(named: from, in: folder) {
                sequence += 1
                let landed = target.appendingPathComponent(entryName(sequence, entry.revision))
                try files.moveItem(at: entry.url, to: landed)
                moved.append((entry.url, landed))
            }
            try files.removeItem(at: source)
        } catch {
            for pair in moved.reversed() { try? files.moveItem(at: pair.to, to: pair.from) }
            throw error
        }
        tidy(to, in: folder)
    }

    /// Journals a rename: the pair appended, an earlier entry of the same
    /// unordered pair removed, the oldest dropped past `renameJournalLimit`.
    /// Nothing unless `folder` exists.
    static func recordRename(_ a: String, _ b: String, in folder: URL) {
        let files = FileManager.default
        guard files.fileExists(atPath: folder.path) else { return }
        var pairs = journal(in: folder).filter { Set($0) != Set([a, b]) }
        pairs.append([a, b])
        pairs = Array(pairs.suffix(renameJournalLimit))
        let history = folder.appendingPathComponent(historyFolderName, isDirectory: true)
        try? files.createDirectory(at: history, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: pairs) else { return }
        try? data.write(to: renameJournalURL(in: folder), options: .atomic)
    }

    /// `history/renames.json` as it is on disk: its bytes, or nil when
    /// there is no file.
    static func renameJournalBytes(in folder: URL) -> Data? {
        try? Data(contentsOf: renameJournalURL(in: folder))
    }

    /// Puts the journal back as `renameJournalBytes` read it: those bytes,
    /// or no file — what a rename refused after its pair was written does,
    /// at the fold (`moveModule`) or at the clips (`renameGraphic`'s move
    /// back), so a refused act journals nothing (G-28 (d)).
    static func putBackRenameJournal(_ bytes: Data?, in folder: URL) {
        let url = renameJournalURL(in: folder)
        if let bytes = bytes {
            try? bytes.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - The files

    private static func renameJournalURL(in folder: URL) -> URL {
        folder.appendingPathComponent(historyFolderName, isDirectory: true)
            .appendingPathComponent(renameJournalName)
    }

    /// `history/<name>/` inside `folder`.
    static func historyDirectory(of name: String, in folder: URL) -> URL {
        folder.appendingPathComponent(historyFolderName, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    private static func entryName(_ sequence: Int, _ revision: String) -> String {
        String(format: "%06d", sequence) + "-" + revision + ".js"
    }

    /// The kept entries of `name`, oldest first: every
    /// `<sequence>-<64 hex digits>.js` in its directory.
    private static func keptEntries(named name: String, in folder: URL) -> [GraphicKept] {
        guard isModuleName(name) else { return [] }
        let directory = historyDirectory(of: name, in: folder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var entries: [GraphicKept] = []
        for file in names where file.hasSuffix(".js") {
            let parts = file.dropLast(3).split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 2, let sequence = Int(parts[0]), sequence > 0,
                parts[1].count == 64, parts[1].allSatisfy({ "0123456789abcdef".contains($0) })
            else { continue }
            entries.append(GraphicKept(
                revision: String(parts[1]), sequence: sequence,
                url: directory.appendingPathComponent(file)))
        }
        return entries.sorted { $0.sequence < $1.sequence }
    }

    /// One revision once (its highest sequence), then at most
    /// `historyLimit` entries, the lowest sequences removed.
    private static func tidy(_ name: String, in folder: URL) {
        let files = FileManager.default
        var seen = Set<String>()
        var newestFirst: [GraphicKept] = []
        for entry in keptEntries(named: name, in: folder).reversed() {
            if seen.insert(entry.revision).inserted {
                newestFirst.append(entry)
            } else {
                try? files.removeItem(at: entry.url)
            }
        }
        for entry in newestFirst.dropFirst(historyLimit) { try? files.removeItem(at: entry.url) }
    }

    private static func removeIfEmpty(_ directory: URL) {
        let files = FileManager.default
        guard let names = try? files.contentsOfDirectory(atPath: directory.path), names.isEmpty
        else { return }
        try? files.removeItem(at: directory)
    }

    /// The journal as written: every element that is a pair of strings.
    private static func journal(in folder: URL) -> [[String]] {
        guard let data = renameJournalBytes(in: folder),
            let pairs = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return [] }
        return pairs.compactMap { $0 as? [String] }.filter { $0.count == 2 }
    }
}
