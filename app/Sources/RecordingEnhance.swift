import AppKit

/// "Enhance the microphone when it lands" (road map "audio" AP6 part 3, spec
/// §11 AU-68, AU-69): Enhance Voice run over a finished recording's VOICE
/// clips as a follow-up to the landing — never part of it. The landing commits
/// at once and is unchanged (`RecordingLanding`, `untitled(around:)`, the step
/// names, the notes); Enhance follows as its own undo step, "Enhance Voice",
/// once the voice's loudness and speech caches exist, because neither can
/// exist before the media is in a project.
///
/// The values and the pure decision are here: which files are the voice
/// (`voicePaths`), which clips they became (`voiceClips`), whether those are
/// measured (`isAnalysed`) and whether the document is in a state to take an
/// edit (`isBusy`), and `decide`. The two doors share them: the panel through
/// `follow` — a repeating timer per landing, in the run loop's DEFAULT mode
/// (the landing's retry trick: a drag runs the loop in tracking mode, so the
/// timer waits for it) — and `record_screen {enhance}` through
/// `AgentServer.landAndEnhance`, which polls `decide` from the server thread.
///
/// **The follow ends before anything is shown.** On any step but `.wait` the
/// timer is invalidated and the landing's pending entry removed FIRST, then
/// the step acts (`tick`): Cancel on the Measuring Sound sheet, no outcome or
/// a stale answer can never leave a timer that puts the sheet back up, and
/// `isPending` never depends on the sheet.
///
/// **The measurement is held apart from the follow** (#546). `.enhance` ends
/// the follow and then measures, for seconds, under the Measuring Sound
/// sheet, which hands its answer back a main-queue turn after it has gone.
/// From that step until the answer, the refusal or the Cancel has landed the
/// document `isMeasuring` (`Measurement`), and `isUnderWay` is the follow or
/// the measurement: what the polish's follow waits on (CU-101 (a)), so it
/// cannot commit in the gap and make Enhance's answer stale, and what
/// `land_recording` waits on and answers as `enhance_pending`.
enum RecordingEnhance {
    /// One check every half second, the landing's own retry interval.
    static let checkInterval: TimeInterval = RecorderPanelController.landingRetryInterval
    /// Past this since the landing, a voice still unmeasured is given up on.
    static let waitLimit: TimeInterval = 300

    static let notReadyHead =
        "Enhance Voice did not run on the recording: its microphone was not ready to measure "
        + "within 5 minutes."
    static let notReadySentence = notReadyHead + " Select its clip and choose Clip ▸ Enhance Voice."
    /// The tool's `.giveUp` sentence: the same head, a tool's way out.
    static let notReadyToolSentence = notReadyHead + " Call enhance_voice with its clips."
    static let noVoiceSentence =
        "No microphone clip landed on the timeline, so there was nothing to enhance."
    /// The panel box's tooltip (AU-69 (a)), naming AU-68's step.
    static let boxTooltip =
        "After the recording lands, run Clip ▸ Enhance Voice on the microphone's clip as its own "
        + "undo step, \"Enhance Voice\", once its sound has been analyzed."

    /// What one check decides (AU-68 (d)).
    enum Step: Equatable {
        case wait
        case enhance([UInt32])
        case drop
        case giveUp
    }

    // MARK: - The voice

    /// The recording's voice files: each segment's microphone file, each
    /// left-out segment's readable microphone file, and for a voice-over each
    /// segment's own file — never the picture, the camera or the system audio.
    /// None without a microphone. Pure; empty paths dropped, each path once.
    static func voicePaths(of result: RecordingResult) -> [String] {
        guard result.choice.microphone != nil else { return [] }
        var paths = result.segments.compactMap { $0.micDescriptor?.path }
        paths += result.unreadable.compactMap { $0.micDescriptor?.path }
        if result.isVoiceOver { paths += result.segments.map { $0.descriptor.path } }
        var seen: Set<String> = []
        return paths.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Every clip in the open container whose media is one of the voice
    /// files, in clip-id order. Main, after the landing's commit.
    static func voiceClips(of result: RecordingResult, in document: ProjectDocument) -> [UInt32] {
        let paths = Set(voicePaths(of: result))
        guard !paths.isEmpty else { return [] }
        let snapshot = document.editedProject.snapshot
        return snapshot.clips.filter { clip in
            snapshot.media(for: clip).map { paths.contains($0.path) } ?? false
        }.map(\.id).sorted()
    }

    /// The landing's container: the nest `scope` names, or the top level (#458). A follow-up
    /// reads its clips here, never in the open container, so a nest opened during its wait is
    /// busy rather than a drop. The open container's own view when it is the landing's. Main.
    static func container(of document: ProjectDocument, scope: UInt32?) -> ReelProject {
        if document.scope == scope { return document.editedProject }
        return scope.flatMap { document.project.scoped($0) } ?? document.project
    }

    /// The clips still in the landing's container. Main.
    static func present(_ clips: [UInt32], in document: ProjectDocument, scope: UInt32?)
        -> [UInt32]
    {
        let snapshot = container(of: document, scope: scope).snapshot
        return clips.filter { snapshot.clip($0) != nil }
    }

    /// Each clip's media has a current loudness cache, and its speech saved,
    /// or a current speech cache, or no speech model at all (AU-68 (b)). False
    /// for no clips, a missing file or no cache folder. The clips are read in the landing's
    /// container. Main.
    static func isAnalysed(_ clips: [UInt32], in document: ProjectDocument, scope: UInt32?)
        -> Bool
    {
        guard !clips.isEmpty, let cacheDir = document.cacheDirectory else { return false }
        let snapshot = container(of: document, scope: scope).snapshot
        for id in clips {
            guard let clip = snapshot.clip(id), let media = snapshot.media(for: clip),
                let url = mediaURL(for: media)
            else { return false }
            let stamp = MediaImporter.CacheStamp.stamp(for: media, url: url)
            guard MediaImporter.loudnessIsCurrent(for: media, stamp: stamp, in: cacheDir) else {
                return false
            }
            guard media.speech != nil
                || MediaImporter.speechIsCurrent(for: media, stamp: stamp, in: cacheDir)
                || !SileroVAD.isAvailable
            else { return false }
        }
        return true
    }

    /// A drag in progress, or the open container is not the landing's. The
    /// panel adds its own window test in `tick`. Main.
    static func isBusy(_ document: ProjectDocument, scope: UInt32?) -> Bool {
        document.isLiveEditing || document.scope != scope
    }

    /// AU-68 (d), in this order. Pure.
    static func decide(clips: [UInt32], analysed: Bool, busy: Bool, elapsed: TimeInterval) -> Step {
        if clips.isEmpty { return .drop }
        if analysed && !busy { return .enhance(clips) }
        if elapsed >= waitLimit { return .giveUp }
        return .wait
    }

    // MARK: - The panel's follow

    /// One landing's follow: its document, its clips, the scope it landed in,
    /// when, and the timer.
    private final class Follow {
        weak var document: ProjectDocument?
        var clips: [UInt32]
        var scope: UInt32?
        var started: Date
        var timer: Timer?

        init(document: ProjectDocument, clips: [UInt32], scope: UInt32?) {
            self.document = document
            self.clips = clips
            self.scope = scope
            self.started = Date()
        }
    }

    /// The follows under way, by the document's `recipeKey` (never minted
    /// twice). A second landing into a document with a follow under way joins
    /// it: its clips are added and the clock and scope start again.
    private static var follows: [Int: Follow] = [:]

    /// The panel's landing hands its result here once it has committed. A
    /// no-op unless the choice asked for it. Main.
    static func follow(_ result: RecordingResult, in document: ProjectDocument) {
        guard result.choice.enhanceMicrophone else { return }
        let clips = voiceClips(of: result, in: document)
        let key = document.recipeKey
        if let pending = follows[key] {
            pending.clips = Array(Set(pending.clips + clips)).sorted()
            pending.scope = document.scope
            pending.started = Date()
            return
        }
        let follow = Follow(document: document, clips: clips, scope: document.scope)
        follows[key] = follow
        // `scheduledTimer` adds it in the DEFAULT mode: it waits out a drag.
        follow.timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) {
            [weak document] timer in
            guard let document else {
                timer.invalidate()
                follows[key] = nil
                return
            }
            tick(document)
        }
    }

    /// True only while a follow's timer runs for `document`. Main.
    static func isPending(_ document: ProjectDocument) -> Bool {
        follows[document.recipeKey] != nil
    }

    // MARK: - The measurement

    /// The measurements under way, counted by the document's `recipeKey`.
    private static var measuring: [Int: Int] = [:]

    /// One `.enhance` step's measurement: counted from its making until
    /// `end()`, once. Releasing it unended also uncounts it, so a hand-back
    /// that is dropped without being called cannot hold the polish. Made and
    /// ended on main.
    final class Measurement {
        private let key: Int
        private var ended = false

        init(_ document: ProjectDocument) {
            key = document.recipeKey
            RecordingEnhance.measuring[key, default: 0] += 1
        }

        func end() {
            guard !ended else { return }
            ended = true
            RecordingEnhance.uncount(key)
        }

        deinit {
            guard !ended else { return }
            let key = self.key
            if Thread.isMainThread {
                RecordingEnhance.uncount(key)
            } else {
                DispatchQueue.main.async { RecordingEnhance.uncount(key) }
            }
        }
    }

    private static func uncount(_ key: Int) {
        let left = (measuring[key] ?? 0) - 1
        measuring[key] = left > 0 ? left : nil
    }

    /// True from a follow's `.enhance` step until what it measured has
    /// landed: the step, a refusal, or the sheet's Cancel. Main.
    static func isMeasuring(_ document: ProjectDocument) -> Bool {
        measuring[document.recipeKey] != nil
    }

    /// The follow's timer runs, or its measurement has not landed yet: Enhance
    /// Voice may still step on `document`. Main.
    static func isUnderWay(_ document: ProjectDocument) -> Bool {
        isPending(document) || isMeasuring(document)
    }

    /// The timer of `document`'s follow, nil with none — what the probe reads
    /// back after a step (P5). Main.
    static func timer(of document: ProjectDocument) -> Timer? {
        follows[document.recipeKey]?.timer
    }

    /// One firing: decide, and on any step but `.wait` end the follow FIRST
    /// (the type doc), then act. `.enhance` holds a `Measurement` until
    /// `enhanceLanded` calls back. Main.
    static func tick(_ document: ProjectDocument) {
        guard let follow = follows[document.recipeKey] else { return }
        let clips = present(follow.clips, in: document, scope: follow.scope)
        let window = RecorderPanelController.editor(of: document)?.view.window
        let busy =
            isBusy(document, scope: follow.scope) || window == nil || window?.attachedSheet != nil
        let step = decide(
            clips: clips, analysed: isAnalysed(clips, in: document, scope: follow.scope),
            busy: busy,
            elapsed: Date().timeIntervalSince(follow.started))
        guard step != .wait else { return }
        end(follow, key: document.recipeKey)
        switch step {
        case .enhance(let ids):
            guard let window else { return refuse(notReadySentence, in: document) }
            let measurement = Measurement(document)
            AudioMeasureDoor.enhanceLanded(document: document, clips: ids, window: window) {
                measurement.end()
            }
        case .giveUp:
            refuse(notReadySentence, in: document)
        case .drop, .wait:
            break
        }
    }

    private static func end(_ follow: Follow, key: Int) {
        follow.timer?.invalidate()
        follows[key] = nil
    }

    /// A refusal of `enhance_voice` at the inspector's foot; no beep (AU-68 (e)).
    static func refuse(_ reason: String, in document: ProjectDocument) {
        NotificationCenter.default.post(
            name: .projectDocumentDidRefuse, object: document,
            userInfo: [
                "refusal": ReelRefusal(op: AudioMeasureDoor.Command.enhanceVoice.tool, reason: reason)
            ])
    }
}
