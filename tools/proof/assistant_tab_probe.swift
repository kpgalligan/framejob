// Road map 12 A2 — the Assistant tab's probe (spec §11 AI-4, AI-8, AI-11,
// AI-14).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line, `-D REELCUT_DEV_TOOLS` — by
// `assistant_tab_proof.py`, which copies the built helper to
// `<probe dir>/Contents/Helpers/reelcut-agent` (a bare binary's
// `Bundle.main.bundleURL` is its own folder) and runs it with a DUMMY key in
// `-RCSecretFolder`, `-ReelcutInspectorCollapsed NO`, and
// `RC_ASSISTANT_BASE_URL=http://127.0.0.1:9` (nothing listens there; no row
// here sends a message). Under `--close <path>` it runs P8 ALONE, and the
// proof points `RC_ASSISTANT_BASE_URL` at its stand-in (`anthropic_fake.py`),
// scripted to ask for `export` to `<path>` (#150).
//
//   assistant_tab_probe                 P1–P7
//   assistant_tab_probe --close <path>  P8
//
// Prints exactly one stdout line:
//   ANSWER {"rows":[{"id","ok","detail"}]}
//
//   P1  the transcript's mapping over a scripted event list
//   P2  the context meter's three figures
//   P3  showAssistant: the tab shown, the composer first responder
//   P4  a question shown: Return answers nothing; Allow / Deny answer once each
//   P5  AI-14: a changed selection keeps the Assistant tab; a click shows Clip
//   P6  a real session ended by a model change, and by Clear
//   P7  Settings' Assistant pane over MemoryStores and a suite
//   P8  (#150) a window closed with a question pending: the session, held
//       strongly so `deinit` cannot stand in, is closed and the question
//       answered once `{allowed: false, by: "close"}`; the window's next lane
//       call answers; no file at the path
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

func key(_ keyCode: UInt16, _ characters: String, _ window: NSWindow) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
}

func click(_ control: NSView) {
    guard let window = control.window else { return }
    let centre = control.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
    guard
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown, location: centre, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
            pressure: 1)
    else { return }
    control.mouseDown(with: event)
}

// MARK: - P1 the mapping

func rowP1() {
    let transcript = AssistantTranscript()
    var changes: [AssistantTranscriptChange] = []
    transcript.onChange = { changes.append($0) }
    let events: [[String: Any]] = [
        ["type": "turn_started"],
        ["type": "text_delta", "text": "Hel"], ["type": "text_delta", "text": "lo."],
        ["type": "tool_call", "name": "add_marker",
         "arguments": ["project": "/tmp/A.reelcut", "name": "P1", "at": 1_200_000]],
        ["type": "tool_result", "name": "add_marker", "is_error": false, "summary": "ok"],
        ["type": "tool_result", "name": "export", "is_error": true, "summary": "no media"],
        ["type": "text_delta", "text": "Again"],
        ["type": "progress_delta", "text": "Thinking"], ["type": "progress_delta", "text": " more"],
        ["type": "text_delta", "text": "Next"],
        ["type": "message_done", "stop_reason": "end_turn", "usage": [:] as [String: Any]],
        ["type": "text_delta", "text": "After"],
        ["type": "compaction_started", "used": 310_000],
        ["type": "compacted", "before": 310_000, "after": 9_000],
        ["type": "compaction_failed", "reason": "timeout"],
        ["type": "tool_results_cleared", "tool_uses": 3, "tokens": 4_000],
        ["type": "context_usage", "used": 5_000, "limit": 200_000],
        ["type": "question", "tool": "export", "sentence": "export writes /tmp/D.mp4"],
        ["type": "answer", "allowed": true, "by": "person"],
        ["type": "question", "tool": "export", "sentence": "export REPLACES /tmp/E.mp4"],
        ["type": "answer", "allowed": false, "by": "person"],
        ["type": "question", "tool": "export", "sentence": "export writes /tmp/S.mp4"],
        ["type": "answer", "allowed": false, "by": "stop"],
        ["type": "error", "message": "The assistant helper stopped."],
        ["type": "turn_finished"],
    ]
    transcript.person("Mark two seconds.")
    for event in events { transcript.take(event) }
    let want: [AssistantEntry] = [
        .init(kind: .person, text: "Mark two seconds."),
        .init(kind: .reply, text: "Hello."),
        .init(kind: .meta, text: "add_marker (at: 1200000, name: P1)"),
        .init(kind: .meta, text: "failed: no media"),
        .init(kind: .reply, text: "Again"),
        .init(kind: .progress, text: "Thinking more"),
        .init(kind: .reply, text: "Next"),
        .init(kind: .reply, text: "After"),
        .init(kind: .meta, text: "Compacting the conversation (\(310_000.formatted()) tokens)…"),
        .init(
            kind: .meta,
            text: "Compacted: \(310_000.formatted()) → about \(9_000.formatted()) tokens. "
                + "Earlier renders are gone; the assistant re-renders when it needs to look."),
        .init(
            kind: .meta,
            text: "Compaction didn't finish (timeout); it will try again after the next turn."),
        .init(
            kind: .meta,
            text: "Cleared 3 old tool results (\(4_000.formatted()) tokens) from the model's view."),
        .init(kind: .meta, text: "Allowed: export writes /tmp/D.mp4"),
        .init(kind: .meta, text: "Declined: export REPLACES /tmp/E.mp4"),
        .init(kind: .meta, text: "Declined (stop): export writes /tmp/S.mp4"),
        .init(kind: .error, text: "The assistant helper stopped."),
    ]
    let usage = AssistantContextUsage(used: 5_000, limit: 200_000, reported: true)
    let got = transcript.entries
    let gotUsage = transcript.usage
    let extended = changes.filter { if case .extended = $0 { return true } else { return false } }
    let summaries = [
        AssistantTranscript.argumentSummary(nil),
        AssistantTranscript.argumentSummary(["project": "/x"]),
        AssistantTranscript.argumentSummary(["z": String(repeating: "a", count: 80)]),
        AssistantTranscript.argumentSummary(["clips": [3, 4], "ripple": true]),
    ]
    let long = " (z: " + String(repeating: "a", count: 67) + ")"
    transcript.clear()
    let cleared = transcript.entries.isEmpty && changes.last == .usage(
        AssistantContextUsage(used: 0, limit: 200_000, reported: true))
    transcript.take(["type": "context_usage", "used": 42, "limit": 200_000])
    transcript.endConversation(note: "P1 note.")
    let ended = transcript.entries == [.init(kind: .meta, text: "P1 note.")]
        && transcript.usage.used == 0 && transcript.usage.limit == 200_000
    var firstDiff = "none"
    for (index, pair) in zip(got, want).enumerated() where pair.0 != pair.1 {
        firstDiff = "#\(index) got \(pair.0.kind.rawValue) \"\(pair.0.text)\" want "
            + "\(pair.1.kind.rawValue) \"\(pair.1.text)\""
        break
    }
    let ok = got == want && gotUsage == usage && extended.count == 2
        && summaries == ["", "", long, " (clips: [3,4], ripple: true)"] && cleared && ended
    row(
        "P1", ok,
        "\(got.count) entries (want \(want.count)), all equal \(got == want) (first difference "
            + "\(firstDiff)); usage \(gotUsage) want \(usage); extended \(extended.count) (want 2: "
            + "`lo.` and ` more`); summaries \(summaries); clear kept the window \(cleared); "
            + "endConversation \(ended)")
}

// MARK: - P2 the figures

func rowP2() {
    let none = AssistantContextMeterView.figures(AssistantContextUsage())
    let known = AssistantContextMeterView.figures(
        AssistantContextUsage(used: 5_000, limit: 200_000, reported: true))
    let unknown = AssistantContextMeterView.figures(
        AssistantContextUsage(used: 5_000, limit: nil, reported: true))
    let percent = 2.5.formatted(.number.precision(.fractionLength(0...1)))
    let wantKnown = "\(5_000.formatted()) of \(200_000.formatted()) tokens · \(percent)%"
    let wantUnknown = "\(5_000.formatted()) tokens (window size unknown)"
    row(
        "P2", none == "Nothing reported yet" && known == wantKnown && unknown == wantUnknown,
        "\"\(none)\"; \"\(known)\" (want \"\(wantKnown)\"); \"\(unknown)\"")
}

// MARK: - P3 showAssistant

func rowP3(_ editor: EditorViewController, _ window: NSWindow) {
    let before = editor.inspector?.tab.title ?? "none"
    editor.showAssistant(nil)
    spin(0.3)
    let tab = editor.inspector?.tab
    let composer = editor.assistantView?.composer
    let focused = composer.map { $0.currentEditor() != nil
        && window.firstResponder === $0.currentEditor() } ?? false
    let shown = composer.map { !$0.isHiddenOrHasHiddenAncestor && $0.window === window } ?? false
    row(
        "P3", tab == .assistant && focused && shown,
        "tab before \(before), after \(tab?.title ?? "none"); view attached "
            + "\(editor.assistantView != nil); composer on screen \(shown), first responder "
            + "\(focused); placeholder \"\(composer?.placeholderString ?? "")\"")
}

// MARK: - P4 Return never answers

func rowP4() {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 304, height: 520), styleMask: [.titled],
        backing: .buffered, defer: false)
    let view = AssistantView()
    view.frame = NSRect(x: 0, y: 0, width: 304, height: 520)
    view.autoresizingMask = [.width, .height]
    window.contentView = view
    var answers: [Bool] = []
    var sends: [String] = []
    var stops = 0
    view.onAnswer = { answers.append($0) }
    view.onSend = { text in
        sends.append(text)
        return true
    }
    view.onStop = { stops += 1 }
    view.show(hasKey: true)
    window.layoutIfNeeded()

    // The control: idle, Return sends and empties the composer.
    view.show(phase: .idle, question: nil)
    view.composer.stringValue = "hi"
    window.makeFirstResponder(view.composer)
    if let event = key(36, "\r", window) { window.sendEvent(event) }
    let controlSent = sends == ["hi"] && view.composer.stringValue.isEmpty

    let question = AssistantQuestion(tool: "export", path: "/tmp/P4.mp4", exists: false)
    view.show(phase: .asking, question: question)
    window.layoutIfNeeded()
    view.composer.stringValue = "while asking"
    window.makeFirstResponder(view.composer)
    if let event = key(36, "\r", window) { window.sendEvent(event) }
    let returnQuiet = answers.isEmpty && sends == ["hi"] && stops == 0
    let afterReturn = "answers \(answers), sends \(sends), stops \(stops)"
    let rowText = view.questionLabel.stringValue
    let rowShown = !view.questionLabel.isHiddenOrHasHiddenAncestor
        && rowText == "export writes /tmp/P4.mp4"
    let stopTitle = view.sendButton.title
    click(view.allowButton)
    let afterAllow = answers
    click(view.denyButton)
    let afterDeny = answers
    view.show(phase: .idle, question: nil)
    let hidden = view.questionLabel.isHiddenOrHasHiddenAncestor && view.sendButton.title == "Send"
    row(
        "P4",
        controlSent && returnQuiet && rowShown && stopTitle == "Stop" && afterAllow == [true]
            && afterDeny == [true, false] && hidden,
        "idle Return sent \(sends.first ?? "nothing") and emptied the composer \(controlSent); "
            + "asking: Return → \(afterReturn) (quiet \(returnQuiet)); row shown "
            + "\(rowShown) \"\(rowText)\"; Send reads \(stopTitle); "
            + "Allow → \(afterAllow); Deny → \(afterDeny); idle again hides the row \(hidden)")
}

// MARK: - P5 AI-14

func rowP5(_ document: ProjectDocument, _ editor: EditorViewController) {
    guard let inspector = editor.inspector else {
        row("P5", false, "no inspector")
        return
    }
    if document.project.snapshot.tracks.isEmpty {
        document.applyEdit("Add Track", ReelOp.addTrack(index: 0))
    }
    guard let track = document.project.snapshot.tracks.first?.id else {
        row("P5", false, "no track")
        return
    }
    document.applyEdit("Add Text", ReelOp.addTextClip(track: track, at: 0, duration: 600_000))
    guard let clip = document.project.snapshot.clips.first?.id else {
        row("P5", false, "no clip")
        return
    }
    func pick(_ ids: Set<UInt32>) {
        document.selection = ids
        editor.viewStateDidChange()
        spin(0.2)
    }
    pick([])
    inspector.select(.media)
    pick([clip])
    let control = inspector.tab
    pick([])
    inspector.select(.assistant)
    pick([clip])
    let kept = inspector.tab
    inspector.clipPicked()
    let clicked = inspector.tab
    row(
        "P5", control == .clip && kept == .assistant && clicked == .clip,
        "from Media a changed selection shows \(control.title) (the control); from Assistant it "
            + "shows \(kept.title); clipPicked() then shows \(clicked.title)")
}

// MARK: - P6 a real session, ended

func rowP6(_ editor: EditorViewController) {
    guard let view = editor.assistantView else {
        row("P6", false, "no Assistant view attached")
        return
    }
    let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/reelcut-agent")
    var notes: [String] = ["helper \(FileManager.default.isExecutableFile(atPath: helper.path))"]
    guard case .success(let first) = editor.assistantSession() else {
        if case .failure(let error) = editor.assistantSession() {
            notes.append("open refused: \(error.message)")
        }
        row("P6", false, notes.joined(separator: "; "))
        return
    }
    spin(0.3)
    NotificationCenter.default.post(
        name: AssistantConfiguration.didChangeNotification, object: nil,
        userInfo: [AssistantConfiguration.changeKey: "model"])
    let wantNote = "The model is now \(AssistantConfiguration.model()); the next message starts "
        + "a new conversation."
    let modelEnded = first.phase == .closed && editor.assistant == nil
        && editor.assistantTranscript.entries.last == AssistantEntry(kind: .meta, text: wantNote)
    notes.append(
        "model change: closed \(first.phase == .closed), assistant nil "
            + "\(editor.assistant == nil), last entry "
            + "\"\(editor.assistantTranscript.entries.last?.text ?? "none")\"")

    guard case .success(let second) = editor.assistantSession() else {
        row("P6", false, (notes + ["the second open was refused"]).joined(separator: "; "))
        return
    }
    spin(0.3)
    let beforeClear = editor.assistantTranscript.entries.count
    view.clearButton.performClick(nil)
    let cleared = second.phase == .closed && editor.assistant == nil
        && editor.assistantTranscript.entries.isEmpty && beforeClear > 0
    notes.append(
        "Clear (the button): closed \(second.phase == .closed), assistant nil "
            + "\(editor.assistant == nil), entries \(beforeClear) → "
            + "\(editor.assistantTranscript.entries.count)")
    row("P6", modelEnded && cleared, notes.joined(separator: "; "))
}

// MARK: - P7 Settings' Assistant pane

func rowP7() {
    let suiteName = "com.kgalligan.reelcut.assistant-tab-probe"
    UserDefaults().removePersistentDomain(forName: suiteName)
    guard let suite = UserDefaults(suiteName: suiteName) else {
        row("P7", false, "no suite")
        return
    }
    defer { UserDefaults().removePersistentDomain(forName: suiteName) }
    let store = MemoryStore()
    let pane = AssistantSettingsPane(store: { store }, defaults: suite, environment: [:])
    var posted: [String] = []
    let token = NotificationCenter.default.addObserver(
        forName: AssistantConfiguration.didChangeNotification, object: pane, queue: nil
    ) { note in
        posted.append(note.userInfo?[AssistantConfiguration.changeKey] as? String ?? "?")
    }
    defer { NotificationCenter.default.removeObserver(token) }
    var notes: [String] = []
    let emptyState = pane.keyField.placeholderString == AssistantSettingsPane.emptyPlaceholder
        && pane.statusLabel.stringValue == "No API key is set."
        && pane.removeButton.isEnabled == false
    notes.append("empty: placeholder, status, Remove off \(emptyState)")

    pane.keyField.stringValue = "p7-dummy-key"
    pane.saveClicked(nil)
    let saved = store.read() == "p7-dummy-key" && pane.keyField.stringValue.isEmpty
        && pane.keyField.placeholderString == SettingsWindowController.maskedPlaceholder
        && posted == ["key"] && !pane.statusLabel.stringValue.contains("p7-dummy-key")
    notes.append("Save: stored \(store.read() != nil), field empty "
        + "\(pane.keyField.stringValue.isEmpty), masked "
        + "\(pane.keyField.placeholderString == SettingsWindowController.maskedPlaceholder), "
        + "posted \(posted)")

    pane.removeClicked(nil)
    let removed = store.read() == nil && posted == ["key", "key"]
        && pane.keyField.placeholderString == AssistantSettingsPane.emptyPlaceholder
    notes.append("Remove: store empty \(store.read() == nil), posted \(posted)")

    pane.modelField.stringValue = AssistantConfiguration.defaultModel
    pane.modelChanged(nil)
    let defaultQuiet = posted.count == 2
        && suite.string(forKey: AssistantConfiguration.modelKey) == AssistantConfiguration.defaultModel
    notes.append("\"\" → \(AssistantConfiguration.defaultModel): posted \(posted.count - 2), "
        + "written \(suite.string(forKey: AssistantConfiguration.modelKey) ?? "nil")")

    pane.modelField.stringValue = "claude-probe-model"
    pane.modelChanged(nil)
    let changed = posted == ["key", "key", "model"]
        && AssistantConfiguration.model(defaults: suite) == "claude-probe-model"
    pane.modelChanged(nil)
    let sameQuiet = posted == ["key", "key", "model"]
    notes.append("claude-probe-model: posted \(posted), the same again posts nothing \(sameQuiet)")

    let window = SettingsWindowController(
        store: { MemoryStore() }, assistantStore: { MemoryStore() }, defaults: suite,
        environment: [:])
    let arranged = window.content.arrangedSubviews
    let placed = arranged.first === window.headingLabel && arranged.last === window.assistantPane
    notes.append("Settings: Transcription heading first, Assistant pane last \(placed)")
    row("P7", emptyState && saved && removed && defaultQuiet && changed && sameQuiet && placed,
        notes.joined(separator: "; "))
}

// MARK: - P8 close with a question pending (#150)

/// A lane answer crossing to main.
final class LaneResult {
    private let lock = NSLock()
    private var stored: String?

    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ result: String) {
        lock.lock()
        stored = result
        lock.unlock()
    }
}

func rowP8(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
    guard let (document, editor, window) = newEditor() else {
        row("P8", false, "the editor did not open")
        return
    }
    let sent = editor.assistantSend("Export the project (P8).")
    let deadline = Date().addingTimeInterval(30)
    while editor.assistant?.phase != .asking && Date() < deadline { spin(0.05) }
    // Held STRONGLY from here, so its `deinit` cannot decline in `close`'s place.
    guard let session = editor.assistant, session.phase == .asking else {
        row("P8", false, "sent \(sent); never asking in 30 s (phase "
            + "\(editor.assistant.map { "\($0.phase)" } ?? "no session"))")
        return
    }
    let sentence = session.pendingQuestion?.sentence ?? "none"
    let asked = sentence == "export writes \(path)"
    window.close()
    spin(0.5)
    let closed = session.phase == .closed
    let released = editor.assistant == nil
    let events = session.events
    let questionAt = events.lastIndex { $0["type"] as? String == "question" }
    let after = questionAt.map { Array(events[($0 + 1)...]) } ?? []
    let answers = after.filter { $0["type"] as? String == "answer" }
    let byClose = answers.count == 1 && answers[0]["allowed"] as? Bool == false
        && answers[0]["by"] as? String == "close"
    let followUp = LaneResult()
    AgentLane.shared.submit(
        tool: "get_project", argumentsJSON: "{}", document: document,
        askFirst: { _, reply in reply(false) }, completion: { followUp.set($0) })
    let followDeadline = Date().addingTimeInterval(10)
    while followUp.value == nil && Date() < followDeadline { spin(0.02) }
    let answered = followUp.value != nil
    let noFile = !FileManager.default.fileExists(atPath: path)
    let described = answers.map { answer in
        "{allowed: \(answer["allowed"] ?? "nil"), by: \(answer["by"] ?? "nil")}"
    }
    row("P8", asked && closed && released && byClose && answered && noFile,
        "asked \"\(sentence)\" (as wanted \(asked)); after window.close(): phase closed "
            + "\(closed), editor.assistant nil \(released), answers after the question "
            + "\(described) (one, by close: \(byClose)); the next call on the document answered "
            + "in 10 s \(answered) (\(String((followUp.value ?? "nothing").prefix(120)))); "
            + "no file \(noFile)")
    withExtendedLifetime(session) {}
}

// MARK: - Run

let arguments = CommandLine.arguments
let closePath: String? = arguments.firstIndex(of: "--close").flatMap { index in
    index + 1 < arguments.count ? arguments[index + 1] : nil
}

if let closePath {
    rowP8(closePath)
} else {
    rowP1()
    rowP2()
    if let (document, editor, window) = newEditor() {
        rowP3(editor, window)
        rowP4()
        rowP5(document, editor)
        rowP6(editor)
    } else {
        for id in ["P3", "P4", "P5", "P6"] { row(id, false, "the editor did not open") }
    }
    rowP7()
}

let body: [String: Any] = ["rows": rows]
let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
    ?? Data("{}".utf8)
print("ANSWER " + (String(data: data, encoding: .utf8) ?? "{}"))
fflush(stdout)
exit(0)
