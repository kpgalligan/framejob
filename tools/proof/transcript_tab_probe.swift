// Road map "creator-jobs" TX2a — the Transcript tab's probe
// (`transcript_tab_proof.py` builds and runs it). Compiled from `app/Sources`
// minus the app's `main.swift`, through `swift_build.py` with `-D
// FRAMEJOB_DEV_TOOLS`, with THIS file as `main.swift`; the app's
// `Compositor.metal` is built beside it (`space_key_proof.build_shader`).
//
//   transcript-tab-probe <package> --fonts <folder>
//
// The package holds media 20 (a silent WAV) under clip 3 (0–60 s) and clip 4
// (70–130 s), both from source 0. Its editor window is the app's own
// (`ProjectDocument.makeWindowControllers()`, as in `space_key_probe.swift`)
// and the words arrive through `TranscriptTabSource.preload`: nothing is
// recognised. Prints one JSON object, {"rows": [{id, pass, detail}]}.
//   T1  at strip width 280 each title's `DS.sans(12, weight: .semibold)`
//       width is at most its `PanelTabsView.tabRect` width.
//   T3p `highlight(at:)` inside a 1 s gap answers the word before.
//   T5  Space, J and L sent to the focused view play, shuttle back and
//       shuttle forward (read from `editor.playback`); ← selects and seeks
//       to the previous word's frame-snapped start.
//   T4p a click on a word while playing puts the playhead at its frame-snapped
//       start and playback goes on.
//   T7  a live trim leaves `rebuilds` unchanged until it ends, then adds 1.
//   T8  with `now` injected, a person scroll at t followed by a far
//       highlight at t + 1 s does not scroll; at t + 3.1 s it does.
//   T9  the break rule on gaps of 1.2 s and 1.6 s, with and without a voice
//       cache, a voiced 1.6 s gap, across instances, a track change and a
//       speaker change.
//   T10 `clipPicked()` keeps the Transcript tab and brings the clip's first
//       token to the top; from Media it still shows Clip.
//   T13p a ⇧-extension's anchor across a rebuild that shrinks the text: the
//       first word dropped, ⇧← extends from the anchor's word; the text cut
//       to 3 words under the selection, ⇧→ stays inside the text and the
//       next rebuild does not trap.
import AppKit

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": String(detail.prefix(1500))])
}

let args = CommandLine.arguments
let package = args.count > 1 ? args[1] : ""
if let at = args.firstIndex(of: "--fonts"), at + 1 < args.count {
    let folder = URL(fileURLWithPath: args[at + 1])
    for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
        CTFontManagerRegisterFontsForURL(folder.appendingPathComponent(name) as CFURL, .process, nil)
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

let SEC: Ticks = 600_000

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
}

func until(_ seconds: Double, _ done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !done(), Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    return done()
}

func word(
    _ text: String, _ start: Double, _ end: Double, clip: UInt32 = 3, track: UInt32 = 1,
    media: UInt32 = 20, source: Double? = nil, speaker: String? = nil, nest: [UInt32] = []
) -> TimelineTranscript.Word {
    TimelineTranscript.Word(
        text: text, start: Ticks(start * Double(SEC)), end: Ticks(end * Double(SEC)), clip: clip,
        track: track, media: media, engine: .apple, filler: false, speaker: speaker, editable: true,
        why: nil,
        id: TimelineTranscript.Identity(
            nestPath: nest, media: media, source: Ticks((source ?? start) * Double(SEC)), k: 0))
}

func sourceWord(_ start: Double, _ end: Double) -> TimelineTranscript.SourceWord {
    TimelineTranscript.SourceWord(
        text: "w", source: Ticks(start * Double(SEC)), sourceEnd: Ticks(end * Double(SEC)),
        speaker: nil)
}

func key(_ code: UInt16, _ characters: String, window: NSWindow) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
}

// MARK: - T1 the titles fit at 280 pt

do {
    let font = DS.sans(12, weight: .semibold)
    let width = 280 / CGFloat(InspectorTab.allCases.count)
    var detail: [String] = []
    var pass = true
    for tab in InspectorTab.allCases {
        let left = (CGFloat(tab.rawValue) * width).rounded()
        let right = (CGFloat(tab.rawValue + 1) * width).rounded()
        let title = tab.title.size(withAttributes: [.font: font]).width
        pass = pass && title <= right - left
        detail.append("\(tab.title) \(String(format: "%.1f", title)) in \(Int(right - left))")
    }
    row("T1", pass && font.fontName.hasPrefix("SourceSans3"), "\(font.fontName): " + detail.joined(separator: "; "))
}

// MARK: - T3p the highlight in a gap

do {
    let model = TranscriptTokens.build(
        [word("one", 0, 0.4), word("two", 0.5, 0.9), word("three", 1.9, 2.3)], pauses: [:])
    let inGap = model.highlight(at: Ticks(1.4 * Double(SEC)))
    let before = model.highlight(at: -1)
    let onThird = model.highlight(at: Ticks(1.9 * Double(SEC)))
    row("T3p", inGap == 1 && before == nil && onThird == 2,
        "inside the 1 s gap \(String(describing: inGap)) (want 1); before the first "
            + "\(String(describing: before)); at the third's start \(String(describing: onThird))")
}

// MARK: - T9 the break rule

do {
    // A 0–0.4, B 1.6–2.0 (1.2 s after A), C 3.6–4.0 (1.6 s after B).
    let source = [sourceWord(0, 0.4), sourceWord(1.6, 2.0), sourceWord(3.6, 4.0)]
    let chunk = Double(MediaSpeech.chunkTicks) / Double(SEC)
    func cache(voicedGaps: Bool) -> [Float] {
        (0..<Int(4.2 / chunk)).map { k in
            let t = Double(k) * chunk
            let inWord = source.contains {
                t >= Double($0.source) / Double(SEC) - chunk && t < Double($0.sourceEnd) / Double(SEC)
            }
            return inWord || voicedGaps ? 1 : 0
        }
    }
    let confidence = Float(SilenceDetector.Settings.defaultVoiceConfidence)
    let noCache = TranscriptTokens.pauses(source, speech: nil, confidence: confidence)
    let withCache = TranscriptTokens.pauses(source, speech: cache(voicedGaps: false), confidence: confidence)
    let voiced = TranscriptTokens.pauses(source, speech: cache(voicedGaps: true), confidence: confidence)
    let b = source[1].source
    let within = TranscriptTokens.build(
        [word("a", 0, 0.4), word("b", 1.6, 2.0), word("c", 3.6, 4.0)], pauses: [20: withCache])
    let across = TranscriptTokens.build(
        [word("a", 0, 0.4, clip: 3), word("b", 1.6, 2.0, clip: 5), word("c", 3.6, 4.0, clip: 6)],
        pauses: [:])
    let track = TranscriptTokens.build(
        [word("a", 0, 0.4, track: 1), word("b", 0.5, 0.9, track: 2)], pauses: [:])
    let speaker = TranscriptTokens.build(
        [word("a", 0, 0.4, speaker: "A"), word("b", 0.5, 0.9, speaker: "B")], pauses: [:])
    let firsts = { (m: TranscriptTokens) in m.paragraphs.map(\.firstToken) }
    let pass = noCache == [b] && withCache == [b] && voiced.isEmpty
        && firsts(within) == [0, 2] && firsts(across) == [0, 2] && firsts(track) == [0, 1]
        && firsts(speaker) == [0, 1]
    row("T9", pass,
        "pauses without a cache \(noCache.sorted()), with \(withCache.sorted()), voiced gaps "
            + "\(voiced.sorted()) (want [\(b)], [\(b)], []); paragraph starts within one "
            + "instance \(firsts(within)), across instances \(firsts(across)), a track change "
            + "\(firsts(track)), a speaker change \(firsts(speaker))")
}

// MARK: - T8 the follow pause

do {
    let window = NSWindow(
        contentRect: NSRect(x: -20_000, y: 0, width: 304, height: 600), styleMask: [.titled],
        backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 304, height: 600))
    scroll.hasVerticalScroller = true
    let view = TranscriptView(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: 600))
    view.autoresizingMask = [.width]
    scroll.documentView = view
    window.contentView = scroll
    window.orderFrontRegardless()
    let words = (0..<3000).map { word("word\($0)", Double($0) * 0.3, Double($0) * 0.3 + 0.25) }
    view.show(TranscriptTokens.build(words, pauses: [:]), fps: Fps(num: 30, den: 1), timecodeFrames: true)
    spin(0.1)
    var clock: TimeInterval = 1000
    view.now = { clock }
    NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
    spin(0.1)
    clock = 1001
    let before = view.visibleRect.minY
    view.setHighlight(2000, follow: true)
    let held = view.visibleRect.minY
    clock = 1003.1
    view.setHighlight(2500, follow: true)
    let followed = view.visibleRect
    let target = view.rects(forToken: 2500).first ?? .zero
    row("T8", view.lastPersonScroll == 1000 && held == before && followed.minY != before
            && followed.intersects(target),
        "person scroll noted at \(String(describing: view.lastPersonScroll)); top \(before) → "
            + "\(held) one second later (want unchanged) → \(followed.minY) at 3.1 s; token 2500 at "
            + "\(target.minY) in sight \(followed.intersects(target))")
    window.orderOut(nil)
}

// MARK: - T13p the ⇧ anchor across a shrinking rebuild

do {
    let window = NSWindow(
        contentRect: NSRect(x: -20_000, y: 0, width: 304, height: 400), styleMask: [.titled],
        backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 304, height: 400))
    let view = TranscriptView(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: 400))
    view.autoresizingMask = [.width]
    scroll.documentView = view
    window.contentView = scroll
    window.orderFrontRegardless()
    let fps = Fps(num: 30, den: 1)
    let ten = (0..<10).map { word("w\($0)", Double($0) * 0.3, Double($0) * 0.3 + 0.25) }
    func shift(_ arrow: Int) {
        let text = String(Character(UnicodeScalar(arrow)!))
        let code: UInt16 = arrow == NSLeftArrowFunctionKey ? 123 : 124
        if let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: text,
            charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)
        {
            view.keyDown(with: event)
        }
    }
    func shown(_ words: [TimelineTranscript.Word]) {
        view.show(TranscriptTokens.build(words, pauses: [:]), fps: fps, timecodeFrames: true)
    }
    // Words 0…9, word 4 selected, ⇧← → 3...4 anchored at word 4; word 0
    // dropped → 2...3; ⇧← extends from word 4 (now 3) → 1...3.
    shown(ten)
    view.select(4...4)
    shift(NSLeftArrowFunctionKey)
    let first = view.selection
    shown(Array(ten.dropFirst()))
    let remapped = view.selection
    shift(NSLeftArrowFunctionKey)
    let followed = view.selection
    // Words 0…9 again, 6...7 by ⇧→ anchored at 6; cut to words 0…2 (the
    // selection's words gone), then ⇧→ and a rebuild.
    shown(ten)
    view.select(6...6)
    shift(NSRightArrowFunctionKey)
    let extended = view.selection
    shown(Array(ten.prefix(3)))
    shift(NSRightArrowFunctionKey)
    let shrunk = view.selection
    let count = view.model.tokens.count
    let valid = (shrunk.map { $0.lowerBound >= 0 && $0.upperBound < count } ?? true)
        && (view.selectionAnchor.map { $0 >= 0 && $0 < count } ?? true)
    // A rebuild over a selection past the text traps; it runs only when valid.
    if valid { shown(Array(ten.prefix(3))) }
    row("T13p", first == 3...4 && remapped == 2...3 && followed == 1...3 && extended == 6...7 && valid,
        "⇧← from 4 \(String(describing: first)) (want 3...4); word 0 dropped "
            + "\(String(describing: remapped)) (want 2...3); ⇧← again \(String(describing: followed)) "
            + "(want 1...3); ⇧→ from 6 \(String(describing: extended)) (want 6...7); cut to 3 words, "
            + "⇧→ \(String(describing: shrunk)), anchor \(String(describing: view.selectionAnchor)) "
            + "(want inside 0...2); rebuilt \(valid)")
    window.orderOut(nil)
}

// MARK: - The editor rows

// Words every 0.15 s of the 120 s file, so both clips show 400 each.
let heard = TimelineTranscript.MediaWords(
    media: 20, engine: .apple, language: "en-US", fillersReported: false,
    words: (0..<800).map { (n: Int) -> TimelineTranscript.SourceWord in
        let at = Double(n) * 0.15
        return TimelineTranscript.SourceWord(
            text: "spoken\(n)", source: Ticks(at * Double(SEC)),
            sourceEnd: Ticks((at + 0.1) * Double(SEC)), speaker: nil)
    })

func openEditor() -> (ProjectDocument, EditorViewController, NSWindow, TranscriptPane)? {
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: package), ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        return nil
    }
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.5)
    guard let window = document.windowControllers.first?.window,
        let editor = window.contentViewController as? EditorViewController
    else { return nil }
    window.appearance = NSAppearance(named: .aqua)
    editor.showTranscript(nil)
    guard let inspector = editor.inspector, let pane = TranscriptPane.pane(in: inspector) else {
        return nil
    }
    pane.source.preload([20: heard], pauses: [20: []])
    _ = until(5) { pane.source.settled }
    spin(0.3)
    return (document, editor, window, pane)
}

if let (document, editor, window, pane) = openEditor() {
    let view = pane.transcriptView
    let model = { pane.source.model }
    let fps = document.editedProject.snapshot.canvas.fps
    func send(_ event: NSEvent?) { if let event { window.sendEvent(event) } }

    // T5 the keys.
    let focused = window.firstResponder === view
    editor.setPlayhead(20 * SEC)
    spin(0.5)
    send(key(49, " ", window: window))
    let played = until(2) { editor.playback.isPlaying }
    send(key(49, " ", window: window))
    let paused = until(2) { !editor.playback.isPlaying }
    send(key(38, "j", window: window))
    let back = until(2) { editor.playback.rate < 0 }
    let backRate = editor.playback.rate
    send(key(40, "k", window: window))
    _ = until(2) { !editor.playback.isPlaying }
    send(key(37, "l", window: window))
    let forward = until(2) { editor.playback.rate > 0 }
    let forwardRate = editor.playback.rate
    editor.playback.pause()
    spin(0.3)
    view.select(10...10)
    send(key(123, String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), window: window))
    spin(0.3)
    let want = ReelTime.snapToFrame(model().tokens[9].word.start, fps: fps)
    row("T5", focused && played && paused && back && forward && view.selection == 9...9
            && document.playhead == want,
        "view first responder \(focused); Space played \(played), paused \(paused); J rate "
            + "\(backRate); L rate \(forwardRate); ← selection \(String(describing: view.selection)) "
            + "(want 9...9), playhead \(document.playhead) (want \(want))")

    // T4p a click while playing keeps playing (no MCP door starts playback).
    editor.setPlayhead(5 * SEC)
    editor.playPause(nil)
    let playing = until(2) { editor.playback.isPlaying }
    view.click(token: 40)
    let clicked = document.playhead
    let wanted = ReelTime.snapToFrame(model().tokens[40].word.start, fps: fps)
    spin(0.4)
    let still = editor.playback.isPlaying
    editor.playback.pause()
    spin(0.3)
    row("T4p", playing && clicked == wanted && still && view.selection == 40...40,
        "playing before \(playing); playhead after the click \(clicked) (want \(wanted)); still "
            + "playing \(still); selection \(String(describing: view.selection))")

    // T10 a click on a clip keeps the tab and scrolls to it.
    guard let inspector = editor.inspector else { exit(1) }
    view.scrollToToken(0)
    document.selection = [4]
    inspector.clipPicked()
    spin(0.3)
    let firstOf4 = model().tokens.firstIndex { $0.word.clip == 4 }
    let kept = inspector.tab == .transcript
    let top = view.topVisibleToken()
    let geometry = "view \(view.frame); visible \(view.visibleRect); clip "
        + "\(String(describing: view.enclosingScrollView?.contentView.bounds)); token rect "
        + "\(String(describing: firstOf4.flatMap { view.rects(forToken: $0).first }))"
    inspector.select(.media)
    document.selection = [3]
    inspector.clipPicked()
    spin(0.2)
    row("T10", kept && firstOf4 != nil && top == firstOf4 && inspector.tab == .clip,
        "tab after the click \(kept ? "transcript" : "other"); top token \(String(describing: top)) "
            + "(want clip 4's first, \(String(describing: firstOf4))); from Media the click shows "
            + "\(inspector.tab.title); \(geometry)")

    // T7 a live trim, the tab shown again (hiding it dropped its words).
    inspector.select(.transcript)
    pane.source.preload([20: heard], pauses: [20: []])
    _ = until(5) { pane.source.settled }
    spin(0.3)
    let r0 = pane.source.rebuilds
    document.beginLiveEdit()
    for end in [100, 95, 90] {
        editor.timelineLiveUpdated([.trimEnd(clip: 4, to: Ticks(end) * SEC)])
        spin(0.1)
    }
    let during = pane.source.rebuilds
    editor.timelineLiveEnded("Trim")
    _ = until(2) { pane.source.rebuilds != r0 }
    spin(0.2)
    let after = pane.source.rebuilds
    row("T7", during == r0 && after == r0 + 1,
        "rebuilds \(r0) before, \(during) during three live ticks, \(after) after the gesture "
            + "(want \(r0), \(r0 + 1))")

    // T14p a drag past a line's end or before its start: the line answers
    // NSNotFound off its glyphs, and the offset is the line's last or first
    // character, inside the text, never a trap (the owner's CP1 crash).
    view.scrollToToken(0)
    spin(0.2)
    let length = view.offset(of: view.contentStorage.documentRange.endLocation)
    var offsets: [String: Int] = [:]
    var notes: [String] = []
    if let line = view.rects(forToken: 0).first {
        for (name, x) in [("left", CGFloat(0)), ("far left", CGFloat(-400)),
                          ("right", view.bounds.maxX - 1), ("far right", view.bounds.maxX + 400)] {
            let offset = view.characterOffset(at: NSPoint(x: x, y: line.midY))
            notes.append("\(name) \(String(describing: offset))")
            offsets[name] = offset
        }
    } else {
        notes.append("token 0 has no rect")
    }
    let inside = offsets.count == 4 && offsets.values.allSatisfy { $0 >= 0 && $0 < length }
    let ordered = inside && offsets["left"] == offsets["far left"]
        && offsets["left"]! < offsets["right"]! && offsets["left"]! < offsets["far right"]!
    // A drag's path: every 1 pt down the first 400 pt (lines, the gaps between
    // them and between paragraphs, the timecodes) at nine x positions.
    var swept = 0, answered = 0, outside: [String] = []
    for y in stride(from: CGFloat(-20), through: 400, by: 1) {
        for x in [-400, -1, 0, 4, 12, 60, 150, view.bounds.maxX - 1, view.bounds.maxX + 400] as [CGFloat] {
            swept += 1
            guard let offset = view.characterOffset(at: NSPoint(x: x, y: y)) else { continue }
            answered += 1
            if offset < 0 || offset > length, outside.count < 5 { outside.append("(\(x), \(y)) → \(offset)") }
        }
    }
    notes.append("swept \(swept) points, \(answered) answered, outside the text: \(outside)")
    // T15p a press on a word and a drag along its line, paused and then
    // looping while playing: the scroll stays where it was (the owner's CP1
    // note, 2026-11-06: "The text view scrolls vertically, even when I'm
    // just trying to select horizontally").
    func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type, location: view.convert(point, to: nil), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    }
    // `band`: the line in the middle third of what shows, the top one or the
    // bottom one fully shown; `wobble`: the pointer drifts ±3 pt as a hand's
    // does; `past`: the drag runs 80 pt past the view's right edge.
    func dragAlongLine(_ label: String, band: String, wobble: Bool, past: Bool) -> String {
        let clip = view.enclosingScrollView?.contentView
        let shown = view.visibleRect
        let fits = { (r: CGRect) -> Bool in
            switch band {
            case "top": return r.minY >= shown.minY && r.minY < shown.minY + 24
            case "bottom": return r.maxY <= shown.maxY && r.maxY > shown.maxY - 24
            default: return r.minY > shown.minY + shown.height / 3 && r.maxY < shown.maxY - shown.height / 3
            }
        }
        guard
            let start = (0..<model().tokens.count).first(where: { index in
                guard let r = view.rects(forToken: index).first else { return false }
                return fits(r) && r.midX < shown.midX
            }), let rect = view.rects(forToken: start).first,
            let down = mouse(.leftMouseDown, NSPoint(x: rect.midX, y: rect.midY))
        else { return "\(label): no word in the \(band) band" }
        let before = clip?.bounds.origin.y ?? -1
        view.mouseDown(with: down)
        spin(0.05)
        var ys: [CGFloat] = []
        var step = 0
        for x in stride(from: rect.midX, through: shown.maxX + (past ? 80 : -2), by: 8) {
            let dy: CGFloat = wobble ? (step % 2 == 0 ? 3 : -3) : 0
            step += 1
            if let drag = mouse(.leftMouseDragged, NSPoint(x: x, y: rect.midY + dy)) { view.mouseDragged(with: drag) }
            spin(0.03)
            ys.append(clip?.bounds.origin.y ?? -1)
        }
        if let up = mouse(.leftMouseUp, NSPoint(x: shown.maxX - 2, y: rect.midY)) { view.mouseUp(with: up) }
        spin(0.2)
        let after = clip?.bounds.origin.y ?? -1
        let moved = Set((ys + [after]).filter { abs($0 - before) > 0.5 })
        return "\(label) \(band)\(wobble ? " wobbling" : "")\(past ? " past the edge" : ""): word "
            + "\(start), top \(before) before, \(ys.count) drag steps, top after \(after), other tops "
            + "seen \(moved.sorted()), selection \(String(describing: view.selection))"
    }
    var drags: [String] = []
    for playing in [false, true] {
        if playing {
            editor.toggleLoop(nil)
            editor.playPause(nil)
            _ = until(2) { editor.playback.isPlaying }
        }
        for band in ["middle", "top", "bottom"] {
            for (wobble, past) in [(false, false), (true, false), (false, true)] {
                view.scrollToToken(120)
                spin(0.3)
                drags.append(dragAlongLine(playing ? "looping" : "paused", band: band, wobble: wobble, past: past))
            }
        }
        if playing {
            editor.playback.pause()
            editor.toggleLoop(nil)
            spin(0.3)
        }
    }
    let scrolled = drags.filter { !$0.contains("other tops seen []") }
    row("T15p", scrolled.isEmpty,
        "\(scrolled.count) of \(drags.count) drags scrolled: " + (scrolled.isEmpty ? drags : scrolled).joined(separator: "; "))

    row("T14p", ordered && outside.isEmpty && answered > 0,
        notes.joined(separator: "; ") + " (text length \(length); want four offsets inside it, "
            + "both lefts equal, each left before each right, and every swept answer inside)")
} else {
    for id in ["T4p", "T5", "T7", "T10", "T14p", "T15p"] { row(id, false, "the editor did not open on \(package)") }
}

if let data = try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]),
    let text = String(data: data, encoding: .utf8)
{
    print(text)
}
exit(0)
