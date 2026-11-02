// Road map "creator-jobs" TX1, spike TX-S1 — the fill's cost: how fast does
// `SpeechEngine` recognise long speech on this Mac, and can one run cover a
// whole file?
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift` (module FrameJob, the staticlib), through
// `tools/proof/swift_build.py`, by `fill_spike.py`. One run a process:
//
//   fill-spike <file> <in seconds> <length seconds> <language> <out.json>
//
// The run is the app's own on-device path for one `Transcriber.Job` from `in`
// for `length` (a whole file is in 0, length its duration):
// `Transcriber.requireModel`, then `Transcriber().extractAudio` (the 16 kHz
// mono WAV), then `SpeechEngine.transcribe`. Measured: the extract's and the
// recognition's wall time, the WAV's bytes, the words, and the peak of this
// process's `phys_footprint` above its value before the run, sampled every
// 20 ms on a thread of its own. `recognising` is printed (and flushed) the
// moment the extract is done, so a caller can time another measurement
// against the recognition alone. The answer is written to `out.json`;
// stdout's last line is a one-line summary.
import Foundation

let args = CommandLine.arguments
guard args.count == 6, let inSeconds = Double(args[2]), let lengthSeconds = Double(args[3])
else {
    FileHandle.standardError.write(
        Data("usage: fill-spike <file> <in s> <length s> <language> <out.json>\n".utf8))
    exit(2)
}
let url = URL(fileURLWithPath: args[1])
let language = Transcriber.Language(identifier: args[4], displayName: args[4])
let out = URL(fileURLWithPath: args[5])

func footprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}

final class Peak: @unchecked Sendable {
    private let lock = NSLock()
    private var high: UInt64 = 0
    private var stopped = false

    func start() {
        Thread.detachNewThread { [self] in
            while true {
                let now = footprint()
                lock.lock()
                if now > high { high = now }
                let done = stopped
                lock.unlock()
                if done { return }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    func stop() -> UInt64 {
        lock.lock()
        stopped = true
        let value = max(high, footprint())
        lock.unlock()
        return value
    }
}

let perSecond = Double(ReelTime.perSecond)
let job = Transcriber.Job(
    clip: 0, media: 0, name: url.lastPathComponent, source: url,
    sourceIn: Ticks((inSeconds * perSecond).rounded()),
    sourceLength: Ticks((lengthSeconds * perSecond).rounded()), start: 0,
    duration: Ticks((lengthSeconds * perSecond).rounded()), speed: 1)

var answer: [String: Any] = ["in": inSeconds, "length": lengthSeconds, "language": args[4]]
let done = DispatchSemaphore(value: 0)
Thread.detachNewThread {
    defer { done.signal() }
    let cancel = Transcriber.CancelToken()
    let base = footprint()
    let peak = Peak()
    peak.start()
    do {
        try Transcriber.requireModel(language)
        let t0 = Date()
        let extract = try Transcriber().extractAudio(job, cancel: cancel)
        defer { try? FileManager.default.removeItem(at: extract.url) }
        let t1 = Date()
        let bytes = (try? FileManager.default.attributesOfItem(atPath: extract.url.path)[.size])
            as? NSNumber
        print("recognising")
        fflush(stdout)
        let runs = try SpeechEngine.transcribe(
            file: extract.url, locale: language.locale, seconds: extract.seconds,
            name: job.name, cancel: cancel, progress: { _ in })
        let t2 = Date()
        answer["extract_s"] = t1.timeIntervalSince(t0)
        answer["recognise_s"] = t2.timeIntervalSince(t1)
        answer["wall_s"] = t2.timeIntervalSince(t0)
        answer["wav_bytes"] = bytes?.intValue ?? -1
        answer["wav_seconds"] = extract.seconds
        answer["words"] = runs.map { [$0.text, $0.start, $0.end] as [Any] }
        answer["word_count"] = runs.count
    } catch {
        answer["error"] = error.localizedDescription
    }
    let high = peak.stop()
    answer["footprint_base"] = Int(base)
    answer["footprint_peak"] = Int(high)
    answer["peak_added_bytes"] = Int(high) - Int(base)
}
done.wait()
do {
    let data = try JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
    try data.write(to: out)
} catch {
    FileHandle.standardError.write(Data("could not write \(out.path): \(error)\n".utf8))
    exit(1)
}
let summary: [String: Any] = answer.filter { $0.key != "words" }
if let line = try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]) {
    print(String(decoding: line, as: UTF8.self))
}
exit(answer["error"] == nil ? 0 : 1)
