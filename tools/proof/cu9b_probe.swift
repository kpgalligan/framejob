// Road map "creator-jobs" CU9b (spec §11 CU-93) — Speed Up Typing's speech step and its
// wait's bound, driven through the app's own `SpeedUpTyping`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`,
// through `swift_build.py`'s one line. One process:
//
//   cu9b_probe <request.json>
//
// The request names `work` (this run's directory). The answer is one JSON object on stdout,
// `{"rows": [...]}`, each row `{"id", "pass", "detail", "instrument"}`; `cu9b_proof.py` prints
// and scores them.
//
// Rows:
//   P1  `SpeedUpTyping.speech` over five audio media: one whose speech is stored is skipped
//       (`.ready([])`); one whose cache is current and loads is `.ready` with exactly the
//       `set_media_speech` its probabilities give (the run of chunks 2–4, written here, read
//       back as [[2, 5] × chunk]); one not current while detection is available is
//       `.pending([its name])`; one with no file is refused "<name> is offline, so its speech
//       cannot be read."; one not current while detection is unavailable is refused "Speech
//       detection is unavailable on this Mac, so Speed Up Typing cannot tell typing from
//       talking." Every expected sentence is the decision's literal text.
//   P2  `SpeedUpTyping.gaveUp(waitingFor:)` is false at 299 s and true at 300 s.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2,
    let requestData = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
    let workPath = request["work"] as? String
else {
    FileHandle.standardError.write(Data("usage: cu9b_probe <request.json>\n".utf8))
    exit(2)
}
let work = URL(fileURLWithPath: workPath, isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

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

// MARK: - P1 — the speech step's five answers

let present = work.appendingPathComponent("present.m4a")
FileManager.default.createFile(atPath: present.path, contents: Data(repeating: 1, count: 64))
let missing = work.appendingPathComponent("missing.m4a")
try? FileManager.default.removeItem(at: missing)
let cache = work.appendingPathComponent("cache", isDirectory: true)
try? FileManager.default.removeItem(at: cache)
_ = MediaImporter.ensureDirectory(cache)

func mediaRow(_ id: Int, _ path: URL, speech: String = "") -> String {
    """
    {"id": \(id), "path": "\(path.path)", "kind": "audio", "duration": 6000000,
     "has_video": false, "has_audio": true\(speech)}
    """
}
let fixture = """
    {"version": 38, "canvas": {"width": 640, "height": 360, "fps": [30, 1],
     "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true},
     "media": [\(mediaRow(1, present, speech: #", "speech": []"#)), \(mediaRow(2, present)),
               \(mediaRow(3, present)), \(mediaRow(4, missing)), \(mediaRow(5, present))],
     "tracks": [], "clips": [], "markers": [], "next_id": 100}
    """

func describe(_ s: SpeedUpTypingSpeech) -> String {
    switch s {
    case .ready(let ops): return "ready(\(ops.map(\.json)))"
    case .pending(let names): return "pending(\(names))"
    case .refused(let why): return "refused(\(why))"
    }
}

do {
    let snapshot = try ReelProject.from(json: fixture).snapshot
    guard let ready = snapshot.media(2), let stamp = MediaImporter.CacheStamp.stamp(
        for: ready, url: present)
    else {
        row("P1", false, "instrument: the fixture's media 2 or its stamp", instrument: true)
        finish()
    }
    // Chunks 2, 3 and 4 at certainty, the rest silent.
    let p: [Float] = [0, 0, 1, 1, 1, 0, 0, 0]
    let bin = MediaImporter.speechURL(for: 2, in: cache)
    _ = MediaImporter.ensureDirectory(bin.deletingLastPathComponent())
    try p.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: bin)
    let marked = MediaImporter.writeStamp(
        MediaImporter.SpeechStamp(stamp), to: MediaImporter.speechMarkerURL(for: 2, in: cache))
    let chunk = MediaSpeech.chunkTicks
    let name = { (id: UInt32) in snapshot.media(id)?.name ?? "" }
    func ask(_ id: UInt32, available: Bool, current: Bool) -> SpeedUpTypingSpeech {
        SpeedUpTyping.speech(
            for: [id], in: snapshot, cacheDirectory: cache, available: available,
            isCurrent: { _ in current })
    }
    let cases: [(String, SpeedUpTypingSpeech, SpeedUpTypingSpeech)] = [
        ("stored", ask(1, available: true, current: false), .ready([])),
        ("ready", ask(2, available: true, current: true),
         .ready([.setMediaSpeech(media: 2, spans: [[2 * chunk, 5 * chunk]])])),
        ("pending", ask(3, available: true, current: false), .pending([name(3)])),
        ("offline", ask(4, available: true, current: true),
         .refused("\(name(4)) is offline, so its speech cannot be read.")),
        ("unavailable", ask(5, available: false, current: false),
         .refused("Speech detection is unavailable on this Mac, so Speed Up Typing cannot "
                  + "tell typing from talking.")),
    ]
    let wrong = cases.filter { $0.1 != $0.2 }
    row("P1", marked && wrong.isEmpty,
        "marker written \(marked); "
            + cases.map { "\($0.0): \(describe($0.1))" + ($0.1 == $0.2 ? "" : " (want \(describe($0.2)))") }
            .joined(separator: "; "))
} catch {
    row("P1", false, "instrument: \(error)", instrument: true)
}

// MARK: - P2 — the wait's bound

let at299 = SpeedUpTyping.gaveUp(waitingFor: 299)
let at300 = SpeedUpTyping.gaveUp(waitingFor: 300)
row("P2", !at299 && at300, "gaveUp at 299 s \(at299), at 300 s \(at300)")

finish()
