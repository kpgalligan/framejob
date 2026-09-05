import AVFoundation
import AppKit
import UniformTypeIdentifiers

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
/// M1 is `AVAssetExportSession`: the core resolves a preset into concrete
/// settings, this hands them over, and the sheet polls `progress`.
///
/// **M2 seam** — the `AVAssetWriter` path replaces `startSession` and nothing
/// else in this file. It is what adds: a chapter track (an
/// `AVAssetWriterInput` text track associated with the video input through
/// `AVTrackAssociationTypeChapterList`, fed from the project's `chapter`
/// markers), explicit video/audio bitrates (`ExportSettings.videoBitrate` and
/// `audioBitrate` are already carried here and are simply unused by the
/// session path, which only takes a preset name), and the GIF/APNG writers
/// (ImageIO frame-by-frame over `renderFrame`, which is why that one is
/// static and takes no session state).
///
/// **Deprecations.** `exportAsynchronously(completionHandler:)`, `status`,
/// `progress` and `error` on `AVAssetExportSession`, and
/// `copyCGImage(at:actualTime:)` on `AVAssetImageGenerator`, are deprecated in
/// favour of `async` replacements. Deliberately not taken: `async`/`await` is
/// confined to `MediaImporter.swift` (app/CLAUDE.md), and spec §7.8 names this
/// exact API. Those are the only deprecation warnings in this file.
final class Exporter {

    /// Why an export stopped. Every case is reported through `completion` —
    /// nothing here throws at the caller and nothing crashes.
    enum ExportError: LocalizedError {
        /// The core could not produce a composition plan for this project.
        case noPlan
        /// Nothing to write: no video and no audio track in the plan. Reached
        /// by an empty timeline AND by one holding only text, shapes and
        /// images, which need no composition track (spec §7.2) — so the
        /// message has to name the second case, which is the surprising one.
        case emptyTimeline
        /// `AVAssetExportSession` would not build with the preset name the
        /// core resolved (or the fallback for it).
        case presetUnavailable(String)
        /// The settings named a container this build cannot map to a file
        /// type.
        case fileTypeUnsupported(String)
        /// The user pressed Cancel. The sheet dismisses without an alert.
        case cancelled
        /// The session ended in a state that is neither completed nor
        /// cancelled and had no error of its own.
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noPlan:
                return "The project could not be prepared for export."
            case .emptyTimeline:
                return "There is nothing on the timeline to export — add a clip first."
            case .presetUnavailable(let name):
                return "This Mac cannot export with the “\(name)” preset."
            case .fileTypeUnsupported(let container):
                return "“\(container)” is not a container this build can write."
            case .cancelled:
                return "The export was cancelled."
            case .failed(let message):
                return message
            }
        }
    }

    /// How often the sheet's bar is refreshed. `AVAssetExportSession` has no
    /// progress callback, so the only way to draw a bar is to ask (spec
    /// §7.8); 0.1 s is smooth and costs nothing.
    static let progressInterval: TimeInterval = 0.1

    /// The documented rebuild seam (app/CLAUDE.md): building a composition
    /// opens asset tracks, which touches the disk. Same reason as
    /// `Playback`'s, and a queue of its own so an export cannot make the next
    /// preview rebuild wait behind it.
    private let buildQueue = DispatchQueue(
        label: "com.kgalligan.reelcut.export", qos: .userInitiated)

    private var session: AVAssetExportSession?
    private var timer: Timer?
    /// This export's own `RecipeSource` slot. NOT the document's: the document
    /// republishes on every edit, and a frame already queued must not be
    /// composed from a project the user changed halfway through the write.
    private var recipeKey: Int?
    private var progressHandler: ((Double) -> Void)?
    private var completionHandler: ((Result<URL, any Error>) -> Void)?
    private var destination: URL?
    /// Set by `cancel()`. Checked once the build lands, because a cancel
    /// during the build has no session to stop yet.
    private var cancelRequested = false

    init() {}

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("Exporter does not support NSCoder")
    }

    deinit {
        timer?.invalidate()
        if let key = recipeKey { RecipeSource.shared.unregister(key) }
    }

    // MARK: - Exporting

    /// Starts one export. Main thread only — it schedules a run-loop timer and
    /// calls back into the sheet — and one `Exporter` runs one export at a
    /// time; `completion` is called exactly once, on the main thread.
    ///
    /// `project` is a handle, and handles are immutable (spec §5.5), so the
    /// export keeps writing the timeline as it was when the sheet was
    /// confirmed no matter what the document does next.
    func export(
        project: ReelProject, urls: [UInt32: URL], settings: ExportSettings, to url: URL,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, any Error>) -> Void
    ) {
        cancelRequested = false
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

        let planJSON = project.planJSON
        buildQueue.async { [weak self] in
            let result = Result {
                try CompositionBuilder.build(
                    plan: plan, planJSON: planJSON, urls: urls, recipeKey: key)
            }
            DispatchQueue.main.async { [weak self] in
                self?.startSession(result, settings: settings, to: url)
            }
        }
    }

    /// Cancels whatever stage the export is at. Safe to call twice, and safe
    /// to call before the composition has finished building — that is what
    /// `cancelRequested` is for.
    func cancel() {
        cancelRequested = true
        session?.cancelExport()
    }

    /// True between `export` and its completion.
    var isRunning: Bool { completionHandler != nil }

    // MARK: - The session

    private func startSession(
        _ result: Result<BuiltComposition, any Error>, settings: ExportSettings, to url: URL
    ) {
        guard completionHandler != nil else { return }
        guard !cancelRequested else {
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

        let presetName = settings.avPreset ?? Exporter.fallbackPreset(for: settings)
        guard let session = AVAssetExportSession(asset: built.composition, presetName: presetName)
        else {
            finish(.failure(ExportError.presetUnavailable(presetName)))
            return
        }
        guard let fileType = Exporter.fileType(for: settings) else {
            finish(.failure(ExportError.fileTypeUnsupported(settings.container)))
            return
        }
        // AVFoundation refuses to write over an existing file. The save panel
        // already asked for permission to replace, so removing it here is the
        // user's answer being carried out, not a surprise.
        try? FileManager.default.removeItem(at: url)

        session.outputURL = url
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = settings.optimizeForNetwork
        session.timeRange = Exporter.timeRange(settings, composition: built.composition)
        // An audio-only preset gets NO video composition: attaching one asks
        // AVFoundation to run the custom compositor for frames nothing will
        // write, which at best wastes the whole render and at worst refuses
        // the preset outright.
        if !settings.isAudioOnly {
            session.videoComposition = built.videoComposition
        }
        session.audioMix = built.audioMix
        self.session = session

        // The documented progress-timer seam (app/CLAUDE.md). A run-loop
        // timer, not a dispatch source, so it stops deterministically the
        // moment the session finishes.
        timer = Timer.scheduledTimer(
            withTimeInterval: Exporter.progressInterval, repeats: true
        ) { [weak self] _ in
            self?.pollProgress()
        }
        progressHandler?(0)
        session.exportAsynchronously { [weak self] in
            // AVFoundation calls this on a queue of its own.
            OperationQueue.main.addOperation { self?.sessionFinished() }
        }
    }

    private func pollProgress() {
        guard let session = session else { return }
        progressHandler?(Double(session.progress))
    }

    private func sessionFinished() {
        guard let session = session, let url = destination else { return }
        switch session.status {
        case .completed:
            progressHandler?(1)
            finish(.success(url))
        case .cancelled:
            finish(.failure(ExportError.cancelled))
        default:
            finish(
                .failure(
                    session.error
                        ?? ExportError.failed("The export stopped before it finished.")))
        }
    }

    /// The one exit. Tears down the timer and the recipe slot before the
    /// caller hears anything, so a completion handler that starts another
    /// export finds this one fully unwound.
    private func finish(_ result: Result<URL, any Error>) {
        timer?.invalidate()
        timer = nil
        if let key = recipeKey {
            RecipeSource.shared.unregister(key)
            recipeKey = nil
        }
        session = nil
        let completion = completionHandler
        completionHandler = nil
        progressHandler = nil
        completion?(result)
    }

    // MARK: - Settings → AVFoundation

    /// The range to write. The core has already resolved "whole project" or
    /// "in/out range" into `start` and `duration` (§7.8); a zero duration only
    /// happens if the project has none, and then the composition's own length
    /// is the honest answer.
    static func timeRange(_ settings: ExportSettings, composition: AVComposition) -> CMTimeRange {
        let start = CompositionBuilder.time(max(0, settings.start))
        guard settings.duration > 0 else {
            return CMTimeRange(start: start, duration: composition.duration)
        }
        return CMTimeRange(start: start, duration: CompositionBuilder.time(settings.duration))
    }

    /// The `AVAssetExportSession` preset for settings the core did not name
    /// one for. Deliberately a fallback rather than the rule: §7.8 makes the
    /// preset the core's decision, and this only exists so a core that adds a
    /// preset before this build knows about it still exports something
    /// sensible instead of refusing.
    static func fallbackPreset(for settings: ExportSettings) -> String {
        if settings.isAudioOnly { return AVAssetExportPresetAppleM4A }
        switch settings.codec.lowercased() {
        case "hevc", "h265":
            return settings.width >= 3840
                ? AVAssetExportPresetHEVC3840x2160 : AVAssetExportPresetHEVC1920x1080
        case "prores_422", "prores", "prores422":
            return AVAssetExportPresetAppleProRes422LPCM
        default:
            if settings.width >= 3840 { return AVAssetExportPreset3840x2160 }
            if settings.width >= 1920 { return AVAssetExportPreset1920x1080 }
            if settings.width >= 1280 { return AVAssetExportPreset1280x720 }
            return AVAssetExportPreset960x540
        }
    }

    /// The output file type: the core's UTI when it gave one, else the
    /// container name mapped to the four this build writes.
    static func fileType(for settings: ExportSettings) -> AVFileType? {
        if let raw = settings.fileType, !raw.isEmpty { return AVFileType(rawValue: raw) }
        switch settings.container.lowercased() {
        case "mov", "quicktime": return .mov
        case "mp4": return .mp4
        case "m4v": return .m4v
        case "m4a": return .m4a
        default: return nil
        }
    }

    /// The save panel's allowed type. `AVFileType`'s raw values ARE UTIs, so
    /// this is the same decision as `fileType(for:)` and cannot drift from it.
    static func contentType(for settings: ExportSettings) -> UTType? {
        guard let type = fileType(for: settings) else { return nil }
        return UTType(type.rawValue)
    }

    /// The extension the save panel appends.
    static func fileExtension(for settings: ExportSettings) -> String {
        contentType(for: settings)?.preferredFilenameExtension
            ?? settings.container.lowercased()
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
    /// **Limitation**, and the same one `Playback` has: a project whose
    /// visible clips are all text, shapes or images has no composition
    /// tracks, and `AVAssetImageGenerator` cannot run over a composition with
    /// none. Such a project renders in the preview (the compositor draws from
    /// the recipe) but not here. M2's writer path removes the restriction by
    /// driving the compositor itself.
    static func renderFrame(
        project: ReelProject, urls: [UInt32: URL], at t: Ticks, maxWidth: Int?
    ) -> CGImage? {
        // No videoTracks is NOT a refusal: CompositionBuilder gives a
        // timeline of nothing but text, shapes and images a placeholder track
        // so the recipe can still drive every frame. Only a genuinely empty
        // timeline has nothing to render.
        guard let plan = project.plan, plan.duration > 0 else { return nil }
        let key = RecipeSource.shared.register()
        defer { RecipeSource.shared.unregister(key) }
        RecipeSource.shared.set(project, for: key)

        let built: BuiltComposition
        do {
            built = try CompositionBuilder.build(
                plan: plan, planJSON: project.planJSON, urls: urls, recipeKey: key)
        } catch {
            return nil
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
        return try? generator.copyCGImage(
            at: CompositionBuilder.time(max(0, t)), actualTime: nil)
    }

    /// `size` capped to `maxWidth`, aspect kept, never upscaled and never
    /// zero in either axis.
    private static func scaledSize(_ size: CGSize, to maxWidth: Int) -> CGSize {
        guard size.width >= 1, size.height >= 1 else {
            return CGSize(width: maxWidth, height: maxWidth)
        }
        guard CGFloat(maxWidth) < size.width else { return size }
        let scale = CGFloat(maxWidth) / size.width
        return CGSize(width: CGFloat(maxWidth), height: max(1, (size.height * scale).rounded()))
    }
}

// MARK: - Audio-only settings

extension ExportSettings {
    /// True for the "Audio only" preset row (spec §7.8's M4A). Read from the
    /// resolved settings rather than carried from the `ExportPreset` the sheet
    /// picked, so the `Exporter` needs nothing but its settings — and so the
    /// agent's `export {preset, path}` behaves the same as the sheet.
    var isAudioOnly: Bool {
        if let preset = avPreset, preset == AVAssetExportPresetAppleM4A { return true }
        switch container.lowercased() {
        case "m4a", "mp3", "wav", "aiff", "caf": return true
        default: return false
        }
    }
}
