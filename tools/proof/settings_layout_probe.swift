// Issue batch B71 — the Settings window's structure after the redesign:
// Assistant above Transcription, each key label naming its service, each
// heading's ⓘ holding its pane's explanation (spec §11 SH-5), no long
// paragraph left in the window, and the ⓘ's hover and click policy. Issue
// batch B74 (spec §11 MC-7) put the MCP pane first and added L9–L11: its
// order and text, Copy MCP Command's press, and its missing-helper state.
// #127 G6 phase 4 (spec §11 G-38) put the Playback pane last and added L12.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a`. One process,
// no arguments. Its answer is one JSON object on stdout, `{"rows": [...]}`,
// each row `{"id", "pass", "detail"}`; `settings_layout_probe.py` prints and
// scores them.
//
// The fixture: `SettingsWindowController` over two `MemoryStore`s, an empty
// environment, an absent spend folder and a scratch `UserDefaults` suite; the
// window is never shown. L9 and L10 build a second controller whose MCP
// helper is "/bin/sh" and L11 a third whose helper is
// "/nonexistent/framejob-mcp", both over a private pasteboard
// (`com.kgalligan.framejob.settings-layout-probe`, released at exit); the
// general pasteboard is never written. Every string a row compares is a
// LITERAL, never the app's own constant, so a changed constant is a changed
// answer. Rows:
//   L1 `content`'s arranged subviews are exactly [mcpPane, assistantPane,
//      transcriptionPane, playbackPane], and `content.spacing` is 24.
//   L2 the Assistant and Transcription panes open with a stack of
//      [headingLabel, infoButton], the headings reading "Assistant" and
//      "Transcription"; the MCP pane opens with its bare headingLabel reading
//      "MCP" and holds no `SettingsInfoButton`; the window's
//      `initialFirstResponder` is the Assistant key field.
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
//   L9 the MCP pane's arranged subviews are [heading, blurb 1, blurb 2,
//      helper, button, status]; the blurbs read the two literals at 13 pt in
//      the label colour; the helper label reads "/bin/sh", is selectable and
//      wraps at 420; the button reads "Copy MCP Command" and, after layout,
//      sits below the last blurb in the root view's coordinates.
//   L10 with "/bin/sh": the button is enabled and the status empty; a
//      `performClick` puts `claude mcp add --scope user framejob -- '/bin/sh'`
//      on the private pasteboard and the copied sentence in the status; the
//      general pasteboard's `changeCount` does not move; `sync()` empties the
//      status.
//   L11 with "/nonexistent/framejob-mcp": the button is disabled, the status
//      is the missing sentence, and a direct `copyClicked(nil)` leaves the
//      private pasteboard's `changeCount` where it was.
//   L12 the Playback pane opens with [settingsSectionHeader("Playback", ⓘ)]
//      and its row; the box reads "Background render" and is on, the field
//      reads "5", the stepper runs 1–60. Unticking writes false and disables
//      the field and the stepper; committing "0" leaves the suite unchanged
//      and shows "5"; committing "12" writes 12 and sets the stepper to 12;
//      stepping up writes 13.
//   L13 the window fits its screen (G-38, fix pass 1): a fresh controller's
//      `fitScreen` over a 3000 pt visible frame leaves `scroll` exactly the
//      document's height (nothing scrolls); over a 1440 × 875 one (a
//      1440 × 900 display less its menu bar) the window's frame lies inside
//      it vertically, the document is taller than the clip (the panes
//      scroll), and the Playback pane is still `content`'s last, inside the
//      document.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

var rows: [[String: Any]] = []
/// The private pasteboard L10 and L11 write, released by `finish()`.
var probePasteboard: NSPasteboard?
func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": String(detail.prefix(1500))])
}

func finish() -> Never {
    let answer: [String: Any] = ["rows": rows]
    let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    probePasteboard?.releaseGlobally()
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

let suiteName = "com.kgalligan.framejob.settings-layout-probe"
UserDefaults().removePersistentDomain(forName: suiteName)
guard let suite = UserDefaults(suiteName: suiteName) else {
    row("L1", false, "no suite")
    finish()
}
let absentSpend = URL(fileURLWithPath: "/nonexistent/framejob-settings-layout-spend", isDirectory: true)
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
    let ordered = arranged.count == 4 && arranged[0] === controller.mcpPane
        && arranged[1] === assistant && arranged[2] === controller.transcriptionPane
        && arranged[3] === controller.playbackPane
    let spacing = controller.content.spacing
    row("L1", ordered && spacing == 24,
        "arranged \(arranged.map { String(describing: type(of: $0)) }), "
            + "mcp first \(arranged.first === controller.mcpPane), "
            + "assistant second \(arranged.count > 1 && arranged[1] === assistant), "
            + "transcription third \(arranged.count > 2 && arranged[2] === controller.transcriptionPane), "
            + "playback last \(arranged.last === controller.playbackPane), spacing \(spacing)")
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
    let mcp = controller.mcpPane
    let mFirst = mcp.arrangedSubviews.first === mcp.headingLabel
    let mTitle = mcp.headingLabel.stringValue
    func infoButtons(in view: NSView) -> Int {
        (view is SettingsInfoButton ? 1 : 0) + view.subviews.reduce(0) { $0 + infoButtons(in: $1) }
    }
    let mInfo = infoButtons(in: mcp)
    let responder = controller.window?.initialFirstResponder === assistant.keyField
    row("L2", aOK && tOK && aTitle == "Assistant" && tTitle == "Transcription"
            && mFirst && mTitle == "MCP" && mInfo == 0 && responder,
        "Assistant: \(aDetail), \"\(aTitle)\"; Transcription: \(tDetail), \"\(tTitle)\"; "
            + "MCP: heading first \(mFirst), \"\(mTitle)\", ⓘ buttons \(mInfo); "
            + "initial first responder is the Assistant key field \(responder)")
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

// MARK: - L9 the MCP pane's order and text

let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.kgalligan.framejob.settings-layout-probe"))
probePasteboard = pasteboard
let shController = SettingsWindowController(
    store: { MemoryStore() }, assistantStore: { MemoryStore() }, defaults: suite,
    environment: [:], spendFolder: { absentSpend },
    mcpHelper: URL(fileURLWithPath: "/bin/sh"), pasteboard: pasteboard)
let shPane = shController.mcpPane
do {
    let shRoot = shController.window?.contentView
    shRoot?.layoutSubtreeIfNeeded()
    let expectedOrder: [NSView] =
        [shPane.headingLabel] + shPane.blurbLabels + [shPane.helperLabel, shPane.copyButton, shPane.statusLabel]
    let arranged = shPane.arrangedSubviews
    let ordered = arranged.count == expectedOrder.count
        && zip(arranged, expectedOrder).allSatisfy { $0 === $1 }
    let blurbs = [
        "An MCP client such as Claude Code uses Frame Job's tools through framejob-mcp, a helper inside "
            + "this app. It reaches Frame Job over a local socket that only programs you run can open.",
        "If Frame Job isn't running, the first tool call opens it in the background. To add Frame Job to "
            + "Claude Code, copy the command and run it in Terminal.",
    ]
    let texts = shPane.blurbLabels.map(\.stringValue)
    let styled = shPane.blurbLabels.allSatisfy {
        $0.font?.pointSize == 13 && $0.textColor == NSColor.labelColor
    }
    let helper = shPane.helperLabel
    let helperOK = helper.stringValue == "/bin/sh" && helper.isSelectable
        && helper.preferredMaxLayoutWidth == 420
    let title = shPane.copyButton.title
    var below = false
    var frames = "no root"
    if let shRoot, let last = shPane.blurbLabels.last {
        let button = shPane.copyButton.convert(shPane.copyButton.bounds, to: shRoot)
        let blurb = last.convert(last.bounds, to: shRoot)
        below = shRoot.isFlipped ? button.minY >= blurb.maxY : button.maxY <= blurb.minY
        frames = "button \(button), last blurb \(blurb), flipped \(shRoot.isFlipped)"
    }
    row("L9", ordered && texts == blurbs && styled && helperOK && title == "Copy MCP Command" && below,
        "order \(ordered) (\(arranged.count) views); blurbs equal \(texts == blurbs); 13 pt label colour "
            + "\(styled); helper \"\(helper.stringValue)\" selectable \(helper.isSelectable) width "
            + "\(helper.preferredMaxLayoutWidth); title \"\(title)\"; below \(below) (\(frames))")
}

// MARK: - L10 the press, with a helper

do {
    let enabled = shPane.copyButton.isEnabled
    let emptyBefore = shPane.statusLabel.stringValue
    let generalBefore = NSPasteboard.general.changeCount
    shPane.copyButton.performClick(nil)
    let copied = pasteboard.string(forType: .string) ?? "<nil>"
    let status = shPane.statusLabel.stringValue
    let generalAfter = NSPasteboard.general.changeCount
    shPane.sync()
    let statusAfterSync = shPane.statusLabel.stringValue
    row("L10", enabled && emptyBefore == ""
            && copied == "claude mcp add --scope user framejob -- '/bin/sh'"
            && status == "Copied. Paste it into Terminal and press Return."
            && generalBefore == generalAfter && statusAfterSync == "",
        "enabled \(enabled), status before \"\(emptyBefore)\"; copied \"\(copied)\"; status \"\(status)\"; "
            + "general changeCount \(generalBefore) → \(generalAfter); after sync \"\(statusAfterSync)\"")
}

// MARK: - L11 the missing helper

do {
    let missing = SettingsWindowController(
        store: { MemoryStore() }, assistantStore: { MemoryStore() }, defaults: suite,
        environment: [:], spendFolder: { absentSpend },
        mcpHelper: URL(fileURLWithPath: "/nonexistent/framejob-mcp"), pasteboard: pasteboard)
    let pane = missing.mcpPane
    let disabled = !pane.copyButton.isEnabled
    let status = pane.statusLabel.stringValue
    let before = pasteboard.changeCount
    pane.copyClicked(nil)
    let after = pasteboard.changeCount
    row("L11", disabled && status == "framejob-mcp is missing from this copy of Frame Job." && before == after,
        "disabled \(disabled); status \"\(status)\"; probe changeCount \(before) → \(after)")
}

// MARK: - L12 the Playback pane (G-38)

do {
    let pane = controller.playbackPane
    var notes: [String] = []
    let views = pane.arrangedSubviews
    var headed = false
    if views.count == 2, let header = views[0] as? NSStackView {
        let parts = header.arrangedSubviews
        headed = parts.count == 2 && parts[0] === pane.headingLabel && parts[1] === pane.infoButton
            && pane.headingLabel.stringValue == "Playback"
    }
    let rowViews = (views.count == 2 ? (views[1] as? NSStackView)?.arrangedSubviews : nil) ?? []
    let rowOK = rowViews.count == 5 && rowViews[0] === pane.backgroundBox
        && rowViews[2] === pane.delayField && rowViews[3] === pane.delayStepper
        && rowViews[4] === pane.secondsLabel
        && (rowViews[1] as? NSTextField)?.stringValue == "Start after"
        && pane.secondsLabel.stringValue == "seconds"
    let initial = pane.backgroundBox.title == "Background render" && pane.backgroundBox.state == .on
        && pane.delayField.stringValue == "5" && pane.delayField.isEnabled
        && pane.delayStepper.minValue == 1 && pane.delayStepper.maxValue == 60
        && pane.delayStepper.isEnabled
    notes.append("header \(headed); row \(rowOK) (\(rowViews.count) views); box "
        + "\"\(pane.backgroundBox.title)\" \(pane.backgroundBox.state == .on ? "on" : "off"), field "
        + "\"\(pane.delayField.stringValue)\", stepper \(pane.delayStepper.minValue)–"
        + "\(pane.delayStepper.maxValue); initial \(initial)")

    pane.backgroundBox.state = .off
    pane.backgroundToggled(nil)
    let unticked = suite.object(forKey: "FrameJobBackgroundRender") as? Bool == false
        && !pane.delayField.isEnabled && !pane.delayStepper.isEnabled
    notes.append("untick: stored \(suite.object(forKey: "FrameJobBackgroundRender") ?? "nil"), field "
        + "enabled \(pane.delayField.isEnabled), stepper enabled \(pane.delayStepper.isEnabled)")

    let before = suite.dictionaryRepresentation().filter { $0.key.hasPrefix("FrameJobBackgroundRender") }
        .mapValues { "\($0)" }
    pane.delayField.stringValue = "0"
    pane.delayChanged(nil)
    let after = suite.dictionaryRepresentation().filter { $0.key.hasPrefix("FrameJobBackgroundRender") }
        .mapValues { "\($0)" }
    let refused = before == after && pane.delayField.stringValue == "5"
    notes.append("\"0\": suite \(before) → \(after), field \"\(pane.delayField.stringValue)\"")

    pane.delayField.stringValue = "12"
    pane.delayChanged(nil)
    let twelve = suite.object(forKey: "FrameJobBackgroundRenderDelay") as? Int == 12
        && pane.delayStepper.integerValue == 12
    notes.append("\"12\": stored \(suite.object(forKey: "FrameJobBackgroundRenderDelay") ?? "nil"), "
        + "stepper \(pane.delayStepper.integerValue)")

    pane.delayStepper.integerValue += Int(pane.delayStepper.increment)
    pane.delayStepped(nil)
    let thirteen = suite.object(forKey: "FrameJobBackgroundRenderDelay") as? Int == 13
        && pane.delayField.stringValue == "13"
    notes.append("step up: stored \(suite.object(forKey: "FrameJobBackgroundRenderDelay") ?? "nil"), "
        + "field \"\(pane.delayField.stringValue)\"")
    row("L12", headed && rowOK && initial && unticked && refused && twelve && thirteen,
        notes.joined(separator: "; "))
}

// MARK: - L13 the window fits its screen (G-38, fix pass 1)

do {
    let fitted = SettingsWindowController(
        store: { MemoryStore() }, assistantStore: { MemoryStore() }, defaults: suite,
        environment: [:], spendFolder: { absentSpend })
    var good = false
    var detail = "no window or no document view"
    if let window = fitted.window, let document = fitted.scroll.documentView {
        fitted.fitScreen(NSRect(x: 0, y: 0, width: 1728, height: 3000))
        window.contentView?.layoutSubtreeIfNeeded()
        let full = document.frame.height
        let tallScroll = fitted.scroll.frame.height
        let tallWidth = document.frame.width
        let uncapped = full > 0 && abs(tallScroll - full) < 0.5
        let short = NSRect(x: 0, y: 0, width: 1440, height: 875)
        fitted.fitScreen(short)
        window.contentView?.layoutSubtreeIfNeeded()
        let frame = window.frame
        let inside = frame.minY >= short.minY - 0.5 && frame.maxY <= short.maxY + 0.5
        let clipHeight = fitted.scroll.contentView.bounds.height
        let scrolls = document.frame.height > clipHeight + 0.5
        let last = fitted.content.arrangedSubviews.last === fitted.playbackPane
            && fitted.playbackPane.isDescendant(of: document)
        good = uncapped && inside && scrolls && last
        detail = "3000 pt screen: document \(full), scroll \(tallScroll) (equal \(uncapped)), "
            + "document width \(tallWidth) then \(document.frame.width), scroller style "
            + "\(fitted.scroll.scrollerStyle == .legacy ? "legacy" : "overlay"); "
            + "1440 × 875 screen: window \(frame) inside \(inside), document "
            + "\(document.frame.height) over clip \(clipHeight) (scrolls \(scrolls)); playback "
            + "last in the document \(last)"
    }
    row("L13", good, detail)
}

UserDefaults().removePersistentDomain(forName: suiteName)
finish()
