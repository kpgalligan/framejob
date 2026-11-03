import AppKit
import AVFoundation
import Foundation

// Switch by Speaker's planner probe (road map "creator-jobs" SW2a, spec §11
// SW-20…SW-27), compiled with app/Sources through swift_build, with
// `app/Resources/Models` beside the binary so the product's own speech pass
// (Silero VAD) runs. Arguments: `rows <f_turns folder|-> <scratch> [rows]` or
// `spike <f_turns folder> <scratch>`. Rows print one "ok"/"FAIL"/"skip" line
// each, the row's name first (R1–R6), for switch_speaker_probe.py to score;
// every expected value is worked by hand here, never by the planner. The
// spike prints one `spike {json}` line per setting and variant.

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
NSApplication.shared.setActivationPolicy(.prohibited)

let arguments = CommandLine.arguments
let mode = arguments[1]
let fturns: URL? = arguments[2] == "-" ? nil : URL(fileURLWithPath: arguments[2], isDirectory: true)
let scratch = URL(fileURLWithPath: arguments[3], isDirectory: true)
let only: Set<String> = arguments.count > 4 && !arguments[4].isEmpty
    ? Set(arguments[4].split(separator: ",").map(String.init)) : []
func wanted(_ row: String) -> Bool { only.isEmpty || only.contains(row) }

func check(_ row: String, _ name: String, _ good: Bool, _ detail: String = "") {
    print((good ? "  ok   " : "  FAIL ") + row + " " + name + (detail.isEmpty ? "" : ": " + detail))
}
func note(_ row: String, _ text: String) { print("  note \(row) \(text)") }

typealias S = SpeakerSwitch
let fps = Fps(num: 30, den: 1)
let second: Ticks = 600_000
let step: Ticks = 6_000
func t(_ seconds: Double) -> Ticks { Ticks((seconds * 600_000).rounded()) }
/// SW-21's drafted thresholds (bleed 15, dominance 8, margin 6), the rest `Settings()`'s: R1's and
/// R2's hand-worked values never depend on SW-S4's tuning.
let drafted: S.Settings = {
    var settings = S.Settings()
    settings.bleedDB = 15
    settings.dominanceDB = 8
    settings.floorMarginDB = 6
    return settings
}()

// MARK: - R1 SW-21 over synthetic microphones

/// 100 speech steps at P, 100 quiet steps at F, then the test steps: P and F
/// are exactly the calibration levels (nearest rank; tests ≤ 10 % sit below P
/// or are quiet above F).
func microphone(_ track: UInt32, p: Double, f: Double, tests: [(Double, Float)]) -> S.Microphone {
    let level = [Double](repeating: p, count: 100) + [Double](repeating: f, count: 100)
        + tests.map(\.0)
    let voice = [Float](repeating: 0.9, count: 100) + [Float](repeating: 0.1, count: 100)
        + tests.map(\.1)
    return S.Microphone(track: track, level: level, voice: voice,
                        covered: [Bool](repeating: true, count: level.count))
}
func tested(_ mics: [S.Microphone], settings: S.Settings = drafted) -> [S.Label] {
    Array(S.labels(mics, settings: settings).dropFirst(200))
}

if wanted("R1") {
    let one = tested([microphone(1, p: -20, f: -60, tests: [(-20, 0.5), (-20, 0.4999)])])
    check("R1", "voice at 0.5 active, at 0.4999 not", one == [.person(1), .nobody], "\(one)")
    let bleed = tested([microphone(1, p: -20, f: -60, tests: [(-35, 0.9), (-35.01, 0.9)])])
    check("R1", "bleed: ℓ = P − 15 active, 0.01 dB under not", bleed == [.person(1), .nobody],
          "\(bleed)")
    let floor = tested([microphone(1, p: -20, f: -40, tests: [(-34, 0.9), (-34.01, 0.9)])])
    check("R1", "floor: ℓ = F + 6 active, 0.01 dB under not", floor == [.person(1), .nobody],
          "\(floor)")
    let dominance = tested([
        microphone(1, p: -20, f: -60, tests: [(-20, 0.9), (-20, 0.9), (-20, 0.9), (-60, 0.1)]),
        microphone(2, p: -20, f: -60, tests: [(-28, 0.9), (-27.99, 0.9), (-20, 0.9), (-20, 0.9)]),
    ])
    check("R1", "dominance: 8 dB over the other alone, 7.99 dB crosstalk, equal crosstalk, one "
            + "active the person",
          dominance == [.person(1), .crosstalk, .crosstalk, .person(2)], "\(dominance)")
    let percentiles = (S.percentile([5, 1, 4, 2, 3, 6, 7, 8, 9, 10], 0.9),
                       S.percentile([5, 1, 4, 2, 3, 6, 7, 8, 9, 10], 0.1),
                       S.percentile([3, 1, 2], 0.9), S.percentile([], 0.5))
    check("R1", "nearest rank: 90th of 1…10 is 9, 10th is 1, 90th of three is the top, none nil",
          percentiles.0 == 9 && percentiles.1 == 1 && percentiles.2 == 3 && percentiles.3 == nil,
          "\(percentiles)")
    var impulse = [Double](repeating: 0, count: 40)
    impulse[20] = 1
    let levels = ClipLevelSeries.levels(impulse)
    let finite = levels.indices.filter { levels[$0].isFinite }
    check("R1", "an impulse at 20 moves ℓ at 16…25 only, each −10 dB",
          finite == Array(16...25) && finite.allSatisfy { abs(levels[$0] + 10) < 1e-12 },
          "finite at \(finite)")
    var edge = [Double](repeating: 0, count: 40)
    edge[0] = 1
    let clipped = ClipLevelSeries.levels(edge)
    let edgeFinite = clipped.indices.filter { clipped[$0].isFinite }
    check("R1", "at the series' start the window is clipped: ℓ(0) = 10·log10(1/5)",
          edgeFinite == Array(0...5) && abs(clipped[0] - 10 * log10(0.2)) < 1e-12,
          "finite at \(edgeFinite), ℓ(0) \(clipped[0])")
    let defaults = S.Settings()
    check("R1", "the defaults are SW-S4's chosen setting: bleed 15, dominance 8, margin 6",
          defaults.bleedDB == 15 && defaults.dominanceDB == 8 && defaults.floorMarginDB == 6,
          "bleed \(defaults.bleedDB), dominance \(defaults.dominanceDB), margin \(defaults.floorMarginDB)")
}

// MARK: - R2 SW-22 over synthetic labels

/// Labels from (label, seconds) runs at 10 ms.
func labels(_ runs: [(S.Label, Double)]) -> [S.Label] {
    runs.flatMap { [S.Label](repeating: $0.0, count: Int(($0.1 * 100).rounded())) }
}
func whole(_ track: UInt32, _ to: Double) -> S.AngleTrack {
    S.AngleTrack(track: track, clips: [S.Span(clip: track * 10, start: 0, end: t(to))])
}
let ab = S.Pairing(speakers: [S.Speaker(mic: 1, angle: 11), S.Speaker(mic: 2, angle: 12)], wide: 13)
let abNoWide = S.Pairing(speakers: ab.speakers, wide: nil)
func shots(_ l: [S.Label], to: Double, pairing: S.Pairing = ab, angles: [S.AngleTrack]? = nil,
           settings: S.Settings = drafted) -> [S.Shot] {
    S.shots(labels: l, from: 0, to: t(to), fps: fps, pairing: pairing,
            angles: angles ?? [whole(11, to), whole(12, to), whole(13, to)], settings: settings)
}
func shot(_ angle: UInt32, _ a: Double, _ b: Double) -> S.Shot { S.Shot(angle: angle, start: t(a), end: t(b)) }
let A = S.Label.person(1), B = S.Label.person(2), X = S.Label.crosstalk, N = S.Label.nobody

if wanted("R2") {
    // Bridge: A 0.6 s, nobody 0.49 s, A 0.6 s is one 1.69 s turn; with 0.5 s
    // it is two short ones and nothing starts (no wide: the front-most angle).
    let front = [whole(12, 10), whole(11, 10)]
    let bridged = shots(labels([(N, 2), (A, 0.6), (N, 0.49), (A, 0.6), (N, 6.31)]), to: 10,
                        pairing: abNoWide, angles: front)
    let unbridged = shots(labels([(N, 2), (A, 0.6), (N, 0.5), (A, 0.6), (N, 6.3)]), to: 10,
                          pairing: abNoWide, angles: front)
    check("R2", "bridge: 0.49 s of nobody joins two 0.6 s turns into one; 0.5 s does not",
          bridged == [shot(11, 0, 10)] && unbridged == [shot(12, 0, 10)],
          "\(bridged) | \(unbridged)")

    // Opening on the wide, the lead, min_turn at its edge.
    let turn = shots(labels([(N, 3), (A, 3), (N, 1), (B, 1.0), (N, 4)]), to: 12)
    let short = shots(labels([(N, 3), (A, 3), (N, 1), (B, 0.99), (N, 4.01)]), to: 12)
    check("R2", "opens on the wide; a 1.0 s turn cuts 0.2 s early, a 0.99 s one does not",
          turn == [shot(13, 0, 2.8), shot(11, 2.8, 6.8), shot(12, 6.8, 12)]
            && short == [shot(13, 0, 2.8), shot(11, 2.8, 12)], "\(turn) | \(short)")

    // The snap: a turn at 3.01 s cuts at frame 84 (2.81 s is 84.3 frames),
    // one at 3.03 s at frame 85 (84.9).
    let low = shots(labels([(N, 3.01), (A, 3), (N, 5.99)]), to: 12)
    let high = shots(labels([(N, 3.03), (A, 3), (N, 5.97)]), to: 12)
    check("R2", "the lead is snapped to the nearest frame: 84 and 85",
          low.count == 2 && low[1].start == 84 * 20_000 && high.count == 2
            && high[1].start == 85 * 20_000, "\(low) | \(high)")

    // Crosstalk: to the wide; held with `hold`; under crosstalk_min held.
    let talk = labels([(N, 3), (A, 3), (N, 1), (X, 1.5), (N, 1), (B, 3), (N, 1.5)])
    let wide = shots(talk, to: 14)
    var holding = drafted
    holding.crosstalk = .hold
    let held = shots(talk, to: 14, settings: holding)
    let brief = shots(labels([(N, 3), (A, 3), (N, 1), (X, 0.99), (N, 1.51), (B, 3), (N, 1.5)]),
                      to: 14)
    check("R2", "crosstalk of 1.5 s cuts to the wide; `hold` holds; 0.99 s holds",
          wide == [shot(13, 0, 2.8), shot(11, 2.8, 6.8), shot(13, 6.8, 9.3), shot(12, 9.3, 14)]
            && held == [shot(13, 0, 2.8), shot(11, 2.8, 9.3), shot(12, 9.3, 14)]
            && brief == [shot(13, 0, 2.8), shot(11, 2.8, 9.3), shot(12, 9.3, 14)],
          "\(wide) | \(held) | \(brief)")

    // A short shot merges into the one before (A), not the next (the wide).
    let merged = shots(labels([(N, 3), (A, 3), (N, 1), (B, 1.2), (N, 0.2), (X, 2.5), (N, 3.1)]),
                       to: 14)
    check("R2", "a 1.4 s shot merges into the shot before, not the one after",
          merged == [shot(13, 0, 2.8), shot(11, 2.8, 8.2), shot(13, 8.2, 14)], "\(merged)")

    // SW-22 (a)'s crosstalk bridge (the owner's option 1): A 0.3 s between two 0.6 s crosstalk
    // runs joins them into one 1.5 s crosstalk turn at 7 s, which cuts to the wide at 6.8 s and
    // holds it to B's cut at 9.3 s; A 0.5 s does not join (strictly less), so both crosstalk runs
    // are short and A holds until B's turn at 9.5 s cuts at 9.3 s.
    let joined = shots(labels([(N, 3), (A, 3), (N, 1), (X, 0.6), (A, 0.3), (X, 0.6), (N, 1),
                               (B, 3), (N, 1.5)]), to: 14)
    let apart = shots(labels([(N, 3), (A, 3), (N, 1), (X, 0.6), (A, 0.5), (X, 0.6), (N, 0.8),
                              (B, 3), (N, 1.5)]), to: 14)
    check("R2", "crosstalk bridge: X 0.6, A 0.3, X 0.6 is one 1.5 s crosstalk turn to the wide; "
            + "A 0.5 s does not join and holds",
          joined == [shot(13, 0, 2.8), shot(11, 2.8, 6.8), shot(13, 6.8, 9.3), shot(12, 9.3, 14)]
            && apart == [shot(13, 0, 2.8), shot(11, 2.8, 9.3), shot(12, 9.3, 14)],
          "\(joined) | \(apart)")

    // A stretch of two runs, B 0.04 s and nobody 0.23 s (0.27 s), joins: the crosstalk turn is
    // 7–8.47 s, to the wide at 6.8 s; B at 9.5 s cuts at 9.3 s.
    let stretch = shots(labels([(N, 3), (A, 3), (N, 1), (X, 0.6), (B, 0.04), (N, 0.23), (X, 0.6),
                                (N, 1.03), (B, 3), (N, 1.5)]), to: 14)
    check("R2", "crosstalk bridge: the stretch B 0.04, nobody 0.23 between two crosstalk runs "
            + "joins and cuts to the wide",
          stretch == [shot(13, 0, 2.8), shot(11, 2.8, 6.8), shot(13, 6.8, 9.3), shot(12, 9.3, 14)],
          "\(stretch)")

    // A stretch of A 0.3 s and nobody 0.3 s (0.6 s in total) does not join: A holds until B's
    // turn at 9.5 s cuts at 9.3 s.
    let wideStretch = shots(labels([(N, 3), (A, 3), (N, 1), (X, 0.6), (A, 0.3), (N, 0.3),
                                    (X, 0.6), (N, 0.7), (B, 3), (N, 1.5)]), to: 14)
    check("R2", "crosstalk bridge: a stretch of A 0.3 and nobody 0.3 (0.6 s) does not join",
          wideStretch == [shot(13, 0, 2.8), shot(11, 2.8, 9.3), shot(12, 9.3, 14)],
          "\(wideStretch)")

    // The first shot (pulled back to 0, 1.8 s) merges into the one after.
    let first = shots(labels([(N, 0.5), (A, 1.5), (B, 3), (N, 5)]), to: 10, pairing: abNoWide,
                      angles: [whole(11, 10), whole(12, 10)])
    check("R2", "the first shot, short, merges into the one after",
          first == [shot(12, 0, 10)], "\(first)")

    // wide_after 4 s: the wide for min_shot, then the speaker returns.
    var after = drafted
    after.wideAfter = 4
    let long = shots(labels([(N, 3), (A, 10), (N, 4)]), to: 17, settings: after)
    check("R2", "wide_after: the wide at 4 s into a shot for 2 s, repeated",
          long == [shot(13, 0, 2.8), shot(11, 2.8, 6.8), shot(13, 6.8, 8.8), shot(11, 8.8, 12.8),
                   shot(13, 12.8, 14.8), shot(11, 14.8, 17)], "\(long)")

    // (g): A's angle leaves 5–7 s uncovered; the wide takes it.
    let gappy = S.AngleTrack(track: 11, clips: [S.Span(clip: 1, start: 0, end: t(5)),
                                                 S.Span(clip: 2, start: t(7), end: t(20))])
    let handed = shots(labels([(N, 3), (A, 9), (N, 2)]), to: 14,
                       angles: [gappy, whole(12, 14), whole(13, 14)])
    check("R2", "an uncovered stretch of a shot's angle goes to the wide",
          handed == [shot(13, 0, 2.8), shot(11, 2.8, 5), shot(13, 5, 7), shot(11, 7, 14)],
          "\(handed)")
}

// MARK: - R3 SW-24's refusals as one list

func mic(_ track: UInt32, speech: Range<Int>?, count: Int) -> S.Microphone {
    var level = [Double](repeating: -60, count: count)
    var voice = [Float](repeating: 0.1, count: count)
    for k in speech ?? 0..<0 {
        level[k] = -20
        voice[k] = 0.9
    }
    return S.Microphone(track: track, level: level, voice: voice,
                        covered: [Bool](repeating: true, count: count))
}
func input(from: Ticks, to: Ticks, angles: [S.AngleTrack], mics: [S.Microphone], pairing: S.Pairing,
           problems: [String] = [], clipCount: Int = 0) -> S.Input {
    S.Input(from: from, to: to, fps: fps, angles: angles, microphones: mics, pairing: pairing,
            problems: problems, clipCount: clipCount, settings: S.Settings())
}

if wanted("R3") {
    let ten = (101...110).map { track in
        S.AngleTrack(track: UInt32(track), clips: [S.Span(clip: UInt32(track), start: 0, end: t(5))])
    }
    let analysing = "The microphone on track 3 is still being analysed — its loudness has not "
        + "been measured yet. Try again in a moment."
    let unavailable = "Speech detection is unavailable on this Mac, so Switch by Speaker cannot "
        + "tell who is talking."
    let all = input(
        from: 0, to: t(10), angles: ten,
        mics: [mic(1, speech: nil, count: 1000), mic(2, speech: 0..<100, count: 1000),
               S.Microphone(track: 3, level: [], voice: [], covered: [])],
        pairing: S.Pairing(speakers: [S.Speaker(mic: nil, angle: 101), S.Speaker(mic: 7, angle: 102),
                                      S.Speaker(mic: 1, angle: nil), S.Speaker(mic: 2, angle: 103),
                                      S.Speaker(mic: 2, angle: 104)], wide: nil),
        problems: [analysing, unavailable])
    let want = [
        "Switch by Speaker takes at most nine angles; 10 tracks hold a selected clip with a picture.",
        "The speaker on track 101 has no microphone.",
        "The speaker on track 102 has no microphone.",
        "The microphone on track 1 has no angle to show its speaker.",
        "Track 2 is the microphone for 2 speakers; each person needs their own microphone.",
        analysing, unavailable,
        "The microphone on track 1 has no speech between 00:00:00:00 and 00:00:10:00, so it never "
            + "says who is talking.",
        "No angle has a picture between 00:00:05:00 and 00:00:10:00.",
    ]
    let got = S.plan(all)
    check("R3", "every refusal, as one list in order", got == .refused(want),
          "\(got)")
    let one = S.plan(input(from: 0, to: t(10), angles: [whole(11, 10)],
                           mics: [mic(1, speech: 0..<500, count: 1000)],
                           pairing: S.Pairing(speakers: [S.Speaker(mic: 1, angle: 11)], wide: nil)))
    check("R3", "one angle: needs at least two", one == .refused([
        "Switch by Speaker needs at least two angles: tracks holding a selected clip with a picture."
    ]), "\(one)")

    // The ceiling: A speaks 2–5 s, B 5–8 s over angles straddling both ends:
    // shots 11 [2, 4.8) and 12 [4.8, 8): two pieces and four splits, N = 6.
    let most = Int(RC_MAX_CLIPS)
    func ceiling(_ m: Int) -> S.Plan {
        S.plan(input(from: t(2), to: t(8), angles: [whole(11, 10), whole(12, 10)],
                     mics: [mic(1, speech: 0..<300, count: 600), mic(2, speech: 300..<600, count: 600)],
                     pairing: abNoWide, clipCount: m))
    }
    let over = ceiling(most - 5)
    let under = ceiling(most - 6)
    check("R3", "the ceiling: N = 6 refused at M = \(most - 5) by RC_MAX_CLIPS \(most), planned at "
            + "\(most - 6)",
          over == .refused(["Switch by Speaker would add 6 clips to \(most - 5); the most is "
                                + "\(most) — raise the minimum shot."])
            && under == .planned(shots: [shot(11, 2, 4.8), shot(12, 4.8, 8)], added: 6)
            && most == 4096,
          "\(over) | \(under)")
}

// MARK: - R4 SW-20's defaults over snapshots

func video(_ id: UInt32, audio: Bool = true) -> MediaSnapshot {
    MediaSnapshot(id: id, path: "/v\(id).mov", kind: .video, duration: 10 * second, width: 1920,
                  height: 1080, hasVideo: true, hasAudio: audio)
}
func sound(_ id: UInt32) -> MediaSnapshot {
    MediaSnapshot(id: id, path: "/a\(id).wav", kind: .audio, duration: 10 * second, hasVideo: false,
                  hasAudio: true)
}
func clip(_ id: UInt32, track: UInt32, media: UInt32, video: Bool = true, audio: Bool = true,
          linked: UInt32? = nil) -> ClipSnapshot {
    ClipSnapshot(id: id, track: track, start: 0, duration: 10 * second,
                 source: .media(id: media, in: 0, reversed: false),
                 enabled: EnabledFlags(video: video, audio: audio), linked: linked)
}
func project(_ tracks: [UInt32], _ media: [MediaSnapshot], _ clips: [ClipSnapshot]) -> ProjectSnapshot {
    ProjectSnapshot(media: media, tracks: tracks.map { TrackSnapshot(id: $0) }, clips: clips)
}

if wanted("R4") {
    // Two cameras (1, 2) and two files (3, 4): the files are the microphones.
    let files = project([1, 2, 3, 4], [video(1), video(2), sound(3), sound(4)],
                        [clip(10, track: 1, media: 1), clip(20, track: 2, media: 2),
                         clip(30, track: 3, media: 3), clip(40, track: 4, media: 4)])
    let f = S.defaults(selection: files.clips, in: files)
    check("R4", "picture-less files are the microphones; front to back with the angles",
          f.angles == [2, 1] && f.microphones == [4, 3]
            && f.pairing == S.Pairing(speakers: [S.Speaker(mic: 4, angle: 2),
                                                 S.Speaker(mic: 3, angle: 1)], wide: nil),
          "\(f)")

    let cameras = project([1, 2], [video(1), video(2)],
                          [clip(10, track: 1, media: 1), clip(20, track: 2, media: 2)])
    let c = S.defaults(selection: cameras.clips, in: cameras)
    check("R4", "with no file, each camera is its own microphone",
          c.angles == [2, 1] && c.microphones == [2, 1]
            && c.pairing == S.Pairing(speakers: [S.Speaker(mic: 2, angle: 2),
                                                 S.Speaker(mic: 1, angle: 1)], wide: nil),
          "\(c)")

    let three = project([1, 2, 3, 4, 5], [video(1), video(2), video(3), sound(4), sound(5)],
                        [clip(10, track: 1, media: 1), clip(20, track: 2, media: 2),
                         clip(30, track: 3, media: 3), clip(40, track: 4, media: 4),
                         clip(50, track: 5, media: 5)])
    let w = S.defaults(selection: three.clips, in: three)
    check("R4", "the one angle left over is the wide",
          w.angles == [3, 2, 1] && w.microphones == [5, 4]
            && w.pairing == S.Pairing(speakers: [S.Speaker(mic: 5, angle: 3),
                                                 S.Speaker(mic: 4, angle: 2)], wide: 1),
          "\(w)")

    // Two cameras each detached (pictures on 1, 2; their sounds on 3, 4).
    let detached = project([1, 2, 3, 4], [video(1), video(2)],
                           [clip(10, track: 1, media: 1, audio: false, linked: 30),
                            clip(20, track: 2, media: 2, audio: false, linked: 40),
                            clip(30, track: 3, media: 1, video: false, linked: 10),
                            clip(40, track: 4, media: 2, video: false, linked: 20)])
    let d = S.defaults(selection: detached.clips, in: detached)
    check("R4", "two detached cameras, all four selected: two angles, the sound tracks neither "
            + "angles nor microphones",
          d.angles == [2, 1] && d.microphones.isEmpty
            && d.pairing == S.Pairing(speakers: [], wide: nil), "\(d)")

    // One camera whole (1), one detached (picture 2, sound 3): only 1 sounds. One microphone
    // with two angles is SW-83's faces pairing: every angle with it, front first, no wide.
    let mixed = project([1, 2, 3], [video(1), video(2)],
                        [clip(10, track: 1, media: 1),
                         clip(20, track: 2, media: 2, audio: false, linked: 30),
                         clip(30, track: 3, media: 2, video: false, linked: 20)])
    let m = S.defaults(selection: mixed.clips, in: mixed)
    check("R4", "a detached camera sound is never a default microphone",
          m.angles == [2, 1] && m.microphones == [1]
            && m.pairing == S.Pairing(speakers: [S.Speaker(mic: 1, angle: 2),
                                                 S.Speaker(mic: 1, angle: 1)], wide: nil), "\(m)")
}

// MARK: - R5 covering

if wanted("R5") {
    let joined = S.AngleTrack(track: 11, clips: [S.Span(clip: 1, start: 0, end: t(5)),
                                                  S.Span(clip: 2, start: t(5), end: t(10))])
    let across = shots(labels([(A, 10)]), to: 10, pairing: abNoWide,
                       angles: [joined, whole(12, 10)])
    check("R5", "a two-file angle covers its join: one shot over it, no gap",
          S.reach(joined, from: 0) == t(10) && S.firstGap([joined], from: 0, to: t(10)) == nil
            && across == [shot(11, 0, 10)], "\(across)")

    let a = S.AngleTrack(track: 11, clips: [S.Span(clip: 1, start: 0, end: t(4)),
                                             S.Span(clip: 2, start: t(6), end: t(10))])
    let b = S.AngleTrack(track: 12, clips: [S.Span(clip: 3, start: 0, end: t(4)),
                                             S.Span(clip: 4, start: t(7), end: t(10))])
    let gap = S.plan(input(from: 0, to: t(10), angles: [a, b],
                           mics: [mic(1, speech: 0..<500, count: 1000),
                                  mic(2, speech: 500..<1000, count: 1000)], pairing: abNoWide))
    check("R5", "a gap in every angle is refused naming it",
          gap == .refused(["No angle has a picture between 00:00:04:00 and 00:00:06:00."]),
          "\(gap)")

    // No wide; A covers [0, 10.5) ∪ [11, 20), B [0, 20); A [0, 10), a short
    // B [10, 11.5), then A again: B cannot merge into A (A leaves 10.5–11).
    let holed = S.AngleTrack(track: 11, clips: [S.Span(clip: 1, start: 0, end: t(10.5)),
                                                 S.Span(clip: 2, start: t(11), end: t(20))])
    let angles = [holed, whole(12, 20)]
    let kept = shots(labels([(A, 10.2), (B, 1.5), (A, 8.3)]), to: 20, pairing: abNoWide,
                     angles: angles)
    let coveredAll = kept.allSatisfy { s in
        angles.first { $0.track == s.angle }.flatMap { S.reach($0, from: s.start) }.map { $0 >= s.end }
            ?? false
    }
    check("R5", "a short shot its neighbour cannot cover stays; every shot's angle covers it",
          kept == [shot(11, 0, 10), shot(12, 10, 11.5), shot(11, 11.5, 20)] && coveredAll,
          "\(kept)")

    // The first shot's angle (A) is uncovered for 0–3 s: handed to the
    // front-most covering angle (C, 13), not B.
    let late = S.AngleTrack(track: 11, clips: [S.Span(clip: 1, start: t(3), end: t(20))])
    let opening = shots(labels([(A, 10), (N, 10)]), to: 20, pairing: abNoWide,
                        angles: [whole(13, 20), whole(12, 20), late])
    check("R5", "the first shot's uncovered start goes to the front-most covering angle",
          opening == [shot(13, 0, 3), shot(11, 3, 20)], "\(opening)")
}

// MARK: - R6 and the spike: F-TURNS read off a document

struct Variant { let name: String; let micA: String; let micB: String }

func blocking(_ seconds: Double, _ body: @escaping @Sendable () async -> Void) {
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        await body()
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + seconds)
}

/// The variant's document: wide (10), B (11), A (12, two files) back to
/// front, then mic B (13) and mic A (14); every clip selected.
func document(for variant: Variant, manifest: [String: Any], folder: URL) -> ProjectDocument? {
    let cameras = manifest["cameras"] as! [String: [String: Any]]
    let duration = manifest["duration_ticks"] as! Int
    func ticks(_ name: String) -> Int { cameras[name]!["duration_ticks"] as! Int }
    func videoMedia(_ id: Int, _ name: String) -> [String: Any] {
        ["id": id, "path": folder.appendingPathComponent("\(name).mov").path, "kind": "video",
         "duration": ticks(name), "width": 1920, "height": 1080, "fps": [30, 1],
         "has_video": true, "has_audio": false]
    }
    func audioMedia(_ id: Int, _ file: String) -> [String: Any] {
        ["id": id, "path": folder.appendingPathComponent(file).path, "kind": "audio",
         "duration": duration, "has_video": false, "has_audio": true]
    }
    func c(_ id: Int, _ track: Int, _ media: Int, _ start: Int, _ length: Int) -> [String: Any] {
        ["id": id, "track": track, "start": start, "duration": length,
         "source": ["kind": "media", "media": media, "in": 0]]
    }
    let half = ticks("cam_a_1")
    let project: [String: Any] = [
        "version": Int(RC_FORMAT_VERSION),
        "canvas": ["width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
                   "fit_new_clips": true, "timecode_frames": true],
        "media": [videoMedia(1, "cam_a_1"), videoMedia(2, "cam_a_2"), videoMedia(3, "cam_b"),
                  videoMedia(4, "cam_wide"), audioMedia(5, variant.micA), audioMedia(6, variant.micB)],
        "tracks": [["id": 10, "name": "Wide"], ["id": 11, "name": "Cam B"], ["id": 12, "name": "Cam A"],
                   ["id": 13, "name": "Mic B"], ["id": 14, "name": "Mic A"]],
        "clips": [c(20, 12, 1, 0, half), c(21, 12, 2, half, ticks("cam_a_2")),
                  c(22, 11, 3, 0, ticks("cam_b")), c(23, 10, 4, 0, ticks("cam_wide")),
                  c(24, 14, 5, 0, duration), c(25, 13, 6, 0, duration)],
        "markers": [], "next_id": 300, "nests": []]
    let package = scratch.appendingPathComponent("\(variant.name).framejob", isDirectory: true)
    try? FileManager.default.removeItem(at: package)
    try? FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    guard let data = try? JSONSerialization.data(withJSONObject: project),
          (try? data.write(to: package.appendingPathComponent("project.json"))) != nil
    else { return nil }
    let document = ProjectDocument()
    do {
        try document.read(from: package, ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        return nil
    }
    guard let cache = document.cacheDirectory else { return nil }
    for media in document.project.snapshot.media where media.hasAudio {
        let url = URL(fileURLWithPath: media.path)
        let stamp = MediaImporter.CacheStamp.stamp(for: media, url: url)
        blocking(300) { _ = await MediaImporter.loudness(for: media, url: url, stamp: stamp, into: cache) }
        blocking(600) { await MediaImporter.speech(for: media, url: url, stamp: stamp, into: cache) }
    }
    return document
}

/// SW-S4's named limit (the owner, 2026-11-03): F-TURNS' b24_f45, expected shot 17 (b), may be late
/// after onset − lead by at most its measured error; every other cut is held to τ.
let namedLimit: (variant: String, shot: Int, angle: String, lateTicks: Ticks) = ("b24_f45", 17, "b", 99_313)
/// (pass, misses, errors in ms, limited): `limited` names each cut passed only by `namedLimit`.
func score(_ plan: S.Plan, expected: [[String: Any]], lead: Double, variant: String)
    -> (Bool, [String], [Double], [String]) {
    let names: [UInt32: String] = [10: "wide", 11: "b", 12: "a"]
    guard case .planned(let planned, _) = plan else { return (false, ["refused: \(plan)"], [], []) }
    let got = planned.map { names[$0.angle] ?? "?" }
    let want = expected.map { $0["angle"] as! String }
    var misses: [String] = []
    var errors: [Double] = []
    var limited: [String] = []
    if got != want { misses.append("angles \(got) against \(want)") }
    let tau: Ticks = 38_400 + 30_000 + 20_000
    for (index, row) in expected.enumerated() where index < planned.count {
        let start = planned[index].start
        if start % 20_000 != 0 { misses.append("shot \(index) at tick \(start) is off the frame grid") }
        guard let onset = row["onset_ticks"] as? Int else {
            if start != 0 { misses.append("shot \(index) starts at \(start), not the range's start") }
            continue
        }
        let target = Ticks(onset) - t(lead)
        let error = Double(start - target) / 600
        errors.append(error)
        let angle = got.count > index ? got[index] : "?"
        if abs(start - target) > tau {
            if variant == namedLimit.variant, index == namedLimit.shot, angle == namedLimit.angle,
               start - target > tau, start - target <= namedLimit.lateTicks {
                limited.append(String(format: "shot %d (%@) at %.1f ms, SW-S4's named limit (≤ 165.5 ms)",
                                      index, angle, error))
            } else {
                misses.append(String(format: "shot %d (%@) at %.1f ms from onset − lead", index,
                                     angle, error))
            }
        }
    }
    return (misses.isEmpty, misses, errors, limited)
}

if mode == "spike" || mode == "runs" || wanted("R6") {
    guard let folder = fturns,
          let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
          let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else {
        if mode == "spike" {
            print("spike-error no F-TURNS manifest")
            exit(1)
        }
        print("  skip R6 F-TURNS absent (say -v Samantha or Daniel missing)")
        exit(0)
    }
    let variants = (manifest["variants"] as! [[String: Any]]).map {
        Variant(name: $0["name"] as! String, micA: $0["mic_a"] as! String, micB: $0["mic_b"] as! String)
    }
    let expected = manifest["expected_shots"] as! [[String: Any]]
    var inputs: [(Variant, S.Input)] = []
    for variant in variants {
        guard let document = document(for: variant, manifest: manifest, folder: folder),
              let read = S.read(from: document, clips: [20, 21, 22, 23, 24, 25], pairing: nil,
                                range: nil, settings: S.Settings())
        else {
            check("R6", "\(variant.name): the document opens and reads", false)
            continue
        }
        inputs.append((variant, read))
    }
    if mode == "runs" {
        // A diagnostic: each variant's label runs at the defaults, and each
        // microphone's P and F.
        for (variant, read) in inputs {
            for mic in read.microphones {
                var speech: [Double] = []
                var quiet: [Double] = []
                for k in mic.level.indices where mic.covered[k] {
                    if mic.voice[k] >= 0.5 { speech.append(mic.level[k]) } else { quiet.append(mic.level[k]) }
                }
                print("runs \(variant.name) mic \(mic.track) P \(S.percentile(speech, 0.9) ?? .nan) "
                      + "F \(S.percentile(quiet, 0.1) ?? .nan)")
            }
            let labels = S.labels(read.microphones, settings: read.settings)
            let line = S.runs(labels).map { run -> String in
                let name: String
                switch run.label {
                case .nobody: name = "-"
                case .crosstalk: name = "X"
                case .person(let m): name = m == 14 ? "A" : "B"
                }
                return String(format: "%@%.2f+%.2f", name, Double(run.start) / 100,
                              Double(run.end - run.start) / 100)
            }
            print("runs \(variant.name) " + line.joined(separator: " "))
        }
        exit(0)
    }
    if mode == "spike" {
        for bleed in [9.0, 12, 15, 18, 21] {
            for dominance in [4.0, 6, 8, 10, 12] {
                for margin in [3.0, 6, 9] {
                    var settings = S.Settings()
                    settings.bleedDB = bleed
                    settings.dominanceDB = dominance
                    settings.floorMarginDB = margin
                    for (variant, read) in inputs {
                        let input = S.Input(
                            from: read.from, to: read.to, fps: read.fps, angles: read.angles,
                            microphones: read.microphones, pairing: read.pairing,
                            problems: read.problems, clipCount: read.clipCount, settings: settings)
                        let (good, misses, errors, limited) = score(
                            S.plan(input), expected: expected, lead: settings.lead, variant: variant.name)
                        let row: [String: Any] = [
                            "bleed_db": bleed, "dominance_db": dominance, "floor_margin_db": margin,
                            "variant": variant.name, "pass": good, "misses": misses, "limited": limited,
                            "errors_ms": errors.map { ($0 * 10).rounded() / 10 }]
                        let json = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                        print("spike " + String(data: json, encoding: .utf8)!)
                    }
                }
            }
        }
        print("spike-done \(inputs.count) variants")
        exit(0)
    }
    for (variant, read) in inputs {
        let plan = S.plan(read)
        let (good, misses, errors, limited) = score(plan, expected: expected, lead: read.settings.lead,
                                                    variant: variant.name)
        let worst = errors.map(abs).max() ?? 0
        note("R6", "\(variant.name): \(errors.count) cuts, worst \(String(format: "%.1f", worst)) ms, "
                + "errors \(errors.map { String(format: "%.1f", $0) }.joined(separator: " "))"
                + (limited.isEmpty ? "" : "; limited: " + limited.joined(separator: "; ")))
        check("R6", "\(variant.name): the shot angles equal the manifest's and every cut is on the "
                + "frame grid within τ = 147.3 ms of onset − lead (b24_f45's shot 17 to SW-S4's "
                + "named limit, 165.5 ms)", good,
              misses.joined(separator: "; "))
    }
}
