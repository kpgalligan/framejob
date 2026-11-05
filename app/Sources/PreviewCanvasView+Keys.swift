import AppKit

/// The canvas's keys: what it does with a key while it holds first responder
/// (spec §4.2). `CanvasOverlayView` forwards here and owns nothing else.
extension PreviewCanvasView {
    /// The keys the canvas owns while it holds first responder. Everything
    /// else returns false and walks the responder chain to
    /// `EditorViewController.keyDown` (the bare-key transport map).
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.subtracting(.shift).isEmpty else { return false }
        switch event.keyCode {
        case 53:  // Esc
            if cancelGesture() { return true }
            guard cropMode else { return false }
            setCropMode(false)
            return true
        case 36, 76:  // Return, keypad Enter
            guard cropMode else { return false }
            setCropMode(false)
            return true
        case 49:  // Space — armed for panning; the tap is settled on key-up.
            guard !event.isARepeat else { return true }
            spaceHeld = true
            spaceDidPan = false
            return true
        default:
            break
        }
        let step = flags.contains(.shift) ? Self.nudgeStepLarge : Self.nudgeStep
        switch event.keyCode {
        case 123: return nudge(dx: -step, dy: 0)
        case 124: return nudge(dx: step, dy: 0)
        case 125: return nudge(dx: 0, dy: step)
        case 126: return nudge(dx: 0, dy: -step)
        default: return false
        }
    }

    /// Focus left the canvas with Space still down (the inline text editor
    /// taking over, a click in the timeline). Without this the pan stays armed
    /// and the next canvas click drags the whole canvas instead of a clip.
    func releaseSpace() {
        spaceHeld = false
        spaceDidPan = false
    }

    func handleKeyUp(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49 else { return false }
        spaceHeld = false
        // A Space that never panned is the transport's, and the editor never
        // saw the key-down because this view swallowed it.
        if !spaceDidPan { onSpaceTapped?() }
        spaceDidPan = false
        return true
    }
}
