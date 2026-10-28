import Foundation

/// libvpx v1.17.0's VP9, the `vp9_webm` row's encoder (spec §11 CX-3, CX-4, CX-16): one context
/// per export, configured once, fed video-range pictures and drained of packets.
///
/// **Owned by one serial queue.** `ExportEncodePump`'s encode queue makes every call after
/// `init` — `send`, `sendEndOfStream`, `nextPacket` and the `deinit` — so the context is never
/// touched from two threads; libvpx runs its own worker threads (`g_threads`, row-mt) behind
/// it.
///
/// **The configuration** (CX-16 (2)–(7)): `VPX_DL_GOOD_QUALITY` at cpu-used 4 with row-mt, the
/// one speed (CX-3); the depth by picture — Profile 0, 8-bit I420 for `sdr`, Profile 2, 10-bit
/// I010 (`VPX_IMG_FMT_I42016`) for `hlg` and `pq` — with the matrix's colour space in studio
/// range; a keyframe at least every 2 s (`kf_max_dist` ⌊2·fps⌋); a 25-frame lag with alt-refs,
/// two log2 tile columns; and capped constant quality: `VPX_CQ` at the table's CQ level with
/// the cap as the target, libvpx's own 25 % overshoot. VP9's bitstream carries no transfer, so
/// the WebM `Colour` is the picture's only label (`ExportWebMLayout`).
///
/// **Packets.** libvpx packs a hidden alt-ref into the next shown frame's superframe, so each
/// packet is one shown frame at the pts (the frame index, timebase 1/fps) it was sent with.
/// They are collected after each `vpx_codec_encode` into `pending`; the end of stream encodes
/// NULL until no packet comes out.
///
/// **`vp9_alpha_webm`** (CX-17 (3), (4)) runs two of these (`VP9AlphaEncoder`): the picture as
/// above, and the alpha (`Plane.alpha`), which encodes the frame's alpha planes at constant
/// quality (`VPX_Q` at `alphaCQLevel(pixels:)`, banded by size) in full range. Both take a
/// `keyInterval`: `kf_min_dist` = `kf_max_dist` = it, and every frame whose index is a
/// multiple of it is forced a key, so the two streams' keys fall on the same frames.
final class VP9Encoder: ExportVideoEncoder {
    /// Which planes of a frame an encoder encodes: the picture's (Y, Cb, Cr) or the alpha's
    /// (`I010Frame.alphaOffset`, with the constant chroma at `alphaChromaOffset`).
    enum Plane {
        case picture, alpha
    }

    let name = "libvpx"

    private var context = vpx_codec_ctx_t()
    private var image = vpx_image_t()
    private var open = false
    private let format: vpx_img_fmt_t
    private let bytesPerSample: Int
    private let bitDepth: Int
    /// The packets libvpx has answered and the pump has not yet taken, oldest first.
    private var pending: [ExportEncodedPacket] = []
    private var flushing = false
    private var drained = false
    /// Set after the first failed call: nothing more is asked of the context but its teardown.
    private var broken = false
    private let plane: Plane
    /// The forced key interval in frames, nil for CX-16 (6)'s automatic keys.
    private let keyInterval: Int?

    init(
        width: Int, height: Int, fps: Fps, bitsPerSecond: Int, picture: ExportAV1Picture,
        plane: Plane = .picture, keyInterval: Int? = nil
    ) throws {
        self.plane = plane
        self.keyInterval = keyInterval.map { max(1, $0) }
        let depth = Self.bitDepth(for: picture)
        bitDepth = depth
        bytesPerSample = depth > 8 ? 2 : 1
        format = depth > 8 ? VPX_IMG_FMT_I42016 : VPX_IMG_FMT_I420
        var config = vpx_codec_enc_cfg_t()
        try Self.check(
            vpx_codec_enc_config_default(vpx_codec_vp9_cx(), &config, 0),
            "vpx_codec_enc_config_default", context: nil)
        config.g_w = UInt32(clamping: width)
        config.g_h = UInt32(clamping: height)
        // Timebase 1/fps: a frame's pts is its index and its duration 1.
        config.g_timebase = vpx_rational(
            num: Int32(clamping: max(1, fps.den)), den: Int32(clamping: max(1, fps.num)))
        config.g_threads = UInt32(clamping: ProcessInfo.processInfo.activeProcessorCount)
        config.g_pass = VPX_RC_ONE_PASS
        config.g_lag_in_frames = 25
        // The depth (CX-16 (3)): libvpx's `validate_config` refuses a depth above 8 at a
        // profile below 2.
        config.g_profile = depth > 8 ? 2 : 0
        config.g_bit_depth = depth > 8 ? VPX_BITS_10 : VPX_BITS_8
        config.g_input_bit_depth = UInt32(depth)
        // Capped CQ (CX-16 (7)): the cap in kb/s as the target, libvpx's default
        // over- and undershoot (25 / 25).
        let cap = max(1, bitsPerSecond)
        // The alpha is constant quality with no cap (CX-17 (3)).
        config.rc_end_usage = plane == .alpha ? VPX_Q : VPX_CQ
        config.rc_target_bitrate = UInt32(max(1, (Double(cap) / 1000).rounded()))
        // A keyframe at least every 2 s (CX-16 (6)).
        let perSecond = fps.den > 0 ? Double(fps.num) / Double(fps.den) : 30
        config.kf_mode = VPX_KF_AUTO
        config.kf_min_dist = 0
        config.kf_max_dist = UInt32(max(1, (2 * perSecond).rounded(.down)))
        // Keys at fixed frames (CX-17 (4)), the two alpha row's streams alike.
        if let interval = self.keyInterval {
            config.kf_min_dist = UInt32(clamping: interval)
            config.kf_max_dist = UInt32(clamping: interval)
        }
        let flags = depth > 8 ? vpx_codec_flags_t(VPX_CODEC_USE_HIGHBITDEPTH) : 0
        try Self.check(
            framejob_vpx_vp9_enc_init(&context, &config, flags), "vpx_codec_enc_init",
            context: nil)
        open = true
        let pixels = Double(max(1, width * height)) * (perSecond > 0 ? perSecond : 30)
        let range = plane == .alpha ? VPX_CR_FULL_RANGE : VPX_CR_STUDIO_RANGE
        let level = plane == .alpha
            ? Self.alphaCQLevel(pixels: width * height)
            : Int32(Self.cqLevel(bitDepth: depth, bitsPerPixel: Double(cap) / pixels))
        let controls: [(vp8e_enc_control_id, Int32)] = [
            (VP8E_SET_CPUUSED, 4),
            (VP9E_SET_ROW_MT, 1),
            (VP8E_SET_ENABLEAUTOALTREF, 1),
            (VP9E_SET_TILE_COLUMNS, 2),
            (VP9E_SET_FRAME_PARALLEL_DECODING, 0),
            (VP8E_SET_CQ_LEVEL, level),
            (VP9E_SET_COLOR_SPACE,
             Int32((picture == .sdr ? VPX_CS_BT_709 : VPX_CS_BT_2020).rawValue)),
            (VP9E_SET_COLOR_RANGE, Int32(range.rawValue)),
        ]
        for (id, value) in controls {
            try Self.check(
                framejob_vpx_control_int(&context, Int32(id.rawValue), value),
                "vpx_codec_control \(id.rawValue)", context: &context)
        }
        // The image header `send` points at each frame's planes: 4:2:0 at the export size,
        // the picture's colour space in studio range, the alpha in full (no storage of its
        // own).
        image.fmt = format
        image.cs = picture == .sdr ? VPX_CS_BT_709 : VPX_CS_BT_2020
        image.range = range
        image.w = UInt32(clamping: width)
        image.h = UInt32(clamping: height)
        image.d_w = image.w
        image.d_h = image.h
        image.bit_depth = UInt32(depth)
        image.x_chroma_shift = 1
        image.y_chroma_shift = 1
        image.bps = depth > 8 ? 24 : 12
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("VP9Encoder does not support NSCoder")
    }

    deinit {
        if open { _ = vpx_codec_destroy(&context) }
    }

    /// The picture's depth (CX-16 (3)): 8 for the SDR picture, 10 for HLG and PQ.
    static func bitDepth(for picture: ExportAV1Picture) -> Int {
        picture == .sdr ? 8 : 10
    }

    /// The forced key interval of `vp9_alpha_webm`'s two streams (CX-17 (4)): ⌊2·fps⌋ frames,
    /// at least 1.
    static func keyInterval(fps: Fps) -> Int {
        let perSecond = fps.den > 0 ? Double(fps.num) / Double(fps.den) : 30
        return max(1, Int((2 * perSecond).rounded(.down)))
    }

    /// VP9's packets go into the WebM as libvpx wrote them.
    func containerBytes(_ data: Data) throws -> Data {
        data
    }

    /// Sends one picture; libvpx copies its planes into its lookahead, so `frame` may be reused
    /// once this returns. Strides go in bytes, the planes where the converter put them.
    func send(_ frame: I010Frame, index: Int64) throws {
        guard open, !broken, !flushing else { throw Self.stopped }
        guard frame.bitDepth == bitDepth else {
            broken = true
            throw Exporter.ExportError.failed(
                "The VP9 encoder was opened for \(bitDepth)-bit pictures and was sent a "
                    + "\(frame.bitDepth)-bit one.")
        }
        let base = frame.buffer.contents().assumingMemoryBound(to: UInt8.self)
        let offsets: (Int, Int, Int)
        switch plane {
        case .picture:
            offsets = (0, frame.cbOffset, frame.crOffset)
        case .alpha:
            guard let alpha = frame.alphaOffset, let chroma = frame.alphaChromaOffset else {
                broken = true
                throw Exporter.ExportError.failed(
                    "The VP9 alpha encoder was sent a frame with no alpha planes.")
            }
            offsets = (alpha, chroma, chroma)
        }
        image.planes.0 = base + bytesPerSample * offsets.0
        image.planes.1 = base + bytesPerSample * offsets.1
        image.planes.2 = base + bytesPerSample * offsets.2
        image.stride.0 = Int32(bytesPerSample * frame.lumaStride)
        image.stride.1 = Int32(bytesPerSample * frame.chromaStride)
        image.stride.2 = Int32(bytesPerSample * frame.chromaStride)
        let forced = keyInterval.map { index % Int64($0) == 0 } ?? false
        let flags = forced ? vpx_enc_frame_flags_t(VPX_EFLAG_FORCE_KF) : 0
        try record(
            vpx_codec_encode(&context, &image, index, 1, flags, UInt(VPX_DL_GOOD_QUALITY)),
            "vpx_codec_encode")
        collect()
    }

    /// No picture follows: `nextPacket(wait: true)` encodes NULL until libvpx answers nothing.
    func sendEndOfStream() throws {
        guard open, !broken else { throw Self.stopped }
        flushing = true
    }

    /// The next packet: the oldest pending one. `wait` true, after `sendEndOfStream`, flushes
    /// libvpx until a packet comes out or none is left, then answers nil.
    func nextPacket(wait: Bool) throws -> ExportEncodedPacket? {
        guard open, !broken else { throw Self.stopped }
        while pending.isEmpty, wait, flushing, !drained {
            try record(
                vpx_codec_encode(&context, nil, 0, 1, 0, UInt(VPX_DL_GOOD_QUALITY)),
                "vpx_codec_encode")
            if !collect() { drained = true }
        }
        return pending.isEmpty ? nil : pending.removeFirst()
    }

    /// Every frame packet libvpx has ready into `pending`; whether there was one.
    @discardableResult
    private func collect() -> Bool {
        var iterator: vpx_codec_iter_t?
        var any = false
        while let packet = vpx_codec_get_cx_data(&context, &iterator) {
            guard packet.pointee.kind == VPX_CODEC_CX_FRAME_PKT else { continue }
            let frame = packet.pointee.data.frame
            let data = frame.buf.map { Data(bytes: $0, count: frame.sz) } ?? Data()
            pending.append(ExportEncodedPacket(
                data: data, pts: frame.pts, isLast: false,
                isKey: frame.flags & vpx_codec_frame_flags_t(VPX_FRAME_IS_KEY) != 0))
            any = true
        }
        return any
    }

    // MARK: - The rate (CX-16 (7))

    /// CX-16 (8)'s calibration: at each cap in bits per pixel per frame (CX-13's five points,
    /// the Quality tiers' and "Format default"'s at 1080p30), the highest CQ level at which VP9
    /// reached VMAF ≥ the comparator's at that rate under the real cap — `hevc` for the 8-bit
    /// column (the lower of the spike's three clips and the owner's clip through this app; the
    /// owner's binds every point), `hevc_10bit` at `hlg` for the 10-bit one (the owner's clip
    /// in an HLG project).
    private static let calibration: [(bitsPerPixel: Double, cq: [Int: Double])] = [
        (0.0386, [8: 34, 10: 34]),
        (0.0579, [8: 26, 10: 28]),
        (0.0700, [8: 20, 10: 24]),
        (0.0772, [8: 18, 10: 24]),
        (0.1157, [8: 14, 10: 20]),
    ]

    /// The alpha stream's CQ level at `VPX_Q` by picture size (CX-17 (6) as amended): per band,
    /// from its pixel count up, the highest level at which every frame of the moving-disc
    /// fixture kept an alpha PSNR of at least 48.0 dB at that size through `vpxenc` (worst
    /// 48.14, 48.66, 48.91 and 48.18 dB), a smaller picture's edge being a larger share of it.
    static let alphaCQBands: [(pixels: Int, level: Int32)] = [
        (640 * 360, 34), (1280 * 720, 38), (1920 * 1080, 40), (3840 * 2160, 46),
    ]

    /// The band at or below `pixels`; below the smallest band, the smallest band's level.
    static func alphaCQLevel(pixels: Int) -> Int32 {
        let band = alphaCQBands.last(where: { $0.pixels <= pixels }) ?? alphaCQBands[0]
        return band.level
    }

    /// The CQ level at `bitDepth` for a cap of `bitsPerPixel`: linear between the calibrated
    /// points, rounded down, and the end point's beyond either end (`ExportRateTable`).
    static func cqLevel(bitDepth: Int, bitsPerPixel: Double) -> UInt32 {
        let column = bitDepth > 8 ? 10 : 8
        return ExportRateTable.value(
            at: bitsPerPixel,
            points: calibration.map { (bitsPerPixel: $0.bitsPerPixel, value: $0.cq[column] ?? 32) })
    }

    // MARK: - Errors

    private static let stopped = Exporter.ExportError.failed(
        "libvpx stopped after an earlier error.")

    private func record(_ answer: vpx_codec_err_t, _ step: String) throws {
        guard answer != VPX_CODEC_OK else { return }
        broken = true
        throw Exporter.ExportError.failed(
            "libvpx failed: \(step) answered \(answer.rawValue): \(Self.detail(answer, &context)).")
    }

    private static func check(
        _ answer: vpx_codec_err_t, _ step: String, context: UnsafeMutablePointer<vpx_codec_ctx_t>?
    ) throws {
        guard answer != VPX_CODEC_OK else { return }
        throw Exporter.ExportError.failed(
            "libvpx could not start: \(step) answered \(answer.rawValue): "
                + "\(detail(answer, context)).")
    }

    /// libvpx's own detail for the context's last error, else the error's name.
    private static func detail(
        _ answer: vpx_codec_err_t, _ context: UnsafeMutablePointer<vpx_codec_ctx_t>?
    ) -> String {
        if let context, let text = vpx_codec_error_detail(context) {
            return String(cString: text)
        }
        return vpx_codec_err_to_string(answer).map { String(cString: $0) } ?? "no detail"
    }
}
