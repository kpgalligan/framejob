import Anthropic
import Foundation

// What one Messages API response cost, from its own `usage` and `model` and a price table of
// LiteLLM's Anthropic rows in US dollars per million tokens (agent/prices/anthropic.json; spec
// §11 P-2, SA-3). agent/src/pricing.ts's `price`, step for step, and tools/proof/prices.py's
// second reading of it: both answer agent/prices/cases.json. Pure: no I/O, and `price` never
// throws and never answers NaN, whatever JSON value `usage` is. A model the table does not hold,
// and usage the table cannot price (fast mode, a batch or priority tier, a US-only request, a
// malformed count, a class whose rate the row lacks), answers `unknown` with its cause, never $0.
//
// When `usage.iterations` is a non-empty array, each element is priced at its own `model` (or
// the response's), because the top-level counts describe only the attempt that returned the
// message and leave out compaction and a refused attempt before a fallback (the API's
// `BetaUsage.iterations`, read from the response's raw JSON).
//
// Numbers are doubles throughout, as JavaScript's are: a count is any finite, whole,
// non-negative JSON number (`1.0` and `1e3` are counts), and a class's cost is added in
// `classes`' order, so the sums round as the TypeScript's and the Python's do.

/// A price table as read from JSON: the object `PriceTables.parse` accepted, kept as it came.
public struct PriceTable: Sendable, Equatable {
    public let json: RawJSON

    /// Only `PriceTables.parse` and `PriceTables.reduceLiteLLM` make one.
    init(checked json: RawJSON) { self.json = json }

    public var models: RawJSONObject { json["models"]?.objectValue ?? [:] }
    public var source: String { json["source"]?.stringValue ?? "" }
    public var litellmCommit: String? { json["litellm_commit"]?.stringValue }
    public var litellmCommitDate: String? { json["litellm_commit_date"]?.stringValue }
    public var fetchedAt: String? { json["fetched_at"]?.stringValue }
}

/// A price: dollars with the table rows it used, or unknown with its cause.
public enum Price: Sendable, Equatable {
    case dollars(Double, rows: [String])
    /// `cause` is one of model, rate, usage, speed, service_tier, inference_geo.
    case unknown(cause: String, detail: String)

    /// `{kind, dollars, rows}` or `{kind, cause, detail}`, pricing.ts's shapes.
    public var json: RawJSON {
        switch self {
        case .dollars(let dollars, let rows):
            // A non-finite sum is JSON's null, as JSON.stringify writes Infinity.
            return ["kind": "dollars", "dollars": RawJSON.Number(dollars).map(RawJSON.number) ?? .null,
                    "rows": .array(rows.map(RawJSON.string))]
        case .unknown(let cause, let detail):
            return ["kind": "unknown", "cause": .string(cause), "detail": .string(detail)]
        }
    }

    public init?(json: RawJSON?) {
        switch json?["kind"]?.stringValue {
        case "dollars":
            guard let rows = json?["rows"]?.arrayValue else { return nil }
            self = .dollars(json?["dollars"]?.doubleValue ?? .infinity, rows: rows.compactMap(\.stringValue))
        case "unknown":
            guard let cause = json?["cause"]?.stringValue else { return nil }
            self = .unknown(cause: cause, detail: json?["detail"]?.stringValue ?? "")
        default:
            return nil
        }
    }
}

public enum Pricing {
    static let tierThreshold = 200_000.0
    /// The order a class's cost is added in, rate key then count key; the Python reader uses the same.
    static let classes: [(rate: String, count: String)] = [
        ("input", "input"), ("cache_write_5m", "write5m"), ("cache_write_1h", "write1h"),
        ("cache_read", "read"), ("output", "output"),
    ]

    /// The table key a response's model id prices at: the exact id, or the id less a trailing
    /// `-YYYYMMDD` when that is a key; nothing else is stripped.
    public static func matchModel(_ model: String, in table: PriceTable) -> String? {
        let models = table.models
        if models[model] != nil { return model }
        let scalars = Array(model.unicodeScalars)
        let dated = scalars.count >= 9 && scalars[scalars.count - 9] == "-"
            && scalars.suffix(8).allSatisfy { $0.value >= 0x30 && $0.value <= 0x39 }
        if dated {
            let bare = String(String.UnicodeScalarView(scalars.dropLast(9)))
            if models[bare] != nil { return bare }
        }
        return nil
    }

    /// A count: absent or null is 0, else a finite whole non-negative number, else nil.
    static func count(_ object: RawJSON, _ key: String) -> Double? {
        guard let value = object[key], !value.isNull else { return 0 }
        guard let number = value.doubleValue, number.isFinite, number.rounded() == number, number >= 0 else {
            return nil
        }
        return number
    }

    /// The five counts of one entry and the total the tier is chosen by, or why not.
    static func counts(_ entry: RawJSON) -> Result<[String: Double], Detail> {
        guard let input = count(entry, "input_tokens") else { return .failure("input_tokens is not a non-negative integer") }
        guard let creation = count(entry, "cache_creation_input_tokens") else {
            return .failure("cache_creation_input_tokens is not a non-negative integer")
        }
        guard let read = count(entry, "cache_read_input_tokens") else {
            return .failure("cache_read_input_tokens is not a non-negative integer")
        }
        guard let output = count(entry, "output_tokens") else { return .failure("output_tokens is not a non-negative integer") }
        var write5m = creation
        var write1h = 0.0
        if let split = entry["cache_creation"], split.objectValue != nil {
            guard let five = count(split, "ephemeral_5m_input_tokens") else {
                return .failure("cache_creation.ephemeral_5m_input_tokens is not a non-negative integer")
            }
            guard let hour = count(split, "ephemeral_1h_input_tokens") else {
                return .failure("cache_creation.ephemeral_1h_input_tokens is not a non-negative integer")
            }
            write5m = five
            write1h = hour
        }
        return .success(["input": input, "write5m": write5m, "write1h": write1h, "read": read, "output": output,
                         "total": input + creation + read])
    }

    /// A message the arithmetic gives up with.
    struct Detail: Error, ExpressibleByStringLiteral {
        let text: String
        init(stringLiteral value: String) { text = value }
        init(_ text: String) { self.text = text }
    }

    static func usable(_ rate: RawJSON?) -> Bool {
        guard let rate, let value = rate.doubleValue else { return false }
        return value.isFinite && value >= 0
    }

    /// Whether `usage[key]` is absent, null or `ok`.
    static func allowed(_ usage: RawJSON, _ key: String, _ ok: String) -> Bool {
        guard let value = usage[key], !value.isNull else { return true }
        return value.stringValue == ok
    }

    /// JSON.stringify's spelling of a field for a sentence: `undefined` when absent.
    static func quoted(_ value: RawJSON?) -> String { value?.serializedString ?? "undefined" }

    public static func price(usage: RawJSON, model: String, table: PriceTable) -> Price {
        // 1. The shapes.
        guard usage.objectValue != nil else { return .unknown(cause: "usage", detail: "usage is not an object") }
        if model.isEmpty { return .unknown(cause: "model", detail: "no model id") }

        // 2. Modes the table has no rate for.
        if !allowed(usage, "speed", "standard") {
            return .unknown(cause: "speed", detail: "speed \(quoted(usage["speed"])) is not priced")
        }
        if !allowed(usage, "service_tier", "standard") {
            return .unknown(cause: "service_tier", detail: "service_tier \(quoted(usage["service_tier"])) is not priced")
        }
        if !allowed(usage, "inference_geo", "global") {
            return .unknown(cause: "inference_geo", detail: "inference_geo \(quoted(usage["inference_geo"])) is not priced")
        }

        // 3. The entries.
        var entries: [(value: RawJSON, model: String)] = []
        let iterations = usage["iterations"]
        if let iterations, !iterations.isNull, iterations.arrayValue == nil {
            return .unknown(cause: "usage", detail: "iterations is not an array")
        }
        if let list = iterations?.arrayValue, !list.isEmpty {
            for (i, element) in list.enumerated() {
                guard element.objectValue != nil else {
                    return .unknown(cause: "usage", detail: "iterations[\(i)] is not an object")
                }
                let named = element["model"]?.stringValue ?? ""
                entries.append((element, named.isEmpty ? model : named))
            }
        } else {
            entries.append((usage, model))
        }

        // 4. The counts.
        var tallies: [[String: Double]] = []
        for (i, entry) in entries.enumerated() {
            switch counts(entry.value) {
            case .failure(let why):
                return .unknown(cause: "usage", detail: entries.count > 1 ? "iterations[\(i)].\(why.text)" : why.text)
            case .success(let tally):
                tallies.append(tally)
            }
        }

        // 5. The rows.
        var keys: [String] = []
        for entry in entries {
            guard let key = matchModel(entry.model, in: table) else {
                return .unknown(cause: "model", detail: "\(entry.model) is not in the price table")
            }
            keys.append(key)
        }

        // 6. The tier and the rates.
        var rates: [RawJSON] = []
        for i in entries.indices {
            guard let row = table.models[keys[i]], row.objectValue != nil else {
                return .unknown(cause: "rate", detail: "\(keys[i]) has no rates")
            }
            let above = row["above_200k"]
            let tiered = above?.objectValue != nil && tallies[i]["total", default: 0] > tierThreshold
            let chosen = tiered ? above! : row
            for (rateKey, countKey) in classes where tallies[i][countKey, default: 0] > 0 && !usable(chosen[rateKey]) {
                return .unknown(cause: "rate", detail: "\(keys[i]) has no \(tiered ? "above_200k " : "")\(rateKey) rate")
            }
            rates.append(chosen)
        }

        // 7. The arithmetic.
        var dollars = 0.0
        for i in entries.indices {
            var s = 0.0
            for (rateKey, countKey) in classes {
                let tokens = tallies[i][countKey, default: 0]
                if tokens == 0 { continue }
                s += tokens * (rates[i][rateKey]?.doubleValue ?? 0)
            }
            dollars += s / 1_000_000
        }
        var rows: [String] = []
        for key in keys where !rows.contains(key) { rows.append(key) }
        return .dollars(dollars, rows: rows)
    }
}
