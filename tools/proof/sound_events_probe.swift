// Road map "creator-jobs" FC3 — rows P1–P9 of `sound_events_proof.py`, driven
// through the app's own `SoundEvents`, `AnalysisSoundEvents`,
// `AnalysisStore`, `AnalysisStamp`, `MediaImporter.speechReader` and
// `AgentServer.soundEventsAnswer`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, with `-D FRAMEJOB_DEV_TOOLS`, module `FrameJob`, against
// `libframejob_core.a`, through `swift_build.py`. One run:
//
//   sound_events_probe <request.json>
//
// The request names `work` (a scratch folder this run owns), `wav` and `mp3`
// (one speech recording, the MP3 encoded from the WAV with its LAME tag),
// `movie` (a picture with that sound: P3's stamp) and `lengths` (three WAVs
// of the same speech whose lengths are 12 hops exactly and two that are not:
// P9). The answer is one JSON object on stdout, `{"rows": [{"id", "pass",
// "detail"}]}`.
import AVFoundation

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}

let arguments = CommandLine.arguments
guard arguments.count == 2,
    let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])),
    let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
    let workPath = request["work"] as? String, let wavPath = request["wav"] as? String,
    let mp3Path = request["mp3"] as? String, let moviePath = request["movie"] as? String,
    let lengthPaths = request["lengths"] as? [String]
else {
    FileHandle.standardError.write(Data("usage: sound_events_probe <request.json>\n".utf8))
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

typealias Window = SoundEvents.Window
let hop = SoundEvents.hopTicks
let groupCount = SoundEvents.Group.allCases.count

/// Window k of a synthetic media: six values, one NaN in every fifth window,
/// every seventh window all NaN.
func synthetic(_ k: Int) -> Window {
    if k % 7 == 6 { return .empty }
    var values = (0..<groupCount).map { Float(k * 7 + $0) / 997 + 0.000_123_456 }
    if k % 5 == 0 { values[2] = .nan }
    return Window(values: values)
}

/// A media snapshot of `url` (probed), in a one-media project.
func media(at url: URL) -> (ReelProject, MediaSnapshot)? {
    guard let descriptor = try? MediaImporter.probeBlocking(url: url),
        let blank = ReelProject.new(width: 320, height: 180, fps: Fps(num: 30, den: 1)),
        let project = (try? blank.applying(.addMedia(descriptor: descriptor)))?.project,
        let media = project.snapshot.media.last
    else { return nil }
    return (project, media)
}

/// A sound-events request over `ranges` of `media` at `url`, stored in `cacheDir`.
func soundRequest(_ media: MediaSnapshot, url: URL, cacheDir: URL, ranges: [ClosedRange<Int>])
    -> AnalysisRequest?
{
    guard
        let stamp = AnalysisStamp.make(
            kind: .soundEvents, media: media, url: url, input: nil, fullRange: false)
    else { return nil }
    return AnalysisRequest(
        kind: .soundEvents, cacheDir: cacheDir, media: media, url: url, stamp: stamp, input: nil,
        ranges: ranges)
}

func marker(_ dir: URL, _ id: UInt32) -> AnalysisMarker? {
    AnalysisStore.readMarker(.soundEvents, media: id, in: dir)
}
func stored(_ dir: URL, _ id: UInt32) -> [Window]? {
    AnalysisStore.readPayload(.soundEvents, media: id, file: SoundEvents.payloadName, in: dir)
        .flatMap(SoundEvents.decode)
}
func covered(_ dir: URL, _ id: UInt32) -> [[Int]] { marker(dir, id)?.coverage ?? [] }

/// The largest difference of two windows' values; infinity when one is NaN
/// and the other is not.
func difference(_ a: Window, _ b: Window) -> Float {
    var worst: Float = 0
    for (x, y) in zip(a.values, b.values) {
        if x.isNaN != y.isNaN { return .infinity }
        if !x.isNaN { worst = max(worst, abs(x - y)) }
    }
    return worst
}

// MARK: - P1 windows.bin: round trip with NaN, the merge in either order, a damaged file

do {
    let count = 40
    let all = (0..<count).map(synthetic)
    let bytes = SoundEvents.encode(all)
    let back = SoundEvents.decode(bytes)
    let roundTrip = back == all
    let header = [UInt8](bytes.prefix(16))
    let wantHeader = Array("FJSE".utf8) + [1, 0, 24, 0, 40, 0, 0, 0, 6, 0, 0, 0]
    let stamp = AnalysisStamp(
        source: AnalysisSourceID(size: 100, modified: 200, duration: 600_000 * 30),
        kind: .soundEvents, version: 1, parameters: "p", osBuild: "25F80", device: "auto",
        reader: "raw", conversion: nil)
    @discardableResult
    func publish(_ dir: URL, _ range: ClosedRange<Int>) throws -> Bool {
        var merged = false
        var results: [Int: Window] = [:]
        for k in range { results[k] = synthetic(k) }
        try AnalysisStore.publishFile(
            kind: .soundEvents, cacheDir: dir, mediaID: 1, stamp: stamp, covered: [range],
            files: [SoundEvents.payloadName]
        ) { onDisk, partial in
            merged = try SoundEvents.write(
                onDisk: onDisk, partial: partial, count: count, results: results)
            return merged
        }
        return merged
    }
    func file(_ dir: URL) -> URL {
        AnalysisStore.payloadURL(.soundEvents, media: 1, file: SoundEvents.payloadName, in: dir)
    }
    let a = folder("p1-a"), b = folder("p1-b"), c = folder("p1-c")
    let aFirst = try publish(a, 0...9), aSecond = try publish(a, 20...29)
    let bFirst = try publish(b, 20...29), bSecond = try publish(b, 0...9)
    let aBytes = try Data(contentsOf: file(a)), bBytes = try Data(contentsOf: file(b))
    let held = stored(a, 1).map { w in
        (0..<count).allSatisfy { k in
            w[k] == ((0...9).contains(k) || (20...29).contains(k) ? synthetic(k) : .empty)
        }
    } ?? false
    try publish(c, 0...39)
    try Data("not a windows file".utf8).write(to: file(c))
    let damagedMerged = try publish(c, 10...19)
    let fresh = stored(c, 1).map { w in
        (0..<count).allSatisfy { k in w[k] == ((10...19).contains(k) ? synthetic(k) : .empty) }
    } ?? false
    let nanKept = back?[0].values[2].isNaN == true && back?[6] == .empty
    row("P1", roundTrip && nanKept && bytes.count == 16 + count * 24 && header == wantHeader
            && !aFirst && aSecond && !bFirst && bSecond && aBytes == bBytes && held
            && covered(a, 1) == [[0, 9], [20, 29]] && covered(b, 1) == covered(a, 1)
            && !damagedMerged && fresh && covered(c, 1) == [[10, 19]],
        "round trip \(roundTrip), NaN kept \(nanKept), \(bytes.count) bytes (want "
            + "\(16 + count * 24)), header \(header); merged \(aFirst), \(aSecond) and "
            + "\(bFirst), \(bSecond) (want false, true ×2); either order byte-equal "
            + "\(aBytes == bBytes), windows held \(held), coverage \(covered(a, 1)) and "
            + "\(covered(b, 1)); a damaged file: merged \(damagedMerged) (want false), written "
            + "fresh \(fresh), coverage \(covered(c, 1)) (want [[10, 19]])")
} catch {
    row("P1", false, "threw \(error)")
}

// MARK: - P2 the hop grid

do {
    let grid = AnalysisGrid(hopTicks: hop, duration: 600_000 * 3600 * 200)
    var firstOff = -1
    for k in 0...1_000_000 where grid.ticks(of: k) != Ticks(k) * hop {
        firstOff = k
        break
    }
    let durations: [Ticks] = [1, hop - 1, hop, hop + 1, 900_000, 600_000 * 9, 364_290_000]
    let counts = durations.map { AnalysisGrid(hopTicks: hop, duration: $0).count }
    let want = durations.map { Int(($0 + hop - 1) / hop) }
    var kindGrid: AnalysisGrid?
    if let (_, m) = media(at: URL(fileURLWithPath: wavPath)) {
        kindGrid = AnalysisKind.soundEvents.grid(of: m)
        let mine = AnalysisGrid(hopTicks: hop, duration: m.duration)
        if kindGrid != mine { kindGrid = nil }
    }
    row("P2", firstOff < 0 && counts == want && hop == 450_000 && kindGrid != nil
            && kindGrid?.num == 600_000 && kindGrid?.den == Double(hop),
        "ticks(of: k) == k × \(hop) for k ≤ 10⁶: first off \(firstOff) (want none); counts "
            + "\(counts) for \(durations) (want ⌈d / hop⌉ \(want)); kind.grid(of:) the hop "
            + "grid \(kindGrid.map { "\($0.num)/\($0.den), \($0.count) windows" } ?? "no")")
}

// MARK: - P3 the stamp

do {
    let url = URL(fileURLWithPath: moviePath)
    if let (project, m) = media(at: url),
        let logged = (try? project.applying(.setMediaColorRaw(media: m.id, color: ["log": "slog3"])))?
            .project,
        let logMedia = logged.snapshot.media(m.id)
    {
        let cache = folder("p3")
        let sound = try ProjectDocument.analysisRequest(
            kind: .soundEvents, media: logMedia, url: url, urls: [m.id: url], cacheDir: cache,
            need: [0...0])
        let faces = try ProjectDocument.analysisRequest(
            kind: .faces, media: logMedia, url: url, urls: [m.id: url], cacheDir: cache,
            need: [0...0])
        let plain = AnalysisStamp.make(
            kind: .soundEvents, media: m, url: url, input: nil, fullRange: false)
        let kind = AnalysisKind.soundEvents
        let keys = Set(kind.parameters.keys)
        let wantKeys: Set = [
            "classifier", "analyzer", "window_ticks", "hop_ticks", "overlap", "sample_rate",
            "decode", "mp3_trim", "file_version", "record_bytes", "value",
        ]
        let stamp = sound?.stamp
        let ok = kind.version == SoundEvents.tableVersion && kind.usesSoundQueue
            && kind.device == "auto" && kind.vision == nil && kind.margin == 0
            && kind.files == ["windows.bin"] && keys == wantKeys && logMedia.color?.log != nil
            && sound?.input == nil && stamp?.reader == "raw" && stamp?.version == kind.version
            && stamp?.device == "auto" && stamp?.vision == nil && plain.map { stamp?.matches($0) == true } == true
            && faces?.stamp.reader == "converted"
        row("P3", ok,
            "version \(kind.version) (the table's \(SoundEvents.tableVersion)), sound queue "
                + "\(kind.usesSoundQueue), device \(kind.device), vision "
                + "\(String(describing: kind.vision)), margin \(kind.margin), files \(kind.files); "
                + "parameter keys \(keys.sorted()) (want \(wantKeys.sorted())); with color.log "
                + "\(String(describing: logMedia.color?.log)): input "
                + "\(sound?.input == nil ? "nil" : "set"), reader \(stamp?.reader ?? "none") "
                + "(faces' \(faces?.stamp.reader ?? "none")), the stamp equal to the unlogged "
                + "media's \(plain.map { stamp?.matches($0) == true } ?? false)")
    } else {
        row("P3", false, "the movie \(moviePath) did not probe or take a Camera Log")
    }
} catch {
    row("P3", false, "threw \(error)")
}

// MARK: - P4 the MP3's window starts past its encoder delay

/// `count` mono 16 kHz floats of `url`'s first audio track read through
/// `readWindow(k0...k0)` and `speechReader(window:)`, and the reader's start.
func windowed(_ url: URL, k0: Int, count: Int) -> (floats: [Float], start: CMTime, trim: CMTime)? {
    var assets: [UInt32: AVURLAsset] = [:]
    guard let track = CompositionBuilder.assetTrack(at: url, key: 1, mediaType: .audio, assets: &assets),
        let asset = assets[1],
        let (reader, output) = MediaImporter.speechReader(
            asset: asset, track: track, window: AnalysisSoundEvents.readWindow(k0...(k0 + 3))),
        reader.canAdd(output)
    else { return nil }
    reader.add(output)
    guard reader.startReading() else { return nil }
    var floats: [Float] = []
    while floats.count < count, let sample = output.copyNextSampleBuffer() {
        floats += MediaImporter.monoFloats(of: sample) ?? []
    }
    let start = reader.timeRange.start
    reader.cancelReading()
    return (Array(floats.prefix(count)), start, MP3Gapless.leadingTrim(of: url, track: track))
}

do {
    let k0 = 4
    let n = 32_000
    if let mp3 = windowed(URL(fileURLWithPath: mp3Path), k0: k0, count: n),
        let wav = windowed(URL(fileURLWithPath: wavPath), k0: k0, count: n),
        mp3.floats.count == n, wav.floats.count == n
    {
        let want = CMTimeAdd(mp3.trim, CMTime(value: Int64(k0) * hop, timescale: 600_000))
        let startOK = CMTimeCompare(mp3.start, want) == 0
        var best = (lag: 0, score: -Double.infinity)
        for lag in -400...400 {
            var dot = 0.0, aa = 0.0, bb = 0.0
            for i in 500..<(n - 500) {
                let a = Double(wav.floats[i]), b = Double(mp3.floats[i + lag])
                dot += a * b
                aa += a * a
                bb += b * b
            }
            let score = dot / max(1e-12, (aa * bb).squareRoot())
            if score > best.score { best = (lag, score) }
        }
        row("P4", mp3.trim > .zero && startOK && abs(best.lag) <= 16,
            "the MP3's leadingTrim \(mp3.trim.seconds) s (want > 0); the reader starts at "
                + "\(mp3.start.seconds) s (want trim + \(k0) hops = \(want.seconds) s) \(startOK); "
                + "its first 2 s against the WAV's: lag \(best.lag) samples (want 0 ± 16), "
                + "correlation \(String(format: "%.4f", best.score))")
    } else {
        row("P4", false, "the MP3 \(mp3Path) or the WAV \(wavPath) gave no 2 s window")
    }
}

// MARK: - P5 placement on a ×2 and a ramped clip, against MediaPeaks.sourceTick

do {
    let second: Ticks = 600_000
    func make(rate: Double?, ramp: Bool, reversed: Bool) -> (ReelProject, ClipSnapshot, MediaSnapshot)? {
        guard var project = ReelProject.new(width: 320, height: 180, fps: Fps(num: 30, den: 1))
        else { return nil }
        func step(_ op: ReelOp) -> Bool {
            switch try? project.applying(op) {
            case .applied(let next)?: project = next; return true
            case .identity?: return true
            default: return false
            }
        }
        let descriptor = MediaDescriptor(
            path: "/fixtures/sound-events.mov", kind: .video, duration: 40 * second, width: 320,
            height: 180, fps: Fps(num: 30, den: 1), hasVideo: true, hasAudio: true)
        guard step(.addMedia(descriptor: descriptor)),
            let mediaID = project.snapshot.media.first?.id,
            let track = project.snapshot.tracks.first?.id,
            step(.addClip(track: track, media: mediaID, at: second)),
            let clip = project.snapshot.clips.last?.id,
            step(.trimStart(clip: clip, to: second + 2 * second)),
            step(.trimEnd(clip: clip, to: second + 14 * second))
        else { return nil }
        if ramp {
            guard step(.addAction(clip: clip, at: 0, duration: 4 * second)),
                let action = project.snapshot.clips.last?.actions.first?.id,
                step(.setAction(clip: clip, action: action, curve: .linear)),
                step(.setActionEndRaw(clip: clip, action: action, patch: ["speed": 2]))
            else { return nil }
        }
        if let rate, !step(.setSpeed(clip: clip, rate: rate)) { return nil }
        if reversed, !step(.setReversed(clip: clip, reversed: true)) { return nil }
        guard let snapshot = project.snapshot.clips.first(where: { $0.id == clip }),
            let m = project.snapshot.media(for: snapshot)
        else { return nil }
        return (project, snapshot, m)
    }
    var details: [String] = []
    var ok = true
    for (name, rate, ramp) in [("×2", 2.0, false), ("ramp", nil, true)] as [(String, Double?, Bool)] {
        guard let (project, clip, m) = make(rate: rate, ramp: ramp, reversed: false) else {
            ok = false
            details.append("\(name): not made")
            continue
        }
        let grid = AnalysisKind.soundEvents.grid(of: m)
        let windows = (0..<grid.count).map(synthetic)
        let times = AnalysisClipTimes(clip: clip, media: m, map: project.sourceMap(clip.id))
        let placed = SoundEvents.events(
            in: windows, covered: [0...grid.lastIndex], grid: grid, for: times)
        let segments = project.plan?.audioTracks.flatMap(\.segments).filter { $0.clip == clip.id } ?? []
        var worst: Int64 = 0
        var unplaced = 0
        for p in placed {
            guard let segment = segments.first(where: {
                p.timeline >= $0.start && p.timeline <= $0.start + $0.duration
            }) else {
                unplaced += 1
                continue
            }
            worst = max(worst, abs(MediaPeaks.sourceTick(segment, at: p.timeline) - p.source))
        }
        let inWindow = placed.allSatisfy { times.window.contains($0.source) && $0.source < times.window.upperBound }
        let fine = !placed.isEmpty && unplaced == 0 && worst <= 600 && inWindow
            && placed.allSatisfy { $0.timeline == clip.start + $0.clipTime && $0.window == windows[$0.index] }
        ok = ok && fine
        details.append("\(name): \(placed.count) windows placed, worst |sourceTick − source| "
            + "\(worst) ticks (want ≤ 600), \(unplaced) outside every segment, all in the "
            + "played window \(inWindow)")
    }
    if let (project, clip, m) = make(rate: nil, ramp: false, reversed: true) {
        let grid = AnalysisKind.soundEvents.grid(of: m)
        let times = AnalysisClipTimes(clip: clip, media: m, map: project.sourceMap(clip.id))
        let placed = SoundEvents.events(
            in: (0..<grid.count).map(synthetic), covered: [0...grid.lastIndex], grid: grid,
            for: times)
        ok = ok && placed.isEmpty
        details.append("reversed: \(placed.count) placed (want 0)")
    } else {
        ok = false
        details.append("reversed: not made")
    }
    row("P5", ok, details.joined(separator: "; "))
}

// MARK: - P6, P7, P9: the job on real sound

let wavURL = URL(fileURLWithPath: wavPath)
var wholeRun: [Window]?
if let (_, m) = media(at: wavURL) {
    let grid = AnalysisKind.soundEvents.grid(of: m)
    // A whole run, the reference.
    let whole = folder("whole")
    var wholeError = ""
    do {
        if let request = soundRequest(m, url: wavURL, cacheDir: whole, ranges: [0...grid.lastIndex]) {
            _ = try AnalysisSoundEvents.run(request, cancelled: { false }, progress: { _ in })
            wholeRun = stored(whole, m.id)
        }
    } catch {
        wholeError = "\(error)"
    }

    // P6: published every buffer, cancelled once four windows are covered.
    do {
        let cut = folder("p6")
        guard let request = soundRequest(m, url: wavURL, cacheDir: cut, ranges: [0...grid.lastIndex]),
            let reference = wholeRun
        else { throw AnalysisSoundEvents.SoundError.reader("no whole run: \(wholeError)") }
        let finished = try AnalysisSoundEvents.run(
            request,
            cancelled: {
                AnalysisStore.coveredCount(0...grid.lastIndex, covered: marker(cut, m.id)?.ranges ?? []) >= 4
            }, progress: { _ in }, publishInterval: 0)
        let ranges = marker(cut, m.id)?.ranges ?? []
        let windows = stored(cut, m.id) ?? []
        let last = ranges.last?.upperBound ?? -1
        let answered = ranges.allSatisfy { r in r.allSatisfy { k in
            k < windows.count && windows[k].values.contains { !$0.isNaN }
        } }
        var worst: Float = 0
        for r in ranges { for k in r where k < windows.count { worst = max(worst, difference(windows[k], reference[k])) } }
        row("P6", !finished && ranges.count == 1 && ranges.first?.lowerBound == 0 && last >= 3
                && last < grid.lastIndex && answered && worst <= 0.01,
            "finished \(finished) (want false); coverage \(ranges) of 0…\(grid.lastIndex) "
                + "(want one range from 0 past window 3, short of the end); every covered window "
                + "answered \(answered); largest difference from a whole run \(worst) (want ≤ 0.01)")
    } catch {
        row("P6", false, "threw \(error)")
    }

    // P7: two halves against the whole run.
    do {
        let halves = folder("p7")
        let middle = grid.lastIndex / 2
        guard let reference = wholeRun,
            let first = soundRequest(m, url: wavURL, cacheDir: halves, ranges: [0...middle]),
            let second = soundRequest(m, url: wavURL, cacheDir: halves, ranges: [(middle + 1)...grid.lastIndex])
        else { throw AnalysisSoundEvents.SoundError.reader("no whole run: \(wholeError)") }
        _ = try AnalysisSoundEvents.run(first, cancelled: { false }, progress: { _ in })
        let afterFirst = covered(halves, m.id)
        _ = try AnalysisSoundEvents.run(second, cancelled: { false }, progress: { _ in })
        let windows = stored(halves, m.id) ?? []
        let wholeCover = covered(whole, m.id)
        var worst: Float = 0
        var worstAt = -1
        for k in 0..<min(windows.count, reference.count) {
            let d = difference(windows[k], reference[k])
            if d > worst { worst = d; worstAt = k }
        }
        row("P7", worst <= 0.01 && windows.count == reference.count
                && covered(halves, m.id) == wholeCover && afterFirst == [[0, middle]],
            "halves 0…\(middle) then \(middle + 1)…\(grid.lastIndex): coverage \(afterFirst) "
                + "then \(covered(halves, m.id)) (the whole run's \(wholeCover)); largest "
                + "difference \(worst) at window \(worstAt) (want ≤ 0.01; NaN against a value is ∞)")
    } catch {
        row("P7", false, "threw \(error)")
    }
} else {
    row("P6", false, "the WAV \(wavPath) did not probe")
    row("P7", false, "the WAV \(wavPath) did not probe")
}

// MARK: - P8 the answer: 4 decimals, null for NaN, the cap

do {
    let grid = AnalysisGrid(hopTicks: hop, duration: 600_000 * 3600 * 2)
    var windows = (0..<grid.count).map { _ in
        Window(values: [0.123_456_78, 0.000_012_3, 0.987_654_3, 0.5, 0.333_333_3, 0.000_049])
    }
    windows[1].values[3] = .nan
    let small = try AgentServer.soundEventsAnswer(
        windows, indices: [0, 1], grid: grid, clip: nil, from: 0, to: grid.duration)
    let text = String(decoding: try JSONSerialization.data(withJSONObject: small["windows"] ?? []), as: UTF8.self)
    let regex = try NSRegularExpression(pattern: "-?\\d+\\.(\\d+)")
    let numbers = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
        Range($0.range(at: 1), in: text).map { String(text[$0]) }
    }
    let decimals = numbers.map(\.count).max() ?? 0
    let nulls = text.components(separatedBy: "null").count - 1
    let groups = (small["groups"] as? [[String: Any]])?.map { $0["name"] as? String ?? "" } ?? []
    var refused = ""
    var fits: Int64 = -1
    do {
        _ = try AgentServer.soundEventsAnswer(
            windows, indices: Array(0..<grid.count), grid: grid, clip: nil, from: 0,
            to: grid.duration)
    } catch let error as AgentServer.ToolError {
        refused = error.message
        let found = try NSRegularExpression(pattern: "to at most (\\d+)").firstMatch(
            in: refused, range: NSRange(refused.startIndex..., in: refused))
        if let found, let r = Range(found.range(at: 1), in: refused) { fits = Int64(refused[r]) ?? -1 }
    }
    let kept = (0..<grid.count).filter { grid.ticks(of: $0) < fits }
    var answered = false
    if fits > 0 {
        let fields = try AgentServer.soundEventsAnswer(
            windows, indices: kept, grid: grid, clip: nil, from: 0, to: fits)
        let over = try? AgentServer.soundEventsAnswer(
            windows, indices: kept + [kept.count], grid: grid, clip: nil, from: 0, to: fits + hop)
        answered = (fields["count"] as? Int) == kept.count && over == nil
            && grid.ticks(of: kept.count) == fits
    }
    row("P8", decimals <= 4 && !numbers.isEmpty && nulls == 1 && answered
            && groups == SoundEvents.Group.allCases.map(\.rawValue)
            && (small["window"] as? Ticks) == 900_000 && (small["hop"] as? Ticks) == hop,
        "at most \(decimals) decimals over \(numbers.count) numbers (want ≤ 4), \(nulls) null "
            + "(want 1); groups \(groups); two hours refused naming to \(fits), and to that to "
            + "answers \(answered) (\(kept.count) rows): \(refused.prefix(150)); a row: "
            + "\(text.prefix(140))")
} catch {
    row("P8", false, "threw \(error)")
}

// MARK: - P9 the NaN tail

do {
    var details: [String] = []
    var ok = true
    // A decode cut short inside the media: no tail.
    let grid = AnalysisGrid(hopTicks: hop, duration: 600_000 * 9)
    let short = AnalysisSoundEvents.coverage(
        range: 0...grid.lastIndex, from: 0, answered: Set(0...5), decodedEnd: nil, grid: grid)
    let shortOK = short.covered == [0...5] && short.tail.isEmpty
    ok = ok && shortOK
    details.append("cut short: covered \(short.covered) (want [0...5]), tail \(short.tail)")
    for path in lengthPaths {
        let url = URL(fileURLWithPath: path)
        guard let (_, m) = media(at: url) else {
            ok = false
            details.append("\(url.lastPathComponent): did not probe")
            continue
        }
        let g = AnalysisKind.soundEvents.grid(of: m)
        let dir = folder("p9-" + url.deletingPathExtension().lastPathComponent)
        guard let request = soundRequest(m, url: url, cacheDir: dir, ranges: [0...g.lastIndex]) else {
            ok = false
            details.append("\(url.lastPathComponent): no stamp")
            continue
        }
        _ = try AnalysisSoundEvents.run(request, cancelled: { false }, progress: { _ in })
        let windows = stored(dir, m.id) ?? []
        let cover = covered(dir, m.id)
        let nan = (0..<windows.count).filter { windows[$0] == .empty }
        // The decoded sound's end, read as the job reads it (16 kHz, whole).
        var decodedSamples = 0
        var assets: [UInt32: AVURLAsset] = [:]
        if let track = CompositionBuilder.assetTrack(at: url, key: 1, mediaType: .audio, assets: &assets),
            let asset = assets[1],
            let (reader, output) = MediaImporter.speechReader(
                asset: asset, track: track, window: AnalysisSoundEvents.readWindow(0...g.lastIndex)),
            reader.canAdd(output)
        {
            reader.add(output)
            if reader.startReading() {
                while let sample = output.copyNextSampleBuffer() {
                    decodedSamples += MediaImporter.monoFloats(of: sample)?.count ?? 0
                }
            }
            reader.cancelReading()
        }
        let decodedEnd = Ticks((Double(decodedSamples) * 37.5).rounded())
        let overhang = (0..<g.count).filter { g.ticks(of: $0) + SoundEvents.windowTicks > decodedEnd }
        let hit: Bool
        if case .hit? = marker(dir, m.id).map({ _ in
            AnalysisStore.lookup(.soundEvents, media: m.id, stamp: request.stamp, need: 0...g.lastIndex, in: dir)
        }) { hit = true } else { hit = false }
        let fine = cover == [[0, g.lastIndex]] && hit && !nan.isEmpty && nan == overhang
            && nan.last == g.lastIndex && decodedSamples > 0
        ok = ok && fine
        details.append("\(url.lastPathComponent) (\(Double(m.duration) / 600_000) s, \(g.count) "
            + "windows, \(decodedSamples) samples decoded): coverage \(cover), NaN-covered \(nan) "
            + "(want those overhanging the decoded sound \(overhang)), a whole lookup a hit \(hit)")
    }
    row("P9", ok, details.joined(separator: "; "))
} catch {
    row("P9", false, "threw \(error)")
}

let out = try JSONSerialization.data(withJSONObject: ["rows": rows])
print(String(decoding: out, as: UTF8.self))
