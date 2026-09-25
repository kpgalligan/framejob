import AppKit
import ImageIO
import Metal
import UniformTypeIdentifiers

/// The platform half of "text and shapes are described, not rasterized"
/// (§11): a recipe carries the DESCRIPTION, and this turns it into pixels —
/// Core Text for text, Core Graphics for shapes, ImageIO for stills — and
/// hands the compositor a premultiplied BGRA `MTLTexture`.
///
/// Premultiplied is not a detail: `Compositor.metal` blends source-over with
/// `(one, one_minus_source_alpha)` and un-premultiplies these textures before
/// applying the colour controls, so a straight-alpha texture would render
/// with dark fringes around every glyph. `CGImageAlphaInfo.premultipliedFirst`
/// plus `byteOrder32Little` IS BGRA-premultiplied; nothing else here is
/// allowed to produce a texture.
///
/// Everything is cached by the recipe's stable hash (§7.3), 64 entries LRU
/// (§7.5) — except a graphic's texture, keyed by its SVG in a small pool of
/// its own (`graphicCacheLimit`). One instance per `Compositor`, called from
/// its render queue; the measured-size and laid-out-text caches are static
/// and shared, because the canvas overlay on the main thread needs the same
/// numbers to draw handles.
///
/// **Text lives in `LayerRenderersText.swift`** — measuring, laying out and
/// the three reveals — which is the size payment road map 2's phase 6 made
/// before it added gradients. What stays here is the cache, the three entry
/// points, shapes, images and the bitmap/texture pair; the file's own doc
/// argues the seam and names the three members that widened for it.
///
/// The cache key is the RECIPE's hash and never anything this file assembles,
/// and phase 6 is the second feature to depend on that. `recipe.rs`'s
/// `Source::Shape` arm hashes the serialized shape description WHOLE, so a
/// gradient enters the key the moment the field exists — where phase 4 had to
/// fold a computed reveal into the text hash by hand. A key that misses a
/// change renders correctly in a single `render_frame` and then FREEZES
/// during playback, which is the failure to remember before appending
/// anything to a key here or narrowing one.
final class LayerRenderers {

    /// Textures kept before the least recently used one is dropped (§7.5).
    static let cacheLimit = 64
    /// Graphic textures kept, in a least-recently-used pool of their OWN. An
    /// animated graphic's SVG differs every frame, so playback mints a new
    /// full-layer texture per frame (~8 MB at 1080p, ~33 MB at 4K) that is
    /// almost never hit again. In the shared pool 64 of them would evict
    /// every text and shape texture and hold ~2 GB at 4K; here a held or
    /// static graphic still hits and an animating one holds at most this.
    static let graphicCacheLimit = 6
    /// Widest texture rendered. Beyond this a description is refused rather
    /// than clamped — a 40 000 pt font is a typo, not a request.
    static let maxTextureSide = 8192

    let device: MTLDevice
    private let lock = NSLock()
    private var layers = Pool(limit: LayerRenderers.cacheLimit)
    private var graphics = Pool(limit: LayerRenderers.graphicCacheLimit)

    /// A cached rasterization: the texture plus the SOURCE SIZE it was drawn
    /// at, which is what §5.3 placement uses for this layer.
    struct Rendered {
        let texture: MTLTexture
        let size: CGSize
    }

    init(device: MTLDevice) {
        self.device = device
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("LayerRenderers does not support NSCoder")
    }

    // MARK: - Cache

    /// Looks a hash up and renders it with `make` on a miss. The render
    /// happens OUTSIDE the lock: rasterizing a paragraph of text takes
    /// milliseconds and the canvas overlay must not block on it. Two threads
    /// racing on the same miss render twice and the second store wins, which
    /// is cheaper than holding the lock across Core Text.
    /// `graphic` picks the graphics' own pool (`graphicCacheLimit`).
    func cached(_ key: String, graphic: Bool = false, _ make: () -> Rendered?) -> Rendered? {
        lock.lock()
        let hit = graphic ? graphics.hit(key) : layers.hit(key)
        lock.unlock()
        if let hit = hit { return hit }

        guard let rendered = make() else { return nil }
        lock.lock()
        if graphic { graphics.store(key, rendered) } else { layers.store(key, rendered) }
        lock.unlock()
        return rendered
    }

    /// One least-recently-used pool of textures. Call with the lock held.
    private struct Pool {
        let limit: Int
        var entries: [String: Rendered] = [:]
        /// Least recently used first.
        var order: [String] = []

        init(limit: Int) { self.limit = limit }

        mutating func hit(_ key: String) -> Rendered? {
            guard let hit = entries[key] else { return nil }
            touch(key)
            return hit
        }

        mutating func store(_ key: String, _ rendered: Rendered) {
            entries[key] = rendered
            touch(key)
            while order.count > limit, let oldest = order.first {
                order.removeFirst()
                entries.removeValue(forKey: oldest)
            }
        }

        /// Moves `key` to the most-recent end.
        private mutating func touch(_ key: String) {
            if let index = order.firstIndex(of: key) { order.remove(at: index) }
            order.append(key)
        }
    }

    /// Drops every texture. Called when the render context changes size —
    /// the textures themselves are resolution-independent, but a canvas
    /// resize invalidates nothing else and this keeps memory honest.
    func purge() {
        lock.lock()
        layers = Pool(limit: LayerRenderers.cacheLimit)
        graphics = Pool(limit: LayerRenderers.graphicCacheLimit)
        lock.unlock()
    }

    // MARK: - Public rendering

    /// The texture for a `text` recipe layer, cached by the recipe's hash.
    /// The size returned is the MEASURED layout size — the number the model
    /// deliberately does not store (§5.3, §11).
    ///
    /// The key is the core's hash and nothing else. That hash ALREADY covers
    /// the reveal (`recipe.rs`'s `text_hash` folds the amount, the phase and
    /// the kind into it), so appending the amount here would put one rule in
    /// two languages, and leaving the reveal out of the key would hand the
    /// second frame of an animation the first frame's texture — a reveal that
    /// works in a single `render_frame` and freezes during playback.
    func text(_ props: TextProps, hash: String, reveal: RecipeReveal) -> Rendered? {
        // The closure is NON-escaping (`cached` calls it and returns), so a
        // strong capture here cannot make a cycle.
        cached("text:" + hash) { self.renderText(props, reveal: reveal) }
    }

    /// The texture for a `shape` recipe layer. Drawn at EXACTLY the box size
    /// the model stores, with the stroke inset by half its width, so the
    /// texture's size and the recipe's `source_size` agree — if they did not,
    /// every hit-test and handle would be off by the stroke.
    func shape(_ props: ShapeProps, hash: String) -> Rendered? {
        cached("shape:" + hash) { self.renderShape(props) }
    }

    /// The texture for an `image` recipe layer, decoded with ImageIO and
    /// cached by path. Bounded by `maxTextureSide`: a 60-megapixel HEIC is
    /// scaled down once here rather than on every frame.
    func image(url: URL, media: UInt32) -> Rendered? {
        cached("image:\(media):" + url.path) {
            guard let image = MediaImporter.decodeImage(
                url, maxPixelSize: LayerRenderers.maxTextureSide)
            else { return nil }
            return self.renderImage(image)
        }
    }

    // MARK: - Measured layers

    /// The source size of ANY recipe layer: measured for text, the stored
    /// box for a shape, the media size otherwise. This is the closure
    /// `FrameRecipe.layer(at:measuring:)` wants, so the canvas overlay
    /// hit-tests exactly what the compositor drew.
    static func measuredSize(for layer: RecipeLayer) -> CGSize? {
        switch layer.source {
        // The REVEAL is deliberately ignored: the overlay's handles sit on
        // the full text's box, whatever is showing of it at this instant.
        case .text(_, let props, _): return measuredSize(for: props)
        case .shape(_, let props): return layer.sourceSizeCG ?? props.boxSize
        case .track, .image, .graphic, .missing: return layer.sourceSizeCG
        }
    }

    // MARK: - Rasterizing

    /// A shape description drawn into its own box.
    ///
    /// Since format version 6 the area kinds may carry a GRADIENT instead of
    /// a flat fill (§5.2's `shape.gradient`). It takes precedence over `fill`
    /// and does not clear it, so the model keeps the colour underneath and
    /// `{"gradient": null}` is an exact inverse; `line` and `arrow` ignore it
    /// altogether — `drawLine` below is not even told about it — which is
    /// `radius`'s precedent, stored on every kind and read only by the
    /// rectangle arm.
    private func renderShape(_ props: ShapeProps) -> Rendered? {
        let size = CGSize(
            width: min(CGFloat(LayerRenderers.maxTextureSide), max(1, CGFloat(props.width).rounded(.up))),
            height: min(CGFloat(LayerRenderers.maxTextureSide), max(1, CGFloat(props.height).rounded(.up))))
        guard let context = LayerRenderers.bitmap(size) else { return nil }
        let strokeWidth = props.stroke.map { max(0, CGFloat($0.width)) } ?? 0
        // Inset by half the stroke so it lands INSIDE the box: the box is the
        // layer's source size and growing the texture would move the layer.
        let rect = CGRect(origin: .zero, size: size).insetBy(
            dx: strokeWidth / 2, dy: strokeWidth / 2)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if let stroke = props.stroke { context.setStrokeColor(stroke.color.nsColor.cgColor) }
        if let fill = props.fill { context.setFillColor(fill.nsColor.cgColor) }

        switch props.kind {
        case .rectangle:
            let radius = min(CGFloat(props.radius), min(rect.width, rect.height) / 2)
            let path = CGPath(
                roundedRect: rect, cornerWidth: max(0, radius), cornerHeight: max(0, radius),
                transform: nil)
            draw(path, in: context, props: props, box: rect, strokeWidth: strokeWidth)
        case .ellipse:
            draw(CGPath(ellipseIn: rect, transform: nil), in: context, props: props,
                box: rect, strokeWidth: strokeWidth)
        case .line, .arrow:
            drawLine(props, in: context, size: size, strokeWidth: strokeWidth)
        }
        return upload(context, size: size)
    }

    /// One area shape: the interior, then the outline.
    ///
    /// The interior is the gradient when the description carries one and the
    /// flat `fill` otherwise — the precedence rule, in the one place that
    /// draws. The STROKE is untouched by it and keeps `stroke.color`: a
    /// gradient describes an area, and a gradient stroke would need a second
    /// stop list nobody has asked for.
    private func draw(
        _ path: CGPath, in context: CGContext, props: ShapeProps, box: CGRect,
        strokeWidth: CGFloat
    ) {
        let painted =
            props.gradient.map { LayerRenderers.paint($0, path: path, box: box, in: context) }
            ?? false
        if !painted, props.fill != nil {
            context.addPath(path)
            context.fillPath()
        }
        if props.stroke != nil, strokeWidth > 0 {
            context.addPath(path)
            context.strokePath()
        }
    }

    /// The `CGGradient` a stop list describes, in the bitmap's own sRGB
    /// space, or nil when there is nothing to ramp between.
    ///
    /// **The stops are SORTED here**, which reads as defensive noise until
    /// you know the core deliberately does not police the order.
    /// `CGGradient` leaves an unsorted `locations` array undefined, so the
    /// obvious home for the requirement is a refusal in `props_check.rs` —
    /// and that refusal has a failure mode nobody would accept: dragging one
    /// stop past another is how a gradient is edited, and the drag would stop
    /// working half way through. The core says so where the check would have
    /// gone, and the sort lands here, at the one call that needs it.
    /// `sortedStops` is stable, so two stops at one position keep the order
    /// they were written in and the picture does not flip mid-drag.
    ///
    /// Fewer than two stops is refused by the core and answered nil here, so
    /// a hand-written file that got one past falls back to the flat `fill`
    /// rather than drawing nothing.
    ///
    /// One measured thing to know before reading a pixel off one of these:
    /// `CGGradient` is sampled at pixel CENTRES and interpolated through a
    /// table of its own, so a black-to-white ramp across 64 columns reads 2
    /// at the first and 254 at the last (never 0 and 255), and the columns
    /// between it wobble by up to 3/255 from the straight line — monotonic,
    /// deterministic, identical row to row, but not arithmetic. Two ramps
    /// that ought to be each other's mirror differ by that much for the same
    /// reason.
    private static func cgGradient(for gradient: Gradient) -> CGGradient? {
        let stops = gradient.sortedStops
        guard stops.count >= 2, let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        // `RGBA.nsColor` is built with `srgbRed:`, so these colours are
        // already in the space they are declared in and in the one the bitmap
        // holds — the same conversion `setFillColor` gets on the flat path,
        // which is what keeps a one-colour gradient byte-identical to it.
        let colors = stops.map { $0.color.nsColor.cgColor } as CFArray
        let locations = stops.map { CGFloat(min(max($0.at, 0), 1)) }
        return CGGradient(colorsSpace: space, colors: colors, locations: locations)
    }

    /// Paints `gradient` inside `path`, and answers whether it drew.
    ///
    /// The paint is a CLIP, not a transparency layer: `addPath`, `clip`, then
    /// one gradient draw inside a single `saveGState`.
    ///
    /// Measured against the flat path, and the boundary matters: a
    /// one-colour OPAQUE gradient is BYTE-identical to `fillPath()` wherever
    /// a pixel is fully covered — over a full-canvas rectangle, at 0°, 45°
    /// and 137° alike, not one component differs — and within one LSB
    /// wherever it is not: 200 of an ellipse's 4096 pixels, all of them on
    /// the antialiased edge and none of them opaque, plus every pixel of a
    /// translucent plate. The two paths agree on coverage exactly and round
    /// the PREMULTIPLIED colour differently, which is why the difference is
    /// bounded at 1/255 and appears only where alpha is not 255. A
    /// transparency layer buys a full-size buffer and a rounding step of its
    /// own and would not close that last LSB either.
    ///
    /// So a gradient is not a second way of drawing a flat plate, and a proof
    /// that wants a byte comparison out of that fact has to ask it of a
    /// rectangle on integral bounds — which the full-canvas background clip
    /// this feature exists for happens to be.
    ///
    /// It answers false rather than drawing when the box has no area — a
    /// stroke wider than the box makes `insetBy` hand back a NEGATIVE-width
    /// rect, which is older than this feature — or when the stops cannot make
    /// a ramp, and the caller falls back to the flat fill.
    private static func paint(
        _ gradient: Gradient, path: CGPath, box: CGRect, in context: CGContext
    ) -> Bool {
        guard box.width > 0, box.height > 0, let ramp = cgGradient(for: gradient) else {
            return false
        }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        context.clip()
        switch gradient.kind {
        case .linear:
            // Angle 0 is to the RIGHT and grows COUNTER-CLOCKWISE on screen —
            // the crate's one angle convention (`ShadowProps.angle`). This
            // context is y-UP, so the direction takes +sin where
            // `MetalRenderer.encodeShadow`, which works in the y-DOWN canvas
            // frame, takes −sin. Getting that backwards mirrors every
            // gradient that is not horizontal and leaves a horizontal one
            // right, which is why the proof reads a 45° ramp at a named
            // CORNER rather than only at the two ends.
            let radians = CGFloat(gradient.angle) * .pi / 180
            let direction = CGVector(dx: cos(radians), dy: sin(radians))
            // The box PROJECTED onto that direction: half the extent it
            // occupies along the ramp. The end stops then land exactly on the
            // box's own edges at every angle — an inscribed circle would put
            // the corners past the last stop, and the bounding circle would
            // spend most of the ramp outside the shape.
            let half = (abs(box.width * direction.dx) + abs(box.height * direction.dy)) / 2
            let centre = CGPoint(x: box.midX, y: box.midY)
            context.drawLinearGradient(
                ramp,
                start: CGPoint(
                    x: centre.x - direction.dx * half, y: centre.y - direction.dy * half),
                end: CGPoint(
                    x: centre.x + direction.dx * half, y: centre.y + direction.dy * half),
                // Past either end the end stop's colour continues, so a list
                // that starts at 0.2 fills the shape rather than leaving a
                // transparent band at its edge.
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .radial:
            // ONE inscribed ellipse for both area kinds, and it is got by
            // scaling the CTM rather than by choosing a radius: a circle in a
            // 1600 × 200 banner would leave most of the box ungraded, while
            // an ellipse reaches the edge midpoints of a rectangle and the
            // poles of an ellipse alike. The unit circle drawn under this
            // scale IS that ellipse.
            context.translateBy(x: box.midX, y: box.midY)
            context.scaleBy(x: box.width / 2, y: box.height / 2)
            context.drawRadialGradient(
                ramp, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1,
                options: [.drawsAfterEndLocation])
        }
        return true
    }

    /// Line and arrow. `from`/`to` are UNIT coordinates in the box with y
    /// DOWN, matching the canvas convention (§5.2) — CoreGraphics is y-up
    /// here, hence the flip.
    private func drawLine(
        _ props: ShapeProps, in context: CGContext, size: CGSize, strokeWidth: CGFloat
    ) {
        func point(_ unit: CGPoint) -> CGPoint {
            CGPoint(x: unit.x * size.width, y: (1 - unit.y) * size.height)
        }
        var start = point(props.fromPoint)
        var end = point(props.toPoint)
        let width = max(strokeWidth, 1)
        let headLength = width * 4
        let headHalf = width * 2
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        let unitX = dx / length
        let unitY = dy / length

        let wantsStart = props.kind == .arrow && props.arrowStart
        let wantsEnd = props.kind == .arrow && props.arrowEnd
        // Pull the shaft back to the base of each head, so the head's TIP is
        // the endpoint the model describes.
        if wantsStart {
            start = CGPoint(x: start.x + unitX * headLength, y: start.y + unitY * headLength)
        }
        if wantsEnd {
            end = CGPoint(x: end.x - unitX * headLength, y: end.y - unitY * headLength)
        }
        if props.stroke != nil, strokeWidth > 0 {
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }

        let headColor = props.stroke?.color ?? props.fill
        guard let headColor = headColor, wantsStart || wantsEnd else { return }
        context.setFillColor(headColor.nsColor.cgColor)
        if wantsEnd {
            fillHead(
                context, tip: point(props.toPoint), ux: unitX, uy: unitY, length: headLength,
                half: headHalf)
        }
        if wantsStart {
            fillHead(
                context, tip: point(props.fromPoint), ux: -unitX, uy: -unitY, length: headLength,
                half: headHalf)
        }
    }

    private func fillHead(
        _ context: CGContext, tip: CGPoint, ux: CGFloat, uy: CGFloat, length: CGFloat,
        half: CGFloat
    ) {
        let baseX = tip.x - ux * length
        let baseY = tip.y - uy * length
        context.move(to: tip)
        context.addLine(to: CGPoint(x: baseX - uy * half, y: baseY + ux * half))
        context.addLine(to: CGPoint(x: baseX + uy * half, y: baseY - ux * half))
        context.closePath()
        context.fillPath()
    }

    private func renderImage(_ image: CGImage) -> Rendered? {
        let size = CGSize(width: image.width, height: image.height)
        guard size.width >= 1, size.height >= 1, let context = LayerRenderers.bitmap(size)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return upload(context, size: size)
    }

    // MARK: - Bitmaps and textures

    /// A premultiplied BGRA bitmap context — the ONE pixel layout this
    /// renderer produces, and the one `Compositor.metal` samples
    /// (`.bgra8Unorm`).
    ///
    /// Internal rather than private since the text machinery moved to
    /// `LayerRenderersText.swift` and draws into one of these; `private` on
    /// an extension member reaches only its own file.
    static func bitmap(_ size: CGSize) -> CGContext? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0, width <= maxTextureSide, height <= maxTextureSide,
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        context?.setAllowsAntialiasing(true)
        return context
    }

    /// Uploads a bitmap context to a texture. Row 0 of the context's memory
    /// is the TOP row of the drawing, which is also texture row 0 — the same
    /// top-left origin the crop window and the recipe's y-down canvas use, so
    /// nothing is flipped anywhere in this pipeline.
    ///
    /// Internal for `bitmap`'s reason: `renderText` ends here too.
    func upload(_ context: CGContext, size: CGSize) -> Rendered? {
        guard let data = context.data else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: context.width, height: context.height,
            mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, context.width, context.height), mipmapLevel: 0,
            withBytes: data, bytesPerRow: context.bytesPerRow)
        return Rendered(texture: texture, size: size)
    }
}
