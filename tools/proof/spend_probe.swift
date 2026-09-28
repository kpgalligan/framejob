// Road map 13 P2 — the spend probe (spec §11 P-2, P-4, P-5).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `assistant_tab_proof.py`'s `build_probe` swiftc line, `-D REELCUT_DEV_TOOLS` —
// by `spend_proof.py`, which runs it with its scratch folder as the first
// argument. It starts no app, opens no window and reads no defaults of its
// own: every row answers `AssistantSpend` or `AssistantTranscript` directly.
//
//   spend_probe <scratch folder>
//
// Prints exactly one stdout line:
//   ANSWER {"rows":[{"id","ok","detail"}]}
//
//   S1  the cost line's formats, and `day`
//   S2  the transcript sums a turn's `cost` events and resets
//   S3  the ledger line's whitelist
//   S4  `record`: two lines at 0600, a nested folder created, a file refused
//   S5  P-5's table over a `UserDefaults` answering the argument domain
import Foundation

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

func cost(
    _ kind: String, dollars: Double = 0, cause: String = "model", detail: String = "",
    source: String = "bundled", asOf: String = "2026-09-28T06:07:45Z", problem: String? = nil
) -> [String: Any] {
    var prices: [String: Any] = ["kind": source, "as_of": asOf]
    if let problem { prices["problem"] = problem }
    let price: [String: Any] =
        kind == "dollars"
        ? ["kind": "dollars", "dollars": dollars, "rows": ["claude-opus-5-5"]]
        : ["kind": "unknown", "cause": cause, "detail": detail]
    return [
        "type": "cost", "model": "claude-opus-5-5",
        "usage": ["input_tokens": 100, "output_tokens": 10], "cost": price, "prices": prices,
    ]
}

let tail = " · Reelcut's estimate at LiteLLM prices ("
let bundledAsOf = "2026-09-28T06:07:45Z"

// S1 — the formats.
do {
    var p: [String] = []
    let newYork = TimeZone(identifier: "America/New_York")!
    check(&p, AssistantTurnCost.day("2026-09-29T01:00:00Z", in: newYork), "2026-09-28", "day NY")
    check(
        &p, AssistantTurnCost.day("2026-09-29T01:00:00.000Z", in: newYork), "2026-09-28",
        "day NY fractional")
    check(&p, AssistantTurnCost.day("2026-09-29T01:00:00Z", in: TimeZone(identifier: "UTC")!),
          "2026-09-29", "day UTC")
    check(&p, AssistantTurnCost.day("yesterday-ish, not a date"), "yesterday-", "day unparseable")
    check(&p, AssistantTurnCost.amount(0.0006), "$0.0006", "amount 0.0006")
    check(&p, AssistantTurnCost.amount(0.00001), "under $0.0001", "amount 0.00001")
    check(&p, AssistantTurnCost.amount(0), "$0.0000", "amount 0")
    check(&p, AssistantTurnCost().line, nil as String?, "no cost event")
    let day = AssistantTurnCost.day(bundledAsOf)

    var one = AssistantTurnCost()
    one.add(cost("dollars", dollars: 0.0006, problem: "no price cache is configured"))
    check(&p, one.line,
          "Cost: $0.0006" + tail + "bundled table of \(day); not refreshed: no price cache is "
            + "configured)", "priced, bundled with a problem")

    var unknown = AssistantTurnCost()
    unknown.add(cost("unknown", detail: "claude-proof-model is not in the price table",
                     source: "fetched", asOf: bundledAsOf))
    check(&p, unknown.line,
          "Cost: unknown (claude-proof-model is not in the price table)" + tail
            + "fetched \(day))", "unknown alone")

    var mixed = AssistantTurnCost()
    mixed.add(cost("dollars", dollars: 0.0006, source: "cached"))
    mixed.add(cost("unknown", detail: "first detail", source: "cached"))
    mixed.add(cost("unknown", detail: "second detail", source: "cached"))
    check(&p, mixed.line,
          "Cost: unknown (first detail) · at least $0.0006" + tail + "cached \(day))",
          "priced then unknown")

    var tiny = AssistantTurnCost()
    tiny.add(cost("dollars", dollars: 0.00002, source: "fetched"))
    check(&p, tiny.line, "Cost: under $0.0001" + tail + "fetched \(day))", "under a hundredth cent")

    var tinyThenUnknown = AssistantTurnCost()
    tinyThenUnknown.add(cost("dollars", dollars: 0.00002, source: "cached"))
    tinyThenUnknown.add(cost("unknown", detail: "first detail", source: "cached"))
    check(&p, tinyThenUnknown.line,
          "Cost: unknown (first detail) · the priced part under $0.0001" + tail + "cached \(day))",
          "tiny priced then unknown")

    var unwritten = AssistantTurnCost()
    unwritten.add(cost("dollars", dollars: 0.0006, source: "fetched",
                       problem: "the price cache could not be written: EACCES"))
    check(&p, unwritten.line,
          "Cost: $0.0006" + tail + "fetched \(day); the price cache could not be written: EACCES)",
          "fetched with a cache-write problem")
    row("S1", p, "day 2026-09-29T01:00:00Z in New York is 2026-09-28; unparseable → first 10; "
        + "\(one.line ?? "") | \(unknown.line ?? "") | \(mixed.line ?? "")")
}

// S2 — the transcript's sum and its resets.
do {
    var p: [String] = []
    let day = AssistantTurnCost.day(bundledAsOf)
    let transcript = AssistantTranscript()
    transcript.take(["type": "turn_started"])
    transcript.take(cost("dollars", dollars: 0.0006))
    transcript.take(cost("dollars", dollars: 0.0004))
    transcript.take(["type": "turn_finished"])
    check(&p, transcript.entries.last?.kind.rawValue, "meta", "turn 1 kind")
    check(&p, transcript.entries.last?.text, "Cost: $0.0010" + tail + "bundled table of \(day))",
          "turn 1 line")
    transcript.take(["type": "turn_started"])
    transcript.take(cost("dollars", dollars: 0.0006))
    transcript.take(["type": "turn_finished"])
    check(&p, transcript.entries.last?.text, "Cost: $0.0006" + tail + "bundled table of \(day))",
          "turn 2 (not summed with turn 1)")
    let before = transcript.entries.count
    transcript.take(["type": "turn_started"])
    transcript.take(["type": "turn_finished"])
    check(&p, transcript.entries.count, before, "a turn with no cost adds no line")
    transcript.take(["type": "turn_started"])
    transcript.take(cost("dollars", dollars: 0.5))
    transcript.clear()
    transcript.take(["type": "turn_finished"])
    check(&p, transcript.entries.count, 0, "clear() drops the running sum")
    transcript.take(["type": "turn_started"])
    transcript.take(cost("dollars", dollars: 0.5))
    transcript.endConversation(note: "S2 ended.")
    transcript.take(["type": "turn_finished"])
    check(&p, transcript.entries.map(\.text), ["S2 ended."], "endConversation drops the sum")
    row("S2", p, "two turns priced apart ($0.0010, $0.0006); no cost, no line; clear and "
        + "endConversation reset the sum")
}

// S3 — the ledger whitelist.
do {
    var p: [String] = []
    var event = cost("dollars", dollars: 0.0006)
    event["api_key"] = "proof-key"
    event["content"] = "SECRET-CONTENT"
    event["usage"] = [
        "input_tokens": 100, "output_tokens": 10, "cache_creation_input_tokens": 3,
        "cache_read_input_tokens": 4,
        "cache_creation": ["ephemeral_5m_input_tokens": 1, "ephemeral_1h_input_tokens": 2,
                           "content": "SECRET-SPLIT"] as [String: Any],
        "service_tier": "standard", "speed": "standard", "inference_geo": "global",
        "server_tool_use": ["web_search_requests": 1] as [String: Any], "content": "SECRET-USAGE",
        "api_key": "proof-key",
        "iterations": [["type": "message", "model": "claude-opus-5-5", "input_tokens": 100,
                        "output_tokens": 10, "content": "SECRET-ITERATION"] as [String: Any]],
    ] as [String: Any]
    let at = Date(timeIntervalSince1970: 1_790_000_000)
    let line = AssistantSpend.ledgerLine(event, at: at) ?? [:]
    let text = String(
        data: (try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])) ?? Data(),
        encoding: .utf8) ?? ""
    check(&p, line.keys.sorted(),
          ["dollars", "model", "prices", "rows", "service", "time", "unknown", "usage"], "keys")
    for banned in ["SECRET", "proof-key", "api_key", "content", "server_tool_use"]
    where text.contains(banned) {
        p.append("the line carries \(banned)")
    }
    let usage = line["usage"] as? [String: Any] ?? [:]
    check(&p, usage.keys.sorted(),
          ["cache_creation", "cache_creation_input_tokens", "cache_read_input_tokens",
           "inference_geo", "input_tokens", "iterations", "output_tokens", "service_tier",
           "speed"], "usage keys")
    if (line["time"] as? String)?.range(
        of: #"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$"#, options: .regularExpression) == nil {
        p.append("time \(line["time"] ?? "nil") is not ISO 8601 UTC")
    }
    let unknownLine = AssistantSpend.ledgerLine(cost("unknown", detail: "x"), at: at) ?? [:]
    check(&p, unknownLine.keys.sorted(),
          ["dollars", "model", "prices", "service", "time", "unknown", "usage"], "unknown keys")
    check(&p, unknownLine["dollars"] is NSNull, true, "unknown dollars null")
    check(&p, AssistantSpend.ledgerLine(["type": "message_done"], at: at) == nil, true,
          "not a cost")
    row("S3", p, text)
}

// S4 — record.
do {
    var p: [String] = []
    let scratch = URL(fileURLWithPath: CommandLine.arguments.count > 1
        ? CommandLine.arguments[1] : NSTemporaryDirectory())
        .appendingPathComponent("s4", isDirectory: true)
    try? FileManager.default.removeItem(at: scratch)
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let flat = scratch.appendingPathComponent("flat", isDirectory: true)
    try? FileManager.default.createDirectory(at: flat, withIntermediateDirectories: true)
    check(&p, AssistantSpend.record(cost("dollars", dollars: 0.0006), in: flat), nil as String?,
          "first record")
    check(&p, AssistantSpend.record(cost("unknown", detail: "x"), in: flat), nil as String?,
          "second record")
    check(&p, AssistantSpend.record(["type": "turn_finished"], in: flat), nil as String?,
          "a non-cost")
    let ledger = flat.appendingPathComponent(AssistantSpend.ledgerName)
    let lines = ((try? String(contentsOf: ledger, encoding: .utf8)) ?? "")
        .split(separator: "\n", omittingEmptySubsequences: true)
    check(&p, lines.count, 2, "lines")
    for (i, one) in lines.enumerated()
    where (try? JSONSerialization.jsonObject(with: Data(one.utf8))) == nil {
        p.append("line \(i + 1) is not JSON")
    }
    let mode = ((try? FileManager.default.attributesOfItem(atPath: ledger.path))?[.posixPermissions]
        as? NSNumber)?.intValue ?? -1
    check(&p, String(mode, radix: 8), "600", "mode")
    let nested = scratch.appendingPathComponent("not/yet/here", isDirectory: true)
    check(&p, AssistantSpend.record(cost("dollars", dollars: 0.0006), in: nested), nil as String?,
          "nested record")
    let nestedLines = ((try? String(
        contentsOf: nested.appendingPathComponent(AssistantSpend.ledgerName), encoding: .utf8))
        ?? "").split(separator: "\n").count
    check(&p, nestedLines, 1, "nested lines")
    let file = scratch.appendingPathComponent("a-file")
    FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
    let refused = AssistantSpend.record(cost("dollars", dollars: 0.0006), in: file)
    if refused == nil { p.append("a file as the folder was not refused") }
    check(&p, AssistantSpend.record(cost("dollars", dollars: 0.0006), in: nil), nil as String?,
          "no folder writes nothing")
    row("S4", p, "two lines at 0\(String(mode, radix: 8)); nested folder created with "
        + "\(nestedLines) line; a file as the folder: \(refused ?? "nil")")
}

// S5 — P-5's table.
final class ArgumentDefaults: UserDefaults {
    var arguments: [String: Any] = [:]
    var persisted: [String: Any] = [:]
    override func volatileDomain(forName domainName: String) -> [String: Any] {
        domainName == UserDefaults.argumentDomain ? arguments : [:]
    }
    override func object(forKey defaultName: String) -> Any? { persisted[defaultName] }
    override func string(forKey defaultName: String) -> String? {
        persisted[defaultName] as? String
    }
}

do {
    var p: [String] = []
    let base = [AssistantConfiguration.baseURLVariable: "http://127.0.0.1:9"]
    let folder = "/tmp/rc-spend-probe-folder"
    let feed = "http://127.0.0.1:9/feed.json"
    let cache = folder + "/" + AssistantSpend.priceCacheName
    func defaults(_ arguments: [String: Any], persisted: [String: Any] = [:]) -> UserDefaults {
        let d = ArgumentDefaults()
        d.arguments = arguments
        d.persisted = persisted
        return d
    }
    func fields(_ d: UserDefaults, _ e: [String: String]) -> String {
        let f = AssistantSpend.configureFields(defaults: d, environment: e)
        return f.keys.sorted().map { "\($0)=\(f[$0] ?? "")" }.joined(separator: ",")
    }
    let person = AppSupport.file(AssistantSpend.priceCacheName)?.path ?? "nil"
    // 1. Nothing set: the person's folder.
    let none = defaults([:])
    check(&p, AssistantSpend.folder(defaults: none, environment: [:])?.path,
          AppSupport.directory?.path, "nothing set: folder")
    check(&p, fields(none, [:]), "price_cache=\(person)", "nothing set: fields")
    // 2. -RCSpendFolder alone.
    let spend = defaults([AssistantSpend.folderArgument: folder])
    check(&p, AssistantSpend.folder(defaults: spend, environment: [:])?.path, folder,
          "-RCSpendFolder: folder")
    check(&p, fields(spend, [:]), "price_cache=\(cache)", "-RCSpendFolder: fields")
    // 3. The override alone: no folder, nothing.
    check(&p, AssistantSpend.folder(defaults: none, environment: base)?.path, nil as String?,
          "override: folder")
    check(&p, fields(none, base), "", "override: fields")
    // 4. The override with -RCSpendFolder and no feed: the ledger, no cache.
    check(&p, AssistantSpend.folder(defaults: spend, environment: base)?.path, folder,
          "override + folder: folder")
    check(&p, fields(spend, base), "", "override + folder: fields")
    // 5. The override with both.
    let both = defaults([AssistantSpend.folderArgument: folder, AssistantSpend.feedArgument: feed])
    check(&p, fields(both, base), "price_cache=\(cache),price_feed=\(feed)",
          "override + folder + feed: fields")
    // 6. The override with the feed alone.
    let feedOnly = defaults([AssistantSpend.feedArgument: feed])
    check(&p, fields(feedOnly, base), "price_feed=\(feed)", "override + feed: fields")
    // 7. A persisted value is not an argument.
    let persisted = defaults([:], persisted: [AssistantSpend.folderArgument: folder,
                                              AssistantSpend.feedArgument: feed])
    check(&p, AssistantSpend.folder(defaults: persisted, environment: base)?.path, nil as String?,
          "persisted: folder")
    check(&p, fields(persisted, base), "", "persisted: fields")
    row("S5", p, "nothing set → the person's folder; -RCSpendFolder → it; the override → none; "
        + "the override + folder → the ledger only; + feed → the cache too; a persisted value "
        + "moves nothing")
}

let answer = ["rows": rows]
let data = try! JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
print("ANSWER " + String(data: data, encoding: .utf8)!)
