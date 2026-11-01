import Foundation

/// One Match Audio press's measurement (road map "audio" AP12, spec §11
/// AU-122…AU-124): the reference rendered once as it plays, each target's
/// trial rendered for its speech spectrum and fitted when EQ is matched,
/// then an inner `LoudnessMeasureRun` to the reference's loudness when
/// Loudness is. `AudioMeasureDoor.pressMatch` runs it under the Measuring
/// Sound sheet, and `match_audio` waits on it off main.
///
/// `LoudnessMeasureRun`'s posture: the trials are made on main from the
/// project the press read, each render runs on `ProcessedLoudness.queue`
/// and answers on main before the next is asked for, and every render key's
/// wants are kept until `finish` (the inner run's too). `progress` counts
/// every render: the reference, each target's spectrum, then the inner run's
/// clips.
final class AudioMatchRun: AudioMeasureRunning {
    struct Outcome {
        /// T, the reference's integrated loudness as it plays.
        let referenceLUFS: Double
        let fits: [UInt32: AudioMatchFit.Fit]
        /// The inner run's outcome; nil with Loudness off.
        let loudness: LoudnessMeasureRun.Outcome?
        /// Targets the spectra skipped, by name.
        let problems: [AudioNormalize.Problem]
        /// The reference could not be matched to (its render or its spectrum):
        /// the sentence; every other field is then empty.
        let refusal: AudioMatch.Refusal?
    }

    /// Any thread.
    private final class State {
        private let lock = NSLock()
        private var raised = false
        private var innerRun: LoudnessMeasureRun?
        var cancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return raised
        }
        /// Raises the flag; answers the inner run to cancel, if one has started.
        func cancel() -> LoudnessMeasureRun? {
            lock.lock()
            defer { lock.unlock() }
            raised = true
            return innerRun
        }
        func set(_ run: LoudnessMeasureRun) {
            lock.lock()
            innerRun = run
            lock.unlock()
        }
        var inner: LoudnessMeasureRun? {
            lock.lock()
            defer { lock.unlock() }
            return innerRun
        }
    }

    private let input: AudioMatch.Input
    private let base: ReelProject
    private let scope: UInt32?
    private let urls: [UInt32: URL]
    private let resolution: ReverseResolution
    /// Loudness Normalize's jobs for the targets as they are, with EQ off.
    private let plainJobs: [LoudnessMeasureRun.Job]
    private let state = State()

    var progress: ((Int, Int) -> Void)?

    private var completion: ((Outcome?) -> Void)?
    private var referenceLUFS = 0.0
    private var referenceLevels: [Double]?
    private var fits: [UInt32: AudioMatchFit.Fit] = [:]
    private var problems: [AudioNormalize.Problem] = []
    private var index = 0
    private var rendered = 0
    private var keys: [Int] = []
    private var finished = false

    /// Main. Captures the document's project, scope, media and reverse
    /// resolution: every render is made from what the press read.
    init(document: ProjectDocument, input: AudioMatch.Input) {
        assert(Thread.isMainThread)
        self.input = input
        base = document.project
        scope = document.scope
        urls = document.mediaURLs()
        resolution = ReverseSource.shared.resolution(for: document.recipeKey)
        plainJobs = input.eq
            ? []
            : AudioMeasureDoor.normalizeJobs(
                AudioNormalize.LoudnessInput(readings: input.targets.map(\.loudness), problems: []),
                in: document)
    }

    deinit {
        if !finished { keys.forEach { RampAudioRenders.shared.release(owner: $0) } }
    }

    /// The reference always renders (AU-122).
    var needsRender: Bool { true }

    /// The renders known before the inner run: the reference and, with EQ,
    /// each target's spectrum; the inner run's clips are added as it reports.
    private var plannedRenders: Int { 1 + (input.eq ? input.targets.count : 0) }

    /// Main. `completion` once, on main: the outcome, or nil after `cancel`.
    func start(_ completion: @escaping (Outcome?) -> Void) {
        assert(Thread.isMainThread)
        self.completion = completion
        renderReference()
    }

    /// Any thread: the render in flight stops at its next check (the inner
    /// run's too), and the run answers nil.
    func cancel() {
        state.cancel()?.cancel()
    }

    /// Main. Releases every render key's wants, the inner run's too; idempotent.
    func finish() {
        assert(Thread.isMainThread)
        guard !finished else { return }
        finished = true
        keys.forEach { RampAudioRenders.shared.release(owner: $0) }
        keys.removeAll()
        state.inner?.finish()
    }

    /// AU-122: the reference renders from the press's own project, no trial
    /// edit — its chain, its limiter and its base volume as the fader; nil
    /// when the reference is not in it.
    static func referenceProject(base: ReelProject, scope: UInt32?, clip: UInt32)
        -> ReelProject?
    {
        let project: ReelProject?
        if let scope { project = base.scoped(scope) } else { project = base }
        guard let project, project.snapshot.clip(clip) != nil else { return nil }
        return project
    }

    // MARK: - The steps

    private func renderReference() {
        guard !state.cancelled else { return answer(nil) }
        let reference = input.reference
        rendered += 1
        progress?(rendered, plannedRenders)
        guard
            let project = Self.referenceProject(base: base, scope: scope, clip: reference.clip)
        else {
            return refuse("its sound could not be measured: the project could not be read.")
        }
        let meter = input.eq ? SpeechSpectrumMeter(speech: reference.speech ?? []) : nil
        render(project, reference.clip, meter) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .cancelled: return self.answer(nil)
            case .failed(let message):
                return self.refuse("its sound could not be measured: \(message)")
            case .skipped(let reason): return self.refuse(reason)
            case .steps(let steps, _):
                guard let lufs = StepLoudness.integrated(steps) else {
                    return self.refuse("is under −70 LUFS as it plays.")
                }
                self.referenceLUFS = lufs
            }
            if let meter {
                guard let levels = meter.finish() else {
                    return self.refuse(
                        "has under 1 s of speech in the part of it that plays, too little to "
                            + "match a tone to.")
                }
                guard AudioMatchFit.contentBands(levels) >= AudioMatchFit.minimumBands else {
                    return self.refuse(
                        "has under \(AudioMatchFit.minimumBands) third-octave bands within "
                            + "\(Int(AudioMatchFit.contentRangeDB)) dB of its loudest, too "
                            + "narrow a sound to match a tone to.")
                }
                self.referenceLevels = levels
            }
            self.nextTarget()
        }
    }

    /// AU-124: each target's trial — its tonal slots off, volume 1, no
    /// limiter — rendered for its speech spectrum, then fitted (AU-125, AU-126).
    private func nextTarget() {
        guard !state.cancelled else { return answer(nil) }
        guard input.eq, index < input.targets.count, let reference = referenceLevels else {
            return measureLoudness()
        }
        let target = input.targets[index]
        rendered += 1
        progress?(rendered, plannedRenders)
        let patch = AudioPatch(
            volume: 1, limiter: .some(nil), eq: .some(AudioMatchFit.trialEQ(target.current.eq)))
        guard
            let trial = LoudnessMeasureRun.trial(
                base: base, scope: scope, clip: target.clip, patch: patch)
        else {
            return skip(target.clip, "its tone could not be measured: its settings were refused.")
        }
        let meter = SpeechSpectrumMeter(speech: target.speech ?? [])
        render(trial, target.clip, meter) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .cancelled: return self.answer(nil)
            case .failed(let message):
                return self.skip(target.clip, "its tone could not be measured: \(message)")
            case .skipped(let reason): return self.skip(target.clip, reason)
            case .steps: break
            }
            guard let levels = meter.finish() else {
                return self.skip(
                    target.clip,
                    "has under 1 s of speech in the part of it that plays, too little to match "
                        + "its tone from.")
            }
            guard let curve = AudioMatchFit.target(reference: reference, target: levels) else {
                return self.skip(
                    target.clip,
                    "shares under \(AudioMatchFit.minimumBands) third-octave bands with the "
                        + "reference within \(Int(AudioMatchFit.contentRangeDB)) dB of their "
                        + "loudest, too few to match its tone.")
            }
            self.fits[target.clip] = AudioMatchFit.fit(curve: curve.curve, weights: curve.weights)
            self.index += 1
            self.nextTarget()
        }
    }

    /// AU-123: Loudness Normalize to T through an inner run, each target's
    /// chain the matched EQ when EQ is on.
    private func measureLoudness() {
        guard !state.cancelled else { return answer(nil) }
        guard input.loudness else { return complete(nil) }
        let jobs: [LoudnessMeasureRun.Job]
        if input.eq {
            jobs = input.targets.compactMap { target in
                guard let fit = fits[target.clip] else { return nil }
                return LoudnessMeasureRun.Job(
                    reading: target.loudness,
                    chain: AudioPatch(eq: .some(AudioMatchFit.applied(fit, to: target.current.eq))))
            }
        } else {
            jobs = plainJobs
        }
        guard !jobs.isEmpty else { return complete(nil) }
        let inner = LoudnessMeasureRun(
            base: base, scope: scope, urls: urls, resolution: resolution, jobs: jobs,
            problems: [], targetLUFS: referenceLUFS)
        state.set(inner)
        // A cancel raised between the check above and `set` missed the inner run.
        guard !state.cancelled else { return answer(nil) }
        let before = rendered
        let renders = jobs.filter { $0.chain != nil }.count
        inner.progress = { [weak self] clip, _ in
            self?.progress?(before + clip, before + renders)
        }
        inner.start { [weak self] outcome in
            guard let self else { return }
            guard let outcome else { return self.answer(nil) }
            self.complete(outcome)
        }
    }

    private func complete(_ loudness: LoudnessMeasureRun.Outcome?) {
        answer(
            Outcome(
                referenceLUFS: referenceLUFS, fits: fits, loudness: loudness, problems: problems,
                refusal: nil))
    }

    private func refuse(_ reason: String) {
        answer(
            Outcome(
                referenceLUFS: 0, fits: [:], loudness: nil, problems: [],
                refusal: .reference("The reference, clip \(input.reference.clip), \(reason)")))
    }

    private func skip(_ clip: UInt32, _ reason: String) {
        problems.append(AudioNormalize.Problem(clip: clip, reason: reason))
        index += 1
        nextTarget()
    }

    private func answer(_ outcome: Outcome?) {
        guard let completion else { return }
        self.completion = nil
        completion(state.cancelled ? nil : outcome)
    }

    /// `ProcessedLoudness.render` on its queue with `meter` fed beside the
    /// steps; `then` on main, the key kept for `finish` (released at once
    /// when the run has already finished).
    private func render(
        _ project: ReelProject, _ clip: UInt32, _ meter: SpeechSpectrumMeter?,
        then: @escaping (ProcessedLoudness.Rendered) -> Void
    ) {
        let urls = self.urls
        let resolution = self.resolution
        let state = self.state
        ProcessedLoudness.queue.async { [weak self] in
            let (rendered, key) = ProcessedLoudness.render(
                project, clip: clip, urls: urls, resolution: resolution, spectrum: meter,
                cancelled: { state.cancelled })
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
