import Foundation

/// SVT-AV1 v4.2.0, the `av1` row's encoder (spec §11 CX-2, CX-4, CX-12, CX-14): one handle
/// per export, configured once, fed video-range I010 pictures and drained of packets.
///
/// **Owned by one serial queue.** `ExportEncodePump`'s encode queue makes every call after
/// `init` — `send`, `sendEndOfStream`, `nextPacket` and the `deinit` — so the handle is
/// never touched from two threads; SVT runs its own worker threads behind it.
///
/// **The configuration** (CX-12 (2), (3); CX-13): the sheet's speed as SVT's preset (8, 6 or
/// 4), capped CRF — a constant quality matched to HEVC's at the cap, which is the settings'
/// rate or HEVC's 0.07 bits per pixel per frame — a closed GOP (`SVT_AV1_KF_REFRESH`) with a
/// keyframe at least every 2 s, 10-bit Main 4:2:0, and the picture's primaries, transfer
/// and matrix in video range written into the sequence header (CX-14 (4)): BT.709's for the
/// SDR picture, BT.2020 with HLG or PQ for the HDR ones. On PQ alone, HD-5's fixed mastering
/// display and content light level, which SVT writes as metadata OBUs on each KEY_FRAME
/// (CX-14 (5)).
final class SVTAV1Encoder {
    /// One packet as SVT answered it: its bytes (temporal delimiters still in), the `pts` the
    /// picture was sent with, and whether it is the last.
    struct Packet {
        let data: Data
        let pts: Int64
        let isLast: Bool
    }

    /// The sequence header OBU (`svt_av1_enc_stream_header`), the `av1C` record's source.
    let sequenceHeader: Data

    private var handle: UnsafeMutablePointer<EbComponentType>?
    /// Set after the first failed call: nothing more is asked of the handle but its teardown.
    private var broken = false

    init(
        width: Int, height: Int, fps: Fps, bitsPerSecond: Int, speed: EncoderSpeed,
        picture: ExportAV1Picture
    ) throws {
        _ = Self.installLogCallback
        var config = EbSvtAv1EncConfiguration()
        var opened: UnsafeMutablePointer<EbComponentType>?
        try Self.check(svt_av1_enc_init_handle(&opened, &config), "svt_av1_enc_init_handle")
        guard let opened else {
            throw Exporter.ExportError.failed("SVT-AV1 could not start: no handle was made.")
        }
        config.enc_mode = speed.svtPreset
        config.source_width = UInt32(clamping: width)
        config.source_height = UInt32(clamping: height)
        config.frame_rate_numerator = UInt32(clamping: fps.num)
        config.frame_rate_denominator = UInt32(clamping: fps.den)
        config.encoder_bit_depth = 10
        config.encoder_color_format = EB_YUV420
        config.profile = MAIN_PROFILE
        // Capped CRF (CX-13): what SVT's own `--crf` sets, and the cap as `max_bit_rate`.
        let cap = min(max(1, bitsPerSecond), Self.maxCap)
        config.rate_control_mode = UInt8(SVT_AV1_RC_MODE_CQP_OR_CRF.rawValue)
        config.aq_mode = 2
        config.qp = Self.crf(speed: speed, bitsPerPixel: Double(cap)
            / (Double(max(1, width * height)) * (fps.double > 0 ? fps.double : 30)))
        config.max_bit_rate = UInt32(cap)
        // SVT-AV1 v4.2.0's own default (`EbSvtAv1Enc.h`, `enc_settings.c`): a soft cap that
        // hard footage may exceed, the owner's "quality first" (CX-13 (1)).
        config.mbr_over_shoot_pct = 50
        // Closed GOP, and a keyframe at least every 2 s: the period is ⌊2·fps⌋ frames.
        config.intra_refresh_type = SVT_AV1_KF_REFRESH
        let perSecond = fps.den > 0 ? Double(fps.num) / Double(fps.den) : 30
        config.intra_period_length = Int32(max(1, (2 * perSecond).rounded(.down))) - 1
        config.color_primaries = picture.primaries
        config.transfer_characteristics = picture.transfer
        config.matrix_coefficients = picture.matrix
        config.color_range = EB_CR_STUDIO_RANGE
        do {
            if picture.carriesHDR10 {
                try Self.setHDR10(&config)
            }
            sequenceHeader = try Self.start(opened, &config)
        } catch {
            _ = svt_av1_enc_deinit(opened)
            _ = svt_av1_enc_deinit_handle(opened)
            throw error
        }
        handle = opened
    }

    /// HD-5's fixed HDR10 metadata into the configuration, from `ExportAV1Picture`'s strings.
    private static func setHDR10(_ config: inout EbSvtAv1EncConfiguration) throws {
        guard svt_aom_parse_mastering_display(
            &config.mastering_display, ExportAV1Picture.masteringDisplay) != 0,
            svt_aom_parse_content_light_level(
                &config.content_light_level, ExportAV1Picture.contentLightLevel) != 0
        else {
            throw Exporter.ExportError.failed(
                "SVT-AV1 could not start: the HDR10 metadata could not be set.")
        }
    }

    /// Configures and starts the handle, answering its sequence header.
    private static func start(
        _ handle: UnsafeMutablePointer<EbComponentType>, _ config: inout EbSvtAv1EncConfiguration
    ) throws -> Data {
        try check(svt_av1_enc_set_parameter(handle, &config), "svt_av1_enc_set_parameter")
        try check(svt_av1_enc_init(handle), "svt_av1_enc_init")
        var header: UnsafeMutablePointer<EbBufferHeaderType>?
        try check(svt_av1_enc_stream_header(handle, &header), "svt_av1_enc_stream_header")
        guard let header, let bytes = header.pointee.p_buffer else {
            throw Exporter.ExportError.failed("SVT-AV1 could not start: it wrote no stream header.")
        }
        defer { _ = svt_av1_enc_stream_header_release(header) }
        return Data(bytes: bytes, count: Int(header.pointee.n_filled_len))
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("SVTAV1Encoder does not support NSCoder")
    }

    deinit {
        guard let handle else { return }
        _ = svt_av1_enc_deinit(handle)
        _ = svt_av1_enc_deinit_handle(handle)
    }

    /// Sends one picture; SVT copies its planes, so `frame` may be reused once this returns.
    /// SVT reads a 10-bit plane as `uint16_t` from the byte pointer it is given, its stride in
    /// samples (`enc_handle.c`, `copy_frame_buffer`), so each plane starts two bytes per sample
    /// in and the strides go as they are.
    func send(_ frame: I010Frame, index: Int64) throws {
        guard let handle, !broken else { throw Self.stopped }
        let base = frame.buffer.contents().assumingMemoryBound(to: UInt8.self)
        var planes = EbSvtIOFormat(
            luma: base, cb: base + 2 * frame.cbOffset, cr: base + 2 * frame.crOffset,
            y_stride: UInt32(frame.lumaStride), cr_stride: UInt32(frame.chromaStride),
            cb_stride: UInt32(frame.chromaStride))
        try withUnsafeMutablePointer(to: &planes) { io in
            var picture = EbBufferHeaderType()
            picture.size = UInt32(MemoryLayout<EbBufferHeaderType>.size)
            picture.p_buffer = UnsafeMutableRawPointer(io).assumingMemoryBound(to: UInt8.self)
            let chroma = frame.chromaStride * ((frame.height + 1) / 2)
            picture.n_filled_len = UInt32(2 * (frame.lumaStride * frame.height + 2 * chroma))
            picture.n_alloc_len = picture.n_filled_len
            picture.pts = index
            picture.pic_type = EB_AV1_INVALID_PICTURE
            try record(svt_av1_enc_send_picture(handle, &picture), "svt_av1_enc_send_picture")
        }
    }

    /// Tells SVT no picture follows, so `nextPacket(wait: true)` drains to the last packet.
    func sendEndOfStream() throws {
        guard let handle, !broken else { throw Self.stopped }
        var end = EbBufferHeaderType()
        end.size = UInt32(MemoryLayout<EbBufferHeaderType>.size)
        end.flags = UInt32(EB_BUFFERFLAG_EOS)
        end.pic_type = EB_AV1_INVALID_PICTURE
        try record(svt_av1_enc_send_picture(handle, &end), "svt_av1_enc_send_picture")
    }

    /// The next packet: nil when none is ready (`wait` false); `wait` true blocks until one
    /// is, which is only asked after `sendEndOfStream`.
    func nextPacket(wait: Bool) throws -> Packet? {
        guard let handle, !broken else { throw Self.stopped }
        var out: UnsafeMutablePointer<EbBufferHeaderType>?
        let answer = svt_av1_enc_get_packet(handle, &out, wait ? 1 : 0)
        if answer == EB_NoErrorEmptyQueue { return nil }
        try record(answer, "svt_av1_enc_get_packet")
        guard let header = out?.pointee else { return nil }
        defer { svt_av1_enc_release_out_buffer(&out) }
        let length = Int(header.n_filled_len)
        let data = header.p_buffer.map { Data(bytes: $0, count: length) } ?? Data()
        return Packet(
            data: data, pts: header.pts, isLast: header.flags & UInt32(EB_BUFFERFLAG_EOS) != 0)
    }

    // MARK: - The rate (CX-13)

    /// SVT-AV1's largest `max_bit_rate`, 100,000 kb/s.
    private static let maxCap = 100_000_000

    /// CX-13 (3)'s calibration, CX-14 (6)'s at 10 bits: at each cap in bits per pixel per
    /// frame (the Quality tiers' and "Format default"'s at 1080p30), the highest CRF at which
    /// each speed reached VMAF ≥ HEVC's at that rate on every calibration clip — the spike's
    /// three 8-bit clips against 8-bit HEVC, and the owner's 55 s clip through this app at
    /// 10 bits against `hevc_10bit` — Faster, Balanced, Smaller file.
    private static let calibration: [(bitsPerPixel: Double, crf: [EncoderSpeed: Double])] = [
        (0.0386, [.faster: 36, .balanced: 36, .smaller: 36]),
        (0.0579, [.faster: 26, .balanced: 28, .smaller: 28]),
        (0.0700, [.faster: 22, .balanced: 24, .smaller: 24]),
        (0.0772, [.faster: 20, .balanced: 24, .smaller: 24]),
        (0.1157, [.faster: 12, .balanced: 16, .smaller: 16]),
    ]

    /// The CRF for `speed` at a cap of `bitsPerPixel`: linear between the calibrated points,
    /// rounded down, and the end point's beyond either end.
    static func crf(speed: EncoderSpeed, bitsPerPixel: Double) -> UInt32 {
        let points = calibration.map { ($0.bitsPerPixel, $0.crf[speed] ?? 32) }
        guard let first = points.first, let last = points.last else { return 32 }
        if !(bitsPerPixel > first.0) { return UInt32(first.1) }
        if bitsPerPixel >= last.0 { return UInt32(last.1) }
        for (low, high) in zip(points, points.dropFirst()) where bitsPerPixel < high.0 {
            let share = (bitsPerPixel - low.0) / (high.0 - low.0)
            return UInt32((low.1 + share * (high.1 - low.1)).rounded(.down))
        }
        return UInt32(last.1)
    }

    // MARK: - Errors and the log

    private static let stopped = Exporter.ExportError.failed(
        "SVT-AV1 stopped after an earlier error.")

    private func record(_ answer: EbErrorType, _ step: String) throws {
        guard answer != EB_ErrorNone else { return }
        broken = true
        throw Exporter.ExportError.failed("SVT-AV1 failed: \(step) answered \(Self.hex(answer)).")
    }

    private static func check(_ answer: EbErrorType, _ step: String) throws {
        guard answer != EB_ErrorNone else { return }
        throw Exporter.ExportError.failed(
            "SVT-AV1 could not start: \(step) answered \(hex(answer)).")
    }

    private static func hex(_ answer: EbErrorType) -> String {
        "0x" + String(UInt32(bitPattern: answer.rawValue), radix: 16)
    }

    /// SVT's log through its callback (spec §11 CX-12 (6)), installed once per process before
    /// the first `svt_av1_enc_init_handle`, which finalises the library's logging: info and
    /// debug dropped, warnings and errors as `SVT-AV1: …` lines in the system log.
    private static let installLogCallback: Void = {
        svt_av1_set_log_callback({ _, level, _, format, arguments in
            guard level.rawValue >= 0, level.rawValue <= SVT_AV1_LOG_WARN.rawValue, let format,
                let arguments
            else { return }
            var text = [CChar](repeating: 0, count: 1024)
            _ = vsnprintf(&text, text.count, format, arguments)
            let line = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
            NSLog("SVT-AV1: %@", line)
        }, nil)
    }()
}
