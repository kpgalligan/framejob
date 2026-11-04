import Foundation

/// Make Vertical's summary (spec §11 VR-35) and its answer (VR-36): what `plan` did, said as
/// the sheet's and the tool's text and as `make_vertical_version`'s keys. A pure move out of
/// `VerticalVersion+Plan.swift` (road map "creator-jobs" VR5b's toll). Names no `rc_*`.
extension VerticalVersion {
    /// VR-35: the counts, then one line per re-laid switch (VR-54), then one line per entry
    /// with a reason; the graphic counts and lines VR4b's (`templates`, VR-44 (d)).
    static func summary(_ plan: Plan, templates: TemplateReport = TemplateReport()) -> String {
        func count(_ treatment: Treatment) -> Int {
            plan.entries.filter { $0.treatment == treatment }.count
        }
        var text = "Makes a \(plan.width) × \(plan.height) version."
        let followed = count(.followed)
        if followed > 0 { text += " Follows \(counted(followed, "clip"))." }
        if !plan.cursor.isEmpty {
            text += " Follows the cursor in \(counted(plan.cursor.count, "clip")), their own "
                + "zooms and pans replaced."
        }
        if !plan.speaker.isEmpty {
            text += " Follows whoever is talking in \(counted(plan.speaker.count, "clip"))."
        }
        if !plan.relaid.isEmpty {
            text += " Re-lays \(counted(plan.relaid.count, "camera layout")) for the new canvas."
        }
        let whole = count(.whole)
        if whole > 0 { text += " Shows \(counted(whole, "clip")) whole on a blurred copy." }
        let kept = count(.kept)
        if kept > 0 { text += " Keeps \(counted(kept, "clip")) as placed." }
        let refilled = count(.refilled)
        if refilled > 0 { text += " Re-fills \(counted(refilled, "background"))." }
        let removed = count(.removed)
        if removed > 0 {
            text += " Removes \(removed) blurred \(removed == 1 ? "copy" : "copies") the "
                + "framing replaces."
        }
        text += graphicsCounts(plan, templates)
        if plan.backgrounds { text += " Adds a Backgrounds track for the blurred copy." }
        if plan.moreTracks > 0 {
            text += " Adds \(plan.moreTracks) more \(plan.moreTracks == 1 ? "track" : "tracks")"
                + " behind it where clips overlap."
        }
        if plan.reEased > 0 { text += " \(counted(plan.reEased, "action")) re-eased at a cut." }
        if plan.carried > 0 {
            text += " \(counted(plan.carried, "action")) "
                + (plan.carried == 1 ? "carries" : "carry") + " a framing move."
        }
        if let relaid = plan.captions?.relaid.count, relaid > 0 {
            text += " Re-lays \(counted(relaid, "caption track")) for the new canvas."
        }
        let canvas = plan.project.snapshot.canvas
        var lines = [text] + plan.relaid.map { relaidLine($0, canvas: canvas) }
        for entry in plan.entries {
            guard let reason = entry.reason else { continue }
            let why = reason.hasSuffix(".") ? String(reason.dropLast()) : reason
            switch entry.treatment {
            case .notFollowed: lines.append("Clip \(entry.clip) is not followed: \(why).")
            default: lines.append("Clip \(entry.clip) is followed, but \(why).")
            }
        }
        lines += (plan.captions?.kept ?? []).map(CaptionRelayout.keptLine)
        lines += graphicsLines(templates)
        return lines.joined(separator: "\n")
    }

    /// VR-39 (d)'s pending summary, while the analysis is still to be made; with `speaker` it
    /// says the sheet comes back to confirm the microphones' faces (VR-66 (e)).
    static func pendingSummary(files: Int, width: Int, height: Int, speaker: Bool = false)
        -> String
    {
        "Finds the faces, people and shot changes in \(counted(files, "file")) on this Mac "
            + "first, " + (speaker ? "then asks you to confirm who is on each microphone, " : "")
            + "then makes a \(width) × \(height) version."
    }

    /// The answer's keys every door shares (VR-36): `canvas`, `clips` in id order,
    /// `backgrounds`, `more_tracks`, `re_eased`, `moves_carried`, `summary`, `graphics`,
    /// `cursor` (VR-52), `relaid` (VR-54) and `speaker` (VR-64 (f)).
    static func answerFields(_ plan: Plan, templates: TemplateReport = TemplateReport())
        -> [String: Any]
    {
        let clips: [[String: Any]] = plan.entries.map { entry in
            var row: [String: Any] = [
                "clip": Int(entry.clip), "treatment": entry.treatment.rawValue,
            ]
            if let reason = entry.reason { row["reason"] = reason }
            return row
        }
        var fields: [String: Any] = [
            "canvas": ["width": plan.width, "height": plan.height],
            "clips": clips,
            "backgrounds": plan.backgrounds,
            "more_tracks": plan.moreTracks,
            "re_eased": plan.reEased,
            "moves_carried": plan.carried,
            "summary": summary(plan, templates: templates),
            "cursor": plan.cursor.map { Int($0) },
            "relaid": relaidFields(plan.relaid),
            "speaker": plan.speaker.map { framed -> [String: Any] in
                [
                    "clip": Int(framed.clip), "mics": framed.mics.map { Int($0) },
                    "mic_faces": framed.faces.map { Int($0) },
                ]
            },
            "graphics": graphicsFields(plan, templates),
        ]
        if let captions = plan.captions {
            fields["captions"] = CaptionRelayout.answerFields(captions)
        }
        return fields
    }

    static func counted(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
