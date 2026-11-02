import Foundation

/// `samples.bin` (spec §11 CJ-33; road map "creator-jobs" CJ3), the `faces`
/// kind's one payload file per media, little-endian:
///
/// - a 16-byte header: ASCII `FJFS`, `UInt16` version 1, `UInt16` face record
///   bytes (36, or 28 without landmarks), `UInt32` sample count, `UInt32` face
///   count;
/// - one 16-byte row per sample index from 0: `Int64` the frame's pts in
///   ticks (−1: no frame), `UInt32` its first face, `UInt32` its face count;
/// - the face records: `Float32` x, y, width, height (0…1, top-left, display
///   orientation), confidence, roll, yaw (radians), and with landmarks mouth
///   gap and mouth width (NaN: absent).
///
/// The cache is raw; only the answer rounds. A publish decodes the on-disk
/// file and replaces the samples it covers; a file that does not decode, or
/// holds another sample count or record size, is written fresh and answers
/// false, so the store keeps the job's coverage alone.
extension AnalysisFaces {

    static let fileVersion: UInt16 = 1
    static var recordBytes: UInt16 { landmarks ? 36 : 28 }
    static let headerBytes = 16
    static let rowBytes = 16

    /// One face as stored; NaN marks an absent value. Equal bit for bit.
    struct Face: Equatable {
        var x, y, width, height, confidence, roll, yaw, mouthGap, mouthWidth: Float

        var values: [Float] { [x, y, width, height, confidence, roll, yaw, mouthGap, mouthWidth] }

        static func == (a: Face, b: Face) -> Bool {
            a.values.map(\.bitPattern) == b.values.map(\.bitPattern)
        }
    }

    /// One sample: the frame it read (pts −1: none) and its faces in CJ-31's order.
    struct Sample: Equatable {
        var pts: Int64
        var faces: [Face]

        static let empty = Sample(pts: -1, faces: [])
    }

    /// nil when `data` is not a `samples.bin` this build reads.
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
        guard bytes[0..<4].elementsEqual(Array("FJFS".utf8)), u16(4) == fileVersion else {
            return nil
        }
        let record = Int(u16(6))
        guard record == 36 || record == 28 else { return nil }
        let count = Int(u32(8)), faceCount = Int(u32(12))
        let facesAt = headerBytes + count * rowBytes
        guard data.count == facesAt + faceCount * record else { return nil }
        var faces: [Face] = []
        faces.reserveCapacity(faceCount)
        for i in 0..<faceCount {
            let at = facesAt + i * record
            var v = (0..<(record / 4)).map { Float(bitPattern: u32(at + $0 * 4)) }
            if v.count == 7 { v += [.nan, .nan] }
            faces.append(
                Face(x: v[0], y: v[1], width: v[2], height: v[3], confidence: v[4], roll: v[5],
                     yaw: v[6], mouthGap: v[7], mouthWidth: v[8]))
        }
        var samples: [Sample] = []
        samples.reserveCapacity(count)
        for k in 0..<count {
            let at = headerBytes + k * rowBytes
            let first = Int(u32(at + 8)), n = Int(u32(at + 12))
            guard first + n <= faceCount else { return nil }
            samples.append(Sample(pts: i64(at), faces: Array(faces[first..<(first + n)])))
        }
        return (count, samples)
    }

    /// The bytes of `samples`, at this build's record size.
    static func encode(_ samples: [Sample]) -> Data {
        var data = Data()
        let faceCount = samples.reduce(0) { $0 + $1.faces.count }
        data.reserveCapacity(headerBytes + samples.count * rowBytes + faceCount * Int(recordBytes))
        func put<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("FJFS".utf8))
        put(fileVersion)
        put(recordBytes)
        put(UInt32(samples.count))
        put(UInt32(faceCount))
        var first = 0
        for sample in samples {
            put(sample.pts)
            put(UInt32(first))
            put(UInt32(sample.faces.count))
            first += sample.faces.count
        }
        let fields = Int(recordBytes) / 4
        for face in samples.flatMap(\.faces) {
            for value in face.values.prefix(fields) { put(value.bitPattern) }
        }
        return data
    }

    /// The publish's write: the on-disk file decoded (when it answers for the
    /// stamp and decodes at `count` samples and this record size) with
    /// `covering`'s samples replaced by `samples` (absent: `Sample.empty`),
    /// else a fresh file of `count` samples; written to `partial`. Answers
    /// whether it merged.
    static func write(
        onDisk: URL?, partial: URL, count: Int, covering: ClosedRange<Int>,
        samples: [Int: Sample]
    ) throws -> Bool {
        var merged = false
        var all = [Sample](repeating: .empty, count: count)
        if let onDisk, let data = try? Data(contentsOf: onDisk), let old = decode(data),
            old.count == count, data.count >= 8,
            UInt16(data[data.startIndex + 6]) | UInt16(data[data.startIndex + 7]) << 8
                == recordBytes
        {
            all = old.samples
            merged = true
        }
        for k in covering where k >= 0 && k < count { all[k] = samples[k] ?? .empty }
        try encode(all).write(to: partial)
        return merged
    }
}
