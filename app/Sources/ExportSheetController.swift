import AppKit
import UniformTypeIdentifiers

/// File ▸ Export… (⌘E) and the toolbar's Export button: pick a format and a
/// size, adjust the frame rate, the quality and the range, then a save panel
/// and a progress sheet (spec §7.8, §10 step 10).
///
/// Every number the sheet shows comes back from `rc_export_settings` — the
/// sheet never computes an output size, a rate or a duration itself. That is
/// the §7 rule ("Rust decides") applied to a dialog: the controls only say
/// what to ASK for, the core answers, and what the readout shows is exactly
/// what `Exporter` will be handed. It also means a format the core adds
/// tomorrow needs no change here: the Format popup is built from
/// `ReelExport.presets()` and the Size popup from `ReelExport.sizes`, so
/// GIF, APNG or anything else joins the menu the moment the core's table
/// lists it — with the sizes the core fits to this document — and `Applies`
/// below decides which of this sheet's controls that row can honestly take.
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

    /// The formats: the core's preset table, one row per encoding.
    private let presets: [ExportPreset]
    /// The core's Size rows for the current format, in its order, repeats
    /// included — the list `rc_export_sizes` answered, whose first row is
    /// the format's default. Kept whole: it is the record of what the core
    /// said, and `visibleSizes` is a reading of it, not a replacement.
    private var sizes: [ExportSize] = []
    /// The rows the Size popup shows: `sizes` minus every row whose numbers
    /// an earlier row already has. The popup's last item, "Custom…", is not
    /// one of them and sits at index `visibleSizes.count`, so this — never
    /// `sizes` — is what the popup's selection indexes.
    ///
    /// The hiding is the sheet's and not the core's, on purpose. A row's id
    /// is the `export` tool's vocabulary (`export_size.rs`), so `1080p` has
    /// to mean the same thing on every document, including the 1920 × 1080
    /// one where it is the document's own size — dropping it there would
    /// be the popup's tidiness leaking into an API. A person, though, reads
    /// the numbers, and one size under two names is a menu with a row that
    /// does nothing; the row that stays is the earliest, which is the one
    /// whose name says more ("Document size" over "1080p", "GIF default"
    /// over both on a document the cap already holds).
    private var visibleSizes: [ExportSize] = []
    /// The preset id `sizes` was listed for, so that a format pick which
    /// lands on the format already chosen rebuilds nothing — NSPopUpButton
    /// sends its action on every pick, the current row included, and a
    /// rebuild would put the popup back on the default row and let
    /// `syncReadout` write over a typed custom size. The preset id is the
    /// whole key because the list's other input, the document, cannot
    /// change while the sheet is up (every editor action validates false
    /// with a sheet attached).
    private var sizesPreset: String?
    /// The message the core refused the size listing with, or nil when it
    /// answered. Held so `resolve()` can show it: a popup that silently
    /// held only "Custom…" would export the fields' clamped floor, 16 × 16,
    /// as if someone had asked for it.
    private var sizesError: String?
    /// The in/out range at open time, if the document has one. Captured
    /// because the sheet blocks every edit while it is up, so it cannot move.
    private let range: (start: Ticks, end: Ticks)?

    /// The settings the core resolved for the current control values, and the
    /// message it refused with. Exactly one of the two is non-nil once
    /// `resolve()` has run.
    private var resolved: ExportSettings?
    private var resolveError: String?

    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    /// The custom size, on the row under the Size popup. Live only while
    /// "Custom…" is chosen; the rest of the time they mirror the core's
    /// answer, greyed, so picking Custom starts from the numbers of the row
    /// that was selected a moment before.
    private let widthField = NSTextField(string: "")
    private let heightField = NSTextField(string: "")
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
    /// Internal, not private: the agent's `export` refuses a custom size
    /// outside it by name (`AgentServer+Render.swift`), and one constant is
    /// how the sheet and the tool cannot disagree.
    static let sizeRange = 16...8192

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

    /// The tiers, in menu order. Index 0 of the popup is "Format default",
    /// i.e. no override at all — the format's own rate, or the export
    /// session's ladder when it carries none.
    private static let tiers: [QualityTier] = [
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
        formatPopup.addItems(withTitles: presets.map { $0.name })
        // The sheet opens on the first row of each of the core's two lists:
        // the H.264 format (`export.rs`, `PRESETS`) and, in its Size popup,
        // the document's own size (`export_size.rs`), so that ⌘E exports the
        // document as it is unless a person picks otherwise. Each default
        // has one home — the order of its list — and this is only the
        // reading of it, made explicit, and guarded so that an empty table
        // reaches `resolve()`'s own message rather than a selection out of
        // range.
        if !presets.isEmpty { formatPopup.selectItem(at: 0) }
        formatPopup.font = DS.sans(13)
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged(_:))
        formatPopup.widthAnchor.constraint(equalToConstant: 240).isActive = true

        sizePopup.font = DS.sans(13)
        sizePopup.target = self
        sizePopup.action = #selector(sizeChanged(_:))
        sizePopup.widthAnchor.constraint(equalToConstant: 240).isActive = true
        rebuildSizes()

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

        ratePopup.addItem(withTitle: "Project rate")
        ratePopup.addItems(withTitles: Self.rates.map { "\($0.displayName) fps" })
        ratePopup.font = DS.sans(13)
        ratePopup.target = self
        ratePopup.action = #selector(rangeOrRateChanged(_:))
        ratePopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

        qualityPopup.addItem(withTitle: "Format default")
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
            [fieldLabel("Format:"), formatPopup],
            [fieldLabel("Size:"), sizePopup],
            // The custom fields get a row of their own under the popup: the
            // card is 420 wide with 22 insets and a 106 label column, so a
            // 240 popup fits beside its label and the popup plus two fields
            // does not.
            [NSGridCell.emptyContentView, sizeRow()],
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
            hint: "The format decides the codec and the container. Size, frame rate and "
                + "range start as the document's and quality as the format's; a GIF or an "
                + "APNG starts at its own cap and rate.",
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

    /// Lists the core's rows for the current format, refills the Size popup
    /// with the ones worth showing (`visibleSizes`) and puts it back on the
    /// first — that format's default — so a size picked under one format
    /// cannot follow the person into another whose default is different
    /// (GIF's is its cap, H.264's is the document). Called once from
    /// `loadView` and then only when the format actually changes
    /// (`formatChanged`), which is what lets a custom size survive a pick.
    ///
    /// A listing the core refuses leaves only "Custom…" in the popup, and
    /// its message in `sizesError` for `resolve()` to show — there, not
    /// here, because the readout is repainted by every resolve and a
    /// message written into it now would be gone by the next one.
    private func rebuildSizes() {
        sizes = []
        sizesError = nil
        sizesPreset = currentPreset?.id
        if let project = editor?.document?.project, let preset = currentPreset {
            do {
                sizes = try ReelExport.sizes(project, preset: preset.id)
            } catch {
                sizesError = error.localizedDescription
            }
        }
        visibleSizes = sizes.reduce(into: []) { shown, row in
            if !shown.contains(where: { $0.width == row.width && $0.height == row.height }) {
                shown.append(row)
            }
        }
        sizePopup.removeAllItems()
        sizePopup.addItems(
            withTitles: visibleSizes.map { "\($0.name) · \($0.width) × \($0.height)" })
        sizePopup.addItem(withTitle: "Custom…")
        sizePopup.selectItem(at: 0)
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
        // A format whose sizes the core could not list is not exported at
        // all, whatever the settings call would answer: the one refusal
        // `rc_export_sizes` shares with `rc_export_settings` is an unknown
        // preset, but a listing can also fail on its own (a reply this
        // build cannot decode), and the size the sheet would then send is
        // the fields' clamped floor, 16 × 16, which nobody asked for.
        if let message = sizesError {
            resolved = nil
            resolveError = message
            syncReadout()
            return
        }
        // An empty Custom field is not a size. Its formatter accepts the
        // empty string as "no value", `integerValue` reads that as 0, and
        // the clamp would turn it into the 16-pixel floor — an export
        // nobody asked for, reached by clearing a field and clicking
        // Export…, since that click commits the field before it reads.
        if isCustomSize, currentApplies.size,
            widthField.stringValue.isEmpty || heightField.stringValue.isEmpty
        {
            resolved = nil
            resolveError = "Type a width and a height, or pick a size from the list."
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
        let index = formatPopup.indexOfSelectedItem
        guard index >= 0, index < presets.count else { return nil }
        return presets[index]
    }

    private var currentApplies: Applies { Applies(currentPreset) }

    /// True while the Size popup's last item, "Custom…", is chosen — which is
    /// also the state of a popup whose listing failed, since Custom is then
    /// its only item; harmless, because `resolve()` refuses that case before
    /// the fields are read.
    private var isCustomSize: Bool { sizePopup.indexOfSelectedItem == visibleSizes.count }

    /// The frame-rate override, or nil for "Project rate" — and always nil
    /// for a preset that has no frames, so a rate picked for a movie cannot
    /// follow the user into an audio-only export.
    private var currentRate: Fps? {
        let index = ratePopup.indexOfSelectedItem - 1
        guard currentApplies.frameRate, index >= 0, index < Self.rates.count else { return nil }
        return Self.rates[index]
    }

    /// The quality tier, or nil for "Format default" — and, on the same
    /// rule, always nil for a preset that takes no bit rate.
    private var currentTier: QualityTier? {
        let index = qualityPopup.indexOfSelectedItem - 1
        guard currentApplies.quality, index >= 0, index < Self.tiers.count else { return nil }
        return Self.tiers[index]
    }

    /// The size override, or nil when the Size popup is on its first row.
    ///
    /// That row is the format's default — the first of the core's list and
    /// of `visibleSizes` alike, since nothing precedes it to hide it — and
    /// it is sent as NO override rather than as its own numbers so that
    /// what ⌘E exports and what the `export` tool exports with no `size`
    /// are one code path in the core — the default lives in
    /// `export_size.rs`, not in two readings of it. Any other row sends
    /// that row's numbers; "Custom…" sends the fields', clamped. Nil too
    /// for a format that has no frames, so a size picked for a movie cannot
    /// follow the user into an audio-only export.
    private func sizeOverride() -> (width: Int, height: Int)? {
        guard currentApplies.size else { return nil }
        if isCustomSize {
            return (clampedSize(widthField), clampedSize(heightField))
        }
        let index = sizePopup.indexOfSelectedItem
        guard index > 0, index < visibleSizes.count else { return nil }
        return (visibleSizes[index].width, visibleSizes[index].height)
    }

    /// The frame the controls are ASKING for: the same numbers `overrides()`
    /// sends, plus the fallbacks the core would apply to them.
    ///
    /// The tiers are computed against this rather than against `resolved`,
    /// which still describes the PREVIOUS format at the moment a new one is
    /// being resolved — the bit rate would then be one change behind the
    /// size it was supposed to be for.
    private func requestedFormat() -> (width: Int, height: Int, fps: Fps) {
        let canvas = editor?.document?.project.snapshot.canvas ?? CanvasSnapshot()
        // No override resolves to the Size popup's first row. The format's
        // own cap, then the canvas, stand in for it only when the listing
        // failed — the same fallback the core applies to a preset with no
        // size (`export.rs`).
        var width = sizes.first?.width ?? currentPreset?.width ?? canvas.width
        var height = sizes.first?.height ?? currentPreset?.height ?? canvas.height
        if let size = sizeOverride() {
            width = size.width
            height = size.height
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
        if let size = sizeOverride() {
            overrides["width"] = size.width
            overrides["height"] = size.height
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
    /// a row of the Size popup owns the size, which is what makes "Custom…"
    /// readable: pick it and the fields already hold the numbers to edit.
    ///
    /// Enablement comes from the FORMAT rather than from `resolved`, so a
    /// refused resolve leaves the controls where they were instead of
    /// greying out the very one that has to be changed to fix it.
    private func syncReadout() {
        let applies = currentApplies
        let custom = isCustomSize
        // A popup whose listing failed holds nothing to choose, and the one
        // control that can put a size back is the Format popup, so the size
        // controls grey out with it — the exception to the rule in the doc
        // comment above, for the one refusal no size can fix.
        let listed = sizesError == nil
        sizePopup.isEnabled = applies.size && listed
        for field in [widthField, heightField] {
            field.isEnabled = applies.size && listed && custom
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
        if !custom {
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
    /// read as "the format's own rate" rather than let the popup imply a
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
            parts.append("format's own rate")
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

    /// A new format means a new Size list — its default may differ — so the
    /// popup is rebuilt before the resolve. The rate, quality and range
    /// choices stay where they are; `Applies` decides whether they count.
    ///
    /// The SAME format, picked again, is not a change: NSPopUpButton sends
    /// its action for every pick, and rebuilding here would reset the Size
    /// popup to its default and overwrite a typed custom size with the
    /// core's answer for it (`sizesPreset`). Nothing else moved either, so
    /// there is nothing to resolve.
    @objc private func formatChanged(_ sender: Any?) {
        guard currentPreset?.id != sizesPreset else { return }
        rebuildSizes()
        resolve()
    }

    /// Picking "Custom…" needs no pre-fill of its own: `syncReadout` kept
    /// the fields mirroring the core's answer for the row that was selected,
    /// so they hold that row's numbers at the moment they come live.
    @objc private func sizeChanged(_ sender: Any?) {
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
        // End any edit in a Custom field first. A mouse click on a button
        // does not take the first responder from a text field, so the value
        // typed there has not been committed — `controlTextDidEndEditing`,
        // and the resolve it runs, fire only when the field editor resigns —
        // and `resolved` still describes the size from BEFORE the edit.
        // Handing the first responder to nobody makes it resign now,
        // synchronously, so the read below sees the numbers on screen. A
        // field whose text its formatter rejects refuses to resign; that is
        // the person's to fix, so the click just beeps.
        if let sheetWindow = view.window, !sheetWindow.makeFirstResponder(nil) {
            NSSound.beep()
            return
        }
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
        panel.message = Self.panelMessage(for: settings)
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

    /// The save panel's one line about what is being written. "As a movie"
    /// was wrong for half the table: a GIF or an APNG is an animated image
    /// and the audio-only row writes no picture at all. The classes are the
    /// sheet's own (`Applies`, `isFrameSequence`), so a format that is
    /// neither is a movie by the same reading that gave it a Size popup.
    private static func panelMessage(for settings: ExportSettings) -> String {
        if settings.isAudioOnly { return "Export the timeline's audio." }
        if isFrameSequence(container: settings.container) {
            return "Export the timeline as an animated \(settings.container.uppercased())."
        }
        return "Export the timeline as a movie."
    }
}

// MARK: - Size fields

extension ExportSheetController: NSTextFieldDelegate {
    /// A custom size is re-resolved on commit, not per keystroke: every
    /// resolve is an FFI round trip, and a half-typed "19" is not a size
    /// anyone means. A commit is Return, Tab, a click into the other field,
    /// or `exportClicked` ending the edit on its way to the save panel.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard isCustomSize else { return }
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
