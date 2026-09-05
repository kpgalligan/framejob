import AVFoundation
import AppKit
import UniformTypeIdentifiers

/// The editor window's content controller — spec §3's layout and nothing
/// else.
///
/// **Frozen file** (app/CLAUDE.md): this holds wiring only — view
/// construction, the closures that forward to named methods, the transport,
/// and the menu-validation table. Every feature lands in an
/// `EditorViewController+<Feature>.swift` extension, which is why the
/// properties those extensions need (`document`, `playback`, the three pane
/// containers, the view-state flags) are internal rather than private.
///
/// The three containers are the seams: a later stage puts
/// `PreviewCanvasView` in `canvasContainer`, `InspectorViewController`'s view
/// in `inspectorContainer` and `TimelineView` in `timelineContainer`, and
/// replaces the placeholders that stand in for them now.
final class EditorViewController: NSViewController {
    // MARK: - Metrics (spec §3's table)

    static let toolbarHeight: CGFloat = 44
    static let defaultInspectorWidth: CGFloat = 320
    static let minInspectorWidth: CGFloat = 280
    static let maxInspectorWidth: CGFloat = 440
    static let defaultTimelineHeight: CGFloat = 240
    static let minTimelineHeight: CGFloat = 140
    /// The timeline may not eat more than 60 % of the window (spec §3).
    static let maxTimelineFraction: CGFloat = 0.6
    static let minCanvasWidth: CGFloat = 380
    static let minUpperHeight: CGFloat = 220
    /// The void margin around the preview (spec §4.2).
    static let canvasMargin: CGFloat = 24

    // MARK: - Persisted view state

    /// Pane sizes and the toolbar toggles. View state, so `UserDefaults` and
    /// not the project (spec §5.2's last bullet).
    static let inspectorWidthKey = "ReelcutInspectorWidth"
    static let timelineHeightKey = "ReelcutTimelineHeight"
    static let inspectorCollapsedKey = "ReelcutInspectorCollapsed"
    static let safeGuidesKey = "ReelcutSafeGuidesVisible"
    static let snappingKey = "ReelcutSnappingEnabled"
    static let trackHeightKey = "ReelcutTimelineTrackHeight"

    // MARK: - Model

    /// Internal, not private: every `EditorViewController+…` file is a
    /// handler of this controller and acts on its document.
    weak var document: ProjectDocument?

    /// The preview transport. Owned here because the player layer is part of
    /// this view tree; `ProjectDocument` never touches it.
    let playback: Playback

    // MARK: - Panes

    /// Spec §3's three regions. The containers are stable; their contents are
    /// what later stages replace.
    let canvasContainer = NSView()
    let inspectorContainer = NSView()
    let timelineContainer = NSView()

    /// Hosts `playback.playerLayer`, sized to the canvas rectangle inside the
    /// void so the safe guides (and later the handle overlay) can share its
    /// exact frame.
    let playerHost = NSView()
    let safeGuides = SafeGuidesView(frame: .zero)

    private let mainSplit = NSSplitView()
    private let upperSplit = NSSplitView()

    // MARK: - Toolbar

    private let timecodeField = NSTextField(string: "00:00:00:00")
    private let durationLabel = NSTextField(labelWithString: "/ 00:00:00:00")
    private var zoomPopup: OptionPopupControl!
    private var safeToggle: OptionCheckboxControl!
    private let playButton = GhostButton(
        symbol: "play.fill", fallback: "▶", caption: nil, tooltip: "Play (Space)",
        action: #selector(playPause(_:)))
    private let pauseButton = GhostButton(
        symbol: "pause.fill", fallback: "❚❚", caption: nil, tooltip: "Pause (Space)",
        action: #selector(playPause(_:)))
    private let loopButton = GhostButton(
        symbol: "repeat", fallback: "↻", caption: nil, tooltip: "Loop",
        action: #selector(toggleLoop(_:)))

    // MARK: - View state

    /// Canvas zoom, indexing `canvasZoomTitles` (0 = Fit). Internal: the
    /// preview overlay stage reads it to map points through the video rect.
    var canvasZoomIndex = 0
    static let canvasZoomTitles = ["Fit", "50%", "100%", "200%"]
    /// The stops the titles name. `PreviewCanvasView` owns the table because
    /// it is the one that has to turn a stop into a rectangle.
    private static var canvasZoomScales: [CGFloat] { PreviewCanvasView.zoomScales }

    /// Toolbar toggles. Internal for the same reason as `document`.
    var safeGuidesVisible = UserDefaults.standard.bool(forKey: safeGuidesKey)
    var loopEnabled = false
    /// Timeline snapping (N). Lives here rather than on the timeline so the
    /// menu, the timeline toolbar and the canvas all read one flag.
    var snappingEnabled = true
    /// Timeline track height: 0 small, 1 medium, 2 large.
    var trackHeight = 1

    private var didRestorePanes = false
    private var isAdjustingPanes = false
    /// The handle `Playback` was last told about. Selection and range changes
    /// travel on the same notification as model changes, and re-publishing an
    /// unchanged project would cost a zero-tolerance seek per click.
    private var publishedProject: ReelProject?

    // MARK: - Life cycle

    init(document: ProjectDocument) {
        self.document = document
        playback = Playback(recipeKey: document.recipeKey)
        super.init(nibName: nil, bundle: nil)
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.snappingKey) != nil {
            snappingEnabled = defaults.bool(forKey: Self.snappingKey)
        }
        if defaults.object(forKey: Self.trackHeightKey) != nil {
            trackHeight = min(max(defaults.integer(forKey: Self.trackHeightKey), 0), 2)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EditorViewController does not support NSCoder")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        // Drops the player item and stops the periodic observer. Releasing
        // the RecipeSource key is the DOCUMENT's job (ProjectDocument.close).
        playback.invalidate()
    }

    // MARK: - View construction

    override func loadView() {
        let root = FileDropView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        root.wantsLayer = true
        root.layer?.backgroundColor = DS.chromeBackground.cgColor

        let toolbar = buildToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toolbar)

        buildPanes()
        mainSplit.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(mainSplit)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: Self.toolbarHeight),
            mainSplit.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            mainSplit.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            mainSplit.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            mainSplit.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        view = root
    }

    /// Spec §4.1's row: transport, timecode, canvas zoom, safe guides, then
    /// the add/export group pushed to the trailing edge.
    private func buildToolbar() -> NSView {
        let bar = BarView(border: .bottom)

        DSField.style(timecodeField)
        timecodeField.font = DS.mono(12)
        timecodeField.alignment = .center
        timecodeField.delegate = self
        timecodeField.toolTip = "Current time — click to type one (1:23, 83.5, 1:23:04)"
        timecodeField.widthAnchor.constraint(equalToConstant: 112).isActive = true

        durationLabel.font = DS.mono(12)
        durationLabel.textColor = DS.textFaint

        zoomPopup = OptionPopupControl(
            width: 74, items: Self.canvasZoomTitles,
            read: { [weak self] in self?.canvasZoomIndex ?? 0 },
            write: { [weak self] index in self?.setCanvasZoom(index) },
            enabled: { true },
            onEdit: { [weak self] in self?.refreshToolbarControls() })

        safeToggle = OptionCheckboxControl(
            label: "Safe",
            read: { [weak self] in self?.safeGuidesVisible ?? false },
            write: { [weak self] value in self?.setSafeGuides(value) },
            enabled: { true },
            onEdit: { [weak self] in self?.refreshToolbarControls() })

        let transport = NSStackView(views: [
            GhostButton(
                symbol: "backward.end.fill", fallback: "⏮", caption: nil,
                tooltip: "Go to Start (Home)", action: #selector(goToStart(_:))),
            GhostButton(
                symbol: "chevron.left.2", fallback: "◀◀", caption: nil,
                tooltip: "Previous Edit Point (↑)", action: #selector(previousEditPoint(_:))),
            playButton, pauseButton,
            GhostButton(
                symbol: "chevron.right.2", fallback: "▶▶", caption: nil,
                tooltip: "Next Edit Point (↓)", action: #selector(nextEditPoint(_:))),
            GhostButton(
                symbol: "forward.end.fill", fallback: "⏭", caption: nil,
                tooltip: "Go to End (End)", action: #selector(goToEnd(_:))),
            loopButton,
        ])
        transport.orientation = .horizontal
        transport.spacing = 2

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(1), for: .horizontal)

        let trailing = NSStackView(views: [
            GhostButton(
                symbol: "textformat", fallback: "T", caption: nil,
                tooltip: "Add Text (T)", action: #selector(addTextClip(_:))),
            GhostButton(
                symbol: "square.on.circle", fallback: "▭", caption: nil,
                tooltip: "Add Shape", action: #selector(showAddShapeMenu(_:))),
            GhostButton(
                symbol: "bookmark", fallback: "◆", caption: nil,
                tooltip: "Add Marker (M)", action: #selector(addMarker(_:))),
            StickerButton(
                title: "Export…", style: .primary, target: nil,
                action: #selector(exportProject(_:))),
        ])
        trailing.orientation = .horizontal
        trailing.spacing = 4

        let row = NSStackView(views: [
            transport, timecodeField, durationLabel, zoomPopup, safeToggle, spacer, trailing,
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        bar.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    /// The nested splits of spec §3: canvas | inspector on top, timeline
    /// below. `NSSplitView` owns the arranged subviews' frames, so the pane
    /// containers are plain views and everything inside them is either
    /// autolayout (the placeholders) or frame-positioned by `layoutCanvas`
    /// (the preview).
    private func buildPanes() {
        // The splits lay their arranged subviews out with constraints, so the
        // containers opt out of the autoresizing mask; the two views INSIDE
        // the canvas container keep theirs, because `layoutCanvas` positions
        // them by frame against the canvas rectangle it computes.
        for pane in [canvasContainer, inspectorContainer, timelineContainer, upperSplit] {
            pane.translatesAutoresizingMaskIntoConstraints = false
        }
        canvasContainer.wantsLayer = true
        canvasContainer.layer?.backgroundColor = DS.canvasVoid.cgColor
        // The player layer's host and the safe guides are built here because
        // they belong to `playback`'s lifetime, then re-parented into
        // `PreviewCanvasView` by `installCanvas()` — one object has to own the
        // canvas rectangle, and it is the one the overlay maps through.
        playerHost.wantsLayer = true
        playerHost.layer?.addSublayer(playback.playerLayer)
        canvasContainer.addSubview(playerHost)
        safeGuides.isHidden = !safeGuidesVisible
        canvasContainer.addSubview(safeGuides)

        // The inspector and timeline panes are filled by `installInspector()`
        // and `installTimeline()` (their +Feature extensions) once the outlets
        // exist — each needs its closures wired at the moment it is built.

        upperSplit.isVertical = true
        upperSplit.dividerStyle = .thin
        upperSplit.delegate = self
        upperSplit.addArrangedSubview(canvasContainer)
        upperSplit.addArrangedSubview(inspectorContainer)
        upperSplit.setHoldingPriority(NSLayoutConstraint.Priority(249), forSubviewAt: 0)
        upperSplit.setHoldingPriority(NSLayoutConstraint.Priority(251), forSubviewAt: 1)

        mainSplit.isVertical = false
        mainSplit.dividerStyle = .thin
        mainSplit.delegate = self
        mainSplit.addArrangedSubview(upperSplit)
        mainSplit.addArrangedSubview(timelineContainer)
        mainSplit.setHoldingPriority(NSLayoutConstraint.Priority(249), forSubviewAt: 0)
        mainSplit.setHoldingPriority(NSLayoutConstraint.Priority(251), forSubviewAt: 1)
    }

    private func fill(_ container: NSView, with content: NSView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        playback.onTimeChanged = { [weak self] time in self?.playbackTimeChanged(time) }
        playback.onRateChanged = { [weak self] rate in self?.playbackRateChanged(rate) }
        playback.onError = { [weak self] error in self?.playbackFailed(error) }
        NotificationCenter.default.addObserver(
            self, selector: #selector(projectDidChange(_:)),
            name: .projectDocumentDidChange, object: nil)
        installCanvas()
        installTimeline()
        // Last: it registers the two views above as drop targets for a media
        // row dragged out of the Media tab.
        installInspector()
        playbackRateChanged(0)
        refreshToolbarControls()
        refreshFromDocument(isLive: false)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        restorePanesIfNeeded()
        // The bare-key map (Space, JKL, arrows) reaches keyDown through the
        // responder chain, so the root view has to hold first responder.
        view.window?.makeFirstResponder(view)
        // A project that opened with files missing offers Relink… once
        // (EditorViewController+Export.swift owns the once-per-document rule).
        offerRelinkIfNeeded()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutCanvas()
    }

    // MARK: - Panes

    private func restorePanesIfNeeded() {
        guard !didRestorePanes, view.bounds.width > 1, view.bounds.height > 1 else { return }
        didRestorePanes = true
        isAdjustingPanes = true
        defer { isAdjustingPanes = false }

        let defaults = UserDefaults.standard
        let inspectorWidth = clampInspectorWidth(
            CGFloat(defaults.double(forKey: Self.inspectorWidthKey)))
        let timelineHeight = clampTimelineHeight(
            CGFloat(defaults.double(forKey: Self.timelineHeightKey)))
        mainSplit.setPosition(
            mainSplit.bounds.height - timelineHeight - mainSplit.dividerThickness,
            ofDividerAt: 0)
        upperSplit.setPosition(
            upperSplit.bounds.width - inspectorWidth - upperSplit.dividerThickness,
            ofDividerAt: 0)
        if defaults.bool(forKey: Self.inspectorCollapsedKey) {
            inspectorContainer.isHidden = true
        }
    }

    private func clampInspectorWidth(_ stored: CGFloat) -> CGFloat {
        let width = stored > 0 ? stored : Self.defaultInspectorWidth
        return min(max(width, Self.minInspectorWidth), Self.maxInspectorWidth)
    }

    private func clampTimelineHeight(_ stored: CGFloat) -> CGFloat {
        let height = stored > 0 ? stored : Self.defaultTimelineHeight
        let ceiling = max(
            Self.minTimelineHeight, mainSplit.bounds.height * Self.maxTimelineFraction)
        return min(max(height, Self.minTimelineHeight), ceiling)
    }

    // MARK: - Canvas layout

    /// Places the preview inside the void. The arithmetic — zoom stops, the
    /// pan offset, the caption, and the safe guides sharing the canvas's exact
    /// frame — belongs to `PreviewCanvasView`, because the overlay has to map
    /// through the very same rectangle (`EditorViewController+Canvas.swift`).
    func layoutCanvas() {
        layoutCanvasPane()
    }

    // MARK: - Document changes

    @objc private func projectDidChange(_ note: Notification) {
        guard let document = document, note.object as? ProjectDocument === document else { return }
        refreshFromDocument(isLive: (note.userInfo?["isLive"] as? Bool) ?? false)
    }

    /// The one path from a changed project to the preview. `isLive` rides
    /// straight through to `Playback`, which debounces structural rebuilds
    /// during a gesture (spec §7.6).
    func refreshFromDocument(isLive: Bool) {
        guard let document = document else { return }
        applyLoopRange()
        if publishedProject !== document.project {
            publishedProject = document.project
            playback.update(project: document.project, urls: document.mediaURLs(), isLive: isLive)
        }
        layoutCanvas()
        refreshTimecode()
        refreshCanvas(isLive: isLive)
        refreshTimeline(isLive: isLive)
        refreshInspector(isLive: isLive)
        if let window = view.window {
            window.subtitle = EditorWindowController.subtitle(for: document)
        }
    }

    // MARK: - Playback wiring

    private func playbackTimeChanged(_ time: Ticks) {
        document?.playhead = time
        refreshTimecode()
        canvasPlayheadMoved()
        timelinePlayheadMoved()
        inspectorPlayheadMoved()
    }

    private func playbackRateChanged(_ rate: Float) {
        playButton.isHidden = rate != 0
        pauseButton.isHidden = rate == 0
    }

    private func playbackFailed(_ error: any Error) {
        // A failed rebuild is never fatal — the previous item keeps playing —
        // so it reports and stops there.
        NSApp.presentError(error)
    }

    func applyLoopRange() {
        guard loopEnabled else {
            playback.loopRange = nil
            return
        }
        if let range = document?.inOutRange, range.end > range.start {
            playback.loopRange = (start: range.start, duration: range.end - range.start)
        } else if let duration = document?.project.duration, duration > 0 {
            playback.loopRange = (start: 0, duration: duration)
        } else {
            playback.loopRange = nil
        }
    }

    // MARK: - Timecode

    /// "current / duration" in the document's rate (spec §4.1). Formatting is
    /// the core's (`ReelTime.format`), so the toolbar, the ruler and the
    /// agent all spell a time the same way.
    func refreshTimecode() {
        guard let document = document else { return }
        let canvas = document.project.snapshot.canvas
        let frames = canvas.timecodeFrames
        if timecodeField.currentEditor() == nil {
            timecodeField.stringValue = ReelTime.format(
                document.playhead, fps: canvas.fps, frames: frames)
        }
        durationLabel.stringValue =
            "/ " + ReelTime.format(document.project.duration, fps: canvas.fps, frames: frames)
    }

    /// Moves the playhead and the player together. Every tick reaching an op
    /// is snapped to the frame grid first (spec §6), and so is this one.
    func setPlayhead(_ time: Ticks) {
        guard let document = document else { return }
        let snapped = ReelTime.snapToFrame(max(0, time), fps: document.project.snapshot.canvas.fps)
        document.playhead = snapped
        playback.seek(to: snapped)
        refreshTimecode()
        canvasPlayheadMoved()
        timelinePlayheadMoved()
        inspectorPlayheadMoved()
    }

    private func refreshToolbarControls() {
        zoomPopup?.refresh()
        safeToggle?.refresh()
        loopButton.alphaValue = loopEnabled ? 1 : 0.55
    }

    // MARK: - Transport actions

    @objc func playPause(_ sender: Any?) {
        playback.togglePlayPause()
    }

    @objc func goToStart(_ sender: Any?) {
        playback.pause()
        setPlayhead(0)
    }

    @objc func goToEnd(_ sender: Any?) {
        playback.pause()
        setPlayhead(document?.project.duration ?? 0)
    }

    @objc func previousEditPoint(_ sender: Any?) {
        let now = document?.playhead ?? 0
        setPlayhead(editPoints().last { $0 < now } ?? 0)
    }

    @objc func nextEditPoint(_ sender: Any?) {
        let now = document?.playhead ?? 0
        let points = editPoints()
        setPlayhead(points.first { $0 > now } ?? points.last ?? now)
    }

    @objc func toggleLoop(_ sender: Any?) {
        loopEnabled.toggle()
        applyLoopRange()
        refreshToolbarControls()
    }

    /// Clip boundaries plus the two ends — what ↑/↓ and the transport's
    /// chevrons step between.
    private func editPoints() -> [Ticks] {
        guard let document = document else { return [0] }
        let snapshot = document.project.snapshot
        var points: Set<Ticks> = [0, snapshot.duration]
        for clip in snapshot.clips {
            points.insert(clip.start)
            points.insert(clip.end)
        }
        return points.sorted()
    }

    /// JKL (spec §9): L steps forward 1× → 2× → 4×, J the same backwards, K
    /// pauses. A rate the item cannot serve is AVFoundation's business.
    private static let shuttleRates: [Float] = [1, 2, 4]

    private func shuttle(forward: Bool) {
        let rate = playback.rate
        let sign: Float = forward ? 1 : -1
        let magnitude = abs(rate)
        guard rate * sign > 0 else {
            playback.setRate(sign)
            return
        }
        let next = Self.shuttleRates.first { $0 > magnitude + 0.01 } ?? magnitude
        playback.setRate(sign * next)
    }

    // MARK: - Canvas zoom and guides

    private func setCanvasZoom(_ index: Int) {
        canvasZoomIndex = min(max(index, 0), Self.canvasZoomScales.count - 1)
        layoutCanvas()
        refreshToolbarControls()
    }

    @objc func zoomIn(_ sender: Any?) {
        setCanvasZoom(canvasZoomIndex + 1)
    }

    @objc func zoomOut(_ sender: Any?) {
        setCanvasZoom(canvasZoomIndex - 1)
    }

    @objc func zoomToFit(_ sender: Any?) {
        setCanvasZoom(0)
    }

    private func setSafeGuides(_ visible: Bool) {
        safeGuidesVisible = visible
        safeGuides.isHidden = !visible
        UserDefaults.standard.set(visible, forKey: Self.safeGuidesKey)
    }

    @objc func toggleSafeAreas(_ sender: Any?) {
        setSafeGuides(!safeGuidesVisible)
        refreshToolbarControls()
    }

    /// ⌥⌘I. Collapsing an arranged subview is `isHidden` on it — the
    /// documented way, and the only one that survives a window resize.
    @objc func toggleInspector(_ sender: Any?) {
        let collapsed = !inspectorContainer.isHidden
        inspectorContainer.isHidden = collapsed
        UserDefaults.standard.set(collapsed, forKey: Self.inspectorCollapsedKey)
        upperSplit.adjustSubviews()
    }

    @objc func toggleSnapping(_ sender: Any?) {
        snappingEnabled.toggle()
        UserDefaults.standard.set(snappingEnabled, forKey: Self.snappingKey)
        timeline?.snappingEnabled = snappingEnabled
    }

    /// View > Timeline Track Height ▸ — the sender's tag is 0/1/2, the
    /// small/medium/large of spec §4.4.
    @objc func setTrackHeight(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag, (0...2).contains(tag) else {
            NSSound.beep()
            return
        }
        applyTrackHeight(tag)
    }

    // MARK: - Selection and range (pure view state)

    override func selectAll(_ sender: Any?) {
        guard let document = document else { return }
        document.selection = Set(document.project.snapshot.clips.map { $0.id })
        viewStateDidChange()
    }

    /// Selection and the in/out range are VIEW state: no op runs and no undo
    /// step is registered. Every view still draws them, so they travel on the
    /// one document channel (app/CLAUDE.md's state flow) — the project handle
    /// is unchanged, so `refreshFromDocument` skips the preview republish.
    func viewStateDidChange() {
        guard let document = document else { return }
        NotificationCenter.default.post(
            name: .projectDocumentDidChange, object: document, userInfo: ["isLive": false])
    }

    /// ⌥⌘A: everything that starts at or after the playhead — the selection
    /// you then drag to insert time (spec §4.4).
    @objc func selectAfterPlayhead(_ sender: Any?) {
        guard let document = document else { return }
        let now = document.playhead
        document.selection = Set(
            document.project.snapshot.clips.filter { $0.start >= now }.map { $0.id })
        viewStateDidChange()
    }

    @objc func setInPoint(_ sender: Any?) {
        guard let document = document else { return }
        let end = document.inOutRange?.end ?? document.project.duration
        document.inOutRange = (start: document.playhead, end: max(end, document.playhead))
        viewStateDidChange()
        applyLoopRange()
    }

    @objc func setOutPoint(_ sender: Any?) {
        guard let document = document else { return }
        let start = document.inOutRange?.start ?? 0
        document.inOutRange = (start: min(start, document.playhead), end: document.playhead)
        viewStateDidChange()
        applyLoopRange()
    }

    @objc func clearInOutRange(_ sender: Any?) {
        document?.inOutRange = nil
        viewStateDidChange()
        applyLoopRange()
    }

    // MARK: - Media

    /// File > Add Media… (⇧⌘I). The probe is asynchronous and the whole
    /// batch commits as one undo step; `ProjectDocument.importMedia` owns
    /// both halves.
    @objc func addMediaFiles(_ sender: Any?) {
        guard let document = document, let window = view.window else {
            NSSound.beep()
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ProjectDocument.readableTypes.compactMap(UTType.init)
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            document.importMedia(panel.urls)
        }
    }

    /// The Add Shape toolbar button's menu (rectangle, ellipse, line,
    /// arrow). Tags index `ShapeKind.allCases`, so the menu can never drift
    /// from the enum.
    @objc func showAddShapeMenu(_ sender: Any?) {
        let menu = NSMenu()
        for (index, kind) in ShapeKind.allCases.enumerated() {
            let item = NSMenuItem(
                title: kind.displayName, action: #selector(addShapeClip(_:)), keyEquivalent: "")
            item.tag = index
            menu.addItem(item)
        }
        guard let anchor = sender as? NSView else {
            NSSound.beep()
            return
        }
        menu.popUp(
            positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 4), in: anchor)
    }

    // MARK: - Keyboard (spec §9, the part the editor owns)

    override func keyDown(with event: NSEvent) {
        if handleEditorKey(event) { return }
        super.keyDown(with: event)
    }

    /// Bare keys only, and never while text is being edited — a modifier-less
    /// letter must not be stolen from the timecode field or (later) an inline
    /// text clip. Everything with a modifier arrives as a menu key
    /// equivalent instead, which is also where it gets validated.
    private func handleEditorKey(_ event: NSEvent) -> Bool {
        if view.window?.firstResponder is NSText { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.subtracting(.shift).isEmpty else { return false }
        guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else {
            return false
        }
        let shift = flags.contains(.shift)
        switch scalar.value {
        case UInt32(NSLeftArrowFunctionKey):
            stepFrames(shift ? -10 : -1)
        case UInt32(NSRightArrowFunctionKey):
            stepFrames(shift ? 10 : 1)
        case UInt32(NSUpArrowFunctionKey):
            previousEditPoint(nil)
        case UInt32(NSDownArrowFunctionKey):
            nextEditPoint(nil)
        case UInt32(NSHomeFunctionKey):
            goToStart(nil)
        case UInt32(NSEndFunctionKey):
            goToEnd(nil)
        default:
            return handleEditorCharacter(Character(scalar), shift: shift)
        }
        return true
    }

    /// Compared as a lowercased STRING, not a `Character`: lowercasing is not
    /// one-to-one in every locale (a Turkish "İ" becomes two scalars), and
    /// `Character(String)` traps on anything but exactly one.
    private func handleEditorCharacter(_ character: Character, shift: Bool) -> Bool {
        switch character.lowercased() {
        case " ":
            playPause(nil)
        case "j":
            shuttle(forward: false)
        case "k":
            playback.pause()
        case "l":
            shuttle(forward: true)
        case "i":
            setInPoint(nil)
        case "o":
            setOutPoint(nil)
        case "n":
            toggleSnapping(nil)
        case "m":
            addMarker(nil)
        case "w":
            trimStartToPlayhead(nil)
        case "e":
            trimEndToPlayhead(nil)
        case "t":
            addTextClip(nil)
        case "c":
            toggleCropMode(nil)
        case "z" where shift:
            fitTimeline(nil)
        default:
            return false
        }
        return true
    }

    private func stepFrames(_ count: Int) {
        guard let document = document else { return }
        playback.stepFrames(count, fps: document.project.snapshot.canvas.fps)
        document.playhead = playback.currentTime
        refreshTimecode()
    }

    // MARK: - Clip, track and marker actions
    //
    // One-line forwards into `EditorViewController+Timeline.swift`, which owns
    // the bodies (app/CLAUDE.md: this file stays wiring).

    @objc func splitAtPlayhead(_ sender: Any?) { splitAtPlayheadCommand() }
    @objc func trimStartToPlayhead(_ sender: Any?) { trimToPlayhead(.start) }
    @objc func trimEndToPlayhead(_ sender: Any?) { trimToPlayhead(.end) }
    @objc func deleteClips(_ sender: Any?) { deleteSelection() }
    @objc func rippleDeleteClips(_ sender: Any?) { rippleDeleteSelection() }
    @objc func duplicateClips(_ sender: Any?) { duplicateSelection() }
    @objc func freezeFrame(_ sender: Any?) { freezeSelection() }
    @objc func detachAudio(_ sender: Any?) { detachSelectionAudio() }
    /// Clip ▸ Speed… — the sheet lives in `SpeedSheetController`
    /// (EditorViewController+Export.swift).
    @objc func showSpeedSheet(_ sender: Any?) { presentSpeedSheet() }
    @objc func newTrack(_ sender: Any?) { newTrackCommand() }
    @objc func removeTrack(_ sender: Any?) { removeTrackCommand() }
    @objc func removeEmptyTracks(_ sender: Any?) { removeEmptyTracksCommand() }
    @objc func toggleTrackHidden(_ sender: Any?) { toggleTrack(.hidden) }
    @objc func toggleTrackMuted(_ sender: Any?) { toggleTrack(.muted) }
    @objc func toggleTrackLocked(_ sender: Any?) { toggleTrack(.locked) }
    @objc func addMarker(_ sender: Any?) { addMarkerCommand() }
    /// C — the preview canvas's crop mode (EditorViewController+Canvas.swift).
    @objc func toggleCropMode(_ sender: Any?) { toggleCanvasCropMode() }
    @objc func nextMarker(_ sender: Any?) { stepMarker(forward: true) }
    @objc func previousMarker(_ sender: Any?) { stepMarker(forward: false) }
    /// ⌥⌘K — the Video tab's Actions section owns the body
    /// (EditorViewController+Inspector.swift).
    @objc func addActionAtPlayhead(_ sender: Any?) { addActionAtPlayheadCommand() }
    /// Clip ▸ Transition ▸ — the sender's tag indexes `TransitionKind.allCases`.
    @objc func setTransitionKind(_ sender: Any?) { setTransitionKindCommand(sender) }
    /// M1 step 6 — the timeline view.
    @objc func fitTimeline(_ sender: Any?) { timeline?.fit() }
    /// ⌘E — the export sheet (EditorViewController+Export.swift).
    @objc func exportProject(_ sender: Any?) { exportProjectCommand() }

    // MARK: - Actions later stages implement
    //
    // Every menu item and toolbar button is wired and validated from the
    // start; the ones whose feature has not landed beep and are disabled by
    // `plannedActions` below. Each names the M1 step (spec §10) that fills it
    // in, so the stub and the work that replaces it are never in doubt.

    /// M1 step 7 — the clipboard shares the op table's delete/insert-time.
    @objc func cut(_ sender: Any?) { NSSound.beep() }
    /// M1 step 7.
    @objc func copy(_ sender: Any?) { NSSound.beep() }
    /// M1 step 7.
    @objc func paste(_ sender: Any?) { NSSound.beep() }
    /// M3 — nests.
    @objc func nestClips(_ sender: Any?) { NSSound.beep() }
    /// M3.
    @objc func unnestClips(_ sender: Any?) { NSSound.beep() }
    /// Add Text and Add Shape land in EditorViewController+AddClips.swift;
    /// these forward so the toolbar's and the menu's selectors stay the ones
    /// the frozen file declares.
    @objc func addTextClip(_ sender: Any?) { addTextClipAtPlayhead(sender) }
    @objc func addShapeClip(_ sender: Any?) { addShapeClipAtPlayhead(sender) }
    /// M3 — Consolidate Media.
    @objc func consolidateMedia(_ sender: Any?) { NSSound.beep() }
}

// MARK: - Timecode field

extension EditorViewController: NSTextFieldDelegate {
    /// Click-to-type on the timecode (spec §4.1). Parsing is the core's, so
    /// `1:23`, `83.5` and `1:23:04` all mean here what they mean everywhere
    /// else; anything it refuses beeps and the field snaps back.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === timecodeField,
              let document = document
        else { return }
        guard let ticks = ReelTime.parse(
            field.stringValue, fps: document.project.snapshot.canvas.fps)
        else {
            NSSound.beep()
            refreshTimecode()
            return
        }
        playback.pause()
        setPlayhead(ticks)
        view.window?.makeFirstResponder(view)
    }
}

// MARK: - Split view

extension EditorViewController: NSSplitViewDelegate {
    func splitView(
        _ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        if splitView === upperSplit {
            // The divider's coordinate is the canvas pane's width, so the
            // inspector's MAXIMUM is the canvas's minimum.
            return max(Self.minCanvasWidth, splitView.bounds.width - Self.maxInspectorWidth)
        }
        // The timeline may take at most 60 % of the window, so the top pane
        // keeps at least the remaining 40 % (and never less than its own
        // minimum).
        return max(Self.minUpperHeight, splitView.bounds.height * (1 - Self.maxTimelineFraction))
    }

    func splitView(
        _ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        if splitView === upperSplit {
            return max(
                Self.minCanvasWidth, splitView.bounds.width - Self.minInspectorWidth)
        }
        return max(
            Self.minUpperHeight, splitView.bounds.height - Self.minTimelineHeight)
    }

    /// Only the inspector collapses, and only through ⌥⌘I — a divider
    /// dragged to the edge should clamp at 280 pt, not vanish.
    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        subview === inspectorContainer
    }

    func splitView(
        _ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int
    ) -> Bool {
        false
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !isAdjustingPanes, didRestorePanes else { return }
        let defaults = UserDefaults.standard
        if !inspectorContainer.isHidden, inspectorContainer.bounds.width > 1 {
            defaults.set(Double(inspectorContainer.bounds.width), forKey: Self.inspectorWidthKey)
        }
        if timelineContainer.bounds.height > 1 {
            defaults.set(Double(timelineContainer.bounds.height), forKey: Self.timelineHeightKey)
        }
        layoutCanvas()
    }
}

// MARK: - Validation

extension EditorViewController: NSUserInterfaceValidations {
    /// Selectors whose feature has not landed yet. They stay visible and
    /// wired — so the menu is complete from the first build — but validate
    /// to false, exactly as Rasterize disables a `planned` tool.
    private static let plannedActions: Set<Selector> = [
        #selector(cut(_:)), #selector(copy(_:)), #selector(paste(_:)),
        #selector(nestClips(_:)), #selector(unnestClips(_:)),
        #selector(consolidateMedia(_:)),
    ]

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        guard document != nil else { return false }
        // A sheet is up (export, import): its captured state and the document
        // must not diverge, so every editor action is off.
        guard view.window?.attachedSheet == nil else { return false }
        guard let action = item.action else { return true }
        if Self.plannedActions.contains(action) { return false }

        let menuItem = item as? NSMenuItem
        switch action {
        case #selector(toggleLoop(_:)):
            menuItem?.state = loopEnabled ? .on : .off
        case #selector(toggleSafeAreas(_:)):
            menuItem?.state = safeGuidesVisible ? .on : .off
        case #selector(toggleSnapping(_:)):
            menuItem?.state = snappingEnabled ? .on : .off
        case #selector(setTrackHeight(_:)):
            menuItem?.state = menuItem?.tag == trackHeight ? .on : .off
        case #selector(toggleInspector(_:)):
            menuItem?.title = inspectorContainer.isHidden ? "Show Inspector" : "Hide Inspector"
        case #selector(clearInOutRange(_:)):
            return document?.inOutRange != nil
        case #selector(zoomIn(_:)):
            return canvasZoomIndex < Self.canvasZoomScales.count - 1
        case #selector(zoomOut(_:)):
            return canvasZoomIndex > 0
        case #selector(zoomToFit(_:)):
            return canvasZoomIndex != 0
        case #selector(playPause(_:)), #selector(goToStart(_:)), #selector(goToEnd(_:)),
            #selector(previousEditPoint(_:)), #selector(nextEditPoint(_:)):
            return (document?.project.duration ?? 0) > 0
        default:
            // The canvas, inspector, dialog and clip/track/marker commands
            // answer for themselves; nil means "not one of mine"
            // (EditorViewController+Canvas.swift, +Inspector.swift,
            // +Export.swift, +Timeline.swift).
            if let answer = validateExportAction(action, item: item) { return answer }
            if let answer = validateCanvasAction(action, item: item) { return answer }
            if let answer = validateInspectorAction(action, item: item) { return answer }
            if let answer = validateTimelineAction(action) { return answer }
        }
        return true
    }
}
