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
/// SAY, cut off this file at the 400-line cap, and
/// `AgentServer+RecordingLanding.swift` the landing, cut at camera-recording CR3-0.
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
/// missing or outside 1…600, then `source` (its value; for `voice_over`
/// the screen-only arguments given, then `microphone: false`), `display`
/// with `window`, a `rate` or `size` outside the vocabulary,
/// `microphone: true` (implied by a voice-over) with the Microphone grant
/// absent (the status WORD in the sentence), and a `project` naming nothing
/// open, answered by `target(_:)`'s own sentence and never turned into a
/// fresh document. A voice-over stops there: it reads no other grant and
/// looks nothing up (spec §11 recording, "A voice-over is a recording with
/// no picture"). A camera recording (spec §11 CAM-4) then looks the camera
/// up — the named one, else the default, refused naming every camera present
/// — then its format (CAM-6), and only then the Camera grant (`+RecordingCamera.swift`). A
/// screen recording then reads the Screen Recording grant,
/// synchronously, named with the System Settings pane. Only then the
/// display or window lookup, which cannot be asked without the grant — a
/// list with NO display in it (a locked console) is named as that, not as
/// an index out of range. `CGRequestScreenCaptureAccess` and the picker are
/// never called, nor is System Settings opened (decision 4): the panel is
/// where a person grants.
///
/// **The target is `.document(recipeKey:)`**, resolved BEFORE the recording
/// and looked up again AFTER it (`RecordingLanding.resolve`): a document that
/// closed meanwhile lands as a new project and the answer says so, as it does
/// for `place: false` in a new project, which still opens the document.
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
/// semaphore again, bounded at `stopCeiling(segments:)` over the count the
/// session holds at the stop. `stop()` is sent with NO completion (`onFinish`
/// lands the result once) and in any state past idle JOINS the finishing
/// under way (the recorder's finding 1), so a person's Stop a second before
/// the span ends is a stop that lands, never `.busy`. A stop that never
/// concludes within that bound is a reported timeout naming EVERY movie the
/// recorder still holds — one per segment — and main is asked nothing more:
/// the recorder has no cancel, and the recording may yet finish on its own.
///
/// **A recording this tool starts is controllable from the machine.** Once
/// the start lands it puts up the same `RecorderStatusItem` the panel does
/// (R1 review, R2d): a person at the Mac watching an agent record can pause,
/// resume and stop it from the menu bar — Pause and Resume are the
/// recorder's `pause()` / `resume()`, Stop is `ScreenRecorder.shared.stop()`,
/// which joins — and the item's elapsed label ticks from a 1 Hz timer on
/// main, its mark flipping at once on the recorder's
/// `pauseDidChangeNotification` (`AgentServer+RecordingChrome.swift`, #181).
/// Both come down in `onFinish`, before the landing.
extension AgentServer {

    /// Seconds the tool waits for `stop()` to conclude, INDEPENDENT of
    /// `seconds` and a function of the SEGMENTS the recorder holds: its own
    /// `finishCeiling` (past which it probes whatever is on disk), plus two
    /// sequential `MediaImporter.probe` ceilings of 30 s PER SEGMENT
    /// (`MediaImporter.probeTimeout`; `settle` probes each segment's movie, then
    /// its microphone file — n segments, 2n probes), plus a margin: 75 s
    /// unpaused, 60 s more per further segment. The old bound was
    /// `seconds + 30`; R2's fixed 75 s was shorter than two segments' probes.
    static func stopCeiling(segments: Int) -> TimeInterval {
        ScreenRecorder.finishCeiling
            + 2 * MediaImporter.probeTimeout * TimeInterval(max(segments, 1)) + 5
    }

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
        let kind = try recordingSourceKind(a)
        let voiceOver = kind == .voiceOver
        let screen = kind == .screen
        let (displayIndex, windowID) = !screen ? (0, nil) : try recordingSourceArguments(a)
        let rate = try intArg(a, "rate") ?? 60
        guard rate == 30 || rate == 60 else {
            throw ToolError(message: "rate must be 30 or 60 (got \(rate)).")
        }
        let resolution = !screen ? .nominal : try recordingResolution(a)
        let microphone = voiceOver ? true : try boolArg(a, "microphone") ?? false
        let systemAudio = !screen ? false : try boolArg(a, "system_audio") ?? true
        let showClicks = !screen ? false : try boolArg(a, "show_clicks") ?? false
        let includeFrameJob =
            !screen ? false : try boolArg(a, "include_framejob_windows") ?? false
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

        // A voice-over has no picture: no grant but the Microphone's is
        // read, and there is nothing to look up.
        var source = RecordingSource.voiceOver
        var filter: SCContentFilter?
        var cameraPick: CameraPick?
        if kind == .camera {
            // CAM-3 (7) and (8): the camera lookup and its format, then the Camera grant —
            // read, never requested.
            cameraPick = try recordingCamera(a)
            source = .camera
        }
        if kind == .screen {
            // 2. The Screen Recording grant — read, never requested.
            guard RecordingGrant.screenRecordingGranted else {
                throw ToolError(message: RecordingGrant.screenRecordingRefusal)
            }

            // 3. The content (unlistable without the grant) and the
            //    programmatic filter — a display source excludes Frame Job
            //    unless `include_framejob_windows`; the tool excludes no
            //    window.
            let content = try shareableContent()
            source = try recordingSource(displayIndex, windowID, in: content)
            do {
                filter = try ScreenRecorder.filter(
                    for: source, in: content,
                    excluding: RecordingExclusion.make(
                        includeFrameJobWindows: includeFrameJob,
                        ownBundleID: Bundle.main.bundleIdentifier, panelWindowID: nil))
            } catch {
                throw ToolError(message: error.localizedDescription)
            }
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
            source: source, includeFrameJobWindows: includeFrameJob,
            microphone: microphoneID, systemAudio: systemAudio,
            showClicks: showClicks, rate: rate, resolution: resolution,
            destination: destination, folder: folder ?? RecordingFiles.folder(),
            camera: cameraPick?.id, cameraFormat: cameraPick?.format)

        // 5. The recording: start, the span, stop — all waits on this thread.
        let result = try record(filter: filter, choice: choice, seconds: seconds)

        // 6. A drag in the target document is waited out HERE, on this
        //    thread — a wait on main would hold the gesture it waits for.
        awaitGestureEnd(destination)

        // 7. The landing, on main, through the door the panel does not use.
        return try onMain { try self.land(result, place: place) }
    }

    // MARK: - The recording

    /// Start, the span, stop. See the header for the hook and the waits. A
    /// filter is a screen recording, started through `start`; with none, a
    /// camera (`choice.source == .camera`) is started through `startCamera`
    /// and a voice-over through `startVoiceOver`, and the span waits first
    /// for their first segment's start (`awaitFirstStart`).
    private func record(
        filter: SCContentFilter?, choice: RecordingChoice, seconds: Double
    ) throws -> RecordingResult {
        let recorder = ScreenRecorder.shared
        let started = DispatchSemaphore(value: 0)
        let startBox = AgentBox<Result<Void, Error>>()
        let finished = DispatchSemaphore(value: 0)
        let box = AgentBox<Result<RecordingResult, Error>>()
        let chrome = RecordingToolChrome()
        // `onFinish` runs on MAIN, once: the status item comes down before
        // the landing, and the box is written before the signal.
        let deliver: (Result<RecordingResult, Error>) -> Void = { outcome in
            chrome.remove()
            if box.value == nil { box.value = outcome }
            finished.signal()
        }
        let startCompletion: (Error?) -> Void = { error in
            startBox.value = error.map { .failure($0) } ?? .success(())
            started.signal()
        }
        onMain {
            if let filter {
                recorder.start(
                    filter: filter, choice: choice, mayAsk: false, onFinish: deliver,
                    completion: startCompletion)
            } else if choice.source == .camera {
                recorder.startCamera(
                    choice: choice, mayAsk: false, onFinish: deliver,
                    completion: startCompletion)
            } else {
                recorder.startVoiceOver(
                    choice: choice, mayAsk: false, onFinish: deliver,
                    completion: startCompletion)
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
        if filter == nil { awaitFirstStart(recorder, ended: box) }

        // The span: the recording runs on main's run loop, this thread waits,
        // and only `onFinish` — an external stop, a failure — wakes it early.
        if finished.wait(timeout: .now() + seconds) == .timedOut {
            // The segment count is read in the SAME hop that stops: a Resume
            // landing between the two would mint a segment — two probes — the
            // wait had not budgeted for. The item freezes first (its doc).
            let segments = onMain { () -> Int in
                chrome.freeze()
                let count = max(recorder.heldSegmentCount, 1)
                recorder.stop()
                return count
            }
            guard finished.wait(timeout: .now() + Self.stopCeiling(segments: segments)) == .success
            else {
                // The files the recorder still holds — one per segment.
                let movies = onMain { () -> [String] in
                    chrome.remove()
                    return recorder.heldFilePaths
                }
                throw ToolError(
                    message: Self.finishTimeoutSentence(
                        movies: movies, voiceOver: choice.source == .voiceOver))
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

    /// SERVER THREAD. A voice-over's start completion answers BEFORE its
    /// writer's did-start, so a span counted from it comes out short by the
    /// input's start-up time (a second on a Bluetooth input); a camera's
    /// answers when segment 0's writer is armed, before its first buffer
    /// (CAM-4 point 5: the span is the picture recorded, the warm-up not in
    /// it). This polls `heldFirstStartedAt` through `onMain` until it lands,
    /// the recording has already ended (`ended` written by `onFinish`), or
    /// `ScreenRecorder.armCeiling` passes — past which the span runs as
    /// before. A screen recording's start already answers after its arm.
    private func awaitFirstStart(
        _ recorder: ScreenRecorder, ended: AgentBox<Result<RecordingResult, Error>>
    ) {
        let deadline = Date().addingTimeInterval(ScreenRecorder.armCeiling)
        while Date() < deadline {
            let waiting = onMain { recorder.heldFirstStartedAt == nil && ended.value == nil }
            guard waiting else { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }
}
