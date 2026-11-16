// tools/proof/audio_ap5_probe.swift — the in-process instrument behind
// `audio_ap5_proof.py --probe` (road map "audio" AP5, spec §11 AU-50…AU-57).
// Compiled with every file in `app/Sources` but `main.swift` through
// `swift_build.py`'s line under `FRAMEJOB_DEV_TOOLS` (P11 and P12 hold a
// render through `RampAudioRenders.devHoldKey`), copied in as `main.swift`,
// with `Blank.mp4` beside the binary (the builder's placeholder track for an
// audio-only plan).
//
//     audio_ap5_probe <work-dir> <Rode-usb-mic.m4a>
//
// Fixtures are 48 kHz stereo float WAVs of seeded noise written by
// `AVAudioFile`; a synthetic "render" is seeded noise written by
// `RampCAFWriter` under the name `IsolationCache` gives the clip's window.
// Projects are ops on an untitled `ProjectDocument`, published under a fresh
// recipe key with `AudioDSPSource` and a `ReverseResolution` whose `isolated`
// is <work-dir>/cache/isolated. One line per row, `ok <ID> — <detail>` or
// `FAIL <ID> — <detail>`; no app is launched. With `AP5_ROWS=P4,P13` in the
// environment only the sections answering those rows run (the proof's
// mutants ask for their own).
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
//  P4  a ×1 segment gets a tapped request and no chain; a constant speed with
//      Keep pitch on a two-stage chain, with it off or a ramp a three-stage
//      one, each stage formable only once the file before it is on disk; a
//      pending reverse none (AU-55 as amended, #387).
//  P5  `IsolationRenderer` over 6 s of the Rode recording from 10 s: the
//      render's lag against the dry by cross-correlation is 0.
//  P6  the window [10, 15 s) against the whole file's render over 10–11 s:
//      residual ≤ −40 dB.
//  P7  `name` differs by window and by reversal; a request ignores Amount.
//  P8  `Exporter.withRampAudio` runs its build only once the isolation file
//      exists.
//  P9  a forced failure: the owner's `settled` runs exactly once, on the main
//      queue; `failure(for:)` and `IsolationCache.status(of:)` carry the message.
//  P10 a round's frame count (#409): lanes that agree give their count; lanes
//      that differ fail the render naming both counts; one lane its own.
//  P11 Voice Isolation's Status in the app's own Clip pane (#408): "Off";
//      after `set_audio {isolation: 1}`, read while the render is held (ten
//      minutes, so no host can settle it first), "Rendering…"; the hold is
//      then taken off, the held render dropped and the document wants it
//      again; after the document's `.reversedMediaDidChange`, "Ready", its
//      file on disk. A second leg on a media that is not audio:
//      "Rendering…", then "Not rendered: " and the render's own failure,
//      which names the isolated voice (not the ramp renderer's "retimed
//      audio", whose source check a forward clip's isolation shares).
//      Neither the handles nor the published resolution change when a
//      render settles, so only the pane's drop of its memo moves the words.
//  P12 the same landing leg for Voice Effect's Status (its own memo).
//      P11 and P12 run first, before any other row's document wants a
//      render, and each leg releases its wants and removes its cache folder.
//
// The retimed rows (#387). Their chains are rendered by the export's own
// wait, with the DRY window written where the isolation lands, so a mix is
// the dry sound and a processed render must equal the dry one.
//  P13 the shift is exact: the processed render against the dry render of
//      the same segment — ×2 (from 2.5 s, and over 2–6 s of the file,
//      where both ends sit on a whole second and only the pad holds what the
//      resampler reads outside them) and a ×1→×2 ramp with Keep pitch off,
//      and a clip whose source-in is under the pad, max |Δ| ≤ 1e-6; a ×1→×2
//      ramp (from 2.5 s and from 2 s) and a ×1→×12 ramp with Keep pitch on
//      ≤ −60 dB, and the frames Apple's unit read past the clip's last no
//      more than the window holds.
//  P8b the export's wait ran its build with every stage of each chain on disk.
//  P18 a metering build (the preview's) and an export build of each read
//      identical; a live ×2 clip's two reads, and the dry clip's, each
//      within −10 dB (AVFoundation's time-pitch is not deterministic, #337:
//      both figures reported), and its lag against the dry clip, whose
//      samples its window holds, 0 (≤ 48 samples).
//  P14 the mix: dry 1 and isolated 0 give 1 − a at 0.5 and 0.25; mono stays
//      mono; an Amount moved 0 → 1 over a two-leg map against the closed form.
//  P15 a live segment reads its processed window at source-in − the window's
//      first frame (less SY-24's lead at ×1.0005), scaled as the media, on a
//      composition track apart from an AAC neighbour, with no tap; with the
//      file removed it reads the media. A rendered segment plays its
//      processed render, the dry one when only that exists, nothing with
//      neither.
//  P16 names: a rate edit that keeps the window keeps the isolation and the
//      mix and renames the render; an Amount renames the mix and the render,
//      not the isolation; a window that moves renames the isolation; a dry
//      render's name is what the rule before #387 gives.
//  P17 the Status: "Rendering…" under a held render with the dry render
//      wanted beside the chain, "Ready" once the last file lands, "Not
//      rendered: …" in the isolation's words; "Plays no sound" above the
//      audio ceiling, for Voice Isolation and Voice Effect.
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

/// `AP5_ROWS=P4,P13` runs only the sections that answer one of those rows (a
/// mutant is scored on its own rows); unset, every section runs.
let chosenRows: Set<String>? = ProcessInfo.processInfo.environment["AP5_ROWS"].map {
    Set($0.split(separator: ",").map(String.init))
}
func runs(_ ids: String...) -> Bool {
    chosenRows.map { !$0.isDisjoint(with: ids) } ?? true
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
    let output = ExportWriter.audioReadOutput(built)
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

if runs("P1") {
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

if runs("P2") {
    let (alone, aloneDetail) = p2(noiseClip: false, bound: 1e-7)
    let (led, ledDetail) = p2(noiseClip: true, bound: 1e-4)
    row("P2", alone && led, aloneDetail + "; " + ledDetail)
}

// =========================================================================
// P2b — off the 48 kHz grid

if runs("P2b") {
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

if runs("P3") {
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

if runs("P5") {
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

if runs("P6") {
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
// P11, P12 — the Status memo dropped when a render lands or fails (#408)

var kept: [AnyObject] = []

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

/// The app's Clip pane over `document` with `clip` selected, on the Sound
/// sub-tab, in no window: the "Status" read-out of the section `id`.
func statusReadout(_ document: ProjectDocument, _ clip: UInt32, section id: String)
    -> OptionDisplayControl?
{
    let inspector = InspectorViewController()
    inspector.document = document
    document.selection = [clip]
    inspector.binding.invalidate()
    let pane = ClipPane(inspector: inspector)
    kept += [inspector, pane]
    pane.binding.invalidate()
    pane.choose(.sound)
    pane.rebuild()
    pane.refresh()
    guard let section = pane.sections.first(where: { $0.id == id }) else { return nil }
    let row = walk(section).compactMap { $0 as? InspectorRowView }.first { row in
        row.arrangedSubviews.contains { ($0 as? InspectorRowLabel)?.stringValue == "Status" }
    }
    return row.flatMap { row in walk(row).lazy.compactMap { $0 as? OptionDisplayControl }.first }
}

struct StatusLeg {
    var off = ""
    var before = ""
    var after = ""
    /// Why the "before" read cannot be trusted, when it cannot.
    var early: String?
    var settles = 0
    var fileExists = false
    var failure: String?
    var problem: String?
}

/// The render hold P11 and P12 read under, in seconds: long enough that no
/// host settles a render before the first read.
let statusHold = 600.0

/// `seconds` as `-RCDevRampRenderHold`, in the registration domain: nothing
/// is written to disk.
func holdRenders(_ seconds: Double) {
    UserDefaults.standard.register(defaults: [RampAudioRenders.devHoldKey: seconds])
}

/// One leg: a 1 s clip of `file`, the pane built while the section is off,
/// `patch` applied through the document (which wants the render, held
/// `statusHold` seconds), the Status read; then the hold taken off, the held
/// render dropped (waited for through `keptNames`, which names a running
/// render) and wanted again by the document's own `ensureRampAudio()`; and
/// the Status read again after the document's `.reversedMediaDidChange`. No
/// sleep decides a read: each wait is for a state, bounded at 120 s.
func statusLeg(_ file: URL, section id: String, patch: AudioPatch, voice: Bool) -> StatusLeg {
    var leg = StatusLeg()
    let document = ProjectDocument()
    guard let clip = place(document, file, seconds: 12, at: 0) else {
        leg.problem = "the clip was not placed"
        return leg
    }
    edit(document, "Trim", [.trimEnd(clip: clip, to: SEC)])
    guard let readout = statusReadout(document, clip, section: id) else {
        leg.problem = "the pane has no \(id) Status read-out"
        return leg
    }
    func read() -> String {
        readout.refresh()
        return readout.text
    }
    leg.off = read()
    var settles = 0
    let observer = NotificationCenter.default.addObserver(
        forName: .reversedMediaDidChange, object: document, queue: nil
    ) { _ in settles += 1 }
    defer {
        NotificationCenter.default.removeObserver(observer)
        RampAudioRenders.shared.release(owner: document.recipeKey)
        if let cache = document.temporaryCacheDirectory {
            try? FileManager.default.removeItem(at: cache)
        }
    }
    holdRenders(statusHold)
    defer { holdRenders(0) }
    edit(document, "Set", [.setAudio(clips: [clip], patch: patch)])
    let dsp = AudioDSPParameters(snapshot: document.project.snapshot)
    let reverse = ReverseSource.shared.resolution(for: document.recipeKey)
    let urls = document.mediaURLs()
    let segment = document.project.plan?.audioTracks.flatMap(\.segments).first { $0.clip == clip }
    let request = segment.flatMap { s in
        voice
            ? VoiceCache.request(for: s, dsp: dsp, urls: urls, reverse: reverse)
            : IsolationCache.request(for: s, dsp: dsp, urls: urls, reverse: reverse)
    }
    guard let request else {
        leg.problem = "the clip has no render request"
        return leg
    }
    leg.before = read()
    if settles > 0 {
        leg.early = "the render settled before the first read, under the hold"
    } else if FileManager.default.fileExists(atPath: request.destination.path) {
        leg.early = "the render's file was there before the first read"
    } else if let failure = RampAudioRenders.shared.failure(for: request.destination) {
        leg.early = "the render had failed before the first read: \(failure)"
    }
    // The hold off, and the held render dropped: `release` cancels it, and
    // it is gone from `keptNames` once it has stopped. Wanting it again
    // sooner would only un-cancel the held one.
    holdRenders(0)
    let folder = request.destination.deletingLastPathComponent()
    RampAudioRenders.shared.release(owner: document.recipeKey)
    let deadline = Date().addingTimeInterval(120)
    while !RampAudioRenders.shared.keptNames(in: folder).isEmpty, Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    guard RampAudioRenders.shared.keptNames(in: folder).isEmpty, settles == 0 else {
        leg.problem = "the held render did not stop (settled \(settles))"
        return leg
    }
    document.ensureRampAudio()
    while settles == 0, Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    leg.settles = settles
    leg.after = read()
    leg.fileExists = FileManager.default.fileExists(atPath: request.destination.path)
    leg.failure = RampAudioRenders.shared.failure(for: request.destination)
    return leg
}

func told(_ leg: StatusLeg) -> String {
    if let problem = leg.problem { return problem }
    return "\"\(leg.off)\" → \"\(leg.before)\" → \"\(leg.after)\" (settled \(leg.settles), file "
        + "\(leg.fileExists), failure \(leg.failure ?? "none")"
        + (leg.early.map { "; \($0)" } ?? "") + ")"
}

func landed(_ leg: StatusLeg) -> Bool {
    leg.problem == nil && leg.early == nil && leg.off == "Off" && leg.before == "Rendering…"
        && leg.settles > 0 && leg.after == "Ready" && leg.fileExists && leg.failure == nil
}

if runs("P11", "P12") {
    let lands = statusLeg(
        dryA, section: "audio.isolation", patch: AudioPatch(isolation: 1), voice: false)
    let text = work.appendingPathComponent("p11-not-audio.txt")
    try? "not audio".write(to: text, atomically: true, encoding: .utf8)
    let fails = statusLeg(
        text, section: "audio.isolation", patch: AudioPatch(isolation: 1), voice: false)
    let failed = fails.problem == nil && fails.early == nil && fails.off == "Off"
        && fails.before == "Rendering…" && fails.settles > 0 && fails.failure != nil
        && fails.after == "Not rendered: " + (fails.failure ?? "") && !fails.fileExists
        && (fails.failure ?? "").hasPrefix("The isolated voice's source cannot be read: ")
    row("P11", landed(lands) && failed, "lands: \(told(lands)); fails: \(told(fails))")

    let voiced = statusLeg(
        dryA, section: "audio.voice",
        patch: AudioPatch(voice: .some(VoiceProps(kind: .pitch, pitch: 2))), voice: true)
    row("P12", landed(voiced), "lands: \(told(voiced))")
}

// =========================================================================
// P17 — a retimed clip's Status, and what the document wants (#387). Here,
// with P11 and P12, before any other row's document wants a render.

if runs("P17") {
    var parts: [String] = []
    var ok = true
    /// A 1 s clip of `file` at `rate`, isolated; the Status under a held
    /// render, what the document wants meanwhile, and the Status once the
    /// chain settles (a state waited for, bounded at 120 s).
    func leg(_ file: URL, rate: Double, keepPitch: Bool) -> (String, String, Bool, [Int]) {
        let document = ProjectDocument()
        guard let clip = place(document, file, seconds: 12, at: 0) else {
            return ("no clip", "", false, [])
        }
        edit(document, "Trim", [.trimEnd(clip: clip, to: 2 * SEC)])
        edit(document, "Speed", [.setSpeed(clip: clip, rate: rate, keepPitch: keepPitch)])
        defer {
            RampAudioRenders.shared.release(owner: document.recipeKey)
            if let cache = document.temporaryCacheDirectory {
                try? FileManager.default.removeItem(at: cache)
            }
        }
        holdRenders(statusHold)
        defer { holdRenders(0) }
        edit(document, "Iso", [.setAudio(clips: [clip], patch: AudioPatch(isolation: 1))])
        let before = AudioPane.isolationWords(IsolationCache.status(of: clip, in: document))
        var wantsDry = false
        if let s = document.project.plan?.audioTracks.flatMap(\.segments).first(where: {
            $0.clip == clip
        }), let directory = document.rampAudioDirectory,
            let dry = RampAudioCache.request(
                for: s, urls: document.mediaURLs(),
                reverse: ReverseSource.shared.resolution(for: document.recipeKey))
        {
            wantsDry = RampAudioRenders.shared.keptNames(in: directory)
                .contains(dry.destination.lastPathComponent)
        }
        holdRenders(0)
        RampAudioRenders.shared.release(owner: document.recipeKey)
        let deadline = Date().addingTimeInterval(120)
        func kept() -> Bool {
            [document.rampAudioDirectory, document.isolatedAudioDirectory].compactMap { $0 }
                .contains { !RampAudioRenders.shared.keptNames(in: $0).isEmpty }
        }
        while kept(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        document.ensureRampAudio()
        var status = IsolationCache.status(of: clip, in: document)
        while status == .rendering, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            status = IsolationCache.status(of: clip, in: document)
        }
        func count(_ directory: URL?) -> Int {
            directory.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) }?
                .filter { $0.hasSuffix(".caf") }.count ?? 0
        }
        return (before, AudioPane.isolationWords(status), wantsDry,
            [count(document.isolatedAudioDirectory), count(document.rampAudioDirectory)])
    }
    let off = leg(dryA, rate: 2, keepPitch: false)
    let good = off.0 == "Rendering…" && off.1 == "Ready" && off.2 && off.3 == [2, 2]
    ok = ok && good
    parts.append("×2 Keep pitch off: \"\(off.0)\" under a held render, the dry render wanted "
        + "beside the chain: \(off.2); then \"\(off.1)\" with \(off.3[safe: 0] ?? -1) isolated "
        + "and \(off.3[safe: 1] ?? -1) ramp files (want 2 and 2)")
    let on = leg(dryA, rate: 2, keepPitch: true)
    ok = ok && on.0 == "Rendering…" && on.1 == "Ready" && on.3 == [2, 0]
    parts.append("×2 Keep pitch on: \"\(on.0)\" → \"\(on.1)\", \(on.3[safe: 0] ?? -1) isolated "
        + "and \(on.3[safe: 1] ?? -1) ramp files (want 2 and 0)")
    let text = work.appendingPathComponent("p17-not-audio.txt")
    try? "not audio".write(to: text, atomically: true, encoding: .utf8)
    let fails = leg(text, rate: 2, keepPitch: true)
    ok = ok && fails.1.hasPrefix("Not rendered: The isolated voice's source cannot be read")
    parts.append("a file that is not audio: \"\(fails.1)\"")

    // Above the audio ceiling a clip plays no sound: nothing to isolate.
    let silent = ProjectDocument()
    if let clip = place(silent, dryA, seconds: 12, at: 0) {
        edit(silent, "Fast", [
            .setSpeed(clip: clip, rate: 16),
            .setAudio(clips: [clip], patch: AudioPatch(
                isolation: 1, voice: .some(VoiceProps(kind: .pitch, pitch: 2)))),
        ])
        let isolation = AudioPane.isolationWords(IsolationCache.status(of: clip, in: silent))
        let voice = AudioPane.isolationWords(VoiceCache.status(of: clip, in: silent))
        let segments = silent.project.plan?.audioTracks.flatMap(\.segments)
            .filter { $0.clip == clip && $0.duration > 0 }.count ?? -1
        ok = ok && isolation == "Plays no sound" && voice == "Plays no sound" && segments == 0
        parts.append("×16 (\(segments) audio segments): Voice Isolation \"\(isolation)\", Voice "
            + "Effect \"\(voice)\"")
        RampAudioRenders.shared.release(owner: silent.recipeKey)
    } else {
        ok = false
        parts.append("×16: no clip")
    }
    row("P17", ok, parts.joined(separator: "; "))
}

// =========================================================================
// P7 — the name

if runs("P7") {
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

if runs("P8") {
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

if runs("P9") {
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

// =========================================================================
// P10 — lanes that disagree fail the render (#409)

if runs("P10") {
    let agree = try? IsolationRenderer.roundFrames([4096, 4096])
    let one = try? IsolationRenderer.roundFrames([4096])
    var message = "no error"
    var named = false
    do {
        let got = try IsolationRenderer.roundFrames([4096, 4095])
        message = "answered \(got)"
    } catch let error as IsolationRenderer.RenderError {
        if case .failed(let why) = error {
            named = why.contains("4096") && why.contains("4095")
        }
        message = error.localizedDescription
    } catch {
        message = "another error: \(error.localizedDescription)"
    }
    row("P10", agree == 4096 && one == 4096 && named,
        "[4096, 4096] → \(agree.map(String.init) ?? "threw"); [4096] → "
            + "\(one.map(String.init) ?? "threw"); [4096, 4095] → \(message)")
}

// =========================================================================
// P13–P18, P8b — a retimed clip is isolated through its processed window
// (spec §11 AU-55 as amended, #387)

/// One clip of `file` on its own document, retimed, with `isolation`, its
/// renders published into a cache folder of its own.
struct Retimed {
    let f: Fixture
    let reverse: ReverseResolution
    var urls: [UInt32: URL] { f.document.mediaURLs() }
    var segment: PlanSegment? { f.segment }
    var chain: RetimedSound.Chain? {
        segment.flatMap { RetimedSound.chain(for: $0, dsp: f.dsp, urls: urls, reverse: reverse) }
    }
}

enum Retime {
    case constant(Double, keepPitch: Bool)
    case ramp(to: Double, keepPitch: Bool)
}

/// The clip is added at 1 s, trimmed to start `sourceIn` into the file and to
/// last `length`, then retimed. `amount` 0 leaves it dry.
func retimed(
    _ name: String, _ retime: Retime, amount: Double = 1, sourceIn: Ticks = 5 * SEC / 2,
    length: Ticks = 4 * SEC, file: URL = dryA, seconds: Double = 12, neighbour: URL? = nil
) -> Retimed? {
    let document = ProjectDocument()
    guard let clip = place(document, file, seconds: seconds, at: SEC) else { return nil }
    edit(document, "Trim", [
        .trimStart(clip: clip, to: SEC + sourceIn),
        .trimEnd(clip: clip, to: SEC + sourceIn + length),
    ])
    switch retime {
    case .constant(let rate, let keepPitch):
        edit(document, "Speed", [.setSpeed(clip: clip, rate: rate, keepPitch: keepPitch)])
    case .ramp(let rate, let keepPitch):
        if !keepPitch {
            edit(document, "Pitch", [.setSpeed(clip: clip, rate: 1, keepPitch: false)])
        }
        edit(document, "Ramp", [.addSpeedRamp(clip: clip, shape: .rampUp, rate: rate)])
    }
    if amount > 0 {
        edit(document, "Iso", [.setAudio(clips: [clip], patch: AudioPatch(isolation: amount))])
    }
    if let neighbour, let other = addMedia(document, neighbour, seconds: 30) {
        let track = document.project.snapshot.tracks[0].id
        edit(document, "Neighbour", [.addClip(track: track, media: other, at: 20 * SEC)])
    }
    let cache = work.appendingPathComponent("retimed-\(name)", isDirectory: true)
        .appendingPathComponent("cache", isDirectory: true)
    try? FileManager.default.removeItem(at: cache)
    let reverse = ReverseResolution(
        ready: [:], pending: [], rampAudio: RampAudioCache.directory(in: cache),
        isolated: IsolationCache.directory(in: cache))
    // The document's own wants (into its temporary cache) are not the row's.
    RampAudioRenders.shared.release(owner: document.recipeKey)
    let key = RecipeSource.shared.register()
    RecipeSource.shared.set(document.project, for: key)
    AudioDSPSource.shared.publish(AudioDSPParameters(snapshot: document.project.snapshot), for: key)
    ReverseSource.shared.publish(reverse, project: document.project, for: key)
    return Retimed(f: Fixture(document: document, key: key, clip: clip), reverse: reverse)
}

/// `file`'s frames `[window)` as interleaved floats, `channels` wide.
func sourceFrames(_ file: URL, _ window: IsolationWindow, channels: Int) -> [Float]? {
    let asset = AVURLAsset(url: file)
    guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .audio),
        let reader = try? RampSourceReader(
            asset: asset, track: track, channels: channels, from: window.firstFrame),
        (try? reader.fill(through: window.endFrame)) != nil
    else { return nil }
    var out: [Float] = []
    out.reserveCapacity(Int(window.endFrame - window.firstFrame) * channels)
    for k in window.firstFrame..<window.endFrame {
        for c in 0..<channels { out.append(reader.sample(k, channel: c)) }
    }
    return out
}

func writeCAF(_ url: URL, _ samples: [Float], channels: Int) -> Bool {
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let writer = try? RampCAFWriter(url: url, channels: channels) else { return false }
    do {
        try writer.write(samples, frames: samples.count / channels)
        try writer.close()
    } catch { return false }
    return true
}

/// The DRY window written where the chain's isolation lands, so the mix at
/// any Amount is the dry sound and the processed render must equal the dry
/// one; then the rest of the chain rendered by the export's own wait.
/// Answers whether `build` ran with every stage on disk, or why not.
func renderChain(_ r: Retimed, file: URL = dryA) -> (ok: Bool, detail: String) {
    guard let chain = r.chain, let isolation = chain.isolation, let plan = r.f.project.plan,
        let dry = sourceFrames(file, chain.window, channels: 2),
        writeCAF(isolation.destination, dry, channels: 2)
    else { return (false, "no chain, or its isolation was not written") }
    var existed: [Bool] = []
    do {
        try Exporter.withOfflineAudio(plan: plan, urls: r.urls, key: r.f.key, cancelled: { false }) {
            existed = chain.stages.map {
                FileManager.default.fileExists(atPath: $0.destination.path)
            }
        }
    } catch {
        return (false, "withOfflineAudio threw: \(error.localizedDescription)")
    }
    RampAudioRenders.shared.release(owner: r.f.key)
    return (existed.count == chain.stages.count && existed.allSatisfy { $0 },
        "\(chain.stages.count) stages, on disk at build: \(existed)")
}

func channel0(_ url: URL) -> [Float]? {
    guard let audio = IsolatedAudio(contentsOf: url) else { return nil }
    return Array(UnsafeBufferPointer(start: audio.samples(channel: 0), count: audio.frames))
}

/// (max |a − b|, 10·log10(Σ(a − b)² / Σ b²)) over the common length.
func difference(_ a: [Float], _ b: [Float]) -> (worst: Float, db: Double) {
    let n = min(a.count, b.count)
    var worst: Float = 0
    var error = 0.0
    var power = 0.0
    for i in 0..<n {
        let d = a[i] - b[i]
        worst = max(worst, abs(d))
        error += Double(d) * Double(d)
        power += Double(b[i]) * Double(b[i])
    }
    return (worst, 10 * log10(max(error, 1e-30) / max(power, 1e-30)))
}

/// The dry render of `r`'s segment, straight through the renderer.
func dryRender(_ r: Retimed, _ name: String, file: URL = dryA)
    -> (samples: [Float], report: RampAudioRenderer.Report)?
{
    guard let ramp = r.segment?.ramp else { return nil }
    let url = work.appendingPathComponent("dry-render-\(name).caf")
    try? FileManager.default.removeItem(at: url)
    guard let report = try? RampAudioRenderer.render(
        RampAudioRenderer.Job(
            source: file, map: RampAudioCache.map(of: ramp), keepPitch: ramp.keepPitch,
            destination: url)),
        let samples = channel0(url)
    else { return nil }
    return (samples, report)
}

// P4 — which segments are tapped, and which form a chain

if runs("P4") {
    var parts: [String] = []
    var ok = true
    func touch(_ url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }
    let cases: [(String, Retime?, RetimedSound.Kind, Int)] = [
        ("×1", nil, .tapped, 0),
        ("×2 Keep pitch on", .constant(2, keepPitch: true), .live, 2),
        ("×2 Keep pitch off", .constant(2, keepPitch: false), .rendered, 3),
        ("a ramp", .ramp(to: 2, keepPitch: true), .rendered, 3),
    ]
    for (name, retime, kind, stages) in cases {
        guard let r = retimed("p4-\(stages)-\(name.count)", retime ?? .constant(1, keepPitch: true)),
            let s = r.segment
        else {
            ok = false
            parts.append("\(name): no fixture")
            continue
        }
        let tapped = IsolationCache.request(for: s, dsp: r.f.dsp, urls: r.urls, reverse: r.reverse)
        let chain = r.chain
        var grown: [Int] = []
        if let chain {
            grown.append(chain.formable.count)
            for stage in chain.stages.dropLast() {
                touch(stage.destination)
                grown.append(chain.formable.count)
            }
        }
        let good = RetimedSound.kind(of: s) == kind && (tapped != nil) == (kind == .tapped)
            && (chain?.stages.count ?? 0) == stages && chain?.kind == (kind == .tapped ? nil : kind)
            && grown == Array(1...max(stages, 1)).prefix(stages).map { $0 }
        ok = ok && good
        parts.append("\(name): \(tapped == nil ? "no tapped request" : "a tapped request"), "
            + "\(chain?.stages.count ?? 0) chain stage(s), formable as each lands \(grown)")
    }
    if let r = retimed("p4-pending", .constant(2, keepPitch: true)), let s = r.segment {
        let pending = ReverseResolution(
            ready: [:], pending: [r.f.clip], rampAudio: r.reverse.rampAudio,
            isolated: r.reverse.isolated)
        let none = RetimedSound.chain(for: s, dsp: r.f.dsp, urls: r.urls, reverse: pending) == nil
        ok = ok && none
        parts.append("pending reverse: \(none ? "no chain" : "a chain")")
    }
    row("P4", ok, parts.joined(separator: "; "))
}

// P13, P8b, P18 — the shift is exact, the export waits for the whole chain,
// and a metering build reads what an export build reads

var rendered: [String: Retimed] = [:]
if runs("P13", "P8b", "P18", "P15") {
    var parts: [String] = []
    var ok = true
    var waited = true
    var waitParts: [String] = []
    var same = true
    var sameParts: [String] = []
    // name, retime, source-in, length, bound: max |Δ| for Keep pitch off, dB for on.
    let cases: [(String, Retime, Ticks, Ticks, Double)] = [
        ("x2-off", .constant(2, keepPitch: false), 5 * SEC / 2, 4 * SEC, 1e-6),
        // From 2 s to 6 s of the file: both ends on a whole second, so only
        // the pad holds what the resampler reads outside them.
        ("x2-off-grid", .constant(2, keepPitch: false), 2 * SEC, 4 * SEC, 1e-6),
        ("ramp-off", .ramp(to: 2, keepPitch: false), 5 * SEC / 2, 4 * SEC, 1e-6),
        ("head-off", .constant(2, keepPitch: false), SEC / 10, 2 * SEC, 1e-6),
        ("ramp-on", .ramp(to: 2, keepPitch: true), 5 * SEC / 2, 4 * SEC, -60),
        // On a whole second, so only the pad holds the unit's preroll.
        ("ramp-on-grid", .ramp(to: 2, keepPitch: true), 2 * SEC, 4 * SEC, -60),
        ("ramp-on-x12", .ramp(to: 12, keepPitch: true), SEC / 2, SEC, -60),
    ]
    for (name, retime, sourceIn, length, bound) in cases {
        guard let r = retimed("p13-\(name)", retime, sourceIn: sourceIn, length: length),
            let chain = r.chain, let s = r.segment
        else {
            ok = false
            parts.append("\(name): no fixture")
            continue
        }
        let made = renderChain(r)
        waited = waited && made.ok
        waitParts.append("\(name): \(made.detail)")
        guard made.ok, let processed = channel0(chain.last.destination),
            let dry = dryRender(r, name)
        else {
            ok = false
            parts.append("\(name): the chain or the dry render did not land (\(made.detail))")
            continue
        }
        rendered[name] = r
        let d = difference(processed, dry.samples)
        let keep = s.ramp?.keepPitch ?? false
        var good = processed.count == dry.samples.count && !processed.isEmpty
        var text = "\(name) (window from frame \(chain.window.firstFrame) to "
            + "\(chain.window.endFrame), \(processed.count) frames): "
        if keep {
            // What the unit read past what the clip plays, against the pad.
            let sounding = RetimedSound.sounding(of: s)!
            let played = sounding.endFrame - sounding.firstFrame
            let past = (dry.report.pulledFrames ?? 0) - played
            let room = chain.window.endFrame - sounding.endFrame
            good = good && d.db <= bound && past <= room
            text += String(format: "%.1f dB against the dry render (bound %.0f); the unit read "
                + "%lld frames past the clip's last, the window holds %lld", d.db, bound, past, room)
        } else {
            good = good && Double(d.worst) <= bound
            text += "max |Δ| \(d.worst) against the dry render (bound \(bound))"
        }
        ok = ok && good
        parts.append(text)

        // P18: the preview's build against the export's.
        guard let plan = r.f.project.plan,
            let export = build(r.f).flatMap(exportRead),
            let preview = (try? CompositionBuilder.build(
                plan: plan, planJSON: r.f.project.planJSON, urls: r.urls, recipeKey: r.f.key,
                metering: true)).flatMap(exportRead)
        else {
            same = false
            sameParts.append("\(name): a build did not read")
            continue
        }
        let equal = export.left == preview.left && export.right == preview.right
        let heard = export.left.contains { $0 != 0 }
        same = same && equal && heard
        sameParts.append("\(name): identical \(equal) over \(export.left.count) frames")
    }
    row("P13", ok, parts.joined(separator: "; "))
    row("P8b", waited, waitParts.joined(separator: "; "))

    // P18's live leg: Keep pitch on at ×2 is AVFoundation's time-pitch, read twice.
    func twoReads(_ r: Retimed) -> Double? {
        guard let plan = r.f.project.plan, let a = build(r.f).flatMap(exportRead),
            let b = (try? CompositionBuilder.build(
                plan: plan, planJSON: r.f.project.planJSON, urls: r.urls, recipeKey: r.f.key,
                metering: true)).flatMap(exportRead)
        else { return nil }
        return difference(a.left, b.left).db
    }
    // On the owner's recording: speech keeps its shape through the time-pitch.
    if let live = retimed(
        "p18-live", .constant(2, keepPitch: true), sourceIn: 8 * SEC, file: rode, seconds: 30),
        let dry = retimed(
            "p18-live-dry", .constant(2, keepPitch: true), amount: 0, sourceIn: 8 * SEC,
            file: rode, seconds: 30),
        renderChain(live, file: rode).ok, let isolated = twoReads(live),
        let plain = twoReads(dry),
        let a = build(live.f).flatMap(exportRead), let b = build(dry.f).flatMap(exportRead)
    {
        rendered["x2-on"] = live
        // The processed window holds the dry sound here, so the two clips
        // play the same samples: the lag between them is the substitution's.
        // 1.5 s from 0.25 s into the clip (it plays 2 s from 9 s).
        let n = 72_000
        let base = Int((live.segment?.start ?? 0) * 2 / 25) + 12_000
        var best = -Float.infinity
        var lag = Int.min
        for l in -2_000...2_000 {
            var dot: Float = 0
            a.left.withUnsafeBufferPointer { x in
                b.left.withUnsafeBufferPointer { y in
                    vDSP_dotpr(x.baseAddress! + base, 1, y.baseAddress! + base + l, 1, &dot,
                        vDSP_Length(n))
                }
            }
            if dot > best { (best, lag) = (dot, l) }
        }
        // Two reads of AVFoundation's time-pitch are sometimes identical
        // and sometimes not, dry or processed alike (measured from −18 dB
        // to −334 dB over four runs of this row, #337), so the two figures
        // are reported and held only to −10 dB: one sound, not another.
        let good = isolated <= -10 && plain <= -10 && abs(lag) <= 48 && best > 0
            && a.left.count >= base + n + 2_000
        same = same && good
        sameParts.append(String(format: "x2-on (live): two reads differ by %.1f dB, two reads "
            + "of the dry clip by %.1f dB (each ≤ −10: AVFoundation's time-pitch is not "
            + "deterministic); against the dry clip, whose samples its window holds, lag %d "
            + "samples (≤ 48, 1 ms)", isolated, plain, lag))
    } else {
        same = false
        sameParts.append("x2-on (live): did not build or read")
    }
    row("P18", same, sameParts.joined(separator: "; "))
}

// P14 — the mix

if runs("P14") {
    var parts: [String] = []
    var ok = true
    let folder = work.appendingPathComponent("p14", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let frames = 48_000
    func constant(_ name: String, channels: Int, value: Float) -> URL? {
        let url = folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        return writeCAF(url, [Float](repeating: value, count: frames * channels), channels: channels)
            ? url : nil
    }
    let window = IsolationWindow(firstFrame: 0, endFrame: Int64(frames))
    func mix(_ name: String, source: URL, isolated: URL, amount: Double, map: [[Ticks]] = [],
        points: [MixPoint] = []) -> (samples: [Float], channels: Int)?
    {
        let out = folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: out)
        let job = MixJob(
            window: window, isolated: isolated, amount: amount, map: map, points: points)
        guard (try? IsolationMix.render(
            IsolationMix.Job(source: source, job: job, destination: out),
            cancelled: { false })) != nil,
            let audio = IsolatedAudio(contentsOf: out)
        else { return nil }
        return (Array(UnsafeBufferPointer(start: audio.samples(channel: 0), count: audio.frames)),
            audio.channels)
    }
    if let mono = constant("one-mono.caf", channels: 1, value: 1),
        let stereo = constant("one-stereo.caf", channels: 2, value: 1),
        let zero = constant("zero.caf", channels: 2, value: 0)
    {
        for amount in [0.5, 0.25] {
            if let got = mix("flat-\(amount).caf", source: stereo, isolated: zero, amount: amount) {
                let worst = got.samples.map { abs($0 - Float(1 - amount)) }.max() ?? 1
                ok = ok && worst <= 1e-6 && got.channels == 2 && got.samples.count == frames
                parts.append("amount \(amount) of dry 1 and isolated 0: worst |out − "
                    + "\(1 - amount)| \(worst), \(got.channels) channels")
            } else {
                ok = false
                parts.append("amount \(amount): no file")
            }
        }
        if let got = mix("mono.caf", source: mono, isolated: zero, amount: 0.5) {
            ok = ok && got.channels == 1
            parts.append("a mono source: \(got.channels) channel(s)")
        } else {
            ok = false
            parts.append("mono: no file")
        }
        // A two-leg map: clip [0, 0.25 s) plays source [0, 0.25 s) at ×1, clip
        // [0.25, 0.5 s) plays source [0.25, 1 s) at ×3; the Amount runs 0 → 1
        // over the clip. Out = 1 − a(t(f)), computed here.
        let quarter = SEC / 4
        let map: [[Ticks]] = [[0, 0], [quarter, quarter], [2 * quarter, SEC]]
        let points = [MixPoint(at: 0, amount: 0), MixPoint(at: 2 * quarter, amount: 1)]
        if let got = mix(
            "moved.caf", source: stereo, isolated: zero, amount: 0, map: map, points: points)
        {
            var worst: Float = 0
            for (f, sample) in got.samples.enumerated() {
                let x = Double(f) * 12.5
                let t = x <= Double(quarter)
                    ? x : Double(quarter) + (x - Double(quarter)) / 3
                let a = min(max(t / Double(2 * quarter), 0), 1)
                worst = max(worst, abs(sample - Float(1 - a)))
            }
            ok = ok && worst <= 1e-5
            parts.append("an Amount moved 0 → 1 over a two-leg map: worst \(worst) against the "
                + "closed form (bound 1e-5)")
        } else {
            ok = false
            parts.append("moved: no file")
        }
    } else {
        ok = false
        parts.append("the fixtures were not written")
    }
    row("P14", ok, parts.joined(separator: "; "))
}

// P15 — what the composition reads

if runs("P15") {
    var parts: [String] = []
    var ok = true
    /// (source file, source start in ticks, source length, target start,
    /// target length, the composition track's id) of each non-empty segment.
    func segments(_ built: BuiltComposition) -> [(URL, Ticks, Ticks, Ticks, Ticks, CMPersistentTrackID)] {
        built.composition.tracks.filter { $0.mediaType == .audio }.flatMap { track in
            track.segments.compactMap { segment in
                guard !segment.isEmpty, let url = segment.sourceURL else { return nil }
                let m = segment.timeMapping
                return (url, CompositionBuilder.ticks(m.source.start),
                    CompositionBuilder.ticks(m.source.duration),
                    CompositionBuilder.ticks(m.target.start),
                    CompositionBuilder.ticks(m.target.duration), track.trackID)
            }
        }
    }
    func same(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.path == b.standardizedFileURL.path
    }
    // A live clip of the Rode recording (AAC) with a ×1 clip of it at 20 s:
    // one format on one plan track, until the live one reads its window.
    for (name, rate, lead) in [("×2", 2.0, Ticks(0)), ("×1.0005 (varispeed)", 1.0005, Ticks(575))] {
        guard FileManager.default.fileExists(atPath: rode.path),
            let r = retimed(
                "p15-\(rate)", .constant(rate, keepPitch: true), file: rode, seconds: 30,
                neighbour: rode),
            let chain = r.chain, let s = r.segment, renderChain(r, file: rode).ok,
            let built = build(r.f)
        else {
            ok = false
            parts.append("\(name): the fixture did not build")
            continue
        }
        let found = segments(built)
        let own = found.first { same($0.0, chain.processed.destination) }
        let other = found.first { same($0.0, rode) && $0.3 == 20 * SEC }
        let taps = built.audioMix.inputParameters.filter { $0.audioTapProcessor != nil }.count
        let wantIn = s.sourceIn - lead - chain.window.firstFrame * 25 / 2
        let placed = own.map {
            $0.1 == wantIn && $0.2 == s.sourceDuration && $0.3 == s.start && $0.4 == s.duration
        } ?? false
        let apart = own != nil && other != nil && own!.5 != other!.5
        try? FileManager.default.removeItem(at: chain.processed.destination)
        let dry = build(r.f).map(segments)?.contains { same($0.0, rode) && $0.3 == s.start } ?? false
        let good = chain.kind == .live && placed && apart && taps == 0 && dry
        ok = ok && good
        parts.append("\(name), Keep pitch on: reads its processed window from "
            + "\(own.map { String($0.1) } ?? "nowhere") ticks (want \(wantIn)), "
            + "\(own.map { String($0.2) } ?? "-") long scaled to \(own.map { String($0.4) } ?? "-") "
            + "(want \(s.sourceDuration) → \(s.duration)); on a track of its own beside the AAC "
            + "clip: \(apart); taps \(taps); with the file removed it reads the media: \(dry)")
    }
    // A rendered segment: the processed render, else the dry one, else nothing.
    if let r = rendered["x2-off"], let chain = r.chain, let s = r.segment,
        let dry = RampAudioCache.request(for: s, urls: r.urls, reverse: r.reverse)
    {
        let first = build(r.f).map(segments)?.first?.0
        try? FileManager.default.createDirectory(
            at: dry.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: chain.last.destination, to: dry.destination)
        try? FileManager.default.removeItem(at: chain.last.destination)
        let second = build(r.f).map(segments)?.first?.0
        try? FileManager.default.removeItem(at: dry.destination)
        let third = build(r.f).map(segments)?.count
        let good = first.map { same($0, chain.last.destination) } == true
            && second.map { same($0, dry.destination) } == true && third == 0
        ok = ok && good
        parts.append("a rendered segment plays its processed render "
            + "(\(first?.lastPathComponent ?? "none")), the dry one when only that is there "
            + "(\(second?.lastPathComponent ?? "none")), and nothing with neither "
            + "(\(third.map(String.init) ?? "no build") segments)")
    } else {
        ok = false
        parts.append("rendered: P13's ×2 fixture is not there")
    }
    row("P15", ok, parts.joined(separator: "; "))
}

// P16 — what each file is named by

if runs("P16") {
    var parts: [String] = []
    var ok = true
    func chainOf(_ rate: Double, amount: Double, length: Ticks = 4 * SEC, keep: Bool = false)
        -> (Retimed, RetimedSound.Chain, PlanSegment)?
    {
        guard let r = retimed(
            "p16-\(rate)-\(amount)-\(length)", .constant(rate, keepPitch: keep), amount: amount,
            length: length),
            let chain = r.chain, let s = r.segment
        else { return nil }
        return (r, chain, s)
    }
    func last(_ request: RampAudioRequest?) -> String { request?.destination.lastPathComponent ?? "" }
    if let a = chainOf(2, amount: 1), let b = chainOf(1.9, amount: 1),
        let c = chainOf(2, amount: 0.5), let d = chainOf(2, amount: 1, length: 2 * SEC),
        let ramp = a.2.ramp, let file = a.0.urls[a.2.media]
    {
        let rate = last(a.1.isolation) == last(b.1.isolation)
            && last(a.1.processed) == last(b.1.processed) && last(a.1.render) != last(b.1.render)
        let amount = last(a.1.isolation) == last(c.1.isolation)
            && last(a.1.processed) != last(c.1.processed) && last(a.1.render) != last(c.1.render)
        let moved = last(a.1.isolation) != last(d.1.isolation)
        // A dry render's name by the rule as it stood before #387, spelled
        // again here: FNV-1a 64 over the media file, the renderer's version
        // (4), the reversal, Keep pitch, the glide and the map.
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        func pairs(_ list: [[Ticks]]) -> String {
            list.map { $0.map(String.init).joined(separator: ":") }.joined(separator: ",")
        }
        let key = "\(file.path)|\(size)|\(Int64(modified.rounded()))|v4|r0|k0"
            + "|g\(pairs(ramp.glide))|m\(pairs(ramp.map))"
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        let hex = String(hash, radix: 16)
        let pinned = "\(a.2.media)-" + String(repeating: "0", count: max(0, 16 - hex.count))
            + hex + ".caf"
        let dry = last(RampAudioCache.request(for: a.2, urls: a.0.urls, reverse: a.0.reverse))
        ok = rate && amount && moved && dry == pinned && dry != last(a.1.render)
        parts.append("×2 and ×1.9 of one window (\(a.1.window.firstFrame)–\(a.1.window.endFrame) "
            + "and \(b.1.window.firstFrame)–\(b.1.window.endFrame)): one isolation and one mix, "
            + "two renders: \(rate); Amount 1 and 0.5: one isolation, two mixes, two renders: "
            + "\(amount); a clip 2 s shorter: another isolation: \(moved); the dry render "
            + "\(dry) is the name the rule before #387 gives (\(pinned))")
    } else {
        ok = false
        parts.append("the fixtures did not build")
    }
    row("P16", ok, parts.joined(separator: "; "))
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
