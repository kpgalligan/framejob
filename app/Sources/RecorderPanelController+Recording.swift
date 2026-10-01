import AVFoundation
import AppKit
import ScreenCaptureKit

/// Everything the recorder panel does from Record pressed to the recording
/// RUNNING (road map 3, R1c) — the countdown, the start, the stop —
/// `RecorderPanelController.swift`'s third file. The grants a press checks
/// first are `+Grants.swift`. The recording's END
/// and its landing are `+Landing.swift`, and the window picker is
/// `+Picker.swift`, both cut out along the lines `recordingEnded` and
/// `presentPicker` draw when the R1 review's fixes put this file past the
/// 400-line cap; the pause and the resume, and the phases drawn, are
/// `+Pause.swift` (R2c).
///
/// **Before the grants, the source** (R1 review): Record with the Source row
/// reading "Window…" and no picked filter refuses FIRST, by name, and starts
/// no countdown — `currentChoice()` would otherwise quietly fall back to the
/// main display and record the wrong thing. The picker is NOT presented from
/// the guard: a refusal that puts up a system UI is not a refusal.
///
/// **The start is bounded and numbered** (R1 review). `.starting` used to
/// have no ceiling and no exit: `ScreenRecorder.shareableContent` can hold
/// its answer for tens of seconds on a locked console (measured ~37 s), and
/// a panel waiting on it showed "Starting…" with the button disabled and no
/// way back. Now each press of Record is one ATTEMPT with a number
/// (`startGeneration`), the lookup's completion carries the number and is
/// ignored once it is stale, and a one-shot timer at
/// `ScreenRecorder.armCeiling` fails the attempt with `.startTimedOut` while
/// the lookup is still pending. Once `launch` has handed the attempt to the
/// recorder its own arm ceiling is the bound (the same sentence, from the
/// start completion) and the panel's timer is cancelled, so the two cannot
/// both fire on one attempt.
///
/// **Stop while starting** (lane C's flag, closed by reading the seam):
/// after `launch` the recorder is arming and `stop()` is HELD — finishing
/// begins the moment the start lands, and the end arrives through the
/// session's `onFinish` like any other; a start that FAILS instead answers
/// the start completion alone, `onFinish` is never called for it, and
/// `startFailed` is the only thing that runs. Before `launch` there is
/// nothing to stop: `abandonStart` bumps the generation so the pending
/// answer is dropped, and the panel goes idle. Without that arm a Stop while
/// the lookup was pending left the panel at "Stopping…" for good, because
/// the answer then found the phase moved on and did nothing.
///
/// **The microphone is prepared at the countdown's start** (R1 review;
/// `ScreenRecorder+Microphone.swift` says why — `startRunning()`'s first-use
/// cost, up to 0.4 s of voice missing from the file) and discarded on cancel,
/// on close and on a refused start, so an input never stays open past the
/// recording it was for. **The meter moves during the countdown** (#98 c):
/// `beginCountdown` arms the tick, which through `.countdown` and
/// `.starting` does nothing but `publishMicrophoneLevel()`, read from the
/// prepared session; the discard publishes the silence. **The tick shows a
/// microphone problem the moment the recorder reports one**: the picture
/// keeps recording, the meter goes silent, and the note says so rather than
/// leaving a dead bar.
///
/// **Two timers run in `.common` modes** — the countdown and the 30 Hz tick
/// — because a status item's menu runs the run loop in event-tracking mode
/// while it is open, and a default-mode timer stalls there: the elapsed
/// label in the menu bar froze at the one moment a person was looking at
/// it. `RecorderStatusItem`'s doc carries the same sentence from its side.
extension RecorderPanelController {
    /// The note for Record pressed over "Window…" with nothing picked.
    static let chooseWindowSentence = "Choose a window with Window… first, or pick a display."
    /// The note for a Stop that arrived before the recording had begun.
    static let abandonedSentence = "Stopped before the recording began; nothing was recorded."

    // MARK: - Record and Stop

    /// The Record button in every phase: start, cancel the countdown, or
    /// stop; a beep while the recorder is finishing or the panel is adding.
    @objc func record(_ sender: Any?) {
        switch phase {
        case .idle:
            beginIfGranted()
        case .countdown:
            cancelCountdown()
        case .recording, .paused, .starting:
            stopRecording()
        case .stopping, .landing:
            NSSound.beep()
        }
    }

    /// Stop, from the panel's button, the status item's menu or File ▸ Stop
    /// Recording. A recording the panel did not start (the `record_screen`
    /// tool's) is not this panel's to stop — `AppDelegate.newRecording`
    /// routes that one to the recorder directly — so anything but a panel
    /// recording beeps. Paused is stopped exactly as recording is: the
    /// recorder's `.paused` arm takes the same finishing path with the
    /// segment's output already closed — and the status item is FROZEN at
    /// the mark it shows, because the tick goes on through `.stopping` with
    /// `paused` false and would bring the coral dot back over a finish that
    /// captures nothing (R2 review; the footnote holds its mark the same
    /// way, `refreshStatusLabel`). While `.starting`: launched, the stop is
    /// held by the recorder and lands through `onFinish`; not yet, the
    /// attempt is abandoned (the type doc).
    func stopRecording() {
        switch phase {
        case .recording, .paused:
            statusItem?.freeze()
            phase = .stopping
            recorder.stop()
        case .starting where launched:
            phase = .stopping
            recorder.stop()
        case .starting:
            abandonStart()
        default:
            NSSound.beep()
        }
    }

    // MARK: - The grants

    private func beginIfGranted() {
        if sourcePopup.selectedItem?.tag == Self.windowTag, pickedFilter == nil {
            setNote(Self.chooseWindowSentence)
            return
        }
        guard checkScreenRecordingGrant(), checkMicrophoneGrant() else { return }
        setNote("")
        beginCountdown()
    }

    // MARK: - The countdown

    /// 3, 2, 1 in the panel, one second each — `TimelineView.flashRefusal`'s
    /// shape: `[weak self]`, self-invalidating — added to the main run loop
    /// in `.common` modes (the type doc). The Record button reads Cancel
    /// meanwhile, and a click on it or closing the panel ends the countdown
    /// with nothing started. The microphone the choice names is prepared
    /// here, after the grants and before the first second has passed, so its
    /// start cost is paid while the numeral is still on screen — and the
    /// tick is armed at once, so the meter reads that session through the
    /// 3-2-1 (#98 c).
    func beginCountdown() {
        countdownTimer?.invalidate()
        phase = .countdown(Self.countdownSeconds)
        recorder.prepareMicrophone(currentChoice().microphone)
        armTick()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, case .countdown(let remaining) = self.phase else {
                timer.invalidate()
                return
            }
            if remaining > 1 {
                self.phase = .countdown(remaining - 1)
            } else {
                timer.invalidate()
                self.countdownTimer = nil
                self.startRecording()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        recorder.discardPreparedMicrophone()
        if case .countdown = phase { phase = .idle }
    }

    // MARK: - Start

    /// The choice as the controls stand, then the filter: a picked window's
    /// is the picker's own; a display's is built from the shareable content
    /// and leaves out what `recordingExclusion(includeReelcutWindows:)`
    /// names (`ScreenRecorder.filter(for:in:excluding:)`) — Reelcut's own
    /// application, which keeps the document windows out of a display
    /// recording's picture, or with Include Reelcut windows on the panel's
    /// window alone. One attempt, numbered and bounded (the type doc).
    private func startRecording() {
        let choice = currentChoice()
        let exclusion = recordingExclusion(includeReelcutWindows: choice.includeReelcutWindows)
        startGeneration += 1
        let generation = startGeneration
        launched = false
        phase = .starting
        startTimer?.invalidate()
        startTimer = Timer.scheduledTimer(
            withTimeInterval: ScreenRecorder.armCeiling, repeats: false
        ) { [weak self] _ in self?.armTimedOut(generation: generation) }
        if choice.source == .picked, let filter = pickedFilter {
            launch(filter: filter, choice: choice)
            return
        }
        ScreenRecorder.shareableContent { [weak self] outcome in
            guard let self, self.phase == .starting, generation == self.startGeneration else {
                return
            }
            switch outcome {
            case .failure(let error):
                self.startFailed(error)
            case .success(let content):
                do {
                    let filter = try ScreenRecorder.filter(
                        for: choice.source, in: content, excluding: exclusion)
                    self.launch(filter: filter, choice: choice)
                } catch {
                    self.startFailed(error)
                }
            }
        }
    }

    /// The arm ceiling, for the lookup half of an attempt: a stale number, a
    /// phase that moved on, or an attempt the recorder already holds (its
    /// own ceiling reports that one) does nothing. Internal so a probe can
    /// fire it without a lookup.
    func armTimedOut(generation: Int) {
        guard phase == .starting, generation == startGeneration, !launched else { return }
        startFailed(RecorderError.startTimedOut)
    }

    /// A Stop before the recorder was handed the attempt: the pending
    /// lookup's answer is orphaned by the generation bump, the prepared
    /// microphone let go, and the panel idle with a note saying nothing was
    /// recorded.
    private func abandonStart() {
        startGeneration += 1
        startTimer?.invalidate()
        startTimer = nil
        recorder.discardPreparedMicrophone()
        phase = .idle
        setNote(Self.abandonedSentence)
    }

    private func launch(filter: SCContentFilter, choice: RecordingChoice) {
        // From here the recorder's arm ceiling is the bound.
        startTimer?.invalidate()
        startTimer = nil
        launched = true
        recorder.start(
            filter: filter, choice: choice,
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

    /// A refused, failed or timed-out start: idle, the note, and the
    /// microphone the countdown prepared let go.
    func startFailed(_ error: any Error) {
        startTimer?.invalidate()
        startTimer = nil
        launched = false
        recorder.discardPreparedMicrophone()
        phase = .idle
        setNote(error.localizedDescription)
    }

    /// The recording chrome (decision 7): the status item in the menu bar
    /// with Pause, Resume and Stop (`+Pause.swift` for the first two), the
    /// 30 Hz tick, and the panel ordered OUT for EVERY source until the
    /// landing has something to say — whether or not it was on screen
    /// (`show()` beeps meanwhile; `showWhenLanded` remembers, and
    /// `revealIfNoted` reads it). R1 hid it for a picked window only,
    /// because a display's filter excludes Reelcut (R0 q3); the user asked
    /// for the dialog to go away whatever is recorded, and the menu bar's
    /// item is the recording's controls now.
    private func recordingDidStart() {
        // A stop asked for while arming has moved the phase on; the end
        // comes through `recordingEnded`.
        guard phase == .starting else { return }
        phase = .recording
        resumeProblem = nil
        setNote("")
        let item = RecorderStatusItem(
            onPause: { [weak self] in self?.pauseRecording() },
            onResume: { [weak self] in self?.resumeRecording() },
            onStop: { [weak self] in self?.stopRecording() })
        item.show()
        statusItem = item
        armTick()
        showWhenLanded = window?.isVisible == true
        hiddenForRecording = true
        window?.orderOut(nil)
    }

    // MARK: - The tick

    /// 30 Hz from the countdown's start, in `.common` modes (the type doc).
    /// Through `.countdown` and `.starting` it ONLY meters — the prepared
    /// session's level (#98 c; the recorder publishes nothing while
    /// arming, so the bar holds its last pre-roll level for that instant).
    /// While recording or paused: the microphone's level into the panel's
    /// own meter (`ScreenRecorder.publishMicrophoneLevel`, a no-op without
    /// a microphone and while paused, the recorder having silenced the
    /// bar), the elapsed time in the footnote and in the status item — with
    /// `paused`, which is what flips the item's menu — and a microphone
    /// problem into the note. `recordingDidStart` re-arms it.
    private func armTick() {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            switch self.phase {
            case .countdown, .starting:
                self.recorder.publishMicrophoneLevel()
                return
            default:
                break
            }
            guard self.phase == .recording || self.phase == .paused || self.phase == .stopping
            else {
                timer.invalidate()
                return
            }
            self.recorder.publishMicrophoneLevel()
            self.refreshStatusLabel()
            self.statusItem?.update(elapsed: self.recorder.elapsed, paused: self.phase == .paused)
            self.syncMicrophoneNote()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    /// The live note — what the panel says while a recording runs or is
    /// paused — rebuilt at every tick from its two PARTS and never from the
    /// label's text: `ScreenRecorder.microphoneProblem` the moment it is
    /// non-nil (a device unplugged, a writer that gave up), and
    /// `resumeProblem`, a resume the recorder refused (`+Pause.swift`,
    /// whose `liveNote` is the composition). Composing from the label was
    /// the R2 review's defect: a microphone did-finish landing late
    /// replaced a note that did not yet contain its sentence and wiped the
    /// resume's, and each retried resume appended its sentence again. Set
    /// only on a change, because `setNote` refits the window and this runs
    /// at 30 Hz.
    func syncMicrophoneNote() {
        let text = Self.liveNote(
            microphoneProblem: recorder.microphoneProblem, resumeProblem: resumeProblem)
        if noteLabel.stringValue != text { setNote(text) }
    }

    func disarmTick() {
        tickTimer?.invalidate()
        tickTimer = nil
    }
}
