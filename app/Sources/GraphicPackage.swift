// app/Sources/GraphicPackage.swift — the Graphic dialog's Export… and
// `export_graphic` (spec §11 G-46): one graphic written as a `.fjgraphic`
// package holding its module and only the project fonts and assets the
// engine saw it use.
//
// **A job is built on main and written off it.** `GraphicPackageJob.project`
// and `.template` read the document on main: the module's bytes, its title,
// category and description (`GraphicCatalog`), its size and length
// (`AgentServer.metaWhole`, as `render_graphic` reads them), and a FRESH
// library (`GraphicStore.makeIndexedLibrary()`; a template's holds the
// bundled faces alone). `write(to:)` runs QuickJS, so it runs only on the
// sheet's 8 MiB `Thread` or the agent's server thread — never main, never GCD.
//
// **The usage rule** (G-46 (b)): the module is compiled against that library
// and drawn — every frame up to `maxFrames` with its default props, else
// `maxFrames` evenly spaced, each `svg` then `rasterize` — and then each
// variant (an `enum` option other than the default, a boolean's opposite, in
// schema order, at most `maxVariants`) over `variantFrames` evenly spaced
// frames, every other prop at its default. The library's `usage()` is then
// every project font blob and asset to pack; a bundled face never is. A
// frame that throws is skipped and counted.
//
// **The file** is the core's (`ReelGraphicPackage.write`): written as
// `.<file>.partial` beside the destination and renamed over it, so an
// existing file is replaced whole; any throw removes the partial file.

import Foundation
import UniformTypeIdentifiers

enum GraphicPackage {
    static let fileExtension = "fjgraphic", typeIdentifier = "com.kgalligan.framejob-graphic"
    static let maxFrames = 900, variantFrames = 30, maxVariants = 32

    /// The exported type (`project.yml`), else a zip by its extension.
    static var contentType: UTType {
        UTType(typeIdentifier)
            ?? UTType(filenameExtension: fileExtension, conformingTo: .zip) ?? .zip
    }

    /// The manifest's `app_version`: the bundle's `CFBundleShortVersionString`, else "".
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Every frame of `length` when there are at most `cap`, else `cap` frames evenly spaced
    /// from the first to the last.
    static func sampledFrames(length: Int, cap: Int) -> [Int] {
        guard length > cap else { return Array(0..<max(length, 0)) }
        guard cap > 1 else { return cap == 1 ? [0] : [] }
        return (0..<cap).map { i in
            Int((Double(i) * Double(length - 1) / Double(cap - 1)).rounded())
        }
    }

    /// The props of each variant G-46 (b) draws: one per `enum` option other than its
    /// default and one per boolean's opposite, in schema order, at most `maxVariants`.
    static func variants(_ schema: GraphicSchema) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for entry in schema.entries {
            switch (entry.type, entry.default) {
            case ("enum", let value):
                let current: String? = { if case .string(let s) = value { return s }; return nil }()
                for option in entry.options where option != current {
                    out.append([entry.key: option])
                }
            case ("boolean", .bool(let flag)):
                out.append([entry.key: !flag])
            default:
                continue
            }
        }
        return Array(out.prefix(maxVariants))
    }
}

/// What one export wrote.
struct GraphicPackageResult {
    let url: URL
    /// The manifest's in-package paths, in order; `manifest.json` itself is not among them.
    let files: [String]
    /// Every frame drawn (the defaults' and the variants'), and how many of them threw.
    let frames: Int
    let failedFrames: Int
}

/// One graphic, read off the document on main, ready to be written off it.
struct GraphicPackageJob {
    let name: String
    /// What a compile failure names: `graphics/<name>.js` or `the template "<name>"`.
    let label: String
    let title: String
    let category: String
    let description: String?
    let source: Data
    let library: GraphicLibrary
    /// The library's font blobs: the project file each came from, nil for a bundled face.
    let fonts: [GraphicFile?]
    let assets: [GraphicFile]
    let width: Int
    let height: Int
    let length: Int
    let fps: Fps
    let canvas: CanvasSnapshot
    let appVersion: String

    /// A This Project module, read on main. Throws the store's sentence when the folder does
    /// not hold it.
    static func project(named name: String, document: ProjectDocument) throws -> GraphicPackageJob {
        guard let store = document.graphicStore else {
            throw ReelCoreError(message: ProjectDocument.noGraphicsFolderSentence)
        }
        let indexed = try store.makeIndexedLibrary()
        guard let file = indexed.scan.modules[name] else {
            throw ReelCoreError(message: store.noModuleSentence(name))
        }
        var meta: [String: Any] = [:]
        if case .compiled(_, _, let described, _)? = GraphicRegistry.shared.entry(
            named: name, for: document.recipeKey)
        {
            meta = described
        }
        return try make(
            name: name, label: "graphics/\(name).js", meta: meta, source: file.bytes,
            library: indexed.library, fonts: indexed.fonts, assets: indexed.scan.assets,
            document: document)
    }

    /// A bundled template, read on main, with a library of the bundled faces alone.
    static func template(
        _ entry: GraphicTemplateLibrary.Entry, document: ProjectDocument
    ) throws -> GraphicPackageJob {
        let name = entry.template.name
        let source: Data
        do {
            source = try Data(contentsOf: entry.template.url)
        } catch {
            throw ReelCoreError(
                message: "\(entry.template.url.path) could not be read: "
                    + error.localizedDescription)
        }
        let library = GraphicLibrary()
        var fonts: [GraphicFile?] = []
        for url in GraphicStore.bundledFontURLs(in: ProjectDocument.bundledFontsDirectory) {
            try library.addFont(Data(contentsOf: url))
            fonts.append(nil)
        }
        var meta: [String: Any] = [:]
        if case .compiled(_, _, let described, _) = entry.entry { meta = described }
        return try make(
            name: name, label: "the template \"\(name)\"", meta: meta, source: source,
            library: library, fonts: fonts, assets: [], document: document)
    }

    private static func make(
        name: String, label: String, meta: [String: Any], source: Data, library: GraphicLibrary,
        fonts: [GraphicFile?], assets: [GraphicFile], document: ProjectDocument
    ) throws -> GraphicPackageJob {
        let canvas = document.project.snapshot.canvas
        let tick = max(canvas.fps.frameDuration, 1)
        let width: Int, height: Int, length: Int
        do {
            width = try AgentServer.metaWhole(meta, "width", name, in: AgentServer.sides)
                ?? canvas.width
            height = try AgentServer.metaWhole(meta, "height", name, in: AgentServer.sides)
                ?? canvas.height
            length = try AgentServer.metaWhole(
                meta, "durationInFrames", name, in: 1...Int.max / Int(tick))
                ?? Int((5 * canvas.fps.double).rounded(.up))
        } catch let error as AgentServer.ToolError {
            throw ReelCoreError(message: error.message)
        }
        return GraphicPackageJob(
            name: name, label: label, title: GraphicCatalog.title(meta: meta, name: name),
            category: GraphicCatalog.category(meta: meta),
            description: GraphicCatalog.description(meta: meta), source: source,
            library: library, fonts: fonts, assets: assets, width: width, height: height,
            length: length, fps: canvas.fps, canvas: canvas, appVersion: GraphicPackage.appVersion)
    }

    /// Compiles, draws by G-46 (b)'s rule, and writes the package at `url`, replacing a file
    /// there. Never on main and never on GCD: the sheet's 8 MiB `Thread` or the agent's server
    /// thread. Throws a sentence, writing nothing, for a module that does not compile.
    func write(to url: URL) throws -> GraphicPackageResult {
        let module: GraphicModule
        do {
            module = try GraphicModule.compile(
                library: library, name: name, source: String(decoding: source, as: UTF8.self),
                budgetMs: GraphicRegistry.offlineBudgetMs)
        } catch {
            let first = GraphicDiagnostic.of(error).first
            let line = first?.line.map { " (line \($0))" } ?? ""
            throw ReelCoreError(
                message: "\(label) does not compile: " + (first?.message ?? "no diagnostic")
                    + line)
        }
        let describe = module.describeJSON()
        let described = (try? JSONSerialization.jsonObject(with: Data(describe.utf8)))
            as? [String: Any]
        let schema = GraphicSchema(
            describeJSON: describe, schema: described?["schema"] as? [String: Any] ?? [:])
        var frames = 0, failed = 0
        let sample = { (frame: Int, props: [String: Any]) in
            frames += 1
            if !self.draw(module, frame: frame, props: props) { failed += 1 }
        }
        for frame in GraphicPackage.sampledFrames(length: length, cap: GraphicPackage.maxFrames) {
            sample(frame, [:])
        }
        let variantFrames = GraphicPackage.sampledFrames(
            length: length, cap: GraphicPackage.variantFrames)
        for props in GraphicPackage.variants(schema) {
            for frame in variantFrames { sample(frame, props) }
        }

        let usage = library.usage()
        let usedFonts = usage.fonts.compactMap { fonts.indices.contains($0) ? fonts[$0] : nil }
        let usedAssets = usage.assets.compactMap { used in assets.first { $0.name == used } }
        var listed: [[String: Any]] = [["path": "\(name).js", "size": source.count]]
        var data = source
        for (folder, files) in [
            (GraphicStore.fontsFolderName, usedFonts), (GraphicStore.assetsFolderName, usedAssets),
        ] {
            for file in files {
                listed.append(["path": "\(folder)/\(file.name)", "size": file.bytes.count])
                data.append(file.bytes)
            }
        }
        let spec: [String: Any] = [
            "module": name, "title": title, "category": category,
            "description": description ?? NSNull(), "app_version": appVersion, "files": listed,
        ]
        let specJSON = String(
            decoding: try JSONSerialization.data(withJSONObject: spec), as: UTF8.self)

        let partial = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).partial")
        let manifest: String
        do {
            manifest = try ReelGraphicPackage.write(
                path: partial.path, packageJSON: specJSON, data: data)
            guard rename(partial.path, url.path) == 0 else {
                let why = String(cString: strerror(errno))
                throw ReelCoreError(message: "\(url.path) could not be replaced: \(why)")
            }
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        let parsed = (try? JSONSerialization.jsonObject(with: Data(manifest.utf8)))
            as? [String: Any]
        let paths = (parsed?["files"] as? [[String: Any]] ?? [])
            .compactMap { $0["path"] as? String }
        return GraphicPackageResult(url: url, files: paths, frames: frames, failedFrames: failed)
    }

    /// One frame drawn and rasterized at the graphic's size; false when either threw.
    private func draw(_ module: GraphicModule, frame: Int, props: [String: Any]) -> Bool {
        let ctx = AgentServer.graphicContext(
            frame: frame, fps: fps, length: length, width: width, height: height, canvas: canvas)
        guard let ctxData = try? JSONSerialization.data(withJSONObject: ctx),
            let propsData = try? JSONSerialization.data(withJSONObject: props)
        else { return false }
        do {
            let drawn = try module.svg(
                frame: frame, propsJSON: String(decoding: propsData, as: UTF8.self),
                ctxJSON: String(decoding: ctxData, as: UTF8.self),
                budgetMs: GraphicRegistry.offlineBudgetMs)
            _ = try library.rasterize(drawn.svg, width: width, height: height)
            return true
        } catch {
            return false
        }
    }
}
