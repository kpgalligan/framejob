// Issue batch B14 (#115, #169) — the cache passes' ledger, the save gate
// and the peaks retry, driven through the app's own `MediaImporter`,
// `CacheLedger` and `ProjectDocument`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` — the swiftc
// line `peaks_probe.py` uses. One scenario per process:
//
//   cache_pass_probe <request.json> <G0|G1|G2|G2c|G3|S1|S2|R1|R2|R3|W1>
//
// The request names `media` (a copy of tools/proof/media) and `work` (this
// run's directory). The answer is one JSON object on stdout, `{"rows": [...]}`,
// each row `{"id", "pass", "detail"}`; `cache_pass_probe.py` prints and
// scores them. Every wait pumps `RunLoop.main` (the cache posts hop to main)
// and is bounded; a timeout is the row's FAIL.
//
// "The pass ended" is read through a same-URL follower enqueued through the
// ledger straight after the pass: its task awaits the pass's and sets a
// flag. A same-URL pass with the same input never supersedes, so the
// follower changes nothing.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3,
    let requestData = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
    let mediaPath = request["media"] as? String, let workPath = request["work"] as? String
else {
    FileHandle.standardError.write(Data("usage: cache_pass_probe <request.json> <scenario>\n".utf8))
    exit(2)
}
let scenario = arguments[2]
let mediaDir = URL(fileURLWithPath: mediaPath, isDirectory: true)
let work = URL(fileURLWithPath: workPath, isDirectory: true)
    .appendingPathComponent(scenario, isDirectory: true)
let files = FileManager.default
let ledger = MediaImporter.CacheLedger.shared
let projectType = ProjectDocument.projectTypeIdentifier
_ = NSApplication.shared

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}
func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    exit(0)
}

// MARK: - Instruments

/// A flag set on one thread and read on another.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    private var when: Date?
    func set() {
        lock.lock()
        if !value { value = true; when = Date() }
        lock.unlock()
    }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    var at: Date? { lock.lock(); defer { lock.unlock() }; return when }
}

/// Pumps the main run loop for `seconds`.
func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.01))) }
}

/// Pumps until `condition` holds or `limit` seconds pass; the seconds it
/// took, or nil.
func waitUntil(_ limit: Double, _ condition: () -> Bool) -> Double? {
    let start = Date()
    while Date().timeIntervalSince(start) < limit {
        if condition() { return Date().timeIntervalSince(start) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return condition() ? Date().timeIntervalSince(start) : nil
}

func seconds(_ value: Double?) -> String { value.map { String(format: "%.2f s", $0) } ?? "never" }

func exists(_ url: URL) -> Bool { files.fileExists(atPath: url.path) }

func fresh(_ url: URL) {
    try? files.removeItem(at: url)
    try? files.createDirectory(at: url, withIntermediateDirectories: true)
}

/// A copy of one of the proof media under this scenario's directory.
func copyMedium(_ name: String, as target: String) -> URL {
    let url = work.appendingPathComponent(target)
    try? files.removeItem(at: url)
    try? files.copyItem(at: mediaDir.appendingPathComponent(name), to: url)
    return url
}

/// The record `probeBlocking` gives `url`, under `id`, at `path`.
func record(_ url: URL, id: UInt32, path: URL? = nil) -> MediaSnapshot? {
    guard let d = try? MediaImporter.probeBlocking(url: url) else { return nil }
    return MediaSnapshot(
        id: id, path: (path ?? url).path, kind: d.kind, duration: d.duration,
        width: d.width, height: d.height, fps: d.fps, hasVideo: d.hasVideo,
        hasAudio: d.hasAudio)
}

/// A same-URL follower: its flag is set when the pass enqueued before it
/// has ended.
func follower(_ cacheDir: URL, _ media: UInt32, _ url: URL) -> Flag {
    let ended = Flag()
    ledger.enqueue(cacheDir: cacheDir, media: media, url: url) { previous, _, pass in
        Task.detached {
            await previous?.value
            ended.set()
            pass.done()
        }
    }
    return ended
}

func peaksPresent(_ id: UInt32, _ cacheDir: URL) -> Bool {
    exists(MediaImporter.peaksURL(for: id, in: cacheDir))
        || exists(MediaImporter.peaksMarkerURL(for: id, in: cacheDir))
}

/// `loadPeaks` answers and the marker is the file's own `PeaksStamp` now.
func validWaveform(_ id: UInt32, _ cacheDir: URL, _ media: MediaSnapshot, _ source: URL) -> Bool {
    guard MediaImporter.loadPeaks(for: id, in: cacheDir) != nil,
        let stamp = MediaImporter.CacheStamp.stamp(for: media, url: source)
    else { return false }
    return MediaImporter.readPeaksStamp(at: MediaImporter.peaksMarkerURL(for: id, in: cacheDir))
        == MediaImporter.PeaksStamp(stamp)
}

/// A package directory with an empty `cache/`, and its cache URL.
func package(_ name: String) -> (package: URL, cache: URL) {
    let pkg = work.appendingPathComponent(name, isDirectory: true)
    let cache = pkg.appendingPathComponent("cache", isDirectory: true)
    try? files.createDirectory(at: cache, withIntermediateDirectories: true)
    return (pkg, cache)
}

/// The save's swap: the old package aside, the listed copy in its place.
func swap(_ pkg: URL, with copy: URL) -> Bool {
    let aside = pkg.deletingLastPathComponent().appendingPathComponent("old.framejob")
    do {
        try files.moveItem(at: pkg, to: aside)
        try files.moveItem(at: copy, to: pkg)
        return true
    } catch {
        return false
    }
}

var posts: [(media: UInt32, kind: String)] = []
NotificationCenter.default.addObserver(forName: .mediaCacheDidChange, object: nil, queue: nil) { n in
    posts.append((
        n.userInfo?[MediaImporter.mediaIDKey] as? UInt32 ?? 0,
        n.userInfo?[MediaImporter.cacheKindKey] as? String ?? ""))
}

fresh(work)

// MARK: - G0, G1 — a save straddling a waveform pass

/// G0 (control; #169): the save lists the package BEFORE the pass and swaps
/// after it published into the old one. G1: the same with the save
/// announced to the ledger, so nothing publishes until it ends.
func waveformSave(announced: Bool) {
    let id: UInt32 = announced ? 12 : 11
    let (pkg, cache) = package("pkg.framejob")
    let listed = work.appendingPathComponent("listed.framejob")
    let source = copyMedium("toneA.m4a", as: "toneA.m4a")
    let name = announced ? "G1" : "G0"
    guard let media = record(source, id: id) else {
        return row(name, false, "toneA.m4a did not probe")
    }
    let save = announced ? ledger.saveBegan(cacheDir: cache) : 0
    try? files.copyItem(at: pkg, to: listed)
    MediaImporter.generateCaches(for: media, url: source, in: cache)
    let ended = follower(cache, id, source)
    if !announced {
        let took = waitUntil(30) { ended.isSet }
        let oldMarker = exists(MediaImporter.peaksMarkerURL(for: id, in: cache))
        let swapped = swap(pkg, with: listed)
        pump(5)
        let lost = !peaksPresent(id, cache)
        return row(name, took != nil && oldMarker && swapped && lost,
                   "pass ended \(seconds(took)); marker in the old package \(oldMarker); "
                   + "swapped \(swapped); the swapped-in package has no peaks 5 s later: \(lost)")
    }
    var leaked = false
    let start = Date()
    while Date().timeIntervalSince(start) < 5 {
        if peaksPresent(id, cache) { leaked = true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    let swapped = swap(pkg, with: listed)
    ledger.saveEnded(cacheDir: cache, save: save)
    let landed = waitUntil(15) { validWaveform(id, cache, media, source) }
    row(name, !leaked && swapped && landed != nil,
        "old package got a .bin or marker during the save: \(leaked); swapped \(swapped); "
        + "valid waveform in the swapped-in package \(seconds(landed)) after saveEnded")
}

// MARK: - G2, G2c — the strip's marker and the save

func stripSave(deleteFrame: Bool) {
    let name = deleteFrame ? "G2" : "G2c"
    let id: UInt32 = deleteFrame ? 13 : 14
    let (_, cache) = package("pkg.framejob")
    let source = copyMedium("A.mov", as: "A.mov")
    guard let media = record(source, id: id),
        let stamp = MediaImporter.CacheStamp.stamp(for: media, url: source)
    else { return row(name, false, "A.mov did not probe") }
    let marker = MediaImporter.thumbsMarkerURL(for: id, in: cache)
    let save = ledger.saveBegan(cacheDir: cache)
    MediaImporter.generateCaches(for: media, url: source, in: cache)
    let ended = follower(cache, id, source)
    var count = -1
    var since = Date()
    let still = waitUntil(30) {
        let now = MediaImporter.thumbnailCount(for: id, in: cache)
        if now != count { count = now; since = Date() }
        return count > 0 && Date().timeIntervalSince(since) >= 1
    }
    let markerHeld = exists(marker)
    let frame = MediaImporter.thumbsDirectory(for: id, in: cache).appendingPathComponent("3.jpg")
    var deleted = false
    if deleteFrame { deleted = (try? files.removeItem(at: frame)) != nil }
    ledger.saveEnded(cacheDir: cache, save: save)
    let took = waitUntil(40) { ended.isSet }
    let after = MediaImporter.readStamp(at: marker)
    let good = deleteFrame ? (deleted && after == nil) : after == stamp
    row(name, still != nil && !markerHeld && took != nil && good,
        "\(count) frames held still \(seconds(still)); marker while the save ran: \(markerHeld); "
        + (deleteFrame ? "3.jpg deleted \(deleted); " : "")
        + "pass ended \(seconds(took)); marker after: "
        + (after == nil ? "none" : (after == stamp ? "the stamp" : "another stamp")))
}

// MARK: - G3 — a real document's save waits for a publication

func documentSave() {
    let pkg = work.appendingPathComponent("doc.framejob", isDirectory: true)
    let blank = ProjectDocument()
    do {
        let wrapper = try blank.fileWrapper(ofType: projectType)
        try wrapper.write(to: pkg, options: .atomic, originalContentsURL: nil)
    } catch {
        return row("G3", false, "the package could not be written: \(error.localizedDescription)")
    }
    let document = ProjectDocument()
    do {
        try document.read(from: pkg, ofType: projectType)
    } catch {
        return row("G3", false, "the package did not read: \(error.localizedDescription)")
    }
    document.fileURL = pkg
    guard let cache = document.cacheDirectory else { return row("G3", false, "no cacheDirectory") }
    let entered = DispatchSemaphore(value: 0)
    let holdEnded = Flag()
    let publisher = Thread {
        ledger.publish(in: cache, for: nil) {
            entered.signal()
            Thread.sleep(forTimeInterval: 2)
            holdEnded.set()
        }
    }
    publisher.start()
    guard entered.wait(timeout: .now() + 10) == .success else {
        return row("G3", false, "the held publication never began")
    }
    let called = Date()
    let completed = Flag()
    var saveError: String?
    document.save(to: pkg, ofType: projectType, for: .saveOperation) { error in
        saveError = error?.localizedDescription
        completed.set()
    }
    let returned = Date()
    let arrived = waitUntil(30) { completed.isSet }
    _ = waitUntil(5) { holdEnded.isSet }
    let afterHold = holdEnded.at.map { returned >= $0 } ?? false
    let started = Date()
    let answered = ledger.publish(in: cache, for: nil) {}
    let took = Date().timeIntervalSince(started)
    row("G3", afterHold && arrived != nil && answered && took < 1,
        String(format: "save returned %.2f s after the call, ", returned.timeIntervalSince(called))
        + "after the hold ended: \(afterHold); completion \(seconds(arrived)) after return; "
        + String(format: "a publish after it answered %@ in %.3f s", "\(answered)", took)
        + (saveError.map { " (the save's error, not scored: \($0))" } ?? ""))
}

// MARK: - S1 — a held pass does not hold a relink's pass, and writes nothing after

func heldPass() {
    let id: UInt32 = 21
    let (_, cache) = package("pkg.framejob")
    let one = copyMedium("AV.mov", as: "one.mov")
    let two = copyMedium("AV.mov", as: "two.mov")
    if let date = (try? files.attributesOfItem(atPath: one.path))?[.modificationDate] as? Date {
        try? files.setAttributes(
            [.modificationDate: date.addingTimeInterval(10)], ofItemAtPath: two.path)
    }
    guard let first = record(one, id: id), let second = record(two, id: id),
        let stampOne = MediaImporter.CacheStamp.stamp(for: first, url: one),
        let stampTwo = MediaImporter.CacheStamp.stamp(for: second, url: two), stampOne != stampTwo
    else {
        row("S1a", false, "AV.mov copies did not probe or stamp apart")
        return row("S1b", false, "not run")
    }
    let released = Flag()
    let holding = Flag()
    let fakeEnded = Flag()
    ledger.enqueue(cacheDir: cache, media: id, url: one) { previous, _, pass in
        var held = pass
        held.hold = {
            guard !released.isSet, MediaImporter.thumbnailCount(for: id, in: cache) >= 2 else {
                return
            }
            holding.set()
            let cap = Date().addingTimeInterval(200)
            while !released.isSet, Date() < cap { usleep(10_000) }
        }
        let fake = held
        return Task.detached {
            await previous?.value
            await MediaImporter.thumbnails(for: first, url: one, stamp: stampOne, into: cache,
                                           pass: fake)
            await MediaImporter.peaks(for: first, url: one, stamp: stampOne, into: cache, pass: fake)
            fakeEnded.set()
            fake.done()
        }
    }
    guard waitUntil(30, { holding.isSet }) != nil else {
        released.set()
        row("S1a", false, "the fake pass never reached its hold")
        return row("S1b", false, "not run")
    }
    let thumbsMarker = MediaImporter.thumbsMarkerURL(for: id, in: cache)
    let peaksMarker = MediaImporter.peaksMarkerURL(for: id, in: cache)
    MediaImporter.generateCaches(for: second, url: two, in: cache)
    let latency = waitUntil(60) {
        MediaImporter.readStamp(at: thumbsMarker) == stampTwo
            && MediaImporter.readPeaksStamp(at: peaksMarker) == MediaImporter.PeaksStamp(stampTwo)
    }
    row("S1a", latency != nil,
        "both markers are two.mov's \(seconds(latency)) after its pass was asked for")
    func snapshot() -> [String: String] {
        var out: [String: String] = [
            "thumbs marker": (try? Data(contentsOf: thumbsMarker))?.base64EncodedString() ?? "-",
            "peaks marker": (try? Data(contentsOf: peaksMarker))?.base64EncodedString() ?? "-",
            "bin": (try? Data(contentsOf: MediaImporter.peaksURL(for: id, in: cache)))?
                .base64EncodedString() ?? "-",
        ]
        let strip = MediaImporter.thumbsDirectory(for: id, in: cache)
        for name in (try? files.contentsOfDirectory(atPath: strip.path)) ?? []
        where name.hasSuffix(".jpg") {
            let inode = (try? files.attributesOfItem(
                atPath: strip.appendingPathComponent(name).path))?[.systemFileNumber] as? Int
            out[name] = "\(inode ?? -1)"
        }
        return out
    }
    let before = snapshot()
    released.set()
    let ended = waitUntil(30) { fakeEnded.isSet }
    pump(1)
    let after = snapshot()
    let changed = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }.sorted()
    row("S1b", ended != nil && changed.isEmpty,
        "the fake pass ended \(seconds(ended)) after its release; changed: "
        + (changed.isEmpty ? "nothing" : changed.joined(separator: ", ")))
}

// MARK: - S2 — a same-URL pass with another Camera Log input supersedes (spec §11 GR-21)

func inputSupersedes() {
    let id: UInt32 = 22
    let (_, cache) = package("pkg.framejob")
    let one = copyMedium("AV.mov", as: "one.mov")
    guard let media = record(one, id: id),
        let stamp = MediaImporter.CacheStamp.stamp(for: media, url: one)
    else { return row("S2", false, "AV.mov did not probe or stamp") }
    let released = Flag()
    let holding = Flag()
    let heldEnded = Flag()
    ledger.enqueue(cacheDir: cache, media: id, url: one, input: nil) { previous, _, pass in
        var held = pass
        held.hold = {
            guard !released.isSet, MediaImporter.thumbnailCount(for: id, in: cache) >= 2 else {
                return
            }
            holding.set()
            let cap = Date().addingTimeInterval(200)
            while !released.isSet, Date() < cap { usleep(10_000) }
        }
        let fake = held
        return Task.detached {
            await previous?.value
            await MediaImporter.thumbnails(for: media, url: one, stamp: stamp, into: cache,
                                           pass: fake)
            heldEnded.set()
            fake.done()
        }
    }
    guard waitUntil(30, { holding.isSet }) != nil else {
        released.set()
        return row("S2", false, "the held pass never reached its hold")
    }
    let slog3 = MediaColor(log: .slog3, gamut: .sGamut3Cine)
    var changedBounded: Bool?
    var sameBounded: Bool?
    ledger.enqueue(cacheDir: cache, media: id, url: one, input: slog3) { previous, bounded, pass in
        changedBounded = bounded
        return Task.detached {
            await MediaImporter.awaitPass(previous, bounded: bounded)
            pass.done()
        }
    }
    let strip = MediaImporter.thumbsDirectory(for: id, in: cache)
    func snapshot() -> [String: String] {
        var out: [String: String] = [:]
        for name in (try? files.contentsOfDirectory(atPath: strip.path)) ?? [] {
            let attributes = try? files.attributesOfItem(
                atPath: strip.appendingPathComponent(name).path)
            let inode = attributes?[.systemFileNumber] as? Int ?? -1
            let date = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
            out[name] = "\(inode) \(date)"
        }
        return out
    }
    let before = snapshot()
    released.set()
    let ended = waitUntil(30) { heldEnded.isSet }
    pump(1)
    let after = snapshot()
    let changed = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }.sorted()
    ledger.enqueue(cacheDir: cache, media: id, url: one, input: slog3) { previous, bounded, pass in
        sameBounded = bounded
        return Task.detached {
            await previous?.value
            pass.done()
        }
    }
    row("S2", changedBounded == true && sameBounded == false && ended != nil && changed.isEmpty,
        "another input: bounded \(changedBounded.map { "\($0)" } ?? "never asked"); "
        + "the held pass ended \(seconds(ended)) after its release and changed "
        + (changed.isEmpty ? "nothing" : changed.joined(separator: ", "))
        + "; CONTROL, the same input again: bounded "
        + (sameBounded.map { "\($0)" } ?? "never asked"))
}

// MARK: - R1, R2, R3 — the peaks retry

/// A text file under toneA's record: AVFoundation opens nothing.
func textSource(_ id: UInt32, _ name: String) -> (media: MediaSnapshot, source: URL, toneA: URL)? {
    let toneA = copyMedium("toneA.m4a", as: "toneA.m4a")
    let source = work.appendingPathComponent(name)
    try? Data("not a movie\n".utf8).write(to: source)
    guard let media = record(toneA, id: id, path: source) else { return nil }
    return (media, source, toneA)
}

func retryLands() {
    let id: UInt32 = 31
    let (_, cache) = package("pkg.framejob")
    guard let text = textSource(id, "r1.m4a") else {
        return row("R1", false, "toneA.m4a did not probe")
    }
    let (media, source, toneA) = text
    let voice = MediaImporter.speechURL(for: id, in: cache)
    try? files.createDirectory(at: voice.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(repeating: 0, count: 64).write(to: voice)
    MediaImporter.generateCaches(for: media, url: source, in: cache)
    let withdrawn = waitUntil(30) { posts.contains { $0.media == id && $0.kind == "speech" } }
    let none = MediaImporter.loadPeaks(for: id, in: cache) == nil && !peaksPresent(id, cache)
    let staged = work.appendingPathComponent("r1.staged")
    try? files.removeItem(at: staged)
    try? files.copyItem(at: toneA, to: staged)
    let replaced = rename(staged.path, source.path) == 0
    let landed = waitUntil(10) { validWaveform(id, cache, media, source) }
    row("R1", withdrawn != nil && none && replaced && landed != nil,
        "speech withdrawal post \(seconds(withdrawn)); no peaks then: \(none); "
        + "source replaced with toneA's bytes: \(replaced); valid waveform \(seconds(landed)) later")
}

func retryEnds() {
    let id: UInt32 = 32
    let (_, cache) = package("pkg.framejob")
    guard let text = textSource(id, "r2.m4a") else {
        return row("R2", false, "toneA.m4a did not probe")
    }
    let (media, source) = (text.media, text.source)
    MediaImporter.generateCaches(for: media, url: source, in: cache)
    let ended = follower(cache, id, source)
    let took = waitUntil(22) { ended.isSet }
    let none = !peaksPresent(id, cache)
    row("R2", took != nil && none, "the pass ended \(seconds(took)) after it was asked for; no peaks: \(none)")
}

func retrySuperseded() {
    let id: UInt32 = 33
    let (_, cache) = package("pkg.framejob")
    guard let text = textSource(id, "r3.m4a"), let real = record(text.toneA, id: id) else {
        return row("R3", false, "toneA.m4a did not probe")
    }
    let (media, source, toneA) = text
    MediaImporter.generateCaches(for: media, url: source, in: cache)
    pump(4)
    MediaImporter.generateCaches(for: real, url: toneA, in: cache)
    let landed = waitUntil(5) { validWaveform(id, cache, real, toneA) }
    row("R3", landed != nil,
        "a toneA copy asked for 4 s in: valid waveform \(seconds(landed)) later")
}

// MARK: - W1 — the bounded wait cancels its sleeper (issue batch B29, #178.6)

/// A previous pass that ends in 0.3 s, waited for BOUNDED: the wait returns
/// with it, and the sleeper `awaitPass` answers ends at once rather than
/// sleeping out `CacheLedger.waitLimit`.
func sleeperCancelled() {
    let previous = Task<Void, Never>.detached { _ = try? await Task.sleep(for: .seconds(0.3)) }
    let returned = Flag()
    let answered = Flag()
    let sleeperEnded = Flag()
    Task.detached {
        let sleeper = await MediaImporter.awaitPass(previous, bounded: true)
        returned.set()
        guard let sleeper else { return }
        answered.set()
        await sleeper.value
        sleeperEnded.set()
    }
    let back = waitUntil(5) { returned.isSet }
    _ = waitUntil(5) { sleeperEnded.isSet }
    let end: Double? = {
        guard let r = returned.at, let e = sleeperEnded.at else { return nil }
        return e.timeIntervalSince(r)
    }()
    row("W1", back != nil && answered.isSet && end.map { $0 <= 2 } == true,
        "the wait returned \(seconds(back)) after it was asked for; "
        + "a sleeper answered: \(answered.isSet); it ended \(seconds(end)) after the return")
}

switch scenario {
case "G0": waveformSave(announced: false)
case "G1": waveformSave(announced: true)
case "G2": stripSave(deleteFrame: true)
case "G2c": stripSave(deleteFrame: false)
case "G3": documentSave()
case "S1": heldPass()
case "S2": inputSupersedes()
case "R1": retryLands()
case "R2": retryEnds()
case "R3": retrySuperseded()
case "W1": sleeperCancelled()
default:
    FileHandle.standardError.write(Data("unknown scenario \(scenario)\n".utf8))
    exit(2)
}
finish()
