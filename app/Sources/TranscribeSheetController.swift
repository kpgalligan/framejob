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
    private let mediaURLs: [UInt32: URL]
    private let selection: Set<UInt32>
    private let inOutRange: (start: Ticks, end: Ticks)?
    private let languages: [Transcriber.Language]

    private let transcriber = Transcriber()
    let token = Transcriber.CancelToken()

    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let scopePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let summaryLabel = NSTextField(labelWithString: "")
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    let bar = NSProgressIndicator()
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    let detailLabel = NSTextField(labelWithString: "")
    /// Set in `loadView`; the only implicitly-unwrapped optionals here, which
    /// is what app/CLAUDE.md allows them for.
    private var settingsStack: NSStackView!
    private var progressStack: NSStackView!
    var stopButton: NSButton!
    private var startButton: NSButton!

    var didStart = false
    var didFinish = false

    private static let scopes = Scope.allCases

    init(document: ProjectDocument) {
        self.document = document
        // The container the cues will LAND in, not the document — see
        // `CaptionImporter.plan`'s paragraph. A scope cannot change under
        // an open sheet, so capturing it here is as safe as the rest.
        self.snapshot = document.editedProject.snapshot
        self.mediaURLs = document.mediaURLs()
        self.selection = document.selection
        self.inOutRange = document.inOutRange
        self.languages = Transcriber.languages()
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

    private func jobs(in scope: Scope) -> [Transcriber.Job] {
        Transcriber.jobs(for: clips(in: scope), in: snapshot, urls: mediaURLs).jobs
    }

    /// The scope the sheet opens on: what the user pointed at, if it holds
    /// anything transcribable, then the range they marked, then everything.
    private var defaultScope: Scope {
        if !jobs(in: .selection).isEmpty { return .selection }
        if inOutRange != nil, !jobs(in: .range).isEmpty { return .range }
        return .all
    }

    private var scope: Scope {
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
        for language in languages {
            languagePopup.addItem(withTitle: language.displayName)
            // The identifier, not the row's position — see `language`.
            languagePopup.lastItem?.representedObject = language.identifier
        }
        if languages.isEmpty {
            languagePopup.addItem(withTitle: "No on-device language")
            // A popup's menu validates its own rows, so this has to come
            // BEFORE the row is disabled or AppKit puts it straight back on.
            languagePopup.menu?.autoenablesItems = false
            languagePopup.item(at: 0)?.isEnabled = false
            languagePopup.isEnabled = false
        } else if let preferred = Transcriber.defaultLanguage(in: languages),
                  let index = languagePopup.itemArray.firstIndex(where: {
                      $0.representedObject as? String == preferred.identifier
                  }) {
            languagePopup.selectItem(at: index)
        }
        languagePopup.font = DS.sans(13)
        languagePopup.widthAnchor.constraint(equalToConstant: 200).isActive = true

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

        let grid = NSGridView(views: [
            [fieldLabel("Language:"), languagePopup],
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

        let content = NSStackView(views: [settingsStack, progressStack])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 0

        stopButton = sheetCancelButton(target: self, action: #selector(stopClicked(_:)))
        startButton = StickerButton(
            title: "Generate", style: .primary, target: self,
            action: #selector(startClicked(_:)))
        view = makeSheetView(
            title: "Generate Captions",
            hint: "The words are recognised ON THIS MAC and land as ordinary text clips on a "
                + "track of their own, so they show in the preview and burn into an export "
                + "with no further step. Nothing is uploaded.",
            content: content,
            buttonRow: makeButtonRow(
                cancel: stopButton, apply: startButton,
                leading: [sheetFootnote("captions go on a new front track")]))
        refresh()
    }

    // MARK: - Settings

    @objc private func controlChanged(_ sender: Any?) {
        refresh()
    }

    /// Everything the settings state shows, recomputed from the controls —
    /// there is no other way for the readout and the button to get out of
    /// step with each other.
    private func refresh() {
        let jobs = jobs(in: scope)
        let seconds = jobs.reduce(0) { $0 + $1.sourceLength }
        summaryLabel.stringValue = jobs.isEmpty
            ? "Nothing to transcribe"
            : "\(jobs.count) clip\(jobs.count == 1 ? "" : "s") · "
                + ReelTime.format(seconds, fps: snapshot.canvas.fps, frames: false)
                + " of audio"
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
    @objc private func startClicked(_ sender: Any?) {
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
    private func showProgress() {
        settingsStack.isHidden = true
        progressStack.isHidden = false
        // Hidden AND disabled: AppKit skips both when it looks for the Return
        // key's target, so Cancel is the sheet's only live button while it
        // runs.
        startButton.isHidden = true
        startButton.isEnabled = false
    }

    private func progressed(_ fraction: Double, _ name: String) {
        guard !didFinish else { return }
        bar.doubleValue = min(max(fraction, 0), 1)
        detailLabel.stringValue = name
    }
}
