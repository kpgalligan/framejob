import AppKit

// MARK: - The menu bar, for a recording the tool started

/// The `RecorderStatusItem` and the 1 Hz timer that ticks its label, for a
/// recording `record_screen` started — so a person at the machine can pause,
/// resume and stop an agent's recording from the menu bar as they can the
/// panel's (R2d). MAIN THREAD throughout: `show` is hopped there after the
/// start lands, `remove` runs inside `onFinish` (which the recorder calls on
/// main) and on the tool's own finish timeout; `ended` makes the two
/// orderings safe, because a recording that concluded before the hop to
/// `show` must put nothing up that nothing will take down. The timer is
/// added to main's run loop in `.common` modes and invalidated there.
///
/// The three closures go straight to `ScreenRecorder.shared`. Stop freezes
/// the item, then is `stop()` with no completion — a join, landed by the
/// tool's own `onFinish`; `record`'s span-end stop freezes it the same way.
/// Pause and Resume are `pause()` / `resume()` under `try?`: the menu offers
/// each only in the state that accepts it, so the one refusal possible is a
/// race with the recording's own end, with no panel to say it in. The flip
/// is the recorder's: `show` observes its `pauseDidChangeNotification`
/// (synchronous on main, where `pause()` / `resume()` run) and calls
/// `tick()`, so the menu flips AT a pause or resume from ANY door — this
/// menu, the panel's, File ▸ Pause Recording — and not at the timer's next
/// turn (the item rebuilds its menu only when `paused` changes; #181).
/// `show` also observes `finishingDidBeginNotification` and calls `freeze()`,
/// so any stop, from any door, freezes the tool's item (#193). `remove`
/// takes both observers down. The SPAN is wall clock, unchanged: a
/// pause from the menu bar shortens what was recorded, and the result's
/// `pauses` and `duration` say so.
final class RecordingToolChrome {
    private var item: RecorderStatusItem?
    private var timer: Timer?
    private var ended = false
    private var observer: NSObjectProtocol?
    private var finishObserver: NSObjectProtocol?

    init() {}

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RecordingToolChrome does not support NSCoder")
    }

    /// MAIN. A no-op once ended, once showing, or for a recorder neither
    /// recording nor paused (a pending stop moved it on before the hop). A
    /// PAUSED recorder is ADMITTED: the item is then what offers Resume.
    func show(_ recorder: ScreenRecorder) {
        guard !ended, item == nil, recorder.state == .recording || recorder.state == .paused
        else { return }
        let item = RecorderStatusItem(
            onPause: {
                _ = try? ScreenRecorder.shared.pause()
            },
            onResume: {
                _ = try? ScreenRecorder.shared.resume()
            },
            onStop: { [weak self] in
                self?.freeze()
                ScreenRecorder.shared.stop()
            })
        item.show()
        observer = NotificationCenter.default.addObserver(
            forName: ScreenRecorder.pauseDidChangeNotification, object: recorder, queue: nil
        ) { [weak self] _ in self?.tick() }
        finishObserver = NotificationCenter.default.addObserver(
            forName: ScreenRecorder.finishingDidBeginNotification, object: recorder, queue: nil
        ) { [weak self] _ in self?.freeze() }
        self.item = item
        tick()
        // `.common` modes, the panel's rule (`RecorderStatusItem`'s doc): under
        // an open status-item menu a default-mode timer does not fire.
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    /// MAIN. The recorder's elapsed — frozen while paused — and whether it
    /// is paused, into the item; a no-op once the item is down.
    private func tick() {
        guard let item else { return }
        let recorder = ScreenRecorder.shared
        item.update(elapsed: recorder.elapsed, paused: recorder.isPaused)
    }

    /// MAIN. A stop is under way: the item holds its mark and time through
    /// the finish (`RecorderStatusItem.freeze`), or the next tick — `isPaused`
    /// false once finishing — would flip a paused ❚❚ back to the coral dot.
    func freeze() { item?.freeze() }

    /// MAIN. Idempotent.
    func remove() {
        ended = true
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let finishObserver { NotificationCenter.default.removeObserver(finishObserver) }
        finishObserver = nil
        timer?.invalidate()
        timer = nil
        item?.remove()
        item = nil
    }
}
