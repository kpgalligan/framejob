// Road map "creator-jobs" TX1 — the timeline transcript's probe
// (`timeline_transcript_proof.py` builds and runs it). Compiled from
// `app/Sources` minus the app's `main.swift`, through `swift_build.py`, with
// THIS file as `main.swift`, so every row calls the app's own code: projects
// are made through the core (`ReelProject.from(json:)`, `applying`) and their
// plans and snapshots read as the app reads them; media words are written
// here by hand, so every expected placement is arithmetic on this page.
//
//   timeline-transcript-probe <work folder> <speech wav> <its duration in ticks>
//
// Prints one JSON object, {"rows": [{id, pass, detail}]}.
//   T1  order: two tracks, three media; a tie broken front track first.
//   T2  heard: a muted track's clip gives no words, its twin's do.
//   T3  a nested word at the nest clip's start plus inner time, not editable
//       with TX-11's nest sentence, nest_path the nest clip.
//   T4  a nest shown by two clips: words twice with distinct ids; a nest clip
//       shorter than its nest: only the words it plays.
//   T5  a duplicated clip: k 0 then 1; both moved later: the same ids.
//   T6  no_words: a nested clip with audio off named with its nest, a
//       reversed clip with the gate's sentence, a text clip not listed.
//   T7  TX-11: a word under a transition and one on a locked track, each
//       with its sentence; a word clear of both editable.
//   T8  the same speech twice: named once over 8 s; not over 4 s; not with
//       other words.
//   T9  the window: TR-13's empty sentence, the outside sentence, the clamp,
//       the overlap rule.
//   T10 paging: 2,001 words on distinct frames, two sharing the boundary
//       frame, all on one tick; `frameFloor` at 30, 30000/1001 and 7 fps.
//   T11 the fill: two owners want one whole-file item, one releases, the
//       other's run is stored as one run over the whole file; a third want
//       is answered from the cache without recognising (the file untouched).
//       Then, over an empty cache: d's run is under way and d releases; e
//       wants it before the cancelled run unwinds, and e's run is stored.
//       A named SKIP when this Mac has no installed speech model.
import Foundation

var rows: [[String: Any]] = []

func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}

func skip(_ id: String, _ why: String) {
    rows.append(["id": id, "skip": why])
}

let args = CommandLine.arguments
let work = URL(fileURLWithPath: args.count > 1 ? args[1] : NSTemporaryDirectory())
let speech = args.count > 2 ? URL(fileURLWithPath: args[2]) : nil
let speechTicks = args.count > 3 ? Ticks(args[3]) ?? 0 : 0
let SEC: Ticks = 600_000

// MARK: - Fixtures

func media(_ id: UInt32, path: String = "/fixtures/a.wav", duration: Ticks = 60 * SEC) -> String {
    #"{"id":\#(id),"path":"\#(path)","kind":"audio","duration":\#(duration),"has_audio":true}"#
}

func track(_ id: UInt32, muted: Bool = false, locked: Bool = false) -> String {
    #"{"id":\#(id),"name":"T\#(id)","muted":\#(muted),"locked":\#(locked)}"#
}

func clip(
    _ id: UInt32, on: UInt32, at start: Ticks, length: Ticks, media: UInt32, from: Ticks = 0,
    audio: Bool = true, reversed: Bool = false
) -> String {
    #"{"id":\#(id),"track":\#(on),"start":\#(start),"duration":\#(length),"source":{"kind":"media","media":\#(media),"in":\#(from),"reversed":\#(reversed)},"enabled":{"video":true,"audio":\#(audio)}}"#
}

func nestClip(_ id: UInt32, on: UInt32, at start: Ticks, length: Ticks, shows: UInt32) -> String {
    #"{"id":\#(id),"track":\#(on),"start":\#(start),"duration":\#(length),"source":{"kind":"nest","project":\#(shows)}}"#
}

func textClip(_ id: UInt32, on: UInt32, at start: Ticks) -> String {
    #"{"id":\#(id),"track":\#(on),"start":\#(start),"duration":\#(SEC),"source":{"kind":"text"},"text":{"content":"Hi"}}"#
}

func nest(_ id: UInt32, name: String, tracks: [String], clips: [String]) -> String {
    #"{"id":\#(id),"name":"\#(name)","width":1920,"height":1080,"tracks":[\#(tracks.joined(separator: ","))],"clips":[\#(clips.joined(separator: ","))]}"#
}

func project(
    media: [String], tracks: [String], clips: [String], nests: [String] = []
) -> ReelProject? {
    let json = #"{"version":37,"canvas":{"width":1920,"height":1080,"fps":[30,1]},"media":[\#(media.joined(separator: ","))],"tracks":[\#(tracks.joined(separator: ","))],"clips":[\#(clips.joined(separator: ","))],"markers":[],"nests":[\#(nests.joined(separator: ","))],"next_id":500}"#
    return try? ReelProject.from(json: json)
}

func words(_ media: UInt32, _ list: [(String, Double)]) -> TimelineTranscript.MediaWords {
    TimelineTranscript.MediaWords(
        media: media, engine: .apple, language: "en-US", fillersReported: false,
        words: list.map {
            TimelineTranscript.SourceWord(
                text: $0.0, source: Ticks($0.1 * Double(SEC)),
                sourceEnd: Ticks(($0.1 + 0.4) * Double(SEC)), speaker: nil)
        })
}

let urls: [UInt32: URL] = [
    1: URL(fileURLWithPath: "/fixtures/a.wav"), 2: URL(fileURLWithPath: "/fixtures/b.wav"),
    3: URL(fileURLWithPath: "/fixtures/c.wav"),
]

/// The words of `project` for `heard`, through the app's own read.
func read(_ project: ReelProject?, _ heard: [TimelineTranscript.MediaWords])
    -> (words: [TimelineTranscript.Word], instances: [TimelineTranscript.Instance],
        noWords: [TimelineTranscript.NoWords])
{
    guard let project, let plan = project.plan else { return ([], [], []) }
    let snapshot = project.snapshot
    let found = TimelineTranscript.read(
        plan: plan, snapshot: snapshot, urls: urls, maps: { _, _ in nil })
    let media = Dictionary(uniqueKeysWithValues: heard.map { ($0.media, $0) })
    return (TimelineTranscript.words(found.instances, media: media, snapshot: snapshot),
            found.instances, found.noWords)
}

func brief(_ words: [TimelineTranscript.Word]) -> String {
    words.map { "\($0.text)@\($0.start)/c\($0.clip)/t\($0.track)/k\($0.id.k)" }
        .joined(separator: " ")
}

let m1 = words(1, [("alpha", 1), ("bravo", 2)])
let m2 = words(2, [("charlie", 1), ("delta", 3)])
let m3 = words(3, [("echo", 0.5)])

// MARK: - T1 order

do {
    let p = project(
        media: [media(1), media(2), media(3)], tracks: [track(10), track(11)],
        clips: [
            clip(20, on: 10, at: 0, length: 8 * SEC, media: 1),
            clip(21, on: 11, at: 0, length: 8 * SEC, media: 2),
            clip(22, on: 10, at: 10 * SEC, length: 4 * SEC, media: 3),
        ])
    let got = read(p, [m1, m2, m3]).words
    let want = ["charlie", "alpha", "bravo", "delta", "echo"]
    let starts: [Ticks] = [SEC, SEC, 2 * SEC, 3 * SEC, 10 * SEC + SEC / 2]
    row("T1", got.map(\.text) == want && got.map(\.start) == starts
            && got.map(\.clip) == [21, 20, 20, 21, 22] && got.allSatisfy { $0.editable },
        brief(got))
}

// MARK: - T2 heard

do {
    let p = project(
        media: [media(1)], tracks: [track(10), track(12, muted: true)],
        clips: [
            clip(23, on: 12, at: 0, length: 8 * SEC, media: 1),
            clip(24, on: 10, at: 20 * SEC, length: 8 * SEC, media: 1),
        ])
    let got = read(p, [m1]).words
    row("T2", got.map(\.clip) == [24, 24] && got.map(\.start) == [21 * SEC, 22 * SEC],
        "muted clip 23, heard clip 24: \(brief(got))")
}

// MARK: - T3, T4 nests

let inner = clip(42, on: 41, at: SEC, length: 4 * SEC, media: 1)
let intro = nest(40, name: "Intro", tracks: [track(41)], clips: [inner])
let nestSentence = "Inside nest Intro: open it (⌘↓) to cut its words."
do {
    let p = project(
        media: [media(1)], tracks: [track(10)],
        clips: [nestClip(30, on: 10, at: 3 * SEC, length: 5 * SEC, shows: 40)], nests: [intro])
    let got = read(p, [m1]).words
    // Source 1 s is inner clip time 1 s, nest time 2 s, timeline 3 s + 2 s.
    row("T3", got.map(\.start) == [5 * SEC, 6 * SEC] && got.allSatisfy {
            !$0.editable && $0.why == nestSentence && $0.id.nestPath == [30] && $0.track == 10
                && $0.clip == 42
        }, brief(got) + " why \(got.first?.why ?? "nil")")
}
do {
    let p = project(
        media: [media(1)], tracks: [track(10)],
        clips: [
            nestClip(30, on: 10, at: 3 * SEC, length: 5 * SEC, shows: 40),
            nestClip(31, on: 10, at: 20 * SEC, length: 5 * SEC, shows: 40),
            nestClip(32, on: 10, at: 40 * SEC, length: 5 * SEC / 2, shows: 40),
        ], nests: [intro])
    let got = read(p, [m1]).words
    let ids = Set(got.map(\.id))
    row("T4", got.map(\.start) == [5 * SEC, 6 * SEC, 22 * SEC, 23 * SEC, 42 * SEC]
            && ids.count == got.count && got.map(\.id.nestPath) == [[30], [30], [31], [31], [32]],
        brief(got))
}

// MARK: - T5 identity

do {
    func twins(_ shift: Ticks) -> [TimelineTranscript.Word] {
        read(
            project(
                media: [media(1)], tracks: [track(10)],
                clips: [
                    clip(50, on: 10, at: shift, length: 8 * SEC, media: 1),
                    clip(51, on: 10, at: 10 * SEC + shift, length: 8 * SEC, media: 1),
                ]), [m1]
        ).words
    }
    let before = twins(0)
    let after = twins(5 * SEC)
    row("T5", before.map(\.id.k) == [0, 0, 1, 1] && Set(before.map(\.id)).count == 4
            && before.map(\.id) == after.map(\.id) && after.map(\.start) == before.map { $0.start + 5 * SEC },
        "before \(brief(before)); after \(brief(after))")
}

// MARK: - T6 no words

do {
    let off = nest(
        61, name: "Intro", tracks: [track(62)],
        clips: [clip(63, on: 62, at: 0, length: 2 * SEC, media: 1, audio: false)])
    let p = project(
        media: [media(1)], tracks: [track(10), track(11)],
        clips: [
            nestClip(60, on: 10, at: 0, length: 2 * SEC, shows: 61),
            clip(64, on: 11, at: 0, length: 2 * SEC, media: 1, reversed: true),
            textClip(65, on: 11, at: 4 * SEC),
        ], nests: [off])
    let got = read(p, [m1]).noWords
    let want = [
        TimelineTranscript.NoWords(
            clip: 63, nestPath: [60], tag: "clip 63 in nest Intro",
            reason: "its audio is switched off"),
        TimelineTranscript.NoWords(
            clip: 64, nestPath: [], tag: "clip 64",
            reason: "it plays in reverse, so its speech cannot be transcribed"),
    ]
    row("T6", p != nil && got == want, "\(got.map { "\($0.tag): \($0.reason) \($0.nestPath)" })")
}

// MARK: - T7 editability

do {
    let base = project(
        media: [media(1), media(2)], tracks: [track(10), track(11, locked: true)],
        clips: [
            clip(70, on: 10, at: 0, length: 4 * SEC, media: 1),
            clip(71, on: 10, at: 4 * SEC, length: 4 * SEC, media: 2, from: 4 * SEC),
            clip(72, on: 11, at: 20 * SEC, length: 4 * SEC, media: 1),
        ])
    let joined = try? base?.applying(.addTransition(clip: 71, kind: nil, duration: SEC)).project
    let heard = [words(1, [("alpha", 0.5), ("bravo", 3.8)]), words(2, [("charlie", 4.1), ("delta", 7)])]
    let got = read(joined, heard).words
    let wall = "Under a transition: a cut here would leave one clip's tail under its neighbour."
    let lock = "Track T11 is locked: a cut would leave these words in place and move everything "
        + "after them."
    let walls = joined.map { SilenceDetector.overlapWalls($0.snapshot) } ?? []
    let inWall = got.filter { w in walls.contains { $0.start < max(w.end, w.start + 1) && $0.end > w.start } }
    let ok = joined != nil && !walls.isEmpty && !inWall.isEmpty
        && got.filter { $0.clip != 72 }.allSatisfy { w in
            inWall.contains(w) ? (!w.editable && w.why == wall) : (w.editable && w.why == nil)
        }
        && got.filter { $0.clip == 72 }.allSatisfy { !$0.editable && $0.why == lock }
        && got.contains { $0.clip == 72 } && got.contains { $0.editable }
    row("T7", ok, "walls \(walls.map { "\($0.start)-\($0.end)" }); \(got.map { "\($0.text)@\($0.start) \($0.why ?? "editable")" })")
}

// MARK: - T8 the same speech

do {
    let said = ["the", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog", "today"]
    func list(_ m: UInt32, _ texts: [String]) -> TimelineTranscript.MediaWords {
        words(m, texts.enumerated().map { ($0.element, 0.5 + Double($0.offset) * 0.7) })
    }
    func notes(_ second: Ticks, _ heard: [TimelineTranscript.MediaWords]) -> [String] {
        let found = read(
            project(
                media: [media(1), media(2), media(3)], tracks: [track(10), track(11)],
                clips: [
                    clip(80, on: 10, at: 0, length: 8 * SEC, media: 1),
                    clip(81, on: 11, at: second, length: 8 * SEC, media: heard[1].media),
                ]), heard)
        return TimelineTranscript.sameSpeech(found.words, instances: found.instances)
    }
    let same = notes(0, [list(1, said), list(2, said)])
    let short = notes(4 * SEC, [list(1, said), list(2, said)])
    let other = notes(0, [list(1, said), list(3, said.map { $0 + "x" })])
    let want = ["Clips 80 and 81 carry the same speech. Mute one, or switch its audio off, to read it once."]
    row("T8", same == want && short.isEmpty && other.isEmpty,
        "8 s overlap \(same); 4 s \(short); other words \(other)")
}

// MARK: - T9 the window

do {
    var problems: [String] = []
    func refusal(_ from: Ticks?, _ to: Ticks?) -> String {
        do {
            _ = try TimelineTranscript.window(from: from, to: to, duration: 10 * SEC)
            return "none"
        } catch { return error.localizedDescription }
    }
    let empty = refusal(SEC, SEC)
    if empty != "to must be after from: the window from 600000 to 600000 ticks (both snapped to "
        + "frames) is empty." { problems.append("empty: \(empty)") }
    let outside = refusal(100 * SEC, nil)
    if outside != "The window from 60000000 is outside the timeline, which runs from 0 to "
        + "6000000 ticks." { problems.append("outside: \(outside)") }
    let clamped = try? TimelineTranscript.window(from: -SEC, to: 20 * SEC, duration: 10 * SEC)
    if clamped != TranscriptReader.Window(from: 0, to: 10 * SEC) { problems.append("clamp \(String(describing: clamped))") }
    if (try? TimelineTranscript.window(from: nil, to: nil, duration: 10 * SEC)) != .some(nil) {
        problems.append("no bounds is not nil")
    }
    let list = read(
        project(media: [media(1)], tracks: [track(10)],
                clips: [clip(90, on: 10, at: 0, length: 8 * SEC, media: 1)]), [m1]).words
    // alpha [1 s, 1.4 s), bravo [2 s, 2.4 s): a window [1.2 s, 2 s) keeps alpha only.
    let kept = TimelineTranscript.overlapping(list, in: TranscriptReader.Window(from: 6 * SEC / 5, to: 2 * SEC))
    if kept.map(\.text) != ["alpha"] { problems.append("overlap \(brief(kept))") }
    row("T9", problems.isEmpty, problems.isEmpty ? "TR-13's sentences, the clamp and the overlap" : problems.joined(separator: "; "))
}

// MARK: - T10 paging

do {
    let fps = Fps(num: 30, den: 1)
    func word(_ i: Int, _ start: Ticks) -> TimelineTranscript.Word {
        TimelineTranscript.Word(
            text: "w\(i)", start: start, end: start + 10_000, clip: 1, track: 1, media: 1,
            engine: .apple, filler: false, speaker: nil, editable: true, why: nil,
            id: TimelineTranscript.Identity(nestPath: [], media: 1, source: start, k: 0))
    }
    var problems: [String] = []
    // Distinct frames: 40,000 ticks apart (two frames each).
    let distinct = (0...2000).map { word($0, Ticks($0) * 40_000) }
    let a = TimelineTranscript.page(distinct, fps: fps)
    if a.words.count != 2000 || a.nextFrom != 2000 * 40_000 {
        problems.append("distinct: \(a.words.count), next \(String(describing: a.nextFrom))")
    }
    // Words 1999 and 2000 share a frame: the page stops before 1999.
    var shared = distinct
    shared[2000] = word(2000, shared[1999].start + 5_000)
    let b = TimelineTranscript.page(shared, fps: fps)
    if b.words.count != 1999 || b.nextFrom != 1999 * 40_000 {
        problems.append("shared: \(b.words.count), next \(String(describing: b.nextFrom))")
    }
    // Every word on one tick: the page stays whole, next the boundary after.
    let one = (0...2000).map { word($0, 7 * 20_000 + 3) }
    let c = TimelineTranscript.page(one, fps: fps)
    if c.words.count != 2000 || c.nextFrom != 8 * 20_000 {
        problems.append("one tick: \(c.words.count), next \(String(describing: c.nextFrom))")
    }
    if TimelineTranscript.page(Array(distinct.prefix(2000)), fps: fps).nextFrom != nil {
        problems.append("2000 words paged")
    }
    for rate in [Fps(num: 30, den: 1), Fps(num: 30000, den: 1001), Fps(num: 7, den: 1)] {
        for t: Ticks in [0, 1, 19_999, 20_000, 20_019, 20_021, 85_714, 85_715, 1_234_567] {
            let f = TimelineTranscript.frameFloor(t, fps: rate)
            if f > t || ReelTime.snapToFrame(f, fps: rate) != f
                || ReelTime.snapToFrame(f + rate.frameDuration, fps: rate) <= t {
                problems.append("frameFloor(\(t)) at \(rate.num)/\(rate.den) = \(f)")
            }
        }
    }
    row("T10", problems.isEmpty, problems.isEmpty
        ? "2000 then next 80000000; 1999 then 79960000; one tick whole then 160000; frameFloor at 3 rates"
        : problems.joined(separator: "; "))
}

// MARK: - T11 the fill

func fillRow() {
    guard let speech, speechTicks > 0 else { return skip("T11", "no speech file was given") }
    let languages = Transcriber.languages()
    guard let language = Transcriber.defaultLanguage(in: languages) else {
        return skip("T11", "this Mac has no installed on-device speech model")
    }
    let cache = work.appendingPathComponent("cache", isDirectory: true)
    try? FileManager.default.removeItem(at: cache)
    try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    guard
        let p = project(
            media: [media(1, path: speech.path, duration: speechTicks)], tracks: [track(10)],
            clips: [clip(95, on: 10, at: 0, length: speechTicks, media: 1)]),
        let record = p.snapshot.media(1),
        let stamp = DeviceTranscriptCache.currentStamp(record, url: speech, language: language.identifier)
    else { return row("T11", false, "the fixture project or its stamp could not be made") }
    let key = RecipeSource.shared.register()
    RecipeSource.shared.set(p, for: key)
    defer { RecipeSource.shared.unregister(key) }
    let item = TranscriptFill.Item(
        media: 1, url: speech, name: speech.lastPathComponent, duration: speechTicks, stamp: stamp,
        cacheDir: cache, language: language, record: record)
    let fill = TranscriptFill(key: key)
    let a = fill.newOwner()
    let b = fill.newOwner()
    fill.want(owner: a, items: [item])
    fill.want(owner: b, items: [item])
    fill.release(owner: b)
    let gotB = fill.wait(owner: b)
    let gotA = fill.wait(owner: a)
    fill.release(owner: a)
    let file = DeviceTranscriptCache.fileURL(for: 1, language: language.identifier, in: cache)
    let stored = DeviceTranscriptCache.read(for: 1, language: language.identifier, in: cache)
    let modified = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
    let c = fill.newOwner()
    fill.want(owner: c, items: [item])
    let gotC = fill.wait(owner: c)
    fill.release(owner: c)
    let after = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
    let runs = stored?.runs ?? []
    // Rewanted while unwinding: a fresh cache, so the run recognises.
    let cache2 = work.appendingPathComponent("cache-rewant", isDirectory: true)
    try? FileManager.default.removeItem(at: cache2)
    try? FileManager.default.createDirectory(at: cache2, withIntermediateDirectories: true)
    let item2 = TranscriptFill.Item(
        media: 1, url: speech, name: speech.lastPathComponent, duration: speechTicks, stamp: stamp,
        cacheDir: cache2, language: language, record: record)
    let fill2 = TranscriptFill(key: key)
    let d = fill2.newOwner()
    let e = fill2.newOwner()
    fill2.want(owner: d, items: [item2])
    let deadline = Date().addingTimeInterval(60)
    while fill2.progress() == nil && Date() < deadline { usleep(1000) }
    let underway = fill2.progress() != nil
    fill2.release(owner: d)
    fill2.want(owner: e, items: [item2])
    let gotD = fill2.wait(owner: d)
    let gotE = fill2.wait(owner: e)
    fill2.release(owner: e)
    let stored2 = DeviceTranscriptCache.read(for: 1, language: language.identifier, in: cache2)
    let rewanted = underway && gotD == [1: .cancelled] && gotE == [1: .stored]
        && stored2?.runs.count == 1
    let ok = gotA == [1: .stored] && gotB == [1: .cancelled] && gotC == [1: .stored]
        && runs.count == 1 && runs.first?.sourceIn == 0 && runs.first?.sourceLength == speechTicks
        && !(runs.first?.words.isEmpty ?? true) && modified != nil && modified == after && rewanted
    row("T11", ok,
        "owner a \(gotA), released b \(gotB), again c \(gotC); \(runs.count) run(s) "
            + "\(runs.map { "[\($0.sourceIn), +\($0.sourceLength)) \($0.words.count) words" }); "
            + "file untouched by the third want \(modified != nil && modified == after); "
            + "under way \(underway), released d \(gotD), rewanted e \(gotE), "
            + "\(stored2?.runs.count ?? 0) run(s) stored for e")
}
fillRow()

let answer = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys])) ?? Data()
print(String(decoding: answer, as: UTF8.self))
