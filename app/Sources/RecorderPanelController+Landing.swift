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
/// status item, the panel shown again if a picked source hid it) and then
/// lands. A DOCUMENT target commits the placement through the document's
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
/// **The note says three things, in order**, through `landingNote`, a pure
/// function so a probe can pin every combination without a landing: how the
/// recording ended when it was not this panel's own Stop; that the document
/// the person CHOSE had closed, when the choice was a document and the
/// landing opened a new project (R1 review — the fallback is exact, and a
/// person who chose "Untitled 2" should not have to work out why a new
/// window appeared instead); and the microphone's problem, when the
/// recording is a `.success` whose `micProblem` is set — a success, not an
/// error, so the picture lands first and the sentence follows it.
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
        if hiddenForRecording {
            hiddenForRecording = false
            if showWhenLanded { window?.orderFront(nil) }
            showWhenLanded = false
        }
        switch outcome {
        case .failure(let error):
            phase = .idle
            setNote(error.localizedDescription)
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
                document.selection = Set([placement.clipId, placement.micClipId].compactMap { $0 })
                Self.editor(of: document)?.viewStateDidChange()
                landed(result, asNewProject: false)
            } catch {
                failedToLand(result, error)
            }
        case .newProject:
            do {
                _ = try ProjectDocument.untitled(around: result)
                landed(result, asNewProject: true)
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

    /// Back to idle; the note is `landingNote`'s.
    private func landed(_ result: RecordingResult, asNewProject: Bool) {
        phase = .idle
        rebuildDestinations()
        setNote(
            Self.landingNote(
                stoppedBy: result.stoppedBy, chosen: result.choice.destination,
                landedAsNewProject: asNewProject, micProblem: result.micProblem))
    }

    /// The file is on disk whatever went wrong after it, so the note says
    /// where — and what became of the microphone, when that is a second
    /// sentence the result carries.
    private func failedToLand(_ result: RecordingResult, _ error: any Error) {
        phase = .idle
        var note =
            "The recording was saved at \(result.descriptor.path) but could not be added: "
            + error.localizedDescription
        if let problem = result.micProblem { note += " " + problem }
        setNote(note)
    }

    /// The landing's note (the type doc): the stop's sentence unless the
    /// stop was this panel's own; the closed-document sentence when a chosen
    /// document was gone by the time the recording ended; the microphone's
    /// problem last. Empty for the ordinary case, so `setNote` hides the
    /// label.
    static func landingNote(
        stoppedBy: StopReason, chosen: RecordingDestination, landedAsNewProject: Bool,
        micProblem: String?
    ) -> String {
        var sentences: [String] = []
        switch stoppedBy {
        case .stopped:
            break
        case .userStopped:
            sentences.append("Stopped from the menu bar; the recording was added.")
        case .systemStopped:
            sentences.append(
                "The system stopped the recording (the display slept or went away); "
                    + "what was captured was added.")
        }
        if case .document = chosen, landedAsNewProject {
            sentences.append(destinationClosedSentence)
        }
        if let micProblem { sentences.append(micProblem) }
        return sentences.joined(separator: " ")
    }

    /// `AgentServer.editor(_:)`'s lookup; nil for a windowless document.
    static func editor(of document: ProjectDocument) -> EditorViewController? {
        document.windowControllers
            .compactMap { $0.contentViewController as? EditorViewController }
            .first
    }
}
