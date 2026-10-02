import AVFoundation
import AppKit

/// Everything that ENDS a voice-over (spec §11 recording, "A voice-over is a
/// recording with no picture", #99) — `+Finishing.swift`'s shape for a
/// machine with no stream, cut from `+VoiceOver.swift` the way that file was
/// cut from the base: the writer's two reports, the one finishing path, the
/// settle, the probe walker and the conclude.
///
/// **What the writer reports.** A did-start is stamped on its segment (and
/// ignored once the segment was stopped, so a span never runs backwards). A
/// did-finish marks its segment finished and, when the file did not finish
/// well (`AVErrorRecordingSuccessfullyFinishedKey` honoured), records the
/// writer's sentence as its `failure`. A did-finish nobody asked for — the
/// segment's `stoppedAt` still nil — is the microphone stopping on its own:
/// it sets `stoppedOnItsOwn` BEFORE anything stamps `stoppedAt`, finished
/// well or not, and, while recording, ends the voice-over, because nothing
/// else is recording. What it wrote lands, with that segment's `micProblem`.
///
/// **One finishing path**, from `.recording` or `.paused`: the open writer
/// stamped and stopped, `.finishing`, the meter silent,
/// `finishingDidBeginNotification` posted, the wait bounded at
/// `finishCeiling` (in `.common`), and the wait's question asked once here.
/// **The settle runs once**: the session stopped, then each segment probed in
/// order; a file that reads is a `RecordingSegment` whose `descriptor` is the
/// `.m4a` itself, one that will not is an `UnreadableSegment`; no readable
/// file is a failure naming the files on disk. `stoppedBy` is always
/// `.stopped`: there is no system indicator to stop a voice-over.
extension ScreenRecorder {
    // MARK: - The writer's reports

    func voiceFileStarted(_ url: URL, output: AVCaptureFileOutput, at: Date) {
        guard let current = voiceSession, current.micOutput === output,
            let index = current.index(of: url), current.segments[index].startedAt == nil,
            current.segments[index].stoppedAt == nil
        else { return }
        voiceSession?.segments[index].startedAt = at
    }

    func voiceFileFinished(
        _ url: URL, output: AVCaptureFileOutput, finishedWell: Bool, error: (any Error)?
    ) {
        guard let current = voiceSession, current.micOutput === output,
            let index = current.index(of: url)
        else { return }
        voiceSession?.segments[index].finished = true
        if !finishedWell, current.segments[index].failure == nil {
            voiceSession?.segments[index].failure =
                "The microphone recording failed: "
                + (error?.localizedDescription ?? "it reported no error.")
        }
        if current.segments[index].stoppedAt == nil {
            // Unasked: the marker goes on FIRST, before the finishing path
            // stamps `stoppedAt` and erases the only sign of it.
            voiceSession?.segments[index].stoppedOnItsOwn =
                error?.localizedDescription ?? "It reported no error."
            if state == .recording { beginVoiceFinishing() }
        }
        checkVoiceFinished()
    }

    // MARK: - The finishing path

    /// From `.recording` or `.paused`; anything else changes nothing. While
    /// recording the open segment is stamped and its writer asked to stop;
    /// while paused both were done at the pause.
    func beginVoiceFinishing() {
        guard state == .recording || state == .paused, let current = voiceSession else { return }
        timer?.invalidate()
        let wasRecording = state == .recording
        state = .finishing
        meter.publish(.silent, from: ObjectIdentifier(self))
        if wasRecording {
            let last = current.segments.count - 1
            if current.segments[last].stoppedAt == nil {
                voiceSession?.segments[last].stoppedAt = Date()
            }
            current.micOutput.stopRecording()
        }
        NotificationCenter.default.post(name: Self.finishingDidBeginNotification, object: self)
        let ceiling = Timer(timeInterval: Self.finishCeiling, repeats: false) { [weak self] _ in
            guard let self, self.state == .finishing, self.voiceSession?.settling == false
            else { return }
            self.voiceSession?.timedOut = true
            self.settleVoice()
        }
        RunLoop.main.add(ceiling, forMode: .common)
        timer = ceiling
        // Last, so a synchronous settle finds the timer to invalidate.
        checkVoiceFinished()
    }

    /// Every segment's did-finish has landed: settle.
    func checkVoiceFinished() {
        guard state == .finishing, let current = voiceSession, !current.settling,
            current.segments.allSatisfy({ $0.finished })
        else { return }
        settleVoice()
    }

    /// Once per session: the capture session stopped, then the walk.
    private func settleVoice() {
        guard let done = voiceSession, !done.settling else { return }
        voiceSession?.settling = true
        timer?.invalidate()
        timer = nil
        done.micSession.stopRunning()
        meter.publish(.silent, from: ObjectIdentifier(self))
        probeVoiceSegment(done, at: 0, landed: [], skipped: [])
    }

    /// Probes segment `index`'s file and moves to the next, in order — each
    /// probe's completion is on main, and the order of `landed` IS the order
    /// the landing places the clips in.
    private func probeVoiceSegment(
        _ done: VoiceSession, at index: Int, landed: [RecordingSegment],
        skipped: [UnreadableSegment]
    ) {
        guard index < done.segments.count else { return concludeVoice(done, landed, skipped) }
        let segment = done.segments[index]
        MediaImporter.probe(url: segment.url) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .failure(let error):
                let path = segment.url.path
                let reason: RecorderError =
                    done.timedOut && !segment.finished
                    ? .timedOut
                    : .finishFailed("The voice-over could not be read: " + error.localizedDescription)
                let left = UnreadableSegment(
                    moviePath: path,
                    keptFiles: FileManager.default.fileExists(atPath: path) ? [path] : [],
                    error: reason, position: landed.count)
                self.probeVoiceSegment(done, at: index + 1, landed: landed, skipped: skipped + [left])
            case .success(let descriptor):
                let problem = segment.stoppedOnItsOwn.map {
                    "The microphone stopped recording on its own: \($0) "
                        + "The voice-over ends where it stopped."
                }
                let landedSegment = RecordingSegment(
                    descriptor: descriptor, micDescriptor: nil, micOffset: 0,
                    startedAt: segment.startedAt ?? segment.calledAt, micProblem: problem)
                self.probeVoiceSegment(
                    done, at: index + 1, landed: landed + [landedSegment], skipped: skipped)
            }
        }
    }

    /// The ONE outcome, to `onFinish` and every registered stop completion,
    /// after the recorder is idle again. No readable file is a failure: the
    /// first left-out segment's error, naming every file still on disk.
    private func concludeVoice(
        _ done: VoiceSession, _ landed: [RecordingSegment], _ skipped: [UnreadableSegment]
    ) {
        let outcome: Result<RecordingResult, Error>
        if landed.isEmpty {
            let files = done.segments.map(\.url.path)
                .filter { FileManager.default.fileExists(atPath: $0) }
            let first = skipped.first?.error ?? .finishFailed("The voice-over wrote no file.")
            outcome = .failure(
                RecorderError.filesKept(
                    first, movie: "",
                    microphone: files.isEmpty ? nil : files.joined(separator: ", ")))
        } else {
            outcome = .success(
                RecordingResult(
                    segments: landed, choice: done.choice, stoppedBy: .stopped,
                    pauses: done.pauses, unreadable: skipped))
        }
        voiceSession = nil
        state = .idle
        timer?.invalidate()
        timer = nil
        microphoneProblem = nil
        discardPreparedMicrophone()
        let stops = stopCompletions
        stopCompletions = []
        done.onFinish(outcome)
        stops.forEach { $0(outcome) }
    }
}
