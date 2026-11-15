import AppKit

/// The editor toolbar's Contribute button (spec §11 TIP-6, TIP-9): green, right
/// of Export…, showing the Contribute dialog. **An experiment the owner may remove**:
/// deleting this file and its one line in `buildToolbar` removes it.
///
/// A view around one `AccentButton` (which is final) so that it can hide
/// ITSELF while Settings ▸ Contributions' toggle is off and follow
/// `TipsSettings.didChangeNotification`: the frozen editor file holds no
/// property for it, and a hidden arranged subview leaves no gap in the
/// toolbar's stack. The fill is `DS.tips`, a fixed green apart from the
/// action ink in both appearances (CI-4). The press is the nil-target
/// `showTips(_:)` on `AppDelegate`; it is not an edit, so it has no MCP
/// mirror.
final class TipsToolbarButton: NSView {
    static let title = "Contribute"
    static let tooltip = "Contribute to Frame Job"

    private let defaults: UserDefaults
    let button = AccentButton(
        title: TipsToolbarButton.title, symbol: nil, fallback: "",
        tooltip: TipsToolbarButton.tooltip, action: #selector(AppDelegate.showTips(_:)),
        fill: DS.tips)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init(frame: .zero)
        button.setAccessibilityIdentifier("toolbar.tips")
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged(_:)),
            name: TipsSettings.didChangeNotification, object: nil)
        sync()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TipsToolbarButton does not support NSCoder")
    }

    /// Shown exactly while the toggle is on.
    func sync() {
        isHidden = !TipsSettings.isEnabled(in: defaults)
    }

    @objc private func settingsChanged(_ note: Notification) {
        sync()
    }
}
