import AppKit

/// Clip ▸ Auto Zoom… (road map "creator-jobs" CU7, spec §11 CU-76): zooms planned from the
/// selected clips' cursor files — Zoom, Arrive before the click, Stay after the last activity,
/// Follow the cursor while zoomed, Zoom on typing, Replace existing zooms — applied as one undo
/// step "Auto Zoom". `auto_zoom` (`AgentServer+AutoZoom.swift`) plans through the same
/// `AutoZoom.plan`.
///
/// The sheet opens with the remembered values (`AutoZoomSettings.remembered`), reads the files
/// off the main thread ("Reading cursor files…", Zoom disabled), then plans on main at every
/// control change and says what it would do, or the refusal. Zoom applies the plan, then writes
/// only the keys whose value changed. Zoom on typing is on, and enabled, only when a file has
/// typing stretches, and is never remembered.
///
/// **The dev accept** (`-RCDevAutoZoomAccept YES`, dev tools only): the sheet presses Zoom once
/// its first plan exists, with its controls as set (AU-128's precedent).
final class AutoZoomSheetController: NSViewController, NSTextFieldDelegate {
    /// The dev-only launch default that presses Zoom.
    static let devAcceptKey = "RCDevAutoZoomAccept"

    private weak var document: ProjectDocument?
    private let clipIDs: [UInt32]
    private let opened: AutoZoomSettings
    private var tracks: [UInt32: ReelCursor]?
    private var plan: AutoZoomPlan?
    private var accepted = false

    private let zoomField = NSTextField(string: "")
    private let leadField = NSTextField(string: "")
    private let stayField = NSTextField(string: "")
    private let followBox = NSButton(
        checkboxWithTitle: "Follow the cursor while zoomed", target: nil, action: nil)
    private let typingBox = NSButton(
        checkboxWithTitle: "Zoom on typing", target: nil, action: nil)
    private let replaceBox = NSButton(
        checkboxWithTitle: "Replace existing zooms", target: nil, action: nil)
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private var zoomButton: NSButton?

    init(document: ProjectDocument, clips: [UInt32]) {
        self.document = document
        self.clipIDs = clips
        self.opened = AutoZoomSettings.remembered(.standard)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AutoZoomSheetController does not support NSCoder")
    }

    // MARK: - View

    override func loadView() {
        style(zoomField, range: AutoZoomSettings.zoomRange, value: opened.zoom)
        style(leadField, range: AutoZoomSettings.leadRange, value: opened.lead)
        style(stayField, range: AutoZoomSettings.stayRange, value: opened.stay)
        for (box, on) in [(followBox, opened.follow), (typingBox, false), (replaceBox, opened.replace)] {
            box.state = on ? .on : .off
            box.font = DS.sans(13)
            box.target = self
            box.action = #selector(controlChanged(_:))
        }
        typingBox.isEnabled = false
        summaryLabel.font = DS.sans(12)
        summaryLabel.textColor = DS.textMuted
        summaryLabel.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2
        summaryLabel.stringValue = "Reading cursor files…"
        summaryLabel.setAccessibilityIdentifier("autozoom.summary")

        let grid = makeSheetGrid([
            [fieldLabel("Zoom:"), sheetRow([zoomField, fieldLabel("×")])],
            [fieldLabel("Arrive:"), sheetRow([leadField, fieldLabel("s before the click")])],
            [fieldLabel("Stay:"), sheetRow([stayField, fieldLabel("s after the last activity")])],
            [NSGridCell.emptyContentView, followBox],
            [NSGridCell.emptyContentView, typingBox],
            [NSGridCell.emptyContentView, replaceBox],
        ])
        let cancel = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        let zoom = StickerButton(
            title: "Zoom", style: .primary, target: self, action: #selector(zoomClicked(_:)))
        zoom.isEnabled = false
        zoomButton = zoom
        view = makeSheetView(
            title: "Auto Zoom",
            hint: "Zooms in where the recording's clicks and typing are, and back out after. "
                + "Each zoom is an ordinary action. One undo step.",
            content: sheetColumn([grid, summaryLabel]),
            buttonRow: makeButtonRow(cancel: cancel, apply: zoom))
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

    private func didRead(_ read: Result<[UInt32: ReelCursor], Error>) {
        switch read {
        case .failure(let error):
            summaryLabel.stringValue = error.localizedDescription
        case .success(let tracks):
            self.tracks = tracks
            let typing = AutoZoom.hasTyping(tracks)
            typingBox.isEnabled = typing
            typingBox.state = typing ? .on : .off
            replan()
            #if FRAMEJOB_DEV_TOOLS
            if plan != nil, !accepted, UserDefaults.standard.bool(forKey: Self.devAcceptKey) {
                accepted = true
                DispatchQueue.main.async { [weak self] in self?.zoomClicked(nil) }
            }
            #endif
        }
    }

    // MARK: - Values

    /// What the controls say, each number inside its range.
    private var settings: AutoZoomSettings {
        func clamped(_ field: NSTextField, _ range: ClosedRange<Double>) -> Double {
            min(max(field.doubleValue, range.lowerBound), range.upperBound)
        }
        var s = AutoZoomSettings()
        s.zoom = clamped(zoomField, AutoZoomSettings.zoomRange)
        s.lead = clamped(leadField, AutoZoomSettings.leadRange)
        s.stay = clamped(stayField, AutoZoomSettings.stayRange)
        s.follow = followBox.state == .on
        s.typing = typingBox.isEnabled && typingBox.state == .on
        s.replace = replaceBox.state == .on
        return s
    }

    /// Plans again on main and says what Zoom would do.
    private func replan() {
        guard let document, let tracks else { return }
        let snapshot = document.editedProject.snapshot
        let clips = clipIDs.compactMap { snapshot.clip($0) }
        do {
            let plan = try AutoZoom.plan(
                clips, tracks: tracks, project: document.editedProject, settings: settings,
                from: nil, to: nil)
            self.plan = plan
            summaryLabel.stringValue = Self.summary(plan)
            zoomButton?.isEnabled = true
        } catch {
            plan = nil
            summaryLabel.stringValue = error.localizedDescription
            zoomButton?.isEnabled = false
        }
    }

    /// "N zooms in V visits", and the drops.
    static func summary(_ plan: AutoZoomPlan) -> String {
        let zooms = plan.added == 1 ? "1 zoom" : "\(plan.added) zooms"
        let visits = plan.visits == 1 ? "1 visit" : "\(plan.visits) visits"
        var text = "\(zooms) in \(visits)."
        if plan.dropped > 0 {
            text += " \(plan.dropped) dropped where an action is already set."
        }
        return text
    }

    // MARK: - Controls

    @objc private func controlChanged(_ sender: Any?) {
        replan()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let range =
            field === zoomField
            ? AutoZoomSettings.zoomRange
            : field === leadField ? AutoZoomSettings.leadRange : AutoZoomSettings.stayRange
        field.doubleValue = min(max(field.doubleValue, range.lowerBound), range.upperBound)
        replan()
    }

    // MARK: - Commit

    @objc private func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    @objc private func zoomClicked(_ sender: Any?) {
        replan()
        guard let document, let plan else { return }
        let settings = self.settings
        dismiss(self)
        if !plan.ops.isEmpty {
            document.applyEdit(AutoZoom.actionName, plan.ops)
        }
        settings.remember(changedFrom: opened, in: .standard)
    }
}
