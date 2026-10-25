import AVFoundation

/// Writes the timeline to a file (spec §7.8), and renders one frame offline
/// for the agent's verification hook.
///
/// The whole point of the design is that export and playback share exactly
/// one description of the movie: the core's composition plan becomes the same
/// `AVComposition` + `AVVideoComposition` (`CompositionBuilder`), and the same
/// Metal compositor draws every frame from the same frame recipes. An export
/// that disagreed with the preview would be a bug in one of those two, never
/// in a second rendering path — because there is not one.
///
/// M1 was `AVAssetExportSession`: the core resolved a preset into concrete
/// settings, this handed them over, and the sheet polled `progress`. M2's
/// `AVAssetWriter` path (`ExporterWriter.swift`) has **replaced** it, and this
/// file is otherwise unchanged — `export`, `cancel`, `finish`, `isRunning`,
/// the progress timer, every `ExportError`, `renderFrame` and every
/// settings helper (`ExporterSettings.swift` since phase 7) are what they
/// were.
///
/// **Why the writer replaced the session outright rather than joining it.**
/// The session path cannot express three things the sheet already promises:
/// a chapter track (`AVAssetExportSession` writes none, so a `chapter: true`
/// marker vanished on export), explicit bitrates (`ExportSettings` has
/// carried `videoBitrate`/`audioBitrate` all along and a preset NAME can say
/// nothing about them), and the resolved output size and frame rate — a
/// preset scales to fit whatever it likes, so the sheet's "1920 × 1080 ·
/// 25 fps" was a readout of numbers nothing downstream ever read. Keeping
/// both paths would have made all three conditional: chapters when the
/// project has them AND the codec took the writer, one quality rule here and
/// another there, and two answers to "what did the file end up as". That is
/// the same second-rendering-path this whole design exists to avoid, one
/// layer down. The writer covers every preset the core offers — H.264, HEVC,
/// ProRes and audio-only M4A — so there is no case left for the session to
/// hold.
///
/// **The two formats AVFoundation cannot write** — animated GIF and APNG —
/// are assembled frame by frame through ImageIO instead
/// (`ExporterImageSequence.swift`), over `renderFrame`, which is why that one
/// is static and takes no export state. Neither goes through AVFoundation at
/// all, so neither is a branch of the writer path: they are a second
/// pipeline, and `Exporter.pipeline` picks between the two on the core's
/// `avf_preset`. Everything below the pick — the progress timer, `finish`,
/// every `ExportError` — is shared, because the sheet cannot tell which one
/// it got.
///
/// **Two passes, since phase 5.** An export that carries sound MEASURES its
/// mix before it writes it (`Loudness.swift`), which is what lets the final
/// line report "Peak −1.0 dBTP · −14.0 LUFS" for every export and what
/// chooses the gain for one that asked to be normalised. That pass is
/// **`ExporterLoudness.swift`** — this class's own extension, cut out when this
/// file went past its size cap and otherwise unchanged — and its header carries
/// the rest of the argument: what the pass costs, why it builds a composition
/// of its own rather than sharing this one's mix, and why it reads float.
///
/// **Recipe options, since road map 2's phase 7.** `export` and `renderFrame`
/// each take a `RecipeOptions` (spec §7.3) — what the caller wants of the
/// PICTURE besides the timeline, today the burnt-in timecode. It is not an
/// export override and cannot be made one: the core's override table ignores
/// an unknown key on purpose, so an option sent that way would vanish and the
/// export would report success on an unchanged file. Both entry points take
/// it because they are two independent doors to the compositor — `export`
/// publishes it on this export's `RecipeSource` key, which is what every
/// frame `ExportWriter` reads back arrives through, while
/// `ImageSequenceWriter` bypasses the writer entirely and renders each frame
/// through `renderFrame`, on a key of its own. Both default to `.none`, so
/// everything that does not ask writes what it wrote before.
///
/// **Settings → AVFoundation lives in `ExporterSettings.swift`** — the time
/// range, the file type, the UTI, the extension
/// and `ExportSettings.isAudioOnly`, an extension of this class in a file of
/// its own, cut out when phase 7 came to add the options argument and this
/// file stood at exactly 600 lines. It is the same toll `ExporterLoudness.swift`
/// paid, and the same shape: pure functions of a settings value, no export
/// state, half their callers the export SHEET rather than the export.
///
/// **Deprecations.** `copyCGImage(at:actualTime:)` on
/// `AVAssetImageGenerator` is deprecated in favour of an `async` replacement.
/// Deliberately not taken: `async`/`await` is confined to
/// `MediaImporter.swift` (app/CLAUDE.md), and spec §7.8 names this exact API.
/// It is the only deprecation warning in this file, and the build baseline in
/// the root `CLAUDE.md` names it by file — which is why `renderFrame` stayed
/// here when the settings helpers went out.
final class Exporter {

    /// How often the sheet's bar is refreshed. Neither
    /// `AVAssetExportSession` nor `AVAssetWriter` has a progress callback, so
    /// the only way to draw a bar is to ask (spec §7.8); 0.1 s is smooth and
    /// costs nothing.
    static let progressInterval: TimeInterval = 0.1

    /// The documented rebuild seam (app/CLAUDE.md): building a composition
    /// opens asset tracks, which touches the disk. Same reason as
    /// `Playback`'s, and a queue of its own so an export cannot make the next
    /// preview rebuild wait behind it.
    private let buildQueue = DispatchQueue(
        label: "com.kgalligan.framejob.export", qos: .userInitiated)

    /// Whatever is writing this export: the `AVAssetWriter` path or the
    /// ImageIO one, behind the three calls `Exporter` makes of either
    /// (`ExportPipeline`).
    private var writer: (any ExportPipeline)?
    private var timer: Timer?
    /// This export's own `RecipeSource` slot. NOT the document's: the document
    /// republishes on every edit, and a frame already queued must not be
    /// composed from a project the user changed halfway through the write.
    private var recipeKey: Int?
    /// Where this export writes — removed by `finish` when a graphic failed.
    private var destination: URL?
    private var progressHandler: ((Double) -> Void)?
    private var completionHandler: ((Result<URL, any Error>) -> Void)?

    /// Guards everything the measurement pass and the main thread both touch.
    /// `ExportWriter` has the same three members for the same reason, and
    /// this is that discipline copied rather than a second one invented:
    /// `cancelRequested` used to be main-thread-only state, and a measure
    /// loop on `buildQueue` that reads it would make it a data race the
    /// moment the pass became cancellable.
    ///
    /// It and the four members below are internal only so that the pass that
    /// reads them can be — `ExporterLoudness.swift` is an extension of this
    /// class in another file. Nothing outside those two files may take it.
    let lock = NSLock()
    /// Set by `cancel()`. Checked once the build lands, because a cancel
    /// during the build has no writer to stop yet, and again per sample
    /// buffer of the measurement.
    private var cancelRequested = false
    /// 0…1 through the measurement pass.
    private var measureProgress: Double = 0
    /// True while the measurement reads samples. Only its own loop cancels
    /// its reader, never `cancel()`, and a read that never returns is not
    /// woken (spec §11 G-17).
    var measuring = false

    /// The share of the progress bar the measurement pass owns, decided
    /// before the build so the mapping cannot move under the sheet. A
    /// measurement really is about half of an audio-only export's work and a
    /// rounding error beside a movie's video encode, and a bar that claims
    /// otherwise is worse than one that is coarse.
    private var measureShare: Double = 0
    /// The measurement, held from the pass until `finish` publishes it.
    private var pendingLoudness: ExportLoudness?

    /// What this export's sound measured, and what the gain (if any) made of
    /// it — nil for a format with no audio, and until `finish` has run.
    ///
    /// Set in `finish`, which is documented below as the one exit, and NOT
    /// cleared by it: both consumers read it off the `Exporter` they already
    /// hold, after the completion has fired (the progress sheet in
    /// `finished(_:)`, the agent's `export` on its own stack). Widening the
    /// pipeline's `Result<URL, any Error>` instead would drag
    /// `ImageSequenceWriter` into a concept it has no audio to have.
    private(set) var loudnessReport: ExportLoudness?
    /// Each distinct warning this export's graphics gave (G-24 (c)), set in
    /// `finish` beside `loudnessReport` and before the unpin, whatever the
    /// result, and read the same way; reset in `export`.
    private(set) var graphicWarnings: [ExportGraphicWarning] = []

    /// Bytes for the measurement's sample buffers, grown once. Raw and
    /// 16-byte aligned rather than an `[UInt8]`, because the samples are
    /// bound to `Float` or `Int16` and an array of bytes promises neither
    /// alignment. Touched only on `buildQueue`.
    var scratchStorage: UnsafeMutableRawPointer?
    var scratchCapacity = 0

    init() {}

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("Exporter does not support NSCoder")
    }

    deinit {
        timer?.invalidate()
        releaseRecipeKey { DispatchQueue.global(qos: .utility).async(execute: $0) }
        scratchStorage?.deallocate()
    }

    // MARK: - Exporting

    /// Starts one export. Main thread only — it schedules a run-loop timer and
    /// calls back into the sheet — and one `Exporter` runs one export at a
    /// time; `completion` is called exactly once, on the main thread.
    ///
    /// `project` is a handle, and handles are immutable (spec §5.5), so the
    /// export keeps writing the timeline as it was when the sheet was
    /// confirmed no matter what the document does next.
    ///
    /// **`options` is what the caller wants of the PICTURE besides the
    /// timeline** (`RecipeOptions`, spec §7.3) — today, whether to burn the
    /// timecode in. It is not an export override and could not be one: the
    /// core's override table ignores a key it does not know, so an option
    /// posted that way would vanish and this would report success on a file
    /// it had not changed. It travels two ways from here, and BOTH are
    /// needed. Published on this export's own `RecipeSource` key, it reaches
    /// every frame `ExportWriter` reads back through the compositor; handed
    /// to `Exporter.pipeline`, it reaches `ImageSequenceWriter`, which never
    /// goes through `ExportWriter` at all and renders each GIF or APNG frame
    /// through a key of its own. Plumbing only the first would leave every
    /// image-sequence export silently un-burnt.
    ///
    /// The default is `.none`, so a caller that says nothing writes exactly
    /// the file it wrote before phase 7.
    ///
    /// **`graphics` is the document's compiled set as the export was asked
    /// for** (G-13, `ExporterGraphics.swift`): pinned on this export's key
    /// for its whole life, gated before the build, and the export stopped
    /// on the first frame a graphic fails. nil draws every graphic's slate.
    func export(
        project: ReelProject, urls: [UInt32: URL], settings: ExportSettings, to url: URL,
        options: RecipeOptions = .none, graphics: GraphicSet? = nil,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, any Error>) -> Void
    ) {
        setCancelRequested(false)
        setMeasureProgress(0)
        loudnessReport = nil
        graphicWarnings = []
        pendingLoudness = nil
        progressHandler = progress
        completionHandler = completion
        destination = url

        guard let plan = project.plan else {
            finish(.failure(ExportError.noPlan))
            return
        }
        // An EMPTY timeline is still refused; a timeline of nothing but text,
        // shapes and images is not. Those layers own no composition track
        // (§7.2), but CompositionBuilder gives that case a placeholder video
        // track so the recipe can still drive every frame.
        guard plan.duration > 0 else {
            finish(.failure(ExportError.emptyTimeline))
            return
        }

        let key = RecipeSource.shared.register()
        recipeKey = key
        RecipeSource.shared.set(project, for: key)
        // The options belong to the KEY, not to the handle, which is what
        // makes this enough: `finish` unregisters the key and takes them with
        // it, and nothing else in the process can be reading it.
        RecipeSource.shared.setOptions(options.delivering(settings), for: key)
        if let graphics = graphics { GraphicRegistry.shared.pin(graphics, for: key) }

        measureShare = Exporter.measuresLoudness(settings)
            ? (settings.isAudioOnly ? 0.5 : 0.1) : 0
        // The timer starts BEFORE the build rather than with the writer,
        // because the measurement pass is the first thing with a fraction to
        // report and, on an audio-only export, half the wait.
        startProgressTimer()

        let planJSON = project.planJSON
        buildQueue.async { [weak self] in
            let build = {
                try CompositionBuilder.build(
                    plan: plan, planJSON: planJSON, urls: urls, recipeKey: key)
            }
            // A module that does not compile refuses the export here, through
            // `startWriting`'s `.failure` arm, before the destination is touched.
            let result = Exporter.graphicsRefusal(
                project: project, settings: settings, graphics: graphics
            ).map { Result<BuiltComposition, any Error>.failure($0) } ?? Result {
                try Exporter.withRampAudio(plan: plan, urls: urls, settings: settings, key: key,
                    cancelled: { self?.isCancelled ?? true }, then: build) }
            // Read here, not on the main thread: the markers come off the
            // SNAPSHOT, and on a handle nothing has looked at yet that is the
            // first decode of the whole project JSON.
            let chapters = ExportChapter.list(from: project.snapshot.markers)
            var loudness: ExportLoudness?
            if case .success = result, Exporter.measuresLoudness(settings), let self = self,
                !self.isCancelled
            {
                // A composition of its own for the measurement (see the type
                // doc): the same plan, the same media, a fresh `AVAudioMix`
                // with fresh taps, and a video composition nothing reads.
                if let measured = try? build() {
                    loudness = self.measureLoudness(measured, settings: settings)
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.startWriting(
                    result, project: project, urls: urls, chapters: chapters,
                    settings: settings, loudness: loudness, graphics: graphics, to: url)
            }
        }
    }

    /// Cancels whatever stage the export is at. Safe to call twice, and safe
    /// to call before the composition has finished building — that is what
    /// `cancelRequested` is for. It only sets flags: each reader is cancelled
    /// by the loop that reads it (spec §11 G-17).
    func cancel() {
        setCancelRequested(true)
        writer?.cancel()
    }

    /// Whether this export measures its sound at all. Everything but the two
    /// image formats, which hold no audio track in the file format itself —
    /// the same fact the core reports as `audio: false` for those rows.
    private static func measuresLoudness(_ settings: ExportSettings) -> Bool {
        !settings.isImageSequence
    }

    /// True between `export` and its completion.
    var isRunning: Bool { completionHandler != nil }

    // MARK: - The write

    /// The built composition, the chapters and the settings, handed to the
    /// pipeline the settings ask for — the one place this file knows anything
    /// about how a file is actually written (`ExporterWriter.swift` and
    /// `ExporterImageSequence.swift`).
    private func startWriting(
        _ result: Result<BuiltComposition, any Error>, project: ReelProject,
        urls: [UInt32: URL], chapters: [ExportChapter], settings: ExportSettings,
        loudness: ExportLoudness?, graphics: GraphicSet?, to url: URL
    ) {
        guard completionHandler != nil else { return }
        pendingLoudness = loudness
        guard !isCancelled else {
            finish(.failure(ExportError.cancelled))
            return
        }
        let built: BuiltComposition
        switch result {
        case .failure(let error):
            finish(.failure(error))
            return
        case .success(let composition):
            built = composition
        }
        // AVFoundation refuses to write over an existing file, and a stale
        // one under a half-written image sequence would be no better. The
        // save panel already asked for permission to replace, so removing it
        // here is the user's answer being carried out, not a surprise.
        try? FileManager.default.removeItem(at: url)

        // Which pipeline writes it is the settings' decision rather than this
        // file's: `Exporter.pipeline` reads the core's `avf_preset` and hands
        // back either the `AVAssetWriter` path or the ImageIO one.
        //
        // The recipe options are read back off the KEY rather than carried
        // down from `export` as a second copy, so the export has exactly one
        // record of what it was asked for and the two pipelines cannot end up
        // disagreeing about it.
        let options = recipeKey.map { RecipeSource.shared.options(for: $0) } ?? .none
        let writer: any ExportPipeline
        do {
            writer = try Exporter.pipeline(
                built: built, project: project, urls: urls, settings: settings,
                chapters: chapters, options: options, graphics: graphics, to: url)
        } catch {
            finish(.failure(error))
            return
        }
        self.writer = writer
        // The gain is not part of choosing a pipeline, so it is handed over
        // after the pick rather than through it: `Exporter.pipeline` stays
        // the one place that decides WHICH pipeline writes a file, and a
        // gain only ever exists for settings that pick resolves to the
        // `AVAssetWriter` path — `measuresLoudness` refuses the image rows,
        // which are the only ones it does not.
        if let loudness = loudness, !loudness.isUnity {
            (writer as? ExportWriter)?.normalizeAudio(byLinearGain: Float(loudness.linearGain))
        }
        Exporter.startGraphicPrefetch(key: recipeKey, project: project, graphics: graphics,
            built: built, settings: settings, pipeline: writer)

        startProgressTimer()
        progressHandler?(measureShare)
        // The pipeline calls back on the main thread, exactly once. The bar
        // is driven to full here rather than left wherever the last sample
        // put it, so a consumer that watches only `progress` still sees the
        // end.
        writer.start { [weak self] result in
            guard let self = self else { return }
            if case .success = result { self.progressHandler?(1) }
            self.finish(Exporter.encoderOutcome(result, settings: settings, destination: url))
        }
    }

    /// The documented progress-timer seam (app/CLAUDE.md). A run-loop timer,
    /// not a dispatch source, so it stops deterministically the moment the
    /// write finishes. Idempotent: `export` starts it for the measurement
    /// and `startWriting` for the write, and only one runs.
    private func startProgressTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(
            withTimeInterval: Exporter.progressInterval, repeats: true
        ) { [weak self] _ in
            self?.pollProgress()
        }
    }

    private func pollProgress() {
        // A graphic failed on the render thread: stop the write, and `finish`
        // says which graphic and which frame.
        if let key = recipeKey, GraphicRegistry.shared.failure(for: key) != nil { cancel() }
        progressHandler?(currentProgress)
    }

    /// The bar: the measurement's share first, the write's the rest of the
    /// way. `measureShare` is 0 for a format with no sound, so an export
    /// that measures nothing reports exactly what it reported before.
    private var currentProgress: Double {
        if let writer = writer {
            return measureShare + writer.progress * (1 - measureShare)
        }
        lock.lock()
        defer { lock.unlock() }
        return measureProgress * measureShare
    }

    /// What the sheet should say while this runs, or nil for its own
    /// wording. Only the measurement has a phase of its own: the build
    /// before it is "Preparing…" and everything after it is "Writing…",
    /// which is what the sheet already says. `measuring` is set only once
    /// the reader has started, so the label appears exactly while samples
    /// are being measured and not for the build that precedes them.
    var phaseDescription: String? {
        lock.lock()
        defer { lock.unlock() }
        return measuring ? "Measuring loudness…" : nil
    }

    /// The one exit. Tears down the timer and the recipe slot before the
    /// caller hears anything, so a completion handler that starts another
    /// export finds this one fully unwound. The measurement is PUBLISHED
    /// here rather than cleared: both callers read it after their completion
    /// has fired.
    private func finish(_ result: Result<URL, any Error>) {
        let result = Exporter.graphicOutcome(result, key: recipeKey, destination: destination)
        loudnessReport = pendingLoudness
        graphicWarnings = Exporter.graphicWarnings(on: recipeKey)
        pendingLoudness = nil
        timer?.invalidate()
        timer = nil
        releaseRecipeKey()
        writer = nil
        let completion = completionHandler
        completionHandler = nil
        progressHandler = nil
        completion?(result)
    }

    /// For `finish` and `deinit`; `deinit` defers `ramp`, as it can run in `RampAudioRenders.wait`.
    private func releaseRecipeKey(ramp: (@escaping () -> Void) -> Void = { $0() }) {
        guard let key = recipeKey else { return }
        RecipeSource.shared.unregister(key)
        GraphicPrefetch.shared.stop(key)
        GraphicRegistry.shared.unpin(key)
        ramp { RampAudioRenders.shared.release(owner: key) }
        recipeKey = nil
    }

    // MARK: - Shared state

    /// The three accessors over `lock`. Two are internal for the same reason
    /// it is: `ExporterLoudness.swift` checks the first per sample buffer.
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelRequested
    }

    private func setCancelRequested(_ value: Bool) {
        lock.lock()
        cancelRequested = value
        lock.unlock()
    }

    func setMeasureProgress(_ value: Double) {
        lock.lock()
        measureProgress = value
        lock.unlock()
    }

    // MARK: - Offline single frame (spec §7.9's `render_frame`)

    /// One composed frame, rendered without a player — the agent's
    /// verification hook, and the M2 GIF/APNG writer's frame source.
    ///
    /// It goes through the SAME composition and video composition an export
    /// does, which is the entire value of it: what this returns is what the
    /// file will contain at `t`, not a second opinion about it. Both time
    /// tolerances are `.zero` so the frame is the one asked for rather than
    /// the nearest sync sample.
    ///
    /// Synchronous and disk-touching (it opens asset tracks and decodes):
    /// call it OFF the main thread. Returns nil rather than throwing for
    /// every failure — no plan, nothing to compose, a time past the end.
    ///
    /// **A timeline of nothing but text, shapes and images renders here.**
    /// This paragraph used to say the opposite — that such a project has no
    /// composition tracks, that `AVAssetImageGenerator` cannot run over a
    /// composition with none, and that it therefore rendered in the preview
    /// and not here. That was true once and stopped being true two milestones
    /// ago, while the sentence stayed: `CompositionBuilder.addPlaceholderIfNeeded`
    /// gives exactly that project an empty video track, whose one job is to
    /// make every frame time exist for the generator to ask about, and the
    /// recipe draws the picture as it always did. The guard below says the
    /// same thing in code four lines from here. Only a genuinely EMPTY
    /// timeline — `plan.duration == 0` — is refused.
    ///
    /// **`options` is a PARAMETER and not something read off the project**
    /// (`RecipeOptions`, spec §7.3), and that is load-bearing rather than
    /// belt-and-braces: this method registers a `RecipeSource` key of its
    /// OWN, so an option published against any other key — an export's, a
    /// document's — cannot reach the frames it renders. GIF and APNG never
    /// go through `ExportWriter` at all; `ImageSequenceWriter.append` calls
    /// this once per frame, and an option that travelled only on the export's
    /// key would leave every one of those files silently un-burnt.
    ///
    /// It defaults to `.none`, which is the right answer for a caller that
    /// wants the PICTURE rather than a deliverable: the canvas eyedropper
    /// samples what the canvas shows, and Save Frame grabs the frame. The
    /// callers that pass something are the export sheet, the `export` tool
    /// and `render_frame` — the last one both for agent parity and because it
    /// is the only way a proof script can photograph a burn-in at all.
    ///
    /// `graphics` is pinned on the frame's own key, as `export` pins it on
    /// its own; nil draws every graphic's slate. `keepsDepth` is the caller's
    /// format (`carriesDepth`): when true and `DeepVideoFrame.reads` the frame (a deep still,
    /// PR-9, or a deep VP9 track, PR-12), `DeepStillFrame.read`'s reader reads it.
    static func renderFrame(
        project: ReelProject, urls: [UInt32: URL], at t: Ticks, maxWidth: Int?,
        options: RecipeOptions = .none, graphics: GraphicSet? = nil, keepsDepth: Bool = false
    ) -> CGImage? {
        renderFrameReported(
            project: project, urls: urls, at: t, maxWidth: maxWidth, options: options,
            graphics: graphics, keepsDepth: keepsDepth
        ).image
    }

    /// `renderFrame`, with what the frame's graphics reported while it was
    /// drawn — read off the key's pin before it is dropped.
    static func renderFrameReported(
        project: ReelProject, urls: [UInt32: URL], at t: Ticks, maxWidth: Int?,
        options: RecipeOptions, graphics: GraphicSet?, keepsDepth: Bool = false
    ) -> RenderedFrame {
        // No videoTracks is NOT a refusal: CompositionBuilder gives a
        // timeline of nothing but text, shapes and images a placeholder track
        // so the recipe can still drive every frame. Only a genuinely empty
        // timeline has nothing to render.
        guard let plan = project.plan, plan.duration > 0 else {
            return RenderedFrame(image: nil, graphics: [])
        }
        let key = RecipeSource.shared.register()
        defer { RecipeSource.shared.unregister(key) }
        RecipeSource.shared.set(project, for: key)
        if let graphics = graphics { GraphicRegistry.shared.pin(graphics, for: key) }
        // Runs after the `return` below has read the reports.
        defer { GraphicRegistry.shared.unpin(key) }
        // Before the build, not after: the generator may ask for a frame the
        // moment the composition exists, and a frame composed against this
        // key's defaults would be one frame short of what was asked for.
        RecipeSource.shared.setOptions(options, for: key)

        let built: BuiltComposition
        do {
            built = try CompositionBuilder.build(
                plan: plan, planJSON: project.planJSON, urls: urls, recipeKey: key)
        } catch {
            return RenderedFrame(image: nil, graphics: GraphicRegistry.shared.reports(for: key))
        }
        if DeepVideoFrame.reads(project, built, urls: urls, at: t, options: options, keepsDepth: keepsDepth) {
            return RenderedFrame(
                image: DeepStillFrame.read(built, at: t, maxWidth: maxWidth),
                graphics: GraphicRegistry.shared.reports(for: key))
        }

        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // The video composition already applies every source's orientation
        // (`CompositionBuilder.orientationCode`), so asking the generator to
        // apply a preferred transform on top would turn the frame twice.
        generator.appliesPreferredTrackTransform = false
        if let maxWidth = maxWidth, maxWidth > 0 {
            generator.maximumSize = scaledSize(built.videoComposition.renderSize, to: maxWidth)
        }
        let image = try? generator.copyCGImage(
            at: CompositionBuilder.time(max(0, t)), actualTime: nil)
        return RenderedFrame(image: image, graphics: GraphicRegistry.shared.reports(for: key))
    }

    /// `size` capped to `maxWidth`, aspect kept, never upscaled and never
    /// zero in either axis.
    static func scaledSize(_ size: CGSize, to maxWidth: Int) -> CGSize {
        guard size.width >= 1, size.height >= 1 else {
            return CGSize(width: maxWidth, height: maxWidth)
        }
        guard CGFloat(maxWidth) < size.width else { return size }
        let scale = CGFloat(maxWidth) / size.width
        return CGSize(width: CGFloat(maxWidth), height: max(1, (size.height * scale).rounded()))
    }
}
