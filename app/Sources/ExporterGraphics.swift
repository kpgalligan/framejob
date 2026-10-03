import CoreGraphics
import Foundation

/// An export's graphics (road map 10 §5f, G-8 and G-13, G3c): the gate that
/// refuses a module that does not compile before anything is built, and the
/// mapping from a graphic that failed mid-export to the error the caller
/// reads.
///
/// **The set is PINNED, not looked up.** `Exporter.export` and
/// `renderFrameReported` pin the `GraphicSet` their caller captured on their
/// own `RecipeSource` key (`GraphicRegistry.pin`), so an export draws the
/// modules as they compiled when it was asked for, whatever the document's
/// store does next, and a queued job draws the set it was ENQUEUED with.
/// Every pin has its `unpin` on each exit: `finish`, `deinit`, and
/// `renderFrameReported`'s `defer`.
///
/// **The gate is compile-only** (G-8 asks for no dry run): a module that
/// throws at frame 900 is found at frame 900. The render thread records the
/// failure on the export's key; the progress timer reads it on main and
/// cancels, and `finish` replaces whatever the pipeline answered with
/// `.graphicFailed` and removes the file.
extension Exporter {

    /// One offline frame and what its graphics reported while it was drawn:
    /// the failure first, then the warnings (`GraphicRegistry.reports`).
    struct RenderedFrame {
        let image: CGImage?
        let graphics: [GraphicReport]
    }

    /// `.graphicsNotCompiled` when a graphic clip the export will draw has a
    /// module that failed to compile or has none, else nil. Nothing to gate
    /// with no set or an audio-only export. The clips are the top level's in
    /// `settings`' range, plus every graphic clip of each nest reached from a
    /// clip in the range, however deep — the whole nest, not its window,
    /// which over-includes by decision.
    static func graphicsRefusal(
        project: ReelProject, settings: ExportSettings, graphics: GraphicSet?
    ) -> ExportError? {
        guard let graphics = graphics, !settings.isAudioOnly else { return nil }
        let names = graphicNames(project: project, settings: settings)
        let refused = names.sorted().compactMap { name -> (name: String, message: String)? in
            switch graphics.modules[name] {
            case nil:
                return (name, "has no module in graphics/")
            case .failed(let diagnostics, _)?:
                let reason = diagnostics.first?.located ?? "the engine gave no reason"
                return (name, "does not compile — " + reason)
            case .compiled?:
                return nil
            }
        }
        return refused.isEmpty ? nil : .graphicsNotCompiled(refused)
    }

    /// The module names of every graphic clip the export draws: the top
    /// level's in `settings`' range, plus every graphic clip of each nest
    /// reached from a clip in the range, however deep.
    static func graphicNames(project: ReelProject, settings: ExportSettings) -> Set<String> {
        let range = settings.start..<(settings.start + settings.duration)
        let snapshot = project.snapshot
        var names = Set<String>()
        var visited = Set<UInt32>()
        for clip in snapshot.clips where clip.start < range.upperBound && clip.end > range.lowerBound {
            if let graphic = clip.graphic { names.insert(graphic.name) }
            guard let id = clip.source.nestID else { continue }
            collectGraphicNames(inNest: id, of: snapshot, into: &names, visited: &visited)
        }
        return names
    }

    /// Starts the export's graphic prefetch (spec §11 G-26) — only for the
    /// `ExportWriter` path, with a pinned set and a graphic in range — over
    /// the range the writer reads at the frame duration it reads at.
    /// `finish` and `deinit` stop it beside the unpin. Main thread.
    static func startGraphicPrefetch(
        key: Int?, project: ReelProject, graphics: GraphicSet?, built: BuiltComposition,
        settings: ExportSettings, pipeline: any ExportPipeline
    ) {
        guard let key = key, graphics != nil, pipeline is ExportWriter, !settings.isAudioOnly,
            !graphicNames(project: project, settings: settings).isEmpty
        else { return }
        GraphicPrefetch.shared.start(
            key: key, range: Exporter.timeRange(settings, composition: built.composition),
            frameDuration: ExportWriter.videoComposition(built, settings: settings).frameDuration)
    }

    /// Every graphic clip's module name in nest `id` and in each nest reached
    /// from it. `visited` is belt and braces: `check_nesting` refuses a
    /// cycle, but a hand-written file is not held to it (`pathToClip`'s rule).
    private static func collectGraphicNames(
        inNest id: UInt32, of snapshot: ProjectSnapshot,
        into names: inout Set<String>, visited: inout Set<UInt32>
    ) {
        guard visited.insert(id).inserted, let nest = snapshot.nest(id) else { return }
        for inner in nest.clips {
            if let graphic = inner.graphic { names.insert(graphic.name) }
            if let child = inner.source.nestID {
                collectGraphicNames(inNest: child, of: snapshot, into: &names, visited: &visited)
            }
        }
    }

    /// `.graphicFailed` for one failed report.
    static func graphicFailed(_ report: GraphicReport) -> ExportError {
        .graphicFailed(
            name: report.name, frame: report.frame,
            message: report.diagnostics.first?.message ?? "the engine gave no reason")
    }

    /// `result`, unless a graphic failed on `key`: then the file at
    /// `destination` is removed and the answer is `.graphicFailed`, whatever
    /// the pipeline said — a success, the cancel `pollProgress` asked for,
    /// or a reader's error.
    static func graphicOutcome(
        _ result: Result<URL, any Error>, key: Int?, destination: URL?
    ) -> Result<URL, any Error> {
        guard let key = key, let failure = GraphicRegistry.shared.failure(for: key) else {
            return result
        }
        if let destination = destination { try? FileManager.default.removeItem(at: destination) }
        return .failure(graphicFailed(failure))
    }

    /// The pin's non-failed reports, one per diagnostic; each (name,
    /// message) once, its first frame kept, in arrival order (G-24 (c)).
    static func graphicWarnings(from reports: [GraphicReport]) -> [ExportGraphicWarning] {
        var seen = Set<[String]>()
        var warnings: [ExportGraphicWarning] = []
        for report in reports where !report.failed {
            for diagnostic in report.diagnostics
            where seen.insert([report.name, diagnostic.located]).inserted {
                warnings.append(ExportGraphicWarning(
                    name: report.name, frame: report.frame, message: diagnostic.located))
            }
        }
        return warnings
    }

    /// `graphicWarnings(from:)` over what `key`'s pin holds; `[]` for nil.
    static func graphicWarnings(on key: Int?) -> [ExportGraphicWarning] {
        guard let key = key else { return [] }
        return graphicWarnings(from: GraphicRegistry.shared.reports(for: key))
    }

    /// The count a finished export's line ends with: "" for none. `hover`
    /// true (the progress sheet) adds "(hover for details)"; false is the
    /// queue's row, whose label truncates its tail.
    static func graphicWarningSuffix(
        _ warnings: [ExportGraphicWarning], hover: Bool = true
    ) -> String {
        guard !warnings.isEmpty else { return "" }
        let count = warnings.count == 1 ? "1 graphic warning" : "\(warnings.count) graphic warnings"
        return " " + count + (hover ? " (hover for details)." : ".")
    }

    /// The tooltip's list, one line each: "\"<name>\" at frame F: <message>"
    /// ("\"<name>\": <message>" with no frame); nil for none.
    static func graphicWarningDetails(_ warnings: [ExportGraphicWarning]) -> String? {
        guard !warnings.isEmpty else { return nil }
        return warnings.map { warning in
            let place = warning.frame.map { " at frame \($0)" } ?? ""
            return "\"\(warning.name)\"\(place): \(warning.message)"
        }.joined(separator: "\n")
    }
}

/// One distinct warning a graphic gave while an export drew it: the graphic,
/// the first frame (its own) it was given at, and the located message.
struct ExportGraphicWarning: Equatable {
    let name: String
    let frame: Int?
    let message: String
}

extension GraphicDiagnostic {
    /// The message, then ` (line L, column C)` when it has a line.
    var located: String {
        guard let line = line else { return message }
        return message + " (line \(line)" + (column.map { ", column \($0)" } ?? "") + ")"
    }
}
