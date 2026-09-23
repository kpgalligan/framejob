// Road map 8, spike W0 — the on-device speech probe (q1, q2's Apple half, q3).
//
// It takes NOTHING from `app/Sources`: the app is built at macOS 15 and this
// is built at 26.0, so the two cannot share a module. Everything here is
// Speech and AVFoundation, and one JSON object goes to stdout per run.
//
//   xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 \
//       speech_probe.swift -o speech_probe
//
//   speech_probe words  <wav> <locale> [--bounded-s N]
//   speech_probe sf     <wav> <locale>
//   speech_probe assets <locale> [<not_installed_locale>]
//   speech_probe cancel <wav> <locale> <after_ms>
//
// `requestAuthorization` is NEVER called — it is an unanswerable prompt for an
// agent, and a bare Mach-O with no `NSSpeechRecognitionUsageDescription`
// CRASHES on it (`Transcriber.swift:284-289`). `downloadAndInstall` is never
// called either: a download is a person's decision and it would change host
// state the spike is only allowed to measure. `authorizationStatus()` is a
// READ and is the only authorization call in the file.
import AVFoundation
import Foundation
import Speech

// MARK: - The one JSON object

func emit(_ object: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        ?? Data(#"{"ok":false,"error":"the answer would not serialise"}"#.utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func usage(_ message: String) -> Never {
    emit(["ok": false, "error": message])
    exit(1)
}

func statusName(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .authorized: return "authorized"
    @unknown default: return "unknown"
    }
}

func seconds(_ time: CMTime) -> Any {
    let value = time.seconds
    return value.isFinite ? value : NSNull()
}

/// A number JSON can carry, or null. `CMTime.seconds` on an invalid time is a
/// NaN, and `JSONSerialization` refuses one rather than writing it.
func finite(_ value: Double) -> Any { value.isFinite ? value : NSNull() }

func audioSeconds(_ url: URL) -> Double? {
    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    let rate = file.processingFormat.sampleRate
    guard rate > 0 else { return nil }
    return Double(file.length) / rate
}

// MARK: - words — SpeechTranscriber over a file

/// What one analysis collected. Built inside the collecting task and handed
/// back whole, so a bound that expires still answers with what had arrived.
/// `@unchecked` because its two arrays are JSON-shaped `Any`, which no
/// `Sendable` check can see into; it crosses the actor once, at the end, and
/// nothing else holds a reference to it.
struct Collected: @unchecked Sendable {
    var runs: [[String: Any]] = []
    var results: [[String: Any]] = []
    var zeroLength = 0
    var finalRuns = 0
    var longest = 0.0
}

/// Named wall times collected from inside a task, so the answer can say WHERE
/// a run's seconds went rather than only how many there were, and the flag the
/// bound is enforced against.
///
/// An `NSLock` and not an actor, and the watchdog is an ordinary `Thread` and
/// not a `Task`, for one measured reason: a `SpeechAnalyzer` over a ten-minute
/// file has been seen to stop answering on this host, and while it does, an
/// awaiting watchdog never gets scheduled either — the bound goes by and
/// nothing prints, which turns the row's ANSWER into a kill from outside with
/// no measurement in it. A lock and a thread are outside the cooperative pool,
/// so the expiry is reported whatever the pool is doing. (A task group would be
/// worse still: it WAITS for every child it did not await, which makes the
/// sleep the answer's wall time whoever won.)
final class Stages: @unchecked Sendable {
    private let lock = NSLock()
    private var times: [String: Double] = [:]
    private var finished = false
    private var failure: String?

    func set(_ name: String, _ value: Double) {
        lock.lock(); times[name] = value; lock.unlock()
    }
    func finish(_ error: String?) {
        lock.lock(); failure = error; finished = true; lock.unlock()
    }
    func read() -> [String: Double] {
        lock.lock(); defer { lock.unlock() }; return times
    }
    func done() -> Bool {
        lock.lock(); defer { lock.unlock() }; return finished
    }
    func error() -> String? {
        lock.lock(); defer { lock.unlock() }; return failure
    }
}

@available(macOS 26.0, *)
final class Sink: @unchecked Sendable {
    private let lock = NSLock()
    private var collected = Collected()

    func take(_ result: SpeechTranscriber.Result) {
        lock.lock()
        defer { lock.unlock() }
        var count = 0
        var withRange = 0
        for run in result.text.runs {
            let text = String(result.text[run.range].characters)
            count += 1
            guard let range = run.audioTimeRange else { continue }
            withRange += 1
            guard result.isFinal else { continue }
            let start = range.start.seconds
            let end = range.end.seconds
            let confidence: Any = run.transcriptionConfidence.map { $0 as Any } ?? NSNull()
            collected.runs.append([
                "text": text,
                "start": finite(start), "end": finite(end),
                "confidence": confidence,
            ])
            collected.finalRuns += 1
            if end.isFinite, start.isFinite {
                if end <= start { collected.zeroLength += 1 }
                collected.longest = max(collected.longest, end - start)
            }
        }
        collected.results.append([
            "start": seconds(result.range.start), "end": seconds(result.range.end),
            "is_final": result.isFinal, "run_count": count, "runs_with_time": withRange,
            "text": String(result.text.characters),
        ])
    }

    func read() -> Collected {
        lock.lock(); defer { lock.unlock() }; return collected
    }
}

/// The answer as far as it got, in the shape `wordsMode` writes — built here
/// so the watchdog thread can print exactly what the ordinary exit would.
@available(macOS 26.0, *)
func wordsAnswer(
    _ base: [String: Any], sink: Sink, stages: Stages, started: Date, expired: Bool
) -> [String: Any] {
    var out = base
    let collected = sink.read()
    let failure = stages.error()
    out["expired"] = expired
    out["ok"] = !expired && failure == nil && stages.done()
    if let failure { out["error"] = failure }
    out["stages"] = stages.read()
    out["runs"] = collected.runs
    out["results"] = collected.results
    out["zero_length"] = collected.zeroLength
    out["longest_run_s"] = collected.longest
    out["spans_pause_note"] =
        "a run's own start and end are what a pause is measured against; "
        + "the longest final run here is \(String(format: "%.3f", collected.longest)) s"
    out["wall_s"] = Date().timeIntervalSince(started)
    out["status_after"] = statusName(SFSpeechRecognizer.authorizationStatus())
    return out
}

@available(macOS 26.0, *)
func wordsMode(wav: URL, locale: String, bound: Double) async -> [String: Any] {
    var out: [String: Any] = ["mode": "words", "locale": locale]
    out["status_before"] = statusName(SFSpeechRecognizer.authorizationStatus())
    out["seconds_audio"] = audioSeconds(wav) ?? 0.0
    out["bounded_s"] = bound
    let started = Date()
    let sink = Sink()
    do {
        let file = try AVAudioFile(forReading: wav)
        let transcriber = SpeechTranscriber(
            locale: Locale(identifier: locale), transcriptionOptions: [], reportingOptions: [],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence])
        out["installed_locales"] = await SpeechTranscriber.installedLocales.map { $0.identifier }
        out["is_available"] = SpeechTranscriber.isAvailable
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let reader = Task {
            for try await result in transcriber.results { sink.take(result) }
        }
        // The three waits are timed separately because they are three
        // different costs and the record needs them apart: the analysis
        // itself, the finalize, and the drain of the results sequence.
        let stages = Stages()
        let work = Task {
            do {
                let began = Date()
                let last = try await analyzer.analyzeSequence(from: file)
                stages.set("analyze_s", Date().timeIntervalSince(began))
                let finalizing = Date()
                if let last {
                    try await analyzer.finalizeAndFinish(through: last)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                stages.set("finalize_s", Date().timeIntervalSince(finalizing))
                let draining = Date()
                _ = try? await reader.value
                stages.set("drain_s", Date().timeIntervalSince(draining))
                stages.finish(nil)
            } catch {
                stages.finish("\(error)")
            }
        }
        // The bound, enforced OUTSIDE the cooperative pool. If the analysis
        // stops answering, this thread still wakes, prints what arrived and
        // ends the process — the expiry is the row's answer and it has to be
        // printable even when nothing else in the runtime can run.
        let base = out
        let watchdog = Thread {
            Thread.sleep(forTimeInterval: max(bound, 1.0))
            guard !stages.done() else { return }
            emit(wordsAnswer(base, sink: sink, stages: stages, started: started, expired: true))
            exit(0)
        }
        watchdog.stackSize = 512 * 1024
        watchdog.start()
        let deadline = Date().addingTimeInterval(max(bound, 1.0) + 5.0)
        while !stages.done(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let expired = !stages.done()
        if expired {
            work.cancel()
            reader.cancel()
            await analyzer.cancelAndFinishNow()
        }
        return wordsAnswer(out, sink: sink, stages: stages, started: started, expired: expired)
    } catch {
        out["ok"] = false
        out["error"] = "\(error)"
    }
    out["wall_s"] = Date().timeIntervalSince(started)
    out["status_after"] = statusName(SFSpeechRecognizer.authorizationStatus())
    if out["ok"] == nil { out["ok"] = false }
    return out
}

// MARK: - sf — the shipped engine, for the comparison

/// `SFSpeechRecognizer` over a file, bounded by the caller's own clock.
///
/// The third-party report road map 8 §2 cites is that it "silently never
/// starts" on macOS 26. That is a hang, and a hang is measured here as the
/// bound EXPIRING with nothing delivered — never as a crash and never as an
/// unbounded wait.
func sfMode(wav: URL, locale: String, bound: Double) -> [String: Any] {
    var out: [String: Any] = ["mode": "sf", "locale": locale]
    out["status_before"] = statusName(SFSpeechRecognizer.authorizationStatus())
    out["seconds_audio"] = audioSeconds(wav) ?? 0.0
    let started = Date()
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
        out["ok"] = false
        out["error"] = "SFSpeechRecognizer(locale:) answered nil for \(locale)"
        out["wall_s"] = Date().timeIntervalSince(started)
        out["status_after"] = statusName(SFSpeechRecognizer.authorizationStatus())
        return out
    }
    out["is_available"] = recognizer.isAvailable
    out["supports_on_device"] = recognizer.supportsOnDeviceRecognition
    let request = SFSpeechURLRecognitionRequest(url: wav)
    request.shouldReportPartialResults = false
    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
    request.addsPunctuation = true
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    recognizer.queue = queue
    let done = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var segments: [[String: Any]] = []
    // EVERY callback, not only the final one: with partial results off the
    // engine may still deliver a file as several results, each carrying
    // `speechRecognitionMetadata`, and only the last `isFinal`. `segments`
    // stays the final result's alone; `segments_accumulated` is every
    // metadata-bearing or final result's, in arrival order.
    var callbacks: [[String: Any]] = []
    var accumulated: [[String: Any]] = []
    var problem: String?
    var delivered = false
    let task = recognizer.recognitionTask(with: request) { result, error in
        lock.lock()
        if let error {
            problem = "\(error)"
            callbacks.append(["error": "\(error)"])
            lock.unlock()
            done.signal()
            return
        }
        guard let result else { lock.unlock(); return }
        delivered = true
        let rows: [[String: Any]] = result.bestTranscription.segments.map {
            ["text": $0.substring, "start": $0.timestamp, "duration": $0.duration,
             "confidence": $0.confidence]
        }
        let hasMetadata = result.speechRecognitionMetadata != nil
        callbacks.append([
            "is_final": result.isFinal, "has_metadata": hasMetadata,
            "segment_count": rows.count, "segments": rows,
            "text": result.bestTranscription.formattedString,
        ])
        if hasMetadata || result.isFinal { accumulated.append(contentsOf: rows) }
        if result.isFinal {
            segments = rows
            lock.unlock()
            done.signal()
            return
        }
        lock.unlock()
    }
    let expired = done.wait(timeout: .now() + bound) == .timedOut
    if expired { task.cancel() }
    lock.lock()
    out["segments"] = segments
    out["callbacks"] = callbacks
    out["segments_accumulated"] = accumulated
    out["error"] = problem ?? NSNull()
    out["any_result_delivered"] = delivered
    lock.unlock()
    out["expired"] = expired
    out["ok"] = !expired && problem == nil && !segments.isEmpty
    out["wall_s"] = Date().timeIntervalSince(started)
    out["status_after"] = statusName(SFSpeechRecognizer.authorizationStatus())
    return out
}

// MARK: - assets — AssetInventory, read only

@available(macOS 26.0, *)
func assetsMode(locale: String, other: String?) async -> [String: Any] {
    var out: [String: Any] = ["mode": "assets", "locale": locale]
    let supported = await SpeechTranscriber.supportedLocales.map { $0.identifier }
    let installed = await SpeechTranscriber.installedLocales.map { $0.identifier }
    out["supported"] = supported
    out["installed"] = installed
    out["reserved"] = await AssetInventory.reservedLocales.map { $0.identifier }
    out["max_reserved"] = AssetInventory.maximumReservedLocales
    let chosen = other ?? supported.first(where: { !installed.contains($0) })
    out["other_locale"] = chosen ?? NSNull()

    func module(_ identifier: String) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: Locale(identifier: identifier), transcriptionOptions: [],
            reportingOptions: [], attributeOptions: [.audioTimeRange])
    }
    func name(_ status: AssetInventory.Status) -> String {
        switch status {
        case .unsupported: return "unsupported"
        case .supported: return "supported"
        case .downloading: return "downloading"
        case .installed: return "installed"
        @unknown default: return "unknown"
        }
    }
    out["status_installed"] = name(await AssetInventory.status(forModules: [module(locale)]))
    if let chosen {
        out["status_other"] = name(await AssetInventory.status(forModules: [module(chosen)]))
    } else {
        out["status_other"] = NSNull()
    }
    // `assetInstallationRequest` only ASKS. The request it may answer with is
    // read for its `progress` and then dropped: `downloadAndInstall()` is
    // never called anywhere in this file.
    do {
        let request = try await AssetInventory.assetInstallationRequest(
            supporting: [module(locale)])
        out["request_nil"] = request == nil
    } catch {
        out["request_nil"] = NSNull()
        out["request_error"] = "\(error)"
    }
    if let chosen {
        do {
            let request = try await AssetInventory.assetInstallationRequest(
                supporting: [module(chosen)])
            if let progress = request?.progress {
                out["progress"] = [
                    "total_unit_count": progress.totalUnitCount,
                    "fraction_completed": progress.fractionCompleted,
                    "kind": progress.kind?.rawValue ?? "none",
                    "is_indeterminate": progress.isIndeterminate,
                ]
                out["other_request_nil"] = false
            } else {
                out["progress"] = NSNull()
                out["other_request_nil"] = true
            }
        } catch {
            out["progress"] = NSNull()
            out["other_request_error"] = "\(error)"
        }
    } else {
        out["progress"] = NSNull()
    }
    out["ok"] = true
    return out
}

// MARK: - cancel — how an analysis stops

@available(macOS 26.0, *)
func cancelMode(wav: URL, locale: String, afterMilliseconds: Int) async -> [String: Any] {
    var out: [String: Any] = ["mode": "cancel", "locale": locale,
                              "cancelled_after_ms": afterMilliseconds]
    let started = Date()
    let sink = Sink()
    do {
        let file = try AVAudioFile(forReading: wav)
        let transcriber = SpeechTranscriber(
            locale: Locale(identifier: locale), transcriptionOptions: [], reportingOptions: [],
            attributeOptions: [.audioTimeRange])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let reader = Task {
            for try await result in transcriber.results { sink.take(result) }
        }
        let work = Task { () -> CMTime? in try await analyzer.analyzeSequence(from: file) }
        try await Task.sleep(nanoseconds: UInt64(max(afterMilliseconds, 0)) * 1_000_000)
        let before = sink.read()
        out["results_before_cancel"] = before.results.count
        out["runs_before_cancel"] = before.finalRuns
        await analyzer.cancelAndFinishNow()
        work.cancel()
        reader.cancel()
        // Deliberately NOT awaited: whether `analyzeSequence` returns after a
        // cancel is part of what this row asks, and waiting on it here would
        // turn a "no" into a hang instead of an answer.
        out["ok"] = true
        out["error"] = NSNull()
    } catch {
        out["ok"] = false
        out["error"] = "\(error)"
        if out["results_before_cancel"] == nil { out["results_before_cancel"] = 0 }
    }
    out["wall_s"] = Date().timeIntervalSince(started)
    return out
}

// MARK: - main

@main
enum Probe {
    static func main() async {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            usage("usage: speech_probe words|sf|assets|cancel …")
        }
        guard #available(macOS 26.0, *) else {
            usage("speech_probe needs macOS 26.0; this host is older")
        }
        switch arguments[1] {
        case "words":
            guard arguments.count >= 4 else {
                usage("usage: speech_probe words <wav> <locale> [--bounded-s N]")
            }
            var bound = 600.0
            if let index = arguments.firstIndex(of: "--bounded-s"), index + 1 < arguments.count,
               let value = Double(arguments[index + 1]) {
                bound = value
            }
            emit(await wordsMode(
                wav: URL(fileURLWithPath: arguments[2]), locale: arguments[3], bound: bound))
        case "sf":
            guard arguments.count >= 4 else { usage("usage: speech_probe sf <wav> <locale>") }
            var bound = 120.0
            if let index = arguments.firstIndex(of: "--bounded-s"), index + 1 < arguments.count,
               let value = Double(arguments[index + 1]) {
                bound = value
            }
            emit(sfMode(
                wav: URL(fileURLWithPath: arguments[2]), locale: arguments[3], bound: bound))
        case "assets":
            guard arguments.count >= 3 else {
                usage("usage: speech_probe assets <locale> [<not_installed_locale>]")
            }
            emit(await assetsMode(
                locale: arguments[2], other: arguments.count >= 4 ? arguments[3] : nil))
        case "cancel":
            guard arguments.count >= 5, let after = Int(arguments[4]) else {
                usage("usage: speech_probe cancel <wav> <locale> <after_ms>")
            }
            emit(await cancelMode(
                wav: URL(fileURLWithPath: arguments[2]), locale: arguments[3],
                afterMilliseconds: after))
        default:
            usage("unknown mode \(arguments[1])")
        }
        exit(0)
    }
}
