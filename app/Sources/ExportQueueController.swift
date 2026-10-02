import Foundation

/// The export queue (road map 2's phase 7e): the exports a person has
/// confirmed but does not want to sit and watch, run one after another while
/// the editor stays live.
///
/// **There is no AppKit in this file, and that is the design rather than
/// tidiness.** A queue window can be checked by neither of this project's two
/// instruments: the offscreen harness renders an `EditorViewController` into a
/// window and nothing else, and MCP drives the app through tools — of which
/// this feature has none and must have none (below). What a proof CAN do is
/// compile a probe out of the whole of `app/Sources`
/// (`tools/proof/phase6_chrome.py`'s `build_probe`), make one of these,
/// enqueue two jobs, spin the main run loop until `isIdle` and read `jobs`
/// back — without an `NSWindow` ever being ordered front. So the job list and
/// its state machine live here, where a script can reach them, and
/// `ExportQueueWindowController.swift` is a READER of this and nothing else:
/// it holds no job, decides nothing, and closing it stops nothing.
/// `AudioNormalize.swift` and `CaptionLayout.swift` are the same split — the
/// arithmetic where a script can call it, the dialog around it — and phase 5's
/// level meter is the closest sibling, where the MODEL publishes a number
/// precisely so that a proof need not photograph a window.
///
/// **No MCP mirror is owed.** The rule is that every user-visible EDIT gets
/// one (spec §7.9); a queue edits no project, it writes files, and an agent can
/// already call `export` N times in sequence — which is exactly what this
/// does. `export` IS the mirror. Adding a tool so that a proof could exist
/// would be the proof deciding the product's API, which
/// `tools/proof/README.md` settled for the level meter and this phase
/// inherits.
///
/// **One job at a time, on the MAIN thread, a fresh `Exporter` for each.**
/// `Exporter.export`'s own doc says main-thread-only and one export at a time,
/// and it means both: it schedules a run-loop `Timer` — which must be
/// invalidated on the thread it was scheduled on — and calls its progress and
/// completion handlers on the main thread. So this is a CHAIN and not a pool:
/// `start()` runs the head of the list and each completion runs the next. A
/// `DispatchQueue` of exporters would be the wrong shape whatever the machine's
/// core count, and not only because of the timer — an `Exporter` carries
/// per-export state (`recipeKey`, `cancelRequested`, the loudness scratch
/// buffer), which is why each job gets its own rather than one being reset
/// between jobs. Every method below is main-thread-only for that reason, like
/// the exporter it drives.
///
/// **What a job holds is the whole of what it will write, captured when it was
/// confirmed.** The `ReelProject` is a handle and handles are immutable (spec
/// §5.5) — every edit and every undo makes a NEW one — so a queued write cannot
/// be reached by an edit made after it, and it needs no clone: `Exporter.export`
/// publishes it on a `RecipeSource` key it mints for itself, never the
/// document's, so even the frames the compositor serves this export come from
/// this handle. The document may be edited, undone or CLOSED while the job
/// waits; the handle is retained here and the Rust project behind it lives
/// until the job is gone.
///
/// **And the media URLs are resolved at ENQUEUE, which is what makes them part
/// of that same snapshot.** `ProjectDocument.mediaURLs()` resolves a bookmark
/// and asks the filesystem whether the file is there (`mediaURL(for:)`), so it
/// is a reading of the disk at the moment it is called: resolving at RUN time
/// would silently pick up a Relink… or a moved file from after the job was
/// queued, which is the exact change an immutable job exists to exclude. That
/// rule is structural here rather than remembered — `enqueue` takes a
/// `[UInt32: URL]` and a job holds no document, so there is nothing to ask
/// again later even if somebody wanted to.
///
/// **The REVERSE resolution is the third thing in that snapshot, and it was
/// missing.** Handle immutability covers the project and nothing beside it:
/// which clips play from a pre-rendered backwards file is a reading of the
/// disk too (`ProjectDocument.reverseState`, `ReverseCache.existing`), it
/// cannot be derived from a bare handle, and it lives in a side table keyed by
/// object IDENTITY — which the document overwrites on every edit and removes
/// when it closes. So a job queued from a timeline holding a reversed clip
/// used to answer `.none` the moment anything was edited, and `.none` means
/// "not reversed": the export took the forward asset at the mirrored source
/// window, unslated and unreported. It is captured here at enqueue, exactly as
/// the URLs are, and PINNED to this job's own handle for the length of its
/// write (`ReverseSource.pin`). Anything else the picture depends on that is
/// neither in the handle nor derivable from it joins that list.
final class ExportQueueController {
    /// The app's one queue: the export sheet's Add to Queue fills it and
    /// Window ▸ Export Queue shows it.
    static let shared = ExportQueueController()

    /// Where a job is. A closed set with no associated values, so the two
    /// readers ask it different questions without either having to spell a
    /// message: the window's row draws its own wording (which carries a
    /// percentage the state cannot know), and a probe compares the case and
    /// reads `Job.message` for the sentence. The raw values are the same
    /// strings a probe writes into its JSON answer.
    enum State: String {
        /// Queued and not started. The only state a job can be enqueued in.
        case waiting
        /// The one job an `Exporter` is running. At most one at any moment.
        case running
        /// The file landed.
        case completed
        /// Stopped by a person, either before it started or mid-write — in
        /// which case its half-written file has been removed.
        case cancelled
        /// The exporter refused or failed. Whatever it had written is LEFT on
        /// disk, which is `ExportProgressSheetController`'s posture and not a
        /// new one: a cancel is a person saying "not this", where a failure is
        /// evidence, and the file names itself in the message.
        case failed

        /// Whether the job is over, however it ended — the test for "may be
        /// removed from the list" and for "no longer holds a project handle
        /// worth keeping".
        var isFinished: Bool { self == .completed || self == .cancelled || self == .failed }
    }

    /// One confirmed export. Everything it needs was read when it was
    /// enqueued; see the type doc for why that is the whole point of it.
    struct Job {
        /// Monotonic within one launch. The window's rows and every method
        /// below address a job by this rather than by index, because a job can
        /// be removed from the middle of the list while a later one runs.
        let id: UInt64
        /// The timeline as it was confirmed — immutable, and retained here, so
        /// the document behind it may be edited, undone or closed.
        ///
        /// A FINISHED job goes on holding it, and that is a real cost stated
        /// rather than hidden: a handle is the project's model and not its
        /// media, so it is JSON-sized, and Clear Finished (or Remove) is what
        /// releases it along with the row that says where the file went.
        /// Dropping the handle at the finish would buy those bytes back and
        /// cost the field its `let` — an immutable job whose contents change
        /// once is a harder thing to reason about than a list somebody tidies.
        let project: ReelProject
        /// The media files as they resolved AT ENQUEUE.
        let urls: [UInt32: URL]
        /// Which of this timeline's clips play from a pre-rendered backwards
        /// file, as that resolved AT ENQUEUE — the type doc's third piece of
        /// the snapshot. Read from `ReverseSource` here and published back to
        /// it under this job's own handle while the job runs, because the
        /// document's copy is overwritten by the next edit and dropped when it
        /// closes.
        let reverse: ReverseResolution
        let settings: ExportSettings
        let destination: URL
        /// What this export asks of the PICTURE besides the timeline — the
        /// burn-in (`RecipeOptions`). Carried per job, because two jobs from
        /// one document may legitimately differ in it.
        let options: RecipeOptions
        /// The document's compiled graphics as they stood AT ENQUEUE (G-13) —
        /// the type doc's list again: a module saved after Add to Queue is not
        /// in the handle, and the document's set is swapped by that save and
        /// dropped when it closes. `Exporter.export` pins it for the write.
        let graphics: GraphicSet?
        var state: State = .waiting
        /// 0…1, and only meaningful while `state` is `.running`.
        var progress: Double = 0
        /// The line a person reads when it is over: what was written and what
        /// the file measured, or why it stopped — plus the one thing worth
        /// saying mid-flight, that a cancel is in hand. nil while it waits.
        var message: String?
        /// What the exporter says it is doing right now, or nil for "writing",
        /// which is the caller's own wording. Today the only phase is the
        /// loudness measurement, which on an audio-only export is half the wait
        /// and the half where nothing is on disk yet.
        ///
        /// A field of its own rather than a use of `message`, because the two
        /// are written by different things at the same time: the progress tick
        /// arrives ten times a second and would otherwise wipe the "Stopping…"
        /// a person had just asked for.
        var phase: String?
        /// Set on a COMPLETED job when a later job starts writing to the same
        /// path, because from that moment this row's file is not this row's
        /// any more — `Exporter.startWriting` removes whatever is at the
        /// destination before it builds its pipeline, so the earlier export is
        /// gone whether the later one succeeds, fails or is cancelled.
        ///
        /// The row stops claiming "Exported …" and stops offering Show in
        /// Finder. It is a fact about what happened rather than a state: the
        /// job really did complete, and rewriting its `state` would lose that.
        ///
        /// One case marks it where the file in fact survives, and it is the
        /// honest direction of the two: a later job whose COMPOSITION fails to
        /// build returns before the delete, so nothing was destroyed. It is
        /// left alone rather than reached for, because knowing which failures
        /// precede the delete means reading `Exporter`'s stages from here, and
        /// a shared destination implies a shared project — a build that failed
        /// for job 2 would almost always have failed for job 1.
        var superseded: Bool = false
        /// What the graphics warned while a COMPLETED job's file was drawn
        /// (G-24 (c)): the row's count and its tooltip's list.
        var graphicWarnings: [ExportGraphicWarning] = []

        /// What the row calls this job. The file name and not the path: the
        /// row is narrow, and the full path is the tooltip's job.
        var name: String { destination.lastPathComponent }
    }

    /// Posted after any change to `jobs` — an enqueue, a progress tick, a
    /// finish, a cancel, a removal — with the controller as the `object`, so
    /// an observer of the shared queue is never woken by a probe's own
    /// instance. Main thread, like everything else here.
    static let didChangeNotification = Notification.Name(
        "com.kgalligan.reelcut.exportQueueDidChange")

    /// Every job this launch still knows about, in the order they were added.
    /// A finished one stays until it is removed, because "it is done and here
    /// is where it went" is the queue's other job.
    private(set) var jobs: [Job] = []

    /// The exporter running `runningID`'s job, and nil whenever nothing is
    /// running. Set and cleared together with the job's state, so `isIdle` can
    /// be answered from `jobs` alone.
    private var exporter: Exporter?

    /// The handle whose reverse resolution is pinned in `ReverseSource` right
    /// now — the running job's, and nil whenever nothing is running. Held
    /// separately from the job so that `launch` and `finished` are provably one
    /// pin and one release, whatever happens to the list in between.
    private var pinnedProject: ReelProject?

    /// True only while `start()` is inside `Exporter.export`. An early refusal
    /// — `noPlan`, `emptyTimeline` — completes SYNCHRONOUSLY, so `finished`
    /// can run before `export` has returned; without this flag the next job
    /// would be launched from inside the previous one's stack frame and a
    /// queue of refusals would recurse as deep as it is long. With it, a
    /// re-entrant `start()` is refused and the frame already on the stack
    /// picks the next job up in its own loop.
    private var isLaunching = false

    private var nextID: UInt64 = 1

    /// Internal rather than private, and deliberately: a proof compiles a
    /// probe out of `app/Sources` and makes its OWN queue, so that running two
    /// jobs in a script cannot disturb — or be disturbed by — the app's shared
    /// one. It is the same reason `ExportPresetsStore` is a value a test can
    /// make.
    init() {}

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ExportQueueController does not support NSCoder")
    }

    // MARK: - Asking

    /// Nothing waiting and nothing running. The queue's own "are we there
    /// yet", and what a probe spins the run loop until.
    ///
    /// Answered from `jobs` rather than from `exporter`, so it means the same
    /// thing to a caller that cannot see the private state.
    var isIdle: Bool {
        !jobs.contains { $0.state == .waiting || $0.state == .running }
    }

    /// The job an exporter is writing right now, if any.
    var runningJob: Job? { jobs.first { $0.state == .running } }

    /// How many are still queued behind it.
    var waitingCount: Int { jobs.filter { $0.state == .waiting }.count }

    func job(_ id: UInt64) -> Job? { jobs.first { $0.id == id } }

    // MARK: - Filling

    /// Adds one confirmed export and starts the queue if it is not already
    /// running. Answers the job's id, so a caller can follow it.
    ///
    /// The arguments are `Exporter.export`'s, and that is not a coincidence:
    /// a job is exactly the call that will be made, held until its turn. Both
    /// `project` and `urls` are read by the CALLER, at the moment the save
    /// panel answered (`EditorViewController.enqueueExport`), which is what
    /// the type doc means by capturing at enqueue.
    ///
    /// **Two jobs may name one file, and the queue still does not refuse it —
    /// but it no longer pretends the person was warned.** The reason first
    /// given here was that "the save panel asked about replacing an existing
    /// file both times", and that is false in exactly the case that matters:
    /// `NSSavePanel` prompts only when something is at the path as Save is
    /// confirmed, and job 1 spends its build and its whole loudness
    /// measurement pass with nothing at the destination — `Exporter.export`
    /// does both before `startWriting` deletes and `AVAssetWriter` creates —
    /// so two Add to Queue actions in quick succession are never asked
    /// anything. Refusing here would still be wrong: overwriting your own
    /// export is a thing a person is allowed to do, and the queue must not be
    /// the one place in the app where they may not. What was wrong was the
    /// silence AFTERWARDS, and `launch` is where that is answered — the
    /// earlier row is marked `superseded` the moment a later job starts
    /// writing to its path, so no row goes on offering a file that another
    /// job has since deleted or replaced.
    @discardableResult
    func enqueue(
        project: ReelProject, urls: [UInt32: URL], settings: ExportSettings, to url: URL,
        options: RecipeOptions = .none, graphics: GraphicSet? = nil
    ) -> UInt64 {
        let id = nextID
        nextID += 1
        jobs.append(
            Job(
                id: id, project: project, urls: urls,
                // The third piece of the enqueue-time snapshot; the type doc
                // says why it cannot be left to be asked again at run time.
                reverse: ReverseSource.shared.resolution(publishedFor: project),
                settings: settings, destination: url, options: options, graphics: graphics))
        didChange()
        start()
        return id
    }

    // MARK: - Running

    /// Runs the first waiting job, if nothing is running already. Idempotent
    /// and safe to call at any time: `enqueue` calls it, every completion
    /// calls it, and a caller may call it itself.
    ///
    /// The loop is for the synchronous-refusal case `isLaunching` describes: a
    /// job the exporter refuses without ever going asynchronous has already
    /// finished by the time `launch` returns, and this frame takes the next
    /// one rather than recursing into it.
    func start() {
        guard !isLaunching else { return }
        isLaunching = true
        defer { isLaunching = false }
        while exporter == nil, let index = jobs.firstIndex(where: { $0.state == .waiting }) {
            launch(at: index)
        }
    }

    /// One job handed to one fresh `Exporter`. The exporter is stored BEFORE
    /// the call, because an early refusal calls back before `export` returns
    /// and `finished` has to find it there.
    private func launch(at index: Int) {
        let job = jobs[index]
        jobs[index].state = .running
        jobs[index].progress = 0
        jobs[index].message = nil
        jobs[index].phase = nil
        // Any COMPLETED row naming this same path stops claiming its file
        // here, and here rather than when the file is actually deleted: the
        // delete happens inside `Exporter.startWriting`, seconds later and in
        // a file this one may not reach into, and being early is the honest
        // direction — a row that stops offering a file just before it is
        // destroyed costs a person nothing, where one that offers it just
        // after sends them to the Finder for something that is gone.
        for other in jobs.indices
        where other != index && jobs[other].state == .completed
            && jobs[other].destination == job.destination
        {
            jobs[other].superseded = true
        }
        // The job's own reverse resolution, held against its own handle for
        // exactly the length of this write. At most one pin exists at a time,
        // which is the invariant `ReverseSource.pin` asks its callers for and
        // which this class keeps for free by running one job at a time.
        ReverseSource.shared.pin(job.reverse, for: job.project)
        pinnedProject = job.project
        let exporter = Exporter()
        self.exporter = exporter
        didChange()
        exporter.export(
            project: job.project, urls: job.urls, settings: job.settings, to: job.destination,
            options: job.options, graphics: job.graphics,
            progress: { [weak self] value in self?.progressed(job.id, value) },
            completion: { [weak self] result in self?.finished(job.id, result) })
    }

    private func progressed(_ id: UInt64, _ value: Double) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
            jobs[index].state == .running
        else { return }
        jobs[index].progress = min(max(value, 0), 1)
        // The exporter names its own phase while it has one. The progress
        // sheet asks the same question with the same call; a row that said
        // "Writing" through the measurement would be claiming a file that does
        // not exist yet.
        jobs[index].phase = exporter?.phaseDescription
        didChange()
    }

    /// The one exit for all three outcomes, and the mirror of
    /// `ExportProgressSheetController.finished` — deliberately, because there
    /// must not be two accounts of what finishing an export means. The
    /// exporter is cleared first, so the `start()` at the foot can hand the
    /// next job a fresh one.
    private func finished(_ id: UInt64, _ result: Result<URL, any Error>) {
        // Read BEFORE the exporter is dropped: `Exporter.finish` publishes the
        // measurement and then calls this, so the report is there now and only
        // now.
        let measured = exporter?.loudnessReport.map { " \($0.summary)." } ?? ""
        let warnings = exporter?.graphicWarnings ?? []
        exporter = nil
        // The pin goes with the exporter, and from `pinnedProject` rather than
        // from the job, so that releasing it cannot depend on the job still
        // being in the list. Exactly one release per `launch`, which is what
        // `ReverseSource.pin` asks for; a pin left behind would retain the
        // Rust project for the life of the process.
        if let pinned = pinnedProject {
            ReverseSource.shared.unpin(pinned)
            pinnedProject = nil
        }
        if let index = jobs.firstIndex(where: { $0.id == id }) {
            jobs[index].phase = nil
            switch result {
            case .success(let url):
                jobs[index].state = .completed
                jobs[index].progress = 1
                jobs[index].graphicWarnings = warnings
                // The count BEFORE the loudness figures: the row truncates
                // its tail (`ExportQueueRowView`).
                jobs[index].message = "Exported “\(url.lastPathComponent)”."
                    + Exporter.graphicWarningSuffix(warnings, hover: false) + measured
            case .failure(let error):
                if case Exporter.ExportError.cancelled = error {
                    // A cancelled job leaves nothing behind, and this line is
                    // DEFENCE IN DEPTH rather than the thing that achieves it
                    // — measured, because the obvious reading is wrong and a
                    // reader who believes it would be relying on a guarantee
                    // this line does not provide. Both pipelines already
                    // clean up after themselves: `AVAssetWriter.cancelWriting()`
                    // removes its own part-file (`ExporterWriter.swift` says
                    // so where it calls it) and `ImageSequenceWriter.report`
                    // removes its own. Deleting this line changes no observable
                    // outcome — phase 7's proof mutated it away and scored
                    // 77/77 — so the check beside it is written as the OUTCOME
                    // ("nothing is left behind") and not as a guard on this
                    // call. Keep it: it costs nothing, it states the policy
                    // where the policy is decided, and it is what holds if a
                    // third pipeline ever arrives that is less tidy.
                    // `ExportProgressSheetController.finished` is the same line
                    // for the same reason.
                    try? FileManager.default.removeItem(at: jobs[index].destination)
                    jobs[index].state = .cancelled
                    jobs[index].progress = 0
                    jobs[index].message = "Cancelled."
                } else {
                    jobs[index].state = .failed
                    jobs[index].progress = 0
                    jobs[index].message = error.localizedDescription
                }
            }
        }
        didChange()
        start()
    }

    // MARK: - Stopping and tidying

    /// Stops one job, whether it has started or not.
    ///
    /// A WAITING job is simply marked: it has no exporter to stop and no file
    /// to remove, because nothing has been written under its name. A RUNNING
    /// one is asked to stop and answers through `finished`, which is where its
    /// file is removed — one exit, so a cancel from the window and a cancel
    /// from a script clean up identically. A finished job is left alone.
    func cancel(_ id: UInt64) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        switch jobs[index].state {
        case .waiting:
            jobs[index].state = .cancelled
            jobs[index].message = "Cancelled before it started."
            didChange()
        case .running:
            jobs[index].message = "Stopping…"
            exporter?.cancel()
            didChange()
        case .completed, .cancelled, .failed:
            break
        }
    }

    /// Stops everything. The WAITING jobs go first and the running one last,
    /// and the order is load-bearing: cancelling the running job posts its
    /// completion, and a completion starts the next waiting job — so stopping
    /// the writer first would start the very jobs this is meant to stop.
    func cancelAll() {
        for job in jobs where job.state == .waiting { cancel(job.id) }
        if let running = runningJob { cancel(running.id) }
    }

    /// Drops one finished row. A job still waiting or running is not removed —
    /// cancel it first, which is what the window's one button does in its two
    /// states.
    func remove(_ id: UInt64) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
            jobs[index].state.isFinished
        else { return }
        jobs.remove(at: index)
        didChange()
    }

    /// Drops every finished row and leaves the queue itself running.
    func clearFinished() {
        let before = jobs.count
        jobs.removeAll { $0.state.isFinished }
        if jobs.count != before { didChange() }
    }

    private func didChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
