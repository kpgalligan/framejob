import AppKit

/// File ▸ Generate Captions… — road map 2 phase 4a's dialog: a language, a
/// scope, and then the same card turned into a progress bar while
/// `Transcriber` works.
///
/// **One sheet, two states, and that is deliberate.**
/// `ConsolidateProgressSheetController` already changes its own buttons and
/// labels mid-run, and `ExportProgressSheetController` puts the reason best:
/// success and failure both turn the sheet into its own result panel rather
/// than trading it for an alert. Presenting a SECOND sheet from this one's
/// action is the thing `ReverseProgressSheetController.viewDidDisappear`
/// records as not working here — a sheet dismissed a moment ago is still
/// `window.attachedSheet` and the next presentation is refused. Staying one
/// sheet also keeps the bargain that lets this card be trusted: every editor
/// action validates false while a sheet is attached, so the clips it counted
/// in `init` are the clips that will be transcribed.
///
/// **A model is installed HERE and nowhere else** (spec §11 W-8). The
/// Language popup lists every locale the engine supports, a row whose model
/// is missing marked "— not installed", and choosing one shows the Download
/// row (`TranscribeSheetController+Download.swift`): a download is a
/// person's act, so the `transcribe` tool refuses such a locale by name and
/// never downloads. Generate is live only for an installed language. No grant
/// is asked for and no ceiling is reported: W0 q1 measured neither.
///
/// **Two engines, one card (road map 6 §5e).** An Engine popup under
/// Language chooses between the recogniser on this Mac and AssemblyAI, and
/// the choice re-populates Language, shows or hides the three cloud rows, and
/// changes the hint. `TranscribeSheetController+Cloud.swift` holds everything
/// that is only about the cloud engine; what is HERE is the card, and three
/// methods — `refresh`, `noteText` and `startClicked` — whose FIRST statement
/// dispatches on the engine. That order is load-bearing: under
/// `.assemblyai` none of the three reads `language` or `languages`, so a Mac
/// with no on-device model can still transcribe in the cloud.
///
/// **The widenings this split cost**, in toll 3's pattern: `languages`,
/// `mediaURLs`, `languagePopup`, `summaryLabel`, `noteLabel`, `hintLabel`,
/// `scope`, `jobs(in:)`, `startButton`, `showProgress()` and `progressed(_:_:)`
/// are internal rather than private, because `+Cloud.swift` builds the same
/// card out of them. W2 widened `language`, `grid` and `refresh()` for the
/// Download row's file; the cloud half still reads none of them.
///
/// **The Style row and what hangs under it** are two more files:
/// `TranscribeSheetController+Style.swift` (the Style popup, the preview and
/// Replace) and `TranscribeSheetController+Looks.swift` (the three look
/// checkboxes and the on-device note, spec §11 W-15). What is HERE for them
/// is their stored views and their grid rows.
///
/// **Four injection points, for the probe and for nothing else.** `store`,
/// `defaults`, `environment` and `languages` are initialiser arguments with
/// the app's own values as defaults, so an instrument can build this sheet
/// with an empty `MemoryStore`, a throwaway defaults suite, no environment
/// and no on-device model at all, and measure what a person would see.
final class TranscribeSheetController: NSViewController {

    /// Which clips a run is taken over.
    enum Scope: CaseIterable {
        case selection
        case range
        case all

        var displayName: String {
            switch self {
            case .selection: return "Selected clips"
            case .range: return "In/out range"
            case .all: return "Whole timeline"
            }
        }
    }

    /// Weak, like every sheet's back-reference: the document must be free to
    /// close even with a dialog mid-air.
    weak var document: ProjectDocument?

    /// Everything a run reads, taken off the document once. The document
    /// cannot change under an open sheet, which is what makes that safe.
    let snapshot: ProjectSnapshot
    /// The source maps of the handle `snapshot` came from (spec §11 SR-20 (d)).
    let sourceMaps: SourceMaps
    let mediaURLs: [UInt32: URL]
    private let selection: Set<UInt32>
    private let inOutRange: (start: Ticks, end: Ticks)?
    var languages: [Transcriber.Language]

    /// Where the AssemblyAI key comes from, where the region and the
    /// remembered engine are read and written, and what a `RC_ASSEMBLYAI_KEY`
    /// would be read out of — injected so a probe can build this card with an
    /// empty store and a throwaway suite. R6-9's folder override is already
    /// inside `AssemblyAIConfiguration.store()`.
    let store: any SecretStore
    let defaults: UserDefaults
    let environment: [String: String]

    private let transcriber = Transcriber()
    let token = Transcriber.CancelToken()

    let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let enginePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let speakersCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let vocabularyField = NSTextField()
    let refreshCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let scopePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let summaryLabel = NSTextField(labelWithString: "")
    let noteLabel = NSTextField(wrappingLabelWithString: "")
    /// The engine's own hint. `makeSheetView` takes `hint: nil` and this
    /// label goes first in the content instead, because the sentence changes
    /// with the popup and the builder's hint is a constructor argument.
    let hintLabel = NSTextField(wrappingLabelWithString: "")
    let bar = NSProgressIndicator()
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    let detailLabel = NSTextField(labelWithString: "")
    let stylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    /// The three looks (`+Looks.swift`), titled and set by `makeLooksRow()`.
    let slideCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let fillCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let dimCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let dimNoteLabel = NSTextField(wrappingLabelWithString: "")
    let previewView = NSImageView()
    let replaceCheckbox = NSButton(checkboxWithTitle: "existing captions", target: nil, action: nil)
    let replaceLabel = NSTextField(wrappingLabelWithString: "")
    /// Set in `loadView`; the only implicitly-unwrapped optionals here, which
    /// is what app/CLAUDE.md allows them for.
    private var settingsStack: NSStackView!
    private var progressStack: NSStackView!
    var grid: NSGridView!
    var stopButton: NSButton!
    var startButton: NSButton!
    /// The Download row's three views, built by `makeDownloadRow()`.
    var downloadButton: NSButton!
    var downloadBar: NSProgressIndicator!
    var downloadLabel: NSTextField!
    /// The running download's own `Progress`, observed while it runs.
    var downloadProgress: Progress?
    var downloadObservation: NSKeyValueObservation?
    /// The locale the RUNNING download is for; nil when none runs.
    var downloading: Transcriber.Language?

    /// The run, held for its life: `CloudTranscriber.run` hops onto its own
    /// queue with `[weak self]`, so a transcriber nobody retains never
    /// completes at all.
    var cloud: CloudTranscriber?
    /// What the cloud run said beside its `Outcome` — the report card's
    /// extra lines, read by `finish`.
    var cloudReport: CloudTranscriber.Report?
    /// Whether the language was DETECTED rather than named, which is what
    /// makes a confidence figure a true claim about how it was arrived at.
    var cloudDetected = false
    /// One `CloudEstimate.Facts` per media, read from disk once per sheet —
    /// `refresh` runs on every keystroke in the Vocabulary field and a stat
    /// per keystroke per media is not a readout, it is a spin.
    var cloudFactsCache: [UInt32: CloudEstimate.Facts] = [:]
    /// The answer `sampleWords()` gave for a job's clip — the fixed sample when the
    /// transcript is absent or has no words for it — so a MISS is read once too
    /// (`cloudFactsCache`'s rule: `refresh` runs per keystroke).
    var sampleWordsCache: [UInt32: [CaptionCues.Word]] = [:]
    /// What the preview was last drawn for (`+Style.swift`); nil until the
    /// first `refreshStyleRow`, which therefore always draws.
    var previewKey: PreviewKey?

    var didStart = false
    var didFinish = false


    private static let scopes = Scope.allCases
    /// The grid rows that belong to AssemblyAI alone.
    static let cloudRows = [3, 4, 5]

    init(
        document: ProjectDocument, store: any SecretStore = AssemblyAIConfiguration.store(),
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        languages: [Transcriber.Language] = Transcriber.supportedLanguages()
    ) {
        self.document = document
        // The container the cues will LAND in, not the document — see
        // `CaptionImporter.plan`'s paragraph. A scope cannot change under
        // an open sheet, so capturing it here is as safe as the rest.
        self.snapshot = document.editedProject.snapshot
        self.sourceMaps = document.editedProject.sourceMap
        self.mediaURLs = document.mediaURLs()
        self.selection = document.selection
        self.inOutRange = document.inOutRange
        self.languages = languages
        self.store = store
        self.defaults = defaults
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TranscribeSheetController does not support NSCoder")
    }

    // MARK: - What each scope would transcribe

    private func clips(in scope: Scope) -> [ClipSnapshot] {
        switch scope {
        case .selection:
            return snapshot.clips.filter { selection.contains($0.id) }
        case .range:
            guard let range = inOutRange else { return [] }
            return snapshot.clips.filter { $0.start < range.end && $0.end > range.start }
        case .all:
            return snapshot.clips
        }
    }

    func jobs(in scope: Scope) -> [Transcriber.Job] {
        Transcriber.jobs(
            for: clips(in: scope), in: snapshot, urls: mediaURLs, maps: sourceMaps
        ).jobs
    }

    /// The scope the sheet opens on: what the user pointed at, if it holds
    /// anything transcribable, then the range they marked, then everything.
    private var defaultScope: Scope {
        if !jobs(in: .selection).isEmpty { return .selection }
        if inOutRange != nil, !jobs(in: .range).isEmpty { return .range }
        return .all
    }

    var scope: Scope {
        let index = scopePopup.indexOfSelectedItem
        guard Self.scopes.indices.contains(index) else { return .all }
        return Self.scopes[index]
    }

    /// The row's own language, read off the item rather than counted off the
    /// list: two locales can localize to one display name, and the rows are
    /// `NSMenuItem`s because `NSPopUpButton.addItem(withTitle:)` would REMOVE
    /// an existing row with the same title before adding the new one — so an
    /// index into `languages` could name a different language than the row
    /// the person clicked. `CaptionExporter`'s track popup carries the same
    /// guard for the same reason (app/CLAUDE.md's popup rule).
    var language: Transcriber.Language? {
        guard let identifier = languagePopup.selectedItem?.representedObject as? String else {
            return languages.first
        }
        return languages.first { $0.identifier == identifier } ?? languages.first
    }

    // MARK: - View

    override func loadView() {
        languagePopup.font = DS.sans(13)
        languagePopup.widthAnchor.constraint(equalToConstant: 200).isActive = true

        // The remembered engine, and the ONLY place it is read (R6-2 keeps
        // an agent call out of this key). An absent or unknown value is the
        // on-device engine, which is what every build before this one did.
        for engine in TranscriptionEngine.allCases {
            let item = NSMenuItem(title: engine.displayName, action: nil, keyEquivalent: "")
            item.representedObject = engine.rawValue
            enginePopup.menu?.addItem(item)
        }
        let remembered = defaults.string(forKey: TranscriptionEngine.defaultsKey)
        if let index = enginePopup.itemArray.firstIndex(where: {
            $0.representedObject as? String == remembered
        }) {
            enginePopup.selectItem(at: index)
        } else {
            enginePopup.selectItem(at: 0)
        }
        enginePopup.font = DS.sans(13)
        enginePopup.target = self
        enginePopup.action = #selector(engineChanged(_:))
        enginePopup.widthAnchor.constraint(equalToConstant: 200).isActive = true
        populateLanguages()

        speakersCheckbox.title = "split by speaker, coloured in Subtitles"
        speakersCheckbox.font = DS.sans(12)
        speakersCheckbox.target = self
        speakersCheckbox.action = #selector(controlChanged(_:))
        DSField.style(vocabularyField)
        vocabularyField.placeholderString = "names and jargon, separated by commas"
        vocabularyField.delegate = self
        vocabularyField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        refreshCheckbox.title = "ignore any cached transcript"
        refreshCheckbox.font = DS.sans(12)
        refreshCheckbox.target = self
        refreshCheckbox.action = #selector(controlChanged(_:))

        for scope in Self.scopes {
            scopePopup.addItem(withTitle: scope.displayName)
        }
        // Same rule, and the reason it matters: offering a scope that holds
        // nothing with speech in it is offering a run whose only answer is
        // "there was nothing to transcribe".
        scopePopup.menu?.autoenablesItems = false
        for (index, scope) in Self.scopes.enumerated() where jobs(in: scope).isEmpty {
            scopePopup.item(at: index)?.isEnabled = false
        }
        scopePopup.selectItem(at: Self.scopes.firstIndex(of: defaultScope) ?? 2)
        scopePopup.font = DS.sans(13)
        scopePopup.target = self
        scopePopup.action = #selector(controlChanged(_:))
        scopePopup.widthAnchor.constraint(equalToConstant: 200).isActive = true

        summaryLabel.font = DS.mono(11)
        summaryLabel.textColor = DS.textMuted
        noteLabel.font = DS.sans(11)
        noteLabel.textColor = DS.textFaint
        noteLabel.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2
        // `makeSheetView`'s own hint style, because this label is standing in
        // for the one it would have built.
        hintLabel.font = DS.sans(12)
        hintLabel.textColor = DS.textMuted
        hintLabel.isEditable = false
        hintLabel.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2

        grid = makeSheetGrid([
            [fieldLabel("Language:"), languagePopup],
            makeDownloadRow(),
            [fieldLabel("Engine:"), enginePopup],
            [fieldLabel("Speakers:"), speakersCheckbox],
            [fieldLabel("Vocabulary:"), vocabularyField],
            [fieldLabel("Transcribe again:"), refreshCheckbox],
            [fieldLabel("From:"), scopePopup],
            makeStyleRow(),
            makeLooksRow(),
            makePreviewRow(),
            makeReplaceRow(),
        ])

        settingsStack = sheetColumn([grid, summaryLabel, noteLabel])

        styleSheetProgressBar(bar)
        styleSheetStatusLabel(statusLabel)
        styleSheetDetailLabel(detailLabel)

        progressStack = makeProgressStack([bar, statusLabel, detailLabel])
        progressStack.isHidden = true

        let content = NSStackView(views: [hintLabel, settingsStack, progressStack])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 0
        content.setCustomSpacing(16, after: hintLabel)

        stopButton = sheetCancelButton(target: self, action: #selector(stopClicked(_:)))
        startButton = StickerButton(
            title: "Generate", style: .primary, target: self,
            action: #selector(startClicked(_:)))
        view = makeSheetView(
            title: "Generate Captions", hint: nil, content: content,
            buttonRow: makeButtonRow(
                cancel: stopButton, apply: startButton,
                leading: [sheetFootnote("captions go on a new track")]))
        // A key saved or removed while this card is up must not leave a
        // dead Generate button behind it.
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged(_:)),
            name: SettingsWindowController.didChangeNotification, object: nil)
        applyEngine()
        refresh()
    }

    // MARK: - Settings

    @objc func controlChanged(_ sender: Any?) {
        refresh()
    }

    /// The Engine popup: remember the choice, re-populate Language, show or
    /// hide the three cloud rows, change the hint, and recompute.
    @objc private func engineChanged(_ sender: Any?) {
        defaults.set(engine.rawValue, forKey: TranscriptionEngine.defaultsKey)
        populateLanguages()
        applyEngine()
        refresh()
    }

    /// A key or a REGION changed in the Settings window while this card is
    /// open. The hint names the jurisdiction and `beginCloud` resolves the
    /// base URL from that same setting at click time, so the sentence is
    /// rewritten here as well as the readout — `applyEngine` is idempotent
    /// (05-review's finding 2).
    @objc private func settingsChanged(_ note: Notification) {
        applyEngine()
        refresh()
    }

    /// The rows and the sentence that belong to the chosen engine. Called
    /// from `loadView`, from `engineChanged` and from `settingsChanged`, and
    /// from nowhere else: the grid's shape is not something a readout
    /// recomputes.
    func applyEngine() {
        let cloud = engine == .assemblyai
        for index in Self.cloudRows where grid.numberOfRows > index {
            grid.row(at: index).isHidden = !cloud
        }
        hintLabel.stringValue = Self.hint(
            for: engine, region: AssemblyAIConfiguration.region(defaults: defaults))
    }

    /// Everything the settings state shows, recomputed from the controls —
    /// there is no other way for the readout and the button to get out of
    /// step with each other.
    func refresh() {
        defer { refreshStyleRow(); refreshDownloadRow() }
        guard engine == .apple else {
            refreshCloud()
            return
        }
        let jobs = jobs(in: scope)
        let seconds = jobs.reduce(0) { $0 + $1.sourceLength }
        summaryLabel.stringValue = jobs.isEmpty
            ? "Nothing to transcribe"
            : "\(jobs.count) clip\(jobs.count == 1 ? "" : "s") · "
                + ReelTime.format(seconds, fps: snapshot.canvas.fps, frames: false)
                + " of audio"
        // The cloud arm hangs its reasons — file names, a price, AssemblyAI's
        // dated rate — off this same label. They are not true of an on-device
        // run, so going back to this engine takes them down (05-review's
        // finding 1).
        summaryLabel.toolTip = nil
        let note = noteText(jobs: jobs)
        noteLabel.stringValue = note
        noteLabel.isHidden = note.isEmpty
        startButton?.isEnabled = !jobs.isEmpty && language?.installed == true
    }

    private func noteText(jobs: [Transcriber.Job]) -> String {
        guard engine == .apple else { return cloudNoteText(jobs: jobs) }
        var notes: [String] = []
        if languages.isEmpty {
            notes.append(
                "This Mac's speech engine named no language with an on-device speech model. "
                    + "Reopen this sheet to ask it again.")
        }
        if jobs.isEmpty {
            notes.append(
                "Only a clip whose media has sound can be transcribed, and never one played in "
                    + "reverse.")
        }
        return notes.joined(separator: " ")
    }

    // MARK: - Buttons

    /// Cancel while it runs, Close once it is over.
    @objc private func stopClicked(_ sender: Any?) {
        guard didStart else {
            dismiss(self)
            return
        }
        guard !didFinish else {
            dismiss(self)
            return
        }
        stopButton.isEnabled = false
        detailLabel.stringValue = "Stopping…"
        token.cancel()
    }

    /// The run, for an installed language only.
    @objc func startClicked(_ sender: Any?) {
        guard engine == .apple else {
            // Nothing below this line is read for the cloud engine: no
            // on-device model, no `language`.
            guard !didStart, !jobs(in: scope).isEmpty, runRequest().options != nil else {
                NSSound.beep()
                return
            }
            beginCloud()
            return
        }
        guard !didStart, downloading == nil, let language = language, language.installed,
            !jobs(in: scope).isEmpty
        else {
            NSSound.beep()
            return
        }
        begin(language: language)
    }

    private func begin(language: Transcriber.Language) {
        guard !didStart else { return }
        didStart = true
        let jobs = self.jobs(in: scope)
        showProgress()
        statusLabel.stringValue =
            "Transcribing \(jobs.count) clip\(jobs.count == 1 ? "" : "s")…"
        transcriber.run(
            jobs: jobs, language: language,
            frame: max(snapshot.canvas.fps.frameDuration, 1), pages: pagesRequest, cancel: token,
            progress: { [weak self] fraction, name in
                // The run's own queue: every UI touch hops, the way
                // `ConsolidateProgressSheetController` bounces its.
                DispatchQueue.main.async { self?.progressed(fraction, name) }
            },
            completion: { [weak self] outcome in self?.finish(outcome) })
    }

    /// Swaps the card. The settings are gone rather than disabled: a run that
    /// has begun cannot take a different language, and a greyed grid invites
    /// a click that can do nothing.
    func showProgress() {
        settingsStack.isHidden = true
        progressStack.isHidden = false
        hideReturnTarget(startButton)
    }

    func progressed(_ fraction: Double, _ name: String) {
        guard !didFinish else { return }
        bar.doubleValue = min(max(fraction, 0), 1)
        detailLabel.stringValue = name
    }
}

// MARK: - The Vocabulary field

/// The one thing on this card a person TYPES into, so the readout has to move
/// with the keystroke rather than with the commit — `MediaPane`'s search
/// field's rule. The facts are cached per media, so this costs no disk read.
extension TranscribeSheetController: NSTextFieldDelegate {
    func controlTextDidChange(_ note: Notification) {
        refresh()
    }
}
