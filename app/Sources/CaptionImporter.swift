import AppKit
import UniformTypeIdentifiers

/// File ▸ Import Captions… — a SubRip (`.srt`) file becomes TEXT CLIPS on a
/// track of their own (road map Phase 6, "SRT captions").
///
/// **Why text clips rather than a caption model.** Burn-in then costs
/// nothing: a text clip already draws through `LayerRenderers`, already
/// composites through `Compositor.metal` and already exports through the
/// same pass, so an imported caption shows up in the preview, in
/// `render_frame` and in the written movie without one line of export code.
/// It also leaves every caption editable with the tools that already exist —
/// drag one to retime it, select the lot and restyle them in the Text pane —
/// which a parallel caption model would have had to earn back one command at
/// a time. The cost is that captions are not a switchable soft-subtitle
/// track; §1 does not ask for one.
///
/// **The grammar.** SubRip is blocks separated by blank lines:
///
/// ```
/// 1
/// 00:00:04,120 --> 00:00:06,480
/// Two lines of
/// caption text.
/// ```
///
/// Handled here, because every one of them is in files people actually have:
/// a UTF-8 BOM, CRLF or bare-CR line endings, a missing index line, the
/// comma decimal separator (and the dot some tools write instead), the
/// `HH:MM:SS` / `MM:SS` shorthands, cue-position settings trailing the end
/// timestamp, `<i>`/`<b>`/`<font>` inline tags and `{\an8}` overrides, the
/// handful of HTML entities, and text encoded as UTF-16 or Windows-1252
/// rather than UTF-8.
///
/// **Malformed entries are reported, never silently dropped** — the parser
/// keeps the line number of every block it refused and the caller shows
/// them. A caption file half of which vanished without a word is worse than
/// one that did not import.
///
/// Times snap to the canvas frame grid like every other time in this app
/// (spec §5.1), which is also why a caption may end up one frame shorter
/// than the file says.
///
/// **What is here is the SubRip grammar and nothing else.** Everything from
/// the frame grid onwards — snapping, the overlap trim, the Caption preset,
/// the new front-most track and the probe that learns the new clips' ids —
/// is `CaptionLayout`, so `Transcriber.swift` lays a transcript out exactly
/// as a file is laid out. `plan(for:in:track:)` below is the whole seam:
/// read, parse, hand the cues over, rewrap the error with the file's name.
enum CaptionImporter {

    // MARK: - What a file parses into

    /// One cue as WRITTEN — before the frame grid, before overlap fixing.
    struct Cue: Equatable {
        /// The file's own numbering, when the block carried one. Kept only
        /// so a message can name the entry the way the file does.
        let index: Int?
        /// 1-based line of the block's timing line, for problem messages.
        let line: Int
        let start: Ticks
        let end: Ticks
        let text: String
    }

    /// A block the parser refused, or a cue placement gave up on — the
    /// shared type, whose `tag` this file always spells `"line <n>"`, so
    /// `description` reads `"line 12: no caption text"` exactly as it did
    /// when the line number was a field of its own.
    typealias Problem = CaptionLayout.Problem

    /// What an import will do, before anything is applied. The layout's, so
    /// a transcript and a file produce the same shape of answer.
    typealias Plan = CaptionLayout.Plan

    /// A refusal naming the line it came from.
    private static func problem(line: Int, reason: String) -> Problem {
        Problem(tag: "line \(line)", reason: reason)
    }

    struct ParsedFile: Equatable {
        let cues: [Cue]
        let problems: [Problem]
    }

    /// What one block parsed to. `Result` would want `Problem` to conform to
    /// `Error`, and a problem is something to REPORT, not something to
    /// throw — the parser keeps going past every one of them.
    private enum Block {
        case cue(Cue)
        case problem(Problem)
    }

    /// Why an import produced nothing. Every case carries the file, because
    /// an agent may have named a path the user never saw — which is also why
    /// `CaptionLayout.LayoutError`, whose producer is not always a file, is
    /// caught and rewrapped into these rather than thrown through.
    enum CaptionError: LocalizedError {
        case unreadable(URL)
        case noCues(URL, [Problem])
        case refused(URL)
        case tooMany(URL, cues: Int, room: Int)

        var errorDescription: String? {
            switch self {
            case .unreadable(let url):
                return "“\(url.lastPathComponent)” could not be read as text."
            case .noCues(let url, let problems):
                let detail = problems.prefix(3).map { $0.description }.joined(separator: "; ")
                return "No captions could be read from “\(url.lastPathComponent)”."
                    + (detail.isEmpty ? "" : " \(detail).")
            case .refused(let url):
                return "The captions in “\(url.lastPathComponent)” could not be placed on the "
                    + "timeline."
            case .tooMany(let url, let cues, let room):
                return "“\(url.lastPathComponent)” holds \(cues) captions, more than this "
                    + "project has room for: \(room) more clip\(room == 1 ? "" : "s") would "
                    + "fit, out of \(Int(RC_MAX_CLIPS))."
            }
        }
    }

    // MARK: - Reading

    /// The types File ▸ Import Captions… offers. `.srt` is not a registered
    /// system type, so `UTType(filenameExtension:)` mints the same dynamic
    /// type a `.srt` file on disk is itself given — which is what makes the
    /// filter match it — and the text types ride along for a caption file
    /// some other app has claimed.
    static var contentTypes: [UTType] {
        var types: [UTType] = [.plainText, .text]
        if let srt = UTType(filenameExtension: "srt") { types.insert(srt, at: 0) }
        return types
    }

    /// The file's text. UTF-8 first (what every modern tool writes), then
    /// UTF-16 for a file with a wide BOM, then the two single-byte encodings
    /// a subtitle file off a DVD rip is likely to be in. Latin-1 maps all
    /// 256 bytes, so the last arm never fails on a file that exists —
    /// mojibake is a better answer here than a refusal, since the timing
    /// lines are ASCII either way.
    static func text(of url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url) else { throw CaptionError.unreadable(url) }
        for encoding in [String.Encoding.utf8, .utf16, .windowsCP1252, .isoLatin1] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        throw CaptionError.unreadable(url)
    }

    // MARK: - Parsing

    /// Splits the file into blocks on blank lines and parses each one. A
    /// block that is not a cue becomes a `Problem` naming its first line;
    /// parsing never stops at the first bad block, because one broken entry
    /// in a thousand-line file must not cost the other 999.
    static func parse(_ raw: String) -> ParsedFile {
        let lines = normalized(raw).components(separatedBy: "\n")
        var cues: [Cue] = []
        var problems: [Problem] = []
        var index = 0
        while index < lines.count {
            while index < lines.count, isBlank(lines[index]) { index += 1 }
            guard index < lines.count else { break }
            let first = index
            var block: [String] = []
            while index < lines.count, !isBlank(lines[index]) {
                block.append(lines[index])
                index += 1
            }
            switch cue(from: block, firstLine: first + 1) {
            case .cue(let cue): cues.append(cue)
            case .problem(let problem): problems.append(problem)
            }
        }
        return ParsedFile(cues: cues, problems: problems)
    }

    /// One block. The timing line is found by searching for `-->` rather
    /// than by counting lines, which is what makes the index line optional
    /// — plenty of tools omit it.
    private static func cue(from block: [String], firstLine: Int) -> Block {
        guard let offset = block.firstIndex(where: { $0.contains("-->") }) else {
            return .problem(
                problem(line: firstLine, reason: "no “-->” timing line in this entry"))
        }
        let timingLine = firstLine + offset
        if offset > 1 {
            return .problem(
                problem(line: firstLine, reason: "\(offset) lines before the timing line"))
        }
        let number = offset == 1 ? Int(block[0].trimmingCharacters(in: .whitespaces)) : nil

        let halves = block[offset].components(separatedBy: "-->")
        guard halves.count == 2 else {
            return .problem(problem(line: timingLine, reason: "two “-->” in one timing line"))
        }
        guard let start = ticks(fromTimestamp: halves[0]) else {
            return .problem(
                problem(
                    line: timingLine,
                    reason: "“\(trimmed(halves[0]))” is not a HH:MM:SS,mmm time"))
        }
        guard let end = ticks(fromTimestamp: halves[1]) else {
            return .problem(
                problem(
                    line: timingLine,
                    reason: "“\(trimmed(halves[1]))” is not a HH:MM:SS,mmm time"))
        }
        guard end > start else {
            return .problem(problem(line: timingLine, reason: "ends at or before it starts"))
        }

        let body = block.dropFirst(offset + 1).map { plainText($0) }
        let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .problem(problem(line: timingLine, reason: "no caption text"))
        }
        return .cue(Cue(index: number, line: timingLine, start: start, end: end, text: text))
    }

    /// One SubRip timestamp. Accepts `HH:MM:SS,mmm`, the dot some tools
    /// write instead of the comma, the `MM:SS` and `SS` shorthands, and any
    /// number of fraction digits; ignores whatever follows the timestamp,
    /// which is where SubRip's optional position settings (`X1:… X2:…`)
    /// live. Arithmetic is integer throughout so a timestamp lands on the
    /// tick the file meant rather than near it.
    static func ticks(fromTimestamp text: String) -> Ticks? {
        guard let token = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).first
        else { return nil }
        let parts = token.replacingOccurrences(of: ",", with: ".")
            .split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 1, parts.count <= 3 else { return nil }

        var seconds: Ticks = 0
        for part in parts.dropLast() {
            guard let value = wholeNumber(part) else { return nil }
            seconds = seconds * 60 + value
        }
        guard let lastPart = parts.last else { return nil }
        let halves = lastPart.split(separator: ".", omittingEmptySubsequences: false)
        guard halves.count <= 2, let whole = wholeNumber(halves[0]) else { return nil }
        seconds = seconds * 60 + whole
        // A day of captions is 86 400 s; the cap is only here so the
        // multiplication below cannot overflow on a garbage timestamp.
        guard seconds >= 0, seconds <= 1_000_000 else { return nil }

        var total = seconds * ReelTime.perSecond
        if halves.count == 2 {
            let digits = halves[1]
            guard digits.count <= 9, let value = wholeNumber(digits) else { return nil }
            var scale: Ticks = 1
            for _ in 0..<digits.count { scale *= 10 }
            total += (ReelTime.perSecond * value + scale / 2) / scale
        }
        return total
    }

    /// A run of ASCII digits as a number — `Int64.init` would also accept a
    /// sign and Unicode digits, neither of which is a timestamp.
    private static func wholeNumber(_ text: Substring) -> Ticks? {
        guard !text.isEmpty, text.count <= 18,
              text.allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }
        return Ticks(text)
    }

    /// Strips the inline markup SubRip carries — `<i>`, `<b>`, `<u>`,
    /// `<font …>` and the ASS `{\an8}` overrides — and decodes the entities
    /// that come with it. The model has one plain string per text clip
    /// (spec §5.2), so markup that cannot be honoured is removed rather than
    /// shown as angle brackets on the canvas.
    private static func plainText(_ raw: String) -> String {
        var out = ""
        var index = raw.startIndex
        while index < raw.endIndex {
            let character = raw[index]
            let rest = raw[raw.index(after: index)...]
            if character == "<", let close = rest.firstIndex(of: ">"),
               looksLikeTag(rest[rest.startIndex..<close]) {
                index = raw.index(after: close)
                continue
            }
            if character == "{", let close = rest.firstIndex(of: "}"),
               rest[rest.startIndex..<close].first == "\\" {
                index = raw.index(after: close)
                continue
            }
            out.append(character)
            index = raw.index(after: index)
        }
        return decodeEntities(out)
    }

    /// `<i>` and `</font>` are markup; `<<` and `a < b` are text. The test
    /// is the one HTML itself uses: a tag opens with a letter, or with a
    /// slash and a letter.
    private static func looksLikeTag(_ body: Substring) -> Bool {
        guard let first = body.first else { return false }
        if first == "/" { return body.dropFirst().first?.isLetter == true }
        return first.isLetter
    }

    /// `&amp;` last, or every other decoded entity would be decoded twice.
    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = text
        for (entity, character) in [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"),
            ("&#39;", "'"), ("&nbsp;", " "), ("&amp;", "&"),
        ] {
            out = out.replacingOccurrences(of: entity, with: character)
        }
        return out
    }

    /// A leading BOM survives `String(data:encoding:.utf8)` as U+FEFF, and
    /// left in place it makes the first block's index line unparseable.
    private static func normalized(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Placement

    /// Everything an import will do, computed against `project` and applied
    /// by nobody: the UI commits it through `ProjectDocument`, the agent
    /// through `AgentServer.editResult`.
    ///
    /// The whole of the placement is `CaptionLayout.place` — this is the
    /// SubRip half handing its cues over, and the file name being put back
    /// into the refusals so the alert and the tool's error string say which
    /// file they are about.
    ///
    /// `track` places on an existing track; absent, the captions get a new
    /// front-most track of their own, which is the only placement that can
    /// never be refused by the overlap rule.
    static func plan(for url: URL, in project: ReelProject, track: UInt32? = nil) throws -> Plan {
        let parsed = parse(try text(of: url))
        guard !parsed.cues.isEmpty else {
            throw CaptionError.noCues(url, parsed.problems)
        }
        let cues = parsed.cues.map {
            CaptionLayout.Cue(start: $0.start, end: $0.end, text: $0.text, tag: "line \($0.line)")
        }
        do {
            return try CaptionLayout.place(
                cues, problems: parsed.problems, in: project, track: track)
        } catch let error as CaptionLayout.LayoutError {
            switch error {
            case .noCues(let problems): throw CaptionError.noCues(url, problems)
            case .refused: throw CaptionError.refused(url)
            case .tooMany(let cues, let room):
                throw CaptionError.tooMany(url, cues: cues, room: room)
            }
        }
    }
}

// MARK: - The menu command

/// File ▸ Import Captions…, mirrored by the agent's `import_captions`
/// (`AgentServer+Media.swift`).
extension EditorViewController {

    /// The open panel, then the import. Both the panel's completion and the
    /// alert that follows it are OFF-EVENT, which is why the edit goes
    /// through `performGroupedEdit` (app/CLAUDE.md's undo pitfall).
    func importCaptionsCommand() {
        guard let document = document, let window = view.window else {
            NSSound.beep()
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = CaptionImporter.contentTypes
        panel.message = "Choose a SubRip (.srt) caption file."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importCaptions(from: url, into: document, in: window)
        }
    }

    private func importCaptions(from url: URL, into document: ProjectDocument, in window: NSWindow)
    {
        let plan: CaptionImporter.Plan
        do {
            // **The EDITED project, not the document.** A caption plan
            // measures a placement — the frame grid, the overlap trim, the
            // new front-most track — and road map 2's phase 9 addresses the
            // ops it produces to whatever nest is open. Reading the document
            // here and writing into the nest there is one gesture computing
            // against one container and landing in another, which is the
            // shape `SilenceDetector` and `AudioNormalize` were moved off
            // in the same phase. A producer reads the container it writes.
            plan = try CaptionImporter.plan(for: url, in: document.editedProject)
        } catch {
            let alert = NSAlert(error: error)
            alert.beginSheetModal(for: window, completionHandler: nil)
            return
        }
        document.performGroupedEdit("Import Captions", plan.ops)
        guard !plan.report.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText =
            "Imported \(plan.clips) caption\(plan.clips == 1 ? "" : "s") from "
            + "“\(url.lastPathComponent)”."
        alert.informativeText = plan.report
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
}
