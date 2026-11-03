import Foundation

/// Auto Zoom's Swift half (road map "creator-jobs" CU7, spec §11 CU-70…CU-76): the sheet's
/// settings and their remembered keys, the selected clips' cursor files found and read, and
/// `plan_zooms` asked of the core through `ReelCursor` (this file names no `rc_*`, CJ-8 (l))
/// with its answer read into ops. Both doors — Clip ▸ Auto Zoom… (`AutoZoomSheetController`)
/// and `auto_zoom` (`AgentServer+AutoZoom.swift`) — plan here.

/// What the sheet sets (CU-70's defaults). `typing` is never remembered: it is on whenever the
/// files hold typing (CU-76).
struct AutoZoomSettings: Equatable {
    var zoom = 2.0, lead = 0.6, stay = 2.5
    var follow = true, typing = true, replace = false

    static let zoomRange: ClosedRange<Double> = 1.25...4
    static let leadRange: ClosedRange<Double> = 0.2...2.0
    static let stayRange: ClosedRange<Double> = 0.5...10.0

    static let zoomKey = "FrameJobAutoZoomZoom"
    static let leadKey = "FrameJobAutoZoomLead"
    static let stayKey = "FrameJobAutoZoomStay"
    static let followKey = "FrameJobAutoZoomFollow"
    static let replaceKey = "FrameJobAutoZoomReplace"

    /// The remembered values, each clamped into its range; the default for a key not stored.
    /// Read through `double(forKey:)` and `bool(forKey:)`, so a launch argument's string
    /// (`-FrameJobAutoZoomLead 1`) reads as its number.
    static func remembered(_ d: UserDefaults) -> AutoZoomSettings {
        var s = AutoZoomSettings()
        func number(_ key: String, _ range: ClosedRange<Double>, _ value: inout Double) {
            guard d.object(forKey: key) != nil else { return }
            let v = d.double(forKey: key)
            if v.isFinite, v > 0 { value = min(max(v, range.lowerBound), range.upperBound) }
        }
        number(zoomKey, zoomRange, &s.zoom)
        number(leadKey, leadRange, &s.lead)
        number(stayKey, stayRange, &s.stay)
        if d.object(forKey: followKey) != nil { s.follow = d.bool(forKey: followKey) }
        if d.object(forKey: replaceKey) != nil { s.replace = d.bool(forKey: replaceKey) }
        return s
    }

    /// Writes only the keys whose value differs from `opened`'s, so a sheet whose controls
    /// were not changed writes nothing (mcp.py's DEFAULTS MOVED guard); `typing` never.
    func remember(changedFrom opened: AutoZoomSettings, in d: UserDefaults) {
        if zoom != opened.zoom { d.set(zoom, forKey: Self.zoomKey) }
        if lead != opened.lead { d.set(lead, forKey: Self.leadKey) }
        if stay != opened.stay { d.set(stay, forKey: Self.stayKey) }
        if follow != opened.follow { d.set(follow, forKey: Self.followKey) }
        if replace != opened.replace { d.set(replace, forKey: Self.replaceKey) }
    }
}

/// `plan_zooms`' answer: the ops in the core's order and its counts.
struct AutoZoomPlan {
    let ops: [ReelOp]
    let visits, added, replaced, dropped, closedAtCut, basesSet: Int
    let actions: [[String: Any]]
}

enum AutoZoom {
    /// The undo step's name, both doors.
    static let actionName = "Auto Zoom"

    /// A sentence either door shows as it is.
    struct Refusal: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The menu's test (CU-76): at least one clip, each a media clip whose media has a cursor
    /// file.
    static func canOffer(_ selection: [ClipSnapshot], in snapshot: ProjectSnapshot) -> Bool {
        !selection.isEmpty
            && selection.allSatisfy { clip in
                guard case .media(let id, _, _) = clip.source else { return false }
                return snapshot.media(id)?.cursor != nil
            }
    }

    /// Each clip's media's cursor file, by media id. Throws a clip that is not a media clip,
    /// a media with no cursor file, and a file that is missing, each in its sentence.
    static func cursorFiles(_ clips: [ClipSnapshot], in snapshot: ProjectSnapshot) throws
        -> [UInt32: URL]
    {
        var files: [UInt32: URL] = [:]
        for clip in clips {
            guard case .media(let id, _, _) = clip.source, let media = snapshot.media(id) else {
                throw Refusal(
                    message: "Clip \(clip.id) is not a media clip (it shows "
                        + "\(clip.source.kindName)), so it has no cursor file.")
            }
            guard media.cursor != nil, let file = cursorURL(for: media) else {
                throw Refusal(
                    message: "Media \(id) has no cursor file. A screen recording made by Frame "
                        + "Job has one; set_media_cursor attaches one.")
            }
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw Refusal(
                    message: "Media \(id)'s cursor file \(file.lastPathComponent) is missing. "
                        + "The Media tab's Cursor section ▸ Locate…, or set_media_cursor, "
                        + "points it at the file.")
            }
            files[id] = file
        }
        return files
    }

    /// Opens each file through the core. Off the main thread: a file can be large.
    static func readTracks(_ files: [UInt32: URL]) throws -> [UInt32: ReelCursor] {
        var tracks: [UInt32: ReelCursor] = [:]
        for (media, file) in files {
            do {
                tracks[media] = try ReelCursor(data: try Data(contentsOf: file))
            } catch {
                let reason = (error as? ReelCoreError)?.message ?? error.localizedDescription
                throw Refusal(
                    message: "The cursor file \(file.lastPathComponent) could not be read: "
                        + reason)
            }
        }
        return tracks
    }

    /// Whether any file holds a typing stretch (CU-25's `typing` events).
    static func hasTyping(_ tracks: [UInt32: ReelCursor]) -> Bool {
        let request = #"{"events":{"from":0,"to":4611686018427387903,"kinds":["typing"]}}"#
        return tracks.values.contains { track in
            guard let text = try? track.query(request),
                let object = try? JSONSerialization.jsonObject(with: Data(text.utf8))
                    as? [String: Any]
            else { return false }
            return !((object["typing"] as? [Any]) ?? []).isEmpty
        }
    }

    /// `plan_zooms`' request JSON for `clips` (container ticks `from`/`to`, nil for none).
    static func request(
        _ clips: [UInt32], settings: AutoZoomSettings, from: Ticks?, to: Ticks?
    ) -> String {
        var args: [String: Any] = [
            "clips": clips.map { Int($0) }, "zoom": settings.zoom, "lead": settings.lead,
            "stay": settings.stay, "follow": settings.follow, "typing": settings.typing,
            "replace": settings.replace,
        ]
        if let from { args["from"] = from }
        if let to { args["to"] = to }
        let data = (try? JSONSerialization.data(withJSONObject: ["plan_zooms": args])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Asks the core for the plan over `clips` of `project` (the edited one, so inside a nest
    /// the nest's), one track per clip; throws the core's sentence as a `Refusal`.
    static func plan(
        _ clips: [ClipSnapshot], tracks: [UInt32: ReelCursor], project: ReelProject,
        settings: AutoZoomSettings, from: Ticks?, to: Ticks?
    ) throws -> AutoZoomPlan {
        var ordered: [ReelCursor] = []
        for clip in clips {
            guard case .media(let id, _, _) = clip.source, let track = tracks[id] else {
                throw Refusal(message: "Clip \(clip.id)'s cursor file was not read.")
            }
            ordered.append(track)
        }
        let text: String
        do {
            text = try ReelCursor.query(
                request(clips.map(\.id), settings: settings, from: from, to: to),
                tracks: ordered, project: project)
        } catch {
            let reason = (error as? ReelCoreError)?.message ?? error.localizedDescription
            throw Refusal(message: sentence(reason))
        }
        guard let answer = try? JSONSerialization.jsonObject(with: Data(text.utf8))
            as? [String: Any]
        else { throw Refusal(message: "Auto Zoom's plan could not be read.") }
        let ops = try ((answer["ops"] as? [[String: Any]]) ?? []).map(op)
        func count(_ key: String) -> Int { (answer[key] as? NSNumber)?.intValue ?? 0 }
        return AutoZoomPlan(
            ops: ops, visits: count("visits"), added: count("added"),
            replaced: count("replaced"), dropped: count("dropped"),
            closedAtCut: count("closed_at_cut"), basesSet: count("bases_set"),
            actions: (answer["actions"] as? [[String: Any]]) ?? [])
    }

    /// The core's lowercase sentence as one a person reads: capitalised, with a full stop.
    static func sentence(_ core: String) -> String {
        guard let first = core.first else { return core }
        let text = first.uppercased() + core.dropFirst()
        return text.hasSuffix(".") ? text : text + "."
    }

    /// One op of the answer, through `ReelOps.swift`'s factories.
    private static func op(_ o: [String: Any]) throws -> ReelOp {
        func id(_ key: String) -> UInt32 { (o[key] as? NSNumber)?.uint32Value ?? 0 }
        func ticks(_ key: String) -> Ticks { (o[key] as? NSNumber)?.int64Value ?? 0 }
        switch o["op"] as? String {
        case "remove_action":
            return .removeAction(clip: id("clip"), action: id("action"))
        case "set_video":
            let clips = ((o["clips"] as? [NSNumber]) ?? []).map(\.uint32Value)
            return .setVideoRaw(clips: clips, patch: o["patch"] ?? [String: Any]())
        case "add_zoom_action":
            return .addZoomActionRaw(
                clip: id("clip"), at: ticks("at"), duration: ticks("duration"),
                region: o["region"] ?? NSNull(),
                fit: (o["fit"] as? String).flatMap(ZoomFit.init(rawValue:)),
                curve: (o["curve"] as? String).flatMap(Curve.init(rawValue:)))
        default:
            throw Refusal(message: "Auto Zoom's plan named an op it does not make.")
        }
    }
}
