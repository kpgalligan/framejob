import Foundation

/// `get_transcript` (road map "cut-by-transcript" CT-4, spec §11 TR-5,
/// TR-11): one clip's spoken words in TIMELINE ticks, fillers flagged — the
/// words File ▸ Generate Captions… and Clip ▸ Remove Filler Words… read,
/// handed to the caller so the assistant can choose a false start and cut it
/// with `ripple_delete_ranges`.
///
/// An APP-STATE tool and a read: nothing is edited and no undo step is made.
/// The source is the media's cached transcript when one is current
/// (`TranscriptReader.cached`), else this Mac's recogniser over the clip's own
/// window, whose words are kept in a regenerable per-media, per-language cache
/// (`DeviceTranscriptCache`, TR-14) that a later call inside a stored run
/// answers from; never the network, so it has no AI-7 row.
///
/// **It runs on the SERVER thread** (`AgentServer.offMainTools`), for
/// `transcribe`'s reason: the on-device run blocks its caller for seconds to
/// minutes. The clip, its job and the cache are read in ONE main-thread hop,
/// `transcribeForFillers`' posture. The assistant's Stop reaches the
/// on-device run through its `Transcriber.CancelToken`, linked exactly as
/// `transcribe` links its own (AI-16 as TR-11 amends it).
extension AgentServer {

    /// `get_transcript` — the words Generate Captions… and Remove Filler
    /// Words… read, for one clip. Refused in TR-11's order: the clip, a clip
    /// with no speech from a media file, the `from`/`to` window (TR-13), the
    /// language's spelling, then — with no cached transcript only — the
    /// installed model and the recogniser's own sentence.
    func getTranscript(_ a: [String: Any]) throws -> String {
        let stop = AgentLane.shared.callCancel  // the assistant's Stop (spec §11 AI-16, TR-11)
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "get_transcript must run on the server thread — its name is missing "
                    + "from AgentServer.offMainTools.")
        }
        struct Context {
            let document: ProjectDocument
            let job: Transcriber.Job
            let cached: TranscriptReader.Cached?
            /// The `from`/`to` window, snapped and clamped; nil without one (TR-13).
            let window: TranscriptReader.Window?
            /// Where the on-device cache lives, and the clip's media (TR-14).
            let cacheDir: URL?
            let media: MediaSnapshot?
        }
        let context = try onMain { () -> Context in
            let document = try self.target(a)
            let clip = try self.clipArg(a, "clip", document)
            let snapshot = document.editedProject.snapshot
            let outcome = Transcriber.jobs(
                for: [clip], in: snapshot, urls: document.mediaURLs(),
                maps: document.editedProject.sourceMap)
            guard let job = outcome.jobs.first else {
                let reason = outcome.problems.first?.reason ?? "it plays no speech"
                throw ToolError(message: "Clip \(clip.id) has no words to read: \(reason).")
            }
            let from = try self.optionalTimeArg(a, "from", document)
            let to = try self.optionalTimeArg(a, "to", document)
            let window: TranscriptReader.Window?
            do {
                window = try TranscriptReader.window(from: from, to: to, clip: job)
            } catch let error as TranscriptReader.WindowError {
                throw ToolError(message: error.localizedDescription)
            }
            var cached: TranscriptReader.Cached?
            let cacheDir = document.cacheDirectory
            let media = snapshot.media(job.media)
            if let cache = cacheDir, let media {
                cached = TranscriptReader.cached(for: media, url: job.source, in: cache)
            }
            return Context(
                document: document, job: job, cached: cached, window: window, cacheDir: cacheDir,
                media: media)
        }
        let wanted = try stringArg(a, "language")
        try Self.checkSpelling(of: wanted)

        let job = context.job
        let window = context.window
        let words: [TranscriptReader.Word]
        var result: [String: Any]
        if let cached = context.cached {
            let cloudWords = TranscriptReader.cloudWords(for: job, in: cached.file)
            words = window.map { TranscriptReader.overlapping(cloudWords, in: $0) } ?? cloudWords
            result = [
                "engine": TranscriptionEngine.assemblyai.rawValue,
                "fillers_reported": cached.fillersReported,
            ]
            if let code = cached.file.header.languageCode { result["language"] = code }
        } else {
            let language = try Self.transcriptionLanguage(wanted)
            // The assistant's Stop reaches the run through its own token (AI-16, TR-11).
            let token = Transcriber.CancelToken()
            stop?.onCancel { token.cancel() }
            // A window narrows what the recogniser hears to it and 2 s either side (TR-13).
            let run = window.map { TranscriptReader.recognitionJob(job, for: $0) } ?? job
            // A stored run that heard this span answers; else it is recognised and kept (TR-14).
            let answer: (heard: DeviceTranscriptCache.Heard, cached: Bool)
            do {
                answer = try DeviceTranscriptCache.heard(
                    run, language: language.identifier, media: context.media,
                    in: context.cacheDir, cancelled: { token.isCancelled },
                    recognize: {
                        try TranscriptReader.recognize(run, language: language, cancel: token)
                    })
            } catch {
                throw ToolError(message: error.localizedDescription)
            }
            let heard = TranscriptReader.deviceWords(answer.heard, for: job)
            words = window.map { TranscriptReader.overlapping(heard, in: $0) } ?? heard
            result = [
                "engine": TranscriptionEngine.apple.rawValue,
                "fillers_reported": false,
                "language": language.identifier,
                "cached": answer.cached,
            ]
        }

        result["ok"] = true
        result["clip"] = Int(job.clip)
        result["media"] = Int(job.media)
        result["count"] = words.count
        if let window {
            result["from"] = window.from
            result["to"] = window.to
        }
        result["words"] = words.map { word -> [String: Any] in
            var row: [String: Any] = [
                "text": word.text, "start": word.start, "end": word.end, "filler": word.filler,
            ]
            if let speaker = word.speaker { row["speaker"] = speaker }
            return row
        }
        var notes: [String] = []
        if words.isEmpty {
            notes.append(
                window.map {
                    "No words were heard in clip \(job.clip) between \($0.from) and \($0.to) ticks."
                } ?? "No words were heard in clip \(job.clip).")
        }
        if result["fillers_reported"] as? Bool != true {
            notes.append(
                "These words were not transcribed with filler words, so a filler missing here "
                    + "may still be in the audio.")
        }
        if !notes.isEmpty { result["note"] = notes.joined(separator: " ") }
        return try onMain {
            result["project"] = self.summary(context.document)
            return try self.jsonResult(result)
        }
    }
}
