// app/Sources/GraphicPrefetch.swift — an export's graphics, and a playing
// preview's, rasterized AHEAD of the compositor, on worker threads (spec §11
// G-26, G-36 and G-37, issue #127).
//
// **The compositor stays the one writer.** A worker runs a frame's graphic
// modules and rasterizes their SVG into a slot; the compositor still runs
// `svg` itself, records every warning and failure and draws every error card
// (G-8), and takes a slot's raster only on a pool miss and only when the
// worker's texture key equals its own (`LayerRenderersGraphic.swift`). So a
// worker can be wrong, late or absent and the file is still the serial
// path's, byte for byte.
//
// **Where it runs.** An `ExportWriter` export with a pinned set and a
// graphic in range (`Exporter.startGraphicPrefetch`), and a preview playing
// forward over a project that draws a graphic, on the document's own key
// (`Playback+Prefetch.swift`, G-36); never GIF/APNG, a one-frame render or a
// paused or reversing preview. `FrameJobGraphicPrefetchOff` (YES) is the
// measurement switch back to the serial path for both.
//
// **The grid.** A worker walks `range.start + i × frameDuration` on the
// export's own key: the core snaps the start onto the export's own grid
// from 0, at the export's rate after any override, so those are the
// instants the writer asks the compositor for. A playback session's grid
// starts at the seek target or the playhead, snapped down onto the
// composition's own grid from 0. A worker reads only through
// `RecipeSource.recipe(for:at:)` and `GraphicRegistry.resolve` — the
// export's PINNED set (G-13), or the document's — and never records a report.
//
// **Following.** A playback session `follows`: the compositor reports every
// request's time (`reach`), a worker never claims a frame at or before the
// last one reached (the frames passed over are `skipped`), and a held entry
// of an earlier frame goes as unused. A request outside the session's range
// is not followed, and a seek's session follows nothing until a request
// lands in its first `armFrames` frames: a seek installs the session before
// AVFoundation cancels the old position's requests, and those still served
// in between must not move the new session's floor. An export session never reads `floor`,
// `skipped` or `deferred`, and its log line is unchanged; a following one's
// appends `, playback from <start>, <skipped> skipped, <kept> kept`.
//
// **Bounds (G-37).** Bytes decide how far ahead workers go: a worker waits
// while the held rasters of ALL sessions reach the one process-wide budget
// (a quarter of physical memory, less under memory pressure), or while its
// session holds `entryCeiling` entries, bytes or none. A playing document's
// key KEEPS the frames it drew (`GraphicPrefetch+Memory.swift`): a finished
// raster leaving its slot goes into the kept frames, `take` answers from them
// before any slot, and a worker skips a texture key already kept. The kept
// frames fill only the room the held rasters leave.
//
// **One `NSCondition`** guards `sessions`, the kept frames, every total and
// every session and entry field, broadcast on every change (`CacheLedger`'s
// precedent). A worker never
// waits while it holds an unfinished entry, so the compositor's `take`, the
// one wait on its queue, always ends: on `done` or on `stop`. Each worker is
// a Foundation `Thread` with a stack above the engine's own 1 MiB; its
// QuickJS engines die with it.

import CoreGraphics
import CoreMedia
import Foundation

final class GraphicPrefetch: @unchecked Sendable {
    static let shared = GraphicPrefetch()
    /// YES draws every graphic on the compositor's queue alone.
    static let offDefaultsKey = "FrameJobGraphicPrefetchOff"
    /// Above `graphic::STACK_BYTES` (1 MiB).
    static let workerStackBytes = 8 << 20
    static var workerCount: Int { max(1, ProcessInfo.processInfo.activeProcessorCount - 1) }
    /// The entries one session holds at most, bytes or none (G-37 (a)).
    static let entryCeiling = 1024

    /// One slot's raster as a worker made it. Guarded by `condition`.
    private final class Entry {
        let index: Int
        var bytes: Int
        var done = false
        /// Set by the worker's same-texture shortcut: the raster is left to
        /// the compositor's pool, from an earlier frame's entry.
        var deferred = false
        var textureKey: String?
        var raster: Result<GraphicRaster, any Error>?
        /// A pass's later layers deferred to this entry, and their top index.
        var sharers = 0, sharedUpTo = 0

        init(index: Int, bytes: Int) {
            self.index = index
            self.bytes = bytes
        }
    }

    /// One export's prefetch. Guarded by `condition`; its workers hold it
    /// after `stop` has removed it from `sessions`.
    private final class Session: @unchecked Sendable {
        let key: Int
        let start: CMTime
        let frameDuration: CMTime
        let endTicks: Ticks
        let workerCount: Int
        /// A playback session: `reach` raises `floor`, `claim` skips past it.
        let follows: Bool
        /// A paused document's pass into its kept frames (G-38).
        let background: Bool
        var drawn = 0, alreadyKept = 0, end = "done"
        let startTicks: Ticks
        let frameTicks: Ticks
        /// False for a seek's session until a request lands in its first
        /// `armFrames` frames; `reach` follows nothing before.
        var armed: Bool
        /// The last frame index the compositor reached; -1 before any.
        var floor = -1
        var skipped = 0
        var next = 0
        var exhausted = false
        var stopped = false
        var slots: [Slot: Entry] = [:]
        var heldBytes = 0
        var liveWorkers = 0
        var logged = false
        var framesWithGraphics = 0
        var hits = 0
        var mismatched = 0
        var missed = 0
        var unused = 0
        /// Requests the kept frames answered while this session ran.
        var kept = 0
        /// Texture key → the SMALLEST frame index whose entry rasterizes it,
        /// least recently touched first; the compositor pool's capacity.
        var recent: [(key: String, index: Int)] = []

        init(
            key: Int, range: CMTimeRange, frameDuration: CMTime, workerCount: Int, follows: Bool,
            seeking: Bool, background: Bool
        ) {
            self.key = key
            self.background = background
            self.start = range.start
            self.frameDuration = frameDuration
            self.endTicks = CompositionBuilder.ticks(range.end)
            self.workerCount = workerCount
            self.follows = follows
            self.armed = !seeking
            self.startTicks = CompositionBuilder.ticks(range.start)
            self.frameTicks = max(1, CompositionBuilder.ticks(frameDuration))
        }

        func recentIndex(_ key: String) -> Int? {
            recent.first { $0.key == key }?.index
        }

        /// `key` moved to the most recent end, at `index` when given.
        func touch(_ key: String, index: Int? = nil) {
            let kept = recentIndex(key)
            recent.removeAll { $0.key == key }
            guard let value = index ?? kept else { return }
            recent.append((key, value))
            if recent.count > LayerRenderers.graphicCacheLimit { recent.removeFirst() }
        }
    }

    let condition = NSCondition()
    private var sessions: [Int: Session] = [:]
    /// The kept frames and the keys that keep (G-37 (c)).
    var kept = KeptFrames()
    var keeping: Set<Int> = []
    /// The last pass's key and grid start, and its App Nap opt-out (G-38).
    var aheadOrigin: (key: Int, startTicks: Ticks)?
    var passActivity: NSObjectProtocol?
    /// The system's memory-pressure level, and the dev tool's simulated one.
    var pressure = MemoryPressure.normal
    var simulatedPressure: MemoryPressure?
    /// Every session's held rasters: bytes, entries holding bytes, and their
    /// peaks since the last report that reset them.
    var heldTotal = 0
    var heldEntries = 0
    var heldPeakBytes = 0
    var heldPeakEntries = 0
    /// Requests the kept frames answered.
    var keptHits = 0
    var pressureSource: DispatchSourceMemoryPressure?

    private init() {
        watchMemoryPressure()
    }

    // MARK: - Main

    /// Starts `key`'s workers over `range` at `frameDuration`: `follows` a
    /// play (G-36), `seeking` from a seek, `background` a paused pass (G-38;
    /// both main only). False, installing nothing, when the switch is on, `key`
    /// has a session, either is not positive, or (a pass) `key` does not keep
    /// or any session is a pass or follows.
    @discardableResult
    func start(
        key: Int, range: CMTimeRange, frameDuration: CMTime, follows: Bool = false,
        seeking: Bool = false, background: Bool = false
    ) -> Bool {
        guard !UserDefaults.standard.bool(forKey: Self.offDefaultsKey),
            range.isValid, range.start.isNumeric, range.duration.isNumeric,
            frameDuration.isNumeric,
            CMTimeCompare(range.duration, .zero) > 0, CMTimeCompare(frameDuration, .zero) > 0
        else { return false }
        if follows { stopBackground() }
        let count = Self.workerCount
        let startTicks = CompositionBuilder.ticks(range.start)
        condition.lock()
        let refused =
            background
            && (!keeping.contains(key) || sessions.values.contains { $0.background }
                || sessions.values.contains { $0.follows })
        guard sessions[key] == nil, !refused else {
            condition.unlock()
            return false
        }
        if background { beginAhead(key, startTicks: startTicks) }
        if follows { followAhead(key, startTicks: startTicks) }
        let session = Session(
            key: key, range: range, frameDuration: frameDuration, workerCount: count,
            follows: follows, seeking: seeking, background: background)
        session.liveWorkers = count
        sessions[key] = session
        condition.broadcast()
        condition.unlock()
        if background {
            NSLog("[framejob] graphic background: key %ld, from %lld, started", key, startTicks)
        }
        for _ in 0..<count {
            let thread = Thread { [self] in self.work(session) }
            thread.stackSize = Self.workerStackBytes
            thread.qualityOfService = background ? .utility : .userInitiated
            thread.name = "framejob.graphic-prefetch"
            thread.start()
        }
        return true
    }

    /// `stop(key)` for every background session, no other. Main only.
    func stopBackground() {
        condition.lock()
        let keys = sessions.values.filter(\.background).map(\.key)
        condition.unlock()
        for key in keys { stop(key) }
    }

    /// Ends `key`'s session: its entries unused (a keeping key's finished
    /// rasters kept), its workers told. Any thread; idempotent; never waits.
    /// A pass logs at once: nothing it draws after the stop is kept.
    func stop(_ key: Int) {
        condition.lock()
        guard let session = sessions.removeValue(forKey: key) else {
            condition.unlock()
            return
        }
        (session.stopped, session.end) = (true, session.exhausted ? session.end : "stopped")
        if session.follows { endAhead(key) }
        if session.background { endPassActivity() }
        session.unused += session.slots.count
        for entry in session.slots.values { release(entry, from: session) }
        session.slots.removeAll()
        condition.broadcast()
        let line = session.liveWorkers == 0 || session.background ? logLine(session) : nil
        condition.unlock()
        if let line = line { NSLog("%@", line) }
    }

    // MARK: - The compositor's queue

    /// A seek's session follows from the first request in this many of its
    /// first frames: the seek's own frame, or one just after it.
    static let armFrames = 4

    /// The compositor reached `ticks` on `key`. In a following session a
    /// request inside its range whose frame index is above `floor` raises
    /// it, and every entry of a frame BELOW it goes as unused — the floor
    /// frame's own entry is the one `take` is about to ask for. A seek's
    /// session (a loop's return included) follows nothing until a request
    /// lands in its first `armFrames` frames: until then a request may be
    /// the old position's, served before AVFoundation cancelled it. Any
    /// thread; a no-op unless `key`'s session follows.
    func reach(_ key: Int, ticks: Ticks) {
        condition.lock()
        defer { condition.unlock() }
        guard let session = sessions[key], session.follows,
            ticks >= session.startTicks, ticks < session.endTicks
        else { return }
        let index = Int(clamping: (ticks - session.startTicks) / session.frameTicks)
        if !session.armed {
            guard index < Self.armFrames else { return }
            session.armed = true
        }
        guard index > session.floor else { return }
        session.floor = index
        if aheadOrigin?.key == key { kept.clearAhead(below: index) }
        let passed = session.slots.filter { $0.value.index < index }
        for (slot, entry) in passed {
            session.slots[slot] = nil
            release(entry, from: session)
        }
        session.unused += passed.count
        condition.broadcast()
    }

    /// The worker's raster for `slot` when its texture key is `textureKey`,
    /// else nil. A keeping key's kept raster for `textureKey` answers first,
    /// session or none, and takes the slot out. Every entry of an earlier
    /// frame goes as unused. Waits for the entry's worker, or for `stop` — a
    /// wait `stop` ends counts as nothing. In a following session an entry
    /// the worker left to the pool counts `missed`: playback may have
    /// dropped the frame that filled it.
    func take(_ key: Int, slot: Slot, textureKey: String) -> Result<GraphicRaster, any Error>? {
        condition.lock()
        defer { condition.unlock() }
        if keeping.contains(key), let raster = kept.raster(key, textureKey) {
            if let session = sessions[key] {
                if let entry = session.slots[slot] {
                    remove(slot, entry, from: session)
                    condition.broadcast()
                }
                session.kept += 1
            }
            keptHits += 1
            return .success(raster)
        }
        guard let session = sessions[key] else { return nil }
        guard let entry = session.slots[slot] else {
            session.missed += 1
            return nil
        }
        remove(slot, entry, from: session)
        condition.broadcast()
        while !entry.done, !session.stopped { condition.wait() }
        guard entry.done else { return nil }
        if session.follows, entry.deferred, textureKey == entry.textureKey {
            session.missed += 1
            return nil
        }
        if entry.done, let raster = entry.raster, entry.textureKey == textureKey {
            session.hits += 1
            return raster
        }
        session.mismatched += 1
        return nil
    }

    /// `take`'s removal for a slot the pool answered: never waits. A keeping
    /// key's kept frame for `textureKey` is touched first, session or none.
    func discard(_ key: Int, slot: Slot, textureKey: String) {
        condition.lock()
        defer { condition.unlock() }
        if keeping.contains(key) { _ = kept.raster(key, textureKey) }
        guard let session = sessions[key], let entry = session.slots[slot] else { return }
        remove(slot, entry, from: session)
        session.unused += 1
        condition.broadcast()
    }

    /// `slot` and every entry of an earlier frame out of `session`, the
    /// earlier ones counted unused. Under `condition`.
    private func remove(_ slot: Slot, _ entry: Entry, from session: Session) {
        let earlier = session.slots.filter { $0.value.index < entry.index }
        for (old, value) in earlier {
            session.slots[old] = nil
            release(value, from: session)
        }
        session.unused += earlier.count
        session.slots[slot] = nil
        release(entry, from: session)
    }

    /// An entry's bytes out of the totals, once; a keeping key's finished
    /// raster then kept, room permitting (true when it is). Under `condition`.
    @discardableResult
    private func release(_ entry: Entry, from session: Session) -> Bool {
        guard entry.bytes > 0 else { return false }
        session.heldBytes -= entry.bytes
        heldTotal -= entry.bytes
        heldEntries -= 1
        entry.bytes = 0
        guard keeping.contains(session.key), entry.done,
            case .success(let raster)? = entry.raster, let textureKey = entry.textureKey,
            raster.bgra.count <= budgetBytes - heldTotal
        else { return false }
        kept.insert(session.key, textureKey, raster)
        kept.trim(toFit: budgetBytes - heldTotal)
        return kept.contains(session.key, textureKey)
    }

    // MARK: - Workers

    /// One graphic layer a worker will draw.
    private struct Job {
        let slot: Slot
        let entry: Entry
        let module: GraphicModule
    }

    private func work(_ session: Session) {
        while let index = claim(session) {
            let time = CMTimeAdd(
                session.start,
                CMTimeMultiply(session.frameDuration, multiplier: Int32(clamping: index)))
            let t = CompositionBuilder.ticks(time)
            if t >= session.endTicks {
                condition.lock()
                session.exhausted = true
                condition.broadcast()
                condition.unlock()
                break
            }
            guard let recipe = RecipeSource.shared.recipe(for: session.key, at: t),
                let resolved = GraphicRegistry.shared.resolve(session.key)
            else { continue }
            var wanted: [(slot: Slot, module: GraphicModule)] = []
            for layer in recipe.layers where layer.opacity > 0 {
                guard case .graphic(let name, _, let frame, let props, let ctx) = layer.source,
                    case .compiled(let module, _, _, _)? = resolved.set.modules[name]
                else { continue }
                let size = layer.sourceSizeCG ?? CGSize(width: 640, height: 360)
                let slot = Slot(
                    name: name, frame: frame, width: Int(size.width), height: Int(size.height),
                    propsJSON: props, ctxJSON: ctx)
                wanted.append((slot, module))
            }
            guard !wanted.isEmpty else { continue }
            guard let jobs = insert(wanted, index: index, into: session) else { break }
            draw(jobs, session: session, resolved: resolved)
        }
        condition.lock()
        session.liveWorkers -= 1
        let ends = session.liveWorkers == 0 && (session.stopped || session.background)
        if ends, sessions[session.key] === session { sessions[session.key] = nil }
        if ends, session.background, !session.stopped { endPassActivity() }
        let line = ends ? logLine(session) : nil
        condition.broadcast()
        condition.unlock()
        if let line = line { NSLog("%@", line) }
    }

    /// The next frame index, once the held rasters of every session are
    /// under the budget and this session under `entryCeiling` entries; nil
    /// once stopped or exhausted. A following session's never at or before
    /// `floor`, and from the last pass's key it also waits while the held
    /// and marked bytes reach the budget; a pass ends `full` there (G-38).
    private func claim(_ session: Session) -> Int? {
        condition.lock()
        defer { condition.unlock() }
        while !session.stopped, !session.exhausted {
            if session.background, kept.aheadBytes + heldTotal >= budgetBytes {
                (session.exhausted, session.end) = (true, "full")
                condition.broadcast()
                break
            }
            let waits =
                heldTotal >= budgetBytes || session.slots.count >= Self.entryCeiling
                || session.follows && aheadOrigin?.key == session.key
                    && heldTotal + kept.aheadBytes >= budgetBytes
            guard waits else { break }
            condition.wait()
        }
        guard !session.stopped, !session.exhausted else { return nil }
        if session.follows, session.next <= session.floor {
            session.skipped += session.floor + 1 - session.next
            session.next = session.floor + 1
        }
        let index = session.next
        session.next += 1
        return index
    }

    /// Every absent slot of frame `index` inserted under ONE hold, the totals
    /// and peaks raised and the kept frames trimmed to the room left; nil
    /// once stopped. A play from the last pass's key first waits for room
    /// beside the marked frames; a pass without room ends `full` (G-38).
    private func insert(
        _ wanted: [(slot: Slot, module: GraphicModule)], index: Int, into session: Session
    ) -> [Job]? {
        condition.lock()
        defer { condition.unlock() }
        let slots = wanted.map(\.slot)
        while session.follows, aheadOrigin?.key == session.key, !session.stopped,
            !roomAhead(for: slots) { condition.wait() }
        guard !session.stopped else { return nil }
        if session.background, !roomAhead(for: slots) {
            (session.exhausted, session.end) = (true, "full")
            return nil
        }
        session.framesWithGraphics += 1
        var jobs: [Job] = []
        for (slot, module) in wanted where session.slots[slot] == nil {
            let entry = Entry(index: index, bytes: slot.width * slot.height * 4)
            session.slots[slot] = entry
            session.heldBytes += entry.bytes
            heldTotal += entry.bytes
            if entry.bytes > 0 { heldEntries += 1 }
            jobs.append(Job(slot: slot, entry: entry, module: module))
        }
        heldPeakBytes = max(heldPeakBytes, heldTotal)
        heldPeakEntries = max(heldPeakEntries, heldEntries)
        kept.trim(toFit: budgetBytes - heldTotal)
        if !jobs.isEmpty { condition.broadcast() }
        return jobs
    }

    /// Each job's SVG, key and raster, outside the lock; `stopped` checked
    /// between jobs, and the rest marked done. A texture key an earlier
    /// frame's entry rasterizes, or the key keeps, is left to the compositor.
    private func draw(
        _ jobs: [Job], session: Session, resolved: (set: GraphicSet, budgetMs: Int)
    ) {
        for (position, job) in jobs.enumerated() {
            condition.lock()
            let stopped = session.stopped
            if stopped {
                for rest in jobs[position...] { rest.entry.done = true }
                condition.broadcast()
            }
            condition.unlock()
            if stopped { return }
            let slot = job.slot
            guard let drawn = try? job.module.svg(
                frame: slot.frame, propsJSON: slot.propsJSON, ctxJSON: slot.ctxJSON,
                budgetMs: resolved.budgetMs)
            else {
                finish(job, in: session, raster: nil)
                continue
            }
            let key = LayerRenderers.textureKey(
                svg: drawn.svg, width: slot.width, height: slot.height,
                libraryVersion: resolved.set.libraryVersion)
            condition.lock()
            job.entry.textureKey = key
            let keptAlready = keeping.contains(session.key) && kept.contains(session.key, key)
            if keptAlready || session.recentIndex(key).map({ $0 < job.entry.index }) == true {
                session.touch(key)
                job.entry.done = true
                job.entry.deferred = true
                release(job.entry, from: session)
                if session.background, !session.stopped {
                    if session.slots[job.slot] === job.entry { session.slots[job.slot] = nil }
                    if keptAlready, kept.raster(session.key, key) != nil {
                        kept.markAhead(session.key, key, index: job.entry.index)
                        session.alreadyKept += 1
                    } else if let first = session.slots.values.first(where: {
                        !$0.done && $0.textureKey == key && $0.index < job.entry.index
                    }) {
                        (first.sharers, first.sharedUpTo) =
                            (first.sharers + 1, max(first.sharedUpTo, job.entry.index))
                    }
                }
                condition.broadcast()
                condition.unlock()
                continue
            }
            session.touch(key, index: job.entry.index)
            condition.unlock()
            let raster = Result<GraphicRaster, any Error>(catching: {
                try resolved.set.library.rasterize(
                    drawn.svg, width: slot.width, height: slot.height)
            })
            finish(job, in: session, raster: raster)
        }
    }

    /// `job`'s raster in; a pass's entry leaves its slot, its raster kept and marked.
    private func finish(
        _ job: Job, in session: Session, raster: Result<GraphicRaster, any Error>?) {
        condition.lock()
        job.entry.raster = raster
        job.entry.done = true
        if session.background, !session.stopped {
            if session.slots[job.slot] === job.entry { session.slots[job.slot] = nil }
            if release(job.entry, from: session), let textureKey = job.entry.textureKey {
                let entry = job.entry
                kept.markAhead(session.key, textureKey, index: max(entry.index, entry.sharedUpTo))
                (session.drawn, session.alreadyKept) =
                    (session.drawn + 1, session.alreadyKept + entry.sharers)
            }
        }
        condition.broadcast()
        condition.unlock()
    }

    /// The session's one line, once. Under `condition`.
    private func logLine(_ session: Session) -> String? {
        guard !session.logged else { return nil }
        session.logged = true
        if session.background {
            return backgroundLine(
                key: session.key, workers: session.workerCount, start: session.startTicks,
                frames: session.framesWithGraphics, counts: (session.drawn, session.alreadyKept),
                end: session.end)
        }
        let line =
            "[framejob] graphic prefetch: key \(session.key), \(session.workerCount) workers, "
            + "\(session.framesWithGraphics) frames with graphics, \(session.hits) hits, "
            + "\(session.mismatched) mismatched, \(session.missed) missed, "
            + "\(session.unused) unused"
        guard session.follows else { return line }
        return line + ", playback from \(session.startTicks), \(session.skipped) skipped, "
            + "\(session.kept) kept"
    }
}
