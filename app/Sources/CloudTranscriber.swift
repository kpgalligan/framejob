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
    /// On-device `SpeechTranscriber` — `Transcriber`, the default.
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

    enum AccessError: LocalizedError, Equatable {
        case credentialRequired

        var errorDescription: String? {
            "No AssemblyAI API key is set. Set one in Reelcut ▸ Settings ▸ Transcription, "
                + "or RC_ASSEMBLYAI_KEY for a proof."
        }
    }

    /// The serial queue the whole run happens on — `Transcriber.work`'s
    /// twin, and one of the queue seams app/CLAUDE.md lists. A run is
    /// network-bound minutes of somebody else's compute and must never be on
    /// main.
    private let work = DispatchQueue(label: "com.kgalligan.reelcut.cloud-transcribe")

    let client: AssemblyAIClient?
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

    init(client: AssemblyAIClient? = nil, cacheDirectory: URL, media: [UInt32: MediaSnapshot]) {
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
        pages: CaptionPages.Request, cancel: Transcriber.CancelToken,
        progress: ((Double, String) -> Void)? = nil,
        completion: @escaping (Result<Transcriber.Outcome, any Error>) -> Void
    ) {
        work.async { [weak self] in
            guard let self = self else { return }
            let outcome = Result {
                try self.transcribe(
                    jobs, options: options, refresh: refresh, frame: frame, pages: pages,
                    cancel: cancel, progress: progress)
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
        guard let client = self.client else {
            DispatchQueue.main.async {
                completion(.failure(.request(AccessError.credentialRequired.localizedDescription)))
            }
            return
        }
        work.async {
            let answer = client.verify()
            DispatchQueue.main.async { completion(answer) }
        }
    }

    /// The synchronous body, road map 6 §5a. Call it off the main thread; a
    /// tool that already runs on the server thread calls it directly.
    ///
    /// There is no ceiling to report on the other side of a REST call, and
    /// since W2 there is none on this Mac either (spec §11 W-8): the tool's
    /// `truncated` key is gone for both engines, and the proof says so.
    func transcribe(
        _ jobs: [Transcriber.Job], options: TranscriptOptions, refresh: Bool, frame: Ticks,
        pages: CaptionPages.Request, cancel: Transcriber.CancelToken,
        progress: ((Double, String) -> Void)? = nil
    ) throws -> Transcriber.Outcome {
        report = Report()
        var last = 0.0
        func publish(_ value: Double, _ detail: String) {
            last = max(last, value)
            progress?(last, detail)
        }
        publish(0, "")

        // (1) The janitor, FIRST on keyed runs — before anything this run does can
        // overwrite the file that holds an id we still owe a DELETE. A Stop
        // the person has ALREADY pressed is answered above it, and one that
        // arrives during it is heard between its items (the reader review,
        // §10.13 R1·2).
        if cancel.isCancelled { throw Transcriber.TranscribeError.cancelled }
        if client == nil {
            report.janitorDeferred = MediaTranscript.undeleted(in: cacheDirectory).map(\.media)
        } else {
            let janitor = retryDeletes(cancel: cancel)
            report.janitorDeleted = janitor.deleted
            report.janitorFailed = janitor.failed
        }
        if cancel.isCancelled { throw Transcriber.TranscribeError.cancelled }
        if client == nil, jobs.isEmpty || refresh { throw AccessError.credentialRequired }

        // (2) Grouped by media, in the order of each media's FIRST clip, and
        // classified before any work starts so the progress shares are known.
        var order: [UInt32] = []
        var grouped: [UInt32: [Transcriber.Job]] = [:]
        for job in jobs {
            if grouped[job.media] == nil { order.append(job.media) }
            grouped[job.media, default: []].append(job)
        }
        // Admit the entire keyless batch from disk before deriving a cue.
        // Holding these decoded files also closes the gap between admission
        // and use if a package file disappears while the worker is running.
        var keylessFiles: [UInt32: MediaTranscript.File] = [:]
        if client == nil {
            for id in order {
                if cancel.isCancelled { throw Transcriber.TranscribeError.cancelled }
                guard let entry = media[id], let url = grouped[id]?.first?.source,
                    let source = MediaImporter.CacheStamp.stamp(for: entry, url: url),
                    MediaTranscript.readStamp(for: id, in: cacheDirectory)
                        == TranscriptStamp(source: source, options: options),
                    let file = MediaTranscript.read(for: id, in: cacheDirectory)
                else { throw AccessError.credentialRequired }
                keylessFiles[id] = file
            }
            report.cached = order
        }
        var stamps: [UInt32: TranscriptStamp] = [:]
        var unreadable: [UInt32] = []
        var toUpload: [UInt32] = []
        var held: [UInt32] = []
        var cached: [UInt32] = []
        for id in order {
            if client == nil { continue }
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
            if let file = keylessFiles[id] {
                files[id] = file
            } else if unreadable.contains(id) {
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
                        + "not uploaded again; the next run with an API key retries the delete")
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
                cues.append(
                    contentsOf: CaptionPages.cues(
                        from: words, span: job.span, frame: frame, request: pages,
                        engine: .assemblyai, clip: job.clip))
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
        return Transcriber.Outcome(cues: cues, problems: problems, clips: clips)
    }
}
