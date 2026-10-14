import AppKit
import UniformTypeIdentifiers

/// The agent's two output tools: `render_frame`, the verification hook the
/// whole project's end-to-end checking depends on, and `export`, which writes
/// a file through the same `Exporter` the sheet uses.
///
/// Both run on the SERVER thread (`AgentServer.offMainTools`): each blocks on
/// decode or encode for as long as the work takes, and freezing the UI —
/// which is also the run loop AVFoundation delivers progress on — for the
/// whole of it is not acceptable. They hop to main through `onMain` for every
/// document touch.
extension AgentServer {

    // MARK: - Rendering

    /// `render_frame`'s `selection`: absent, or an id (a whole number in the
    /// id range), refused by name otherwise.
    private func selectionArg(_ a: [String: Any]) throws -> UInt32? {
        guard let value = try intArg(a, "selection") else { return nil }
        guard value >= 0, value <= Int(UInt32.max) else {
            throw ToolError(message: "selection is not a clip id: \(value)")
        }
        return UInt32(value)
    }

    /// `render_frame` — the offline twin of the preview: an
    /// `AVAssetImageGenerator` over the SAME `AVComposition` +
    /// `AVVideoComposition` an export writes, so what comes back is what the
    /// file would contain at `t` rather than a second opinion about it
    /// (`Exporter.renderFrame`, spec §7.9). It is the PREVIEW it twins and
    /// not the export, which decides what it renders while a nest is open —
    /// see the body.
    ///
    /// The frame comes back BOTH ways: base64 in an MCP image block, so a
    /// model can look at it, and as a file on disk whose path the result
    /// names, so a test can diff it or a human can open it.
    ///
    /// **The write is `FrameWriter`'s, and that is the point of it** (road map
    /// 2's phase 7a). This handler used to hold its own
    /// `CGImageDestination` — which made File ▸ Save Frame… and this tool two
    /// encoders that happened to agree — and now both call one `write`. That
    /// is what makes "Save Frame's PNG is byte-identical to `render_frame`'s"
    /// a fact about the code rather than a claim, and it is the only way the
    /// line can ever be checked: a save panel cannot be driven over MCP or
    /// offscreen, so no proof script can press the menu item.
    ///
    /// **The last sentence of the text block is load-bearing.** A call that
    /// names neither `path` nor `format` still writes a PNG into the
    /// temporary directory and still ends "Written to <path>." byte for byte
    /// as it did before this phase: five proof scripts (phases 1, 2, 3, 4 and
    /// 6) read the path back out of it with `Written to (\S+\.png)\.` and
    /// every PNG comparison this project makes hangs off that one regular
    /// expression. Anything new to say goes BEFORE it.
    ///
    /// **`burn_in_timecode` is a recipe option and never an export override**
    /// (`RecipeOptions`): it changes the picture, so it travels with the
    /// description of the picture. It is here for parity with `export`, and
    /// because a burn-in lives only in rendered pixels — this is the one tool
    /// that can photograph one, so it is the instrument every claim about
    /// phase 7c's layer is made through.
    ///
    /// **`ungraded` and the four scope booleans are View ▸ Show Ungraded's
    /// and View ▸ Scopes' mirror** (spec §11 GR-4, GR-5, GR-10): the switch,
    /// the panel and its slot picks are view state and never reach this tool,
    /// so it is asked here. `ungraded` is a recipe option like
    /// `burn_in_timecode`; `waveform`, `parade`, `vectorscope` and `histogram`
    /// measure the frame just written through the panel's own analyser, once
    /// for all of them, and write each beside the image as
    /// `<path>.<scope>.json` with a sentence each, in that order
    /// (`writeScopes`, in `AgentServer+Scopes.swift`).
    ///
    /// **`selection` is View ▸ Show Selection's mirror** (spec §11 GR-13): an
    /// adjustment clip's id, a recipe option like `ungraded` — the clip's
    /// qualifier drawn as grey, every layer in front of it left out, black
    /// where the clip is not on the frame. An id naming no adjustment clip of
    /// the edited project is refused, naming `selection`.
    ///
    /// **A graphic that warned or failed is named** (G-8, G3c): one sentence
    /// per report the frame's pin held, before the last. The set is the
    /// DOCUMENT's (`recipeKey`), not the scoped handle's: a nest draws the
    /// package's modules too.
    func renderFrame(_ a: [String: Any]) throws -> String {
        let selection = try selectionArg(a)
        let context = try onMain {
            () throws -> (ReelProject, [UInt32: URL], Ticks, CGSize, GraphicSet?) in
            let document = try self.target(a)
            let t = try self.optionalTimeArg(a, "t", document) ?? document.playhead
            if let selection, !(document.editedProject.snapshot.clip(selection)
                .map(InspectorTab.isAdjustment) ?? false)
            {
                throw ToolError(
                    message: "selection must name an adjustment clip of this project; clip "
                        + "\(selection) is not one.")
            }
            // `editedProject`, not `project` — road map 2's phase 9. With a
            // nest open (`set_scope`) this renders THAT nest at its own
            // frozen canvas, from its own zero, with the outer transform not
            // applied: the same picture the preview panel is showing, which
            // is what makes a scoped edit checkable at all. It is the one
            // place in this file that side of the split is taken; `export`
            // below stays the DOCUMENT's, because an export writes the whole
            // timeline whatever the timeline happens to be showing. With no
            // nest open the two are the same handle and every earlier
            // phase's frame comparison is unaffected.
            return (
                document.editedProject, document.mediaURLs(), max(0, t),
                document.editedProject.snapshot.canvas.size,
                GraphicRegistry.shared.snapshot(for: document.recipeKey)
            )
        }
        let (project, urls, time, canvasSize, graphics) = context
        var maxWidth: Int?
        if let requested = try intArg(a, "max_width") {
            guard requested >= 16, requested <= 8192 else {
                throw ToolError(message: "max_width must be 16…8192 px (got \(requested)).")
            }
            maxWidth = requested
        }
        let options = RecipeOptions(
            burnInTimecode: try boolArg(a, "burn_in_timecode") ?? false,
            ungraded: try boolArg(a, "ungraded") ?? false, selection: selection)
        var scopes: [ScopeKind] = []
        for kind in ScopeKind.allCases where try boolArg(a, kind.rawValue) ?? false {
            scopes.append(kind)
        }
        // Resolved BEFORE the render, so a mistyped folder is answered in a
        // millisecond rather than after a decode: `exportProject` orders its
        // own two the same way.
        let (url, format) = try frameDestination(a, at: time)
        // Off the main thread by construction — `Exporter.renderFrame` opens
        // asset tracks and decodes, and says so.
        let rendered = Exporter.renderFrameReported(
            project: project, urls: urls, at: time, maxWidth: maxWidth, options: options,
            graphics: graphics)
        guard let image = rendered.image else {
            throw ToolError(
                message: "No frame at \(time). Either the time is past the end of the timeline, "
                    + "the media is missing, or the timeline is empty.")
        }
        do {
            try FrameWriter.write(image, as: format, to: url)
        } catch {
            // `FrameWriter.WriteError` names the path and the format in every
            // case it has, so the message passes through as it was written.
            throw ToolError(message: error.localizedDescription)
        }
        guard let data = try? Data(contentsOf: url) else {
            throw ToolError(message: "Wrote \(url.path) but could not read it back.")
        }
        var text =
            "Frame at \(time) ticks of a \(Int(canvasSize.width))×\(Int(canvasSize.height)) px "
            + "canvas, rendered at \(image.width)×\(image.height) px"
        if options.burnInTimecode {
            text += ", with the project timecode burnt in"
        }
        if options.ungraded {
            text += ", with every grade removed"
        }
        if let selection {
            text += ", drawn as clip \(selection)'s qualifier selection (white fully graded, "
                + "black untouched)"
        }
        text += "."
        // Said where the caller can see it rather than only in the schema: a
        // frame off a transparent canvas (phase 7b) has just lost its alpha,
        // and a note that arrives with the file is the one that is read.
        if !format.carriesAlpha {
            text += " " + FrameWriter.flattenNote
        }
        for report in rendered.graphics {
            text += " " + Self.graphicSentence(report)
        }
        if !scopes.isEmpty {
            text += " " + (try Self.writeScopes(scopes, of: image, beside: url))
        }
        text += " Written to \(url.path)."
        return try callResult(
            content: [
                [
                    "type": "image", "data": data.base64EncodedString(),
                    "mimeType": Self.mimeType(format),
                ],
                ["type": "text", "text": text],
            ], isError: false)
    }

    /// One graphic's report as `render_frame` says it: failed at a frame,
    /// did not compile, or warned — each diagnostic with its location.
    static func graphicSentence(_ report: GraphicReport) -> String {
        let said = report.diagnostics.map { $0.located }.joined(separator: "; ")
        guard let frame = report.frame else {
            return "Graphic \"\(report.name)\" does not compile: \(said)."
        }
        let verb = report.failed ? "failed" : "warned"
        return "Graphic \"\(report.name)\" \(verb) at frame \(frame): \(said)."
    }

    /// Where `render_frame` writes and in what container — its `path` and
    /// `format` arguments resolved together, because neither can be read
    /// without the other.
    ///
    /// **No `path` is the case every proof script takes**, and it is exactly
    /// what it was: a file in the temporary directory named for the tick it
    /// holds, ending in the format's own extension — `.png` unless a caller
    /// asked for something else.
    ///
    /// With a `path`, the format is `FrameWriter`'s answer and not a second
    /// opinion: an explicit `format` wins, else the path's own extension, else
    /// PNG — `export_captions`' rule, one file over. The path then goes
    /// through `destinationURL`, so a wrong extension is REPLACED rather than
    /// appended to: `{path: "shot.jpg", format: "png"}` writes `shot.png`, not
    /// the doubled `shot.jpg.png`, which is why the five image containers
    /// joined `replaceableExtensions` in this phase.
    ///
    /// The folder must already exist and is refused BY NAME when it does not,
    /// which is `export`'s posture at the same point: a tool that created
    /// directories would answer a mistyped path by scattering empty ones.
    private func frameDestination(
        _ a: [String: Any], at time: Ticks
    ) throws -> (url: URL, format: FrameWriter.Format) {
        let requested = try requestedFrameFormat(a)
        guard let path = try stringArg(a, "path") else {
            let format = requested ?? .png
            let name = "framejob-frame-\(time)-\(UUID().uuidString.prefix(8))"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(name).\(format.fileExtension)")
            return (url, format)
        }
        // Empty is refused rather than read as absent: a caller that sent a
        // `path` meant to name a file, and silently writing to a temporary
        // one instead is a success reported for a file nobody can find.
        guard !path.isEmpty else {
            throw ToolError(
                message: "path must name a file to write — omit it for a temporary one.")
        }
        let format = FrameWriter.format(
            for: URL(fileURLWithPath: (path as NSString).expandingTildeInPath),
            requested: requested)
        let url = Self.destinationURL(path, extension: format.fileExtension)
        let folder = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw ToolError(message: "There is no folder at \(folder.path) to write into.")
        }
        return (url, format)
    }

    /// The `format` argument, refused BY NAME when it names no container —
    /// nil when it is absent, which is what lets `FrameWriter.format(for:)`
    /// fall back to the path. It is `export_captions`' `requestedFormat` with
    /// three rows instead of two.
    ///
    /// `jpg` is read as `jpeg` on purpose. `FrameWriter.Format`'s raw value is
    /// deliberately NOT its file extension — JPEG has two spellings and
    /// collapsing them would make one of them wrong — and `format(for:)`
    /// already reads both off a path, so refusing four letters here that are
    /// accepted in the argument beside it is an inconsistency a caller meets
    /// on its first try. The schema still advertises the three canonical
    /// names, which is what a caller reading the catalog will send.
    private func requestedFrameFormat(_ a: [String: Any]) throws -> FrameWriter.Format? {
        guard let name = try stringArg(a, "format") else { return nil }
        let lowered = name.lowercased()
        guard let format = FrameWriter.Format(rawValue: lowered == "jpg" ? "jpeg" : lowered)
        else {
            let known = FrameWriter.Format.allCases.map { $0.rawValue }
            throw ToolError(
                message: "format must be one of " + known.joined(separator: ", ")
                    + " (got \"\(name)\").")
        }
        return format
    }

    /// The image block's `mimeType`, read off the format's own `UTType`
    /// rather than switched over a second time here: the block and the file
    /// are then one decision, and a fourth container would arrive described
    /// correctly without anybody remembering this line.
    ///
    /// All three carry one (measured: `image/png`, `image/jpeg`,
    /// `image/heic`). The fallback exists only because the API is optional,
    /// and it is deliberately generic rather than a guess: telling a client
    /// that a HEIC is a PNG is worse than telling it nothing.
    private static func mimeType(_ format: FrameWriter.Format) -> String {
        format.contentType.preferredMIMEType ?? "application/octet-stream"
    }
}
