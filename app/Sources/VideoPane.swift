import AppKit

/// The Clip tab's PIXEL sections (spec §4.3): Transform, Crop, Corner Radius,
/// Colour, Chroma Key, Filters, Reflection, Spotlight, Obscure, Speed and —
/// when the clip overlaps its predecessor — Transition.
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
                inspectorRow(
                    "Blend", [blend], mixed: { binding.mixedVideo { $0.blend } }, binding: binding,
                    writes: binding.ops(video: VideoPatch(blend: binding.videoProps.blend)),
                    default: .derived(
                        binding, name: "Blend Mode", read: { binding.videoProps.blend },
                        ops: { binding.ops(video: VideoPatch(blend: $0)) })),
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
                        var c = current()
                        c.key = chromaKeyComponents(color)
                        return ops(c)
                    },
                    mixed: { binding.mixedVideo { $0.chroma?.key } },
                    enabled: on),
                inspectorButtonRow([pick]),
                inspectorValueRow(
                    "Tolerance", binding, name: "Chroma Tolerance", unit: "%", decimals: 0,
                    min: 0, max: 100, quick: [0, 10, 20, 40, 60],
                    read: { current().tolerance * 100 },
                    ops: { value in
                        var c = current()
                        c.tolerance = value / 100
                        return ops(c)
                    },
                    mixed: { binding.mixedVideo { $0.chroma?.tolerance } },
                    enabled: on),
                inspectorValueRow(
                    "Softness", binding, name: "Chroma Softness", unit: "%", decimals: 0,
                    min: 0, max: 100, quick: [0, 5, 10, 25, 50],
                    read: { current().softness * 100 },
                    ops: { value in
                        var c = current()
                        c.softness = value / 100
                        return ops(c)
                    },
                    mixed: { binding.mixedVideo { $0.chroma?.softness } },
                    enabled: on),
                inspectorValueRow(
                    "Spill", binding, name: "Chroma Spill", unit: "%", decimals: 0,
                    min: 0, max: 100, quick: [0, 25, 50, 75, 100],
                    read: { current().spill * 100 },
                    ops: { value in
                        var c = current()
                        c.spill = value / 100
                        return ops(c)
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
                }, binding: binding, writes: ops(writeList()))
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
            reset: { binding.apply("Filters", video: VideoPatch(filters: [])) },
            differs: { !list().isEmpty },
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
                        var r = current()
                        r.opacity = value / 100
                        return ops(r)
                    },
                    mixed: { binding.mixedVideo { $0.reflection?.opacity } },
                    enabled: on),
                inspectorValueRow(
                    "Height", binding, name: "Reflection Height", unit: "%", decimals: 0,
                    min: 0, max: 100, quick: [25, 50, 75, 100],
                    read: { current().height * 100 },
                    ops: { value in
                        var r = current()
                        r.height = value / 100
                        return ops(r)
                    },
                    mixed: { binding.mixedVideo { $0.reflection?.height } },
                    enabled: on),
                inspectorValueRow(
                    "Gap", binding, name: "Reflection Gap", unit: " px", decimals: 0, min: 0,
                    max: 200, quick: [0, 4, 8, 16, 32],
                    read: { current().gap },
                    ops: { value in
                        var r = current()
                        r.gap = value
                        return ops(r)
                    },
                    mixed: { binding.mixedVideo { $0.reflection?.gap } },
                    enabled: on),
                inspectorValueRow(
                    "Falloff", binding, name: "Reflection Falloff", unit: "%", decimals: 0,
                    min: 0, max: 100, quick: [0, 25, 50, 75, 100],
                    read: { current().falloff * 100 },
                    ops: { value in
                        var r = current()
                        r.falloff = value / 100
                        return ops(r)
                    },
                    mixed: { binding.mixedVideo { $0.reflection?.falloff } },
                    enabled: on),
            ])
    }

    // MARK: Spotlight

    /// Darkens the canvas outside a rectangle or ellipse and optionally
    /// magnifies what is inside it — a stand-in for a freehand
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
    /// needs goes through `edited { … }` — each row sets its one field on a
    /// copy of the current value, and the other seven ride along.
    func spotlightSection() -> InspectorSection {
        let binding = self.binding
        let shapes = SpotShape.allCases
        func current() -> SpotlightProps { binding.videoProps.spotlight ?? SpotlightProps() }
        func on() -> Bool { binding.videoProps.spotlight != nil }
        func edited(_ change: (inout SpotlightProps) -> Void) -> [ReelOp] {
            var s = current()
            change(&s)
            return binding.ops(video: VideoPatch(spotlight: .some(s)))
        }
        return InspectorSection(
            id: "video.spotlight", title: "Spotlight",
            summary: { on() ? current().shape.displayName.lowercased() : "off" },
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
                        return edited { $0.shape = shapes[index] }
                    },
                    mixed: { binding.mixedVideo { $0.spotlight?.shape } },
                    enabled: on),
                inspectorValueRow(
                    "Center X", binding, name: "Spotlight Center", unit: " px", decimals: 0,
                    min: -20000, max: 20000, slider: false,
                    read: { current().x },
                    ops: { v in edited { $0.x = v } },
                    mixed: { binding.mixedVideo { $0.spotlight?.x } },
                    enabled: on),
                inspectorValueRow(
                    "Center Y", binding, name: "Spotlight Center", unit: " px", decimals: 0,
                    min: -20000, max: 20000, slider: false,
                    read: { current().y },
                    ops: { v in edited { $0.y = v } },
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
                    ops: { v in edited { $0.width = v } },
                    mixed: { binding.mixedVideo { $0.spotlight?.width } },
                    enabled: on),
                inspectorValueRow(
                    "Height", binding, name: "Spotlight Size", unit: " px", decimals: 0, min: 1,
                    max: 20000, quick: [135, 270, 405, 540], slider: false,
                    read: { current().height },
                    ops: { v in edited { $0.height = v } },
                    mixed: { binding.mixedVideo { $0.spotlight?.height } },
                    enabled: on),
                inspectorValueRow(
                    "Feather", binding, name: "Spotlight Feather", unit: " px", decimals: 0,
                    min: 0, max: 200, quick: [0, 10, 20, 40, 80],
                    read: { current().feather },
                    ops: { v in edited { $0.feather = v } },
                    mixed: { binding.mixedVideo { $0.spotlight?.feather } },
                    enabled: on),
                inspectorValueRow(
                    "Dim", binding, name: "Spotlight Dim", unit: "%", decimals: 0, min: 0,
                    max: 100, quick: [0, 30, 60, 80, 100],
                    read: { current().dim * 100 },
                    ops: { v in edited { $0.dim = v / 100 } },
                    mixed: { binding.mixedVideo { $0.spotlight?.dim } },
                    enabled: on),
                // 1 is "no zoom" and 2× is the ceiling `SPOT_ZOOM_MAX` puts
                // on it: the pixels come from the same decoded frame, and
                // past 2× nothing is left but softness.
                inspectorValueRow(
                    "Zoom", binding, name: "Spotlight Zoom", unit: "×", decimals: 2, min: 1,
                    max: 2, quick: [1, 1.2, 1.5, 2],
                    read: { current().zoom },
                    ops: { v in edited { $0.zoom = v } },
                    mixed: { binding.mixedVideo { $0.spotlight?.zoom } },
                    enabled: on),
            ])
    }
}
