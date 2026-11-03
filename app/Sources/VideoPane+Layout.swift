import AppKit

/// The Layout section's choices (road map creator-jobs CO7, spec §11 CO-71), kept on `ClipPane`
/// so they outlive a rebuild: per window, never saved, not undoable.
final class CameraLayoutSectionState {
    var kind: CameraLayoutKind = .corner
    var shape: CameraLayoutShape = .square
    var corner: CameraLayoutCorner = .bottomRight
    var seconds: Double = 0.5

    /// The layout the section would switch to; a corner's shape and corner only for Corner.
    var choice: CameraLayoutChoice {
        kind == .corner
            ? CameraLayoutChoice(kind: .corner, shape: shape, corner: corner)
            : CameraLayoutChoice(kind: kind, shape: nil, corner: nil)
    }

    /// The switch's length, nil at the core's 0.5 s.
    var duration: Ticks? {
        let ticks = Ticks((seconds * 600_000).rounded())
        return ticks == CameraLayoutChoice.defaultDuration ? nil : ticks
    }
}

/// The Picture sub-tab's Layout section (CO-71), after Transform and Behind Subject and before
/// Crop: Layout, Shape and Corner pop-ups, Duration, and Switch at Playhead, which sends exactly
/// what Clip ▸ Camera Layout ▸ sends with this clip as the camera and the core finding the
/// screen, through `CameraLayoutCommand.run` (the focus on the person, CO-70; the nest offer,
/// CO-72). `switch_layout` is its MCP mirror. Shut by default; no Reset.
extension VideoPane {

    /// Exactly one clip selected, a `.media` clip with a picture and a source size.
    var allLayoutable: Bool {
        guard binding.isSingle, let clip = binding.primary, case .media = clip.source else {
            return false
        }
        return clip.video != nil && binding.snapshot.sourceSize(of: clip) != nil
    }

    func layoutSection(_ state: CameraLayoutSectionState) -> InspectorSection {
        let binding = self.binding
        let kinds = CameraLayoutKind.allCases
        let shapes = CameraLayoutShape.allCases
        let corners = CameraLayoutCorner.allCases
        let shapeTitles = ["Square", "Rounded", "Circle"]
        let isCorner: () -> Bool = { state.kind == .corner }
        func popup(
            _ items: [String], read: @escaping () -> Int, write: @escaping (Int) -> Void,
            enabled: @escaping () -> Bool = { true }
        ) -> OptionPopupControl {
            OptionPopupControl(
                width: InspectorMetrics.popupWidth, items: items, read: read, write: write,
                enabled: enabled, onEdit: { binding.edited() })
        }
        let layout = popup(
            kinds.map(\.title), read: { kinds.firstIndex(of: state.kind) ?? 0 },
            write: { if kinds.indices.contains($0) { state.kind = kinds[$0] } })
        let shape = popup(
            shapeTitles, read: { shapes.firstIndex(of: state.shape) ?? 0 },
            write: { if shapes.indices.contains($0) { state.shape = shapes[$0] } },
            enabled: isCorner)
        let corner = popup(
            corners.map(\.title), read: { corners.firstIndex(of: state.corner) ?? 0 },
            write: { if corners.indices.contains($0) { state.corner = corners[$0] } },
            enabled: isCorner)
        let duration = OptionFieldControl(
            width: InspectorMetrics.fieldWidth, unit: "s", decimals: 2, min: 0.01, max: 10,
            quick: [0.25, 0.5, 1, 2], read: { state.seconds },
            write: { state.seconds = $0 }, enabled: { true },
            onEdit: { binding.edited() })
        let switchButton = OptionButtonControl(
            title: "Switch at Playhead",
            action: { [weak self] in
                guard let document = binding.document, let clip = binding.primary else {
                    NSSound.beep()
                    return
                }
                CameraLayoutCommand.run(
                    state.choice, camera: clip.id, screen: nil, duration: state.duration,
                    document: document, window: self?.inspector?.view.window)
            },
            enabled: { [weak self] in self?.inspector?.view.window?.attachedSheet == nil },
            onEdit: {})
        switchButton.toolTip =
            "Lay out this clip as the camera, and the clip behind it as the screen, from the "
            + "playhead — what Clip ▸ Camera Layout ▸ does"
        return InspectorSection(
            id: "video.layout", title: "Layout",
            summary: {
                guard state.kind == .corner else { return state.kind.title }
                let shape = shapes.firstIndex(of: state.shape).map { shapeTitles[$0] } ?? ""
                return "\(shape), \(state.corner.title)"
            },
            defaultExpanded: false,
            rows: [
                inspectorRow("Layout", [layout]),
                inspectorRow("Shape", [shape]),
                inspectorRow("Corner", [corner]),
                inspectorRow("Duration", [duration]),
                inspectorButtonRow([switchButton]),
            ])
    }
}
