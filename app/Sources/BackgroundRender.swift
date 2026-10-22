import AppKit

/// Settings ▸ Playback ▸ Background render (spec §11 G-38 (a)): a person's
/// setting, like AI-11's model and R6-12's key — no tool reads or writes it
/// and it has no MCP mirror. `PlaybackSettingsPane` is its one writer; a
/// proof sets it in the argument domain and writes nothing.
struct BackgroundRenderSettings: Equatable {
    /// Bool; absent = true.
    static let enabledKey = "FrameJobBackgroundRender"
    /// Int seconds; absent = the default, outside the range clamped into it.
    static let delayKey = "FrameJobBackgroundRenderDelay"
    static let defaultDelay = 5
    static let delayRange = 1...60

    var enabled = true
    var delaySeconds = BackgroundRenderSettings.defaultDelay

    static func load(from defaults: UserDefaults = .standard) -> BackgroundRenderSettings {
        var settings = BackgroundRenderSettings()
        if defaults.object(forKey: enabledKey) != nil {
            settings.enabled = defaults.bool(forKey: enabledKey)
        }
        if defaults.object(forKey: delayKey) != nil {
            let seconds = defaults.integer(forKey: delayKey)
            settings.delaySeconds = min(max(seconds, delayRange.lowerBound), delayRange.upperBound)
        }
        return settings
    }

    /// Writes both keys.
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Self.enabledKey)
        defaults.set(delaySeconds, forKey: Self.delayKey)
    }
}

/// What the idle clock's door answered (`Playback.startBackgroundRender`).
enum BackgroundStart {
    case started
    case notNeeded
    /// Seeking, restoring, rebuilding, holding, or the start refused (a
    /// window plays): the clock runs again.
    case busy
}

/// The idle clock (spec §11 G-38 (b), (c)). Main only.
///
/// **Activity** restarts it and stops the running background pass at once:
/// every event in `activityEvents` the app receives (a local monitor, so
/// pointer motion alone and events in other apps do not count), every
/// `.projectDocumentDidChange` of any document (live ticks included), and
/// every `syncPrefetch` of any transport — play, pause, a rate change, a
/// seek — which also makes that transport `current`. An agent's call counts
/// only when it edits or moves a transport.
///
/// **At the delay** (read from the stored setting at every restart), with
/// the setting on and no transport playing, `current` is asked to start a
/// pass; a playing transport or `.busy` runs the clock again, `.notNeeded`
/// waits for the next activity. `current` is weak,
/// and an invalidated `Playback` has no item, so a late fire finds nothing.
final class BackgroundRender {
    static let shared = BackgroundRender()
    static let activityEvents: NSEvent.EventTypeMask = [
        .keyDown, .flagsChanged, .leftMouseDown, .leftMouseDragged, .rightMouseDown,
        .rightMouseDragged, .otherMouseDown, .otherMouseDragged, .scrollWheel, .magnify, .rotate,
        .swipe, .smartMagnify,
    ]

    private weak var current: Playback?
    /// Every transport that has moved: none may play when a pass starts.
    private let transports = NSHashTable<Playback>.weakObjects()
    private var timer: Timer?
    private var monitor: Any?
    private var observer: NSObjectProtocol?

    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: Self.activityEvents) {
            [weak self] event in
            self?.noteActivity(from: nil)
            return event
        }
        observer = NotificationCenter.default.addObserver(
            forName: .projectDocumentDidChange, object: nil, queue: nil
        ) { [weak self] _ in
            self?.noteActivity(from: nil)
        }
    }

    /// Activity: `playback`, when given, becomes `current`; the running pass
    /// stops; the one timer restarts at the stored delay.
    func noteActivity(from playback: Playback?) {
        if let playback {
            current = playback
            transports.add(playback)
        }
        GraphicPrefetch.shared.stopBackground()
        restartClock()
    }

    private func restartClock() {
        timer?.invalidate()
        let delay = TimeInterval(BackgroundRenderSettings.load().delaySeconds)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.idle()
        }
    }

    /// A window that plays — forward or in reverse, with graphics or
    /// without — runs the clock again (G-38 (c)).
    private func idle() {
        timer = nil
        guard BackgroundRenderSettings.load().enabled else { return }
        let playing = transports.allObjects.contains { $0.rate != 0 }
        if playing || current?.startBackgroundRender() == .busy { restartClock() }
    }
}
