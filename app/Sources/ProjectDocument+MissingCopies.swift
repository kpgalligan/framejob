import Foundation

/// The open-time repairs of a project's media, after `project.json` is read
/// and before the document is shown: the re-anchor of consolidated media
/// (`ProjectDocument.reanchoringConsolidatedMedia`) and, here, the re-copy
/// of a WebM or Matroska copy that is gone (spec §11 #228-O, O13 and Q3).
///
/// Neither is an edit. Both run where `readPackage` runs — on
/// NSDocumentController's read queue for a person's File ▸ Open, on the main
/// thread inside `withoutAsking` for an agent's `open_project` — before the
/// document exists as far as AppKit is concerned, so they register no undo
/// step, dirty nothing and show no alert; whatever save comes next writes
/// the new paths out.
extension ProjectDocument {

    /// `readPackage`'s repairs, in order: the re-anchor first, so a
    /// consolidated copy found in the package's `media/` is never copied
    /// again, then the re-copy.
    static func repairingMedia(_ project: ReelProject, package: URL) -> ReelProject {
        let anchored = reanchoringConsolidatedMedia(project, package: package)
        return recopyingMissingCopies(anchored)
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
    /// the main thread, where no watch is passed: there the read is an
    /// agent's `open_project` (MC-5), and the copy blocks the window for its
    /// length (#231). Copies run one at a time (`ContainerRewrap.assist`'s
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
        let shown = Thread.isMainThread ? nil : watch
        var ops: [ReelOp] = []
        for media in project.snapshot.media where media.original != nil {
            let copy = mediaURL(for: media)
            guard copy == nil || copy.map(trashed) == true else { continue }
            guard let source = originalURL(for: media), ContainerRewrap.isMatroska(source) else {
                continue
            }
            guard let descriptor = try? MediaImporter.probeBuiltInCopy(of: source, watch: shown)
            else { continue }
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
