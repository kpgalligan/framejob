import AppKit

/// The menu bar's record indicator (road map 3, R1c) — the app's first
/// `NSStatusItem`: a red dot in `DS.meterClip` and the elapsed time while a
/// recording runs, with one menu item, Stop Recording. It exists because a
/// global stop hotkey would need an Input Monitoring or Accessibility grant,
/// and the recorder panel may be hidden (a picked-window recording orders it
/// out) or behind the application being recorded; a status item needs no
/// grant and is reachable from every Space.
///
/// It is created when a recording starts and removed the moment the
/// recording ENDS — before the landing, not after it: the item's one job is
/// to stop the recording, and once the recorder is finishing there is nothing
/// left for it to do. The elapsed label is pushed by the panel's own 30 Hz
/// timer (`update(elapsed:)`), so this class keeps no timer and no recorder;
/// it holds a closure for the stop, `AudioNormalize`'s value-in-value-out
/// posture applied to a control, so a probe can make one without the panel.
///
/// **That timer runs in `.common` run-loop modes, and this item is why**
/// (R1 review). Opening a status item's menu runs the main run loop in
/// event-tracking mode for as long as the menu is down, and a timer
/// scheduled in the default mode alone does not fire there — so the elapsed
/// label froze at the moment its menu opened, which is the one moment a
/// person is looking at it to decide whether to press Stop. The panel adds
/// its tick (and its countdown, for the same reason) with
/// `RunLoop.main.add(_:forMode: .common)`, and `update(elapsed:)` is then
/// called under the open menu as it is at any other time.
///
/// The fonts are the SYSTEM's, not `DS`'s: the menu bar is the OS's chrome
/// and a vendored face there would read as a foreign object. Monospaced
/// digits so the label does not jitter as the seconds tick.
final class RecorderStatusItem: NSObject {
    private let onStop: () -> Void
    private var item: NSStatusItem?

    init(onStop: @escaping () -> Void) {
        self.onStop = onStop
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RecorderStatusItem does not support NSCoder")
    }

    deinit { remove() }

    /// Whether the item is in the menu bar.
    var isShowing: Bool { item != nil }

    /// Puts the item up, at 0:00. A second call while showing is a no-op.
    func show() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu(title: "Recording")
        let stop = NSMenuItem(
            title: "Stop Recording", action: #selector(stopClicked(_:)), keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)
        item.menu = menu
        item.button?.toolTip = "Reelcut is recording"
        self.item = item
        update(elapsed: 0)
    }

    /// The panel's timer calls this at 30 Hz; the label changes once a second.
    func update(elapsed: TimeInterval) {
        item?.button?.attributedTitle = Self.title(elapsed: elapsed)
    }

    func remove() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
    }

    @objc private func stopClicked(_ sender: Any?) {
        onStop()
    }

    // MARK: - The label

    /// `m:ss`, and `h:mm:ss` past an hour. Pure, so a probe can pin it.
    static func label(for seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds.rounded(.down)))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let secs = whole % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// The dot in `DS.meterClip`, then the time in the menu bar's own face
    /// with monospaced digits.
    static func title(elapsed: TimeInterval) -> NSAttributedString {
        let size = NSFont.systemFontSize
        let title = NSMutableAttributedString(
            string: "●", attributes: [
                .font: NSFont.systemFont(ofSize: size), .foregroundColor: DS.meterClip,
            ])
        title.append(
            NSAttributedString(
                string: " " + label(for: elapsed),
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)]))
        return title
    }
}
