// Road map "creator-jobs" CO2a1 (spec §11 CO-20, CO-21): the probe row of
// `co2a_proof.py`, compiled as `main.swift` over `app/Sources` through
// `swift_build.build()` with `FRAMEJOB_DEV_TOOLS`, and run as
// `co2a-probe <request.json>`. The request names the movie path the fixture's
// media point at (`movie`); the probe builds its own two-media fixture. No
// app, no file read but the request. It prints one JSON object,
// `{"rows": [{"id", "pass", "detail"}]}`, on stdout.
//
// - D13p a two-media project (media 5 and 7, clips 11 and 12, so no media id
//   is a clip id), clip 11 on media 5 with a cutout and clip 12 on media 7
//   with another: `VideoProps.cutout` equals the JSON; `VideoPatch(cutout:
//   .some(p))` writes all five keys and `.some(nil)` an `NSNull`;
//   `recipe(at:)`'s layer `cutout` decodes the mask's media (5 and 7), kind,
//   quality and the rest; `recipeJSON(at:)`'s layer for clip 11 names media 5.

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

guard CommandLine.arguments.count > 1,
    let requestData = FileManager.default.contents(atPath: CommandLine.arguments[1]),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
    let movie = request["movie"] as? String
else {
    row("D13p", false, "the request could not be read")
    finish()
}

let cutout11: [String: Any] = [
    "subject": "person", "quality": "standard", "background": "keep", "edge": -0.25,
    "feather": 0.5,
]
let cutout12: [String: Any] = [
    "subject": "person", "quality": "best", "background": "remove", "edge": 0.75,
    "feather": 0.0,
]

func media(_ id: Int) -> [String: Any] {
    [
        "id": id, "path": movie, "kind": "video", "duration": 10 * Int(second), "width": 640,
        "height": 360, "fps": [30, 1], "has_video": true, "has_audio": false,
    ]
}

func clip(_ id: Int, track: Int, media: Int, cutout: [String: Any]) -> [String: Any] {
    [
        "id": id, "track": track, "start": 0, "duration": 6 * Int(second),
        "source": ["kind": "media", "media": media, "in": 0], "video": ["cutout": cutout],
    ]
}

let fixture: [String: Any] = [
    "canvas": ["width": 1280, "height": 720, "fps": [30, 1]],
    "media": [media(5), media(7)],
    "tracks": [["id": 2, "name": "Track 1"], ["id": 3, "name": "Track 2"]],
    "clips": [
        clip(11, track: 2, media: 5, cutout: cutout11),
        clip(12, track: 3, media: 7, cutout: cutout12),
    ],
    "next_id": 100,
]

func layers(_ text: String?) -> [[String: Any]] {
    guard let data = text?.data(using: .utf8),
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return [] }
    return object["layers"] as? [[String: Any]] ?? []
}

// ---- D13p -----------------------------------------------------------------

do {
    var problems: [String] = []
    do {
        let data = try JSONSerialization.data(withJSONObject: fixture, options: [.sortedKeys])
        let project = try ReelProject.from(json: String(decoding: data, as: UTF8.self))
        let snapshot = project.snapshot
        let expected11 = CutoutProps(
            subject: .person, quality: .standard, background: .keep, edge: -0.25, feather: 0.5)
        let expected12 = CutoutProps(
            subject: .person, quality: .best, background: .remove, edge: 0.75, feather: 0)
        let stored = Dictionary(
            snapshot.clips.map { ($0.id, $0.video?.cutout) }, uniquingKeysWith: { a, _ in a })
        if stored[11] != .some(expected11) {
            problems.append("clip 11's VideoProps.cutout \(String(describing: stored[11]))")
        }
        if stored[12] != .some(expected12) {
            problems.append("clip 12's VideoProps.cutout \(String(describing: stored[12]))")
        }

        let patch =
            VideoPatch(cutout: .some(expected11)).dictionary["cutout"] as? [String: Any] ?? [:]
        if patch.count != 5 || !(patch as NSDictionary).isEqual(to: cutout11) {
            problems.append("VideoPatch's cutout \(patch)")
        }
        let defaults =
            VideoPatch(cutout: .some(CutoutProps())).dictionary["cutout"] as? [String: Any] ?? [:]
        let defaultJSON: [String: Any] = [
            "subject": "person", "quality": "standard", "background": "remove", "edge": 0.0,
            "feather": 0.0,
        ]
        if defaults.count != 5 || !(defaults as NSDictionary).isEqual(to: defaultJSON) {
            problems.append("VideoPatch's default cutout \(defaults)")
        }
        if !(VideoPatch(cutout: .some(nil)).dictionary["cutout"] is NSNull) {
            problems.append("VideoPatch(cutout: .some(nil)) did not write NSNull")
        }
        if VideoPatch().dictionary["cutout"] != nil {
            problems.append("VideoPatch() wrote a cutout")
        }

        let t = 2 * second
        if let recipe = project.recipe(at: t) {
            let decoded = Dictionary(
                recipe.layers.map { ($0.clip, $0.cutout) }, uniquingKeysWith: { a, _ in a })
            for (clipID, mediaID, want) in [(UInt32(11), UInt32(5), expected11),
                                            (UInt32(12), UInt32(7), expected12)] {
                guard let found = decoded[clipID], let cut = found else {
                    problems.append("recipe(at:) decoded no cutout for clip \(clipID)")
                    continue
                }
                if cut.mask.kind != .media || cut.mask.media != mediaID
                    || cut.mask.quality != want.quality || cut.background != want.background
                    || cut.edge != want.edge || cut.feather != want.feather
                {
                    problems.append("clip \(clipID)'s recipe cutout \(cut)")
                }
            }
        } else {
            problems.append("recipe(at:) answered nothing")
        }
        let text = layers(project.recipeJSON(at: t))
        let eleven = text.first { ($0["clip"] as? Int) == 11 }
        let mask = (eleven?["cutout"] as? [String: Any])?["mask"] as? [String: Any]
        if (mask?["media"] as? Int) != 5 || (mask?["kind"] as? String) != "media" {
            problems.append("recipeJSON's clip 11 mask \(String(describing: mask))")
        }
    } catch {
        problems.append("the fixture did not open: \(error)")
    }
    row("D13p", problems.isEmpty, problems.isEmpty
        ? "VideoProps.cutout, VideoPatch's five keys and NSNull, the recipe's mask media 5 and 7"
        : problems.joined(separator: "; "))
}

finish()
