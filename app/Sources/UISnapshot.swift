import AppKit

#if FRAMEJOB_DEV_TOOLS
/// `snapshot_ui`'s main-thread half (road map 11's V2a, spec §11 V-1..V-3):
/// which window and which view a call means, the facts about that window,
/// the temporary staging a capture needs, and one `cacheDisplay` pass.
///
/// Every member is main-thread only. The handler
/// (`AgentServer+Snapshot.swift`) runs on the server thread and reaches each
/// one through `onMain`, one hop per pass, so the settle loop's waits are
/// the server's and the main run loop turns freely between passes.
///
/// **Staging is undone on every exit.** The fill is an `NSImageView` put
/// just above `playerHost` — under `safeGuides` and `overlay`, V1's W4a — so
/// the handles land on the picture as they do on screen. It comes out again
/// in `unstage`, which the handler calls from a `defer`: left in, the next
/// capture differs (V1's W6). No appearance is staged: a live switch left
/// build-time colours in the launch appearance (V3), so the look is the
/// instance's, chosen at launch (`DevAppearance`).
enum UISnapshot {
    enum WindowKind: String, CaseIterable {
        case editor, sheet, settings, welcome, recorder

        /// The window's name in a refusal.
        var title: String {
            switch self {
            case .editor: return "editor"
            case .sheet: return "sheet"
            case .settings: return "Settings"
            case .welcome: return "Welcome"
            case .recorder: return "New Recording"
            }
        }
    }
    enum Region: String, CaseIterable { case toolbar, preview, inspector, timeline }

    /// What one capture is of: the window, the view drawn into the PNG, and
    /// the editor behind it when there is one (the fill and the regions).
    struct Subject {
        let window: NSWindow
        let root: NSView
        let kind: WindowKind
        let region: Region?
        let editor: EditorViewController?
    }

    /// One `cacheDisplay` of a root: the bitmap and a copy of its bytes, which
    /// is what two passes are compared by.
    struct Pass {
        let rep: NSBitmapImageRep
        let bytes: Data
    }

    /// What `stage` changed, so `unstage` can put it back.
    struct Staging {
        let window: NSWindow
        let fill: NSImageView?
    }

    /// `harness/main.swift`'s settle: two consecutive passes byte-identical,
    /// at most forty of them, 20 ms apart.
    static let settleLimit = 40
    static let settleInterval: TimeInterval = 0.02

    // MARK: - Resolution

    /// The open Settings, Welcome or New Recording window, found among
    /// `NSApp.windows` by its controller's class. Never `.shared`: touching
    /// any of those singletons BUILDS its window, and a capture must not open
    /// what it was asked to look at.
    static func openWindow(_ kind: WindowKind) -> NSWindow? {
        NSApp.windows.first { window in
            guard window.isVisible else { return false }
            switch kind {
            case .settings: return window.windowController is SettingsWindowController
            case .welcome: return window.windowController is WelcomeWindowController
            case .recorder: return window.windowController is RecorderPanelController
            case .editor, .sheet: return false
            }
        }
    }

    /// A named region of the editor: the toolbar is the root's `BarView`, the
    /// other three are the editor's pane containers.
    static func regionView(_ region: Region, of editor: EditorViewController) -> NSView? {
        switch region {
        case .toolbar: return editor.view.subviews.first { $0 is BarView }
        case .preview: return editor.canvasContainer
        case .inspector: return editor.inspectorContainer
        case .timeline: return editor.timelineContainer
        }
    }

    /// `view`'s bounds in `root`'s space, top-left origin, in points rounded
    /// to two decimal places: `[x, y, w, h]`.
    static func rect(_ view: NSView, in root: NSView) -> [Double] {
        let r = view.convert(view.bounds, to: root)
        let top = root.isFlipped ? r.minY : root.bounds.height - r.maxY
        return [r.minX, top, r.width, r.height].map { round2($0) }
    }

    static func round2(_ value: CGFloat) -> Double {
        (Double(value) * 100).rounded() / 100
    }

    /// A JSON value for an optional string: the string, or `null`.
    static func orNull(_ value: String?) -> Any {
        value.map { $0 as Any } ?? NSNull()
    }

    // MARK: - Facts

    /// What the capture depended on: a proof compares only captures whose
    /// scale, activity, key state and colour space agree.
    static func facts(_ window: NSWindow) -> [String: Any] {
        [
            "active": NSApp.isActive,
            "key": window.isKeyWindow,
            "main": window.isMainWindow,
            "visible": window.isVisible,
            "occluded": !window.occlusionState.contains(.visible),
            "scale": Double(window.backingScaleFactor),
            "color_space": orNull(window.colorSpace?.localizedName),
            "sheet_attached": window.attachedSheet != nil,
        ]
    }

    /// The visible windows, in `windowNumber` order, each with what a caller
    /// needs to choose one.
    static func listing() -> [String: Any] {
        let windows = NSApp.windows.filter { $0.isVisible }
            .sorted { $0.windowNumber < $1.windowNumber }
        return [
            "ok": true,
            "active": NSApp.isActive,
            "windows": windows.map(row),
        ]
    }

    static func kind(of window: NSWindow) -> String {
        if window.contentViewController is EditorViewController { return "editor" }
        if window.sheetParent != nil { return "sheet" }
        if window.windowController is SettingsWindowController { return "settings" }
        if window.windowController is WelcomeWindowController { return "welcome" }
        if window.windowController is RecorderPanelController { return "recorder" }
        if window is NSPanel { return "panel" }
        return "other"
    }

    static func row(_ window: NSWindow) -> [String: Any] {
        let frame = window.frame
        let content = window.contentView?.bounds.size ?? .zero
        var project: Any = NSNull()
        if window.contentViewController is EditorViewController,
            let document = window.windowController?.document as? ProjectDocument
        {
            project = orNull(AgentServer.path(of: document))
        }
        var sheet: Any = NSNull()
        if let attached = window.attachedSheet {
            let size = attached.contentView?.bounds.size ?? .zero
            sheet = [
                "class": NSStringFromClass(type(of: attached)),
                "content": [round2(size.width), round2(size.height)],
                "file_panel": attached is NSSavePanel,
            ] as [String: Any]
        }
        return [
            "kind": kind(of: window),
            "class": NSStringFromClass(type(of: window)),
            "title": window.title,
            "frame": [frame.minX, frame.minY, frame.width, frame.height].map { round2($0) },
            "content": [round2(content.width), round2(content.height)],
            "scale": Double(window.backingScaleFactor),
            "visible": window.isVisible,
            "occluded": !window.occlusionState.contains(.visible),
            "key": window.isKeyWindow,
            "main": window.isMainWindow,
            "project": project,
            "sheet": sheet,
        ]
    }

    // MARK: - Staging

    /// With a picture, puts it under the canvas overlay at `playerHost`'s
    /// frame (V1's W4a).
    static func stage(_ subject: Subject, picture: CGImage?) -> Staging {
        var fill: NSImageView?
        if let picture, let canvas = subject.editor?.previewCanvas {
            let host = canvas.playerHost
            let view = NSImageView(frame: host.frame)
            view.image = NSImage(
                cgImage: picture, size: NSSize(width: picture.width, height: picture.height))
            view.imageScaling = .scaleAxesIndependently
            view.imageFrameStyle = .none
            canvas.addSubview(view, positioned: .above, relativeTo: host)
            fill = view
        }
        return Staging(window: subject.window, fill: fill)
    }

    /// Takes the fill out.
    static func unstage(_ staging: Staging) {
        staging.fill?.removeFromSuperview()
    }

    // MARK: - Capture

    /// One pass: lay out, display, `cacheDisplay` the root, copy its bytes.
    static func pass(_ root: NSView) -> Pass? {
        root.layoutSubtreeIfNeeded()
        root.displayIfNeeded()
        guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return nil }
        root.cacheDisplay(in: root.bounds, to: rep)
        guard let data = rep.bitmapData else { return nil }
        return Pass(rep: rep, bytes: Data(bytes: data, count: rep.bytesPerRow * rep.pixelsHigh))
    }
}
#endif
