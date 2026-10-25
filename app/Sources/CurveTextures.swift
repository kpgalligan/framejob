import Foundation
import Metal

/// The curves' strips (spec §11 GR-12, grading-2 G2-3): each layer's
/// `ColorCurves` as one `stripSize` × 2 texture of `CurveTable.strip`'s
/// texels (row 0 the tone composites, row 1 the hue curves, spec §11 GR-32),
/// which step 4c.2 samples at `texture(3)` — `rgba32Float`, or
/// `rgba16Float` on a device without 32-bit float filtering (REASONED never
/// on an Apple-silicon Mac; still under one 10-bit level). Kept in a
/// least-recently-used cache of `capacity`, keyed by the curves — their
/// `blends` included (spec §11 GR-34), so a blended channel makes a new strip
/// every frame of its action, as any animated curve does — held by
/// `LookTextures` beside the looks' cache.
///
/// **The placeholder** is a 2 × 2 identity strip: row 0 (0, 0, 0, 1) and
/// (1, 1, 1, 1), row 1 (0, 1, 0, 1) twice (no shift, gain 1): bound on every
/// draw whose layer is uncurved, because every fragment that names
/// `texture(3)` must have one there, and an identity so even a stray sample
/// would change nothing. An upload that fails answers it too, and `prepare`
/// then zeroes `curvesEnabled` and `hueCurvesEnabled`, so the layer draws
/// uncurved rather than not at all. One lock: the preview's and an export's
/// compositors render on their own queues.
final class CurveTextures {
    static let capacity = 8

    let placeholder: MTLTexture
    /// The strips' pixel format, decided once for the device.
    let format: MTLPixelFormat
    private let device: MTLDevice
    private let lock = NSLock()
    private var cache = LRUCache<ColorCurves, MTLTexture>(limit: CurveTextures.capacity)

    init?(device: MTLDevice) {
        self.device = device
        format = device.supports32BitFloatFiltering ? .rgba32Float : .rgba16Float
        guard let placeholder = CurveTextures.upload(
            [0, 0, 0, 1, 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 0, 1], width: 2, height: 2,
            format: format, device: device)
        else { return nil }
        placeholder.label = "Frame Job curves placeholder"
        self.placeholder = placeholder
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("CurveTextures does not support NSCoder")
    }

    /// The strip to bind for a layer's curves: the cached one, built now on
    /// a miss; the placeholder for the identity or a failed upload.
    func texture(for curves: ColorCurves) -> MTLTexture {
        guard !curves.isIdentity else { return placeholder }
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache.value(for: curves) { return hit }
        let strip = CurveTextures.upload(
            CurveTable.strip(curves), width: CurveTable.stripSize, height: CurveTable.stripRows,
            format: format, device: device)
        strip?.label = "Frame Job curves"
        let made = strip ?? placeholder
        cache.insert(made, for: curves)
        return made
    }

    /// `texels` (RGBA floats, `width` × `height` of them, row 0 first) as a
    /// `width` × `height` texture in `format`, half floats converted by
    /// Swift's `Float16` (round to nearest); nil when the device cannot make
    /// it.
    static func upload(
        _ texels: [Float], width: Int, height: Int = 1, format: MTLPixelFormat,
        device: MTLDevice
    ) -> MTLTexture? {
        guard width >= 2, height >= 1, texels.count == width * height * 4 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let region = MTLRegionMake2D(0, 0, width, height)
        if format == .rgba32Float {
            texels.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                texture.replace(region: region, mipmapLevel: 0, withBytes: base,
                                bytesPerRow: width * 16)
            }
        } else {
            let halves = texels.map { Float16($0) }
            halves.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                texture.replace(region: region, mipmapLevel: 0, withBytes: base,
                                bytesPerRow: width * 8)
            }
        }
        return texture
    }
}
