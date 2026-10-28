import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Choosing a pipeline

/// What `Exporter` needs of whatever is actually writing the file.
///
/// There are two now: `ExportWriter` (`ExporterWriter.swift`), which encodes
/// a movie through `AVAssetWriter`, and `ImageSequenceWriter` below, which
/// assembles a GIF or an APNG frame by frame through ImageIO. Inside they
/// have nothing in common — one reads a composition back on AVFoundation's
/// schedule, the other renders single frames offline — but from the sheet's
/// side an export is an export: it starts once, it reports a fraction while
/// it runs, it can be cancelled, and it calls back exactly once on the main
/// thread. That is the whole protocol, and it is what lets `Exporter` keep
/// one progress timer, one `finish` and one set of `ExportError`s instead of
/// a second copy of each per format.
protocol ExportPipeline: AnyObject {
    /// 0…1, polled by `Exporter`'s timer every `Exporter.progressInterval`.
    var progress: Double { get }
    /// Begins the write. Main thread; `completion` is called exactly once, on
    /// the main thread, and may be called before this returns.
    func start(completion: @escaping (Result<URL, any Error>) -> Void)
    /// Stops as soon as the write notices. Safe from any thread, safe to call
    /// twice, and safe to call after the write has already finished.
    func cancel()
}

/// The writer already had this shape to the letter. Declaring the conformance
/// here rather than in `ExporterWriter.swift` keeps that file knowing nothing
/// about a second pipeline — the choice between them belongs to the one place
/// that makes it, `Exporter.pipeline`.
extension ExportWriter: ExportPipeline {}

/// A pipeline the loudness normalisation's gain is handed to after the pick (`Exporter`'s
/// one caller): the `AVAssetWriter` path and the WebM one (spec §11 CX-15 (2)), each
/// applying it with `ExportAudioGain` before the end of the sound is cut.
protocol ExportAudioNormalizing: AnyObject {
    func normalizeAudio(byLinearGain gain: Float)
}

extension ExportWriter: ExportAudioNormalizing {}

extension ExportSettings {
    /// True when the core resolved a format AVFoundation cannot write, and
    /// the file is to be assembled frame by frame instead.
    ///
    /// The test is the ABSENT `avf_preset`, which is precisely what
    /// `export.rs` documents it to mean — "Swift's cue to take the ImageIO
    /// path… NOT 'pick a session preset yourself'" — rather than a list of
    /// container names here that would have to be kept in step with the
    /// preset table by hand. A container this build has no ImageIO format for
    /// still lands in `ImageSequenceFormat(container:)` and is refused there
    /// with `.fileTypeUnsupported`; sending it down the AVFoundation path
    /// instead would hand `AVAssetWriter` a file type it raises on rather
    /// than throws for.
    var isImageSequence: Bool { avPreset == nil }

    /// How many frames the range holds: the writer's count and the export
    /// sheet's readout alike. Floor, and at least one (a range shorter than a
    /// frame is a still); nil when the rate cannot be stepped.
    var sequenceFrameCount: Int? {
        let step = fps.frameDuration
        guard step > 0 else { return nil }
        return max(1, Int(max(0, duration) / step))
    }
}

extension Exporter {
    /// The pipeline for these settings: the `AVAssetWriter` path for every
    /// movie preset, the core's WebM writer for a `webm` container, the
    /// ImageIO path for the two image ones.
    ///
    /// `built` reaches only the writer, which reads the whole composition
    /// back through it; the image path renders each frame from the project
    /// itself, at the size the core resolved. Building the composition is
    /// not wasted work for it even so — that is what turns missing or
    /// unreadable media into a reported failure before a single frame is
    /// written, and `Exporter` has built it before either pipeline exists.
    ///
    /// `chapters` reach only the writer. Neither GIF nor APNG has anywhere to
    /// put them, which is the same fact about those containers that
    /// `export.rs` reports as `audio: false` for their rows.
    ///
    /// `options` (spec §7.3) is the mirror image: they reach only the IMAGE
    /// path. The writer needs none, because it never asks for a recipe — it
    /// reads the composition back, and every frame inside it is composed by
    /// the compositor against the export's `RecipeSource` key, which
    /// `Exporter.export` has already published them on. The image path has no
    /// such composition to read: it renders each frame through
    /// `Exporter.renderFrame`, which mints a key of its own, so the options
    /// have to be handed to it as a value. That asymmetry is the whole reason
    /// this parameter exists, and it is why `ExporterWriter.swift` needed no
    /// edit for the burn-in at all.
    ///
    /// `graphics` goes the same way for the same reason: the export's pin is
    /// on the export's key, and each image frame pins it on its own.
    static func pipeline(
        built: BuiltComposition, project: ReelProject, urls: [UInt32: URL],
        settings: ExportSettings, chapters: [ExportChapter], options: RecipeOptions,
        graphics: GraphicSet?, to url: URL
    ) throws -> any ExportPipeline {
        // A WebM is the core's to write (spec §11 CX-15 (2)): the second writer.
        if settings.container.lowercased() == "webm" {
            return try ExportWebMWriter(
                built: built, settings: settings, chapters: chapters, to: url)
        }
        guard settings.isImageSequence else {
            return try ExportWriter(built: built, settings: settings, chapters: chapters, to: url)
        }
        return try ImageSequenceWriter(
            project: project, urls: urls, settings: settings, options: options,
            graphics: graphics, to: url)
    }
}

// MARK: - The two image formats

/// A format ImageIO assembles from a list of frames (spec §7.8).
///
/// Both are one `CGImageDestination` holding many images, and both keep their
/// animation properties under the destination's format dictionary — but not
/// the same one, and not under the same keys, which is the whole reason this
/// is an enum rather than a pair of constants: the loop count and the frame
/// delay are the only things that differ between writing a GIF and writing an
/// APNG, and they differ in every character.
///
/// An APNG's destination type is PNG's own. The animation lives in `acTL` and
/// `fcTL` chunks inside a file that is still an ordinary PNG — which is why
/// `export.rs` resolves that row's `file_type` to `public.png` and why a
/// viewer that knows nothing of APNG shows the first frame rather than an
/// error.
enum ImageSequenceFormat {
    case gif
    case apng

    /// The core's container name. nil is a refusal: this build writes these
    /// two and nothing else, and a container it does not know must reach the
    /// user as `.fileTypeUnsupported` rather than as a file of the wrong kind.
    init?(container: String) {
        switch container.lowercased() {
        case "gif": self = .gif
        case "apng": self = .apng
        default: return nil
        }
    }

    /// What the format is called in a message the user reads.
    var displayName: String {
        switch self {
        case .gif: return "GIF"
        case .apng: return "APNG"
        }
    }

    /// True where the file carries its frames' colour label, so each frame is
    /// labelled BT.709 first (`FrameWriter.labelled`, spec §11 PR-11). A GIF
    /// carries none — ImageIO writes no `ICCRGBG1` extension and reads every
    /// GIF as sRGB (measured, `frame_label_proof.py` E3) — so its frames are
    /// left as they are.
    var carriesLabel: Bool {
        switch self {
        case .gif: return false
        case .apng: return true
        }
    }

    /// The destination's type. Taken from `UTType` rather than spelled as a
    /// literal so it cannot drift from the UTI `export.rs` puts in
    /// `file_type` — the same identifier the save panel derives the
    /// extension from (`Exporter.contentType(for:)`).
    var destinationType: CFString {
        switch self {
        case .gif: return UTType.gif.identifier as CFString
        case .apng: return UTType.png.identifier as CFString
        }
    }

    /// The whole file's properties: loop forever.
    ///
    /// Zero means "endlessly" in both formats, and endlessly is the only
    /// sensible default for a clip cut out of a timeline — an animated GIF
    /// that played once and stopped would be a video file with none of a
    /// video file's controls.
    var fileProperties: CFDictionary {
        switch self {
        case .gif:
            return [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFLoopCount as String: 0
                ]
            ] as CFDictionary
        case .apng:
            return [
                kCGImagePropertyPNGDictionary as String: [
                    kCGImagePropertyAPNGLoopCount as String: 0
                ]
            ] as CFDictionary
        }
    }

    /// One frame's properties: how long it is held, in seconds.
    ///
    /// Both the clamped and the unclamped delay are written, to the same
    /// number. Readers disagree about the first: a floor is applied to it by
    /// some, ImageIO itself included — read an APNG written at 25 fps back
    /// and its `DelayTime` comes out 0.05 while `UnclampedDelayTime` is the
    /// 0.04 the file holds (measured) — so the unclamped one is the honest
    /// value and the clamped one is what a reader that enforces a floor will
    /// use anyway.
    ///
    /// The preset rates exist so the number is expressible at all
    /// (`export.rs`: a GIF delay is stored as a whole number of hundredths of
    /// a second, which is why that preset is 12.5 fps and not 15). A
    /// frame-rate override that is not expressible lands wherever the
    /// format's own rounding puts it, which is the format's rule and not
    /// something to second-guess here.
    func frameProperties(delay: Double) -> CFDictionary {
        switch self {
        case .gif:
            return [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime as String: delay,
                    kCGImagePropertyGIFUnclampedDelayTime as String: delay,
                ]
            ] as CFDictionary
        case .apng:
            return [
                kCGImagePropertyPNGDictionary as String: [
                    kCGImagePropertyAPNGDelayTime as String: delay,
                    kCGImagePropertyAPNGUnclampedDelayTime as String: delay,
                ]
            ] as CFDictionary
        }
    }
}

// MARK: - The image-sequence pipeline

/// Writes an animated GIF or APNG by rendering the timeline one frame at a
/// time into a `CGImageDestination` (spec §7.8).
///
/// **Why this is not a branch of the writer path.** AVFoundation writes
/// neither format — there is no `AVFileType` for either — so there is no
/// session to configure and no `AVAssetWriterInput` to feed. What there is
/// instead is a list of frame times and a file that holds pictures, which is
/// ImageIO's job and nothing else's.
///
/// **The frame source is `Exporter.renderFrame`, deliberately.** That method
/// is static and takes no export state precisely so this can drive it, and
/// using it keeps the property the whole design exists for: a GIF frame is
/// composed by the same compositor, from the same recipe, through the same
/// composition as the same frame in the preview and in an H.264 export. A
/// second, ImageIO-shaped rendering path would be a second opinion about what
/// the movie looks like. What it costs is that every frame builds a
/// composition, an image generator and a compositor of its own where the
/// writer builds one for the whole file: a few tens of milliseconds a frame
/// at these presets' sizes (measured), which is nothing for a clip and is the
/// reason for `maxFrames`.
///
/// **No audio, ever.** Neither container has a track to put it in, which the
/// core states as `audio: false` for both rows rather than leaving it to be
/// discovered here.
///
/// **Progress and cancellation match the writer exactly**, because the sheet
/// cannot tell which pipeline it got: the fraction is frames appended over
/// frames wanted and `Exporter`'s 0.1 s timer reads it, the cancel flag is
/// checked between frames — a single frame is bounded work, so a cancel lands
/// within one — and `completion` is called once, on the main thread.
final class ImageSequenceWriter: ExportPipeline {

    /// The most frames either format will be assembled from. A refusal rather
    /// than a truncation: a GIF that silently stopped halfway would be a file
    /// the user did not ask for, and the message names the two knobs that fix
    /// it.
    ///
    /// **What the cap protects against.** Both formats store every frame as a
    /// whole picture with no inter-frame prediction, so a file's size is
    /// frames × pixels and nothing else — the same fact that made `export.rs`
    /// pin both presets to a small size and a low rate. On top of that, every
    /// frame here is a full offline render. A ten-minute timeline exported at
    /// 30 fps is 18,000 of them: ten minutes of rendering ending in a file of
    /// hundreds of megabytes that no viewer will open, from a Range popup
    /// left on "Whole project" by mistake. 600 frames is 48 s at the GIF
    /// preset's 12.5 fps and 24 s at
    /// the APNG preset's 25 — past anything either format is used for, and
    /// short enough that the mistake is caught in the first seconds instead
    /// of at the end of the wait. The sheet already shows the frame count in
    /// its summary line, so the number the refusal names is the one the user
    /// was looking at.
    static let maxFrames = 600

    private let project: ReelProject
    private let urls: [UInt32: URL]
    /// What the export asked of the PICTURE besides the timeline (spec §7.3),
    /// carried as a VALUE because this pipeline cannot read it any other way:
    /// every frame goes through `Exporter.renderFrame`, which registers a
    /// `RecipeSource` key of its own, so the export's key — where
    /// `Exporter.export` published these — is one no frame of this file will
    /// ever be composed against.
    private let options: RecipeOptions
    /// The export's compiled graphics, pinned per frame for the same reason.
    private let graphics: GraphicSet?
    private let destination: URL
    private let format: ImageSequenceFormat
    /// Every frame's time in the PROJECT's clock, in order. Precomputed:
    /// the range and the rate cannot change once the sheet is confirmed, and
    /// a list makes the count — the denominator of `progress` and the size
    /// `CGImageDestination` is created for — a fact rather than an estimate.
    private let times: [Ticks]
    /// The rate the export resolved to — the preset's or the sheet's, not
    /// necessarily the project's — for the timecode in a failure message.
    private let fps: Fps
    /// The size every frame is written at: the settings', exactly. The core
    /// has already fitted the picture inside the cap or the requested size
    /// (`export_size.rs`), so these are the numbers the sheet showed and the
    /// numbers the `export` tool reports, and the file has to carry them
    /// rather than whatever `AVAssetImageGenerator` rounds its `maximumSize`
    /// down to — a 1080 × 1920 timeline asked for at 152 × 270 came back
    /// 151 wide.
    private let frameSize: CGSize
    private let sink: CGImageDestination
    private let frameProperties: CFDictionary

    /// One frame at a time, off the main thread — `Exporter.renderFrame`
    /// decodes and composites, and its own documentation says never to call
    /// it on the main one. Serial because the frames go into the destination
    /// in order.
    private let queue = DispatchQueue(
        label: "com.kgalligan.framejob.export.images", qos: .userInitiated)

    /// Guards what the render queue and the main thread both touch.
    private let lock = NSLock()
    private var appended = 0
    private var cancelRequested = false

    /// Called once, on the main thread, and then dropped.
    private var completion: ((Result<URL, any Error>) -> Void)?

    /// Resolves the settings into a frame list and opens the destination, or
    /// throws the `Exporter.ExportError` the sheet should show. Nothing is
    /// rendered and nothing is written until `start`.
    init(
        project: ReelProject, urls: [UInt32: URL], settings: ExportSettings,
        options: RecipeOptions, graphics: GraphicSet?, to url: URL
    ) throws {
        guard let format = ImageSequenceFormat(container: settings.container) else {
            throw Exporter.ExportError.fileTypeUnsupported(settings.container)
        }
        // `sequenceFrameCount`, which the sheet's "N frames" readout reads
        // too. The core has already snapped the range to this very grid, so
        // its division is usually exact.
        guard let count = settings.sequenceFrameCount else {
            throw Exporter.ExportError.failed(
                "The export frame rate is not one this build can step through.")
        }
        let step = settings.fps.frameDuration
        guard count <= Self.maxFrames else {
            throw Exporter.ExportError.failed(
                "An animated \(format.displayName) is limited to \(Self.maxFrames) frames and "
                    + "this range is \(count). Shorten the range, or lower the export frame "
                    + "rate.")
        }

        self.project = project
        self.urls = urls
        self.options = options
        self.graphics = graphics
        self.destination = url
        self.format = format
        self.fps = settings.fps
        let start = max(0, settings.start)
        self.times = (0..<count).map { start + Ticks($0) * step }
        self.frameSize = CGSize(width: max(1, settings.width), height: max(1, settings.height))
        self.frameProperties = format.frameProperties(
            delay: Double(step) / Double(ReelTime.perSecond))

        guard let sink = CGImageDestinationCreateWithURL(
            url as CFURL, format.destinationType, count, nil)
        else {
            throw Exporter.ExportError.failed("The file could not be opened for writing.")
        }
        // Before any image is added. The loop count belongs to a header —
        // the GIF's `NETSCAPE2.0` application extension, the APNG's `acTL`
        // chunk — that comes before the first frame in the file (measured:
        // `acTL` precedes `IDAT` in what this writes), and setting it up
        // front is the ordering every ImageIO example uses.
        CGImageDestinationSetProperties(sink, format.fileProperties)
        self.sink = sink
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ImageSequenceWriter does not support NSCoder")
    }

    // MARK: - Running

    /// Main thread. Every frame is rendered on the queue, so this returns
    /// immediately and the completion always arrives later — where the writer
    /// path can refuse before returning, this one has nothing left to refuse:
    /// `init` did all of it.
    func start(completion: @escaping (Result<URL, any Error>) -> Void) {
        self.completion = completion
        queue.async { [weak self] in self?.run() }
    }

    /// A flag, as the writer's cancel is: a frame render is bounded work that
    /// finishes on its own, so the flag is read between frames and the
    /// render in flight is simply thrown away.
    func cancel() {
        lock.lock()
        cancelRequested = true
        lock.unlock()
    }

    var progress: Double {
        lock.lock()
        defer { lock.unlock() }
        // `times` is never empty — `init` refuses a zero-length range through
        // `max(1, …)` — so this divides by at least one.
        return min(1, Double(appended) / Double(times.count))
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelRequested
    }

    private func run() {
        for (index, time) in times.enumerated() {
            guard !isCancelled else {
                fail(Exporter.ExportError.cancelled)
                return
            }
            // One pool per frame, not one for the whole loop: every frame
            // builds a composition, an image generator and a compositor of
            // its own, all of them autoreleased, and the loop is a single
            // block on the queue. Without this the peak memory of a
            // 600-frame GIF is 600 compositions.
            if let error = autoreleasepool(invoking: { append(at: time) }) {
                fail(error)
                return
            }
            lock.lock()
            appended = index + 1
            lock.unlock()
        }
        // The last frame can land while the user is pressing Cancel; a file
        // they cancelled out of is not one to hand back because the timing
        // was unlucky, which is the rule the writer path follows too.
        guard !isCancelled else {
            fail(Exporter.ExportError.cancelled)
            return
        }
        guard CGImageDestinationFinalize(sink) else {
            fail(
                Exporter.ExportError.failed(
                    "The \(format.displayName) could not be written."))
            return
        }
        report(.success(destination))
    }

    /// Renders one frame and hands it to ImageIO. Returns the error that
    /// stopped the export, or nil when the frame is in.
    ///
    /// A frame that will not render fails the whole export rather than being
    /// skipped. Skipping would leave an animation shorter than the range with
    /// no sign of which moment went missing, and every frame that renders in
    /// the preview renders here — the two go through the same composition —
    /// so a nil is a real failure worth reporting.
    private func append(at time: Ticks) -> (any Error)? {
        let rendered = Exporter.renderFrameReported(
            project: project, urls: urls, at: time, maxWidth: Int(frameSize.width),
            options: options, graphics: graphics)
        // A graphic that failed drew its error card; the frame is not written
        // and `fail` removes the file.
        if let failure = rendered.graphics.first(where: { $0.failed }) {
            return Exporter.graphicFailed(failure)
        }
        guard let image = rendered.image else {
            let timecode = ReelTime.format(time, fps: fps, frames: true)
            return Exporter.ExportError.failed(
                "The frame at \(timecode) could not be rendered, so the "
                    + "\(format.displayName) was not written.")
        }
        let frame = format.carriesLabel ? FrameWriter.labelled(image) : image
        CGImageDestinationAddImage(sink, Self.sized(frame, to: frameSize), frameProperties)
        return nil
    }

    /// Reports a failure, having removed whatever ImageIO may already have
    /// put on disk. A half-written GIF is not a GIF, and `AVAssetWriter`'s
    /// `cancelWriting` removes its own part-file for the same reason.
    private func fail(_ error: any Error) {
        try? FileManager.default.removeItem(at: destination)
        report(.failure(error))
    }

    /// The one exit, main thread, at most once.
    private func report(_ result: Result<URL, any Error>) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let completion = self.completion else { return }
            self.completion = nil
            completion(result)
        }
    }

    // MARK: - Size

    /// `image` drawn into a bitmap of exactly `size`, or `image` itself when
    /// it already is that size.
    ///
    /// The fit — the picture INSIDE the size, aspect kept, never upscaled,
    /// where the movie writer letterboxes — is the core's decision
    /// (`export_size.rs`, spec §7.8) and `settings.width` × `height` is its
    /// answer; this only makes the frame that size. `renderFrame` is asked
    /// for that width and the generator's own fit lands within a pixel of
    /// it, so the draw is a hair's scale and never a crop. A context that
    /// cannot be made — no memory — falls back to the frame as rendered,
    /// which is a pixel off rather than nothing.
    private static func sized(_ image: CGImage, to size: CGSize) -> CGImage {
        let width = max(1, Int(size.width)), height = max(1, Int(size.height))
        if image.width == width && image.height == height { return image }
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
