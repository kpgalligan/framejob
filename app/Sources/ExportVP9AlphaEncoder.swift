import Foundation

/// `vp9_alpha_webm`'s encoder (spec §11 CX-17 (3), (4)): two encoders fed the same frames —
/// the picture's (`VP9Encoder` exactly as `vp9_webm`'s 8-bit, with forced keys) and the
/// alpha's (`VP9Encoder.Plane.alpha`, constant quality, full range) — answering a packet only
/// when both have answered that frame, the alpha's bytes in its `alpha`.
///
/// **Paired by pts.** Each encoder's packets wait in a queue of their own; the oldest of each
/// are paired when both queues have one. An alpha packet at another frame than the picture's,
/// or one that disagrees on being a keyframe, fails the export in its own sentence: the WebM
/// writer would otherwise put one frame's alpha under another's picture, or a key's alpha
/// under an inter frame a seek cannot decode. The keys agree by construction (both encoders'
/// `keyInterval`), so either sentence is a defect, never a file.
///
/// Every call is made on the pump's encode queue alone, as on any `ExportVideoEncoder`.
final class VP9AlphaEncoder: ExportVideoEncoder {
    let name = "libvpx"

    private let picture: any ExportVideoEncoder
    private let alpha: any ExportVideoEncoder
    private var pictures: [ExportEncodedPacket] = []
    private var alphas: [ExportEncodedPacket] = []
    /// Set once a stream has answered its last packet after the end of stream.
    private var pictureDrained = false
    private var alphaDrained = false

    init(picture: any ExportVideoEncoder, alpha: any ExportVideoEncoder) {
        self.picture = picture
        self.alpha = alpha
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("VP9AlphaEncoder does not support NSCoder")
    }

    /// The two libvpx encoders of an 8-bit SDR picture at the export's size and rate, their
    /// keys forced every `VP9Encoder.keyInterval(fps:)` frames; the cap is the picture's alone.
    static func make(width: Int, height: Int, fps: Fps, bitsPerSecond: Int) throws
        -> VP9AlphaEncoder
    {
        let interval = VP9Encoder.keyInterval(fps: fps)
        return VP9AlphaEncoder(
            picture: try VP9Encoder(
                width: width, height: height, fps: fps, bitsPerSecond: bitsPerSecond,
                picture: .sdr, plane: .picture, keyInterval: interval),
            alpha: try VP9Encoder(
                width: width, height: height, fps: fps, bitsPerSecond: bitsPerSecond,
                picture: .sdr, plane: .alpha, keyInterval: interval))
    }

    func send(_ frame: I010Frame, index: Int64) throws {
        try picture.send(frame, index: index)
        try alpha.send(frame, index: index)
    }

    func sendEndOfStream() throws {
        try picture.sendEndOfStream()
        try alpha.sendEndOfStream()
    }

    /// The next frame both streams have answered, the alpha's bytes in its `alpha`; nil when
    /// either has nothing ready (`wait` false) or both are drained (`wait` true).
    func nextPacket(wait: Bool) throws -> ExportEncodedPacket? {
        while let packet = try picture.nextPacket(wait: false) { pictures.append(packet) }
        while let packet = try alpha.nextPacket(wait: false) { alphas.append(packet) }
        if wait {
            if pictures.isEmpty, !pictureDrained {
                if let packet = try picture.nextPacket(wait: true) {
                    pictures.append(packet)
                } else {
                    pictureDrained = true
                }
            }
            if alphas.isEmpty, !alphaDrained {
                if let packet = try alpha.nextPacket(wait: true) {
                    alphas.append(packet)
                } else {
                    alphaDrained = true
                }
            }
        }
        return try Self.pair(&pictures, &alphas, drained: pictureDrained || alphaDrained)
    }

    func containerBytes(_ data: Data) throws -> Data {
        try picture.containerBytes(data)
    }

    /// The oldest picture packet with the oldest alpha packet, both taken from their queues;
    /// nil when either queue is empty and the streams are not `drained`, or both are empty. A
    /// pts or key disagreement, or one stream ending before the other, throws.
    static func pair(
        _ pictures: inout [ExportEncodedPacket], _ alphas: inout [ExportEncodedPacket],
        drained: Bool
    ) throws -> ExportEncodedPacket? {
        guard let p = pictures.first, let a = alphas.first else {
            guard drained, let left = pictures.first ?? alphas.first else { return nil }
            let which = pictures.isEmpty ? "alpha stream" : "picture"
            throw Exporter.ExportError.failed(
                "libvpx's \(which) answered frame \(left.pts) after the other stream ended.")
        }
        guard a.pts == p.pts else {
            throw Exporter.ExportError.failed(
                "libvpx's alpha stream answered frame \(a.pts) where the picture's answered "
                    + "\(p.pts).")
        }
        guard a.isKey == p.isKey else {
            throw Exporter.ExportError.failed(
                "libvpx's alpha frame \(p.pts) and picture frame \(p.pts) disagree on being a "
                    + "keyframe.")
        }
        pictures.removeFirst()
        alphas.removeFirst()
        return ExportEncodedPacket(
            data: p.data, pts: p.pts, isLast: p.isLast, isKey: p.isKey, alpha: a.data)
    }
}
