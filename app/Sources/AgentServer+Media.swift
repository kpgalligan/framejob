import AppKit

/// The agent's media tools: the three `media` rows of spec §6's op table plus
/// `import_media`, the one an agent actually wants — `add_media` takes a
/// descriptor somebody has to have probed, and probing files is the host's job
/// (spec §7.7).
extension AgentServer {

    // MARK: - Importing

    /// `import_media` — File ▸ Add Media… and every Finder drop
    /// (`ProjectDocument.importMedia`): probe the file, then `add_media`.
    ///
    /// **Runs on the server thread** (`AgentServer.offMainTools`).
    /// `MediaImporter.probe`'s completion is delivered on the MAIN thread, so
    /// a main-thread wait for it would deadlock; waiting here leaves main free
    /// to deliver it, exactly as `ProjectDocument.readMediaFile` waits on
    /// NSDocument's background read queue.
    ///
    /// **The new media id is the project's `next_id` from BEFORE the op** —
    /// the documented contract (`ReelOp.addMedia`), because there is one FFI
    /// entry point for every op (spec §11) and it returns a project, not a
    /// value. The id is read off the snapshot first and cross-checked against
    /// what the edit actually added.
    func importMedia(_ a: [String: Any]) throws -> String {
        let path = try requiredString(a, "path")
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError(message: "No file at \(url.path)")
        }
        let document = try onMain { try self.target(a) }
        let descriptor = try probe(url)
        return try onMain {
            let expected = document.project.snapshot.nextId
            let before = try self.performGroupedEdit(
                document, "Add Media", [.addMedia(descriptor: descriptor)])
            let added = ProjectSnapshot.addedMedia(from: before, to: document.project.snapshot)
            document.generateCaches()
            var result: [String: Any] = [
                "ok": true,
                "media": Int(added.first ?? expected),
                "path": url.path,
                "kind": descriptor.kind.rawValue,
                "duration": descriptor.duration,
                "width": descriptor.width,
                "height": descriptor.height,
                "fps": [descriptor.fps.num, descriptor.fps.den],
                "has_video": descriptor.hasVideo,
                "has_audio": descriptor.hasAudio,
                "has_alpha": descriptor.hasAlpha,
            ]
            result["note"] =
                "The file is in the project's media list but not on the timeline yet — place it "
                + "with add_clip {track, media, at}."
            result["project"] = self.summary(document)
            return try self.jsonResult(result)
        }
    }

    /// Probes one file and waits for the answer. MUST run off the main thread
    /// — see `importMedia` — and gives up after 30 seconds, the same ceiling
    /// `ProjectDocument.readMediaFile` puts on an unreadable file.
    private func probe(_ url: URL) throws -> MediaDescriptor {
        guard !Thread.isMainThread else {
            throw ToolError(message: "Probing cannot run on the main thread.")
        }
        let semaphore = DispatchSemaphore(value: 0)
        let box = AgentBox<Result<MediaDescriptor, any Error>>()
        MediaImporter.probe(url: url) { result in
            box.value = result
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 30) == .success else {
            throw ToolError(message: "Timed out reading \(url.lastPathComponent).")
        }
        guard let outcome = box.value else {
            throw ToolError(message: "Could not read \(url.lastPathComponent).")
        }
        do {
            return try outcome.get()
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
    }

    // MARK: - The raw op

    /// `add_media` — the op behind `import_media`, exposed for parity with
    /// spec §6. It takes the descriptor a probe produced (the `media[]`
    /// element of §5.2 minus its id), so unless you are replaying a project's
    /// own JSON, call `import_media` and let the host probe.
    func addMedia(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        guard let object = a["descriptor"] as? [String: Any] else {
            throw ToolError(
                message: "descriptor must be a JSON object — the media[] element of the project "
                    + "JSON minus its id. import_media probes a file and builds it for you.")
        }
        let descriptor = try mediaDescriptor(object)
        let expected = document.project.snapshot.nextId
        let before = try performGroupedEdit(
            document, "Add Media", [.addMedia(descriptor: descriptor)])
        let added = ProjectSnapshot.addedMedia(from: before, to: document.project.snapshot)
        document.generateCaches()
        return try jsonResult(
            [
                "ok": true, "media": Int(added.first ?? expected), "path": descriptor.path,
                "project": summary(document),
            ])
    }

    /// A `media[]` element minus its id, under the model's own key names.
    /// Everything but `path` has a default, so a descriptor for a still is
    /// `{"path": …, "kind": "image", "width": …, "height": …}`.
    private func mediaDescriptor(_ object: [String: Any]) throws -> MediaDescriptor {
        let allowed: Set<String> = [
            "path", "bookmark", "kind", "duration", "width", "height", "fps", "has_video",
            "has_audio", "has_alpha",
        ]
        let unknown = object.keys.filter { !allowed.contains($0) }.sorted()
        if let first = unknown.first {
            throw ToolError(
                message: "Unknown descriptor key \"\(first)\" — allowed keys are "
                    + allowed.sorted().joined(separator: ", ") + ".")
        }
        let path = try requiredString(object, "path")
        var kind = MediaKind.video
        if let name = stringArg(object, "kind") {
            guard let parsed = MediaKind(rawValue: name) else {
                throw ToolError(
                    message: "kind must be one of "
                        + MediaKind.allCases.map { $0.rawValue }.joined(separator: ", ")
                        + " (got \"\(name)\").")
            }
            kind = parsed
        }
        var fps = Fps.thirty
        if let array = object["fps"] as? [Any], array.count == 2,
            let num = (array[0] as? NSNumber)?.intValue,
            let den = (array[1] as? NSNumber)?.intValue, num > 0, den > 0 {
            fps = Fps(num: num, den: den)
        } else if object["fps"] != nil, !(object["fps"] is NSNull) {
            throw ToolError(
                message: "fps must be [numerator, denominator], e.g. [30000, 1001].")
        }
        return MediaDescriptor(
            path: (path as NSString).expandingTildeInPath,
            bookmark: stringArg(object, "bookmark"),
            kind: kind,
            duration: Ticks(intArg(object, "duration") ?? 0),
            width: intArg(object, "width") ?? 0,
            height: intArg(object, "height") ?? 0,
            fps: fps,
            hasVideo: boolArg(object, "has_video") ?? (kind != .audio),
            hasAudio: boolArg(object, "has_audio") ?? (kind == .audio),
            hasAlpha: boolArg(object, "has_alpha") ?? false)
    }

    // MARK: - Relinking and removing

    /// `relink_media` — Relink… (`RelinkSheetController`, and the Media tab's
    /// row menu). A bookmark is made for the new file here, so the link
    /// survives a later move exactly as the sheet's does.
    func relinkMedia(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let media = try mediaArg(a, "media", document)
        let path = try requiredString(a, "path")
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError(message: "No file at \(url.path)")
        }
        let bookmark = stringArg(a, "bookmark") ?? bookmarkString(for: url)
        let result = try editResult(
            document, "Relink Media",
            [.relinkMedia(media: media.id, path: url.path, bookmark: bookmark)],
            ["media": Int(media.id), "path": url.path])
        document.generateCaches()
        return result
    }

    /// `remove_media` — the Media tab's row menu (`MediaPane.remove`). Media
    /// still in use refuses without `with_clips`, which is the alert's second
    /// button.
    func removeMedia(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let media = try mediaArg(a, "media", document)
        let withClips = boolArg(a, "with_clips")
        let users = document.project.snapshot.clips.filter { $0.source.mediaID == media.id }.count
        if users > 0, withClips != true {
            throw ToolError(
                message: "\(media.name) is used by \(users) clip" + (users == 1 ? "" : "s")
                    + ". Pass with_clips: true to remove them too.")
        }
        return try editResult(
            document, "Remove Media", [.removeMedia(media: media.id, withClips: withClips)],
            ["media": Int(media.id)])
    }
}

extension ProjectSnapshot {
    /// The media ids one edit added. `AgentServer.created(from:to:)` reports
    /// the same thing for every kind at once; `add_media` needs just this one,
    /// and needs it before it can build its result.
    static func addedMedia(from before: ProjectSnapshot, to after: ProjectSnapshot) -> [UInt32] {
        let existing = Set(before.media.map { $0.id })
        return after.media.map { $0.id }.filter { !existing.contains($0) }
    }
}
