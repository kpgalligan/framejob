import AppKit

/// What the Make Vertical Version sheet's Make hands the editor (spec §11 VR-39 (f)): once, on
/// the main queue's next turn after `viewDidDisappear`; never after Cancel.
struct VerticalHandOff {
    let settings: VerticalSettings
    let copy: Bool
    /// `present` for a following kind, [] for Center.
    let targets: [UInt32]
    let missing: Set<UInt32>
    /// The missing analyses; [] when none or Center.
    let requests: [AnalysisRequest]
    /// What the sheet read; [:] when `requests` is non-empty or Center.
    let subjects: [UInt32: [String: Any]]
    /// `document.project` when `analysisTargets` ran (`viewDidAppear`).
    let asked: ReelProject
    /// `document.scope` at the same moment.
    let scope: UInt32?
}

/// File ▸ Make Vertical Version… (road map "creator-jobs" VR3b, spec §11 VR-39 (b)–(f), (h)):
/// VR3a's step over the top-level timeline (`VerticalVersion.plan`), opened as a copy or applied
/// in place by the editor (`EditorViewController+VerticalVersion.swift`); the tool is
/// `make_vertical_version` (`AgentServer+VerticalVersion.swift`).
///
/// Shape (the sizes `VerticalVersion.offered` lists), Follow, Zoom (100–400 %, opening at 100 %,
/// never remembered), Where Empty (off while Follow is Center), Make a copy (ticked, never
/// remembered), then the summary. Follow and Where Empty are VR-29 (c)'s two keys, through
/// `FollowSubjectSettings`. At `viewDidAppear` the sheet splits the media pictures by
/// `analysisTargets` and asks `FramingAnalysis.requests` what is missing. With nothing missing it
/// reads the subjects off main ("Reading the analysis…", Make disabled) and plans on main at
/// every change; with something missing a following kind shows the pending summary. Center
/// reads no subjects, so it plans at once and never analyzes. Make remembers, dismisses and
/// hands a `VerticalHandOff` to the editor: the sheet itself never edits and never opens a
/// window.
///
/// **The dev accept** (`-RCDevVerticalAccept YES`, or `in-place`, which unticks Make a copy
/// first; dev tools only): the sheet presses Make once, the first time Make is enabled after the
/// first summary (AU-128's precedent).
final class VerticalVersionSheetController: NSViewController, NSTextFieldDelegate {
    /// The dev-only launch default that presses Make.
    static let devAcceptKey = "RCDevVerticalAccept"
    /// Its value that unticks Make a copy before pressing Make.
    static let devAcceptInPlace = "in-place"
    private static let followTitles = ["Subject", "Faces", "People", "Salient Region", "Center"]
    private static let whereEmpties: [(String, FramingWhereEmpty)] = [
        ("Show Whole", .fit), ("Center", .center),
    ]

    private weak var document: ProjectDocument?
    private let make: (VerticalHandOff) -> Void
    private let opened: FollowSubjectSettings
    private let shapes: [VerticalShape]
    private let canvas: CanvasSnapshot
    private var present: [UInt32] = []
    private var missing: Set<UInt32> = []
    private var requests: [AnalysisRequest] = []
    private var requestError: String?
    private var subjects: [UInt32: [String: Any]]?
    private var asked: ReelProject?
    private var askedScope: UInt32?
    private var accepted = false
    /// Set by Make: handed to `make` after disappearing.
    private var handOff: VerticalHandOff?

    private let shapePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let followPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let whereEmptyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let zoomField = NSTextField(string: "")
    private let copyBox = NSButton(checkboxWithTitle: "Make a copy", target: nil, action: nil)
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private var makeButton: NSButton?

    init(document: ProjectDocument, make: @escaping (VerticalHandOff) -> Void) {
        self.document = document
        self.make = make
        self.opened = FollowSubjectSettings.remembered(.standard, zoom: 1)
        self.canvas = document.project.snapshot.canvas
        self.shapes = VerticalVersion.offered(canvas)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("VerticalVersionSheetController does not support NSCoder")
    }

    // MARK: - View

    override func loadView() {
        for shape in shapes {
            let size = shape.size(from: canvas)
            shapePopup.addItem(withTitle: "\(shape.rawValue) (\(size.width) × \(size.height))")
        }
        shapePopup.selectItem(at: 0)
        for title in Self.followTitles { followPopup.addItem(withTitle: title) }
        followPopup.selectItem(at: FollowSubject.follows.firstIndex(of: opened.follow) ?? 0)
        for (title, _) in Self.whereEmpties { whereEmptyPopup.addItem(withTitle: title) }
        whereEmptyPopup.selectItem(
            at: Self.whereEmpties.firstIndex { $0.1 == opened.whereEmpty } ?? 0)
        for (popup, id) in [
            (shapePopup, "vertical.shape"), (followPopup, "vertical.follow"),
            (whereEmptyPopup, "vertical.whereEmpty"),
        ] {
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
        zoomField.integerValue = 100
        zoomField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        zoomField.setAccessibilityIdentifier("vertical.zoom")
        DSField.style(zoomField)

        copyBox.state = .on
        copyBox.font = DS.sans(13)
        copyBox.target = self
        copyBox.action = #selector(controlChanged(_:))
        copyBox.setAccessibilityIdentifier("vertical.copy")

        summaryLabel.font = DS.sans(12)
        summaryLabel.textColor = DS.textMuted
        summaryLabel.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2
        summaryLabel.stringValue = FollowSubjectSheetController.reading
        summaryLabel.setAccessibilityIdentifier("vertical.summary")

        let grid = makeSheetGrid([
            [fieldLabel("Shape:"), shapePopup],
            [fieldLabel("Follow:"), followPopup],
            [fieldLabel("Zoom:"), sheetRow([zoomField, sheetUnitLabel("%")])],
            [fieldLabel("Where Empty:"), whereEmptyPopup],
            [NSGridCell.emptyContentView, copyBox],
        ])
        let cancel = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        let make = StickerButton(
            title: "Make", style: .primary, target: self, action: #selector(makeClicked(_:)))
        make.isEnabled = false
        makeButton = make
        view = makeSheetView(
            title: "Make Vertical Version",
            hint: "Makes a version of the timeline for a tall or square canvas. Each full-frame "
                + "movie clip follows its subject with eased moves, stills and nests are "
                + "centred, and everything else is kept as placed, with a blurred copy behind a "
                + "clip where it shows the whole picture. With Make a copy it opens as a new "
                + "project and this one does not change. One undo step.",
            content: sheetColumn([grid, summaryLabel]),
            buttonRow: makeButtonRow(cancel: cancel, apply: make))
        whereEmptyPopup.isEnabled = opened.follow != .center
    }

    /// VR-39 (d): the targets and the requests, once, on the project and scope the hand-off
    /// carries.
    override func viewDidAppear() {
        super.viewDidAppear()
        guard asked == nil, let document else { return }
        let project = document.project
        asked = project
        askedScope = document.scope
        let targets = VerticalVersion.analysisTargets(project, urls: document.mediaURLs())
        present = targets.present
        missing = targets.missing
        do {
            requests = try FramingAnalysis.requests(clips: present, in: document, project: project)
        } catch {
            requestError = error.localizedDescription
        }
        if requestError == nil, requests.isEmpty {
            if let cacheDir = document.cacheDirectory, !present.isEmpty {
                let clips = present
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let read = FollowSubject.subjects(clips, in: project, cacheDir: cacheDir)
                    DispatchQueue.main.async { self?.didRead(read) }
                }
            } else {
                subjects = [:]
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
        let make = self.make
        DispatchQueue.main.async { make(handOff) }
    }

    // MARK: - Values

    /// What the follow controls say, Zoom inside its range: VR-29's settings, remembered as theirs.
    private var follow: FollowSubjectSettings {
        let range = FollowSubjectSettings.zoomRange
        let percent = Double(zoomField.integerValue)
        let follow = FollowSubject.follows[max(0, followPopup.indexOfSelectedItem)]
        let empty = Self.whereEmpties[max(0, whereEmptyPopup.indexOfSelectedItem)].1
        return FollowSubjectSettings(
            follow: follow, zoom: min(max(percent / 100, range.lowerBound), range.upperBound),
            whereEmpty: empty)
    }

    /// The step's settings: the chosen shape and the follow controls.
    private func settings(_ follow: FollowSubjectSettings) -> VerticalSettings? {
        guard !shapes.isEmpty else { return nil }
        let shape = shapes[min(max(0, shapePopup.indexOfSelectedItem), shapes.count - 1)]
        return VerticalSettings(
            shape: shape, follow: follow.follow, zoom: follow.zoom, whereEmpty: follow.whereEmpty)
    }

    /// Whether Make hands the analysis on: a following kind with requests missing.
    private func pending(_ follow: FollowSubjectSettings) -> Bool {
        follow.follow.follows && requestError == nil && !requests.isEmpty
    }

    /// Says what Make would do and enables it: the request error, the pending summary,
    /// "Reading the analysis…", or the plan made on main over the document's current handle.
    private func refresh() {
        let follow = self.follow
        whereEmptyPopup.isEnabled = follow.follow != .center
        var enabled = false
        if let settings = settings(follow) {
            if follow.follow.follows, let requestError {
                summaryLabel.stringValue = requestError
            } else if pending(follow) {
                let size = settings.shape.size(from: canvas)
                summaryLabel.stringValue = VerticalVersion.pendingSummary(
                    files: Set(requests.map(\.media.id)).count, width: size.width,
                    height: size.height)
                enabled = true
            } else if follow.follow.follows, subjects == nil {
                summaryLabel.stringValue = FollowSubjectSheetController.reading
            } else {
                let (made, text) = planned(settings)
                summaryLabel.stringValue = text
                enabled = made
            }
        }
        makeButton?.isEnabled = enabled
        acceptIfAsked()
    }

    /// `VerticalVersion.plan` on the document's current handle: whether it makes anything, and
    /// its summary or the refusal.
    private func planned(_ settings: VerticalSettings) -> (Bool, String) {
        guard let document else { return (false, "") }
        do {
            switch try VerticalVersion.plan(
                document.project, settings: settings,
                subjects: settings.follow.follows ? (subjects ?? [:]) : [:], missing: missing)
            {
            case .plan(let plan): return (!plan.ops.isEmpty, VerticalVersion.summary(plan))
            case .refused(let why): return (false, why)
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// The dev accept: Make pressed once, async, the first time it is enabled with the sheet up;
    /// `in-place` unticks Make a copy first.
    private func acceptIfAsked() {
        #if FRAMEJOB_DEV_TOOLS
        guard makeButton?.isEnabled == true, !accepted, view.window != nil else { return }
        let defaults = UserDefaults.standard
        let inPlace = defaults.string(forKey: Self.devAcceptKey) == Self.devAcceptInPlace
        guard inPlace || defaults.bool(forKey: Self.devAcceptKey) else { return }
        accepted = true
        if inPlace { copyBox.state = .off }
        DispatchQueue.main.async { [weak self] in self?.makeClicked(nil) }
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

    /// Writes the remembered keys, dismisses and hands the editor what it needs: the plan is
    /// made again there, on the current handle, after the project check (VR-39 (f), (g)).
    @objc private func makeClicked(_ sender: Any?) {
        guard makeButton?.isEnabled == true, let asked else { return }
        let follow = self.follow
        guard let settings = settings(follow) else { return }
        let following = follow.follow.follows
        let analyzing = pending(follow)
        follow.remember(changedFrom: opened, in: .standard)
        handOff = VerticalHandOff(
            settings: settings, copy: copyBox.state == .on, targets: following ? present : [],
            missing: missing, requests: analyzing ? requests : [],
            subjects: analyzing || !following ? [:] : (subjects ?? [:]), asked: asked,
            scope: askedScope)
        dismiss(self)
    }
}
