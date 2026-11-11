// Find in the Transcript tab (#434, spec §11 TX-37…TX-39) — the probe
// (`transcript_find_proof.py` builds and runs it). Compiled from `app/Sources`
// minus the app's `main.swift`, through `swift_build.py` with `-D
// FRAMEJOB_DEV_TOOLS`, with THIS file as `main.swift`; the app's
// `Compositor.metal` is built beside it (`space_key_proof.build_shader`).
//
//   transcript-find-probe <package> --fonts <folder>
//
// The package is `transcript_tab_proof.probe_package()`'s: media 20 (a silent
// WAV) under clip 3 (0–60 s) and clip 4 (70–130 s), both from source 0. Its
// editor window is the app's own and the words arrive through
// `TranscriptTabSource.preload`: 400 source words shown twice, tokens 0–399
// and 400–799 in two paragraphs, "Café" "Noir" at 20–21, "cafe" at 120 and
// "CAFÉ" at 250 (so 420–421, 520 and 650 too), "tail" at 399. Keys and clicks
// go through `NSWindow.sendEvent`; nothing is posted to the system but a
// click's own mouse-up. Prints one JSON object, {"rows": [{id, pass, detail}]}.
//   F1  `TranscriptFind` alone: case, diacritics and width ignored; a phrase
//       inside a paragraph and its pieces; none across a paragraph break or a
//       collapse; never overlapping; spaces and the empty query find nothing;
//       `current` and `step` wrap; the three labels.
//   F2  Edit ▸ Find…'s validator is false on the Clip tab and true on
//       Transcript; the action shows the bar, its field typing; selection,
//       range, playhead and rebuilds unchanged.
//   F3  typed "cafe" with the playhead on token 300: six matches, the current
//       one the first at or after the highlight (token 420), in sight after
//       the scroll; nothing selected, no range, the playhead unmoved.
//   F4  Return steps and wraps with the field still typing; ⇧Return steps
//       back; keypad Enter is Return; nothing selected.
//   F5  Esc in the field: the bar and its marks gone and the transcript's
//       text first responder (it was as the bar opened); J, L and Space then
//       drive playback and ← selects a word. Opened from the content view,
//       Esc returns the keys there.
//   F6  with the bar open, a click on a word selects it, makes the text first
//       responder and leaves the bar and its matches; Esc clears the
//       selection; the next Esc closes the bar.
//   F7  a rebuild with source word 5 removed, the current match (token 520's)
//       scrolled out of sight: the matches are recomputed, the current one is
//       on the same word, and nothing scrolled it into sight.
//   F8  playing with the bar open, a far playhead move does not scroll;
//       closed, it does.
//   F9  the field typing, the Clip tab picked: the bar closed and no editable
//       text first responder; back on Transcript the bar is closed with its
//       text kept, and opening it searches that text again.
//   F10 a bare view with 27,000 words in 900 paragraphs and a match in every
//       word: drawing lays out no more fragments than before the find (+4);
//       the last match, measured first where an estimate puts it, is inside
//       the visible rect once revealed.
//   F11 `cacheDisplay` with and without the find: a match's pixels differ,
//       the current match's differ from another match's of the same word, and
//       a line with no match is identical.
//   F12 the field typing, a press on the bar's Next: the field still typing
//       and the current match one on; a press on Done closes the bar.
//   F13 the transcript's text first responder (no bar), the Clip tab picked:
//       the content view is first responder and L plays forward.
//   F14 `scrollToToken` (TX-20's click on a clip, #558) on a fresh bare view of
//       the same 27,000 words, the token measured first where an estimate puts
//       it: (a) token 18,000 is at the visible top and is the top visible
//       token; (b) the last token is in sight with the view's bottom at the
//       visible bottom, at the height every paragraph laid out gives; (c) a
//       paragraph's first token less than a viewport from the end is at the
//       top or as (b); and in each the place does not move when the rest is
//       laid out. Its detail also reads the scroller's knob. (d) the follow
//       (`setHighlight`) to token 18,000 puts it a third from the top, and
//       the next word's tick scrolls nothing.
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
    _ text: String, _ start: Double, _ end: Double, clip: UInt32 = 3, track: UInt32 = 1
) -> TimelineTranscript.Word {
    TimelineTranscript.Word(
        text: text, start: Ticks(start * Double(SEC)), end: Ticks(end * Double(SEC)), clip: clip,
        track: track, media: 20, engine: .apple, filler: false, speaker: nil, editable: true,
        why: nil,
        id: TimelineTranscript.Identity(
            nestPath: [], media: 20, source: Ticks(start * Double(SEC)), k: 0))
}

func key(
    _ code: UInt16, _ characters: String, window: NSWindow, flags: NSEvent.ModifierFlags = []
) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
}

func firsts(_ matches: [TranscriptFind.Match]) -> [Int] { matches.map(\.tokens.lowerBound) }

// MARK: - F1 the search alone

do {
    let texts = ["Café", "noir", "then", "CAFE", "Noirish", "aaa", "x"]
    var words = texts.enumerated().map { word($1, Double($0) * 0.3, Double($0) * 0.3 + 0.2) }
    words.append(word("noir", 2.4, 2.6, track: 2))
    words.append(word("end", 2.7, 2.9, track: 2))
    let model = TranscriptTokens.build(words, pauses: [:])
    let index = TranscriptFind.Index(model: model)
    let cafe = index.matches("cafe")
    let wide = index.matches("ｃａｆｅ")
    let phrase = index.matches("café noir")
    let across = index.matches("x noir")
    let within = index.matches("noir then")
    let collapsed = TranscriptFind.Index(
        model: TranscriptTokens.build(words, pauses: [:], struck: [], collapsed: [2: 1])
    ).matches("noir then")
    let overlap = index.matches("aa")
    let part = index.matches("fé n")
    let noir = index.matches("noir")
    let wantPiece = [
        TranscriptFind.Piece(token: 0, range: NSRange(location: 2, length: 2)),
        TranscriptFind.Piece(token: 1, range: NSRange(location: 0, length: 1)),
    ]
    let search = firsts(cafe) == [0, 3] && firsts(wide) == [0, 3]
        && phrase.map(\.tokens) == [0...1, 3...4] && across.isEmpty && within.map(\.tokens) == [1...2]
        && collapsed.isEmpty && overlap.count == 1
        && overlap.first?.pieces == [TranscriptFind.Piece(token: 5, range: NSRange(location: 0, length: 2))]
        && part.first?.pieces == wantPiece && index.matches(" ").isEmpty && index.matches("").isEmpty
        && model.paragraphs.count == 2 && firsts(noir) == [1, 4, 7]
    let current = TranscriptFind.current(in: noir, atOrAfter: 2) == 1
        && TranscriptFind.current(in: noir, atOrAfter: 8) == 0
        && TranscriptFind.current(in: [], atOrAfter: 0) == nil
    let step = TranscriptFind.step(2, by: 1, count: 3) == 0
        && TranscriptFind.step(0, by: -1, count: 3) == 2
        && TranscriptFind.step(nil, by: -1, count: 3) == 2
        && TranscriptFind.step(nil, by: 1, count: 0) == nil
    let labels = [
        TranscriptFind.label(query: "", current: nil, count: 0),
        TranscriptFind.label(query: "q", current: nil, count: 0),
        TranscriptFind.label(query: "q", current: 2, count: 12),
    ]
    row("F1", search && current && step && labels == ["", "No matches", "3 of 12"],
        "cafe \(firsts(cafe)) (want [0, 3]); full-width \(firsts(wide)); “café noir” "
            + "\(phrase.map(\.tokens)) (want 0...1, 3...4); across the paragraph break "
            + "\(across.count) (want 0); “noir then” \(within.count), collapsed \(collapsed.count) "
            + "(want 1, 0); “aa” in aaa \(overlap.count) (want 1); “fé n” pieces "
            + "\(String(describing: part.first?.pieces)); spaces \(index.matches(" ").count); "
            + "current \(current); step \(step); labels \(labels)")
}

// MARK: - F10 27,000 words, a match in every one

/// A bare `TranscriptView` in a 304 × 600 scroll view showing 27,000 words in
/// 900 paragraphs, drawn nowhere yet. F10 and each of F14's targets take a
/// fresh one: once a reveal has laid a view out, nothing in it is an estimate.
func longView() -> (window: NSWindow, view: TranscriptView, model: TranscriptTokens) {
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
    var words: [TimelineTranscript.Word] = []
    words.reserveCapacity(27_000)
    for paragraph in 0..<900 {
        for n in 0..<30 {
            let at = Double(paragraph) * 4 + Double(n) * 0.08
            words.append(word("w\(paragraph)x\(n)", at, at + 0.06, clip: UInt32(100 + paragraph)))
        }
    }
    let model = TranscriptTokens.build(words, pauses: [:])
    view.show(model, fps: Fps(num: 30, den: 1), timecodeFrames: true)
    spin(0.2)
    return (window, view, model)
}

do {
    let (window, view, model) = longView()
    func laidOut() -> Int {
        var count = 0
        view.layoutManager.enumerateTextLayoutFragments(
            from: view.layoutManager.documentRange.location, options: []
        ) { fragment in
            if fragment.state == .layoutAvailable { count += 1 }
            return true
        }
        return count
    }
    func paint() {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.visibleRect) else { return }
        view.cacheDisplay(in: view.visibleRect, to: bitmap)
    }
    paint()
    let before = laidOut()
    let matches = TranscriptFind.Index(model: model).matches("w")
    view.setFind(matches, current: 0)
    paint()
    let after = laidOut()
    view.setFind(matches, current: matches.count - 1)
    let estimate = view.findCurrentRect?.minY ?? -1
    let began = Date()
    view.revealFind()
    let took = Date().timeIntervalSince(began)
    spin(0.1)
    let rect = view.findCurrentRect ?? .zero
    let shown = view.visibleRect
    let inSight = rect.height > 0 && rect.minY >= shown.minY && rect.maxY <= shown.maxY
    row("F10", model.paragraphs.count == 900 && matches.count == 27_000 && before > 0
            && after <= before + 4 && inSight && view.findCurrentVisible,
        "\(model.paragraphs.count) paragraphs, \(matches.count) matches (want 900, 27000); "
            + "fragments laid out \(before) before the find, \(after) after its draw (want ≤ "
            + "\(before + 4)); the last match, estimated at \(estimate), revealed in "
            + "\(String(format: "%.3f", took)) s at \(rect.minY)…\(rect.maxY) in visible "
            + "\(shown.minY)…\(shown.maxY): \(inSight)")
    window.orderOut(nil)
}

// MARK: - F14 a click-to-clip scroll in 27,000 words (#558)

do {
    /// The view's height with every paragraph laid out.
    func finalHeight(_ view: TranscriptView) -> CGFloat {
        view.layoutManager.ensureLayout(for: view.layoutManager.documentRange)
        view.layoutViewport()
        return view.frame.height
    }
    func f(_ value: CGFloat) -> String { String(format: "%.1f", value) }
    var pass = true
    var detail = ""
    // (a) far from the end, (b) the last word, (c) a paragraph's first word less
    // than a viewport from the end (the text below it is an estimate until the
    // scroll's own viewport pass lays it out).
    for (name, token) in [("a", 18_000), ("b", 26_999), ("c", 26_910)] {
        let (window, view, _) = longView()
        let clipHeight = view.enclosingScrollView?.contentView.bounds.height ?? 0
        let heightBefore = view.frame.height
        let estimate = view.rects(forToken: token).first?.minY ?? -1
        let began = Date()
        view.scrollToToken(token)
        let took = Date().timeIntervalSince(began)
        spin(0.1)
        let rect = view.rects(forToken: token).first ?? .zero
        let shown = view.visibleRect
        let top = view.topVisibleToken()
        let heightAfter = view.frame.height
        let knob = view.enclosingScrollView?.verticalScroller?.doubleValue ?? -1
        let knobWant = Double(shown.minY / max(heightAfter - clipHeight, 1))
        let final = finalHeight(view)
        let after = view.rects(forToken: token).first ?? .zero
        let atTop = rect.height > 0 && abs(rect.minY - 4 - shown.minY) <= 0.5
        let inSight = rect.height > 0 && rect.minY >= shown.minY && rect.maxY <= shown.maxY
        let atBottom = abs(shown.maxY - heightAfter) <= 0.5 && abs(heightAfter - final) <= 0.5
        // A place that a later layout would move was an estimate.
        let settled = abs(after.minY - rect.minY) <= 0.5
        let ok: Bool
        switch name {
        case "a": ok = atTop && top == token && settled
        case "b": ok = inSight && atBottom && settled
        default: ok = (atTop || (inSight && atBottom)) && settled
        }
        pass = pass && ok
        detail += "(\(name)) token \(token): estimate \(f(estimate)), scrolled in "
            + "\(String(format: "%.3f", took)) s to \(f(rect.minY)) (\(f(after.minY)) all laid "
            + "out), visible \(f(shown.minY))…\(f(shown.maxY)), top token \(top ?? -1), height "
            + "\(f(heightBefore)) → \(f(heightAfter)) of \(f(final)), top \(atTop) sight "
            + "\(inSight) bottom \(atBottom), knob \(String(format: "%.4f", knob)) (computed "
            + "\(String(format: "%.4f", knobWant))): \(ok). "
        window.orderOut(nil)
    }
    // (d) the follow after a far jump: one tick, then one more on the next word.
    do {
        let (window, view, _) = longView()
        let estimate = view.rects(forToken: 18_000).first?.minY ?? -1
        let began = Date()
        view.setHighlight(18_000, follow: true)
        let took = Date().timeIntervalSince(began)
        spin(0.1)
        let rect = view.rects(forToken: 18_000).first ?? .zero
        let shown = view.visibleRect
        let third = rect.height > 0 && abs(rect.minY - shown.height / 3 - shown.minY) <= 0.5
        let again = Date()
        view.setHighlight(18_001, follow: true)
        let tick = Date().timeIntervalSince(again)
        spin(0.05)
        let still = abs(view.visibleRect.minY - shown.minY) <= 0.5
        _ = finalHeight(view)
        let after = view.rects(forToken: 18_000).first ?? .zero
        let ok = third && still && abs(after.minY - rect.minY) <= 0.5
        pass = pass && ok
        detail += "(d) the follow to token 18000: estimate \(f(estimate)), followed in "
            + "\(String(format: "%.3f", took)) s to \(f(rect.minY)) (\(f(after.minY)) all laid "
            + "out), visible \(f(shown.minY))…\(f(shown.maxY)), a third from the top \(third); "
            + "the next word's tick \(String(format: "%.4f", tick)) s, scrolled nothing "
            + "\(still): \(ok)."
        window.orderOut(nil)
    }
    row("F14", pass, detail)
}

// MARK: - F11 the marks' pixels

do {
    let window = NSWindow(
        contentRect: NSRect(x: -20_000, y: 0, width: 304, height: 300), styleMask: [.titled],
        backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 304, height: 300))
    let view = TranscriptView(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: 300))
    view.autoresizingMask = [.width]
    scroll.documentView = view
    window.contentView = scroll
    window.orderFrontRegardless()
    let texts = ["alpha", "one", "two", "alpha", "three"]
    let model = TranscriptTokens.build(
        texts.enumerated().map { word($1, Double($0) * 0.3, Double($0) * 0.3 + 0.2) }, pauses: [:])
    view.show(model, fps: Fps(num: 30, den: 1), timecodeFrames: true)
    spin(0.2)
    func paint() -> NSBitmapImageRep? {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }
    /// The colours of `rect` (view points, flipped) in `bitmap`, row by row.
    func pixels(_ bitmap: NSBitmapImageRep, _ rect: CGRect) -> [UInt32] {
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        var out: [UInt32] = []
        let x0 = Int((rect.minX * scale).rounded(.up))
        let x1 = Int((rect.maxX * scale).rounded(.down))
        let y0 = Int((rect.minY * scale).rounded(.up))
        let y1 = Int((rect.maxY * scale).rounded(.down))
        guard x0 < x1, y0 < y1 else { return out }
        for y in y0..<y1 {
            for x in x0..<x1 {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let r = UInt32((color.redComponent * 255).rounded())
                let g = UInt32((color.greenComponent * 255).rounded())
                let b = UInt32((color.blueComponent * 255).rounded())
                out.append(r << 16 | g << 8 | b)
            }
        }
        return out
    }
    let plain = paint()
    let matches = TranscriptFind.Index(model: model).matches("alpha")
    view.setFind(matches, current: 0)
    let found = paint()
    let first = view.rects(forToken: 0).first ?? .zero
    let second = view.rects(forToken: 3).first ?? .zero
    let timecode = view.rects(for: view.timecodeRanges.first ?? NSRange(location: 0, length: 0)).first ?? .zero
    var detail = "no bitmap"
    var pass = false
    if let plain, let found, first.width > 0, second.width > 0, timecode.width > 0 {
        let marked = pixels(plain, first) != pixels(found, first)
        // The two marks' fills, read just inside each rect's left edge, clear of the glyphs.
        let edge = { (r: CGRect) in CGRect(x: r.minX - 1, y: r.minY + 1, width: 1, height: r.height - 2) }
        let current = pixels(found, edge(first))
        let other = pixels(found, edge(second))
        let strengths = !current.isEmpty && !other.isEmpty && current != other
            && pixels(plain, edge(second)) != other
        let untouched = pixels(plain, timecode) == pixels(found, timecode) && !pixels(plain, timecode).isEmpty
        pass = matches.count == 2 && marked && strengths && untouched
        detail = "\(matches.count) matches (want 2); the first match's pixels changed \(marked); the "
            + "current mark differs from the other and the other from no mark \(strengths); the "
            + "timecode line identical \(untouched)"
    }
    row("F11", pass, detail)
    window.orderOut(nil)
}

// MARK: - The editor rows

let special: [Int: String] = [20: "Café", 21: "Noir", 120: "cafe", 250: "CAFÉ", 399: "tail"]
func heard(without dropped: Int? = nil) -> TimelineTranscript.MediaWords {
    TimelineTranscript.MediaWords(
        media: 20, engine: .apple, language: "en-US", fillersReported: false,
        words: (0..<400).filter { $0 != dropped }.map { (n: Int) -> TimelineTranscript.SourceWord in
            let at = Double(n) * 0.15
            return TimelineTranscript.SourceWord(
                text: special[n] ?? "w\(n)", source: Ticks(at * Double(SEC)),
                sourceEnd: Ticks((at + 0.1) * Double(SEC)), speaker: nil)
        })
}

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
    pane.source.preload([20: heard()], pauses: [20: []])
    _ = until(5) { pane.source.settled }
    spin(0.3)
    return (document, editor, window, pane)
}

if let (document, editor, window, pane) = openEditor(), let inspector = editor.inspector {
    let view = pane.transcriptView
    let band = pane.findBand
    let root = editor.view
    let model = { pane.source.model }
    func send(_ event: NSEvent?) { if let event { window.sendEvent(event) } }
    func typing() -> Bool { pane.findFieldHasKeys(in: window) }
    func who() -> String {
        let first = window.firstResponder
        if first === view { return "the transcript" }
        if first === root { return "the content view" }
        if typing() { return "the find field" }
        return String(describing: first.map { type(of: $0) })
    }
    /// Replaces the field's text as typing does.
    func typeText(_ text: String) -> Bool {
        guard let editor = window.firstResponder as? NSTextView else { return false }
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
        spin(0.1)
        return true
    }
    func click(at point: NSPoint) {
        if let release = NSEvent.mouseEvent(
            with: .leftMouseUp, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
            pressure: 0)
        {
            NSApp.postEvent(release, atStart: false)
        }
        guard let down = NSEvent.mouseEvent(
            with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
            pressure: 1)
        else { return }
        // K-4's rule runs in `sendEvent` before dispatch; this window is never
        // key (the probe's app is `.prohibited`), so AppKit does not dispatch
        // the press to a view and the hit view is handed it here. F12 holds
        // that to ONE delivery: Next must step by exactly one.
        send(down)
        if let content = window.contentView,
            let hit = content.hitTest(content.superview?.convert(point, from: nil) ?? point)
        {
            hit.mouseDown(with: down)
        }
        spin(0.3)
    }
    func center(of target: NSView) -> NSPoint {
        target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil)
    }
    let returnKey = { (flags: NSEvent.ModifierFlags) in key(36, "\r", window: window, flags: flags) }
    let escape = { key(53, "\u{1b}", window: window) }
    func current() -> Int? { pane.find.current }
    func matchFirsts() -> [Int] { firsts(pane.find.matches) }
    let wanted = [20, 120, 250, 420, 520, 650]

    // F2 the validator and the open.
    let item = NSMenuItem(
        title: "Find…", action: #selector(EditorViewController.findInTranscript(_:)), keyEquivalent: "f")
    inspector.select(.clip)
    spin(0.2)
    let onClip = editor.validateUserInterfaceItem(item)
    inspector.select(.transcript)
    pane.source.preload([20: heard()], pauses: [20: []])
    _ = until(5) { pane.source.settled }
    spin(0.3)
    let onTranscript = editor.validateUserInterfaceItem(item)
    window.makeFirstResponder(view)
    let rebuilds = pane.source.rebuilds
    let playhead = document.playhead
    editor.findInTranscript(nil)
    spin(0.2)
    let opened = pane.isFindOpen && !band.isHidden && band.frame.height > 20
    let typingAfterOpen = typing()
    row("F2", !onClip && onTranscript && opened && typingAfterOpen && view.selection == nil
            && document.inOutRange == nil && document.playhead == playhead
            && pane.source.rebuilds == rebuilds && model().tokens.count == 800,
        "the validator on Clip \(onClip), on Transcript \(onTranscript) (want false, true); bar "
            + "open \(opened), height \(band.frame.height); first responder \(who()); selection "
            + "\(String(describing: view.selection)); range \(String(describing: document.inOutRange)); "
            + "playhead \(document.playhead) (was \(playhead)); rebuilds \(pane.source.rebuilds) "
            + "(was \(rebuilds)); \(model().tokens.count) tokens")
    pane.closeFind()

    // F3 typing, from the highlighted word.
    editor.setPlayhead(model().tokens[300].word.start)
    spin(0.3)
    let lit = view.highlight
    view.scroll(to: 0)
    window.makeFirstResponder(view)
    editor.findInTranscript(nil)
    spin(0.1)
    let typed = typeText("cafe")
    let at3 = current()
    let rect3 = view.findCurrentRect ?? .zero
    let shown3 = view.visibleRect
    let inSight3 = rect3.height > 0 && rect3.minY >= shown3.minY && rect3.maxY <= shown3.maxY
    let held = document.playhead
    row("F3", typed && lit == 300 && matchFirsts() == wanted && at3 == 3 && inSight3
            && shown3.minY > 0 && band.countText == "4 of 6" && view.selection == nil
            && document.inOutRange == nil && held == model().tokens[300].word.start,
        "typed \(typed); highlight \(String(describing: lit)); matches \(matchFirsts()) (want "
            + "\(wanted)); current \(String(describing: at3)) (want 3, token 420); its rect "
            + "\(rect3.minY)…\(rect3.maxY) in visible \(shown3.minY)…\(shown3.maxY); count "
            + "“\(band.countText)”; selection \(String(describing: view.selection)); range "
            + "\(String(describing: document.inOutRange)); playhead \(held)")

    // F4 Return, ⇧Return, keypad Enter.
    var steps: [Int?] = []
    var kept = true
    for flags in [NSEvent.ModifierFlags(), [], [], .shift] {
        send(returnKey(flags))
        spin(0.1)
        steps.append(current())
        kept = kept && typing()
    }
    send(key(76, "\u{3}", window: window, flags: [.numericPad]))
    spin(0.1)
    steps.append(current())
    kept = kept && typing()
    row("F4", steps == [4, 5, 0, 5, 0] && kept && view.selection == nil && pane.isFindOpen
            && band.countText == "1 of 6" && view.findCurrentVisible,
        "Return ×3, ⇧Return, keypad Enter: current \(steps) (want 4, 5, 0, 5, 0); the field "
            + "kept the keys \(kept) (first responder \(who())); selection "
            + "\(String(describing: view.selection)); count “\(band.countText)”; in sight "
            + "\(view.findCurrentVisible)")

    // F5 Esc, and the keys after it.
    if !typing() { window.makeFirstResponder(band.field) }
    send(escape())
    spin(0.2)
    let closed = !pane.isFindOpen && band.isHidden && view.findMatches.isEmpty
    let backToText = window.firstResponder === view
    let after5 = who()
    editor.setPlayhead(20 * SEC)
    spin(0.3)
    send(key(49, " ", window: window))
    let played = until(2) { editor.playback.isPlaying }
    send(key(49, " ", window: window))
    let paused = until(2) { !editor.playback.isPlaying }
    send(key(38, "j", window: window))
    let back = until(2) { editor.playback.rate < 0 }
    send(key(40, "k", window: window))
    _ = until(2) { !editor.playback.isPlaying }
    send(key(37, "l", window: window))
    let forward = until(2) { editor.playback.rate > 0 }
    editor.playback.pause()
    spin(0.3)
    view.select(10...10)
    send(key(123, String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), window: window))
    spin(0.2)
    let arrowed = view.selection == 9...9
    view.select(nil)
    window.makeFirstResponder(root)
    editor.findInTranscript(nil)
    spin(0.1)
    let typingFromRoot = typing()
    send(escape())
    spin(0.2)
    let backToRoot = window.firstResponder === root && !pane.isFindOpen
    row("F5", closed && backToText && played && paused && back && forward && arrowed
            && typingFromRoot && backToRoot,
        "Esc: bar closed and unmarked \(closed), first responder \(after5) (want the "
            + "transcript); Space played \(played), paused \(paused); J back \(back); L forward "
            + "\(forward); ← selected the word before \(arrowed); opened from the content view "
            + "(typing \(typingFromRoot)), Esc returned the keys there \(backToRoot) (\(who()))")

    // F6 a click on a word with the bar open; two Escs.
    view.scroll(to: 0)
    window.makeFirstResponder(view)
    editor.findInTranscript(nil)
    spin(0.1)
    _ = typeText("cafe")
    var clock: TimeInterval = 1_000_000  // injected, so a click here never pauses F8's follow
    view.now = { clock }
    let target = (current().map { pane.find.matches[$0].tokens.lowerBound } ?? 0) + 1
    let wordRect = view.rects(forToken: target).first ?? .zero
    click(at: view.convert(NSPoint(x: wordRect.midX, y: wordRect.midY), to: nil))
    let selected = view.selection
    let clickedOpen = pane.isFindOpen && matchFirsts() == wanted && !band.isHidden
    let textFirst = window.firstResponder === view
    send(escape())
    spin(0.2)
    let cleared = view.selection == nil && pane.isFindOpen
    send(escape())
    spin(0.2)
    let closedBySecond = !pane.isFindOpen && window.firstResponder === view
    row("F6", target == 21 && selected?.contains(target) == true && clickedOpen && textFirst
            && cleared && closedBySecond,
        "clicked token \(target) at \(wordRect): selection \(String(describing: selected)); the "
            + "bar still open with its matches \(clickedOpen); first responder the transcript "
            + "\(textFirst); Esc cleared the selection and left the bar \(cleared); the next Esc "
            + "closed it \(closedBySecond)")

    // F7 a rebuild under the bar.
    editor.findInTranscript(nil)
    spin(0.1)
    _ = typeText("cafe")
    while let at = current(), at != 4 { pane.findStep(1) }
    let word7 = current().map { model().tokens[pane.find.matches[$0].tokens.lowerBound].word.id }
    view.scroll(to: 0)
    spin(0.1)
    let top7 = view.topVisibleToken().map { model().tokens[$0].word.id }
    let hiddenBefore = !view.findCurrentVisible
    let r7 = pane.source.rebuilds
    pane.source.preload([20: heard(without: 5)], pauses: [20: []])
    _ = until(5) { pane.source.rebuilds != r7 && pane.source.settled }
    spin(0.3)
    let wanted7 = [19, 119, 249, 418, 518, 648]
    let word7After = current().map { model().tokens[pane.find.matches[$0].tokens.lowerBound].word.id }
    let top7After = view.topVisibleToken().map { model().tokens[$0].word.id }
    row("F7", model().tokens.count == 798 && matchFirsts() == wanted7 && current() == 4
            && word7 != nil && word7After == word7 && view.findMatches.map(\.tokens.lowerBound) == wanted7
            && hiddenBefore && !view.findCurrentVisible && top7After == top7,
        "\(model().tokens.count) tokens after the rebuild (want 798); matches \(matchFirsts()) "
            + "(want \(wanted7)); current \(String(describing: current())) on the same word "
            + "\(word7After == word7); drawn \(view.findMatches.count); out of sight before "
            + "\(hiddenBefore) and after \(!view.findCurrentVisible); the top word unchanged "
            + "\(top7After == top7)")
    pane.closeFind()
    pane.source.preload([20: heard()], pauses: [20: []])
    _ = until(5) { pane.source.settled && pane.source.model.tokens.count == 800 }
    spin(0.3)

    // F8 the follow waits while the bar is open.
    clock += 100
    window.makeFirstResponder(view)
    editor.findInTranscript(nil)
    spin(0.1)
    _ = typeText("")
    view.scroll(to: 0)
    editor.setPlayhead(SEC)
    editor.playPause(nil)
    let playing8 = until(2) { editor.playback.isPlaying }
    let top8 = view.visibleRect.minY
    editor.setPlayhead(model().tokens[700].word.start)
    spin(0.4)
    let heldTop = view.visibleRect.minY
    let lit8 = view.highlight
    pane.closeFind()
    editor.setPlayhead(model().tokens[350].word.start)
    spin(0.4)
    let followedTop = view.visibleRect.minY
    let still8 = editor.playback.isPlaying
    editor.playback.pause()
    spin(0.3)
    row("F8", playing8 && still8 && heldTop == top8 && (lit8 ?? 0) >= 700 && followedTop != top8,
        "playing \(playing8) and still \(still8); bar open, the playhead to token 700 (highlight "
            + "\(String(describing: lit8))): top \(top8) → \(heldTop) (want unchanged); bar "
            + "closed, to token 350: top \(followedTop) (want moved)")

    // F13 leaving the tab with the text focused.
    window.makeFirstResponder(view)
    inspector.select(.clip)
    spin(0.3)
    let diagWho = who()
    send(key(37, "l", window: window))
    let diagForward = until(2) { editor.playback.rate > 0 }
    editor.playback.pause()
    spin(0.3)
    row("F13", diagWho == "the content view" && diagForward,
        "the transcript first responder, the Clip tab picked: first responder \(diagWho) (want "
            + "the content view); L then plays forward \(diagForward)")
    inspector.select(.transcript)
    pane.source.preload([20: heard()], pauses: [20: []])
    _ = until(5) { pane.source.settled && pane.source.model.tokens.count == 800 }
    spin(0.3)

    // F9 hiding the tab.
    view.scroll(to: 0)
    editor.findInTranscript(nil)
    spin(0.1)
    _ = typeText("cafe")
    let typing9 = typing()
    inspector.select(.clip)
    spin(0.3)
    let closed9 = !pane.isFindOpen
    let noText = TextFocus.typing(window.firstResponder) == nil
    let first9 = who()
    inspector.select(.transcript)
    pane.source.preload([20: heard()], pauses: [20: []])
    _ = until(5) { pane.source.settled && pane.source.model.tokens.count == 800 }
    spin(0.3)
    let stillClosed = !pane.isFindOpen && band.isHidden && band.query == "cafe"
    editor.findInTranscript(nil)
    spin(0.2)
    row("F9", typing9 && closed9 && noText && window.firstResponder != nil && first9 == "the content view"
            && stillClosed && matchFirsts() == wanted && typing(),
        "typing before \(typing9); the Clip tab picked: bar closed \(closed9), no editable text "
            + "first responder \(noText) (\(first9)); back on Transcript closed with “\(band.query)” "
            + "kept \(stillClosed); opened again: matches \(matchFirsts()) (want \(wanted)), typing "
            + "\(typing())")

    // F12 a press on the bar's own buttons.
    if !pane.isFindOpen { editor.findInTranscript(nil) }
    if !typing() { window.makeFirstResponder(band.field) }
    spin(0.1)
    let before12 = current()
    click(at: center(of: band.next))
    let after12 = current()
    let typing12 = typing()
    click(at: center(of: band.done))
    row("F12", before12 != nil && after12 == before12.map { ($0 + 1) % 6 } && typing12
            && !pane.isFindOpen,
        "a press on Next: current \(String(describing: before12)) → \(String(describing: after12)), "
            + "the field still typing \(typing12); a press on Done closed the bar \(!pane.isFindOpen)")
    document.close()
} else {
    for id in ["F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F12"] {
        row(id, false, "the editor did not open on \(package)")
    }
}

if let data = try? JSONSerialization.data(withJSONObject: ["rows": rows]),
    let text = String(data: data, encoding: .utf8)
{
    print(text)
}
exit(0)
