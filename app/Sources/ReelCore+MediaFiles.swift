import AppKit

// The media files the core reads or writes — `ReelContainer`, `ReelCube`, `ReelHDR10`,
// `ReelAV1`, `ReelWebM`: a pure move out of `ReelCore.swift` (road map creator-jobs CJ0d, T15).

// MARK: - Containers

/// A WebM or Matroska file's index (`RcContainer`, spec §11 #216-R): its
/// first video and audio track and where each frame's bytes lie, which
/// `ContainerRewrap` copies into a movie. `retime` comes before any sample
/// is read; after it, `count` and `sample` may be called from two threads at
/// once (the writer's two pumps), since neither changes the index.
final class ReelContainer {
    static let video = UInt32(RC_CONTAINER_VIDEO)
    static let audio = UInt32(RC_CONTAINER_AUDIO)
    private let handle: OpaquePointer

    /// Opens and indexes the file; throws the core's lowercase reason.
    init(path: String) throws {
        var err: UnsafeMutablePointer<CChar>? = nil
        guard let made = rc_container_open(path, &err) else {
            throw ReelCoreError(message: takeErrorMessage(err, fallback: "it could not be read"))
        }
        handle = made
    }

    deinit { rc_container_free(handle) }

    /// The header's describe JSON.
    var describeJSON: String { takeString(rc_container_describe(handle)) ?? "{}" }

    /// Snaps the video to `fps`'s grid when it lies on it; true when it did.
    func retime(_ fps: Fps) -> Bool {
        rc_container_retime(handle, Int64(fps.num), Int64(fps.den))
    }

    /// The copied samples of `track`.
    func count(_ track: UInt32) -> Int {
        Int(clamping: rc_container_sample_count(handle, track))
    }

    /// Sample `index` of `track`, in decode order; nil past the count.
    func sample(_ track: UInt32, at index: Int) -> RcContainerSample? {
        guard index >= 0 else { return nil }
        var out = RcContainerSample()
        return rc_container_sample(handle, track, UInt64(index), &out) ? out : nil
    }
}

// MARK: - LUTs

/// A `.cube` 3D LUT read by the core (`RcCube`, spec §11 GR-8), so the import
/// probe and the compositor read one file the same way.
enum ReelCube {
    /// The largest file the core reads; `MediaImporter.readLUT` reads one
    /// byte more, so a larger file is refused in the core's own sentence.
    static let maxBytes = Int(RC_CUBE_MAX_BYTES)

    /// The file's lattice; throws the core's lowercase sentence.
    static func parse(_ data: Data) throws -> CubeLattice {
        var err: UnsafeMutablePointer<CChar>? = nil
        let made = withNonNullBytes(data) { rc_cube_parse($0, $1, &err) }
        guard let cube = made else {
            throw ReelCoreError(message: takeErrorMessage(err, fallback: "it could not be read"))
        }
        defer { rc_cube_free(cube) }
        let size = Int(rc_cube_size(cube))
        var rgb = [Float](repeating: 0, count: size * size * size * 3)
        let copied = rgb.withUnsafeMutableBufferPointer { out in
            out.baseAddress.map { rc_cube_copy_rgb(cube, $0, out.count) } ?? false
        }
        guard size >= 2, copied else {
            throw ReelCoreError(message: "its table could not be read")
        }
        return CubeLattice(size: size, rgb: rgb)
    }
}

// MARK: - HDR10

/// A PQ file's HDR10 peak read by the core (`rc_hdr10_peak`, spec §11 HD-12):
/// the format description's two extensions when either is present, else the
/// first sample's prefix SEI, its NAL units prefixed by `nalLength` bytes.
enum ReelHDR10 {
    /// What the core read; an empty `PQColor` when it read nothing (the core
    /// answers NULL only on a caught panic, read as nothing too).
    static func peak(mastering: Data?, contentLight: Data?, sample: Data?, nalLength: Int)
        -> PQColor
    {
        let length = UInt32(clamping: max(0, nalLength))
        let text: String? = withBytes(mastering) { m, mCount in
            withBytes(contentLight) { l, lCount in
                withBytes(sample) { s, sCount in
                    takeString(rc_hdr10_peak(m, mCount, l, lCount, s, sCount, length))
                }
            }
        }
        return text.flatMap { ReelJSON.decode(PQColor.self, from: $0) } ?? PQColor()
    }

    /// An AV1 track's peak (spec §11 HD-18 (c)), for a description carrying
    /// neither extension: the metadata OBUs of its `av1C` record (`config`),
    /// then of its first sample with data; an empty `PQColor` when nothing
    /// reads.
    static func av1Peak(config: Data?, sample: Data?) -> PQColor {
        let text: String? = withBytes(config) { c, cCount in
            withBytes(sample) { s, sCount in
                takeString(rc_hdr10_av1_peak(c, cCount, s, sCount))
            }
        }
        return text.flatMap { ReelJSON.decode(PQColor.self, from: $0) } ?? PQColor()
    }

    /// A PQ still's peak (`rc_hdr10_still_peak`, spec §11 HD-20 (b)) from its
    /// whole file: a PNG's `cLLI`/`mDCV`, a HEIF or AVIF primary item's
    /// `clli`/`mdcv`; an empty `PQColor` when nothing reads.
    static func stillPeak(file: Data?) -> PQColor {
        let text: String? = withBytes(file) { f, fCount in
            takeString(rc_hdr10_still_peak(f, fCount))
        }
        return text.flatMap { ReelJSON.decode(PQColor.self, from: $0) } ?? PQColor()
    }
}

/// AV1 in MP4's container bytes, decided in the core (spec §11 CX-12 (4)): the
/// `av1C` record from SVT-AV1's sequence header, each packet's temporal
/// delimiters stripped, and the written file's `ftyp` branded `av01`.
enum ReelAV1 {
    /// The record for the first sequence header OBU in `sequenceHeader`; throws
    /// the core's sentence when there is none or it ends early.
    static func config(sequenceHeader: Data) throws -> Config {
        var err: UnsafeMutablePointer<CChar>? = nil
        let raw = withByteBuffer(sequenceHeader) { rc_av1_config($0, $1, &err) }
        guard let text = takeString(raw) else {
            throw ReelCoreError(
                message: takeErrorMessage(err, fallback: "the av1C record could not be built"))
        }
        return try Config.decoded(text)
    }

    /// `data` without its temporal delimiter OBUs; false, `data` untouched, when
    /// it is not a run of whole OBUs (or is empty).
    static func stripTemporalDelimiters(_ data: inout Data) -> Bool {
        let kept = withMutableByteBuffer(&data) { rc_av1_strip_temporal_delimiters($0, $1) }
        guard kept > 0 else { return false }
        data.removeSubrange(data.startIndex.advanced(by: kept)...)
        return true
    }

    /// `rc_av1_ftyp_brand` over a file's first bytes, in place: 1 rewritten, 0
    /// already carried, -1 no `ftyp` box or no `mp41` brand.
    static func brandAV01(_ head: inout Data) -> Int32 {
        withMutableByteBuffer(&head) { rc_av1_ftyp_brand($0, $1) }
    }
}

/// The core's WebM writer (`RcWebm`, spec §11 CX-15), `ExportWebMWriter`'s file. `add`,
/// `endTrack` and `finish` may come from several threads; each throws the core's sentence.
final class ReelWebM {
    static let video = UInt32(RC_WEBM_VIDEO)
    static let audio = UInt32(RC_WEBM_AUDIO)
    private let handle: OpaquePointer

    /// Creates the file at `path` and writes its header from `layoutJSON`.
    init(path: String, layoutJSON: String) throws {
        var err: UnsafeMutablePointer<CChar>? = nil
        guard let made = rc_webm_open(path, layoutJSON, &err) else {
            throw ReelCoreError(message: takeErrorMessage(err, fallback: "it could not be made"))
        }
        handle = made
    }

    deinit { rc_webm_free(handle) }

    func add(track: UInt32, ptsNs: Int64, key: Bool, discardPaddingNs: Int64, data: Data) throws {
        try check { err in
            withByteBuffer(data) {
                rc_webm_add_packet(handle, track, ptsNs, key, discardPaddingNs, $0, $1, err)
            }
        }
    }

    /// One video packet with its alpha frame (spec §11 CX-17 (5)), on a layout whose video has
    /// `alpha_mode`.
    func addVideo(ptsNs: Int64, key: Bool, data: Data, alpha: Data) throws {
        try check { err in
            withByteBuffer(data) { picture, pictureCount in
                withByteBuffer(alpha) { plane, planeCount in
                    rc_webm_add_video_with_alpha(
                        handle, ptsNs, key, picture, pictureCount, plane, planeCount, err)
                }
            }
        }
    }

    func endTrack(_ track: UInt32) throws { try check { rc_webm_end_track(handle, track, $0) } }

    func finish() throws { try check { rc_webm_finish(handle, $0) } }

    private func check(
        _ call: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Bool
    ) throws {
        var err: UnsafeMutablePointer<CChar>? = nil
        guard !call(&err) else { return }
        throw ReelCoreError(message: takeErrorMessage(err, fallback: "it could not be written"))
    }
}
