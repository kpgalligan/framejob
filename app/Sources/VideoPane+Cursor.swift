import AppKit

/// The Picture sub-tab's Cursor section (road map creator-jobs CU3b, CU4, spec §11 CU-38 (b),
/// CU-40), after Background and before Shadow: Show cursor, Size, Style, Smoothing, Hide when
/// idle, Clicks, Ripple color, Ripple size and Polish. Each row writes only its own key through
/// `VideoPatch.cursorPart` as one named undo step. Inside an action Size and Ripple size animate;
/// Show, Style, Clicks and Ripple color switch at the end (CU-30); Smoothing, Hide when idle and
/// Polish are the clip's — `InspectorBinding.structural(video:for:)` sends them to the base (⊘),
/// and stores the defaults on a base with no cursor when an end key is written. Smoothing and
/// Hide when idle read the clip's BASE cursor, never the evaluated props.
extension VideoPane {

    /// The section's gate: every selected clip is a media or still clip whose media has a cursor
    /// file the movie's picture does not already show (`media.cursor` with `in_picture` false).
    /// `ClipPane.structureSignature` carries it, so a relink, an undo or a landing that changes
    /// the media's `cursor` under a fixed selection adds or removes the section.
    var allCursored: Bool {
        let clips = binding.clips
        let snapshot = binding.snapshot
        return !clips.isEmpty
            && clips.allSatisfy { clip in
                switch clip.source {
                case .media, .still:
                    guard let cursor = snapshot.media(for: clip)?.cursor else { return false }
                    return !cursor.inPicture
                default:
                    return false
                }
            }
    }

    func cursorSection() -> InspectorSection {
        let binding = self.binding
        /// The evaluated props (the action's end with one selected), the defaults without any.
        func props() -> CursorProps { binding.videoProps.cursor ?? CursorProps() }
        /// The first clip's BASE cursor — what the recipe reads `smoothing` and `hide_idle`
        /// from (CU-30) — and the defaults in `.defaults` mode, a row's reset.
        func base() -> CursorProps {
            guard binding.mode != .defaults else { return CursorProps() }
            return binding.videoClips.first?.video?.cursor ?? CursorProps()
        }
        func baseMixed<T: Equatable>(_ read: @escaping (CursorProps) -> T) -> Bool {
            binding.mixed(binding.videoClips) { read($0.video?.cursor ?? CursorProps()) }
        }
        func on() -> Bool { props().show }
        func ops(_ value: Bool) -> [ReelOp] {
            binding.ops(video: VideoPatch(cursorPart: CursorPatch(show: value)))
        }
        func part(_ patch: CursorPatch) -> [ReelOp] {
            binding.ops(video: VideoPatch(cursorPart: patch))
        }
        func ripples() -> Bool { props().clicks == .ripple }
        let styles = CursorStyle.allCases
        let clicks = CursorClicks.allCases
        let smoothing = CursorProps.smoothingSteps
        let hiding = CursorProps.hideIdleSteps
        let fallback = GraphicSchemaRows.rgba(css: CursorProps.defaultClickColor) ?? [1, 1, 1, 0.8]
        func rippleColor() -> RGBA {
            let css = ReelColor.normalise(props().clickColor) ?? CursorProps.defaultClickColor
            return GraphicSchemaRows.rgba(css: css) ?? fallback
        }
        let reset: CursorPatch = {
            let d = CursorProps()
            return CursorPatch(
                show: d.show, scale: d.scale, style: d.style, smoothing: d.smoothing,
                hideIdle: .some(d.hideIdle), clicks: d.clicks, clickColor: d.clickColor,
                clickSize: d.clickSize)
        }()
        let polish = OptionButtonControl(
            title: "Polish",
            action: { binding.apply("Polish Cursor", part(CursorProps.polished)) },
            enabled: { true }, onEdit: { binding.edited() })
        polish.toolTip = "Smoothing Medium and Hide when idle after 3 s"
        return InspectorSection(
            id: "video.cursor", title: "Cursor",
            summary: {
                let p = props()
                guard p.show || p.clicks == .ripple else { return "off" }
                return (p.style == .arrow ? "arrow" : "on")
                    + (p.clicks == .ripple ? " + ripples" : "")
            },
            reset: { binding.apply("Reset Cursor", part(reset)) },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Show cursor", binding, name: "Show Cursor", read: on, ops: ops,
                    mixed: { binding.mixedVideo { $0.cursor?.show ?? true } }),
                inspectorValueRow(
                    "Size", binding, name: "Cursor Size", unit: "%", decimals: 0, min: 25,
                    max: 800, sliderMax: 400, quick: [50, 100, 150, 200, 400],
                    read: { props().scale * 100 },
                    ops: { part(CursorPatch(scale: $0 / 100)) },
                    mixed: { binding.mixedVideo { $0.cursor?.scale ?? 1 } }),
                inspectorPopupRow(
                    "Style", binding, name: "Cursor Style", items: ["As recorded", "Arrow"],
                    read: { styles.firstIndex(of: props().style) ?? 0 },
                    ops: { index in
                        guard styles.indices.contains(index) else { return [] }
                        return part(CursorPatch(style: styles[index]))
                    },
                    mixed: { binding.mixedVideo { $0.cursor?.style ?? .recorded } }),
                inspectorPopupRow(
                    "Smoothing", binding, name: "Cursor Smoothing", items: smoothing.map(\.title),
                    read: { smoothing.firstIndex { $0.value == base().smoothing } ?? -1 },
                    ops: { index in
                        guard smoothing.indices.contains(index) else { return [] }
                        return part(CursorPatch(smoothing: smoothing[index].value))
                    },
                    mixed: { baseMixed { $0.smoothing } }),
                inspectorPopupRow(
                    "Hide when idle", binding, name: "Hide Cursor When Idle",
                    items: hiding.map(\.title),
                    read: { hiding.firstIndex { $0.value == base().hideIdle } ?? -1 },
                    ops: { index in
                        guard hiding.indices.contains(index) else { return [] }
                        return part(CursorPatch(hideIdle: .some(hiding[index].value)))
                    },
                    mixed: { baseMixed { $0.hideIdle } }),
                inspectorPopupRow(
                    "Clicks", binding, name: "Cursor Clicks", items: ["None", "Ripple"],
                    read: { clicks.firstIndex(of: props().clicks) ?? 0 },
                    ops: { index in
                        guard clicks.indices.contains(index) else { return [] }
                        return part(CursorPatch(clicks: clicks[index]))
                    },
                    mixed: { binding.mixedVideo { $0.cursor?.clicks ?? .off } }),
                inspectorColorRow(
                    "Ripple color", binding, name: "Ripple Color", read: rippleColor,
                    ops: { part(CursorPatch(clickColor: GraphicSchemaRows.css($0))) },
                    mixed: {
                        binding.mixedVideo {
                            ReelColor.normalise($0.cursor?.clickColor ?? CursorProps.defaultClickColor)
                        }
                    },
                    enabled: ripples, discrete: true),
                inspectorValueRow(
                    "Ripple size", binding, name: "Ripple Size", unit: "%", decimals: 0,
                    min: 25, max: 400, quick: [50, 100, 150, 200],
                    read: { props().clickSize * 100 },
                    ops: { part(CursorPatch(clickSize: $0 / 100)) },
                    mixed: { binding.mixedVideo { $0.cursor?.clickSize ?? 1 } },
                    enabled: ripples),
                inspectorRow(
                    nil, [polish], binding: binding, writes: part(CursorProps.polished)),
            ])
    }
}
