import AppKit

/// `transcribe`'s CLOUD arm — road map 6 §5g. The engine argument, the three
/// arguments that only mean something with it, and the run itself.
///
/// It is a file of its own, and `AgentServer+Captions.swift` is otherwise the
/// code it was, for the reason §5g gives: the on-device path's refusals are a
/// story about a GRANT and a downloaded MODEL, the cloud path's are a story
/// about a CREDENTIAL and somebody else's service, and the two read as one
/// tangle when they are interleaved. What the two share — the scope, the
/// jobs, the frame, the cues, `CaptionLayout.place` and the result's shape —
/// stays over there and is reached exactly once from here, through this
/// method's two arguments and its answer.
///
/// **R6-2: `engine` is never remembered.** `TranscriptionEngine.defaultsKey`
/// is the SHEET's memory of what a person last chose, and this file does not
/// read it. An agent that wants its audio uploaded says so every time, which
/// is the only shape in which a call's meaning does not depend on what
/// somebody did in the UI an hour ago.
///
/// **R6-7: no `async`, and no queue of its own.** `CloudTranscriber.transcribe`
/// is the SYNCHRONOUS body, and this handler is already off main
/// (`AgentServer.offMainTools`), so the run happens on the server thread and
/// the wait IS the call — `transcribe`'s own argument for why it is in that
/// set, read across to an engine that waits on a socket instead of on a
/// recogniser.
///
/// **No credential is ever in an answer.** Not in a `ToolError`, not in a
/// `Problem`, not in the `note`: the only thing this file does with the
/// credential is hand it to `AssemblyAIClient.init`, which puts it in one
/// header and in no log line.
extension AgentServer {

    // MARK: - The engine argument

    /// `engine`, refused BY NAME with both spellings when it is neither.
    ///
    /// Absent is `.apple`, and absent is the ONLY thing that makes it
    /// `.apple`: `UserDefaults` is not consulted here (R6-2). It is read
    /// through `stringArg`, so a number or an object is refused as a type
    /// error naming the key before the spelling is even looked at.
    func transcriptionEngine(_ a: [String: Any]) throws -> TranscriptionEngine {
        guard let name = try stringArg(a, "engine") else { return .apple }
        guard let engine = TranscriptionEngine(rawValue: name) else {
            throw ToolError(
                message: "engine must be \"apple\" or \"assemblyai\" (got \"\(name)\").")
        }
        return engine
    }

    /// The three arguments that only mean something to AssemblyAI, refused
    /// by name under `engine: "apple"`.
    ///
    /// `voice_confidence`-with-`mode: "level"`'s precedent (road map 4):
    /// an argument that cannot do anything is a MISTAKE, not a no-op, and
    /// dropping it quietly would let a caller believe a speaker-labelled
    /// transcript had been asked for and read the cues as if it had. The
    /// FIRST one present is the one named, in a fixed order, so the refusal
    /// is the same sentence for the same call every time.
    func refuseCloudOnlyArguments(_ a: [String: Any]) throws {
        for key in ["speakers", "vocabulary", "refresh"] {
            guard let value = a[key], !(value is NSNull) else { continue }
            throw ToolError(
                message: "\(key) only applies with engine \"assemblyai\". Pass engine: "
                    + "\"assemblyai\", or leave it out.")
        }
    }

    // MARK: - The cloud run

    /// The whole of the cloud arm: the three arguments, the vocabulary's
    /// rules, the credential, the endpoint, the run, and the result keys
    /// `Outcome` has no room for.
    ///
    /// **The refusal order is §5g's**, and every step of it is above the
    /// network on purpose. The caller's own mistakes are already answered by
    /// the time this is called (unknown clip, empty scope, misspelt engine);
    /// here it is the arguments' own types and values, then the CREDENTIAL,
    /// then the endpoint — and only then is a socket opened. A run that was
    /// going to be refused for a missing key must not first extract and
    /// upload half a gigabyte of audio to find that out.
    ///
    /// **The main thread is touched exactly once**, for the document's cache
    /// directory and its media records. Everything else the run needs is in
    /// the `Job`s by value, which is what lets the whole round trip happen
    /// off main with no document held.
    func cloudTranscription(
        _ a: [String: Any], document: ProjectDocument, jobs: [Transcriber.Job], frame: Ticks,
        language: String?
    ) throws -> (outcome: Transcriber.Outcome, fields: [String: Any]) {
        let speakers = try boolArg(a, "speakers") ?? false
        let asked = try stringsArg(a, "vocabulary") ?? []
        let refresh = try boolArg(a, "refresh") ?? false
        let code = try Self.cloudLanguage(language)
        let vocabulary = Self.keyterms(asked)

        var notes: [String] = []
        if asked.count > vocabulary.count, vocabulary.count == AssemblyAIClient.maxKeyterms {
            notes.append(
                "vocabulary was capped at \(AssemblyAIClient.maxKeyterms) terms (AssemblyAI's "
                    + "limit); \(asked.count) were given.")
        }

        let store = AssemblyAIConfiguration.store()
        guard let credential = AssemblyAIConfiguration.credential(store: store) else {
            throw ToolError(
                message: "No AssemblyAI API key is set. Set one in Reelcut ▸ Settings ▸ "
                    + "Transcription, or RC_ASSEMBLYAI_KEY for a proof.")
        }
        let base: URL
        do {
            base = try AssemblyAIConfiguration.baseURL()
        } catch {
            throw ToolError(message: error.localizedDescription)
        }

        let context = try onMain { () -> (cache: URL, media: [UInt32: MediaSnapshot]) in
            guard let cache = document.cacheDirectory else {
                throw ToolError(
                    message: "This document has nowhere to keep its transcript cache, so it "
                        + "cannot be transcribed with AssemblyAI. Save it first.")
            }
            var records: [UInt32: MediaSnapshot] = [:]
            for entry in document.editedProject.snapshot.media { records[entry.id] = entry }
            return (cache, records)
        }

        let options = TranscriptOptions(
            speechModels: TranscriptOptions.shippedModels, languageCode: code,
            speakerLabels: speakers, keytermsPrompt: vocabulary)
        let transcriber = CloudTranscriber(
            client: AssemblyAIClient(base: base, credential: credential),
            cacheDirectory: context.cache, media: context.media)
        let outcome: Transcriber.Outcome
        do {
            outcome = try transcriber.transcribe(
                jobs, options: options, refresh: refresh, frame: frame,
                cancel: Transcriber.CancelToken())
        } catch {
            // In band, message and all, exactly as the on-device arm does —
            // including "no speech was recognised", which is a true answer
            // about the audio rather than a transport problem.
            throw ToolError(message: error.localizedDescription)
        }
        return (outcome, Self.cloudFields(transcriber.report, code: code, notes: notes))
    }

    /// `language` for the cloud engine: absent or `"auto"` is DETECTION,
    /// which is the wire's absent `language_code`; anything else is passed
    /// through trimmed.
    ///
    /// Nothing here checks the code against a table. C0's q5 measured that a
    /// code AssemblyAI does not support is a 400 at SUBMISSION in 0.24 s with
    /// its own sentence — so the cost of a wrong code is one wasted upload,
    /// and relaying the service's answer is better than carrying a second
    /// dated list of codes that can be wrong in the other direction. An
    /// EMPTY string is refused here, though: it is not a code and it is not
    /// "auto", and sending it would be asking for a language called "".
    private static func cloudLanguage(_ wanted: String?) throws -> String? {
        guard let wanted = wanted else { return nil }
        let trimmed = wanted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolError(
                message: "language cannot be empty. Pass a code like en, or \"auto\" to let "
                    + "AssemblyAI detect it, or leave it out.")
        }
        return trimmed.lowercased() == "auto" ? nil : trimmed
    }

    /// `keyterms_prompt`: trimmed, empties dropped, de-duplicated KEEPING
    /// THE FIRST spelling, capped at `AssemblyAIClient.maxKeyterms`.
    ///
    /// First rather than last because the order a caller wrote is the order
    /// of importance it meant, and the cap cuts from the end — a list that
    /// re-ordered itself and then cut would drop terms the caller put first.
    private static func keyterms(_ given: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for term in given {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            out.append(trimmed)
            if out.count == AssemblyAIClient.maxKeyterms { break }
        }
        return out
    }

    /// The result keys the cloud engine adds — §5g's list, built from the
    /// run's own `Report` and from nothing else.
    ///
    /// `note` exists only when there is a part to put in it: R6-8's fallback
    /// ran, a vocabulary was cut, or a remote delete is still owed. An empty
    /// note would be a key a caller has to read to learn nothing.
    private static func cloudFields(
        _ report: CloudTranscriber.Report, code: String?, notes: [String]
    ) -> [String: Any] {
        var parts = notes
        let preferred = TranscriptOptions.shippedModels.first ?? "universal-3-5-pro"
        for row in report.uploaded {
            guard let model = row.speechModelUsed, model != preferred else { continue }
            parts.append(
                "AssemblyAI transcribed media \(row.media) with \(model), not \(preferred).")
        }
        // Once per media id: a media can be in `janitorFailed` (an id owed
        // from an earlier run) and in `uploaded` with `remoteDeleted` false
        // (an id owed from this one), and saying it twice would read as two
        // transcripts.
        var owed: [UInt32] = []
        for id in report.janitorFailed where !owed.contains(id) { owed.append(id) }
        for row in report.uploaded where !row.remoteDeleted && !owed.contains(row.media) {
            owed.append(row.media)
        }
        for id in owed {
            parts.append(
                "AssemblyAI has not confirmed deleting the transcript of media \(id); the next "
                    + "run retries it.")
        }

        var fields: [String: Any] = [
            "engine": TranscriptionEngine.assemblyai.rawValue,
            "language": code ?? "auto",
            "uploaded": report.uploaded.map { Int($0.media) },
            "cached": report.cached.map { Int($0) },
            "audio_seconds": report.uploaded.reduce(0) { $0 + $1.audioSeconds },
        ]
        let models: [[String: Any]] = report.uploaded.compactMap { row in
            guard let model = row.speechModelUsed else { return nil }
            return ["media": Int(row.media), "model": model]
        }
        if !models.isEmpty { fields["speech_model_used"] = models }
        // Only under detection: a code the caller NAMED comes back as itself
        // and reporting it as "detected" would be a false claim about how it
        // was arrived at (C0's q1 measured that `language_confidence` is
        // present only when the language was detected).
        if code == nil {
            let detected: [[String: Any]] = report.uploaded.compactMap { row in
                guard let answer = row.languageCode else { return nil }
                var out: [String: Any] = ["media": Int(row.media), "code": answer]
                if let confidence = row.languageConfidence { out["confidence"] = confidence }
                return out
            }
            if !detected.isEmpty { fields["language_detected"] = detected }
        }
        if !parts.isEmpty { fields["note"] = parts.joined(separator: " ") }
        return fields
    }
}
