import AppKit

#if FRAMEJOB_DEV_TOOLS
/// `transcript_view`'s Find (spec §11 TX-38): the two arguments a proof
/// drives the Transcript tab's find bar with, and what the tool answers about
/// it. Find itself has no product tool (TX-37): it edits nothing.
///
/// `find` — a string opens the bar as Edit ▸ Find… does and sets its field's
/// text through the field's own change path; null closes it by Esc's path.
/// `find_step` — "next" or "previous", Return's or ⇧Return's path, once,
/// after `find`; refused while the bar would be closed.
extension AgentServer {

    struct TranscriptFindArguments {
        /// `.some(nil)` for an explicit null (close).
        var find: String??
        var step: Int?
    }

    /// Read on the server thread, refused before anything moves.
    func transcriptFindArguments(_ a: [String: Any]) throws -> TranscriptFindArguments {
        var out = TranscriptFindArguments()
        if let raw = a["find"] {
            if raw is NSNull {
                out.find = .some(nil)
            } else {
                guard let text = raw as? String else {
                    throw ToolError(message: "find must be a string or null.")
                }
                out.find = .some(text)
            }
        }
        if let step = try stringArg(a, "find_step") {
            switch step {
            case "next": out.step = 1
            case "previous": out.step = -1
            default:
                throw ToolError(message: "find_step must be \"next\" or \"previous\" (got \"\(step)\").")
            }
        }
        if out.step != nil, case .some(.none) = out.find {
            throw ToolError(message: "find_step steps an open find bar; find: null closes it.")
        }
        return out
    }

    /// TX-38's refusal that reads the tab. Main thread.
    static func checkFind(_ find: TranscriptFindArguments, _ pane: TranscriptPane) throws {
        if find.step != nil, find.find == nil, !pane.isFindOpen {
            throw ToolError(
                message: "find_step steps an open find bar: pass find, or Edit ▸ Find… first.")
        }
    }

    /// Applies `find`, then `find_step`. Main thread.
    static func applyFind(_ find: TranscriptFindArguments, _ pane: TranscriptPane) {
        if let wanted = find.find {
            if let text = wanted {
                pane.openFind()
                pane.findBand.type(text)
            } else {
                pane.closeFind()
            }
        }
        if let step = find.step { pane.findStep(step) }
    }

    /// The answer's `find`: null while the bar is closed. Main thread.
    static func findAnswer(_ pane: TranscriptPane) -> Any {
        guard pane.isFindOpen else { return NSNull() }
        let state = pane.find
        return [
            "query": pane.findBand.query,
            "count": state.matches.count,
            "current": state.current ?? NSNull(),
            "matches": state.matches.prefix(200).map {
                ["first": $0.tokens.lowerBound, "last": $0.tokens.upperBound]
            },
            "label": pane.findBand.countText,
            "field_first_responder": pane.findFieldHasKeys(in: pane.window),
            "current_visible": pane.transcriptView.findCurrentVisible,
        ] as [String: Any]
    }

    static let transcriptFindProperties: [String: Any] = [
        "find": [
            "type": ["string", "null"],
            "description": "The find bar (spec §11 TX-37): a string opens it as Edit ▸ Find… "
                + "does, its field first responder, and sets the field's text as typing does; "
                + "null closes it as Esc does.",
        ],
        "find_step": [
            "type": "string", "enum": ["next", "previous"],
            "description": "Presses Return's (next) or ⇧Return's (previous) path once, after "
                + "find; refused while the find bar is closed.",
        ],
    ]

    static let transcriptFindProse =
        " Then find, then find_step (spec §11 TX-38): the answer's find is null while the find "
        + "bar is closed, else {query, count, current: the current match's index or null, "
        + "matches: the first 200 as [{first, last}] token indices, label: the bar's count, "
        + "field_first_responder, current_visible}. Also refused: find_step while the bar is "
        + "closed or with find: null, and a find_step that is neither next nor previous."
}
#endif
