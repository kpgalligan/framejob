import AppKit

/// The timeline pane (spec §4.4): a toolbar row over one `NSScrollView`
/// whose document view draws the ruler, the lanes and the clips.
///
/// **Wiring and drawing only.** Every conversion is `TimelineLayout`'s and
/// every gesture's arithmetic is a session struct in `TimelineSessions.swift`;
/// what lives here is the view tree, the hit test, the paint, and the
/// dispatch from a mouse event to the session that owns it. The controller
/// pushes state in (`update`, `setPlayhead`) and receives intent back through
/// the `on*` closures — it, not this view, owns the document.
///
/// The header column and the ruler are floating subviews of the document
/// view, repositioned to the visible rectangle's origin whenever the clip
/// view's bounds change, so the headers stay put horizontally and the ruler
/// vertically. Both refuse to be hit themselves (`hitTest` returns nil unless
/// a real subview — an inline rename field — is under the point), which is
/// what lets `TimelineContentView` own ALL the mouse handling instead of
/// three views each re-deriving what is under the pointer.
final class TimelineView: NSView, NSTextFieldDelegate {
    static let toolbarHeight: CGFloat = 32

    // MARK: - State pushed in by the controller

    private(set) var snapshot = ProjectSnapshot.empty
    private(set) var selection: Set<UInt32> = []
    private(set) var playhead: Ticks = 0
    private(set) var inOutRange: (start: Ticks, end: Ticks)?
    private(set) var cacheDirectory: URL?

    /// Snapping (N) and the track height live on the controller — the menu,
    /// this toolbar and the canvas all have to read one flag — so they are
    /// pushed in and pushed back out through closures.
    var snappingEnabled = true {
        didSet { snapToggle?.refresh() }
    }

    var trackHeightIndex = 1 {
        didSet {
            guard trackHeightIndex != oldValue else { return }
            heightControl?.refresh()
            rebuildLayout()
        }
    }

    /// Points per second.
    private(set) var zoom = TimelineLayout.defaultZoom

    private(set) var layout = TimelineLayout()

    // MARK: - Intent out

    var onSelectionChanged: ((Set<UInt32>) -> Void)?
    /// A scrub: the playhead is view state, so this never becomes an op.
    var onScrub: ((Ticks) -> Void)?
    var onLiveBegin: (() -> Void)?
    var onLiveUpdate: (([ReelOp]) -> Void)?
    var onLiveEnd: ((String) -> Void)?
    /// A one-shot edit (a header toggle, a rename) as one undo step.
    var onEdit: ((String, [ReelOp]) -> Void)?
    /// Applies ops to the current handle PURELY and hands back the result,
    /// only so a gesture can learn the ids the core is about to mint for a
    /// `duplicate` or an `add_track`. Nothing is mutated and no undo step is
    /// registered — `applying` is pure (spec §5.5), so this is a question.
    var onProbe: (([ReelOp]) -> ProjectSnapshot?)?
    /// `snapCandidates(excluding:)`, asked once per gesture — never per
    /// refresh: it is an FFI round-trip and a selection change would
    /// otherwise pay for one on every mouse-moved.
    var onSnapCandidates: (([UInt32]) -> [Ticks])?
    var onSnappingToggled: (() -> Void)?
    var onTrackHeightChanged: ((Int) -> Void)?

    // MARK: - Views

    private let scrollView = NSScrollView()
    let content = TimelineContentView()
    let ruler = TimelineRulerView()
    let headers = TimelineHeaderView()
    private var snapToggle: OptionCheckboxControl?
    private var heightControl: OptionSegmentedControl?
    private let zoomSlider = NSSlider(
        value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)

    /// Content-space origin of the two floating bands, refreshed on every
    /// scroll. The hit test needs them: the ruler is only "the ruler" where
    /// it is currently drawn.
    private(set) var pinnedX: CGFloat = 0
    private(set) var pinnedY: CGFloat = 0

    // MARK: - Gesture sessions (one stored property each)

    var clipDrag: ClipDragSession?
    var trim: TrimSession?
    var marquee: RangeSession?
    var scrub: PlayheadSession?
    var markerDrag: MarkerDragSession?
    var fadeDrag: FadeHandleSession?
    var trackDrag: TrackDragSession?

    /// The handle a clip drag started from, kept because the live preview
    /// changes `snapshot` under the gesture (a previewed `add_track` restacks
    /// every row) and the row → track mapping must not move with it.
    private var dragBase: ProjectSnapshot?
    private var dragSnapper = TimelineSnapper(
        fps: .thirty, candidates: [], threshold: 1, enabled: false)

    /// The ghost drawn while a refused drop springs back (spec §4.4).
    private(set) var refusal: (from: CGRect, to: CGRect, progress: CGFloat)?
    private var refusalTimer: Timer?

    /// Thumbnails and peaks, kept off the draw path's disk.
    let caches = TimelineCaches()

    /// The inline editor used for a track or marker rename.
    private var renameField: NSTextField?
    private var renameCommit: ((String) -> Void)?

    // MARK: - Life cycle

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = DS.chromeBackground.cgColor

        let toolbar = buildToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)

        content.timeline = self
        ruler.timeline = self
        headers.timeline = self
        content.addSubview(ruler)
        content.addSubview(headers)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = DS.timelineLane
        scrollView.documentView = content
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: Self.toolbarHeight),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewMoved(_:)),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewResized(_:)),
            name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(mediaCacheChanged(_:)),
            name: .mediaCacheDidChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TimelineView does not support NSCoder")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        refusalTimer?.invalidate()
    }

    // NOTE: there is deliberately no `layout()` override — the property
    // `layout` (the metrics) already owns that name, and the two things a
    // resize has to do arrive as clip-view notifications anyway: a bounds
    // change is a scroll (re-pin the floating bands), a frame change is a
    // resize (rebuild the content size).

    // MARK: - Toolbar (spec §4.4's row)

    private func buildToolbar() -> NSView {
        let bar = BarView(border: .bottom)

        let actions = NSStackView(views: [
            GhostButton(
                symbol: "scissors", fallback: "✂", caption: nil, tooltip: "Split (⌘T)",
                action: #selector(EditorViewController.splitAtPlayhead(_:))),
            GhostButton(
                symbol: "arrow.right.to.line", fallback: "⇥", caption: nil,
                tooltip: "Trim Start to Playhead (W)",
                action: #selector(EditorViewController.trimStartToPlayhead(_:))),
            GhostButton(
                symbol: "arrow.left.to.line", fallback: "⇤", caption: nil,
                tooltip: "Trim End to Playhead (E)",
                action: #selector(EditorViewController.trimEndToPlayhead(_:))),
            GhostButton(
                symbol: "delete.left", fallback: "⌫", caption: nil,
                tooltip: "Ripple Delete (⌘⌫)",
                action: #selector(EditorViewController.rippleDeleteClips(_:))),
            GhostButton(
                symbol: "bookmark", fallback: "◆", caption: nil, tooltip: "Add Marker (M)",
                action: #selector(EditorViewController.addMarker(_:))),
        ])
        actions.orientation = .horizontal
        actions.spacing = 2

        let snap = OptionCheckboxControl(
            label: "Snap",
            read: { [weak self] in self?.snappingEnabled ?? false },
            write: { [weak self] _ in self?.onSnappingToggled?() },
            enabled: { true },
            onEdit: { [weak self] in self?.snapToggle?.refresh() })
        snapToggle = snap

        // The one raw AppKit control in the app's chrome: spec §4.4 asks for
        // a zoom SLIDER and `OptionControls.swift` (which is Rasterize's, and
        // stays in sync with it) has no slider to borrow.
        zoomSlider.target = self
        zoomSlider.action = #selector(zoomSliderChanged(_:))
        zoomSlider.isContinuous = true
        zoomSlider.controlSize = .small
        zoomSlider.toolTip = "Timeline Zoom"
        zoomSlider.widthAnchor.constraint(equalToConstant: 108).isActive = true

        let height = OptionSegmentedControl(
            segments: [
                (symbol: "reelcut.small", fallback: "S", tooltip: "Small tracks"),
                (symbol: "reelcut.medium", fallback: "M", tooltip: "Medium tracks"),
                (symbol: "reelcut.large", fallback: "L", tooltip: "Large tracks"),
            ],
            read: { [weak self] in self?.trackHeightIndex ?? 1 },
            write: { [weak self] index in self?.onTrackHeightChanged?(index) },
            segmentEnabled: nil, enabled: { true },
            onEdit: { [weak self] in self?.heightControl?.refresh() })
        heightControl = height

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(1), for: .horizontal)

        let row = NSStackView(views: [
            actions, snap, spacer, zoomSlider,
            GhostButton(
                symbol: "arrow.left.and.right", fallback: "⇔", caption: nil,
                tooltip: "Fit Timeline (⇧Z)",
                action: #selector(EditorViewController.fitTimeline(_:))),
            height,
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        bar.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    // MARK: - State in

    /// The one path from a changed project to the timeline. The controller
    /// calls it from `refreshFromDocument`, so a live gesture's every tick
    /// lands here too — which is exactly what makes the drag preview the
    /// core's own answer rather than a drawing of one.
    func update(
        snapshot: ProjectSnapshot, selection: Set<UInt32>, playhead: Ticks,
        inOutRange: (start: Ticks, end: Ticks)?, cacheDirectory: URL?
    ) {
        self.snapshot = snapshot
        self.selection = selection
        self.playhead = playhead
        self.inOutRange = inOutRange
        self.cacheDirectory = cacheDirectory
        rebuildLayout()
    }

    /// The cheap path: playback moves the playhead 30 times a second and
    /// nothing else changes.
    func setPlayhead(_ time: Ticks) {
        guard time != playhead else { return }
        playhead = time
        revealPlayhead()
        content.needsDisplay = true
        ruler.needsDisplay = true
    }

    // MARK: - Layout

    func rebuildLayout() {
        var next = TimelineLayout()
        next.canvas = snapshot.canvas
        next.trackCount = snapshot.tracks.count
        next.heightIndex = trackHeightIndex
        next.zoom = zoom
        next.duration = snapshot.duration
        next.viewport = scrollView.contentView.bounds.size
        layout = next

        let size = NSSize(width: layout.contentWidth, height: layout.contentHeight)
        if content.frame.size != size {
            content.frame = NSRect(origin: .zero, size: size)
        }
        pinFloatingBands()
        content.needsDisplay = true
        zoomSlider.doubleValue = Double(Self.sliderValue(for: zoom))
        window?.invalidateCursorRects(for: content)
    }

    /// Spec §4.4's "pinned in `scroll(_:)`": AppKit delivers a scroll as a
    /// bounds change on the clip view, and this is the handler.
    private func pinFloatingBands() {
        let visible = scrollView.contentView.bounds
        pinnedX = max(visible.minX, 0)
        pinnedY = max(visible.minY, 0)
        ruler.frame = NSRect(
            x: 0, y: pinnedY, width: layout.contentWidth, height: TimelineLayout.rulerHeight)
        headers.frame = NSRect(
            x: pinnedX, y: TimelineLayout.rulerHeight, width: TimelineLayout.headerWidth,
            height: max(layout.contentHeight - TimelineLayout.rulerHeight, 0))
        ruler.needsDisplay = true
        headers.needsDisplay = true
    }

    @objc private func clipViewMoved(_ note: Notification) {
        pinFloatingBands()
    }

    /// The pane was resized: the content size (and so a Fit zoom) depends on
    /// the viewport, so the whole layout is rebuilt rather than re-pinned.
    @objc private func clipViewResized(_ note: Notification) {
        rebuildLayout()
    }

    @objc private func mediaCacheChanged(_ note: Notification) {
        guard let media = note.userInfo?[MediaImporter.mediaIDKey] as? UInt32 else { return }
        let kind = note.userInfo?[MediaImporter.cacheKindKey] as? String
        caches.invalidate(media: media, kind: kind)
        content.needsDisplay = true
    }

    // MARK: - Zoom and scrolling

    static func sliderValue(for zoom: CGFloat) -> CGFloat {
        let span = log(TimelineLayout.maxZoom / TimelineLayout.minZoom)
        return min(max(log(zoom / TimelineLayout.minZoom) / span, 0), 1)
    }

    static func zoom(forSlider value: CGFloat) -> CGFloat {
        let span = log(TimelineLayout.maxZoom / TimelineLayout.minZoom)
        return TimelineLayout.minZoom * exp(min(max(value, 0), 1) * span)
    }

    @objc private func zoomSliderChanged(_ sender: NSSlider) {
        let anchor = scrollView.contentView.bounds.midX
        setZoom(Self.zoom(forSlider: CGFloat(sender.doubleValue)), anchoredAt: anchor)
    }

    /// Zooms about a content-space x, keeping the time under it in place —
    /// what a pinch and ⌘= expect and what a naive "set the zoom" never does.
    func setZoom(_ next: CGFloat, anchoredAt anchorX: CGFloat) {
        let clamped = min(max(next, TimelineLayout.minZoom), TimelineLayout.maxZoom)
        guard abs(clamped - zoom) > 0.0001 else { return }
        let time = layout.time(atX: anchorX)
        let offset = anchorX - scrollView.contentView.bounds.minX
        zoom = clamped
        rebuildLayout()
        scroll(toX: layout.x(for: time) - offset)
    }

    /// ⇧Z — the whole project across the window (spec §4.4).
    func fit() {
        let width = scrollView.contentView.bounds.width
        guard width > 40 else { return }
        zoom = TimelineLayout.fitZoom(duration: snapshot.duration, width: width)
        rebuildLayout()
        scroll(toX: 0)
    }

    private func scroll(toX x: CGFloat) {
        let clip = scrollView.contentView
        let maxX = max(layout.contentWidth - clip.bounds.width, 0)
        clip.scroll(to: NSPoint(x: min(max(x, 0), maxX), y: clip.bounds.minY))
        scrollView.reflectScrolledClipView(clip)
        pinFloatingBands()
    }

    /// Auto-scroll: keeps the playhead in view while it runs (spec §4.4).
    private func revealPlayhead() {
        let clip = scrollView.contentView
        let x = layout.x(for: playhead)
        let left = clip.bounds.minX + TimelineLayout.headerWidth + 24
        let right = clip.bounds.maxX - 24
        guard x < left || x > right else { return }
        scroll(toX: x - TimelineLayout.headerWidth - clip.bounds.width * 0.35)
    }

    // MARK: - Refusal

    /// A drop the core refused springs back instead of just beeping
    /// (spec §4.4). The ghost is drawn by `TimelineContentView`; this only
    /// runs the clock.
    func flashRefusal(from: CGRect, to: CGRect) {
        refusalTimer?.invalidate()
        refusal = (from: from, to: to, progress: 0)
        let started = Date()
        refusalTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) {
            [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            let progress = CGFloat(Date().timeIntervalSince(started) / 0.22)
            if progress >= 1 {
                timer.invalidate()
                self.refusalTimer = nil
                self.refusal = nil
            } else {
                self.refusal?.progress = progress
            }
            self.content.needsDisplay = true
        }
    }

    // MARK: - Inline rename

    /// One editor for both renames (a track header, a marker). It is a real
    /// subview of the floating band it edits, which is why those bands let
    /// their subviews be hit even though they refuse hits themselves.
    func beginRename(
        in host: NSView, frame: NSRect, text: String, commit: @escaping (String) -> Void
    ) {
        endRename()
        let field = NSTextField(string: text)
        field.frame = frame
        field.font = DS.sans(11)
        field.isBordered = true
        field.isBezeled = true
        field.drawsBackground = true
        field.focusRingType = .none
        field.delegate = self
        host.addSubview(field)
        renameField = field
        renameCommit = commit
        window?.makeFirstResponder(field)
    }

    private func endRename() {
        renameField?.removeFromSuperview()
        renameField = nil
        renameCommit = nil
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === renameField else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let commit = renameCommit
        endRename()
        // Back to the editor's root view: it is what holds the bare-key map
        // (Space, W, E …), and leaving the window itself as first responder
        // would silently drop every one of them.
        window?.makeFirstResponder(window?.contentView)
        guard !value.isEmpty else { return }
        commit?(value)
    }

    // MARK: - Gestures

    /// Everything a session needs to snap, built once per gesture so the
    /// candidate list is not re-fetched from the core on every mouse-moved.
    private func makeSnapper(excluding clips: [UInt32], suppressed: Bool) -> TimelineSnapper {
        let core = onSnapCandidates?(clips) ?? []
        return TimelineSnapper(
            fps: snapshot.canvas.fps,
            candidates: TimelineSnapper.candidates(
                core: core, playhead: playhead, range: inOutRange),
            threshold: layout.snapThreshold,
            enabled: snappingEnabled && !suppressed)
    }

    /// Mouse-down. Picks the session that owns the hit and starts it; a click
    /// that only changes the selection starts none.
    func beginGesture(
        hit: TimelineHit, at point: CGPoint, flags: NSEvent.ModifierFlags, clicks: Int
    ) {
        endRename()
        let suppressed = flags.contains(.command)
        switch hit {
        case .none, .corner:
            break

        case .ruler(let time):
            var session = PlayheadSession(time: time, wasPlaying: false)
            dragSnapper = makeSnapper(excluding: [], suppressed: suppressed)
            session.update(time: time, snapper: dragSnapper)
            scrub = session
            onScrub?(session.time)

        case .marker(let id):
            guard let marker = snapshot.marker(id) else { break }
            if clicks == 2 {
                renameMarker(marker)
                break
            }
            dragSnapper = makeSnapper(excluding: [], suppressed: suppressed)
            markerDrag = MarkerDragSession(marker: id, original: marker.time, time: marker.time)
            onLiveBegin?()

        case .header(let row):
            guard let track = track(atRow: row) else { break }
            if clicks == 2 {
                renameTrack(track, row: row)
                break
            }
            trackDrag = TrackDragSession(
                track: track.id, originalRow: row, trackCount: snapshot.tracks.count, row: row)

        case .headerButton(let row, let button):
            toggleHeader(button, row: row)

        case .clip(let id):
            selectClip(id, flags: flags)
            beginClipDrag(anchor: id, at: point, flags: flags)

        case .clipEdge(let id, let edge):
            selectClip(id, flags: flags)
            beginTrim(id, edge: edge, flags: flags)

        case .fade(let id, let edge):
            guard let clip = snapshot.clip(id) else { break }
            let props = clip.audioProps
            fadeDrag = FadeHandleSession(
                clip: id, edge: edge, clipStart: clip.start, clipEnd: clip.end,
                length: edge == .start ? props.fadeIn : props.fadeOut)
            onLiveBegin?()

        case .lane(_, _):
            if !flags.contains(.shift), !selection.isEmpty {
                selection = []
                onSelectionChanged?(selection)
            }
            marquee = RangeSession(
                origin: point, additive: flags.contains(.shift), base: selection, current: point)
        }
        content.needsDisplay = true
    }

    /// Mouse-dragged. Exactly one session is live; each one turns the pointer
    /// into its own ops and pushes them at the document as a live edit.
    func continueGesture(at point: CGPoint, flags: NSEvent.ModifierFlags) {
        let time = layout.time(atX: point.x)
        // ⌘ suppresses snapping while the drag is in flight, not only at the
        // press — and the threshold follows a mid-drag zoom. Only the flags
        // and the radius are rebuilt; the candidate list stays the one the
        // gesture fetched, so this costs nothing.
        dragSnapper = TimelineSnapper(
            fps: dragSnapper.fps, candidates: dragSnapper.candidates,
            threshold: layout.snapThreshold,
            enabled: snappingEnabled && !flags.contains(.command))
        if var session = scrub {
            session.update(time: time, snapper: dragSnapper)
            scrub = session
            onScrub?(session.time)
        } else if var session = clipDrag {
            // Rows are read from the layout the gesture STARTED with: a
            // previewed `add_track` restacks the live one under the pointer.
            var base = layout
            base.trackCount = session.trackCount
            session.update(time: time, row: base.unclampedRow(atY: point.y), snapper: dragSnapper)
            clipDrag = session
            onLiveUpdate?(session.ops(destination: destination(for: session)))
        } else if var session = trim {
            session.update(time: time, snapper: dragSnapper)
            trim = session
            onLiveUpdate?([session.op])
        } else if var session = markerDrag {
            session.update(time: time, snapper: dragSnapper)
            markerDrag = session
            onLiveUpdate?([session.op])
        } else if var session = fadeDrag {
            session.update(time: time, fps: snapshot.canvas.fps)
            fadeDrag = session
            onLiveUpdate?([session.op])
        } else if var session = marquee {
            session.current = point
            marquee = session
            selection = session.selection(in: snapshot, layout: layout)
            onSelectionChanged?(selection)
        } else if var session = trackDrag {
            session.update(row: layout.unclampedRow(atY: point.y))
            trackDrag = session
        }
        content.needsDisplay = true
    }

    /// Mouse-up. Closes the live edit as ONE undo step, and springs a refused
    /// drop back to where it came from.
    func endGesture(at point: CGPoint, flags: NSEvent.ModifierFlags) {
        if scrub != nil {
            scrub = nil
        } else if let session = clipDrag {
            clipDrag = nil
            onLiveEnd?(session.duplicating ? "Duplicate Clips" : "Move Clips")
            checkRefusal(of: session)
            dragBase = nil
        } else if let session = trim {
            trim = nil
            onLiveEnd?(session.isRateStretch ? "Rate Stretch" : "Trim Clip")
        } else if markerDrag != nil {
            markerDrag = nil
            onLiveEnd?("Move Marker")
        } else if fadeDrag != nil {
            fadeDrag = nil
            onLiveEnd?("Set Fade")
        } else if marquee != nil {
            marquee = nil
        } else if let session = trackDrag {
            trackDrag = nil
            if let op = session.op, session.didMove {
                onEdit?("Reorder Track", [op])
            }
        }
        content.needsDisplay = true
        headers.needsDisplay = true
    }

    /// Compares what the drag asked for with what the core did. `onLiveEnd`
    /// has already published, so `snapshot` is the answer.
    private func checkRefusal(of session: ClipDragSession) {
        // A drop that asked for a new track lands on a row that did not exist
        // when the drag started, so there is nothing to compare — and a drop
        // that duplicated moved the copies, not the anchor.
        guard session.didMove, !session.duplicating, !session.needsNewTrack,
              let clip = snapshot.clip(session.anchor),
              let index = snapshot.trackIndex(of: clip.track)
        else { return }
        let landedRow = layout.row(forTrackIndex: index)
        guard clip.start != session.proposedStart || landedRow != session.row else { return }
        let row = min(max(session.row, 0), max(layout.trackCount - 1, 0))
        var ghost = layout.clipRect(clip, row: row)
        ghost.origin.x = layout.x(for: session.proposedStart)
        flashRefusal(from: ghost, to: layout.clipRect(clip, row: landedRow))
    }

    private func beginClipDrag(anchor: UInt32, at point: CGPoint, flags: NSEvent.ModifierFlags) {
        guard let clip = snapshot.clip(anchor),
              let index = snapshot.trackIndex(of: clip.track),
              !snapshot.tracks[index].locked
        else { return }
        let ids = selection.contains(anchor) ? Array(selection) : [anchor]
        let dragged = snapshot.clips.filter { ids.contains($0.id) }
        guard !dragged.isEmpty else { return }
        let duplicating = flags.contains(.option)

        // Every id the ops will need, probed against the handle the gesture
        // is about to snapshot — the ONE moment the current project and the
        // live-edit base are the same thing.
        let existingClips = Set(snapshot.clips.map { $0.id })
        let existingTracks = Set(snapshot.tracks.map { $0.id })
        var copies: [UInt32] = []
        var copyShift: Ticks = 0
        var prefix: [ReelOp] = []
        if duplicating {
            let probed = onProbe?([.duplicate(clips: ids)])
            let made = (probed?.clips ?? []).filter { !existingClips.contains($0.id) }
                .sorted { $0.start < $1.start }
            if !made.isEmpty {
                copies = made.map { $0.id }
                let from = dragged.map { $0.start }.min() ?? 0
                copyShift = (made.map { $0.start }.min() ?? from) - from
                prefix = [.duplicate(clips: ids)]
            }
        }
        let count = snapshot.tracks.count
        let top = probeTrack(prefix + [.addTrack(index: count)], existing: existingTracks)
        let bottom = probeTrack(prefix + [.addTrack(index: 0)], existing: existingTracks)

        dragBase = snapshot
        dragSnapper = makeSnapper(excluding: ids, suppressed: flags.contains(.command))
        clipDrag = ClipDragSession(
            clips: ids, anchor: anchor, anchorStart: clip.start,
            anchorRow: layout.row(forTrackIndex: index),
            grabTime: layout.time(atX: point.x),
            spanStart: dragged.map { $0.start }.min() ?? clip.start,
            trackCount: count, duplicating: !copies.isEmpty, copies: copies, copyShift: copyShift,
            newTrackTop: top, newTrackBottom: bottom,
            row: layout.row(forTrackIndex: index))
        onLiveBegin?()
    }

    private func probeTrack(_ ops: [ReelOp], existing: Set<UInt32>) -> UInt32? {
        guard let probed = onProbe?(ops) else { return nil }
        return probed.tracks.first { !existing.contains($0.id) }?.id
    }

    private func beginTrim(_ id: UInt32, edge: TimelineEdge, flags: NSEvent.ModifierFlags) {
        guard let clip = snapshot.clip(id),
              let index = snapshot.trackIndex(of: clip.track),
              !snapshot.tracks[index].locked
        else { return }
        let frame = max(snapshot.canvas.fps.frameDuration, 1)
        dragSnapper = makeSnapper(excluding: [id], suppressed: flags.contains(.command))
        trim = TrimSession(
            clip: id, edge: edge,
            stretch: flags.contains(.option) && clip.source.hasSourceBound,
            originalStart: clip.start, originalEnd: clip.end, frame: frame,
            time: edge == .start ? clip.start : clip.end)
        onLiveBegin?()
    }

    /// The destination track id for the row a drag is over, or nil to leave
    /// every clip on its own track. Read from the gesture's base handle.
    private func destination(for session: ClipDragSession) -> UInt32? {
        guard let base = dragBase, session.row != session.anchorRow,
              (0..<base.tracks.count).contains(session.row)
        else { return nil }
        return base.tracks[base.tracks.count - 1 - session.row].id
    }

    private func selectClip(_ id: UInt32, flags: NSEvent.ModifierFlags) {
        if flags.contains(.shift) {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        } else if !selection.contains(id) {
            selection = [id]
        }
        onSelectionChanged?(selection)
    }

    private func toggleHeader(_ button: TimelineHeaderButton, row: Int) {
        guard let track = track(atRow: row) else { return }
        switch button {
        case .hidden:
            onEdit?("Hide Track", [.setTrack(track: track.id, hidden: !track.hidden)])
        case .muted:
            onEdit?("Mute Track", [.setTrack(track: track.id, muted: !track.muted)])
        case .locked:
            onEdit?("Lock Track", [.setTrack(track: track.id, locked: !track.locked)])
        }
    }

    private func renameTrack(_ track: TrackSnapshot, row: Int) {
        let frame = NSRect(
            x: 6, y: layout.rowTop(row) - TimelineLayout.rulerHeight + 3,
            width: TimelineLayout.headerWidth - 12, height: 20)
        beginRename(in: headers, frame: frame, text: track.name) { [weak self] name in
            self?.onEdit?("Rename Track", [.setTrack(track: track.id, name: name)])
        }
    }

    private func renameMarker(_ marker: MarkerSnapshot) {
        let frame = NSRect(x: max(layout.x(for: marker.time) - 40, 0), y: 3, width: 110, height: 20)
        beginRename(in: ruler, frame: frame, text: marker.name) { [weak self] name in
            self?.onEdit?("Rename Marker", [.setMarker(marker: marker.id, name: name)])
        }
    }

    // MARK: - Shared lookups (the drawing views use these too)

    func track(atRow row: Int) -> TrackSnapshot? {
        let index = layout.trackIndex(forRow: row)
        return snapshot.tracks.indices.contains(index) ? snapshot.tracks[index] : nil
    }

    /// The clip tint of spec §4.4, from `Theme.swift`'s tokens.
    static func tint(for clip: ClipSnapshot) -> NSColor {
        switch clip.source {
        case .media:
            return clip.enabled.video ? DS.clipVideo : DS.clipAudio
        case .still:
            return DS.clipStill
        case .image:
            return DS.clipStill
        case .text:
            return DS.clipText
        case .shape:
            return DS.clipShape
        case .nest:
            return DS.clipNest
        }
    }

    /// True when the clip contributes samples, i.e. deserves a waveform and
    /// fade handles. A nest clip has no media but does have a mix — the core
    /// gives it audio props exactly when something inside it sings, and its
    /// fades apply to all of that (`core/src/audio.rs`) — so it gets the
    /// handles. There is no waveform to draw for one; `drawWaveform` finds no
    /// media and returns.
    func hasAudio(_ clip: ClipSnapshot) -> Bool {
        guard clip.enabled.audio else { return false }
        if case .nest = clip.source { return clip.audio != nil }
        guard let media = snapshot.media(for: clip) else { return false }
        return media.hasAudio
    }

    /// True when the clip contributes pixels — a filmstrip goes here.
    func hasVideo(_ clip: ClipSnapshot) -> Bool {
        guard clip.enabled.video else { return false }
        switch clip.source {
        case .media, .still, .image: return snapshot.media(for: clip)?.hasVideo ?? false
        case .text, .shape, .nest: return false
        }
    }

    /// Source time under a timeline time, for the filmstrip and the waveform.
    /// Source advances at `speed` per timeline tick (spec §6 `set_speed`).
    static func sourceTime(of clip: ClipSnapshot, at time: Ticks) -> Ticks {
        let rate = clip.speed > 0 ? clip.speed : 1
        let offset = Double(time - clip.start) * rate
        return clip.source.sourceIn + TimelineLayout.ticks(clamping: offset)
    }
}

// MARK: - Caches

/// Thumbnails and waveform peaks, kept out of `draw(_:)`'s way.
///
/// `MediaImporter` writes both to the document's cache directory; reading a
/// peaks file is a whole-file read and a filmstrip is one file per tile, so a
/// redraw that went to disk every time would make scrolling crawl. Misses are
/// remembered too — a project whose caches have not been generated yet must
/// not re-stat the same missing file sixty times a second.
final class TimelineCaches {
    private var thumbnailCache: [String: CGImage] = [:]
    private var thumbnailMisses: Set<String> = []
    private var peakCache: [UInt32: [Float]] = [:]
    private var peakMisses: Set<UInt32> = []

    /// Well past a screenful of tiles; the whole table is dropped rather than
    /// evicted one by one, because the next scroll refills what it needs.
    private static let thumbnailLimit = 800

    /// `index` is a whole second of SOURCE time, which is how
    /// `MediaImporter` names the files.
    func thumbnail(media: UInt32, index: Int, in directory: URL) -> CGImage? {
        let key = "\(media)/\(index)"
        if let image = thumbnailCache[key] { return image }
        if thumbnailMisses.contains(key) { return nil }
        guard let image = MediaImporter.loadThumbnail(for: media, index: index, in: directory)
        else {
            thumbnailMisses.insert(key)
            return nil
        }
        if thumbnailCache.count >= Self.thumbnailLimit {
            thumbnailCache.removeAll(keepingCapacity: true)
        }
        thumbnailCache[key] = image
        return image
    }

    /// 100 buckets per second of source, mono, max magnitude.
    func peaks(media: UInt32, in directory: URL) -> [Float]? {
        if let cached = peakCache[media] { return cached }
        if peakMisses.contains(media) { return nil }
        guard let loaded = MediaImporter.loadPeaks(for: media, in: directory) else {
            peakMisses.insert(media)
            return nil
        }
        peakCache[media] = loaded
        return loaded
    }

    /// Called for every `.mediaCacheDidChange`. Thumbnails post repeatedly as
    /// they land, so only the misses need clearing there — a tile already
    /// read is still the same tile.
    func invalidate(media: UInt32, kind: String?) {
        if kind == MediaImporter.peaksKind || kind == nil {
            peakCache.removeValue(forKey: media)
            peakMisses.remove(media)
        }
        if kind == MediaImporter.thumbsKind || kind == nil {
            let prefix = "\(media)/"
            thumbnailMisses = thumbnailMisses.filter { !$0.hasPrefix(prefix) }
        }
    }

    func purge() {
        thumbnailCache.removeAll()
        thumbnailMisses.removeAll()
        peakCache.removeAll()
        peakMisses.removeAll()
    }
}

// MARK: - Drawing helpers

/// The few paint primitives the three timeline views share. Free of state so
/// either view can call them mid-`draw`.
enum TimelineDraw {
    /// A `CGImage` the right way up in a FLIPPED view — `CGContext.draw`
    /// alone puts every thumbnail on its head here.
    static func image(_ image: CGImage, in rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext, rect.width > 0, rect.height > 0
        else { return }
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY + rect.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        context.restoreGState()
    }

    /// 45° hatching — a locked track and a transition overlap both wear it.
    static func hatch(_ rect: CGRect, color: NSColor, spacing: CGFloat = 7) {
        guard rect.width > 0, rect.height > 0 else { return }
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: NSPoint(x: x, y: rect.maxY))
            path.line(to: NSPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        path.stroke()
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// A one-line label clipped to `rect`, drawn from its top-left.
    static func label(
        _ text: String, in rect: CGRect, font: NSFont, color: NSColor, centered: Bool = false
    ) {
        guard rect.width > 6, !text.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = text.size(withAttributes: attributes)
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        let x = centered ? rect.midX - size.width / 2 : rect.minX
        text.draw(at: NSPoint(x: x, y: rect.minY), withAttributes: attributes)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// An SF Symbol tinted and centred, falling back to a glyph — the
    /// `GhostButton` rule, for the header toggles that are not buttons.
    static func symbol(_ name: String, fallback: String, in rect: CGRect, tint: NSColor) {
        if let icon = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))?
            .tinted(with: tint)
        {
            let size = icon.size
            icon.draw(
                in: NSRect(
                    x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                    width: size.width, height: size.height))
            return
        }
        label(
            fallback,
            in: CGRect(x: rect.minX, y: rect.midY - 6, width: rect.width, height: 12),
            font: DS.sans(10), color: tint, centered: true)
    }
}

// MARK: - Content view

/// The scroll view's document view: the lanes, the clips, the playhead line,
/// and ALL of the timeline's mouse handling (the ruler and the header column
/// float above it but refuse hits, so this view alone decides what is under
/// the pointer — see `TimelineView`'s note).
final class TimelineContentView: NSView {
    weak var timeline: TimelineView?

    override var isFlipped: Bool { true }

    /// The editor's root view keeps first responder so the bare-key map
    /// (Space, W, E, …) keeps working while the timeline is clicked.
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TimelineContentView does not support NSCoder")
    }

    // MARK: Regions

    /// Spec §4.4's split: a filmstrip over a waveform on a video clip with
    /// sound, the whole bar for one that has only the one.
    static func regions(
        in rect: CGRect, hasVideo: Bool, hasAudio: Bool
    ) -> (video: CGRect, audio: CGRect) {
        switch (hasVideo, hasAudio) {
        case (true, true):
            let top = (rect.height * 0.56).rounded()
            return (
                CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: top),
                CGRect(
                    x: rect.minX, y: rect.minY + top, width: rect.width,
                    height: rect.height - top)
            )
        case (true, false): return (rect, .zero)
        case (false, true): return (.zero, rect)
        case (false, false): return (.zero, .zero)
        }
    }

    /// The square handle for one fade, at the audio region's corner when the
    /// fade is zero and at the fade's end once it has been dragged in.
    static func fadeRect(
        _ clip: ClipSnapshot, edge: TimelineEdge, audio: CGRect, layout: TimelineLayout
    ) -> CGRect {
        let props = clip.audioProps
        let side = TimelineLayout.fadeHandle
        let time = edge == .start ? clip.start + props.fadeIn : clip.end - props.fadeOut
        let x = min(max(layout.x(for: time), audio.minX), max(audio.maxX - side, audio.minX))
        return CGRect(x: x - (edge == .start ? 0 : side), y: audio.minY, width: side, height: side)
    }

    // MARK: Hit testing

    func hit(at point: CGPoint) -> TimelineHit {
        guard let owner = timeline else { return .none }
        let layout = owner.layout
        let snapshot = owner.snapshot

        if point.y >= owner.pinnedY, point.y < owner.pinnedY + TimelineLayout.rulerHeight {
            if point.x < owner.pinnedX + TimelineLayout.headerWidth { return .corner }
            for marker in snapshot.markers
            where abs(layout.x(for: marker.time) - point.x) <= 6 {
                return .marker(marker.id)
            }
            return .ruler(max(layout.time(atX: point.x), 0))
        }

        if point.x < owner.pinnedX + TimelineLayout.headerWidth {
            guard let row = layout.row(atY: point.y) else { return .none }
            let local = CGPoint(x: point.x - owner.pinnedX, y: point.y - layout.rowTop(row))
            if let button = TimelineHeaderView.button(at: local, height: layout.trackHeight) {
                return .headerButton(row: row, button: button)
            }
            return .header(row: row)
        }

        guard let row = layout.row(atY: point.y), let track = owner.track(atRow: row) else {
            return .none
        }
        for clip in snapshot.clips(onTrack: track.id) {
            let rect = layout.clipRect(clip, row: row)
            guard point.x >= rect.minX - 1, point.x <= rect.maxX + 1 else { continue }
            guard !track.locked else { return .clip(clip.id) }
            if owner.hasAudio(clip) {
                let audio = Self.regions(
                    in: rect, hasVideo: owner.hasVideo(clip), hasAudio: true
                ).audio
                for edge in [TimelineEdge.start, TimelineEdge.end]
                where Self.fadeRect(clip, edge: edge, audio: audio, layout: layout)
                    .insetBy(dx: -2, dy: -2).contains(point) {
                    return .fade(clip.id, edge)
                }
            }
            // A bar too narrow to hold two grab zones is all body: trimming a
            // 3 pt clip by eye is not an interaction, it is a trap.
            if rect.width > TimelineLayout.edgeGrab * 3 {
                if point.x - rect.minX <= TimelineLayout.edgeGrab {
                    return .clipEdge(clip.id, .start)
                }
                if rect.maxX - point.x <= TimelineLayout.edgeGrab {
                    return .clipEdge(clip.id, .end)
                }
            }
            return .clip(clip.id)
        }
        return .lane(row: row, time: max(layout.time(atX: point.x), 0))
    }

    // MARK: Mouse

    private func flags(_ event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        timeline?.beginGesture(
            hit: hit(at: point), at: point, flags: flags(event), clicks: event.clickCount)
    }

    override func mouseDragged(with event: NSEvent) {
        timeline?.continueGesture(
            at: convert(event.locationInWindow, from: nil), flags: flags(event))
    }

    override func mouseUp(with event: NSEvent) {
        timeline?.endGesture(at: convert(event.locationInWindow, from: nil), flags: flags(event))
    }

    /// Pinch to zoom about the pointer (spec §4.4).
    override func magnify(with event: NSEvent) {
        guard let owner = timeline else { return }
        let point = convert(event.locationInWindow, from: nil)
        owner.setZoom(owner.layout.zoom * (1 + event.magnification), anchoredAt: point.x)
    }

    /// ⌥/⌘ + wheel zooms about the pointer; everything else scrolls.
    override func scrollWheel(with event: NSEvent) {
        let modifiers = flags(event)
        guard modifiers.contains(.option) || modifiers.contains(.command), let owner = timeline
        else {
            super.scrollWheel(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 90 : event.deltaY / 6
        owner.setZoom(owner.layout.zoom * (1 + step), anchoredAt: point.x)
    }

    override func resetCursorRects() {
        guard let owner = timeline else { return }
        let layout = owner.layout
        let visible = visibleRect
        for (index, track) in owner.snapshot.tracks.enumerated() where !track.locked {
            let row = layout.row(forTrackIndex: index)
            for clip in owner.snapshot.clips(onTrack: track.id) {
                let rect = layout.clipRect(clip, row: row)
                guard rect.intersects(visible), rect.width > TimelineLayout.edgeGrab * 3 else {
                    continue
                }
                let grab = TimelineLayout.edgeGrab
                addCursorRect(
                    CGRect(x: rect.minX, y: rect.minY, width: grab, height: rect.height),
                    cursor: .resizeLeftRight)
                addCursorRect(
                    CGRect(x: rect.maxX - grab, y: rect.minY, width: grab, height: rect.height),
                    cursor: .resizeLeftRight)
            }
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let owner = timeline else { return }
        let layout = owner.layout
        let snapshot = owner.snapshot

        DS.timelineLane.setFill()
        dirtyRect.fill()

        for row in 0..<max(layout.trackCount, 0) {
            let rect = layout.rowRect(row, width: layout.contentWidth)
            guard rect.intersects(dirtyRect) else { continue }
            (row.isMultiple(of: 2) ? DS.timelineLaneAlt : DS.timelineLane).setFill()
            rect.fill()
        }

        if let range = owner.inOutRange, range.end > range.start, layout.trackCount > 0 {
            DS.timelineRangeShade.setFill()
            NSRect(
                x: layout.x(for: range.start), y: layout.lanesTop,
                width: layout.width(of: range.end - range.start),
                height: layout.lanesHeight
            ).fill()
        }

        for (index, track) in snapshot.tracks.enumerated() {
            let row = layout.row(forTrackIndex: index)
            let lane = layout.rowRect(row, width: layout.contentWidth)
            guard lane.intersects(dirtyRect) else { continue }
            let clips = snapshot.clips(onTrack: track.id)
            for (position, clip) in clips.enumerated() {
                let rect = layout.clipRect(clip, row: row)
                guard rect.intersects(dirtyRect) else { continue }
                draw(
                    clip: clip, in: rect, track: track,
                    previous: position > 0 ? clips[position - 1] : nil,
                    owner: owner, visible: dirtyRect)
            }
            if track.locked {
                TimelineDraw.hatch(lane, color: DS.textFaint.withAlphaComponent(0.55))
            }
        }

        drawOverlays(owner: owner, layout: layout)
    }

    private func drawOverlays(owner: TimelineView, layout: TimelineLayout) {
        if let marquee = owner.marquee {
            let rect = marquee.rect
            DS.selectionFill.setFill()
            rect.fill()
            DS.marquee.setStroke()
            NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }

        let guide = owner.clipDrag?.guide ?? owner.trim?.guide ?? owner.markerDrag?.guide
        if let guide = guide {
            DS.snapGuide.setFill()
            NSRect(x: layout.x(for: guide) - 0.5, y: 0, width: 1, height: bounds.height).fill()
        }

        DS.playhead.setFill()
        NSRect(
            x: (layout.x(for: owner.playhead) - 0.5).rounded(), y: layout.lanesTop - 2,
            width: 1, height: max(layout.lanesHeight + 4, 0)
        ).fill()

        if let refusal = owner.refusal {
            let t = min(max(refusal.progress, 0), 1)
            let rect = CGRect(
                x: refusal.from.minX + (refusal.to.minX - refusal.from.minX) * t,
                y: refusal.from.minY + (refusal.to.minY - refusal.from.minY) * t,
                width: refusal.from.width, height: refusal.from.height)
            DS.playhead.withAlphaComponent(0.75 * (1 - t) + 0.25).setStroke()
            let path = NSBezierPath(
                roundedRect: rect.insetBy(dx: 1, dy: 1),
                xRadius: TimelineLayout.clipRadius, yRadius: TimelineLayout.clipRadius)
            path.lineWidth = 2
            path.stroke()
        }
    }

    /// One clip bar: tint, filmstrip, waveform, transition, actions, label,
    /// fade handles, selection outline — spec §4.4's list, in paint order.
    private func draw(
        clip: ClipSnapshot, in rect: CGRect, track: TrackSnapshot, previous: ClipSnapshot?,
        owner: TimelineView, visible: CGRect
    ) {
        let layout = owner.layout
        let dimmed = track.hidden || (!clip.enabled.video && !clip.enabled.audio)
        var tint = TimelineView.tint(for: clip)
        if dimmed {
            tint = tint.blended(withFraction: 0.5, of: DS.chromeBackground) ?? tint
        }

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(
            roundedRect: rect, xRadius: TimelineLayout.clipRadius,
            yRadius: TimelineLayout.clipRadius
        ).addClip()
        tint.setFill()
        rect.fill()

        let hasVideo = owner.hasVideo(clip)
        let hasAudio = owner.hasAudio(clip)
        let regions = Self.regions(in: rect, hasVideo: hasVideo, hasAudio: hasAudio)
        if !regions.video.isEmpty {
            drawFilmstrip(clip, in: regions.video, owner: owner, visible: visible)
        }
        if !regions.audio.isEmpty {
            let muted = clip.audioProps.muted || track.muted
            drawWaveform(clip, in: regions.audio, owner: owner, visible: visible, muted: muted)
        }

        // An action is a darker band along the top edge over its span; its
        // start is CLIP time, so it maps back through the clip's own start.
        for action in clip.actions where action.duration > 0 {
            let from = layout.x(for: clip.start + action.start)
            let to = layout.x(for: clip.start + action.endTime)
            NSColor.black.withAlphaComponent(0.34).setFill()
            NSRect(x: from, y: rect.minY, width: max(to - from, 2), height: 5).fill()
        }

        // The label sits below the action band when there is one, so the two
        // never fight for the same five points.
        let labelTop = rect.minY + (clip.actions.isEmpty ? 2 : 6)
        TimelineDraw.label(
            owner.snapshot.name(of: clip),
            in: CGRect(x: rect.minX + 5, y: labelTop, width: rect.width - 8, height: 13),
            font: DS.sans(10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.92))
        NSGraphicsContext.current?.restoreGraphicsState()

        // The transition zone is the OVERLAP with the previous clip, so it is
        // drawn unclipped — it belongs to both bars.
        if let transition = clip.transitionIn, let previous = previous, previous.end > clip.start {
            let zone = CGRect(
                x: layout.x(for: clip.start), y: rect.minY,
                width: max(layout.width(of: previous.end - clip.start), 2), height: rect.height)
            NSColor.black.withAlphaComponent(0.22).setFill()
            zone.fill()
            TimelineDraw.hatch(zone, color: NSColor.white.withAlphaComponent(0.4), spacing: 5)
            TimelineDraw.label(
                transition.kind.displayName,
                in: CGRect(x: zone.minX, y: zone.maxY - 13, width: zone.width, height: 12),
                font: DS.sans(9), color: NSColor.white.withAlphaComponent(0.85), centered: true)
        }

        if hasAudio, regions.audio.height >= TimelineLayout.fadeHandle + 2 {
            for edge in [TimelineEdge.start, TimelineEdge.end] {
                let handle = Self.fadeRect(clip, edge: edge, audio: regions.audio, layout: layout)
                NSColor.white.withAlphaComponent(0.7).setFill()
                handle.fill()
            }
        }

        if owner.selection.contains(clip.id) {
            DS.playhead.setStroke()
            let outline = NSBezierPath(
                roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: TimelineLayout.clipRadius,
                yRadius: TimelineLayout.clipRadius)
            outline.lineWidth = 2
            outline.stroke()
        }
    }

    private func drawFilmstrip(
        _ clip: ClipSnapshot, in rect: CGRect, owner: TimelineView, visible: CGRect
    ) {
        guard rect.height >= 20, let directory = owner.cacheDirectory,
              let media = owner.snapshot.media(for: clip), media.width > 0, media.height > 0
        else { return }
        let aspect = CGFloat(media.width) / CGFloat(media.height)
        let tile = max((rect.height * aspect).rounded(), 12)
        let skipped = max(((visible.minX - rect.minX) / tile).rounded(.down), 0)
        var x = rect.minX + skipped * tile
        let limit = min(rect.maxX, visible.maxX)
        while x < limit {
            let time = max(owner.layout.time(atX: x + tile / 2), clip.start)
            let source = TimelineView.sourceTime(of: clip, at: time)
            let index = Int(max(source, 0) / ReelTime.perSecond)
            if let image = owner.caches.thumbnail(media: media.id, index: index, in: directory) {
                TimelineDraw.image(
                    image, in: CGRect(x: x, y: rect.minY, width: tile, height: rect.height))
            }
            x += tile
        }
    }

    /// The cached peaks (100 buckets per source second) as a centred column
    /// plot. Muted draws at 40 % (spec §4.4).
    private func drawWaveform(
        _ clip: ClipSnapshot, in rect: CGRect, owner: TimelineView, visible: CGRect, muted: Bool
    ) {
        guard rect.height >= 8, let directory = owner.cacheDirectory,
              let media = owner.snapshot.media(for: clip),
              let peaks = owner.caches.peaks(media: media.id, in: directory), !peaks.isEmpty
        else { return }
        let alpha: CGFloat = muted ? 0.4 : 1
        NSColor.white.withAlphaComponent(0.72 * alpha).setFill()
        let midY = rect.midY
        let half = rect.height / 2 - 1
        let from = max(rect.minX, visible.minX)
        let to = min(rect.maxX, visible.maxX)
        var x = from.rounded(.down)
        let bucketsPerSecond = Double(MediaImporter.peakBucketsPerSecond)
        while x < to {
            let time = max(owner.layout.time(atX: x), clip.start)
            let source = TimelineView.sourceTime(of: clip, at: time)
            let bucket = Int(
                (Double(max(source, 0)) / Double(ReelTime.perSecond) * bucketsPerSecond)
                    .rounded(.down))
            guard peaks.indices.contains(bucket) else {
                x += 1
                continue
            }
            let amplitude = CGFloat(min(max(peaks[bucket], 0), 1)) * half
            NSRect(x: x, y: midY - amplitude, width: 1, height: max(amplitude * 2, 1)).fill()
            x += 1
        }
    }
}

// MARK: - Ruler

/// The floating ruler band: adaptive ticks, the in/out shading, the marker
/// flags and the playhead's coral head (spec §4.4).
///
/// Its frame's x is always 0 and its width the whole content, so its local x
/// IS content x and every tick can be placed straight from the layout. Only
/// its y floats. It refuses hits so `TimelineContentView` owns the mouse; the
/// one exception is a real subview, which is how the inline rename field
/// still works.
final class TimelineRulerView: NSView {
    weak var timeline: TimelineView?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TimelineRulerView does not support NSCoder")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let owner = timeline else { return }
        let layout = owner.layout
        DS.chromeBackground.setFill()
        bounds.fill()

        if let range = owner.inOutRange, range.end > range.start {
            DS.timelineRangeShade.setFill()
            NSRect(
                x: layout.x(for: range.start), y: 0,
                width: layout.width(of: range.end - range.start), height: bounds.height
            ).fill()
        }

        let steps = layout.rulerSteps()
        let range = layout.visibleRange(dirtyRect)
        drawTicks(steps: steps, range: range, layout: layout)
        drawMarkers(owner: owner, layout: layout)

        // The corner covers the ticks that would otherwise slide under the
        // header column, and it is drawn last for exactly that reason.
        let corner = NSRect(
            x: owner.pinnedX, y: 0, width: TimelineLayout.headerWidth, height: bounds.height)
        DS.chromeBackground.setFill()
        corner.fill()
        DS.border.setFill()
        NSRect(x: corner.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

        drawPlayheadHead(owner: owner, layout: layout)
    }

    /// Minors and majors walk their OWN grids rather than the majors being
    /// "every nth minor".
    ///
    /// **Pitfall:** at 29.97 a frame is 20 020 ticks and a second is 600 000,
    /// which is not a multiple of it — testing `time.isMultiple(of: major)`
    /// inside the minor loop would land only on zero and the ruler would lose
    /// every label on exactly the rates that need them most.
    private func drawTicks(
        steps: (minor: Ticks, major: Ticks), range: (start: Ticks, end: Ticks),
        layout: TimelineLayout
    ) {
        guard steps.minor > 0, steps.major > 0 else { return }
        DS.borderStrong.setFill()
        var minor = max((range.start / steps.minor) * steps.minor, 0)
        while minor <= range.end {
            NSRect(x: layout.x(for: minor).rounded(), y: bounds.height - 6, width: 1, height: 5)
                .fill()
            minor += steps.minor
        }
        var major = max((range.start / steps.major) * steps.major, 0)
        while major <= range.end {
            defer { major += steps.major }
            NSRect(x: layout.x(for: major).rounded(), y: bounds.height - 10, width: 1, height: 9)
                .fill()
            TimelineDraw.label(
                layout.rulerLabel(major),
                in: CGRect(
                    x: layout.x(for: major) + 3, y: 2, width: layout.width(of: steps.major) - 4,
                    height: 12),
                font: DS.mono(9), color: DS.textMuted)
        }
    }

    private func drawMarkers(owner: TimelineView, layout: TimelineLayout) {
        for marker in owner.snapshot.markers {
            let x = layout.x(for: marker.time).rounded()
            let flag = NSBezierPath()
            flag.move(to: NSPoint(x: x, y: 3))
            flag.line(to: NSPoint(x: x + 9, y: 6))
            flag.line(to: NSPoint(x: x, y: 9))
            flag.close()
            let color = markerColor(marker.color)
            if marker.chapter {
                color.setFill()
                flag.fill()
            } else {
                color.setStroke()
                flag.lineWidth = 1
                flag.stroke()
            }
            color.setFill()
            NSRect(x: x, y: 3, width: 1, height: bounds.height - 5).fill()
        }
    }

    /// The model stores a colour NAME (spec §5.2), not components.
    private func markerColor(_ name: String) -> NSColor {
        switch name.lowercased() {
        case "red": return .systemRed
        case "orange": return DS.coral
        case "yellow": return DS.butter
        case "green": return DS.forest
        case "blue": return .systemBlue
        case "purple": return .systemPurple
        default: return DS.textStrong
        }
    }

    private func drawPlayheadHead(owner: TimelineView, layout: TimelineLayout) {
        let x = layout.x(for: owner.playhead).rounded()
        guard x >= owner.pinnedX + TimelineLayout.headerWidth else { return }
        DS.playhead.setFill()
        let head = NSBezierPath()
        head.move(to: NSPoint(x: x - 5, y: bounds.height - 10))
        head.line(to: NSPoint(x: x + 5, y: bounds.height - 10))
        head.line(to: NSPoint(x: x, y: bounds.height - 1))
        head.close()
        head.fill()
        NSRect(x: x - 0.5, y: 0, width: 1, height: bounds.height).fill()
    }
}

// MARK: - Track headers

/// The floating 120 pt header column: name, then eye / speaker / lock
/// (spec §4.4). Like the ruler it refuses hits so the content view can own
/// the mouse, and like the ruler it still lets a rename field through.
final class TimelineHeaderView: NSView {
    weak var timeline: TimelineView?

    static let buttonSize: CGFloat = 17
    private static let buttonInset: CGFloat = 6

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TimelineHeaderView does not support NSCoder")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// The three toggles, laid out from the row's bottom-left. `local` is the
    /// point relative to the ROW's top-left corner; the content view's hit
    /// test is the only caller, which is why the geometry lives here beside
    /// the drawing that has to agree with it.
    static func buttonRect(_ index: Int, height: CGFloat) -> CGRect {
        CGRect(
            x: buttonInset + CGFloat(index) * (buttonSize + 3),
            // Never above 16 pt: on a Small track the name label owns the top
            // of the row and the toggles have to clear it.
            y: max(height - buttonSize - 2, 16), width: buttonSize, height: buttonSize)
    }

    static func button(at local: CGPoint, height: CGFloat) -> TimelineHeaderButton? {
        let buttons: [TimelineHeaderButton] = [.hidden, .muted, .locked]
        for (index, button) in buttons.enumerated()
        where buttonRect(index, height: height).insetBy(dx: -1, dy: -1).contains(local) {
            return button
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let owner = timeline else { return }
        let layout = owner.layout
        DS.chromeBackground.setFill()
        bounds.fill()

        for (index, track) in owner.snapshot.tracks.enumerated() {
            let row = layout.row(forTrackIndex: index)
            // Local y: the column's frame starts at the ruler's height.
            let top = layout.rowTop(row) - TimelineLayout.rulerHeight
            let rect = CGRect(x: 0, y: top, width: bounds.width, height: layout.trackHeight)
            guard rect.intersects(dirtyRect) else { continue }
            DS.chromeBackground.setFill()
            rect.fill()
            DS.border.setFill()
            NSRect(x: 0, y: rect.maxY, width: bounds.width, height: 1).fill()

            TimelineDraw.label(
                track.name.isEmpty ? "Track \(index + 1)" : track.name,
                in: CGRect(x: 8, y: rect.minY + 2, width: bounds.width - 14, height: 13),
                font: DS.sans(11, weight: .semibold), color: DS.textStrong)

            let toggles: [(TimelineHeaderButton, String, String, Bool)] = [
                (.hidden, track.hidden ? "eye.slash" : "eye", "H", track.hidden),
                (.muted, track.muted ? "speaker.slash" : "speaker.wave.2", "M", track.muted),
                (.locked, track.locked ? "lock" : "lock.open", "L", track.locked),
            ]
            for (position, toggle) in toggles.enumerated() {
                var box = Self.buttonRect(position, height: layout.trackHeight)
                box.origin.y += rect.minY
                if toggle.3 {
                    DS.selectionFill.setFill()
                    NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
                }
                TimelineDraw.symbol(
                    toggle.1, fallback: toggle.2, in: box,
                    tint: toggle.3 ? DS.accent : DS.textMuted)
            }
        }

        // The drop line for a header reorder in flight.
        if let drag = timeline?.trackDrag, drag.didMove, drag.row != drag.originalRow {
            DS.playhead.setFill()
            let y = layout.rowTop(drag.row) - TimelineLayout.rulerHeight
            NSRect(x: 0, y: y - 1, width: bounds.width, height: 2).fill()
        }

        DS.border.setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
    }
}
