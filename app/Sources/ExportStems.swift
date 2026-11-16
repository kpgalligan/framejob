import AVFoundation

/// An audio export's stems (spec §11 AU-108): the mix, then one file per stem
/// beside it, in one job. `Exporter.pipeline` wraps the mix's `ExportWriter`
/// in this when the settings carry `stems`, and it is otherwise the one
/// pipeline it was.
///
/// **Each stem is its own write** (spec §11 #378, CX-15 (2)): a fresh build of
/// the same plan on the export's key — fresh taps, for `ExporterLoudness`'s
/// reason, and the ramp, isolation and voice renders the key holds — read
/// through only its own composition tracks (`BuiltComposition.selectingAudio`)
/// into an `ExportWriter` of its own, whose master neither gains nor limits
/// (`ExportAudioMaster(limits: false)`): a stem is pre-master, so the stems
/// sum to the mix within rounding wherever the master neither gains nor
/// limits. The builds run on this pipeline's one serial queue; each writer is
/// made and started on the main thread, and the job's completion, the last
/// stem's, precedes `Exporter.finish`, which releases the key.
///
/// **Every file is written aside** (spec §11 #531): the mix at the hidden
/// sibling `Exporter` gave it (`mixWriting`), each stem at its own
/// (`ExportAside.temporary`). When every write has succeeded, each stem is
/// renamed over its path in order, and then `Exporter.finish` renames the mix.
/// **Nothing is left by a failure or a cancel**: every sibling that finished is
/// removed here, the part-written one by its writer, and every path keeps the
/// file it had.
///
/// **The names** are the core's (`export_stems.rs`); a stem's file is
/// `<mix name> - <stem name>.<mix extension>` beside the mix, replacing a file
/// there without asking — except one of the project's media, which refuses
/// the job before any stem file is touched (`collision`, `SourceCollision`).
final class ExportStemsPipeline: ExportPipeline, ExportAudioNormalizing {

    /// A stem's path names media the project uses (spec §11 AU-108 (d)).
    struct SourceCollision: LocalizedError {
        let url: URL
        var errorDescription: String? {
            "The stem “\(url.lastPathComponent)” would replace media this project uses; "
                + "export under another name."
        }
    }

    private let mix: ExportWriter
    private let stems: [ExportStem]
    private let settings: ExportSettings
    private let mixURL: URL
    /// The mix's hidden sibling, which `Exporter.finish` renames over `mixURL`.
    private let mixWriting: URL
    private let rebuild: () throws -> BuiltComposition
    /// The stems' builds, one at a time.
    private let queue = DispatchQueue(
        label: "com.kgalligan.framejob.export.stems", qos: .userInitiated)

    /// Guards everything `progress` and `cancel` read off the main thread.
    private let lock = NSLock()
    /// The write running now (the mix first), nil between two.
    private var current: ExportWriter?
    /// Writes finished, the mix included.
    private var finishedCount = 0
    private var cancelRequested = false
    /// Siblings this job finished, removed if it does not end well. Main thread.
    private var written: [URL] = []
    /// Each finished stem's sibling and its path, renamed in order by
    /// `complete` once every write has succeeded. Main thread.
    private var stemFiles: [(writing: URL, path: URL)] = []
    /// Called once, on the main thread, and then dropped.
    private var completion: ((Result<URL, any Error>) -> Void)?

    init(
        mix: ExportWriter, stems: [ExportStem], settings: ExportSettings, mixURL: URL,
        mixWriting: URL, sources: [URL], rebuild: @escaping () throws -> BuiltComposition
    ) throws {
        if let clash = Self.collision(stems: stems, mix: mixURL, sources: sources) {
            throw SourceCollision(url: clash)
        }
        self.mix = mix
        self.stems = stems
        self.settings = settings
        self.mixURL = mixURL
        self.mixWriting = mixWriting
        self.rebuild = rebuild
        current = mix
    }

    // MARK: - Names

    /// `<mix name without extension> - <stem name>.<mix extension>`, beside
    /// the mix.
    static func url(for stem: ExportStem, mix: URL) -> URL {
        let base = mix.deletingPathExtension().lastPathComponent
        let ext = mix.pathExtension
        let file = ext.isEmpty ? "\(base) - \(stem.name)" : "\(base) - \(stem.name).\(ext)"
        return mix.deletingLastPathComponent().appendingPathComponent(file)
    }

    /// The success line's tail: "", " and 1 stem" or " and N stems".
    static func summary(_ settings: ExportSettings) -> String {
        switch settings.stems.count {
        case 0: return ""
        case 1: return " and 1 stem"
        case let count: return " and \(count) stems"
        }
    }

    /// The plan the stems are rebuilt from (#393): nil when no stems are
    /// asked for. Stems asked for with no plan fail the job (`.noPlan`),
    /// asked before the mix's writer is made, rather than writing only the
    /// mix while the answer lists stems no one wrote.
    static func plan(for settings: ExportSettings, from plan: CompositionPlan?) throws
        -> CompositionPlan?
    {
        guard !settings.stems.isEmpty else { return nil }
        guard let plan else { throw Exporter.ExportError.noPlan }
        return plan
    }

    /// The first stem URL that is one of `sources` — symlinks resolved,
    /// standardized, compared case-insensitively — or nil.
    static func collision(stems: [ExportStem], mix: URL, sources: [URL]) -> URL? {
        let taken = Set(sources.map(canonical))
        return stems.map { url(for: $0, mix: mix) }.first { taken.contains(canonical($0)) }
    }

    private static func canonical(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
    }

    // MARK: - The pipeline

    /// The mix's share first, then each stem's: `(finished + current) / (1 + N)`.
    var progress: Double {
        lock.lock()
        defer { lock.unlock() }
        let running = current?.progress ?? 0
        return (Double(finishedCount) + running) / Double(1 + stems.count)
    }

    /// The loudness gain is the mix's alone (spec §11 AU-108 (e)).
    func normalizeAudio(byLinearGain gain: Float) {
        mix.normalizeAudio(byLinearGain: gain)
    }

    func start(completion: @escaping (Result<URL, any Error>) -> Void) {
        self.completion = completion
        mix.start { [weak self] result in self?.ended(result, at: self?.mixWriting, next: 0) }
    }

    /// Sets the flag and stops the write running now; a stem not yet started
    /// sees the flag before it starts.
    func cancel() {
        lock.lock()
        cancelRequested = true
        let running = current
        lock.unlock()
        running?.cancel()
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelRequested
    }

    /// One write ended (main thread): on success the file is kept and stem
    /// `next` follows; otherwise the job ends with nothing left behind.
    private func ended(_ result: Result<URL, any Error>, at url: URL?, next: Int) {
        lock.lock()
        current = nil
        lock.unlock()
        switch result {
        case .failure(let error):
            if let url { written.append(url) }
            fail(error)
        case .success:
            if let url { written.append(url) }
            lock.lock()
            finishedCount += 1
            lock.unlock()
            write(next)
        }
    }

    /// Builds stem `index` on the queue, then writes it on the main thread.
    private func write(_ index: Int) {
        guard !isCancelled else { return fail(Exporter.ExportError.cancelled) }
        guard index < stems.count else { return swapStems() }
        let stem = stems[index]
        queue.async { [weak self] in
            guard let self else { return }
            let built = Result { try self.rebuild().selectingAudio(of: Set(stem.tracks)) }
            DispatchQueue.main.async { self.writeBuilt(built, stem: stem, index: index) }
        }
    }

    private func writeBuilt(_ built: Result<BuiltComposition, any Error>, stem: ExportStem, index: Int) {
        guard !isCancelled else { return fail(Exporter.ExportError.cancelled) }
        let path = Self.url(for: stem, mix: mixURL)
        // The save panel asked about the mix; a stem's file is replaced, by
        // `swapStems` once every write has succeeded.
        let url = ExportAside.temporary(for: path)
        let writer: ExportWriter
        do {
            let composition = try built.get()
            writer = try ExportWriter(built: composition, settings: settings, chapters: [], to: url)
        } catch {
            return fail(error)
        }
        stemFiles.append((writing: url, path: path))
        lock.lock()
        current = writer
        let cancelled = cancelRequested
        lock.unlock()
        if cancelled { writer.cancel() }
        writer.start { [weak self] result in self?.ended(result, at: url, next: index + 1) }
    }

    /// Every write succeeded: each stem's sibling renamed over its path in
    /// order, then the job's success (the mix is `Exporter.finish`'s). A rename
    /// that fails removes its sibling and those not yet renamed, and fails the
    /// job with its sentence; the stems already renamed stay.
    private func swapStems() {
        for (index, file) in stemFiles.enumerated() {
            do {
                try ExportAside.swap(file.writing, into: file.path)
            } catch {
                for rest in stemFiles[index...] { ExportAside.discard(rest.writing) }
                stemFiles = []
                written = []
                return complete(.failure(error))
            }
        }
        stemFiles = []
        written = []
        complete(.success(mixURL))
    }

    /// Removes every sibling this job wrote, then reports `error`.
    private func fail(_ error: any Error) {
        for url in written { ExportAside.discard(url) }
        written = []
        stemFiles = []
        complete(.failure(error))
    }

    private func complete(_ result: Result<URL, any Error>) {
        let handler = completion
        completion = nil
        handler?(result)
    }
}
