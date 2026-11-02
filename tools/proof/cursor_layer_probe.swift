// Road map "creator-jobs" CU3a1 (spec §11 CU-30, CU-32, CU-35, CU-39): the
// probe rows of `cursor_layer_proof.py`, compiled as `main.swift` over
// `app/Sources` through `swift_build.build()` with `FRAMEJOB_DEV_TOOLS`, and
// run as `cursor-layer-probe <request.json>`. The request names the v37
// fixture (`fixture`, a project as JSON text: A.mov, one clip, one zoom
// action). No app, no file read but the request. It prints one JSON object,
// `{"rows": [{"id", "pass", "detail"}]}`, on stdout.
//
// - L1d the Swift mirrors of a fixture carrying `media.cursor` and
//   `video.cursor`: `MediaSnapshot.cursor` and `VideoProps.cursor` equal the
//   JSON, `MediaDescriptor(media).dictionary["cursor"]` is the JSON object,
//   and `VideoPatch`'s `cursor` writes all eight keys, or `NSNull` for
//   `.some(nil)`.
// - L3r at five times every layer's `cursor` is null; with `media[0].cursor`
//   `{path, in_picture: true}` the recipe's TEXT is byte-identical at each
//   time; the control, `in_picture: false`, is not null.
// - L9 a base `cursor {smoothing: 0}` and an action over [1 s, 3 s) ending
//   `{smoothing: 1, hide_idle: 5, scale: 3}`: at 0.5, 1.5, 2.5 and 3.5 s the
//   key's and `props`' `smoothing` are 0 and `hide_idle` null; `props.scale`
//   1, strictly between 1 and 3 twice, then 3; `recipe(at:)` decodes the same.

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
    let fixtureText = request["fixture"] as? String,
    let fixtureData = fixtureText.data(using: .utf8),
    let fixture = (try? JSONSerialization.jsonObject(with: fixtureData)) as? [String: Any]
else {
    for id in ["L1d", "L3r", "L9"] { row(id, false, "the request could not be read") }
    finish()
}

/// `fixture` changed by `edit`, as JSON text.
func variant(_ edit: (inout [String: Any]) -> Void) -> String {
    var copy = fixture
    edit(&copy)
    let data = (try? JSONSerialization.data(withJSONObject: copy, options: [.sortedKeys])) ?? Data()
    return String(decoding: data, as: UTF8.self)
}

/// Sets `value` at `media[0][key]`.
func setMedia(_ project: inout [String: Any], _ key: String, _ value: Any) {
    var media = project["media"] as? [[String: Any]] ?? []
    if !media.isEmpty { media[0][key] = value }
    project["media"] = media
}

/// Sets `value` at `clips[0][key]`.
func setClip(_ project: inout [String: Any], _ key: String, _ value: Any) {
    var clips = project["clips"] as? [[String: Any]] ?? []
    if !clips.isEmpty { clips[0][key] = value }
    project["clips"] = clips
}

func layers(_ text: String?) -> [[String: Any]] {
    guard let data = text?.data(using: .utf8),
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return [] }
    return object["layers"] as? [[String: Any]] ?? []
}

let mediaCursorJSON: [String: Any] = [
    "path": "/proof/A.fjcursor", "bookmark": "Qk0=", "in_picture": false,
]
let cursorJSON: [String: Any] = [
    "show": false, "scale": 2.5, "style": "arrow", "smoothing": 0.5, "hide_idle": 3.0,
    "clicks": "ripple", "click_color": "red", "click_size": 1.5,
]

// ---- L1d ------------------------------------------------------------------

do {
    let text = variant { project in
        setMedia(&project, "cursor", mediaCursorJSON)
        var clips = project["clips"] as? [[String: Any]] ?? []
        var video = clips.first?["video"] as? [String: Any] ?? [:]
        video["cursor"] = cursorJSON
        if !clips.isEmpty { clips[0]["video"] = video }
        project["clips"] = clips
    }
    var problems: [String] = []
    do {
        let project = try ReelProject.from(json: text)
        let snapshot = project.snapshot
        let expectedMedia = MediaCursor(path: "/proof/A.fjcursor", bookmark: "Qk0=", inPicture: false)
        let expectedProps = CursorProps(
            show: false, scale: 2.5, style: .arrow, smoothing: 0.5, hideIdle: 3, clicks: .ripple,
            clickColor: "red", clickSize: 1.5)
        if snapshot.media.first?.cursor != expectedMedia {
            problems.append("MediaSnapshot.cursor \(String(describing: snapshot.media.first?.cursor))")
        }
        if snapshot.clips.first?.video?.cursor != expectedProps {
            problems.append("VideoProps.cursor \(String(describing: snapshot.clips.first?.video?.cursor))")
        }
        if let media = snapshot.media.first {
            let written = MediaDescriptor(media).dictionary["cursor"] as? [String: Any] ?? [:]
            if !(written as NSDictionary).isEqual(to: mediaCursorJSON) {
                problems.append("MediaDescriptor's cursor \(written)")
            }
            let probe = MediaDescriptor(media).probeDictionary["cursor"] as? [String: Any] ?? [:]
            if !(probe as NSDictionary).isEqual(to: mediaCursorJSON) {
                problems.append("the probe's cursor \(probe)")
            }
        } else {
            problems.append("no media")
        }
        let patch = VideoPatch(cursor: .some(expectedProps)).dictionary["cursor"] as? [String: Any] ?? [:]
        if patch.count != 8 || !(patch as NSDictionary).isEqual(to: cursorJSON) {
            problems.append("VideoPatch's cursor \(patch)")
        }
        let defaults = VideoPatch(cursor: .some(CursorProps())).dictionary["cursor"] as? [String: Any] ?? [:]
        if defaults.count != 8 || !(defaults["hide_idle"] is NSNull)
            || defaults["clicks"] as? String != "none"
        {
            problems.append("VideoPatch's default cursor \(defaults)")
        }
        if !(VideoPatch(cursor: .some(nil)).dictionary["cursor"] is NSNull) {
            problems.append("VideoPatch(cursor: .some(nil)) did not write NSNull")
        }
        if VideoPatch().dictionary["cursor"] != nil {
            problems.append("VideoPatch() wrote a cursor")
        }
    } catch {
        problems.append("the fixture did not open: \(error)")
    }
    row("L1d", problems.isEmpty, problems.isEmpty
        ? "the snapshot, the descriptor and the patch mirror media.cursor and video.cursor"
        : problems.joined(separator: "; "))
}

// ---- L3r ------------------------------------------------------------------

do {
    let times: [Ticks] = [0, second / 2, 3 * second / 2, 2 * second + 20_000, 5 * second]
    var problems: [String] = []
    do {
        let plain = try ReelProject.from(json: variant { _ in })
        let inPicture = try ReelProject.from(json: variant { project in
            setMedia(&project, "cursor", ["path": "/proof/A.fjcursor", "in_picture": true])
        })
        let control = try ReelProject.from(json: variant { project in
            setMedia(&project, "cursor", ["path": "/proof/A.fjcursor", "in_picture": false])
        })
        for t in times {
            let text = plain.recipeJSON(at: t)
            let drawn = layers(text)
            if drawn.isEmpty { problems.append("no layer at \(t)") }
            if drawn.contains(where: { !($0["cursor"] is NSNull) }) {
                problems.append("a non-null cursor at \(t)")
            }
            if inPicture.recipeJSON(at: t) != text {
                problems.append("in_picture: true changed the recipe text at \(t)")
            }
            let controlled = layers(control.recipeJSON(at: t))
            if controlled.isEmpty || controlled.contains(where: { $0["cursor"] is NSNull }) {
                problems.append("the control's cursor is null at \(t)")
            }
        }
    } catch {
        problems.append("a fixture did not open: \(error)")
    }
    row("L3r", problems.isEmpty, problems.isEmpty
        ? "null at \(times.count) times, in_picture: true byte-identical, the control keyed"
        : problems.joined(separator: "; "))
}

// ---- L9 -------------------------------------------------------------------

do {
    var problems: [String] = []
    var scales: [Double] = []
    do {
        let project = try ReelProject.from(json: variant { project in
            setMedia(&project, "cursor", ["path": "/proof/A.fjcursor", "in_picture": false])
            var clips = project["clips"] as? [[String: Any]] ?? []
            var video = clips.first?["video"] as? [String: Any] ?? [:]
            video["cursor"] = ["smoothing": 0]
            if !clips.isEmpty { clips[0]["video"] = video }
            project["clips"] = clips
            setClip(&project, "actions", [[
                "id": 4, "start": second, "duration": 2 * second, "curve": "linear",
                "end": ["video": ["cursor": ["smoothing": 1, "hide_idle": 5, "scale": 3]]],
            ]])
        })
        let start = (fixture["clips"] as? [[String: Any]])?.first?["start"] as? Int ?? 0
        for clipT in [second / 2, 3 * second / 2, 5 * second / 2, 7 * second / 2] {
            let t = Ticks(start) + clipT
            guard let key = layers(project.recipeJSON(at: t)).first?["cursor"] as? [String: Any],
                let props = key["props"] as? [String: Any]
            else {
                problems.append("no cursor key at \(t)")
                continue
            }
            if (key["smoothing"] as? Double) != 0 || (props["smoothing"] as? Double) != 0 {
                problems.append("smoothing \(key["smoothing"] ?? "nil") / \(props["smoothing"] ?? "nil") at \(t)")
            }
            if !(key["hide_idle"] is NSNull) || !(props["hide_idle"] is NSNull) {
                problems.append("hide_idle \(key["hide_idle"] ?? "nil") at \(t)")
            }
            let scale = (props["scale"] as? Double) ?? .nan
            scales.append(scale)
            guard let decoded = project.recipe(at: t)?.layers.first?.cursor else {
                problems.append("recipe(at:) decoded no cursor at \(t)")
                continue
            }
            if decoded.smoothing != 0 || decoded.hideIdle != nil || decoded.props.smoothing != 0
                || decoded.props.hideIdle != nil || decoded.props.scale != scale
            {
                problems.append("recipe(at:) decoded \(decoded) at \(t)")
            }
        }
    } catch {
        problems.append("the fixture did not open: \(error)")
    }
    let shaped = scales.count == 4 && scales[0] == 1 && scales[1] > 1 && scales[1] < 3
        && scales[2] > scales[1] && scales[2] < 3 && scales[3] == 3
    if !shaped { problems.append("props.scale \(scales)") }
    row("L9", problems.isEmpty, problems.isEmpty
        ? "smoothing 0 and hide_idle null at 4 times; props.scale \(scales)"
        : problems.joined(separator: "; "))
}

finish()
