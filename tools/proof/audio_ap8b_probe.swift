// tools/proof/audio_ap8b_probe.swift — the in-process instrument behind
// `audio_ap8b_proof.py --probe` (road map "audio" AP8b, spec §11 AU-85..AU-89).
// Compiled with every file in `app/Sources` but `main.swift` through
// `swift_build.py`'s line, copied in as `main.swift`.
//
//     audio_ap8b_probe <work-dir>
//
// One line per row, `ok <ID> — <detail>` or `FAIL <ID> — <detail>`; no app is
// launched. Projects are made in-process (`ReelProject.from(json:)`), their
// plans the core's.
//
//  A1  `AudioProps.interpolated`: numbers move linearly (pan, isolation, a
//      compressor's threshold and its attack ticks, a high-pass's corner);
//      discretes and presence come from the left (mono, channels, bypass, a
//      limiter only on the right); the slope 12 → 24, the mains 50 → 60 and
//      the harmonics 2 → 6 hold the left value at f 0.5 and 0.99.
//  A2  an eased action moving a band's gain 0 → +12 dB and the pan −0.5 → +0.5,
//      through `AudioTapContext` at 512-, 4096- and irregular buffers: the
//      three renders are byte-identical, and differ from the input.
//  A3  a linear pan −0.5 → +0.5 over [1 s, 3 s) on a constant input: each
//      sample's gain pair is `AudioPanLaw.gains(pan(t_n))` within 1e-6.
//  A4  `usesLimiter` and `usesNoiseReduction` from a point alone, and a
//      track whose base has neither runs both, with the limiter's lead.
//  A5  isolation's Amount 0 → 1 over [1 s, 3 s) from a base of 0:
//      `AudioIsolationTrack` keeps the segment, and its crossfade over a dry
//      0 and a wet 0.5 reads `a(t)` per frame within 1e-6.
//  A6  `AudioPatch.routedInsideAction`: the duck, keep-pitch, the fade shapes
//      and the voice to the base, the rest to the end; a nest clip's mono to
//      the base.
//  A7  `AudioDynamicsLevels.wanting` counts a gate keyed on at an end alone;
//      `isolates` and `wantsIsolation` from an end alone, the base amount 0.
//  A8  `ReelOp.setActionEnd` with an EQ whose high-pass is off: `off` is
//      exactly `["audio.eq.high_pass"]` and the patch's `eq` has no
//      `high_pass`.
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

func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

func summary(_ tests: [(String, Bool)]) -> (Bool, String) {
    let failed = tests.filter { !$0.1 }.map(\.0)
    return (failed.isEmpty, "\(tests.count - failed.count)/\(tests.count) checks"
        + (failed.isEmpty ? "" : "; failed: " + failed.joined(separator: ", ")))
}

guard CommandLine.arguments.count == 2 else {
    row("A1", false, "usage: audio_ap8b_probe <work-dir>")
    exit(0)
}
let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

/// A project of one 4 s clip (2) of an audio media on track 3, `audio` its
/// base, with one action (`id` 9) over [1 s, 3 s) ending at `end`.
func project(audio: String, curve: String, end: String) -> ReelProject? {
    try? ReelProject.from(json: """
        {"version": \(RC_FORMAT_VERSION),
         "canvas": {"width": 320, "height": 180, "fps": [30, 1], "background": [0, 0, 0, 1]},
         "media": [{"id": 1, "path": "/fixtures/ap8b.wav", "kind": "audio",
                    "duration": \(20 * SEC), "has_video": false, "has_audio": true}],
         "tracks": [{"id": 3, "name": "Track 1"}],
         "clips": [{"id": 2, "track": 3, "start": 0, "duration": \(4 * SEC),
                    "source": {"kind": "media", "media": 1, "in": 0}, "audio": \(audio),
                    "actions": [{"id": 9, "start": \(SEC), "duration": \(2 * SEC),
                                 "curve": "\(curve)", "end": \(end)}]}],
         "next_id": 10}
        """)
}

/// The project's audio track schedule and parameters.
func schedule(_ p: ReelProject) -> (AudioTrackDSP, AudioDSPParameters, [PlanSegment])? {
    guard let plan = p.plan, let segments = plan.audioTracks.first?.segments else { return nil }
    let parameters = AudioDSPParameters(snapshot: p.snapshot)
    return (AudioTrackDSP(segments: segments, parameters: parameters), parameters, segments)
}

/// `input` (two channels) through a tap built on `track`, in buffers of the
/// sizes `sizes` cycles through.
func tapped(_ track: AudioTrackDSP, _ input: [[Float]], sizes: [Int]) -> [[Float]] {
    let context = AudioTapContext(track: track, isolation: nil, meter: nil)
    context.prepare(
        channelCount: 2, sampleRate: Double(RATE), maxFrames: 4096,
        formatFlags: AudioFormatFlags(kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved),
        bitsPerChannel: 32)
    let total = input[0].count
    var out = [[Float]](repeating: [Float](repeating: 0, count: total), count: 2)
    let list = AudioBufferList.allocate(maximumBuffers: 2)
    let l = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
    let r = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
    var position = 0
    var turn = 0
    while position < total {
        let frames = min(sizes[turn % sizes.count], total - position)
        turn += 1
        for i in 0..<frames {
            l[i] = input[0][position + i]
            r[i] = input[1][position + i]
        }
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: l)
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: r)
        context.process(
            list.unsafeMutablePointer, frames: frames,
            time: CMTime(value: Int64(position), timescale: CMTimeScale(RATE)),
            startOfStream: position == 0)
        for i in 0..<frames {
            out[0][position + i] = l[i]
            out[1][position + i] = r[i]
        }
        position += frames
    }
    l.deallocate()
    r.deallocate()
    free(list.unsafeMutablePointer)
    return out
}

// MARK: - A1 interpolation

do {
    let left = AudioProps(
        mono: false, pan: 0,
        compressor: CompressorProps(thresholdDb: -40, ratio: 2, attack: 600, release: 6000),
        isolation: 0,
        eq: EqProps(highPass: EqPassProps(frequency: 80, slope: 12), bypass: false),
        hum: HumProps(frequency: 50, depthDb: 20, harmonics: 2), channels: .both)
    let right = AudioProps(
        mono: true, pan: 1,
        compressor: CompressorProps(thresholdDb: 0, ratio: 4, attack: 1200, release: 6000),
        limiter: LimiterProps(), isolation: 0.8,
        eq: EqProps(highPass: EqPassProps(frequency: 160, slope: 24), bypass: true),
        hum: HumProps(frequency: 60, depthDb: 40, harmonics: 6), channels: .left)
    let half = left.interpolated(toward: right, by: 0.5)
    let late = left.interpolated(toward: right, by: 0.99)
    let tests: [(String, Bool)] = [
        ("pan 0.5", near(half.pan, 0.5)),
        ("isolation 0.4", near(half.isolation, 0.4)),
        ("threshold −20", near(half.compressor?.thresholdDb ?? .nan, -20)),
        ("attack 900 ticks", half.compressor?.attack == 900),
        ("high-pass 120 Hz", near(half.eq?.highPass?.frequency ?? .nan, 120)),
        ("hum depth 30", near(half.hum?.depthDb ?? .nan, 30)),
        ("mono from the left", half.mono == false && late.mono == false),
        ("channels from the left", half.channels == .both && late.channels == .both),
        ("bypass from the left", half.eq?.bypass == false && late.eq?.bypass == false),
        ("limiter presence from the left", half.limiter == nil && late.limiter == nil),
        ("slope holds 12", half.eq?.highPass?.slope == 12 && late.eq?.highPass?.slope == 12),
        ("mains holds 50", half.hum?.frequency == 50 && late.hum?.frequency == 50),
        ("harmonics hold 2", half.hum?.harmonics == 2 && late.hum?.harmonics == 2),
    ]
    let (ok, detail) = summary(tests)
    row("A1", ok, detail)
}

// MARK: - A2 an automated EQ gain and pan, buffer-size invariant

func noise(_ frames: Int, seed: UInt64) -> [Float] {
    var state = seed
    return (0..<frames).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(Int64(bitPattern: state >> 11) % 2_000_000) / 8_000_000 - 0.125
    }
}

do {
    let p = project(
        audio: #"{"eq": {"band_2": {"frequency": 1000, "gain_db": 0, "q": 1}}, "pan": -0.5}"#,
        curve: "ease_in_out",
        end: #"{"audio": {"eq": {"band_2": {"gain_db": 12}}, "pan": 0.5}}"#)
    if let p, let (track, _, segments) = schedule(p) {
        let points = segments.first?.automation.count ?? 0
        let input = [noise(4 * RATE, seed: 1), noise(4 * RATE, seed: 2)]
        let small = tapped(track, input, sizes: [512])
        let large = tapped(track, input, sizes: [4096])
        let odd = tapped(track, input, sizes: [1000, 37, 2048, 333, 4096, 1, 777])
        let same = small == large && small == odd
        let moved = small[0][(3 * RATE)...] != input[0][(3 * RATE)...]
        let automated = track.spans.first?.automation != nil
        row("A2", same && moved && automated && points > 4,
            "\(points) points, automated span \(automated); 512 = 4096 \(small == large), "
                + "512 = irregular \(small == odd); the output moved \(moved)")
    } else {
        row("A2", false, "the project or its plan did not build")
    }
}

// MARK: - A3 the pan per sample

do {
    let p = project(audio: #"{"pan": -0.5}"#, curve: "linear", end: #"{"audio": {"pan": 0.5}}"#)
    if let p, let (track, _, _) = schedule(p) {
        let total = 4 * RATE
        let input = [[Float](repeating: 0.25, count: total), [Float](repeating: 0.25, count: total)]
        let out = tapped(track, input, sizes: [512])
        var worst = 0.0
        for n in stride(from: 0, to: total, by: 7) {
            let tick = Double(n) * Double(SEC) / Double(RATE)
            let pan = -0.5 + min(max((tick - Double(SEC)) / Double(2 * SEC), 0), 1)
            let gains = AudioPanLaw.gains(pan)
            worst = max(worst, abs(Double(out[0][n]) - 0.25 * Double(gains.left)))
            worst = max(worst, abs(Double(out[1][n]) - 0.25 * Double(gains.right)))
        }
        row("A3", worst <= 1e-6, "worst |out − 0.25·law(pan(t_n))| \(worst) (want ≤ 1e-6)")
    } else {
        row("A3", false, "the project or its plan did not build")
    }
}

// MARK: - A4 the track-wide stages from a point alone

do {
    let base = PlanAudioPoint(at: 0, audio: AudioProps())
    let limited = PlanAudioPoint(at: SEC, audio: AudioProps(limiter: LimiterProps()))
    let reduced = PlanAudioPoint(at: SEC, audio: AudioProps(noiseReduction: 0.5))
    func automation(_ points: [PlanAudioPoint]) -> AudioDSPAutomation {
        AudioDSPAutomation(
            points: points, volume: 1, level: nil, enclosingMono: false, trackBalance: .unity)
    }
    var tests: [(String, Bool)] = [
        ("usesLimiter from a point", automation([base, limited]).usesLimiter),
        ("usesNoiseReduction from a point", automation([base, reduced]).usesNoiseReduction),
        ("neither from none", !automation([base]).usesLimiter
            && !automation([base]).usesNoiseReduction),
    ]
    let p = project(
        audio: "{}", curve: "linear",
        end: #"{"audio": {"limiter": {}, "noise_reduction": 0.5}}"#)
    if let p, let (track, _, _) = schedule(p) {
        tests.append(("the track limits", track.usesLimiter))
        tests.append(("the track reduces", track.usesNoiseReduction))
        tests.append((
            "the limiter's lead", track.lookupLead == CompositionBuilder.AudioShift.limiterLead))
    } else {
        tests.append(("the project built", false))
    }
    let (ok, detail) = summary(tests)
    row("A4", ok, detail)
}

// MARK: - A5 isolation's Amount per frame from a base of 0

func writeConstant(_ url: URL, seconds: Int, value: Float) -> Bool {
    try? FileManager.default.removeItem(at: url)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(RATE), channels: 2),
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(RATE * seconds))
    else { return false }
    buffer.frameLength = buffer.frameCapacity
    for c in 0..<2 {
        for i in 0..<Int(buffer.frameLength) { buffer.floatChannelData![c][i] = value }
    }
    guard let file = try? AVAudioFile(
        forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32,
        interleaved: false)
    else { return false }
    return (try? file.write(from: buffer)) != nil
}

do {
    let p = project(audio: "{}", curve: "linear", end: #"{"audio": {"isolation": 1}}"#)
    let wetURL = work.appendingPathComponent("ap8b-wet.caf")
    if let p, let (_, parameters, segments) = schedule(p), let s = segments.first,
        writeConstant(wetURL, seconds: 6, value: 0.5), let wet = IsolatedAudio(contentsOf: wetURL)
    {
        let isolation = AudioIsolationTrack(
            segments: segments, shift: .none, dsp: parameters,
            renders: [IsolationSegmentKey(s): wet])
        let span = isolation.spans.first
        let total = 4 * RATE
        let l = UnsafeMutablePointer<Float>.allocate(capacity: total)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: total)
        l.initialize(repeating: 0, count: total)
        r.initialize(repeating: 0, count: total)
        var at = 0
        while at < total {
            let frames = min(1000, total - at)
            var chunk: [UnsafeMutablePointer<Float>?] = [l + at, r + at]
            chunk.withUnsafeMutableBufferPointer {
                isolation.apply($0, count: 2, frames: frames, at: Int64(at))
            }
            at += frames
        }
        var worst = 0.0
        for n in stride(from: 0, to: total, by: 5) {
            let tick = Double(n) * Double(SEC) / Double(RATE)
            let a = min(max((tick - Double(SEC)) / Double(2 * SEC), 0), 1)
            worst = max(worst, abs(Double(l[n]) - 0.5 * a), abs(Double(r[n]) - 0.5 * a))
        }

        l.deallocate()
        r.deallocate()
        let kept = span != nil && !(span?.amounts.isEmpty ?? true) && span?.amount == 0
        row("A5", kept && worst <= 1e-6,
            "base 0 kept \(kept) (\(span?.amounts.count ?? 0) amounts); worst |out − 0.5·a(t)| "
                + "\(worst) (want ≤ 1e-6)")
    } else {
        row("A5", false, "the project, its plan or the wet render did not build")
    }
}

// MARK: - A6 the routing inside an action

do {
    let patch = AudioPatch(
        volume: 0.5, duck: .some(DuckProps()), mono: true, keepPitch: false, pan: 0.5,
        compressor: .some(CompressorProps()), noiseReduction: 0.3, fadeInShape: .sCurve,
        fadeOutShape: .plus3Db, limiter: .some(LimiterProps()), isolation: 0.5,
        eq: .some(EqProps(band2: EqBandProps())), hum: .some(HumProps()), channels: .left,
        gate: .some(GateProps()), deEsser: .some(DeEsserProps()),
        voice: .some(nil))
    let clip = patch.routedInsideAction(nestClip: false)
    let nest = patch.routedInsideAction(nestClip: true)
    let base = clip.base ?? AudioPatch()
    let end = clip.end ?? AudioPatch()
    let tests: [(String, Bool)] = [
        ("base: duck, keep pitch, fade shapes, voice",
         base.duck != nil && base.keepPitch == false && base.fadeInShape == .sCurve
            && base.fadeOutShape == .plus3Db && base.voice != nil),
        ("base: nothing else",
         base.mono == nil && base.pan == nil && base.eq == nil && base.isolation == nil
            && base.limiter == nil && base.gate == nil && base.volume == nil),
        ("end: the tap keys",
         end.mono == true && end.pan == 0.5 && end.compressor != nil
            && end.noiseReduction == 0.3 && end.limiter != nil && end.isolation == 0.5
            && end.eq != nil && end.hum != nil && end.channels == .left && end.gate != nil
            && end.deEsser != nil && end.volume == 0.5),
        ("end: not the base's",
         end.duck == nil && end.keepPitch == nil && end.fadeInShape == nil && end.voice == nil),
        ("a nest clip's mono to the base", nest.base?.mono == true && nest.end?.mono == nil),
    ]
    let (ok, detail) = summary(tests)
    row("A6", ok, detail)
}

// MARK: - A7 the wanted sets from an end

do {
    var tests: [(String, Bool)] = []
    if let gated = project(audio: "{}", curve: "linear", end: #"{"audio": {"gate": {}}}"#),
        let isolated = project(audio: "{}", curve: "linear", end: #"{"audio": {"isolation": 0.5}}"#),
        let plain = project(audio: "{}", curve: "linear", end: #"{"audio": {"pan": 0.5}}"#)
    {
        tests.append((
            "a gate at an end is wanting",
            AudioDynamicsLevels.wanting(gated.snapshot).map(\.id) == [2]))
        tests.append(("a pan is not", AudioDynamicsLevels.wanting(plain.snapshot).isEmpty))
        let wanted = AudioDSPParameters(snapshot: isolated.snapshot)
        tests.append(("isolates from an end", wanted.isolates))
        tests.append(("wantsIsolation from an end", wanted.wantsIsolation(2)))
        tests.append(("the base amount stays 0", wanted.isolation(for: 2) == 0))
        tests.append(("not empty", !wanted.isEmpty))
        tests.append(("a pan does not isolate", !AudioDSPParameters(snapshot: plain.snapshot).isolates))
    } else {
        tests.append(("the projects built", false))
    }
    let (ok, detail) = summary(tests)
    row("A7", ok, detail)
}

// MARK: - A8 the EQ slot lift

do {
    let eq = EqProps(
        highPass: nil, lowShelf: .lowShelf, band1: EqBandProps(), band2: EqBandProps(),
        band3: EqBandProps(), highShelf: .highShelf, lowPass: .lowPass)
    let op = ReelOp.setActionEnd(
        clip: 2, action: 9, patch: ActionPatch(audio: AudioPatch(eq: .some(eq))))
    let off = op.args["off"] as? [String] ?? []
    let sent = ((op.args["patch"] as? [String: Any])?["audio"] as? [String: Any])?["eq"]
        as? [String: Any]
    let lifted = sent.map { $0["high_pass"] == nil && $0["band_2"] != nil } ?? false
    var applied = false
    if let p = project(
        audio: #"{"eq": {"high_pass": {"frequency": 80, "slope": 12}}}"#, curve: "linear",
        end: "{}"), case .applied(let next)? = try? p.applying(op)
    {
        let end = next.snapshot.clips.first?.actions.first?.end.audio?.eq
        if case .some(.some(let stored)) = end { applied = stored.highPass == nil }
    }
    row("A8", off == ["audio.eq.high_pass"] && lifted && applied,
        "off \(off); the patch's eq without high_pass \(lifted); applied \(applied)")
}
exit(0)
