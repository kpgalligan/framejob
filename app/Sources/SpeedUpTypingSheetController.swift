import AppKit

/// Clip ▸ Speed Up Typing… (road map "creator-jobs" CU9b, spec §11 CU-93): each typing stretch
/// of the selected clips' cursor files with no speech and no shortcut played at Rate, 0.3 s at
/// ×1 kept at each end, as one undo step "Speed Up Typing". `speed_up_typing`
/// (`AgentServer+SpeedUpTyping.swift`) resolves through the same `SpeedUpTyping.resolve`.
///
/// The sheet opens with the remembered values (`SpeedUpTypingSettings.remembered`), reads the
/// files off the main thread ("Reading cursor files…", Apply disabled), then plans on main at
/// every control change and says what Apply would do, or why it would change nothing, or the
/// refusal. A media with sound under a stretch whose speech has not been detected yet makes the
/// sheet WAIT: it starts the pass once (`ProjectDocument.generateCaches()`, idempotent), plans
/// again on each `speech` cache landing, and gives up after `SpeedUpTyping.waitLimit`. Apply
/// commits the speech ops and the `retime_range` ops through `SpeedAudioDrop.commit` — its
/// question's Cancel leaves the sheet up — and only then writes the keys that changed.
///
/// **The dev accept** (`-RCDevSpeedUpTypingAccept YES`, dev tools only): the sheet presses Apply
/// once its first plan with ops exists, with its controls as set (AU-128's precedent).
final class SpeedUpTypingSheetController: NSViewController, NSTextFieldDelegate {
    /// The dev-only launch default that presses Apply.
    static let devAcceptKey = "RCDevSpeedUpTypingAccept"

    private weak var document: ProjectDocument?
    private let clipIDs: [UInt32]
    private let opened: SpeedUpTypingSettings
    private var tracks: [UInt32: ReelCursor]?
    private var planned: (speechOps: [ReelOp], plan: SpeedUpTypingPlan)?
    private var waitStarted: Date?
    private var passStarted = false
    private var giveUpTimer: Timer?
    private var accepted = false

    private let rateField = NSTextField(string: "")
    private let shortestField = NSTextField(string: "")
    private let pitchBox = NSButton(checkboxWithTitle: "Keep pitch", target: nil, action: nil)
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private var applyButton: NSButton?

    init(document: ProjectDocument, clips: [UInt32]) {
        self.document = document
        self.clipIDs = clips
        self.opened = SpeedUpTypingSettings.remembered(.standard)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SpeedUpTypingSheetController does not support NSCoder")
    }

    deinit {
        giveUpTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - View

    override func loadView() {
        style(rateField, range: SpeedUpTypingSettings.rateRange, value: opened.rate)
        style(shortestField, range: SpeedUpTypingSettings.shortestRange, value: opened.shortest)
        pitchBox.state = opened.keepPitch ? .on : .off
        pitchBox.font = DS.sans(13)
        pitchBox.target = self
        pitchBox.action = #selector(controlChanged(_:))
        summaryLabel.font = DS.sans(12)
        summaryLabel.textColor = DS.textMuted
        summaryLabel.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2
        summaryLabel.stringValue = "Reading cursor files…"
        summaryLabel.setAccessibilityIdentifier("speeduptyping.summary")

        let grid = makeSheetGrid([
            [fieldLabel("Rate:"), sheetRow([rateField, fieldLabel("×")])],
            [fieldLabel("Shortest stretch:"), sheetRow([shortestField, fieldLabel("s")])],
            [NSGridCell.emptyContentView, pitchBox],
        ])
        let cancel = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        let apply = sheetApplyButton(target: self, action: #selector(applyClicked(_:)))
        apply.isEnabled = false
        applyButton = apply
        view = makeSheetView(
            title: "Speed Up Typing",
            hint: "Plays the recording's typing faster where nobody speaks and no shortcut is "
                + "shown, keeping 0.3 s at normal speed at each end. One undo step.",
            content: sheetColumn([grid, summaryLabel]),
            buttonRow: makeButtonRow(cancel: cancel, apply: apply))
        NotificationCenter.default.addObserver(
            self, selector: #selector(cacheChanged(_:)), name: .mediaCacheDidChange, object: nil)
    }

    private func style(_ field: NSTextField, range: ClosedRange<Double>, value: Double) {
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
        field.doubleValue = value
        field.widthAnchor.constraint(equalToConstant: 64).isActive = true
        DSField.style(field)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard tracks == nil, let document else { return }
        let snapshot = document.editedProject.snapshot
        let clips = clipIDs.compactMap { snapshot.clip($0) }
        let files: [UInt32: URL]
        do {
            files = try AutoZoom.cursorFiles(clips, in: snapshot)
        } catch {
            summaryLabel.stringValue = error.localizedDescription
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let read = Result { try AutoZoom.readTracks(files) }
            DispatchQueue.main.async { self?.didRead(read) }
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        giveUpTimer?.invalidate()
        giveUpTimer = nil
    }

    private func didRead(_ read: Result<[UInt32: ReelCursor], Error>) {
        switch read {
        case .failure(let error):
            summaryLabel.stringValue = error.localizedDescription
        case .success(let tracks):
            self.tracks = tracks
            replan()
        }
    }

    // MARK: - Values

    /// What the controls say, each number inside its range.
    private var settings: SpeedUpTypingSettings {
        func clamped(_ field: NSTextField, _ range: ClosedRange<Double>) -> Double {
            min(max(field.doubleValue, range.lowerBound), range.upperBound)
        }
        var s = SpeedUpTypingSettings()
        s.rate = clamped(rateField, SpeedUpTypingSettings.rateRange)
        s.shortest = clamped(shortestField, SpeedUpTypingSettings.shortestRange)
        s.keepPitch = pitchBox.state == .on
        return s
    }

    /// Plans again on main and says what Apply would do, or what the sheet waits for.
    private func replan() {
        guard let document, let tracks else { return }
        let snapshot = document.editedProject.snapshot
        let clips = clipIDs.compactMap { snapshot.clip($0) }
        let settings = self.settings
        do {
            switch try SpeedUpTyping.resolve(
                clips, tracks: tracks, project: document.editedProject,
                cacheDirectory: document.cacheDirectory, settings: settings, from: nil, to: nil)
            {
            case .planned(let speechOps, let plan):
                stopWaiting()
                planned = (speechOps, plan)
                summaryLabel.stringValue = SpeedUpTyping.summary(plan, settings: settings)
                applyButton?.isEnabled = !plan.ops.isEmpty
                #if FRAMEJOB_DEV_TOOLS
                if !plan.ops.isEmpty, !accepted,
                    UserDefaults.standard.bool(forKey: Self.devAcceptKey)
                {
                    accepted = true
                    DispatchQueue.main.async { [weak self] in self?.applyClicked(nil) }
                }
                #endif
            case .waiting(let names):
                planned = nil
                applyButton?.isEnabled = false
                wait(for: names, in: document)
            }
        } catch {
            stopWaiting()
            planned = nil
            summaryLabel.stringValue = error.localizedDescription
            applyButton?.isEnabled = false
        }
    }

    /// The wait for speech detection (CU-93): the pass started once per sheet, bounded at
    /// `SpeedUpTyping.waitLimit`, after which the sheet stops waiting.
    private func wait(for names: [String], in document: ProjectDocument) {
        let listed = names.joined(separator: ", ")
        if waitStarted == nil {
            waitStarted = Date()
            if !passStarted {
                passStarted = true
                document.generateCaches()
            }
            giveUpTimer = Timer.scheduledTimer(
                withTimeInterval: SpeedUpTyping.waitLimit, repeats: false
            ) { [weak self] _ in self?.replan() }
        }
        let elapsed = Date().timeIntervalSince(waitStarted ?? Date())
        if SpeedUpTyping.gaveUp(waitingFor: elapsed) {
            giveUpTimer?.invalidate()
            giveUpTimer = nil
            summaryLabel.stringValue = "Speech detection has not finished for \(listed). "
                + "Close this sheet and try again."
        } else {
            summaryLabel.stringValue = "Waiting for speech detection on \(listed)…"
        }
    }

    private func stopWaiting() {
        waitStarted = nil
        giveUpTimer?.invalidate()
        giveUpTimer = nil
    }

    /// A speech cache landed: plan again while waiting and not yet given up.
    @objc private func cacheChanged(_ note: Notification) {
        guard note.userInfo?[MediaImporter.cacheKindKey] as? String == MediaImporter.speechKind,
            let started = waitStarted,
            !SpeedUpTyping.gaveUp(waitingFor: Date().timeIntervalSince(started))
        else { return }
        replan()
    }

    // MARK: - Controls

    @objc private func controlChanged(_ sender: Any?) {
        replan()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let range =
            field === rateField
            ? SpeedUpTypingSettings.rateRange : SpeedUpTypingSettings.shortestRange
        field.doubleValue = min(max(field.doubleValue, range.lowerBound), range.upperBound)
        replan()
    }

    // MARK: - Commit

    @objc private func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    @objc private func applyClicked(_ sender: Any?) {
        replan()
        guard let document, let planned, !planned.plan.ops.isEmpty else { return }
        let (settings, opened) = (self.settings, self.opened)
        SpeedAudioDrop.commit(
            SpeedUpTyping.actionName, planned.speechOps + planned.plan.ops, to: document,
            asking: view.window,
            before: { [weak self] in
                if let self { self.dismiss(self) }
                settings.remember(changedFrom: opened, in: .standard)
            })
    }
}
