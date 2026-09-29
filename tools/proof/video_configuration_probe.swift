// tools/proof/video_configuration_probe.swift — the in-process instrument behind
// `video_configuration_proof.py`'s C2 and V7 (issue batch B11, #91). Compiled
// with every file in `app/Sources` but `main.swift` over `harness/build.sh`'s
// swiftc line, copied in as `main.swift`, with the app's `Fonts`, `Blank.mp4`
// and a `default.metallib` of the app's own shader beside the binary —
// `export_cancel_probe.swift`'s build.
//
//     video_configuration_probe <package.reelcut> <out.mov>
//
// It opens the package as the app does (`read`, `fileURL`) and exports
// `prores_422` with the export sheet's frame-rate override at 25 fps
// (`ReelExport.settings(…, overrides: ["fps": [25, 1]])`) through
// `Exporter().export(… urls: doc.mediaURLs() …)` — the one path that hands
// `ExportWriter` a rate the canvas (30 fps) does not have, so the writer's
// frame-duration variant of the video composition is what draws the file.
// It uses only API that both the control tree and the tree under test have.
//
// One JSON object on stdout — `outcome` (`success`, `failure`, `deadline`),
// `error`, `path`, `fps` — and exit 0. A crash is the caller's to see.
import AppKit

let arguments = CommandLine.arguments
var answer: [String: Any] = [:]

func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

guard arguments.count == 3 else {
    answer["outcome"] = "failure"
    answer["error"] = "usage: <package.reelcut> <out.mov>"
    finish()
}
let packageURL = URL(fileURLWithPath: arguments[1])
let outURL = URL(fileURLWithPath: arguments[2])

NSApplication.shared.setActivationPolicy(.prohibited)

let document = ProjectDocument()
do {
    try document.read(from: packageURL, ofType: "com.kgalligan.reelcut-project")
} catch {
    answer["outcome"] = "failure"
    answer["error"] = "the package would not open: \(error.localizedDescription)"
    finish()
}
document.fileURL = packageURL

let settings: ExportSettings
do {
    settings = try ReelExport.settings(
        document.project, preset: "prores_422", overrides: ["fps": [25, 1]])
} catch {
    answer["outcome"] = "failure"
    answer["error"] = "the core would not resolve prores_422 at 25 fps: \(error)"
    finish()
}
answer["fps"] = [settings.fps.num, settings.fps.den]
try? FileManager.default.removeItem(at: outURL)

let exporter = Exporter()
var outcome: Result<URL, any Error>?
exporter.export(
    project: document.project, urls: document.mediaURLs(), settings: settings,
    to: outURL, progress: { _ in },
    completion: { result in outcome = result })

let deadline = Date().addingTimeInterval(300)
while outcome == nil, Date() < deadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
}

switch outcome {
case .success(let url)?:
    answer["outcome"] = "success"
    answer["path"] = url.path
case .failure(let error)?:
    answer["outcome"] = "failure"
    answer["error"] = error.localizedDescription
case nil:
    answer["outcome"] = "deadline"
}
finish()
