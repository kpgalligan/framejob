// Road map 12 A3 — the prompt texts' probe (spec §11 AI-7, AI-9, AI-15).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line, `-D REELCUT_DEV_TOOLS` — by
// `assistant_prompt_proof.py`, as `assistant_lane_probe.swift` is.
//
//   assistant_prompt_probe <work-dir>
//
// Prints exactly one stdout line:
//   ANSWER {"rows":[{"id","ok","detail"}],"texts":{"system","search_guide",
//          "compaction_instructions","core_tools"}}
//
// The rows check the texts in `AssistantPrompt.swift` against the code that
// decides what they say, so a text cannot drift from the app silently:
//
//   F1  every backticked token is a tool, or a path of argument names and
//       `get_project` keys; no snake_case word outside backticks but the
//       context tag; no withheld tool anywhere
//   F2  the timescale: `ReelTime.perSecond` is `RC_TIMESCALE`, and the system
//       prompt and `get_project`'s note both say it
//   F3  the shared id kinds: each backticked, and in the fixture each an
//       array of objects with integer ids, all distinct and below `next_id`
//   F4  the search topics and the core tools cover the assistant's catalog
//       exactly, once each, and the guide shows every topic's words
//   F5  the ask-first and conditional withheld rows of
//       `AssistantToolTable.rows` are named in the system prompt
//   F6  no blank line in any text; the length bounds
//   F7  the live context block, exactly, and `AssistantPrompt.message`; and
//       `checkLiterals` (#158): every `none` and `null` in the three texts is
//       in double quotes, and the system prompt names the scope-less value
//       as the block writes it, `("<word>": the timeline)`
//   F8  (#158) `checkF8`: every ask-first row's reason is a write ("It
//       writes " or "It copies "), there is at least one, and the system
//       prompt says "These tools write files, so each asks the person first: "
//   M1–M6  each checker FAILS on a mutated copy of its input (M5: `"none"`
//       unquoted in the system prompt; M6: an ask-first row that spends money
//       rather than writing)
//
// The fixture is an untitled document edited through `AgentLane.submit`
// pinned to it, as the assistant's session calls: two tracks, a text clip
// with an action, two shapes (the second nested), a marker and an image.
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

let argv = CommandLine.arguments
let work = argv.count > 1 ? argv[1] : NSTemporaryDirectory()
AgentLane.prepareAtLaunch()

var rows: [[String: Any]] = []

func row(_ id: String, _ ok: Bool, _ detail: String) {
    rows.append(["id": id, "ok": ok, "detail": String(detail.prefix(1500))])
}

func answer() -> Never {
    let texts: [String: Any] = [
        "system": AssistantPrompt.system, "search_guide": AssistantPrompt.searchGuide,
        "compaction_instructions": AssistantPrompt.compactionInstructions,
        "core_tools": AssistantPrompt.coreTools,
    ]
    let body: [String: Any] = ["rows": rows, "texts": texts]
    let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    print("ANSWER " + (String(data: data, encoding: .utf8) ?? "{}"))
    fflush(stdout)
    exit(0)
}

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

func json(_ object: [String: Any]) -> String {
    String(data: (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8),
           encoding: .utf8) ?? "{}"
}

/// A result crossing from the lane to main.
final class Pending {
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

/// `submit`, pinned to `document`, from main, as the session calls it; every
/// ask-first question is declined (the fixture asks none).
func call(_ tool: String, _ arguments: [String: Any], _ document: ProjectDocument)
    -> (ok: Bool, text: String)
{
    let pending = Pending()
    AgentLane.shared.submit(
        tool: tool, argumentsJSON: json(arguments), document: document,
        askFirst: { _, reply in reply(false) }, completion: { pending.set($0) })
    let deadline = Date().addingTimeInterval(30)
    while pending.value == nil && Date() < deadline { spin(0.02) }
    guard let result = pending.value,
        let object = (try? JSONSerialization.jsonObject(with: Data(result.utf8)))
            as? [String: Any]
    else { return (false, "no answer") }
    let text = ((object["content"] as? [[String: Any]]) ?? [])
        .compactMap { $0["text"] as? String }.joined(separator: " ")
    return (object["isError"] as? Bool != true, text)
}

func object(_ text: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
}

func intValue(_ any: Any?) -> Int? {
    guard let number = any as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
        return nil
    }
    return number.intValue
}

// MARK: - The fixture

var fixtureProblems: [String] = []
var fixtureDocument: ProjectDocument?
var fixture: [String: Any] = [:]

func buildFixture() {
    let document = ProjectDocument()
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(0.5)
    fixtureDocument = document
    let png = (work as NSString).appendingPathComponent("probe.png")
    if let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0),
        let data = rep.representation(using: .png, properties: [:])
    {
        try? data.write(to: URL(fileURLWithPath: png))
    }
    func nextID() -> Int {
        let got = call("get_project", [:], document)
        return intValue((object(got.text)["project"] as? [String: Any])?["next_id"]) ?? -1
    }
    func step(_ tool: String, _ arguments: [String: Any]) -> Int {
        let id = nextID()
        let got = call(tool, arguments, document)
        if !got.ok { fixtureProblems.append("\(tool): \(got.text.prefix(200))") }
        return id
    }
    let titles = step("add_track", ["name": "Titles"])
    let shapes = step("add_track", ["name": "Shapes"])
    let title = step(
        "add_text_clip",
        ["track": titles, "at": 0, "duration": 1_200_000, "text": ["content": "Welcome"]])
    _ = step("add_shape_clip", ["track": shapes, "at": 0, "duration": 1_200_000])
    let second = step("add_shape_clip", ["track": shapes, "at": 1_200_000, "duration": 1_200_000])
    _ = step("add_action", ["clip": title, "at": 0, "duration": 600_000])
    _ = step("add_marker", ["at": 600_000, "name": "Probe"])
    _ = step(
        "add_media",
        ["descriptor": ["path": png, "kind": "image", "width": 64, "height": 64]])
    _ = step("nest", ["clips": [second]])
    let got = call("get_project", [:], document)
    if !got.ok { fixtureProblems.append("get_project: \(got.text.prefix(200))") }
    fixture = object(got.text)
}

// MARK: - What the texts may name

func assistantCatalog() -> [[String: Any]] {
    guard let catalog = AgentServer.shared.preparedCatalog,
        let tools = (try? JSONSerialization.jsonObject(with: Data(catalog.utf8)))
            as? [[String: Any]]
    else { return [] }
    return AssistantToolTable.assistantCatalog(tools)
}

let catalog = assistantCatalog()
let toolNames = Set(catalog.compactMap { $0["name"] as? String })

/// Every property name at any depth of `schema`.
func argumentNames(_ schema: Any, into names: inout Set<String>) {
    if let dict = schema as? [String: Any] {
        if let properties = dict["properties"] as? [String: Any] {
            names.formUnion(properties.keys)
        }
        for value in dict.values { argumentNames(value, into: &names) }
    } else if let array = schema as? [Any] {
        for value in array { argumentNames(value, into: &names) }
    }
}

/// Every key at any depth of `value`.
func keys(_ value: Any, into names: inout Set<String>) {
    if let dict = value as? [String: Any] {
        names.formUnion(dict.keys)
        for inner in dict.values { keys(inner, into: &names) }
    } else if let array = value as? [Any] {
        for inner in array { keys(inner, into: &names) }
    }
}

func matches(_ pattern: String, _ text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).compactMap {
        Range($0.range, in: text).map { String(text[$0]) }
    }
}

func wholeMatch(_ pattern: String, _ text: String) -> Bool {
    text.range(of: "^" + pattern + "$", options: .regularExpression) != nil
}

var vocabulary = Set<String>()

let withheldNames: Set<String> = AgentServer.devToolNames.union(
    AssistantToolTable.rows.filter { $0.rule == .withheld && $0.onlyWith == nil }.map(\.tool))

// MARK: - The checkers, each a function of its inputs

typealias Texts = (system: String, guide: String, compaction: String)

func checkF1(_ texts: Texts) -> (Bool, String) {
    let pathPattern = #"[a-z][a-z0-9_]*(\[[0-9]+\])?(\.[a-z][a-z0-9_]*)*"#
    var problems: [String] = []
    var count = 0
    for (label, text) in [("system", texts.system), ("guide", texts.guide),
                          ("compaction", texts.compaction)] {
        for quoted in matches("`[^`]*`", text) {
            count += 1
            let token = String(quoted.dropFirst().dropLast())
            guard wholeMatch(pathPattern, token) else {
                problems.append("\(label): `\(token)` is not an identifier path")
                continue
            }
            if toolNames.contains(token) { continue }
            let segments = token.split(separator: ".").map {
                String($0.split(separator: "[").first ?? "")
            }
            let unknown = segments.filter { !vocabulary.contains($0) }
            if !unknown.isEmpty {
                problems.append("\(label): `\(token)` names \(unknown), no tool, argument or key")
            }
        }
        var bare = text.replacingOccurrences(
            of: "`[^`]*`", with: " ", options: .regularExpression)
        bare = bare.replacingOccurrences(of: "<\(AssistantLiveContext.tag)>", with: " ")
        for word in matches("[a-z0-9]+(_[a-z0-9]+)+", bare) {
            problems.append("\(label): \(word) outside backticks")
        }
        let words = Set(matches("[A-Za-z0-9_]+", text))
        for name in withheldNames.intersection(words).sorted() {
            problems.append("\(label): names the withheld \(name)")
        }
    }
    return (problems.isEmpty && count > 0,
            "\(count) backticked tokens against \(toolNames.count) tools and "
                + "\(vocabulary.count) names; \(withheldNames.count) withheld names"
                + (problems.isEmpty ? "" : "; " + problems.prefix(8).joined(separator: "; ")))
}

func checkF2(_ system: String, note: String) -> (Bool, String) {
    let digits = String(RC_TIMESCALE)
    let same = ReelTime.perSecond == Ticks(RC_TIMESCALE)
    let inSystem = system.contains(digits)
    let inNote = note.contains(digits)
    return (same && inSystem && inNote,
            "ReelTime.perSecond \(ReelTime.perSecond) == RC_TIMESCALE \(digits): \(same); "
                + "in system \(inSystem); in get_project's note \(inNote)")
}

func checkF4(_ topics: [(words: String, tools: [String])], guide: String) -> (Bool, String) {
    let core = AssistantPrompt.coreTools
    var problems: [String] = []
    var seen = Set<String>()
    for topic in topics {
        for tool in topic.tools {
            if seen.contains(tool) { problems.append("\(tool) twice") }
            seen.insert(tool)
        }
        if !guide.contains(topic.words) { problems.append("words \"\(topic.words)\" not in guide") }
    }
    let overlap = seen.intersection(core)
    if !overlap.isEmpty { problems.append("topics hold core tools \(overlap.sorted())") }
    let union = seen.union(core)
    let missing = toolNames.subtracting(union).sorted()
    let extra = union.subtracting(toolNames).sorted()
    if !missing.isEmpty { problems.append("no topic for \(missing)") }
    if !extra.isEmpty { problems.append("not in the catalog \(extra)") }
    for tool in core where !guide.contains("`\(tool)`") {
        problems.append("core `\(tool)` not in guide")
    }
    return (problems.isEmpty && !toolNames.isEmpty,
            "\(topics.count) topics, \(seen.count) tools + \(core.count) core against "
                + "\(toolNames.count) in the assistant's catalog"
                + (problems.isEmpty ? "" : "; " + problems.prefix(8).joined(separator: "; ")))
}

/// (#158) Every `none`/`null` in the three texts has `"` on both sides, and
/// `system` holds `("<noScope>": the timeline)`.
func checkLiterals(_ texts: Texts, noScope: String) -> (Bool, String) {
    var problems: [String] = []
    var count = 0
    let pattern = try? NSRegularExpression(pattern: #"\b(none|null)\b"#)
    for (label, text) in [("system", texts.system), ("guide", texts.guide),
                          ("compaction", texts.compaction)] {
        let ns = text as NSString
        for match in pattern?.matches(in: text, range: NSRange(location: 0, length: ns.length))
            ?? [] {
            count += 1
            let range = match.range
            let before = range.location > 0
                ? ns.substring(with: NSRange(location: range.location - 1, length: 1)) : ""
            let end = range.location + range.length
            let after = end < ns.length ? ns.substring(with: NSRange(location: end, length: 1)) : ""
            if before != "\"" || after != "\"" {
                let from = max(0, range.location - 12)
                let context = ns.substring(
                    with: NSRange(location: from, length: min(ns.length, end + 12) - from))
                problems.append("\(label): \(ns.substring(with: range)) unquoted in \"\(context)\"")
            }
        }
    }
    let scopeLine = "(\"\(noScope)\": the timeline)"
    if !texts.system.contains(scopeLine) { problems.append("system lacks \(scopeLine)") }
    return (problems.isEmpty && count > 0 && !noScope.isEmpty,
            "\(count) none/null literals\(problems.isEmpty ? ", each quoted" : ""); the no-scope "
                + "word \"\(noScope)\" as "
                + "\(scopeLine)"
                + (problems.isEmpty ? "" : "; " + problems.prefix(6).joined(separator: "; ")))
}

/// The first word after `scope: ` in a scope-less live context block.
func noScopeWord() -> String {
    let text = AssistantLiveContext(name: "x", path: nil, scope: nil, playhead: 0, selection: [])
        .text
    guard let range = text.range(of: "scope: ") else { return "" }
    return String(text[range.upperBound...].prefix { !$0.isWhitespace })
}

/// (#158) "These tools write files": each ask-first row's reason is a write.
func checkF8(_ rows: [AssistantToolRow], system: String) -> (Bool, String) {
    let claim = "These tools write files, so each asks the person first: "
    var problems: [String] = []
    let asking = rows.filter { $0.rule == .askFirst }
    if asking.isEmpty { problems.append("no ask-first row") }
    for entry in asking where !(entry.reason.hasPrefix("It writes ")
        || entry.reason.hasPrefix("It copies ")) {
        problems.append("\(entry.tool): \"\(entry.reason)\" is not a write")
    }
    if !system.contains(claim) { problems.append("system lacks \"\(claim)\"") }
    return (problems.isEmpty,
            "\(asking.count) ask-first rows (\(asking.map(\.tool)))"
                + (problems.isEmpty ? ", each reason a write; " : "; ")
                + "the claim in system \(system.contains(claim))"
                + (problems.isEmpty ? "" : "; " + problems.joined(separator: "; ")))
}

// MARK: - The rows

func rowF3() {
    let system = AssistantPrompt.system
    let project = fixture["project"] as? [String: Any] ?? [:]
    var problems: [String] = []
    for kind in AssistantPrompt.sharedIdKinds where !system.contains("`\(kind)`") {
        problems.append("`\(kind)` not in system")
    }
    var ids: [String: [Int]] = [:]
    func walk(_ value: Any, _ where_: String) {
        if let dict = value as? [String: Any] {
            for (key, inner) in dict {
                // A graphic's `clips` is a list of clip ids, not objects that own one.
                let idList = key == "clips" && where_.range(
                    of: #"\.graphics\[\d+\]$"#, options: .regularExpression) != nil
                if !idList, AssistantPrompt.sharedIdKinds.contains(key),
                    let array = inner as? [Any]
                {
                    for element in array {
                        guard let object = element as? [String: Any],
                            let id = intValue(object["id"])
                        else {
                            problems.append("\(where_).\(key) holds \(element), not an object "
                                + "with an integer id")
                            continue
                        }
                        ids[key, default: []].append(id)
                    }
                }
                walk(inner, "\(where_).\(key)")
            }
        } else if let array = value as? [Any] {
            for (index, inner) in array.enumerated() { walk(inner, "\(where_)[\(index)]") }
        }
    }
    walk(project, "project")
    for kind in AssistantPrompt.sharedIdKinds where (ids[kind] ?? []).isEmpty {
        problems.append("no \(kind) in the fixture")
    }
    let all = ids.values.flatMap { $0 }
    let next = intValue(project["next_id"]) ?? -1
    if Set(all).count != all.count { problems.append("ids repeat: \(all.sorted())") }
    if let high = all.max(), high >= next { problems.append("id \(high) ≥ next_id \(next)") }
    let counts = AssistantPrompt.sharedIdKinds.map { "\($0) \(ids[$0]?.count ?? 0)" }
    row("F3", problems.isEmpty && fixtureProblems.isEmpty,
        "\(counts.joined(separator: ", ")); \(all.count) ids, next_id \(next)"
            + (fixtureProblems.isEmpty ? "" : "; fixture: \(fixtureProblems)")
            + (problems.isEmpty ? "" : "; " + problems.prefix(8).joined(separator: "; ")))
}

func rowF5() {
    let system = AssistantPrompt.system
    var problems: [String] = []
    var named: [String] = []
    for entry in AssistantToolTable.rows {
        if entry.rule == .askFirst {
            named.append(entry.tool)
            if !system.contains("`\(entry.tool)`") { problems.append("`\(entry.tool)` missing") }
        } else if let only = entry.onlyWith {
            named.append("\(entry.tool) \(only.key) \"\(only.value)\"")
            for piece in ["`\(entry.tool)`", "`\(only.key)`", "\"\(only.value)\""]
            where !system.contains(piece) {
                problems.append("\(piece) missing")
            }
        }
    }
    row("F5", problems.isEmpty && !named.isEmpty,
        "named: \(named)" + (problems.isEmpty ? "" : "; " + problems.joined(separator: "; ")))
}

func rowF6() {
    let texts = [("system", AssistantPrompt.system, 6000),
                 ("guide", AssistantPrompt.searchGuide, 1500),
                 ("compaction", AssistantPrompt.compactionInstructions, 1000)]
    var problems: [String] = []
    for (label, text, bound) in texts {
        if text.isEmpty { problems.append("\(label) empty") }
        if text.contains("\n\n") { problems.append("\(label) holds a blank line") }
        if text.count > bound { problems.append("\(label) \(text.count) > \(bound)") }
    }
    row("F6", problems.isEmpty,
        texts.map { "\($0.0) \($0.1.count)/\($0.2)" }.joined(separator: ", ")
            + (problems.isEmpty ? "" : "; " + problems.joined(separator: "; ")))
}

func rowF7() {
    let samples: [(AssistantLiveContext, String)] = [
        (AssistantLiveContext(name: "Demo", path: "/tmp/Demo.reelcut", scope: 7,
                              playhead: 2_400_000, selection: [3, 12]),
         "<reelcut_context>\nname: Demo\npath: /tmp/Demo.reelcut\n"
            + "scope: 7 (a nest is open: ids and times are its own)\n"
            + "playhead: 2400000 (4.000 s)\nselection: 3, 12\n</reelcut_context>"),
        (AssistantLiveContext(name: "Demo", path: "/tmp/Demo.reelcut", scope: nil,
                              playhead: 0, selection: []),
         "<reelcut_context>\nname: Demo\npath: /tmp/Demo.reelcut\n"
            + "scope: none (the timeline is open)\n"
            + "playhead: 0 (0.000 s)\nselection: none\n</reelcut_context>"),
        (AssistantLiveContext(name: "Untitled", path: nil, scope: 4,
                              playhead: 1_234_567, selection: []),
         "<reelcut_context>\nname: Untitled\npath: none (never saved)\n"
            + "scope: 4 (a nest is open: ids and times are its own)\n"
            + "playhead: 1234567 (2.058 s)\nselection: none\n</reelcut_context>"),
        (AssistantLiveContext(name: "Untitled 2", path: nil, scope: nil,
                              playhead: 600_000, selection: [9]),
         "<reelcut_context>\nname: Untitled 2\npath: none (never saved)\n"
            + "scope: none (the timeline is open)\n"
            + "playhead: 600000 (1.000 s)\nselection: 9\n</reelcut_context>"),
    ]
    var problems: [String] = []
    for (index, (context, expected)) in samples.enumerated() where context.text != expected {
        problems.append("sample \(index + 1): \(context.text.debugDescription)")
    }
    let t = "Put a marker at 3 seconds."
    if let document = fixtureDocument {
        let wanted = AssistantLiveContext(document: document).text + "\n" + t
        if AssistantPrompt.message(t, document: document) != wanted {
            problems.append("message(document:) is not the block, a newline and the text")
        }
    } else {
        problems.append("no fixture document")
    }
    if AssistantPrompt.message(t, document: nil) != t { problems.append("message(nil) != text") }
    let labels = ["name", "path", "scope", "playhead", "selection"]
    let missing = labels.filter { fixture[$0] == nil }
    if !missing.isEmpty { problems.append("labels not keys of get_project: \(missing)") }
    let literals = checkLiterals(texts, noScope: noScopeWord())
    if !literals.0 { problems.append("literals: \(literals.1)") }
    row("F7", problems.isEmpty,
        "\(samples.count) samples exact, message() with and without a document, labels "
            + "\(labels) keys of get_project; \(literals.1)"
            + (problems.isEmpty ? "" : "; " + problems.prefix(6).joined(separator: "; ")))
}

try? FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
buildFixture()
argumentNames(catalog, into: &vocabulary)
keys(fixture, into: &vocabulary)

let texts: Texts = (AssistantPrompt.system, AssistantPrompt.searchGuide,
                    AssistantPrompt.compactionInstructions)
let note = fixture["note"] as? String ?? ""
let f1 = checkF1(texts)
row("F1", f1.0 && fixtureProblems.isEmpty && !catalog.isEmpty, f1.1)
let f2 = checkF2(texts.system, note: note)
row("F2", f2.0, f2.1)
rowF3()
let f4 = checkF4(AssistantPrompt.searchTopics, guide: texts.guide)
row("F4", f4.0, f4.1)
rowF5()
rowF6()
rowF7()
let f8 = checkF8(AssistantToolTable.rows, system: texts.system)
row("F8", f8.0, f8.1)

// The mutants: each checker must FAIL on its copy.
let m1 = checkF1((texts.system + " `add_markers`", texts.guide, texts.compaction))
row("M1", !m1.0, "system + \" `add_markers`\": F1 fails \(!m1.0) (\(m1.1))")
let m2 = checkF2(
    texts.system.replacingOccurrences(of: String(RC_TIMESCALE), with: "60000"), note: note)
row("M2", !m2.0, "timescale digits → 60000: F2 fails \(!m2.0) (\(m2.1))")
var dropped = AssistantPrompt.searchTopics
if !dropped.isEmpty, !dropped[0].tools.isEmpty { dropped[0].tools.removeLast() }
let m3 = checkF4(dropped, guide: texts.guide)
row("M3", !m3.0, "the first topic's last tool dropped: F4 fails \(!m3.0) (\(m3.1))")
let m4 = checkF1((texts.system + " record_screen", texts.guide, texts.compaction))
row("M4", !m4.0, "system + \" record_screen\": F1 fails \(!m4.0) (\(m4.1))")
let m5 = checkLiterals(
    (texts.system.replacingOccurrences(of: "\"none\"", with: "none"), texts.guide,
     texts.compaction), noScope: noScopeWord())
row("M5", !m5.0, "system's \"none\" unquoted: the literal check fails \(!m5.0) (\(m5.1))")
let m6 = checkF8(
    AssistantToolTable.rows + [AssistantToolRow(
        tool: "transcribe", rule: .askFirst, onlyWith: nil,
        reason: "It spends the person's money.")],
    system: texts.system)
row("M6", !m6.0, "an ask-first transcribe that spends money: F8 fails \(!m6.0) (\(m6.1))")

for document in AgentServer.shared.openProjects() { document.close() }
spin(0.2)
answer()
