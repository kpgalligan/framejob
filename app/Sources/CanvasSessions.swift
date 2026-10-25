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
/// angle reads CLOCKWISE on screen — the same sense the canvas's hit boxes
/// (`CanvasLayerBox`) un-rotate by, which is what keeps overlay hit-testing
/// and the compositor's picture the same answer.
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
/// the target's props instead (`CanvasEditTarget`: the base, or the selected
/// action's end state), never the playhead's interpolated value.
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
        canvasRect(of: clip, in: canvas, sourceSize: sourceSize, video: video.uncropped)
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

    // MARK: The region frame

    /// A canvas point as SOURCE pixels measured from the centre of the
    /// layer's CROPPED rect — the frame `video.spotlight`, `video.obscure`
    /// and `add_zoom_action`'s region all speak (`model_regions.rs`'s
    /// `Spotlight`, and `Compositor.metal`'s
    /// `centre = cropped * 0.5 + float2(spotX, spotY)`). Spec §5.3 calls it Q.
    ///
    /// **It reads the EVALUATED props, and that is the opposite of every
    /// gesture session in this file.** Move, Scale, Rotate and Crop all
    /// capture the target's props at mouse-down (`CanvasEditTarget.start`),
    /// because the op merges into them and a clip inside an action must not
    /// be baked to its animated value. A region is measured the other way round: the
    /// user drags over what is ON SCREEN, and a source-pixel answer is
    /// transform-invariant only if the un-transform matches the transform
    /// that drew it. `video` here IS the recipe's evaluated state, so a clip
    /// already inside an action scaling it 2× yields the region the user
    /// drew rather than half of it — and it agrees by construction with
    /// `edit_zoom.rs`, which reads the clip evaluated at the action's start.
    /// The two readings differ only once a clip has actions, which is
    /// exactly when a zoom action is being added to it.
    func sourcePoint(_ point: CGPoint) -> CGPoint {
        let local = unrotated(point)
        let box = rect
        let s = video.scale > 0 ? video.scale : 1
        return CGPoint(x: (local.x - box.midX) / s, y: (local.y - box.midY) / s)
    }

    /// The inverse of `sourcePoint`: a point in the layer's own source-pixel
    /// frame, back on the canvas — what draws a stored region where its
    /// pixels are.
    func canvasPoint(source point: CGPoint) -> CGPoint {
        let box = rect
        let s = video.scale > 0 ? video.scale : 1
        return rotated(CGPoint(x: box.midX + point.x * s, y: box.midY + point.y * s))
    }

    /// A rectangle in the source-pixel frame as its four canvas-space
    /// corners, TL TR BR BL — `corners(of:)`'s twin, for the one shape that
    /// is axis-aligned in the LAYER's axes rather than in the canvas's.
    func canvasQuad(ofSource box: CGRect) -> [CGPoint] {
        [
            canvasPoint(source: CGPoint(x: box.minX, y: box.minY)),
            canvasPoint(source: CGPoint(x: box.maxX, y: box.minY)),
            canvasPoint(source: CGPoint(x: box.maxX, y: box.maxY)),
            canvasPoint(source: CGPoint(x: box.minX, y: box.maxY)),
        ]
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

/// A colour as `video.chroma.key`: exactly three components, clamped to 0…1.
///
/// That key is the ONE colour in the schema the model spells without an alpha
/// (`[f64; 3]` in `model.rs`, and `props_check.rs` bounds each channel), so a
/// four-component `RGBA` — which is what a colour well hands back, and what
/// the comparison in `changedRGBA` needs — has to be cut back to three before
/// it can reach `set_video`. A longer array is not a warning there: serde
/// answers `invalid length 4, expected an array of length 3` and the whole
/// edit fails.
func chromaKeyComponents(_ color: RGBA) -> [Double] {
    (0..<3).map { index in
        let value = index < color.count ? color[index] : 0
        return canvasRound(min(max(value, 0), 1))
    }
}

// MARK: - Move

/// Dragging inside the box to move the selection (spec §4.2). Every selected
/// clip moves by the same canvas-space delta; the anchor clip's rectangle is
/// what snapping tests, so the whole selection clicks into place together.
///
/// The op writes the target's props plus the delta (the base, or the selected
/// action's end state — CI-13), never the evaluated position at the playhead.
struct CanvasMoveSession {
    /// The target's `(x, y)` per clip, captured at mouse-down.
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

    /// One op per clip, routed by `target`: each keeps its own position, so
    /// a multi-clip move cannot collapse the selection onto one point.
    func ops(to target: CanvasEditTarget) -> [ReelOp] {
        bases.keys.sorted().compactMap { id in
            guard let base = bases[id] else { return nil }
            return target.op(
                video: VideoPatch(
                    x: canvasRound(base.x + delta.dx), y: canvasRound(base.y + delta.dy)),
                clip: id)
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
    /// The target's video props at mouse-down (`CanvasEditTarget.start`).
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

    func ops(to edit: CanvasEditTarget) -> [ReelOp] {
        let placement = VideoPatch(
            x: canvasRound(base.x + offset.dx), y: canvasRound(base.y + offset.dy))
        var uniform = placement
        uniform.scale = canvasRound(scale)
        switch target {
        case .uniform:
            return [edit.op(video: uniform, clip: clip)]
        case .box:
            // Base whatever `edit` says (CI-13): `set_shape` has no action
            // form, and the placement that pins the pivot travels with it.
            return [
                .setShape(
                    clips: [clip],
                    patch: ShapePatch(
                        width: canvasRound(boxSize.width), height: canvasRound(boxSize.height))),
                .setVideo(clips: [clip], patch: placement),
            ]
        case .textWidth:
            guard widthOnly else { return [edit.op(video: uniform, clip: clip)] }
            return [edit.op(text: TextPatch(width: .some(canvasRound(textWidth))), clip: clip)]
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

    func op(to target: CanvasEditTarget) -> ReelOp {
        target.op(video: VideoPatch(rotation: canvasRound(rotation)), clip: clip)
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

    func op(to target: CanvasEditTarget) -> ReelOp {
        target.op(video: VideoPatch(crop: crop), clip: clip)
    }

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

// MARK: - Chroma-key eyedropper

/// Picking the chroma key colour off the canvas (spec §4.3's "key color with
/// a canvas eyedropper"). One click, not a drag — and a session all the same,
/// because the sample cannot be taken while that click is being handled.
///
/// The preview's pixels belong to the Metal compositor, not to any view, so
/// the honest way to read one is to compose the frame again offline
/// (`Exporter.renderFrame` — the same `AVComposition` the export writes from,
/// so the pixel picked is the pixel the file would hold). That render opens
/// asset tracks and decodes, which has to happen off the main thread, and by
/// the time it lands the selection may have moved. Everything the click meant
/// is therefore captured here first: `EditorViewController+Eyedropper.swift`
/// runs it and compares this against the selection before it commits.
struct CanvasEyedropperSession {
    /// The clips the pick will key — the Video pane's video clips, in the
    /// order it offers them.
    let clips: [UInt32]
    /// The chroma those clips already carry, so a re-pick replaces the colour
    /// and keeps the tolerances the user dialled in.
    let base: ChromaProps?

    /// The op that makes the frame this samples FROM. Applied to a COPY of
    /// the project — pure, never published, never on the undo stack, the way
    /// `EditorViewController+Inspector`'s probe is (§5.5).
    ///
    /// It removes the three things standing between the pixel on screen and
    /// the number `Compositor.metal` actually compares against the key:
    ///
    ///  - the clip's own chroma, because a keyed pixel is a HOLE — the most
    ///    natural pick of all, "the green I can still see", would otherwise
    ///    sample whatever shows through it;
    ///  - its colour adjustment, tone, wheels, curves and look (GR-2, GR-11, GR-12, GR-7), as
    ///    the shader keys BEFORE them (§7.5's order of operations), so the adjusted pixel
    ///    is not the one being compared;
    ///  - its opacity, because a faded layer's pixel on screen is already
    ///    mixed with whatever lies behind it.
    ///
    /// What is left is a layer drawn exactly as the key sees it. A layer
    /// COVERED by another one is still covered — the pick is what is visible
    /// at that point, which is what a user aiming at it means.
    var suppression: ReelOp {
        .setVideo(clips: clips, patch: VideoPatch(
            opacity: 1, color: ColorPatch(.identity), chroma: .some(nil),
            look: .some(nil), wheels: .neutral, curves: .reset))
    }

    /// The sampled colour as the props to write. A first pick keeps
    /// `Chroma::default`'s tolerances (0.2 / 0.1 / 0.5, `model.rs`), which is
    /// also what the section's on-switch writes.
    func chroma(picked color: RGBA) -> ChromaProps {
        let previous = base ?? ChromaProps()
        return ChromaProps(
            key: chromaKeyComponents(color), tolerance: previous.tolerance,
            softness: previous.softness, spill: previous.spill)
    }

    /// The colour of the canvas pixel at `point` in a frame composed from
    /// `canvas`, or nil when there is nothing there to pick.
    ///
    /// **The rendered frame is not the canvas.** Its size is whatever the
    /// composition asked for, so a canvas coordinate indexes it as a
    /// FRACTION and never as a pixel number; get that wrong and a project
    /// whose plan was built for another canvas size picks the wrong colour
    /// silently. Its rows do run top-down, which is the same sense canvas
    /// space does, so no flip belongs here.
    ///
    /// The readback is sRGB. The shader compares the values the decoder
    /// handed it, so a wide-gamut source can put a pick a per cent or two
    /// off the number the key needs — which is what `tolerance` is for, and
    /// why the pick sets a colour rather than a threshold.
    static func color(at point: CGPoint, in frame: CGImage, canvas: CanvasSnapshot) -> RGBA? {
        let size = canvas.size
        guard size.width >= 1, size.height >= 1, frame.width >= 1, frame.height >= 1 else {
            return nil
        }
        let column = Int((point.x / size.width * CGFloat(frame.width)).rounded(.down))
        let row = Int((point.y / size.height * CGFloat(frame.height)).rounded(.down))
        guard column >= 0, row >= 0, column < frame.width, row < frame.height else { return nil }
        guard let pixel = frame.cropping(to: CGRect(x: column, y: row, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                      data: base, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        let alpha = Double(bytes[3]) / 255
        // Nothing on the canvas there. Refused rather than picked: a
        // transparent pixel un-premultiplies to black, and keying black is
        // never what a click on empty canvas meant.
        guard alpha > 0 else { return nil }
        return (0..<3).map { min(Double(bytes[$0]) / 255 / alpha, 1) }
    }
}

// MARK: - Region drags

/// What a region dragged on the canvas is FOR (spec §4.2's region mode).
///
/// One rubber band serves two commits — `add_zoom_action`'s `region` and a
/// `video.obscure` entry — because they are the same rectangle in the same
/// frame, spec §5.3's Q. A second overlay with a second copy of the maths is
/// precisely the drift this file exists to prevent, so the purpose travels
/// with the session and `EditorViewController+ZoomRegion.swift` branches on
/// it in exactly one place: the commit. The geometry below reads it only to
/// say whether the resolved frame is worth drawing.
enum CanvasRegionPurpose {
    /// `Z`, and the action lane's Zoom to Region button.
    case zoom
    /// The Obscure section's "Place on Canvas".
    case obscure
}

/// A rectangle dragged over the picture: the region a zoom action lands on,
/// or one `video.obscure` entry (spec §4.2, §4.3).
///
/// Both ends are held in CANVAS pixels — the space this whole file speaks —
/// and turned into source pixels only through the layer's box, so a rotated
/// or a cropped clip needs no special case here. The band itself drags FREE:
/// constraining it to the canvas's aspect would make `fill` unreachable from
/// the canvas, since a band that already has the canvas's shape fits and
/// fills identically. What keeps that honest is the resolved frame — the
/// rectangle that will actually be on screen when the zoom lands — which the
/// mode strokes beside the band while the drag is live, the same instinct as
/// the crop ghost.
struct ZoomRegionSession {
    let purpose: CanvasRegionPurpose
    /// The clip the region belongs to. The mode is armed for exactly one.
    let clip: UInt32
    /// Where the press landed, canvas pixels.
    let anchor: CGPoint
    var current: CGPoint
    /// ⇧ held during a ZOOM drag: the region covers the canvas rather than
    /// sitting inside it. It means nothing to an obscure region, which is
    /// the rectangle it is drawn as.
    var fill = false
    /// False until the pointer actually leaves the press point — a click
    /// that drew no rectangle must commit nothing, the `didMove` flag every
    /// session here carries.
    var didMove = false

    /// The smallest band that counts, in CANVAS pixels. A press with a
    /// twitch in it would otherwise ask the core to zoom to a region a
    /// fraction of a pixel wide, which is an `Err` naming `region.width`
    /// rather than the "nothing happened" it looks like.
    static let minBand: CGFloat = 6

    /// The dragged rectangle in canvas pixels, however the two corners lie.
    var canvasRect: CGRect {
        CGRect(
            x: min(anchor.x, current.x), y: min(anchor.y, current.y),
            width: abs(current.x - anchor.x), height: abs(current.y - anchor.y))
    }

    /// The flag is raised by MOVEMENT, not by the call: `mouseUp` runs this
    /// once more with the release point so the band ends where the pointer
    /// did, and a press-and-release that never moved must still read as the
    /// click it was.
    mutating func update(point: CGPoint, fill: Bool) {
        current = point
        self.fill = fill
        if point != anchor { didMove = true }
    }

    /// The band as a rectangle in the layer's own source-pixel frame — the
    /// min corner and the size, which `region(in:)` turns into the centre
    /// and size the op wants. Nil when the drag is too small to mean
    /// anything.
    ///
    /// All FOUR corners of the band are taken through `sourcePoint`, not the
    /// two the drag names: the band is axis-aligned in CANVAS space, so on a
    /// rotated layer its bounding box in Q is spanned by the other diagonal
    /// as much as by this one. At zero rotation the four collapse to the two
    /// and this is the rectangle that was dragged.
    func sourceRect(in box: CanvasLayerBox) -> CGRect? {
        let band = canvasRect
        guard didMove, band.width >= Self.minBand, band.height >= Self.minBand else { return nil }
        let corners = [
            CGPoint(x: band.minX, y: band.minY), CGPoint(x: band.maxX, y: band.minY),
            CGPoint(x: band.maxX, y: band.maxY), CGPoint(x: band.minX, y: band.maxY),
        ].map { box.sourcePoint($0) }
        guard let first = corners.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in corners.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    /// The band as the op's region: the CENTRE and the size, in source
    /// pixels from the cropped rect's centre. Rounded the way every canvas
    /// gesture rounds what it writes.
    ///
    /// `ZoomRegion` is `add_zoom_action`'s argument type
    /// (`ReelCore.swift`), and it is what an `ObscureProps` is built from
    /// too: the two commits differ in where the four numbers go, never in
    /// what they mean. The centre is taken before the rounding rather than
    /// after, so a band rounded to whole pixels cannot drift half a pixel
    /// off the rectangle that was drawn.
    func region(in box: CanvasLayerBox) -> ZoomRegion? {
        guard let rect = sourceRect(in: box) else { return nil }
        return ZoomRegion(
            x: canvasRound(rect.midX), y: canvasRound(rect.midY),
            width: canvasRound(rect.width), height: canvasRound(rect.height))
    }

    /// The scale `add_zoom_action` will resolve for this band — `k = |cos θ|`,
    /// `m = |sin θ|`, and the two formulas `edit_zoom.rs`'s module doc
    /// derives, clamped into the layer's legal range exactly as the core
    /// clamps before it computes the offsets.
    ///
    /// **This is a PREVIEW, and the core remains the authority.** Nothing is
    /// written from it: the op recomputes the same number from the same
    /// region, so the picture the band promises is the picture the op
    /// produces. It is repeated here for one reason — a `fit`/`fill`
    /// argument only means something if the band can differ from the result,
    /// and the only way to show that difference is to draw it. If the two
    /// ever disagree, `edit_zoom.rs` is right and this is the copy to fix.
    func resolvedScale(in box: CanvasLayerBox, source: CGRect) -> Double {
        let canvas = box.canvas.size
        let radians = box.rotation * .pi / 180
        let k = abs(cos(radians))
        let m = abs(sin(radians))
        let width = Double(canvas.width)
        let height = Double(canvas.height)
        let rw = Double(source.width)
        let rh = Double(source.height)
        let scale: Double
        if fill {
            scale = max((width * k + height * m) / rw, (width * m + height * k) / rh)
        } else {
            scale = min(width / (rw * k + rh * m), height / (rw * m + rh * k))
        }
        return min(max(scale, CanvasScaleSession.minScale), CanvasScaleSession.maxScale)
    }

    /// What the canvas will actually SHOW once the zoom lands, drawn in
    /// today's canvas space.
    ///
    /// The derivation is two lines. After the zoom a point `q` sits at
    /// `(W/2, H/2) + s′·R(θ)·(q − q_c)`, so the `q` still on screen are
    /// `q_c + R(−θ)·u/s′` for `u` in the canvas box. Today that same set
    /// draws at `canvasPoint(q_c) + (s/s′)·u`, because the two rotations
    /// cancel: a zoom changes the layer's scale and position, never its
    /// angle, so the rectangle is AXIS-ALIGNED in canvas space however the
    /// layer is turned. It is centred on the region's centre and measures
    /// `(s/s′)` of the canvas. For `fit` it is the smallest canvas-shaped
    /// rectangle containing the region, and it touches it on one axis; for
    /// `fill` it sits inside it. When the scale had to be clamped it grows,
    /// which is the honest picture of a region too small to reach.
    func frameRect(in box: CanvasLayerBox, source: CGRect) -> CGRect? {
        guard purpose == .zoom else { return nil }
        let resolved = resolvedScale(in: box, source: source)
        let scale = box.video.scale > 0 ? box.video.scale : 1
        guard resolved > 0 else { return nil }
        let factor = CGFloat(scale / resolved)
        let size = box.canvas.size
        let centre = box.canvasPoint(source: CGPoint(x: source.midX, y: source.midY))
        let width = size.width * factor
        let height = size.height * factor
        return CGRect(
            x: centre.x - width / 2, y: centre.y - height / 2, width: width, height: height)
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
