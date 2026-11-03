import AppKit

#if FRAMEJOB_DEV_TOOLS
/// `land_recording` — a dev tool (road map "audio" AP6 part 3, spec §11
/// AU-69 (e)): fixture files handed to the product's own code as a finished
/// recording, through either door, so `audio_ap6c_proof.py` can watch
/// "Enhance the microphone when it lands" without a recorder. The recorder
/// needs the Microphone grant and a voice at the microphone, while a proof's
/// instance records room tone under the terminal's grants; everything after
/// `onFinish` here is the product's: the panel's `recordingEnded` (and so its
/// landing and `RecordingEnhance.follow`), or `record_screen`'s
/// `awaitGestureEnd` and `landAndEnhance`. It mirrors no edit of its own.
///
/// Off main (`devOffMainTools`): it probes files, waits for the panel and
/// polls the follow, every touch an `onMain` hop.
extension AgentServer {
    /// Which door the fixture recording lands through.
    enum LandRecordingDoor: String, CaseIterable {
        case tool, panel
    }

    /// The microphone id a fixture recording names: any non-nil id says
    /// "recorded with a microphone".
    static let landRecordingMicrophone = "land_recording"

    func landRecording(_ a: [String: Any]) throws -> String {
        try requireServerThread("land_recording")
        guard let voice = try stringsArg(a, "voice"), !voice.isEmpty else {
            throw ToolError(message: "Missing required argument: voice")
        }
        guard voice.count <= 8 else {
            throw ToolError(message: "voice must name 1…8 files (got \(voice.count)).")
        }
        let movie = try stringArg(a, "movie")
        let door = try enumArg(a, "door", LandRecordingDoor.self) ?? .tool
        let enhance = try boolArg(a, "enhance") ?? false
        let place = try boolArg(a, "place")
        let followWait = try doubleArg(a, "follow_wait")
        let cursor = try stringArg(a, "cursor")
        if cursor != nil, movie == nil {
            throw ToolError(
                message: "cursor cannot be given without movie — a cursor file belongs to the "
                    + "screen segment's movie.")
        }
        // CU3c (spec §11 CU-36 (e)): the choice's Cursor and Show Clicks, a screen's only.
        let cursorMode = try enumArg(a, "cursor_mode", RecordingCursor.self)
        if cursorMode != nil, movie == nil {
            throw ToolError(
                message: "cursor_mode cannot be given without movie — a voice-over has no "
                    + "pointer.")
        }
        let showClicks = try boolArg(a, "show_clicks")
        if showClicks != nil, movie == nil {
            throw ToolError(
                message: "show_clicks cannot be given without movie — a voice-over has no "
                    + "clicks.")
        }
        if movie != nil, voice.count != 1 {
            throw ToolError(
                message: "With movie, voice must name exactly one file — the movie's microphone "
                    + "(got \(voice.count)).")
        }
        if door == .panel, place != nil {
            throw ToolError(
                message: "place cannot be given with door: \"panel\" — the panel always places.")
        }
        if let followWait {
            guard door == .panel else {
                throw ToolError(
                    message: "follow_wait cannot be given with door: \"tool\" — that door "
                        + "already waits for the enhance.")
            }
            guard followWait.isFinite, (0...330).contains(followWait) else {
                throw ToolError(message: "follow_wait must be 0…330 seconds (got \(followWait)).")
            }
        }
        let voices = try voice.map(landRecordingProbe)
        let picture = try movie.map(landRecordingProbe)
        let destination = try onMain { try self.recordingDestination(a) }

        var choice = RecordingChoice()
        choice.source = picture == nil ? .voiceOver : .display(CGMainDisplayID())
        choice.microphone = Self.landRecordingMicrophone
        choice.systemAudio = false
        choice.destination = destination
        choice.enhanceMicrophone = enhance
        choice.cursor = cursorMode
        choice.showClicks = showClicks ?? false
        let now = Date()
        let segments =
            try picture.map {
                [
                    try landRecordingCursor(
                        cursor,
                        RecordingSegment(
                            descriptor: $0, micDescriptor: voices[0], micOffset: 0,
                            startedAt: now))
                ]
            }
            ?? voices.map {
                RecordingSegment(descriptor: $0, micDescriptor: nil, micOffset: 0, startedAt: now)
            }
        let result = RecordingResult(
            segments: segments, choice: choice, stoppedBy: .stopped, pauses: 0)

        switch door {
        case .tool:
            awaitGestureEnd(destination)
            return try landAndEnhance(result, place: place ?? true)
        case .panel:
            return try landThroughPanel(result, followWait: followWait ?? 0)
        }
    }

    /// One fixture file, probed as `record_screen`'s settle probes its files
    /// (`mayAsk: false`); a file that will not probe is refused naming it.
    private func landRecordingProbe(_ raw: String) throws -> MediaDescriptor {
        let path = (raw.trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
            .expandingTildeInPath
        let semaphore = DispatchSemaphore(value: 0)
        let box = AgentBox<Result<MediaDescriptor, any Error>>()
        MediaImporter.probe(url: URL(fileURLWithPath: path), mayAsk: false) { outcome in
            box.value = outcome
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + MediaImporter.probeTimeout) == .success,
            let outcome = box.value
        else {
            throw ToolError(message: "land_recording: \(path) did not probe in time.")
        }
        do {
            return try outcome.get()
        } catch {
            throw ToolError(
                message: "land_recording: \(path) will not probe: \(error.localizedDescription)")
        }
    }

    /// The screen segment with `cursor`'s file attached (spec §11 CU-34 (d)), as a recording's
    /// landing attaches the file it wrote; `segment` unchanged without `cursor`. A file that does
    /// not attach is refused in `cursorAttachment`'s sentence.
    private func landRecordingCursor(
        _ cursor: String?, _ segment: RecordingSegment
    ) throws -> RecordingSegment {
        guard let cursor else { return segment }
        let file = URL(
            fileURLWithPath: (cursor.trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
                .expandingTildeInPath)
        switch MediaImporter.cursorAttachment(at: file, to: segment.descriptor) {
        case .success(let attachment):
            return segment.withCursor(
                url: file, problem: nil, image: attachment.image, attached: attachment.cursor)
        case .failure(let problem):
            throw ToolError(message: "land_recording: " + problem.message)
        }
    }

    /// The panel's door: `recordingEnded(.success)` on main, then up to 25 s
    /// for the panel to be idle again, then up to `followWait` seconds for its
    /// follow to end. `landed` is `document` or `new_project` when the
    /// recording's first file is in a project, else null; `note` the panel's.
    private func landThroughPanel(_ result: RecordingResult, followWait: Double) throws -> String {
        let before = try onMain { () throws -> Set<ObjectIdentifier> in
            let panel = RecorderPanelController.shared
            guard panel.phase == .idle, ScreenRecorder.shared.state == .idle else {
                throw ToolError(
                    message: "door: \"panel\" needs the recorder and its panel idle — a "
                        + "recording or a landing is under way.")
            }
            let open = Set(self.openProjects().map(ObjectIdentifier.init))
            panel.recordingEnded(.success(result))
            return open
        }
        let idleBy = Date().addingTimeInterval(25)
        while Date() < idleBy, onMain({ RecorderPanelController.shared.phase != .idle }) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        let path = result.descriptor.path
        let (document, landed) = onMain { () -> (ProjectDocument?, String?) in
            func holds(_ document: ProjectDocument) -> Bool {
                document.project.snapshot.media.contains { $0.path == path }
            }
            if let fresh = self.openProjects().first(where: {
                !before.contains(ObjectIdentifier($0)) && holds($0)
            }) {
                return (fresh, "new_project")
            }
            if case .document(let target) = RecordingLanding.resolve(result.choice.destination),
                holds(target)
            {
                return (target, "document")
            }
            return (nil, nil)
        }
        if let document, followWait > 0 {
            let until = Date().addingTimeInterval(followWait)
            while Date() < until, onMain({ RecordingEnhance.isPending(document) }) {
                Thread.sleep(forTimeInterval: RecordingEnhance.checkInterval)
            }
        }
        return try onMain {
            var fields: [String: Any] = [
                "landed": landed.map { $0 as Any } ?? NSNull(),
                "note": RecorderPanelController.shared.noteLabel.stringValue,
            ]
            if let document { fields["project"] = self.summary(document) }
            fields["enhance_pending"] = document.map(RecordingEnhance.isPending) ?? false
            return try self.jsonResult(fields)
        }
    }

    // MARK: - Catalog

    func landRecordingTool() -> [String: Any] {
        tool(
            "land_recording",
            "DEV TOOL (absent from Distribution builds). Land fixture files as a FINISHED "
                + "recording, through the product's own code after the recorder's onFinish — "
                + "for proving Enhance the microphone when it lands (spec AU-68, AU-69) without "
                + "a microphone grant or a voice. Without movie, a voice-over of the voice "
                + "files, one segment each; with movie, one screen segment whose microphone file "
                + "is voice's one file (mic_offset 0), and cursor, when given, a cursor file "
                + "attached to that segment's media as a recording's landing attaches the file it "
                + "wrote (spec CU-34); cursor_mode and show_clicks are that recording's Cursor and "
                + "Show Clicks, so a separate one with show_clicks lands its screen clip with "
                + "ripples as a recording does (spec CU-31). Each file is probed as a recording's "
                + "are. "
                + "door tool (default) waits out a drag and lands as record_screen does, "
                + "answering what record_screen would, enhance or enhance_error included; door "
                + "panel hands the result to the recorder panel's recordingEnded, waits up to "
                + "25 s for the panel to be idle and then up to follow_wait seconds for its "
                + "follow to end, and answers {landed (document, new_project or null), note "
                + "(the panel's), project, enhance_pending (read last)}. Refused by name: a "
                + "path that will not probe, movie with other than one voice file, place with "
                + "door panel, door panel while the recorder or the panel is not idle, "
                + "follow_wait with door tool or outside 0…330, cursor, cursor_mode or "
                + "show_clicks without movie, a cursor file that does not attach (it will not "
                + "open, or its movie_size is not the "
                + "movie's).",
            [
                "voice": [
                    "type": "array", "items": ["type": "string"],
                    "description": "1…8 sound files: a voice-over's files in order, or with "
                        + "movie the one microphone file.",
                ],
                "movie": [
                    "type": "string",
                    "description": "A movie to land as the screen recording's picture, its "
                        + "microphone voice's one file.",
                ],
                "cursor": [
                    "type": "string",
                    "description": "with movie only: a cursor file (.fjcursor) attached to the "
                        + "screen segment's media; its movie_size must be the movie's.",
                ],
                "cursor_mode": [
                    "type": "string", "enum": RecordingCursor.allCases.map(\.rawValue),
                    "description": "with movie only: the recording's Cursor, separate or "
                        + "in_picture (default: the display's, separate).",
                ],
                "show_clicks": [
                    "type": "boolean",
                    "description": "with movie only: the recording's Show Clicks (default "
                        + "false).",
                ],
                "door": [
                    "type": "string", "enum": LandRecordingDoor.allCases.map(\.rawValue),
                    "description": "tool (default): record_screen's landing; panel: the "
                        + "recorder panel's.",
                ],
                "enhance": [
                    "type": "boolean",
                    "description": "The choice's Enhance the microphone when it lands (default "
                        + "false).",
                ],
                "place": [
                    "type": "boolean",
                    "description": "door tool only: record_screen's place (default true).",
                ],
                "follow_wait": [
                    "type": "number", "minimum": 0, "maximum": 330,
                    "description": "door panel only: seconds to wait for the follow to end "
                        + "(default 0).",
                ],
            ], required: ["voice"])
    }
}
#endif
