// app/Sources/AgentServer+GraphicFiles.swift — `delete_graphic`,
// `rename_graphic` and `restore_graphic` (issue #103, issue batch B84; spec
// §11 G-27, G-28, G-29): a module of the package's `graphics/` deleted,
// renamed, or one of its kept texts put back, through the three bodies in
// `ProjectDocument+GraphicFiles.swift` — the SAME bodies File ▸ Delete
// Graphic…, Rename Graphic… and Restore Graphic Version… run through their
// sheet (`GraphicFileSheetController.swift`, spec §11 G-30), so the two
// doors refuse in the same sentences.
//
// All three are app-state tools: `project` only from the envelope, no
// `scope`. They run on MAIN — each body ends its file act in ONE
// synchronous `rescan()`, so the registry has compiled what the folder holds
// before the reply is built — and are never called from a
// `.graphicsDidChange` observer (`drain()` is not re-entrant). A file act is
// not undoable and never dirty (G-3); a rename's clips are ONE undo step,
// "Rename Graphic", and Undo renames the file back (G-28 (e)).
//
// `kept` in every answer is the module's kept revisions, newest first
// (G-29 (e)).

import Foundation

extension AgentServer {

    static let keptNote = "not undoable; the text it replaced is kept (the last 10 per module) "
        + "— restore_graphic brings it back"

    /// `delete_graphic` — UI path: File ▸ Delete Graphic…,
    /// `EditorViewController.deleteGraphic(_:)`
    /// (`EditorViewController+GraphicFiles.swift`).
    func deleteGraphic(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let name = try requiredString(a, "name")
        let store = try graphicStore(document)
        let revision = try graphicFileAct { try document.deleteGraphic(named: name) }
        return try jsonResult([
            "ok": true, "name": name, "revision": revision,
            "kept": store.kept(named: name).map(\.revision),
            "note": "not undoable; the deleted text is kept (the last 10 per module) — "
                + "restore_graphic brings it back",
        ])
    }

    /// `rename_graphic` — UI path: File ▸ Rename Graphic…,
    /// `EditorViewController.renameGraphic(_:)`
    /// (`EditorViewController+GraphicFiles.swift`).
    ///
    /// The clips' `set_graphic {name}` ops go through `performGroupedEdit`
    /// as ONE step; with no clip drawn by the module no edit is made.
    func renameGraphic(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let name = try requiredString(a, "name")
        let to = try requiredString(a, "to")
        let store = try graphicStore(document)
        let clips = try graphicFileAct {
            try document.renameGraphic(named: name, to: to) {
                try self.performGroupedEdit(document, "Rename Graphic", $0)
            }
        }
        return try jsonResult([
            "ok": true, "name": to, "renamed_from": name, "clips": clips.map { Int($0) },
            "revision": store.module(named: to)?.revision ?? NSNull(),
            "kept": store.kept(named: to).map(\.revision),
            "note": "the file rename is not an undo step of its own and does not mark the "
                + "project edited; the clips' new name is one step, Rename Graphic, and undo "
                + "of it renames the file back",
        ])
    }

    /// `restore_graphic` — UI path: File ▸ Restore Graphic Version…,
    /// `EditorViewController.restoreGraphicVersion(_:)`
    /// (`EditorViewController+GraphicFiles.swift`), which restores the newest
    /// kept text.
    ///
    /// Answers the compile of the restored text, as `write_graphic` does.
    func restoreGraphic(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let name = try requiredString(a, "name")
        let revision = try stringArg(a, "revision")
        let store = try graphicStore(document)
        let restored = try graphicFileAct {
            try document.restoreGraphic(named: name, revision: revision)
        }
        var result = moduleReport(named: name, document)
        result["name"] = name
        result["restored"] = restored
        result["kept"] = store.kept(named: name).map(\.revision)
        result["note"] = Self.keptNote
        return try jsonResult(result)
    }

    /// A body's `ReelCoreError` as the tool's own error, its sentence kept.
    private func graphicFileAct<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as ReelCoreError {
            throw ToolError(message: error.message)
        }
    }
}
