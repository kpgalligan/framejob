import AppKit

/// Clip ▸ Remove Silences… — road map 2 phase 3a's dialog: five controls
/// (Judge by, the threshold, Longer than, Keep at ends, In), a live count of
/// what they would cut, the same spans washed onto the timeline behind the
/// sheet, and one `ripple_delete_ranges` op when Remove is pressed.
///
/// **Everything it measures is read once, in `init`.** `SilenceDetector.Input`
/// is the snapshot, the composition plan, the selection and every peaks file
/// the timeline's media has, taken off the document in one pass. That is safe
/// because the document cannot change under an open sheet — every editor
/// action validates false while one is attached
/// (`EditorViewController.validateUserInterfaceItem`) — and it is what lets
/// `refresh()` run SYNCHRONOUSLY on every slider tick: after the first read
/// a detection is arithmetic over a few thousand floats already in memory,
/// with no file, no FFI and no queue in it. A background hop would buy
/// nothing and would make the commit off-event, which drags
/// `performGroupedEdit` and a staleness check in behind it.
///
/// The one thing that CAN change under the sheet is the peaks cache: it is
/// written by the fire-and-forget task `ProjectDocument.generateCaches()`
/// starts, so a project opened seconds ago may still be analysing. Media in
/// that state is never proposed for removal (the detector treats a missing
/// cache as "never quiet", because proposing to delete a whole clip because
/// its waveform has not landed is the one failure this feature must not
/// have), the readout says so, and `.mediaCacheDidChange` re-reads the input
/// and recomputes as each file lands — the same notification `MediaPane` and
/// `TimelineView` already watch.
final class SilenceSheetController: NSViewController, NSTextFieldDelegate {
    /// Weak, like every sheet's back-reference: the document must be free to
    /// close even with a dialog mid-air.
    private weak var document: ProjectDocument?
    /// Weak too, and held only to reach `timeline` — the candidate wash is
    /// the sheet's own view state, so the sheet sets it and the sheet clears
    /// it. Nothing else does: `TimelineView.update(...)` does not carry it.
    private weak var editor: EditorViewController?

    /// Everything a detection reads, taken off the document once (and again
    /// when a peaks file lands). `var` for that second reason only.
    private var input: SilenceDetector.Input
    /// The settings the controls open at — the published defaults, over the
    /// scope the input picked for itself.
    private let initialSettings: SilenceDetector.Settings
    /// What the controls currently describe. The Remove button sends exactly
    /// these spans, so the readout and the edit cannot disagree.
    private var outcome: SilenceDetector.Outcome

    private let modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let thresholdSlider = NSSlider()
    private let thresholdReadout = NSTextField(labelWithString: "")
    private let thresholdLabel = NSTextField(labelWithString: "")
    private let minimumField = NSTextField(string: "")
    private let paddingField = NSTextField(string: "")
    private let scopePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let summaryLabel = NSTextField(labelWithString: "")
    private let noteLabel = NSTextField(wrappingLabelWithString: "")

    /// The popup's rows, in order.
    private static let modes: [SilenceDetector.Mode] = [.voice, .level]
    /// Set in `loadView`; the only implicitly-unwrapped optional here, which
    /// is what app/CLAUDE.md allows them for.
    private var applyButton: NSButton!

    /// The popup's rows, in order. A chooser, not a pull-down, so the current
    /// scope is what the button shows.
    private static let scopes: [SilenceDetector.Scope] = [.selected, .audible]

    init(document: ProjectDocument, editor: EditorViewController, input: SilenceDetector.Input) {
        self.document = document
        self.editor = editor
        self.input = input
        let settings = SilenceDetector.Settings(
            scope: input.defaultScope, mode: input.voiceAvailable ? .voice : .level)
        self.initialSettings = settings
        self.outcome = SilenceDetector.detect(input, settings: settings)
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(cacheChanged(_:)), name: .mediaCacheDidChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SilenceSheetController does not support NSCoder")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - View

    override func loadView() {
        for mode in Self.modes { modePopup.addItem(withTitle: mode.displayName) }
        // `autoenablesItems` off FIRST: a popup's menu validates its own
        // rows and would put a disabled one straight back on otherwise.
        modePopup.menu?.autoenablesItems = false
        if !input.voiceAvailable, let item = modePopup.item(at: 0) {
            item.isEnabled = false
        }
        modePopup.selectItem(at: Self.modes.firstIndex(of: initialSettings.mode) ?? 1)
        modePopup.font = DS.sans(13)
        modePopup.target = self
        modePopup.action = #selector(controlChanged(_:))
        modePopup.widthAnchor.constraint(equalToConstant: 168).isActive = true

        thresholdSlider.minValue = SilenceDetector.Settings.thresholdRange.lowerBound
        thresholdSlider.maxValue = SilenceDetector.Settings.thresholdRange.upperBound
        thresholdSlider.doubleValue = initialSettings.thresholdDB
        thresholdSlider.isContinuous = true
        thresholdSlider.controlSize = .small
        thresholdSlider.target = self
        thresholdSlider.action = #selector(controlChanged(_:))
        thresholdSlider.widthAnchor.constraint(equalToConstant: 168).isActive = true

        thresholdLabel.font = DS.sans(13)
        thresholdLabel.textColor = DS.textStrong

        thresholdReadout.font = DS.mono(11)
        thresholdReadout.textColor = DS.textMuted
        thresholdReadout.alignment = .left
        thresholdReadout.widthAnchor.constraint(equalToConstant: 64).isActive = true

        style(minimumField, range: SilenceDetector.Settings.minLengthRange)
        minimumField.doubleValue = ReelTime.seconds(initialSettings.minLength)
        style(paddingField, range: SilenceDetector.Settings.paddingRange)
        paddingField.doubleValue = ReelTime.seconds(initialSettings.padding)

        for scope in Self.scopes {
            scopePopup.addItem(withTitle: scope.displayName)
        }
        // Offering *Selected clips* when nothing selected makes a sound would
        // be offering a run that can only answer "nothing to analyse".
        // `autoenablesItems` off first: a popup's menu validates its own rows
        // by default and would put the item straight back on.
        scopePopup.menu?.autoenablesItems = false
        if input.defaultScope != .selected, let item = scopePopup.item(at: 0) {
            item.isEnabled = false
        }
        scopePopup.selectItem(at: Self.scopes.firstIndex(of: initialSettings.scope) ?? 1)
        scopePopup.font = DS.sans(13)
        scopePopup.target = self
        scopePopup.action = #selector(controlChanged(_:))
        scopePopup.widthAnchor.constraint(equalToConstant: 168).isActive = true

        summaryLabel.font = DS.mono(11)
        summaryLabel.textColor = DS.textMuted
        noteLabel.font = DS.sans(11)
        noteLabel.textColor = DS.textFaint
        noteLabel.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2

        let thresholdRow = sheetRow([thresholdSlider, thresholdReadout])
        let minimumRow = sheetRow([minimumField, sheetUnitLabel("seconds")])
        let paddingRow = sheetRow([paddingField, sheetUnitLabel("seconds")])

        let grid = makeSheetGrid([
            [fieldLabel("Judge by:"), modePopup],
            [thresholdLabel, thresholdRow],
            [fieldLabel("Longer than:"), minimumRow],
            [fieldLabel("Keep at ends:"), paddingRow],
            [fieldLabel("In:"), scopePopup],
        ])

        let content = sheetColumn([grid, summaryLabel, noteLabel])

        let cancelButton = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        applyButton = StickerButton(
            title: "Remove", style: .primary, target: self, action: #selector(applyClicked(_:)))
        view = makeSheetView(
            title: "Remove Silences",
            hint: "The quiet spans are cut and the timeline closes over them, as one edit. "
                + "Quiet is measured IN THE MIX, so a clip you have turned down, faded or "
                + "ducked never holds a cut up — and a span with nothing audible over it, a "
                + "gap or a muted clip alike, is left alone. Nothing INSIDE a nest is cut: a "
                + "nest plays from its first frame, so a cut into one would strand the rest "
                + "of it.",
            content: content,
            buttonRow: makeButtonRow(
                cancel: cancelButton, apply: applyButton,
                leading: [sheetFootnote("markers keep their place")]))
        refresh()
    }

    /// A field in seconds: the formatter carries the same bounds `Settings`
    /// publishes, so the control refuses what the detector would clamp rather
    /// than accepting a number and quietly meaning another one.
    private func style(_ field: NSTextField, range: ClosedRange<Double>) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.minimum = NSNumber(value: range.lowerBound)
        formatter.maximum = NSNumber(value: range.upperBound)
        field.formatter = formatter
        field.delegate = self
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 72).isActive = true
        DSField.style(field)
    }

    // MARK: - Values

    /// The threshold, in whole dBFS. Rounded here rather than left as the
    /// slider's continuous position so the readout and the detection are the
    /// same number: a slider that reads "−40 dBFS" while measuring −40.37 is
    /// a dialog that lies about what it did.
    private var thresholdDB: Double {
        let value = thresholdSlider.doubleValue.rounded()
        return min(
            max(value, SilenceDetector.Settings.thresholdRange.lowerBound),
            SilenceDetector.Settings.thresholdRange.upperBound)
    }

    private var minimumSeconds: Double {
        clamp(minimumField.doubleValue, to: SilenceDetector.Settings.minLengthRange)
    }

    private var paddingSeconds: Double {
        clamp(paddingField.doubleValue, to: SilenceDetector.Settings.paddingRange)
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private var scope: SilenceDetector.Scope {
        let index = scopePopup.indexOfSelectedItem
        guard Self.scopes.indices.contains(index) else { return input.defaultScope }
        return Self.scopes[index]
    }

    private var mode: SilenceDetector.Mode {
        let index = modePopup.indexOfSelectedItem
        guard Self.modes.indices.contains(index) else { return initialSettings.mode }
        let picked = Self.modes[index]
        // The Voice row is disabled rather than removed when the model
        // cannot be used, but a stale selection (a popup rebuilt under one)
        // must still fall back honestly.
        return picked == .voice && !input.voiceAvailable ? .level : picked
    }

    private var settings: SilenceDetector.Settings {
        SilenceDetector.Settings(
            thresholdDB: thresholdDB,
            minLength: ReelTime.ticks(seconds: minimumSeconds),
            padding: ReelTime.ticks(seconds: paddingSeconds),
            scope: scope, mode: mode)
    }

    // MARK: - Detection

    /// Re-detect from the controls and republish everything that follows from
    /// it: the readout, the Remove button and the timeline's wash. Called
    /// from `loadView` and from every control action — there is no other way
    /// for the three to get out of step with each other.
    private func refresh() {
        outcome = SilenceDetector.detect(input, settings: settings)
        thresholdReadout.stringValue = String(format: "%.0f dBFS", thresholdDB)
        // The floor keeps the hint (:153–158) true in either mode: a level
        // is still what a clip with no voice, or every clip when the model
        // cannot be used, is judged by.
        thresholdLabel.stringValue =
            outcome.mode == .voice ? "Level if no voice:" : "Quieter than:"
        summaryLabel.stringValue = summaryText()
        let note = noteText()
        noteLabel.stringValue = note
        noteLabel.isHidden = note.isEmpty
        applyButton?.isEnabled = !outcome.isEmpty
        editor?.timeline?.candidateSpans = outcome.spans
    }

    /// "23 cuts · removes 00:00:04:12", in the app's one spelling of a time
    /// (`ReelTime.format`, the core's own formatter) rather than a second
    /// one invented here — `SpeedSheetController`'s readout does the same
    /// with the lengths it predicts.
    private func summaryText() -> String {
        guard !outcome.isEmpty else { return "No cuts" }
        let cuts = outcome.spans.count == 1 ? "1 cut" : "\(outcome.spans.count) cuts"
        let removed = ReelTime.format(
            outcome.removed, fps: input.snapshot.canvas.fps, frames: true)
        return cuts + " · removes " + removed
    }

    /// The second line, when there is something the count alone would hide.
    /// All three readings below can come out as "0 cuts" and none of them
    /// means "there is no dead air here", which is why they are spelled out
    /// — and they are JOINED rather than answered first-match, because a
    /// project can easily be two of them at once.
    private func noteText() -> String {
        var notes: [String] = []
        if outcome.clips.isEmpty {
            notes.append(
                outcome.scope == .selected
                    ? "Nothing the selected clips play is audible in the mix, so nothing "
                        + "was analysed."
                    : "Nothing in this timeline is audible, so nothing was analysed.")
        } else if !outcome.pendingMedia.isEmpty {
            // Named rather than counted: which file is still being analysed
            // is what tells the user whether to wait or to go ahead, and the
            // sheet re-runs by itself the moment one lands.
            let names = outcome.pendingMedia.compactMap { input.snapshot.media($0)?.name }
            let listed = names.isEmpty
                ? (outcome.pendingMedia.count == 1
                    ? "one file" : "\(outcome.pendingMedia.count) files")
                : names.joined(separator: ", ")
            // The promise is the LEVEL rule's: a media with no peaks is never
            // quiet there. In voice mode the model has landed and spans
            // inside the file are proposed — only a clip it found no voice in
            // waits for the waveform (the reader review, road map 4 §8, R3·1).
            notes.append(
                outcome.mode == .level
                    ? "The waveform is still being analysed for \(listed). "
                        + promise(about: outcome.pendingMedia)
                    : "The waveform is still being analysed for \(listed). "
                        + waveformPromise())
        }
        if !input.voiceAvailable {
            notes.append(
                "The voice model could not be used, so quiet is judged by level.")
        }
        if !outcome.voicePending.isEmpty {
            let names = outcome.voicePending.compactMap { input.snapshot.media($0)?.name }
            let listed = names.isEmpty
                ? (outcome.voicePending.count == 1
                    ? "one file" : "\(outcome.voicePending.count) files")
                : names.joined(separator: ", ")
            notes.append(
                "Speech is still being analysed for \(listed). "
                    + promise(about: outcome.voicePending))
        }
        // Named by CLIP (#107): two clips of one file can be judged
        // differently, so the file's name alone would not say which.
        let byLevel = SilenceDetector.VoiceAnswer.labels(
            outcome.answers.filter { $0.judgedByLevel }, in: input.snapshot)
        if byLevel.count == 1 {
            notes.append("\(byLevel[0]) holds no voice and is judged by level.")
        } else if byLevel.count > 1 {
            notes.append(
                "\(byLevel.count) clips hold no voice and are judged by level: "
                    + byLevel.joined(separator: ", ") + ".")
        }
        if !outcome.protectedNests.isEmpty {
            // The detector will not propose a span that reaches into a nest
            // (`SilenceDetector`'s doc says why), so a nested screencast
            // finds fewer cuts than its waveform looks like it holds. Left
            // unsaid, that reads as "there is no dead air here".
            let count = outcome.protectedNests.count
            let subject = count == 1 ? "a nest" : "\(count) nests"
            notes.append(
                "Quiet inside \(subject) is left alone: a nest plays from its first frame, "
                    + "so cutting into one would strand the rest of it. Open the nest (⌘↓) "
                    + "and remove its silences there to take the dead air out.")
        }
        return notes.joined(separator: " ")
    }

    /// The "nothing inside is proposed" line, made about what the ANSWER
    /// shows rather than about the mode: the gain FLOOR is asked before
    /// either cache (`SilenceDetector.isQuiet`), so a clip the mix has turned
    /// down, faded, ducked or muted is quiet with nothing on disk at all and
    /// its spans are in the readout above this line (the reader review, road
    /// map 4 §8, finding 2). The tool's twin says the same in
    /// `AgentServer+Silence`. Since #107 it names the clips it is about.
    private func promise(about pending: [UInt32]) -> String {
        let labels = SilenceDetector.VoiceAnswer.labels(
            outcome.mixAnswers(inside: Set(pending)), in: input.snapshot)
        guard !labels.isEmpty else { return "Nothing inside is proposed for removal yet." }
        return "What is proposed inside \(labels.joined(separator: ", ")) is quiet in the MIX "
            + "— turned down, faded or ducked — which neither cache can change."
    }

    /// The VOICE-mode waveform line's own promise, which is narrower than
    /// `promise(about:)` above and cannot borrow it (the reader review's
    /// second sceptic pass, road map 4 §8). In voice mode the model has
    /// landed for most of what is on screen, so a media whose waveform is
    /// late still has spans proposed inside it BY THE MODEL — `promise` would
    /// then answer "quiet in the MIX", which is false about a clip nothing
    /// has turned down. What is true is an EXCEPTION, named by clip (#107):
    /// the clips of those media whose own answer is proposed while the cache
    /// their quiet test reads is missing (`Outcome.mixAnswers`) — a clip that
    /// holds no voice waiting on this waveform, or one whose speech cache has
    /// not landed either (`SilenceDetector.detect` returns on a missing
    /// speech cache BEFORE the by-level test, so such a clip is waiting on
    /// its speech). Only the FLOOR can propose inside a waiting clip, so what
    /// it names is what the mix made quiet, and a clip of the same file the
    /// mix left alone is not named.
    private func waveformPromise() -> String {
        let plain = "Anything inside it that holds no voice is left alone until it lands"
        let labels = SilenceDetector.VoiceAnswer.labels(
            outcome.mixAnswers(inside: Set(outcome.pendingMedia)), in: input.snapshot)
        guard !labels.isEmpty else { return plain + "." }
        return plain + ", except where the mix already turns "
            + labels.joined(separator: ", ") + " down far enough to be quiet."
    }

    // MARK: - Controls

    @objc private func controlChanged(_ sender: Any?) {
        refresh()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Write the clamped value back, so a number the formatter let through
        // but `Settings` bounds does not stay on screen as if it had been
        // taken.
        minimumField.doubleValue = minimumSeconds
        paddingField.doubleValue = paddingSeconds
        refresh()
    }

    /// A peaks or speech file landed, or was WITHDRAWN. Re-read the input —
    /// that is the only way to pick the new floats up, since `Input` holds
    /// them by value — and recompute.
    ///
    /// It re-reads whether or not anything is PENDING. It used to stop unless
    /// `pendingMedia` or `pendingSpeech` held something, and the post that
    /// matters most arrives when neither does: a relink driven from the agent
    /// while this sheet is up withdraws the old `.bin` FIRST, so the sheet
    /// went on showing spans measured from a file the project no longer uses
    /// until something else woke it (the reader review, road map 4 §8, R2·2 —
    /// the limit `archive/remaining.md` §5 recorded as unprovable, on
    /// the belief that no proof could drive this sheet; `silence2_probe.py`'s
    /// claim 17 does). The media id is not checked against the scope: a file
    /// this project does not use posts nothing, and a re-read costs one pass
    /// over caches that are already in the page cache.
    @objc private func cacheChanged(_ note: Notification) {
        let kind = note.userInfo?[MediaImporter.cacheKindKey] as? String
        guard kind == MediaImporter.peaksKind || kind == MediaImporter.speechKind,
              let document = document,
              let reread = SilenceDetector.read(from: document)
        else { return }
        input = reread
        refresh()
    }

    // MARK: - Commit

    @objc private func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    /// ONE `ripple_delete_ranges` for however many spans — one op, one undo
    /// step, and the core's own merge-then-cut-right-to-left rule rather than
    /// N ripples sent in a row (which would each shift the ones after it).
    ///
    /// Nothing is sent when there is nothing to cut: `applyEdit` answers the
    /// core's identity with a beep, and a beep at a dialog the user has just
    /// confirmed reads as a refusal rather than as "nothing to do". The
    /// button is disabled for the same reason, and AppKit skips a disabled
    /// button when it looks for the Return key's target, so the guard below
    /// should be unreachable — it costs one comparison to be sure.
    @objc private func applyClicked(_ sender: Any?) {
        // A click on a button does not take the first responder from a text
        // field, so a just-typed length has not been committed yet. Ending
        // editing runs `controlTextDidEndEditing`, which re-detects; the
        // spans are therefore read AFTER it.
        guard endSheetFieldEditing() else { return }
        let spans = outcome.spans
        let document = self.document
        dismiss(self)
        guard let document = document, !spans.isEmpty else { return }
        document.applyEdit(
            "Remove Silences",
            [.rippleDeleteRanges(ranges: spans.map { (from: $0.start, to: $0.end) })])
    }

    /// The one teardown point: it fires for Remove, for Cancel, for Escape
    /// and for a window closing under the sheet alike. Nothing else clears
    /// the wash — the spans are not part of `TimelineView.update(...)`, so
    /// leaving them set would paint a permanent tint over a timeline whose
    /// clips have since moved.
    override func viewDidDisappear() {
        super.viewDidDisappear()
        editor?.timeline?.candidateSpans = []
    }
}

// MARK: - The menu command

/// The command half, at the foot of the file that owns the feature —
/// `CaptionImporter.swift`'s precedent, which keeps File ▸ Import Captions…
/// beside the importer it opens rather than in a file of its own.
extension EditorViewController {

    /// Clip ▸ Remove Silences… — the body of the frozen file's one-line
    /// `@objc func removeSilences(_:)` forward.
    ///
    /// The detector's input is read HERE rather than in the sheet's `init`,
    /// so the two honest refusals happen before a dialog goes up: a plan this
    /// build cannot read, and a timeline with no sound in it at all. A sheet
    /// whose only possible answer is "nothing to analyse" should not open.
    func removeSilencesCommand() {
        guard let document = document, view.window?.attachedSheet == nil else {
            NSSound.beep()
            return
        }
        guard let input = SilenceDetector.read(from: document), input.hasAudio else {
            NSSound.beep()
            return
        }
        // The wash the sheet puts on the lanes is read while it is up, and a
        // running playhead repaints over it several times a second.
        playback.pause()
        presentAsSheet(SilenceSheetController(document: document, editor: self, input: input))
    }

    /// The half of `validateUserInterfaceItem` this file owns. nil means "not
    /// mine" and leaves the other answers alone.
    func validateSilenceAction(_ action: Selector) -> Bool? {
        guard let document = document else { return false }
        switch action {
        case #selector(EditorViewController.removeSilences(_:)):
            // The honest test is the PLAN — it is what the detector reads —
            // but `ReelProject.plan` decodes JSON on every access and a
            // validator runs on every menu open. This is the same question
            // asked of the snapshot, which is memoized: it is deliberately
            // the body of `TimelineView.hasAudio`, and it is copied rather
            // than shared because that one lives on a VIEW and a controller
            // reaching into the timeline for a model question is the wrong
            // direction. The sheet's own guard is the exact answer.
            let snapshot = document.editedProject.snapshot
            return snapshot.clips.contains { clip in
                guard clip.enabled.audio else { return false }
                if case .nest = clip.source { return clip.audio != nil }
                return snapshot.media(for: clip)?.hasAudio ?? false
            }
        default:
            return nil
        }
    }
}
