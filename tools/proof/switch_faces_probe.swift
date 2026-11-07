import Foundation

// Switch by Speaker's faces mode probe (road map "creator-jobs" SW8, spec §11
// SW-81…SW-84, SW-87), compiled with app/Sources through swift_build.
// Arguments: `rows [rows]`. Rows print one "ok"/"FAIL" line each, the row's
// name first (P1–P6), for switch_faces_probe.py to score; every expected value
// is worked by hand here, never by the code under test.

let arguments = CommandLine.arguments
let only: Set<String> = arguments.count > 2 && !arguments[2].isEmpty
    ? Set(arguments[2].split(separator: ",").map(String.init)) : []
func wanted(_ row: String) -> Bool { only.isEmpty || only.contains(row) }

func check(_ row: String, _ name: String, _ good: Bool, _ detail: String = "") {
    print((good ? "  ok   " : "  FAIL ") + row + " " + name + (detail.isEmpty ? "" : ": " + detail))
}

typealias S = SpeakerSwitch
typealias F = FaceActivity
let fps = Fps(num: 30, den: 1)
let second: Ticks = 600_000
func t(_ seconds: Double) -> Ticks { Ticks((seconds * 600_000).rounded()) }
func near(_ a: Double?, _ b: Double?, _ tolerance: Double = 1e-12) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (x?, y?): return abs(x - y) <= tolerance
    default: return false
    }
}
func near(_ a: [Double?], _ b: [Double?]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { near($0, $1) }
}

func face(_ w: Float, _ h: Float, gap: Float, width: Float, x: Float = 0.1) -> AnalysisFaces.Face {
    AnalysisFaces.Face(x: x, y: 0.2, width: w, height: h, confidence: 0.9, roll: 0, yaw: 0,
                       mouthGap: gap, mouthWidth: width)
}

// MARK: - P1 the largest face and the opening

if wanted("P1") {
    let small = face(0.1, 0.1, gap: 0.01, width: 0.1, x: 0.1)
    let large = face(0.3, 0.3, gap: 0.06, width: 0.3, x: 0.6)
    let sample = AnalysisFaces.Sample(pts: 0, faces: [small, large])
    let picked = F.largest(sample.faces)
    check("P1", "the larger face, second in CJ-31's order, is the person",
          picked == large, "\(String(describing: picked))")
    let want = Double(Float(0.06)) / Double(Float(0.3))
    check("P1", "the opening is the largest face's gap over its width (0.2, not the first face's 0.1)",
          near(F.opening(sample), want), "\(String(describing: F.opening(sample)))")
    let equal = [face(0.2, 0.2, gap: 0.02, width: 0.2, x: 0.1), face(0.2, 0.2, gap: 0.08, width: 0.2, x: 0.5)]
    check("P1", "equal areas: the first in order",
          F.largest(equal) == equal[0], "\(String(describing: F.largest(equal)))")
    let nils = [
        F.opening(AnalysisFaces.Sample(pts: 0, faces: [face(0.3, 0.3, gap: .nan, width: 0.3)])),
        F.opening(AnalysisFaces.Sample(pts: 0, faces: [face(0.3, 0.3, gap: 0.05, width: 0)])),
        F.opening(AnalysisFaces.Sample(pts: -1, faces: [face(0.3, 0.3, gap: 0.05, width: 0.3)])),
        F.opening(AnalysisFaces.Sample(pts: 0, faces: [])),
    ]
    check("P1", "a NaN gap, a width of 0, pts −1 and no face each give nil",
          nils.allSatisfy { $0 == nil }, "\(nils)")
}

// MARK: - P2 activities

if wanted("P2") {
    check("P2", "halfWidth: 2 at 10 a second, 1 at 5",
          F.halfWidth(rate: 10) == 2 && F.halfWidth(rate: 5) == 1,
          "\(F.halfWidth(rate: 10)), \(F.halfWidth(rate: 5))")
    let alternating: [Double?] = [0, 1, 0, 1, 0, 1, 0]
    let two = F.activities(alternating, half: 2)
    // Index 0 sees [0,1,0]: std √2/3; 1 sees [0,1,0,1]: 0.5; 2…4 see five: mean 0.4 or 0.6,
    // variance 0.24; 5 sees [0,1,0,1] again; 6 [1,0,1]... sees indices 4…6: [0,1,0].
    let r = (2.0).squareRoot() / 3, f = (0.24).squareRoot()
    let wantTwo: [Double?] = [r, 0.5, f, f, f, 0.5, r]
    check("P2", "the exact population std at half 2, the edges clipped",
          near(two, wantTwo), "\(two)")
    let one = F.activities(alternating, half: 1)
    let wantOne: [Double?] = [0.5, r, r, r, r, r, 0.5]
    check("P2", "the exact population std at half 1, the edges clipped",
          near(one, wantOne), "\(one)")
    let sparse = F.activities([nil, 0.5, nil, nil, 0.2, nil, 0.4], half: 1)
    let wantSparse: [Double?] = [nil, nil, nil, nil, nil, 0.1, nil]
    check("P2", "fewer than two values in the window give nil; two give their std",
          near(sparse, wantSparse), "\(sparse)")
    check("P2", "all nil gives nil", F.activities([nil, nil, nil], half: 2).allSatisfy { $0 == nil })
}

// MARK: - P3 the label

if wanted("P3") {
    func label(_ speech: Bool, _ values: [Double?]) -> S.Label {
        F.label(speech: speech,
                activities: values.enumerated().map { (angle: UInt32($0.offset + 1), activity: $0.element) },
                ratio: F.ratio, floor: F.floor)
    }
    let quiet = label(false, [0.375, 0.01])
    check("P3", "no speech is nobody despite activity", quiet == .nobody, "\(quiet)")
    let exact = label(true, [0.375, 0.25])
    let under = label(true, [0.3725, 0.25])
    check("P3", "top exactly 1.5× the next is the person; 1.49× is crosstalk",
          exact == .person(1) && under == .crosstalk, "\(exact) | \(under)")
    let second = label(true, [0.25, 0.375])
    check("P3", "the top angle wins wherever it is in the order", second == .person(2), "\(second)")
    let atFloor = label(true, [0.02, nil])
    let overFloor = label(true, [0.0201, nil])
    check("P3", "top == floor 0.02 is crosstalk; just above is the person",
          atFloor == .crosstalk && overFloor == .person(1), "\(atFloor) | \(overFloor)")
    let alone = label(true, [nil, 0.1])
    check("P3", "a single valid angle is the person", alone == .person(2), "\(alone)")
    let none = label(true, [nil, nil])
    check("P3", "all nil is nobody", none == .nobody, "\(none)")
    check("P3", "the constants: window 0.5 s, ratio 1.5, floor 0.02, faces min_shot 3 s",
          F.window == 0.5 && F.ratio == 1.5 && F.floor == 0.02 && F.minShot == 3
            && S.Settings().faceRatio == 1.5 && S.Settings().faceFloor == 0.02)
}

// MARK: - P4 the mode, its pairing and the plan

func video(_ id: UInt32) -> MediaSnapshot {
    MediaSnapshot(id: id, path: "/v\(id).mov", kind: .video, duration: 20 * second, width: 1920,
                  height: 1080, hasVideo: true, hasAudio: false)
}
func sound(_ id: UInt32) -> MediaSnapshot {
    MediaSnapshot(id: id, path: "/a\(id).wav", kind: .audio, duration: 20 * second, hasVideo: false,
                  hasAudio: true)
}
func clip(_ id: UInt32, track: UInt32, media: UInt32) -> ClipSnapshot {
    ClipSnapshot(id: id, track: track, start: 0, duration: 20 * second,
                 source: .media(id: media, in: 0, reversed: false))
}
func project(_ tracks: [UInt32], _ media: [MediaSnapshot], _ clips: [ClipSnapshot]) -> ProjectSnapshot {
    ProjectSnapshot(media: media, tracks: tracks.map { TrackSnapshot(id: $0) }, clips: clips)
}
func whole(_ track: UInt32, _ to: Double) -> S.AngleTrack {
    S.AngleTrack(track: track, clips: [S.Span(clip: track * 10, start: 0, end: t(to))])
}
func shot(_ angle: UInt32, _ a: Double, _ b: Double) -> S.Shot { S.Shot(angle: angle, start: t(a), end: t(b)) }
/// A microphone speaking in `spans` (seconds) over `count` steps.
func mic(_ track: UInt32, _ spans: [(Double, Double)], count: Int) -> S.Microphone {
    var level = [Double](repeating: -60, count: count)
    var voice = [Float](repeating: 0.1, count: count)
    for (a, b) in spans {
        for k in Int((a * 100).rounded())..<min(count, Int((b * 100).rounded())) {
            level[k] = -20
            voice[k] = 0.9
        }
    }
    return S.Microphone(track: track, level: level, voice: voice,
                        covered: [Bool](repeating: true, count: count))
}
/// An activity series: `value` inside `spans` (seconds), `rest` elsewhere.
func activity(_ spans: [(Double, Double)], _ value: Double, rest: Double?, count: Int) -> [Double?] {
    var out = [Double?](repeating: rest, count: count)
    for (a, b) in spans {
        for k in Int((a * 100).rounded())..<min(count, Int((b * 100).rounded())) { out[k] = value }
    }
    return out
}
func input(to: Double, angles: [S.AngleTrack], mics: [S.Microphone], pairing: S.Pairing,
           faces: [S.FaceAngle] = [], problems: [String] = []) -> S.Input {
    S.Input(from: 0, to: t(to), fps: fps, angles: angles, microphones: mics, pairing: pairing,
            problems: problems, clipCount: 0, settings: S.Settings(), faces: faces)
}
func sp(_ mic: UInt32?, _ angle: UInt32?) -> S.Speaker { S.Speaker(mic: mic, angle: angle) }

if wanted("P4") {
    // SW-83's defaults: one file (4) and two cameras (1, 2), then three cameras (1, 2, 3).
    let two = project([1, 2, 4], [video(1), video(2), sound(4)],
                      [clip(10, track: 1, media: 1), clip(20, track: 2, media: 2),
                       clip(40, track: 4, media: 4)])
    let d2 = S.defaults(selection: two.clips, in: two)
    let three = project([1, 2, 3, 4], [video(1), video(2), video(3), sound(4)],
                        [clip(10, track: 1, media: 1), clip(20, track: 2, media: 2),
                         clip(30, track: 3, media: 3), clip(40, track: 4, media: 4)])
    let d3 = S.defaults(selection: three.clips, in: three)
    check("P4", "one microphone, two angles: every angle with it, front first, no wide, faces mode",
          d2.pairing == S.Pairing(speakers: [sp(4, 2), sp(4, 1)], wide: nil)
            && S.mode(d2.pairing) == .faces, "\(d2.pairing)")
    check("P4", "one microphone, three angles: three speakers, no wide, faces mode",
          d3.pairing == S.Pairing(speakers: [sp(4, 3), sp(4, 2), sp(4, 1)], wide: nil)
            && S.mode(d3.pairing) == .faces, "\(d3.pairing)")

    // withoutWide's three cases.
    let named = S.withoutWide(S.Pairing(speakers: [sp(1, 11), sp(1, 12)], wide: 12))
    check("P4", "one mic, angles A and B, wide B: [(M, A)] wide B, microphones mode",
          named == S.Pairing(speakers: [sp(1, 11)], wide: 12) && S.mode(named) == .microphones,
          "\(named)")
    let before = S.plan(input(to: 10, angles: [whole(11, 10), whole(12, 10)],
                              mics: [mic(1, [(3, 6)], count: 1000)], pairing: named))
    check("P4", "…and it plans as before SW8: the wide, then A 0.2 s before the turn",
          before == .planned(shots: [shot(12, 0, 2.8), shot(11, 2.8, 10)], added: 2), "\(before)")
    let wideC = S.withoutWide(S.Pairing(speakers: [sp(1, 11), sp(1, 12), sp(1, 13)], wide: 13))
    check("P4", "three angles with wide C: two face speakers, faces mode",
          wideC == S.Pairing(speakers: [sp(1, 11), sp(1, 12)], wide: 13) && S.mode(wideC) == .faces
            && S.faceSpeakers(wideC) == [sp(1, 11), sp(1, 12)]
            && S.facePairing(wideC) == S.Pairing(speakers: [sp(11, 11), sp(12, 12)], wide: 13),
          "\(wideC)")
    let twoMics = S.Pairing(speakers: [sp(1, 11), sp(2, 12)], wide: 12)
    check("P4", "two microphones with a speaker's angle the wide: unchanged",
          S.withoutWide(twoMics) == twoMics && S.mode(twoMics) == .microphones)

    // A mixed shared microphone stays SW-24's refusal.
    let mixed = S.plan(input(
        to: 10, angles: [whole(11, 10), whole(12, 10), whole(13, 10)],
        mics: [mic(1, [(1, 4)], count: 1000), mic(2, [(5, 8)], count: 1000)],
        pairing: S.Pairing(speakers: [sp(1, 11), sp(1, 12), sp(2, 13)], wide: nil)))
    let sentence = "Track 1 is the microphone for 2 speakers; each person needs their own microphone."
    check("P4", "a shared microphone beside another is still refused in SW-24's sentence",
          mixed == .refused([sentence]), "\(mixed)")

    // The plan over synthetic series: A speaks 3–6 s, B 7–10 s, both 11.5–13 s, A 13.5–14 s
    // (under min_turn); the wide's two faces move most while B speaks. Range 0–15 s.
    let count = 1500
    let pairing = S.Pairing(speakers: [sp(1, 11), sp(1, 12)], wide: 13)
    let angles = [whole(11, 15), whole(12, 15), whole(13, 15)]
    let faces = [
        S.FaceAngle(track: 11, activity: activity([(3, 6), (11.5, 13), (13.5, 14)], 0.1, rest: 0.01, count: count)),
        S.FaceAngle(track: 12, activity: activity([(7, 10), (11.5, 13)], 0.1, rest: 0.01, count: count)),
        S.FaceAngle(track: 13, activity: activity([(7, 10)], 0.5, rest: 0.01, count: count)),
    ]
    let planned = S.plan(input(
        to: 15, angles: angles, mics: [mic(1, [(3, 6), (7, 10), (11.5, 13), (13.5, 14)], count: count)],
        pairing: pairing, faces: faces))
    let want: [S.Shot] = [shot(13, 0, 2.8), shot(11, 2.8, 6.8), shot(12, 6.8, 11.3), shot(13, 11.3, 15)]
    check("P4", "plan: the wide, then each turn − lead snapped, crosstalk to the wide, a 0.5 s turn "
            + "starting nothing, the wide not contesting",
          planned == .planned(shots: want, added: 4), "\(planned)")
}

// MARK: - P5 the pending and no-face refusals, in order

if wanted("P5") {
    let pending = "The camera on track 13 is still being analyzed — its faces have not been found "
        + "yet. Try again in a moment."
    let count = 1000
    let got = S.plan(input(
        to: 10, angles: [whole(11, 10), whole(12, 5), whole(13, 10)],
        mics: [mic(1, [], count: count)],
        pairing: S.Pairing(speakers: [sp(1, 11), sp(1, 12), sp(1, 13)], wide: nil),
        faces: [S.FaceAngle(track: 11, activity: activity([(1, 2)], 0.1, rest: nil, count: count)),
                S.FaceAngle(track: 12, activity: [Double?](repeating: nil, count: count)),
                S.FaceAngle(track: 13, activity: [])],
        problems: [pending]))
    let want = [
        pending,
        "The microphone on track 1 has no speech between 00:00:00:00 and 00:00:10:00, so it never "
            + "says who is talking.",
        "The camera on track 12 shows no face whose mouth can be read between 00:00:00:00 and "
            + "00:00:10:00, so it never says who is talking.",
    ]
    check("P5", "read's pending, then no speech, then the camera with no readable mouth; no "
            + "shared-microphone refusal and none for the unread angle",
          got == .refused(want), "\(got)")
}

// MARK: - P6 source(atClip:) and faceSeries

if wanted("P6") {
    let media = video(1)
    func times(_ c: ClipSnapshot) -> AnalysisClipTimes { AnalysisClipTimes(clip: c, media: media, map: nil) }
    let trimmed = times(ClipSnapshot(id: 1, track: 1, start: t(4), duration: t(5),
                                     source: .media(id: 1, in: t(2), reversed: false)))
    let fast = times(ClipSnapshot(id: 2, track: 1, start: 0, duration: t(4),
                                  source: .media(id: 1, in: t(1), reversed: false), speed: 2))
    let back = times(ClipSnapshot(id: 3, track: 1, start: 0, duration: t(5),
                                  source: .media(id: 1, in: t(1), reversed: true)))
    let points = [
        trimmed.source(atClip: t(1)) == t(3),
        fast.source(atClip: t(1)) == t(3),
        back.source(atClip: t(2)) == t(17),
    ]
    let ticks: [Ticks] = [0, 1, 12_345, t(1.5), t(3)]
    let trips = [trimmed, fast, back].allSatisfy { clip in
        ticks.allSatisfy { clip.clipTime(ofSource: clip.source(atClip: $0)) == $0 }
    }
    check("P6", "source(atClip:): trimmed 1 s → 3 s, speed 2 1 s → 3 s, reversed 2 s → 17 s of 20",
          points.allSatisfy { $0 }, "\(points)")
    check("P6", "source(atClip:) round-trips through clipTime(ofSource:) trimmed, at speed 2 and "
            + "reversed", trips)

    let grid = AnalysisGrid(samplesPerSecond: 10, duration: 20 * second)
    let x = S.FaceClip(span: S.Span(clip: 1, start: 0, end: t(10)),
                       times: times(ClipSnapshot(id: 1, track: 1, start: 0, duration: t(10),
                                                 source: .media(id: 1, in: 0, reversed: false))),
                       grid: grid, duration: 20 * second,
                       activity: [Double?](repeating: 0.1, count: grid.count))
    // Y starts later and plays the media from 12 s, so its 8 s past its start is 20 s, the end.
    var yActivity = [Double?](repeating: 0.2, count: grid.count)
    yActivity[grid.index(of: t(13))] = 0.3
    let y = S.FaceClip(span: S.Span(clip: 2, start: t(5), end: t(15)),
                       times: times(ClipSnapshot(id: 2, track: 1, start: t(5), duration: t(10),
                                                 source: .media(id: 1, in: t(12), reversed: false))),
                       grid: grid, duration: 20 * second, activity: yActivity)
    let series = S.faceSeries([x, y], from: 0, count: 1600)
    let at = { (seconds: Double) in series[Int(seconds * 100)] }
    check("P6", "faceSeries: X alone at 2 s, the later-starting Y where both cover (6 s), its "
            + "nearest sample (6.0 s → source 13 s), past Y's media end nil, off every clip nil",
          at(2) == 0.1 && at(6) == 0.3 && at(9.5) == 0.2 && at(13.5) == nil && at(15.5) == nil,
          "2 s \(String(describing: at(2))), 6 s \(String(describing: at(6))), 9.5 s "
            + "\(String(describing: at(9.5))), 13.5 s \(String(describing: at(13.5))), 15.5 s "
            + "\(String(describing: at(15.5)))")
}
