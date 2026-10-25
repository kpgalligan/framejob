import AppKit

/// Pick from Canvas for the qualifier (spec §11 GR-13, owner choice 8): the
/// Qualifier section's button arms a third modal canvas mode beside the
/// chroma eyedropper and the region band (`armCanvasMode` ends the others),
/// the next click on the preview samples the picture BEHIND the selected
/// adjustment clip — rendered with the `behind` option, so the clip's own
/// grade and every canvas layer in front of it are left out — and the
/// ranges are centred on that pixel (`ColorQualifier.picked`). One undo
/// step, "Qualifier"; Esc, a second press of the button, or a selection
/// change cancels.
///
/// The pixel is re-rendered rather than read off the screen, and off the
/// main thread, for the eyedropper's reasons (`+Eyedropper`): the commit
/// that follows is OFF-EVENT, so it goes through `applyGrouped`.
extension EditorViewController {
    /// One frame composed for one pixel: its own queue, as the eyedropper's.
    private static let qualifierPickQueue = DispatchQueue(
        label: "com.kgalligan.framejob.qualifier-pick", qos: .userInitiated)

    /// The armed mode. Nil is the answer to "is the mode on".
    var qualifierPick: QualifierPickView? {
        canvasContainer.subviews.compactMap { $0 as? QualifierPickView }.first
    }

    // MARK: - Commands

    /// The section's "Pick from Canvas", sent as a command the way the
    /// chroma key's is. A second press disarms. Refused (a beep) unless every
    /// selected clip is an adjustment clip.
    @objc func pickQualifier(_ sender: Any?) {
        guard qualifierPick == nil else {
            endQualifierPick()
            return
        }
        guard let inspector = inspector, previewCanvas != nil else {
            NSSound.beep()
            return
        }
        let clips = inspector.binding.clips
        guard let first = clips.first, clips.allSatisfy({ InspectorTab.isAdjustment($0) }) else {
            NSSound.beep()
            return
        }
        let picker = QualifierPickView(clips: clips.map { $0.id }, behind: first.id)
        // One-line forwards only (app/CLAUDE.md).
        picker.onPick = { [weak self] point in self?.qualifierPicked(at: point) }
        picker.onCancel = { [weak self] in self?.endQualifierPick() }
        armCanvasMode(picker)
    }

    /// Disarms it, from Esc, a second press, a completed pick, `syncQualifierPick`
    /// and `armCanvasMode` arming another mode.
    func endQualifierPick() { dismissCanvasMode(qualifierPick) }

    /// Called from `refreshCanvas`: armed for the clips selected when it
    /// opened, it closes the moment the selection is anything else.
    func syncQualifierPick() {
        guard let picker = qualifierPick else { return }
        let current = inspector?.binding.clips.map { $0.id } ?? []
        guard current != picker.clips else { return }
        endQualifierPick()
    }

    // MARK: - The pick

    /// One click on the preview, `point` in WINDOW coordinates.
    private func qualifierPicked(at point: CGPoint) {
        guard let document = document, previewCanvas != nil, let picker = qualifierPick
        else { return }
        guard let target = pickedCanvasPixel(atWindow: point) else {
            // A click in the void is a miss, not a decision: the mode stays.
            NSSound.beep()
            return
        }
        let snapshot = document.editedProject.snapshot.canvas
        let clips = picker.clips
        let behind = picker.behind
        let hlg = snapshot.output == .hlg
        endQualifierPick()
        let project = document.editedProject
        let urls = document.mediaURLs()
        let time = document.playhead
        let graphics = GraphicRegistry.shared.snapshot(for: document.recipeKey)
        EditorViewController.qualifierPickQueue.async { [weak self] in
            let color = QualifierPick.sample(
                project: project, urls: urls, at: time, clip: behind, point: target,
                canvas: snapshot, graphics: graphics)
            DispatchQueue.main.async { self?.qualifierSampled(color, clips: clips, hlg: hlg) }
        }
    }

    /// Back on the main thread with the sampled colour: the ranges centred on
    /// it, through the binding's off-event door (an action's end when one is
    /// selected), unless the selection moved while the frame composed. `hlg`
    /// is the canvas output's, read with the click: the pass's luma weights.
    private func qualifierSampled(_ color: RGBA?, clips: [UInt32], hlg: Bool) {
        guard let inspector = inspector, let color = color else {
            NSSound.beep()
            return
        }
        let binding = inspector.binding
        guard binding.clips.map({ $0.id }) == clips else {
            NSSound.beep()
            return
        }
        let patch = binding.videoProps.qualifier.picked(QualifierSample(color, hlg: hlg))
        binding.applyGrouped("Qualifier", binding.ops(video: VideoPatch(qualifier: patch)))
    }
}

/// What a pick samples (GR-13): the frame at `at` rendered with
/// `RecipeOptions(behind: clip)` — the adjustment clip and every canvas
/// layer in front of it left out — read at `point` (canvas pixels) as the
/// eyedropper reads a pixel. An HLG project's frame is read at its code
/// values (`FrameWriter.pickable`) and not un-lifted: the qualifier works on
/// the HLG signal (spec §11 HD-13 (h)).
enum QualifierPick {
    static func sample(
        project: ReelProject, urls: [UInt32: URL], at time: Ticks, clip: UInt32,
        point: CGPoint, canvas: CanvasSnapshot, graphics: GraphicSet?
    ) -> RGBA? {
        let options = RecipeOptions(behind: clip)
        let frame = Exporter.renderFrame(
            project: project, urls: urls, at: time, maxWidth: nil, options: options,
            graphics: graphics)
        return frame.flatMap {
            CanvasEyedropperSession.color(at: point, in: FrameWriter.pickable($0), canvas: canvas)
        }
    }
}

/// Pick from Canvas's overlay: the clips it was armed for and the
/// adjustment clip whose picture behind it is sampled.
final class QualifierPickView: CanvasPickOverlay {
    let clips: [UInt32]
    let behind: UInt32

    init(clips: [UInt32], behind: UInt32) {
        self.clips = clips
        self.behind = behind
        super.init(hint: "Click to pick the colour to qualify · Esc to cancel")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("QualifierPickView does not support NSCoder")
    }
}
