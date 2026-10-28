import Foundation

/// One packet as a bundled encoder answered it (spec §11 CX-12, CX-15 (3), CX-16 (6)): its
/// bytes as the encoder wrote them, the `pts` the picture was sent with (its frame index),
/// whether it is the last, and whether it is a key — a KEY_FRAME for SVT-AV1, libvpx's
/// `VPX_FRAME_IS_KEY` for VP9 — which the WebM writer flags.
struct ExportEncodedPacket {
    let data: Data
    let pts: Int64
    let isLast: Bool
    let isKey: Bool
}

/// What `ExportEncodePump` asks of a bundled encoder (spec §11 CX-12, CX-16): SVT-AV1 for the
/// AV1 rows (`SVTAV1Encoder`), libvpx's VP9 for `vp9_webm` (`VP9Encoder`). Every call after
/// `init` is made on the pump's encode queue alone.
protocol ExportVideoEncoder: AnyObject {
    /// The library's name in a sentence ("SVT-AV1", "libvpx").
    var name: String { get }
    /// Sends one picture, `index` its pts; the encoder copies the planes, so `frame` may be
    /// reused once this returns.
    func send(_ frame: I010Frame, index: Int64) throws
    /// No picture follows, so `nextPacket(wait: true)` drains to the last packet.
    func sendEndOfStream() throws
    /// The next packet: nil when none is ready (`wait` false). `wait` true is asked only after
    /// `sendEndOfStream` and answers nil once the encoder is drained.
    func nextPacket(wait: Bool) throws -> ExportEncodedPacket?
    /// A packet's bytes as the container takes them: SVT-AV1's with their temporal delimiters
    /// stripped (CX-12 (4)), VP9's as they are. Throws when the bytes cannot be read.
    func containerBytes(_ data: Data) throws -> Data
}

/// A bundled encoder's rate table (spec §11 CX-13 (3), CX-16 (7)): a constant quality — a CRF
/// or a CQ level — as a function of the cap's bits per pixel per frame.
enum ExportRateTable {
    /// The value at `bitsPerPixel`: linear between `points` (ascending in bits per pixel),
    /// rounded down (a lower value is the better picture), and the end point's value beyond
    /// either end. An empty table is a programming error, never a value: 0 would ask for the
    /// largest file the encoder can make.
    static func value(
        at bitsPerPixel: Double, points: [(bitsPerPixel: Double, value: Double)]
    ) -> UInt32 {
        guard let first = points.first, let last = points.last else {
            preconditionFailure("ExportRateTable.value: an empty rate table")
        }
        if !(bitsPerPixel > first.bitsPerPixel) { return UInt32(first.value) }
        if bitsPerPixel >= last.bitsPerPixel { return UInt32(last.value) }
        for (low, high) in zip(points, points.dropFirst()) where bitsPerPixel < high.bitsPerPixel {
            let share = (bitsPerPixel - low.bitsPerPixel) / (high.bitsPerPixel - low.bitsPerPixel)
            return UInt32((low.value + share * (high.value - low.value)).rounded(.down))
        }
        return UInt32(last.value)
    }
}
