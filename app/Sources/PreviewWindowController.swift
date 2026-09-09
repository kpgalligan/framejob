import AVFoundation
import AppKit

/// View ▸ Preview Window (⇧⌘P) — road map 2's phase 8b: a second window showing
/// exactly what the canvas shows, with no overlay, no handles and no chrome, for
/// a second display.
///
/// **It is a second `AVPlayerLayer` on the SAME player**, which is the whole
/// implementation: one player, two layers, so the two pictures cannot drift
/// apart by construction — there is no second item, no second composition, no
/// synchronisation and nothing to keep in step. The archived AVFoundation
/// Programming Guide says this does not work ("only the most recently created
/// such layer will display any video content onscreen"), and the current SDK
/// header says nothing either way, so it was MEASURED on macOS 26.5.1 before
/// this file was written: two layers on one player, built in both orders,
/// both reported a non-nil `displayedPixelBuffer` with byte-identical
/// checksums on every one of eighteen probes, and releasing the second left the
/// first still displaying. Two things about that measurement are worth carrying
/// forward, because the obvious instruments are useless here:
/// `isReadyForDisplay` and `videoRect` both come back TRUE and plausible for a
/// layer with no superlayer at all and for one in a window that was never
/// ordered in — `displayedPixelBuffer` is the only property that discriminates.
/// Do not "fix" this back into a single layer moved between two windows on the
/// strength of the archived guidance.
///
/// **The window is an `NSPanel`, and that is not stylistic.** AppKit resolves a
/// menu item's nil-target action down the KEY window's responder chain, then the
/// key window and its delegate, then the MAIN window's chain — and a titled
/// `NSWindow` becomes key AND main, displacing the editor. Measured, with a
/// three-mode probe over one ⌘E item whose action lives on the editor's content
/// view controller:
///
/// | second window | key | main | `NSApp.target(forAction:)` | item |
/// |---|---|---|---|---|
/// | none | Editor | Editor | the content controller | enabled |
/// | `NSWindow` | Preview | **Preview** | **NONE** | **disabled** |
/// | `NSPanel` | Preview | Editor | the content controller | enabled |
///
/// So with a plain window every ⌘-item whose action lives on
/// `EditorViewController` — ⌘E Export…, ⌘T Split, ⌘0 Zoom to Fit — goes dead
/// while the preview is focused, and a panel keeps every one of them alive
/// with no forwarding code at all (`NSPanel.canBecomeMain` is false;
/// `canBecomeKey` is true, so it still takes ⌘W and the keys below). This is
/// the app's first `NSPanel`.
///
/// **What a panel keeps alive is the items whose action is on the EDITOR's
/// own responder chain, and ⌘Z / ⇧⌘Z are not those** — which is the whole
/// reason this controller is the panel's DELEGATE. Edit ▸ Undo is the bare
/// `Selector(("undo:"))` (`AppDelegate+Menus.swift`), resolved down the KEY
/// window's chain rather than the main one, and `NSWindow` itself implements
/// it (measured: `NSWindow.instancesRespond(to: "undo:")` is true and
/// `NSResponder`'s is false), so the search STOPS at this panel and asks the
/// panel's own undo manager. Measured against exactly the shape this file
/// builds: the editor window's `undoManager` IS the document's — through the
/// responder chain, since the editor window has no delegate at all and
/// `NSWindowController` implements `windowWillReturnUndoManager:` nowhere
/// (both measured) — while an undelegated panel silently mints a second,
/// empty one, `panel.validateMenuItem` answers false for ⌘Z, and the item is
/// greyed out. That is the worst pairing available with the forwarded keys
/// below: the one window a person can edit from would be the one window they
/// cannot take it back from. So `windowWillReturnUndoManager` hands back
/// `editor?.document?.undoManager` and ⌘Z here undoes the step ⌘Z there
/// undoes. The assignment steals nothing — the panel's delegate was nil, and
/// `NSWindowController` neither conforms to `NSWindowDelegate` nor implements
/// one of its methods (measured, all three), so no AppKit behaviour changes
/// with it, and the editor window's `willCloseNotification` observer below is
/// a NOTIFICATION on the OTHER window that a delegate on this one cannot
/// touch.
///
/// **And the delegate has to be there before anything ASKS**, which is the
/// second ordering hazard in the init below and was measured the same way as
/// the first. `NSWindow.undoManager` asks the delegate on every request — but
/// the first request that FALLS THROUGH, because there is no delegate or
/// because it answered nil, mints a manager of the window's own and that one
/// is kept for good, the delegate never consulted again. Both halves are
/// readings: a panel stripped of its delegate answered with a fresh empty
/// manager and putting the delegate straight back did not undo it (installed,
/// and answering the document's manager when called by hand, while
/// `panel.undoManager` still came back the panel's own), and a bare panel
/// whose delegate answered nil once stayed on its own manager after the
/// delegate started answering properly. A panel built through this init
/// answers correctly on its first ask, so nothing between `NSPanel(…)` and
/// the assignment asks for one; anything added there that might must go
/// BELOW it.
///
/// Two panel defaults are wrong for this window and are set explicitly.
/// `hidesOnDeactivate` defaults to **true** on `NSPanel` (measured), which
/// would make a preview on a second display vanish the moment the person
/// switched to another app — the one moment a second display is most useful.
/// And the panel is full-screen capable, which a window that cannot become
/// main might not have been: also measured — with
/// `collectionBehavior = .fullScreenPrimary` the panel's `styleMask` gains
/// `.fullScreen` and its frame becomes the screen's.
///
/// **Retention: the editor holds it, and the document deliberately does NOT.**
/// `document.addWindowController(_:)` is the tidy answer to "who owns a second
/// window", and it cannot be used here, for a reason that is measured rather
/// than feared: AppKit only asks a document about SAVING when the window
/// controller being closed is the last one. A probe with a dirty untitled
/// `NSDocument` closed its first window and got a save sheet with one window
/// controller — and with two, the same close put up NO sheet, destroyed the
/// editor window silently and left the document open behind a preview panel
/// with nothing to edit in. That is a data-loss shape, so this is one stored
/// property on `EditorViewController` (`previewWindow`) instead, which is
/// exactly what the frozen-file rule permits an extension to be unable to hold,
/// and the document keeps its one window controller and all of NSDocument's
/// close semantics unchanged. It is not `ExportQueueWindowController`'s
/// `static let shared` mould either: that is a process-wide singleton and a
/// player is PER DOCUMENT.
///
/// The controller therefore closes ITSELF when the editor's window closes,
/// rather than waiting to be deallocated: a window whose controller has been
/// released while it is still on screen is nobody's, and the observer is the
/// deterministic door. Once made, the controller lives as long as the editor —
/// closing the panel hides the window and keeps the frame, and ⇧⌘P shows it
/// again.
///
/// **It persists its frame**, which app/CLAUDE.md records the phase-7 queue
/// window as deliberately not doing. The reason it earns one here is the
/// feature's own: a preview window is opened to put it on a SECOND DISPLAY, and
/// one that comes back in the middle of the laptop screen every time has failed
/// at the thing it exists for. The autosave name is fixed rather than
/// per-document — a per-document name would mint a defaults key per project —
/// so every project's preview opens where the last one was left. The price of
/// one name is a documented limit rather than a bug: with two projects'
/// previews open at once the second opens exactly on top of the first, and only
/// one of the two autosaves, because `setFrameAutosaveName` answers false for a
/// name another window already holds.
final class PreviewWindowController: NSWindowController {

    /// One name for every document. See the type doc: per-document would grow
    /// the defaults domain a key at a time. AppKit stores it under
    /// `"NSWindow Frame " + name`, which is the key the offscreen harness pins.
    static let frameAutosaveName = "ReelcutPreviewWindow"

    /// The transport whose keys this window forwards. Weak: the editor owns
    /// this controller, and a strong link back would be a cycle.
    private weak var editor: EditorViewController?
    private let surface: PreviewSurfaceView

    init(editor: EditorViewController) {
        self.editor = editor
        surface = PreviewSurfaceView(editor: editor, layer: editor.playback.makePreviewLayer())

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        panel.contentView = surface
        // Black, not `DS.chromeBackground`: the surround of a preview is the
        // absence of picture, and the canvas pane's own void
        // (`DS.canvasVoid`) is a piece of editor chrome that has no business
        // in a window whose whole point is to show nothing but the frame.
        panel.backgroundColor = .black
        panel.minSize = NSSize(width: 320, height: 200)
        // See the type doc: a panel hides itself when the app deactivates
        // unless told not to, and a preview on a second display must not.
        panel.hidesOnDeactivate = false
        // Measured to work on a panel; the road map asks for it so the window
        // can fill a second display outright.
        panel.collectionBehavior = [.fullScreenPrimary]
        // `NSApp.windowsMenu` is set (`AppDelegate.buildMainMenu`), so without
        // this the Window menu would list "Preview" as well as View's own item
        // — the queue window's rule, and the same reason.
        panel.isExcludedFromWindowsMenu = true
        // The controller outlives the window's closing (⇧⌘P shows it again),
        // so closing must not release it.
        panel.isReleasedWhenClosed = false
        // Restore, then arm — in that order, and both calls, because the two
        // are different things: `setFrameUsingName` is the READ (false when
        // nothing was ever saved, which is the only honest test for "first
        // run" and what centres the window), and `setFrameAutosaveName` is
        // what makes every later move and resize write itself back.
        if !panel.setFrameUsingName(PreviewWindowController.frameAutosaveName) {
            panel.center()
        }
        super.init(window: panel)
        // ARMED AFTER `super.init`, and that ORDER IS THE WHOLE POINT.
        // `NSWindowController.init(window:)` assigns its OWN
        // `windowFrameAutosaveName` — "" unless somebody set one — onto the
        // window it is handed, so a name set on the panel BEFORE this line is
        // silently wiped. Nothing then ever writes `NSWindow Frame
        // ReelcutPreviewWindow`, the `setFrameUsingName` above can only ever
        // answer false, and the panel opens centred every time — which is the
        // one thing this type must not do, since a preview window is opened to
        // put the picture on a SECOND DISPLAY. Measured, both halves: the name
        // reads back as "" when it is set first, and re-asking after the
        // controller has taken the window answers true and sticks.
        _ = panel.setFrameAutosaveName(PreviewWindowController.frameAutosaveName)
        // ALSO after `super.init`, and for one method only: see the type doc.
        // `undo:` is implemented by `NSWindow`, so ⌘Z resolves at whichever
        // window is key and asks THAT window's undo manager — a panel with no
        // delegate answers with an empty one of its own, and undo is dead in
        // the only window from which the keys below can make an edit. It is
        // an ORDERING as much as an assignment: a window that has once fallen
        // back to a manager of its own keeps it and stops asking the delegate
        // (measured), so nothing above this line may ask for one.
        panel.delegate = self
        syncTitle()

        // The deterministic door: the editor's window going away is what ends
        // this one, not this object's deallocation. See the type doc.
        if let window = editor.view.window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(editorWindowWillClose(_:)),
                name: NSWindow.willCloseNotification, object: window)
        }
    }

    /// "Intro — Preview". The document's name is in the title because two open
    /// projects each get their own preview and two windows called "Preview"
    /// would be a guessing game; it is refreshed on every `show()` rather than
    /// observed, since the only thing that renames a project is a save and the
    /// next ⇧⌘P picks it up. Nothing else reads this title — the window is
    /// excluded from the Window menu, and AppKit's own document-title
    /// machinery is not involved because this controller belongs to the
    /// EDITOR and not to the document (see the type doc).
    private func syncTitle() {
        let name = editor?.document?.displayName
        window?.title = name.map { "\($0) — Preview" } ?? "Preview"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PreviewWindowController does not support NSCoder")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Shows the panel and puts the surface in first responder, so a bare
    /// Space or J/K/L pressed here reaches the transport rather than beeping.
    func show() {
        guard let window = window else { return }
        syncTitle()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(surface)
    }

    var isShowing: Bool { window?.isVisible ?? false }

    @objc private func editorWindowWillClose(_ note: Notification) {
        close()
    }
}

/// The panel is delegated for ONE answer, and the type doc argues it: ⌘Z is
/// `undo:`, `NSWindow` implements `undo:`, so the key window's own undo manager
/// is what runs — and this window's own is not the document's.
///
/// Nothing else of `NSWindowDelegate` is implemented here on purpose. The
/// panel's closing is not this protocol's business: closing HIDES the window
/// and keeps the controller (⇧⌘P shows it again), and the thing that must end
/// this window is the EDITOR's window closing, which arrives as a
/// `willCloseNotification` on that other window and cannot be a delegate
/// callback on this one.
extension PreviewWindowController: NSWindowDelegate {

    /// The document's manager, so ⌘Z / ⇧⌘Z from the panel undo the same step
    /// they undo from the editor.
    ///
    /// **Nil is not a soft answer here**, which is worth knowing before
    /// anybody adds a condition to this line: a nil answer sends `NSWindow`
    /// to its fallback, which MINTS a manager of its own and keeps it — the
    /// delegate is never asked again, even once it would answer (measured, on
    /// a bare panel: nil, then the real manager, and the window still reported
    /// its own). So this returns nil only where the question has no meaning
    /// left at all — the editor or its document deallocated, which is past
    /// the point where this controller has closed itself — and never as a
    /// "not right now".
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        editor?.document?.undoManager
    }
}

/// The panel's content: one `AVPlayerLayer`, black around it, and the transport
/// keys handed back to the editor.
///
/// It is a plain `NSView` hosting the layer rather than a second
/// `PreviewCanvasView`, and that is the feature: no overlay, no handles, no safe
/// guides, no drop target and no zoom — a preview window is for LOOKING at the
/// frame, and every one of those affordances belongs to the window that also
/// holds the timeline the gesture would edit.
private final class PreviewSurfaceView: NSView {
    private weak var editor: EditorViewController?
    private let playerLayer: AVPlayerLayer

    init(editor: EditorViewController, layer: AVPlayerLayer) {
        self.editor = editor
        playerLayer = layer
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.cgColor
        self.layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PreviewSurfaceView does not support NSCoder")
    }

    /// The layer fills the view and `.resizeAspect` letterboxes inside it, so
    /// there is no canvas rectangle to compute here — unlike `layoutCanvas`,
    /// which has to know one because the overlay maps through it.
    /// `CATransaction` off, or every resize animates the picture into place.
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    /// A window resize changes this view's frame directly, and a frame change
    /// is not by itself a reason for AppKit to run a layout pass on a view with
    /// no constraints in it. `PreviewCanvasView` has the same shape and gets
    /// away with `layout()` alone because `EditorViewController.layoutCanvas`
    /// calls it by hand from every path that resizes the pane; this window has
    /// no such caller, so it asks for the pass itself.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override var acceptsFirstResponder: Bool { true }

    /// Bare transport keys — Space, J/K/L, the arrows, Home/End, and the
    /// letters — reach the editor only through the DOCUMENT window's responder
    /// chain, and this window's chain does not contain the editor's view
    /// controller. Rather than duplicate the key map, the event is handed to
    /// the one that owns it; `PreviewCanvasView.onSpaceTapped` is the same
    /// move made from inside the editor's own window.
    ///
    /// Everything with a modifier is a menu key equivalent and needs nothing
    /// here: those resolve through the MAIN window, which is still the editor
    /// because this window is a panel (see `PreviewWindowController`'s doc).
    ///
    /// `handleEditorKey` carries two refusals that this window inherits, and
    /// both are the point rather than a shortcoming. It refuses while the
    /// editor window's first responder is an `NSText`, so a bare key pressed
    /// here does nothing if a field is still being edited over there — the
    /// same refusal the editor would give the key itself, and an exception for
    /// this window would mean a Space typed into the timecode field arriving
    /// as Play. And it refuses while a SHEET is attached to the editor, which
    /// was added for this window: a sheet is window-modal, not
    /// application-modal (measured — `NSApp.modalWindow` is nil with one up,
    /// and this panel is still visible and still takes key), so without it a
    /// bare `t` pressed here would add a text clip behind an open export card
    /// that has already captured the project it is about to write. The guard
    /// lives beside the key map rather than here, so both windows get it from
    /// one line and no second copy can drift.
    override func keyDown(with event: NSEvent) {
        if editor?.handleEditorKey(event) == true { return }
        super.keyDown(with: event)
    }
}

/// The menu half, at the foot of the feature's own file — the shape
/// `CaptionExporter.swift` and `SilenceSheetController.swift` set. Declared
/// `@objc` on an `extension EditorViewController`, so the frozen file needs no
/// forward for it (app/CLAUDE.md's pitfall: a second declaration there would be
/// a redeclaration, not a forward).
extension EditorViewController {

    /// View ▸ Preview Window (⇧⌘P). A toggle rather than an opener: the item
    /// carries a checkmark for the state it is in, so the one key both opens
    /// the window and puts it away, which is what `Snapping` and `Safe Areas`
    /// do with theirs.
    ///
    /// The controller is made once and kept — closing hides the panel and keeps
    /// its frame, and its layer stops being fed because it is no longer on
    /// screen (measured in the phase-8 spike: a layer in a window that is not
    /// ordered in returns nil from `displayedPixelBuffer` while claiming
    /// `isReadyForDisplay`). If a closed panel ever shows up as a real cost,
    /// the fix is to drop its layer's player, not to rebuild this into a
    /// create-and-destroy cycle: the frame and the first-responder state are
    /// worth more than the layer.
    @objc func togglePreviewWindow(_ sender: Any?) {
        if let existing = previewWindow {
            if existing.isShowing {
                existing.close()
            } else {
                existing.show()
            }
            return
        }
        let controller = PreviewWindowController(editor: self)
        previewWindow = controller
        controller.show()
    }

    /// The half of `validateUserInterfaceItem` this file owns. nil means "not
    /// one of mine".
    ///
    /// Always enabled, like the two toggles above it in the View menu: a
    /// preview window over an empty timeline shows the canvas background,
    /// which is exactly what the editor's own canvas shows, and refusing to
    /// open it would be refusing to look at the thing.
    func validatePreviewWindowAction(
        _ action: Selector, item: any NSValidatedUserInterfaceItem
    ) -> Bool? {
        guard action == #selector(togglePreviewWindow(_:)) else { return nil }
        (item as? NSMenuItem)?.state = previewWindow?.isShowing == true ? .on : .off
        return true
    }
}
