import AVFoundation
import AppKit
import ScreenCaptureKit

/// Everything that ENDS a recording, and the three delegates that tell the
/// recorder about it — `ScreenRecorder.swift`'s second half, cut at the
/// 400-line cap along the line the state machine already had: arming there,
/// finishing here. Every crossing member of the base class is internal for
/// it, the tree's rule for a class split across files.
///
/// **One finishing path.** `stop()`, the stream delegate's external stops
/// (`.userStopped`, `.systemStoppedStream`), a stream failure and a
/// recording-output failure all enter `beginFinishing`, which tells the
/// microphone output to stop, calls `stopCapture`, and waits — bounded at
/// `finishCeiling` — for every writer's did-finish before `settle` stops
/// the microphone session and probes the files. What differs between the
/// entrances is only `Session.stoppedBy` and `Session.screenFailure`: a
/// screen failure set by the time `settle` runs is what the caller
/// receives, and the files are left where they are for a person to find —
/// NAMED, in the sentence (finding 6).
///
/// **The microphone cannot fail the recording** (finding 0). `settle`
/// probes the MOVIE first whenever the screen side did not fail; a
/// microphone that never started, whose writer reported an error, or whose
/// file will not probe is a `.success` with `micDescriptor` nil and
/// `micProblem` set, its file left on disk and named. A microphone that
/// dies MID-recording (finding 3) sets `microphoneProblem` at once,
/// silences the meter and lets the picture record on; `stop` lands it.
///
/// **`settle` runs once** (finding 2): `Session.settling` is set on entry,
/// `checkFinished` and the ceiling timer bail on it, and a callback that
/// lands during the probe — measured reaching `conclude` twice before —
/// changes nothing. The wait is bounded rather than trusted (R0: stop →
/// did-finish 0.03 s without a microphone, up to 1.1 s with one): past the
/// ceiling the files are probed anyway, since the writer may have closed
/// the file without saying so, and a movie that will not probe is answered
/// `.timedOut`.
///
/// **Every delegate method hops to main first** and then checks that the
/// object calling belongs to the CURRENT session, so a late callback from
/// a session that already failed or settled changes nothing.

extension ScreenRecorder {
    /// `settle` has begun for the current session — the one-shot's
    /// question, asked in one place (finding 2).
    var isSettling: Bool { session?.settling ?? false }

    /// The one finishing path, from `.recording` only. `reason` is what
    /// `RecordingResult.stoppedBy` will say; a failure, if any, is already
    /// on the session. The meter goes silent HERE (finding 8), not at
    /// settle, so a bar does not hold its last level through the wait.
    /// `stopRecording` is ALWAYS sent to a microphone output and its
    /// did-finish always waited for: the SDK delivers one per request even
    /// when nothing was written, and a `micFinished` set by hand is what
    /// let a file the writer was still closing be probed too early.
    func beginFinishing(_ reason: StopReason) {
        guard state == .recording, let current = session else { return }
        timer?.invalidate()
        state = .finishing
        session?.stoppedBy = reason
        session?.stoppedAt = Date()
        meter.publish(.silent, from: ObjectIdentifier(self))
        current.micOutput?.stopRecording()
        current.stream.stopCapture { [weak self] _ in
            // The output's did-finish is what says the file is closed; an
            // error here (a stream the system already stopped) changes
            // nothing about the wait.
            DispatchQueue.main.async { self?.checkFinished() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.finishCeiling, repeats: false) {
            [weak self] _ in
            guard let self, self.state == .finishing, !self.isSettling else { return }
            self.session?.timedOut = true
            self.settle()
        }
    }

    func checkFinished() {
        guard state == .finishing, !isSettling, let current = session, current.screenFinished,
            current.micOutput == nil || current.micFinished
        else { return }
        settle()
    }

    /// Stops the microphone session, probes the movie and then — when the
    /// microphone's writer did not fail — its file, and answers. Once, per
    /// session. The recorder stays `.finishing` until the answer is
    /// delivered, so a second start cannot overwrite the first's hook.
    func settle() {
        guard let done = session, !isSettling else { return }
        session?.settling = true
        timer?.invalidate()
        timer = nil
        done.micSession?.stopRunning()
        meter.publish(.silent, from: ObjectIdentifier(self))
        if let failure = done.screenFailure { return conclude(done, .failure(failure)) }
        MediaImporter.probe(url: done.movieURL) { [weak self] movie in
            guard let self else { return }
            switch movie {
            case .failure(let error):
                self.conclude(done, .failure(Self.unreadable(done, error)))
            case .success(let descriptor):
                self.settleMicrophone(done, movie: descriptor)
            }
        }
    }

    /// The microphone's half of `settle`: no microphone → done; a writer
    /// that reported an error → its sentence; otherwise the file is probed,
    /// and a probe that fails says whether the microphone ever started.
    private func settleMicrophone(_ done: Session, movie: MediaDescriptor) {
        guard let micURL = done.micURL else {
            return conclude(done, .success(Self.result(done, movie: movie, mic: nil, problem: nil)))
        }
        if let failure = done.micFailure {
            let problem = failure + Self.fileClause(micURL, "What it wrote is at")
            return conclude(
                done, .success(Self.result(done, movie: movie, mic: nil, problem: problem)))
        }
        MediaImporter.probe(url: micURL) { [weak self] mic in
            guard let self else { return }
            switch mic {
            case .failure(let error):
                let problem =
                    done.micStartedAt == nil
                    ? "The microphone never started recording, so the picture was recorded "
                        + "without it." + Self.fileClause(micURL, "Its file is at")
                    : "The microphone recording could not be read: " + error.localizedDescription
                        + Self.fileClause(micURL, "The file is at")
                self.conclude(
                    done, .success(Self.result(done, movie: movie, mic: nil, problem: problem)))
            case .success(let micDescriptor):
                self.conclude(
                    done,
                    .success(Self.result(done, movie: movie, mic: micDescriptor, problem: nil)))
            }
        }
    }

    /// Delivers the ONE outcome — to the session's `onFinish` and to every
    /// registered stop completion — with a failure NAMING the files it
    /// left behind (finding 6), then returns to idle. `done` is the session
    /// `settle` captured, never re-read: the one-shot is `settling`, and
    /// this method has no second guard to hide a second entry behind.
    private func conclude(_ done: Session, _ outcome: Result<RecordingResult, Error>) {
        var delivered = outcome
        if case .failure(let error) = outcome, let failure = error as? RecorderError {
            delivered = .failure(Self.namingFiles(failure, done))
        }
        session = nil
        state = .idle
        microphoneProblem = nil
        pendingStop = false
        discardPreparedMicrophone()
        let stops = stopCompletions
        stopCompletions = []
        done.onFinish(delivered)
        stops.forEach { $0(delivered) }
    }

    /// The failure with " The recording is at <movie>; the microphone at
    /// <mic>." appended — each file only when it is actually on disk, so a
    /// sentence never sends a person to a path that holds nothing.
    static func namingFiles(_ error: RecorderError, _ done: Session) -> RecorderError {
        let manager = FileManager.default
        guard manager.fileExists(atPath: done.movieURL.path) else { return error }
        let mic = done.micURL.flatMap { manager.fileExists(atPath: $0.path) ? $0.path : nil }
        return .filesKept(error, movie: done.movieURL.path, microphone: mic)
    }

    /// " <lead> <path>." when the file exists, else nothing.
    private static func fileClause(_ url: URL, _ lead: String) -> String {
        FileManager.default.fileExists(atPath: url.path) ? " \(lead) \(url.path)." : ""
    }

    private static func unreadable(_ done: Session, _ error: any Error) -> RecorderError {
        done.timedOut
            ? .timedOut
            : .finishFailed("The recording could not be read: " + error.localizedDescription)
    }

    /// The offset is the screen's did-start minus the microphone's, each
    /// falling back to the call that asked for it when the callback never
    /// came; `startedAt` is the screen's did-start on the same terms.
    private static func result(
        _ done: Session, movie: MediaDescriptor, mic: MediaDescriptor?, problem: String?
    ) -> RecordingResult {
        let screenStart = done.screenStartedAt ?? done.captureStartedAt ?? done.calledAt
        var offset: Ticks = 0
        if mic != nil, let micStart = done.micStartedAt ?? done.micRecordingCalledAt {
            let seconds = screenStart.timeIntervalSince(micStart)
            offset = Ticks((seconds * Double(ReelTime.perSecond)).rounded())
        }
        return RecordingResult(
            descriptor: movie, micDescriptor: mic, micOffset: offset, choice: done.choice,
            startedAt: screenStart, stoppedBy: done.stoppedBy, micProblem: problem)
    }
}

// MARK: - The stream's delegate

extension ScreenRecorder: SCStreamDelegate {
    /// The system indicator's Stop, a display that slept, or a failure. The
    /// 15.2 `streamDidBecomeActive`/`Inactive` pair is optional and not
    /// implemented, so nothing here needs an `@available`.
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        DispatchQueue.main.async { [weak self] in self?.streamStopped(stream, error: error) }
    }

    private func streamStopped(_ stream: SCStream, error: any Error) {
        guard let current = session, current.stream === stream else { return }
        switch state {
        case .idle:
            return
        case .finishing:
            // An external stop whose did-finish landed FIRST (finding 7):
            // the output's finish began the path as `.stopped`, and the
            // reason arrives now. Adopted only when no `stop()` ended the
            // recording, so a person's own Stop keeps its name.
            if !current.stopAsked, current.stoppedBy == .stopped,
                let reason = Self.externalStop(error)
            {
                session?.stoppedBy = reason
            }
        case .arming:
            // The start's completion reports it (`captureStarted` reads it).
            session?.screenFailure = RecorderError.startFailed(Self.sentence(for: error))
        case .recording:
            if let reason = Self.externalStop(error) {
                beginFinishing(reason)
            } else {
                session?.screenFailure = RecorderError.finishFailed(Self.sentence(for: error))
                beginFinishing(.stopped)
            }
        }
    }
}

// MARK: - The recording output's delegate

extension ScreenRecorder: SCRecordingOutputDelegate {
    /// Stamped where it arrives (R0 q2: 86–107 ms BEFORE `startCapture`'s
    /// completion), so the offset never includes the hop.
    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let at = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self, let current = self.session, current.output === recordingOutput,
                current.screenStartedAt == nil
            else { return }
            self.session?.screenStartedAt = at
        }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let current = self.session, current.output === recordingOutput
            else { return }
            self.session?.screenFinished = true
            if self.session?.screenFailure == nil {
                let sentence = "The recording failed: " + error.localizedDescription
                self.session?.screenFailure =
                    self.state == .arming ? .startFailed(sentence) : .finishFailed(sentence)
            }
            self.outputEnded()
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let current = self.session, current.output === recordingOutput
            else { return }
            self.session?.screenFinished = true
            self.outputEnded()
        }
    }

    /// A finish or a failure nobody asked for (the writer gave up) ends the
    /// recording the way an external stop does; one that was asked for is
    /// the wait's answer. While arming, the start's completion reports it.
    private func outputEnded() {
        if state == .recording { beginFinishing(.stopped) } else { checkFinished() }
    }
}

// MARK: - The microphone file output's delegate

extension ScreenRecorder: AVCaptureFileOutputRecordingDelegate {
    /// Arrives on a private queue (R0 q6b), stamped here before the hop.
    func fileOutput(
        _ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        let at = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self, let current = self.session, current.micOutput === output,
                current.micStartedAt == nil
            else { return }
            self.session?.micStartedAt = at
        }
    }

    /// The writer is done, well or badly. Badly while the picture still
    /// records (finding 3) — the device unplugged, the writer giving up —
    /// is a microphone PROBLEM and never the recording's end: the sentence
    /// is published at once for the panel's tick, the meter goes silent,
    /// and `settle` will carry it on the result. Badly while arming is the
    /// same problem, seen earlier.
    func fileOutput(
        _ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection], error: (any Error)?
    ) {
        // A non-nil error can still mean a usable file: the key says so.
        let finishedWell =
            error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool)
                == true
        DispatchQueue.main.async { [weak self] in
            guard let self, let current = self.session, current.micOutput === output
            else { return }
            self.session?.micFinished = true
            if !finishedWell, self.session?.micFailure == nil, let error {
                let sentence = "The microphone recording failed: " + error.localizedDescription
                self.session?.micFailure = sentence
                self.microphoneProblem = sentence
                self.meter.publish(.silent, from: ObjectIdentifier(self))
            }
            self.checkFinished()
        }
    }
}
