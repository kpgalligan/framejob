// Road map 13 P4 — the spend UI probe (spec §11 P-4, P-7).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` —
// `assistant_tab_proof.py`'s `build_probe` swiftc line, `-D FRAMEJOB_DEV_TOOLS` —
// by `spend_ui_proof.py`, which runs it with `TZ=America/Los_Angeles` (so a
// month taken in the local zone would differ from UTC's at both edges) and its
// scratch folder as the first argument. Every spend folder here is inside the
// scratch folder or absent; nothing reads the person's ledger (P-5).
//
//   spend_ui_probe <scratch folder>
//
// Prints exactly one stdout line:
//   ANSWER {"rows":[{"id","ok","detail"}]}
//
//   M1  the fold over a fixture ledger, September 2026 UTC
//   M2  every Settings sentence and `amount`, exactly
//   M3  `month` and `title` at both edges of a month
//   C1  the transcript's conversation sum, its figures, and its resets
//   C2  `AssistantView.reload` / `apply` → `assistant.spend`'s text and tooltip
//   C3  Settings' pane in a window: no folder, an absent ledger, a fixture
//       ledger read off main, and a recorded line that keeps the shown
//       sentence until the new one answers
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

var rows: [[String: Any]] = []

func row(_ id: String, _ problems: [String], _ detail: String) {
    rows.append([
        "id": id, "ok": problems.isEmpty,
        "detail": String((problems.isEmpty ? detail : problems.joined(separator: "; ")).prefix(2000)),
    ])
}

func check(_ problems: inout [String], _ got: Any?, _ want: Any?, _ what: String) {
    let a = got.map { "\($0)" } ?? "nil"
    let b = want.map { "\($0)" } ?? "nil"
    if a != b { problems.append("\(what): got \(a), expected \(b)") }
}

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

/// Spins until `label` reads `want` or `seconds` pass; answers what it read.
func waitFor(_ label: NSTextField, _ want: String, within seconds: Double) -> String {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline && label.stringValue != want {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    return label.stringValue
}

func utc(_ text: String) -> Date {
    AssistantSpend.instant(text) ?? Date(timeIntervalSince1970: 0)
}

func cost(_ kind: String, dollars: Double = 0, detail: String = "no price") -> [String: Any] {
    let price: [String: Any] =
        kind == "dollars"
        ? ["kind": "dollars", "dollars": dollars, "rows": ["claude-opus-5-5"]]
        : ["kind": "unknown", "cause": "model", "detail": detail]
    return [
        "type": "cost", "model": "claude-opus-5-5",
        "usage": ["input_tokens": 100, "output_tokens": 10], "cost": price,
        "prices": ["kind": "bundled", "as_of": "2026-09-28T06:07:45Z"],
    ]
}

func find(_ identifier: String, in view: NSView) -> NSTextField? {
    if let field = view as? NSTextField, field.accessibilityIdentifier() == identifier {
        return field
    }
    for sub in view.subviews {
        if let found = find(identifier, in: sub) { return found }
    }
    return nil
}

let scratch = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : NSTemporaryDirectory(), isDirectory: true)
let september = AssistantSpendMonth.month(containing: utc("2026-09-15T12:00:00Z"))

// M1 — the fold.
do {
    var p: [String] = []
    let lines = [
        #"{"time":"2026-09-01T00:00:00Z","service":"anthropic","dollars":0.5}"#,
        #"{"time":"2026-09-30T23:59:59Z","service":"anthropic","dollars":0.25}"#,
        #"{"time":"2026-10-01T00:00:00Z","service":"anthropic","dollars":100}"#,
        #"{"time":"2026-08-31T23:59:59Z","service":"anthropic","dollars":100}"#,
        #"{"time":"2026-09-15T12:00:00.123Z","service":"anthropic","dollars":0.125}"#,
        #"{"time":"2026-09-10T00:00:00Z","service":"anthropic","dollars":null}"#,
        #"{"time":"2026-09-10T00:00:00Z","service":"anthropic","dollars":true}"#,
        #"{"time":"2026-09-10T00:00:00Z","serv"#,
        #"[]"#,
        #"{"time":"yesterday","service":"anthropic","dollars":1}"#,
        #"{"time":"2026-09-10T00:00:00Z","service":"assemblyai","dollars":9}"#,
        "",
        "   ",
    ]
    let data = Data((lines.joined(separator: "\n") + "\n").utf8)
    let got = AssistantSpendMonth.fold(data, month: september)
    check(&p, got.dollars, 0.875, "dollars")
    check(&p, got.priced, 3, "priced")
    check(&p, got.unpriced, 2, "unpriced")
    check(&p, got.unreadable, 3, "unreadable")
    check(&p, AssistantSpendMonth.fold(Data(), month: september), AssistantSpendMonth.Summary(),
          "empty ledger")
    row("M1", p, "\(lines.count) lines over September 2026 UTC → dollars \(got.dollars), "
        + "priced \(got.priced), unpriced \(got.unpriced), unreadable \(got.unreadable)")
}

// M2 — the sentences and `amount`.
do {
    var p: [String] = []
    typealias S = AssistantSpendMonth.Summary
    let t = "September 2026 (UTC)"
    let cases: [(AssistantSpendMonth.Reading, String)] = [
        (.noLedger, "This launch keeps no spend ledger."),
        (.reading, "Reading the spend ledger…"),
        (.summary(S()), "Nothing recorded in \(t)."),
        (.summary(S(dollars: 0, priced: 0, unpriced: 0, unreadable: 1)),
         "Nothing recorded in \(t). 1 ledger line could not be read."),
        (.summary(S(dollars: 0.5, priced: 1, unpriced: 0, unreadable: 0)),
         "\(t): $0.50 over 1 response."),
        (.summary(S(dollars: 1.25, priced: 3, unpriced: 0, unreadable: 0)),
         "\(t): $1.25 over 3 responses."),
        (.summary(S(dollars: 0.001, priced: 2, unpriced: 0, unreadable: 2)),
         "\(t): under $0.01 over 2 responses. 2 ledger lines could not be read."),
        (.summary(S(dollars: 0.75, priced: 3, unpriced: 2, unreadable: 3)),
         "\(t): 5 responses; 2 could not be priced, the rest came to $0.75. 3 ledger lines "
            + "could not be read."),
        (.summary(S(dollars: 0.75, priced: 1, unpriced: 1, unreadable: 0)),
         "\(t): 2 responses; 1 could not be priced, the rest came to $0.75."),
        (.summary(S(dollars: 0, priced: 0, unpriced: 1, unreadable: 0)),
         "\(t): 1 response; none could be priced."),
        (.summary(S(dollars: 0, priced: 0, unpriced: 2, unreadable: 1)),
         "\(t): 2 responses; none could be priced. 1 ledger line could not be read."),
        (.failed("The file couldn’t be opened."),
         "The spend ledger could not be read: The file couldn’t be opened."),
        (.failed("permission denied"), "The spend ledger could not be read: permission denied."),
    ]
    for (reading, want) in cases {
        check(&p, AssistantSpendMonth.sentence(reading, month: september), want, "\(reading)")
    }
    let amounts: [(Double, String)] = [
        (0, "$0.00"), (0.001, "under $0.01"), (0.0049, "under $0.01"), (0.006, "$0.01"),
        (0.75, "$0.75"), (12.3456, "$12.35"), (1234.5, "$1234.50"),
    ]
    for (dollars, want) in amounts {
        check(&p, AssistantSpendMonth.amount(dollars), want, "amount \(dollars)")
    }
    check(&p, AssistantSpendMonth.note,
          "Frame Job's own estimate at LiteLLM prices, from its spend ledger. The Anthropic "
            + "Console shows what your account was billed.", "note")
    row("M2", p, "\(cases.count) sentences and \(amounts.count) amounts exactly, and the note")
}

// M3 — the month and its title at the edges.
do {
    var p: [String] = []
    let first = AssistantSpendMonth.month(containing: utc("2026-09-01T00:00:00Z"))
    let last = AssistantSpendMonth.month(containing: utc("2026-09-30T23:59:59Z"))
    let before = AssistantSpendMonth.month(containing: utc("2026-08-31T23:59:59Z"))
    let after = AssistantSpendMonth.month(containing: utc("2026-10-01T00:00:00Z"))
    for (name, month) in [("first second", first), ("last second", last)] {
        check(&p, month.start, utc("2026-09-01T00:00:00Z"), "\(name): start")
        check(&p, month.end, utc("2026-10-01T00:00:00Z"), "\(name): end")
        check(&p, AssistantSpendMonth.title(month), "September 2026 (UTC)", "\(name): title")
    }
    check(&p, before.start, utc("2026-08-01T00:00:00Z"), "August: start")
    check(&p, AssistantSpendMonth.title(before), "August 2026 (UTC)", "August: title")
    check(&p, after.start, utc("2026-10-01T00:00:00Z"), "October: start")
    check(&p, AssistantSpendMonth.title(after), "October 2026 (UTC)", "October: title")
    check(&p, TimeZone.current.identifier, "America/Los_Angeles", "the probe's local zone")
    row("M3", p, "2026-09-01T00:00:00Z and 2026-09-30T23:59:59Z → September 2026 (UTC), "
        + "[\(first.start), \(first.end)); the seconds either side → August and October, with "
        + "the local zone \(TimeZone.current.identifier)")
}

// C1 — the transcript's conversation cost.
do {
    var p: [String] = []
    let transcript = AssistantTranscript()
    var changes: [AssistantTranscriptChange] = []
    transcript.onChange = { changes.append($0) }
    check(&p, transcript.conversationCost.figure, "Nothing yet", "fresh")
    transcript.take(["type": "turn_started"])
    transcript.take(cost("dollars", dollars: 0.0006))
    transcript.take(cost("dollars", dollars: 0.0004))
    transcript.take(["type": "turn_finished"])
    transcript.take(["type": "turn_started"])
    transcript.take(cost("dollars", dollars: 0.001))
    transcript.take(["type": "turn_finished"])
    check(&p, transcript.conversationCost.figure, "$0.0020 · Frame Job's estimate", "two turns")
    let costChanges = changes.compactMap { change -> String? in
        if case .conversationCost(let c) = change { return c.figure }
        return nil
    }
    check(&p, costChanges, ["$0.0006 · Frame Job's estimate", "$0.0010 · Frame Job's estimate",
                            "$0.0020 · Frame Job's estimate"], "one change per cost event")
    changes = []
    transcript.clear()
    check(&p, transcript.conversationCost.figure, "Nothing yet", "after clear")
    check(&p, changes.count, 3, "clear's change count")
    if changes.count == 3 {
        check(&p, changes[0] == .cleared, true, "clear: .cleared first")
        check(&p, changes[1] == .conversationCost(AssistantTurnCost()), true,
              "clear: .conversationCost second")
        if case .usage = changes[2] {} else { p.append("clear: the last change is not .usage") }
    }

    transcript.take(cost("unknown", detail: "not in the table"))
    check(&p, transcript.conversationCost.figure, "unknown · Frame Job's estimate", "unknown alone")
    transcript.take(cost("dollars", dollars: 0.0006))
    check(&p, transcript.conversationCost.figure, "at least $0.0006 · Frame Job's estimate",
          "unknown then priced")
    changes = []
    transcript.endConversation(note: "C1 ended.")
    check(&p, transcript.conversationCost.figure, "Nothing yet", "after endConversation")
    check(&p, changes.count, 3, "endConversation's change count")
    if changes.count == 3 {
        check(&p, changes[0] == .appended(AssistantEntry(kind: .meta, text: "C1 ended.")), true,
              "endConversation: the note first")
        check(&p, changes[1] == .conversationCost(AssistantTurnCost()), true,
              "endConversation: .conversationCost second")
        if case .usage = changes[2] {} else {
            p.append("endConversation: the last change is not .usage")
        }
    }

    var tiny = AssistantTurnCost()
    tiny.add(cost("dollars", dollars: 0.00002))
    check(&p, tiny.figure, "under $0.0001 · Frame Job's estimate", "tiny priced")
    tiny.add(cost("unknown"))
    check(&p, tiny.figure, "unknown · Frame Job's estimate", "tiny priced then unknown")
    var edge = AssistantTurnCost()
    edge.add(cost("dollars", dollars: 0.00005))
    edge.add(cost("unknown"))
    check(&p, edge.figure, "at least $0.0001 · Frame Job's estimate", "at the 0.00005 edge")
    check(&p, AssistantTurnCost.figureTooltip,
          "What this conversation's responses cost at LiteLLM prices, as Frame Job estimates it. "
            + "The Anthropic Console shows what your account was billed.", "tooltip")
    row("C1", p, "Nothing yet → $0.0020 over two turns, one change per cost; clear and "
        + "endConversation emit .conversationCost before .usage and reset to Nothing yet; "
        + "unknown, at least, under $0.0001")
}

// C2 — the tab's Spend row.
do {
    var p: [String] = []
    let view = AssistantView()
    view.frame = NSRect(x: 0, y: 0, width: 304, height: 600)
    view.layoutSubtreeIfNeeded()
    let label = find("assistant.spend", in: view)
    if label == nil { p.append("no assistant.spend label") }
    var cost1 = AssistantTurnCost()
    cost1.add(cost("dollars", dollars: 0.0123))
    view.reload([], usage: AssistantContextUsage(), cost: AssistantTurnCost())
    check(&p, label?.stringValue, "Nothing yet", "reload with no cost")
    view.reload([], usage: AssistantContextUsage(), cost: cost1)
    check(&p, label?.stringValue, "$0.0123 · Frame Job's estimate", "reload with a cost")
    var cost2 = cost1
    cost2.add(cost("unknown"))
    view.apply(.conversationCost(cost2))
    check(&p, label?.stringValue, "at least $0.0123 · Frame Job's estimate", "apply")
    view.apply(.usage(AssistantContextUsage(used: 10, limit: 100, reported: true)))
    check(&p, label?.stringValue, "at least $0.0123 · Frame Job's estimate", "a usage change")
    view.apply(.cleared)
    view.apply(.conversationCost(AssistantTurnCost()))
    check(&p, label?.stringValue, "Nothing yet", "reset")
    check(&p, label?.toolTip, AssistantTurnCost.figureTooltip, "tooltip")
    row("C2", p, "assistant.spend: Nothing yet → $0.0123 → at least $0.0123 → Nothing yet; "
        + "tooltip \(label?.toolTip ?? "nil")")
}

// C3 — Settings' pane in a window.
do {
    var p: [String] = []
    func pane(_ folder: URL?) -> (AssistantSettingsPane, NSWindow) {
        let pane = AssistantSettingsPane(
            store: { MemoryStore() }, defaults: UserDefaults(), environment: [:],
            spendFolder: { folder })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = pane
        window.orderFrontRegardless()
        return (pane, window)
    }
    let now = Date()
    let title = AssistantSpendMonth.title(AssistantSpendMonth.month(containing: now))

    let (noFolder, w1) = pane(nil)
    check(&p, noFolder.spendLabel.stringValue, "", "init reads nothing")
    noFolder.refreshSpend()
    check(&p, noFolder.spendLabel.stringValue, "This launch keeps no spend ledger.", "no folder")
    check(&p, noFolder.spendNoteLabel.stringValue,
          "Frame Job's own estimate at LiteLLM prices, from its spend ledger. The Anthropic "
            + "Console shows what your account was billed.", "the note")
    w1.orderOut(nil)

    let absent = scratch.appendingPathComponent("c3-absent", isDirectory: true)
    try? FileManager.default.removeItem(at: absent)
    let (absentPane, w2) = pane(absent)
    absentPane.refreshSpend()
    check(&p, absentPane.spendLabel.stringValue, "Nothing recorded in \(title).", "absent ledger")
    check(&p, FileManager.default.fileExists(atPath: absent.path), false,
          "the absent folder is still absent")
    w2.orderOut(nil)

    let folder = scratch.appendingPathComponent("c3", isDirectory: true)
    try? FileManager.default.removeItem(at: folder)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let stamp = ISO8601DateFormatter().string(from: now)
    let seed = [
        #"{"time":"\#(stamp)","service":"anthropic","dollars":0.5}"#,
        #"{"time":"\#(stamp)","service":"anthropic","dollars":0.25}"#,
        #"{"time":"\#(stamp)","service":"anthropic","dollars":null}"#,
    ].joined(separator: "\n") + "\n"
    FileManager.default.createFile(
        atPath: folder.appendingPathComponent(AssistantSpend.ledgerName).path,
        contents: Data(seed.utf8))
    let (ledgerPane, w3) = pane(folder)
    check(&p, w3.isVisible, true, "the window is visible")
    ledgerPane.refreshSpend()
    check(&p, ledgerPane.spendLabel.stringValue, "Reading the spend ledger…", "reading at once")
    let first = "\(title): 3 responses; 1 could not be priced, the rest came to $0.75."
    check(&p, waitFor(ledgerPane.spendLabel, first, within: 5), first, "the fold within 5 s")
    let recorded = AssistantSpend.record(cost("dollars", dollars: 0.0625), in: folder)
    check(&p, recorded, nil as String?, "record")
    check(&p, ledgerPane.spendLabel.stringValue, first, "synchronously after record")
    let second = "\(title): 4 responses; 1 could not be priced, the rest came to $0.81."
    check(&p, waitFor(ledgerPane.spendLabel, second, within: 5), second,
          "the new sentence within 5 s")
    w3.orderOut(nil)
    row("C3", p, "no folder → no ledger; absent → Nothing recorded, still absent; ledger → "
        + "Reading…, then \(first); record → unchanged, then \(second)")
}

let answer = ["rows": rows]
let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])) ?? Data()
print("ANSWER " + (String(data: data, encoding: .utf8) ?? "{}"))
