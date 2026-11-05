import AppKit

extension VideoPane {
    // MARK: Filters

    /// The filter stack (§4.3's M3 list), at most `FilterProps.max` deep.
    ///
    /// **Order matters among the point filters.** The compositor applies
    /// Sepia, Noir, Vignette and Invert in the order listed, after Blur,
    /// Sharpen and Pixelate, wherever those sit. That is why each
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
            order.toolTip = "Where this filter sits in the stack. Sepia, Noir, Vignette and "
                + "Invert apply in stack order; Blur, Sharpen and Pixelate always apply first."
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
}
