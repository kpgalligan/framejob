import Foundation

/// What the assistant's responses cost, on the app's side (road map 13 P2,
/// spec §11 P-4, P-5): the spend folder, the price-table fields `configure`
/// carries, the ledger line each `cost` event becomes, the view of an event a
/// dev tool may return, and the turn's cost line. The helper prices every
/// response (`agent/src/priceTable.ts`, `pricing.ts`); this file only records
/// the dollars it computed and formats them and their dates. No pricing
/// arithmetic is done here (road map 13 §2).
///
/// **P-5, the rule this file keeps.** The ledger (`spend.jsonl`) and the price
/// cache (`anthropic-prices.json`) are the person's, in the spend folder,
/// Reelcut's own folder in Application Support. `-RCSpendFolder <path>`,
/// read from the ARGUMENT domain alone (`AssemblyAIConfiguration.argument`,
/// R6-9 (c)), replaces it. With `RC_ASSISTANT_BASE_URL` set and no
/// `-RCSpendFolder` there is no spend folder: nothing is written and the
/// helper prices from its bundled table. With the base URL set, the cache is
/// handed to the helper only together with `-RCPriceFeed`, so a proof never
/// reaches LiteLLM. The support folder is named in exactly one line of this
/// file, as in `AssistantConfiguration.swift`; the folder is created, at
/// 0700, by whichever comes first: a ledger line written (`record`) or the
/// helper's cache write (`refreshPrices`, `mkdir -p`).
///
/// **Never the key, never content.** A ledger line carries the keys
/// `ledgerLine` lists and nothing else; `usage` is whitelisted field by field.
enum AssistantSpend {
    static let folderArgument = "RCSpendFolder", feedArgument = "RCPriceFeed",
        ledgerName = "spend.jsonl", priceCacheName = "anthropic-prices.json"
    /// Posted by `record` (object nil, on its caller's thread — main in the
    /// app) each time it writes a ledger line; Settings' month figure
    /// re-reads the ledger on it (spec §11 P-7).
    static let didRecordNotification = Notification.Name("ReelcutSpendDidRecord")

    /// The token counts a ledger line keeps from a `usage` or an iteration.
    private static let countKeys = [
        "input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens",
    ]
    /// The split of cache writes under `usage.cache_creation`.
    private static let splitKeys = ["ephemeral_5m_input_tokens", "ephemeral_1h_input_tokens"]
    /// The modes `usage` names, which decide whether a response is priced.
    private static let modeKeys = ["service_tier", "speed", "inference_geo"]

    /// The spend folder, or nil when there is none (P-5).
    static func folder(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let path = AssemblyAIConfiguration.argument(folderArgument, defaults: defaults) {
            return URL(
                fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let base = environment[AssistantConfiguration.baseURLVariable], !base.isEmpty {
            return nil
        }
        return AppSupport.directory
    }

    /// `configure`'s `price_cache` and `price_feed` (`agent/src/protocol.ts`):
    /// the cache in the spend folder, when there is one and, with the
    /// base-URL override set, only beside `-RCPriceFeed`.
    static func configureFields(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: Any] {
        var fields: [String: Any] = [:]
        let feed = AssemblyAIConfiguration.argument(feedArgument, defaults: defaults)
        if let feed { fields["price_feed"] = feed }
        guard let folder = folder(defaults: defaults, environment: environment) else {
            return fields
        }
        let overridden = !(environment[AssistantConfiguration.baseURLVariable] ?? "").isEmpty
        if overridden && feed == nil { return fields }
        fields["price_cache"] = folder.appendingPathComponent(priceCacheName).path
        return fields
    }

    /// The ledger line of a `cost` event, else nil: `time` (ISO 8601 UTC),
    /// `service`, `model`, the whitelisted `usage`, `dollars` (or null),
    /// `unknown` (null or `{cause, detail}`), `rows` (only when priced),
    /// `prices` (`{kind, as_of, problem?}`) and `partial: true` for a response
    /// cut short (spec §11 P-8), absent otherwise. Nothing else.
    static func ledgerLine(_ event: [String: Any], at time: Date) -> [String: Any]? {
        guard event["type"] as? String == "cost" else { return nil }
        let cost = event["cost"] as? [String: Any] ?? [:]
        var line: [String: Any] = [
            "time": ISO8601DateFormatter().string(from: time),
            "service": "anthropic",
            "model": (event["model"] as? String).map { $0 as Any } ?? NSNull(),
            "usage": usage(event["usage"]),
            "prices": prices(event["prices"]),
            "dollars": NSNull(), "unknown": NSNull(),
        ]
        if cost["kind"] as? String == "dollars", let dollars = number(cost["dollars"]) {
            line["dollars"] = dollars
            line["rows"] = (cost["rows"] as? [Any] ?? []).compactMap { $0 as? String }
        } else {
            line["unknown"] = [
                "cause": cost["cause"] as? String ?? "usage",
                "detail": cost["detail"] as? String ?? "the helper sent no price",
            ]
        }
        if isPartial(event) { line["partial"] = true }
        return line
    }

    /// Whether `event` is a response cut short (P-8): only a JSON `true`.
    static func isPartial(_ event: [String: Any]) -> Bool {
        guard let flag = event["partial"] as? NSNumber,
            CFGetTypeID(flag) == CFBooleanGetTypeID()
        else { return false }
        return flag.boolValue
    }

    /// Appends `event`'s ledger line to `spend.jsonl` in `folder`, creating
    /// the folder first; the file is opened `O_APPEND|O_CREAT` at 0600 and
    /// the line written in one `write`. Nil when written or when there is
    /// nothing to write (not a `cost`, no spend folder); else the failure, in
    /// a sentence the transcript can show.
    static func record(_ event: [String: Any], in folder: URL?, at time: Date = Date()) -> String? {
        guard let line = ledgerLine(event, at: time), let folder else { return nil }
        let path = folder.appendingPathComponent(ledgerName).path
        func failure(_ reason: String) -> String {
            let bare = reason.hasSuffix(".") ? String(reason.dropLast()) : reason
            return "The spend ledger \(path) could not be written: \(bare)."
        }
        do {
            try AppSupport.ensureDirectory(folder)
        } catch {
            return failure(error.localizedDescription)
        }
        guard var data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
        else { return failure("the line is not JSON") }
        data.append(UInt8(ascii: "\n"))
        let descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard descriptor >= 0 else { return failure(String(cString: strerror(errno))) }
        defer { close(descriptor) }
        let written = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard written == data.count else {
            return failure(written < 0 ? String(cString: strerror(errno)) : "a short write")
        }
        NotificationCenter.default.post(name: didRecordNotification, object: nil)
        return nil
    }

    /// An event as a dev tool may return it (AI-8, AI-11: never the key or
    /// the model): a `cost` keeps only `{type, cost: {kind, dollars|cause},
    /// prices}` and `partial: true` for one cut short; every other event is itself.
    static func toolView(_ event: [String: Any]) -> [String: Any] {
        guard event["type"] as? String == "cost" else { return event }
        let cost = event["cost"] as? [String: Any] ?? [:]
        var view: [String: Any] = ["kind": cost["kind"] ?? NSNull()]
        if cost["kind"] as? String == "dollars" {
            view["dollars"] = cost["dollars"] ?? NSNull()
        } else {
            view["cause"] = cost["cause"] ?? NSNull()
        }
        var kept: [String: Any] = [
            "type": "cost", "cost": view, "prices": prices(event["prices"]),
        ]
        if isPartial(event) { kept["partial"] = true }
        return kept
    }

    /// An ISO 8601 instant, with whole or fractional seconds; nil otherwise.
    /// The two parsers are built once: a month's fold calls this per line.
    static func instant(_ text: String) -> Date? {
        wholeSeconds.date(from: text) ?? fractionalSeconds.date(from: text)
    }

    private static let wholeSeconds = ISO8601DateFormatter()
    private static let fractionalSeconds: ISO8601DateFormatter = {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser
    }()

    /// A JSON number that is not a boolean.
    static func number(_ value: Any?) -> NSNumber? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID()
        else { return nil }
        return value
    }

    // MARK: - Private

    private static func counts(_ from: [String: Any], into: inout [String: Any]) {
        for key in countKeys { if let value = number(from[key]) { into[key] = value } }
        if let split = from["cache_creation"] as? [String: Any] {
            var kept: [String: Any] = [:]
            for key in splitKeys { if let value = number(split[key]) { kept[key] = value } }
            into["cache_creation"] = kept
        }
    }

    private static func usage(_ value: Any?) -> [String: Any] {
        guard let usage = value as? [String: Any] else { return [:] }
        var kept: [String: Any] = [:]
        counts(usage, into: &kept)
        for key in modeKeys { if let mode = usage[key] as? String { kept[key] = mode } }
        if let iterations = usage["iterations"] as? [Any] {
            kept["iterations"] = iterations.map { element -> [String: Any] in
                guard let entry = element as? [String: Any] else { return [:] }
                var one: [String: Any] = [:]
                for key in ["type", "model"] { if let text = entry[key] as? String { one[key] = text } }
                counts(entry, into: &one)
                return one
            }
        }
        return kept
    }

    private static func prices(_ value: Any?) -> [String: Any] {
        let source = value as? [String: Any] ?? [:]
        var kept: [String: Any] = [
            "kind": source["kind"] as? String ?? "unknown", "as_of": source["as_of"] as? String ?? "",
        ]
        if let problem = source["problem"] as? String { kept["problem"] = problem }
        return kept
    }
}

/// One turn's cost, summed from its `cost` events: the dollars the helper
/// computed, the first response it could not price, and the table the last
/// response was priced from. `line` is the transcript's `.meta` line; a turn
/// with no `cost` event has none. Unknown is never shown as $0 (P-2); a
/// response cut short makes the priced amount "at least" (P-8).
struct AssistantTurnCost: Equatable {
    private var responses = 0
    private var dollars = 0.0
    private var priced = false
    private var firstUnknown: String?
    private var partial = false
    private var kind = "", asOf = "", problem: String?

    mutating func add(_ event: [String: Any]) {
        guard event["type"] as? String == "cost" else { return }
        responses += 1
        if AssistantSpend.isPartial(event) { partial = true }
        let cost = event["cost"] as? [String: Any] ?? [:]
        if cost["kind"] as? String == "dollars", let value = cost["dollars"] as? Double {
            dollars += value
            priced = true
        } else if firstUnknown == nil {
            firstUnknown = cost["detail"] as? String ?? "no price"
        }
        let source = event["prices"] as? [String: Any] ?? [:]
        kind = source["kind"] as? String ?? ""
        asOf = source["as_of"] as? String ?? ""
        problem = source["problem"] as? String
    }

    var line: String? {
        guard responses > 0 else { return nil }
        var amount = Self.amount(dollars)
        if let firstUnknown {
            amount = "unknown (\(firstUnknown))"
            if priced { amount += Self.pricedPart(dollars) }
        } else if partial {
            amount = Self.lowerBound(dollars) + " (a response was cut short)"
        }
        let day = Self.day(asOf)
        var source: String
        switch kind {
        case "bundled": source = "bundled table of \(day)"
        case "cached": source = "cached \(day)"
        case "fetched": source = "fetched \(day)"
        default: source = "\(kind) \(day)"
        }
        // A fetched table was refreshed; its problem is the cache write.
        if let problem { source += (kind == "fetched" ? "; " : "; not refreshed: ") + problem }
        return "Cost: \(amount) · Reelcut's estimate at LiteLLM prices (\(source))"
    }

    /// The Assistant tab's Spend row (spec §11 P-7): "Nothing yet" before any
    /// response; the amount when every response was priced, "at least" it
    /// when one was cut short; "at least" the priced part when one was not
    /// priced and the part shows; else "unknown".
    var figure: String {
        guard responses > 0 else { return "Nothing yet" }
        let estimate = " · Reelcut's estimate"
        if firstUnknown == nil {
            return (partial ? Self.lowerBound(dollars) : Self.amount(dollars)) + estimate
        }
        if dollars >= 0.000_05 { return "at least " + String(format: "$%.4f", dollars) + estimate }
        return "unknown" + estimate
    }

    /// The Spend row's spellings, longest first (spec §11 P-7, P-8):
    /// ["Nothing yet"] before any response; else [figure], plus, when figure
    /// starts "at least " or "under ", figure with that prefix replaced by
    /// "≥" or "<" (no space). Every rung after a response ends
    /// " · Reelcut's estimate".
    var figureLadder: [String] {
        let full = figure
        for (long, short) in [("at least ", "≥"), ("under ", "<")] where full.hasPrefix(long) {
            return [full, short + full.dropFirst(long.count)]
        }
        return [full]
    }

    static let figureTooltip =
        "What this conversation's responses cost at LiteLLM prices, as Reelcut estimates it. "
        + "The Anthropic Console shows what your account was billed."

    /// `$%.4f`, or `under $0.0001` for a positive amount that would round to 0.
    static func amount(_ dollars: Double) -> String {
        if dollars > 0 && dollars < 0.000_05 { return "under $0.0001" }
        return String(format: "$%.4f", dollars)
    }

    /// A lower bound (P-8): `at least $%.4f`, or `amount` below $0.00005.
    static func lowerBound(_ dollars: Double) -> String {
        dollars < 0.000_05 ? amount(dollars) : "at least " + String(format: "$%.4f", dollars)
    }

    /// What the priced responses of a turn with an unknown one came to:
    /// ` · at least $%.4f`, or ` · the priced part under $0.0001` for a
    /// positive amount that would round to 0.
    static func pricedPart(_ dollars: Double) -> String {
        if dollars > 0 && dollars < 0.000_05 { return " · the priced part under $0.0001" }
        return " · at least " + String(format: "$%.4f", dollars)
    }

    /// The `yyyy-MM-dd` of the ISO 8601 instant `asOf` in `zone`; its first 10
    /// characters when it does not parse.
    static func day(_ asOf: String, in zone: TimeZone = .current) -> String {
        guard let instant = AssistantSpend.instant(asOf) else { return String(asOf.prefix(10)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: instant)
    }
}
