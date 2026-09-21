import Foundation

/// The cloud engine's seam and its run: `TranscriptionEngine`, the two
/// spellings a caption run can be asked for, and `CloudTranscriber`, which
/// takes exactly what `Transcriber` takes and answers exactly what
/// `Transcriber` answers — road map 6 §5a, whole.
///
/// **What a run is.** The janitor first (R6-4), then the jobs grouped by
/// MEDIA rather than by clip, because R6-3 says one upload per media file and
/// every clip over it is derived from that one transcript. A media whose
/// cache is current is read from disk and costs no request at all; a media
/// whose remote delete this run could not confirm is HELD (R6-11); every
/// other media is extracted whole, uploaded, submitted, polled, written to
/// the cache and deleted remotely, in that order. Then each job's words are
/// cut out of its media's transcript by the mapping and built into cues.
///
/// **One media's failure is one media's problem.** `Transcriber`'s rule, read
/// across: a media that could not be transcribed is reported under
/// `problems` for every clip on it and the run carries on, because a run is a
/// LIST and throwing away the media that worked over the one that did not is
/// minutes of somebody else's compute discarded. There are exactly two
/// exceptions and both are named in §5a: a CANCELLATION, which is the
/// person's instruction to place nothing, and a REFUSED KEY, which would fail
/// every later media the same way and cost an upload each time it did.
///
/// **`run` is `Transcriber.run`'s twin line for line.** R6-7: no `async`
/// here or below it, one serial queue, the body synchronous on it, the single
/// completion posted to main.
enum TranscriptionEngine: String, CaseIterable {
    /// On-device `SFSpeechRecognizer` — `Transcriber`, the default.
    case apple
    /// AssemblyAI over the network — `CloudTranscriber`.
    case assemblyai

    /// What the sheet remembers between opens (road map 6 §5a). An agent call
    /// never reads it: R6-2 says the cloud engine is asked for every time.
    static let defaultsKey = "ReelcutCaptionEngine"

    /// The popup's words. "On this Mac" rather than "Apple" because what the
    /// person is choosing is where their audio goes, not whose recogniser it
    /// is.
    var displayName: String {
        switch self {
        case .apple: return "On this Mac"
        case .assemblyai: return "AssemblyAI"
        }
    }
}

/// AssemblyAI as a second engine behind the one command (R6-1). Same jobs,
/// same cancel token, same frame, same `Outcome`, so
/// `TranscribeSheetController.finish` and the tool's placement code cannot
/// tell which engine ran.
final class CloudTranscriber {

    /// Everything a caller may want to SAY about a run that the `Outcome`
    /// has no room for — which media were uploaded and what AssemblyAI said
    /// about each, which were served from the cache, and what the janitor
    /// managed.
    ///
    /// It is beside the outcome rather than inside it because `Outcome` is
    /// the shape BOTH engines answer and the on-device one has nothing to
    /// put in any of these fields. The tool reads it for its result keys and
    /// c1-chrome's report card reads it for its lines.
    struct Report: Equatable {

        /// One media this run sent to AssemblyAI, and what came back.
        struct Uploaded: Equatable {
            let media: UInt32
            /// R6-8: which model actually ran, so a fallback is reported.
            let speechModelUsed: String?
            let languageCode: String?
            /// Set when the language was DETECTED, not when it was named.
            let languageConfidence: Double?
            /// Seconds as AssemblyAI reported them — what was billed.
            let audioSeconds: Int
            let format: Transcriber.UploadFormat
            /// Whether this fetched transcript's initial JSON write landed.
            let transcriptWritten: Bool
            /// Whether the remote transcript is confirmed gone (R6-4).
            let remoteDeleted: Bool
        }

        var uploaded: [Uploaded] = []
        /// Media served from `cache/transcripts/` with no request at all.
        var cached: [UInt32] = []
        /// Media whose earlier transcript the janitor deleted this run.
        var janitorDeleted: [UInt32] = []
        /// Media whose earlier transcript the janitor could NOT delete.
        var janitorFailed: [UInt32] = []
        /// R6-11: in `janitorFailed` AND this run would otherwise have
        /// fetched them. A held media is in neither `uploaded` nor `cached`
        /// and its clips are reported as problems: its cache file is the one
        /// record of an id we still have to delete, and a fetch would
        /// overwrite it.
        var held: [UInt32] = []

        /// Cleanup still owed, in stable per-media order. An ID can be
        /// retried only when its transcript JSON was saved in the project.
        func deletionWarnings(name: (UInt32) -> String) -> [String] {
            var seen: Set<UInt32> = []
            var warnings: [String] = []
            func append(_ id: UInt32, written: Bool) {
                guard seen.insert(id).inserted else { return }
                let target = name(id)
                var warning: String
                if written {
                    warning = "AssemblyAI has not confirmed deleting the transcript of \(target); "
                        + "it will be retried at the next run."
                } else {
                    warning = "AssemblyAI has not confirmed deleting the transcript of \(target). "
                        + "Its transcript could not be saved in the project, so Reelcut cannot "
                        + "retry deleting it automatically. Delete it in your AssemblyAI dashboard."
                }
                if held.contains(id) { warning += " It was not uploaded again in this run." }
                warnings.append(warning)
            }
            for id in janitorFailed { append(id, written: true) }
            for row in uploaded where !row.remoteDeleted {
                append(row.media, written: row.transcriptWritten)
            }
            return warnings
        }
    }

    /// The serial queue the whole run happens on — `Transcriber.work`'s
    /// twin, and one of the queue seams app/CLAUDE.md lists. A run is
    /// network-bound minutes of somebody else's compute and must never be on
    /// main.
    private let work = DispatchQueue(label: "com.kgalligan.reelcut.cloud-transcribe")

    let client: AssemblyAIClient
    /// Where `cache/transcripts/` lives for this run — the document's cache
    /// directory, passed by value so the run holds no document.
    let cacheDirectory: URL
    /// The media records the jobs point at, by id, for the stamp.
    let media: [UInt32: MediaSnapshot]

    /// What the last run said. Written only inside `transcribe`, read only
    /// after it returns (or after `run`'s completion has fired), which is why
    /// it needs no lock: one run at a time on one serial queue, and the
    /// caller that reads it is the caller that waited for it.
    private(set) var report = Report()

    init(client: AssemblyAIClient, cacheDirectory: URL, media: [UInt32: MediaSnapshot]) {
        self.client = client
        self.cacheDirectory = cacheDirectory
        self.media = media
    }

    /// Transcribes every job and answers on the MAIN thread —
    /// `Transcriber.run`'s seam, so a sheet and a semaphore-waiting tool can
    /// both stay synchronous. `progress` is NOT hopped: it fires on the run's
    /// own queue and its caller bounces it.
    func run(
        jobs: [Transcriber.Job], options: TranscriptOptions, refresh: Bool, frame: Ticks,
        cancel: Transcriber.CancelToken, progress: ((Double, String) -> Void)? = nil,
        completion: @escaping (Result<Transcriber.Outcome, any Error>) -> Void
    ) {
        work.async { [weak self] in
            guard let self = self else { return }
            let outcome = Result {
                try self.transcribe(
                    jobs, options: options, refresh: refresh, frame: frame, cancel: cancel,
                    progress: progress)
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    /// `GET /v2/transcript?limit=1` on the run's OWN queue, answered on
    /// main — the Settings window's Verify button.
    ///
    /// Spec §11's R6-12: verify adds no queue. `work` is already one of the
    /// seams `app/CLAUDE.md` lists, and a second one for a single cheap
    /// authenticated GET would be a queue nobody could name a rule for.
    ///
    /// It captures the CLIENT and not `self`. A verify is a wait on a socket
    /// and the window that asked may be gone before it answers; there is
    /// nothing on this object for it to write, and a strong `self` would
    /// keep a whole transcriber alive for the duration of a button press.
    func verify(completion: @escaping (Result<Void, AssemblyAIClient.ClientError>) -> Void) {
        let client = self.client
        work.async {
            let answer = client.verify()
            DispatchQueue.main.async { completion(answer) }
        }
    }

    /// The synchronous body, road map 6 §5a. Call it off the main thread; a
    /// tool that already runs on the server thread calls it directly.
    ///
    /// `truncations` is ALWAYS empty and that is a claim, not an oversight:
    /// there is no one-minute ceiling on the other side of a REST call, so
    /// the tool's `truncated` key can never appear for this engine and the
    /// proof says so.
    func transcribe(
        _ jobs: [Transcriber.Job], options: TranscriptOptions, refresh: Bool, frame: Ticks,
        cancel: Transcriber.CancelToken, progress: ((Double, String) -> Void)? = nil
    ) throws -> Transcriber.Outcome {
        report = Report()
        var last = 0.0
        func publish(_ value: Double, _ detail: String) {
            last = max(last, value)
            progress?(last, detail)
        }
        publish(0, "")

        // (1) The janitor, FIRST — before anything this run does can
        // overwrite the file that holds an id we still owe a DELETE. A Stop
        // the person has ALREADY pressed is answered above it, and one that
        // arrives during it is heard between its items (the reader review,
        // §10.13 R1·2).
        if cancel.isCancelled { throw Transcriber.TranscribeError.cancelled }
        let janitor = retryDeletes(cancel: cancel)
        report.janitorDeleted = janitor.deleted
        report.janitorFailed = janitor.failed
        if cancel.isCancelled { throw Transcriber.TranscribeError.cancelled }

        // (2) Grouped by media, in the order of each media's FIRST clip, and
        // classified before any work starts so the progress shares are known.
        var order: [UInt32] = []
        var grouped: [UInt32: [Transcriber.Job]] = [:]
        for job in jobs {
            if grouped[job.media] == nil { order.append(job.media) }
            grouped[job.media, default: []].append(job)
        }
        var stamps: [UInt32: TranscriptStamp] = [:]
        var unreadable: [UInt32] = []
        var toUpload: [UInt32] = []
        var held: [UInt32] = []
        var cached: [UInt32] = []
        for id in order {
            guard let entry = media[id], let url = grouped[id]?.first?.source,
                let source = MediaImporter.CacheStamp.stamp(for: entry, url: url)
            else {
                unreadable.append(id)
                continue
            }
            let stamp = TranscriptStamp(source: source, options: options)
            stamps[id] = stamp
            if MediaTranscript.isCurrent(stamp, for: id, in: cacheDirectory), !refresh {
                cached.append(id)
            } else if report.janitorFailed.contains(id) {
                held.append(id)
            } else {
                toUpload.append(id)
            }
        }
        report.held = held
        // Held and cached media are NOT in the shares: neither costs a
        // second of work, and a slice for one would make the bar stall.
        let bar = CloudProgress(seconds: toUpload.map { ReelTime.seconds(media[$0]?.duration ?? 0) })

        var files: [UInt32: MediaTranscript.File] = [:]
        var cues: [CaptionLayout.Cue] = []
        var problems: [CaptionLayout.Problem] = []
        var clips: [UInt32] = []
        // Kept apart from `problems` for `Transcriber.transcribe`'s reason:
        // they decide WHICH refusal an empty run earns.
        var failures: [String] = []

        func refuse(_ id: UInt32, _ reason: String) {
            for job in grouped[id] ?? [] {
                problems.append(CaptionLayout.Problem(tag: "clip \(job.clip)", reason: reason))
                failures.append("clip \(job.clip): \(reason)")
            }
        }

        for id in order {
            if cancel.isCancelled { throw Transcriber.TranscribeError.cancelled }
            if unreadable.contains(id) {
                refuse(id, "its media file could not be read")
            } else if cached.contains(id) {
                if let file = MediaTranscript.read(for: id, in: cacheDirectory) {
                    files[id] = file
                    report.cached.append(id)
                } else {
                    refuse(id, "its cached transcript could not be read")
                }
            } else if held.contains(id) {
                // R6-11, the whole of it: no fetch, no write, one sentence
                // per clip, and the file left byte for byte.
                refuse(
                    id,
                    "AssemblyAI has not confirmed deleting its earlier transcript, so it was "
                        + "not uploaded again; the next run retries the delete")
            } else if let index = toUpload.firstIndex(of: id), let entry = media[id],
                let url = grouped[id]?.first?.source, let stamp = stamps[id]
            {
                do {
                    let answer = try fetch(
                        media: entry, url: url, stamp: stamp, options: options, cancel: cancel,
                        progress: { phase, within, detail in
                            publish(bar.fraction(media: index, phase: phase, within: within), detail)
                        })
                    files[id] = answer.file
                    report.uploaded.append(answer.uploaded)
                    publish(
                        bar.fraction(media: index, phase: .saving, within: 1),
                        CloudProgress.detail(.saving, file: entry.name))
                } catch {
                    if let client = error as? AssemblyAIClient.ClientError,
                        case .submissionUnresolved(let authenticationStatus) = client,
                        cancel.isCancelled || authenticationStatus != nil
                    {
                        throw client
                    }
                    if cancel.isCancelled { throw Transcriber.TranscribeError.cancelled }
                    if let client = error as? AssemblyAIClient.ClientError {
                        if client == .cancelled { throw Transcriber.TranscribeError.cancelled }
                        // An auth failure ends the run at once: every later
                        // media would fail the same way and each costs an
                        // upload to find out.
                        if case .keyRefused = client { throw error }
                    }
                    if let native = error as? Transcriber.TranscribeError, native == .cancelled {
                        throw Transcriber.TranscribeError.cancelled
                    }
                    refuse(id, error.localizedDescription)
                }
            }

            // (4) Every job on this media, derived from the one transcript.
            guard let file = files[id] else { continue }
            for job in grouped[id] ?? [] {
                let words = MediaTranscript.words(for: job, in: file)
                    .filter { $0.start < job.start + job.duration }
                cues.append(contentsOf: CaptionCues.build(from: words, frame: frame, clip: job.clip))
                if words.isEmpty {
                    problems.append(
                        CaptionLayout.Problem(
                            tag: "clip \(job.clip)", reason: "no speech was recognised in it"))
                } else {
                    clips.append(job.clip)
                }
            }
        }

        if cancel.isCancelled { throw Transcriber.TranscribeError.cancelled }
        guard !cues.isEmpty else {
            // `Transcriber.transcribe`'s two closing throws, same rule: "no
            // speech was recognised" is a claim about the AUDIO, and making
            // it when the audio was never read would send somebody looking
            // for words that are on the timeline.
            guard failures.isEmpty else {
                throw Transcriber.TranscribeError.failed(
                    failures.prefix(3).joined(separator: "; "))
            }
            throw Transcriber.TranscribeError.nothingRecognized
        }
        publish(1, "")
        return Transcriber.Outcome(
            cues: cues, problems: problems, truncations: [], clips: clips)
    }
}
