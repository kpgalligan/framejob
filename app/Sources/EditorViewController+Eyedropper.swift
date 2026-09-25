import AppKit

// MARK: - The modal canvas modes

/// A view whose PRESENCE over the canvas pane IS a mode: the chroma
/// eyedropper's sheet (below) and the region band
/// (`EditorViewController+ZoomRegion.swift`). Each covers the whole picture,
/// swallows every click on it and holds first responder so Esc reaches it, so
/// **at most one may be armed at a time**.
///
/// Nothing else coordinates them: each is found by KIND among
/// `canvasContainer`'s subviews, and an extension has no stored state in which
/// either could see the other. So the rule lives in the one place both entry
/// points have to pass through anyway — `armCanvasMode`, the only code that
/// installs one of these views — and this protocol is what lets it end the
/// others without naming them.
protocol CanvasModalMode: NSView {}

extension EditorViewController {
    /// Installs a modal canvas mode over the canvas pane and gives it the
    /// keyboard, ending whichever mode was armed before it.
    ///
    /// **Why ending the others is here and not at the call sites.** Arming one
    /// mode while another was armed used to leave BOTH overlays installed,
    /// stacked over the same pane: the lower one kept its callbacks, kept its
    /// `sync…` hook, and was still ready to commit its own edit from a gesture
    /// aimed at the upper one — which is how arming the eyedropper under an
    /// armed region band turned the next canvas drag into an unasked-for zoom
    /// action. One entry point remembered to end its sibling and the other did
    /// not; from here neither can forget, and a third mode inherits the rule by
    /// being installed at all.
    func armCanvasMode(_ mode: CanvasModalMode) {
        endCanvasModes()
        mode.translatesAutoresizingMaskIntoConstraints = false
        canvasContainer.addSubview(mode)
        NSLayoutConstraint.activate([
            mode.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
            mode.bottomAnchor.constraint(equalTo: canvasContainer.bottomAnchor),
            mode.leadingAnchor.constraint(equalTo: canvasContainer.leadingAnchor),
            mode.trailingAnchor.constraint(equalTo: canvasContainer.trailingAnchor),
        ])
        view.window?.makeFirstResponder(mode)
        view.window?.invalidateCursorRects(for: mode)
    }

    /// Ends every armed modal canvas mode. Each `end…` is a no-op when its own
    /// mode is not armed, so this is the whole cost of a new mode: one line.
    private func endCanvasModes() {
        endChromaEyedropper()
        endRegionMode()
    }
}

/// The canvas eyedropper for the chroma key (spec §4.3): the Video pane's
/// "Pick from Canvas" arms it, the next click on the preview samples the
/// pixel under the pointer, and that colour becomes the selection's key.
///
/// **Why it is not a `PreviewCanvasView` gesture.** That file is frozen at
/// its size (app/CLAUDE.md), but the better reason is that a mode which
/// swallows every click on the canvas is not another branch in
/// `beginGesture` — it is a sheet laid over the canvas that has exactly one
/// thing to say. The overlay's PRESENCE is the mode, which is also how an
/// extension gets to hold state it cannot store: `chromaEyedropper` finds it
/// by kind, the same way `previewCanvas` finds the canvas.
///
/// **Why the pixel is re-rendered rather than read off the screen.** The
/// preview's pixels are the compositor's; the screen's have been through the
/// window server, a colour profile, a scale factor and possibly another
/// window on top. Only the first of those is the picture the shader will
/// key, and `Exporter.renderFrame` composes exactly it — the same
/// `AVComposition` and `AVVideoComposition` an export writes from. It
/// decodes, so it runs off the main thread (the seam `Exporter`'s own build
/// queue documents), which makes the commit that follows OFF-EVENT: it goes
/// through the grouped entry point or every pick after the first would merge
/// into one undo step (app/CLAUDE.md's undo pitfall).
extension EditorViewController {
    /// One frame composed for one pixel is a decode, not a redraw: its own
    /// queue, so a pick cannot be stuck behind an export's build or make the
    /// next preview rebuild wait behind it.
    private static let eyedropperQueue = DispatchQueue(
        label: "com.kgalligan.reelcut.eyedropper", qos: .userInitiated)

    /// The armed eyedropper. Nil is the answer to "is the mode on".
    var chromaEyedropper: CanvasEyedropperView? {
        canvasContainer.subviews.compactMap { $0 as? CanvasEyedropperView }.first
    }

    // MARK: - Commands

    /// The Chroma Key section's "Pick from Canvas" button, sent as a command
    /// the way Crop on Canvas is (`VideoPane.chromaSection`). A second press
    /// disarms: the button is the way out when focus has left the canvas and
    /// Esc no longer reaches the overlay.
    @objc func pickChromaKey(_ sender: Any?) {
        guard chromaEyedropper == nil else {
            endChromaEyedropper()
            return
        }
        beginChromaEyedropper()
    }

    /// Arms the mode over the canvas pane. Refuses with nothing to key rather
    /// than putting up a crosshair that could only ever beep.
    private func beginChromaEyedropper() {
        guard let inspector = inspector, previewCanvas != nil else {
            NSSound.beep()
            return
        }
        let clips = inspector.binding.videoClips.map { $0.id }
        guard !clips.isEmpty else {
            NSSound.beep()
            return
        }
        let picker = CanvasEyedropperView(
            session: CanvasEyedropperSession(
                clips: clips, base: inspector.binding.videoProps.chroma))
        // One-line forwards only (app/CLAUDE.md).
        picker.onPick = { [weak self] point in self?.chromaKeyPicked(at: point) }
        picker.onCancel = { [weak self] in self?.endChromaEyedropper() }
        // The one door in: it ends an armed region mode on the way (the
        // inspector stays clickable under a canvas overlay, so the button that
        // arms this can be pressed with the band already up).
        armCanvasMode(picker)
    }

    /// Disarms it, from Esc, from a second press of the button, from a
    /// completed pick, and from `syncChromaEyedropper`.
    func endChromaEyedropper() {
        guard let picker = chromaEyedropper else { return }
        // The pitfall `PreviewCanvasView.finishTextEditing` documents: the
        // teardown runs from inside the picker's OWN event handler, so the
        // callbacks are cleared before the view goes and a second entry finds
        // nothing to do instead of recursing.
        picker.onPick = nil
        picker.onCancel = nil
        picker.removeFromSuperview()
        // The crosshair belonged to a view that is now gone; without this the
        // pointer keeps it until the next mouse-moved event lands somewhere
        // with a cursor rect of its own.
        NSCursor.arrow.set()
        // Focus goes back where the canvas keys live, or Esc would leave the
        // arrow-key nudge dead until the user clicked the canvas again.
        if let overlay = previewCanvas?.overlay {
            view.window?.makeFirstResponder(overlay)
        }
    }

    /// Called from `refreshCanvas`: the mode is armed for the clips that were
    /// selected when it opened, so the moment the selection stops being those
    /// clips it is aimed at nothing and closes itself.
    func syncChromaEyedropper() {
        guard let picker = chromaEyedropper else { return }
        let current = inspector?.binding.videoClips.map { $0.id } ?? []
        guard current != picker.session.clips else { return }
        endChromaEyedropper()
    }

    // MARK: - The pick

    /// One click on the preview. `point` is in WINDOW coordinates: the canvas
    /// view owns the only mapping from points to canvas pixels (spec §11),
    /// and the overlay is not allowed to know about zoom or pan.
    private func chromaKeyPicked(at point: CGPoint) {
        guard let document = document, let canvas = previewCanvas,
              let session = chromaEyedropper?.session
        else { return }
        let target = canvas.viewToCanvas(canvas.convert(point, from: nil))
        // The EDITED project's canvas: inside a nest the preview IS the
        // nest, at its own frozen size, so the rectangle a point is mapped
        // into and the frame that is rendered to sample it must both be that
        // one (road map 2's phase 9).
        let snapshot = document.editedProject.snapshot.canvas
        let size = snapshot.size
        guard target.x >= 0, target.y >= 0, target.x < size.width, target.y < size.height else {
            // The void around the canvas. The mode stays armed — a click that
            // missed the picture is a miss, not a decision.
            NSSound.beep()
            return
        }
        endChromaEyedropper()

        let urls = document.mediaURLs()
        let time = document.playhead
        // `applying` is pure (§5.5): this handle is published nowhere and
        // registers no undo step. It exists to be rendered and then dropped.
        // Its other answers — an identity, meaning no clip had anything to
        // suppress, a refusal, and a throw — leave the document's own handle
        // as the right frame to sample, which is what `.project` on a `try?`
        // collapses them to.
        let project = (try? document.editedProject.applying([session.suppression])).project
            ?? document.editedProject
        let graphics = GraphicRegistry.shared.snapshot(for: document.recipeKey)
        EditorViewController.eyedropperQueue.async { [weak self] in
            let frame = Exporter.renderFrame(
                project: project, urls: urls, at: time, maxWidth: nil, graphics: graphics)
            let picked = frame.flatMap {
                CanvasEyedropperSession.color(at: target, in: $0, canvas: snapshot)
            }
            DispatchQueue.main.async { self?.chromaKeySampled(picked, session: session) }
        }
    }

    /// Back on the main thread with the sampled colour.
    ///
    /// The commit goes through the BINDING rather than straight to the
    /// document, because the binding is the one place that knows an edit made
    /// while the playhead sits inside an action belongs to that action's end
    /// state rather than to the clip's base props (§4.3) — and `applyGrouped`
    /// is its off-event door, which this is.
    private func chromaKeySampled(_ color: RGBA?, session: CanvasEyedropperSession) {
        guard let inspector = inspector, let color = color else {
            // A frame that would not compose, or a pixel with no colour in
            // it. Nothing to say beyond "that did not work".
            NSSound.beep()
            return
        }
        let binding = inspector.binding
        guard binding.videoClips.map({ $0.id }) == session.clips else {
            // The selection moved while the frame was composing. Dropped
            // rather than applied to a clip the user never aimed at.
            NSSound.beep()
            return
        }
        binding.applyGrouped(
            "Chroma Key",
            binding.ops(video: VideoPatch(chroma: .some(session.chroma(picked: color)))))
    }
}

// MARK: - The overlay

/// The mode's view: a transparent sheet over the whole canvas pane that takes
/// the one click, wears the crosshair, and says how to get back out.
///
/// It holds the session and nothing else. Where the click landed on the
/// canvas, what is under it, and what to do about it are all the view
/// controller's — this is the same division `CanvasOverlayView` keeps with
/// `PreviewCanvasView`.
final class CanvasEyedropperView: NSView, CanvasModalMode {
    let session: CanvasEyedropperSession
    /// The picked point in WINDOW coordinates.
    var onPick: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    private static let hint = "Click to pick the key color · Esc to cancel"
    private static let hintPadding: CGFloat = 9
    private static let hintTop: CGFloat = 10

    init(session: CanvasEyedropperSession) {
        self.session = session
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CanvasEyedropperView does not support NSCoder")
    }

    /// The canvas's own y-down space, so the hint is placed from the top edge
    /// the way it reads.
    override var isFlipped: Bool { true }

    /// Esc has to reach `keyDown`, which means holding first responder for as
    /// long as the mode lasts.
    override var acceptsFirstResponder: Bool { true }

    /// The pick tears this view down from inside this very call — the same
    /// shape as the canvas text editor committing on ⌘Return — so the last
    /// reference to it must not be the superview's.
    override func mouseDown(with event: NSEvent) {
        withExtendedLifetime(self) { onPick?(event.locationInWindow) }
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {  // Esc
            super.keyDown(with: event)
            return
        }
        withExtendedLifetime(self) { onCancel?() }
    }

    /// AppKit publishes no eyedropper cursor, so a pick gets the crosshair —
    /// the same bargain `CanvasHandle.cursor` makes for the diagonal resize
    /// it also cannot spell.
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

    /// A modal cursor is not enough on its own: the pill is what tells
    /// someone who clicked the button by accident that they are in a mode and
    /// how to leave it.
    override func draw(_ dirtyRect: NSRect) {
        let label = NSAttributedString(
            string: Self.hint,
            attributes: [.font: DS.sans(11), .foregroundColor: DS.textStrong])
        let size = label.size()
        let pill = CGRect(
            x: ((bounds.width - size.width) / 2 - Self.hintPadding).rounded(),
            y: Self.hintTop,
            width: (size.width + Self.hintPadding * 2).rounded(),
            height: (size.height + 6).rounded())
        guard pill.width < bounds.width else { return }
        let path = NSBezierPath(rect: pill)
        DS.chromeBackground.withAlphaComponent(0.92).setFill()
        path.fill()
        DS.accent.setStroke()
        path.stroke()
        label.draw(at: NSPoint(x: pill.minX + Self.hintPadding, y: pill.minY + 3))
    }
}
