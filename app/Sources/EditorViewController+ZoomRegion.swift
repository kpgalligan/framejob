import AppKit

/// The canvas REGION mode (spec §4.2): drag a rectangle over the picture and
/// something is done with it. Two things, so far — `Z` adds a zoom action
/// that brings the rectangle to the canvas (`add_zoom_action`, road map 2's
/// phase 3b), and the Obscure section's "Place on Canvas" appends the
/// rectangle to `video.obscure` (phase 3c).
///
/// **Why one mode and not two.** Both are the same rectangle in the same
/// frame — spec §5.3's Q, source pixels from the centre of the layer's
/// cropped rect — dragged with the same gesture over the same picture. A
/// second overlay with a second copy of the conversion is exactly the drift
/// `CanvasSessions.swift` exists to prevent, so `ZoomRegionSession` carries a
/// `CanvasRegionPurpose` and this file branches on it in one place: the
/// commit at the bottom.
///
/// **Why it is not a `PreviewCanvasView` gesture**, and why every piece below
/// has the shape it has: `EditorViewController+Eyedropper.swift` argues it in
/// full and this file follows it deliberately rather than inventing a second
/// shape for a modal canvas mode. The overlay's PRESENCE is the mode (an
/// extension can hold no state, and the frozen canvas can take no seventh
/// stored session); it is installed through `armCanvasMode`, the one place
/// that keeps two modal overlays from stacking; it takes first responder so
/// Esc reaches it; it clears its callbacks before it is torn down from inside
/// its own event handler; it hands focus back to the canvas overlay on the way
/// out; and a `sync…` hook closes it when the selection it was armed for
/// moves.
///
/// **The one thing it does differently.** The eyedropper takes a click and
/// this takes a DRAG, so the session lives on the view between mouse-down and
/// mouse-up, and the view is given five one-line closures instead of two: two
/// coordinate conversions (only `PreviewCanvasView` may map points to canvas
/// pixels, spec §11), the resolved frame it draws while dragging, and the two
/// outcomes. None of them holds logic; each forwards to a named method here.
extension EditorViewController {
    /// The armed region mode. Nil is the answer to "is the mode on".
    var canvasRegion: CanvasRegionView? {
        canvasContainer.subviews.compactMap { $0 as? CanvasRegionView }.first
    }

    // MARK: - Commands

    /// `Z`, and the Actions section's "Zoom to Region…" button.
    ///
    /// It TOGGLES, which the eyedropper had to learn the hard way: once focus
    /// has left the overlay — a click in the inspector, a menu — Esc no
    /// longer reaches it and the key that armed the mode is the only way back
    /// out. Pressing it again while the OTHER purpose is armed switches
    /// purpose rather than leaving two half-armed modes to reason about.
    @objc func zoomToRegion(_ sender: Any?) { toggleRegionMode(.zoom) }

    /// The Obscure section's "Place on Canvas": the same band, appended to
    /// `video.obscure` instead of turned into an action.
    @objc func placeObscureRegion(_ sender: Any?) { toggleRegionMode(.obscure) }

    /// The Actions section's "Zoom Back": the null-region form of the same
    /// op, at the playhead. No rectangle to drag, so no mode.
    @objc func zoomBack(_ sender: Any?) { zoomBackCommand() }

    private func toggleRegionMode(_ purpose: CanvasRegionPurpose) {
        if let armed = canvasRegion {
            let again = armed.purpose == purpose
            endRegionMode()
            if again { return }
        }
        beginRegionMode(purpose)
    }

    /// Arms the mode over the canvas pane.
    ///
    /// It refuses rather than putting up a crosshair that could only ever
    /// beep — `beginChromaEyedropper`'s rule, and `addActionAtPlayheadCommand`
    /// already refuses an action when the playhead is off the clip. There has
    /// to be exactly one clip selected (a region belongs to one layer's
    /// source pixels; two clips would be two different rectangles), it has to
    /// be drawing at the playhead (`regionTarget` asks the canvas, so a
    /// clip hidden behind an in/out range or on a locked track says no), and
    /// an obscure region needs a free slot.
    private func beginRegionMode(_ purpose: CanvasRegionPurpose) {
        guard let target = regionTarget(), previewCanvas != nil else {
            NSSound.beep()
            return
        }
        if purpose == .obscure, obscureRegions().count >= ObscureProps.max {
            NSSound.beep()
            return
        }
        let region = CanvasRegionView(
            purpose: purpose, clip: target.id, note: regionNote(purpose, clip: target.id))
        // One-line forwards only (app/CLAUDE.md).
        region.canvasPoint = { [weak self] point in self?.regionCanvasPoint(point) }
        region.viewPoint = { [weak self] point in self?.regionViewPoint(point) ?? point }
        region.resolvedFrame = { [weak self] session in self?.regionResolvedFrame(session) }
        region.onCommit = { [weak self] session in self?.regionCommitted(session) }
        region.onCancel = { [weak self] in self?.endRegionMode() }
        // The one door in (`EditorViewController+Eyedropper.swift`): it ends an
        // armed eyedropper on the way, so the two modes cannot stack.
        armCanvasMode(region)
    }

    /// Disarms it, from Esc, from a second press of the key or the button,
    /// from a completed drag, and from `syncRegionMode`.
    func endRegionMode() {
        guard let region = canvasRegion else { return }
        // The teardown runs from inside the view's OWN event handler, so the
        // callbacks go before the view does and a second entry finds nothing
        // to do instead of recursing (the pitfall
        // `PreviewCanvasView.finishTextEditing` documents).
        region.canvasPoint = nil
        region.viewPoint = nil
        region.resolvedFrame = nil
        region.onCommit = nil
        region.onCancel = nil
        region.removeFromSuperview()
        // The crosshair belonged to a view that is now gone.
        NSCursor.arrow.set()
        // Focus goes back where the canvas keys live, or the arrow-key nudge
        // and the Space pan stay dead until the canvas is clicked again.
        if let overlay = previewCanvas?.overlay {
            view.window?.makeFirstResponder(overlay)
        }
    }

    /// Called from `refreshCanvas`, beside `syncChromaEyedropper`: the mode is
    /// armed for ONE clip, so the moment the selection stops being that clip
    /// — or the playhead leaves it, which would put the action's start off the
    /// clip — it is aimed at nothing and closes itself.
    func syncRegionMode() {
        guard let region = canvasRegion else { return }
        guard regionTarget()?.id != region.clip else {
            // Still aimed at the same clip — but the NOTE is about that
            // clip's `during`, not about the moment the mode was armed, and
            // Clip ▸ Motion ▸ During, an undo and an agent's `set_video` can
            // all add or clear one while the band is up. So it is re-read
            // here, where every `refreshCanvas` passes.
            region.note = regionNote(region.purpose, clip: region.clip)
            return
        }
        endRegionMode()
    }

    /// The band's second pill for one clip, or nil: a During motion moves the
    /// clip under a zoom solved without it (spec §11, R5-4), and only a zoom
    /// is solved.
    private func regionNote(_ purpose: CanvasRegionPurpose, clip: UInt32) -> String? {
        guard purpose == .zoom else { return nil }
        let during = document?.editedProject.snapshot.clip(clip)?.videoProps.motion?.during
        return during != nil ? CanvasRegionView.duringNote : nil
    }

    /// `add_zoom_action` with no region, at the playhead: the clip goes back
    /// to its own base `scale`, `x` and `y` over the action's span. The core
    /// reads an absent and an explicit null region the same way; the op
    /// builder sends the null so a saved call says which it meant.
    private func zoomBackCommand() {
        guard let document = document, let box = regionTarget(),
              let clip = document.editedProject.snapshot.clip(box.id)
        else {
            NSSound.beep()
            return
        }
        document.applyEdit(
            "Zoom Back",
            .addZoomAction(clip: clip.id, at: clip.clipTime(document.playhead), region: nil))
    }

    // MARK: - What the mode is aimed at

    /// The one layer a region may be drawn on: the single selected clip, on
    /// screen at the playhead and not on a locked track.
    ///
    /// It is answered as a `CanvasLayerBox` rather than a `ClipSnapshot`
    /// because the box IS the question — it exists only for a clip the recipe
    /// put on the canvas at this instant, and it carries the EVALUATED
    /// transform the rectangle has to be measured through
    /// (`CanvasLayerBox.sourcePoint` says why that is the opposite of every
    /// other canvas session).
    private func regionTarget() -> CanvasLayerBox? {
        guard let document = document, document.selection.count == 1,
              let id = document.selection.first,
              let clip = document.editedProject.snapshot.clip(id), clip.contains(document.playhead),
              let box = previewCanvas?.box(for: id), !box.locked
        else { return nil }
        return box
    }

    /// The obscure list the mode would append to — the first selected clip
    /// with pixels, read through the binding so a playhead inside an action
    /// reads that action's end state and not the base props.
    private func obscureRegions() -> [ObscureProps] {
        inspector?.binding.videoProps.obscure ?? []
    }

    // MARK: - The overlay's five questions

    /// A window point as canvas pixels. `PreviewCanvasView` owns the only
    /// mapping (spec §11) and the overlay is not allowed to know about zoom
    /// or panning, so it asks.
    private func regionCanvasPoint(_ point: CGPoint) -> CGPoint? {
        guard let canvas = previewCanvas else { return nil }
        return canvas.viewToCanvas(canvas.convert(point, from: nil))
    }

    /// The inverse, landed in the OVERLAY's own coordinates — which are the
    /// canvas view's today (both fill `canvasContainer`, both are flipped),
    /// but the conversion is spelled out rather than assumed.
    private func regionViewPoint(_ point: CGPoint) -> CGPoint {
        guard let canvas = previewCanvas, let region = canvasRegion else { return point }
        return region.convert(canvas.canvasToView(point), from: canvas)
    }

    /// The rectangle the canvas will actually be showing once this zoom lands,
    /// in canvas pixels — what the overlay strokes beside the band so a
    /// freely dragged rectangle does not have to be guessed at.
    private func regionResolvedFrame(_ session: ZoomRegionSession) -> CGRect? {
        guard let box = previewCanvas?.box(for: session.clip),
              let source = session.sourceRect(in: box)
        else { return nil }
        return session.frameRect(in: box, source: source)
    }

    // MARK: - The commit

    /// One finished drag. `mouseUp` is an AppKit event, so both branches
    /// commit through the ordinary (non-grouped) door and each is ONE undo
    /// step; the eyedropper needs `applyGrouped` only because its answer comes
    /// back off a queue.
    ///
    /// A band too small to mean anything leaves the mode ARMED and beeps —
    /// a stray click is a miss, not a decision, which is the rule the
    /// eyedropper states for a click that landed off the picture.
    private func regionCommitted(_ session: ZoomRegionSession) {
        guard let box = previewCanvas?.box(for: session.clip),
              let region = session.region(in: box)
        else {
            NSSound.beep()
            return
        }
        switch session.purpose {
        case .zoom:
            commitZoom(session, region: region)
        case .obscure:
            commitObscure(session, region: region)
        }
    }

    /// `add_zoom_action` at the playhead in CLIP time. `fit` unless ⇧ was
    /// held, and no `curve`, so the core's `ease_in_out` applies rather than
    /// `Curve.default`'s `linear`.
    private func commitZoom(_ session: ZoomRegionSession, region: ZoomRegion) {
        guard let document = document, let clip = document.editedProject.snapshot.clip(session.clip),
              clip.contains(document.playhead)
        else {
            NSSound.beep()
            return
        }
        endRegionMode()
        document.applyEdit(
            "Zoom to Region",
            .addZoomAction(
                clip: clip.id, at: clip.clipTime(document.playhead), region: region,
                fit: session.fill ? .fill : .fit))
    }

    /// One more `video.obscure` entry, with the rest of its fields at the
    /// defaults the Add button uses.
    ///
    /// It goes through the INSPECTOR BINDING and not straight to the
    /// document, because the binding is the one place that knows an edit made
    /// while the playhead sits inside an action belongs to that action's end
    /// state (§4.3) — and an animated obscure region is precisely what phase
    /// 3c's list-interpolation rule exists for, so bypassing it would break
    /// the feature silently.
    private func commitObscure(_ session: ZoomRegionSession, region: ZoomRegion) {
        guard let inspector = inspector, inspector.binding.ids == [session.clip] else {
            // The selection moved out from under the drag.
            NSSound.beep()
            return
        }
        let binding = inspector.binding
        var next = binding.videoProps.obscure
        guard next.count < ObscureProps.max else {
            NSSound.beep()
            return
        }
        next.append(
            ObscureProps(
                x: region.x, y: region.y, width: region.width, height: region.height))
        endRegionMode()
        binding.apply("Obscure Region", binding.ops(video: VideoPatch(obscure: next)))
    }
}

// MARK: - The overlay

/// The mode's view: a transparent sheet over the whole canvas pane that takes
/// one drag, draws it, wears the crosshair, and says how to get back out.
///
/// It holds the purpose, the clip and the live session, and nothing else.
/// Where the band landed on the canvas, what the layer under it looks like,
/// and what to do about it are all the view controller's — the same division
/// `CanvasOverlayView` keeps with `PreviewCanvasView`, and the reason the
/// five closures below take and answer plain points and rectangles.
final class CanvasRegionView: NSView, CanvasModalMode {
    /// What the band is for. Read here only for the hint pill; the commit
    /// branches on the session's copy.
    let purpose: CanvasRegionPurpose
    /// The clip the mode was armed for.
    let clip: UInt32
    /// A second hint pill under the first; nil draws none. A `var` because
    /// what it says is a fact about the CLIP, which can change while the mode
    /// is armed — `syncRegionMode` re-reads it on every `refreshCanvas`.
    var note: String? {
        didSet {
            if note != oldValue { needsDisplay = true }
        }
    }
    /// Live between mouse-down and mouse-up, and nil either side of it.
    private(set) var session: ZoomRegionSession?

    /// A WINDOW point as canvas pixels; nil when there is no canvas to ask.
    var canvasPoint: ((CGPoint) -> CGPoint?)?
    /// A canvas point in this view's own coordinates.
    var viewPoint: ((CGPoint) -> CGPoint)?
    /// The rectangle the zoom will frame, in canvas pixels.
    var resolvedFrame: ((ZoomRegionSession) -> CGRect?)?
    var onCommit: ((ZoomRegionSession) -> Void)?
    var onCancel: (() -> Void)?

    private static let zoomHint = "Drag a rectangle to zoom to it · ⇧ fills · Esc to cancel"
    private static let obscureHint = "Drag a rectangle to obscure · Esc to cancel"
    static let duringNote = "This clip has During motion — the zoom is solved without it"
    private static let hintPadding: CGFloat = 9
    private static let hintTop: CGFloat = 10
    /// The band's own stroke, and the resolved frame's at a lower alpha —
    /// the same ink, because they are two readings of one rectangle.
    private static let frameAlpha: CGFloat = 0.45

    init(purpose: CanvasRegionPurpose, clip: UInt32, note: String? = nil) {
        self.purpose = purpose
        self.clip = clip
        self.note = note
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CanvasRegionView does not support NSCoder")
    }

    /// The canvas's own y-down space, so the band's rectangle and the hint's
    /// placement both read the way they look.
    override var isFlipped: Bool { true }

    /// Esc has to reach `keyDown`, which means holding first responder for as
    /// long as the mode lasts.
    override var acceptsFirstResponder: Bool { true }

    // MARK: Events

    /// The press starts the band wherever it landed — including in the void
    /// around the picture. A region's centre is allowed outside the layer
    /// (the core asks only that x and y be finite), and dragging in from the
    /// margin to catch the edge of the frame is the ordinary way to do it.
    override func mouseDown(with event: NSEvent) {
        guard let point = canvasPoint?(event.locationInWindow) else {
            NSSound.beep()
            return
        }
        session = ZoomRegionSession(
            purpose: purpose, clip: clip, anchor: point, current: point,
            fill: event.modifierFlags.contains(.shift))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        track(event)
    }

    /// The release tears this view down from inside this very call — the same
    /// shape as the eyedropper's pick — so the last reference to it must not
    /// be the superview's.
    override func mouseUp(with event: NSEvent) {
        track(event)
        guard let finished = session else { return }
        session = nil
        withExtendedLifetime(self) { onCommit?(finished) }
    }

    /// ⇧ is read at every step rather than latched at the press, so the
    /// choice between fit and fill can be made while the band is being drawn
    /// and the resolved frame answers it as it is made.
    private func track(_ event: NSEvent) {
        guard var live = session, let point = canvasPoint?(event.locationInWindow) else { return }
        live.update(point: point, fill: event.modifierFlags.contains(.shift))
        session = live
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {  // Esc
            super.keyDown(with: event)
            return
        }
        session = nil
        withExtendedLifetime(self) { onCancel?() }
    }

    /// AppKit publishes no "draw a region" cursor, so the band gets the
    /// crosshair — the bargain the eyedropper and `CanvasHandle.cursor` both
    /// make for a shape they cannot spell.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    /// The view is installed before Auto Layout has given it a size, so its
    /// first cursor rect would be cut over an empty rectangle and the
    /// crosshair would never appear. Re-cut it once the size is real.
    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        drawBand()
        drawHint()
    }

    /// The band, and — for a zoom — the rectangle it resolves to.
    ///
    /// Both are AXIS-ALIGNED in canvas space (the band by construction, the
    /// frame because a zoom changes a layer's scale and position and never
    /// its angle), and the canvas-to-view mapping is a scale and a
    /// translation, so two converted corners describe each of them. Nothing
    /// here is rotated, which is why the marquee's flat rectangle is honest
    /// even over a turned clip.
    private func drawBand() {
        guard let session = session, let convert = viewPoint else { return }
        let band = rect(from: convert(session.anchor), to: convert(session.current))
        guard band.width >= 1, band.height >= 1 else { return }
        let path = NSBezierPath(rect: band.insetBy(dx: 0.5, dy: 0.5))
        DS.selectionFill.setFill()
        path.fill()
        DS.marquee.setStroke()
        path.stroke()

        guard let canvasFrame = resolvedFrame?(session) else { return }
        let frame = rect(
            from: convert(CGPoint(x: canvasFrame.minX, y: canvasFrame.minY)),
            to: convert(CGPoint(x: canvasFrame.maxX, y: canvasFrame.maxY)))
        guard frame.width >= 1, frame.height >= 1 else { return }
        let ghost = NSBezierPath(rect: frame.insetBy(dx: 0.5, dy: 0.5))
        // Dashed as well as dimmed: the two rectangles coincide on one axis
        // under `fit`, and a solid stroke at a lower alpha under a solid one
        // reads as a rendering artefact rather than as a second rectangle.
        let dash: [CGFloat] = [4, 3]
        ghost.setLineDash(dash, count: dash.count, phase: 0)
        DS.marquee.withAlphaComponent(Self.frameAlpha).setStroke()
        ghost.stroke()
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// A modal cursor is not enough on its own: the pill is what tells
    /// someone who pressed the key by accident that they are in a mode and
    /// how to leave it. Copied from `CanvasEyedropperView` so the two modes
    /// announce themselves identically.
    private func drawHint() {
        let hint = purpose == .zoom ? Self.zoomHint : Self.obscureHint
        let height = drawPill(hint, top: Self.hintTop)
        // 6 pt between the two pills: a gap that reads as two lines of one hint.
        if let note = note { _ = drawPill(note, top: Self.hintTop + height + 6) }
    }

    /// One pill centred at `top`, skipped when it would not fit; answers its
    /// height either way, so a second pill's place does not depend on the first.
    private func drawPill(_ text: String, top: CGFloat) -> CGFloat {
        let label = NSAttributedString(
            string: text,
            attributes: [.font: DS.sans(11), .foregroundColor: DS.textStrong])
        let size = label.size()
        let pill = CGRect(
            x: ((bounds.width - size.width) / 2 - Self.hintPadding).rounded(),
            y: top,
            width: (size.width + Self.hintPadding * 2).rounded(),
            height: (size.height + 6).rounded())
        guard pill.width < bounds.width else { return pill.height }
        let path = NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4)
        DS.chromeBackground.withAlphaComponent(0.92).setFill()
        path.fill()
        DS.accent.setStroke()
        path.stroke()
        label.draw(at: NSPoint(x: pill.minX + Self.hintPadding, y: pill.minY + 3))
        return pill.height
    }
}
