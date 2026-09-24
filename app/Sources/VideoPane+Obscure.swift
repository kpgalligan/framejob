import AppKit

extension VideoPane {
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
                    mixed: { mixedAt(index) { $0.kind } },
                    binding: binding, writes: edited(index)))
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
                    mixed: { mixedAt(index) { $0.x } || mixedAt(index) { $0.y } },
                    binding: binding, writes: edited(index, x: writeAt(index)?.x)))
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
                    mixed: { mixedAt(index) { $0.width } || mixedAt(index) { $0.height } },
                    binding: binding, writes: edited(index, width: writeAt(index)?.width)))
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
            reset: { binding.apply("Obscure", video: VideoPatch(obscure: [])) },
            differs: { !list().isEmpty },
            defaultExpanded: false,
            rows: rows)
    }
}
