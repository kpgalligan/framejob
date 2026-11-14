// Tips (spec §11 TIP-1…TIP-7) — the probe `tips_proof.py` builds and runs.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a`, through
// `tools/proof/swift_build.py`. One process:
//
//   tips-probe <scratch folder> <fonts folder>
//
// Its answer is one JSON object on stdout, `{"rows": [...]}`, each row
// `{"id", "pass", "detail"}`; `tips_proof.py` prints and scores them, and
// its header says what each row holds. Every string and number a row compares
// is a LITERAL here, never the app's own constant, so a changed constant is a
// changed answer.
//
// Nothing reaches the screen, a browser or a real defaults domain: activation
// policy `.prohibited`; every editor in a window 20,000 pt off every display
// that cannot become key; the dialog's two order calls and its `open` are
// closures that only record; the state lives in `ProbeDefaults`, in memory.
// The one use of `UserDefaults.standard` is C3's toggle, set through the
// volatile ARGUMENT domain and cleared again, which writes nothing. The
// exports of W1–W3 are real ones, of a document made in process holding one
// shape clip and no media, into the scratch folder.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": String(detail.prefix(1800))])
}
func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    exit(0)
}

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: tips-probe <scratch> <fonts>\n".utf8))
    exit(2)
}
let scratch = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fonts = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
for name in (try? FileManager.default.contentsOfDirectory(atPath: fonts.path)) ?? []
where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
    CTFontManagerRegisterFontsForURL(fonts.appendingPathComponent(name) as CFURL, .process, nil)
}

func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

/// A line on stderr, which `tips_proof.py` keeps beside the answer.
func trace(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }

/// The state's defaults, in memory. Only the calls `Tips.swift` and
/// `TipsSettingsPane.swift` make are answered; anything else traps, which is a
/// crash and so a failed run, never a write to a real domain.
final class ProbeDefaults: UserDefaults {
    var values: [String: Any] = [:]
    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func integer(forKey defaultName: String) -> Int {
        (values[defaultName] as? NSNumber)?.intValue ?? 0
    }
    override func bool(forKey defaultName: String) -> Bool {
        (values[defaultName] as? NSNumber)?.boolValue ?? false
    }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Int, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Bool, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values[defaultName] = nil }
    override func string(forKey defaultName: String) -> String? { trap() }
    override func register(defaults registrationDictionary: [String: Any]) { trap() }
    override func setPersistentDomain(_ domain: [String: Any], forName domainName: String) {
        trap()
    }
    override func removePersistentDomain(forName domainName: String) { trap() }
    override func setVolatileDomain(_ domain: [String: Any], forName domainName: String) {
        trap()
    }
    override func synchronize() -> Bool { trap() }
    private func trap(_ function: String = #function) -> Never {
        fatalError("ProbeDefaults: \(function) would reach a real defaults domain")
    }
}

// MARK: - S: the schedule

func calendar(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}
let la = calendar("America/Los_Angeles")
let auckland = calendar("Pacific/Auckland")
let utc = calendar("UTC")
func at(
    _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0,
    in calendar: Calendar = la
) -> Date {
    calendar.date(
        from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}
let day: TimeInterval = 86_400
func due(_ state: TipsState, _ now: Date, _ calendar: Calendar = la) -> Bool {
    TipsSchedule.isDue(state, now: now, calendar: calendar)
}
func verdicts(_ pairs: [(String, Bool, Bool)]) -> (Bool, String) {
    (pairs.allSatisfy { $0.1 == $0.2 },
     pairs.map { "\($0.0): \($0.1) (want \($0.2))" }.joined(separator: "; "))
}

do {
    let first = at(2027, 6, 1)
    let result = verdicts([
        ("nothing recorded", due(TipsState(), first), false),
        ("5 exports and no first export",
         due(TipsState(firstExport: nil, exports: 5), first), false),
    ])
    row("S1", result.0, result.1)

    let ready = TipsState(firstExport: first, exports: 5)
    let s2 = verdicts([
        ("29 d 23 h after the first export", due(ready, first + 30 * day - 3600), false),
        ("30 d after, 1 July", due(ready, first + 30 * day), true),
    ])
    row("S2", s2.0, s2.1)

    let s3 = verdicts([
        ("4 exports after 400 d",
         due(TipsState(firstExport: first, exports: 4), first + 400 * day), false),
        ("5 exports after 400 d", due(ready, first + 400 * day), true),
    ])
    row("S3", s3.0, s3.1)

    var off = ready
    off.enabled = false
    let s4 = verdicts([
        ("toggle off, otherwise due", due(off, first + 30 * day), false),
        ("the same state with it on", due(ready, first + 30 * day), true),
    ])
    row("S4", s4.0, s4.1)
}

do {
    let asked = TipsState(
        firstExport: at(2026, 1, 1), exports: 9, lastAsked: at(2027, 2, 10))
    let s5 = verdicts([
        ("15 July", due(asked, at(2027, 7, 15)), false),
        ("30 November 23:59:59", due(asked, at(2027, 11, 30, 23, 59, 59)), false),
        ("1 December 00:00:00", due(asked, at(2027, 12, 1, 0, 0, 0)), true),
        ("31 December 23:59:59", due(asked, at(2027, 12, 31, 23, 59, 59)), true),
        ("1 January 00:00:00", due(asked, at(2028, 1, 1, 0, 0, 0)), false),
    ])
    row("S5", s5.0, s5.1)

    func lastAsked(_ date: Date) -> TipsState {
        TipsState(firstExport: at(2026, 1, 1), exports: 9, lastAsked: date)
    }
    let s6 = verdicts([
        ("asked 1 June 00:00:00, 10 December",
         due(lastAsked(at(2027, 6, 1, 0, 0, 0)), at(2027, 12, 10)), true),
        ("asked 1 June 00:00:01, 10 December",
         due(lastAsked(at(2027, 6, 1, 0, 0, 1)), at(2027, 12, 10)), false),
        ("asked 20 August, 10 December",
         due(lastAsked(at(2027, 8, 20)), at(2027, 12, 10)), false),
        ("asked 20 August, the December after",
         due(lastAsked(at(2027, 8, 20)), at(2028, 12, 10)), true),
    ])
    row("S6", s6.0, s6.1)

    let s7 = verdicts([
        ("asked 5 December, 20 December",
         due(lastAsked(at(2027, 12, 5, 10)), at(2027, 12, 20)), false),
        ("asked 5 December, 2 December a year on",
         due(lastAsked(at(2027, 12, 5, 10)), at(2028, 12, 2)), true),
    ])
    row("S7", s7.0, s7.1)

    // One instant: 30 November 12:00 UTC is 1 December 01:00 in Auckland and
    // 30 November 04:00 in Los Angeles.
    let instant = at(2027, 11, 30, 12, 0, 0, in: utc)
    let state = lastAsked(at(2027, 2, 10, 12, 0, 0, in: utc))
    let s8 = verdicts([
        ("Pacific/Auckland", due(state, instant, auckland), true),
        ("America/Los_Angeles", due(state, instant, la), false),
    ])
    row("S8", s8.0, s8.1)

    let first = at(2027, 6, 1)
    let s9 = verdicts([
        ("a day before the first export",
         due(TipsState(firstExport: first, exports: 5), first - day), false),
        ("a December before the last ask",
         due(lastAsked(at(2027, 12, 5)), at(2026, 12, 10)), false),
    ])
    row("S9", s9.0, s9.1)

    let local = TipsSchedule.localCalendar()
    row("S10",
        local.identifier == .gregorian && local.timeZone == TimeZone.current
            && TipsSchedule.firstAskDays == 30 && TipsSchedule.firstAskExports == 5
            && TipsSchedule.skipMonths == 6,
        "localCalendar \(local.identifier) in \(local.timeZone.identifier) (current "
            + "\(TimeZone.current.identifier)); days \(TipsSchedule.firstAskDays), exports "
            + "\(TipsSchedule.firstAskExports), months \(TipsSchedule.skipMonths)")
}

// MARK: - A: the state

/// A clock a row moves by hand.
final class Clock {
    var now = at(2027, 3, 1)
}

do {
    let store = ProbeDefaults()
    let clock = Clock()
    let ask = TipsAsk(defaults: store, now: { clock.now }, calendar: { la })
    let stampedAt = clock.now
    ask.countExport()
    let one = store.values["FrameJobTipsExports"] as? Int
    let firstStamp = store.values["FrameJobTipsFirstExport"] as? Date
    clock.now += 3 * day
    ask.countExport()
    let two = store.values["FrameJobTipsExports"] as? Int
    let secondStamp = store.values["FrameJobTipsFirstExport"] as? Date
    row("A1", one == 1 && two == 2 && firstStamp == stampedAt && secondStamp == stampedAt,
        "exports \(String(describing: one)) then \(String(describing: two)); first export "
            + "stamped \(firstStamp == stampedAt), unchanged by the second \(secondStamp == stampedAt)")

    for _ in 0..<3 { ask.countExport() }
    let early = ask.takeAsk()
    let earlyWrote = store.values["FrameJobTipsLastAsked"] != nil
    clock.now = stampedAt + 31 * day
    let taken = ask.takeAsk()
    let recorded = store.values["FrameJobTipsLastAsked"] as? Date
    let again = ask.takeAsk()
    row("A2", !early && !earlyWrote && taken && recorded == clock.now && !again,
        "5 exports after 3 d: takeAsk \(early), wrote \(earlyWrote); after 31 d: takeAsk "
            + "\(taken), last asked is the clock \(recorded == clock.now); at once again \(again)")
}

do {
    let store = ProbeDefaults()
    let clock = Clock()
    let ask = TipsAsk(defaults: store, now: { clock.now }, calendar: { la })
    for _ in 0..<5 { ask.countExport() }
    clock.now += 40 * day
    var posts = 0
    let token = NotificationCenter.default.addObserver(
        forName: TipsSettings.didChangeNotification, object: nil, queue: nil
    ) { _ in posts += 1 }
    TipsSettings.setEnabled(false, in: store)
    NotificationCenter.default.removeObserver(token)
    let offValue = store.values["FrameJobTips"] as? Bool
    let taken = ask.takeAsk()
    let wrote = store.values["FrameJobTipsLastAsked"] != nil
    ask.countExport()
    let counted = store.values["FrameJobTipsExports"] as? Int
    row("A3", offValue == false && posts == 1 && !taken && !wrote && counted == 6,
        "off writes FrameJobTips \(String(describing: offValue)) and posts \(posts); takeAsk "
            + "\(taken), wrote \(wrote); a sixth export still counts \(String(describing: counted))")

    let other = ProbeDefaults()
    let ask2 = TipsAsk(defaults: other, now: { clock.now }, calendar: { la })
    ask2.noteTipPageOpened()
    let noted = other.values["FrameJobTipsLastAsked"] as? Date
    row("A4", noted == clock.now && other.values.count == 1,
        "noteTipPageOpened wrote last asked as the clock \(noted == clock.now), keys "
            + "\(other.values.keys.sorted())")

    let fresh = ProbeDefaults()
    let absentOn = TipsSettings.isEnabled(in: fresh)
    let ask3 = TipsAsk(defaults: fresh, now: { clock.now }, calendar: { la })
    ask3.countExport()
    ask3.noteTipPageOpened()
    TipsSettings.setEnabled(true, in: fresh)
    let keys = fresh.values.keys.sorted()
    let dates = fresh.values["FrameJobTipsFirstExport"] is Date
        && fresh.values["FrameJobTipsLastAsked"] is Date
    row("A5",
        absentOn
            && keys == ["FrameJobTips", "FrameJobTipsExports", "FrameJobTipsFirstExport",
                        "FrameJobTipsLastAsked"]
            && dates && TipsLink.url == "https://boppallewyn.com/frame-job/tips/",
        "absent toggle reads on \(absentOn); keys \(keys); both dates are Date \(dates); link "
            + "\(TipsLink.url)")
}

// MARK: - F: which queue jobs count

do {
    var states: [UInt64: ExportQueueController.State] = [1: .waiting]
    var calls = 0
    let follower = TipsQueueFollower(state: { states[$0] }, completed: { calls += 1 })
    follower.follow(1)
    follower.settle()
    let waiting = calls
    states[1] = .running
    follower.settle()
    let running = calls
    states[1] = .completed
    follower.settle()
    follower.settle()
    follower.settle()
    row("F1", waiting == 0 && running == 0 && calls == 1 && follower.followed.isEmpty,
        "completed called \(waiting) while waiting, \(running) while running, \(calls) after "
            + "three settles of a completed job; still followed \(follower.followed.sorted())")

    var others: [UInt64: ExportQueueController.State] = [2: .running, 3: .running, 4: .running]
    var otherCalls = 0
    let second = TipsQueueFollower(state: { others[$0] }, completed: { otherCalls += 1 })
    second.follow(2)
    second.follow(3)
    second.follow(4)
    others[2] = .cancelled
    others[3] = .failed
    others[4] = nil
    second.settle()
    others[2] = .completed
    second.settle()
    row("F2", otherCalls == 0 && second.followed.isEmpty,
        "a cancelled, a failed and a removed job: completed called \(otherCalls), still "
            + "followed \(second.followed.sorted())")

    var unfollowed: [UInt64: ExportQueueController.State] = [7: .completed, 8: .running]
    var thirdCalls = 0
    let third = TipsQueueFollower(state: { unfollowed[$0] }, completed: { thirdCalls += 1 })
    third.follow(8)
    third.settle()
    unfollowed[8] = .completed
    third.settle()
    row("F3", thirdCalls == 1,
        "job 7 completed and never followed, job 8 followed: completed called \(thirdCalls)")
}

// MARK: - C1: the dialog

func allViews(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap { allViews($0) } }

func png(_ view: NSView, to url: URL) -> Int {
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0 }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { return 0 }
    try? data.write(to: url)
    var colors = Set<UInt32>()
    let step = max(1, rep.pixelsWide / 64)
    for y in stride(from: 0, to: rep.pixelsHigh, by: step) {
        for x in stride(from: 0, to: rep.pixelsWide, by: step) {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            colors.insert(
                UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8
                    | UInt32(c.blueComponent * 255))
        }
    }
    return colors.count
}

do {
    let store = ProbeDefaults()
    let clock = Clock()
    let ask = TipsAsk(defaults: store, now: { clock.now }, calendar: { la })
    var opened: [URL] = []
    var orders: [String] = []
    // Each order call really orders the window, moved off every display
    // first, so that a close can be read off `isVisible`.
    func order(_ window: NSWindow, _ how: String) {
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderBack(nil)
        orders.append(how)
    }
    let dialog = TipsWindowController(
        ask: ask, open: { opened.append($0) }, orderKey: { order($0, "key") },
        orderFront: { order($0, "front") })
    func visible() -> Bool { dialog.window?.isVisible == true }
    var notes: [String] = []
    var good = true
    func check(_ pass: Bool, _ note: String) {
        if !pass { good = false }
        notes.append("\(note) \(pass)")
    }
    let texts = allViews(dialog.window?.contentView ?? NSView())
        .compactMap { ($0 as? NSTextField)?.stringValue }
    check(dialog.window?.title == "Tips", "window titled Tips")
    check(texts.contains("Frame Job is free and open source"), "heading")
    check(
        texts.contains(
            "Frame Job is made by one developer. It is free to use and its source is open. If "
                + "it is useful to you, a tip helps pay for the time to keep working on it. Tips "
                + "are voluntary, and nothing in Frame Job is locked without one."),
        "body")
    check(
        texts.contains("You can turn this reminder off in Frame Job ▸ Settings… ▸ Tips."),
        "hint")
    check(
        dialog.notNowButton.title == "Not Now" && dialog.notNowButton.keyEquivalent == "\u{1b}",
        "Not Now on Escape")
    check(
        dialog.tipButton.title == "Leave a Tip" && dialog.tipButton.keyEquivalent == "\r",
        "Leave a Tip on Return")
    check(dialog.window?.isExcludedFromWindowsMenu == true, "out of the Window menu")
    check(dialog.window?.frameAutosaveName.isEmpty == true, "no frame autosave name")

    check(!visible(), "not shown until asked")
    dialog.show()
    check(
        orders == ["key"] && visible() && store.values.isEmpty,
        "show() orders key and writes nothing")
    dialog.notNowButton.performClick(nil)
    check(
        !visible() && opened.isEmpty && store.values.isEmpty,
        "Not Now closes, opens and writes nothing")
    dialog.showAutomatic()
    check(
        orders == ["key", "front"] && visible() && store.values.isEmpty,
        "showAutomatic() orders front, never key, and writes nothing (orders \(orders))")
    dialog.tipButton.performClick(nil)
    check(
        opened.map { $0.absoluteString } == ["https://boppallewyn.com/frame-job/tips/"],
        "Leave a Tip opens exactly the page (\(opened.map { $0.absoluteString }))")
    check(
        store.values["FrameJobTipsLastAsked"] as? Date == clock.now && store.values.count == 1,
        "Leave a Tip writes last asked alone")
    check(!visible(), "Leave a Tip closes")

    // A picture of each look for a reader: a dialog built under that look,
    // as the app builds its one under the look it launched in.
    // The app's look is settled before its first window; this process has
    // already drawn under the system's, so each picture is built with its
    // look as the current drawing appearance too, which is what a layer's
    // background colour resolves against.
    for (look, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        guard let appearance = NSAppearance(named: name) else { continue }
        NSApp.appearance = appearance
        var colors = 0
        appearance.performAsCurrentDrawingAppearance {
            let pictured = TipsWindowController(
                ask: ask, open: { _ in }, orderKey: { _ in }, orderFront: { _ in })
            pictured.show()
            colors = pictured.window?.contentView.map {
                png($0, to: scratch.appendingPathComponent("tips-dialog.\(look).png"))
            } ?? 0
        }
        check(colors > 1, "\(look) PNG has \(colors) colours")
    }
    NSApp.appearance = nil
    row("C1", good, notes.joined(separator: "; "))
}

// MARK: - The editor: a document made in process, off every display

final class OffWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct Editor {
    let document: ProjectDocument
    let controller: EditorViewController
    let window: NSWindow
    let keep: NSWindowController
}

let second: Ticks = 600_000

/// An untitled document holding one rectangle of `seconds`, its editor in an
/// off-screen window of `width` × 700.
func makeEditor(seconds: Int, width: CGFloat = 1440) -> Editor? {
    let document = ProjectDocument()
    document.performGroupedEdit("Track", [.addTrack(index: 0)])
    guard let track = document.project.snapshot.tracks.first?.id else { return nil }
    document.performGroupedEdit(
        "Shape",
        [.addShapeClip(track: track, at: 0, duration: Ticks(seconds) * second, shape: .rectangle)])
    guard document.project.duration > 0 else { return nil }
    let controller = EditorViewController(document: document)
    let frame = NSRect(x: -20000, y: -20000, width: width, height: 700)
    let window = OffWindow(
        contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered, defer: false)
    window.contentViewController = controller
    window.setFrame(frame, display: false)
    controller.viewWillAppear()
    controller.viewDidAppear()
    controller.refreshFromDocument(isLive: false)
    let keep = NSWindowController(window: window)
    document.addWindowController(keep)
    window.orderBack(nil)
    for _ in 0..<8 {
        spin(0.05)
        controller.view.layoutSubtreeIfNeeded()
    }
    return Editor(document: document, controller: controller, window: window, keep: keep)
}

// MARK: - C2, C3: the toolbar button

/// What C2 and C3 read off one editor's toolbar.
struct Toolbar {
    let row: NSStackView
    let bar: NSView
    let export: AccentButton
    let tips: TipsToolbarButton

    init?(_ editor: Editor) {
        editor.controller.view.layoutSubtreeIfNeeded()
        guard
            let tips = allViews(editor.controller.view).compactMap({ $0 as? TipsToolbarButton })
                .first,
            let row = tips.superview as? NSStackView, let bar = row.superview,
            let export = row.arrangedSubviews.compactMap({ $0 as? AccentButton }).last
        else { return nil }
        self.row = row
        self.bar = bar
        self.export = export
        self.tips = tips
    }

    /// Each arranged view's width, the flexible spacer's apart.
    var widths: (fixed: [CGFloat], spacer: CGFloat) {
        var fixed: [CGFloat] = []
        var spacer: CGFloat = -1
        for view in row.arrangedSubviews where !view.isHidden {
            if view.contentHuggingPriority(for: .horizontal).rawValue == 1 {
                spacer = view.frame.width
            } else {
                fixed.append((view.frame.width * 100).rounded() / 100)
            }
        }
        return (fixed, spacer)
    }

    func inBar(_ view: NSView) -> NSRect { bar.convert(view.bounds, from: view) }
}

func components(_ color: NSColor) -> [Int] {
    guard let c = color.usingColorSpace(.sRGB) else { return [] }
    return [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
}

do {
    var notes: [String] = []
    var good = true
    func check(_ pass: Bool, _ note: String) {
        if !pass { good = false }
        notes.append("\(note) \(pass)")
    }
    var wide: [CGFloat] = []
    for width in [CGFloat(1440), 900] {
        guard let editor = makeEditor(seconds: 1, width: width), let toolbar = Toolbar(editor)
        else {
            check(false, "no editor or no Tips button at \(Int(width)) pt")
            continue
        }
        let arranged = toolbar.row.arrangedSubviews
        let count = arranged.count
        check(
            count >= 2 && arranged[count - 1] === toolbar.tips
                && arranged[count - 2] === toolbar.export && toolbar.export.title == "Export…",
            "\(Int(width)) pt: the row ends Export… then Tips")
        let tipsRect = toolbar.inBar(toolbar.tips)
        let exportRect = toolbar.inBar(toolbar.export)
        check(
            abs(tipsRect.minX - exportRect.maxX - 12) < 0.01
                && abs(toolbar.bar.bounds.maxX - tipsRect.maxX - 12) < 0.01,
            "\(Int(width)) pt: Tips 12 pt after Export… and 12 pt from the edge (Export… ends "
                + "\(exportRect.maxX), Tips \(tipsRect.minX)–\(tipsRect.maxX), bar "
                + "\(toolbar.bar.bounds.maxX))")
        check(
            abs(tipsRect.height - 26) < 0.01
                && abs(tipsRect.width - toolbar.tips.button.intrinsicContentSize.width) < 0.01,
            "\(Int(width)) pt: 26 pt tall at its own width (\(tipsRect.size))")
        let widths = toolbar.widths
        if width == 1440 {
            wide = widths.fixed
            let button = toolbar.tips.button
            check(button.title == "Tips", "titled Tips")
            check(
                components(button.fill) == [0x2E, 0x7D, 0x32],
                "fill #2E7D32 (\(components(button.fill)))")
            check(
                button.action.map { NSStringFromSelector($0) } == "showTips:"
                    && button.target == nil,
                "nil-target showTips:")
            check(button.toolTip == "Support Frame Job", "tooltip")
            let colors = png(
                toolbar.bar, to: scratch.appendingPathComponent("tips-toolbar.png"))
            check(colors > 1, "toolbar PNG has \(colors) colours")
        } else {
            check(
                widths.fixed == wide && widths.spacer > 0,
                "900 pt: every control keeps its 1440 pt width (\(widths.fixed) against \(wide)) "
                    + "and the spacer is \(widths.spacer) pt")
        }
        editor.window.close()
    }
    row("C2", good, notes.joined(separator: "; "))
}

do {
    var notes: [String] = []
    var good = true
    func check(_ pass: Bool, _ note: String) {
        if !pass { good = false }
        notes.append("\(note) \(pass)")
    }
    func setToggle(_ value: Bool?) {
        UserDefaults.standard.setVolatileDomain(
            value.map { ["FrameJobTips": $0] } ?? [:], forName: UserDefaults.argumentDomain)
        NotificationCenter.default.post(name: TipsSettings.didChangeNotification, object: nil)
    }
    if let editor = makeEditor(seconds: 1), let toolbar = Toolbar(editor) {
        func settle() {
            for _ in 0..<4 {
                spin(0.02)
                editor.controller.view.layoutSubtreeIfNeeded()
            }
        }
        let edge = toolbar.bar.bounds.maxX
        check(!toolbar.tips.isHidden, "on at first")
        setToggle(false)
        settle()
        check(toolbar.tips.isHidden, "off: hidden")
        check(
            abs(edge - toolbar.inBar(toolbar.export).maxX - 12) < 0.01,
            "off: Export… 12 pt from the edge (\(toolbar.inBar(toolbar.export).maxX) of \(edge))")
        setToggle(true)
        settle()
        check(!toolbar.tips.isHidden, "on again: shown")
        check(
            abs(edge - toolbar.inBar(toolbar.tips).maxX - 12) < 0.01,
            "on again: Tips 12 pt from the edge")
        setToggle(nil)
        editor.window.close()
    } else {
        check(false, "no editor or no Tips button")
    }
    row("C3", good, notes.joined(separator: "; "))
}

// MARK: - C4: Settings' pane

do {
    let store = ProbeDefaults()
    var shown = 0
    let pane = TipsSettingsPane(defaults: store, showTips: { shown += 1 })
    var notes: [String] = []
    var good = true
    func check(_ pass: Bool, _ note: String) {
        if !pass { good = false }
        notes.append("\(note) \(pass)")
    }
    let arranged = pane.arrangedSubviews
    check(
        arranged.count == 4 && arranged[0] === pane.headingLabel && arranged[1] === pane.blurbLabel
            && arranged[2] === pane.toggleBox && arranged[3] === pane.tipsButton,
        "heading, blurb, toggle, button")
    check(pane.headingLabel.stringValue == "Tips", "heading Tips")
    check(
        pane.blurbLabel.stringValue
            == "Frame Job is free and open source, made by one developer. Tips are voluntary."
            && pane.blurbLabel.stringValue.count < 200,
        "the blurb, under 200 characters")
    check(
        pane.toggleBox.title == "Show the Tips button and the yearly reminder"
            && pane.toggleBox.state == .on,
        "the toggle's title, on by default")
    check(
        allViews(pane).compactMap { $0 as? SettingsInfoButton }.isEmpty, "no info button")
    var posts = 0
    let token = NotificationCenter.default.addObserver(
        forName: TipsSettings.didChangeNotification, object: nil, queue: nil
    ) { _ in posts += 1 }
    pane.toggleBox.performClick(nil)
    check(
        store.values["FrameJobTips"] as? Bool == false && posts == 1
            && pane.toggleBox.state == .off,
        "unticking writes FrameJobTips false and posts once (posts \(posts))")
    check(
        pane.tipsButton.title == "Tips" && !pane.tipsButton.isHidden && pane.tipsButton.isEnabled,
        "off: the Tips button is there and enabled")
    pane.tipsButton.performClick(nil)
    check(shown == 1, "off: a press shows the dialog (\(shown))")
    pane.toggleBox.performClick(nil)
    check(
        store.values["FrameJobTips"] as? Bool == true && posts == 2,
        "ticking writes true and posts again (posts \(posts))")
    pane.tipsButton.performClick(nil)
    check(
        shown == 2 && !pane.tipsButton.isHidden && pane.tipsButton.isEnabled,
        "on: the button is there and a press shows the dialog (\(shown))")
    check(store.values.count == 1, "the pane writes one key (\(store.values.keys.sorted()))")
    NotificationCenter.default.removeObserver(token)
    row("C4", good, notes.joined(separator: "; "))
}

// MARK: - W: the two export doors, with real exports

/// One door's fixture: a state one export short of due, and a dialog that
/// only records how it was ordered.
final class Door {
    let store = ProbeDefaults()
    let clock = Clock()
    var orders: [String] = []
    lazy var ask = TipsAsk(defaults: store, now: { self.clock.now }, calendar: { la })
    lazy var dialog = TipsWindowController(
        ask: ask, open: { _ in }, orderKey: { [unowned self] _ in self.orders.append("key") },
        orderFront: { [unowned self] _ in self.orders.append("front") })

    init() {
        store.values["FrameJobTipsExports"] = 4
        store.values["FrameJobTipsFirstExport"] = clock.now - 40 * day
    }

    var exports: Int { store.integer(forKey: "FrameJobTipsExports") }
    var lastAsked: Date? { store.values["FrameJobTipsLastAsked"] as? Date }
}

/// The progress sheet the editor is presenting now. One an earlier export
/// dismissed has no presenter any more, and is passed over.
func progressSheet(_ editor: Editor) -> ExportProgressSheetController? {
    editor.controller.presentedViewControllers?
        .compactMap { $0 as? ExportProgressSheetController }
        .last { $0.presentingViewController != nil }
}

func button(_ title: String, in sheet: NSViewController) -> NSButton? {
    allViews(sheet.view).compactMap { $0 as? NSButton }.first { $0.title == title }
}

/// Runs Export… as the export card's commit does, through `beginExport`, and
/// waits for the sheet to end one way or another. Answers how it ended:
/// "exported", "failed" (the sheet reads Close with no Show in Finder),
/// "gone" (a cancel dismissed it) or why it could not be run.
func runExport(
    _ editor: Editor, to destination: URL, doors: TipsDoors, cancel: Bool = false
) -> String {
    guard
        let settings = try? ReelExport.settings(
            editor.document.project, preset: "h264", overrides: nil)
    else { return "no settings" }
    try? FileManager.default.removeItem(at: destination)
    editor.controller.beginExport(settings: settings, to: destination, tips: doors)
    spin(0.2)
    guard let sheet = progressSheet(editor) else { return "no progress sheet" }
    trace("runExport \(destination.lastPathComponent): presented "
        + "\(editor.controller.presentedViewControllers?.count ?? 0), presenting "
        + "\(sheet.presentingViewController != nil), attached "
        + "\(editor.window.attachedSheet != nil)")
    sheet.viewDidAppear()
    if cancel { button("Cancel", in: sheet)?.performClick(nil) }
    let start = Date()
    while Date().timeIntervalSince(start) < 120 {
        spin(0.05)
        if progressSheet(editor) == nil { return "gone" }
        if button("Close", in: sheet) != nil {
            let reveal = button("Show in Finder", in: sheet)
            if reveal?.isHidden == false { return "exported" }
            trace("runExport \(destination.lastPathComponent) failed: "
                + allViews(sheet.view).compactMap { ($0 as? NSTextField)?.stringValue }
                    .joined(separator: " | "))
            return "failed"
        }
    }
    return "no end within 120 s"
}

/// Presses the result sheet's Close and lets the sheet leave.
func closeSheet(_ editor: Editor) {
    guard let sheet = progressSheet(editor) else { return }
    trace("closeSheet: presented \(editor.controller.presentedViewControllers?.count ?? 0), "
        + "presenting \(sheet.presentingViewController != nil), attached "
        + "\(editor.window.attachedSheet != nil)")
    button("Close", in: sheet)?.performClick(nil)
    for _ in 0..<20 where progressSheet(editor) != nil { spin(0.05) }
    spin(0.3)
}

do {
    // W2 first: a failed and a cancelled Export… on a state the next counted
    // export would make due.
    let door = Door()
    let doors = TipsDoors(ask: door.ask, dialog: { door.dialog }, queue: ExportQueueController())
    var notes: [String] = []
    var good = true
    func check(_ pass: Bool, _ note: String) {
        if !pass { good = false }
        notes.append("\(note) \(pass)")
    }
    if let short = makeEditor(seconds: 1), let long = makeEditor(seconds: 240) {
        let failed = runExport(
            short, to: URL(fileURLWithPath: "/nonexistent-framejob-tips-probe/out.mp4"),
            doors: doors)
        check(failed == "failed", "an export to a folder that is not there fails (\(failed))")
        closeSheet(short)
        check(
            door.exports == 4 && door.lastAsked == nil && door.orders.isEmpty,
            "the failure: exports \(door.exports), no ask, orders \(door.orders)")
        let cancelled = runExport(
            long, to: scratch.appendingPathComponent("w2-cancelled.mp4"), doors: doors,
            cancel: true)
        check(cancelled == "gone", "a cancelled export dismisses its sheet (\(cancelled))")
        spin(0.3)
        check(
            door.exports == 4 && door.lastAsked == nil && door.orders.isEmpty,
            "the cancel: exports \(door.exports), no ask, orders \(door.orders)")
        long.window.close()
        row("W2", good, notes.joined(separator: "; "))

        // W1: the same door and state, a success.
        notes = []
        good = true
        let exported = runExport(
            short, to: scratch.appendingPathComponent("w1-first.mp4"), doors: doors)
        check(exported == "exported", "Export… succeeds (\(exported))")
        spin(0.3)
        check(
            door.exports == 5 && door.lastAsked == nil && door.orders.isEmpty,
            "with the result sheet up: counted (\(door.exports)), not asked, orders \(door.orders)")
        closeSheet(short)
        check(
            door.orders == ["front"] && door.lastAsked == door.clock.now,
            "after Close: ordered front, never key (\(door.orders)), and last asked recorded "
                + "(\(door.lastAsked == door.clock.now))")
        let again = runExport(
            short, to: scratch.appendingPathComponent("w1-second.mp4"), doors: doors)
        closeSheet(short)
        check(
            again == "exported" && door.exports == 6 && door.orders == ["front"],
            "a second export (\(again)): counted (\(door.exports)), not asked again "
                + "(\(door.orders))")
        short.window.close()
        row("W1", good, notes.joined(separator: "; "))
    } else {
        row("W2", false, "no editor")
        row("W1", false, "no editor")
    }
}

do {
    // W3: Add to Queue's door on the probe's own queue. Job A is enqueued
    // as the agent's `export` enqueues, unfollowed; B is followed; C is
    // followed and cancelled while it waits.
    let door = Door()
    let queue = ExportQueueController()
    let doors = TipsDoors(ask: door.ask, dialog: { door.dialog }, queue: queue)
    var notes: [String] = []
    var good = true
    func check(_ pass: Bool, _ note: String) {
        if !pass { good = false }
        notes.append("\(note) \(pass)")
    }
    if let editor = makeEditor(seconds: 1),
        let settings = try? ReelExport.settings(
            editor.document.project, preset: "h264", overrides: nil)
    {
        func enqueue(_ name: String) -> UInt64 {
            let destination = scratch.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            return queue.enqueue(
                project: editor.document.project, urls: editor.document.mediaURLs(),
                settings: settings, to: destination)
        }
        let a = enqueue("w3-agent.mp4")
        let b = enqueue("w3-person.mp4")
        doors.follow(queueJob: b)
        let c = enqueue("w3-cancelled.mp4")
        doors.follow(queueJob: c)
        queue.cancel(c)
        let start = Date()
        while !queue.isIdle, Date().timeIntervalSince(start) < 120 { spin(0.05) }
        spin(0.3)
        let states = [a, b, c].map { queue.job($0)?.state.rawValue ?? "gone" }
        trace("W3 messages: \([a, b, c].map { queue.job($0)?.message ?? "-" })")
        check(
            states == ["completed", "completed", "cancelled"],
            "the unfollowed and the followed job completed, the third was cancelled (\(states))")
        check(
            door.exports == 5,
            "one export counted, the followed one (\(door.exports) from 4)")
        check(
            door.orders == ["front"] && door.lastAsked == door.clock.now,
            "asked when it completed: ordered front, never key (\(door.orders)), last asked "
                + "recorded (\(door.lastAsked == door.clock.now))")
        editor.window.close()
    } else {
        check(false, "no editor or no settings")
    }
    row("W3", good, notes.joined(separator: "; "))
}

finish()
