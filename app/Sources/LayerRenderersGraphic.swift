// app/Sources/LayerRenderersGraphic.swift — a `graphic` recipe layer drawn
// (road map 10 §5d, G3b): the registry's compiled module for the layer's
// key → the module's SVG for the frame → a raster at the layer's own size
// (G-7) → a premultiplied BGRA texture, the one layout `Compositor.metal`
// samples.
//
// **The texture key is the SVG TEXT**, not the recipe's hash — a departure
// from `LayerRenderers.swift`'s "the recipe's hash is the whole key", made
// by design §5d: the module is JavaScript the user edits, so the same hash
// can draw differently after a save, and the SVG is what the pixels are a
// function of (with the size and the library's fonts and assets). A frame
// whose SVG repeats — a hold, a static graphic — skips the raster.
//
// **The props and ctx are the core's own JSON text** (`props_json` and
// `ctx_json`), handed to the engine untouched: the engine overlays the
// module's defaults under the stored props (G-4), and warns about a stale
// key or a wrong type rather than refusing.
//
// **A graphic that fails draws its error card** (G-8, G3c): no module of
// that name, a module that did not compile, a throw or a timeout from the
// draw, a raster the engine refused. The card is keyed by its own TEXT in
// the same graphic pool, so a failed frame never serves the last good
// frame's texture and a later good frame never serves the card. Each
// failure and each warning is RECORDED against the recipe key — kept only
// by a pinned offline key (`GraphicRegistry.pin`), a no-op for a preview
// key. A raster's warnings ride in `Rendered.warnings`, so a pool hit still
// reports them. Only a key with no set (the slate) and an upload that fails
// answer nil.

import AppKit
import CoreText
import CryptoKit
import Metal

extension LayerRenderers {

    /// The texture for a `graphic` recipe layer at `size` — the graphic, or
    /// its error card — or nil when `recipeKey` has no set.
    func graphic(
        name: String, frame: Int, propsJSON: String, ctxJSON: String,
        size: CGSize, recipeKey: Int
    ) -> Rendered? {
        guard let resolved = GraphicRegistry.shared.resolve(recipeKey) else { return nil }
        let set = resolved.set
        let module: GraphicModule
        switch set.modules[name] {
        case nil:
            let missing = GraphicDiagnostic(
                level: "error", message: "No module named \"\(name)\" in graphics/",
                line: nil, column: nil, frame: nil)
            return failed(name, frame: frame, [missing], size: size, recipeKey: recipeKey)
        case .failed(let diagnostics, _)?:
            return failed(name, frame: nil, diagnostics, size: size, recipeKey: recipeKey)
        case .compiled(let compiled, _, _, _)?:
            module = compiled
        }
        let drawn: (svg: String, warnings: [GraphicDiagnostic])
        do {
            drawn = try module.svg(
                frame: frame, propsJSON: propsJSON, ctxJSON: ctxJSON,
                budgetMs: resolved.budgetMs)
        } catch {
            return failed(
                name, frame: frame, Self.diagnostics(of: error), size: size, recipeKey: recipeKey)
        }
        if !drawn.warnings.isEmpty {
            GraphicRegistry.shared.record(
                GraphicReport(name: name, frame: frame, failed: false, diagnostics: drawn.warnings),
                for: recipeKey)
        }
        let width = Int(size.width), height = Int(size.height)
        let key = LayerRenderers.textureKey(
            svg: drawn.svg, width: width, height: height, libraryVersion: set.libraryVersion)
        let slot = GraphicPrefetch.Slot(
            name: name, frame: frame, width: width, height: height, propsJSON: propsJSON,
            ctxJSON: ctxJSON)
        var refused: [GraphicDiagnostic]?
        var made = false
        let rendered = cached(key, graphic: true) {
            made = true
            let raster: GraphicRaster
            do {
                if let prefetched = GraphicPrefetch.shared.take(
                    recipeKey, slot: slot, textureKey: key)
                {
                    raster = try prefetched.get()
                } else {
                    raster = try set.library.rasterize(drawn.svg, width: width, height: height)
                }
            } catch {
                refused = Self.diagnostics(of: error)
                return nil
            }
            GraphicPrefetch.shared.keep(recipeKey, textureKey: key, raster: raster)
            guard var uploaded = self.upload(raster) else { return nil }
            uploaded.warnings = raster.warnings
            return uploaded
        }
        if !made { GraphicPrefetch.shared.discard(recipeKey, slot: slot) }
        if let refused = refused {
            return failed(name, frame: frame, refused, size: size, recipeKey: recipeKey)
        }
        guard let rendered = rendered else { return nil }
        if !rendered.warnings.isEmpty {
            GraphicRegistry.shared.record(
                GraphicReport(
                    name: name, frame: frame, failed: false, diagnostics: rendered.warnings),
                for: recipeKey)
        }
        return rendered
    }

    /// A failure recorded against `recipeKey` and drawn as its error card.
    private func failed(
        _ name: String, frame: Int?, _ diagnostics: [GraphicDiagnostic], size: CGSize,
        recipeKey: Int
    ) -> Rendered? {
        GraphicRegistry.shared.record(
            GraphicReport(name: name, frame: frame, failed: true, diagnostics: diagnostics),
            for: recipeKey)
        return errorCard(
            text: Self.errorCardText(name: name, frame: frame, diagnostic: diagnostics.first),
            size: size)
    }

    /// The engine's diagnostics out of a thrown error — one error saying
    /// what was thrown when it carries none.
    private static func diagnostics(of error: any Error) -> [GraphicDiagnostic] {
        if let failure = error as? GraphicFailure, !failure.diagnostics.isEmpty {
            return failure.diagnostics
        }
        return [GraphicDiagnostic(
            level: "error", message: error.localizedDescription, line: nil, column: nil,
            frame: nil)]
    }

    /// The card's lines: `<name> · frame <N>` (or `· does not compile`), the
    /// message, and `line L, column C` when the diagnostic has a line.
    static func errorCardText(name: String, frame: Int?, diagnostic: GraphicDiagnostic?) -> String {
        var lines = [frame.map { "\(name) · frame \($0)" } ?? "\(name) · does not compile"]
        if let diagnostic = diagnostic {
            lines.append(diagnostic.message)
            if let line = diagnostic.line {
                lines.append("line \(line)" + (diagnostic.column.map { ", column \($0)" } ?? ""))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The error card (G-8): dark red, a 2 px bright red border, `text` in
    /// white mono inset by three times its point size. Keyed by the text and
    /// the size in the graphic pool.
    func errorCard(text: String, size: CGSize) -> Rendered? {
        let digest = SHA256.hash(data: Data(text.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let key = "graphic-error:" + hex + ":"
            + "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
        return cached(key, graphic: true) {
            guard let context = LayerRenderers.bitmap(size) else { return nil }
            let bounds = CGRect(x: 0, y: 0, width: context.width, height: context.height)
            Self.paintErrorCard(text, in: context, bounds: bounds)
            return self.upload(context, size: bounds.size)
        }
    }

    /// The card's drawing, into `bounds` of an unflipped `context`: the one
    /// painter, shared by `errorCard` and `render_graphic`'s contact sheet.
    static func paintErrorCard(_ text: String, in context: CGContext, bounds: CGRect) {
        context.setFillColor(CGColor(srgbRed: 230 / 255, green: 40 / 255, blue: 40 / 255, alpha: 1))
        context.fill(bounds)
        context.setFillColor(CGColor(srgbRed: 64 / 255, green: 8 / 255, blue: 8 / 255, alpha: 1))
        context.fill(bounds.insetBy(dx: 2, dy: 2))
        let point = max(11, (min(bounds.width, bounds.height) / 28).rounded())
        let rect = bounds.insetBy(dx: 3 * point, dy: 3 * point)
        if rect.width > 0, rect.height > 0 {
            let attributed = NSAttributedString(
                string: text,
                attributes: [.font: DS.mono(point), .foregroundColor: NSColor.white])
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: 0, length: 0),
                CGPath(rect: rect, transform: nil), nil)
            CTFrameDraw(frame, context)
        }
    }

    /// `"graphic:" + SHA-256(svg) + ":" + w×h + ":" + libraryVersion`.
    static func textureKey(svg: String, width: Int, height: Int, libraryVersion: String) -> String {
        let digest = SHA256.hash(data: Data(svg.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "graphic:" + hex + ":" + "\(width)x\(height)" + ":" + libraryVersion
    }

    /// Uploads an engine raster — already premultiplied BGRA, rows
    /// `stride` bytes apart, row 0 the top — to a `.bgra8Unorm` texture of
    /// the raster's own size.
    func upload(_ raster: GraphicRaster) -> Rendered? {
        guard raster.width > 0, raster.height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: raster.width, height: raster.height,
            mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        raster.bgra.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, raster.width, raster.height), mipmapLevel: 0,
                withBytes: base, bytesPerRow: raster.stride)
        }
        return Rendered(
            texture: texture, size: CGSize(width: raster.width, height: raster.height))
    }
}

extension GraphicPrefetch {
    /// One graphic layer's inputs — exactly what `LayerRenderers.graphic` is
    /// called with. Member order is load-bearing (`graphics_proof.py`'s
    /// `frame-plus-one` anchor in `LayerRenderersGraphic.swift`).
    struct Slot: Hashable {
        let name: String
        let frame: Int
        let width: Int
        let height: Int
        let propsJSON: String
        let ctxJSON: String
    }
}
