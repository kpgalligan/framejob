// tools/proof/audio_ap5_probe.swift — the in-process instrument behind
// `audio_ap5_proof.py --probe` (road map "audio" AP5, spec §11 AU-50…AU-57).
// Compiled with every file in `app/Sources` but `main.swift` through
// `swift_build.py`'s line, copied in as `main.swift`, with `Blank.mp4` beside
// the binary (the builder's placeholder track for an audio-only plan).
//
//     audio_ap5_probe <work-dir> <Rode-usb-mic.m4a>
//
// Fixtures are 48 kHz stereo float WAVs of seeded noise written by
// `AVAudioFile`; a synthetic "render" is seeded noise written by
// `RampCAFWriter` under the name `IsolationCache` gives the clip's window.
// Projects are ops on an untitled `ProjectDocument`, published under a fresh
// recipe key with `AudioDSPSource` and a `ReverseResolution` whose `isolated`
// is <work-dir>/cache/isolated. One line per row, `ok <ID> — <detail>` or
// `FAIL <ID> — <detail>`; no app is launched.
//
//  P1  isolation 1 with no render: no tap on any track, the mix read
//      byte-identical to isolation 0.
//  P2  a synthetic stereo render: isolation 1 reads it sample for sample at
//      the placement (a clip at 3.5 s from source 2.5 s), ≤ 1e-7 alone and
//      ≤ 1e-4 with noise reduction on the track (the 512-sample lead; the
//      reducer at 0 is an FFT round trip).
//  P2b `wetOffset` and a built span off the 48 kHz grid: at 20,020 /
//      sourceIn 40,040 ticks is 1,602 − first, the reverse −1,602 − first.
//  P3  amount 0.5 and 0.25 against dry + a·(render − dry), ≤ 1e-6.
//  P4  no request for a time-scaled, a ramped, a freeze or a pending-reverse
//      segment; a plain one gets one.
//  P5  `IsolationRenderer` over 6 s of the Rode recording from 10 s: the
//      render's lag against the dry by cross-correlation is 0.
//  P6  the window [10, 15 s) against the whole file's render over 10–11 s:
//      residual ≤ −40 dB.
//  P7  `name` differs by window and by reversal; a request ignores Amount.
//  P8  `Exporter.withRampAudio` runs its build only once the isolation file
//      exists.
//  P9  a forced failure: the owner's `settled` runs exactly once, on the main
//      queue; `failure(for:)` and `IsolationCache.status(of:)` carry the message.
import AVFoundation
import Accelerate
import AppKit

_ = NSApplication.shared
NSApplication.shared.setActivationPolicy(.prohibited)

let SEC: Ticks = 600_000
let RATE = 48_000

func row(_ id: String, _ ok: Bool, _ detail: String) {
    print("\(ok ? "ok" : "FAIL") \(id) — \(detail)")
    fflush(stdout)
}

guard CommandLine.arguments.count == 3 else {
    row("P1", false, "usage: audio_ap5_probe <work-dir> <Rode-usb-mic.m4a>")
    exit(0)
}
let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let rode = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
let isolatedDir = IsolationCache.directory(
    in: work.appendingPathComponent("cache", isDirectory: true))
try? FileManager.default.createDirectory(at: isolatedDir, withIntermediateDirectories: true)

// =========================================================================
// Fixtures

struct Noise {
    var state: UInt32
    mutating func next() -> Float {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Float(Int32(bitPattern: state)) / Float(Int32.max)
    }
}

func writeNoise(_ url: URL, seed: UInt32, seconds: Double, amplitude: Float) -> String? {
    try? FileManager.default.removeItem(at: url)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(RATE), channels: 2),
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(RATE) * seconds))
    else { return "no buffer for \(url.lastPathComponent)" }
    buffer.frameLength = buffer.frameCapacity
    var noise = Noise(state: seed)
    for i in 0..<Int(buffer.frameLength) {
        buffer.floatChannelData![0][i] = amplitude * noise.next()
        buffer.floatChannelData![1][i] = amplitude * noise.next()
    }
    do {
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: RATE,
                AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    } catch {
        return "\(url.lastPathComponent) would not write: \(error)"
    }
    return nil
}

let dryA = work.appendingPathComponent("dry-a.wav")
let dryB = work.appendingPathComponent("dry-b.wav")
let written = [
    writeNoise(dryA, seed: 1, seconds: 12, amplitude: 0.4),
    writeNoise(dryB, seed: 2, seconds: 12, amplitude: 0.3),
].compactMap { $0 }
if !written.isEmpty {
    row("P1", false, "fixtures: " + written.joined(separator: "; "))
    exit(0)
}

/// `ops` through the document, each first tried on a scratch chain so a bad
/// op is a printed FAIL and an exit, never `ProjectDocument`'s modal alert.
func edit(_ document: ProjectDocument, _ name: String, _ ops: [ReelOp]) {
    var trial = document.project
    for op in ops {
        do {
            switch try trial.applying(op) {
            case .applied(let next): trial = next
            case .identity: break
            case .refused(let refusal):
                row("P1", false, "\(op.name) was refused: \(refusal.reason)")
                exit(0)
            }
        } catch {
            row("P1", false, "\(op.name) is invalid: \(error)")
            exit(0)
        }
    }
    document.performGroupedEdit(name, ops)
}

struct Fixture {
    let document: ProjectDocument
    let key: Int
    let clip: UInt32
    var project: ReelProject { document.project }
    var segment: PlanSegment? {
        project.plan?.audioTracks.flatMap(\.segments).first { $0.clip == clip }
    }
    var dsp: AudioDSPParameters { AudioDSPParameters(snapshot: project.snapshot) }
}

func addMedia(_ document: ProjectDocument, _ url: URL, seconds: Double) -> UInt32? {
    edit(
        document, "Media",
        [.addMedia(descriptor: MediaDescriptor(
            path: url.path, kind: .audio, duration: Ticks(seconds * Double(SEC)),
            hasVideo: false, hasAudio: true))])
    return document.project.snapshot.media.first { $0.path == url.path }?.id
}

func place(_ document: ProjectDocument, _ url: URL, seconds: Double, at: Ticks) -> UInt32? {
    guard let media = addMedia(document, url, seconds: seconds) else { return nil }
    let track = document.project.snapshot.tracks[0].id
    edit(document, "Clip", [.addClip(track: track, media: media, at: at)])
    return document.project.snapshot.clips.first { $0.track == track && $0.start == at }?.id
}

/// One clip of `dryA` added at 1 s and trimmed to start at 3.5 s from source
/// 2.5 s, with `isolation`; `noiseClip` adds `dryB` at 14 s with noise
/// reduction 0.5 on the same track.
func fixture(isolation: Double, noiseClip: Bool = false, pending: Bool = false) -> Fixture? {
    let document = ProjectDocument()
    guard let clip = place(document, dryA, seconds: 12, at: SEC) else { return nil }
    edit(document, "Trim", [.trimStart(clip: clip, to: 3 * SEC + SEC / 2)])
    if isolation > 0 {
        edit(
            document, "Iso", [.setAudio(clips: [clip], patch: AudioPatch(isolation: isolation))])
    }
    if noiseClip, let other = place(document, dryB, seconds: 12, at: 14 * SEC) {
        edit(
            document, "NR", [.setAudio(clips: [other], patch: AudioPatch(noiseReduction: 0.5))])
    }
    let key = RecipeSource.shared.register()
    RecipeSource.shared.set(document.project, for: key)
    AudioDSPSource.shared.publish(AudioDSPParameters(snapshot: document.project.snapshot), for: key)
    ReverseSource.shared.publish(
        ReverseResolution(ready: [:], pending: pending ? [clip] : [], isolated: isolatedDir),
        project: document.project, for: key)
    return Fixture(document: document, key: key, clip: clip)
}

func build(_ f: Fixture) -> BuiltComposition? {
    guard let plan = f.project.plan else { return nil }
    return try? CompositionBuilder.build(
        plan: plan, planJSON: f.project.planJSON, urls: f.document.mediaURLs(),
        recipeKey: f.key, metering: false)
}

typealias Stereo = (left: [Float], right: [Float])

/// The export's float read of the whole timeline, placed by presentation time.
func exportRead(_ built: BuiltComposition) -> Stereo? {
    guard let reader = try? AVAssetReader(asset: built.composition) else { return nil }
    let output = ExportWriter.audioReadOutput(built, gained: true)
    guard reader.canAdd(output) else { return nil }
    reader.add(output)
    guard reader.startReading() else { return nil }
    let total = ExportAudioEnd.frames(ofTicks: CompositionBuilder.ticks(built.composition.duration))
    var left = [Float](repeating: 0, count: total)
    var right = [Float](repeating: 0, count: total)
    while let sample = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
        let count = CMBlockBufferGetDataLength(block) / 8
        var raw = [Float](repeating: 0, count: 2 * count)
        _ = raw.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: 8 * count, destination: $0.baseAddress!)
        }
        let offset = Int(CMTimeConvertScale(
            CMSampleBufferGetPresentationTimeStamp(sample), timescale: 48_000,
            method: .roundHalfAwayFromZero).value)
        for i in 0..<count where offset + i >= 0 && offset + i < total {
            left[offset + i] = raw[2 * i]
            right[offset + i] = raw[2 * i + 1]
        }
    }
    return reader.status == .completed ? (left, right) : nil
}

/// A synthetic render of `f`'s window written where `IsolationCache` names
/// it: seeded noise, stereo, the window's length. Answers its channels.
func writeRender(_ f: Fixture) -> (render: [[Float]], window: IsolationWindow, url: URL)? {
    guard let s = f.segment, let file = f.document.mediaURLs()[s.media] else { return nil }
    let window = IsolationCache.window(of: s)
    guard let name = IsolationCache.name(
        media: s.media, mediaFile: file, reversed: false, window: window)
    else { return nil }
    let url = isolatedDir.appendingPathComponent(name)
    let frames = Int(window.endFrame - window.firstFrame)
    var noise = Noise(state: 7)
    var render: [[Float]] = [[], []]
    var interleaved = [Float](repeating: 0, count: 2 * frames)
    for i in 0..<frames {
        for c in 0..<2 {
            let v = 0.5 * noise.next()
            render[c].append(v)
            interleaved[2 * i + c] = v
        }
    }
    guard let writer = try? RampCAFWriter(url: url, channels: 2) else { return nil }
    do {
        try writer.write(interleaved, frames: frames)
        try writer.close()
    } catch { return nil }
    return (render, window, url)
}

/// The span `[first, end)` in composition frames, and the wet index offset,
/// computed here from the decision's arithmetic rather than read from the app.
func expectedSpan(_ s: PlanSegment, _ window: IsolationWindow) -> (Int, Int, Int) {
    func r(_ t: Ticks) -> Int {
        let a = 2 * t + 12
        return Int(a >= 0 ? a / 25 : -((-a + 24) / 25))
    }
    return (r(s.start), r(s.start + s.duration), r(s.sourceIn - s.start) - Int(window.firstFrame))
}

// =========================================================================
// P1 — pending: no tap, the dry read byte for byte

do {
    guard let off = fixture(isolation: 0), let on = fixture(isolation: 1),
        let builtOff = build(off), let builtOn = build(on),
        let readOff = exportRead(builtOff), let readOn = exportRead(builtOn)
    else {
        row("P1", false, "a fixture did not build or read")
        exit(0)
    }
    let taps = builtOn.audioMix.inputParameters.filter { $0.audioTapProcessor != nil }.count
    let same = readOff.left == readOn.left && readOff.right == readOn.right
    row("P1", taps == 0 && same && !readOn.left.isEmpty,
        "isolation 1 with no render: \(taps) taps over "
            + "\(builtOn.audioMix.inputParameters.count) tracks; read byte-identical to "
            + "isolation 0: \(same) (\(readOn.left.count) frames)")
}

// =========================================================================
// P2 — the render at the placement

func p2(noiseClip: Bool, bound: Float) -> (Bool, String) {
    guard let f = fixture(isolation: 1, noiseClip: noiseClip), let s = f.segment,
        let rendered = writeRender(f), let built = build(f), let read = exportRead(built)
    else { return (false, "the fixture did not build, write or read") }
    let (render, window) = (rendered.render, rendered.window)
    let (start, end, offset) = expectedSpan(s, window)
    var worst: Float = 0
    var counted = 0
    for f in start..<min(end, read.left.count) {
        let w = f + offset
        guard w >= 0, w < render[0].count else { continue }
        worst = max(worst, abs(read.left[f] - render[0][w]), abs(read.right[f] - render[1][w]))
        counted += 1
    }
    let ok = worst <= bound && counted >= end - start - 1 && counted > 0
    return (ok, "\(noiseClip ? "with" : "without") noise reduction on the track: clip at "
        + "\(Double(s.start) / Double(SEC)) s from source \(Double(s.sourceIn) / Double(SEC)) s, "
        + "\(counted) frames, worst |out − render| \(worst) (bound \(bound))")
}

do {
    let (alone, aloneDetail) = p2(noiseClip: false, bound: 1e-7)
    let (led, ledDetail) = p2(noiseClip: true, bound: 1e-4)
    row("P2", alone && led, aloneDetail + "; " + ledDetail)
}

// =========================================================================
// P2b — off the 48 kHz grid

do {
    let window = IsolationWindow(firstFrame: 1_000, endFrame: 2_000)
    let forward = IsolationCache.wetOffset(at: 20_020, sourceIn: 40_040, window: window)
    let backward = IsolationCache.wetOffset(at: 40_040, sourceIn: 20_020, window: window)
    let json = """
        {"clip": 5, "media": 1, "source_in": 40040, "source_duration": 600600,
         "start": 20020, "duration": 600600}
        """
    var spanOffset: Int64? = nil
    var spanStart: Int64? = nil
    var spanWindow = IsolationWindow(firstFrame: 0, endFrame: 0)
    // The span reads `dsp` for the amount, so the segment names the
    // fixture's isolated clip.
    if let one = fixture(isolation: 1), let rendered = writeRender(one),
        let audio = IsolatedAudio(contentsOf: rendered.url),
        let segment = ReelJSON.decode(
            PlanSegment.self,
            from: json.replacingOccurrences(of: "\"clip\": 5", with: "\"clip\": \(one.clip)"))
    {
        spanWindow = IsolationCache.window(of: segment)
        let track = AudioIsolationTrack(
            segments: [segment], shift: .none, dsp: one.dsp,
            renders: [IsolationSegmentKey(segment): audio])
        spanOffset = track.spans.first?.wetOffset
        spanStart = track.spans.first?.startFrame
    }
    let ok = forward == 1_602 - window.firstFrame && backward == -1_602 - window.firstFrame
        && spanOffset == 1_602 - spanWindow.firstFrame && spanStart == 1_602
    row("P2b", ok,
        "wetOffset(at 20,020, in 40,040) = \(forward) (want \(1_602 - window.firstFrame)); "
            + "(at 40,040, in 20,020) = \(backward) (want \(-1_602 - window.firstFrame)); "
            + "a built span at 20,020 from 40,040: start \(spanStart.map(String.init) ?? "none") "
            + "(want 1602), offset \(spanOffset.map(String.init) ?? "none") (want "
            + "\(1_602 - spanWindow.firstFrame))")
}

// =========================================================================
// P3 — Amount is a crossfade

do {
    guard let dryFixture = fixture(isolation: 0), let s = dryFixture.segment,
        let built = build(dryFixture), let dry = exportRead(built)
    else {
        row("P3", false, "the dry fixture did not build or read")
        exit(0)
    }
    var parts: [String] = []
    var ok = true
    for amount in [0.5, 0.25] {
        guard let f = fixture(isolation: amount), let rendered = writeRender(f),
            let b = build(f), let read = exportRead(b)
        else {
            ok = false
            parts.append("amount \(amount): did not build")
            continue
        }
        let (render, window) = (rendered.render, rendered.window)
        let (start, end, offset) = expectedSpan(s, window)
        let a = Float(amount)
        var worst: Float = 0
        for f in start..<min(end, read.left.count) {
            let w = f + offset
            guard w >= 0, w < render[0].count else { continue }
            let l = dry.left[f] + a * (render[0][w] - dry.left[f])
            let r = dry.right[f] + a * (render[1][w] - dry.right[f])
            worst = max(worst, abs(read.left[f] - l), abs(read.right[f] - r))
        }
        ok = ok && worst <= 1e-6
        parts.append("amount \(amount): worst \(worst) over \(end - start) frames")
    }
    row("P3", ok, parts.joined(separator: "; ") + " (bound 1e-6)")
}

// =========================================================================
// P4 — which segments are isolated

do {
    let fixed = fixture(isolation: 1)
    guard let f = fixed, let media = f.segment?.media else {
        row("P4", false, "the fixture did not build")
        exit(0)
    }
    func segment(_ extra: String, duration: Ticks = 600_000, sourceDuration: Ticks = 600_000)
        -> PlanSegment?
    {
        ReelJSON.decode(
            PlanSegment.self,
            from: "{\"clip\": \(f.clip), \"media\": \(media), \"source_in\": 0, "
                + "\"source_duration\": \(sourceDuration), \"start\": 0, "
                + "\"duration\": \(duration)\(extra)}")
    }
    let reverse = ReverseResolution(ready: [:], pending: [], isolated: isolatedDir)
    let pendingReverse = ReverseResolution(ready: [:], pending: [f.clip], isolated: isolatedDir)
    let cases: [(String, PlanSegment?, ReverseResolution, Bool)] = [
        ("plain", segment(""), reverse, true),
        ("time-scaled ×2", segment(", \"pitch\": \"spectral\"", sourceDuration: 1_200_000),
         reverse, false),
        ("ramped", segment(
            ", \"ramp\": {\"keep_pitch\": false, \"glide\": [], "
                + "\"map\": [[0, 0], [600000, 1200000]], \"constant\": true}",
            sourceDuration: 1_200_000), reverse, false),
        ("freeze", segment("", duration: 1_200_000, sourceDuration: 20_000), reverse, false),
        ("pending reverse", segment(""), pendingReverse, false),
    ]
    var ok = true
    var parts: [String] = []
    for (name, s, resolution, wanted) in cases {
        guard let s else {
            ok = false
            parts.append("\(name): did not decode")
            continue
        }
        let got = IsolationCache.request(
            for: s, dsp: f.dsp, urls: f.document.mediaURLs(), reverse: resolution)
        ok = ok && (got != nil) == wanted
        parts.append("\(name): \(got == nil ? "no request" : "a request")")
    }
    row("P4", ok, parts.joined(separator: ", "))
}

// =========================================================================
// P5, P6 — the renderer on the owner's recording

func renderRode(_ window: IsolationWindow, _ name: String) -> (IsolatedAudio?, String) {
    guard FileManager.default.fileExists(atPath: rode.path) else {
        return (nil, "\(rode.path) is not here")
    }
    let destination = work.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: destination)
    do {
        let source = try RampAudioCache.renderSource(for: rode)
        let report = try IsolationRenderer.render(
            IsolationRenderer.Job(source: source, window: window, destination: destination),
            cancelled: { false })
        guard let audio = IsolatedAudio(contentsOf: destination) else {
            return (nil, "the render did not read back")
        }
        return (audio, String(format: "%lld frames, %d ch, latency %d, %.2f s wall",
            report.frames, report.channels, report.latencyFrames, report.wallSeconds))
    } catch {
        return (nil, "the render failed: \(error.localizedDescription)")
    }
}

/// The Rode recording's frames [from, to) on channel 0.
func rodeDry(from: Int64, to: Int64) -> [Float]? {
    let asset = AVURLAsset(url: (try? RampAudioCache.renderSource(for: rode)) ?? rode)
    guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .audio),
        let reader = try? RampSourceReader(asset: asset, track: track, channels: 1, from: from)
    else { return nil }
    guard (try? reader.fill(through: to)) != nil else { return nil }
    return (from..<to).map { reader.sample($0, channel: 0) }
}

do {
    let window = IsolationWindow(firstFrame: 10 * 48_000, endFrame: 16 * 48_000)
    let (audio, detail) = renderRode(window, "p5.caf")
    if let audio, let dry = rodeDry(from: window.firstFrame, to: window.endFrame) {
        let wet = Array(UnsafeBufferPointer(start: audio.samples(channel: 0), count: audio.frames))
        // Σ wet[i]·dry[i + lag] over 3 s inside the window, lag in ±6,000.
        let base = 48_000
        let n = 3 * 48_000
        var best = -Float.infinity
        var bestLag = Int.min
        for lag in -6_000...6_000 {
            var dot: Float = 0
            wet.withUnsafeBufferPointer { w in
                dry.withUnsafeBufferPointer { d in
                    vDSP_dotpr(w.baseAddress! + base, 1, d.baseAddress! + base + lag, 1, &dot,
                        vDSP_Length(n))
                }
            }
            if dot > best { (best, bestLag) = (dot, lag) }
        }
        row("P5", bestLag == 0 && audio.frames == Int(window.endFrame - window.firstFrame),
            "6 s from 10 s: \(detail); \(audio.frames) frames read back; cross-correlation "
                + "peak at lag \(bestLag) (want 0)")
    } else {
        row("P5", false, detail)
    }
}

do {
    let window = IsolationWindow(firstFrame: 10 * 48_000, endFrame: 15 * 48_000)
    let total = (try? AVAudioFile(forReading: rode).length) ?? 0
    let (part, partDetail) = renderRode(window, "p6-window.caf")
    let (whole, wholeDetail) = renderRode(
        IsolationWindow(firstFrame: 0, endFrame: total), "p6-whole.caf")
    if let part, let whole, whole.frames >= 11 * 48_000 {
        var error: Double = 0
        var power: Double = 0
        let a = part.samples(channel: 0)
        let b = whole.samples(channel: 0)
        for i in 0..<48_000 {
            let x = Double(a[i])
            let y = Double(b[10 * 48_000 + i])
            error += (x - y) * (x - y)
            power += y * y
        }
        let residual = 10 * log10(max(error, 1e-30) / max(power, 1e-30))
        row("P6", residual <= -40,
            String(format: "[10, 15 s) against [0, end) over 10–11 s: residual %.1f dB "
                + "(bound −40); window %@; whole %@", residual, partDetail, wholeDetail))
    } else {
        row("P6", false, "window: \(partDetail); whole: \(wholeDetail)")
    }
}

// =========================================================================
// P7 — the name

do {
    let w1 = IsolationWindow(firstFrame: 0, endFrame: 48_000)
    let w2 = IsolationWindow(firstFrame: 0, endFrame: 48_001)
    let forward = IsolationCache.name(media: 1, mediaFile: dryA, reversed: false, window: w1)
    let longer = IsolationCache.name(media: 1, mediaFile: dryA, reversed: false, window: w2)
    let reversed = IsolationCache.name(media: 1, mediaFile: dryA, reversed: true, window: w1)
    var amountSame = false
    if let half = fixture(isolation: 0.5), let full = fixture(isolation: 1),
        let s = half.segment
    {
        let reverse = ReverseResolution(ready: [:], pending: [], isolated: isolatedDir)
        let a = IsolationCache.request(
            for: s, dsp: half.dsp, urls: half.document.mediaURLs(), reverse: reverse)
        let b = IsolationCache.request(
            for: s, dsp: full.dsp, urls: full.document.mediaURLs(), reverse: reverse)
        amountSame = a != nil && a?.destination == b?.destination
    }
    let ok = forward != nil && forward != longer && forward != reversed && longer != reversed
        && amountSame
    row("P7", ok,
        "window [0, 48000) \(forward ?? "nil"), [0, 48001) \(longer ?? "nil"), reversed "
            + "\(reversed ?? "nil"); amount 0.5 and 1 name one file: \(amountSame)")
}

// =========================================================================
// P8 — the export waits

do {
    let document = ProjectDocument()
    var detail = "the fixture did not build"
    var ok = false
    if FileManager.default.fileExists(atPath: rode.path),
        let clip = place(document, rode, seconds: 30, at: 0)
    {
        edit(
            document, "Iso", [.trimEnd(clip: clip, to: 3 * SEC),
                    .setAudio(clips: [clip], patch: AudioPatch(isolation: 1))])
        let folder = work.appendingPathComponent("p8", isDirectory: true)
            .appendingPathComponent("cache", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        let dir = IsolationCache.directory(in: folder)
        let key = RecipeSource.shared.register()
        RecipeSource.shared.set(document.project, for: key)
        AudioDSPSource.shared.publish(
            AudioDSPParameters(snapshot: document.project.snapshot), for: key)
        let resolution = ReverseResolution(ready: [:], pending: [], isolated: dir)
        ReverseSource.shared.publish(resolution, project: document.project, for: key)
        if let plan = document.project.plan,
            let settings = try? ReelExport.settings(document.project, preset: "audio_wav")
        {
            let urls = document.mediaURLs()
            let requests = IsolationCache.requests(
                plan: plan, dsp: AudioDSPParameters(snapshot: document.project.snapshot),
                urls: urls, reverse: resolution)
            var existed: [Bool] = []
            do {
                try Exporter.withRampAudio(
                    plan: plan, urls: urls, settings: settings, key: key, cancelled: { false }
                ) {
                    existed = requests.map {
                        FileManager.default.fileExists(atPath: $0.destination.path)
                    }
                }
                ok = !requests.isEmpty && existed.allSatisfy { $0 }
                detail = "\(requests.count) isolation request(s); at build each file existed: "
                    + "\(existed)"
            } catch {
                detail = "withRampAudio threw: \(error.localizedDescription)"
            }
            RampAudioRenders.shared.release(owner: key)
        }
    }
    row("P8", ok, detail)
}

// =========================================================================
// P9 — a failure reaches the owner

do {
    let folder = work.appendingPathComponent("p9", isDirectory: true)
        .appendingPathComponent("cache", isDirectory: true)
    try? FileManager.default.removeItem(at: folder)
    let dir = IsolationCache.directory(in: folder)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let text = work.appendingPathComponent("not-audio.txt")
    try? "not audio".write(to: text, atomically: true, encoding: .utf8)
    let request = RampAudioRequest(
        clip: 77, media: 9, destination: dir.appendingPathComponent("9-forced.caf"),
        source: text, reversed: true,
        job: .isolation(IsolationWindow(firstFrame: 0, endFrame: 48_000)))
    var calls = 0
    var onMain = true
    let owner = 990_001
    RampAudioRenders.shared.want([request], owner: owner) {
        calls += 1
        onMain = onMain && Thread.isMainThread
    }
    let deadline = Date().addingTimeInterval(60)
    while calls == 0, Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    let failure = RampAudioRenders.shared.failure(for: request.destination)
    let status = IsolationCache.status(of: request)
    RampAudioRenders.shared.release(owner: owner)
    let ok = calls == 1 && onMain && failure != nil && status == .failed(failure ?? "")
    row("P9", ok,
        "settled ran \(calls) time(s), on main: \(onMain); failure: \(failure ?? "nil"); "
            + "status: \(status)")
}
