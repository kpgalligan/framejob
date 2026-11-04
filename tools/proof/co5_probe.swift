// Road map "creator-jobs" CO5 (spec §11 CO-53, CO-55): the planner probe of `co5_proof.py`'s
// P1, compiled as `main.swift` over every `app/Sources` file but `main.swift` with
// `FRAMEJOB_DEV_TOOLS` through `swift_build.build()`. No app.
//
// `co5-probe` prints one JSON object, `{"rows": [{"id", "pass", "detail"}]}`, on stdout. Every
// row is P1's, each a claim about `BehindSubjectPlan` read against projects made through the
// core (`ReelProject.from(json:)`):
// - the pick: the named clip; else the front-most selected candidate; else the front-most with
//   a base cutout; else the front-most;
// - the title's span, min(4 s, the clip's end − at);
// - the new track's index: above the clip's track and the unbroken run of matte tracks in front
//   of it — `[V, M→V]` 2, `[V, M1→V, M2]` 3, `[V, M→V, T]` 2;
// - the three refusals' sentences, word for word;
// - three ops with a base cutout, four without, and what they make once applied (the track's
//   id and name, the title's id, `behind_subject`, the clip's `cutout {background: keep}`);
// - `isCutBySubject`: true for the planned title once applied, false for a flagged clip with no
//   subject behind it, nil for a clip with no layer.

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

let second: Ticks = 600_000

func media(_ id: Int, kind: String = "video") -> [String: Any] {
    [
        "id": id, "path": "/fixtures/camera-\(id).mov", "kind": kind,
        "duration": 60 * Int(second), "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true,
    ]
}

func clip(_ id: Int, track: Int, start: Ticks = 0, seconds: Int = 6, cutout: Bool = false)
    -> [String: Any]
{
    var video: [String: Any] = [:]
    if cutout { video["cutout"] = [String: Any]() }
    return [
        "id": id, "track": track, "start": start, "duration": seconds * Int(second),
        "source": ["kind": "media", "media": 1, "in": 0], "video": video,
    ]
}

func track(_ id: Int, matte: String? = nil, hidden: Bool = false) -> [String: Any] {
    var t: [String: Any] = ["id": id, "name": "Track \(id)"]
    if let matte { t["matte"] = matte }
    if hidden { t["hidden"] = true }
    return t
}

func project(tracks: [[String: Any]], clips: [[String: Any]]) throws -> ReelProject {
    let fixture: [String: Any] = [
        "canvas": ["width": 1920, "height": 1080, "fps": [30, 1]],
        "media": [media(1)], "tracks": tracks, "clips": clips, "next_id": 100,
    ]
    let data = try JSONSerialization.data(withJSONObject: fixture, options: [.sortedKeys])
    return try ReelProject.from(json: String(decoding: data, as: UTF8.self))
}

func planned(
    _ p: ReelProject, at: Ticks, selection: Set<UInt32> = [], clip: UInt32? = nil
) -> BehindSubjectPlan.Plan? {
    if case .success(let plan) = BehindSubjectPlan.plan(
        in: p.snapshot, at: at, selection: selection, clip: clip)
    {
        return plan
    }
    return nil
}

func refusal(_ p: ReelProject, at: Ticks, clip: UInt32? = nil) -> String? {
    if case .failure(let why) = BehindSubjectPlan.plan(
        in: p.snapshot, at: at, selection: [], clip: clip)
    {
        return why.sentence
    }
    return nil
}

do {
    // Three ordinary tracks, back to front 2, 3, 4: clip 11 on 2, 12 (cut out) on 3, 13 on 4.
    let three = try project(
        tracks: [track(2), track(3), track(4)],
        clips: [clip(11, track: 2), clip(12, track: 3, cutout: true), clip(13, track: 4)])
    let picks: [(String, Set<UInt32>, UInt32?, UInt32?)] = [
        ("nothing selected: the front-most with a cutout", [], nil, 12),
        ("11 selected: the front-most selected", [11], nil, 11),
        ("11 and 13 selected: the front-most selected", [11, 13], nil, 13),
        ("clip 11 named over a selection of 13", [13], 11, 11),
    ]
    for (what, selection, named, want) in picks {
        let got = planned(three, at: second, selection: selection, clip: named)?.clip
        row("P1", got == want, "\(what): \(String(describing: got)) (want \(want ?? 0))")
    }
    let uncut = try project(
        tracks: [track(2), track(3), track(4)],
        clips: [clip(11, track: 2), clip(12, track: 3), clip(13, track: 4)])
    let front = planned(uncut, at: second)?.clip
    row("P1", front == 13, "no cutout anywhere: the front-most, \(String(describing: front))")

    // The span: min(4 s, the rest).
    let early = planned(three, at: second)?.duration
    let late = planned(three, at: 3 * second)?.duration
    row(
        "P1", early == 4 * second && late == 3 * second,
        "duration at 1 s of a 6 s clip \(String(describing: early)) (4 s), at 3 s "
            + "\(String(describing: late)) (3 s)")

    // The index above the run of matte tracks in front of the clip's track.
    let indexCases: [(String, [[String: Any]], Int)] = [
        ("[V, M→V]", [track(2), track(3, matte: "alpha")], 2),
        ("[V, M1→V, M2]", [track(2), track(3, matte: "alpha"), track(4, matte: "luma")], 3),
        ("[V, M→V, T]", [track(2), track(3, matte: "alpha"), track(4)], 2),
        ("[V]", [track(2)], 1),
    ]
    for (what, tracks, want) in indexCases {
        let p = try project(tracks: tracks, clips: [clip(11, track: 2, cutout: true)])
        let got = planned(p, at: second)?.trackIndex
        row("P1", got == want, "\(what): track index \(String(describing: got)) (want \(want))")
    }

    // The three sentences, word for word.
    let hiddenMatte = try project(
        tracks: [track(2), track(3, hidden: true), track(4, matte: "alpha")],
        clips: [
            clip(11, track: 2, start: 10 * second), clip(12, track: 3), clip(13, track: 4),
        ])
    let none = refusal(hiddenMatte, at: second)
    row(
        "P1",
        none == "No clip of a video file or picture plays at 600000 on a shown track that is not "
            + "a matte track, so there is no one to put the title behind.",
        "noClip (a clip on a hidden track and one on a matte track): \(none ?? "nil")")
    let hold = refusal(hiddenMatte, at: second, clip: 12)
    row(
        "P1",
        hold == "Clip 12 cannot have a title put behind its subject: it must be a clip of a "
            + "video file or a picture on the timeline, on a shown track that is not a matte "
            + "track.",
        "cannotHold (a clip on a hidden track): \(hold ?? "nil")")
    let notAt = refusal(hiddenMatte, at: second, clip: 11)
    row(
        "P1", notAt == "Clip 11 does not play at 600000: pass an at inside it.",
        "notAt: \(notAt ?? "nil")")

    // Three ops with a cutout, four without, and what they make.
    for (what, base, cut) in [("a cut-out clip", three, true), ("an uncut clip", uncut, false)] {
        guard let plan = planned(base, at: second, clip: 12) else {
            row("P1", false, "\(what): no plan")
            continue
        }
        let ops = BehindSubjectPlan.ops(plan, content: "Hello")
        let names = ops.map(\.name)
        let wantNames =
            ["add_track", "add_text_clip", "set_video"] + (cut ? [] : ["set_video"])
        row(
            "P1", names == wantNames && plan.addsCutout == !cut,
            "\(what): ops \(names), addsCutout \(plan.addsCutout)")
        guard let after = try base.applying(ops).project else {
            row("P1", false, "\(what): the ops did not apply")
            continue
        }
        let s = after.snapshot
        let newTrack = s.tracks.firstIndex { $0.id == plan.track }
        let title = s.clips.first { $0.id == plan.text }
        let camera = s.clips.first { $0.id == 12 }
        let made =
            newTrack == plan.trackIndex && s.tracks[plan.trackIndex].name == "Behind Subject"
            && plan.track == 100 && plan.text == 101 && title?.track == plan.track
            && title?.start == second && title?.duration == 4 * second
            && title?.text?.content == "Hello" && title?.video?.behindSubject == true
            && camera?.video?.cutout?.background == (cut ? .remove : .keep)
        row(
            "P1", made,
            "\(what): track \(plan.track) at index \(String(describing: newTrack)), title "
                + "\(plan.text) on \(String(describing: title?.track)) for "
                + "\(String(describing: title?.duration)), behind_subject "
                + "\(String(describing: title?.video?.behindSubject)), the clip's background "
                + "\(String(describing: camera?.video?.cutout?.background))")
        let recipe = after.recipe(at: second)
        let cutBy = recipe.flatMap { BehindSubjectPlan.isCutBySubject(clip: plan.text, in: $0) }
        let noLayer = recipe.flatMap { BehindSubjectPlan.isCutBySubject(clip: 999, in: $0) }
        row(
            "P1", cutBy == true && noLayer == nil,
            "\(what): isCutBySubject(title) \(String(describing: cutBy)), of a clip with no "
                + "layer \(String(describing: noLayer))")
    }

    // A flagged clip with the cut-out clip in FRONT of it is not cut.
    let inFront = try project(
        tracks: [track(2), track(3)],
        clips: [clip(11, track: 3, cutout: true), clip(12, track: 2)])
    let flagged =
        try inFront.applying(
            .setVideo(clips: [12], patch: VideoPatch(behindSubject: true))
        ).project
    let notCut = flagged?.recipe(at: second).flatMap {
        BehindSubjectPlan.isCutBySubject(clip: 12, in: $0)
    }
    row(
        "P1", notCut == false,
        "a flagged clip behind the cut-out clip: isCutBySubject \(String(describing: notCut))")
} catch {
    row("P1", false, "the probe threw: \(error)")
}
finish()
