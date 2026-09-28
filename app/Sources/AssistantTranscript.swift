import Foundation

/// One line of the Assistant tab's transcript: what the person sent, the
/// assistant's streamed reply, its progress notes between tool calls, a meta
/// line (a tool call, a failed result, an answer, compaction, a note the app
/// writes), or an error.
struct AssistantEntry: Equatable {
    enum Kind: String {
        case person, reply, progress, meta, error
    }

    let kind: Kind
    var text: String
}

/// What changed in the transcript, so a view redraws one entry rather than
/// all of them. `extended` carries the entry's WHOLE text now.
enum AssistantTranscriptChange: Equatable {
    case appended(AssistantEntry)
    case extended(index: Int, text: String)
    case cleared
    case usage(AssistantContextUsage)
    /// The conversation's cost so far (road map 13 P4, spec §11 P-7).
    case conversationCost(AssistantTurnCost)
}

/// The window's conversation as the person reads it (road map 12 A2): the
/// session's events turned into entries, and the context usage the helper
/// last reported. Rasterize's `AssistantPanelViewController.handleEvent`,
/// ported as storage with no views, so the tab and a later floating window
/// (spec §11 AI-4) draw the same transcript. It lives on
/// `EditorViewController.assistantTranscript`, beside the session; the view
/// holds none of it. Main only.
final class AssistantTranscript {
    private(set) var entries: [AssistantEntry] = []
    private(set) var usage = AssistantContextUsage()
    /// Every `cost` event since the last Clear or ended conversation, summed:
    /// the tab's Spend row (spec §11 P-7). In memory, so it carries across a
    /// helper restart and needs no spend folder.
    private(set) var conversationCost = AssistantTurnCost()

    /// Each change, as it happens.
    var onChange: ((AssistantTranscriptChange) -> Void)?

    /// The delta type ("text_delta" / "progress_delta") extending the newest
    /// entry; any other event, or a line the app writes, ends it.
    private var streamingType: String?
    /// The last question's sentence, which the answer event does not carry.
    private var questionSentence = ""
    /// The running turn's `cost` events, summed (road map 13 P2).
    private var turnCost = AssistantTurnCost()

    /// What the person sent.
    func person(_ text: String) {
        streamingType = nil
        append(.person, text)
    }

    /// A meta line the app writes (a settings change, say).
    func note(_ text: String) {
        streamingType = nil
        append(.meta, text)
    }

    /// One `AssistantSession` event.
    func take(_ event: [String: Any]) {
        let type = event["type"] as? String
        if type != streamingType { streamingType = nil }
        switch type {
        case "text_delta":
            delta(event["text"] as? String ?? "", type: "text_delta", kind: .reply)
        case "progress_delta":
            delta(event["text"] as? String ?? "", type: "progress_delta", kind: .progress)
        case "compaction_started":
            let used = (event["used"] as? Int ?? 0).formatted()
            append(.meta, "Compacting the conversation (\(used) tokens)…")
        case "compacted":
            let before = (event["before"] as? Int ?? 0).formatted()
            let after = (event["after"] as? Int ?? 0).formatted()
            append(
                .meta,
                "Compacted: \(before) → about \(after) tokens. Earlier renders are gone; "
                    + "the assistant re-renders when it needs to look.")
        case "compaction_failed":
            let reason = event["reason"] as? String ?? "no summary came back"
            append(
                .meta,
                "Compaction didn't finish (\(reason)); it will try again after the next turn.")
        case "tool_results_cleared":
            let uses = event["tool_uses"] as? Int ?? 0
            let tokens = (event["tokens"] as? Int ?? 0).formatted()
            append(
                .meta, "Cleared \(uses) old tool results (\(tokens) tokens) from the model's view.")
        case "context_usage":
            setUsage(
                AssistantContextUsage(
                    used: event["used"] as? Int ?? 0, limit: event["limit"] as? Int,
                    reported: true))
        case "tool_call":
            let name = event["name"] as? String ?? "?"
            append(.meta, name + Self.argumentSummary(event["arguments"]))
        case "tool_result":
            if event["is_error"] as? Bool == true {
                append(.meta, "failed: \(event["summary"] as? String ?? "")")
            }
        case "question":
            questionSentence = event["sentence"] as? String ?? ""
        case "answer":
            let by = event["by"] as? String ?? "person"
            if event["allowed"] as? Bool == true {
                append(.meta, "Allowed: \(questionSentence)")
            } else if by == "person" {
                append(.meta, "Declined: \(questionSentence)")
            } else {
                append(.meta, "Declined (\(by)): \(questionSentence)")
            }
        case "error":
            append(.error, event["message"] as? String ?? "Unknown error.")
        case "turn_started":
            turnCost = AssistantTurnCost()
        case "cost":
            turnCost.add(event)
            conversationCost.add(event)
            onChange?(.conversationCost(conversationCost))
        case "turn_finished":
            if let line = turnCost.line { append(.meta, line) }
            turnCost = AssistantTurnCost()
        default:
            break
        }
    }

    /// Clear: every entry gone, the cost and the usage back to none. The
    /// window size is the model's, so it is kept.
    func clear() {
        entries = []
        streamingType = nil
        questionSentence = ""
        turnCost = AssistantTurnCost()
        onChange?(.cleared)
        resetConversationCost()
        setUsage(AssistantContextUsage(used: 0, limit: usage.limit, reported: usage.reported))
    }

    /// The conversation ended under the transcript (a key or model change):
    /// the note says so, and the cost and the usage start over.
    func endConversation(note text: String) {
        note(text)
        turnCost = AssistantTurnCost()
        resetConversationCost()
        setUsage(AssistantContextUsage(used: 0, limit: usage.limit, reported: usage.reported))
    }

    /// " (k: v, …)" for a tool call's arguments, sorted, `project` dropped,
    /// the first 70 characters; "" when there is nothing to show.
    static func argumentSummary(_ arguments: Any?) -> String {
        guard let arguments = arguments as? [String: Any], !arguments.isEmpty else { return "" }
        let parts = arguments
            .filter { $0.key != "project" }
            .map { "\($0.key): \(compact($0.value))" }
            .sorted()
            .joined(separator: ", ")
        guard !parts.isEmpty else { return "" }
        return " (\(String(parts.prefix(70))))"
    }

    /// A string as itself; anything else as one line of JSON, so an id array
    /// reads `[3,4]` and a boolean `true`.
    private static func compact(_ value: Any) -> String {
        if let string = value as? String { return string }
        guard
            JSONSerialization.isValidJSONObject([value]),
            let data = try? JSONSerialization.data(
                withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return "\(value)" }
        return text
    }

    // MARK: - Private

    private func append(_ kind: AssistantEntry.Kind, _ text: String) {
        let entry = AssistantEntry(kind: kind, text: text)
        entries.append(entry)
        onChange?(.appended(entry))
    }

    /// Streams into the newest entry while the same delta type runs; the
    /// first delta of a run opens an entry.
    private func delta(_ text: String, type: String, kind: AssistantEntry.Kind) {
        guard streamingType == type, let last = entries.indices.last else {
            append(kind, text)
            streamingType = type
            return
        }
        entries[last].text += text
        onChange?(.extended(index: last, text: entries[last].text))
    }

    private func resetConversationCost() {
        conversationCost = AssistantTurnCost()
        onChange?(.conversationCost(conversationCost))
    }

    private func setUsage(_ next: AssistantContextUsage) {
        usage = next
        onChange?(.usage(next))
    }
}
