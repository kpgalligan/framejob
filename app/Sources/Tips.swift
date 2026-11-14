import Foundation

/// Tips (spec §11 TIP-1…TIP-7): what the dialog links to, when Frame Job asks
/// by itself, and what it remembers. Foundation only, so a probe can run the
/// rule against a clock of its own and the AppKit-free export queue can be
/// followed from here. The dialog is `TipsWindowController.swift`, the
/// editor's button `TipsToolbarButton.swift`, Settings' pane
/// `TipsSettingsPane.swift`.

/// The one address "Leave a Tip" opens (TIP-1). The page is the owner's.
enum TipsLink {
    static let url = "https://boppallewyn.com/frame-job/tips/"
}

/// What the schedule is decided from: the stored state, read at one moment.
struct TipsState: Equatable {
    /// When the first counted export succeeded; nil before one has.
    var firstExport: Date?
    /// How many exports a person confirmed in the export card have succeeded.
    var exports = 0
    /// When the automatic ask was last shown, or "Leave a Tip" last pressed.
    var lastAsked: Date?
    /// Settings ▸ Tips' toggle.
    var enabled = true
}

/// When the automatic ask is due (TIP-3). Pure: the state, a moment and a
/// calendar in, a Bool out.
enum TipsSchedule {
    static let firstAskDays = 30
    static let firstAskExports = 5
    static let skipMonths = 6

    /// The Gregorian calendar in the Mac's time zone as it is now, whatever
    /// calendar the person's Mac shows: "December" is its month 12.
    static func localCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }

    /// Off is never due. The first ask waits for `firstAskExports` exports
    /// and `firstAskDays` days since the first of them. After an ask, only a
    /// December is due, and not one whose 1 December 00:00 is less than
    /// `skipMonths` calendar months after the last ask.
    static func isDue(_ state: TipsState, now: Date, calendar: Calendar) -> Bool {
        guard state.enabled else { return false }
        guard let first = state.firstExport else { return false }
        guard state.exports >= firstAskExports else { return false }
        guard now.timeIntervalSince(first) >= Double(firstAskDays) * 86_400 else { return false }
        guard let last = state.lastAsked else { return true }
        guard calendar.component(.month, from: now) == 12 else { return false }
        let year = calendar.component(.year, from: now)
        guard
            let december = calendar.date(from: DateComponents(year: year, month: 12, day: 1)),
            let earliest = calendar.date(byAdding: .month, value: skipMonths, to: last)
        else { return false }
        return earliest <= december
    }
}

/// Settings ▸ Tips' toggle (TIP-5, TIP-6): on shows the editor's Tips button
/// and lets the automatic ask happen.
enum TipsSettings {
    /// Bool; absent = true.
    static let enabledKey = "FrameJobTips"

    /// Posted after the toggle is written, so every editor's Tips button
    /// follows it at once.
    static let didChangeNotification = Notification.Name("FrameJobTipsSettingsDidChange")

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) == nil ? true : defaults.bool(forKey: enabledKey)
    }

    /// Writes the toggle and posts `didChangeNotification`.
    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

/// The stored state and its three writers (TIP-5). Every writer is reached
/// only from a person's door: an export confirmed in the export card, or the
/// dialog's "Leave a Tip". Main thread.
final class TipsAsk {
    /// Int; absent = 0.
    static let exportsKey = "FrameJobTipsExports"
    /// A date, stamped by the first counted export and never again.
    static let firstExportKey = "FrameJobTipsFirstExport"
    /// A date: the last automatic ask, or the last press of "Leave a Tip".
    static let lastAskedKey = "FrameJobTipsLastAsked"

    /// The app's own, over the bundle's defaults and the real clock.
    static let shared = TipsAsk()

    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: () -> Calendar

    init(
        defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() },
        calendar: @escaping () -> Calendar = { TipsSchedule.localCalendar() }
    ) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
    }

    var state: TipsState {
        TipsState(
            firstExport: defaults.object(forKey: Self.firstExportKey) as? Date,
            exports: defaults.integer(forKey: Self.exportsKey),
            lastAsked: defaults.object(forKey: Self.lastAskedKey) as? Date,
            enabled: TipsSettings.isEnabled(in: defaults))
    }

    /// One more export a person confirmed has succeeded. Counts whatever the
    /// toggle says.
    func countExport() {
        let state = self.state
        defaults.set(state.exports + 1, forKey: Self.exportsKey)
        if state.firstExport == nil { defaults.set(now(), forKey: Self.firstExportKey) }
    }

    /// True when the automatic ask is due now, and then it is recorded as
    /// asked, so the caller shows the dialog and a second call answers false.
    func takeAsk() -> Bool {
        let moment = now()
        guard TipsSchedule.isDue(state, now: moment, calendar: calendar()) else { return false }
        defaults.set(moment, forKey: Self.lastAskedKey)
        return true
    }

    /// "Leave a Tip" was pressed, from any door: that is an ask too.
    func noteTipPageOpened() {
        defaults.set(now(), forKey: Self.lastAskedKey)
    }
}

/// Which export queue jobs a person started (Add to Queue), followed by id as
/// `AgentExports` follows the agent's, so the queue's jobs carry no origin
/// (TIP-4). `settle()` runs on every change of the queue.
final class TipsQueueFollower {
    private let state: (UInt64) -> ExportQueueController.State?
    private let completed: () -> Void
    private(set) var followed: Set<UInt64> = []

    init(state: @escaping (UInt64) -> ExportQueueController.State?, completed: @escaping () -> Void)
    {
        self.state = state
        self.completed = completed
    }

    func follow(_ id: UInt64) {
        followed.insert(id)
        settle()
    }

    /// A followed job that completed calls `completed` once and is dropped;
    /// one cancelled, failed or gone from the list is dropped; one waiting or
    /// running stays.
    func settle() {
        for id in followed.sorted() {
            switch state(id) {
            case .completed:
                followed.remove(id)
                completed()
            case .cancelled, .failed, nil:
                followed.remove(id)
            case .waiting, .running:
                break
            }
        }
    }
}
