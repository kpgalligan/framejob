import AppKit

/// The Clip tab's PIXEL sections (spec §4.3): Transform, Crop, Corner Radius,
/// Colour, Chroma Key, Filters, Reflection, Spotlight, Obscure, Speed,
/// Actions and — when the clip overlaps its predecessor — Transition.
///
/// **This pane is never shown.** Since the six tabs became three it is a
/// factory: `ClipPane` holds one instance and calls the section methods below
/// in the order the design asks for, mixing them with the audio, text and
/// shape panes' sections according to what is selected. Everything here still
/// reads and writes through the shared `InspectorBinding`, so the sections do
/// not care which pane built them. `structureSignature` is still this pane's
/// job — `ClipPane` composes it with the other three.
///
/// Text and shape clips get the groups that measure the layer against itself
/// — Transform, Opacity, Shadow, Filters, Reflection and Spotlight — but not
/// the ones that need a decoded frame behind them, which is why Crop, Corner
/// Radius, Colour and Chroma Key are gated on `allSourcePixels` and Speed on
/// `allMedia` (only a `media` source accepts `set_speed`, §6). Filters,
/// Reflection and Spotlight follow Shadow's precedent rather than Chroma's:
/// their lengths are source pixels and their strengths are fractions of the
/// layer's own rectangle, both of which a text or shape layer has (the
/// renderer measures it). A section that does not apply is absent rather than
/// disabled: the pane is rebuilt when the selection's kinds change, so there
/// is nothing stale to grey out.
final class VideoPane: InspectorPaneView {
    // MARK: - Applicability

    /// Clips whose rectangle comes from decoded pixels — the ones with a crop,
    /// a colour treatment and a corner radius.
    var allSourcePixels: Bool {
        let clips = binding.clips
        return !clips.isEmpty
            && clips.allSatisfy { InspectorTab.hasSourcePixels($0, in: binding.snapshot) }
    }

    /// Clips `set_speed` accepts (§6: a non-media source is an error).
    var allMedia: Bool {
        let clips = binding.clips
        return !clips.isEmpty && clips.allSatisfy { $0.source.hasSourceBound }
    }

    /// The overlap with the previous clip on the same track, when there is
    /// one. That overlap IS the transition's duration (§5.2).
    func overlap(before clip: ClipSnapshot) -> Ticks? {
        let earlier = binding.snapshot.clips(onTrack: clip.track).filter { $0.start < clip.start }
        guard let previous = earlier.last else { return nil }
        let overlap = previous.end - clip.start
        return overlap > 0 ? overlap : nil
    }

    override var structureSignature: String {
        var parts = [super.structureSignature]
        parts.append(allSourcePixels ? "px" : "-")
        parts.append(allMedia ? "media" : "-")
        // The filter stack is one of the two sections whose ROW COUNT comes
        // from the model, so its length belongs here: adding or removing a
        // filter has to rebuild the pane, while re-ordering or re-dialling
        // one only refreshes it (the rows read by index, so the values
        // simply move).
        parts.append("f\(binding.videoProps.filters.count)")
        // The obscure list is the second one, and for the same reason: Add,
        // Remove and "Place on Canvas" all change how many rows the section
        // has, while dialling a region's amount only changes what they read.
        parts.append("o\(binding.videoProps.obscure.count)")
        if binding.isSingle, let clip = binding.primary {
            parts.append(clip.actions.map { String($0.id) }.joined(separator: "."))
            parts.append(overlap(before: clip) != nil ? "transition" : "-")
        }
        return parts.joined(separator: "|")
    }

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
            // The action note first: where an edit LANDS outranks anything
            // about what it looks like. Then the nest note, which says why a
            // row is GREY — a disabled control the reader cannot explain
            // outranks a warning about one that works — and the blend note
            // last, since it only ever appears when the mode is one that
            // cannot be seen at all.
            note: { [weak self] in
                binding.actionNote ?? self?.nestBlendNote() ?? self?.blendNote()
            },
            reset: {
                binding.apply(
                    "Reset Transform",
                    video: VideoPatch(
                        x: 0, y: 0, scale: 1, rotation: 0, opacity: 1, blend: .normal))
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
                inspectorRow("Blend", [blend], mixed: { binding.mixedVideo { $0.blend } }),
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
    /// (`edit_props.rs`) is the refusal and `clamp_video` (`actions.rs`) is
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
    /// modes — the same property `Compositor.swift`'s shadow mask relies on.
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

    // MARK: Crop

    func cropSection() -> InspectorSection {
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
            summary: {
                let c = crop()
                guard c.l != 0 || c.t != 0 || c.r != 0 || c.b != 0 else { return "none" }
                return String(format: "%.0f·%.0f·%.0f·%.0f", c.l, c.t, c.r, c.b)
            },
            note: { binding.actionNote },
            reset: { binding.apply("Crop", video: VideoPatch(crop: .zero)) },
            defaultExpanded: false,
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

    func cornerSection() -> InspectorSection {
        let binding = self.binding
        return InspectorSection(
            id: "video.corner", title: "Corner Radius",
            summary: { String(format: "%.0f px", binding.videoProps.cornerRadius) },
            note: { binding.actionNote },
            reset: { binding.apply("Corner Radius", video: VideoPatch(cornerRadius: 0)) },
            defaultExpanded: false,
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

    func colorSection() -> InspectorSection {
        let binding = self.binding
        func color() -> ColorAdjust { binding.videoProps.color }
        func ops(_ next: ColorAdjust) -> [ReelOp] { binding.ops(video: VideoPatch(color: next)) }
        return InspectorSection(
            id: "video.color", title: "Color",
            summary: { color().isIdentity ? "neutral" : "adjusted" },
            note: { binding.actionNote },
            reset: { binding.apply("Color", video: VideoPatch(color: .identity)) },
            defaultExpanded: false,
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

    // MARK: Chroma key

    /// The M3 green-screen group (§4.3): the switch, the key colour with its
    /// canvas eyedropper, and the three knobs the shader keys with. The core
    /// bounds all four of them to 0…1 (`props_check.rs`'s `video.chroma.*`),
    /// so the three are dialled as percentages of that range and the colour
    /// is written as the three components `chroma.key` is — the one colour in
    /// the schema with no alpha in it.
    ///
    /// Every control writes a WHOLE `ChromaProps`, exactly as the Shadow
    /// group does: the patch replaces the object, so each edit re-sends the
    /// other three values as they stand.
    ///
    /// "Pick from Canvas" stays live with the key switched OFF, and picking
    /// then turns it on: someone who has just aimed at the green has already
    /// said what they want, and making them flip a switch first to be allowed
    /// to say it is a step that carries no decision.
    func chromaSection() -> InspectorSection {
        let binding = self.binding
        func current() -> ChromaProps { binding.videoProps.chroma ?? ChromaProps() }
        func ops(_ next: ChromaProps) -> [ReelOp] {
            binding.ops(video: VideoPatch(chroma: .some(next)))
        }
        func on() -> Bool { binding.videoProps.chroma != nil }
        let pick = OptionButtonControl(
            title: "Pick from Canvas",
            action: { [weak self] in
                self?.inspector?.onCommand?(#selector(EditorViewController.pickChromaKey(_:)))
            },
            enabled: { true }, onEdit: {})
        pick.toolTip = "Click the preview to sample the key color (Esc cancels)"
        return InspectorSection(
            id: "video.chroma", title: "Chroma Key",
            summary: { on() ? String(format: "%.0f%%", current().tolerance * 100) : "off" },
            note: { binding.actionNote },
            reset: { binding.apply("Chroma Key", video: VideoPatch(chroma: .some(nil))) },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Key out a color", binding, name: "Chroma Key",
                    read: on,
                    ops: { value in
                        binding.ops(
                            video: VideoPatch(chroma: value ? .some(ChromaProps()) : .some(nil)))
                    },
                    mixed: { binding.mixedVideo { $0.chroma != nil } }),
                inspectorColorRow(
                    "Key Color", binding, name: "Chroma Key Color",
                    // Padded to four components on the way in and cut back to
                    // three on the way out: `changedRGBA`'s unchanged-colour
                    // guard compares component by component and gives up when
                    // the two lengths differ — which, with the colour panel
                    // writing continuously through a drag, would beep at every
                    // mouse-moved event that changed nothing.
                    read: { current().key + [1] },
                    ops: { color in
                        let c = current()
                        return ops(
                            ChromaProps(
                                key: chromaKeyComponents(color), tolerance: c.tolerance,
                                softness: c.softness, spill: c.spill))
                    },
                    mixed: { binding.mixedVideo { $0.chroma?.key } },
                    enabled: on),
                inspectorButtonRow([pick]),
                inspectorValueRow(
                    "Tolerance", binding, name: "Chroma Tolerance", unit: "%", decimals: 0,
                    min: 0, max: 100, quick: [0, 10, 20, 40, 60],
                    read: { current().tolerance * 100 },
                    ops: { value in
                        let c = current()
                        return ops(
                            ChromaProps(
                                key: c.key, tolerance: value / 100, softness: c.softness,
                                spill: c.spill))
                    },
                    mixed: { binding.mixedVideo { $0.chroma?.tolerance } },
                    enabled: on),
                inspectorValueRow(
                    "Softness", binding, name: "Chroma Softness", unit: "%", decimals: 0,
                    min: 0, max: 100, quick: [0, 5, 10, 25, 50],
                    read: { current().softness * 100 },
                    ops: { value in
                        let c = current()
                        return ops(
                            ChromaProps(
                                key: c.key, tolerance: c.tolerance, softness: value / 100,
                                spill: c.spill))
                    },
                    mixed: { binding.mixedVideo { $0.chroma?.softness } },
                    enabled: on),
                inspectorValueRow(
                    "Spill", binding, name: "Chroma Spill", unit: "%", decimals: 0,
                    min: 0, max: 100, quick: [0, 25, 50, 75, 100],
                    read: { current().spill * 100 },
                    ops: { value in
                        let c = current()
                        return ops(
                            ChromaProps(
                                key: c.key, tolerance: c.tolerance, softness: c.softness,
                                spill: value / 100))
                    },
                    mixed: { binding.mixedVideo { $0.chroma?.spill } },
                    enabled: on),
            ])
    }

    // MARK: Filters

    /// The filter stack (§4.3's M3 list), at most `FilterProps.max` deep.
    ///
    /// **Order is the whole point.** The compositor applies `video.filters`
    /// in the order they are listed, so blur-then-sepia and sepia-then-blur
    /// are different pictures, and a control set that cannot say which comes
    /// first would be lying about what the layer does. That is why each
    /// filter's row leads with a POSITION popup rather than an ordinal label:
    /// the number both shows where the filter sits and is the thing that
    /// moves it. It occupies the label column the rest of the inspector
    /// already reserves, where a Move Up / Move Down pair costs two controls
    /// beyond it and up-only costs one plus a dead first row; and with four
    /// slots it reaches any order in one gesture rather than three.
    ///
    /// Nothing here is a general-purpose list editor, and it must not become
    /// one: the cap is four, so the whole stack is on screen at once, the
    /// rows are built against a fixed index (the count is in
    /// `structureSignature`, so add and remove rebuild the pane while a
    /// re-order merely refreshes it), and every write sends the WHOLE array.
    /// That last point is what keeps add, remove and re-order ordinary
    /// `set_video` patches instead of three new ops — `actions::merge`
    /// replaces arrays wholesale rather than merging them element by element.
    ///
    /// Adding and removing a filter change the CLIP, not the action under the
    /// playhead, even when the section's note says an edit here lands on an
    /// action's end state: a list of a different length in an end patch
    /// cannot interpolate, so it would be invisible for the whole span and
    /// destroyed by the next write. `InspectorBinding.structural(video:for:)`
    /// is where that is decided, for this list and the obscure one alike, and
    /// it argues the whole rule.
    ///
    /// **A row READS the evaluated stack and WRITES the one it is replacing**,
    /// which are the same array everywhere except inside an action —
    /// `writeList()` below, and `InspectorBinding.editedList`, which argues it.
    /// One residual is left deliberately: Add and Remove still build from the
    /// evaluated stack, because `structural` routes them to the BASE props and
    /// the entries they carry across are therefore the values at the playhead
    /// rather than the clip's own. It is the same family of defect one step
    /// out, it is older than the write list, and fixing it means deciding
    /// which of two arrays an add is really an edit of — a question the length
    /// rule above does not answer.
    func filtersSection() -> InspectorSection {
        let binding = self.binding
        let kinds = FilterKind.allCases
        func list() -> [FilterProps] { binding.videoProps.filters }
        func at(_ index: Int) -> FilterProps? {
            let filters = list()
            return filters.indices.contains(index) ? filters[index] : nil
        }
        func ops(_ next: [FilterProps]) -> [ReelOp] {
            binding.ops(video: VideoPatch(filters: next))
        }
        /// The stack an EDIT is built on, which inside an action is not the
        /// one the rows are showing: the action's own end `filters` when its
        /// end patch carries them, the clip's base stack otherwise
        /// (`InspectorBinding.editedList`, which argues it). `list()` above
        /// stays the read — every row goes on showing the picture at the
        /// playhead — and this is the write. Without the pair, dialling one
        /// filter re-sent every OTHER filter at its interpolated value and
        /// flattened its ramp.
        func writeList() -> [FilterProps] {
            binding.editedList(action: { $0.filters }, base: { $0.filters })
        }
        func writeAt(_ index: Int) -> FilterProps? {
            let filters = writeList()
            return filters.indices.contains(index) ? filters[index] : nil
        }
        /// One slot changed, the rest of the stack as it stands. An index the
        /// model no longer holds yields the list unchanged, which the core
        /// answers as the identity it is — the same beep a refusal gets, no
        /// undo step either way. The row is a frame behind its rebuild there,
        /// and a guess about which filter was meant would be worse.
        func replacing(_ index: Int, _ next: FilterProps) -> [FilterProps] {
            var filters = writeList()
            guard filters.indices.contains(index) else { return filters }
            filters[index] = next
            return filters
        }

        let count = list().count
        func row(_ index: Int) -> NSView {
            let order = OptionPopupControl(
                width: InspectorMetrics.labelWidth,
                items: (1...Swift.max(count, 1)).map { String($0) },
                read: { index },
                write: { position in
                    // The write list, not the read one: a re-order keeps the
                    // LENGTH, so it lands on the action's end patch like any
                    // other dial, and building it from the evaluated stack
                    // would pin every filter's amount on its way past.
                    var next = writeList()
                    guard next.indices.contains(index), next.indices.contains(position),
                          position != index
                    else { return }
                    next.insert(next.remove(at: index), at: position)
                    binding.apply("Reorder Filters", ops(next))
                },
                enabled: { true },
                onEdit: { binding.edited() })
            order.toolTip = "Where this filter sits in the stack; they are applied in order"
            let kind = OptionPopupControl(
                width: 92, items: kinds.map { $0.displayName },
                read: { kinds.firstIndex(of: at(index)?.kind ?? .blur) ?? 0 },
                write: { choice in
                    // `writeAt`, so the amount carried alongside the new kind
                    // is the one the edit is replacing rather than the one
                    // under the playhead.
                    guard let filter = writeAt(index), kinds.indices.contains(choice)
                    else { return }
                    binding.apply(
                        "Filter Kind",
                        ops(
                            replacing(
                                index, FilterProps(kind: kinds[choice], amount: filter.amount))))
                },
                enabled: { true },
                onEdit: { binding.edited() })
            let remove = OptionButtonControl(
                title: "Remove",
                action: {
                    var next = list()
                    guard next.indices.contains(index) else {
                        NSSound.beep()
                        return
                    }
                    next.remove(at: index)
                    binding.apply("Remove Filter", ops(next))
                },
                enabled: { true }, onEdit: {})
            remove.toolTip =
                "Take this filter off the clip — the stack itself, not the action "
                + "under the playhead"
            return inspectorRow(
                nil, [order, kind, remove],
                mixed: {
                    binding.mixedVideo { props in
                        props.filters.indices.contains(index) ? props.filters[index].kind : nil
                    }
                })
        }

        var rows: [NSView] = []
        for index in 0..<count {
            rows.append(row(index))
            rows.append(
                inspectorValueRow(
                    "Amount", binding, name: "Filter Amount", unit: "%", decimals: 0, min: 0,
                    max: 100, quick: [0, 25, 50, 75, 100],
                    read: { (at(index)?.amount ?? 0) * 100 },
                    ops: { value in
                        guard let filter = writeAt(index) else { return [] }
                        return ops(
                            replacing(index, FilterProps(kind: filter.kind, amount: value / 100)))
                    },
                    mixed: {
                        binding.mixedVideo { props in
                            props.filters.indices.contains(index)
                                ? props.filters[index].amount : nil
                        }
                    }))
        }
        if count == 0 {
            rows.append(inspectorRow(nil, [InspectorRowLabel("No filters on this clip.")]))
        }
        let add = OptionButtonControl(
            title: "Add Filter",
            action: {
                var next = list()
                guard next.count < FilterProps.max else {
                    NSSound.beep()
                    return
                }
                next.append(FilterProps())
                binding.apply("Add Filter", ops(next))
            },
            enabled: { list().count < FilterProps.max }, onEdit: {})
        add.toolTip =
            "Append a half-strength blur to the end of the stack — on the clip itself, "
            + "not on the action under the playhead"
        rows.append(
            inspectorButtonRow([add, InspectorRowLabel("\(FilterProps.max) at most")]))

        return InspectorSection(
            id: "video.filters", title: "Filters",
            summary: {
                let stack = list()
                guard !stack.isEmpty else { return "none" }
                return stack.count == 1
                    ? stack[0].kind.displayName.lowercased() : "\(stack.count) filters"
            },
            note: { binding.actionNote },
            reset: { binding.apply("Filters", video: VideoPatch(filters: [])) },
            defaultExpanded: false,
            rows: rows)
    }

    // MARK: Reflection

    /// The mirrored copy drawn below the layer (§4.3's M3 list).
    ///
    /// `height` and `falloff` are FRACTIONS of the layer's cropped height —
    /// half the layer, however big the layer is — so both are dialled as
    /// percentages; `gap` is source pixels, the frame the crop, the corner
    /// radius and the shadow's distance already work in.
    ///
    /// Every control writes a WHOLE `ReflectionProps`, exactly as Shadow and
    /// Chroma Key do: the patch replaces the object, so each edit re-sends
    /// the other three values as they stand.
    func reflectionSection() -> InspectorSection {
        let binding = self.binding
        func current() -> ReflectionProps { binding.videoProps.reflection ?? ReflectionProps() }
        func ops(_ next: ReflectionProps) -> [ReelOp] {
            binding.ops(video: VideoPatch(reflection: .some(next)))
        }
        func on() -> Bool { binding.videoProps.reflection != nil }
        return InspectorSection(
            id: "video.reflection", title: "Reflection",
            summary: { on() ? String(format: "%.0f%%", current().opacity * 100) : "off" },
            note: { binding.actionNote },
            reset: { binding.apply("Reflection", video: VideoPatch(reflection: .some(nil))) },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Mirror the layer below itself", binding, name: "Reflection",
                    read: on,
                    ops: { value in
                        binding.ops(
                            video: VideoPatch(
                                reflection: value ? .some(ReflectionProps()) : .some(nil)))
                    },
                    mixed: { binding.mixedVideo { $0.reflection != nil } }),
                inspectorValueRow(
                    "Opacity", binding, name: "Reflection Opacity", unit: "%", decimals: 0,
                    min: 0, max: 100, quick: [0, 20, 35, 50, 75],
                    read: { current().opacity * 100 },
                    ops: { value in
                        let r = current()
                        return ops(
                            ReflectionProps(
                                opacity: value / 100, height: r.height, gap: r.gap,
                                falloff: r.falloff))
                    },
                    mixed: { binding.mixedVideo { $0.reflection?.opacity } },
                    enabled: on),
                inspectorValueRow(
                    "Height", binding, name: "Reflection Height", unit: "%", decimals: 0,
                    min: 0, max: 100, quick: [25, 50, 75, 100],
                    read: { current().height * 100 },
                    ops: { value in
                        let r = current()
                        return ops(
                            ReflectionProps(
                                opacity: r.opacity, height: value / 100, gap: r.gap,
                                falloff: r.falloff))
                    },
                    mixed: { binding.mixedVideo { $0.reflection?.height } },
                    enabled: on),
                inspectorValueRow(
                    "Gap", binding, name: "Reflection Gap", unit: " px", decimals: 0, min: 0,
                    max: 200, quick: [0, 4, 8, 16, 32],
                    read: { current().gap },
                    ops: { value in
                        let r = current()
                        return ops(
                            ReflectionProps(
                                opacity: r.opacity, height: r.height, gap: value,
                                falloff: r.falloff))
                    },
                    mixed: { binding.mixedVideo { $0.reflection?.gap } },
                    enabled: on),
                inspectorValueRow(
                    "Falloff", binding, name: "Reflection Falloff", unit: "%", decimals: 0,
                    min: 0, max: 100, quick: [0, 25, 50, 75, 100],
                    read: { current().falloff * 100 },
                    ops: { value in
                        let r = current()
                        return ops(
                            ReflectionProps(
                                opacity: r.opacity, height: r.height, gap: r.gap,
                                falloff: value / 100))
                    },
                    mixed: { binding.mixedVideo { $0.reflection?.falloff } },
                    enabled: on),
            ])
    }

    // MARK: Spotlight

    /// Darkens the canvas outside a rectangle or ellipse and optionally
    /// magnifies what is inside it — the stand-in for a screencast editor's freehand
    /// callout (§4.3's M3 list).
    ///
    /// It lives HERE and not in the Shape pane, where spec §4.3 first listed
    /// it, because the zoom half can only be drawn by the layer that owns the
    /// pixels: a separate darkening shape could dim the frame but could never
    /// magnify it. The centre and the box are SOURCE pixels measured from the
    /// centre of the cropped rect — the same frame Crop and Corner Radius use
    /// — so they are plain px fields rather than percentages, and the centre
    /// is allowed outside the layer (the core only asks that x and y be
    /// finite): half a spotlight running off the edge of the frame is a
    /// legitimate picture.
    ///
    /// Eight fields is enough that spelling all of them out at every row
    /// would bury the one that changes, so the whole-object write the patch
    /// needs goes through `edited(…)` — one named argument per row, the other
    /// seven re-read from the current value.
    func spotlightSection() -> InspectorSection {
        let binding = self.binding
        let shapes = SpotShape.allCases
        func current() -> SpotlightProps { binding.videoProps.spotlight ?? SpotlightProps() }
        func on() -> Bool { binding.videoProps.spotlight != nil }
        func edited(
            shape: SpotShape? = nil, x: Double? = nil, y: Double? = nil, width: Double? = nil,
            height: Double? = nil, feather: Double? = nil, dim: Double? = nil, zoom: Double? = nil
        ) -> [ReelOp] {
            let s = current()
            return binding.ops(
                video: VideoPatch(
                    spotlight: .some(
                        SpotlightProps(
                            shape: shape ?? s.shape, x: x ?? s.x, y: y ?? s.y,
                            width: width ?? s.width, height: height ?? s.height,
                            feather: feather ?? s.feather, dim: dim ?? s.dim,
                            zoom: zoom ?? s.zoom))))
        }
        return InspectorSection(
            id: "video.spotlight", title: "Spotlight",
            summary: { on() ? current().shape.displayName.lowercased() : "off" },
            note: { binding.actionNote },
            reset: { binding.apply("Spotlight", video: VideoPatch(spotlight: .some(nil))) },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Spotlight a region", binding, name: "Spotlight",
                    read: on,
                    ops: { value in
                        binding.ops(
                            video: VideoPatch(
                                spotlight: value ? .some(SpotlightProps()) : .some(nil)))
                    },
                    mixed: { binding.mixedVideo { $0.spotlight != nil } }),
                inspectorPopupRow(
                    "Shape", binding, name: "Spotlight Shape",
                    items: shapes.map { $0.displayName },
                    read: { shapes.firstIndex(of: current().shape) ?? 0 },
                    ops: { index in
                        guard shapes.indices.contains(index) else { return [] }
                        return edited(shape: shapes[index])
                    },
                    mixed: { binding.mixedVideo { $0.spotlight?.shape } },
                    enabled: on),
                inspectorValueRow(
                    "Center X", binding, name: "Spotlight Center", unit: " px", decimals: 0,
                    min: -20000, max: 20000, slider: false,
                    read: { current().x },
                    ops: { edited(x: $0) },
                    mixed: { binding.mixedVideo { $0.spotlight?.x } },
                    enabled: on),
                inspectorValueRow(
                    "Center Y", binding, name: "Spotlight Center", unit: " px", decimals: 0,
                    min: -20000, max: 20000, slider: false,
                    read: { current().y },
                    ops: { edited(y: $0) },
                    mixed: { binding.mixedVideo { $0.spotlight?.y } },
                    enabled: on),
                // The core takes width and height as strictly greater than
                // zero (`above`, not `at_least`): a spotlight with no area is
                // a fully dimmed frame with no way back, so the field's floor
                // is one pixel rather than nought.
                inspectorValueRow(
                    "Width", binding, name: "Spotlight Size", unit: " px", decimals: 0, min: 1,
                    max: 20000, quick: [240, 480, 720, 960], slider: false,
                    read: { current().width },
                    ops: { edited(width: $0) },
                    mixed: { binding.mixedVideo { $0.spotlight?.width } },
                    enabled: on),
                inspectorValueRow(
                    "Height", binding, name: "Spotlight Size", unit: " px", decimals: 0, min: 1,
                    max: 20000, quick: [135, 270, 405, 540], slider: false,
                    read: { current().height },
                    ops: { edited(height: $0) },
                    mixed: { binding.mixedVideo { $0.spotlight?.height } },
                    enabled: on),
                inspectorValueRow(
                    "Feather", binding, name: "Spotlight Feather", unit: " px", decimals: 0,
                    min: 0, max: 200, quick: [0, 10, 20, 40, 80],
                    read: { current().feather },
                    ops: { edited(feather: $0) },
                    mixed: { binding.mixedVideo { $0.spotlight?.feather } },
                    enabled: on),
                inspectorValueRow(
                    "Dim", binding, name: "Spotlight Dim", unit: "%", decimals: 0, min: 0,
                    max: 100, quick: [0, 30, 60, 80, 100],
                    read: { current().dim * 100 },
                    ops: { edited(dim: $0 / 100) },
                    mixed: { binding.mixedVideo { $0.spotlight?.dim } },
                    enabled: on),
                // 1 is "no zoom" and 2× is the ceiling `SPOT_ZOOM_MAX` puts
                // on it: the pixels come from the same decoded frame, and
                // past 2× nothing is left but softness.
                inspectorValueRow(
                    "Zoom", binding, name: "Spotlight Zoom", unit: "×", decimals: 2, min: 1,
                    max: 2, quick: [1, 1.2, 1.5, 2],
                    read: { current().zoom },
                    ops: { edited(zoom: $0) },
                    mixed: { binding.mixedVideo { $0.spotlight?.zoom } },
                    enabled: on),
            ])
    }

    // MARK: Obscure

    /// The obscured regions (§4.3's phase-3c list, schema version 4): boxes
    /// on the layer whose contents are blurred or pixelated so a face, a
    /// password field or a notification cannot be read.
    ///
    /// It is the spotlight's inverse and it is spelled in the spotlight's
    /// frame — `x`/`y` are the region's CENTRE and `width`/`height` its size,
    /// both in SOURCE pixels from the centre of the cropped rect — so a
    /// region rides with its layer through scale, move and rotation, and the
    /// same four numbers typed into Spotlight put a box in the same place.
    /// That is also why the numeric rows are plain px fields rather than
    /// percentages, and why a centre outside the layer is allowed.
    ///
    /// **It is a LIST, so it takes `filtersSection`'s shape and its warning
    /// with it.** Nothing here is a general-purpose list editor and it must
    /// not become one: the cap is four, so every region is on screen at
    /// once; the rows are built against a FIXED INDEX (the count is in
    /// `structureSignature`, so add and remove rebuild the pane while
    /// dialling a value merely refreshes it); an index the model no longer
    /// holds yields the list unchanged, which the core answers as the
    /// identity it is; and every write sends the WHOLE array through an
    /// ordinary `set_video` patch, which is what keeps add and remove out of
    /// the op table (`actions::merge` replaces arrays wholesale).
    ///
    /// **Adding and removing a region change the CLIP**, not the action under
    /// the playhead — including "Place on Canvas", which is an append like
    /// any other. A list of a different length in an action's end patch
    /// cannot interpolate, so an appended region would be invisible for the
    /// whole span and gone at the next write; dialling an existing region's
    /// amount or box still belongs to the action, which is what §3c's
    /// interpolation rule is for. `InspectorBinding.structural(video:for:)`
    /// decides it, for this list and the filter stack alike, and argues it in
    /// full.
    ///
    /// Order does NOT matter here, unlike the filter stack: where two
    /// regions overlap the shader takes the STRONGER of them per fragment,
    /// so there is no position popup to move a region up or down and the
    /// label column carries the region's number instead.
    ///
    /// **One "Place on Canvas", not one per row.** It appends, and it is
    /// disabled at the cap. `InspectorViewController.onCommand` is
    /// `(Selector) -> Void` and carries no index (`inspectorCommand` sends a
    /// nil sender), so a per-row button would need an index-carrying seam of
    /// its own — the first of its kind, added for one button, against the
    /// warning above. A region placed on the canvas is edited in its row like
    /// any other.
    func obscureSection() -> InspectorSection {
        let binding = self.binding
        let shapes = SpotShape.allCases
        let kinds = ObscureKind.allCases
        func list() -> [ObscureProps] { binding.videoProps.obscure }
        func at(_ index: Int) -> ObscureProps? {
            let regions = list()
            return regions.indices.contains(index) ? regions[index] : nil
        }
        func ops(_ next: [ObscureProps]) -> [ReelOp] {
            binding.ops(video: VideoPatch(obscure: next))
        }
        /// The read/write split the filter stack takes, for the same reason
        /// and out of the same reader: inside an action a write REPLACES the
        /// end patch's array whole, so building it from the interpolated
        /// regions would pin every one the user did not touch — and with
        /// eight fields a region, seven of them ride along on every edit.
        func writeList() -> [ObscureProps] {
            binding.editedList(action: { $0.obscure }, base: { $0.obscure })
        }
        func writeAt(_ index: Int) -> ObscureProps? {
            let regions = writeList()
            return regions.indices.contains(index) ? regions[index] : nil
        }
        func replacing(_ index: Int, _ next: ObscureProps) -> [ObscureProps] {
            var regions = writeList()
            guard regions.indices.contains(index) else { return regions }
            regions[index] = next
            return regions
        }
        /// One field of one region changed, the other seven as they stand —
        /// `spotlightSection`'s `edited(…)` over a list. Eight fields is
        /// enough that spelling all of them out at every row would bury the
        /// one that changes.
        func edited(
            _ index: Int, shape: SpotShape? = nil, x: Double? = nil, y: Double? = nil,
            width: Double? = nil, height: Double? = nil, feather: Double? = nil,
            kind: ObscureKind? = nil, amount: Double? = nil
        ) -> [ReelOp] {
            // `writeAt`, not `at`: the seven fields that ride along are the
            // ones the edit is replacing, never the ones the playhead shows.
            guard let o = writeAt(index) else { return [] }
            return ops(
                replacing(
                    index,
                    ObscureProps(
                        shape: shape ?? o.shape, x: x ?? o.x, y: y ?? o.y,
                        width: width ?? o.width, height: height ?? o.height,
                        feather: feather ?? o.feather, kind: kind ?? o.kind,
                        amount: amount ?? o.amount)))
        }
        /// The mixed badge for one region's field: a selection where some
        /// clip has no region at that index disagrees, which the `nil` says.
        func mixedAt<T: Equatable>(_ index: Int, _ read: @escaping (ObscureProps) -> T) -> Bool {
            binding.mixedVideo { props in
                props.obscure.indices.contains(index) ? read(props.obscure[index]) : nil
            }
        }
        /// The paired numeric boxes. Centre and size get two fields on one
        /// row rather than the four separate value rows the spotlight gives
        /// them: four regions × eight rows would be a section nobody can see
        /// the end of, and neither pair wants a slider anyway (§4.3 gives
        /// the spotlight's own centre and size `slider: false`).
        func field(
            _ index: Int, name: String, min lower: Double, max upper: Double,
            quick: [Double] = [], read: @escaping (ObscureProps) -> Double,
            write: @escaping (Int, Double) -> [ReelOp]
        ) -> OptionFieldControl {
            OptionFieldControl(
                width: InspectorMetrics.fieldWidth, unit: " px", decimals: 0, min: lower,
                max: upper, quick: quick,
                read: { at(index).map(read) ?? 0 },
                write: { value in binding.apply(name, write(index, value)) },
                enabled: { true },
                onEdit: { binding.edited() })
        }

        let count = list().count
        var rows: [NSView] = []
        for index in 0..<count {
            let kind = OptionPopupControl(
                width: 96, items: kinds.map { $0.displayName },
                read: { kinds.firstIndex(of: at(index)?.kind ?? .pixelate) ?? 0 },
                write: { choice in
                    guard kinds.indices.contains(choice) else { return }
                    binding.apply("Obscure Kind", edited(index, kind: kinds[choice]))
                },
                enabled: { true },
                onEdit: { binding.edited() })
            kind.toolTip = "Pixelate hides; blur softens"
            let remove = OptionButtonControl(
                title: "Remove",
                action: {
                    var next = list()
                    guard next.indices.contains(index) else {
                        NSSound.beep()
                        return
                    }
                    next.remove(at: index)
                    binding.apply("Remove Region", ops(next))
                },
                enabled: { true }, onEdit: {})
            remove.toolTip =
                "Take this region off the clip — the clip itself, not the action "
                + "under the playhead"
            rows.append(
                inspectorRow(
                    "Region \(index + 1)", [kind, remove],
                    mixed: { mixedAt(index) { $0.kind } }))
            rows.append(
                inspectorPopupRow(
                    "Shape", binding, name: "Obscure Shape",
                    items: shapes.map { $0.displayName },
                    read: { shapes.firstIndex(of: at(index)?.shape ?? .rect) ?? 0 },
                    ops: { choice in
                        guard shapes.indices.contains(choice) else { return [] }
                        return edited(index, shape: shapes[choice])
                    },
                    mixed: { mixedAt(index) { $0.shape } }))
            rows.append(
                inspectorValueRow(
                    "Amount", binding, name: "Obscure Amount", unit: "%", decimals: 0, min: 0,
                    max: 100, quick: [0, 25, 50, 75, 100],
                    read: { (at(index)?.amount ?? 0) * 100 },
                    ops: { edited(index, amount: $0 / 100) },
                    mixed: { mixedAt(index) { $0.amount } }))
            rows.append(
                inspectorValueRow(
                    "Feather", binding, name: "Obscure Feather", unit: " px", decimals: 0,
                    min: 0, max: 200, quick: [0, 10, 20, 40, 80],
                    read: { at(index)?.feather ?? 0 },
                    ops: { edited(index, feather: $0) },
                    mixed: { mixedAt(index) { $0.feather } }))
            rows.append(
                inspectorRow(
                    "Center",
                    [
                        field(
                            index, name: "Obscure Center", min: -20000, max: 20000,
                            read: { $0.x }, write: { i, value in edited(i, x: value) }),
                        field(
                            index, name: "Obscure Center", min: -20000, max: 20000,
                            read: { $0.y }, write: { i, value in edited(i, y: value) }),
                    ],
                    mixed: { mixedAt(index) { $0.x } || mixedAt(index) { $0.y } }))
            // The core takes width and height as strictly greater than zero
            // (`above`, not `at_least`), exactly as it does the spotlight's:
            // a region with no area hides nothing and cannot be grabbed back,
            // so the field's floor is one pixel rather than nought.
            rows.append(
                inspectorRow(
                    "Size",
                    [
                        field(
                            index, name: "Obscure Size", min: 1, max: 20000,
                            quick: [120, 240, 480, 960], read: { $0.width },
                            write: { i, value in edited(i, width: value) }),
                        field(
                            index, name: "Obscure Size", min: 1, max: 20000,
                            quick: [68, 135, 270, 540], read: { $0.height },
                            write: { i, value in edited(i, height: value) }),
                    ],
                    mixed: { mixedAt(index) { $0.width } || mixedAt(index) { $0.height } }))
        }
        if count == 0 {
            rows.append(inspectorRow(nil, [InspectorRowLabel("No obscured regions.")]))
        }
        let add = OptionButtonControl(
            title: "Add Region",
            action: {
                var next = list()
                guard next.count < ObscureProps.max else {
                    NSSound.beep()
                    return
                }
                next.append(ObscureProps())
                binding.apply("Add Region", ops(next))
            },
            enabled: { list().count < ObscureProps.max }, onEdit: {})
        add.toolTip =
            "Add a 480 × 270 pixelated box at the centre of the layer — on the clip "
            + "itself, not on the action under the playhead"
        let place = OptionButtonControl(
            title: "Place on Canvas",
            action: { [weak self] in
                self?.inspector?.onCommand?(#selector(EditorViewController.placeObscureRegion(_:)))
            },
            enabled: { list().count < ObscureProps.max }, onEdit: {})
        place.toolTip =
            "Drag a rectangle on the canvas (Esc cancels) — it is appended to the clip "
            + "itself, not to the action under the playhead"
        rows.append(
            inspectorButtonRow([add, place, InspectorRowLabel("\(ObscureProps.max) at most")]))

        return InspectorSection(
            id: "video.obscure", title: "Obscure",
            summary: {
                let regions = list()
                guard !regions.isEmpty else { return "none" }
                return regions.count == 1
                    ? regions[0].kind.displayName.lowercased() : "\(regions.count) regions"
            },
            note: { binding.actionNote },
            reset: { binding.apply("Obscure", video: VideoPatch(obscure: [])) },
            defaultExpanded: false,
            rows: rows)
    }

    // MARK: Speed

    /// Speed is a clip-level op, not a patch: `set_speed` takes one clip and
    /// re-times its actions (§6), so the selection becomes one op each and the
    /// whole batch is a single undo step.
    ///
    /// Reverse used to sit here, next to Rate, because both re-time the same
    /// source. It now sits in the Clip tab's Timing section with In, Out and
    /// Duration, which is what the redesign asks for and reads better anyway:
    /// Rate is how fast, Reverse is which way, and the duration readout the
    /// two of them share belongs with the edges it is measured between.
    func speedSection() -> InspectorSection {
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
            summary: { String(format: "%.2f×", rate()) },
            reset: { binding.apply("Set Speed", speedOps(1, keepPitch: nil)) },
            defaultExpanded: false,
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
            ])
    }

    // MARK: Actions

    /// The actions table (§4.3). One clip at a time: an action id belongs to
    /// its clip, so a table over a multi-selection would be lying about which
    /// span it edits.
    func actionsSection() -> InspectorSection {
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
            // The screencast zoom (§4.2's region mode, `add_zoom_action`).
            // Both are ordinary actions once they land — they appear in the
            // table above with `scale, x, y` as their end patch — which is
            // why they are buttons in THIS section rather than a section of
            // their own. Neither has a menu item: the road map's list does
            // not name one and C's crop mode is the precedent for a canvas
            // mode reached by a bare key and a pane button.
            let zoom = OptionButtonControl(
                title: "Zoom to Region…",
                action: { [weak self] in
                    self?.inspector?.onCommand?(#selector(EditorViewController.zoomToRegion(_:)))
                },
                enabled: { true }, onEdit: {})
            zoom.toolTip = "Drag a rectangle on the canvas to zoom to it (Z; ⇧ fills)"
            let back = OptionButtonControl(
                title: "Zoom Back",
                action: { [weak self] in
                    self?.inspector?.onCommand?(#selector(EditorViewController.zoomBack(_:)))
                },
                enabled: { true }, onEdit: {})
            back.toolTip = "Add an action at the playhead returning the clip to its own transform"
            rows.append(inspectorButtonRow([zoom, back]))
        } else {
            rows.append(
                inspectorRow(nil, [InspectorRowLabel("Select one clip to edit its actions.")]))
        }
        return InspectorSection(
            id: "video.actions", title: "Actions",
            summary: {
                guard binding.isSingle, let clip = binding.primary else { return nil }
                return clip.actions.isEmpty ? "none" : "\(clip.actions.count)"
            },
            defaultExpanded: false, rows: rows)
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
}
