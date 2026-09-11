import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The await-free half of `MediaImporter`: the refusal type, the still-image
/// question, the ImageIO probe of a still, and the rate table
/// `rationalFrameRate` rounds a track's float onto. Nothing here touches
/// AVFoundation's loading API — every `await` is in `MediaImporter.swift`,
/// the one file that may (app/CLAUDE.md) — and every member keeps its
/// `MediaImporter.` spelling at every call site, so the cut is invisible from
/// outside: it exists because road map 3's held tail took the base file over
/// the ~600-line cap, and the members that owe nothing to the seam are the
/// ones that could leave. `MediaCacheFiles.swift` is the same shape for the
/// cache half.
extension MediaImporter {

    // MARK: - Errors

    /// Import refusals. Every one is shown in an alert and never crashes;
    /// `unreadable` is also what a relink of a moved file reports.
    enum ImportError: LocalizedError {
        case unreadable(URL)
        case noTracks(URL)
        case timedOut(URL)

        var errorDescription: String? {
            switch self {
            case .unreadable(let url):
                return "Could not read \(url.lastPathComponent)."
            case .noTracks(let url):
                return "\(url.lastPathComponent) has no video or audio the app can open."
            case .timedOut(let url):
                return "Timed out reading \(url.lastPathComponent)."
            }
        }

        /// Whether a user-installed ffmpeg is worth offering (`FFmpegRewrap`).
        ///
        /// `unreadable` is the one that matters: AVFoundation answers a
        /// Matroska or a WebM with `AVFoundationErrorDomain -11828 "Cannot
        /// Open"` on the *container*, before it has looked at the codecs
        /// inside, so a plain H.264 recording in an `.mkv` lands here and is
        /// one stream copy away from importing. `noTracks` is included
        /// because a container AVFoundation half-understands can report a
        /// duration and no tracks; `FFmpegRewrap.plan` refuses a file that
        /// genuinely has no video and no audio, so a truly empty one keeps
        /// this message. `timedOut` is not: a stalled network mount will
        /// stall ffmpeg too, and the second wait is not a kindness.
        var invitesFFmpeg: Bool {
            switch self {
            case .unreadable, .noTracks: return true
            case .timedOut: return false
            }
        }
    }

    // MARK: - Stills

    /// Still-image types ImageIO decodes and AVFoundation would refuse.
    /// Probed with ImageIO and imported as `kind: image` (§7.7).
    static let imageTypes: [UTType] = [.png, .jpeg, .heic, .heif, .tiff, .gif, .bmp, .webP]

    /// Whether `url` is a still picture rather than a movie. Type-based, not
    /// extension-based, so a `.heic` written by a camera and a `.jpeg` with
    /// no extension both land in the same branch.
    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return imageTypes.contains { type.conforms(to: $0) }
    }

    /// ImageIO's view of a still: pixel size, and alpha from the file's own
    /// properties. Duration 0 — an `image` clip has no source bound and any
    /// duration (§5.2).
    static func probeImage(_ url: URL) throws -> MediaDescriptor {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            CGImageSourceGetCount(source) > 0,
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            throw ImportError.unreadable(url)
        }
        let width = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        guard width > 0, height > 0 else { throw ImportError.unreadable(url) }
        let hasAlpha = (props[kCGImagePropertyHasAlpha] as? Bool) ?? false
        // `hasVideo` is true for a still: it contributes pixels, so
        // `enabled.video` means something on its clips. It still gets NO
        // composition track — the recipe names an image layer `image`, not
        // `track` (§7.2), and the plan never lists it.
        return MediaDescriptor(
            path: url.path, bookmark: bookmarkString(for: url), kind: .image, duration: 0,
            width: width, height: height, fps: .thirty, hasVideo: true, hasAudio: false,
            hasAlpha: hasAlpha)
    }

    // MARK: - Rates

    /// The rates a container is allowed to round: the integer rates and the
    /// three NTSC /1001 rates (§7.7). Anything else keeps three decimals as
    /// `[round(fps × 1000), 1000]`, which is exact enough to place source
    /// frames and never pretends a 47.3 fps screen recording is 48.
    static let commonRates: [Fps] = [
        Fps(num: 24, den: 1), Fps(num: 24000, den: 1001), Fps(num: 25, den: 1),
        Fps(num: 30, den: 1), Fps(num: 30000, den: 1001), Fps(num: 48, den: 1),
        Fps(num: 50, den: 1), Fps(num: 60, den: 1), Fps(num: 60000, den: 1001),
    ]

    /// Tolerance for that match, in frames per second. 0.01 is wide enough
    /// for a float's error at 60 fps and narrower than the 0.03 gap between
    /// 29.97 and 30 — the pair this must never confuse.
    static let rateTolerance = 0.01

    static func rationalFrameRate(_ nominal: Double) -> Fps {
        guard nominal.isFinite, nominal > 0 else { return .thirty }
        for candidate in commonRates where abs(candidate.double - nominal) <= rateTolerance {
            return candidate
        }
        return Fps(num: Int((nominal * 1000).rounded()), den: 1000)
    }
}
