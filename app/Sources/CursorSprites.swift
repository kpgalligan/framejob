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
/// only, so it keeps no lock. `uploads` counts the textures made since `init` (a probe's
/// measure that a sprite is never made per frame).
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

    private let device: MTLDevice
    private var entries = LRUCache<Key, Entry>(limit: CursorSprites.limit)
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
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: context.width, height: context.height,
            mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, context.width, context.height), mipmapLevel: 0,
            withBytes: data, bytesPerRow: context.bytesPerRow)
        return texture
    }
}
