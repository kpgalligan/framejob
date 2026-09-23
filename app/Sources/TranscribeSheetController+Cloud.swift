import AppKit

// MARK: - Sheet: the cloud engine

/// Everything on the Generate Captions card that is only about AssemblyAI —
/// road map 6 §5e. The Language popup's second population, what the controls
/// ADD UP TO (`RunRequest`), the readout the estimate writes, the two hint
/// sentences, the notes, and the run itself.
///
/// **It is a file of its own for `AgentServer+CloudCaptions.swift`'s reason,
/// read across to the chrome.** The on-device half of this sheet is a story
/// about an installed MODEL and its Download row; this half is a story about a
/// CREDENTIAL, somebody else's money and a cache. Interleaved they read as one
/// tangle, and the main file would be over its cap besides.
///
/// **Nothing here reads the on-device model list, the Download row or `language`.**
/// That is the whole point of the dispatch in the three methods next door: a
/// Mac with no on-device speech model can still transcribe in the cloud, and
/// this file is where that has to stay true.
///
/// **The controls are read in ONE place.** `runRequest()` is the function
/// from the card's state to what a run would receive, and everything else —
/// the estimate, the notes, the button, the run — goes through it, so the
/// summary can never describe a different request from the one Generate
/// sends. The vocabulary's rules are `TranscriptOptions.keyterms`, the same
/// function the tool uses and not a second copy of it.
extension TranscribeSheetController {

    /// The note under the button when no credential resolves — §5e's
    /// sentence, and it names the window that fixes it.
    static let noKeyNote = "No AssemblyAI API key is set — Reelcut ▸ Settings…"

    // MARK: - The engine and its languages

    /// Read off the ITEM, never off the index — app/CLAUDE.md's popup rule.
    /// Anything unreadable is the on-device engine, which is what every build
    /// before road map 6 did.
    var engine: TranscriptionEngine {
        guard let raw = enginePopup.selectedItem?.representedObject as? String,
            let chosen = TranscriptionEngine(rawValue: raw)
        else { return .apple }
        return chosen
    }

    /// The Language popup for the chosen engine: every locale the on-device
    /// engine supports, a row with no model titled "— not installed", or
    /// "Detect automatically" and then §2's 21 codes by display name.
    ///
    /// The on-device arm is the code `loadView` carried before the Engine
    /// popup existed, moved here whole so switching back answers exactly what
    /// the card opened with.
    func populateLanguages() {
        languagePopup.removeAllItems()
        // A popup's menu validates its own rows, so this has to come BEFORE
        // any row is disabled or AppKit puts it straight back on.
        languagePopup.menu?.autoenablesItems = false
        languagePopup.isEnabled = true
        guard engine == .apple else {
            // "" is the code for DETECTION, which is the wire's absent
            // `language_code`, and it is the row the card opens on: a person
            // who has not said which language they are speaking is better
            // served by the service's own answer than by this Mac's locale.
            languagePopup.addItem(withTitle: "Detect automatically")
            languagePopup.lastItem?.representedObject = ""
            for entry in AssemblyAILanguages.all {
                languagePopup.addItem(withTitle: entry.displayName)
                languagePopup.lastItem?.representedObject = entry.code
            }
            languagePopup.selectItem(at: 0)
            return
        }
        for language in languages {
            languagePopup.addItem(
                withTitle: language.installed
                    ? language.displayName : "\(language.displayName) — not installed")
            // The identifier, not the row's position — see `language`.
            languagePopup.lastItem?.representedObject = language.identifier
        }
        if languages.isEmpty {
            languagePopup.addItem(withTitle: "No on-device language")
            languagePopup.item(at: 0)?.isEnabled = false
            languagePopup.isEnabled = false
        } else if let preferred = Transcriber.defaultLanguage(in: languages),
            let index = languagePopup.itemArray.firstIndex(where: {
                $0.representedObject as? String == preferred.identifier
            })
        {
            languagePopup.selectItem(at: index)
        }
    }

    /// §5e's two hint sentences, verbatim, with the region's own display name
    /// in the cloud one — the person is agreeing to a jurisdiction as much as
    /// to a service.
    static func hint(for engine: TranscriptionEngine, region: AssemblyAIConfiguration.Region)
        -> String
    {
        switch engine {
        case .apple:
            return "The words are recognised ON THIS MAC and land as ordinary text clips on a "
                + "track of their own, so they show in the preview and burn into an export "
                + "with no further step. Nothing is uploaded."
        case .assemblyai:
            return "The audio of these files is uploaded to AssemblyAI (\(region.displayName)), "
                + "transcribed with Universal-3.5 Pro, and deleted from AssemblyAI once the "
                + "words have been read back. Nothing is uploaded until Generate is pressed."
        }
    }

    // MARK: - What the controls add up to

    /// The card's state as what a run would be given — one value, so the
    /// readout, the notes, the button and Generate itself cannot disagree.
    struct RunRequest: Equatable {
        let engine: TranscriptionEngine
        /// The on-device locale identifier, and nil for the cloud engine.
        let appleLanguage: String?
        /// The cloud request, and nil for the on-device engine.
        let options: TranscriptOptions?
        let refresh: Bool
        /// How many terms were TYPED, before the trim, the de-duplication and
        /// the cap — `capNote` is the only reader.
        let vocabularyGiven: Int
    }

    func runRequest() -> RunRequest {
        let chosen = engine
        guard chosen == .assemblyai else {
            return RunRequest(
                engine: .apple, appleLanguage: languagePopup.selectedItem?.representedObject
                    as? String, options: nil, refresh: false, vocabularyGiven: 0)
        }
        let vocabulary = Self.vocabulary(from: vocabularyField.stringValue)
        let code = languagePopup.selectedItem?.representedObject as? String
        return RunRequest(
            engine: .assemblyai, appleLanguage: nil,
            options: TranscriptOptions(
                speechModels: TranscriptOptions.shippedModels,
                languageCode: (code?.isEmpty ?? true) ? nil : code,
                speakerLabels: speakersCheckbox.state == .on,
                keytermsPrompt: vocabulary.terms),
            refresh: refreshCheckbox.state == .on, vocabularyGiven: vocabulary.given)
    }

    /// The Vocabulary field as the tool's `vocabulary` argument: split on
    /// commas, then `TranscriptOptions.keyterms` — the SAME trim, the same
    /// de-duplication keeping the first spelling, the same cap. `given` is
    /// the count before any of that, which is what the tool's own note says.
    static func vocabulary(from text: String) -> (given: Int, terms: [String]) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (0, [])
        }
        let pieces = text.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        return (pieces.count, TranscriptOptions.keyterms(pieces))
    }

    /// The tool's own cap condition (`AgentServer+CloudCaptions.swift`'s
    /// `cloudTranscription`), read across: a list is CUT only when more were
    /// given than kept AND what was kept is exactly the ceiling. A list that
    /// shrank because it held duplicates or blanks lost nothing, and saying
    /// it was capped would send somebody looking for terms they never typed.
    static func capNote(given: Int, kept: Int) -> String? {
        guard given > kept, kept == AssemblyAIClient.maxKeyterms else { return nil }
        return "Vocabulary was capped at \(AssemblyAIClient.maxKeyterms) terms (AssemblyAI's "
            + "limit); \(given) were given."
    }

    // MARK: - The estimate

    /// One `Facts` per media of the current scope, read from disk ONCE per
    /// media for the life of the sheet.
    ///
    /// `refresh` runs on every keystroke in the Vocabulary field, and a stat
    /// of two files per media per keystroke is a spin, not a readout. What
    /// the facts hold cannot change under an open sheet anyway: every editor
    /// action validates false while one is attached.
    func cloudFacts(for jobs: [Transcriber.Job]) -> [CloudEstimate.Facts] {
        guard let cache = document?.cacheDirectory else { return [] }
        var order: [UInt32] = []
        for job in jobs where !order.contains(job.media) { order.append(job.media) }
        let missing = jobs.filter { cloudFactsCache[$0.media] == nil }
        if !missing.isEmpty {
            var records: [UInt32: MediaSnapshot] = [:]
            for entry in snapshot.media { records[entry.id] = entry }
            for fact in CloudEstimate.facts(
                jobs: missing, media: records, cacheDirectory: cache)
            {
                cloudFactsCache[fact.media] = fact
            }
        }
        return order.compactMap { cloudFactsCache[$0] }
    }

    /// What this run would cost and why, or nil when the card is not in a
    /// state that can be priced — the on-device engine, or a document with
    /// nowhere to keep a cache.
    func cloudEstimate() -> CloudEstimate? {
        let request = runRequest()
        guard let options = request.options, document?.cacheDirectory != nil else { return nil }
        return CloudEstimate(
            facts: cloudFacts(for: jobs(in: scope)), options: options, refresh: request.refresh)
    }

    // MARK: - The readout, the note and the button

    /// `refresh`'s cloud arm. Everything the settings state shows, recomputed
    /// from the controls, with nothing about a grant or an on-device model in
    /// it.
    func refreshCloud() {
        let jobs = self.jobs(in: scope)
        let estimate = cloudEstimate()
        let reusable = estimate?.canReuseWithoutCredential == true
        let hasCredential = AssemblyAIConfiguration.credential(
            store: store, environment: environment) != nil
        hintLabel.stringValue = !hasCredential && reusable
            ? "Current cached transcripts will be used without an API key or network request."
            : Self.hint(
                for: .assemblyai, region: AssemblyAIConfiguration.region(defaults: defaults))
        summaryLabel.stringValue = estimate
            .map { CloudEstimate.describe($0, fps: snapshot.canvas.fps) } ?? "Nothing to transcribe"
        // The WHY, where a person can reach it without it pushing the card
        // apart: one line per file that is not already transcribed, plus the
        // dated rate (R6-13 puts a held file's price on its own line).
        let reasons = estimate.map { CloudEstimate.reasons($0) } ?? []
        summaryLabel.toolTip = reasons.isEmpty ? nil : reasons.joined(separator: "\n")
        let note = cloudNoteText(jobs: jobs)
        noteLabel.stringValue = note
        noteLabel.isHidden = note.isEmpty
        let hasWork = estimate.map {
            !$0.uploads.isEmpty || !$0.cached.isEmpty || !$0.awaiting.isEmpty
        } ?? false
        startButton?.isEnabled =
            !jobs.isEmpty
            && document?.cacheDirectory != nil && (hasCredential ? hasWork : reusable)
    }

    /// `noteText`'s cloud arm — the three things that are about the CALL and
    /// not about the audio: no credential, a vocabulary that was cut, and a
    /// scope holding nothing that can be transcribed.
    func cloudNoteText(jobs: [Transcriber.Job]) -> String {
        var notes: [String] = []
        if AssemblyAIConfiguration.credential(store: store, environment: environment) == nil,
            cloudEstimate()?.canReuseWithoutCredential != true
        {
            notes.append(Self.noKeyNote)
        }
        if document?.cacheDirectory == nil {
            notes.append(
                "This project has nowhere to keep its transcript cache, so it cannot be "
                    + "transcribed with AssemblyAI. Save it first.")
        }
        let request = runRequest()
        if let cap = Self.capNote(
            given: request.vocabularyGiven, kept: request.options?.keytermsPrompt.count ?? 0)
        {
            notes.append(cap)
        }
        if jobs.isEmpty {
            notes.append(
                "Only a clip whose media has sound can be transcribed, and never one played in "
                    + "reverse.")
        }
        return notes.joined(separator: " ")
    }

    // MARK: - The run

    /// The cloud run, on the same `CancelToken` the on-device one uses, so
    /// Stop cancels an upload or a wait exactly as it cancels a recognition.
    ///
    /// The transcriber is stored in `cloud` for its whole life: `run` hops
    /// onto its own serial queue under `[weak self]`, and a transcriber
    /// nobody retains never completes at all. Progress arrives on that queue
    /// and is hopped to main here, `ConsolidateProgressSheetController`'s
    /// shape and the on-device arm's.
    func beginCloud() {
        guard !didStart else { return }
        let request = runRequest()
        guard let options = request.options, let cache = document?.cacheDirectory
        else {
            NSSound.beep()
            return
        }
        let credential = AssemblyAIConfiguration.credential(
            store: store, environment: environment)
        var client: AssemblyAIClient?
        if let credential {
            do {
                let base = try AssemblyAIConfiguration.baseURL(defaults: defaults)
                client = AssemblyAIClient(base: base, credential: credential)
            } catch {
                // A misconfigured keyed endpoint is a result card.
                didStart = true
                showProgress()
                finish(.failure(error))
                return
            }
        }
        didStart = true
        let jobs = self.jobs(in: scope)
        showProgress()
        statusLabel.stringValue =
            "Transcribing \(jobs.count) clip\(jobs.count == 1 ? "" : "s") with AssemblyAI…"
        var records: [UInt32: MediaSnapshot] = [:]
        for entry in snapshot.media { records[entry.id] = entry }
        let run = CloudTranscriber(
            client: client,
            cacheDirectory: cache, media: records)
        cloud = run
        // A code the person NAMED comes back as itself; only an absent one
        // was detected, which is what makes a confidence figure honest.
        cloudDetected = options.languageCode == nil
        run.run(
            jobs: jobs, options: options, refresh: request.refresh,
            frame: max(snapshot.canvas.fps.frameDuration, 1), pages: pagesRequest, cancel: token,
            progress: { [weak self] fraction, name in
                DispatchQueue.main.async { self?.progressed(fraction, name) }
            },
            completion: { [weak self] outcome in
                guard let self = self else { return }
                self.finishCloud(outcome, report: run.report)
            })
    }

    /// A Stop between worker success and main delivery still prevents placement.
    func finishCloud(
        _ outcome: Result<Transcriber.Outcome, any Error>, report: CloudTranscriber.Report
    ) {
        precondition(Thread.isMainThread)
        cloudReport = report
        if case .success = outcome, token.isCancelled {
            finish(.failure(Transcriber.TranscribeError.cancelled))
        } else {
            finish(outcome)
        }
    }
}
