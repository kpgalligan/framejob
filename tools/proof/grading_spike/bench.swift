// tools/proof/grading_spike/bench.swift — the GPU half and the decode timer of
// road map "grading" GR0's spike (`grading_spike.py`). Compiled as `main.swift`
// over every other file in `app/Sources` through `swift_build.build(…,
// optimize=True)`, for the app's own types: it fills the app's `LayerUniforms`
// and hands the shader its first 104 floats (416 bytes, asserted below — the
// block the shader pinned at 4d742cc reads; the tree's own grew a tone group in
// grading GR2) followed by 16 grade floats (480 bytes, asserted),
// builds its pipelines the way `MetalRenderer.pipelineDescriptor` does with
// `MetalRenderer.workingFormat` (`rgba16Float`, spec §11 PR-1), and wraps #258's
// sources through a `CVMetalTextureCache` the way `Compositor.texture(from:live:)`
// does, in `MetalRenderer.metalFormat(for:)`'s format (the biplanar planes as
// `r16Unorm` and `rg16Unorm`, which the app has no case for).
//
//   bench --lib NAME=PATH … --width W --height H --frames N --runs R --warmup K
//         --seed S --out JSON
//   bench --decode PATH --format 32BGRA|64RGBAHalf|x420|x422 --frames N --runs R
//         --out JSON
//
// The libraries (`grading_spike.py` makes them from the tree's shader): V0 the
// tree unpatched; VF-T/VF-TL (a uniform flag), VC-T/VC-TL (function constants 2
// and 3), VA-T/VA-TL (always on), each without and with the look; VE (VF-TL with
// exposure and white balance on encoded values); VB (#258: `kBiplanar`, function
// constant 4, and the chroma plane at `texture(3)`).
//
// Scenes, full bleed: S1 one picture layer, ungraded; ST tone; STL tone and a
// 33³ look at 0.8; SA S1 then one full-frame adjustment pass carrying STL's
// grade; SH (#258) four video layers in five source forms. One command buffer
// per frame, committed and waited on, timed as `gpuEndTime − gpuStartTime`.
// Within a run every series is taken whole (warm-up, then N frames) in an order
// drawn from a seeded generator (the seed plus the run index). The K rows and
// P1 are readbacks, taken before any timing.
import AVFoundation
import CoreVideo
import Foundation
import Metal

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("bench: \(message)\n".utf8))
    exit(2)
}

// ---- arguments -------------------------------------------------------------

var libs: [String: String] = [:]
var width = 1920, height = 1080, frames = 200, runs = 3, warmup = 5
var seed: UInt64 = 1
var outPath = ""
var decodePath = ""
var decodeFormatName = ""
do {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let flag = it.next() {
        guard let value = it.next() else { fail("\(flag) takes a value") }
        switch flag {
        case "--lib":
            let parts = value.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { fail("--lib NAME=PATH") }
            libs[parts[0]] = parts[1]
        case "--width": width = Int(value) ?? 0
        case "--height": height = Int(value) ?? 0
        case "--frames": frames = Int(value) ?? 0
        case "--runs": runs = Int(value) ?? 0
        case "--warmup": warmup = Int(value) ?? 0
        case "--seed": seed = UInt64(value) ?? 0
        case "--out": outPath = value
        case "--decode": decodePath = value
        case "--format": decodeFormatName = value
        default: fail("unknown flag \(flag)")
        }
    }
}
guard frames > 0, runs > 0, !outPath.isEmpty else { fail("--frames, --runs and --out are required") }

func writeJSON(_ object: [String: Any]) {
    do {
        let data = try JSONSerialization.data(withJSONObject: object,
                                              options: [.sortedKeys, .prettyPrinted])
        try data.write(to: URL(fileURLWithPath: outPath))
    } catch { fail("could not write \(outPath): \(error)") }
    print("bench: wrote \(outPath)")
}

func fourCC(_ code: OSType) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
    return String(bytes: bytes, encoding: .ascii) ?? String(code)
}

func pixelFormat(named name: String) -> OSType? {
    switch name {
    case "32BGRA": return kCVPixelFormatType_32BGRA
    case "64RGBAHalf": return kCVPixelFormatType_64RGBAHalf
    case "x420": return kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
    case "x422": return kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange
    default: return nil
    }
}

// ---- the decode timer (D1) -------------------------------------------------

/// N frames of PATH's first video track through `AVAssetReader` into the named
/// `CVPixelBuffer` format, per run; frames per second of wall clock from
/// `startReading` to the Nth frame.
func runDecode() -> Never {
    guard let format = pixelFormat(named: decodeFormatName) else {
        fail("--format must be 32BGRA, 64RGBAHalf, x420 or x422")
    }
    let asset = AVURLAsset(url: URL(fileURLWithPath: decodePath))
    guard let track = asset.tracks(withMediaType: .video).first else {
        fail("\(decodePath) has no video track")
    }
    var results: [[String: Any]] = []
    for run in 0..<runs {
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { fail("reader: \(error)") }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(format),
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { fail("the reader will not take the output") }
        reader.add(output)
        let started = DispatchTime.now().uptimeNanoseconds
        guard reader.startReading() else {
            fail("startReading: \(String(describing: reader.error))")
        }
        var count = 0
        var delivered: OSType = 0
        while count < frames, let sample = output.copyNextSampleBuffer() {
            if let image = CMSampleBufferGetImageBuffer(sample) {
                delivered = CVPixelBufferGetPixelFormatType(image)
                count += 1
            }
        }
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
        if reader.status == .failed { fail("reading: \(String(describing: reader.error))") }
        reader.cancelReading()
        guard count > 0 else { fail("no frame was decoded") }
        guard delivered == format else {
            fail("asked for \(fourCC(format)), delivered \(fourCC(delivered))")
        }
        results.append(["run": run, "frames": count, "seconds": seconds,
                        "fps": Double(count) / seconds])
    }
    writeJSON(["path": decodePath, "format": decodeFormatName, "frames": frames,
               "delivered": fourCC(format), "runs": results])
    exit(0)
}
if !decodePath.isEmpty { runDecode() }

// ---- the GPU bench: what it was given ---------------------------------------

let routeVariants = ["VF-T", "VF-TL", "VC-T", "VC-TL", "VA-T", "VA-TL"].filter { libs[$0] != nil }
let lookRoutes = routeVariants.filter { $0.hasSuffix("-TL") }
let gradingVariants = routeVariants + (libs["VE"] != nil ? ["VE"] : [])
let adjustVariants = lookRoutes + (libs["VE"] != nil ? ["VE"] : [])
guard width > 0, height > 0, libs["V0"] != nil, libs["VB"] != nil, !lookRoutes.isEmpty else {
    fail("usage: --lib V0=… --lib VB=… --lib VF-TL=… (and the other variants) --width --height …")
}

/// The 16 grade floats the spike's shaders append to `LayerUniforms`, in the
/// shader's order.
struct GradeFields {
    var exposure: Float = 0
    var temperature: Float = 0
    var tint: Float = 0
    var highlights: Float = 0
    var shadows: Float = 0
    var whites: Float = 0
    var blacks: Float = 0
    var vibrance: Float = 0
    var fade: Float = 0
    var toneEnabled: Float = 0
    var lookAmount: Float = 0
    var lookEnabled: Float = 0
    var lookSize: Float = 2
    var reserved0: Float = 0
    var reserved1: Float = 0
    var reserved2: Float = 0
}

/// What every draw fills: the app's block, then the grade. What the shader is
/// HANDED is `packed(_:)`: the block's first 104 floats, then the grade.
struct GradeBlock {
    var layer = LayerUniforms()
    var grade = GradeFields()
}

/// The 104 floats every variant's shader reads before the grade: the block as
/// it stood at 4d742cc, which ends at `canvasPerDestY`.
let layerBytes = 416
guard MemoryLayout<LayerUniforms>.offset(of: \LayerUniforms.canvasPerDestY) == layerBytes - 4,
    MemoryLayout<LayerUniforms>.stride >= layerBytes
else {
    fail("LayerUniforms' first 104 floats do not end at \(layerBytes) bytes")
}
guard MemoryLayout<GradeFields>.stride == 64 else {
    fail("the grade is \(MemoryLayout<GradeFields>.stride) bytes, not 64")
}
let blockBytes = layerBytes + MemoryLayout<GradeFields>.stride
guard blockBytes == 480 else { fail("the handed block is \(blockBytes) bytes, not 480") }

/// `block` as the shader reads it: `LayerUniforms`' first 416 bytes, then the
/// 64-byte grade.
func packed(_ block: GradeBlock) -> [UInt8] {
    var layer = block.layer
    var grade = block.grade
    let head = withUnsafeBytes(of: &layer) { Array($0.prefix(layerBytes)) }
    let tail = withUnsafeBytes(of: &grade) { Array($0) }
    return head + tail
}

guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
else { fail("no Metal device") }
let workingFormat = MetalRenderer.workingFormat
guard workingFormat == .rgba16Float else { fail("the working format is not rgba16Float") }

// ---- pipelines, as `MetalRenderer.pipelineDescriptor` builds them ------------

var libraries: [String: MTLLibrary] = [:]
for (name, path) in libs {
    do { libraries[name] = try device.makeLibrary(URL: URL(fileURLWithPath: path)) } catch {
        fail("\(name): the metallib would not load: \(error)")
    }
}

func function(_ lib: String, _ name: String, _ constants: [Int: Bool]) -> MTLFunction {
    let values = MTLFunctionConstantValues()
    for (index, value) in constants {
        var flag = value
        values.setConstantValue(&flag, type: .bool, index: index)
    }
    do {
        return try libraries[lib]!.makeFunction(name: name, constantValues: values)
    } catch { fail("\(lib): \(name): \(error)") }
}

func pipelineState(_ vertex: MTLFunction, _ fragment: MTLFunction, format: MTLPixelFormat,
                   blending: Bool = true) -> MTLRenderPipelineState {
    let d = MTLRenderPipelineDescriptor()
    d.vertexFunction = vertex
    d.fragmentFunction = fragment
    d.colorAttachments[0].pixelFormat = format
    d.colorAttachments[0].isBlendingEnabled = blending
    if blending {
        d.colorAttachments[0].rgbBlendOperation = .add
        d.colorAttachments[0].alphaBlendOperation = .add
        d.colorAttachments[0].sourceRGBBlendFactor = .one
        d.colorAttachments[0].sourceAlphaBlendFactor = .one
        d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }
    do { return try device.makeRenderPipelineState(descriptor: d) } catch {
        fail("pipeline: \(error)")
    }
}

/// A layer pipeline of `lib`'s `framejob_layer_fragment` with these constants.
func layerState(_ lib: String, _ constants: [Int: Bool],
                format: MTLPixelFormat = workingFormat) -> MTLRenderPipelineState {
    var all = constants
    all[0] = false  // kGatherFilters: no layer here gathers
    return pipelineState(function(lib, "framejob_layer_vertex", all),
                         function(lib, "framejob_layer_fragment", all), format: format)
}

/// The adjustment pass: `framejob_adjust_fragment` over the full-canvas quad,
/// blending OFF (it reads `[[color(0)]]` and returns the finished pixel).
func adjustState(_ lib: String, format: MTLPixelFormat = workingFormat) -> MTLRenderPipelineState {
    var all: [Int: Bool] = [0: false]
    if lib.hasPrefix("VC") { all[2] = true; all[3] = true }
    return pipelineState(function(lib, "framejob_shadow_vertex", all),
                         function(lib, "framejob_adjust_fragment", all), format: format,
                         blending: false)
}

/// The three states a grading variant draws with: an ungraded layer, a toned
/// one, a toned and looked one. Only the VC routes have more than one.
struct VariantStates {
    let ungraded: MTLRenderPipelineState
    let tone: MTLRenderPipelineState
    let toneLook: MTLRenderPipelineState
    let adjust: MTLRenderPipelineState?
}

var states: [String: VariantStates] = [:]
for variant in gradingVariants {
    let adjust = adjustVariants.contains(variant) ? adjustState(variant) : nil
    if variant.hasPrefix("VC") {
        let off = layerState(variant, [2: false, 3: false])
        let tone = layerState(variant, [2: true, 3: false])
        let both = variant.hasSuffix("TL") ? layerState(variant, [2: true, 3: true]) : tone
        states[variant] = VariantStates(ungraded: off, tone: tone, toneLook: both, adjust: adjust)
    } else {
        let one = layerState(variant, [:])
        states[variant] = VariantStates(ungraded: one, tone: one, toneLook: one, adjust: adjust)
    }
}
let v0State = layerState("V0", [:])
let v0State8 = layerState("V0", [:], format: .bgra8Unorm)
let vbOn = layerState("VB", [4: true])
let vbOff = layerState("VB", [4: false])
let p1Library = lookRoutes.contains("VF-TL") ? "VF-TL" : lookRoutes[0]
let adjust16 = states[p1Library]!.adjust!
let adjust8 = adjustState(p1Library, format: .bgra8Unorm)

let samplerDescriptor = MTLSamplerDescriptor()
samplerDescriptor.minFilter = .linear
samplerDescriptor.magFilter = .linear
samplerDescriptor.sAddressMode = .clampToEdge
samplerDescriptor.tAddressMode = .clampToEdge
guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
    fail("no sampler")
}

// ---- textures --------------------------------------------------------------

typealias RGB = (Float, Float, Float)

func texture2D(_ format: MTLPixelFormat, _ w: Int, _ h: Int, target: Bool) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: format, width: w, height: h, mipmapped: false)
    d.usage = target ? [.shaderRead, .renderTarget] : [.shaderRead]
    d.storageMode = target ? .private : .shared
    guard let t = device.makeTexture(descriptor: d) else { fail("texture \(w)×\(h)") }
    return t
}

func halfBits(_ v: Float) -> UInt16 { Float16(v).bitPattern }

/// An `rgba16Float` picture, straight and opaque (PR-2's stand-in source).
func halfPicture(_ w: Int, _ h: Int, _ colour: (Int, Int) -> RGB) -> MTLTexture {
    var data = [UInt16](repeating: 0, count: w * h * 4)
    for y in 0..<h {
        for x in 0..<w {
            let c = colour(x, y)
            let i = (y * w + x) * 4
            data[i] = halfBits(c.0)
            data[i + 1] = halfBits(c.1)
            data[i + 2] = halfBits(c.2)
            data[i + 3] = halfBits(1)
        }
    }
    let t = texture2D(.rgba16Float, w, h, target: false)
    data.withUnsafeBytes {
        t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                  withBytes: $0.baseAddress!, bytesPerRow: w * 8)
    }
    return t
}

/// A 3D `rgba16Float` lattice of side `n`, red varying fastest (x), then
/// green (y), then blue (z): the `.cube` order.
func lattice(_ n: Int, _ map: (Float, Float, Float) -> RGB) -> MTLTexture {
    let d = MTLTextureDescriptor()
    d.textureType = .type3D
    d.pixelFormat = .rgba16Float
    d.width = n
    d.height = n
    d.depth = n
    d.usage = [.shaderRead]
    d.storageMode = .shared
    guard let t = device.makeTexture(descriptor: d) else { fail("3D texture \(n)") }
    var data = [UInt16](repeating: 0, count: n * n * n * 4)
    let step = 1 / Float(n - 1)
    for b in 0..<n {
        for g in 0..<n {
            for r in 0..<n {
                let c = map(Float(r) * step, Float(g) * step, Float(b) * step)
                let i = ((b * n + g) * n + r) * 4
                data[i] = halfBits(c.0)
                data[i + 1] = halfBits(c.1)
                data[i + 2] = halfBits(c.2)
                data[i + 3] = halfBits(1)
            }
        }
    }
    data.withUnsafeBytes {
        t.replace(region: MTLRegionMake3D(0, 0, 0, n, n, n), mipmapLevel: 0, slice: 0,
                  withBytes: $0.baseAddress!, bytesPerRow: n * 8, bytesPerImage: n * n * 8)
    }
    return t
}

let W = width, H = height
// The S scenes' picture: red runs with x, green with y, blue a fine checker.
let picture = halfPicture(W, H) { x, y in
    (0.1 + 0.8 * Float(x) / Float(max(W - 1, 1)), 0.1 + 0.8 * Float(y) / Float(max(H - 1, 1)),
     ((x / 8 + y / 8) % 2 == 0) ? 0.3 : 0.7)
}
let mattePlaceholder: MTLTexture = {
    let t = texture2D(.bgra8Unorm, 1, 1, target: false)
    var white: UInt32 = 0xFFFF_FFFF
    t.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &white,
              bytesPerRow: 4)
    return t
}()
let identity2 = lattice(2) { ($0, $1, $2) }
let identity33 = lattice(33) { ($0, $1, $2) }
let swap33 = lattice(33) { ($2, $1, $0) }
// A smooth non-identity look: a gentle S-curve, a warm shift, a little more
// saturation — textbook shapes, Frame Job's own numbers.
let smooth33 = lattice(33) { r, g, b in
    func curve(_ v: Float) -> Float { v - 0.12 * sin(2 * Float.pi * v) / (2 * Float.pi) }
    let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
    let sat: (Float) -> Float = { luma + ($0 - luma) * 1.2 }
    return (min(max(curve(sat(r)) + 0.03, 0), 1), min(max(curve(sat(g)), 0), 1),
            min(max(curve(sat(b)) - 0.03, 0), 1))
}
let destination = texture2D(workingFormat, W, H, target: true)
let background = MTLClearColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)

// ---- #258's sources: IOSurface-backed pixel buffers --------------------------

let textureCache: CVMetalTextureCache = {
    var cache: CVMetalTextureCache?
    let usage = MTLTextureUsage([.shaderRead, .renderTarget]).rawValue
    CVMetalTextureCacheCreate(
        kCFAllocatorDefault, [kCVMetalTextureUsage: usage] as CFDictionary, device, nil, &cache)
    guard let cache else { fail("no texture cache") }
    return cache
}()

func pixelBuffer(_ format: OSType, _ w: Int, _ h: Int) -> CVPixelBuffer {
    let attributes: [String: Any] = [
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, w, h, format,
                                     attributes as CFDictionary, &buffer)
    guard status == kCVReturnSuccess, let buffer else {
        fail("CVPixelBufferCreate \(fourCC(format)) \(w)×\(h): \(status)")
    }
    return buffer
}

/// 10-bit video-range BT.709 codes for an encoded RGB colour.
func videoCodes(_ c: RGB) -> (UInt16, UInt16, UInt16) {
    let y = 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2
    let cb = (c.2 - y) / 1.8556
    let cr = (c.0 - y) / 1.5748
    func code(_ v: Float) -> UInt16 { UInt16(min(max(v.rounded(), 0), 1023)) }
    return (code(64 + 876 * y), code(512 + 896 * cb), code(512 + 896 * cr))
}

/// Fill a pixel buffer on the CPU from an encoded RGB picture, in its own form:
/// BGRA bytes, RGBA halves, or 10-bit codes MSB-aligned in 16-bit words.
func fillBuffer(_ buffer: CVPixelBuffer, _ colour: (Int, Int) -> RGB) {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let format = CVPixelBufferGetPixelFormatType(buffer)
    let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
    switch format {
    case kCVPixelFormatType_32BGRA:
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { fail("no base address") }
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let p = base.assumingMemoryBound(to: UInt8.self)
        func byte(_ v: Float) -> UInt8 { UInt8(min(max((v * 255).rounded(), 0), 255)) }
        for y in 0..<h {
            for x in 0..<w {
                let c = colour(x, y)
                let i = y * row + x * 4
                p[i] = byte(c.2)
                p[i + 1] = byte(c.1)
                p[i + 2] = byte(c.0)
                p[i + 3] = 255
            }
        }
    case kCVPixelFormatType_64RGBAHalf:
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { fail("no base address") }
        let row = CVPixelBufferGetBytesPerRow(buffer) / 2
        let p = base.assumingMemoryBound(to: UInt16.self)
        for y in 0..<h {
            for x in 0..<w {
                let c = colour(x, y)
                let i = y * row + x * 4
                p[i] = halfBits(c.0)
                p[i + 1] = halfBits(c.1)
                p[i + 2] = halfBits(c.2)
                p[i + 3] = halfBits(1)
            }
        }
    case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
         kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange:
        guard let lumaBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
            let chromaBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)
        else { fail("no plane base address") }
        let lumaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) / 2
        let chromaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) / 2
        let cw = CVPixelBufferGetWidthOfPlane(buffer, 1)
        let ch = CVPixelBufferGetHeightOfPlane(buffer, 1)
        let luma = lumaBase.assumingMemoryBound(to: UInt16.self)
        let chroma = chromaBase.assumingMemoryBound(to: UInt16.self)
        for y in 0..<h {
            for x in 0..<w { luma[y * lumaRow + x] = videoCodes(colour(x, y)).0 << 6 }
        }
        let sx = w / cw, sy = h / ch
        for y in 0..<ch {
            for x in 0..<cw {
                let codes = videoCodes(colour(x * sx + sx / 2, y * sy + sy / 2))
                chroma[y * chromaRow + x * 2] = codes.1 << 6
                chroma[y * chromaRow + x * 2 + 1] = codes.2 << 6
            }
        }
    default:
        fail("cannot fill \(fourCC(format))")
    }
}

/// One plane of a buffer through the texture cache — `Compositor.texture(from:
/// live:)`'s call shape — with its wrapper kept in `live` until the frame's
/// command buffer completes.
func wrap(_ buffer: CVPixelBuffer, plane: Int, _ format: MTLPixelFormat,
          _ live: inout [CVMetalTexture]) -> MTLTexture {
    let planar = CVPixelBufferIsPlanar(buffer)
    let w = planar ? CVPixelBufferGetWidthOfPlane(buffer, plane) : CVPixelBufferGetWidth(buffer)
    let h = planar ? CVPixelBufferGetHeightOfPlane(buffer, plane) : CVPixelBufferGetHeight(buffer)
    var wrapper: CVMetalTexture?
    let status = CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault, textureCache, buffer, nil, format, w, h, plane, &wrapper)
    guard status == kCVReturnSuccess, let wrapper, let texture = CVMetalTextureGetTexture(wrapper)
    else { fail("CVMetalTextureCacheCreateTextureFromImage plane \(plane): \(status)") }
    live.append(wrapper)
    return texture
}

/// A single-plane buffer wrapped in the app's own format for it.
func wrapSingle(_ buffer: CVPixelBuffer, _ live: inout [CVMetalTexture]) -> MTLTexture {
    guard let format = MetalRenderer.metalFormat(for: CVPixelBufferGetPixelFormatType(buffer))
    else { fail("metalFormat(for:) has no case for this buffer") }
    return wrap(buffer, plane: 0, format, &live)
}

let forms: [(name: String, format: OSType)] = [
    ("B8", kCVPixelFormatType_32BGRA), ("H16", kCVPixelFormatType_64RGBAHalf),
    ("X420", kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange),
    ("X422", kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange),
]

// ---- encoding --------------------------------------------------------------

func fullBleed(_ w: Int, _ h: Int, sourceW: Int? = nil, sourceH: Int? = nil,
               anchorX: Float? = nil, anchorY: Float? = nil, scale: Float = 1) -> GradeBlock {
    var b = GradeBlock()
    b.layer.canvasWidth = Float(w)
    b.layer.canvasHeight = Float(h)
    b.layer.anchorX = anchorX ?? Float(w) / 2
    b.layer.anchorY = anchorY ?? Float(h) / 2
    b.layer.sourceWidth = Float(sourceW ?? w)
    b.layer.sourceHeight = Float(sourceH ?? h)
    b.layer.scale = scale
    b.layer.opacity = 1
    b.layer.premultiplied = 0
    b.layer.canvasPerDestX = 1
    b.layer.canvasPerDestY = 1
    return b
}

var toneST = GradeFields()
toneST.exposure = 0.5
toneST.temperature = 0.2
toneST.tint = -0.1
toneST.highlights = -0.2
toneST.shadows = 0.2
toneST.whites = 0.1
toneST.blacks = -0.1
toneST.vibrance = 0.2
toneST.fade = 0.1
toneST.toneEnabled = 1
var toneSTL = toneST
toneSTL.lookAmount = 0.8
toneSTL.lookEnabled = 1
toneSTL.lookSize = 33

func pass(_ buffer: MTLCommandBuffer, _ target: MTLTexture, load: Bool = false,
          clear: MTLClearColor = background, _ body: (MTLRenderCommandEncoder) -> Void) {
    let d = MTLRenderPassDescriptor()
    d.colorAttachments[0].texture = target
    d.colorAttachments[0].loadAction = load ? .load : .clear
    d.colorAttachments[0].clearColor = clear
    d.colorAttachments[0].storeAction = .store
    guard let encoder = buffer.makeRenderCommandEncoder(descriptor: d) else { fail("encoder") }
    body(encoder)
    encoder.endEncoding()
}

func drawLayer(_ e: MTLRenderCommandEncoder, _ state: MTLRenderPipelineState,
               _ source: MTLTexture, _ block: GradeBlock, look: MTLTexture = identity2,
               chroma: MTLTexture? = nil) {
    let b = packed(block)
    e.setRenderPipelineState(state)
    e.setVertexBytes(b, length: blockBytes, index: 0)
    e.setFragmentBytes(b, length: blockBytes, index: 0)
    e.setFragmentTexture(source, index: 0)
    e.setFragmentTexture(mattePlaceholder, index: 1)
    e.setFragmentTexture(look, index: 2)
    e.setFragmentTexture(chroma ?? mattePlaceholder, index: 3)
    e.setFragmentSamplerState(sampler, index: 0)
    e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
}

func drawAdjust(_ e: MTLRenderCommandEncoder, _ state: MTLRenderPipelineState,
                _ block: GradeBlock, look: MTLTexture = identity2) {
    let b = packed(block)
    e.setRenderPipelineState(state)
    e.setFragmentBytes(b, length: blockBytes, index: 0)
    e.setFragmentTexture(look, index: 2)
    e.setFragmentSamplerState(sampler, index: 0)
    e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
}

func block(_ grade: GradeFields) -> GradeBlock {
    var b = fullBleed(W, H)
    b.grade = grade
    return b
}

/// Encode one frame of a (variant, scene) into `buffer`.
func encodeGrading(_ variant: String, _ scene: String, _ buffer: MTLCommandBuffer) {
    if variant == "V0" || variant == "V0b" {
        pass(buffer, destination) { drawLayer($0, v0State, picture, block(GradeFields())) }
        return
    }
    let s = states[variant]!
    switch scene {
    case "S1":
        pass(buffer, destination) { drawLayer($0, s.ungraded, picture, block(GradeFields())) }
    case "ST":
        pass(buffer, destination) { drawLayer($0, s.tone, picture, block(toneST)) }
    case "STL":
        pass(buffer, destination) {
            drawLayer($0, s.toneLook, picture, block(toneSTL), look: smooth33)
        }
    case "SA":
        guard let adjust = s.adjust else { fail("\(variant) has no adjustment pipeline") }
        pass(buffer, destination) {
            drawLayer($0, s.ungraded, picture, block(GradeFields()))
            drawAdjust($0, adjust, block(toneSTL), look: smooth33)
        }
    default:
        fail("unknown scene \(scene)")
    }
}

// ---- readback --------------------------------------------------------------

/// Row `y` of a target as [0, 1] RGBA floats (an `rgba16Float` or a
/// `bgra8Unorm` target).
func readRow(_ texture: MTLTexture, _ y: Int, encode: ((MTLCommandBuffer) -> Void)? = nil)
    -> [Float]
{
    let w = texture.width
    let bpp = texture.pixelFormat == .bgra8Unorm ? 4 : 8
    guard let out = device.makeBuffer(length: w * bpp, options: .storageModeShared),
        let buffer = queue.makeCommandBuffer()
    else { fail("readback buffer") }
    encode?(buffer)
    guard let blit = buffer.makeBlitCommandEncoder() else { fail("blit") }
    blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
              sourceOrigin: MTLOrigin(x: 0, y: y, z: 0),
              sourceSize: MTLSize(width: w, height: 1, depth: 1), to: out,
              destinationOffset: 0, destinationBytesPerRow: w * bpp,
              destinationBytesPerImage: w * bpp)
    blit.endEncoding()
    buffer.commit()
    buffer.waitUntilCompleted()
    if let error = buffer.error { fail("readback: \(error)") }
    if bpp == 4 {
        let p = out.contents().bindMemory(to: UInt8.self, capacity: w * 4)
        var values = [Float](repeating: 0, count: w * 4)
        for x in 0..<w {
            let i = x * 4
            values[i] = Float(p[i + 2]) / 255  // BGRA to RGBA
            values[i + 1] = Float(p[i + 1]) / 255
            values[i + 2] = Float(p[i]) / 255
            values[i + 3] = Float(p[i + 3]) / 255
        }
        return values
    }
    let p = out.contents().bindMemory(to: UInt16.self, capacity: w * 4)
    return (0..<(w * 4)).map { Float(Float16(bitPattern: p[$0])) }
}

/// The whole of an `rgba16Float` target, as half bit patterns.
func readHalves(_ texture: MTLTexture, encode: (MTLCommandBuffer) -> Void) -> [UInt16] {
    let w = texture.width, h = texture.height
    guard let out = device.makeBuffer(length: w * h * 8, options: .storageModeShared),
        let buffer = queue.makeCommandBuffer()
    else { fail("readback buffer") }
    encode(buffer)
    guard let blit = buffer.makeBlitCommandEncoder() else { fail("blit") }
    blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
              sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
              sourceSize: MTLSize(width: w, height: h, depth: 1), to: out,
              destinationOffset: 0, destinationBytesPerRow: w * 8,
              destinationBytesPerImage: w * h * 8)
    blit.endEncoding()
    buffer.commit()
    buffer.waitUntilCompleted()
    if let error = buffer.error { fail("readback: \(error)") }
    let p = out.contents().bindMemory(to: UInt16.self, capacity: w * h * 4)
    return Array(UnsafeBufferPointer(start: p, count: w * h * 4))
}

func srgbDecode(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
func srgbEncode(_ v: Double) -> Double {
    let c = min(max(v, 0), 1)
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
}
func r4(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }

var kRows: [[String: Any]] = []
func k(_ row: String, _ variant: String, _ ok: Bool, _ detail: String) {
    kRows.append(["row": row, "variant": variant, "ok": ok, "detail": detail])
}

// ---- K1: an ungraded layer under every grading variant equals V0 -------------

do {
    let reference = readHalves(destination) { encodeGrading("V0", "S1", $0) }
    for variant in gradingVariants {
        let got = readHalves(destination) { encodeGrading(variant, "S1", $0) }
        var worst: Float = 0
        var at = 0
        for i in 0..<got.count {
            let d = abs(Float(Float16(bitPattern: got[i])) - Float(Float16(bitPattern: reference[i])))
            if d > worst { worst = d; at = i }
        }
        let ok = worst <= 1.0 / 1023
        k("K1", variant, ok, "S1 max |Δ| against V0 \(r4(Double(worst))) "
          + "(\(r4(Double(worst) * 1023)) / 1023) at pixel \(at / 4) channel \(at % 4); bound 1/1023")
    }
}

// ---- K2: +1 EV on a flat 0.5 grey, per route ---------------------------------

let grey = halfPicture(16, 16) { _, _ in (0.5, 0.5, 0.5) }
let small = texture2D(workingFormat, 16, 16, target: true)
do {
    let want = srgbEncode(min(1, 2 * srgbDecode(0.5)))
    var grade = GradeFields()
    grade.exposure = 1
    grade.toneEnabled = 1
    var b = fullBleed(16, 16)
    b.grade = grade
    for variant in routeVariants {
        let state = states[variant]!.tone
        let row = readRow(small, 8) { buffer in
            pass(buffer, small) { drawLayer($0, state, grey, b) }
        }
        let got = (0..<3).map { Double(row[8 * 4 + $0]) }
        let worst = got.map { abs($0 - want) }.max() ?? 1
        k("K2", variant, worst <= 1.0 / 255, "0.5 grey at +1 EV gave \(got.map(r4)), want "
          + "encode(min(1, 2·decode(0.5))) = \(r4(want)) ± 1/255 (off \(r4(worst * 255)) levels)")
    }
}

// ---- K3: an identity look changes nothing; a channel swap swaps --------------

let kPicture = halfPicture(64, 64) { x, y in
    (Float(x) / 63, Float(y) / 63, Float(x + y) / 126)
}
let kTarget = texture2D(workingFormat, 64, 64, target: true)
let swapSource = halfPicture(16, 16) { _, _ in (0.2, 0.5, 0.8) }
do {
    var lookOne = GradeFields()
    lookOne.lookEnabled = 1
    lookOne.lookSize = 33
    lookOne.lookAmount = 1
    var lookZero = lookOne
    lookZero.lookAmount = 0
    for variant in lookRoutes {
        let state = states[variant]!.toneLook
        var b1 = fullBleed(64, 64), b0 = fullBleed(64, 64)
        b1.grade = lookOne
        b0.grade = lookZero
        let one = readHalves(kTarget) { buffer in
            pass(buffer, kTarget) { drawLayer($0, state, kPicture, b1, look: identity33) }
        }
        let zero = readHalves(kTarget) { buffer in
            pass(buffer, kTarget) { drawLayer($0, state, kPicture, b0, look: identity33) }
        }
        var worst: Float = 0
        for i in 0..<one.count {
            worst = max(worst, abs(Float(Float16(bitPattern: one[i]))
                                   - Float(Float16(bitPattern: zero[i]))))
        }
        var bs = fullBleed(16, 16)
        bs.grade = lookOne
        let row = readRow(small, 8) { buffer in
            pass(buffer, small) { drawLayer($0, state, swapSource, bs, look: swap33) }
        }
        let got = (0..<3).map { Double(row[8 * 4 + $0]) }
        let want = [0.8, 0.5, 0.2]
        let swapWorst = zip(got, want).map { abs($0 - $1) }.max() ?? 1
        k("K3", variant, worst <= 1.0 / 1023 && swapWorst <= 1.0 / 255,
          "identity 33³ at amount 1 against amount 0: max |Δ| \(r4(Double(worst))) "
          + "(bound 1/1023); channel swap on (0.2, 0.5, 0.8) gave \(got.map(r4)), "
          + "want (0.8, 0.5, 0.2) ± 1/255")
    }
}

// ---- K4 and P1: the 256-column grey ramp -------------------------------------

let rampW = 256, rampH = 8
let ramp: MTLTexture = {
    var bytes = [UInt8](repeating: 255, count: rampW * rampH * 4)
    for y in 0..<rampH {
        for x in 0..<rampW {
            let i = (y * rampW + x) * 4
            bytes[i] = UInt8(x)
            bytes[i + 1] = UInt8(x)
            bytes[i + 2] = UInt8(x)
        }
    }
    let t = texture2D(.bgra8Unorm, rampW, rampH, target: false)
    bytes.withUnsafeBytes {
        t.replace(region: MTLRegionMake2D(0, 0, rampW, rampH), mipmapLevel: 0,
                  withBytes: $0.baseAddress!, bytesPerRow: rampW * 4)
    }
    return t
}()
let rampTarget = texture2D(workingFormat, rampW, rampH, target: true)
let rampTarget8 = texture2D(.bgra8Unorm, rampW, rampH, target: true)
let black = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

func exposureBlock(_ ev: Float) -> GradeBlock {
    var b = fullBleed(rampW, rampH)
    b.grade.exposure = ev
    b.grade.toneEnabled = 1
    return b
}

do {
    for variant in lookRoutes {
        let adjust = states[variant]!.adjust!
        let row = readRow(rampTarget, rampH / 2) { buffer in
            pass(buffer, rampTarget, clear: black) {
                drawLayer($0, v0State, ramp, fullBleed(rampW, rampH))
                drawAdjust($0, adjust, exposureBlock(1))
            }
        }
        var worst = 0.0
        var at = 0
        for i in 0..<rampW {
            let want = srgbEncode(min(1, 2 * srgbDecode(Double(i) / 255)))
            let d = (0..<3).map { abs(Double(row[i * 4 + $0]) - want) }.max() ?? 1
            if d > worst { worst = d; at = i }
        }
        k("K4", variant, worst <= 1.0 / 255,
          "the adjustment pass at +1 EV over the 256-column ramp: worst column \(at) off by "
          + "\(r4(worst * 255)) levels from encode(min(1, 2·decode(i/255))) (bound 1 level)")
    }
}

/// −1 EV then +1 EV as two adjustment passes, each its own render pass so the
/// intermediate is stored in the target's own format between them.
func stacked(_ target: MTLTexture, layer: MTLRenderPipelineState,
             adjust: MTLRenderPipelineState) -> [String: Any] {
    let row = readRow(target, rampH / 2) { buffer in
        pass(buffer, target, clear: black) { drawLayer($0, layer, ramp, fullBleed(rampW, rampH)) }
        pass(buffer, target, load: true) { drawAdjust($0, adjust, exposureBlock(-1)) }
        pass(buffer, target, load: true) { drawAdjust($0, adjust, exposureBlock(1)) }
    }
    var levels = Set<Int>()
    var worst = 0.0
    for i in 0..<rampW {
        let v = Double(row[i * 4 + 1])
        levels.insert(Int((v * 255).rounded()))
        worst = max(worst, abs(v * 255 - Double(i)))
    }
    return ["distinct_levels": levels.count, "max_delta_levels": r4(worst)]
}
let p1: [String: Any] = [
    "library": p1Library,
    "rgba16Float": stacked(rampTarget, layer: v0State, adjust: adjust16),
    "bgra8Unorm": stacked(rampTarget8, layer: v0State8, adjust: adjust8),
]

// ---- K5: the colour bars in the four buffer forms ----------------------------

let bars: [RGB] = [(0.75, 0.75, 0.75), (0.75, 0.75, 0), (0, 0.75, 0.75), (0, 0.75, 0),
                   (0.75, 0, 0.75), (0.75, 0, 0), (0, 0, 0.75), (0, 0, 0)]
do {
    var readings: [String: [Double]] = [:]
    for form in forms {
        let buffer = pixelBuffer(form.format, W, H)
        fillBuffer(buffer) { x, _ in bars[min(x * 8 / W, 7)] }
        var live: [CVMetalTexture] = []
        let biplanar = form.name.hasPrefix("X")
        let luma = biplanar ? wrap(buffer, plane: 0, .r16Unorm, &live) : wrapSingle(buffer, &live)
        let chroma = biplanar ? wrap(buffer, plane: 1, .rg16Unorm, &live) : nil
        let row = readRow(destination, H / 2) { command in
            pass(command, destination) {
                drawLayer($0, biplanar ? vbOn : v0State, luma, fullBleed(W, H), chroma: chroma)
            }
        }
        withExtendedLifetime(live) {}
        readings[form.name] = (0..<8).flatMap { band -> [Double] in
            let x = (2 * band + 1) * W / 16
            return (0..<3).map { Double(row[x * 4 + $0]) }
        }
    }
    let reference = readings["H16"]!
    for (name, bound) in [("B8", 1.0), ("X420", 2.0), ("X422", 2.0)] {
        let got = readings[name]!
        var worst = 0.0
        var at = 0
        for i in 0..<got.count where abs(got[i] - reference[i]) > worst {
            worst = abs(got[i] - reference[i])
            at = i
        }
        k("K5", name, worst <= bound / 255,
          "8 band centres against H16: worst \(r4(worst * 255)) levels at band \(at / 3) "
          + "channel \(at % 3) (bound \(Int(bound)) levels); band 1 \(Array(got[3..<6]).map(r4)) "
          + "against \(Array(reference[3..<6]).map(r4))")
    }
}

// ---- SH (#258): four video layers per source form ----------------------------

/// Four distinct pictures per form, each the full canvas size.
var shSources: [String: [CVPixelBuffer]] = [:]
for form in forms {
    shSources[form.name] = (0..<4).map { index in
        let buffer = pixelBuffer(form.format, W, H)
        let shift = Float(index) * 0.17
        fillBuffer(buffer) { x, y in
            let u = Float(x) / Float(W), v = Float(y) / Float(H)
            return ((u + shift).truncatingRemainder(dividingBy: 1),
                    (v + 2 * shift).truncatingRemainder(dividingBy: 1),
                    ((x / 16 + y / 16 + index) % 2 == 0) ? 0.25 : 0.75)
        }
        return buffer
    }
}
// One full bleed, two at half scale in opposite quarters, one at 0.35.
let shPlacements: [GradeBlock] = [
    fullBleed(W, H),
    fullBleed(W, H, anchorX: Float(W) / 4, anchorY: Float(H) / 4, scale: 0.5),
    fullBleed(W, H, anchorX: Float(W) * 3 / 4, anchorY: Float(H) * 3 / 4, scale: 0.5),
    fullBleed(W, H, scale: 0.35),
]

func encodeSH(_ series: String, _ buffer: MTLCommandBuffer) -> [CVMetalTexture] {
    var live: [CVMetalTexture] = []
    let form: String
    let state: MTLRenderPipelineState
    switch series {
    case "B8": form = "B8"; state = v0State
    case "H16", "H16b": form = "H16"; state = v0State
    case "X420": form = "X420"; state = vbOn
    case "X422": form = "X422"; state = vbOn
    case "VB0": form = "H16"; state = vbOff
    default: fail("unknown SH series \(series)")
    }
    let biplanar = form.hasPrefix("X")
    let textures: [(MTLTexture, MTLTexture?)] = shSources[form]!.map { source in
        biplanar
            ? (wrap(source, plane: 0, .r16Unorm, &live), wrap(source, plane: 1, .rg16Unorm, &live))
            : (wrapSingle(source, &live), nil)
    }
    pass(buffer, destination) { e in
        for (index, placement) in shPlacements.enumerated() {
            drawLayer(e, state, textures[index].0, placement, chroma: textures[index].1)
        }
    }
    return live
}

// ---- timing ----------------------------------------------------------------

struct SeriesPlan {
    let name: String
    let encode: (MTLCommandBuffer) -> [CVMetalTexture]
}

var plan: [SeriesPlan] = []
func grading(_ variant: String, _ scene: String) {
    plan.append(SeriesPlan(name: "\(variant):\(scene)") { encodeGrading(variant, scene, $0); return [] })
}
grading("V0", "S1")
grading("V0b", "S1")
for variant in gradingVariants { grading(variant, "S1") }
for variant in routeVariants { grading(variant, "ST") }
for variant in adjustVariants { grading(variant, "STL") }
for variant in lookRoutes { grading(variant, "SA") }
for series in ["B8", "H16", "H16b", "X420", "X422", "VB0"] {
    plan.append(SeriesPlan(name: "\(series):SH") { encodeSH(series, $0) })
}

func frameMilliseconds(_ series: SeriesPlan) -> Double {
    guard let buffer = queue.makeCommandBuffer() else { fail("command buffer") }
    let live = series.encode(buffer)
    buffer.commit()
    buffer.waitUntilCompleted()
    withExtendedLifetime(live) {}
    if let error = buffer.error { fail("\(series.name): \(error)") }
    return (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
}

/// SplitMix64: the order of a run is a permutation drawn from seed + run.
struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func median(_ values: [Double]) -> Double {
    let s = values.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

var samples: [String: [[String: Double]]] = [:]
var orders: [[String]] = []
// A failed K row makes every figure meaningless (the driver scores it a FAIL and
// reads no time), so the GPU time is not spent.
if kRows.contains(where: { ($0["ok"] as? Bool) != true }) { runs = 0 }
for run in 0..<runs {
    var rng = SplitMix(state: seed &+ UInt64(run))
    var order = Array(plan.indices)
    for i in stride(from: order.count - 1, to: 0, by: -1) {
        let j = Int(rng.next() % UInt64(i + 1))
        order.swapAt(i, j)
    }
    orders.append(order.map { plan[$0].name })
    for index in order {
        let series = plan[index]
        for _ in 0..<warmup { _ = frameMilliseconds(series) }
        let times = (0..<frames).map { _ in frameMilliseconds(series) }
        samples[series.name, default: []].append(
            ["median": median(times), "min": times.min()!, "max": times.max()!])
    }
}

writeJSON([
    "width": W, "height": H, "frames": frames, "runs": runs, "warmup": warmup,
    "seed": seed, "gpu": device.name, "uniform_bytes": blockBytes,
    "layer_uniform_bytes": MemoryLayout<LayerUniforms>.stride,
    "k": kRows, "p1": p1, "samples": samples, "orders": orders,
])
