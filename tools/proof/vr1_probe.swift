// Road map "creator-jobs" VR1 — rows P1–P7 of `vr1_proof.py`, driven through
// the app's own `AnalysisSubjects`, `AnalysisStore.publishFile`,
// `AnalysisStamp`, `AgentServer.subjectsAnswer`, `FramingAnalysis` and
// `SubjectsOverlay`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, with `-D FRAMEJOB_DEV_TOOLS`, module `FrameJob`, against
// `libframejob_core.a`, through `swift_build.py`. One run:
//
//   vr1_probe <request.json>
//
// The request names `fixture` (a movie: P3's stamp, P5's and P7's media A),
// `fixture_b` (P5's media B) and
// `work` (a scratch folder this run owns). The answer is one JSON object on
// stdout, `{"rows": [{"id", "pass", "detail"}], "row_bytes": {…}}`.
import AppKit
import Vision

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
    FileHandle.standardError.write(Data("usage: vr1_probe <request.json>\n".utf8))
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

typealias Box = AnalysisSubjects.Box
typealias Sample = AnalysisSubjects.Sample
typealias Subjects = AnalysisSubjects.Subjects

func box(_ x: Float, _ y: Float, _ w: Float = 0.1, _ h: Float = 0.2, seed: Float = 0) -> Box {
    Box(x: x, y: y, width: w, height: h, confidence: 0.7 + seed / 1000)
}

/// Sample k of a synthetic media: k % 3 people and (k + 1) % 2 salient boxes
/// (one absent-frame sample every 7th).
func synthetic(_ k: Int) -> Sample {
    if k % 7 == 6 { return .empty }
    let people = (0..<(k % 3)).map {
        box(0.1 + Float($0) * 0.3 + Float(k) / 1000, 0.2, seed: Float(k + $0))
    }
    let salient = (0..<((k + 1) % 2)).map { _ in box(0.4, 0.3, 0.3, 0.4, seed: Float(k)) }
    return Sample(pts: Int64(k) * 60_000 + 20_000, subjects: Subjects(people: people, salient: salient))
}

func apply(_ project: ReelProject?, _ op: ReelOp) -> ReelProject? {
    project.flatMap { (try? $0.applying(op))?.project }
}

let fixtureURL = URL(fileURLWithPath: fixturePath)
let descriptor = try? MediaImporter.probeBlocking(url: fixtureURL)
let descriptorB = (request["fixture_b"] as? String).flatMap {
    try? MediaImporter.probeBlocking(url: URL(fileURLWithPath: $0))
}
/// A 1920 × 1080 project holding the two fixtures (media A and B) and six tracks.
let made: (ReelProject, MediaSnapshot, MediaSnapshot, [UInt32])? = {
    func fail(_ why: String) -> (ReelProject, MediaSnapshot, MediaSnapshot, [UInt32])? {
        FileHandle.standardError.write(Data("vr1_probe: \(why)\n".utf8))
        return nil
    }
    guard let descriptor, let descriptorB else { return fail("a fixture did not probe") }
    guard var project = ReelProject.new(width: 1920, height: 1080, fps: Fps(num: 30, den: 1))
    else { return fail("no project") }
    for each in [descriptor, descriptorB] {
        do {
            guard let next = try project.applying(.addMedia(descriptor: each)).project else {
                return fail("add_media did not apply")
            }
            project = next
        } catch { return fail("add_media: \(error)") }
    }
    for index in 1..<6 {
        do {
            guard let next = try project.applying(.addTrack(index: index)).project else {
                return fail("add_track \(index) did not apply")
            }
            project = next
        } catch { return fail("add_track \(index): \(error)") }
    }
    let media = project.snapshot.media
    guard media.count == 2 else { return fail("\(media.count) media") }
    return (project, media[0], media[1], project.snapshot.tracks.map(\.id))
}()
let source = AnalysisSourceID(size: 100, modified: 200, duration: 600_000_000)
let base = AnalysisStamp(
    source: source, kind: .subjects, version: 1, parameters: "p", osBuild: "25F80",
    device: AnalysisSubjects.device, reader: "raw", conversion: nil, vision: AnalysisSubjects.vision)
let count = 50

/// Publishes samples `range` of the synthetic media through `publishFile` and
/// `AnalysisSubjects.write`; answers whether the write merged.
@discardableResult
func publish(_ dir: URL, _ range: ClosedRange<Int>) throws -> Bool {
    var merged = false
    var found: [Int: Sample] = [:]
    for k in range { found[k] = synthetic(k) }
    try AnalysisStore.publishFile(
        kind: .subjects, cacheDir: dir, mediaID: 1, stamp: base, covered: [range],
        files: [AnalysisSubjects.payloadName]
    ) { onDisk, partial in
        merged = try AnalysisSubjects.write(
            onDisk: onDisk, partial: partial, count: count, covering: range, samples: found)
        return merged
    }
    return merged
}
func fileURL(_ dir: URL) -> URL {
    AnalysisStore.payloadURL(.subjects, media: 1, file: AnalysisSubjects.payloadName, in: dir)
}
func coverage(_ dir: URL) -> [[Int]] {
    AnalysisStore.readMarker(.subjects, media: 1, in: dir)?.coverage ?? []
}

// MARK: - P1 the codec round trip, the merge in either order, a damaged file

do {
    let all = (0..<count).map(synthetic)
    let bytes = AnalysisSubjects.encode(all)
    let back = AnalysisSubjects.decode(bytes)
    let roundTrip = back?.count == count && back?.samples == all
    let boxes = all.reduce(0) { $0 + $1.subjects.people.count + $1.subjects.salient.count }
    let expectedSize = 16 + count * 16 + boxes * 20
    let header = [UInt8](bytes.prefix(8))
    // Sample 2's row: its first box, 2 people, 1 salient box.
    let rowAt = { (k: Int) -> [UInt8] in [UInt8](bytes[(16 + k * 16)..<(16 + k * 16 + 16)]) }
    let firstOf2 = (0..<2).reduce(0) {
        $0 + all[$1].subjects.people.count + all[$1].subjects.salient.count
    }
    let row2 = rowAt(2)
    let rowOK = row2[8] == UInt8(firstOf2 & 0xff) && row2[12] == 2 && row2[13] == 0
        && row2[14] == 1 && row2[15] == 0
    // A sample's people first, then its salient boxes.
    let at2 = 16 + count * 16 + firstOf2 * 20
    let thirdBoxX = Float(bitPattern: [UInt8](bytes[(at2 + 40)..<(at2 + 44)]).enumerated()
        .reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) })
    let order = thirdBoxX == all[2].subjects.salient[0].x
    let a = folder("p1-a"), b = folder("p1-b"), c = folder("p1-c")
    let aFirst = try publish(a, 0...9), aSecond = try publish(a, 20...29)
    let bFirst = try publish(b, 20...29), bSecond = try publish(b, 0...9)
    let aBytes = try Data(contentsOf: fileURL(a)), bBytes = try Data(contentsOf: fileURL(b))
    let decoded = AnalysisSubjects.decode(aBytes)
    let held = (0..<count).allSatisfy { k in
        let want = (0...9).contains(k) || (20...29).contains(k) ? synthetic(k) : Sample.empty
        return decoded?.samples[k] == want
    }
    try publish(c, 0...49)
    try Data("not a samples file".utf8).write(to: fileURL(c))
    let damagedMerged = try publish(c, 10...19)
    let afterDamage = AnalysisSubjects.decode(try Data(contentsOf: fileURL(c)))
    let fresh = afterDamage.map { d in
        (0..<count).allSatisfy { k in d.samples[k] == ((10...19).contains(k) ? synthetic(k) : .empty) }
    } ?? false
    let faces = AnalysisFaces.decode(bytes) == nil
    row("P1", roundTrip && bytes.count == expectedSize && header == Array("FJSB".utf8) + [1, 0, 20, 0]
            && rowOK && order && faces
            && !aFirst && aSecond && !bFirst && bSecond && aBytes == bBytes && held
            && coverage(a) == [[0, 9], [20, 29]] && coverage(b) == coverage(a)
            && !damagedMerged && fresh && coverage(c) == [[10, 19]],
        "round trip \(roundTrip) (\(bytes.count) bytes, want \(expectedSize)), header \(header); "
            + "sample 2's row \(row2) (first \(firstOf2), 2 people, 1 salient) \(rowOK), its third "
            + "box the salient one \(order); a faces reader refuses it \(faces); "
            + "merged \(aFirst), \(aSecond) and \(bFirst), \(bSecond) (want false, true ×2); "
            + "either order byte-equal \(aBytes == bBytes), samples held \(held), coverage "
            + "\(coverage(a)) and \(coverage(b)); a damaged file: merged \(damagedMerged) "
            + "(want false), written fresh \(fresh), coverage \(coverage(c)) (want [[10, 19]])")
} catch {
    row("P1", false, "threw \(error)")
}

// MARK: - P2 CJ-31's order and the y flip

do {
    let right = box(0.6, 0.1), left = box(0.1, 0.5), lowSameX = box(0.3, 0.6, 0.2, 0.2),
        highSameX = box(0.3, 0.1, 0.2, 0.2)
    let got = AnalysisSubjects.ordered([right, lowSameX, left, highSameX])
    let order = got == [left, highSameX, lowSameX, right]
    let flipped = AnalysisSubjects.box(CGRect(x: 0.125, y: 0.125, width: 0.25, height: 0.5), 0.5)
    let flip = flipped == Box(x: 0.125, y: 0.375, width: 0.25, height: 0.5, confidence: 0.5)
    let flip2 = AnalysisSubjects.box(CGRect(x: 0.5, y: 0, width: 0.25, height: 0.25), 0.9)
    row("P2", order && flip && flip2.y == 0.75 && flip2.width == 0.25 && flip2.confidence == 0.9,
        "ordered by centre x then y \(order); Vision's (0.125, 0.125, 0.25, 0.5) → \(flipped) "
            + "(want y 0.375), (0.5, 0, 0.25, 0.25) → \(flip2) (want y 0.75)")
}

// MARK: - P3 the stamp and the requests (VR-4 as VR-10 amends it)

if let (_, media, _, _) = made {
    let stamp = AnalysisStamp.make(
        kind: .subjects, media: media, url: fixtureURL, input: nil, fullRange: false)
    let json = stamp.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) } ?? ""
    let want = "people:\(AnalysisSubjects.peopleDevice.rawValue);salient:"
        + AnalysisSubjects.salientDevice.rawValue
    let vision = AnalysisVisionStamp(
        request: "human_rectangles+attention_saliency", quality: "upper_body", revision: 2,
        rate: AnalysisSubjects.rateName, readSize: String(AnalysisSubjects.longSide))
    let people = AnalysisSubjects.makePeople(), salient = AnalysisSubjects.makeSalient()
    let requests = people.upperBodyOnly && people.revision == VNDetectHumanRectanglesRequestRevision2
        && salient.revision == VNGenerateAttentionBasedSaliencyImageRequestRevision2
    let upper = AnalysisSubjects.parameters["upper_body_only"] as? Bool == true
    let grid = AnalysisKind.subjects.grid(of: media)
    let faces = AnalysisStamp.make(kind: .faces, media: media, url: fixtureURL, input: nil, fullRange: false)
    let ok = stamp?.version == 1 && stamp?.kind == .subjects && stamp?.device == want
        && stamp?.vision == vision && requests && upper
        && !json.contains(fixtureURL.lastPathComponent) && grid.num == AnalysisSubjects.rate
        && grid.den == 1 && AnalysisKind.subjects.files == [AnalysisSubjects.payloadName]
        && AnalysisKind.subjects.margin == 0 && !AnalysisKind.subjects.usesSoundQueue
        && faces?.parameters != stamp?.parameters
    row("P3", ok,
        "the stamp \(json); device \(stamp?.device ?? "none") (want \(want)); vision "
            + "\(String(describing: stamp?.vision)); requests upperBodyOnly \(people.upperBodyOnly), "
            + "revisions \(people.revision)/\(salient.revision); parameters upper_body_only \(upper); "
            + "no path \(!json.contains(fixtureURL.lastPathComponent)); grid \(grid.num)/\(grid.den), "
            + "\(grid.count) samples")
} else {
    row("P3", false, "the fixture \(fixturePath) did not probe")
}

// MARK: - P4 the answer: 4 decimals, the row's bytes, the cap

do {
    let grid = AnalysisGrid(samplesPerSecond: AnalysisSubjects.rate, duration: 600_000 * 3600)
    let person = Box(x: 0.43218765, y: 0.27771234, width: 0.18753968, height: 0.53340388,
                     confidence: 0.84635013)
    let region = Box(x: 0.40017456, y: 0.21771234, width: 0.25153968, height: 0.48340388,
                     confidence: 0.51)
    let late = Int(AnalysisSubjects.rate * 3594)
    var samples = [Sample](repeating: .empty, count: grid.count)
    samples[late] = Sample(pts: grid.ticks(of: late) + 20_000,
                           subjects: Subjects(people: [person], salient: [region]))
    samples[late + 1] = Sample(pts: -1, subjects: Subjects(people: [], salient: []))
    var clip: AnalysisClipTimes?
    if let (project, media, _, tracks) = made,
        let placed = apply(project, .addClip(track: tracks[0], media: media.id, at: 36_000_000)),
        let id = placed.snapshot.clips.last?.id,
        let edited = apply(placed, .trimStart(clip: id, to: 36_000_000 + 600_000)),
        let snapshot = edited.snapshot.clip(id)
    {
        clip = AnalysisClipTimes(clip: snapshot, media: media, map: edited.sourceMap(id))
    }
    func answer(_ indices: [Int], clip: AnalysisClipTimes?) throws -> Data {
        let fields = try AgentServer.subjectsAnswer(
            samples, indices: indices, grid: grid, clip: clip, from: 0, to: grid.duration)
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
        "one_person_one_salient": one, "one_person_one_salient_clip": oneClip, "rows_fit": fit,
        "rows_fit_clip": fitClip, "seconds_fit": Double(fit) / AnalysisSubjects.rate,
        "seconds_fit_clip": Double(fitClip) / AnalysisSubjects.rate, "sample": text,
    ]
    var crowded = samples
    for k in 0..<crowded.count {
        crowded[k] = Sample(pts: grid.ticks(of: k), subjects: Subjects(
            people: Array(repeating: person, count: 3), salient: Array(repeating: region, count: 2)))
    }
    var refused = ""
    var fits: Int64 = -1
    do {
        _ = try AgentServer.subjectsAnswer(
            crowded, indices: Array(0..<crowded.count), grid: grid, clip: nil, from: 0,
            to: grid.duration)
    } catch let error as AgentServer.ToolError {
        refused = error.message
        if let match = groups("to at most (\\d+)", in: refused).first { fits = Int64(match) ?? -1 }
    }
    let kept = (0..<crowded.count).filter { grid.ticks(of: $0) < fits }
    var answered = false
    var firstOut: Int64 = -1
    if fits > 0 {
        let fields = try AgentServer.subjectsAnswer(
            crowded, indices: kept, grid: grid, clip: nil, from: 0, to: fits)
        answered = (fields["count"] as? Int) == kept.count
            && (fields["rate"] as? Double) == AnalysisSubjects.rate
        firstOut = grid.ticks(of: kept.count)
        let encoded = try JSONSerialization.data(withJSONObject: fields["samples"] ?? [])
        let over = try? AgentServer.subjectsAnswer(
            crowded, indices: kept + [kept.count], grid: grid, clip: nil, from: 0, to: firstOut + 1)
        answered = answered && encoded.count <= AgentServer.analysisAnswerCap && over == nil
    }
    let shape = text.contains("\"people\":[{") && text.contains("\"salient\":[{")
        && text.contains("\"frame\":null") && text.contains("\"confidence\":0.51")
    row("P4", decimals <= 4 && !numbers.isEmpty && nulls == 1 && shape && one > 0
            && oneClip > one && fits > 0 && answered && fits == firstOut,
        "at most \(decimals) decimals over \(numbers.count) numbers (want ≤ 4), \(nulls) null "
            + "(want 1: the frameless sample's frame), people and salient rows \(shape); a row with "
            + "one person and one salient box \(one) bytes, \(oneClip) with clip; \(fit) rows "
            + "(\(Double(fit) / AnalysisSubjects.rate) s) fit, \(fitClip) with clip; the crowded hour "
            + "refused naming to \(fits) (the first row out at \(firstOut)), and to that to answers "
            + "\(answered): \(refused.prefix(160))")
} catch {
    row("P4", false, "threw \(error)")
}

// MARK: - P5 FramingAnalysis' windows

let second: Ticks = 600_000
if let (project, a, b, tracks) = made {
    // Clip 1: A's 10…20 s; clip 2: A's 40…45 s; clip 3: A's 19.5…25 s (meets 1's
    // window once widened); clip 4: B's 0…5 s at ×2 (plays 0…10 s); a text clip.
    var p: ReelProject? = project
    var ids: [UInt32] = []
    func place(_ media: MediaSnapshot, track: UInt32, at: Ticks, from: Ticks, to: Ticks) {
        p = apply(p, .addClip(track: track, media: media.id, at: at - from))
        guard let id = p?.snapshot.clips.last?.id else { return }
        ids.append(id)
        if from > 0 { p = apply(p, .trimStart(clip: id, to: at)) }
        p = apply(p, .trimEnd(clip: id, to: at + (to - from)))
    }
    place(a, track: tracks[0], at: 100 * second, from: 10 * second, to: 20 * second)
    place(a, track: tracks[1], at: 100 * second, from: 40 * second, to: 45 * second)
    place(b, track: tracks[2], at: 100 * second, from: 0, to: 5 * second)
    place(a, track: tracks[3], at: 100 * second, from: 19 * second + second / 2, to: 25 * second)
    if ids.count == 4 { p = apply(p, .setSpeed(clip: ids[2], rate: 2)) }
    p = apply(p, .addTextClip(track: tracks[4], at: 0, duration: 5 * second))
    let text = p?.snapshot.clips.last?.id
    let windows = p.map { FramingAnalysis.windows(clips: ids + (text.map { [$0] } ?? []), in: $0) }
    let played = p.flatMap { project in ids.compactMap { id in
        project.snapshot.clip(id).map { clip in
            AnalysisClipTimes(clip: clip, media: clip.source.mediaID == b.id ? b : a,
                              map: project.sourceMap(id)).window
        }
    } } ?? []
    // B's one window: clip 4's played window (×2), widened by 1 s and clamped at 0.
    let fourth = played.count == 4 ? played[2] : 0...0
    let want = [
        FramingAnalysis.MediaWindows(media: a.id, windows: [
            9 * second...26 * second, 39 * second...46 * second]),
        FramingAnalysis.MediaWindows(media: b.id, windows: [
            max(0, fourth.lowerBound - second)...min(b.duration, fourth.upperBound + second)]),
    ]
    row("P5", windows == want && FramingAnalysis.kinds == [.shots, .faces, .subjects]
            && FramingAnalysis.margin == second,
        "windows \(windows.map { $0.map { "\($0.media): \($0.windows)" } } ?? []) (want "
            + "\(want.map { "\($0.media): \($0.windows)" })); the clips' played windows \(played); "
            + "kinds \(FramingAnalysis.kinds.map(\.rawValue))")
} else {
    row("P5", false, "the fixture \(fixturePath) did not probe")
}

// MARK: - P6 the grid: every subjects sample a faces sample, and the index at a tick

do {
    let duration: Ticks = 60 * second
    let faces = AnalysisGrid(samplesPerSecond: AnalysisFaces.rate, duration: duration)
    let subjects = AnalysisGrid(samplesPerSecond: AnalysisSubjects.rate, duration: duration)
    let faceTicks = Set((0..<faces.count).map { faces.ticks(of: $0) })
    let all = (0..<subjects.count).allSatisfy { faceTicks.contains(subjects.ticks(of: $0)) }
    let k = 37
    let at = SubjectsOverlay.sampleIndex(at: subjects.ticks(of: k), grid: subjects)
    let before = SubjectsOverlay.sampleIndex(at: subjects.ticks(of: k) - 1, grid: subjects)
    let low = SubjectsOverlay.sampleIndex(at: -5 * second, grid: subjects)
    let high = SubjectsOverlay.sampleIndex(at: 99 * second, grid: subjects)
    row("P6", all && at == k && before == k - 1 && low == 0 && high == subjects.lastIndex,
        "\(subjects.count) subjects samples at \(AnalysisSubjects.rate)/s, every one a faces "
            + "sample (\(faces.count) at \(AnalysisFaces.rate)/s): \(all); the index at sample "
            + "\(k)'s tick \(at), one tick before \(before), at −5 s \(low), past the end \(high) "
            + "(last \(subjects.lastIndex))")
}

// MARK: - P7 the overlay's mapping: corners against (★), the source tick

/// (★), written out: the canvas centre plus (x, y), plus the source point's
/// offset from the source centre scaled and turned (degrees, y down).
func star(_ u: Double, _ v: Double, size: CGSize, video: VideoProps, canvas: CGSize) -> CGPoint {
    let dx = (u * size.width - size.width / 2) * video.scale
    let dy = (v * size.height - size.height / 2) * video.scale
    let r = video.rotation * .pi / 180
    return CGPoint(x: canvas.width / 2 + video.x + dx * cos(r) - dy * sin(r),
                   y: canvas.height / 2 + video.y + dx * sin(r) + dy * cos(r))
}

if let (project, a, _, tracks) = made {
    var notes: [String] = []
    var ok = true
    var p = apply(project, .addClip(track: tracks[0], media: a.id, at: 0))
    let placedID = p?.snapshot.clips.last?.id ?? 0
    var patch = VideoPatch()
    patch.scale = 0.5
    patch.x = 100
    patch.y = -50
    patch.rotation = 30
    patch.crop = CropInsets(l: 200, t: 100, r: 0, b: 50)
    p = apply(p, .setVideo(clips: [placedID], patch: patch))
    let t: Ticks = 5 * second
    let layer = p.flatMap { project in
        project.recipe(at: t).map { CanvasLayerBox.boxes(recipe: $0, snapshot: project.snapshot) }
    }?.first { $0.id == placedID }
    if let layer {
        let unit = CGRect(x: 0.25, y: 0.125, width: 0.5, height: 0.25)
        let got = SubjectsOverlay.corners(of: unit, on: layer)
        let size = CGSize(width: a.width, height: a.height)
        let canvas = CGSize(width: 1920, height: 1080)
        let want = [(0.25, 0.125), (0.75, 0.125), (0.75, 0.375), (0.25, 0.375)].map {
            star($0.0, $0.1, size: size, video: layer.video, canvas: canvas)
        }
        let off = zip(got, want).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? .infinity
        ok = ok && got.count == 4 && off < 1e-6
        notes.append("cropped, scaled 0.5, at (100, −50), turned 30°: corners off (★) by "
            + "\(off) px (want < 1e-6)")
    } else {
        ok = false
        notes.append("no layer for the placed clip")
    }
    // ×2, reversed and ramped clips: the forward source tick under the playhead.
    func tick(_ ops: (UInt32) -> [ReelOp], at offset: Ticks) -> (Ticks, Ticks, ClipSnapshot, Bool)? {
        var q = apply(project, .addClip(track: tracks[1], media: a.id, at: 0))
        guard let id = q?.snapshot.clips.last?.id else { return nil }
        q = apply(q, .trimStart(clip: id, to: 5 * second))
        for op in ops(id) { q = apply(q, op) }
        guard let q, let clip = q.snapshot.clip(id) else { return nil }
        let got = SubjectsOverlay.sourceTick(
            of: clip, in: a, at: clip.start + offset, map: q.sourceMap(id))
        let map = q.sourceMap(id)
        let forward: Ticks
        if let map, map.ramped {
            forward = Ticks(map.source(atClip: Double(offset)).rounded(.down))
        } else {
            forward = clip.source.sourceIn + Ticks(Double(offset) * clip.speed)
        }
        let want = clip.source.isReversed
            ? ReverseMirror.mirrored(forward, about: a.duration) : forward
        return (got, want, clip, map?.ramped == true)
    }
    if let (got, want, clip, _) = tick({ [.setSpeed(clip: $0, rate: 2)] }, at: 3 * second) {
        let expected = 5 * second + 6 * second
        ok = ok && got == want && got == expected
        notes.append("×2 at 3 s into a clip trimmed to 5 s: \(got) (want \(expected), the map's "
            + "\(want), speed \(clip.speed))")
    } else { ok = false; notes.append("the ×2 clip could not be made") }
    if let (got, want, clip, _) = tick({ [.setReversed(clip: $0, reversed: true)] }, at: 3 * second) {
        let expected = a.duration - clip.source.sourceIn - 3 * second
        ok = ok && got == want && got == expected && clip.source.isReversed
        notes.append("reversed at 3 s: \(got) (want \(expected), mirrored about \(a.duration); "
            + "sourceIn \(clip.source.sourceIn))")
    } else { ok = false; notes.append("the reversed clip could not be made") }
    if let (got, want, _, ramped) = tick({ [.addSpeedRamp(clip: $0, shape: .speedDip, rate: 0.5)] }, at: 4 * second) {
        ok = ok && got == want && ramped
        notes.append("a speed dip to ×0.5, at 4 s: \(got) (want the SourceMap's \(want), ramped \(ramped))")
    } else { ok = false; notes.append("the ramped clip could not be made") }
    row("P7", ok, notes.joined(separator: "; "))
} else {
    row("P7", false, "the fixture \(fixturePath) did not probe")
}

let out = try JSONSerialization.data(withJSONObject: ["rows": rows].merging(extra) { a, _ in a })
print(String(decoding: out, as: UTF8.self))
