import AppKit
import UniformTypeIdentifiers

/// File ▸ Export… (⌘E) and the toolbar's Export button: pick a preset, adjust
/// the size, the frame rate, the quality and the range, then a save panel and
/// a progress sheet (spec §7.8, §10 step 10).
///
/// Every number the sheet shows comes back from `rc_export_settings` — the
/// sheet never computes an output size, a rate or a duration itself. That is
/// the §7 rule ("Rust decides") applied to a dialog: the controls only say
/// what to ASK for, the core answers, and what the readout shows is exactly
/// what `Exporter` will be handed. It also means a preset the core adds
/// tomorrow needs no change here: the picker is built from
/// `ReelExport.presets()`, so GIF, APNG or anything else joins the menu the
/// moment the core's table lists it, and `Applies` below decides which of
/// this sheet's controls that row can honestly take.
///
/// The one number the sheet DOES choose is the bit rate: a quality tier is a
/// request, like a custom size, not a readout. It is spelled as bits per
/// pixel per frame so it means the same picture at every size, and what the
/// core answers with is what the footnote reports.
///
/// Its own file rather than another section of `Sheets.swift` (frozen at its
/// current size), built from the same `makeSheetView`/`makeButtonRow` pieces
/// so it matches every other dialog.
final class ExportSheetController: NSViewController {
    /// Weak: the editor owns the presentation, and a sheet must never be the
    /// reason a closing window's controller stays alive.
    private weak var editor: EditorViewController?

    private let presets: [ExportPreset]
    /// The in/out range at open time, if the document has one. Captured
    /// because the sheet blocks every edit while it is up, so it cannot move.
    private let range: (start: Ticks, end: Ticks)?

    /// The settings the core resolved for the current control values, and the
    /// message it refused with. Exactly one of the two is non-nil once
    /// `resolve()` has run.
    private var resolved: ExportSettings?
    private var resolveError: String?

    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let widthField = NSTextField(string: "")
    private let heightField = NSTextField(string: "")
    private let presetSizeCheckbox = NSButton(
        checkboxWithTitle: "Use the preset's size", target: nil, action: nil)
    private let ratePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let qualityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let rangePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private let footnote = sheetFootnote("")
    private var exportButton: NSButton!

    /// Frame-rate overrides. Index 0 is "the project's rate", i.e. no
    /// override at all — the core then uses the canvas rate (§5.2).
    private static let rates: [Fps] = Fps.common

    /// The widest and narrowest custom size the fields accept. Not a format
    /// limit: a sanity range so a mistyped digit cannot ask the encoder for a
    /// 300 000-pixel frame.
    private static let sizeRange = 16...8192

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
    private struct QualityTier {
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

    /// The tiers, in menu order. Index 0 of the popup is "Preset default",
    /// i.e. no override at all — the preset's own rate, or the export
    /// session's ladder when it carries none.
    private static let tiers: [QualityTier] = [
        QualityTier(name: "Low", bitsPerPixel: 0.064, audioBitsPerSecond: 128_000),
        QualityTier(name: "Medium", bitsPerPixel: 0.096, audioBitsPerSecond: 192_000),
        QualityTier(name: "High", bitsPerPixel: 0.129, audioBitsPerSecond: 256_000),
        QualityTier(name: "Maximum", bitsPerPixel: 0.193, audioBitsPerSecond: 320_000),
    ]

    /// What the picked preset can actually take from this sheet.
    ///
    /// Both the enablement of every control AND every override key are read
    /// from one of these, so a greyed-out control can never still be sending
    /// a value to the core — which is what keeps the sheet honest as presets
    /// that are not H.264 movies join the list.
    private struct Applies {
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

        /// ProRes is a fixed-rate intra codec: the profile decides the data
        /// rate, and §7.8's preset pairs it with LPCM audio, so neither
        /// number is the sheet's to name.
        private var fixedRate: Bool {
            preset?.codec.lowercased().hasPrefix("prores") ?? false
        }

        private var hasVideo: Bool { preset.map { !$0.audioOnly } ?? false }

        var size: Bool { hasVideo }
        var frameRate: Bool { hasVideo }
        var videoBitrate: Bool { hasVideo && !frameSequence && !fixedRate }
        var audioBitrate: Bool { preset != nil && !frameSequence && !fixedRate }
        var quality: Bool { videoBitrate || audioBitrate }
    }

    /// GIF and APNG. Spelled once, and taken from the container rather than
    /// the codec because that is the field both `ExportPreset` and
    /// `ExportSettings` carry.
    private static func isFrameSequence(container: String) -> Bool {
        let container = container.lowercased()
        return container == "gif" || container == "apng"
    }

    /// A bit rate as the tier rows and the footnote spell it.
    private static func rateText(_ bitsPerSecond: Int) -> String {
        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitsPerSecond) / 1_000_000)
        }
        return "\(Int((Double(bitsPerSecond) / 1000).rounded())) kbps"
    }

    init(editor: EditorViewController) {
        self.editor = editor
        self.presets = ReelExport.presets()
        if let bounds = editor.document?.inOutRange, bounds.end > bounds.start {
            self.range = bounds
        } else {
            self.range = nil
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ExportSheetController does not support NSCoder")
    }

    // MARK: - View

    override func loadView() {
        presetPopup.addItems(withTitles: presets.map { $0.name })
        presetPopup.font = DS.sans(13)
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged(_:))
        presetPopup.widthAnchor.constraint(equalToConstant: 240).isActive = true

        for field in [widthField, heightField] {
            let formatter = NumberFormatter()
            formatter.numberStyle = .none
            formatter.allowsFloats = false
            formatter.minimum = NSNumber(value: Self.sizeRange.lowerBound)
            formatter.maximum = NSNumber(value: Self.sizeRange.upperBound)
            field.formatter = formatter
            field.delegate = self
            field.alignment = .right
            field.widthAnchor.constraint(equalToConstant: 72).isActive = true
            DSField.style(field)
        }

        presetSizeCheckbox.state = .on
        presetSizeCheckbox.font = DS.sans(13)
        presetSizeCheckbox.target = self
        presetSizeCheckbox.action = #selector(presetSizeChanged(_:))

        ratePopup.addItem(withTitle: "Project rate")
        ratePopup.addItems(withTitles: Self.rates.map { "\($0.displayName) fps" })
        ratePopup.font = DS.sans(13)
        ratePopup.target = self
        ratePopup.action = #selector(rangeOrRateChanged(_:))
        ratePopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

        qualityPopup.addItem(withTitle: "Preset default")
        // Bare names now; `syncQualityTitles` puts the rate each tier would
        // ask for beside them as soon as the first resolve has run.
        qualityPopup.addItems(withTitles: Self.tiers.map { $0.name })
        qualityPopup.font = DS.sans(13)
        qualityPopup.target = self
        qualityPopup.action = #selector(qualityChanged(_:))
        qualityPopup.widthAnchor.constraint(equalToConstant: 200).isActive = true

        rangePopup.addItem(withTitle: "Whole project")
        if range != nil { rangePopup.addItem(withTitle: "In/out range") }
        rangePopup.font = DS.sans(13)
        rangePopup.target = self
        rangePopup.action = #selector(rangeOrRateChanged(_:))
        rangePopup.isEnabled = range != nil
        rangePopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

        summaryLabel.font = DS.mono(11)
        summaryLabel.textColor = DS.textMuted
        summaryLabel.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2

        let grid = NSGridView(views: [
            [fieldLabel("Preset:"), presetPopup],
            [fieldLabel("Size:"), sizeRow()],
            [NSGridCell.emptyContentView, presetSizeCheckbox],
            [fieldLabel("Frame rate:"), ratePopup],
            [fieldLabel("Quality:"), qualityPopup],
            [fieldLabel("Range:"), rangePopup],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 106

        // The readout sits UNDER the grid rather than in its second column:
        // it is a full sentence and would run past the card's edge from an
        // indented start.
        let content = NSStackView(views: [grid, summaryLabel])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10

        let cancelButton = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        exportButton = StickerButton(
            title: "Export…", style: .primary, target: self, action: #selector(exportClicked(_:)))
        view = makeSheetView(
            title: "Export",
            hint: "The preset decides the codec and the container; the size, the frame rate, the "
                + "quality and the range override what it would otherwise take from the project.",
            content: content,
            buttonRow: makeButtonRow(
                cancel: cancelButton, apply: exportButton, leading: [footnote]))

        resolve()
    }

    private func sizeRow() -> NSStackView {
        let times = NSTextField(labelWithString: "×")
        times.font = DS.sans(13)
        times.textColor = DS.textMuted
        let stack = NSStackView(views: [widthField, times, heightField])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }

    // MARK: - Resolving

    /// Asks the core for the settings the current controls describe, then
    /// repaints the readout from the answer.
    ///
    /// A refusal is not an error dialog: the message goes in the readout and
    /// Export greys out, so a bad override reads as "this combination is not
    /// available" rather than interrupting the person adjusting it.
    private func resolve() {
        guard let project = editor?.document?.project, let preset = currentPreset else {
            resolved = nil
            resolveError = "This build has no export presets."
            syncReadout()
            return
        }
        do {
            resolved = try ReelExport.settings(
                project, preset: preset.id, overrides: overrides())
            resolveError = nil
        } catch {
            resolved = nil
            resolveError = error.localizedDescription
        }
        syncReadout()
    }

    private var currentPreset: ExportPreset? {
        let index = presetPopup.indexOfSelectedItem
        guard index >= 0, index < presets.count else { return nil }
        return presets[index]
    }

    private var currentApplies: Applies { Applies(currentPreset) }

    /// The frame-rate override, or nil for "Project rate" — and always nil
    /// for a preset that has no frames, so a rate picked for a movie cannot
    /// follow the user into an audio-only export.
    private var currentRate: Fps? {
        let index = ratePopup.indexOfSelectedItem - 1
        guard currentApplies.frameRate, index >= 0, index < Self.rates.count else { return nil }
        return Self.rates[index]
    }

    /// The quality tier, or nil for "Preset default" — and, on the same
    /// rule, always nil for a preset that takes no bit rate.
    private var currentTier: QualityTier? {
        let index = qualityPopup.indexOfSelectedItem - 1
        guard currentApplies.quality, index >= 0, index < Self.tiers.count else { return nil }
        return Self.tiers[index]
    }

    /// The frame the controls are ASKING for: the same numbers `overrides()`
    /// sends, plus the fallbacks the core would apply to them.
    ///
    /// The tiers are computed against this rather than against `resolved`,
    /// which still describes the PREVIOUS preset at the moment a new one is
    /// being resolved — the bit rate would then be one change behind the
    /// size it was supposed to be for.
    private func requestedFormat() -> (width: Int, height: Int, fps: Fps) {
        let canvas = editor?.document?.project.snapshot.canvas ?? CanvasSnapshot()
        var width = currentPreset?.width ?? canvas.width
        var height = currentPreset?.height ?? canvas.height
        if currentApplies.size, presetSizeCheckbox.state == .off {
            width = clampedSize(widthField)
            height = clampedSize(heightField)
        }
        return (width, height, currentRate ?? canvas.fps)
    }

    /// The override object, with every key the controls are NOT overriding
    /// left out — the same rule the op builders follow, so the core's own
    /// defaults apply (§6). Keys are the core's override names in
    /// `export.rs` — `width`, `height`, `fps`, `range`, `video_bitrate`,
    /// `audio_bitrate`.
    private func overrides() -> [String: Any]? {
        var overrides: [String: Any] = [:]
        let applies = currentApplies
        let format = requestedFormat()
        if applies.size, presetSizeCheckbox.state == .off {
            overrides["width"] = format.width
            overrides["height"] = format.height
        }
        if let fps = currentRate {
            overrides["fps"] = [fps.num, fps.den]
        }
        // Bits per second: the unit `export.rs` reads these two overrides in,
        // and the one `AVVideoAverageBitRateKey` takes after it. They are
        // sent separately because a preset may take one and not the other —
        // the audio-only row has no video rate to set, and a frame-sequence
        // row has neither.
        if let tier = currentTier {
            if applies.videoBitrate {
                overrides["video_bitrate"] = tier.videoBitsPerSecond(
                    width: format.width, height: format.height, fps: format.fps,
                    codec: currentPreset?.codec ?? "")
            }
            if applies.audioBitrate {
                overrides["audio_bitrate"] = tier.audioBitsPerSecond
            }
        }
        // The core reads the range as ONE nested object (`export.rs`), and
        // ignores override keys it does not know — so `start` and `duration`
        // spelled at the top level exported the whole project instead of the
        // in/out range, silently.
        if rangePopup.indexOfSelectedItem == 1, let range = range {
            overrides["range"] = [
                "start": range.start,
                "duration": max(0, range.end - range.start),
            ]
        }
        return overrides.isEmpty ? nil : overrides
    }

    private func clampedSize(_ field: NSTextField) -> Int {
        min(max(field.integerValue, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
    }

    /// Rewrites the readout, the footnote, the controls' enablement and the
    /// Export button from `resolved`. The size fields follow the core while
    /// the preset owns the size, which is what makes the checkbox readable:
    /// turn it off and the fields already hold the numbers to edit.
    ///
    /// Enablement comes from the PRESET rather than from `resolved`, so a
    /// refused resolve leaves the controls where they were instead of
    /// greying out the very one that has to be changed to fix it.
    private func syncReadout() {
        let applies = currentApplies
        let usingPreset = presetSizeCheckbox.state == .on
        presetSizeCheckbox.isEnabled = applies.size
        for field in [widthField, heightField] {
            field.isEnabled = applies.size && !usingPreset
            field.textColor = field.isEnabled ? DS.textStrong : DS.textMuted
        }
        ratePopup.isEnabled = applies.frameRate
        qualityPopup.isEnabled = applies.quality
        syncQualityTitles(applies)

        guard let settings = resolved else {
            summaryLabel.stringValue = resolveError ?? "These settings are not available."
            summaryLabel.textColor = DS.textStrong
            footnote.stringValue = ""
            exportButton?.isEnabled = false
            return
        }
        if usingPreset {
            widthField.integerValue = settings.width
            heightField.integerValue = settings.height
        }
        summaryLabel.textColor = DS.textMuted
        summaryLabel.stringValue = summary(for: settings)
        footnote.stringValue = footnoteText(for: settings)
        exportButton?.isEnabled = settings.duration > 0
    }

    /// Re-titles the tier rows with the rate each would ask for at the size
    /// and frame rate now chosen. "High" on its own says nothing; "High ·
    /// 8.0 Mbps" is the control's actual promise, and it has to move when
    /// the frame it is a rate for moves.
    private func syncQualityTitles(_ applies: Applies) {
        let format = requestedFormat()
        let codec = currentPreset?.codec ?? ""
        for (index, tier) in Self.tiers.enumerated() {
            guard let item = qualityPopup.item(at: index + 1) else { continue }
            if applies.videoBitrate {
                let rate = tier.videoBitsPerSecond(
                    width: format.width, height: format.height, fps: format.fps, codec: codec)
                item.title = "\(tier.name) · \(Self.rateText(rate))"
            } else if applies.audioBitrate {
                item.title = "\(tier.name) · \(Self.rateText(tier.audioBitsPerSecond))"
            } else {
                item.title = tier.name
            }
        }
    }

    /// The one-line description of what the file will contain.
    private func summary(for settings: ExportSettings) -> String {
        if settings.isAudioOnly {
            // Milliseconds rather than frames, and no rate in the line: audio
            // has no frames, which is the same reason the rate popup is
            // greyed out for this preset.
            let duration = ReelTime.format(settings.duration, fps: settings.fps, frames: false)
            return "Audio only · \(duration)"
        }
        let duration = ReelTime.format(settings.duration, fps: settings.fps, frames: true)
        var text = "\(settings.width) × \(settings.height) · \(settings.fps.displayName) fps · "
            + duration
        if Self.isFrameSequence(container: settings.container) {
            // What a GIF or an APNG costs is frames, not seconds — and it
            // carries no audio however much of it the timeline has, which is
            // worth saying before the export rather than after it.
            text += " · \(frameCount(settings)) frames, no audio"
        }
        return text
    }

    /// The bottom-left footnote: the codec, the container, and the rates the
    /// CORE resolved — never the ones the tier asked for, and not filtered by
    /// what the sheet thinks applies, since a preset is free to carry a rate
    /// of its own that no control here offered.
    ///
    /// The distinction matters because `export.rs` drops override keys it
    /// does not know, silently (the same trap the range comment above names).
    /// A tier picked against a core that has no bit-rate overrides has to
    /// read as "the preset's own rate" rather than let the popup imply a
    /// number the file will not have.
    private func footnoteText(for settings: ExportSettings) -> String {
        var parts = [settings.codec.uppercased()]
        let container = settings.container.uppercased()
        // A frame-sequence preset's codec IS its container: "GIF · GIF".
        if container != parts[0] { parts.append(container) }
        if let rate = settings.videoBitrate {
            parts.append(Self.rateText(rate))
        }
        if let rate = settings.audioBitrate {
            parts.append("\(Self.rateText(rate)) audio")
        }
        if currentTier != nil, settings.videoBitrate == nil, settings.audioBitrate == nil {
            parts.append("preset's own rate")
        }
        return parts.joined(separator: " · ")
    }

    /// How many frames the resolved range holds. Arithmetic on what the core
    /// answered, not a second opinion about it.
    private func frameCount(_ settings: ExportSettings) -> Int {
        let step = settings.fps.frameDuration
        guard step > 0 else { return 0 }
        return Int(settings.duration / step)
    }

    // MARK: - Controls

    @objc private func presetChanged(_ sender: Any?) {
        resolve()
    }

    @objc private func presetSizeChanged(_ sender: Any?) {
        resolve()
    }

    @objc private func rangeOrRateChanged(_ sender: Any?) {
        resolve()
    }

    @objc private func qualityChanged(_ sender: Any?) {
        resolve()
    }

    // MARK: - Commit

    @objc private func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    /// Hands off to the save panel, then to `EditorViewController`'s
    /// `beginExport`. The settings are captured BEFORE the dismissal: after
    /// it this controller's window is gone and its controls are on their way
    /// out of the view tree.
    @objc private func exportClicked(_ sender: Any?) {
        guard let editor = editor, let settings = resolved,
              let window = editor.view.window
        else {
            NSSound.beep()
            return
        }
        let name = suggestedName(for: settings, in: editor)
        dismiss(self)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = "Export the timeline as a movie."
        if let type = Exporter.contentType(for: settings) {
            panel.allowedContentTypes = [type]
        }
        // AppKit queues this behind the sheet that is on its way out, so the
        // panel appears once the settings card has finished leaving.
        panel.beginSheetModal(for: window) { [weak editor] response in
            guard response == .OK, let url = panel.url, let editor = editor else { return }
            editor.beginExport(settings: settings, to: url)
        }
    }

    /// The document's name with the container's extension. `displayName` is
    /// what the title bar says, including "Untitled Project".
    private func suggestedName(for settings: ExportSettings, in editor: EditorViewController)
        -> String
    {
        let base = editor.document?.displayName ?? "Untitled Project"
        let stem = (base as NSString).deletingPathExtension
        return (stem.isEmpty ? base : stem) + "." + Exporter.fileExtension(for: settings)
    }
}

// MARK: - Size fields

extension ExportSheetController: NSTextFieldDelegate {
    /// A custom size is re-resolved on commit, not per keystroke: every
    /// resolve is an FFI round trip, and a half-typed "19" is not a size
    /// anyone means.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard presetSizeCheckbox.state == .off else { return }
        resolve()
    }
}

// MARK: - Progress

/// The sheet that stays up for the write itself: a bar, a Cancel that really
/// stops the session, and — once the file lands — the result and a Show in
/// Finder (spec §10 step 10).
///
/// It owns the `Exporter`, which is why the export survives everything the
/// editor does next: the sheet is retained by the presenting controller for
/// as long as it is on screen, and nothing else holds the session.
final class ExportProgressSheetController: NSViewController {
    private let exporter = Exporter()
    /// The project handle as the export was confirmed. Handles are immutable
    /// (spec §5.5), so edits made after this point cannot reach the file.
    private let project: ReelProject
    private let urls: [UInt32: URL]
    private let settings: ExportSettings
    private let destination: URL

    private let bar = NSProgressIndicator()
    private let statusLabel = NSTextField(wrappingLabelWithString: "Preparing…")
    private let percentLabel = NSTextField(labelWithString: "0 %")
    /// Set in `loadView`; the only implicitly-unwrapped optionals the file has
    /// (app/CLAUDE.md allows them for exactly this).
    private var stopButton: NSButton!
    private var revealButton: NSButton!

    private var didStart = false
    private var didFinish = false

    init(project: ReelProject, urls: [UInt32: URL], settings: ExportSettings, to url: URL) {
        self.project = project
        self.urls = urls
        self.settings = settings
        self.destination = url
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ExportProgressSheetController does not support NSCoder")
    }

    override func loadView() {
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.doubleValue = 0
        bar.usesThreadedAnimation = true
        bar.widthAnchor.constraint(equalToConstant: sheetWidth - sheetInset * 2).isActive = true

        statusLabel.font = DS.sans(12)
        statusLabel.textColor = DS.textMuted
        statusLabel.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2
        statusLabel.stringValue = "Preparing “\(destination.lastPathComponent)”…"

        percentLabel.font = DS.mono(11)
        percentLabel.textColor = DS.textFaint

        let content = NSStackView(views: [bar, statusLabel, percentLabel])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8

        stopButton = StickerButton(
            title: "Cancel", style: .secondary, target: self, action: #selector(stopClicked(_:)))
        revealButton = StickerButton(
            title: "Show in Finder", style: .primary, target: self,
            action: #selector(revealClicked(_:)))
        // Hidden AND disabled while the export runs: AppKit skips both when it
        // looks for the Return key's target, so the sheet's only live button
        // is Cancel until there is a file to show.
        revealButton.isHidden = true
        revealButton.isEnabled = false

        view = makeSheetView(
            title: "Exporting",
            content: content,
            buttonRow: makeButtonRow(cancel: stopButton, apply: revealButton))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didStart else { return }
        didStart = true
        exporter.export(
            project: project, urls: urls, settings: settings, to: destination,
            progress: { [weak self] value in self?.progressed(value) },
            completion: { [weak self] result in self?.finished(result) })
    }

    // MARK: - Exporter callbacks

    private func progressed(_ value: Double) {
        guard !didFinish else { return }
        let clamped = min(max(value, 0), 1)
        bar.doubleValue = clamped
        percentLabel.stringValue = "\(Int((clamped * 100).rounded())) %"
        if clamped > 0 {
            statusLabel.stringValue = "Writing “\(destination.lastPathComponent)”…"
        }
    }

    /// The one exit for all three outcomes. Cancelling closes the sheet and
    /// removes the half-written file; success and failure both turn the sheet
    /// into its own result panel rather than trading it for an alert.
    private func finished(_ result: Result<URL, any Error>) {
        didFinish = true
        switch result {
        case .success(let url):
            bar.doubleValue = 1
            percentLabel.stringValue = "100 %"
            statusLabel.stringValue = "Exported “\(url.lastPathComponent)”."
            statusLabel.textColor = DS.textStrong
            stopButton.title = "Close"
            revealButton.isHidden = false
            revealButton.isEnabled = true
        case .failure(let error):
            if case Exporter.ExportError.cancelled = error {
                try? FileManager.default.removeItem(at: destination)
                dismiss(self)
                return
            }
            bar.doubleValue = 0
            percentLabel.stringValue = ""
            statusLabel.stringValue = error.localizedDescription
            statusLabel.textColor = DS.textStrong
            stopButton.title = "Close"
        }
    }

    // MARK: - Buttons

    /// Cancel while it runs, Close once it is over. One button because there
    /// is only ever one thing to do with a sheet that is busy.
    @objc private func stopClicked(_ sender: Any?) {
        guard !didFinish else {
            dismiss(self)
            return
        }
        stopButton.isEnabled = false
        statusLabel.stringValue = "Stopping…"
        exporter.cancel()
    }

    @objc private func revealClicked(_ sender: Any?) {
        guard didFinish else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
        dismiss(self)
    }
}
