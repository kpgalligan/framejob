// Road map creator-jobs VR5b — the camera layouts' naming twin (spec §11 VR-54, VR-56 R7),
// measured through the app's own sources with no app: for every Clip ▸ Camera Layout ▸ row
// (`CameraLayoutChoice.menuRows`), the end the CORE writes for it with `switch_layout` on
// 1920 × 1080 and 1080 × 1080, with a 1920 × 1080 and a 1280 × 720 camera, is named that row by
// `VerticalVersion.layoutName`, and `isLayoutAction` is true for it; a zoom end ({scale, x, y})
// is not a layout action.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`, with
// `FRAMEJOB_DEV_TOOLS`, against `libframejob_core.a`, through `swift_build.py`:
//
//   vr5b_probe <work dir> main   -> {"rows": [{"id", "pass", "detail"}, ...]}
import AppKit

guard CommandLine.arguments.count >= 3, CommandLine.arguments[2] == "main" else {
    FileHandle.standardError.write(Data("usage: vr5b_probe <work dir> main\n".utf8))
    exit(2)
}

let second = ReelTime.perSecond
var rows: [[String: Any]] = []
func row(_ id: String, _ problems: [String], _ detail: String) {
    rows.append(["id": id, "pass": problems.isEmpty,
                 "detail": problems.isEmpty ? detail : problems.joined(separator: "; ")])
}

/// Screen clip 10 (a 1920 × 1080 media) behind camera clip 20 (`camera`), both [0, 30 s).
func fixture(canvas: (Int, Int), camera: (Int, Int), actions: [[String: Any]] = []) throws
    -> ReelProject
{
    func media(_ id: Int, _ size: (Int, Int)) -> [String: Any] {
        ["id": id, "path": "/m/\(id).mov", "kind": "video", "duration": 600 * Int(second),
         "width": size.0, "height": size.1, "fps": [30, 1], "has_video": true,
         "has_audio": false]
    }
    func clip(_ id: Int, _ track: Int, _ media: Int) -> [String: Any] {
        ["id": id, "track": track, "start": 0, "duration": 30 * Int(second),
         "source": ["kind": "media", "media": media, "in": 0], "video": [String: Any](),
         "actions": id == 10 ? actions : []]
    }
    let project: [String: Any] = [
        "version": 38,
        "canvas": ["width": canvas.0, "height": canvas.1, "fps": [30, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true],
        "media": [media(1, camera), media(2, (1920, 1080))],
        "tracks": [["id": 3, "name": "Screen"], ["id": 4, "name": "Camera"]],
        "clips": [clip(10, 3, 2), clip(20, 4, 1)], "markers": [], "next_id": 100,
    ]
    let data = try JSONSerialization.data(withJSONObject: project)
    return try ReelProject.from(json: String(decoding: data, as: UTF8.self))
}

func name(_ choice: CameraLayoutChoice?) -> String {
    guard let choice else { return "nil" }
    return [choice.kind.rawValue, choice.shape?.rawValue, choice.corner?.rawValue]
        .compactMap { $0 }.joined(separator: "/")
}

// R7: every row named back.
var problems: [String] = []
var checked = 0
for canvas in [(1920, 1080), (1080, 1080)] {
    for camera in [(1920, 1080), (1280, 720)] {
        for choice in CameraLayoutChoice.menuRows {
            let what = "\(name(choice)) on \(canvas.0)×\(canvas.1), camera \(camera.0)×\(camera.1)"
            do {
                let base = try fixture(canvas: canvas, camera: camera)
                guard case .applied(let laid) = try base.applying(
                    choice.op(camera: 20, screen: nil, at: 2 * second))
                else {
                    problems.append("\(what): switch_layout did not apply")
                    continue
                }
                let snapshot = laid.snapshot
                guard let clip = snapshot.clip(20),
                    let action = clip.actions.first(where: { $0.start == 2 * second })
                else {
                    problems.append("\(what): no layout action at 2 s")
                    continue
                }
                checked += 1
                if !VerticalVersion.isLayoutAction(action) {
                    problems.append("\(what): isLayoutAction false")
                }
                let got = VerticalVersion.layoutName(action, of: clip, in: snapshot)
                if got != choice { problems.append("\(what): named \(name(got))") }
            } catch {
                problems.append("\(what): \(error)")
            }
        }
    }
}
do {
    let zoom: [String: Any] = ["id": 90, "start": 0, "duration": Int(second),
                               "curve": "ease_in_out",
                               "end": ["video": ["scale": 2.0, "x": -400.0, "y": -200.0]]]
    let project = try fixture(canvas: (1920, 1080), camera: (1280, 720), actions: [zoom])
    if let action = project.snapshot.clip(10)?.actions.first {
        if VerticalVersion.isLayoutAction(action) { problems.append("a zoom end is a layout") }
    } else {
        problems.append("the zoom fixture has no action")
    }
} catch {
    problems.append("the zoom fixture: \(error)")
}
row("R7", problems + (checked == 64 ? [] : ["\(checked) ends checked, want 64"]),
    "\(checked) core-made ends named back to their row, each a layout action; a zoom end not one")

let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
    ?? Data("{}".utf8)
FileHandle.standardOutput.write(data)
exit(0)
