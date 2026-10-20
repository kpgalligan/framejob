import AppKit

/// What the Camera Log popup can say: none, a built-in curve with its gamut,
/// a `lut` media of the project, or the Use LUT… row that imports one.
enum CameraLogChoice: Equatable {
    case none
    case curve(LogCurve, CameraGamut)
    case lut(UInt32)
    case useLUT

    /// The built-in rows, in the popup's order (spec §11 GR-16): every curve
    /// with each gamut it pairs with.
    static let curves: [CameraLogChoice] = [
        .curve(.appleLog, .bt2020), .curve(.appleLog2, .appleWideGamut),
        .curve(.slog3, .sGamut3Cine), .curve(.slog3, .sGamut3), .curve(.vlog, .vGamut),
    ]

    /// A media's setting as a row: its curve and gamut (the curve's first
    /// when none is stored), else its LUT, else none.
    init(_ color: MediaColor?) {
        if let log = color?.log, let gamut = color?.effectiveGamut {
            self = .curve(log, gamut)
        } else if let lut = color?.lut {
            self = .lut(lut)
        } else {
            self = .none
        }
    }

    /// The row's title: "S-Log3 / S-Gamut3.Cine", "Apple Log" (a curve with
    /// one gamut is named alone), "LUT: <name>".
    func title(in snapshot: ProjectSnapshot) -> String {
        switch self {
        case .none: return "None"
        case .curve(let log, let gamut):
            return log.gamuts.count > 1 || log == .vlog
                ? "\(log.displayName) / \(gamut.displayName)" : log.displayName
        case .lut(let id):
            return "LUT: " + (snapshot.media(id).map(LookGallery.lutName) ?? "media \(id)")
        case .useLUT: return "Use LUT…"
        }
    }
}

/// The Media tab's **Camera Log** section (spec §11 GR-16, §4.3): how the
/// file selected in the list is converted at step 0 — None, a maker's curve,
/// or a `.cube` LUT — one undo step "Camera Log", and a line saying what is
/// set and whether it came from the file. It acts on `selectedMedia`, the row
/// a click selects (`MediaPaneCommands.select(_:)`, which refreshes this
/// section), and is disabled when that is not a video file. The agent's
/// mirror is `set_media_color` (`AgentServer+Media.swift`).
extension MediaPane {
    func cameraLogSection() -> InspectorSection {
        let binding = self.binding
        /// The selected row when it is a video file.
        func selected() -> MediaSnapshot? {
            guard let id = binding.document?.selectedMedia,
                let media = binding.documentSnapshot.media(id), media.kind == .video
            else { return nil }
            return media
        }
        let snapshot = binding.documentSnapshot
        let luts = LookGallery.luts(in: snapshot).map { CameraLogChoice.lut($0.id) }
        let choices = ([CameraLogChoice.none] + CameraLogChoice.curves + luts + [.useLUT])
            .map { (title: $0.title(in: snapshot), value: $0) }
        let popup = OptionPopupControl(
            width: InspectorMetrics.popupWidth + 52, choices: choices,
            read: { CameraLogChoice(selected()?.color) },
            write: { [weak self] choice in
                guard let media = selected(), choice != CameraLogChoice(media.color) else { return }
                // Every write keeps a PQ file's peak override (spec §11 HD-12):
                // `color` replaces the Camera Log and the override together.
                let pq = media.color?.pq
                switch choice {
                case .none:
                    binding.apply(
                        "Camera Log", [.setMediaColor(media: media.id, color: MediaColor(pq: pq))])
                case .curve(let log, let gamut):
                    binding.apply(
                        "Camera Log",
                        [.setMediaColor(
                            media: media.id, color: MediaColor(log: log, gamut: gamut, pq: pq))])
                case .lut(let lut):
                    binding.apply(
                        "Camera Log",
                        [.setMediaColor(media: media.id, color: MediaColor(lut: lut, pq: pq))])
                case .useLUT:
                    self?.inspector?.onCommand?(
                        #selector(EditorViewController.useCameraLogLUT(_:)))
                }
            },
            enabled: { selected() != nil },
            onEdit: { binding.edited() })
        popup.toolTip = "How this file's log footage is converted to Rec. 709"
        let readout = inspectorReadout(width: InspectorMetrics.popupWidth + 52) {
            guard let media = selected() else { return "Select a video in the list" }
            let title = CameraLogChoice(media.color).title(in: binding.documentSnapshot)
            return media.color?.detected == true ? "\(title) — from the file" : title
        }
        return InspectorSection(
            id: "media.camera_log", title: "Camera Log",
            summary: {
                selected().map {
                    CameraLogChoice($0.color).title(in: binding.documentSnapshot)
                }
            },
            rows: [inspectorRow("Log", [popup]), inspectorRow(nil, [readout])])
    }
}
