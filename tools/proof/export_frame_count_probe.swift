// kpgalligan/framejob#350 — the export sheet's "N frames" readout and the
// image-sequence writer count frames with one function,
// `ExportSettings.sequenceFrameCount`; the probe
// (`export_frame_count_proof.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a`, on
// `swift_build.py`'s line. No window, no Metal.
//
//   export_frame_count_probe [answer.json]
//
// One JSON object out (to the answer path, else stdout): `rows`, each a
// name, ok and detail. Every fixture is an `ExportSettings` DECODED from the
// JSON the core answers (`{"container":"gif","fps":[N,D],"range":{…}}`), so
// S0 first proves each fixture decoded the rate it names: `Fps` decodes only
// the two-element array and `lenient` turns anything else into 30 fps.
//
//   S1–S6  `sequenceFrameCount` at 12.5 fps (step 48 000 ticks): T = 0 → 1,
//          T = 40 000 (shorter than a frame) → 1, 144 000 → 3, 168 000 → 3
//          (floor), −48 000 → 1; fps 0/1 → nil
//   W1–W3  `ImageSequenceWriter.init` on those settings: 601 frames refused
//          naming 601, fps 0/1 refused in the rate sentence, 600 accepted
import Foundation

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1200))])
}

let gifStep: Ticks = 48_000  // one frame at 12.5 fps, 600 000 ticks a second

func settings(fps: [Int], duration: Ticks, start: Ticks = 0) -> ExportSettings? {
    let object: [String: Any] = [
        "container": "gif", "fps": fps, "width": 320, "height": 180,
        "range": ["start": start, "duration": duration],
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
    return try? JSONDecoder().decode(ExportSettings.self, from: data)
}

struct Fixture {
    let label: String
    let fps: [Int]
    let duration: Ticks
}

let fixtures: [Fixture] = [
    Fixture(label: "S1", fps: [25, 2], duration: 0),
    Fixture(label: "S2", fps: [25, 2], duration: 40_000),
    Fixture(label: "S3", fps: [25, 2], duration: 144_000),
    Fixture(label: "S4", fps: [25, 2], duration: 168_000),
    Fixture(label: "S5", fps: [25, 2], duration: -48_000),
    Fixture(label: "S6", fps: [0, 1], duration: 144_000),
    Fixture(label: "W1", fps: [25, 2], duration: 601 * gifStep),
    Fixture(label: "W2", fps: [0, 1], duration: 601 * gifStep),
    Fixture(label: "W3", fps: [25, 2], duration: 600 * gifStep),
]

// S0 — every fixture decodes the rate it names.
var undecoded: [String] = []
for fixture in fixtures {
    let got = settings(fps: fixture.fps, duration: fixture.duration)
    if got?.fps != Fps(num: fixture.fps[0], den: fixture.fps[1]) {
        undecoded.append("\(fixture.label) wanted \(fixture.fps), decoded "
            + (got.map { "\($0.fps.num)/\($0.fps.den)" } ?? "nothing"))
    }
}
check("S0 every S and W fixture decodes the fps it names", undecoded.isEmpty,
      undecoded.isEmpty ? "\(fixtures.count) fixtures" : undecoded.joined(separator: "; "))

// S1–S6 — the count itself.
let expected: [String: Int?] = ["S1": 1, "S2": 1, "S3": 3, "S4": 3, "S5": 1, "S6": nil]
let titles: [String: String] = [
    "S1": "12.5 fps, T = 0 → 1",
    "S2": "12.5 fps, T = 40 000 (two 30 fps frames, shorter than one GIF frame) → 1",
    "S3": "12.5 fps, T = 144 000 → 3",
    "S4": "12.5 fps, T = 168 000 → 3 (floor)",
    "S5": "12.5 fps, T = −48 000 → 1",
    "S6": "fps 0/1 → nil",
]
for fixture in fixtures where fixture.label.hasPrefix("S") {
    let want = expected[fixture.label] ?? nil
    let got = settings(fps: fixture.fps, duration: fixture.duration)?.sequenceFrameCount
    check("\(fixture.label) \(titles[fixture.label] ?? "")", got == want,
          "sequenceFrameCount \(got.map(String.init) ?? "nil"), want "
            + (want.map(String.init) ?? "nil"))
}

// W1–W3 — the writer refuses and accepts on that count.
let scratch = FileManager.default.temporaryDirectory
    .appendingPathComponent("export-frame-count-\(ProcessInfo.processInfo.processIdentifier)")
try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

/// nil when the writer was made; otherwise the `.failed` text, or a
/// description of any other error.
func writerError(_ label: String) -> (made: Bool, failed: String?, other: String?) {
    guard let fixture = fixtures.first(where: { $0.label == label }),
        let settings = settings(fps: fixture.fps, duration: fixture.duration),
        let project = ReelProject.new(width: 320, height: 180, fps: Fps(num: 30, den: 1))
    else { return (false, nil, "the fixture or the project could not be made") }
    do {
        _ = try ImageSequenceWriter(
            project: project, urls: [:], settings: settings, options: .none, graphics: nil,
            to: scratch.appendingPathComponent("\(label).gif"))
        return (true, nil, nil)
    } catch Exporter.ExportError.failed(let text) {
        return (false, text, nil)
    } catch {
        return (false, nil, "\(error)")
    }
}

let w1 = writerError("W1")
check("W1 12.5 fps, T = 601 frames: the writer throws .failed naming \"this range is 601\"",
      w1.failed?.contains("this range is 601") == true,
      "made \(w1.made), failed \(w1.failed ?? "nil"), other \(w1.other ?? "nil")")

let rateSentence = "The export frame rate is not one this build can step through."
let w2 = writerError("W2")
check("W2 fps 0/1: the writer throws .failed(\"\(rateSentence)\") exactly",
      w2.failed == rateSentence,
      "made \(w2.made), failed \(w2.failed ?? "nil"), other \(w2.other ?? "nil")")

let w3 = writerError("W3")
check("W3 12.5 fps, T = 600 frames: the writer is made", w3.made,
      "made \(w3.made), failed \(w3.failed ?? "nil"), other \(w3.other ?? "nil")")

try? FileManager.default.removeItem(at: scratch)

let answer = try JSONSerialization.data(withJSONObject: ["rows": rows], options: [.prettyPrinted])
if CommandLine.arguments.count > 1 {
    try answer.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
} else {
    FileHandle.standardOutput.write(answer)
}
exit(0)
