import AVFoundation
import AppKit
import Speech

/// On-device speech recognition into caption cues — the engine behind
/// File ▸ Generate Captions… (`TranscribeSheetController`) and the agent's
/// `transcribe`. What comes out is `[CaptionLayout.Cue]`, which is what an
/// imported `.srt` also becomes, so a transcript is laid out by exactly the
/// code that lays out a file and burn-in stays free.
///
/// **No `async`.** `SFSpeechRecognizer`'s callback and delegate API is
/// complete for a transcription — a delegate method per hypothesis, one for
/// the final result, one for progress — so this file keeps Rasterize's
/// synchronous discipline and `async`/`await` stays confined to
/// `MediaImporter.swift` (spec §11, app/CLAUDE.md, and road map 2 phase 0
/// decided it in as many words). `SpeechAnalyzer`, the macOS 26 replacement,
/// is `async`-only and would earn the argument again — but only when the
/// deployment target moves, and then as one more named file.
///
/// **The queue.** Recognition is the one seam this feature adds to the list
/// in app/CLAUDE.md, and it is really two. `work` is a serial queue the whole
/// run happens on — extraction is disk-bound and a recognition is minutes of
/// somebody else's compute — and `delivery` is the `OperationQueue` the
/// recognizer is told to call back on. That second one is not optional:
/// `SFSpeechRecognizer.queue` defaults to the app's MAIN queue, which would
/// make an off-main tool's semaphore wait depend on the main runloop staying
/// free. The single completion is posted to main at the end, which is
/// `MediaImporter.probe`'s seam and lets every caller stay synchronous.
///
/// **It transcribes EXTRACTED audio, never the media file.** The road map
/// assumed `SFSpeechURLRecognitionRequest` can read a project's `.mov`;
/// nothing in the framework's documentation promises it (its error vocabulary
/// has `SFSpeechErrorCodeAudioReadFailed`, "the audio file could not be
/// read"), and the question cannot be settled without a TCC grant that an
/// agent-driven app — never the frontmost app — cannot obtain. A design that
/// works for `say -o`'s fixtures and fails on every real clip is the worst
/// failure shape available, so each job's SOURCE WINDOW is written to a
/// temporary mono WAV first and the recogniser is handed that.
///
/// The choice pays twice. It bounds the work to what the timeline actually
/// uses — a 20 s clip of a 30-minute recording is 20 seconds of recognition,
/// not thirty minutes — and it makes the time mapping trivial: a word at `t`
/// seconds into the extract lands at `clip.start + ticks(t) / speed`, with no
/// `in` term left in the arithmetic at all.
///
/// **The one-minute ceiling is REPORTED, not worked around.**
/// `SFSpeechRecognizer.h` says the framework stops tasks that last longer than
/// a minute. The paragraph is written about the network service and nothing
/// exempts on-device file recognition, so when the last word lands more than
/// `Transcriber.truncationSlack` before the end of the extract the outcome
/// carries a `Truncation` saying where it stopped, the sheet says so in words
/// and the tool reports it. A caption run that quietly stops at sixty seconds
/// and says nothing is the failure this rule exists to prevent. Chunking at
/// the silences phase 3 can already find is the recorded follow-up, not this
/// phase's work.
///
/// **One job's failure is one job's problem, never the run's.** A run is a
/// LIST of clips and each is read on its own, so a clip whose extract comes
/// back empty — a file whose audio track is shorter than its picture, which
/// screen and phone recordings routinely are, trimmed into the tail where
/// only pictures are left — is reported under `Outcome.problems` and the run
/// carries on. Throwing there would discard every cue the earlier clips
/// produced and name only the clip that failed, which is minutes of somebody
/// else's compute thrown away over one bad tail. The one exception is
/// cancellation: that is the user's instruction, it means "place nothing",
/// and it stays a real throw.
final class Transcriber {

    // MARK: - What a run is asked to do

    /// One clip's worth of work. Everything the mapping needs is here by
    /// value, so a run holds no document and nothing can change under it.
    struct Job: Equatable {
        let clip: UInt32
        /// What the timeline calls this clip, for the progress line.
        let name: String
        /// The file behind the clip's media.
        let source: URL
        /// The clip's `in` point — where the extract begins in source time.
        let sourceIn: Ticks
        /// How much SOURCE time the clip plays: `duration × speed`, the
        /// core's own `content_length_in_source` (`source_window.rs`).
        let sourceLength: Ticks
        /// Project time of the clip's first frame.
        let start: Ticks
        let duration: Ticks
        let speed: Double
    }

    /// A job whose last recognised word landed well before the end of its
    /// audio — the framework's documented one-minute ceiling, most likely.
    /// Times are PROJECT ticks, so a caller can print a timecode.
    struct Truncation: Equatable {
        let clip: UInt32
        let stoppedAt: Ticks
        let end: Ticks
    }

    /// What a whole run produced.
    struct Outcome {
        /// Every cue, from every job, in the order the jobs ran.
        /// `CaptionLayout.place` sorts them.
        let cues: [CaptionLayout.Cue]
        /// Clips that were skipped, and cues nothing could be made of, each
        /// with a reason — `import_captions`' `skipped` idiom.
        let problems: [CaptionLayout.Problem]
        /// Jobs the recogniser appears to have cut short.
        let truncations: [Truncation]
        /// The clips a cue actually came out of.
        let clips: [UInt32]
    }

    /// Why a run produced nothing.
    enum TranscribeError: LocalizedError, Equatable {
        case notAuthorized(String)
        case unknownLanguage(String)
        case noOnDeviceModel(String)
        case unavailable(String)
        case unreadable(String)
        case failed(String)
        case timedOut(String)
        case cancelled
        case nothingRecognized

        var errorDescription: String? {
            switch self {
            case .notAuthorized(let status):
                // Named verbatim because a script has no other way to read it:
                // the TCC database is unreadable without Full Disk Access and
                // `tccutil` has no grant verb, so this sentence IS the phase's
                // only observable of the grant state.
                return "speech recognition is not authorized for Reelcut (status: \(status)) — "
                    + "run File ▸ Generate Captions… once from the app to grant it"
            case .unknownLanguage(let name):
                return "“\(name)” is not a language speech recognition knows — "
                    + "check the tag's spelling."
            case .noOnDeviceModel(let name):
                return "\(name) has no on-device speech model on this Mac. Download it in "
                    + "System Settings ▸ Keyboard ▸ Dictation, or choose another language."
            case .unavailable(let name):
                return "The \(name) recogniser is not available right now."
            case .unreadable(let name):
                return "“\(name)” has no audio that could be read."
            case .failed(let reason):
                return "The transcription failed: \(reason)"
            case .timedOut(let name):
                return "Transcribing “\(name)” took too long and was stopped."
            case .cancelled:
                return "The transcription was cancelled."
            case .nothingRecognized:
                return "No speech was recognised in the audio that was transcribed."
            }
        }
    }

    /// `MediaConsolidator.CancelToken`'s shape — one flag, one lock, safe from
    /// any thread and safe to set twice — with the recognition task under the
    /// same lock, because speech cancellation is PUSH: there is no loop of
    /// ours to poll inside a recognition, only `SFSpeechRecognitionTask.cancel()`.
    final class CancelToken {
        private let lock = NSLock()
        private var flag = false
        private var task: SFSpeechRecognitionTask?

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return flag
        }

        func cancel() {
            lock.lock()
            flag = true
            let running = task
            lock.unlock()
            // Outside the lock: `cancel()` calls back into the delegate on
            // the recogniser's own queue, and holding a lock across it would
            // be a lock held across somebody else's code.
            running?.cancel()
        }

        /// Stops the task that is running WITHOUT marking the run cancelled —
        /// what a wedged recognition earns. The flag is the run's, and a job
        /// that timed out must not set it: every later job would then refuse
        /// as cancelled and the whole outcome, earlier clips included, would
        /// be thrown away over one clip the recogniser never finished.
        func stopTask() {
            lock.lock()
            let running = task
            lock.unlock()
            running?.cancel()
        }

        /// Hands the token the task it may stop. A cancel that arrived while
        /// the task was being created still lands.
        func attach(_ task: SFSpeechRecognitionTask?) {
            lock.lock()
            self.task = task
            let already = flag
            lock.unlock()
            if already { task?.cancel() }
        }

        func release() {
            lock.lock()
            task = nil
            lock.unlock()
        }
    }

    // MARK: - Authorization

    static var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    static var isAuthorized: Bool { authorizationStatus == .authorized }

    /// The status as the framework spells it, for a message a script can read.
    static func name(of status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    /// The refusal every path that cannot ask must use.
    static var authorizationRefusal: TranscribeError {
        .notAuthorized(name(of: authorizationStatus))
    }

    /// Whether a system prompt can actually be answered — `FFmpegRewrap.canAsk`'s
    /// question about the identical launch flag, and the same one-line body.
    /// An agent-driven app (`-AgentServerEnabled YES`) has nobody at the
    /// keyboard: `requestAuthorization`'s prompt would sit unseen while the
    /// handler's semaphore ran down to its ceiling, turning a clean "not
    /// authorized" into a wedged tool call. So the TOOL reads the status and
    /// refuses; only the SHEET, which a person opened, ever asks.
    static var canAsk: Bool {
        !UserDefaults.standard.bool(forKey: AgentServer.enabledDefaultsKey)
    }

    /// Asks once. The framework does not guarantee which queue it answers on,
    /// so the answer is posted to main — everything that reads it is a sheet.
    ///
    /// Never call this from a tool handler: see `canAsk`. And never at type
    /// init or in a `loadView` that the offscreen harness reaches — the
    /// harness builds a bare Mach-O with no `Info.plist`, and
    /// `SFSpeechRecognizer.h` says an app without
    /// `NSSpeechRecognitionUsageDescription` CRASHES here.
    static func requestAuthorization(
        _ completion: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void
    ) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { completion(status) }
        }
    }

    // MARK: - Running

    /// Seconds of audio that may follow the last recognised word before the
    /// run is called truncated. Two seconds is longer than any trailing pause
    /// a sentence ends with and far shorter than the minute the framework's
    /// ceiling would leave behind.
    static let truncationSlack: Double = 2

    private let work = DispatchQueue(
        label: "com.kgalligan.reelcut.transcribe", qos: .userInitiated)
    private let delivery: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    /// The task does NOT retain its delegate (`SFSpeechRecognizer.h`), so
    /// this does: a `[weak]` or a local would be deallocated the instant the
    /// call returned and progress would stop with no error and a bar that
    /// never moves.
    private var sink: TaskSink?
    private var recognizer: SFSpeechRecognizer?

    init() {}

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Transcriber does not support NSCoder")
    }

    /// Transcribes every job, in order, and answers on the MAIN thread —
    /// `MediaImporter.probe`'s seam, which is what lets a sheet and a
    /// semaphore-waiting tool both stay synchronous. `progress` is NOT hopped:
    /// it fires on the run's own queue and its caller bounces it, exactly as
    /// `ConsolidateProgressSheetController` bounces `MediaConsolidator.run`'s.
    func run(
        jobs: [Job], language: Language, frame: Ticks, cancel: CancelToken,
        progress: ((Double, String) -> Void)? = nil,
        completion: @escaping (Result<Outcome, any Error>) -> Void
    ) {
        work.async { [weak self] in
            guard let self = self else { return }
            let outcome = Result {
                try self.transcribe(
                    jobs, language: language, frame: frame, cancel: cancel, progress: progress)
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    /// The synchronous body. Call it off the main thread; a tool that already
    /// runs on the server thread may call it directly rather than through
    /// `run`.
    func transcribe(
        _ jobs: [Job], language: Language, frame: Ticks, cancel: CancelToken,
        progress: ((Double, String) -> Void)? = nil
    ) throws -> Outcome {
        guard Self.isAuthorized else { throw Self.authorizationRefusal }
        guard let recognizer = SFSpeechRecognizer(locale: language.locale) else {
            throw TranscribeError.unknownLanguage(language.displayName)
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscribeError.noOnDeviceModel(language.displayName)
        }
        guard recognizer.isAvailable else {
            throw TranscribeError.unavailable(language.displayName)
        }
        recognizer.queue = delivery
        self.recognizer = recognizer
        defer { self.recognizer = nil }

        let total = jobs.reduce(0.0) { $0 + ReelTime.seconds($1.sourceLength) }
        var done = 0.0
        var cues: [CaptionLayout.Cue] = []
        var problems: [CaptionLayout.Problem] = []
        var truncations: [Truncation] = []
        var clips: [UInt32] = []
        // The jobs that could not be READ, kept apart from `problems` because
        // they decide which refusal an empty run gets: a run that heard no
        // speech and a run whose audio could not be opened are two different
        // answers, and only one of them is about the speaking.
        var failures: [String] = []

        for job in jobs {
            if cancel.isCancelled { throw TranscribeError.cancelled }
            let base = done
            let length = ReelTime.seconds(job.sourceLength)
            progress?(total > 0 ? base / total : 0, job.name)

            // One clip's failure is reported and stepped over — see the type's
            // doc. Cancellation is the exception and rethrows: it means the
            // person asked for nothing to be placed, not that this clip was
            // unreadable.
            do {
                let extract = try extractAudio(job, cancel: cancel)
                defer { try? FileManager.default.removeItem(at: extract.url) }
                let segments = try recognize(
                    extract.url, with: recognizer, seconds: extract.seconds, name: job.name,
                    cancel: cancel,
                    progress: { seconds in
                        guard total > 0 else { return }
                        progress?(min(1, (base + min(seconds, length)) / total), job.name)
                    })

                let words = segments.map { segment -> CaptionCues.Word in
                    CaptionCues.Word(
                        text: segment.substring,
                        start: Self.project(segment.timestamp, in: job),
                        end: Self.project(segment.timestamp + max(0, segment.duration), in: job))
                }.filter { $0.start < job.start + job.duration }
                cues.append(
                    contentsOf: CaptionCues.build(from: words, frame: frame, clip: job.clip))
                if !words.isEmpty { clips.append(job.clip) }

                if let last = segments.last {
                    let stopped = last.timestamp + max(0, last.duration)
                    if extract.seconds - stopped > Self.truncationSlack {
                        truncations.append(
                            Truncation(
                                clip: job.clip, stoppedAt: Self.project(stopped, in: job),
                                end: Self.project(extract.seconds, in: job)))
                    }
                } else {
                    problems.append(
                        CaptionLayout.Problem(
                            tag: "clip \(job.clip)", reason: "no speech was recognised in it"))
                }
            } catch TranscribeError.cancelled {
                throw TranscribeError.cancelled
            } catch {
                let reason = error.localizedDescription
                problems.append(CaptionLayout.Problem(tag: "clip \(job.clip)", reason: reason))
                failures.append("clip \(job.clip): \(reason)")
            }
            done += length
        }

        if cancel.isCancelled { throw TranscribeError.cancelled }
        guard !cues.isEmpty else {
            // Nothing came out, and WHICH nothing matters: "no speech was
            // recognised" is a claim about the audio, and making it when the
            // audio was never read would send somebody looking for words that
            // are on the timeline.
            guard failures.isEmpty else {
                throw TranscribeError.failed(failures.prefix(3).joined(separator: "; "))
            }
            throw TranscribeError.nothingRecognized
        }
        progress?(1, "")
        return Outcome(cues: cues, problems: problems, truncations: truncations, clips: clips)
    }

    /// A second `t` into the extract, as project time.
    ///
    /// The whole of the mapping, and it is this short only because the
    /// extract begins at the clip's `in` point: `clip.start + ticks(t) / speed`,
    /// with no source-window term left. Clamped into the clip, since a
    /// recogniser may hand back a word whose duration runs past the audio it
    /// was given.
    static func project(_ t: Double, in job: Job) -> Ticks {
        let speed = job.speed.isFinite && job.speed > 0 ? job.speed : 1
        let offset = ReelTime.ticks(seconds: max(0, t) / speed)
        return min(job.start + max(0, offset), job.start + job.duration)
    }

    // MARK: - Recognition

    /// One extract through the recogniser, waited for.
    ///
    /// The DELEGATE route rather than the result handler, because
    /// `speechRecognitionTask(_:didProcessAudioDuration:)` is the only
    /// "how far along" signal the framework has and it exists nowhere else —
    /// and both existing progress sheets in this app are determinate, so a
    /// third kind of progress would be a third thing to explain. Partial
    /// results are off: exactly one final result has to be handled, which is
    /// what spec §11 means by the callback API being complete.
    private func recognize(
        _ url: URL, with recognizer: SFSpeechRecognizer, seconds: Double, name: String,
        cancel: CancelToken, progress: @escaping (Double) -> Void
    ) throws -> [SFTranscriptionSegment] {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation

        let sink = TaskSink()
        sink.onDuration = progress
        self.sink = sink
        defer {
            self.sink = nil
            cancel.release()
        }
        cancel.attach(recognizer.recognitionTask(with: request, delegate: sink))

        // Four times real time, floored at two minutes: a recognition that has
        // gone that far past its audio is wedged, and a tool blocked on this
        // is holding a connection open.
        //
        // `stopTask`, never `cancel`: this ends the wedged TASK, and the run
        // goes on to the next job with this one reported. Setting the run's
        // own flag here would make every later job refuse as cancelled and
        // throw away the cues the earlier ones already produced.
        guard sink.wait(seconds: max(120, seconds * 4)) else {
            cancel.stopTask()
            throw TranscribeError.timedOut(name)
        }
        if cancel.isCancelled { throw TranscribeError.cancelled }
        if let error = sink.failure {
            throw TranscribeError.failed(error.localizedDescription)
        }
        return sink.segments
    }
}

// MARK: - The task's delegate

/// The one object `SFSpeechRecognitionTask` will talk to. It is a separate
/// class because the task does NOT retain its delegate
/// (`SFSpeechRecognizer.h`, `recognitionTaskWithRequest:delegate:`) and
/// `Transcriber` therefore has to — a delegate that is only referenced from
/// the call site is deallocated the instant the call returns, and progress
/// then stops with no error at all.
///
/// Every method here arrives on the recogniser's own queue, so the state is
/// behind a lock and the terminal signal is a semaphore the run's thread
/// waits on.
private final class TaskSink: NSObject, SFSpeechRecognitionTaskDelegate {
    private let lock = NSLock()
    private let done = DispatchSemaphore(value: 0)
    private var signalled = false
    private var result: SFSpeechRecognitionResult?
    private var error: (any Error)?

    /// Seconds of audio processed so far. Set before the task starts, so it
    /// can never be attached to a task that has already begun reporting.
    var onDuration: ((Double) -> Void)?

    var segments: [SFTranscriptionSegment] {
        lock.lock()
        defer { lock.unlock() }
        return result?.bestTranscription.segments ?? []
    }

    var failure: (any Error)? {
        lock.lock()
        defer { lock.unlock() }
        return error
    }

    func wait(seconds: Double) -> Bool {
        done.wait(timeout: .now() + seconds) == .success
    }

    /// Finishes once, whichever of the three ways the task ends.
    private func finish(_ failure: (any Error)?) {
        lock.lock()
        if signalled {
            lock.unlock()
            return
        }
        signalled = true
        if error == nil { error = failure }
        lock.unlock()
        done.signal()
    }

    func speechRecognitionTask(
        _ task: SFSpeechRecognitionTask,
        didFinishRecognition recognitionResult: SFSpeechRecognitionResult
    ) {
        lock.lock()
        result = recognitionResult
        lock.unlock()
    }

    func speechRecognitionTask(
        _ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool
    ) {
        finish(successfully ? nil : task.error)
    }

    func speechRecognitionTaskWasCancelled(_ task: SFSpeechRecognitionTask) {
        finish(task.error)
    }

    func speechRecognitionTask(
        _ task: SFSpeechRecognitionTask, didProcessAudioDuration duration: TimeInterval
    ) {
        onDuration?(duration)
    }
}
