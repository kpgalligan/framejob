import AVFoundation
import AppKit

/// The preview pane (spec §4.2): the composition at document size, centred in
/// `DS.canvasVoid` with a 24 pt margin, and a transparent overlay above it
/// carrying the selection box, the eight scale handles, the rotation grip,
/// crop mode, the snap guides and the inline text editor.
///
/// **The one rule that makes this work:** the overlay draws in the SAME
/// coordinate space as the video, by mapping through `AVPlayerLayer.videoRect`
/// (§11's decision to put an `AVPlayerLayer` under an overlay rather than
/// drive an `MTKView`). That mapping is `canvasToView` / `viewToCanvas` and
/// exists exactly once — every hit test, handle, guide and text-editor frame
/// goes through it, so handles and pixels cannot drift apart.
///
/// **Frozen file** (app/CLAUDE.md): wiring and drawing only. The gesture maths
/// is `CanvasSessions.swift` (one stored session property each, below) and the
/// document seam is `EditorViewController+Canvas.swift`.
final class PreviewCanvasView: NSView {
    // MARK: - Metrics

    /// The zoom stops behind spec §4.1's popup — 0 means Fit. The editor's
    /// popup titles (`EditorViewController.canvasZoomTitles`) index the same
    /// table, so the two cannot drift.
    static let zoomScales: [CGFloat] = [0, 0.5, 1, 2]

    /// Handle side and grab radius in VIEW points, so they stay the same size
    /// on screen at every zoom.
    static let handleSize: CGFloat = 8
    static let handleGrab: CGFloat = 11
    /// How far the rotation grip floats above the top edge, view points.
    static let rotationOffset: CGFloat = 26
    static let captionHeight: CGFloat = 16
    static let captionGap: CGFloat = 6
    /// Spec §4.2's void margin.
    static let margin = EditorViewController.canvasMargin
    /// Nudge distances in CANVAS pixels (spec §4.2: 1 px, ⇧ 10 px).
    static let nudgeStep: CGFloat = 1
    static let nudgeStepLarge: CGFloat = 10
    /// A pinch has to accumulate this much before it takes the next zoom stop
    /// — the stops are discrete, so a continuous gesture is quantized here
    /// rather than lying to the popup.
    static let pinchStep: CGFloat = 0.28

    // MARK: - Wiring (set by `EditorViewController.installCanvas`)

    var onSelectionChanged: ((Set<UInt32>) -> Void)?
    var onLiveBegin: (() -> Void)?
    var onLiveUpdate: (([ReelOp]) -> Void)?
    var onLiveEnd: ((String) -> Void)?
    var onEdit: ((String, [ReelOp]) -> Void)?
    /// +1 / -1 through the zoom stops (pinch, and ⌥-wheel).
    var onZoomStep: ((Int) -> Void)?
    var onCropModeChanged: ((Bool) -> Void)?
    /// A bare Space press that turned out not to be a pan — the transport's,
    /// which the overlay has to hand back because it swallowed the key-down
    /// to arm panning.
    var onSpaceTapped: (() -> Void)?

    // MARK: - Views

    /// The host for `Playback.playerLayer`. Owned by `EditorViewController`
    /// (it is part of the player's lifetime, not this view's) and re-parented
    /// here at install time so this file can size it.
    let playerHost: NSView
    let safeGuides: SafeGuidesView
    let overlay = CanvasOverlayView()
    private let caption = NSTextField(labelWithString: "")
    /// Weak: `Playback` owns the layer and may drop its item at any time.
    private weak var playerLayer: AVPlayerLayer?

    // MARK: - Pushed state

    /// The handle every recipe is asked of. Replaced — never mutated — on
    /// each document change, exactly like `RecipeSource`'s slot.
    private(set) var project: ReelProject?
    private(set) var snapshot = ProjectSnapshot.empty
    private(set) var selection: Set<UInt32> = []
    private(set) var playhead: Ticks = 0
    /// What a gesture starts from and writes (spec §11 CI-13).
    var editTarget = CanvasEditTarget.base
    /// Echoes `EditorViewController.snappingEnabled` (the N toggle).
    var snappingEnabled = true
    private(set) var cropMode = false
    /// 0 = Fit; otherwise points per canvas pixel.
    private(set) var zoomScale: CGFloat = 0
    private(set) var panOffset = CGPoint.zero
    /// The canvas rectangle in view points, from the last `layoutCanvas`.
    /// Named `canvasFrame` and not `canvasRect` on purpose: the free function
    /// `canvasRect(of:in:sourceSize:video:)` must stay callable from here.
    private(set) var canvasFrame = CGRect.zero

    // MARK: - Sessions (one stored property each, CanvasSessions.swift)

    var moving: CanvasMoveSession?
    var scaling: CanvasScaleSession?
    var rotating: CanvasRotateSession?
    var cropping: CanvasCropSession?
    var endpointDrag: CanvasEndpointSession?
    var panning: CanvasPanSession?

    /// Built once per gesture: the candidate lists are an O(layers) sweep and
    /// must not be rebuilt on every mouse-moved.
    private var snapper = CanvasSnapper(xs: [], ys: [], threshold: 0, enabled: false)
    private var cachedBoxes: [CanvasLayerBox]?
    private var pinchAccumulator: CGFloat = 0
    private var spaceHeld = false
    private var spaceDidPan = false
    private var textEditor: CanvasTextView?
    private(set) var editingClip: UInt32?

    // MARK: - Life cycle

    init(playerHost: NSView, safeGuides: SafeGuidesView, playerLayer: AVPlayerLayer) {
        self.playerHost = playerHost
        self.safeGuides = safeGuides
        self.playerLayer = playerLayer
        super.init(frame: .zero)
        wantsLayer = true
        overlay.canvas = self
        caption.font = DS.mono(10)
        caption.textColor = DS.textFaint
        caption.alignment = .center
        addSubview(playerHost)
        addSubview(safeGuides)
        addSubview(overlay)
        addSubview(caption)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PreviewCanvasView does not support NSCoder")
    }

    /// Canvas space is y-down (§5.3), so the view is too: the mapping to
    /// points is then a scale and a translation with no flip in it.
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        layoutCanvas()
    }

    // MARK: - State push

    /// The ONE path from the document to this pane. `project` is the handle
    /// frame recipes are asked of; the snapshot rides along for names, tracks
    /// and the canvas.
    func update(
        project: ReelProject?, selection: Set<UInt32>, playhead: Ticks, target: CanvasEditTarget
    ) {
        self.project = project
        editTarget = target
        snapshot = project?.snapshot ?? .empty
        self.selection = selection
        self.playhead = playhead
        cachedBoxes = nil
        if cropMode, primaryBox == nil { setCropMode(false) }
        if let editing = editingClip, snapshot.clip(editing) == nil { cancelTextEditing() }
        layoutCanvas()
        overlay.needsDisplay = true
    }

    /// Playhead only — the cheap path, called thirty times a second during
    /// playback. The recipe behind the handles is rebuilt lazily, so a moving
    /// playhead with nothing selected costs a redraw and no FFI call.
    func setPlayhead(_ time: Ticks) {
        guard playhead != time else { return }
        playhead = time
        cachedBoxes = nil
        guard !selection.isEmpty || cropMode else { return }
        overlay.needsDisplay = true
    }

    /// Zoom stop in points per canvas pixel; 0 = Fit.
    func setZoom(_ scale: CGFloat) {
        guard zoomScale != scale else { return }
        zoomScale = scale
        // A zoom change re-centres: the old pan is a fraction of a different
        // canvas and would read as a jump.
        if scale <= 0 { panOffset = .zero }
        layoutCanvas()
        overlay.needsDisplay = true
    }

    // MARK: - Layout

    /// Places the canvas rectangle inside the void and everything that shares
    /// its frame. Called from `layout()` and from `EditorViewController`'s
    /// `layoutCanvas` (the split views resize this pane without laying it out).
    func layoutCanvas() {
        let canvas = snapshot.canvas
        overlay.frame = bounds
        guard canvas.width > 0, canvas.height > 0, bounds.width > 8, bounds.height > 8 else {
            return
        }
        let available = CGRect(
            x: Self.margin, y: Self.margin,
            width: max(bounds.width - Self.margin * 2, 1),
            height: max(
                bounds.height - Self.margin * 2 - Self.captionHeight - Self.captionGap, 1))
        var scale = zoomScale
        if scale <= 0 {
            scale = min(
                available.width / canvas.size.width, available.height / canvas.size.height)
        }
        scale = max(scale, 0.01)
        let size = CGSize(
            width: (canvas.size.width * scale).rounded(),
            height: (canvas.size.height * scale).rounded())
        clampPan(canvasSize: size, available: available)
        let rect = CGRect(
            x: (available.midX - size.width / 2 + panOffset.x).rounded(),
            y: (available.midY - size.height / 2 + panOffset.y).rounded(),
            width: size.width, height: size.height)
        canvasFrame = rect
        playerHost.frame = rect
        safeGuides.frame = rect
        // 0.06em tracking, the treatment every machine-produced number in the
        // chrome gets. Tracking needs an ATTRIBUTED value, and an attributed
        // value carries its own alignment — the field's `.center` no longer
        // applies once one is set — so the centring rides along in it.
        let captionStyle = NSMutableParagraphStyle()
        captionStyle.alignment = .center
        caption.attributedStringValue = NSAttributedString(
            string: "\(canvas.width) × \(canvas.height) · \(canvas.fps.displayName) fps",
            attributes: [
                .font: DS.mono(10), .foregroundColor: DS.textFaint,
                .kern: 10 * 0.06, .paragraphStyle: captionStyle,
            ])
        caption.frame = CGRect(
            x: 0, y: min(rect.maxY + Self.captionGap, bounds.height - Self.captionHeight),
            width: bounds.width, height: Self.captionHeight)
        // Layer geometry outside an explicit animation must not animate: an
        // implicit CA animation on every window resize makes the preview swim
        // behind the pointer.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = playerHost.bounds
        playerHost.layer?.backgroundColor = canvas.background.nsColor.cgColor
        CATransaction.commit()
        if let editor = textEditor, let id = editingClip, let box = box(for: id) {
            editor.frame = editorFrame(for: box)
        }
    }

    /// Keeps the canvas from being dragged out of the pane: a pan is only
    /// possible along an axis the canvas actually overflows.
    private func clampPan(canvasSize: CGSize, available: CGRect) {
        let slackX = max((canvasSize.width - available.width) / 2, 0)
        let slackY = max((canvasSize.height - available.height) / 2, 0)
        panOffset = CGPoint(
            x: min(max(panOffset.x, -slackX), slackX),
            y: min(max(panOffset.y, -slackY), slackY))
    }

    /// True when the canvas overflows the pane, which is the only time
    /// Space-drag means anything (spec §4.2).
    var canPan: Bool {
        let available = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        return canvasFrame.width > available.width + 1 || canvasFrame.height > available.height + 1
    }

    // MARK: - The coordinate mapping (spec §4.2, §11)

    /// The video rectangle in THIS view's coordinates. Normally identical to
    /// `canvasFrame` — the host is sized to the canvas and the render size is
    /// the canvas size — but going through `AVPlayerLayer.videoRect` is what
    /// keeps the overlay honest if a plan built for an older canvas size is
    /// still on screen, which is exactly the drift §11 warns about.
    var videoRectInView: CGRect {
        guard let rect = playerLayer?.videoRect, rect.width > 1, rect.height > 1 else {
            return canvasFrame
        }
        // The layer's coordinates are the host's layer bounds, y up from its
        // bottom-left; this view is flipped, so y flips on the way out.
        return CGRect(
            x: playerHost.frame.minX + rect.minX,
            y: playerHost.frame.minY + (playerHost.bounds.height - rect.maxY),
            width: rect.width, height: rect.height)
    }

    /// View points per canvas pixel.
    var canvasScale: CGFloat {
        let width = CGFloat(snapshot.canvas.width)
        guard width > 0 else { return 1 }
        let rect = videoRectInView
        guard rect.width > 1 else { return 1 }
        return rect.width / width
    }

    func canvasToView(_ point: CGPoint) -> CGPoint {
        let rect = videoRectInView
        let scale = canvasScale
        return CGPoint(x: rect.minX + point.x * scale, y: rect.minY + point.y * scale)
    }

    func viewToCanvas(_ point: CGPoint) -> CGPoint {
        let rect = videoRectInView
        let scale = canvasScale
        guard scale > 0 else { return .zero }
        return CGPoint(x: (point.x - rect.minX) / scale, y: (point.y - rect.minY) / scale)
    }

    func canvasToView(_ rect: CGRect) -> CGRect {
        let origin = canvasToView(rect.origin)
        let scale = canvasScale
        return CGRect(
            x: origin.x, y: origin.y, width: rect.width * scale, height: rect.height * scale)
    }

    /// A distance in view points, as canvas pixels — how the constant-size
    /// grab radii and the rotation grip's offset cross the mapping.
    func canvasDistance(_ points: CGFloat) -> CGFloat {
        let scale = canvasScale
        return scale > 0 ? points / scale : points
    }

    // MARK: - Layers

    /// The composed frame's layers as boxes, back to front. Rebuilt lazily so
    /// a playhead tick with nothing selected never asks the core.
    var boxes: [CanvasLayerBox] {
        if let cached = cachedBoxes { return cached }
        let built: [CanvasLayerBox]
        if let recipe = project?.recipe(at: playhead) {
            built = CanvasLayerBox.boxes(recipe: recipe, snapshot: snapshot)
        } else {
            built = CanvasLayerBox.boxes(snapshot: snapshot, at: playhead)
        }
        cachedBoxes = built
        return built
    }

    func box(for id: UInt32) -> CanvasLayerBox? { boxes.last { $0.id == id } }

    /// The selected layer the handles hang off: the front-most selected one,
    /// which is the one a click would have picked.
    var primaryBox: CanvasLayerBox? { boxes.last { selection.contains($0.id) } }

    // MARK: - Hit testing

    /// What is under `point` (view space). Handles win over bodies, and the
    /// primary selection's handles win over everything, so a handle sitting on
    /// top of another clip still grabs.
    func hit(at point: CGPoint) -> CanvasHit {
        if let box = primaryBox, !box.locked {
            let grab = Self.handleGrab
            if cropMode {
                for handle in CanvasHandle.allCases
                where near(canvasToView(box.cropHandlePoint(handle)), point, grab) {
                    return .cropHandle(box.id, handle)
                }
            } else {
                let offset = canvasDistance(Self.rotationOffset)
                if near(canvasToView(box.rotationHandlePoint(offset: offset)), point, grab) {
                    return .rotation(box.id)
                }
                for endpoint in [CanvasEndpoint.from, .to] {
                    guard let at = box.endpointPoint(endpoint) else { continue }
                    if near(canvasToView(at), point, grab) { return .endpoint(box.id, endpoint) }
                }
                for handle in CanvasHandle.allCases
                where near(canvasToView(box.handlePoint(handle)), point, grab) {
                    return .handle(box.id, handle)
                }
            }
        }
        let canvasPoint = viewToCanvas(point)
        // Front to back: the topmost VISIBLE clip wins. Locked tracks are not
        // hit (spec §4.2); hidden ones never reach the recipe at all.
        if let box = boxes.reversed().first(where: { !$0.locked && $0.contains(canvasPoint) }) {
            return .body(box.id)
        }
        return .empty
    }

    private func near(_ a: CGPoint, _ b: CGPoint, _ radius: CGFloat) -> Bool {
        abs(a.x - b.x) <= radius && abs(a.y - b.y) <= radius
    }

    // MARK: - Selection

    private func selectClip(_ id: UInt32, flags: NSEvent.ModifierFlags) {
        var next = selection
        if flags.contains(.shift) {
            if next.contains(id) { next.remove(id) } else { next.insert(id) }
        } else if !next.contains(id) {
            next = [id]
        }
        guard next != selection else { return }
        selection = next
        onSelectionChanged?(next)
        overlay.needsDisplay = true
    }

    private func clearSelection() {
        guard !selection.isEmpty else { return }
        selection = []
        onSelectionChanged?([])
        overlay.needsDisplay = true
    }

    // MARK: - Crop mode

    /// C, or a double-click on a clip with pixels (spec §4.2). Refuses with
    /// no selection rather than entering a mode with no box in it.
    @discardableResult
    func setCropMode(_ on: Bool) -> Bool {
        let allowed = on && primaryBox != nil
        if on && !allowed { return false }
        guard cropMode != allowed else { return true }
        cropMode = allowed
        onCropModeChanged?(cropMode)
        overlay.needsDisplay = true
        window?.invalidateCursorRects(for: overlay)
        return true
    }

    // MARK: - Gestures

    private func makeSnapper(excluding clips: Set<UInt32>, suppressed: Bool) -> CanvasSnapper {
        let lists = CanvasSnapper.candidates(
            boxes: boxes, excluding: clips, canvas: snapshot.canvas)
        return CanvasSnapper(
            xs: lists.xs, ys: lists.ys,
            threshold: CanvasSnapper.tick(canvasDistance(CanvasSnapper.threshold)),
            enabled: snappingEnabled && !suppressed)
    }

    /// Mouse-down. Picks the session that owns the hit and starts it; a click
    /// that only changes the selection starts none.
    func beginGesture(at point: CGPoint, flags: NSEvent.ModifierFlags, clicks: Int) {
        commitTextEditing()
        if spaceHeld, canPan {
            spaceDidPan = true
            panning = CanvasPanSession(origin: point, base: panOffset, offset: panOffset)
            return
        }
        switch hit(at: point) {
        case .empty:
            setCropMode(false)
            if !flags.contains(.shift) { clearSelection() }

        case .body(let id):
            selectClip(id, flags: flags)
            if clicks >= 2 {
                doubleClicked(id)
                return
            }
            if cropMode, primaryBox?.id != id { setCropMode(false) }
            beginMove(anchor: id, at: point, flags: flags)

        case .handle(let id, let handle):
            beginScale(id, handle: handle)

        case .rotation(let id):
            beginRotate(id, at: point)

        case .cropHandle(let id, let handle):
            beginCrop(id, handle: handle)

        case .endpoint(let id, let endpoint):
            beginEndpoint(id, endpoint: endpoint)
        }
        overlay.needsDisplay = true
    }

    /// Mouse-dragged. Exactly one session is live; each turns the pointer into
    /// its own ops and pushes them as a live edit, so the box on screen is the
    /// core's own answer and a refused tick simply leaves the last good frame.
    func continueGesture(at point: CGPoint, flags: NSEvent.ModifierFlags) {
        if var session = panning {
            session.update(point: point)
            panning = session
            panOffset = session.offset
            layoutCanvas()
            overlay.needsDisplay = true
            return
        }
        // ⌘ suppresses snapping while the drag is in flight, not only at the
        // press; the candidate list the gesture fetched is kept.
        snapper = CanvasSnapper(
            xs: snapper.xs, ys: snapper.ys,
            threshold: CanvasSnapper.tick(canvasDistance(CanvasSnapper.threshold)),
            enabled: snappingEnabled && !flags.contains(.command))
        let canvasPoint = viewToCanvas(point)
        if var session = moving {
            session.update(point: canvasPoint, snapper: snapper)
            moving = session
            onLiveUpdate?(session.ops(to: editTarget))
        } else if var session = scaling {
            session.update(
                point: canvasPoint, aspectFree: flags.contains(.shift),
                aboutCentre: flags.contains(.option))
            scaling = session
            onLiveUpdate?(session.ops(to: editTarget))
        } else if var session = rotating {
            session.update(point: canvasPoint, snapping: flags.contains(.shift))
            rotating = session
            onLiveUpdate?([session.op(to: editTarget)])
        } else if var session = cropping {
            session.update(point: canvasPoint)
            cropping = session
            onLiveUpdate?([session.op(to: editTarget)])
        } else if var session = endpointDrag {
            guard let box = box(for: session.clip) else { return }
            session.update(unit: box.endpointUnit(canvasPoint))
            endpointDrag = session
            onLiveUpdate?([session.op])
        }
        overlay.needsDisplay = true
    }

    /// Mouse-up. Closes the live edit as ONE undo step (§7.6); a gesture that
    /// changed nothing registers none, because `endLiveEdit` compares handles.
    func endGesture(at point: CGPoint, flags: NSEvent.ModifierFlags) {
        if panning != nil {
            panning = nil
        } else if moving != nil {
            moving = nil
            onLiveEnd?("Move")
        } else if scaling != nil {
            scaling = nil
            onLiveEnd?("Scale")
        } else if rotating != nil {
            rotating = nil
            onLiveEnd?("Rotate")
        } else if cropping != nil {
            cropping = nil
            onLiveEnd?("Crop")
        } else if endpointDrag != nil {
            endpointDrag = nil
            onLiveEnd?("Move Endpoint")
        }
        overlay.needsDisplay = true
        window?.invalidateCursorRects(for: overlay)
    }

    /// Double-click: a text clip opens its inline editor, anything with pixels
    /// enters crop mode (spec §4.2).
    private func doubleClicked(_ id: UInt32) {
        guard let clip = snapshot.clip(id) else { return }
        if clip.text != nil, case .text = clip.source {
            beginTextEditing(id)
            return
        }
        if setCropMode(true) { return }
        NSSound.beep()
    }

    private func beginMove(anchor: UInt32, at point: CGPoint, flags: NSEvent.ModifierFlags) {
        let ids = selection.contains(anchor) ? selection : [anchor]
        var bases: [UInt32: CGPoint] = [:]
        for id in ids {
            guard let clip = snapshot.clip(id),
                  snapshot.track(clip.track)?.locked != true
            else { continue }
            let props = editTarget.start(of: clip, in: project).video
            bases[id] = CGPoint(x: props.x, y: props.y)
        }
        guard !bases.isEmpty, let box = box(for: anchor) else { return }
        snapper = makeSnapper(excluding: Set(bases.keys), suppressed: flags.contains(.command))
        moving = CanvasMoveSession(
            bases: bases, anchor: anchor, anchorBounds: box.bounds, grab: viewToCanvas(point))
        onLiveBegin?()
    }

    private func beginScale(_ id: UInt32, handle: CanvasHandle) {
        guard let box = box(for: id), let clip = snapshot.clip(id) else { return }
        let route = editTarget.forScale(of: clip)
        let start = route.start(of: clip, in: project)
        let base = start.video
        let rect = startRect(of: box, base: base)
        let target: CanvasScaleTarget
        if let shape = clip.shape, case .shape = clip.source {
            target = .box(shape.boxSize)
        } else if clip.text != nil, case .text = clip.source {
            // An auto-sized text clip has no stored width, so the measured box
            // (divided back out of the scale) is the width the drag starts from.
            target = .textWidth(
                start.text?.width ?? (Double(rect.width) / max(base.scale, 0.001)))
        } else {
            target = .uniform
        }
        scaling = CanvasScaleSession(
            clip: id, handle: handle, target: target, base: base, startRect: rect,
            rotation: base.rotation, scale: base.scale,
            boxSize: clip.shape?.boxSize ?? .zero, textWidth: start.text?.width ?? 0)
        onLiveBegin?()
    }

    private func beginRotate(_ id: UInt32, at point: CGPoint) {
        guard let clip = snapshot.clip(id) else { return }
        let base = editTarget.start(of: clip, in: project).video
        let anchor = canvasAnchor(of: clip, in: snapshot.canvas, video: base)
        rotating = CanvasRotateSession(
            clip: id, base: base, anchor: anchor,
            grabAngle: CanvasRotateSession.angle(of: viewToCanvas(point), about: anchor),
            rotation: base.rotation)
        onLiveBegin?()
    }

    private func beginCrop(_ id: UInt32, handle: CanvasHandle) {
        guard let box = box(for: id), let clip = snapshot.clip(id) else { return }
        let base = editTarget.start(of: clip, in: project).video
        cropping = CanvasCropSession(
            clip: id, handle: handle, base: base, sourceSize: box.sourceSize,
            startRect: startRect(of: box, base: base), rotation: base.rotation, crop: base.crop)
        onLiveBegin?()
    }

    private func beginEndpoint(_ id: UInt32, endpoint: CanvasEndpoint) {
        guard let clip = snapshot.clip(id), let shape = clip.shape else { return }
        endpointDrag = CanvasEndpointSession(
            clip: id, endpoint: endpoint,
            unit: endpoint == .from ? shape.fromPoint : shape.toPoint)
        onLiveBegin?()
    }

    /// The uncropped rectangle a session starts from, computed from the
    /// target's props (what the op merges into, CI-13) rather than the
    /// recipe's evaluated ones — the two differ only once a clip has actions.
    private func startRect(of box: CanvasLayerBox, base: VideoProps) -> CGRect {
        let uncropped = VideoProps(
            x: base.x, y: base.y, scale: base.scale, rotation: base.rotation,
            opacity: base.opacity, crop: .zero, cornerRadius: base.cornerRadius,
            shadow: base.shadow, color: base.color, chroma: base.chroma)
        return canvasRect(
            of: box.clip, in: snapshot.canvas, sourceSize: box.sourceSize, video: uncropped)
    }

    // MARK: - Keyboard

    /// The keys the canvas owns while it holds first responder. Everything
    /// else returns false and walks the responder chain to
    /// `EditorViewController.keyDown` (the bare-key transport map).
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.subtracting(.shift).isEmpty else { return false }
        switch event.keyCode {
        case 53:  // Esc
            if cancelGesture() { return true }
            guard cropMode else { return false }
            setCropMode(false)
            return true
        case 36, 76:  // Return, keypad Enter
            guard cropMode else { return false }
            setCropMode(false)
            return true
        case 49:  // Space — armed for panning; the tap is settled on key-up.
            guard !event.isARepeat else { return true }
            spaceHeld = true
            spaceDidPan = false
            return true
        default:
            break
        }
        let step = flags.contains(.shift) ? Self.nudgeStepLarge : Self.nudgeStep
        switch event.keyCode {
        case 123: return nudge(dx: -step, dy: 0)
        case 124: return nudge(dx: step, dy: 0)
        case 125: return nudge(dx: 0, dy: step)
        case 126: return nudge(dx: 0, dy: -step)
        default: return false
        }
    }

    /// Focus left the canvas with Space still down (the inline text editor
    /// taking over, a click in the timeline). Without this the pan stays armed
    /// and the next canvas click drags the whole canvas instead of a clip.
    func releaseSpace() {
        spaceHeld = false
        spaceDidPan = false
    }

    func handleKeyUp(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49 else { return false }
        spaceHeld = false
        // A Space that never panned is the transport's, and the editor never
        // saw the key-down because this view swallowed it.
        if !spaceDidPan { onSpaceTapped?() }
        spaceDidPan = false
        return true
    }

    /// Arrow-key nudge (spec §4.2). One op per clip and one undo step, the
    /// same shape a move drag commits.
    @discardableResult
    func nudge(dx: CGFloat, dy: CGFloat) -> Bool {
        var ops: [ReelOp] = []
        for id in selection.sorted() {
            guard let clip = snapshot.clip(id), snapshot.track(clip.track)?.locked != true
            else { continue }
            let props = editTarget.start(of: clip, in: project).video
            ops.append(
                editTarget.op(
                    video: VideoPatch(
                        x: canvasRound(props.x + Double(dx)),
                        y: canvasRound(props.y + Double(dy))),
                    clip: id))
        }
        guard !ops.isEmpty else { return false }
        onEdit?("Nudge", ops)
        return true
    }

    /// Esc during a drag: abandons the session without committing. The live
    /// edit still has to be closed, or the document keeps its gesture base
    /// forever and the next edit merges into it.
    private func cancelGesture() -> Bool {
        guard moving != nil || scaling != nil || rotating != nil || cropping != nil
            || endpointDrag != nil
        else { return false }
        moving = nil
        scaling = nil
        rotating = nil
        cropping = nil
        endpointDrag = nil
        onLiveEnd?("Cancel")
        overlay.needsDisplay = true
        return true
    }

    // MARK: - Zoom and pan from the trackpad

    func pinched(by magnification: CGFloat) {
        pinchAccumulator += magnification
        while abs(pinchAccumulator) >= Self.pinchStep {
            let direction = pinchAccumulator > 0 ? 1 : -1
            pinchAccumulator -= CGFloat(direction) * Self.pinchStep
            onZoomStep?(direction)
        }
    }

    func scrolled(dx: CGFloat, dy: CGFloat) {
        guard canPan else { return }
        panOffset = CGPoint(x: panOffset.x + dx, y: panOffset.y + dy)
        layoutCanvas()
        overlay.needsDisplay = true
    }

    // MARK: - Inline text editing (spec §4.2)

    /// An `NSTextView` positioned in canvas space over the text clip. It is
    /// axis-aligned even for a rotated clip: AppKit text editing in a rotated
    /// frame fights the input method, and the committed string is the same
    /// either way.
    func beginTextEditing(_ id: UInt32) {
        guard let box = box(for: id), let props = box.clip.text else {
            NSSound.beep()
            return
        }
        cancelTextEditing()
        setCropMode(false)
        let editor = CanvasTextView(frame: editorFrame(for: box))
        editor.isRichText = false
        editor.drawsBackground = true
        editor.backgroundColor = DS.chromeBackground.withAlphaComponent(0.92)
        editor.textColor = DS.textStrong
        editor.font = editorFont(for: props, box: box)
        editor.alignment = alignment(props.align)
        editor.textContainerInset = NSSize(width: 2, height: 2)
        editor.string = props.content
        editor.onCommit = { [weak self] in self?.commitTextEditing() }
        editor.onCancel = { [weak self] in self?.cancelTextEditing() }
        editor.onBlur = { [weak self] in self?.finishTextEditing(commit: true, focus: false) }
        addSubview(editor, positioned: .above, relativeTo: overlay)
        textEditor = editor
        editingClip = id
        window?.makeFirstResponder(editor)
        editor.selectAll(nil)
        overlay.needsDisplay = true
    }

    /// Commits the edited string as one `set_text`. An unchanged string is an
    /// identity edit and the core refuses it, so nothing is sent for it.
    func commitTextEditing() {
        finishTextEditing(commit: true, focus: true)
    }

    func cancelTextEditing() {
        finishTextEditing(commit: false, focus: true)
    }

    /// **Pitfall:** tearing the editor down makes it resign first responder,
    /// which is the very thing that calls back in here. The callbacks are
    /// cleared and the state is nil'd BEFORE the view is removed, so the
    /// second entry finds nothing to do instead of recursing.
    private func finishTextEditing(commit: Bool, focus: Bool) {
        guard let editor = textEditor, let id = editingClip else { return }
        let value = editor.string
        textEditor = nil
        editingClip = nil
        editor.onCommit = nil
        editor.onCancel = nil
        editor.onBlur = nil
        editor.removeFromSuperview()
        // Back to the overlay: it holds the canvas keys, and leaving the
        // window itself as first responder silently drops every one of them.
        if focus { window?.makeFirstResponder(overlay) }
        overlay.needsDisplay = true
        guard commit, let clip = snapshot.clip(id), clip.text?.content != value else { return }
        onEdit?("Edit Text", [.setText(clips: [id], patch: TextPatch(content: value))])
    }

    private func editorFrame(for box: CanvasLayerBox) -> CGRect {
        let rect = canvasToView(box.uncroppedRect.insetBy(dx: -2, dy: -2))
        return CGRect(
            x: rect.minX, y: rect.minY, width: max(rect.width, 60), height: max(rect.height, 24))
    }

    private func editorFont(for props: TextProps, box: CanvasLayerBox) -> NSFont {
        let size = min(max(props.size * box.video.scale * Double(canvasScale), 8), 300)
        return NSFont(name: props.font, size: size) ?? DS.sans(size)
    }

    private func alignment(_ value: String) -> NSTextAlignment {
        switch value {
        case "center": return .center
        case "right": return .right
        default: return .left
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        DS.canvasVoid.setFill()
        bounds.fill()
        guard canvasFrame.width > 2 else { return }
        // A hairline so a black canvas on a dark void still has an edge.
        DS.border.setStroke()
        let border = NSBezierPath(rect: canvasFrame.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()
    }

    /// The overlay's whole drawing pass. Called by `CanvasOverlayView.draw`,
    /// which owns nothing but the event forwarding.
    func drawOverlay(in dirtyRect: CGRect) {
        guard canvasFrame.width > 2, canvasScale > 0 else { return }
        if cropMode, let box = primaryBox { drawCropGhost(box) }
        for box in boxes where selection.contains(box.id) {
            strokeBox(box, emphasised: box.id == primaryBox?.id)
        }
        if let box = primaryBox, !box.locked, editingClip == nil {
            if cropMode {
                drawHandles(
                    CanvasHandle.allCases.map { box.cropHandlePoint($0) }, fill: DS.snapGuide)
            } else {
                drawRotationGrip(box)
                drawHandles(CanvasHandle.allCases.map { box.handlePoint($0) }, fill: .white)
                drawEndpoints(box)
            }
        }
        drawSnapGuides()
    }

    private func strokeBox(_ box: CanvasLayerBox, emphasised: Bool) {
        let path = polygon(box.corners)
        // A dark backing stroke first: the coral outline has to survive both a
        // white frame and a black one.
        NSColor.black.withAlphaComponent(0.4).setStroke()
        path.lineWidth = emphasised ? 3 : 2
        path.stroke()
        DS.playhead.setStroke()
        path.lineWidth = emphasised ? 1.5 : 1
        path.stroke()
    }

    /// Crop mode's ghost: everything the crop is removing, dimmed to 30 % of
    /// the frame's own contrast. The overlay cannot re-render the source
    /// pixels — the player shows the CROPPED composite — so the ghost is the
    /// region, drawn as a scrim inside the uncropped rectangle.
    private func drawCropGhost(_ box: CanvasLayerBox) {
        let outer = polygon(box.corners(of: box.uncroppedRect))
        let inner = polygon(box.corners)
        let ghost = NSBezierPath()
        ghost.append(outer)
        ghost.append(inner)
        ghost.windingRule = .evenOdd
        NSColor.white.withAlphaComponent(0.3).setFill()
        ghost.fill()
        outer.lineWidth = 1
        let dash: [CGFloat] = [4, 3]
        outer.setLineDash(dash, count: dash.count, phase: 0)
        DS.snapGuide.withAlphaComponent(0.9).setStroke()
        outer.stroke()
    }

    private func drawHandles(_ points: [CGPoint], fill: NSColor) {
        let side = Self.handleSize
        for point in points {
            let centre = canvasToView(point)
            let rect = CGRect(
                x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
            let path = NSBezierPath(rect: rect)
            fill.setFill()
            path.fill()
            NSColor.black.withAlphaComponent(0.7).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawRotationGrip(_ box: CanvasLayerBox) {
        let offset = canvasDistance(Self.rotationOffset)
        let top = canvasToView(box.handlePoint(.top))
        let grip = canvasToView(box.rotationHandlePoint(offset: offset))
        let stalk = NSBezierPath()
        stalk.move(to: top)
        stalk.line(to: grip)
        stalk.lineWidth = 1
        DS.playhead.setStroke()
        stalk.stroke()
        let radius = Self.handleSize / 2 + 1
        let circle = NSBezierPath(
            ovalIn: CGRect(
                x: grip.x - radius, y: grip.y - radius, width: radius * 2, height: radius * 2))
        NSColor.white.setFill()
        circle.fill()
        DS.playhead.setStroke()
        circle.lineWidth = 1.5
        circle.stroke()
    }

    /// Line and arrow shapes get endpoint handles instead of a meaningful box
    /// (spec §4.2) — round, so they never read as scale handles.
    private func drawEndpoints(_ box: CanvasLayerBox) {
        for endpoint in [CanvasEndpoint.from, .to] {
            guard let at = box.endpointPoint(endpoint) else { continue }
            let centre = canvasToView(at)
            let radius = Self.handleSize / 2 + 1
            let circle = NSBezierPath(
                ovalIn: CGRect(
                    x: centre.x - radius, y: centre.y - radius,
                    width: radius * 2, height: radius * 2))
            DS.marquee.setFill()
            circle.fill()
            NSColor.white.setStroke()
            circle.lineWidth = 1
            circle.stroke()
        }
    }

    /// The guides for whichever axes are currently snapped, drawn across the
    /// whole canvas so the alignment they claim is visible.
    private func drawSnapGuides() {
        guard let session = moving, session.guideX != nil || session.guideY != nil else { return }
        DS.snapGuide.setStroke()
        let canvas = snapshot.canvas
        if let x = session.guideX {
            let top = canvasToView(CGPoint(x: x, y: 0))
            let bottom = canvasToView(CGPoint(x: x, y: CGFloat(canvas.height)))
            strokeGuide(from: top, to: bottom)
        }
        if let y = session.guideY {
            let left = canvasToView(CGPoint(x: 0, y: y))
            let right = canvasToView(CGPoint(x: CGFloat(canvas.width), y: y))
            strokeGuide(from: left, to: right)
        }
    }

    private func strokeGuide(from: CGPoint, to: CGPoint) {
        let path = NSBezierPath()
        path.move(to: from)
        path.line(to: to)
        path.lineWidth = 1
        path.stroke()
    }

    private func polygon(_ points: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: canvasToView(first))
        for point in points.dropFirst() { path.line(to: canvasToView(point)) }
        path.close()
        return path
    }
}

// MARK: - Overlay

/// The transparent view above the player layer: it owns every mouse and key
/// event on the canvas and nothing else. All of the geometry, state and
/// drawing belongs to `PreviewCanvasView`, exactly as `TimelineContentView`
/// defers to `TimelineView` — so "what did I grab" is answered in one place.
final class CanvasOverlayView: NSView {
    weak var canvas: PreviewCanvasView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CanvasOverlayView does not support NSCoder")
    }

    /// Same y-down space as the canvas it draws in.
    override var isFlipped: Bool { true }

    /// Unlike the timeline's content view this one DOES take first responder:
    /// the arrow-key nudge and Space-drag panning of spec §4.2 only make sense
    /// when the canvas has focus. Everything it does not handle walks the
    /// responder chain up to `EditorViewController.keyDown`, so the transport
    /// keys keep working.
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        canvas?.drawOverlay(in: dirtyRect)
    }

    private func flags(_ event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        canvas?.beginGesture(at: point, flags: flags(event), clicks: event.clickCount)
    }

    override func mouseDragged(with event: NSEvent) {
        canvas?.continueGesture(
            at: convert(event.locationInWindow, from: nil), flags: flags(event))
    }

    override func mouseUp(with event: NSEvent) {
        canvas?.endGesture(at: convert(event.locationInWindow, from: nil), flags: flags(event))
    }

    override func magnify(with event: NSEvent) {
        canvas?.pinched(by: event.magnification)
    }

    /// ⌥/⌘ + wheel steps the zoom; a bare wheel pans a canvas that overflows
    /// and is otherwise ignored (there is nothing to scroll).
    override func scrollWheel(with event: NSEvent) {
        let modifiers = flags(event)
        guard let owner = canvas else { return }
        if modifiers.contains(.option) || modifiers.contains(.command) {
            let step = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY / 90 : event.deltaY / 6
            owner.pinched(by: step)
            return
        }
        owner.scrolled(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
    }

    override func keyDown(with event: NSEvent) {
        if canvas?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if canvas?.handleKeyUp(event) == true { return }
        super.keyUp(with: event)
    }

    override func resignFirstResponder() -> Bool {
        canvas?.releaseSpace()
        return super.resignFirstResponder()
    }

    override func resetCursorRects() {
        guard let owner = canvas, let box = owner.primaryBox, !box.locked else { return }
        let grab = PreviewCanvasView.handleGrab
        for handle in CanvasHandle.allCases {
            let centre = owner.canvasToView(box.handlePoint(handle))
            addCursorRect(
                CGRect(
                    x: centre.x - grab / 2, y: centre.y - grab / 2, width: grab, height: grab),
                cursor: handle.cursor)
        }
    }
}

// MARK: - Inline text editor

/// The in-canvas text session's editor. ⌘Return commits and Esc cancels;
/// plain Return is a newline, because a text clip's content is multi-line
/// (spec §4.3's Text tab edits the same string).
final class CanvasTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    /// Clicking away commits, the way every other in-place editor in the app
    /// does (the timeline's rename field, the timecode). Separate from
    /// `onCommit` so the owner can clear it before tearing the editor down —
    /// removing the view resigns first responder and would otherwise recurse.
    var onBlur: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // 36 = Return, 76 = keypad Enter, 53 = Esc.
        if event.modifierFlags.contains(.command), event.keyCode == 36 || event.keyCode == 76 {
            onCommit?()
            return
        }
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        let allowed = super.resignFirstResponder()
        if allowed { onBlur?() }
        return allowed
    }
}
