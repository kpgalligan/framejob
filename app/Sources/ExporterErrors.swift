import Foundation

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
        /// unknown codec name, or one `AVAssetWriter` refuses an input for.
        /// Carries the preset id when the core gave one, else the codec.
        case presetUnavailable(String)
        /// The settings named a container this build cannot map to a file
        /// type.
        case fileTypeUnsupported(String)
        /// An alpha-carrying row was asked for a size of a different ASPECT
        /// from the canvas, which cannot be written correctly and so is not
        /// written at all (road map 2, phase 7b). Carries the canvas and the
        /// asked-for size, in that order.
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
        /// aspect (`export_size.rs`), so only a hand-typed Custom size can
        /// reach this, and the message says what to type instead.
        case alphaAspectMismatch(width: Int, height: Int, wantWidth: Int, wantHeight: Int)
        /// The user pressed Cancel. The sheet dismisses without an alert.
        case cancelled
        /// The write ended in a state that is neither completed nor
        /// cancelled and had no error of its own — or one of the reader's or
        /// writer's own steps refused with a message worth showing.
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
            }
        }
    }
}
