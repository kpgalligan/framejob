import AppKit

#if FRAMEJOB_DEV_TOOLS
/// `snapshot_ui` — a dev tool (road map 11's V2a, spec §11 V-1..V-3): the
/// app's windows listed, or one of them captured through `cacheDisplay` as
/// an MCP image block and a PNG on disk, with a layout dump beside it.
///
/// **It runs on the SERVER thread** (`devOffMainTools`), where the road map
/// said main: the fill waits on `Exporter.renderFrameReported`, which
/// decodes, and the settle waits 20 ms between passes, and neither may hold
/// the main thread. So every AppKit touch is an `onMain` hop — one to
/// resolve the window, one to stage, one per pass, one to read the facts and
/// the layout and unstage — and the waits are this thread's.
///
/// **It never needs the app active or its window visible**: `cacheDisplay`
/// draws the view tree, not the screen, and every fact that could change a
/// picture (`active`, `key`, `occluded`, `scale`, `color_space`) comes back
/// in `window_facts` so a comparison can refuse to compare what differs.
extension AgentServer {

    private struct SnapshotRequest {
        let window: UISnapshot.WindowKind
        let region: UISnapshot.Region?
        let url: URL
        let fill: Bool
        let layout: Bool
    }

    /// The fill's inputs, read on main in the first hop.
    private struct FillContext {
        let project: ReelProject
        let urls: [UInt32: URL]
        let playhead: Ticks
        let graphics: GraphicSet?
        let maxWidth: Int
    }

    private static let captureArguments = ["view", "path", "fill_preview", "layout"]
    private static let appearanceRefusal = "appearance is refused: switched on a live window it "
        + "left colours built in the launch appearance, a mix the app never draws. Launch the "
        + "instance with -RCDevAppearance light or -RCDevAppearance dark instead."

    func snapshotUI(_ a: [String: Any]) throws -> String {
        guard let request = try snapshotRequest(a) else {
            return try jsonResult(onMain { UISnapshot.listing() })
        }
        let (subject, context) = try onMain { try self.snapshotSubject(a, request) }

        var picture: CGImage?
        var tick: Ticks?
        if let context {
            picture = Exporter.renderFrameReported(
                project: context.project, urls: context.urls, at: context.playhead,
                maxWidth: context.maxWidth, options: .none, graphics: context.graphics
            ).image
            tick = context.playhead
        }

        var staging: UISnapshot.Staging? = onMain {
            UISnapshot.stage(subject, picture: picture)
        }
        defer {
            if let left = staging { onMain { UISnapshot.unstage(left) } }
        }

        var last: UISnapshot.Pass?
        var passes = 0
        var settled = false
        while passes < UISnapshot.settleLimit {
            guard let next = onMain({ UISnapshot.pass(subject.root) }) else {
                throw ToolError(message: "The \(request.window.rawValue) window did not draw.")
            }
            passes += 1
            if let previous = last, previous.bytes == next.bytes {
                last = next
                settled = true
                break
            }
            last = next
            Thread.sleep(forTimeInterval: UISnapshot.settleInterval)
        }
        guard let capture = last, let image = capture.rep.cgImage else {
            throw ToolError(message: "The \(request.window.rawValue) window did not draw.")
        }

        var result: [String: Any] = [:]
        var layoutReport: [String: Any]?
        var points = CGSize.zero
        onMain {
            result = self.snapshotFacts(subject, request)
            points = subject.root.bounds.size
            if request.layout {
                layoutReport = UISnapshotLayout.report(root: subject.root, skipping: staging?.fill)
            }
            if let done = staging {
                UISnapshot.unstage(done)
                staging = nil
            }
        }

        if subject.kind == .editor {
            let preview = previewState(request, filled: picture != nil, asked: context != nil)
            result["preview"] = preview.state
            result["preview_note"] = preview.note
            if picture != nil, let tick { result["preview_tick"] = tick }
        }
        do {
            try FrameWriter.write(image, as: .png, to: request.url)
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        guard let data = try? Data(contentsOf: request.url) else {
            throw ToolError(message: "Wrote \(request.url.path) but could not read it back.")
        }
        result["ok"] = true
        result["window"] = request.window.rawValue
        result["view"] = request.region?.rawValue ?? NSNull()
        result["path"] = request.url.path
        result["width_px"] = capture.rep.pixelsWide
        result["height_px"] = capture.rep.pixelsHigh
        result["points"] = [UISnapshot.round2(points.width), UISnapshot.round2(points.height)]
        result["settled"] = settled
        result["passes"] = passes
        result["layout_path"] = NSNull()
        if let layoutReport {
            let layoutURL = request.url.deletingPathExtension()
                .appendingPathExtension("layout.json")
            var file = layoutReport
            file["window"] = request.window.rawValue
            file["view"] = request.region?.rawValue ?? NSNull()
            file["scale"] = result["scale"]
            file["size"] = result["points"]
            let json = try JSONSerialization.data(
                withJSONObject: file, options: [.prettyPrinted, .sortedKeys])
            do {
                try json.write(to: layoutURL)
            } catch {
                throw ToolError(
                    message: "Could not write \(layoutURL.path): \(error.localizedDescription)")
            }
            result["layout_path"] = layoutURL.path
            result["problems"] = layoutReport["problems"] ?? []
            result["private_problems"] =
                (layoutReport["private_problems"] as? [[String: Any]])?.count ?? 0
        }
        let text = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        return try callResult(
            content: [
                ["type": "image", "data": data.base64EncodedString(), "mimeType": "image/png"],
                ["type": "text", "text": String(decoding: text, as: UTF8.self)],
            ], isError: false)
    }

    // MARK: - Arguments

    /// Every argument read and refused here, off main, before any hop. nil
    /// is a listing.
    private func snapshotRequest(_ a: [String: Any]) throws -> SnapshotRequest? {
        let window = try enumArg(a, "window", UISnapshot.WindowKind.self)
        let region = try enumArg(a, "view", UISnapshot.Region.self)
        if a["appearance"] != nil { throw ToolError(message: Self.appearanceRefusal) }
        let path = try stringArg(a, "path")
        let fill = try boolArg(a, "fill_preview") ?? true
        let layout = try boolArg(a, "layout") ?? true
        let hasProject = a["project"] != nil && !(a["project"] is NSNull)
        guard let window else {
            let given = Self.captureArguments.filter { a[$0] != nil && !(a[$0] is NSNull) }
            if !given.isEmpty {
                throw ToolError(
                    message: "\(given.joined(separator: ", ")) \(given.count == 1 ? "is" : "are") "
                        + "for a capture and needs window; with no window snapshot_ui lists the "
                        + "open windows.")
            }
            if hasProject {
                throw ToolError(
                    message: "project names the editor to capture and needs window editor or "
                        + "sheet; with no window snapshot_ui lists every open window.")
            }
            return nil
        }
        if hasProject, window != .editor, window != .sheet {
            throw ToolError(
                message: "project cannot name the \(window.rawValue) window: it belongs to no "
                    + "document.")
        }
        if region != nil, window != .editor {
            throw ToolError(
                message: "view names a region of the editor and cannot be used with window "
                    + "\(window.rawValue).")
        }
        return SnapshotRequest(
            window: window, region: region,
            url: try snapshotDestination(path, window, region), fill: fill, layout: layout)
    }

    /// `render_frame`'s rule: an explicit path through `destinationURL`, its
    /// folder required to exist; none is a temporary file named for what it
    /// holds.
    private func snapshotDestination(
        _ path: String?, _ window: UISnapshot.WindowKind, _ region: UISnapshot.Region?
    ) throws -> URL {
        guard let path else {
            let name = ["framejob-ui", window.rawValue, region?.rawValue].compactMap { $0 }
                .joined(separator: "-")
            return Self.temporaryOutput(name, extension: "png")
        }
        return try Self.requireFolder(
            of: Self.destinationURL(try Self.nonEmptyOutputPath(path), extension: "png"))
    }

    // MARK: - Main-thread reads

    /// The window and view a request means, and the fill's inputs when the
    /// capture holds the preview. Main thread.
    private func snapshotSubject(
        _ a: [String: Any], _ request: SnapshotRequest
    ) throws -> (UISnapshot.Subject, FillContext?) {
        let kind = request.window
        switch kind {
        case .settings, .welcome, .recorder:
            guard let window = UISnapshot.openWindow(kind), let root = window.contentView else {
                throw ToolError(message: "The \(kind.title) window is not open.")
            }
            return (
                UISnapshot.Subject(window: window, root: root, kind: kind, region: nil, editor: nil),
                nil)
        case .editor, .sheet:
            let document = try target(a)
            let name = Self.path(of: document) ?? document.displayName ?? "Untitled"
            guard let editor = editor(document), let window = editor.view.window,
                let content = window.contentView
            else {
                throw ToolError(message: "The project \(name) has no window to capture.")
            }
            if kind == .sheet {
                guard let sheet = window.attachedSheet, let root = sheet.contentView else {
                    throw ToolError(message: "The project \(name)'s window has no sheet attached.")
                }
                if sheet is NSSavePanel {
                    let panel = NSStringFromClass(type(of: sheet))
                    throw ToolError(
                        message: "The attached sheet is a file panel (\(panel)), drawn out of "
                            + "process: it would capture as one colour.")
                }
                return (
                    UISnapshot.Subject(
                        window: sheet, root: root, kind: kind, region: nil, editor: nil),
                    nil)
            }
            var root: NSView = content
            if let region = request.region {
                guard let view = UISnapshot.regionView(region, of: editor) else {
                    throw ToolError(message: "The editor has no \(region.rawValue) region.")
                }
                root = view
            }
            let subject = UISnapshot.Subject(
                window: window, root: root, kind: kind, region: request.region, editor: editor)
            guard request.fill, request.region == nil || request.region == .preview,
                let canvas = editor.previewCanvas
            else { return (subject, nil) }
            let width = ceil(canvas.playerHost.frame.width * window.backingScaleFactor)
            let context = FillContext(
                project: document.editedProject, urls: document.mediaURLs(),
                playhead: document.playhead,
                graphics: GraphicRegistry.shared.snapshot(for: document.recipeKey),
                maxWidth: min(8192, max(16, Int(width))))
            return (subject, context)
        }
    }

    /// The facts, the scale, the effective appearance and, for the editor,
    /// the regions and the well. Main thread, before `unstage`.
    private func snapshotFacts(
        _ subject: UISnapshot.Subject, _ request: SnapshotRequest
    ) -> [String: Any] {
        let window = subject.window
        let match = subject.root.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        var result: [String: Any] = [
            "window_facts": UISnapshot.facts(window),
            "scale": Double(window.backingScaleFactor),
            "appearance": match == .darkAqua ? "dark" : "light",
        ]
        guard let editor = subject.editor, let content = window.contentView else { return result }
        var regions: [String: Any] = [:]
        for region in UISnapshot.Region.allCases {
            guard let view = UISnapshot.regionView(region, of: editor) else { continue }
            regions[region.rawValue] = UISnapshot.rect(view, in: content)
        }
        result["regions"] = regions
        result["origin"] = UISnapshot.rect(subject.root, in: content)
        if let host = editor.previewCanvas?.playerHost, host.isDescendant(of: subject.root) {
            result["well"] = UISnapshot.rect(host, in: subject.root)
        } else {
            result["well"] = NSNull()
        }
        return result
    }

    private func previewState(
        _ request: SnapshotRequest, filled: Bool, asked: Bool
    ) -> (state: String, note: String) {
        if let region = request.region, region != .preview {
            return (
                "not_in_capture",
                "The preview is not in the \(region.rawValue) region, so nothing was filled.")
        }
        if !request.fill {
            return (
                "unfilled",
                "fill_preview was false: the well shows what cacheDisplay draws of it, the "
                    + "canvas background, not the picture.")
        }
        if filled {
            return (
                "filled",
                "The well holds render_frame's picture at the playhead, put under the canvas "
                    + "overlay for the capture and removed after.")
        }
        if !asked { return ("unfilled", "The editor has no preview canvas to fill.") }
        return (
            "no_frame",
            "No frame at the playhead (an empty timeline, the playhead past the end, or "
                + "missing media): the well shows the canvas background.")
    }

    // MARK: - Catalog

    func snapshotUITool() -> [String: Any] {
        tool(
            "snapshot_ui",
            "DEV TOOL (absent from Distribution builds). Look at the app's chrome. With no "
                + "window, lists the visible windows (kind, class, title, frame, content size, "
                + "scale, visible, occluded, key, main, the editor's project path and any "
                + "attached sheet). With window, captures it through cacheDisplay — it works "
                + "with the app inactive and its window behind others — and answers an image "
                + "block plus a JSON text block: the PNG's path, its size in px and points, the "
                + "scale, the effective appearance, whether two passes settled, the window's "
                + "facts, for the editor the four regions' rects and the preview well's, and "
                + "with layout the problems a layout dump found (ambiguous layout, a view past "
                + "its superview, a truncated text field; AppKit's private _NS views counted "
                + "apart). The dump itself is written beside the PNG as <name>.layout.json.",
            [
                "window": [
                    "type": "string",
                    "enum": UISnapshot.WindowKind.allCases.map { $0.rawValue },
                    "description": "What to capture: editor (the project's editor window), "
                        + "sheet (the sheet attached to it), settings, welcome or recorder (the "
                        + "New Recording panel), when open. Omit to list the windows instead.",
                ],
                "view": [
                    "type": "string", "enum": UISnapshot.Region.allCases.map { $0.rawValue },
                    "description": "Editor only: capture one region, not the whole window.",
                ],
                "appearance": [
                    "type": "string",
                    "description": "Refused, whatever its value: the look is the instance's, "
                        + "chosen at launch with -RCDevAppearance light or dark.",
                ],
                "path": [
                    "type": "string",
                    "description": "Where to write the PNG; the folder must exist. Omit for a "
                        + "temporary file.",
                ],
                "fill_preview": [
                    "type": "boolean",
                    "description": "Put render_frame's picture at the playhead in the preview "
                        + "well, under the canvas overlay, for the capture (default true).",
                ],
                "layout": [
                    "type": "boolean",
                    "description": "Write the layout dump and answer its problems (default true).",
                ],
            ])
    }
}
#endif
