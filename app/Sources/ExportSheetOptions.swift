import AppKit

/// What the export sheet's controls MEAN, before any of them has been read:
/// the ranges the fields accept, the loudness targets and the fixed ceiling,
/// the quality ladder and its arithmetic, and `Applies` — the one reading of
/// a format that decides which of the sheet's controls that row can honestly
/// take.
///
/// The seam is between a control's VOCABULARY and its VALUE.
/// `ExportSheetController.swift` builds the popups and the fields and puts
/// the card up; `ExportSheetResolve.swift` reads what is chosen and asks the
/// core about it. Everything here is what both of them consult and neither
/// of them owns: it depends on no popup's selection, holds no state, and
/// would answer the same for a sheet that was never shown. That is also why
/// the two nested types live in this half rather than beside the controls
/// they gate — `QualityTier` is a bit-rate calculation and `Applies` is a
/// reading of one `ExportPreset` row, and neither has ever asked an
/// `NSPopUpButton` a question.
///
/// The cut is the size payment `ExportSheetController.swift` owed at 1114
/// lines against app/CLAUDE.md's ~600 cap, and it is a pure move: the same
/// declarations, in the same order, with the same bodies. **The toll is
/// visibility.** `private` on an extension member reaches only its own file,
/// so `loudnessTargets`, `loudnessRange`, `tiers`, `QualityTier`, `Applies`,
/// `isFrameSequence` and `rateText` are all internal now, for the reason
/// `ExporterLoudness.swift` records: the split, and nothing else. `sizeRange`
/// and `peakCeilingDBTP` were already internal and say in their own comments
/// why. `loudnessTitle` arrived later, in phase 7, and for the other reason a
/// member moves: the controller was at the cap and had to give something up
/// before it took the Preset row on.
extension ExportSheetController {

    /// The widest and narrowest custom size the fields accept. Not a format
    /// limit: a sanity range so a mistyped digit cannot ask the encoder for a
    /// 300 000-pixel frame.
    /// Internal, not private: the agent's `export` refuses a custom size
    /// outside it by name (`AgentServer+Render.swift`), and one constant is
    /// how the sheet and the tool cannot disagree.
    static let sizeRange = 16...8192

    // MARK: - Loudness

    /// The Loudness popup's rows after "Off", in menu order: the integrated
    /// target each asks the export to be normalised to.
    ///
    /// −14 LUFS is where every streaming service has settled (Spotify,
    /// YouTube and Apple Music all normalise to within a decibel of it), −16
    /// is the podcast convention for stereo, and −23 is EBU R 128, which is
    /// broadcast delivery in Europe and what "LUFS" meant before streaming
    /// took the word. Anything else is "Custom…" and the field beside it.
    static let loudnessTargets: [Double] = [-14, -16, -23]

    /// The true-peak ceiling every normalised export is capped against, in
    /// dBTP. FIXED in phase 5 rather than made a control: five presets and
    /// one broadcast-standard ceiling is what people actually pick, the sheet
    /// is already six control rows deep, and the `export` tool keeps
    /// `peak_dbtp` for a script that needs −0.3 or −2.0. The hint says the
    /// number, so a fixed value is visible rather than folklore.
    static let peakCeilingDBTP: Double = -1

    /// A target as its menu row reads. The two named tiers say who asks for
    /// them, because "−14" and "−23" mean nothing to someone who has not met
    /// them before and everything to someone who has.
    ///
    /// Here rather than beside the popup it titles, and the move is the size
    /// payment `ExportSheetController.swift` owed before phase 7 put a Preset
    /// row and a burn-in on it. It belongs in this half by this file's own
    /// rule: it is a pure function of a target, holds no state, asks no
    /// control anything, and is `rateText`'s sibling — the spelling of one of
    /// the ladders `loudnessTargets` and `tiers` declare a few lines up.
    static func loudnessTitle(_ target: Double) -> String {
        let value = String(format: "%.0f", target).replacingOccurrences(of: "-", with: "−")
        switch target {
        case -14: return "\(value) LUFS (streaming)"
        case -23: return "\(value) LUFS (broadcast)"
        default: return "\(value) LUFS"
        }
    }

    /// What the core will take: `export_overrides.rs`'s own bounds for
    /// `loudness_lufs`, spelled here so the field's formatter refuses what
    /// the core would refuse rather than sending it and reading the message
    /// back.
    static let loudnessRange: ClosedRange<Double> = -70...0

    // MARK: - Quality

    /// One row of the Quality popup: a video rate expressed as bits per pixel
    /// per frame, and the AAC rate that goes with it.
    ///
    /// **Where the video numbers come from.** They are anchored on one
    /// published figure and scaled from it rather than guessed: YouTube's
    /// recommended upload for 1080p SDR H.264 at 30 fps is 8 Mbps, and
    /// 1920 × 1080 × 30 is 62.2 Mpixel/s, so "High" is 8 000 000 / 62 200 000
    /// ≈ 0.129 bits per pixel per frame. The other three tiers are 0.5×,
    /// 0.75× and 1.5× of it — 4, 6 and 12 Mbps at 1080p30, which brackets
    /// Apple's HLS Authoring Specification 1080p H.264 rung (6.0–7.8 Mbps)
    /// on both sides.
    ///
    /// Holding bits-per-pixel constant makes the rate scale with the frame's
    /// area, so High is 3.6 Mbps at 720p and 32 Mbps at 4K. That is
    /// deliberately flatter than YouTube's own ladder, which is generous at
    /// the small end because its rungs are transcode targets; a master at a
    /// constant bits-per-pixel is the same picture at every size, which is
    /// what choosing "High" ought to mean.
    struct QualityTier {
        let name: String
        /// Bits per pixel per frame, for H.264 at 30 fps or less.
        let bitsPerPixel: Double
        /// AAC-LC stereo, bits per second. 128 kbps is the streaming
        /// baseline, 256 is what Apple Music ships, and 320 is where AAC-LC
        /// stops paying for the extra bits.
        let audioBitsPerSecond: Int

        /// The video rate for a `width` × `height` frame at `fps`.
        ///
        /// The 30 is not a stand-in for `fps`: the frame rate enters through
        /// `rateFactor` instead, because bits do not scale linearly with it.
        /// Consecutive frames are more alike the closer together they are,
        /// which is why YouTube's ladder asks 1.5× for its 48–60 fps column
        /// and nothing extra for 24 fps over 30. This mirrors that shape —
        /// one step at 30 and below, one above it.
        func videoBitsPerSecond(width: Int, height: Int, fps: Fps, codec: String) -> Int {
            let pixels = Double(max(width, 1)) * Double(max(height, 1))
            let rateFactor = fps.double > 30.5 ? 1.5 : 1.0
            // HEVC reaches the same picture at roughly 60 % of H.264's rate —
            // the ratio between the two 1080p rungs of the same Apple
            // specification the tiers are calibrated against.
            let codecFactor = QualityTier.isHEVC(codec) ? 0.6 : 1.0
            let bits = pixels * 30 * bitsPerPixel * rateFactor * codecFactor
            // To the nearest 100 kbps: these are estimates, and a request for
            // "7 963 200 bits" would claim a precision they do not have.
            return max(100_000, Int((bits / 100_000).rounded()) * 100_000)
        }

        private static func isHEVC(_ codec: String) -> Bool {
            let codec = codec.lowercased()
            return codec.hasPrefix("hevc") || codec.hasPrefix("h265") || codec.hasPrefix("h.265")
        }
    }

    /// The tiers, in menu order. Index 0 of the popup is "Format default",
    /// i.e. no override at all — the format's own rate, or the export
    /// session's ladder when it carries none.
    static let tiers: [QualityTier] = [
        QualityTier(name: "Low", bitsPerPixel: 0.064, audioBitsPerSecond: 128_000),
        QualityTier(name: "Medium", bitsPerPixel: 0.096, audioBitsPerSecond: 192_000),
        QualityTier(name: "High", bitsPerPixel: 0.129, audioBitsPerSecond: 256_000),
        QualityTier(name: "Maximum", bitsPerPixel: 0.193, audioBitsPerSecond: 320_000),
    ]

    /// What the picked format can actually take from this sheet.
    ///
    /// Both the enablement of every control AND every override key are read
    /// from one of these, so a greyed-out control can never still be sending
    /// a value to the core — which is what keeps the sheet honest as formats
    /// that are not H.264 movies join the list.
    struct Applies {
        private let preset: ExportPreset?

        init(_ preset: ExportPreset?) {
            self.preset = preset
        }

        /// A frame sequence — GIF or APNG — has a size and a frame rate but
        /// no bit rate to spend and no audio track to put one on.
        private var frameSequence: Bool {
            guard let preset = preset else { return false }
            return ExportSheetController.isFrameSequence(container: preset.container)
        }

        /// A row whose data rate is not the sheet's to name. ProRes is a
        /// fixed-rate intra codec — the profile decides — and §7.8's preset
        /// pairs it with LPCM audio; the two LPCM audio rows are
        /// uncompressed by definition, so offering either of them an AAC bit
        /// rate would be a control that changes nothing about the file.
        private var fixedRate: Bool {
            let codec = preset?.codec.lowercased() ?? ""
            return codec.hasPrefix("prores") || codec == "lpcm"
        }

        private var hasVideo: Bool { preset.map { !$0.audioOnly } ?? false }

        var size: Bool { hasVideo }
        var frameRate: Bool { hasVideo }
        var videoBitrate: Bool { hasVideo && !frameSequence && !fixedRate }
        var audioBitrate: Bool { preset != nil && !frameSequence && !fixedRate }
        var quality: Bool { videoBitrate || audioBitrate }

        /// Loudness normalisation is a gain on the mixed sound, so it
        /// applies to every row that HAS sound — which is every row but the
        /// two frame sequences. Deliberately not gated by `fixedRate` (ProRes
        /// carries LPCM audio and takes a gain like anything else) nor by
        /// `hasVideo` (the three audio-only rows are exactly where a
        /// delivery target matters most).
        var loudness: Bool { preset != nil && !frameSequence }
    }

    /// GIF and APNG. Spelled once, and taken from the container rather than
    /// the codec because that is the field both `ExportPreset` and
    /// `ExportSettings` carry.
    static func isFrameSequence(container: String) -> Bool {
        let container = container.lowercased()
        return container == "gif" || container == "apng"
    }

    /// A bit rate as the tier rows and the footnote spell it.
    static func rateText(_ bitsPerSecond: Int) -> String {
        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitsPerSecond) / 1_000_000)
        }
        return "\(Int((Double(bitsPerSecond) / 1000).rounded())) kbps"
    }
}
