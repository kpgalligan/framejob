import AppKit

/// The preview canvas's half of the editor: installing `PreviewCanvasView` in
/// the top-left pane, turning its `on*` intents into `ProjectDocument` edits,
/// and the crop-mode command the shell stage stubbed (spec §4.2).
///
/// Nothing here holds state — an extension cannot — which is deliberate: the
/// gesture sessions live on the canvas view and the model lives on the
/// document, so this file is only ever the seam between them.
extension EditorViewController {
    /// The installed canvas, found by kind rather than kept in a stored
    /// property: `EditorViewController.swift` is frozen at wiring, and the
    /// pane container is the seam it publishes.
    var previewCanvas: PreviewCanvasView? {
        canvasContainer.subviews.compactMap { $0 as? PreviewCanvasView }.first
    }

    // MARK: - Installation

    /// Fills the canvas pane. Called once from `viewDidLoad`, before the first
    /// `refreshFromDocument`.
    ///
    /// `playerHost` and `safeGuides` are built by the base file (the player
    /// layer's lifetime belongs with `playback`) and re-parented into the
    /// canvas view here, so exactly one object owns the canvas rectangle and
    /// the overlay cannot be laid out against a different one.
    func installCanvas() {
        let canvas = PreviewCanvasView(
            playerHost: playerHost, safeGuides: safeGuides, playerLayer: playback.playerLayer)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        for existing in canvasContainer.subviews where existing !== canvas {
            existing.removeFromSuperview()
        }
        canvasContainer.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: canvasContainer.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: canvasContainer.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: canvasContainer.trailingAnchor),
        ])

        // One-line forwards only (app/CLAUDE.md): every body is a named method
        // on this controller or on the document.
        canvas.onSelectionChanged = { [weak self] ids in self?.canvasSelected(ids) }
        canvas.onLiveBegin = { [weak self] in self?.document?.beginLiveEdit() }
        canvas.onLiveUpdate = { [weak self] ops in self?.document?.updateLiveEdit(ops) }
        canvas.onLiveEnd = { [weak self] name in self?.document?.endLiveEdit(name) }
        canvas.onEdit = { [weak self] name, ops in self?.document?.applyEdit(name, ops) }
        canvas.onZoomStep = { [weak self] delta in self?.canvasZoomStepped(delta) }
        canvas.onCropModeChanged = { [weak self] _ in self?.canvasCropModeChanged() }
        canvas.onSpaceTapped = { [weak self] in self?.playPause(nil) }

        canvas.snappingEnabled = snappingEnabled
        refreshCanvas(isLive: false)
    }

    /// Project → canvas, from `refreshFromDocument`. The handle rides along
    /// because the overlay asks it for a frame recipe (§7.3): the layer list
    /// is the ONE description of what is on screen, and re-deriving it from
    /// the snapshot would drift from what the compositor drew.
    func refreshCanvas(isLive: Bool) {
        guard let document = document, let canvas = previewCanvas else { return }
        canvas.snappingEnabled = snappingEnabled
        canvas.update(
            project: document.project, selection: document.selection,
            playhead: document.playhead)
        // Selection travels on this same channel (`viewStateDidChange`), and
        // an armed eyedropper is armed for particular clips
        // (EditorViewController+Eyedropper.swift), so this is where it learns
        // that what it was aimed at is no longer selected.
        syncChromaEyedropper()
    }

    /// Places the canvas rectangle. Called from the base file's
    /// `layoutCanvas()` — the split views resize the pane without ever laying
    /// it out, so the zoom stop has to be pushed from here.
    func layoutCanvasPane() {
        guard let canvas = previewCanvas else { return }
        let scales = PreviewCanvasView.zoomScales
        canvas.setZoom(scales[min(max(canvasZoomIndex, 0), scales.count - 1)])
        canvas.layoutCanvas()
    }

    /// Playhead → canvas. Separate from `refreshCanvas` because playback moves
    /// it thirty times a second and nothing else changes; the overlay rebuilds
    /// its recipe lazily, so this costs nothing with an empty selection.
    func canvasPlayheadMoved() {
        previewCanvas?.setPlayhead(document?.playhead ?? 0)
    }

    // MARK: - Intents from the view

    /// A PICK, which is not the same thing as a selection change: the
    /// inspector is told first and unconditionally, because clicking a clip
    /// means "show me this one" even when it was already selected (the design
    /// handoff's interaction list, and the reason `clipPicked()` exists rather
    /// than the panel inferring it from `ids != lastSelection`). The guard
    /// below still stops an unchanged selection from posting a refresh.
    private func canvasSelected(_ ids: Set<UInt32>) {
        guard let document = document else { return }
        if !ids.isEmpty { inspector?.clipPicked() }
        guard document.selection != ids else { return }
        document.selection = ids
        viewStateDidChange()
    }

    /// Pinch and ⌥-wheel walk the same four stops as the toolbar popup, so the
    /// popup can never show a zoom the canvas is not at.
    private func canvasZoomStepped(_ delta: Int) {
        if delta > 0 {
            zoomIn(nil)
        } else {
            zoomOut(nil)
        }
    }

    /// Crop mode is view state on the canvas — no op runs and no undo step is
    /// registered — so it travels on the one document channel, the same way
    /// selection does. The inspector's Crop section (M2) reads it from there.
    private func canvasCropModeChanged() {
        viewStateDidChange()
    }

    // MARK: - Commands

    /// C, and Clip ▸ Crop on Canvas (spec §4.2, §9). Refuses with nothing
    /// selected rather than entering a mode with no box in it.
    func toggleCanvasCropMode() {
        guard let canvas = previewCanvas else {
            NSSound.beep()
            return
        }
        if !canvas.setCropMode(!canvas.cropMode) { NSSound.beep() }
    }

    // MARK: - Validation

    /// The half of `validateUserInterfaceItem` this file owns. nil means "not
    /// mine" and leaves the other answers alone; `item` is passed so the check
    /// mark can be set beside the answer, as the base file does for its own.
    func validateCanvasAction(
        _ action: Selector, item: any NSValidatedUserInterfaceItem
    ) -> Bool? {
        guard let document = document else { return false }
        switch action {
        case #selector(toggleCropMode(_:)):
            (item as? NSMenuItem)?.state = previewCanvas?.cropMode == true ? .on : .off
            return !document.selection.isEmpty
        default:
            return nil
        }
    }
}
