import AppKit
import UniformTypeIdentifiers

/// File ▸ Export… (⌘E) and the toolbar's Export button: pick a preset, adjust
/// the size, the frame rate and the range, then a save panel and a progress
/// sheet (spec §7.8, §10 step 10).
///
/// Every number the sheet shows comes back from `rc_export_settings` — the
/// sheet never computes an output size, a rate or a duration itself. That is
/// the §7 rule ("Rust decides") applied to a dialog: the controls only say
/// what to ASK for, the core answers, and what the readout shows is exactly
/// what `Exporter` will be handed. It also means a preset the core adds
/// tomorrow needs no change here.
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
            hint: "The preset decides the codec and the container; the size, the frame rate and "
                + "the range override what it would otherwise take from the project.",
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

    /// The override object, with every key the controls are NOT overriding
    /// left out — the same rule the op builders follow, so the core's own
    /// defaults apply (§6). Keys are the core's override names in
    /// `export.rs` — `width`, `height`, `fps`, `range`.
    private func overrides() -> [String: Any]? {
        var overrides: [String: Any] = [:]
        if presetSizeCheckbox.state == .off {
            overrides["width"] = clampedSize(widthField)
            overrides["height"] = clampedSize(heightField)
        }
        let rate = ratePopup.indexOfSelectedItem - 1
        if rate >= 0, rate < Self.rates.count {
            let fps = Self.rates[rate]
            overrides["fps"] = [fps.num, fps.den]
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

    /// Rewrites the readout, the footnote, the size fields and the Export
    /// button from `resolved`. The size fields follow the core while the
    /// preset owns the size, which is what makes the checkbox readable: turn
    /// it off and the fields already hold the numbers to edit.
    private func syncReadout() {
        let usingPreset = presetSizeCheckbox.state == .on
        for field in [widthField, heightField] {
            field.isEnabled = !usingPreset
            field.textColor = usingPreset ? DS.textMuted : DS.textStrong
        }

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
        let duration = ReelTime.format(settings.duration, fps: settings.fps, frames: true)
        if settings.isAudioOnly {
            summaryLabel.stringValue = "Audio only · \(settings.fps.displayName) fps · \(duration)"
        } else {
            summaryLabel.stringValue =
                "\(settings.width) × \(settings.height) · \(settings.fps.displayName) fps · "
                + duration
        }
        footnote.stringValue =
            "\(settings.codec.uppercased()) · \(settings.container.uppercased())"
        exportButton?.isEnabled = settings.duration > 0
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
