import Foundation

/// Make Vertical's step (spec §11 VR-30…VR-35; road map "creator-jobs" VR3a): a project's
/// tall or square version as one grouped edit — `set_canvas`, a "Backgrounds" track, one
/// `reframe_clip` per picture from the old canvas, its backdrops and plates re-filled — tried
/// on one `SwitchAngle.Trial`. The copy is `ProjectDocument+VerticalCopy.swift`'s, the tool
/// `AgentServer+VerticalVersion.swift`'s; File ▸ Make Vertical Version… is
/// `VerticalVersionSheetController.swift` and `EditorViewController+VerticalVersion.swift` (VR3b,
/// VR-39).
///
/// This file holds the shapes (VR-32), the settings and the classes (VR-33);
/// `VerticalVersion+Plan.swift` the step (VR-34); `VerticalVersion+Summary.swift` the summary
/// and the answer (VR-35, VR-36); `VerticalVersion+Layers.swift` the graphics (VR-42, VR-44,
/// VR4b); `VerticalVersion+Layouts.swift` class 2b and step 3b (VR-53, VR-54, VR5b). Swift restates none
/// of VR-26's refusals: a clip the core will not frame reaches `keep` through the core's own
/// sentence. Names no `rc_*`.
enum VerticalShape: String, CaseIterable {
    case tall = "9:16"
    case portrait = "4:5"
    case square = "1:1"

    /// Height over width.
    private var ratio: Double {
        switch self {
        case .tall: return 16.0 / 9.0
        case .portrait: return 5.0 / 4.0
        case .square: return 1
        }
    }

    /// VR-32: w = min(W, H) rounded down to even; h = 2 × round(w × ratio / 2).
    func size(from canvas: CanvasSnapshot) -> (width: Int, height: Int) {
        let short = min(canvas.width, canvas.height)
        let width = short - short % 2
        let height = 2 * Int((Double(width) * ratio / 2).rounded())
        return (width, height)
    }
}

/// What the step is asked for (VR-36's arguments, VR3b's sheet).
struct VerticalSettings: Equatable {
    var shape: VerticalShape
    /// One of `VerticalVersion.follows`.
    var follow: FramingFollow
    /// Times the scale that fills the canvas, 1–4 (the core refuses outside).
    var zoom: Double
    var whereEmpty: FramingWhereEmpty
    /// Whether step (6) re-pages the word caption tracks (spec §11 VR-40 (f)); the sheet
    /// passes the default, `make_vertical_version` its `captions`.
    var captions = true
    /// `follow: speaker`'s microphones (spec §11 VR-64 (a)): 2–4 clip ids, each standing for
    /// its track; read only with `speaker`.
    var mics: [UInt32] = []
    /// One face number per microphone in `mics`' order, or nil for the core's own match; read
    /// only with `speaker`.
    var micFaces: [UInt32]? = nil
}

enum VerticalVersion {
    /// The undo step's name (VR-31, FC-90).
    static let actionName = "Make Vertical"
    static let backgroundsName = FollowSubject.backgroundsName
    /// The name `add_blurred_background` and `reframe_clip`'s backdrop give a copy.
    static let blurredName = "Blurred Background"
    /// The sheet's Follow pop-up and the tool's `follow`, in order (spec §11 VR-66 (a)): Follow
    /// Subject's list with Speaker before Center.
    static let follows: [FramingFollow] = [.subject, .face, .person, .salient, .speaker, .center]

    /// Whether `follow` analyses the media pictures (VR-64 (c)): the following kinds and
    /// `speaker`, which frames its other pictures on their faces.
    static func analyses(_ follow: FramingFollow) -> Bool {
        follow.follows || follow == .speaker
    }

    /// The Make Vertical sheet's opening Follow and Where Empty (VR-66 (a)): VR-29 (c)'s key
    /// read against `follows`, so a stored `speaker` opens Speaker here while Follow Subject's
    /// sheet reads it as Subject; any other value is Subject. Where Empty as
    /// `FollowSubjectSettings.remembered`; Zoom is never remembered, so 1.
    static func remembered(_ defaults: UserDefaults) -> FollowSubjectSettings {
        var settings = FollowSubjectSettings.remembered(defaults, zoom: 1)
        let kind = defaults.string(forKey: FollowSubjectSettings.followKey)
            .flatMap(FramingFollow.init(rawValue:))
        settings.follow = kind.flatMap { follows.contains($0) ? $0 : nil } ?? .subject
        return settings
    }

    /// What the step did to one clip, as the answer spells it.
    enum Treatment: String {
        case followed, whole, kept, refilled, removed, resized, relaid
        case notFollowed = "not_followed"
    }

    /// VR-33's classes.
    enum Role: Equatable {
        /// (1) A blurred copy of the clip `partner`, in front of it.
        case backdrop(partner: UInt32)
        /// (2) A shape rectangle the canvas's size at the centre, scale 1.
        case shapePlate
        /// (2) An image or still named "Background" at the canvas's fill.
        case imagePlate
        /// (2b) A clip laid out by Clip ▸ Camera Layout ▸ as the camera, as the screen behind
        /// it, or a cut piece of one (VR-53 (a), `VerticalVersion+Layouts.swift`).
        case layoutCamera, layoutScreen, layoutPiece
        /// (3) A media, still or image clip covering one axis of the canvas.
        case picture
        /// (4) A nest clip covering one axis.
        case nest
        /// (5) A graphic exactly the canvas's size, each side (VR-42 (a)).
        case graphic
        /// (6) Everything else.
        case other
    }

    /// VR-33's first match per top-level clip with a picture (not audio-only, not an
    /// adjustment clip, video enabled), in id order, on the OLD canvas.
    static func classify(_ project: ReelProject) -> [(clip: UInt32, role: Role)] {
        let snapshot = project.snapshot
        let order = Dictionary(
            uniqueKeysWithValues: snapshot.tracks.enumerated().map { ($0.element.id, $0.offset) })
        return snapshot.clips.sorted { $0.id < $1.id }.compactMap { clip in
            guard hasPicture(clip, in: snapshot) else { return nil }
            return (clip.id, role(of: clip, in: project, order: order))
        }
    }

    /// The `.picture` clips whose source is `.media` (the analysis targets).
    static func mediaPictures(
        _ roles: [(clip: UInt32, role: Role)], in snapshot: ProjectSnapshot
    ) -> [UInt32] {
        roles.compactMap { entry in
            guard entry.role == .picture, let clip = snapshot.clip(entry.clip),
                case .media = clip.source
            else { return nil }
            return entry.clip
        }
    }

    /// VR-37's analysis targets: the media pictures (`mediaPictures(classify(project), …)`),
    /// split by whether their media has a URL in `urls` (`document.mediaURLs()`); `missing` are
    /// kept, not followed. A present one whose media has a cursor file is in `cursor`, never
    /// analysed: it follows its cursor (spec §11 VR-51). The tool's first hop and the sheet
    /// both read it (VR-39 (d)).
    static func analysisTargets(_ project: ReelProject, urls: [UInt32: URL])
        -> (present: [UInt32], missing: Set<UInt32>, cursor: [UInt32])
    {
        let snapshot = project.snapshot
        let pictures = mediaPictures(classify(project), in: snapshot)
        let missing = Set(pictures.filter { id in
            snapshot.clip(id)?.source.mediaID.map { urls[$0] == nil } ?? false
        })
        let found = pictures.filter { !missing.contains($0) }
        let cursor = found.filter { id in
            snapshot.clip(id).flatMap { snapshot.media(for: $0) }?.cursor != nil
        }
        return (found.filter { !cursor.contains($0) }, missing, cursor)
    }

    /// VR-32's "not offered": `VerticalShape.allCases` whose size differs from `canvas`, in case
    /// order (the sheet's Shape pop-up, VR-39 (b)).
    static func offered(_ canvas: CanvasSnapshot) -> [VerticalShape] {
        VerticalShape.allCases.filter { shape in
            let size = shape.size(from: canvas)
            return size.width != canvas.width || size.height != canvas.height
        }
    }

    /// "moves by its own motion: <name>" for the first active slot that is neither a fade nor
    /// a spin, in the order during, in, out; nil when there is none.
    static func motionNote(_ clip: ClipSnapshot) -> String? {
        guard let motion = clip.videoProps.motion else { return nil }
        if let during = motion.during, during.amount > 0, during.kind != .spin {
            return "moves by its own motion: \(during.kind.displayName)"
        }
        for edge in [motion.inEdge, motion.out].compactMap({ $0 })
        where edge.isActive && edge.kind != .fade && edge.kind != .spin {
            return "moves by its own motion: \(edge.kind.displayName)"
        }
        return nil
    }

    /// The scale that fills `canvas` with a source of `size` (`edit_fit.rs`'s `fill_scale`),
    /// clamped to the canvas sessions' range.
    static func fill(_ size: CGSize, width: Int, height: Int) -> Double {
        guard size.width > 0, size.height > 0 else { return 1 }
        let scale = max(Double(width) / size.width, Double(height) / size.height)
        return min(CanvasScaleSession.maxScale, max(CanvasScaleSession.minScale, scale))
    }

    // MARK: - The classes

    /// A clip that draws pixels: `ProjectSnapshot.layers(at:)`'s test without the time.
    private static func hasPicture(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Bool {
        guard clip.enabled.video else { return false }
        if case .adjustment = clip.source { return false }
        if let media = snapshot.media(for: clip) { return media.hasVideo || media.kind == .image }
        return true
    }

    private static func role(
        of clip: ClipSnapshot, in project: ReelProject, order: [UInt32: Int]
    ) -> Role {
        let snapshot = project.snapshot
        let canvas = snapshot.canvas
        if clip.name == blurredName, let partner = partner(of: clip, in: snapshot, order: order) {
            return .backdrop(partner: partner)
        }
        let video = clip.videoProps
        let centred = abs(video.x) <= 1e-6 && abs(video.y) <= 1e-6
        switch clip.source {
        case .shape:
            if let shape = clip.shape, shape.kind == .rectangle, centred,
                abs(video.scale - 1) <= 1e-6,
                abs(shape.width - Double(canvas.width)) <= 0.5,
                abs(shape.height - Double(canvas.height)) <= 0.5
            {
                return .shapePlate
            }
        case .image, .still:
            if clip.name == "Background", centred, let size = snapshot.sourceSize(of: clip) {
                let fill = fill(size, width: canvas.width, height: canvas.height)
                if abs(video.scale - fill) <= 1e-6 * fill { return .imagePlate }
            }
        case .graphic:
            if let graphic = clip.graphic, graphic.width == canvas.width,
                graphic.height == canvas.height
            {
                return .graphic
            }
        default:
            break
        }
        if let laid = layoutRole(of: clip, in: snapshot, order: order) { return laid }
        switch clip.source {
        case .media, .still, .image:
            if covers(clip, in: project) { return .picture }
        case .nest:
            if covers(clip, in: project) { return .nest }
        default:
            break
        }
        return .other
    }

    /// (1)'s partner: a clip on a track in front of `clip`'s with an equal source, start and
    /// duration; the nearest track first.
    private static func partner(
        of clip: ClipSnapshot, in snapshot: ProjectSnapshot, order: [UInt32: Int]
    ) -> UInt32? {
        guard let own = order[clip.track] else { return nil }
        return snapshot.clips
            .filter {
                $0.id != clip.id && (order[$0.track] ?? -1) > own && $0.source == clip.source
                    && $0.start == clip.start && $0.duration == clip.duration
            }
            .min { (order[$0.track] ?? 0, $0.id) < (order[$1.track] ?? 0, $1.id) }?.id
    }

    /// (3)'s test: the clip's rectangle at its first frame — base props with scale, x and y
    /// from `clip_state` at its start — covers one axis of the canvas (both edges at or beyond
    /// it, at most 1 px inside) and is centred within 2 % on the other, or covers it too.
    private static func covers(_ clip: ClipSnapshot, in project: ReelProject) -> Bool {
        let snapshot = project.snapshot
        guard let size = snapshot.sourceSize(of: clip) else { return false }
        var video = clip.videoProps
        if let state = project.clipState(clip.id, at: clip.start)?["video"] as? [String: Any] {
            if let scale = (state["scale"] as? NSNumber)?.doubleValue { video.scale = scale }
            if let x = (state["x"] as? NSNumber)?.doubleValue { video.x = x }
            if let y = (state["y"] as? NSNumber)?.doubleValue { video.y = y }
        }
        let canvas = snapshot.canvas
        let rect = canvasRect(of: clip, in: canvas, sourceSize: size, video: video)
        let (w, h) = (Double(canvas.width), Double(canvas.height))
        let coversX = rect.minX <= 1 && rect.maxX >= w - 1
        let coversY = rect.minY <= 1 && rect.maxY >= h - 1
        let centredX = abs(rect.midX - w / 2) <= 0.02 * w
        let centredY = abs(rect.midY - h / 2) <= 0.02 * h
        return (coversX && (centredY || coversY)) || (coversY && centredX)
    }
}
