import AppKit

/// The Video tab (spec §4.3): Transform, Crop, Corner Radius, Shadow, Colour,
/// Speed, Actions and — when the clip overlaps its predecessor — Transition.
///
/// Text and shape clips get Transform, Opacity and Shadow only, which is why
/// the pixel-only groups are gated on `allSourcePixels` and Speed on
/// `allMedia` (only a `media` source accepts `set_speed`, §6). A section that
/// does not apply is absent rather than disabled: the pane is rebuilt when the
/// selection's kinds change, so there is nothing stale to grey out.
final class VideoPane: InspectorPaneView {
    override var tab: InspectorTab { .video }

    // MARK: - Applicability

    /// Clips whose rectangle comes from decoded pixels — the ones with a crop,
    /// a colour treatment and a corner radius.
    private var allSourcePixels: Bool {
        let clips = binding.clips
        return !clips.isEmpty
            && clips.allSatisfy { InspectorTab.hasSourcePixels($0, in: binding.snapshot) }
    }

    /// Clips `set_speed` accepts (§6: a non-media source is an error).
    private var allMedia: Bool {
        let clips = binding.clips
        return !clips.isEmpty && clips.allSatisfy { $0.source.hasSourceBound }
    }

    /// The overlap with the previous clip on the same track, when there is
    /// one. That overlap IS the transition's duration (§5.2).
    private func overlap(before clip: ClipSnapshot) -> Ticks? {
        let earlier = binding.snapshot.clips(onTrack: clip.track).filter { $0.start < clip.start }
        guard let previous = earlier.last else { return nil }
        let overlap = previous.end - clip.start
        return overlap > 0 ? overlap : nil
    }

    override var structureSignature: String {
        var parts = [super.structureSignature]
        parts.append(allSourcePixels ? "px" : "-")
        parts.append(allMedia ? "media" : "-")
        if binding.isSingle, let clip = binding.primary {
            parts.append(clip.actions.map { String($0.id) }.joined(separator: "."))
            parts.append(overlap(before: clip) != nil ? "transition" : "-")
        }
        return parts.joined(separator: "|")
    }

    // MARK: - Sections

    override func makeSections() -> [InspectorSection] {
        var sections: [InspectorSection] = [transformSection()]
        if allSourcePixels {
            sections.append(cropSection())
            sections.append(cornerSection())
        }
        sections.append(inspectorShadowSection(binding))
        if allSourcePixels {
            sections.append(colorSection())
        }
        if allMedia {
            sections.append(speedSection())
        }
        sections.append(actionsSection())
        if binding.isSingle, let clip = binding.primary, overlap(before: clip) != nil {
            sections.append(transitionSection(clip.id))
        }
        return sections
    }

    // MARK: Transform

    private func transformSection() -> InspectorSection {
        let binding = self.binding
        return InspectorSection(
            id: "video.transform", title: "Transform",
            note: { binding.actionNote },
            reset: {
                binding.apply(
                    "Reset Transform",
                    video: VideoPatch(x: 0, y: 0, scale: 1, rotation: 0, opacity: 1))
            },
            rows: [
                inspectorValueRow(
                    "Scale", binding, name: "Scale", unit: "%", decimals: 1, min: 1, max: 1000,
                    quick: [25, 50, 75, 100, 150, 200, 400],
                    read: { binding.videoProps.scale * 100 },
                    ops: { binding.ops(video: VideoPatch(scale: $0 / 100)) },
                    mixed: { binding.mixedVideo { $0.scale } }),
                inspectorValueRow(
                    "Position X", binding, name: "Position", unit: " px", decimals: 0,
                    min: -20000, max: 20000, slider: false,
                    read: { binding.videoProps.x },
                    ops: { binding.ops(video: VideoPatch(x: $0)) },
                    mixed: { binding.mixedVideo { $0.x } }),
                inspectorValueRow(
                    "Position Y", binding, name: "Position", unit: " px", decimals: 0,
                    min: -20000, max: 20000, slider: false,
                    read: { binding.videoProps.y },
                    ops: { binding.ops(video: VideoPatch(y: $0)) },
                    mixed: { binding.mixedVideo { $0.y } }),
                inspectorValueRow(
                    "Rotation", binding, name: "Rotation", unit: "°", decimals: 1, min: -180,
                    max: 180, quick: [-90, -45, 0, 45, 90, 180],
                    read: { binding.videoProps.rotation },
                    ops: { binding.ops(video: VideoPatch(rotation: $0)) },
                    mixed: { binding.mixedVideo { $0.rotation } }),
                inspectorValueRow(
                    "Opacity", binding, name: "Opacity", unit: "%", decimals: 0, min: 0, max: 100,
                    quick: [0, 25, 50, 75, 100],
                    read: { binding.videoProps.opacity * 100 },
                    ops: { binding.ops(video: VideoPatch(opacity: $0 / 100)) },
                    mixed: { binding.mixedVideo { $0.opacity } }),
                inspectorButtonRow([
                    OptionButtonControl(
                        title: "Fit to Canvas",
                        action: { [weak self] in self?.fitOrFill(fill: false) },
                        enabled: { true }, onEdit: {}),
                    OptionButtonControl(
                        title: "Fill Canvas",
                        action: { [weak self] in self?.fitOrFill(fill: true) },
                        enabled: { true }, onEdit: {}),
                ]),
            ])
    }

    /// Fit is `min(cw/sw, ch/sh)`, Fill is `max` (§5.3), centred either way.
    /// Each clip gets its own op because the scale depends on ITS source size;
    /// clips whose size only the renderer knows (text) are skipped.
    private func fitOrFill(fill: Bool) {
        let canvas = binding.canvas
        var ops: [ReelOp] = []
        for clip in binding.clips {
            guard let source = binding.snapshot.sourceSize(of: clip),
                  source.width > 0, source.height > 0
            else { continue }
            let horizontal = Double(canvas.width) / Double(source.width)
            let vertical = Double(canvas.height) / Double(source.height)
            let scale = fill ? max(horizontal, vertical) : min(horizontal, vertical)
            ops.append(
                contentsOf: binding.ops(
                    video: VideoPatch(x: 0, y: 0, scale: scale), for: clip))
        }
        binding.apply(fill ? "Fill Canvas" : "Fit to Canvas", ops)
    }

    // MARK: Crop

    private func cropSection() -> InspectorSection {
        let binding = self.binding
        func crop() -> CropInsets { binding.videoProps.crop }
        func ops(_ next: CropInsets) -> [ReelOp] { binding.ops(video: VideoPatch(crop: next)) }
        let cropButton = OptionButtonControl(
            title: "Crop on Canvas",
            action: { [weak self] in
                self?.inspector?.onCommand?(#selector(EditorViewController.toggleCropMode(_:)))
            },
            enabled: { true }, onEdit: {})
        cropButton.toolTip = "Drag the crop edges on the canvas (C)"
        return InspectorSection(
            id: "video.crop", title: "Crop",
            note: { binding.actionNote },
            reset: { binding.apply("Crop", video: VideoPatch(crop: .zero)) },
            rows: [
                inspectorValueRow(
                    "Left", binding, name: "Crop", unit: " px", decimals: 0, min: 0, max: 20000,
                    slider: false, read: { crop().l },
                    ops: { ops(CropInsets(l: $0, t: crop().t, r: crop().r, b: crop().b)) },
                    mixed: { binding.mixedVideo { $0.crop.l } }),
                inspectorValueRow(
                    "Top", binding, name: "Crop", unit: " px", decimals: 0, min: 0, max: 20000,
                    slider: false, read: { crop().t },
                    ops: { ops(CropInsets(l: crop().l, t: $0, r: crop().r, b: crop().b)) },
                    mixed: { binding.mixedVideo { $0.crop.t } }),
                inspectorValueRow(
                    "Right", binding, name: "Crop", unit: " px", decimals: 0, min: 0, max: 20000,
                    slider: false, read: { crop().r },
                    ops: { ops(CropInsets(l: crop().l, t: crop().t, r: $0, b: crop().b)) },
                    mixed: { binding.mixedVideo { $0.crop.r } }),
                inspectorValueRow(
                    "Bottom", binding, name: "Crop", unit: " px", decimals: 0, min: 0, max: 20000,
                    slider: false, read: { crop().b },
                    ops: { ops(CropInsets(l: crop().l, t: crop().t, r: crop().r, b: $0)) },
                    mixed: { binding.mixedVideo { $0.crop.b } }),
                inspectorButtonRow([cropButton]),
            ])
    }

    // MARK: Corner radius

    private func cornerSection() -> InspectorSection {
        let binding = self.binding
        return InspectorSection(
            id: "video.corner", title: "Corner Radius",
            note: { binding.actionNote },
            reset: { binding.apply("Corner Radius", video: VideoPatch(cornerRadius: 0)) },
            rows: [
                inspectorValueRow(
                    "Radius", binding, name: "Corner Radius", unit: " px", decimals: 0, min: 0,
                    max: 500, quick: [0, 4, 8, 16, 32, 64],
                    read: { binding.videoProps.cornerRadius },
                    ops: { binding.ops(video: VideoPatch(cornerRadius: $0)) },
                    mixed: { binding.mixedVideo { $0.cornerRadius } })
            ])
    }

    // MARK: Colour

    private func colorSection() -> InspectorSection {
        let binding = self.binding
        func color() -> ColorAdjust { binding.videoProps.color }
        func ops(_ next: ColorAdjust) -> [ReelOp] { binding.ops(video: VideoPatch(color: next)) }
        return InspectorSection(
            id: "video.color", title: "Color",
            note: { binding.actionNote },
            reset: { binding.apply("Color", video: VideoPatch(color: .identity)) },
            rows: [
                inspectorValueRow(
                    "Brightness", binding, name: "Brightness", decimals: 2, min: -1, max: 1,
                    read: { color().brightness },
                    ops: {
                        ops(
                            ColorAdjust(
                                brightness: $0, contrast: color().contrast,
                                saturation: color().saturation, hue: color().hue))
                    },
                    mixed: { binding.mixedVideo { $0.color.brightness } }),
                inspectorValueRow(
                    "Contrast", binding, name: "Contrast", decimals: 2, min: -1, max: 1,
                    read: { color().contrast },
                    ops: {
                        ops(
                            ColorAdjust(
                                brightness: color().brightness, contrast: $0,
                                saturation: color().saturation, hue: color().hue))
                    },
                    mixed: { binding.mixedVideo { $0.color.contrast } }),
                inspectorValueRow(
                    "Saturation", binding, name: "Saturation", decimals: 2, min: -1, max: 1,
                    read: { color().saturation },
                    ops: {
                        ops(
                            ColorAdjust(
                                brightness: color().brightness, contrast: color().contrast,
                                saturation: $0, hue: color().hue))
                    },
                    mixed: { binding.mixedVideo { $0.color.saturation } }),
                inspectorValueRow(
                    "Hue", binding, name: "Hue", unit: "°", decimals: 0, min: -180, max: 180,
                    read: { color().hue },
                    ops: {
                        ops(
                            ColorAdjust(
                                brightness: color().brightness, contrast: color().contrast,
                                saturation: color().saturation, hue: $0))
                    },
                    mixed: { binding.mixedVideo { $0.color.hue } }),
            ])
    }

    // MARK: Speed

    /// Speed is a clip-level op, not a patch: `set_speed` takes one clip and
    /// re-times its actions (§6), so the selection becomes one op each and the
    /// whole batch is a single undo step.
    private func speedSection() -> InspectorSection {
        let binding = self.binding
        func rate() -> Double {
            let value = binding.primary?.speed ?? 1
            return value > 0 ? value : 1
        }
        func speedOps(_ next: Double, keepPitch: Bool?) -> [ReelOp] {
            binding.clips.filter { $0.source.hasSourceBound }
                .map { .setSpeed(clip: $0.id, rate: next, keepPitch: keepPitch) }
        }
        return InspectorSection(
            id: "video.speed", title: "Speed",
            reset: { binding.apply("Set Speed", speedOps(1, keepPitch: nil)) },
            rows: [
                inspectorValueRow(
                    "Rate", binding, name: "Set Speed", unit: "×", decimals: 2, min: 0.1, max: 10,
                    quick: [0.5, 1, 2, 4], slider: false,
                    read: rate,
                    ops: { speedOps($0, keepPitch: nil) },
                    mixed: { binding.mixed { $0.speed } }),
                inspectorCheckRow(
                    "Keep pitch", binding, name: "Keep Pitch",
                    read: { binding.audioProps.keepPitch },
                    ops: { value in speedOps(rate(), keepPitch: value) },
                    mixed: { binding.mixedAudio { $0.keepPitch } }),
                inspectorRow(
                    "Duration",
                    [
                        inspectorReadout {
                            guard let clip = binding.primary else { return "—" }
                            return ReelTime.format(
                                clip.duration, fps: binding.canvas.fps,
                                frames: binding.canvas.timecodeFrames)
                        }
                    ]),
            ])
    }

    // MARK: Actions

    /// The actions table (§4.3). One clip at a time: an action id belongs to
    /// its clip, so a table over a multi-selection would be lying about which
    /// span it edits.
    private func actionsSection() -> InspectorSection {
        let binding = self.binding
        var rows: [NSView] = []
        if binding.isSingle, let clip = binding.primary {
            for (index, action) in clip.actions.enumerated() {
                rows.append(actionRow(clip: clip.id, action: action.id, index: index))
                rows.append(curveRow(clip: clip.id, action: action.id))
            }
            if clip.actions.isEmpty {
                rows.append(inspectorRow(nil, [InspectorRowLabel("No actions on this clip.")]))
            }
            let add = OptionButtonControl(
                title: "Add Action", action: { [weak self] in self?.addAction(clip.id) },
                enabled: { true }, onEdit: {})
            add.toolTip = "Add an action at the playhead (⌥⌘K)"
            rows.append(inspectorButtonRow([add, InspectorRowLabel("⌥⌘K")]))
        } else {
            rows.append(
                inspectorRow(nil, [InspectorRowLabel("Select one clip to edit its actions.")]))
        }
        return InspectorSection(id: "video.actions", title: "Actions", rows: rows)
    }

    /// A row binds by ID, never by the captured value: an edit elsewhere in
    /// the section moves the action, and the row is refreshed rather than
    /// rebuilt, so a captured `ActionSnapshot` would show yesterday's numbers.
    private func actionRow(clip: UInt32, action: UInt32, index: Int) -> NSView {
        let binding = self.binding
        func current() -> ActionSnapshot? {
            binding.snapshot.clip(clip)?.actions.first { $0.id == action }
        }
        func span() -> Double {
            max(ReelTime.seconds(binding.snapshot.clip(clip)?.duration ?? 0), 0.01)
        }
        let start = OptionFieldControl(
            width: 54, unit: " s", decimals: 2, min: 0, max: 36000, quick: [],
            read: { ReelTime.seconds(current()?.start ?? 0) },
            write: { value in
                binding.apply(
                    "Move Action",
                    [
                        .setAction(
                            clip: clip, action: action,
                            start: ReelTime.snapToFrame(
                                ReelTime.ticks(seconds: min(value, span())),
                                fps: binding.canvas.fps))
                    ])
            },
            enabled: { true },
            onEdit: { binding.edited() })
        let duration = OptionFieldControl(
            width: 54, unit: " s", decimals: 2, min: 0.01, max: 36000, quick: [0.25, 0.5, 1, 2],
            read: { ReelTime.seconds(current()?.duration ?? 0) },
            write: { value in
                binding.apply(
                    "Resize Action",
                    [
                        .setAction(
                            clip: clip, action: action,
                            duration: ReelTime.snapToFrame(
                                ReelTime.ticks(seconds: min(value, span())),
                                fps: binding.canvas.fps))
                    ])
            },
            enabled: { true },
            onEdit: { binding.edited() })
        let remove = OptionButtonControl(
            title: "Remove",
            action: { binding.apply("Remove Action", [.removeAction(clip: clip, action: action)]) },
            enabled: { true }, onEdit: {})
        return inspectorRow("Action \(index + 1)", [start, duration, remove])
    }

    private func curveRow(clip: UInt32, action: UInt32) -> NSView {
        let binding = self.binding
        let curves = Curve.allCases
        func current() -> ActionSnapshot? {
            binding.snapshot.clip(clip)?.actions.first { $0.id == action }
        }
        let popup = OptionPopupControl(
            width: 96, items: curves.map { $0.displayName },
            read: { curves.firstIndex(of: current()?.curve ?? .easeInOut) ?? 0 },
            write: { index in
                guard curves.indices.contains(index) else { return }
                binding.apply(
                    "Action Curve", [.setAction(clip: clip, action: action, curve: curves[index])])
            },
            enabled: { true },
            onEdit: { binding.edited() })
        return inspectorRow(
            "Curve",
            [
                popup,
                inspectorReadout(width: 96) {
                    VideoPane.summary(of: current()?.end ?? ActionPatch())
                },
            ])
    }

    /// "which properties change" (§4.3) — the end patch's keys, spelled the
    /// way the model spells them.
    static func summary(of patch: ActionPatch) -> String {
        var keys: [String] = []
        if let video = patch.video { keys.append(contentsOf: video.dictionary.keys) }
        if let audio = patch.audio { keys.append(contentsOf: audio.dictionary.keys) }
        if let text = patch.text { keys.append(contentsOf: text.dictionary.keys) }
        return keys.isEmpty ? "no change" : keys.sorted().joined(separator: ", ")
    }

    /// ⌥⌘K, and the section's own button: an action at the playhead, in CLIP
    /// time (§6 `add_action`). Refuses off the clip rather than asking the
    /// core to clamp a nonsense start.
    private func addAction(_ id: UInt32) {
        guard let clip = binding.snapshot.clip(id), clip.contains(binding.playhead) else {
            NSSound.beep()
            return
        }
        binding.apply("Add Action", [.addAction(clip: id, at: clip.clipTime(binding.playhead))])
    }

    // MARK: Transition

    private func transitionSection(_ clip: UInt32) -> InspectorSection {
        let binding = self.binding
        let kinds = TransitionKind.allCases
        let items = ["None"] + kinds.map { $0.displayName }
        /// The overlap read fresh: changing the duration MOVES the clip
        /// (§6 `set_transition_duration`), so the captured start would be
        /// wrong one edit later.
        func overlapSeconds() -> Double {
            guard let current = binding.snapshot.clip(clip) else { return 0 }
            let earlier = binding.snapshot.clips(onTrack: current.track)
                .filter { $0.start < current.start }
            guard let previous = earlier.last else { return 0 }
            return ReelTime.seconds(max(previous.end - current.start, 0))
        }
        return InspectorSection(
            id: "video.transition", title: "Transition",
            rows: [
                inspectorPopupRow(
                    "Kind", binding, name: "Set Transition", items: items,
                    read: {
                        guard let kind = binding.snapshot.clip(clip)?.transitionIn?.kind else {
                            return 0
                        }
                        return (kinds.firstIndex(of: kind) ?? 0) + 1
                    },
                    ops: { index in
                        let kind = index == 0 ? nil : kinds[min(max(index - 1, 0), kinds.count - 1)]
                        return [.setTransition(clip: clip, kind: kind)]
                    }),
                inspectorValueRow(
                    "Duration", binding, name: "Transition Duration", unit: " s", decimals: 2,
                    min: 0.02, max: 10, quick: [0.25, 0.5, 1, 2], slider: false,
                    read: overlapSeconds,
                    ops: { value in
                        [
                            .setTransitionDuration(
                                clip: clip,
                                duration: ReelTime.snapToFrame(
                                    ReelTime.ticks(seconds: value), fps: binding.canvas.fps))
                        ]
                    }),
            ])
    }
}
