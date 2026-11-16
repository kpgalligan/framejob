// Road map "creator-jobs" CJ2a — rows P1–P11 of `analysis_proof.py`, driven
// through the app's own `AnalysisStamp`, `AnalysisStore`, `AnalysisShots`,
// `AnalysisFrames`, `AnalysisLane`'s request and `AnalysisClipTimes`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, with `-D FRAMEJOB_DEV_TOOLS` (the canned rule's flag), module
// `FrameJob`, against `libframejob_core.a`, through `swift_build.py`. One run:
//
//   analysis_probe <request.json>
//
// The request names `shots` and `vfr` (the fixtures) and `work` (a scratch
// folder this run owns). The answer is one JSON object on stdout,
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
    let shotsPath = request["shots"] as? String, let vfrPath = request["vfr"] as? String,
    let workPath = request["work"] as? String
else {
    FileHandle.standardError.write(Data("usage: analysis_probe <request.json>\n".utf8))
    exit(2)
}
let work = URL(fileURLWithPath: workPath)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

/// A fresh one-media project around `path`: (project, its media, its track).
func project(_ path: String) -> (ReelProject, MediaSnapshot, UInt32)? {
    guard let descriptor = try? MediaImporter.probeBlocking(url: URL(fileURLWithPath: path)),
        let blank = ReelProject.new(
            width: descriptor.width, height: descriptor.height, fps: descriptor.fps),
        let added = (try? blank.applying(.addMedia(descriptor: descriptor)))?.project,
        let media = added.snapshot.media.last, let track = added.snapshot.tracks.first?.id
    else { return nil }
    return (added, media, track)
}

func folder(_ name: String) -> URL {
    let url = work.appendingPathComponent(name, isDirectory: true)
    try? FileManager.default.removeItem(at: url)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

let source = AnalysisSourceID(size: 100, modified: 200, duration: 300)
let base = AnalysisStamp(
    source: source, kind: .shots, version: 1, parameters: "p", osBuild: "25F80", device: "cpu",
    reader: "raw", conversion: nil)

// MARK: - P1 each stamp field alone makes a miss

do {
    let dir = folder("p1")
    try AnalysisStore.publish(
        kind: .shots, cacheDir: dir, mediaID: 1, stamp: base, covered: [0...9],
        files: [AnalysisShots.payloadName]
    ) { data in AnalysisShots.merge(&data, count: 10, records: [:], covered: [0...9]) }
    func lookup(_ stamp: AnalysisStamp) -> Bool {
        AnalysisStore.lookup(.shots, media: 1, stamp: stamp, need: 0...9, in: dir)
            != .miss([0...9])
    }
    let variants: [(String, AnalysisStamp)] = [
        ("source.size", AnalysisStamp(source: AnalysisSourceID(size: 101, modified: 200, duration: 300), kind: .shots, version: 1, parameters: "p", osBuild: "25F80", device: "cpu", reader: "raw", conversion: nil)),
        ("source.modified", AnalysisStamp(source: AnalysisSourceID(size: 100, modified: 201, duration: 300), kind: .shots, version: 1, parameters: "p", osBuild: "25F80", device: "cpu", reader: "raw", conversion: nil)),
        ("source.duration", AnalysisStamp(source: AnalysisSourceID(size: 100, modified: 200, duration: 301), kind: .shots, version: 1, parameters: "p", osBuild: "25F80", device: "cpu", reader: "raw", conversion: nil)),
        ("version", AnalysisStamp(source: source, kind: .shots, version: 2, parameters: "p", osBuild: "25F80", device: "cpu", reader: "raw", conversion: nil)),
        ("parameters", AnalysisStamp(source: source, kind: .shots, version: 1, parameters: "q", osBuild: "25F80", device: "cpu", reader: "raw", conversion: nil)),
        ("osBuild", AnalysisStamp(source: source, kind: .shots, version: 1, parameters: "p", osBuild: "25G1", device: "cpu", reader: "raw", conversion: nil)),
        ("device", AnalysisStamp(source: source, kind: .shots, version: 1, parameters: "p", osBuild: "25F80", device: "gpu", reader: "raw", conversion: nil)),
        ("reader", AnalysisStamp(source: source, kind: .shots, version: 1, parameters: "p", osBuild: "25F80", device: "cpu", reader: "converted", conversion: nil)),
    ]
    let hit = AnalysisStore.lookup(.shots, media: 1, stamp: base, need: 0...9, in: dir)
    let misses = variants.map { ($0.0, lookup($0.1)) }
    let leaked = misses.filter { $0.1 }.map(\.0)
    row("P1", hit != .miss([0...9]) && leaked.isEmpty && !variants.isEmpty,
        "the base stamp \(hit == .miss([0...9]) ? "MISSED" : "hits"); each of "
            + "\(variants.map(\.0).joined(separator: ", ")) alone misses"
            + (leaked.isEmpty ? "" : " — but \(leaked) hit"))
} catch {
    row("P1", false, "publish failed: \(error.localizedDescription)")
}

// MARK: - P2 coverage union and the hit rule with the margin

do {
    let dir = folder("p2")
    for range in [10...20, 21...30, 40...50] {
        try AnalysisStore.publish(
            kind: .shots, cacheDir: dir, mediaID: 1, stamp: base, covered: [range],
            files: [AnalysisShots.payloadName]
        ) { data in AnalysisShots.merge(&data, count: 60, records: [:], covered: [range]) }
    }
    let marker = AnalysisStore.readMarker(.shots, media: 1, in: dir)
    let unionOK = marker?.coverage == [[10, 30], [40, 50]]
    guard let (_, fixture, _) = project(shotsPath) else {
        throw AnalysisStore.StoreError.write("the shots fixture did not probe")
    }
    let grid = AnalysisGrid(media: fixture)
    let margin = AnalysisKind.shots.margin
    let inside = grid.need(23...27, margin: margin)  // 10…40
    let first = AnalysisStore.lookup(.shots, media: 1, stamp: base, need: inside, in: dir)
    let edge = grid.need(15...27, margin: margin)  // 2…40: its own indices covered, not the margin
    let second = AnalysisStore.lookup(.shots, media: 1, stamp: base, need: edge, in: dir)
    try AnalysisStore.publish(
        kind: .shots, cacheDir: dir, mediaID: 1, stamp: base, covered: [31...39],
        files: [AnalysisShots.payloadName]
    ) { data in AnalysisShots.merge(&data, count: 60, records: [:], covered: [31...39]) }
    let third = AnalysisStore.lookup(.shots, media: 1, stamp: base, need: inside, in: dir)
    let after = AnalysisStore.readMarker(.shots, media: 1, in: dir)?.coverage
    let ok = unionOK && margin == 13 && inside == 10...40 && first == .miss([31...39])
        && second == .miss([2...9, 31...39]) && third != .miss([31...39])
        && after == [[10, 50]]
    row("P2", ok,
        "coverage \(marker?.coverage ?? []) (want [[10,30],[40,50]]); margin \(margin); window "
            + "23…27 needs \(inside) → \(first); 15…27 needs \(edge) → \(second); after 31…39 "
            + "→ \(third), coverage \(after ?? [])")
} catch {
    row("P2", false, "publish failed: \(error.localizedDescription)")
}

// MARK: - P3 the cut rule

do {
    typealias R = AnalysisShots.Record
    func records(_ n: Int, _ set: [Int: (Float, Float)], empty: Set<Int> = []) -> [R] {
        (0..<n).map { k in
            if empty.contains(k) { return .empty }
            let (d1, d2) = set[k] ?? (0.01, 0.01)
            return R(pts: Int64(k) * 20_000, d1: d1, d2: d2)
        }
    }
    // A flash at 20: 20 and 21 tie at 2; 21's d2 (to 19) is small.
    let flash = AnalysisShots.cuts(records(60, [20: (2, 2), 21: (2, 0.01)]), in: 0...59)
    // A hard cut at 20: its d1 ties 30's within m; the earlier wins.
    let tie = AnalysisShots.cuts(
        records(60, [20: (0.9, 0.9), 21: (0.01, 0.9), 30: (0.9, 0.9), 31: (0.01, 0.9)]),
        in: 0...59)
    // A dissolve: d1 0.2 for 20 frames, under T.
    var dissolveSet: [Int: (Float, Float)] = [:]
    for k in 20..<40 { dissolveSet[k] = (0.2, 0.33) }
    let dissolve = AnalysisShots.cuts(records(60, dissolveSet), in: 0...59)
    // m: cuts 8 apart (the smaller suppressed) and 14 apart (both kept).
    let near = AnalysisShots.cuts(
        records(80, [20: (0.9, 0.9), 21: (0.01, 0.9), 28: (0.5, 0.5), 29: (0.01, 0.5)]),
        in: 0...79)
    let far = AnalysisShots.cuts(
        records(80, [20: (0.9, 0.9), 21: (0.01, 0.9), 34: (0.5, 0.5), 35: (0.01, 0.5)]),
        in: 0...79)
    // No frame within m + 1 after 20 (21…33 empty; 34 holds a small d2): a cut;
    // and a frame at the media's last index: a cut.
    let gap = AnalysisShots.cuts(
        records(60, [20: (0.9, 0.01), 34: (0.01, 0.01)], empty: Set(21...33)), in: 0...59)
    let end = AnalysisShots.cuts(records(30, [29: (0.9, 0.9)]), in: 0...29)
    let ok = flash.isEmpty && tie == [20] && dissolve.isEmpty && near == [20]
        && far == [20, 34] && gap == [20] && end == [29]
    row("P3", ok,
        "flash \(flash) (want []), tie \(tie) ([20]), dissolve \(dissolve) ([]), 8 apart "
            + "\(near) ([20]), 14 apart \(far) ([20, 34]), no frame within m+1 \(gap) ([20]), "
            + "at the end \(end) ([29]); T \(AnalysisShots.threshold), m "
            + "\(AnalysisShots.neighbourhood)")
}

// MARK: - P4 frames.bin round trip

do {
    typealias R = AnalysisShots.Record
    let written: [Int: R] = [
        0: R(pts: 0, d1: 0, d2: 0), 3: R(pts: 60_000, d1: 0.5, d2: 1.25),
        7: R(pts: 140_000, d1: 2, d2: 0.34),
    ]
    var data = Data()
    AnalysisShots.merge(&data, count: 10, records: written, covered: [0...9])
    let back = AnalysisShots.decode(data, count: 10)
    let want = (0..<10).map { written[$0] ?? .empty }
    // The third record's bytes, spelled by hand: little-endian Int64, Float32, Float32.
    let hand: [UInt8] = [0x60, 0xEA, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x3F, 0, 0, 0xA0, 0x3F]
    let third = [UInt8](data[(3 * 16)..<(4 * 16)])
    let empty = [UInt8](data[(1 * 16)..<(2 * 16)])
    let emptyHand: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF] + [UInt8](repeating: 0, count: 8)
    row("P4", data.count == 160 && back == want && third == hand && empty == emptyHand,
        "\(data.count) bytes (want 160); decode equal \(back == want); record 3 \(third == hand ? "is" : "is NOT") the hand-spelt bytes; an empty index \(empty == emptyHand ? "is" : "is NOT") pts −1, 0, 0")
}

// MARK: - P5 the canned rule

do {
    let canned = AnalysisMarker(
        stamp: nil, canned: true, source: source, files: [AnalysisShots.payloadName],
        coverage: [[0, 9]])
    let other = AnalysisStamp(
        source: AnalysisSourceID(size: 999, modified: 200, duration: 300), kind: .shots,
        version: 1, parameters: "p", osBuild: "25F80", device: "cpu", reader: "raw",
        conversion: nil)
    UserDefaults.standard.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
    let without = canned.answers(for: base)
    UserDefaults.standard.setVolatileDomain(
        [AnalysisLane.devCannedKey: true], forName: UserDefaults.argumentDomain)
    let with = canned.answers(for: base)
    let wrongSource = canned.answers(for: other)
    UserDefaults.standard.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
    row("P5", !without && with && !wrongSource,
        "without the flag \(without) (want false), with it \(with) (true), with it and "
            + "another source \(wrongSource) (false)")
}

// MARK: - P6 trimmed, ×2 and reversed mapping

if let (made, media, track) = project(shotsPath) {
    func placed(_ ops: (UInt32) -> [ReelOp]) -> AnalysisClipTimes? {
        guard let withClip = (try? made.applying(.addClip(track: track, media: media.id, at: 0)))?.project,
            let id = withClip.snapshot.clips.last?.id,
            let edited = (try? withClip.applying(ops(id)))?.project,
            let clip = edited.snapshot.clips.first(where: { $0.id == id })
        else { return nil }
        return AnalysisClipTimes(clip: clip, media: media, map: edited.sourceMap(id))
    }
    let d = media.duration
    let trimmed = placed { [.trimStart(clip: $0, to: 600_000)] }
    let doubled = placed { [.setSpeed(clip: $0, rate: 2)] }
    let reversed = placed { [.setReversed(clip: $0, reversed: true)] }
    let s: Int64 = 2_400_000  // 4 s, frame 120 of the 30 fps fixture
    let t = trimmed.map { ($0.window, $0.clipTime(ofSource: s)) }
    let x = doubled.map { ($0.window, $0.clipTime(ofSource: s)) }
    let r = reversed.map { ($0.window, $0.clipTime(ofSource: s)) }
    let ok = t?.0.lowerBound == 600_000 && t?.1 == 1_800_000
        && x?.0.lowerBound == 0 && x?.1 == 1_200_000
        && r?.0.upperBound == d && r?.1 == d - s
    row("P6", ok,
        "trimmed to 1 s: window \(String(describing: t?.0)), source 4 s at \(String(describing: t?.1)) (want 1800000); ×2: \(String(describing: x?.0)), \(String(describing: x?.1)) (1200000); reversed (pivot \(d)): \(String(describing: r?.0)), \(String(describing: r?.1)) (\(d - s))")
} else {
    row("P6", false, "the shots fixture did not probe")
}

// MARK: - P7 the VFR twin

if let (_, media, _) = project(vfrPath) {
    let url = URL(fileURLWithPath: vfrPath)
    let grid = AnalysisGrid(media: media)
    func job(_ name: String, _ ranges: [ClosedRange<Int>]) -> [AnalysisShots.Record]? {
        let dir = folder(name)
        guard let stamp = AnalysisStamp.make(kind: .shots, media: media, url: url, input: nil, fullRange: false)
        else { return nil }
        let request = AnalysisRequest(
            kind: .shots, cacheDir: dir, media: media, url: url, stamp: stamp, input: nil,
            ranges: ranges)
        guard (try? AnalysisShots.run(request, cancelled: { false })) == true,
            let data = AnalysisStore.readPayload(.shots, media: media.id, file: AnalysisShots.payloadName, in: dir)
        else { return nil }
        return AnalysisShots.decode(data, count: grid.count)
    }
    if let whole = job("p7-whole", [0...grid.lastIndex]) {
        let gaps = (1..<(grid.lastIndex - 1)).filter { !whole[$0].holdsFrame && whole[$0 - 1].holdsFrame && whole[$0 + 1].holdsFrame }
        var details: [String] = []
        var ok = !gaps.isEmpty
        for gap in gaps {
            let start = gap + 1
            guard let part = job("p7-from-\(start)", [start...grid.lastIndex]) else {
                ok = false
                details.append("the job from \(start) failed")
                continue
            }
            let span = start...min(grid.lastIndex, start + 20)
            let same = span.allSatisfy { AnalysisShots.bytes(of: whole[$0]) == AnalysisShots.bytes(of: part[$0]) }
            let differing = span.filter { whole[$0] != part[$0] }
            ok = ok && same
            details.append("gap at \(gap): \(span) \(same ? "equal" : "DIFFER at \(differing)")")
        }
        // The cut after the first gap (the fixture's frame 120, 4 s): found by both.
        let cutTick: Int64 = 2_400_000
        let wholeCuts = AnalysisShots.cuts(whole, in: 0...grid.lastIndex)
        let cutIndex = wholeCuts.first { abs(whole[$0].pts - cutTick) < 30_000 }
        var partFound = false
        if let gap = gaps.first, let part = job("p7-from-\(gap + 1)", [(gap + 1)...grid.lastIndex]),
            let cutIndex
        {
            partFound = AnalysisShots.cuts(part, in: (gap + 1)...grid.lastIndex).contains(cutIndex)
        }
        ok = ok && cutIndex != nil && partFound
        row("P7", ok,
            "fps \(media.fps.num)/\(media.fps.den), \(grid.count) indices; "
                + details.joined(separator: "; ")
                + "; the cut at 4 s: index \(String(describing: cutIndex)) in the whole-file "
                + "job, \(partFound ? "found" : "NOT found") by the job after the gap; whole-file cuts \(wholeCuts)")
    } else {
        row("P7", false, "the whole-file job failed")
    }
} else {
    row("P7", false, "the VFR twin did not probe")
}

// MARK: - P8 two disjoint publishes from one on-disk state, either order

do {
    typealias R = AnalysisShots.Record
    let a: [Int: R] = [2: R(pts: 40_000, d1: 0.5, d2: 0.5)]
    let b: [Int: R] = [22: R(pts: 440_000, d1: 0.75, d2: 0.75)]
    func publish(_ dir: URL, _ records: [Int: R], _ range: ClosedRange<Int>) throws {
        try AnalysisStore.publish(
            kind: .shots, cacheDir: dir, mediaID: 1, stamp: base, covered: [range],
            files: [AnalysisShots.payloadName]
        ) { data in AnalysisShots.merge(&data, count: 30, records: records, covered: [range]) }
    }
    let ab = folder("p8-ab")
    let ba = folder("p8-ba")
    let both = folder("p8-concurrent")
    try publish(ab, a, 0...9)
    try publish(ab, b, 20...29)
    try publish(ba, b, 20...29)
    try publish(ba, a, 0...9)
    let group = DispatchGroup()
    for (records, range) in [(a, 0...9), (b, 20...29)] {
        group.enter()
        DispatchQueue.global().async {
            try? publish(both, records, range)
            group.leave()
        }
    }
    group.wait()
    func state(_ dir: URL) -> (Data?, [[Int]]?) {
        (AnalysisStore.readPayload(.shots, media: 1, file: AnalysisShots.payloadName, in: dir),
         AnalysisStore.readMarker(.shots, media: 1, in: dir)?.coverage)
    }
    let (abData, abCover) = state(ab)
    let (baData, baCover) = state(ba)
    let (cData, cCover) = state(both)
    let records = abData.map { AnalysisShots.decode($0, count: 30) }
    let ok = abData != nil && abData == baData && abData == cData
        && abCover == [[0, 9], [20, 29]] && baCover == abCover && cCover == abCover
        && records?[2] == a[2] && records?[22] == b[22]
    row("P8", ok,
        "A then B, B then A and both at once: payloads \(abData == baData && abData == cData ? "equal" : "DIFFER"); coverage \(abCover ?? []), \(baCover ?? []), \(cCover ?? []); both records kept \(records?[2] == a[2] && records?[22] == b[22])")
} catch {
    row("P8", false, "publish failed: \(error.localizedDescription)")
}

// MARK: - P9 a publish during a save writes nothing until the save ends

do {
    let dir = folder("p9")
    let ledger = MediaImporter.CacheLedger.shared
    let marker = AnalysisStore.markerURL(.shots, media: 1, in: dir)
    let payload = AnalysisStore.payloadURL(
        .shots, media: 1, file: AnalysisShots.payloadName, in: dir)
    func present() -> (Bool, Bool) {
        (FileManager.default.fileExists(atPath: marker.path),
         FileManager.default.fileExists(atPath: payload.path))
    }
    let save = ledger.saveBegan(cacheDir: dir)
    let done = DispatchSemaphore(value: 0)
    var failure: String?
    DispatchQueue.global().async {
        do {
            try AnalysisStore.publish(
                kind: .shots, cacheDir: dir, mediaID: 1, stamp: base, covered: [0...9],
                files: [AnalysisShots.payloadName]
            ) { data in AnalysisShots.merge(&data, count: 10, records: [:], covered: [0...9]) }
        } catch {
            failure = error.localizedDescription
        }
        done.signal()
    }
    // The publish waits on the ledger; 0.5 s is ample for a write made outside it.
    let finishedDuring = done.wait(timeout: .now() + 0.5) == .success
    let during = present()
    ledger.saveEnded(cacheDir: dir, save: save)
    let finished = done.wait(timeout: .now() + 10) == .success
    let after = present()
    let ok = !finishedDuring && !during.0 && !during.1 && finished && failure == nil
        && after.0 && after.1
    row("P9", ok,
        "during the save: publish returned \(finishedDuring) (want false), marker \(during.0), "
            + "payload \(during.1) (want false, false); after saveEnded: returned \(finished), "
            + "marker \(after.0), payload \(after.1) (want true, true)"
            + (failure.map { "; the publish failed: \($0)" } ?? ""))
}

// MARK: - P10 a cancelled shots job keeps what it stored (#435)

if let (_, media, _) = project(shotsPath) {
    let url = URL(fileURLWithPath: shotsPath)
    let grid = AnalysisGrid(media: media)
    func request(_ dir: URL) -> AnalysisRequest? {
        AnalysisStamp.make(kind: .shots, media: media, url: url, input: nil, fullRange: false).map {
            AnalysisRequest(
                kind: .shots, cacheDir: dir, media: media, url: url, stamp: $0, input: nil,
                ranges: [0...grid.lastIndex])
        }
    }
    let wholeDir = folder("p10-whole"), cutDir = folder("p10-cancelled")
    var halfway = false
    var whole: Bool?, cut: Bool?, thrown: String?
    do {
        if let a = request(wholeDir) { whole = try AnalysisShots.run(a, cancelled: { false }) }
        if let b = request(cutDir) {
            cut = try AnalysisShots.run(
                b, cancelled: { halfway }, progress: { if $0 >= 0.5 { halfway = true } })
        }
    } catch {
        thrown = error.localizedDescription
    }
    let coverage = AnalysisStore.readMarker(.shots, media: media.id, in: cutDir)?.coverage ?? []
    let wholeBytes = AnalysisStore.readPayload(
        .shots, media: media.id, file: AnalysisShots.payloadName, in: wholeDir)
    let cutBytes = AnalysisStore.readPayload(
        .shots, media: media.id, file: AnalysisShots.payloadName, in: cutDir)
    var k = -1
    if coverage.count == 1, coverage[0].count == 2, coverage[0][0] == 0 { k = coverage[0][1] }
    let span = (k + 1) * 16
    let equal = k >= 0 && wholeBytes.map { $0.count >= span } == true
        && cutBytes.map { $0.count >= span } == true
        && wholeBytes!.prefix(span) == cutBytes!.prefix(span)
    row("P10", thrown == nil && whole == true && cut == false && k > 0 && k < grid.lastIndex
            && equal,
        "the whole run answered \(String(describing: whole)); the run cancelled at half answered "
            + "\(String(describing: cut)) (want false); its coverage \(coverage) (want one range "
            + "[0, k], 0 < k < \(grid.lastIndex)); records 0…\(k) "
            + "\(equal ? "byte-equal to the whole run's" : "DIFFER or are missing")"
            + (thrown.map { "; threw \($0)" } ?? ""))
} else {
    row("P10", false, "the shots fixture did not probe")
}

// MARK: - P11 a cancelled job's publish only merges (#435)

if let (_, media, _) = project(shotsPath) {
    let s1 = base
    let s0 = AnalysisStamp(
        source: source, kind: .shots, version: 1, parameters: "q", osBuild: "25F80",
        device: "cpu", reader: "raw", conversion: nil)
    func request(_ dir: URL, _ stamp: AnalysisStamp) -> AnalysisRequest {
        AnalysisRequest(
            kind: .shots, cacheDir: dir, media: media, url: URL(fileURLWithPath: shotsPath),
            stamp: stamp, input: nil, ranges: [0...29])
    }
    func publish(_ dir: URL, _ stamp: AnalysisStamp, _ range: ClosedRange<Int>) throws {
        try AnalysisStore.publish(
            kind: .shots, cacheDir: dir, mediaID: 1, stamp: stamp, covered: [range],
            files: [AnalysisShots.payloadName]
        ) { data in AnalysisShots.merge(&data, count: 30, records: [:], covered: [range]) }
    }
    func cancelled(_ dir: URL, _ stamp: AnalysisStamp, _ range: ClosedRange<Int>) {
        AnalysisStore.publishCancelled(request(dir, stamp)) { try publish(dir, stamp, range) }
    }
    func bytes(_ dir: URL) -> (Data?, Data?) {
        (try? Data(contentsOf: AnalysisStore.markerURL(.shots, media: 1, in: dir)),
         AnalysisStore.readPayload(.shots, media: 1, file: AnalysisShots.payloadName, in: dir))
    }
    func marker(_ dir: URL) -> AnalysisMarker? { AnalysisStore.readMarker(.shots, media: 1, in: dir) }
    do {
        let a = folder("p11-a")
        try publish(a, s1, 0...9)
        let before = bytes(a)
        cancelled(a, s0, 0...4)
        let after = bytes(a)
        let keptA = before.0 != nil && before.1 != nil && before.0 == after.0 && before.1 == after.1
        cancelled(a, s1, 10...19)
        let mergedB = marker(a)?.coverage == [[0, 19]] && marker(a)?.stamp?.matches(s1) == true
        let c = folder("p11-c")
        cancelled(c, s0, 0...4)
        let freshC = marker(c)?.stamp?.matches(s0) == true && marker(c)?.coverage == [[0, 4]]
        let d = folder("p11-d")
        try publish(d, s1, 0...9)
        try publish(d, s0, 0...4)
        let replacedD = marker(d)?.stamp?.matches(s0) == true && marker(d)?.coverage == [[0, 4]]
        row("P11", keptA && mergedB && freshC && replacedD,
            "(a) a cancelled publish under another stamp over an S1 cache: marker and frames.bin "
                + "\(keptA ? "byte-identical" : "CHANGED"); (b) under S1: coverage "
                + "\(marker(a)?.coverage ?? []) (want [[0, 19]]); (c) on an empty cache: marker "
                + "stamp S0 \(freshC) with coverage \(marker(c)?.coverage ?? []); (d) an ordinary "
                + "publish under S0 over S1 replaces \(replacedD) (coverage "
                + "\(marker(d)?.coverage ?? []))")
    } catch {
        row("P11", false, "publish failed: \(error.localizedDescription)")
    }
} else {
    row("P11", false, "the shots fixture did not probe")
}

let answer = try JSONSerialization.data(withJSONObject: ["rows": rows])
print(String(decoding: answer, as: UTF8.self))
