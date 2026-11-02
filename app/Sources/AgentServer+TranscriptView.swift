import AppKit

#if FRAMEJOB_DEV_TOOLS
/// `transcript_view` — a dev tool (road map "creator-jobs" TX2a, spec §11
/// TX-23): what a window's Transcript tab shows, and the three things a
/// person does there that a proof needs — focus the view, select words, and
/// click one (the mouse's own path, `TranscriptView.click(token:)`). Since
/// TX2b (TX-27) it also sets the bar's Words from and Language and presses
/// its Read, and presses its Stop LATER (`stop_after`): every tool call holds
/// `AgentLane`'s one lock, so no call could press Stop while
/// `get_timeline_transcript` waits. Since TX3a (TX-23 amended by TX-31) each
/// token carries the tab's `cut_start`/`cut_end` (`TranscriptCut.wordCut`
/// over the tab's `cutTable()`), and `cut` is the selection's plan. Since
/// TX3b (TX-34) it clicks a pause token (`select_pause`, the mouse's
/// `TranscriptView.clickPause`) and answers the pauses shown, the selected
/// one and, with one selected, its plan as `cut`.
///
/// **It runs on the SERVER thread** (`devOffMainTools`) so `wait` may poll
/// the tab's source until it is settled; every step is an `onMain` hop.
/// Arguments are read and refused before anything moves, and so are a
/// project with no window and a tab that is not shown.
extension AgentServer {

    /// Each pane's last `stop_after`: "pending", "pressed" or "not shown".
    /// Main only.
    private static let stopAfters = NSMapTable<TranscriptPane, NSString>.weakToStrongObjects()

    func transcriptView(_ a: [String: Any]) throws -> String {
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "transcript_view must run on the server thread — its name is missing "
                    + "from AgentServer.devOffMainTools.")
        }
        let focus = try boolArg(a, "focus") ?? false
        let click = try intArg(a, "click")
        let selectPause = try intArg(a, "select_pause")
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
        if selectPause != nil, select != nil || click != nil {
            throw ToolError(message: "select, click and select_pause each set the selection: pass one.")
        }
        let bar = try transcriptBarArguments(a)
        if select != nil || click != nil || selectPause != nil,
            bar.wordsFrom != nil || bar.language != nil
        {
            throw ToolError(
                message: "select, click and select_pause name tokens of the view as it is; set "
                    + "words_from or language in a call of their own.")
        }
        if bar.read, bar.wordsFrom != nil || bar.language != nil {
            throw ToolError(
                message: "read presses the bar as it is; set words_from or language in a call "
                    + "of their own.")
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
            let shownPauses = view.pauses.count
            if let selectPause, !(0..<shownPauses).contains(selectPause) {
                throw ToolError(
                    message: "select_pause names pause \(selectPause); the tab shows \(shownPauses).")
            }
            try Self.checkBar(bar, pane)
            if let track = bar.wordsFrom { pane.bar.chooseWordsFrom(track) }
            if let language = bar.language { pane.bar.chooseLanguage(language) }
            if bar.read { pane.bar.pressRead() }
            if focus { view.window?.makeFirstResponder(view) }
            if let select { view.select(select.map { $0[0]...$0[1] }) }
            if let click { view.click(token: click) }
            if let selectPause { view.clickPause(selectPause) }
            return pane
        }
        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline, !(onMain { pane.source.settled }) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return try onMain {
            let document = try self.target(a)
            if let seconds = bar.stopAfter {
                Self.stopAfters.setObject("pending", forKey: pane)
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak pane] in
                    guard let pane else { return }
                    let shown = pane.bar.stopShown
                    if shown { pane.bar.pressStop() }
                    Self.stopAfters.setObject(shown ? "pressed" : "not shown", forKey: pane)
                }
            }
            return try self.jsonResult(self.transcriptAnswer(pane, document))
        }
    }

    /// The bar's arguments as read (TX-27): `wordsFrom` and `language` are
    /// `.some(nil)` for an explicit null (All tracks, Automatic).
    private struct TranscriptBarArguments {
        var wordsFrom: UInt32??
        var language: String??
        var stopAfter: Double?
        var read = false
    }

    /// The bar's arguments, read on the server thread: the language through
    /// `checkSpelling` and then `transcriptionLanguage`, which may block.
    private func transcriptBarArguments(_ a: [String: Any]) throws -> TranscriptBarArguments {
        var bar = TranscriptBarArguments()
        if let raw = a["words_from"] {
            if raw is NSNull {
                bar.wordsFrom = .some(nil)
            } else {
                guard let track = UInt32(exactly: try intArg(a, "words_from") ?? -1) else {
                    throw ToolError(message: "words_from must be a track id or null.")
                }
                bar.wordsFrom = .some(track)
            }
        }
        if let raw = a["language"] {
            if raw is NSNull {
                bar.language = .some(nil)
            } else {
                let wanted = try stringArg(a, "language")
                try Self.checkSpelling(of: wanted)
                bar.language = .some(try Self.transcriptionLanguage(wanted).identifier)
            }
        }
        if let seconds = try doubleArg(a, "stop_after") {
            guard (0...60).contains(seconds) else {
                throw ToolError(message: "stop_after must be 0…60 seconds (got \(seconds)).")
            }
            bar.stopAfter = seconds
        }
        bar.read = try boolArg(a, "read") ?? false
        return bar
    }

    /// TX-27's refusals that read the tab. Main thread.
    private static func checkBar(_ bar: TranscriptBarArguments, _ pane: TranscriptPane) throws {
        let source = pane.source!
        if let wanted = bar.wordsFrom, let track = wanted,
            !source.tracks.contains(where: { $0.id == track })
        {
            let listed = ["All tracks (null)"] + source.tracks.map { "\($0.name) (\($0.id))" }
            throw ToolError(
                message: "words_from names track \(track); Words from lists "
                    + listed.joined(separator: ", ") + ".")
        }
        if bar.stopAfter != nil, !pane.bar.stopShown {
            throw ToolError(message: "Stop is not shown: the tab is not reading on this Mac.")
        }
        if bar.read, !pane.bar.readShown {
            throw ToolError(message: "Read is not shown: the tab's reading was not stopped.")
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
        let container = document.editedProject.snapshot
        let canvas = container.canvas
        let table = source.cutTable()
        let total = ShotSplit.clipCount(document.project.snapshot)
        let pauseCut: [String: Any]? = view.pauseSelection.map { index in
            let plan = TranscriptCut.planPause(
                view.pauses[index], table: table, container: container, total: total)
            return [
                "pause": index, "start": plan.range.start, "end": plan.range.end,
                "clips_after": plan.clipsAfter, "clips_peak": plan.clipsPeak,
                "refusal": plan.refusal?.sentence ?? NSNull(),
            ]
        }
        let cut: Any = pauseCut ?? view.selection.map { selection -> [String: Any] in
            let plan = TranscriptCut.plan(
                selection, table: table, container: container, total: total, fps: canvas.fps)
            return [
                "selection": [plan.selection.lowerBound, plan.selection.upperBound],
                "start": plan.range.start, "end": plan.range.end, "clips_after": plan.clipsAfter,
                "clips_peak": plan.clipsPeak, "refusal": plan.refusal?.sentence ?? NSNull(),
            ]
        } ?? NSNull()
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
        case .stopped: status = "stopped"
        }
        return [
            "ok": true,
            "settled": source.settled,
            "tokens": model.tokens.map { token -> [String: Any] in
                var row = Self.wordRow(
                    token.word,
                    cut: TranscriptCut.wordCut(
                        token.index, table: table, container: container, fps: canvas.fps))
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
            "cut": cut,
            "pauses": view.pauses.enumerated().map { index, pause -> [String: Any] in
                [
                    "index": index, "after": pause.after, "start": pause.span.start,
                    "end": pause.span.end, "cut_start": pause.cut.start, "cut_end": pause.cut.end,
                ]
            },
            "pause_selection": view.pauseSelection ?? NSNull(),
            "first_responder": view.window?.firstResponder === view,
            "fill": fill,
            "owns_want": source.ownsWant,
            "status": status,
            "status_text": TranscriptBar.statusText(source.status) ?? [],
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
            "bar": [
                "words_from": source.wordsFrom.map { Int($0) } ?? NSNull(),
                "tracks": source.tracks.map { ["id": Int($0.id), "name": $0.name] as [String: Any] },
                "language": source.language ?? NSNull(),
                "languages": (source.languages ?? []).map {
                    ["identifier": $0.identifier, "name": $0.displayName]
                },
                "stop_shown": pane.bar.stopShown,
                "read_shown": pane.bar.readShown,
                "stop_after": Self.stopAfters.object(forKey: pane).map { $0 as String } ?? NSNull(),
            ] as [String: Any],
            "project": summary(document),
        ]
    }

    // MARK: - Catalog

    func transcriptViewTool() -> [String: Any] {
        tool(
            "transcript_view",
            "DEV TOOL (absent from Distribution builds). What a project's Transcript tab shows "
                + "(spec §11 TX-23, TX-27), after optionally setting its bar's Words from and "
                + "Language, pressing its Read, focusing its view, selecting tokens and clicking "
                + "one or a pause token as a person would. Applies words_from, then language, "
                + "then read, then focus, then select, then click or select_pause; schedules "
                + "stop_after's press of the bar's Stop that many seconds after the answer; then waits up to wait seconds for the "
                + "tab's source to settle (no load, fill or pending media left). Answers settled, "
                + "tokens (get_timeline_transcript's word rows, cut_start and cut_end the tab's "
                + "own, plus index, paragraph and struck), paragraphs {index, start, timecode, "
                + "first_token}, highlight, playhead, playing, selection, cut (null with no "
                + "selection, else the selection's plan: {selection [first, last] widened, start, "
                + "end, clips_after, clips_peak, refusal: the sentence Delete would refuse with, "
                + "or null}; with a pause selected {pause, start, end, clips_after, clips_peak, "
                + "refusal}), pauses (the pause tokens shown, [{index, after: the token before "
                + "it, start, end: the silence, cut_start, cut_end: what Delete cuts}]), "
                + "pause_selection (an index or null), first_responder, fill {media, fraction} or null, owns_want, status "
                + "(idle, loading, reading, no_model, failed or stopped) with status_text, "
                + "no_words, notes, rebuilds, last_rebuild_ms, top_token, bar {words_from, "
                + "tracks [{id, name}], language, languages [{identifier, name}], stop_shown, "
                + "read_shown, stop_after: pending, pressed, not shown or null} and project. "
                + "Refused, changing nothing: a project with no window, a Transcript tab not "
                + "shown (select_inspector_tab first), an index past the tokens shown, a track "
                + "not in the container, a language not installed, a pause index past the "
                + "pauses shown, select_pause together with select or click, select, click or "
                + "select_pause together with words_from or language, read together with "
                + "words_from or language, "
                + "stop_after while Stop is not shown, and read while Read is not shown.",
            [
                "focus": [
                    "type": "boolean",
                    "description": "true makes the transcript view first responder, as a click "
                        + "in it does.",
                ],
                "select": [
                    "type": ["array", "null"], "items": ["type": "integer"],
                    "minItems": 2, "maxItems": 2,
                    "description": "[first, last] token indices, inclusive, to select as a "
                        + "person does (the selection widened, its cut made the in/out range); "
                        + "null clears the selection.",
                ],
                "click": [
                    "type": "integer", "minimum": 0,
                    "description": "A token index to click: it alone is selected and the "
                        + "playhead moves to its frame-snapped start, playback going on if it "
                        + "was playing.",
                ],
                "select_pause": [
                    "type": "integer", "minimum": 0,
                    "description": "A pause token's index (pauses[].index) to click: the word "
                        + "selection is cleared, the pause selected, its cut made the in/out range "
                        + "and the playhead moved to the cut's start.",
                ],
                "wait": [
                    "type": "number", "minimum": 0, "maximum": 60,
                    "description": "Seconds (0–60, default 0) to wait for the tab's source to "
                        + "settle before answering.",
                ],
                "words_from": [
                    "type": ["integer", "null"],
                    "description": "The bar's Words from: a track id of the edited container, "
                        + "or null for All tracks.",
                ],
                "language": [
                    "type": ["string", "null"],
                    "description": "The bar's Language: an installed recognition language "
                        + "(en-US, en, or its name), or null for Automatic, the Mac's default.",
                ],
                "stop_after": [
                    "type": "number", "minimum": 0, "maximum": 60,
                    "description": "Seconds (0–60) after the answer at which the bar's Stop is "
                        + "pressed through its own path; refused while Stop is not shown.",
                ],
                "read": [
                    "type": "boolean",
                    "description": "true presses the bar's Read, shown after Stop.",
                ],
            ])
    }
}
#endif
