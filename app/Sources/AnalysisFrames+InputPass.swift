import AVFoundation
import Metal

/// CO-7's third reader (spec §11 CO-7, CO-13; road map "creator-jobs" CO1):
/// a converting media read for a picture kind that must keep every frame's
/// own presentation time (`masks`), where the one-clip composition's
/// converted reader hands back the composition's frame grid instead.
///
/// An `AVAssetReaderTrackOutput` over the first video track decodes to the
/// compositor's source format (`Compositor.sourcePixelFormat`, Metal
/// compatible) at the natural size scaled to the long side; each frame is
/// wrapped as a texture and converted by step 0's own pass (`InputPass`) to
/// SDR — the conversion chosen ONCE per read: the media's Camera Log
/// (`InputConversion.choose(input:)`), else the track's first format
/// description's labels (`choose(for:)`); a `.lut` through
/// `LutTextures.texture(at:)`; the range flag as the stamp records it
/// (`readsRange` and the track's flag), a PQ media's effective peak — into a
/// `.shared` `rgba16Float` target made per read, read back, rounded to 8-bit
/// BGRA as `halfToBGRA` does, and turned upright from the track's
/// `preferredTransform` as the direct reader is.
extension AnalysisFrames {

    static func decodeThroughInputPass(
        _ source: Source, input: ThumbnailInput, longSide: Int, range: CMTimeRange,
        cancelled: () -> Bool, each: (Int64, AnalysisPicture) throws -> Bool
    ) throws -> Bool {
        let asset = AVURLAsset(
            url: source.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .video) else {
            throw ReadError.noPicture
        }
        let transform = preferredTransform(of: track)
        let turned = CompositionBuilder.orientationCode(transform) & 1 == 1
        let display = size(of: source.media, longSide: longSide)
        let natural = turned ? (display.height, display.width) : (display.width, display.height)
        let pass = try InputPassReader(
            input: input, track: track, width: natural.0, height: natural.1)
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch {
            throw ReadError.reader(error.localizedDescription)
        }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(Compositor.sourcePixelFormat),
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferWidthKey as String: natural.0,
                kCVPixelBufferHeightKey as String: natural.1,
            ])
        output.alwaysCopiesSampleData = false
        reader.timeRange = range
        reader.add(output)
        var upright = Upright(transform: transform)
        var scratch: [UInt8] = []
        return try pump(reader, output, cancelled: cancelled) { pts, buffer in
            let half = try pass.convert(buffer)
            return try halfToBGRA(half, into: &scratch) { picture in
                let bgra = try pass.bgra(picture)
                return try upright.picture(of: bgra) { try each(pts, $0) }
            }
        }
    }
}

/// One read's step-0 pass: the device, the pipeline, the conversion and its
/// LUT, the per-read target and the two buffers its read-back goes through.
private final class InputPassReader {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pass: InputPass
    let cache: CVMetalTextureCache
    let conversion: InputConversion
    let lut: MTLTexture?
    let fullRange: Bool
    let peak: UInt32?
    let target: MTLTexture
    let half: CVPixelBuffer
    let picture: CVPixelBuffer

    init(input: ThumbnailInput, track: AVAssetTrack, width: Int, height: Int) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
            let library = (try? device.makeDefaultLibrary(bundle: Bundle.main))
                ?? device.makeDefaultLibrary(),
            let pass = InputPass(device: device, library: library, label: "Frame Job analysis")
        else { throw AnalysisFrames.ReadError.unconvertible }
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
            == kCVReturnSuccess, let cache
        else { throw AnalysisFrames.ReadError.unconvertible }
        let descriptions =
            CompositionBuilder.keyed(track, "formatDescriptions") as? [CMFormatDescription] ?? []
        guard
            let conversion = input.color.flatMap(InputConversion.choose(input:))
                ?? descriptions.first.flatMap(InputConversion.choose(for:))
        else { throw AnalysisFrames.ReadError.unconvertible }
        var lut: MTLTexture?
        if case .lut = conversion {
            guard let url = input.lutURL, let lattice = LutTextures(device: device).texture(at: url)
            else { throw AnalysisFrames.ReadError.unconvertible }
            lut = lattice
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: max(1, width), height: max(1, height),
            mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor),
            let half = Self.buffer(kCVPixelFormatType_64RGBAHalf, width: width, height: height),
            let picture = Self.buffer(kCVPixelFormatType_32BGRA, width: width, height: height)
        else { throw AnalysisFrames.ReadError.unconvertible }
        self.device = device
        self.queue = queue
        self.pass = pass
        self.cache = cache
        self.conversion = conversion
        self.lut = lut
        fullRange = input.readsRange && CompositionBuilder.isFullRange(track)
        peak = input.color?.pq?.effectivePeak
        self.target = target
        self.half = half
        self.picture = picture
    }

    private static func buffer(_ format: OSType, width: Int, height: Int) -> CVPixelBuffer? {
        var out: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, max(1, width), max(1, height), format,
            attributes as CFDictionary, &out) == kCVReturnSuccess
        else { return nil }
        return out
    }

    /// `frame` through step 0 into the target, read back into `half`.
    func convert(_ frame: CVPixelBuffer) throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(frame)
        let height = CVPixelBufferGetHeight(frame)
        guard width == target.width, height == target.height,
            let format = MetalRenderer.metalFormat(for: CVPixelBufferGetPixelFormatType(frame))
        else { throw AnalysisFrames.ReadError.unconvertible }
        var wrapper: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, frame, nil, format, width, height, 0, &wrapper)
            == kCVReturnSuccess, let wrapper, let source = CVMetalTextureGetTexture(wrapper),
            let buffer = queue.makeCommandBuffer(),
            pass.encode(
                conversion, premultiplied: false, from: source, into: target, buffer: buffer,
                lut: lut, fullRange: fullRange, peak: peak, output: .sdr)
        else { throw AnalysisFrames.ReadError.unconvertible }
        buffer.commit()
        buffer.waitUntilCompleted()
        withExtendedLifetime(wrapper) {}
        guard buffer.status == .completed else { throw AnalysisFrames.ReadError.unconvertible }
        CVPixelBufferLockBaseAddress(half, [])
        defer { CVPixelBufferUnlockBaseAddress(half, []) }
        guard let base = CVPixelBufferGetBaseAddress(half) else {
            throw AnalysisFrames.ReadError.unconvertible
        }
        target.getBytes(
            base, bytesPerRow: CVPixelBufferGetBytesPerRow(half),
            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return half
    }

    /// `rounded` (8-bit BGRA rows) copied into the per-read 32BGRA buffer
    /// `Upright` reads.
    func bgra(_ rounded: AnalysisPicture) throws -> CVPixelBuffer {
        CVPixelBufferLockBaseAddress(picture, [])
        defer { CVPixelBufferUnlockBaseAddress(picture, []) }
        guard let base = CVPixelBufferGetBaseAddress(picture),
            CVPixelBufferGetWidth(picture) == rounded.width,
            CVPixelBufferGetHeight(picture) == rounded.height
        else { throw AnalysisFrames.ReadError.unconvertible }
        let row = CVPixelBufferGetBytesPerRow(picture)
        for y in 0..<rounded.height {
            memcpy(base + y * row, rounded.bytes + y * rounded.bytesPerRow, rounded.width * 4)
        }
        return picture
    }
}
