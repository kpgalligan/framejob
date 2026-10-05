import AppKit

/// The export sheet's ANSWER half: read the controls, ask the core what they
/// describe, and repaint the card from what it said.
///
/// The seam is the §7 rule the sheet is built on, drawn as a file boundary.
/// `ExportSheetController.swift` owns the controls — it makes the popups and
/// the fields, lists the sizes, and hands a person something to choose with.
/// Nothing there decides an output size, a rate or a duration, because
/// nothing in this dialog does: every number the card shows comes back from
/// `rc_export_settings`, and this file is the whole of the round trip. It
/// turns a selection into the override object the core reads (`overrides()`),
/// sends it (`resolve()`), and writes the answer into the readout, the
/// footnote and the controls' enablement (`syncReadout()`). Between those
/// three, the `current…` accessors are the one place a popup index becomes a
/// meaning, so a control's index arithmetic is never spelled twice.
///
/// The one number the sheet DOES choose is the bit rate, and it is here for
/// that reason rather than beside the Quality popup: a tier is a REQUEST
/// (`ExportSheetOptions.swift` holds the ladder), and turning one into bits
/// per second needs the frame the controls are asking for — which is
/// `requestedFormat()`, three accessors deep into this file and nowhere near
/// the popup.
///
/// The cut is the size payment `ExportSheetController.swift` owed at 1114
/// lines against app/CLAUDE.md's ~600 cap, and it is a pure move: the same
/// methods, in the same order, with the same bodies. **The toll is
/// visibility**, for the reason `ExporterLoudness.swift` records — `private`
/// on an extension member reaches only its own file, and a stored property
/// cannot live in an extension at all. So every control, every field and
/// every piece of state this file reads is internal in the file that
/// declares it, and the four members the controls call back into —
/// `resolve()`, `currentPreset`, `isCustomSize` and `isCustomLoudness` — are
/// internal here. Everything else below stays `private`, because a `private`
/// extension member is reachable from the rest of THIS file, and nothing
/// outside it has ever asked.
/// Phase 7 added the OTHER direction to this file, and it belongs here for the
/// same reason the first one does: `currentChoice` is a reading of the
/// controls, exactly as `overrides()` is, and `apply(_:)` is that reading run
/// backwards. Keeping the pair together is what makes a saved preset and the
/// remembered choice provably the same thing as clicking each control by hand —
/// there is one account of what a stored choice means, and both halves of it
/// are on one screen.
extension ExportSheetController {

    // MARK: - Resolving

    /// Asks the core for the settings the current controls describe, then
    /// repaints the readout from the answer.
    ///
    /// A refusal is not an error dialog: the message goes in the readout and
    /// Export greys out, so a bad override reads as "this combination is not
    /// available" rather than interrupting the person adjusting it.
    func resolve() {
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
        // The same rule for the Custom loudness field, and for the same
        // reason: an empty field is not a target, and reading it as one would
        // export at whatever the clamp's floor happens to be.
        if isCustomLoudness, currentApplies.loudness, loudnessField.stringValue.isEmpty {
            resolved = nil
            resolveError = "Type a loudness target in LUFS, or pick one from the list."
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

    // MARK: - The card as a value

    /// The controls as an `ExportChoice`, with the sheet's own gating applied:
    /// a control the chosen format cannot take (`Applies`) contributes
    /// nothing, exactly as it contributes no override. So a preset saved off
    /// an audio-only row carries no size, and one saved off a GIF carries no
    /// loudness — the record says what was actually asked for and never what
    /// a greyed-out popup happened to be sitting on.
    ///
    /// **The burn-in is gated by that same rule and used not to be**, which
    /// broke the sentence above rather than any of the core's: a tick made on
    /// an H.264 row and carried across to WAV was written into the record
    /// beside a size, an fps and a tier all three deliberately left empty, so
    /// a named preset — and the remembered choice, which is this same
    /// value — said a file with no picture would carry a burn-in. It is not an
    /// override, so nothing downstream ever refused it; `Applies.burnIn`
    /// (below) is where it is refused now.
    ///
    /// The `name` is empty: naming a choice is the Save… item's business.
    var currentChoice: ExportChoice {
        var choice = ExportChoice(presetID: currentPreset?.id ?? "")
        if currentApplies.size {
            if isCustomSize {
                choice.customSize = [clampedSize(widthField), clampedSize(heightField)]
            } else {
                let index = sizePopup.indexOfSelectedItem
                // The ROW's id, never its index (`ExportChoice.sizeRow`).
                // Index 0 is recorded like any other: it is a row a person
                // chose, and `sizeOverride()`'s decision to send it as no
                // override at all is about the CORE's default and not about
                // what the popup was showing.
                if index >= 0, index < visibleSizes.count {
                    choice.sizeRow = visibleSizes[index].id
                }
            }
        }
        choice.fps = currentRate.map { [$0.num, $0.den] }
        choice.qualityTier = currentTier?.name
        choice.loudness = currentLoudness
        choice.inOutRange = rangePopup.indexOfSelectedItem == 1
        choice.burnInTimecode = currentApplies.burnIn && recipeOptions.burnInTimecode
        return choice
    }

    /// Writes a stored choice back into the controls. **The order is
    /// load-bearing and this method is where it is written down**; every
    /// caller — the remembered choice in `loadView`, a preset picked from the
    /// popup — goes through here so there is only ever one order.
    ///
    /// 1. **Format FIRST, before the sizes are listed.** A programmatic
    ///    `selectItem` sends no action, so `formatChanged`'s `sizesPreset`
    ///    guard never fires and nothing rebuilds on its own; listing after the
    ///    pick is what makes the rows this format's rows.
    /// 2. **Size AFTER `rebuildSizes()`**, which ends with an unconditional
    ///    `sizePopup.selectItem(at: 0)` and would undo a selection made before
    ///    it.
    /// 3. **A custom LOUDNESS selects "Custom…" first and fills the field
    ///    second**, because `syncReadout` overwrites that field from the popup
    ///    whenever the popup is not on Custom — and `resolve()` runs one
    ///    `syncReadout` after this returns.
    /// 4. **`in_out` degrades to "Whole project"** on a document that has no
    ///    range: the popup only carries that row when `range != nil`, so
    ///    selecting index 1 would select nothing at all.
    ///
    /// It does NOT resolve. The caller does, once, after the last control has
    /// moved — a resolve per control would be six FFI round trips to paint one
    /// card.
    func apply(_ choice: ExportChoice) {
        if let index = presets.firstIndex(where: { $0.id == choice.presetID }) {
            formatPopup.selectItem(at: index)
        }
        rebuildSizes()
        applySize(choice)

        if let fps = choice.fps, fps.count == 2,
            let index = Self.rates.firstIndex(where: { $0.num == fps[0] && $0.den == fps[1] })
        {
            ratePopup.selectItem(at: index + 1)
        } else {
            ratePopup.selectItem(at: 0)
        }

        if let name = choice.qualityTier,
            let index = Self.tiers.firstIndex(where: { $0.name == name })
        {
            qualityPopup.selectItem(at: index + 1)
        } else {
            qualityPopup.selectItem(at: 0)
        }

        applyLoudness(choice)
        rangePopup.selectItem(at: choice.inOutRange && range != nil ? 1 : 0)
        burnInCheckbox.state = choice.burnInTimecode ? .on : .off
    }

    /// Step 2, after the listing. A row whose id this format does not offer —
    /// a GIF's cap under H.264, or a row `visibleSizes` hid because an earlier
    /// row already has its numbers — falls back to the SAME NUMBERS under
    /// whatever row does show them, and only then to the format's default.
    /// Hiding is a tidiness of the popup's (`visibleSizes`), so a choice of
    /// "1080p" on a 1920 × 1080 document has to land on "Document size" rather
    /// than be dropped: it is the same export.
    private func applySize(_ choice: ExportChoice) {
        if let row = choice.sizeRow {
            if let index = visibleSizes.firstIndex(where: { $0.id == row }) {
                sizePopup.selectItem(at: index)
                return
            }
            if let hidden = sizes.first(where: { $0.id == row }),
                let index = visibleSizes.firstIndex(where: {
                    $0.width == hidden.width && $0.height == hidden.height
                })
            {
                sizePopup.selectItem(at: index)
                return
            }
            return
        }
        guard let custom = choice.customSize, custom.count == 2 else { return }
        // "Custom…" is the item after the last visible row.
        sizePopup.selectItem(at: visibleSizes.count)
        widthField.integerValue = custom[0]
        heightField.integerValue = custom[1]
    }

    /// Step 3: the row first, the field second.
    private func applyLoudness(_ choice: ExportChoice) {
        guard let target = choice.loudness else {
            loudnessPopup.selectItem(at: 0)
            return
        }
        if let index = Self.loudnessTargets.firstIndex(of: target) {
            loudnessPopup.selectItem(at: index + 1)
            return
        }
        loudnessPopup.selectItem(at: Self.loudnessTargets.count + 1)
        loudnessField.doubleValue = target
    }

    var currentPreset: ExportPreset? {
        let index = formatPopup.indexOfSelectedItem
        guard index >= 0, index < presets.count else { return nil }
        return presets[index]
    }

    private var currentApplies: Applies { Applies(currentPreset) }

    /// True while the Size popup's last item, "Custom…", is chosen — which is
    /// also the state of a popup whose listing failed, since Custom is then
    /// its only item; harmless, because `resolve()` refuses that case before
    /// the fields are read.
    var isCustomSize: Bool { sizePopup.indexOfSelectedItem == visibleSizes.count }

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

    /// True while the Loudness popup's last item, "Custom…", is chosen.
    var isCustomLoudness: Bool {
        loudnessPopup.indexOfSelectedItem == Self.loudnessTargets.count + 1
    }

    /// The integrated target to normalise to, or nil for "Off" — index 0 of
    /// the popup, on the Quality row's established rule that the first item
    /// is no override at all. Nil too for a format with no sound, so a target
    /// picked for a movie cannot follow the user into a GIF.
    private var currentLoudness: Double? {
        guard currentApplies.loudness else { return nil }
        let index = loudnessPopup.indexOfSelectedItem
        if index >= 1, index <= Self.loudnessTargets.count {
            return Self.loudnessTargets[index - 1]
        }
        guard isCustomLoudness, !loudnessField.stringValue.isEmpty else { return nil }
        let value = loudnessField.doubleValue
        guard value.isFinite else { return nil }
        return min(
            max(value, Self.loudnessRange.lowerBound), Self.loudnessRange.upperBound)
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
        // Both loudness keys together, always: the core refuses a
        // `peak_dbtp` with no `loudness_lufs` by name, because normalisation
        // is gain-only and a ceiling with nothing to cap would be a key
        // accepted, echoed and silently inert
        // (`export_overrides.rs::loudness`). The ceiling is fixed at
        // −1 dBTP in this phase and the hint says so.
        if let target = currentLoudness {
            overrides["loudness_lufs"] = target
            overrides["peak_dbtp"] = Self.peakCeilingDBTP
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
        loudnessPopup.isEnabled = applies.loudness
        loudnessField.isEnabled = applies.loudness && isCustomLoudness
        loudnessField.textColor = loudnessField.isEnabled ? DS.textStrong : DS.textMuted
        if !isCustomLoudness {
            // The field mirrors the row that is chosen, exactly as the size
            // fields mirror the core's answer, so picking "Custom…" starts
            // from the number that was in force a moment before. "Off" has no
            // number of its own, so it shows the first target — the one
            // Custom is most likely to be an adjustment of.
            loudnessField.doubleValue = currentLoudness ?? Self.loudnessTargets[0]
        }
        // The last control on the card, and the last one to be gated: the
        // burn-in stayed live on the three audio-only rows, alone among the
        // format-dependent controls, offering to write a timecode into a file
        // with no picture to write it into.
        burnInCheckbox.isEnabled = applies.burnIn

        guard let settings = resolved else {
            summaryLabel.stringValue = resolveError ?? "These settings are not available."
            summaryLabel.textColor = DS.textStrong
            footnote.stringValue = ""
            footnote.toolTip = nil
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
        footnote.toolTip = footnote.stringValue
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
        // The core's echo, not the popup's row: a build whose
        // `export_settings` has never heard of `loudness_lufs` drops the key
        // silently, and the footnote must not then promise a normalisation
        // the file will not have.
        if let target = settings.loudnessLufs {
            parts.append(
                String(format: "%g LUFS", target).replacingOccurrences(of: "-", with: "−"))
        }
        // Whether the ENCODING carries a fourth channel — the core's own
        // answer for this row (`ExportSettings.alpha`), never a reading of the
        // canvas. It is the one place the sheet says which format keeps a
        // transparent background, and it is a POSITIVE claim only: the rows
        // that answer false are not enumerated here, because the flag says
        // what the settings object says and the footnote's whole rule is that
        // it reports the core rather than the popup.
        if settings.alpha { parts.append("alpha") }
        return parts.joined(separator: " · ")
    }

    /// How many frames the resolved range holds. Arithmetic on what the core
    /// answered, not a second opinion about it.
    private func frameCount(_ settings: ExportSettings) -> Int {
        let step = settings.fps.frameDuration
        guard step > 0 else { return 0 }
        return Int(settings.duration / step)
    }
}

// MARK: - The control `Applies` was missing

extension ExportSheetController.Applies {
    /// Whether the picked format can take a burn-in.
    ///
    /// It was the one FORMAT-DEPENDENT control on the card that `Applies` did
    /// not answer for, and it stayed live on the three audio-only rows while
    /// Size, Frame rate and Quality greyed out around it — a checkbox
    /// promising to write a timecode into a file with no picture. The tick was
    /// inert on the FILE (`ExporterWriter.addVideo` returns at
    /// `settings.isAudioOnly`, so an audio-only export composes no frame at
    /// all), which is why nothing downstream ever complained; what it was not
    /// inert on is the RECORD, because `currentChoice` wrote it into a saved
    /// preset and into the remembered choice beside a size, an fps and a tier
    /// that same method had deliberately left empty.
    ///
    /// It answers `size`, and that is the definition rather than a
    /// coincidence: a burn-in is a TEXT LAYER drawn into the picture, so it
    /// applies exactly where a size does — both are `Applies`' own
    /// `hasVideo`. Spelled through `size` rather than through the preset
    /// because `hasVideo` is `private` to `ExportSheetOptions.swift`, and a
    /// second reading of `!preset.audioOnly` is precisely the drift `Applies`
    /// exists to prevent; it belongs beside its four siblings the next time
    /// that file is open.
    var burnIn: Bool { size }
}
