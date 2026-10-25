// app/Sources/AgentServer+GraphicRender.swift — `render_graphic` (road map
// 10 §5h, G4b): a module drawn WITHOUT a clip, as a contact sheet of up to
// sixteen frames with each frame number printed under its cell, or as one
// frame's SVG text.
//
// **Runs on the SERVER thread** (`AgentServer.offMainTools`), `render_frame`'s
// posture: sixteen 4K frames are seconds of work, and freezing the UI for them
// is not acceptable. Every document touch is inside one `onMain` — the
// target, the module as the registry compiled it, the canvas — and the draw
// after it is the engine's, which is any-thread (`GraphicModule.svg`,
// `GraphicLibrary.rasterize`). The module is held for the whole call, and it
// holds its library strongly, so a rescan mid-call swaps the registry's set
// and not this one.
//
// **The ctx is the clip's, with no clip** (`recipe_graphic.rs`'s keys
// exactly): the canvas's fps, `durationInFrames` from `meta` (else 5 s at
// that rate, ceiled), the module's size from the caller, else `meta`, else
// the canvas — `add_graphic_clip`'s defaults — and the project's canvas.
// A frame that throws or will not rasterize is its error card on the sheet
// and a sentence in the reply; a warning is a sentence too.
//
// **`format` is read and checked first** (spec §11 G-19): with svg a
// non-null `path`, `background` or `max_width` — the png sheet's — is refused
// by name, before the multi-frame refusal, since svg answers text and writes
// no file. A frame at or past `durationInFrames` is DRAWN, not refused, with
// `progress` clamped at 1: a clip longer than its length draws those frames
// too (G-9, G-19 (b)). A png sheet past `GraphicContactSheet.maxCellPixels`
// of frames is refused once the size is known, before any frame is drawn
// or any file written (G-20 (d)).

import Foundation

extension AgentServer {

    /// `render_graphic` — UI path: none — the preview well is a person's
    /// picture; §5j builds no strip.
    func renderGraphic(_ a: [String: Any]) throws -> String {
        let name = try requiredString(a, "name")
        let frames = try graphicFrames(a)
        let propsJSON = try graphicPropsJSON(a)
        let requestedWidth = try graphicSide(a, "width")
        let requestedHeight = try graphicSide(a, "height")
        let format = try stringArg(a, "format") ?? "png"
        guard format == "png" || format == "svg" else {
            throw ToolError(message: "format must be png or svg (got \"\(format)\").")
        }
        if format == "svg" {
            let sheetOnly = ["path", "background", "max_width"].filter {
                a[$0].map { !($0 is NSNull) } ?? false
            }
            if !sheetOnly.isEmpty {
                throw ToolError(
                    message: "format svg takes no path, background or max_width — those are the "
                        + "png contact sheet's; svg answers one frame's SVG text in the reply and "
                        + "writes no file (got \(sheetOnly.joined(separator: ", "))).")
            }
            if frames.count > 1 {
                throw ToolError(
                    message: "format svg answers ONE frame's SVG, and frames names "
                        + "\(frames.count); ask for one frame, or for a png contact sheet.")
            }
        }
        let maxWidth = try intArg(a, "max_width") ?? GraphicContactSheet.maxWidthDefault
        let widths = GraphicContactSheet.maxWidthMin...GraphicContactSheet.maxSide
        guard widths.contains(maxWidth) else {
            throw ToolError(
                message: "max_width must be \(widths.lowerBound)…\(widths.upperBound) px "
                    + "(got \(maxWidth)).")
        }
        let backgroundName = try stringArg(a, "background") ?? "transparent"
        guard let background = GraphicSheetBackground(backgroundName) else {
            throw ToolError(
                message: "background must be \(GraphicSheetBackground.accepted) "
                    + "(got \"\(backgroundName)\").")
        }
        let url = format == "png" ? try graphicSheetDestination(a, name: name) : nil

        let context = try onMain {
            () throws -> (module: GraphicModule, width: Int, height: Int, fps: Fps,
                canvas: CanvasSnapshot, frames: Int) in
            let document = try self.target(a)
            let compiled = try self.compiledModule(named: name, document)
            let canvas = document.project.snapshot.canvas
            let tick = max(canvas.fps.frameDuration, 1)
            let width = try requestedWidth.map(Int.init)
                ?? Self.metaWhole(compiled.meta, "width", name, in: Self.sides) ?? canvas.width
            let height = try requestedHeight.map(Int.init)
                ?? Self.metaWhole(compiled.meta, "height", name, in: Self.sides) ?? canvas.height
            let length = try Self.metaWhole(
                compiled.meta, "durationInFrames", name, in: 1...Int.max / Int(tick))
                ?? Int((5 * canvas.fps.double).rounded(.up))
            return (compiled.module, width, height, canvas.fps, canvas, length)
        }
        let pixels = frames.count * context.width * context.height
        if format == "png", pixels > GraphicContactSheet.maxCellPixels {
            throw ToolError(
                message: "A contact sheet draws at most \(GraphicContactSheet.maxCellPixels) px of "
                    + "frames; \(frames.count) frame(s) of \(context.width)×\(context.height) are "
                    + "\(pixels) px — ask for fewer frames or a smaller width and height.")
        }

        var reports: [GraphicReport] = []
        var cells: [GraphicSheetCell] = []
        for frame in frames {
            let ctx = Self.graphicContext(
                frame: frame, fps: context.fps, length: context.frames, width: context.width,
                height: context.height, canvas: context.canvas)
            let drawn: (svg: String, warnings: [GraphicDiagnostic])
            do {
                drawn = try context.module.svg(
                    frame: frame, propsJSON: propsJSON, ctxJSON: Self.jsonText(ctx),
                    budgetMs: GraphicRegistry.offlineBudgetMs)
            } catch {
                let diagnostics = Self.graphicDiagnostics(of: error)
                if format == "svg" {
                    return try svgReply(name, frame, nil, diagnostics, ctx)
                }
                reports.append(
                    GraphicReport(name: name, frame: frame, failed: true, diagnostics: diagnostics))
                cells.append(Self.cardCell(name, frame, diagnostics))
                continue
            }
            if format == "svg" {
                return try svgReply(name, frame, drawn.svg, drawn.warnings, ctx)
            }
            if !drawn.warnings.isEmpty {
                reports.append(
                    GraphicReport(name: name, frame: frame, failed: false, diagnostics: drawn.warnings))
            }
            do {
                let raster = try context.module.library.rasterize(
                    drawn.svg, width: context.width, height: context.height)
                if !raster.warnings.isEmpty {
                    reports.append(GraphicReport(
                        name: name, frame: frame, failed: false, diagnostics: raster.warnings))
                }
                cells.append(GraphicSheetCell(frame: frame, image: raster.cgImage(), cardText: nil))
            } catch {
                let diagnostics = Self.graphicDiagnostics(of: error)
                reports.append(
                    GraphicReport(name: name, frame: frame, failed: true, diagnostics: diagnostics))
                cells.append(Self.cardCell(name, frame, diagnostics))
            }
        }

        let layout = GraphicContactSheet.layout(
            count: cells.count, cellWidth: context.width, cellHeight: context.height,
            maxWidth: maxWidth)
        guard let url = url,
            let sheet = GraphicContactSheet.paint(cells, layout: layout, background: background)
        else {
            throw ToolError(
                message: "The contact sheet of \(layout.width)×\(layout.height) px could not be "
                    + "painted.")
        }
        do {
            try FrameWriter.write(sheet, as: .png, to: url)
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        guard let data = try? Data(contentsOf: url) else {
            throw ToolError(message: "Wrote \(url.path) but could not read it back.")
        }
        let listed = frames.map(String.init).joined(separator: ", ")
        var text = "Contact sheet of \(frames.count) frame(s) of \"\(name)\" — frames \(listed) — "
            + "each \(context.width)×\(context.height) px at scale "
            + String(format: "%g", layout.scale)
            + " on \(layout.columns)×\(layout.rows), \(layout.width)×\(layout.height) px, "
            + "background \(backgroundName)."
        for report in reports {
            text += " " + Self.graphicSentence(report)
        }
        text += " Written to \(url.path)."
        return try callResult(
            content: [
                ["type": "image", "data": data.base64EncodedString(), "mimeType": "image/png"],
                ["type": "text", "text": text],
            ], isError: false)
    }

    /// `frames` (1…16 whole numbers ≥ 0) or `frame`, never both; `[0]` for
    /// neither.
    private func graphicFrames(_ a: [String: Any]) throws -> [Int] {
        let single = try intArg(a, "frame")
        let listed = a["frames"].flatMap { $0 is NSNull ? nil : $0 }
        if single != nil, listed != nil {
            throw ToolError(message: "frame and frames are exclusive — pass one or the other.")
        }
        if let single = single {
            guard single >= 0 else { throw ToolError(message: "frame must be 0 or more: \(single).") }
            return [single]
        }
        guard let listed = listed else { return [0] }
        let limit = GraphicContactSheet.maxFrames
        guard let list = listed as? [Any], (1...limit).contains(list.count) else {
            throw ToolError(message: "frames must be a list of 1 to \(limit) frame numbers.")
        }
        return try list.enumerated().map { index, raw in
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                let whole = AgentServer.whole(number), whole >= 0
            else {
                throw ToolError(
                    message: "frames[\(index)] must be a whole frame number of 0 or more "
                        + "(got \(AgentServer.describe(raw))).")
            }
            return whole
        }
    }

    /// `props` as the JSON text the engine takes; `{}` when absent.
    private func graphicPropsJSON(_ a: [String: Any]) throws -> String {
        guard let raw = a["props"], !(raw is NSNull) else { return "{}" }
        guard let props = raw as? [String: Any] else {
            throw ToolError(message: "props must be an object keyed by the schema's names")
        }
        return Self.jsonText(props)
    }

    /// Where the sheet is written: `path` through `destinationURL` as a
    /// `.png`, its folder required to exist; else a temporary file.
    private func graphicSheetDestination(_ a: [String: Any], name: String) throws -> URL {
        guard let path = try stringArg(a, "path") else {
            return Self.temporaryOutput("framejob-graphic-\(name)", extension: "png")
        }
        return try Self.requireFolder(
            of: Self.destinationURL(try Self.nonEmptyOutputPath(path), extension: "png"))
    }

    /// `recipe_graphic.rs`'s ctx for `frame` of a `length`-frame graphic.
    private static func graphicContext(
        frame: Int, fps: Fps, length: Int, width: Int, height: Int, canvas: CanvasSnapshot
    ) -> [String: Any] {
        let rate = fps.double
        let progress = min(max(Double(frame) / Double(max(length - 1, 1)), 0), 1)
        return [
            "fps": rate, "time": rate > 0 ? Double(frame) / rate : 0,
            "durationInFrames": length, "progress": progress,
            "width": width, "height": height,
            "canvas": ["width": canvas.width, "height": canvas.height],
        ]
    }

    /// The `svg` format's answer: one frame's text, or why there is none.
    private func svgReply(
        _ name: String, _ frame: Int, _ svg: String?, _ diagnostics: [GraphicDiagnostic],
        _ ctx: [String: Any]
    ) throws -> String {
        try jsonResult([
            "name": name, "frame": frame, "ok": svg != nil, "svg": svg ?? NSNull(),
            "diagnostics": diagnostics.map(Self.diagnosticJSON), "ctx": ctx,
        ])
    }

    private static func cardCell(
        _ name: String, _ frame: Int, _ diagnostics: [GraphicDiagnostic]
    ) -> GraphicSheetCell {
        GraphicSheetCell(
            frame: frame, image: nil,
            cardText: LayerRenderers.errorCardText(
                name: name, frame: frame, diagnostic: diagnostics.first))
    }

    /// The engine's diagnostics out of a thrown error — one error saying
    /// what was thrown when it carries none.
    private static func graphicDiagnostics(of error: any Error) -> [GraphicDiagnostic] {
        if let failure = error as? GraphicFailure, !failure.diagnostics.isEmpty {
            return failure.diagnostics
        }
        return [GraphicDiagnostic(
            level: "error", message: error.localizedDescription, line: nil, column: nil,
            frame: nil)]
    }

    private static func jsonText(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
