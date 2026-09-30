import AVFoundation
import AppKit
import ScreenCaptureKit

/// Everything that ENDS a recording — `ScreenRecorder.swift`'s second half,
/// cut at the 400-line cap along the line the state machine already had:
/// arming there, finishing here. The three delegates that tell the recorder
/// about it were the foot of this file until R2's segments took it over the
/// cap, and are `ScreenRecorder+Delegates.swift` now. Every crossing member
/// of the base class is internal for it, the tree's rule for a class split
/// across files.
///
/// **One finishing path.** `stop()`, the stream delegate's external stops
/// (`.userStopped`, `.systemStopped`), a stream failure and a
/// recording-output failure all enter `beginFinishing` — from `.recording`
/// OR `.paused` — which stamps and stops what is still open (nothing, when
/// paused: the pause closed the segment's output and stopped the
/// microphone's writer), calls `stopCapture` either way, asks the wait's
/// question once itself, and waits — bounded at `finishCeiling` — for
/// EVERY segment's did-finish before `settle` stops the microphone session
/// and probes the files. What differs
/// between the entrances is only `Session.stoppedBy` and
/// `Session.screenFailure`: a screen failure set by the time `settle` runs
/// is what the caller receives, and the files are left where they are for
/// a person to find — NAMED, every one that exists, in the sentence
/// (finding 6).
///
/// **The microphone cannot fail the recording** (finding 0), per segment.
/// `settle` probes segment by segment, in order, the MOVIE first whenever
/// the screen side did not fail; a microphone that never started, whose
/// writer reported an error, or whose file will not probe is that SEGMENT's
/// `micProblem` on a `.success`, its file left on disk and named, the
/// picture landing without it. A microphone that dies MID-recording
/// (finding 3) sets `microphoneProblem` at once, silences the meter and
/// lets the picture record on; `stop` lands it. A movie that will not probe
/// is LEFT OUT (#97): the walker goes on to the next segment and the result
/// names it in `unreadable`, its files kept on disk and named; only a
/// recording with NO readable movie fails — the first segment's error, every
/// file named, so one segment's failure reads as it always did.
///
/// **`settle` runs once** (finding 2): `Session.settling` is set on entry,
/// `checkFinished` and the ceiling timer bail on it, and a callback that
/// lands during the probe — measured reaching `conclude` twice before —
/// changes nothing. The wait is bounded rather than trusted (R0: stop →
/// did-finish 0.03 s without a microphone, up to 1.1 s with one): past the
/// ceiling the files are probed anyway, since the writer may have closed
/// the file without saying so, and a movie that will not probe is answered
/// `.timedOut` when ITS writer never said it finished — a closed segment's
/// is a read failure whichever segment the ceiling fired for.

extension ScreenRecorder {
    /// `settle` has begun for the current session — the one-shot's
    /// question, asked in one place (finding 2).
    var isSettling: Bool { session?.settling ?? false }

    /// The one finishing path, from `.recording` or `.paused`. `reason` is
    /// what `RecordingResult.stoppedBy` will say; a failure, if any, is
    /// already on the session. The meter goes silent HERE (finding 8), not
    /// at settle, so a bar does not hold its last level through the wait.
    /// While RECORDING the last segment is still open: its `stoppedAt` is
    /// stamped and `stopRecording` is sent to the microphone output —
    /// ALWAYS, and its did-finish waited for: the SDK answers a request
    /// with one even when nothing was written (a writer that already failed
    /// and said so gets no second one, harmlessly: its did-finish with the
    /// error set `micFinished`, and the wait reads the flag), and a
    /// `micFinished` set by hand is what let a file the writer was still
    /// closing be probed too early. While PAUSED both were done at the
    /// pause, only `stopCapture` remains, and NO did-finish is coming to
    /// ask the wait's question — every flag may have been true for minutes
    /// — so `checkFinished` is asked once here, synchronously, LAST (the R2
    /// review): the alternative was to trust `stopCapture`'s completion on
    /// a stream the system may already have stopped, which is unmeasured.
    /// Safe from `.recording` too: there `allFinished` is false unless the
    /// last output finished before the path began, and that file is closed.
    func beginFinishing(_ reason: StopReason) {
        guard state == .recording || state == .paused, let current = session else { return }
        timer?.invalidate()
        let wasRecording = state == .recording
        state = .finishing
        session?.stoppedBy = reason
        meter.publish(.silent, from: ObjectIdentifier(self))
        if wasRecording {
            session?.segments[current.lastIndex].stoppedAt = Date()
            current.micOutput?.stopRecording()
        }
        current.stream.stopCapture { [weak self] _ in
            // The outputs' did-finishes are what say the files are closed;
            // an error here (a stream the system already stopped) changes
            // nothing about the wait.
            DispatchQueue.main.async { self?.checkFinished() }
        }
        // In `.common`, the panel's rule: a status-item menu held open runs
        // the loop in tracking mode, where a default-mode timer waits for
        // the menu to close — and `record_screen`'s `stopCeiling`, two
        // seconds past this one, does not.
        let ceiling = Timer(timeInterval: Self.finishCeiling, repeats: false) { [weak self] _ in
            guard let self, self.state == .finishing, !self.isSettling else { return }
            self.session?.timedOut = true
            self.settle()
        }
        RunLoop.main.add(ceiling, forMode: .common)
        timer = ceiling
        // Last, so a synchronous settle finds the timer to invalidate.
        checkFinished()
    }

    func checkFinished() {
        guard state == .finishing, !isSettling, let current = session, current.allFinished
        else { return }
        settle()
    }

    /// Stops the microphone session and probes segment by segment — each
    /// movie, then its microphone file — and answers ONE result. Once, per
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
        probeSegment(done, at: 0, landed: [], skipped: [])
    }

    /// The walker: probes segment `index`'s movie — a failure LEAVES THE
    /// SEGMENT OUT, `leftOut`, with no microphone probe — then its
    /// microphone, appends the `RecordingSegment` and moves to the next;
    /// past the last, concludes: a failure with the first left-out
    /// segment's error when nothing landed, else a success carrying the
    /// left-out ones. Sequential and recursive rather than concurrent,
    /// because each probe's completion is on main and the order of `landed`
    /// IS the order the landing places the clips in.
    private func probeSegment(
        _ done: Session, at index: Int, landed: [RecordingSegment],
        skipped: [UnreadableSegment]
    ) {
        guard index < done.segments.count else {
            guard !landed.isEmpty else { return conclude(done, .failure(skipped[0].error)) }
            // The reason is read LIVE: an external stop whose did-finish
            // landed first writes it during the probe (`+Delegates.swift`'s
            // `.finishing` arm), after `settle` copied `done`.
            let result = RecordingResult(
                segments: landed, choice: done.choice,
                stoppedBy: session?.stoppedBy ?? done.stoppedBy, pauses: done.pauses,
                unreadable: skipped)
            return conclude(done, .success(result))
        }
        MediaImporter.probe(url: done.segments[index].movieURL) { [weak self] movie in
            guard let self else { return }
            switch movie {
            case .failure(let error):
                let left = Self.leftOut(done, at: index, error)
                self.probeSegment(done, at: index + 1, landed: landed, skipped: skipped + [left])
            case .success(let descriptor):
                self.probeMicrophone(done, at: index, movie: descriptor) { [weak self] segment in
                    self?.probeSegment(
                        done, at: index + 1, landed: landed + [segment], skipped: skipped)
                }
            }
        }
    }

    /// Segment `index`, left out: its movie as named, the files it left on
    /// disk (movie, then microphone, each only if there) and `unreadable`'s
    /// error for it.
    private static func leftOut(_ done: Session, at index: Int, _ error: any Error)
        -> UnreadableSegment
    {
        let segment = done.segments[index]
        let kept = [segment.movieURL.path, segment.micURL?.path].compactMap { $0 }
            .filter { FileManager.default.fileExists(atPath: $0) }
        return UnreadableSegment(
            moviePath: segment.movieURL.path, keptFiles: kept,
            error: unreadable(done, at: index, error))
    }

    /// The microphone's half of one segment: no microphone → done; a writer
    /// that reported an error → its sentence; otherwise the file is probed,
    /// and a probe that fails says whether the microphone ever started.
    /// `then` receives the landed segment, on main.
    private func probeMicrophone(
        _ done: Session, at index: Int, movie: MediaDescriptor,
        then: @escaping (RecordingSegment) -> Void
    ) {
        let segment = done.segments[index]
        guard let micURL = segment.micURL else {
            return then(Self.result(done, at: index, movie: movie, mic: nil, problem: nil))
        }
        if let failure = segment.micFailure {
            let problem = failure + Self.fileClause(micURL, "What it wrote is at")
            return then(Self.result(done, at: index, movie: movie, mic: nil, problem: problem))
        }
        MediaImporter.probe(url: micURL) { mic in
            switch mic {
            case .failure(let error):
                let problem =
                    segment.micStartedAt == nil
                    ? "The microphone never started recording, so the picture was recorded "
                        + "without it." + Self.fileClause(micURL, "Its file is at")
                    : "The microphone recording could not be read: " + error.localizedDescription
                        + Self.fileClause(micURL, "The file is at")
                then(Self.result(done, at: index, movie: movie, mic: nil, problem: problem))
            case .success(let micDescriptor):
                then(Self.result(done, at: index, movie: movie, mic: micDescriptor, problem: nil))
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
    /// sentence never sends a person to a path that holds nothing. With
    /// segments, every movie that exists comma-joined in order, and every
    /// microphone file likewise, so one segment's sentence is byte for byte
    /// R1's; no movie on disk at all leaves the error as it was.
    static func namingFiles(_ error: RecorderError, _ done: Session) -> RecorderError {
        let manager = FileManager.default
        let movies = done.segments.map(\.movieURL.path).filter { manager.fileExists(atPath: $0) }
        guard !movies.isEmpty else { return error }
        let mics = done.segments.compactMap { $0.micURL?.path }
            .filter { manager.fileExists(atPath: $0) }
        return .filesKept(
            error, movie: movies.joined(separator: ", "),
            microphone: mics.isEmpty ? nil : mics.joined(separator: ", "))
    }

    /// " <lead> <path>." when the file exists, else nothing.
    private static func fileClause(_ url: URL, _ lead: String) -> String {
        FileManager.default.fileExists(atPath: url.path) ? " \(lead) \(url.path)." : ""
    }

    /// `.timedOut` only when the FAILING segment's writer never said it
    /// finished — the ceiling's own case; a closed segment's movie that will
    /// not probe is a read failure whichever segment the ceiling fired for.
    private static func unreadable(_ done: Session, at index: Int, _ error: any Error)
        -> RecorderError
    {
        done.timedOut && !done.segments[index].screenFinished
            ? .timedOut
            : .finishFailed("The recording could not be read: " + error.localizedDescription)
    }

    /// One segment, landed. The offset is the screen's did-start minus the
    /// microphone's, each falling back to the call that asked for it when
    /// the callback never came; `startedAt` is the screen's did-start on
    /// the same terms (`Session.screenStart(of:)`, then the call that added
    /// the output — which, for the first segment, is `start`'s own call,
    /// R1's third fallback).
    private static func result(
        _ done: Session, at index: Int, movie: MediaDescriptor, mic: MediaDescriptor?,
        problem: String?
    ) -> RecordingSegment {
        let segment = done.segments[index]
        let screenStart = done.screenStart(of: index) ?? segment.addedAt
        var offset: Ticks = 0
        if mic != nil, let micStart = segment.micStartedAt ?? segment.micRecordingCalledAt {
            let seconds = screenStart.timeIntervalSince(micStart)
            offset = Ticks((seconds * Double(ReelTime.perSecond)).rounded())
        }
        return RecordingSegment(
            descriptor: movie, micDescriptor: mic, micOffset: offset, startedAt: screenStart,
            micProblem: problem)
    }
}
