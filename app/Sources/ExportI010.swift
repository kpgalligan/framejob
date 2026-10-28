import CoreVideo
import Metal
import MetalPerformanceShaders

/// One picture for a bundled encoder: planar 4:2:0 in one shared buffer (spec §11 CX-14 (3),
/// CX-16 (3)) — luma, then Cb at `cbOffset`, then Cr at `crOffset`, each row `lumaStride` or
/// `chromaStride` samples. Strides and offsets count samples: at a `bitDepth` of 10 each is
/// 16 bits holding its 10 bits in the low bits, little-endian (I010, yuv420p10le); at 8 each
/// is one byte (I420, yuv420p).
struct I010Frame {
    let buffer: MTLBuffer
    let width: Int
    let height: Int
    let lumaStride: Int
    let chromaStride: Int
    let cbOffset: Int
    let crOffset: Int
    /// 10 (I010) or 8 (I420): the bytes a sample takes are `bitDepth > 8 ? 2 : 1`.
    let bitDepth: Int
    /// `vp9_alpha_webm`'s second picture (spec §11 CX-17 (2)), 8-bit, after the first: its
    /// luma, Y = round(255 · clamp(a)) at `lumaStride`, then one chroma plane of a constant 128
    /// at `chromaStride`, which stands for both Cb and Cr. In samples; nil off the alpha row.
    let alphaOffset: Int?
    let alphaChromaOffset: Int?
}

/// `framejob_export_alpha8`'s uniforms, field for field; in samples.
private struct ExportAlphaUniforms {
    var width: UInt32
    var height: UInt32
    var lumaStride: UInt32
    var alphaOffset: UInt32
}

/// `ExportI010.metal`'s uniforms, field for field; strides and offsets in samples.
private struct ExportI010Uniforms {
    var width: UInt32
    var height: UInt32
    var lumaStride: UInt32
    var chromaStride: UInt32
    var cbOffset: UInt32
    var crOffset: UInt32
    var kr: Float
    var kb: Float
}

/// The compositor's 64RGBAHalf frames as video-range I010 for the AV1 rows and `vp9_webm`'s
/// HDR pictures, or as video-range I420 for `vp9_webm`'s SDR picture (spec §11 CX-12 (5),
/// CX-14 (3), CX-16 (3)), through the picture's matrix (`ExportAV1Picture.lumaWeights`), on
/// the GPU: `MPSImageLanczosScale` to the export size when it is not the canvas — the
/// picture fitted inside with black bars, or filling a frame within a pixel of the canvas's
/// shape (`fills`, G-33 (c)) — then `framejob_export_i010` or, at 8 bits,
/// `framejob_export_i420`. With `alpha` (`vp9_alpha_webm`, CX-17 (2)) each frame also has
/// its alpha as a second 8-bit picture, written by `framejob_export_alpha8` from the same
/// (scaled) texture.
///
/// Called on the export's video queue alone; the planes come from a pool the encode queue
/// gives back through `recycle` once the encoder has copied them.
final class ExportI010Converter {
    let width: Int
    let height: Int

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    /// `framejob_export_alpha8`, nil off the alpha row.
    private let alphaPipeline: MTLComputePipelineState?
    private let cache: CVMetalTextureCache
    /// The scaler, its transform and clip, and the export-size texture it writes; nil when
    /// the export is at the canvas size.
    private let scaler: MPSImageLanczosScale?
    private let scaled: MTLTexture?
    private var transform = MPSScaleTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0)
    private let weights: (kr: Float, kb: Float)
    /// In samples.
    private let lumaStride: Int
    private let chromaStride: Int
    /// 10 or 8: the kernel and the bytes per sample.
    private let bitDepth: Int
    /// In bytes: two per sample at 10 bits, one at 8; with the alpha planes on the alpha row.
    private let length: Int
    private let alpha: Bool

    private let lock = NSLock()
    private var pool: [I010Frame] = []

    init(
        width: Int, height: Int, canvas: CGSize, fills: Bool, picture: ExportAV1Picture,
        bitDepth: Int = 10, alpha: Bool = false, pool count: Int
    ) throws {
        func failure(_ what: String) -> Exporter.ExportError {
            .failed("The frames could not be prepared for the encoder: \(what).")
        }
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw failure("no Metal device") }
        guard let library = (try? device.makeDefaultLibrary(bundle: Bundle.main))
            ?? device.makeDefaultLibrary(),
            let function = library.makeFunction(
                name: bitDepth > 8 ? "framejob_export_i010" : "framejob_export_i420"),
            let pipeline = try? device.makeComputePipelineState(function: function)
        else { throw failure("the conversion kernel is missing") }
        var alphaPipeline: MTLComputePipelineState?
        if alpha {
            guard bitDepth == 8, let function = library.makeFunction(name: "framejob_export_alpha8"),
                let made = try? device.makeComputePipelineState(function: function)
            else { throw failure("the alpha kernel is missing") }
            alphaPipeline = made
        }
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
            == kCVReturnSuccess, let cache
        else { throw failure("no texture cache") }
        self.width = width
        self.height = height
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.alphaPipeline = alphaPipeline
        self.alpha = alpha
        self.cache = cache
        weights = picture.lumaWeights
        lumaStride = width
        chromaStride = (width + 1) / 2
        self.bitDepth = bitDepth
        let pictureSamples = lumaStride * height + 2 * chromaStride * ((height + 1) / 2)
        let alphaSamples = alpha ? lumaStride * height + chromaStride * ((height + 1) / 2) : 0
        length = (bitDepth > 8 ? 2 : 1) * pictureSamples + alphaSamples

        let canvasWidth = Int(canvas.width.rounded())
        let canvasHeight = Int(canvas.height.rounded())
        if canvasWidth == width && canvasHeight == height || canvasWidth < 1 || canvasHeight < 1 {
            scaler = nil
            scaled = nil
        } else {
            let made = try Self.scaling(
                device: device, size: (width, height), canvas: canvas, fills: fills)
            scaler = made.scaler
            scaled = made.texture
            transform = made.transform
        }
        for _ in 0..<max(1, count) {
            pool.append(try makeFrame())
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ExportI010Converter does not support NSCoder")
    }

    /// The Lanczos scaler, its transform and clip, and a destination cleared to black once:
    /// a fit writes only the picture's rectangle, so the bars stay black on every frame.
    private static func scaling(
        device: MTLDevice, size: (Int, Int), canvas: CGSize, fills: Bool
    ) throws -> (scaler: MPSImageLanczosScale, texture: MTLTexture, transform: MPSScaleTransform) {
        let (w, h) = (Double(size.0), Double(size.1))
        let (cw, ch) = (Double(canvas.width), Double(canvas.height))
        let s = fills ? max(w / cw, h / ch) : min(w / cw, h / ch)
        let (pw, ph) = (cw * s, ch * s)
        let transform = MPSScaleTransform(
            scaleX: s, scaleY: s, translateX: (w - pw) / 2, translateY: (h - ph) / 2)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: size.0, height: size.1, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw Exporter.ExportError.failed(
                "The frames could not be prepared for the encoder: no scaling texture.")
        }
        let zeros = [UInt16](repeating: 0, count: size.0 * size.1 * 4)
        texture.replace(
            region: MTLRegionMake2D(0, 0, size.0, size.1), mipmapLevel: 0, withBytes: zeros,
            bytesPerRow: size.0 * 8)
        let scaler = MPSImageLanczosScale(device: device)
        if !fills {
            let x = max(0, Int(((w - pw) / 2).rounded()))
            let y = max(0, Int(((h - ph) / 2).rounded()))
            scaler.clipRect = MTLRegionMake2D(
                x, y, min(size.0 - x, Int(pw.rounded())), min(size.1 - y, Int(ph.rounded())))
        }
        return (scaler, texture, transform)
    }

    private func makeFrame() throws -> I010Frame {
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw Exporter.ExportError.failed(
                "The frames could not be prepared for the encoder: no plane buffer.")
        }
        let chromaSamples = chromaStride * ((height + 1) / 2)
        let alphaOffset = lumaStride * height + 2 * chromaSamples
        let alphaChroma = alphaOffset + lumaStride * height
        if alpha {
            // The alpha picture's chroma is a constant 128, written once per pooled frame.
            memset(buffer.contents() + alphaChroma, 128, chromaSamples)
        }
        return I010Frame(
            buffer: buffer, width: width, height: height, lumaStride: lumaStride,
            chromaStride: chromaStride, cbOffset: lumaStride * height,
            crOffset: lumaStride * height + chromaSamples, bitDepth: bitDepth,
            alphaOffset: alpha ? alphaOffset : nil, alphaChromaOffset: alpha ? alphaChroma : nil)
    }

    /// One frame converted, waiting for the GPU; nil when it could not be wrapped or the
    /// GPU failed.
    func convert(_ frame: CVPixelBuffer) -> I010Frame? {
        guard let source = wrap(frame), let texture = CVMetalTextureGetTexture(source),
            let out = take(), let commands = queue.makeCommandBuffer()
        else { return nil }
        var input = texture
        if let scaler, let scaled {
            withUnsafePointer(to: &transform) { pointer in
                scaler.scaleTransform = pointer
                scaler.encode(
                    commandBuffer: commands, sourceTexture: texture, destinationTexture: scaled)
                scaler.scaleTransform = nil
            }
            input = scaled
        }
        guard let encoder = commands.makeComputeCommandEncoder() else {
            recycle(out)
            return nil
        }
        var uniforms = ExportI010Uniforms(
            width: UInt32(width), height: UInt32(height), lumaStride: UInt32(lumaStride),
            chromaStride: UInt32(chromaStride), cbOffset: UInt32(out.cbOffset),
            crOffset: UInt32(out.crOffset), kr: weights.kr, kb: weights.kb)
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(input, index: 0)
        encoder.setBuffer(out.buffer, offset: 0, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<ExportI010Uniforms>.stride, index: 1)
        let group = MTLSize(width: 16, height: 16, depth: 1)
        let blocks = MTLSize(width: (width + 1) / 2, height: (height + 1) / 2, depth: 1)
        encoder.dispatchThreads(blocks, threadsPerThreadgroup: group)
        if let alphaPipeline, let alphaOffset = out.alphaOffset {
            var alphaUniforms = ExportAlphaUniforms(
                width: UInt32(width), height: UInt32(height), lumaStride: UInt32(lumaStride),
                alphaOffset: UInt32(alphaOffset))
            encoder.setComputePipelineState(alphaPipeline)
            encoder.setBytes(
                &alphaUniforms, length: MemoryLayout<ExportAlphaUniforms>.stride, index: 1)
            encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1), threadsPerThreadgroup: group)
        }
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        withExtendedLifetime(source) {}
        guard commands.status == .completed else {
            recycle(out)
            return nil
        }
        return out
    }

    /// Gives a frame's planes back to the pool.
    func recycle(_ frame: I010Frame) {
        lock.lock()
        pool.append(frame)
        lock.unlock()
    }

    private func take() -> I010Frame? {
        lock.lock()
        let frame = pool.popLast()
        lock.unlock()
        return frame ?? (try? makeFrame())
    }

    /// The frame as a Metal texture over the same IOSurface.
    private func wrap(_ frame: CVPixelBuffer) -> CVMetalTexture? {
        CVMetalTextureCacheFlush(cache, 0)
        var wrapper: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, frame, nil, .rgba16Float,
            CVPixelBufferGetWidth(frame), CVPixelBufferGetHeight(frame), 0, &wrapper)
        return status == kCVReturnSuccess ? wrapper : nil
    }
}
