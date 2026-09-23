import AVFoundation
import AppKit

/// On-device speech recognition into caption cues — the engine behind
/// File ▸ Generate Captions… (`TranscribeSheetController`) and the agent's
/// `transcribe`. What comes out is `[CaptionLayout.Cue]`, which is what an
/// imported `.srt` also becomes, so a transcript is laid out by exactly the
/// code that lays out a file and burn-in stays free.
///
/// **No `async` here.** The engine is `SpeechAnalyzer`/`SpeechTranscriber`
/// (spec §11 W-8), which is `async`-only, and all of it lives in
/// `SpeechEngine.swift` — the one named file the amended `MediaImporter`
/// decision allows. This file calls its synchronous wrappers and keeps
/// Rasterize's synchronous discipline.
///
/// **The queue.** `work` is the serial queue the whole run happens on
/// (R6-7), because `SpeechEngine.transcribe` blocks the thread it is called
/// on. The single completion is posted to main at the end, the seam
/// `MediaImporter.probe` uses, so every caller stays synchronous.
///
/// **It transcribes EXTRACTED audio, never the media file.** Each job's
/// SOURCE WINDOW is written to a temporary 16 kHz mono WAV first and the
/// engine is handed that (spec §11). It bounds the work to what the timeline
/// actually uses — a 20 s clip of a 30-minute recording is 20 seconds of
/// recognition, not thirty minutes — and it makes the time mapping trivial: a
/// word at `t` seconds into the extract lands at `clip.start + ticks(t) /
/// speed`, with no `in` term left in the arithmetic at all.
///
/// **No ceiling and no grant** (spec §11 W-8): W0 q1 read 99.81 % of a
/// 613.7 s file with no Speech Recognition grant asked. What a run CAN be
/// refused for is a model that is not installed — `transcribe` asks
/// `SpeechEngine.isInstalled` for the chosen locale first, and a person
/// installs it from the sheet's Download row.
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
        /// The media record behind the clip. The on-device engine never
        /// needed it — it extracts each clip's own source window — but the
        /// cloud engine uploads a MEDIA once and derives every clip on it
        /// from one transcript (R6-3), so the grouping key and the cache
        /// file's name are this (road map 6 §5a, §5b).
        let media: UInt32
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

    /// What a whole run produced.
    struct Outcome {
        /// Every cue, from every job, in the order the jobs ran.
        /// `CaptionLayout.place` sorts them.
        let cues: [CaptionLayout.Cue]
        /// Clips that were skipped, and cues nothing could be made of, each
        /// with a reason — `import_captions`' `skipped` idiom.
        let problems: [CaptionLayout.Problem]
        /// The clips a cue actually came out of.
        let clips: [UInt32]
    }

    /// Why a run produced nothing.
    enum TranscribeError: LocalizedError, Equatable {
        case unknownLanguage(String)
        case notInstalled(String)
        case unavailable(String)
        case unreadable(String)
        case failed(String)
        case timedOut(String)
        case cancelled
        case nothingRecognized

        var errorDescription: String? {
            switch self {
            case .unknownLanguage(let name):
                return "“\(name)” is not a language speech recognition knows — "
                    + "check the tag's spelling."
            case .notInstalled(let name):
                // "A person has to install it": a download is a person's act,
                // never a tool's (spec §11 W-8), and the sheet is where it is.
                return "\(name) is not installed on this Mac. A person has to install it: open "
                    + "File ▸ Generate Captions…, choose it under Language, and press Download."
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
    /// any thread and safe to set twice — with the running analysis under the
    /// same lock, because speech cancellation is PUSH: there is no loop of
    /// ours to poll inside a recognition, only `SpeechEngine.Handle.cancel()`.
    ///
    /// **It holds a `URLSessionTask` beside it** (road map 6 §5a), under the
    /// same lock and cancelled outside it, for the same reason: a cloud run
    /// waiting on an upload has no loop of its own either, and one token has
    /// to stop whichever engine is running. The two slots are independent —
    /// only one engine runs at a time, and a token that had to know which
    /// would be a token every caller had to tell.
    final class CancelToken {
        private let lock = NSLock()
        private var flag = false
        private var task: SpeechEngine.Handle?
        private var request: URLSessionTask?

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return flag
        }

        func cancel() {
            lock.lock()
            flag = true
            let running = task
            let sending = request
            lock.unlock()
            // Outside the lock: `cancel()` reaches into the engine's task —
            // and, for a `URLSessionTask`, the session's delegate — and
            // holding a lock across it would be a lock held across somebody
            // else's code.
            running?.cancel()
            sending?.cancel()
        }

        /// Stops the task that is running WITHOUT marking the run cancelled —
        /// what a wedged recognition earns. The flag is the run's, and a job
        /// that timed out must not set it: every later job would then refuse
        /// as cancelled and the whole outcome, earlier clips included, would
        /// be thrown away over one clip the recogniser never finished.
        func stopTask() {
            lock.lock()
            let running = task
            let sending = request
            lock.unlock()
            running?.cancel()
            sending?.cancel()
        }

        /// Hands the token the analysis it may stop. A cancel that arrived
        /// while the analysis was being created still lands.
        func attach(_ task: SpeechEngine.Handle?) {
            lock.lock()
            self.task = task
            let already = flag
            lock.unlock()
            if already { task?.cancel() }
        }

        /// The cloud run's half of the same contract, and an overload rather
        /// than a second name so a caller that holds a token cancels it the
        /// one way whatever is running underneath.
        func attach(_ task: URLSessionTask?) {
            lock.lock()
            self.request = task
            let already = flag
            lock.unlock()
            if already { task?.cancel() }
        }

        func release() {
            lock.lock()
            task = nil
            request = nil
            lock.unlock()
        }
    }

    // MARK: - Running

    private let work = DispatchQueue(
        label: "com.kgalligan.reelcut.transcribe", qos: .userInitiated)

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
        jobs: [Job], language: Language, frame: Ticks, pages: CaptionPages.Request,
        cancel: CancelToken, progress: ((Double, String) -> Void)? = nil,
        completion: @escaping (Result<Outcome, any Error>) -> Void
    ) {
        work.async { [weak self] in
            guard let self = self else { return }
            let outcome = Result {
                try self.transcribe(
                    jobs, language: language, frame: frame, pages: pages, cancel: cancel,
                    progress: progress)
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    /// The synchronous body. Call it off the main thread; a tool that already
    /// runs on the server thread may call it directly rather than through
    /// `run`. `pages` is the caption style and canvas each job's words are
    /// paged for (`CaptionPages.cues`).
    func transcribe(
        _ jobs: [Job], language: Language, frame: Ticks, pages: CaptionPages.Request,
        cancel: CancelToken, progress: ((Double, String) -> Void)? = nil
    ) throws -> Outcome {
        guard SpeechEngine.isAvailable else {
            throw TranscribeError.unavailable(language.displayName)
        }
        // The model question for the ONE chosen locale. A question that took
        // too long is not a missing model, and its sentence must not send
        // anybody to Download for one that may be installed.
        switch SpeechEngine.isInstalled(language.locale) {
        case .none:
            throw TranscribeError.unavailable(language.displayName)
        case .some(false):
            throw TranscribeError.notInstalled(language.displayName)
        case .some(true):
            break
        }

        let total = jobs.reduce(0.0) { $0 + ReelTime.seconds($1.sourceLength) }
        var done = 0.0
        var cues: [CaptionLayout.Cue] = []
        var problems: [CaptionLayout.Problem] = []
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
                let runs = try SpeechEngine.transcribe(
                    file: extract.url, locale: language.locale, seconds: extract.seconds,
                    name: job.name, cancel: cancel,
                    progress: { seconds in
                        guard total > 0 else { return }
                        progress?(min(1, (base + min(seconds, length)) / total), job.name)
                    })

                let words = runs.map { run -> CaptionCues.Word in
                    CaptionCues.Word(
                        text: run.text,
                        start: Self.project(run.start, in: job),
                        end: Self.project(run.end, in: job))
                }.filter { $0.start < job.start + job.duration }
                cues.append(
                    contentsOf: CaptionPages.cues(
                        from: words, span: job.span, frame: frame, request: pages,
                        engine: .apple, clip: job.clip))
                if !words.isEmpty { clips.append(job.clip) }

                if runs.isEmpty {
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
        return Outcome(cues: cues, problems: problems, clips: clips)
    }

    /// A second `t` into the extract, as project time.
    ///
    /// The whole of the mapping, and it is this short only because the
    /// extract begins at the clip's `in` point: `clip.start + ticks(t) / speed`,
    /// with no source-window term left. Clamped into the clip through
    /// `placed` — the one door both caption mappings convert through, and
    /// the place R6-10's bound on a hand-written `speed` is applied.
    static func project(_ t: Double, in job: Job) -> Ticks {
        let speed = job.speed.isFinite && job.speed > 0 ? job.speed : 1
        return placed(offset: max(0, t) / speed * Double(ReelTime.perSecond), in: job)
    }
}
