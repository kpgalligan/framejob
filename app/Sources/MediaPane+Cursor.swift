import AppKit
import UniformTypeIdentifiers

/// The Media tab's **Cursor** section (road map creator-jobs CU5, spec §11
/// CU-54): the cursor file of the video selected in the list — its name, or
/// that it is missing — with **Locate…**, which attaches a `.fjcursor` file
/// through the import's own check (`MediaImporter.cursorAttachment`, CU-34)
/// as one step "Locate Cursor File", and **Remove**, which clears it, "Remove
/// Cursor File". It is there once the project has a video media with a
/// picture (`MediaPane.makeSections`), so Locate… stays reachable after the
/// last Remove, and acts on `selectedMedia`, the row a click selects. The
/// agent's mirror is the `set_media_cursor` tool (`AgentServer+Cursor.swift`),
/// which runs the same check.
extension MediaPane {
    func cursorSection() -> InspectorSection {
        let binding = self.binding
        /// The selected row when it is a video with a picture.
        func selected() -> MediaSnapshot? {
            guard let id = binding.document?.selectedMedia,
                let media = binding.documentSnapshot.media(id),
                MediaPane.takesCursor(media)
            else { return nil }
            return media
        }
        let locate = OptionButtonControl(
            title: "Locate…",
            action: { [weak self] in
                guard let media = selected() else { return }
                self?.locateCursor(media)
            },
            enabled: { selected() != nil },
            onEdit: { binding.edited() })
        locate.toolTip = "Choose the .fjcursor file recorded with this movie"
        let remove = OptionButtonControl(
            title: "Remove",
            action: {
                guard let media = selected(), media.cursor != nil else { return }
                binding.apply(
                    "Remove Cursor File", [.setMediaCursor(media: media.id, cursor: nil)])
            },
            enabled: { selected()?.cursor != nil },
            onEdit: { binding.edited() })
        remove.toolTip = "Forget this movie's cursor file; the file itself is not deleted"
        let readout = inspectorReadout(width: InspectorMetrics.popupWidth + 52) {
            let id = binding.document?.selectedMedia
            return MediaPane.cursorLine(id.flatMap { binding.documentSnapshot.media($0) })
        }
        return InspectorSection(
            id: "media.cursor", title: "Cursor",
            summary: {
                guard let media = selected(), let cursor = media.cursor else { return nil }
                return MediaPane.cursorMissing(media)
                    ? "missing" : (cursor.path as NSString).lastPathComponent
            },
            rows: [inspectorRow("File", [locate, remove]), inspectorRow(nil, [readout])])
    }

    /// A media that can carry a cursor file: a video with a picture (CU-39).
    static func takesCursor(_ media: MediaSnapshot) -> Bool {
        media.kind == .video && media.hasVideo
    }

    /// Whether the section is shown for a project's media list (CU-54).
    static func showsCursorSection(_ media: [MediaSnapshot]) -> Bool {
        media.contains(where: takesCursor)
    }

    /// Whether a media's cursor file names nothing on disk.
    static func cursorMissing(_ media: MediaSnapshot) -> Bool {
        guard media.cursor != nil else { return false }
        guard let url = cursorURL(for: media) else { return true }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    /// The readout's line (CU-54): nothing selected that can carry one, no
    /// file, the file's name, or its name and that it is missing.
    static func cursorLine(_ media: MediaSnapshot?) -> String {
        guard let media, takesCursor(media) else { return "Select a video in the list" }
        guard let cursor = media.cursor else { return "No cursor file" }
        let name = (cursor.path as NSString).lastPathComponent
        return cursorMissing(media) ? "\(name) — missing" : name
    }

    /// Locate…: an open panel of `.fjcursor` files, the import's attach check
    /// against this media, then one step — or an alert with the check's
    /// sentence and nothing edited.
    func locateCursor(_ media: MediaSnapshot) {
        guard let window = window else {
            NSSound.beep()
            return
        }
        let binding = self.binding
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let type = UTType(filenameExtension: CursorFileWriter.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.message = "Choose the cursor file for “\(media.name)”."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            switch MediaImporter.cursorAttachment(at: url, to: MediaDescriptor(media)) {
            case .success(let attachment):
                binding.applyGrouped(
                    "Locate Cursor File",
                    [.setMediaCursor(media: media.id, cursor: attachment.cursor)])
            case .failure(let problem):
                // The panel's sheet is still ending; the alert waits a turn.
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "The cursor file was not attached"
                    alert.informativeText = problem.message
                    alert.beginSheetModal(for: window)
                }
            }
        }
    }
}
