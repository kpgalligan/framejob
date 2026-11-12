import Anthropic
import Foundation

// The stdio protocol between the app (AssistantSession) and this helper: one JSON object per
// line in each direction. The name "tool_result" is used both ways, with different shapes. Spec
// §7.9b and agent/src/protocol.ts hold the contract; spec §11 SA-6 says what changed with Swift.

/// The Assistant tab's Chat Settings that shape requests (spec §11 AI-20).
public struct ChatSettings: Sendable, Equatable {
    /// Compact at the end of a turn once context reaches this many tokens; nil never compacts.
    public var autoCompactTokens: Int?
    /// Let the API clear old tool results past a threshold (off by default).
    public var clearToolResults: Bool

    /// What a helper uses before its first `configure`.
    public static let initial = ChatSettings(autoCompactTokens: 300_000, clearToolResults: false)

    public init(autoCompactTokens: Int?, clearToolResults: Bool) {
        self.autoCompactTokens = autoCompactTokens
        self.clearToolResults = clearToolResults
    }

    /// Lenient, as the app's `settingsJSON` is the only writer: a missing or null limit is "never".
    init(json: RawJSON?) {
        autoCompactTokens = json?["auto_compact_tokens"]?.intValue
        clearToolResults = json?["clear_tool_results"]?.boolValue ?? false
    }

    var json: RawJSON {
        ["auto_compact_tokens": autoCompactTokens.map { .number(.init($0)) } ?? .null,
         "clear_tool_results": .bool(clearToolResults)]
    }
}

/// One entry of the app's MCP-format tool catalog. `description` and `inputSchema` stay the
/// JSON the app sent, in its key order, so the request's tool prefix is the same bytes on every
/// round.
public struct CatalogTool: Sendable, Equatable {
    public var name: String
    public var description: RawJSON?
    public var inputSchema: RawJSON?

    public init(name: String, description: RawJSON?, inputSchema: RawJSON?) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// The app's `configure` message.
public struct Configure: Sendable, Equatable {
    public var apiKey: String
    public var model: String
    public var system: String
    public var tools: [CatalogTool]
    /// Tools the model sees up front; every other catalog entry is deferred (tool search).
    public var coreTools: [String]
    /// Appended to the system prompt after a blank line: what tool search can find.
    public var searchGuide: String
    /// What the end-of-turn compaction summary must carry.
    public var compactionInstructions: String
    public var settings: ChatSettings
    /// The app's base-URL override (RC_ASSISTANT_BASE_URL, spec §11 AI-13), for a test server.
    public var apiBase: String?
    /// The price cache's absolute path; nil is the bundled table only, and no refresh.
    public var priceCache: String?
    /// Where the refresh fetches LiteLLM's table; nil is `PriceTable.liteLLMURL`.
    public var priceFeed: String?

    public init(apiKey: String, model: String, system: String, tools: [CatalogTool], coreTools: [String],
                searchGuide: String, compactionInstructions: String, settings: ChatSettings, apiBase: String?,
                priceCache: String? = nil, priceFeed: String? = nil)
    {
        self.apiKey = apiKey
        self.model = model
        self.system = system
        self.tools = tools
        self.coreTools = coreTools
        self.searchGuide = searchGuide
        self.compactionInstructions = compactionInstructions
        self.settings = settings
        self.apiBase = apiBase
        self.priceCache = priceCache
        self.priceFeed = priceFeed
    }
}

/// A line the app sent that this helper cannot use.
public struct ProtocolError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// App -> helper.
public enum HostMessage: Sendable, Equatable {
    case configure(Configure)
    case send(text: String)
    case cancel
    /// Chat Settings changed; applies from the next turn.
    case settings(ChatSettings)
    /// The answer to a tool_request; `result` is the MCP CallToolResult, nil when absent
    /// (a JSON null is `.null`: the app could not run the tool).
    case toolResult(callID: String, result: RawJSON?)
    /// A type this helper does not handle, ignored: `reset` among them, which the app never
    /// sends (Clear closes the process; spec §11 SA-6).
    case other(type: String?)

    /// Decodes one line. Throws `ProtocolError` (or the parser's error) for a bad line.
    public static func decode(_ line: Data) throws -> HostMessage {
        let json = try RawJSON.parse(line)
        guard case .object = json else { throw ProtocolError("expected a JSON object") }
        let type = json["type"]?.stringValue
        switch type {
        case "configure":
            return .configure(try decodeConfigure(json))
        case "send":
            return .send(text: try string(json, "text", in: "send"))
        case "cancel":
            return .cancel
        case "settings":
            return .settings(ChatSettings(json: json["settings"]))
        case "tool_result":
            return .toolResult(callID: try string(json, "call_id", in: "tool_result"), result: json["result"])
        default:
            return .other(type: type)
        }
    }

    private static func decodeConfigure(_ json: RawJSON) throws -> Configure {
        guard let entries = json["tools"]?.arrayValue else { throw ProtocolError("configure needs a tools array") }
        let tools = try entries.map { entry -> CatalogTool in
            guard let name = entry["name"]?.stringValue else { throw ProtocolError("a configure tool needs a name") }
            return CatalogTool(name: name, description: entry["description"], inputSchema: entry["inputSchema"])
        }
        guard let core = json["core_tools"]?.arrayValue else { throw ProtocolError("configure needs a core_tools array") }
        guard json["settings"]?.objectValue != nil else { throw ProtocolError("configure needs a settings object") }
        return Configure(
            apiKey: try string(json, "api_key", in: "configure"),
            model: try string(json, "model", in: "configure"),
            system: try string(json, "system", in: "configure"),
            tools: tools,
            coreTools: core.compactMap(\.stringValue),
            searchGuide: try string(json, "search_guide", in: "configure"),
            compactionInstructions: try string(json, "compaction_instructions", in: "configure"),
            settings: ChatSettings(json: json["settings"]),
            apiBase: json["api_base"]?.stringValue,
            priceCache: json["price_cache"]?.stringValue,
            priceFeed: json["price_feed"]?.stringValue)
    }

    private static func string(_ json: RawJSON, _ key: String, in type: String) throws -> String {
        guard let value = json[key]?.stringValue else { throw ProtocolError("\(type) needs a string \(key)") }
        return value
    }

    /// The message as the app writes it (tests build lines from it).
    public var json: RawJSON {
        switch self {
        case .configure(let c):
            var o: RawJSONObject = [
                "type": "configure", "api_key": .string(c.apiKey), "model": .string(c.model),
                "system": .string(c.system),
                "tools": .array(c.tools.map { tool in
                    var entry: RawJSONObject = ["name": .string(tool.name)]
                    if let d = tool.description { entry["description"] = d }
                    if let s = tool.inputSchema { entry["inputSchema"] = s }
                    return .object(entry)
                }),
                "core_tools": .array(c.coreTools.map { .string($0) }),
                "search_guide": .string(c.searchGuide),
                "compaction_instructions": .string(c.compactionInstructions),
                "settings": c.settings.json,
            ]
            if let base = c.apiBase { o["api_base"] = .string(base) }
            if let cache = c.priceCache { o["price_cache"] = .string(cache) }
            if let feed = c.priceFeed { o["price_feed"] = .string(feed) }
            return .object(o)
        case .send(let text): return ["type": "send", "text": .string(text)]
        case .cancel: return ["type": "cancel"]
        case .settings(let s): return ["type": "settings", "settings": s.json]
        case .toolResult(let id, let result):
            var o: RawJSONObject = ["type": "tool_result", "call_id": .string(id)]
            if let result { o["result"] = result }
            return .object(o)
        case .other(let type): return ["type": type.map { .string($0) } ?? .null]
        }
    }
}

/// Helper -> app. The app reads these loosely ([String: Any]), so a renamed field fails
/// silently there: the names and shapes are the contract.
public enum HelperEvent: Sendable, Equatable {
    /// After `configure`: the handshake. The app does not wait for it; a proof does.
    case ready
    case turnStarted
    case textDelta(String)
    /// A progress note between tool calls (a thinking delta under display "updates").
    case progressDelta(String)
    /// One complete response of a turn's rounds (never a summary): its stop reason and usage.
    case messageDone(stopReason: RawJSON, usage: RawJSON?)
    /// Tokens in the conversation after the last response; limit is the model's window (nil if unknown).
    case contextUsage(used: Int, limit: Int?)
    case toolCall(name: String, arguments: RawJSON)
    /// Run a tool and answer with tool_result. The arguments stay a JSON string, as the dispatcher takes them.
    case toolRequest(callID: String, name: String, argumentsJSON: String)
    case toolResult(name: String, isError: Bool, summary: String)
    case error(String)
    /// The turn's final reply pushed context past the auto-compact limit; a summary is being written.
    case compactionStarted(used: Int)
    /// The history is now the summary block; before/after are tokens in context.
    case compacted(before: Int, after: Int)
    /// No summary came back; the history is unchanged and the next turn end tries again.
    case compactionFailed(reason: String)
    /// The API cleared old tool results from what the model saw on one request.
    case toolResultsCleared(toolUses: Int, tokens: Int)
    /// Once per configure: before `ready` when no refresh is due, else when the refresh settles.
    case prices(PriceSource)
    /// Per response at the turn's prices: after message_done; for a summary, before compacted or
    /// compaction_failed. `partial` is a response cut short (a cancel or an error), priced from
    /// what its stream had reported, before any error (spec §11 P-8, SA-3). `model` and `usage`
    /// are the response's own JSON, nil when it had none.
    case cost(model: RawJSON?, usage: RawJSON?, cost: Price, prices: PriceSource, partial: Bool)
    case turnFinished

    /// The event's JSON, its keys in protocol.ts's order: `type` first, then the fields.
    public var json: RawJSON {
        switch self {
        case .ready: return ["type": "ready"]
        case .turnStarted: return ["type": "turn_started"]
        case .textDelta(let t): return ["type": "text_delta", "text": .string(t)]
        case .progressDelta(let t): return ["type": "progress_delta", "text": .string(t)]
        case .messageDone(let stop, let usage):
            var o: RawJSONObject = ["type": "message_done", "stop_reason": stop]
            if let usage { o["usage"] = usage }
            return .object(o)
        case .contextUsage(let used, let limit):
            return ["type": "context_usage", "used": .number(.init(used)), "limit": limit.map { .number(.init($0)) } ?? .null]
        case .toolCall(let name, let arguments): return ["type": "tool_call", "name": .string(name), "arguments": arguments]
        case .toolRequest(let id, let name, let args):
            return ["type": "tool_request", "call_id": .string(id), "name": .string(name), "arguments_json": .string(args)]
        case .toolResult(let name, let isError, let summary):
            return ["type": "tool_result", "name": .string(name), "is_error": .bool(isError), "summary": .string(summary)]
        case .error(let message): return ["type": "error", "message": .string(message)]
        case .compactionStarted(let used): return ["type": "compaction_started", "used": .number(.init(used))]
        case .compacted(let before, let after):
            return ["type": "compacted", "before": .number(.init(before)), "after": .number(.init(after))]
        case .compactionFailed(let reason): return ["type": "compaction_failed", "reason": .string(reason)]
        case .toolResultsCleared(let uses, let tokens):
            return ["type": "tool_results_cleared", "tool_uses": .number(.init(uses)), "tokens": .number(.init(tokens))]
        case .prices(let source): return ["type": "prices", "source": source.json]
        case .cost(let model, let usage, let cost, let prices, let partial):
            // Absent stays absent, as JSON.stringify drops an undefined field.
            var o: RawJSONObject = ["type": "cost"]
            if let model { o["model"] = model }
            if let usage { o["usage"] = usage }
            o["cost"] = cost.json
            o["prices"] = prices.json
            if partial { o["partial"] = true }
            return .object(o)
        case .turnFinished: return ["type": "turn_finished"]
        }
    }

    /// One protocol line: the compact JSON and a newline.
    public var line: Data {
        var data = json.serialized()
        data.append(0x0A)
        return data
    }

    /// The event a line holds, or nil for anything else (tests read lines back).
    public init?(json: RawJSON) {
        func int(_ key: String) -> Int? { json[key]?.intValue }
        func str(_ key: String) -> String? { json[key]?.stringValue }
        switch str("type") {
        case "ready": self = .ready
        case "turn_started": self = .turnStarted
        case "text_delta": guard let t = str("text") else { return nil }; self = .textDelta(t)
        case "progress_delta": guard let t = str("text") else { return nil }; self = .progressDelta(t)
        case "message_done": self = .messageDone(stopReason: json["stop_reason"] ?? .null, usage: json["usage"])
        case "context_usage":
            guard let used = int("used") else { return nil }
            self = .contextUsage(used: used, limit: int("limit"))
        case "tool_call":
            guard let name = str("name") else { return nil }
            self = .toolCall(name: name, arguments: json["arguments"] ?? .null)
        case "tool_request":
            guard let id = str("call_id"), let name = str("name"), let args = str("arguments_json") else { return nil }
            self = .toolRequest(callID: id, name: name, argumentsJSON: args)
        case "tool_result":
            guard let name = str("name"), let isError = json["is_error"]?.boolValue, let summary = str("summary")
            else { return nil }
            self = .toolResult(name: name, isError: isError, summary: summary)
        case "error": guard let m = str("message") else { return nil }; self = .error(m)
        case "compaction_started": guard let u = int("used") else { return nil }; self = .compactionStarted(used: u)
        case "compacted":
            guard let b = int("before"), let a = int("after") else { return nil }
            self = .compacted(before: b, after: a)
        case "compaction_failed": guard let r = str("reason") else { return nil }; self = .compactionFailed(reason: r)
        case "tool_results_cleared":
            guard let u = int("tool_uses"), let t = int("tokens") else { return nil }
            self = .toolResultsCleared(toolUses: u, tokens: t)
        case "prices": guard let s = PriceSource(json: json["source"]) else { return nil }; self = .prices(s)
        case "cost":
            guard let cost = Price(json: json["cost"]), let prices = PriceSource(json: json["prices"]) else { return nil }
            self = .cost(model: json["model"], usage: json["usage"], cost: cost, prices: prices,
                         partial: json["partial"]?.boolValue == true)
        case "turn_finished": self = .turnFinished
        default: return nil
        }
    }
}

/// Where events go: stdout in the helper, a recorder in tests. `emit` is synchronous and
/// keeps the order of its calls; it must be safe from any task.
public protocol EventSink: Sendable {
    func emit(_ event: HelperEvent)
}
