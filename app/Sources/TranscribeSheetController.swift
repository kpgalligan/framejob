import AppKit
import Speech

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
/// **The grant is asked for HERE and nowhere else.**
/// `SFSpeechRecognizer.requestAuthorization` puts up a system prompt that
/// needs a person, and this sheet is the one place in the app where one is
/// known to be present by construction. The `transcribe` tool reads
/// `authorizationStatus()` and refuses instead (`Transcriber.canAsk` carries
/// the argument, which is `FFmpegRewrap.canAsk`'s). Denied and restricted are
/// answered before the button is ever enabled; `notDetermined` is answered by
/// asking, on the click, and the answer either starts the run or turns this
/// into a result card explaining what happened.
///
/// **What it cannot promise.** The recogniser's one-minute ceiling is real
/// and undocumented for the on-device path (`Transcriber`'s doc argues it), so
/// a run that stops early says where it stopped rather than pretending the
/// clip held no more speech.
///
/// **Two engines, one card (road map 6 §5e).** An Engine popup under
/// Language chooses between the recogniser on this Mac and AssemblyAI, and
/// the choice re-populates Language, shows or hides the three cloud rows, and
/// changes the hint. `TranscribeSheetController+Cloud.swift` holds everything
/// that is only about the cloud engine; what is HERE is the card, and three
/// methods — `refresh`, `noteText` and `startClicked` — whose FIRST statement
/// dispatches on the engine. That order is load-bearing: under
/// `.assemblyai` none of the three reads `language`, `languages`, `isBlocked`,
/// `Transcriber.authorizationStatus` or `requestAuthorization`, so a Mac with
/// no on-device model and no Speech grant can still transcribe in the cloud.
/// The `.apple` arms are the code they were, moved under the dispatch.
///
/// **The widenings this split cost**, in toll 3's pattern: `languages`,
/// `mediaURLs`, `languagePopup`, `summaryLabel`, `noteLabel`, `hintLabel`,
/// `scope`, `jobs(in:)`, `startButton`, `showProgress()` and `progressed(_:_:)`
/// are internal rather than private, because `+Cloud.swift` builds the same
/// card out of them. `language` and `isBlocked` stay private: the cloud half
/// must not be able to read either.
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
    let mediaURLs: [UInt32: URL]
    private let selection: Set<UInt32>
    private let inOutRange: (start: Ticks, end: Ticks)?
    let languages: [Transcriber.Language]

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
    /// Set in `loadView`; the only implicitly-unwrapped optionals here, which
    /// is what app/CLAUDE.md allows them for.
    private var settingsStack: NSStackView!
    private var progressStack: NSStackView!
    private var grid: NSGridView!
    var stopButton: NSButton!
    var startButton: NSButton!

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

    var didStart = false
    var didFinish = false

    private static let scopes = Scope.allCases
    /// The grid rows that belong to AssemblyAI alone.
    static let cloudRows = [2, 3, 4]

    init(
        document: ProjectDocument, store: any SecretStore = AssemblyAIConfiguration.store(),
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        languages: [Transcriber.Language] = Transcriber.languages()
    ) {
        self.document = document
        // The container the cues will LAND in, not the document — see
        // `CaptionImporter.plan`'s paragraph. A scope cannot change under
        // an open sheet, so capturing it here is as safe as the rest.
        self.snapshot = document.editedProject.snapshot
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
        Transcriber.jobs(for: clips(in: scope), in: snapshot, urls: mediaURLs).jobs
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
    /// list: `NSPopUpButton.addItem(withTitle:)` REMOVES an existing row with
    /// the same title before adding the new one, and two locales can localize
    /// to one display name, so an index into `languages` can name a different
    /// language than the row the person clicked. `CaptionExporter`'s track
    /// popup carries the same guard for the same reason.
    private var language: Transcriber.Language? {
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
            enginePopup.addItem(withTitle: engine.displayName)
            enginePopup.lastItem?.representedObject = engine.rawValue
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

        speakersCheckbox.title = "start a new caption when the speaker changes"
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

        grid = NSGridView(views: [
            [fieldLabel("Language:"), languagePopup],
            [fieldLabel("Engine:"), enginePopup],
            [fieldLabel("Speakers:"), speakersCheckbox],
            [fieldLabel("Vocabulary:"), vocabularyField],
            [fieldLabel("Transcribe again:"), refreshCheckbox],
            [fieldLabel("From:"), scopePopup],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 106

        settingsStack = NSStackView(views: [grid, summaryLabel, noteLabel])
        settingsStack.orientation = .vertical
        settingsStack.alignment = .leading
        settingsStack.spacing = 10

        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.doubleValue = 0
        bar.usesThreadedAnimation = true
        bar.widthAnchor.constraint(equalToConstant: sheetWidth - sheetInset * 2).isActive = true
        statusLabel.font = DS.sans(12)
        statusLabel.textColor = DS.textMuted
        statusLabel.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2
        detailLabel.font = DS.mono(11)
        detailLabel.textColor = DS.textFaint
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.widthAnchor.constraint(equalToConstant: sheetWidth - sheetInset * 2)
            .isActive = true

        progressStack = NSStackView(views: [bar, statusLabel, detailLabel])
        progressStack.orientation = .vertical
        progressStack.alignment = .leading
        progressStack.spacing = 8
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
                leading: [sheetFootnote("captions go on a new front track")]))
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
    private func refresh() {
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
        startButton?.isEnabled = !jobs.isEmpty && !languages.isEmpty && !isBlocked
    }

    /// True when no click could ever succeed: the grant was refused for good.
    /// `notDetermined` is not blocked — that is the state a click FIXES.
    private var isBlocked: Bool {
        let status = Transcriber.authorizationStatus
        return status == .denied || status == .restricted
    }

    private func noteText(jobs: [Transcriber.Job]) -> String {
        guard engine == .apple else { return cloudNoteText(jobs: jobs) }
        var notes: [String] = []
        if languages.isEmpty {
            notes.append(
                "No language on this Mac has an on-device speech model. Download one in "
                    + "System Settings ▸ Keyboard ▸ Dictation and reopen this sheet.")
        }
        if isBlocked {
            notes.append(
                "Speech Recognition is turned off for Reelcut (status: "
                    + "\(Transcriber.name(of: Transcriber.authorizationStatus))). Turn it on in "
                    + "System Settings ▸ Privacy & Security ▸ Speech Recognition.")
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

    /// The grant, then the run. `requestAuthorization` only ever happens on
    /// this path, and only from `.notDetermined`.
    @objc func startClicked(_ sender: Any?) {
        guard engine == .apple else {
            // Nothing below this line is read for the cloud engine: no
            // grant, no on-device model, no `language`.
            guard !didStart, !jobs(in: scope).isEmpty, runRequest().options != nil else {
                NSSound.beep()
                return
            }
            beginCloud()
            return
        }
        guard !didStart, let language = language, !jobs(in: scope).isEmpty else {
            NSSound.beep()
            return
        }
        guard Transcriber.authorizationStatus == .notDetermined else {
            begin(language: language)
            return
        }
        startButton.isEnabled = false
        Transcriber.requestAuthorization { [weak self] _ in
            guard let self = self else { return }
            self.startButton.isEnabled = true
            self.begin(language: language)
        }
    }

    private func begin(language: Transcriber.Language) {
        guard !didStart else { return }
        guard Transcriber.isAuthorized else {
            didStart = true
            showProgress()
            finish(.failure(Transcriber.authorizationRefusal))
            return
        }
        didStart = true
        let jobs = self.jobs(in: scope)
        showProgress()
        statusLabel.stringValue =
            "Transcribing \(jobs.count) clip\(jobs.count == 1 ? "" : "s")…"
        transcriber.run(
            jobs: jobs, language: language,
            frame: max(snapshot.canvas.fps.frameDuration, 1), cancel: token,
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
        // Hidden AND disabled: AppKit skips both when it looks for the Return
        // key's target, so Cancel is the sheet's only live button while it
        // runs.
        startButton.isHidden = true
        startButton.isEnabled = false
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
