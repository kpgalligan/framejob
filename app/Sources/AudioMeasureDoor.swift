import AppKit

/// The one body the Volume section's buttons and the Clip menu share for
/// Normalize and Enhance Voice (road map "audio" AP6, spec §11 AU-60,
/// AU-64, AU-65), and Clip ▸ Match Audio…'s after its sheet (AP12,
/// `pressMatch`, AU-128). Not a line of arithmetic is here: the read, the
/// jobs and the plan are `AudioNormalize`'s, `AudioEnhance`'s and
/// `AudioMatch`'s, the measurement is `LoudnessMeasureRun`'s or
/// `AudioMatchRun`'s, and this decides only how a press waits and commits.
///
/// - **Normalize in Peak mode** commits `AudioNormalize.plan(read).ops` at
///   once, inside the event, exactly as before: no run, no render, no sheet.
/// - **Normalize in Loudness mode and Enhance Voice** build a run. When no
///   clip needs a render the run answers at once and the plan is committed
///   inside the event (`applyEdit`), today's Normalize byte for byte.
///   Otherwise the Measuring Sound sheet goes up from the window's content
///   controller, and its answer is committed with `performGroupedEdit` (a
///   sheet's completion is not an AppKit event, app/CLAUDE.md's undo
///   pitfall) only when the document's project and scope are still the ones
///   the press read; else it beeps and says so at the inspector's foot, as
///   `finishSynchronizeAudio` does.
///
/// Nothing to do, a second press, no window and a sheet already up all beep.
///
/// **A landing's follow** (spec §11 AU-68) is another caller:
/// `enhanceLanded`, Enhance Voice over a recording's voice clips once their
/// caches exist. It shares `measure`, with a refusal at the inspector's foot
/// wherever a press beeps, and commits as its own group, since a timer's
/// firing is not an AppKit event either. It alone passes `done`, which
/// `enhanceLanded` and `measure` call exactly once at every exit — a refusal
/// before the run, the answer or refusal landed with or without the sheet,
/// the sheet's Cancel, a run with no outcome, the document gone — so
/// `RecordingEnhance` knows when its measurement is over (#546).
enum AudioMeasureDoor {
    enum Command {
        case normalize, enhanceVoice, matchAudio

        var name: String {
            switch self {
            case .normalize: return "Normalize"
            case .enhanceVoice: return AudioEnhance.actionName
            case .matchAudio: return AudioMatch.actionName
            }
        }

        var tool: String {
            switch self {
            case .normalize: return "normalize_clip"
            case .enhanceVoice: return "enhance_voice"
            case .matchAudio: return "match_audio"
            }
        }
    }

    /// The sheet's title.
    static let sheetTitle = "Measuring Sound"

    /// The stale answer's sentence, ending in what to do again: "Choose
    /// Enhance Voice again." from the sheet, "Call enhance_voice again." from
    /// a tool.
    static func staleReason(again: String) -> String {
        "the project changed while its sound was being measured, so nothing changed. \(again)"
    }

    static func press(
        _ command: Command, document: ProjectDocument, clips: [UInt32], window: NSWindow?
    ) {
        guard !clips.isEmpty else { return NSSound.beep() }
        switch command {
        case .normalize where NormalizeChoice.mode == .peak:
            guard let input = AudioNormalize.read(from: document, clips: clips) else {
                return NSSound.beep()
            }
            commit(command.name, AudioNormalize.plan(input).ops, document: document)
        case .normalize:
            guard let input = AudioNormalize.readLoudness(from: document, clips: clips) else {
                return NSSound.beep()
            }
            let target = NormalizeChoice.targetLUFS
            let run = LoudnessMeasureRun(
                document: document, jobs: normalizeJobs(input, in: document),
                problems: input.problems, targetLUFS: target)
            measure(command, run: run, document: document, window: window) {
                .ops(AudioNormalize.plan($0.input, targetLUFS: target, solved: $0.solved).ops)
            }
        case .enhanceVoice:
            guard
                let setup = enhanceSetup(
                    document: document, clips: clips, targetLUFS: NormalizeChoice.targetLUFS)
            else { return NSSound.beep() }
            let run = setup.makeRun(document: document)
            measure(command, run: run, document: document, window: window) {
                .ops(setup.plan($0).ops)
            }
        case .matchAudio:
            // Its reference comes from the Match Audio sheet: `pressMatch`.
            NSSound.beep()
        }
    }

    /// Match Audio's press (road map "audio" AP12, spec §11 AU-121, AU-128),
    /// from the Match Audio sheet's hand-back: `reference` and the other
    /// clips, read, then always measured under the Measuring Sound sheet (the
    /// reference renders), its answer landed by `measure`'s stale test. A
    /// refusal — the reference's, or nothing to match — beeps once and puts
    /// its sentence at the inspector's foot, before the sheet or after it
    /// (AU-128, #410).
    static func pressMatch(
        document: ProjectDocument, reference: UInt32, clips: [UInt32], loudness: Bool, eq: Bool,
        window: NSWindow?
    ) {
        guard loudness || eq, !clips.isEmpty else { return NSSound.beep() }
        let input: AudioMatch.Input
        switch AudioMatch.read(
            from: document, reference: reference, clips: clips, loudness: loudness, eq: eq)
        {
        case .failure(let refusal):
            return say(
                refusal.sentence, command: .matchAudio, document: document,
                beep: { NSSound.beep() })
        case .success(let read): input = read
        }
        let run = AudioMatchRun(document: document, input: input)
        measure(
            .matchAudio, run: run, document: document, window: window,
            answer: { matchAnswer(input, $0) })
    }

    /// Match's answer to a run's outcome, pure: the reference's refusal,
    /// else "Nothing could be matched." with every skip when no target was
    /// matched after the renders (the tool's sentence), else the plan's ops.
    static func matchAnswer(_ input: AudioMatch.Input, _ outcome: AudioMatchRun.Outcome) -> Answer {
        if let refusal = outcome.refusal { return .refused(refusal.sentence) }
        let plan = AudioMatch.plan(input, outcome: outcome)
        guard !plan.matched.isEmpty else { return .refused(AudioMatch.nothingMatched(plan.skipped)) }
        return .ops(plan.ops)
    }

    /// Enhance Voice's one setup (AU-68 (e), #412), shared by the press, a
    /// landing's follow and `enhance_voice`: the read, the choices and the
    /// target. It builds no run: `makeRun` is called only after the caller's
    /// refusals, and its caller owes the run `finish()`.
    struct EnhanceSetup {
        let input: AudioEnhance.Input
        let choices: [AudioEnhance.Choice]
        let targetLUFS: Double

        /// The measurement run over the choices' jobs. Main.
        func makeRun(document: ProjectDocument) -> LoudnessMeasureRun {
            LoudnessMeasureRun(
                document: document, jobs: AudioEnhance.jobs(input, choices),
                problems: input.problems, targetLUFS: targetLUFS)
        }

        func plan(_ outcome: LoudnessMeasureRun.Outcome) -> AudioEnhance.Plan {
            AudioEnhance.plan(input, choices: choices, outcome: outcome, targetLUFS: targetLUFS)
        }
    }

    /// Main. Nil when the project's audio plan cannot be read.
    static func enhanceSetup(document: ProjectDocument, clips: [UInt32], targetLUFS: Double)
        -> EnhanceSetup?
    {
        guard let input = AudioEnhance.read(from: document, clips: clips) else { return nil }
        return EnhanceSetup(
            input: input, choices: AudioEnhance.choose(input), targetLUFS: targetLUFS)
    }

    /// Enhance Voice over a landed recording's voice clips (AU-68 (e)), at
    /// Normalize's target: the press's setup and `measure` with refusals in
    /// place of beeps. `done` is called exactly once, after whatever this
    /// call ends in has landed (the type doc, #546). Main.
    static func enhanceLanded(
        document: ProjectDocument, clips: [UInt32], window: NSWindow, done: @escaping () -> Void
    ) {
        let refuse = { (reason: String) in RecordingEnhance.refuse(reason, in: document) }
        guard
            let setup = enhanceSetup(
                document: document, clips: clips, targetLUFS: NormalizeChoice.targetLUFS)
        else {
            refuse("The project's audio plan could not be read, so there is no voice to measure.")
            return done()
        }
        guard !setup.input.isEmpty else {
            refuse(nothingReason(setup.input.problems))
            return done()
        }
        let run = setup.makeRun(document: document)
        measure(
            .enhanceVoice, run: run, document: document, window: window, refuse: refuse,
            empty: { nothingReason(setup.plan($0).skipped) }, done: done
        ) { .ops(setup.plan($0).ops) }
    }

    /// `enhance_voice`'s sentence for nothing measured or nothing planned.
    static func nothingReason(_ problems: [AudioNormalize.Problem]) -> String {
        "Nothing could be enhanced. " + problems.map { $0.description }.joined(separator: " ")
    }

    /// Loudness Normalize's jobs: a clip whose chain has a stage the cache
    /// leaves out renders with no change to its settings (the run takes its
    /// limiter off for R0); any other reading stands (AU-64 (a)). Main.
    static func normalizeJobs(_ input: AudioNormalize.LoudnessInput, in document: ProjectDocument)
        -> [LoudnessMeasureRun.Job]
    {
        let snapshot = document.editedProject.snapshot
        return input.readings.map {
            LoudnessMeasureRun.Job(
                reading: $0,
                chain: ProcessedLoudness.needsRender(snapshot.clip($0.clip)?.audio)
                    ? AudioPatch() : nil)
        }
    }

    /// What a measured press answers: the ops to commit, or a refusal's
    /// sentence known only after the measurement.
    enum Answer {
        case ops([ReelOp])
        case refused(String)
    }

    /// The one landing of a measured answer, on main. `.refused` says its
    /// sentence once: through `refuse` on a landing's follow, else one `beep`
    /// and the sentence at the inspector's foot (`say`). `.ops([])` fails
    /// with `empty()`: `refuse` gets it, or a press gets a bare beep.
    /// Otherwise it commits: `applyEdit` when `inEvent` and `refuse` is nil
    /// (which beeps at an identity), else `performGroupedEdit`. `beep` is the
    /// probe's seam; the app passes none.
    static func land(
        _ answer: Answer, command: Command, document: ProjectDocument, inEvent: Bool,
        refuse: ((String) -> Void)?, empty: @autoclosure () -> String,
        beep: () -> Void = { NSSound.beep() }
    ) {
        switch answer {
        case .refused(let reason):
            if let refuse { return refuse(reason) }
            say(reason, command: command, document: document, beep: beep)
        case .ops(let ops):
            guard !ops.isEmpty else {
                if let refuse { return refuse(empty()) }
                return beep()
            }
            if inEvent, refuse == nil {
                document.applyEdit(command.name, ops)
            } else {
                document.performGroupedEdit(command.name, ops)
            }
        }
    }

    /// One beep and `reason` at the inspector's foot, as `command`'s tool.
    private static func say(
        _ reason: String, command: Command, document: ProjectDocument, beep: () -> Void
    ) {
        beep()
        NotificationCenter.default.post(
            name: .projectDocumentDidRefuse, object: document,
            userInfo: ["refusal": ReelRefusal(op: command.tool, reason: reason)])
    }

    /// Runs `run` at once when nothing renders, else under the sheet, and
    /// lands `answer` of its outcome through `land`. With `refuse` (a
    /// landing's follow) each beep is that refusal instead — `empty` says
    /// why nothing was planned — and the commit is grouped. `done` is called
    /// exactly once, after the last thing this call does: at each return
    /// below, and from whichever of the sheet's two hand-backs runs (#546).
    private static func measure<Run: AudioMeasureRunning>(
        _ command: Command, run: Run, document: ProjectDocument,
        window: NSWindow?, refuse: ((String) -> Void)? = nil,
        empty: ((Run.Outcome) -> String)? = nil, done: (() -> Void)? = nil,
        answer: @escaping (Run.Outcome) -> Answer
    ) {
        let stopped = "\(command.tool) was stopped while its sound was being measured."
        guard run.needsRender else {
            // No render: the run answers before `start` returns, inside the event.
            run.start { outcome in
                guard let outcome else { return fail(refuse, stopped) }
                land(
                    answer(outcome), command: command, document: document, inEvent: true,
                    refuse: refuse, empty: empty?(outcome) ?? stopped)
            }
            run.finish()
            done?()
            return
        }
        guard let window, window.attachedSheet == nil, let host = window.contentViewController
        else {
            run.finish()
            fail(refuse, "A sheet was already up on the project's window, so nothing changed.")
            done?()
            return
        }
        let asked = document.project
        let scope = document.scope
        host.presentAsSheet(
            AudioMeasureSheetController(run: run, title: sheetTitle, stopped: { done?() }) {
                [weak document] outcome in
                defer {
                    run.finish()
                    done?()
                }
                guard let document else { return }
                let stale = document.project !== asked || document.scope != scope
                land(
                    stale
                        ? .refused(staleReason(again: "Choose \(command.name) again."))
                        : answer(outcome),
                    command: command, document: document, inEvent: false, refuse: refuse,
                    empty: empty?(outcome) ?? stopped)
            })
    }

    /// The press beeps; a landing's follow says `reason` at the inspector's foot.
    private static func fail(_ refuse: ((String) -> Void)?, _ reason: String) {
        guard let refuse else { return NSSound.beep() }
        refuse(reason)
    }

    /// Inside the event: `applyEdit`, which beeps at an identity; an empty
    /// list beeps here.
    private static func commit(_ name: String, _ ops: [ReelOp], document: ProjectDocument) {
        guard !ops.isEmpty else { return NSSound.beep() }
        document.applyEdit(name, ops)
    }
}
