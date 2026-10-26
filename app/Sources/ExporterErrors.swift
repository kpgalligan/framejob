import AVFoundation

extension Exporter {

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
        /// This Mac will not encode what the core's preset resolved to — an
        /// unknown codec name, one `AVAssetWriter` refuses an input for, or
        /// one whose encoder is not found when the write starts
        /// (`Exporter.encoderOutcome`). Carries the preset id when the core
        /// gave one, else the codec.
        case presetUnavailable(String)
        /// The settings named a container this build cannot map to a file
        /// type.
        case fileTypeUnsupported(String)
        /// An alpha-carrying row was asked for a size of a different SHAPE
        /// from the canvas, which cannot be written correctly and so is not
        /// written at all (road map 2, phase 7b). Carries the canvas and the
        /// size the core resolved, in that order.
        ///
        /// **Which sizes reach it** (spec §11 G-33 (c)): on `prores_4444` and
        /// `hevc_alpha`, a frame more than a pixel off the canvas's shape
        /// (`ExportWriter.shapeGap`: `gap > limit`). A frame within a pixel is
        /// filled instead of padded and is written — the evened Document row
        /// on a canvas with an odd edge, a standard row whose long edge
        /// rounded, a size typed in the canvas's own proportions (evened
        /// first on `hevc_alpha`, so an odd one is written a pixel smaller),
        /// and on `prores_4444` a typed frame one pixel short. So no size of
        /// the canvas's shape is refused for being odd; a typed size of any
        /// other shape is judged as the even frame it becomes
        /// (1279 × 720 on 1920 × 1080 is 1278 × 720 on `hevc_alpha`, and
        /// refused).
        ///
        /// **Measured, not feared.** `AVVideoScalingModeResizeAspect` pads
        /// the frame to the asked-for shape, and the padding path destroys
        /// the alpha channel: a 320 × 180 transparent canvas written
        /// `prores_4444` at 240 × 240 comes back with the PICTURE at alpha 0
        /// and the letterbox BARS at alpha 255 — the answer inverted, not
        /// merely lost. The same canvas at 160 × 90 or 640 × 360 is correct
        /// at every pixel, so the fault is the padding and nothing else.
        ///
        /// It is refused rather than documented because the file would be
        /// silently wrong in the one respect the row exists for, and this
        /// codebase's rule for exactly that shape is `codecType(for:)`'s:
        /// a refusal, never a fallback that puts a file on disk which is not
        /// the one asked for. Nothing legitimate is blocked by accident —
        /// every row of the Size popup is fitted to the document's own
        /// aspect (`export_size.rs`), so only a hand-typed Custom size of
        /// another shape can reach this (or a canvas, or a typed size, with
        /// an edge of exactly 1 px, raised to 2 on `hevc_alpha`), and the
        /// message says what to type instead: every size with the canvas's
        /// proportions is written, odd or even, smaller or larger.
        case alphaAspectMismatch(width: Int, height: Int, wantWidth: Int, wantHeight: Int)
        /// The user pressed Cancel. The sheet dismisses without an alert.
        case cancelled
        /// The write ended in a state that is neither completed nor
        /// cancelled and had no error of its own — or one of the reader's or
        /// writer's own steps refused with a message worth showing.
        case failed(String)
        /// Graphic clips in the range whose module does not compile, or is
        /// not in `graphics/`, each with what is wrong: the export was refused
        /// before it started (G-8). Sorted by name.
        case graphicsNotCompiled([(name: String, message: String)])
        /// A graphic failed while the export drew it, at its own frame — nil
        /// when it did not compile. The export stopped and its file is gone.
        case graphicFailed(name: String, frame: Int?, message: String)
        /// A ramped clip's audio render failed (spec §11 SR-12 (g), (h)): the
        /// export waits for every ramp segment it plays and never writes one
        /// silent, so it stops, naming the clip and the renderer's reason.
        case rampAudioFailed(clip: UInt32, message: String)

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
            case .alphaAspectMismatch(let width, let height, let wantWidth, let wantHeight):
                return "An export that keeps transparency has to have the canvas's own shape. "
                    + "This canvas is \(width) × \(height) and \(wantWidth) × \(wantHeight) is a "
                    + "different shape, so the picture would be padded and the padding loses the "
                    + "alpha channel. Export at \(width) × \(height), at one of the sizes in the "
                    + "popup, or at any size with the same proportions."
            case .cancelled:
                return "The export was cancelled."
            case .failed(let message):
                return message
            case .graphicsNotCompiled(let refused):
                let clauses = refused.map { "the graphic \"\($0.name)\" \($0.message)" }
                return "The export was not started: " + clauses.joined(separator: "; ")
                    + ". Fix the module and export again."
            case .graphicFailed(let name, let frame?, let message):
                return "The export was stopped at frame \(frame) of the graphic \"\(name)\": "
                    + "\(message). No file was written."
            case .graphicFailed(let name, nil, let message):
                return "The export was stopped: the graphic \"\(name)\" does not compile — "
                    + "\(message). No file was written."
            case .rampAudioFailed(let clip, let message):
                return "Clip \(clip)'s retimed audio could not be rendered: \(message)."
            }
        }
    }

    /// What a finished write becomes when the reason it failed is that this
    /// Mac has no encoder for the row (spec §11 G-33 (e)): the preset's own
    /// sentence, and no file.
    ///
    /// `ExportWriter.addVideo` cannot see it. Measured with an encoder
    /// specification nothing satisfies, on `.hevcWithAlpha` and `.hevc`
    /// alike: `canApply` is true, the input constructs, `canAdd` is true, and
    /// `startWriting()` then fails with `AVFoundationErrorDomain` −11834
    /// ("Cannot Encode"), leaving a 0-byte file at the destination. So it is
    /// mapped here, where `startWriting` hears the pipeline: exactly that
    /// domain and code become `.presetUnavailable` with the preset's name and
    /// the file is removed, and every other result is returned as it came.
    static func encoderOutcome(
        _ result: Result<URL, any Error>, settings: ExportSettings, destination: URL
    ) -> Result<URL, any Error> {
        guard case .failure(let error) = result else { return result }
        let reason = error as NSError
        guard reason.domain == AVFoundationErrorDomain,
            reason.code == AVError.Code.encoderNotFound.rawValue
        else { return result }
        try? FileManager.default.removeItem(at: destination)
        return .failure(ExportError.presetUnavailable(ExportWriter.presetName(settings)))
    }
}
