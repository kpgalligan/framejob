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
    ///
    /// The result carries the sound the file actually holds — its integrated
    /// loudness and true peak, measured on the way through — for every format
    /// that has any, whether `loudness_lufs` was asked for or not.
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
        ]
        if let measured = Self.loudnessResult(exporter.loudnessReport) {
            result["loudness"] = measured
        }
        return try jsonResult(result)
    }

    /// What the export's sound MEASURED, for the result — nil, and then the
    /// key is simply absent, wherever `Exporter` published no report: a
    /// format that holds no audio track at all (GIF and APNG), and a
    /// timeline with no sound in it, which is the case a caller actually
    /// meets. A missing `loudness` is therefore "there was nothing to
    /// measure", never "the measurement was skipped".
    ///
    /// This is `detect_silence`'s posture applied to the writer: the numbers
    /// are read back off the file's own mix rather than repeated from the
    /// request, so a caller can check that a −14 LUFS export actually landed
    /// at −14, which is what makes phase 5's ±0.5 LU claim a claim anyone can
    /// test over MCP. `target` is what was ASKED for and is absent when
    /// nothing was — every export measures itself and reports, normalised or
    /// not.
    ///
    /// It is read off the `Exporter` this stack still holds, after the
    /// semaphore the completion signalled: `Exporter.finish` publishes the
    /// report before it calls back, and it is documented there as never
    /// cleared, so both consumers (this and the progress sheet) read it after
    /// their completion has fired.
    ///
    /// Every level goes through `jsonLevel`: a silent programme measures
    /// −∞ dBTP, and `JSONSerialization` throws on an infinity — which would
    /// report a successful export as a failed tool call.
    private static func loudnessResult(_ report: ExportLoudness?) -> [String: Any]? {
        guard let report = report else { return nil }
        var measured: [String: Any] = [
            // The same sentence the progress sheet's last line shows, so the
            // two consumers of one measurement cannot describe it differently.
            "summary": report.summary,
            "true_peak_dbtp": jsonLevel(report.truePeakDBTP),
            "sample_peak_dbfs": jsonLevel(report.measured.samplePeakDBFS + report.gainDB),
            "gain_db": report.gainDB,
            "ceiling_dbtp": jsonLevel(report.ceiling),
            "capped_by_peak": report.cappedByPeak,
        ]
        // Absent rather than null, and for a reason worth the line: a
        // programme shorter than one 400 ms gating block, or one whose every
        // block fell under the standard's absolute gate, HAS no integrated
        // loudness. `summary` says so in words.
        if let integrated = report.integratedLUFS, integrated.isFinite {
            measured["integrated_lufs"] = integrated
        }
        if let target = report.target {
            measured["target_lufs"] = target
        }
        return measured
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
