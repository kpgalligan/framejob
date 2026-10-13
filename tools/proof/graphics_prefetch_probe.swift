// tools/proof/graphics_prefetch_probe.swift — the in-process export behind
// `graphics_prefetch_proof.py`'s S5 (issue #127, spec §11 G-26): the export
// sheet's frame-rate override, which no MCP argument reaches, is the one
// path that draws through `ExportWriter.videoComposition`'s variant. Compiled
// with every file in `app/Sources` but `main.swift` over
// `harness/build.sh`'s swiftc line, copied in as `main.swift`, with the
// app's `Fonts`, `Blank.mp4` and a `default.metallib` beside the binary.
//
//     graphics_prefetch_probe <package> <out.mov> <on|off>
//
// It opens the package as `graphics_pin_probe.swift` does, registers the
// prefetch's off switch for `off`, and exports `prores_422` at 25 fps over
// the range from tick 140 000 (project frame 7 of a 30 fps canvas, off the
// 25 fps grid) to 140 000 before the end, with the document's compiled set.
// It spins the main run loop to the completion and 10 s more, so the
// session's log line reaches stderr, then prints one JSON line on stdout:
// `{outcome, path, error, fps, start}`.
import AppKit

let arguments = CommandLine.arguments
var answer: [String: Any] = [:]

func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

guard arguments.count == 4, ["on", "off"].contains(arguments[3]) else {
    answer["outcome"] = "error"
    answer["error"] = "usage: <package> <out.mov> <on|off>"
    finish()
}
let packageURL = URL(fileURLWithPath: arguments[1])
let outURL = URL(fileURLWithPath: arguments[2])
answer["path"] = outURL.path
if arguments[3] == "off" {
    UserDefaults.standard.register(defaults: [GraphicPrefetch.offDefaultsKey: true])
}

NSApplication.shared.setActivationPolicy(.prohibited)

/// The fonts beside the binary, as `harness/build.sh` puts them.
let binaryDirectory = URL(fileURLWithPath: arguments[0]).deletingLastPathComponent()
    .standardizedFileURL
let fontsDirectory = binaryDirectory.appendingPathComponent("Fonts")
for name in (try? FileManager.default.contentsOfDirectory(atPath: fontsDirectory.path)) ?? []
where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
    CTFontManagerRegisterFontsForURL(
        fontsDirectory.appendingPathComponent(name) as CFURL, .process, nil)
}

/// Spins the main run loop until `done()` or the deadline.
func spin(until done: () -> Bool, timeout: Double) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !done(), Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return done()
}

let document = ProjectDocument()
do {
    try document.read(from: packageURL, ofType: ProjectDocument.projectTypeIdentifier)
} catch {
    answer["outcome"] = "error"
    answer["error"] = "the package would not open: \(error.localizedDescription)"
    finish()
}
document.fileURL = packageURL
document.startGraphicStore()

let duration = document.project.duration
let settings: ExportSettings
do {
    settings = try ReelExport.settings(
        document.project, preset: "prores_422",
        overrides: ["fps": [25, 1], "range": ["start": 140_000, "duration": duration - 280_000]])
} catch {
    answer["outcome"] = "error"
    answer["error"] = "the core would not resolve the settings: \(error.localizedDescription)"
    finish()
}
answer["fps"] = [settings.fps.num, settings.fps.den]
answer["start"] = settings.start

try? FileManager.default.removeItem(at: outURL)
let exporter = Exporter()
var outcome: Result<URL, any Error>?
exporter.export(
    project: document.project, urls: document.mediaURLs(), settings: settings, to: outURL,
    graphics: GraphicRegistry.shared.snapshot(for: document.recipeKey), progress: { _ in },
    completion: { outcome = $0 })
let settled = spin(until: { outcome != nil }, timeout: 600)
switch outcome {
case .success?:
    answer["outcome"] = "success"
case .failure(let error)?:
    answer["outcome"] = "failure"
    answer["error"] = error.localizedDescription
case nil:
    answer["outcome"] = "unsettled"
    answer["error"] = "no completion within 600 s (settled \(settled))"
}
_ = spin(until: { false }, timeout: 10)
document.stopGraphicStore()
finish()
