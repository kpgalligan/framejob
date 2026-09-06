import AppKit

/// The Video tab (spec §4.3): Transform, Crop, Corner Radius, Shadow, Colour,
/// Chroma Key, Filters, Reflection, Spotlight, Speed, Actions and — when the
/// clip overlaps its predecessor — Transition.
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
        // The filter stack is the one section whose ROW COUNT comes from the
        // model, so its length belongs here: adding or removing a filter has
        // to rebuild the pane, while re-ordering or re-dialling one only
        // refreshes it (the rows read by index, so the values simply move).
        parts.append("f\(binding.videoProps.filters.count)")
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
            sections.append(chromaSection())
        }
        sections.append(filtersSection())
        sections.append(reflectionSection())
        sections.append(spotlightSection())
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

    // MARK: Chroma key

    /// The M3 green-screen group (§4.3): the switch, the key colour with its
    /// canvas eyedropper, and the three knobs the shader keys with. The core
    /// bounds all four of them to 0…1 (`edit_props.rs`'s `video.chroma.*`),
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
    private func chromaSection() -> InspectorSection {
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
            note: { binding.actionNote },
            reset: { binding.apply("Chroma Key", video: VideoPatch(chroma: .some(nil))) },
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
    private func filtersSection() -> InspectorSection {
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
        /// One slot changed, the rest of the stack as it stands. An index the
        /// model no longer holds yields the list unchanged, which the core
        /// answers as the identity it is (`None`, a refusal beep, no undo
        /// step) — the row is a frame behind its rebuild there, and writing a
        /// guess about which filter was meant would be worse than a beep.
        func replacing(_ index: Int, _ next: FilterProps) -> [FilterProps] {
            var filters = list()
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
                    var next = list()
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
                    guard let filter = at(index), kinds.indices.contains(choice) else { return }
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
                        guard let filter = at(index) else { return [] }
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
        add.toolTip = "Append a half-strength blur to the end of the stack"
        rows.append(
            inspectorButtonRow([add, InspectorRowLabel("\(FilterProps.max) at most")]))

        return InspectorSection(
            id: "video.filters", title: "Filters",
            note: { binding.actionNote },
            reset: { binding.apply("Filters", video: VideoPatch(filters: [])) },
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
    private func reflectionSection() -> InspectorSection {
        let binding = self.binding
        func current() -> ReflectionProps { binding.videoProps.reflection ?? ReflectionProps() }
        func ops(_ next: ReflectionProps) -> [ReelOp] {
            binding.ops(video: VideoPatch(reflection: .some(next)))
        }
        func on() -> Bool { binding.videoProps.reflection != nil }
        return InspectorSection(
            id: "video.reflection", title: "Reflection",
            note: { binding.actionNote },
            reset: { binding.apply("Reflection", video: VideoPatch(reflection: .some(nil))) },
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
    private func spotlightSection() -> InspectorSection {
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
            note: { binding.actionNote },
            reset: { binding.apply("Spotlight", video: VideoPatch(spotlight: .some(nil))) },
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

    // MARK: Speed

    /// Speed is a clip-level op, not a patch: `set_speed` takes one clip and
    /// re-times its actions (§6), so the selection becomes one op each and the
    /// whole batch is a single undo step. `set_reversed` is the same shape.
    ///
    /// **Reverse carries a state readout that no other control here needs.**
    /// AVFoundation cannot play a clip backwards, so ticking the box does not
    /// change the picture by itself: it makes the app pre-render the frames
    /// (spec §11), and until they exist the clip draws a slate rather than
    /// lying about which way it is going. The readout says which of those the
    /// clip is in, and the button is what restarts a render the user stopped
    /// — the one path back from `ReverseStatus.stopped`, since nothing retries
    /// on its own.
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
        func status() -> ReverseStatus {
            guard let document = binding.document, let clip = binding.primary else { return .off }
            return document.reverseStatus(of: clip)
        }
        let render = OptionButtonControl(
            title: "Render Reverse",
            action: { [weak self] in
                guard let binding = self?.binding, let clip = binding.primary else { return }
                binding.document?.retryReversedMedia(for: clip)
            },
            enabled: { status() == .stopped },
            onEdit: {})
        render.toolTip = "Render the reversed frames this clip needs"
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
                inspectorCheckRow(
                    "Reverse", binding, name: "Reverse",
                    read: { binding.primary?.source.isReversed ?? false },
                    ops: { value in
                        binding.clips.filter { $0.source.hasSourceBound }
                            .map { .setReversed(clip: $0.id, reversed: value) }
                    },
                    mixed: { binding.mixed { $0.source.isReversed } }),
                inspectorRow("Reversed frames", [inspectorReadout { status().summary }]),
                inspectorButtonRow([render]),
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
