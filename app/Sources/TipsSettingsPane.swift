import AppKit

/// Settings' Tips pane (spec §11 TIP-6): the window's last. A bare heading,
/// one visible sentence, the toggle and a Tips button.
///
/// **The toggle** (`TipsSettings`, on by default) decides two things at once:
/// whether the editor shows its Tips button, and whether Frame Job ever shows
/// the dialog by itself. It saves when it is pressed, with no Save button, and
/// every open editor follows `TipsSettings.didChangeNotification`.
///
/// **The button is always there.** It shows the dialog whatever the toggle
/// says, and is never hidden or disabled: with the toggle off it is the one
/// way left to reach the dialog. What it shows is a parameter, so a probe
/// presses it without a window appearing.
///
/// **No ⓘ.** The sentence is short enough to show (under SH-5's 200
/// characters), and the dialog one press away says the rest. It is a
/// person's setting: no tool reads or writes it (R6-12, MC-7).
final class TipsSettingsPane: NSStackView {
    static let paneTitle = "Tips"
    static let blurb = "Frame Job is free and open source, made by one developer. Tips are voluntary."
    static let toggleTitle = "Show the Tips button and the yearly reminder"
    static let buttonTitle = "Tips"
    /// The Settings window's width less its two insets.
    private static let textWidth: CGFloat = 420

    private let defaults: UserDefaults
    private let showTips: () -> Void

    let headingLabel = NSTextField(labelWithString: TipsSettingsPane.paneTitle)
    let blurbLabel = NSTextField(wrappingLabelWithString: TipsSettingsPane.blurb)
    let toggleBox = NSButton(
        checkboxWithTitle: TipsSettingsPane.toggleTitle, target: nil, action: nil)
    private(set) var tipsButton: NSButton!

    init(defaults: UserDefaults, showTips: @escaping () -> Void) {
        self.defaults = defaults
        self.showTips = showTips
        super.init(frame: .zero)
        build()
        sync()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TipsSettingsPane does not support NSCoder")
    }

    private func build() {
        headingLabel.font = DS.sans(15, weight: .bold)
        headingLabel.textColor = DS.textStrong
        headingLabel.setAccessibilityIdentifier("settings.tips.heading")

        blurbLabel.font = DS.sans(13)
        blurbLabel.textColor = DS.textStrong
        blurbLabel.preferredMaxLayoutWidth = Self.textWidth
        blurbLabel.setAccessibilityIdentifier("settings.tips.blurb")

        toggleBox.font = DS.sans(13)
        toggleBox.target = self
        toggleBox.action = #selector(toggled(_:))
        toggleBox.setAccessibilityIdentifier("settings.tips.toggle")

        tipsButton = StickerButton(
            title: Self.buttonTitle, style: .secondary, target: self,
            action: #selector(tipsClicked(_:)))
        tipsButton.setAccessibilityIdentifier("settings.tips.button")

        orientation = .vertical
        alignment = .leading
        spacing = 12
        for view in [headingLabel, blurbLabel, toggleBox, tipsButton] as [NSView] {
            addArrangedSubview(view)
        }
    }

    /// The stored toggle on the box. Reads only.
    func sync() {
        toggleBox.state = TipsSettings.isEnabled(in: defaults) ? .on : .off
    }

    @objc func toggled(_ sender: Any?) {
        TipsSettings.setEnabled(toggleBox.state == .on, in: defaults)
        sync()
    }

    @objc func tipsClicked(_ sender: Any?) {
        showTips()
    }
}
