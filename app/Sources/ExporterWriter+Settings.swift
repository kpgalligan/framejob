import AVFoundation

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
    /// which is right for every other row, and destroys the alpha channel
    /// when it has to pad: the picture comes back at alpha 0 and the bars at
    /// alpha 255, the answer inverted. A pure SCALE is safe at any factor,
    /// up or down, so what is refused is the aspect change and not the
    /// resize.
    ///
    /// The test is the fit itself rather than a ratio comparison, because a
    /// ratio needs a tolerance nobody can justify and this needs none: fit
    /// the canvas into the box the way the encoder will, and if what comes
    /// out is the box, there is no padding.
    ///
    /// **The box is `encodedSize`'s and not `settings`', and the difference
    /// was a hole in this guard.** The encoder is handed
    /// `AVVideoWidthKey`/`AVVideoHeightKey`, not the size the core resolved,
    /// and a rounding there moves the BOX the canvas is fitted into — which
    /// the comparison never saw. An odd-edged transparent document (legal:
    /// `set_canvas` refuses an odd dimension, `Project::new` and `validate`
    /// do not, so an odd-sized PNG opened as a document or an odd display
    /// size gets one) passed at 1001 × 667 and was encoded at 1000 × 666,
    /// reaching the padding path through the DEFAULT "Document size" row
    /// with the guard silent. `encodedSize` is what closed it; asking it
    /// here rather than `settings` is what keeps it closed if a later row
    /// ever needs a rounding of its own.
    ///
    /// One pixel of slack on each edge stays, and it is a deliberate trade
    /// rather than an oversight. It absorbs `export_size.rs`'s even-rounding
    /// of a standard row's long edge — `fitted()` can miss the canvas's
    /// exact aspect by a pixel, and refusing every standard row on such a
    /// document would be a false refusal for a fault nobody can see. What it
    /// costs is measured: a one-pixel pad puts ONE edge column at the
    /// backdrop's alpha instead of the picture's (1001 × 667 fitted into
    /// 1000 × 666 comes back with its right-hand column opaque where the
    /// canvas is transparent), where the aspect change this refuses puts
    /// whole BARS there.
    static func checkAlphaSurvivesTheSize(
        _ settings: ExportSettings, canvas: CGSize
    ) throws {
        guard settings.alpha, canvas.width >= 1, canvas.height >= 1,
            settings.width >= 1, settings.height >= 1
        else { return }
        let frame = encodedSize(settings)
        let want = CGSize(width: frame.width, height: frame.height)
        let scale = min(want.width / canvas.width, want.height / canvas.height)
        let fitted = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        guard abs(fitted.width - want.width) > 1 || abs(fitted.height - want.height) > 1 else {
            return
        }
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
    /// preference.** Rounding an odd edge down moves the box, so
    /// `AVVideoScalingModeResizeAspect` pads by the pixel the rounding took
    /// away — and padding is the one thing an alpha export cannot survive.
    /// Measured here (macOS 26.5.1, `AVAssetWriter` +
    /// `AVVideoCodecType.proRes4444`): asked for 1001 × 667 the writer
    /// accepts it and the file comes back `prores`, `yuva444p12le`,
    /// 1001 × 667, with the transparent half at alpha 0 and the opaque half
    /// at 255 — exact at every pixel; asked for 1000 × 666 with the same
    /// 1001 × 667 picture it comes back with its right-hand column OPAQUE
    /// where the canvas is transparent. So the one row that cannot afford
    /// the rounding turns out not to need it.
    /// Every other row keeps the rounding it has always had, ProRes 422
    /// included — it does not need it either (measured: 1001 × 667 survives
    /// as `yuv422p10le`), but changing the bytes a shipped row writes for a
    /// case no proof covers is not this guard's business.
    private static func encodedSize(_ settings: ExportSettings) -> (width: Int, height: Int) {
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
    /// told the size the sheet promised and `AVVideoScalingModeResizeAspect`
    /// fits the canvas inside it, letterboxing rather than distorting when
    /// the two aspects differ. The frame itself is `encodedSize`'s answer —
    /// the rounding lives there, with the argument for it and for the row
    /// that is exempt, because `checkAlphaSurvivesTheSize` has to compare
    /// against the same number.
    ///
    /// **Bitrate.** `settings.videoBitrate` when the core resolved one. When
    /// it did not, a rate computed from the frame — bits per pixel per frame,
    /// halved for HEVC — rather than none at all: with no
    /// `AVVideoAverageBitRateKey` VideoToolbox picks a conservative default
    /// that visibly under-runs a 4K timeline. ProRes gets neither: its rate
    /// is a property of the profile.
    static func videoSettings(_ settings: ExportSettings) throws -> [String: Any] {
        guard let codec = codecType(for: settings.codec) else {
            throw Exporter.ExportError.presetUnavailable(presetName(settings))
        }
        let frame = encodedSize(settings)
        var output: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: frame.width,
            AVVideoHeightKey: frame.height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            // The compositor works in SDR sRGB/709 and tone-maps HDR sources
            // on the way in (§7.5), so tagging the output 709 is a statement
            // of what the pixels ARE, not a conversion.
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
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
        output[AVVideoCompressionPropertiesKey] = compression
        return output
    }

    /// The core's codec name as an `AVVideoCodecType`. nil is a refusal, not
    /// a fallback: writing H.264 because "vp9" was not understood would put a
    /// file on disk that is not the one asked for.
    private static func codecType(for codec: String) -> AVVideoCodecType? {
        switch codec.lowercased() {
        case "h264", "avc", "avc1": return .h264
        case "hevc", "h265", "hvc1": return .hevc
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
    /// half that for HEVC — clamped so a tiny canvas still gets a usable rate
    /// and a huge one cannot ask for a file no disk wants.
    private static func defaultVideoBitrate(
        _ settings: ExportSettings, codec: AVVideoCodecType
    ) -> Int {
        let pixels = Double(max(1, settings.width)) * Double(max(1, settings.height))
        let rate = settings.fps.double > 0 ? settings.fps.double : 30
        let perPixel = codec == .hevc ? 0.07 : 0.14
        return Int(min(max(pixels * rate * perPixel, 1_000_000), 200_000_000))
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
    /// **Two codecs mean LPCM, and the CONTAINER decides the byte order.**
    /// ProRes has since M2 (§7.8 pairs the profile with uncompressed sound),
    /// and phase 5's `audio_wav` / `audio_aiff` rows carry the codec `lpcm`
    /// outright. The dictionary handed to the encoder is then literally
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
        let codec = settings.codec.lowercased()
        guard codec == "lpcm" || codec.hasPrefix("prores") else {
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
