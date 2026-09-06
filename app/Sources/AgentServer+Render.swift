import AppKit
import ImageIO
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

    /// `render_frame` — the offline twin of the preview: an
    /// `AVAssetImageGenerator` over the SAME `AVComposition` +
    /// `AVVideoComposition` an export writes, so what comes back is what the
    /// file would contain at `t` rather than a second opinion about it
    /// (`Exporter.renderFrame`, spec §7.9).
    ///
    /// The PNG comes back BOTH ways: base64 in an MCP image block, so a model
    /// can look at the frame, and as a file on disk whose path the result
    /// names, so a test can diff it or a human can open it.
    func renderFrame(_ a: [String: Any]) throws -> String {
        let context = try onMain { () throws -> (ReelProject, [UInt32: URL], Ticks, CGSize) in
            let document = try self.target(a)
            let t = try self.optionalTimeArg(a, "t", document) ?? document.playhead
            return (
                document.project, document.mediaURLs(), max(0, t),
                document.project.snapshot.canvas.size
            )
        }
        let (project, urls, time, canvasSize) = context
        var maxWidth: Int?
        if let requested = try intArg(a, "max_width") {
            guard requested >= 16, requested <= 8192 else {
                throw ToolError(message: "max_width must be 16…8192 px (got \(requested)).")
            }
            maxWidth = requested
        }
        // Off the main thread by construction — `Exporter.renderFrame` opens
        // asset tracks and decodes, and says so.
        guard let image = Exporter.renderFrame(
            project: project, urls: urls, at: time, maxWidth: maxWidth)
        else {
            throw ToolError(
                message: "No frame at \(time). Either the time is past the end of the timeline, "
                    + "the media is missing, or the timeline is empty.")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reelcut-frame-\(time)-\(UUID().uuidString.prefix(8)).png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw ToolError(message: "Could not write a PNG to \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination),
            let data = try? Data(contentsOf: url)
        else {
            throw ToolError(message: "PNG encoding failed.")
        }
        let text =
            "Frame at \(time) ticks of a \(Int(canvasSize.width))×\(Int(canvasSize.height)) px "
            + "canvas, rendered at \(image.width)×\(image.height) px. Written to \(url.path)."
        return try callResult(
            content: [
                ["type": "image", "data": data.base64EncodedString(), "mimeType": "image/png"],
                ["type": "text", "text": text],
            ], isError: false)
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
    func exportProject(_ a: [String: Any]) throws -> String {
        let presetID = try requiredString(a, "preset")
        let path = try requiredString(a, "path")
        let wholeProject = (try stringArg(a, "range") ?? "project").lowercased()
        guard ["project", "in_out"].contains(wholeProject) else {
            throw ToolError(
                message: "range must be \"project\" (the whole timeline) or \"in_out\" "
                    + "(the in/out range set_range set), not \"\(wholeProject)\".")
        }
        let prepared = try onMain {
            () throws -> (ProjectDocument, ReelProject, [UInt32: URL], ExportSettings) in
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
            return (document, document.project, document.mediaURLs(), settings)
        }
        let (document, project, urls, settings) = prepared
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
                project: project, urls: urls, settings: settings, to: url,
                progress: { _ in }
            ) { result in
                box.value = result
                semaphore.signal()
            }
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
        return try jsonResult([
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
        ])
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
    /// `patchArg` rule (`AgentServer+Arguments.swift`): a `size` dropped in
    /// silence would export at the wrong size and report success. A custom
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
