import AppKit

/// The menu bar's record indicator (road map 3, R1c), and since R2c the
/// recording's CONTROLS — the app's first `NSStatusItem`: a dot in
/// `DS.meterClip` and the elapsed time while a recording runs, a pause
/// glyph and the FROZEN time while it is paused, and a two-row menu that
/// reads Pause Recording · Stop Recording, then Resume Recording · Stop
/// Recording while paused. It exists because a global hotkey would need an
/// Input Monitoring or Accessibility grant, and because the recorder panel
/// is OFF SCREEN for the recording's whole span (decision 7: it orders out
/// at `recordingDidStart` whatever the source, and comes back only with
/// something to say) — so this item is the recording's whole chrome, and it
/// needs no grant and is reachable from every Space.
///
/// It is created when a recording starts and removed the moment the
/// recording ENDS — before the landing, not after it: once the recorder is
/// finishing there is nothing left for it to do. The label is pushed by its
/// owner's timer (`update(elapsed:paused:)` — the panel's at 30 Hz, the
/// tool's at 1 Hz), so this class keeps no timer and no recorder; it holds
/// three closures, `AudioNormalize`'s value-in-value-out posture applied to
/// a control, so a probe can make one without the panel. It never asks
/// whether a pause SUCCEEDED: the owner's next `update` says, by `paused`,
/// and that is the one place the menu is decided.
///
/// **The menu is rebuilt only when `paused` FLIPS, never per tick**, and
/// the rows are replaced inside the one `NSMenu` the item was shown with
/// rather than the menu swapped. A status item's menu may be OPEN when a
/// tick fires — the tracking run loop delivers the timer (below) — and a
/// title change under an open menu is harmless where rebuilding its rows
/// thirty times a second is not; the flip itself cannot arrive under the
/// open menu from the menu's own row, because a click closes the menu
/// before its action runs. `menuTitles(paused:)` and
/// `title(elapsed:paused:)` are PURE, which is how a probe pins both menus
/// and both labels without a menu bar.
///
/// **`freeze()` pins the mark from the owner's Stop on** (R2 review). The
/// owner's tick goes on calling `update` through its stopping phase, with
/// `paused` read off a phase that is `.stopping` and no longer `.paused`,
/// so a Stop from paused used to bring the coral dot back for the second or
/// two the finish takes — a recording that was not capturing, shown as
/// capturing. Frozen, `update` keeps the mark and the menu it last showed
/// and moves only the time; the panel calls it in `stopRecording()`, the
/// tool's chrome at its Stop. And `openMenu()` is a click on the button —
/// it pops the menu exactly as a person's click would — for the quit guard
/// while the panel is hidden (`RecorderPanelController.revealControls`), so
/// a person who paused and forgot is shown Pause, Resume and Stop rather
/// than beeped at.
///
/// **That timer runs in `.common` run-loop modes, and this item is why**
/// (R1 review). Opening a status item's menu runs the main run loop in
/// event-tracking mode for as long as the menu is down, and a timer
/// scheduled in the default mode alone does not fire there — so the elapsed
/// label froze at the moment its menu opened, which is the one moment a
/// person is looking at it to decide whether to press Stop. The panel adds
/// its tick (and its countdown, for the same reason) with
/// `RunLoop.main.add(_:forMode: .common)`, and `update(elapsed:paused:)` is
/// then called under the open menu as it is at any other time.
///
/// **One fixed length** (#98). The item is sized ONCE, `itemLength`: the
/// widest title either mark makes at `widestElapsed` (9:59:59) plus
/// `titleInset` each side, so the menu bar's other items never shift as the
/// seconds tick, the hour appears or the mark flips between the dot and
/// the pause glyph. A label past 9:59:59 is wider than that; it is not
/// sized for.
///
/// The fonts are the SYSTEM's, not `DS`'s: the menu bar is the OS's chrome
/// and a vendored face there would read as a foreign object. Monospaced
/// digits so the label does not jitter as the seconds tick. The pause
/// glyph takes NO colour of its own — the coral dot means "capturing", and
/// a paused recording is not — so it is drawn in whatever the menu bar
/// draws its text in, light or dark.
final class RecorderStatusItem: NSObject {
    /// Two heavy vertical bars (U+275A). The panel's footnote spells a pause
    /// with the same glyph, from here, so the two never drift apart.
    static let pauseGlyph = "❚❚"
    /// The longest time the item is sized for (the type doc).
    static let widestElapsed: TimeInterval = 35_999
    /// Room each side of the title inside the item.
    static let titleInset: CGFloat = 6
    /// The item's one length: the wider of the two marks' titles at
    /// `widestElapsed`, rounded up, plus the insets (the type doc).
    static let itemLength: CGFloat = [false, true].map { paused in
        ceil(RecorderStatusItem.title(elapsed: widestElapsed, paused: paused).size().width)
            + 2 * titleInset
    }.reduce(0, max)

    private let onPause: () -> Void
    private let onResume: () -> Void
    private let onStop: () -> Void
    private var item: NSStatusItem?
    /// Which of the two menus the item shows. `update` compares `paused`
    /// with it before touching the menu (the type doc).
    private var menuShowsPaused = false
    /// Set by `freeze()`: `update` then reads its mark from `menuShowsPaused`
    /// and never from the argument.
    private var frozen = false

    init(
        onPause: @escaping () -> Void, onResume: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        self.onPause = onPause
        self.onResume = onResume
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

    /// Puts the item up, at 0:00 with the RECORDING menu and its one fixed
    /// length. A second call while showing is a no-op.
    func show() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: Self.itemLength)
        item.menu = NSMenu(title: "Recording")
        self.item = item
        menuShowsPaused = false
        frozen = false
        rebuildMenu(paused: false)
        item.button?.toolTip = Self.tooltip(paused: false)
        update(elapsed: 0, paused: false)
    }

    /// The owner's timer calls this — 30 Hz from the panel, 1 Hz from the
    /// tool — with the recorder's `elapsed`, which freezes while paused, so
    /// a paused label holds still on its own. The menu and the tooltip are
    /// rebuilt only when `paused` differs from what they show; frozen, the
    /// argument is ignored and the mark stays (the type doc).
    func update(elapsed: TimeInterval, paused: Bool) {
        guard let item else { return }
        let paused = frozen ? menuShowsPaused : paused
        item.button?.attributedTitle = Self.title(elapsed: elapsed, paused: paused)
        guard paused != menuShowsPaused else { return }
        menuShowsPaused = paused
        rebuildMenu(paused: paused)
        item.button?.toolTip = Self.tooltip(paused: paused)
    }

    /// From the owner's Stop on: the mark and the menu stay what they last
    /// were, whatever `update` is told (the type doc).
    func freeze() {
        frozen = true
    }

    /// A click on the item's button, which pops its menu as a person's click
    /// would (the type doc); false with no item to click, which the caller
    /// answers with a beep.
    @discardableResult
    func openMenu() -> Bool {
        guard let button = item?.button else { return false }
        button.performClick(nil)
        return true
    }

    func remove() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
    }

    /// The rows of the menu the item already has, replaced in place: the
    /// first is Pause or Resume by `paused`, the second is always Stop.
    private func rebuildMenu(paused: Bool) {
        guard let menu = item?.menu else { return }
        menu.removeAllItems()
        let actions = [
            paused ? #selector(resumeClicked(_:)) : #selector(pauseClicked(_:)),
            #selector(stopClicked(_:)),
        ]
        for (title, action) in zip(Self.menuTitles(paused: paused), actions) {
            let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
            row.target = self
            menu.addItem(row)
        }
    }

    @objc private func pauseClicked(_ sender: Any?) {
        onPause()
    }

    @objc private func resumeClicked(_ sender: Any?) {
        onResume()
    }

    @objc private func stopClicked(_ sender: Any?) {
        onStop()
    }

    // MARK: - The vocabulary, pure

    /// The two rows, in order. Pure, so a probe can pin both menus.
    static func menuTitles(paused: Bool) -> [String] {
        [paused ? "Resume Recording" : "Pause Recording", "Stop Recording"]
    }

    /// The button's tooltip, which says which of the two states the item
    /// is showing.
    static func tooltip(paused: Bool) -> String {
        paused ? "Frame Job's recording is paused" : "Frame Job is recording"
    }

    /// `m:ss`, and `h:mm:ss` past an hour. Pure, so a probe can pin it.
    static func label(for seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds.rounded(.down)))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let secs = whole % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// The dot in `DS.meterClip` while recording, or the pause glyph in the
    /// menu bar's own colour while paused (the type doc), then the time in
    /// the menu bar's own face with monospaced digits.
    static func title(elapsed: TimeInterval, paused: Bool) -> NSAttributedString {
        let size = NSFont.systemFontSize
        var mark: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size)]
        if !paused { mark[.foregroundColor] = DS.meterClip }
        let title = NSMutableAttributedString(string: paused ? pauseGlyph : "●", attributes: mark)
        title.append(
            NSAttributedString(
                string: " " + label(for: elapsed),
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)]))
        return title
    }
}
