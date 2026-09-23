import AVFoundation
import Foundation
import Speech

/// The on-device speech engine — `SpeechAnalyzer` and `SpeechTranscriber` —
/// behind `Transcriber`, and the ONE file under `app/Sources` that says
/// `async` or `import Speech` for it (spec §11 W-8, road map 8 §5f).
///
/// **Every entry point is synchronous or a main-queue completion.** The
/// framework is `async`-only, so each call here starts a `Task.detached` —
/// never `Task {}`, which would inherit the main actor from a main-thread
/// caller and deadlock on the semaphore that caller then waits on — and the
/// caller waits on a `DispatchSemaphore` the task signals, or is called back
/// on main. `Transcriber`, the sheet and the `transcribe` tool never see
/// `async`, and nothing else in the app gains it.
///
/// **It reads the SAME extracted audio the old engine did**:
/// `Transcriber+Extract.swift`'s 16 kHz mono WAV, opened with
/// `AVAudioFile(forReading:)`. W0 q1 measured this engine over exactly those
/// files: every run one whitespace token with a LEADING space on all but the
/// first (trimmed here), no ceiling at ten minutes, and no TCC grant asked.
///
/// **Reservations are given back.** A reserved locale counts against a cap
/// of 5 (`AssetInventory.maximumReservedLocales`, W0 q3), so every path that
/// constructs a transcriber — `transcribe`, `isInstalled`, `download` —
/// releases on every exit, success or failure, what it may have reserved.
/// The release answering `false` is not an error: there was nothing left to
/// release.
///
/// **The asks are bounded.** `supportedLocales`, `installedLocales` and
/// `isInstalled` wait at most `askBound` seconds and answer an empty list or
/// nil past it, because a caller on the main thread must not be held by a
/// framework that has stopped answering.
enum SpeechEngine {

    /// One recognised token: its text, TRIMMED, and its range in seconds
    /// into the file that was transcribed.
    struct Run: Equatable {
        let text: String
        let start: Double
        let end: Double
    }

    /// What `Transcriber.CancelToken` holds for a running analysis. Cancel
    /// is PUSH, as it was for the old engine's task: `Task.cancel()` on the
    /// analysis and `cancelAndFinishNow()` on the analyzer, which ends the
    /// results sequence the reader is draining. A cancel that arrives before
    /// either exists is remembered and lands the moment it is handed over.
    final class Handle: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private var task: Task<Void, Never>?
        private var analyzer: SpeechAnalyzer?

        func cancel() {
            lock.lock()
            cancelled = true
            let running = task
            let analysing = analyzer
            lock.unlock()
            running?.cancel()
            if let analysing { Task.detached { await analysing.cancelAndFinishNow() } }
        }

        fileprivate func hold(_ task: Task<Void, Never>) {
            lock.lock()
            self.task = task
            let already = cancelled
            lock.unlock()
            if already { task.cancel() }
        }

        fileprivate func hold(_ analyzer: SpeechAnalyzer) {
            lock.lock()
            self.analyzer = analyzer
            let already = cancelled
            lock.unlock()
            if already { Task.detached { await analyzer.cancelAndFinishNow() } }
        }
    }

    /// Seconds any locale or asset question may take before it is answered
    /// as "could not be asked".
    static let askBound: Double = 10

    // MARK: - Transcribing

    /// One file through the engine, waited for.
    ///
    /// Synchronous: it blocks the CALLING thread on a semaphore the detached
    /// analysis signals, so it must never be called on main. Bounded at four
    /// times real time, floored at two minutes, as the old engine was — past
    /// that the analysis is stopped WITHOUT marking the run cancelled
    /// (`stopTask`) and this one file answers `.timedOut`.
    ///
    /// Finalized results only. A run with no `audioTimeRange`, or whose text
    /// trims to nothing, is dropped. `progress` gets each result's end, in
    /// seconds into the file, on the analysis task's own thread.
    static func transcribe(
        file: URL, locale: Locale, seconds: Double, name: String,
        cancel: Transcriber.CancelToken, progress: @escaping (Double) -> Void
    ) throws -> [Run] {
        precondition(!Thread.isMainThread, "SpeechEngine.transcribe blocks; call it off main")
        guard (try? AVAudioFile(forReading: file)) != nil else {
            throw Transcriber.TranscribeError.unreadable(name)
        }
        let sink = Sink(progress: progress)
        let handle = Handle()
        cancel.attach(handle)
        defer { cancel.release() }
        handle.hold(
            Task.detached(priority: .userInitiated) {
                await analyse(file, locale: locale, into: sink, handle: handle)
            })

        // Waited for in slices so a cancel is answered at once, whatever the
        // analysis is doing: the token has already pushed the stop, and the
        // detached task winds down — and releases its locale — on its own.
        let deadline = Date().addingTimeInterval(max(120, seconds * 4))
        while !sink.wait(seconds: 0.1) {
            if cancel.isCancelled { throw Transcriber.TranscribeError.cancelled }
            if Date() >= deadline {
                cancel.stopTask()
                throw Transcriber.TranscribeError.timedOut(name)
            }
        }
        if cancel.isCancelled { throw Transcriber.TranscribeError.cancelled }
        if let failure = sink.failure {
            throw Transcriber.TranscribeError.failed(failure.localizedDescription)
        }
        return sink.runs
    }

    /// The analysis itself: a reader draining `results` while the analyzer
    /// reads the whole file, then a finalize through the last sample — or a
    /// cancel when the file gave it nothing to finalize — then the drain.
    /// The sink is finished BEFORE the release, so the caller is answered
    /// before this task waits its turn at the gate.
    private static func analyse(
        _ file: URL, locale: Locale, into sink: Sink, handle: Handle
    ) async {
        var failure: (any Error)?
        do {
            let audio = try AVAudioFile(forReading: file)
            let transcriber = module(locale)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            handle.hold(analyzer)
            let reader = Task.detached {
                for try await result in transcriber.results { sink.take(result) }
            }
            do {
                if let last = try await analyzer.analyzeSequence(from: audio) {
                    try await analyzer.finalizeAndFinish(through: last)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
            } catch {
                await analyzer.cancelAndFinishNow()
                reader.cancel()
                throw error
            }
            try await reader.value
        } catch {
            failure = error
        }
        sink.finish(failure)
        await release(locale)
    }

    /// What one analysis collected, under a lock because the reader task
    /// writes it and the waiting thread reads it.
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private let progress: (Double) -> Void
        private var collected: [Run] = []
        private var error: (any Error)?
        private var finished = false

        init(progress: @escaping (Double) -> Void) {
            self.progress = progress
        }

        var runs: [Run] {
            lock.lock()
            defer { lock.unlock() }
            return collected
        }

        var failure: (any Error)? {
            lock.lock()
            defer { lock.unlock() }
            return error
        }

        func wait(seconds: Double) -> Bool {
            done.wait(timeout: .now() + seconds) == .success
        }

        func finish(_ failure: (any Error)?) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            error = failure
            lock.unlock()
            done.signal()
        }

        /// One result's runs, appended — every result, not the last one: a
        /// file arrives as many results (172 over ten minutes, W0 q1).
        func take(_ result: SpeechTranscriber.Result) {
            guard result.isFinal else { return }
            var found: [Run] = []
            for run in result.text.runs {
                guard let range = run.audioTimeRange else { continue }
                let text = String(result.text[run.range].characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let start = range.start.seconds
                let end = range.end.seconds
                guard !text.isEmpty, start.isFinite, end.isFinite else { continue }
                found.append(Run(text: text, start: start, end: end))
            }
            lock.lock()
            collected.append(contentsOf: found)
            lock.unlock()
            let reached = result.range.end.seconds
            if reached.isFinite { progress(reached) }
        }
    }

    // MARK: - Locales and models

    /// Whether this Mac can run the engine at all.
    static var isAvailable: Bool { SpeechTranscriber.isAvailable }

    /// Every locale the engine names, model or no model. Empty past
    /// `askBound`.
    static func supportedLocales() -> [Locale] {
        ask { await SpeechTranscriber.supportedLocales } ?? []
    }

    /// The locales whose model is on this Mac. Empty past `askBound`.
    static func installedLocales() -> [Locale] {
        ask { await SpeechTranscriber.installedLocales } ?? []
    }

    /// `AssetInventory.status(forModules:)` for ONE locale — the only
    /// installed test W0 q3 found (a request is non-nil even for an
    /// installed model). nil when the question took longer than `askBound`,
    /// or the locale could not be reserved, which is not the same answer as
    /// "not installed".
    ///
    /// **The locale is RESERVED for the question.** Measured by W2 on this
    /// host: `status` answers `.supported` for an installed model this
    /// process has not reserved, and `.installed` once it has; constructing
    /// a transcriber reserves nothing, and a reservation does not download.
    /// So the ask reserves, reads, and gives back a reservation it made.
    ///
    /// The whole reserve → read → give back runs inside `gate`, as every
    /// release does, so no other path's release can drop the reservation
    /// between the reserve and the read, and `held` is read under it too.
    static func isInstalled(_ locale: Locale) -> Bool? {
        let answer: Bool?? = ask {
            await gate.run {
                let tag = locale.identifier(.bcp47)
                let held = await AssetInventory.reservedLocales.contains {
                    $0.identifier(.bcp47) == tag
                }
                if !held {
                    guard (try? await AssetInventory.reserve(locale: locale)) != nil else {
                        return nil
                    }
                }
                let status = await AssetInventory.status(forModules: [module(locale)])
                if !held { await releaseNow(locale) }
                return status == .installed
            }
        }
        return answer ?? nil
    }

    /// Downloads and installs one locale's model. `progress` is handed the
    /// request's own `Progress` on MAIN before the download starts — zero
    /// units until it does (W0 q3) — and `completion` answers on MAIN. A
    /// locale already installed completes at once with success.
    ///
    /// A person's act, never a tool's (spec §11 W-8, R6-12's argument): the
    /// sheet's Download row is the only caller, and no tool handler calls it.
    /// `completion` lands BEFORE the release, so the caller is answered
    /// before this task waits its turn at the gate.
    static func download(
        _ locale: Locale, progress: @escaping (Progress) -> Void,
        completion: @escaping (Result<Void, any Error>) -> Void
    ) {
        Task.detached(priority: .userInitiated) {
            let outcome: Result<Void, any Error>
            do {
                let request = try await AssetInventory.assetInstallationRequest(
                    supporting: [module(locale)])
                if let request {
                    let tracked = request.progress
                    await MainActor.run { progress(tracked) }
                    try await request.downloadAndInstall()
                }
                outcome = .success(())
            } catch {
                outcome = .failure(error)
            }
            await MainActor.run { completion(outcome) }
            await release(locale)
        }
    }

    // MARK: - The plumbing

    /// The one module shape this app asks for: final text, with times.
    private static func module(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale, transcriptionOptions: [], reportingOptions: [],
            attributeOptions: [.audioTimeRange])
    }

    /// Gives back the reservation constructing a module took — the locale as
    /// it was asked for, and any reserved locale with the same BCP-47 tag,
    /// because the framework may hold `en_US` for an `en-US` that was asked.
    /// Inside `gate`, so it never lands inside `isInstalled`'s question.
    private static func release(_ locale: Locale) async {
        await gate.run { await releaseNow(locale) }
    }

    /// `release`'s walk, for a caller already inside `gate`.
    private static func releaseNow(_ locale: Locale) async {
        let tag = locale.identifier(.bcp47)
        await AssetInventory.release(reservedLocale: locale)
        for reserved in await AssetInventory.reservedLocales
        where reserved.identifier(.bcp47) == tag {
            await AssetInventory.release(reservedLocale: reserved)
        }
    }

    /// The one reservation walk at a time: `isInstalled`'s reserve → status
    /// → release, and every `release`. An actor alone is not enough — it
    /// interleaves at each `await` — so a caller that finds it busy waits
    /// its turn, first come first served. Never call `release` or `gate.run`
    /// from inside `gate.run` — `releaseNow` is the in-gate form. Internal
    /// so `speech_engine_probe.swift`'s P8 can hold it; nothing in the app
    /// outside this file reads it.
    static let gate = Gate()

    actor Gate {
        private var busy = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func run<T: Sendable>(_ body: @Sendable () async -> T) async -> T {
            if busy {
                await withCheckedContinuation { waiting.append($0) }
            } else {
                busy = true
            }
            let answer = await body()
            if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
            return answer
        }
    }

    /// An `async` question, answered synchronously within `askBound` — or
    /// nil. The detached task runs on after an expiry and finishes whatever
    /// it was doing, a release included.
    private static func ask<T>(_ body: @escaping @Sendable () async -> T) -> T? {
        let box = Box<T>()
        Task.detached(priority: .userInitiated) {
            box.put(await body())
        }
        return box.take(within: askBound)
    }

    private final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var value: T?

        func put(_ answer: T) {
            lock.lock()
            value = answer
            lock.unlock()
            done.signal()
        }

        func take(within seconds: Double) -> T? {
            guard done.wait(timeout: .now() + seconds) == .success else { return nil }
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }
}
