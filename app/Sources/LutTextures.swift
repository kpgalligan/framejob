import Accelerate
import Foundation
import Metal

/// A `.cube` file's table as the core read it (`ReelCube.parse`): `size`
/// points an axis and `size³` rows of red, green and blue, red changing
/// fastest — a 3D texture's texel order.
struct CubeLattice {
    let size: Int
    let rgb: [Float]
}

/// Imported LUTs' lattices (spec §11 GR-8): a LUT look's `.cube` file read
/// through `MediaImporter.readLUT` and uploaded as an `rgba16Float` `size³`
/// 3D texture, alpha 1 and every value clamped to 0–1, which step 4d samples
/// at `texture(2)` exactly as it samples a built-in look's bake.
///
/// Kept in a least-recently-used cache of `capacity`, keyed by the file's
/// path, byte size and modification date — so a LUT changed on disk is read
/// again at the next frame drawn — with a file that cannot be read or
/// uploaded cached as a failure under its key, so a refused or broken file
/// is not re-read every frame (a missing file has no key and answers nil at
/// once). The attributes are read through `FileManager` each time, never
/// through `URL.resourceValues`, which caches them on the URL. One lock, as
/// `LookTextures`' cache has: the preview's and an export's compositors
/// render on their own queues.
final class LutTextures {
    static let capacity = 8

    private struct Key: Hashable {
        let path: String
        let size: Int
        let modified: Date
    }

    private enum Entry {
        case texture(MTLTexture)
        case failed
    }

    private let device: MTLDevice
    private let lock = NSLock()
    private var cache: [Key: Entry] = [:]
    /// Least recently used first.
    private var order: [Key] = []

    init(device: MTLDevice) {
        self.device = device
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("LutTextures does not support NSCoder")
    }

    /// The lattice of the `.cube` file at `url`, read and uploaded on a miss;
    /// nil when the file is missing, refused by the core or cannot be
    /// uploaded.
    func texture(at url: URL) -> MTLTexture? {
        let path = url.standardizedFileURL.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let bytes = (attributes[.size] as? NSNumber)?.intValue,
            let modified = attributes[.modificationDate] as? Date
        else { return nil }
        let key = Key(path: path, size: bytes, modified: modified)
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] {
            order.removeAll { $0 == key }
            order.append(key)
            if case .texture(let texture) = hit { return texture }
            return nil
        }
        let made = (try? MediaImporter.readLUT(url)).flatMap { upload($0) }
        cache[key] = made.map { .texture($0) } ?? .failed
        order.append(key)
        while order.count > LutTextures.capacity {
            cache[order.removeFirst()] = nil
        }
        return made
    }

    /// The table as `rgba16Float` texels, each value clamped to 0–1 and
    /// alpha 1, converted to half floats by vImage (round to nearest).
    private func upload(_ lattice: CubeLattice) -> MTLTexture? {
        let n = lattice.size
        let points = n * n * n
        guard n >= 2, lattice.rgb.count == points * 3 else { return nil }
        var rgba = [Float](repeating: 1, count: points * 4)
        for point in 0..<points {
            for channel in 0..<3 {
                rgba[point * 4 + channel] = min(max(lattice.rgb[point * 3 + channel], 0), 1)
            }
        }
        let count = rgba.count
        var halves = [UInt16](repeating: 0, count: count)
        let converted: Bool = rgba.withUnsafeMutableBytes { source in
            halves.withUnsafeMutableBytes { target in
                guard let from = source.baseAddress, let to = target.baseAddress else {
                    return false
                }
                var src = vImage_Buffer(
                    data: from, height: 1, width: vImagePixelCount(count),
                    rowBytes: source.count)
                var dst = vImage_Buffer(
                    data: to, height: 1, width: vImagePixelCount(count),
                    rowBytes: target.count)
                return vImageConvert_PlanarFtoPlanar16F(&src, &dst, vImage_Flags(kvImageNoFlags))
                    == kvImageNoError
            }
        }
        guard converted else { return nil }
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = n
        descriptor.height = n
        descriptor.depth = n
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let written: Bool = halves.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return false }
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, n, n, n), mipmapLevel: 0, slice: 0,
                withBytes: base, bytesPerRow: n * 8, bytesPerImage: n * n * 8)
            return true
        }
        guard written else { return nil }
        texture.label = "Frame Job LUT"
        return texture
    }
}
