import AppKit

/// The Source row "Microphone Only" — a VOICE-OVER from the panel (#99;
/// spec §11 recording, "A voice-over is a recording with no picture") —
/// `RecorderPanelController.swift`'s eighth file, NEW rather than cut: it is
/// the whole of what the panel adds for a recording with no picture, and the
/// base file, `+Rows.swift` and `+Recording.swift` learn it only by a line or
/// two each.
///
/// **The row** is the Source popup's last, directly under "Window…", by tag.
/// It persists for the session only, as a picked window does: no defaults key
/// is written for it, and the display key is left alone while it is chosen.
/// Chosen, it greys System Audio, Show Clicks and Size with their values
/// KEPT, so the panel does not jump under the pointer; Rate stays live (it is
/// a new project's rate), and so do Microphone and Record Into.
///
/// **The press** never reads or asks the Screen Recording grant: Microphone
/// "Off" refuses with a note, and otherwise the Microphone grant is the only
/// one checked (`+Grants.swift`'s `checkMicrophoneGrant`, the panel's one
/// door to it) before the same 3-2-1. The start is `startVoiceOver`, which
/// answers before it returns — there is no lookup and no arming, so no start
/// timer either.
///
/// **The panel STAYS UP while it records** (the owner's choice): the rows are
/// locked as for any recording, the meter is live, the footnote shows the dot
/// or the pause glyph and the elapsed time, Record reads Stop, and a Pause /
/// Resume button stands beside it. `hidesForRecording` is the one decision
/// `recordingDidStart` reads; Close takes the panel away and the recording
/// carries on under the status item.
extension RecorderPanelController {
    /// The Source row, by tag: last, directly under "Window…" (tag 1), with
    /// no separator between them.
    static let voiceOverTag = 2
    static let microphoneOnlyTitle = "Microphone Only"
    static let microphoneOffSentence =
        "Microphone Only records the microphone alone — choose a microphone first."
    static let voiceOverSizeNote = "no picture — the microphone alone"

    var voiceOverSelected: Bool { sourcePopup.selectedItem?.tag == Self.voiceOverTag }

    /// Whether the panel orders out at `recordingDidStart` for `source`.
    static func hidesForRecording(_ source: RecordingSource) -> Bool { source != .voiceOver }

    /// Every control unlocked only while idle; the four screen-only ones
    /// (Include Reelcut windows among them, set only here) greyed besides
    /// while Microphone Only is chosen, their values kept.
    func syncControlsEnabled() {
        let idle = phase == .idle
        let controls: [NSControl] = [
            sourcePopup, microphonePopup, ratePopup, sizePopup, destinationPopup,
            systemAudioSwitch, showClicksSwitch,
        ]
        for control in controls { control.isEnabled = idle }
        let screenOnly = idle && !voiceOverSelected
        let screenControls: [NSControl] = [
            systemAudioSwitch, showClicksSwitch, sizePopup, includeReelcutCheckbox,
        ]
        for control in screenControls {
            control.isEnabled = screenOnly
        }
    }

    /// The Pause / Resume button beside Stop: on screen only while a
    /// voice-over records or is paused — a screen recording's panel is off
    /// screen, and its pause is the status item's.
    func syncPauseButton() {
        let live = phase == .recording || phase == .paused
        voiceOverPauseButton.isHidden = !(voiceOverSelected && live)
        let title = phase == .paused ? "Resume" : "Pause"
        if voiceOverPauseButton.title != title {
            voiceOverPauseButton.title = title
            voiceOverPauseButton.invalidateIntrinsicContentSize()
        }
    }

    /// The button: pause while recording, resume while paused (the status
    /// item's own two calls, `+Pause.swift`); anything else beeps.
    @objc func pauseButtonPressed(_ sender: Any?) {
        switch phase {
        case .recording: pauseRecording()
        case .paused: resumeRecording()
        default: NSSound.beep()
        }
    }

    /// Record with Microphone Only chosen: Off refuses with a note; otherwise
    /// the Microphone grant alone, then the countdown. Screen Recording is
    /// neither read nor asked.
    func beginVoiceOverIfGranted() {
        guard currentChoice().microphone != nil else {
            setNote(Self.microphoneOffSentence)
            return
        }
        floatAgain()
        guard checkMicrophoneGrant() else { return }
        setNote("")
        beginCountdown()
    }

    /// The countdown's end for a voice-over: handed straight to the recorder,
    /// whose answer comes before it returns.
    func launchVoiceOver(_ choice: RecordingChoice) {
        launched = true
        recorder.startVoiceOver(
            choice: choice, mayAsk: true,
            onFinish: { [weak self] outcome in self?.recordingEnded(outcome) }
        ) { [weak self] error in
            guard let self else { return }
            if let error {
                self.startFailed(error)
                return
            }
            self.recordingDidStart()
        }
    }
}
