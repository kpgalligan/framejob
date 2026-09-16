// vision_job — the Vision spike's video instrument (2026-09-15).
//
//   job <video> <kind> <device> <mode> <rate> [dump]
//       q2: decode with AVAssetReader (32BGRA, IOSurface) and segment a frame
//       per 1/rate s of SOURCE time (rate "all" = every decoded frame); report
//       decode / Vision / copy-out time, total wall, × realtime, peak RSS.
//       mode: decode    — no Vision at all (the decode floor)
//             fresh     — a new request object and VNImageRequestHandler per frame
//             reused    — one request object, a VNImageRequestHandler per frame
//             sequence  — one request object through one VNSequenceRequestHandler
//       dump: every mask's 8-bit bytes appended to one file (absent fg = zeros)
//   stats <dump> <w> <h>            q7: consecutive-mask flicker and coverage
//   cmpdump <a> <b> <w> <h>         q3: two dumps of one job, mask by mask
//   cachesize <dump> <w> <h> <frameW> <frameH>   q6: a whole job's masks in each encoding
//
// kinds and devices as vision_stills.

import AVFoundation
import CoreVideo
import Foundation
import Vision

@main
struct VisionJob {
    static func main() throws {
        var a = CommandLine.arguments.dropFirst()
        guard let cmd = a.popFirst() else { die("usage: see header") }
        let args = Array(a)
        switch cmd {
        case "job": try job(args)
        case "stats": stats(args[0], Int(args[1])!, Int(args[2])!)
        case "cmpdump": cmpdump(args[0], args[1], Int(args[2])!, Int(args[3])!)
        case "cachesize": cachesize(args[0], Int(args[1])!, Int(args[2])!, Int(args[3])!, Int(args[4])!)
        default: die("unknown command \(cmd)")
        }
    }

    static func reader(_ path: String) throws -> (AVAssetReader, AVAssetReaderTrackOutput, Double) {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let track = asset.tracks(withMediaType: .video).first else { die("no video track") }
        let r = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ])
        out.alwaysCopiesSampleData = false
        r.add(out)
        return (r, out, CMTimeGetSeconds(asset.duration))
    }

    static func job(_ args: [String]) throws {
        hashRawSamples = false
        let path = args[0]
        let mode = args[3]
        let isDecode = mode == "decode"
        guard let kind = Kind(rawValue: isDecode ? "person-fast" : args[1]) else { die("kind") }
        guard let dev = Device(rawValue: args[2]) else { die("device") }
        let every: Double? = args[4] == "all" ? nil : 1.0 / Double(args[4])!
        let dumpPath = args.count > 5 ? args[5] : nil
        var dump: FileHandle?
        if let dumpPath {
            FileManager.default.createFile(atPath: dumpPath, contents: nil)
            dump = FileHandle(forWritingAtPath: dumpPath)
        }

        let tStart = nowNs()
        let (r, out, duration) = try reader(path)
        guard r.startReading() else { die("startReading \(String(describing: r.error))") }
        let shared = makeRequest(kind)
        pin(shared, dev)
        let seq = VNSequenceRequestHandler()
        var decodeMs = 0.0, visionMs = 0.0, copyMs = 0.0
        var decoded = 0, masks = 0, absent = 0, nextTick = 0.0
        var visionEach: [Double] = []
        var maskW = 0, maskH = 0
        var instanceHistogram: [Int: Int] = [:]
        while true {
            let t0 = nowNs()
            guard let sb = out.copyNextSampleBuffer() else { decodeMs += ms(t0, nowNs()); break }
            decodeMs += ms(t0, nowNs())
            decoded += 1
            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            if let every {
                guard pts + 1e-6 >= nextTick else { continue }
                while nextTick <= pts + 1e-6 { nextTick += every }
            }
            guard !isDecode, let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            let req: VNImageBasedRequest
            if mode == "fresh" { req = makeRequest(kind); pin(req, dev) } else { req = shared }
            var m: Mask
            if mode == "sequence" {
                runStartNs = nowNs()
                try seq.perform([req], on: pb)
                m = try collect(kind == .fgScaled ? .fgMask : kind, req, nil)
            } else {
                m = try run(kind, req, pb)
            }
            visionMs += lastVisionMs
            visionEach.append(lastVisionMs)
            if !kind.isPerson { instanceHistogram[m.instances, default: 0] += 1 }
            let c0 = nowNs()
            masks += 1
            if m.bytes.isEmpty {
                absent += 1
                if maskW == 0 { (maskW, maskH) = (512, 512) }
                m.bytes = [UInt8](repeating: 0, count: maskW * maskH)
            } else { (maskW, maskH) = (m.width, m.height) }
            dump?.write(Data(m.bytes))
            copyMs += ms(c0, nowNs())
        }
        try dump?.close()
        let wall = ms(tStart, nowNs())
        print("job \((path as NSString).lastPathComponent) \(isDecode ? "decode-only" : kind.rawValue) \(dev.rawValue) \(mode) rate \(args[4]): source \(f(duration, 2)) s, decoded \(decoded), masks \(masks) (\(absent) absent) \(maskW)x\(maskH)")
        print("  wall \(f(wall / 1000, 2)) s = \(f(duration / (wall / 1000), 1))x realtime | decode \(f(decodeMs / 1000, 2)) s  vision \(f(visionMs / 1000, 2)) s (median \(f(median(visionEach), 1)) ms, p90 \(f(percentile(visionEach, 0.9), 1)) ms)  copy-out+dump \(f(copyMs / 1000, 2)) s | peak RSS \(f(peakRSSMB(), 0)) MB")
        if !instanceHistogram.isEmpty {
            print("  foreground instances per mask: " + instanceHistogram.keys.sorted().map { "\($0): \(instanceHistogram[$0]!)" }.joined(separator: ", "))
        }
    }

    static func load(_ path: String, _ w: Int, _ h: Int) -> [[UInt8]] {
        guard let d = FileManager.default.contents(atPath: path) else { die("missing \(path)") }
        let b = [UInt8](d), n = w * h
        return stride(from: 0, to: b.count, by: n).map { Array(b[$0..<min($0 + n, b.count)]) }
    }

    static func stats(_ path: String, _ w: Int, _ h: Int) {
        let ms = load(path, w, h)
        var mads: [Double] = [], o32: [Double] = [], changed: [Double] = [], covs: [Double] = []
        var identicalPairs = 0
        for (i, m) in ms.enumerated() {
            covs.append(coverage(m).over127)
            if i > 0 {
                let d = diff(ms[i - 1], m)
                mads.append(d.mad); o32.append(d.over32); changed.append(Double(d.differing) / Double(m.count))
                if d.differing == 0 { identicalPairs += 1 }
            }
        }
        print("stats \((path as NSString).lastPathComponent) \(ms.count) masks \(w)x\(h)")
        print("  coverage>127: mean \(f(covs.reduce(0, +) / Double(covs.count) * 100, 2))%  min \(f((covs.min() ?? 0) * 100, 2))%  max \(f((covs.max() ?? 0) * 100, 2))%")
        print("  consecutive MAD (0-255): mean \(f(mads.reduce(0, +) / Double(max(1, mads.count)), 3))  median \(f(median(mads), 3))  p90 \(f(percentile(mads, 0.9), 3))  max \(f(mads.max() ?? 0, 3))")
        print("  consecutive px changed: median \(f(median(changed) * 100, 2))%  |  px changed by >32: mean \(f(o32.reduce(0, +) / Double(max(1, o32.count)) * 100, 3))%  p90 \(f(percentile(o32, 0.9) * 100, 3))%  max \(f((o32.max() ?? 0) * 100, 3))%  |  identical consecutive pairs \(identicalPairs)/\(mads.count)")
    }

    static func cmpdump(_ a: String, _ b: String, _ w: Int, _ h: Int) {
        let x = load(a, w, h), y = load(b, w, h)
        guard x.count == y.count else { print("cmpdump: counts differ \(x.count) vs \(y.count)"); return }
        var same = 0, worstPx = 0, worstAbs = 0, madSum = 0.0
        for i in 0..<x.count {
            let d = diff(x[i], y[i])
            if d.differing == 0 { same += 1 }
            worstPx = max(worstPx, d.differing); worstAbs = max(worstAbs, d.maxAbs); madSum += d.mad
        }
        print("cmpdump \((a as NSString).lastPathComponent) vs \((b as NSString).lastPathComponent): \(same)/\(x.count) masks byte-identical; worst mask \(worstPx) px differ, max abs \(worstAbs), mean MAD \(f(madSum / Double(x.count), 4))")
    }

    static func cachesize(_ path: String, _ w: Int, _ h: Int, _ fw: Int, _ fh: Int) {
        let ms = load(path, w, h)
        var raw = 0, png = 0, lz = 0, r256 = 0, p256 = 0, l256 = 0, rf = 0, pf = 0, lf = 0, all = [UInt8]()
        let s = 256.0 / Double(max(fw, fh))
        let fW = Int((Double(fw) * s).rounded()), fH = Int((Double(fh) * s).rounded())
        for m in ms {
            raw += m.count; png += pngData(m, w, h).count; lz += lzfseSize(m)
            let d = downscale(m, w, h, longEdge: 256)
            r256 += d.bytes.count; p256 += pngData(d.bytes, d.w, d.h).count; l256 += lzfseSize(d.bytes)
            // to the FRAME's aspect at 256 on the long edge (what a sampler at frame UVs would want)
            let dst = resize(m, w, h, fW, fH)
            rf += dst.count; pf += pngData(dst, fW, fH).count; lf += lzfseSize(dst)
            all.append(contentsOf: dst)
        }
        let kb = { (x: Int) in f(Double(x) / 1024, 1) + " KB" }
        print("cachesize \((path as NSString).lastPathComponent): \(ms.count) masks")
        print("  native \(w)x\(h): raw \(kb(raw))  png \(kb(png))  lzfse-each \(kb(lz))")
        print("  256 long edge, mask aspect \(downscale(ms[0], w, h, longEdge: 256).w)x\(downscale(ms[0], w, h, longEdge: 256).h): raw \(kb(r256))  png \(kb(p256))  lzfse-each \(kb(l256))")
        print("  256 long edge, frame aspect \(fW)x\(fH): raw \(kb(rf))  png \(kb(pf))  lzfse-each \(kb(lf))  lzfse-whole-file \(kb(lzfseSize(all)))")
    }
}
