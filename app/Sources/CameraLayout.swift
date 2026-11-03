import Foundation

// Camera layouts (road map "creator-jobs" CO6, spec §11 CO-60…CO-66): the
// three vocabularies `switch_layout` takes, mirroring `core/src/layout.rs`'s
// `CameraLayout`, `LayoutShape` and `LayoutCorner` (the op table publishes
// the same members); the Clip ▸ Camera Layout ▸ rows; and the role rule the
// menu reads its camera and screen by. Pure: no `rc_*`, no view.

/// The five layouts (CO-60).
enum CameraLayoutKind: String, CaseIterable {
    case corner
    case sideBySide = "side_by_side"
    case stacked
    case cameraFull = "camera_full"
    case screenOnly = "screen_only"

    var title: String {
        switch self {
        case .corner: return "Corner"
        case .sideBySide: return "Side by Side"
        case .stacked: return "Stacked"
        case .cameraFull: return "Camera Full"
        case .screenOnly: return "Screen Only"
        }
    }
}

/// The corner picture's shape.
enum CameraLayoutShape: String, CaseIterable {
    case square, rounded, circle

    /// The corner submenu's title for this shape.
    var menuTitle: String {
        switch self {
        case .square: return "Corner"
        case .rounded: return "Rounded Corner"
        case .circle: return "Circle"
        }
    }
}

/// The canvas corner the corner picture sits in.
enum CameraLayoutCorner: String, CaseIterable {
    case bottomRight = "bottom_right"
    case bottomLeft = "bottom_left"
    case topRight = "top_right"
    case topLeft = "top_left"

    var title: String {
        switch self {
        case .bottomRight: return "Bottom Right"
        case .bottomLeft: return "Bottom Left"
        case .topRight: return "Top Right"
        case .topLeft: return "Top Left"
        }
    }
}

/// One Clip ▸ Camera Layout ▸ row: a layout and, for a corner, its shape
/// and corner. A menu item's tag is its index in `menuRows` (CO-66).
struct CameraLayoutChoice: Equatable {
    let kind: CameraLayoutKind
    let shape: CameraLayoutShape?
    let corner: CameraLayoutCorner?

    /// Every corner shape at each corner, then the other four layouts, in
    /// the menu's order.
    static let menuRows: [CameraLayoutChoice] =
        CameraLayoutShape.allCases.flatMap { shape in
            CameraLayoutCorner.allCases.map {
                CameraLayoutChoice(kind: .corner, shape: shape, corner: $0)
            }
        }
        + [.sideBySide, .stacked, .cameraFull, .screenOnly].map {
            CameraLayoutChoice(kind: $0, shape: nil, corner: nil)
        }

    /// The row's own title: the corner inside a shape's submenu, else the
    /// layout.
    var title: String { corner?.title ?? kind.title }

    /// The core's switch length when `duration` is absent (`DEFAULT_SWITCH`, 0.5 s).
    static let defaultDuration: Ticks = 300_000

    /// The op at `at` for these roles; an absent `duration` and `curve` are the core's. `focus`
    /// is the camera crop's centre (CO-70), `nest` the offer's yes (CO-72).
    func op(
        camera: UInt32, screen: UInt32?, at: Ticks, duration: Ticks? = nil,
        focus: (Double, Double)? = nil, nest: Bool? = nil
    ) -> ReelOp {
        .switchLayout(
            camera: camera, screen: screen, layout: kind, shape: shape, corner: corner, at: at,
            duration: duration, focus: focus, nest: nest)
    }
}

/// Who is the camera and who the screen for the menu (CO-66).
enum CameraLayoutRoles {
    /// The track a recording's camera lands on (`RecordingLanding`).
    static let cameraTrackName = "Camera"

    /// Two selected picture clips on different tracks: the front one is the
    /// camera and the other the screen. One: it is the camera and the core
    /// finds the screen. None: the clip at the playhead on the front-most
    /// track named "Camera". nil when that yields no camera containing the
    /// playhead.
    static func roles(selected: [ClipSnapshot], playhead: Ticks, in snapshot: ProjectSnapshot)
        -> (camera: UInt32, screen: UInt32?)?
    {
        let picture = { (clip: ClipSnapshot) in
            clip.video != nil && snapshot.sourceSize(of: clip) != nil
        }
        let plays = { (clip: ClipSnapshot) in clip.start <= playhead && playhead < clip.end }
        switch selected.count {
        case 2:
            guard selected.allSatisfy(picture),
                let a = snapshot.trackIndex(of: selected[0].track),
                let b = snapshot.trackIndex(of: selected[1].track), a != b
            else { return nil }
            let (camera, screen) = a > b ? (selected[0], selected[1]) : (selected[1], selected[0])
            return plays(camera) ? (camera.id, screen.id) : nil
        case 1:
            let camera = selected[0]
            return picture(camera) && plays(camera) ? (camera.id, nil) : nil
        case 0:
            guard let track = snapshot.tracks.last(where: { $0.name == cameraTrackName }),
                let camera = snapshot.clips.first(where: {
                    $0.track == track.id && plays($0) && picture($0)
                })
            else { return nil }
            return (camera.id, nil)
        default:
            return nil
        }
    }
}
