import AppKit

/// Settings' Playback pane (spec §11 G-38 (a)): Background render, on, and
/// the idle wait before it starts, under the Transcription pane in
/// `SettingsWindowController`'s one stack. Its heading carries a
/// `SettingsInfoButton` holding `explanation()` (SH-5).
///
/// One row, AssistantSettingsPane's compaction row's shape: the checkbox,
/// "Start after", the seconds field and its stepper, "seconds". The field and
/// the stepper are enabled only while the box is ticked. Each control saves
/// at once through `BackgroundRenderSettings.save`, with no Save button; a
/// field value outside `delayRange` beeps and shows the stored value again,
/// writing nothing. The pane holds no reference to `BackgroundRender`: a
/// click or a key in it is activity like any other, and every restart of
/// the idle clock reads the stored delay. It is a person's setting — no tool
/// reads or writes it (AI-11, R6-12).
final class PlaybackSettingsPane: NSStackView {
    static let paneTitle = "Playback"
    static let backgroundTitle = "Background render"
    static let delayText = "Start after"
    static let secondsText = "seconds"

    private let defaults: UserDefaults

    let headingLabel = NSTextField(labelWithString: PlaybackSettingsPane.paneTitle)
    /// The heading's ⓘ, holding `explanation()` (SH-5).
    let infoButton = SettingsInfoButton(
        section: PlaybackSettingsPane.paneTitle, infoText: PlaybackSettingsPane.explanation())
    let backgroundBox = NSButton(
        checkboxWithTitle: PlaybackSettingsPane.backgroundTitle, target: nil, action: nil)
    let delayField = NSTextField()
    let delayStepper = NSStepper()
    let secondsLabel = NSTextField(labelWithString: PlaybackSettingsPane.secondsText)

    init(defaults: UserDefaults) {
        self.defaults = defaults
        super.init(frame: .zero)
        build()
        sync()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PlaybackSettingsPane does not support NSCoder")
    }

    private func build() {
        headingLabel.font = DS.sans(15, weight: .bold)
        headingLabel.textColor = DS.textStrong
        headingLabel.setAccessibilityIdentifier("settings.playback.heading")
        infoButton.setAccessibilityIdentifier("settings.playback.info")

        backgroundBox.font = DS.sans(13)
        backgroundBox.target = self
        backgroundBox.action = #selector(backgroundToggled(_:))
        backgroundBox.setAccessibilityIdentifier("settings.playback.background")

        let delayLabel = fieldLabel(Self.delayText)
        DSField.style(delayField)
        delayField.alignment = .right
        delayField.target = self
        delayField.action = #selector(delayChanged(_:))
        delayField.cell?.sendsActionOnEndEditing = true
        delayField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        delayField.setAccessibilityIdentifier("settings.playback.delay")

        let range = BackgroundRenderSettings.delayRange
        delayStepper.minValue = Double(range.lowerBound)
        delayStepper.maxValue = Double(range.upperBound)
        delayStepper.increment = 1
        delayStepper.valueWraps = false
        delayStepper.autorepeat = true
        delayStepper.target = self
        delayStepper.action = #selector(delayStepped(_:))
        delayStepper.setAccessibilityIdentifier("settings.playback.stepper")

        secondsLabel.font = DS.sans(13)
        secondsLabel.textColor = DS.textMuted

        orientation = .vertical
        alignment = .leading
        spacing = 12
        let delayRow = NSStackView(
            views: [backgroundBox, delayLabel, delayField, delayStepper, secondsLabel])
        delayRow.orientation = .horizontal
        delayRow.alignment = .centerY
        delayRow.spacing = 6
        // Hugs at its content, so its width is not a tie with the column's (#143).
        delayRow.setHuggingPriority(.required, for: .horizontal)
        addArrangedSubview(settingsSectionHeader(headingLabel, info: infoButton))
        addArrangedSubview(delayRow)
    }

    // MARK: - Syncing

    /// The stored setting on the controls; the field and the stepper enabled
    /// only while the box is ticked, the field never written while it is
    /// being edited. Reads only, never writes.
    func sync() {
        let settings = BackgroundRenderSettings.load(from: defaults)
        backgroundBox.state = settings.enabled ? .on : .off
        delayField.isEnabled = settings.enabled
        delayStepper.isEnabled = settings.enabled
        delayStepper.integerValue = settings.delaySeconds
        if delayField.currentEditor() == nil {
            delayField.stringValue = String(settings.delaySeconds)
        }
    }

    // MARK: - Controls

    @objc func backgroundToggled(_ sender: Any?) {
        var settings = BackgroundRenderSettings.load(from: defaults)
        settings.enabled = backgroundBox.state == .on
        settings.save(to: defaults)
        sync()
    }

    /// The field's commit (Return or leaving it). Outside the range beeps and
    /// shows the stored value again, writing nothing.
    @objc func delayChanged(_ sender: Any?) {
        var settings = BackgroundRenderSettings.load(from: defaults)
        let typed = delayField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = Int(typed), BackgroundRenderSettings.delayRange.contains(seconds) else {
            NSSound.beep()
            delayField.stringValue = String(settings.delaySeconds)
            return
        }
        settings.delaySeconds = seconds
        settings.save(to: defaults)
        sync()
        delayField.stringValue = String(seconds)
    }

    @objc func delayStepped(_ sender: Any?) {
        var settings = BackgroundRenderSettings.load(from: defaults)
        settings.delaySeconds = delayStepper.integerValue
        settings.save(to: defaults)
        sync()
        delayField.stringValue = String(settings.delaySeconds)
    }

    /// The ⓘ's text in two paragraphs: what the pass does and when, and
    /// where its frames are held.
    static func explanation() -> String {
        [
            "While you leave Frame Job alone for the time set here, it draws the graphics "
                + "after the playhead in the window you last used, so they play smoothly from the "
                + "start. It stops as soon as you do anything in Frame Job and starts again after "
                + "the same wait, and it keeps the processor busy while it runs.",
            "The frames are held in memory, at most a quarter of this Mac's and less when memory "
                + "is short, until the window closes or newer frames replace them.",
        ].joined(separator: "\n\n")
    }
}
