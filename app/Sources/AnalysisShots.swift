import Foundation

/// The `shots` kind (spec §11 CJ-24; road map "creator-jobs" CJ2a): hard
/// cuts from a deterministic picture difference, no ML.
///
/// **The signature** is spike CJ-S4's: a 4 × 4 × 4 colour histogram — the
/// top two bits of each of R, G and B — of the frame at long side 256, in
/// whole-pixel counts. **The distance** is their L1 summed exactly in
/// integers and divided once by the pixel count (0…2), so two distances
/// equal in counts are equal to the bit — a flash's two sides tie, as the
/// cut rule's tie-break needs.
///
/// **Stored per grid index** (`frames.bin`, one 16-byte little-endian record
/// per index from 0: `Int64` pts in ticks, −1 for no frame, `Float32` d1,
/// `Float32` d2): d1(i) is the distance to p1(i), the greatest index below i
/// holding a frame; d2(i) to p2(i), the greatest below p1(i); none → 0. Both
/// depend only on the frame and the two kept frames before it (CJ-22).
///
/// **The cut rule, applied when answered** (`cuts`): frame i is a cut when
/// d1(i) ≥ T; d2(n(i)) ≥ T, n(i) the least index above i holding a frame,
/// the test passing when no frame lies in i+1…i+m+1 or at the media's end;
/// and d1(i) is the largest d1 over i−m…i+m, an empty index counting 0, ties
/// to the earlier. T = 0.34, m = 12; the read margin is m + 1.
enum AnalysisShots {
    static let longSide = 256
    static let threshold: Float = 0.34
    static let neighbourhood = 12
    /// The read margin, m + 1 indices each side.
    static var margin: Int { neighbourhood + 1 }
    static let payloadName = "frames.bin"
    static let recordSize = 16
    /// A job publishes at each range's end and after this much wall time.
    static let publishInterval: TimeInterval = 30

    /// What the stored values depend on (never T or m): the stamp's digest.
    static let parameters: [String: Any] = [
        "signature": "rgb_histogram", "bits_per_channel": 2, "long_side": longSide,
        "distance": "l1_counts",
    ]

    struct Record: Equatable {
        var pts: Int64
        var d1: Float
        var d2: Float

        static let empty = Record(pts: -1, d1: 0, d2: 0)
        var holdsFrame: Bool { pts >= 0 }
    }

    // MARK: - The signature

    /// 64 counts of a picture's colours by their top two bits.
    static func signature(_ picture: AnalysisPicture) -> [Int32] {
        var counts = [Int32](repeating: 0, count: 64)
        for y in 0..<picture.height {
            let row = picture.bytes + y * picture.bytesPerRow
            for x in 0..<picture.width {
                let p = row + x * 4
                let bin = Int(p[2] >> 6) << 4 | Int(p[1] >> 6) << 2 | Int(p[0] >> 6)
                counts[bin] += 1
            }
        }
        return counts
    }

    /// L1 of two signatures over the first one's pixel count.
    static func distance(_ a: [Int32], _ b: [Int32]) -> Float {
        var sum: Int64 = 0
        var total: Int64 = 0
        for i in 0..<min(a.count, b.count) {
            sum += Int64(abs(a[i] - b[i]))
            total += Int64(a[i])
        }
        return total > 0 ? Float(Double(sum) / Double(total)) : 0
    }

    // MARK: - frames.bin

    /// Every record of a payload, `count` long; an index past the bytes is
    /// empty.
    static func decode(_ data: Data, count: Int) -> [Record] {
        var records = [Record](repeating: .empty, count: count)
        data.withUnsafeBytes { raw in
            let available = min(count, raw.count / recordSize)
            for k in 0..<available {
                let o = k * recordSize
                let pts = Int64(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: Int64.self))
                let d1 = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o + 8, as: UInt32.self))
                let d2 = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o + 12, as: UInt32.self))
                records[k] = Record(pts: pts, d1: Float(bitPattern: d1), d2: Float(bitPattern: d2))
            }
        }
        return records
    }

    /// One record's 16 bytes.
    static func bytes(of record: Record) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(recordSize)
        withUnsafeBytes(of: record.pts.littleEndian) { out += $0 }
        withUnsafeBytes(of: record.d1.bitPattern.littleEndian) { out += $0 }
        withUnsafeBytes(of: record.d2.bitPattern.littleEndian) { out += $0 }
        return out
    }

    /// `data` made `count` records long (new ones empty), then every index of
    /// `covered` written: its record when `records` holds one, else empty.
    static func merge(
        _ data: inout Data, count: Int, records: [Int: Record], covered: [ClosedRange<Int>]
    ) {
        let length = count * recordSize
        if data.count < length {
            var tail = Data()
            for _ in 0..<((length - data.count) / recordSize) { tail.append(contentsOf: bytes(of: .empty)) }
            data.append(tail)
        } else if data.count > length {
            data.removeSubrange(length..<data.count)
        }
        for range in covered {
            for k in range where k >= 0 && k < count {
                let o = data.startIndex + k * recordSize
                data.replaceSubrange(o..<(o + recordSize), with: bytes(of: records[k] ?? .empty))
            }
        }
    }

    // MARK: - The cut rule

    /// The cuts among `window`'s indices of `records` (the whole grid).
    static func cuts(
        _ records: [Record], in window: ClosedRange<Int>, threshold: Float = threshold,
        m: Int = neighbourhood
    ) -> [Int] {
        let n = records.count
        func holds(_ i: Int) -> Bool { i >= 0 && i < n && records[i].holdsFrame }
        let low = max(0, window.lowerBound)
        let high = min(n - 1, window.upperBound)
        guard low <= high else { return [] }
        var found: [Int] = []
        for i in low...high where holds(i) && records[i].d1 >= threshold {
            let d = records[i].d1
            // A single flash returning to the shot: the next frame within
            // m + 1 must differ from the frame before this one too.
            var next: Int?
            if i + 1 <= min(n - 1, i + m + 1) {
                next = (i + 1...min(n - 1, i + m + 1)).first(where: holds)
            }
            if let next, records[next].d2 < threshold { continue }
            var largest = true
            for j in max(0, i - m)...min(n - 1, i + m) where j != i {
                let other = holds(j) ? records[j].d1 : 0
                if (j < i && other >= d) || (j > i && other > d) {
                    largest = false
                    break
                }
            }
            if largest { found.append(i) }
        }
        return found
    }

    // MARK: - The job

    /// Runs `request`'s ranges in order, publishing at each range's end and
    /// every `publishInterval`. False when `cancelled()` stopped it.
    /// `progress` hears done / total of the ranges' indices after each
    /// stored frame (the Analyzing sheet's bar, spec §11 CJ-28).
    static func run(
        _ request: AnalysisRequest, cancelled: () -> Bool,
        progress: (Double) -> Void = { _ in }
    ) throws -> Bool {
        let grid = AnalysisGrid(media: request.media)
        let source = AnalysisFrames.Source(
            media: request.media, url: request.url, input: request.input)
        let total = max(1, request.ranges.reduce(0) { $0 + $1.count })
        var before = 0
        for range in request.ranges {
            var records: [Int: Record] = [:]
            var p1: [Int32]?
            var p2: [Int32]?
            var coveredFrom = range.lowerBound
            var lastIndex = range.lowerBound - 1
            var lastPublish = Date()
            let finished = try AnalysisFrames.read(
                range: range, grid: grid, source: source, longSide: longSide,
                cancelled: cancelled
            ) { k, pts, picture in
                let signature = signature(picture)
                if k >= range.lowerBound {
                    records[k] = Record(
                        pts: pts, d1: p1.map { distance(signature, $0) } ?? 0,
                        d2: p2.map { distance(signature, $0) } ?? 0)
                    lastIndex = k
                    progress(Double(before + k - range.lowerBound + 1) / Double(total))
                }
                p2 = p1
                p1 = signature
                if Date().timeIntervalSince(lastPublish) >= publishInterval,
                    lastIndex >= coveredFrom
                {
                    try publish(request, grid: grid, covered: coveredFrom...lastIndex, records)
                    records.removeAll()
                    coveredFrom = lastIndex + 1
                    lastPublish = Date()
                }
            }
            guard finished else { return false }
            if coveredFrom <= range.upperBound {
                try publish(request, grid: grid, covered: coveredFrom...range.upperBound, records)
            }
            before += range.count
        }
        return true
    }

    private static func publish(
        _ request: AnalysisRequest, grid: AnalysisGrid, covered: ClosedRange<Int>,
        _ records: [Int: Record]
    ) throws {
        try AnalysisStore.publish(
            kind: .shots, cacheDir: request.cacheDir, mediaID: request.media.id,
            stamp: request.stamp, covered: [covered], files: [payloadName]
        ) { data in
            merge(&data, count: grid.count, records: records, covered: [covered])
        }
    }
}
