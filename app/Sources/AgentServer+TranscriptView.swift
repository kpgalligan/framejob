import AppKit

#if FRAMEJOB_DEV_TOOLS
/// `transcript_view` — a dev tool (road map "creator-jobs" TX2a, spec §11
/// TX-23): what a window's Transcript tab shows, and the three things a
/// person does there that a proof needs — focus the view, select words, and
/// click one (the mouse's own path, `TranscriptView.click(token:)`).
///
/// **It runs on the SERVER thread** (`devOffMainTools`) so `wait` may poll
/// the tab's source until it is settled; every step is an `onMain` hop.
/// Arguments are read and refused before anything moves, and so are a
/// project with no window and a tab that is not shown.
extension AgentServer {

    func transcriptView(_ a: [String: Any]) throws -> String {
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "transcript_view must run on the server thread — its name is missing "
                    + "from AgentServer.devOffMainTools.")
        }
        let focus = try boolArg(a, "focus") ?? false
        let click = try intArg(a, "click")
        let wait = try doubleArg(a, "wait") ?? 0
        guard (0...60).contains(wait) else {
            throw ToolError(message: "wait must be 0…60 seconds (got \(wait)).")
        }
        var select: [Int]??
        if let raw = a["select"] {
            if raw is NSNull {
                select = .some(nil)
            } else {
                let pair = try intsArg(a, "select") ?? []
                guard pair.count == 2, pair[0] <= pair[1] else {
                    throw ToolError(
                        message: "select must be two token indices, first ≤ last, or null.")
                }
                select = .some(pair)
            }
        }

        let pane = try onMain { () throws -> TranscriptPane in
            let pane = try self.shownTranscriptPane(a)
            let view = pane.transcriptView
            let count = pane.source.model.tokens.count
            if let pair = select ?? nil, pair[1] >= count || pair[0] < 0 {
                throw ToolError(message: "select names token \(pair[1]); the tab shows \(count).")
            }
            if let click, !(0..<count).contains(click) {
                throw ToolError(message: "click names token \(click); the tab shows \(count).")
            }
            if focus { view.window?.makeFirstResponder(view) }
            if let select { view.select(select.map { $0[0]...$0[1] }) }
            if let click { view.click(token: click) }
            return pane
        }
        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline, !(onMain { pane.source.settled }) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return try onMain {
            let document = try self.target(a)
            return try self.jsonResult(self.transcriptAnswer(pane, document))
        }
    }

    /// The window's Transcript pane, refused when there is no window or the
    /// tab is not shown. Main thread.
    private func shownTranscriptPane(_ a: [String: Any]) throws -> TranscriptPane {
        let document = try target(a)
        guard let inspector = editor(document)?.inspector, inspector.isViewLoaded else {
            let name = Self.path(of: document) ?? document.displayName ?? "Untitled"
            throw ToolError(
                message: "The project \(name) has no window: transcript_view reaches the "
                    + "Transcript tab only through its editor window.")
        }
        guard inspector.tab == .transcript, let pane = TranscriptPane.pane(in: inspector),
            pane.isShown
        else {
            throw ToolError(message: "select_inspector_tab {tab: \"transcript\"} first.")
        }
        return pane
    }

    /// TX-23's answer. Main thread.
    private func transcriptAnswer(_ pane: TranscriptPane, _ document: ProjectDocument) -> [String: Any] {
        let source = pane.source!
        let view = pane.transcriptView
        let model = source.model
        let canvas = document.editedProject.snapshot.canvas
        let fill: Any = source.fillProgress.map {
            ["media": Int($0.media), "fraction": $0.fraction] as [String: Any]
        } ?? NSNull()
        let status: String
        switch source.status {
        case .idle: status = "idle"
        case .loading: status = "loading"
        case .reading: status = "reading"
        case .noModel: status = "no_model"
        case .failed: status = "failed"
        }
        return [
            "ok": true,
            "settled": source.settled,
            "tokens": model.tokens.map { token -> [String: Any] in
                var row = Self.wordRow(token.word)
                row["index"] = token.index
                row["paragraph"] = token.paragraph
                row["struck"] = token.struck
                return row
            },
            "paragraphs": model.paragraphs.map {
                [
                    "index": $0.index, "start": $0.start, "first_token": $0.firstToken,
                    "timecode": ReelTime.format($0.start, fps: canvas.fps, frames: canvas.timecodeFrames),
                ] as [String: Any]
            },
            "highlight": view.highlight ?? NSNull(),
            "playhead": document.playhead,
            "playing": editor(document)?.playback.isPlaying ?? false,
            "selection": view.selection.map { [$0.lowerBound, $0.upperBound] } ?? NSNull(),
            "first_responder": view.window?.firstResponder === view,
            "fill": fill,
            "owns_want": source.ownsWant,
            "status": status,
            "status_text": TranscriptPane.statusText(source.status) ?? [],
            "no_words": source.noWords.map {
                [
                    "clip": Int($0.clip), "nest_path": $0.nestPath.map { Int($0) },
                    "tag": $0.tag, "reason": $0.reason,
                ] as [String: Any]
            },
            "notes": source.notes,
            "rebuilds": source.rebuilds,
            "last_rebuild_ms": source.lastRebuildMilliseconds,
            "top_token": view.topVisibleToken() ?? NSNull(),
            "project": summary(document),
        ]
    }

    // MARK: - Catalog

    func transcriptViewTool() -> [String: Any] {
        tool(
            "transcript_view",
            "DEV TOOL (absent from Distribution builds). What a project's Transcript tab shows "
                + "(spec §11 TX-23), after optionally focusing its view, selecting tokens and "
                + "clicking one as a person would. Applies focus, then select, then click, then "
                + "waits up to wait seconds for the tab's source to settle (no load, fill or "
                + "pending media left). Answers settled, tokens (get_timeline_transcript's word "
                + "rows plus index, paragraph and struck), paragraphs {index, start, timecode, "
                + "first_token}, highlight, playhead, playing, selection, first_responder, fill "
                + "{media, fraction} or null, owns_want, status (idle, loading, reading, "
                + "no_model or failed) with status_text, no_words, notes, rebuilds, "
                + "last_rebuild_ms, top_token and project. Refused, changing nothing: a project "
                + "with no window, a Transcript tab not shown (select_inspector_tab first), and "
                + "an index past the tokens shown.",
            [
                "focus": [
                    "type": "boolean",
                    "description": "true makes the transcript view first responder, as a click "
                        + "in it does.",
                ],
                "select": [
                    "type": ["array", "null"], "items": ["type": "integer"],
                    "minItems": 2, "maxItems": 2,
                    "description": "[first, last] token indices, inclusive, to select; null "
                        + "clears the selection.",
                ],
                "click": [
                    "type": "integer", "minimum": 0,
                    "description": "A token index to click: it alone is selected and the "
                        + "playhead moves to its frame-snapped start, playback going on if it "
                        + "was playing.",
                ],
                "wait": [
                    "type": "number", "minimum": 0, "maximum": 60,
                    "description": "Seconds (0–60, default 0) to wait for the tab's source to "
                        + "settle before answering.",
                ],
            ])
    }
}
#endif
