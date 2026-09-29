// tools/proof/export_cancel_probe.swift — the in-process instrument behind
// `export_cancel_proof.py`'s M0–M2 (issue batch B1, #74, spec §11 G-17).
// Compiled with every file in `app/Sources` but `main.swift` over
// `harness/build.sh`'s swiftc line, copied in as `main.swift`, with the app's
// `Fonts`, `Blank.mp4` and a `default.metallib` of the app's own shader beside
// the binary — `graphics_pin_probe.swift`'s build.
//
//     export_cancel_probe <package.reelcut> <out.m4a> <delay|-1>
//
// It opens the package as the app does (`read`, `fileURL`), exports
// `audio_m4a` through `Exporter().export(… urls: doc.mediaURLs() …)` and
// polls `phaseDescription` on the main run loop in slices of at most 10 ms,
// under a 300 s deadline.
//
//   delay < 0   no cancel; `window` is the time from the first non-nil phase
//               to the next nil — how long the measurement ran.
//   delay >= 0  `cancel()` `delay` seconds after the phase first reads
//               non-nil, from main, as the sheet's and the queue's Cancel do.
//
// One JSON object on stdout — `outcome` (`success`, `cancelled` only for
// `Exporter.ExportError.cancelled`, `failure`, `deadline`), `error`,
// `window`, `phase_at_cancel`, `latency` (cancel to completion, seconds) and
// `left` (a file at the out path) — and exit 0. A crash is the caller's to
// see, as a signal.
import AppKit

let arguments = CommandLine.arguments
var answer: [String: Any] = [:]

func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

guard arguments.count == 4, let delay = Double(arguments[3]) else {
    answer["outcome"] = "failure"
    answer["error"] = "usage: <package.reelcut> <out.m4a> <delay|-1>"
    finish()
}
let packageURL = URL(fileURLWithPath: arguments[1])
let outURL = URL(fileURLWithPath: arguments[2])
answer["delay"] = delay

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

guard let settings = try? ReelExport.settings(document.project, preset: "audio_m4a") else {
    answer["outcome"] = "failure"
    answer["error"] = "the core would not resolve audio_m4a"
    finish()
}
try? FileManager.default.removeItem(at: outURL)

let exporter = Exporter()
var outcome: Result<URL, any Error>?
var completedAt: Date?
exporter.export(
    project: document.project, urls: document.mediaURLs(), settings: settings,
    to: outURL, progress: { _ in },
    completion: { result in
        outcome = result
        completedAt = Date()
    })

let deadline = Date().addingTimeInterval(300)
var phaseStarted: Date?
var phaseEnded: Date?
var cancelledAt: Date?
while outcome == nil, Date() < deadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    let phase = exporter.phaseDescription
    let now = Date()
    if phase != nil, phaseStarted == nil { phaseStarted = now }
    if phase == nil, phaseStarted != nil, phaseEnded == nil { phaseEnded = now }
    if delay >= 0, cancelledAt == nil, let started = phaseStarted,
        now.timeIntervalSince(started) >= delay
    {
        answer["phase_at_cancel"] = phase ?? NSNull()
        cancelledAt = Date()
        exporter.cancel()
    }
}

if let started = phaseStarted, let ended = phaseEnded {
    answer["window"] = ended.timeIntervalSince(started)
} else {
    answer["window"] = NSNull()
}
if let cancelled = cancelledAt, let completed = completedAt {
    answer["latency"] = completed.timeIntervalSince(cancelled)
} else {
    answer["latency"] = NSNull()
}
switch outcome {
case .success?:
    answer["outcome"] = "success"
case .failure(let error)?:
    if case Exporter.ExportError.cancelled = error {
        answer["outcome"] = "cancelled"
    } else {
        answer["outcome"] = "failure"
    }
    answer["error"] = error.localizedDescription
case nil:
    answer["outcome"] = "deadline"
}
answer["left"] = FileManager.default.fileExists(atPath: outURL.path)
finish()
