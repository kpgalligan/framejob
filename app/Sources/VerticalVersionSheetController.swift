import AppKit

/// What the Make Vertical Version sheet's Make hands the editor (spec §11 VR-39 (f)): once, on
/// the main queue's next turn after `viewDidDisappear`; never after Cancel.
struct VerticalHandOff {
    let settings: VerticalSettings
    let copy: Bool
    /// `present` for a following kind, [] for Center.
    let targets: [UInt32]
    /// `analysisTargets`' `cursor` for a following kind, [] for Center (spec §11 VR-51).
    let cursor: [UInt32]
    let missing: Set<UInt32>
    /// The missing analyses; [] when none or Center.
    let requests: [AnalysisRequest]
    /// What the sheet read, the cursor's beside the analysis's; [:] when `requests` is
    /// non-empty or Center.
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
/// remembered), then the summary. Follow and Where Empty are VR-29 (c)'s two keys, opened from
/// `VerticalVersion.remembered` (so a stored Speaker opens here) and written through
/// `FollowSubjectSettings.remember`.
///
/// **Speaker** (road map creator-jobs VR6b, spec §11 VR-66) shows `VerticalSpeakerPicker`: the
/// microphone tracks, the ticked ones' Face pop-ups and a note. Its reading
/// (`VerticalVersion.speakerReading`: the turns, then the core's match on the reference clip) is
/// made on main and cached per ticked set only when ready; a refused one is read again at each
/// refresh. Make passes the ticked `mics` and the confirmed `micFaces`. A sheet presented again
/// after its analysis (`restoring`) opens on the hand-off's shape, follow, zoom, where empty,
/// copy and ticked microphones. At `viewDidAppear` the sheet splits the media pictures by
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
    /// `VerticalVersion.follows`' titles, in its order.
    private static let followTitles = [
        "Subject", "Faces", "People", "Salient Region", "Speaker", "Center",
    ]
    private static let whereEmpties: [(String, FramingWhereEmpty)] = [
        ("Show Whole", .fit), ("Center", .center),
    ]

    private weak var document: ProjectDocument?
    private let make: (VerticalHandOff) -> Void
    private let opened: FollowSubjectSettings
    /// The hand-off this sheet is presented again from, after its analysis (VR-66 (e)).
    private let restoring: VerticalHandOff?
    private let picker: VerticalSpeakerPicker
    /// Speaker's ready readings, per ticked set, each with the reference's microphones named
    /// back as the ticked ones, so a set ticked again is offered its match again (VR-66 (c)).
    private var readings: [[UInt32]: (read: VerticalVersion.SpeakerReading, mics: [UInt32])] = [:]
    /// The subjects with their turns the current Speaker plan read.
    private var speakerSubjects: [UInt32: [String: Any]]?
    private let shapes: [VerticalShape]
    private let canvas: CanvasSnapshot
    private var present: [UInt32] = []
    private var cursor: [UInt32] = []
    private var missing: Set<UInt32> = []
    private var requests: [AnalysisRequest] = []
    private var requestError: String?
    private var subjects: [UInt32: [String: Any]]?
    private var asked: ReelProject?
    /// VR-44 (b)'s survey of the project's graphic modules, made once at `viewDidAppear`.
    private var templates = VerticalVersion.TemplateSurvey()
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

    init(
        document: ProjectDocument, restoring: VerticalHandOff? = nil,
        make: @escaping (VerticalHandOff) -> Void
    ) {
        self.document = document
        self.make = make
        self.opened = VerticalVersion.remembered(.standard)
        self.restoring = restoring
        self.canvas = document.project.snapshot.canvas
        self.shapes = VerticalVersion.offered(canvas)
        let ticked = restoring.map(\.settings.mics).flatMap { $0.isEmpty ? nil : $0 }
        let relay = PickerRelay()
        self.picker = VerticalSpeakerPicker(
            microphones: VerticalVersion.microphones(document.project), ticked: ticked,
            onChange: { relay.changed?() })
        super.init(nibName: nil, bundle: nil)
        relay.changed = { [weak self] in self?.refresh() }
    }

    /// The picker's change, handed to the sheet once it exists.
    private final class PickerRelay {
        var changed: (() -> Void)?
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
        let start = restoring?.settings
        shapePopup.selectItem(at: start.flatMap { shapes.firstIndex(of: $0.shape) } ?? 0)
        for title in Self.followTitles { followPopup.addItem(withTitle: title) }
        followPopup.selectItem(
            at: VerticalVersion.follows.firstIndex(of: start?.follow ?? opened.follow) ?? 0)
        for (title, _) in Self.whereEmpties { whereEmptyPopup.addItem(withTitle: title) }
        let empty = start?.whereEmpty ?? opened.whereEmpty
        whereEmptyPopup.selectItem(at: Self.whereEmpties.firstIndex { $0.1 == empty } ?? 0)
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
        zoomField.integerValue = Int(((start?.zoom ?? 1) * 100).rounded())
        zoomField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        zoomField.setAccessibilityIdentifier("vertical.zoom")
        DSField.style(zoomField)

        copyBox.state = (restoring?.copy ?? true) ? .on : .off
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
                + "movie clip follows its subject with eased moves (with Speaker, whoever is "
                + "talking on the ticked microphones), stills and nests are "
                + "centred, and everything else is kept as placed, with a blurred copy behind a "
                + "clip where it shows the whole picture. With Make a copy it opens as a new "
                + "project and this one does not change. One undo step.",
            content: sheetColumn([grid, picker.view, summaryLabel]),
            buttonRow: makeButtonRow(cancel: cancel, apply: make))
        whereEmptyPopup.isEnabled = follow.follow != .center
        picker.view.isHidden = follow.follow != .speaker
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
        cursor = targets.cursor
        templates = VerticalVersion.templateSurvey(project, store: document.graphicStore)
        do {
            requests = try FramingAnalysis.requests(clips: present, in: document, project: project)
        } catch {
            requestError = error.localizedDescription
        }
        if requestError == nil, requests.isEmpty {
            // The cache folder is needed only for the analysed pictures; a cursor is read
            // from its own file (VR-51).
            let cacheDir = present.isEmpty ? nil : document.cacheDirectory
            let clips = cacheDir == nil ? [] : present
            let cursorClips = cursor
            if clips.isEmpty, cursorClips.isEmpty {
                subjects = [:]
            } else {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    var read = cacheDir.map {
                        FollowSubject.subjects(clips, in: project, cacheDir: $0)
                    } ?? [:]
                    read.merge(FramingCursor.subjects(cursorClips, in: project)) { _, new in new }
                    DispatchQueue.main.async { self?.didRead(read) }
                }
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
        let follow = VerticalVersion.follows[max(0, followPopup.indexOfSelectedItem)]
        let empty = Self.whereEmpties[max(0, whereEmptyPopup.indexOfSelectedItem)].1
        return FollowSubjectSettings(
            follow: follow, zoom: min(max(percent / 100, range.lowerBound), range.upperBound),
            whereEmpty: empty)
    }

    /// The step's settings: the chosen shape and the follow controls, with Speaker the ticked
    /// microphones and their confirmed faces.
    private func settings(_ follow: FollowSubjectSettings) -> VerticalSettings? {
        guard !shapes.isEmpty else { return nil }
        let shape = shapes[min(max(0, shapePopup.indexOfSelectedItem), shapes.count - 1)]
        let speaker = follow.follow == .speaker
        return VerticalSettings(
            shape: shape, follow: follow.follow, zoom: follow.zoom, whereEmpty: follow.whereEmpty,
            mics: speaker ? picker.mics : [], micFaces: speaker ? picker.micFaces : nil)
    }

    /// Whether Make hands the analysis on: an analysing follow with requests missing.
    private func pending(_ follow: FollowSubjectSettings) -> Bool {
        VerticalVersion.analyses(follow.follow) && requestError == nil && !requests.isEmpty
    }

    /// Says what Make would do and enables it: the request error, the pending summary,
    /// "Reading the analysis…", or the plan made on main over the document's current handle.
    private func refresh() {
        let follow = self.follow
        let analysing = VerticalVersion.analyses(follow.follow)
        let speaker = follow.follow == .speaker
        whereEmptyPopup.isEnabled = follow.follow != .center
        picker.view.isHidden = !speaker
        speakerSubjects = nil
        var enabled = false
        if let settings = settings(follow) {
            let ticked = (2...VerticalSpeakerPicker.mostMicrophones).contains(settings.mics.count)
            if analysing, let requestError {
                summaryLabel.stringValue = requestError
            } else if speaker, let document,
                VerticalVersion.speakerClips(document.project, settings: settings, missing: missing)
                    .isEmpty
            {
                summaryLabel.stringValue = VerticalVersion.noSpeakerClipSheet
            } else if pending(follow) {
                let size = settings.shape.size(from: canvas)
                summaryLabel.stringValue = VerticalVersion.pendingSummary(
                    files: Set(requests.map(\.media.id)).count, width: size.width,
                    height: size.height, speaker: speaker)
                enabled = !speaker || ticked
            } else if analysing, subjects == nil {
                summaryLabel.stringValue = FollowSubjectSheetController.reading
            } else if speaker {
                switch reading(settings) {
                case .refused(let why):
                    summaryLabel.stringValue = why
                case .ready(let read, _, _):
                    // Read again: the reading's first offer may have preset the faces.
                    let confirmed = self.settings(follow) ?? settings
                    speakerSubjects = read
                    let (made, text) = planned(confirmed)
                    summaryLabel.stringValue = text
                    enabled = made && ticked && confirmed.micFaces != nil
                }
            } else {
                let (made, text) = planned(settings)
                summaryLabel.stringValue = text
                enabled = made
            }
        }
        makeButton?.isEnabled = enabled
        acceptIfAsked()
    }

    /// VR-66 (c): the ticked set's reading, a ready one cached and offered to the picker at every
    /// refresh (`offer` presets a set once, so a repeat does nothing until the set is ticked
    /// again and its rows rebuilt); a refused one read again at every refresh.
    private func reading(_ settings: VerticalSettings) -> VerticalVersion.SpeakerReading {
        let key = settings.mics
        if let cached = readings[key] {
            if case .ready(_, _, let match) = cached.read { picker.offer(match, mics: cached.mics) }
            return cached.read
        }
        guard let document else { return .refused("") }
        var unconfirmed = settings
        unconfirmed.micFaces = nil
        let read = VerticalVersion.speakerReading(
            document: document, project: document.project, settings: unconfirmed,
            subjects: subjects ?? [:], missing: missing)
        guard case .ready(_, let reference, let match) = read else { return read }
        // The reference's own microphones named back as the ticked ones, track by track.
        let snapshot = document.project.snapshot
        let own = VerticalVersion.speakerClips(
            document.project, settings: unconfirmed, missing: missing
        ).first { $0.clip == reference }?.mics ?? []
        let byTrack = Dictionary(
            key.compactMap { id in snapshot.clip(id).map { ($0.track, id) } },
            uniquingKeysWith: { first, _ in first })
        let mics = own.map { snapshot.clip($0).flatMap { byTrack[$0.track] } ?? $0 }
        readings[key] = (read, mics)
        picker.offer(match, mics: mics)
        return read
    }

    /// `VerticalVersion.plan` on the document's current handle: whether it makes anything, and
    /// its summary or the refusal.
    private func planned(_ settings: VerticalSettings) -> (Bool, String) {
        guard let document else { return (false, "") }
        do {
            let read = settings.follow == .speaker
                ? (speakerSubjects ?? [:])
                : VerticalVersion.analyses(settings.follow) ? (subjects ?? [:]) : [:]
            switch try VerticalVersion.plan(
                document.project, settings: settings, subjects: read, missing: missing)
            {
            case .plan(let plan):
                let report = VerticalVersion.templateReport(
                    templates, copy: copyBox.state == .on)
                return (!plan.ops.isEmpty, VerticalVersion.summary(plan, templates: report))
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
        let following = VerticalVersion.analyses(follow.follow)
        let analyzing = pending(follow)
        follow.remember(changedFrom: opened, in: .standard)
        let read = follow.follow == .speaker ? speakerSubjects : subjects
        handOff = VerticalHandOff(
            settings: settings, copy: copyBox.state == .on, targets: following ? present : [],
            cursor: following ? cursor : [], missing: missing, requests: analyzing ? requests : [],
            subjects: analyzing || !following ? [:] : (read ?? [:]), asked: asked,
            scope: askedScope)
        dismiss(self)
    }
}
