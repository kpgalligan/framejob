// Road map 12 A2 — the Assistant tab's probe (spec §11 AI-4, AI-8, AI-11,
// AI-14, AI-17, AI-19).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line, `-D REELCUT_DEV_TOOLS` — by
// `assistant_tab_proof.py`, which copies the built helper to
// `<probe dir>/Contents/Helpers/reelcut-agent` (a bare binary's
// `Bundle.main.bundleURL` is its own folder) and runs it with a DUMMY key in
// `-RCSecretFolder`, `-ReelcutInspectorCollapsed NO`, and
// `RC_ASSISTANT_BASE_URL=http://127.0.0.1:9` (nothing listens there; no row
// here sends a message). In every mode it first registers every face in
// `--fonts <dir>` (the app's `app/Resources/Fonts`; a bare binary has no
// `ATSApplicationFontsPath`), so each row measures in the shipped faces (#207).
// Under `--close <path>` it runs P8 ALONE, and the proof points
// `RC_ASSISTANT_BASE_URL` at its stand-in (`anthropic_fake.py`), scripted to
// ask for `export` to `<path>` (#150). Under `--badge <path> --fonts <dir>` it
// runs P14 ALONE, against the stand-in scripted to ask for `export` to
// `<path>` twice (#152).
//
//   assistant_tab_probe --fonts <dir>   P1–P7, P9–P13, P15 (P9 writes
//                                       looks/assistant-light|dark.png under
//                                       the working folder)
//   assistant_tab_probe --close <path>  P8
//   assistant_tab_probe --badge <path> --fonts <dir>
//                                       P14 (writes looks/badge-light.png)
//
// Prints exactly one stdout line:
//   ANSWER {"rows":[{"id","ok","detail"}]}
//
//   P1  the transcript's mapping over a scripted event list
//   P2  the context meter's three figures, and its three ladders
//   P3  showAssistant: the tab shown, the composer first responder
//   P4  a question shown: Return answers nothing; Allow / Deny answer once each
//   P5  AI-14: a changed selection keeps the Assistant tab; a click shows Clip
//   P6  a real session ended by a model change, and by Clear
//   P7  Settings' Assistant pane over MemoryStores and a suite
//   P8  (#150) a window closed with a question pending: the session, held
//       strongly so `deinit` cannot stand in, is closed and the question
//       answered once `{allowed: false, by: "close"}`; the window's next lane
//       call answers; no file at the path
//   P9  (AI-17, #154) the composer at the inspector's minimum width less a
//       legacy scroller, light then dark: ⇧/⌥/⌃/⌘Return and ⇧ keypad Enter
//       insert "\n" and send nothing; Tab and ⇧Tab type nothing; 26 pt empty,
//       strictly taller through five lines, the sixth unchanged; every kind,
//       a usage reported, a cost, a question and five lines lay out with no
//       problem; a bare Return sends the whole text once and the field is ""
//       at 26 pt again; the meter (#182) shows a rung of its ladder that fits,
//       never the full figure for 5,000 of 200,000, its tooltip the full
//       figure, the meter's width the same for three usages; at 480 wide (the
//       control) the full figure, fitting
//   P10 (AI-17, #153) the transcript is one text: the entries joined by
//       "\n"; the dump's `assistant.entry.<kind>` parts in order, parented to
//       the transcript, tops never decreasing; an extension is one edit at or
//       past its entry's start, the earlier parts unchanged; a selection
//       across entries 0–1 copies as plain text; `.cleared` leaves no text
//       and no part; a secure field being edited leaks into no record, and
//       the composer's record reads its string
//   P11 (AI-17) the composer's undo is its own: typing leaves the document's
//       canUndo and edited state alone; `undo:` from the composer undoes
//       typing and not a document step; a set string drops the history
//   P12 (#182) the transcript's text view fills its clip view at 520, 720
//       and 420 pt high, so a click 4 pt above the clip view's bottom, below
//       the one entry (the control), hits the text view
//   P13 (#182 item 4) the composer's placeholder rect is one line high at
//       the text's origin; and with a 41-character message the field is one
//       line at 480, two at the minimum width, one at 480 again, one pass
//       each (a guard of the refit in the field's layout(); #182 item 3 is
//       accepted: a refit from AssistantView.layout() lagged a pass in B47)
//   P14 (#152, AI-19) light, in a real editor window: before any send the tab
//       is Clip, the Assistant tab never built, the dot hidden; asking, it
//       shows on Clip, Media and Assistant; Deny hides it at once and it stays
//       hidden once idle; a second question shows it and Stop hides it; in
//       Source Sans 3 at 280 and 480 pt the dot is inside the Assistant tab,
//       ≥ 1 pt from its trailing edge and ≥ 1 pt right of the title; the
//       inspector drawn with the dot hidden and with it removed is
//       byte-identical, and with it shown differs only inside the dot's rect
//       (outset 1 pt); no file at the path
//   P15 (#203) the Spend row at the inspector's minimum width less a legacy
//       scroller, light, for seven costs (none; priced 0.0018 and 0.00002;
//       partial 0.1234 and 12.3456; unknown alone; priced 0.0123 then
//       unknown): the label shows a rung of `figureLadder` that fits its
//       frame, ends " · Reelcut's estimate" once a response is counted, its
//       tooltip `figureTooltip`; the row's width the same for all seven; at
//       480 (the control) each shows `figure`; and (#207) the label's face is
//       IBMPlexMono-Regular, `--fonts` was given, and the shipped
//       IBMPlexMono-Regular.ttf registered (the face's file is reported, not
//       scored: Plex Mono is also installed in /Library/Fonts on this host)
import AppKit
import CoreText

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
    let ladders = [
        AssistantContextMeterView.figureLadder(
            AssistantContextUsage(used: 5_000, limit: 200_000, reported: true)),
        AssistantContextMeterView.figureLadder(
            AssistantContextUsage(used: 5_000, limit: nil, reported: true)),
        AssistantContextMeterView.figureLadder(AssistantContextUsage()),
    ]
    let wantLadders = [
        [wantKnown, "\(5_000.formatted()) / \(200_000.formatted()) · \(percent)%", "\(percent)%"],
        [wantUnknown, "\(5_000.formatted()) tokens"],
        ["Nothing reported yet"],
    ]
    row(
        "P2",
        none == "Nothing reported yet" && known == wantKnown && unknown == wantUnknown
            && ladders == wantLadders,
        "\"\(none)\"; \"\(known)\" (want \"\(wantKnown)\"); \"\(unknown)\"; ladders \(ladders) "
            + "(want \(wantLadders))")
}

// MARK: - P3 showAssistant

func rowP3(_ editor: EditorViewController, _ window: NSWindow) {
    let before = editor.inspector?.tab.title ?? "none"
    editor.showAssistant(nil)
    spin(0.3)
    let tab = editor.inspector?.tab
    let composer = editor.assistantView?.composer
    let focused = composer.map { window.firstResponder === $0 } ?? false
    let shown = composer.map { !$0.isHiddenOrHasHiddenAncestor && $0.window === window } ?? false
    row(
        "P3", tab == .assistant && focused && shown,
        "tab before \(before), after \(tab?.title ?? "none"); view attached "
            + "\(editor.assistantView != nil); composer on screen \(shown), first responder "
            + "\(focused); placeholder \"\(composer?.placeholder ?? "")\"")
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
    view.composer.string = "hi"
    window.makeFirstResponder(view.composer)
    if let event = key(36, "\r", window) { window.sendEvent(event) }
    let controlSent = sends == ["hi"] && view.composer.string.isEmpty

    let question = AssistantQuestion(tool: "export", path: "/tmp/P4.mp4", exists: false)
    view.show(phase: .asking, question: question)
    window.layoutIfNeeded()
    view.composer.string = "while asking"
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
    let placed = arranged.count == 3 && arranged[1] === window.assistantPane
        && arranged.last === window.transcriptionPane
    notes.append("Settings: three panes, Assistant pane second, Transcription pane last \(placed)")
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

// MARK: - P9 the composer's keys, growth and layout (AI-17)

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func keyEvent(
    _ keyCode: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = [],
    _ window: NSWindow
) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
}

/// `text` typed through the composer's own `keyDown`, one key per character.
func typeKeys(_ text: String, into composer: NSTextView, _ window: NSWindow) {
    let codes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, " ": 49,
    ]
    for character in text {
        if let event = keyEvent(codes[character] ?? 0, String(character), [], window) {
            composer.keyDown(with: event)
        }
    }
}

/// The panel's own background under the view, so a capture shows the look
/// (`cacheDisplay` draws views, never the window's background).
final class P9Backdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

/// P9's meter check at the window's current width, then the 480-wide control.
func p9Meter(_ view: AssistantView, _ window: NSWindow) -> (Bool, String) {
    guard let meter = walk(view).first(where: { $0 is AssistantContextMeterView })
        as? AssistantContextMeterView
    else { return (false, "meter: no AssistantContextMeterView in the view") }
    let label = meter.figuresLabel
    let u1 = AssistantContextUsage(used: 5_000, limit: 200_000, reported: true)
    let u2 = AssistantContextUsage(used: 123_456, limit: 1_000_000, reported: true)
    let u3 = AssistantContextUsage(used: 5_000, limit: nil, reported: true)
    var ok = true
    var notes: [String] = []
    var widths: [CGFloat] = []
    for (name, usage) in [("U1", u1), ("U2", u2), ("U3", u3)] {
        view.apply(.usage(usage))
        window.layoutIfNeeded()
        let shown = label.stringValue
        let inLadder = AssistantContextMeterView.figureLadder(usage).contains(shown)
        let fits = label.intrinsicContentSize.width <= label.frame.width + 0.5
        let tip = label.toolTip == AssistantContextMeterView.figures(usage)
        let short = name != "U1" || shown != AssistantContextMeterView.figures(usage)
        ok = ok && inLadder && fits && tip && short
        widths.append(meter.frame.width)
        notes.append("\(name) \"\(shown)\" (in the ladder \(inLadder), intrinsic "
            + "\(label.intrinsicContentSize.width) in \(label.frame.width), tooltip full \(tip)"
            + (name == "U1" ? ", not the full figure \(short)" : "") + ")")
    }
    let steady = widths.allSatisfy { abs($0 - widths[0]) <= 0.5 }
    ok = ok && steady
    notes.append("meter widths \(widths) (equal \(steady))")
    view.apply(.usage(u1))
    window.setContentSize(NSSize(width: 480, height: window.contentRect(
        forFrameRect: window.frame).height))
    window.layoutIfNeeded()
    let wide = label.stringValue
    let wideFull = wide == AssistantContextMeterView.figures(u1)
    let wideFits = label.intrinsicContentSize.width <= label.frame.width + 0.5
    ok = ok && wideFull && wideFits
    notes.append("control at 480: \"\(wide)\" (the full figure \(wideFull), intrinsic "
        + "\(label.intrinsicContentSize.width) in \(label.frame.width))")
    return (ok, "meter: " + notes.joined(separator: ", "))
}

func p9Look(_ look: String, _ appearance: NSAppearance.Name) -> (Bool, String) {
    NSApp.appearance = NSAppearance(named: appearance)
    defer { NSApp.appearance = nil }
    let width = EditorViewController.minInspectorWidth
        - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.titled],
        backing: .buffered, defer: false)
    let backdrop = P9Backdrop(frame: NSRect(x: 0, y: 0, width: width, height: 600))
    let view = AssistantView()
    view.frame = backdrop.bounds
    view.autoresizingMask = [.width, .height]
    backdrop.addSubview(view)
    window.contentView = backdrop
    var sends: [String] = []
    view.onSend = { text in
        sends.append(text)
        return true
    }
    view.show(hasKey: true)
    view.show(phase: .idle, question: nil)
    window.layoutIfNeeded()
    let composer = view.composer
    guard let field = composer.enclosingScrollView as? AssistantComposerField else {
        return (false, "\(look): the composer is not in an AssistantComposerField")
    }
    window.makeFirstResponder(composer)
    var notes: [String] = []

    // Modified Returns are new lines; nothing is sent.
    typeKeys("a", into: composer, window)
    for (flag, letter) in [
        (NSEvent.ModifierFlags.shift, "b"), (.option, "c"), (.control, "d"), (.command, "e"),
    ] {
        if let event = keyEvent(36, "\r", flag, window) { composer.keyDown(with: event) }
        typeKeys(letter, into: composer, window)
    }
    let modified = composer.string
    let modifiedOK = modified == "a\nb\nc\nd\ne" && !modified.contains("\u{2028}")
        && sends.isEmpty
    notes.append("⇧/⌥/⌃/⌘Return → \(modified.debugDescription) (want \"a\\nb\\nc\\nd\\ne\", no "
        + "U+2028), sends \(sends.count)")
    composer.string = "f"
    composer.setSelectedRange(NSRange(location: 1, length: 0))
    if let event = keyEvent(76, "\u{3}", [.shift, .numericPad], window) {
        composer.keyDown(with: event)
    }
    let enter = composer.string
    let enterOK = enter == "f\n" && sends.isEmpty
    notes.append("⇧ keypad Enter → \(enter.debugDescription)")

    // Tab and ⇧Tab move focus; they type nothing.
    composer.string = "tabs"
    window.makeFirstResponder(composer)
    composer.setSelectedRange(NSRange(location: 4, length: 0))
    if let event = keyEvent(48, "\t", [], window) { composer.keyDown(with: event) }
    window.makeFirstResponder(composer)
    if let event = keyEvent(48, "\u{19}", [.shift], window) { composer.keyDown(with: event) }
    let tabbed = composer.string
    let tabOK = tabbed == "tabs"
    notes.append("Tab, ⇧Tab → \(tabbed.debugDescription)")
    window.makeFirstResponder(composer)

    // 26 pt empty, strictly taller through five lines, the sixth unchanged.
    composer.string = ""
    window.layoutIfNeeded()
    let empty = field.frame.height
    var heights: [CGFloat] = []
    for count in 1...6 {
        composer.string = (1...count).map { "line \($0)" }.joined(separator: "\n")
        window.layoutIfNeeded()
        heights.append(field.frame.height)
    }
    let grows = heights[0] == AssistantComposerField.oneLineHeight
        && zip(heights[0..<4], heights[1..<5]).allSatisfy { $0 < $1 } && heights[5] == heights[4]
    let heightOK = empty == AssistantComposerField.oneLineHeight && grows
    notes.append("heights empty \(empty), lines 1–6 \(heights)")

    // Every kind, a cost, a question and five lines: no layout problem.
    var cost = AssistantTurnCost()
    cost.add([
        "type": "cost", "cost": ["kind": "dollars", "dollars": 0.0018] as [String: Any],
        "prices": ["kind": "bundled", "as_of": "2026-09-01"],
    ])
    view.reload(
        [
            .init(kind: .person, text: "Put a marker at two seconds,\nthen export it."),
            .init(kind: .reply, text: "Done: the marker is at 2 s and the export is written."),
            .init(kind: .progress, text: "Thinking about the timeline"),
            .init(kind: .meta, text: "add_marker (at: 1200000, name: P9)"),
            .init(kind: .error, text: "The assistant helper stopped."),
        ],
        usage: AssistantContextUsage(used: 5_000, limit: 200_000, reported: true), cost: cost)
    let question = AssistantQuestion(tool: "export", path: "/tmp/P9.mp4", exists: false)
    view.show(phase: .idle, question: question)
    composer.string = (1...5).map { "line \($0)" }.joined(separator: "\n")
    window.layoutIfNeeded()
    view.layoutSubtreeIfNeeded()
    let report = UISnapshotLayout.report(root: view, skipping: nil)
    let problems = report["problems"] as? [[String: Any]] ?? []
    notes.append("layout problems \(problems.count) \(String(describing: problems.prefix(3)))")
    let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("looks")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let png = folder.appendingPathComponent("assistant-\(look).png")
    try? FileManager.default.removeItem(at: png)
    var written = false
    if let rep = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds) {
        backdrop.cacheDisplay(in: backdrop.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            written = (try? data.write(to: png)) != nil
        }
    }
    notes.append("\(png.lastPathComponent) written \(written)")

    // A bare Return sends the whole text once and empties the field.
    view.show(phase: .idle, question: nil)
    let whole = composer.string
    window.makeFirstResponder(composer)
    if let event = keyEvent(36, "\r", [], window) { composer.keyDown(with: event) }
    window.layoutIfNeeded()
    let sentOK = sends == [whole] && composer.string.isEmpty
        && field.frame.height == AssistantComposerField.oneLineHeight
    notes.append("bare Return sent \(sends.map { $0.debugDescription }), composer "
        + "\(composer.string.debugDescription) at \(field.frame.height) pt")

    // The meter at this width: a rung of the ladder that fits, the full
    // figure in the tooltip; the meter's own width never follows the rung.
    let (meterOK, meterNote) = p9Meter(view, window)
    notes.append(meterNote)
    window.orderOut(nil)
    let ok = modifiedOK && enterOK && tabOK && heightOK && problems.isEmpty && written && sentOK
        && meterOK
    return (ok, "\(look): " + notes.joined(separator: "; "))
}

func rowP9() {
    let light = p9Look("light", .aqua)
    let dark = p9Look("dark", .darkAqua)
    row("P9", light.0 && dark.0, light.1 + " | " + dark.1)
}

// MARK: - P10 the transcript: one text, its parts, a copy across entries

func rowP10() {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 304, height: 520), styleMask: [.titled],
        backing: .buffered, defer: false)
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 304, height: 520))
    let view = AssistantView()
    view.frame = root.bounds
    view.autoresizingMask = [.width, .height]
    root.addSubview(view)
    let secure = NSSecureTextField(frame: NSRect(x: 4, y: 4, width: 120, height: 22))
    root.addSubview(secure)
    window.contentView = root
    view.show(hasKey: true)
    window.layoutIfNeeded()
    guard let transcript = walk(view).first(where: { $0 is AssistantTranscriptView })
        as? AssistantTranscriptView
    else {
        row("P10", false, "no AssistantTranscriptView in the view")
        return
    }
    var notes: [String] = []
    let entries: [AssistantEntry] = [
        .init(kind: .person, text: "First line of the person,\nand its second line."),
        .init(kind: .reply, text: "A reply."),
        .init(kind: .progress, text: "Thinking"),
        .init(kind: .meta, text: "add_marker (at: 1200000, name: P10)"),
        .init(kind: .error, text: "The assistant helper stopped."),
    ]
    view.reload(entries, usage: AssistantContextUsage(), cost: AssistantTurnCost())
    window.layoutIfNeeded()
    let joined = entries.map(\.text).joined(separator: "\n")
    let textOK = transcript.textView.string == joined
    notes.append("the text is the entries joined by \\n \(textOK)")

    func parts() -> (records: [[String: Any]], parentOK: Bool) {
        let report = UISnapshotLayout.report(root: root, skipping: nil)
        let views = report["views"] as? [[String: Any]] ?? []
        let owner = views.first { $0["class"] as? String == "AssistantTranscriptView" }?["i"]
            as? Int
        let records = views.filter { ($0["id"] as? String)?.hasPrefix("assistant.entry.") == true }
        let parentOK = owner != nil && records.allSatisfy { $0["parent"] as? Int == owner }
        return (records, parentOK)
    }
    let (records, parentOK) = parts()
    let got = records.map { (($0["id"] as? String) ?? "", ($0["text"] as? String) ?? "") }
    let want = entries.map { ("assistant.entry.\($0.kind.rawValue)", $0.text) }
    let recordsOK = got.count == want.count && zip(got, want).allSatisfy { $0 == $1 }
    let tops = records.compactMap { ($0["frame"] as? [Double])?[1] }
    let topsOK = tops.count == records.count && zip(tops, tops.dropFirst()).allSatisfy { $0 <= $1 }
    notes.append("records \(got.map { $0.0.replacingOccurrences(of: "assistant.entry.", with: "") }) "
        + "(as wanted \(recordsOK)), parented to the transcript \(parentOK), tops \(tops) "
        + "never decrease \(topsOK)")

    // An extension edits only the newest entry's range.
    view.apply(.appended(AssistantEntry(kind: .reply, text: "Hel")))
    let before = transcript.snapshotParts()
    let start = (transcript.textView.string as NSString).length - 3
    var posted: [NSRange] = []
    let token = NotificationCenter.default.addObserver(
        forName: NSTextStorage.didProcessEditingNotification,
        object: transcript.textView.textStorage, queue: nil
    ) { note in
        if let storage = note.object as? NSTextStorage { posted.append(storage.editedRange) }
    }
    view.apply(.extended(index: 5, text: "Hello, world."))
    NotificationCenter.default.removeObserver(token)
    let after = transcript.snapshotParts()
    let extendOK = posted.count == 1 && (posted.first?.location ?? -1) >= start
        && before.count == 6 && after.count == 6 && Array(before[0..<5]) == Array(after[0..<5])
        && after[5].text == "Hello, world."
    notes.append("extend: \(posted.count) edit(s) at \(posted.map { "\($0)" }) (entry starts at "
        + "\(start)), earlier parts unchanged \(before.count == 6 && Array(before.prefix(5)) == Array(after.prefix(5)))")

    // A selection across entries 0–1 copies as plain text.
    let firstLength = (entries[0].text as NSString).length
    let selection = NSRange(location: firstLength - 5, length: 5 + 1 + 4)
    transcript.textView.setSelectedRange(selection)
    let wanted = (transcript.textView.string as NSString).substring(with: selection)
    // What Copy writes: the selection in the view's writable types, to a
    // private pasteboard (never the person's). NSTextView writes plain text
    // by the legacy name; `.string` is what the pasteboard reads it back as.
    let plain = NSPasteboard.PasteboardType("NSStringPboardType")
    let types = transcript.textView.writablePasteboardTypes
    let board = NSPasteboard(name: NSPasteboard.Name("com.kgalligan.reelcut.p10." + UUID().uuidString))
    board.clearContents()
    let wrote = transcript.textView.writeSelection(to: board, types: types)
    let copied = board.string(forType: .string)
    let rich = board.types?.contains(where: { $0 == .rtf || $0 == .rtfd }) == true
    board.releaseGlobally()
    let copyOK = wrote && copied == wanted && wanted.contains("\n") && !rich
    let typesOK = types == [plain]
    notes.append("copy across 0–1 \(copied.debugDescription) (want \(wanted.debugDescription)); "
        + "writable types \(types.map(\.rawValue))")

    // Cleared: no text and no part.
    view.apply(.cleared)
    let (clearedRecords, _) = parts()
    let clearedOK = transcript.textView.string.isEmpty && clearedRecords.isEmpty
    notes.append("cleared: text \(transcript.textView.string.debugDescription), parts "
        + "\(clearedRecords.count)")

    // A secure field being edited: its text in no record; the composer's is read.
    secure.stringValue = "p10-secret"
    window.makeFirstResponder(secure)
    let editing = secure.currentEditor() != nil
    view.composer.string = "p10 composer"
    let report = UISnapshotLayout.report(root: root, skipping: nil)
    let views = report["views"] as? [[String: Any]] ?? []
    let leaked = views.contains { ($0["text"] as? String)?.contains("p10-secret") == true }
    let composerText = views.first { $0["id"] as? String == "assistant.composer" }?["text"]
        as? String
    let secureOK = editing && !leaked && composerText == "p10 composer"
    notes.append("secure field being edited \(editing), its text in a record \(leaked); the "
        + "composer's record \(composerText.debugDescription)")
    window.orderOut(nil)
    row("P10", textOK && recordsOK && parentOK && topsOK && extendOK && copyOK && typesOK
        && clearedOK && secureOK, notes.joined(separator: "; "))
}

// MARK: - P11 the composer's undo is its own

final class P11Marker {
    var ran = false
}

func rowP11() {
    guard let (document, editor, window) = newEditor() else {
        row("P11", false, "the editor did not open")
        return
    }
    editor.showAssistant(nil)
    spin(0.3)
    guard let composer = editor.assistantView?.composer, let manager = document.undoManager
    else {
        row("P11", false, "no composer, or no document undo manager")
        return
    }
    window.makeFirstResponder(composer)
    var notes: [String] = []
    let shared = window.undoManager === manager
    let canUndoBefore = manager.canUndo
    let editedBefore = document.isDocumentEdited
    let controls = shared && !canUndoBefore && !editedBefore
    notes.append("controls: the window's undo manager is the document's \(shared); before "
        + "typing canUndo \(canUndoBefore), edited \(editedBefore)")
    typeKeys("abc", into: composer, window)
    spin(0.3)
    let own = composer.undoManager !== manager
    let quiet = manager.canUndo == canUndoBefore && document.isDocumentEdited == editedBefore
    let typedUndo = composer.undoManager?.canUndo == true
    notes.append("typed \(composer.string.debugDescription): own manager \(own); document canUndo "
        + "\(manager.canUndo), edited \(document.isDocumentEdited); composer canUndo \(typedUndo)")
    let marker = P11Marker()
    manager.registerUndo(withTarget: marker) { $0.ran = true }
    manager.setActionName("P11 marker")
    spin(0.2)
    let performed = composer.tryToPerform(Selector(("undo:")), with: nil)
    spin(0.1)
    let text = composer.string
    let prefix = text.count < 3 && "abc".hasPrefix(text)
    let markerKept = !marker.ran && manager.canUndo && manager.undoActionName == "P11 marker"
    notes.append("undo: performed \(performed), composer \(text.debugDescription) (a strict prefix "
        + "of abc \(prefix)), marker ran \(marker.ran), document canUndo \(manager.canUndo) "
        + "\"\(manager.undoActionName)\"")
    composer.string = "x"
    let dropped = composer.undoManager?.canUndo == false
    notes.append("string = \"x\" drops the composer's undo \(dropped)")
    row("P11", controls && own && quiet && typedUndo && performed && prefix && markerKept && dropped,
        notes.joined(separator: "; "))
    manager.removeAllActions()
    withExtendedLifetime(document) {}
}

// MARK: - P12 the transcript's text view fills its clip view (#182)

func rowP12() {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 304, height: 520), styleMask: [.titled],
        backing: .buffered, defer: false)
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 304, height: 520))
    let view = AssistantView()
    view.frame = root.bounds
    view.autoresizingMask = [.width, .height]
    root.addSubview(view)
    window.contentView = root
    view.show(hasKey: true)
    window.layoutIfNeeded()
    guard let transcript = walk(view).first(where: { $0 is AssistantTranscriptView })
        as? AssistantTranscriptView
    else {
        row("P12", false, "no AssistantTranscriptView in the view")
        return
    }
    view.reload([.init(kind: .person, text: "One line.")], usage: AssistantContextUsage(),
                cost: AssistantTurnCost())
    var ok = true
    var notes: [String] = []
    for height in [520, 720, 420] as [CGFloat] {
        window.setContentSize(NSSize(width: 304, height: height))
        window.layoutIfNeeded()
        let clip = transcript.contentView
        let textHeight = transcript.textView.frame.height
        let filled = abs(textHeight - clip.bounds.height) <= 0.5
        // Window coordinates: y grows upward, so "above the bottom" is +4.
        let clipInWindow = clip.convert(clip.bounds, to: nil)
        let point = NSPoint(x: clipInWindow.midX, y: clipInWindow.minY + 4)
        let entry = transcript.entryLayout().first?.rect ?? .zero
        let entryInWindow = transcript.convert(entry, to: nil)
        let below = !entry.isEmpty && point.y < entryInWindow.minY
        let hit = transcript.superview.flatMap { superview in
            transcript.hitTest(superview.convert(point, from: nil))
        }
        let hitText = hit === transcript.textView
        ok = ok && filled && below && hitText
        notes.append("\(Int(height)): text view \(textHeight) in a clip view of "
            + "\(clip.bounds.height) (filled \(filled); text view frame \(transcript.textView.frame), "
            + "clip bounds \(clip.bounds)); the point \(point) below the entry's "
            + "\(entryInWindow) \(below) (the control); hitTest → "
            + "\(hit.map { String(describing: type(of: $0)) } ?? "nil") (the text \(hitText))")
    }
    window.orderOut(nil)
    row("P12", ok, notes.joined(separator: "; "))
}

// MARK: - P13 the placeholder's height (#182 item 4) and the width refit in the field's layout()

func rowP13() {
    NSApp.appearance = NSAppearance(named: .aqua)
    defer { NSApp.appearance = nil }
    let narrow = EditorViewController.minInspectorWidth
        - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 600), styleMask: [.titled],
        backing: .buffered, defer: false)
    let backdrop = P9Backdrop(frame: NSRect(x: 0, y: 0, width: 480, height: 600))
    let view = AssistantView()
    view.frame = backdrop.bounds
    view.autoresizingMask = [.width, .height]
    backdrop.addSubview(view)
    window.contentView = backdrop
    view.show(hasKey: true)
    view.show(phase: .idle, question: nil)
    window.layoutIfNeeded()
    let composer = view.composer
    guard let field = composer.enclosingScrollView as? AssistantComposerField else {
        row("P13", false, "the composer is not in an AssistantComposerField")
        return
    }
    let lineHeight = AssistantComposerField.lineHeight(composer.font ?? DS.sans(12))
    let one = AssistantComposerField.oneLineHeight
    composer.string = "Put a marker at two seconds and then cut."
    window.layoutIfNeeded()
    let wide = field.frame.height
    let constant = {
        field.constraints.first { $0.firstAttribute == .height && $0.secondItem == nil }?
            .constant ?? -1
    }
    var trace = ["480: constant \(constant()), text view width \(composer.frame.width)"]
    window.setContentSize(NSSize(width: narrow, height: 600))
    window.layoutIfNeeded()
    let narrowHeight = field.frame.height
    trace.append("narrow: constant \(constant()), text view width \(composer.frame.width)")
    window.setContentSize(NSSize(width: 480, height: 600))
    window.layoutIfNeeded()
    let back = field.frame.height
    trace.append("480 again: constant \(constant()), text view width \(composer.frame.width)")
    composer.string = ""
    let rect = composer.placeholderRect
    let placeholderOK = !composer.placeholder.isEmpty && rect.height == lineHeight
        && rect.minY == composer.textContainerOrigin.y && rect.width > 0
    // A guard of the refit in the field's layout() (#182 item 3, accepted in B47):
    // one line, two at the narrow width, one again, each after one pass.
    let heightsOK = wide == one && narrowHeight == one + lineHeight && back == one
    window.orderOut(nil)
    row("P13", placeholderOK && heightsOK,
        "placeholder \"\(composer.placeholder)\"; placeholderRect \(rect) (want height "
            + "\(lineHeight), minY \(composer.textContainerOrigin.y), width > 0); "
            + "\"Put a marker at two seconds and then cut.\" after one layoutIfNeeded() each: "
            + "at 480 \(wide) pt (want \(one)), at \(narrow) \(narrowHeight) pt (want "
            + "\(one + lineHeight)), at 480 again \(back) pt (want \(one)); "
            + trace.joined(separator: ", "))
}

// MARK: - P14 the Assistant tab's question dot (#152, AI-19)

/// The bytes of `view` drawn by `cacheDisplay`, with its pixel geometry.
struct P14Capture {
    let rep: NSBitmapImageRep
    let bytes: [UInt8]
}

func p14Capture(_ view: NSView) -> P14Capture? {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.bitmapData else { return nil }
    let count = rep.bytesPerRow * rep.pixelsHigh
    return P14Capture(rep: rep, bytes: Array(UnsafeBufferPointer(start: data, count: count)))
}

/// Pixels of `a` and `b` that differ, counted inside and outside `inside`
/// (a pixel rect: columns x, rows from the top).
func p14Differences(_ a: P14Capture, _ b: P14Capture, inside: NSRect) -> (Int, Int) {
    let stride = a.rep.bitsPerPixel / 8
    var within = 0
    var outside = 0
    for row in 0..<a.rep.pixelsHigh {
        for column in 0..<a.rep.pixelsWide {
            let at = row * a.rep.bytesPerRow + column * stride
            if a.bytes[at..<(at + stride)] == b.bytes[at..<(at + stride)] { continue }
            if inside.contains(NSPoint(x: CGFloat(column) + 0.5, y: CGFloat(row) + 0.5)) {
                within += 1
            } else {
                outside += 1
            }
        }
    }
    return (within, outside)
}

func rowP14(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
    NSApp.appearance = NSAppearance(named: .aqua)
    defer { NSApp.appearance = nil }
    guard let (_, editor, _) = newEditor(), let inspector = editor.inspector else {
        row("P14", false, "the editor or its inspector did not open")
        return
    }
    let badge = inspector.assistantBadge
    var notes: [String] = []
    var ok = true
    func check(_ name: String, _ good: Bool, _ detail: String) {
        ok = ok && good
        notes.append("\(name) \(good ? "ok" : "FAIL"): \(detail)")
    }
    func shown() -> Bool { !badge.isHiddenOrHasHiddenAncestor }
    func phase() -> String { editor.assistant.map { "\($0.phase)" } ?? "no session" }

    // (a) before any send.
    check("(a)", inspector.tab == .clip && editor.assistantView == nil && !shown(),
          "tab \(inspector.tab), assistantView nil \(editor.assistantView == nil), "
            + "badge shown \(shown())")

    // (b) asking: shown on Clip, Media and Assistant.
    let sent = editor.assistantSend("Export the project (P14 one).")
    var deadline = Date().addingTimeInterval(30)
    while editor.assistant?.phase != .asking && Date() < deadline { spin(0.05) }
    let asking = editor.assistant?.phase == .asking
    let onClip = shown() && inspector.tab == .clip
    inspector.select(.media)
    let onMedia = shown() && inspector.tab == .media
    inspector.select(.assistant)
    spin(0.1)
    let onAssistant = shown() && inspector.tab == .assistant
    check("(b)", sent && asking && onClip && onMedia && onAssistant,
          "sent \(sent), asking in 30 s \(asking) (phase \(phase())); shown on Clip \(onClip), "
            + "on Media \(onMedia), on Assistant \(onAssistant)")

    // (c) Deny: hidden at once, and still hidden once idle.
    editor.assistantAnswer(false)
    let deniedHidden = !shown()
    deadline = Date().addingTimeInterval(30)
    while editor.assistant?.phase != .idle && Date() < deadline { spin(0.05) }
    let idle = editor.assistant?.phase == .idle
    check("(c)", deniedHidden && idle && !shown(),
          "hidden at Deny \(deniedHidden); idle in 30 s \(idle) (phase \(phase())); hidden "
            + "\(!shown())")

    // (d) a second question, then Stop.
    let again = editor.assistantSend("Export the project (P14 two).")
    deadline = Date().addingTimeInterval(30)
    while editor.assistant?.phase != .asking && Date() < deadline { spin(0.05) }
    let askingAgain = editor.assistant?.phase == .asking && shown()
    let phaseAgain = phase()
    editor.assistantStop()
    let stoppedHidden = !shown()
    check("(d)", again && askingAgain && stoppedHidden,
          "sent \(again), asking and shown \(askingAgain) (phase \(phaseAgain)); hidden at "
            + "Stop \(stoppedHidden) (phase \(phase()))")

    // (e) geometry, in the shipped Source Sans 3.
    let registered = NSFont(name: "SourceSans3-SemiBold", size: 12) != nil
    var geometry: [String] = []
    var geometryOK = registered
    for width in [EditorViewController.minInspectorWidth, 480] {
        let tab = InspectorTabBadge.tabRect(stripWidth: width, stripHeight: DS.tabHeight)
        let title = InspectorTabBadge.titleRect(stripWidth: width, stripHeight: DS.tabHeight)
        let dot = InspectorTabBadge.dotRect(stripWidth: width, stripHeight: DS.tabHeight)
        let inside = tab.contains(dot) && tab.maxX - dot.maxX >= 1
        let clear = dot.minX >= title.maxX + 1
        geometryOK = geometryOK && inside && clear
        geometry.append("at \(width): tab \(tab), title \(title), dot \(dot) (inside with ≥ 1 pt "
            + "to the trailing edge \(inside), ≥ 1 pt right of the title \(clear))")
    }
    check("(e)", geometryOK,
          "SourceSans3-SemiBold registered \(registered); " + geometry.joined(separator: "; "))

    // (f) pixels: shown (A), hidden (B), removed (C).
    let root = inspector.view
    root.layoutSubtreeIfNeeded()
    // The dot's rect in the root, read while the badge is still in it.
    let dot = badge.convert(
        InspectorTabBadge.dotRect(stripWidth: badge.bounds.width, stripHeight: badge.bounds.height),
        to: root
    ).insetBy(dx: -1, dy: -1)
    inspector.showAssistantBadge(true)
    let a = p14Capture(root)
    inspector.showAssistantBadge(false)
    let b = p14Capture(root)
    badge.removeFromSuperview()
    let c = p14Capture(root)
    if let a, let b, let c {
        let scale = CGFloat(a.rep.pixelsWide) / root.bounds.width
        let top = root.isFlipped ? dot.minY : root.bounds.height - dot.maxY
        let pixels = NSRect(x: dot.minX * scale, y: top * scale, width: dot.width * scale,
                            height: dot.height * scale)
        let sameBC = b.bytes == c.bytes
        let (within, outside) = p14Differences(a, b, inside: pixels)
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("looks")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let png = folder.appendingPathComponent("badge-light.png")
        try? FileManager.default.removeItem(at: png)
        let written = a.rep.representation(using: .png, properties: [:])
            .map { (try? $0.write(to: png)) != nil } ?? false
        check("(f)", sameBC && within > 0 && outside == 0 && written,
              "\(a.rep.pixelsWide)×\(a.rep.pixelsHigh) px; hidden and removed byte-identical "
                + "\(sameBC); shown vs hidden: \(within) px differ inside the dot's rect "
                + "\(pixels) (want > 0), \(outside) outside (want 0); \(png.lastPathComponent) "
                + "written \(written)")
    } else {
        check("(f)", false, "a capture failed (A \(a != nil), B \(b != nil), C \(c != nil))")
    }

    // (g) nothing written.
    let noFile = !FileManager.default.fileExists(atPath: path)
    check("(g)", noFile, "no file at \(path) \(noFile)")
    row("P14", ok, notes.joined(separator: "; "))
}

// MARK: - P15 the Spend row at the inspector's minimum width (#203)

/// The shipped faces' registration (#207), set once before the mode dispatch.
var shippedFonts: (directory: String?, notes: [String], plexRegistered: Bool) = (nil, [], false)

/// Registers every `.ttf` and `.otf` in `--fonts <dir>` for the process, as
/// the harness's `registerFonts` does. IBMPlexMono-Regular.ttf counts as
/// registered when the call answers true or answers "already registered" (105).
func registerShippedFonts(_ arguments: [String]) -> (
    directory: String?, notes: [String], plexRegistered: Bool
) {
    guard let index = arguments.firstIndex(of: "--fonts"), index + 1 < arguments.count else {
        return (nil, ["no --fonts"], false)
    }
    let fonts = URL(fileURLWithPath: arguments[index + 1])
    var notes: [String] = []
    var plexRegistered = false
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: fonts.path)) ?? []).sorted()
    for name in names where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
        var error: Unmanaged<CFError>?
        let done = CTFontManagerRegisterFontsForURL(
            fonts.appendingPathComponent(name) as CFURL, .process, &error)
        let code = error.map { CFErrorGetCode($0.takeRetainedValue()) }
        let registered = done || code == CTFontManagerError.alreadyRegistered.rawValue
        if name == "IBMPlexMono-Regular.ttf" { plexRegistered = registered }
        notes.append("\(name) \(done ? "registered" : "error \(code.map(String.init) ?? "none")")")
    }
    return (fonts.path, notes, plexRegistered)
}

func p15Costs() -> [(String, AssistantTurnCost)] {
    func event(_ cost: [String: Any], partial: Bool = false) -> [String: Any] {
        var made: [String: Any] = [
            "type": "cost", "cost": cost, "prices": ["kind": "bundled", "as_of": "2026-09-01"],
        ]
        if partial { made["partial"] = true }
        return made
    }
    func priced(_ dollars: Double) -> [String: Any] { ["kind": "dollars", "dollars": dollars] }
    let unknown: [String: Any] = ["kind": "unknown", "cause": "model", "detail": "no price"]
    func made(_ events: [[String: Any]]) -> AssistantTurnCost {
        var cost = AssistantTurnCost()
        for item in events { cost.add(item) }
        return cost
    }
    return [
        ("none", AssistantTurnCost()),
        ("priced 0.0018", made([event(priced(0.0018))])),
        ("priced 0.00002", made([event(priced(0.000_02))])),
        ("partial 0.1234", made([event(priced(0.1234), partial: true)])),
        ("partial 12.3456", made([event(priced(12.3456), partial: true)])),
        ("unknown alone", made([event(unknown)])),
        ("priced 0.0123 then unknown", made([event(priced(0.0123)), event(unknown)])),
    ]
}

func rowP15() {
    NSApp.appearance = NSAppearance(named: .aqua)
    defer { NSApp.appearance = nil }
    let narrow = EditorViewController.minInspectorWidth
        - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: narrow, height: 600), styleMask: [.titled],
        backing: .buffered, defer: false)
    let backdrop = P9Backdrop(frame: NSRect(x: 0, y: 0, width: narrow, height: 600))
    let view = AssistantView()
    view.frame = backdrop.bounds
    view.autoresizingMask = [.width, .height]
    backdrop.addSubview(view)
    window.contentView = backdrop
    view.show(hasKey: true)
    view.show(phase: .idle, question: nil)
    window.layoutIfNeeded()
    guard let spend = walk(view).first(where: { $0 is AssistantConversationCostView })
        as? AssistantConversationCostView
    else {
        row("P15", false, "no AssistantConversationCostView in the view")
        return
    }
    let label = spend.figureLabel
    let suffix = " · Reelcut's estimate"
    let wantedFace = "IBMPlexMono-Regular"
    let face = label.font?.fontName ?? "none"
    let faceOK = face == wantedFace
    let fontFile = label.font.flatMap {
        CTFontCopyAttribute($0 as CTFont, kCTFontURLAttribute) as? URL
    }?.path ?? "none"
    var ok = faceOK && shippedFonts.directory != nil && shippedFonts.plexRegistered
    var notes = [
        "face \(face) (wanted \(wantedFace)) \(faceOK); fonts \(shippedFonts.directory ?? "none"); "
            + "IBMPlexMono-Regular.ttf registered \(shippedFonts.plexRegistered); font file \(fontFile)",
    ] + shippedFonts.notes
    var widths: [CGFloat] = []
    for (name, cost) in p15Costs() {
        view.reload([], usage: AssistantContextUsage(), cost: cost)
        window.layoutIfNeeded()
        let shown = label.stringValue
        let fits = label.intrinsicContentSize.width <= label.frame.width + 0.5
        let ends = name == "none" ? shown == "Nothing yet" : shown.hasSuffix(suffix)
        let tip = label.toolTip == AssistantTurnCost.figureTooltip
        let inLadder = cost.figureLadder.contains(shown)
        ok = ok && fits && ends && tip && inLadder
        widths.append(spend.frame.width)
        notes.append("\(name) \"\(shown)\" (\(shown.count) characters; intrinsic "
            + "\(label.intrinsicContentSize.width) in \(label.frame.width), fits \(fits); "
            + "ends as wanted \(ends); in the ladder \(inLadder); tooltip \(tip))")
    }
    let steady = widths.allSatisfy { abs($0 - widths[0]) <= 0.5 }
    ok = ok && steady
    notes.append("at \(narrow) the row's widths \(widths) (equal \(steady))")
    window.setContentSize(NSSize(width: 480, height: 600))
    window.layoutIfNeeded()
    for (name, cost) in p15Costs() {
        view.reload([], usage: AssistantContextUsage(), cost: cost)
        window.layoutIfNeeded()
        let shown = label.stringValue
        let full = shown == cost.figure
        let fits = label.intrinsicContentSize.width <= label.frame.width + 0.5
        ok = ok && full && fits
        notes.append("control at 480: \(name) \"\(shown)\" (the full figure \(full), intrinsic "
            + "\(label.intrinsicContentSize.width) in \(label.frame.width))")
    }
    window.orderOut(nil)
    row("P15", ok, notes.joined(separator: "; "))
}

// MARK: - Run

let arguments = CommandLine.arguments
let closePath: String? = arguments.firstIndex(of: "--close").flatMap { index in
    index + 1 < arguments.count ? arguments[index + 1] : nil
}
let badgePath: String? = arguments.firstIndex(of: "--badge").flatMap { index in
    index + 1 < arguments.count ? arguments[index + 1] : nil
}

// The shipped faces first, for every mode, as the harness's `registerFonts`
// does: a bare binary has no `ATSApplicationFontsPath` (#207).
shippedFonts = registerShippedFonts(arguments)

if let closePath {
    rowP8(closePath)
} else if let badgePath {
    rowP14(badgePath)
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
    rowP9()
    rowP10()
    rowP11()
    rowP12()
    rowP13()
    rowP15()
}

let body: [String: Any] = ["rows": rows]
let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
    ?? Data("{}".utf8)
print("ANSWER " + (String(data: data, encoding: .utf8) ?? "{}"))
fflush(stdout)
exit(0)
