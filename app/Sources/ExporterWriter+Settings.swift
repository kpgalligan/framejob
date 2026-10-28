import AVFoundation
import VideoToolbox

// `ExportWriter`'s settings half: what an `ExportSettings` row becomes in
// AVFoundation's own terms — the video composition, the alpha guard, the
// encoder dictionaries for the picture and the sound, and which containers
// carry chapters. A pure move out of `ExporterWriter.swift` at its size cap
// (issue batch B60); the members `ExporterWriter.swift` calls lost
// `private`, and nothing else changed.
extension ExportWriter {

    // MARK: - Settings → AVFoundation

    /// The video composition to render through: the one the plan built,
    /// unless the settings ask for a different frame rate.
    ///
    /// `CompositionBuilder` ticks the composition at the PROJECT's rate, and
    /// the sheet's Frame-rate popup overrides `settings.fps` — which the
    /// session path could not honour at all (a preset name carries no rate),
    /// so the readout promised 25 fps and the file held 30. The builder's
    /// configuration with the asked-for `frameDuration` samples the same
    /// timeline at the asked-for instants (#91); the recipes are evaluated per
    /// frame at whatever tick is requested, so nothing else has to know.
    static func videoComposition(
        _ built: BuiltComposition, settings: ExportSettings
    ) -> AVVideoComposition {
        let fps = settings.fps
        var configuration = built.videoConfiguration
        guard fps.num > 0, fps.den > 0 else { return built.videoComposition }
        configuration.frameDuration = CompositionBuilder.frameDuration(fps)
        guard configuration.frameDuration != built.videoConfiguration.frameDuration
        else { return built.videoComposition }
        return AVVideoComposition(configuration: configuration)
    }

    /// Refuses an alpha-carrying export whose size would have to be PADDED
    /// (road map 2, phase 7b; `Exporter.ExportError.alphaAspectMismatch`
    /// carries the argument and the measurement).
    ///
    /// The composition renders at the canvas size and
    /// `AVVideoScalingModeResizeAspect` fits it into the asked-for frame —
    /// which is right for an opaque row, and destroys the alpha channel
    /// when it has to pad: the picture comes back at alpha 0 and the bars at
    /// alpha 255, the answer inverted. A pure SCALE is safe at any factor,
    /// up or down, so what is refused is the shape change and not the
    /// resize.
    ///
    /// The test is `shapeGap`'s, the one `fillsTheBox` asks too (spec §11
    /// G-33 (c)): a frame of the canvas's exact shape is written as it is, a
    /// frame within a pixel of it is FILLED, and only a frame further off —
    /// `gap > limit` — would be padded, which is what is refused here. So an
    /// alpha row is exact or filled and never padded, and it reaches
    /// `hevc_alpha` as it reaches `prores_4444`, because the row's `alpha`
    /// is true.
    ///
    /// **The box is `encodedSize`'s and not `settings`'.** The encoder is
    /// handed `AVVideoWidthKey`/`AVVideoHeightKey`, and it is that frame's
    /// shape the picture has to meet. On settings the core resolved the two
    /// are one pair (G-33 (b): the core evens the size on the rows that need
    /// it, and ProRes 4444 keeps an odd edge), so asking `encodedSize` is the
    /// floor under any other caller: a rounding there moves the box, and a
    /// comparison against `settings` would not see it. An odd-edged
    /// transparent document is legal — `set_canvas` refuses an odd dimension,
    /// `Project::new` and `validate` do not, so an odd-sized PNG opened as a
    /// document or an odd display size gets one — and at 1001 × 667 its
    /// Document row is 1001 × 667 on ProRes 4444, the canvas's exact shape,
    /// and the evened 1000 × 666 on `hevc_alpha`, within a pixel and filled.
    ///
    /// **The pixel of slack does not cost an edge.** It is there for
    /// `export_size.rs`'s even-rounding — a standard row's long edge, the
    /// evened Document row on a canvas with an odd edge, and an odd size
    /// typed in the canvas's proportions can each miss the canvas's exact
    /// shape by a pixel, and refusing them would be a false refusal. A frame
    /// inside the slack is FILLED (`videoSettings`),
    /// so every edge of it is the picture's; fitted, the pad put an edge
    /// column at the backdrop's alpha instead (ProRes 4444 at 255,
    /// `hevc_alpha` up to 16, where the canvas is transparent — G-33 (c)).
    /// `hevc_alpha_proof.py`'s rows O1, O4, O5, P1 and P2 read all four
    /// edges of such files at alpha 0.
    static func checkAlphaSurvivesTheSize(
        _ settings: ExportSettings, canvas: CGSize
    ) throws {
        guard settings.alpha, canvas.width >= 1, canvas.height >= 1,
            settings.width >= 1, settings.height >= 1
        else { return }
        let shape = shapeGap(encodedSize(settings), canvas: canvas)
        guard shape.gap > shape.limit else { return }
        // The MESSAGE names `settings`' size and not the box. That is the
        // size the core RESOLVED (spec §11 G-33): on ProRes 4444, which
        // keeps an odd edge, the pair that was asked for — so the sentence
        // still tells the person what to type instead, with no number in it
        // they never typed — and on a row the core evens, the even pair the
        // sheet and the `export` tool reported.
        throw Exporter.ExportError.alphaAspectMismatch(
            width: Int(canvas.width.rounded()), height: Int(canvas.height.rounded()),
            wantWidth: settings.width, wantHeight: settings.height)
    }

    /// How far a frame is from the canvas's shape, and how far counts as
    /// "within a pixel" — the ONE shape test, in integers, which the alpha
    /// guard and the scaling mode both ask (spec §11 G-33 (c)). Nothing else
    /// compares shapes.
    ///
    /// With `cw` × `ch` the canvas and `bw` × `bh` the frame,
    /// `d = bw·ch − bh·cw` and `gap = |d|`; 0 is the canvas's exact shape.
    /// When `d > 0` the frame is wider than the canvas's shape: a fit leaves
    /// `gap/ch` px of width uncovered and a fill overshoots the height by
    /// `gap/cw` px; when `d < 0` it is the other way round. `limit` has two
    /// arms. A canvas-SHAPED size less at most one pixel on each axis —
    /// `(bw + a)·ch == (bh + b)·cw` for some `a`, `b` in {0, 1}: the evened
    /// Document row, an odd size typed in the canvas's own proportions once
    /// the core has evened it (720 × 405 on 1920 × 1080 arrives as
    /// 720 × 404), and on ProRes 4444 a typed frame one pixel short —
    /// `max(cw, ch)`: the fit leaves at most a pixel OR the fill overshoots
    /// by at most one. There `gap` is `|b·cw − a·ch|`, never above the
    /// limit, so such a frame is always exact or filled. Any other frame:
    /// `ch` when `d > 0`, else `cw` — the fit leaves at most a pixel, which
    /// is the phase-7b guard in integers. `gap <= limit` is "within a
    /// pixel", and it is `<=` on purpose: an evened canvas whose odd edge is
    /// the SHORT one sits exactly on the limit (181 × 320 into 180 × 320:
    /// gap 320, limit 320).
    ///
    /// The first arm is what lets an evened size through — fitted, it can
    /// miss by more than a pixel (1.77 px at 181 × 320) — at ANY scale,
    /// smaller than the canvas or larger, because a size of the canvas's
    /// shape is never refused for being odd (the owner's answer). Swift is
    /// handed only the even frame, so on 400 × 100 it cannot tell a typed
    /// 396 × 98 or 404 × 100 from an evened 396 × 99 or 404 × 101: those are
    /// filled too, on every row, where they were letterboxed — the costs
    /// G-33 (c) records as accepted. A frame typed to pad the canvas by any
    /// other amount (402 × 100 on 400 × 100: gap 200, limit 100) is
    /// letterboxed as it always was. The quotients are arithmetic, not what
    /// the scaler cuts: it drops whole source pixels and stretches the rest
    /// (G-33 (c) has the measurement).
    private static func shapeGap(
        _ frame: (width: Int, height: Int), canvas: CGSize
    ) -> (gap: Int, limit: Int) {
        let cw = max(1, Int(canvas.width.rounded()))
        let ch = max(1, Int(canvas.height.rounded()))
        let d = frame.width * ch - frame.height * cw
        // (bw + a)·ch == (bh + b)·cw for some a, b in {0, 1} is d == b·cw − a·ch.
        let inside = [0, cw, -ch, cw - ch].contains(d)
        let limit = inside ? max(cw, ch) : (d > 0 ? ch : cw)
        return (abs(d), limit)
    }

    /// Whether the picture FILLS the frame rather than being fitted inside
    /// it: a frame within a pixel of the canvas's shape and not exactly it
    /// (`shapeGap`). No codec is asked — an opaque row fills where it used to
    /// write a black line, an alpha row where it used to write an edge at the
    /// wrong alpha.
    static func fillsTheBox(_ settings: ExportSettings, canvas: CGSize) -> Bool {
        let shape = shapeGap(encodedSize(settings), canvas: canvas)
        return shape.gap > 0 && shape.gap <= shape.limit
    }

    /// The frame the ENCODER is given, and the ONE place that is decided,
    /// because a second opinion about it is exactly what
    /// `checkAlphaSurvivesTheSize` was missing.
    ///
    /// **The core has already evened the size** (spec §11 G-33). On every row
    /// that needs even dimensions `rc_export_settings` resolves an odd edge
    /// one pixel smaller — a standard row, the Document row and a custom size
    /// alike (`export_size.rs`'s `even_size`, which is `evenDimension`'s
    /// arithmetic) — so on what the core answers this function is the
    /// IDENTITY, and the size the sheet, the queue and the `export` tool
    /// report is the frame the file has. The rounding stays as the floor
    /// under any caller that hands in settings the core did not resolve:
    /// H.264 and HEVC require even dimensions whoever asks.
    ///
    /// **ProRes 4444 keeps its odd edges, and that is the fix rather than a
    /// preference.** Rounding an odd edge down moves the box, and a picture
    /// FITTED into the moved box is padded by the pixel the rounding took
    /// away — and padding is the one thing an alpha export cannot survive.
    /// Measured here (macOS 26.5.1, `AVAssetWriter` +
    /// `AVVideoCodecType.proRes4444`): asked for 1001 × 667 the writer
    /// accepts it and the file comes back `prores`, `yuva444p12le`,
    /// 1001 × 667, with the transparent half at alpha 0 and the opaque half
    /// at 255 — exact at every pixel; asked for 1000 × 666 with the same
    /// 1001 × 667 picture, fitted, it came back with its right-hand column
    /// OPAQUE where the canvas is transparent. So the one row that could not
    /// afford the rounding turns out not to need it — and since G-33 a frame
    /// a pixel short is filled rather than fitted, so the master keeps its
    /// odd edge because it can be the document's own pixels, not because the
    /// rounding would still break it.
    /// Every other row keeps the rounding it has always had, ProRes 422
    /// included — it does not need it either (measured: 1001 × 667 survives
    /// as `yuv422p10le`), but changing the bytes a shipped row writes for a
    /// case no proof covers is not this guard's business.
    static func encodedSize(_ settings: ExportSettings) -> (width: Int, height: Int) {
        guard codecType(for: settings.codec) == .proRes4444 else {
            return (evenDimension(settings.width), evenDimension(settings.height))
        }
        return (max(1, settings.width), max(1, settings.height))
    }

    /// The encoder settings for the picture.
    ///
    /// **Size.** The composition renders at the CANVAS size (§7.2), and the
    /// core resolves the export size — the document's unless the sheet's
    /// Size popup, its Custom fields or the `export` tool asked for another
    /// — and they are not the same number; the session path simply dropped
    /// the second one on the floor: the preset scaled to fit whatever it
    /// liked, so the sheet's "1920 × 1080" was a wish. Here the encoder is
    /// told the size the sheet promised, and the scaling mode is one of two
    /// (spec §11 G-33 (c)). A frame of the canvas's exact shape, or one more
    /// than a pixel off it, gets `AVVideoScalingModeResizeAspect`: the canvas
    /// fitted inside, letterboxed rather than distorted when the two shapes
    /// differ. A frame WITHIN a pixel of the canvas's shape (`fillsTheBox`)
    /// gets `AVVideoScalingModeResizeAspectFill`: the picture covers the
    /// frame, where a fit wrote one or two black lines along an edge — the
    /// evened Document row on a canvas with an odd edge, an odd size typed
    /// in the canvas's proportions, and a standard row whose long edge
    /// rounded. The frame itself is `encodedSize`'s answer,
    /// because `checkAlphaSurvivesTheSize` and `fillsTheBox` have to compare
    /// against the same number.
    ///
    /// **HEVC with alpha** is the HEVC row's dictionary — the bit rate, the
    /// key-frame interval, the expected frame rate — plus the one key that
    /// says what the pixels handed to the encoder ARE: straight, because the
    /// video pump un-premultiplies an alpha row's frames first
    /// (`ExportStraightAlpha`, spec §11 G-35 (e), amending G-33 (d)). There
    /// is no alpha-quality key and no profile key (G-33 (d) has what was
    /// measured with and without).
    ///
    /// **Bitrate.** `settings.videoBitrate` when the core resolved one. When
    /// it did not, a rate computed from the frame — bits per pixel per frame,
    /// halved for HEVC — rather than none at all: with no
    /// `AVVideoAverageBitRateKey` VideoToolbox picks a conservative default
    /// that visibly under-runs a 4K timeline. ProRes gets neither: its rate
    /// is a property of the profile.
    static func videoSettings(
        _ settings: ExportSettings, canvas: CGSize
    ) throws -> [String: Any] {
        guard let codec = codecType(for: settings.codec) else {
            throw Exporter.ExportError.presetUnavailable(presetName(settings))
        }
        let frame = encodedSize(settings)
        let fills = fillsTheBox(settings, canvas: canvas)
        var output: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: frame.width,
            AVVideoHeightKey: frame.height,
            AVVideoScalingModeKey: fills
                ? AVVideoScalingModeResizeAspectFill : AVVideoScalingModeResizeAspect,
            // The compositor works in SDR 709 and converts HDR sources itself
            // at step 0 (GR-15, §7.5), so tagging the output 709 is a
            // statement of what the pixels ARE, not a conversion.
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        // An HLG project's 10-bit row (spec §11 HD-13 (j), HD-14 (c), the
        // core's `color`): its pixels are HLG or PQ over BT.2020, and so are
        // its tags; its SDR version (`sdr`) keeps the BT.709 tags above.
        let hlg = settings.color == "hlg"
        let pq = settings.color == "pq"
        if hlg || pq {
            output[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: pq
                    ? AVVideoTransferFunction_SMPTE_ST_2084_PQ : AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
            ]
        }
        // HDR10's fixed metadata (spec §11 HD-5, HD-14 (d)): ProRes takes the
        // two keys as a compression dictionary of their own (measured, M7).
        if pq, codec == .proRes422 || codec == .proRes4444 {
            output[AVVideoCompressionPropertiesKey] = hdr10Metadata
        }
        guard codec != .proRes422, codec != .proRes4444 else { return output }

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: settings.videoBitrate.map { max(1, $0) }
                ?? defaultVideoBitrate(settings, codec: codec),
            // A keyframe at least every two seconds. Deliberate, not a
            // default: an exported movie is scrubbed and re-cut, and
            // VideoToolbox's own interval is long enough to make that
            // painful.
            AVVideoMaxKeyFrameIntervalDurationKey: 2.0,
        ]
        if settings.fps.double > 0 {
            compression[AVVideoExpectedSourceFrameRateKey] = Int(settings.fps.double.rounded())
        }
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        // Pinned to 8-bit Main (spec §11 PR-3): given no profile, VideoToolbox
        // follows its input's format, and the compositor's 16-bit frames
        // gave Main 10. `frameForm` rounds this row's frame to 8 bits as
        // well; the pin is what holds Main if a deep frame ever reaches it.
        // `hevc_10bit` is the same codec pinned to Main 10, fed deep frames.
        if codec == .hevc, isMain10(settings) {
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel as String
        } else if codec == .hevc {
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel as String
        }
        if codec == .hevcWithAlpha {
            compression[kVTCompressionPropertyKey_AlphaChannelMode as String] =
                kVTAlphaChannelMode_StraightAlpha
        }
        // Dolby Vision off (spec §11 HD-5, choice 5a): without the key
        // VideoToolbox adds a profile 8.4 configuration and RPU frames to an
        // HLG HEVC Main 10 file by itself (the brief's M7).
        if hlg, codec == .hevc {
            compression[kVTCompressionPropertyKey_HDRMetadataInsertionMode as String] =
                kVTHDRMetadataInsertionMode_None
        }
        // HDR10's metadata beside the other keys, with NO insertion-mode key:
        // explicit values are written exactly and no Dolby Vision is added
        // (spec §11 HD-14 (f), measured).
        if pq, codec == .hevc {
            compression.merge(hdr10Metadata) { _, metadata in metadata }
        }
        output[AVVideoCompressionPropertiesKey] = compression
        return output
    }

    /// HDR10's mastering display and content light level as VideoToolbox's
    /// two compression keys (`OutputTransform`'s blobs, spec §11 HD-14 (d)).
    static var hdr10Metadata: [String: Any] {
        [
            kVTCompressionPropertyKey_MasteringDisplayColorVolume as String:
                OutputTransform.masteringDisplay,
            kVTCompressionPropertyKey_ContentLightLevelInfo as String:
                OutputTransform.contentLightLevel,
        ]
    }

    /// What the video pump makes of each 64RGBAHalf frame before the encoder
    /// (spec §11 PR-3, `ExportFrames`): `hevc_alpha`'s rounded to 8 bits and
    /// straightened, any other alpha row's (`prores_4444`) straightened in
    /// float, `h264`'s and `hevc`'s rounded to 8 bits; nil hands the frame on
    /// as drawn. The two 8-bit codecs encode a ramp worse from half-float
    /// frames: H.264 8.80 steps RMS against 6.27 from 32BGRA, and `hevc`
    /// (Main) 9.04 against 6.46 (precision PR1). `hevc_10bit` maps to `.hevc`
    /// too, so it is asked by its codec NAME first: Main 10 takes the deep
    /// frames, which is the row's whole point.
    static func frameForm(_ settings: ExportSettings) -> ExportFrameForm? {
        let codec = codecType(for: settings.codec)
        if settings.alpha { return codec == .hevcWithAlpha ? .straightEightBit : .straightHalf }
        if isMain10(settings) { return nil }
        return codec == .h264 || codec == .hevc ? .eightBit : nil
    }

    /// Whether the row is `hevc_10bit` (spec §11 PR-3): `.hevc` with the
    /// Main 10 profile and the compositor's frames as drawn. Asked by the
    /// codec name because `codecType(for:)` answers `.hevc` for both HEVC rows.
    private static func isMain10(_ settings: ExportSettings) -> Bool {
        settings.codec.lowercased() == "hevc_10bit"
    }

    /// The core's codec name as an `AVVideoCodecType`. nil is a refusal, not
    /// a fallback: writing H.264 because "vp9" was not understood would put a
    /// file on disk that is not the one asked for.
    private static func codecType(for codec: String) -> AVVideoCodecType? {
        switch codec.lowercased() {
        case "h264", "avc", "avc1": return .h264
        case "hevc", "h265", "hvc1": return .hevc
        case "hevc_alpha": return .hevcWithAlpha
        case "hevc_10bit": return .hevc
        case "prores_422", "prores", "prores422": return .proRes422
        case "prores_4444", "prores4444": return .proRes4444
        default: return nil
        }
    }

    /// What to call the settings in a refusal: the core's preset id when it
    /// gave one, else the codec that could not be written.
    static func presetName(_ settings: ExportSettings) -> String {
        settings.preset.isEmpty ? settings.codec : settings.preset
    }

    /// Bits per second for a frame of this size at this rate. The constants
    /// are the usual delivery figures — about 9 Mbps for 1080p30 H.264 and
    /// half that for HEVC, with or without alpha — clamped so a tiny canvas
    /// still gets a usable rate and a huge one cannot ask for a file no disk
    /// wants.
    private static func defaultVideoBitrate(
        _ settings: ExportSettings, codec: AVVideoCodecType
    ) -> Int {
        let perPixel = (codec == .hevc || codec == .hevcWithAlpha) ? 0.07 : 0.14
        return defaultVideoBitrate(settings, bitsPerPixel: perPixel)
    }

    /// The same rate at `bitsPerPixel` per frame — the AV1 row's "Format
    /// default" is HEVC's 0.07 (spec §11 CX-9 (2)).
    static func defaultVideoBitrate(_ settings: ExportSettings, bitsPerPixel: Double) -> Int {
        let pixels = Double(max(1, settings.width)) * Double(max(1, settings.height))
        let rate = settings.fps.double > 0 ? settings.fps.double : 30
        return Int(min(max(pixels * rate * bitsPerPixel, 1_000_000), 200_000_000))
    }

    /// Even, and never zero — H.264 and HEVC macroblocks come in pairs.
    /// `encodedSize` is the only caller and says which rows want it.
    private static func evenDimension(_ value: Int) -> Int {
        let clamped = max(2, value)
        return clamped - (clamped % 2)
    }

    /// What comes OUT of the mix for an export with no gain: 16-bit
    /// interleaved LPCM. The same format the ProRes path writes, and one
    /// every encoder here takes without a conversion in between.
    ///
    /// **It SATURATES.** A mix past full scale written with no gain is
    /// clipped here, and `ExportLoudness.mixClipped` reports it. A gained
    /// export does not read this dictionary: it reads the float mix the
    /// measurement read and `ExportAudioGain` quantises it once, after the
    /// gain, into this same 16-bit shape (spec §11 #86). This dictionary is
    /// kept for the un-normalised read because changing it would change
    /// every such export's bytes.
    static let decodedAudioSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    /// The encoder settings for the sound: LPCM where the row asks for it, so
    /// a master stays a master, and AAC everywhere else. `settings.audioBitrate`
    /// when the core resolved one, else 192 kbps — stereo AAC's
    /// transparent-enough rate and what the M1 presets landed on.
    ///
    /// **Two codecs mean LPCM (`ExportSettings.carriesLinearPCM(codec:)`), and
    /// the CONTAINER decides the byte order.** ProRes has since M2 (§7.8
    /// pairs the profile with uncompressed sound), and phase 5's `audio_wav`
    /// / `audio_aiff` rows carry the codec `lpcm` outright. The dictionary handed to the encoder is then literally
    /// `decodedAudioSettings`, so nothing is converted on the way: an export
    /// with no gain reads the mix in it, and on a gained export
    /// `ExportAudioGain` produces it from the float read. The exception is
    /// AIFF, which is big-endian by definition where WAV and QuickTime are
    /// little. Getting that flag wrong is not a subtle bug, and it was measured rather than
    /// reasoned about: on macOS 26.5.1 `AVAssetWriter.canAdd` answers FALSE
    /// for AAC settings into a `.wav` and FALSE for a little-endian LPCM
    /// dictionary into an `.aiff`, so either mistake reaches the user as
    /// `.presetUnavailable` for a format the table advertises. With the
    /// branch as written, one twenty-second tone came out of both rows the
    /// same size and decoded to identical PCM, sample for sample.
    ///
    /// A row whose codec is `lpcm` in a container this build has no rule for
    /// still gets little-endian LPCM rather than AAC, because AAC in an
    /// uncompressed container is the failure that reads as
    /// `.presetUnavailable` and sends the reader looking at the preset table.
    static func audioSettings(_ settings: ExportSettings) -> [String: Any] {
        guard ExportSettings.carriesLinearPCM(codec: settings.codec) else {
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: settings.audioBitrate.map { max(1, $0) } ?? 192_000,
            ]
        }
        guard settings.container.lowercased() == "aiff" else { return decodedAudioSettings }
        var bigEndian = decodedAudioSettings
        bigEndian[AVLinearPCMIsBigEndianKey] = true
        return bigEndian
    }

    /// Whether this container can hold a chapter track (see `addChapters`).
    /// The QuickTime family and nothing else: a chapter list is a text track
    /// associated with the movie's own, and WAV, AIFF and the two image
    /// formats have no track to associate it with.
    static func carriesChapters(_ settings: ExportSettings) -> Bool {
        switch settings.container.lowercased() {
        case "mov", "quicktime", "mp4", "m4v", "m4a": return true
        default: return false
        }
    }
}
