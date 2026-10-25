import AppKit

/// The Clip tab's **Transition** section (spec §4.3) — the one group that is
/// not about the layer's own pixels but about how it MEETS the clip before
/// it. `ClipPane` shows it only for a single clip with an overlap
/// (`ClipPane.makeSections()`), which is the only state in which an overlap
/// has a transition to describe.
///
/// An `extension VideoPane` in a file of its own because `VideoPane.swift`
/// stood at 1465 lines against the ~400-line rule for new files and the
/// section is about to grow the Curve popup and the Crossfade Audio check
/// row road map 5's E1 adds. The move cost no visibility: `binding` is
/// internal and the row builders are free functions.
extension VideoPane {
    // MARK: Transition

    /// The section's four rows: which transition, how it is eased, whether
    /// it crossfades the sound, and how long the overlap is.
    ///
    /// **The Curve and Crossfade Audio rows READ the snapshot's lenient
    /// defaults** — `linear` and `false` — which is what a clip with no
    /// stored transition draws, and what a version-6 file's transition
    /// means. They deliberately do not show what the core would MINT: the
    /// section has to say what is there.
    ///
    /// **And when `transitionIn` is nil, each of the two sends BOTH keys.**
    /// The Kind popup's index 0 is None, so a clip under an overlap is one
    /// click away from having no stored transition at all while still being
    /// drawn as a cross dissolve; a one-key `set_transition_style` on that
    /// clip would mint `ease_in_out`/`true` underneath and the untouched
    /// row would silently change its value. Sending both makes the minted
    /// transition exactly what the section was showing, with only the
    /// touched value moved. With a transition stored, each row sends its one
    /// key and the core keeps the other. `TextPane`'s animation section is
    /// the precedent, applied to two scalars rather than to one object.
    func transitionSection(_ clip: UInt32) -> InspectorSection {
        let binding = self.binding
        let kinds = TransitionKind.allCases
        let items = ["None"] + kinds.map { $0.displayName }
        let curves = Curve.allCases
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
        func stored() -> TransitionSnapshot? { binding.snapshot.clip(clip)?.transitionIn }
        func curve() -> Curve { stored()?.curve ?? .linear }
        func crossfades() -> Bool { stored()?.audio ?? false }
        /// The style write, carrying the other row's DISPLAYED value too
        /// whenever there is nothing stored to keep it (see the doc above).
        func styleOps(curve next: Curve?, audio: Bool?) -> [ReelOp] {
            if stored() == nil {
                return [
                    .setTransitionStyle(
                        clip: clip, curve: next ?? curve(), audio: audio ?? crossfades())
                ]
            }
            return [.setTransitionStyle(clip: clip, curve: next, audio: audio)]
        }
        return InspectorSection(
            id: "video.transition", title: "Transition",
            summary: {
                guard let transition = stored() else { return "none" }
                return transition.kind.displayName.lowercased()
                    + " · " + transition.curve.displayName.lowercased()
                    + String(format: " · %.2f s", overlapSeconds())
            },
            defaultExpanded: false,
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
                    }, resets: false),
                inspectorPopupRow(
                    "Curve", binding, name: "Transition Curve",
                    items: curves.map { $0.displayName },
                    read: { curves.firstIndex(of: curve()) ?? 0 },
                    ops: { index in
                        styleOps(
                            curve: curves[min(max(index, 0), curves.count - 1)], audio: nil)
                    }, resets: false),
                inspectorCheckRow(
                    "Crossfade Audio", binding, name: "Transition Audio",
                    read: crossfades,
                    ops: { value in styleOps(curve: nil, audio: value) }, resets: false),
                inspectorValueRow(
                    "Duration", binding, name: "Transition Duration", unit: " s", decimals: 2,
                    min: 0.02, max: 10, quick: [0.25, 0.5, 1, 2], slider: false,
                    read: overlapSeconds,
                    ops: { value in
                        [
                            .setTransitionDuration(
                                clip: clip,
                                duration: binding.frameTicks(seconds: value))
                        ]
                    }, resets: false),
            ])
    }
}
