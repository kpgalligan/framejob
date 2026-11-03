// Road map "creator-jobs" CU7 (spec §11 CU-73, CU-77): Z5, the probe row of `cu7_proof.py`,
// compiled as `main.swift` over `app/Sources` through `swift_build.build()` with
// `FRAMEJOB_DEV_TOOLS`, and run as `cu7-probe <request.json>`. The request names a project
// JSON (`project`: one media clip, 10, whose media has a cursor file, carrying twelve actions
// whose ends the proof wrote) and a cursor file (`cursor`). It prints one JSON object,
// `{"rows": [{"id", "pass", "detail"}]}`.
//
// - Z5 `ActionBands.isZoom` (what the timeline draws the zoom glyph by) and the core's
//   `is_zoom` (read through what `plan_zooms` with Replace removes, `AutoZoom.plan`) agree on
//   every one of the twelve ends, and the ends hold both kinds.

import AppKit
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

guard CommandLine.arguments.count > 1,
    let requestData = FileManager.default.contents(atPath: CommandLine.arguments[1]),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
    let projectPath = request["project"] as? String, let cursorPath = request["cursor"] as? String,
    let projectText = try? String(contentsOfFile: projectPath, encoding: .utf8),
    let cursorData = FileManager.default.contents(atPath: cursorPath)
else {
    row("Z5", false, "no request")
    finish()
}

do {
    let project = try ReelProject.from(json: projectText)
    let snapshot = project.snapshot
    guard let clip = snapshot.clip(10), case .media(let media, _, _) = clip.source else {
        row("Z5", false, "the fixture has no media clip 10")
        finish()
    }
    let track = try ReelCursor(data: cursorData)
    var settings = AutoZoomSettings()
    settings.replace = true
    let plan = try AutoZoom.plan(
        [clip], tracks: [media: track], project: project, settings: settings, from: nil,
        to: nil)
    let removed = Set(
        plan.ops.filter { $0.name == "remove_action" }
            .compactMap { ($0.args["action"] as? UInt32) ?? ($0.args["action"] as? NSNumber)?.uint32Value })
    var disagree: [String] = []
    var zooms = 0
    for action in clip.actions {
        let swift = ActionBands.isZoom(action)
        if swift { zooms += 1 }
        if swift != removed.contains(action.id) {
            disagree.append("action \(action.id): isZoom \(swift), removed \(removed.contains(action.id))")
        }
    }
    let both = zooms > 0 && zooms < clip.actions.count
    row(
        "Z5", clip.actions.count == 12 && both && disagree.isEmpty,
        "\(clip.actions.count) ends, \(zooms) zooms by isZoom, \(removed.count) removed by "
            + "plan_zooms' Replace; "
            + (disagree.isEmpty ? "they agree on every end" : disagree.joined(separator: "; ")))
} catch {
    row("Z5", false, "the plan failed: \(error.localizedDescription)")
}
finish()
