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

    static let toolbarHeight = DS.toolbarHeight
    /// The redesign's inspector width (`DS.panelWidth`, 304). The two clamps
    /// below are the window's, not the design's, and stay where they were.
    static let defaultInspectorWidth = DS.panelWidth
    static let minInspectorWidth: CGFloat = 280
    static let maxInspectorWidth: CGFloat = 440
    /// 300, not the 240 that predates the redesign: lane heights are per KIND
    /// now (`DS.trackHeights`), so a Medium text/video/audio stack is
    /// 44 + 84 + 60 pt of lanes plus 2 pt between each, the 22 pt ruler, the
    /// timeline's own 36 pt bar and 4 pt of lane inset top and bottom — 260 pt
    /// before a fourth track, against a 240 pt pane that clipped the last one.
    /// The DEFAULT only: the two clamps below and the persisted
    /// `timelineHeightKey` are untouched, so a pane the user has already sized
    /// keeps the size they gave it.
    static let defaultTimelineHeight: CGFloat = 300
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

    /// View ▸ Preview Window's panel, once it has been asked for (road map 2's
    /// phase 8b). A stored property is exactly what an extension cannot hold,
    /// which is why this one line is here and every other line of the feature
    /// is in `PreviewWindowController.swift`.
    ///
    /// It is here rather than on the DOCUMENT, and that is measured rather than
    /// stylistic: `addWindowController` would make the preview a second window
    /// controller, and AppKit only asks a document about saving when the LAST
    /// one closes — so closing the editor with a preview open would skip the
    /// save prompt on a dirty untitled project. That file's doc carries the
    /// probe.
    var previewWindow: PreviewWindowController?

    /// This window's assistant conversation (spec §11 AI-4: one per window,
    /// owned outside any view), once asked for; `+Assistant` holds the rest.
    /// Stored here for `previewWindow`'s reason: an extension cannot hold it.
    var assistant: AssistantSession?
    /// Its transcript, and the view drawing it (road map 12 A2): the view
    /// holds none of the conversation (AI-4), so both are kept here.
    let assistantTranscript = AssistantTranscript()
    weak var assistantView: AssistantView?

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
    //
    // The views only. `buildToolbar`, `refreshToolbarControls` and the cluster
    // metrics are `EditorViewController+Toolbar.swift`; an extension cannot add
    // stored properties, so these seven stay here and are internal for it.

    let timecodeField = NSTextField(string: "00:00:00:00")
    let durationLabel = NSTextField(labelWithString: "/ 00:00:00:00")
    var zoomPopup: OptionPopupControl!
    var safeToggle: OptionCheckboxControl!
    let playButton = GhostButton(
        symbol: "play", fallback: "▶", caption: nil, tooltip: "Play (Space)",
        action: #selector(playPause(_:)),
        size: EditorViewController.transportButtonSize,
        pointSize: EditorViewController.transportSymbolPointSize,
        cornerRadius: DS.buttonRadius)
    let pauseButton = GhostButton(
        symbol: "pause", fallback: "❚❚", caption: nil, tooltip: "Pause (Space)",
        action: #selector(playPause(_:)),
        size: EditorViewController.transportButtonSize,
        pointSize: EditorViewController.transportSymbolPointSize,
        cornerRadius: DS.buttonRadius)
    let loopButton = GhostButton(
        symbol: "repeat", fallback: "↻", caption: nil, tooltip: "Loop",
        action: #selector(toggleLoop(_:)),
        size: EditorViewController.transportButtonSize,
        pointSize: EditorViewController.transportSymbolPointSize,
        cornerRadius: DS.buttonRadius)

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
    /// The last rate-stretch tick that applied (`+SpeedAudio`).
    var lastLiveOps: [ReelOp] = []

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
        NotificationCenter.default.addObserver(
            self, selector: #selector(reversedMediaDidChange(_:)),
            name: .reversedMediaDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(graphicsDidChange(_:)),
            name: .projectGraphicsDidChange, object: nil)
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

    /// A reversed asset landed on disk. The plan is unchanged, so the §7.6
    /// rebuild rule would skip it: drop the item and let the refresh below
    /// rebuild (`ProjectDocument.reversedMediaDidChange`).
    @objc private func reversedMediaDidChange(_ note: Notification) {
        guard let document = document, note.object as? ProjectDocument === document else { return }
        playback.invalidate()
        publishedProject = nil
        refreshFromDocument(isLive: false)
    }

    /// The one path from a changed project to the preview. `isLive` rides
    /// straight through to `Playback`, which debounces structural rebuilds
    /// during a gesture (spec §7.6).
    /// **The guard is `editedProject`, not `project`** (road map 2's phase
    /// 9). It is an object-IDENTITY test, and entering or leaving a nest does
    /// not replace the document's handle — so with `project` on both sides
    /// the test is FALSE across a scope change and the player, the
    /// compositor's `RecipeSource` slot and `AudioDSPSource` would all go on
    /// showing the outer timeline while the timeline showed the nest.
    /// `ProjectDocument.editedProject` is memoised per parent handle, so the
    /// identity test still means what it always meant: two reads with nothing
    /// changed in between answer the same object.
    func refreshFromDocument(isLive: Bool) {
        guard let document = document else { return }
        applyLoopRange()
        let edited = document.editedProject
        if publishedProject !== edited {
            publishedProject = edited
            playback.update(project: edited, urls: document.mediaURLs(), isLive: isLive)
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
        // A failed rebuild is never fatal — the previous item keeps playing, or is dropped under
        // a held scope change, whose new time is kept (#185) — so it reports and stops there.
        NSApp.presentError(error)
    }

    func applyLoopRange() {
        guard loopEnabled else {
            playback.loopRange = nil
            return
        }
        if let range = document?.inOutRange, range.end > range.start {
            playback.loopRange = (start: range.start, duration: range.end - range.start)
        } else if let duration = document?.editedProject.duration, duration > 0 {
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
        // The EDITED project throughout the transport: with a nest open the
        // playhead is measured from the NEST's zero and the duration on the
        // readout is the nest's, which is what makes the number under the
        // scrubber agree with the bar the person is dragging.
        let canvas = document.editedProject.snapshot.canvas
        let frames = canvas.timecodeFrames
        if timecodeField.currentEditor() == nil {
            timecodeField.stringValue = ReelTime.format(
                document.playhead, fps: canvas.fps, frames: frames)
        }
        durationLabel.stringValue =
            "/ " + ReelTime.format(document.editedProject.duration, fps: canvas.fps, frames: frames)
    }

    /// Moves the playhead and the player together. Every tick reaching an op
    /// is snapped to the frame grid first (spec §6), and so is this one.
    func setPlayhead(_ time: Ticks) {
        guard let document = document else { return }
        let snapped = ReelTime.snapToFrame(
            max(0, time), fps: document.editedProject.snapshot.canvas.fps)
        document.playhead = snapped
        playback.seek(to: snapped)
        refreshTimecode()
        canvasPlayheadMoved()
        timelinePlayheadMoved()
        inspectorPlayheadMoved()
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
        setPlayhead(document?.editedProject.duration ?? 0)
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
        let snapshot = document.editedProject.snapshot
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

    /// Internal: the toolbar's zoom popup writes through it
    /// (EditorViewController+Toolbar.swift).
    func setCanvasZoom(_ index: Int) {
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

    /// Internal: the toolbar's Safe checkbox writes through it
    /// (EditorViewController+Toolbar.swift).
    func setSafeGuides(_ visible: Bool) {
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
        document.selection = Set(document.editedProject.snapshot.clips.map { $0.id })
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
            document.editedProject.snapshot.clips.filter { $0.start >= now }.map { $0.id })
        viewStateDidChange()
    }

    @objc func setInPoint(_ sender: Any?) {
        guard let document = document else { return }
        let end = document.inOutRange?.end ?? document.editedProject.duration
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

    /// The Add Shape button's menu (rectangle, ellipse, line, arrow) — the
    /// button is the timeline bar's since the chrome cleanup took clip actions
    /// out of the toolbar. Tags index `ShapeKind.allCases`, so the menu can
    /// never drift from the enum.
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
    ///
    /// Internal rather than private since road map 2's phase 8b: the preview
    /// window is a second window, so its content view is not in this
    /// controller's responder chain and has nowhere to send a bare Space or
    /// J/K/L. It hands the event here rather than carrying a second copy of the
    /// map (`PreviewWindowController.swift`), which is the one thing that could
    /// make the two windows' transports disagree.
    func handleEditorKey(_ event: NSEvent) -> Bool {
        if view.window?.firstResponder is NSText { return false }
        // And never while a sheet is attached — the same invariant
        // `validateUserInterfaceItem` opens with below, because this map is
        // not only transport: `t` adds a text clip, `w`/`e` trim, `m` marks,
        // `,`/`.` nudge, `i`/`o` write the range. A sheet captures a project
        // handle and reads it again later, so the document must not move
        // under it. Until phase 8b that held here for free and needed no line,
        // since a sheet takes the editor window's key status and this method
        // was simply unreachable while one was up. But a sheet is WINDOW-modal
        // rather than application-modal (measured: with one attached
        // `NSApp.modalWindow` is nil, and the preview panel is visible and
        // `canBecomeKey`), and the panel forwards its bare keys straight here,
        // where no validator stands — `t` added a text clip behind an open
        // export card that had already captured the project it was about to
        // write, and Remove Silences, which computes its spans ONCE, would
        // have rippled ranges that no longer described the timeline. The guard
        // belongs beside the key map rather than in the panel: both windows
        // inherit it, no second copy can drift, and the editor's own path pays
        // nothing for a case it cannot reach.
        if view.window?.attachedSheet != nil { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else {
            return false
        }
        guard EditorKey.isBare(flags, scalar: scalar.value) else { return false }
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
        case 27: return deselectActionCommand()
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
        // Bare Z arms the canvas region mode (road map 2's phase 3b, spec §9),
        // and it must stay BELOW the ⇧Z case: a `switch` matches in source
        // order, so a bare "z" above it would swallow Fit Timeline silently.
        // The command itself toggles, so Z is also the way back out
        // (EditorViewController+ZoomRegion.swift).
        case "z":
            zoomToRegion(nil)
        // ⇧ is still applied to `charactersIgnoringModifiers`, so ⇧, arrives
        // as "<" on a US layout — both spellings mean the same nudge.
        case ",", "<":
            nudgeSelection(frames: shift ? -10 : -1)
        case ".", ">":
            nudgeSelection(frames: shift ? 10 : 1)
        default:
            return false
        }
        return true
    }

    private func stepFrames(_ count: Int) {
        guard let document = document else { return }
        playback.stepFrames(count, fps: document.editedProject.snapshot.canvas.fps)
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
    /// ⌘G / ⇧⌘G — EditorViewController+Nest.swift.
    @objc func nestClips(_ sender: Any?) { nestSelection() }
    @objc func unnestClips(_ sender: Any?) { unnestSelection() }
    /// Clip ▸ Close Gap, Edit ▸ Insert / Overwrite at Playhead and Edit ▸
    /// Select All on Track — EditorViewController+Edge.swift. The two drags
    /// (⌥⇧ slip and roll) and the `,` / `.` nudge live there too and need no
    /// menu item of their own.
    @objc func closeGapAtPlayhead(_ sender: Any?) { closeGapAtPlayheadCommand() }
    @objc func insertMediaAtPlayhead(_ sender: Any?) { placeSelectedMedia(insert: true) }
    @objc func overwriteMediaAtPlayhead(_ sender: Any?) { placeSelectedMedia(insert: false) }
    @objc func selectAllClipsOnTrack(_ sender: Any?) { selectAllOnTrack() }
    /// ⌘X / ⌘C / ⌘V / ⌥⌘V — EditorViewController+Clipboard.swift.
    @objc func cut(_ sender: Any?) { cutSelection() }
    @objc func copy(_ sender: Any?) { copySelection() }
    @objc func paste(_ sender: Any?) { pasteClips() }
    @objc func pasteAttributes(_ sender: Any?) { pasteAttributes() }
    /// ⇧⌘R, Clip ▸ Label ▸ and Track ▸ Solo — EditorViewController+Identity.swift
    /// (Solo's body is `toggleTrack` in +Timeline.swift, beside its siblings).
    @objc func renameClip(_ sender: Any?) { renameClipCommand() }
    @objc func setClipLabel(_ sender: Any?) { setClipLabelCommand(sender) }
    @objc func toggleTrackSolo(_ sender: Any?) { toggleTrack(.solo) }

    // MARK: - Forwards into feature files
    //
    // Every menu item and toolbar button is wired and validated from the
    // start. Anything whose feature has not landed yet beeps and is disabled
    // by `plannedActions` below; nothing is in that state today.

    /// Add Text and Add Shape land in EditorViewController+AddClips.swift;
    /// these forward so the toolbar's and the menu's selectors stay the ones
    /// the frozen file declares.
    @objc func addTextClip(_ sender: Any?) { addTextClipAtPlayhead(sender) }
    @objc func addShapeClip(_ sender: Any?) { addShapeClipAtPlayhead(sender) }
    /// File ▸ Consolidate Media… — EditorViewController+Consolidate.swift.
    @objc func consolidateMedia(_ sender: Any?) { consolidateMediaCommand() }
    /// File ▸ Import Captions… — CaptionImporter.swift.
    @objc func importCaptions(_ sender: Any?) { importCaptionsCommand() }
    /// Clip ▸ Remove Silences… — the body and its validator are at the foot of
    /// SilenceSheetController.swift, beside the sheet they open, exactly as
    /// Import Captions' are at the foot of CaptionImporter.swift.
    ///
    /// Zoom to Region and Zoom Back need no forward here: both are declared
    /// `@objc` on `extension EditorViewController` in
    /// EditorViewController+ZoomRegion.swift (`pickChromaKey`'s precedent),
    /// and a second declaration in this file would be a redeclaration, not a
    /// forward.
    @objc func removeSilences(_ sender: Any?) { removeSilencesCommand() }
    /// File ▸ Generate Captions… — the body and its validator are at the foot
    /// of TranscribeSheetController+Commit.swift, and File ▸ Export Captions…' are at
    /// the foot of CaptionExporter.swift: the same rule as Import Captions'
    /// and Remove Silences', a command living beside the feature it opens.
    @objc func generateCaptions(_ sender: Any?) { generateCaptionsCommand() }
    @objc func exportCaptions(_ sender: Any?) { exportCaptionsCommand() }

    /// Clip ▸ Normalize (road map 2 phase 5c) — the menu half of the Audio
    /// section's Normalize button.
    ///
    /// **Not a line of the arithmetic is here**, which is the whole point of
    /// `AudioNormalize` being a value type: this reads no peaks and derives no
    /// gain, it calls the same `read` + `plan` pair `AudioPane.normalize` and
    /// the agent's `normalize_clip` call, so the three cannot mean different
    /// things. What reaches the document is one ordinary `set_audio` per clip
    /// — each clip gets its own measured gain — committed as ONE undo step.
    ///
    /// The body is HERE rather than at the foot of the file that owns the
    /// feature, which is the rule Remove Silences… and the two caption
    /// commands follow. `AudioNormalize.swift` is a pure value type with no
    /// `EditorViewController` extension in it, and phase 5's file allocation
    /// gave this handful of lines no other home; a second sound command should
    /// take them both into an `EditorViewController+Audio.swift` beside the
    /// plan they commit rather than growing this file further.
    ///
    /// The scope is `AudioNormalize.canOffer` — `AudioPane.normalizable`'s
    /// scope exactly, and the same question the validator arm below asks — so a
    /// shape, a silent movie or a NEST picked alongside is simply not asked
    /// about instead of coming back as a refusal the user did not cause. It is
    /// `InspectorTab.hasAudio` and not that alone: a nest carrying anything
    /// audible has audio properties of its own, so `hasAudio` says yes about a
    /// clip the plan flattens and `read` can only refuse. `canOffer` is the one
    /// home of that rule, and the button, this command and this file's
    /// validator arm all ask it, or two of the three would disagree about one
    /// selection.
    ///
    /// Two different things beep, and both are correct. A selection nothing can
    /// be measured in produces no ops, and a second press on an
    /// already-normalised selection produces ops that change nothing: the first
    /// is an empty list and the second an identity edit, and `applyEdit` refuses
    /// both without registering an undo step. The menu is not the place that
    /// explains WHY a clip was skipped; `normalize_clip` reports each reason by
    /// name under `skipped`.
    @objc func normalizeClips(_ sender: Any?) {
        guard let document = document else { return }
        let snapshot = document.editedProject.snapshot
        let ids = selectedClips.filter { AudioNormalize.canOffer($0, in: snapshot) }.map { $0.id }
        guard !ids.isEmpty, let input = AudioNormalize.read(from: document, clips: ids) else {
            NSSound.beep()
            return
        }
        document.applyEdit("Normalize", AudioNormalize.plan(input).ops)
    }
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
            field.stringValue, fps: document.editedProject.snapshot.canvas.fps)
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
    ///
    /// Empty since ⌘G / ⇧⌘G landed (EditorViewController+Nest.swift), which
    /// were the last two. The mechanism stays for the next unfinished
    /// command; an empty set is the honest way to say there is not one.
    private static let plannedActions: Set<Selector> = []

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
            return (document?.editedProject.duration ?? 0) > 0
        case #selector(normalizeClips(_:)):
            // The arm belongs here rather than in a `validate…Action` helper
            // because the command's body is in this file too (above); it is
            // load-bearing all the same. Without it Clip ▸ Normalize falls
            // through to the closing `return true` and is live on a selection
            // it could only beep at.
            //
            // It asks the command's own question of the MEMOIZED snapshot, not
            // of the plan: a validator runs on every menu open, and
            // `ReelProject.plan` decodes JSON on every access. The plan is
            // still the honest answer to "does this clip make a sound", and
            // `AudioNormalize.read` asks it — a clip enabled here but with no
            // audio segment is reported under `skipped` rather than silently
            // dropped, which is the right side to be wrong on.
            //
            // `AudioNormalize.canOffer` and not `InspectorTab.hasAudio`: a
            // nest carrying anything audible has audio properties of its own,
            // so `hasAudio` says yes about the one clip `read` can ONLY refuse
            // (the plan flattens a nest, so the clip has no segment of its
            // own). The Audio pane's button asks the same function through
            // `AudioPane.normalizable`, which is what keeps a greyed button
            // and a live menu item from disagreeing about one selection.
            guard let snapshot = document?.editedProject.snapshot else { return false }
            return selectedClips.contains { AudioNormalize.canOffer($0, in: snapshot) }
        default:
            // The canvas, inspector, dialog and clip/track/marker commands
            // answer for themselves; nil means "not one of mine"
            // (EditorViewController+Canvas.swift, +Inspector.swift,
            // +Export.swift, +Timeline.swift, +Nest.swift).
            // Phase 9's arm goes FIRST, because it is the only one that
            // overrides another file's answer: it turns the three marker
            // commands off while a nest is open, and `validateTimelineAction`
            // below would otherwise answer them.
            if let answer = validateNestScopeAction(action) { return answer }
            if let answer = validateNestAction(action) { return answer }
            if let answer = validateClipboardAction(action) { return answer }
            if let answer = validateConsolidateAction(action) { return answer }
            if let answer = validateExportAction(action, item: item) { return answer }
            if let answer = validateCanvasAction(action, item: item) { return answer }
            if let answer = validateInspectorAction(action, item: item) { return answer }
            if let answer = validateTimelineAction(action) { return answer }
            if let answer = validateEdgeAction(action) { return answer }
            if let answer = validateIdentityAction(action, item: item) { return answer }
            if let answer = validateMotionAction(action, item: item) { return answer }
            if let answer = validateLookAction(action, item: item) { return answer }
            if let answer = validateBackgroundAction(action) { return answer }
            if let answer = validateSaveFrameAction(action) { return answer }
            if let answer = validatePreviewQualityAction(action, item: item) { return answer }
            if let answer = validatePreviewWindowAction(action, item: item) { return answer }
            if let answer = validateSeeingAction(action, item: item) { return answer }
            if let answer = validateGraphicMenuAction(action) { return answer }
            if let answer = validateAdjustmentAction(action) { return answer }
            // The arms whose files are not `EditorViewController+…`: Remove
            // Silences' body and validator live at the foot of
            // SilenceSheetController.swift, beside the sheet, and phase 4's
            // two caption commands follow the same rule from the feet of
            // TranscribeSheetController+Commit.swift and CaptionExporter.swift.
            //
            // Both caption arms are load-bearing, not decoration. Without
            // them the two items fall through to `return true` and are
            // enabled on a timeline where they can only beep — Generate
            // Captions… on a project with no audible media clip, Export
            // Captions… on one with no all-text track. Each arm asks the
            // cheap snapshot question its command's own guard asks, so the
            // menu and the command can never disagree.
            if let answer = validateSilenceAction(action) { return answer }
            if let answer = validateTranscribeAction(action) { return answer }
            if let answer = validateCaptionExportAction(action) { return answer }
        }
        return true
    }
}
