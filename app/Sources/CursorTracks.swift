import Foundation

/// A cursor track wanted at one smoothing: the file and the smoothing its clip draws with.
struct CursorTrackRequest: Hashable {
    let url: URL
    let smoothing: Double
}

extension Notification.Name {
    /// A (path, smoothing) became ready (`CursorTracks`), posted once on main; userInfo
    /// `["path": String, "smoothing": Double]`.
    static let cursorTrackDidLand = Notification.Name("FrameJobCursorTrackDidLand")
}

/// The process-wide registry of loaded and prepared cursor tracks (spec §11 CU-24, CU-26),
/// in `RampAudioRenders`' owner shape.
///
/// **Owners.** Each owner's latest `want` set is PINNED until it is replaced or
/// `release(owner:)` is called; `wait(for:owner:cancelled:)` first wants its set under its
/// owner, so an export's set stays pinned until the export releases it. A pinned (path,
/// smoothing) is never evicted, however many there are.
///
/// **Keys.** A track is keyed by its path with the file's size and modification second, read
/// by stat at `want`; a change reloads. A failed key (the core's sentence, CU-24, or a file that
/// could not be read) is not retried until its size or modification second changes.
///
/// **Eviction** touches only unpinned entries: at most `capacity` paths, the least recently
/// wanted unpinned one closed first, and per path at most `smoothingsPerPath` prepared
/// smoothings, the least recently wanted unpinned one dropped first. A dropped smoothing's
/// `ready` entry goes under the lock BEFORE its `unprepare` is sent on the queue, so `ready`
/// never answers a smoothing the core has dropped, and a later `want` prepares and lands it
/// again.
///
/// **Work.** One serial `.utility` queue loads (the dev hold first), opens, prepares and
/// unprepares; `ready` reads a locked dictionary and nothing else, so the compositor never
/// waits on a load. Each (path, smoothing) landing posts `.cursorTrackDidLand` once on main;
/// nothing else here touches main. `RecipeSource.set` and `Playback.update` want their cursor
/// media from CU3a2, when the recipe carries them.
final class CursorTracks: @unchecked Sendable {
    static let shared = CursorTracks()
    /// The dev-only launch default that holds each load that many seconds, so a proof can act
    /// while it is pending. Read only under `FRAMEJOB_DEV_TOOLS`.
    static let devHoldKey = "RCDevCursorLoadHold"
    static let capacity = 8
    static let smoothingsPerPath = 4

    enum WaitError: Error, Equatable {
        case failed(path: String, message: String), cancelled
    }

    /// A file's identity: its size and modification second, or nil when stat failed.
    private struct FileKey: Equatable {
        let size: Int64
        let second: Int64
    }

    /// A pinned (path, smoothing): an owner's latest `want` holds it.
    private struct Pin: Hashable {
        let path: String
        let smoothing: Double
    }

    /// One path's track: loading until `cursor` is set; `ready` the landed smoothings,
    /// `pending` the ones queued; `used` each smoothing's and `lastWanted` the path's clock.
    private final class Entry {
        let key: FileKey
        var cursor: ReelCursor?
        var ready: Set<Double> = []
        var pending: Set<Double> = []
        var used: [Double: UInt64] = [:]
        var lastWanted: UInt64 = 0
        init(key: FileKey) { self.key = key }
    }

    private let condition = NSCondition()
    private var entries: [String: Entry] = [:]
    private var failures: [String: (key: FileKey?, message: String)] = [:]
    private var wants: [Int: [CursorTrackRequest]] = [:]
    private var clock: UInt64 = 0
    private let work = DispatchQueue(label: "com.kgalligan.framejob.cursor-tracks", qos: .utility)

    /// The app uses `shared`; a probe measures a registry of its own.
    init() {}

    /// Replaces `owner`'s wanted set (pinned until replaced or released), queues a load or a
    /// prepare for each request not ready, then evicts. Any thread; stats each file once.
    func want(_ requests: [CursorTrackRequest], owner: Int) {
        var keys: [String: FileKey?] = [:]
        for request in requests where keys[request.url.path] == nil {
            keys[request.url.path] = Self.stat(request.url.path)
        }
        condition.lock()
        wants[owner] = requests.isEmpty ? nil : requests
        var jobs: [(String, Entry, Double)] = []
        for request in requests {
            let path = request.url.path
            let key = keys[path] ?? nil
            clock += 1
            if let failed = failures[path] {
                if failed.key == key { continue }
                failures[path] = nil
            }
            guard let key else {
                failures[path] = (nil, "the cursor file \(path) could not be read")
                entries[path] = nil
                continue
            }
            let entry: Entry
            if let current = entries[path], current.key == key {
                entry = current
            } else {
                entry = Entry(key: key)
                entries[path] = entry
            }
            entry.lastWanted = clock
            entry.used[request.smoothing] = clock
            let s = request.smoothing
            if !entry.ready.contains(s), !entry.pending.contains(s) {
                entry.pending.insert(s)
                jobs.append((path, entry, s))
            }
        }
        let drops = evictLocked()
        // Queued before the unlock, so the serial queue's order follows the lock's.
        for (path, entry, s) in jobs {
            work.async { self.perform(path: path, entry: entry, smoothing: s) }
        }
        unprepare(drops)
        condition.unlock()
    }

    /// Drops `owner`'s pin — a closed document, a finished export — then evicts.
    func release(owner: Int) {
        condition.lock()
        wants[owner] = nil
        unprepare(evictLocked())
        condition.unlock()
    }

    /// Sends each dropped smoothing's `unprepare` on the queue, after its `ready` entry went.
    /// Under the lock, so no `perform` queued by a later `want` can run before it.
    private func unprepare(_ drops: [(ReelCursor, Double)]) {
        for (cursor, s) in drops { work.async { _ = try? cursor.unprepare(smoothing: s) } }
    }

    /// The track at `smoothing` when it has landed, else nil. Never blocks on a load.
    func ready(url: URL, smoothing: Double) -> ReelCursor? {
        condition.lock()
        defer { condition.unlock() }
        guard let entry = entries[url.path], entry.ready.contains(smoothing) else { return nil }
        return entry.cursor
    }

    /// Why the track at `url` failed, or nil.
    func failure(url: URL) -> String? {
        condition.lock()
        defer { condition.unlock() }
        return failures[url.path]?.message
    }

    /// Wants `requests` under `owner`, then blocks until every one is ready, one has failed, or
    /// `cancelled()` answers true — polled every 0.1 s. Never on main; the caller calls
    /// `release(owner:)` afterwards.
    func wait(for requests: [CursorTrackRequest], owner: Int, cancelled: () -> Bool) throws {
        want(requests, owner: owner)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if cancelled() { throw WaitError.cancelled }
            for request in requests {
                if let failed = failures[request.url.path] {
                    throw WaitError.failed(path: request.url.path, message: failed.message)
                }
            }
            if requests.allSatisfy({ entries[$0.url.path]?.ready.contains($0.smoothing) == true }) {
                return
            }
            condition.wait(until: Date().addingTimeInterval(0.1))
        }
    }

    // MARK: - The queue

    /// Loads `entry`'s file when it has no track yet (the dev hold first), then prepares
    /// `smoothing` and lands it — unless the entry was replaced or the smoothing evicted
    /// meanwhile, when an orphaned prepare is unprepared again.
    private func perform(path: String, entry: Entry, smoothing: Double) {
        condition.lock()
        let current = entries[path] === entry && entry.pending.contains(smoothing)
        var cursor = entry.cursor
        condition.unlock()
        guard current else { return }
        if cursor == nil {
            hold()
            do {
                let loaded = try ReelCursor(data: Data(contentsOf: URL(fileURLWithPath: path)))
                condition.lock()
                if entries[path] === entry { entry.cursor = loaded }
                condition.unlock()
                cursor = loaded
            } catch {
                let message = (error as? ReelCoreError)?.message ?? error.localizedDescription
                condition.lock()
                if entries[path] === entry {
                    entries[path] = nil
                    failures[path] = (entry.key, message)
                }
                condition.broadcast()
                condition.unlock()
                return
            }
        }
        guard let cursor else { return }
        if smoothing > 0 { _ = try? cursor.prepare(smoothing: smoothing) }
        condition.lock()
        let lands = entries[path] === entry && entry.pending.remove(smoothing) != nil
        if lands { entry.ready.insert(smoothing) }
        condition.broadcast()
        condition.unlock()
        if lands {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .cursorTrackDidLand, object: nil,
                    userInfo: ["path": path, "smoothing": smoothing])
            }
        } else if smoothing > 0 {
            _ = try? cursor.unprepare(smoothing: smoothing)
        }
    }

    /// Evicts unpinned smoothings past `smoothingsPerPath` on each path, then unpinned paths
    /// past `capacity`, least recently wanted first; answers the stored smoothings whose
    /// `unprepare` the caller sends on the queue. Under the lock.
    private func evictLocked() -> [(ReelCursor, Double)] {
        let pinned = Set(wants.values.joined().map {
            Pin(path: $0.url.path, smoothing: $0.smoothing)
        })
        let pinnedPaths = Set(pinned.map(\.path))
        var drops: [(ReelCursor, Double)] = []
        for (path, entry) in entries {
            let held = entry.ready.union(entry.pending).filter { $0 > 0 }
            var over = held.count - Self.smoothingsPerPath
            let loose = held.filter { !pinned.contains(Pin(path: path, smoothing: $0)) }
            for s in loose.sorted(by: { entry.used[$0, default: 0] < entry.used[$1, default: 0] }) {
                guard over > 0 else { break }
                over -= 1
                entry.pending.remove(s)
                entry.used[s] = nil
                if entry.ready.remove(s) != nil, let cursor = entry.cursor {
                    drops.append((cursor, s))
                }
            }
        }
        var over = entries.count - Self.capacity
        let loose = entries.filter { !pinnedPaths.contains($0.key) }
        for (path, _) in loose.sorted(by: { $0.value.lastWanted < $1.value.lastWanted }) {
            guard over > 0 else { break }
            over -= 1
            entries[path] = nil
        }
        return drops
    }

    /// The file's size and modification second, or nil when it cannot be read.
    private static func stat(_ path: String) -> FileKey? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let date = attributes[.modificationDate] as? Date
        else { return nil }
        return FileKey(size: size, second: Int64(date.timeIntervalSince1970.rounded(.down)))
    }

    /// `-RCDevCursorLoadHold <s>`: each load waits s seconds first (dev tools only).
    private func hold() {
        #if FRAMEJOB_DEV_TOOLS
        let seconds = UserDefaults.standard.double(forKey: Self.devHoldKey)
        if seconds > 0 { Thread.sleep(forTimeInterval: seconds) }
        #endif
    }
}
