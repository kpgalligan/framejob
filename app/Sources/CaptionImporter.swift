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

    /// A block the parser refused, or a cue placement gave up on.
    struct Problem: Equatable {
        let line: Int
        let reason: String

        var description: String { "line \(line): \(reason)" }
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

    /// What an import will do, before anything is applied: the ops, and
    /// everything the caller has to tell the user about.
    struct Plan {
        /// One `add_track` (unless placing on an existing track), one
        /// `add_text_clip` per surviving cue, and one `set_video` putting
        /// the whole batch where the Caption preset lives.
        let ops: [ReelOp]
        /// Clips this plan really creates — smaller than `cues` if the core
        /// refused a placement on a track the caller chose.
        let clips: Int
        /// Cues that survived parsing and placement.
        let cues: Int
        /// Cues shortened because the next one started before they ended.
        let trimmed: Int
        let problems: [Problem]
        /// The name of the track created for these captions; nil when the
        /// caller named a track to place them on instead.
        let trackName: String?

        /// The human report: what was adjusted and what was skipped. Empty
        /// when the file imported cleanly, which is the signal to say
        /// nothing at all.
        var report: String {
            var lines: [String] = []
            if trimmed > 0 {
                lines.append(
                    "\(trimmed) caption\(trimmed == 1 ? "" : "s") overlapped the next one and "
                        + "\(trimmed == 1 ? "was" : "were") shortened to fit.")
            }
            if !problems.isEmpty {
                lines.append(
                    "\(problems.count) entr\(problems.count == 1 ? "y was" : "ies were") "
                        + "skipped:")
                lines.append(contentsOf: problems.prefix(8).map { "    • " + $0.description })
                if problems.count > 8 {
                    lines.append("    • …and \(problems.count - 8) more.")
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Why an import produced nothing. Every case carries the file, because
    /// an agent may have named a path the user never saw.
    enum CaptionError: LocalizedError {
        case unreadable(URL)
        case noCues(URL, [Problem])
        case refused(URL)

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
                Problem(line: firstLine, reason: "no “-->” timing line in this entry"))
        }
        let timingLine = firstLine + offset
        if offset > 1 {
            return .problem(
                Problem(line: firstLine, reason: "\(offset) lines before the timing line"))
        }
        let number = offset == 1 ? Int(block[0].trimmingCharacters(in: .whitespaces)) : nil

        let halves = block[offset].components(separatedBy: "-->")
        guard halves.count == 2 else {
            return .problem(Problem(line: timingLine, reason: "two “-->” in one timing line"))
        }
        guard let start = ticks(fromTimestamp: halves[0]) else {
            return .problem(
                Problem(
                    line: timingLine,
                    reason: "“\(trimmed(halves[0]))” is not a HH:MM:SS,mmm time"))
        }
        guard let end = ticks(fromTimestamp: halves[1]) else {
            return .problem(
                Problem(
                    line: timingLine,
                    reason: "“\(trimmed(halves[1]))” is not a HH:MM:SS,mmm time"))
        }
        guard end > start else {
            return .problem(Problem(line: timingLine, reason: "ends at or before it starts"))
        }

        let body = block.dropFirst(offset + 1).map { plainText($0) }
        let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .problem(Problem(line: timingLine, reason: "no caption text"))
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

    /// A cue once the frame grid and its neighbours have had their say.
    private struct Placed {
        let line: Int
        let start: Ticks
        var end: Ticks
        let text: String
    }

    /// The Caption preset of §4.2 — the same row the Text pane's Presets
    /// section applies, looked up by name so the two cannot drift. The
    /// fallback is that row's own values, and exists only so a rename in
    /// `TextPane` is a wrong style rather than a crash.
    static var captionPreset: TextPreset {
        TextPreset.all.first { $0.name == "Caption" }
            ?? TextPreset(
                name: "Caption", font: "SourceSans3-Regular", sizeFraction: 0.035, xFraction: 0,
                yFraction: 0.38, align: "center",
                backdrop: BackdropProps(color: [0, 0, 0, 0.6], padding: 12, radius: 8))
    }

    /// How much of the canvas width a caption may fill before it wraps.
    /// Unlike the Text pane's presets this plan DOES fix a box width: a
    /// caption's words come out of a file rather than from someone watching
    /// the canvas, so a long line has to wrap itself.
    private static let wrapFraction = 0.8

    /// Everything an import will do, computed against `project` and applied
    /// by nobody: the UI commits it through `ProjectDocument`, the agent
    /// through `AgentServer.editResult`.
    ///
    /// `track` places on an existing track; absent, the captions get a new
    /// front-most track of their own, which is the only placement that can
    /// never be refused by the overlap rule.
    static func plan(for url: URL, in project: ReelProject, track: UInt32? = nil) throws -> Plan {
        let parsed = parse(try text(of: url))
        let snapshot = project.snapshot
        let canvas = snapshot.canvas
        let frame = max(canvas.fps.frameDuration, 1)
        guard !parsed.cues.isEmpty else {
            throw CaptionError.noCues(url, parsed.problems)
        }

        // Snap, then give a cue that snapped to nothing its one frame back,
        // THEN resolve overlaps — in that order, so an overlap the minimum
        // length introduces is still one the overlap pass fixes.
        var placed = parsed.cues.map { cue -> Placed in
            let start = ReelTime.snapToFrame(max(0, cue.start), fps: canvas.fps)
            let end = ReelTime.snapToFrame(cue.end, fps: canvas.fps)
            return Placed(line: cue.line, start: start, end: max(end, start + frame),
                          text: cue.text)
        }
        placed.sort { $0.start == $1.start ? $0.line < $1.line : $0.start < $1.start }

        // Captions are one track, so two cues on screen at once cannot both
        // be honoured: the later one wins its start and the earlier one is
        // cut back to it. That is also what the overlap rule (§6) would
        // otherwise refuse the placement over.
        var trimmed = 0
        for index in placed.indices.dropLast() where placed[index].end > placed[index + 1].start {
            placed[index].end = placed[index + 1].start
            trimmed += 1
        }
        var problems = parsed.problems
        for cue in placed where cue.end - cue.start < frame {
            problems.append(
                Problem(line: cue.line, reason: "starts less than a frame before the next caption"))
        }
        let kept = placed.filter { $0.end - $0.start >= frame }
        guard !kept.isEmpty else { throw CaptionError.noCues(url, problems) }

        var ops: [ReelOp] = []
        let destination: UInt32
        let name = trackName(in: snapshot)
        if let track = track {
            destination = track
        } else {
            // A new id is `next_id` from BEFORE the op — the documented
            // contract of the one JSON entry point (§6), since an op returns
            // a project rather than an id. Index `tracks.count` is the front
            // of the stack, so captions draw over everything.
            destination = snapshot.nextId
            ops.append(.addTrack(index: snapshot.tracks.count, name: name))
        }

        let preset = captionPreset
        let height = Double(canvas.height)
        var base = TextPatch(
            font: preset.font, size: (height * preset.sizeFraction).rounded(),
            align: preset.align, valign: "middle", backdrop: .some(preset.backdrop),
            width: .some(Double(canvas.width) * wrapFraction))
        for cue in kept {
            base.content = cue.text
            ops.append(
                .addTextClip(
                    track: destination, at: cue.start, duration: cue.end - cue.start, text: base))
        }

        // The preset's position is a `set_video` patch, and a patch needs
        // ids the ops have not minted yet — so the batch is applied PURELY
        // first and the ids read off the throwaway result. Applying the same
        // ops to the same handle mints the same ids, which is what makes
        // appending the patch to this very list correct
        // (`EditorViewController+AddClips.swift` does the same for one clip).
        guard let probed = try project.applying(ops) else { throw CaptionError.refused(url) }
        let before = Set(snapshot.clips.map { $0.id })
        let created = probed.snapshot.clips.map { $0.id }.filter { !before.contains($0) }
        guard !created.isEmpty else { throw CaptionError.refused(url) }
        ops.append(
            .setVideo(
                clips: created,
                patch: VideoPatch(
                    x: preset.xFraction * Double(canvas.width), y: preset.yFraction * height,
                    opacity: 1)))

        return Plan(
            ops: ops, clips: created.count, cues: kept.count, trimmed: trimmed,
            problems: problems, trackName: track == nil ? name : nil)
    }

    /// "Captions", then "Captions 2" — so two imported files are tellable
    /// apart in the track header.
    private static func trackName(in snapshot: ProjectSnapshot) -> String {
        let taken = Set(snapshot.tracks.map { $0.name })
        var name = "Captions"
        var suffix = 2
        while taken.contains(name) {
            name = "Captions \(suffix)"
            suffix += 1
        }
        return name
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
            plan = try CaptionImporter.plan(for: url, in: document.project)
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
