import AppKit

/// The editor's document window, and the two things it decides: where a bare
/// Space goes (spec §11 K-1, kpgalligan/framejob#35), and when text gives
/// the keys back (K-4, `TextFocus` below), which it asks first.
///
/// **Space is the transport's unless the first responder is typing or claims
/// it.** The window routes a bare Space key-DOWN (⇧ and ⇪ allowed, any other
/// modifier untouched) BEFORE dispatch, because dispatch is what beeped when
/// the WINDOW was first responder — as it still can be when a focused view is
/// removed (`OptionFieldControl.finishEditing` hands focus to the content
/// view since #60): `NSWindow.keyDown` forwards to nothing, and
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

/// When the editor window takes the keys back from text (spec §11 K-4):
/// typing is focus-averse. Only a click, or a command that exists to type,
/// gives text the keys; a click outside it, Tab (unless Full Keyboard Access
/// is on), and Return in a one-line field hand them back to the content
/// view — the root that holds the bare-key map — BEFORE dispatch, so Space
/// plays the moment typing ends.
///
/// Before dispatch because of what dispatch did: a click on the timeline,
/// which refuses first responder, left the field editor attached, and
/// AppKit's own Return re-selected the field after its commit — both behind
/// no focus ring, so the next Space was typed into a field that looked left.
/// Each field still commits through its own end-of-editing path, as on any
/// blur. Pure, so a probe can ask it.
enum TextFocus {
    /// The text taking keys when `responder` is editable text — every field
    /// editor, the Text tab's area, the canvas's inline editor, the
    /// composer — else nil.
    static func typing(_ responder: NSResponder?) -> NSTextView? {
        guard let text = responder as? NSTextView, text.isEditable else { return nil }
        return text
    }

    /// Where a click keeps the typing: a field editor's field, or the
    /// `OptionFieldControl` that frames it (its margins and chevron are the
    /// field's own); else the text view's scroll view, so a scroller is
    /// inside; else the text view.
    static func host(of text: NSTextView) -> NSView {
        if text.isFieldEditor, let field = text.delegate as? NSView {
            return (field.superview as? OptionFieldControl) ?? field
        }
        return text.enclosingScrollView ?? text
    }

    /// True when the key-down `event` leaves `text`: Tab or ⇧Tab in any
    /// text, unless `fullKeyboardAccess` — then Tab is AppKit's key-view
    /// loop, how such a user reaches a control (K-1's exception); Return or
    /// keypad Enter in a field editor (⇧ ⇪, and the keypad and fn flags,
    /// allowed). ⌃Tab, ⌥Return and ⌘ are AppKit's; a multi-line view routes
    /// its own Return (`TextEditKey`). Never while an input method has
    /// marked text.
    static func leavesOnKey(
        _ event: NSEvent, in text: NSTextView, fullKeyboardAccess: Bool
    ) -> Bool {
        guard event.type == .keyDown, !text.hasMarkedText() else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 48:
            return !fullKeyboardAccess && flags.subtracting([.shift, .capsLock]).isEmpty
        case 36, 76:
            return text.isFieldEditor
                && flags.subtracting([.shift, .capsLock, .numericPad, .function]).isEmpty
        default:
            return false
        }
    }

    /// True when a mouse-down whose content hit is `hit` leaves `text`: a
    /// hit outside its host. nil — the click is outside the content view,
    /// on the title bar — never leaves.
    static func leavesOnClick(hit: NSView?, in text: NSTextView) -> Bool {
        guard let hit else { return false }
        return !hit.isDescendant(of: host(of: text))
    }
}

/// The bare-key map's modifier rule, read by `handleEditorKey` (#61).
enum EditorKey {
    /// Device-independent part of `flags` minus [.shift, .capsLock] must be empty, except that on a
    /// function-key scalar (0xF700...0xF8FF) .numericPad and .function are also allowed. ⌘ ⌥ ⌃ .help never. Pure.
    static func isBare(_ flags: NSEvent.ModifierFlags, scalar: UInt32) -> Bool {
        var allowed: NSEvent.ModifierFlags = [.shift, .capsLock]
        if (0xF700...0xF8FF).contains(scalar) { allowed.formUnion([.numericPad, .function]) }
        return flags.intersection(.deviceIndependentFlagsMask).subtracting(allowed).isEmpty
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
        // A key that leaves is spent; a click that leaves is then delivered.
        if leaveText(for: event), event.type == .keyDown { return }
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

    /// `TextFocus`'s rule applied: true when `event` left the text, first
    /// responder now the content view. A field that refuses to resign keeps
    /// the event, and nothing is taken while a sheet is attached.
    private func leaveText(for event: NSEvent) -> Bool {
        guard attachedSheet == nil, let text = TextFocus.typing(firstResponder),
              let content = contentView
        else { return false }
        let leaves: Bool
        switch event.type {
        case .keyDown:
            leaves = TextFocus.leavesOnKey(
                event, in: text, fullKeyboardAccess: NSApp.isFullKeyboardAccessEnabled)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let point = content.superview?.convert(event.locationInWindow, from: nil)
                ?? event.locationInWindow
            leaves = TextFocus.leavesOnClick(hit: content.hitTest(point), in: text)
        default:
            leaves = false
        }
        return leaves && makeFirstResponder(content)
    }
}
