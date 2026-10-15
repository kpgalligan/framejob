import AppKit

extension InspectorBinding {
    // MARK: Writes

    /// The part of a video patch that changes what the clip IS, and the part
    /// an action can animate. Either half may be nil; together they are the
    /// whole patch.
    ///
    /// **A list-valued key whose new LENGTH differs from the clip's own is
    /// the first kind, wherever the playhead sits.** `actions.rs`'s list rule
    /// interpolates an array PER INDEX only while the two lengths match, and
    /// otherwise holds the whole list at its start value and switches on the
    /// action's last tick. So a `filters` or `obscure` list of a different
    /// length written into an action's END patch is invisible for the entire
    /// span the user is looking at: the added region does not appear, and the
    /// section does not even grow a row, because `VideoPane`'s
    /// `structureSignature` counts the EVALUATED list. Worse, it does not
    /// survive: the next write of that list sends the whole array the pane
    /// can read — the base one, without the new entry — and replaces the end
    /// patch with it. Adding, removing and clearing therefore land on the
    /// BASE props even inside an action, where they are visible and keep.
    ///
    /// Dialling a value INSIDE an existing entry still goes to the action,
    /// which is what phase 3c's list rule exists for: a region's `amount`
    /// ramped from 0 to 1 is exactly that, and it works.
    ///
    /// The length is compared against `editedList` above — the action's own
    /// end list where there is one, the clip's base list otherwise — and never
    /// against the EVALUATED list the section reads, because that array is the
    /// one an end patch has to match to interpolate at all.
    ///
    /// **The sentence that used to stand here said "nothing the inspector does
    /// can put a different length into an end patch", and it was one action
    /// short of true.** With two actions on a clip and the first one's end
    /// patch changing the filter COUNT, the evaluated list at a playhead
    /// inside the SECOND action is longer than the base, so a comparison
    /// against the base classified an ordinary dial as structural and wrote
    /// the clip's base stack — changing every frame before the first action.
    /// With the pair above the section can only ever write the length it can
    /// see, so the guarantee holds; what it cannot promise is anything about a
    /// length a hand-written file or a `set_action_end` call put there.
    ///
    /// Do not fold this back into the single `set_action_end` it looks like.
    /// The two writes are the same shape from here and behave nothing alike
    /// three layers down, and every step of the failure is silent.
    ///
    /// Two residuals, both left deliberately and both smaller than what they
    /// replace:
    ///
    ///  - Changing an entry's DISCRIMINANT (a filter's `kind`, a region's
    ///    `kind` or `shape`) inside an action still writes the end patch,
    ///    because unlike a length change that IS a coherent animation —
    ///    `ENTRY_DISCRIMINANTS` in `actions.rs` holds the entry and switches
    ///    it at the end, which is what §5.4 says a discrete value does. It
    ///    reads back as unchanged until then, which is the inspector's
    ///    standing habit of showing the value AT THE PLAYHEAD while writing
    ///    the action's end, and not a property of lists.
    ///  - Adding or removing an entry while an action ALREADY animates that
    ///    list leaves the end patch at the old length, so that animation
    ///    degrades to a switch at the end until the end state is written
    ///    again. There is no way to say "drop this key" from here — a
    ///    `VideoPatch`'s list keys are single optionals, so nil is absent
    ///    rather than null — and a visible degradation is worth more than an
    ///    invisible append.
    private func structural(video patch: VideoPatch, for clip: ClipSnapshot)
        -> (base: VideoPatch?, animatable: VideoPatch?)
    {
        var base = VideoPatch()
        var animatable = patch
        if let filters = patch.filters,
            filters.count != editedList(clip, action: { $0.filters }, base: { $0.filters }).count
        {
            base.filters = filters
            animatable.filters = nil
        }
        if let obscure = patch.obscure,
            obscure.count != editedList(clip, action: { $0.obscure }, base: { $0.obscure }).count
        {
            base.obscure = obscure
            animatable.obscure = nil
        }
        // A curve is a list too (spec §11 GR-12, GR-32), with one more case
        // that still animates: an identity curve on either side (its domain's
        // identity: a hue curve's every value neutral), which the core
        // aligns to the other's x's (`align_identity_curves`). So a channel
        // goes to the END when its new count is the edited one's, or either
        // the edited or the new list is the identity, and to the BASE only
        // for a count change between two curves.
        if let curves = patch.curves {
            var moved = ColorCurvesPatch()
            var kept = curves
            for channel in CurveChannel.allCases {
                guard case .some(.some(let list)) = curves.entry(channel) else { continue }
                let edited = editedCurve(clip, channel)
                if list.count == edited.count || channel.domain.isIdentity(edited)
                    || channel.domain.isIdentity(list)
                {
                    continue
                }
                moved = moved.setting(channel, .some(list))
                kept = kept.setting(channel, nil)
            }
            if !moved.isEmpty { base.curves = moved }
            animatable.curves = kept.isEmpty ? nil : kept
        }
        // Motion is not an animation target (the core refuses it in
        // `set_action_end`), so it ALWAYS lands on the base props.
        if patch.motion != nil {
            base.motion = patch.motion
            animatable.motion = nil
        }
        return (base.isEmpty ? nil : base, animatable.isEmpty ? nil : animatable)
    }

    /// The curve a write of `channel` replaces on `clip` (`editedList`'s
    /// rule): the selected action's end curve when the end names one, the
    /// clip's base curve otherwise (the identity when it has none).
    func editedCurve(_ clip: ClipSnapshot, _ channel: CurveChannel) -> [CurvePoint] {
        editedList(
            clip,
            action: { end -> [CurvePoint]? in
                guard case .some(.some(let list)) = end.curves?.entry(channel) else { return nil }
                return list
            },
            base: { $0.curves.points(channel) })
    }

    /// One clip's ops for a video patch: the action's end state when the
    /// playhead is inside one, the base props otherwise — and the base props
    /// for whatever `structural(video:for:)` pulls out, either way.
    func ops(video patch: VideoPatch, for clip: ClipSnapshot) -> [ReelOp] {
        split(
            [clip], patch, patch.isEmpty, base: { .setVideo(clips: $0, patch: $1) },
            action: { ActionPatch(video: $0) },
            structural: { self.structural(video: $0, for: $1) })
    }

    /// The selection's ops for a video patch. Clips outside an action share
    /// ONE `set_video` with several ids (§4.3); the ones inside get their own
    /// `set_action_end`, less the structural part.
    func ops(video patch: VideoPatch) -> [ReelOp] {
        split(
            videoClips, patch, patch.isEmpty, base: { .setVideo(clips: $0, patch: $1) },
            action: { ActionPatch(video: $0) },
            structural: { self.structural(video: $0, for: $1) })
    }

    /// Spec §11 CI-3: pan, mono, compressor, noise reduction, duck and
    /// keep-pitch are the clip's, whatever is selected.
    private func structural(audio patch: AudioPatch, for clip: ClipSnapshot)
        -> (base: AudioPatch?, animatable: AudioPatch?)
    {
        let base = AudioPatch(
            duck: patch.duck, mono: patch.mono, keepPitch: patch.keepPitch, pan: patch.pan,
            compressor: patch.compressor, noiseReduction: patch.noiseReduction)
        var animatable = patch
        (animatable.duck, animatable.mono, animatable.keepPitch) = (nil, nil, nil)
        (animatable.pan, animatable.compressor, animatable.noiseReduction) = (nil, nil, nil)
        return (base.isEmpty ? nil : base, animatable.isEmpty ? nil : animatable)
    }

    func ops(audio patch: AudioPatch) -> [ReelOp] {
        split(
            audioClips, patch, patch.isEmpty, base: { .setAudio(clips: $0, patch: $1) },
            action: { ActionPatch(audio: $0) },
            structural: { self.structural(audio: $0, for: $1) })
    }

    func ops(text patch: TextPatch) -> [ReelOp] {
        split(
            textClips, patch, patch.isEmpty, base: { .setText(clips: $0, patch: $1) },
            action: { ActionPatch(text: $0) })
    }

    /// Spec §11 G-34 (l): a graphic clip's props. Clips outside an action
    /// share ONE `set_graphic`, each value through G-15 (b)'s null rule
    /// (`patchProps`), so a base write is what it always was; a clip with an
    /// action selected gets one `set_action_end` naming `graphic.props.<key>`
    /// with the module's `schema`, each value as it is — a `null` in an end
    /// REMOVES (G-34 (j)). An asset is the base's (an end refuses one, G-34
    /// (b)), sent there by CI-3's mechanism.
    func ops(
        graphic values: [String: GraphicPropValue], entries: [GraphicSchemaEntry],
        clips: [ClipSnapshot], schema: [String: Any]?
    ) -> [ReelOp] {
        let assets = Set(entries.filter { $0.type == "asset" }.map(\.key))
        return split(
            clips, values, values.isEmpty,
            base: {
                .setGraphicRaw(clips: $0, patch: ["props": GraphicSchemaRows.patchProps($1, entries: entries)], schema: schema)
            },
            action: { ActionPatch(graphic: ActionGraphicPatch(props: $0)) },
            schema: schema,
            structural: { values, _ in
                let base = values.filter { assets.contains($0.key) }
                let animated = values.filter { !assets.contains($0.key) }
                return (base.isEmpty ? nil : base, animated.isEmpty ? nil : animated)
            })
    }

    /// One row's write: `ops(graphic:entries:…)` for one entry.
    func ops(
        graphic value: GraphicPropValue, for entry: GraphicSchemaEntry,
        clips: [ClipSnapshot], schema: [String: Any]?
    ) -> [ReelOp] {
        ops(graphic: [entry.key: value], entries: [entry], clips: clips, schema: schema)
    }

    /// Shapes have no action form (§5.4's patch covers video, audio and text),
    /// so this is always one `set_shape` over every selected shape clip.
    func ops(shape patch: ShapePatch) -> [ReelOp] {
        let ids = shapeClips.map { $0.id }
        guard !patch.isEmpty, !ids.isEmpty else { return [] }
        return [.setShape(clips: ids, patch: patch)]
    }

    /// The shared rule: clips outside an action share ONE op with several ids
    /// (§4.3's "one op with several clip ids"); each clip the playhead is
    /// inside an action of gets its own `set_action_end` instead — less the
    /// part `structural` pulls back onto its base props, which is a change to
    /// the clip and not to how it animates.
    ///
    /// Audio and text pass no `structural`, and the default says why they
    /// need none: `VideoPatch` is the only patch with an array-valued key, so
    /// video is the only one whose write can change a LENGTH. `schema` goes with
    /// every `set_action_end`; only a graphic end needs one (G-34 (c)).
    private func split<Patch>(
        _ clips: [ClipSnapshot], _ patch: Patch, _ isEmpty: Bool,
        base: ([UInt32], Patch) -> ReelOp,
        action end: (Patch) -> ActionPatch, schema: [String: Any]? = nil,
        structural: (Patch, ClipSnapshot) -> (base: Patch?, animatable: Patch?) = {
            whole, _ in (base: nil, animatable: whole)
        }
    ) -> [ReelOp] {
        guard !isEmpty, !clips.isEmpty else { return [] }
        var ops: [ReelOp] = []
        var ids: [UInt32] = []
        for clip in clips {
            guard let inside = action(clip) else {
                ids.append(clip.id)
                continue
            }
            let parts = structural(patch, clip)
            if let onClip = parts.base { ops.append(base([clip.id], onClip)) }
            if let animated = parts.animatable {
                ops.append(
                    .setActionEnd(clip: clip.id, action: inside.id, patch: end(animated), schema: schema))
            }
        }
        if !ids.isEmpty { ops.insert(base(ids, patch), at: 0) }
        return ops
    }

    // MARK: Commits

    func apply(_ name: String, _ ops: [ReelOp]) {
        guard !ops.isEmpty else {
            NSSound.beep()
            return
        }
        inspector?.onEdit?(name, ops)
    }

    func apply(_ name: String, video patch: VideoPatch) { apply(name, ops(video: patch)) }
    func apply(_ name: String, audio patch: AudioPatch) { apply(name, ops(audio: patch)) }
    func apply(_ name: String, text patch: TextPatch) { apply(name, ops(text: patch)) }
    func apply(_ name: String, shape patch: ShapePatch) { apply(name, ops(shape: patch)) }

    /// `apply` as one undo step with the step that ended at `step` — undone
    /// first when nothing has been applied since (#272, a wheel strip's
    /// off-knob double-click; `ProjectDocument.applyEdit(_:_:amending:)`).
    func amend(_ name: String, _ ops: [ReelOp], step: ReelProject) {
        guard !ops.isEmpty else {
            NSSound.beep()
            return
        }
        inspector?.onAmendEdit?(name, ops, step)
    }

    /// Off-event commits (a sheet's completion, an alert's answer) — the
    /// grouped entry point is mandatory there (app/CLAUDE.md's undo pitfall).
    func applyGrouped(_ name: String, _ ops: [ReelOp]) {
        guard !ops.isEmpty else {
            NSSound.beep()
            return
        }
        inspector?.onGroupedEdit?(name, ops)
    }

    // MARK: Live gestures

    func liveBegin() { inspector?.onLiveBegin?() }
    func liveUpdate(_ ops: [ReelOp]) {
        guard !ops.isEmpty else { return }
        inspector?.onLiveUpdate?(ops)
    }
    func liveEnd(_ name: String) { inspector?.onLiveEnd?(name) }

    /// The refresh a control asks for after it writes, so the readouts and
    /// dependent fields in the same section catch up.
    func edited() { inspector?.refresh(isLive: false) }
}
