import CryptoKit
import Foundation

/// Make Vertical's graphics (spec §11 VR-42, VR-44; road map "creator-jobs" VR4b): a graphic the
/// old canvas's size re-sized to the new one in step (4) (`graphicOps`), and a project's own
/// copies of road map 10's six templates surveyed by revision (`templateSurvey`), rewritten with
/// the bundled text only in a copy (`updateTemplates`, `ProjectDocument+VerticalCopy.swift`) and
/// listed otherwise, with the answer's `graphics` and the summary's graphic lines. The table is
/// `GraphicTemplates+Revisions.swift`'s. Names no `rc_*`.
extension VerticalVersion {

    /// VR-42 (b): `set_graphic {width, height}` to the new canvas; the base x and y, when either
    /// is non-zero, and each action end's named x and y by the axis ratios. Scale is never
    /// touched: the graphic is the canvas's size again, so its scale means what it meant.
    static func graphicOps(
        _ clip: ClipSnapshot, from old: CanvasSnapshot, width: Int, height: Int
    ) -> [ReelOp] {
        let rx = Double(width) / Double(max(1, old.width))
        let ry = Double(height) / Double(max(1, old.height))
        var ops: [ReelOp] = [
            .setGraphicRaw(clips: [clip.id], patch: ["width": width, "height": height])
        ]
        let video = clip.videoProps
        if video.x != 0 || video.y != 0 {
            ops.append(
                .setVideo(clips: [clip.id], patch: VideoPatch(x: video.x * rx, y: video.y * ry)))
        }
        for action in clip.actions {
            guard let end = action.end.video, end.x != nil || end.y != nil else { continue }
            var moved: [String: Any] = [:]
            if let x = end.x { moved["x"] = x * rx }
            if let y = end.y { moved["y"] = y * ry }
            ops.append(.setActionEndRaw(clip: clip.id, action: action.id, patch: ["video": moved]))
        }
        return ops
    }

    /// VR-44 (b): the drawn modules that are an older copy of a bundled template (module →
    /// stem) and those matching no shipped revision that size themselves by height (sorted).
    struct TemplateSurvey: Equatable {
        var outdated: [String: String] = [:]
        var byHeight: [String] = []
    }

    /// VR-44 (d): what was (or will be) updated and what is listed, both by name.
    struct TemplateReport: Equatable {
        struct Listed: Equatable {
            let name: String
            let reason: String
        }
        var updated: [String] = []
        var listed: [Listed] = []
    }

    static let byHeightReason =
        "it sizes itself by the canvas's height, so it may not fit the narrow frame"

    static func inPlaceReason(_ stem: String) -> String {
        "it is an older copy of the bundled template \"\(stem)\"; Make Vertical updates it only "
            + "in a copy"
    }

    /// The SHA-256 of a bundled template's text, nil when it cannot be read.
    private static func bundledRevision(_ stem: String, in bundled: URL) -> String? {
        let url = bundled.appendingPathComponent(stem + ".js")
        guard let bytes = try? Data(contentsOf: url) else { return nil }
        return GraphicStore.hex(SHA256.hash(data: bytes))
    }

    /// VR-44 (b), main: over `DerivedCarry.drawnGraphicNames`, each name's scanned module —
    /// outdated when its revision is a shipped row for stem S other than the readable bundled
    /// `<S>.js`'s (by revision, never by name); by height when no row matches and its text
    /// measures by `ctx.height / 1080`. No store, an empty survey.
    static func templateSurvey(
        _ project: ReelProject, store: GraphicStore?,
        bundled: URL = GraphicTemplates.bundledDirectory
    ) -> TemplateSurvey {
        var survey = TemplateSurvey()
        guard let store else { return survey }
        var current: [String: String?] = [:]
        for name in DerivedCarry.drawnGraphicNames(project.snapshot).sorted() {
            guard let module = store.module(named: name) else { continue }
            if let stem = GraphicTemplates.shippedRevisions[module.revision] {
                if current[stem] == nil { current[stem] = bundledRevision(stem, in: bundled) }
                if let now = current[stem] ?? nil, now != module.revision {
                    survey.outdated[name] = stem
                }
            } else if GraphicTemplates.measuresByHeight(
                String(decoding: module.bytes, as: UTF8.self))
            {
                survey.byHeight.append(name)
            }
        }
        return survey
    }

    /// VR-44 (c), predicted: with `copy` the outdated modules are updated; without it each is
    /// listed with the in-place reason. Both list the modules that size by height.
    static func templateReport(_ survey: TemplateSurvey, copy: Bool) -> TemplateReport {
        var report = TemplateReport()
        var listed = survey.byHeight.map { TemplateReport.Listed(name: $0, reason: byHeightReason) }
        if copy {
            report.updated = survey.outdated.keys.sorted()
        } else {
            listed += survey.outdated.map {
                TemplateReport.Listed(name: $0.key, reason: inPlaceReason($0.value))
            }
        }
        report.listed = listed.sorted { $0.name < $1.name }
        return report
    }

    /// VR-44 (c), main, the copy only: each outdated module rewritten with the bundled text
    /// through `store.write(name:source:)`, then ONE `rescan()`, whose pass keeps the replaced
    /// text as the module's history (`keepReplaced`). A failure lists the module.
    static func updateTemplates(
        _ survey: TemplateSurvey, in store: GraphicStore, from bundled: URL
    ) -> TemplateReport {
        var report = TemplateReport()
        var listed = survey.byHeight.map { TemplateReport.Listed(name: $0, reason: byHeightReason) }
        for (name, stem) in survey.outdated.sorted(by: { $0.key < $1.key }) {
            do {
                let source = try String(
                    contentsOf: bundled.appendingPathComponent(stem + ".js"), encoding: .utf8)
                try store.write(name: name, source: source)
                report.updated.append(name)
            } catch {
                listed.append(
                    TemplateReport.Listed(
                        name: name,
                        reason: "it could not be updated: \(error.localizedDescription)"))
            }
        }
        if !survey.outdated.isEmpty { store.rescan() }
        report.listed = listed.sorted { $0.name < $1.name }
        return report
    }

    /// The answer's `graphics {resized, updated, listed [{name, reason}]}` (VR-36 as amended).
    static func graphicsFields(_ plan: Plan, _ templates: TemplateReport) -> [String: Any] {
        [
            "resized": plan.entries.filter { $0.treatment == .resized }.count,
            "updated": templates.updated,
            "listed": templates.listed.map { ["name": $0.name, "reason": $0.reason] },
        ]
    }

    /// The summary's graphic counts, after the removed copies (VR-35 as amended).
    static func graphicsCounts(_ plan: Plan, _ templates: TemplateReport) -> String {
        var text = ""
        let resized = plan.entries.filter { $0.treatment == .resized }.count
        if resized > 0 { text += " Re-sizes \(counted(resized, "graphic")) to the new canvas." }
        let updated = templates.updated.count
        if updated > 0 {
            text += " Updates \(counted(updated, "graphic module")) to the current template."
        }
        return text
    }

    /// One line per listed module, after the caption lines.
    static func graphicsLines(_ templates: TemplateReport) -> [String] {
        templates.listed.map { "Graphic module \"\($0.name)\" is left as it is: \($0.reason)." }
    }
}
