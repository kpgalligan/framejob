import Darwin
import Foundation
import Metal

/// One media's mask pack as the compositor reads it (spec §11 CO-24, CO-25): the mapped pack,
/// its marker's coverage (merged), the media's grid and each mask's end for the reversed slot.
final class CutoutPack {
    let pack: MaskPack
    let coverage: [ClosedRange<Int>]
    let grid: AnalysisGrid
    let ends: [(end: Int64, slot: Int)]

    init(pack: MaskPack, coverage: [ClosedRange<Int>], grid: AnalysisGrid) {
        self.pack = pack
        self.coverage = AnalysisStore.merged(coverage)
        self.grid = grid
        self.ends = CutoutLookup.ends(of: pack, grid: grid)
    }
}

/// What the compositor keeps to draw a cutout (road map creator-jobs CO2a2, spec §11 CO-24…CO-27):
/// the lookup's plan per recipe key, the packs per (cache folder, media), the stamps they are
/// checked against, which clip windows found a subject, and the masks' textures.
///
/// **A request reads at most one `stat`** per cut-out layer, of the media's marker: the marker,
/// the stamp and the pack are read again only when the marker's (inode, size, modification
/// time), the media or its URL changes, and the stamp's asset read only when the media or its
/// URL does (CO-25). A publish renames a new pack into place, so a mapping kept here stays whole.
///
/// **A mask's texture** is its bytes as stored — `r8Unorm`, the pack's width × height,
/// `replace(region:)` — never through AVFoundation, step 0 or a lift (CO-27); a least-recently-
/// used pool of `limit`, keyed by the pack's identity and the slot, each entry holding its pack
/// so an identity is never reused while its texture is held. `uploads` counts textures made.
///
/// One per `MetalRenderer`, called on its render queue only, so it keeps no lock (as
/// `CursorSprites`).
final class CutoutMasks {
    static let limit = 8

    private struct PlanEntry {
        weak var project: ReelProject?
        let plan: CutoutPlan
    }

    private struct PackKey: Hashable {
        let folder: String
        let media: UInt32
    }

    /// The marker file's identity by `stat`: a publish writes a new file.
    private struct Signature: Equatable {
        let inode: UInt64
        let size: Int64
        let seconds: Int
        let nanoseconds: Int
    }

    private struct PackEntry {
        let signature: Signature?
        let url: URL
        let media: MediaSnapshot
        let pack: CutoutPack?
    }

    private struct StampEntry {
        let url: URL
        let lut: URL?
        let media: MediaSnapshot
        let stamp: AnalysisStamp?
    }

    private struct FoundKey: Hashable {
        let pack: ObjectIdentifier
        let clip: UInt32
        let lower: Ticks
        let upper: Ticks
    }

    private struct FoundEntry {
        let pack: CutoutPack
        let found: Bool
    }

    private struct TextureKey: Hashable {
        let pack: ObjectIdentifier
        let slot: Int
    }

    private struct TextureEntry {
        let pack: CutoutPack
        let texture: MTLTexture
    }

    private let device: MTLDevice
    private var plans: [Int: PlanEntry] = [:]
    private var packs: [PackKey: PackEntry] = [:]
    private var stamps: [UInt32: StampEntry] = [:]
    private var founds = LRUCache<FoundKey, FoundEntry>(limit: 256)
    private var textures = LRUCache<TextureKey, TextureEntry>(limit: CutoutMasks.limit)
    private(set) var uploads = 0

    init(device: MTLDevice) {
        self.device = device
    }

    /// The lookup's plan of `project`, kept per `key` while the key holds that very handle; a
    /// new handle (every edit and drag tick) decodes its plan once, when a cut-out layer draws.
    func plan(for key: Int, project: ReelProject) -> CutoutPlan {
        if let entry = plans[key], entry.project === project { return entry.plan }
        plans = plans.filter { $0.value.project != nil }
        let plan = CutoutPlan(project: project)
        plans[key] = PlanEntry(project: project, plan: plan)
        return plan
    }

    /// `media`'s pack in `cacheDir` when its marker answers for the stamp the analysis would
    /// make over `url` (`urls` names a LUT Camera Log's file) and the pack reads; nil otherwise
    /// (spec §11 CO-25).
    func pack(media: MediaSnapshot, url: URL, cacheDir: URL, urls: [UInt32: URL]) -> CutoutPack? {
        let marker = AnalysisStore.markerURL(.masks, media: media.id, in: cacheDir)
        let signature = Self.signature(of: marker)
        let key = PackKey(folder: cacheDir.standardizedFileURL.path, media: media.id)
        if let entry = packs[key], entry.signature == signature, entry.url == url,
            entry.media == media
        {
            return entry.pack
        }
        var answer: CutoutPack?
        if signature != nil, let read = AnalysisStore.readMarker(.masks, media: media.id, in: cacheDir),
            let stamp = stamp(media: media, url: url, urls: urls), read.answers(for: stamp),
            let file = read.files.first,
            let pack = try? MaskPack(
                contentsOf: AnalysisStore.payloadURL(.masks, media: media.id, file: file, in: cacheDir)),
            pack.width > 0, pack.height > 0
        {
            answer = CutoutPack(pack: pack, coverage: read.ranges, grid: AnalysisGrid(media: media))
        }
        packs[key] = PackEntry(signature: signature, url: url, media: media, pack: answer)
        return answer
    }

    /// Whether `window` (forward source ticks) of `clip` found a subject in `pack` (CO-26),
    /// worked out once per (pack, clip, window).
    func found(_ pack: CutoutPack, clip: UInt32, window: ClosedRange<Ticks>) -> Bool {
        let key = FoundKey(
            pack: ObjectIdentifier(pack), clip: clip, lower: window.lowerBound,
            upper: window.upperBound)
        if let hit = founds.value(for: key, where: { $0.pack === pack }) { return hit.found }
        let found = CutoutLookup.subjectFound(
            pack: pack.pack, window: window, coverage: pack.coverage, grid: pack.grid)
        founds.insert(FoundEntry(pack: pack, found: found), for: key)
        return found
    }

    /// Slot `slot`'s mask as an `r8Unorm` texture, uploaded as stored; nil when it does not
    /// decompress to the pack's size or cannot be made.
    func texture(_ pack: CutoutPack, slot: Int) -> MTLTexture? {
        let key = TextureKey(pack: ObjectIdentifier(pack), slot: slot)
        if let hit = textures.value(for: key, where: { $0.pack === pack }) { return hit.texture }
        let width = pack.pack.width, height = pack.pack.height
        guard let bytes = try? pack.pack.mask(slot: slot) else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: base,
                bytesPerRow: width)
        }
        uploads += 1
        textures.insert(TextureEntry(pack: pack, texture: texture), for: key)
        return texture
    }

    /// The stamp `ProjectDocument.analysisRequest` would make for `media` at `url` — its asset
    /// read only when the media, its URL or its LUT's URL changed (CO-25).
    private func stamp(media: MediaSnapshot, url: URL, urls: [UInt32: URL]) -> AnalysisStamp? {
        let lut = media.color?.lut.flatMap { urls[$0] }
        if let entry = stamps[media.id], entry.url == url, entry.lut == lut, entry.media == media {
            return entry.stamp
        }
        let (input, fullRange) = ProjectDocument.analysisInput(media: media, url: url, urls: urls)
        let stamp = AnalysisStamp.make(
            kind: .masks, media: media, url: url, input: input, fullRange: fullRange)
        stamps[media.id] = StampEntry(url: url, lut: lut, media: media, stamp: stamp)
        return stamp
    }

    /// The file's (inode, size, modification time); nil when it cannot be stat'ed.
    private static func signature(of url: URL) -> Signature? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return Signature(
            inode: UInt64(info.st_ino), size: Int64(info.st_size),
            seconds: Int(info.st_mtimespec.tv_sec), nanoseconds: Int(info.st_mtimespec.tv_nsec))
    }
}
