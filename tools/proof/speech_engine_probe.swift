// Road map 8, W2 — the on-device engine's probe (`speech_engine_proof.py`
// builds and runs it). Compiled from `app/Sources` minus the app's
// `main.swift`, over `harness/build.sh`'s own swiftc line at macOS 26.0, with
// THIS file as `main.swift` — so every row below calls the app's own code,
// not a copy of it. It is a probe, so it may import Speech itself (the app
// may not, outside `SpeechEngine.swift`).
//
//   speech-engine-probe <pangram.wav> <ten.wav>
//
// Every row prints `  ok   <row> — …`, `  FAIL <row> — …` or
// `  SKIP <row> — …`; the last line is the score. A mutant is scored by the
// row NAMES that failed, so a row's name never changes. Rows: P6, P7, P4, P1 ×2,
// P2 ×3, P3, P5 ×4, then P8 LAST — it holds the gate every row above uses.
import AVFoundation
import AppKit
import Speech

var passed = 0
var failed = 0
var skipped = 0

func check(_ row: String, _ good: Bool, _ detail: String) {
    if good { passed += 1 } else { failed += 1 }
    print("  \(good ? "ok  " : "FAIL") \(row) — \(detail)")
}

func skip(_ row: String, _ why: String) {
    skipped += 1
    print("  SKIP \(row) — \(why)")
}

/// `body` on a thread of its own — `SpeechEngine.transcribe` refuses main —
/// waited for with main's run loop turning, so a completion posted to main
/// still lands. nil past `bound`.
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

/// An `async` question, answered synchronously within `bound`.
final class Slot<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?
    func put(_ answer: T) {
        lock.lock()
        value = answer
        lock.unlock()
    }
    func read() -> T? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

func asked<T>(_ bound: Double, _ body: @escaping @Sendable () async -> T) -> T? {
    let slot = Slot<T>()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        slot.put(await body())
        done.signal()
    }
    guard done.wait(timeout: .now() + bound) == .success else { return nil }
    return slot.read()
}

func seconds(of url: URL) -> Double? {
    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    return Double(file.length) / file.processingFormat.sampleRate
}

func job(_ url: URL, _ length: Double) -> Transcriber.Job {
    let ticks = Ticks(length * Double(ReelTime.perSecond))
    return Transcriber.Job(
        clip: 1, media: 1, name: url.lastPathComponent, source: url, sourceIn: 0,
        sourceLength: ticks, start: 0, duration: ticks, speed: 1)
}

let pangramWords = (
    "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs. "
        + "How vexingly quick daft zebras jump."
).lowercased().split(separator: " ").map {
    $0.trimmingCharacters(in: .punctuationCharacters)
}

/// How many of the pangram's 23 words a list of tokens holds, each counted
/// at most as often as the pangram says it.
func matched(_ tokens: [String]) -> Int {
    var wanted: [String: Int] = [:]
    for word in pangramWords { wanted[word, default: 0] += 1 }
    var hits = 0
    for token in tokens {
        let word = token.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if let left = wanted[word], left > 0 {
            wanted[word] = left - 1
            hits += 1
        }
    }
    return hits
}

_ = NSApplication.shared
let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: speech-engine-probe <pangram.wav> <ten.wav>")
    exit(2)
}
let pangram = URL(fileURLWithPath: arguments[1])
let ten = URL(fileURLWithPath: arguments[2])
guard let pangramSeconds = seconds(of: pangram), let tenSeconds = seconds(of: ten) else {
    print("  FAIL fixtures — a fixture would not open")
    exit(1)
}

let installed = Transcriber.languages()
let supported = Transcriber.supportedLanguages()
let english = installed.first { $0.identifier == "en-US" }

// ---- P6, P7: the engine itself, over the two fixtures ----------------------

if english == nil {
    skip("P6 pangram", "en-US is not installed on this host")
    skip("P7 ten minutes", "en-US is not installed on this host")
} else {
    let runs = offMain(120) {
        try? SpeechEngine.transcribe(
            file: pangram, locale: Locale(identifier: "en-US"), seconds: pangramSeconds,
            name: "pangram", cancel: Transcriber.CancelToken(), progress: { _ in })
    } ?? nil
    let tokens = runs?.map { $0.text } ?? []
    let untrimmed = tokens.filter {
        $0 != $0.trimmingCharacters(in: .whitespacesAndNewlines) || $0.isEmpty
    }
    check("P6 pangram", runs != nil && untrimmed.isEmpty && matched(tokens) >= 20,
          "\(tokens.count) runs, \(matched(tokens)) of \(pangramWords.count) pangram words, "
            + "\(untrimmed.count) with whitespace at an end: \(untrimmed.prefix(3))")

    let whole = offMain(600) {
        try? SpeechEngine.transcribe(
            file: ten, locale: Locale(identifier: "en-US"), seconds: tenSeconds,
            name: "ten", cancel: Transcriber.CancelToken(), progress: { _ in })
    } ?? nil
    let last = whole?.last?.end ?? 0
    check("P7 ten minutes", (whole?.count ?? 0) >= 1000 && last >= tenSeconds - 5,
          "\(whole?.count ?? 0) runs over \(String(format: "%.1f", tenSeconds)) s, the last "
            + "ending at \(String(format: "%.1f", last)) s")
}

// ---- P4: an uninstalled locale never reaches the engine --------------------

let preferred = ["fr-FR", "de-DE", "ja-JP", "ko-KR"]
let uninstalled = preferred.compactMap { tag in
    supported.first { $0.identifier == tag && !$0.installed }
}.first ?? supported.first { !$0.installed }
if let missing = uninstalled {
    let began = Date()
    let answer: Result<Transcriber.Outcome, any Error>? = offMain(60) {
        Result {
            try Transcriber().transcribe(
                [job(pangram, pangramSeconds)], language: missing, frame: 20_000,
                pages: CaptionPages.Request(style: .subtitles, canvas: CGSize(width: 1920, height: 1080)), cancel: Transcriber.CancelToken())
        }
    }
    let wall = Date().timeIntervalSince(began)
    var refused = false
    if case .failure(let error)? = answer,
        let reason = error as? Transcriber.TranscribeError,
        reason == .notInstalled(missing.displayName)
    {
        refused = true
    }
    check("P4 not installed", refused && wall < 5,
          "\(missing.identifier) answered \(String(describing: answer)) in "
            + "\(String(format: "%.2f", wall)) s")
} else {
    skip("P4 not installed", "every supported locale is installed on this host")
}

// ---- P1: a cancel lands ----------------------------------------------------

if let english {
    let token = Transcriber.CancelToken()
    let transcriber = Transcriber()
    var outcome: Result<Transcriber.Outcome, any Error>?
    var heard = 0.0
    transcriber.run(
        jobs: [job(ten, tenSeconds)], language: english, frame: 20_000,
        pages: CaptionPages.Request(style: .subtitles, canvas: CGSize(width: 1920, height: 1080)), cancel: token,
        progress: { fraction, _ in heard = max(heard, fraction) },
        completion: { outcome = $0 })
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    token.cancel()
    let cancelled = Date()
    while outcome == nil, Date().timeIntervalSince(cancelled) < 5 {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    let wall = Date().timeIntervalSince(cancelled)
    var good = false
    if case .failure(let error)? = outcome,
        (error as? Transcriber.TranscribeError) == .cancelled
    {
        good = true
    }
    check("P1 cancel", good && wall < 5,
          "answered \(outcome.map { String(describing: $0) } ?? "nothing") "
            + "\(String(format: "%.2f", wall)) s after the cancel (progress had reached "
            + "\(String(format: "%.3f", heard)))")

    // The same cancel once the ENGINE is running: at 300 ms the run above
    // may still be extracting, so this one waits for the analysis to report
    // progress before it cancels.
    let midToken = Transcriber.CancelToken()
    var midOutcome: Result<Transcriber.Outcome, any Error>?
    var midHeard = 0.0
    transcriber.run(
        jobs: [job(ten, tenSeconds)], language: english, frame: 20_000,
        pages: CaptionPages.Request(style: .subtitles, canvas: CGSize(width: 1920, height: 1080)), cancel: midToken,
        progress: { fraction, _ in midHeard = max(midHeard, fraction) },
        completion: { midOutcome = $0 })
    let waiting = Date()
    while midHeard < 0.02, midOutcome == nil, Date().timeIntervalSince(waiting) < 60 {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    let reached = midHeard
    midToken.cancel()
    let stopped = Date()
    while midOutcome == nil, Date().timeIntervalSince(stopped) < 5 {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    let midWall = Date().timeIntervalSince(stopped)
    var midGood = false
    if case .failure(let error)? = midOutcome,
        (error as? Transcriber.TranscribeError) == .cancelled
    {
        midGood = true
    }
    check("P1 cancel mid-analysis", midGood && midWall < 5 && reached > 0 && reached < 1,
          "cancelled at progress \(String(format: "%.3f", reached)); answered "
            + "\(midOutcome.map { String(describing: $0) } ?? "nothing") "
            + "\(String(format: "%.2f", midWall)) s later")
} else {
    skip("P1 cancel", "en-US is not installed on this host")
    skip("P1 cancel mid-analysis", "en-US is not installed on this host")
}

// ---- P2: the two lists, the tag spelling, the reservations -----------------

let supportedTags = Set(supported.map { $0.identifier })
let underscored = (installed + supported).filter {
    $0.identifier.contains("_") || !$0.identifier.contains("-")
}
check("P2 lists",
      !installed.isEmpty && installed.allSatisfy { supportedTags.contains($0.identifier) }
        && installed.allSatisfy { $0.installed } && underscored.isEmpty,
      "\(installed.count) installed ⊆ \(supported.count) supported, "
        + "\(underscored.count) without a BCP-47 hyphen: \(underscored.prefix(3).map { $0.identifier })")
check("P2 bcp47",
      Locale(identifier: "en-US").identifier(.bcp47) == Locale(identifier: "en_US").identifier(.bcp47),
      "en-US → \(Locale(identifier: "en-US").identifier(.bcp47)), "
        + "en_US → \(Locale(identifier: "en_US").identifier(.bcp47))")
var reserved: [String] = ["<not asked>"]
let settle = Date()
repeat {
    reserved = asked(10) { await AssetInventory.reservedLocales.map { $0.identifier } } ?? ["<timed out>"]
    if reserved.isEmpty { break }
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
} while Date().timeIntervalSince(settle) < 10
check("P2 reservations", reserved.isEmpty,
      "AssetInventory.reservedLocales after the runs above: \(reserved)")

// ---- P3: the default language is this Mac's own ----------------------------

let current = Locale.current.identifier(.bcp47)
let lower = current.lowercased()
if !supported.contains(where: { $0.identifier.lowercased() == lower })
    && !installed.contains(where: { $0.identifier.lowercased() == lower })
{
    skip("P3 default", "this host's tag \(current) is in neither list")
} else {
    let overSupported = Transcriber.defaultLanguage(in: supported)?.identifier ?? "<none>"
    let overInstalled = Transcriber.defaultLanguage(in: installed)?.identifier ?? "<none>"
    check("P3 default",
          overSupported.lowercased() == lower && overInstalled.lowercased() == lower,
          "Locale.current is \(current); defaultLanguage answers \(overSupported) over the "
            + "supported list and \(overInstalled) over the installed one")
}

// ---- P5: the sheet's Download row ------------------------------------------

func sheetRow() {
    let suite = "framejob.speech-engine-probe.\(ProcessInfo.processInfo.processIdentifier)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        check("P5 sheet", false, "no defaults suite")
        return
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    let french = Transcriber.Language(
        identifier: "fr-FR", displayName: "French (France)", installed: false)
    let american = Transcriber.Language(
        identifier: "en-US", displayName: "English (United States)", installed: true)
    let sheet = TranscribeSheetController(
        document: ProjectDocument(), store: MemoryStore(), defaults: defaults,
        environment: [:], languages: [american, french])
    _ = sheet.view
    func choose(_ tag: String) {
        if let index = sheet.languagePopup.itemArray.firstIndex(where: {
            $0.representedObject as? String == tag
        }) {
            sheet.languagePopup.selectItem(at: index)
        }
    }
    func rowShown() -> Bool { !sheet.grid.row(at: 1).isHidden }
    choose("fr-FR")
    sheet.refreshDownloadRow()
    let title = sheet.languagePopup.selectedItem?.title ?? ""
    check("P5 offered",
          rowShown() && sheet.downloadButton.title == "Download" && title.contains("not installed"),
          "fr-FR selected: row shown \(rowShown()), button “\(sheet.downloadButton.title)”, "
            + "popup row “\(title)”")

    sheet.downloading = french
    sheet.downloadProgress = nil
    sheet.refreshDownloadRow()
    check("P5 awaiting progress",
          rowShown() && sheet.downloadButton.title == "Cancel" && !sheet.downloadButton.isEnabled,
          "before the request's Progress: button “\(sheet.downloadButton.title)”, "
            + "enabled \(sheet.downloadButton.isEnabled)")

    sheet.downloadProgress = Progress()
    choose("en-US")
    sheet.refreshDownloadRow()
    let label = sheet.downloadLabel.stringValue
    check("P5 locked",
          rowShown() && !sheet.languagePopup.isEnabled && !sheet.enginePopup.isEnabled
            && label.contains("French (France)") && sheet.downloadButton.title == "Cancel",
          "mid-download with en-US selected: row shown \(rowShown()), language popup "
            + "enabled \(sheet.languagePopup.isEnabled), engine popup enabled "
            + "\(sheet.enginePopup.isEnabled), label “\(label)”")

    sheet.downloadFinished(.success(()))
    let selected = sheet.languagePopup.selectedItem?.representedObject as? String ?? "<nil>"
    check("P5 finished",
          sheet.languagePopup.isEnabled && sheet.enginePopup.isEnabled && selected == "fr-FR"
            && sheet.downloading == nil,
          "after success: popups enabled \(sheet.languagePopup.isEnabled)/"
            + "\(sheet.enginePopup.isEnabled), selected \(selected), downloading "
            + "\(sheet.downloading?.identifier ?? "nil")")
}
sheetRow()

// ---- P8: a stalled gate holder does not wedge an analysis ------------------

if english == nil {
    skip("P8 gate stalled", "en-US is not installed on this host")
} else {
    let entered = DispatchSemaphore(value: 0)
    let stall = Task.detached {
        await SpeechEngine.gate.run {
            entered.signal()
            try? await Task.sleep(for: .seconds(90))
        }
    }
    // The stall cancelled, then awaited: true when it left the gate within 5 s.
    func drain() -> Bool {
        stall.cancel()
        let drained = DispatchSemaphore(value: 0)
        Task.detached {
            _ = await stall.value
            drained.signal()
        }
        return drained.wait(timeout: .now() + 5) == .success
    }
    if entered.wait(timeout: .now() + 5) != .success {
        let drained = drain()
        check("P8 gate stalled", false, "the stall never entered the gate within 5 s; "
                + "cancelled, it drained within 5 s: \(drained)")
    } else {
        let began = Date()
        let runs = offMain(60) {
            try? SpeechEngine.transcribe(
                file: pangram, locale: Locale(identifier: "en-US"), seconds: pangramSeconds,
                name: "pangram-stalled", cancel: Transcriber.CancelToken(), progress: { _ in })
        } ?? nil
        let wall = Date().timeIntervalSince(began)
        let tokens = runs?.map { $0.text } ?? []
        let drained = drain()
        check("P8 gate stalled", runs != nil && matched(tokens) >= 20 && wall < 30 && drained,
              "with the gate held for 90 s: \(runs == nil ? "no answer" : "\(tokens.count) runs"), "
                + "\(matched(tokens)) pangram words, in \(String(format: "%.2f", wall)) s; "
                + "the stall, cancelled, drained within 5 s: \(drained)")
    }
}

print("\n\(passed)/\(passed + failed) probe rows passed, \(skipped) skipped")
exit(failed == 0 ? 0 : 1)
