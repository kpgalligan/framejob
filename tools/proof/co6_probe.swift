// Road map "creator-jobs" CO6 (spec §11 CO-63, CO-67) — L11: every layout action
// `switch_layout` wrote in `co6_proof.py`'s L1 is no zoom to the timeline and names exactly
// the six placement keys, read through the app's own `ActionBands.isZoom` and `ActionPatch`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`,
// through `swift_build.py`'s one line. One process:
//
//   co6_probe <request.json>
//
// The request names `projects`: paths of project JSON files (`get_project`'s `project`, each
// after one L1 switch) and `clips`: the ids whose actions to read. The answer is one JSON
// object on stdout, `{"rows": [...]}`, each row `{"id", "pass", "detail", "instrument"}`;
// `co6_proof.py` prints and scores them.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2,
    let requestData = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
    let paths = request["projects"] as? [String],
    let clipIDs = request["clips"] as? [Int]
else {
    FileHandle.standardError.write(Data("usage: co6_probe <request.json>\n".utf8))
    exit(2)
}

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String, instrument: Bool = false) {
    rows.append(["id": id, "pass": pass && !instrument, "detail": String(detail.prefix(1500)),
                 "instrument": instrument])
}
func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    exit(0)
}

let six: Set<String> = ["x", "y", "scale", "crop", "corner_radius", "opacity"]
var read = 0
var problems: [String] = []
for path in paths {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8),
        let project = try? ReelProject.from(json: text)
    else {
        problems.append("\(path) did not open")
        continue
    }
    for id in clipIDs {
        guard let clip = project.snapshot.clip(UInt32(id)) else { continue }
        for action in clip.actions {
            read += 1
            let keys = Set(action.end.video?.dictionary.keys.map { $0 } ?? [])
            if ActionBands.isZoom(action) {
                problems.append("\(URL(fileURLWithPath: path).lastPathComponent) clip \(id) "
                    + "action \(action.id) reads as a zoom")
            }
            if keys != six {
                problems.append("\(URL(fileURLWithPath: path).lastPathComponent) clip \(id) "
                    + "action \(action.id) names \(keys.sorted())")
            }
        }
    }
}
row(
    "L11", read > 0 && problems.isEmpty,
    "\(read) layout actions in \(paths.count) projects; "
        + (problems.isEmpty ? "none is a zoom and each names exactly the six keys"
            : problems.joined(separator: "; ")))
finish()
