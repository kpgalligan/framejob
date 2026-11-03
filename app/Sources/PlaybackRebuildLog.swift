import Foundation

#if FRAMEJOB_DEV_TOOLS
/// The preview's rebuilds, counted and timed (road map "creator-jobs" SW0, spec §11 SW-1): one
/// log per `Playback`, read by the dev tool `playback_rebuilds`
/// (`AgentServer+PlaybackRebuilds.swift`). Dev tools only, so Distribution carries none of it.
///
/// Three calls feed it, each one line under `FRAMEJOB_DEV_TOOLS`: `Playback.startRebuild`
/// notes a generation's start, `finishRebuild`'s success arm — after its generation guard, so
/// a superseded build is never an entry — keeps the entry with its `built_ms`, and the landing
/// arm of `seekFinished()` (`Playback+Scope.swift`) fills the last entry's `landed_ms`: the
/// restore seek that follows the item swap is the first seek to land after it.
///
/// Main thread only, as `Playback` is. Times are `DispatchTime` uptime nanoseconds, so a sleep
/// of the Mac does not count.
final class PlaybackRebuildLog {
    /// The last rebuilds kept; `count` goes on counting past it.
    static let capacity = 256
    /// `-RCDevRebuildHold <s>` (spec §11 SW-4): each rebuild's main-thread landing waits s
    /// seconds, through `Playback.rebuildHop`, so a proof can make two edits inside one flight.
    static let devHoldKey = "RCDevRebuildHold"

    struct Entry: Equatable {
        let generation: Int
        /// When the generation started (`DispatchTime.now().uptimeNanoseconds`).
        let start: UInt64
        /// From the start to the success arm, in ms.
        let builtMs: Double
        /// From the start to the first seek landing after the build, in ms; nil until then.
        var landedMs: Double?
    }

    /// Oldest first, at most `capacity`.
    private(set) var entries: [Entry] = []
    /// Entries built since the last reset (may exceed `capacity`).
    private(set) var count = 0
    /// Generation → its start, until a build at or after it lands.
    private var starts: [Int: UInt64] = [:]

    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    private static func ms(from start: UInt64, to end: UInt64) -> Double {
        Double(end &- start) / 1_000_000
    }

    /// `startRebuild` dispatched this generation.
    func started(generation: Int) {
        starts[generation] = Self.now()
    }

    /// This generation's build reached the success arm as the current one.
    func built(generation: Int) {
        guard let start = starts[generation] else { return }
        entries.append(
            Entry(
                generation: generation, start: start,
                builtMs: Self.ms(from: start, to: Self.now()), landedMs: nil))
        count += 1
        starts = starts.filter { $0.key > generation }
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    /// A seek landed: the last entry's landing, if it has none yet.
    func landed() {
        guard let last = entries.indices.last, entries[last].landedMs == nil else { return }
        entries[last].landedMs = Self.ms(from: entries[last].start, to: Self.now())
    }

    /// Forgets every entry and the count; a generation already started keeps its start.
    func reset() {
        entries = []
        count = 0
    }

    /// The hop `Playback.init` installs when `-RCDevRebuildHold` is positive, else nil — so a
    /// probe that sets `rebuildHop` itself (`scope_playhead_probe.swift`) is never overridden
    /// by a default it did not pass.
    static func heldHop() -> ((@escaping ((any Error)?) -> Void) -> Void)? {
        let seconds = UserDefaults.standard.double(forKey: devHoldKey)
        guard seconds > 0 else { return nil }
        return { finish in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { finish(nil) }
        }
    }
}
#endif
