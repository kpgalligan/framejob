import AppKit

/// Clip ▸ Follow Subject… (road map "creator-jobs" VR2b2, spec §11 VR-29 (b)–(d), (g), (h)): each
/// selected clip with a moving picture framed on its subject by `reframe_clip` with `replace:
/// true` and a "Backgrounds" track behind it, as one undo step "Follow Subject". The plan is
/// `FollowSubject.plan`; `reframe_clip`'s tool is the mirror (`AgentServer+Framing.swift`).
///
/// Follow (Subject, Faces, People, Salient Region, Center), Zoom (100–400 %, never remembered)
/// and Where Empty (Show Whole, Center; off while Follow is Center), then the summary. The sheet
/// opens at once and asks `FramingAnalysis.requests` what is missing. With nothing missing it
/// reads the subjects off main ("Reading the analysis…", Follow disabled) and plans on main at
/// every change. With something missing a following kind shows the pending summary, and Follow
/// remembers, dismisses and hands the requests to the editor (`analyze`) on the main queue's next
/// turn after `viewDidDisappear` — the Analyzing sheet and the commit are
/// `EditorViewController+FollowSubject.swift`'s. Center reads no subjects, so it plans at once and
/// never analyzes. Follow plans again on the document's current handle before it applies.
///
/// **The dev accept** (`-RCDevFollowAccept YES`, dev tools only): the sheet presses Follow once,
/// the first time Follow is enabled after the first summary (AU-128's precedent).
final class FollowSubjectSheetController: NSViewController, NSTextFieldDelegate {
    /// The dev-only launch default that presses Follow.
    static let devAcceptKey = "RCDevFollowAccept"
    static let reading = "Reading the analysis…"
    private static let followTitles = ["Subject", "Faces", "People", "Salient Region", "Center"]
    private static let whereEmpties: [(String, FramingWhereEmpty)] = [
        ("Show Whole", .fit), ("Center", .center),
    ]

    private weak var document: ProjectDocument?
    private let clipIDs: [UInt32]
    private let opened: FollowSubjectSettings
    private let analyze: (FollowSubjectSettings, [AnalysisRequest]) -> Void
    private var requests: [AnalysisRequest] = []
    private var requestError: String?
    private var subjects: [UInt32: [String: Any]]?
    private var asked = false
    private var plan: FollowSubject.Plan?
    private var accepted = false
    /// Set by Follow when the analysis is to be made: handed to `analyze` after disappearing.
    private var handOff: (FollowSubjectSettings, [AnalysisRequest])?

    private let followPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let whereEmptyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let zoomField = NSTextField(string: "")
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private var followButton: NSButton?

    init(
        document: ProjectDocument, clips: [UInt32],
        analyze: @escaping (FollowSubjectSettings, [AnalysisRequest]) -> Void
    ) {
        self.document = document
        self.clipIDs = clips
        self.analyze = analyze
        self.opened = FollowSubjectSettings.remembered(
            .standard, zoom: FollowSubject.defaultZoom(clips, in: document.editedProject.snapshot))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FollowSubjectSheetController does not support NSCoder")
    }

    // MARK: - View

    override func loadView() {
        for title in Self.followTitles { followPopup.addItem(withTitle: title) }
        followPopup.selectItem(at: FollowSubject.follows.firstIndex(of: opened.follow) ?? 0)
        for (title, _) in Self.whereEmpties { whereEmptyPopup.addItem(withTitle: title) }
        whereEmptyPopup.selectItem(
            at: Self.whereEmpties.firstIndex { $0.1 == opened.whereEmpty } ?? 0)
        for (popup, id) in [(followPopup, "follow.kind"), (whereEmptyPopup, "follow.whereEmpty")] {
            popup.font = DS.sans(13)
            popup.target = self
            popup.action = #selector(controlChanged(_:))
            popup.setAccessibilityIdentifier(id)
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: FollowSubjectSettings.zoomRange.lowerBound * 100)
        formatter.maximum = NSNumber(value: FollowSubjectSettings.zoomRange.upperBound * 100)
        zoomField.formatter = formatter
        zoomField.delegate = self
        zoomField.alignment = .right
        zoomField.integerValue = Int((opened.zoom * 100).rounded())
        zoomField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        zoomField.setAccessibilityIdentifier("follow.zoom")
        DSField.style(zoomField)

        summaryLabel.font = DS.sans(12)
        summaryLabel.textColor = DS.textMuted
        summaryLabel.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2
        summaryLabel.stringValue = Self.reading
        summaryLabel.setAccessibilityIdentifier("follow.summary")

        let grid = makeSheetGrid([
            [fieldLabel("Follow:"), followPopup],
            [fieldLabel("Zoom:"), sheetRow([zoomField, sheetUnitLabel("%")])],
            [fieldLabel("Where Empty:"), whereEmptyPopup],
        ])
        let cancel = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        let follow = StickerButton(
            title: "Follow", style: .primary, target: self, action: #selector(followClicked(_:)))
        follow.isEnabled = false
        followButton = follow
        view = makeSheetView(
            title: "Follow Subject",
            hint: "Frames each selected clip on its subject with eased moves on its action lane, "
                + "and a blurred copy behind it where it shows the whole picture. Replaces the "
                + "clips' own position and scale. One undo step.",
            content: sheetColumn([grid, summaryLabel]),
            buttonRow: makeButtonRow(cancel: cancel, apply: follow))
        whereEmptyPopup.isEnabled = opened.follow != .center
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !asked, let document else { return }
        asked = true
        do {
            requests = try FramingAnalysis.requests(
                clips: FollowSubject.analysed(clipIDs, in: document.editedProject), in: document)
        } catch {
            requestError = error.localizedDescription
        }
        if requestError == nil, requests.isEmpty, let cacheDir = document.cacheDirectory {
            let project = document.editedProject
            let clips = clipIDs
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let read = FollowSubject.subjects(clips, in: project, cacheDir: cacheDir)
                DispatchQueue.main.async { self?.didRead(read) }
            }
        }
        refresh()
    }

    private func didRead(_ read: [UInt32: [String: Any]]) {
        subjects = read
        refresh()
    }

    /// The one hand-back: once, after the sheet is gone, never after Cancel.
    override func viewDidDisappear() {
        super.viewDidDisappear()
        guard let handOff else { return }
        self.handOff = nil
        let analyze = self.analyze
        DispatchQueue.main.async { analyze(handOff.0, handOff.1) }
    }

    // MARK: - Values

    /// What the controls say, Zoom inside its range.
    private var settings: FollowSubjectSettings {
        let range = FollowSubjectSettings.zoomRange
        let percent = Double(zoomField.integerValue)
        let follow = FollowSubject.follows[max(0, followPopup.indexOfSelectedItem)]
        let empty = Self.whereEmpties[max(0, whereEmptyPopup.indexOfSelectedItem)].1
        return FollowSubjectSettings(
            follow: follow, zoom: min(max(percent / 100, range.lowerBound), range.upperBound),
            whereEmpty: empty)
    }

    /// Whether Follow must make the analysis first: a following kind with requests missing.
    private func pending(_ settings: FollowSubjectSettings) -> Bool {
        settings.follow.follows && requestError == nil && !requests.isEmpty
    }

    /// Says what Follow would do and enables it: the request error, the pending summary,
    /// "Reading the analysis…", or the plan made on main over the document's current handle.
    private func refresh() {
        let settings = self.settings
        whereEmptyPopup.isEnabled = settings.follow != .center
        plan = nil
        var enabled = false
        if settings.follow.follows, let requestError {
            summaryLabel.stringValue = requestError
        } else if pending(settings) {
            summaryLabel.stringValue = FollowSubject.pendingSummary(
                files: Set(requests.map(\.media.id)).count, clips: clipIDs.count)
            enabled = true
        } else if settings.follow.follows, subjects == nil {
            summaryLabel.stringValue = Self.reading
        } else {
            let (made, text) = planned(settings)
            plan = made
            summaryLabel.stringValue = text
            enabled = !(made?.ops.isEmpty ?? true)
        }
        followButton?.isEnabled = enabled
        acceptIfAsked()
    }

    /// `FollowSubject.plan` on the document's current handle: the plan and its summary, or the
    /// refusal.
    private func planned(_ settings: FollowSubjectSettings) -> (FollowSubject.Plan?, String) {
        guard let document else { return (nil, "") }
        do {
            switch try FollowSubject.plan(
                clipIDs, subjects: settings.follow.follows ? (subjects ?? [:]) : [:],
                settings: settings, project: document.editedProject)
            {
            case .plan(let plan): return (plan, FollowSubject.summary(plan))
            case .refused(let why): return (nil, why)
            }
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    /// The dev accept: Follow pressed once, async, the first time it is enabled with the sheet up.
    private func acceptIfAsked() {
        #if FRAMEJOB_DEV_TOOLS
        guard followButton?.isEnabled == true, !accepted, view.window != nil,
            UserDefaults.standard.bool(forKey: Self.devAcceptKey)
        else { return }
        accepted = true
        DispatchQueue.main.async { [weak self] in self?.followClicked(nil) }
        #endif
    }

    // MARK: - Controls

    @objc private func controlChanged(_ sender: Any?) {
        refresh()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        let range = FollowSubjectSettings.zoomRange
        let percent = Double(zoomField.integerValue)
        zoomField.integerValue = Int(
            min(max(percent, range.lowerBound * 100), range.upperBound * 100))
        refresh()
    }

    // MARK: - Commit

    @objc private func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    /// A following kind with requests missing hands them off; otherwise the plan is made again on
    /// the current handle and applied as one step, a refusal staying in the summary.
    @objc private func followClicked(_ sender: Any?) {
        guard let document, followButton?.isEnabled == true else { return }
        let settings = self.settings
        if pending(settings) {
            settings.remember(changedFrom: opened, in: .standard)
            handOff = (settings, requests)
            dismiss(self)
            return
        }
        let (made, text) = planned(settings)
        guard let made, !made.ops.isEmpty else {
            summaryLabel.stringValue = text
            followButton?.isEnabled = false
            return
        }
        settings.remember(changedFrom: opened, in: .standard)
        dismiss(self)
        document.performGroupedEdit(FollowSubject.actionName, made.ops)
    }
}
