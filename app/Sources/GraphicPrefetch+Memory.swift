// app/Sources/GraphicPrefetch+Memory.swift — the graphic rasters' one memory
// budget and the frames a document keeps (spec §11 G-37, issue #127).
//
// **One budget for the process.** A quarter of physical memory covers every
// session's held rasters (export and playback) and the kept frames. A worker
// waits while the held rasters of all sessions reach it (`claim`); the kept
// frames give way, least recently used first, and never exceed the room the
// held rasters leave: every change to either trims them to
// `max(0, budget − held)`. Memory pressure halves the budget (warning) or
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

    /// The least recently used out until `bytes <= max(0, room)`.
    mutating func trim(toFit room: Int) {
        let limit = max(0, room)
        while bytes > limit, head < order.count {
            let (name, stamp) = order[head]
            head += 1
            guard let frame = frames[name], frame.stamp == stamp else { continue }
            frames[name] = nil
            bytes -= frame.raster.bgra.count
        }
        compact()
    }

    /// Every frame of `key` out.
    mutating func drop(_ key: Int) {
        let gone = frames.keys.filter { $0.key == key }
        for name in gone {
            if let frame = frames.removeValue(forKey: name) { bytes -= frame.raster.bgra.count }
        }
        compact()
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
            keptBytes: kept.bytes, keptFrames: kept.count, keptHits: keptHits)
        if resettingPeaks {
            heldPeakBytes = heldTotal
            heldPeakEntries = heldEntries
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
