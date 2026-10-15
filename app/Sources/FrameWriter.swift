import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One composed frame written to a file: a `CGImage` and a format in, a URL
/// out (road map 2 phase 7a).
///
/// It is `AudioNormalize.swift`'s shape applied to pictures, and it is a value
/// type for the same reason that one is. **File ▸ Save Frame… and the agent's
/// `render_frame` call this and nothing else**, so "Save Frame's PNG is
/// byte-identical to `render_frame`'s" is a fact about the code rather than a
/// claim in a comment — and it is the only way the line can ever be checked,
/// because a save panel cannot be driven over MCP or offscreen and a proof
/// script can therefore never press the menu item. Anything that goes in here
/// changes both paths at once; anything that lives in only one of them is a
/// place the two can drift.
///
/// So there is deliberately **no `NSSavePanel`, no `ProjectDocument` and no
/// AppKit view in this file**. Picking the URL is
/// `EditorViewController+SaveFrame.swift`'s job and naming a temporary file is
/// `AgentServer+Render.swift`'s; both hand the result here.
///
/// **PNG's properties dictionary is `nil`, and it must stay `nil`.** That is
/// what `render_frame` has always passed (`AgentServer+Render.swift`), and
/// every phase from 1 to 6 compares PNG bytes against frames written that
/// way. Anything that ADDS metadata changes the file: phase 7's proof
/// mutated this to `[kCGImagePropertyDPIWidth: 144]` and caught it by the
/// extra `pHYs` chunk.
///
/// The honest limit, measured rather than assumed, because the sentence
/// above invites a stronger claim than the platform supports: on macOS
/// 26.5.1 an EMPTY dictionary and no dictionary write byte-identical PNGs
/// (same sha256, same 5330 bytes, same chunk list, across two processes).
/// So no BYTE comparison can catch `[:]` here — but the rule is not
/// unguarded, and saying it was would send the next reader looking for a
/// check that exists: `phase7_chrome.py` reads `destinationProperties != nil`
/// STRUCTURALLY through the probe, which is what an empty dictionary fails
/// and a byte comparison cannot. That is a fact about this ImageIO, not a
/// licence — the rule stays `nil`, because the next ImageIO owes us nothing
/// and the failure would then arrive as a rendering change in five scripts
/// at once.
///
/// **JPEG flattens onto BLACK, and it says so out loud.** JPEG is the one of
/// the three containers that cannot carry an alpha channel at all, and phase
/// 7b makes a transparent canvas reachable in this very phase — so a person
/// who has just set the canvas to Transparent and saves a JPEG would otherwise
/// get whatever ImageIO happens to do with the premultiplied pixels, silently.
/// Black is the choice rather than white because black is what the preview
/// well and the exported movie already show behind the canvas: the still then
/// matches the picture the person was looking at when they asked for it. The
/// flatten belongs to JPEG ALONE — PNG and HEIC both carry alpha, so nothing
/// is thrown away in those two, and adding a flatten to them would destroy
/// information the format was chosen for. The panel's hint carries the same
/// sentence, because a silent flatten is the thing being avoided. JPEG is
/// also the one that holds 8 bits a component whatever it is handed, which is
/// why `Format.carriesDepth` is false for it alone and no frame grabbed for a
/// JPEG is read through the reader (spec §11 PR-9).
///
/// **The quality is 0.9, not `MediaImporter.writeJPEG`'s 0.7.** Those two
/// numbers answer different questions: a filmstrip thumbnail is 54 px tall and
/// is discarded when the cache is cleared, while this is a delivery still
/// somebody is about to put in a document. Neither number is a compromise
/// between the two, which is why they are written down separately rather than
/// shared through a constant.
enum FrameWriter {

    // MARK: - The formats

    /// The three containers Save Frame writes, each declaring everything that
    /// is true of it in ONE place: its type, the extension a file of it takes,
    /// what a menu calls it, and whether it can hold an alpha channel.
    ///
    /// The `rawValue` is a stable identifier for the agent's vocabulary and is
    /// deliberately NOT the file extension — JPEG's are "jpeg" and "jpg" and
    /// collapsing them would make one of the two wrong. `format(for:)` reads
    /// both spellings back.
    ///
    /// `UTType.heic` and not `public.heif`: only the former is in
    /// `CGImageDestinationCopyTypeIdentifiers()` on macOS 15, so a destination
    /// created for the latter is nil and the write fails at the last moment
    /// with nothing to say. Measured, not assumed.
    enum Format: String, CaseIterable {
        case png
        case jpeg
        case heic

        var contentType: UTType {
            switch self {
            case .png: return .png
            case .jpeg: return .jpeg
            case .heic: return .heic
            }
        }

        /// The extension a file of this format takes. One spelling per
        /// format: the panel writes it, `destinationURL` replaces with it and
        /// `format(for:)` reads every accepted spelling back to it.
        var fileExtension: String {
            switch self {
            case .png: return "png"
            case .jpeg: return "jpg"
            case .heic: return "heic"
            }
        }

        /// Every spelling of this format's extension the app READS — one
        /// each, and JPEG's two, `fileExtension` first.
        ///
        /// It is the vocabulary and not just a list: `format(for:)` reads a
        /// name with it and the save panel's format popup decides with it
        /// which trailing dot-suffix is an EXTENSION it may replace and which
        /// is part of a name somebody typed. Those two questions have one
        /// answer and now have one home.
        var acceptedExtensions: [String] {
            switch self {
            case .png: return ["png"]
            case .jpeg: return ["jpg", "jpeg"]
            case .heic: return ["heic"]
            }
        }

        /// What a popup row and a message call it.
        var displayName: String {
            switch self {
            case .png: return "PNG"
            case .jpeg: return "JPEG"
            case .heic: return "HEIC"
            }
        }

        /// True where the container can hold an alpha channel — which is the
        /// whole of the flatten rule: the one format that cannot is the one
        /// format that gets a black backdrop.
        var carriesAlpha: Bool {
            switch self {
            case .png, .heic: return true
            case .jpeg: return false
            }
        }

        /// The one line the save panel shows under the format popup. Every
        /// row gets one rather than only JPEG: a note that appears for one
        /// choice reads as a warning about that choice, where the fact worth
        /// carrying is that the three rows differ about alpha at all — which
        /// is what somebody who has just set the canvas to Transparent
        /// (phase 7b) needs to know before they pick, not after.
        var alphaNote: String {
            carriesAlpha
                ? "\(displayName) keeps the canvas's alpha channel."
                : FrameWriter.flattenNote
        }

        /// The properties dictionary handed to `CGImageDestinationAddImage`,
        /// and `nil` for PNG on purpose (see the type's doc): PNG is lossless,
        /// there is nothing to ask it for, and the byte-identity every earlier
        /// phase's proof depends on is identity with a nil dictionary.
        var destinationProperties: CFDictionary? {
            switch self {
            case .png:
                return nil
            case .jpeg, .heic:
                return [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
            }
        }
    }

    /// The lossy quality both lossy rows are written at. A delivery still, not
    /// a thumbnail — see the type's doc for why this is 0.9 and
    /// `MediaImporter.writeJPEG`'s is 0.7.
    static let quality = 0.9

    /// The one sentence the panel and any message about JPEG says, kept here
    /// beside the behaviour it describes so the two cannot drift.
    static let flattenNote =
        "JPEG has no alpha channel: a transparent canvas is flattened onto black."

    // MARK: - Failures

    /// Failures name the PATH, never a bare `false`. A frame grab that
    /// answered only "no" would leave a person guessing between a folder they
    /// cannot write, a format this Mac's ImageIO does not know and an encoder
    /// that gave up — three different things to do about it.
    ///
    /// **So the first two are two CASES and not one sentence**, and the
    /// review is what settled it: `CGImageDestinationCreateWithURL` answers
    /// nil for both, and a single message asserting the format was the wrong
    /// one of the three for the case a caller actually hits. Measured here
    /// (macOS 26.5.1): it answers nil for `/card.png`, for
    /// `/private/var/db/x.png`, for `/System/nowhere/card.png` and for a
    /// path that is an existing directory — every one of them a PNG this Mac
    /// writes perfectly, and the agent reaches all four, because
    /// `render_frame` takes a caller's path and a launched `.app`'s working
    /// directory is `/`. Telling somebody to go looking for a missing
    /// encoder when the answer is a folder they cannot write is worse than
    /// saying nothing.
    enum WriteError: LocalizedError {
        /// `CGImageDestinationCreateWithURL` answered nil for a type this
        /// machine's ImageIO does not WRITE. Decided by asking
        /// `CGImageDestinationCopyTypeIdentifiers()`, which is a question
        /// about the machine and carries no URL in it.
        case unsupported(Format, URL)
        /// `CGImageDestinationCreateWithURL` answered nil for a type this
        /// machine DOES write, so what it could not do is create the file:
        /// a folder that is not there, one this app may not write into, a
        /// read-only or absent volume, or a path that is itself a directory.
        /// ImageIO tells those apart nowhere, so the message names the CLASS
        /// and asks the two questions a person can answer, rather than
        /// inventing a cause. The agent is the caller that reaches it — an
        /// `NSSavePanel` choice confers access to the URL it returns even for
        /// an unsandboxed app, so Save Frame reaches it only where the volume
        /// or the folder went away between the panel and the write.
        case unwritable(Format, URL)
        /// The opaque bitmap the JPEG flatten draws into could not be made.
        case flattenFailed(URL)
        /// `CGImageDestinationFinalize` answered false.
        case encodingFailed(Format, URL)

        var errorDescription: String? {
            switch self {
            case .unsupported(let format, let url):
                return "Could not write \(format.displayName) to \(url.path). "
                    + "This Mac's image encoders do not offer that format."
            case .unwritable(let format, let url):
                return "Could not write \(format.displayName) to \(url.path). "
                    + "The file could not be created there — check that the folder exists "
                    + "and that Frame Job is allowed to write into it."
            case .flattenFailed(let url):
                return "Could not flatten the frame onto black for \(url.path)."
            case .encodingFailed(let format, let url):
                return "\(format.displayName) encoding failed for \(url.path)."
            }
        }
    }

    /// Which of the two nil-destination failures happened, asked the only way
    /// ImageIO answers it: `CGImageDestinationCopyTypeIdentifiers()` is the
    /// list of types this machine WRITES, so a format on that list did not
    /// fail for being unknown and the URL is what is left.
    ///
    /// It runs only on the failure path, so the ordinary write pays nothing
    /// for it; and it probes no file — `isWritableFile(atPath:)` answers a
    /// permission bit, which is not the question when the refusal is TCC's or
    /// the parent is missing, and a probe write would be a second way to
    /// create the very file being reported.
    private static func destinationFailure(_ format: Format, _ url: URL) -> WriteError {
        let writable = (CGImageDestinationCopyTypeIdentifiers() as NSArray as? [String]) ?? []
        return writable.contains(format.contentType.identifier)
            ? .unwritable(format, url)
            : .unsupported(format, url)
    }

    // MARK: - Reading a format off a name

    /// The format `url` names, or `requested` when a caller has said. Both
    /// spellings of JPEG read back to one case; anything unrecognised is PNG,
    /// which is the row that loses nothing.
    ///
    /// It is `CaptionExporter.format(for:requested:)` verbatim in shape, and
    /// for that function's reason: the panel and the agent both end here, so
    /// "what did this path ask for" is answered once.
    ///
    /// The spellings read here are exactly the ones in
    /// `AgentServer.replaceableExtensions`, and they have to be: a name this
    /// app never writes is part of the NAME rather than an extension (that
    /// set's own rule), so recognising a spelling here that the set does not
    /// replace would turn `shot.heif` into `shot.heif.heic` — the doubled name
    /// the whole mechanism exists to prevent. `heif` is the one that tempts,
    /// and it is left out on both sides together.
    static func format(for url: URL, requested: Format? = nil) -> Format {
        if let requested = requested { return requested }
        let suffix = url.pathExtension.lowercased()
        return Format.allCases.first { $0.acceptedExtensions.contains(suffix) } ?? .png
    }

    /// Every extension this app writes a still under, lower-cased — the union
    /// of the three formats' `acceptedExtensions`. `renamed` is the caller and
    /// carries the argument for having a set at all.
    static let knownExtensions = Set(Format.allCases.flatMap { $0.acceptedExtensions })

    /// A save panel's name field rewritten for a newly chosen format: the
    /// stem it already holds, then that format's extension. `fallback` is
    /// what an empty field falls back to.
    ///
    /// **Only a suffix this app WRITES is an extension**, and the rest of the
    /// name is the person's. `deletingPathExtension` takes whatever follows
    /// the last dot whatever it is, so the format popup used to turn
    /// `Board v1.2` into `Board v1.jpg` — eating a character somebody typed
    /// on purpose while doing exactly what it was told. That is the same
    /// hazard `AgentServer.destinationURL` avoids for that same name — it
    /// strips only a member of `replaceableExtensions` and APPENDS otherwise,
    /// so `Board v1.2` over MCP is written as `Board v1.2.png` and always
    /// was; `knownExtensions` is this side's half of the one rule.
    /// Measured: `("Board v1.2" as NSString).deletingPathExtension` is
    /// "Board v1", and `("shot.final" as NSString)`'s is "shot".
    ///
    /// It is a function of a string and lives HERE rather than in the panel
    /// for the reason `write` does: an accessory view's private method is
    /// reachable by no proof this project can write, because a save panel
    /// cannot be driven over MCP or offscreen — so a rule kept there is a
    /// rule nothing can check. As a pure function a probe compiled from
    /// `app/Sources` calls it with a table of names (`AudioNormalize.swift`'s
    /// argument, and `CaptionCues`') — `tools/proof/remaining_probe.py`,
    /// section 1, the first instrument to have actually done so.
    static func renamed(_ name: String, as format: Format, fallback: String) -> String {
        let suffix = (name as NSString).pathExtension.lowercased()
        let stem =
            knownExtensions.contains(suffix)
            ? (name as NSString).deletingPathExtension : name
        return "\(stem.isEmpty ? fallback : stem).\(format.fileExtension)"
    }

    // MARK: - Writing

    /// Writes `image` to `url` and answers the URL it wrote. The caller owns
    /// the path — this creates no folders and replaces no extension, because
    /// the two callers disagree about both (the panel has already asked a
    /// person, and the agent runs its path through
    /// `AgentServer.destinationURL`).
    @discardableResult
    static func write(_ image: CGImage, as format: Format, to url: URL) throws -> URL {
        let subject = format.carriesAlpha ? image : try flattenedOntoBlack(image, for: url)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, format.contentType.identifier as CFString, 1, nil)
        else {
            throw destinationFailure(format, url)
        }
        CGImageDestinationAddImage(destination, subject, format.destinationProperties)
        guard CGImageDestinationFinalize(destination) else {
            throw WriteError.encodingFailed(format, url)
        }
        return url
    }

    /// `image` composited over black in an OPAQUE bitmap — the JPEG flatten.
    ///
    /// It is a real draw rather than a hint to the encoder because there is no
    /// such hint: handed premultiplied pixels with alpha, a JPEG destination
    /// simply drops the alpha channel, which leaves a half-transparent white
    /// title composited as mid-grey and a fully transparent canvas as black
    /// anyway — the right answer in one case and a wrong one in the other, with
    /// no way to tell them apart afterwards. Compositing first makes every
    /// pixel the same arithmetic the compositor and the exported movie already
    /// do against their black ground.
    ///
    /// It runs for EVERY JPEG, including a frame that carries no alpha at all.
    /// Short-circuiting an opaque source would be one branch and one saved
    /// copy, and it would buy a second way for a JPEG to be produced — a
    /// direct encode whose colour handling need not match the drawn one's, on
    /// a path nothing measures. One path per format is worth a full-frame
    /// draw at the speed a person presses a menu item.
    ///
    /// Eight bits a component, deliberately: JPEG has no more, so a frame from
    /// a 10-bit source (which `render_frame` writes as 16-bit float from a
    /// ProRes or HEVC Main 10 clip) is truncated here rather than at some
    /// later point where it would look like a rendering difference. The colour space is the image's own where it is
    /// an RGB one, so the flatten changes coverage and nothing else; a source
    /// in any other model falls back to device RGB, which is the only thing
    /// `noneSkipLast` can be built over.
    private static func flattenedOntoBlack(_ image: CGImage, for url: URL) throws -> CGImage {
        let space: CGColorSpace = {
            if let own = image.colorSpace, own.model == .rgb { return own }
            return CGColorSpaceCreateDeviceRGB()
        }()
        guard image.width > 0, image.height > 0,
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else {
            throw WriteError.flattenFailed(url)
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(rect)
        context.draw(image, in: rect)
        guard let flattened = context.makeImage() else {
            throw WriteError.flattenFailed(url)
        }
        return flattened
    }
}

extension FrameWriter {
    /// The BT.709 label every rendered frame's file carries (spec §11 PR-11):
    /// the space `CVImageBufferCreateColorSpaceFromAttachments` makes of the
    /// BT.709 primaries, transfer function and matrix — the space the
    /// generator already gives a frame of a BT.709-tagged source,
    /// `kCGColorSpaceCoreMedia709` — else `CGColorSpace.itur_709`.
    static let frameSpace: CGColorSpace = {
        let attachments =
            [
                kCVImageBufferColorPrimariesKey: kCVImageBufferColorPrimaries_ITU_R_709_2,
                kCVImageBufferTransferFunctionKey: kCVImageBufferTransferFunction_ITU_R_709_2,
                kCVImageBufferYCbCrMatrixKey: kCVImageBufferYCbCrMatrix_ITU_R_709_2,
            ] as CFDictionary
        return CVImageBufferCreateColorSpaceFromAttachments(attachments)?.takeRetainedValue()
            ?? CGColorSpace(name: CGColorSpace.itur_709)!
    }()

    /// `image` labelled `frameSpace`, its pixels untouched; `image` itself
    /// when the copy cannot be made.
    static func labelled(_ image: CGImage) -> CGImage {
        image.copy(colorSpace: frameSpace) ?? image
    }

    /// `write(labelled(image), as: format, to: url)`: the one writer of
    /// `render_frame` and File ▸ Save Frame… (PR-11). `write` itself stays
    /// unlabelled for `snapshot_ui`, `render_graphic`'s sheets and the look
    /// gallery's tiles.
    @discardableResult
    static func writeFrame(_ image: CGImage, as format: Format, to url: URL) throws -> URL {
        try write(labelled(image), as: format, to: url)
    }
}

extension FrameWriter.Format {
    /// True where the container keeps more than 8 bits a component — PNG
    /// (16-bit) and HEIC — so a frame grabbed for it is read through the reader
    /// when it shows a deep still or a deep VP9 track (`DeepVideoFrame`, spec
    /// §11 PR-9, PR-12); JPEG is 8-bit, so its frame is built exactly as before.
    var carriesDepth: Bool {
        switch self {
        case .png, .heic: return true
        case .jpeg: return false
        }
    }
}
