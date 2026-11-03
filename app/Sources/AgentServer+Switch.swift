import Foundation

/// `copy_pieces` and `switch_angle` (road map "creator-jobs" SW1, spec §11
/// SW-11…SW-15), mirroring Clip ▸ Switch Angle ▸ (`switchAngle` in
/// `EditorViewController+SwitchAngle.swift`): `switch_angle` runs the menu's
/// own planner (`SwitchAngle.plan`) and commits it as one undo step;
/// `copy_pieces` is the op it writes with, one op, one undo step "Copy
/// Pieces". And `switch_by_speaker` (SW2b, spec §11 SW-23, SW-26), mirroring
/// Clip ▸ Switch by Speaker… (`SwitchSpeakerSheetController`) through the same
/// `SpeakerSwitch.read`, `plan` and `edit`, one undo step "Switch by Speaker".
extension AgentServer {

    func copyPieces(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        _ = try idArg(a, "clip")
        _ = try idArg(a, "track")
        guard let ranges = try rangesArg(a, "ranges", document) else {
            throw ToolError(
                message: "Missing required argument: ranges (an array of [from, to] pairs, "
                    + "each a time in ticks).")
        }
        guard !ranges.isEmpty else {
            throw ToolError(message: "ranges is empty — name at least one [from, to] pair.")
        }
        let clip = try clipArg(a, "clip", document)
        let track = try trackArg(a, "track", document)
        let op = ReelOp.copyPieces(
            clip: clip.id, track: track.id, ranges: ranges,
            video: try boolArg(a, "video"), audio: try boolArg(a, "audio"))
        return try editResult(document, "Copy Pieces", [op])
    }

    /// The container `set_scope` has open, as `text_behind_subject` reads it:
    /// no `scope` key, on the main thread, committed through
    /// `performGroupedEdit` (which stamps that scope on the ops).
    func switchAngle(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try idArg(a, "clip")
        let angle = try idArg(a, "angle")
        let container =
            effectiveScope(document).flatMap { document.project.scoped($0) } ?? document.project
        let answer: SwitchAngle.Answer
        do {
            answer = try SwitchAngle.plan(clip: clip, angle: angle, in: container)
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        switch answer {
        case .refused(let reason):
            throw ToolError(message: reason)
        case .plan(let plan):
            _ = try performGroupedEdit(document, plan.actionName, plan.ops)
            // Written by hand so the keys keep SW-15's order.
            let step = try JSONSerialization.data(
                withJSONObject: plan.actionName, options: .fragmentsAllowed)
            let project = try JSONSerialization.data(withJSONObject: summary(document))
            let pieces = plan.pieces.map(String.init).joined(separator: ",")
            let text = "{\"ok\":true,\"step\":\(String(decoding: step, as: UTF8.self)),"
                + "\"pieces\":[\(pieces)],\"transitions_removed\":\(plan.transitionsRemoved),"
                + "\"project\":\(String(decoding: project, as: UTF8.self))}"
            return try callResult(content: [["type": "text", "text": text]], isError: false)
        }
    }

    // MARK: - switch_by_speaker (SW2b)

    /// SW-26 (c): the container `set_scope` has open, no `scope` key, on the main thread,
    /// committed through `performGroupedEdit`. Argument errors first, then `read`, Replace's
    /// track, `plan` and `edit`; `apply: false` answers the same without editing.
    func switchBySpeaker(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let settings = try speakerSettings(a)
        let fps = document.editedProject.snapshot.canvas.fps
        let from = try intArg(a, "from").map { ReelTime.snapToFrame(Ticks($0), fps: fps) }
        let to = try intArg(a, "to").map { ReelTime.snapToFrame(Ticks($0), fps: fps) }
        if (from == nil) != (to == nil) {
            throw ToolError(message: "Name both from and to, or neither.")
        }
        if let from, let to, to <= from {
            throw ToolError(message: "to (\(to)) must be after from (\(from)) on the frame grid.")
        }
        let scope = try idScope(document)
        func trackID(_ raw: Any?, _ key: String) throws -> UInt32 {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                let value = Self.whole(number), value >= 0, value <= Int(UInt32.max)
            else { throw ToolError(message: "\(key) must be a track id (an integer).") }
            guard scope.track(UInt32(value)) != nil else {
                throw ToolError(message: "no track with id \(value)")
            }
            return UInt32(value)
        }
        var speakers: [SpeakerSwitch.Speaker]?
        if let raw = a["speakers"], !(raw is NSNull) {
            guard let rows = raw as? [Any], !rows.isEmpty else {
                throw ToolError(
                    message: "speakers must be an array of {mic, angle} objects, at least one.")
            }
            speakers = try rows.map { row in
                guard let item = row as? [String: Any] else {
                    throw ToolError(message: "each of speakers must be an object {mic, angle}.")
                }
                if let stranger = item.keys.sorted().first(where: { $0 != "mic" && $0 != "angle" })
                {
                    throw ToolError(
                        message: "speakers: unknown key \(stranger); each speaker is {mic, angle}.")
                }
                return SpeakerSwitch.Speaker(
                    mic: try trackID(item["mic"], "a speaker's mic"),
                    angle: try trackID(item["angle"], "a speaker's angle"))
            }
        }
        let snapshot = document.editedProject.snapshot
        let selected = document.selection.sorted().compactMap { snapshot.clip($0) }
        let implied = SpeakerSwitch.defaults(selection: selected, in: snapshot)
        var wide: UInt32?
        let wideNamed = a.keys.contains("wide")
        if let raw = a["wide"], !(raw is NSNull) {
            let id = try trackID(raw, "wide")
            guard implied.angles.contains(id) else {
                throw ToolError(message: "wide: track \(id) is not an angle")
            }
            wide = id
        }
        let track = try a["track"].flatMap { $0 is NSNull ? nil : $0 }.map {
            try trackID($0, "track")
        }

        // `wide` absent: SW-20's leftover rule over the speakers used.
        let pairing: SpeakerSwitch.Pairing?
        if let speakers {
            if !wideNamed {
                let used = Set(speakers.compactMap(\.angle))
                let left = implied.angles.filter { !used.contains($0) }
                wide = left.count == 1 ? left.first : nil
            }
            pairing = SpeakerSwitch.Pairing(speakers: speakers, wide: wide)
        } else {
            pairing = wideNamed
                ? SpeakerSwitch.Pairing(speakers: implied.pairing.speakers, wide: wide) : nil
        }
        let range = from.flatMap { f in to.map { (from: f, to: $0) } }
        guard
            let input = SpeakerSwitch.read(
                from: document, clips: nil, pairing: pairing, range: range, settings: settings)
        else {
            throw ToolError(
                message: "The project's audio plan could not be read, so Switch by Speaker "
                    + "cannot run. Try again in a moment.")
        }
        let refused = "Switch by Speaker was refused: "
        if let track,
            let why = SpeakerSwitch.replaceRefusal(
                track, input: input, selection: document.selection, in: snapshot)
        {
            throw ToolError(message: refused + why)
        }
        guard case .planned(let shots, let added) = SpeakerSwitch.plan(input) else {
            if case .refused(let reasons) = SpeakerSwitch.plan(input) {
                throw ToolError(message: refused + reasons.joined(separator: " "))
            }
            throw ToolError(message: refused + "nothing was planned.")
        }
        let mute = try boolArg(a, "mute_cameras") ?? SpeakerSwitch.muteDefault(input)
        let answer: SpeakerSwitch.EditAnswer
        do {
            answer = try SpeakerSwitch.edit(
                shots, input: input, muteCameras: mute, replacing: track,
                selection: document.selection, in: document.editedProject)
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        let edit: SpeakerSwitch.Edit
        switch answer {
        case .refused(let why):
            // (a)'s refusal already says where; (h)'s is the bare sentence.
            throw ToolError(
                message: why.hasPrefix("Switch by Speaker was refused") ? why : refused + why)
        case .edit(let made):
            edit = made
        }

        let apply = try boolArg(a, "apply") ?? true
        if apply {
            try performGroupedEdit(document, SpeakerSwitch.actionName, edit.ops)
            document.selection = edit.selection
        }
        func id(_ value: UInt32?) -> Any { value.map { NSNumber(value: $0) } ?? NSNull() }
        var fields: [String: Any] = [
            "ok": true,
            "applied": apply,
            "track": apply || track != nil ? id(edit.track) : NSNull(),
            "shots": shots.map { ["angle": $0.angle, "start": $0.start, "end": $0.end] },
            "ops": edit.ops.count,
            "added": added,
            "speakers": input.pairing.speakers.map { ["mic": id($0.mic), "angle": id($0.angle)] },
            "wide": id(input.pairing.wide),
            "mute_cameras": mute,
            "project": summary(document),
        ]
        if apply { fields["step"] = SpeakerSwitch.actionName }
        return try jsonResult(fields)
    }

    /// SW-26's numbers and `crosstalk`, each refused outside its range in auto_zoom's form.
    private func speakerSettings(_ a: [String: Any]) throws -> SpeakerSwitch.Settings {
        typealias S = SpeakerSwitch.Settings
        func plain(_ v: Double) -> String {
            v.rounded() == v && abs(v) < 1e15 ? String(Int64(v)) : String(v)
        }
        func number(_ key: String, _ unit: String, _ range: ClosedRange<Double>) throws
            -> Double?
        {
            guard let v = try doubleArg(a, key) else { return nil }
            guard v.isFinite, range.contains(v) else {
                throw ToolError(
                    message: "\(key) is \(plain(v))\(unit); it runs "
                        + "\(plain(range.lowerBound))–\(plain(range.upperBound))\(unit).")
            }
            return v
        }
        var s = S()
        s.minShot = try number("min_shot", " s", S.minShotRange) ?? s.minShot
        s.minTurn = try number("min_turn", " s", S.minTurnRange) ?? s.minTurn
        s.lead = try number("lead", " s", S.leadRange) ?? s.lead
        s.bleedDB = try number("bleed_db", " dB", S.bleedRange) ?? s.bleedDB
        s.dominanceDB = try number("dominance_db", " dB", S.dominanceRange) ?? s.dominanceDB
        s.wideAfter = try number("wide_after", " s", S.wideAfterRange)
        if let crosstalk = try stringArg(a, "crosstalk") {
            guard let value = SpeakerSwitch.Crosstalk(rawValue: crosstalk) else {
                throw ToolError(
                    message: "crosstalk is \"\(crosstalk)\"; it is \"wide\" or \"hold\".")
            }
            s.crosstalk = value
        }
        return s
    }
}
