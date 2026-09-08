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
        /// core's own `content_length` (`model_query.rs`).
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

    // MARK: - Languages

    /// One row of the sheet's language popup, and the vocabulary the tool's
    /// `language` argument speaks.
    struct Language: Equatable {
        /// A BCP-47 identifier, `en-US`.
        let identifier: String
        let displayName: String

        var locale: Locale { Locale(identifier: identifier) }
    }

    private static let languageLock = NSLock()
    private static var cachedLanguages: [Language]?
    private static var cachedSupported: [Language]?

    /// Every dictation locale this Mac can recognise WITHOUT a network,
    /// sorted by display name.
    ///
    /// The filter is not cosmetic: an `SFSpeechRecognitionRequest` can only
    /// honour `requiresOnDeviceRecognition` where the recogniser answers
    /// `supportsOnDeviceRecognition`, so an unfiltered popup would offer rows
    /// whose every run fails. Measured on this machine: **4 of 63** supported
    /// locales have on-device assets, and the whole pass — one recogniser per
    /// locale — takes **0.33 s**, which is why it is cached and why it is not
    /// asked for again on every control change.
    ///
    /// The result is cached only when it is NON-empty, because the property
    /// is known to answer false on the first read after a recogniser is
    /// constructed and true a moment later — caching an empty first answer
    /// would make the feature refuse for the rest of the session on a machine
    /// where it works.
    static func languages() -> [Language] {
        languageLock.lock()
        if let cached = cachedLanguages {
            languageLock.unlock()
            return cached
        }
        languageLock.unlock()

        let found = named(
            SFSpeechRecognizer.supportedLocales().filter { locale in
                SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition ?? false
            })

        if !found.isEmpty {
            languageLock.lock()
            cachedLanguages = found
            languageLock.unlock()
        }
        return found
    }

    /// Every locale the FRAMEWORK names, model downloaded or not — the
    /// unfiltered twin of `languages()`.
    ///
    /// There are two lists because a caller who named a language this Mac
    /// could not use has one of TWO problems and they have two different
    /// fixes. `en-XX` is a tag speech recognition has never heard of, and the
    /// fix is to spell it right; `fr-FR` is a tag it knows perfectly well
    /// that this Mac has no model for, and the fix is a download in System
    /// Settings. Told only "this Mac cannot recognise it", somebody with the
    /// second problem retypes a tag that was right all along, which is what
    /// `transcribe`'s catalog entry promises does not happen.
    ///
    /// It costs no recogniser — `supportedLocales()` is a list the framework
    /// answers out of its own bundle — so this is sixty-odd display-name
    /// lookups where `languages()` is sixty-odd recogniser constructions.
    /// And it is INDEPENDENT OF THE GRANT, which is the property the tool
    /// leans on: measured at status `notDetermined`, 63 locales here, the
    /// same 4 of them on device. That is why a misspelled tag can be refused
    /// ABOVE the authorization check, among the caller's other mistakes,
    /// while the download question stays BELOW it, where a machine nobody has
    /// granted yet cannot be mistaken for one with no models installed.
    ///
    /// Cached like its twin, and an empty answer is not cached, for its
    /// twin's reason turned around: the list is static, so the cache is only
    /// about not rebuilding the display names, and an empty framework list is
    /// not an answer this file is willing to remember.
    static func supportedLanguages() -> [Language] {
        languageLock.lock()
        if let cached = cachedSupported {
            languageLock.unlock()
            return cached
        }
        languageLock.unlock()

        let found = named(SFSpeechRecognizer.supportedLocales())
        if !found.isEmpty {
            languageLock.lock()
            cachedSupported = found
            languageLock.unlock()
        }
        return found
    }

    /// Locales as rows: named in this Mac's own language and sorted by that
    /// NAME rather than by tag, because a person reads the name — and both
    /// lists are built here so the popup and the two refusals cannot spell
    /// one locale two ways.
    private static func named(_ locales: Set<Locale>) -> [Language] {
        let names = Locale.current
        return locales.map { locale -> Language in
            let identifier = locale.identifier
            return Language(
                identifier: identifier,
                displayName: names.localizedString(forIdentifier: identifier) ?? identifier)
        }.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    /// The language a run defaults to: this Mac's own, when it survives the
    /// on-device filter, then anything sharing its language code, then the
    /// first row there is.
    static func defaultLanguage(in list: [Language]) -> Language? {
        let current = Locale.current.identifier
        if let exact = list.first(where: {
            $0.identifier.caseInsensitiveCompare(current) == .orderedSame
        }) {
            return exact
        }
        let code = Locale.current.language.languageCode?.identifier ?? ""
        if !code.isEmpty,
           let near = list.first(where: { $0.identifier.hasPrefix(code) }) {
            return near
        }
        return list.first
    }

    /// The language a caller named — `en-US`, `en`, or a display name — or nil
    /// when nothing in `list` matches it.
    ///
    /// It is asked of BOTH lists, and that is the point: of
    /// `supportedLanguages()` to tell a misspelling from a real tag, and then
    /// of `languages()` to tell a real tag this Mac has a model for from one
    /// it has not. Those are the tool's two language refusals, and one
    /// matcher answers both so they cannot come to disagree about what
    /// counts as a match.
    static func language(matching name: String, in list: [Language]) -> Language? {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return nil }
        if let exact = list.first(where: {
            $0.identifier.caseInsensitiveCompare(wanted) == .orderedSame
        }) { return exact }
        if let named = list.first(where: {
            $0.displayName.caseInsensitiveCompare(wanted) == .orderedSame
        }) { return named }
        // `en` should find `en-US` — a caller who names a language rather
        // than a region means the one this Mac has.
        let prefix = wanted.replacingOccurrences(of: "_", with: "-").lowercased()
        return list.first { $0.identifier.lowercased().hasPrefix(prefix + "-") }
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

    // MARK: - What can be transcribed

    /// Turns clips into jobs, and says why it refused the rest.
    ///
    /// Only a `media` clip whose file exists and has sound can be
    /// transcribed. A `still`, `image`, `text`, `shape` or `nest` source
    /// cannot — `edit.rs`'s non-media rule, in five names — and neither can a
    /// **reversed** clip, whose audio plays backwards and whose transcript
    /// would be nonsense presented as fact.
    ///
    /// "Has sound" is `InspectorTab.hasAudio`'s question and not the media's:
    /// the FILE having an audio track is only half of it, and `enabled.audio`
    /// is the other half (`audio.rs` gives such a clip no voice at all, so the
    /// timeline plays nothing for it). Detach Audio is what makes the
    /// difference visible — it leaves the picture clip with `enabled.audio`
    /// false and puts an audio-only twin with the SAME media, `in`, `start`
    /// and `speed` on the track below, so asking the media would recognise one
    /// recording twice, place two identical cues at one time, and then report
    /// the pile-up it made as captions that had to be shortened.
    static func jobs(
        for clips: [ClipSnapshot], in snapshot: ProjectSnapshot, urls: [UInt32: URL]
    ) -> (jobs: [Job], problems: [CaptionLayout.Problem]) {
        var jobs: [Job] = []
        var problems: [CaptionLayout.Problem] = []
        for clip in clips.sorted(by: { $0.start < $1.start }) {
            let tag = "clip \(clip.id)"
            guard case .media(let media, let sourceIn, let reversed) = clip.source else {
                problems.append(
                    CaptionLayout.Problem(
                        tag: tag, reason: "its source is not a media file, so it has no speech"))
                continue
            }
            guard !reversed else {
                problems.append(
                    CaptionLayout.Problem(
                        tag: tag,
                        reason: "it plays in reverse, so its speech cannot be transcribed"))
                continue
            }
            guard let entry = snapshot.media(media), entry.hasAudio else {
                problems.append(
                    CaptionLayout.Problem(tag: tag, reason: "its media has no audio track"))
                continue
            }
            guard clip.enabled.audio else {
                problems.append(
                    CaptionLayout.Problem(tag: tag, reason: "its audio is switched off"))
                continue
            }
            guard let url = urls[media] else {
                problems.append(
                    CaptionLayout.Problem(tag: tag, reason: "its media file is missing"))
                continue
            }
            guard clip.speed.isFinite, clip.speed > 0, clip.duration > 0 else {
                problems.append(
                    CaptionLayout.Problem(tag: tag, reason: "its speed or length is degenerate"))
                continue
            }
            jobs.append(
                Job(
                    clip: clip.id, name: snapshot.name(of: clip), source: url,
                    sourceIn: max(0, sourceIn), sourceLength: contentLength(of: clip),
                    start: clip.start, duration: clip.duration, speed: clip.speed))
        }
        return (jobs, problems)
    }

    /// How much SOURCE time a clip plays — `Project::content_length`
    /// (`core/src/model_query.rs`) in Swift, saturating the same way, because
    /// the extract's range is a source range and the core owns what that
    /// means.
    private static func contentLength(of clip: ClipSnapshot) -> Ticks {
        let scaled = Double(clip.duration) * clip.speed
        guard scaled.isFinite, scaled >= 1 else { return max(clip.duration, 1) }
        return Ticks(scaled.rounded())
    }

    /// Whether anything in this project could be transcribed at all — the
    /// menu item's validator, deliberately the cheap snapshot question rather
    /// than a plan, because a validator runs on every menu open.
    ///
    /// It asks the same three things `jobs` asks and in the same order, minus
    /// the two a snapshot cannot answer without the document's media URLs, so
    /// the item can only be enabled where a run would find work. `enabled.audio`
    /// is one of the three: a timeline whose every audible clip has had its
    /// sound switched off has nothing to transcribe, and a menu item that
    /// opens a sheet whose only answer is "nothing to transcribe" is the
    /// dialog `generateCaptionsCommand`'s guard exists to prevent.
    static func hasTranscribableClip(in snapshot: ProjectSnapshot) -> Bool {
        snapshot.clips.contains { clip in
            guard case .media(let media, _, let reversed) = clip.source, !reversed,
                  clip.enabled.audio
            else {
                return false
            }
            return snapshot.media(media)?.hasAudio ?? false
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
    private static func project(_ t: Double, in job: Job) -> Ticks {
        let speed = job.speed.isFinite && job.speed > 0 ? job.speed : 1
        let offset = ReelTime.ticks(seconds: max(0, t) / speed)
        return min(job.start + max(0, offset), job.start + job.duration)
    }

    // MARK: - Extraction

    /// What the recogniser is handed: 16 kHz mono 16-bit LPCM in a `.wav`.
    ///
    /// Mono and 16 kHz because that is what speech recognition works in — a
    /// minute of it is under two megabytes, where the app's own 48 kHz stereo
    /// mix (`ExporterWriter.decodedAudioSettings`) would be eleven — and LPCM
    /// because an intermediate should cost no generation of its own. The
    /// stereo→mono downmix and the rate conversion are the reader's:
    /// `AVAssetReaderTrackOutput` does both, with no channel layout needed for
    /// one channel out.
    private static let extractSampleRate = 16000

    private static let extractSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: extractSampleRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    /// Writes the clip's source window to a temporary file and answers where
    /// it went and how long it really is.
    ///
    /// The length is counted in PCM frames rather than read back off the
    /// written asset: `AVAsset.duration` is deprecated in favour of an
    /// `async` accessor this file may not use (app/CLAUDE.md), and frames
    /// divided by a known sample rate is the more exact number anyway. It is
    /// what the truncation test compares against, so it has to be the audio
    /// the recogniser was actually given, not the range that was asked for —
    /// a clip whose source window runs past the end of its file gets a
    /// shorter extract and must not be called truncated for it.
    ///
    /// The file goes in `NSTemporaryDirectory()`, never inside the package:
    /// it is an input to one recognition and is deleted the moment that
    /// recognition ends, unlike a reversed render, which is expensive enough
    /// to be worth carrying (`ReverseCache`'s doc argues the other side).
    private func extractAudio(_ job: Job, cancel: CancelToken) throws -> (
        url: URL, seconds: Double
    ) {
        let asset = AVURLAsset(
            url: job.source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        // The app's one synchronous track lookup, so the deprecation it costs
        // is paid once (`CompositionBuilder.firstTrack`'s doc).
        guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .audio) else {
            throw TranscribeError.unreadable(job.name)
        }

        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reelcut-transcribe-\(UUID().uuidString).wav")
        try? FileManager.default.removeItem(at: destination)

        let range = CMTimeRange(
            start: CompositionBuilder.time(job.sourceIn),
            duration: CompositionBuilder.time(max(1, job.sourceLength)))
        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: destination, fileType: .wav)
        } catch {
            throw TranscribeError.failed(error.localizedDescription)
        }
        reader.timeRange = range

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: Self.extractSettings)
        guard reader.canAdd(output) else { throw TranscribeError.unreadable(job.name) }
        reader.add(output)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.extractSettings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw TranscribeError.unreadable(job.name) }
        writer.add(input)

        guard reader.startReading() else {
            throw TranscribeError.failed(
                reader.error?.localizedDescription ?? "the audio could not be read")
        }
        guard writer.startWriting() else {
            throw TranscribeError.failed(
                writer.error?.localizedDescription ?? "the extract could not be opened")
        }
        // The session begins where the window does, so the first sample lands
        // at zero of the extract — which is what makes `project(_:in:)` a
        // single division with no `in` term in it.
        writer.startSession(atSourceTime: range.start)

        var frames = 0
        while let sample = output.copyNextSampleBuffer() {
            if cancel.isCancelled {
                reader.cancelReading()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: destination)
                throw TranscribeError.cancelled
            }
            // 5 ms is far shorter than any buffer and far longer than a
            // context switch — `ReverseRenderer`'s number, for its reason.
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            guard input.append(sample) else {
                reader.cancelReading()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: destination)
                throw TranscribeError.failed(
                    writer.error?.localizedDescription ?? "the extract could not be written")
            }
            frames += CMSampleBufferGetNumSamples(sample)
        }
        guard reader.status == .completed else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            throw TranscribeError.failed(
                reader.error?.localizedDescription ?? "the audio stopped before it finished")
        }
        input.markAsFinished()
        // `finishWriting` closes the container on a queue of its own, and this
        // method's contract is that the file exists when it returns.
        let closed = DispatchSemaphore(value: 0)
        writer.finishWriting { closed.signal() }
        closed.wait()
        guard writer.status == .completed, frames > 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw TranscribeError.unreadable(job.name)
        }
        return (destination, Double(frames) / Double(Self.extractSampleRate))
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
