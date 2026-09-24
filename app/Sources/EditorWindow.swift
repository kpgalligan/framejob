import AppKit

/// The editor's document window, and the one thing it decides: where a bare
/// Space goes (spec §11 K-1, kpgalligan/reelcut#35).
///
/// **Space is the transport's unless the first responder is typing or claims
/// it.** The window routes a bare Space key-DOWN (⇧ and ⇪ allowed, any other
/// modifier untouched) BEFORE dispatch, because dispatch is what beeped: an
/// inspector number field ends its edit with `makeFirstResponder(nil)`
/// (`OptionFieldControl.finishEditing`), which leaves the WINDOW as first
/// responder, `NSWindow.keyDown` forwards to nothing, and
/// `NSResponder.noResponder(for:)` beeps — the key never reached
/// `EditorViewController.keyDown`.
///
/// Three claimants keep the key:
/// - an editable `NSTextView` — every field editor, the Text tab's area, the
///   canvas's inline editor, the Media tab's search field — so a Space is
///   TYPED there;
/// - an `NSButton` (which covers `NSPopUpButton`) or an `NSSegmentedControl`:
///   they press on Space by AppKit's own convention, reachable only under
///   Full Keyboard Access, and an accessibility user keeps it;
/// - the canvas overlay (`CanvasOverlayView`), whose own Space arms a pan and
///   toggles play on key-UP (`PreviewCanvasView.handleKeyUp`).
/// And nothing is taken while a sheet is attached. An auto-repeat of a Space
/// the window took is swallowed. A non-editable field editor (a selectable
/// label), a slider, the window itself and every custom inspector control
/// are the transport's.
///
/// `handleEditorCharacter`'s `case " "` in `EditorViewController` stays for
/// the preview panel's forward (`PreviewWindowController.keyDown`) and is
/// dead for this window.
enum SpaceKeyRoute: Equatable { case transport, held, responder }

enum SpaceKey {
    /// nil unless `event` is a key-DOWN of keyCode 49 whose device-independent
    /// flags ⊆ [.shift, .capsLock]. Pure: reads only its arguments.
    static func route(
        _ event: NSEvent, firstResponder: NSResponder?, sheetAttached: Bool
    ) -> SpaceKeyRoute? {
        guard event.type == .keyDown, event.keyCode == 49 else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.subtracting([.shift, .capsLock]).isEmpty else { return nil }
        if sheetAttached { return .responder }
        if (firstResponder as? NSTextView)?.isEditable == true { return .responder }
        if firstResponder is NSButton || firstResponder is NSSegmentedControl
            || firstResponder is CanvasOverlayView
        {
            return .responder
        }
        if event.isARepeat { return .held }
        return .transport
    }
}

final class EditorWindow: NSWindow {
    /// Forwards to `super` unchanged. Declared because the unavailable coder
    /// init below is a designated initializer, and declaring one stops Swift
    /// inheriting `NSWindow`'s — without it `EditorWindowController`'s
    /// construction does not typecheck.
    override init(
        contentRect: NSRect, styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EditorWindow does not support NSCoder")
    }

    override func sendEvent(_ event: NSEvent) {
        switch SpaceKey.route(
            event, firstResponder: firstResponder, sheetAttached: attachedSheet != nil)
        {
        case .transport:
            guard let editor = contentViewController as? EditorViewController else {
                super.sendEvent(event)
                return
            }
            editor.playPause(nil)
        case .held:
            return
        case .responder, nil:
            super.sendEvent(event)
        }
    }
}
