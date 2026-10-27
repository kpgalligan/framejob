import AppKit

/// The panel SHOWN: `show()`, the one-second timer that keeps the Record Into
/// rows current while it is up, `setNote` and the refit that keeps the card on
/// its screen — `RecorderPanelController.swift`'s ninth file. A pure move out
/// of the base file, which stood at 399 lines against the 400-line cap a
/// Camera source would have grown: camera recording's CR1-0, paid first and
/// alone. Its `// MARK: - Showing` came here whole, bodies untouched;
/// `armSyncTimer` stays private, since its one caller, `show()`, moved with it.
extension RecorderPanelController {

    // MARK: - Showing

    /// Beeps and shows nothing while a recording has the panel hidden (the
    /// type doc): the welcome window's button is the caller that would
    /// otherwise un-hide it into the recording. Shown while idle, a prepared
    /// capture that failed (or a build that threw) is let go first, so the
    /// preview's sync tries again (spec §11 CAM-7 (5)). The device observers
    /// are added before that sync, which applies a change made while the
    /// panel was closed (CAM-8 (1)).
    func show() {
        guard !hiddenForRecording else {
            NSSound.beep()
            return
        }
        panelClosing = false
        if phase == .idle {
            rebuildSources()
            rebuildMicrophones()
            rebuildCameras()
            restoreChoices()
            if recorder.state == .idle, previewFailure != nil { recorder.discardPreparedCamera() }
        }
        rebuildDestinations()
        refreshSizeNote()
        fitWindowToContent()
        floatAgain()
        if NSApp.isActive {
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.orderFrontRegardless()
        }
        armSyncTimer()
        observeDevices()
        syncCameraPreview()
    }

    /// One second, while the panel is up: the Record Into rows follow the
    /// documents that open and close and the one in front — while idle,
    /// which `rebuildDestinations` itself decides — and the camera preview
    /// steps again (CAM-7 (5)).
    private func armSyncTimer() {
        guard syncTimer == nil else { return }
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            guard self.window?.isVisible == true else { return }
            self.rebuildDestinations()
            self.syncCameraPreview()
        }
    }

    // `syncPhase()` and `refreshStatusLabel()` — the phases drawn — are
    // `+Pause.swift`'s since the R2 review, the base file's toll.

    func setNote(_ text: String) {
        noteLabel.stringValue = text
        noteLabel.isHidden = text.isEmpty
        fitWindowToContent()
    }

    /// The window takes the card's fitting size, keeping its TOP-LEFT where
    /// it was — `setContentSize` would keep the bottom-left and walk the
    /// title bar up the screen every time the note appeared — and then
    /// CONSTRAINED to its screen (`window.screen`, else the main one), so a
    /// panel whose bottom edge sits near the Dock is pushed up when the
    /// countdown grows it rather than growing under the Dock (R1 review;
    /// measured, the numeral adds 88 pt below the rows and a note 42 more).
    /// `setFrame` itself constrains nothing — a window can be put anywhere
    /// programmatically, on screen or off — which is why the call is
    /// explicit.
    func fitWindowToContent() {
        guard let window else { return }
        card.layoutSubtreeIfNeeded()
        let content = NSRect(origin: .zero, size: card.fittingSize)
        var frame = window.frameRect(forContentRect: content)
        let current = window.frame
        frame.origin = NSPoint(x: current.minX, y: current.maxY - frame.height)
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        frame = window.constrainFrameRect(frame, to: screen)
        window.setFrame(frame, display: window.isVisible)
    }
}
