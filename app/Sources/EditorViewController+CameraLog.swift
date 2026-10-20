import AppKit

/// The Camera Log popup's Use LUT… (spec §11 GR-16): a `.cube` chosen in a
/// sheet panel becomes the selected video file's input conversion — Import
/// LUT…'s panel and probe (`EditorViewController+Look.swift`), then ONE
/// grouped edit "Camera Log": `add_media` (a file already in the list is
/// the row it already has) and `set_media_color {lut}`. The agent's mirror is
/// `import_media` then `set_media_color`.
extension EditorViewController {
    @objc func useCameraLogLUT(_ sender: Any?) {
        guard let document = document, let window = view.window,
            let media = document.selectedMedia,
            document.project.snapshot.media(media)?.kind == .video
        else {
            NSSound.beep()
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [MediaImporter.lutType]
        panel.message = "Choose a .cube LUT that converts this file's log footage to Rec. 709."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Self.useCameraLogLUT(from: url, into: document, media: media)
        }
    }

    /// The probe, then the one grouped step; off-event, so grouped
    /// explicitly. A refused file is the document's error sheet.
    static func useCameraLogLUT(from url: URL, into document: ProjectDocument, media: UInt32) {
        MediaImporter.probe(url: url, mayAsk: true) { result in
            do {
                let descriptor = try result.get()
                guard let lut = try backgroundMedia(for: descriptor, in: document.project) else {
                    NSSound.beep()
                    return
                }
                // The media's PQ peak override is kept (spec §11 HD-12).
                let pq = document.project.snapshot.media(media)?.color?.pq
                document.performGroupedEdit(
                    "Camera Log",
                    [.addMedia(descriptor: descriptor),
                     .setMediaColor(media: media, color: MediaColor(lut: lut, pq: pq))])
            } catch {
                document.present(error)
            }
        }
    }
}
