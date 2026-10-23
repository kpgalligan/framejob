// Road map "cut-by-transcript", CT-0 — the filler spike's probe
// (`filler_spike.py` builds and runs it). Compiled through
// `swift_build.build` over every file in `app/Sources` but the app's own
// `main.swift`, at macOS 26.0, with THIS file as `main.swift`, so the audio is
// extracted and transcribed by the app's own `Transcriber.extractAudio` and
// `SpeechEngine.transcribe`, not a copy of them. It may import Speech itself
// (the app may not, outside `SpeechEngine.swift`).
//
//   filler-spike-probe <work-dir> <media-path>…
//
// Line 1 is `{"locale":"en-US","installed":true|false|null}` from
// `SpeechEngine.isInstalled`; anything but true exits 3 there. Then one line
// per media: `{"file","ok","error","seconds","runs":[{"text","start","end"}]}`.
// The extracted WAV is deleted after each file; a file with no answer within
// 900 s exits 4 after its delete. It never downloads a model,
// never asks for Speech authorization and never touches the network.
import AVFoundation
import AppKit
import Foundation

/// `body` on a thread of its own — `SpeechEngine.transcribe` refuses main —
/// waited for with main's run loop turning, so a completion posted to main
/// still lands. nil past `bound`. (`speech_engine_probe.swift`'s, copied.)
func offMain<T>(_ bound: Double, _ body: @escaping () -> T) -> T? {
    let lock = NSLock()
    var answer: T?
    var done = false
    let thread = Thread {
        let value = body()
        lock.lock()
        answer = value
        done = true
        lock.unlock()
    }
    thread.stackSize = 8 << 20
    thread.start()
    let deadline = Date().addingTimeInterval(bound)
    while Date() < deadline {
        lock.lock()
        let finished = done
        let value = answer
        lock.unlock()
        if finished { return value }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return nil
}

func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
        let line = String(data: data, encoding: .utf8)
    else {
        print("{\"ok\":false,\"error\":\"unencodable line\"}")
        return
    }
    print(line)
    fflush(stdout)
}

_ = NSApplication.shared
let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("usage: filler-spike-probe <work-dir> <media-path>…")
    exit(2)
}
let work = URL(fileURLWithPath: arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
let locale = Locale(identifier: "en-US")

let installed = SpeechEngine.isInstalled(locale)
emit(["locale": "en-US", "installed": installed.map { $0 as Any } ?? NSNull()])
guard installed == true else { exit(3) }

enum Outcome {
    case heard(seconds: Double, runs: [SpeechEngine.Run])
    case failed(seconds: Double, error: String)
}

for (index, path) in arguments.dropFirst(2).enumerated() {
    let media = URL(fileURLWithPath: path)
    let wav = work.appendingPathComponent("\(index + 1).wav")
    let answered: Outcome? = offMain(900) {
        var seconds = 0.0
        do {
            let frames = try Transcriber.extractAudio(
                url: media, name: media.lastPathComponent, range: Transcriber.wholeAsset,
                to: wav, cancel: Transcriber.CancelToken())
            seconds = Double(frames) / 16000
            let runs = try SpeechEngine.transcribe(
                file: wav, locale: locale, seconds: seconds, name: media.lastPathComponent,
                cancel: Transcriber.CancelToken(), progress: { _ in })
            return .heard(seconds: seconds, runs: runs)
        } catch {
            return .failed(seconds: seconds, error: String(describing: error))
        }
    }
    guard let outcome = answered else {
        // The worker may still be extracting: the failed line goes out
        // first, then the WAV is removed and the process exits at once,
        // ending the worker with it, so no WAV is written after the remove.
        emit([
            "file": media.lastPathComponent, "ok": false, "error": "no answer within 900 s",
            "seconds": 0, "runs": [Any](),
        ])
        try? FileManager.default.removeItem(at: wav)
        exit(4)
    }
    try? FileManager.default.removeItem(at: wav)
    switch outcome {
    case .heard(let seconds, let runs):
        emit([
            "file": media.lastPathComponent, "ok": true, "error": NSNull(), "seconds": seconds,
            "runs": runs.map { ["text": $0.text, "start": $0.start, "end": $0.end] },
        ])
    case .failed(let seconds, let error):
        emit([
            "file": media.lastPathComponent, "ok": false, "error": error, "seconds": seconds,
            "runs": [Any](),
        ])
    }
}
exit(0)
