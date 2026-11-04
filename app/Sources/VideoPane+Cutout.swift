import AppKit

/// The Picture sub-tab's Background section (road map creator-jobs CO3, spec §11 CO-30): Remove
/// Background by Vision on the Mac, right after Chroma Key. The checkbox and Reset are the
/// clip's — a base `set_video` whatever is selected, so inside an action they are ⊘ — and
/// Background, Edge and Feather write a sparse `cutoutPart`, which an action animates (an end
/// gets only the row's own key). Status reads the pane's `CutoutStatus.Memo`; Analyze Now asks
/// the editor's `analyzeCutoutNow` (the wants made again, then a failed run retried). With every
/// selected clip a picture, Subject (Person, Foreground) follows the checkbox: the clip's, like
/// it (road map creator-jobs CO10b, spec §11 CO-108).
extension VideoPane {

    /// Every selected clip can be cut out: a media or still clip of a video file with pictures,
    /// or an image clip of a picture (CO-108).
    var allCutoutable: Bool {
        let clips = binding.clips
        return !clips.isEmpty
            && clips.allSatisfy { CutoutStatus.canCutOut($0, in: binding.snapshot) }
    }

    /// Every selected clip is an image clip — the Subject row's gate (CO-108).
    var allPictures: Bool {
        let clips = binding.clips
        return !clips.isEmpty && clips.allSatisfy {
            if case .image = $0.source { return true }
            return false
        }
    }

    /// Every selected video clip has a BASE cutout — Background, Edge and Feather's gate.
    var allCutOut: Bool {
        let clips = binding.videoClips
        return !clips.isEmpty && clips.allSatisfy { $0.video?.cutout != nil }
    }

    func cutoutSection(_ memo: CutoutStatus.Memo) -> InspectorSection {
        let binding = self.binding
        func anyOn() -> Bool { binding.videoClips.contains { $0.video?.cutout != nil } }
        func allOn() -> Bool { allCutOut }
        func cut() -> CutoutProps { binding.videoProps.cutout ?? CutoutProps() }
        func onOps() -> [ReelOp] {
            binding.videoClips.filter { $0.video?.cutout == nil }.flatMap {
                binding.ops(video: VideoPatch(cutout: .some(CutoutProps())), for: $0)
            }
        }
        // Base whatever is selected: `structural(video:for:)` sends a cutout's presence there.
        func offOps() -> [ReelOp] { binding.ops(video: VideoPatch(cutout: .some(nil))) }
        func part(_ patch: CutoutPatch) -> [ReelOp] {
            binding.ops(video: VideoPatch(cutoutPart: patch))
        }
        let enabled: () -> Bool = { [weak self] in self?.allCutOut ?? false }
        func single() -> (UInt32, ProjectDocument)? {
            guard binding.videoClips.count == 1, let clip = binding.videoClips.first,
                let document = binding.document
            else { return nil }
            return (clip.id, document)
        }
        func statusWords() -> String {
            guard let (clip, document) = single() else { return "—" }
            return CutoutStatus.words(memo.status(of: clip, in: document).state)
        }
        func analyzable() -> Bool {
            guard let document = binding.document else { return false }
            let states: [CutoutState]
            if let (clip, document) = single() {
                states = [memo.status(of: clip, in: document).state]
            } else {
                states = binding.videoClips.filter { $0.video?.cutout != nil }.map {
                    CutoutStatus.status(of: $0.id, in: document).state
                }
            }
            return states.contains {
                switch $0 {
                case .analyzing, .failed: return true
                default: return false
                }
            }
        }

        let check = OptionCheckboxControl(
            label: "Remove background", read: allOn,
            write: { value in binding.apply("Remove Background", value ? onOps() : offOps()) },
            enabled: { true }, onEdit: { binding.edited() })
        weak var statusView: OptionDisplayControl?
        let readout = inspectorReadout(width: 170) {
            let words = statusWords()
            statusView?.toolTip = words
            if let statusView, let (clip, document) = single() {
                memo.watch(statusView, clip: clip, document: document)
            }
            return words
        }
        statusView = readout
        let analyze = OptionButtonControl(
            title: "Analyze Now",
            action: { [weak self] in
                self?.inspector?.onCommand?(#selector(EditorViewController.analyzeCutoutNow(_:)))
                memo.invalidate()
                binding.edited()
            },
            enabled: analyzable, onEdit: {})
        analyze.toolTip = "Make this clip's masks now, again after a failure"
        let backgrounds = CutoutBackground.allCases
        let subjects = CutoutSubject.allCases
        // The clip's subject, written whole on the BASE through `structural(video:for:)` —
        // a cutout's presence goes there, so the row is ⊘ inside an action (CO-108).
        func subjectOps(_ index: Int) -> [ReelOp] {
            guard subjects.indices.contains(index) else { return [] }
            return binding.videoClips.compactMap { clip -> [ReelOp]? in
                guard var base = clip.video?.cutout else { return nil }
                base.subject = subjects[index]
                return binding.ops(video: VideoPatch(cutout: .some(base)), for: clip)
            }.flatMap { $0 }
        }
        let subjectRow: [NSView] = allPictures
            ? [
                inspectorPopupRow(
                    "Subject", binding, name: "Cutout Subject", items: ["Person", "Foreground"],
                    read: { subjects.firstIndex(of: cut().subject) ?? 0 },
                    ops: subjectOps,
                    mixed: {
                        Set(binding.videoClips.compactMap { $0.video?.cutout?.subject }).count > 1
                    },
                    enabled: enabled)
            ] : []
        return InspectorSection(
            id: "video.cutout", title: "Background",
            summary: {
                guard anyOn() else { return "off" }
                return single() == nil ? "on" : statusWords()
            },
            reset: { binding.apply("Remove Background", offOps()) },
            defaultExpanded: false,
            rows: [
                inspectorRow(
                    nil, [check], mixed: { anyOn() && !allOn() }, binding: binding,
                    writes: offOps(),
                    default: InspectorRowDefault(
                        name: "Remove Background", differs: anyOn, ops: offOps)),
            ] + subjectRow + [
                inspectorPopupRow(
                    "Background", binding, name: "Cutout Background", items: ["Remove", "Keep"],
                    read: { backgrounds.firstIndex(of: cut().background) ?? 0 },
                    ops: { index in
                        guard backgrounds.indices.contains(index) else { return [] }
                        return part(CutoutPatch(background: backgrounds[index]))
                    },
                    mixed: { binding.mixedVideo { $0.cutout?.background } },
                    enabled: enabled),
                inspectorValueRow(
                    "Edge", binding, name: "Cutout Edge", decimals: 2, min: -1, max: 1,
                    quick: [-0.5, -0.25, 0, 0.25, 0.5],
                    read: { cut().edge },
                    ops: { part(CutoutPatch(edge: $0)) },
                    mixed: { binding.mixedVideo { $0.cutout?.edge } },
                    enabled: enabled),
                inspectorValueRow(
                    "Feather", binding, name: "Cutout Feather", unit: "%", decimals: 0,
                    min: 0, max: 100, quick: [0, 10, 25, 50],
                    read: { cut().feather * 100 },
                    ops: { part(CutoutPatch(feather: $0 / 100)) },
                    mixed: { binding.mixedVideo { $0.cutout?.feather } },
                    enabled: enabled),
                inspectorRow("Status", [readout]),
                inspectorButtonRow([analyze]),
            ])
    }
}
