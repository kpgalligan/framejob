// Road map creator-jobs CU1a — the cursor file's capture buffer, anchor, writer and read-back,
// driven with synthetic segments through the app's own `CursorCaptureBuffer`, `CursorAnchor`,
// `CursorFileWriter` and `ReelCursor` (spec §11 CU-10, CU-14…CU-17).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`,
// against `libframejob_core.a`, through `swift_build.py`:
//
//   cursor_capture_probe <work dir>
//
// Every file is written under `<work dir>` beside a movie path that need not exist, then
// decoded back with `JSONSerialization`. The answer is one JSON object on stdout,
// `{"rows": [...]}`, each row `{"id", "pass", "detail"}`; `cursor_capture_probe.py` prints
// and scores them.
import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: cursor_capture_probe <work dir>\n".utf8))
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

let content = CursorPixelSize(width: 3024, height: 1964)
let movie = CursorPixelSize(width: 3024, height: 1964)

func geometry(_ x: Double, scale: Double = 1) -> CursorGeometry {
    CursorGeometry(screenRect: CGRect(x: x, y: 0, width: 1512, height: 982),
                   contentRect: CGRect(x: 0, y: 0, width: 1512, height: 982),
                   contentScale: scale, scaleFactor: 2)
}

func start(_ geometry: CursorGeometry, image: CursorImageMode = .currentSystem,
           content: CursorPixelSize = content) -> CursorSegmentStart {
    CursorSegmentStart(inPicture: false, source: .display, displayID: 1,
                       sourceFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                       pointSize: CGSize(width: 1512, height: 982), pixelsPerPoint: 2,
                       contentSize: content, cursorImage: image, geometry: geometry)
}

/// A PNG as far as the core checks one: the signature, then `tag`.
func png(_ tag: UInt8) -> Data {
    Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, tag, tag, tag])
}

/// Writes `body` beside `<name>.mov` and decodes it back; the object or why not.
func written(_ body: Data?, _ name: String) -> ([String: Any]?, String?) {
    guard let body else { return (nil, "\(name): closeSegment answered nil") }
    do {
        let url = try CursorFileWriter.write(body, forMovie: work.appendingPathComponent(
            "\(name).mov"))
        guard url.lastPathComponent == "\(name).fjcursor" else {
            return (nil, "\(name): written as \(url.lastPathComponent)")
        }
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, "\(name): not a JSON object")
        }
        return (object, nil)
    } catch let problem as CursorFileProblem {
        return (nil, "\(name): refused — \(problem.message)")
    } catch {
        return (nil, "\(name): \(error)")
    }
}

func ints(_ object: [String: Any]?, _ path: String) -> [Int] {
    var value: Any? = object
    for key in path.split(separator: ".") { value = (value as? [String: Any])?[String(key)] }
    return (value as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
}

func count(_ object: [String: Any]?, _ path: String) -> Int {
    var value: Any? = object
    for key in path.split(separator: ".") { value = (value as? [String: Any])?[String(key)] }
    return (value as? [Any])?.count ?? -1
}

func geometries(_ object: [String: Any]?) -> [[String: Any]] {
    object?["geometry"] as? [[String: Any]] ?? []
}

func rectOf(_ entry: [String: Any]?) -> [Int] {
    (entry?["screen_rect"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
}

func expect(_ problems: inout [String], _ what: String, _ got: Any, _ want: Any) {
    if "\(got)" != "\(want)" { problems.append("\(what) \(got), expected \(want)") }
}

// MARK: - C1: two segments with a pause, each its own

do {
    var problems: [String] = []
    var buffer = CursorCaptureBuffer()
    buffer.openSegment(start(geometry(0)))
    buffer.image(png: png(1), hotSpot: CGPoint(x: 4, y: 4), pointSize: CGSize(width: 16,
                 height: 24), kind: .arrow, host: 100.05)
    for (i, host) in [100.1, 100.2, 100.3].enumerated() {
        buffer.move(to: CGPoint(x: Double(i), y: 5), host: host)
    }
    buffer.click(button: 0, down: true, at: CGPoint(x: 1, y: 5), count: 1, host: 100.15)
    buffer.click(button: 0, down: false, at: CGPoint(x: 1, y: 5), count: 1, host: 100.25)
    buffer.scroll(dx: 0, dy: -2, at: CGPoint(x: 1, y: 5), host: 100.2)
    let first = buffer.closeSegment(movieSize: movie,
                                    anchor: CursorAnchor.choose(e2: 100.0, e1: 99.9))
    // The pause: samples fed while closed are dropped.
    buffer.move(to: CGPoint(x: 50, y: 50), host: 105.0)
    buffer.click(button: 1, down: true, at: CGPoint(x: 50, y: 50), count: 1, host: 105.1)
    buffer.openSegment(start(geometry(700)))
    buffer.image(png: png(2), hotSpot: CGPoint(x: 8, y: 8), pointSize: CGSize(width: 16,
                 height: 16), kind: .ibeam, host: 110.52)
    buffer.move(to: CGPoint(x: 9, y: 9), host: 110.5)
    buffer.move(to: CGPoint(x: 10, y: 9), host: 110.6)
    buffer.click(button: 0, down: true, at: CGPoint(x: 10, y: 9), count: 2, host: 110.55)
    let second = buffer.closeSegment(movieSize: movie,
                                     anchor: CursorAnchor.choose(e2: 110.0, e1: 109.9))
    let (a, whyA) = written(first, "C1-segment-1")
    let (b, whyB) = written(second, "C1-segment-2")
    problems += [whyA, whyB].compactMap { $0 }
    if problems.isEmpty {
        expect(&problems, "segment 1 moves.t", ints(a, "moves.t"), [100_000, 200_000, 300_000])
        expect(&problems, "segment 1 clicks.t", ints(a, "clicks.t"), [150_000, 250_000])
        expect(&problems, "segment 1 scrolls.dy", ints(a, "scrolls.dy"), [-200])
        expect(&problems, "segment 1 images", count(a, "images"), 1)
        expect(&problems, "segment 1 image_changes.t", ints(a, "image_changes.t"), [50_000])
        expect(&problems, "segment 1 geometry", geometries(a).count, 1)
        expect(&problems, "segment 2 moves.t", ints(b, "moves.t"), [500_000, 600_000])
        expect(&problems, "segment 2 moves.x", ints(b, "moves.x"), [900, 1000])
        expect(&problems, "segment 2 clicks.t", ints(b, "clicks.t"), [550_000])
        expect(&problems, "segment 2 clicks.count", ints(b, "clicks.count"), [2])
        expect(&problems, "segment 2 scrolls", count(b, "scrolls.t"), 0)
        expect(&problems, "segment 2 images", count(b, "images"), 1)
        expect(&problems, "segment 2 image_changes", ints(b, "image_changes.id"), [0])
        expect(&problems, "segment 2 geometry", geometries(b).count, 1)
        expect(&problems, "segment 2 geometry[0].screen_rect", rectOf(geometries(b).first),
               [70_000, 0, 151_200, 98_200])
        expect(&problems, "segment 2 anchor_host_us", b?["anchor_host_us"] as? Int ?? -1,
               110_000_000)
    }
    row("C1", problems, "segment 1: 3 moves, 2 clicks, 1 scroll, 1 image from 100.0 s; "
        + "segment 2: 2 moves, 1 click, 1 image from 110.0 s, its own opening geometry; "
        + "the pause's samples dropped")
}

// MARK: - C2: three geometry changes and a repeat, three entries past the opening

do {
    var problems: [String] = []
    var buffer = CursorCaptureBuffer()
    buffer.openSegment(start(geometry(0)))
    buffer.geometry(geometry(10), host: 200.1)
    buffer.geometry(geometry(20, scale: 0.5), host: 200.2)
    buffer.geometry(geometry(20, scale: 0.5), host: 200.25)
    buffer.geometry(geometry(30), host: 200.3)
    let (file, why) = written(buffer.closeSegment(
        movieSize: movie, anchor: CursorAnchor.choose(e2: 200.0, e1: 199.9)), "C2")
    if let why { problems.append(why) }
    let entries = geometries(file)
    expect(&problems, "entries", entries.count, 4)
    expect(&problems, "t", entries.map { ($0["t"] as? Int) ?? -1 },
           [0, 100_000, 200_000, 300_000])
    expect(&problems, "screen_rect x", entries.map { rectOf($0).first ?? -1 },
           [0, 1000, 2000, 3000])
    expect(&problems, "content_scale", entries.map { ($0["content_scale"] as? Double) ?? -1 },
           [1.0, 1.0, 0.5, 1.0])
    row("C2", problems, "4 entries: the opening one (the start's, t 0) and 3 changes; "
        + "the repeat not written")
}

// MARK: - C3: E2 when given, E1 when not, named in the header

do {
    var problems: [String] = []
    let withE2 = CursorAnchor.choose(e2: 5.0, e1: 4.9)
    let withoutE2 = CursorAnchor.choose(e2: nil, e1: 4.9)
    expect(&problems, "choose(e2: 5, e1: 4.9)", "\(withE2.kind) \(withE2.host)", "e2 5.0")
    expect(&problems, "choose(e2: nil, e1: 4.9)", "\(withoutE2.kind) \(withoutE2.host)",
           "e1 4.9")
    for (name, anchor, kind, us) in [("C3-e2", withE2, "e2", 5_000_000),
                                     ("C3-e1", withoutE2, "e1", 4_900_000)] {
        var buffer = CursorCaptureBuffer()
        buffer.openSegment(start(geometry(0)))
        buffer.move(to: CGPoint(x: 1, y: 1), host: 5.5)
        let (file, why) = written(buffer.closeSegment(movieSize: movie, anchor: anchor), name)
        if let why { problems.append(why) }
        expect(&problems, "\(name) anchor", file?["anchor"] as? String ?? "?", kind)
        expect(&problems, "\(name) anchor_host_us", file?["anchor_host_us"] as? Int ?? -1, us)
    }
    row("C3", problems, "E2 5.0 s chosen and named \"e2\" (5000000 µs); without E2, E1 4.9 s "
        + "named \"e1\" (4900000 µs)")
}

// MARK: - C4: a corrupted body leaves neither file and answers the core's sentence

do {
    var problems: [String] = []
    var buffer = CursorCaptureBuffer()
    buffer.openSegment(start(geometry(0)))
    buffer.move(to: CGPoint(x: 1, y: 1), host: 1.5)
    let good = buffer.closeSegment(movieSize: movie,
                                   anchor: CursorAnchor.choose(e2: 1.0, e1: 0.9)) ?? Data()
    let text = String(decoding: good, as: UTF8.self)
    let corruptions = [
        ("version 2", text.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")),
        ("truncated", String(text.prefix(text.count / 2))),
        ("a typed key's label", text.replacingOccurrences(
            of: "\"typed\":{\"t\":[]}", with: "\"typed\":{\"label\":[\"a\"],\"t\":[]}")),
    ]
    var sentences: [String] = []
    for (index, (what, body)) in corruptions.enumerated() {
        if body == text { problems.append("\(what): the corruption did not apply"); continue }
        let bytes = Data(body.utf8)
        let movieURL = work.appendingPathComponent("C4-\(index).mov")
        let target = CursorFileWriter.url(forMovie: movieURL)
        let partial = target.appendingPathExtension("partial")
        // A file already there is replaced on success and removed on a failure.
        try? Data("stale".utf8).write(to: target)
        var sentence = "?"
        do {
            _ = try ReelCursor(data: bytes)
            problems.append("\(what): ReelCursor accepted it")
        } catch {
            sentence = (error as? ReelCoreError)?.message ?? "\(error)"
        }
        do {
            _ = try CursorFileWriter.write(bytes, forMovie: movieURL)
            problems.append("\(what): the writer kept it")
        } catch let problem as CursorFileProblem {
            if !problem.message.contains(sentence) {
                problems.append("\(what): \"\(problem.message)\" lacks \"\(sentence)\"")
            }
        } catch {
            problems.append("\(what): threw \(error)")
        }
        let files = FileManager.default
        if files.fileExists(atPath: target.path) { problems.append("\(what): .fjcursor left") }
        if files.fileExists(atPath: partial.path) { problems.append("\(what): .partial left") }
        sentences.append("\(what): \(sentence)")
    }
    row("C4", problems, "neither path left, each problem carrying the core's sentence — "
        + sentences.joined(separator: " | "))
}

// MARK: - C5: every synthetic fixture accepted, its decoded counts the stated ones

struct Fixture {
    let name: String
    let image: CursorImageMode
    let feed: (inout CursorCaptureBuffer) -> Void
    /// path → the stated values (an `[Int]`) or count (an `Int`), or a string field's value.
    let stated: [String: Any]
}

let anchor = 50.0
let fixtures: [Fixture] = [
    Fixture(name: "negative-scrolls", image: .currentSystem, feed: { b in
        b.scroll(dx: -1.5, dy: -12.25, at: CGPoint(x: 3, y: 4), host: anchor + 0.1)
        b.scroll(dx: 0.25, dy: 3, at: CGPoint(x: 3, y: 4), host: anchor + 0.2)
    }, stated: ["scrolls.dx": [-150, 25], "scrolls.dy": [-1225, 300],
                "scrolls.x": [300, 300], "cursor_image": "none"]),
    Fixture(name: "hidden-before-anchor", image: .currentSystem, feed: { b in
        b.hidden(fromHost: anchor - 2, toHost: anchor - 1)
    }, stated: ["hidden.from": 0, "hidden.to": 0]),
    Fixture(name: "hidden-across-anchor", image: .currentSystem, feed: { b in
        b.hidden(fromHost: anchor - 1, toHost: anchor + 0.5)
    }, stated: ["hidden.from": [0], "hidden.to": [500_000]]),
    Fixture(name: "hidden-overlapping-and-touching", image: .currentSystem, feed: { b in
        b.hidden(fromHost: anchor + 2, toHost: anchor + 4)
        b.hidden(fromHost: anchor + 1, toHost: anchor + 3)
        b.hidden(fromHost: anchor + 11, toHost: anchor + 12)
        b.hidden(fromHost: anchor + 10, toHost: anchor + 11)
    }, stated: ["hidden.from": [1_000_000, 10_000_000], "hidden.to": [4_000_000, 12_000_000]]),
    Fixture(name: "none-fed-images", image: .none, feed: { b in
        for tag in UInt8(1)...3 {
            b.image(png: png(tag), hotSpot: .zero, pointSize: CGSize(width: 16, height: 16),
                    kind: nil, host: anchor + Double(tag))
        }
    }, stated: ["images": 0, "image_changes.t": 0, "cursor_image": "none"]),
    Fixture(name: "before-anchor-latest-kept", image: .currentSystem, feed: { b in
        b.move(to: CGPoint(x: 1, y: 1), host: anchor - 0.3)
        b.move(to: CGPoint(x: 2, y: 2), host: anchor - 0.1)
        b.move(to: CGPoint(x: 3, y: 3), host: anchor + 0.2)
        for (tag, at) in [(UInt8(1), -0.5), (2, -0.2), (3, 0.1)] {
            b.image(png: png(tag), hotSpot: .zero, pointSize: CGSize(width: 16, height: 16),
                    kind: .arrow, host: anchor + at)
        }
        b.geometry(geometry(40), host: anchor - 0.4)
        b.click(button: 0, down: true, at: .zero, count: 1, host: anchor - 0.1)
        b.scroll(dx: 1, dy: 1, at: .zero, host: anchor - 0.1)
        b.dirty(CGRect(x: 0, y: 0, width: 1, height: 1), host: anchor - 0.1)
        b.shortcut(keys: "cmd+s", keyCode: 1, host: anchor - 0.1)
        b.typed(host: anchor - 0.1)
    }, stated: ["moves.t": [0, 200_000], "moves.x": [200, 300], "images": 3,
                "image_changes.t": [0, 100_000], "image_changes.id": [1, 2],
                "geometry": 1, "clicks.t": 0, "scrolls.t": 0, "dirty.t": 0,
                "keys.shortcut.t": 0, "keys.typed.t": 0]),
    Fixture(name: "images-interned-changes-deduped", image: .currentSystem, feed: { b in
        for (tag, at) in [(UInt8(1), 0.1), (1, 0.2), (2, 0.3), (1, 0.4), (2, 0.5)] {
            b.image(png: png(tag), hotSpot: CGPoint(x: 2, y: 3),
                    pointSize: CGSize(width: 16, height: 16), kind: nil, host: anchor + at)
        }
    }, stated: ["images": 2, "image_changes.id": [0, 1, 0, 1],
                "image_changes.t": [100_000, 300_000, 400_000, 500_000],
                "cursor_image": "current-system"]),
    Fixture(name: "events-sorted", image: .currentSystem, feed: { b in
        for at in [0.3, 0.1, 0.2] {
            b.click(button: 1, down: true, at: CGPoint(x: at, y: 0), count: 1, host: anchor + at)
        }
        b.dirty(CGRect(x: 10, y: 20, width: 30, height: 40), host: anchor + 0.2)
        b.dirty(CGRect(x: 11, y: 21, width: 31, height: 41), host: anchor + 0.1)
        b.shortcut(keys: "cmd+shift+k", keyCode: 40, host: anchor + 0.4)
        b.shortcut(keys: "ctrl+plus", keyCode: 24, host: anchor + 0.5)
        for at in [0.7, 0.6, 0.8] { b.typed(host: anchor + at) }
    }, stated: ["clicks.t": [100_000, 200_000, 300_000], "clicks.x": [10, 20, 30],
                "dirty.t": [100_000, 200_000], "dirty.w": [3100, 3000],
                "keys.shortcut.code": [40, 24], "keys.typed.t": [600_000, 700_000, 800_000]]),
]

do {
    var problems: [String] = []
    for fixture in fixtures {
        var buffer = CursorCaptureBuffer()
        buffer.openSegment(start(geometry(0), image: fixture.image))
        fixture.feed(&buffer)
        let (file, why) = written(buffer.closeSegment(
            movieSize: movie, anchor: CursorAnchor.choose(e2: anchor, e1: anchor - 0.1)),
            "C5-\(fixture.name)")
        if let why { problems.append(why); continue }
        for (path, want) in fixture.stated.sorted(by: { $0.key < $1.key }) {
            let what = "\(fixture.name) \(path)"
            if let values = want as? [Int] {
                expect(&problems, what, ints(file, path), values)
            } else if let number = want as? Int {
                expect(&problems, what, count(file, path), number)
            } else {
                expect(&problems, what, file?[path] as? String ?? "?", want)
            }
        }
    }
    row("C5", problems, "\(fixtures.count) fixtures accepted by the core, every stated count "
        + "and value decoded: " + fixtures.map(\.name).joined(separator: ", "))
}

// MARK: - C6: an odd content size and the movie's own size

do {
    var problems: [String] = []
    var buffer = CursorCaptureBuffer()
    buffer.openSegment(start(geometry(0), content: CursorPixelSize(width: 1001, height: 701)))
    let (file, why) = written(buffer.closeSegment(
        movieSize: CursorPixelSize(width: 1002, height: 702),
        anchor: CursorAnchor.choose(e2: 1.0, e1: 0.9)), "C6")
    if let why { problems.append(why) }
    expect(&problems, "movie_size", ints(file, "movie_size"), [1002, 702])
    expect(&problems, "content_size", ints(file, "content_size"), [1001, 701])
    row("C6", problems, "content_size [1001, 701], movie_size [1002, 702]")
}

let answer = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
    ?? Data("{}".utf8)
FileHandle.standardOutput.write(answer)
exit(0)
