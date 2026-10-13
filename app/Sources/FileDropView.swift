import AppKit
import UniformTypeIdentifiers

/// Root view of the editor and welcome windows: accepts files dragged in from
/// the Finder and opens each as a document, exactly like dropping them on the
/// Dock icon. Adapted from Rasterize's `FileDropView`.
///
/// It also accepts first responder so the editor's bare-key map (Space, JKL,
/// arrows — spec §9) reaches `EditorViewController.keyDown` through the
/// responder chain; a plain `NSView` refuses, and the keys would go nowhere.
class FileDropView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FileDropView does not support NSCoder")
    }

    override var acceptsFirstResponder: Bool { true }

    /// The URLs on the pasteboard this app claims — the `.framejob` package
    /// and every movie/audio/image type the Info.plist lists as an Alternate
    /// handler, which is exactly `ProjectDocument.readableTypes`.
    private func readableURLs(from sender: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: options) as? [URL]
        else { return [] }
        let readable = ProjectDocument.readableTypes.compactMap(UTType.init)
        return urls.filter { url in
            guard let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                ?? UTType(filenameExtension: url.pathExtension)
            else { return false }
            return readable.contains { type.conforms(to: $0) }
        }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        readableURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = readableURLs(from: sender)
        for url in urls {
            NSDocumentController.shared.openDocument(
                withContentsOf: url, display: true
            ) { _, _, error in
                if let error = error, (error as? CocoaError)?.code != .userCancelled {
                    NSApp.presentError(error)
                }
            }
        }
        return !urls.isEmpty
    }
}
