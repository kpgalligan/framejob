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

    // MARK: Crop

    func cropSection() -> InspectorSection {
        let binding = self.binding
        func crop() -> CropInsets { binding.videoProps.crop }
        func ops(_ next: CropInsets) -> [ReelOp] { binding.ops(video: VideoPatch(crop: next)) }
        let cropButton = commandButton(
            "Crop on Canvas", #selector(EditorViewController.toggleCropMode(_:)),
            toolTip: "Drag the crop edges on the canvas (C)")
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
        let pick = commandButton(
            "Pick from Canvas", #selector(EditorViewController.pickChromaKey(_:)),
            toolTip: "Click the preview to sample the key color (Esc cancels)")
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

    // MARK: Reflection

    /// The mirrored copy drawn below the layer (§4.3's M3 list).
    ///
    /// `height` is a FRACTION of the layer's cropped height — half the layer,
    /// however big it is — and `falloff` how far it fades across that height,
    /// so both are dialled as percentages; `gap` is source pixels, the frame
    /// the crop, the corner radius and the shadow's distance already work in.
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
