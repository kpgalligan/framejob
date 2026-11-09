// Road map "creator-jobs" CO1 — rows P1–P11 of `co1_proof.py`, driven through
// the app's own `MaskPack`, `AnalysisStore.publishFile`, `AnalysisStamp` and
// `AnalysisMasks`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, with `-D FRAMEJOB_DEV_TOOLS`, module `FrameJob`, against
// `libframejob_core.a`, through `swift_build.py`. One run:
//
//   co1_probe <request.json>
//
// The request names `fixture` (a movie whose masks stamp P5 makes) and `work`
// (a scratch folder this run owns). The answer is one JSON object on stdout,
// `{"rows": [{"id", "pass", "detail"}]}`.
import AppKit

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}

let arguments = CommandLine.arguments
guard arguments.count == 2,
    let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])),
    let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
    let fixturePath = request["fixture"] as? String, let workPath = request["work"] as? String
else {
    FileHandle.standardError.write(Data("usage: co1_probe <request.json>\n".utf8))
    exit(2)
}
let work = URL(fileURLWithPath: workPath)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

// The app rows' reader: `compare` is a list of {a, b} pack paths; each pair
// answers its masks' sizes, frame counts, the pts both hold, and at those pts
// the largest byte difference and the IoU of the masks above 127 (mean and
// least) — so the proof never decompresses LZFSE itself.
if let pairs = request["compare"] as? [[String: String]] {
    var answers: [[String: Any]] = []
    for pair in pairs {
        do {
            let a = try MaskPack(contentsOf: URL(fileURLWithPath: pair["a"] ?? ""))
            let b = try MaskPack(contentsOf: URL(fileURLWithPath: pair["b"] ?? ""))
            var slotsB: [Int64: Int] = [:]
            for frame in b.frames { slotsB[frame.pts] = Int(frame.slot) }
            var shared = 0, worst = 0, ious: [Double] = []
            for frame in a.frames {
                guard let slot = slotsB[frame.pts] else { continue }
                shared += 1
                let x = try a.mask(slot: Int(frame.slot)), y = try b.mask(slot: slot)
                guard x.count == y.count else {
                    worst = 255
                    ious.append(0)
                    continue
                }
                var inter = 0, union = 0
                for i in 0..<x.count {
                    worst = max(worst, abs(Int(x[i]) - Int(y[i])))
                    let p = x[i] > 127, q = y[i] > 127
                    if p && q { inter += 1 }
                    if p || q { union += 1 }
                }
                ious.append(union == 0 ? 1 : Double(inter) / Double(union))
            }
            answers.append([
                "a_size": [a.width, a.height], "b_size": [b.width, b.height],
                "a_frames": a.frames.count, "b_frames": b.frames.count, "shared": shared,
                "max_diff": worst,
                "mean_iou": ious.isEmpty ? 0 : ious.reduce(0, +) / Double(ious.count),
                "min_iou": ious.min() ?? 0,
                "median_iou": ious.isEmpty ? 0 : ious.sorted()[ious.count / 2],
                "below_090": ious.filter { $0 < 0.9 }.count,
            ])
        } catch {
            answers.append(["error": error.localizedDescription])
        }
    }
    let out = try JSONSerialization.data(withJSONObject: ["pairs": answers])
    print(String(decoding: out, as: UTF8.self))
    exit(0)
}

func folder(_ name: String) -> URL {
    let url = work.appendingPathComponent(name, isDirectory: true)
    try? FileManager.default.removeItem(at: url)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A w × h mask whose bytes are `seed`-dependent, and its analysed entry.
func mask(_ pts: Int64, seed: UInt8, w: Int = 8, h: Int = 4) -> ([UInt8], MaskPack.Analysed) {
    let bytes = (0..<(w * h)).map { UInt8(truncatingIfNeeded: Int(seed) &* 31 &+ $0 &* 7) }
    let compressed = (try? (Data(bytes) as NSData).compressed(using: .lzfse)) as Data? ?? Data()
    let found = bytes.withUnsafeBytes { MaskPack.found($0, width: w, height: h) }
    return (bytes, MaskPack.Analysed(pts: pts, compressed: compressed, found: found))
}

let frame: Int64 = 20_000
let fixtureURL = URL(fileURLWithPath: fixturePath)
/// The fixture's media (P5's stamp, P8's 30 fps grid).
let fixtureMedia: MediaSnapshot? = {
    guard let descriptor = try? MediaImporter.probeBlocking(url: fixtureURL),
        let blank = ReelProject.new(
            width: descriptor.width, height: descriptor.height, fps: descriptor.fps)
    else { return nil }
    return (try? blank.applying(.addMedia(descriptor: descriptor)))?.project?.snapshot.media.last
}()
let source = AnalysisSourceID(size: 100, modified: 200, duration: 600_000_000)
let vision = AnalysisVisionStamp(
    request: "person_segmentation", quality: "balanced", revision: 1, rate: "every",
    readSize: "source")
let base = AnalysisStamp(
    source: source, kind: .masks, version: 1, parameters: "p", osBuild: "25F80", device: "gpu",
    reader: "raw", conversion: nil, vision: vision)

/// Publishes frames `indices` (pts k × frame), each its own mask, through
/// `publishFile`; answers whether the write merged.
@discardableResult
func publish(_ dir: URL, _ indices: ClosedRange<Int>, seed: UInt8 = 0, w: Int = 8, h: Int = 4,
             maskOf: ((Int) -> Int)? = nil) throws -> Bool {
    var merged = false
    let wanted = Set(indices.map { maskOf?($0) ?? $0 })
    let masks = wanted.sorted().map { mask(Int64($0) * frame, seed: UInt8($0 % 200) &+ seed, w: w, h: h).1 }
    let frames = indices.map { k in (pts: Int64(k) * frame, index: Int32(k), maskPts: Int64(maskOf?(k) ?? k) * frame) }
    try AnalysisStore.publishFile(
        kind: .masks, cacheDir: dir, mediaID: 1, stamp: base, covered: [indices],
        files: [MaskPack.fileName]
    ) { onDisk, partial in
        merged = try MaskPack.write(
            onDisk: onDisk, partial: partial, width: w, height: h, frames: frames, masks: masks)
        return merged
    }
    return merged
}

func packURL(_ dir: URL) -> URL {
    AnalysisStore.payloadURL(.masks, media: 1, file: MaskPack.fileName, in: dir)
}
func markerURL(_ dir: URL) -> URL { AnalysisStore.markerURL(.masks, media: 1, in: dir) }

// MARK: - P1 a fresh write reads back byte-exact

do {
    let dir = folder("p1")
    let partial = dir.appendingPathComponent("fresh.pack")
    let made = [mask(0, seed: 1), mask(60_000, seed: 2), mask(120_000, seed: 3)]
    let frames: [(pts: Int64, index: Int32, maskPts: Int64)] = [
        (80_000, 4, 60_000), (0, 0, 0), (20_000, 1, 0), (60_000, 3, 60_000), (120_000, 6, 120_000),
    ]
    let merged = try MaskPack.write(
        onDisk: nil, partial: partial, width: 8, height: 4, frames: frames, masks: made.map(\.1))
    let pack = try MaskPack(contentsOf: partial)
    let bytes = try Data(contentsOf: partial)
    let blobs = made.reduce(0) { $0 + $1.1.compressed.count }
    let tablesOffset = UInt64(blobs)
    let footer = [UInt8](bytes.suffix(40))
    func u32(_ o: Int) -> UInt32 { footer[o..<(o + 4)].reversed().reduce(0) { $0 << 8 | UInt32($1) } }
    func u64(_ o: Int) -> UInt64 { footer[o..<(o + 8)].reversed().reduce(0) { $0 << 8 | UInt64($1) } }
    let footerOK = footer[0..<4] == [0x46, 0x4A, 0x4D, 0x50][...] && u32(4) == 1 && u32(8) == 8
        && u32(12) == 4 && u32(16) == 5 && u32(20) == 3 && u64(24) == tablesOffset && u64(32) == 0
    let wantFrames = [
        MaskPack.Frame(pts: 0, index: 0, slot: 0), MaskPack.Frame(pts: 20_000, index: 1, slot: 0),
        MaskPack.Frame(pts: 60_000, index: 3, slot: 1), MaskPack.Frame(pts: 80_000, index: 4, slot: 1),
        MaskPack.Frame(pts: 120_000, index: 6, slot: 2),
    ]
    let masksOK = try (0..<3).allSatisfy { try pack.mask(slot: $0) == made[$0].0 }
        && pack.masks.map(\.pts) == [0, 60_000, 120_000]
        && pack.masks.map(\.found) == made.map(\.1.found)
        && pack.masks[0].offset == 0 && pack.masks[1].offset == UInt64(made[0].1.compressed.count)
    let size = bytes.count == blobs + 5 * 16 + 3 * 24 + 40
    row("P1", !merged && pack.width == 8 && pack.height == 4 && pack.frames == wantFrames
        && masksOK && footerOK && size,
        "merged \(merged) (want false); \(pack.width)×\(pack.height); frames "
            + "\(pack.frames == wantFrames ? "sorted with their slots" : "WRONG \(pack.frames)"); "
            + "masks \(masksOK ? "byte-exact" : "DIFFER"); footer \(footerOK ? "as spelt" : "WRONG \(footer)"); "
            + "\(bytes.count) bytes (\(size ? "blobs + tables + 40" : "WRONG"))")
} catch {
    row("P1", false, "threw \(error.localizedDescription)")
}

// MARK: - P2 disjoint publishes in either order, blobs in place, an equal pts keeps its slot

do {
    func state(_ dir: URL) throws -> (MaskPack, [[Int]]) {
        (try MaskPack(contentsOf: packURL(dir)),
         AnalysisStore.readMarker(.masks, media: 1, in: dir)?.coverage ?? [])
    }
    let ab = folder("p2-ab"), ba = folder("p2-ba")
    let first = try publish(ab, 0...9)
    let earlier = try Data(contentsOf: packURL(ab))
    let earlierTables = Int(try MaskPack(contentsOf: packURL(ab)).masks.map { $0.offset + UInt64($0.length) }.max() ?? 0)
    let second = try publish(ab, 20...29)
    let later = try Data(contentsOf: packURL(ab))
    try publish(ba, 20...29)
    try publish(ba, 0...9)
    let (abPack, abCover) = try state(ab)
    let (baPack, baCover) = try state(ba)
    let inPlace = later.prefix(earlierTables) == earlier.prefix(earlierTables)
    func masksOf(_ pack: MaskPack) throws -> [Int64: [UInt8]] {
        var out: [Int64: [UInt8]] = [:]
        for (slot, m) in pack.masks.enumerated() { out[m.pts] = try pack.mask(slot: slot) }
        return out
    }
    let sameContent = try masksOf(abPack) == masksOf(baPack)
        && abPack.frames.map(\.pts) == baPack.frames.map(\.pts)
        && abPack.frames.map(\.pts) == (Array(0...9) + Array(20...29)).map { Int64($0) * frame }
    // An equal pts: frame 9's mask published again with other bytes, and
    // frames 10 and 11 pointing at it.
    let before = try MaskPack(contentsOf: packURL(ab))
    let slot9 = before.frames.first { $0.index == 9 }!.slot
    let bytes9 = try before.mask(slot: Int(slot9))
    try publish(ab, 9...11, seed: 77, maskOf: { _ in 9 })
    let after = try MaskPack(contentsOf: packURL(ab))
    let bytesAfter = try after.mask(slot: Int(slot9))
    let kept = after.frames.first { $0.index == 9 }?.slot == slot9
        && bytesAfter == bytes9
        && after.frames.filter { (10...11).contains($0.index) }.allSatisfy { $0.slot == slot9 }
        && after.masks.count == before.masks.count
    let cover = AnalysisStore.readMarker(.masks, media: 1, in: ab)?.coverage ?? []
    row("P2", !first && second && abCover == [[0, 9], [20, 29]] && baCover == abCover
        && sameContent && inPlace && kept && cover == [[0, 11], [20, 29]],
        "first merged \(first), second \(second) (want false, true); coverage \(abCover) and \(baCover); "
            + "either order \(sameContent ? "the same frames and masks" : "DIFFERS"); the first "
            + "publish's blobs \(inPlace ? "unchanged in place" : "MOVED"); an equal pts "
            + "\(kept ? "keeps its slot and bytes, 10 and 11 point at it" : "did NOT keep its slot")"
            + "; coverage then \(cover)")
} catch {
    row("P2", false, "threw \(error.localizedDescription)")
}

// MARK: - P3 shown(at:)

do {
    let dir = folder("p3")
    let partial = dir.appendingPathComponent("p3.pack")
    let made = [mask(100_000, seed: 1), mask(200_000, seed: 2)]
    try MaskPack.write(
        onDisk: nil, partial: partial, width: 8, height: 4,
        frames: [(100_000, 5, 100_000), (200_000, 10, 200_000), (300_000, 15, 200_000)],
        masks: made.map(\.1))
    let pack = try MaskPack(contentsOf: partial)
    let got = [pack.shown(at: 99_999), pack.shown(at: 100_000), pack.shown(at: 150_000),
               pack.shown(at: 200_000), pack.shown(at: 299_999), pack.shown(at: 900_000)]
    let want: [Int?] = [nil, 0, 0, 1, 1, 2]
    row("P3", got == want, "shown at 99999, 100000, 150000, 200000, 299999, 900000: \(got) (want \(want))")
} catch {
    row("P3", false, "threw \(error.localizedDescription)")
}

// MARK: - P4 the found flag at 0.5 %

do {
    let w = 200, h = 10  // 2,000 pixels: 0.5 % is 10
    func flag(_ above: Int, at127: Int = 0) -> Bool {
        var bytes = [UInt8](repeating: 0, count: w * h)
        for i in 0..<above { bytes[i] = 128 }
        for i in above..<(above + at127) { bytes[i] = 127 }
        return bytes.withUnsafeBytes { MaskPack.found($0, width: w, height: h) }
    }
    let exact = flag(10), fewer = flag(9), at127 = flag(9, at127: 5), all = flag(2000)
    row("P4", exact && !fewer && !at127 && all,
        "10 of 2000 above 127 \(exact) (want true); 9 \(fewer) (false); 9 and five at 127 "
            + "\(at127) (false); all \(all)")
}

// MARK: - P5 the vision field alone makes a miss; the masks stamp's JSON

do {
    let dir = folder("p5")
    try publish(dir, 0...9)
    func hits(_ stamp: AnalysisStamp) -> Bool {
        AnalysisStore.lookup(.masks, media: 1, stamp: stamp, need: 0...9, in: dir) != .miss([0...9])
    }
    func with(_ vision: AnalysisVisionStamp?) -> AnalysisStamp {
        AnalysisStamp(
            source: source, kind: .masks, version: 1, parameters: "p", osBuild: "25F80",
            device: "gpu", reader: "raw", conversion: nil, vision: vision)
    }
    let variants: [(String, AnalysisVisionStamp?)] = [
        ("none", nil),
        ("request", AnalysisVisionStamp(request: "x", quality: "balanced", revision: 1, rate: "every", readSize: "source")),
        ("quality", AnalysisVisionStamp(request: "person_segmentation", quality: "fast", revision: 1, rate: "every", readSize: "source")),
        ("revision", AnalysisVisionStamp(request: "person_segmentation", quality: "balanced", revision: 2, rate: "every", readSize: "source")),
        ("rate", AnalysisVisionStamp(request: "person_segmentation", quality: "balanced", revision: 1, rate: "15", readSize: "source")),
        ("read size", AnalysisVisionStamp(request: "person_segmentation", quality: "balanced", revision: 1, rate: "every", readSize: "1920")),
    ]
    let leaked = variants.filter { hits(with($0.1)) }.map(\.0)
    let url = fixtureURL
    guard let media = fixtureMedia,
        let stamp = AnalysisStamp.make(kind: .masks, media: media, url: url, input: nil, fullRange: false),
        let shots = AnalysisStamp.make(kind: .shots, media: media, url: url, input: nil, fullRange: false)
    else { throw AnalysisStore.StoreError.write("the fixture did not probe") }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = String(decoding: try encoder.encode(stamp), as: UTF8.self)
    let shotsJSON = String(decoding: try encoder.encode(shots), as: UTF8.self)
    let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]
    let v = object["vision"] as? [String: Any] ?? [:]
    let named = ["request", "quality", "revision", "rate", "readSize"].allSatisfy { v[$0] != nil }
        && object["osBuild"] as? String == AnalysisStamp.osBuild && !(AnalysisStamp.osBuild).isEmpty
        && object["device"] as? String == AnalysisMasks.device
        && v["request"] as? String == "person_segmentation" && v["quality"] as? String == "balanced"
        && v["revision"] as? Int == 1
    let noPath = !json.contains(url.deletingLastPathComponent().path) && !json.contains(url.lastPathComponent)
    row("P5", hits(base) && leaked.isEmpty && named && noPath && !shotsJSON.contains("vision"),
        "the base \(hits(base) ? "hits" : "MISSED"); each of \(variants.map(\.0)) alone "
            + (leaked.isEmpty ? "misses" : "— but \(leaked) hit") + "; the masks stamp \(json); "
            + "\(noPath ? "no path" : "HOLDS A PATH"); the shots stamp "
            + "\(shotsJSON.contains("vision") ? "HAS" : "has no") vision key")
} catch {
    row("P5", false, "threw \(error.localizedDescription)")
}

// MARK: - P6 a write that throws leaves the store as it was

do {
    let dir = folder("p6")
    try publish(dir, 0...9)
    let marker = try Data(contentsOf: markerURL(dir))
    let pack = try Data(contentsOf: packURL(dir))
    struct Thrown: Error {}
    var threw = false
    do {
        try AnalysisStore.publishFile(
            kind: .masks, cacheDir: dir, mediaID: 1, stamp: base, covered: [20...29],
            files: [MaskPack.fileName]
        ) { _, partial in
            try Data(repeating: 7, count: 4096).write(to: partial)
            throw Thrown()
        }
    } catch {
        threw = true
    }
    let partial = packURL(dir).appendingPathExtension("partial")
    let markerAfter = try? Data(contentsOf: markerURL(dir))
    let packAfter = try? Data(contentsOf: packURL(dir))
    let gone = !FileManager.default.fileExists(atPath: partial.path)
    row("P6", threw && markerAfter == marker && packAfter == pack && gone,
        "the publish threw \(threw); marker \(markerAfter == marker ? "unchanged" : "CHANGED"), "
            + "pack \(packAfter == pack ? "unchanged" : "CHANGED"); \(gone ? "no" : "a") .partial left")
} catch {
    row("P6", false, "threw \(error.localizedDescription)")
}

// MARK: - P7 a publish during a save writes nothing until the save ends

do {
    let dir = folder("p7")
    let ledger = MediaImporter.CacheLedger.shared
    func present() -> (Bool, Bool) {
        (FileManager.default.fileExists(atPath: markerURL(dir).path),
         FileManager.default.fileExists(atPath: packURL(dir).path))
    }
    let save = ledger.saveBegan(cacheDir: dir)
    let done = DispatchSemaphore(value: 0)
    var failure: String?
    DispatchQueue.global().async {
        do { try publish(dir, 0...9) } catch { failure = error.localizedDescription }
        done.signal()
    }
    let finishedDuring = done.wait(timeout: .now() + 0.5) == .success
    let during = present()
    ledger.saveEnded(cacheDir: dir, save: save)
    let finished = done.wait(timeout: .now() + 10) == .success
    let after = present()
    row("P7", !finishedDuring && !during.0 && !during.1 && finished && failure == nil
        && after.0 && after.1,
        "during the save: returned \(finishedDuring), marker \(during.0), pack \(during.1) (want "
            + "false ×3); after saveEnded: returned \(finished), marker \(after.0), pack \(after.1)"
            + (failure.map { "; failed: \($0)" } ?? ""))
}

// MARK: - P8 runs, the capped rate's nearest slot, and covered

do {
    let dir = folder("p8")
    let partial = dir.appendingPathComponent("runs.pack")
    let w = 200, h = 10
    func flagged(_ k: Int, _ found: Bool) -> MaskPack.Analysed {
        var bytes = [UInt8](repeating: 0, count: w * h)
        if found { for i in 0..<20 { bytes[i] = 255 } }
        let compressed = (try? (Data(bytes) as NSData).compressed(using: .lzfse)) as Data? ?? Data()
        return MaskPack.Analysed(pts: Int64(k) * frame, compressed: compressed, found: bytes.withUnsafeBytes { MaskPack.found($0, width: w, height: h) })
    }
    let foundAt: (Int) -> Bool = { !(5...9).contains($0) }
    try MaskPack.write(
        onDisk: nil, partial: partial, width: w, height: h,
        frames: (0...19).map { (Int64($0) * frame, Int32($0), Int64($0) * frame) },
        masks: (0...19).map { flagged($0, foundAt($0)) })
    let pack = try MaskPack(contentsOf: partial)
    guard let media = fixtureMedia, media.fps.num == 30, media.fps.den == 1 else {
        throw AnalysisStore.StoreError.write("the 30 fps fixture did not probe")
    }
    let grid = AnalysisGrid(media: media)
    let runs = AnalysisMasks.runs(pack, window: 2...17, coverage: [0...9, 12...19], grid: grid)
    let want = [
        AnalysisMasks.Run(from: 2 * frame, to: 5 * frame, subjectFound: true, frames: 3),
        AnalysisMasks.Run(from: 5 * frame, to: 10 * frame, subjectFound: false, frames: 5),
        AnalysisMasks.Run(from: 12 * frame, to: 18 * frame, subjectFound: true, frames: 6),
    ]
    // The capped rate: 15 a second over 30 fps analyses the even frames; 10 a
    // second every third. Each frame's slot is its nearest analysed (ties to
    // the earlier).
    func picks(_ rate: Double) -> [Int] {
        var previous: Int64?
        var out: [Int] = []
        for k in 0...12 {
            if AnalysisMasks.analysed(Int64(k) * frame, after: previous, rate: rate) { out.append(k) }
            previous = Int64(k) * frame
        }
        return out
    }
    let fifteen = picks(15), ten = picks(10)
    let times = fifteen.map { Int64($0) * frame }
    let capped = dir.appendingPathComponent("capped.pack")
    try MaskPack.write(
        onDisk: nil, partial: capped, width: w, height: h,
        frames: (0...12).map { k in (Int64(k) * frame, Int32(k), AnalysisMasks.nearest(Int64(k) * frame, in: times)!) },
        masks: fifteen.map { flagged($0, true) })
    let cappedPack = try MaskPack(contentsOf: capped)
    let slots = cappedPack.frames.map { Int(cappedPack.masks[Int($0.slot)].pts / frame) }
    let wantSlots = [0, 0, 2, 2, 4, 4, 6, 6, 8, 8, 10, 10, 12]
    let mid = AnalysisMasks.covered(897...1100, analysedDone: [897, 900], finished: false)
    let none = AnalysisMasks.covered(897...1100, analysedDone: [], finished: false)
    let whole = AnalysisMasks.covered(897...1100, analysedDone: [897, 900], finished: true)
    row("P8", runs == want && fifteen == [0, 2, 4, 6, 8, 10, 12] && ten == [0, 3, 6, 9, 12]
        && slots == wantSlots && mid == 897...900 && none == nil && whole == 897...1100,
        "runs over 2…17 with coverage [0…9, 12…19]: \(runs.map { "(\($0.from / frame)…\($0.to / frame) \($0.subjectFound) \($0.frames))" }) "
            + "(want 2…5 true 3, 5…10 false 5, 12…18 true 6); 15 a second picks \(fifteen), 10 a "
            + "second \(ten); each frame's mask \(slots) (want \(wantSlots), ties to the earlier); "
            + "covered mid-range (30 fps, rate 10, analysed 897 and 900 done, 902 read) "
            + "\(String(describing: mid)) (want 897…900), none done \(String(describing: none)), "
            + "finished \(String(describing: whole))")
} catch {
    row("P8", false, "threw \(error.localizedDescription)")
}

// MARK: - P9 a marker whose pack is gone, garbage, or another size

do {
    var details: [String] = []
    var ok = true
    for damage in ["deleted", "garbage", "other size"] {
        let dir = folder("p9-\(damage)")
        try publish(dir, 0...599)
        switch damage {
        case "deleted": try FileManager.default.removeItem(at: packURL(dir))
        case "garbage": try Data(repeating: 0xAB, count: 9000).write(to: packURL(dir))
        default:
            try FileManager.default.removeItem(at: packURL(dir))
            try MaskPack.write(
                onDisk: nil, partial: packURL(dir), width: 4, height: 2,
                frames: [(0, 0, 0)], masks: [mask(0, seed: 9, w: 4, h: 2).1])
        }
        let lookup = AnalysisStore.lookup(.masks, media: 1, stamp: base, need: 0...599, in: dir)
        let merged = try publish(dir, 600...899)
        let cover = AnalysisStore.readMarker(.masks, media: 1, in: dir)?.coverage ?? []
        let pack = try MaskPack(contentsOf: packURL(dir))
        let only = pack.frames.map(\.index) == (600...899).map { Int32($0) }
        let lookupOK = damage == "deleted" ? lookup == .miss([0...599]) : true
        let good = lookupOK && !merged && cover == [[600, 899]] && only
        ok = ok && good
        details.append("\(damage): lookup \(lookup)\(lookupOK ? "" : " (want miss [0…599])"), merged \(merged), "
            + "coverage \(cover), pack frames \(only ? "600…899 only" : "\(pack.frames.count) WRONG")")
    }
    row("P9", ok, details.joined(separator: "; "))
} catch {
    row("P9", false, "threw \(error.localizedDescription)")
}

// MARK: - P10 a publish of a range that made no mask keeps the pack

// A range of only dropped VFR frames decodes nothing, so its job has no mask
// size: `AnalysisMasks` publishes it at 0 × 0 with no frames and no masks.
do {
    let dir = folder("p10-frameless")
    try publish(dir, 0...599)
    func decoded(_ pack: MaskPack) throws -> [Int64: [UInt8]] {
        var out: [Int64: [UInt8]] = [:]
        for (slot, m) in pack.masks.enumerated() { out[m.pts] = try pack.mask(slot: slot) }
        return out
    }
    let before = try MaskPack(contentsOf: packURL(dir))
    let beforeMasks = try decoded(before)
    var merged = false
    try AnalysisStore.publishFile(
        kind: .masks, cacheDir: dir, mediaID: 1, stamp: base, covered: [600...600],
        files: [MaskPack.fileName]
    ) { onDisk, partial in
        merged = try MaskPack.write(
            onDisk: onDisk, partial: partial, width: 0, height: 0, frames: [], masks: [])
        return merged
    }
    let after = try MaskPack(contentsOf: packURL(dir))
    let cover = AnalysisStore.readMarker(.masks, media: 1, in: dir)?.coverage ?? []
    let sizeKept = (after.width, after.height) == (before.width, before.height)
    let framesKept = after.frames == before.frames && after.masks == before.masks
    let bytesKept = try decoded(after) == beforeMasks
    row("P10", merged && sizeKept && framesKept && bytesKept && cover == [[0, 600]],
        "merged \(merged) (want true); size \(after.width)×\(after.height) (want "
            + "\(before.width)×\(before.height)); frames \(after.frames.count) of "
            + "\(before.frames.count) kept \(framesKept), masks byte-equal \(bytesKept); "
            + "coverage \(cover) (want [[0, 600]])")
} catch {
    row("P10", false, "threw \(error.localizedDescription)")
}

// MARK: - P11 a request range wholly past the grid is skipped (#456)

// A 1 s media at 30 fps has indices 0…29; a range of 100…110 clamps to bounds that cross. The
// url does not exist: a range that reached the reader would fail, so true with nothing published
// says it was skipped before any read.
do {
    let dir = folder("p11-crossed")
    let media = MediaSnapshot(
        id: 1, path: "/nowhere/p11.mov", kind: .video, duration: 600_000, width: 640, height: 360,
        hasVideo: true, hasAudio: false)
    let request = AnalysisRequest(
        kind: .masks, cacheDir: dir, media: media,
        url: URL(fileURLWithPath: "/nowhere/p11.mov"), stamp: base, input: nil,
        ranges: [100...110])
    var heard: [Double] = []
    let finished = try AnalysisMasks.run(request, cancelled: { false }) { heard.append($0) }
    let marker = FileManager.default.fileExists(atPath: markerURL(dir).path)
    let pack = FileManager.default.fileExists(atPath: packURL(dir).path)
    row("P11", finished && !marker && !pack && heard.isEmpty,
        "finished \(finished) (want true); marker \(marker), pack \(pack) (want neither); "
            + "progress heard \(heard.count) (want 0)")
} catch {
    row("P11", false, "threw \(error.localizedDescription)")
}

let answer = try JSONSerialization.data(withJSONObject: ["rows": rows])
print(String(decoding: answer, as: UTF8.self))
