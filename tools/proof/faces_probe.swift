// Road map "creator-jobs" CJ3 — rows P1–P5 of `faces_proof.py`, driven through
// the app's own `AnalysisFaces`, `AnalysisStore.publishFile`, `AnalysisStamp`
// and `AgentServer.facesAnswer`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, with `-D FRAMEJOB_DEV_TOOLS`, module `FrameJob`, against
// `libframejob_core.a`, through `swift_build.py`. One run:
//
//   faces_probe <request.json>
//
// The request names `fixture` (a movie: P4's stamp, P5's clip) and `work` (a
// scratch folder this run owns). The answer is one JSON object on stdout,
// `{"rows": [{"id", "pass", "detail"}], "row_bytes": {…}}`.
import AppKit

var rows: [[String: Any]] = []
var extra: [String: Any] = [:]
func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}

let arguments = CommandLine.arguments
guard arguments.count == 2,
    let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])),
    let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
    let fixturePath = request["fixture"] as? String, let workPath = request["work"] as? String
else {
    FileHandle.standardError.write(Data("usage: faces_probe <request.json>\n".utf8))
    exit(2)
}
let work = URL(fileURLWithPath: workPath)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

func folder(_ name: String) -> URL {
    let url = work.appendingPathComponent(name, isDirectory: true)
    try? FileManager.default.removeItem(at: url)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

typealias Face = AnalysisFaces.Face
typealias Sample = AnalysisFaces.Sample

func face(_ x: Float, _ y: Float, _ w: Float = 0.1, _ h: Float = 0.2, seed: Float = 0) -> Face {
    Face(x: x, y: y, width: w, height: h, confidence: 0.7 + seed / 1000, roll: -0.0921 - seed / 997,
         yaw: 0.1227 + seed / 991, mouthGap: seed == 3 ? .nan : 0.0712 + seed / 983,
         mouthWidth: 0.3654 + seed / 977)
}

/// Sample k of a synthetic media: k % 3 faces (one absent-frame sample every 7th).
func synthetic(_ k: Int) -> Sample {
    if k % 7 == 6 { return .empty }
    let n = k % 3
    return Sample(
        pts: Int64(k) * 60_000 + 20_000,
        faces: (0..<n).map { face(0.1 + Float($0) * 0.3 + Float(k) / 1000, 0.2, seed: Float(k + $0)) })
}

let fixtureURL = URL(fileURLWithPath: fixturePath)
let made: (ReelProject, MediaSnapshot, UInt32)? = {
    guard let descriptor = try? MediaImporter.probeBlocking(url: fixtureURL),
        let blank = ReelProject.new(width: 1920, height: 1080, fps: Fps(num: 30, den: 1)),
        let project = (try? blank.applying(.addMedia(descriptor: descriptor)))?.project,
        let media = project.snapshot.media.last, let track = project.snapshot.tracks.first?.id
    else { return nil }
    return (project, media, track)
}()
let source = AnalysisSourceID(size: 100, modified: 200, duration: 600_000_000)
let base = AnalysisStamp(
    source: source, kind: .faces, version: 1, parameters: "p", osBuild: "25F80",
    device: AnalysisFaces.device, reader: "raw", conversion: nil, vision: AnalysisFaces.vision)
let count = 50

/// Publishes samples `range` of the synthetic media through `publishFile` and
/// `AnalysisFaces.write`; answers whether the write merged.
@discardableResult
func publish(_ dir: URL, _ range: ClosedRange<Int>) throws -> Bool {
    var merged = false
    var found: [Int: Sample] = [:]
    for k in range { found[k] = synthetic(k) }
    try AnalysisStore.publishFile(
        kind: .faces, cacheDir: dir, mediaID: 1, stamp: base, covered: [range],
        files: [AnalysisFaces.payloadName]
    ) { onDisk, partial in
        merged = try AnalysisFaces.write(
            onDisk: onDisk, partial: partial, count: count, covering: range, samples: found)
        return merged
    }
    return merged
}
func fileURL(_ dir: URL) -> URL {
    AnalysisStore.payloadURL(.faces, media: 1, file: AnalysisFaces.payloadName, in: dir)
}
func coverage(_ dir: URL) -> [[Int]] {
    AnalysisStore.readMarker(.faces, media: 1, in: dir)?.coverage ?? []
}

// MARK: - P1 the codec round trip, the merge in either order, a damaged file

do {
    let all = (0..<count).map(synthetic)
    let bytes = AnalysisFaces.encode(all)
    let back = AnalysisFaces.decode(bytes)
    let roundTrip = back?.count == count && back?.samples == all
    let expectedSize = 16 + count * 16 + all.reduce(0) { $0 + $1.faces.count } * 36
    let header = [UInt8](bytes.prefix(8))
    let a = folder("p1-a"), b = folder("p1-b"), c = folder("p1-c")
    let aFirst = try publish(a, 0...9), aSecond = try publish(a, 20...29)
    let bFirst = try publish(b, 20...29), bSecond = try publish(b, 0...9)
    let aBytes = try Data(contentsOf: fileURL(a)), bBytes = try Data(contentsOf: fileURL(b))
    let decoded = AnalysisFaces.decode(aBytes)
    let held = (0..<count).allSatisfy { k in
        let want = (0...9).contains(k) || (20...29).contains(k) ? synthetic(k) : Sample.empty
        return decoded?.samples[k] == want
    }
    try publish(c, 0...49)
    try Data("not a samples file".utf8).write(to: fileURL(c))
    let damagedMerged = try publish(c, 10...19)
    let afterDamage = AnalysisFaces.decode(try Data(contentsOf: fileURL(c)))
    let fresh = afterDamage.map { d in
        (0..<count).allSatisfy { k in d.samples[k] == ((10...19).contains(k) ? synthetic(k) : .empty) }
    } ?? false
    row("P1", roundTrip && bytes.count == expectedSize && header == Array("FJFS".utf8) + [1, 0, 36, 0]
            && !aFirst && aSecond && !bFirst && bSecond && aBytes == bBytes && held
            && coverage(a) == [[0, 9], [20, 29]] && coverage(b) == coverage(a)
            && !damagedMerged && fresh && coverage(c) == [[10, 19]],
        "round trip \(roundTrip) (\(bytes.count) bytes, want \(expectedSize)), header \(header); "
            + "merged \(aFirst), \(aSecond) and \(bFirst), \(bSecond) (want false, true ×2); "
            + "either order byte-equal \(aBytes == bBytes), samples held \(held), coverage "
            + "\(coverage(a)) and \(coverage(b)); a damaged file: merged \(damagedMerged) "
            + "(want false), written fresh \(fresh), coverage \(coverage(c)) (want [[10, 19]])")
} catch {
    row("P1", false, "threw \(error)")
}

// MARK: - P2 CJ-31's order and the y flip

do {
    let right = face(0.6, 0.1), left = face(0.1, 0.5), lowSameX = face(0.3, 0.6, 0.2, 0.2),
        highSameX = face(0.3, 0.1, 0.2, 0.2)
    let got = AnalysisFaces.ordered([right, lowSameX, left, highSameX])
    let order = got == [left, highSameX, lowSameX, right]
    let flipped = AnalysisFaces.topLeft(CGRect(x: 0.125, y: 0.125, width: 0.25, height: 0.5))
    let flip = abs(flipped.minY - 0.375) < 1e-12 && flipped.minX == 0.125
        && flipped.height == 0.5
    let flip2 = AnalysisFaces.topLeft(CGRect(x: 0.5, y: 0.0, width: 0.25, height: 0.25))
    row("P2", order && flip && abs(flip2.minY - 0.75) < 1e-12 && flip2.width == 0.25,
        "ordered by centre x then y \(order); Vision's (0.125, 0.125, 0.25, 0.5) → "
            + "\(flipped) (want y 0.375), (0.5, 0, 0.25, 0.25) → \(flip2) (want y 0.75)")
}

// MARK: - P3 the sample a frame serves

do {
    let grid = AnalysisGrid(samplesPerSecond: 10, duration: 1_200_000)
    func pick(_ frames: [Int64]) -> [Int: Int64] {
        var out: [Int: Int64] = [:]
        var previous: Int64?
        for pts in frames {
            if let ks = AnalysisFaces.samples(at: pts, after: previous, grid: grid) {
                for k in ks { out[k] = pts }
            }
            previous = pts
        }
        return out
    }
    let at25 = (0..<50).map { Int64($0) * 24_000 }
    let picked = pick(at25)
    let firstAtOrAfter = (0..<grid.count).allSatisfy { k in
        let t = grid.ticks(of: k)
        return picked[k] == at25.first(where: { $0 >= t })
    }
    let sample1 = picked[1].map { $0 / 24_000 }
    let gap = pick([0, 24_000, 200_000, 224_000])
    let gapOK = gap[0] == 0 && gap[1] == nil && gap[2] == nil && gap[3] == 200_000
    row("P3", firstAtOrAfter && sample1 == 3 && gapOK,
        "25 fps at 10 a second: every sample the first frame at or after its tick "
            + "\(firstAtOrAfter); sample 1 → frame \(sample1.map(String.init) ?? "none") (want 3); "
            + "frames 0, 24000, 200000, 224000: samples 0…3 → \((0...3).map { gap[$0] ?? -1 }) "
            + "(want [0, -1, -1, 200000])")
}

// MARK: - P4 the stamp

if let (_, media, _) = made {
    let stamp = AnalysisStamp.make(
        kind: .faces, media: media, url: fixtureURL, input: nil, fullRange: false)
    let json = stamp.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) } ?? ""
    let rect = AnalysisFaces.rectanglesDevice.rawValue, lm = AnalysisFaces.landmarksDevice.rawValue
    let want = "rectangles:\(rect)" + (AnalysisFaces.landmarks ? ";landmarks:\(lm)" : "")
    let vision = AnalysisVisionStamp(
        request: AnalysisFaces.landmarks ? "face_rectangles+face_landmarks" : "face_rectangles",
        quality: AnalysisFaces.landmarks ? "constellation_76" : "none", revision: 3,
        rate: AnalysisFaces.rateName, readSize: String(AnalysisFaces.longSide))
    let grid = AnalysisKind.faces.grid(of: media)
    let ok = stamp?.version == 1 && stamp?.kind == .faces && stamp?.device == want
        && stamp?.vision == vision && !json.contains(fixtureURL.path)
        && !json.contains(fixtureURL.lastPathComponent) && grid.num == AnalysisFaces.rate
        && grid.den == 1
    row("P4", ok,
        "the stamp \(json); device \(stamp?.device ?? "none") (want \(want)); vision "
            + "\(String(describing: stamp?.vision)); no path \(!json.contains(fixtureURL.lastPathComponent)); "
            + "grid \(grid.num)/\(grid.den), \(grid.count) samples")
} else {
    row("P4", false, "the fixture \(fixturePath) did not probe")
}

// MARK: - P5 the answer: 4 decimals, null for NaN, the row's bytes, the cap

do {
    let grid = AnalysisGrid(samplesPerSecond: AnalysisFaces.rate, duration: 600_000 * 3600)
    let sampleFace = Face(
        x: 0.43218765, y: 0.27771234, width: 0.18753968, height: 0.33340388,
        confidence: 0.84635013, roll: -0.10431069, yaw: -0.09203885, mouthGap: 0.07617188,
        mouthWidth: 0.36547852)
    var nanFace = sampleFace
    nanFace.yaw = .nan
    nanFace.mouthGap = .nan
    let late = 35_940
    var samples = [Sample](repeating: .empty, count: grid.count)
    samples[late] = Sample(pts: grid.ticks(of: late) + 20_000, faces: [sampleFace])
    samples[late + 1] = Sample(pts: grid.ticks(of: late + 1), faces: [nanFace, sampleFace])
    var clip: AnalysisClipTimes?
    if let (project, media, track) = made,
        let placed = (try? project.applying(.addClip(track: track, media: media.id, at: 36_000_000)))?.project,
        let id = placed.snapshot.clips.last?.id,
        let edited = (try? placed.applying(.trimStart(clip: id, to: 36_000_000 + 600_000)))?.project,
        let snapshot = edited.snapshot.clips.first(where: { $0.id == id })
    {
        clip = AnalysisClipTimes(clip: snapshot, media: media, map: edited.sourceMap(id))
    }
    func answer(_ indices: [Int], clip: AnalysisClipTimes?) throws -> Data {
        let fields = try AgentServer.facesAnswer(
            samples, indices: indices, grid: grid, clip: clip, landmarks: true, from: 0,
            to: grid.duration)
        return try JSONSerialization.data(withJSONObject: fields["samples"] ?? [])
    }
    let bytes = try answer([late, late + 1], clip: nil)
    let text = String(decoding: bytes, as: UTF8.self)
    func groups(_ pattern: String, in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
    let numbers = groups("-?\\d+\\.(\\d+)", in: text)
    let decimals = numbers.map(\.count).max() ?? 0
    let nulls = text.components(separatedBy: "null").count - 1
    let one = try answer([late], clip: nil).count - 2
    let oneClip = try clip.map { try answer([late], clip: $0).count - 2 } ?? 0
    let fit = (AgentServer.analysisAnswerCap - 2) / (one + 1)
    let fitClip = oneClip > 0 ? (AgentServer.analysisAnswerCap - 2) / (oneClip + 1) : 0
    extra["row_bytes"] = [
        "one_face": one, "one_face_clip": oneClip, "rows_fit": fit, "rows_fit_clip": fitClip,
        "seconds_fit": Double(fit) / AnalysisFaces.rate,
        "seconds_fit_clip": Double(fitClip) / AnalysisFaces.rate, "sample": text,
    ]
    // The cap: four faces in every sample of an hour.
    var crowded = samples
    for k in 0..<crowded.count {
        crowded[k] = Sample(pts: grid.ticks(of: k), faces: Array(repeating: sampleFace, count: 4))
    }
    var refused = ""
    var fits: Int64 = -1
    do {
        _ = try AgentServer.facesAnswer(
            crowded, indices: Array(0..<crowded.count), grid: grid, clip: nil, landmarks: true,
            from: 0, to: grid.duration)
    } catch let error as AgentServer.ToolError {
        refused = error.message
        if let match = groups("to at most (\\d+)", in: refused).first { fits = Int64(match) ?? -1 }
    }
    let kept = (0..<crowded.count).filter { grid.ticks(of: $0) < fits }
    var answered = false
    var firstOut: Int64 = -1
    if fits > 0 {
        let fields = try AgentServer.facesAnswer(
            crowded, indices: kept, grid: grid, clip: nil, landmarks: true, from: 0, to: fits)
        answered = (fields["count"] as? Int) == kept.count
        firstOut = grid.ticks(of: kept.count)
        let encoded = try JSONSerialization.data(withJSONObject: fields["samples"] ?? [])
        var withOne = kept
        withOne.append(kept.count)
        let over = try? AgentServer.facesAnswer(
            crowded, indices: withOne, grid: grid, clip: nil, landmarks: true, from: 0,
            to: firstOut + 1)
        answered = answered && encoded.count <= AgentServer.analysisAnswerCap && over == nil
    }
    row("P5", decimals <= 4 && !numbers.isEmpty && nulls == 2 && one > 0 && oneClip > one
            && fits > 0 && answered && fits == firstOut,
        "at most \(decimals) decimals over \(numbers.count) numbers (want ≤ 4), \(nulls) nulls "
            + "(want 2: the NaN yaw and gap); a one-face row \(one) bytes, \(oneClip) with clip; "
            + "\(fit) rows (\(Double(fit) / AnalysisFaces.rate) s) fit, \(fitClip) with clip; "
            + "the crowded hour refused naming to \(fits) (the first row out at \(firstOut)), "
            + "and to that to answers \(answered): \(refused.prefix(160))")
} catch {
    row("P5", false, "threw \(error)")
}

let out = try JSONSerialization.data(withJSONObject: ["rows": rows].merging(extra) { a, _ in a })
print(String(decoding: out, as: UTF8.self))
