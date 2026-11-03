import AppKit

/// The Picture sub-tab's Hide While Silent section (road map creator-jobs CO9,
/// spec §11 CO-94): the camera fades out in the pauses of a media's speech
/// and back in just before it (CO-90). After Layout, shut by default.
///
/// Every row is one undo step "Hide While Silent" and writes the WHOLE gate to
/// the base (`structural(video:for:)`: it is not an animation target), each
/// edit re-sending the other values as they stand (the Ducking section's
/// rule). A gate naming a media whose speech is not saved yet carries that
/// media's `set_media_speech` first, in the same step, as Duck by Speech does
/// (`DuckSpeech.ops(forMedia:)`); a refusal there sends nothing, and the
/// section's note says why.
extension VideoPane {

    /// Every selected clip draws pixels and none is a nest clip (a nest scope
    /// is allowed): a nest clip never draws itself (CO-92).
    var allHideable: Bool {
        let clips = binding.clips
        return !clips.isEmpty
            && clips.allSatisfy { clip in
                if case .nest = clip.source { return false }
                return InspectorTab.hasPixels(clip, in: binding.snapshot)
            }
    }

    func hideSilentSection() -> InspectorSection {
        let binding = self.binding
        let name = "Hide While Silent"
        /// The sentence of the last refused `ops(forMedia:)`, shown as the note.
        final class Problem { var text: String? }
        let problem = Problem()
        func candidates() -> [MediaSnapshot] {
            HideSilentSources.candidates(for: binding.clips, in: binding.snapshot)
        }
        func gated() -> [ClipSnapshot] { binding.videoClips.filter { $0.video?.hideSilent != nil } }
        func anyOn() -> Bool { !gated().isEmpty }
        func allOn() -> Bool {
            !binding.videoClips.isEmpty && gated().count == binding.videoClips.count
        }
        func current() -> HideSilentProps? { gated().first?.video?.hideSilent }
        /// The media's `set_media_speech` ops, or nil when `ops(forMedia:)`
        /// refused: then the row writes nothing and the note says why.
        func spans(_ media: UInt32) -> [ReelOp]? {
            do {
                let ops = try DuckSpeech.ops(
                    forMedia: media, in: binding.snapshot,
                    cacheDirectory: binding.document?.cacheDirectory)
                problem.text = nil
                return ops
            } catch {
                problem.text = error.localizedDescription
                return nil
            }
        }
        /// The whole gate `next` on every selected picture clip, the spans first.
        func write(_ next: HideSilentProps) -> [ReelOp] {
            guard let speech = spans(next.media) else { return [] }
            return speech + binding.ops(video: VideoPatch(hideSilent: .some(next)))
        }
        func onOps() -> [ReelOp] {
            guard let first = candidates().first else { return [] }
            let gate = HideSilentProps(media: first.id)
            let set = binding.videoClips.filter { $0.video?.hideSilent == nil }.flatMap {
                binding.ops(video: VideoPatch(hideSilent: .some(gate)), for: $0)
            }
            guard !set.isEmpty, let speech = spans(gate.media) else { return [] }
            return speech + set
        }
        func offOps() -> [ReelOp] { binding.ops(video: VideoPatch(hideSilent: .some(nil))) }
        func offerable() -> Bool {
            guard let first = candidates().first else { return false }
            return DuckSpeech.problem(
                forMedia: first.id, in: binding.snapshot,
                cacheDirectory: binding.document?.cacheDirectory) == nil
        }
        /// "Speech from"'s media: the candidates, then the set media when it
        /// is not among them.
        func sources() -> [MediaSnapshot] {
            var list = candidates()
            if let set = current()?.media, !list.contains(where: { $0.id == set }),
               let row = binding.snapshot.media(set)
            {
                list.append(row)
            }
            return list
        }
        let sourceList = sources()
        func seconds(_ ticks: Ticks) -> Double { ReelTime.seconds(ticks) }
        func ticks(_ seconds: Double) -> Ticks { ReelTime.ticks(seconds: max(seconds, 0)) }
        func edit(_ change: (inout HideSilentProps) -> Void) -> [ReelOp] {
            guard var next = current() else { return [] }
            change(&next)
            return write(next)
        }

        let check = OptionCheckboxControl(
            label: "Hide while silent", read: allOn,
            write: { value in binding.apply(name, value ? onOps() : offOps()) },
            enabled: { anyOn() || offerable() }, onEdit: { binding.edited() })
        if !anyOn(), let first = candidates().first {
            check.toolTip = DuckSpeech.problem(
                forMedia: first.id, in: binding.snapshot,
                cacheDirectory: binding.document?.cacheDirectory)
        } else if candidates().isEmpty, !anyOn() {
            check.toolTip = "No clip with sound plays under the selection."
        }
        return InspectorSection(
            id: "video.hide_silent", title: "Hide While Silent",
            summary: {
                guard anyOn() else { return "off" }
                let media = Set(gated().map { $0.video?.hideSilent?.media ?? 0 })
                guard allOn(), media.count == 1, let id = media.first,
                      let row = binding.snapshot.media(id)
                else { return "on" }
                return row.name
            },
            note: { problem.text },
            reset: { binding.apply(name, offOps()) },
            defaultExpanded: false,
            rows: [
                inspectorRow(
                    nil, [check], mixed: { anyOn() && !allOn() }, binding: binding,
                    writes: offOps(),
                    default: InspectorRowDefault(name: name, differs: anyOn, ops: offOps)),
                inspectorPopupRow(
                    "Speech from", binding, name: name, items: sourceList.map(\.name),
                    read: {
                        sourceList.firstIndex { $0.id == current()?.media } ?? 0
                    },
                    ops: { index in
                        guard sourceList.indices.contains(index) else { return [] }
                        return edit { $0.media = sourceList[index].id }
                    },
                    mixed: { binding.mixedVideo { $0.hideSilent?.media } },
                    enabled: anyOn, resets: false),
                inspectorValueRow(
                    "Pre-roll", binding, name: name, unit: " s", decimals: 2, min: 0, max: 5,
                    quick: [0, 0.1, 0.2, 0.5],
                    read: { seconds(current()?.preRoll ?? HideSilentProps.defaultPreRoll) },
                    ops: { value in edit { $0.preRoll = ticks(value) } },
                    mixed: { binding.mixedVideo { $0.hideSilent?.preRoll } },
                    enabled: anyOn),
                inspectorValueRow(
                    "Hold", binding, name: name, unit: " s", decimals: 2, min: 0, max: 5,
                    quick: [0.5, 1, 1.5, 3],
                    read: { seconds(current()?.hold ?? HideSilentProps.defaultHold) },
                    ops: { value in edit { $0.hold = ticks(value) } },
                    mixed: { binding.mixedVideo { $0.hideSilent?.hold } },
                    enabled: anyOn),
                inspectorValueRow(
                    "Fade", binding, name: name, unit: " s", decimals: 2, min: 0, max: 5,
                    quick: [0, 0.15, 0.3, 0.5],
                    read: { seconds(current()?.fade ?? HideSilentProps.defaultFade) },
                    ops: { value in edit { $0.fade = ticks(value) } },
                    mixed: { binding.mixedVideo { $0.hideSilent?.fade } },
                    enabled: anyOn),
            ])
    }
}
