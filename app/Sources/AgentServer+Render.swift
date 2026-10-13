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

    // MARK: - Export

    /// `export` — ⌘E (`EditorViewController.exportProjectCommand` and
    /// `ExportSheetController`). The preset names the ENCODING — a container
    /// and a codec, nothing about size — and the size is the sheet's separate
    /// choice, in the Size popup's own vocabulary and defaulting as the popup
    /// does to its first row: the document's size, or an image format's cap.
    /// The CORE resolves both into concrete settings (`rc_export_settings`)
    /// that go to the same `Exporter.export` the sheet uses: there is exactly
    /// one writer, so an agent export and a menu export cannot disagree.
    ///
    /// Blocks until the file is written, so the model can render, export and
    /// verify in sequence without polling.
    ///
    /// One argument is NOT a setting and never reaches the core:
    /// `burn_in_timecode` is a recipe option (`RecipeOptions`), read below
    /// beside the overrides it deliberately does not join.
    ///
    /// The result carries the sound the file actually holds — its integrated
    /// loudness and true peak, measured on the way through — for every format
    /// that has any, whether `loudness_lufs` was asked for or not.
    func exportProject(_ a: [String: Any]) throws -> String {
        let stop = AgentLane.shared.callCancel  // the assistant's Stop (spec §11 AI-16)
        let presetID = try requiredString(a, "preset")
        let path = try requiredString(a, "path")
        let wholeProject = (try stringArg(a, "range") ?? "project").lowercased()
        guard ["project", "in_out"].contains(wholeProject) else {
            throw ToolError(
                message: "range must be \"project\" (the whole timeline) or \"in_out\" "
                    + "(the in/out range set_range set), not \"\(wholeProject)\".")
        }
        // The export sheet's burn-in checkbox — and read HERE rather than
        // into `overrides` below, which is the whole of the decision. A
        // recipe option changes the PICTURE, so it travels with the
        // description of the picture: `export_overrides.rs` ignores a key it
        // does not know, on purpose, so a `burn_in_timecode` posted through
        // `rc_export_settings` would vanish without a word and this tool
        // would report success on an un-burnt file. It goes to `Exporter`
        // beside the settings instead (`RecipeOptions`, `Exporter.export`),
        // which is also what reaches GIF and APNG — those never go through
        // `ExportWriter` at all.
        let options = RecipeOptions(burnInTimecode: try boolArg(a, "burn_in_timecode") ?? false)
        let prepared = try onMain {
            () throws -> (ProjectDocument, ReelProject, [UInt32: URL], ExportSettings, GraphicSet?)
            in
            let document = try self.target(a)
            guard document.project.duration > 0 else {
                throw ToolError(message: "There is nothing on the timeline to export.")
            }
            // The Range popup of the export sheet, in the sheet's own terms:
            // "Whole project" is no override at all, "In/out range" is the
            // core's ONE nested `range` object (`export.rs`). The core snaps
            // it to the frame grid and clamps it to the project.
            var overrides: [String: Any] = [:]
            if wholeProject == "in_out" {
                guard let range = document.inOutRange, range.end > range.start else {
                    throw ToolError(
                        message: "This project has no in/out range — set one with set_range "
                            + "{start, end}, or export with range \"project\".")
                }
                overrides["range"] = ["start": range.start, "duration": range.end - range.start]
            }
            // The sheet's Quality popup, in the core's own words: it resolves
            // a tier into these two keys and nothing else
            // (`ExportSheetController.overrides()`), so the agent spells them
            // the same way rather than re-deriving a rate from a tier name.
            // The core validates them — positive, u32 — and an unset key means
            // "the preset decides", which is what a nil bitrate already means
            // to the writer.
            if let video = try self.intArg(a, "video_bitrate") {
                overrides["video_bitrate"] = video
            }
            if let audio = try self.intArg(a, "audio_bitrate") {
                overrides["audio_bitrate"] = audio
            }
            // The sheet's Loudness popup, in the core's words again — and
            // through `doubleArg`, not `intArg`: −14.5 LUFS is a real request
            // and every one of these figures is a negative fraction. Neither
            // is validated here. `export_overrides.rs` owns the bounds
            // (−70…0 and −20…0) and the one PAIRING rule among the overrides
            // — a `peak_dbtp` with no `loudness_lufs` is refused, because
            // normalisation is gain-only and a ceiling with nothing to cap
            // would be a key accepted, echoed and silently inert — and it
            // names the offending value the way the bitrate refusals do.
            // Restating a bound here would be a second spelling of it to
            // drift from the first.
            // The sheet sends both together and fixes the ceiling at
            // −1 dBTP; a caller that wants −0.3 or −2.0 says so here.
            if let target = try self.doubleArg(a, "loudness_lufs") {
                overrides["loudness_lufs"] = target
            }
            if let ceiling = try self.doubleArg(a, "peak_dbtp") {
                overrides["peak_dbtp"] = ceiling
            }
            // The sheet's Size popup: a row id, or "Custom…" as an explicit
            // [width, height]. Absent is no override at all, so the tool's
            // default and the sheet's are one code path in the core — the
            // document's size, or an image format's cap.
            if let size = try self.exportSizeArg(a, document.project, preset: presetID) {
                overrides["width"] = size.width
                overrides["height"] = size.height
            }
            let settings: ExportSettings
            do {
                settings = try ReelExport.settings(
                    document.project, preset: presetID, overrides: overrides)
            } catch {
                throw Self.coreRefusal(error)
            }
            return (
                document, document.project, document.mediaURLs(), settings,
                GraphicRegistry.shared.snapshot(for: document.recipeKey)
            )
        }
        let (document, project, urls, settings, graphics) = prepared
        let url = Self.destinationURL(path, extension: Exporter.fileExtension(for: settings))
        let folder = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw ToolError(message: "There is no folder at \(folder.path) to write into.")
        }

        // Held on this stack for the whole call, which is what keeps the
        // export alive: nothing else references it, and its `deinit` tears the
        // progress timer and its recipe slot down.
        let exporter = Exporter()
        let semaphore = DispatchSemaphore(value: 0)
        let box = AgentBox<Result<URL, any Error>>()
        onMain {
            // The editor pauses before its own export so the player is not
            // decoding the same media; the agent's does the same.
            self.editor(document)?.playback.pause()
            exporter.export(
                project: project, urls: urls, settings: settings, to: url, options: options,
                graphics: graphics, progress: { _ in }
            ) { result in
                box.value = result
                semaphore.signal()
            }
            stop?.onCancel { [weak exporter] in exporter?.cancel() }
        }
        guard semaphore.wait(timeout: .now() + 3600) == .success else {
            // Cancel on main AND let main hold the last reference: `Exporter`
            // installs a run-loop timer that its `deinit` invalidates, and a
            // timer has to be invalidated on the thread it was scheduled on.
            // (On the normal path `finish` has already torn the timer down
            // before it calls back, so the release here is a no-op.)
            DispatchQueue.main.async { exporter.cancel() }
            throw ToolError(message: "The export did not finish within an hour.")
        }
        guard let outcome = box.value else {
            throw ToolError(message: "The export ended without a result.")
        }
        let written: URL
        do {
            written = try outcome.get()
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: written.path)[.size])
            .flatMap { ($0 as? NSNumber)?.intValue } ?? 0
        var result: [String: Any] = [
            "ok": true,
            "path": written.path,
            "bytes": size,
            "preset": settings.preset,
            "container": settings.container,
            "codec": settings.codec,
            "width": settings.width,
            "height": settings.height,
            "fps": [settings.fps.num, settings.fps.den],
            "start": settings.start,
            "duration": settings.duration,
            // Not one of the resolved settings — the core never saw it — but
            // it is a fact about the file that was written, and every other
            // key here is one too.
            //
            // What it establishes is exactly one link and not the chain: this
            // is `options.burnInTimecode`, the local decoded a few lines up,
            // so a caller reading it back knows the argument was READ rather
            // than dropped in argument reading — the failure `boolArg`'s
            // refusal covers from the other side. It does NOT say the writer
            // used it; only a pixel can say that, and
            // `tools/proof/phase7_proof.py` is where one does.
            "burn_in_timecode": options.burnInTimecode,
        ]
        if let measured = Self.loudnessResult(exporter.loudnessReport) {
            result["loudness"] = measured
        }
        if let warned = Self.graphicWarningsResult(exporter.graphicWarnings) {
            result["graphic_warnings"] = warned
        }
        return try jsonResult(result)
    }

    /// The `size` argument of `export`, in the Size popup's vocabulary: a row
    /// id resolved through the same `rc_export_sizes` the popup is built from
    /// (`document`, `preset`, `2160p`, `1440p`, `1080p`, `720p` — `ExportSize`
    /// in `ReelCore.swift` says what each means, and `core/src/export_size.rs`
    /// why every document lists every row), or the popup's "Custom…" as an
    /// explicit `[width, height]`. nil when absent, which is no override: the
    /// core's default for the preset.
    ///
    /// A value that is neither is refused by NAME, never read as absent — the
    /// rule every reader in `AgentServer+Arguments.swift` keeps, and the root
    /// `CLAUDE.md`'s: a value a handler cannot read is refused by name, never
    /// dropped. A `size` dropped in silence would export at the wrong size
    /// and report success. A custom
    /// size outside the sheet's own field range is refused the same way,
    /// where the sheet clamps: a tool has no field to clamp in view of the
    /// caller, and the sheet's reason — a mistyped digit must not reach the
    /// encoder as a 300 000-pixel frame — holds for a model's typo too.
    private func exportSizeArg(
        _ a: [String: Any], _ project: ReelProject, preset: String
    ) throws -> (width: Int, height: Int)? {
        guard let raw = a["size"], !(raw is NSNull) else { return nil }
        // The rows come first, whichever spelling follows: every refusal
        // below lists the ids from them rather than from a vocabulary
        // restated here, which could drift from the core's, and a preset the
        // core does not know is refused at this point in the same words
        // `exportProject` would use a call later.
        let rows: [ExportSize]
        do {
            rows = try ReelExport.sizes(project, preset: preset)
        } catch {
            throw Self.coreRefusal(error)
        }
        let ids = rows.map { $0.id }.joined(separator: ", ")
        if let id = raw as? String {
            guard let row = rows.first(where: { $0.id == id }) else {
                throw ToolError(
                    message: "No export size is called \"\(id)\" for \(preset). The sizes "
                        + "are: \(ids) — or pass [width, height].")
            }
            return (row.width, row.height)
        }
        if let array = raw as? [Any], array.count == 2 {
            let edges = array.compactMap(Self.wholeEdge)
            if edges.count == 2 {
                let range = ExportSheetController.sizeRange
                // Each refusal of a `size` offers the OTHER spelling: the
                // unknown-id one above names the custom form, and this one
                // names the rows, so a caller who meant a standard size and
                // reached for numbers has the ids in front of it.
                guard edges.allSatisfy(range.contains) else {
                    throw ToolError(
                        message: "A custom size must be \(range.lowerBound)…\(range.upperBound) "
                            + "px on each edge, not [\(edges[0]), \(edges[1])] — or pass a "
                            + "row: \(ids).")
                }
                return (edges[0], edges[1])
            }
        }
        throw ToolError(
            message: "size must be a row of the export sheet's Size popup — \(ids) — or "
                + "[width, height] in px, not \(Self.spelled(raw)).")
    }

    /// One edge of a custom size as a whole number, or nil for a value that
    /// is not one — which sends the whole `size` to the refusal that names
    /// it. The coercion `intArg` applies holds: a string spelling of a whole
    /// number is a JSON-typing slip, not a different request. A fraction is
    /// refused rather than truncated, since 1920.5 is not a width the caller
    /// can have meant. So is a boolean: JSON's `true` arrives as an
    /// `NSNumber` like any other and would read as 1 through it, and the
    /// Core Foundation type is the one thing that still tells `true` from
    /// `1`.
    private static func wholeEdge(_ value: Any) -> Int? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let real = number.doubleValue
            return real.isFinite && real == real.rounded() ? number.intValue : nil
        }
        return (value as? String).flatMap(Int.init)
    }

    /// A refusal from `rc_export_settings` or `rc_export_sizes` as the tool's
    /// error. The core's message passes through as it was, with one
    /// addition: an unknown preset id — the message that begins
    /// "unknown export preset", the same words from either call
    /// (`export.rs`) — gets the ids the table does take appended, because
    /// without them it is the one error a model cannot correct itself from,
    /// since nothing else lists the table. A refused bitrate or range keeps
    /// its own message alone: a list of presets under it would be a false
    /// lead.
    private static func coreRefusal(_ error: any Error) -> ToolError {
        let message = error.localizedDescription
        guard message.hasPrefix("unknown export preset") else {
            return ToolError(message: message)
        }
        let names = ReelExport.presets().map { $0.id }.joined(separator: ", ")
        return ToolError(message: "\(message). The presets are: \(names).")
    }

    /// A caller's value as it was spelled, for a refusal that names it: its
    /// JSON where it is JSON, its Swift description otherwise.
    private static func spelled(_ raw: Any) -> String {
        guard JSONSerialization.isValidJSONObject([raw]),
            let data = try? JSONSerialization.data(
                withJSONObject: raw, options: [.fragmentsAllowed]),
            let text = String(data: data, encoding: .utf8)
        else { return String(describing: raw) }
        return text
    }
}
