import AppKit

/// File ▸ Rename Graphic…, Delete Graphic… and Restore Graphic Version…
/// (spec §11 G-30; issue #103, issue batch B84): three menu actions, the
/// one place their sheet goes up, and their validator arm. The sheet,
/// `GraphicFileSheetController`, calls the bodies the three tools call
/// (`ProjectDocument+GraphicFiles.swift`); nothing here writes a file or
/// applies an op.
///
/// **Where a sheet opens** (G-30 (d)): Rename and Restore on the graphic of
/// the ONE selected clip when it is a row, else the first; Delete always on
/// the first. `selectedClips` is the open scope's selection.
///
/// **When an item is live** (G-30 (f)): something to list, and for Rename
/// no nest open. `validateGraphicMenuAction`'s default arm forwards here;
/// the frozen file's validator has already answered false with a sheet
/// attached. On every menu open Rename and Delete ask the last scan, and
/// Restore `keptNames()`: file names under `graphics/history/`, no bytes.
extension EditorViewController {

    /// File ▸ Rename Graphic… — `rename_graphic`'s body.
    @objc func renameGraphic(_ sender: Any?) {
        presentGraphicFileSheet(.rename)
    }

    /// File ▸ Delete Graphic… — `delete_graphic`'s body.
    @objc func deleteGraphic(_ sender: Any?) {
        presentGraphicFileSheet(.delete)
    }

    /// File ▸ Restore Graphic Version… — `restore_graphic`'s body, the
    /// newest kept text.
    @objc func restoreGraphicVersion(_ sender: Any?) {
        presentGraphicFileSheet(.restore)
    }

    /// The sheet for `act`, or a beep when the item has nothing to offer.
    func presentGraphicFileSheet(_ act: GraphicFileAct) {
        guard let document = document, GraphicFileSheetController.isOffered(act, in: document)
        else {
            NSSound.beep()
            return
        }
        let choices = GraphicFileSheetController.choices(for: act, in: document)
        let clips = selectedClips
        let selected = clips.count == 1 ? clips[0].graphic?.name : nil
        let sheet = GraphicFileSheetController(
            document: document, act: act, choices: choices,
            opening: GraphicFileSheetController.opening(for: act, selected: selected, in: choices))
        presentAsSheet(sheet)
    }

    /// The menu arm for the three; nil for any other action.
    func validateGraphicFileAction(_ action: Selector) -> Bool? {
        let act: GraphicFileAct
        switch action {
        case #selector(renameGraphic(_:)): act = .rename
        case #selector(deleteGraphic(_:)): act = .delete
        case #selector(restoreGraphicVersion(_:)): act = .restore
        default: return nil
        }
        guard let document = document else { return false }
        return GraphicFileSheetController.isOffered(act, in: document)
    }
}
