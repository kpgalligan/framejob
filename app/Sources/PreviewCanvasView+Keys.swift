import AppKit

/// The canvas's keys: what it does with a key while it holds first responder
/// (spec §4.2). `CanvasOverlayView` forwards here and owns nothing else.
extension PreviewCanvasView {
    /// The keys the canvas owns while it holds first responder. Everything
    /// else returns false and walks the responder chain to
    /// `EditorViewController.keyDown` (the bare-key transport map).
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard CanvasKey.isPlain(flags) else { return false }
        switch event.keyCode {
        case 53:  // Esc
            if cancelGesture() { return true }
            return handleCropKey(event)
        case 36, 76:  // Return, keypad Enter
            return handleCropKey(event)
        case 49:  // Space — armed for panning; the tap is settled on key-up.
            // K-1's rule, not the arrows': the window takes only this Space.
            guard flags.subtracting([.shift, .capsLock]).isEmpty else { return false }
            guard !event.isARepeat else { return true }
            spaceHeld = true
            spaceDidPan = false
            return true
        case 123...126 where isGestureLive:
            // A committed edit inside a live edit would keep its undo step
            // through Esc, which CI-16 forbids (spec §11 K-5).
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

    /// A key-up settles only a press the canvas armed: ⌥Space, and a Space the
    /// window took before the canvas had focus, are not its to toggle (K-5).
    func handleKeyUp(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49, spaceHeld else { return false }
        spaceHeld = false
        // A Space that never panned is the transport's, and the editor never
        // saw the key-down because this view swallowed it.
        if !spaceDidPan { onSpaceTapped?() }
        spaceDidPan = false
        return true
    }

    /// Esc (53), Return (36) or keypad Enter (76), plain by `CanvasKey`, with
    /// crop mode on: leaves it. `handleEditorKey` asks too, so the keys work
    /// from any focus but typing (spec §11 K-6).
    func handleCropKey(_ event: NSEvent) -> Bool {
        guard cropMode, [53, 36, 76].contains(event.keyCode),
              CanvasKey.isPlain(event.modifierFlags)
        else { return false }
        setCropMode(false)
        return true
    }

    /// A primary box exists, `InspectorTab.hasSourcePixels` answers false for
    /// its clip, and its track's `matte` is `.none`: crop shapes a matte
    /// whatever the clip's kind (spec §11 K-7, MT-4).
    var primaryRefusesCrop: Bool {
        guard let clip = primaryBox?.clip else { return false }
        return !InspectorTab.hasSourcePixels(clip, in: snapshot)
            && snapshot.track(clip.track)?.matte == TrackMatte.none
    }

    /// A session `cancelGesture` closes is open: move, scale, rotate, crop,
    /// endpoint or region grip. A pan is not one.
    var isGestureLive: Bool {
        moving != nil || scaling != nil || rotating != nil || cropping != nil
            || endpointDrag != nil || obscureDrag != nil
    }
}
