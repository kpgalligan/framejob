// app/Sources/GraphicPrefetch+Memory.swift — the graphic rasters' one memory
// budget and the frames a document keeps (spec §11 G-37, issue #127).
//
// **One budget for the process.** A quarter of physical memory covers every
// session's held rasters (export and playback) and the kept frames. A worker
// waits while the held rasters of all sessions reach it (`claim`); the kept
// frames give way, least recently used first, and never exceed the room the
// held rasters leave: every change to either trims them to
// `max(0, budget − held)`. Frames a background pass drew ahead (G-38) are
// marked and give way last. Memory pressure halves the budget (warning) or
// sets it to 0 (critical: nothing is kept and no worker claims).
//
// **Kept frames.** Only a `Playback`'s key keeps (`beginKeeping` in its
// `init`): each raster the compositor used, and each finished raster a worker
// made for that key when it leaves its slot, under its texture key. A raster
// is a function of its texture key (the SVG text, the size and the library's
// content hash), so a kept raster is the serial path's (G-26 (c)).
// `FrameJobGraphicKeepOff` (YES) keeps nothing.
//
// Everything here is guarded by `GraphicPrefetch.condition`; `KeptFrames`
// never locks.

import Foundation

/// The system's memory-pressure level, and the budget it allows.
enum MemoryPressure: String, CaseIterable {
    case normal, warning, critical
}

extension MemoryPressure {
    /// A quarter of `physical` at normal, an eighth at warning, 0 at critical.
    func budget(physical: UInt64) -> Int {
        switch self {
        case .normal: return Int(clamping: physical / 4)
        case .warning: return Int(clamping: physical / 8)
        case .critical: return 0
        }
    }
}

/// The kept graphic rasters of every keeping key, least recently used first
/// out. Under `GraphicPrefetch.condition` only; never locks.
struct KeptFrames {
    private struct Name: Hashable {
        let key: Int
        let textureKey: String
    }

    private struct Frame {
        let name: Name
        let raster: GraphicRaster
        var stamp: Int
    }

    private var frames: [Name: Frame] = [:]
    /// Marked frame → the highest background frame index it serves (G-38).
    private var ahead: [Name: Int] = [:]
    /// Σ bytes of the marked frames.
    private(set) var aheadBytes = 0
    /// Marked frames `trim` pushed out while still marked, since the last
    /// report that reset it (`graphic_memory`'s `ahead_evicted`, G-38 (d)).
    var aheadEvicted = 0
    /// Every touch in order, oldest first from `head`; an element whose stamp
    /// is no longer its frame's is stale and skipped.
    private var order: [(name: Name, stamp: Int)] = []
    private var head = 0
    private var clock = 0
    /// Σ raster.bgra.count over the kept frames.
    private(set) var bytes = 0

    var count: Int { frames.count }

    func contains(_ key: Int, _ textureKey: String) -> Bool {
        frames[Name(key: key, textureKey: textureKey)] != nil
    }

    /// `key`'s raster for `textureKey`, touched; nil when none is kept.
    mutating func raster(_ key: Int, _ textureKey: String) -> GraphicRaster? {
        guard let frame = frames[Name(key: key, textureKey: textureKey)] else { return nil }
        touch(frame.name)
        return frame.raster
    }

    /// Keeps `raster` under `key` and `textureKey`; one already kept is only
    /// touched.
    mutating func insert(_ key: Int, _ textureKey: String, _ raster: GraphicRaster) {
        let name = Name(key: key, textureKey: textureKey)
        if frames[name] != nil {
            touch(name)
            return
        }
        clock += 1
        frames[name] = Frame(name: name, raster: raster, stamp: clock)
        order.append((name, clock))
        bytes += raster.bgra.count
    }

    /// Out until `bytes <= max(0, room)`: unmarked frames least recently used
    /// first, marked ones only after no unmarked frame is left (G-38 (d)).
    mutating func trim(toFit room: Int) {
        let limit = max(0, room)
        var index = head
        while bytes > limit, index < order.count {
            let (name, stamp) = order[index]
            index += 1
            guard let one = frames[name], one.stamp == stamp, ahead[name] == nil else { continue }
            trimOut(name)
        }
        while bytes > limit, head < order.count {
            let (name, stamp) = order[head]
            head += 1
            guard let frame = frames[name], frame.stamp == stamp else { continue }
            trimOut(name)
        }
        compact()
    }

    /// `trim`'s eviction: a marked frame counted in `aheadEvicted`.
    private mutating func trimOut(_ name: Name) {
        if ahead[name] != nil { aheadEvicted += 1 }
        evict(name)
    }

    /// Every frame of `key` out.
    mutating func drop(_ key: Int) {
        let gone = frames.keys.filter { $0.key == key }
        for name in gone { evict(name) }
        compact()
    }

    /// Marks `key`'s kept frame for `textureKey` as drawn ahead, serving
    /// background frame `index`; the higher index stays. A kept frame only.
    mutating func markAhead(_ key: Int, _ textureKey: String, index: Int) {
        let name = Name(key: key, textureKey: textureKey)
        guard let frame = frames[name] else { return }
        if let old = ahead[name] {
            ahead[name] = max(old, index)
        } else {
            ahead[name] = index
            aheadBytes += frame.raster.bgra.count
        }
    }

    /// The marks whose index is below `index` out: the compositor passed them.
    mutating func clearAhead(below index: Int) {
        let passed = ahead.filter { $0.value < index }.map(\.key)
        for name in passed {
            ahead[name] = nil
            if let frame = frames[name] { aheadBytes -= frame.raster.bgra.count }
        }
    }

    /// Every mark out.
    mutating func clearAhead() {
        ahead.removeAll()
        aheadBytes = 0
    }

    /// `name`'s frame out, and its mark with it.
    private mutating func evict(_ name: Name) {
        guard let frame = frames.removeValue(forKey: name) else { return }
        bytes -= frame.raster.bgra.count
        if ahead.removeValue(forKey: name) != nil { aheadBytes -= frame.raster.bgra.count }
    }

    private mutating func touch(_ name: Name) {
        clock += 1
        frames[name]?.stamp = clock
        order.append((name, clock))
        compact()
    }

    /// The stale touches out once they outnumber the frames.
    private mutating func compact() {
        if frames.isEmpty {
            order.removeAll()
            head = 0
            return
        }
        guard order.count - head > 2 * frames.count + 64 else { return }
        order = order[head...].filter { frames[$0.name]?.stamp == $0.stamp }
        head = 0
    }
}

/// `graphic_memory`'s answer (G-37).
struct GraphicMemoryReport: Equatable {
    let physicalBytes, budgetBytes: Int
    let pressure: MemoryPressure
    let heldBytes, heldPeakBytes, heldPeakEntries, keptBytes, keptFrames, keptHits: Int
    /// The marked frames' bytes now, the marked frames a trim pushed out
    /// since the last report that reset the peaks, and whether a pass holds
    /// its App Nap opt-out (G-38 (d), (c)).
    let aheadBytes, aheadEvicted: Int
    let passActivity: Bool
}

extension GraphicPrefetch {
    /// YES: nothing is kept (a measurement switch, independent of
    /// `offDefaultsKey`).
    static let keepOffDefaultsKey = "FrameJobGraphicKeepOff"
    static let physicalBytes = ProcessInfo.processInfo.physicalMemory

    /// The budget at the level in force: the simulated one when set, else the
    /// system's. Under `condition`.
    var budgetBytes: Int { (simulatedPressure ?? pressure).budget(physical: Self.physicalBytes) }

    /// `key` keeps the frames it draws from now on. Any thread; a no-op under
    /// the switch.
    func beginKeeping(_ key: Int) {
        guard !UserDefaults.standard.bool(forKey: Self.keepOffDefaultsKey) else { return }
        condition.lock()
        keeping.insert(key)
        condition.unlock()
    }

    /// Whether `key` keeps the frames it draws: a background pass's own
    /// condition (G-38 (e)). Any thread.
    func keeps(_ key: Int) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return keeping.contains(key)
    }

    /// `key`'s kept frames out; it still keeps.
    func dropKept(_ key: Int) {
        condition.lock()
        kept.drop(key)
        condition.unlock()
    }

    /// `stop(key)`, then its kept frames out, then it keeps no more.
    func endKeeping(_ key: Int) {
        stop(key)
        condition.lock()
        kept.drop(key)
        keeping.remove(key)
        condition.unlock()
    }

    /// A background pass from `key` at `startTicks` begins: every mark out,
    /// it is the origin (G-38 (d)), and Frame Job opts out of App Nap for
    /// the pass's life, so it keeps drawing while hidden or covered (G-38
    /// (c)); `endPassActivity` ends it. Under `condition`.
    func beginAhead(_ key: Int, startTicks: Ticks) {
        kept.clearAhead()
        aheadOrigin = (key, startTicks)
        endPassActivity()
        passActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Frame Job background render (spec §11 G-38)")
    }

    /// The pass ended (done, full or stopped): its App Nap opt-out ends.
    /// Under `condition`.
    func endPassActivity() {
        if let activity = passActivity { ProcessInfo.processInfo.endActivity(activity) }
        passActivity = nil
    }

    /// A play from `key` at `startTicks` begins: the marks stay only when it
    /// starts where the last pass did, on its key. Under `condition`.
    func followAhead(_ key: Int, startTicks: Ticks) {
        if let origin = aheadOrigin, origin.key == key, origin.startTicks == startTicks { return }
        kept.clearAhead()
        aheadOrigin = nil
    }

    /// The play on the last pass's key stopped: every mark out. Under
    /// `condition`.
    func endAhead(_ key: Int) {
        guard aheadOrigin?.key == key else { return }
        kept.clearAhead()
        aheadOrigin = nil
    }

    /// Whether a background pass can take `slots` without its marked frames
    /// giving way: they, every held raster and `slots` within the budget. A
    /// pass ends `full` when not (G-38 (c)). Under `condition`.
    func roomAhead(for slots: [Slot]) -> Bool {
        kept.aheadBytes + heldTotal + slots.reduce(0) { $0 + $1.width * $1.height * 4 }
            <= budgetBytes
    }

    /// A background session's one line (G-38 (c)); B is the marked bytes.
    /// Under `condition`.
    func backgroundLine(
        key: Int, workers: Int, start: Ticks, frames: Int, counts: (drawn: Int, kept: Int),
        end: String
    ) -> String {
        "[framejob] graphic background: key \(key), \(workers) workers, from \(start), "
            + "\(frames) frames with graphics, \(counts.drawn) drawn, \(counts.kept) already "
            + "kept, \(kept.aheadBytes) bytes kept, \(end)"
    }

    /// The compositor used `raster` for `textureKey` on `key`: kept when `key`
    /// keeps and it fits the room the held rasters leave, then the kept
    /// frames trimmed to that room.
    func keep(_ key: Int, textureKey: String, raster: GraphicRaster) {
        condition.lock()
        defer { condition.unlock() }
        guard keeping.contains(key), raster.bgra.count <= budgetBytes - heldTotal else { return }
        kept.insert(key, textureKey, raster)
        kept.trim(toFit: budgetBytes - heldTotal)
    }

    /// The memory-pressure level: the system's, or with `simulated` the dev
    /// tool's, which holds until it sets `.normal` (that clears it). The kept
    /// frames trimmed to the new budget, and every waiting worker told.
    func setPressure(_ level: MemoryPressure, simulated: Bool = false) {
        condition.lock()
        if simulated {
            simulatedPressure = level == .normal ? nil : level
        } else {
            pressure = level
        }
        kept.trim(toFit: budgetBytes - heldTotal)
        condition.broadcast()
        condition.unlock()
    }

    /// The budget, the held rasters and the kept frames now; the peaks reset
    /// to the current totals when asked.
    func memoryReport(resettingPeaks: Bool) -> GraphicMemoryReport {
        condition.lock()
        defer { condition.unlock() }
        let report = GraphicMemoryReport(
            physicalBytes: Int(clamping: Self.physicalBytes), budgetBytes: budgetBytes,
            pressure: simulatedPressure ?? pressure, heldBytes: heldTotal,
            heldPeakBytes: heldPeakBytes, heldPeakEntries: heldPeakEntries,
            keptBytes: kept.bytes, keptFrames: kept.count, keptHits: keptHits,
            aheadBytes: kept.aheadBytes, aheadEvicted: kept.aheadEvicted,
            passActivity: passActivity != nil)
        if resettingPeaks {
            heldPeakBytes = heldTotal
            heldPeakEntries = heldEntries
            kept.aheadEvicted = 0
        }
        return report
    }

    /// One `DispatchSourceMemoryPressure` over normal, warning and critical,
    /// on a utility queue, for the process's life.
    func watchMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self, weak source] in
            guard let self, let event = source?.data else { return }
            let level: MemoryPressure =
                event.contains(.critical)
                ? .critical : event.contains(.warning) ? .warning : .normal
            self.setPressure(level)
        }
        condition.lock()
        pressureSource = source
        condition.unlock()
        source.activate()
    }
}
