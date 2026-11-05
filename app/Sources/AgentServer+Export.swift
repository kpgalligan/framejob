import AppKit

extension AgentServer {

    // MARK: - Export

    /// `export` — ⌘E (`EditorViewController.exportProjectCommand` and
    /// `ExportSheetController`). The preset names the ENCODING — a container
    /// and a codec, nothing about size — and the size is the sheet's separate
    /// choice, in the Size popup's own vocabulary and defaulting as the popup
    /// does to its first row: the document's size, or an image format's cap.
    /// The CORE resolves both into concrete settings (`rc_export_settings`)
    /// that go to the same `Exporter.export` the sheet uses: there is exactly
    /// one writer, so an agent export and a menu export cannot disagree.
    ///
    /// Answers AT ONCE (spec §11 #326): every refusal is made here, before
    /// anything is queued — the arguments, the core's settings, the folder
    /// and the graphics gate — and the export is then a job in the Export
    /// Queue, exactly as the sheet's Add to Queue makes one, answered as
    /// `{export_id, path, status}`. `export_status` follows the job and
    /// `cancel_export` stops it (`AgentServer+ExportStatus.swift`); a failure
    /// while writing comes back from there. The queue window is not shown.
    ///
    /// One argument is NOT a setting and never reaches the core:
    /// `burn_in_timecode` is a recipe option (`RecipeOptions`), read below
    /// beside the overrides it deliberately does not join.
    ///
    /// The finished job's answer carries the sound the file actually holds —
    /// its integrated loudness and true peak, measured on the way through —
    /// for every format that has any, whether `loudness_lufs` was asked for
    /// or not, and, with `stems` (the sheet's Stems popup, spec §11 AU-108),
    /// each stem file beside the mix.
    func exportProject(_ a: [String: Any]) throws -> String {
        // The clock `export_status`'s `elapsed` runs on, read before any check.
        let started = ProcessInfo.processInfo.systemUptime
        let presetID = try requiredString(a, "preset")
        let path = try requiredString(a, "path")
        let wholeProject = (try stringArg(a, "range") ?? "project").lowercased()
        guard ["project", "in_out"].contains(wholeProject) else {
            throw ToolError(
                message: "range must be \"project\" (the whole timeline) or \"in_out\" "
                    + "(the in/out range set_range set), not \"\(wholeProject)\".")
        }
        // The export sheet's burn-in checkbox — and read HERE rather than
        // into `overrides` below, which is the whole of the decision. A
        // recipe option changes the PICTURE, so it travels with the
        // description of the picture: `export_overrides.rs` ignores a key it
        // does not know, on purpose, so a `burn_in_timecode` posted through
        // `rc_export_settings` would vanish without a word and this tool
        // would report success on an un-burnt file. It goes to `Exporter`
        // beside the settings instead (`RecipeOptions`, `Exporter.export`),
        // which is also what reaches GIF and APNG — those never go through
        // `ExportWriter` at all.
        let options = RecipeOptions(burnInTimecode: try boolArg(a, "burn_in_timecode") ?? false)
        let prepared = try onMain {
            () throws -> (ProjectDocument, ReelProject, [UInt32: URL], ExportSettings, GraphicSet?)
            in
            let document = try self.target(a)
            guard document.project.duration > 0 else {
                throw ToolError(message: "There is nothing on the timeline to export.")
            }
            let settings = try self.exportSettings(
                a, on: document, preset: presetID, range: wholeProject)
            return (
                document, document.project, document.mediaURLs(), settings,
                GraphicRegistry.shared.snapshot(for: document.recipeKey)
            )
        }
        let (document, project, urls, settings, graphics) = prepared
        let url = try Self.requireFolder(
            of: Self.destinationURL(path, extension: Exporter.fileExtension(for: settings)))

        // The graphics gate, here rather than only in the writer: a module
        // that does not compile refuses the CALL, so nothing is queued that
        // could only fail (`Exporter.graphicsRefusal`, the writer's own gate).
        if let refusal = Exporter.graphicsRefusal(
            project: project, settings: settings, graphics: graphics)
        {
            throw ToolError(message: refusal.localizedDescription)
        }
        let (id, status) = onMain { () -> (UInt64, String) in
            // The editor pauses before its own export so the player is not
            // decoding the same media; the agent's does the same.
            self.editor(document)?.playback.pause()
            let id = ExportQueueController.shared.enqueue(
                project: project, urls: urls, settings: settings, to: url, options: options,
                graphics: graphics)
            AgentExports.shared.track(
                id, settings: settings, burnInTimecode: options.burnInTimecode, started: started)
            let word = ExportQueueController.shared.job(id).map {
                Self.exportStatusWord($0.state)
            }
            return (id, word ?? "queued")
        }
        return try jsonResult(["export_id": id, "path": url.path, "status": status])
    }

    /// The core's settings for `export`'s arguments, every override read as
    /// the sheet's popups spell it, and every refusal the tool's own. Main
    /// only. `range` is the call's `range`, already lower-cased.
    func exportSettings(
        _ a: [String: Any], on document: ProjectDocument, preset: String, range: String
    ) throws -> ExportSettings {
        // The Range popup of the export sheet, in the sheet's own terms:
        // "Whole project" is no override at all, "In/out range" is the
        // core's ONE nested `range` object (`export.rs`). The core snaps
        // it to the frame grid and clamps it to the project.
        var overrides: [String: Any] = [:]
        if range == "in_out" {
            guard let inOut = document.inOutRange, inOut.end > inOut.start else {
                throw ToolError(
                    message: "This project has no in/out range — set one with set_range "
                        + "{start, end}, or export with range \"project\".")
            }
            overrides["range"] = ["start": inOut.start, "duration": inOut.end - inOut.start]
        }
        // The sheet's Quality popup, in the core's own words: it resolves
        // a tier into these two keys and nothing else
        // (`ExportSheetController.overrides()`), so the agent spells them
        // the same way rather than re-deriving a rate from a tier name.
        // The core validates them — positive, u32 — and an unset key means
        // "the preset decides", which is what a nil bitrate already means
        // to the writer.
        if let video = try intArg(a, "video_bitrate") {
            overrides["video_bitrate"] = video
        }
        if let audio = try intArg(a, "audio_bitrate") {
            overrides["audio_bitrate"] = audio
        }
        // The sheet's Loudness popup, in the core's words again — and
        // through `doubleArg`, not `intArg`: −14.5 LUFS is a real request
        // and every one of these figures is a negative fraction. Neither
        // is validated here. `export_overrides.rs` owns the bounds
        // (−70…0 and −20…0) and names the offending value the way the
        // bitrate refusals do; either may come alone, the ceiling being
        // the master limiter's (spec §11 AU-27).
        // Restating a bound here would be a second spelling of it to
        // drift from the first.
        // The sheet sends both together and fixes the ceiling at
        // −1 dBTP; a caller that wants −0.3 or −2.0 says so here.
        if let target = try doubleArg(a, "loudness_lufs") {
            overrides["loudness_lufs"] = target
        }
        if let ceiling = try doubleArg(a, "peak_dbtp") {
            overrides["peak_dbtp"] = ceiling
        }
        // The sheet's Size popup: a row id, or "Custom…" as an explicit
        // [width, height]. Absent is no override at all, so the tool's
        // default and the sheet's are one code path in the core — the
        // document's size, or an image format's cap.
        if let size = try exportSizeArg(a, document.project, preset: preset) {
            overrides["width"] = size.width
            overrides["height"] = size.height
        }
        // The sheet's Dynamic Range popup (spec §11 HD-14 (c)), forwarded
        // unread: the core's reader and resolver own its three words, its
        // per-row defaults and both refusals, each in its own sentence.
        if let dynamicRange = a["dynamic_range"] {
            overrides["dynamic_range"] = dynamicRange
        }
        // The sheet's Speed popup (spec §11 CX-12 (2)), forwarded unread on the
        // same terms: the core reads the three words and refuses a row without one.
        if let speed = a["encoder_speed"] {
            overrides["encoder_speed"] = speed
        }
        // The sheet's Bit depth popup (spec §11 AU-29), forwarded unread on the
        // same terms: the core reads 16 or 24 and refuses a row without a depth.
        if let bits = a["audio_bits"] {
            overrides["audio_bits"] = bits
        }
        // The sheet's Stems popup (spec §11 AU-108), forwarded unread on the same
        // terms: the core reads "tracks" or "names", refuses a movie row, and refuses
        // a project with no track heard.
        if let stems = a["stems"] {
            overrides["stems"] = stems
        }
        do {
            return try ReelExport.settings(document.project, preset: preset, overrides: overrides)
        } catch {
            throw Self.coreRefusal(error)
        }
    }

    /// The file `export` writes for these arguments: the settings' own
    /// extension on `path`, so the assistant's question names what the tool
    /// will write (spec §11 AI-21 (c)). It throws what the tool would refuse.
    /// Main only, on the document the lane pinned.
    func exportDestination(_ a: [String: Any], on document: ProjectDocument) throws -> URL {
        let preset = try requiredString(a, "preset")
        let path = try requiredString(a, "path")
        let range = (try stringArg(a, "range") ?? "project").lowercased()
        let settings = try exportSettings(a, on: document, preset: preset, range: range)
        return Self.destinationURL(path, extension: Exporter.fileExtension(for: settings))
    }

    /// The `size` argument of `export`, in the Size popup's vocabulary: a row
    /// id resolved through the same `rc_export_sizes` the popup is built from
    /// (`document`, `preset`, `2160p`, `1440p`, `1080p`, `720p` — `ExportSize`
    /// in `ReelCore.swift` says what each means, and `core/src/export_size.rs`
    /// why every document lists every row), or the popup's "Custom…" as an
    /// explicit `[width, height]`. nil when absent, which is no override: the
    /// core's default for the preset.
    ///
    /// A value that is neither is refused by NAME, never read as absent — the
    /// rule every reader in `AgentServer+Arguments.swift` keeps, and the root
    /// `CLAUDE.md`'s: a value a handler cannot read is refused by name, never
    /// dropped. A `size` dropped in silence would export at the wrong size
    /// and report success. A custom
    /// size outside the sheet's own field range is refused the same way,
    /// where the sheet clamps: a tool has no field to clamp in view of the
    /// caller, and the sheet's reason — a mistyped digit must not reach the
    /// encoder as a 300 000-pixel frame — holds for a model's typo too.
    private func exportSizeArg(
        _ a: [String: Any], _ project: ReelProject, preset: String
    ) throws -> (width: Int, height: Int)? {
        guard let raw = a["size"], !(raw is NSNull) else { return nil }
        // The rows come first, whichever spelling follows: every refusal
        // below lists the ids from them rather than from a vocabulary
        // restated here, which could drift from the core's, and a preset the
        // core does not know is refused at this point in the same words
        // `exportProject` would use a call later.
        let rows: [ExportSize]
        do {
            rows = try ReelExport.sizes(project, preset: preset)
        } catch {
            throw Self.coreRefusal(error)
        }
        let ids = rows.map { $0.id }.joined(separator: ", ")
        if let id = raw as? String {
            guard let row = rows.first(where: { $0.id == id }) else {
                throw ToolError(
                    message: "No export size is called \"\(id)\" for \(preset). The sizes "
                        + "are: \(ids) — or pass [width, height].")
            }
            return (row.width, row.height)
        }
        if let array = raw as? [Any], array.count == 2 {
            let edges = array.compactMap(Self.wholeEdge)
            if edges.count == 2 {
                let range = ExportSheetController.sizeRange
                // Each refusal of a `size` offers the OTHER spelling: the
                // unknown-id one above names the custom form, and this one
                // names the rows, so a caller who meant a standard size and
                // reached for numbers has the ids in front of it.
                guard edges.allSatisfy(range.contains) else {
                    throw ToolError(
                        message: "A custom size must be \(range.lowerBound)…\(range.upperBound) "
                            + "px on each edge, not [\(edges[0]), \(edges[1])] — or pass a "
                            + "row: \(ids).")
                }
                return (edges[0], edges[1])
            }
        }
        throw ToolError(
            message: "size must be a row of the export sheet's Size popup — \(ids) — or "
                + "[width, height] in px, not \(Self.spelled(raw)).")
    }

    /// One edge of a custom size as a whole number, or nil for a value that
    /// is not one — which sends the whole `size` to the refusal that names
    /// it. The coercion `intArg` applies holds: a string spelling of a whole
    /// number is a JSON-typing slip, not a different request. A fraction is
    /// refused rather than truncated, since 1920.5 is not a width the caller
    /// can have meant. So is a boolean: JSON's `true` arrives as an
    /// `NSNumber` like any other and would read as 1 through it, and the
    /// Core Foundation type is the one thing that still tells `true` from
    /// `1`.
    private static func wholeEdge(_ value: Any) -> Int? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let real = number.doubleValue
            return real.isFinite && real == real.rounded() ? number.intValue : nil
        }
        return (value as? String).flatMap(Int.init)
    }

    /// A refusal from `rc_export_settings` or `rc_export_sizes` as the tool's
    /// error. The core's message passes through as it was, with one
    /// addition: an unknown preset id — the message that begins
    /// "unknown export preset", the same words from either call
    /// (`export.rs`) — gets the ids the table does take appended, because
    /// without them it is the one error a model cannot correct itself from,
    /// since nothing else lists the table. A refused bitrate or range keeps
    /// its own message alone: a list of presets under it would be a false
    /// lead.
    private static func coreRefusal(_ error: any Error) -> ToolError {
        let message = error.localizedDescription
        guard message.hasPrefix("unknown export preset") else {
            return ToolError(message: message)
        }
        let names = ReelExport.presets().map { $0.id }.joined(separator: ", ")
        return ToolError(message: "\(message). The presets are: \(names).")
    }

    /// A caller's value as it was spelled, for a refusal that names it: its
    /// JSON where it is JSON, its Swift description otherwise.
    private static func spelled(_ raw: Any) -> String {
        guard JSONSerialization.isValidJSONObject([raw]),
            let data = try? JSONSerialization.data(
                withJSONObject: raw, options: [.fragmentsAllowed]),
            let text = String(data: data, encoding: .utf8)
        else { return String(describing: raw) }
        return text
    }
}
