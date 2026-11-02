import Foundation

/// The open-time repairs of a project's media, after `project.json` is read
/// and before the document is shown: the re-anchor of consolidated media
/// (`ProjectDocument.reanchoringConsolidatedMedia`) and, here, the re-copy
/// of a WebM or Matroska copy that is gone (spec §11 #228-O, O13 and Q3).
///
/// Neither is an edit. Both run where `readPackage` runs — on
/// NSDocumentController's read queue for a person's File ▸ Open, on the
/// lane's thread inside `withoutAsking` for an agent's `open_project` (spec
/// §11 #231), on the main thread for a read AppKit runs there — before the
/// document exists as far as AppKit is concerned, so they register no undo
/// step, dirty nothing and show no alert; whatever save comes next writes
/// the new paths out.
extension ProjectDocument {

    /// `readPackage`'s repairs, in order: the re-anchor first, so a
    /// consolidated copy found in the package's `media/` is never copied
    /// again, then the cursor files' re-anchor (spec §11 CU-52), then the
    /// re-copy.
    static func repairingMedia(_ project: ReelProject, package: URL) -> ReelProject {
        let anchored = reanchoringConsolidatedMedia(project, package: package)
        let cursors = reanchoringCursorFiles(anchored, package: package)
        return recopyingMissingCopies(cursors)
    }

    /// Points each media's cursor file at the package's `media/` when it was
    /// consolidated there and the package has moved (road map creator-jobs
    /// CU5, spec §11 CU-52): a `media.cursor` whose `cursorURL(for:)` names no
    /// file, while `<package>/media/<its path's last component>` exists, gets
    /// `set_media_cursor {path: that file, in_picture}` — no bookmark, as
    /// Consolidate writes it. Applied purely, as the media re-anchor is.
    static func reanchoringCursorFiles(_ project: ReelProject, package: URL) -> ReelProject {
        // `media/`, `ProjectDocument`'s private `mediaDirectoryName`, which this
        // extension in another file cannot read (`ProjectDocument.swift` takes
        // no line for CU5).
        let directory = package.appendingPathComponent("media", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return project }
        var ops: [ReelOp] = []
        for media in project.snapshot.media {
            guard let cursor = media.cursor, let file = cursorURL(for: media),
                !FileManager.default.fileExists(atPath: file.path)
            else { continue }
            let name = (cursor.path as NSString).lastPathComponent
            guard !name.isEmpty else { continue }
            let candidate = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            ops.append(
                .setMediaCursor(
                    media: media.id,
                    cursor: MediaCursor(path: candidate.path, inPicture: cursor.inPicture)))
        }
        guard !ops.isEmpty else { return project }
        // Only `.applied` is a repair; both other arms leave it as opened.
        return (try? project.applying(ops)).project ?? project
    }

    /// Copies again every WebM or Matroska copy that is gone, from its
    /// original, and points the media at the new copy with its probe.
    ///
    /// A media is copied again when all four hold: its copy is gone —
    /// `mediaURL(for:)` resolves nothing, or resolves inside the Trash
    /// (`trashed`), where Finder's delete moves the copy and its bookmark
    /// follows it; it has an `original`; the original resolves; and the
    /// original is still a Matroska file. The copy is the built-in one only
    /// (`MediaImporter.probeBuiltInCopy`): never ffmpeg, never a question.
    /// The Trash counts as gone HERE only; every other reader of
    /// `mediaURL(for:)` still plays a copy from the Trash.
    ///
    /// Each copy shows #228-P's window after 1 s through `watch`, except on
    /// the main thread, where a window could not be shown, and inside
    /// `withoutAsking`, an agent's `open_project` (MC-5, #231): no watch is
    /// passed there. Copies run one at a time (`ContainerRewrap.assist`'s
    /// lock). A Cancel or any failure skips that media (Q3): a missing copy
    /// stays missing, with the slate, the badge and Relink…, and the next
    /// open tries again; a copy in the Trash keeps its path and bookmark.
    ///
    /// `trashed` is the probe's seam, so the Trash case is proved without
    /// touching the real Trash; the app passes none.
    static func recopyingMissingCopies(
        _ project: ReelProject, watch: RewrapWatch? = RewrapProgressWindowController.watch,
        trashed: (URL) -> Bool = isTrashed
    ) -> ReelProject {
        let shown = Thread.isMainThread || MediaImporter.isWithoutAsking ? nil : watch
        var ops: [ReelOp] = []
        for media in project.snapshot.media where media.original != nil {
            let copy = mediaURL(for: media)
            guard copy == nil || copy.map(trashed) == true else { continue }
            guard let source = originalURL(for: media), ContainerRewrap.isMatroska(source) else {
                continue
            }
            guard let copied = try? MediaImporter.probeBuiltInCopy(of: source, watch: shown)
            else { continue }
            let descriptor = MediaImporter.relinkProbe(copied, current: media)  // CU-38 (a)
            ops.append(
                .relinkMedia(
                    media: media.id, path: descriptor.path, bookmark: descriptor.bookmark,
                    probe: descriptor))
        }
        guard !ops.isEmpty else { return project }
        // Only `.applied` is a repair; both other arms leave it as opened.
        return (try? project.applying(ops)).project ?? project
    }
}
