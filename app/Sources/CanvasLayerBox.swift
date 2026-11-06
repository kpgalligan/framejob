import AppKit

// MARK: - A layer's box on the canvas

/// Where one layer inside a nest clip draws, in canvas space: what a press on
/// a nest box is tested against, since a nest's rectangle (a whole canvas,
/// after ⌘G) can hold far less picture than it covers.
struct CanvasLayerPicture {
    let rect: CGRect
    let anchor: CGPoint
    let rotation: Double

    func contains(_ point: CGPoint) -> Bool {
        let v = canvasUnrotate(
            CGVector(dx: point.x - anchor.x, dy: point.y - anchor.y), degrees: rotation)
        return rect.contains(CGPoint(x: anchor.x + v.dx, y: anchor.y + v.dy))
    }
}

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
    /// A nest clip's pictures on this frame; nil on every other box, which
    /// hits on `rect` alone.
    var picture: [CanvasLayerPicture]? = nil

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

    /// Hit test in canvas space, rotation included. A nest is hit on the
    /// pictures inside its rectangle, so a press where it draws nothing
    /// reaches what is behind it (spec §4.2's "topmost visible clip").
    func contains(_ point: CGPoint) -> Bool {
        guard rect.contains(unrotated(point)) else { return false }
        guard let picture else { return true }
        return picture.contains { $0.contains(point) }
    }

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
    /// the order the canvas hit-tests in. The layers out of one nest clip
    /// make ONE box, at the first one's slot: a nest clip is one clip.
    static func boxes(recipe: FrameRecipe, snapshot: ProjectSnapshot) -> [CanvasLayerBox] {
        var nests = Set<UInt32>()
        return recipe.layers.compactMap { layer in
            if let nest = layer.nest {
                guard nests.insert(nest.clip).inserted else { return nil }
                return nestBox(nest, recipe: recipe, snapshot: snapshot)
            }
            guard let clip = snapshot.clip(layer.clip) else { return nil }
            guard let size = LayerRenderers.measuredSize(for: layer)
                ?? snapshot.sourceSize(of: clip), size.width > 0, size.height > 0
            else { return nil }
            return CanvasLayerBox(
                clip: clip, canvas: snapshot.canvas, video: layer.videoProps, sourceSize: size,
                locked: snapshot.track(clip.track)?.locked ?? false)
        }
    }

    /// A nest clip's box: its own rectangle, at the placement the core entered
    /// it with, and the pictures of its layers on this frame. `canvasRect` and
    /// `canvasAnchor` read no field of the `clip` they are given, so the nest's
    /// clip serves for a layer's folded props.
    private static func nestBox(
        _ nest: RecipeNest, recipe: FrameRecipe, snapshot: ProjectSnapshot
    ) -> CanvasLayerBox? {
        guard let clip = snapshot.clip(nest.clip), let size = snapshot.sourceSize(of: clip),
              size.width > 0, size.height > 0
        else { return nil }
        var video = clip.videoProps
        video.x = nest.x
        video.y = nest.y
        video.scale = nest.scale
        video.rotation = nest.rotation
        video.crop = nest.crop
        let pictures = recipe.layers.filter { $0.nest?.clip == nest.clip }.compactMap {
            layer -> CanvasLayerPicture? in
            guard let drawn = LayerRenderers.measuredSize(for: layer),
                  drawn.width > 0, drawn.height > 0
            else { return nil }
            let props = layer.videoProps
            return CanvasLayerPicture(
                rect: canvasRect(of: clip, in: snapshot.canvas, sourceSize: drawn, video: props),
                anchor: canvasAnchor(of: clip, in: snapshot.canvas, video: props),
                rotation: props.rotation)
        }
        return CanvasLayerBox(
            clip: clip, canvas: snapshot.canvas, video: video, sourceSize: size,
            locked: snapshot.track(clip.track)?.locked ?? false, picture: pictures)
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
