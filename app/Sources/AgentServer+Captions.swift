import AppKit

/// The agent's two caption tools: `transcribe` (File ▸ Generate Captions…)
/// and `export_captions` (File ▸ Export Captions…) — the two directions of
/// phase 4's caption work.
///
/// They live in a file of their own rather than beside `import_captions` in
/// `AgentServer+Media.swift` for `AgentServer+Silence.swift`'s reason: neither
/// is a mirror of an op, both are app-state tools with a concern of their own
/// — one drives a speech recogniser, the other writes a subtitle container —
/// and the argument for how each is threaded belongs beside the code it
/// explains rather than three files away.
///
/// **`transcribe` runs on the SERVER thread** (`AgentServer.offMainTools`).
/// The set's criterion is "waits for something the main thread has to deliver
/// or must not be doing", and a recognition task is both halves of it: the
/// Speech framework delivers its callbacks on an `OperationQueue` that
/// defaults to the app's main one, so a main-thread wait would deadlock
/// exactly as `import_media`'s probe would, and a transcription is seconds to
/// minutes of work that must not freeze the UI. `detect_silence` was kept OUT
/// of the set on the same criterion read the other way — it reads a few
/// hundred KB and returns — and that is the distinction, not "touches the
/// disk".
///
/// **`export_captions` runs on the MAIN thread**, where every other
/// non-`offMainTools` handler runs: writing a few KB of text synchronously
/// waits on nothing and has no completion to deliver, which is
/// `import_captions`' own argument in the opposite direction.
extension AgentServer {

    // MARK: - Transcribing

    /// `transcribe` — File ▸ Generate Captions… (`TranscribeSheetController`,
    /// whose language popup, clip scope and progress bar are these arguments
    /// and this result). On-device speech recognition over the clips' own
    /// audio, laid out as ordinary text clips through the same
    /// `CaptionLayout.place` an imported `.srt` goes through, so a generated
    /// caption and an imported one are the same kind of thing afterwards.
    ///
    /// **Runs on the server thread** (`AgentServer.offMainTools`) and calls
    /// `Transcriber.transcribe` — the SYNCHRONOUS body its own doc offers "a
    /// tool that already runs on the server thread" — rather than `run`,
    /// whose completion is posted to main for a sheet's benefit. There is
    /// therefore no semaphore here at all: the wait is the call, and the main
    /// thread stays free to deliver the recogniser's callbacks, which is the
    /// whole reason this tool is off main.
    ///
    /// **It never asks for the Speech Recognition grant.**
    /// `SFSpeechRecognizer.authorizationStatus()` is a synchronous read, so
    /// the refusal is instant and its message can carry the fix;
    /// `requestAuthorization` puts up a system prompt that needs the app to be
    /// FRONTMOST, and an agent-driven app is never the active app (the fact
    /// `AgentServer.target`'s doc already turns on). A prompt nobody can see
    /// would hold this handler open to its ceiling. Asking is the sheet's job,
    /// because a person opened it — `Transcriber.canAsk` is the same question
    /// `FFmpegRewrap.canAsk` asks about the same launch flag.
    ///
    /// **The order of the refusals is deliberate**, and the LANGUAGE question
    /// is split across it, because its two halves are not the same kind of
    /// question. The caller's own mistakes — a clip id that names nothing, a
    /// scope with nothing audible in it, and a language tag speech
    /// recognition has never heard of — are model questions and are answered
    /// FIRST, so they stay reachable on a machine with no grant;
    /// `Transcriber.supportedLanguages()` reads the same at every
    /// authorization status, so a misspelling can be named there honestly.
    /// The grant is checked next, and only then whether this Mac has a MODEL
    /// for the language that was named, because `Transcriber.languages()` is
    /// a framework question about downloaded assets and a machine nobody has
    /// granted yet would otherwise be told to download what it may already
    /// have — "no languages" where the true answer is "you have not granted
    /// this yet". That ordering is what makes the grant-less refusals checks
    /// a proof script can run, and they are the only part of this tool a
    /// headless run reaches.
    ///
    /// **Since road map 6's C1 it has TWO engines** (§5g), and this method
    /// owns only the choice between them: `engine` is read after the
    /// caller's own model mistakes and before anything either engine does,
    /// and each arm is then the code it was or is
    /// (`AgentServer+CloudCaptions.swift`). The order of the refusals, end to
    /// end: the unknown clip and the empty scope (the scope), a misspelt
    /// `engine` with both spellings named, then — under `apple` — a
    /// cloud-only argument refused BY NAME, the language's spelling, the
    /// grant and the on-device model; or — under `assemblyai` — the three
    /// cloud arguments' own types, the credential, the endpoint, a media over
    /// ten hours, and only then the network. `truncated` can appear for the
    /// on-device engine alone: there is no one-minute ceiling on the other
    /// side of a REST call, and `CloudTranscriber` answers no truncations at
    /// all.
    func transcribe(_ a: [String: Any]) throws -> String {
        // `importMedia`'s guard, restated: everything below assumes the main
        // thread is free, which is only true while this handler is not
        // standing on it.
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "transcribe must run on the server thread — its name is missing from "
                    + "AgentServer.offMainTools.")
        }
        let place = try boolArg(a, "place") ?? true
        let wanted = try stringArg(a, "language")

        let document = try onMain { try self.target(a) }
        // The scope, the jobs and the frame in ONE main-thread hop, so every
        // decision below is made against one snapshot rather than against
        // however many the document had while we were hopping. `Job` carries
        // everything by value for the same reason.
        let scope = try onMain { try self.transcriptionScope(a, document) }
        guard !scope.jobs.isEmpty else { throw scope.emptyRefusal }

        let outcome: Transcriber.Outcome
        var fields: [String: Any]
        switch try transcriptionEngine(a) {
        case .apple:
            // An argument that can only mean something to AssemblyAI is the
            // caller's own mistake and is named before any work starts.
            try refuseCloudOnlyArguments(a)

            // A tag the framework has never heard of is a typo, and a typo is
            // the caller's own mistake, so it is answered here with the rest
            // of them and above the grant. See the two-part note in this
            // method's doc.
            try Self.checkSpelling(of: wanted)

            guard Transcriber.isAuthorized else {
                throw ToolError(message: Transcriber.authorizationRefusal.localizedDescription)
            }
            let language = try Self.transcriptionLanguage(wanted)

            // Held on this stack for the whole call, as `export` holds its
            // `Exporter`: the transcriber owns the task's delegate, which the
            // task itself does not retain.
            let transcriber = Transcriber()
            do {
                outcome = try transcriber.transcribe(
                    scope.jobs, language: language, frame: scope.frame,
                    cancel: Transcriber.CancelToken())
            } catch {
                // Every failure comes back in band, message and all —
                // including "no speech was recognised", which is a true
                // answer about the audio rather than a transport problem.
                throw ToolError(message: error.localizedDescription)
            }
            fields = [
                "engine": TranscriptionEngine.apple.rawValue,
                "language": language.identifier,
            ]
        case .assemblyai:
            let answer = try cloudTranscription(
                a, document: document, jobs: scope.jobs, frame: scope.frame, language: wanted)
            outcome = answer.outcome
            fields = answer.fields
        }

        // Ticks, not seconds: every other tool speaks the model's own unit and
        // the catalog has one sentence for it.
        let reported: [[String: Any]] = outcome.cues.map {
            ["start": $0.start, "end": $0.end, "text": $0.text]
        }
        var problems = scope.problems + outcome.problems
        fields["cues"] = reported
        fields["clips_read"] = outcome.clips.map { Int($0) }
        if !outcome.truncations.isEmpty {
            fields["truncated"] = outcome.truncations.map {
                ["clip": Int($0.clip), "at": $0.stoppedAt, "end": $0.end] as [String: Any]
            }
            // Reported rather than worked around: the framework stops a
            // recognition task after about a minute, and a caption run that
            // quietly ended at 60 s and said nothing is the failure this key
            // exists to prevent.
            let count = outcome.truncations.count
            fields["note"] =
                "Recognition stopped early on \(count) clip" + (count == 1 ? "" : "s")
                + ". Speech recognition ends a task after about a minute, so nothing between "
                + "at and end was heard. Split the clip and transcribe the halves."
        }

        // `place: false` is a read, like `detect_silence`: no ops, no undo
        // step, and the caller places the cues itself or does not.
        guard place else {
            fields["ok"] = true
            fields["placed"] = false
            if !problems.isEmpty { fields["skipped"] = problems.map { $0.description } }
            return try onMain {
                fields["project"] = self.summary(document)
                return try self.jsonResult(fields)
            }
        }
        return try onMain {
            // The plan is built at COMMIT time against the document's CURRENT
            // handle. Recognition is asynchronous work that took real seconds,
            // and `CaptionLayout.place` probes the handle to learn the ids its
            // own ops will mint — so a plan built before the recognition
            // could patch ids that no longer mean what it thought.
            let plan: CaptionLayout.Plan
            do {
                plan = try CaptionLayout.place(
                    outcome.cues, problems: problems, in: document.editedProject)
            } catch {
                throw ToolError(message: error.localizedDescription)
            }
            problems = plan.problems
            fields["placed"] = true
            fields["captions"] = plan.clips
            if let name = plan.trackName { fields["track_name"] = name }
            if plan.trimmed > 0 { fields["trimmed"] = plan.trimmed }
            if !problems.isEmpty { fields["skipped"] = problems.map { $0.description } }
            return try self.editResult(document, "Generate Captions", plan.ops, fields)
        }
    }

    /// What a run will read, what it will not, and the frame it measures
    /// against — everything `Transcriber` needs, by value.
    ///
    /// Main thread only: it reads the snapshot and the document's media URLs.
    private func transcriptionScope(
        _ a: [String: Any], _ document: ProjectDocument
    ) throws -> TranscriptionScope {
        // The OPEN container's, because the ops this run produces are
        // addressed to it (road map 2's phase 9). Reading the document and
        // writing into the nest is one gesture measuring against one timeline
        // and landing in another; `SilenceDetector` and `AudioNormalize` were
        // moved off that shape in the same phase, and File ▸ Generate
        // Captions… reads the same handle for the same reason.
        let snapshot = document.editedProject.snapshot
        let named = try optionalClipsArg(a, "clips", document)
        let clips = named.map { ids in ids.compactMap { snapshot.clip($0) } } ?? snapshot.clips
        let outcome = Transcriber.jobs(for: clips, in: snapshot, urls: document.mediaURLs())
        // An unnamed scope is every clip in the project, and most of them are
        // legitimately not speech — listing "clip 3: its source is not a media
        // file" for a whole timeline would bury the one entry that matters.
        // Only clips the caller ASKED for are reported, which is
        // `import_captions`' rule read across: it reports what the caller's
        // own file was too malformed to use.
        let problems = named == nil ? [] : outcome.problems
        return TranscriptionScope(
            jobs: outcome.jobs, problems: problems, named: named != nil,
            frame: max(snapshot.canvas.fps.frameDuration, 1))
    }

    /// The jobs a run will do, and how to refuse when there are none.
    private struct TranscriptionScope {
        let jobs: [Transcriber.Job]
        let problems: [CaptionLayout.Problem]
        /// Whether the caller named the clips, which decides which refusal
        /// is the honest one: "none of THOSE" or "nothing here at all".
        let named: Bool
        let frame: Ticks

        var emptyRefusal: AgentServer.ToolError {
            guard named else {
                return ToolError(
                    message: "Nothing in this timeline has recorded sound to transcribe. Only a "
                        + "clip playing a movie or sound file can be, and not one played in "
                        + "reverse.")
            }
            let reasons = problems.map { $0.description }.joined(separator: "; ")
            return ToolError(
                message: "None of those clips can be transcribed"
                    + (reasons.isEmpty ? "." : " — " + reasons + "."))
        }
    }

    /// The first half of the language question: is this a language tag at
    /// ALL? Everything the framework names passes, model or no model.
    ///
    /// It is a separate function because it is a separate PROBLEM with a
    /// separate fix. A tag speech recognition has never heard of is a
    /// misspelling and is retyped; a tag it knows that this Mac has no model
    /// for is a download, and `transcriptionLanguage` below refuses that one
    /// in those words. One refusal for both would send somebody whose only
    /// problem was an undownloaded model back to check a tag that was right
    /// all along — which is what `transcribe`'s catalog entry promises does
    /// not happen, and the promise is the reason this half exists.
    ///
    /// Being asked above the grant is the other reason. The framework's list
    /// is static and reads the same at every authorization status, so this
    /// answer is honest on a machine nobody has granted, where the on-device
    /// question is not.
    ///
    /// It refuses only where that list is NON-EMPTY. An empty one is not
    /// evidence that a tag is wrong — it is evidence that the question could
    /// not be asked at all — and "no such language" off it would be the very
    /// mistake the grant-first ordering exists to avoid, one list further out.
    private static func checkSpelling(of wanted: String?) throws {
        guard let wanted = wanted else { return }
        let known = Transcriber.supportedLanguages()
        guard !known.isEmpty, Transcriber.language(matching: wanted, in: known) == nil else {
            return
        }
        throw ToolError(
            message: Transcriber.TranscribeError.unknownLanguage(wanted).localizedDescription
                + " It knows \(known.count): " + list(known) + ".")
    }

    /// The second half: the `language` argument as one of the rows the
    /// sheet's popup shows, refused BY NAME when this Mac has no on-device
    /// MODEL for it — the argument vocabulary's rule applied to a vocabulary
    /// that is the machine's rather than the model's.
    ///
    /// `Transcriber.language(matching:in:)` does the matching (an identifier,
    /// a bare language code, or the display name), and
    /// `Transcriber.defaultLanguage` the fallback, so the tool and the popup
    /// cannot drift apart.
    private static func transcriptionLanguage(_ wanted: String?) throws -> Transcriber.Language {
        let languages = Transcriber.languages()
        guard !languages.isEmpty else {
            throw ToolError(
                message: "This Mac has no ON-DEVICE speech model for any language. macOS "
                    + "downloads one the first time a language is used for dictation: open "
                    + "System Settings ▸ Keyboard ▸ Dictation, add a language, and try again.")
        }
        guard let wanted = wanted else {
            guard let fallback = Transcriber.defaultLanguage(in: languages) else {
                throw ToolError(
                    message: "No language could be chosen. Pass language with one of: "
                        + list(languages) + ".")
            }
            return fallback
        }
        guard let match = Transcriber.language(matching: wanted, in: languages) else {
            throw noModelRefusal(for: wanted, ready: languages)
        }
        return match
    }

    /// "This Mac has no model for a language it otherwise understands" — the
    /// download refusal, and the only way past `checkSpelling` that is still
    /// about the language.
    ///
    /// The display NAME comes back out of the framework's list rather than
    /// being echoed as the caller typed it, because "French (France) has no
    /// on-device speech model" reads as a fact about a language where "fr has
    /// no on-device speech model" reads as a fact about a string. A tag that
    /// arrives here with no name to be found can only mean the framework's
    /// list was empty when `checkSpelling` asked it, and then the tag is the
    /// best name there is — one message with a fallback, rather than a third
    /// arm that nothing can reach, which is the shape this whole refusal was
    /// found in.
    private static func noModelRefusal(
        for wanted: String, ready: [Transcriber.Language]
    ) -> ToolError {
        let known = Transcriber.supportedLanguages()
        let name = Transcriber.language(matching: wanted, in: known)?.displayName ?? wanted
        return ToolError(
            message: Transcriber.TranscribeError.noOnDeviceModel(name).localizedDescription
                + " Ready to use here: " + list(ready) + ".")
    }

    /// The identifiers of either list, capped: the framework names sixty-odd
    /// and an error message that prints all sixty is not read at all.
    private static func list(_ languages: [Transcriber.Language]) -> String {
        let names = languages.map { $0.identifier }.sorted()
        guard names.count > 24 else { return names.joined(separator: ", ") }
        return names.prefix(24).joined(separator: ", ") + ", …and \(names.count - 24) more"
    }

    // MARK: - Exporting captions

    /// `export_captions` — File ▸ Export Captions… (`CaptionExporter`, which
    /// owns the two containers and the round-trip rule). Writes one text
    /// track's clips out as SubRip (`.srt`) or WebVTT (`.vtt`). It edits
    /// nothing, so it answers through `jsonResult` rather than `editResult`
    /// and registers no undo step.
    ///
    /// **The track is never guessed**, and the rule is `CaptionExporter`'s
    /// rather than restated here: the default is the single track whose clips
    /// are all text, and with none or with more than one
    /// `CaptionExporter.resolveTrack` refuses and its `ExportError` LISTS the
    /// candidates by id, name and cue count. That is the posture
    /// `remove_media` takes for media still in use and `export` takes for an
    /// unknown size; picking the front-most candidate would write the wrong
    /// file and report success.
    ///
    /// The one thing this handler owns is the PATH, because a path is an
    /// argument rather than a caption question: the format is resolved first
    /// (an explicit `format` wins, else the path's own extension, else
    /// SubRip) so `destinationURL` can replace a wrong extension rather than
    /// append to it — `talk.srt` asked for as `vtt` is `talk.vtt`, not
    /// `talk.srt.vtt`, which is why `srt` and `vtt` joined
    /// `replaceableExtensions`.
    func exportCaptions(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        // The open container's, so the track this writes is the one
        // `get_project` is listing.
        let snapshot = document.editedProject.snapshot
        let path = try requiredString(a, "path")
        let expanded = (path as NSString).expandingTildeInPath
        let format = CaptionExporter.format(
            for: URL(fileURLWithPath: expanded), requested: try requestedFormat(a))
        let url = Self.destinationURL(path, extension: format.rawValue)
        let folder = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw ToolError(message: "There is no folder at \(folder.path) to write into.")
        }

        // Read through `trackArg` rather than handed to the exporter raw, so
        // an id that names nothing is refused as "No track has id N" here
        // instead of arriving there as a track with no clips.
        var requestedTrack: UInt32?
        if a["track"] != nil, !(a["track"] is NSNull) {
            requestedTrack = try trackArg(a, "track", document).id
        }
        let outcome: (track: UInt32, format: CaptionExporter.Format, cues: [CaptionExporter.Cue])
        do {
            outcome = try CaptionExporter.export(
                from: snapshot, track: requestedTrack, to: url, format: format)
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        return try jsonResult([
            "ok": true,
            // The URL that was WRITTEN, never the argument: `destinationURL`
            // replaces a wrong extension, and every caller reports what
            // actually landed so the substitution is never silent.
            "path": url.path,
            "format": outcome.format.rawValue,
            "track": Int(outcome.track),
            "track_name": snapshot.track(outcome.track)?.name ?? "",
            "cues": outcome.cues.count,
            "project": summary(document),
        ])
    }

    /// The `format` argument, refused BY NAME when it is not one of the two
    /// containers — nil when it is absent, which is what lets
    /// `CaptionExporter.format(for:requested:)` fall back to the path.
    private func requestedFormat(_ a: [String: Any]) throws -> CaptionExporter.Format? {
        guard let name = try stringArg(a, "format") else { return nil }
        guard let format = CaptionExporter.Format(rawValue: name.lowercased()) else {
            let known = CaptionExporter.Format.allCases.map { $0.rawValue }
            throw ToolError(
                message: "format must be one of " + known.joined(separator: ", ")
                    + " (got \"\(name)\").")
        }
        return format
    }
}
