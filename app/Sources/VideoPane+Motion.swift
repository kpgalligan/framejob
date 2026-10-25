import AppKit

/// The Clip tab's **Motion** section (spec §4.3, road map 5's E2) — what a
/// clip does on its way in, on its way out, and all the way through.
///
/// An `extension VideoPane` in a file of its own, `VideoPane+Transition.swift`'s
/// shape, because `VideoPane.swift` is over the size cap and may not grow.
///
/// **Every write is PER CLIP.** A `motion` patch replaces the whole object
/// (`MotionProps.dictionary` always writes three keys), so one `set_video`
/// over several ids would stamp the first clip's other two slots onto every
/// other clip. Each row therefore reads THAT clip's base motion, changes the
/// one slot or field, and emits that clip's own op — through
/// `ops(video:for:)`, whose `structural` puts motion on the base props even
/// inside an action. Reset alone is selection-wide, since every clip gets the
/// same value. Reads are the first clip's, the section rule.
extension VideoPane {
    // MARK: Motion

    func motionSection() -> InspectorSection {
        let binding = self.binding
        let edges = EdgeMotion.allCases
        let durings = DuringMotion.allCases
        func motion() -> MotionProps { binding.videoProps.motion ?? MotionProps() }
        /// One op per clip over the selection's pixel clips; `step` answers
        /// the clip's next motion, or nil to skip the clip.
        func perClip(_ step: (ClipSnapshot, MotionProps) -> MotionProps?) -> [ReelOp] {
            var ops: [ReelOp] = []
            for clip in binding.videoClips {
                let current = clip.videoProps.motion ?? MotionProps()
                guard let next = step(clip, current) else { continue }
                ops.append(
                    contentsOf: binding.ops(video: VideoPatch(motion: .some(next)), for: clip))
            }
            return ops
        }
        func edgeKind(_ index: Int) -> EdgeMotion? {
            index == 0 ? nil : edges[min(max(index - 1, 0), edges.count - 1)]
        }
        /// A chosen kind keeps the slot's stored duration, else the core's
        /// own 0.5 s default (`MotionEdge()`).
        func edge(_ kind: EdgeMotion?, keeping stored: MotionEdge?) -> MotionEdge? {
            guard let kind = kind else { return nil }
            return MotionEdge(kind: kind, duration: stored?.duration ?? MotionEdge().duration)
        }
        func summary() -> String {
            let m = motion()
            var parts: [String] = []
            if let e = m.inEdge { parts.append("in " + e.displayName.lowercased()) }
            if let e = m.out { parts.append("out " + e.displayName.lowercased()) }
            if let d = m.during { parts.append(d.kind.displayName.lowercased()) }
            return parts.isEmpty ? "off" : parts.joined(separator: " · ")
        }
        func inactiveNote() -> String? {
            let selected = binding.videoClips.map { $0.videoProps.motion }
            let inactiveIn = selected.contains { $0?.inEdge.map { !$0.isActive } ?? false }
            let inactiveOut = selected.contains { $0?.out.map { !$0.isActive } ?? false }
            guard inactiveIn || inactiveOut else { return nil }
            let slots = [inactiveIn ? "In" : nil, inactiveOut ? "Out" : nil]
                .compactMap { $0 }.joined(separator: " and ")
            return "Selection includes inactive \(slots) motion (zero duration). "
                + "Increase Duration to reactivate; choose None to clear."
        }

        let preview = commandButton(
            "Preview", #selector(EditorViewController.previewClipMotion(_:)),
            toolTip:
                "Play the clip in a loop: sets the in/out range to the clip and turns Loop on"
                + " — both stay until you clear them")

        return InspectorSection(
            id: "video.motion", title: "Motion presets",
            summary: summary,
            reset: { binding.apply("Motion", video: VideoPatch(motion: .some(nil))) },
            defaultExpanded: false,
            rows: [
                InspectorNoteLabel(wraps: true, note: inactiveNote),
                inspectorPopupRow(
                    "In", binding, name: "Motion In", items: ["None"] + edges.map(\.displayName),
                    read: { motion().inEdge.map { (edges.firstIndex(of: $0.kind) ?? 0) + 1 } ?? 0 },
                    ops: { index in
                        perClip { _, m in
                            m.with { $0.inEdge = edge(edgeKind(index), keeping: m.inEdge) }
                        }
                    },
                    mixed: { binding.mixedVideo { $0.motion?.inEdge?.kind } }),
                // 0.1 s to 10 s: a few frames at the short end, and far longer
                // than any entrance is meant to take at the long one.
                inspectorValueRow(
                    "In Duration", binding, name: "Motion In Duration", unit: " s", decimals: 2,
                    min: 0.1, max: 10, quick: [0.25, 0.5, 1], slider: false,
                    read: { ReelTime.seconds(motion().inEdge?.duration ?? MotionEdge().duration) },
                    ops: { value in
                        perClip { _, m in
                            guard m.inEdge != nil else { return nil }
                            return m.with {
                                $0.inEdge?.duration = binding.frameTicks(seconds: value)
                            }
                        }
                    },
                    mixed: { binding.mixedVideo { $0.motion?.inEdge?.duration } },
                    enabled: { motion().inEdge != nil }),
                inspectorPopupRow(
                    "Out", binding, name: "Motion Out", items: ["None"] + edges.map(\.displayName),
                    read: { motion().out.map { (edges.firstIndex(of: $0.kind) ?? 0) + 1 } ?? 0 },
                    ops: { index in
                        perClip { _, m in
                            m.with { $0.out = edge(edgeKind(index), keeping: m.out) }
                        }
                    },
                    mixed: { binding.mixedVideo { $0.motion?.out?.kind } }),
                // The same range as In Duration, for the same reason.
                inspectorValueRow(
                    "Out Duration", binding, name: "Motion Out Duration", unit: " s", decimals: 2,
                    min: 0.1, max: 10, quick: [0.25, 0.5, 1], slider: false,
                    read: { ReelTime.seconds(motion().out?.duration ?? MotionEdge().duration) },
                    ops: { value in
                        perClip { _, m in
                            guard m.out != nil else { return nil }
                            return m.with { $0.out?.duration = binding.frameTicks(seconds: value) }
                        }
                    },
                    mixed: { binding.mixedVideo { $0.motion?.out?.duration } },
                    enabled: { motion().out != nil }),
                inspectorPopupRow(
                    "During", binding, name: "Motion During",
                    items: ["None"] + durings.map(\.displayName),
                    read: {
                        motion().during.map { (durings.firstIndex(of: $0.kind) ?? 0) + 1 } ?? 0
                    },
                    ops: { index in
                        perClip { _, m in
                            guard index > 0 else { return m.with { $0.during = nil } }
                            // A kind keeps the stored amount and period, else
                            // the core's own defaults (`MotionDuring()`).
                            var during = m.during ?? MotionDuring()
                            during.kind = durings[min(index - 1, durings.count - 1)]
                            return m.with { $0.during = during }
                        }
                    },
                    mixed: { binding.mixedVideo { $0.motion?.during?.kind } }),
                // Written as a percentage because the model's 0–1 reads as a
                // strength; `/ 100` at the write is the only conversion.
                inspectorValueRow(
                    "Amount", binding, name: "Motion Amount", unit: "%", decimals: 0,
                    min: 0, max: 100, quick: [25, 50, 75, 100], slider: false,
                    read: { (motion().during?.amount ?? MotionDuring().amount) * 100 },
                    ops: { value in
                        perClip { _, m in
                            guard m.during != nil else { return nil }
                            return m.with { $0.during?.amount = value / 100 }
                        }
                    },
                    mixed: { binding.mixedVideo { $0.motion?.during?.amount } },
                    enabled: { motion().during != nil }),
                // 0.1 s to 10 s: a cycle shorter than a few frames aliases, and
                // one longer than ten seconds no longer reads as a cycle.
                // Disabled for drift, which ignores the period.
                inspectorValueRow(
                    "Period", binding, name: "Motion Period", unit: " s", decimals: 2,
                    min: 0.1, max: 10, quick: [0.25, 0.5, 1, 2], slider: false,
                    read: {
                        ReelTime.seconds(motion().during?.period ?? MotionDuring().period)
                    },
                    ops: { value in
                        perClip { _, m in
                            guard m.during != nil else { return nil }
                            return m.with { $0.during?.period = binding.frameTicks(seconds: value) }
                        }
                    },
                    mixed: { binding.mixedVideo { $0.motion?.during?.period } },
                    enabled: {
                        guard let d = motion().during else { return false }
                        return d.kind != .drift
                    }),
                inspectorButtonRow([preview]),
            ])
    }
}
