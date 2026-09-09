import AVFoundation
import UniformTypeIdentifiers

/// The resolved export settings translated into AVFoundation's vocabulary —
/// a time range, a session preset name, a file type, a UTI, an extension, and
/// the one question the sheet and the agent both ask of a row.
///
/// **Why this is a file of its own, and why it is this half.** `Exporter.swift`
/// stood at exactly 600 lines and road map 2's phase 7 came to give both
/// `export` and `renderFrame` a `RecipeOptions` argument, so something had to
/// go out first — the rule `ExporterLoudness.swift` paid in phase 5 and
/// `LayerRenderersText.swift` paid in phase 6. This is the concern that came
/// out because it is the one with no export in it: every member below is a
/// pure function of an `ExportSettings` value, none touches an `Exporter`
/// instance, a timer, a pipeline or a recipe slot, and half the callers are
/// the export SHEET rather than the export. What stayed is what runs an
/// export.
///
/// One member deliberately did NOT come with them, and it is worth naming so
/// nobody "finishes" the cut: `Exporter.renderFrame` is the other pure static
/// on that class, and it stays where it is. It is the only
/// `copyCGImage(at:actualTime:)` call in the app, so moving it would move the
/// single deliberate deprecation warning `Exporter.swift`'s own doc — and the
/// root `CLAUDE.md`'s build baseline — names by file.
///
/// Nothing here changed in the move. Every member is still reached as
/// `Exporter.<name>` or off an `ExportSettings` value, so no call site moved
/// with it.
extension Exporter {

    // MARK: - Settings → AVFoundation

    /// The range to write. The core has already resolved "whole project" or
    /// "in/out range" into `start` and `duration` (§7.8); a zero duration only
    /// happens if the project has none, and then the composition's own length
    /// is the honest answer.
    static func timeRange(_ settings: ExportSettings, composition: AVComposition) -> CMTimeRange {
        let start = CompositionBuilder.time(max(0, settings.start))
        guard settings.duration > 0 else {
            return CMTimeRange(start: start, duration: composition.duration)
        }
        return CMTimeRange(start: start, duration: CompositionBuilder.time(settings.duration))
    }

    /// The `AVAssetExportSession` preset for settings the core did not name
    /// one for. Deliberately a fallback rather than the rule: §7.8 makes the
    /// preset the core's decision, and this only exists so a core that adds a
    /// preset before this build knows about it still exports something
    /// sensible instead of refusing.
    ///
    /// **Not on the export path any more** — the writer sets the codec, the
    /// size and the bitrate itself and needs no preset name. Kept because
    /// `ExportSettings.isAudioOnly` reads `avPreset` against one of these
    /// names, and as the one record of which fixed-frame session preset a
    /// codec at a size would have meant, now that the core's rows carry only
    /// the "highest quality" names (§7.8): the mapping has not left the
    /// project, only the session has. (It used to say "has not left this
    /// FILE", which phase 7's cut made false — `isAudioOnly` came with it,
    /// which is the half of that sentence that still matters: the two are
    /// still read side by side.)
    static func fallbackPreset(for settings: ExportSettings) -> String {
        if settings.isAudioOnly { return AVAssetExportPresetAppleM4A }
        switch settings.codec.lowercased() {
        case "hevc", "h265":
            return settings.width >= 3840
                ? AVAssetExportPresetHEVC3840x2160 : AVAssetExportPresetHEVC1920x1080
        case "prores_422", "prores", "prores422":
            return AVAssetExportPresetAppleProRes422LPCM
        default:
            if settings.width >= 3840 { return AVAssetExportPreset3840x2160 }
            if settings.width >= 1920 { return AVAssetExportPreset1920x1080 }
            if settings.width >= 1280 { return AVAssetExportPreset1280x720 }
            return AVAssetExportPreset960x540
        }
    }

    /// The output file type: the core's UTI when it gave one, else the
    /// container name mapped to the six this build writes.
    ///
    /// The fallback is only ever reached by a core that gave no `file_type`,
    /// which none of the shipped rows does. It carries `wav` and `aiff` all
    /// the same, for the symmetry rather than the need: the two LPCM rows
    /// resolve through their UTI like every other row, and a reader who
    /// finds them missing from this list would reasonably conclude they take
    /// a different path.
    static func fileType(for settings: ExportSettings) -> AVFileType? {
        if let raw = settings.fileType, !raw.isEmpty { return AVFileType(rawValue: raw) }
        switch settings.container.lowercased() {
        case "mov", "quicktime": return .mov
        case "mp4": return .mp4
        case "m4v": return .m4v
        case "m4a": return .m4a
        case "wav": return .wav
        case "aiff": return .aiff
        default: return nil
        }
    }

    /// The save panel's allowed type. `AVFileType`'s raw values ARE UTIs, so
    /// this is the same decision as `fileType(for:)` and cannot drift from it.
    static func contentType(for settings: ExportSettings) -> UTType? {
        guard let type = fileType(for: settings) else { return nil }
        return UTType(type.rawValue)
    }

    /// The extension the save panel appends.
    static func fileExtension(for settings: ExportSettings) -> String {
        contentType(for: settings)?.preferredFilenameExtension
            ?? settings.container.lowercased()
    }
}

// MARK: - Audio-only settings

extension ExportSettings {
    /// True for the "Audio only" preset row (spec §7.8's M4A). Read from the
    /// resolved settings rather than carried from the `ExportPreset` the sheet
    /// picked, so the `Exporter` needs nothing but its settings — and so the
    /// agent's `export {preset, path}` behaves the same as the sheet.
    var isAudioOnly: Bool {
        if let preset = avPreset, preset == AVAssetExportPresetAppleM4A { return true }
        switch container.lowercased() {
        case "m4a", "mp3", "wav", "aiff", "caf": return true
        default: return false
        }
    }
}
