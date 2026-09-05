import AppKit

/// The preview canvas's geometry and its gesture sessions (spec §4.2).
///
/// Everything here works in CANVAS space — pixels, origin at the canvas's
/// top-left, **y growing downward** — which is the space `canvasRect(of:in:
/// sourceSize:video:)` and `canvasAnchor(of:in:video:)` in
/// `ProjectSnapshot.swift` speak, and the space the frame recipe describes.
/// `PreviewCanvasView` owns the one conversion to and from view points
/// (`canvasToView` / `viewToCanvas`, mapped through `AVPlayerLayer.videoRect`
/// so handles and pixels cannot drift); nothing in this file knows about
/// points, zoom or panning.
///
/// **The pitfall this file exists to avoid:** placement is *not*
/// re-derivable. Cropping removes edges in place and rotation happens about
/// the *uncropped* centre, so every rectangle comes from `canvasRect` and
/// every rotation from `canvasAnchor` — never from a hand-rolled transform.

// MARK: - Rotation

/// Rotates `vector` by `degrees`. Canvas y grows downward, so a positive
/// angle reads CLOCKWISE on screen — the same sense `FrameRecipe.layer(at:)`
/// un-rotates by, which is what keeps overlay hit-testing and the
/// compositor's hit-testing the same answer.
func canvasRotate(_ vector: CGVector, degrees: Double) -> CGVector {
    guard degrees != 0 else { return vector }
    let radians = degrees * .pi / 180
    let c = cos(radians)
    let s = sin(radians)
    return CGVector(dx: vector.dx * c - vector.dy * s, dy: vector.dx * s + vector.dy * c)
}

/// The inverse of `canvasRotate` — a canvas point taken back into the
/// layer's own axis-aligned space.
func canvasUnrotate(_ vector: CGVector, degrees: Double) -> CGVector {
    canvasRotate(vector, degrees: -degrees)
}

// MARK: - Handles

/// One of the eight scale handles of a selection box, named for where it
/// sits in the layer's OWN (un-rotated) canvas rect. The canvas is y-down,
/// so "top" is the smaller y — exactly what it looks like on screen.
enum CanvasHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    /// Position in the unit square measured from the rect's centre: -1, 0 or
    /// +1 on each axis.
    var unit: CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: -1, y: -1)
        case .top: return CGPoint(x: 0, y: -1)
        case .topRight: return CGPoint(x: 1, y: -1)
        case .right: return CGPoint(x: 1, y: 0)
        case .bottomRight: return CGPoint(x: 1, y: 1)
        case .bottom: return CGPoint(x: 0, y: 1)
        case .bottomLeft: return CGPoint(x: -1, y: 1)
        case .left: return CGPoint(x: -1, y: 0)
        }
    }

    /// The handle across the box — the point a plain (no-⌥) scale drag pins.
    var opposite: CanvasHandle {
        switch self {
        case .topLeft: return .bottomRight
        case .top: return .bottom
        case .topRight: return .bottomLeft
        case .right: return .left
        case .bottomRight: return .topLeft
        case .bottom: return .top
        case .bottomLeft: return .topRight
        case .left: return .right
        }
    }

    /// Corners drive both axes; edge midpoints drive one.
    var isCorner: Bool { unit.x != 0 && unit.y != 0 }
    var drivesX: Bool { unit.x != 0 }
    var drivesY: Bool { unit.y != 0 }

    /// Where the handle sits on `rect`, in the rect's own (un-rotated) space.
    func point(in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.midX + unit.x * rect.width / 2,
            y: rect.midY + unit.y * rect.height / 2)
    }

    /// AppKit has no diagonal resize cursor in its public API, so corners get
    /// the crosshair rather than a cursor that lies about the axis.
    var cursor: NSCursor {
        if isCorner { return .crosshair }
        return drivesX ? .resizeLeftRight : .resizeUpDown
    }
}

/// Which end of a `line` / `arrow` shape a drag grabbed (spec §4.2's
/// endpoint handles). Distinct from `TimelineEdge`, which is a *time* edge.
enum CanvasEndpoint: Equatable {
    case from
    case to
}

/// What is under the pointer on the canvas. Computed once per press by
/// `PreviewCanvasView.hit(at:)` and handed to the session that owns that kind
/// of drag, so "what did I grab" is decided in one function instead of being
/// re-derived by every mouse handler.
enum CanvasHit: Equatable {
    case handle(UInt32, CanvasHandle)
    case rotation(UInt32)
    case cropHandle(UInt32, CanvasHandle)
    case endpoint(UInt32, CanvasEndpoint)
    case body(UInt32)
    /// The void, or the canvas with nothing under the pointer.
    case empty
}

// MARK: - A layer's box on the canvas

/// One frame-recipe layer paired with the clip it came from and the source
/// size the platform measured for it — everything the overlay needs to draw
/// a box, hit-test it, or snap to it.
///
/// The recipe carries EVALUATED properties (actions already applied, §5.4),
/// which is what must be drawn; the ops a gesture emits are written against
/// the clip's BASE props instead, because that is what `set_video` merges
/// into. The two are the same value until a clip has actions (M3).
struct CanvasLayerBox {
    let clip: ClipSnapshot
    let canvas: CanvasSnapshot
    /// The layer's evaluated video properties (`RecipeLayer.videoProps`).
    let video: VideoProps
    /// Uncropped source size: media pixels, the shape box, or the measured
    /// text layout box (`LayerRenderers.measuredSize(for:)`).
    let sourceSize: CGSize
    /// A locked track is drawn but never hit (spec §4.2).
    let locked: Bool

    var id: UInt32 { clip.id }
    var rotation: Double { video.rotation }

    /// The rotation centre — the centre of the UNCROPPED rectangle. Cropping
    /// never moves it, which is exactly why it is its own function.
    var anchor: CGPoint { canvasAnchor(of: clip, in: canvas, video: video) }

    /// The cropped rectangle, un-rotated: what the compositor draws pixels
    /// into, and what the eight handles hang off.
    var rect: CGRect {
        canvasRect(of: clip, in: canvas, sourceSize: sourceSize, video: video)
    }

    /// The same rectangle with the crop taken out — the crop-mode ghost, and
    /// the box a shape's unit-space endpoints are measured in.
    var uncroppedRect: CGRect {
        canvasRect(of: clip, in: canvas, sourceSize: sourceSize, video: uncropped)
    }

    /// `video` with the crop zeroed. Built through the real initializer so a
    /// property added to `VideoProps` cannot be silently dropped here.
    var uncropped: VideoProps {
        VideoProps(
            x: video.x, y: video.y, scale: video.scale, rotation: video.rotation,
            opacity: video.opacity, crop: .zero, cornerRadius: video.cornerRadius,
            shadow: video.shadow, color: video.color, chroma: video.chroma)
    }

    /// A point in the layer's axis-aligned space, taken into canvas space.
    func rotated(_ point: CGPoint) -> CGPoint {
        let a = anchor
        let v = canvasRotate(
            CGVector(dx: point.x - a.x, dy: point.y - a.y), degrees: rotation)
        return CGPoint(x: a.x + v.dx, y: a.y + v.dy)
    }

    /// A canvas point taken back into the layer's axis-aligned space, where
    /// `rect` and the crop insets live.
    func unrotated(_ point: CGPoint) -> CGPoint {
        let a = anchor
        let v = canvasUnrotate(
            CGVector(dx: point.x - a.x, dy: point.y - a.y), degrees: rotation)
        return CGPoint(x: a.x + v.dx, y: a.y + v.dy)
    }

    /// Hit test in canvas space, rotation included.
    func contains(_ point: CGPoint) -> Bool { rect.contains(unrotated(point)) }

    /// The cropped rectangle's four corners in canvas space, TL TR BR BL.
    var corners: [CGPoint] { corners(of: rect) }

    func corners(of box: CGRect) -> [CGPoint] {
        [
            rotated(CGPoint(x: box.minX, y: box.minY)),
            rotated(CGPoint(x: box.maxX, y: box.minY)),
            rotated(CGPoint(x: box.maxX, y: box.maxY)),
            rotated(CGPoint(x: box.minX, y: box.maxY)),
        ]
    }

    /// The axis-aligned bounds of the ROTATED box — what snapping and the
    /// visible-extent tests use, so a turned clip still offers sane edges.
    var bounds: CGRect {
        let points = corners
        guard let first = points.first else { return rect }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func handlePoint(_ handle: CanvasHandle) -> CGPoint { rotated(handle.point(in: rect)) }

    func cropHandlePoint(_ handle: CanvasHandle) -> CGPoint { handlePoint(handle) }

    /// The rotation grip, `offset` canvas pixels beyond the top edge along
    /// the box's own "up".
    func rotationHandlePoint(offset: CGFloat) -> CGPoint {
        let up = canvasRotate(CGVector(dx: 0, dy: -1), degrees: rotation)
        let top = handlePoint(.top)
        return CGPoint(x: top.x + up.dx * offset, y: top.y + up.dy * offset)
    }

    /// A line/arrow endpoint in canvas space. Endpoints are UNIT coordinates
    /// in the uncropped box (`ShapeProps.from` / `.to`).
    func endpointPoint(_ endpoint: CanvasEndpoint) -> CGPoint? {
        guard let shape = clip.shape, shape.kind.isLinear else { return nil }
        let unit = endpoint == .from ? shape.fromPoint : shape.toPoint
        let box = uncroppedRect
        return rotated(
            CGPoint(x: box.minX + unit.x * box.width, y: box.minY + unit.y * box.height))
    }

    /// The inverse: a canvas point as unit coordinates in the uncropped box,
    /// clamped to it.
    func endpointUnit(_ point: CGPoint) -> CGPoint {
        let box = uncroppedRect
        guard box.width > 0, box.height > 0 else { return .zero }
        let local = unrotated(point)
        return CGPoint(
            x: min(max((local.x - box.minX) / box.width, 0), 1),
            y: min(max((local.y - box.minY) / box.height, 0), 1))
    }

    // MARK: Building

    /// The boxes of one composed frame, back to front — the recipe's own
    /// order, which is the order the compositor draws in and the reverse of
    /// the order the canvas hit-tests in.
    static func boxes(recipe: FrameRecipe, snapshot: ProjectSnapshot) -> [CanvasLayerBox] {
        recipe.layers.compactMap { layer in
            guard let clip = snapshot.clip(layer.clip) else { return nil }
            guard let size = LayerRenderers.measuredSize(for: layer)
                ?? snapshot.sourceSize(of: clip), size.width > 0, size.height > 0
            else { return nil }
            return CanvasLayerBox(
                clip: clip, canvas: snapshot.canvas, video: layer.videoProps, sourceSize: size,
                locked: snapshot.track(clip.track)?.locked ?? false)
        }
    }

    /// The degraded path, used only when the core cannot answer with a
    /// recipe: the same list from the snapshot alone, with base props and no
    /// action evaluation. Text is measured the same way, so a text clip still
    /// gets a box.
    static func boxes(snapshot: ProjectSnapshot, at time: Ticks) -> [CanvasLayerBox] {
        snapshot.layers(at: time).compactMap { clip in
            var size = snapshot.sourceSize(of: clip)
            if size == nil, let text = clip.text {
                size = LayerRenderers.measuredSize(for: text)
            }
            guard let resolved = size, resolved.width > 0, resolved.height > 0 else { return nil }
            return CanvasLayerBox(
                clip: clip, canvas: snapshot.canvas, video: clip.videoProps, sourceSize: resolved,
                locked: snapshot.track(clip.track)?.locked ?? false)
        }
    }
}

// MARK: - Snapping

/// Spec §4.2's canvas snapping: the canvas centre lines, its edges, its
/// thirds, and every other visible layer's edges and centres.
///
/// The candidates are computed here in Swift from the layer rects — the core
/// has no idea where anything sits on screen — but the nearest-within-
/// threshold *pick* is `ReelSnap.resolve` (i.e. `rc_snap_resolve`), so the
/// canvas and the timeline snap by the same rule. That function speaks in
/// `Ticks`, so canvas coordinates are rounded to whole pixels on the way in;
/// a snap is always to a pixel, which is what the guides promise anyway.
struct CanvasSnapper {
    /// Grab radius in VIEW points, converted to canvas pixels per zoom.
    static let threshold: CGFloat = 8

    let xs: [Ticks]
    let ys: [Ticks]
    /// The radius in canvas pixels at the current zoom.
    let threshold: Ticks
    /// Folds together the N toggle and the ⌘ suppression, so no session ever
    /// looks at modifier flags itself.
    let enabled: Bool

    /// What a proposed rectangle has to move by to sit on a candidate, plus
    /// the guide lines to draw (canvas coordinates, nil when nothing snapped).
    struct Result {
        var offset = CGVector.zero
        var guideX: CGFloat?
        var guideY: CGFloat?
    }

    /// Tries the rectangle's leading edge, centre and trailing edge on each
    /// axis and takes the smallest correction of the three.
    func resolve(rect: CGRect) -> Result {
        var result = Result()
        guard enabled else { return result }
        if let hit = best(of: [rect.minX, rect.midX, rect.maxX], in: xs) {
            result.offset.dx = hit.delta
            result.guideX = hit.guide
        }
        if let hit = best(of: [rect.minY, rect.midY, rect.maxY], in: ys) {
            result.offset.dy = hit.delta
            result.guideY = hit.guide
        }
        return result
    }

    private func best(
        of anchors: [CGFloat], in candidates: [Ticks]
    ) -> (delta: CGFloat, guide: CGFloat)? {
        var winner: (delta: CGFloat, guide: CGFloat)?
        for anchor in anchors {
            let (resolved, snapped) = ReelSnap.resolve(
                candidates, CanvasSnapper.tick(anchor), threshold: threshold)
            guard snapped else { continue }
            let delta = CGFloat(resolved) - anchor
            if let current = winner, abs(current.delta) <= abs(delta) { continue }
            winner = (delta, CGFloat(resolved))
        }
        return winner
    }

    /// A canvas coordinate as a whole pixel, clamped well inside `Int64` so a
    /// runaway drag cannot trap the conversion.
    static func tick(_ value: CGFloat) -> Ticks {
        guard value.isFinite else { return 0 }
        return Ticks(min(max(value.rounded(), -1e9), 1e9))
    }

    /// Canvas landmarks plus the other layers'. `excluding` is the clips the
    /// gesture is moving — a drag must not snap to itself.
    static func candidates(
        boxes: [CanvasLayerBox], excluding: Set<UInt32>, canvas: CanvasSnapshot
    ) -> (xs: [Ticks], ys: [Ticks]) {
        let width = CGFloat(canvas.width)
        let height = CGFloat(canvas.height)
        var xs: Set<Ticks> = [
            tick(0), tick(width / 3), tick(width / 2), tick(width * 2 / 3), tick(width),
        ]
        var ys: Set<Ticks> = [
            tick(0), tick(height / 3), tick(height / 2), tick(height * 2 / 3), tick(height),
        ]
        for box in boxes where !excluding.contains(box.id) {
            let bounds = box.bounds
            xs.formUnion([tick(bounds.minX), tick(bounds.midX), tick(bounds.maxX)])
            ys.formUnion([tick(bounds.minY), tick(bounds.midY), tick(bounds.maxY)])
        }
        return (xs.sorted(), ys.sorted())
    }
}

/// Trims a canvas coordinate to three decimals before it goes into an op.
/// Snapping produces whole or half pixels; this only keeps float noise out of
/// the project JSON, where it would make two identical edits compare unequal.
func canvasRound(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return (value * 1000).rounded() / 1000
}

// MARK: - Move

/// Dragging inside the box to move the selection (spec §4.2). Every selected
/// clip moves by the same canvas-space delta; the anchor clip's rectangle is
/// what snapping tests, so the whole selection clicks into place together.
///
/// The op writes BASE props plus the delta, never the evaluated position, so
/// a clip inside an action is not silently baked to its animated value.
struct CanvasMoveSession {
    /// Base `(x, y)` per clip, captured from the gesture-start snapshot.
    let bases: [UInt32: CGPoint]
    let anchor: UInt32
    /// The anchor's rotated bounds at mouse-down.
    let anchorBounds: CGRect
    /// Pointer position at mouse-down, canvas space.
    let grab: CGPoint

    var delta = CGVector.zero
    var guideX: CGFloat?
    var guideY: CGFloat?
    /// False until the pointer actually leaves the press point — a click that
    /// only selects must not register an undo step.
    var didMove = false

    /// One `set_video` per clip: each keeps its own base position, so a
    /// multi-clip move cannot collapse the selection onto one point.
    var ops: [ReelOp] {
        bases.keys.sorted().compactMap { id in
            guard let base = bases[id] else { return nil }
            return .setVideo(
                clips: [id],
                patch: VideoPatch(
                    x: canvasRound(base.x + delta.dx), y: canvasRound(base.y + delta.dy)))
        }
    }

    mutating func update(point: CGPoint, snapper: CanvasSnapper) {
        var raw = CGVector(dx: point.x - grab.x, dy: point.y - grab.y)
        let proposed = anchorBounds.offsetBy(dx: raw.dx, dy: raw.dy)
        let result = snapper.resolve(rect: proposed)
        raw.dx += result.offset.dx
        raw.dy += result.offset.dy
        delta = raw
        guideX = result.guideX
        guideY = result.guideY
        didMove = true
    }
}

// MARK: - Scale

/// What a scale drag is allowed to change, which depends on what the model
/// stores for that clip (§5.2).
///
/// **The pitfall:** a clip has ONE uniform `scale` — there is no per-axis
/// scale for pixels. So "edges scale one axis" and "⇧ frees the aspect" can
/// only be honoured where the model owns a second number: a shape's
/// `width`/`height`, or a text clip's wrap `width`. Everywhere else a drag
/// stays uniform rather than pretending otherwise.
enum CanvasScaleTarget: Equatable {
    /// Media, stills, images, nests — `video.scale` only.
    case uniform
    /// A shape's box, in model units.
    case box(CGSize)
    /// A text clip's wrap width (nil = auto-sized); the measured width at
    /// mouse-down stands in for it.
    case textWidth(Double)
}

/// One clip resized by one of the eight handles (spec §4.2). ⌥ scales about
/// the centre; without it the opposite handle is pinned, which means the
/// clip's position moves too — hence the `x`/`y` in the patch.
struct CanvasScaleSession {
    let clip: UInt32
    let handle: CanvasHandle
    let target: CanvasScaleTarget
    /// The clip's BASE video props at mouse-down (see `CanvasLayerBox`).
    let base: VideoProps
    /// The uncropped rectangle at mouse-down, un-rotated, canvas space. Its
    /// centre IS the rotation anchor, which is what makes the position
    /// correction below a plain rotation of the centre's displacement.
    let startRect: CGRect
    let rotation: Double

    var scale: Double
    var boxSize: CGSize
    var textWidth: Double
    /// True once a `.textWidth` drag has actually taken the width path. The
    /// other six handles of a text clip fall back to a uniform scale, and
    /// `ops` must then emit `set_video` rather than `set_text`.
    var widthOnly = false
    /// Change in the clip's `(x, y)`, canvas space.
    var offset = CGVector.zero
    var didMove = false

    static let minScale = 0.01
    static let maxScale = 10.0
    static let minBox = 4.0
    static let maxBox = 20000.0

    var ops: [ReelOp] {
        let placement = VideoPatch(
            x: canvasRound(base.x + offset.dx), y: canvasRound(base.y + offset.dy))
        var uniform = placement
        uniform.scale = canvasRound(scale)
        switch target {
        case .uniform:
            return [.setVideo(clips: [clip], patch: uniform)]
        case .box:
            return [
                .setShape(
                    clips: [clip],
                    patch: ShapePatch(
                        width: canvasRound(boxSize.width), height: canvasRound(boxSize.height))),
                .setVideo(clips: [clip], patch: placement),
            ]
        case .textWidth:
            guard widthOnly else { return [.setVideo(clips: [clip], patch: uniform)] }
            return [
                .setText(clips: [clip], patch: TextPatch(width: .some(canvasRound(textWidth))))
            ]
        }
    }

    /// `point` is the pointer in canvas space; `aspectFree` is ⇧ and
    /// `aboutCentre` is ⌥.
    mutating func update(point: CGPoint, aspectFree: Bool, aboutCentre: Bool) {
        let centre = CGPoint(x: startRect.midX, y: startRect.midY)
        let grip = handle.point(in: startRect)
        let pivot = aboutCentre ? centre : handle.opposite.point(in: startRect)
        // The pointer, taken back into the layer's own axis-aligned space —
        // the space `startRect` and the handles live in.
        let local = unrotatedPoint(point, about: centre)

        let dx0 = grip.x - pivot.x
        let dy0 = grip.y - pivot.y
        let dx = local.x - pivot.x
        let dy = local.y - pivot.y
        let axisX = abs(dx0) > 0.001 ? dx / dx0 : 1
        let axisY = abs(dy0) > 0.001 ? dy / dy0 : 1
        let square = dx0 * dx0 + dy0 * dy0
        let diagonal = square > 0.001 ? (dx * dx0 + dy * dy0) / square : 1

        var fx: CGFloat = 1
        var fy: CGFloat = 1
        switch target {
        case .uniform:
            let f = handle.isCorner ? diagonal : (handle.drivesX ? axisX : axisY)
            let clamped = min(
                max(base.scale * Double(f), CanvasScaleSession.minScale),
                CanvasScaleSession.maxScale)
            scale = clamped
            let applied = base.scale > 0 ? clamped / base.scale : 1
            fx = CGFloat(applied)
            fy = fx

        case .box(let start):
            var wide = start.width
            var high = start.height
            if handle.isCorner {
                wide = start.width * Double(aspectFree ? axisX : diagonal)
                high = start.height * Double(aspectFree ? axisY : diagonal)
            } else if handle.drivesX {
                wide = start.width * Double(axisX)
            } else {
                high = start.height * Double(axisY)
            }
            boxSize = CGSize(
                width: min(max(wide, CanvasScaleSession.minBox), CanvasScaleSession.maxBox),
                height: min(max(high, CanvasScaleSession.minBox), CanvasScaleSession.maxBox))
            fx = start.width > 0 ? CGFloat(boxSize.width / start.width) : 1
            fy = start.height > 0 ? CGFloat(boxSize.height / start.height) : 1

        case .textWidth(let start):
            guard handle.drivesX, !handle.isCorner else {
                // Corners and the top/bottom edges have no second axis to
                // give a text clip, so they scale it uniformly instead.
                let f = handle.isCorner ? diagonal : axisY
                scale = min(
                    max(base.scale * Double(f), CanvasScaleSession.minScale),
                    CanvasScaleSession.maxScale)
                let applied = base.scale > 0 ? scale / base.scale : 1
                widthOnly = false
                apply(fx: CGFloat(applied), fy: CGFloat(applied), pivot: pivot, centre: centre)
                didMove = true
                return
            }
            widthOnly = true
            textWidth = min(
                max(start * Double(axisX), CanvasScaleSession.minBox),
                CanvasScaleSession.maxBox)
            // The measured box includes backdrop padding and outline
            // overshoot, so the pivot cannot be held exactly; the centre stays
            // put and the text grows both ways.
            offset = .zero
            didMove = true
            return
        }
        apply(fx: fx, fy: fy, pivot: pivot, centre: centre)
        didMove = true
    }

    /// Holds `pivot` still while the box scales by `(fx, fy)`: the centre
    /// moves in the layer's own space, and that displacement is rotated back
    /// into canvas space to become the clip's new `(x, y)`.
    private mutating func apply(fx: CGFloat, fy: CGFloat, pivot: CGPoint, centre: CGPoint) {
        let moved = CGPoint(
            x: pivot.x + (centre.x - pivot.x) * fx,
            y: pivot.y + (centre.y - pivot.y) * fy)
        offset = canvasRotate(
            CGVector(dx: moved.x - centre.x, dy: moved.y - centre.y), degrees: rotation)
    }

    private func unrotatedPoint(_ point: CGPoint, about centre: CGPoint) -> CGPoint {
        let v = canvasUnrotate(
            CGVector(dx: point.x - centre.x, dy: point.y - centre.y), degrees: rotation)
        return CGPoint(x: centre.x + v.dx, y: centre.y + v.dy)
    }
}

// MARK: - Rotate

/// The grip above the top edge (spec §4.2). ⇧ snaps to 15°.
struct CanvasRotateSession {
    let clip: UInt32
    let base: VideoProps
    /// The rotation centre, canvas space — `canvasAnchor`, never the cropped
    /// rectangle's middle.
    let anchor: CGPoint
    /// The pointer's angle at mouse-down, radians.
    let grabAngle: Double

    var rotation: Double
    var didMove = false

    static let snapDegrees = 15.0

    var op: ReelOp {
        .setVideo(clips: [clip], patch: VideoPatch(rotation: canvasRound(rotation)))
    }

    mutating func update(point: CGPoint, snapping: Bool) {
        let angle = atan2(Double(point.y - anchor.y), Double(point.x - anchor.x))
        var degrees = base.rotation + (angle - grabAngle) * 180 / .pi
        if snapping {
            degrees = (degrees / CanvasRotateSession.snapDegrees).rounded()
                * CanvasRotateSession.snapDegrees
        }
        // Kept in (-180, 180] so the inspector never shows 4 000°.
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees > 180 { degrees -= 360 }
        if degrees <= -180 { degrees += 360 }
        rotation = degrees
        didMove = true
    }

    /// The angle a press at `point` makes about `anchor` — what a session is
    /// constructed with so the grip does not jump to the pointer.
    static func angle(of point: CGPoint, about anchor: CGPoint) -> Double {
        atan2(Double(point.y - anchor.y), Double(point.x - anchor.x))
    }
}

// MARK: - Crop

/// Crop mode's handles (spec §4.2): the same eight positions, but each one
/// drives a crop inset in SOURCE pixels instead of the layer's size.
///
/// Cropping never shifts content (§5.3), so this session writes `crop` and
/// nothing else — no compensating `x`/`y`, ever.
struct CanvasCropSession {
    let clip: UInt32
    let handle: CanvasHandle
    let base: VideoProps
    let sourceSize: CGSize
    /// The uncropped rectangle at mouse-down, un-rotated, canvas space.
    let startRect: CGRect
    let rotation: Double

    var crop: CropInsets
    var didMove = false

    /// A crop may never close a rectangle completely; one source pixel is the
    /// floor, which is also what the core enforces.
    static let minRemaining = 1.0

    var op: ReelOp { .setVideo(clips: [clip], patch: VideoPatch(crop: crop)) }

    mutating func update(point: CGPoint) {
        let centre = CGPoint(x: startRect.midX, y: startRect.midY)
        let v = canvasUnrotate(
            CGVector(dx: point.x - centre.x, dy: point.y - centre.y), degrees: rotation)
        let local = CGPoint(x: centre.x + v.dx, y: centre.y + v.dy)
        let scale = base.scale > 0 ? base.scale : 1
        // Source pixels from the uncropped rectangle's top-left corner.
        let sx = Double(local.x - startRect.minX) / scale
        let sy = Double(local.y - startRect.minY) / scale

        var l = crop.l
        var t = crop.t
        var r = crop.r
        var b = crop.b
        let limit = CanvasCropSession.minRemaining
        if handle.unit.x < 0 { l = min(max(sx, 0), max(sourceSize.width - r - limit, 0)) }
        if handle.unit.x > 0 {
            r = min(max(sourceSize.width - sx, 0), max(sourceSize.width - l - limit, 0))
        }
        if handle.unit.y < 0 { t = min(max(sy, 0), max(sourceSize.height - b - limit, 0)) }
        if handle.unit.y > 0 {
            b = min(max(sourceSize.height - sy, 0), max(sourceSize.height - t - limit, 0))
        }
        crop = CropInsets(
            l: canvasRound(l), t: canvasRound(t), r: canvasRound(r), b: canvasRound(b))
        didMove = true
    }
}

// MARK: - Shape endpoints

/// Dragging a `line` or `arrow` end (spec §4.2). The model stores them as
/// unit coordinates in the shape's box, so the box itself never changes.
struct CanvasEndpointSession {
    let clip: UInt32
    let endpoint: CanvasEndpoint
    var unit: CGPoint
    var didMove = false

    var op: ReelOp {
        let values = [canvasRound(unit.x), canvasRound(unit.y)]
        switch endpoint {
        case .from: return .setShape(clips: [clip], patch: ShapePatch(from: values))
        case .to: return .setShape(clips: [clip], patch: ShapePatch(to: values))
        }
    }

    /// `unit` comes from `CanvasLayerBox.endpointUnit`, which owns the
    /// rotation and the box maths.
    mutating func update(unit: CGPoint) {
        self.unit = unit
        didMove = true
    }
}

// MARK: - Pan

/// Space-drag panning when the canvas is larger than the pane (spec §4.2).
/// Pure view state: it never reaches the document.
struct CanvasPanSession {
    /// Pointer at mouse-down, VIEW points — the one session that works in
    /// points, because panning is a property of the viewport and not of the
    /// canvas.
    let origin: CGPoint
    let base: CGPoint
    var offset: CGPoint

    mutating func update(point: CGPoint) {
        offset = CGPoint(x: base.x + (point.x - origin.x), y: base.y + (point.y - origin.y))
    }
}
