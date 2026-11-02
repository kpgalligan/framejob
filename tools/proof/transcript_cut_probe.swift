// Road map "creator-jobs" TX3a and TX3b — the word cut's and the pause token's probe (`transcript_cut_proof.py`
// builds and runs it). Compiled from `app/Sources` minus the app's
// `main.swift`, through `swift_build.py`, with THIS file as `main.swift`, so
// every row calls the app's own code: projects are made through the core
// (`ReelProject.from(json:)`), read by `TimelineTranscript.read` and `words`,
// and cut by `TranscriptCut`; words and voice caches are written here by
// hand, so every expected tick is arithmetic on this page.
//
//   transcript-cut-probe
//
// Prints one JSON object, {"rows": [{id, pass, detail}]}.
//   U1  onsets (`sourceOnsets`): E2 from a run's end less G, the run free to
//       begin before the window; E2 with no cache falls back to E1, the start
//       plus the lead; E1; E0; the clamps to the previous word's corrected end
//       and to the window; the shipped rule is TX-S3's verdict, E0.
//   U2  a run's cut: the next word's onset; the 1 s cap past a long pause;
//       an unread clip's start; no next word: the end plus G.
//   U3  crosstalk: a selected word widened over the other track's word it
//       cuts into; the next word of the same clip never taken; a locked
//       track's word never added; `wordCut(i)` == `plan(i...i).range` for
//       every token.
//   U4  the refusal order: a nested word (TX-11's sentence) before a locked
//       track's words in the range, which before the ceiling; the locked
//       sentence names the track.
//   U5  the counts: a talking head (picture and sound on two unlocked
//       tracks) cut mid-clip is N + 2 after and N + 4 at the peak; a clip
//       wholly inside is one fewer; the ceiling refuses on the peak, N the
//       peak, and not at the peak; a locked track's clips are not cut.
//   U6  the range is the core's own snap, each bound to its nearest frame, but
//       a start past the cut word's start, or an end past the next word's
//       start, is that start's frame floor.
//   U7  pause detection (TX3b, spec §11 TX-34): a 33-cell silence between two
//       words of one clip is a pause, 31 cells none; a ×2 clip's 1.5 s source
//       silence none (timeline time); the longest run, the earliest of equal
//       runs; the clip's window clamps it; under E0's early onset (a word
//       starting before the silence and ending after it) exactly one pause,
//       after the word before; two clips of one media none; a locked track's
//       words none; no voice cache none; words whose start was moved (TX1b)
//       matched on `identityTick` still give their pause; a recognised end
//       inside the silence still starts the span at its first cell (the back
//       extension); and the extension stops at the word before's start.
//   U8  a pause's cut: `[span + 0.2 s, span − 0.2 s)` snapped, exact ticks; the
//       word after's start inside raises the start past it; another shown
//       word's extent in the cut, or an unread clip's start, drops it; a cut
//       left empty after the clamp drops it.
//   U9  `planPause`: a locked track's word in the cut refused in TX-32's
//       sentence naming the track; the ceiling on the peak with N; the counts
//       equal `clipsAfter` and `clipsPeak`.
import Foundation

var rows: [[String: Any]] = []

func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}

let SEC: Ticks = 600_000
let MS: Ticks = 600
let chunk = MediaSpeech.chunkTicks

// MARK: - Fixtures (timeline_transcript_probe.swift's shapes)

func media(_ id: UInt32, path: String) -> String {
    #"{"id":\#(id),"path":"\#(path)","kind":"audio","duration":\#(60 * SEC),"has_audio":true}"#
}

func track(_ id: UInt32, locked: Bool = false, name: String? = nil) -> String {
    #"{"id":\#(id),"name":"\#(name ?? "T\(id)")","muted":false,"locked":\#(locked)}"#
}

func clip(_ id: UInt32, on: UInt32, at start: Ticks, length: Ticks, media: UInt32, from: Ticks = 0,
          speed: Double = 1)
    -> String
{
    #"{"id":\#(id),"track":\#(on),"start":\#(start),"duration":\#(length),"speed":\#(speed),"source":{"kind":"media","media":\#(media),"in":\#(from),"reversed":false},"enabled":{"video":true,"audio":true}}"#
}

func nestClip(_ id: UInt32, on: UInt32, at start: Ticks, length: Ticks, shows: UInt32) -> String {
    #"{"id":\#(id),"track":\#(on),"start":\#(start),"duration":\#(length),"source":{"kind":"nest","project":\#(shows)}}"#
}

func nest(_ id: UInt32, name: String, tracks: [String], clips: [String]) -> String {
    #"{"id":\#(id),"name":"\#(name)","width":1920,"height":1080,"tracks":[\#(tracks.joined(separator: ","))],"clips":[\#(clips.joined(separator: ","))]}"#
}

func project(media: [String], tracks: [String], clips: [String], nests: [String] = [])
    -> ReelProject?
{
    let json = #"{"version":38,"canvas":{"width":1920,"height":1080,"fps":[30,1]},"media":[\#(media.joined(separator: ","))],"tracks":[\#(tracks.joined(separator: ","))],"clips":[\#(clips.joined(separator: ","))],"markers":[],"nests":[\#(nests.joined(separator: ","))],"next_id":500}"#
    return try? ReelProject.from(json: json)
}

let urls: [UInt32: URL] = [
    1: URL(fileURLWithPath: "/fixtures/a.wav"), 2: URL(fileURLWithPath: "/fixtures/b.wav"),
    3: URL(fileURLWithPath: "/fixtures/c.wav"),
]
let mediaRows = [media(1, path: "/fixtures/a.wav"), media(2, path: "/fixtures/b.wav"),
                 media(3, path: "/fixtures/c.wav")]

/// Words of one media at (start, end) seconds, engine E0's.
func words(_ media: UInt32, _ list: [(String, Double, Double)]) -> TimelineTranscript.MediaWords {
    TimelineTranscript.MediaWords(
        media: media, engine: .apple, language: "en-US", fillersReported: false,
        words: list.map {
            TimelineTranscript.SourceWord(
                text: $0.0, source: Ticks(($0.1 * Double(SEC)).rounded()),
                sourceEnd: Ticks(($0.2 * Double(SEC)).rounded()), speaker: nil)
        })
}

/// The cut's table of `project` for `heard` (every track shown), its
/// container and its total clip count.
func table(_ project: ReelProject?, _ heard: [TimelineTranscript.MediaWords],
           rule: TranscriptCut.Rule = TranscriptCut.shipped, tracks: Set<UInt32>? = nil,
           speech: [UInt32: [Float]] = [:])
    -> (TranscriptCut.Table, ProjectSnapshot, Int)?
{
    guard let project, let plan = project.plan else { return nil }
    let snapshot = project.snapshot
    let found = TimelineTranscript.read(
        plan: plan, snapshot: snapshot, urls: urls, maps: { _, _ in nil })
    let byMedia = Dictionary(uniqueKeysWithValues: heard.map { ($0.media, $0) })
    let all = TimelineTranscript.words(found.instances, media: byMedia, snapshot: snapshot)
    let made = TranscriptCut.Table(
        all: all, tracks: tracks,
        context: TranscriptCut.Context(instances: found.instances, media: byMedia, speech: speech),
        rule: rule)
    return (made, snapshot, ShotSplit.clipCount(snapshot))
}

func describe(_ range: TranscriptCut.Range) -> String { "[\(range.start), \(range.end))" }

// MARK: - U1 onsets

do {
    let lead: Ticks = 162_000
    let guardTicks: Ticks = 38_400
    let two = [
        TimelineTranscript.SourceWord(text: "a", source: 200 * MS, sourceEnd: 600 * MS, speaker: nil),
        TimelineTranscript.SourceWord(text: "b", source: 1000 * MS, sourceEnd: 1400 * MS, speaker: nil),
    ]
    // Speech everywhere but cells 21…29 (672–960 ms): b's run ends at 960 ms,
    // inside (a's mid 670 ms, b's mid 1,470 ms].
    var speech = [Float](repeating: 0.9, count: 80)
    for k in 21...29 { speech[k] = 0.1 }
    let e2 = TranscriptCut.sourceOnsets(
        two, windowStart: 0, lead: lead, speech: speech, rule: .e2(guardTicks: guardTicks))
    let fallback = TranscriptCut.sourceOnsets(
        two, windowStart: 0, lead: lead, speech: nil, rule: .e2(guardTicks: guardTicks))
    let e1 = TranscriptCut.sourceOnsets(two, windowStart: 0, lead: lead, speech: speech, rule: .e1)
    let e0 = TranscriptCut.sourceOnsets(two, windowStart: 0, lead: 0, speech: speech, rule: .e0)
    // The clamp to the previous word's corrected end: c starts before a ends.
    let overlap = [
        two[0],
        TimelineTranscript.SourceWord(text: "c", source: 500 * MS, sourceEnd: 900 * MS, speaker: nil),
    ]
    let clamped = TranscriptCut.sourceOnsets(overlap, windowStart: 0, lead: 0, speech: nil, rule: .e0)
    // A run that begins before the window (0–288 ms non-speech, window from
    // 100 ms, d's mid 400 ms): found, its end less G.
    var early = [Float](repeating: 0.9, count: 40)
    for k in 0...8 { early[k] = 0.1 }
    let d = [TimelineTranscript.SourceWord(text: "d", source: 300 * MS, sourceEnd: 500 * MS, speaker: nil)]
    let before = TranscriptCut.sourceOnsets(
        d, windowStart: 100 * MS, lead: 0, speech: early, rule: .e2(guardTicks: guardTicks))
    let runEnd = 30 * chunk
    let want: [(String, [Ticks], [Ticks])] = [
        ("E2", e2, [200 * MS + lead, runEnd - guardTicks]),
        ("E2 no cache", fallback, [200 * MS + lead, 1000 * MS + lead]),
        ("E1", e1, [200 * MS + lead, 1000 * MS + lead]),
        ("E0", e0, [200 * MS, 1000 * MS]),
        ("clamp", clamped, [200 * MS, 600 * MS]),
        ("before window", before, [9 * chunk - guardTicks]),
    ]
    let bad = want.filter { $0.1 != $0.2 }.map { "\($0.0) \($0.1) want \($0.2)" }
    let e0Window = TranscriptCut.sourceOnsets(
        [TimelineTranscript.SourceWord(text: "e", source: 100 * MS, sourceEnd: 200 * MS, speaker: nil)],
        windowStart: 150 * MS, lead: 0, speech: nil, rule: .e0)
    row("U1", bad.isEmpty && e0Window == [150 * MS] && TranscriptCut.shipped == .e0,
        bad.isEmpty
            ? "E2 run end − G, its fallback E1 (+lead), E1, E0, the clamps and a run before the "
                + "window as written; window clamp \(e0Window); shipped \(TranscriptCut.shipped)"
            : bad.joined(separator: "; ") + "; shipped \(TranscriptCut.shipped)")
}

// MARK: - U2 the cap, the next onset, an unread clip

do {
    // a 1.0–1.4, b 1.5–1.9, then c at 8.0 s: a's cut ends at b's onset, b's at
    // its end + 1 s, c's (no next word) at its end + G (0 under E0).
    let p = project(
        media: mediaRows, tracks: [track(10)],
        clips: [clip(20, on: 10, at: 0, length: 10 * SEC, media: 1)])
    let m1 = words(1, [("a", 1.0, 1.4), ("b", 1.5, 1.9), ("c", 8.0, 8.4)])
    // The same with media 2's clip on track 11 from 2.5 s, its words unread.
    let q = project(
        media: mediaRows, tracks: [track(10), track(11)],
        clips: [clip(20, on: 10, at: 0, length: 10 * SEC, media: 1),
                clip(21, on: 11, at: 2 * SEC + SEC / 2, length: 4 * SEC, media: 2)])
    if let (t, _, _) = table(p, [m1]), let (u, _, _) = table(q, [m1]) {
        let a = t.cut(0...0), b = t.cut(1...1), c = t.cut(2...2), ab = t.cut(0...1)
        let walled = u.cut(1...1)
        let ok = a == .init(start: 1 * SEC, end: 1 * SEC + SEC / 2)
            && b == .init(start: 1 * SEC + SEC / 2, end: 2 * SEC + 9 * SEC / 10)
            && c == .init(start: 8 * SEC, end: 8 * SEC + 4 * SEC / 10)
            && ab == .init(start: 1 * SEC, end: 2 * SEC + 9 * SEC / 10)
            && walled == .init(start: 1 * SEC + SEC / 2, end: 2 * SEC + SEC / 2)
            && u.unread == [2 * SEC + SEC / 2]
        row("U2", ok,
            "a \(describe(a)), b \(describe(b)) (cap), c \(describe(c)) (no next), a…b "
                + "\(describe(ab)); unread \(u.unread), b walled \(describe(walled))")
    } else {
        row("U2", false, "no plan")
    }
}

// MARK: - U3 crosstalk and widening

do {
    // X 2.0–2.6 and z 2.7–3.0 on track 10 (media 1); Y 1.8–2.3 on track 11
    // (media 2): Y starts before X and runs into it.
    let m1 = words(1, [("w", 0.5, 0.9), ("X", 2.0, 2.6), ("z", 2.7, 3.0)])
    let m2 = words(2, [("Y", 1.8, 2.3)])
    let clips = [clip(20, on: 10, at: 0, length: 5 * SEC, media: 1),
                 clip(21, on: 11, at: 0, length: 5 * SEC, media: 2)]
    let open = project(media: mediaRows, tracks: [track(10), track(11)], clips: clips)
    let shut = project(media: mediaRows, tracks: [track(10), track(11, locked: true)], clips: clips)
    if let (t, container, total) = table(open, [m1, m2]),
        let (l, lockedContainer, _) = table(shut, [m1, m2])
    {
        let texts = (0..<t.shown.count).map { t.word($0).text }
        let x = texts.firstIndex(of: "X") ?? -1, y = texts.firstIndex(of: "Y") ?? -1
        let wide = TranscriptCut.widen(x...x, table: t, container: container)
        let alone = TranscriptCut.widen(0...0, table: t, container: container)
        let narrow = TranscriptCut.widen(x...x, table: l, container: lockedContainer)
        let fps = container.canvas.fps
        let mismatched = (0..<t.shown.count).filter {
            TranscriptCut.wordCut($0, table: t, container: container, fps: fps)
                != TranscriptCut.plan($0...$0, table: t, container: container, total: total, fps: fps).range
        }
        let ok = texts == ["w", "Y", "X", "z"] && wide == y...x && alone == 0...0
            && narrow == x...x && mismatched.isEmpty
            && TranscriptCut.wordCut(x, table: t, container: container, fps: fps).start == 18 * SEC / 10
        row("U3", ok,
            "tokens \(texts); X widened to \(wide) (want \(y)...\(x)); w alone \(alone); Y locked: "
                + "\(narrow); wordCut ≠ plan(i...i) at \(mismatched); X's wordCut "
                + describe(TranscriptCut.wordCut(x, table: t, container: container, fps: fps)))
    } else {
        row("U3", false, "no plan")
    }
}

// MARK: - U4 the refusal order

do {
    let inner = clip(42, on: 41, at: 0, length: 4 * SEC, media: 3)
    let intro = nest(40, name: "Intro", tracks: [track(41)], clips: [inner])
    let m1 = words(1, [("X", 2.0, 2.6)])
    let m2 = words(2, [("Y", 1.8, 2.3)])
    let m3 = words(3, [("n", 0.2, 0.6)])
    let p = project(
        media: mediaRows, tracks: [track(10), track(11, locked: true, name: "Music")],
        clips: [nestClip(30, on: 10, at: 0, length: 1 * SEC, shows: 40),
                clip(20, on: 10, at: 1 * SEC, length: 4 * SEC, media: 1, from: 1 * SEC),
                clip(21, on: 11, at: 0, length: 5 * SEC, media: 2)],
        nests: [intro])
    if let (t, container, total) = table(p, [m1, m2, m3]) {
        let texts = (0..<t.shown.count).map { t.word($0).text }
        let x = texts.firstIndex(of: "X") ?? -1, n = texts.firstIndex(of: "n") ?? -1
        let fps = container.canvas.fps
        let plain = TranscriptCut.plan(x...x, table: t, container: container, total: total, fps: fps)
        let both = TranscriptCut.plan(n...x, table: t, container: container, total: total, fps: fps)
        let tight = TranscriptCut.plan(
            x...x, table: t, container: container, total: total, fps: fps, ceiling: 0)
        let locked = TranscriptCut.Refusal.locked(track: "Music")
        let nested = "Inside nest Intro: open it (⌘↓) to cut its words."
        let ok = plain.refusal == locked
            && locked.sentence == "Track Music is locked and has words in this cut: unlock it to cut here."
            && both.refusal == .notEditable(nested) && tight.refusal == locked
        row("U4", ok,
            "X alone: \(plain.refusal?.sentence ?? "none"); n…X: \(both.refusal?.sentence ?? "none"); "
                + "X at ceiling 0: \(tight.refusal?.sentence ?? "none")")
    } else {
        row("U4", false, "no plan")
    }
}

// MARK: - U5 the counts and the ceiling

do {
    // A talking head: picture (track 10) and sound (track 11), both 0–10 s,
    // and a short clip at 4.0–4.2 s on track 12, wholly inside a 3–5 s cut;
    // track 13 locked, its clip spanning the cut.
    let p = project(
        media: mediaRows,
        tracks: [track(10), track(11), track(12), track(13, locked: true)],
        clips: [clip(20, on: 10, at: 0, length: 10 * SEC, media: 1),
                clip(21, on: 11, at: 0, length: 10 * SEC, media: 2),
                clip(22, on: 12, at: 4 * SEC, length: SEC / 5, media: 3),
                clip(23, on: 13, at: 0, length: 10 * SEC, media: 3)])
    if let p {
        let container = p.snapshot
        let n = ShotSplit.clipCount(container)
        let mid = TranscriptCut.Range(start: 3 * SEC, end: 5 * SEC)
        let after = TranscriptCut.clipsAfter(cutting: mid, container: container, total: n)
        let peak = TranscriptCut.clipsPeak(cutting: mid, container: container, total: n)
        // A one-word table over the talking head, its word 3.0–4.9 s with no
        // next word: the cut stops at 4 s, where the unread clip on track 12
        // starts, so that clip stays whole.
        let speech = words(1, [("w", 3.0, 4.9)])
        if let (t, c, total) = table(p, [speech]) {
            let fps = c.canvas.fps
            let ceilingAt = { (limit: Int) in
                TranscriptCut.plan(0...0, table: t, container: c, total: total, fps: fps, ceiling: limit)
            }
            let planned = ceilingAt(Int(RC_MAX_CLIPS))
            let over = ceilingAt(planned.clipsPeak - 1)
            let at = ceilingAt(planned.clipsPeak)
            let between = ceilingAt(planned.clipsAfter)
            let ok = n == 4 && after == n + 2 - 1 && peak == n + 4
                && planned.clipsAfter == n + 2 && planned.clipsPeak == n + 4
                && over.refusal == .ceiling(clips: planned.clipsPeak) && at.refusal == nil
                && between.refusal == .ceiling(clips: planned.clipsPeak)
                && over.refusal?.sentence == "This cut would make \(planned.clipsPeak) clips; a "
                    + "project holds at most \(Int(RC_MAX_CLIPS)). Lock a track that needs no cut, "
                    + "such as a music bed, or cut less."
            row("U5", ok,
                "N \(n); 3–5 s: after \(after) (want \(n + 1)), peak \(peak) (want \(n + 4)); the "
                    + "word's cut \(describe(planned.range)): after \(planned.clipsAfter), peak "
                    + "\(planned.clipsPeak); ceiling peak−1 \(over.refusal?.sentence ?? "none"); "
                    + "at peak \(at.refusal?.sentence ?? "none"); at after "
                    + "\(between.refusal?.sentence ?? "none")")
        } else {
            row("U5", false, "no plan")
        }
    } else {
        row("U5", false, "no project")
    }
}

// MARK: - U6 the core's snap

do {
    // Off the 30 fps grid (a frame is 20,000 ticks). a starts at 1.03 s
    // (618,000): its nearest frame (620,000) passes a's start, so the cut
    // starts at its floor (600,000). a's cut ends at b's onset, 1.96 s
    // (1,176,000), whose nearest frame (1,180,000) passes b's start, so the
    // end is b's floor (1,160,000). b, with no next word, ends at 2.31 s
    // (1,386,000): its nearest frame (1,380,000), not the frame after.
    let p = project(
        media: mediaRows, tracks: [track(10)],
        clips: [clip(20, on: 10, at: 0, length: 10 * SEC, media: 1)])
    let m1 = words(1, [("a", 1.03, 1.4), ("b", 1.96, 2.31)])
    if let (t, container, total) = table(p, [m1]) {
        let fps = container.canvas.fps
        let a = TranscriptCut.plan(0...0, table: t, container: container, total: total, fps: fps)
        let b = TranscriptCut.plan(1...1, table: t, container: container, total: total, fps: fps)
        let rawA = t.cut(0...0), rawB = t.cut(1...1)
        let wantA = TranscriptCut.Range(
            start: TimelineTranscript.frameFloor(t.word(0).start, fps: fps),
            end: TimelineTranscript.frameFloor(t.word(1).start, fps: fps))
        let wantB = TranscriptCut.Range(
            start: TimelineTranscript.frameFloor(t.word(1).start, fps: fps),
            end: ReelTime.snapToFrame(rawB.end, fps: fps))
        let ok = a.range == wantA && b.range == wantB && wantA == .init(start: 600_000, end: 1_160_000)
            && wantB == .init(start: 1_160_000, end: 1_380_000)
        row("U6", ok,
            "a: cut \(describe(rawA)) planned \(describe(a.range)) (want \(describe(wantA))); b: cut "
                + "\(describe(rawB)) planned \(describe(b.range)) (want \(describe(wantB)))")
    } else {
        row("U6", false, "no plan")
    }
}

// MARK: - U7–U9 the pause token (TX3b, spec §11 TX-34)

/// A voice cache of 2,000 cells (64 s), speech everywhere but `quiet`.
func cache(_ quiet: [Swift.Range<Int>]) -> [Float] {
    var out = [Float](repeating: 0.9, count: 2000)
    for run in quiet { for k in run { out[k] = 0.1 } }
    return out
}

/// The pauses of one 10 s clip of media 1 at 0 (track 10), its words
/// `list` and its cache quiet over `quiet`, plus `extra` clips and tracks.
func pausesOf(
    _ list: [(String, Double, Double)], quiet: [Swift.Range<Int>], speed: Double = 1,
    extraTracks: [String] = [], extraClips: [String] = [],
    heard more: [TimelineTranscript.MediaWords] = [], tracks: Set<UInt32>? = nil,
    noCache: Bool = false, locked: Bool = false
) -> (pauses: [TranscriptCut.Pause], table: TranscriptCut.Table, container: ProjectSnapshot, total: Int)? {
    let p = project(
        media: mediaRows, tracks: [track(10, locked: locked)] + extraTracks,
        clips: [clip(20, on: 10, at: 0, length: Ticks(Double(10 * SEC) / speed), media: 1, speed: speed)]
            + extraClips)
    let speech: [UInt32: [Float]] = noCache ? [:] : [1: cache(quiet)]
    guard let (t, container, total) = table(p, [words(1, list)] + more, tracks: tracks, speech: speech)
    else { return nil }
    return (TranscriptCut.pauses(t, fps: container.canvas.fps), t, container, total)
}

func describe(_ pauses: [TranscriptCut.Pause]) -> String {
    pauses.isEmpty ? "none"
        : pauses.map { "after \($0.after) span \(describe($0.span)) cut \(describe($0.cut))" }
            .joined(separator: "; ")
}

let ab = [("a", 1.0, 1.4), ("b", 4.0, 4.4)]

do {
    var checks: [(String, Bool, String)] = []
    // 33 cells (1,056 ms) between a (ends 1.4 s) and b: a pause; 31 none.
    if let long = pausesOf(ab, quiet: [50..<83]), let short = pausesOf(ab, quiet: [50..<81]) {
        checks.append((
            "33 cells", long.pauses.map(\.after) == [0]
                && long.pauses.first?.span == .init(start: 50 * chunk, end: 83 * chunk),
            describe(long.pauses)))
        checks.append(("31 cells", short.pauses.isEmpty, describe(short.pauses)))
    }
    // A ×2 clip: 47 cells (1.5 s of source) are 0.75 s of timeline.
    if let fast = pausesOf(ab, quiet: [50..<97], speed: 2) {
        checks.append(("×2 1.5 s source", fast.pauses.isEmpty, describe(fast.pauses)))
    }
    // Runs of 10, 40 and 40 cells: the first 40.
    if let three = pausesOf(ab, quiet: [45..<55, 56..<96, 97..<137]) {
        checks.append((
            "longest", three.pauses.first?.span == .init(start: 56 * chunk, end: 96 * chunk)
                && three.pauses.count == 1, describe(three.pauses)))
    }
    // The clip plays source 0–3 s; b (2.9–4.4 s) runs past it: the window
    // stops at 3 s (cell 93).
    if let p = project(
        media: mediaRows, tracks: [track(10)],
        clips: [clip(20, on: 10, at: 0, length: 3 * SEC, media: 1)]),
        let (t, c, _) = table(p, [words(1, [("a", 1.0, 1.4), ("b", 2.9, 4.4)])],
                              speech: [1: cache([50..<130])])
    {
        let found = TranscriptCut.pauses(t, fps: c.canvas.fps)
        checks.append((
            "window clamp", found.map(\.span) == [.init(start: 50 * chunk, end: 93 * chunk)],
            describe(found)))
    }
    // E0's early onset: a starts at 0.9 s, inside z (0.5–1.0 s), and ends at
    // 3.6 s, after the silence (cells 35–89): one pause, after z.
    if let early = pausesOf(
        [("z", 0.5, 1.0), ("a", 0.9, 3.6), ("b", 3.7, 4.0)], quiet: [35..<90])
    {
        checks.append((
            "E0 early onset", early.pauses.map(\.after) == [0]
                && early.pauses.first?.span == .init(start: 35 * chunk, end: 90 * chunk),
            describe(early.pauses)))
    }
    // Two clips of media 1: source 0–3.5 s at 0, then 3.5 s on at 3.5 s.
    if let p = project(
        media: mediaRows, tracks: [track(10)],
        clips: [clip(20, on: 10, at: 0, length: 3 * SEC + SEC / 2, media: 1),
                clip(21, on: 10, at: 3 * SEC + SEC / 2, length: 3 * SEC, media: 1,
                     from: 3 * SEC + SEC / 2)]),
        let (t, c, _) = table(p, [words(1, ab)], speech: [1: cache([50..<120])])
    {
        let found = TranscriptCut.pauses(t, fps: c.canvas.fps)
        checks.append(("two clips", t.shown.count == 2 && found.isEmpty, describe(found)))
    }
    if let shut = pausesOf(ab, quiet: [50..<83], locked: true) {
        checks.append(("locked track", shut.pauses.isEmpty, describe(shut.pauses)))
    }
    if let bare = pausesOf(ab, quiet: [50..<83], noCache: true) {
        checks.append(("no cache", bare.pauses.isEmpty, describe(bare.pauses)))
    }
    // (i) Moved starts (TX1b): a recognised at 1.0 s moved to 1.1 s, b at
    // 3.6 s moved to 4.1 s; the ids carry the recognised ticks.
    let moved = TimelineTranscript.MediaWords(
        media: 1, engine: .apple, language: "en-US", fillersReported: false,
        words: [
            TimelineTranscript.SourceWord(
                text: "a", source: 1100 * MS, sourceEnd: 1400 * MS, speaker: nil,
                recognisedStart: 1000 * MS),
            TimelineTranscript.SourceWord(
                text: "b", source: 4100 * MS, sourceEnd: 4400 * MS, speaker: nil,
                recognisedStart: 3600 * MS),
        ])
    if let p = project(
        media: mediaRows, tracks: [track(10)],
        clips: [clip(20, on: 10, at: 0, length: 10 * SEC, media: 1)]),
        let (t, c, _) = table(p, [moved], speech: [1: cache([50..<83])])
    {
        let found = TranscriptCut.pauses(t, fps: c.canvas.fps)
        checks.append((
            "moved starts", found.map(\.after) == [0]
                && found.first?.span == .init(start: 50 * chunk, end: 83 * chunk),
            describe(found)))
    }
    // (ii) a's recognised end 7 cells inside a 40-cell silence (cells
    // 50–89): the span starts at cell 50, not 57.
    if let late = pausesOf([("a", 1.0, 57 * 0.032), ("b", 4.0, 4.4)], quiet: [50..<90]) {
        checks.append((
            "late end", late.pauses.first?.span == .init(start: 50 * chunk, end: 90 * chunk)
                && late.pauses.count == 1, describe(late.pauses)))
    }
    // (iii) Quiet from cell 20, before a (1.0 s, cell 31.25) and over its own
    // cells: the extension stops at the first cell at or after a's start, 32.
    if let floor = pausesOf(ab, quiet: [20..<83]) {
        checks.append((
            "floor at a's start",
            floor.pauses.first?.span == .init(start: 32 * chunk, end: 83 * chunk)
                && floor.pauses.count == 1, describe(floor.pauses)))
    }
    let bad = checks.filter { !$0.1 }
    row("U7", checks.count == 12 && bad.isEmpty,
        "\(checks.count)/12 cases built; " + checks.map { "\($0.0): \($0.1 ? "ok" : "FAIL") (\($0.2))" }
            .joined(separator: "; "))
}

do {
    var checks: [(String, Bool, String)] = []
    let frame: Ticks = 20_000
    // Span [960,000, 1,593,600): 1,080,000 is a frame; 1,473,600 snaps to
    // 1,480,000.
    if let plain = pausesOf(ab, quiet: [50..<83]) {
        checks.append((
            "exact", plain.pauses.map(\.cut) == [.init(start: 1_080_000, end: 1_480_000)]
                && ReelTime.snapToFrame(50 * chunk + SEC / 5, fps: plain.container.canvas.fps)
                    == 1_080_000, describe(plain.pauses)))
    }
    // b starts at 3.0 s (1,800,000), inside [1,080,000, 2,380,000): the cut
    // starts on the frame after it.
    if let inside = pausesOf([("a", 1.0, 1.4), ("b", 3.0, 4.4)], quiet: [50..<130]) {
        checks.append((
            "b's start inside", inside.pauses.map(\.cut)
                == [.init(start: 1_800_000 + frame, end: 2_380_000)], describe(inside.pauses)))
    }
    // z on track 11 (0.8–2.0 s) ends inside the cut.
    if let cross = pausesOf(
        ab, quiet: [50..<83], extraTracks: [track(11)],
        extraClips: [clip(21, on: 11, at: 0, length: 10 * SEC, media: 2)],
        heard: [words(2, [("z", 0.8, 2.0)])])
    {
        let texts = (0..<cross.table.shown.count).map { cross.table.word($0).text }
        checks.append((
            "another word", texts == ["z", "a", "b"] && cross.pauses.isEmpty,
            "tokens \(texts); \(describe(cross.pauses))"))
    }
    // Media 3, with no words, starts at 2.0 s on track 12.
    if let wall = pausesOf(
        ab, quiet: [50..<83], extraTracks: [track(12)],
        extraClips: [clip(22, on: 12, at: 2 * SEC, length: SEC, media: 3)])
    {
        checks.append((
            "unread start", wall.table.unread == [2 * SEC] && wall.pauses.isEmpty,
            "unread \(wall.table.unread); \(describe(wall.pauses))"))
    }
    // b starts at 1,790,000, one frame under e (1,800,000): the clamp leaves
    // nothing.
    if let empty = pausesOf(
        [("a", 1.0, 1.4), ("b", 1_790_000.0 / Double(SEC), 3.4)], quiet: [50..<100])
    {
        checks.append(("empty", empty.pauses.isEmpty, describe(empty.pauses)))
    }
    let bad = checks.filter { !$0.1 }
    row("U8", checks.count == 5 && bad.isEmpty,
        "\(checks.count)/5 cases built; " + checks.map { "\($0.0): \($0.1 ? "ok" : "FAIL") (\($0.2))" }
            .joined(separator: "; "))
}

do {
    var checks: [(String, Bool, String)] = []
    // Words from track 10; y (2.0–2.2 s) on the locked track "Music" lies in
    // the cut.
    if let held = pausesOf(
        ab, quiet: [50..<83], extraTracks: [track(11, locked: true, name: "Music")],
        extraClips: [clip(21, on: 11, at: 0, length: 10 * SEC, media: 2)],
        heard: [words(2, [("y", 2.0, 2.2)])], tracks: [10]), let pause = held.pauses.first
    {
        let plan = TranscriptCut.planPause(
            pause, table: held.table, container: held.container, total: held.total)
        checks.append((
            "locked", plan.refusal == .locked(track: "Music")
                && plan.refusal?.sentence
                    == "Track Music is locked and has words in this cut: unlock it to cut here.",
            plan.refusal?.sentence ?? "none"))
    }
    if let plain = pausesOf(ab, quiet: [50..<83]), let pause = plain.pauses.first {
        let fit = TranscriptCut.planPause(
            pause, table: plain.table, container: plain.container, total: plain.total)
        let over = TranscriptCut.planPause(
            pause, table: plain.table, container: plain.container, total: plain.total,
            ceiling: fit.clipsPeak - 1)
        let at = TranscriptCut.planPause(
            pause, table: plain.table, container: plain.container, total: plain.total,
            ceiling: fit.clipsPeak)
        let after = TranscriptCut.clipsAfter(cutting: pause.cut, container: plain.container, total: plain.total)
        let peak = TranscriptCut.clipsPeak(cutting: pause.cut, container: plain.container, total: plain.total)
        checks.append((
            "counts", fit.clipsAfter == after && fit.clipsPeak == peak && after == plain.total + 1
                && peak == plain.total + 2 && fit.range == pause.cut && fit.refusal == nil,
            "N \(plain.total), after \(fit.clipsAfter) (\(after)), peak \(fit.clipsPeak) (\(peak))"))
        checks.append((
            "ceiling", over.refusal == .ceiling(clips: fit.clipsPeak) && at.refusal == nil,
            "peak−1: \(over.refusal?.sentence ?? "none"); at peak: \(at.refusal?.sentence ?? "none")"))
    }
    let bad = checks.filter { !$0.1 }
    row("U9", checks.count == 3 && bad.isEmpty,
        "\(checks.count)/3 cases built; " + checks.map { "\($0.0): \($0.1 ? "ok" : "FAIL") (\($0.2))" }
            .joined(separator: "; "))
}

let data = try JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
