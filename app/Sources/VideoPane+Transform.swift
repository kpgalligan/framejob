import AppKit

/// The Clip tab's Transform section (spec §4.3): a pure move out of
/// `VideoPane.swift` (road map creator-jobs CU11b's toll, spec §11 CU-118).
extension VideoPane {
    // MARK: Transform

    /// The one section the design leaves OPEN by default: it is what a
    /// freshly picked clip is most often picked for.
    func transformSection() -> InspectorSection {
        let binding = self.binding
        let modes = BlendMode.allCases
        // Built by hand rather than with `inspectorPopupRow` for one reason:
        // the row builder has nowhere to hang a tooltip, and this is the
        // control in the app that most needs one — the note below fires only
        // when the trap is actually live, and the tooltip is where the whole
        // of it is written down.
        let blend = OptionPopupControl(
            width: InspectorMetrics.popupWidth, items: modes.map { $0.displayName },
            read: { modes.firstIndex(of: binding.videoProps.blend) ?? 0 },
            write: { index in
                guard modes.indices.contains(index) else { return }
                binding.apply("Blend Mode", video: VideoPatch(blend: modes[index]))
            },
            // Disabled on a nest clip, where the core refuses every mode but
            // `normal` (`edit_props.rs`'s `check_blend`) and an enabled popup
            // could only raise an error sheet for a row the panel itself
            // offered. `shape.radius`'s `enabled: { kind == .rectangle }` and
            // this phase's own gradient rows are the convention: a control
            // that cannot land is greyed, never allowed to fail.
            enabled: { VideoPane.blendApplies(to: binding.videoClips) },
            onEdit: { binding.edited() })
        blend.toolTip =
            "How this layer combines with what is already on the canvas. A blend needs "
            + "something UNDER it: over the empty canvas multiply, darken and overlay read "
            + "black, and screen, add, lighten and difference change nothing at all — "
            + "Clip ▸ Add Background puts a plate on the back track to blend against. A "
            + "cross dissolve draws as normal for the length of the overlap."
        return InspectorSection(
            id: "video.transform", title: "Transform",
            summary: {
                let props = binding.videoProps
                let scale = String(format: "%.0f%%", props.scale * 100)
                guard abs(props.rotation) >= 0.05 else { return scale }
                return scale + String(format: " · %.0f°", props.rotation)
            },
            // The nest note first, which says why a row is GREY — a disabled
            // control the reader cannot explain outranks a warning about one
            // that works — and the blend note last, since it only ever
            // appears when the mode is one that cannot be seen at all.
            note: { [weak self] in
                self?.nestBlendNote() ?? self?.blendNote()
            },
            reset: {
                binding.apply(
                    "Reset Transform",
                    video: VideoPatch(
                        x: 0, y: 0, scale: 1, rotation: 0, opacity: 1, blend: .normal,
                        motionBlur: 0))
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
                // Beside Opacity, which is the other answer to "how does this
                // layer meet what is under it" (format version 6).
                //
                // `blend` is an ORDINARY animatable key and deliberately not
                // one `InspectorBinding.structural` pulls out: changing a
                // discrete value inside an action is a coherent animation —
                // it holds and switches at the end, which is what §5.4 says a
                // discrete value does — and `structural`'s own doc already
                // settles the identical case for a filter's `kind`. Keep that
                // function about LENGTH alone.
                inspectorRow(
                    "Blend", [blend], mixed: { binding.mixedVideo { $0.blend } }, binding: binding,
                    writes: binding.ops(video: VideoPatch(blend: binding.videoProps.blend)),
                    default: .derived(
                        binding, name: "Blend Mode", read: { binding.videoProps.blend },
                        ops: { binding.ops(video: VideoPatch(blend: $0)) })),
                // The shutter as a percentage of one canvas frame (format 42,
                // spec §11 CU-113, CU-118 (b)): an ordinary animatable key, so
                // inside an action it writes the action's end. Greyed where the
                // core refuses any value above 0 (CU-111).
                inspectorValueRow(
                    "Motion Blur", binding, name: "Motion Blur", unit: "%", decimals: 0, min: 0,
                    max: 100, quick: [0, 25, 50, 100],
                    read: { binding.videoProps.motionBlur * 100 },
                    ops: { binding.ops(video: VideoPatch(motionBlur: $0 / 100)) },
                    mixed: { binding.mixedVideo { $0.motionBlur } },
                    enabled: { VideoPane.motionBlurApplies(to: binding.videoClips) }),
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

    /// Whether `set_video {blend}` can land on this selection at all.
    ///
    /// A nest clip's blend is refused by the core, and by design: a nest is
    /// FLATTENED rather than composited offscreen (`nest.rs`), so the nest
    /// clip contributes no layer of its own for a mode to apply to — its
    /// clips each become a layer and each blend on their own. `check_blend`
    /// (`edit_props.rs`) is the refusal and `clamp_video` (`actions_clamp.rs`) is
    /// the same rule closing the `set_action_end` back door, so both of the
    /// row's outcomes were dead ends: an error sheet from the popup, or a
    /// mode stored into an action's end state that the recipe then forces
    /// back to `normal`.
    ///
    /// Static and taking the list, so the rule can be measured without an
    /// inspector, a document or a window around it.
    static func blendApplies(to clips: [ClipSnapshot]) -> Bool {
        clips.allSatisfy { $0.source.nestID == nil }
    }

    /// Whether `set_video {motion_blur}` above 0 can land on this selection
    /// (spec §11 CU-111, CU-118 (b)): the core refuses it on a nest clip, whose
    /// layers are its contents' and blur on their own, and on an adjustment
    /// clip, which draws no picture to move. `blendApplies`' convention: the
    /// row is greyed rather than allowed to fail.
    static func motionBlurApplies(to clips: [ClipSnapshot]) -> Bool {
        clips.allSatisfy { $0.source.nestID == nil && !InspectorTab.isAdjustment($0) }
    }

    /// The Transform section's note when the Blend row is grey: what the
    /// control cannot do and where the mode goes instead.
    ///
    /// The way in is the round trip the rest of the app already documents
    /// (`EditorViewController+Nest.swift`): un-group, blend the clip that
    /// wanted it, group again. A blend on a clip INSIDE a nest is allowed and
    /// blends against the canvas below the WHOLE nest — spec §5.3's third
    /// honest limit of the flattening — which is what the note is pointing at
    /// rather than promising an equivalent.
    private func nestBlendNote() -> String? {
        guard !VideoPane.blendApplies(to: binding.videoClips) else { return nil }
        return "A nest has no pixels of its own to blend — un-group it (⇧⌘G) to blend "
            + "the clips inside."
    }

    /// The Transform section's note when a blend mode has nothing to blend
    /// with — the one trap this feature has, and the reason a person's first
    /// try at it looks broken.
    ///
    /// Every mode but `normal` is a function of two colours, and the canvas
    /// starts as its background (black, unless the Document tab says
    /// otherwise). So a layer with nothing under it and a non-normal mode is
    /// either black — `multiply`, `darken` and `overlay` all collapse when the
    /// destination is 0 — or exactly what it was, since `screen`, `add`,
    /// `lighten` and `difference` are all the identity against 0. Neither
    /// looks like a mode that is working, and neither is a bug.
    ///
    /// It is COMPUTED rather than a standing warning, which is the whole point
    /// of putting it here: it appears only when the trap is really live, and
    /// it names which of the two failures the user is looking at. The full
    /// explanation, and the answer, live in the popup's tooltip — a note is
    /// one truncating line.
    ///
    /// Read off the FIRST video clip's props, as every other reading in this
    /// section is: with a mixed selection the row already shows one clip's
    /// value and the mixed badge says the rest disagree.
    private func blendNote() -> String? {
        let mode = binding.videoProps.blend
        guard mode != .normal, let clip = binding.videoClips.first else { return nil }
        let snapshot = binding.snapshot
        return VideoPane.blendTrapNote(
            mode, over: snapshot.canvas.background,
            hasLayerBehind: hasVisibleLayerBehind(clip, in: snapshot))
    }

    /// The note's whole rule, as a function of the three things it depends on
    /// — the mode, the canvas colour and whether anything draws underneath —
    /// so it can be measured without an inspector around it.
    ///
    /// **The canvas has to be OPAQUE black, not merely black**, and the alpha
    /// is the half the first version left out. `blendPremultiplied`'s
    /// `(1 - ab)·src` term carries the source through an empty destination:
    /// at `ab` = 0 the whole formula reduces to `src` exactly, for all eight
    /// modes — the same property `Compositor+Shadow.swift`'s shadow mask relies on.
    /// So over a TRANSPARENT canvas `multiply` renders the layer untouched,
    /// and a note reading "multiply reads black here" would name the opposite
    /// of what is on screen. Between the two the composite is a partial
    /// version of the same (`ab` = 0.5 halves a multiply), which neither verb
    /// describes either, so anything short of opaque stands the note down.
    /// A missing fourth component reads as 1, which is `RGBA.nsColor`'s
    /// convention and the only reading under which a three-component colour
    /// means what it says.
    static func blendTrapNote(_ mode: BlendMode, over background: RGBA, hasLayerBehind: Bool)
        -> String?
    {
        guard mode != .normal, !hasLayerBehind else { return nil }
        // A non-black canvas is something to blend against, so the trap is not
        // live: `multiply` over a white canvas is the layer itself, which is
        // the identity a person can see and reason about.
        guard background.prefix(3).allSatisfy({ $0 <= 0.001 }) else { return nil }
        guard background.count > 3 ? background[3] >= 0.999 : true else { return nil }
        let collapsesToBlack: Set<BlendMode> = [.multiply, .darken, .overlay]
        let verb = collapsesToBlack.contains(mode) ? "reads black here" : "changes nothing here"
        return "Nothing behind this clip — \(mode.displayName.lowercased()) \(verb)."
    }

    /// Whether anything DRAWS under `clip` for any part of its span.
    ///
    /// Tracks are back-to-front (§6: index 0 is the back), so "behind" is the
    /// prefix of the track list before this clip's own, and a hidden track or
    /// a clip with its video switched off contributes nothing to blend with.
    /// Deliberately a question about the timeline rather than about the frame
    /// under the playhead: the note is about the clip, and a blend that has a
    /// backdrop for only half its span is not the mistake this warns about.
    private func hasVisibleLayerBehind(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot)
        -> Bool
    {
        guard let index = snapshot.tracks.firstIndex(where: { $0.id == clip.track }) else {
            return false
        }
        for track in snapshot.tracks.prefix(index) where !track.hidden {
            let covered = snapshot.clips(onTrack: track.id).contains { other in
                other.enabled.video && other.start < clip.end && other.end > clip.start
            }
            if covered { return true }
        }
        return false
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
}
