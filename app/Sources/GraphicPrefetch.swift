// app/Sources/GraphicPrefetch.swift — an export's graphics rasterized
// AHEAD of the compositor, on worker threads (spec §11 G-26, issue #127).
//
// **The compositor stays the one writer.** A worker runs a frame's graphic
// modules and rasterizes their SVG into a slot; the compositor still runs
// `svg` itself, records every warning and failure and draws every error card
// (G-8), and takes a slot's raster only on a pool miss and only when the
// worker's texture key equals its own (`LayerRenderersGraphic.swift`). So a
// worker can be wrong, late or absent and the file is still the serial
// path's, byte for byte.
//
// **Where it runs.** Only an `ExportWriter` export with a pinned set and a
// graphic in range (`Exporter.startGraphicPrefetch`); never GIF/APNG, a
// one-frame render or the preview. `ReelcutGraphicPrefetchOff` (YES) is the
// measurement switch back to the serial path.
//
// **The grid.** A worker walks `range.start + i × frameDuration` on the
// export's own key: the core snaps the start onto the export's own grid
// from 0, at the export's rate after any override, so those are the
// instants the writer asks the compositor for. A worker reads only through
// `RecipeSource.recipe(for:at:)` and `GraphicRegistry.resolve` — the
// export's PINNED set (G-13) — and never records a report.
//
// **One `NSCondition`** guards `sessions` and every session and entry field,
// broadcast on every change (`CacheLedger`'s precedent). A worker never
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
    static let offDefaultsKey = "ReelcutGraphicPrefetchOff"
    /// The rasters held ahead, at most.
    static let maxHeldBytes = 1 << 30
    /// Above `graphic::STACK_BYTES` (1 MiB).
    static let workerStackBytes = 8 << 20
    static var workerCount: Int { max(1, ProcessInfo.processInfo.activeProcessorCount - 1) }
    /// The slots held ahead, at most.
    static var slotLimit: Int { 4 * workerCount }

    /// One graphic layer's inputs — exactly what `LayerRenderers.graphic` is
    /// called with. Member order is load-bearing (`graphics_proof.py`'s
    /// `frame-plus-one` anchor in `LayerRenderersGraphic.swift`).
    struct Slot: Hashable {
        let name: String
        let frame: Int
        let width: Int
        let height: Int
        let propsJSON: String
        let ctxJSON: String
    }

    /// One slot's raster as a worker made it. Guarded by `condition`.
    private final class Entry {
        let index: Int
        var bytes: Int
        var done = false
        var textureKey: String?
        var raster: Result<GraphicRaster, any Error>?

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
        /// Texture key → the SMALLEST frame index whose entry rasterizes it,
        /// least recently touched first; the compositor pool's capacity.
        var recent: [(key: String, index: Int)] = []

        init(key: Int, range: CMTimeRange, frameDuration: CMTime, workerCount: Int) {
            self.key = key
            self.start = range.start
            self.frameDuration = frameDuration
            self.endTicks = CompositionBuilder.ticks(range.end)
            self.workerCount = workerCount
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

    private let condition = NSCondition()
    private var sessions: [Int: Session] = [:]

    private init() {}

    // MARK: - Main

    /// Starts `key`'s workers over `range` at `frameDuration`. A no-op when
    /// the switch is on, a session for `key` exists, or either is not
    /// positive.
    func start(key: Int, range: CMTimeRange, frameDuration: CMTime) {
        guard !UserDefaults.standard.bool(forKey: Self.offDefaultsKey),
            range.isValid, range.start.isNumeric, range.duration.isNumeric,
            frameDuration.isNumeric,
            CMTimeCompare(range.duration, .zero) > 0, CMTimeCompare(frameDuration, .zero) > 0
        else { return }
        let count = Self.workerCount
        condition.lock()
        guard sessions[key] == nil else {
            condition.unlock()
            return
        }
        let session = Session(
            key: key, range: range, frameDuration: frameDuration, workerCount: count)
        session.liveWorkers = count
        sessions[key] = session
        condition.unlock()
        for _ in 0..<count {
            let thread = Thread { [self] in self.work(session) }
            thread.stackSize = Self.workerStackBytes
            thread.qualityOfService = .userInitiated
            thread.name = "reelcut.graphic-prefetch"
            thread.start()
        }
    }

    /// Ends `key`'s session: its entries unused, its workers told. Any
    /// thread; idempotent; never waits.
    func stop(_ key: Int) {
        condition.lock()
        guard let session = sessions.removeValue(forKey: key) else {
            condition.unlock()
            return
        }
        session.stopped = true
        session.unused += session.slots.count
        for entry in session.slots.values { entry.bytes = 0 }
        session.slots.removeAll()
        session.heldBytes = 0
        condition.broadcast()
        let line = session.liveWorkers == 0 ? logLine(session) : nil
        condition.unlock()
        if let line = line { NSLog("%@", line) }
    }

    // MARK: - The compositor's queue

    /// The worker's raster for `slot` when its texture key is `textureKey`,
    /// else nil. Every entry of an earlier frame goes as unused. Waits for
    /// the entry's worker, or for `stop`.
    func take(_ key: Int, slot: Slot, textureKey: String) -> Result<GraphicRaster, any Error>? {
        condition.lock()
        defer { condition.unlock() }
        guard let session = sessions[key] else { return nil }
        guard let entry = session.slots[slot] else {
            session.missed += 1
            return nil
        }
        remove(slot, entry, from: session)
        condition.broadcast()
        while !entry.done, !session.stopped { condition.wait() }
        if entry.done, let raster = entry.raster, entry.textureKey == textureKey {
            session.hits += 1
            return raster
        }
        session.mismatched += 1
        return nil
    }

    /// `take`'s removal for a slot the pool answered: never waits.
    func discard(_ key: Int, slot: Slot) {
        condition.lock()
        defer { condition.unlock() }
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

    private func release(_ entry: Entry, from session: Session) {
        session.heldBytes -= entry.bytes
        entry.bytes = 0
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
        let line = session.liveWorkers == 0 && session.stopped ? logLine(session) : nil
        condition.broadcast()
        condition.unlock()
        if let line = line { NSLog("%@", line) }
    }

    /// The next frame index, once there is room; nil once stopped or
    /// exhausted.
    private func claim(_ session: Session) -> Int? {
        condition.lock()
        defer { condition.unlock() }
        while !session.stopped, !session.exhausted,
            session.slots.count >= Self.slotLimit || session.heldBytes >= Self.maxHeldBytes
        {
            condition.wait()
        }
        guard !session.stopped, !session.exhausted else { return nil }
        let index = session.next
        session.next += 1
        return index
    }

    /// Every absent slot of frame `index` inserted under ONE hold; nil once
    /// stopped.
    private func insert(
        _ wanted: [(slot: Slot, module: GraphicModule)], index: Int, into session: Session
    ) -> [Job]? {
        condition.lock()
        defer { condition.unlock() }
        guard !session.stopped else { return nil }
        session.framesWithGraphics += 1
        var jobs: [Job] = []
        for (slot, module) in wanted where session.slots[slot] == nil {
            let entry = Entry(index: index, bytes: slot.width * slot.height * 4)
            session.slots[slot] = entry
            session.heldBytes += entry.bytes
            jobs.append(Job(slot: slot, entry: entry, module: module))
        }
        if !jobs.isEmpty { condition.broadcast() }
        return jobs
    }

    /// Each job's SVG, key and raster, outside the lock; `stopped` checked
    /// between jobs, and the rest marked done.
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
                finish(job.entry, raster: nil)
                continue
            }
            let key = LayerRenderers.textureKey(
                svg: drawn.svg, width: slot.width, height: slot.height,
                libraryVersion: resolved.set.libraryVersion)
            condition.lock()
            job.entry.textureKey = key
            if let earlier = session.recentIndex(key), earlier < job.entry.index {
                session.touch(key)
                job.entry.done = true
                release(job.entry, from: session)
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
            finish(job.entry, raster: raster)
        }
    }

    private func finish(_ entry: Entry, raster: Result<GraphicRaster, any Error>?) {
        condition.lock()
        entry.raster = raster
        entry.done = true
        condition.broadcast()
        condition.unlock()
    }

    /// The session's one line, once. Under `condition`.
    private func logLine(_ session: Session) -> String? {
        guard !session.logged else { return nil }
        session.logged = true
        return "[reelcut] graphic prefetch: key \(session.key), \(session.workerCount) workers, "
            + "\(session.framesWithGraphics) frames with graphics, \(session.hits) hits, "
            + "\(session.mismatched) mismatched, \(session.missed) missed, "
            + "\(session.unused) unused"
    }
}
