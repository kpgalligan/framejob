import CoreGraphics
import Foundation
import Metal

/// One frame's luma waveform (spec §11 GR-5): for each of 256 column bins of
/// the picture, how many pixels sit at each of 256 levels of Rec. 709 luma Y′
/// on the encoded (sRGB) values. What View ▸ Waveform draws and what
/// `render_frame {waveform}` writes beside its PNG — one type, so the panel and
/// the tool cannot count differently.
///
/// A pixel clips HIGH at level 255 (Y′ ≥ 254.5/255, what an 8-bit file writes
/// as 255) and LOW at level 0 (Y′ < 0.5/255); a column is marked when at least
/// `markShare` of its pixels clip.
struct WaveformTrace: Equatable {
    static let columns = 256
    static let levels = 256
    /// The share of a column's pixels that must clip for its mark: 0.5 %.
    static let markShare = 0.005

    /// `counts[column * levels + level]`.
    let counts: [UInt32]
    /// The analysed frame's size in pixels.
    let width: Int
    let height: Int

    /// Pixels at level 255, over every column.
    var clippedHigh: Int { clipped(level: Self.levels - 1) }
    /// Pixels at level 0, over every column.
    var clippedLow: Int { clipped(level: 0) }

    /// The whole frame's share clipping high, in percent.
    var highlightsPercent: Double { percent(clippedHigh) }
    /// The whole frame's share clipping low, in percent.
    var shadowsPercent: Double { percent(clippedLow) }

    /// "Highlights clipped 12.5 %" — the panel's first readout.
    var highlightsReadout: String { "Highlights clipped " + Self.spelled(highlightsPercent) }
    /// "Shadows clipped 0.0 %" — the panel's second readout.
    var shadowsReadout: String { "Shadows clipped " + Self.spelled(shadowsPercent) }

    /// The readouts before the first frame has been analysed.
    static let noHighlights = "Highlights clipped —"
    static let noShadows = "Shadows clipped —"

    /// A percentage as every readout spells it: one decimal, then " %".
    static func spelled(_ percent: Double) -> String {
        String(format: "%.1f %%", percent)
    }

    /// The column bins where at least `markShare` of the column's pixels clip
    /// high (`high`) or low.
    func marks(high: Bool) -> [Int] {
        let level = high ? Self.levels - 1 : 0
        return (0..<Self.columns).filter { column in
            let base = column * Self.levels
            let total = counts[base..<(base + Self.levels)].reduce(0) { $0 + Int($1) }
            return total > 0 && Double(counts[base + level]) >= Self.markShare * Double(total)
        }
    }

    /// What `render_frame {waveform}` writes: the counts as 256 arrays, one
    /// per column bin, each indexed by level, and every figure the panel shows.
    func json() -> [String: Any] {
        let byColumn = (0..<Self.columns).map { column in
            counts[(column * Self.levels)..<((column + 1) * Self.levels)].map { Int($0) }
        }
        return [
            "columns": Self.columns, "levels": Self.levels, "width": width, "height": height,
            "counts": byColumn, "clipped_high": clippedHigh, "clipped_low": clippedLow,
            "marks_high": marks(high: true), "marks_low": marks(high: false),
            "highlights": highlightsPercent, "shadows": shadowsPercent,
        ]
    }

    private func clipped(level: Int) -> Int {
        (0..<Self.columns).reduce(0) { $0 + Int(counts[$1 * Self.levels + level]) }
    }

    private func percent(_ count: Int) -> Double {
        100 * Double(count) / Double(max(width * height, 1))
    }
}

/// The waveform's GPU pass (`Waveform.metal`'s `reelcut_waveform_bin`): one
/// thread per pixel, an atomic add into a 256 × 256 counts buffer.
///
/// Two callers. `WaveformTaps` encodes the pass into a command buffer of its
/// own over the compositor's finished destination (`encode`), never waiting;
/// `render_frame {waveform}` analyses the frame it just rendered and waits
/// (`analyze(image:)`), off the main thread like the rest of that tool.
final class WaveformAnalyzer {
    /// Over the app's default library, where Xcode compiles every shader in
    /// `app/Resources/Shaders`; nil on a machine with no Metal device (and in
    /// an instrument with no library, which builds its own through `init`).
    static let shared: WaveformAnalyzer? = {
        guard let device = MTLCreateSystemDefaultDevice(),
            let library = (try? device.makeDefaultLibrary(bundle: Bundle.main))
                ?? device.makeDefaultLibrary()
        else { return nil }
        return WaveformAnalyzer(device: device, library: library)
    }()

    let device: MTLDevice
    private let pipeline: MTLComputePipelineState
    /// Only `analyze`'s; the tap encodes into a queue of its own.
    private let queue: MTLCommandQueue

    static let countsLength =
        WaveformTrace.columns * WaveformTrace.levels * MemoryLayout<UInt32>.stride

    init?(device: MTLDevice, library: MTLLibrary) {
        guard let function = library.makeFunction(name: "reelcut_waveform_bin"),
            let pipeline = try? device.makeComputePipelineState(function: function),
            let queue = device.makeCommandQueue()
        else { return nil }
        self.device = device
        self.pipeline = pipeline
        self.queue = queue
    }

    /// Encodes the pass over `frame` into `buffer` and answers the counts
    /// buffer it will fill, readable once `buffer` has completed.
    func encode(_ frame: MTLTexture, into buffer: MTLCommandBuffer) -> MTLBuffer? {
        guard let counts = device.makeBuffer(length: Self.countsLength, options: .storageModeShared),
            let encoder = buffer.makeComputeCommandEncoder()
        else { return nil }
        memset(counts.contents(), 0, Self.countsLength)
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(frame, index: 0)
        encoder.setBuffer(counts, offset: 0, index: 0)
        let across = pipeline.threadExecutionWidth
        let down = max(1, pipeline.maxTotalThreadsPerThreadgroup / across)
        encoder.dispatchThreads(
            MTLSize(width: frame.width, height: frame.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: across, height: down, depth: 1))
        encoder.endEncoding()
        return counts
    }

    /// The trace a completed pass left in `counts`, for a `width` × `height`
    /// frame.
    func trace(of counts: MTLBuffer, width: Int, height: Int) -> WaveformTrace {
        let count = WaveformTrace.columns * WaveformTrace.levels
        let bound = counts.contents().bindMemory(to: UInt32.self, capacity: count)
        return WaveformTrace(
            counts: Array(UnsafeBufferPointer(start: bound, count: count)), width: width,
            height: height)
    }

    /// The trace of `texture`, waiting for the GPU.
    func analyze(texture: MTLTexture) -> WaveformTrace? {
        guard let buffer = queue.makeCommandBuffer(),
            let counts = encode(texture, into: buffer)
        else { return nil }
        buffer.commit()
        buffer.waitUntilCompleted()
        guard buffer.status == .completed else { return nil }
        return trace(of: counts, width: texture.width, height: texture.height)
    }

    /// The trace of a rendered image: drawn into an RGBA half-float bitmap in
    /// the image's OWN colour space (no conversion, so the encoded values are
    /// the image's), uploaded, then the kernel.
    func analyze(image: CGImage) -> WaveformTrace? {
        let width = image.width
        let height = image.height
        let own = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        guard width > 0, height > 0,
            let space = own ?? CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 16,
                bytesPerRow: width * 8, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder16Little.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        guard let data = context.data, let texture = device.makeTexture(descriptor: descriptor)
        else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: data,
            bytesPerRow: context.bytesPerRow)
        return analyze(texture: texture)
    }
}
