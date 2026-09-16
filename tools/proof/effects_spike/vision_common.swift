// The Vision spike's shared helpers (2026-09-15): loading a still into the
// pixel buffer AVAssetReader would hand the app (32BGRA, IOSurface-backed),
// the requests under test with a compute-device choice, and turning whatever
// mask a request returns into 8-bit bytes that can be hashed, compared,
// downscaled and encoded. Compiled into both vision_stills and vision_job.

import Accelerate
import CoreML
import CoreVideo
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

// MARK: - clocks and output

func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
func ms(_ a: UInt64, _ b: UInt64) -> Double { Double(b &- a) / 1e6 }

func median(_ xs: [Double]) -> Double {
    let s = xs.sorted()
    guard !s.isEmpty else { return .nan }
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

func percentile(_ xs: [Double], _ p: Double) -> Double {
    let s = xs.sorted()
    guard !s.isEmpty else { return .nan }
    return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
}

func peakRSSMB() -> Double {
    var u = rusage()
    getrusage(RUSAGE_SELF, &u)
    return Double(u.ru_maxrss) / 1_048_576
}

func f(_ x: Double, _ d: Int = 2) -> String { String(format: "%.\(d)f", x) }

func fourCC(_ t: OSType) -> String {
    let c = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((t >> $0) & 0xff))) }
    return String(c)
}

func sha(_ bytes: [UInt8]) -> String {
    SHA256.hash(data: bytes).prefix(8).map { String(format: "%02x", $0) }.joined()
}

func die(_ s: String) -> Never {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
    exit(2)
}

// MARK: - frames

func makeBGRA(width: Int, height: Int) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    let attrs: [CFString: Any] = [
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ]
    let r = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
    guard r == kCVReturnSuccess, let pb else { die("CVPixelBufferCreate \(r)") }
    return pb
}

/// A PNG/JPEG still drawn into a 32BGRA IOSurface buffer, optionally at another size.
func loadFrame(_ path: String, width: Int? = nil, height: Int? = nil) -> CVPixelBuffer {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { die("cannot read \(path)") }
    let w = width ?? img.width, h = height ?? img.height
    let pb = makeBGRA(width: w, height: h)
    CVPixelBufferLockBaseAddress(pb, [])
    defer { CVPixelBufferUnlockBaseAddress(pb, []) }
    let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info) else { die("CGContext") }
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return pb
}

// MARK: - devices

/// `cpuforce` sets the CPU on `.main` whether or not the request lists it
/// (to see what a request with no CPU path does when asked for one).
enum Device: String, CaseIterable { case auto, cpu, gpu, ane, cpuforce }

func describe(_ d: MLComputeDevice) -> String {
    switch d {
    case .cpu: return "cpu"
    case .gpu(let g): return "gpu(\(g.metalDevice.name))"
    case .neuralEngine(let n): return "ane(\(n.totalCoreCount) cores)"
    @unknown default: return "unknown"
    }
}

/// Pins every stage the request supports to the named device class, or
/// leaves Vision to choose (`auto`). Returns false if a stage has no such device.
@discardableResult
func pin(_ req: VNRequest, _ dev: Device) -> Bool {
    guard dev != .auto else { return true }
    if dev == .cpuforce {
        let cpu = MLComputeDevice.allComputeDevices.first { if case .cpu = $0 { return true }; return false }
        req.setComputeDevice(cpu, for: .main)
        return true
    }
    guard let stages = try? req.supportedComputeStageDevices else { return false }
    var ok = true
    for (stage, devices) in stages {
        let pick = devices.first { d in
            switch (d, dev) {
            case (.cpu, .cpu), (.cpu, .cpuforce), (.gpu, .gpu), (.neuralEngine, .ane): return true
            default: return false
            }
        }
        if let pick { req.setComputeDevice(pick, for: stage) } else { ok = false }
    }
    return ok
}

// MARK: - the requests under test

enum Kind: String, CaseIterable {
    case personFast = "person-fast", personBalanced = "person-balanced", personAccurate = "person-accurate"
    case fgObserve = "fg-observe"      // perform only; the instance-label buffer
    case fgMask = "fg-mask"            // perform + generateMask(forInstances: all) — native mask size
    case fgScaled = "fg-scaled"        // perform + generateScaledMaskForImage — image size

    var isPerson: Bool { rawValue.hasPrefix("person") }
}

func makeRequest(_ k: Kind) -> VNImageBasedRequest {
    switch k {
    case .personFast, .personBalanced, .personAccurate:
        let r = VNGeneratePersonSegmentationRequest()
        r.qualityLevel = k == .personFast ? .fast : k == .personBalanced ? .balanced : .accurate
        r.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return r
    case .fgObserve, .fgMask, .fgScaled:
        return VNGenerateForegroundInstanceMaskRequest()
    }
}

struct Mask {
    var width = 0, height = 0
    var format: OSType = 0
    var bytes: [UInt8] = []      // 8-bit, row-packed (width*height)
    var rawHash = ""             // hash of the buffer's own sample bytes (float for fg)
    var instances = 0
    var observations = 0
}

/// Copies a one-component buffer out as row-packed bytes. Floats become
/// round(clamp(v,0,1)*255); the raw sample bytes are hashed as well.
func extract(_ pb: CVPixelBuffer) -> (bytes: [UInt8], rawHash: String, w: Int, h: Int, fmt: OSType) {
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
    let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
    let fmt = CVPixelBufferGetPixelFormatType(pb)
    let bpr = CVPixelBufferGetBytesPerRow(pb)
    let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
    var out = [UInt8](repeating: 0, count: w * h)
    var raw: [UInt8] = []
    switch fmt {
    case kCVPixelFormatType_OneComponent8:
        for y in 0..<h { for x in 0..<w { out[y * w + x] = base[y * bpr + x] } }
        raw = out
    case kCVPixelFormatType_OneComponent32Float:
        if hashRawSamples { raw.reserveCapacity(w * h * 4) }
        for y in 0..<h {
            let row = UnsafeRawPointer(base + y * bpr).assumingMemoryBound(to: Float32.self)
            for x in 0..<w {
                let v = row[x]
                out[y * w + x] = UInt8(max(0, min(255, (v * 255).rounded())))
                if hashRawSamples { withUnsafeBytes(of: v) { raw.append(contentsOf: $0) } }
            }
        }
    default:
        die("unhandled mask format \(fourCC(fmt))")
    }
    return (out, hashRawSamples ? sha(raw) : "", w, h, fmt)
}

/// The job instrument turns this off: hashing 4 bytes a pixel is not work the app would do.
nonisolated(unsafe) var hashRawSamples = true

/// Wall time of the last `run`'s Vision work alone (handler, perform, and the
/// mask generation call), excluding the copy-out and hashing that follow.
nonisolated(unsafe) var lastVisionMs = 0.0
nonisolated(unsafe) var runStartNs: UInt64 = 0

/// One perform of `kind` on `frame` with `req` (reused or fresh, the caller decides).
func run(_ kind: Kind, _ req: VNImageBasedRequest, _ frame: CVPixelBuffer) throws -> Mask {
    runStartNs = nowNs()
    let handler = VNImageRequestHandler(cvPixelBuffer: frame, options: [:])
    try handler.perform([req])
    return try collect(kind, req, handler)
}

func collect(_ kind: Kind, _ req: VNImageBasedRequest, _ handler: VNImageRequestHandler?) throws -> Mask {
    var m = Mask()
    if kind.isPerson {
        let obs = (req as! VNGeneratePersonSegmentationRequest).results ?? []
        m.observations = obs.count
        guard let o = obs.first else { lastVisionMs = ms(runStartNs, nowNs()); return m }
        lastVisionMs = ms(runStartNs, nowNs())
        let e = extract(o.pixelBuffer)
        (m.bytes, m.rawHash, m.width, m.height, m.format) = (e.bytes, e.rawHash, e.w, e.h, e.fmt)
        return m
    }
    let obs = (req as! VNGenerateForegroundInstanceMaskRequest).results ?? []
    m.observations = obs.count
    guard let o = obs.first else { lastVisionMs = ms(runStartNs, nowNs()); return m }
    m.instances = o.allInstances.count
    let pb: CVPixelBuffer
    switch kind {
    case .fgObserve: pb = o.instanceMask
    case .fgMask:
        guard m.instances > 0 else { lastVisionMs = ms(runStartNs, nowNs()); return m }
        pb = try o.generateMask(forInstances: o.allInstances)
    default:
        guard m.instances > 0, let handler else { lastVisionMs = ms(runStartNs, nowNs()); return m }
        pb = try o.generateScaledMaskForImage(forInstances: o.allInstances, from: handler)
    }
    lastVisionMs = ms(runStartNs, nowNs())
    let e = extract(pb)
    (m.bytes, m.rawHash, m.width, m.height, m.format) = (e.bytes, e.rawHash, e.w, e.h, e.fmt)
    return m
}

// MARK: - mask arithmetic

struct Coverage { var over127 = 0.0, nonzero = 0.0, mean = 0.0, max = 0 }

func coverage(_ b: [UInt8]) -> Coverage {
    guard !b.isEmpty else { return Coverage() }
    var over = 0, nz = 0, sum = 0, mx = 0
    for v in b { let i = Int(v); if i > 127 { over += 1 }; if i > 0 { nz += 1 }; sum += i; if i > mx { mx = i } }
    let n = Double(b.count)
    return Coverage(over127: Double(over) / n, nonzero: Double(nz) / n, mean: Double(sum) / n, max: mx)
}

func covString(_ c: Coverage) -> String {
    "cover>127 \(f(c.over127 * 100, 2))%  nonzero \(f(c.nonzero * 100, 2))%  mean \(f(c.mean, 2))  max \(c.max)"
}

struct Diff { var differing = 0, maxAbs = 0, mad = 0.0, over32 = 0.0 }

func diff(_ a: [UInt8], _ b: [UInt8]) -> Diff {
    guard a.count == b.count, !a.isEmpty else { return Diff(differing: -1) }
    var d = Diff(), sum = 0, o32 = 0
    for i in 0..<a.count {
        let x = abs(Int(a[i]) - Int(b[i]))
        if x != 0 { d.differing += 1 }
        if x > d.maxAbs { d.maxAbs = x }
        if x > 32 { o32 += 1 }
        sum += x
    }
    d.mad = Double(sum) / Double(a.count)
    d.over32 = Double(o32) / Double(a.count)
    return d
}

/// vImage (CPU, deterministic) resample so the long edge is `longEdge`, keeping the mask's aspect.
func downscale(_ b: [UInt8], _ w: Int, _ h: Int, longEdge: Int) -> (bytes: [UInt8], w: Int, h: Int) {
    let s = Double(longEdge) / Double(max(w, h))
    let dw = max(1, Int((Double(w) * s).rounded())), dh = max(1, Int((Double(h) * s).rounded()))
    return (resize(b, w, h, dw, dh), dw, dh)
}

/// vImage resample of a planar 8-bit mask to exactly `dw`×`dh`.
func resize(_ b: [UInt8], _ w: Int, _ h: Int, _ dw: Int, _ dh: Int) -> [UInt8] {
    var src = b
    var dst = [UInt8](repeating: 0, count: dw * dh)
    src.withUnsafeMutableBytes { sp in
        dst.withUnsafeMutableBytes { dp in
            var si = vImage_Buffer(data: sp.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w)
            var di = vImage_Buffer(data: dp.baseAddress, height: vImagePixelCount(dh), width: vImagePixelCount(dw), rowBytes: dw)
            _ = vImageScale_Planar8(&si, &di, nil, vImage_Flags(kvImageHighQualityResampling))
        }
    }
    return dst
}

func pngData(_ b: [UInt8], _ w: Int, _ h: Int) -> Data {
    let cf = CFDataCreate(nil, b, b.count)!
    let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                      provider: CGDataProvider(data: cf)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    return out as Data
}

func lzfseSize(_ b: [UInt8]) -> Int {
    let data = Data(b)
    return (try? (data as NSData).compressed(using: .lzfse))?.length ?? -1
}
