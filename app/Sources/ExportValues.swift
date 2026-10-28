import AppKit

/// The export values the core's presets and settings decode into — `ExportPreset`,
/// `ExportSettings` and `ExportSize` — moved out of `ReelCore.swift` (a pure move, hdr H-1)
/// because they name no `rc_*` symbol; `ReelExport` there still reads them.
/// One row of `rc_export_presets`. Decoded leniently: the core owns this
/// schema (§7.8) and may add fields this build does not know.
struct ExportPreset: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    /// "mov", "mp4", "m4a".
    let container: String
    /// "h264", "hevc", "prores_422", "aac".
    let codec: String
    /// Fixed output size, or nil for the document (canvas) size.
    let width: Int?
    let height: Int?
    let audioOnly: Bool
    /// Whether the row carries an HLG project's HDR picture (`"hdr"`, spec §11
    /// HD-14 (c)): the three 10-bit rows, which offer the Dynamic Range popup.
    let carriesHDR: Bool
    /// The bundled encoder's speeds the row takes (`encoder_speeds`, spec §11
    /// CX-12 (2)): `av1`'s three, which offer the Speed popup; empty elsewhere.
    let encoderSpeeds: [EncoderSpeed]

    /// The core spells the size as one `size: [w, h] | null` and audio-only
    /// as `video: false` (`export.rs`), so the size and the audio flag are
    /// read from those rather than from `width` / `height` / `audio_only`,
    /// which it never emits.
    private enum CodingKeys: String, CodingKey {
        case id, name, container, codec, size, video, hdr, encoderSpeeds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id, "")
        name = c.lenient(.name, "")
        container = c.lenient(.container, "mov")
        codec = c.lenient(.codec, "h264")
        let size: [Int]? = c.lenient(.size)
        width = size?.count == 2 ? size?[0] : nil
        height = size?.count == 2 ? size?[1] : nil
        audioOnly = !c.lenient(.video, true)
        carriesHDR = c.lenient(.hdr, false)
        let speeds: [String] = c.lenient(.encoderSpeeds, [])
        encoderSpeeds = speeds.compactMap(EncoderSpeed.init(rawValue:))
    }
}

/// A preset plus overrides resolved against the project into the concrete
/// numbers `Exporter` configures its pipeline with — `ExportWriter` or the
/// ImageIO frame sequence (§7.8).
struct ExportSettings: Decodable, Equatable {
    let preset: String
    let container: String
    let codec: String
    let width: Int
    let height: Int
    let fps: Fps
    /// The range to write — the whole timeline, or the in/out range.
    let start: Ticks
    let duration: Ticks
    /// The `AVAssetExportSession` preset name the row carries for the
    /// record; nil is the signal that AVFoundation cannot write this
    /// container and the frames go through ImageIO (`isImageSequence`).
    let avPreset: String?
    /// The `AVFileType` raw value, e.g. "com.apple.quicktime-movie".
    let fileType: String?
    let optimizeForNetwork: Bool
    let videoBitrate: Int?
    let audioBitrate: Int?
    /// The integrated loudness target the written file is normalised to, in
    /// LUFS (`export_overrides.rs`'s `loudness_lufs`, −70…0), or nil for "do
    /// not normalise" — which is what an ABSENT key means, the same rule the
    /// two bitrates follow. The export sheet's Loudness popup and the
    /// `export` tool are the two callers that set it.
    let loudnessLufs: Double?
    /// The true-peak ceiling the normalising gain is capped against, in dBTP
    /// (`peak_dbtp`, −20…0). The core refuses one with no `loudnessLufs`
    /// beside it, so this is nil whenever that is; nil WITH a target is a
    /// script's "no ceiling but full scale", and `ExportLoudness.resolve`
    /// supplies 0 dBTP for it.
    let peakDbtp: Double?
    /// Whether this ENCODING carries an alpha channel — true for `prores_4444`,
    /// `hevc_alpha` and `apng`, and for nothing else the table offers.
    ///
    /// The rows are not alike and `apng`'s is the one to remember beside it:
    /// `gif` is FALSE though a GIF can show a transparent pixel, because one
    /// palette index is not a channel and nothing partial survives it, where
    /// APNG carries a real fourth channel (`export_table.rs`'s field doc is
    /// where that argument lives, and the header repeats it). A reader who
    /// takes this for `prores_4444` alone reads the export sheet's footnote
    /// and the Document tab's note as bugs — which is what the phase's own
    /// review found this sentence doing.
    ///
    /// **It is a capability of the row, NOT a statement about the project**,
    /// and the obvious reading of the name is the wrong one. `export_settings`
    /// resolves one flat object for every row alike, so a flag derived from
    /// the canvas background would report `alpha: true` on an H.264, a GIF
    /// and a WAV, none of which can hold one. It follows `audio`'s own
    /// precedent in `export_table.rs`: "a fact about the CONTAINER rather
    /// than a decision about the project". A translucent canvas is a
    /// separate, orthogonal fact, and what this answers is whether the file
    /// would keep it.
    let alpha: Bool
    /// The picture the file is written as and tagged with (spec §11 HD-14
    /// (c), `export.rs`): in an HLG project `"hlg"` (a 10-bit row's default),
    /// `"pq"` (HDR10) or `"sdr"` (the SDR version, every other video row's);
    /// nil — today's tags — for every SDR project and every audio row, whose
    /// settings carry no key.
    let color: String?
    /// The bundled encoder that writes the video (`writer`, "svt_av1", spec
    /// §11 CX-12) and its speed (`encoder_speed`); nil on every row
    /// AVFoundation encodes, whose settings carry neither key.
    let writer: String?
    let encoderSpeed: EncoderSpeed?

    /// `color` as the picture it names; nil when the settings carry none.
    var dynamicRange: DynamicRange? { color.flatMap(DynamicRange.init(rawValue:)) }

    /// Spelled out rather than synthesized because two keys do not follow
    /// from the property names: the core nests the resolved range under
    /// `range` (`export.rs`), and its preset name is `avf_preset`, which
    /// `.convertFromSnakeCase` turns into `avfPreset`. Decoding those as
    /// `start` / `duration` / `avPreset` silently produced a zero-length
    /// range — which disabled the export sheet's Export button and made the
    /// agent's `export` report `"duration": 0` — and threw the core's
    /// AVFoundation preset away.
    ///
    /// The two loudness keys are NOT of that kind: `loudness_lufs` and
    /// `peak_dbtp` convert to `loudnessLufs` and `peakDbtp` on their own.
    /// They are listed for the reason every other well-behaved key is —
    /// a `CodingKeys` enum is exhaustive, and a case left out is a field
    /// that silently decodes as nil. `alpha` (phase 7) is the newest of
    /// those, and it decodes as FALSE when left out, which would have read
    /// as "no row can carry alpha" — a defect that looks like a working
    /// build.
    ///
    /// **Two keys the core emits are still absent, deliberately: `audio` and
    /// `video`.** Nothing decodes them, so adding cases would add two stored
    /// properties no reader consults; `isAudioOnly` answers the same question
    /// from `avPreset` and the container and predates both. `alpha` is the
    /// first of the three anything actually reads, which is why it is the
    /// only one here. A future reader of `audio` or `video` adds the case —
    /// it does not infer the answer from this list's silence.
    private enum CodingKeys: String, CodingKey {
        case preset, container, codec, width, height, fps, range
        case avPreset = "avfPreset"
        case fileType, optimizeForNetwork, videoBitrate, audioBitrate
        case loudnessLufs, peakDbtp, alpha, color, writer, encoderSpeed
    }

    private enum RangeKeys: String, CodingKey {
        case start, duration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = c.lenient(.preset, "")
        container = c.lenient(.container, "mov")
        codec = c.lenient(.codec, "h264")
        width = c.lenient(.width, 1920)
        height = c.lenient(.height, 1080)
        fps = c.lenient(.fps, Fps.thirty)
        let range = try? c.nestedContainer(keyedBy: RangeKeys.self, forKey: .range)
        start = range?.lenient(.start, 0) ?? 0
        duration = range?.lenient(.duration, 0) ?? 0
        avPreset = c.lenient(.avPreset)
        fileType = c.lenient(.fileType)
        optimizeForNetwork = c.lenient(.optimizeForNetwork, true)
        videoBitrate = c.lenient(.videoBitrate)
        audioBitrate = c.lenient(.audioBitrate)
        loudnessLufs = c.lenient(.loudnessLufs)
        peakDbtp = c.lenient(.peakDbtp)
        // False is the safe default: only `prores_4444`, `hevc_alpha` and
        // `apng` answer true, and a core that predates phase 7 does not emit
        // the key at all. Its silence UNDER-reports — that core has no
        // `prores_4444` row to describe, but its `apng` row wrote alpha then as it does
        // now — and under-reporting is the direction that cannot hurt: this
        // key only ADDS the footnote's "alpha" and ARMS
        // `ExportWriter.checkAlphaSurvivesTheSize`, so false promises less
        // than the file holds where true would promise more.
        alpha = c.lenient(.alpha, false)
        color = c.lenient(.color)
        writer = c.lenient(.writer)
        let speed: String? = c.lenient(.encoderSpeed)
        encoderSpeed = speed.flatMap(EncoderSpeed.init(rawValue:))
    }

    var renderSize: CGSize { CGSize(width: width, height: height) }
}

extension ExportSettings {
    /// Whether an encoding's sound is LPCM: the `lpcm` codec of the
    /// uncompressed audio rows, and every ProRes profile, which §7.8 pairs
    /// with uncompressed sound. The export sheet's fixed-rate rows
    /// (`ExportSheetController.Applies`) and the writer's audio settings
    /// (`ExportWriter.audioSettings`) both ask it.
    static func carriesLinearPCM(codec: String) -> Bool {
        let c = codec.lowercased()
        return c == "lpcm" || c.hasPrefix("prores")
    }
}

/// A bundled encoder's speed (spec §11 CX-2, CX-12 (2)): the core's word, the
/// sheet's name and SVT-AV1's preset.
enum EncoderSpeed: String, CaseIterable {
    case faster, balanced, smaller

    var menuName: String {
        switch self {
        case .faster: return "Faster"
        case .balanced: return "Balanced"
        case .smaller: return "Smaller file"
        }
    }

    var svtPreset: Int8 {
        switch self {
        case .faster: return 8
        case .balanced: return 6
        case .smaller: return 4
        }
    }
}

/// One row of the export sheet's Size popup, from `rc_export_sizes`: the
/// document's own size, an image format's cap, or a standard size fitted to
/// the document's aspect.
struct ExportSize: Decodable, Equatable, Identifiable {
    /// "document", "preset" (an image format's cap), "2160p", "1440p",
    /// "1080p" or "720p" — the vocabulary the `export` tool's `size` takes.
    let id: String
    /// "Document size" (or "Document (even)"), "GIF default", "4K"… — the
    /// sheet appends the numbers.
    let name: String
    let width: Int
    let height: Int
}
