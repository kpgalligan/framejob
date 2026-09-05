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
        if let requested = intArg(a, "max_width") {
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
    /// `ExportSheetController`). The preset is resolved into concrete settings
    /// by the CORE (`rc_export_settings`) and handed to the same
    /// `Exporter.export` the sheet uses: there is exactly one writer, so an
    /// agent export and a menu export cannot disagree.
    ///
    /// Blocks until the file is written, so the model can render, export and
    /// verify in sequence without polling.
    func exportProject(_ a: [String: Any]) throws -> String {
        let presetID = try requiredString(a, "preset")
        let path = try requiredString(a, "path")
        let wholeProject = (stringArg(a, "range") ?? "project").lowercased()
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
            var overrides: [String: Any]?
            if wholeProject == "in_out" {
                guard let range = document.inOutRange, range.end > range.start else {
                    throw ToolError(
                        message: "This project has no in/out range — set one with set_range "
                            + "{start, end}, or export with range \"project\".")
                }
                overrides = [
                    "range": ["start": range.start, "duration": range.end - range.start]
                ]
            }
            let settings: ExportSettings
            do {
                settings = try ReelExport.settings(
                    document.project, preset: presetID, overrides: overrides)
            } catch {
                let names = ReelExport.presets().map { $0.id }.joined(separator: ", ")
                throw ToolError(
                    message: error.localizedDescription + " The presets are: \(names).")
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
}
