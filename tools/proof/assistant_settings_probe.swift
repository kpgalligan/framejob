// Issue batch B48 (#151) — the assistant's chat settings' probe (spec §11
// AI-20, amending AI-9 and AI-18).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `assistant_tab_proof.build_probe`'s swiftc line, `-D REELCUT_DEV_TOOLS` — by
// `assistant_settings_proof.py`, which copies the built helper to
// `<probe dir>/Contents/Helpers/reelcut-agent` and runs it with the stand-in's
// allow-listed dummy key in `-RCSecretFolder`, `-ReelcutInspectorCollapsed NO`
// and `RC_ASSISTANT_BASE_URL` at `anthropic_fake.py`, scripted with CS2's four
// replies. The three chat-settings keys are NEVER probe arguments: the
// argument domain would shadow the pane's writes. `build_probe` names every
// binary `assistant_tab_probe`, so the standard domain is the tab probe's
// too; the three keys are removed from it at start and at exit.
//
// Prints exactly one stdout line:
//   ANSWER {"rows":[{"id","ok","detail"}],"clearTriggerTokens":N}
//
//   CS1  (before any editor exists) `AssistantChatSettings` over a fresh
//        suite: empty is the default and {300000, false}; 19,999 and 900,001
//        read as 300,000, 20,000 and 900,000 are kept; off answers null,
//        clear on true; save/load round-trips; stored (false, 40,000, true)
//        `settingsJSON(defaults: suite)` answers {null, true}; the pane over
//        the suite in a window: starts on / 300,000 / off, field enabled;
//        "40,000" committed stores 40,000 and posts ["settings"], again posts
//        nothing; "10000" beeps back to 40,000, writing and posting nothing;
//        the compaction box off disables the field, +1 posted; the clear box
//        on, +1 posted; never "key" or "model"; `sync()` shows stored
//        (false, 40,000, true)
//   CS2  a real editor's session against the stand-in: turn 1 (50,000 input
//        tokens) does not compact; a pane on `.standard` commits "40,000" and
//        turns clearing on — posted ["settings","settings"], the session the
//        same object, not closed, the transcript unchanged with no "new
//        conversation" entry; turn 2 (50,000) compacts once with 40,000 ≤
//        used < 300,000, then `compacted`; the compaction box off posts +1;
//        turn 3 (950,000) does not compact. The stand-in's POSTs are the
//        proof's half of the row.
import AppKit

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))
AgentLane.prepareAtLaunch()

var rows: [[String: Any]] = []

func row(_ id: String, _ ok: Bool, _ detail: String) {
    rows.append(["id": id, "ok": ok, "detail": String(detail.prefix(2000))])
}

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

func newEditor() -> (ProjectDocument, EditorViewController, NSWindow)? {
    let document = ProjectDocument()
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(0.5)
    guard let window = document.windowControllers.first?.window,
        let editor = window.contentViewController as? EditorViewController
    else { return nil }
    return (document, editor, window)
}

let chatKeys = [
    AssistantChatSettings.autoCompactKey, AssistantChatSettings.autoCompactTokensKey,
    AssistantChatSettings.clearToolResultsKey,
]

func removeChatKeys() {
    for key in chatKeys { UserDefaults.standard.removeObject(forKey: key) }
}

/// The pane in a window of its own, and every change it posts.
final class PaneHarness {
    let pane: AssistantSettingsPane
    let window: NSWindow
    private(set) var posted: [String] = []
    private var token: NSObjectProtocol?

    init(defaults: UserDefaults) {
        pane = AssistantSettingsPane(
            store: { MemoryStore() }, defaults: defaults, environment: [:], spendFolder: { nil })
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentView = pane
        token = NotificationCenter.default.addObserver(
            forName: AssistantConfiguration.didChangeNotification, object: pane, queue: nil
        ) { [weak self] note in
            self?.posted.append(note.userInfo?[AssistantConfiguration.changeKey] as? String ?? "?")
        }
    }

    func commitTokens(_ text: String) {
        pane.compactTokensField.stringValue = text
        pane.compactTokensChanged(nil)
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
}

func describe(_ json: [String: Any]) -> String {
    let tokens = json["auto_compact_tokens"].map { $0 is NSNull ? "null" : "\($0)" } ?? "absent"
    return "{auto_compact_tokens: \(tokens), clear_tool_results: "
        + "\(json["clear_tool_results"].map { "\($0)" } ?? "absent")}"
}

// MARK: - CS1

func rowCS1() {
    let suiteName = "com.kgalligan.reelcut.assistant-settings-probe"
    UserDefaults().removePersistentDomain(forName: suiteName)
    guard let suite = UserDefaults(suiteName: suiteName) else {
        row("CS1", false, "no suite")
        return
    }
    defer { UserDefaults().removePersistentDomain(forName: suiteName) }
    var checks: [(String, Bool)] = []
    func check(_ name: String, _ good: Bool) { checks.append((name, good)) }

    let empty = AssistantChatSettings.load(from: suite)
    let emptyJSON = empty.helperJSON
    check(
        "empty is the default and \(describe(emptyJSON))",
        empty == AssistantChatSettings()
            && emptyJSON["auto_compact_tokens"] as? Int == 300_000
            && emptyJSON["clear_tool_results"] as? Bool == false)

    for (stored, wanted) in [
        (19_999, 300_000), (900_001, 300_000), (20_000, 20_000), (900_000, 900_000),
    ] {
        suite.set(stored, forKey: AssistantChatSettings.autoCompactTokensKey)
        let read = AssistantChatSettings.load(from: suite).autoCompactTokens
        check("stored \(stored) reads \(read) (wanted \(wanted))", read == wanted)
    }
    suite.removeObject(forKey: AssistantChatSettings.autoCompactTokensKey)

    var off = AssistantChatSettings()
    off.autoCompact = false
    off.clearToolResults = true
    let offJSON = off.helperJSON
    check(
        "off and clearing \(describe(offJSON))",
        offJSON["auto_compact_tokens"] is NSNull && offJSON["clear_tool_results"] as? Bool == true)

    var chosen = AssistantChatSettings()
    chosen.autoCompact = false
    chosen.autoCompactTokens = 40_000
    chosen.clearToolResults = true
    chosen.save(to: suite)
    let loaded = AssistantChatSettings.load(from: suite)
    check(
        "save/load round-trips (\(loaded.autoCompact), \(loaded.autoCompactTokens), "
            + "\(loaded.clearToolResults))", loaded == chosen)

    let sent = AssistantConfiguration.settingsJSON(defaults: suite)
    check(
        "settingsJSON(defaults: suite) over (false, 40000, true) \(describe(sent))",
        sent["auto_compact_tokens"] is NSNull && sent["clear_tool_results"] as? Bool == true
            && sent.count == 2)

    // The pane over the suite, emptied.
    for key in chatKeys { suite.removeObject(forKey: key) }
    let harness = PaneHarness(defaults: suite)
    let pane = harness.pane
    let started = pane.compactBox.state == .on
        && pane.compactTokensField.stringValue
            == AssistantChatSettings.defaultCompactTokens.formatted()
        && pane.clearToolResultsBox.state == .off && pane.compactTokensField.isEnabled
    check(
        "the pane starts compact \(pane.compactBox.state == .on), field "
            + "\"\(pane.compactTokensField.stringValue)\", clear "
            + "\(pane.clearToolResultsBox.state == .on), field enabled "
            + "\(pane.compactTokensField.isEnabled)", started)

    harness.commitTokens("40,000")
    let stored40 = suite.object(forKey: AssistantChatSettings.autoCompactTokensKey) as? Int
    check(
        "\"40,000\" stores \(stored40.map(String.init) ?? "nothing"), posted \(harness.posted)",
        stored40 == 40_000 && harness.posted == ["settings"])
    harness.commitTokens("40,000")
    check("the same again posts \(harness.posted)", harness.posted == ["settings"])

    harness.commitTokens("10000")
    let after10 = suite.object(forKey: AssistantChatSettings.autoCompactTokensKey) as? Int
    check(
        "\"10000\" shows \"\(pane.compactTokensField.stringValue)\", stored "
            + "\(after10.map(String.init) ?? "nothing"), posted \(harness.posted)",
        pane.compactTokensField.stringValue == 40_000.formatted() && after10 == 40_000
            && harness.posted == ["settings"])

    pane.compactBox.performClick(nil)
    let compactOff = AssistantChatSettings.load(from: suite).autoCompact
    check(
        "the compaction box: stored on \(compactOff), field enabled "
            + "\(pane.compactTokensField.isEnabled), posted \(harness.posted)",
        !compactOff && !pane.compactTokensField.isEnabled
            && harness.posted == ["settings", "settings"])

    pane.clearToolResultsBox.performClick(nil)
    let clearing = AssistantChatSettings.load(from: suite).clearToolResults
    check(
        "the clear box: stored \(clearing), posted \(harness.posted)",
        clearing && harness.posted == ["settings", "settings", "settings"])
    check(
        "never key or model",
        !harness.posted.contains("key") && !harness.posted.contains("model"))

    // sync() over stored (false, 40000, true), the controls first set otherwise.
    chosen.save(to: suite)
    pane.compactBox.state = .on
    pane.clearToolResultsBox.state = .off
    pane.compactTokensField.isEnabled = true
    pane.compactTokensField.stringValue = "1"
    pane.sync()
    check(
        "sync() shows compact \(pane.compactBox.state == .on), \""
            + "\(pane.compactTokensField.stringValue)\", clear "
            + "\(pane.clearToolResultsBox.state == .on), field enabled "
            + "\(pane.compactTokensField.isEnabled)",
        pane.compactBox.state == .off && pane.clearToolResultsBox.state == .on
            && pane.compactTokensField.stringValue == 40_000.formatted()
            && !pane.compactTokensField.isEnabled)
    harness.window.close()

    let failed = checks.filter { !$0.1 }.map(\.0)
    row(
        "CS1", failed.isEmpty,
        (failed.isEmpty ? "" : "FAILED: \(failed.joined(separator: " | ")) || ")
            + checks.map(\.0).joined(separator: "; "))
}

// MARK: - CS2

/// Sends `text` and waits up to 30 s for the session to be idle again; the
/// events the turn appended.
func turn(_ editor: EditorViewController, _ text: String) -> (Bool, [[String: Any]]) {
    let before = editor.assistant?.events.count ?? 0
    let sent = editor.assistantSend(text)
    guard sent, let session = editor.assistant else { return (false, []) }
    let deadline = Date().addingTimeInterval(30)
    while session.phase != .idle && Date() < deadline { spin(0.05) }
    let events = Array(session.events.dropFirst(before))
    return (session.phase == .idle, events)
}

func kinds(_ events: [[String: Any]], _ kind: String) -> [[String: Any]] {
    events.filter { $0["type"] as? String == kind }
}

func rowCS2() {
    guard let (_, editor, window) = newEditor() else {
        row("CS2", false, "the editor did not open")
        return
    }
    defer { window.close() }
    var notes: [String] = []
    var good = true
    func check(_ name: String, _ ok: Bool) {
        notes.append("\(name) \(ok ? "ok" : "FAIL")")
        good = good && ok
    }

    let (idle1, events1) = turn(editor, "CS2 turn 1.")
    check(
        "turn 1: idle in 30 s \(idle1), compaction_started "
            + "\(kinds(events1, "compaction_started").count)",
        idle1 && kinds(events1, "compaction_started").isEmpty)
    guard let session = editor.assistant else {
        row("CS2", false, (notes + ["no session after turn 1"]).joined(separator: "; "))
        return
    }

    let harness = PaneHarness(defaults: .standard)
    let entriesBefore = editor.assistantTranscript.entries.count
    harness.commitTokens("40,000")
    harness.pane.clearToolResultsBox.performClick(nil)
    spin(0.3)
    let entries = editor.assistantTranscript.entries
    let ended = entries.contains { $0.text.contains("new conversation") }
    check(
        "the pane: posted \(harness.posted), the same session "
            + "\(editor.assistant === session), phase \(session.phase), entries "
            + "\(entriesBefore) → \(entries.count), a new-conversation entry \(ended)",
        harness.posted == ["settings", "settings"] && editor.assistant === session
            && session.phase != .closed && entries.count == entriesBefore && !ended)

    let (idle2, events2) = turn(editor, "CS2 turn 2.")
    let started = kinds(events2, "compaction_started")
    let used = started.first?["used"] as? Int
    let order = events2.compactMap { $0["type"] as? String }
        .filter { ["compaction_started", "compacted", "compaction_failed"].contains($0) }
    check(
        "turn 2: idle \(idle2), compaction events \(order), used "
            + "\(used.map(String.init) ?? "none")",
        idle2 && started.count == 1 && order == ["compaction_started", "compacted"]
            && (used.map { $0 >= 40_000 && $0 < 300_000 } ?? false))

    harness.pane.compactBox.performClick(nil)
    check("the compaction box off: posted \(harness.posted)", harness.posted.count == 3)

    let (idle3, events3) = turn(editor, "CS2 turn 3.")
    check(
        "turn 3: idle \(idle3), compaction_started "
            + "\(kinds(events3, "compaction_started").count)",
        idle3 && kinds(events3, "compaction_started").isEmpty)
    let errors = (events1 + events2 + events3).filter { $0["type"] as? String == "error" }
        .compactMap { $0["message"] as? String }
    check("errors \(errors)", errors.isEmpty)
    harness.window.close()
    editor.assistantClear()
    row("CS2", good, notes.joined(separator: "; "))
}

// MARK: - Run

removeChatKeys()
rowCS1()
rowCS2()
removeChatKeys()

let body: [String: Any] = [
    "rows": rows, "clearTriggerTokens": AssistantChatSettings.clearTriggerTokens,
]
let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
    ?? Data("{}".utf8)
print("ANSWER " + (String(data: data, encoding: .utf8) ?? "{}"))
fflush(stdout)
exit(0)
