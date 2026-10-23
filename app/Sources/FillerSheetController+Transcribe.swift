import AppKit

// MARK: - Sheet: the media with no filler transcript

/// Remove Filler Words' TR-7 section (spec §11 TR-2, TR-10): one row per
/// media in scope with no AssemblyAI transcript made with filler words — its
/// name, what one press would upload and cost (`CloudEstimate.describe` of
/// the very request the run sends, `FillerTranscription`), and a Transcribe
/// button — and the run that button starts.
///
/// **One media per press.** The request is the media's previous one plus
/// fillers (`FillerTranscription.options`), and the run only writes the
/// media's transcript cache: no caption is placed and no undo step is made.
/// When it lands the sheet reads its input again (`runEnded`), so the media
/// leaves the list and its fillers join the count.
///
/// **The button is disabled** with no credential (the note names Settings),
/// with no cache directory (the note says to save), with no clip that plays
/// the media from its file, and while any run goes — except the running
/// row's, which reads Stop and cancels it.
extension FillerSheetController {

    /// The rows, made again from `input.needsTranscript`: called at open, when
    /// a run starts and when it ends.
    func rebuildRows() {
        for view in rowsStack.arrangedSubviews {
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        mediaRows = []
        runnable = []
        let snapshot = document?.editedProject.snapshot
        let urls = document?.mediaURLs() ?? [:]
        var records: [UInt32: MediaSnapshot] = [:]
        for entry in snapshot?.media ?? [] { records[entry.id] = entry }
        let textWidth = sheetWidth - sheetInset * 2 - 120
        for media in input.needsTranscript {
            let jobs =
                snapshot.map { FillerTranscription.jobs(for: media, in: $0, urls: urls) } ?? []
            let name = NSTextField(labelWithString: records[media]?.name ?? "Media \(media)")
            name.font = DS.sans(13)
            name.textColor = DS.textStrong
            name.lineBreakMode = .byTruncatingMiddle
            name.preferredMaxLayoutWidth = textWidth
            let estimate = NSTextField(wrappingLabelWithString: "")
            estimate.font = DS.mono(11)
            estimate.textColor = DS.textMuted
            estimate.preferredMaxLayoutWidth = textWidth
            if let cache = cacheDirectory,
                let priced = FillerTranscription.estimate(
                    jobs: jobs, media: records, cacheDirectory: cache)
            {
                estimate.stringValue = CloudEstimate.describe(priced, fps: input.fps)
                estimate.toolTip = CloudEstimate.rateSentence(speakers: priced.speakers)
                runnable.insert(media)
            } else {
                estimate.stringValue = cacheDirectory == nil
                    ? "Save the project to transcribe it"
                    : "No clip plays this file, so it cannot be transcribed"
            }
            if media == runningMedia { estimate.stringValue = "Starting…" }
            let button = StickerButton(
                title: "Transcribe", style: .secondary, target: self,
                action: #selector(transcribeClicked(_:)))
            let text = NSStackView(views: [name, estimate])
            text.orientation = .vertical
            text.alignment = .leading
            text.spacing = 2
            text.widthAnchor.constraint(equalToConstant: textWidth).isActive = true
            let line = NSStackView(views: [text, button])
            line.orientation = .horizontal
            line.alignment = .centerY
            line.spacing = 12
            rowsStack.addArrangedSubview(line)
            mediaRows.append(MediaRow(media: media, name: name, estimate: estimate, button: button))
        }
        transcribeSection.isHidden = input.needsTranscript.isEmpty
    }

    /// Whether a key resolves, through the sheet's own store and environment.
    var hasCredential: Bool {
        AssemblyAIConfiguration.credential(store: store, environment: environment) != nil
    }

    /// The buttons' titles and states: Stop on the running row, Transcribe
    /// on every other, enabled only when a press could run.
    func refreshRows() {
        let idle = runningMedia == nil
        let hasCredential = self.hasCredential
        for row in mediaRows {
            let title = row.media == runningMedia ? "Stop" : "Transcribe"
            if row.button.title != title {
                row.button.title = title
                row.button.invalidateIntrinsicContentSize()
            }
            if row.media == runningMedia {
                row.button.isEnabled = true
                continue
            }
            row.button.isEnabled = idle && hasCredential && runnable.contains(row.media)
        }
    }

    /// What the rows need said: no key, and nowhere to keep a transcript.
    func transcribeNotes() -> [String] {
        guard !input.needsTranscript.isEmpty else { return [] }
        var notes: [String] = []
        if !hasCredential { notes.append(TranscribeSheetController.noKeyNote) }
        if cacheDirectory == nil {
            notes.append(
                "This project has nowhere to keep its transcript cache, so it cannot be "
                    + "transcribed with AssemblyAI. Save it first.")
        }
        return notes
    }

    // MARK: - The run

    /// Transcribe on an idle row starts its run; Stop on the running row
    /// cancels it.
    @objc func transcribeClicked(_ sender: Any?) {
        guard let button = sender as? NSButton,
            let row = mediaRows.first(where: { $0.button === button })
        else { return }
        if row.media == runningMedia {
            token?.cancel()
            return
        }
        guard runningMedia == nil else {
            NSSound.beep()
            return
        }
        transcribe(media: row.media)
    }

    /// One media's paid upload, on `CloudTranscriber.run`'s own queue, with
    /// the request `FillerTranscription` builds; the completion arrives on
    /// main and goes to `runEnded`.
    func transcribe(media: UInt32) {
        guard let document = document, let cache = cacheDirectory,
            let credential = AssemblyAIConfiguration.credential(
                store: store, environment: environment)
        else {
            NSSound.beep()
            return
        }
        let client: AssemblyAIClient
        do {
            client = AssemblyAIClient(
                base: try AssemblyAIConfiguration.baseURL(defaults: defaults),
                credential: credential)
        } catch {
            lastError = error.localizedDescription
            refresh()
            return
        }
        let snapshot = document.editedProject.snapshot
        let jobs = FillerTranscription.jobs(for: media, in: snapshot, urls: document.mediaURLs())
        guard !jobs.isEmpty else {
            NSSound.beep()
            return
        }
        var records: [UInt32: MediaSnapshot] = [:]
        for entry in snapshot.media { records[entry.id] = entry }
        let run = CloudTranscriber(client: client, cacheDirectory: cache, media: records)
        let cancel = Transcriber.CancelToken()
        cloud = run
        token = cancel
        runStarted(media: media)
        run.run(
            jobs: jobs,
            options: FillerTranscription.options(
                for: MediaTranscript.readStamp(for: media, in: cache)),
            refresh: FillerTranscription.refresh,
            frame: max(snapshot.canvas.fps.frameDuration, 1),
            pages: CaptionPages.Request(
                style: .subtitles,
                canvas: CGSize(width: snapshot.canvas.width, height: snapshot.canvas.height)),
            cancel: cancel,
            progress: { [weak self] fraction, detail in
                DispatchQueue.main.async { self?.progressed(media, fraction, detail) }
            },
            completion: { [weak self] outcome in
                guard let self = self, !self.tornDown else { return }
                if case .failure(let error) = outcome {
                    self.runEnded(error: error)
                } else {
                    self.runEnded(error: nil)
                }
            })
    }

    /// The running row's estimate line, while it runs.
    private func progressed(_ media: UInt32, _ fraction: Double, _ detail: String) {
        guard media == runningMedia, let row = mediaRows.first(where: { $0.media == media })
        else { return }
        let percent = "\(Int((min(max(fraction, 0), 1) * 100).rounded())) %"
        row.estimate.stringValue = (detail.isEmpty ? "Transcribing" : detail) + " · " + percent
    }
}
