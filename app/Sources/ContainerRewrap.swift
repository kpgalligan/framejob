import AVFoundation
import CoreMedia
import VideoToolbox

/// A WebM or Matroska file opened by a built-in rewrap (spec §11 #216-R):
/// the core indexes the container (`ReelContainer`) and its first video and
/// audio streams are copied, unchanged, into a QuickTime movie under
/// `~/Library/Application Support/Reelcut/Rewrapped/`, the folder ffmpeg's
/// conversions use, by `FFmpegRewrap.destination(for:)`'s digest name — so a
/// second import of the same file reuses the copy.
///
/// The order is the decision's: the core opens the file; a codec this Mac
/// cannot decode is refused in #216's sentence BEFORE anything is copied
/// (VP8, AV1 without hardware decode, VP9 Profile 1 or 3), and a codec the
/// copy cannot carry is refused in its own (`unsupported`), which alone
/// falls through to the opt-in ffmpeg step; the video is snapped to its
/// frame grid when it lies on one; the copy's size is checked against the
/// free space first; and the movie is written under a `.partial.mov` name
/// and moved into place, so a failure leaves no file behind.
///
/// Await-free (spec §11 W-8): `ContainerRewrapWriter` waits on its writer
/// through a semaphore.
enum ContainerRewrap {

    /// Whether `url` begins with an EBML header: 1A 45 DF A3.
    static func isMatroska(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 4)) ?? Data()
        return head == Data([0x1A, 0x45, 0xDF, 0xA3])
    }

    /// Held across the existence re-check and the copy, so two imports of one
    /// file copy it once.
    private static let lock = NSLock()

    /// The movie for `source`: a copy already on disk, else a new one.
    /// `watch` is called once, on this thread, when a new copy starts, with
    /// the progress the copy reports to and reads its Cancel from (spec §11
    /// #228-P); a reused copy calls none, and a tool call passes none.
    static func assist(_ source: URL, watch: RewrapWatch? = nil) throws -> URL {
        if let existing = FFmpegRewrap.existingRewrap(of: source) { return existing }
        guard let destination = FFmpegRewrap.destination(for: source) else {
            throw ContainerRewrapError.failed(source, reason: "the copy folder could not be found")
        }
        lock.lock()
        defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        let progress = RewrapProgress(source: source)
        watch?(progress)
        defer { progress.finish() }
        try rewrap(source, to: destination, progress: progress)
        return destination
    }

    /// Copies `source` into a movie at `destination`. `freeBytes` stands in
    /// for the volume's free space, `stopAfter` fails the copy after that
    /// many samples and `refuseAudioAt` has the writer refuse that audio
    /// sample — the three seams the probe drives; the app passes none.
    /// `progress` is told the copy's size and each sample's bytes, and its
    /// Cancel is read after the index opens, before the write and between
    /// samples; a cancelled copy throws `.cancelled` with nothing left.
    static func rewrap(
        _ source: URL, to destination: URL, freeBytes: Int64? = nil, stopAfter: Int? = nil,
        refuseAudioAt: Int? = nil, progress: RewrapProgress? = nil
    ) throws {
        let container: ReelContainer
        do {
            container = try ReelContainer(path: source.path)
        } catch {
            let reason = (error as? ReelCoreError)?.message ?? error.localizedDescription
            throw ContainerRewrapError.unreadable(source, reason: reason)
        }
        if progress?.isCancelled == true { throw ContainerRewrapError.cancelled(source) }
        var description = try describe(container, source)
        if description.video == nil, description.audio == nil {
            throw MediaImporter.ImportError.noTracks(source)
        }
        try precheck(description, source)
        if let nominal = description.video?.nominalFps {
            _ = container.retime(MediaImporter.rationalFrameRate(nominal))
            description = try describe(container, source)
        }
        try checkSpace(for: description, source, at: destination, freeBytes: freeBytes)
        if progress?.isCancelled == true { throw ContainerRewrapError.cancelled(source) }
        do {
            try AppSupport.ensureDirectory(destination.deletingLastPathComponent())
        } catch {
            throw ContainerRewrapError.failed(source, reason: "the copy folder could not be created")
        }
        let manager = FileManager.default
        let partial = destination.deletingPathExtension().appendingPathExtension("partial.mov")
        try? manager.removeItem(at: partial)
        progress?.begin(
            totalBytes: (description.video?.bytes ?? 0) + (description.audio?.bytes ?? 0))
        do {
            try ContainerRewrapWriter.write(
                container, description, from: source, to: partial, stopAfter: stopAfter,
                refuseAudioAt: refuseAudioAt, progress: progress)
            try manager.moveItem(at: partial, to: destination)
        } catch {
            try? manager.removeItem(at: partial)
            if error is ContainerRewrapError { throw error }
            throw ContainerRewrapError.failed(source, reason: error.localizedDescription)
        }
    }

    private static func describe(
        _ container: ReelContainer, _ source: URL
    ) throws -> ContainerDescription {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let description = try? decoder.decode(
            ContainerDescription.self, from: Data(container.describeJSON.utf8))
        else {
            throw ContainerRewrapError.unreadable(source, reason: "its index could not be read")
        }
        return description
    }

    // MARK: - Before the copy

    /// #216's refusals from the codec facts in the Tracks element, then a
    /// codec the copy does not carry.
    private static func precheck(_ d: ContainerDescription, _ source: URL) throws {
        let fileName = source.lastPathComponent
        if let video = d.video, !video.encoded, let fourcc = video.fourcc {
            let codec = fourCharCode(fourcc)
            let av1Hardware = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
            let profile = video.vp9Profile
            let undecodable = fourcc == "vp08"
                || (codec == kCMVideoCodecType_AV1 && !av1Hardware)
                || (codec == kCMVideoCodecType_VP9 && (profile == 1 || profile == 3))
            if undecodable {
                throw MediaImporter.ImportError.undecodable(
                    source,
                    sentence: DecoderSupport.refusal(
                        fileName: fileName, codec: codec, vp9Profile: profile,
                        av1Hardware: av1Hardware))
            }
        }
        let tracks: [(kind: String, codecID: String, fourcc: String?, encoded: Bool)] = [
            d.video.map { ("video", $0.codecId, $0.fourcc, $0.encoded) },
            d.audio.map { ("audio", $0.codecId, $0.fourcc, $0.encoded) },
        ].compactMap { $0 }
        for track in tracks where track.fourcc == nil || track.encoded {
            throw ContainerRewrapError.unsupported(
                source,
                sentence: unsupported(
                    fileName: fileName, kind: track.kind, codecID: track.codecID,
                    encoded: track.encoded))
        }
    }

    /// The free space on the volume the copy goes to, against what the core
    /// says the copy needs. With no reading of the volume, the copy goes on.
    private static func checkSpace(
        for d: ContainerDescription, _ source: URL, at destination: URL, freeBytes: Int64?
    ) throws {
        var folder = destination.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: folder.path), folder.path != "/" {
            folder = folder.deletingLastPathComponent()
        }
        let values = try? folder.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedNameKey, .volumeNameKey,
        ])
        guard let free = freeBytes ?? values?.volumeAvailableCapacityForImportantUsage else {
            return
        }
        let needed = Int64(clamping: d.requiredBytes)
        guard free < needed else { return }
        let volume = values?.volumeLocalizedName ?? values?.volumeName ?? "the disk"
        throw ContainerRewrapError.noSpace(
            source,
            sentence: spaceRefusal(
                fileName: source.lastPathComponent, needed: needed, free: free, volume: volume))
    }

    // MARK: - The sentences

    /// The names a refusal gives a codec it does not copy.
    private static let codecNames: [String: String] = [
        "A_VORBIS": "Vorbis", "A_FLAC": "FLAC", "A_MPEG/L3": "MP3", "A_MPEG/L2": "MP2",
        "A_AC3": "AC-3", "A_EAC3": "E-AC-3", "A_DTS": "DTS", "A_TRUEHD": "TrueHD",
        "V_MPEG2": "MPEG-2", "V_MPEG4/ISO/ASP": "MPEG-4 Part 2", "V_THEORA": "Theora",
        "V_PRORES": "ProRes",
    ]

    static func unsupported(fileName: String, kind: String, codecID: String, encoded: Bool)
        -> String
    {
        let tail = "which Reelcut cannot copy out of a WebM or Matroska file."
        if encoded {
            return "\(fileName) has a compressed or encrypted \(kind) track, \(tail)"
        }
        let name = codecNames[codecID]
            ?? (codecID.hasPrefix("A_PCM/") ? "PCM" : "“\(codecID)”")
        return "\(fileName) has \(name) \(kind), \(tail)"
    }

    static func spaceRefusal(fileName: String, needed: Int64, free: Int64, volume: String)
        -> String
    {
        let need = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
        let left = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
        return "Not enough free space to open \(fileName): its video and sound need about"
            + " \(need) on “\(volume)”, which has \(left) free. Nothing was copied."
    }

    /// A four-character code from its four ASCII letters.
    static func fourCharCode(_ text: String) -> FourCharCode {
        text.utf8.prefix(4).reduce(0) { ($0 << 8) | FourCharCode($1) }
    }
}

/// Why a WebM or Matroska file was not copied. Only `unsupported` invites
/// the opt-in ffmpeg step: the copy cannot carry that codec and ffmpeg may.
enum ContainerRewrapError: LocalizedError {
    case unsupported(URL, sentence: String)
    case noSpace(URL, sentence: String)
    case unreadable(URL, reason: String)
    case failed(URL, reason: String)
    /// The person's Cancel (spec §11 #228-P); never presented.
    case cancelled(URL)

    var errorDescription: String? {
        switch self {
        case .unsupported(_, let sentence), .noSpace(_, let sentence):
            return sentence
        case .unreadable(let url, let reason):
            return "Could not read \(url.lastPathComponent): \(reason)."
        case .failed(let url, let reason):
            return "Could not copy \(url.lastPathComponent) into a movie: \(reason)."
        case .cancelled(let url):
            return "Copying \(url.lastPathComponent) was cancelled."
        }
    }

    var invitesFFmpeg: Bool {
        if case .unsupported = self { return true }
        return false
    }
}

/// `rc_container_describe`'s JSON (the header's keys, read snake_case).
struct ContainerDescription: Decodable {
    struct Video: Decodable {
        let codecId: String
        let fourcc: String?
        let encoded: Bool
        let width: Int
        let height: Int
        let atom: String?
        let atomHex: String?
        let vp9Profile: Int?
        let nominalFps: Double?
        let timescale: Int64
        let grid: Bool
        let samples: Int
        let bytes: UInt64
    }

    struct Audio: Decodable {
        let codecId: String
        let fourcc: String?
        let encoded: Bool
        let sampleRate: Double
        let channels: Int
        let cookieHex: String
        let framesPerPacket: Int
        let timescale: Int64
        let samples: Int
        let bytes: UInt64
    }

    let docType: String
    let requiredBytes: UInt64
    let video: Video?
    let audio: Audio?
}
