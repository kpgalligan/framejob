import Foundation

/// A measurement the Measuring Sound sheet runs and an off-main tool waits
/// on (spec §11 AU-65, AU-128): `LoudnessMeasureRun` and `AudioMatchRun`.
/// `start` answers once on main, nil after `cancel`; `cancel` is any
/// thread; `finish` releases every render key's wants, once the answer is
/// committed or dropped. `needsRender` false means `start` answers before it
/// returns.
protocol AudioMeasureRunning: AnyObject {
    associatedtype Outcome
    var needsRender: Bool { get }
    var progress: ((Int, Int) -> Void)? { get set }
    func start(_ completion: @escaping (Outcome?) -> Void)
    func cancel()
    func finish()
}

/// One run's outcome held between its answer and its hand-back (the sheet,
/// `AgentServer.awaitMeasurement`): a generic function cannot nest a type.
final class AudioMeasureOutcomeBox<Outcome> {
    var outcome: Outcome?
}

/// One press's processed measurement (spec §11 AU-64 (b), (e)): clip by
/// clip, R0 through the clip's chain, the solve, and the limiter's verify
/// renders. Loudness Normalize and Enhance Voice both build one, through
/// `AudioMeasureDoor` and their tools, so the button, the menu and the tool
/// solve alike.
///
/// Everything but the render is on main: the trial handles are made here
/// (from the project the press read, scoped to its nest), and each render's
/// answer comes back on main before the next is asked for. A job with no
/// chain is a clip the loudness cache already reads as it plays; its reading
/// stands and nothing renders. `finish` releases every render key's wants
/// (kept between renders so the verify renders find the same files), and is
/// owed once per run, after the commit or the cancel.
final class LoudnessMeasureRun: AudioMeasureRunning {
    /// One clip: its reading (the cache's, with the limiter the solve uses),
    /// and the chain to render it through; nil chain, the reading stands.
    struct Job {
        let reading: AudioNormalize.LoudnessReading
        let chain: AudioPatch?
    }

    /// The readings to plan (a rendered clip's is its processed reading) with
    /// every skip, and each rendered clip's solve.
    struct Outcome {
        let input: AudioNormalize.LoudnessInput
        let solved: [UInt32: AudioNormalize.Solved]
    }

    static let verifyToleranceLU = 0.1
    static let maximumVerifyRenders = 3

    /// Any thread.
    private final class Flag {
        private let lock = NSLock()
        private var set = false
        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return set
        }
        func raise() {
            lock.lock()
            set = true
            lock.unlock()
        }
    }

    private let base: ReelProject
    private let scope: UInt32?
    private let urls: [UInt32: URL]
    private let resolution: ReverseResolution
    private let jobs: [Job]
    private let problems: [AudioNormalize.Problem]
    private let targetLUFS: Double
    private let cancelled = Flag()

    /// Main: the clip being measured (1-based) and how many render.
    var progress: ((Int, Int) -> Void)?

    private var completion: ((Outcome?) -> Void)?
    private var index = 0
    private var measured = 0
    private var readings: [AudioNormalize.LoudnessReading] = []
    private var skipped: [AudioNormalize.Problem] = []
    private var solved: [UInt32: AudioNormalize.Solved] = [:]
    private var keys: [Int] = []
    private var finished = false

    /// Main. Captures the document's project, scope, media and reverse
    /// resolution: every trial is made from what the press read.
    convenience init(
        document: ProjectDocument, jobs: [Job], problems: [AudioNormalize.Problem],
        targetLUFS: Double
    ) {
        assert(Thread.isMainThread)
        self.init(
            base: document.project, scope: document.scope, urls: document.mediaURLs(),
            resolution: ReverseSource.shared.resolution(for: document.recipeKey), jobs: jobs,
            problems: problems, targetLUFS: targetLUFS)
    }

    /// Main. From pieces a caller already captured from the press's
    /// document (`AudioMatchRun`'s inner run).
    init(
        base: ReelProject, scope: UInt32?, urls: [UInt32: URL], resolution: ReverseResolution,
        jobs: [Job], problems: [AudioNormalize.Problem], targetLUFS: Double
    ) {
        assert(Thread.isMainThread)
        self.base = base
        self.scope = scope
        self.urls = urls
        self.resolution = resolution
        self.jobs = jobs
        self.problems = problems
        self.targetLUFS = targetLUFS.isFinite ? targetLUFS : AudioNormalize.defaultTargetLUFS
    }

    deinit {
        if !finished { keys.forEach { RampAudioRenders.shared.release(owner: $0) } }
    }

    /// Whether any clip renders; with none, the outcome is the input as read.
    var needsRender: Bool { jobs.contains { $0.chain != nil } }

    private var renderCount: Int { jobs.filter { $0.chain != nil }.count }

    /// Main. `completion` once, on main: the outcome, or nil after `cancel`.
    func start(_ completion: @escaping (Outcome?) -> Void) {
        assert(Thread.isMainThread)
        self.completion = completion
        next()
    }

    /// Any thread: the render in flight stops at its next check, and the
    /// run answers nil.
    func cancel() {
        cancelled.raise()
    }

    /// Main. Releases every render key's wants; idempotent.
    func finish() {
        assert(Thread.isMainThread)
        guard !finished else { return }
        finished = true
        keys.forEach { RampAudioRenders.shared.release(owner: $0) }
        keys.removeAll()
    }

    // MARK: - The steps

    private func next() {
        guard !cancelled.isSet else { return answer(nil) }
        while index < jobs.count, jobs[index].chain == nil {
            readings.append(jobs[index].reading)
            index += 1
        }
        guard index < jobs.count, let chain = jobs[index].chain else {
            return answer(
                Outcome(
                    input: AudioNormalize.LoudnessInput(
                        readings: readings, problems: problems + skipped),
                    solved: solved))
        }
        let job = jobs[index]
        measured += 1
        progress?(measured, renderCount)
        // R0 pre-fader: no limiter, and volume 1, so no fader either.
        var first = chain
        first.limiter = .some(nil)
        first.volume = 1
        guard let trial = trial(job.reading.clip, first) else {
            skip(job, "its processing could not be measured: its settings were refused.")
            return
        }
        let key = ProcessedLoudness.key(clip: job.reading.clip, project: trial)
        render(trial, job.reading.clip) { [weak self] rendered in
            guard let self else { return }
            guard case .steps(let steps, let peaks) = rendered else { return self.settle(job, rendered) }
            if let key { ProcessedLoudness.Memo.shared.store(key, steps: steps, peaks: peaks) }
            self.solve(job, chain: chain, steps: steps, peaks: peaks)
        }
    }

    /// AU-64 (e): R0's reading through AU-24's plan; with a limiter, the
    /// verify renders.
    private func solve(_ job: Job, chain: AudioPatch, steps: [Double], peaks: [Double]) {
        let lufs = StepLoudness.integrated(steps) ?? job.reading.lufs
        let peak = max(peaks.max() ?? 0, .leastNormalMagnitude)
        let processed = AudioNormalize.LoudnessReading(
            clip: job.reading.clip, media: job.reading.media, lufs: lufs, truePeak: peak,
            steps: steps, stepPeaks: peaks, limiter: job.reading.limiter,
            materialLUFS: job.reading.lufs, currentVolume: job.reading.currentVolume)
        let planned = AudioNormalize.plan(
            AudioNormalize.LoudnessInput(readings: [processed], problems: []),
            targetLUFS: targetLUFS)
        guard let row = planned.normalized.first else {
            return skip(job, "its processing could not be measured: no volume could be solved.")
        }
        guard let limiter = row.limiter else {
            readings.append(processed)
            solved[job.reading.clip] = AudioNormalize.Solved(
                volume: row.volume, limiter: nil, resultLUFS: row.resultLUFS,
                resultTruePeakDBTP: row.resultTruePeakDBTP, limit: row.limit, renders: 1)
            return advance()
        }
        verify(job, processed, chain: chain, volume: row.volume, limiter: limiter, verifies: 0)
    }

    /// One verify render of the chain with `{volume, limiter}` (the stage
    /// told the volume, AU-22), read through the fader at that volume, so R
    /// is its loudness as it stands; again, nearer, while it misses the
    /// target by more than the tolerance, the volume can still move toward it
    /// (not at the ceiling and short) and fewer than `maximumVerifyRenders`
    /// have run.
    private func verify(
        _ job: Job, _ processed: AudioNormalize.LoudnessReading, chain: AudioPatch,
        volume: Double, limiter: LimiterProps, verifies: Int
    ) {
        guard !cancelled.isSet else { return answer(nil) }
        var patch = chain
        patch.volume = volume
        patch.limiter = .some(limiter)
        guard let trial = trial(job.reading.clip, patch) else {
            return skip(job, "its processing could not be measured: its settings were refused.")
        }
        render(trial, job.reading.clip) { [weak self] rendered in
            guard let self else { return }
            // Read through the clip's fader at `volume` (`ProcessedLoudness.render`).
            guard case .steps(let steps, let peaks) = rendered,
                let result = StepLoudness.integrated(steps)
            else { return self.settle(job, rendered) }
            let peak = peaks.max() ?? 0
            let count = verifies + 1
            let target = self.targetLUFS
            let capped = volume >= AudioNormalize.maxGain && result < target
            if abs(result - target) > Self.verifyToleranceLU, !capped,
                count < Self.maximumVerifyRenders
            {
                let nearer = min(volume * pow(10, (target - result) / 20), AudioNormalize.maxGain)
                return self.verify(
                    job, processed, chain: chain, volume: nearer, limiter: limiter,
                    verifies: count)
            }
            self.readings.append(processed)
            self.solved[job.reading.clip] = AudioNormalize.Solved(
                volume: volume, limiter: limiter, resultLUFS: result,
                resultTruePeakDBTP: peak > 0 ? 20 * log10(peak) : -.infinity,
                limit: volume >= AudioNormalize.maxGain
                    && result < target - Self.verifyToleranceLU ? .maxGain : nil,
                renders: 1 + count)
            self.advance()
        }
    }

    /// A render that did not give steps: cancelled ends the run; a failure
    /// or a skip skips the clip by name (AU-64 (d)).
    private func settle(_ job: Job, _ rendered: ProcessedLoudness.Rendered) {
        switch rendered {
        case .cancelled: answer(nil)
        case .failed(let message):
            skip(job, "its processing could not be measured: \(message)")
        case .skipped(let reason): skip(job, reason)
        case .steps: skip(job, "is under −70 LUFS after its processing.")
        }
    }

    private func skip(_ job: Job, _ reason: String) {
        skipped.append(AudioNormalize.Problem(clip: job.reading.clip, reason: reason))
        advance()
    }

    private func advance() {
        index += 1
        next()
    }

    private func answer(_ outcome: Outcome?) {
        guard let completion else { return }
        self.completion = nil
        completion(cancelled.isSet ? nil : outcome)
    }

    // MARK: - The trial and the render

    private func trial(_ clip: UInt32, _ patch: AudioPatch) -> ReelProject? {
        Self.trial(base: base, scope: scope, clip: clip, patch: patch)
    }

    /// AU-64 (b): the press's project with one `set_audio` of `patch` on
    /// `clip`, scoped to the nest it read in; nil when the core refuses it.
    /// Match Audio's target trials are made here too (AU-124).
    static func trial(base: ReelProject, scope: UInt32?, clip: UInt32, patch: AudioPatch)
        -> ReelProject?
    {
        let op = ReelOp.setAudio(clips: [clip], patch: patch).scoped(scope)
        let handle: ReelProject
        switch try? base.applying(op) {
        case .applied(let updated)?: handle = updated
        case .identity?: handle = base
        default: return nil
        }
        guard let scope else { return handle }
        return handle.scoped(scope)
    }

    /// `ProcessedLoudness.render` on its queue; `then` on main with the
    /// answer, the key kept for `finish` (released at once when the run has
    /// already finished).
    private func render(
        _ trial: ReelProject, _ clip: UInt32,
        then: @escaping (ProcessedLoudness.Rendered) -> Void
    ) {
        let urls = self.urls
        let resolution = self.resolution
        let flag = cancelled
        ProcessedLoudness.queue.async { [weak self] in
            let (rendered, key) = ProcessedLoudness.render(
                trial, clip: clip, urls: urls, resolution: resolution,
                cancelled: { flag.isSet })
            DispatchQueue.main.async {
                guard let self, !self.finished else {
                    RampAudioRenders.shared.release(owner: key)
                    return
                }
                self.keys.append(key)
                then(rendered)
            }
        }
    }
}
