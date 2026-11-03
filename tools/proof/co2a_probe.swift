// Road map "creator-jobs" CO2a1 and CO2a2 (spec §11 CO-20, CO-21, CO-24…CO-27): the probe of
// `co2a_proof.py`, compiled as `main.swift` over `app/Sources` and
// `cutout_spike/mask_track_writer.swift` (the bar code) through `swift_build.build()` with
// `FRAMEJOB_DEV_TOOLS`. Modes:
//
// - `co2a-probe <request.json>`: the rows. The request names the movie path the fixtures'
//   media point at (`movie`). It prints one JSON object, `{"rows": [{"id", "pass", "detail"}],
//   "d1p": {…}}`, on stdout.
// - `co2a-probe barcode <out.mov> <frames>`: CO-S2's bar-code movie (`writeBarcode`), frame k
//   carrying k.
// - `co2a-probe pack <spec.json>`: a canned `masks.pack` (`MaskPack.write`), `spec` naming `out`,
//   `frames` (pts k × 20,000, grid index k), `rate` (`every` or a capped rate r: the first frame
//   at or after each k / r s, CJ-23) and `kind` — `barcode` (512 × 288: rows 35–65 % 255, the
//   picture's own bar-code band; rows 75–95 % the analysed frame's index as a bar code, white
//   255 and black 0; the rest 0), `zero` (every mask 0, no subject) or `ramp` (CO4's E4, spec
//   §11 CO-42: column i `round(255 · clamp((i − 240) / 32, 0, 1))` in every row — 0 left of 240,
//   255 from 272) or `person_left` (CO7's P2, spec §11 CO-70: columns 160–223 × rows 72–215
//   at 255, every other texel 0 — a person left of centre, centroid texel (192, 144)). Each
//   frame's slot is its nearest analysed mask, ties to the earlier
//   (`AnalysisMasks.nearest`).
// - `co2a-probe mask <pack> <slot> <out>`: slot's mask decompressed, its bytes written raw;
//   prints `{"width", "height"}`.
//
// - D13p (CO2a1) a two-media project (media 5 and 7, clips 11 and 12, so no media id
//   is a clip id), clip 11 on media 5 with a cutout and clip 12 on media 7
//   with another: `VideoProps.cutout` equals the JSON; `VideoPatch(cutout:
//   .some(p))` writes all five keys and `.some(nil)` an `NSNull`;
//   `recipe(at:)`'s layer `cutout` decodes the mask's media (5 and 7), kind,
//   quality and the rest; `recipeJSON(at:)`'s layer for clip 11 names media 5.
// - D1p (CO2a2, CO-24) ten cases' plans over a 300-frame 30 fps media 5 — a trim, ×0.5, ×2,
//   ×1.37, `add_speed_ramp` ramp up ×2, `freeze_frame`, a reverse, `split`, a nest and a
//   cross-dissolve — at every composition frame, every covering segment of media 5:
//   `CutoutLookup.sourceTick` and the slot `CutoutLookup.slot` answers from a pack analysed at
//   every frame and one at 15 a second (coverage the whole file). The probe answers the rows
//   (`d1p`); the proof scores them against `deciders.expected_mask`.

import Foundation

var rows: [[String: Any]] = []
var d1p: [String: Any] = [:]

func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}

func finish() -> Never {
    let data =
        (try? JSONSerialization.data(
            withJSONObject: ["rows": rows, "d1p": d1p], options: [.sortedKeys]))
        ?? Data()
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

let second: Ticks = 600_000

let frameTicks: Ticks = 20_000

/// The analysed frames of `frames` frames at `rate` (CJ-23): every frame, or for a rate r the
/// first frame at or after each k / r s.
func analysedFrames(_ frames: Int, rate: String) -> [Int] {
    guard let r = Int(rate) else { return Array(0..<frames) }
    var picked: [Int] = []
    var k = 0, at = 0
    while true {
        while at < frames && at * r < k * 30 { at += 1 }
        if at >= frames { break }
        if picked.last != at { picked.append(at) }
        k += 1
    }
    return picked
}

/// A pack of `frames` frames analysed at `rate`, each analysed mask `mask(index)`, written to
/// `url`.
func writePack(
    _ url: URL, frames: Int, rate: String, width: Int, height: Int, mask: (Int) -> [UInt8]
) throws {
    let analysed = analysedFrames(frames, rate: rate)
    let times = analysed.map { Int64($0) * frameTicks }
    let masks = analysed.map { index -> MaskPack.Analysed in
        let bytes = mask(index)
        let compressed = (try? (Data(bytes) as NSData).compressed(using: .lzfse) as Data) ?? Data()
        let found = bytes.withUnsafeBytes { MaskPack.found($0, width: width, height: height) }
        return MaskPack.Analysed(pts: Int64(index) * frameTicks, compressed: compressed, found: found)
    }
    let rows = (0..<frames).map { k -> (pts: Int64, index: Int32, maskPts: Int64) in
        let pts = Int64(k) * frameTicks
        return (pts, Int32(k), AnalysisMasks.nearest(pts, in: times) ?? 0)
    }
    try? FileManager.default.removeItem(at: url)
    try MaskPack.write(
        onDisk: nil, partial: url, width: width, height: height, frames: rows, masks: masks)
}

/// CO4's ramp mask (512 × 288): column i `round(255 · clamp((i − 240) / 32, 0, 1))` in every
/// row, the same for every analysed frame.
func rampPackMask() -> [UInt8] {
    let w = 512, h = 288
    let row = (0..<w).map { i -> UInt8 in
        UInt8((255 * min(max(Double(i - 240) / 32, 0), 1)).rounded())
    }
    return [UInt8]((0..<h).map { _ in row }.joined())
}

/// CO7's person left of centre (512 × 288): columns 160–223 × rows 72–215 at 255, the rest 0.
func personLeftPackMask() -> [UInt8] {
    let w = 512, h = 288
    var out = [UInt8](repeating: 0, count: w * h)
    for y in 72...215 {
        for x in 160...223 { out[y * w + x] = 255 }
    }
    return out
}

/// The canned bar-code mask of analysed frame `index` (512 × 288).
func barcodePackMask(_ index: Int) -> [UInt8] {
    let w = 512, h = 288
    var out = [UInt8](repeating: 0, count: w * h)
    out.withUnsafeMutableBufferPointer { pointer in
        let base = pointer.baseAddress!
        for y in Int(Double(h) * 0.35)..<Int(Double(h) * 0.65) {
            memset(base + y * w, 255, w)
        }
        BarCode.draw(index, into: base, stride: w, width: w,
                     band: Int(Double(h) * 0.75)..<Int(Double(h) * 0.95), white: 255, black: 0)
    }
    return out
}

func jsonOut(_ object: Any) -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

let arguments = CommandLine.arguments
switch arguments.count > 1 ? arguments[1] : "" {
case "barcode":
    guard arguments.count > 3, let frames = Int(arguments[3]) else { jsonOut(["ok": false]) }
    do {
        try writeBarcode(URL(fileURLWithPath: arguments[2]), frames: frames) { $0 }
        jsonOut(["ok": true])
    } catch {
        jsonOut(["ok": false, "error": "\(error)"])
    }
case "pack":
    guard arguments.count > 2,
        let data = FileManager.default.contents(atPath: arguments[2]),
        let spec = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let out = spec["out"] as? String, let frames = spec["frames"] as? Int,
        let rate = spec["rate"] as? String, let kind = spec["kind"] as? String
    else { jsonOut(["ok": false, "error": "the spec could not be read"]) }
    do {
        try writePack(
            URL(fileURLWithPath: out), frames: frames, rate: rate, width: 512, height: 288
        ) { index in
            switch kind {
            case "zero": return [UInt8](repeating: 0, count: 512 * 288)
            case "ramp": return rampPackMask()
            case "person_left": return personLeftPackMask()
            default: return barcodePackMask(index)
            }
        }
        jsonOut(["ok": true, "analysed": analysedFrames(frames, rate: rate)])
    } catch {
        jsonOut(["ok": false, "error": "\(error)"])
    }
case "mask":
    guard arguments.count > 4, let slot = Int(arguments[3]) else { jsonOut(["ok": false]) }
    do {
        let pack = try MaskPack(contentsOf: URL(fileURLWithPath: arguments[2]))
        let bytes = try pack.mask(slot: slot)
        try Data(bytes).write(to: URL(fileURLWithPath: arguments[4]))
        jsonOut(["ok": true, "width": pack.width, "height": pack.height])
    } catch {
        jsonOut(["ok": false, "error": "\(error)"])
    }
default:
    break
}

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


// ---- D1p --------------------------------------------------------------------

do {
    let frames = 300
    let cut: [String: Any] = ["subject": "person", "quality": "standard", "background": "remove",
                              "edge": 0.0, "feather": 0.0]
    func mediaClip(_ id: Int, start: Ticks, duration: Ticks, sourceIn: Ticks = 0,
                   extra: [String: Any] = [:], reversed: Bool = false, track: Int = 2)
        -> [String: Any]
    {
        var clip: [String: Any] = [
            "id": id, "track": track, "start": start, "duration": duration,
            "source": ["kind": "media", "media": 5, "in": sourceIn, "reversed": reversed],
            "video": ["cutout": cut],
        ]
        for (key, value) in extra { clip[key] = value }
        return clip
    }
    func project(_ clips: [[String: Any]], nests: [[String: Any]] = []) throws -> ReelProject {
        let fixture: [String: Any] = [
            "canvas": ["width": 1920, "height": 1080, "fps": [30, 1]],
            "media": [[
                "id": 5, "path": movie, "kind": "video", "duration": Int(frameTicks) * frames,
                "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true,
                "has_audio": false,
            ]],
            "tracks": [["id": 2, "name": "Track 1"]],
            "clips": clips, "nests": nests, "next_id": 100,
        ]
        let data = try JSONSerialization.data(withJSONObject: fixture, options: [.sortedKeys])
        return try ReelProject.from(json: String(decoding: data, as: UTF8.self))
    }
    func applied(_ project: ReelProject, _ op: ReelOp) throws -> ReelProject {
        switch try project.applying(op) {
        case .applied(let next): return next
        case .identity: throw ReelCoreError(message: "\(op.name) was an identity")
        case .refused(let refusal): throw ReelCoreError(message: refusal.reason)
        }
    }
    var problems: [String] = []
    var cases: [(String, ReelProject)] = []
    do {
        let plain = try project([mediaClip(11, start: 0, duration: 6 * second)])
        cases.append(("trim", try project([
            mediaClip(11, start: 0, duration: 3 * second, sourceIn: 2 * second)])))
        cases.append(("x0.5", try project([
            mediaClip(11, start: 0, duration: 4 * second, extra: ["speed": 0.5])])))
        cases.append(("x2", try project([
            mediaClip(11, start: 0, duration: 4 * second, extra: ["speed": 2.0])])))
        cases.append(("x1.37", try project([
            mediaClip(11, start: 0, duration: 4 * second, extra: ["speed": 1.37])])))
        cases.append(("ramp", try applied(
            plain, .addSpeedRamp(clip: 11, shape: .rampUp, rate: 2))))
        cases.append(("freeze", try applied(
            plain, .freezeFrame(clip: 11, at: 2 * second, duration: second))))
        cases.append(("reverse", try project([
            mediaClip(11, start: 0, duration: 6 * second, reversed: true)])))
        cases.append(("split", try applied(plain, .split(clips: [11], at: 2 * second))))
        cases.append(("nest", try project(
            [["id": 60, "track": 2, "start": second, "duration": 4 * second,
              "source": ["kind": "nest", "project": 50]]],
            nests: [["id": 50, "name": "Nest", "width": 1920, "height": 1080,
                     "tracks": [["id": 53, "name": "Inner"]],
                     "clips": [mediaClip(51, start: 0, duration: 4 * second, sourceIn: second,
                                         track: 53)]]])))
        cases.append(("dissolve", try project([
            mediaClip(11, start: 0, duration: 4 * second),
            mediaClip(12, start: 3 * second, duration: 3 * second, sourceIn: 5 * second,
                      extra: ["transition_in": ["kind": "cross_dissolve", "curve": "linear",
                                                "audio": false]]),
        ])))
    } catch {
        problems.append("a case did not build: \(error)")
    }
    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("co2a-probe-\(getpid())", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let mediaSnapshot = cases.first?.1.snapshot.media(5)
    var packs: [(String, CutoutPack)] = []
    for rate in ["every", "15"] {
        let url = folder.appendingPathComponent("\(rate).pack")
        do {
            try writePack(url, frames: frames, rate: rate, width: 2, height: 2) { _ in
                [255, 255, 255, 255]
            }
            guard let mediaSnapshot else { throw ReelCoreError(message: "no media 5") }
            packs.append((rate, CutoutPack(
                pack: try MaskPack(contentsOf: url), coverage: [0...(frames - 1)],
                grid: AnalysisGrid(media: mediaSnapshot))))
        } catch {
            problems.append("the \(rate) pack: \(error)")
        }
    }
    var out: [[Any]] = []
    for (name, project) in cases {
        let plan = CutoutPlan(project: project)
        let duration = project.plan?.duration ?? 0
        var t: Ticks = 0
        var seen = 0
        while t < duration {
            for track in plan.segments.keys.sorted() {
                guard let segment = plan.covering(track: track, at: t), segment.media == 5
                else { continue }
                let s = CutoutLookup.sourceTick(segment, at: t)
                let pivot = plan.pivots[segment.clip]
                for (rate, pack) in packs {
                    let slot = CutoutLookup.slot(
                        pack: pack.pack, ends: pack.ends, coverage: pack.coverage,
                        grid: pack.grid, sourceTick: s, pivot: pivot)
                    let maskPts = slot.map { pack.pack.masks[$0].pts } ?? -1
                    out.append([name, rate, t, track, Int(segment.clip), segment.sourceIn,
                                segment.sourceDuration, segment.start, segment.duration, s,
                                pivot ?? -1, maskPts])
                    seen += 1
                }
            }
            t += frameTicks
        }
        if seen == 0 { problems.append("\(name): no frame covered by media 5") }
    }
    d1p = ["frames": frames, "rows": out, "problems": problems,
           "analysed": ["every": analysedFrames(frames, rate: "every"),
                        "15": analysedFrames(frames, rate: "15")]]
}

finish()
