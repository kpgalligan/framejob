import AppKit

/// Clip ▸ Remove Filler Words… — road map "cut-by-transcript" CT-3 (spec §11
/// TR-4, TR-7, TR-10): `detect_fillers`' answer as a count, the same spans
/// washed onto the timeline behind the sheet, and one `ripple_delete_ranges`
/// op when Remove is pressed.
///
/// **`SilenceSheetController`'s shape, without its controls.** TR-9 has no
/// threshold, padding or length to tune, so there is nothing to change and
/// `refresh()` runs only when the input does: at open, and after a
/// Transcribe run lands a filler transcript. The input is read once by the
/// command, as Remove Silences' is, because the document cannot change under
/// an open sheet — every editor action validates false while one is attached.
///
/// **The media with no filler transcript** (TR-7: the fillers come only from
/// an AssemblyAI transcript that asked for them) get a section of their own:
/// the cloud-only note, where the audio goes (R6-2), and one row per media
/// with its estimate and a Transcribe button
/// (`FillerSheetController+Transcribe.swift`). A run is one media's paid
/// upload, so Remove is disabled while it goes: Return cannot cut, and Cancel
/// is the only default-key path left, which stops the run.
final class FillerSheetController: NSViewController {
    /// Weak, like every sheet's back-reference: the document must be free to
    /// close even with a dialog mid-air.
    weak var document: ProjectDocument?
    /// Weak too. The candidate wash is the sheet's own view state, so the
    /// sheet sets it and the sheet clears it.
    weak var timeline: TimelineView?

    /// Everything a detection reads, taken off the document once — and again
    /// when a Transcribe run lands, which is why it is a `var`.
    var input: FillerDetector.Input
    /// Where the transcript cache lives; nil for a document that has none.
    let cacheDirectory: URL?
    /// Where the AssemblyAI key, the region and the endpoint come from —
    /// `TranscribeSheetController`'s injection points, for the probe.
    let store: any SecretStore
    let defaults: UserDefaults
    let environment: [String: String]

    /// What the sheet currently describes. Remove sends exactly these spans,
    /// so the readout and the edit cannot disagree.
    private(set) var outcome: FillerDetector.Outcome
    /// The media a Transcribe run is going for, or nil when none is.
    private(set) var runningMedia: UInt32?
    /// The last run's error sentence, shown in the note until the next run.
    var lastError: String?
    /// The run in flight, held for its whole life: `CloudTranscriber.run`
    /// hops onto its own queue under `[weak self]`, and a transcriber nobody
    /// retains never completes.
    var cloud: CloudTranscriber?
    /// The running run's Stop.
    var token: Transcriber.CancelToken?
    /// Set by the teardown, so a run that answers after the sheet has gone
    /// cannot put the wash back.
    var tornDown = false

    let summaryLabel = NSTextField(labelWithString: "")
    let noteLabel = NSTextField(wrappingLabelWithString: "")
    /// The TR-7 section's second line: R6-2's where, which region, and the
    /// deletion, set before any Transcribe button can be enabled.
    let hintLabel = NSTextField(wrappingLabelWithString: "")
    let cloudNoteLabel = NSTextField(wrappingLabelWithString: FillerSheetController.cloudOnlyNote)
    /// The TR-7 section: the note, the hint and the rows; hidden when every
    /// media in scope already has a filler transcript.
    let transcribeSection = NSStackView()
    let rowsStack = NSStackView()
    /// Set in `loadView`; the only implicitly-unwrapped optional here.
    private(set) var applyButton: NSButton!
    /// One per `outcome.needsTranscript`, in order.
    var mediaRows: [MediaRow] = []
    /// The rows' media a press could run: a cache directory and at least one
    /// clip that plays it from its file.
    var runnable: Set<UInt32> = []

    struct MediaRow {
        let media: UInt32
        let name: NSTextField
        let estimate: NSTextField
        let button: NSButton
    }

    /// TR-7's sentence.
    static let cloudOnlyNote =
        "Filler words are found only in an AssemblyAI transcript made with filler words — "
        + "transcription on this Mac does not report them. These files have none yet:"

    /// Generate Captions…' AssemblyAI sentence with "Transcribe" for
    /// "Generate" (R6-2, kept by TR-10).
    static func uploadHint(region: AssemblyAIConfiguration.Region) -> String {
        "The audio of these files is uploaded to AssemblyAI (\(region.displayName)), "
            + "transcribed with Universal-3.5 Pro, and deleted from AssemblyAI once the "
            + "words have been read back. Nothing is uploaded until Transcribe is pressed."
    }

    init(
        document: ProjectDocument, timeline: TimelineView?, input: FillerDetector.Input,
        cacheDirectory: URL?, store: any SecretStore = AssemblyAIConfiguration.store(),
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.document = document
        self.timeline = timeline
        self.input = input
        self.cacheDirectory = cacheDirectory
        self.store = store
        self.defaults = defaults
        self.environment = environment
        self.outcome = FillerDetector.detect(input)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FillerSheetController does not support NSCoder")
    }

    // MARK: - View

    override func loadView() {
        let width = sheetWidth - sheetInset * 2
        summaryLabel.font = DS.mono(11)
        summaryLabel.textColor = DS.textMuted
        noteLabel.font = DS.sans(11)
        noteLabel.textColor = DS.textFaint
        noteLabel.preferredMaxLayoutWidth = width
        cloudNoteLabel.font = DS.sans(12)
        cloudNoteLabel.textColor = DS.textStrong
        cloudNoteLabel.preferredMaxLayoutWidth = width
        hintLabel.font = DS.sans(11)
        hintLabel.textColor = DS.textMuted
        hintLabel.preferredMaxLayoutWidth = width
        // R6-2 before any button: the sentence is set here, ahead of the
        // first `rebuildRows`, so no Transcribe can be enabled without it.
        hintLabel.stringValue = Self.uploadHint(
            region: AssemblyAIConfiguration.region(defaults: defaults))

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 8
        transcribeSection.orientation = .vertical
        transcribeSection.alignment = .leading
        transcribeSection.spacing = 8
        for view in [cloudNoteLabel, hintLabel, rowsStack] as [NSView] {
            transcribeSection.addArrangedSubview(view)
        }

        let content = sheetColumn([summaryLabel, noteLabel, transcribeSection])

        let cancelButton = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        applyButton = StickerButton(
            title: "Remove", style: .primary, target: self, action: #selector(applyClicked(_:)))
        view = makeSheetView(
            title: "Remove Filler Words",
            hint: "Each run of filler words — um, uh, er and the rest — is cut and the timeline "
                + "closes over it, as one edit. A cut is widened to the 32 ms speech grid so "
                + "the whole filler goes, but never into the words beside it, and its edges "
                + "snap inward to the frame grid. A filler that would cut into another clip's "
                + "word, a nest or a transition is left in.",
            content: content,
            buttonRow: makeButtonRow(
                cancel: cancelButton, apply: applyButton,
                leading: [sheetFootnote("markers keep their place")]))
        rebuildRows()
        refresh()
    }

    // MARK: - Detection

    /// Re-detect and republish everything that follows from it: the readout,
    /// the rows' buttons, the note, the Remove button and the timeline's wash.
    func refresh() {
        outcome = FillerDetector.detect(input)
        summaryLabel.stringValue = summaryText()
        refreshRows()
        let note = noteText()
        noteLabel.stringValue = note
        noteLabel.isHidden = note.isEmpty
        applyButton?.isEnabled = !outcome.spans.isEmpty && runningMedia == nil
        timeline?.candidateSpans = outcome.spans
    }

    /// "3 cuts · removes 00:00:01:12", in the app's one spelling of a time.
    private func summaryText() -> String {
        guard !outcome.spans.isEmpty else { return "No cuts" }
        let cuts = outcome.spans.count == 1 ? "1 cut" : "\(outcome.spans.count) cuts"
        return cuts + " · removes " + ReelTime.format(outcome.removed, fps: input.fps, frames: true)
    }

    /// The second line, joined: what the count alone would hide.
    private func noteText() -> String {
        var notes: [String] = []
        if outcome.scope == .selected {
            notes.append("Only the selected clips are read.")
        }
        let dropped = outcome.dropped.count
        if dropped > 0 {
            notes.append(
                (dropped == 1 ? "1 filler is" : "\(dropped) fillers are")
                    + " left in: too short to cut, or cutting would reach another clip's word, "
                    + "a nest or a transition.")
        }
        let locked = outcome.locked.count
        if locked > 0 {
            notes.append(
                (locked == 1 ? "1 clip is" : "\(locked) clips are")
                    + " on a locked track, which the cut neither cuts nor moves, so "
                    + (locked == 1 ? "its" : "their") + " fillers were not read.")
        }
        if outcome.clips.isEmpty, outcome.needsTranscript.isEmpty, outcome.locked.isEmpty {
            notes.append("Nothing in scope plays speech from a media file, so nothing was read.")
        }
        notes.append(contentsOf: transcribeNotes())
        if let lastError { notes.append(lastError) }
        return notes.joined(separator: " ")
    }

    // MARK: - A Transcribe run's two ends

    /// A run has started for `media`: Remove goes off and its row reads Stop.
    func runStarted(media: UInt32) {
        runningMedia = media
        lastError = nil
        rebuildRows()
        refresh()
    }

    /// A run has ended: the input is read again, so a media that now has a
    /// filler transcript leaves the list and its fillers are counted.
    func runEnded(error: (any Error)?) {
        runningMedia = nil
        cloud = nil
        token = nil
        lastError = error?.localizedDescription
        if let document = document {
            input = FillerDetector.read(from: document, clips: nil)
        }
        rebuildRows()
        refresh()
    }

    // MARK: - Commit

    @objc private func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    /// ONE `ripple_delete_ranges` for however many spans — one op, one undo
    /// step. The button is disabled when there is nothing to cut and while a
    /// run goes, and AppKit skips a disabled button for Return, so the guard
    /// below should be unreachable.
    @objc private func applyClicked(_ sender: Any?) {
        guard endSheetFieldEditing() else { return }
        let document = self.document
        dismiss(self)
        guard let document = document, !outcome.spans.isEmpty, runningMedia == nil else { return }
        document.applyEdit(
            "Remove Filler Words",
            [.rippleDeleteRanges(ranges: outcome.spans.map { (from: $0.start, to: $0.end) })])
    }

    /// The one teardown point, for Remove, Cancel, Escape and a window
    /// closing under the sheet alike: a run still going is stopped, and the
    /// wash comes off — it is not part of `TimelineView.update(...)`.
    override func viewDidDisappear() {
        super.viewDidDisappear()
        tornDown = true
        token?.cancel()
        timeline?.candidateSpans = []
    }
}

// MARK: - The menu command

/// The command half, at the foot of the file that owns the feature —
/// `SilenceSheetController.swift`'s precedent.
extension EditorViewController {

    /// Clip ▸ Remove Filler Words… — the body of the frozen file's one-line
    /// `@objc func removeFillerWords(_:)` forward. It beeps with no clip that
    /// plays sound from a media file, the validator's own question.
    func removeFillerWordsCommand() {
        guard let document = document, view.window?.attachedSheet == nil,
            Transcriber.hasTranscribableClip(in: document.editedProject.snapshot)
        else {
            NSSound.beep()
            return
        }
        let input = FillerDetector.read(from: document, clips: nil)
        // The wash is read while the sheet is up, and a running playhead
        // repaints over it several times a second.
        playback.pause()
        let sheet = FillerSheetController(
            document: document, timeline: timeline, input: input,
            cacheDirectory: document.cacheDirectory)
        presentAsSheet(sheet)
    }

    /// The half of `validateUserInterfaceItem` this file owns. nil means "not
    /// mine" and leaves the other answers alone.
    func validateFillerAction(_ action: Selector) -> Bool? {
        guard action == #selector(EditorViewController.removeFillerWords(_:)) else { return nil }
        guard let document = document else { return false }
        return Transcriber.hasTranscribableClip(in: document.editedProject.snapshot)
    }
}
