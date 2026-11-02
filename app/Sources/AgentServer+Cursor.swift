import Foundation

/// A recording's cursor file over MCP (road map "creator-jobs" CU5, spec §11
/// CU-50, CU-53): the op tool `set_media_cursor`, which mirrors the Media
/// tab's Cursor section ▸ Locate… and Remove (`MediaPane+Cursor.swift`), and
/// `get_cursor_events`, a read with no menu: the file's clicks, scrolls,
/// shortcuts, typing stretches and path, in media or clip time.
extension AgentServer {

    // MARK: - set_media_cursor

    /// `set_media_cursor` — Locate… and Remove. A non-null `cursor` is held
    /// to Locate's own check first (CU-50 (b)): the file opens through the
    /// core and its `movie_size` is the movie's (`cursorAttachment`, CU-34),
    /// and the call's `in_picture` is the file's. The path checked is the
    /// path stored, as given (no `~` expansion). Passing both, the op is
    /// sent with the caller's value as given; the core reads it strictly and
    /// refuses by name. An unknown media goes on to the core's own sentence;
    /// `null` is not checked.
    func setMediaCursor(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let media = try idArg(a, "media")
        guard let cursor = a["cursor"] else {
            throw ToolError(
                message: "Missing required argument: cursor ({path, bookmark?, in_picture} or "
                    + "null)")
        }
        if let object = cursor as? [String: Any],
            let path = object["path"] as? String, !path.isEmpty,
            let entry = document.project.snapshot.media(media)
        {
            let file = URL(fileURLWithPath: path)
            switch MediaImporter.cursorAttachment(at: file, to: MediaDescriptor(entry)) {
            case .failure(let problem):
                throw ToolError(message: problem.message)
            case .success(let attachment):
                if let asked = object["in_picture"] as? Bool,
                    asked != attachment.cursor.inPicture
                {
                    throw ToolError(
                        message: "The cursor file \(file.lastPathComponent) was not attached: "
                            + "its in_picture is \(attachment.cursor.inPicture) and the call "
                            + "says \(asked).")
                }
            }
        }
        let name = cursor is NSNull ? "Remove Cursor File" : "Locate Cursor File"
        return try editResult(
            document, name, [.setMediaCursorRaw(media: media, cursor: cursor)],
            ["media": Int(media)])
    }

    // MARK: - get_cursor_events

    /// What the first main-thread hop resolves.
    struct CursorEventsCall {
        let document: ProjectDocument
        let media: MediaSnapshot
        let clip: ClipSnapshot?
        let times: AnalysisClipTimes?
        let file: URL
        let request: CursorEventsAnswer.Request
    }

    /// `get_cursor_events` — refused in CU-53 (g)'s order. **Runs on the
    /// SERVER thread** (`creatorOffMainTools`): one main hop resolves, the
    /// file is opened as a fresh `ReelCursor` here, and a last main hop
    /// computes Q, which reads `clip_state`, and the summary.
    func getCursorEvents(_ a: [String: Any]) throws -> String {
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "get_cursor_events must run on the server thread — its name is "
                    + "missing from AgentServer.creatorOffMainTools.")
        }
        let call = try onMain { try self.resolveCursorEventsCall(a) }
        let track: ReelCursor
        let read: CursorEventsAnswer.Read
        do {
            track = try ReelCursor(data: try Data(contentsOf: call.file))
            read = try CursorEventsAnswer.read(track, call.request, times: call.times)
        } catch {
            let reason = (error as? ReelCoreError)?.message ?? error.localizedDescription
            throw ToolError(
                message: "The cursor file \(call.file.lastPathComponent) could not be read: "
                    + reason)
        }
        return try onMain {
            var result = CursorEventsAnswer.answer(
                read, call.request, crop: { t in self.cropAt(call, clipTime: t) })
            result["media"] = Int(call.media.id)
            if let clip = call.clip { result["clip"] = Int(clip.id) }
            result["size"] = [call.media.width, call.media.height]
            result["cursor_file"] = call.file.path
            result["in_picture"] = call.media.cursor?.inPicture ?? false
            result["project"] = self.summary(call.document)
            return try self.jsonResult(result)
        }
    }

    /// The clip's crop at clip tick `t` (CU-53 (c)): its base crop when it
    /// has no actions, else `clip_state`'s at `clip.start + t` on the edited
    /// project. Main thread.
    private func cropAt(_ call: CursorEventsCall, clipTime t: Ticks) -> CropInsets {
        guard let clip = call.clip else { return CropInsets() }
        guard !clip.actions.isEmpty else { return clip.videoProps.crop }
        let state = call.document.editedProject.clipState(clip.id, at: clip.start + t)
        let crop = (state?["video"] as? [String: Any])?["crop"] as? [String: Any]
        func side(_ key: String) -> Double { (crop?[key] as? NSNumber)?.doubleValue ?? 0 }
        return CropInsets(l: side("l"), t: side("t"), r: side("r"), b: side("b"))
    }

    private func resolveCursorEventsCall(_ a: [String: Any]) throws -> CursorEventsCall {
        func given(_ key: String) -> Bool { a[key] != nil && !(a[key] is NSNull) }
        guard given("media") != given("clip") else {
            throw ToolError(
                message: "Name exactly one of media and clip: the recording whose cursor file "
                    + "to read in its own times, or the clip to read it in clip time.")
        }
        let kinds = try CursorEventsAnswer.kinds(try stringsArg(a, "kinds"))
        let smoothingArg = try doubleArg(a, "smoothing")
        if let s = smoothingArg, !(0...1).contains(s) {
            throw ToolError(message: "smoothing must be 0–1, not \(s).")
        }
        let document = try target(a)
        let media: MediaSnapshot
        var clip: ClipSnapshot?
        var times: AnalysisClipTimes?
        if given("clip") {
            let snapshot = try clipArg(a, "clip", document)
            guard case .media(let id, _, _) = snapshot.source,
                let entry = document.editedProject.snapshot.media(id)
            else {
                throw ToolError(
                    message: "Clip \(snapshot.id) is not a media clip (it shows "
                        + "\(snapshot.source.kindName)), so it has no cursor file.")
            }
            guard !snapshot.source.isReversed else {
                throw ToolError(
                    message: "Clip \(snapshot.id) plays reversed; get_cursor_events reads only "
                        + "clips that play forward. Ask with media \(id) for the file's own "
                        + "times.")
            }
            media = entry
            clip = snapshot
            times = AnalysisClipTimes(
                clip: snapshot, media: entry,
                map: document.editedProject.sourceMap(snapshot.id))
        } else {
            media = try mediaArg(a, "media", document)
        }
        guard media.cursor != nil, let file = cursorURL(for: media) else {
            throw ToolError(
                message: "Media \(media.id) has no cursor file. A screen recording made by "
                    + "Frame Job has one; set_media_cursor attaches one.")
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw ToolError(
                message: "Media \(media.id)'s cursor file \(file.lastPathComponent) is missing. "
                    + "The Media tab's Cursor section ▸ Locate…, or set_media_cursor, points "
                    + "it at the file.")
        }
        let duration = clip?.duration ?? media.duration
        let from = Ticks(try intArg(a, "from") ?? 0)
        let to = Ticks(try intArg(a, "to") ?? Int(duration))
        guard to > from else {
            throw ToolError(
                message: "to (\(to)) must be after from (\(from)), in "
                    + (clip == nil ? "the media's source ticks." : "the clip's own ticks."))
        }
        let smoothing = smoothingArg ?? clip?.video?.cursor?.smoothing ?? 0
        let request = CursorEventsAnswer.Request(
            kinds: kinds, from: from, to: to, smoothing: smoothing,
            size: (Double(media.width), Double(media.height)))
        return CursorEventsCall(
            document: document, media: media, clip: clip, times: times, file: file,
            request: request)
    }
}
