import AppKit

/// The document window. Nothing but sizing and the subtitle lives here — the
/// editor itself is `EditorViewController`.
final class EditorWindowController: NSWindowController {
    init(document: ProjectDocument) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.contentViewController = EditorViewController(document: document)
        window.backgroundColor = DS.chromeBackground
        window.titlebarAppearsTransparent = false
        window.minSize = NSSize(width: 900, height: 620)

        // Content size: the canvas at a comfortable preview scale plus the
        // chrome around it (toolbar 44, inspector 320, timeline 240), clamped
        // to 85 % of the screen. A 4K project must not open a 4K window.
        let canvas = document.project.snapshot.canvas
        var contentSize = NSSize(
            width: min(canvas.size.width, 1280) + EditorViewController.defaultInspectorWidth,
            height: min(canvas.size.height, 720) + EditorViewController.toolbarHeight
                + EditorViewController.defaultTimelineHeight)
        if let screen = NSScreen.main {
            let limit = screen.visibleFrame
            contentSize.width = min(contentSize.width, limit.width * 0.85)
            contentSize.height = min(contentSize.height, limit.height * 0.85)
        }
        contentSize.width = max(contentSize.width, 900)
        contentSize.height = max(contentSize.height, 620)
        window.setContentSize(contentSize)
        window.center()

        super.init(window: window)

        // The title tracks the document name through NSDocument's own
        // synchronizeWindowTitleWithDocumentName; only the subtitle is ours,
        // and the editor refreshes it whenever the canvas changes.
        window.subtitle = EditorWindowController.subtitle(for: document)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EditorWindowController does not support NSCoder")
    }

    /// "1920 × 1080 · 30 fps" — the two document facts that are never in the
    /// title. Static so `EditorViewController` can refresh it after a
    /// `set_canvas` without reaching into this controller's internals.
    static func subtitle(for document: ProjectDocument) -> String {
        let canvas = document.project.snapshot.canvas
        return "\(canvas.width) × \(canvas.height) · \(canvas.fps.displayName) fps"
    }
}
