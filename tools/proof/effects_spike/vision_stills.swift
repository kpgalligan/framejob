// vision_stills — the Vision spike's still-frame instrument (2026-09-15).
//
//   shape  <frame>                          q1: API shape, sizes, formats, revisions, devices
//   cold   <frame> <kind> [device]          q2: first-call cost in a fresh process (then call 2 and 3)
//   warm   <frame> <kind> <n> [device] [WxH] q2: warm per-frame wall time, median/p90 of n
//   det    <frame> <kind> <device> <dir>    q3: in-process repeatability; writes/compares <dir>/…raw across processes
//   cmp    <a.raw> <b.raw>                  q3: byte difference of two dumped masks
//   content <frame>...                      q4/q5: what every request returns, and coverage
//   cache  <frame>...                       q6: bytes per cached mask in four encodings
//
// kinds: person-fast person-balanced person-accurate fg-observe fg-mask fg-scaled
// devices: auto cpu gpu ane

import CoreVideo
import Foundation
import Vision

@main
struct VisionStills {
    static func main() throws {
        var a = CommandLine.arguments.dropFirst()
        guard let cmd = a.popFirst() else { die("usage: see header") }
        let args = Array(a)
        switch cmd {
        case "shape": try shape(args[0])
        case "cold": try cold(args[0], Kind(rawValue: args[1])!, Device(rawValue: args.count > 2 ? args[2] : "auto")!)
        case "warm": try warm(args)
        case "det": try det(args[0], Kind(rawValue: args[1])!, Device(rawValue: args[2])!, args[3])
        case "cmp": cmp(args[0], args[1])
        case "content": try content(args)
        case "cache": try cache(args)
        default: die("unknown command \(cmd)")
        }
    }

    // MARK: q1

    static func shape(_ path: String) throws {
        print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let frame = loadFrame(path)
        print("input \(CVPixelBufferGetWidth(frame))x\(CVPixelBufferGetHeight(frame)) \(fourCC(CVPixelBufferGetPixelFormatType(frame)))")

        let p = VNGeneratePersonSegmentationRequest()
        print("\nVNGeneratePersonSegmentationRequest: superclass \(String(describing: VNGeneratePersonSegmentationRequest.superclass()!))")
        print("  supportedRevisions \(Array(VNGeneratePersonSegmentationRequest.supportedRevisions)) default \(VNGeneratePersonSegmentationRequest.defaultRevision) current \(VNGeneratePersonSegmentationRequest.currentRevision)")
        print("  default qualityLevel \(p.qualityLevel.rawValue) (0 accurate, 1 balanced, 2 fast) outputPixelFormat \(fourCC(p.outputPixelFormat)) revision \(p.revision)")
        if let s = try? p.supportedComputeStageDevices {
            for (stage, devs) in s { print("  stage \(stage.rawValue): \(devs.map(describe))") }
        }
        print("  computeDevice(main) before perform: \(p.computeDevice(for: .main).map(describe) ?? "nil (Vision chooses)")")
        let q = VNGeneratePersonSegmentationRequest()
        print("  frameAnalysisSpacing \(CMTimeGetSeconds(q.frameAnalysisSpacing))")

        for level: VNGeneratePersonSegmentationRequest.QualityLevel in [.fast, .balanced, .accurate] {
            for fmt in [kCVPixelFormatType_OneComponent8, kCVPixelFormatType_OneComponent16Half, kCVPixelFormatType_OneComponent32Float] {
                let r = VNGeneratePersonSegmentationRequest()
                r.qualityLevel = level
                r.outputPixelFormat = fmt
                let thread = Thread.current
                var handlerThreadSame = false, handlerCalled = false
                let r2 = VNGeneratePersonSegmentationRequest { _, _ in handlerCalled = true; handlerThreadSame = Thread.current == thread }
                r2.qualityLevel = level
                r2.outputPixelFormat = fmt
                let h = VNImageRequestHandler(cvPixelBuffer: frame, options: [:])
                try h.perform([r, r2])
                let calledBeforeReturn = handlerCalled
                let obs = r.results ?? []
                let o = obs.first!
                let pb = o.pixelBuffer
                print("  quality \(level.rawValue) fmt \(fourCC(fmt)): results \(obs.count) \(type(of: o)) -> \(CVPixelBufferGetWidth(pb))x\(CVPixelBufferGetHeight(pb)) \(fourCC(CVPixelBufferGetPixelFormatType(pb))) bytesPerRow \(CVPixelBufferGetBytesPerRow(pb)) confidence \(o.confidence) iosurface \(CVPixelBufferGetIOSurface(pb) != nil) | completion handler ran before perform returned: \(calledBeforeReturn), same thread: \(handlerThreadSame)")
            }
        }

        print("\nVNGenerateForegroundInstanceMaskRequest: superclass \(String(describing: VNGenerateForegroundInstanceMaskRequest.superclass()!))")
        print("  supportedRevisions \(Array(VNGenerateForegroundInstanceMaskRequest.supportedRevisions)) default \(VNGenerateForegroundInstanceMaskRequest.defaultRevision) current \(VNGenerateForegroundInstanceMaskRequest.currentRevision)")
        let fg = VNGenerateForegroundInstanceMaskRequest()
        if let s = try? fg.supportedComputeStageDevices {
            for (stage, devs) in s { print("  stage \(stage.rawValue): \(devs.map(describe))") }
        }
        let h = VNImageRequestHandler(cvPixelBuffer: frame, options: [:])
        try h.perform([fg])
        let obs = fg.results ?? []
        print("  results \(obs.count)")
        if let o = obs.first {
            let im = o.instanceMask
            print("  \(type(of: o)) allInstances \(Array(o.allInstances)) confidence \(o.confidence)")
            print("  instanceMask \(CVPixelBufferGetWidth(im))x\(CVPixelBufferGetHeight(im)) \(fourCC(CVPixelBufferGetPixelFormatType(im))) bytesPerRow \(CVPixelBufferGetBytesPerRow(im))")
            if !o.allInstances.isEmpty {
                let m = try o.generateMask(forInstances: o.allInstances)
                print("  generateMask(forInstances:) \(CVPixelBufferGetWidth(m))x\(CVPixelBufferGetHeight(m)) \(fourCC(CVPixelBufferGetPixelFormatType(m)))")
                let s = try o.generateScaledMaskForImage(forInstances: o.allInstances, from: h)
                print("  generateScaledMaskForImage \(CVPixelBufferGetWidth(s))x\(CVPixelBufferGetHeight(s)) \(fourCC(CVPixelBufferGetPixelFormatType(s)))")
                let mi = try o.generateMaskedImage(ofInstances: o.allInstances, from: h, croppedToInstancesExtent: false)
                print("  generateMaskedImage(uncropped) \(CVPixelBufferGetWidth(mi))x\(CVPixelBufferGetHeight(mi)) \(fourCC(CVPixelBufferGetPixelFormatType(mi)))")
                let mc = try o.generateMaskedImage(ofInstances: o.allInstances, from: h, croppedToInstancesExtent: true)
                print("  generateMaskedImage(cropped) \(CVPixelBufferGetWidth(mc))x\(CVPixelBufferGetHeight(mc)) \(fourCC(CVPixelBufferGetPixelFormatType(mc)))")
                let e = extract(m)
                var hist = [Int](repeating: 0, count: 6)
                for v in e.bytes { hist[v == 0 ? 0 : v == 255 ? 5 : 1 + Int(v) * 4 / 255] += 1 }
                print("  generateMask value histogram [0, (0,64), [64,128), [128,191), [191,255), 255]: \(hist)")
            }
        }
        // the same frame at other sizes: does the native mask size follow the input?
        for (w, hh) in [(1280, 720), (1920, 1080), (3840, 2160), (1080, 1920), (1000, 1000)] {
            let fr = loadFrame(path, width: w, height: hh)
            var line = "  input \(w)x\(hh):"
            for level: VNGeneratePersonSegmentationRequest.QualityLevel in [.fast, .balanced, .accurate] {
                let r = VNGeneratePersonSegmentationRequest()
                r.qualityLevel = level
                try VNImageRequestHandler(cvPixelBuffer: fr, options: [:]).perform([r])
                let pb = r.results!.first!.pixelBuffer
                line += " person[\(level.rawValue)] \(CVPixelBufferGetWidth(pb))x\(CVPixelBufferGetHeight(pb))"
            }
            let g = VNGenerateForegroundInstanceMaskRequest()
            try VNImageRequestHandler(cvPixelBuffer: fr, options: [:]).perform([g])
            if let o = g.results?.first {
                line += " fg.instanceMask \(CVPixelBufferGetWidth(o.instanceMask))x\(CVPixelBufferGetHeight(o.instanceMask))"
            } else { line += " fg: no observation" }
            print(line)
        }
        print("peak RSS \(f(peakRSSMB(), 1)) MB")
    }

    // MARK: q2

    static func cold(_ path: String, _ kind: Kind, _ dev: Device) throws {
        let frame = loadFrame(path)
        var times: [Double] = []
        for _ in 0..<3 {
            let req = makeRequest(kind)
            pin(req, dev)
            _ = try run(kind, req, frame)
            times.append(lastVisionMs)
        }
        print("cold \(kind.rawValue) \(dev.rawValue) \(CVPixelBufferGetWidth(frame))x\(CVPixelBufferGetHeight(frame)): call1 \(f(times[0], 1)) ms  call2 \(f(times[1], 1)) ms  call3 \(f(times[2], 1)) ms  rss \(f(peakRSSMB(), 0)) MB")
    }

    static func warm(_ args: [String]) throws {
        let path = args[0]
        let kind = Kind(rawValue: args[1])!
        let n = Int(args[2])!
        let dev = Device(rawValue: args.count > 3 ? args[3] : "auto")!
        var frame: CVPixelBuffer
        if args.count > 4 {
            let p = args[4].split(separator: "x").map { Int($0)! }
            frame = loadFrame(path, width: p[0], height: p[1])
        } else { frame = loadFrame(path) }
        let reqWarm = makeRequest(kind)
        pin(reqWarm, dev)
        for _ in 0..<5 { _ = try run(kind, reqWarm, frame) }
        // a fresh request object per frame (what a stateless cache job does) and one reused object
        var fresh: [Double] = [], reused: [Double] = []
        var m = Mask()
        for _ in 0..<n {
            let r = makeRequest(kind)
            pin(r, dev)
            m = try run(kind, r, frame)
            fresh.append(lastVisionMs)
        }
        for _ in 0..<n {
            _ = try run(kind, reqWarm, frame)
            reused.append(lastVisionMs)
        }
        print("warm \(kind.rawValue) \(dev.rawValue) \(CVPixelBufferGetWidth(frame))x\(CVPixelBufferGetHeight(frame)) n=\(n): fresh-request median \(f(median(fresh))) ms p90 \(f(percentile(fresh, 0.9))) | reused-request median \(f(median(reused))) ms p90 \(f(percentile(reused, 0.9))) | mask \(m.width)x\(m.height) | rss \(f(peakRSSMB(), 0)) MB")
    }

    // MARK: q3

    static func det(_ path: String, _ kind: Kind, _ dev: Device, _ dir: String) throws {
        let frame = loadFrame(path)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // fresh request + fresh handler, twice
        func fresh() throws -> Mask { let r = makeRequest(kind); pin(r, dev); return try run(kind, r, frame) }
        let a = try fresh(), b = try fresh()
        // one request object, reused (person segmentation is a VNStatefulRequest)
        let r = makeRequest(kind); pin(r, dev)
        let c = try run(kind, r, frame), d = try run(kind, r, frame)
        var e = d
        for _ in 0..<8 { e = try run(kind, r, frame) }
        let name = (path as NSString).lastPathComponent.replacingOccurrences(of: ".png", with: "")
        let file = "\(dir)/\(name)-\(kind.rawValue)-\(dev.rawValue).raw"
        var cross = "first run: wrote \(file)"
        if let prev = FileManager.default.contents(atPath: file) {
            let pd = diff([UInt8](prev), a.bytes)
            cross = "vs previous process: " + (pd.differing == 0 ? "IDENTICAL" : "differ \(pd.differing) px maxAbs \(pd.maxAbs) mad \(f(pd.mad, 4))")
        } else {
            FileManager.default.createFile(atPath: file, contents: Data(a.bytes))
        }
        func line(_ x: Mask, _ y: Mask) -> String {
            let dd = diff(x.bytes, y.bytes)
            return dd.differing == 0 ? "IDENTICAL" : "differ \(dd.differing)/\(x.bytes.count) px maxAbs \(dd.maxAbs) mad \(f(dd.mad, 4))"
        }
        print("det \(name) \(kind.rawValue) \(dev.rawValue) mask \(a.width)x\(a.height) hash \(a.rawHash) obs \(a.observations) inst \(a.instances)")
        print("  fresh#1 vs fresh#2: \(line(a, b))  [raw hash equal: \(a.rawHash == b.rawHash)]")
        print("  reused#1 vs fresh#1: \(line(a, c))   reused#1 vs reused#2: \(line(c, d))   reused#2 vs reused#10: \(line(d, e))")
        print("  \(cross)")
    }

    static func cmp(_ a: String, _ b: String) {
        guard let x = FileManager.default.contents(atPath: a), let y = FileManager.default.contents(atPath: b) else { die("missing") }
        let d = diff([UInt8](x), [UInt8](y))
        print("cmp \((a as NSString).lastPathComponent) vs \((b as NSString).lastPathComponent): " + (d.differing == 0 ? "IDENTICAL" : "differ \(d.differing)/\(x.count) px (\(f(Double(d.differing) * 100 / Double(x.count), 3))%) maxAbs \(d.maxAbs) mad \(f(d.mad, 4)) over32 \(f(d.over32 * 100, 4))%"))
    }

    // MARK: q4 / q5

    static func content(_ paths: [String]) throws {
        let outDir = ProcessInfo.processInfo.environment["MASK_PNG_DIR"]
        for path in paths {
            let frame = loadFrame(path)
            let name = (path as NSString).lastPathComponent.replacingOccurrences(of: ".png", with: "")
            print("\(name) (\(CVPixelBufferGetWidth(frame))x\(CVPixelBufferGetHeight(frame)))")
            for kind in [Kind.personFast, .personBalanced, .personAccurate, .fgMask] {
                let r = makeRequest(kind)
                let m: Mask
                do { m = try run(kind, r, frame) } catch {
                    print("  \(kind.rawValue): THREW \(error)"); continue
                }
                if m.bytes.isEmpty {
                    print("  \(kind.rawValue): observations \(m.observations) instances \(m.instances) -> no mask")
                    continue
                }
                print("  \(kind.rawValue): observations \(m.observations)\(kind.isPerson ? "" : " instances \(m.instances)") mask \(m.width)x\(m.height) \(covString(coverage(m.bytes)))")
                if let outDir {
                    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
                    try pngData(m.bytes, m.width, m.height).write(to: URL(fileURLWithPath: "\(outDir)/\(name)-\(kind.rawValue).png"))
                }
            }
        }
    }

    // MARK: q6

    static func cache(_ paths: [String]) throws {
        for path in paths {
            let frame = loadFrame(path)
            let name = (path as NSString).lastPathComponent.replacingOccurrences(of: ".png", with: "")
            for kind in [Kind.personFast, .personBalanced, .personAccurate, .fgMask, .fgScaled] {
                let m = try run(kind, makeRequest(kind), frame)
                guard !m.bytes.isEmpty else { print("\(name) \(kind.rawValue): no mask"); continue }
                let png = pngData(m.bytes, m.width, m.height).count
                let s = downscale(m.bytes, m.width, m.height, longEdge: 256)
                let spng = pngData(s.bytes, s.w, s.h).count
                print("\(name) \(kind.rawValue) native \(m.width)x\(m.height): raw \(m.bytes.count) B  png \(png) B  lzfse \(lzfseSize(m.bytes)) B | 256-long-edge \(s.w)x\(s.h): raw \(s.bytes.count) B  png \(spng) B  lzfse \(lzfseSize(s.bytes)) B")
            }
        }
    }
}
