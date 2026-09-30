import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The await-free half of `MediaImporter`: the refusal type, the still-image
/// question, the ImageIO probe of a still, and the rate table
/// `rationalFrameRate` rounds a track's float onto. It also holds the
/// probe's synchronous faces (`probe(url:completion:)`, `probeAllowingRewrap`,
/// `probeBlocking`), which wait through `waitForProbe`. Nothing here touches
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

    // MARK: - The synchronous faces

    /// The queue the completion-handler face probes on. A serial queue, not
    /// the cooperative pool: a conversion (`FFmpegRewrap`) blocks its thread
    /// for as long as ffmpeg runs, which is exactly what a cooperative
    /// thread must never do, and serialising means a batch drop of four
    /// unreadable files asks four questions in order rather than stacking
    /// four alerts. `app/CLAUDE.md` names import as one of the documented
    /// `DispatchQueue` seams.
    private static let importQueue = DispatchQueue(
        label: "com.kgalligan.reelcut.import", qos: .userInitiated)

    /// The synchronous face of `probe` for the rest of the app: the result
    /// arrives on the main thread, so the caller can go straight to
    /// `add_media` + `add_clip` without ever writing `await`.
    static func probe(
        url: URL, completion: @escaping (Result<MediaDescriptor, any Error>) -> Void
    ) {
        importQueue.async {
            let outcome = Result { try probeAllowingRewrap(url) }
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    /// The AVFoundation probe plus spec §11's opt-in ffmpeg step, and the
    /// body of both synchronous faces.
    ///
    /// The two halves are deliberately not nested inside `probe(url:)`.
    /// `waitForProbe` puts a 30-second ceiling on AVFoundation, which is
    /// right for reading headers and catastrophically wrong for a transcode;
    /// `FFmpegRewrap.assist` therefore runs OUTSIDE it, unbounded, and its
    /// result is probed with a fresh ceiling of its own. `assist` also needs
    /// the main thread for its consent alert, which it can only have because
    /// this function's callers are never the thread being waited on.
    ///
    /// Every one of the four import paths funnels through here — document
    /// open (`ProjectDocument.readMediaFile`), File ▸ Add Media… and Finder
    /// drops (`ProjectDocument.probeNext`), and the agent's `import_media`
    /// (`AgentServer+Media.probe`) — so an MKV opens the same way in all of
    /// them, and `assist` answering `nil` leaves all four with exactly the
    /// failure they report on a machine that has no ffmpeg.
    ///
    /// **Known cost of the document-open path.** Three of those four callers
    /// are already off the main thread, so ffmpeg runs with the UI live. The
    /// fourth, `read(from:ofType:)`, is *allowed* to run on main (its own
    /// comment says NSDocumentController does not always take the concurrent
    /// read queue), and there it blocks: opening a WebM straight from the
    /// Finder can beachball for the length of the encode. The consent alert
    /// states the cost first, which is the mitigation available from here —
    /// a progress sheet would need a seam in `ProjectDocument`, which owns
    /// the sheet-presenting side of every long operation.
    private static func probeAllowingRewrap(_ url: URL) throws -> MediaDescriptor {
        do {
            return try waitForProbe(url)
        } catch let failure as ImportError where failure.invitesFFmpeg && !isImage(url) {
            // Images are excluded because ImageIO's refusal means the picture
            // is corrupt, not that the container is exotic — and a PNG is not
            // something to hand to a video converter.
            guard let rewrapped = try FFmpegRewrap.assist(url) else { throw failure }
            do {
                return try waitForProbe(rewrapped)
            } catch {
                // ffmpeg wrote a file AVFoundation still will not open. The
                // conversion is cached by name, so leaving it there would
                // hand the same broken result back for ever; throwing it away
                // makes the next attempt a real attempt. The error reported
                // is the ORIGINAL one, because the file the user chose is the
                // one they are being told about.
                FFmpegRewrap.discard(rewrapped)
                throw failure
            }
        }
    }

    /// The BLOCKING face of `probe`, for `ProjectDocument.read(from:ofType:)`.
    ///
    /// That method is synchronous by contract and CAN run on the main thread
    /// — NSDocumentController's open path does not always take the concurrent
    /// read queue, and every agent tool call hops to main before it opens
    /// anything. So this must never wait on the main actor. The obvious
    /// spelling (a completion delivered through `MainActor.run`, joined with
    /// a `DispatchGroup`) deadlocks exactly there: the waiter is holding the
    /// one thread the completion needs, and the open dies on the timeout
    /// instead of the file. Here the work runs on the cooperative pool and
    /// the result comes back through a plain semaphore, so the waiting thread
    /// is never the thread being waited on.
    static func probeBlocking(url: URL) throws -> MediaDescriptor {
        try probeAllowingRewrap(url)
    }
}
