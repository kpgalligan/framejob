// Road map "creator-jobs" CO2b (spec §11 CO-22): the probe of `co2b_proof.py`, compiled as
// `main.swift` over `app/Sources` through `swift_build.build()` with `FRAMEJOB_DEV_TOOLS`.
//
// `co2b-probe <request.json>`: the request names `movie` (a 640 × 360, 30 fps, 10 s file the
// fixtures' media point at) and `scratch` (an empty folder, the P2 cache). It prints one JSON
// object, `{"rows": [{"id", "pass", "detail"}]}`, on stdout.
//
// - P1 (CO-22 (a)) the windows and the need rule over a 300-frame 30 fps media: a frame-aligned
//   forward window (in 1 s, 2 s), a ×0.5 window (in 0, 4 s), a reversed one (in 0, 2 s), a
//   `freeze_frame` hold (its still is one source frame) and a direct zero-length window
//   [1,210,000, 1,210,000) (60…61), and one at the media's end (in 8 s,
//   2 s): `CutoutWants.windows` and `need` against the values worked by hand; and at every
//   composition frame and the last tick of each segment, the indices CO-24's lookup asks — the
//   frame shown at or before the query and the query's own index — lie inside the need.
// - P2 (CO-22 (c)) `CutoutWants.kept` over five open requests of one media whose need is
//   30…90: a running one meeting the need kept; an ended one not; a running one outside it
//   dropped; a queued one wholly inside it kept; a queued one only overlapping it (80…100)
//   dropped. `CutoutWants.requests` over an empty cache then wants the two kept plus one new
//   request holding 30…39, 51…59 and 71…90 — the needed part of the dropped queued one included,
//   neither kept one's indices.

import Foundation

var rows: [[String: Any]] = []

func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}

func finish() -> Never {
    let data =
        (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data()
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

// `co2b-probe mask <pack> <slot> <out>`: the slot's mask decompressed (`MaskPack.mask`), its
// bytes written raw; prints `{"width", "height"}` (W6 reads it).
if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "mask" {
    let args = CommandLine.arguments
    var answer: [String: Any] = ["ok": false]
    if let pack = try? MaskPack(contentsOf: URL(fileURLWithPath: args[2])),
        let slot = Int(args[3]), let bytes = try? pack.mask(slot: slot),
        (try? Data(bytes).write(to: URL(fileURLWithPath: args[4]))) != nil
    {
        answer = ["ok": true, "width": pack.width, "height": pack.height]
    }
    let data = (try? JSONSerialization.data(withJSONObject: answer)) ?? Data()
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

guard CommandLine.arguments.count > 1,
    let requestData = FileManager.default.contents(atPath: CommandLine.arguments[1]),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
    let movie = request["movie"] as? String, let scratch = request["scratch"] as? String
else {
    row("P1", false, "the request could not be read")
    row("P2", false, "the request could not be read")
    finish()
}

let second: Ticks = 600_000
let frameTicks: Ticks = 20_000
let cut: [String: Any] = [
    "subject": "person", "quality": "standard", "background": "remove", "edge": 0.0,
    "feather": 0.0,
]

func project(_ clips: [[String: Any]]) throws -> ReelProject {
    let fixture: [String: Any] = [
        "canvas": ["width": 640, "height": 360, "fps": [30, 1]],
        "media": [[
            "id": 5, "path": movie, "kind": "video", "duration": Int(10 * second),
            "width": 640, "height": 360, "fps": [30, 1], "has_video": true, "has_audio": false,
        ]],
        "tracks": [["id": 2, "name": "Track 1"]],
        "clips": clips, "next_id": 100,
    ]
    let data = try JSONSerialization.data(withJSONObject: fixture, options: [.sortedKeys])
    return try ReelProject.from(json: String(decoding: data, as: UTF8.self))
}

func mediaClip(
    start: Ticks = 0, duration: Ticks, sourceIn: Ticks = 0, speed: Double? = nil,
    reversed: Bool = false
) -> [String: Any] {
    var clip: [String: Any] = [
        "id": 11, "track": 2, "start": start, "duration": duration,
        "source": ["kind": "media", "media": 5, "in": sourceIn, "reversed": reversed],
        "video": ["cutout": cut],
    ]
    if let speed { clip["speed"] = speed }
    return clip
}

func applied(_ project: ReelProject, _ op: ReelOp) throws -> ReelProject {
    switch try project.applying(op) {
    case .applied(let next): return next
    case .identity: throw ReelCoreError(message: "\(op.name) was an identity")
    case .refused(let refusal): throw ReelCoreError(message: refusal.reason)
    }
}

func spell(_ windows: [CutoutWindow]) -> String {
    windows.map { "[\($0.lower), \($0.upper))" }.joined(separator: " ")
}

// ---- P1 ---------------------------------------------------------------------

do {
    var problems: [String] = []
    var said: [String] = []
    // (name, project, the windows by hand, each window's need by hand)
    var cases: [(String, ReelProject, [(Ticks, Ticks)], [ClosedRange<Int>])] = []
    do {
        cases.append(("forward", try project([mediaClip(duration: 2 * second, sourceIn: second)]),
                      [(second, 3 * second)], [30...90]))
        cases.append(("x0.5", try project([mediaClip(duration: 4 * second, speed: 0.5)]),
                      [(0, 2 * second)], [0...60]))
        cases.append(("reversed", try project([mediaClip(duration: 2 * second, reversed: true)]),
                      [(8 * second, 10 * second)], [240...299]))
        let plain = try project([mediaClip(duration: 4 * second)])
        // The hold of frame 60 for 1 s after 2 s — `freeze_frame`'s still is ONE source frame,
        // [1,200,000, 1,220,000), whose need is 60…61 (index(of: 1,219,999) rounds to 61) —
        // between the clip's two halves.
        cases.append(("freeze", try applied(
            plain, .freezeFrame(clip: 11, at: 2 * second, duration: second)),
            [(0, 2 * second), (2 * second, 2 * second + frameTicks), (2 * second, 4 * second)],
            [0...60, 60...61, 60...120]))
        cases.append(("end", try project([mediaClip(duration: 2 * second, sourceIn: 8 * second)]),
                      [(8 * second, 10 * second)], [240...299]))
    } catch {
        problems.append("a case did not build: \(error)")
    }
    for (name, project, hand, needs) in cases {
        guard let plan = project.plan, let media = project.snapshot.media(5) else {
            problems.append("\(name): no plan")
            continue
        }
        let grid = AnalysisGrid(media: media)
        let windows = CutoutWants.windows(plan: plan, snapshot: project.snapshot, range: nil)
        let got = windows.map { ($0.lower, $0.upper) }
        if got.count != hand.count || zip(got, hand).contains(where: { $0 != $1 }) {
            problems.append("\(name): windows \(spell(windows)), not \(hand)")
        }
        let need = windows.map { CutoutWants.need($0, grid: grid) }
        if need != needs {
            problems.append("\(name): need \(need), not \(needs)")
        }
        // Every query CO-24's lookup makes of these segments lies inside the need.
        let lookup = CutoutPlan(project: project)
        var asked = 0
        for track in plan.videoTracks {
            for segment in track.segments where segment.duration > 0 {
                var times = Array(stride(
                    from: segment.start, to: segment.start + segment.duration, by: Int(frameTicks)))
                times.append(segment.start + segment.duration - 1)
                for t in times {
                    let s = CutoutLookup.sourceTick(segment, at: t)
                    let query = lookup.pivots[segment.clip].map { ReverseMirror.mirrored(s, about: $0) - 1 } ?? s
                    let shown = min(grid.lastIndex, max(0, Int(query / frameTicks)))
                    let index = grid.index(of: query)
                    asked += 1
                    let union = AnalysisStore.merged(need)
                    if !union.contains(where: { $0.contains(shown) && $0.contains(index) }) {
                        problems.append(
                            "\(name): t \(t) asks frame \(shown) and index \(index), outside "
                                + "\(union)")
                    }
                }
            }
        }
        said.append("\(name) \(spell(windows)) → \(need) (\(asked) queries inside)")
    }
    if let media = (try? project([]))?.snapshot.media(5) {
        let zero = CutoutWants.need(
            CutoutWindow(clip: 11, media: 5, lower: 1_210_000, upper: 1_210_000),
            grid: AnalysisGrid(media: media))
        if zero != 60...61 {
            problems.append("a zero-length window at 1,210,000: need \(zero), not 60...61")
        }
        said.append("zero-length [1210000, 1210000) → \(zero)")
    } else {
        problems.append("the empty project's media did not decode")
    }
    row("P1", problems.isEmpty && cases.count == 5,
        problems.isEmpty ? said.joined(separator: "; ") : problems.prefix(6).joined(separator: "; "))
}

// ---- P2 ---------------------------------------------------------------------

do {
    var problems: [String] = []
    let cacheDir = URL(fileURLWithPath: scratch, isDirectory: true)
    try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    let url = URL(fileURLWithPath: movie)
    if let project = try? project([mediaClip(duration: 2 * second, sourceIn: second)]),
        let media = project.snapshot.media(5),
        let stamp = AnalysisStamp.make(
            kind: .masks, media: media, url: url, input: nil, fullRange: false)
    {
        func open(_ ranges: [ClosedRange<Int>]) -> AnalysisRequest {
            AnalysisRequest(
                kind: .masks, cacheDir: cacheDir, media: media, url: url, stamp: stamp, input: nil,
                ranges: ranges)
        }
        let runningMeets = open([40...50])
        let ended = open([30...40])
        let runningOutside = open([100...120])
        let queuedInside = open([60...70])
        let queuedOverlap = open([80...100])
        let states: [AnalysisRequest: CutoutRunState] = [
            runningMeets: .running, ended: .ended, runningOutside: .running,
            queuedInside: .queued, queuedOverlap: .queued,
        ]
        let need: [UInt32: [ClosedRange<Int>]] = [5: [30...90]]
        let kept = CutoutWants.kept(
            previous: [runningMeets, ended, runningOutside, queuedInside, queuedOverlap],
            need: need, state: { states[$0] ?? .ended })
        let cases: [(String, AnalysisRequest, Bool)] = [
            ("a running request meeting the need", runningMeets, true),
            ("an ended request", ended, false),
            ("a running request outside the need", runningOutside, false),
            ("a queued request wholly inside the need", queuedInside, true),
            ("a queued request only overlapping the need (80…100)", queuedOverlap, false),
        ]
        var said: [String] = []
        for (what, request, want) in cases {
            let got = kept.contains(request)
            said.append("\(what) \(got ? "kept" : "dropped")")
            if got != want { problems.append("\(what): \(got ? "kept" : "dropped")") }
        }
        let windows = project.plan.map {
            CutoutWants.windows(plan: $0, snapshot: project.snapshot, range: nil)
        } ?? []
        let (requests, failures) = CutoutWants.requests(
            windows: windows, snapshot: project.snapshot, urls: [5: url], cacheDir: cacheDir,
            keeping: kept)
        let fresh = requests.filter { !kept.contains($0) }
        let wantFresh: [ClosedRange<Int>] = [30...39, 51...59, 71...90]
        if !failures.isEmpty { problems.append("failures \(failures)") }
        if Array(requests.prefix(kept.count)) != kept {
            problems.append("the kept requests are not wanted first: \(requests.map(\.ranges))")
        }
        if fresh.count != 1 || fresh.first?.ranges != wantFresh {
            problems.append("the new request \(fresh.map(\.ranges)), not \(wantFresh)")
        }
        said.append("the new request \(fresh.map(\.ranges))")
        row("P2", problems.isEmpty, problems.isEmpty
            ? said.joined(separator: "; ") : problems.joined(separator: "; "))
    } else {
        row("P2", false, "the fixture's media or stamp could not be made from \(movie)")
    }
}

finish()
