import AppKit
import CoreText
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
/// (§7.5). One instance per `Compositor`, called from its render queue; the
/// measured-size cache is static and shared, because the canvas overlay on
/// the main thread needs the same numbers to draw handles.
final class LayerRenderers {

    /// Textures kept before the least recently used one is dropped (§7.5).
    static let cacheLimit = 64
    /// Widest texture rendered. Beyond this a description is refused rather
    /// than clamped — a 40 000 pt font is a typo, not a request.
    static let maxTextureSide = 8192

    private let device: MTLDevice
    private let lock = NSLock()
    private var entries: [String: Rendered] = [:]
    /// Least recently used first.
    private var order: [String] = []

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
    private func cached(_ key: String, _ make: () -> Rendered?) -> Rendered? {
        lock.lock()
        if let hit = entries[key] {
            touch(key)
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let rendered = make() else { return nil }
        lock.lock()
        entries[key] = rendered
        touch(key)
        while order.count > LayerRenderers.cacheLimit, let oldest = order.first {
            order.removeFirst()
            entries.removeValue(forKey: oldest)
        }
        lock.unlock()
        return rendered
    }

    /// Moves `key` to the most-recent end. Call with the lock held.
    private func touch(_ key: String) {
        if let index = order.firstIndex(of: key) { order.remove(at: index) }
        order.append(key)
    }

    /// Drops every texture. Called when the render context changes size —
    /// the textures themselves are resolution-independent, but a canvas
    /// resize invalidates nothing else and this keeps memory honest.
    func purge() {
        lock.lock()
        entries.removeAll()
        order.removeAll()
        lock.unlock()
    }

    // MARK: - Public rendering

    /// The texture for a `text` recipe layer, cached by the recipe's hash.
    /// The size returned is the MEASURED layout size — the number the model
    /// deliberately does not store (§5.3, §11).
    func text(_ props: TextProps, hash: String) -> Rendered? {
        // The closure is NON-escaping (`cached` calls it and returns), so a
        // strong capture here cannot make a cycle.
        cached("text:" + hash) { self.renderText(props) }
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

    // MARK: - Measured text

    /// The layout size of a text description, in source pixels, INCLUDING
    /// the backdrop's padding and the outline's overshoot — the box the
    /// texture is drawn into, so the compositor and the overlay agree on
    /// where a text layer is.
    ///
    /// Static and process-wide because the overlay asks for it on the main
    /// thread while the compositor asks for it on its render queue, and
    /// re-measuring a paragraph per frame is the one cost this cache exists
    /// to avoid.
    static func measuredSize(for props: TextProps) -> CGSize {
        let key = layoutKey(props)
        sizeLock.lock()
        if let hit = sizeCache[key] {
            sizeLock.unlock()
            return hit
        }
        sizeLock.unlock()

        let size = measure(props)
        sizeLock.lock()
        if sizeCache.count > cacheLimit * 4 { sizeCache.removeAll() }
        sizeCache[key] = size
        sizeLock.unlock()
        return size
    }

    /// The source size of ANY recipe layer: measured for text, the stored
    /// box for a shape, the media size otherwise. This is the closure
    /// `FrameRecipe.layer(at:measuring:)` wants, so the canvas overlay
    /// hit-tests exactly what the compositor drew.
    static func measuredSize(for layer: RecipeLayer) -> CGSize? {
        switch layer.source {
        case .text(_, let props): return measuredSize(for: props)
        case .shape(_, let props): return layer.sourceSizeCG ?? props.boxSize
        case .track, .image, .missing: return layer.sourceSizeCG
        }
    }

    private static let sizeLock = NSLock()
    private static var sizeCache: [String: CGSize] = [:]

    /// Every field that changes the LAYOUT (colour does not). Cheap to build
    /// and stable, which is all a cache key has to be.
    private static func layoutKey(_ props: TextProps) -> String {
        let outline = props.outline.map { "\($0.width)" } ?? "-"
        let backdrop = props.backdrop.map { "\($0.padding)" } ?? "-"
        let width = props.width.map { "\($0)" } ?? "-"
        return [
            props.content, props.font, "\(props.size)", props.align, props.valign,
            "\(props.lineSpacing)", "\(props.tracking)", outline, backdrop, width,
        ].joined(separator: "\u{1}")
    }

    /// CoreText's "no constraint". `CGFloat.greatestFiniteMagnitude` makes
    /// the framesetter's arithmetic overflow into NaN on some fonts; a large
    /// finite number does not.
    private static let unconstrained: CGFloat = 100_000

    private static func measure(_ props: TextProps) -> CGSize {
        let attributed = attributedString(props)
        guard attributed.length > 0 else { return CGSize(width: 1, height: 1) }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var fitRange = CFRange()
        let constraint = CGSize(
            width: props.width.map { max(1, CGFloat($0)) } ?? unconstrained,
            height: unconstrained)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil, constraint, &fitRange)
        let inset = textInset(props)
        let width = (props.width.map { CGFloat($0) } ?? suggested.width) + inset * 2
        let height = suggested.height + inset * 2
        return CGSize(
            width: min(CGFloat(maxTextureSide), max(1, width.rounded(.up))),
            height: min(CGFloat(maxTextureSide), max(1, height.rounded(.up))))
    }

    /// The margin around the laid-out text: the backdrop's padding, and
    /// enough room for the outline, whose stroke straddles the glyph edge.
    private static func textInset(_ props: TextProps) -> CGFloat {
        let outline = props.outline.map { CGFloat($0.width) } ?? 0
        let padding = props.backdrop.map { CGFloat($0.padding) } ?? 0
        return max(outline, padding)
    }

    private static func attributedString(_ props: TextProps) -> NSAttributedString {
        let size = max(1, CGFloat(props.size))
        let font = CTFontCreateWithName(props.font as CFString, size, nil)
        let paragraph = NSMutableParagraphStyle()
        switch props.align {
        case "left": paragraph.alignment = .left
        case "right": paragraph.alignment = .right
        default: paragraph.alignment = .center
        }
        // `lineSpacing` is a MULTIPLE of the natural line height (§5.2), not
        // a point value, which is `lineHeightMultiple`, not `lineSpacing`.
        if props.lineSpacing > 0, props.lineSpacing != 1 {
            paragraph.lineHeightMultiple = CGFloat(props.lineSpacing)
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: props.color.nsColor,
            .paragraphStyle: paragraph,
        ]
        if props.tracking != 0 { attributes[.kern] = CGFloat(props.tracking) }
        if let outline = props.outline {
            // A NEGATIVE stroke width means "fill AND stroke", and the value
            // is a PERCENTAGE of the font size — positive would draw the
            // outline only and lose the fill.
            attributes[.strokeWidth] = -CGFloat(outline.width) / size * 100
            attributes[.strokeColor] = outline.color.nsColor
        }
        return NSAttributedString(string: props.content, attributes: attributes)
    }

    // MARK: - Rasterizing

    private func renderText(_ props: TextProps) -> Rendered? {
        let size = LayerRenderers.measuredSize(for: props)
        guard let context = LayerRenderers.bitmap(size) else { return nil }
        let inset = LayerRenderers.textInset(props)

        if let backdrop = props.backdrop {
            let rect = CGRect(origin: .zero, size: size)
            let radius = min(CGFloat(backdrop.radius), min(size.width, size.height) / 2)
            let path = CGPath(
                roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            context.addPath(path)
            context.setFillColor(backdrop.color.nsColor.cgColor)
            context.fillPath()
        }

        let attributed = LayerRenderers.attributedString(props)
        if attributed.length > 0 {
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            var fitRange = CFRange()
            let constraint = CGSize(
                width: size.width - inset * 2, height: LayerRenderers.unconstrained)
            let laid = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRange(location: 0, length: 0), nil, constraint, &fitRange)
            // Two points of slack: CoreText CLIPS to the frame path, and a
            // frame exactly as tall as the suggested size drops the last
            // line on some fonts through rounding.
            let height = min(size.height - inset * 2, laid.height) + 2
            let y: CGFloat
            switch props.valign {
            // CoreGraphics is y-UP here, so "top" is the high y.
            case "top": y = size.height - inset - height
            case "bottom": y = inset
            default: y = (size.height - height) / 2
            }
            let rect = CGRect(x: inset, y: y, width: size.width - inset * 2, height: height)
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil),
                nil)
            CTFrameDraw(frame, context)
        }
        return upload(context, size: size)
    }

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
            draw(path, in: context, props: props, strokeWidth: strokeWidth)
        case .ellipse:
            draw(CGPath(ellipseIn: rect, transform: nil), in: context, props: props,
                strokeWidth: strokeWidth)
        case .line, .arrow:
            drawLine(props, in: context, size: size, strokeWidth: strokeWidth)
        }
        return upload(context, size: size)
    }

    private func draw(
        _ path: CGPath, in context: CGContext, props: ShapeProps, strokeWidth: CGFloat
    ) {
        if props.fill != nil {
            context.addPath(path)
            context.fillPath()
        }
        if props.stroke != nil, strokeWidth > 0 {
            context.addPath(path)
            context.strokePath()
        }
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

    /// A premultiplied BGRA bitmap context — the ONE pixel layout this file
    /// produces, and the one `Compositor.metal` samples (`.bgra8Unorm`).
    private static func bitmap(_ size: CGSize) -> CGContext? {
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
    private func upload(_ context: CGContext, size: CGSize) -> Rendered? {
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
