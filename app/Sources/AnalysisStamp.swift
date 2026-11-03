import CryptoKit
import Foundation

/// What an analysis cache certifies (spec §11 CJ-22, CJ-26; road map
/// "creator-jobs" CJ2a): the kinds, the source's identity, the stamp a
/// marker holds, the marker itself, and the canned rule.
///
/// Nothing here reads a picture or writes a file; `AnalysisStore` does.

/// One analysis a media can have (spec §11 CJ-8 (c): every kind of every bet
/// lives under `cache/analysis/<kind>/`). Names use underscores.
enum AnalysisKind: String, Codable, CaseIterable {
    case shots
    /// Person masks (spec §11 CO-4, CO-10; road map CO1): `AnalysisMasks`.
    case masks
    /// Every face per sample of source time (spec §11 CJ-30…CJ-34; road map
    /// CJ3): `AnalysisFaces`, on its own sample grid (`grid(of:)`).
    case faces
    /// Sound Analysis' confidence per window for six groups (spec §11
    /// FC-30…FC-34; road map FC3): `AnalysisSoundEvents`, on the hop grid,
    /// the one kind on the sound queue.
    case soundEvents = "sound_events"
    /// People (upper body) and salient regions per sample of source time
    /// (spec §11 VR-10, VR-11; road map VR1): `AnalysisSubjects`, on its own
    /// sample grid.
    case subjects

    /// The kind's version: a change to what it stores bumps it, and every
    /// marker of the old version is a miss (Vision request revisions go in
    /// here too, CJ-22).
    var version: Int {
        switch self {
        case .shots: return 1
        case .masks: return 1
        case .faces: return 1
        case .soundEvents: return SoundEvents.tableVersion
        case .subjects: return 1
        }
    }

    /// Whether the kind decodes sound (the sound queue) rather than pictures.
    var usesSoundQueue: Bool {
        switch self {
        case .shots, .masks, .faces, .subjects: return false
        case .soundEvents: return true
        }
    }

    /// The compute device the stamp records: `cpu` for `shots`, whose
    /// signature is integer arithmetic on the CPU; for `masks` the device a
    /// pinned request reads back (spec §11 CO-11); for `faces` and `subjects`
    /// each request's (CJ-32, VR-11).
    var device: String {
        switch self {
        case .shots: return "cpu"
        case .masks: return AnalysisMasks.device
        case .faces: return AnalysisFaces.device
        case .soundEvents: return SoundEvents.device
        case .subjects: return AnalysisSubjects.device
        }
    }

    /// The parameters its stored values depend on — never a threshold or a
    /// neighbourhood applied when a request is answered (CJ-22).
    var parameters: [String: Any] {
        switch self {
        case .shots: return AnalysisShots.parameters
        case .masks: return AnalysisMasks.parameters
        case .faces: return AnalysisFaces.parameters
        case .soundEvents: return SoundEvents.parameters
        case .subjects: return AnalysisSubjects.parameters
        }
    }

    /// The read margin, in grid indices each side of a window (CJ-22).
    var margin: Int {
        switch self {
        case .shots: return AnalysisShots.margin
        case .masks, .faces, .soundEvents, .subjects: return 0
        }
    }

    /// The payload files the kind's folder holds.
    var files: [String] {
        switch self {
        case .shots: return [AnalysisShots.payloadName]
        case .masks: return [MaskPack.fileName]
        case .faces: return [AnalysisFaces.payloadName]
        case .soundEvents: return [SoundEvents.payloadName]
        case .subjects: return [AnalysisSubjects.payloadName]
        }
    }

    /// A Vision kind's request, as its stamp records it; nil for `shots` and
    /// `sound_events`.
    var vision: AnalysisVisionStamp? {
        switch self {
        case .shots, .soundEvents: return nil
        case .masks: return AnalysisMasks.vision
        case .faces: return AnalysisFaces.vision
        case .subjects: return AnalysisSubjects.vision
        }
    }

    /// The grid the kind's coverage and payload are indexed by: the media's
    /// frames, but for `faces` its sample grid, `AnalysisFaces.rate` a second
    /// (CJ-33), for `sound_events` its hop grid (FC-31), and for `subjects`
    /// its own, `AnalysisSubjects.rate` (VR-11).
    func grid(of media: MediaSnapshot) -> AnalysisGrid {
        switch self {
        case .shots, .masks: return AnalysisGrid(media: media)
        case .faces:
            return AnalysisGrid(samplesPerSecond: AnalysisFaces.rate, duration: media.duration)
        case .soundEvents:
            return AnalysisGrid(hopTicks: SoundEvents.hopTicks, duration: media.duration)
        case .subjects:
            return AnalysisGrid(samplesPerSecond: AnalysisSubjects.rate, duration: media.duration)
        }
    }
}

/// The source's identity: `CacheStamp`'s size, modification second and
/// duration, and no path, so a moved package keeps its analysis (CJ-22).
struct AnalysisSourceID: Codable, Equatable {
    let size: Int64
    let modified: Int64
    let duration: Ticks

    /// nil when the file cannot be stat'ed.
    static func of(_ media: MediaSnapshot, url: URL) -> AnalysisSourceID? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = (attributes[.size] as? NSNumber)?.int64Value,
            let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return AnalysisSourceID(
            size: size, modified: Int64(modified.timeIntervalSince1970.rounded()),
            duration: media.duration)
    }
}

/// A Vision kind's request, as its stamp records it (spec §11 CJ-22, CO-10):
/// the request, its quality and revision, the rate and the read size.
struct AnalysisVisionStamp: Codable, Equatable {
    let request: String
    let quality: String
    let revision: Int
    let rate: String
    let readSize: String
}

/// A marker's stamp (spec §11 CJ-22): a stamp that differs in any field is a
/// miss, and the next store deletes the marker, then the payload.
struct AnalysisStamp: Codable, Equatable {
    let source: AnalysisSourceID
    let kind: AnalysisKind
    let version: Int
    /// Hex SHA-256 of the sorted-key JSON of `kind.parameters`.
    let parameters: String
    /// `sysctl kern.osversion`.
    let osBuild: String
    /// `kind.device`.
    let device: String
    /// `raw` or `converted` (CJ-23).
    let reader: String
    /// The conversion, as a converted filmstrip's marker records it; non-nil
    /// iff `reader` is `converted`.
    let conversion: ConvertedThumbsStamp?
    /// A Vision kind's request (`masks`, `faces`, `subjects`); nil, and absent on disk,
    /// for `shots`.
    var vision: AnalysisVisionStamp? = nil

    /// The stamp of `kind` over `media` at `url`, read through `input` (nil:
    /// the direct reader); nil when the file cannot be stat'ed.
    static func make(
        kind: AnalysisKind, media: MediaSnapshot, url: URL, input: ThumbnailInput?,
        fullRange: Bool
    ) -> AnalysisStamp? {
        guard let source = AnalysisSourceID.of(media, url: url) else { return nil }
        var conversion: ConvertedThumbsStamp?
        if let input {
            guard let cacheStamp = MediaImporter.CacheStamp.stamp(for: media, url: url) else {
                return nil
            }
            conversion = ConvertedThumbsStamp(cacheStamp, input: input, fullRange: fullRange)
        }
        return AnalysisStamp(
            source: source, kind: kind, version: kind.version,
            parameters: digest(kind.parameters), osBuild: osBuild, device: kind.device,
            reader: input == nil ? "raw" : "converted", conversion: conversion,
            vision: kind.vision)
    }

    /// Field by field, so no field can drop out of the comparison unseen
    /// (P1: each field alone makes a miss).
    func matches(_ other: AnalysisStamp) -> Bool {
        source == other.source && kind == other.kind && version == other.version
            && parameters == other.parameters
            && osBuild == other.osBuild
            && device == other.device
            && reader == other.reader && conversion == other.conversion
            && vision == other.vision
    }

    /// This Mac's OS build, `kern.osversion` (e.g. `25F80`).
    static let osBuild: String = {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }()

    /// Hex SHA-256 of `parameters` as sorted-key JSON.
    static func digest(_ parameters: [String: Any]) -> String {
        let data =
            (try? JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys]))
            ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// `cache/analysis/<kind>/<media id>.json` (spec §11 CJ-22, CJ-26): the
/// stamp, the payload's files and the coverage — the sorted ranges of grid
/// indices stored, merged where they overlap or touch, inclusive, as
/// `[[first, last], …]`. A canned marker carries no stamp, only `canned:
/// true` and the source's identity.
struct AnalysisMarker: Codable, Equatable {
    let stamp: AnalysisStamp?
    let canned: Bool?
    let source: AnalysisSourceID
    let files: [String]
    let coverage: [[Int]]

    /// The coverage as ranges; a malformed pair is dropped.
    var ranges: [ClosedRange<Int>] {
        coverage.compactMap { pair in
            pair.count == 2 && pair[0] <= pair[1] ? pair[0]...pair[1] : nil
        }
    }

    /// Whether this marker's analysis may answer for `stamp`: a stamped
    /// marker whose stamp matches; a canned one only where `cannedHonoured`
    /// and its source is `stamp`'s.
    func answers(for stamp: AnalysisStamp) -> Bool {
        if canned == true { return Self.cannedHonoured && source == stamp.source }
        return self.stamp?.matches(stamp) == true
    }

    /// `-RCDevAnalysisCanned YES` in a `FRAMEJOB_DEV_TOOLS` build; false in
    /// Distribution, which never reads a canned marker (CJ-26).
    static var cannedHonoured: Bool {
        #if FRAMEJOB_DEV_TOOLS
        return UserDefaults.standard.bool(forKey: AnalysisLane.devCannedKey)
        #else
        return false
        #endif
    }
}
