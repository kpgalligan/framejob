import Foundation

/// The recorder's polish on landing (road map "creator-jobs" CU10, spec §11 CU-100…CU-102):
/// Auto Zoom, Add Shortcut Overlays and Speed Up Typing run over a finished screen recording's
/// clips as FOLLOW-UPS to the landing — never part of it (AU-68's shape). The landing commits
/// at once and is unchanged; each command follows as its own undo step, named by its title, in
/// `allCases` order, after any Enhance Voice: zooms are planned on unsplit clips, and the
/// speed-up's stretches avoid the overlays (CU-91).
///
/// The values and the pure decision are here: which commands a choice asks for (`commands`),
/// which files are the screen (`screenPaths`), which clips they are now (`screenClips`,
/// recomputed at every check, so the speed-up's splits and clips added later are seen), whether
/// a command can run (`isReady`), the sentences, and `decide`. The two doors share them: the
/// panel through `follow` (`RecordingPolish+Follow.swift`), and `record_screen` /
/// `land_recording`'s tool door through `AgentServer.polishLanded`, which polls `decide` from
/// the server thread.
enum RecordingPolish {
    /// The three commands, in the order they run.
    enum Command: String, CaseIterable {
        case autoZoom = "auto_zoom"
        case shortcutOverlays = "shortcut_overlays"
        case speedUpTyping = "speed_up_typing"

        /// Each command's undo step, its `actionName`.
        var title: String {
            switch self {
            case .autoZoom: return AutoZoom.actionName
            case .shortcutOverlays: return ShortcutOverlays.actionName
            case .speedUpTyping: return SpeedUpTyping.actionName
            }
        }

        /// The menu item a person runs it by.
        var menuPath: String {
            switch self {
            case .autoZoom: return "Clip ▸ Auto Zoom…"
            case .shortcutOverlays: return "Clip ▸ Add Shortcut Overlays"
            case .speedUpTyping: return "Clip ▸ Speed Up Typing…"
            }
        }
    }

    /// What one check decides (CU-101 (e)).
    enum Step: Equatable {
        case wait
        case run(Command, [UInt32])
        case drop
        case giveUp(Command)
    }

    /// One check every half second, the landing's (and Enhance's) own interval.
    static let checkInterval: TimeInterval = RecordingEnhance.checkInterval
    /// Past this since a command's clock started, it is given up on.
    static let waitLimit: TimeInterval = 300

    /// The commands `choice` asks for, always in `allCases` order.
    static func commands(of choice: RecordingChoice) -> [Command] {
        Command.allCases.filter { command in
            switch command {
            case .autoZoom: return choice.autoZoom
            case .shortcutOverlays: return choice.shortcutOverlays
            case .speedUpTyping: return choice.speedUpTyping
            }
        }
    }

    // MARK: - The screen

    /// Each segment's movie, the screen's files; none for a voice-over or a camera alone, whose
    /// segments are no screen. Pure; empty paths dropped, each path once.
    static func screenPaths(of result: RecordingResult) -> [String] {
        guard !result.isVoiceOver, result.choice.source != .camera else { return [] }
        var seen: Set<String> = []
        return result.segments.map { $0.descriptor.path }.filter {
            !$0.isEmpty && seen.insert($0).inserted
        }
    }

    /// Every clip of the open container whose media is one of `paths` AND has a cursor file,
    /// in id order. Main.
    static func screenClips(_ paths: [String], in document: ProjectDocument) -> [UInt32] {
        let wanted = Set(paths)
        guard !wanted.isEmpty else { return [] }
        let snapshot = document.editedProject.snapshot
        return snapshot.clips.filter { clip in
            guard let media = snapshot.media(for: clip) else { return false }
            return wanted.contains(media.path) && media.cursor != nil
        }.map(\.id).sorted()
    }

    // MARK: - Readiness

    /// Documents whose speech wait has started the cache pass, by `recipeKey` (CU-101 (c)).
    private static var cachesStarted: Set<Int> = []

    /// CU-101 (c). Auto Zoom and Add Shortcut Overlays need only the cursor files, which the
    /// caller has read. The speed-up is ready unless `SpeedUpTyping.resolve` answers `.waiting`;
    /// its first `.waiting` for the document starts `generateCaches()` (a pass that could not
    /// read a file is not retried until the next open). A throw counts as ready, so the run
    /// reports the refusal. Main.
    static func isReady(
        _ command: Command, clips: [UInt32], tracks: [UInt32: ReelCursor],
        speedUp: SpeedUpTypingSettings, in document: ProjectDocument
    ) -> Bool {
        guard command == .speedUpTyping else { return true }
        let snapshot = document.editedProject.snapshot
        let outcome: SpeedUpTypingOutcome
        do {
            outcome = try SpeedUpTyping.resolve(
                clips.compactMap { snapshot.clip($0) }, tracks: tracks,
                project: document.editedProject, cacheDirectory: document.cacheDirectory,
                settings: speedUp, from: nil, to: nil)
        } catch {
            return true
        }
        guard case .waiting = outcome else {
            cachesStarted.remove(document.recipeKey)
            return true
        }
        if cachesStarted.insert(document.recipeKey).inserted { document.generateCaches() }
        return false
    }

    /// The wait for `document` is over: a later wait starts the pass again. Main.
    static func forgetWait(_ document: ProjectDocument) {
        cachesStarted.remove(document.recipeKey)
    }

    /// CU-101 (e), in this order. Pure.
    static func decide(
        command: Command, clips: [UInt32], enhancing: Bool, ready: Bool, busy: Bool,
        elapsed: TimeInterval
    ) -> Step {
        if clips.isEmpty { return .drop }
        if enhancing { return .wait }
        if ready && !busy { return .run(command, clips) }
        if elapsed >= waitLimit { return .giveUp(command) }
        return .wait
    }

    // MARK: - Sentences (CU-101 (k))

    static func noScreenSentence(_ c: Command) -> String {
        "No screen clip with a cursor file landed on the timeline, so \(c.title) did not run."
    }

    static func notReadySentence(_ c: Command, tool: Bool) -> String {
        let why =
            c == .speedUpTyping
            ? "its speech was not detected within 5 minutes."
            : "the project was busy for 5 minutes."
        let way =
            tool
            ? " Call \(c.rawValue) with its clips."
            : " Select its clips and choose \(c.menuPath)."
        return "\(c.title) did not run on the recording: " + why + way
    }

    static func stoppedSentence(_ c: Command) -> String {
        "record_screen was stopped before \(c.title) ran, so it did not run."
    }

    /// The panel box's tooltip (CU-102 (a)), naming the step.
    static func tooltip(_ c: Command) -> String {
        "After the recording lands, run \(c.menuPath) on its screen clips as its own undo step, "
            + "\"\(c.title)\"."
    }
}
