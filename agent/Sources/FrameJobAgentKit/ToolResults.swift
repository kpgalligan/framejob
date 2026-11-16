import Anthropic
import Foundation

/// An MCP CallToolResult turned into Messages API tool_result content, plus the
/// one-line summary the panel shows for a failure.
public struct ConvertedToolResult: Sendable, Equatable {
    public var blocks: [RawJSON]
    public var isError: Bool
    public var summary: String

    public init(blocks: [RawJSON], isError: Bool, summary: String) {
        self.blocks = blocks
        self.isError = isError
        self.summary = summary
    }
}

public enum ToolResults {
    /// How much of a tool's first text the panel's summary keeps, in UTF-16 code units
    /// (the protocol contract's 200, which the TypeScript helper's `convertToolResult` kept).
    public static let summaryLength = 200

    /// The Anthropic API's limit on one image, in bytes of base64 (spec §11 PR-25): an image item
    /// whose `data` passes it is answered as text, so it never enters the history; exactly at it is
    /// sent (SA-14).
    public static let imageLimit = 10_485_760

    /// MCP CallToolResult -> tool_result content. Text becomes a text block and an
    /// image a base64 image block (image/png when it names no type); other content
    /// types are dropped. No result, or nothing usable in it, is an error block.
    /// An image whose base64 passes `imageLimit` becomes the `tooLarge` text in its
    /// place, the rest kept, and makes the result an error summarised by that sentence
    /// (spec §11 SA-14), so the image never reaches the history.
    public static func convert(_ result: RawJSON?) -> ConvertedToolResult {
        guard let result, isTruthy(result) else { return failure("The tool failed to execute.") }
        var blocks: [RawJSON] = []
        var summary = ""
        var replaced: String?
        for item in result["content"]?.arrayValue ?? [] {
            switch item["type"]?.stringValue {
            case "text":
                let text = item["text"]?.stringValue ?? ""
                if summary.isEmpty { summary = prefix(text, summaryLength) }
                blocks.append(["type": "text", "text": .string(text)])
            case "image":
                let data = item["data"]?.stringValue ?? ""
                let bytes = data.utf8.count
                if bytes > imageLimit {
                    let sentence = tooLarge(bytes)
                    if replaced == nil { replaced = sentence }
                    blocks.append(["type": "text", "text": .string(sentence)])
                    continue
                }
                if summary.isEmpty { summary = "(image)" }
                blocks.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": .string(item["mimeType"]?.stringValue ?? "image/png"),
                        "data": .string(data),
                    ],
                ])
            default:
                continue
            }
        }
        if blocks.isEmpty { return failure("The tool returned no content.") }
        if let replaced {
            return ConvertedToolResult(blocks: blocks, isError: true, summary: prefix(replaced, summaryLength))
        }
        return ConvertedToolResult(blocks: blocks, isError: result["isError"]?.boolValue == true, summary: summary)
    }

    /// The tool_result block for one tool_use, as the SDK runner built it: an error
    /// carries `is_error` and keeps its blocks, images included.
    public static func block(toolUseID: RawJSON, _ converted: ConvertedToolResult) -> RawJSON {
        var o: RawJSONObject = ["type": "tool_result", "tool_use_id": toolUseID, "content": .array(converted.blocks)]
        if converted.isError { o["is_error"] = true }
        return .object(o)
    }

    /// The answer to a tool_use naming no tool the helper was configured with.
    public static func notFound(toolUseID: RawJSON, name: String) -> RawJSON {
        ["type": "tool_result", "tool_use_id": toolUseID, "content": .string("Error: Tool '\(name)' not found"),
         "is_error": true]
    }

    /// The answer to a tool_use in a turn's final reply (one that stopped with
    /// `stopReason`, not `tool_use`), which is never run.
    public static func notRun(toolUseID: RawJSON, stopReason: String) -> RawJSON {
        ["type": "tool_result", "tool_use_id": toolUseID,
         "content": .string("Not run: the reply stopped with \(stopReason) before this call could run."),
         "is_error": true]
    }

    /// What the model reads in place of an image of `bytes` bytes of base64 past `imageLimit`
    /// (spec §11 SA-14). It names `max_width` conditionally: the helper knows no tool's arguments.
    static func tooLarge(_ bytes: Int) -> String {
        "The image is too large to send: its base64 is \(grouped(bytes)) bytes and the API's limit for one image is "
            + "\(grouped(imageLimit)). Ask again for a smaller one, with max_width where the tool takes it."
    }

    /// `n` with a comma between each group of three digits, written by hand: the helper reads no
    /// locale.
    static func grouped(_ n: Int) -> String {
        var digits = String(n)
        var groups = ""
        while digits.count > 3 {
            groups = "," + digits.suffix(3) + groups
            digits.removeLast(3)
        }
        return digits + groups
    }

    /// The first `limit` UTF-16 code units of `text`, never splitting a surrogate pair.
    static func prefix(_ text: String, _ limit: Int) -> String {
        var units = 0
        var end = text.unicodeScalars.startIndex
        for scalar in text.unicodeScalars {
            let width = scalar.utf16.count
            if units + width > limit { break }
            units += width
            end = text.unicodeScalars.index(after: end)
        }
        return String(text.unicodeScalars[..<end])
    }

    private static func failure(_ message: String) -> ConvertedToolResult {
        ConvertedToolResult(blocks: [["type": "text", "text": .string(message)]], isError: true, summary: message)
    }

    /// The contract's failed result: a falsy one (`null`, `false`, `0`, `NaN` or an
    /// empty string) is "The tool failed to execute."; any array or object is a result.
    private static func isTruthy(_ value: RawJSON) -> Bool {
        switch value {
        case .null: return false
        case .bool(let b): return b
        case .number(let n): return n.doubleValue.map { $0 != 0 && !$0.isNaN } ?? true
        case .string(let s): return !s.isEmpty
        case .array, .object: return true
        }
    }
}
