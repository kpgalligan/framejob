import AppKit
import AVFoundation
import CoreMedia
import Foundation

// Enhance Voice's probe (road map "audio" AP6, spec §11 AU-60…AU-64),
// compiled with app/Sources through swift_build, `app/Resources/Models`
// beside the binary so the product's own speech pass runs. Arguments: the
// fixtures folder (`rode.m4a`), a scratch folder. Prints one "ok"/"FAIL" line
// per row, each row's name first (E1–E3, E6–E11), for audio_ap6_probe.py to
// score. Nothing here renders: the processed solve is the proof's (V2, V13).

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
NSApplication.shared.setActivationPolicy(.prohibited)

let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let scratch = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

func check(_ row: String, _ name: String, _ good: Bool, _ detail: String = "") {
    print((good ? "  ok   " : "  FAIL ") + row + " " + name + (detail.isEmpty ? "" : ": " + detail))
}
func f3(_ x: Double?) -> String { x.map { String(format: "%.3f", $0) } ?? "nil" }
func dB(_ x: Double) -> Double { x > 0 ? 20 * log10(x) : -.infinity }

// MARK: - Synthetic readings

/// One 10 ms step: its loudness ℓ (LUFS), true peak (dBFS), high band ℓ,
/// and whether it is speech.
struct Step { var level: Double; var peak: Double; var high: Double; var speech: Bool }

func energy(_ level: Double) -> Double { pow(10, (level - LoudnessMeter.offset) / 10) }

func reading(_ steps: [Step], lufs: Double) -> (ClipLoudness.Reading, [Bool]) {
    let r = ClipLoudness.Reading(
        lufs: lufs, truePeak: steps.map { pow(10, $0.peak / 20) }.max() ?? 0,
        playedTicks: Ticks(steps.count) * 6000, steps: steps.map { energy($0.level) },
        stepPeaks: steps.map { pow(10, $0.peak / 20) },
        stepSources: steps.indices.map { Ticks($0) * 6000 + 3000 },
        stepHighs: steps.map { energy($0.high) })
    return (r, steps.map(\.speech))
}

let L = -30.0

/// 200 speech steps at L (peaks alternating −20 and −6 dBFS, high band
/// `high`), then `pause` pause steps at `pauseLevels` (cycled) and `pausePeak`.
func voice(floorGap: Double? = -40, pause: Int = 100, pausePeak: Double = -70,
           pauseLevels: [Double]? = nil, high: Double = L - 30, hotHighs: Int = 0,
           hotLevel: Double = L - 9, speechPeaks: [Double] = [-20, -6]) -> [Step] {
    var steps: [Step] = []
    for k in 0..<200 {
        steps.append(Step(level: L, peak: speechPeaks[k % speechPeaks.count],
                          high: k < hotHighs ? hotLevel : high, speech: true))
    }
    let levels = pauseLevels ?? [L + (floorGap ?? -40)]
    for k in 0..<pause {
        steps.append(Step(level: levels[k % levels.count], peak: pausePeak, high: -120,
                          speech: false))
    }
    return steps
}

func enhance(_ steps: [Step], isolatable: Bool = true, current: AudioProps = AudioProps())
    -> AudioEnhance.Choice?
{
    let (r, mask) = reading(steps, lufs: L)
    guard let m = AudioEnhance.measure(r, speech: mask, isolatable: isolatable) else { return nil }
    let input = AudioEnhance.Input(
        readings: [AudioEnhance.Reading(clip: 7, media: 1, measurement: m, loudness: r,
                                        current: current)], problems: [])
    return AudioEnhance.choose(input).first
}

/// The chosen patch's keys: never the volume or the limiter, which the
/// processed solve writes (AU-64).
func keys(_ row: AudioEnhance.Choice?) -> [String] {
    row.map { $0.patch.dictionary.keys.sorted() } ?? []
}
let always = ["compressor", "de_esser", "eq"]
let cleaning = ["compressor", "de_esser", "eq", "gate", "isolation", "noise_reduction"]

// MARK: - E1 each rule, both sides of its threshold

do {
    let noisy = enhance(voice(floorGap: -44))
    check("E1", "floor − L −44 dB, isolatable: isolation 0.8, noise reduction 0, a gate",
          noisy?.patch.isolation == IsolationCache.defaultAmount
            && noisy?.patch.noiseReduction == 0 && noisy?.patch.gate??.ratio == 4
            && keys(noisy) == cleaning,
          "\(String(describing: noisy?.patch.dictionary))")
    // The pauses' median peak −70 dBFS: the gate opens at −70 + 10 − L = −30 re L.
    check("E1", "the gate's threshold is the pause peak + 10 − L, rounded: −30",
          noisy?.patch.gate??.thresholdDb == -30,
          "\(String(describing: noisy?.patch.gate)), pause peak "
            + "\(f3(noisy?.measurement.pausePeakMedianDB)), floor \(f3(noisy?.measurement.floorLUFS))")
    let quiet = enhance(voice(floorGap: -46))
    check("E1", "floor − L −46 dB: isolation 0, noise reduction 0, the gate cleared",
          quiet?.patch.isolation == 0 && quiet?.patch.noiseReduction == 0
            && quiet?.patch.gate.map { $0 == nil } == true && keys(quiet) == cleaning,
          "\(String(describing: quiet?.patch.dictionary))")
    let dry = enhance(voice(floorGap: -44), isolatable: false)
    check("E1", "noisy and not isolatable: noise reduction 0.5, isolation 0, a gate",
          dry?.patch.noiseReduction == 0.5 && dry?.patch.isolation == 0
            && dry?.patch.gate??.thresholdDb == -30, "\(String(describing: dry?.patch.dictionary))")
    let high = enhance(voice(floorGap: -20, pausePeak: -40))
    let low = enhance(voice(floorGap: -44, pausePeak: -100))
    check("E1", "the gate's threshold held to −6 and −40",
          high?.patch.gate??.thresholdDb == -6 && low?.patch.gate??.thresholdDb == -40,
          "\(f3(high?.patch.gate??.thresholdDb)) \(f3(low?.patch.gate??.thresholdDb))")
    // 12 of 200 speech steps (6 %) at L − 9: on; 8 (4 %): off; 20 at L − 11: off.
    let hot = enhance(voice(hotHighs: 12))
    let cool = enhance(voice(hotHighs: 8))
    let under = enhance(voice(hotHighs: 20, hotLevel: L - 11))
    check("E1", "the de-esser on at 6 % sibilant speech, off at 4 % and for a band at L − 11",
          hot?.patch.deEsser == .some(DeEsserProps()) && cool?.patch.deEsser == .some(nil)
            && under?.patch.deEsser == .some(nil),
          "shares \(f3(hot?.measurement.sibilantShare)) \(f3(cool?.measurement.sibilantShare)) "
            + "\(f3(under?.measurement.sibilantShare))")
    // Pause loudness 60 % at L − 60 and 40 % at L − 20: the MEDIAN is L − 60
    // (quiet), the mean L − 44 (noisy).
    let mixed = enhance(voice(pauseLevels: [L - 60, L - 60, L - 60, L - 20, L - 20]))
    check("E1", "the floor is the MEDIAN pause loudness (L − 60, so no gate), not the mean",
          mixed?.measurement.floorLUFS == L - 60 && mixed?.patch.gate.map { $0 == nil } == true,
          "floor \(f3(mixed?.measurement.floorLUFS))")
    check("E1", "the high-pass is the EQ's Rumble Cut, other slots kept",
          noisy?.patch.eq??.highPass == EqPassProps(frequency: 80, slope: 24)
            && enhance(voice(), current: AudioProps(eq: EqProps(band2: EqBandProps())))?
                .patch.eq??.band2 == EqBandProps(),
          "\(String(describing: noisy?.patch.eq))")
}

// MARK: - E2 the compressor

/// The model, written out here rather than called: the follower, the
/// one-pole reduction and the gain (AU-64), for E2's makeup.
func modelled(_ r: ClipLoudness.Reading, _ c: CompressorProps) -> [Double] {
    let thr = c.thresholdDb
    let slope = 1 - 1 / c.ratio
    let rel = Double(c.release) / 600_000, att = Double(c.attack) / 600_000
    var lvl = 0.0, red = 0.0
    var out: [Double] = []
    for (k, e) in r.steps.enumerated() {
        lvl = max(r.stepPeaks[k], lvl * exp(-0.01 / max(rel, 0.01)))
        let target = lvl > pow(10, thr / 20) ? (20 * log10(lvl) - thr) * slope : 0
        let tau = target > red ? att : rel
        red += (target - red) * (tau > 0 ? 1 - exp(-0.01 / tau) : 1)
        let g = pow(10, (c.makeupDb - red) / 20)
        out.append(e * g * g)
    }
    return out
}

do {
    let row = enhance(voice())
    let (r, _) = reading(voice(), lufs: L)
    let c = row?.patch.compressor ?? nil
    let after = StepLoudness.integrated(modelled(r, CompressorProps(thresholdDb: -13)))
    let want = min(max((L - (after ?? .nan)).rounded(), 0), 24)
    check("E2", "the threshold is the speech's median true peak, rounded: −13 dBFS; 3:1, 10 ms, "
            + "200 ms by default",
          c?.thresholdDb == -13 && c?.ratio == 3 && c?.attack == 6000 && c?.release == 120_000,
          "\(String(describing: c))")
    check("E2", "the makeup gives back what the compression takes, rounded",
          c?.makeupDb == want && want > 0,
          "makeup \(f3(c?.makeupDb)), loudness at makeup 0 \(f3(after)) against L \(L)")
    let through = c.map { StepLoudness.integrated(modelled(r, $0)) } ?? nil
    check("E2", "through the compressor with its makeup the loudness is within 0.5 LU of L",
          abs((through ?? .nan) - L) <= 0.5, "\(f3(through))")
    let loud = enhance(voice(speechPeaks: [3]))
    let soft = enhance(voice(speechPeaks: [-70]))
    check("E2", "the threshold held to 0 and −60 dBFS",
          (loud?.patch.compressor ?? nil)?.thresholdDb == 0
            && (soft?.patch.compressor ?? nil)?.thresholdDb == -60,
          "\(String(describing: loud?.patch.compressor)) \(String(describing: soft?.patch.compressor))")
}

// MARK: - E8 the speech mask

do {
    let spans: [[Ticks]] = [[100, 200], [300, 400]]
    let sources: [Ticks] = [50, 100, 150, 199, 200, 250, 300, 399, 400, 1000, 350, 120]
    let want = [false, true, true, true, false, false, true, true, false, false, true, true]
    let got = AudioEnhance.speechMask(sources: sources, spans: spans)
    check("E8", "a step is speech when its source midpoint lies in [start, end), any order",
          got == want && AudioEnhance.speechMask(sources: [5], spans: []) == [false],
          "\(got)")
}

// MARK: - E7 the unmeasured floor (synthetic)

do {
    let row = enhance(voice(pause: 10))
    check("E7", "under 0.5 s of pause: no floor, isolation, noise reduction and gate left out",
          row?.measurement.floorLUFS == nil && keys(row) == always
            && row?.reasons.contains { $0.contains("no floor") } == true,
          "\(keys(row)) \(row?.reasons.first { $0.hasPrefix("Noise") } ?? "")")
    let (r, mask) = reading(Array(voice().suffix(150)), lufs: L)
    check("E7", "under 1 s of speech measures nothing",
          AudioEnhance.measure(r, speech: mask, isolatable: true) == nil)
}

// MARK: - E9 the measurement plan

func object(_ json: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
}

do {
    // Clip 7 twice on track 1 beside clip 8, clip 9 alone on track 2; ramps,
    // pans, a video track, a duck and two instructions, all to go.
    func seg(_ clip: Int, _ start: Int, _ duration: Int) -> [String: Any] {
        ["clip": clip, "media": 1, "source_in": 0, "source_duration": duration, "start": start,
         "duration": duration, "track_pans": [0.5, 0.25]]
    }
    let fixture: [String: Any] = [
        "timescale": 600_000, "duration": 6_000_000, "fps": [30, 1], "render_size": [320, 180],
        "video_tracks": [["id": 1, "segments": [seg(7, 0, 600_000)]]],
        "audio_tracks": [
            ["id": 2, "segments": [seg(7, 600_000, 600_000), seg(8, 1_200_000, 600_000),
                                   seg(7, 1_800_000, 300_000)],
             "ramps": [["start": 600_000, "duration": 600_000, "from": 0.5, "to": 0.5]]],
            ["id": 3, "segments": [seg(9, 0, 600_000)],
             "ramps": [["start": 0, "duration": 600_000, "from": 1, "to": 1]]],
        ],
        "instructions": [["start": 0, "duration": 600_000, "required_track_ids": [1]],
                         ["start": 600_000, "duration": 5_400_000, "required_track_ids": []]],
        "warnings": [], "output": "sdr",
        "ducks": [["clip": 7, "ramps": [["start": 0, "duration": 600_000, "from": 1, "to": 0.5]]]],
    ]
    let json = String(
        data: try! JSONSerialization.data(withJSONObject: fixture, options: [.sortedKeys]),
        encoding: .utf8)!
    let measured = ProcessedLoudness.measurementPlan(json, clip: 7)
    let root = measured.map { object($0.json) } ?? [:]
    let tracks = root["audio_tracks"] as? [[String: Any]] ?? []
    let segments = tracks.first?["segments"] as? [[String: Any]] ?? []
    check("E9", "only the clip's segments, its emptied track dropped",
          tracks.count == 1 && segments.count == 2
            && segments.allSatisfy { ($0["clip"] as? Int) == 7 }
            && measured?.plan.audioTracks.first?.segments.count == 2,
          "\(tracks.count) tracks, \(segments.map { $0["clip"] ?? "?" })")
    check("E9", "no ramps, every segment's track_pans empty (pre-fader)",
          tracks.allSatisfy { $0["ramps"] == nil }
            && segments.allSatisfy { ($0["track_pans"] as? [Any])?.isEmpty == true }
            && measured?.plan.audioTracks.first?.ramps == nil,
          "\(tracks.map { $0.keys.sorted() })")
    let instructions = root["instructions"] as? [[String: Any]] ?? []
    check("E9", "no video tracks or ducks, one instruction from 0 over the plan",
          (root["video_tracks"] as? [Any])?.isEmpty == true
            && (root["ducks"] as? [Any])?.isEmpty == true && instructions.count == 1
            && (instructions.first?["start"] as? Int) == 0
            && (instructions.first?["duration"] as? Int) == 6_000_000
            && (instructions.first?["required_track_ids"] as? [Any])?.isEmpty == true,
          "\(instructions)")
    check("E9", "the span of the clip's segments, 600000…2100000",
          measured?.start == 600_000 && measured?.end == 2_100_000,
          "\(String(describing: measured?.start))…\(String(describing: measured?.end))")
    check("E9", "a clip with no audio segment has no measurement plan",
          ProcessedLoudness.measurementPlan(json, clip: 42) == nil)
    // A render's plan: the base volume as one constant ramp, the export's fader.
    let faded = ProcessedLoudness.measurementPlan(json, clip: 7, volume: 2)?.plan.audioTracks
    let unity = ProcessedLoudness.measurementPlan(json, clip: 7, volume: 1)?.plan.audioTracks
    let fader = faded?.first?.ramps ?? []
    check("E9", "with volume 2 one constant ramp at 2 over the plan; at 1 none",
          faded?.count == 1 && fader.count == 1 && fader.first?.start == 0
            && fader.first?.duration == 6_000_000 && fader.first?.from == 2
            && fader.first?.to == 2 && unity?.first?.ramps == nil,
          "\(fader)")
}

// MARK: - E10 which clips render

do {
    let renders: [(String, AudioProps)] = [
        ("eq", AudioProps(eq: EqProps(highPass: EqPassProps(frequency: 80)))),
        ("hum", AudioProps(hum: HumProps())),
        ("isolation", AudioProps(isolation: 0.5)),
        ("noise_reduction", AudioProps(noiseReduction: 0.5)),
        ("gate", AudioProps(gate: GateProps(thresholdDb: -20))),
        ("de_esser", AudioProps(deEsser: DeEsserProps())),
        ("compressor", AudioProps(compressor: CompressorProps())),
        ("voice", AudioProps(voice: VoiceProps(kind: .robot))),
        ("leveller", AudioProps(leveller: LevellerProps())),
    ]
    let plain: [(String, AudioProps)] = [
        ("pan", AudioProps(pan: 0.5)), ("mono", AudioProps(mono: true)),
        ("channels", AudioProps(channels: .left)), ("limiter", AudioProps(limiter: LimiterProps())),
        ("volume", AudioProps(volume: 4)), ("fades", AudioProps(fadeIn: 60_000, fadeOut: 60_000)),
        ("bypassed eq",
         AudioProps(eq: EqProps(highPass: EqPassProps(frequency: 80), bypass: true))),
        ("empty eq", AudioProps(eq: EqProps())),
        ("inert voice", AudioProps(voice: VoiceProps(kind: .robot, amount: 0))),
    ]
    for (name, audio) in renders {
        check("E10", "\(name) renders", ProcessedLoudness.needsRender(audio))
    }
    for (name, audio) in plain {
        check("E10", "\(name) alone plans off the cache", !ProcessedLoudness.needsRender(audio))
    }
    check("E10", "no audio props plans off the cache", !ProcessedLoudness.needsRender(nil))
}

// MARK: - E11 the solved row keeps a volume within 0.05 dB

do {
    let (r, _) = reading(voice(), lufs: L)
    let limiter = LimiterProps()
    func solvedVolume(_ db: Double, limiter solvedLimiter: LimiterProps? = LimiterProps(),
                      current: Double = 2) -> Double? {
        let read = AudioNormalize.LoudnessReading(
            clip: 1, media: 1, lufs: L, truePeak: r.truePeak, steps: r.steps,
            stepPeaks: r.stepPeaks, limiter: limiter, materialLUFS: L - 3,
            currentVolume: current)
        let solve = AudioNormalize.Solved(
            volume: current * pow(10, db / 20), limiter: solvedLimiter, resultLUFS: -16,
            resultTruePeakDBTP: -1, limit: nil, renders: 2)
        let plan = AudioNormalize.plan(
            AudioNormalize.LoudnessInput(readings: [read], problems: []), targetLUFS: -16,
            solved: [1: solve])
        let patch = plan.ops.first?.args["patch"] as? [String: Any]
        return (patch?["volume"] as? NSNumber)?.doubleValue ?? patch?["volume"] as? Double
    }
    let kept = solvedVolume(0.04)
    let moved = solvedVolume(0.06)
    let other = solvedVolume(0.04, limiter: LimiterProps(ceilingDb: -2))
    check("E11", "a solve 0.04 dB from the clip's volume keeps it; 0.06 dB writes the solve",
          kept == 2 && moved.map { abs($0 - 2 * pow(10, 0.06 / 20)) < 1e-12 } == true,
          "kept \(f3(kept)), moved \(f3(moved))")
    check("E11", "a different solved limiter writes the solve", other.map { $0 != 2 } == true,
          "\(f3(other))")
    // A cache row whose own volume is 0.02 dB from the plan's: never kept.
    let first = AudioNormalize.plan(
        AudioNormalize.LoudnessInput(readings: [
            AudioNormalize.LoudnessReading(clip: 1, media: 1, lufs: L, truePeak: r.truePeak,
                                           steps: r.steps, stepPeaks: r.stepPeaks)],
                                     problems: []), targetLUFS: -16).normalized.first
    let near = (first?.volume ?? 1) * pow(10, 0.02 / 20)
    let cached = AudioNormalize.plan(
        AudioNormalize.LoudnessInput(readings: [
            AudioNormalize.LoudnessReading(clip: 1, media: 1, lufs: L, truePeak: r.truePeak,
                                           steps: r.steps, stepPeaks: r.stepPeaks,
                                           currentVolume: near)], problems: []),
        targetLUFS: -16)
    let row = cached.normalized.first
    check("E11", "a cache row writes the plan's volume, not one 0.02 dB away; no processed figure",
          row?.volume == first?.volume && row?.processedLUFS == nil && row?.renders == 0,
          "\(f3(row?.volume)) against \(f3(first?.volume)), current \(f3(near))")
}

// MARK: - The owner's recording, through a probe document

func decode(_ url: URL) -> [Float]? {
    let asset = AVURLAsset(url: url)
    let box = TrackBox()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        box.track = (try? await asset.loadTracks(withMediaType: .audio))?.first
        done.signal()
    }
    done.wait()
    guard let track = box.track, let reader = try? AVAssetReader(asset: asset) else { return nil }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false])
    reader.add(output)
    guard reader.startReading() else { return nil }
    var samples: [Float] = []
    while let buffer = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
        let length = CMBlockBufferGetDataLength(block)
        var chunk = [Float](repeating: 0, count: length / 4)
        _ = chunk.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                       destination: $0.baseAddress!)
        }
        samples += chunk
    }
    return reader.status == .completed ? samples : nil
}
final class TrackBox: @unchecked Sendable { var track: AVAssetTrack? }
final class ResultBox: @unchecked Sendable { var value = false }

let rodeURL = fixtures.appendingPathComponent("rode.m4a")
guard let material = decode(rodeURL) else {
    check("E6", "the owner's recording decodes", false)
    exit(1)
}
let rodeTicks = Ticks((Double(material.count) / 48_000 * 600_000).rounded(.up))
func media(_ id: UInt32) -> MediaSnapshot {
    MediaSnapshot(id: id, path: rodeURL.path, kind: .audio, duration: rodeTicks, hasVideo: false,
                  hasAudio: true)
}

/// Clip 2 the whole recording (media 91); clip 3 0.3 s of it; clip 4 media
/// 92 with 0.5 s of saved speech; clip 5 media 93 (no loudness file); clip 6
/// media 94 (loudness, no speech). One track each.
let package = scratch.appendingPathComponent("enhance.framejob", isDirectory: true)
try? FileManager.default.removeItem(at: package)
try? FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
do {
    func m(_ id: Int, speech: [[Int]]? = nil) -> [String: Any] {
        var out: [String: Any] = ["id": id, "path": rodeURL.path, "kind": "audio",
                                  "duration": Int(rodeTicks), "has_video": false,
                                  "has_audio": true]
        if let speech { out["speech"] = speech }
        return out
    }
    func c(_ id: Int, track: Int, media: Int, duration: Int) -> [String: Any] {
        ["id": id, "track": track, "start": 0, "duration": duration,
         "source": ["kind": "media", "media": media, "in": 0], "audio": [:]]
    }
    let whole = Int(rodeTicks) / 20_000 * 20_000
    let project: [String: Any] = [
        "version": Int(RC_FORMAT_VERSION),
        "canvas": ["width": 320, "height": 180, "fps": [30, 1], "background": [0, 0, 0, 1],
                   "fit_new_clips": true, "timecode_frames": true],
        "media": [m(91), m(92, speech: [[0, 300_000]]), m(93), m(94)],
        "tracks": (11...15).map { ["id": $0, "name": "Track \($0)"] },
        "clips": [c(2, track: 11, media: 91, duration: whole),
                  c(3, track: 12, media: 91, duration: 180_000),
                  c(4, track: 13, media: 92, duration: whole),
                  c(5, track: 14, media: 93, duration: whole),
                  c(6, track: 15, media: 94, duration: whole)],
        "markers": [], "next_id": 300, "nests": []]
    try! JSONSerialization.data(withJSONObject: project)
        .write(to: package.appendingPathComponent("project.json"))
}
let document = ProjectDocument()
do {
    try document.read(from: package, ofType: ProjectDocument.projectTypeIdentifier)
} catch {
    check("E6", "the probe document opens", false, "\(error)")
    exit(1)
}
let cache = document.cacheDirectory!
for id: UInt32 in [91, 92, 94] {
    let done = DispatchSemaphore(value: 0)
    let box = ResultBox()
    Task.detached {
        box.value = await MediaImporter.loudness(
            for: media(id), url: rodeURL,
            stamp: MediaImporter.CacheStamp.stamp(for: media(id), url: rodeURL), into: cache)
        done.signal()
    }
    _ = done.wait(timeout: .now() + 120)
}
do {
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        await MediaImporter.speech(
            for: media(91), url: rodeURL,
            stamp: MediaImporter.CacheStamp.stamp(for: media(91), url: rodeURL), into: cache)
        done.signal()
    }
    _ = done.wait(timeout: .now() + 300)
}

// MARK: - E7 the skips, by name

do {
    let input = AudioEnhance.read(from: document, clips: [99, 3, 4, 5, 6])
    let reasons = input?.problems.map { $0.description } ?? []
    let want = ["clip 99: is not a clip", "clip 3: plays for under 0.4 s",
                "clip 4: has under 1 s of speech", "clip 5: is still being analyzed — its loudness",
                "clip 6: is still being analyzed — its speech has not been detected yet"]
    check("E7", "five skips, each by name: not a clip, 0.3 s, 0.5 s of speech, no loudness file, "
            + "no speech",
          input?.readings.isEmpty == true && reasons.count == 5
            && zip(reasons, want).allSatisfy { $0.hasPrefix($1) },
          reasons.joined(separator: " | "))
}

// MARK: - E6 the owner's recording

guard let input = AudioEnhance.read(from: document, clips: [2]), let owner = input.readings.first
else {
    let why = AudioEnhance.read(from: document, clips: [2])?.problems.first?.description ?? "nil"
    check("E6", "the owner's recording is measured (VAD available: \(SileroVAD.isAvailable))",
          false, why)
    exit(1)
}
let choices = AudioEnhance.choose(input)
guard let choice = choices.first else {
    check("E6", "the owner's recording has a choice", false)
    exit(1)
}
do {
    let m = owner.measurement
    print("  note E6 measured: L \(f3(m.lufs)) LUFS, TP \(f3(dB(m.truePeak))) dBTP, speech "
          + "\(m.speechSteps) steps, pause \(m.pauseSteps), floor \(f3(m.floorLUFS)) LUFS "
          + "(F \(f3(m.floorGapDB)) dB), pause peak \(f3(m.pausePeakMedianDB)) dBFS, speech peak "
          + "\(f3(m.peakMedianDB)) dBFS, sibilant share \(f3(m.sibilantShare)), isolatable "
          + "\(m.isolatable)")
    let set = choice.patch.dictionary
    let json = (try? JSONSerialization.data(withJSONObject: set, options: [.sortedKeys]))
        .flatMap { String(data: $0, encoding: .utf8) } ?? "?"
    print("  note E6 chose: \(json); limiter \(choice.limiter.dictionary)")
    for reason in choice.reasons { print("  note E6 reason: \(reason)") }
    // Over 3 s of speech, so the leveller (AU-67) is among the keys too.
    check("E6", "the owner's recording: noisy pauses, so isolation, a gate and every key but "
            + "volume and limiter",
          keys(choice) == (cleaning + ["leveller"]).sorted() && choice.patch.isolation == IsolationCache.defaultAmount
            && choice.limiter.ceilingDb <= AudioNormalize.ceilingDBTP
            && choice.patch.volume == nil && choice.patch.limiter == nil,
          "\(keys(choice))")
    let c = choice.patch.compressor ?? nil
    let through = c.map {
        StepLoudness.integrated(
            AudioDynamicsModel.compressed(
                steps: owner.loudness.steps, peaks: owner.loudness.stepPeaks, compressor: $0).steps)
    } ?? nil
    check("E6", "its compressor gives back what it takes: makeup > 0, loudness within 0.5 LU of L",
          (c?.makeupDb ?? 0) > 0 && abs((through ?? .nan) - m.lufs) <= 0.5,
          "makeup \(f3(c?.makeupDb)), through \(f3(through)) against \(f3(m.lufs))")
    let jobs = AudioEnhance.jobs(input, choices)
    check("E6", "its job renders through the chosen patch, carrying the limiter and the volume",
          jobs.count == 1 && jobs.first?.chain == choice.patch
            && jobs.first?.reading.limiter == choice.limiter
            && jobs.first?.reading.currentVolume == owner.current.volume,
          "\(jobs.count) jobs")
    let real = ProcessedLoudness.measurementPlan(document.editedProject.planJSON, clip: 2)
    check("E9", "the owner's clip has a measurement plan of its one track over its span",
          real?.plan.audioTracks.count == 1 && real?.start == 0
            && real?.end == document.project.snapshot.clip(2).map { $0.start + $0.duration },
          "\(String(describing: real?.start))…\(String(describing: real?.end))")
}

// MARK: - E3 choose over its own result writes the same keys

do {
    // The choice committed with a volume and limiter, as the solve would add.
    var first = choice.patch
    first.volume = 4
    first.limiter = .some(choice.limiter)
    document.applyEdit(AudioEnhance.actionName, [.setAudio(clips: [2], patch: first)])
    let enhanced = document.project.snapshot.clip(2)?.audio
    let again = AudioEnhance.read(from: document, clips: [2]).map { AudioEnhance.choose($0) }
    let second = again?.first
    var answer = "nothing"
    if let second, let edit = try? document.project.applying(
        .setAudio(clips: [2], patch: second.patch))
    {
        switch edit {
        case .identity: answer = "identity"
        case .applied: answer = "applied"
        case .refused(let why): answer = "refused: \(why.reason)"
        }
    }
    check("E3", "the edit landed, and choose over its own result is the same patch, an identity",
          enhanced?.compressor != nil && enhanced?.gate != nil && second?.patch == choice.patch
            && second?.limiter == choice.limiter && answer == "identity",
          "second press \(answer)")
}
