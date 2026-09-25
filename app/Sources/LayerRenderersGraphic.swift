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
// Any failure — no set for the key, no module, a module that did not
// compile, a throw from the draw or the raster, an upload that fails —
// answers nil, and the compositor draws the slate. G3c's error card is the
// better answer to most of those.

import CryptoKit
import Metal

extension LayerRenderers {

    /// The texture for a `graphic` recipe layer at `size`, or nil.
    func graphic(
        name: String, frame: Int, propsJSON: String, ctxJSON: String,
        size: CGSize, recipeKey: Int
    ) -> Rendered? {
        guard let resolved = GraphicRegistry.shared.resolve(recipeKey),
            case .compiled(let module, _, _, _)? = resolved.set.modules[name],
            let drawn = try? module.svg(
                frame: frame, propsJSON: propsJSON, ctxJSON: ctxJSON,
                budgetMs: resolved.budgetMs)
        else { return nil }
        let set = resolved.set
        let width = Int(size.width), height = Int(size.height)
        let key = LayerRenderers.textureKey(
            svg: drawn.svg, width: width, height: height, libraryVersion: set.libraryVersion)
        return cached(key, graphic: true) {
            guard let raster = try? set.library.rasterize(drawn.svg, width: width, height: height)
            else { return nil }
            return self.upload(raster)
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
