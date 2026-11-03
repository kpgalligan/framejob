import Foundation

/// `samples.bin` of the `subjects` kind (spec §11 VR-10; road map
/// "creator-jobs" VR1), one payload file per media, little-endian:
///
/// - a 16-byte header: ASCII `FJSB`, `UInt16` version 1, `UInt16` box record
///   bytes (20), `UInt32` sample count, `UInt32` box count;
/// - one 16-byte row per sample index from 0: `Int64` the frame's pts in
///   ticks (−1: no frame), `UInt32` its first box, `UInt16` its people count,
///   `UInt16` its salient count;
/// - the box records: `Float32` x, y, width, height (0…1, top-left, display
///   orientation) and confidence; a sample's people first, then its salient
///   boxes, each group in `ordered` order.
///
/// The cache is raw; only the answer rounds. A publish decodes the on-disk
/// file and replaces the samples it covers; a file that does not decode, or
/// holds another sample count, is written fresh and answers false, so the
/// store keeps the job's coverage alone (`faces`' rule, CJ-33).
extension AnalysisSubjects {

    static let fileVersion: UInt16 = 1
    static let recordBytes: UInt16 = 20
    static let headerBytes = 16
    static let rowBytes = 16

    /// One box as stored. Equal bit for bit.
    struct Box: Equatable {
        var x, y, width, height, confidence: Float

        var values: [Float] { [x, y, width, height, confidence] }

        static func == (a: Box, b: Box) -> Bool {
            a.values.map(\.bitPattern) == b.values.map(\.bitPattern)
        }
    }

    /// What one analysed frame holds: its people and its salient regions.
    struct Subjects: Equatable {
        var people: [Box]
        var salient: [Box]
    }

    /// One sample: the frame it read (pts −1: none) and its boxes.
    struct Sample: Equatable {
        var pts: Int64
        var subjects: Subjects

        static let empty = Sample(pts: -1, subjects: Subjects(people: [], salient: []))
    }

    /// CJ-31: by box centre x, then y (top-left frame), exact float compare.
    static func ordered(_ boxes: [Box]) -> [Box] {
        boxes.sorted { a, b in
            let ax = a.x + a.width / 2, bx = b.x + b.width / 2
            if ax != bx { return ax < bx }
            return a.y + a.height / 2 < b.y + b.height / 2
        }
    }

    /// nil when `data` is not a `subjects` `samples.bin` this build reads.
    static func decode(_ data: Data) -> (count: Int, samples: [Sample])? {
        guard data.count >= headerBytes else { return nil }
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> UInt16 { UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> UInt32 {
            (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[at + $1]) << (8 * UInt32($1)) }
        }
        func i64(_ at: Int) -> Int64 {
            Int64(bitPattern: (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[at + $1]) << (8 * UInt64($1)) })
        }
        guard bytes[0..<4].elementsEqual(Array("FJSB".utf8)), u16(4) == fileVersion,
            u16(6) == recordBytes
        else { return nil }
        let record = Int(recordBytes)
        let count = Int(u32(8)), boxCount = Int(u32(12))
        let boxesAt = headerBytes + count * rowBytes
        guard data.count == boxesAt + boxCount * record else { return nil }
        var boxes: [Box] = []
        boxes.reserveCapacity(boxCount)
        for i in 0..<boxCount {
            let at = boxesAt + i * record
            let v = (0..<5).map { Float(bitPattern: u32(at + $0 * 4)) }
            boxes.append(Box(x: v[0], y: v[1], width: v[2], height: v[3], confidence: v[4]))
        }
        var samples: [Sample] = []
        samples.reserveCapacity(count)
        for k in 0..<count {
            let at = headerBytes + k * rowBytes
            let first = Int(u32(at + 8)), people = Int(u16(at + 12)), salient = Int(u16(at + 14))
            guard first + people + salient <= boxCount else { return nil }
            samples.append(Sample(pts: i64(at), subjects: Subjects(
                people: Array(boxes[first..<(first + people)]),
                salient: Array(boxes[(first + people)..<(first + people + salient)]))))
        }
        return (count, samples)
    }

    /// The bytes of `samples`.
    static func encode(_ samples: [Sample]) -> Data {
        var data = Data()
        let boxCount = samples.reduce(0) { $0 + $1.subjects.people.count + $1.subjects.salient.count }
        data.reserveCapacity(headerBytes + samples.count * rowBytes + boxCount * Int(recordBytes))
        func put<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("FJSB".utf8))
        put(fileVersion)
        put(recordBytes)
        put(UInt32(samples.count))
        put(UInt32(boxCount))
        var first = 0
        for sample in samples {
            put(sample.pts)
            put(UInt32(first))
            put(UInt16(sample.subjects.people.count))
            put(UInt16(sample.subjects.salient.count))
            first += sample.subjects.people.count + sample.subjects.salient.count
        }
        for sample in samples {
            for box in sample.subjects.people + sample.subjects.salient {
                for value in box.values { put(value.bitPattern) }
            }
        }
        return data
    }

    /// The publish's write: the on-disk file decoded (when it answers for the
    /// stamp and decodes at `count` samples) with `covering`'s samples
    /// replaced by `samples` (absent: `Sample.empty`), else a fresh file of
    /// `count` samples; written to `partial`. Answers whether it merged.
    static func write(
        onDisk: URL?, partial: URL, count: Int, covering: ClosedRange<Int>,
        samples: [Int: Sample]
    ) throws -> Bool {
        var merged = false
        var all = [Sample](repeating: .empty, count: count)
        if let onDisk, let data = try? Data(contentsOf: onDisk), let old = decode(data),
            old.count == count
        {
            all = old.samples
            merged = true
        }
        for k in covering where k >= 0 && k < count { all[k] = samples[k] ?? .empty }
        try encode(all).write(to: partial)
        return merged
    }
}
