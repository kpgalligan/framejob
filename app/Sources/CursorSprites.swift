import CoreGraphics
import ImageIO
import Metal

/// The cursor's sprite textures (spec §11 CU-33 (c), (e), (g)): one per cursor image a track
/// draws, made once — the image's PNG from `ReelCursor.image(id:)` decoded into a premultiplied
/// `bgra8Unorm` texture, the layout `LayerRenderers` uploads — and, in an HLG project, lifted
/// once through `lift` (`MetalRenderer.lifted`, `LayerLift`), never per frame.
///
/// A least-recently-used pool of `limit` entries keyed by the track's identity, the image id and
/// the project's output. Each entry holds its track strongly, so an identity is never reused for
/// another track while its sprite is held. One per `MetalRenderer`, called on its render queue
/// only, so it keeps no lock. `uploads` counts the textures made since `init`, arrows included
/// (a probe's measure that a sprite is never made per frame).
///
/// Since CU4 (spec §11 CU-41) it also holds Frame Job's arrow (`CursorArrow`): rasterized by the
/// graphic engine through a `GraphicLibrary` of its own, one texture per pixel size and output
/// in a second pool of `limit`, lifted in an HLG project as a sprite is.
final class CursorSprites {
    static let limit = 64

    private struct Key: Hashable {
        let track: ObjectIdentifier
        let id: Int
        let output: CanvasOutput
    }

    private struct Entry {
        let track: ReelCursor
        let texture: MTLTexture
    }

    private struct ArrowKey: Hashable {
        let width: Int
        let height: Int
        let output: CanvasOutput
    }

    private let device: MTLDevice
    private var entries = LRUCache<Key, Entry>(limit: CursorSprites.limit)
    private var arrows = LRUCache<ArrowKey, MTLTexture>(limit: CursorSprites.limit)
    /// The engine the arrow is rasterized by; it has no fonts or assets, and freezes on its
    /// first rasterize.
    private let library = GraphicLibrary()
    private(set) var uploads = 0

    init(device: MTLDevice) {
        self.device = device
    }

    /// The image's texture, lifted through `lift` in an HLG project; nil when it cannot be made
    /// (an id the track does not hold, a PNG that does not decode, a lift that fails).
    func texture(
        track: ReelCursor, id: Int, output: CanvasOutput, lift: (MTLTexture) -> MTLTexture?
    ) -> MTLTexture? {
        let key = Key(track: ObjectIdentifier(track), id: id, output: output)
        if let hit = entries.value(for: key, where: { $0.track === track }) {
            return hit.texture
        }
        guard let image = try? track.image(id: id), let decoded = upload(png: image.png)
        else { return nil }
        let drawn: MTLTexture
        if output == .hlg {
            guard let lifted = lift(decoded) else { return nil }
            drawn = lifted
        } else {
            drawn = decoded
        }
        uploads += 1
        entries.insert(Entry(track: track, texture: drawn), for: key)
        return drawn
    }

    /// Frame Job's arrow at `width` × `height` pixels, lifted through `lift` in an HLG project;
    /// made once per size and output (CU-41). Nil when the engine refuses it or a lift fails.
    func arrow(
        width: Int, height: Int, output: CanvasOutput, lift: (MTLTexture) -> MTLTexture?
    ) -> MTLTexture? {
        let key = ArrowKey(width: width, height: height, output: output)
        if let hit = arrows.value(for: key) { return hit }
        guard let raster = try? library.rasterize(
            CursorArrow.svg(width: width, height: height), width: width, height: height),
              let decoded = upload(raster: raster)
        else { return nil }
        let drawn: MTLTexture
        if output == .hlg {
            guard let lifted = lift(decoded) else { return nil }
            drawn = lifted
        } else {
            drawn = decoded
        }
        uploads += 1
        arrows.insert(drawn, for: key)
        return drawn
    }

    /// An engine raster — premultiplied BGRA, row 0 the top — uploaded as `upload(png:)` does.
    private func upload(raster: GraphicRaster) -> MTLTexture? {
        guard let texture = makeTexture(width: raster.width, height: raster.height) else {
            return nil
        }
        raster.bgra.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, raster.width, raster.height), mipmapLevel: 0,
                withBytes: base, bytesPerRow: raster.stride)
        }
        return texture
    }

    /// A `.bgra8Unorm`, `.managed`, shader-read texture: every sprite's descriptor.
    private func makeTexture(width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        return device.makeTexture(descriptor: descriptor)
    }

    /// `png` decoded and drawn into a premultiplied BGRA bitmap at its own pixel size, then
    /// uploaded; row 0 is the image's top row, as every layer texture is.
    private func upload(png: Data) -> MTLTexture? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = LayerRenderers.bitmap(
                CGSize(width: image.width, height: image.height)),
              let data = context.data
        else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        guard let texture = makeTexture(width: context.width, height: context.height) else {
            return nil
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, context.width, context.height), mipmapLevel: 0,
            withBytes: data, bytesPerRow: context.bytesPerRow)
        return texture
    }
}
