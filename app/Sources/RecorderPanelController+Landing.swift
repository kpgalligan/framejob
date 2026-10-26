import AppKit

/// The recorder panel from the recording's END to the note that says where
/// it went (road map 3, R1c) — `RecorderPanelController.swift`'s fourth
/// file, cut out of `+Recording.swift` along the line `recordingEnded`
/// draws when the R1 review's fixes took that file past the 400-line cap:
/// everything before the session's `onFinish` fires stays there, everything
/// after it is here.
///
/// **One door for a finished recording.** The session's `onFinish` — called
/// exactly once whoever ended the recording: the panel's Stop, the status
/// item's, the system indicator's, a display that slept, a failure — arrives
/// at `recordingEnded`, which tears the recording chrome down (the tick, the
/// status item, and the `hiddenForRecording` flag that made `show()` beep —
/// clearing it, and showing NOTHING) and then lands. A DOCUMENT target
/// commits the placement through the document's
/// own door (`performGroupedEdit`, then `generateCaches`, the selection, and
/// the editor told through `viewStateDidChange`); a NEW PROJECT is
/// `ProjectDocument.untitled(around:)`, which does everything. A document
/// mid-drag is not committed over the gesture's base handle: the landing is
/// retried from a half-second timer until the drag ends, bounded at forty
/// tries — **20 s, kept** (lane C's flag, closed by reading): a landing that
/// waited for ever would hold the file's note back for ever, and the note
/// after the bound names the file, which is on disk either way — and on
/// either failure the note names the FILE, which is on disk whatever went
/// wrong after it. That timer stays in the DEFAULT run-loop mode on
/// purpose, unlike the countdown and the tick: a drag runs the loop in
/// tracking mode, so the retry fires when the drag ENDS, which is the
/// moment it is for.
///
/// **The commit is checked by its handle** (R1 review). `performGroupedEdit`
/// answers nothing: a refusal beeps or puts up the core's sentence on the
/// document's window and returns, and the panel — which cannot see either
/// — used to report "added" over a project with nothing in it. The
/// document's `project` handle changes ONLY on success (`applyEdit`'s three
/// outcomes), so `land` reads it before the commit and compares after, and
/// an unchanged handle is a failed landing with the file's path in the
/// note. The trial in `RecordingLanding.placement` sees everything the
/// commit will, so the arm is reached only by a race the trial cannot see —
/// an edit landing between the two on the same run-loop turn — and it is
/// there because the alternative is a note that lies.
///
/// **The note says six things, in order**, through `landingNote`, a pure
/// function so a probe can pin every combination without a landing: how the
/// recording ended when it was not this panel's own Stop (`.stopped` is the
/// status item's Stop too; `.userStopped` is the SYSTEM's indicator, and the
/// sentence names it so, now that Frame Job's own item is a menu-bar item as
/// well); that the document the person CHOSE had closed, when the choice
/// was a document and the landing opened a new project (R1 review — the
/// fallback is exact, and a person who chose "Untitled 2" should not have
/// to work out why a new window appeared instead); the segments left out
/// because their movie would not probe (`unreadableNote`, #97), each naming
/// the files it kept; the microphone's
/// problem, when the recording is a `.success` whose `micProblem` is set —
/// a success, not an error, so the picture lands first and the sentence
/// follows it; a resume the recorder refused (`resumeProblem`, STATE on the
/// panel and never text read back off the label — the R2 review's defect:
/// each end replaced the label whole, so after a refused resume and a clean
/// Stop the note was empty and the reveal showed nothing, the opposite of
/// what `+Pause.swift` promised); and the placement's own notes, one per
/// file the landing could not place. `failedToLand` names every file
/// through `filesClause` and carries the unreadable segments', the
/// microphone's and the resume's sentences too.
///
/// **The panel comes back ONLY with something to say** (decision 7, R2c).
/// It ordered out at `recordingDidStart` whatever the source, and each of
/// the three ends — `landed`, `failedToLand`, the failure arm of
/// `recordingEnded` — finishes with `revealIfNoted()`, AFTER its note is
/// set: the panel is ordered front when it was on screen as the recording
/// began (`showWhenLanded`) and the note is non-empty, and `showWhenLanded`
/// is cleared either way. A clean recording lands in its document or opens
/// its project and the panel stays away; ⌥⌘N shows it again. The reveal
/// belongs to the END and not to `recordingEnded`, because the deferred
/// landing's retries can put twenty seconds between the two, and a panel
/// shown with "Adding…" and no note yet is the dialog the user asked to be
/// rid of.
extension RecorderPanelController {
    static let landingRetryInterval: TimeInterval = 0.5
    static let landingRetryLimit = 40
    static let destinationClosedSentence =
        "The document you chose was closed, so the recording opened as a new project."

    // MARK: - The end, and the landing

    func recordingEnded(_ outcome: Result<RecordingResult, Error>) {
        disarmTick()
        statusItem?.remove()
        statusItem = nil
        launched = false
        hiddenForRecording = false
        switch outcome {
        case .failure(let error):
            phase = .idle
            setNote(
                [error.localizedDescription, resumeProblem].compactMap { $0 }
                    .joined(separator: " "))
            revealIfNoted()
        case .success(let result):
            phase = .landing
            landingAttempts = 0
            land(result)
        }
    }

    func land(_ result: RecordingResult) {
        switch RecordingLanding.resolve(result.choice.destination) {
        case .document(let document):
            guard !document.isLiveEditing else {
                deferLanding(result)
                return
            }
            do {
                let placement = try RecordingLanding.placement(result, in: document, place: true)
                let before = document.project
                document.performGroupedEdit(RecordingLanding.actionName, placement.ops)
                // The handle changes only on success (the type doc).
                guard document.project !== before else {
                    failedToLand(
                        result,
                        ReelCoreError(
                            message: "the project refused the placement and nothing was added"))
                    return
                }
                document.generateCaches()
                // Every segment's clip, microphone clips included (R2b); a
                // segment that minted none is a nil entry, and its sentence
                // is in `placement.notes`.
                document.selection = Set(
                    (placement.clipIds + placement.micClipIds + placement.leftOutMicClipIds)
                        .compactMap { $0 })
                Self.editor(of: document)?.viewStateDidChange()
                landed(result, asNewProject: false, notes: placement.notes)
            } catch {
                failedToLand(result, error)
            }
        case .newProject:
            do {
                let (_, notes) = try ProjectDocument.untitled(around: result)
                landed(result, asNewProject: true, notes: notes)
            } catch {
                failedToLand(result, error)
            }
        }
    }

    /// A drag is in progress: try again when it has had half a second to
    /// end, up to the limit — a landing over the gesture's base handle would
    /// be undone by the gesture's own end.
    private func deferLanding(_ result: RecordingResult) {
        landingAttempts += 1
        guard landingAttempts <= Self.landingRetryLimit else {
            let waited = Int(Double(Self.landingRetryLimit) * Self.landingRetryInterval)
            failedToLand(
                result,
                ReelCoreError(message: "A drag was still in progress after \(waited) s."))
            return
        }
        landingTimer?.invalidate()
        landingTimer = Timer.scheduledTimer(
            withTimeInterval: Self.landingRetryInterval, repeats: false
        ) { [weak self] _ in
            self?.landingTimer = nil
            self?.land(result)
        }
    }

    /// Back to idle; the note is `landingNote`'s, over the placement's own
    /// notes — the unreadable segments' sentences followed by what became of
    /// their readable voices (#181 item 2), said only here, on a landing
    /// that succeeded — and the reveal last.
    private func landed(_ result: RecordingResult, asNewProject: Bool, notes: [String]) {
        phase = .idle
        rebuildDestinations()
        let leftOut = [result.unreadableNote, result.leftOutVoiceNote].compactMap { $0 }
        setNote(
            Self.landingNote(
                stoppedBy: result.stoppedBy, chosen: result.choice.destination,
                landedAsNewProject: asNewProject, micProblem: result.micProblem,
                resumeProblem: resumeProblem, notes: notes,
                unreadable: leftOut.isEmpty ? nil : leftOut.joined(separator: " "),
                camera: result.camera))
        revealIfNoted()
    }

    /// The files are on disk whatever went wrong after them, so the note
    /// names every one (`filesClause`: each segment's movie, and the
    /// microphone files that landed) — then what became of an unreadable
    /// segment, the microphone, the camera (its `problem` and warm-up `note`,
    /// spec §11 CAM-5) and a refused resume, when the result or the panel
    /// carries those sentences — and the reveal last.
    private func failedToLand(_ result: RecordingResult, _ error: any Error) {
        phase = .idle
        var note =
            "The recording was saved at \(result.filesClause) but could not be added: "
            + error.localizedDescription
        for sentence in [
            result.unreadableNote, result.micProblem, result.camera?.problem, result.camera?.note,
            resumeProblem,
        ].compactMap({ $0 })
        {
            note += " " + sentence
        }
        setNote(note)
        revealIfNoted()
    }

    /// The panel back on screen after a landing, ONLY when it was on screen
    /// as the recording began and the note has something in it (the type
    /// doc). Called LAST by each of the three ends, after the note is set —
    /// which is the whole point — and reached after the deferred landing's
    /// retries as well, since nothing before it clears `showWhenLanded`.
    /// Cleared either way, so a later `show()` of the person's own is not
    /// mistaken for this one. Internal so a probe can drive both ways.
    func revealIfNoted() {
        if showWhenLanded, !noteLabel.stringValue.isEmpty { window?.orderFront(nil) }
        showWhenLanded = false
    }

    /// The landing's note (the type doc): the stop's sentence unless the
    /// stop was this panel's own; the closed-document sentence when a chosen
    /// document was gone by the time the recording ended; the unreadable
    /// segments' sentences; the microphone's problem; a refused resume's
    /// sentence; then the placement's notes. Empty for the ordinary case, so
    /// `setNote` hides the label. The R2 arguments, #97's `unreadable` and
    /// CR1c's `camera` are LAST and default, so the probe's R1 rows read as
    /// they did. A CAMERA result (spec §11 CAM-5) says its own stop — the
    /// camera's `problem`, else that it stopped on its own — in place of the
    /// display's, and its warm-up `note` follows the microphone's problem.
    static func landingNote(
        stoppedBy: StopReason, chosen: RecordingDestination, landedAsNewProject: Bool,
        micProblem: String?, resumeProblem: String? = nil, notes: [String] = [],
        unreadable: String? = nil, camera: RecordingCamera? = nil
    ) -> String {
        var sentences: [String] = []
        switch stoppedBy {
        case .stopped:
            break
        case .userStopped:
            sentences.append(
                "Stopped from the system's screen-recording indicator; the recording was added.")
        case .systemStopped:
            if let camera {
                sentences.append(
                    (camera.problem ?? "The camera stopped on its own.")
                        + " What was captured was added.")
            } else {
                sentences.append(
                    "The system stopped the recording (the display slept or went away); "
                        + "what was captured was added.")
            }
        }
        if case .document = chosen, landedAsNewProject {
            sentences.append(destinationClosedSentence)
        }
        if let unreadable { sentences.append(unreadable) }
        if let micProblem { sentences.append(micProblem) }
        if let note = camera?.note { sentences.append(note) }
        if let resumeProblem { sentences.append(resumeProblem) }
        sentences.append(contentsOf: notes)
        return sentences.joined(separator: " ")
    }

    /// `AgentServer.editor(_:)`'s lookup; nil for a windowless document.
    static func editor(of document: ProjectDocument) -> EditorViewController? {
        document.windowControllers
            .compactMap { $0.contentViewController as? EditorViewController }
            .first
    }
}
