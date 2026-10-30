import AVFoundation

/// Audio while scrubbing, the half with a queue and an engine (road map
/// "audio" AP13, spec §11 AU-130…AU-136). `ScrubGrains.swift` is the pure
/// half: what a grain is, how it is read, when one is asked for.
///
/// **Not the player** (AU-130). A grain is read from a composition built
/// only for scrubbing — the player's plan, media and recipe slot, with taps
/// of its own, for the reason `ExporterLoudness.swift`'s header gives for its
/// own build — one `AVAssetReader` at a time on this object's serial queue,
/// and played through an `AVAudioEngine` that only scrubbing uses. Bursts of
/// rate on the `AVPlayer` would move and report the playhead, fight its
/// one-seek-in-flight rule and wait behind the picture.

/// What a scrub build is made from: the player's own inputs.
struct ScrubSource {
    let plan: CompositionPlan
    let planJSON: String
    let urls: [UInt32: URL]
    let recipeKey: Int
}

/// Where grains sound. Every call is on `ScrubAudio`'s queue.
protocol ScrubGrainSink: AnyObject {
    /// Ready the output; false means there is none and the grain is dropped.
    func start() -> Bool
    /// Queue one windowed grain after the ones before it.
    func play(left: [Float], right: [Float])
    /// Stop the output and drop whatever is queued.
    func stop()
}

/// The app's sink: an `AVAudioPlayerNode` on an `AVAudioEngine` of its own,
/// made lazily in the 48 kHz stereo float standard format. Creates no engine
/// until `start()`, so every app source compiles into the harness and the
/// probes at no cost. `inputNode` is never touched: touching it asks for the
/// microphone (AU-132).
final class ScrubEngineSink: ScrubGrainSink {
    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var observer: NSObjectProtocol?
    private let format = AVAudioFormat(
        standardFormatWithSampleRate: Double(ScrubGrains.sampleRate), channels: 2)
    /// Set from whatever thread posts `AVAudioEngineConfigurationChange`:
    /// the next `start()` then builds a fresh engine.
    private let lock = NSLock()
    private var configurationChanged = false

    init() {}

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ScrubEngineSink does not support NSCoder")
    }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    func start() -> Bool {
        lock.lock()
        let changed = configurationChanged
        configurationChanged = false
        lock.unlock()
        if changed { tearDown() }
        if engine == nil { makeEngine() }
        guard let engine = engine, let node = node else { return false }
        if !engine.isRunning {
            do { try engine.start() } catch { return false }
        }
        if !node.isPlaying { node.play() }
        return true
    }

    func play(left: [Float], right: [Float]) {
        let count = min(left.count, right.count)
        guard count > 0, let node = node, let format = format,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
            let channels = buffer.floatChannelData
        else { return }
        buffer.frameLength = AVAudioFrameCount(count)
        left.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: count) }
        right.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: count) }
        node.scheduleBuffer(buffer, completionHandler: nil)
    }

    func stop() {
        node?.stop()
        engine?.stop()
    }

    private func makeEngine() {
        guard let format = format else { return }
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            self.lock.lock()
            self.configurationChanged = true
            self.lock.unlock()
        }
        self.engine = engine
        self.node = node
    }

    private func tearDown() {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        node?.stop()
        engine?.stop()
        node = nil
        engine = nil
    }
}

/// One editor window's scrub audio. Its API is the main thread's; the
/// builds, the reads and the sink run on `queue`, strictly one at a time.
///
/// **Two kinds of queue item, and only one is ever dropped.** A REBUILD is
/// posted whenever a move sees a player composition it has not built from,
/// grain or no grain, and always runs, so the scrub build can never stay
/// behind the player (AU-130). A GRAIN request carries the generation it was
/// asked in; `end()` and `invalidate()` bump it, so requests not yet read
/// when the mouse comes up are dropped, before the read and again before the
/// play (AU-132). The grain already handed to the sink plays out its fade.
final class ScrubAudio {
    /// How long after a scrub ends the engine keeps running (AU-132).
    static let idleStop: TimeInterval = 1.0

    /// Scrub builds made so far. Probe-readable after `drain()`.
    var builds: Int {
        lock.lock()
        defer { lock.unlock() }
        return buildCount
    }

    private let sink: ScrubGrainSink
    /// The seam (app/CLAUDE.md's `DispatchQueue` list): every build, read and
    /// sink call.
    private let queue = DispatchQueue(
        label: "com.kgalligan.framejob.scrub-audio", qos: .userInteractive)
    /// Guards `generation` and `buildCount`, which both sides read.
    private let lock = NSLock()
    private var generation = 0
    private var buildCount = 0

    // Main thread.
    private var scheduler = ScrubGrainScheduler()
    /// The player composition the last rebuild was posted for. Weak, so a
    /// released one reads nil and the next differs.
    private weak var builtFor: AVComposition?
    private var idleTimer: Timer?

    // The queue's.
    private var scrubBuild: BuiltComposition?

    init(sink: ScrubGrainSink = ScrubEngineSink()) {
        self.sink = sink
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ScrubAudio does not support NSCoder")
    }

    /// The press and every drag position (AU-132). `playhead` is already
    /// frame-snapped; `player` is the preview's current composition, and
    /// `source` is asked for only when that is not the one last built from.
    /// No player composition, no grain.
    func move(
        to playhead: Ticks, duration: Ticks, player: AVComposition?,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime, source: () -> ScrubSource?
    ) {
        idleTimer?.invalidate()
        idleTimer = nil
        guard let player = player else { return }
        if player !== builtFor, let source = source() {
            queue.async { [weak self] in self?.rebuild(source) }
            builtFor = player
        }
        guard let grain = scheduler.move(to: playhead, duration: duration, now: now) else { return }
        let asked = currentGeneration()
        queue.async { [weak self] in self?.render(grain, generation: asked) }
    }

    /// Mouse-up: nothing more is asked for, what is not yet read is dropped,
    /// and the engine stops `idleStop` later unless a move comes first.
    func end() {
        scheduler.end()
        bumpGeneration()
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleStop, repeats: false) {
            [weak self] _ in self?.idle()
        }
    }

    /// The window is going: nothing more plays, and the output stops. The
    /// sink is captured strongly, so the stop runs even if this object is
    /// gone by the time the queue reaches it.
    func invalidate() {
        bumpGeneration()
        idleTimer?.invalidate()
        idleTimer = nil
        let sink = self.sink
        queue.async { sink.stop() }
    }

    /// The probe's seam: returns once everything posted so far has run.
    func drain() {
        queue.sync {}
    }

    // MARK: - Main thread

    private func idle() {
        idleTimer = nil
        let sink = self.sink
        queue.async { sink.stop() }
    }

    private func currentGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    private func bumpGeneration() {
        lock.lock()
        generation += 1
        lock.unlock()
    }

    // MARK: - The queue

    private func isStale(_ asked: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return asked != generation
    }

    private func rebuild(_ source: ScrubSource) {
        scrubBuild = try? CompositionBuilder.build(
            plan: source.plan, planJSON: source.planJSON, urls: source.urls,
            recipeKey: source.recipeKey, metering: false)
        lock.lock()
        buildCount += 1
        lock.unlock()
    }

    private func render(_ grain: ScrubGrain, generation asked: Int) {
        guard !isStale(asked), sink.start() else { return }
        guard let built = scrubBuild,
            var samples = ScrubGrains.read(built, start: grain.start, frames: grain.frames)
        else { return }
        guard !isStale(asked) else { return }
        ScrubGrains.window(&samples.left, &samples.right)
        sink.play(left: samples.left, right: samples.right)
    }
}
