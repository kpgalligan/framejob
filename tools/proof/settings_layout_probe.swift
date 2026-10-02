// Issue batch B71 — the Settings window's structure after the redesign:
// Assistant above Transcription, each key label naming its service, each
// heading's ⓘ holding its pane's explanation (spec §11 SH-5), no long
// paragraph left in the window, and the ⓘ's hover and click policy.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a`. One process,
// no arguments. Its answer is one JSON object on stdout, `{"rows": [...]}`,
// each row `{"id", "pass", "detail"}`; `settings_layout_probe.py` prints and
// scores them.
//
// The fixture: `SettingsWindowController` over two `MemoryStore`s, an empty
// environment, an absent spend folder and a scratch `UserDefaults` suite; the
// window is never shown. Every string a row compares is a LITERAL, never the
// app's own constant, so a changed constant is a changed answer. Rows:
//   L1 `content`'s arranged subviews are exactly [assistantPane,
//      transcriptionPane], and `content.spacing` is 24.
//   L2 each pane opens with a stack of [headingLabel, infoButton], the
//      headings reading "Assistant" and "Transcription".
//   L3 the row holding each key field opens with "Anthropic API key:" /
//      "AssemblyAI API key:"; both empty placeholders read "Paste your key";
//      no text field in the window reads exactly "API key:".
//   L4 each ⓘ: its text is its owner's `explanation()`, its accessibility
//      label "About <section>" and help the text, no tooltip; its popover's
//      label holds the text at 13 pt in the label colour; the texts carry
//      their facts.
//   L5 no text field in the window holds an explanation's words or runs past
//      200 characters; the spend note is still there and visible.
//   L6 a synthesized mouse-entered schedules a hover show; a mouse-exited
//      before the delay cancels it and nothing shows.
//   L7 the click policy on a button in no window (state changes, no show).
//   L8 the transient guard's hit test on a button in an unshown window.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": String(detail.prefix(1500))])
}

func finish() -> Never {
    let answer: [String: Any] = ["rows": rows]
    let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    exit(0)
}

func fields(in view: NSView) -> [NSTextField] {
    var found: [NSTextField] = []
    if let field = view as? NSTextField { found.append(field) }
    for sub in view.subviews { found += fields(in: sub) }
    return found
}

func isDescendant(_ view: NSView, of root: NSView?) -> Bool {
    guard let root else { return false }
    var walk: NSView? = view
    while let current = walk {
        if current === root { return true }
        walk = current.superview
    }
    return false
}

func enterExit(_ type: NSEvent.EventType) -> NSEvent? {
    NSEvent.enterExitEvent(
        with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)
}

let suiteName = "com.kgalligan.reelcut.settings-layout-probe"
UserDefaults().removePersistentDomain(forName: suiteName)
guard let suite = UserDefaults(suiteName: suiteName) else {
    row("L1", false, "no suite")
    finish()
}
let absentSpend = URL(fileURLWithPath: "/nonexistent/reelcut-settings-layout-spend", isDirectory: true)
let controller = SettingsWindowController(
    store: { MemoryStore() }, assistantStore: { MemoryStore() }, defaults: suite,
    environment: [:], spendFolder: { absentSpend })
let assistant = controller.assistantPane
guard let root = controller.window?.contentView else {
    row("L1", false, "the window has no content view")
    finish()
}
root.layoutSubtreeIfNeeded()
let allFields = fields(in: root)

// MARK: - L1 the order

do {
    let arranged = controller.content.arrangedSubviews
    let ordered = arranged.count == 2 && arranged[0] === assistant
        && arranged[1] === controller.transcriptionPane
    let spacing = controller.content.spacing
    row("L1", ordered && spacing == 24,
        "arranged \(arranged.map { String(describing: type(of: $0)) }), "
            + "assistant first \(arranged.first === assistant), "
            + "transcription last \(arranged.last === controller.transcriptionPane), spacing \(spacing)")
}

// MARK: - L2 the headers

func header(of pane: NSStackView, heading: NSTextField, info: SettingsInfoButton) -> (Bool, String) {
    guard let stack = pane.arrangedSubviews.first as? NSStackView else {
        return (false, "first arranged subview is \(pane.arrangedSubviews.first.map { "\(type(of: $0))" } ?? "nil")")
    }
    let views = stack.arrangedSubviews
    let ok = views.count == 2 && views[0] === heading && views[1] === info
    return (ok, "header stack of \(views.count), heading then info \(ok)")
}
do {
    let (aOK, aDetail) = header(of: assistant, heading: assistant.headingLabel, info: assistant.infoButton)
    let (tOK, tDetail) = header(
        of: controller.transcriptionPane, heading: controller.headingLabel, info: controller.infoButton)
    let aTitle = assistant.headingLabel.stringValue
    let tTitle = controller.headingLabel.stringValue
    row("L2", aOK && tOK && aTitle == "Assistant" && tTitle == "Transcription",
        "Assistant: \(aDetail), \"\(aTitle)\"; Transcription: \(tDetail), \"\(tTitle)\"")
}

// MARK: - L3 the key labels

func keyRowLabel(_ field: NSTextField) -> String {
    guard let stack = field.superview as? NSStackView, stack.arrangedSubviews.contains(field),
        let label = stack.arrangedSubviews.first as? NSTextField, label !== field
    else { return "<no row>" }
    return label.stringValue
}
do {
    let aLabel = keyRowLabel(assistant.keyField)
    let tLabel = keyRowLabel(controller.keyField)
    let aPlace = assistant.keyField.placeholderString ?? "<nil>"
    let tPlace = controller.keyField.placeholderString ?? "<nil>"
    let bare = allFields.filter { $0.stringValue == "API key:" }.count
    row("L3", aLabel == "Anthropic API key:" && tLabel == "AssemblyAI API key:"
            && aPlace == "Paste your key" && tPlace == "Paste your key" && bare == 0,
        "labels \"\(aLabel)\" / \"\(tLabel)\", placeholders \"\(aPlace)\" / \"\(tPlace)\", "
            + "bare \"API key:\" fields \(bare)")
}

// MARK: - L4 the info buttons

func infoFacts(_ button: SettingsInfoButton, owner: String, section: String) -> (Bool, String) {
    let label = button.infoLabel
    let checks: [(String, Bool)] = [
        ("text is explanation()", button.infoText == owner),
        ("a11y label", button.accessibilityLabel() == "About \(section)"),
        ("a11y help", button.accessibilityHelp() == button.infoText),
        ("no tooltip", button.toolTip == nil),
        ("label text", label.stringValue == button.infoText),
        ("13 pt", label.font?.pointSize == 13),
        ("label colour", label.textColor == NSColor.labelColor),
        ("in the popover", isDescendant(label, of: button.popover.contentViewController?.view)),
    ]
    let failed = checks.filter { !$0.1 }.map(\.0)
    return (failed.isEmpty, "\(section): " + (failed.isEmpty ? "all hold" : "failed \(failed)")
        + " (\(label.font?.pointSize ?? 0) pt, \(label.textColor.map { "\($0)" } ?? "nil"))")
}
do {
    let (aOK, aDetail) = infoFacts(
        assistant.infoButton, owner: AssistantSettingsPane.explanation(), section: "Assistant")
    let (tOK, tDetail) = infoFacts(
        controller.infoButton, owner: SettingsWindowController.explanation(), section: "Transcription")
    let tText = controller.infoButton.infoText
    let aText = assistant.infoButton.infoText
    let tWords = ["uploaded to AssemblyAI", "deleted from AssemblyAI", "$0.21 an hour", "2026-09-17"]
    let aWords = ["compaction threshold", "Changing either setting keeps the conversation."]
    let missing = tWords.filter { !tText.contains($0) } + aWords.filter { !aText.contains($0) }
    row("L4", aOK && tOK && missing.isEmpty, "\(aDetail); \(tDetail); missing words \(missing)")
}

// MARK: - L5 no paragraph left

do {
    let paragraphs = allFields.filter {
        $0.stringValue.contains("uploaded to AssemblyAI") || $0.stringValue.contains("compaction threshold")
    }
    let long = allFields.filter { $0.stringValue.count > 200 }
    let note = assistant.spendNoteLabel
    let notePresent = isDescendant(note, of: root) && !note.isHiddenOrHasHiddenAncestor
    row("L5", paragraphs.isEmpty && long.isEmpty && notePresent,
        "fields \(allFields.count), holding an explanation \(paragraphs.count), "
            + "over 200 characters \(long.map(\.stringValue.count)), spend note present \(notePresent)")
}

// MARK: - L6 hover, cancelled

do {
    let button = controller.infoButton
    if let entered = enterExit(.mouseEntered), let exited = enterExit(.mouseExited) {
        button.mouseEntered(with: entered)
        let pending = button.hoverPending
        button.mouseExited(with: exited)
        let cleared = !button.hoverPending
        let shown = button.isShowingInfo
        row("L6", pending && cleared && !shown,
            "after enter pending \(pending); after exit cleared \(cleared), showing \(shown)")
    } else {
        row("L6", false, "could not synthesize the enter/exit events")
    }
}

// MARK: - L7 the click policy

do {
    let button = SettingsInfoButton(section: "Probe", infoText: "Probe text.")
    var steps: [String] = []
    func note(_ name: String) { steps.append("\(name) → \(button.infoState)") }
    let exited = enterExit(.mouseExited)
    button.showInfo(byHover: true); note("hover")
    let s1 = button.infoState == .hover
    button.toggleInfo(nil); note("press")
    let s2 = button.infoState == .held
    if let exited { button.mouseExited(with: exited) }
    note("exit")
    let s3 = button.infoState == .held
    button.toggleInfo(nil); note("press")
    let s4 = button.infoState == .closed
    button.toggleInfo(nil); note("press")
    let s5 = button.infoState == .held
    button.hideInfo(); note("hide")
    let s6 = button.infoState == .closed
    button.showInfo(byHover: true)
    if let exited { button.mouseExited(with: exited) }
    note("hover, exit")
    let s7 = button.infoState == .closed
    row("L7", exited != nil && s1 && s2 && s3 && s4 && s5 && s6 && s7, steps.joined(separator: "; "))
}

// MARK: - L8 the transient guard's hit test

do {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled],
        backing: .buffered, defer: true)
    let other = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled],
        backing: .buffered, defer: true)
    let button = SettingsInfoButton(section: "Probe", infoText: "Probe text.")
    if let content = window.contentView {
        content.addSubview(button)
        button.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 60).isActive = true
        button.topAnchor.constraint(equalTo: content.topAnchor, constant: 60).isActive = true
        content.layoutSubtreeIfNeeded()
        let frame = button.convert(button.bounds, to: nil)
        let centre = NSPoint(x: frame.midX, y: frame.midY)
        let outside = NSPoint(x: centre.x + 40, y: centre.y)
        let onIt = button.isOnIcon(locationInWindow: centre, in: window)
        let offIt = button.isOnIcon(locationInWindow: outside, in: window)
        let elsewhere = button.isOnIcon(locationInWindow: centre, in: other)
        row("L8", onIt && !offIt && !elsewhere,
            "frame \(frame); centre \(onIt), 40 pt out \(offIt), another window \(elsewhere)")
    } else {
        row("L8", false, "the window has no content view")
    }
}

UserDefaults().removePersistentDomain(forName: suiteName)
finish()
