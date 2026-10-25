import AppKit
import UniformTypeIdentifiers

/// File ▸ Export Captions… — the other direction of `CaptionImporter`: a
/// track of text clips written back out as SubRip (`.srt`) or WebVTT
/// (`.vtt`), mirrored by the agent's `export_captions`.
///
/// **A caption's times are a clip's times and nothing else.** That is what
/// `CaptionImporter`'s header doc bought by making a caption an ordinary text
/// clip: there is no caption model to read back, so this walks the chosen
/// track's clips in timeline order and writes `start`, `end` and
/// `text.content`. Retime a caption by dragging it and the export follows;
/// restyle it in the Text pane and the export does not care.
///
/// **The track is never guessed.** A candidate is a track that holds at least
/// one clip, every one of which is a text clip, and which yields at least one
/// non-empty cue — a shape clip has no `content` and would export as a blank
/// entry, and nothing in the model marks a track as "the caption track"
/// (`CaptionLayout.trackName` only mints a name, and a user may rename it).
/// With no candidate, or with more than one, this refuses and NAMES the
/// candidates, which is the posture `remove_media` and `export` already take
/// when an answer is not unique. The menu item offers the same list as a
/// popup in the save panel and pre-selects a single candidate.
///
/// **When a round trip is exact.** Import an SRT and export it and the cue
/// times come back byte for byte **exactly when the canvas frame duration is
/// a whole number of milliseconds** — and then only for cue times already on
/// the frame grid. `CaptionImporter` snaps every cue to that grid (spec §5.1)
/// and `format_timecode` rounds ticks to the nearest millisecond, so at 25 fps
/// (40 ms a frame) and 50 fps (20 ms) every snapped time is a whole number of
/// milliseconds and survives; at 30 fps a frame is 33⅓ ms and
/// `00:00:04,120` comes back as `00:00:04.133`. That is arithmetic, not a
/// defect, and a tolerance instead of a fixture at 25 fps would be a check
/// that passes against a build where this file did nothing.
///
/// **The two files are byte-siblings only up to a point.** WebVTT treats `<`
/// as markup and `&` as an entity introducer, so this escapes `&`, `<` and
/// `>` on the way out and SubRip does not (the importer strips tags on the way
/// in, so a literal `<` in a caption survives an `.srt` round trip and would
/// be swallowed by a VTT reader). For text containing none of the three, a
/// `.vtt` differs from the `.srt` of the same track by exactly three things:
/// the `WEBVTT` header, the missing index lines, and `.` where SubRip writes
/// `,` in a timestamp. Index lines are legal in WebVTT and omitted by every
/// writer, so they are omitted here.
///
/// **The exact shape written**, because a byte comparison needs it in words:
/// each entry is its index line (SubRip only), its timing line
/// `HH:MM:SS,mmm --> HH:MM:SS,mmm`, then its text lines; entries are separated
/// by one blank line; the file ends with a single newline. Line endings are
/// LF, not CRLF — every reader takes LF, and `CaptionImporter.normalized`
/// folds CRLF away on the way back in, so a round trip is unaffected.
enum CaptionExporter {

    // MARK: - Vocabulary

    /// The two containers. `rawValue` is the file extension, which is also
    /// how the format is derived from a path.
    enum Format: String, CaseIterable {
        case srt
        case vtt

        var displayName: String {
            switch self {
            case .srt: return "SubRip (.srt)"
            case .vtt: return "WebVTT (.vtt)"
            }
        }

        /// The decimal separator in a timestamp — the ONE difference between
        /// the two timing lines.
        var decimalSeparator: String {
            switch self {
            case .srt: return ","
            case .vtt: return "."
            }
        }

        /// The type the save panel filters on. `.srt` and `.vtt` are not
        /// registered system types, so `UTType(filenameExtension:)` mints the
        /// same dynamic type such a file on disk is itself given — the trick
        /// `CaptionImporter.contentTypes` already relies on.
        var contentType: UTType {
            UTType(filenameExtension: rawValue) ?? .plainText
        }
    }

    /// One cue as it will be written: project time, from a clip.
    struct Cue: Equatable {
        let start: Ticks
        let end: Ticks
        let text: String
    }

    /// A track this could be asked to write, and what it holds.
    struct Candidate: Equatable {
        let track: UInt32
        let name: String
        let cues: Int

        /// How a refusal names it.
        var description: String { "\(track) “\(name)” (\(cues) cue\(cues == 1 ? "" : "s"))" }

        /// How the save panel's popup names it, and the id is in there for the
        /// same reason `description` carries it: a track's name is neither
        /// unique nor fixed (`edit_track.rs` accepts any name and a track is
        /// renamed from its header, so two imported caption tracks renamed
        /// alike are ordinary), and two rows a person cannot tell apart are
        /// not a choice. It also keeps the row TITLES distinct, though the
        /// popup's rows are `NSMenuItem`s carrying the track, so a repeated
        /// title could no longer drop a row as `addItem(withTitle:)` would.
        var menuTitle: String { "\(name) — \(cues) cue\(cues == 1 ? "" : "s") (track \(track))" }
    }

    /// Why an export produced nothing.
    enum ExportError: LocalizedError {
        case noTextTrack
        case ambiguous([Candidate])
        case notCaptions(UInt32, String)
        case empty(UInt32, String)
        case unwritable(URL, String)

        var errorDescription: String? {
            switch self {
            case .noTextTrack:
                return "No track holds only text clips, so there are no captions to write."
            case .ambiguous(let candidates):
                return "Several tracks hold only text clips, so which to write is not obvious: "
                    + candidates.map { $0.description }.joined(separator: ", ")
                    + ". Name one with track."
            case .notCaptions(let track, let name):
                return "Track \(track) “\(name)” holds clips that are not text, so it cannot be "
                    + "written as captions."
            case .empty(let track, let name):
                return "Track \(track) “\(name)” has no caption text on it."
            case .unwritable(let url, let reason):
                return "“\(url.lastPathComponent)” could not be written: \(reason)"
            }
        }
    }

    // MARK: - Choosing a track

    /// Every track that could be written as captions, FRONT-most first —
    /// captions are placed at the front of the stack (`CaptionLayout.place`),
    /// so the likeliest answer is the first row of a popup and the first name
    /// in a refusal.
    static func candidates(in snapshot: ProjectSnapshot) -> [Candidate] {
        snapshot.tracks.reversed().compactMap { track in
            let clips = snapshot.clips(onTrack: track.id)
            guard !clips.isEmpty, clips.allSatisfy({ isText($0) }) else { return nil }
            let count = cues(onTrack: track.id, in: snapshot).count
            guard count > 0 else { return nil }
            return Candidate(track: track.id, name: track.name, cues: count)
        }
    }

    /// The track an export will write: the one the caller named, or the sole
    /// candidate. Never a guess — see the type's doc.
    static func resolveTrack(_ requested: UInt32?, in snapshot: ProjectSnapshot) throws -> UInt32 {
        if let requested = requested {
            let name = snapshot.track(requested)?.name ?? "Track \(requested)"
            let clips = snapshot.clips(onTrack: requested)
            guard clips.allSatisfy({ isText($0) }) else {
                throw ExportError.notCaptions(requested, name)
            }
            guard !cues(onTrack: requested, in: snapshot).isEmpty else {
                throw ExportError.empty(requested, name)
            }
            return requested
        }
        let found = candidates(in: snapshot)
        guard let only = found.first else { throw ExportError.noTextTrack }
        guard found.count == 1 else { throw ExportError.ambiguous(found) }
        return only.track
    }

    private static func isText(_ clip: ClipSnapshot) -> Bool {
        if case .text = clip.source { return true }
        return false
    }

    // MARK: - Reading the cues

    /// One track's captions in timeline order. A clip with no text, or none
    /// left after the tidy below, contributes nothing — it is a caption
    /// somebody emptied, and writing a blank entry would make the file
    /// unreadable rather than honest.
    static func cues(onTrack track: UInt32, in snapshot: ProjectSnapshot) -> [Cue] {
        snapshot.clips(onTrack: track).compactMap { clip in
            guard let content = clip.text?.content else { return nil }
            let text = body(content)
            guard !text.isEmpty, clip.duration > 0 else { return nil }
            return Cue(start: clip.start, end: clip.end, text: text)
        }
    }

    /// A cue's text as a caption file can hold it: LF line endings, no blank
    /// lines and no trailing spaces.
    ///
    /// A blank line is SubRip's ENTRY separator, so a caption that contained
    /// one would split into two entries, the second of which has no timing
    /// line — a file no reader can parse and this app itself would refuse on
    /// the way back in. Collapsing is the only answer that keeps the words.
    private static func body(_ content: String) -> String {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // MARK: - Writing

    /// The whole file, as a string. Pure, so a proof can compare it with the
    /// bytes on disk and a caller can write it wherever it likes.
    static func text(for cues: [Cue], format: Format, fps: Fps) -> String {
        var entries: [String] = []
        for (index, cue) in cues.enumerated() {
            var lines: [String] = []
            if format == .srt { lines.append("\(index + 1)") }
            lines.append(
                timestamp(cue.start, format: format, fps: fps) + " --> "
                    + timestamp(cue.end, format: format, fps: fps))
            lines.append(escaped(cue.text, format: format))
            entries.append(lines.joined(separator: "\n"))
        }
        let header = format == .vtt ? "WEBVTT\n\n" : ""
        return header + entries.joined(separator: "\n\n") + "\n"
    }

    /// `HH:MM:SS,mmm` or `HH:MM:SS.mmm`. The number is the CORE's — spec §5.1
    /// gives `time.rs` sole ownership of formatting a timecode ("nothing else
    /// in the crate may re-derive a frame boundary or format a timecode"), and
    /// a Swift exporter dividing by 600 to find milliseconds would be a second
    /// implementation of the rounding rule. Only the separator is ours.
    private static func timestamp(_ t: Ticks, format: Format, fps: Fps) -> String {
        let text = ReelTime.format(max(0, t), fps: fps, frames: false)
        guard format.decimalSeparator != "." else { return text }
        return text.replacingOccurrences(of: ".", with: format.decimalSeparator)
    }

    /// WebVTT's three characters. `&` FIRST, the mirror of
    /// `CaptionImporter.decodeEntities` doing it last: escape it after `<` and
    /// every ampersand this pass introduced would be escaped a second time.
    /// SubRip has no markup, so it escapes nothing.
    private static func escaped(_ text: String, format: Format) -> String {
        guard format == .vtt else { return text }
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// The format an export will use: the caller's choice, else the path's own
    /// extension when it names one, else SubRip — the format the importer
    /// reads and the one most tools expect.
    static func format(for url: URL, requested: Format? = nil) -> Format {
        if let requested = requested { return requested }
        return Format(rawValue: url.pathExtension.lowercased()) ?? .srt
    }

    // MARK: - Naming

    /// Every extension a caption file is written under — the two formats'
    /// `rawValue`s, which ARE their extensions (`Format`'s doc). It is the
    /// caption formats' own set and not `FrameWriter.knownExtensions`, because
    /// the question a set here answers is "did THIS popup write the suffix on
    /// this name", and the only suffixes a caption panel ever puts on a name
    /// are these two; a still's `.png` is `FrameWriter`'s to replace and a
    /// caption panel handed `chart.png` keeps it, as it keeps `.txt`. It is
    /// also the set `export_captions` replaces
    /// (`AgentServer.captionDestinationURL`, spec §11 #43);
    /// `tools/proof/remaining_probe.py`'s 1f builds a row from each member
    /// here and asks that function, so the rule is pinned rather than stated.
    static let knownExtensions = Set(Format.allCases.map { $0.rawValue })

    /// A save panel's name field rewritten for a newly chosen format: the
    /// stem it already holds, then that format's extension. `fallback` is
    /// what an empty field falls back to. It is `FrameWriter.renamed` line
    /// for line, with `rawValue` where that one has `fileExtension`, and for
    /// its reason: **only a suffix this app WRITES is an extension**, and the
    /// rest of the name is the person's. A bare `deletingPathExtension` takes
    /// whatever follows the last dot, so the format popup used to turn
    /// `Board v1.2` into `Board v1.vtt` — eating a character somebody typed
    /// on purpose while doing exactly what it was told. Measured:
    /// `("Board v1.2" as NSString).deletingPathExtension` is "Board v1", and
    /// `("shot.final" as NSString)`'s is "shot".
    ///
    /// A foreign extension is KEPT: `talk.txt` under SubRip is `talk.txt.srt`,
    /// because `txt` is part of the name by `AgentServer.captionDestinationURL`'s
    /// rule — it strips only a member of `knownExtensions` and appends otherwise
    /// — and `talk.txt.srt` is the file `export_captions` writes for that same
    /// path, so the panel and the tool agree about what the name
    /// means. The suffix is compared lower-cased, as `captionDestinationURL`
    /// compares, so `talk.SRT` under WebVTT is `talk.vtt` and not
    /// `talk.SRT.vtt`; a dot-leading name has no extension to Foundation
    /// (`.srt` under WebVTT is `.srt.vtt`), which is pinned rather than
    /// special-cased. `chart.png` under SubRip is `chart.png.srt` both here
    /// and over MCP.
    ///
    /// It is a pure function of a string and lives HERE rather than in
    /// `CaptionExportOptions` for `FrameWriter.renamed`'s reason: an
    /// accessory view's private method is reachable by no proof this project
    /// can write, because a save panel cannot be driven over MCP or
    /// offscreen, and the MCP path never comes near it — `export_captions`
    /// goes through `captionDestinationURL`, which this function mirrors, so an MCP
    /// check for `Board v1.2` passes against a build with the bare strip in
    /// it. `tools/proof/remaining_probe.py` compiles `app/Sources` and calls
    /// this with a table of names instead.
    static func renamed(_ name: String, as format: Format, fallback: String) -> String {
        let suffix = (name as NSString).pathExtension.lowercased()
        let stem =
            knownExtensions.contains(suffix)
            ? (name as NSString).deletingPathExtension : name
        return "\(stem.isEmpty ? fallback : stem).\(format.rawValue)"
    }

    /// Writes the file, UTF-8, no BOM. A missing folder is refused rather
    /// than created: a caller who named one that is not there meant a
    /// different path.
    static func write(_ text: String, to url: URL) throws {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.unwritable(url, error.localizedDescription)
        }
    }

    /// The whole export in one call, for the agent and the save panel alike:
    /// pick the track, read the cues, write the file, and answer what landed.
    @discardableResult
    static func export(
        from snapshot: ProjectSnapshot, track requested: UInt32?, to url: URL,
        format requestedFormat: Format? = nil
    ) throws -> (track: UInt32, format: Format, cues: [Cue]) {
        let track = try resolveTrack(requested, in: snapshot)
        let cues = cues(onTrack: track, in: snapshot)
        let format = format(for: url, requested: requestedFormat)
        try write(text(for: cues, format: format, fps: snapshot.canvas.fps), to: url)
        return (track, format, cues)
    }
}

// MARK: - The save panel's options

/// The two choices a caption export has, carried in the save panel's
/// accessory view rather than in a sheet of its own: which track, and which
/// format. A second sheet for two popups would be the heavier answer, and
/// chaining a sheet out of a sheet is what `ReverseProgressSheetController`
/// records as not working here.
///
/// It owns nothing but its controls; the panel's completion holds it for as
/// long as the panel is up.
private final class CaptionExportOptions: NSObject {
    private weak var panel: NSSavePanel?
    private let candidates: [CaptionExporter.Candidate]
    private let stem: String
    private let trackPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    let view: NSView

    init(panel: NSSavePanel, candidates: [CaptionExporter.Candidate], stem: String) {
        self.panel = panel
        self.candidates = candidates
        self.stem = stem

        for candidate in candidates {
            // The row is an `NSMenuItem` carrying the TRACK, never its
            // position in the list: `NSPopUpButton.addItem(withTitle:)`
            // removes an existing row with the same title before adding the
            // new one — measured: three rows two of which read alike come
            // back as two — so a popup built that way and indexed by
            // `indexOfSelectedItem` would hand the exporter a different track
            // than the one the row named and report the write as a success.
            // `menuTitle` keeps the titles distinct; this makes the mapping
            // right whatever the titles do.
            let item = NSMenuItem(title: candidate.menuTitle, action: nil, keyEquivalent: "")
            item.representedObject = candidate.track
            trackPopup.menu?.addItem(item)
        }
        trackPopup.font = DS.sans(13)
        trackPopup.selectItem(at: 0)
        // Only one track to choose is not a choice, and a live popup with one
        // row invites a click that can change nothing.
        trackPopup.isEnabled = candidates.count > 1

        for format in CaptionExporter.Format.allCases {
            formatPopup.addItem(withTitle: format.displayName)
        }
        formatPopup.font = DS.sans(13)
        formatPopup.selectItem(at: 0)

        let grid = NSGridView(views: [
            [fieldLabel("Track:"), trackPopup],
            [fieldLabel("Format:"), formatPopup],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 60
        grid.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            grid.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualTo: grid.widthAnchor, constant: 32),
        ])
        view = container

        super.init()
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged(_:))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CaptionExportOptions does not support NSCoder")
    }

    var track: UInt32? {
        guard let chosen = trackPopup.selectedItem?.representedObject as? UInt32 else {
            return candidates.first?.track
        }
        return chosen
    }

    var format: CaptionExporter.Format {
        let all = CaptionExporter.Format.allCases
        let index = formatPopup.indexOfSelectedItem
        guard all.indices.contains(index) else { return .srt }
        return all[index]
    }

    /// The panel's filter and its name field both name the container, so both
    /// move together — otherwise AppKit appends `.srt` to a name the user just
    /// asked to be a `.vtt`.
    ///
    /// Only the EXTENSION is this method's to change. The stem is read back
    /// off the panel rather than from `stem`, which is the document's name and
    /// was fixed when the panel opened: a person who typed “lecture-01” over
    /// it and then chose WebVTT would otherwise watch the field silently
    /// revert to the document's name, and save to a path they had already
    /// replaced. `stem` survives as the fallback for a field emptied to
    /// nothing.
    ///
    /// The rewrite itself is `CaptionExporter.renamed`, which strips a
    /// trailing suffix only when it is one of the two formats' own — so
    /// `Board v1.2` no longer becomes `Board v1.vtt` — and is a free function
    /// for the reason its doc gives: a rule inside a save panel's private
    /// method is a rule no proof can reach.
    @objc private func formatChanged(_ sender: Any?) {
        guard let panel = panel else { return }
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = CaptionExporter.renamed(
            panel.nameFieldStringValue, as: format, fallback: stem)
    }
}

// MARK: - The menu command

/// File ▸ Export Captions…, mirrored by the agent's `export_captions`. The
/// command half lives at the foot of the file that owns the feature —
/// `CaptionImporter.swift`'s precedent, which keeps File ▸ Import Captions…
/// beside the importer it opens.
extension EditorViewController {

    /// The save panel, then the write. The panel's completion is OFF-EVENT,
    /// but an export mutates nothing, so there is no undo step to group — it
    /// writes, and puts up an alert if it could not.
    ///
    /// The refusals happen HERE, before the panel: a save panel whose only
    /// possible answer is "there are no captions on this timeline" should not
    /// open, which is `removeSilencesCommand`'s rule.
    func exportCaptionsCommand() {
        guard let document = document, let window = view.window,
              view.window?.attachedSheet == nil
        else {
            NSSound.beep()
            return
        }
        // The open container's, so the track this offers to write is the one
        // `get_project` is listing — a reader and a writer that disagree
        // about which timeline they mean is the defect phase 9 closed in
        // the producers next door.
        let snapshot = document.editedProject.snapshot
        let candidates = CaptionExporter.candidates(in: snapshot)
        guard !candidates.isEmpty else {
            NSSound.beep()
            return
        }
        // The title with the package's own extension off and NOTHING else
        // off — `ProjectDocument+DisplayStem.swift` says why the bare strip
        // that stood here lost the `.2` of "Board v1.2", and why its known
        // set is `{framejob}` where the popup's below is `{srt, vtt}`. It is
        // also the popup's fallback for a field emptied to nothing.
        let stem = document.displayStem
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(stem).srt"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [CaptionExporter.Format.srt.contentType]
        panel.message = "Write one track's text clips out as a caption file."
        let options = CaptionExportOptions(panel: panel, candidates: candidates, stem: stem)
        panel.accessoryView = options.view
        // The completion is what keeps `options` alive: the panel retains the
        // accessory VIEW, not the object whose action the format popup calls,
        // and a deallocated target would leave a live popup that changes
        // nothing.
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.exportCaptions(
                from: document, track: options.track, format: options.format, to: url,
                in: window)
        }
    }

    private func exportCaptions(
        from document: ProjectDocument, track: UInt32?, format: CaptionExporter.Format,
        to url: URL, in window: NSWindow
    ) {
        do {
            // The snapshot is read HERE rather than captured with the panel:
            // a panel is not a sheet, so the document was editable the whole
            // time it was up and what the user sees now is what should land.
            _ = try CaptionExporter.export(
                from: document.editedProject.snapshot, track: track, to: url, format: format)
        } catch {
            let alert = NSAlert(error: error)
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }

    /// The half of `validateUserInterfaceItem` this file owns. nil means "not
    /// mine" and leaves the other answers alone.
    func validateCaptionExportAction(_ action: Selector) -> Bool? {
        guard let document = document else { return false }
        switch action {
        case #selector(EditorViewController.exportCaptions(_:)):
            // The honest test is `candidates`, and it is cheap: the snapshot
            // is memoized and a validator runs on every menu open, so this
            // costs one pass over the clips per track. The command's own
            // guard is the same answer.
            return !CaptionExporter.candidates(in: document.editedProject.snapshot).isEmpty
        default:
            return nil
        }
    }
}
