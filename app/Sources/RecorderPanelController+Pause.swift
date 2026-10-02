import AppKit

/// Pause and resume from the panel's side, the one door into a hidden
/// recording's controls, and the phases drawn (road map 3, R2c) —
/// `RecorderPanelController.swift`'s sixth file, NEW rather than cut for its
/// first two members: they are the whole of what the panel adds for a pause,
/// and `+Recording.swift` and the base file were both within a dozen lines
/// of the 400-line cap when R2 began. `syncPhase` and `refreshStatusLabel`
/// then MOVED here from the base file when the R2 review's fixes took it
/// over the cap — the base file's toll, paid along the line the footnote
/// draws: its `.paused` and `.stopping` arms are what the pause added, and
/// `syncPhase` is its one caller besides the tick.
///
/// **Neither pause member is reachable from the panel's own controls** but
/// in a voice-over, whose panel stays up with a Pause / Resume button
/// (`+VoiceOver.swift`). The panel is off screen for every other recording
/// (decision 7), so Pause Recording
/// and Resume Recording are rows of the status item's menu, which calls
/// these through the closures `recordingDidStart` hands it, and File ▸
/// Pause/Resume Recording (`AppDelegate+Recording.swift`), the second door,
/// which calls them for the panel's own recording (#98). The panel's
/// phase — `.recording ⇄ .paused` — follows the recorder's own `pause()` /
/// `resume()` (`ScreenRecorder+Pause.swift`), which are synchronous and
/// throw. The phase moves only AFTER the call returns
/// without throwing, so the panel never claims a state the recorder
/// refused: a pause that could not close the segment's file leaves the
/// recorder `.recording` and the panel with it, and a resume whose output
/// could not be added leaves both `.paused`.
///
/// **The two refusals are answered differently, on purpose.** A refused
/// pause BEEPS: the recorder is still recording, nothing was lost, and the
/// panel is hidden, so a note there would be read by nobody until the
/// landing, by which time it would be stale. A refused resume keeps the
/// recorder's sentence as `resumeProblem` and stays paused: the stream still
/// captures but no file is taking it, so what the person does next — try
/// again, or stop and land what was recorded — depends on the sentence, and
/// the landing's reveal (`revealIfNoted`, `+Landing.swift`) brings the
/// panel back with that sentence in its note when they stop. The sentence
/// is STATE and never text read back off the label (R2 review): the live
/// note is rebuilt from `[microphoneProblem, resumeProblem]` at every tick
/// (`syncMicrophoneNote`, over `liveNote` below), so a microphone
/// did-finish landing late cannot wipe it and a retried resume replaces it
/// rather than appending a second copy; and `landingNote` takes it as an
/// argument, so the landing's note carries it where the first shape — each
/// end replacing the label whole — dropped it, and the reveal showed
/// nothing. A resume that LANDS clears it: a sentence about a refusal the
/// person has since got past would bring the panel back with nothing true
/// to say.
///
/// A Stop while paused (`stopRecording`, `record(_:)`, File ▸ Stop
/// Recording) goes to `recorder.stop()` exactly as one while recording
/// does — the recorder's `.paused` arm takes the same finishing path with
/// the segment's output already closed — and the status item comes down at
/// `recordingEnded` as ever. The tick runs through `.paused` (`armTick`):
/// the meter poll is a no-op there, the recorder having silenced the bar at
/// the pause, and `elapsed` is frozen, so the footnote and the item hold
/// still on their own.
extension RecorderPanelController {
    // MARK: - Pause and resume

    /// The status item's Pause Recording, and File ▸ Pause Recording's for
    /// the panel's own recording. `.recording` → `.paused`; any
    /// other phase beeps — the row was clicked in the moment between a Stop
    /// and the item coming down — and so does any throw, `.alreadyPaused`
    /// among them (the header).
    func pauseRecording() {
        guard phase == .recording else {
            NSSound.beep()
            return
        }
        do {
            try recorder.pause()
            phase = .paused
        } catch {
            NSSound.beep()
        }
    }

    /// The status item's Resume Recording, and File ▸ Resume Recording's.
    /// `.paused` → `.recording`, with
    /// the refused-resume sentence cleared; any other phase beeps. A throw
    /// leaves the phase paused and keeps the recorder's sentence as
    /// `resumeProblem`, REPLACING an earlier one, redrawn into the note at
    /// once rather than at the tick's next turn (the header).
    func resumeRecording() {
        guard phase == .paused else {
            NSSound.beep()
            return
        }
        do {
            try recorder.resume()
            resumeProblem = nil
            phase = .recording
        } catch {
            resumeProblem = error.localizedDescription
            syncMicrophoneNote()
        }
    }

    /// The live note's two parts, in order: the microphone's sentence, with
    /// the fact that the picture is still recording (a silent meter alone
    /// reads as a broken recording), then a refused resume's; empty with
    /// neither. Pure, so a probe can pin the composition without a recorder.
    static func liveNote(microphoneProblem: String?, resumeProblem: String?) -> String {
        var sentences: [String] = []
        if let microphoneProblem {
            sentences.append(
                "The microphone stopped: \(microphoneProblem) The picture is still recording.")
        }
        if let resumeProblem { sentences.append(resumeProblem) }
        return sentences.joined(separator: " ")
    }

    // MARK: - The hidden recording's one door

    /// The quit guard's call (`AppDelegate.applicationShouldTerminate`).
    /// While this panel is hidden for its recording `show()` can only beep,
    /// and a beep tells a person who paused and forgot nothing — so the
    /// status item's menu is opened instead, Pause or Resume and Stop put
    /// in front of them (`RecorderStatusItem.openMenu`); the beep is kept
    /// for the one case with no item to open. Any other recording — a
    /// tool's, which File ▸ Stop Recording ends — shows the panel as before.
    func revealControls() {
        guard hiddenForRecording else {
            show()
            return
        }
        if statusItem?.openMenu() != true { NSSound.beep() }
    }

    // MARK: - The phases, drawn

    /// Draws the phase: the button's title and enabled state, the controls
    /// locked while anything is in flight, the countdown numeral, the
    /// footnote, and the window refitted to whatever appeared or went.
    func syncPhase() {
        syncControlsEnabled()
        syncPauseButton()
        var countdown: String?
        switch phase {
        case .idle:
            recordButton.title = "Record"
            recordButton.isEnabled = true
        case .countdown(let remaining):
            recordButton.title = "Cancel"
            recordButton.isEnabled = true
            countdown = "\(remaining)"
        case .starting:
            recordButton.title = "Starting…"
            recordButton.isEnabled = false
        case .recording, .paused:
            recordButton.title = "Stop"
            recordButton.isEnabled = true
        case .stopping:
            recordButton.title = "Stopping…"
            recordButton.isEnabled = false
        case .landing:
            recordButton.title = "Adding…"
            recordButton.isEnabled = false
        }
        recordButton.invalidateIntrinsicContentSize()
        countdownLabel.stringValue = countdown ?? ""
        countdownLabel.isHidden = countdown == nil
        refreshStatusLabel()
        fitWindowToContent()
    }

    /// The footnote: the folder while idle, the coral dot and the elapsed
    /// time while recording, the pause glyph and the frozen time while
    /// paused — faint, because the dot's colour means "capturing" — and
    /// through `.stopping` whichever of those two it last showed, left
    /// UNTOUCHED (R2 review): the phase no longer says whether the Stop
    /// came from paused, `elapsed` is frozen at the stop call, and
    /// redrawing the arm as recording brought the coral dot back over a
    /// finish that captures nothing. The status item keeps its mark the
    /// same way (`RecorderStatusItem.freeze`, called by `stopRecording`).
    func refreshStatusLabel() {
        switch phase {
        case .recording:
            statusLabel.stringValue = "● " + RecorderStatusItem.label(for: recorder.elapsed)
            statusLabel.textColor = DS.meterClip
        case .paused:
            statusLabel.stringValue =
                RecorderStatusItem.pauseGlyph + " " + RecorderStatusItem.label(for: recorder.elapsed)
            statusLabel.textColor = DS.textFaint
        case .stopping:
            break
        default:
            statusLabel.stringValue =
                "saved in " + (RecordingFiles.folder().path as NSString).abbreviatingWithTildeInPath
            statusLabel.textColor = DS.textFaint
        }
    }
}
