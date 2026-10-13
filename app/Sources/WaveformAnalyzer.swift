import CoreGraphics
import Foundation
import Metal

/// One frame's luma waveform (spec §11 GR-5): for each of 256 column bins of
/// the picture, how many pixels sit at each of 256 levels of Rec. 709 luma Y′
/// on the encoded (sRGB) values. What View ▸ Scopes' Waveform draws and what
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

/// The scopes' GPU passes (`Waveform.metal`: `framejob_waveform_bin`,
/// `framejob_parade_bin`, `framejob_vectorscope_bin`, `framejob_histogram_bin`;
/// spec §11 GR-5, GR-10): one thread per pixel, each kind into a counts
/// buffer of its own, under GR-10's counting rule.
///
/// Two callers. `WaveformTaps` encodes the shown kinds' passes into ONE
/// command buffer of its own over the compositor's finished destination
/// (`encode`), never waiting; `render_frame {waveform, parade, vectorscope,
/// histogram}` analyses the frame it just rendered and waits
/// (`analyze(image:kinds:)`), off the main thread like the rest of that tool.
/// Every iteration over a set of kinds runs in `ScopeKind.allCases` order.
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

    /// Each kind's kernel.
    static let functions: [ScopeKind: String] = [
        .waveform: "framejob_waveform_bin", .parade: "framejob_parade_bin",
        .vectorscope: "framejob_vectorscope_bin", .histogram: "framejob_histogram_bin",
    ]

    let device: MTLDevice
    private let pipelines: [ScopeKind: MTLComputePipelineState]
    /// Only `analyze`'s; the tap encodes into a queue of its own.
    private let queue: MTLCommandQueue

    /// The parade's threadgroup width, `kParadeBands`' premise in
    /// `Waveform.metal`.
    static let paradeAcross = 8

    /// The number of counters a kind's pass fills.
    static func countsCount(_ kind: ScopeKind) -> Int {
        let plane = WaveformTrace.columns * WaveformTrace.levels
        switch kind {
        case .waveform: return plane
        case .parade: return 3 * plane
        case .vectorscope: return VectorscopeTrace.bins * VectorscopeTrace.bins
        case .histogram: return 4 * WaveformTrace.levels
        }
    }

    /// A kind's counts buffer, in bytes.
    static func countsLength(_ kind: ScopeKind) -> Int {
        countsCount(kind) * MemoryLayout<UInt32>.stride
    }

    /// Fails unless all four kernels are in `library`.
    init?(device: MTLDevice, library: MTLLibrary) {
        var pipelines: [ScopeKind: MTLComputePipelineState] = [:]
        for kind in ScopeKind.allCases {
            guard let name = Self.functions[kind], let function = library.makeFunction(name: name),
                let pipeline = try? device.makeComputePipelineState(function: function)
            else { return nil }
            pipelines[kind] = pipeline
        }
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.pipelines = pipelines
        self.queue = queue
    }

    /// Encodes each of `kinds`' passes over `frame` into `buffer`, in
    /// `ScopeKind.allCases` order, and answers each kind's counts buffer,
    /// readable once `buffer` has completed.
    func encode(_ kinds: Set<ScopeKind>, frame: MTLTexture, into buffer: MTLCommandBuffer)
        -> [ScopeKind: MTLBuffer]?
    {
        guard let encoder = buffer.makeComputeCommandEncoder() else { return nil }
        var made: [ScopeKind: MTLBuffer] = [:]
        for kind in ScopeKind.allCases where kinds.contains(kind) {
            let length = Self.countsLength(kind)
            guard let pipeline = pipelines[kind],
                let counts = device.makeBuffer(length: length, options: .storageModeShared)
            else {
                encoder.endEncoding()
                return nil
            }
            memset(counts.contents(), 0, length)
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(frame, index: 0)
            encoder.setBuffer(counts, offset: 0, index: 0)
            // The parade's threadgroups are 8 px wide, so each spans at
            // most the two column bins its kernel counts per band.
            let across = kind == .parade ? Self.paradeAcross : pipeline.threadExecutionWidth
            let down = max(1, pipeline.maxTotalThreadsPerThreadgroup / across)
            encoder.dispatchThreads(
                MTLSize(width: frame.width, height: frame.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: across, height: down, depth: 1))
            made[kind] = counts
        }
        encoder.endEncoding()
        return made
    }

    /// The waveform's pass alone (`encode(_:frame:into:)` with `.waveform`).
    func encode(_ frame: MTLTexture, into buffer: MTLCommandBuffer) -> MTLBuffer? {
        encode([.waveform], frame: frame, into: buffer)?[.waveform]
    }

    /// The trace a completed `kind` pass left in `counts`, for a `width` ×
    /// `height` frame.
    func trace(_ kind: ScopeKind, of counts: MTLBuffer, width: Int, height: Int) -> ScopeTrace {
        let count = Self.countsCount(kind)
        let bound = counts.contents().bindMemory(to: UInt32.self, capacity: count)
        let values = Array(UnsafeBufferPointer(start: bound, count: count))
        switch kind {
        case .waveform:
            return .waveform(WaveformTrace(counts: values, width: width, height: height))
        case .parade:
            return .parade(ParadeTrace(counts: values, width: width, height: height))
        case .vectorscope:
            return .vectorscope(VectorscopeTrace(counts: values, width: width, height: height))
        case .histogram:
            return .histogram(HistogramTrace(counts: values, width: width, height: height))
        }
    }

    /// The waveform trace a completed pass left in `counts`.
    func trace(of counts: MTLBuffer, width: Int, height: Int) -> WaveformTrace {
        let count = Self.countsCount(.waveform)
        let bound = counts.contents().bindMemory(to: UInt32.self, capacity: count)
        return WaveformTrace(
            counts: Array(UnsafeBufferPointer(start: bound, count: count)), width: width,
            height: height)
    }

    /// `kinds`' traces of `texture`, waiting for the GPU.
    func analyze(texture: MTLTexture, kinds: Set<ScopeKind>) -> [ScopeKind: ScopeTrace]? {
        guard let buffer = queue.makeCommandBuffer(),
            let counts = encode(kinds, frame: texture, into: buffer)
        else { return nil }
        buffer.commit()
        buffer.waitUntilCompleted()
        guard buffer.status == .completed else { return nil }
        var traces: [ScopeKind: ScopeTrace] = [:]
        for kind in ScopeKind.allCases {
            guard let buffer = counts[kind] else { continue }
            traces[kind] = trace(kind, of: buffer, width: texture.width, height: texture.height)
        }
        return traces
    }

    /// The waveform trace of `texture`, waiting for the GPU.
    func analyze(texture: MTLTexture) -> WaveformTrace? {
        guard case .waveform(let trace)? = analyze(texture: texture, kinds: [.waveform])?[.waveform]
        else { return nil }
        return trace
    }

    /// `kinds`' traces of a rendered image: drawn into an RGBA half-float
    /// bitmap in the image's OWN colour space (no conversion, so the encoded
    /// values are the image's), uploaded, then the kernels.
    func analyze(image: CGImage, kinds: Set<ScopeKind>) -> [ScopeKind: ScopeTrace]? {
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
        return analyze(texture: texture, kinds: kinds)
    }

    /// The waveform trace of a rendered image.
    func analyze(image: CGImage) -> WaveformTrace? {
        guard case .waveform(let trace)? = analyze(image: image, kinds: [.waveform])?[.waveform]
        else { return nil }
        return trace
    }
}
