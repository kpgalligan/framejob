import AppKit

/// The recorder panel's polish follow (road map "creator-jobs" CU10, spec §11 CU-101 (f)…(i)):
/// a repeating timer per LANDING — never joined with another, unlike Enhance's — in the run
/// loop's DEFAULT mode, so a drag (tracking mode) holds it. Each firing decides for the first
/// command still to run; the follow ends FIRST, its timer invalidated and its entry removed, on
/// `.drop`, on `.giveUp`, before the last run, or when the cursor files fail to read, and then
/// the step acts. A refusal from one run moves on to the next command, whose clock starts then.
///
/// The panel's settings are what each menu door would use (CU-101 (g)): Auto Zoom's remembered
/// sheet values with Zoom on typing on whenever the files hold typing, the overlays' defaults
/// and Speed Up Typing's remembered sheet values. Nothing here asks: a plan with no ops and a
/// `.drop` are quiet, and a refusal, a give-up or a read failure is said at the inspector's foot
/// (`projectDocumentDidRefuse`), with no beep and no sheet (CU-101 (h)). A timer is not an
/// AppKit event, so every commit is `performGroupedEdit`.
extension RecordingPolish {
    /// One landing's follow.
    private final class Follow {
        weak var document: ProjectDocument?
        let paths: [String]
        let scope: UInt32?
        var commands: [Command]
        var started = Date()
        var enhancing = false
        /// The cursor files, by media id, once read; `reading` while a read is out.
        var tracks: [UInt32: ReelCursor]?
        var reading = false
        var timer: Timer?

        init(document: ProjectDocument, paths: [String], scope: UInt32?, commands: [Command]) {
            self.document = document
            self.paths = paths
            self.scope = scope
            self.commands = commands
        }
    }

    /// The follows under way, by a number minted per landing.
    private static var follows: [Int: Follow] = [:]
    private static var minted = 0

    /// The panel's landing hands its result here once it has committed (after Enhance's
    /// follow). A no-op unless the choice asks for a command. Main.
    static func follow(_ result: RecordingResult, in document: ProjectDocument) {
        let asked = commands(of: result.choice)
        guard !asked.isEmpty else { return }
        minted += 1
        let id = minted
        let follow = Follow(
            document: document, paths: screenPaths(of: result), scope: document.scope,
            commands: asked)
        follows[id] = follow
        // `scheduledTimer` adds it in the DEFAULT mode: it waits out a drag.
        follow.timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) {
            [weak document] timer in
            guard let document else {
                timer.invalidate()
                follows[id] = nil
                return
            }
            tick(id, document)
        }
    }

    /// True while any follow of `document` runs. Main.
    static func isPending(_ document: ProjectDocument) -> Bool {
        follows.values.contains { $0.document === document }
    }

    /// One firing. Main.
    private static func tick(_ id: Int, _ document: ProjectDocument) {
        guard let follow = follows[id], let command = follow.commands.first else {
            return end(id, document)
        }
        let clips = screenClips(follow.paths, in: document)
        // CU-101 (a): the clock restarts when Enhance Voice's follow ends.
        let enhancing = RecordingEnhance.isPending(document)
        if follow.enhancing && !enhancing { follow.started = Date() }
        follow.enhancing = enhancing
        let media = mediaIDs(clips, in: document)
        if !clips.isEmpty, !follow.reading,
            follow.tracks.map({ !media.isSubset(of: Set($0.keys)) }) ?? true
        {
            read(id, follow, clips, in: document)
        }
        let window = RecorderPanelController.editor(of: document)?.view.window
        let busy =
            RecordingEnhance.isBusy(document, scope: follow.scope) || window == nil
            || window?.attachedSheet != nil
        let ready =
            follow.tracks.map { tracks in
                media.isSubset(of: Set(tracks.keys))
                    && isReady(
                        command, clips: clips, tracks: tracks,
                        speedUp: SpeedUpTypingSettings.remembered(.standard), in: document)
            } ?? false
        let step = decide(
            command: command, clips: clips, enhancing: enhancing, ready: ready, busy: busy,
            elapsed: Date().timeIntervalSince(follow.started))
        switch step {
        case .wait:
            return
        case .drop:
            end(id, document)
        case .giveUp(let given):
            end(id, document)
            refuse(given, notReadySentence(given, tool: false), in: document)
        case .run(let ran, let ids):
            follow.commands.removeFirst()
            follow.started = Date()
            if follow.commands.isEmpty { end(id, document) }
            if let reason = run(ran, clips: ids, tracks: follow.tracks ?? [:], in: document) {
                refuse(ran, reason, in: document)
            }
        }
    }

    /// The media ids of `clips`. Main.
    private static func mediaIDs(_ clips: [UInt32], in document: ProjectDocument) -> Set<UInt32> {
        let snapshot = document.editedProject.snapshot
        return Set(clips.compactMap { snapshot.clip($0).flatMap { snapshot.media(for: $0)?.id } })
    }

    /// The clips' cursor files read on a global queue, once; a failure ends the follow and is
    /// said under the command it was read for. Main.
    private static func read(
        _ id: Int, _ follow: Follow, _ clips: [UInt32], in document: ProjectDocument
    ) {
        let snapshot = document.editedProject.snapshot
        let files: [UInt32: URL]
        do {
            files = try AutoZoom.cursorFiles(clips.compactMap { snapshot.clip($0) }, in: snapshot)
        } catch {
            return failRead(id, follow, error, in: document)
        }
        follow.reading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let read = Result { try AutoZoom.readTracks(files) }
            DispatchQueue.main.async { [weak document] in
                follow.reading = false
                guard let document, follows[id] === follow else { return }
                switch read {
                case .success(let tracks): follow.tracks = tracks
                case .failure(let error): failRead(id, follow, error, in: document)
                }
            }
        }
    }

    private static func failRead(
        _ id: Int, _ follow: Follow, _ error: Error, in document: ProjectDocument
    ) {
        let command = follow.commands.first ?? .autoZoom
        end(id, document)
        refuse(command, error.localizedDescription, in: document)
    }

    private static func end(_ id: Int, _ document: ProjectDocument) {
        follows[id]?.timer?.invalidate()
        follows[id] = nil
        forgetWait(document)
    }

    // MARK: - The three runs

    /// Plans `command` over `clips` and commits it as one grouped step; nil when it applied or
    /// had nothing to do, else the sentence to say. Main.
    private static func run(
        _ command: Command, clips ids: [UInt32], tracks: [UInt32: ReelCursor],
        in document: ProjectDocument
    ) -> String? {
        let snapshot = document.editedProject.snapshot
        let clips = ids.compactMap { snapshot.clip($0) }
        do {
            switch command {
            case .autoZoom:
                var settings = AutoZoomSettings.remembered(.standard)
                settings.typing = AutoZoom.hasTyping(tracks)
                let plan = try AutoZoom.plan(
                    clips, tracks: tracks, project: document.editedProject, settings: settings,
                    from: nil, to: nil)
                guard !plan.ops.isEmpty else { return nil }
                document.performGroupedEdit(AutoZoom.actionName, plan.ops)
            case .shortcutOverlays:
                let planned = try ShortcutOverlays.prepared(
                    document, clips: ids, tracks: tracks, settings: ShortcutOverlaySettings(),
                    from: nil, to: nil)
                guard !planned.plan.ops.isEmpty else { return nil }
                document.performGroupedEdit(ShortcutOverlays.actionName, planned.plan.ops)
            case .speedUpTyping:
                return try speedUp(clips, tracks: tracks, in: document)
            }
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    /// CU-101 (i): the panel cannot ask Set Speed, so a speed-up that would leave a clip's audio
    /// out is not applied and its note is the refusal; otherwise one grouped step, the captions
    /// it re-times riding in it.
    private static func speedUp(
        _ clips: [ClipSnapshot], tracks: [UInt32: ReelCursor], in document: ProjectDocument
    ) throws -> String? {
        let outcome = try SpeedUpTyping.resolve(
            clips, tracks: tracks, project: document.editedProject,
            cacheDirectory: document.cacheDirectory,
            settings: SpeedUpTypingSettings.remembered(.standard), from: nil, to: nil)
        guard case .planned(let speechOps, let plan) = outcome else {
            return notReadySentence(.speedUpTyping, tool: false)
        }
        guard !plan.ops.isEmpty else { return nil }
        let step = CaptionRetime.withRetime(
            SpeedUpTyping.actionName, speechOps + plan.ops, on: document.editedProject)
        let crossing =
            SpeedAudioDrop.mayCross(step.ops)
            ? SpeedAudioDrop.crossing(applying: step.ops, to: document.editedProject) : []
        guard crossing.isEmpty else { return SpeedAudioDrop.note(crossing) }
        document.performGroupedEdit(step.name, step.ops)
        return nil
    }

    /// A refusal of `command` at the inspector's foot; no beep (CU-101 (h)).
    private static func refuse(_ command: Command, _ reason: String, in document: ProjectDocument) {
        NotificationCenter.default.post(
            name: .projectDocumentDidRefuse, object: document,
            userInfo: ["refusal": ReelRefusal(op: command.rawValue, reason: reason)])
    }
}
