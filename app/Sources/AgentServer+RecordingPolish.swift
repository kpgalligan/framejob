import Foundation

/// `record_screen`'s polish on landing (road map "creator-jobs" CU10, spec §11 CU-100…CU-102):
/// the three arguments `auto_zoom`, `shortcut_overlays` and `speed_up_typing` and their
/// refusals, and the tool door's follow-up after `land` and any Enhance Voice — the panel's
/// "When it lands:" boxes without the panel. Every command is its tool's own body
/// (`autoZoom(document:clips:settings:)` and the two beside it) at the tools' defaults, since a
/// tool reads no `UserDefaults`, each its own undo step.
extension AgentServer {

    /// The three booleans (default false), in the order auto_zoom, shortcut_overlays,
    /// speed_up_typing, each refused without `place` and the last two without `keys:
    /// "shortcuts"` (CU-102 (b)); read after `enhance`, before any grant. With voice_over or
    /// camera they never reach here: the source's stranger lists refuse them by name.
    func recordingPolish(_ a: [String: Any], place: Bool, keys: RecordingKeys) throws
        -> [RecordingPolish.Command]
    {
        var asked: [RecordingPolish.Command] = []
        for command in RecordingPolish.Command.allCases {
            guard try boolArg(a, command.rawValue) ?? false else { continue }
            if !place { throw ToolError(message: Self.polishNeedsPlace(command)) }
            if command != .autoZoom, keys != .shortcuts {
                throw ToolError(message: Self.polishNeedsKeys(command))
            }
            asked.append(command)
        }
        return asked
    }

    /// CU-102 (b)'s `place` sentences.
    static func polishNeedsPlace(_ command: RecordingPolish.Command) -> String {
        switch command {
        case .autoZoom:
            return "auto_zoom: true plans on the landed screen clips, so it needs place: true."
        case .shortcutOverlays:
            return "shortcut_overlays: true places overlays over the landed screen clips, so it "
                + "needs place: true."
        case .speedUpTyping:
            return "speed_up_typing: true speeds up the landed screen clips' typing, so it needs "
                + "place: true."
        }
    }

    /// CU-102 (b)'s `keys` sentences (none for auto_zoom, which zooms on clicks too).
    static func polishNeedsKeys(_ command: RecordingPolish.Command) -> String {
        let what = command == .speedUpTyping ? "typing to speed up" : "shortcut to show"
        return "\(command.rawValue): true needs keys: \"shortcuts\" — without it the cursor file "
            + "records no \(what)."
    }

    /// SERVER THREAD. CU-101 (j): for each command the choice asks for, in order, `decide`
    /// polled through `onMain` every `RecordingPolish.checkInterval`, then the tool's body; its
    /// answer object under the command's name, or a sentence under `<name>_error`. On `.drop`,
    /// `.giveUp` or the call's cancel, every command not yet run gets its sentence. The cursor
    /// files are read here, once, for the speed-up's readiness; a read that fails counts as
    /// ready, so the body says why.
    func polishLanded(
        _ result: RecordingResult, in document: ProjectDocument, into fields: inout [String: Any]
    ) {
        var remaining = RecordingPolish.commands(of: result.choice)
        guard !remaining.isEmpty else { return }
        let stop = AgentLane.shared.callCancel
        let paths = RecordingPolish.screenPaths(of: result)
        let scope = onMain { document.scope }
        var tracks: [UInt32: ReelCursor]?
        var started = Date()
        func fail(_ sentence: (RecordingPolish.Command) -> String) {
            for command in remaining { fields[command.rawValue + "_error"] = sentence(command) }
            remaining = []
        }
        while let command = remaining.first {
            if stop?.isCancelled == true {
                fail(RecordingPolish.stoppedSentence)
                break
            }
            if command == .speedUpTyping, tracks == nil {
                let files = onMain { () -> [UInt32: URL] in
                    let snapshot = document.editedProject.snapshot
                    let clips = RecordingPolish.screenClips(paths, in: document)
                    return (try? AutoZoom.cursorFiles(
                        clips.compactMap { snapshot.clip($0) }, in: snapshot)) ?? [:]
                }
                tracks = (try? AutoZoom.readTracks(files)) ?? [:]
            }
            let held = tracks ?? [:]
            let step = onMain { () -> RecordingPolish.Step in
                let clips = RecordingPolish.screenClips(paths, in: document)
                let ready =
                    !clips.isEmpty
                    && RecordingPolish.isReady(
                        command, clips: clips, tracks: held, speedUp: SpeedUpTypingSettings(),
                        in: document)
                return RecordingPolish.decide(
                    command: command, clips: clips,
                    enhancing: RecordingEnhance.isPending(document), ready: ready,
                    busy: RecordingEnhance.isBusy(document, scope: scope),
                    elapsed: Date().timeIntervalSince(started))
            }
            switch step {
            case .wait:
                Thread.sleep(forTimeInterval: RecordingPolish.checkInterval)
            case .drop:
                fail(RecordingPolish.noScreenSentence)
            case .giveUp:
                fail { RecordingPolish.notReadySentence($0, tool: true) }
            case .run(let ran, let clips):
                do {
                    let answer = try polish(ran, document: document, clips: clips)
                    fields[ran.rawValue] = Self.resultObject(answer) ?? answer
                } catch let error as ToolError {
                    fields[ran.rawValue + "_error"] = error.message
                } catch {
                    fields[ran.rawValue + "_error"] = error.localizedDescription
                }
                remaining.removeFirst()
                started = Date()
            }
        }
        onMain { RecordingPolish.forgetWait(document) }
    }

    /// One command through its tool's body at the tools' defaults. SERVER THREAD.
    private func polish(
        _ command: RecordingPolish.Command, document: ProjectDocument, clips: [UInt32]
    ) throws -> String {
        switch command {
        case .autoZoom:
            return try autoZoom(document: document, clips: clips, settings: AutoZoomSettings())
        case .shortcutOverlays:
            return try addShortcutOverlays(
                document: document, clips: clips, settings: ShortcutOverlaySettings())
        case .speedUpTyping:
            return try speedUpTyping(
                document: document, clips: clips, settings: SpeedUpTypingSettings())
        }
    }
}
