// app/Sources/ProjectDocument+GraphicFiles.swift — deleting, renaming and
// restoring a module of the document's `graphics/` (spec §11 G-27, G-28,
// G-29; issue #103): the three bodies BOTH doors call — the agent's
// `delete_graphic`, `rename_graphic` and `restore_graphic`
// (`AgentServer+GraphicFiles.swift`) and File ▸ Delete Graphic…, Rename
// Graphic… and Restore Graphic Version… — so the two refuse in the same
// sentences, and the repair that keeps a clip's module name and the file
// together across Undo.
//
// **Every throw of a body's own is a `ReelCoreError`**, its message the
// sentence. The "used" and "drawn" refusals are written here and are not a
// core rule's: each names a file act's precondition.
//
// **A file act is not an undo step and never dirties the document** (G-3):
// only a rename's `set_graphic` ops are model state, applied through the
// caller's `apply` as ONE step. Each body ends its file act in one
// `rescan()`, so it is called from a handler or a command — never from a
// `.graphicsDidChange` or `.projectGraphicsDidChange` observer (`drain()`
// is not re-entrant). Fonts and assets are never touched.

import AppKit
import CryptoKit

extension ProjectDocument {
    /// The clips drawn by the module `name`, one group per container that
    /// holds any: the timeline first (`nest` nil), then the nests by id; ids
    /// ascending. Reads the DOCUMENT, whatever nest is open.
    func graphicClips(named name: String) -> [(nest: UInt32?, clips: [UInt32])] {
        let snapshot = project.snapshot
        func drawn(_ clips: [ClipSnapshot]) -> [UInt32] {
            clips.filter { $0.graphic?.name == name }.map(\.id).sorted()
        }
        var groups: [(nest: UInt32?, clips: [UInt32])] = []
        let timeline = drawn(snapshot.clips)
        if !timeline.isEmpty { groups.append((nil, timeline)) }
        for nest in snapshot.nests.sorted(by: { $0.id < $1.id }) {
            let inside = drawn(nest.clips)
            if !inside.isEmpty { groups.append((nest.id, inside)) }
        }
        return groups
    }

    /// `clips 4 and 9 on the timeline and clip 12 in nest 7`: one group per
    /// container, joined by " and " (G-27 (b)).
    static func graphicClipSentence(_ groups: [(nest: UInt32?, clips: [UInt32])]) -> String {
        groups.map { group in
            let ids = group.clips.map { String($0) }
            let listed = ids.count == 1
                ? "clip \(ids[0])"
                : "clips " + ids.dropLast().joined(separator: ", ") + " and " + ids[ids.count - 1]
            return listed + (group.nest.map { " in nest \($0)" } ?? " on the timeline")
        }.joined(separator: " and ")
    }

    /// Deletes `graphics/<name>.js`, keeping its text (G-27); the kept
    /// revision. Refused while a clip draws the module.
    func deleteGraphic(named name: String) throws -> String {
        let store = try graphicFilesStore()
        guard store.module(named: name) != nil else {
            throw ReelCoreError(message: store.noModuleSentence(name))
        }
        let groups = graphicClips(named: name)
        guard groups.isEmpty else {
            throw ReelCoreError(
                message: "The graphic \"\(name)\" is still drawn by "
                    + Self.graphicClipSentence(groups) + Self.graphicClipAdvice)
        }
        let revision: String
        do {
            revision = try store.removeModule(named: name)
        } catch {
            throw Self.graphicFileFailure(name, "deleted", error)
        }
        store.rescan()
        return revision
    }

    /// Renames the module `name` to `to` (G-28): the file, its kept
    /// revisions, and every clip that names it — `apply` is handed one
    /// `set_graphic {name}` per container, each addressed to its own, to
    /// commit as ONE undo step, and is not called when no clip names the
    /// module. The ids repointed, ascending. When `apply` throws, or leaves
    /// a clip behind, the file is moved back and the journal put back as it
    /// was read before the rename: a refused rename journals no pair (G-28
    /// (d)). A move back that fails leaves the pair, for the repair.
    func renameGraphic(
        named name: String, to: String, apply: ([ReelOp]) throws -> Void
    ) throws -> [UInt32] {
        let store = try graphicFilesStore()
        guard store.module(named: name) != nil else {
            throw ReelCoreError(message: store.noModuleSentence(name))
        }
        guard GraphicStore.isModuleName(to) else {
            throw ReelCoreError(message: GraphicStore.nameSentence(to))
        }
        guard !store.holdsModule(named: to) else {
            throw ReelCoreError(message: "graphics/\(to).js already exists")
        }
        let drawn = graphicClips(named: to)
        guard drawn.isEmpty else {
            throw ReelCoreError(
                message: "The name \"\(to)\" is already drawn by "
                    + Self.graphicClipSentence(drawn) + Self.graphicClipAdvice)
        }
        if let nest = scope {
            throw ReelCoreError(
                message: "rename_graphic has no meaning inside nest \(nest): it renames the "
                    + "module for every clip in the project, the timeline's included. "
                    + "set_scope with no arguments comes back out; then rename.")
        }
        let journalled = GraphicStore.renameJournalBytes(in: store.folderURL)
        do {
            try store.moveModule(from: name, to: to)
        } catch {
            throw Self.graphicFileFailure(name, "renamed", error)
        }
        store.rescan()
        let groups = graphicClips(named: name)
        guard !groups.isEmpty else { return [] }
        let ops = groups.map {
            ReelOp.setGraphicRaw(clips: $0.clips, patch: ["name": to]).scoped($0.nest)
        }
        func moveBack() {
            if (try? store.moveModule(from: to, to: name)) != nil {
                GraphicStore.putBackRenameJournal(journalled, in: store.folderURL)
            }
            store.rescan()
        }
        do {
            try apply(ops)
        } catch {
            moveBack()
            throw error
        }
        guard graphicClips(named: name).isEmpty else {
            moveBack()
            throw ReelCoreError(
                message: "graphics/\(name).js could not be renamed: its clips did not take "
                    + "the new name")
        }
        return groups.flatMap { $0.clips }.sorted()
    }

    /// Writes a kept text of `name` back as `graphics/<name>.js` (G-29):
    /// `revision`, else the newest kept; the revision restored. The text it
    /// replaces is kept by the rescan's pass. Works when the file is absent.
    /// A kept file whose bytes are not the revision in its name is not a
    /// kept text (spec §5.6): refused, nothing written (G-29 (d)).
    func restoreGraphic(named name: String, revision: String?) throws -> String {
        let store = try graphicFilesStore()
        let kept = store.kept(named: name)
        guard var entry = kept.first else {
            throw ReelCoreError(
                message: "No kept revision of \"\(name)\" — one is kept when a write replaces "
                    + "a module's text or delete_graphic removes it")
        }
        if let revision = revision {
            guard let asked = kept.first(where: { $0.revision == revision }) else {
                let listed = kept.map(\.revision).joined(separator: ", ")
                throw ReelCoreError(
                    message: "\"\(name)\" has no kept revision \(revision) — kept: \(listed)")
            }
            entry = asked
        }
        do {
            let bytes = try Data(contentsOf: entry.url)
            guard GraphicStore.hex(SHA256.hash(data: bytes)) == entry.revision else {
                let others = kept.filter { $0 != entry }.map(\.revision)
                throw ReelCoreError(
                    message: "graphics/history/\(name)/\(entry.url.lastPathComponent) was "
                        + "changed outside Frame Job and no longer holds the revision in its "
                        + "name; it is not restored — other kept revisions: "
                        + (others.isEmpty ? "none" : others.joined(separator: ", ")))
            }
            try store.write(name: name, bytes: bytes)
        } catch let error as ReelCoreError {
            throw error
        } catch {
            throw Self.graphicFileFailure(name, "written", error)
        }
        store.rescan()
        return entry.revision
    }

    /// The repair (G-28 (e)), in ONE direction: a journalled pair says the
    /// app last moved the file FROM its first name TO its second, and for
    /// each pair, newest first, when the first name is drawn by a clip, has
    /// no file and has no kept revision, while the second has a file and no
    /// clip, the file is moved back under the first — which journals the
    /// pair the other way round, so Redo is the same repair. One `rescan()`
    /// if anything moved. Never from a pair's first name to its second: a
    /// drawn second name with no file is a removal the app did not make
    /// (G-28 (f)). A file-less name WITH kept revisions is a deleted module
    /// (G-27 (f)) and is left alone. Returns at once when every drawn name
    /// has a file.
    func reconcileGraphicNames() {
        guard let store = graphicStore else { return }
        let snapshot = project.snapshot
        let drawn = Set(
            (snapshot.clips + snapshot.nests.flatMap { $0.clips })
                .compactMap { $0.graphic?.name }.filter(GraphicStore.isModuleName))
        guard drawn.contains(where: { !store.holdsModule(named: $0) }) else { return }
        let folder = store.folderURL
        func onDisk(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(name + ".js").path)
        }
        var moved = false
        for (x, y) in store.renamePairs() {
            guard drawn.contains(x), !onDisk(x),
                store.kept(named: x).isEmpty,
                GraphicStore.isModuleName(y), onDisk(y), !drawn.contains(y),
                (try? store.moveModule(from: y, to: x)) != nil
            else { continue }
            moved = true
        }
        if moved { store.rescan() }
    }

    /// `.projectDocumentDidChange` for this document: every committed change
    /// (an edit, an undo, a redo), never a live gesture's tick.
    @objc func graphicNamesMayHaveChanged(_ note: Notification) {
        guard note.userInfo?["isLive"] as? Bool != true else { return }
        reconcileGraphicNames()
    }

    // MARK: - Sentences

    private static let graphicClipAdvice =
        "; delete those clips or point them at another module (set_graphic {name}) first"

    private func graphicFilesStore() throws -> GraphicStore {
        guard let store = graphicStore else {
            throw ReelCoreError(
                message: "This project has no graphics folder open (its window has not been made)")
        }
        return store
    }

    /// `graphics/<name>.js could not be <verb>: <why>`.
    private static func graphicFileFailure(
        _ name: String, _ verb: String, _ error: Error
    ) -> ReelCoreError {
        ReelCoreError(
            message: "graphics/\(name).js could not be \(verb): \(error.localizedDescription)")
    }
}
