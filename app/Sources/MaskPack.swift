import Foundation

/// The `masks` kind's one payload file per media (spec §11 CO-4, CO-10; road
/// map "creator-jobs" CO1): `cache/analysis/masks/<media id>/masks.pack`.
///
/// **Bytes**, little-endian:
/// - the mask blobs, each one analysed mask, 8-bit at the size Vision
///   answered for the media, LZFSE-compressed (`NSData.compressed(using:
///   .lzfse)`), in append order;
/// - the frame table, 16 bytes a frame: `Int64` pts (source ticks), `Int32`
///   grid index, `UInt32` slot (the mask table's index of its nearest
///   analysed mask); sorted by pts, a pts at most once;
/// - the mask table, 24 bytes a mask: `Int64` pts, `UInt64` offset from the
///   file's start, `UInt32` length, `UInt8` found, three zero bytes; in append
///   order, so a slot never moves;
/// - the footer, 40 bytes: `FJMP`, `UInt32` version, width, height, frame
///   count, mask count, `UInt64` tables offset, `UInt64` 0.
///
/// **The append-merge** (`write`): an on-disk pack of this version and size
/// is cloned to the partial (`FileManager.copyItem`, an APFS clone), cut at
/// its tables, and only the masks whose pts its mask table lacks are appended
/// — a pts on disk keeps its slot and its bytes — then the merged frame table
/// (on disk wins on an equal pts), the extended mask table and the footer.
/// Anything else is written fresh. Written only through
/// `AnalysisStore.publishFile`'s `.partial` and rename; read mapped.
struct MaskPack {
    static let fileName = "masks.pack"
    static let version: UInt32 = 1
    static let footerSize = 40
    static let frameSize = 16
    static let maskSize = 24
    private static let magic: [UInt8] = Array("FJMP".utf8)

    struct Frame: Equatable {
        let pts: Int64
        let index: Int32
        let slot: UInt32
    }

    struct Mask: Equatable {
        let pts: Int64
        let offset: UInt64
        let length: UInt32
        let found: Bool
    }

    /// One analysed mask a job hands the writer.
    struct Analysed {
        let pts: Int64
        let compressed: Data
        let found: Bool
    }

    let width: Int
    let height: Int
    let frames: [Frame]
    let masks: [Mask]
    private let data: Data
    private let tablesOffset: Int

    /// Reads and checks a pack (mapped); throws `MaskPackError`.
    init(contentsOf url: URL) throws {
        let data: Data
        do { data = try Data(contentsOf: url, options: .alwaysMapped) } catch {
            throw MaskPackError.notAPack
        }
        try self.init(data: data)
    }

    init(data: Data) throws {
        let n = data.count
        guard n >= Self.footerSize else { throw MaskPackError.notAPack }
        func u32(_ at: Int) -> UInt32 {
            data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: at, as: UInt32.self)) }
        }
        func u64(_ at: Int) -> UInt64 {
            data.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: at, as: UInt64.self)) }
        }
        let foot = n - Self.footerSize
        guard [UInt8](data[(data.startIndex + foot)..<(data.startIndex + foot + 4)]) == Self.magic
        else { throw MaskPackError.notAPack }
        let version = u32(foot + 4)
        guard version == Self.version else { throw MaskPackError.version(version) }
        let width = Int(u32(foot + 8)), height = Int(u32(foot + 12))
        let frameCount = Int(u32(foot + 16)), maskCount = Int(u32(foot + 20))
        let tables = u64(foot + 24)
        guard tables <= UInt64(foot),
            Int(tables) + frameCount * Self.frameSize + maskCount * Self.maskSize == foot
        else { throw MaskPackError.truncated }
        let tablesOffset = Int(tables)
        var masks: [Mask] = []
        masks.reserveCapacity(maskCount)
        let maskBase = tablesOffset + frameCount * Self.frameSize
        data.withUnsafeBytes { raw in
            for i in 0..<maskCount {
                let o = maskBase + i * Self.maskSize
                masks.append(
                    Mask(
                        pts: Int64(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: Int64.self)),
                        offset: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: o + 8, as: UInt64.self)),
                        length: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o + 16, as: UInt32.self)),
                        found: raw[o + 20] != 0))
            }
        }
        guard masks.allSatisfy({ $0.offset + UInt64($0.length) <= UInt64(tablesOffset) }) else {
            throw MaskPackError.truncated
        }
        var frames: [Frame] = []
        frames.reserveCapacity(frameCount)
        data.withUnsafeBytes { raw in
            for i in 0..<frameCount {
                let o = tablesOffset + i * Self.frameSize
                frames.append(
                    Frame(
                        pts: Int64(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: Int64.self)),
                        index: Int32(littleEndian: raw.loadUnaligned(fromByteOffset: o + 8, as: Int32.self)),
                        slot: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o + 12, as: UInt32.self))))
            }
        }
        guard frames.allSatisfy({ Int($0.slot) < maskCount }) else { throw MaskPackError.truncated }
        self.width = width
        self.height = height
        self.frames = frames
        self.masks = masks
        self.data = data
        self.tablesOffset = tablesOffset
    }

    /// Slot `slot`'s mask, decompressed: width × height bytes, row-packed.
    func mask(slot: Int) throws -> [UInt8] {
        guard slot >= 0, slot < masks.count else { throw MaskPackError.truncated }
        let entry = masks[slot]
        let start = data.startIndex + Int(entry.offset)
        let blob = data[start..<(start + Int(entry.length))]
        guard let plain = try? (Data(blob) as NSData).decompressed(using: .lzfse) as Data,
            plain.count == width * height
        else { throw MaskPackError.size(width, height) }
        return [UInt8](plain)
    }

    /// The index in `frames` of the frame shown at `pts`: the last whose pts
    /// is at or before it; nil before the first.
    func shown(at pts: Int64) -> Int? {
        var low = 0, high = frames.count
        while low < high {
            let mid = (low + high) / 2
            if frames[mid].pts <= pts { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }

    /// Whether a mask holds a subject (spec §11 CO-5, CO-10): at least 0.5 %
    /// of its pixels above 127.
    static func found(_ mask: UnsafeRawBufferPointer, width: Int, height: Int) -> Bool {
        var above = 0
        for byte in mask.prefix(width * height) where byte > 127 { above += 1 }
        return above * 200 >= width * height
    }

    // MARK: - Writing

    /// Writes `partial`: merged onto `onDisk` (answers true) when that parses
    /// at this version and `width` × `height` — or at any size when `masks` is
    /// empty (a job that made no mask, e.g. a range of dropped VFR frames, has
    /// no size and keeps the pack's own) — else fresh (false). Each frame's
    /// `maskPts` must be a mask of `masks` or of the on-disk pack.
    @discardableResult
    static func write(
        onDisk: URL?, partial: URL, width: Int, height: Int,
        frames: [(pts: Int64, index: Int32, maskPts: Int64)], masks: [Analysed]
    ) throws -> Bool {
        let fm = FileManager.default
        var old: MaskPack?
        if let onDisk, let pack = try? MaskPack(contentsOf: onDisk),
            masks.isEmpty || (pack.width == width && pack.height == height)
        {
            old = pack
        }
        let width = old?.width ?? width, height = old?.height ?? height
        var table = old?.masks ?? []
        var slots: [Int64: UInt32] = [:]
        for (i, mask) in table.enumerated() { slots[mask.pts] = UInt32(i) }
        var blobs = Data()
        var end = UInt64(old?.tablesOffset ?? 0)
        for mask in masks where slots[mask.pts] == nil {
            slots[mask.pts] = UInt32(table.count)
            table.append(
                Mask(pts: mask.pts, offset: end, length: UInt32(mask.compressed.count), found: mask.found))
            blobs.append(mask.compressed)
            end += UInt64(mask.compressed.count)
        }
        var byPts: [Int64: Frame] = [:]
        for frame in frames {
            guard let slot = slots[frame.maskPts] else {
                throw AnalysisStore.StoreError.write(
                    "the frame at \(frame.pts) has no mask at \(frame.maskPts)")
            }
            byPts[frame.pts] = Frame(pts: frame.pts, index: frame.index, slot: slot)
        }
        for frame in old?.frames ?? [] { byPts[frame.pts] = frame }  // on disk wins
        let merged = byPts.values.sorted { $0.pts < $1.pts }
        var tail = blobs
        tail.append(tables(merged, table, width: width, height: height, tablesOffset: end))
        if let old, let onDisk {
            try? fm.removeItem(at: partial)
            try fm.copyItem(at: onDisk, to: partial)
            let handle = try FileHandle(forWritingTo: partial)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(old.tablesOffset))
            try handle.seekToEnd()
            try handle.write(contentsOf: tail)
            return true
        }
        try tail.write(to: partial)
        return false
    }

    /// The frame table, the mask table and the footer.
    private static func tables(
        _ frames: [Frame], _ masks: [Mask], width: Int, height: Int, tablesOffset: UInt64
    ) -> Data {
        var out = Data()
        out.reserveCapacity(frames.count * frameSize + masks.count * maskSize + footerSize)
        func put<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) }
        }
        for frame in frames {
            put(frame.pts)
            put(frame.index)
            put(frame.slot)
        }
        for mask in masks {
            put(mask.pts)
            put(mask.offset)
            put(mask.length)
            out.append(contentsOf: [mask.found ? 1 : 0, 0, 0, 0])
        }
        out.append(contentsOf: magic)
        put(version)
        put(UInt32(width))
        put(UInt32(height))
        put(UInt32(frames.count))
        put(UInt32(masks.count))
        put(tablesOffset)
        put(UInt64(0))
        return out
    }
}

/// Why a pack would not read; packs are written only through a `.partial`
/// and a rename, so each is hand damage.
enum MaskPackError: LocalizedError, Equatable {
    case notAPack, version(UInt32), size(Int, Int), truncated

    var errorDescription: String? {
        switch self {
        case .notAPack: return "the file is not a mask pack"
        case .version(let v): return "the pack is version \(v), not \(MaskPack.version)"
        case .size(let w, let h): return "a mask is not \(w) × \(h) bytes"
        case .truncated: return "the pack's tables do not fit its bytes"
        }
    }
}
