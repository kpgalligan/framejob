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
                AudioNormalize.plan($0.input, targetLUFS: target, solved: $0.solved).ops
            }
        case .enhanceVoice:
            guard let input = AudioEnhance.read(from: document, clips: clips) else {
                return NSSound.beep()
            }
            let target = NormalizeChoice.targetLUFS
            let choices = AudioEnhance.choose(input)
            let run = LoudnessMeasureRun(
                document: document, jobs: AudioEnhance.jobs(input, choices),
                problems: input.problems, targetLUFS: target)
            measure(command, run: run, document: document, window: window) {
                AudioEnhance.plan(input, choices: choices, outcome: $0, targetLUFS: target).ops
            }
        case .matchAudio:
            // Its reference comes from the Match Audio sheet: `pressMatch`.
            NSSound.beep()
        }
    }

    /// Match Audio's press (road map "audio" AP12, spec §11 AU-121, AU-128),
    /// from the Match Audio sheet's hand-back: `reference` and the other
    /// clips, read, then always measured under the Measuring Sound sheet (the
    /// reference renders), its plan committed by `measure`'s stale test. A
    /// refusal — the reference's, or nothing to match — beeps and puts its
    /// sentence at the inspector's foot, before the sheet or after it.
    static func pressMatch(
        document: ProjectDocument, reference: UInt32, clips: [UInt32], loudness: Bool, eq: Bool,
        window: NSWindow?
    ) {
        guard loudness || eq, !clips.isEmpty else { return NSSound.beep() }
        let input: AudioMatch.Input
        switch AudioMatch.read(
            from: document, reference: reference, clips: clips, loudness: loudness, eq: eq)
        {
        case .failure(let refusal): return refuse(refusal.sentence, document: document)
        case .success(let read): input = read
        }
        let run = AudioMatchRun(document: document, input: input)
        measure(.matchAudio, run: run, document: document, window: window) { [weak document] in
            if let refusal = $0.refusal {
                if let document { refuse(refusal.sentence, document: document) }
                return []
            }
            let plan = AudioMatch.plan(input, outcome: $0)
            guard !plan.matched.isEmpty else {
                // Every target skipped after the renders: the tool's sentence.
                if let document {
                    refuse(AudioMatch.nothingMatched(plan.skipped), document: document)
                }
                return []
            }
            return plan.ops
        }
    }

    /// A beep and `reason` at the inspector's foot.
    private static func refuse(_ reason: String, document: ProjectDocument) {
        NSSound.beep()
        NotificationCenter.default.post(
            name: .projectDocumentDidRefuse, object: document,
            userInfo: ["refusal": ReelRefusal(op: Command.matchAudio.tool, reason: reason)])
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

    /// Runs `run` at once when nothing renders, else under the sheet, and
    /// commits `ops` of its outcome.
    private static func measure<Run: AudioMeasureRunning>(
        _ command: Command, run: Run, document: ProjectDocument,
        window: NSWindow?, ops: @escaping (Run.Outcome) -> [ReelOp]
    ) {
        guard run.needsRender else {
            // No render: the run answers before `start` returns, inside the event.
            run.start { outcome in
                guard let outcome else { return NSSound.beep() }
                commit(command.name, ops(outcome), document: document)
            }
            run.finish()
            return
        }
        guard let window, window.attachedSheet == nil, let host = window.contentViewController
        else {
            run.finish()
            return NSSound.beep()
        }
        let asked = document.project
        let scope = document.scope
        host.presentAsSheet(
            AudioMeasureSheetController(run: run, title: sheetTitle) { [weak document] outcome in
                defer { run.finish() }
                guard let document else { return }
                guard document.project === asked, document.scope == scope else {
                    NSSound.beep()
                    NotificationCenter.default.post(
                        name: .projectDocumentDidRefuse, object: document,
                        userInfo: [
                            "refusal": ReelRefusal(
                                op: command.tool,
                                reason: staleReason(again: "Choose \(command.name) again."))
                        ])
                    return
                }
                let planned = ops(outcome)
                guard !planned.isEmpty else { return NSSound.beep() }
                document.performGroupedEdit(command.name, planned)
            })
    }

    /// Inside the event: `applyEdit`, which beeps at an identity; an empty
    /// list beeps here.
    private static func commit(_ name: String, _ ops: [ReelOp], document: ProjectDocument) {
        guard !ops.isEmpty else { return NSSound.beep() }
        document.applyEdit(name, ops)
    }
}
