import AppKit
import AVFoundation
import CoreMedia
import Foundation

// Enhance Voice's probe (road map "audio" AP6, spec §11 AU-60…AU-64),
// compiled with app/Sources through swift_build, `app/Resources/Models`
// beside the binary so the product's own speech pass runs. Arguments: the
// fixtures folder (`rode.m4a`), a scratch folder. Prints one "ok"/"FAIL" line
// per row, each row's name first (E1–E3, E6–E18), for audio_ap6_probe.py to
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

func enhance(_ steps: [Step], current: AudioProps = AudioProps()) -> AudioEnhance.Choice? {
    let (r, mask) = reading(steps, lufs: L)
    guard let m = AudioEnhance.measure(r, speech: mask) else { return nil }
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
    check("E1", "floor − L −44 dB: isolation 0.8, noise reduction 0, a gate",
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
          AudioEnhance.measure(r, speech: mask) == nil)
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
    check("E10", "no audio props plans off the cache",
          !ProcessedLoudness.needsRender(Optional<AudioProps>.none))

    // AU-159 (a): a stage only at an action's end. No base stage; one action
    // from 1 s whose end is `end`, `duration` ticks long.
    func clip(_ end: String, duration: Int = 1_200_000) -> ClipSnapshot? {
        ReelJSON.decode(ClipSnapshot.self, from: """
            {"id": 2, "track": 3, "start": 0, "duration": 6000000,
             "source": {"kind": "media", "media": 1, "in": 0}, "audio": {},
             "actions": [{"id": 90, "start": 600000, "duration": \(duration),
                          "curve": "linear", "end": {"audio": \(end)}}]}
            """)
    }
    let ends: [(String, String)] = [
        ("eq", #"{"eq": {"high_pass": {"frequency": 80, "slope": 24}}}"#),
        ("hum", #"{"hum": {}}"#), ("isolation", #"{"isolation": 0.5}"#),
        ("noise_reduction", #"{"noise_reduction": 0.5}"#),
        ("gate", #"{"gate": {"threshold_db": -20}}"#), ("de_esser", #"{"de_esser": {}}"#),
        ("compressor", #"{"compressor": {}}"#), ("leveller", #"{"leveller": {}}"#),
        // AU-165 (a): a limiter at an end, and a null keying the clip's off.
        ("limiter", #"{"limiter": {"ceiling_db": -6}}"#), ("a null limiter", #"{"limiter": null}"#),
    ]
    let plainEnds: [(String, String)] = [
        ("pan", #"{"pan": 0.5}"#), ("mono", #"{"mono": true}"#),
        ("channels", #"{"channels": "left"}"#),
        ("volume", #"{"volume": 2}"#), ("a null eq", #"{"eq": null}"#),
        ("a null gate", #"{"gate": null}"#), ("isolation 0", #"{"isolation": 0}"#),
        ("noise_reduction 0", #"{"noise_reduction": 0}"#),
    ]
    for (name, end) in ends {
        let snapshot = clip(end)
        check("E10", "\(name) only at an action's end renders",
              snapshot?.actions.count == 1 && !ProcessedLoudness.needsRender(snapshot?.audio)
                && ProcessedLoudness.needsRender(snapshot))
    }
    for (name, end) in plainEnds {
        let snapshot = clip(end)
        check("E10", "\(name) at an action's end alone plans off the cache",
              snapshot?.actions.count == 1 && !ProcessedLoudness.needsRender(snapshot))
    }
    let still = clip(#"{"gate": {"threshold_db": -20}}"#, duration: 0)
    check("E10", "a gate at the end of an action of no duration plans off the cache",
          still?.actions.first?.duration == 0 && !ProcessedLoudness.needsRender(still))
    let stillLimiter = clip(#"{"limiter": {"ceiling_db": -6}}"#, duration: 0)
    check("E10", "a limiter at the end of an action of no duration plans off the cache",
          stillLimiter?.actions.first?.duration == 0 && !ProcessedLoudness.needsRender(stillLimiter))
    check("E10", "no clip plans off the cache",
          !ProcessedLoudness.needsRender(Optional<ClipSnapshot>.none))

    // E15 (AU-165 (a), (b)): which clips an action's end sets a limiter on,
    // and which solves are checked by render.
    var nullStored = false
    if case .some(.none) = clip(#"{"limiter": null}"#)?.actions.first?.end.audio?.limiter {
        nullStored = true
    }
    let based = ReelJSON.decode(ClipSnapshot.self, from: """
        {"id": 2, "track": 3, "start": 0, "duration": 6000000,
         "source": {"kind": "media", "media": 1, "in": 0}, "audio": {"limiter": {}},
         "actions": [{"id": 90, "start": 600000, "duration": 1200000,
                      "curve": "linear", "end": {"audio": {"pan": 0.5}}}]}
        """)
    // The last column is AU-168 (a)'s `endLimiterOn`: a null keys the clip's
    // own limiter off, so it turns none on.
    let sets: [(String, ClipSnapshot?, Bool, Bool)] = [
        ("a limiter at an end", clip(#"{"limiter": {"ceiling_db": -6}}"#), true, true),
        ("a null limiter at an end (keyed off)", clip(#"{"limiter": null}"#), true, false),
        ("a limiter beside a gate at an end",
         clip(#"{"gate": {"threshold_db": -20}, "limiter": {}}"#), true, true),
        ("a limiter at the end of an action of no duration", stillLimiter, false, false),
        ("an end with no limiter key", clip(#"{"gate": {"threshold_db": -20}}"#), false, false),
        ("the clip's own limiter, an end without one", based, false, false),
        ("no clip", nil, false, false),
    ]
    for (name, snapshot, wanted, on) in sets {
        check("E15", "endSetsLimiter: \(name) \(wanted ? "sets" : "does not set") one",
              ProcessedLoudness.endSetsLimiter(snapshot) == wanted
                && (name == "no clip" || snapshot != nil))
        check("E15", "endLimiterOn: \(name) \(on ? "turns" : "does not turn") one on",
              ProcessedLoudness.endLimiterOn(snapshot) == on
                && (name == "no clip" || snapshot != nil))
    }
    check("E15", "a null limiter at an end decodes as a stored null", nullStored)
    let verifies: [(LimiterProps?, Bool, Bool)] = [
        (LimiterProps(), false, true), (LimiterProps(), true, true), (nil, true, true),
        (nil, false, false),
    ]
    for (limiter, end, wanted) in verifies {
        check("E15", "verifiesByRender with \(limiter == nil ? "no" : "a") limiter and "
                + "\(end ? "an" : "no") action-end limiter: \(wanted)",
              LoudnessMeasureRun.verifiesByRender(limiter: limiter, endLimiter: end) == wanted)
    }

    // E17 (AU-165 (b)): AU-24's question at a volume the loop steps to.
    let ceiling = pow(10, AudioNormalize.ceilingDBTP / 20)
    let peak = pow(10, -18.5 / 20)
    let under = ceiling / peak * pow(10, -0.01 / 20)
    let over = ceiling / peak * pow(10, 0.01 / 20)
    check("E17", "no limiter, R0's peak 0.01 dB under −1 dBTP at the volume: stays off",
          !LoudnessMeasureRun.limiterGoesOn(nil, truePeak: peak, volume: under))
    check("E17", "no limiter, R0's peak 0.01 dB over −1 dBTP at the volume: goes on",
          LoudnessMeasureRun.limiterGoesOn(nil, truePeak: peak, volume: over))
    check("E17", "a limiter already on is not asked again",
          !LoudnessMeasureRun.limiterGoesOn(LimiterProps(), truePeak: peak, volume: over * 4))
    let chosen = AudioNormalize.ceilingLimiter(nil)
    let lowered = AudioNormalize.ceilingLimiter(LimiterProps(ceilingDb: -0.5, release: 1_200))
    let kept = AudioNormalize.ceilingLimiter(LimiterProps(ceilingDb: -3, release: 1_200))
    check("E17", "the limiter that goes on is AU-24's: the default at −1 dBTP; a clip's own "
            + "lowered to −1 or kept under it",
          chosen == LimiterProps(ceilingDb: -1) && lowered == LimiterProps(ceilingDb: -1, release: 1_200)
            && kept == LimiterProps(ceilingDb: -3, release: 1_200),
          "\(chosen), \(lowered), \(kept)")
}

// MARK: - E18 what stopped a verified solve away from its target (AU-167, #607)

do {
    let t = -16.0
    let cases: [(String, Double, Double, AudioNormalize.Limit?)] = [
        ("×2, 0.11 LU short", 2, t - 0.11, .verifyRenders),
        ("×2, 0.11 LU over", 2, t + 0.11, .verifyRenders),
        ("×2, 0.09 LU short", 2, t - 0.09, nil),
        ("×2, 0.09 LU over", 2, t + 0.09, nil),
        ("×32, 0.11 LU short", 32, t - 0.11, .maxGain),
        ("×32, 0.09 LU short", 32, t - 0.09, nil),
        ("×32, 0.11 LU over", 32, t + 0.11, .verifyRenders),
        ("×31.9, 5 LU short", 31.9, t - 5, .verifyRenders),
    ]
    for (name, volume, result, wanted) in cases {
        let got = AudioNormalize.verifiedLimit(volume: volume, resultLUFS: result, targetLUFS: t)
        check("E18", "verifiedLimit at \(name): \(wanted?.rawValue ?? "nil")", got == wanted,
              got?.rawValue ?? "nil")
    }
    // The tools' note: today's sentence for the ceiling's clips, byte for byte.
    // A row's R0 is −39.4 LUFS unless given: ×32 of it, −9.3, reaches −16.
    func result(_ clip: UInt32, _ limit: AudioNormalize.Limit?, r0: Double? = -39.4)
        -> AudioNormalize.LoudnessResult
    {
        var r = AudioNormalize.LoudnessResult(
            clip: clip, media: 1, measuredLUFS: -41.6, truePeakDBTP: -18.5,
            volume: limit == .maxGain ? 32 : 2, resultLUFS: -29.1, resultTruePeakDBTP: -3.5,
            limit: limit, limiter: LimiterProps(ceilingDb: -1))
        r.processedLUFS = r0
        r.renders = r0 == nil ? 0 : 4
        return r
    }
    func note(_ rows: [AudioNormalize.LoudnessResult], _ ends: Set<UInt32> = [],
              _ target: Double = -16) -> String? {
        AudioNormalize.limitNote(rows, endLimiters: ends, targetLUFS: target)
    }
    let ceilingOnly = "Clip(s) 3, 5 stopped short of -16.0 LUFS: the volume that reaches it would "
        + "pass the 32× ceiling (limited_by max_gain). result_lufs says where each landed."
    let none = note([result(3, nil)])
    let ceiling = note([result(3, .maxGain), result(4, nil), result(5, .maxGain)])
    let verify = note([result(6, nil), result(7, .verifyRenders)], [], -24.417) ?? ""
    let both = note([result(3, .maxGain), result(7, .verifyRenders)]) ?? ""
    let tail = "result_lufs says where each landed."
    check("E18", "limitNote: no limit, no note", none == nil, none ?? "nil")
    check("E18", "limitNote: the ceiling's clips alone keep today's sentence exactly",
          ceiling == ceilingOnly, ceiling ?? "nil")
    check("E18", "limitNote: a verify bound's clip named with verify_renders and a limiter, no "
            + "max_gain, the tail once",
          verify.hasPrefix("Clip(s) 7 ") && verify.contains("-24.417 LUFS")
            && verify.contains("(limited_by verify_renders)") && verify.contains("limiter")
            && !verify.contains("max_gain") && verify.hasSuffix(tail)
            && verify.components(separatedBy: tail).count == 2, verify)
    check("E18", "limitNote: both, each clip in its own sentence, the tail once",
          both.hasPrefix("Clip(s) 3 stopped short of -16.0 LUFS") && both.contains("Clip(s) 7 ")
            && both.contains("(limited_by max_gain)") && both.contains("(limited_by verify_renders)")
            && both.hasSuffix(tail) && both.components(separatedBy: tail).count == 2, both)
    // AU-168 (b), (c): a limiter an action's end turns on, named in the
    // ceiling's place when R0 at ×32 would have reached the target.
    let reach = 20 * log10(AudioNormalize.maxGain)
    let mixed = note([result(3, .maxGain), result(5, .maxGain)], [5]) ?? ""
    let allHeld = note([result(3, .maxGain), result(5, .maxGain)], [3, 5]) ?? ""
    let quiet = note([result(3, .maxGain, r0: -50), result(5, .maxGain, r0: -50)], [3, 5])
    let near = note([result(5, .maxGain, r0: -16 - 0.05 - reach)], [5]) ?? ""
    let far = note([result(5, .maxGain, r0: -16 - 0.15 - reach)], [5]) ?? ""
    let cacheRow = note([result(5, .maxGain, r0: nil)], [5]) ?? ""
    let others = [result(6, nil), result(7, .verifyRenders)]
    let action = "Clip(s) 5 stopped short of -16.0 LUFS at the 32× ceiling (limited_by max_gain), "
        + "but the likely reason is a limiter an action's end turns on"
    check("E18", "limitNote: of two ceiling clips, the one an action's limiter is on for named "
            + "with that limiter, the other in the ceiling's sentence, the tail once",
          mixed.hasPrefix("Clip(s) 3 stopped short of -16.0 LUFS: the volume that reaches it "
            + "would pass") && mixed.contains(action)
            && mixed.components(separatedBy: "would pass").count == 2
            && mixed.components(separatedBy: "(limited_by max_gain)").count == 3
            && mixed.hasSuffix(tail) && mixed.components(separatedBy: tail).count == 2, mixed)
    check("E18", "limitNote: both under an action's limiter, one sentence naming it, no "
            + "\"would pass\"",
          allHeld.hasPrefix("Clip(s) 3, 5 stopped short of -16.0 LUFS at the 32× ceiling "
            + "(limited_by max_gain), but the likely reason is a limiter an action's end")
            && allHeld.contains("no volume reaches the target") && !allHeld.contains("would pass")
            && allHeld.hasSuffix(tail), allHeld)
    check("E18", "limitNote: R0 at −50, ×32 of it short of −16 anyway: the ceiling's sentence "
            + "byte for byte, though an action's limiter is on",
          quiet == ceilingOnly, quiet ?? "nil")
    check("E18", "limitNote: ×32 of R0 0.05 LU short of −16 names the limiter, 0.15 LU short "
            + "the ceiling",
          near.hasPrefix(action) && far.hasPrefix("Clip(s) 5 stopped short of -16.0 LUFS: the "
            + "volume that reaches it would pass"), near + " | " + far)
    check("E18", "limitNote: a row with no R0 (off the cache) keeps the ceiling's sentence",
          cacheRow.contains("would pass") && !cacheRow.contains("action"), cacheRow)
    // match_audio's target is the reference's measured loudness, unrounded.
    let measuredTarget = note([result(3, .maxGain), result(7, .verifyRenders)], [],
                              -15.999999999117435) ?? ""
    check("E18", "limitNote: a target read from a measurement written to 0.001 LU, as -16.0",
          measuredTarget.hasPrefix("Clip(s) 3 stopped short of -16.0 LUFS: ")
            && measuredTarget.contains("Clip(s) 7 ended more than 0.1 LU from -16.0 LUFS: ")
            && !measuredTarget.contains("99999"), measuredTarget)
    check("E18", "limitNote: the clips set only bites on max_gain: a landed and a verify "
            + "bound's clip in it change nothing",
          note(others, [6, 7], -24.417) == note(others, [], -24.417)
            && note(others, [6, 7], -24.417) != nil, note(others, [6, 7], -24.417) ?? "nil")
    // Enhance's loudness reason, by case.
    func row(_ lufs: Double, _ limit: AudioNormalize.Limit?) -> AudioNormalize.LoudnessResult {
        var r = AudioNormalize.LoudnessResult(
            clip: 1, media: 1, measuredLUFS: -41.6, truePeakDBTP: -18.5, volume: 20.8,
            resultLUFS: lufs, resultTruePeakDBTP: -3.5, limit: limit,
            limiter: LimiterProps(ceilingDb: -1))
        r.processedLUFS = -39.4
        r.renders = 4
        return r
    }
    func reason(_ lufs: Double, _ limit: AudioNormalize.Limit?, endLimiter: Bool = false)
        -> String
    {
        AudioEnhance.loudnessReason(
            row(lufs, limit), limiter: LimiterProps(ceilingDb: -1), target: -24,
            endLimiter: endLimiter)
    }
    let landed = reason(-24.05, nil)
    let capped = reason(-29.1, .maxGain)
    let short = reason(-29.55, .verifyRenders)
    let over = reason(-23.8, .verifyRenders)
    let held = reason(-29.1, .maxGain, endLimiter: true)
    let shortHeld = reason(-29.55, .verifyRenders, endLimiter: true)
    check("E18", "the reason: landed ends at its renders", landed.hasSuffix("(4 renders)."), landed)
    check("E18", "the reason: the ceiling's clause kept",
          capped.hasSuffix("(4 renders), short of −24.0 LUFS: the volume would pass 32×."), capped)
    check("E18", "the reason: at ×32 under an action's limiter, that limiter as the likely "
            + "reason, no \"would pass\" (AU-168 (d))",
          held.hasSuffix("(4 renders), short of −24.0 LUFS at 32×, likely because a limiter an "
            + "action's end turns on holds the sound down harder as the volume rises, so no "
            + "volume reaches it.") && !held.contains("would pass"), held)
    check("E18", "the reason: the verify bound's clause the same with an action's limiter on",
          shortHeld == short, shortHeld)
    check("E18", "the reason: the verify bound short of the target names a limiter, not the ceiling",
          short.contains("(4 renders), short of −24.0 LUFS: ") && short.contains("limiter holds")
            && !short.contains("would pass"), short)
    check("E18", "the reason: the verify bound over the target says over",
          over.contains("(4 renders), over −24.0 LUFS: ") && !over.contains("would pass"), over)
}

// MARK: - E16 the verified figure's test (AU-165 (c))

do {
    let figures = ProcessedLoudness.Verified(
        volume: 2, limiter: nil, lufs: -30, truePeak: 0.1)
    let near = 2 * pow(10, 0.04 / 20)
    let far = 2 * pow(10, 0.06 / 20)
    check("E16", "holds at its own volume and limiter, and 0.04 dB away",
          figures.holds(volume: 2, limiter: nil) && figures.holds(volume: near, limiter: nil))
    check("E16", "does not hold 0.06 dB away, nor under another limiter, nor at volume 0",
          !figures.holds(volume: far, limiter: nil)
            && !figures.holds(volume: 2, limiter: LimiterProps())
            && !figures.holds(volume: 0, limiter: nil))
    let limited = ProcessedLoudness.Verified(
        volume: 2, limiter: LimiterProps(), lufs: -30, truePeak: 0.1)
    check("E16", "a limited render holds under the same limiter, not with none",
          limited.holds(volume: 2, limiter: LimiterProps()) && !limited.holds(volume: 2, limiter: nil))
}

// MARK: - E13, E14 the memo's key and a clip's actions (AU-159 (g))

do {
    /// One 10 s clip of media 1 with `audio` and `actions`.
    func project(audio: String, actions: String) -> ReelProject? {
        try? ReelProject.from(json: """
            {"version": \(RC_FORMAT_VERSION),
             "canvas": {"width": 320, "height": 180, "fps": [30, 1], "background": [0, 0, 0, 1]},
             "media": [{"id": 1, "path": "/fixtures/ap6.wav", "kind": "audio",
                        "duration": 36000000, "has_video": false, "has_audio": true}],
             "tracks": [{"id": 3, "name": "Track 1"}],
             "clips": [{"id": 2, "track": 3, "start": 0, "duration": 6000000,
                        "source": {"kind": "media", "media": 1, "in": 0}, "audio": \(audio),
                        "actions": [\(actions)]}],
             "nests": [], "next_id": 100}
            """)
    }
    func action(_ id: Int, at start: Int, _ end: String) -> String {
        """
        {"id": \(id), "start": \(start), "duration": 600000, "curve": "linear",
         "end": {"audio": \(end)}}
        """
    }
    func key(_ project: ReelProject?) -> ProcessedLoudness.Key? {
        project.flatMap { ProcessedLoudness.key(clip: 2, project: $0, document: 0) }
    }
    func applied(_ project: ReelProject?, _ patch: AudioPatch) -> ReelProject? {
        guard let project, case .applied(let next)? = try? project.applying(
            .setAudio(clips: [2], patch: patch)) else { return nil }
        return next
    }

    // E13: R0's trial (no base limiter, volume 1) against the same clip after
    // the solve wrote its volume and limiter. The clip has a base gate and an
    // action whose end is a pan, so its segment has automation points, and
    // the core writes the base limiter into every one.
    let trial = project(audio: #"{"gate": {}}"#, actions: action(90, at: 600_000, #"{"pan": 0.5}"#))
    let solved = applied(trial, AudioPatch(volume: 2, limiter: .some(LimiterProps())))
    let rawTrial = trial.flatMap { ProcessedLoudness.measurementPlan($0.planJSON, clip: 2)?.json }
    let rawSolved = solved.flatMap { ProcessedLoudness.measurementPlan($0.planJSON, clip: 2)?.json }
    check("E13", "the key R0 was stored under is the clip's key after the solve wrote its "
            + "volume and limiter, though the two measurement plans differ (the base limiter is "
            + "in every automation point)",
          key(trial) != nil && key(trial) == key(solved) && rawTrial != nil
            && rawTrial != rawSolved && rawTrial?.contains("\"automation\"") == true
            && rawSolved?.contains("\"limiter\":{") == true,
          "keys equal \(key(trial) == key(solved)), plans differ \(rawTrial != rawSolved)")

    // E14: the key follows an action's audio.
    let gate20 = project(audio: "{}", actions: action(90, at: 600_000, #"{"gate": {"threshold_db": -20}}"#))
    let gate30 = project(audio: "{}", actions: action(90, at: 600_000, #"{"gate": {"threshold_db": -30}}"#))
    check("E14", "another gate threshold at an action's end is another key",
          key(gate20) != nil && key(gate30) != nil && key(gate20) != key(gate30))
    let limit6 = project(audio: #"{"gate": {}}"#,
                         actions: action(90, at: 600_000, #"{"limiter": {"ceiling_db": -6}}"#))
    let limit3 = project(audio: #"{"gate": {}}"#,
                         actions: action(90, at: 600_000, #"{"limiter": {"ceiling_db": -3}}"#))
    check("E14", "another limiter ceiling at an action's end is another key",
          key(limit6) != nil && key(limit3) != nil && key(limit6) != key(limit3))
    let loud = project(audio: #"{"gate": {}}"#,
                       actions: action(90, at: 600_000, #"{"pan": 0.5, "volume": 0.5}"#))
    let quiet = project(audio: #"{"gate": {}}"#,
                        actions: action(90, at: 600_000, #"{"pan": 0.5, "volume": 0.8}"#))
    check("E14", "another volume at an action's end is the same key (the fader's)",
          key(loud) != nil && key(loud) == key(quiet))
    // A limiter one action switches on and a later one keys off: the key-off
    // is a stored null, and taking it away leaves the limiter on to the end.
    let on = action(90, at: 600_000, #"{"limiter": {"ceiling_db": -6}}"#)
    let keyedOff = project(audio: #"{"gate": {}}"#,
                           actions: on + "," + action(91, at: 2_400_000, #"{"pan": 0.1, "limiter": null}"#))
    let leftOn = project(audio: #"{"gate": {}}"#,
                         actions: on + "," + action(91, at: 2_400_000, #"{"pan": 0.1}"#))
    var stored = false
    if case .some(.none) = keyedOff?.snapshot.clip(2)?.actions.last?.end.audio?.limiter {
        stored = true
    }
    check("E14", "a limiter keyed off at a later action's end is another key than the limiter "
            + "left on",
          stored && key(keyedOff) != nil && key(leftOn) != nil && key(keyedOff) != key(leftOn),
          "the null stored \(stored)")
}

// MARK: - E11 the solved row keeps a volume within 0.05 dB

do {
    let (r, _) = reading(voice(), lufs: L)
    let limiter = LimiterProps()
    func solvedVolume(_ db: Double, limiter solvedLimiter: LimiterProps? = LimiterProps(),
                      current: Double = 2, own: LimiterProps? = LimiterProps()) -> Double? {
        // `limiter` the reading's chosen one (Enhance's, made up when the clip has
        // none); `own` the clip's own as read, which the keep rule compares (#400).
        let read = AudioNormalize.LoudnessReading(
            clip: 1, media: 1, lufs: L, truePeak: r.truePeak, steps: r.steps,
            stepPeaks: r.stepPeaks, limiter: limiter, materialLUFS: L - 3,
            currentVolume: current, currentLimiter: own)
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
    // #400: a first press on a clip with no limiter of its own, whose reading
    // carries the chosen default one, writes the solve.
    let unlimited = solvedVolume(0.04, own: nil)
    check("E11", "a clip with no limiter of its own writes the solve 0.04 dB away, though the "
            + "chosen limiter equals the solve's",
          unlimited.map { abs($0 - 2 * pow(10, 0.04 / 20)) < 1e-12 } == true,
          "\(f3(unlimited))")
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

// MARK: - E12 the processed memo names its document (#401)

do {
    // A second document over a copy of the same package: the same clip, plan
    // and chain, another document.
    let copy = scratch.appendingPathComponent("enhance-2.framejob", isDirectory: true)
    try? FileManager.default.removeItem(at: copy)
    let other = ProjectDocument()
    var opened = false
    do {
        try FileManager.default.copyItem(at: package, to: copy)
        try other.read(from: copy, ofType: ProjectDocument.projectTypeIdentifier)
        opened = true
    } catch {
        check("E12", "the second document opens", false, "\(error)")
    }
    if opened {
        let deadline = Date().addingTimeInterval(0.2)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        let steps = [0.25, 0.5, 0.75]
        let peaks = [0.1, 0.2, 0.3]
        let key = ProcessedLoudness.key(
            clip: 2, project: document.editedProject, document: document.recipeKey)
        if let key { ProcessedLoudness.Memo.shared.store(key, steps: steps, peaks: peaks) }
        let mine = ProcessedLoudness.Memo.shared.reading(for: 2, in: document)
        let theirs = ProcessedLoudness.Memo.shared.reading(for: 2, in: other)
        check("E12", "an R0 stored for one document's clip is not read by another open "
                + "document's same clip",
              key != nil && mine?.steps == steps && mine?.peaks == peaks && theirs == nil
                && document.recipeKey != other.recipeKey,
              "key \(key != nil), this document's \(mine.map { "\($0.steps)" } ?? "nil"), the "
                + "other's \(theirs.map { "\($0.steps)" } ?? "nil")")
    }
    withExtendedLifetime(other) {}
}

// MARK: - E16 the memo keeps the verify render beside its R0 (AU-165 (c))

do {
    let key = ProcessedLoudness.key(
        clip: 2, project: document.editedProject, document: document.recipeKey)
    let figures = ProcessedLoudness.Verified(volume: 1.5, limiter: nil, lufs: -28, truePeak: 0.2)
    var stored = false
    var dropped = false
    if let key {
        let memo = ProcessedLoudness.Memo.shared
        memo.store(key, steps: [0.25], peaks: [0.1])
        memo.storeVerified(key, figures)
        stored = memo.reading(for: 2, in: document)?.verified == figures
        memo.store(key, steps: [0.5], peaks: [0.2])
        let after = memo.reading(for: 2, in: document)
        dropped = after?.verified == nil && after?.steps == [0.5]
    }
    check("E16", "the memo answers the verify render stored beside an R0, and the next R0 for "
            + "the key drops it",
          key != nil && stored && dropped, "stored \(stored), dropped \(dropped)")
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
          + "\(f3(m.peakMedianDB)) dBFS, sibilant share \(f3(m.sibilantShare))")
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
            && jobs.first?.reading.currentVolume == owner.current.volume
            && jobs.first?.reading.currentLimiter == owner.current.limiter,
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
