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
                // The DESCRIPTOR's path, not the argument's: an ffmpeg-assisted
                // import rewraps the file and the model stores the conversion,
                // so echoing what was asked for would answer `.mkv` about an
                // entry that is really a `.mov`. The rule generalises — the
                // answer must describe what landed in the project.
                "path": descriptor.path,
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

    /// The longest conversion plus 300 s for the funnel's other bounds: two
    /// 30 s header probes (`MediaImporter.waitForProbe`), ffprobe's and the
    /// encoder query's 20 s each with `run`'s 20 s grace, and ffmpeg's own.
    private static let probeCeiling: TimeInterval = FFmpegRewrap.longestConversion + 300

    /// Probes one file and waits for the answer. MUST run off the main thread
    /// — see `importMedia` — and gives up only after `probeCeiling`: a file
    /// AVFoundation cannot read may be converted by ffmpeg first
    /// (`FFmpegRewrap.assist`), which legitimately takes as long as
    /// `FFmpegRewrap.longestConversion`, so a shorter wait would answer a
    /// timeout while the conversion is still running.
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
        guard semaphore.wait(timeout: .now() + Self.probeCeiling) == .success else {
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

    // MARK: - Captions

    /// `import_captions` — File ▸ Import Captions… (`CaptionImporter`, which
    /// also carries the reasoning for why a caption is a text clip).
    ///
    /// Runs on the main thread like every other op tool: parsing an SRT is
    /// reading a text file, not probing a movie, so there is nothing to wait
    /// for and nothing to keep off main.
    ///
    /// The result reports what was SKIPPED as well as what landed — a
    /// caption file with three malformed entries would otherwise import
    /// silently short, and a model has no other way to see it.
    func importCaptions(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let path = try requiredString(a, "path")
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError(message: "No file at \(url.path)")
        }
        var track: UInt32?
        if a["track"] != nil, !(a["track"] is NSNull) {
            track = try trackArg(a, "track", document).id
        }
        let plan: CaptionImporter.Plan
        do {
            // The EDITED project, like its three siblings (the File-menu
            // importer, `Transcriber` and the `transcribe` tool): the ops
            // this plan produces are addressed to whatever nest is open, so
            // reading the document here would measure a placement against
            // the timeline and land the clips inside the nest.
            plan = try CaptionImporter.plan(for: url, in: document.editedProject, track: track)
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        var fields: [String: Any] = ["captions": plan.clips, "cues": plan.cues]
        if let name = plan.trackName { fields["track_name"] = name }
        if plan.trimmed > 0 { fields["trimmed"] = plan.trimmed }
        if !plan.problems.isEmpty {
            fields["skipped"] = plan.problems.map { $0.description }
        }
        return try editResult(document, "Import Captions", plan.ops, fields)
    }

    // MARK: - Consolidating

    /// `consolidate_media` — File ▸ Consolidate Media…
    /// (`EditorViewController+Consolidate.swift`; `MediaConsolidator` owns
    /// the plan, the copying and the four traps).
    ///
    /// The copy runs on the main thread, where every non-`offMainTools`
    /// handler runs: it is `FileManager` work with no waiting in it, so the
    /// only cost is that the app's own UI is unresponsive while a large
    /// library copies — the connection is served on the server thread and
    /// stays live throughout. The app's sheet does the same work on a
    /// background queue because there is a person watching that one.
    func consolidateMedia(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let plan: MediaConsolidator.Plan
        do {
            plan = try MediaConsolidator.plan(for: document)
        } catch let error as MediaConsolidator.ConsolidateError {
            guard case .untitled = error else {
                throw ToolError(message: error.localizedDescription)
            }
            throw ToolError(
                message: error.localizedDescription + " Call save_project with a path first.")
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        // Already self-contained is not an error — it is the state the
        // caller asked for, and `editResult` would report the empty op list
        // as a refusal.
        guard !plan.isEmpty else {
            return try jsonResult([
                "ok": true, "copied": 0, "directory": plan.directory.path,
                "missing": plan.missing,
                "note": "Every file this project can find is already inside the package.",
                "project": summary(document),
            ])
        }
        let outcome = MediaConsolidator.run(plan)
        // Creating `media/` inside the package moves the package's own
        // modification date, which NSDocument reads as another application
        // having changed the file and refuses every later save over. Told
        // unconditionally, since a failed run may still have made it.
        document.packageContentsDidChangeOnDisk()
        guard !outcome.ops.isEmpty else {
            throw ToolError(message: outcome.summary)
        }
        var fields: [String: Any] = [
            "copied": outcome.copied, "bytes": Int(outcome.bytes),
            "directory": plan.directory.path, "summary": outcome.summary,
        ]
        if !outcome.failures.isEmpty { fields["failures"] = outcome.failures }
        if !outcome.missing.isEmpty { fields["missing"] = outcome.missing }
        let result = try editResult(document, "Consolidate Media", outcome.ops, fields)
        document.generateCaches()
        return result
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
        if let name = try stringArg(object, "kind") {
            guard let parsed = MediaKind(rawValue: name) else {
                throw ToolError(
                    message: "kind must be one of "
                        + MediaKind.allCases.map { $0.rawValue }.joined(separator: ", ")
                        + " (got \"\(name)\").")
            }
            kind = parsed
        }
        var fps = Fps.thirty
        if let array = object["fps"] as? [Any] {
            fps = try fpsPair(array, "descriptor.fps")
        } else if object["fps"] != nil, !(object["fps"] is NSNull) {
            throw ToolError(
                message: "descriptor.fps must be [numerator, denominator], e.g. [30000, 1001].")
        }
        return MediaDescriptor(
            path: (path as NSString).expandingTildeInPath,
            bookmark: try stringArg(object, "bookmark"),
            kind: kind,
            duration: Ticks(try intArg(object, "duration") ?? 0),
            width: try intArg(object, "width") ?? 0,
            height: try intArg(object, "height") ?? 0,
            fps: fps,
            hasVideo: try boolArg(object, "has_video") ?? (kind != .audio),
            hasAudio: try boolArg(object, "has_audio") ?? (kind == .audio),
            hasAlpha: try boolArg(object, "has_alpha") ?? false)
    }

    // MARK: - Relinking and removing

    /// `relink_media` — Relink… (`RelinkSheetController`, and the Media tab's
    /// row menu, both through `ProjectDocument.relinkMedia`). The new file
    /// is probed as `import_media` probes it and the descriptor fills the
    /// op's `probe` (spec §11, #63), so the entry takes the file's duration,
    /// size, rate and flags, a file of another kind is refused in the core's
    /// sentence, and a clip past a shorter file's end is held to it.
    ///
    /// **Runs on the server thread** (`AgentServer.offMainTools`), for
    /// `importMedia`'s reason: the probe's completion arrives on main. The
    /// path stored is the DESCRIPTOR's (an ffmpeg rewrap stores the `.mov`),
    /// and so is the bookmark unless the caller gave one for that same file:
    /// a caller's bookmark of the original beside a rewrapped path would
    /// make `mediaURL`, which resolves the bookmark first, open the file the
    /// record does not name.
    func relinkMedia(_ a: [String: Any]) throws -> String {
        let (document, media) = try onMain {
            let document = try self.target(a)
            return (document, try self.mediaArg(a, "media", document))
        }
        let path = try requiredString(a, "path")
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError(message: "No file at \(url.path)")
        }
        let given = try stringArg(a, "bookmark")
        let descriptor = try probe(url)
        let bookmark = descriptor.path == url.path ? given ?? descriptor.bookmark
            : descriptor.bookmark
        return try onMain {
            let result = try self.editResult(
                document, "Relink Media",
                [
                    .relinkMedia(
                        media: media.id, path: descriptor.path, bookmark: bookmark,
                        probe: descriptor)
                ],
                [
                    "media": Int(media.id), "path": descriptor.path,
                    "kind": descriptor.kind.rawValue, "duration": descriptor.duration,
                    "width": descriptor.width, "height": descriptor.height,
                    "fps": [descriptor.fps.num, descriptor.fps.den],
                    "has_video": descriptor.hasVideo, "has_audio": descriptor.hasAudio,
                    "has_alpha": descriptor.hasAlpha,
                ])
            document.generateCaches()
            return result
        }
    }

    /// `remove_media` — the Media tab's row menu (`MediaPane.remove`). Media
    /// still in use refuses without `with_clips`, which is the alert's second
    /// button.
    ///
    /// **The refusal is the core's** since deepening D2·4: "media 3 is still
    /// used by clips 7 and 9; pass with_clips: true to remove the media and
    /// its clips". This handler used to count the users itself and answer
    /// first, naming the FILE where the core names the clip ids — the better
    /// sentence for a person and the worse one for a caller that has to name
    /// a clip — and the count it took was the one thing about it worth
    /// keeping: `clipsUsing` walks the NESTS as well as the timeline, which
    /// is the set the core refuses against (`every_clip()`) and the set
    /// `with_clips: true` deletes. Phase 8c fixed that count here; the core
    /// always had it right, and the app asks the question at the Media tab's
    /// alert only (`MediaPaneCommands.swift`, still through
    /// `MediaUsage.swift`'s one spelling).
    func removeMedia(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let media = try mediaArg(a, "media", document)
        let withClips = try boolArg(a, "with_clips")
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
