import Anthropic
import Foundation

// The price table in force (spec §11 P-1, P-5, SA-3): the snapshot compiled into the helper
// (agent/prices/anthropic.json, through this target's anthropic.json symlink and SwiftPM's
// `.embedInCode`), a cached copy of LiteLLM's table that the helper refreshes at most once a
// day (PriceRefresh.swift), and the source it priced from, which is always reported so a stale
// table is never silent. The cache path comes from `configure`; without one the helper prices
// from the bundled table and fetches nothing. `reduceLiteLLM` is agent/prices/update.py's
// `reduce_table` with the feed and the fetch time in place of a LiteLLM commit, and both answer
// agent/prices/reduce_cases.json.

/// The table a price came from: the bundled snapshot (as of its LiteLLM commit's date), the
/// cached copy or a fresh fetch (as of `fetched_at`), and why it was not refreshed, if it was not.
public struct PriceSource: Sendable, Equatable {
    public enum Kind: String, Sendable { case bundled, cached, fetched }
    public var kind: Kind
    public var asOf: String
    public var problem: String?

    public init(kind: Kind, asOf: String, problem: String? = nil) {
        self.kind = kind
        self.asOf = asOf
        self.problem = problem
    }

    /// `{kind, as_of, problem?}`, the protocol's shape (spec §7.9b).
    public var json: RawJSON {
        var o: RawJSONObject = ["kind": .string(kind.rawValue), "as_of": .string(asOf)]
        if let problem { o["problem"] = .string(problem) }
        return .object(o)
    }

    public init?(json: RawJSON?) {
        guard let kind = json?["kind"]?.stringValue.flatMap(Kind.init(rawValue:)),
              let asOf = json?["as_of"]?.stringValue else { return nil }
        self.init(kind: kind, asOf: asOf, problem: json?["problem"]?.stringValue)
    }
}

/// A table and where it came from.
public struct LoadedPrices: Sendable, Equatable {
    public var table: PriceTable
    public var source: PriceSource

    func with(problem: String) -> LoadedPrices {
        var copy = self
        copy.source.problem = problem
        return copy
    }
}

/// Where the price cache is and where its refresh reads, from `configure`, and the clock.
public struct PriceOptions: Sendable {
    public var cache: String?
    public var feed: String?
    public var now: @Sendable () -> Date

    public init(cache: String?, feed: String?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.cache = cache
        self.feed = feed
        self.now = now
    }
}

public enum PriceTables {
    public static let liteLLMURL =
        "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    /// A day (spec §11 P-1: the table is refreshed daily).
    public static let refreshAfter: TimeInterval = 86_400
    public static let fetchTimeout: TimeInterval = 30
    public static let userAgent = "framejob-agent"

    static let required = ["claude-opus-5-5", "claude-fable-5-1"]
    /// LiteLLM's field, then the table's rate key, in update.py's order.
    static let fields: [(field: String, key: String)] = [
        ("input_cost_per_token", "input"),
        ("output_cost_per_token", "output"),
        ("cache_read_input_token_cost", "cache_read"),
        ("cache_creation_input_token_cost", "cache_write_5m"),
        ("cache_creation_input_token_cost_above_1hr", "cache_write_1h"),
    ]
    static var baseKeys: [String] { fields.map(\.key) }

    static func isRate(_ value: RawJSON?) -> Bool { Pricing.usable(value) && value?.numberValue != nil }

    /// Why `rates` is not a set of rates, or nil.
    static func ratesProblem(_ rates: RawJSON, _ place: String) -> String? {
        for key in baseKeys where rates[key] != nil && !isRate(rates[key]) {
            return "\(place) \(key) is not a finite non-negative number"
        }
        return nil
    }

    /// A `PriceTable` read from JSON, or why it is not one.
    public static func parse(_ value: RawJSON) -> Result<PriceTable, ProtocolError> {
        func refuse(_ why: String) -> Result<PriceTable, ProtocolError> { .failure(ProtocolError(why)) }
        guard value.objectValue != nil else { return refuse("not a JSON object") }
        guard value["format"]?.numberValue != nil, value["format"]?.doubleValue == 1 else {
            return refuse("format \(Pricing.quoted(value["format"])), not 1")
        }
        guard value["provider"]?.stringValue == "anthropic" else { return refuse("provider \(Pricing.quoted(value["provider"]))") }
        guard value["unit"]?.stringValue == "USD per million tokens" else { return refuse("unit \(Pricing.quoted(value["unit"]))") }
        guard value["source"]?.stringValue != nil else { return refuse("no source") }
        for key in ["litellm_commit", "litellm_commit_date", "fetched_at"]
        where value[key] != nil && value[key]?.stringValue == nil {
            return refuse("\(key) is not a string")
        }
        guard let models = value["models"]?.objectValue else { return refuse("no models") }
        for (model, row) in models {
            guard row.objectValue != nil else { return refuse("\(model) is not a row") }
            if let problem = ratesProblem(row, model) { return refuse(problem) }
            if let above = row["above_200k"] {
                guard above.objectValue != nil else { return refuse("\(model) above_200k is not a row") }
                if let problem = ratesProblem(above, "\(model) above_200k") { return refuse(problem) }
            }
        }
        for model in required {
            guard let row = models[model], row.objectValue != nil else { return refuse("no \(model) row") }
            let missing = baseKeys.filter { row[$0] == nil }
            if !missing.isEmpty { return refuse("\(model) lacks \(missing.joined(separator: ", "))") }
        }
        return .success(PriceTable(checked: value))
    }

    /// update.py's `per_million`: dollars per token to dollars per million, to 6 places.
    static func perMillion(_ value: RawJSON?, _ model: String, _ field: String) -> Result<Double, ProtocolError> {
        guard isRate(value), let rate = value?.doubleValue else {
            return .failure(ProtocolError(
                "\(model).\(field) is not a finite non-negative number: \(Pricing.quoted(value))"))
        }
        // Number(x.toFixed(6)): the exact value rounded to six places, then read back.
        return .success(Double(String(format: "%.6f", rate * 1_000_000)) ?? rate * 1_000_000)
    }

    /// update.py's `reduce_row`.
    static func reduceRow(_ model: String, _ entry: RawJSON) -> Result<RawJSON, ProtocolError> {
        var row = RawJSONObject()
        var above = RawJSONObject()
        for (field, key) in fields {
            if entry[field] != nil {
                switch perMillion(entry[field], model, field) {
                case .failure(let why): return .failure(why)
                case .success(let rate): row[key] = RawJSON.Number(rate).map(RawJSON.number) ?? .null
                }
            }
            let tier = field + "_above_200k_tokens"
            if entry[tier] != nil {
                switch perMillion(entry[tier], model, tier) {
                case .failure(let why): return .failure(why)
                case .success(let rate): above[key] = RawJSON.Number(rate).map(RawJSON.number) ?? .null
                }
            }
        }
        if !above.isEmpty { row["above_200k"] = .object(above) }
        return .success(.object(row))
    }

    /// update.py's `reduce_table`: LiteLLM's anthropic rows, or why the document is refused.
    public static func reduceLiteLLM(_ data: RawJSON, source: String, fetchedAt: String) -> Result<PriceTable, ProtocolError> {
        guard let entries = data.objectValue else { return .failure(ProtocolError("the document is not a JSON object")) }
        var models = RawJSONObject()
        for (model, entry) in entries where entry.objectValue != nil && entry["litellm_provider"]?.stringValue == "anthropic" {
            switch reduceRow(model, entry) {
            case .failure(let why): return .failure(why)
            case .success(let row): models[model] = row
            }
        }
        if models.isEmpty { return .failure(ProtocolError(#"no entry's litellm_provider is "anthropic""#)) }
        for model in required {
            guard let row = models[model] else { return .failure(ProtocolError("no \(model) row")) }
            let missing = baseKeys.filter { row[$0] == nil }
            if !missing.isEmpty { return .failure(ProtocolError("\(model) lacks \(missing.joined(separator: ", "))")) }
        }
        return .success(PriceTable(checked: [
            "format": 1, "provider": "anthropic", "unit": "USD per million tokens",
            "source": .string(source), "fetched_at": .string(fetchedAt), "models": .object(models),
        ]))
    }

    /// Why the helper will not fetch `url`, or nil: https, or http to a loopback host.
    public static func feedProblem(_ url: String) -> String? {
        let refused = "the price feed \(url) is neither https nor a loopback http URL"
        guard let parsed = URLComponents(string: url), let scheme = parsed.scheme?.lowercased(),
              let host = parsed.host?.lowercased(), !host.isEmpty else { return refused }
        if scheme == "https" { return nil }
        if scheme == "http" && ["127.0.0.1", "localhost", "[::1]", "::1"].contains(host) { return nil }
        return refused
    }

    /// The table compiled into the helper, as of its LiteLLM commit's date. A bundled table
    /// that does not parse is a build defect the suite catches; the helper then has none to
    /// price from, so this traps rather than price at zero.
    public static func bundled() -> LoadedPrices {
        let parsed = (try? RawJSON.parse(Data(PackageResources.anthropic_json))).map(parse)
        guard case .success(let table) = parsed else {
            preconditionFailure("the bundled price table is invalid: \(String(describing: parsed))")
        }
        return LoadedPrices(table: table, source: PriceSource(kind: .bundled, asOf: table.litellmCommitDate ?? ""))
    }

    /// `fetched_at` as written by either helper (`toISOString`, fractional seconds) or by hand.
    static func date(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }

    /// `toISOString`'s spelling: UTC, milliseconds, `Z`.
    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// The prices in force at `configure`, from the cache (read synchronously) or the bundled
    /// table, and whether a refresh is due.
    public static func initial(_ o: PriceOptions) -> (prices: LoadedPrices, refreshDue: Bool) {
        let now = o.now()
        let fallback = bundled()
        guard let cache = o.cache, !cache.isEmpty else {
            return (fallback.with(problem: "no price cache is configured"), false)
        }
        guard cache.hasPrefix("/") else { return (fallback.with(problem: "the price cache path is not absolute"), false) }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: cache))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return (fallback, true)
        } catch {
            return (fallback.with(problem: "the price cache is unreadable: \(error.localizedDescription)"), true)
        }
        let table: Result<PriceTable, ProtocolError>
        do {
            table = parse(try RawJSON.parse(data))
        } catch {
            table = .failure(ProtocolError("not JSON: \(AgentSession.describe(error))"))
        }
        switch table {
        case .failure(let why):
            return (fallback.with(problem: "the price cache is unreadable: \(why.message)"), true)
        case .success(let table):
            let fetchedAt = table.fetchedAt ?? ""
            let age = date(fetchedAt).map { now.timeIntervalSince($0) }
            let due = age.map { $0 >= refreshAfter || $0 < 0 } ?? true
            return (LoadedPrices(table: table, source: PriceSource(kind: .cached, asOf: fetchedAt)), due)
        }
    }
}
