// Road map creator-jobs CU2 — a cursor file evaluated through the app's own `ReelCursor.query`
// and its typed requests, and the process-wide `CursorTracks` registry (spec §11 CU-20…CU-26).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`,
// with `FRAMEJOB_DEV_TOOLS`, against `libframejob_core.a`, through `swift_build.py`:
//
//   cursor_track_probe <work dir> -RCDevCursorLoadHold 2
//
// Every fixture is a `CursorFileBody` written under `<work dir>`. The answer is one JSON object
// on stdout, `{"rows": [...]}`, each row `{"id", "pass", "detail"}`; `cursor_track_probe.py`
// prints and scores them (T1, which needs CU1b's granted recordings, is the script's).
import AppKit

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: cursor_track_probe <work dir> …\n".utf8))
    exit(2)
}
let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

var rows: [[String: Any]] = []
func row(_ id: String, _ problems: [String], _ detail: String) {
    rows.append(["id": id, "pass": problems.isEmpty,
                 "detail": problems.isEmpty ? detail : problems.joined(separator: "; ")])
}

// MARK: - Instruments

let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

/// A body at 2 px a point, one geometry entry at the origin (a file unit is 1/50 px).
func body(moves: [(Int64, Int64, Int64)], downs: [(Int64, Int64, Int64)] = [],
          images: Bool = false) -> CursorFileBody {
    var b = CursorFileBody(
        version: ReelCursor.fileVersion, inPicture: false, source: .display, displayID: 1,
        sourceFrame: [0, 0, 151200, 98200], pointSize: [151200, 98200], pixelsPerPoint: 2,
        contentSize: [3024, 1964], movieSize: [3024, 1964], anchor: .e2, anchorHostUs: 0,
        cursorImage: images ? .currentSystem : .none)
    b.geometry = [.init(t: 0, screenRect: [0, 0, 151200, 98200],
                        contentRect: [0, 0, 151200, 98200], contentScale: 1, scaleFactor: 2)]
    b.moves.t = moves.map(\.0)
    b.moves.x = moves.map(\.1)
    b.moves.y = moves.map(\.2)
    for (t, x, y) in downs {
        b.clicks.t.append(t)
        b.clicks.button.append(0)
        b.clicks.down.append(1)
        b.clicks.x.append(x)
        b.clicks.y.append(y)
        b.clicks.count.append(1)
    }
    return b
}

func write(_ b: CursorFileBody, _ name: String) -> URL {
    let url = work.appendingPathComponent(name)
    try? b.encoded().write(to: url)
    return url
}

func nanos() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

/// Main-queue posts, recorded as (path, smoothing).
final class Landings {
    private let lock = NSLock()
    private var seen: [(String, Double)] = []
    func add(_ path: String, _ smoothing: Double) { lock.withLock { seen.append((path, smoothing)) } }
    func count(_ path: String, _ smoothing: Double? = nil) -> Int {
        lock.withLock { seen.filter { $0.0 == path && (smoothing == nil || $0.1 == smoothing) }.count }
    }
}
let landings = Landings()
let observer = NotificationCenter.default.addObserver(
    forName: .cursorTrackDidLand, object: nil, queue: nil) { note in
    landings.add(note.userInfo?["path"] as? String ?? "", note.userInfo?["smoothing"] as? Double ?? -1)
}

/// Runs the main run loop (where landings post) until `done` or `limit` seconds.
@discardableResult
func pump(_ limit: TimeInterval, until done: () -> Bool = { false }) -> Bool {
    let end = Date().addingTimeInterval(limit)
    while Date() < end {
        if done() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return done()
}

/// `wait` off main (it never runs there), pumping main meanwhile; nil, or why it did not
/// return within `limit`.
func waitOffMain(_ tracks: CursorTracks, _ requests: [CursorTrackRequest], owner: Int,
                 limit: TimeInterval) -> String? {
    final class Box { let lock = NSLock(); var done = false; var why: String? }
    let box = Box()
    let deadline = Date().addingTimeInterval(limit)
    DispatchQueue.global().async {
        var why: String?
        do { try tracks.wait(for: requests, owner: owner, cancelled: { Date() > deadline }) }
        catch { why = "wait threw \(error)" }
        box.lock.withLock { box.done = true; box.why = why }
    }
    pump(limit + 2) { box.lock.withLock { box.done } }
    return box.lock.withLock { box.done ? box.why : "wait did not return" }
}

// MARK: - T2: the one-hour worst case through ReelCursor.query

do {
    var problems: [String] = []
    var b = body(moves: [], images: true)
    let hour: Int64 = 3_600_000_000
    for k in 0..<432_000 {
        let t = Int64((Double(k) * 1e6 / 120).rounded())
        b.moves.t.append(t)
        b.moves.x.append(Int64(70000 + 60000 * sin(Double(k) / 500)))
        b.moves.y.append(Int64(45000 + 40000 * cos(Double(k) / 730)))
    }
    for s in 0..<Int64(3600) {
        for (offset, down) in [(Int64(500_000), Int64(1)), (550_000, 0)] {
            b.clicks.t.append(s * 1_000_000 + offset)
            b.clicks.button.append(0)
            b.clicks.down.append(down)
            b.clicks.x.append(70000)
            b.clicks.y.append(45000)
            b.clicks.count.append(1)
        }
        b.imageChanges.t.append(s * 1_000_000 + 1)
        b.imageChanges.id.append(s % 40)
    }
    b.keys.typed.t = (0..<Int64(20_000)).map { $0 * 180_000 }
    b.images = (0..<40).map { i in
        .init(png: Data(pngSignature + [UInt8(i)]).base64EncodedString(), hotX: 400, hotY: 400,
              w: 1600, h: 2400, kind: .arrow)
    }
    do {
        let cursor = try ReelCursor(data: b.encoded())
        var prepares: [Double] = []
        for _ in 0..<2 {
            let start = nanos()
            let kept = try cursor.prepare(smoothing: 1)
            prepares.append(Double(nanos() - start) / 1e9)
            if kept < 2 { problems.append("prepare at 1 kept \(kept)") }
            _ = try cursor.unprepare(smoothing: 1)
        }
        _ = try cursor.prepare(smoothing: 1)
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func requests(_ smoothing: Double) -> [String] {
            (0..<1000).map { _ in
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let at = Int64(seed >> 11) % (hour / 5 * 3)
                return "{\"state\":{\"at\":\(at),\"props\":{\"smoothing\":\(smoothing),"
                    + "\"hide_idle\":2,\"scale\":1,\"clicks\":\"ripple\"}}}"
            }
        }
        var medians: [String] = []
        for (smoothing, label) in [(1.0, "prepared 1"), (0.5, "unprepared 0.5")] {
            for run in 1...2 {
                let list = requests(smoothing)
                var times: [Double] = []
                for request in list {
                    let start = nanos()
                    _ = try cursor.query(request)
                    times.append(Double(nanos() - start) / 1e3)
                }
                let m = median(times)
                medians.append(String(format: "%@ run %d %.2f µs", label, run, m))
                if m > 20 { problems.append(String(format: "state median %.2f µs at %@", m, label)) }
            }
        }
        for (i, p) in prepares.enumerated() where p > 1 {
            problems.append(String(format: "prepare at 1 run %d took %.3f s", i + 1, p))
        }
        row("T2", problems, "432,000 moves, 7,200 clicks, 20,000 typed, 40 images, 3,600 changes; "
            + "state medians " + medians.joined(separator: ", ") + "; prepare at 1 "
            + prepares.map { String(format: "%.3f s", $0) }.joined(separator: ", "))
    } catch {
        row("T2", ["the one-hour file: \(error)"], "")
    }
}

// MARK: - T3: `ready` never waits on a held load; one landing

do {
    var problems: [String] = []
    let tracks = CursorTracks()
    let url = write(body(moves: [(0, 1000, 1000), (10_000, 2000, 1000)]), "t3.fjcursor")
    let request = CursorTrackRequest(url: url, smoothing: 0.5)
    let hold = UserDefaults.standard.double(forKey: CursorTracks.devHoldKey)
    if hold != 2 { problems.append("the dev hold reads \(hold), not 2") }
    let wanted = Date()
    tracks.want([request], owner: 1)
    let start = nanos()
    let first = tracks.ready(url: url, smoothing: 0.5)
    let readyMs = Double(nanos() - start) / 1e6
    if first != nil { problems.append("ready answered a track at once") }
    if readyMs >= 50 { problems.append(String(format: "ready took %.1f ms", readyMs)) }
    pump(4) { tracks.ready(url: url, smoothing: 0.5) != nil }
    let landed = Date().timeIntervalSince(wanted)
    if tracks.ready(url: url, smoothing: 0.5) == nil {
        problems.append("no track 4 s after the want")
    } else if landed < 1.9 {
        problems.append(String(format: "the track was there %.2f s after the want", landed))
    }
    pump(max(0, 4 - Date().timeIntervalSince(wanted)))
    let posts = landings.count(url.path)
    if posts != 1 { problems.append("\(posts) landings over 4 s") }
    tracks.want([request], owner: 1)
    pump(1)
    let again = landings.count(url.path)
    if again != posts { problems.append("a second want posted \(again - posts)") }
    row("T3", problems, String(format: "ready nil in %.3f ms; the track after %.2f s; %d landing "
        + "over 4 s; none for a second want", readyMs, landed, posts))
}

// The hold was T3's; the registry rows below load at once.
UserDefaults.standard.setVolatileDomain([:], forName: UserDefaults.argumentDomain)

// MARK: - T4: `path` at 10 Hz against hand-computed positions

do {
    var problems: [String] = []
    func expect(_ name: String, _ got: [Double], _ want: [Double]) {
        if got.count != want.count || zip(got, want).contains(where: { abs($0 - $1) > 1e-9 }) {
            problems.append("\(name) \(got) is not \(want)")
        }
    }
    do {
        // A collinear uniform run, raw: (500 pt + t/10 µs units) / 50 px, y 300 pt → 600 px.
        let run = (0...100).map { k in (Int64(k) * 10_000, Int64(50000 + k * 1000), Int64(30000)) }
        let uniform = try ReelCursor(data: body(moves: run).encoded())
        let p = try uniform.path(from: 0, to: 600_000, step: 60_000, smoothing: 0)
        if p.t != (0..<10).map({ Int64($0) * 60_000 }) { problems.append("run t \(p.t)") }
        expect("run x", p.x, [1000, 1200, 1400, 1600, 1800, 2000, 2200, 2400, 2600, 2800])
        expect("run y", p.y, Array(repeating: 600, count: 10))
        // A hold, smoothed: held at move 1 (10000 units, 200 px) from 0.1 s to 0.99 s.
        let held = try ReelCursor(data: body(moves: [(0, 0, 0), (100_000, 10000, 0),
                                                     (1_000_000, 20000, 0)]).encoded())
        let h = try held.path(from: 0, to: 600_000, step: 60_000, smoothing: 0.5)
        expect("hold x", h.x, [0] + Array(repeating: 200, count: 9))
        // A click pin, smoothed: off the run at 0.3 s, (800 pt, 350 pt) → (1600, 700) px.
        let clicked = try ReelCursor(data: body(moves: run, downs: [(300_000, 80000, 35000)])
            .encoded())
        let c = try clicked.path(from: 0, to: 600_000, step: 60_000, smoothing: 0.5)
        expect("click x at 0 and 0.3 s", [c.x[0], c.x[3]], [1000, 1600])
        expect("click y at 0 and 0.3 s", [c.y[0], c.y[3]], [600, 700])
    } catch {
        problems.append("\(error)")
    }
    row("T4", problems, "a collinear run raw, a hold and a click pin smoothed, at 10 Hz, each "
        + "within 1e-9 px of its hand-computed position")
}

// MARK: - T5: eviction never touches a pinned entry

do {
    var problems: [String] = []
    let hold = UserDefaults.standard.double(forKey: CursorTracks.devHoldKey)
    // (a) Ten paths pinned under one owner: all land, and `wait` returns.
    let wide = CursorTracks()
    let urls = (0..<10).map { i in
        write(body(moves: [(0, Int64(i) * 100, 0), (10_000, Int64(i) * 100 + 50, 0)]),
              "t5a-\(i).fjcursor")
    }
    let all = urls.map { CursorTrackRequest(url: $0, smoothing: 0) }
    if let why = waitOffMain(wide, all, owner: 7, limit: 30) { problems.append("(a) \(why)") }
    let present = urls.filter { wide.ready(url: $0, smoothing: 0) != nil }.count
    if present != 10 { problems.append("(a) \(present) of 10 ready") }
    wide.release(owner: 7)
    // (b) One path, each smoothing wanted alone in turn.
    let narrow = CursorTracks()
    var zigzag: [(Int64, Int64, Int64)] = []
    for k in Int64(0)...20 { zigzag.append((k * 10_000, k * 1000, k % 3 * 900)) }
    let url = write(body(moves: zigzag), "t5b.fjcursor")
    let smoothings = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]
    for s in smoothings {
        let request = [CursorTrackRequest(url: url, smoothing: s)]
        if let why = waitOffMain(narrow, request, owner: 9, limit: 10) {
            problems.append("(b) \(s): \(why)")
        }
    }
    let readyNow = smoothings.filter { narrow.ready(url: url, smoothing: $0) != nil }
    if readyNow != [0.3, 0.4, 0.5, 0.6] { problems.append("(b) ready after the sixth: \(readyNow)") }
    pump(0.3)
    let before = landings.count(url.path, 0.1)
    if let why = waitOffMain(narrow, [CursorTrackRequest(url: url, smoothing: 0.1)], owner: 9,
                             limit: 10) {
        problems.append("(b) 0.1 again: \(why)")
    }
    pump(0.5)
    let after = landings.count(url.path, 0.1)
    if after != before + 1 { problems.append("(b) wanting 0.1 again posted \(after - before)") }
    if narrow.ready(url: url, smoothing: 0.1) == nil { problems.append("(b) 0.1 not ready again") }
    problems = problems.map { "\($0) (hold \(hold) s)" }
    row("T5", problems, "(a) 10 pinned paths all ready and `wait` returned; (b) after 0.1…0.6 "
        + "0.1 and 0.2 evicted, 0.3…0.6 ready, 0.1 landed again with one post (hold \(hold) s)")
}

NotificationCenter.default.removeObserver(observer)
let answer = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
    ?? Data("{}".utf8)
FileHandle.standardOutput.write(answer)
exit(0)
