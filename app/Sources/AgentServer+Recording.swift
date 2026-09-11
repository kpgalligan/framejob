import AVFoundation
import AppKit
import ScreenCaptureKit

/// `record_screen` — File ▸ New Recording… without the panel (road map 3,
/// R1d): `ScreenRecorder.shared`, the object the panel drives, run for a
/// fixed number of seconds from the agent and landed exactly as the panel
/// lands — `RecordingLanding` for the ops, `ProjectDocument.untitled(around:)`
/// for a new project — so the two doors provably do one thing. This file is
/// the wait around the recorder and the argument vocabulary in front of it;
/// `AgentServer+RecordingResult.swift` is what the answer and the refusals
/// SAY, cut off this file at the 400-line cap.
///
/// **Runs on the server thread** (`AgentServer.offMainTools`), `import_media`'s
/// shape and never `transcribe`'s synchronous body: the recorder's every
/// callback lands on MAIN, so a main-thread wait would deadlock, and a
/// recording of up to ten minutes is not a thing the UI may freeze for. Every
/// document touch is an `onMain` hop; every wait is a `DispatchSemaphore`
/// signalled from main with an `AgentBox` carrying the answer across.
///
/// **The refusal ORDER is the contract** (`transcribe`'s rule): the caller's
/// own mistakes FIRST, so they stay reachable with no grant — `seconds`
/// missing or outside 1…600, `display` with `window`, a `rate` or `size`
/// outside the vocabulary, `microphone: true` with the Microphone grant
/// absent (the status WORD in the sentence), and a `project` naming nothing
/// open, answered by `target(_:)`'s own sentence and never turned into a fresh
/// document (server scout: the by-name refusal stands). Then the Screen
/// Recording grant, read synchronously and named with the System Settings
/// pane. Only then the display or window lookup, which cannot be asked
/// without the grant — and a list with NO display in it (a locked console,
/// every display asleep) is named as that rather than as an index out of
/// range. `CGRequestScreenCaptureAccess` and the picker are never called
/// (decision 4): the panel is where a person grants.
///
/// **The target is `.document(recipeKey:)`**, resolved BEFORE the recording
/// and looked up again AFTER it (`RecordingLanding.resolve`): a document that
/// closed meanwhile lands as a new project and the answer says so, as it does
/// for `place: false` in a new project, which still opens the document — the
/// picture IS the document.
///
/// **One hook, three waits.** `start` takes `onFinish`, which the recorder
/// calls EXACTLY ONCE at conclude whoever ended the recording — this tool's
/// `stop()`, the menu bar's status item, the system's own indicator
/// (`.userStopped`), a display that slept (`.systemStoppedStream`), a
/// failure — and never for a start that fails, whose error is the start
/// completion's alone. So the waits are: the start's completion (bounded
/// past the recorder's own `armCeiling`, whose timer answers first); the
/// span, a wait on the FINISH semaphore that `onFinish` ends early when
/// something else ended the recording; then, after `stop()`, the same
/// semaphore again, bounded at `stopCeiling`. `stop()` is sent with NO
/// completion — `onFinish` already lands the result, and a completion would
/// land it twice — and a `stop()` in any state past idle JOINS the finishing
/// under way (the recorder's finding 1), so a person's Stop from the status
/// item a second before the span ends is a stop that lands, never `.busy`.
/// A stop that never concludes within `stopCeiling` is a reported timeout
/// naming the movie the recorder still holds, and main is asked nothing
/// more: the recorder has no cancel, and the recording may yet finish on
/// its own.
///
/// **A recording this tool starts is stoppable from the machine.** Once the
/// start lands it puts up the same `RecorderStatusItem` the panel does
/// (R1 review): a person at the Mac watching an agent record can stop it
/// from the menu bar — the item's Stop is `ScreenRecorder.shared.stop()`,
/// which joins — and the item's elapsed label ticks from a 1 Hz timer on
/// main. Both come down in `onFinish`, before the landing.
extension AgentServer {

    /// Seconds the tool waits for `stop()` to conclude, INDEPENDENT of
    /// `seconds`: the recorder's own `finishCeiling` (past which it probes
    /// whatever is on disk), plus two sequential `MediaImporter.probe`
    /// ceilings of 30 s (`MediaImporter.waitForProbe`'s literal — the movie
    /// is probed, then the microphone file), plus a margin. 75 s. The old
    /// bound was `seconds + 30`, which for a 1 s recording was shorter than
    /// the probes it had to wait for.
    static let stopCeiling: TimeInterval = ScreenRecorder.finishCeiling + 2 * 30 + 5

    // MARK: - The tool

    /// `record_screen` — File ▸ New Recording…. The header has the order.
    func recordScreen(_ a: [String: Any]) throws -> String {
        // `importMedia`'s guard: everything below assumes main is free.
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "record_screen must run on the server thread — its name is missing "
                    + "from AgentServer.offMainTools.")
        }

        // 1. The caller's own mistakes, every one before any grant is read.
        let seconds = try recordingSeconds(a)
        let (displayIndex, windowID) = try recordingSourceArguments(a)
        let rate = try intArg(a, "rate") ?? 60
        guard rate == 30 || rate == 60 else {
            throw ToolError(message: "rate must be 30 or 60 (got \(rate)).")
        }
        let resolution = try recordingResolution(a)
        let microphone = try boolArg(a, "microphone") ?? false
        let systemAudio = try boolArg(a, "system_audio") ?? true
        let showClicks = try boolArg(a, "show_clicks") ?? false
        let place = try boolArg(a, "place") ?? true
        let folder = try recordingFolder(a)
        if microphone {
            let status = RecordingGrant.microphoneStatus
            guard status == .authorized else {
                throw ToolError(message: RecordingGrant.microphoneRefusal(status))
            }
        }
        // A misspelt `project` is the caller's mistake too — answered above
        // the grant, where `transcribe` answers its own id refusals.
        let destination = try onMain { try self.recordingDestination(a) }

        // 2. The Screen Recording grant — read, never requested.
        guard RecordingGrant.screenRecordingGranted else {
            throw ToolError(message: RecordingGrant.screenRecordingRefusal)
        }

        // 3. The content (unlistable without the grant) and the programmatic
        //    filter — a display source always excludes Reelcut.
        let content = try shareableContent()
        let source = try recordingSource(displayIndex, windowID, in: content)
        let filter: SCContentFilter
        do {
            filter = try ScreenRecorder.filter(for: source, in: content)
        } catch {
            throw ToolError(message: error.localizedDescription)
        }

        // 4. The choice; the microphone is the DEFAULT audio device.
        var microphoneID: String?
        if microphone {
            guard let device = AVCaptureDevice.default(for: .audio) else {
                throw ToolError(message: "No microphone is available.")
            }
            microphoneID = device.uniqueID
        }
        let choice = RecordingChoice(
            source: source, microphone: microphoneID, systemAudio: systemAudio,
            showClicks: showClicks, rate: rate, resolution: resolution,
            destination: destination, folder: folder ?? RecordingFiles.folder())

        // 5. The recording: start, the span, stop — all waits on this thread.
        let result = try record(filter: filter, choice: choice, seconds: seconds)

        // 6. A drag in the target document is waited out HERE, on this
        //    thread — a wait on main would hold the gesture it waits for.
        awaitGestureEnd(destination)

        // 7. The landing, on main, through the door the panel does not use.
        return try onMain { try self.land(result, place: place) }
    }

    // MARK: - The recording

    /// Start, the span, stop. See the header for the hook and the waits.
    private func record(
        filter: SCContentFilter, choice: RecordingChoice, seconds: Double
    ) throws -> RecordingResult {
        let recorder = ScreenRecorder.shared
        let started = DispatchSemaphore(value: 0)
        let startBox = AgentBox<Result<Void, Error>>()
        let finished = DispatchSemaphore(value: 0)
        let box = AgentBox<Result<RecordingResult, Error>>()
        let chrome = RecordingToolChrome()
        // `onFinish` runs on MAIN, once. The status item comes down here,
        // before the landing — the panel's order — and the box is written
        // before the signal, `AgentBox`'s contract.
        let deliver: (Result<RecordingResult, Error>) -> Void = { outcome in
            chrome.remove()
            if box.value == nil { box.value = outcome }
            finished.signal()
        }
        onMain {
            recorder.start(filter: filter, choice: choice, onFinish: deliver) { error in
                startBox.value = error.map { .failure($0) } ?? .success(())
                started.signal()
            }
        }
        // The recorder's own arm timer answers first; this bound is for a
        // start that never answers at all.
        guard started.wait(timeout: .now() + ScreenRecorder.armCeiling + 5) == .success else {
            throw ToolError(
                message: "record_screen timed out waiting for the recording to start."
                    + Self.recordingAlertClause)
        }
        if case .failure(let error) = startBox.value ?? .success(()) {
            throw ToolError(message: Self.startSentence(of: error))
        }
        onMain { chrome.show(recorder) }

        // The span: the recording runs on main's run loop, this thread waits,
        // and only `onFinish` — an external stop, a failure — wakes it early.
        if finished.wait(timeout: .now() + seconds) == .timedOut {
            onMain { recorder.stop() }
            guard finished.wait(timeout: .now() + Self.stopCeiling) == .success else {
                // `session` is the recorder's, internal: the movie it still
                // holds is the one thing the sentence must name.
                let movie = onMain { () -> String? in
                    chrome.remove()
                    return recorder.session?.movieURL.path
                }
                throw ToolError(message: Self.finishTimeoutSentence(movie: movie))
            }
        }
        guard let outcome = box.value else {
            throw ToolError(message: "The recording ended without a result.")
        }
        do {
            return try outcome.get()
        } catch {
            throw ToolError(message: Self.sentence(of: error))
        }
    }

    // MARK: - The landing

    /// SERVER THREAD. A target document mid-drag is not committed over the
    /// gesture's base handle (`RecordingLanding.placement` refuses by name);
    /// the panel retries from a half-second timer bounded at forty tries,
    /// and this is the same wait spelled for a thread that may block: poll
    /// `isLiveEditing` through `onMain` at the panel's own interval and
    /// bound, BY NAME, so the two doors cannot drift apart. A gesture that
    /// outlasts the bound, or a new one begun between the last poll and the
    /// landing, still reaches `placement`'s refusal — now wrapped so it
    /// names the file. Nothing to wait for with a `.newProject` target or a
    /// document that has closed.
    private func awaitGestureEnd(_ destination: RecordingDestination) {
        for _ in 0..<RecorderPanelController.landingRetryLimit {
            let dragging = onMain { () -> Bool in
                guard case .document(let document) = RecordingLanding.resolve(destination)
                else { return false }
                return document.isLiveEditing
            }
            guard dragging else { return }
            Thread.sleep(forTimeInterval: RecorderPanelController.landingRetryInterval)
        }
    }

    /// MAIN. The two doors: a document through `editResult` (one undo step,
    /// the `created` ids, the scope landing); a new project through
    /// `ProjectDocument.untitled(around:)`, which does everything. Every
    /// throw past this point is `savedButNotAdded`'s: the files exist.
    private func land(_ result: RecordingResult, place: Bool) throws -> String {
        var fields = Self.recordingFields(result)
        var notes: [String] = []
        switch RecordingLanding.resolve(result.choice.destination) {
        case .document(let document):
            let placement: RecordingLanding.Placement
            do {
                placement = try RecordingLanding.placement(result, in: document, place: place)
            } catch {
                throw Self.savedButNotAdded(result, error)
            }
            fields["media"] = Int(placement.mediaId)
            if let clip = placement.clipId { fields["clip"] = Int(clip) }
            if let media = placement.micMediaId { fields["mic_media"] = Int(media) }
            if let clip = placement.micClipId { fields["mic_clip"] = Int(clip) }
            fields["landed"] = "document"
            if !place {
                notes.append(
                    "The recording is in the project's media list but not on the timeline — "
                        + "place it with add_clip {track, media, at}.")
            }
            if let mic = Self.microphoneNote(result) { notes.append(mic) }
            if !notes.isEmpty { fields["note"] = notes.joined(separator: " ") }
            let answer: String
            do {
                answer = try editResult(document, RecordingLanding.actionName, placement.ops, fields)
            } catch {
                throw Self.savedButNotAdded(result, error)
            }
            // `editResult` commits and does not build caches; `importMedia`
            // calls this after its own commit for the same reason.
            document.generateCaches()
            return answer
        case .newProject:
            let document: ProjectDocument
            do {
                document = try ProjectDocument.untitled(around: result)
            } catch {
                throw Self.savedButNotAdded(result, error)
            }
            fields.merge(Self.newProjectIds(result, in: document)) { _, new in new }
            fields["landed"] = "new_project"
            if result.choice.destination != .newProject {
                notes.append(
                    "The target document closed while the recording ran, so it opened as a "
                        + "new project instead.")
            }
            if !place {
                notes.append(
                    "place: false has no meaning for a new project — the picture IS the "
                        + "document, so its clip is on the timeline at 0.")
            }
            if let mic = Self.microphoneNote(result) { notes.append(mic) }
            if !notes.isEmpty { fields["note"] = notes.joined(separator: " ") }
            fields["ok"] = true
            fields["project"] = summary(document)
            return try jsonResult(fields)
        }
    }
}

// MARK: - The menu bar, for a recording the tool started

/// The `RecorderStatusItem` and the 1 Hz timer that ticks its label, for a
/// recording `record_screen` started — so a person at the machine can stop
/// an agent's recording from the menu bar as they can the panel's. MAIN
/// THREAD throughout: `show` is hopped there after the start lands, `remove`
/// runs inside `onFinish` (which the recorder calls on main) and on the
/// tool's own finish timeout; `ended` makes the two orderings safe, because
/// a recording that concluded before the hop to `show` must put nothing up
/// that nothing will take down. The timer is added to main's run loop in
/// `.common` modes and invalidated there. The item's Stop is `ScreenRecorder.shared.stop()`
/// with no completion — a join, landed by the tool's own `onFinish`.
private final class RecordingToolChrome {
    private var item: RecorderStatusItem?
    private var timer: Timer?
    private var ended = false

    init() {}

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RecordingToolChrome does not support NSCoder")
    }

    /// MAIN. A no-op once ended, once showing, or for a recorder that is no
    /// longer recording (a pending stop moved it on before the hop).
    func show(_ recorder: ScreenRecorder) {
        guard !ended, item == nil, recorder.state == .recording else { return }
        let item = RecorderStatusItem(onStop: { ScreenRecorder.shared.stop() })
        item.show()
        self.item = item
        // `.common` modes, the panel's rule (`RecorderStatusItem`'s doc): an
        // open status-item menu runs the loop in event-tracking mode, where
        // a default-mode timer does not fire and the label would freeze at
        // the one moment somebody is deciding whether to press Stop.
        let tick = Timer(timeInterval: 1, repeats: true) { [weak recorder, weak item] _ in
            guard let recorder, let item else { return }
            item.update(elapsed: recorder.elapsed)
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    /// MAIN. Idempotent.
    func remove() {
        ended = true
        timer?.invalidate()
        timer = nil
        item?.remove()
        item = nil
    }
}
