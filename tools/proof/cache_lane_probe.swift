// Issue #367 — the cache lane (`MediaImporter.CacheLane`,
// `app/Sources/MediaCacheLane.swift`): at most two bodies at a time, FIFO, on
// the lane's own queue and never on the submitting thread.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a`, through
// `swift_build.build` (`reader_wedge_proof.py`'s probe group). One process
// answers every row:
//
//   cache_lane_probe [<audio file>]
//
// With an audio file it also answers C1 (reported, never scored): 30 s of the
// file read on a GCD queue alone, then again while one blocking task per core
// holds the Swift cooperative pool. Whether that GCD read stalls is the
// measured cause spec §11 #367 names.
//
// The answer is one JSON object on stdout, `{"rows": [...]}`, each row
// `{"id", "pass", "detail"}`; `reader_wedge_proof.py` prints and scores them.
// Every wait is bounded; a timeout is the row's FAIL. The bounds are literals
// (2 at once, a start rank within 1), never read back from `CacheLane.width`.
import AVFoundation
import Foundation

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}

/// What the bodies of one run did: how many ran at once at most, the order
/// they started in, and how many finished.
final class Record: @unchecked Sendable {
    private let lock = NSLock()
    private var running = 0
    private var peak = 0
    private var starts: [Int] = []
    private var done = 0

    func begin(_ index: Int) {
        lock.lock()
        running += 1
        peak = max(peak, running)
        starts.append(index)
        lock.unlock()
    }

    func end() {
        lock.lock()
        running -= 1
        done += 1
        lock.unlock()
    }

    func read() -> (peak: Int, starts: [Int], done: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (peak, starts, done)
    }
}

/// A value set on one thread and read on another.
final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    var value: String? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// A track loaded on one thread and read on another.
final class TrackBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AVAssetTrack?
    var track: AVAssetTrack? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

let count = 40
let bodyMicroseconds: UInt32 = 20_000
let bound: TimeInterval = 10

/// Polls until `count` bodies finished or `bound` passed: the seconds it
/// took, or nil.
func waitDone(_ record: Record, since started: Date) -> TimeInterval? {
    while Date().timeIntervalSince(started) < bound {
        if record.read().done >= count { return Date().timeIntervalSince(started) }
        usleep(1_000)
    }
    return record.read().done >= count ? Date().timeIntervalSince(started) : nil
}

// MARK: - L1 and L3: 40 bodies of 20 ms from 40 threads

do {
    let lane = MediaImporter.CacheLane(width: MediaImporter.CacheLane.width)
    let record = Record()
    let gate = DispatchSemaphore(value: 0)
    for index in 0..<count {
        let thread = Thread {
            gate.wait()
            lane.submit {
                record.begin(index)
                usleep(bodyMicroseconds)
                record.end()
            }
        }
        thread.start()
    }
    let started = Date()
    for _ in 0..<count { gate.signal() }
    let took = waitDone(record, since: started)
    let seen = record.read()
    row("L1", seen.peak == 2,
        "\(count) bodies of 20 ms from \(count) threads: at most \(seen.peak) ran at once (want 2)")
    row("L3", took != nil,
        took.map { "all \(count) bodies finished in \(String(format: "%.3f", $0)) s (bound 10 s)" }
            ?? "\(seen.done) of \(count) bodies finished within 10 s")
}

// MARK: - L2: 40 bodies from one thread start in submission order, within 1

do {
    let lane = MediaImporter.CacheLane(width: MediaImporter.CacheLane.width)
    let record = Record()
    let started = Date()
    for index in 0..<count {
        lane.submit {
            record.begin(index)
            usleep(bodyMicroseconds)
            record.end()
        }
    }
    _ = waitDone(record, since: started)
    let starts = record.read().starts
    let worst = starts.enumerated().map { abs($0.element - $0.offset) }.max() ?? 0
    let ok = starts.count == count && worst <= 1
    row("L2", ok,
        "\(starts.count) of \(count) bodies started; the largest |start rank − submission index| "
            + "is \(worst) (want ≤ 1); first ranks \(Array(starts.prefix(8)))")
}

// MARK: - L4: `onCacheLane` runs its body on the lane's own queue

do {
    let box = Box()
    let finished = DispatchSemaphore(value: 0)
    Task.detached {
        let label = await MediaImporter.onCacheLane {
            String(cString: __dispatch_queue_get_label(nil))
        }
        box.value = label
        finished.signal()
    }
    let answered = finished.wait(timeout: .now() + bound) == .success
    let label = box.value
    row("L4", answered && label == MediaImporter.CacheLane.label,
        answered
            ? "the body ran on queue \"\(label ?? "nil")\" (want \"\(MediaImporter.CacheLane.label)\")"
            : "onCacheLane did not answer within 10 s")
}

// MARK: - C1 (reported): a GCD-queue read while blocked tasks hold the cooperative pool

/// Reads the first 30 s of `track` on a GCD `.utility` queue; signals `done`
/// with the seconds it took in `box`, or why the reader failed.
func gcdRead(_ asset: AVURLAsset, _ track: AVAssetTrack, into box: Box,
             _ done: DispatchSemaphore) {
    DispatchQueue(label: "com.kgalligan.framejob.probe.gcd-read", qos: .utility).async {
        let started = Date()
        guard let reader = try? AVAssetReader(asset: asset) else {
            box.value = "no reader"; done.signal(); return
        }
        let output = AVAssetReaderTrackOutput(
            track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        reader.add(output)
        reader.timeRange = CMTimeRange(start: .zero,
                                       duration: CMTime(seconds: 30, preferredTimescale: 48_000))
        guard reader.startReading() else {
            box.value = "startReading failed"; done.signal(); return
        }
        while output.copyNextSampleBuffer() != nil {}
        box.value = String(format: "%.2f", Date().timeIntervalSince(started))
        done.signal()
    }
}

if CommandLine.arguments.count > 1 {
    let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
    let trackBox = TrackBox()
    let loaded = DispatchSemaphore(value: 0)
    Task.detached {
        trackBox.track = (try? await asset.loadTracks(withMediaType: .audio))?.first
        loaded.signal()
    }
    _ = loaded.wait(timeout: .now() + bound)
    if let track = trackBox.track {
        let control = Box()
        let controlDone = DispatchSemaphore(value: 0)
        gcdRead(asset, track, into: control, controlDone)
        let controlAnswered = controlDone.wait(timeout: .now() + 30) == .success
        let width = ProcessInfo.processInfo.activeProcessorCount
        let entered = Record()
        let release = DispatchSemaphore(value: 0)
        for index in 0..<width {
            Task.detached(priority: .utility) {
                entered.begin(index)
                release.wait()
                entered.end()
            }
        }
        let fillStarted = Date()
        while entered.read().starts.count < width && Date().timeIntervalSince(fillStarted) < 5 {
            usleep(1_000)
        }
        let held = entered.read().starts.count
        let blocked = Box()
        let blockedDone = DispatchSemaphore(value: 0)
        gcdRead(asset, track, into: blocked, blockedDone)
        let stallBound: TimeInterval = 15
        let whileHeld = blockedDone.wait(timeout: .now() + stallBound) == .success
        for _ in 0..<width { release.signal() }
        let afterRelease = whileHeld || blockedDone.wait(timeout: .now() + 30) == .success
        let alone = controlAnswered ? "\(control.value ?? "?") s" : "no answer in 30 s"
        let verdict = whileHeld
            ? "finished in \(blocked.value ?? "?") s while held"
            : "STALLED (no finish in \(Int(stallBound)) s while held)"
                + (afterRelease
                    ? "; finished after the release, \(blocked.value ?? "?") s from its start"
                    : "; still unfinished 30 s after the release")
        row("C1", true,
            "30 s of audio read on a GCD queue: alone \(alone); with \(held) of \(width) "
                + "cooperative threads held by blocking tasks, \(verdict)")
    } else {
        row("C1", true, "not measured: no audio track loaded from \(CommandLine.arguments[1])")
    }
}

let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
    ?? Data("{}".utf8)
FileHandle.standardOutput.write(data)
exit(0)
