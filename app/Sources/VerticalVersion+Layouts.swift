import Foundation

/// Make Vertical's camera layouts (spec §11 VR-53, VR-54; road map "creator-jobs" VR5b): class
/// 2b — a clip laid out by Clip ▸ Camera Layout ▸, as a camera, a screen, or a cut piece of one
/// — and step 3b, one `reframe_clip {follow: "layout"}` per camera, whose replay is the core's
/// (`core/src/reframe_layout.rs`). Swift restates none of the geometry: `isLayoutAction` and
/// `sameSource` twin `action_class.rs`'s `is_layout` and `layout_recognise.rs`'s `same_source`
/// for the classes, and `layoutName` names, for the summary only, an end the core has already
/// recognised. Names no `rc_*`.
extension VerticalVersion {

    /// One re-laid switch: the camera clip, its absolute start, the layout it was on the old
    /// canvas and the one it is now.
    struct Relaid: Equatable {
        let camera: UInt32
        let at: Ticks
        let from: CameraLayoutChoice
        let to: CameraLayoutKind
    }

    /// Step 3b's answer: the clips it changed, their entries and the switches, or the refusal
    /// that stops the step (a refused `keep`, VR-34).
    enum Relayed {
        case done(done: Set<UInt32>, entries: [UInt32: Entry], relaid: [Relaid])
        case refused(String)
    }

    /// The reason a layout role or piece no op re-laid is kept with.
    static let handEditedReason = "its camera layout was edited by hand, so it is kept as placed"

    /// The three roles class 2b gives.
    static func isLayoutRole(_ role: Role) -> Bool {
        role == .layoutCamera || role == .layoutScreen || role == .layoutPiece
    }

    /// A layout action: its end's `video` names all six placement keys (`action_class.rs`'s
    /// `is_layout`, CO-63).
    static func isLayoutAction(_ action: ActionSnapshot) -> Bool {
        guard let video = action.end.video else { return false }
        return video.x != nil && video.y != nil && video.scale != nil && video.crop != nil
            && video.cornerRadius != nil && video.opacity != nil
    }

    /// The same kind and the same media (a media, still or image source) or nest; `in`, `at`
    /// and `reversed` ignored (`same_source`'s twin), so a split half is the same source.
    static func sameSource(_ a: ClipSource, _ b: ClipSource) -> Bool {
        switch (a, b) {
        case (.media(let x, _, _), .media(let y, _, _)): return x == y
        case (.still(let x, _), .still(let y, _)): return x == y
        case (.image(let x), .image(let y)): return x == y
        case (.nest(let x), .nest(let y)): return x == y
        default: return false
        }
    }

    /// The absolute starts of `clip`'s layout actions.
    private static func layoutStarts(_ clip: ClipSnapshot) -> [Ticks] {
        clip.actions.filter(isLayoutAction).map { clip.start + $0.start }
    }

    /// Whether a base is a layout end within the core's recognition tolerances (1 px, 0.001).
    private static func alike(_ video: VideoProps, _ end: VideoPatch) -> Bool {
        guard let x = end.x, let y = end.y, let scale = end.scale, let crop = end.crop,
            let radius = end.cornerRadius, let opacity = end.opacity
        else { return false }
        let px = { (a: Double, b: Double) in abs(a - b) <= 1 }
        return px(video.x, x) && px(video.y, y) && px(video.crop.l, crop.l)
            && px(video.crop.t, crop.t) && px(video.crop.r, crop.r) && px(video.crop.b, crop.b)
            && px(video.cornerRadius, radius) && abs(video.scale - scale) <= 0.001
            && abs(video.opacity - opacity) <= 0.001
    }

    /// Class 2b (VR-53 (a)): a clip holding a layout action is a screen when a clip on a track
    /// in front holds one starting when one of its own does, else a camera; a clip of the same
    /// source as a laid-out clip R on R's track, starting after R's layout action and before
    /// the track's next one, whose base is that action's end, is a piece. nil otherwise.
    static func layoutRole(
        of clip: ClipSnapshot, in snapshot: ProjectSnapshot, order: [UInt32: Int]
    ) -> Role? {
        let own = order[clip.track] ?? -1
        let starts = layoutStarts(clip)
        if !starts.isEmpty {
            let screen = snapshot.clips.contains { other in
                other.id != clip.id && (order[other.track] ?? -1) > own
                    && layoutStarts(other).contains(where: starts.contains)
            }
            return screen ? .layoutScreen : .layoutCamera
        }
        guard snapshot.sourceSize(of: clip) != nil else { return nil }
        let track = snapshot.clips.filter { $0.track == clip.track }
        for laid in track where laid.id != clip.id && sameSource(laid.source, clip.source) {
            for action in laid.actions where isLayoutAction(action) {
                let at = laid.start + action.start
                let next = track.flatMap(layoutStarts).filter { $0 > at }.min() ?? .max
                if clip.start > at, clip.start < next, let end = action.end.video,
                    alike(clip.videoProps, end)
                {
                    return .layoutPiece
                }
            }
        }
        return nil
    }

    /// Step 3b (VR-53 (d)): one `reframe_clip {follow: "layout"}` from the old canvas per
    /// camera in id order, skipped when an earlier one changed it; every clip one changed is
    /// done (`relaid`). A refused op is not a stop: each layout role and piece left is kept
    /// (`keep`, VR-34's fallback) with `handEditedReason`. `width` × `height` is the new size.
    static func relay(
        _ roles: [(clip: UInt32, role: Role)], old: ProjectSnapshot, width: Int, height: Int,
        trial: inout SwitchAngle.Trial
    ) throws -> Relayed {
        let from = (UInt32(old.canvas.width), UInt32(old.canvas.height))
        var done: Set<UInt32> = []
        for (id, role) in roles where role == .layoutCamera && !done.contains(id) {
            let op = ReelOp.reframeClip(
                clip: id, follow: .layout, fromWidth: from.0, fromHeight: from.1)
            let prior = trial.project
            guard case .applied(let made) = try prior.applying(op) else { continue }
            trial.project = made
            trial.ops.append(op)
            let after = made.snapshot
            for clip in prior.snapshot.clips where after.clip(clip.id) != clip {
                done.insert(clip.id)
            }
        }
        var entries: [UInt32: Entry] = [:]
        for (id, role) in roles where isLayoutRole(role) || done.contains(id) {
            if done.contains(id) {
                entries[id] = Entry(clip: id, treatment: .relaid, reason: nil)
                continue
            }
            let keep = ReelOp.reframeClip(
                clip: id, follow: .keep, fromWidth: from.0, fromHeight: from.1)
            if let why = try trial.require(keep) {
                return .refused("Make Vertical was refused at reframe_clip for clip \(id): \(why)")
            }
            entries[id] = Entry(clip: id, treatment: .notFollowed, reason: handEditedReason)
        }
        var relaid: [Relaid] = []
        let tall = height > width
        for (id, role) in roles where role == .layoutCamera && done.contains(id) {
            guard let clip = old.clip(id) else { continue }
            for action in clip.actions where isLayoutAction(action) {
                guard let name = layoutName(action, of: clip, in: old) else { continue }
                let to: CameraLayoutKind = tall && name.kind == .sideBySide ? .stacked : name.kind
                relaid.append(
                    Relaid(camera: id, at: clip.start + action.start, from: name, to: to))
            }
        }
        relaid.sort { ($0.at, $0.camera) < ($1.at, $1.camera) }
        return .done(done: done, entries: entries, relaid: relaid)
    }

    /// The layout a camera's layout end shows on `snapshot`'s canvas (VR-54), for the summary
    /// and the answer only: opacity under 0.5 is Screen Only; x, y, every crop edge and the
    /// radius under 0.5 Camera Full; a picture within the corner box (0.25 W + 1 × H/3 + 1) a
    /// corner — Circle with a crop, Rounded with a radius, else square, the corner by the signs
    /// of x and y; else Stacked below the middle, Side by Side otherwise.
    static func layoutName(
        _ end: ActionSnapshot, of clip: ClipSnapshot, in snapshot: ProjectSnapshot
    ) -> CameraLayoutChoice? {
        guard let patch = end.end.video, let x = patch.x, let y = patch.y,
            let scale = patch.scale, let crop = patch.crop, let radius = patch.cornerRadius,
            let opacity = patch.opacity, let size = snapshot.sourceSize(of: clip)
        else { return nil }
        let kind = { (kind: CameraLayoutKind) in
            CameraLayoutChoice(kind: kind, shape: nil, corner: nil)
        }
        if opacity < 0.5 { return kind(.screenOnly) }
        let edges = [crop.l, crop.t, crop.r, crop.b]
        if abs(x) < 0.5, abs(y) < 0.5, edges.allSatisfy({ $0 < 0.5 }), radius < 0.5 {
            return kind(.cameraFull)
        }
        var video = clip.videoProps
        video.x = x
        video.y = y
        video.scale = scale
        video.crop = crop
        let canvas = snapshot.canvas
        let (w, h) = (Double(canvas.width), Double(canvas.height))
        let rect = canvasRect(of: clip, in: canvas, sourceSize: size, video: video)
        if rect.width <= 0.25 * w + 1, rect.height <= h / 3 + 1 {
            let shape: CameraLayoutShape =
                edges.contains { $0 > 0.5 } ? .circle : radius > 0.5 ? .rounded : .square
            let corner: CameraLayoutCorner =
                y > 0
                ? (x > 0 ? .bottomRight : .bottomLeft) : (x > 0 ? .topRight : .topLeft)
            return CameraLayoutChoice(kind: .corner, shape: shape, corner: corner)
        }
        return kind(rect.midY > h / 2 + 1 ? .stacked : .sideBySide)
    }

    /// A re-laid switch's summary line (VR-54).
    static func relaidLine(_ relaid: Relaid, canvas: CanvasSnapshot) -> String {
        let name =
            relaid.from.kind == .corner
            ? (relaid.from.shape ?? .square).menuTitle : relaid.from.kind.title
        let at = ReelTime.format(relaid.at, fps: canvas.fps, frames: canvas.timecodeFrames)
        if relaid.to != relaid.from.kind {
            return "Re-laid: \(name) → \(relaid.to.title) at \(at)."
        }
        return "Re-laid: \(name) at \(at)."
    }

    /// The answer's `relaid` (VR-54): `camera`, `at` in ticks, `from` and `to` in
    /// `switch_layout`'s words, and `shape` for a corner.
    static func relaidFields(_ relaid: [Relaid]) -> [[String: Any]] {
        relaid.map { entry in
            var row: [String: Any] = [
                "camera": Int(entry.camera), "at": Int(entry.at),
                "from": entry.from.kind.rawValue, "to": entry.to.rawValue,
            ]
            if entry.from.kind == .corner, let shape = entry.from.shape {
                row["shape"] = shape.rawValue
            }
            return row
        }
    }
}
