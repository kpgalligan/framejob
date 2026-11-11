// tools/proof/voice_probe.swift — the in-process instrument behind
// `voice_proof.py --probe` and `--measure` (road map "audio" AP14, spec §11
// AU-140…AU-149). Compiled with every file in `app/Sources` but `main.swift`
// through `swift_build.py`'s line, copied in as `main.swift`, with
// `Blank.mp4` beside the binary.
//
//     voice_probe <work-dir> <Rode-usb-mic.m4a> [measure]
//
// Fixtures are 48 kHz float WAVs written by `AVAudioFile`: seeded stereo
// noise, 220 Hz tone bursts (100 ms on, 100 ms off) and a 50 ms noise burst
// at −6 dBFS RMS at 0.5 s in 10 s of silence (V9 uses it where AU-149's
// sketch said a click: it is K13–K16's fixture, and its tails are longer and
// steadier). A synthetic "render" is seeded noise
// written by `RampCAFWriter` under the name `IsolationCache` or `VoiceCache`
// gives it. Projects are ops on an untitled `ProjectDocument`, published under
// a fresh recipe key with a `ReverseResolution` whose `isolated` is
// <work-dir>/cache/isolated (so `voiced` is <work-dir>/cache/voiced). One line
// per row, `ok <ID> — <detail>` or `FAIL <ID> — <detail>`; no app is launched.
//
//  V1  pending: a voice with no render adds no tap and reads byte-identical to
//      no voice; with the isolated file present and no voiced file, the span
//      is isolation's (its amount, its render).
//  V2  a synthetic voiced render read sample for sample at the placement with
//      isolation 0.5 and its render also present (none applied on top),
//      ≤ 1e-7 alone and ≤ 1e-4 behind the noise reducer's lead.
//  V15 a ×2 clip's voice is a stage of its retimed chain (AU-145 as amended,
//      #387): no tapped request; the voice job over the padded window with the
//      clip's own frames as `sounding`, from the window's isolation when the
//      clip isolates; then the render, with Keep pitch off; the sounding
//      frames in the name.
//  V16 the pad is silent to the effect: Echo with an impulse 50 ms before the
//      clip's first frame leaves the clip's frames at 0, where the unsilenced
//      window echoes it into them; an impulse inside the clip echoes.
//  V3  no tapped request for amount 0, the kind pitch at 0 st, a time-scaled, ramped,
//      freeze or pending-reverse segment, or an isolating clip whose isolated
//      file is missing; once it is present, the request names it.
//  V4  the name changes with window, kind, amount, semitones, isolation and
//      reversal, and not with `pitch` on a kind that does not read it.
//  V5  `VoiceRenderer.render` equals the probe's reference engine (fx_common's
//      loop at 4,096-frame calls over the same input file and
//      `VoiceChain.units`, the same latency discard, then makeup) sample for
//      sample, for lofi, radio, robot, pitch +7 and hall; its length is
//      exactly the window.
//  V6  `writeInput` equals `dry + i·(iso − dry)` at i = 0.4.
//  V7  a mono source (the Rode recording) gives a mono file equal to the
//      reference's `(L+R)/2`.
//  V8  `Exporter.withRampAudio` builds only once the voice file exists, and a
//      voice that cannot render fails it `voiceFailed` naming the clip.
//  V9  room's and cathedral's tails after the burst differ by ≥ 3 s (the
//      presets are in effect from sample 0).
//  V10 sync: on the tone bursts, the 1 ms RMS envelope of the pitch +7 and
//      robot renders cross-correlated with the dry's peaks at lag 0 ± 1 ms;
//      each chain's `Report.latencyFrames` printed.
//  V11 `VoiceProps(kind: .deep, amount: 1, pitch: nil).dictionary["pitch"]` is
//      `NSNull`, and so is the section's kind-change value's.
//  V12 Clip ▸ Voice ▸ (spec §11 AU-158) and the popup are one list:
//      `AppDelegate().voiceMenu()` reads, header by header, as a literal list
//      here, each kind tagged with its index in `VoiceKind.allCases` and sent
//      to `setVoiceEffect:`, no header with an action, None −1 after a
//      separator; and each popup title is "<its header>: <its item>".
//  V13 the mark (`VoiceMenu.state`): checked when every target carries the
//      kind, dashed when some do, off otherwise; None likewise for no effect.
//  V14 what a choice writes (`VoiceMenu.targets`, `.ops`, `.kind(tag:)`): a
//      text clip is no target; Deep over {high, 0.4, 8}, {echo, 1} and none
//      gives {deep, 0.4}, {deep, 1}, {deep, 1} with no pitch; None clears
//      all three; tag 99 is a stranger and −1 is None.
//
// `measure` prints, instead of the rows, one line per kind: `measure <kind>
// m=<dB> dry=<LUFS> wet=<LUFS>`, where m is the dry recording's integrated
// loudness less the render's at a = 1 without makeup (the kind pitch at +7).
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

guard CommandLine.arguments.count >= 3 else {
    row("V1", false, "usage: voice_probe <work-dir> <Rode-usb-mic.m4a> [measure]")
    exit(0)
}
let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let rode = URL(fileURLWithPath: CommandLine.arguments[2])
let measuring = CommandLine.arguments.count > 3 && CommandLine.arguments[3] == "measure"
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
let cacheDir = work.appendingPathComponent("cache", isDirectory: true)
let isolatedDir = IsolationCache.directory(in: cacheDir)
let voicedDir = VoiceCache.directory(in: cacheDir)

func clearCaches() {
    for dir in [isolatedDir, voicedDir] {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
clearCaches()

// =========================================================================
// Fixtures

struct Noise {
    var state: UInt32
    mutating func next() -> Float {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Float(Int32(bitPattern: state)) / Float(Int32.max)
    }
}

func writeWAV(_ url: URL, _ channels: [[Float]]) -> String? {
    try? FileManager.default.removeItem(at: url)
    let frames = channels[0].count
    guard let format = AVAudioFormat(
        standardFormatWithSampleRate: Double(RATE), channels: AVAudioChannelCount(channels.count)),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
    else { return "no buffer for \(url.lastPathComponent)" }
    buffer.frameLength = AVAudioFrameCount(frames)
    for (c, data) in channels.enumerated() {
        data.withUnsafeBufferPointer { buffer.floatChannelData![c].update(from: $0.baseAddress!, count: frames) }
    }
    do {
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: RATE,
                AVNumberOfChannelsKey: channels.count, AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    } catch {
        return "\(url.lastPathComponent) would not write: \(error)"
    }
    return nil
}

func noise(seed: UInt32, frames: Int, amplitude: Float) -> [Float] {
    var n = Noise(state: seed)
    return (0..<frames).map { _ in amplitude * n.next() }
}

let dryA = work.appendingPathComponent("dry-a.wav")
let dryB = work.appendingPathComponent("dry-b.wav")
let tones = work.appendingPathComponent("tones.wav")
let burst = work.appendingPathComponent("burst.wav")
let toneChannel: [Float] = (0..<(4 * RATE)).map { (i: Int) -> Float in
    let phase: Float = 2 * Float.pi * 220 * Float(i) / Float(RATE)
    return (i / 4_800) % 2 == 0 ? 0.5 * sinf(phase) : 0
}
var burstChannel = [Float](repeating: 0, count: 10 * RATE)
do {
    var n = Noise(state: 11)
    for i in (RATE / 2)..<(RATE / 2 + RATE / 20) { burstChannel[i] = 0.866 * n.next() }
}
let written = [
    writeWAV(dryA, [noise(seed: 1, frames: 12 * RATE, amplitude: 0.4),
                    noise(seed: 3, frames: 12 * RATE, amplitude: 0.4)]),
    writeWAV(dryB, [noise(seed: 2, frames: 12 * RATE, amplitude: 0.3),
                    noise(seed: 4, frames: 12 * RATE, amplitude: 0.3)]),
    writeWAV(tones, [toneChannel, toneChannel]),
    writeWAV(burst, [burstChannel, burstChannel]),
].compactMap { $0 }
if !written.isEmpty {
    row("V1", false, "fixtures: " + written.joined(separator: "; "))
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
                row("V1", false, "setup: \(op.name) was refused: \(refusal.reason)")
                exit(0)
            }
        } catch {
            row("V1", false, "setup: \(op.name) is invalid: \(error)")
            exit(0)
        }
    }
    document.performGroupedEdit(name, ops)
}

struct Fixture {
    let document: ProjectDocument
    let key: Int
    let clip: UInt32
    let reverse: ReverseResolution
    var project: ReelProject { document.project }
    var segment: PlanSegment? {
        project.plan?.audioTracks.flatMap(\.segments).first { $0.clip == clip }
    }
    var dsp: AudioDSPParameters { AudioDSPParameters(snapshot: project.snapshot) }
    var urls: [UInt32: URL] { document.mediaURLs() }
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
/// 2.5 s, with `voice` and `isolation`; `noiseClip` adds `dryB` at 14 s with
/// noise reduction 0.5 on the same track.
func fixture(
    voice: VoiceProps?, isolation: Double = 0, noiseClip: Bool = false, pending: Bool = false
) -> Fixture? {
    let document = ProjectDocument()
    guard let clip = place(document, dryA, seconds: 12, at: SEC) else { return nil }
    edit(document, "Trim", [.trimStart(clip: clip, to: 3 * SEC + SEC / 2)])
    if isolation > 0 || voice != nil {
        edit(
            document, "Voice",
            [.setAudio(
                clips: [clip],
                patch: AudioPatch(
                    isolation: isolation > 0 ? isolation : nil,
                    voice: voice.map { .some($0) }))])
    }
    if noiseClip, let other = place(document, dryB, seconds: 12, at: 14 * SEC) {
        edit(
            document, "NR", [.setAudio(clips: [other], patch: AudioPatch(noiseReduction: 0.5))])
    }
    let key = RecipeSource.shared.register()
    RecipeSource.shared.set(document.project, for: key)
    AudioDSPSource.shared.publish(AudioDSPParameters(snapshot: document.project.snapshot), for: key)
    let reverse = ReverseResolution(ready: [:], pending: pending ? [clip] : [], isolated: isolatedDir)
    ReverseSource.shared.publish(reverse, project: document.project, for: key)
    return Fixture(document: document, key: key, clip: clip, reverse: reverse)
}

func build(_ f: Fixture) -> BuiltComposition? {
    guard let plan = f.project.plan else { return nil }
    return try? CompositionBuilder.build(
        plan: plan, planJSON: f.project.planJSON, urls: f.urls, recipeKey: f.key,
        metering: false)
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

/// Seeded stereo noise of `frames` frames written as a float CAF at `url`.
func writeSynthetic(_ url: URL, frames: Int, seed: UInt32) -> [[Float]]? {
    var n = Noise(state: seed)
    var render: [[Float]] = [[], []]
    var interleaved = [Float](repeating: 0, count: 2 * frames)
    for i in 0..<frames {
        for c in 0..<2 {
            let v = 0.5 * n.next()
            render[c].append(v)
            interleaved[2 * i + c] = v
        }
    }
    guard let writer = try? RampCAFWriter(url: url, channels: 2) else { return nil }
    do {
        try writer.write(interleaved, frames: frames)
        try writer.close()
    } catch { return nil }
    return render
}

/// A synthetic isolated render of `f`'s window, where `IsolationCache` names it.
func writeIsolated(_ f: Fixture, seed: UInt32 = 7) -> (render: [[Float]], url: URL)? {
    guard let s = f.segment, let request = IsolationCache.request(
        for: s, dsp: f.dsp, urls: f.urls, reverse: f.reverse)
    else { return nil }
    let window = IsolationCache.window(of: s)
    guard let render = writeSynthetic(
        request.destination, frames: Int(window.endFrame - window.firstFrame), seed: seed)
    else { return nil }
    return (render, request.destination)
}

/// A synthetic voiced render of `f`'s window, where `VoiceCache` names it.
func writeVoiced(_ f: Fixture, seed: UInt32 = 9) -> (render: [[Float]], url: URL)? {
    guard let s = f.segment, let request = VoiceCache.request(
        for: s, dsp: f.dsp, urls: f.urls, reverse: f.reverse)
    else { return nil }
    let window = IsolationCache.window(of: s)
    guard let render = writeSynthetic(
        request.destination, frames: Int(window.endFrame - window.firstFrame), seed: seed)
    else { return nil }
    return (render, request.destination)
}

/// The span `[first, end)` in composition frames, and the wet index offset,
/// from the decision's arithmetic rather than read from the app.
func expectedSpan(_ s: PlanSegment) -> (Int, Int, Int) {
    let window = IsolationCache.window(of: s)
    func r(_ t: Ticks) -> Int {
        let a = 2 * t + 12
        return Int(a >= 0 ? a / 25 : -((-a + 24) / 25))
    }
    return (r(s.start), r(s.start + s.duration), r(s.sourceIn - s.start) - Int(window.firstFrame))
}

func readCAF(_ url: URL) -> [[Float]]? {
    guard let audio = IsolatedAudio(contentsOf: url) else { return nil }
    return (0..<audio.channels).map {
        Array(UnsafeBufferPointer(start: audio.samples(channel: $0), count: audio.frames))
    }
}

/// `source`'s frames [from, to) on each of its channels (1 or 2).
func readSource(_ url: URL, from: Int64, to: Int64, channels: Int) -> [[Float]]? {
    let asset = AVURLAsset(url: url)
    guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .audio),
        let reader = try? RampSourceReader(asset: asset, track: track, channels: channels, from: from)
    else { return nil }
    guard (try? reader.fill(through: to)) != nil else { return nil }
    return (0..<channels).map { c in (from..<to).map { reader.sample($0, channel: c) } }
}

func job(_ source: URL, _ settings: VoiceSettings, _ window: IsolationWindow, _ name: String,
    isolated: URL? = nil, isolation: Double = 0) -> VoiceRenderer.Job
{
    let destination = work.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: destination)
    return VoiceRenderer.Job(
        source: source,
        job: VoiceJob(window: window, settings: settings, isolated: isolated, isolation: isolation),
        destination: destination)
}

func settings(_ kind: VoiceKind, pitch: Double? = nil, amount: Double = 1) -> VoiceSettings {
    VoiceChain.settings(VoiceProps(kind: kind, amount: amount, pitch: pitch))
}

/// The reference engine (fx_common's loop): the input file through
/// `VoiceChain.units` at 48 kHz stereo, 4,096-frame calls, the summed
/// latency discarded, the window's length kept, mono as (L+R)/2, makeup.
func reference(input: URL, settings: VoiceSettings, frames: Int, channels: Int) throws -> [[Float]] {
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    let engine = AVAudioEngine()
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    let units = try VoiceChain.units(for: settings)
    let player = AVAudioPlayerNode()
    engine.attach(player)
    units.forEach { engine.attach($0) }
    var previous: AVAudioNode = player
    for unit in units {
        engine.connect(previous, to: unit, format: format)
        previous = unit
    }
    engine.connect(previous, to: engine.mainMixerNode, format: format)
    let file = try AVAudioFile(forReading: input)
    player.scheduleFile(file, at: nil)
    try engine.start()
    let latency = units.reduce(0) { sum, unit in
        sum + Int((((unit as? AVAudioUnit)?.auAudioUnit.latency ?? 0) * 48_000).rounded())
    }
    player.play()
    let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
    var l: [Float] = []
    var r: [Float] = []
    while l.count < latency + frames {
        _ = try engine.renderOffline(4096, to: buffer)
        let got = Int(buffer.frameLength)
        if got == 0 { break }
        l.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: got))
        r.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![1], count: got))
    }
    player.stop()
    engine.stop()
    let gain = VoiceChain.makeup(settings)
    let kl = Array(l[latency..<(latency + frames)])
    let kr = Array(r[latency..<(latency + frames)])
    if channels == 1 { return [zip(kl, kr).map { ($0 + $1) * 0.5 * gain }] }
    return [kl.map { $0 * gain }, kr.map { $0 * gain }]
}

func worst(_ a: [[Float]], _ b: [[Float]]) -> Float {
    var m: Float = 0
    for c in 0..<min(a.count, b.count) {
        for i in 0..<min(a[c].count, b[c].count) { m = max(m, abs(a[c][i] - b[c][i])) }
    }
    return m
}

// =========================================================================
// --measure: each kind's makeup on the owner's recording

if measuring {
    guard FileManager.default.fileExists(atPath: rode.path),
        let source = try? RampAudioCache.renderSource(for: rode),
        let total = try? AVAudioFile(forReading: source).length,
        let dry = readSource(source, from: 0, to: total, channels: 1)
    else {
        print("measure FAIL — \(rode.path) cannot be read")
        exit(0)
    }
    /// Read as I3's export reads it — the fader at ×4, the mono sound in both
    /// channels — since the gate makes integrated loudness non-linear near
    /// −70 LUFS, where the recording's own pauses sit.
    func lufs(_ x: [Float]) -> Double? {
        guard let meter = LoudnessMeter(sampleRate: 48_000, channelCount: 2) else { return nil }
        var both = [Float](repeating: 0, count: 2 * x.count)
        for i in x.indices {
            both[2 * i] = 4 * x[i]
            both[2 * i + 1] = 4 * x[i]
        }
        both.withUnsafeBufferPointer { meter.feed($0.baseAddress!, frames: x.count) }
        return meter.finish().integratedLUFS
    }
    let dryLUFS = lufs(dry[0]) ?? .nan
    let window = IsolationWindow(firstFrame: 0, endFrame: total)
    for kind in VoiceKind.allCases {
        let s = settings(kind, pitch: kind == .pitch ? 7 : nil)
        do {
            let j = job(source, s, window, "measure-\(kind.rawValue).caf")
            _ = try VoiceRenderer.render(j, cancelled: { false })
            guard let wet = readCAF(j.destination), let wetLUFS = lufs(wet[0]) else {
                print("measure \(kind.rawValue) FAIL — no reading")
                continue
            }
            let m = dryLUFS - (wetLUFS - VoiceChain.makeupDb(kind))
            print(String(format: "measure %@ m=%.2f dry=%.2f wet=%.2f (with the table's %.2f)",
                kind.rawValue, m, dryLUFS, wetLUFS, VoiceChain.makeupDb(kind)))
        } catch {
            print("measure \(kind.rawValue) FAIL — \(error.localizedDescription)")
        }
        fflush(stdout)
    }
    exit(0)
}

// =========================================================================
// V1 — pending plays without the effect; isolation's span when it is ready

do {
    clearCaches()
    let hall = VoiceProps(kind: .hall)
    guard let off = fixture(voice: nil), let on = fixture(voice: hall),
        let builtOff = build(off), let builtOn = build(on),
        let readOff = exportRead(builtOff), let readOn = exportRead(builtOn)
    else {
        row("V1", false, "a fixture did not build or read")
        exit(0)
    }
    let taps = builtOn.audioMix.inputParameters.filter { $0.audioTapProcessor != nil }.count
    let same = readOff.left == readOn.left && readOff.right == readOn.right
    var spanText = "no fixture"
    var spanOK = false
    if let both = fixture(voice: hall, isolation: 0.6), let s = both.segment,
        let iso = writeIsolated(both), let plan = both.project.plan
    {
        let isolated = CompositionBuilder.isolatedAudio(
            plan: plan, urls: both.urls, reverse: both.reverse, dsp: both.dsp)
        let voiced = CompositionBuilder.voicedAudio(
            plan: plan, urls: both.urls, reverse: both.reverse, dsp: both.dsp)
        let track = AudioIsolationTrack(
            segments: [s], shift: .none, dsp: both.dsp, renders: isolated, voiced: voiced)
        let span = track.spans.first
        let isoAudio = IsolatedAudioStore.shared.audio(at: iso.url)
        spanOK = track.spans.count == 1 && voiced.isEmpty && span?.amount == Float(0.6)
            && span?.audio === isoAudio
        spanText = "\(track.spans.count) span(s), voiced renders \(voiced.count), amount "
            + "\(span.map { String($0.amount) } ?? "none"), isolation's render: "
            + "\(span?.audio === isoAudio)"
    }
    row("V1", taps == 0 && same && !readOn.left.isEmpty && spanOK,
        "hall with no render: \(taps) taps over \(builtOn.audioMix.inputParameters.count) "
            + "tracks; read byte-identical to no voice: \(same) (\(readOn.left.count) frames); "
            + "isolation 0.6 ready, voice pending: \(spanText)")
}

// =========================================================================
// V2 — the voiced render at the placement, isolation not applied on top

func v2(noiseClip: Bool, bound: Float) -> (Bool, String) {
    clearCaches()
    guard let f = fixture(voice: VoiceProps(kind: .echo), isolation: 0.5, noiseClip: noiseClip),
        let s = f.segment, writeIsolated(f) != nil, let voiced = writeVoiced(f),
        let built = build(f), let read = exportRead(built)
    else { return (false, "the fixture did not build, write or read") }
    let (start, end, offset) = expectedSpan(s)
    var worst: Float = 0
    var counted = 0
    for i in start..<min(end, read.left.count) {
        let w = i + offset
        guard w >= 0, w < voiced.render[0].count else { continue }
        worst = max(
            worst, abs(read.left[i] - voiced.render[0][w]), abs(read.right[i] - voiced.render[1][w]))
        counted += 1
    }
    let ok = worst <= bound && counted >= end - start - 1 && counted > 0
    return (ok, "\(noiseClip ? "with" : "without") noise reduction on the track: \(counted) "
        + "frames, worst |out − voiced| \(worst) (bound \(bound))")
}

do {
    let (alone, aloneDetail) = v2(noiseClip: false, bound: 1e-7)
    let (led, ledDetail) = v2(noiseClip: true, bound: 1e-4)
    row("V2", alone && led, "isolation 0.5 with its render present; " + aloneDetail + "; " + ledDetail)
}

// =========================================================================
// V3 — which segments are voiced, and the isolation gate

do {
    clearCaches()
    var parts: [String] = []
    var ok = true
    func expect(_ name: String, _ got: RampAudioRequest?, _ wanted: Bool) {
        ok = ok && (got != nil) == wanted
        parts.append("\(name): \(got == nil ? "no request" : "a request")")
    }
    if let zero = fixture(voice: VoiceProps(kind: .hall, amount: 0)), let s = zero.segment {
        expect("amount 0", VoiceCache.request(
            for: s, dsp: zero.dsp, urls: zero.urls, reverse: zero.reverse), false)
    } else { ok = false; parts.append("amount 0: no fixture") }
    if let flat = fixture(voice: VoiceProps(kind: .pitch, pitch: 0)), let s = flat.segment {
        expect("pitch 0 st", VoiceCache.request(
            for: s, dsp: flat.dsp, urls: flat.urls, reverse: flat.reverse), false)
    } else { ok = false; parts.append("pitch 0 st: no fixture") }
    if let f = fixture(voice: VoiceProps(kind: .hall)), let media = f.segment?.media {
        func segment(_ extra: String, duration: Ticks = 600_000, sourceDuration: Ticks = 600_000)
            -> PlanSegment?
        {
            ReelJSON.decode(
                PlanSegment.self,
                from: "{\"clip\": \(f.clip), \"media\": \(media), \"source_in\": 0, "
                    + "\"source_duration\": \(sourceDuration), \"start\": 0, "
                    + "\"duration\": \(duration)\(extra)}")
        }
        let pendingReverse = ReverseResolution(ready: [:], pending: [f.clip], isolated: isolatedDir)
        let cases: [(String, PlanSegment?, ReverseResolution, Bool)] = [
            ("plain", segment(""), f.reverse, true),
            ("time-scaled ×2", segment(", \"pitch\": \"spectral\"", sourceDuration: 1_200_000),
             f.reverse, false),
            ("ramped", segment(
                ", \"ramp\": {\"keep_pitch\": false, \"glide\": [], "
                    + "\"map\": [[0, 0], [600000, 1200000]], \"constant\": true}",
                sourceDuration: 1_200_000), f.reverse, false),
            ("freeze", segment("", duration: 1_200_000, sourceDuration: 20_000), f.reverse, false),
            ("pending reverse", segment(""), pendingReverse, false),
        ]
        for (name, s, resolution, wanted) in cases {
            guard let s else { ok = false; parts.append("\(name): did not decode"); continue }
            expect(name, VoiceCache.request(
                for: s, dsp: f.dsp, urls: f.urls, reverse: resolution), wanted)
        }
    } else { ok = false; parts.append("segments: no fixture") }
    if let both = fixture(voice: VoiceProps(kind: .hall), isolation: 1), let s = both.segment {
        expect("isolated file missing", VoiceCache.request(
            for: s, dsp: both.dsp, urls: both.urls, reverse: both.reverse), false)
        let iso = writeIsolated(both)
        let got = VoiceCache.request(for: s, dsp: both.dsp, urls: both.urls, reverse: both.reverse)
        var named = false
        if case .voice(let j)? = got?.job { named = j.isolated == iso?.url && j.isolation == 1 }
        ok = ok && named
        parts.append("isolated file present: \(got == nil ? "no request" : "a request"), "
            + "naming it: \(named)")
    } else { ok = false; parts.append("isolation: no fixture") }
    row("V3", ok, parts.joined(separator: ", "))
}

// =========================================================================
// V4 — the name

do {
    let w1 = IsolationWindow(firstFrame: 0, endFrame: 48_000)
    let w2 = IsolationWindow(firstFrame: 0, endFrame: 48_001)
    let iso = work.appendingPathComponent("1-0000000000000001.caf")
    func name(_ window: IsolationWindow = w1, _ s: VoiceSettings = settings(.high),
        isolated: URL? = nil, isolation: Double = 0, reversed: Bool = false) -> String?
    {
        VoiceCache.name(
            media: 1, mediaFile: dryA, reversed: reversed,
            job: VoiceJob(window: window, settings: s, isolated: isolated, isolation: isolation))
    }
    let base = name()
    let variants: [(String, String?)] = [
        ("window", name(w2)),
        ("kind", name(w1, settings(.deep))),
        ("amount", name(w1, settings(.high, amount: 0.5))),
        ("semitones", name(w1, settings(.high, pitch: 7))),
        ("isolation", name(w1, isolated: iso, isolation: 0.5)),
        ("reversal", name(reversed: true)),
    ]
    let hallPlain = name(w1, settings(.hall))
    let hallPitched = name(w1, settings(.hall, pitch: 7))
    let differs = variants.allSatisfy { $0.1 != nil && $0.1 != base }
    let ok = base != nil && differs && hallPlain != nil && hallPlain == hallPitched
    row("V4", ok,
        "base \(base ?? "nil"); " + variants.map { "\($0.0) \($0.1 == base ? "same" : "differs")" }
            .joined(separator: ", ")
            + "; hall with and without pitch 7: \(hallPlain == hallPitched ? "same" : "differs")")
}

// =========================================================================
// V5 — the renderer against the reference engine

do {
    let window = IsolationWindow(firstFrame: Int64(RATE), endFrame: 4 * Int64(RATE))
    let frames = Int(window.endFrame - window.firstFrame)
    var parts: [String] = []
    var ok = true
    let cases: [(String, VoiceSettings)] = [
        ("lofi", settings(.lofi)), ("radio", settings(.radio)), ("robot", settings(.robot)),
        ("pitch +7", settings(.pitch, pitch: 7)), ("hall", settings(.hall)),
    ]
    for (label, s) in cases {
        do {
            let j = job(dryA, s, window, "v5-\(s.kind.rawValue).caf")
            let report = try VoiceRenderer.render(j, cancelled: { false })
            let input = try VoiceRenderer.writeInput(
                job(dryA, s, window, "v5-ref-\(s.kind.rawValue).caf"), cancelled: { false })
            let want = try reference(input: input, settings: s, frames: frames, channels: 2)
            guard let got = readCAF(j.destination) else {
                ok = false
                parts.append("\(label): did not read back")
                continue
            }
            let w = worst(got, want)
            let length = got[0].count
            ok = ok && w == 0 && length == frames && got.count == 2
            parts.append("\(label): \(length) frames (want \(frames)), worst |Δ| \(w), latency "
                + "\(report.latencyFrames)")
        } catch {
            ok = false
            parts.append("\(label): \(error.localizedDescription)")
        }
    }
    row("V5", ok, parts.joined(separator: "; ") + " (bound 0)")
}

// =========================================================================
// V6 — the input crossfades the isolated render

do {
    let window = IsolationWindow(firstFrame: 2 * Int64(RATE), endFrame: 5 * Int64(RATE))
    let frames = Int(window.endFrame - window.firstFrame)
    let isoURL = work.appendingPathComponent("v6-isolated.caf")
    let i = 0.4
    if let iso = writeSynthetic(isoURL, frames: frames, seed: 21),
        let dry = readSource(dryA, from: window.firstFrame, to: window.endFrame, channels: 2),
        let input = try? VoiceRenderer.writeInput(
            job(dryA, settings(.hall), window, "v6.caf", isolated: isoURL, isolation: i),
            cancelled: { false }),
        let got = readCAF(input)
    {
        let a = Float(i)
        let want = (0..<2).map { c in
            (0..<frames).map { k -> Float in
                var x = dry[c][k]
                x += a * (iso[c][k] - x)
                return x
            }
        }
        let w = worst(got, want)
        row("V6", w <= 1e-7 && got[0].count == frames,
            "isolation \(i): \(got[0].count) frames (want \(frames)), worst |input − (dry + "
                + "i·(iso − dry))| \(w) (bound 1e-7)")
    } else {
        row("V6", false, "the input was not written or read")
    }
}

// =========================================================================
// V7 — a mono source

do {
    let window = IsolationWindow(firstFrame: 10 * Int64(RATE), endFrame: 13 * Int64(RATE))
    let frames = Int(window.endFrame - window.firstFrame)
    do {
        let source = try RampAudioCache.renderSource(for: rode)
        let s = settings(.hall)
        let j = job(source, s, window, "v7.caf")
        _ = try VoiceRenderer.render(j, cancelled: { false })
        let input = try VoiceRenderer.writeInput(job(source, s, window, "v7-ref.caf"),
            cancelled: { false })
        let want = try reference(input: input, settings: s, frames: frames, channels: 1)
        if let got = readCAF(j.destination) {
            let w = worst(got, want)
            row("V7", got.count == 1 && got[0].count == frames && w == 0,
                "hall on the Rode recording: \(got.count) channel(s), \(got[0].count) frames "
                    + "(want 1, \(frames)), worst |Δ| against (L+R)/2 \(w) (bound 0)")
        } else {
            row("V7", false, "the render did not read back")
        }
    } catch {
        row("V7", false, error.localizedDescription)
    }
}

// =========================================================================
// V8 — the export waits, and a failed voice fails it

func exportFixture(_ media: URL, seconds: Double, voice: VoiceProps, folder: String)
    -> (ProjectDocument, Int, UInt32, ReverseResolution)?
{
    let document = ProjectDocument()
    guard let clip = place(document, media, seconds: seconds, at: 0) else { return nil }
    edit(document, "Voice", [.trimEnd(clip: clip, to: 3 * SEC),
        .setAudio(clips: [clip], patch: AudioPatch(voice: .some(voice)))])
    let cache = work.appendingPathComponent(folder, isDirectory: true)
        .appendingPathComponent("cache", isDirectory: true)
    try? FileManager.default.removeItem(at: cache)
    let key = RecipeSource.shared.register()
    RecipeSource.shared.set(document.project, for: key)
    AudioDSPSource.shared.publish(AudioDSPParameters(snapshot: document.project.snapshot), for: key)
    let resolution = ReverseResolution(
        ready: [:], pending: [], isolated: IsolationCache.directory(in: cache))
    ReverseSource.shared.publish(resolution, project: document.project, for: key)
    return (document, key, clip, resolution)
}

do {
    var parts: [String] = []
    var ok = false
    if FileManager.default.fileExists(atPath: rode.path),
        let (document, key, _, resolution) = exportFixture(
            rode, seconds: 30, voice: VoiceProps(kind: .echo), folder: "v8"),
        let plan = document.project.plan,
        let settings = try? ReelExport.settings(document.project, preset: "audio_wav")
    {
        let urls = document.mediaURLs()
        let requests = VoiceCache.requests(
            plan: plan, dsp: AudioDSPParameters(snapshot: document.project.snapshot), urls: urls,
            reverse: resolution)
        var existed: [Bool] = []
        do {
            try Exporter.withRampAudio(
                plan: plan, urls: urls, settings: settings, key: key, cancelled: { false }
            ) {
                existed = requests.map { FileManager.default.fileExists(atPath: $0.destination.path) }
            }
            ok = !requests.isEmpty && existed.allSatisfy { $0 }
            parts.append("\(requests.count) voice request(s); at build each file existed: \(existed)")
        } catch {
            parts.append("withRampAudio threw: \(error.localizedDescription)")
        }
        RampAudioRenders.shared.release(owner: key)
    } else {
        parts.append("the waiting fixture did not build")
    }
    let text = work.appendingPathComponent("not-audio.m4a")
    try? "not audio".write(to: text, atomically: true, encoding: .utf8)
    var failed = false
    if let (document, key, clip, _) = exportFixture(
        text, seconds: 30, voice: VoiceProps(kind: .echo), folder: "v8-fail"),
        let plan = document.project.plan,
        let settings = try? ReelExport.settings(document.project, preset: "audio_wav")
    {
        do {
            try Exporter.withRampAudio(
                plan: plan, urls: document.mediaURLs(), settings: settings, key: key,
                cancelled: { false }) {}
            parts.append("an unreadable source: built")
        } catch Exporter.ExportError.voiceFailed(let named, let message) {
            failed = named == clip
            parts.append("an unreadable source: voiceFailed(clip \(named), \(message))")
        } catch {
            parts.append("an unreadable source: \(error.localizedDescription)")
        }
        RampAudioRenders.shared.release(owner: key)
    } else {
        parts.append("the failing fixture did not build")
    }
    row("V8", ok && failed, parts.joined(separator: "; "))
}

// =========================================================================
// V9 — the reverb presets from sample 0

/// Seconds from the burst's end until the 10 ms RMS stays under −60 dBFS.
func tail(_ x: [[Float]]) -> Double {
    let block = RATE / 100
    var last = -1
    for b in 0..<(x[0].count / block) {
        var power: Float = 0
        for c in 0..<x.count {
            var s: Float = 0
            x[c].withUnsafeBufferPointer {
                vDSP_svesq($0.baseAddress! + b * block, 1, &s, vDSP_Length(block))
            }
            power = max(power, s / Float(block))
        }
        if 10 * log10(max(Double(power), 1e-30)) > -60 { last = b }
    }
    return Double(last + 1) / 100 - 0.55
}

do {
    let window = IsolationWindow(firstFrame: 0, endFrame: 10 * Int64(RATE))
    var tails: [VoiceKind: Double] = [:]
    var parts: [String] = []
    for kind in [VoiceKind.room, .cathedral] {
        do {
            let j = job(burst, settings(kind), window, "v9-\(kind.rawValue).caf")
            _ = try VoiceRenderer.render(j, cancelled: { false })
            if let got = readCAF(j.destination) { tails[kind] = tail(got) }
        } catch {
            parts.append("\(kind.rawValue): \(error.localizedDescription)")
        }
    }
    let room = tails[.room] ?? .nan
    let cathedral = tails[.cathedral] ?? .nan
    row("V9", cathedral - room >= 3,
        String(format: "tails after a 50 ms burst: room %.2f s, cathedral %.2f s, apart %.2f s "
            + "(≥ 3)", room, cathedral, cathedral - room)
            + (parts.isEmpty ? "" : "; " + parts.joined(separator: "; ")))
}

// =========================================================================
// V10 — sync

/// The 1 ms RMS envelope of channel 0, mean removed.
func envelope(_ x: [Float]) -> [Float] {
    let block = RATE / 1000
    var e = (0..<(x.count / block)).map { b -> Float in
        var s: Float = 0
        x.withUnsafeBufferPointer { vDSP_svesq($0.baseAddress! + b * block, 1, &s, vDSP_Length(block)) }
        return sqrtf(s / Float(block))
    }
    let mean = e.reduce(0, +) / Float(max(e.count, 1))
    for i in e.indices { e[i] -= mean }
    return e
}

do {
    let window = IsolationWindow(firstFrame: 0, endFrame: 4 * Int64(RATE))
    let dry = envelope(toneChannel)
    var ok = true
    var parts: [String] = []
    for (label, s) in [("pitch +7", settings(.pitch, pitch: 7)), ("robot", settings(.robot))] {
        do {
            let j = job(tones, s, window, "v10-\(s.kind.rawValue).caf")
            let report = try VoiceRenderer.render(j, cancelled: { false })
            guard let got = readCAF(j.destination) else {
                ok = false
                parts.append("\(label): did not read back")
                continue
            }
            let wet = envelope(got[0])
            let n = min(dry.count, wet.count)
            var best = (lag: 0, value: -Float.infinity)
            for lag in -50...50 {
                var sum: Float = 0
                for i in 50..<(n - 50) { sum += dry[i] * wet[i + lag] }
                if sum > best.value { best = (lag, sum) }
            }
            ok = ok && abs(best.lag) <= 1
            parts.append("\(label): envelope peak at \(best.lag) ms (want 0 ± 1), latency "
                + "\(report.latencyFrames) frames")
        } catch {
            ok = false
            parts.append("\(label): \(error.localizedDescription)")
        }
    }
    row("V10", ok, parts.joined(separator: "; "))
}

// =========================================================================
// V11 — a kind change sends pitch null

do {
    let alone = VoiceProps(kind: .deep, amount: 1, pitch: nil).dictionary["pitch"]
    let deepIndex = (AudioPane.voiceKinds.firstIndex(of: .deep) ?? -1) + 1
    let chosen = AudioPane.voiceChoice(
        deepIndex, current: VoiceProps(kind: .high, amount: 0.6, pitch: 8))
    let sent = chosen?.dictionary["pitch"]
    let none = AudioPane.voiceChoice(0, current: chosen)
    let ok = alone is NSNull && sent is NSNull && chosen?.kind == .deep && chosen?.amount == 0.6
        && none == nil
    row("V11", ok,
        "deep's dictionary pitch: \(String(describing: alone)); the popup's deep over "
            + "{high, 0.6, 8}: kind \(chosen?.kind.rawValue ?? "nil"), amount "
            + "\(chosen?.amount ?? -1), pitch \(String(describing: sent)); None: "
            + "\(none == nil ? "null" : "a voice")")
}

// =========================================================================
// V12–V14 — Clip ▸ Voice ▸ (spec §11 AU-158)

/// Three sound clips (dryA at 0, dryB at 13 s, the tones at 26 s) and a text
/// clip at 40 s on the first track.
func menuFixture() -> (document: ProjectDocument, sound: [UInt32], text: UInt32)? {
    let document = ProjectDocument()
    guard let a = place(document, dryA, seconds: 12, at: 0),
        let b = place(document, dryB, seconds: 12, at: 13 * SEC),
        let c = place(document, tones, seconds: 4, at: 26 * SEC)
    else { return nil }
    let track = document.project.snapshot.tracks[0].id
    edit(document, "Text", [.addTextClip(track: track, at: 40 * SEC, duration: 2 * SEC)])
    guard let text = document.project.snapshot.clips.first(where: { $0.start == 40 * SEC })?.id
    else { return nil }
    return (document, [a, b, c], text)
}

func setVoices(_ document: ProjectDocument, _ voices: [(UInt32, VoiceProps?)]) {
    edit(
        document, "Voices",
        voices.map { .setAudio(clips: [$0.0], patch: AudioPatch(voice: .some($0.1))) })
}

func stateWord(_ state: NSControl.StateValue) -> String {
    state == .on ? "on" : (state == .mixed ? "mixed" : "off")
}

do {
    let menu = AppDelegate().voiceMenu()
    let action = NSStringFromSelector(#selector(EditorViewController.setVoiceEffect(_:)))
    var read: [String] = []
    var header = ""
    var popup: [String] = []
    var wired = true
    for item in menu.items {
        if item.isSeparatorItem {
            read.append("—")
        } else if item.action == nil {
            header = item.title
            read.append("[\(item.title)]")
            wired = wired && item.submenu == nil
        } else {
            read.append("\(item.title)#\(item.tag)")
            wired = wired && item.action.map { NSStringFromSelector($0) } == action
            if VoiceKind.allCases.indices.contains(item.tag) { popup.append("\(header): \(item.title)") }
        }
    }
    let want = [
        "[Voice]", "Pitch#0", "High#1", "Deep#2", "Robot#3",
        "[Tone]", "Bass#4", "Treble#5", "Bright#6", "Telephone#7", "Radio#8",
        "[Character]", "Lo-Fi#9", "Distorted#10",
        "[Space]", "Echo#11", "Room#12", "Hall#13", "Plate#14", "Cathedral#15",
        "—", "None#-1",
    ]
    let titles = AudioPane.voiceKinds.map(\.title)
    let kinds = VoiceKind.allCases.map(\.rawValue) == [
        "pitch", "high", "deep", "robot", "bass", "treble", "bright", "telephone", "radio", "lofi",
        "distorted", "echo", "room", "hall", "plate", "cathedral",
    ]
    row("V12", menu.title == "Voice" && read == want && wired && kinds && popup == titles,
        "Clip ▸ \(menu.title) ▸ reads \(read.joined(separator: " ")); every item to "
            + "setVoiceEffect: and no header with an action: \(wired); the popup's titles are "
            + "\"<header>: <item>\": \(popup == titles) (\(titles.first ?? "") … "
            + "\(titles.last ?? ""))")
}

do {
    guard let f = menuFixture() else {
        row("V13", false, "the fixture did not build")
        exit(0)
    }
    func states(_ kinds: [VoiceKind?], selected: [UInt32]) -> [String] {
        let snapshot = f.document.project.snapshot
        let targets = VoiceMenu.targets(
            snapshot.clips.filter { selected.contains($0.id) }, in: snapshot)
        return kinds.map { stateWord(VoiceMenu.state($0, targets: targets)) }
    }
    let all = f.sound + [f.text]
    let radio = VoiceProps(kind: .radio)
    setVoices(f.document, f.sound.map { ($0, radio) })
    let same = states([.radio, .echo, nil], selected: all)
    setVoices(f.document, [(f.sound[1], VoiceProps(kind: .echo)), (f.sound[2], nil)])
    let split = states([.radio, .echo, nil, .hall], selected: all)
    setVoices(f.document, f.sound.map { ($0, nil) })
    let none = states([nil] + VoiceKind.allCases.map { Optional($0) }, selected: all)
    let noTarget = states([.radio, nil], selected: [f.text])
    let ok = same == ["on", "off", "off"] && split == ["mixed", "mixed", "mixed", "off"]
        && none == ["on"] + Array(repeating: "off", count: 16) && noTarget == ["off", "off"]
    row("V13", ok,
        "all radio: Radio/Echo/None \(same) (want on, off, off); radio + echo + none: "
            + "Radio/Echo/None/Hall \(split) (want mixed ×3, off); no effect: None and the "
            + "sixteen \(none.prefix(3))… (want on, then off); only a text clip: Radio/None "
            + "\(noTarget) (want off, off)")
}

do {
    guard let f = menuFixture() else {
        row("V14", false, "the fixture did not build")
        exit(0)
    }
    setVoices(
        f.document,
        [(f.sound[0], VoiceProps(kind: .high, amount: 0.4, pitch: 8)),
         (f.sound[1], VoiceProps(kind: .echo))])
    func targets() -> [ClipSnapshot] {
        let snapshot = f.document.project.snapshot
        return VoiceMenu.targets(snapshot.clips, in: snapshot)
    }
    func voices() -> [String] {
        let snapshot = f.document.project.snapshot
        return f.sound.map { id in
            guard let voice = snapshot.clips.first(where: { $0.id == id })?.audioProps.voice
            else { return "none" }
            return "\(voice.kind.rawValue) \(voice.amount) "
                + (voice.pitch.map { "pitch \($0)" } ?? "no pitch")
        }
    }
    let chosen = targets().map(\.id)
    guard chosen == f.sound else {
        // A stranger target's `set_audio` is invalid input, which `edit` exits on.
        row("V14", false, "targets of the three sound clips and a text clip: \(chosen) (want \(f.sound))")
        exit(0)
    }
    let deepOps = VoiceMenu.ops(.deep, targets: targets())
    edit(f.document, "Voice Effect", deepOps)
    let deep = voices()
    let noneOps = VoiceMenu.ops(nil, targets: targets())
    edit(f.document, "Voice Effect", noneOps)
    let cleared = voices()
    let empty = VoiceMenu.ops(.deep, targets: []).count + VoiceMenu.ops(nil, targets: []).count
    let stranger = VoiceMenu.kind(tag: 99) == nil
    let noneTag = VoiceMenu.kind(tag: -1).map { $0 == nil } ?? false
    let deepTag = VoiceMenu.kind(tag: 2).map { $0 == .deep } ?? false
    let ok = chosen == f.sound && deep == ["deep 0.4 no pitch", "deep 1.0 no pitch", "deep 1.0 no pitch"]
        && cleared == ["none", "none", "none"] && deepOps.count == 3 && noneOps.count == 1
        && empty == 0 && stranger && noneTag && deepTag
    row("V14", ok,
        "targets of the three sound clips and a text clip: \(chosen) (want \(f.sound)); Deep "
            + "over {high, 0.4, 8}, {echo, 1}, none: \(deep) in \(deepOps.count) ops; None: "
            + "\(cleared) in \(noneOps.count) op; no target: \(empty) ops; tag 99 a stranger: "
            + "\(stranger), −1 None: \(noneTag), 2 deep: \(deepTag)")
}

// =========================================================================
// V15 — a retimed clip's voice is a stage of its chain (AU-145 as amended, #387)

do {
    clearCaches()
    var parts: [String] = []
    var ok = true
    let rampDir = RampAudioCache.directory(
        in: isolatedDir.deletingLastPathComponent())
    /// The fixture's clip at ×2, and its chain.
    func chain(isolation: Double, keepPitch: Bool)
        -> (RetimedSound.Chain, PlanSegment, RampAudioRequest?)?
    {
        guard let f = fixture(voice: VoiceProps(kind: .hall), isolation: isolation) else {
            return nil
        }
        edit(f.document, "Speed", [.setSpeed(clip: f.clip, rate: 2, keepPitch: keepPitch)])
        let reverse = ReverseResolution(
            ready: [:], pending: [], rampAudio: rampDir, isolated: isolatedDir)
        guard let s = f.segment,
            let chain = RetimedSound.chain(for: s, dsp: f.dsp, urls: f.urls, reverse: reverse)
        else { return nil }
        return (chain, s, VoiceCache.request(for: s, dsp: f.dsp, urls: f.urls, reverse: reverse))
    }
    func voiceJob(_ request: RampAudioRequest) -> VoiceJob? {
        if case .voice(let job) = request.job { return job }
        return nil
    }
    let cases: [(String, Double, Bool, Int)] = [
        ("isolated, Keep pitch off", 1, false, 3), ("Keep pitch off", 0, false, 2),
        ("isolated, Keep pitch on", 1, true, 2), ("Keep pitch on", 0, true, 1),
    ]
    for (name, isolation, keepPitch, stages) in cases {
        guard let (chain, s, tapped) = chain(isolation: isolation, keepPitch: keepPitch),
            let job = voiceJob(chain.processed)
        else {
            ok = false
            parts.append("\(name): no chain with a voice job")
            continue
        }
        let window = RetimedSound.window(of: s)
        let good = tapped == nil && chain.stages.count == stages && job.window == window
            && job.sounding == RetimedSound.sounding(of: s) && job.sounding != window
            && job.isolated == chain.isolation?.destination
            && job.isolation == (isolation > 0 ? isolation : 0)
            && (chain.isolation != nil) == (isolation > 0)
            && chain.processed.destination.deletingLastPathComponent().lastPathComponent
                == VoiceCache.directoryName
            && (chain.render != nil) == !keepPitch
            && (chain.render.map {
                $0.source == chain.processed.destination
                    && $0.sourceFirstFrame == chain.window.firstFrame
            } ?? true)
        ok = ok && good
        parts.append("×2, \(name): no tapped request \(tapped == nil), \(chain.stages.count) "
            + "stage(s) (want \(stages)), the voice over the window "
            + "\(job.window.firstFrame)–\(job.window.endFrame) sounding "
            + "\(job.sounding.map { "\($0.firstFrame)–\($0.endFrame)" } ?? "all of it"): \(good)")
    }
    let w = IsolationWindow(firstFrame: 0, endFrame: 96_000)
    let plain = VoiceCache.name(
        media: 1, mediaFile: dryA, reversed: false,
        job: VoiceJob(window: w, settings: settings(.hall), isolated: nil, isolation: 0))
    let inside = VoiceCache.name(
        media: 1, mediaFile: dryA, reversed: false,
        job: VoiceJob(
            window: w, settings: settings(.hall), isolated: nil, isolation: 0,
            sounding: IsolationWindow(firstFrame: 8_192, endFrame: 80_000)))
    ok = ok && plain != nil && inside != nil && plain != inside
    parts.append("the sounding frames are in the name: \(plain != inside)")
    row("V15", ok, parts.joined(separator: "; "))
}

// =========================================================================
// V16 — the pad is silent to the effect (AU-145 as amended)

do {
    // 6 s of silence with one impulse; the window is [1 s, 5 s), the clip
    // plays [2 s, 4 s). Echo repeats 250 ms (12,000 frames) later.
    let window = IsolationWindow(firstFrame: 48_000, endFrame: 240_000)
    let sounding = IsolationWindow(firstFrame: 96_000, endFrame: 192_000)
    func peakInClip(_ name: String, impulse: Int, sounding: IsolationWindow?) -> Float? {
        var samples = [Float](repeating: 0, count: 6 * 48_000)
        samples[impulse] = 0.9
        let source = work.appendingPathComponent("v16-\(name).wav")
        guard writeWAV(source, [samples, samples]) == nil else { return nil }
        let destination = work.appendingPathComponent("v16-\(name).caf")
        try? FileManager.default.removeItem(at: destination)
        let job = VoiceRenderer.Job(
            source: source,
            job: VoiceJob(
                window: window, settings: settings(.echo), isolated: nil, isolation: 0,
                sounding: sounding),
            destination: destination)
        guard (try? VoiceRenderer.render(job, cancelled: { false })) != nil,
            let out = readCAF(destination), let left = out.first
        else { return nil }
        // The clip's frames, past the impulse's own sample when it is inside.
        let from = max(96_000, impulse + 2_400) - 48_000
        return left[from..<(192_000 - 48_000)].map(abs).max()
    }
    let before = 96_000 - 2_400
    let padded = peakInClip("pad", impulse: before, sounding: sounding)
    let whole = peakInClip("whole", impulse: before, sounding: nil)
    let own = peakInClip("own", impulse: 100_000, sounding: sounding)
    let ok = (padded ?? 1) <= 1e-6 && (whole ?? 0) >= 1e-2 && (own ?? 0) >= 1e-2
    func told(_ value: Float?) -> String { value.map { "\($0)" } ?? "no render" }
    row("V16", ok,
        "Echo, an impulse 50 ms before the clip's first frame, inside the window: the clip's "
            + "frames peak \(told(padded)) (≤ 1e-6); with the pad not silenced \(told(whole)) "
            + "(≥ 0.01, the echo it keeps out); an impulse inside the clip echoes: \(told(own)) "
            + "(≥ 0.01)")
}
